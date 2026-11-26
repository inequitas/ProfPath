-- ProfPath settings: every option in one panel. Opens as its own window (/pp settings, or the
-- Settings button in the ProfPath window) and, when the game client supports it, also appears under
-- the game's AddOns options. Controls are built from plain frames and textures (no newer templates),
-- so they work on any client.
local _, ns = ...
local S = {}
ns.Settings = S

local WIDTH, HEIGHT = 520, 600
local LABEL_W = 230

-- Route colours to pick from.
S.COLORS = {
    { "Orange", 1, 0.35, 0.15 }, { "Red", 1, 0.15, 0.15 }, { "Yellow", 1, 0.85, 0.1 }, { "Green", 0.3, 1, 0.3 },
    { "Cyan", 0.2, 0.85, 1 }, { "Purple", 0.75, 0.4, 1 }, { "Pink", 1, 0.45, 0.8 }, { "White", 1, 1, 1 },
}

-- Defaults for the options added with this panel (older ones keep theirs in Core.lua).
S.DEFAULTS = {
    useStock = true, alertSound = true, alertScreen = true, scale = 1, openTab = 0,
    routeColor = 1, routeWidth = 3, miniRouteWidth = 2, miniRoute = true, routeWaypoint = true,
}

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

local controls = {} -- every built control, refreshed when a panel is shown

local function label(parent, text, x, y, font, w)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetPoint("TOPLEFT", x, -y)
    if w then f:SetWidth(w); f:SetJustifyH("LEFT") end
    f:SetText(text)
    return f
end

local function checkbox(parent, x, y, text, tip, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", x, -y)
    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetAllPoints(); box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    local check = b:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints(); check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    local l = label(parent, text, x + 28, y + 5, "GameFontHighlight", 440)
    local tipF = tip and label(parent, tip, x + 28, y + 22, "GameFontDisableSmall", 440)
    local c = {}
    function c.refresh() if get() then check:Show() else check:Hide() end end
    b:SetScript("OnClick", function() set(not get()); c.refresh() end)
    controls[#controls + 1] = c
    c.refresh()
    local h = 28
    if tipF then h = 26 + math.max(12, tipF:GetStringHeight() or 12) end
    return h, l
end

-- Horizontal slider with a value label: min, max, step; fmt(v) formats the value.
local function slider(parent, x, y, text, tip, min, max, step, get, set, fmt)
    label(parent, text, x, y + 2)
    local value = label(parent, "", x + LABEL_W + 190, y + 2, "GameFontHighlightSmall")
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 16)
    s:SetPoint("TOPLEFT", x + LABEL_W, -y)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0); track:SetPoint("RIGHT", 0, 0); track:SetHeight(6)
    track:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    local c, quiet = {}, false
    function c.refresh()
        quiet = true
        s:SetValue(get())
        value:SetText(fmt(get()))
        quiet = false
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText(fmt(v))
        if not quiet and v ~= get() then set(v) end
    end)
    controls[#controls + 1] = c
    c.refresh()
    local h = 26
    if tip then
        local t = label(parent, tip, x, y + 20, "GameFontDisableSmall", 460)
        h = 24 + math.max(12, t:GetStringHeight() or 12)
    end
    return h
end

-- Button that cycles through choices: list of { value, "Label" }.
local function cycle(parent, x, y, text, tip, list, get, set)
    label(parent, text, x, y + 4)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(180, 22)
    b:SetPoint("TOPLEFT", x + LABEL_W, -y)
    local c = {}
    local function index()
        for i, e in ipairs(list) do if e[1] == get() then return i end end
        return 1
    end
    function c.refresh() b:SetText(list[index()][2]) end
    b:SetScript("OnClick", function()
        local i = index() % #list + 1
        set(list[i][1]); c.refresh()
    end)
    controls[#controls + 1] = c
    c.refresh()
    local h = 28
    if tip then
        local t = label(parent, tip, x, y + 24, "GameFontDisableSmall", 460)
        h = 28 + math.max(12, t:GetStringHeight() or 12)
    end
    return h
end

-- Text box: parse(text) returns the value or nil (shows an error), show(value) gives the text.
local function input(parent, x, y, text, tip, get, set, parse, show)
    label(parent, text, x, y + 4)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(120, 20)
    box:SetPoint("TOPLEFT", x + LABEL_W + 6, -y)
    local c = {}
    function c.refresh() box:SetText(show(get())) end
    local function apply(self)
        local ok, v = parse(self:GetText())
        self:ClearFocus()
        if ok then set(v) else ns.chat(v or "Couldn't read that.") end
        c.refresh()
    end
    box:SetScript("OnEnterPressed", apply)
    box:SetScript("OnEditFocusLost", function(self) c.refresh() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); c.refresh() end)
    controls[#controls + 1] = c
    c.refresh()
    local h = 28
    if tip then
        local t = label(parent, tip, x, y + 24, "GameFontDisableSmall", 460)
        h = 28 + math.max(12, t:GetStringHeight() or 12)
    end
    return h
end

local function heading(parent, y, text)
    label(parent, text, 4, y, "GameFontNormalLarge")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 4, -(y + 22))
    line:SetSize(460, 1)
    line:SetColorTexture(1, 0.82, 0, 0.4)
    return 30
end

local function money(c)
    if not c then return "" end
    local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    return ("%ds"):format(s)
end

-- ---------- the panel ----------

-- Builds every setting into `parent` (a scroll child). Returns its height.
local function buildInto(parent)
    local x, y = 8, 6
    local function add(h) y = y + h + 4 end

    add(heading(parent, y, "Planning"))
    add(cycle(parent, x, y, "How far ahead", "Plan (and scan prices for) this many skill points ahead, or to the end.",
        { { 10, "10 points" }, { 20, "20 points" }, { 30, "30 points" }, { 50, "50 points" }, { 75, "75 points" },
          { 100, "100 points" }, { false, "As far as you can" } },
        function() return opt().range or false end,
        function(v) opt().range = v; replan() end))
    add(input(parent, x, y, "Stop at skill", "Plan up to this skill, whatever the range. Empty: no fixed end.",
        function() return opt().target end,
        function(v) opt().target = v; replan() end,
        function(t)
            t = t:match("^%s*(.-)%s*$")
            if t == "" then return true, nil end
            local n = tonumber(t)
            if n and n >= 1 and n <= 300 then return true, math.floor(n) end
            return false, "Type a skill from 1 to 300, or leave it empty."
        end,
        function(v) return v and tostring(v) or "" end))
    add(cycle(parent, x, y, "Budget", "Batches: buy and craft in steps your gold allows, vendoring as you go. "
        .. "Up front: everything at once. Off: ignore gold.",
        { { "batch", "Fit to gold: batches" }, { "upfront", "Fit to gold: up front" }, { "off", "Off" } },
        function() return opt().budget or "off" end,
        function(v) opt().budget = v; replan() end))
    add(input(parent, x, y, "Budget amount", "Gold to plan with, like 5g or 1g 50s. Empty: the gold in your bags.",
        function() return opt().budgetAmount end,
        function(v) opt().budgetAmount = v; replan() end,
        function(t)
            if t:match("^%s*$") then return true, nil end
            local c = ns.parseMoney and ns.parseMoney(t)
            if c then return true, c end
            return false, "Couldn't read that amount. Try 2, 1g 50s or 50s."
        end, money))
    add(input(parent, x, y, "Keep in reserve", "With the gold in your bags as budget, keep this much aside.",
        function() return opt().reserve end,
        function(v) opt().reserve = v; replan() end,
        function(t)
            if t:match("^%s*$") then return true, nil end
            local c = ns.parseMoney and ns.parseMoney(t)
            if c then return true, c end
            return false, "Couldn't read that amount. Try 2, 1g 50s or 50s."
        end, money))
    add(checkbox(parent, x, y, "Everything in your bags is free",
        "Off (default): only what you had when you started the plan counts as free; what you buy later counts at its price.",
        function() return opt().ownedFree end, function(v) opt().ownedFree = v or nil; replan() end))
    add(checkbox(parent, x, y, "Craft from your own stock",
        "Turn materials you already have into ones the plan needs (Medium into Heavy Leather, hides into cured hides with vendor salt).",
        function() return S.get("useStock") end, function(v) opt().useStock = v; replan() end))
    add(checkbox(parent, x, y, "Gather materials yourself",
        "When nobody sells a material and you have the gathering profession, plan to gather it.",
        function() return opt().gather ~= false end, function(v) opt().gather = v; replan() end))
    add(slider(parent, x, y, "Resale value counted",
        "Share of a crafted item's auction price counted as money back. 0% = vendor price only.",
        0, 100, 5, function() return math.floor((opt().resaleFactor or 0.5) * 100 + 0.5) end,
        function(v) opt().resaleFactor = v / 100; replan() end,
        function(v) return v .. "%" end))
    add(slider(parent, x, y, "Extra cost per craft",
        "Counts each craft as this much more expensive, to prefer plans with fewer crafts.",
        0, 100, 5, function() return opt().effort or 0 end,
        function(v) opt().effort = v > 0 and v or nil; replan() end,
        function(v) return v .. "c" end))

    add(heading(parent, y, "Auction house scans"))
    add(checkbox(parent, x, y, "Skip overpriced items",
        "During item-by-item scans, skip items only used by recipes that are clearly too expensive.",
        function() return opt().prune ~= false end, function(v) opt().prune = v end))

    add(heading(parent, y, "While you level"))
    add(checkbox(parent, x, y, "Re-plan on every skill-up",
        "Keeps the plan current with the window closed, and tells you when a step is done or a cheaper path appears.",
        function() return opt().track ~= false end, function(v) opt().track = v end))
    add(checkbox(parent, x, y, "Alert sound", nil,
        function() return S.get("alertSound") end, function(v) opt().alertSound = v end))
    add(checkbox(parent, x, y, "Alert text on screen", "Besides the chat message.",
        function() return S.get("alertScreen") end, function(v) opt().alertScreen = v end))

    add(heading(parent, y, "Window"))
    add(slider(parent, x, y, "Window size", nil, 70, 130, 5,
        function() return math.floor(S.get("scale") * 100 + 0.5) end,
        function(v) opt().scale = v / 100; if ns.UI and ns.UI.applyScale then ns.UI.applyScale() end end,
        function(v) return v .. "%" end))
    add(cycle(parent, x, y, "Open on", "Automatic: Prepare until a plan is ready, Do it while you follow one.",
        { { 0, "Automatic" }, { 1, "Prepare" }, { 2, "Plan" }, { 3, "Do it" } },
        function() return S.get("openTab") end, function(v) opt().openTab = v end))
    add(checkbox(parent, x, y, "Minimap button", nil,
        function() return not (ProfPathDB.minimap and ProfPathDB.minimap.hide) end,
        function(v)
            ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
            ProfPathDB.minimap.hide = not v or nil
            if ns.Minimap and ns.Minimap.refresh then ns.Minimap.refresh() end
        end))

    add(heading(parent, y, "Gathering routes"))
    local colorList = {}
    for i, c in ipairs(S.COLORS) do
        colorList[i] = { i, ("|cff%02x%02x%02x%s|r"):format(math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), math.floor(c[4] * 255 + 0.5), c[1]) }
    end
    add(cycle(parent, x, y, "Route colour", nil, colorList,
        function() return S.get("routeColor") end, function(v) opt().routeColor = v; restyleMap() end))
    add(slider(parent, x, y, "Line width on the world map", nil, 1, 8, 1,
        function() return S.get("routeWidth") end, function(v) opt().routeWidth = v; restyleMap() end,
        function(v) return tostring(v) end))
    add(slider(parent, x, y, "Line width on the minimap", nil, 1, 5, 1,
        function() return S.get("miniRouteWidth") end, function(v) opt().miniRouteWidth = v; restyleMap() end,
        function(v) return tostring(v) end))
    add(checkbox(parent, x, y, "Show the route on the minimap", nil,
        function() return S.get("miniRoute") end, function(v) opt().miniRoute = v; restyleMap() end))
    add(checkbox(parent, x, y, "Set a waypoint with Show route", "Points the map arrow at the start of the route (or a cave entrance).",
        function() return S.get("routeWaypoint") end, function(v) opt().routeWaypoint = v end))

    y = y + 8
    local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", x, -y)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function() S.reset() end)
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
    for k in pairs(S.DEFAULTS) do o[k] = nil end
    o.range, o.target, o.budget, o.budgetAmount, o.reserve = 30, nil, "batch", nil, nil
    o.ownedFree, o.gather, o.resaleFactor, o.effort, o.prune, o.track = nil, nil, nil, nil, true, true
    ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
    ProfPathDB.minimap.hide = nil
    if ns.Minimap and ns.Minimap.refresh then ns.Minimap.refresh() end
    if ns.UI and ns.UI.applyScale then ns.UI.applyScale() end
    restyleMap()
    replan()
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
