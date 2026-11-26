-- ProfPath route drawing: shows a gathering route (a closed loop of points on a uiMap) on the
-- world map and on the minimap, and can drop a map pin / TomTom waypoint on it.
-- Public: Map.show(zoneEntry, label), Map.clear(), Map.active(), Map.waypoint(), Map.slash(arg)
-- Data: route points are { x1, y1, x2, y2, ... } in 0-100 map percent on uiMap `map`.
local _, ns = ...
local Map = {}
ns.Map = Map

local sqrt, cos, sin, max, min = math.sqrt, math.cos, math.sin, math.max, math.min

-- Route colour and line widths; from the settings (Settings.lua) via applyStyle().
local COLOR = { 1, 0.35, 0.15, 0.9 }
local WORLD_THICKNESS = 3  -- screen-ish thickness on the world map (divided by canvas scale)
local MINI_THICKNESS = 2
local function applyStyle()
    local S = ns.Settings
    if not (S and ProfPathDB) then return end
    COLOR[1], COLOR[2], COLOR[3] = S.routeColor()
    WORLD_THICKNESS = S.get("routeWidth") or 3
    MINI_THICKNESS = S.get("miniRouteWidth") or 2
end
local DOT_SIZE = 7         -- world map dot size (divided by canvas scale)
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Minimap diameter in yards per zoom level (0 = zoomed out most).
local OUTDOOR = { [0] = 466.667, 400, 333.333, 266.667, 200, 133.333 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local ourWaypoint, ourTomTom -- the waypoint ProfPath set (cleared with the route)
local current -- active route: { map = uiMapID, route = { x1, y1, ... }, label = "..." }

-- ---------- helpers ----------

local function say(msg)
    print("|cff66ccffProfPath|r " .. msg)
end

local function validRoute(r)
    return type(r) == "table" and type(r.map) == "number" and type(r.route) == "table" and #r.route >= 4
end

local function save()
    if not ProfPathDB then return end
    if current then
        ProfPathDB.route = { map = current.map, route = current.route, label = current.label, open = current.open, spots = current.spots,
            entrance = current.entrance, cave = current.cave, waypoint = ourWaypoint }
    else
        ProfPathDB.route = nil
    end
end

-- The active route in its map's 0-1 coordinates (world.x / world.y) and the map's size in yards (wYd, hYd).
local world

-- Yards between two points of a map (0-1 coordinates), measured through world positions. Only the
-- distance is used, so it doesn't matter which world axis is north.
local function mapYards(mapID, x1, y1, x2, y2)
    local ok1, c1, a = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x1, y1))
    local ok2, c2, b = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x2, y2))
    if not (ok1 and ok2 and a and b) or c1 ~= c2 then return nil end
    local ax, ay = a:GetXY()
    local bx, by = b:GetXY()
    return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- The route in the zone map's own coordinates plus the map's size in yards. The player's position
-- comes from the same map (GetPlayerMapPosition), so both share one frame: east = +x, south = +y.
-- (Mixing UnitPosition with GetWorldPosFromMapPos swapped the axes and drew the minimap line in the
-- wrong place.)
local function buildWorld()
    world = nil
    if not current or not (C_Map and C_Map.GetWorldPosFromMapPos) or not CreateVector2D then return nil end
    local wYd = mapYards(current.map, 0, 0.5, 1, 0.5)
    local hYd = mapYards(current.map, 0.5, 0, 0.5, 1)
    if not wYd or not hYd or wYd <= 0 or hYd <= 0 then return nil end
    local pts = current.route
    local n = math.floor(#pts / 2)
    local w = { x = {}, y = {}, n = n, wYd = wYd, hYd = hYd }
    for i = 1, n do w.x[i], w.y[i] = pts[i * 2 - 1] / 100, pts[i * 2] / 100 end
    world = w
    return w
end

-- True when the player is standing on `mapID` (or on a child map of it).
local function playerOnMap(mapID)
    if not (C_Map and C_Map.GetBestMapForUnit) then return false end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not id then return false end
    for _ = 1, 4 do
        if id == mapID then return true end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        id = info and info.parentMapID
        if not id or id == 0 then return false end
    end
    return false
end

-- ---------- world map ----------

local overlay, wLines, wDots, wLinesUsed, wDotsUsed
local lastCanvasScale

local function canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function canvasScale()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    local s = sc and sc.GetCanvasScale and sc:GetCanvasScale()
    if not s or s <= 0 then
        local c = canvas()
        s = c and c:GetScale() or 1
    end
    return (s and s > 0) and s or 1
end

local function getWorldLine()
    wLinesUsed = wLinesUsed + 1
    local l = wLines[wLinesUsed]
    if not l then
        l = overlay:CreateLine(nil, "ARTWORK")
        l:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], COLOR[4])
        wLines[wLinesUsed] = l
    end
    return l
end

local function getWorldDot()
    wDotsUsed = wDotsUsed + 1
    local d = wDots[wDotsUsed]
    if not d then
        d = overlay:CreateTexture(nil, "OVERLAY")
        d:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], 1)
        if overlay.CreateMaskTexture then
            local m = overlay:CreateMaskTexture()
            m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(d)
            d:AddMaskTexture(m)
            d.mask = m
        end
        wDots[wDotsUsed] = d
    end
    return d
end

-- Extra routes drawn on the world map only (test command "/pp route all"): { {map, route, color}, ... }
local extra = {}

local function drawWorld()
    if not overlay then return end
    local mapID = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local list = {}
    if current and current.map == mapID then list[1] = { route = current.route, open = current.open, color = COLOR } end
    -- the active route's hot spots (mines, dense clusters) as small yellow loops
    if current and current.map == mapID then
        for _, s in ipairs(current.spots or {}) do list[#list + 1] = { route = s, color = { 1, 0.85, 0.1, 0.95 } } end
    end
    for _, e in ipairs(extra) do if e.map == mapID then list[#list + 1] = e end end
    local ok = mapID and #list > 0
    local c = canvas()
    local w, h = 0, 0
    if ok and c then w, h = c:GetWidth(), c:GetHeight() end
    if not ok or not c or w <= 0 or h <= 0 then
        overlay:Hide()
        return
    end
    overlay:Show()
    -- Stay above the map tiles and other addons' pin layers (Questie and others add frames to the
    -- same canvas, some with high frame levels): sit just above the highest one.
    local top = c:GetFrameLevel() or 0
    for _, child in ipairs({ c:GetChildren() }) do
        if child ~= overlay then
            local lv = child.GetFrameLevel and child:GetFrameLevel() or 0
            if lv > top then top = lv end
        end
    end
    if overlay:GetFrameLevel() <= top then overlay:SetFrameLevel(math.min(top + 5, 9000)) end
    local scale = canvasScale()
    lastCanvasScale = scale
    local thick, dot = WORLD_THICKNESS / scale, DOT_SIZE / scale
    wLinesUsed, wDotsUsed = 0, 0
    for _, r in ipairs(list) do
        local pts, col = r.route, r.color or COLOR
        local n = math.floor(#pts / 2)
        local segs = r.open and n - 1 or n -- open path: no edge from the last point back to the first
        for i = 1, (n > 1) and segs or 0 do
            local j = i % n + 1 -- closed loop: the last point connects back to the first
            local l = getWorldLine()
            l:SetColorTexture(col[1], col[2], col[3], col[4] or 0.9)
            l:SetThickness(thick)
            l:SetStartPoint("TOPLEFT", overlay, pts[i * 2 - 1] / 100 * w, -pts[i * 2] / 100 * h)
            l:SetEndPoint("TOPLEFT", overlay, pts[j * 2 - 1] / 100 * w, -pts[j * 2] / 100 * h)
            l:Show()
        end
    end
    if current and current.map == mapID and current.entrance then
        local d = getWorldDot()
        d:SetSize(DOT_SIZE * 2 / scale, DOT_SIZE * 2 / scale)
        d:SetColorTexture(0.2, 1, 0.3, 1)
        d:ClearAllPoints()
        d:SetPoint("CENTER", overlay, "TOPLEFT", current.entrance[1] / 100 * w, -current.entrance[2] / 100 * h)
        d:Show()
    end
    for i = wLinesUsed + 1, #wLines do wLines[i]:Hide() end
    for i = wDotsUsed + 1, #wDots do wDots[i]:Hide() end
end

local function setupWorld()
    if overlay then return true end
    local c = canvas()
    if not c or not CreateFrame then return false end
    overlay = CreateFrame("Frame", nil, c)
    overlay:SetAllPoints(c)
    overlay:SetFrameLevel((c:GetFrameLevel() or 0) + 20)
    overlay:EnableMouse(false)
    wLines, wDots, wLinesUsed, wDotsUsed = {}, {}, 0, 0
    overlay:SetScript("OnSizeChanged", function() drawWorld() end)
    -- Switching maps or zooming doesn't always fire a hook we can rely on, so while the world map is
    -- open (this watcher is parented to it, so its OnUpdate only runs then) check the shown map and
    -- the zoom 5 times a second and redraw when either changed.
    local watcher = CreateFrame("Frame", nil, WorldMapFrame)
    local acc, lastMapID = 0, nil
    watcher:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        if not current and #extra == 0 then return end
        local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        if id ~= lastMapID or (overlay:IsShown() and canvasScale() ~= lastCanvasScale) then
            lastMapID = id
            drawWorld()
        end
    end)
    watcher:SetScript("OnHide", function() lastMapID = nil end)
    if type(WorldMapFrame.OnMapChanged) == "function" then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() drawWorld() end)
    end
    WorldMapFrame:HookScript("OnShow", function() drawWorld() end)
    WorldMapFrame:HookScript("OnHide", function() overlay:Hide() end)
    drawWorld()
    return true
end

-- ---------- minimap ----------

local mini, mLines, mLinesUsed
local sx, sy = {}, {} -- reused pixel-offset arrays
local lastX, lastY, lastFacing, lastZoom, lastIndoor
local dirty = true
local onMap = false

local function getMiniLine()
    mLinesUsed = mLinesUsed + 1
    local l = mLines[mLinesUsed]
    if not l then
        l = mini:CreateLine(nil, "ARTWORK")
        mLines[mLinesUsed] = l
    end
    l:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], COLOR[4])
    l:SetThickness(MINI_THICKNESS)
    return l
end

local function hideMini()
    if not mini then return end
    mini:Hide()
end

-- Draw the segment (ax,ay)-(bx,by) (pixels from the minimap centre) clipped to the circle of radius r.
-- Solve |A + t(B-A)|^2 = r^2 for t; the visible part is t in [max(0,t1), min(1,t2)].
local function clipDraw(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    if a < 1e-6 then return end
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return end
    local sq = sqrt(disc)
    local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
    local t0, t3 = max(0, t1), min(1, t2)
    if t0 >= t3 then return end
    local l = getMiniLine()
    l:SetStartPoint("CENTER", mini, ax + dx * t0, ay + dy * t0)
    l:SetEndPoint("CENTER", mini, ax + dx * t3, ay + dy * t3)
    l:Show()
end

local function drawMini(px, py, facing, rotating)
    local zoom = Minimap:GetZoom() or 0
    local indoor = IsIndoors and IsIndoors() and true or false
    local diameter = (indoor and INDOOR or OUTDOOR)[zoom] or 300
    local radiusPx = Minimap:GetWidth() / 2
    local scale = radiusPx / (diameter / 2)
    -- Map coordinates: +x is east, +y is south. Offsets in yards from the player (px, py):
    --   east = (x - px) * map width, north = (py - y) * map height.
    -- A rotating minimap shows the player's facing at the top: rotate the offsets by -facing
    -- (facing is counter-clockwise from north), then scale yards to pixels.
    local ca, sa = 1, 0
    if rotating then
        ca, sa = cos(-facing), sin(-facing)
    end
    local n = world.n
    for i = 1, n do
        local east = (world.x[i] - px) * world.wYd
        local north = (py - world.y[i]) * world.hYd
        sx[i] = (east * ca - north * sa) * scale
        sy[i] = (east * sa + north * ca) * scale
    end
    mLinesUsed = 0
    if n > 1 then
        for i = 1, current.open and n - 1 or n do
            local j = i % n + 1
            clipDraw(sx[i], sy[i], sx[j], sy[j], radiusPx)
        end
    end
    for i = mLinesUsed + 1, #mLines do mLines[i]:Hide() end
    mini:Show()
end

local driver
local acc, mapAcc = 0, 0

local function miniUpdate(_, dt)
    acc = acc + dt
    mapAcc = mapAcc + dt
    if acc < 0.1 then return end
    acc = 0
    if not current or not mini then return end
    if mapAcc >= 1 then
        mapAcc = 0
        local was = onMap
        onMap = playerOnMap(current.map)
        if onMap ~= was then dirty = true end
    end
    if not onMap or (ns.Settings and not ns.Settings.get("miniRoute")) then
        hideMini()
        return
    end
    local w = world or buildWorld()
    if not w or w.n < 2 then
        hideMini()
        return
    end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(current.map, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    if not px or (px == 0 and py == 0) then -- not on this map (or no position, e.g. in an instance)
        hideMini()
        dirty = true
        return
    end
    local rotating = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotating and GetPlayerFacing and GetPlayerFacing() or 0
    local zoom = Minimap:GetZoom()
    local indoor = IsIndoors and IsIndoors() and true or false
    local dx, dy = (px - (lastX or 1e9)) * w.wYd, (py - (lastY or 1e9)) * w.hYd -- yards moved
    if not dirty and dx * dx + dy * dy <= 1 and zoom == lastZoom and indoor == lastIndoor
        and (not rotating or math.abs(facing - (lastFacing or 0)) < 0.005) then
        return
    end
    dirty = false
    lastX, lastY, lastFacing, lastZoom, lastIndoor = px, py, facing, zoom, indoor
    drawMini(px, py, facing, rotating)
end

--@debug@
-- Test hook (tests/minimap_spec.lua): run one minimap update.
function Map._tick(dt) miniUpdate(nil, dt) end
--@end-debug@

local function setupMini()
    if mini then return end
    mini = CreateFrame("Frame", nil, Minimap)
    mini:SetAllPoints(Minimap)
    mini:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
    mini:EnableMouse(false)
    mLines, mLinesUsed = {}, 0
    mini:Hide()
end

local function refresh()
    pcall(applyStyle)
    dirty = true
    lastX = nil
    onMap = false
    mapAcc = 1 -- re-check the map on the next tick
    pcall(drawWorld)
    if current then
        pcall(setupMini)
        if not driver then driver = CreateFrame("Frame") end
        driver:SetScript("OnUpdate", function(...) pcall(miniUpdate, ...) end)
    else
        if driver then driver:SetScript("OnUpdate", nil) end
        hideMini()
    end
end

-- ---------- public API ----------

-- spots (optional): hot-spot entries of the same zone, drawn as small yellow loops on the world map.
function Map.show(zoneEntry, label, spots)
    if type(zoneEntry) ~= "table" or type(zoneEntry.route) ~= "table" or not zoneEntry.map then
        return false
    end
    local copy = {}
    for i, v in ipairs(zoneEntry.route) do copy[i] = v end
    if #copy < 4 then return false end
    local sp = {}
    for _, s in ipairs(spots or {}) do
        if s.map == zoneEntry.map and type(s.route) == "table" and #s.route >= 4 then sp[#sp + 1] = s.route end
    end
    current = { map = zoneEntry.map, route = copy, label = label, open = zoneEntry.open, spots = sp,
        entrance = zoneEntry.entrance, cave = zoneEntry.cave }
    pcall(setupWorld) -- in case the world map wasn't loaded yet at login
    world = nil
    save()
    refresh()
    return true
end

-- Open the world map on the active route's zone (the route is drawn there).
function Map.openMap()
    if not current then return end
    local map = current.map
    pcall(function()
        if OpenWorldMap then
            OpenWorldMap(map)
        elseif WorldMapFrame then
            if not WorldMapFrame:IsShown() then
                if ShowUIPanel then ShowUIPanel(WorldMapFrame) else WorldMapFrame:Show() end
            end
            WorldMapFrame:SetMapID(map)
        end
    end)
    pcall(setupWorld)
    pcall(drawWorld)
end

-- Remove the waypoint ProfPath set, but leave one the player placed since.
local function clearWaypoint()
    pcall(function()
        if ourWaypoint and C_Map and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint then
            local wp = C_Map.GetUserWaypoint()
            local px, py
            if wp and wp.position then px, py = wp.position.x, wp.position.y end
            if wp and wp.uiMapID == ourWaypoint.map and px and math.abs(px - ourWaypoint.x) < 0.001
                and math.abs(py - ourWaypoint.y) < 0.001 then
                C_Map.ClearUserWaypoint()
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(false)
                end
            end
        end
    end)
    pcall(function()
        if ourTomTom and TomTom and TomTom.RemoveWaypoint then TomTom:RemoveWaypoint(ourTomTom) end
    end)
    ourWaypoint, ourTomTom = nil, nil
end

-- Redraw with the current settings (colour, line widths, minimap on/off).
function Map.restyle()
    refresh()
end

function Map.clear()
    clearWaypoint()
    current, world = nil, nil
    save()
    refresh()
end

function Map.active()
    return current
end

-- Pin the route point closest to the player (same map) or the first point.
function Map.waypoint()
    if not current then return false end
    local pts = current.route
    local n = math.floor(#pts / 2)
    local best = 1
    pcall(function()
        if C_Map and C_Map.GetPlayerMapPosition and playerOnMap(current.map) then
            local pos = C_Map.GetPlayerMapPosition(current.map, "player")
            if pos then
                local px, py = pos:GetXY()
                px, py = px * 100, py * 100
                local bd
                for i = 1, n do
                    local dx, dy = pts[i * 2 - 1] - px, pts[i * 2] - py
                    local d = dx * dx + dy * dy
                    if not bd or d < bd then bd, best = d, i end
                end
            end
        end
    end)
    local x, y = pts[best * 2 - 1] / 100, pts[best * 2] / 100
    -- A hot spot (cave or mine) has an entrance on open ground: send the player there instead.
    if current.entrance then x, y = current.entrance[1] / 100, current.entrance[2] / 100 end
    local done = false
    pcall(function()
        if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(current.map, x, y))
            ourWaypoint = { map = current.map, x = x, y = y }
            save()
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
            done = true
        end
    end)
    pcall(function()
        if TomTom and TomTom.AddWaypoint then
            if ourTomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, ourTomTom) end
            ourTomTom = TomTom:AddWaypoint(current.map, x, y, { title = current.label or "ProfPath route" })
            done = true
        end
    end)
    return done
end

function Map.slash(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "off" then
        Map.clear()
        say("Route cleared.")
        return true
    --@debug@
    elseif arg:match("^all") then
        -- Test: every route of a profession on the world map, one colour per skill band.
        local kind = arg:match("herb") and "herbalism" or "mining"
        local palette = { { 1, 0.35, 0.15 }, { 1, 0.85, 0.1 }, { 0.3, 1, 0.3 }, { 0.2, 0.8, 1 }, { 0.75, 0.4, 1 }, { 1, 0.4, 0.8 }, { 1, 1, 1 } }
        wipe(extra)
        local count = 0
        for bi, b in ipairs(ns.Routes and ns.Routes[kind] or {}) do
            for _, z in ipairs(b.zones) do
                if z.route then
                    extra[#extra + 1] = { map = z.map, route = z.route, open = z.open, color = palette[(bi - 1) % #palette + 1] }
                    count = count + 1
                end
            end
        end
        pcall(setupWorld)
        pcall(drawWorld)
        local legend = {}
        for bi, b in ipairs(ns.Routes and ns.Routes[kind] or {}) do
            local p = palette[(bi - 1) % #palette + 1]
            legend[#legend + 1] = ("|cff%02x%02x%02x%d-%d|r"):format(p[1] * 255, p[2] * 255, p[3] * 255, b.from, b.to)
        end
        say(("Showing all %d %s routes on the world map: %s. /pp route none clears them."):format(count, kind, table.concat(legend, " ")))
        return true
    elseif arg == "check" then
        -- Test: an L next to you, in any zone: 120 yd north, back, then 60 yd east. On the minimap
        -- (not rotating) the long arm must point up and the short arm right, as on the world map.
        local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then say("No map position here (instance?).") return true end
        local px, py = pos:GetXY()
        current = { map = mapID, label = "minimap check", open = true, spots = {}, route = {} }
        world = nil
        local w = buildWorld()
        if not w then say("Couldn't measure this map.") current = nil return true end
        local n, e = 120 / w.hYd, 60 / w.wYd -- map units for 120 yd north and 60 yd east
        current.route = { px * 100, py * 100, px * 100, (py - n) * 100, px * 100, py * 100, (px + e) * 100, py * 100 }
        world = nil
        refresh()
        say(("Check shape at %.1f, %.1f: a long arm 120 yd north and a short arm 60 yd east of you. "
            .. "On the minimap (with rotation off) the long arm should point up and the short one right, "
            .. "and both should match the world map. /pp route off clears it."):format(px * 100, py * 100))
        return true
    elseif arg == "none" then
        wipe(extra)
        pcall(drawWorld)
        say("Test routes cleared.")
        return true
    elseif arg:match("^test") then
        -- Testing without the profession: /pp route test [mining|herbalism] [skill]
        -- Shows the route for the zone you are in (any skill band that has one), or the given band.
        local kind, skill = arg:match("^test%s*(%a*)%s*(%d*)")
        kind = (kind == "herb" or kind == "herbalism") and "herbalism" or "mining"
        skill = tonumber(skill)
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pick, pickBand
        for _, b in ipairs(ns.Routes and ns.Routes[kind] or {}) do
            if not skill or (skill >= b.from and skill < b.to) then
                for _, z in ipairs(b.zones) do
                    if z.route and (z.map == here or (skill and not pick)) then
                        if z.map == here or not pick then pick, pickBand = z, b end
                    end
                end
            end
            if pick and pick.map == here then break end
        end
        if not pick then
            say(("No %s route for this zone%s. Try /pp route test %s <skill>, e.g. 70."):format(kind,
                skill and " and skill" or "", kind))
            return true
        end
        local zone = ns.Zones and ns.Zones[pick.area]
        Map.show(pick, ("Test: %s %d-%d, %s"):format(kind, pickBand.from, pickBand.to, zone and zone[2] or "?"))
        Map.waypoint()
        say(("Test route: %s %d-%d in %s (%d nodes). /pp route off hides it."):format(kind, pickBand.from,
            pickBand.to, zone and zone[2] or "?", math.floor(#pick.route / 2)))
        return true
    elseif arg == "debug" then
        local c = canvas()
        say(("route: %s, map %s, %d points, open %s"):format(current and "yes" or "no", current and tostring(current.map) or "-",
            current and math.floor(#current.route / 2) or 0, current and tostring(current.open) or "-"))
        say(("WorldMapFrame: %s, shown %s, mapID %s, OnMapChanged %s"):format(tostring(WorldMapFrame ~= nil),
            tostring(WorldMapFrame and WorldMapFrame:IsShown()), tostring(WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()),
            type(WorldMapFrame and WorldMapFrame.OnMapChanged)))
        say(("canvas: %s, size %s x %s, scale %s"):format(tostring(c ~= nil), tostring(c and c:GetWidth()), tostring(c and c:GetHeight()),
            tostring(canvasScale())))
        say(("overlay: %s, shown %s, lines used %d of %d, level %s, strata %s"):format(tostring(overlay ~= nil),
            tostring(overlay and overlay:IsShown()), wLinesUsed or 0, wLines and #wLines or 0,
            tostring(overlay and overlay:GetFrameLevel()), tostring(overlay and overlay:GetFrameStrata())))
        if c then
            local top, n = 0, 0
            for _, child in ipairs({ c:GetChildren() }) do n = n + 1; top = math.max(top, child:GetFrameLevel() or 0) end
            say(("canvas level %s, %d child frames, highest level %d"):format(tostring(c:GetFrameLevel()), n, top))
        end
        if overlay then
            local ok, err = pcall(drawWorld)
            say(("redraw: %s, lines used now %d, overlay shown %s"):format(ok and "ok" or tostring(err), wLinesUsed or 0, tostring(overlay:IsShown())))
        end
        return true
    --@end-debug@
    elseif arg == "show" then
        if not current then
            say("No active route. Pick one in the Gather tab.")
        else
            Map.waypoint()
            say("Route: " .. (current.label or "?"))
        end
        return true
    end
    return false
end

-- ---------- events ----------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local saved = ProfPathDB and ProfPathDB.route
        if validRoute(saved) then
            current = { map = saved.map, route = saved.route, label = saved.label, open = saved.open, spots = saved.spots,
                entrance = saved.entrance, cave = saved.cave }
            ourWaypoint = saved.waypoint
        end
        pcall(setupWorld)
        refresh()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_WorldMap" then
            pcall(setupWorld)
        end
    else
        dirty = true
        mapAcc = 1
    end
end)
