-- ProfPath core: saved variables, slash commands, API discovery (M0).
local addonName, ns = ...

local function chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffProfPath|r: " .. tostring(msg))
end
ns.chat = chat

-- Shallow-ish serializer for dumping unknown API return values into SavedVariables.
local function describe(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = type(v)
    if t ~= "table" then
        if t == "string" or t == "number" or t == "boolean" or t == "nil" then return v end
        return "<" .. t .. ">"
    end
    if seen[v] then return "<cycle>" end
    if depth >= 3 then return "<table>" end
    seen[v] = true
    local out, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 60 then out["<more>"] = true break end
        out[tostring(k)] = describe(val, depth + 1, seen)
    end
    return out
end

local function sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

-- /profpath api : list what this client exposes, saved to ProfPathDB.api.
local NAMESPACES = { "C_TradeSkillUI", "C_AuctionHouse", "C_Item", "C_Container",
    "C_Spell", "C_SpellBook", "C_ProfSpecs", "C_CraftingOrders", "C_MerchantFrame" }
local GLOBALS = { "GetProfessions", "GetProfessionInfo", "GetSkillLineInfo", "GetNumSkillLines",
    "GetItemInfo", "GetItemCount", "GetMerchantItemInfo", "QueryAuctionItems", "GetAuctionItemInfo",
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetNumCrafts", "GetBuildInfo",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillLine",
    "GetMerchantNumItems", "GetMerchantItemID", "GetCoinTextureString", "debugprofilestop" }

local function dumpApi()
    local api = { build = { GetBuildInfo() }, namespaces = {}, cNamespaces = {}, globals = {}, enums = {} }
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 2) == "C_" and type(v) == "table" then
            api.cNamespaces[#api.cNamespaces + 1] = k
        end
    end
    table.sort(api.cNamespaces)
    for _, name in ipairs(NAMESPACES) do
        local tbl = _G[name]
        api.namespaces[name] = type(tbl) == "table" and sortedKeys(tbl) or false
    end
    for _, name in ipairs(GLOBALS) do
        api.globals[name] = type(_G[name]) == "function"
    end
    if type(Enum) == "table" then
        for _, e in ipairs({ "TradeskillRelativeDifficulty", "AuctionHouseFilter", "ItemCommodityStatus" }) do
            api.enums[e] = describe(Enum[e])
        end
    end
    ProfPathDB.api = api
    chat("API list saved. Type /reload so it is written to disk.")
end

-- /profpath probe : with a profession window open, dump real return values.
local function try(fn, ...)
    if type(fn) ~= "function" then return "<missing>" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "<error> " .. tostring(res[2]) end
    table.remove(res, 1)
    return describe(res)
end

local function dumpProbe()
    local T = C_TradeSkillUI or {}
    local probe = {
        professions = try(GetProfessions),
        baseProfessionInfo = try(T.GetBaseProfessionInfo),
        childProfessionInfo = try(T.GetChildProfessionInfo),
        tradeSkillLine = try(T.GetTradeSkillLine),
        recipes = {},
    }
    local ok, ids = pcall(T.GetAllRecipeIDs)
    if ok and type(ids) == "table" then
        probe.recipeCount = #ids
        for i = 1, math.min(3, #ids) do
            local id = ids[i]
            probe.recipes[i] = {
                id = id,
                info = try(T.GetRecipeInfo, id),
                schematic = try(T.GetRecipeSchematic, id, false),
                reagentCount = try(T.GetRecipeNumReagents, id),
                reagent1 = try(T.GetRecipeReagentInfo, id, 1),
                itemLink = try(T.GetRecipeItemLink, id),
            }
        end
    else
        probe.recipeError = tostring(ids)
        chat("Open a profession window first, then run /profpath probe again.")
    end
    ProfPathDB.probe = probe
    chat("Probe saved. Type /reload so it is written to disk.")
end

-- ---------- recalculation ----------

local state = { index = 1 }
ns.state = state

local function owned(items)
    local t = {}
    for _, id in ipairs(items) do
        local count = (C_Item and C_Item.GetItemCount) or GetItemCount
        local n = count and count(id, true) or 0
        if n > 0 then t[id] = n end
    end
    return t
end

local function recalcNow()
    local profs = ns.Recipes.professions()
    state.profs = profs
    -- Which profession to show: the one chosen (remembered per character); otherwise the last
    -- profession window opened; otherwise the first primary profession (not Cooking/First Aid/Fishing).
    local char = ns.Recipes.char()
    local want = char.selectedProf
    state.index = nil
    for i, p in ipairs(profs) do if p.name == want then state.index = i end end
    if not state.index then
        local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
        for i, p in ipairs(profs) do if not SECONDARY[p.name] and not state.index then state.index = i end end
        state.index = state.index or 1
    end
    local prof = profs[state.index]
    state.prof = prof
    if not prof then ns.UI.show(state); return end

    local opt = ProfPathDB.options
    local recipes, info = ns.Recipes.build(prof)
    state.recipes = recipes
    -- Plan (and scan) only the next `range` points unless a fixed target is set ("all" = 300).
    -- Past your current cap the plan includes training the next rank(s), if your level allows.
    local want = opt.target or (opt.range and (prof.rank or 0) + opt.range) or 300
    local level = UnitLevel and UnitLevel("player") or nil
    local rankUps, max, blocked = ns.Recipes.rankPath(prof, want, level)
    local target = math.min(want, max)
    state.rankUps, state.rankBlocked = rankUps, blocked
    local rankCost = 0
    for _, rk in ipairs(rankUps) do rankCost = rankCost + rk.cost end

    -- Cap went up (you trained a rank): unlock so a fresh plan with the new recipes is worked out.
    local c0 = ns.Recipes.char()
    c0.lastMax = c0.lastMax or {}
    local before = c0.lastMax[prof.name]
    c0.lastMax[prof.name] = prof.max
    if before and prof.max and prof.max > before then
        if c0.commit then c0.commit[prof.name] = nil end
        if ns.Track then
            ns.Track.notify(("Rank trained (cap %d)! Re-planned with the new recipes; check the Plan tab."):format(prof.max))
        end
    end
    local items, users = ns.Recipes.itemsToPrice(recipes, prof.rank, target)
    state.target, state.info, state.items, state.users = target, info, items, users
    local have = owned(items) -- bag/bank counts once per recalc

    -- Locked plan and starting stock (per character and profession).
    -- stock[itemID]: units of the starting stock still left. It only ever goes down (as you use
    -- it); what you buy later is never added, so bought materials are not "free".
    local c = ns.Recipes.char()
    c.commit, c.stock = c.commit or {}, c.stock or {}
    local commit, stock = c.commit[prof.name], c.stock[prof.name]
    if commit and (prof.rank or 0) >= commit.target then -- target reached: done, start fresh
        c.commit[prof.name], c.stock[prof.name], commit, stock = nil, nil, nil, nil
    end
    local free = {}
    if opt.ownedFree then
        free = have                         -- option: everything in the bags counts as free
    elseif stock then
        for id, n in pairs(stock) do
            local left = math.min(n, have[id] or 0)
            stock[id] = left > 0 and left or nil
            free[id] = stock[id]
        end
    else
        free = have                         -- not started yet: what you have now is your stock
    end

    -- Materials nobody sells that you can gather yourself (ore, herbs, leather).
    local gather
    if opt.gather ~= false then
        local skills = ns.Recipes.gatherSkills()
        gather = function(itemID) return (ns.Recipes.gatherValue(itemID, skills, prof.skillLine)) end
    end

    local function ctx(t, only, lockAt)
        return {
            gather = gather,
            skill = prof.rank or 1, target = t or target, recipes = recipes,
            price = ns.Prices.ahTotal, vendorBuy = ns.Prices.vendorBuy, vendorSell = ns.Prices.vendorSell,
            owned = have, free = free, resaleFactor = opt.resaleFactor, effort = opt.effort or 0,
            onlyLevel = only, lockAt = lockAt,
        }
    end
    state.makeCtx = ctx

    state.budget, state.committed, state.better = nil, nil, nil
    local mode = opt.budget or "off"
    local gold = (mode ~= "off" and GetMoney) and (opt.budgetAmount or math.max(0, GetMoney() - (opt.reserve or 0))) or nil
    local t0 = debugprofilestop and debugprofilestop()

    if commit then
        -- Follow the locked plan's recipes from the current skill; separately work out a fresh plan
        -- and offer it only if it is clearly cheaper.
        target = math.min(commit.target, max)
        state.target = target
        local lockAt
        if commit.steps then
            lockAt = function(s)
                for _, ls in ipairs(commit.steps) do if s >= ls[1] and s < ls[2] then return ls[3] end end
            end
        end
        local locked = ns.Optimizer.optimize(ctx(target, commit.ids, lockAt))
        if locked.ok then
            state.result, state.committed = locked, commit
            if gold then state.budget = { mode = mode, gold = gold, reach = target, full = target, limited = false,
                custom = opt.budgetAmount ~= nil } end
            local fresh = ns.Optimizer.optimize(ctx(target))
            local saves = fresh.ok and (locked.totalCost - fresh.totalCost) or 0
            if saves >= 2000 and saves >= 0.1 * locked.totalCost then
                state.better = { result = fresh, saves = saves }
                local sig = {}
                for _, s in ipairs(fresh.steps) do sig[#sig + 1] = s.recipe.id end
                sig = table.concat(sig, ",")
                if commit.offered ~= sig and ns.Track then
                    commit.offered = sig
                    ns.Track.notify(("A cheaper path is available (saves about %s). Open ProfPath to switch.")
                        :format(ns.UI.money(saves)))
                end
            end
        else
            commit = nil -- locked recipes no longer workable (e.g. a price vanished): plan fresh below
            c.commit[prof.name] = nil
        end
    end

    if not commit then
        if (prof.rank or 0) >= target then
            state.result = { ok = true, steps = {}, totalCost = 0, shopping = {}, missing = {} }
        elseif gold then
            -- Fit to a typed budget, or the gold on hand minus the reserve: furthest skill, cheapest way.
            -- Going past the cap needs the rank training paid first: set that aside, and if the money
            -- does not reach past the cap anyway, fit again up to the cap with all of it.
            local capNow = prof.max or target
            local fitGold, fitTarget = gold, target
            if target > capNow then
                if gold >= rankCost then fitGold = gold - rankCost else fitTarget = capNow end
            end
            local res, reach, limited, fullCost = ns.Optimizer.fitBudget(ctx, prof.rank or 1, fitTarget, fitGold, mode)
            if target > capNow and fitTarget > capNow and (not res or reach <= capNow) then
                res, reach, limited, fullCost = ns.Optimizer.fitBudget(ctx, prof.rank or 1, capNow, gold, mode)
                limited = true
            end
            if fitTarget < target then limited = true end
            state.budget = { mode = mode, gold = gold, reach = reach, full = target, limited = limited, fullCost = fullCost,
                custom = opt.budgetAmount ~= nil }
            if res then
                state.result, state.target = res, reach
            else
                state.result = { ok = false, broke = true, stuckAt = prof.rank, missing = {} }
            end
        else
            state.result = ns.Optimizer.optimize(ctx())
        end
        -- No priced/learnable recipe past some skill: plan as far as that and say where it stops.
        local r0 = state.result
        state.partialStop = nil
        if r0 and not r0.ok and not r0.broke and (r0.stuckAt or 0) > (prof.rank or 0) then
            local partial = ns.Optimizer.optimize(ctx(r0.stuckAt))
            if partial.ok then
                state.result, state.target, state.partialStop = partial, r0.stuckAt, r0.stuckAt
            end
        end
    end
    -- Rank training the plan needs (it goes past the current cap): add to the costs and show as steps.
    local res = state.result
    if res and res.ok then
        local needed, prevCap = {}, prof.max or 0
        for _, rk in ipairs(rankUps) do
            if (state.target or 0) > prevCap then needed[#needed + 1] = rk; prevCap = rk.cap end
        end
        res.rankUps = needed
        for _, rk in ipairs(needed) do res.learnTotal = (res.learnTotal or 0) + rk.cost end
    end
    if t0 then state.ms = debugprofilestop() - t0 end
    state.haveNow = have
    if ns.Track then ns.Track.remember() end
    ns.UI.show(state)
end

-- Lock the current plan (Do it): its recipes are followed from now on, and the bags at this moment
-- become the starting stock (free). Materials bought afterwards are valued at what they cost.
-- useResult: lock this result instead of the current one (switching to a cheaper path).
function ns.commitPlan(useResult)
    local prof, res = state.prof, useResult or state.result
    if not (prof and res and res.ok and res.steps[1]) then return end
    local c = ns.Recipes.char()
    c.commit, c.stock = c.commit or {}, c.stock or {}
    local ids, steps = {}, {}
    for _, s in ipairs(res.steps) do
        ids[s.recipe.id] = true
        steps[#steps + 1] = { s.fromSkill, s.toSkill, s.recipe.id } -- skill range -> recipe
    end
    c.commit[prof.name] = { ids = ids, steps = steps, target = res.steps[#res.steps].toSkill, t = time() }
    if not c.stock[prof.name] then -- keep the existing stock when switching paths
        local stock = {}
        for id, n in pairs(state.haveNow or {}) do stock[id] = n end
        c.stock[prof.name] = stock
    end
    ns.recalc()
end

-- Unlock (New plan). The starting stock stays as it is, so materials bought for the old plan
-- do not suddenly become free.
function ns.uncommitPlan()
    local prof = state.prof
    if not prof then return end
    local c = ns.Recipes.char()
    if c.commit then c.commit[prof.name] = nil end
    ns.recalc()
end

-- During a scan: is this item still worth searching? Not if every recipe that needs it is
-- already clearly more expensive than a fully priced alternative (see Optimizer.dominated).
-- Re-evaluated only when new prices have arrived, at most every 2 seconds. Bag counts and
-- the rest of the context are taken once per scan.
local pruneAt, pruneVersion, pruned, scanCtx = -1, -1, {}, nil
function ns.itemNeeded(itemID)
    if not ProfPathDB.options.prune or not state.makeCtx then return true end
    local now = GetTime()
    if ns.Prices.version ~= pruneVersion and now - pruneAt > 2 then
        scanCtx = scanCtx or state.makeCtx()
        pruned = ns.Optimizer.dominated(scanCtx, ProfPathDB.options.pruneFactor or 1.5)
        pruneAt, pruneVersion = now, ns.Prices.version
    end
    for _, r in ipairs(state.users[itemID] or {}) do
        if not pruned[r] then return true end
    end
    return false
end

-- Debounced work: many events arrive in bursts, so wait until they settle before acting.
local pendingRecalc, pendingRedraw, pendingCapture = false, false, false
-- Recalculating can take most of a second (long plans, budget fitting). Run it as a coroutine in
-- slices of about 15 ms per frame so the game keeps drawing instead of freezing. The optimizer
-- yields between its passes (ns.Optimizer.yield). Without a frame timer (tests) it runs at once.
local recalcCo, recalcAgain, recalcDriver
local recalcDone = {} -- callbacks for when the running recalculation finishes
local function finished()
    local cbs = recalcDone
    recalcDone = {}
    for _, cb in ipairs(cbs) do pcall(cb) end
end
-- onDone (optional): called once the new plan is in ns.state.
function ns.recalc(onDone)
    if onDone then recalcDone[#recalcDone + 1] = onDone end
    if not (debugprofilestop and CreateFrame and coroutine and coroutine.create) then recalcNow(); finished(); return end
    if recalcCo then recalcAgain = true; return end
    recalcCo = coroutine.create(recalcNow)
    ns.recalcBusy = true
    if ns.UI.setBusy then ns.UI.setBusy(true) end
    local function step()
        local t0 = debugprofilestop()
        while recalcCo do
            local ok, err = coroutine.resume(recalcCo)
            if not ok then
                recalcCo, ns.recalcBusy = nil, false
                if ns.UI.setBusy then ns.UI.setBusy(false) end
                recalcDone = {}
                if geterrorhandler then geterrorhandler()(err) end
            elseif coroutine.status(recalcCo) == "dead" then
                recalcCo, ns.recalcBusy = nil, false
                if recalcAgain then recalcAgain = false; ns.recalc()
                else
                    if ns.UI.setBusy then ns.UI.setBusy(false) end
                    finished()
                end
            end
            if not recalcCo or debugprofilestop() - t0 > 15 then break end
        end
        if not recalcCo and recalcDriver then recalcDriver:SetScript("OnUpdate", nil) end
    end
    recalcDriver = recalcDriver or CreateFrame("Frame")
    recalcDriver:SetScript("OnUpdate", step)
    step()
end
if ns.Optimizer then
    ns.Optimizer.yield = function()
        local co, isMain = coroutine.running()
        if co and not isMain then coroutine.yield() end
    end
end

function ns.requestRecalc()
    if pendingRecalc or not ns.UI.isShown() or ns.Prices.scanning then return end
    pendingRecalc = true
    C_Timer.After(1, function() pendingRecalc = false; ns.recalc() end)
end

-- Only re-render (e.g. item names finished loading); no recalculation.
function ns.requestRedraw()
    if pendingRedraw or not ns.UI.isShown() or not state.result then return end
    pendingRedraw = true
    C_Timer.After(0.5, function() pendingRedraw = false; ns.UI.show(state) end)
end

local function requestCapture()
    if pendingCapture then return end
    pendingCapture = true
    C_Timer.After(1, function()
        pendingCapture = false
        local ok, err = pcall(ns.Recipes.captureWindow)
        if not ok then chat("could not read the profession window: " .. tostring(err)) end
    end)
end

-- Show this profession (remembered per character).
function ns.selectProfessionByName(name)
    if not name then return end
    ns.Recipes.char().selectedProf = name
    ns.recalc()
end

function ns.selectProfession(delta)
    local n = state.profs and #state.profs or 0
    if n == 0 then return end
    local i = ((state.index or 1) - 1 + delta) % n + 1
    ns.selectProfessionByName(state.profs[i].name)
end

function ns.scanNeeded()
    if not state.items then ns.recalc() end
    pruneAt, pruneVersion, scanCtx = -1, -1, nil
    ns.Prices.scan(state.items or {}, ns.itemNeeded)
end

-- Parses an amount of money: "2" or "1.5" (gold), "1g 50s", "50s", "75c", "1g50s20c". Returns copper or nil.
function ns.parseMoney(s)
    s = (s or ""):lower():gsub("%s+", "")
    if s == "" then return nil end
    local n = tonumber(s)
    if n then return n >= 0 and math.floor(n * 10000 + 0.5) or nil end
    local total, rest = 0, s
    for amount, unit in s:gmatch("([%d%.]+)([gsc])") do
        local v = tonumber(amount)
        if not v then return nil end
        total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    rest = rest:gsub("[%d%.]+[gsc]", "")
    if rest ~= "" then return nil end
    return math.floor(total + 0.5)
end

-- Sets (copper) or clears (nil) the typed budget; switches fitting on if it was off.
function ns.setBudgetAmount(copper)
    local opt = ProfPathDB.options
    opt.budgetAmount = copper
    if copper and (opt.budget or "off") == "off" then opt.budget = "batch" end
    ns.recalc()
end

-- ---------- slash commands ----------

local HELP = {
    "/profpath - open the window",
    "/profpath resale <0-1> - share of a product's AH value counted as recovered (now %s)",
    "/profpath owned on|off - on: everything in your bags counts as free; off (default): only what you had when you started the plan (Do it) is free, what you buy after is valued at its cost (now %s)",
    "/profpath target <skill|max> - stop at this skill (now %s)",
    "/profpath range <points|all> - plan and scan only this many points ahead (now %s)",
    "/profpath prune on|off - during scans, skip items only used by clearly too-expensive recipes (now %s)",
    "/profpath effort <copper> - extra cost per craft, to favour fewer crafts (now %d)",
    "/profpath track on|off - re-plan on every skill-up and alert when you should switch (now %s); /profpath minimap on|off; /profpath about",
    "/profpath budget off|batch|upfront|<amount>|mine - fit the plan to your gold or a set amount like 1g50s (now %s); /profpath reserve <gold> keeps some aside",
    "/profpath gather on|off - gather materials nobody sells yourself, if you have the gathering profession (now %s)",
    "/profpath scan - scan AH prices for this profession (auction house must be open)",
    "/profpath route off - hide the gathering route and its waypoint (Show route on the Plan tab shows one)",
}

SLASH_PROFPATH1 = "/profpath"
SLASH_PROFPATH2 = "/pp"
SlashCmdList.PROFPATH = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local opt = ProfPathDB.options
    if cmd == "" then
        ns.UI.toggle()
    --@debug@
    elseif cmd == "api" then -- developer: dump client API info to SavedVariables
        dumpApi()
    elseif cmd == "probe" then
        dumpProbe()
    --@end-debug@
    elseif cmd == "scan" then
        ns.scanNeeded()
    elseif cmd == "resale" and tonumber(arg) then
        opt.resaleFactor = math.max(0, math.min(1, tonumber(arg))); chat("resale = " .. opt.resaleFactor); ns.requestRecalc()
    elseif cmd == "owned" and (arg == "on" or arg == "off") then
        opt.ownedFree = arg == "on"; chat("owned materials free: " .. arg); ns.requestRecalc()
    elseif cmd == "target" and (arg == "max" or tonumber(arg)) then
        opt.target = tonumber(arg); chat("target = " .. (opt.target or "max")); ns.requestRecalc()
    elseif cmd == "budget" and (arg == "mine" or ns.parseMoney(arg)) then
        if arg == "mine" then
            ns.setBudgetAmount(nil); chat("budget: the gold in your bags")
        else
            ns.setBudgetAmount(ns.parseMoney(arg)); chat("budget: " .. ns.UI.money(opt.budgetAmount))
        end
    elseif cmd == "budget" and (arg == "off" or arg == "batch" or arg == "upfront") then
        opt.budget = arg
        chat(("fit to my gold: %s"):format(arg == "off" and "off" or arg == "batch"
            and "batches (buy, craft, vendor, repeat)" or "up front (buy everything first)"))
        ns.requestRecalc()
    elseif cmd == "reserve" and tonumber(arg) then
        opt.reserve = math.max(0, math.floor(tonumber(arg) * 10000))
        chat(("keeping %s untouched"):format(ns.UI.money(opt.reserve))); ns.requestRecalc()
    elseif cmd == "about" then
        local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end)(addonName, "Version")
        chat(("ProfPath %s - cheapest profession leveling from live auction prices."):format(version or ""))
        chat("Trainer, node and creature locations from Wowhead (wowhead.com). Recipe data and terrain from the game files via wago.tools. Gathering zones follow the WoW: Forever guides on Wowhead and wow-professions.com.")
    elseif cmd == "minimap" and (arg == "on" or arg == "off") then
        ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
        ProfPathDB.minimap.hide = arg == "off"
        ns.Minimap.refresh()
        chat("minimap button: " .. arg)
    elseif cmd == "track" and (arg == "on" or arg == "off") then
        opt.track = arg == "on"
        chat("live tracking (re-plan on every skill-up, alert on switches): " .. arg)
    elseif cmd == "effort" and tonumber(arg) then
        opt.effort = math.max(0, math.floor(tonumber(arg)))
        chat(("effort = %d copper per craft (higher = fewer crafts, even if it costs a bit more gold)"):format(opt.effort))
        ns.requestRecalc()
    --@debug@
    elseif cmd == "why" and arg ~= "" then
        if not state.recipes and ns.recalc then pcall(ns.recalc) end
        -- Collect the output in a copy box (select-all, Ctrl+C) instead of chat.
        local lines = {}
        local function pm(c) c = math.floor(c or 0); return ("%dg%02ds%02dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100) end
        local chat = function(t) lines[#lines + 1] = t end
        local function showCopy()
            local f = _G.ProfPathCopyBox
            if not f then
                f = CreateFrame("Frame", "ProfPathCopyBox", UIParent, "BasicFrameTemplateWithInset")
                f:SetSize(620, 380); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
                f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
                f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
                if f.TitleText then f.TitleText:SetText("ProfPath: Ctrl+C to copy, Esc to close") end
                local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
                sf:SetPoint("TOPLEFT", 12, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
                local eb = CreateFrame("EditBox", nil, sf)
                eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(570)
                eb:SetScript("OnEscapePressed", function() f:Hide() end)
                sf:SetScrollChild(eb)
                f.eb = eb
                tinsert(UISpecialFrames, "ProfPathCopyBox")
            end
            local text = table.concat(lines, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
            f.eb:SetText(text)
            f:Show(); f.eb:SetFocus(); f.eb:HighlightText()
        end
        -- Test: why a recipe was or wasn't used. /pp why <part of a recipe name>
        local found = 0
        for _, r in ipairs(state.recipes or {}) do
            if (r.name or ""):lower():find(arg, 1, true) and found < 4 then
                found = found + 1
                chat(("%s (%d): learned %s, learn %s (%s), skill %d, yellow %d, gray %d%s"):format(r.name, r.id,
                    tostring(r.learned), r.learnCost and pm(r.learnCost) or "unknown",
                    r.learnSource and r.learnSource.kind or "-", r.minSkill or 0, r.yellow or 0, r.gray or 0,
                    r.noLevel and ", no leveling (cooldown)" or ""))
                for _, rg in ipairs(r.reagents or {}) do
                    local id, n = rg[1], rg[2]
                    local ah, src = ns.Prices.ahUnit(id)
                    local bulk = ns.Prices.ahTotal(id, n * 20)
                    chat(("   %dx item %d: AH %s (%s), bulk x%d %s each, vendor %s"):format(n, id,
                        ah and pm(ah) or "none", src or "-", n * 20,
                        bulk and pm(math.floor(bulk / (n * 20))) or "none",
                        ns.Prices.vendorBuy(id) and pm(ns.Prices.vendorBuy(id)) or "-"))
                end
            end
        end
        if found == 0 then
            -- Not in the plan's list: say which filter dropped it.
            local prof = state.prof
            chat(("Not in the plan's list (%d recipes there; profession %s, skill line %s, rank %s/%s)."):format(
                #(state.recipes or {}), prof and prof.name or "?", prof and tostring(prof.skillLine) or "?",
                prof and tostring(prof.rank) or "?", prof and tostring(prof.max) or "?"))
            for id, d in pairs(ns.Data.recipes) do
                if (d[8] or ""):lower():find(arg, 1, true) and found < 4 then
                    found = found + 1
                    local c = ns.Recipes.char()
                    local learned = c.learned and prof and c.learned[prof.name] and c.learned[prof.name][id]
                    local ri = ns.Data.recipeItems[id]
                    local why = {}
                    if prof and d[1] ~= prof.skillLine then why[#why + 1] = "other skill line " .. d[1] end
                    if prof and d[4] <= (prof.rank or 0) and not learned then why[#why + 1] = "gray at " .. d[4] end
                    if ns.Data.cooldown and ns.Data.cooldown[id] then why[#why + 1] = "cooldown" end
                    if ri and (ri[3] or 0) ~= 0 then why[#why + 1] = "specialization " .. ri[3] end
                    if ri then
                        local v, ah = ns.Prices.vendorBuy(ri[1]), ns.Prices.ahUnit(ri[1])
                        why[#why + 1] = ("recipe item %d: vendor %s, AH %s"):format(ri[1], v and pm(v) or "-", ah and pm(ah) or "none")
                    else
                        why[#why + 1] = "trainer recipe"
                    end
                    chat(("  %s (%d): %s"):format(d[8], id, table.concat(why, "; ")))
                end
            end
        end
        -- Re-run the plan as the window does, then once with nothing counted as free stock, and show
        -- what each assumes for the materials of the recipes above.
        if state.makeCtx and state.target then
            local mats = {}
            for _, r in ipairs(state.recipes or {}) do
                if (r.name or ""):lower():find(arg, 1, true) then
                    for _, rg in ipairs(r.reagents or {}) do mats[rg[1]] = true end
                end
            end
            for pass = 1, 2 do
                local ctx = state.makeCtx(state.target)
                if pass == 2 then ctx.free = {} end
                local res = ns.Optimizer.optimize(ctx)
                chat(("Plan check %d (%s), target %d: %s"):format(pass, pass == 1 and "as the window" or "nothing free",
                    state.target, res.ok and "ok" or ("stuck at " .. tostring(res.stuckAt))))
                for _, st in ipairs(res.steps or {}) do
                    chat(("   %d-%d %s x%d, cost %s"):format(st.fromSkill, st.toSkill, st.recipe.name or "?",
                        math.ceil(st.expectedCrafts - 1e-9), pm(st.cost)))
                end
                for _, sh in ipairs(res.shopping or {}) do
                    if mats[sh.itemID] or sh.itemID == 4234 or sh.itemID == 2319 then
                        chat(("   material %d: need %d, own %d, free %d, buy %d via %s at %s each"):format(sh.itemID,
                            sh.needed, sh.owned or 0, (ctx.free and ctx.free[sh.itemID]) or 0, sh.buy, tostring(sh.source), pm(sh.unitCost)))
                    end
                end
                for _, it in ipairs(res.intermediates or {}) do
                    chat(("   craft first: %s x%d"):format(it.recipe.name or "?", it.crafts))
                end
                chat(("   net %s, cash %s"):format(pm(res.totalCost), pm((res.cash or 0) + (res.learnTotal or 0))))
            end
        end
        showCopy()
    --@end-debug@
    elseif cmd == "route" and ns.Map and ns.Map.slash(arg) then
        -- handled: /pp route off | show
    elseif cmd == "gather" and (arg == "on" or arg == "off") then
        opt.gather = arg == "on"
        chat("gather materials nobody sells yourself (ore, herbs, leather): " .. arg); ns.requestRecalc()
    elseif cmd == "prune" and (arg == "on" or arg == "off") then
        opt.prune = arg == "on"; chat("skip items only used by clearly too-expensive recipes: " .. arg)
    elseif cmd == "range" and (arg == "all" or tonumber(arg)) then
        opt.range = tonumber(arg) and math.max(5, math.floor(tonumber(arg))) or false
        if opt.target then opt.target = nil; chat("fixed target cleared") end
        chat("range = " .. (opt.range or "all")); ns.requestRecalc()
    else
        chat(HELP[1]); chat(HELP[2]:format(opt.resaleFactor)); chat(HELP[3]:format(opt.ownedFree and "on" or "off"))
        chat(HELP[4]:format(opt.target or "max")); chat(HELP[5]:format(opt.range or "all"))
        chat(HELP[6]:format(opt.prune and "on" or "off")); chat(HELP[7]:format(opt.effort or 0))
        chat(HELP[8]:format(opt.track and "on" or "off")); chat(HELP[9]:format(opt.budget or "off"))
        chat(HELP[10]:format(opt.gather == false and "off" or "on")); chat(HELP[11]); chat(HELP[12])
    end
end

-- ---------- events ----------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        ProfPathDB = ProfPathDB or {}
        local db = ProfPathDB
        db.options = db.options or {}
        -- Default: count only the guaranteed vendor price of crafted items, not an AH resale guess.
        if db.options.resaleFactor == nil then db.options.resaleFactor = 0 end
        -- Owned materials are valued at replacement cost by default, so buying for the plan
        -- does not change the plan. "on" treats them as free (use up farmed stock).
        if db.options.ownedFree == nil then db.options.ownedFree = false end
        if db.options.range == nil then db.options.range = 30 end -- false = plan to max
        if db.options.prune == nil then db.options.prune = true end
        if db.options.track == nil then db.options.track = true end
        if db.options.budget == nil then db.options.budget = "batch" end -- fit plans to the gold you have
        for _, k in ipairs({ "prices", "vendor", "trainer", "trainerSeen", "chars" }) do db[k] = db[k] or {} end
        if (db.version or 1) < 2 then
            -- v1 captured other professions' recipes and wrong skill lines; recapture on next window open.
            for _, c in pairs(db.chars) do c.live, c.skill = {}, {} end
            db.version = 2
        end
        if db.version < 3 then
            -- v2 recorded scan timeouts as "nothing listed"; drop those so they are scanned again.
            for id, e in pairs(db.prices) do if e.none then db.prices[id] = nil end end
            db.version = 3
        end
        if db.version < 4 then
            -- v3 defaulted to counting half the AH value of crafted items as recovered; 0.5 was never
            -- chosen by the user, so move it to the new vendor-only default.
            if db.options.resaleFactor == 0.5 then db.options.resaleFactor = 0 end
            db.version = 4
        end
        if db.version < 5 then
            -- v4 counted owned materials as free, so buying for the plan could flip the plan.
            db.options.ownedFree = false
            db.version = 5
        end
        self:UnregisterEvent("ADDON_LOADED")
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED",
            "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_CLOSED", "GET_ITEM_INFO_RECEIVED", "PLAYER_MONEY" }) do
            pcall(self.RegisterEvent, self, e)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        if event == "TRADE_SKILL_SHOW" then ns.Recipes.switchOnOpen = true end
        requestCapture()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.requestRedraw()
    else
        ns.requestRecalc()
    end
end)
