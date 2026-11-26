-- Builds the settings panel with stub frames, clicks every control and checks what it changes.
-- Run from the ProfPath folder:  lua tests/settings_spec.lua
local noop = function() end
local frames, fontStrings = {}, {}
local function newFrame(kind, name)
    local f = { kind = kind, scripts = {}, hooks = {}, shown = true, text = "" }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript(k, fn) self.hooks[k] = fn end
    function f:Show() self.shown = true; if self.hooks.OnShow then self.hooks.OnShow(self) end end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text end
    function f:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    function f:CreateTexture()
        local t = { shown = true }
        function t:Show() self.shown = true end
        function t:Hide() self.shown = false end
        return setmetatable(t, { __index = function() return noop end })
    end
    function f:CreateFontString()
        local s = { text = "" }
        function s:SetText(t) self.text = t end
        function s:GetStringHeight() return 12 end
        fontStrings[#fontStrings + 1] = s
        return setmetatable(s, { __index = function() return noop end })
    end
    frames[#frames + 1] = f
    return setmetatable(f, { __index = function() return noop end })
end
CreateFrame = function(kind, name) return newFrame(kind, name) end
UIParent, UISpecialFrames = {}, {}
tinsert = table.insert
ProfPathDB = { options = { range = 30, budget = "batch", prune = true, track = true }, minimap = { angle = 225 } }
local chats = {}
local ns = { chat = function(m) chats[#chats + 1] = m end }
local replans = 0
ns.requestRecalc = function() replans = replans + 1 end
ns.parseMoney = function(t)
    local g = tonumber(t:match("(%d+)g")) or 0
    local s = tonumber(t:match("(%d+)s")) or 0
    if not t:match("%d") then return nil end
    if not t:match("[gs]") then g = tonumber(t) end
    return g * 10000 + s * 100
end
local restyles, scaled, minimapRefresh = 0, 0, 0
ns.Map = { restyle = function() restyles = restyles + 1 end }
ns.UI = { applyScale = function() scaled = scaled + 1 end }
ns.Minimap = { refresh = function() minimapRefresh = minimapRefresh + 1 end }
assert(loadfile("Settings.lua"))("ProfPath", ns)
local S = ns.Settings

local fails = 0
local function check(ok, what) if ok then print("ok   " .. what) else fails = fails + 1; print("FAIL " .. what) end end

S.toggle() -- builds the window and shows it (OnShow hook builds the panel)
local function labelled(text)
    -- the control whose label (a font string created just before it) says `text`
    for i, s in ipairs(fontStrings) do
        if s.text == text then return i end
    end
end
-- find controls by kind
local checks, sliders, cycles, boxes = {}, {}, {}, {}
for _, f in ipairs(frames) do
    if f.kind == "Button" and f.scripts.OnClick and not f.text:find("Reset") and f.text == "" then checks[#checks + 1] = f end
    if f.kind == "Slider" then sliders[#sliders + 1] = f end
    if f.kind == "Button" and f.text ~= "" and not f.text:find("Reset") then cycles[#cycles + 1] = f end
    if f.kind == "EditBox" then boxes[#boxes + 1] = f end
end
check(#checks == 10, "10 checkboxes, got " .. #checks)
check(#sliders == 5, "5 sliders, got " .. #sliders)
check(#cycles == 4, "4 choice buttons, got " .. #cycles)
check(#boxes == 3, "3 text boxes, got " .. #boxes)

-- choice buttons: How far ahead (30 -> 50), budget (batch -> upfront), open on (0 -> 1), colour (1 -> 2)
check(cycles[1].text == "30 points", "range shows 30 points")
cycles[1].scripts.OnClick(cycles[1])
check(ProfPathDB.options.range == 50 and cycles[1].text == "50 points", "range cycles to 50")
cycles[2].scripts.OnClick(cycles[2])
check(ProfPathDB.options.budget == "upfront", "budget cycles to up front")
cycles[3].scripts.OnClick(cycles[3])
check(ProfPathDB.options.openTab == 1, "open on Prepare")
cycles[4].scripts.OnClick(cycles[4])
check(ProfPathDB.options.routeColor == 2 and restyles > 0, "route colour 2, map restyled")

-- checkboxes in order: ownedFree, useStock, gather, prune, track, sound, screen, minimap button, mini route, waypoint
checks[1].scripts.OnClick(checks[1]); check(ProfPathDB.options.ownedFree == true, "bags free on")
checks[2].scripts.OnClick(checks[2]); check(ProfPathDB.options.useStock == false, "craft from stock off")
checks[3].scripts.OnClick(checks[3]); check(ProfPathDB.options.gather == false, "gather off")
checks[4].scripts.OnClick(checks[4]); check(ProfPathDB.options.prune == false, "prune off")
checks[5].scripts.OnClick(checks[5]); check(ProfPathDB.options.track == false, "track off")
checks[6].scripts.OnClick(checks[6]); check(S.get("alertSound") == false, "sound off")
checks[7].scripts.OnClick(checks[7]); check(S.get("alertScreen") == false, "screen alert off")
checks[8].scripts.OnClick(checks[8]); check(ProfPathDB.minimap.hide == true and minimapRefresh > 0, "minimap button hidden")
checks[9].scripts.OnClick(checks[9]); check(S.get("miniRoute") == false, "minimap route off")
checks[10].scripts.OnClick(checks[10]); check(S.get("routeWaypoint") == false, "no waypoint")

-- sliders: resale, effort, scale, world width, minimap width
sliders[1]:SetValue(25); check(math.abs(ProfPathDB.options.resaleFactor - 0.25) < 1e-9, "resale 25%")
sliders[2]:SetValue(40); check(ProfPathDB.options.effort == 40, "effort 40c")
sliders[3]:SetValue(110); check(math.abs(S.get("scale") - 1.1) < 1e-9 and scaled > 0, "window 110%")
sliders[4]:SetValue(5); check(S.get("routeWidth") == 5, "world line 5")
sliders[5]:SetValue(3); check(S.get("miniRouteWidth") == 3, "minimap line 3")

-- text boxes: stop at, amount, reserve
boxes[1].text = "205"; boxes[1].scripts.OnEnterPressed(boxes[1]); check(ProfPathDB.options.target == 205, "stop at 205")
boxes[1].text = "999"; boxes[1].scripts.OnEnterPressed(boxes[1]); check(ProfPathDB.options.target == 205 and #chats > 0, "999 refused")
boxes[1].text = ""; boxes[1].scripts.OnEnterPressed(boxes[1]); check(ProfPathDB.options.target == nil, "empty: no fixed end")
boxes[2].text = "5g"; boxes[2].scripts.OnEnterPressed(boxes[2]); check(ProfPathDB.options.budgetAmount == 50000, "amount 5g")
check(boxes[2].text == "5g", "amount shown as 5g")
boxes[3].text = "1g 50s"; boxes[3].scripts.OnEnterPressed(boxes[3]); check(ProfPathDB.options.reserve == 15000, "reserve 1g 50s")
check(replans >= 10, "planning options re-plan (" .. replans .. ")")

-- reset
S.reset()
local o = ProfPathDB.options
check(o.range == 30 and o.budget == "batch" and o.target == nil and o.budgetAmount == nil and o.ownedFree == nil
    and o.gather == nil and o.prune == true and o.track == true and S.get("useStock") == true
    and S.get("routeColor") == 1 and S.get("scale") == 1 and not ProfPathDB.minimap.hide, "reset to defaults")
check(cycles[1].text == "30 points", "controls show the reset values")

print(fails == 0 and "settings ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
