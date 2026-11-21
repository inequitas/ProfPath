-- Checks where Map.lua draws the route on the minimap: a route point north of you must be above the
-- centre, east of you to the right, and a rotating minimap must turn it with your facing.
-- Run from the ProfPath folder:  lua tests/minimap_spec.lua
local noop = function() end
local lines = {}
local function newFrame()
    local f = { scripts = {} }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:CreateLine()
        local l = { shown = false }
        function l:SetStartPoint(_, _, x, y) self.ax, self.ay = x, y end
        function l:SetEndPoint(_, _, x, y) self.bx, self.by = x, y end
        function l:Show() self.shown = true end
        function l:Hide() self.shown = false end
        lines[#lines + 1] = l
        return setmetatable(l, { __index = function() return noop end })
    end
    return setmetatable(f, { __index = function() return noop end })
end
CreateFrame = function() return newFrame() end
Minimap = newFrame()
Minimap.GetWidth = function() return 140 end
Minimap.GetZoom = function() return 0 end -- 466.7 yd across outdoors: 0.3 px per yard
Minimap.GetFrameLevel = function() return 1 end
IsIndoors = function() return false end
CreateVector2D = function(x, y) return { x = x, y = y } end
local W, H = 3000, 2000 -- zone size in yards
-- A world frame with its axes deliberately not east/north: world a = -north, world b = -east.
C_Map = {
    GetWorldPosFromMapPos = function(_, v)
        local a, b = v.y * H, -v.x * W
        return 0, { GetXY = function() return a, b end }
    end,
    GetBestMapForUnit = function() return 1424 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
}
local facing, rotate = 0, "0"
GetCVar = function(k) if k == "rotateMinimap" then return rotate end end
GetPlayerFacing = function() return facing end
ProfPathDB = { options = {} }
SetCVar = noop

local ns = {}
assert(loadfile("Map.lua"))("ProfPath", ns)

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end end

-- An open route from 100 yd north of you to 100 yd north-east (map y up = north).
local north = 0.5 - 100 / H
local east = 0.5 + 100 / W
ns.Map.show({ map = 1424, route = { 50, north * 100, east * 100, north * 100 }, open = true }, "test")
local function tick()
    for _, l in ipairs(lines) do l.shown = false end
    -- the driver frame is the last frame with an OnUpdate script; find it through a fresh show
    ns.Map._tick(1.5)
end
assert(ns.Map._tick, "Map._tick test hook missing")
tick()
local shown = {}
for _, l in ipairs(lines) do if l.shown then shown[#shown + 1] = l end end
check(#shown == 1, "one segment drawn, got " .. #shown)
local l = shown[1]
if l then
    -- 0.3 px per yard: start (0, +30), end (+30, +30)
    check(math.abs(l.ax) < 0.5 and math.abs(l.ay - 30) < 0.5, ("north point above centre: %.1f, %.1f"):format(l.ax, l.ay))
    check(math.abs(l.bx - 30) < 0.5 and math.abs(l.by - 30) < 0.5, ("north-east point up-right: %.1f, %.1f"):format(l.bx, l.by))
end

-- Rotating minimap, facing east (90 degrees clockwise = -pi/2 counter-clockwise from north): north is left.
rotate, facing = "1", 3 * math.pi / 2
tick()
shown = {}
for _, li in ipairs(lines) do if li.shown then shown[#shown + 1] = li end end
l = shown[1]
check(l and l.ax < -29 and math.abs(l.ay) < 0.5, ("facing east: north point is left: %.1f, %.1f"):format(l and l.ax or 0, l and l.ay or 0))

-- /pp route check: an L next to you; not rotating, long arm (120 yd = 36 px) up, short arm (60 yd = 18 px) right.
rotate, facing = "0", 0
print = (function(p) return function(...) local s = select(1, ...); if not tostring(s):find("ProfPath") then p(...) end end end)(print)
assert(ns.Map.slash("check"), "route check not handled")
tick()
shown = {}
for _, li in ipairs(lines) do if li.shown then shown[#shown + 1] = li end end
local up, right
for _, li in ipairs(shown) do
    local ex = math.max(math.abs(li.ax), math.abs(li.bx)); local ey = math.max(li.ay, li.by)
    if math.abs(li.ax) < 0.5 and math.abs(li.bx) < 0.5 and math.abs(ey - 36) < 0.5 then up = true end
    if math.abs(li.ay) < 0.5 and math.abs(li.by) < 0.5 and math.abs(math.max(li.ax, li.bx) - 18) < 0.5 and ex > 0 then right = true end
end
check(up and right, "route check: long arm up, short arm right (" .. #shown .. " segments)")

print(fails == 0 and "minimap ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
