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
ProfPathDB = { options = { range = 30, budget = "batch", prune = true, track = true, resaleFactor = 0, ownedFree = false }, minimap = { angle = 225 } }
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



local centered, redraws = 0, 0
ns.UI.resetPosition = function() centered = centered + 1 end
ns.requestRedraw = function() redraws = redraws + 1 end

S.toggle() -- builds the window and shows it (OnShow hook builds the panel)
local C = S.controls
local o = ProfPathDB.options
local function click(b) b.scripts.OnClick(b) end -- the real click handler

-- Gold and range live on the Prepare tab, not here
check(C.range == nil and C.budget == nil and C.budgetAmount == nil and C.target == nil, "no gold/range duplicates")

-- Shopping
check(C.buyStyle.selected() == 1, "buy a bit at a time by default")
click(C.buyStyle.buttons[2]); check(o.buyStyle == "upfront" and o.budget == "upfront", "buy everything first (budget follows)")
o.budget = "off"; click(C.buyStyle.buttons[1])
check(o.buyStyle == "batch" and o.budget == "off", "with gold ignored, only the preference changes")
check(S.buyStyle() == "batch", "buyStyle() reads it")
C.reserve.type("1g 50s"); check(o.reserve == 15000 and C.reserve.box.text == "1g 50s", "keep 1g 50s")
C.reserve.type("lots"); check(o.reserve == 15000 and #chats > 0, "unreadable amount refused")
click(C.ownedFree.buttons[2]); check(o.ownedFree == true, "bag items always free")
click(C.useStock.button); check(o.useStock == false, "leftovers off")
click(C.gather.button); check(o.gather == false, "gather off")

-- Choosing recipes
check(C.resale.selected() == 1, "resale shows vendor price")
o.resaleFactor = 0.4; S.refresh(); check(C.resale.selected() == 2, "old 40% shows as half")
click(C.resale.buttons[3]); check(o.resaleFactor == 1, "full auction price")
click(C.effort.buttons[3]); check(o.effort == 200, "fewer crafts")
click(C.effort.buttons[1]); check(o.effort == nil, "cheapest clears effort")

-- While you level
click(C.track.button); check(o.track == false, "tracking off")
click(C.alertSound.button); check(S.get("alertSound") == false, "sound off")
click(C.alertScreen.button); check(S.get("alertScreen") == false, "screen alert off")

-- Window
click(C.openWithProfession.button); check(S.get("openWithProfession") == true, "open with profession window")
click(C.openTab.buttons[2]); check(o.openTab == 1, "open on Prepare")
click(C.scale.buttons[3]); check(math.abs(S.get("scale") - 1.15) < 1e-9 and scaled > 0, "window large")
click(C.lockWindow.button); check(S.get("lockWindow") == true, "window locked")
click(C.minimap.button); check(ProfPathDB.minimap.hide == true and minimapRefresh > 0, "minimap button hidden")
click(S.centerButton); check(centered == 1, "window moved to the middle")

-- Routes
click(C.routeColor.buttons[5]); check(o.routeColor == 5 and restyles > 0, "route cyan")
check(C.routeColor.buttons[5].ring.shown and not C.routeColor.buttons[1].ring.shown, "chosen swatch framed")
click(C.routeWidth.buttons[3]); check(o.routeWidth == 5 and o.miniRouteWidth == 3, "thick lines on both maps")
click(C.miniRoute.button); check(S.get("miniRoute") == false, "minimap route off")
click(C.routeWaypoint.button); check(S.get("routeWaypoint") == false, "no waypoint")

-- Advanced
click(C.prune.button); check(o.prune == false, "faster scans off")
click(C.techDetails.button); check(S.get("techDetails") == true and redraws > 0, "technical details on, window redrawn")
check(replans >= 9, "planning answers re-plan (" .. replans .. ")")

-- Reset: this panel's settings back to default, Prepare's gold and range left alone
o.range, o.target, o.budget, o.budgetAmount = 50, 210, "upfront", 70000
click(S.resetButton)
check(o.range == 50 and o.target == 210 and o.budgetAmount == 70000, "reset keeps gold amount and range")
check(o.budget == "batch", "reset: buying a bit at a time again")
check(o.reserve == nil and o.ownedFree == false and o.resaleFactor == 0 and o.effort == nil and o.gather == nil
    and o.prune == true and o.track == true and S.get("useStock") == true and S.get("routeColor") == 1
    and S.get("scale") == 1 and S.get("routeWidth") == 3 and S.get("lockWindow") == false
    and S.get("openWithProfession") == false and S.get("techDetails") == false
    and not ProfPathDB.minimap.hide, "reset to defaults")
check(C.resale.selected() == 1 and C.routeWidth.selected() == 2 and C.buyStyle.selected() == 1, "controls show the reset values")

print(fails == 0 and "settings ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
