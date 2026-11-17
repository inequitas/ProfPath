-- ProfPath prices: auction prices from Auctionator / TSM / own scan, vendor prices, own AH scanner.
local _, ns = ...
local P = {}
ns.Prices = P

local FRESH = 6 * 3600   -- own scan younger than this beats addon prices
local STALE = 24 * 3600  -- older than this is flagged in the UI

-- Reagents sold by vendors in Classic (item IDs). Used only until a merchant visit confirms prices;
-- the merchant cache (ProfPathDB.vendor) always wins. Verify IDs on Wowhead when in doubt.
P.VENDOR_SEED = {
    2320, 2321, 4291, 8343, 14341,             -- threads
    3371, 3372, 8925, 18256,                   -- vials
    2880, 3466,                                -- fluxes
    4289, 2678, 2692, 3713,                    -- salt, spices
    2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290, -- bleach and dyes
    4470, 5140, 6217,                          -- simple wood, flash powder, copper rod
}
local seed = {}
for _, id in ipairs(P.VENDOR_SEED) do seed[id] = true end

local function db() return ProfPathDB end

-- ---------- AH unit price ----------

local function auctionator(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "ProfPath", itemID)
    if not ok or not price or price <= 0 then return nil end
    local age
    if api.GetAuctionAgeByItemID then
        local ok2, days = pcall(api.GetAuctionAgeByItemID, "ProfPath", itemID)
        if ok2 and days then age = days * 86400 end
    end
    return price, age
end

local function tsm(itemID)
    if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
    for _, src in ipairs({ "DBMinBuyout", "DBRecent", "DBMarket" }) do
        local ok, v = pcall(TSM_API.GetCustomPriceValue, src, "i:" .. itemID)
        if ok and v and v > 0 then return v end
    end
end

local function scanned(itemID)
    local e = db().prices[itemID]
    if not e or not e.unit then return nil end
    return e.unit, time() - e.t, e
end

-- Returns unit price, source name, age in seconds (nil if unknown).
function P.ahUnit(itemID)
    local u, age, e = scanned(itemID)
    if u and age < FRESH then return u, "scan", age, e end
    local a, aAge = auctionator(itemID)
    if a then return a, "Auctionator", aAge end
    local t = tsm(itemID)
    if t then return t, "TSM" end
    if u then return u, "scan", age, e end
end

-- Total AH cost to buy qty units, walking the scanned order book when there is one.
function P.ahTotal(itemID, qty)
    local unit, src, _, e = P.ahUnit(itemID)
    if not unit then return nil end
    if src ~= "scan" or not e.book or #e.book == 0 then return unit * qty end
    local left, total, last = qty, 0, unit
    for _, lot in ipairs(e.book) do
        local take = math.min(left, lot[2])
        total, left, last = total + take * lot[1], left - take, lot[1]
        if left <= 0 then return total end
    end
    return total + left * last * 1.25 -- not enough listed: assume a markup for the rest
end

function P.isStale(itemID)
    local _, _, age = P.ahUnit(itemID)
    return age and age > STALE
end

-- ---------- vendor ----------

function P.vendorBuy(itemID)
    local v = db().vendor[itemID]
    if v then return v end
    if seed[itemID] then
        local d = ns.Data.items[itemID]
        if d and d[1] > 0 then return d[1] end
    end
end

function P.vendorSell(itemID)
    local d = ns.Data.items[itemID]
    if d then return d[2] end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then return (select(11, getInfo(itemID))) end
end

-- ---------- own AH scanner (C_AuctionHouse) ----------

local AH = C_AuctionHouse
local queue, pending, pendingSince = {}, nil, 0
local scanFrame = CreateFrame("Frame")
P.scanning = false
-- Scan progress for the UI: done/total items, item being searched, waiting on the server throttle.
P.progress = { done = 0, total = 0, found = 0, timeouts = 0, current = nil, waiting = false }
P.sent, P.got = {}, {}
P.version = 0 -- bumped on every stored price; lets callers cache work between changes

local function report()
    if ns.UI and ns.UI.scanProgress then ns.UI.scanProgress(P.progress, P.scanning) end
end

local function save(itemID, book)
    table.sort(book, function(a, b) return a[1] < b[1] end)
    local trimmed = {}
    for i = 1, math.min(#book, 40) do trimmed[i] = book[i] end
    if book[1] then
        db().prices[itemID] = { unit = book[1][1], t = time(), book = trimmed }
        P.version = P.version + 1
    else
        db().prices[itemID] = { t = time(), none = true }
    end
end

-- A later, fuller reply for an item already counted: update its price, not the progress.
local function refresh(itemID, book)
    local had = db().prices[itemID] and db().prices[itemID].unit
    if #book == 0 then return end
    save(itemID, book)
    if not had then P.progress.found = P.progress.found + 1; report() end
end

local function store(itemID, book)
    table.sort(book, function(a, b) return a[1] < b[1] end)
    local trimmed = {}
    for i = 1, math.min(#book, 40) do trimmed[i] = book[i] end
    if book[1] then
        db().prices[itemID] = { unit = book[1][1], t = time(), book = trimmed }
        P.version = P.version + 1
        P.progress.found = P.progress.found + 1
    else
        db().prices[itemID] = { t = time(), none = true } -- searched, nothing listed
    end
    P.progress.done = P.progress.done + 1
    report()
end

local function finish(stopped)
    P.scanning = false
    scanFrame:SetScript("OnUpdate", nil)
    local p = P.progress
    local secs = p.started and math.floor(GetTime() - p.started) or 0
    ns.chat(("Scan %s in %ds: %d of %d items have listings, %d got no reply, %d skipped as too expensive.")
        :format(stopped and "stopped" or "finished", secs, p.found, p.done - (p.skipped or 0), p.timeouts or 0,
            p.skipped or 0))
    report()
    if ns.recalc then ns.recalc() end
end

function P.stopScan()
    if not P.scanning then return end
    if P.snapshotting then return P.stopSnapshot() end
    queue, pending = {}, nil
    finish(true)
end

-- Throttle handling. When the server throttles, SendSearchQuery is silently ignored: no
-- AUCTION_HOUSE_THROTTLED_MESSAGE_SENT follows. We then retry the same item after a growing pause
-- (backoff) and widen the gap between all later requests (spacing), narrowing it again on success.
local confirmed, backoff, spacing, nextAllowed, retries = false, 0, 0, 0, {}
-- Observed: once throttled, the server allows roughly one search every 5-10 s, so waiting longer
-- than ~8 s between tries only wastes time.
local MAX_RETRIES, MAX_BACKOFF, MAX_SPACING = 5, 8, 3

-- Called on every accepted reply: the server is answering, so ease off the brakes.
local function answered()
    backoff = 0
    spacing = math.max(spacing - 0.1, 0)
end

local function sendNext()
    if pending or not P.scanning or P.snapshotting then return end
    -- Drop items no competitive recipe needs any more (decided with the prices found so far).
    while queue[1] and P.needed and not P.needed(queue[1]) do
        table.remove(queue, 1)
        P.progress.skipped = (P.progress.skipped or 0) + 1
        P.progress.done = P.progress.done + 1
        report()
    end
    local itemID = queue[1]
    if not itemID then return finish() end
    local now = GetTime()
    if now < nextAllowed then
        local s = math.ceil(nextAllowed - now)
        if backoff > 0 and s ~= P.progress.retryIn then P.progress.retryIn = s; report() end
        return
    end
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
        if not P.progress.waiting then P.progress.waiting = true; report() end
        return
    end
    table.remove(queue, 1)
    P.progress.waiting, P.progress.retryIn, P.progress.current = false, nil, itemID
    report()
    pending, pendingSince, confirmed = itemID, now, false
    nextAllowed = now + spacing
    P.sent[itemID] = pendingSince
    local key = AH.MakeItemKey(itemID)
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    local ok, err = pcall(AH.SendSearchQuery, key, sorts, true)
    if not ok then
        ns.chat("Search failed for item " .. itemID .. ": " .. tostring(err))
        pending = nil
    end
end

-- Scan log (last 80 entries) saved to ProfPathDB.scanLog for diagnosing slow scans.
local function log(event, itemID, extra)
    local L = db().scanLog
    local sent = itemID and P.sent[itemID]
    L[#L + 1] = { e = event, id = itemID, ms = sent and math.floor((GetTime() - sent) * 1000) or nil,
        pending = pending, x = extra }
    while #L > 80 do table.remove(L, 1) end
end

-- Results are accepted for any item sent in this scan, so a late reply still counts.
local function onCommodity(itemID)
    if not itemID or not P.sent[itemID] then return end
    local book = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r then book[#book + 1] = { r.unitPrice, r.quantity } end
        if not db().scanSample then db().scanSample = { kind = "commodity", raw = r } end
    end
    if P.got[itemID] then return refresh(itemID, book) end -- fuller second reply
    P.got[itemID] = true
    answered()
    if itemID == pending then pending = nil else -- late reply for a timed-out item
        P.progress.done, P.progress.timeouts = P.progress.done - 1, P.progress.timeouts - 1
    end
    store(itemID, book)
end

local function onItem(itemKey)
    local itemID = itemKey and itemKey.itemID
    if not itemID or not P.sent[itemID] then return end
    local book = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount then
            -- Assumes buyoutAmount is per unit (retail behaviour). Check ProfPathDB.itemScanSample.
            book[#book + 1] = { r.buyoutAmount, r.quantity or 1 }
        end
        if not db().itemScanSample then db().itemScanSample = r end
    end
    if P.got[itemID] then return refresh(itemID, book) end -- fuller second reply
    P.got[itemID] = true
    answered()
    if itemID == pending then pending = nil else -- late reply for a timed-out item
        P.progress.done, P.progress.timeouts = P.progress.done - 1, P.progress.timeouts - 1
    end
    store(itemID, book)
end

local EVENTS = {
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_CLOSED",
}
for _, e in ipairs(EVENTS) do pcall(scanFrame.RegisterEvent, scanFrame, e) end

scanFrame:SetScript("OnEvent", function(_, event, arg)
    local isCommodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED"
    local isItem = event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED"
    -- After the scan ends, still accept follow-up replies for items it sent.
    if not P.scanning and not (isCommodity or isItem) then return end
    local id = type(arg) == "table" and arg.itemID or (type(arg) == "number" and arg) or pending
    if P.scanning then log(event, id) end
    if isCommodity then
        onCommodity(arg)
    elseif isItem then
        onItem(arg)
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
        confirmed = true
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" and pending then
        table.insert(queue, 1, pending) -- the server dropped our request: send it again
        P.sent[pending], pending = nil, nil
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if P.snapshotting then P.stopSnapshot(); return end
        ns.chat("Auction house closed; " .. #queue .. " items were not scanned.")
        P.stopScan(); return
    end
    sendNext()
end)

local NOT_SENT_AFTER, TIMEOUT = 1, 5

-- Give up on an item: counted as "no reply", not as "nothing listed", so the next scan retries it.
local function giveUp(itemID, why)
    log(why, itemID)
    P.progress.timeouts = (P.progress.timeouts or 0) + 1
    P.progress.done = P.progress.done + 1
    if pending == itemID then pending = nil end
    report()
end

local tick
function P.__tick() return tick() end -- for tests
function tick()
    if pending then
        local age = GetTime() - pendingSince
        if not confirmed and age > NOT_SENT_AFTER then
            local id = pending
            pending, P.sent[id] = nil, nil
            retries[id] = (retries[id] or 0) + 1
            backoff = math.min(backoff > 0 and backoff * 2 or 1, MAX_BACKOFF)
            spacing = math.min(spacing + 0.5, MAX_SPACING)
            nextAllowed = GetTime() + backoff
            log("NOT_SENT", id, backoff)
            if retries[id] > MAX_RETRIES then giveUp(id, "GAVE_UP") else table.insert(queue, 1, id) end
        elseif age > TIMEOUT then
            giveUp(pending, "TIMEOUT")
        end
    end
    sendNext()
end

function P.scan(itemIDs, needed)
    if not (AH and AH.SendSearchQuery and AH.MakeItemKey) then
        ns.chat("This client has no C_AuctionHouse search API; use Auctionator or TSM for prices.")
        return
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.chat("Open the auction house first.")
        return
    end
    if P.scanning then return end
    queue = {}
    local now = time()
    for _, id in ipairs(itemIDs) do
        local e = db().prices[id]
        local recent = e and now - e.t < 3600
        if not P.vendorBuy(id) and not recent then queue[#queue + 1] = id end
    end
    ns.chat(("Scanning %d items. Keep the auction house open."):format(#queue))
    P.progress = { done = 0, total = #queue, found = 0, timeouts = 0, skipped = 0, current = nil, waiting = false,
        started = GetTime() }
    P.needed = needed
    P.sent, P.got = {}, {}
    confirmed, backoff, spacing, nextAllowed, retries = false, 0, 0, 0, {}
    db().scanLog = {}
    P.scanning, pending = true, nil
    report()
    local acc = 0
    scanFrame:SetScript("OnUpdate", function(_, elapsed) -- 10 checks a second is plenty
        acc = acc + elapsed
        if acc >= 0.1 then acc = 0; tick() end
    end)
    sendNext()
end

-- ---------- full snapshot (C_AuctionHouse.ReplicateItems) ----------
-- One request returns every auction on the realm. Allowed about once per 15 minutes. Results are
-- read in chunks over several frames so the game does not freeze, and only items some recipe uses
-- (reagents, products, recipe items in the data file) are kept.

local SNAPSHOT_COOLDOWN, SNAPSHOT_WAIT, CHUNK = 15 * 60, 300, 1500
local snapFrame = CreateFrame("Frame")
P.snapshotting = false

function P.snapshotReadyIn()
    local last = db() and db().lastSnapshot
    if not last then return 0 end
    return math.max(0, last + SNAPSHOT_COOLDOWN - time())
end

local function endSnapshot(msg)
    snapFrame:SetScript("OnUpdate", nil)
    snapFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    P.snapshotting, P.scanning = false, false
    P.progress.label = nil
    ns.chat(msg)
    report()
    if ns.recalc then ns.recalc() end
end

function P.stopSnapshot()
    if P.snapshotting then endSnapshot("Full scan stopped.") end
end

local function readSnapshot()
    local n = AH.GetNumReplicateItems and AH.GetNumReplicateItems() or 0
    if n == 0 then
        return endSnapshot("The server sent an empty snapshot. Use Scan AH (item by item) instead.")
    end
    local wanted, books, i = ns.Data.items, {}, 0
    P.progress = { done = 0, total = n, found = 0, timeouts = 0, skipped = 0, started = GetTime(),
        label = "Reading snapshot" }
    report()
    snapFrame:SetScript("OnUpdate", function()
        local stop = math.min(i + CHUNK, n)
        for idx = i, stop - 1 do -- indices are 0-based
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(idx)
            if itemID and wanted[itemID] and buyout and buyout > 0 and count and count > 0 then
                local b = books[itemID]
                if not b then b = {}; books[itemID] = b end
                b[#b + 1] = { buyout / count, count } -- buyout is for the whole stack
            end
        end
        i = stop
        P.progress.done = i
        report()
        if i >= n then
            snapFrame:SetScript("OnUpdate", nil)
            local c = 0
            for id, b in pairs(books) do save(id, b); c = c + 1 end
            P.progress.found = c
            endSnapshot(("Full scan done: %d auctions read, prices for %d crafting items."):format(n, c))
        end
    end)
end

function P.fullScan()
    if not (AH and AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then
        return ns.chat("This client has no full-scan API; use Scan AH.")
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return ns.chat("Open the auction house first.") end
    if P.scanning then return ns.chat("A scan is already running.") end
    local wait = P.snapshotReadyIn()
    if wait > 0 then
        return ns.chat(("Full scan is available again in %d min %02d s (server limit).")
            :format(math.floor(wait / 60), math.floor(wait % 60)))
    end
    db().lastSnapshot = time()
    P.scanning, P.snapshotting = true, true
    P.progress = { done = 0, total = 0, found = 0, timeouts = 0, skipped = 0, started = GetTime(),
        label = "Waiting for the server's snapshot" }
    report()
    snapFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    snapFrame:SetScript("OnEvent", function()
        snapFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        readSnapshot()
    end)
    local acc = 0
    snapFrame:SetScript("OnUpdate", function(_, elapsed) -- keep the waiting timer on the bar moving
        acc = acc + elapsed
        if acc < 1 then return end
        acc = 0
        if GetTime() - P.progress.started > SNAPSHOT_WAIT then
            return endSnapshot("No snapshot after 5 minutes. Use Scan AH (item by item) instead.")
        end
        report()
    end)
    ns.chat("Full scan requested. This can take a minute; keep the auction house open.")
    AH.ReplicateItems()
end
