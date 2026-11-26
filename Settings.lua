-- ProfPath settings: every option in one panel. Opens as its own window (/pp settings, or the
-- Settings button in the ProfPath window) and, when the game client supports it, also appears under
-- the game's AddOns options. Controls are built from plain frames and textures (no newer templates),
-- so they work on any client.
local _, ns = ...
local S = {}
ns.Settings = S

local WIDTH, HEIGHT = 520, 600

-- Route colours to pick from.
S.COLORS = {
    { "Orange", 1, 0.35, 0.15 }, { "Red", 1, 0.15, 0.15 }, { "Yellow", 1, 0.85, 0.1 }, { "Green", 0.3, 1, 0.3 },
    { "Cyan", 0.2, 0.85, 1 }, { "Purple", 0.75, 0.4, 1 }, { "Pink", 1, 0.45, 0.8 }, { "White", 1, 1, 1 },
}

-- Defaults for the options added with this panel (older ones keep theirs in Core.lua).
S.DEFAULTS = {
    useStock = true, alertSound = true, alertScreen = true, scale = 1, openTab = 0,
    routeColor = 1, routeWidth = 3, miniRouteWidth = 2, miniRoute = true, routeWaypoint = true,
    buyStyle = "batch", openWithProfession = false, lockWindow = false, techDetails = false,
}

-- How plans fitted to your gold buy: "batch" (a bit at a time) or "upfront". Follows the current
-- budget mode when it is on, so older saved settings keep their choice.
function S.buyStyle()
    local b = ProfPathDB and ProfPathDB.options and ProfPathDB.options.budget
    if b == "batch" or b == "upfront" then return b end
    return S.get("buyStyle")
end

function S.get(key)
    local o = ProfPathDB and ProfPathDB.options or {}
    local v = o[key]
    if v == nil then return S.DEFAULTS[key] end
    return v
end

-- Route colour as r, g, b.
function S.routeColor()
    local c = S.COLORS[S.get("routeColor")] or S.COLORS[1]
    return c[2], c[3], c[4]
end

local function opt() return ProfPathDB.options end
local function replan() if ns.requestRecalc then ns.requestRecalc() end end
local function restyleMap() if ns.Map and ns.Map.restyle then ns.Map.restyle() end end

-- ---------- controls ----------
-- Every control is a question with its answers in view: radio choices, checkboxes, a few text
-- boxes and colour swatches. S.controls[key] gives tests a handle on each one.

local INNER = 460 -- content width
local controls = {} -- every built control, refreshed when a panel is shown
S.controls = {}

local function register(key, c)
    c.key = key
    controls[#controls + 1] = c
    S.controls[key] = c
    c.refresh()
    return c
end

local function label(parent, text, x, y, font, w)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetPoint("TOPLEFT", x, -y)
    if w then f:SetWidth(w); f:SetJustifyH("LEFT") end
    f:SetText(text)
    return f
end

-- Grey explanation under a question; returns its height.
local function hint(parent, text, x, y)
    if not text then return 0 end
    local t = label(parent, text, x, y, "GameFontDisableSmall", INNER - (x - 8))
    return math.max(12, t:GetStringHeight() or 12) + 4
end

-- One radio button with its label; the label is part of the click area.
local function radio(parent, x, y, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", x, -y)
    b:SetHitRectInsets(0, -(width - 20), 0, 0)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(); t:SetTexture("Interface\\Buttons\\UI-RadioButton")
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(); h:SetTexture("Interface\\Buttons\\UI-RadioButton"); h:SetTexCoord(0.5, 0.75, 0, 1)
    h:SetBlendMode("ADD")
    label(parent, text, x + 20, y + 1, "GameFontHighlight", width - 24)
    b:SetScript("OnClick", onClick)
    function b.select(on) t:SetTexCoord(on and 0.25 or 0, on and 0.5 or 0.25, 0, 1) end
    return b
end

-- A question with answers { value, "Answer" }. opts.cols lays them out in columns; opts.nearest
-- selects the closest answer when the saved number is in between (older saved values).
local function choice(parent, x, y, key, question, tip, list, get, set, opts)
    opts = opts or {}
    local cols = opts.cols or 1
    local top = y
    label(parent, question, x, y, "GameFontNormal")
    y = y + 18
    y = y + hint(parent, tip, x, y)
    local colW = math.floor((INNER - 4) / cols)
    local c = { buttons = {} }
    local function selected()
        local v = get()
        for i, e in ipairs(list) do if e[1] == v then return i end end
        if opts.nearest and type(v) == "number" then
            local best, bd
            for i, e in ipairs(list) do
                local d = type(e[1]) == "number" and math.abs(e[1] - v)
                if d and (not bd or d < bd) then best, bd = i, d end
            end
            return best
        end
    end
    function c.refresh()
        local s = selected()
        for i, b in ipairs(c.buttons) do b.select(i == s) end
    end
    function c.pick(i) set(list[i][1]); S.refresh() end
    function c.selected() return selected() end
    for i, e in ipairs(list) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c.buttons[i] = radio(parent, x + 4 + col * colW, y + row * 22, e[2], colW, function() c.pick(i) end)
    end
    register(key, c)
    return y + math.ceil(#list / cols) * 22 - top
end

local function checkbox(parent, x, y, key, text, tip, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", x, -y)
    b:SetHitRectInsets(0, -(INNER - 40), 0, 0)
    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetAllPoints(); box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    local check = b:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints(); check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    label(parent, text, x + 28, y + 5, "GameFontHighlight", INNER - 36)
    local c = { button = b }
    function c.refresh() if get() then check:Show() else check:Hide() end end
    function c.checked() return get() and true or false end
    function c.toggle() set(not get()); S.refresh() end
    b:SetScript("OnClick", function() c.toggle() end)
    register(key, c)
    return 26 + (tip and hint(parent, tip, x + 28, y + 24) or 0)
end

-- Text box on one line with its label. parse(text) returns ok, value (or false, error message).
local function input(parent, x, y, key, text, tip, get, set, parse, show)
    label(parent, text, x, y + 4, "GameFontHighlight")
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(110, 20)
    box:SetPoint("TOPLEFT", x + 190, -y)
    local c = { box = box }
    function c.refresh() box:SetText(show(get())) end
    local function apply(self)
        local ok, v = parse(self:GetText())
        self:ClearFocus()
        if ok then set(v) else ns.chat(v or "Couldn't read that.") end
        S.refresh()
    end
    function c.type(t) box:SetText(t); apply(box) end
    box:SetScript("OnEnterPressed", apply)
    box:SetScript("OnEditFocusLost", function() c.refresh() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); c.refresh() end)
    register(key, c)
    return 26 + (tip and hint(parent, tip, x + 190, y + 22) or 0)
end

-- Row of colour swatches; the chosen one gets a white frame.
local function swatches(parent, x, y, key, question, colors, get, set)
    label(parent, question, x, y, "GameFontNormal")
    y = y + 20
    local c = { buttons = {} }
    function c.refresh()
        for i, b in ipairs(c.buttons) do if i == get() then b.ring:Show() else b.ring:Hide() end end
    end
    function c.pick(i) set(i); S.refresh() end
    for i, col in ipairs(colors) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(26, 26)
        b:SetPoint("TOPLEFT", x + 4 + (i - 1) * 34, -y)
        b.ring = b:CreateTexture(nil, "BACKGROUND")
        b.ring:SetPoint("TOPLEFT", -3, 3); b.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        b.ring:SetColorTexture(1, 1, 1, 1)
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetAllPoints(); edge:SetColorTexture(0, 0, 0, 1)
        local fill = b:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(col[2], col[3], col[4], 1)
        b:SetScript("OnClick", function() c.pick(i) end)
        b:SetScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(col[1]); GameTooltip:Show() end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c.buttons[i] = b
    end
    register(key, c)
    return 20 + 30
end

local function heading(parent, y, text)
    label(parent, text, 4, y, "GameFontNormalLarge")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 4, -(y + 22))
    line:SetSize(INNER, 1)
    line:SetColorTexture(1, 0.82, 0, 0.4)
    return 30
end

local function money(c)
    if not c then return "" end
    local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    return ("%ds"):format(s)
end

local function parseGold(t)
    if t:match("^%s*$") then return true, nil end
    local c = ns.parseMoney and ns.parseMoney(t)
    if c then return true, c end
    return false, "Couldn't read that amount. Try 5g, 1g 50s or 50s."
end

-- Route line thickness: one choice sets both the world map and the minimap line.
local MINI_FOR = { [2] = 1, [3] = 2, [5] = 3 }

-- ---------- the panel ----------


local function redraw() if ns.requestRedraw then ns.requestRedraw() end end

-- Builds every setting into `parent` (a scroll child). Returns its height.
-- Gold and how far ahead are not here: they're one click away on the Prepare tab.
local function buildInto(parent)
    local x, y = 8, 6
    local function add(h, gap) y = y + h + (gap or 10) end

    y = y + hint(parent, "Your gold and how far ahead to plan are set on the Prepare tab of the ProfPath window.", x, y) + 6

    add(heading(parent, y, "Shopping"))
    add(choice(parent, x, y, "buyStyle", "When ProfPath fits a plan to your gold",
        "Buying a bit at a time lets you reach much further with the same gold.",
        { { "batch", "Buy a bit at a time: buy, craft, sell to a vendor, repeat" },
          { "upfront", "Buy everything before I start crafting" } },
        function() return S.buyStyle() end,
        function(v)
            opt().buyStyle = v
            if (opt().budget or "off") ~= "off" then opt().budget = v end
            replan()
        end), 4)
    add(input(parent, x + 4, y, "reserve", "Always keep at least", "Gold the plan never spends.",
        function() return opt().reserve end,
        function(v) opt().reserve = v; replan() end, parseGold, money))
    add(choice(parent, x, y, "ownedFree", "Materials already in your bags",
        "ProfPath always uses them first. With the first choice, buying for the plan won't change the plan.",
        { { false, "Free if I had them when I started the plan" }, { true, "Always free" } },
        function() return opt().ownedFree and true or false end,
        function(v) opt().ownedFree = v; replan() end), 4)
    add(checkbox(parent, x, y, "useStock", "Make what I need from leftovers I have",
        "For example Heavy Leather from your Medium Leather, or cured hides with salt from a vendor.",
        function() return S.get("useStock") end, function(v) opt().useStock = v; replan() end), 2)
    add(checkbox(parent, x, y, "gather", "Gather materials myself when nobody sells them",
        "Only when you have the gathering profession for them.",
        function() return opt().gather ~= false end, function(v) opt().gather = v; replan() end))

    add(heading(parent, y, "Choosing recipes"))
    add(choice(parent, x, y, "effort", "Cheapest or quickest?", nil,
        { { 0, "Cheapest, however many crafts it takes" }, { 50, "A balance of both" },
          { 200, "Fewer crafts, even if it costs a bit more" } },
        function() return opt().effort or 0 end,
        function(v) opt().effort = v > 0 and v or nil; replan() end, { nearest = true }))
    add(choice(parent, x, y, "resale", "What you craft is worth",
        "Money back from selling what you craft makes a recipe cheaper.",
        { { 0, "Its vendor price (safe)" }, { 0.5, "Half its auction price" }, { 1, "Its full auction price" } },
        function() return opt().resaleFactor or 0 end,
        function(v) opt().resaleFactor = v; replan() end, { nearest = true }))

    add(heading(parent, y, "While you level"))
    add(checkbox(parent, x, y, "track", "Keep the plan up to date as I level",
        "Updates after every skill-up, even with the window closed, and tells you when to switch recipes.",
        function() return opt().track ~= false end, function(v) opt().track = v end), 2)
    add(checkbox(parent, x, y, "alertSound", "Play a sound when it's time to switch", nil,
        function() return S.get("alertSound") end, function(v) opt().alertSound = v end), 2)
    add(checkbox(parent, x, y, "alertScreen", "Also show it in the middle of the screen", nil,
        function() return S.get("alertScreen") end, function(v) opt().alertScreen = v end))

    add(heading(parent, y, "Window"))
    add(checkbox(parent, x, y, "openWithProfession", "Open ProfPath with my profession window", nil,
        function() return S.get("openWithProfession") end, function(v) opt().openWithProfession = v end), 4)
    add(choice(parent, x, y, "openTab", "Open on", "Automatic: Prepare until you have a plan, then Do it.",
        { { 0, "Automatic" }, { 1, "Prepare" }, { 2, "Plan" }, { 3, "Do it" } },
        function() return S.get("openTab") end, function(v) opt().openTab = v end, { cols = 4 }))
    add(choice(parent, x, y, "scale", "Window size", nil,
        { { 0.85, "Small" }, { 1, "Normal" }, { 1.15, "Large" }, { 1.3, "Extra large" } },
        function() return S.get("scale") end,
        function(v) opt().scale = v; if ns.UI and ns.UI.applyScale then ns.UI.applyScale() end end,
        { cols = 4, nearest = true }), 4)
    add(checkbox(parent, x, y, "lockWindow", "Lock the window in place", nil,
        function() return S.get("lockWindow") end, function(v) opt().lockWindow = v end), 2)
    add(checkbox(parent, x, y, "minimap", "Show the minimap button", nil,
        function() return not (ProfPathDB.minimap and ProfPathDB.minimap.hide) end,
        function(v)
            ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
            ProfPathDB.minimap.hide = not v or nil
            if ns.Minimap and ns.Minimap.refresh then ns.Minimap.refresh() end
        end), 4)
    local center = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    center:SetSize(200, 22)
    center:SetPoint("TOPLEFT", x + 4, -y)
    center:SetText("Move the window to the middle")
    center:SetScript("OnClick", function() if ns.UI and ns.UI.resetPosition then ns.UI.resetPosition() end end)
    S.centerButton = center
    add(22)

    add(heading(parent, y, "Gathering routes"))
    add(swatches(parent, x, y, "routeColor", "Route colour", S.COLORS,
        function() return S.get("routeColor") end, function(v) opt().routeColor = v; restyleMap() end))
    add(choice(parent, x, y, "routeWidth", "Line thickness", nil,
        { { 2, "Thin" }, { 3, "Normal" }, { 5, "Thick" } },
        function() return S.get("routeWidth") end,
        function(v) opt().routeWidth, opt().miniRouteWidth = v, MINI_FOR[v]; restyleMap() end,
        { cols = 3, nearest = true }), 4)
    add(checkbox(parent, x, y, "miniRoute", "Draw the route on the minimap too", nil,
        function() return S.get("miniRoute") end, function(v) opt().miniRoute = v; restyleMap() end), 2)
    add(checkbox(parent, x, y, "routeWaypoint", "Point the map arrow at the start of the route",
        "Or at the cave entrance, when the route starts inside one.",
        function() return S.get("routeWaypoint") end, function(v) opt().routeWaypoint = v end))

    add(heading(parent, y, "Advanced"))
    add(checkbox(parent, x, y, "prune", "Faster price scans",
        "Skips items that are only used by recipes far too expensive to be worth it.",
        function() return opt().prune ~= false end, function(v) opt().prune = v end), 2)
    add(checkbox(parent, x, y, "techDetails", "Show technical details",
        "Game data build on Prepare, and skipped-recipe counts and calculation time under the plan.",
        function() return S.get("techDetails") end, function(v) opt().techDetails = v; redraw() end), 4)

    local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", x, -y)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function() S.reset() end)
    S.resetButton = reset
    y = y + 34
    return y
end

-- Panel with a scroll area, built on first show.
local function makePanel(parent, top)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -(top or 10))
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(480, 10)
    scroll:SetScrollChild(child)
    local built = false
    parent:HookScript("OnShow", function()
        if not built then child:SetHeight(buildInto(child)); built = true end
        S.refresh()
    end)
    return scroll
end

function S.refresh()
    for _, c in ipairs(controls) do pcall(c.refresh) end
end

function S.reset()
    local o = opt()
    -- Everything in this panel; gold and how far ahead (Prepare tab) stay as they are.
    for k in pairs(S.DEFAULTS) do o[k] = nil end
    if (o.budget or "off") ~= "off" then o.budget = "batch" end
    o.reserve = nil
    o.ownedFree, o.gather, o.resaleFactor, o.effort, o.prune, o.track = false, nil, 0, nil, true, true
    ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
    ProfPathDB.minimap.hide = nil
    if ns.Minimap and ns.Minimap.refresh then ns.Minimap.refresh() end
    if ns.UI and ns.UI.applyScale then ns.UI.applyScale() end
    restyleMap()
    replan()
    redraw()
    S.refresh()
    ns.chat("Settings reset to defaults.")
end

-- Standalone window.
local window
function S.toggle()
    if not window then
        window = CreateFrame("Frame", "ProfPathSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
        window:SetSize(WIDTH, HEIGHT)
        window:SetPoint("CENTER", 40, 0)
        window:SetMovable(true); window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetFrameStrata("DIALOG")
        tinsert(UISpecialFrames, "ProfPathSettingsFrame")
        local t = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetPoint("TOP", 0, -5)
        t:SetText("ProfPath - Settings")
        window:Hide()
        makePanel(window, 30)
    end
    if window:IsShown() then window:Hide() else window:Show() end
end

-- The game's own options (AddOns tab), when this client has an API for it.
local function registerGameOptions()
    local panel = CreateFrame("Frame")
    panel.name = "ProfPath"
    panel:Hide()
    makePanel(panel, 10)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "ProfPath")
        if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(registerGameOptions) end)
