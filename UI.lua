-- ProfPath window: a three-step wizard.
--   1 Prepare  - checklist: profession read, trainer visited, recipe data, prices (+ scan buttons), range
--   2 Plan     - summary (spend / back / net / crafts) and the steps; click a step for its details
--   3 Do it    - to-do list in order: learn, buy, craft first, level up (ticks update from bags/skill)
-- Public: UI.toggle(), UI.isShown(), UI.show(state), UI.scanProgress(progress, scanning)
local _, ns = ...
local UI = {}
ns.UI = UI

local floor = math.floor
local WIDTH, HEIGHT, CONTENT = 600, 620, 550
local ICON_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_TODO = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ICON_BAD = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_GOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local SOURCE = { ah = "Auction House", vendor = "Vendor", craft = "Craft", gather = "Gather it yourself" }

-- ---------- helpers ----------

local function money(c)
    c = floor((c or 0) + 0.5)
    local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = ("|cffffd700%dg|r"):format(g) end
    if g > 0 or s > 0 then out[#out + 1] = ("|cffc7c7cf%ds|r"):format(s) end
    if g == 0 then out[#out + 1] = ("|cffeda55f%dc|r"):format(cp) end -- copper is noise once there is gold
    return table.concat(out, " ")
end
UI.money = money

-- Crafting station a recipe needs (Anvil, Forge, Cooking Fire...), or nil.
local function station(r)
    local f = r and r.focus
    return f and ns.Data.focusNames and ns.Data.focusNames[f] or nil
end

local function itemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return "item " .. id
    end
    return name
end

local function itemIcon(id)
    local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ago(seconds)
    if seconds < 90 then return "just now" end
    if seconds < 3600 then return floor(seconds / 60) .. " min ago" end
    if seconds < 86400 then return floor(seconds / 3600) .. " h ago" end
    return floor(seconds / 86400) .. " days ago"
end

-- ---------- frame ----------

local frame, title, bar, barText
local tabs = {}
local TAB_NAMES = { "1  Prepare", "2  Plan", "3  Do it" }
local current = 1
local lastState

local function build()
    frame = CreateFrame("Frame", "ProfPathFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames, "ProfPathFrame") -- Escape closes it

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)

    local function small(label, w, x, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, -30); b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    -- Profession dropdown: shows the current profession; click for a menu of all of them.
    local pick = small("", 170, 12, function() UI.toggleProfMenu() end)
    local arrow = pick:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(18, 18)
    arrow:SetPoint("RIGHT", -4, 0)
    UI.profButton = pick

    local menu = CreateFrame("Frame", nil, frame)
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -2)
    menu:SetSize(220, 10)
    local menuBg = menu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints(); menuBg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    local menuEdge = menu:CreateTexture(nil, "BORDER")
    menuEdge:SetPoint("TOPLEFT", -1, 1); menuEdge:SetPoint("BOTTOMRIGHT", 1, -1)
    menuEdge:SetColorTexture(1, 0.82, 0, 0.6)
    menu:Hide()
    menu.buttons = {}
    UI.profMenu = menu
    frame:HookScript("OnHide", function() menu:Hide() end)

    for i, name in ipairs(TAB_NAMES) do
        tabs[i] = small(name, 120, 188 + (i - 1) * 126, function() UI.setTab(i) end)
    end

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 12, -58)
    bar:SetPoint("TOPRIGHT", -12, -58)
    bar:SetHeight(18)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.6, 1)
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    barText:SetPoint("CENTER")
    bar:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    UI.scroll = scroll
    scroll:SetPoint("TOPLEFT", 12, -62)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT, 10)
    scroll:SetScrollChild(child)
    UI.child = child

    -- "Calculating" overlay: covers the content while a recalculation runs (over several frames),
    -- so clicks don't seem to do nothing and an empty window doesn't look broken.
    local busy = CreateFrame("Frame", nil, frame)
    busy:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    busy:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 20, 0)
    busy:SetFrameLevel((scroll:GetFrameLevel() or 0) + 20)
    busy:EnableMouse(true) -- swallow clicks on the half-updated content
    local shade = busy:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.55)
    local label = busy:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOP", 0, -60)
    label:SetText("Calculating your plan...")
    local dots, acc = 0, 0
    busy:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc, dots = 0, (dots + 1) % 4
        label:SetText("Calculating your plan" .. string.rep(".", dots))
    end)
    busy:Hide()
    UI.busy = busy
    frame:Hide() -- new frames start shown; toggle() then shows it on the first /pp
end

-- Called by Core when a recalculation starts (true) and when it finished and drew (false).
function UI.setBusy(on)
    if not UI.busy then return end
    if on then UI.busy:Show() else UI.busy:Hide() end
end

local function showBar(on)
    if on then bar:Show(); UI.scroll:SetPoint("TOPLEFT", 12, -82)
    else bar:Hide(); UI.scroll:SetPoint("TOPLEFT", 12, -62) end
end

function UI.isShown() return frame and frame:IsShown() end

-- Profession menu: one row per profession with its skill; click to switch.
function UI.toggleProfMenu()
    local menu = UI.profMenu
    if not menu then return end
    if menu:IsShown() then menu:Hide(); return end
    local profs = lastState and lastState.profs or {}
    for _, b in ipairs(menu.buttons) do b:Hide() end
    for i, p in ipairs(profs) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
            b:SetSize(212, 24)
            menu.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 26)
        local current = lastState.prof and lastState.prof.name == p.name
        b:SetText(("%s%s  %d / %d"):format(current and "> " or "", p.name, p.rank or 0, p.max or 0))
        b:SetScript("OnClick", function() menu:Hide(); ns.selectProfessionByName(p.name) end)
        b:Show()
    end
    if #profs == 0 then return end
    menu:SetHeight(8 + #profs * 26)
    menu:Show()
end

-- Open on Prepare when something is missing, otherwise on Plan.
local function needsPrep(state)
    local info = state and state.info
    if not state or not state.prof or not info then return true end
    if info.noLearnedData or not ns.Data.build then return true end
    return not (state.result and state.result.ok)
end

function UI.toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide(); return end
    frame:Show()
    -- the plan is calculated over a few frames: pick the tab once it's ready
    ns.recalc(function()
        if needsPrep(ns.state) then UI.setTab(1)
        elseif ns.state.committed then UI.setTab(3) end
    end)
end

function UI.setTab(i)
    current = i
    UI.scroll:SetVerticalScroll(0)
    -- Opening Do it locks the plan (and records the starting stock) if it isn't locked yet.
    if i == 3 and lastState and not lastState.committed and lastState.result and lastState.result.ok
        and lastState.result.steps and #lastState.result.steps > 0 then
        ns.commitPlan()
        return
    end
    if lastState then UI.show(lastState) end
end

-- ---------- layout engine: pooled widgets placed top-down in the scroll child ----------

local pools = { text = {}, tex = {}, click = {}, button = {} }
local used = { text = 0, tex = 0, click = 0, button = 0 }
local y = 0

local function reset()
    for kind, pool in pairs(pools) do
        for i = 1, #pool do pool[i]:Hide() end
        used[kind] = 0
    end
    if UI.budgetBox then UI.budgetBox:Hide() end
    y = 0
end

-- Text box for typing a budget ("1g 50s", "2", "50s"). Enter or the Set button applies it.
local function budgetBox(x, current)
    local box = UI.budgetBox
    if not box then
        box = CreateFrame("EditBox", nil, UI.child, "InputBoxTemplate")
        box:SetAutoFocus(false)
        box:SetSize(84, 20)
        box:SetMaxLetters(16)
        local function apply(self)
            local copper = ns.parseMoney(self:GetText())
            self:ClearFocus()
            if copper then ns.setBudgetAmount(copper)
            else ns.chat("Couldn't read that amount. Try 2, 1g 50s or 50s.") end
        end
        box:SetScript("OnEnterPressed", apply)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box.apply = apply
        UI.budgetBox = box
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", x, -y - 2)
    if not box:HasFocus() then box:SetText(current or "") end
    box:Show()
    return box
end

-- Money as plain text for the input box: "1g 50s".
local function moneyPlain(c)
    c = floor(c + 0.5)
    local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
    return table.concat(out, " ")
end

local function take(kind, make)
    used[kind] = used[kind] + 1
    local w = pools[kind][used[kind]]
    if not w then w = make(); pools[kind][used[kind]] = w end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function text(font, x, yy, w, s, justify, wrap)
    local f = take("text", function() return UI.child:CreateFontString(nil, "OVERLAY") end)
    f:SetFontObject(font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", x, -yy)
    f:SetWidth(w)
    f:SetJustifyH(justify or "LEFT")
    f:SetWordWrap(wrap or false)
    f:SetText(s)
    return f
end

local function tex(path, x, yy, w, h, r, g, b, a)
    local t = take("tex", function() return UI.child:CreateTexture(nil, "ARTWORK") end)
    t:SetPoint("TOPLEFT", x, -yy)
    t:SetSize(w, h)
    if path then t:SetTexture(path); t:SetVertexColor(1, 1, 1, 1); t:SetTexCoord(0, 1, 0, 1)
    else t:SetColorTexture(r, g, b, a) end
    return t
end

local function button(label, x, w, onClick)
    local b = take("button", function() return CreateFrame("Button", nil, UI.child, "UIPanelButtonTemplate") end)
    b:SetPoint("TOPLEFT", x, -y)
    b:SetSize(w, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function clickable(h, onClick)
    local b = take("click", function()
        local c = CreateFrame("Button", nil, UI.child)
        c:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        return c
    end)
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetSize(CONTENT, h)
    b:SetScript("OnClick", onClick)
end

local function para(s, font)
    local f = text(font or "GameFontHighlightSmall", 4, y, CONTENT - 8, s, "LEFT", true)
    y = y + f:GetStringHeight() + 6
end

local function stepTitle(n, s, sub)
    text("GameFontNormalHuge", 4, y, 40, tostring(n))
    text("GameFontNormalLarge", 40, y + 2, CONTENT - 44, s)
    y = y + 24
    if sub then
        local f = text("GameFontDisableSmall", 40, y, CONTENT - 44, sub, "LEFT", true)
        y = y + f:GetStringHeight() + 4
    end
    tex(nil, 4, y + 2, CONTENT - 8, 1, 1, 0.82, 0, 0.5)
    y = y + 10
end

local function section(s)
    y = y + 6
    text("GameFontNormal", 4, y, CONTENT - 8, s)
    y = y + 18
end

-- A line with a status/item icon, a main text, an optional second line and right-aligned text.
local LINE = 34
local function line(icon, main, sub, right, opts)
    opts = opts or {}
    local h = sub and LINE or 24
    if opts.highlight then tex(nil, 0, y, CONTENT, h, 0.2, 0.5, 1, 0.25)
    elseif opts.zebra then tex(nil, 0, y, CONTENT, h, 1, 1, 1, 0.04) end
    if opts.onClick then clickable(h, opts.onClick) end
    local x = 6
    if opts.status then tex(opts.status, x, y + (h - 16) / 2, 16, 16); x = x + 22 end
    if icon then tex(icon, x, y + (h - 22) / 2, 22, 22); x = x + 28 end
    local rightW = right and (opts.rightW or 150) or 0
    text("GameFontHighlight", x, y + (sub and 3 or 5), CONTENT - x - rightW - 8, main)
    if sub then text("GameFontDisableSmall", x, y + 19, CONTENT - x - rightW - 8, sub) end
    if right then text("GameFontHighlight", CONTENT - rightW - 6, y + (h - 12) / 2, rightW, right, "RIGHT") end
    y = y + h + 2
end

-- Big number cards in a row.
local function cards(list)
    local w = (CONTENT - 8 - (#list - 1) * 8) / #list
    for i, c in ipairs(list) do
        local x = 4 + (i - 1) * (w + 8)
        tex(nil, x, y, w, 48, 1, 1, 1, 0.06)
        tex(nil, x, y, w, 2, c.r or 1, c.g or 0.82, c.b or 0, 0.8)
        text("GameFontDisableSmall", x + 8, y + 8, w - 16, c.label)
        text("GameFontHighlightLarge", x + 8, y + 24, w - 16, c.value)
    end
    y = y + 56
end

-- Where to go: the remembered trainer (name, zone, coordinates) with a Waypoint button.
local function trainerHint(profName, rankName, x0)
    x0 = x0 or 62
    local list = ns.Recipes.trainersFor(profName, rankName)
    local best = list[1]
    if not best then
        text("GameFontHighlightSmall", x0, y + 5, CONTENT - x0 - 8,
            ("|cff888888No %s trainer known for your faction. Ask a city guard.|r"):format(profName))
        y = y + 28
        return
    end
    local loc, dist = best.loc, best.dist
    local label = (rankName and (rankName .. " trainer") or "Trainer")
    label = (dist and "Closest " .. label:lower() or label)
    local s = ("|cffffd100%s:|r  %s%s"):format(label, ns.Recipes.trainerText(loc, dist),
        loc.title and loc.title ~= "" and ("  |cff888888<" .. loc.title .. ">|r") or "")
    text("GameFontHighlightSmall", x0, y + 5, CONTENT - x0 - 120, s, "LEFT", false)
    button("Waypoint", CONTENT - 110, 104, function()
        if ns.Recipes.waypoint(loc) then ns.chat("Waypoint set: " .. ns.Recipes.trainerText(loc))
        else ns.chat("Couldn't set a map pin here. " .. ns.Recipes.trainerText(loc)) end
    end)
    y = y + 26
    -- A second option, in case the first can't teach it after all (titles can lag behind the game).
    local alt = list[2]
    if alt then
        text("GameFontDisableSmall", x0, y, CONTENT - x0 - 8,
            ("If not: %s%s"):format(ns.Recipes.trainerText(alt.loc, alt.dist),
                alt.loc.title and alt.loc.title ~= "" and (" <" .. alt.loc.title .. ">") or ""))
        y = y + 18
    end
    y = y + 4
end

-- ---------- tab 1: prepare ----------

local function priceStatus(state)
    local items = state.items or {}
    local priced, newest = 0, nil
    local now = time()
    for _, id in ipairs(items) do
        local e = ProfPathDB.prices[id]
        if e or ns.Prices.vendorBuy(id) then priced = priced + 1 end
        if e and (not newest or e.t > newest) then newest = e.t end
    end
    return priced, #items, newest and (now - newest)
end

local function renderPrepare(state)
    local prof, info = state.prof, state.info
    stepTitle(1, "Gather information", "ProfPath needs to know your recipes, trainer costs and current auction prices.")

    local learnedCount = 0
    for _ in pairs(ns.Recipes.char().learned[prof.name] or {}) do learnedCount = learnedCount + 1 end
    line(nil, "Profession", info.noLearnedData and "Open your profession window (K) once so known recipes can be read."
        or ("%s %d / %d, %d recipes known"):format(prof.name, prof.rank or 0, prof.max or 0, learnedCount), nil,
        { status = info.noLearnedData and ICON_BAD or ICON_OK })

    line(nil, "Trainer", info.trainerSeen and "Recipe costs and skill requirements are known."
        or ("Visit a %s trainer once so recipe costs are known."):format(prof.name), nil,
        { status = info.trainerSeen and ICON_OK or ICON_TODO })
    trainerHint(prof.name, nil, 34)

    line(nil, "Recipe data", ns.Data.build and ("Game data for build %s."):format(ns.Data.build)
        or "Missing: run tools\\build_data.ps1 and /reload.", nil, { status = ns.Data.build and ICON_OK or ICON_BAD })

    local priced, total, age = priceStatus(state)
    -- A recent full scan saw the whole auction house: items it didn't find simply have no listings.
    local snapAge = ProfPathDB.lastSnapshot and (time() - ProfPathDB.lastSnapshot)
    local fullFresh = snapAge and snapAge < 6 * 3600
    local fresh = age and age < 6 * 3600
    local okPrices = total > 0 and (fullFresh or (priced >= total * 0.8 and fresh))
    local priceText
    if total == 0 then priceText = "Nothing to price yet."
    elseif fullFresh then
        priceText = ("Full scan %s: %d of %d items have listings (the rest aren't on sale right now).")
            :format(ago(snapAge), priced, total)
    else
        priceText = ("%d of %d items priced, updated %s. Open the auction house to scan."):format(priced, total,
            age and ago(age) or "never")
    end
    line(nil, "Auction prices", priceText, nil, { status = okPrices and ICON_OK or ICON_TODO })
    local wait = ns.Prices.snapshotReadyIn()
    local snap = ns.Prices.snapshotting
    button(snap and "Stop full scan" or wait > 0 and ("Full scan in %dm"):format(math.ceil(wait / 60)) or "Full scan (fast)",
        34, 160, function() if ns.Prices.snapshotting then ns.Prices.stopSnapshot() else ns.Prices.fullScan() end end)
    local scanning = ns.Prices.scanning and not snap
    button(scanning and "Stop scan" or "Scan missing items", 200, 160,
        function() if ns.Prices.scanning then ns.Prices.stopScan() else ns.scanNeeded() end end)
    y = y + 32

    local opt = ProfPathDB.options
    local MODES = { batch = "Batches", upfront = "Up front", off = "Off" }
    local mode = opt.budget or "off"
    local gold = GetMoney and GetMoney() or 0
    local b = state.budget
    local goldText
    if opt.budgetAmount then
        goldText = ("Budget set to %s (you have %s). "):format(money(opt.budgetAmount), money(gold))
    else
        goldText = ("You have %s%s. "):format(money(gold), (opt.reserve or 0) > 0 and (", keeping " .. money(opt.reserve) .. " aside") or "")
    end
    if mode == "off" then goldText = goldText .. "Plans ignore your gold."
    elseif mode == "batch" then goldText = goldText .. "Plans fit it, buying in batches and vendoring as you go."
    else goldText = goldText .. "Plans fit it with everything bought up front." end
    line(nil, opt.budgetAmount and "Budget" or "Your gold", goldText, nil,
        { status = (b and b.limited) and ICON_TODO or ICON_OK })
    button("Fit to gold: " .. MODES[mode], 34, 160, function()
        local order = { batch = "upfront", upfront = "off", off = "batch" }
        opt.budget = order[mode]
        ns.recalc()
    end)
    local box = budgetBox(206, opt.budgetAmount and moneyPlain(opt.budgetAmount) or "")
    button("Set", 296, 50, function() box.apply(box) end)
    button(opt.budgetAmount and "Use my gold" or "Type an amount", 350, 120, function()
        if opt.budgetAmount then ns.setBudgetAmount(nil) else box:SetFocus() end
    end)
    y = y + 32

    line(nil, "How far ahead", opt.target and ("Up to skill %d."):format(opt.target)
        or opt.range and ("The next %d points (%d -> %d)."):format(opt.range, prof.rank or 0, state.target or 0)
        or ("As far as you can go (%d)."):format(state.target or 0), nil, { status = ICON_OK })
    local RANGES = { 15, 30, 50, false }
    button("Change range", 34, 160, function()
        local nextR = RANGES[1]
        for i, r in ipairs(RANGES) do if r == opt.range then nextR = RANGES[i % #RANGES + 1] end end
        opt.range, opt.target = nextR, nil
        ns.recalc()
    end)
    y = y + 32

    -- Rank: current cap and what the next rank needs.
    local nextRank = (state.rankUps and state.rankUps[1]) or state.rankBlocked
    if not nextRank then
        local _, _, blocked = ns.Recipes.rankPath(prof, 999, UnitLevel and UnitLevel("player") or nil)
        local list = ns.Recipes.rankPath(prof, 999, nil)
        nextRank = blocked or list[1]
    end
    local rankText = ("Your cap is %d."):format(prof.max or 0)
    if nextRank then
        rankText = rankText .. (" Next: %s at skill %d and character level %d, about %s at a trainer%s.")
            :format(nextRank.name, nextRank.req, nextRank.level, money(nextRank.cost),
                nextRank.estimated and " (Classic values until a trainer shows it)" or "")
    end
    local lvlOk = not state.rankBlocked
    line(nil, "Rank", rankText .. (lvlOk and "" or ("  |cffff8800Your level is too low to plan past %d.|r"):format(prof.max or 0)),
        nil, { status = lvlOk and ICON_OK or ICON_TODO })
    y = y + 8

    button("Next:  see the plan  >", CONTENT - 200, 196, function() UI.setTab(2) end)
    y = y + 32
end

-- Recent switch / step-done alert from live tracking, shown on Plan and Do it for 15 minutes.
local function alertBanner(state)
    local a = state.alert
    if not a or time() - a.t > 900 then return end
    tex(nil, 0, y, CONTENT, 26, 1, 0.82, 0, 0.18)
    tex(nil, 0, y, 3, 26, 1, 0.82, 0, 0.9)
    text("GameFontHighlight", 10, y + 7, CONTENT - 16, a.text .. ("  |cff888888(%s)|r"):format(ago(time() - a.t)))
    y = y + 32
end

-- Locked-plan notice with a New plan button, and a cheaper-path offer with a Switch button.
local function lockBanner(state)
    local cm = state.committed
    if not cm then return end
    text("GameFontDisableSmall", 6, y + 4, CONTENT - 150,
        ("Plan locked %s. Only what you had then counts as free; what you buy is valued at its cost.")
            :format(ago(time() - (cm.t or time()))), "LEFT", true)
    button("New plan", CONTENT - 130, 126, function() ns.uncommitPlan(); UI.setTab(2) end)
    y = y + 30
    local b = state.better
    if b then
        tex(nil, 0, y, CONTENT, 30, 0.3, 0.8, 0.3, 0.15)
        tex(nil, 0, y, 3, 30, 0.3, 0.8, 0.3, 0.9)
        local names = {}
        for _, s in ipairs(b.result.steps) do names[#names + 1] = s.recipe.name or "?" end
        text("GameFontHighlight", 10, y + 8, CONTENT - 150, ("Cheaper path now: %s (saves %s)")
            :format(table.concat(names, " > "), money(b.saves)))
        local res = b.result
        local bt = button("Switch to it", CONTENT - 130, 126, function() ns.commitPlan(res) end)
        bt:SetPoint("TOPLEFT", CONTENT - 130, -y - 3)
        y = y + 36
    end
end

-- A "train the next rank" row, shown between the steps where it is needed.
local ICON_BOOK = "Interface\\Icons\\INV_Misc_Book_11"
local function rankRow(rk, fromCap, opts, profName)
    local loc = profName and ns.Recipes.trainerFor(profName, rk.name)
    line(ICON_BOOK, ("|cffffd100At skill %d:|r  train %s at a trainer"):format(rk.req, rk.name),
        ("cap %d -> %d  -  needs character level %d%s%s"):format(fromCap, rk.cap, rk.level,
            rk.estimated and "  -  Classic values until a trainer shows it" or "",
            loc and ("  -  " .. loc.npc .. ", " .. loc.zone) or ""),
        money(rk.cost), opts or {})
end

-- Steps interleaved with the rank training each one needs: a rank goes before the first step that
-- goes past the cap it lifts.
local function withRanks(res, cap)
    local out, pending, prevCap = {}, {}, cap
    for _, rk in ipairs(res.rankUps or {}) do pending[#pending + 1] = rk end
    for _, st in ipairs(res.steps) do
        while pending[1] and st.toSkill > prevCap do
            out[#out + 1] = { rank = pending[1], fromCap = prevCap }
            prevCap = pending[1].cap
            table.remove(pending, 1)
        end
        out[#out + 1] = { step = st }
    end
    return out
end
UI.withRanks = withRanks

-- ---------- tab 2: plan ----------

local function colourRange(r)
    local green = floor((r.yellow + r.gray) / 2)
    return ("|cffff8040orange|r to %d  |cffffff00yellow|r to %d  |cff40c040green|r to %d  |cff808080gray|r at %d")
        :format(r.yellow, green, r.gray, r.gray)
end

local function renderStepDetail(st)
    local r = st.recipe
    local x0 = 20
    local learn
    if r.learned then learn = "You know this recipe."
    elseif r.learnSource and r.learnSource.kind == "item" then
        learn = ("Learn from |cffffffff%s|r (%s, %s), needs skill %d."):format(itemName(r.learnSource.itemID),
            r.learnSource.from, money(r.learnCost), r.learnReq or r.minSkill)
    else
        learn = ("Learn at a trainer for %s, needs skill %d."):format(money(r.learnCost or 0), r.learnReq or r.minSkill)
    end
    for _, t in ipairs(r.toolsMissing or {}) do
        learn = learn .. ("\nNeeds a |cffffffff%s|r, which you don't carry (about %s)."):format(t.name, money(t.cost))
    end
    if station(r) then learn = learn .. ("\nCraft it next to a |cffffffff%s|r."):format(station(r)) end
    local f = text("GameFontHighlightSmall", x0, y, CONTENT - x0 - 4, learn .. "\n" .. colourRange(r), "LEFT", true)
    y = y + f:GetStringHeight() + 6
    for _, rg in ipairs(st.reagents) do
        local how = rg.source == "craft" and ("you craft it (" .. (rg.via.name or "?") .. ")") or SOURCE[rg.source] or "?"
        tex(itemIcon(rg.itemID), x0, y, 18, 18)
        text("GameFontHighlightSmall", x0 + 24, y + 3, 300, ("%d x %s  |cff888888per craft, %s|r"):format(rg.perCraft,
            itemName(rg.itemID), how))
        text("GameFontHighlightSmall", CONTENT - 160, y + 3, 154, ("%d total"):format(rg.total), "RIGHT")
        y = y + 20
    end
    local back = r.productID and (" Vendoring them returns %s."):format(money(st.sellBack)) or ""
    f = text("GameFontDisableSmall", x0, y + 2, CONTENT - x0 - 4,
        ("This step: spend %s on materials.%s"):format(money(st.cash), back), "LEFT", true)
    y = y + f:GetStringHeight() + 10
end

-- Gathering professions (Mining, Herbalism, Skinning) level mostly by gathering, which no recipe
-- plan can show. Returns the kind ("mining"...) or nil.
local function gatherKind(prof)
    local G = ns.Gather
    return G and prof.skillLine and G.lines[prof.skillLine] or nil
end

-- Zones for your skill band and faction (Wowhead's Forever guides plus node counts), each with a
-- button that draws its gathering loop on the world map and minimap.
local function zoneList(prof, kind)
    local bands = ns.Routes and ns.Routes[kind]
    if not bands or #bands == 0 then return end
    local rank = prof.rank or 0
    local band = bands[#bands]
    for _, b in ipairs(bands) do if rank >= b.from and rank < b.to then band = b; break end end
    local side = UnitFactionGroup and UnitFactionGroup("player")
    side = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    local label = ns.Gather.label[kind] or kind
    text("GameFontNormal", 4, y, CONTENT - 8, ("Where to go for %d-%d"):format(band.from, band.to))
    y = y + 20
    local active = ns.Map and ns.Map.active and ns.Map.active()
    -- How easy each zone is to reach from where you are: the zone you're in first, then by
    -- distance on your continent (a known flight path there counts as close), other continents last.
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local py, px, _, pinst
    if UnitPosition then py, px, _, pinst = UnitPosition("player") end
    local taxi = ns.Recipes.char().taxi or {}
    local function reach(z)
        if here == z.map then return 0, "you are here" end
        local zone = ns.Zones and ns.Zones[z.area]
        local zname = zone and zone[2]:lower()
        local fp = false
        if zname then
            -- "Crossroads, The Barrens" / "Stormwind, Elwynn": the part after the comma is the zone
            -- or the start of its name (Elwynn -> Elwynn Forest, Stranglethorn -> Stranglethorn Vale).
            for name in pairs(taxi) do
                local where = (name:match(",%s*(.+)$") or name):lower()
                if zname == where or zname:sub(1, #where + 1) == where .. " " then fp = true; break end
            end
        end
        local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, z.map, CreateVector2D(0.5, 0.5))
        if not (ok and pos and px and inst == pinst) then return 1e9, "other continent (boat or zeppelin)" end
        local d = math.sqrt((pos.x - px) ^ 2 + (pos.y - py) ^ 2)
        if fp then return math.min(d, 1500), ("flight path known, %.1f km"):format(d / 1000) end
        return d, ("%.1f km away"):format(d / 1000)
    end
    -- Skinning: beasts must suit your character level too. A zone whose beasts are more than 2
    -- levels above you goes to the end of the list (marked); if your skill range has no zone at
    -- your level, zones from the next range down (easier beasts, fewer skill-ups) are offered too.
    local plevel = kind == "skinning" and UnitLevel and UnitLevel("player") or nil
    local function beastLevel(z) -- highest beast level along the loop, from "Name 36-37" strings
        local top
        for _, m in ipairs(z.mobs or {}) do
            local hi = tonumber(m:match("(%d+)%s*$"))
            if hi and (not top or hi > top) then top = hi end
        end
        return top
    end
    local mains = {}
    local function collect(b, lower)
        for i, z in ipairs(b.zones) do
            if not z.hotspot and (z.side == "C" or not side or z.side == side) then
                local ok, score, note = pcall(reach, z)
                score, note = ok and score or 1e8, ok and note or nil
                local top = plevel and beastLevel(z)
                local over = top and top - plevel or 0
                local extra
                if over > 2 then
                    score = score + 1e10 * over
                    extra = ("beasts up to level %d: above your level %d"):format(top, plevel)
                elseif lower then
                    score = score + 2000 -- a little behind same-range zones at your level
                    extra = "easier beasts (fewer skill-ups), at your level"
                end
                mains[#mains + 1] = { z = z, i = i + (lower and 100 or 0), score = score, note = note, extra = extra }
            end
        end
    end
    collect(band, false)
    if plevel then
        local fits = false
        for _, m in ipairs(mains) do if not (m.extra and m.extra:find("above")) then fits = true end end
        if not fits then
            for bi, b in ipairs(bands) do
                if b == band and bands[bi - 1] then collect(bands[bi - 1], true) end
            end
        end
    end
    table.sort(mains, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.i < b.i end)
    do -- one row per zone (a zone can be in two skill ranges): keep the better-ranked one
        local seen, kept = {}, {}
        for _, m in ipairs(mains) do
            if not seen[m.z.area] then seen[m.z.area] = true; kept[#kept + 1] = m end
        end
        mains = kept
    end
    -- Up to 4 zones; a zone's hot spots (mines, dense clusters) appear under it once its route is shown.
    -- The most reachable zone is shown; the others sit in a closed "Other viable zones" list.
    -- Hot spots are one info line per zone (they're drawn in yellow with the zone's route).
    -- Compact rows: name and a one-line summary; click the name for the details.
    UI.zoneOpen = UI.zoneOpen or {}
    local rows = {}
    local function addZone(m)
        local n, caves = 0, {}
        for _, o in ipairs(band.zones) do
            if o.hotspot and o.area == m.z.area then
                n = n + 1
                if o.cave and o.entrance then
                    caves[#caves + 1] = ("%s (cave), entrance at %.0f, %.0f"):format(o.name or "cave", o.entrance[1], o.entrance[2])
                end
            end
        end
        rows[#rows + 1] = { z = m.z, note = m.note, extra = m.extra, spots = n, caves = caves }
    end
    if mains[1] then addZone(mains[1]) end
    if #mains > 1 then
        rows[#rows + 1] = { toggle = true, count = #mains - 1 }
        if UI.zonesOpen then for k = 2, math.min(6, #mains) do addZone(mains[k]) end end
    end
    for _, row in ipairs(rows) do
        local z = row.z
        if row.toggle then
            button((UI.zonesOpen and "- " or "+ ") .. ("Other viable zones (%d)"):format(row.count), 10, 220, function()
                UI.zonesOpen = not UI.zonesOpen
                UI.show(lastState)
            end)
            y = y + 30
        else
            local zone = ns.Zones and ns.Zones[z.area]
            local name = (zone and zone[2] or ("zone " .. z.area)) .. (z.variant and (" (" .. z.variant .. ")") or "")
            local key = band.from .. ":" .. z.area
            local open = UI.zoneOpen[key]
            -- summary: loop length, how far, and one short warning when it matters
            local sum = {}
            if z.len then sum[#sum + 1] = ("%.1f km loop"):format(z.len / 1000) end
            if row.note then sum[#sum + 1] = (row.note:gsub(" %(boat or zeppelin%)", "")) end
            if row.extra then
                sum[#sum + 1] = row.extra:find("above") and "|cffff8040above your level|r" or "|cffffd100easier beasts|r"
            end
            clickable(32, function()
                UI.zoneOpen[key] = not open or nil
                UI.show(lastState)
            end)
            text("GameFontHighlight", 10, y + 1, CONTENT - 160, (open and "- " or "+ ") .. name)
            text("GameFontDisableSmall", 22, y + 17, CONTENT - 172, table.concat(sum, "  -  "))
            if z.route and ns.Map then
                local isActive = active and active.map == z.map and active.route and active.route[1] == z.route[1] and active.route[2] == z.route[2]
                button(isActive and "Hide route" or "Show route", CONTENT - 134, 128, function()
                    if isActive then
                        ns.Map.clear()
                    else
                        local spots = {}
                        for _, o in ipairs(band.zones) do if o.hotspot and o.area == z.area then spots[#spots + 1] = o end end
                        ns.Map.show(z, ("%s %d-%d: %s"):format(label, band.from, band.to, name), spots)
                        ns.Map.waypoint()
                        if ns.Map.openMap then ns.Map.openMap() end
                        print(("|cff33ccffProfPath|r: route for %s shown on your world map and minimap (waypoint set)%s. /pp route off hides it.")
                            :format(name, #spots > 0 and (", with %d hot spot%s in yellow on the world map"):format(#spots, #spots > 1 and "s" or "") or ""))
                    end
                    UI.show(lastState)
                end)
            end
            y = y + 34
            if open then
                -- details: everything else about this zone
                local d = {}
                if z.mobs and #z.mobs > 0 then d[#d + 1] = "Beasts: " .. table.concat(z.mobs, ", ") .. "." end
                local covered = z.nodes and z.share and math.floor(z.nodes * z.share + 0.5)
                if covered then d[#d + 1] = ("%d %s along the loop."):format(covered, kind == "skinning" and "beast spawns" or "nodes") end
                if row.extra then d[#d + 1] = row.extra:sub(1, 1):upper() .. row.extra:sub(2) .. "." end
                if z.guide then d[#d + 1] = "Recommended by the WoW: Forever guides." end
                if z.side == "C" then d[#d + 1] = "Contested zone: watch for the other faction." end
                if row.spots > 0 then
                    d[#d + 1] = ("%d hot spot%s nearby (mines, dense clusters), drawn in yellow with the route."):format(row.spots, row.spots > 1 and "s" or "")
                end
                for _, c in ipairs(row.caves) do d[#d + 1] = c .. "." end
                local f = text("GameFontHighlightSmall", 22, y - 2, CONTENT - 30, table.concat(d, " "), "LEFT", true)
                y = y + (f.GetStringHeight and f:GetStringHeight() or 12) + 8
            end
        end
    end
    y = y + 4
end

-- Do it tab for gathering professions: a short action card instead of the Plan tab's full advice.
local function gatherCard(prof, kind, state)
    local rank, max = prof.rank or 0, prof.max or 0
    local bands = ns.Routes and ns.Routes[kind] or {}
    local band, nextBand
    for i, b in ipairs(bands) do
        if rank >= b.from and rank < b.to then band, nextBand = b, bands[i + 1]; break end
    end
    -- skill bar to the end of this range
    local top = band and math.min(band.to, max > 0 and max or band.to) or max
    tex(nil, 0, y, CONTENT, 64, 0.2, 0.5, 1, 0.15)
    tex(nil, 0, y, 4, 64, 0.25, 0.8, 0.35, 1)
    text("GameFontNormalLarge", 14, y + 8, CONTENT - 20, ("%s %d"):format(ns.Gather.label[kind] or kind, rank))
    local barY = y + 36
    local from = band and band.from or 0
    local frac = math.max(0, math.min(1, (rank - from) / math.max(1, top - from)))
    tex(nil, 14, barY, CONTENT - 28, 14, 0, 0, 0, 0.5)
    if frac > 0 then tex(nil, 14, barY, (CONTENT - 28) * frac, 14, 0.25, 0.6, 1, 0.9) end
    text("GameFontHighlightSmall", 14, barY + 1, CONTENT - 28, ("Skill %d / %d"):format(rank, top), "CENTER")
    y = y + 74
    -- your route: the one shown, or the best zone from the Plan tab
    local active = ns.Map and ns.Map.active and ns.Map.active()
    if active then
        para(("|cffffd100Following:|r %s. Ride the loop; tracked nodes and beasts show on the minimap."):format(active.label or "your route"))
        button("Hide route", 4, 160, function() ns.Map.clear(); UI.show(state) end)
        button("Open map", 172, 160, function() if ns.Map.openMap then ns.Map.openMap() end end)
        y = y + 32
    elseif band and #(band.zones or {}) > 0 then
        para("|cffffd100No route shown yet.|r Pick a zone and show its route on the Plan tab.")
        button("Plan tab: pick a zone", 4, 200, function() UI.setTab(2) end)
        y = y + 32
    end
    -- what's next
    local nxt = {}
    if band and nextBand and band.to <= max then
        nxt[#nxt + 1] = ("At %d the best zones change (Plan tab shows them)."):format(band.to)
    end
    if max > 0 and max < 300 and rank >= max - 25 then
        nxt[#nxt + 1] = ("Your cap is %d: train the next rank at a trainer to keep leveling."):format(max)
    end
    if #nxt > 0 then para("|cffffd100Next:|r " .. table.concat(nxt, " ")) end
end

-- What to gather at your skill, as one paragraph.
local function gatherNote(prof)
    local G, kind, rank = ns.Gather, gatherKind(prof), prof.rank or 0
    if not kind then return end
    local text
    if kind == "mining" then
        local parts = {}
        for _, r in ipairs(G.miningRoute) do
            if r[2] > rank then parts[#parts + 1] = ("%s %d-%d"):format(itemName(r[3]), r[1], r[2]) end
        end
        text = "|cffffd100Mining levels mostly by mining ore nodes:|r " .. table.concat(parts, ", ")
            .. ". Smelting gives extra points; recipes here use ore you mine yourself when the auction house has none."
    elseif kind == "herbalism" then
        local now, nextReq, nextNames = {}, nil, {}
        for id, g in pairs(G.items) do
            if g[1] == "herbalism" then
                if g[2] <= rank and g[2] > rank - 50 then now[#now + 1] = { g[2], itemName(id) } end
                if g[2] > rank and (not nextReq or g[2] < nextReq) then nextReq = g[2] end
            end
        end
        for id, g in pairs(G.items) do
            if g[1] == "herbalism" and g[2] == nextReq then nextNames[#nextNames + 1] = itemName(id) end
        end
        table.sort(now, function(a, b) return a[1] > b[1] end)
        local names = {}
        for k = 1, math.min(4, #now) do names[k] = now[k][2] end
        text = "|cffffd100Herbalism levels by picking herbs.|r"
            .. (#names > 0 and (" Best for you now: " .. table.concat(names, ", ") .. ".") or "")
            .. (nextReq and (" At %d you can pick %s."):format(nextReq, table.concat(nextNames, " and ")) or "")
    elseif kind == "skinning" then
        local maxLevel = rank < 100 and (10 + math.floor(rank / 10)) or math.floor(rank / 5)
        text = ("|cffffd100Skinning levels by skinning beasts.|r At %d you can skin creatures up to about level "
            .. "%d; the closer to that level, the more often you get a point."):format(rank, maxLevel)
    elseif kind == "fishing" then
        text = "|cffffd100Fishing levels by fishing.|r Points come quickly at first and slow down as your skill "
            .. "rises. When fish keep getting away, the water is too hard for your skill: a better fishing pole or a "
            .. "lure helps, or fish in an easier zone."
        -- What to do next, by skill (WoW: Forever): lures and how each rank is learned.
        local max = prof.max or 0
        local tip, npc
        if rank < 75 then
            tip = "Any lake or river in a starting zone works. A Shiny Bauble lure helps."
                .. (rank >= 50 and max <= 75 and " You can train Journeyman Fishing now (Fishing 50, level 10) at a fishing trainer." or "")
        elseif rank < 150 then
            tip = "Fish in a capital city, or The Barrens, Darkshore, Loch Modan, Silverpine Forest or Westfall. Nightcrawlers stop fish getting away."
            if rank >= 125 and max <= 150 then
                tip = tip .. " Expert Fishing comes from the book \"Expert Fishing - The Bass and You\", sold by Old Man Heming in Booty Bay (level 20, Fishing 125)."
                npc = { mapID = 1434, x = 0.274, y = 0.770, npc = "Old Man Heming", label = "Waypoint: Old Man Heming" }
            end
        elseif rank < 225 then
            tip = "Fish in Dustwallow Marsh (or Stranglethorn, Desolace, Arathi Highlands) with Bright Baubles from Old Man Heming."
            if rank >= 200 and max <= 225 then
                tip = tip .. " Artisan Fishing needs the quest \"Nat Pagle, Angler Extreme\" from Nat Pagle in Dustwallow Marsh (level 35, Fishing 225): catch four fish in Feralas, Swamp of Sorrows, Desolace and Stranglethorn Vale."
                npc = { mapID = 1445, x = 0.585, y = 0.600, npc = "Nat Pagle", label = "Waypoint: Nat Pagle" }
            end
        else
            tip = "Fish in the higher zones (such as Tanaris, Feralas or Azshara) with Bright Baubles so fish don't get away."
        end
        text = text .. "\n" .. tip
        if npc then
            para(text)
            button(npc.label, 4, 220, function()
                ns.Recipes.waypoint(npc)
                print(("|cff33ccffProfPath|r: waypoint set to %s."):format(npc.npc))
            end)
            y = y + 30
            text = nil
        end
    end
    if text then para(text) end
    zoneList(prof, kind)
    return kind
end

local function renderPlan(state)
    local prof, res, info = state.prof, state.result, state.info
    local kind = gatherKind(prof)
    -- A gathering profession with no crafting route: say so plainly instead of "not enough gold".
    if kind and (res.broke or not res.ok or #res.steps == 0) and not (res.ok and #res.steps == 0
            and (prof.rank or 0) >= (state.target or 0)) then
        stepTitle(2, "Nothing to buy: " .. (ns.Gather.label[kind] or "this profession") .. " levels by gathering",
            "Crafting can't level it from here, so there is no shopping list. Here is what to gather instead.")
        gatherNote(prof)
        button("<  Back to Prepare", 4, 180, function() UI.setTab(1) end)
        y = y + 32
        return
    end
    if res.broke then
        local b = state.budget
        stepTitle(2, "Not enough gold for the next point",
            ("You have %s to spend%s. Even one more skill point costs more than that."):format(money(b and b.gold or 0),
                b and b.mode == "upfront" and " up front" or ""))
        para("Try |cffffffffFit to gold: Batches|r on the Prepare tab (vendoring as you go needs far less gold), "
            .. "lower the reserve (/pp reserve 0), or earn a little more.")
        button("<  Back to Prepare", 4, 180, function() UI.setTab(1) end)
        y = y + 32
        return
    end
    if not res.ok then
        stepTitle(2, "No path yet",
            ("Stuck at skill %d: every recipe that still gives points has an unpriced material."):format(res.stuckAt or 0))
        button("<  Back to Prepare", 4, 180, function() UI.setTab(1) end)
        y = y + 32
        return
    end
    if #res.steps == 0 then
        stepTitle(2, "Nothing to do", "You are already at the target skill.")
        return
    end
    local b = state.budget
    local crafts = 0
    for _, st in ipairs(res.steps) do crafts = crafts + math.ceil(st.expectedCrafts - 1e-9) end
    for _, it in ipairs(res.intermediates or {}) do crafts = crafts + it.crafts end
    stepTitle(2, ("Your path: %d -> %d"):format(prof.rank or 0, state.target or 0),
        state.committed and ("Your locked plan from here, %d crafts. Click a step to see what it needs."):format(crafts)
            or ("The cheapest route with current prices, %d crafts in total. Click a step to see what it needs."):format(crafts))
    lockBanner(state)
    alertBanner(state)
    gatherNote(prof)

    local spend = (res.cash or 0) + (res.learnTotal or 0)
    cards({
        { label = "Gold to spend", value = money(spend) },
        { label = "Back from vendor", value = money(res.sellBack), r = 0.3, g = 0.8, b = 0.3 },
        { label = "Net cost", value = money(spend - (res.sellBack or 0)), r = 0.3, g = 0.6, b = 1 },
        { label = not b and "Your gold (not used)" or b.custom and "Your budget" or "Your gold",
            value = money(b and b.custom and b.gold or (GetMoney and GetMoney() or 0)), r = 0.7, g = 0.7, b = 0.7 },
    })

    -- Budget: say how far the gold reaches and what finishing would take.
    if b and b.limited then
        local more = b.fullCost and (" Reaching %d would cost %s%s in total."):format(b.full, money(b.fullCost),
            b.mode == "batch" and " net" or "") or ""
        tex(nil, 0, y, CONTENT, 26, 0.3, 0.6, 1, 0.15)
        tex(nil, 0, y, 3, 26, 0.3, 0.6, 1, 0.9)
        text("GameFontHighlight", 10, y + 7, CONTENT - 16, ("%s takes you to |cffffffff%d|r of %d.%s")
            :format(b.custom and ("A budget of " .. money(b.gold)) or "Your gold", b.reach, b.full, more))
        y = y + 32
    end
    if b and b.mode == "batch" and spend > b.gold then
        para(("|cff888888You don't need all %s at once: buy for a batch, craft, vendor the results, repeat "
            .. "(see Do it).|r"):format(money(spend)))
    end

    for i, row in ipairs(withRanks(res, prof.max or 0)) do
        if row.rank then
            rankRow(row.rank, row.fromCap, { zebra = i % 2 == 0 }, prof.name)
        else
            local st = row.step
            local key = st.recipe.id .. ":" .. st.fromSkill
            local open = state.selected == key
            local estLearn = st.recipe.learnSource and st.recipe.learnSource.estimated and " |cffaaaaaa(est.)|r" or ""
            line(itemIcon(st.recipe.productID),
                ("|cff33ccff%d - %d|r   %s%s"):format(st.fromSkill, st.toSkill, st.recipe.name or "?",
                    st.recipe.estimated and " |cffaaaaaa(est.)|r" or ""),
                ("%d crafts%s"):format(math.ceil(st.expectedCrafts - 1e-9),
                    st.learnCost > 0 and (("  -  %s %s%s"):format(st.recipe.toolsMissing and (st.recipe.learned and "tool" or "learn + tool")
                        or "learn for", money(st.learnCost), estLearn)) or ""),
                money(st.cost - (st.learnCost or 0)) .. " |cff888888net|r",
                { zebra = i % 2 == 0, highlight = open, onClick = function()
                    state.selected = (state.selected ~= key) and key or nil
                    UI.show(state)
                end })
            if open then renderStepDetail(st) end
        end
    end

    if state.partialStop and kind then
        y = y + 4
        para(("|cffff8800Crafting stops giving points at %d. From there, gathering (see above) is how you level.|r")
            :format(state.partialStop))
    elseif state.partialStop then
        y = y + 4
        para(("|cffff8800The plan stops at %d: past that, no recipe has priced materials and a known way to learn it. "
            .. "Scan the auction house or visit a trainer, then it will reach further.|r"):format(state.partialStop))
    end
    local notes = {}
    if (info.estimatedLearn or 0) > 0 then
        notes[#notes + 1] = info.estimatedLearn .. " trainer recipes past your cap use estimated costs"
    end
    if info.unknownLearn > 0 then notes[#notes + 1] = info.unknownLearn .. " recipes skipped (no way to learn known)" end
    if (info.specSkipped or 0) > 0 then notes[#notes + 1] = info.specSkipped .. " need a specialization you don't have" end
    if (info.cooldownSkipped or 0) > 0 then notes[#notes + 1] = info.cooldownSkipped .. " have a long cooldown" end
    if (info.toolSkipped or 0) > 0 then notes[#notes + 1] = info.toolSkipped .. " need a tool with no known price" end
    if res.missing and #res.missing > 0 then notes[#notes + 1] = #res.missing .. " materials have no price" end
    local gathered = 0
    for _, s in ipairs(res.shopping or {}) do if s.source == "gather" then gathered = gathered + 1 end end
    if gathered > 0 then notes[#notes + 1] = gathered .. " materials you gather yourself (valued at their vendor price)" end
    if state.ms then notes[#notes + 1] = ("calculated in %d ms"):format(floor(state.ms + 0.5)) end
    if #notes > 0 then y = y + 6; para("|cff888888" .. table.concat(notes, "  -  ") .. "|r") end

    y = y + 6
    button("<  Prepare", 4, 140, function() UI.setTab(1) end)
    button("Next:  start leveling  >", CONTENT - 200, 196, function() UI.setTab(3) end)
    y = y + 32
end

-- ---------- tab 3: do it ----------

local function renderDo(state)
    local prof, res = state.prof, state.result
    if not res.ok or #res.steps == 0 then
        local kind = gatherKind(prof)
        if kind then
            stepTitle(3, "Go gathering", (ns.Gather.label[kind] or "This profession")
                .. " levels by gathering: nothing to buy or craft right now.")
            gatherCard(prof, kind, state)
            return
        end
        stepTitle(3, "Nothing to do yet", "Finish Prepare and check the Plan first.")
        return
    end
    stepTitle(3, "Do it", "Work through these in order. Ticks update as you learn, buy and craft. The plan "
        .. "stays as it is; you'll be told if a clearly cheaper path appears.")
    lockBanner(state)
    alertBanner(state)

    local b = state.budget
    local function bagCount(id)
        local count = (C_Item and C_Item.GetItemCount) or GetItemCount
        return id and count and count(id, true) or 0
    end
    local function learnText(r)
        if r.learnSource and r.learnSource.kind == "item" then
            return ("Buy %s (%s), needs skill %d"):format(itemName(r.learnSource.itemID), r.learnSource.from, r.learnReq or 0)
        end
        if r.learnSource and r.learnSource.estimated then
            return ("At the trainer, needs about skill %d (estimated until the trainer lists it)"):format(r.learnReq or r.minSkill)
        end
        return ("At the trainer, needs skill %d"):format(r.learnReq or r.minSkill)
    end

    -- ---- Now: the current step, in the order you do it ----
    local st = res.steps[1]
    local r = st.recipe
    local n = 0
    local function num() n = n + 1; return ("|cffffd100%d.|r  "):format(n) end

    -- Rank training due now (you have the skill for it): do that first, then re-plan.
    local rk = res.rankUps and res.rankUps[1]
    if rk and (prof.rank or 0) >= rk.req then
        section("|cffffd100Rank up first|r")
        line(ICON_BOOK, num() .. ("Train %s at a %s trainer"):format(rk.name, prof.name),
            ("cap %d -> %d. ProfPath re-plans with the new recipes as soon as you have it."):format(prof.max or 0, rk.cap),
            money(rk.cost), { status = ICON_TODO, highlight = true })
        trainerHint(prof.name, rk.name)
    end
    section(("Now:  %s  |cff33ccff%d -> %d|r"):format(r.name or "?", st.fromSkill, st.toSkill))

    -- 1. learn
    if not r.learned then
        line(itemIcon(r.productID), num() .. "Learn " .. (r.name or "?"), learnText(r), money(r.learnCost or 0),
            { status = ICON_TODO })
        if not (r.learnSource and r.learnSource.kind == "item") then trainerHint(prof.name) end
    else
        line(itemIcon(r.productID), num() .. "Learn " .. (r.name or "?"), "You know this recipe.", nil, { status = ICON_OK })
    end
    -- Tools this recipe needs that you don't carry (rods, hammers, spanners).
    local HOW = { vendor = "Sold by vendors", AH = "On the auction house",
        craft = "You can craft it (cheaper than buying)" }
    for _, t in ipairs(r.toolsMissing or {}) do
        line(t.itemID and itemIcon(t.itemID) or nil, num() .. "Get a " .. t.name,
            (HOW[t.how] or "Needed to craft this recipe") .. "; keep it in your bags.", money(t.cost),
            { status = ICON_TODO })
    end

    -- Batch mode: if this step's materials cost more than the budget (after any learn cost), show
    -- one batch: as many crafts as the budget buys. After crafting and vendoring, the bag counts
    -- drop and the list shows the next batch.
    local crafts = math.ceil(st.expectedCrafts - 1e-9)
    local batchCrafts
    if b and b.mode == "batch" and crafts > 0 then
        local avail = b.gold - ((not r.learned) and (st.learnCost or 0) or 0)
        local perCraft = st.cash / st.expectedCrafts
        if st.cash > avail and perCraft > 0 then
            batchCrafts = math.max(1, math.min(crafts, floor(avail / perCraft)))
            if batchCrafts >= crafts then batchCrafts = nil end
        end
    end
    local scale = batchCrafts and batchCrafts / st.expectedCrafts or 1

    -- 2. buy what this step (or this batch) needs
    if batchCrafts then
        local batches = math.ceil(crafts / batchCrafts)
        tex(nil, 0, y, CONTENT, 40, 1, 0.82, 0, 0.12)
        tex(nil, 0, y, 3, 40, 1, 0.82, 0, 0.9)
        text("GameFontHighlight", 10, y + 5, CONTENT - 16, ("Batch 1 of ~%d:  buy for |cffffffff%d crafts|r (about %s)")
            :format(batches, batchCrafts, money(st.cash * scale)))
        text("GameFontDisableSmall", 10, y + 22, CONTENT - 16,
            "Craft them, vendor the results, then come back: this list updates from your bags for the next batch.")
        y = y + 46
    end
    -- Work out what is still missing, top-down from what is in your bags: reagents of the recipe
    -- first come out of the bags; any shortfall of a crafted reagent (e.g. Cured Light Hide) becomes
    -- crafts, and only those crafts need raw materials. So hides already crafted are never re-bought.
    local short, used, craftsLeft = ns.Optimizer.remaining(r, batchCrafts or crafts, st.intermediates, bagCount)

    for i, m in ipairs(st.materials) do
        local buy = math.ceil((short[m.itemID] or 0) - 1e-9)
        local have, use = bagCount(m.itemID), used[m.itemID] or 0
        local sub
        if buy == 0 and use == 0 then sub = "not needed: covered by what you already crafted"
        else sub = ("have %d, using %d  -  %s  -  %s each"):format(have, use, SOURCE[m.source] or "?", money(m.unitCost)) end
        line(itemIcon(m.itemID), (i == 1 and num() or "      ") .. ((m.source == "gather" and "Gather" or "Buy") .. " %s  |cff888888x%d|r"):format(itemName(m.itemID), buy),
            sub, buy == 0 and "|cff40c040done|r" or m.source == "gather" and "|cff888888gather|r" or money(m.unitCost * buy),
            { status = buy == 0 and ICON_OK or ICON_TODO, zebra = i % 2 == 0 })
    end

    -- 3. intermediates still to craft
    for _, it in ipairs(st.intermediates) do
        local left = craftsLeft[it.recipe] or 0
        local have = bagCount(it.recipe.productID)
        local parts = {}
        for _, rg in ipairs(it.recipe.reagents) do parts[#parts + 1] = rg[2] .. "x " .. itemName(rg[1]) end
        line(itemIcon(it.recipe.productID), num() .. ("Craft %s  |cff888888x%d|r"):format(it.recipe.name or "?", left),
            left == 0 and ("you have enough (%d)"):format(have) or ("each from " .. table.concat(parts, ", ")
                .. (station(it.recipe) and ("  -  at a " .. station(it.recipe)) or "")),
            ("have %d"):format(have), { status = left == 0 and ICON_OK or ICON_TODO, rightW = 90 })
    end

    -- 4. level: a large card with skill progress and a luck panel
    local rank = prof.rank or st.fromSkill
    local stepStart = st.fromSkill
    for _, ls in ipairs(state.committed and state.committed.steps or {}) do
        if ls[3] == r.id and rank >= ls[1] and rank < ls[2] then stepStart = ls[1] end
    end
    local cardTop = y
    local cardH = 112
    tex(nil, 0, y, CONTENT, cardH, 0.2, 0.5, 1, 0.18)
    tex(nil, 0, y, 4, cardH, 0.25, 0.8, 0.35, 1)
    tex(itemIcon(r.productID), 14, y + 12, 36, 36)
    text("GameFontNormalLarge", 60, y + 10, CONTENT - 70, num() .. ("Craft %s until skill %d"):format(r.name or "?", st.toSkill))
    text("GameFontHighlight", 60, y + 32, CONTENT - 70, (batchCrafts
        and ("|cffffffff%d|r crafts this batch  -  about %d to go in total"):format(batchCrafts, crafts)
        or ("about |cffffffff%d|r crafts to go"):format(crafts))
        .. (station(r) and ("  -  |cffffd100at a %s|r"):format(station(r)) or ""))

    -- skill bar: from where this step started to its target
    local barX, barW, barY = 60, CONTENT - 76, y + 54
    local frac = math.max(0, math.min(1, (rank - stepStart) / math.max(1, st.toSkill - stepStart)))
    tex(nil, barX, barY, barW, 14, 0, 0, 0, 0.5)
    if frac > 0 then tex(nil, barX, barY, barW * frac, 14, 0.25, 0.6, 1, 0.9) end
    text("GameFontHighlightSmall", barX, barY + 1, barW, ("Skill %d / %d"):format(rank, st.toSkill), "CENTER")

    -- luck: points gained vs. the sum of the skill-up chances of each craft made
    local lc, lp, le
    if ns.Track then lc, lp, le = ns.Track.luckData(r.id) end
    if lc then
        local diff = lp - le
        local pNow = ns.Optimizer.chance(r, rank)
        local verdict, colour
        if diff >= 1 and lp >= 1.15 * le then verdict, colour = ("Lucky  +%.1f points"):format(diff), "|cff40ff40"
        elseif diff <= -1 and lp <= 0.85 * le then verdict, colour = ("Unlucky  %.1f points"):format(diff), "|cffff6040"
        else verdict, colour = "On track", "|cffffffff" end
        local craftsEffect = ""
        if pNow > 0 and math.abs(diff) >= 1 then
            craftsEffect = ("  (about %d crafts %s)"):format(floor(math.abs(diff) / pNow + 0.5), diff > 0 and "saved" or "extra")
        end
        text("GameFontHighlight", 60, y + 76, CONTENT - 220,
            ("%d crafts gave |cffffffff%d|r points, %.1f expected"):format(lc, lp, le))
        text("GameFontNormalLarge", CONTENT - 220, y + 74, 210, colour .. verdict .. "|r", "RIGHT")
        text("GameFontDisableSmall", 60, y + 94, CONTENT - 70,
            ("Chance per craft now: %d%%%s"):format(floor(pNow * 100 + 0.5), craftsEffect))
    else
        text("GameFontDisableSmall", 60, y + 78, CONTENT - 70,
            ("Luck shows here once you start crafting. Chance per craft now: %d%%."):format(
                floor(ns.Optimizer.chance(r, rank) * 100 + 0.5)))
    end
    y = cardTop + cardH + 6
    if batchCrafts and r.productID then
        para(("|cff888888Then vendor the %s: each batch returns about %s.|r"):format(itemName(r.productID),
            money(st.sellBack * scale)))
    end
    if not ProfPathDB.options.track then para("|cff888888Live tracking is off (/pp track on).|r") end

    -- ---- Later: one compact row per following step; click to see its shopping list ----
    local laterRows = {}
    for idx, row in ipairs(withRanks(res, prof.max or 0)) do
        if row.rank then
            if not (rk and row.rank == rk and (prof.rank or 0) >= rk.req) then laterRows[#laterRows + 1] = row end
        elseif row.step ~= st then
            laterRows[#laterRows + 1] = row
        end
    end
    if #laterRows > 0 then
        section("|cff888888Later|r")
        state.expanded = state.expanded or {}
        for i, row in ipairs(laterRows) do
          if row.rank then
            rankRow(row.rank, row.fromCap, { zebra = i % 2 == 0 }, prof.name)
          else
            local ls = row.step
            local lr = ls.recipe
            local key = lr.id .. ":" .. ls.fromSkill
            local bits = {}
            if not lr.learned then bits[#bits + 1] = ("learn (%s)"):format(money(ls.learnCost or 0)) end
            for j = 1, math.min(2, #ls.materials) do
                bits[#bits + 1] = ("%d %s"):format(ls.materials[j].qty, itemName(ls.materials[j].itemID))
            end
            if #ls.materials > 2 then bits[#bits + 1] = "..." end
            bits[#bits + 1] = ("~%d crafts"):format(math.ceil(ls.expectedCrafts - 1e-9))
            local cost = ls.cash + (ls.learnCost or 0)
            local inBatches = b and b.mode == "batch" and cost > b.gold
            line(itemIcon(lr.productID), ("|cffaaaaaaAt skill %d:  %s|r"):format(ls.fromSkill, lr.name or "?"),
                table.concat(bits, "  -  "),
                ("|cff888888%s%s|r"):format(money(cost), inBatches and " in batches" or ""),
                { zebra = i % 2 == 0, onClick = function()
                    state.expanded[key] = not state.expanded[key] or nil
                    UI.show(state)
                end })
            if state.expanded[key] then
                local f = text("GameFontDisableSmall", 40, y, CONTENT - 44, not lr.learned and learnText(lr) or "Known recipe.")
                y = y + f:GetStringHeight() + 4
                for _, m in ipairs(ls.materials) do
                    tex(itemIcon(m.itemID), 40, y, 16, 16)
                    text("GameFontHighlightSmall", 62, y + 2, 300, ("%d x %s  |cff888888%s|r"):format(m.qty,
                        itemName(m.itemID), SOURCE[m.source] or "?"))
                    text("GameFontHighlightSmall", CONTENT - 160, y + 2, 154, money(m.lineCost), "RIGHT")
                    y = y + 18
                end
                for _, it in ipairs(ls.intermediates) do
                    text("GameFontHighlightSmall", 62, y + 2, 400, ("then craft %s x%d"):format(it.recipe.name or "?", it.crafts))
                    y = y + 18
                end
                y = y + 4
            end
          end
        end
    end

    y = y + 6
    button("<  Plan", 4, 140, function() UI.setTab(2) end)
    y = y + 32
end

-- ---------- render ----------

local function render(state)
    reset()
    for i, b in ipairs(tabs) do
        if i == current then b:LockHighlight() else b:UnlockHighlight() end
    end
    if not state.prof then
        title:SetText("ProfPath")
        UI.profButton:SetText("No profession")
        stepTitle(1, "No crafting profession found", "Open your profession window (K) once so ProfPath can read it.")
        return
    end
    title:SetText(("ProfPath  -  %s %d / %d"):format(state.prof.name, state.prof.rank or 0, state.prof.max or 0))
    local n = state.profs and #state.profs or 1
    UI.profButton:SetText(("%s %d%s"):format(state.prof.name, state.prof.rank or 0, n > 1 and "   " or ""))
    if current == 1 then renderPrepare(state)
    elseif current == 2 then renderPlan(state)
    else renderDo(state) end
end

function UI.show(state)
    -- While a recalculation runs in slices, the state is half-updated: draw when it finishes
    -- (the recalculation itself calls UI.show from inside its coroutine).
    if ns.recalcBusy and not coroutine.running() then UI.setBusy(true); return end
    lastState = state
    if not frame or not frame:IsShown() then return end
    render(state)
    UI.child:SetHeight(y + 20)
end

-- ---------- scan progress (called by Prices on every scan step) ----------

local wasScanning
function UI.scanProgress(p, scanning)
    if not frame then build() end
    if scanning and not frame:IsShown() then frame:Show() end
    showBar(true)
    bar:SetMinMaxValues(0, math.max(p.total, 1))
    bar:SetValue(p.done)
    -- Re-render once when a scan starts or stops, so the Prepare buttons show Stop/Start.
    if wasScanning ~= scanning then
        wasScanning = scanning
        if lastState then UI.show(lastState) end
    end
    if p.label then -- full snapshot: waiting for the server, then reading the results
        local secs = floor(GetTime() - (p.started or GetTime()))
        barText:SetText(p.total > 0 and ("%s %d / %d"):format(p.label, p.done, p.total)
            or ("%s... %ds"):format(p.label, secs))
        return
    end
    local pct = p.total > 0 and floor(p.done / p.total * 100) or 100
    if scanning then
        local what = p.retryIn and ("|cffff8800server busy, retrying in %ds|r"):format(p.retryIn)
            or p.waiting and "waiting for server..." or (p.current and itemName(p.current) or "")
        local extra = (p.timeouts or 0) > 0 and (" |cffff8800%d no reply|r"):format(p.timeouts) or ""
        if (p.skipped or 0) > 0 then extra = extra .. (" |cffaaaaaa%d skipped|r"):format(p.skipped) end
        local eta = ""
        if p.started and p.done >= 3 then
            local left = floor((GetTime() - p.started) / p.done * (p.total - p.done))
            eta = left >= 60 and ("  ~%dm %02ds left"):format(floor(left / 60), left % 60) or ("  ~%ds left"):format(left)
        end
        barText:SetText(("Scanning %d / %d (%d%%)%s  %s%s"):format(p.done, p.total, pct, eta, what, extra))
    else
        barText:SetText(("Scan done: %d with listings, %d skipped as too expensive"):format(p.found, p.skipped or 0))
        C_Timer.After(8, function() if not ns.Prices.scanning then showBar(false) end end)
    end
end
