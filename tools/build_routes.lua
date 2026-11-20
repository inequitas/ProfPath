-- Builds Data/Routes.lua from tools/data/wowhead-nodes.json (Wowhead WoW: Forever node data).
-- Run from the ProfPath folder:  lua tools/build_routes.lua
local ns = {}
local function script_dir()
    local src = arg and arg[0] or "tools/build_routes.lua"
    return (src:gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
end
local ROOT = script_dir() .. "/.."

---------------------------------------------------------------- JSON parser
local function parse_json(s)
    local pos = 1
    local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local value
    local function str()
        local e = pos + 1
        while true do
            local c = s:sub(e, e)
            if c == "\\" then e = e + 2
            elseif c == '"' then break
            elseif c == "" then error("unterminated string") else e = e + 1 end
        end
        local raw = s:sub(pos + 1, e - 1)
        pos = e + 1
        raw = raw:gsub("\\u(%x%x%x%x)", function(h) return utf8.char(tonumber(h, 16)) end)
        raw = raw:gsub("\\(.)", { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })
        return raw
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws(); local k = str(); ws()
                assert(s:sub(pos, pos) == ":", "expected : at " .. pos); pos = pos + 1
                t[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "}" then return t end
                assert(d == ",", "expected , at " .. pos)
            end
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "]" then return t end
                assert(d == ",", "expected , at " .. pos)
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            assert(num and #num > 0, "bad json at " .. pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

local function readfile(p)
    local f = assert(io.open(p, "rb")); local d = f:read("a"); f:close(); return d
end

---------------------------------------------------------------- Config
local SKILL = {
    mining = {
        ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Silver Vein"] = 75, ["Iron Deposit"] = 125,
        ["Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Truesilver Deposit"] = 230,
        ["Dark Iron Deposit"] = 230, ["Small Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
        ["Heavy Thorium Vein"] = 300,
    },
    herbalism = {
        ["Peacebloom"] = 1, ["Silverleaf"] = 1, ["Earthroot"] = 15, ["Mageroyal"] = 50,
        ["Briarthorn"] = 70, ["Stranglekelp"] = 85, ["Bruiseweed"] = 100, ["Wild Steelbloom"] = 115,
        ["Grave Moss"] = 120, ["Kingsblood"] = 125, ["Liferoot"] = 150, ["Fadeleaf"] = 160,
        ["Goldthorn"] = 170, ["Khadgar's Whisker"] = 185, ["Wintersbite"] = 195, ["Firebloom"] = 205,
        ["Purple Lotus"] = 210, ["Arthas' Tears"] = 220, ["Sungrass"] = 230, ["Blindweed"] = 235,
        ["Ghost Mushroom"] = 245, ["Gromsblood"] = 250, ["Golden Sansam"] = 260, ["Dreamfoil"] = 270,
        ["Mountain Silversage"] = 280, ["Plaguebloom"] = 285, ["Icecap"] = 290, ["Black Lotus"] = 300,
    },
}
-- Name aliases applied after stripping "Ooze Covered ".
local ALIAS = { ["Thorium Vein"] = "Small Thorium Vein" }

local SIDE = {}
for _, n in ipairs { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Darkshore", "Westfall", "Loch Modan",
    "Redridge Mountains", "Duskwood", "Wetlands", "Stormwind City", "Ironforge", "Darnassus" } do SIDE[n] = "A" end
for _, n in ipairs { "Durotar", "Mulgore", "Tirisfal Glades", "The Barrens", "Silverpine Forest",
    "Orgrimmar", "Thunder Bluff", "Undercity" } do SIDE[n] = "H" end

local STARTERS = { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades",
    "Zephras Isle" }

local BANDS = {
    mining = {
        { 1, 65, STARTERS, true }, { 65, 125, { "Ashenvale", "Redridge Mountains", "The Barrens", "Thousand Needles" } },
        { 125, 175, { "Arathi Highlands", "Desolace", "Stranglethorn Vale", "Thousand Needles" } },
        { 175, 225, { "Azshara", "Tanaris", "The Hinterlands" } },
        { 225, 275, {} }, { 275, 300, {} },
    },
    herbalism = {
        { 1, 70, STARTERS, true }, { 70, 115, { "Darkshore", "Loch Modan", "Silverpine Forest" } },
        { 115, 170, { "Hillsbrad Foothills", "Wetlands", "Stonetalon Mountains" } },
        { 170, 205, { "Stranglethorn Vale", "Arathi Highlands" } },
        { 205, 225, { "Alterac Mountains", "Tanaris", "Searing Gorge" } },
        { 225, 260, {} }, { 260, 300, {} },
    },
    skinning = {
        { 1, 75, STARTERS, true }, { 75, 125, { "The Barrens", "Loch Modan", "Darkshore" } },
        { 125, 175, { "Ashenvale", "Duskwood", "Hillsbrad Foothills", "Wetlands" } },
        { 175, 225, { "Arathi Highlands", "Stranglethorn Vale", "Thousand Needles" } },
    },
    fishing = {
        { 1, 75, STARTERS, true },
        { 75, 150, { "Darnassus", "Ironforge", "Stormwind City", "Orgrimmar", "Thunder Bluff", "Undercity" } },
        { 150, 225, { "Dustwallow Marsh", "Stranglethorn Vale" } },
        { 225, 300, { "Tanaris" } },
    },
}

local MAXZONES = 5
local MAXNODES = 250
local DEDUPE = 0.4 -- map units
local R = 120                      -- yards: the route must pass within R of every covered node
local HOP_YARDS = { 180, 220, 260 } -- max hop between linked nodes/stops, tried in order
local MAX_SEG = 400                 -- yards: longest straight segment (also the longest corridor link)
local CORRIDOR = 160               -- yards: a segment must stay within this distance of a useful node
UNTANGLE_GROWTH = 1.15
local SPIKE_YD = 40                  -- steep stretches shorter than this are ignored (a segment is blocked only when sustained)
local STEEP_COST = 1.3              -- grid-path cost multiplier within 40 yd of steep ground
local PATH_CAP = 600                -- yards: longest single straight piece of a path
local STEEP = 1.2                  -- local slope (rise/run) at or above this is a mountain wall
local NEAR_NODE_YD = 400            -- walkable mask only within this distance of a useful node
local EDGE_DP = 20                  -- yards: simplification of the edge loop
local FAR_YD = 500                  -- edge-loop stretches farther than this from every node are cut with a chord
local MIN_SKIP_WALK = 400           -- yards of walking a chord must skip
local DETOUR_YD_PER_NODE = 90
local MIN_EDGE_COVER = 0.60
local FLAG_KEEPOUT = 70
local USABLE = { [1412] = { { 39.9, 16.7 } } } -- reviewer: the only path up; should stay usable
local FLAGGED = { [1412] = { { 29.5, 27.9 }, { 59.6, 45.8 } }, [1426] = { { 38.2, 57.2 } } } -- reviewer-flagged impassable points
local GRID = 20                    -- yards: walkable-grid cell size and sampling step
local CHAIKIN_PASSES = 1
local TOWN_RADIUS = 250             -- yards around a hostile town that is excluded
local SIMPLIFY = 8                -- yards: Douglas-Peucker tolerance (also the extra slack for coverage checks)
local STOP_HOP_EXTRA = 120         -- yards added to the hop limit between stops (stops are offset from nodes by up to R)
local SPUR_YD_PER_NODE = 90          -- prune a stop when it saves more than this many yards per node it alone covers
local MIN_COVER = 0.85                 -- ...as long as at least this share of the region's nodes stays covered
local UIMAPASSIGNMENT = os.getenv("PROFPATH_UIMAPASSIGNMENT") or (ROOT .. "/tools/data/UiMapAssignment.csv")

---------------------------------------------------------------- Load data
local zones = {}
assert(loadfile(ROOT .. "/Data/Zones.lua"))(nil, ns)
local byName = {}
for area, z in pairs(ns.Zones) do
    local side = SIDE[z[2]] or "C"
    zones[area] = { area = area, map = z[1], name = z[2], side = side }
    byName[z[2]] = area
end

-- zone size in yards from UiMapAssignment.csv (row for the UiMapID with UiMin 0,0 and UiMax 1,1)
local size = {}
do
    local csv = readfile(UIMAPASSIGNMENT)
    local cols
    for line in csv:gmatch("[^\r\n]+") do
        local t = {}
        for v in (line .. ","):gmatch("([^,]*),") do t[#t + 1] = v end
        if not cols then
            cols = {}
            for i, name in ipairs(t) do cols[name] = i end
        else
            local function g(name) return tonumber(t[cols[name]]) end
            if g("UiMin_0") == 0 and g("UiMin_1") == 0 and g("UiMax_0") == 1 and g("UiMax_1") == 1 then
                local id = g("UiMapID")
                local w, h = math.abs(g("Region_4") - g("Region_1")), math.abs(g("Region_3") - g("Region_0"))
                if not size[id] then size[id] = { w, h } end
            end
        end
    end
end

local json = {}
for _, fn in ipairs { "wowhead-nodes.json", "wowhead-nodes-extra.json" } do
    local fh = io.open(ROOT .. "/tools/data/" .. fn, "rb")
    if fh then
        fh:close()
        for id, obj in pairs(parse_json(readfile(ROOT .. "/tools/data/" .. fn))) do json[fn .. ":" .. id] = obj end
    end
end
-- nodes[prof][nodeName][area] = list of {x,y}
local nodes = { mining = {}, herbalism = {} }
local ignoredNames = {}
for _, obj in pairs(json) do
    local prof = obj.kind == "ore" and "mining" or obj.kind == "herb" and "herbalism" or nil
    local name = obj.name:gsub("^Ooze Covered ", "")
    name = ALIAS[name] or name
    if prof and SKILL[prof][name] then
        local bucket = nodes[prof][name] or {}
        nodes[prof][name] = bucket
        for areaStr, pts in pairs(obj.zones or {}) do
            local area = tonumber(areaStr)
            bucket[area] = bucket[area] or {}
            for _, p in ipairs(pts) do bucket[area][#bucket[area] + 1] = { p[1], p[2], name } end
        end
    else
        ignoredNames[obj.name] = true
    end
end

---------------------------------------------------------------- Routing
local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

local function dedupe(pts)
    local out = {}
    for _, p in ipairs(pts) do
        local dup = false
        for _, q in ipairs(out) do if dist(p, q) < DEDUPE then dup = true break end end
        if not dup then out[#out + 1] = p end
    end
    return out
end

local function components(pts, D)
    local n, comp, ncomp = #pts, {}, 0
    local adj = {}
    for i = 1, n do adj[i] = {} end
    for i = 1, n do
        for j = i + 1, n do
            if dist(pts[i], pts[j]) <= D then
                adj[i][#adj[i] + 1] = j; adj[j][#adj[j] + 1] = i
            end
        end
    end
    local sizes = {}
    for i = 1, n do
        if not comp[i] then
            ncomp = ncomp + 1
            comp[i] = ncomp
            local stack, size = { i }, 0
            while #stack > 0 do
                local v = table.remove(stack); size = size + 1
                for _, w in ipairs(adj[v]) do
                    if not comp[w] then comp[w] = ncomp; stack[#stack + 1] = w end
                end
            end
            sizes[ncomp] = size
        end
    end
    local best = 1
    for c = 2, ncomp do if sizes[c] > sizes[best] then best = c end end
    return comp, best, sizes[best], adj
end

local function segDist(p, a, b)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local l2 = dx * dx + dy * dy
    if l2 == 0 then return dist(p, a) end
    local t = ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / l2
    t = math.max(0, math.min(1, t))
    return dist(p, { a[1] + t * dx, a[2] + t * dy })
end

local function chaikin(line, closed)
    local out = {}
    local n = #line
    if closed then
        for i = 1, n do
            local a, b = line[i], line[i % n + 1]
            out[#out + 1] = { 0.75 * a[1] + 0.25 * b[1], 0.75 * a[2] + 0.25 * b[2] }
            out[#out + 1] = { 0.25 * a[1] + 0.75 * b[1], 0.25 * a[2] + 0.75 * b[2] }
        end
    else
        out[1] = line[1]
        for i = 1, n - 1 do
            local a, b = line[i], line[i + 1]
            out[#out + 1] = { 0.75 * a[1] + 0.25 * b[1], 0.75 * a[2] + 0.25 * b[2] }
            out[#out + 1] = { 0.25 * a[1] + 0.75 * b[1], 0.25 * a[2] + 0.75 * b[2] }
        end
        out[#out + 1] = line[n]
    end
    return out
end

local function douglas(line, tol) -- open polyline
    local n = #line
    if n < 3 then return line end
    local keep = { [1] = true, [n] = true }
    local function rec(i, j)
        local md, mi = 0, nil
        for k = i + 1, j - 1 do
            local d = segDist(line[k], line[i], line[j])
            if d > md then md, mi = d, k end
        end
        if not mi and j - i > 1 and dist(line[i], line[j]) > MAX_SEG then mi = (i + j) // 2; md = math.huge end
        if mi and (md > tol or dist(line[i], line[j]) > MAX_SEG) and j - i > 1 then keep[mi] = true; rec(i, mi); rec(mi, j) end
    end
    rec(1, n)
    local out = {}
    for i = 1, n do if keep[i] then out[#out + 1] = line[i] end end
    return out
end

local function simplify(line, closed, tol)
    if not closed then return douglas(line, tol) end
    -- split the loop at the point farthest from point 1 and simplify the two halves
    local far, fd = 1, -1
    for i = 2, #line do local d = dist(line[1], line[i]); if d > fd then fd, far = d, i end end
    if far == 1 then return line end
    local h1, h2 = {}, {}
    for i = 1, far do h1[#h1 + 1] = line[i] end
    for i = far, #line do h2[#h2 + 1] = line[i] end
    h2[#h2 + 1] = line[1]
    local a, b = douglas(h1, tol), douglas(h2, tol)
    local out = {}
    for i = 1, #a do out[#out + 1] = a[i] end
    for i = 2, #b - 1 do out[#out + 1] = b[i] end
    return out
end

local function polyLen(line, closed)
    local l = 0
    for i = 1, #line - 1 do l = l + dist(line[i], line[i + 1]) end
    if closed and #line > 2 then l = l + dist(line[#line], line[1]) end
    return l
end

local function covers(line, closed, nodesY, r)
    local n = #line
    for _, p in ipairs(nodesY) do
        local best = math.huge
        for i = 1, n - 1 do best = math.min(best, segDist(p, line[i], line[i + 1])) end
        if closed and n > 2 then best = math.min(best, segDist(p, line[n], line[1])) end
        if n == 1 then best = dist(p, line[1]) end
        if best > r then return false end
    end
    return true
end

local function orient(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end
local function segCross(a, b, c, d)
    local o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0)) and ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0))
end

-- closed polyline quality: crossings, overlap (share within 40 yd of a part >150 yd away along the loop), longest segment, length
local function metrics(poly)
    local n = #poly
    local len, maxseg, cum = 0, 0, { 0 }
    for i = 1, n do
        local d = dist(poly[i], poly[i % n + 1])
        len = len + d; cum[i + 1] = len
        if d > maxseg then maxseg = d end
    end
    local cr = 0
    for i = 1, n do
        for j = i + 2, n do
            if not (i == 1 and j == n) then
                if segCross(poly[i], poly[i % n + 1], poly[j], poly[j % n + 1]) then cr = cr + 1 end
            end
        end
    end
    -- resample every 20 yd
    local samples = {}
    local k = 1
    local s = 0
    while s < len do
        while cum[k + 1] < s do k = k + 1 end
        local a, b = poly[k], poly[k % n + 1]
        local seglen = cum[k + 1] - cum[k]
        local t = seglen > 0 and (s - cum[k]) / seglen or 0
        samples[#samples + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, s }
        s = s + 20
    end
    local close = 0
    for i = 1, #samples do
        for j = 1, #samples do
            local da = math.abs(samples[i][3] - samples[j][3])
            da = math.min(da, len - da)
            if da > 150 and dist(samples[i], samples[j]) <= 40 then close = close + 1; break end
        end
    end
    return { crossings = cr, overlap = #samples > 0 and close / #samples or 0, maxseg = maxseg, len = len }
end

-- 2-opt on a closed polyline: reverse the part between two crossing segments, while the loop grows by at most 2%
-- and each new segment is at most `limit` long
local function untangle(poly0, limit, okfn)
    local poly = {}
    for i, p in ipairs(poly0) do poly[i] = p end
    local n = #poly
    if n < 4 then return poly end
    local cur = 0
    for i = 1, n do cur = cur + dist(poly[i], poly[i % n + 1]) end
    local maxLen = cur * (UNTANGLE_GROWTH or 1.02)
    for _ = 1, 1000 do
        local moved = false
        for i = 1, n - 2 do
            for j = i + 2, n do
                if not (i == 1 and j == n) then
                    local a, b, c, d = poly[i], poly[i + 1], poly[j], poly[j % n + 1]
                    if segCross(a, b, c, d) then
                        local n1, n2 = dist(a, c), dist(b, d)
                        local delta = n1 + n2 - dist(a, b) - dist(c, d)
                        if n1 <= limit and n2 <= limit and cur + delta <= maxLen and (not okfn or (okfn(a, c) and okfn(b, d))) then
                            local lo, hi = i + 1, j
                            while lo < hi do poly[lo], poly[hi] = poly[hi], poly[lo]; lo = lo + 1; hi = hi - 1 end
                            cur = cur + delta
                            moved = true
                            break
                        end
                    end
                end
            end
            if moved then break end
        end
        if not moved then break end
    end
    return poly
end

-- pts: nodes in map percent; W,H: zone size in yards
local function inCircles(circles, p)
    for _, c in ipairs(circles or {}) do if dist(p, c) <= c.r then return true end end
    return false
end
local terrain = dofile(ROOT .. "/tools/terrain.lua")
terrain.csv = ROOT .. "/tools/data/UiMapAssignment.csv"

-- slope that is sustained over at least SPIKE_YD of travel along the straight segment a-b (yards); short spikes are ignored
local function sustainedSlope(uiMap, a, b, W, H)
    local best, prof = terrain.slopeAlong(uiMap, a[1] / W * 100, a[2] / H * 100, b[1] / W * 100, b[2] / H * 100, W, H)
    if best == nil then return nil end
    local np = #prof
    local len = dist(a, b)
    if np == 0 or len < SPIKE_YD then return 0 end
    local step = len / np
    local w = math.min(np, math.max(1, math.ceil(SPIKE_YD / step - 1e-9)))
    local bestV = 0
    for i = 1, np - w + 1 do
        local mn = math.huge
        for k = i, i + w - 1 do if prof[k] < mn then mn = prof[k] end end
        if mn > bestV then bestV = mn end
    end
    return bestV
end

local function polyMaxSlope(poly, W, H, uiMap)
    if not (uiMap and terrain.zone(uiMap)) then return nil end
    local worst = 0
    for i = 1, #poly do
        local s = sustainedSlope(uiMap, poly[i], poly[i % #poly + 1], W, H)
        if s and s > worst then worst = s end
    end
    return worst
end

local function douglasValid(line, tol, ok)
    local n = #line
    if n < 3 then return line end
    local keep = { [1] = true, [n] = true }
    local function rec(i, j)
        if j - i < 2 then return end
        local md, mi = 0, nil
        for k = i + 1, j - 1 do
            local d = segDist(line[k], line[i], line[j])
            if d > md then md, mi = d, k end
        end
        if md <= tol and ok(line[i], line[j]) then return end
        if md <= tol or not mi then mi = (i + j) // 2 end
        keep[mi] = true; rec(i, mi); rec(mi, j)
    end
    rec(1, n)
    local out = {}
    for i = 1, n do if keep[i] then out[#out + 1] = line[i] end end
    return out
end

local function simplifyValid(line, tol, ok) -- closed polyline
    if #line < 4 then return line end
    local far, fd = 1, -1
    for i = 2, #line do local d = dist(line[1], line[i]); if d > fd then fd, far = d, i end end
    local h1, h2 = {}, {}
    for i = 1, far do h1[#h1 + 1] = line[i] end
    for i = far, #line do h2[#h2 + 1] = line[i] end
    h2[#h2 + 1] = line[1]
    local a, b = douglasValid(h1, tol, ok), douglasValid(h2, tol, ok)
    local out = {}
    for i = 1, #a do out[#out + 1] = a[i] end
    for i = 2, #b - 1 do out[#out + 1] = b[i] end
    return out
end

local function subdivide(poly, maxlen)
    local out = {}
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        out[#out + 1] = a
        local k = math.ceil(dist(a, b) / maxlen)
        for s = 1, k - 1 do out[#out + 1] = { a[1] + (b[1] - a[1]) * s / k, a[2] + (b[2] - a[2]) * s / k } end
    end
    return out
end

local DIRS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }

-- pts: nodes in map percent; W,H: zone size in yards; circles: avoid/town circles (yards); uiMap: for terrain
local function buildRoute(pts, W, H, circles, uiMap)
    local n = #pts
    if n == 0 then return nil end
    local D = MAX_SEG
    local Q = {}
    for i, p in ipairs(pts) do Q[i] = { p[1] * W / 100, p[2] * H / 100 } end
    local useT = (uiMap and terrain.zone(uiMap)) and true or false
    local cols = math.ceil(W / GRID) + 2

    -- walkable mask (20 yd cells). Terrain zones: local slope < STEEP, within 400 yd of a node, outside circles.
    -- Zones without terrain: within CORRIDOR of a node.
    local near, memo = {}, {}
    do
        local lim = useT and NEAR_NODE_YD or CORRIDOR
        local rc = math.ceil(lim / GRID)
        for _, p in ipairs(Q) do
            local cx, cy = math.floor(p[1] / GRID), math.floor(p[2] / GRID)
            for dy = -rc, rc do
                for dx = -rc, rc do
                    local x, y = cx + dx, cy + dy
                    if x >= 0 and y >= 0 then
                        local ccx, ccy = (x + 0.5) * GRID, (y + 0.5) * GRID
                        if (ccx - p[1]) ^ 2 + (ccy - p[2]) ^ 2 <= lim * lim then near[y * cols + x] = true end
                    end
                end
            end
        end
    end
    -- cell state: 0 blocked (out of range, circle, no height data), 1 walkable, 2 steep (slope >= STEEP)
    local function cellState(cx, cy)
        if cx < 0 or cy < 0 then return 0 end
        local key = cy * cols + cx
        local v = memo[key]
        if v ~= nil then return v end
        v = 0
        if near[key] then
            if not useT then v = 1
            else
                local px, py = (cx + 0.5) * GRID, (cy + 0.5) * GRID
                if not inCircles(circles, { px, py }) then
                    local s = terrain.localSlope(uiMap, px / W * 100, py / H * 100, 30, W, H)
                    if s ~= nil then v = (s < STEEP) and 1 or 2 end
                end
            end
        end
        memo[key] = v
        return v
    end
    local function isWalkCell(cx, cy) return cellState(cx, cy) == 1 end
    local function isWalkP(x, y)
        if x < 0 or y < 0 then return false end
        return isWalkCell(math.floor(x / GRID), math.floor(y / GRID))
    end
    -- a segment is valid when it stays on walkable cells (steep cells are tolerated for < SPIKE_YD of travel)
    -- and the slope along it is not sustained at or above STEEP
    local function segOK(a, b)
        for _, c in ipairs(circles or {}) do
            if segDist(c, a, b) < c.r then return false end
        end
        local d = dist(a, b)
        local k = math.max(1, math.ceil(d / GRID))
        local step = d / k
        local run = 0
        for s = 0, k do
            local t = s / k
            local x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
            if x < 0 or y < 0 then return false end
            local st = cellState(math.floor(x / GRID), math.floor(y / GRID))
            if st == 0 then return false
            elseif st == 2 then
                run = run + 1
                if run * math.max(step, 1) >= SPIKE_YD then return false end
            else run = 0 end
        end
        if useT then
            local sl = sustainedSlope(uiMap, a, b, W, H)
            if sl == nil or sl >= STEEP then return false end
        end
        return true
    end
    -- steep ground within 40 yd makes a cell more expensive to path through (prefer valley floors)
    local steepMemo = {}
    local function nearSteep(cx, cy)
        local key = cy * cols + cx
        local v = steepMemo[key]
        if v ~= nil then return v end
        v = false
        if useT then
            for dy = -2, 2 do
                for dx = -2, 2 do
                    if cellState(cx + dx, cy + dy) == 2 then v = true; break end
                end
                if v then break end
            end
        end
        steepMemo[key] = v
        return v
    end

    -- anchors: a walkable position within 100 yd of each node (nodes on steep ground are reached from the flat)
    local A = {}
    for i = 1, n do
        local q = Q[i]
        if isWalkP(q[1], q[2]) then A[i] = q
        else
            local cx, cy = math.floor(q[1] / GRID), math.floor(q[2] / GRID)
            local bd, bp = math.huge, nil
            for dy = -5, 5 do
                for dx = -5, 5 do
                    if isWalkCell(cx + dx, cy + dy) then
                        local p = { (cx + dx + 0.5) * GRID, (cy + dy + 0.5) * GRID }
                        local d = dist(p, q)
                        if d < bd then bd, bp = d, p end
                    end
                end
            end
            if bp and bd <= 100 then A[i] = bp end
        end
    end

    local function covCount(poly, idx)
        local c, k = 0, #poly
        for _, i in ipairs(idx) do
            local best = math.huge
            for s = 1, k do
                local d = segDist(Q[i], poly[s], poly[s % k + 1])
                if d < best then best = d end
            end
            if best <= R then c = c + 1 end
        end
        return c
    end

    -- greedy set cover of nodes `idx` with walkable stops (anchors and midpoints of close anchors)
    local function setCover(idx)
        local cands = {}
        for _, i in ipairs(idx) do if A[i] then cands[#cands + 1] = A[i] end end
        for a = 1, #idx do
            local i = idx[a]
            if A[i] then
                for b = a + 1, #idx do
                    local j = idx[b]
                    if A[j] and dist(A[i], A[j]) <= 2 * R then
                        local mid = { (A[i][1] + A[j][1]) / 2, (A[i][2] + A[j][2]) / 2 }
                        if isWalkP(mid[1], mid[2]) and not inCircles(circles, mid) then cands[#cands + 1] = mid end
                    end
                end
            end
        end
        local cover = {}
        for c, cp in ipairs(cands) do
            local s = {}
            for a, i in ipairs(idx) do if dist(cp, Q[i]) <= R then s[#s + 1] = a end end
            cover[c] = s
        end
        local covered, ncov, S = {}, 0, {}
        while ncov < #idx do
            local bc, bn = nil, 0
            for c = 1, #cands do
                local k = 0
                for _, a in ipairs(cover[c]) do if not covered[a] then k = k + 1 end end
                if k > bn then bc, bn = c, k end
            end
            if not bc then break end
            S[#S + 1] = cands[bc]
            for _, a in ipairs(cover[bc]) do if not covered[a] then covered[a] = true; ncov = ncov + 1 end end
        end
        return S
    end

    ------------------------------------------------------------ method b: stop tour
    local compRank
    local function tourMethod(rank)
        -- walkable components of the 20 yd grid; the region is the component holding the most nodes
        local label = {}
        local ncomp = 0
        for key in pairs(near) do
            if label[key] == nil then
                local cx, cy = key % cols, key // cols
                if isWalkCell(cx, cy) then
                    ncomp = ncomp + 1
                    label[key] = ncomp
                    local stack = { key }
                    while #stack > 0 do
                        local k2 = table.remove(stack)
                        local x, y = k2 % cols, k2 // cols
                        for _, d in ipairs(DIRS) do
                            local nx, ny = x + d[1], y + d[2]
                            if nx >= 0 and ny >= 0 then
                                local nk = ny * cols + nx
                                local corner = (d[1] == 0 or d[2] == 0) or (isWalkCell(x + d[1], y) and isWalkCell(x, y + d[2]))
                                if corner and near[nk] and label[nk] == nil and isWalkCell(nx, ny) then label[nk] = ncomp; stack[#stack + 1] = nk end
                            end
                        end
                    end
                else
                    label[key] = 0
                end
            end
        end
        local function compOf(p) return label[math.floor(p[2] / GRID) * cols + math.floor(p[1] / GRID)] end
        local cn = {}
        for i = 1, n do
            if A[i] then local l = compOf(A[i]); if l and l > 0 then cn[l] = (cn[l] or 0) + 1 end end
        end
        local ranked = {}
        for l, c in pairs(cn) do ranked[#ranked + 1] = { l, c } end
        table.sort(ranked, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
        compRank = ranked
        local bestComp = ranked[rank or 1] and ranked[rank or 1][1]
        if not bestComp then return nil end
        local cand = {}
        for i = 1, n do if A[i] and compOf(A[i]) == bestComp then cand[#cand + 1] = i end end
        -- grow the region from the best-connected node (straight valid links first, nearest node otherwise)
        local nb = {}
        for _, i in ipairs(cand) do nb[i] = {} end
        for a = 1, #cand do
            local i = cand[a]
            for b = a + 1, #cand do
                local j = cand[b]
                local d = dist(A[i], A[j])
                if d <= MAX_SEG and segOK(A[i], A[j]) then
                    nb[i][#nb[i] + 1] = { j, d }; nb[j][#nb[j] + 1] = { i, d }
                end
            end
        end
        local seed = cand[1]
        for _, i in ipairs(cand) do if #nb[i] > #nb[seed] then seed = i end end
        local inRegion, sel, bestD = { [seed] = true }, { seed }, {}
        local function relax(v)
            for _, e in ipairs(nb[v]) do
                local w, d = e[1], e[2]
                if not inRegion[w] and (not bestD[w] or d < bestD[w]) then bestD[w] = d end
            end
        end
        relax(seed)
        while #sel < MAXNODES and #sel < #cand do
            local pick, pd
            for w, d in pairs(bestD) do
                if not inRegion[w] and (not pd or d < pd or (d == pd and w < pick)) then pick, pd = w, d end
            end
            if not pick then
                for _, j in ipairs(cand) do
                    if not inRegion[j] then
                        local d = math.huge
                        for _, i in ipairs(sel) do d = math.min(d, dist(A[i], A[j])) end
                        if not pd or d < pd then pick, pd = j, d end
                    end
                end
            end
            if not pick then break end
            inRegion[pick] = true; sel[#sel + 1] = pick; bestD[pick] = nil
            relax(pick)
        end
        local S0 = setCover(sel)
        if #S0 < 2 then return nil end

        -- grid pathfinding: Dijkstra over 8-connected walkable cells from every stop
        local function keyOf(p) return math.floor(p[2] / GRID) * cols + math.floor(p[1] / GRID) end
        local function dijkstra(sk)
            local dd, prv = { [sk] = 0 }, {}
            local hd, hk, hn = { 0 }, { sk }, 1
            local function push(d, k)
                hn = hn + 1
                local i = hn
                while i > 1 do
                    local p = i // 2
                    if hd[p] <= d then break end
                    hd[i], hk[i] = hd[p], hk[p]; i = p
                end
                hd[i], hk[i] = d, k
            end
            while hn > 0 do
                local d, k = hd[1], hk[1]
                local ld, lk = hd[hn], hk[hn]
                hn = hn - 1
                if hn > 0 then
                    local i = 1
                    while true do
                        local c = i * 2
                        if c > hn then break end
                        if c < hn and hd[c + 1] < hd[c] then c = c + 1 end
                        if hd[c] >= ld then break end
                        hd[i], hk[i] = hd[c], hk[c]; i = c
                    end
                    hd[i], hk[i] = ld, lk
                end
                if d == dd[k] then
                    local x, y = k % cols, k // cols
                    for _, dr in ipairs(DIRS) do
                        local dx, dy = dr[1], dr[2]
                        local nx, ny = x + dx, y + dy
                        if isWalkCell(nx, ny) and (dx == 0 or dy == 0 or (isWalkCell(x + dx, y) and isWalkCell(x, y + dy))) then
                            local step = (dx ~= 0 and dy ~= 0) and 28.284 or 20
                            if nearSteep(nx, ny) then step = step * STEEP_COST end
                            local nd, nk = d + step, ny * cols + nx
                            if not dd[nk] or nd < dd[nk] then dd[nk] = nd; prv[nk] = k; push(nd, nk) end
                        end
                    end
                end
            end
            return dd, prv
        end
        local DD0, PV0 = {}, {}
        for a = 1, #S0 do DD0[a], PV0[a] = dijkstra(keyOf(S0[a])) end
        -- keep the largest group of stops that reach each other
        local lab, nl, lsz = {}, 0, {}
        for a = 1, #S0 do
            if not lab[a] then
                nl = nl + 1; lab[a] = nl
                local c = 1
                for b = 1, #S0 do
                    if not lab[b] and DD0[a][keyOf(S0[b])] then lab[b] = nl; c = c + 1 end
                end
                lsz[nl] = c
            end
        end
        local bl = 1
        for l = 2, nl do if lsz[l] > lsz[bl] then bl = l end end
        local S, DD, PV = {}, {}, {}
        for a = 1, #S0 do
            if lab[a] == bl then S[#S + 1] = S0[a]; DD[#S] = DD0[a]; PV[#S] = PV0[a] end
        end
        local ns_ = #S
        if ns_ < 2 then return nil end
        local C = {}
        for a = 1, ns_ do
            C[a] = {}
            for b = 1, ns_ do C[a][b] = (a == b) and 0 or (DD[a][keyOf(S[b])] or math.huge) end
        end
        for a = 1, ns_ do for b = a + 1, ns_ do
            local v = math.min(C[a][b], C[b][a]); C[a][b] = v; C[b][a] = v
        end end
        local function G(a, b) return C[a][b] end
        -- region nodes actually reached by the stops
        local reg = {}
        for _, i in ipairs(sel) do
            for _, s in ipairs(S) do
                if dist(Q[i], s) <= R then reg[#reg + 1] = i; break end
            end
        end
        local m = #reg
        local N = {}
        for i, idx in ipairs(reg) do N[i] = Q[idx] end

        local function tourCost(t)
            local c = 0
            for i = 1, #t do c = c + G(t[i], t[i % #t + 1]) end
            return c
        end
        local function improve(tour)
            local ns_ = #tour
            if ns_ >= 4 then
                local improved, iter = true, 0
                while improved and iter < 100 do
                    improved = false; iter = iter + 1
                    for i = 1, ns_ - 1 do
                        for j = i + 1, ns_ do
                            local a, b = tour[i], tour[i % ns_ + 1]
                            local c, d = tour[j], tour[j % ns_ + 1]
                            if a ~= c and b ~= c and a ~= d then
                                if G(a, c) + G(b, d) - G(a, b) - G(c, d) < -1e-9 then
                                    local lo, hi = i + 1, j
                                    while lo < hi do tour[lo], tour[hi] = tour[hi], tour[lo]; lo = lo + 1; hi = hi - 1 end
                                    improved = true
                                end
                            end
                        end
                    end
                    for seg = 1, math.min(3, ns_ - 3) do
                        for i = 1, ns_ do
                            local cur = tourCost(tour)
                            local segnodes, rest = {}, {}
                            for k = 0, seg - 1 do segnodes[#segnodes + 1] = tour[(i + k - 1) % ns_ + 1] end
                            for k = seg, ns_ - 1 do rest[#rest + 1] = tour[(i + k - 1) % ns_ + 1] end
                            local bestT, bestC = nil, cur - 1e-9
                            for pos = 1, #rest do
                                for rev = 0, 1 do
                                    local t2 = {}
                                    for k = 1, pos do t2[#t2 + 1] = rest[k] end
                                    if rev == 0 then for k = 1, seg do t2[#t2 + 1] = segnodes[k] end
                                    else for k = seg, 1, -1 do t2[#t2 + 1] = segnodes[k] end end
                                    for k = pos + 1, #rest do t2[#t2 + 1] = rest[k] end
                                    local c = tourCost(t2)
                                    if c < bestC then bestC, bestT = c, t2 end
                                end
                            end
                            if bestT then tour = bestT; improved = true end
                        end
                    end
                end
            end
            return tour
        end
        local function solve(start)
            local tour, used = { start }, { [start] = true }
            for _ = 2, ns_ do
                local cur, bj, bd = tour[#tour], nil, math.huge
                for j = 1, ns_ do
                    if not used[j] and G(cur, j) < bd then bd, bj = G(cur, j), j end
                end
                tour[#tour + 1] = bj; used[bj] = true
            end
            return improve(tour)
        end
        local starts, seenStart = {}, {}
        for _, s in ipairs { 1, ns_ // 4 + 1, ns_ // 2 + 1, (3 * ns_) // 4 + 1, ns_ } do
            if not seenStart[s] then seenStart[s] = true; starts[#starts + 1] = s end
        end
        local tour, tourBest
        for _, s in ipairs(starts) do
            local t = solve(s)
            local c = tourCost(t)
            if not tourBest or c < tourBest then tour, tourBest = t, c end
        end
        -- spur pruning (90 yd per node, 85% of the reachable region must stay covered)
        local preLen, preStops = tourBest, #tour
        local stopCover = {}
        for k = 1, ns_ do
            stopCover[k] = {}
            for i = 1, m do if dist(S[k], N[i]) <= R then table.insert(stopCover[k], i) end end
        end
        local cnt, covered = {}, 0
        for i = 1, m do cnt[i] = 0 end
        for _, k in ipairs(tour) do for _, i in ipairs(stopCover[k]) do cnt[i] = cnt[i] + 1 end end
        for i = 1, m do if cnt[i] > 0 then covered = covered + 1 end end
        local pruned = false
        while #tour > 3 and not os.getenv("PROFPATH_NOPRUNE") do
            local bestPos, bestRatio, bestLost
            for pos = 1, #tour do
                local t = tour[pos]
                local prv, nxt = tour[(pos - 2) % #tour + 1], tour[pos % #tour + 1]
                local lost = 0
                for _, i in ipairs(stopCover[t]) do if cnt[i] == 1 then lost = lost + 1 end end
                local saved = G(prv, t) + G(t, nxt) - G(prv, nxt)
                local ratio = lost == 0 and math.huge or saved / lost
                if (lost == 0 or (ratio > SPUR_YD_PER_NODE and covered - lost >= MIN_COVER * m)) and (not bestRatio or ratio > bestRatio) then
                    bestPos, bestRatio, bestLost = pos, ratio, lost
                end
            end
            if not bestPos then break end
            local t = table.remove(tour, bestPos)
            for _, i in ipairs(stopCover[t]) do cnt[i] = cnt[i] - 1 end
            covered = covered - bestLost
            pruned = true
        end
        if pruned then tour = improve(tour) end
        local postLen = tourCost(tour)
        local tourStops = {}
        for _, k in ipairs(tour) do tourStops[#tourStops + 1] = S[k] end
        local nt = #tour

        -- expand each hop into its grid path, string-pulled into straight valid pieces (cap PATH_CAP)
        local function cellPath(a, b)
            local path = {}
            local k, ka = keyOf(S[b]), keyOf(S[a])
            while k and k ~= ka do
                table.insert(path, 1, { ((k % cols) + 0.5) * GRID, ((k // cols) + 0.5) * GRID })
                k = PV[a][k]
            end
            table.insert(path, 1, S[a])
            path[#path] = S[b]
            return path
        end
        local function pull(path, cap)
            local out = { path[1] }
            local anchor = 1
            while anchor < #path do
                local far = anchor + 1
                for j = anchor + 2, #path do
                    if dist(path[anchor], path[j]) > cap then break end
                    if segOK(path[anchor], path[j]) then far = j else break end
                end
                out[#out + 1] = path[far]; anchor = far
            end
            return out
        end
        local poly, longPieces = {}, 0
        for i = 1, nt do
            local a, b = tour[i], tour[i % nt + 1]
            if a ~= b then
                local path = cellPath(a, b)
                local free = pull(path, math.huge)
                for q = 1, #free - 1 do if dist(free[q], free[q + 1]) > PATH_CAP then longPieces = longPieces + 1 end end
                local capped = pull(path, PATH_CAP)
                for q = 1, #capped - 1 do poly[#poly + 1] = capped[q] end
            end
        end
        poly = untangle(poly, PATH_CAP, segOK)
        return { poly = poly, idx = reg, stops = nt, preLen = preLen, postLen = postLen, preStops = preStops, covered = covered, region = m, stopsY = tourStops, longPieces = longPieces }
    end

    ------------------------------------------------------------ method a: lap along the edge of the valley
    local function edgeMethod()
        if not useT then return nil end
        -- walkable components over cells near nodes
        local label, ncomp, csize = {}, 0, {}
        for key in pairs(near) do
            if label[key] == nil then
                local cx, cy = key % cols, key // cols
                if isWalkCell(cx, cy) then
                    ncomp = ncomp + 1
                    label[key] = ncomp
                    local stack, sz = { key }, 0
                    while #stack > 0 do
                        local k2 = table.remove(stack); sz = sz + 1
                        local x, y = k2 % cols, k2 // cols
                        for _, d in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
                            local nx, ny = x + d[1], y + d[2]
                            if nx >= 0 and ny >= 0 then
                                local nk = ny * cols + nx
                                if near[nk] and label[nk] == nil and isWalkCell(nx, ny) then label[nk] = ncomp; stack[#stack + 1] = nk end
                            end
                        end
                    end
                    csize[ncomp] = sz
                else
                    label[key] = 0
                end
            end
        end
        if ncomp == 0 then return nil end
        local compNodes = {}
        for i = 1, n do
            if A[i] then
                local l = label[math.floor(A[i][2] / GRID) * cols + math.floor(A[i][1] / GRID)]
                if l and l > 0 then compNodes[l] = (compNodes[l] or 0) + 1 end
            end
        end
        local bestC, bestN = nil, 0
        for l, c in pairs(compNodes) do if c > bestN then bestC, bestN = l, c end end
        if not bestC then return nil end
        local idx = {}
        for i = 1, n do
            if A[i] then
                local l = label[math.floor(A[i][2] / GRID) * cols + math.floor(A[i][1] / GRID)]
                if l == bestC then idx[#idx + 1] = i end
            end
        end
        local Cset = {}
        for key, l in pairs(label) do if l == bestC then Cset[key] = true end end
        -- erode by 40 yd (2 cells), then 1 cell, then 0 if nothing is left; keep the largest 8-connected part
        local E
        for _, rad in ipairs { 2, 1, 0 } do
            E = {}
            local cntE = 0
            for key in pairs(Cset) do
                local x, y = key % cols, key // cols
                local keep = true
                if rad > 0 then
                    for dy = -rad, rad do
                        for dx = -rad, rad do
                            if dx * dx + dy * dy <= rad * rad and not Cset[(y + dy) * cols + x + dx] then keep = false; break end
                        end
                        if not keep then break end
                    end
                end
                if keep then E[key] = true; cntE = cntE + 1 end
            end
            if cntE >= 30 then break end
        end
        -- largest 8-connected part
        local lab2, best2, bestSize = {}, nil, 0
        for key in pairs(E) do
            if not lab2[key] then
                local stack, members = { key }, {}
                lab2[key] = true
                while #stack > 0 do
                    local k2 = table.remove(stack); members[#members + 1] = k2
                    local x, y = k2 % cols, k2 // cols
                    for _, d in ipairs(DIRS) do
                        local nk = (y + d[2]) * cols + x + d[1]
                        if E[nk] and not lab2[nk] then lab2[nk] = true; stack[#stack + 1] = nk end
                    end
                end
                if #members > bestSize then best2, bestSize = members, #members end
            end
        end
        if not best2 or bestSize < 10 then return nil end
        local E1 = {}
        for _, k2 in ipairs(best2) do E1[k2] = true end
        -- Moore-neighbour trace of the outer boundary
        local sx, sy
        for key in pairs(E1) do
            local x, y = key % cols, key // cols
            if not sy or y < sy or (y == sy and x < sx) then sx, sy = x, y end
        end
        local function inE(x, y) return x >= 0 and y >= 0 and E1[y * cols + x] == true end
        local bnd = { { sx, sy } }
        local cx, cy, bd = sx, sy, 7
        local fx, fy
        for _ = 1, 400000 do
            local found
            for k = 1, 8 do
                local d = ((bd - 1 + k) % 8) + 1
                local nx, ny = cx + DIRS[d][1], cy + DIRS[d][2]
                if inE(nx, ny) then
                    local dp = ((bd - 1 + k - 1) % 8) + 1
                    local bx, by = cx + DIRS[dp][1], cy + DIRS[dp][2]
                    found = { nx, ny, bx - nx, by - ny }
                    break
                end
            end
            if not found then break end
            if cx == sx and cy == sy and fx and found[1] == fx and found[2] == fy then break end
            if not fx then fx, fy = found[1], found[2] end
            cx, cy = found[1], found[2]
            for d = 1, 8 do if DIRS[d][1] == found[3] and DIRS[d][2] == found[4] then bd = d end end
            bnd[#bnd + 1] = { cx, cy }
            if cx == sx and cy == sy and #bnd > 2 and false then break end
        end
        -- the trace re-enters the start cell; drop the duplicate closing point
        if #bnd > 1 and bnd[#bnd][1] == sx and bnd[#bnd][2] == sy then bnd[#bnd] = nil end
        local poly = {}
        for _, c in ipairs(bnd) do
            local p = { (c[1] + 0.5) * GRID, (c[2] + 0.5) * GRID }
            local last = poly[#poly]
            if not last or last[1] ~= p[1] or last[2] ~= p[2] then poly[#poly + 1] = p end
        end
        if #poly < 8 then return nil end
        -- skip stretches far (> FAR_YD) from every node by a valid chord
        do
            local far = {}
            local anyFar, anyNear = false, false
            for i, p in ipairs(poly) do
                local nearest = math.huge
                for _, q in ipairs(Q) do
                    local d = dist(p, q)
                    if d < nearest then nearest = d end
                end
                far[i] = nearest > FAR_YD
                if far[i] then anyFar = true else anyNear = true end
            end
            if anyFar and anyNear then
                local s0 = 1
                while far[s0] do s0 = s0 + 1 end
                local out, i, cnt2 = {}, 0, #poly
                while i < cnt2 do
                    local idx0 = (s0 - 1 + i) % cnt2 + 1
                    if not far[idx0] then
                        out[#out + 1] = poly[idx0]; i = i + 1
                    else
                        local j = i
                        while j < cnt2 and far[(s0 - 1 + j) % cnt2 + 1] do j = j + 1 end
                        local p, q = out[#out], poly[(s0 - 1 + j) % cnt2 + 1]
                        if not segOK(p, q) then
                            for t = i, j - 1 do out[#out + 1] = poly[(s0 - 1 + t) % cnt2 + 1] end
                        end
                        i = j
                    end
                end
                poly = out
            end
        end
        poly = simplifyValid(poly, EDGE_DP, segOK)
        -- chord shortcuts over stretches that cover no node on their own
        for _ = 1, 40 do
            local V = #poly
            if V < 6 then break end
            local segNodes, cntN = {}, {}
            for k = 1, V do
                local a, b = poly[k], poly[k % V + 1]
                local l = {}
                for _, i in ipairs(idx) do
                    if segDist(Q[i], a, b) <= R then l[#l + 1] = i; cntN[i] = (cntN[i] or 0) + 1 end
                end
                segNodes[k] = l
            end
            local seglen = {}
            for k = 1, V do seglen[k] = dist(poly[k], poly[k % V + 1]) end
            local bestSave, bi, bj = 0, nil, nil
            for i = 1, V do
                local walk = 0
                for step = 1, math.min(V - 2, 80) do
                    walk = walk + seglen[(i + step - 2) % V + 1]
                    local j = (i + step - 1) % V + 1
                    if step >= 2 and walk > MIN_SKIP_WALK then
                        local chord = dist(poly[i], poly[j])
                        local save = walk - chord
                        if save > bestSave + 1e-9 and save > 60 then
                            local rem, lost = {}, false
                            for t = 0, step - 1 do
                                for _, nd in ipairs(segNodes[(i + t - 1) % V + 1]) do rem[nd] = (rem[nd] or 0) + 1 end
                            end
                            for nd, rc in pairs(rem) do
                                if cntN[nd] - rc == 0 and segDist(Q[nd], poly[i], poly[j]) > R then lost = true; break end
                            end
                            if not lost and segOK(poly[i], poly[j]) then bestSave, bi, bj = save, i, j end
                        end
                    end
                end
            end
            if not bi then break end
            local np = {}
            local k = bi
            np[1] = poly[bi]
            local t = bj
            while true do
                np[#np + 1] = poly[t]
                if t == bi then break end
                t = t % V + 1
            end
            np[#np] = nil
            poly = np
        end
        -- detours for clusters of uncovered nodes
        poly = subdivide(poly, 150)
        local function uncovered()
            local u = {}
            for _, i in ipairs(idx) do
                local best = math.huge
                for k = 1, #poly do
                    local d = segDist(Q[i], poly[k], poly[k % #poly + 1])
                    if d < best then best = d end
                end
                if best > R then u[#u + 1] = i end
            end
            return u
        end
        local U = uncovered()
        local seen, clusters = {}, {}
        for _, i in ipairs(U) do
            if not seen[i] then
                local cl, stack = {}, { i }
                seen[i] = true
                while #stack > 0 do
                    local a = table.remove(stack); cl[#cl + 1] = a
                    for _, b in ipairs(U) do
                        if not seen[b] and dist(Q[a], Q[b]) <= 2 * R then seen[b] = true; stack[#stack + 1] = b end
                    end
                end
                clusters[#clusters + 1] = cl
            end
        end
        table.sort(clusters, function(a, b) return #a > #b end)
        local accepted = 0
        for ci, cl in ipairs(clusters) do
            if ci > 40 then break end
            local S = setCover(cl)
            if #S > 0 then
                local V = #poly
                -- order stops by nearest neighbour from the stop closest to the loop
                local order = {}
                do
                    local pool, startI, sd = {}, nil, math.huge
                    for si, s in ipairs(S) do
                        pool[si] = true
                        local d = math.huge
                        for _, p in ipairs(poly) do d = math.min(d, dist(s, p)) end
                        if d < sd then sd, startI = d, si end
                    end
                    order[1] = S[startI]; pool[startI] = nil
                    while next(pool) do
                        local last, bj, bdd = order[#order], nil, math.huge
                        for si in pairs(pool) do
                            local d = dist(last, S[si])
                            if d < bdd then bdd, bj = d, si end
                        end
                        order[#order + 1] = S[bj]; pool[bj] = nil
                    end
                end
                local cx0, cy0 = order[1][1], order[1][2]
                local edges = {}
                for k = 1, V do
                    local a, b = poly[k], poly[k % V + 1]
                    edges[#edges + 1] = { k, dist({ (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 }, { cx0, cy0 }) }
                end
                table.sort(edges, function(a, b) return a[2] < b[2] end)
                local bestExtra, bestK, bestRev
                for e = 1, math.min(12, #edges) do
                    local k = edges[e][1]
                    local a, b = poly[k], poly[k % V + 1]
                    for rev = 0, 1 do
                        local seq = { a }
                        if rev == 0 then for _, s in ipairs(order) do seq[#seq + 1] = s end
                        else for q = #order, 1, -1 do seq[#seq + 1] = order[q] end end
                        seq[#seq + 1] = b
                        local ok, len = true, 0
                        for q = 1, #seq - 1 do
                            if not segOK(seq[q], seq[q + 1]) then ok = false; break end
                            len = len + dist(seq[q], seq[q + 1])
                        end
                        if ok then
                            local extra = len - dist(a, b)
                            if not bestExtra or extra < bestExtra then bestExtra, bestK, bestRev = extra, k, rev end
                        end
                    end
                end
                if bestK then
                    local newCov = #cl
                    if bestExtra / newCov < DETOUR_YD_PER_NODE then
                        local np = {}
                        for k = 1, V do
                            np[#np + 1] = poly[k]
                            if k == bestK then
                                if bestRev == 0 then for _, s in ipairs(order) do np[#np + 1] = s end
                                else for q = #order, 1, -1 do np[#np + 1] = order[q] end end
                            end
                        end
                        poly = np
                        accepted = accepted + 1
                    end
                end
            end
        end
        return { poly = poly, idx = idx, stops = #poly, preLen = 0, postLen = 0, preStops = 0, covered = 0, region = #idx, stopsY = poly }
    end

    ------------------------------------------------------------ choose
    local tour = tourMethod()
    local edge = edgeMethod()
    local cands = {}
    for name, c in pairs { tour = tour, edge = edge } do
        if c then
            c.method = name
            c.len = polyLen(c.poly, true)
            c.cov = covCount(c.poly, c.idx)
            c.frac = c.cov / math.max(1, #c.idx)
            c.ypn = c.len / math.max(1, c.cov)
            cands[#cands + 1] = c
        end
    end
    if #cands == 0 then return nil end
    table.sort(cands, function(a, b)
        local ea, eb = a.frac >= MIN_EDGE_COVER, b.frac >= MIN_EDGE_COVER
        if ea ~= eb then return ea end
        if ea then return a.ypn < b.ypn end
        return a.frac > b.frac
    end)
    local function finish(win, altStr)
    local final = win.poly
    local allIdx = {}
    for i = 1, n do allIdx[i] = i end
    local covAll = covCount(final, allIdx)
    local met = metrics(final)
    local flat = {}
    for _, p in ipairs(final) do
        flat[#flat + 1] = string.format("%.1f", p[1] / W * 100)
        flat[#flat + 1] = string.format("%.1f", p[2] / H * 100)
    end
    local usable = {}
    for _, up in ipairs(USABLE[uiMap] or {}) do
        local py = { up[1] * W / 100, up[2] * H / 100 }
        local best = math.huge
        for k = 1, #final do best = math.min(best, segDist(py, final[k], final[k % #final + 1])) end
        local ls = useT and terrain.localSlope(uiMap, up[1], up[2], 30, W, H)
        usable[#usable + 1] = string.format("(%.1f,%.1f) cell=%d slope=%s route=%dyd", up[1], up[2], cellState(math.floor(py[1] / GRID), math.floor(py[2] / GRID)), ls and string.format("%.2f", ls) or "n/a", math.floor(best + 0.5))
    end
    return { longPieces = win.longPieces or 0, usable = table.concat(usable, "; "), flat = flat, D = D, stops = win.stops, share = covAll / n, open = false, maxhop = met.maxseg,
        preLen = win.preLen, postLen = win.postLen, preCov = win.region, postCov = win.covered, preStops = win.preStops, region = win.region,
        len = met.len, pts = #final, crossings = met.crossings, overlap = met.overlap, stopsY = win.stopsY, polyY = final,
        method = win.method, maxslope = polyMaxSlope(final, W, H, uiMap),
        alt = altStr }
    end
    local res = finish(cands[1], (cands[2] and string.format("%s len=%.0f cov=%d/%d ypn=%.0f", cands[2].method, cands[2].len, cands[2].cov, #cands[2].idx, cands[2].ypn)) or "")
    -- a second walkable component with at least 40% as many nodes gets its own loop
    if tour and compRank and compRank[2] and compRank[2][2] >= 0.4 * compRank[1][2] then
        local t2 = tourMethod(2)
        if t2 then
            t2.method = "tour"
            local sec = finish(t2, "component 2")
            sec.compNodes = compRank[2][2]
            local coveredN = math.floor(sec.share * n + 0.5)
            if sec.overlap <= 0.4 and sec.crossings <= 2 and coveredN >= 15 then res.second = sec end
        end
    end
    res.compNodes = compRank and compRank[1] and compRank[1][2] or 0
    res.compCount = compRank and #compRank or 0
    return res
end

---------------------------------------------------------------- Build
local overrides = {}
do
    local fh = io.open(ROOT .. "/tools/data/route-overrides.json", "rb")
    if fh then
        local txt = fh:read("a"); fh:close()
        txt = txt:gsub("^\239\187\191", "")
        overrides = parse_json(txt)
    end
end
local function applyOverride(gen, ov, pts, W, H, uiMap)
    local poly, flat = {}, {}
    for i = 1, #ov.route - 1, 2 do poly[#poly + 1] = { ov.route[i] * W / 100, ov.route[i + 1] * H / 100 } end
    if #poly > 1 and dist(poly[1], poly[#poly]) < 1 then poly[#poly] = nil end
    for _, p in ipairs(poly) do
        flat[#flat + 1] = string.format("%.1f", p[1] / W * 100)
        flat[#flat + 1] = string.format("%.1f", p[2] / H * 100)
    end
    local met = metrics(poly)
    local cov = 0
    for _, p in ipairs(pts) do
        local py, best = { p[1] * W / 100, p[2] * H / 100 }, math.huge
        for k = 1, #poly do best = math.min(best, segDist(py, poly[k], poly[k % #poly + 1])) end
        if best <= R then cov = cov + 1 end
    end
    return { flat = flat, D = gen.D, stops = #poly, share = cov / #pts, open = false, maxhop = met.maxseg, len = met.len,
        crossings = met.crossings, overlap = met.overlap, stopsY = {}, polyY = poly, manual = true, note = ov.note, method = "manual", maxslope = polyMaxSlope(poly, W, H, uiMap) }
end
local towns, avoid = {}, {}
do
    local fh = io.open(ROOT .. "/tools/data/towns.csv", "rb")
    if fh then
        local first = true
        for line in fh:lines() do
            if first then first = false else
                local um, x, y, sd, nm = line:gsub("\r", ""):match("^(%d+),([%d.]+),([%d.]+),(%a),(.*)$")
                if um then
                    um = tonumber(um)
                    towns[um] = towns[um] or {}
                    table.insert(towns[um], { tonumber(x), tonumber(y), sd, (nm:gsub('^"', ""):gsub('"$', "")) })
                end
            end
        end
        fh:close()
    end
    local ah = io.open(ROOT .. "/tools/data/route-avoid.json", "rb")
    if ah then
        local txt = ah:read("a"); ah:close()
        avoid = parse_json((txt:gsub("^\239\187\191", ""))) or {}
    end
end
-- circles (yards) to keep out of in a zone: hostile towns and avoid areas
local circleCache = {}
local function zoneCircles(area)
    if circleCache[area] then return circleCache[area] end
    local z = zones[area]
    local sz = size[z.map]
    local res = { town = {}, avoid = {} }
    for _, t in ipairs(towns[z.map] or {}) do
        local hostile = (z.side == "A" and t[3] == "H") or (z.side == "H" and t[3] == "A")
            or (z.side == "C" and (t[3] == "A" or t[3] == "H"))
        if hostile then res.town[#res.town + 1] = { t[1] * sz[1] / 100, t[2] * sz[2] / 100, r = TOWN_RADIUS, name = t[4] } end
    end
    for _, a in ipairs(avoid[tostring(z.map)] or {}) do
        res.avoid[#res.avoid + 1] = { a.x * sz[1] / 100, a.y * sz[2] / 100, r = a.r, note = a.note }
    end
    res.all = {}
    for _, c in ipairs(res.town) do res.all[#res.all + 1] = c end
    for _, c in ipairs(res.avoid) do res.all[#res.all + 1] = c end
    circleCache[area] = res
    return res
end

local function usefulPoints(prof, area, s)
    local pts = {}
    for name, req in pairs(SKILL[prof]) do
        if req <= s + 10 and req + 100 > s then
            local list = nodes[prof][name] and nodes[prof][name][area]
            if list then for _, p in ipairs(list) do pts[#pts + 1] = p end end
        end
    end
    table.sort(pts, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    pts = dedupe(pts)
    local zc = zoneCircles(area)
    local sz = size[zones[area].map]
    local keep, et, ea = {}, 0, 0
    for _, p in ipairs(pts) do
        local py = { p[1] * sz[1] / 100, p[2] * sz[2] / 100 }
        if inCircles(zc.town, py) then et = et + 1
        elseif inCircles(zc.avoid, py) then ea = ea + 1
        else keep[#keep + 1] = p end
    end
    return keep, et, ea
end

local unmatched = {}
local function areaOf(name)
    local a = byName[name]
    if not a then unmatched[name] = true end
    return a
end

local report = {}
local nroutes, nopen, globalMax = 0, 0, 0
local metricRows = {}
local flagRows, slopeViol, methodCount = {}, {}, {}
local totalLong = 0
local function checkScore(r)
    local slopeTerm = 0
    if r.maxslope then slopeTerm = r.maxslope >= STEEP and 5 or 0 elseif r.maxhop > 300 then slopeTerm = 2 end
    return r.crossings * 3 + r.overlap * 10 + slopeTerm + (r.share < 0.3 and 1 or 0)
end
local reviewRoutes = {}
local function r1(v) return string.format("%.1f", v) end
local out = { "-- Generated by tools/build_routes.lua from Wowhead WoW: Forever node data (wowhead.com/forever). Do not edit.",
    "local _, ns = ...", "ns.Routes = {" }

local function pickZones(prof, band)
    local from, to, guide, starter = band[1], band[2], band[3], band[4]
    local gathering = SKILL[prof] ~= nil
    local cand, seen = {}, {}
    local function add(area, isGuide)
        if seen[area] then return end
        seen[area] = true
        local c = { area = area, guide = isGuide }
        if gathering then
            c.pts, c.et, c.ea = usefulPoints(prof, area, from); c.nodes = #c.pts
        end
        cand[#cand + 1] = c
    end
    local guideList = {}
    for _, name in ipairs(guide) do
        local a = areaOf(name)
        if a then guideList[#guideList + 1] = a end
    end
    local list = {}
    local cap = MAXZONES
    if starter then cap = #guideList end -- keep every starter zone so both factions are covered
    for _, a in ipairs(guideList) do add(a, true); list[#list + 1] = cand[#cand] end
    if gathering then
        local others = {}
        for area in pairs(zones) do
            if not seen[area] then
                local pts, et, ea = usefulPoints(prof, area, from)
                if #pts > 0 then others[#others + 1] = { area = area, pts = pts, nodes = #pts, et = et, ea = ea } end
            end
        end
        table.sort(others, function(a, b) if a.nodes ~= b.nodes then return a.nodes > b.nodes end return a.area < b.area end)
        if starter then
            -- sort starters by node count, drop empty ones
            table.sort(list, function(a, b) if a.nodes ~= b.nodes then return a.nodes > b.nodes end return a.area < b.area end)
            local keep = {}
            for _, c in ipairs(list) do if c.nodes > 0 then keep[#keep + 1] = c end end
            list = keep
        else
            local keep = {}
            for _, c in ipairs(list) do if c.nodes > 0 then keep[#keep + 1] = c end end
            list = keep
            for _, o in ipairs(others) do
                if #list >= cap then break end
                o.guide = false; list[#list + 1] = o
            end
            while #list > cap do list[#list] = nil end
        end
    end
    return list
end

for _, prof in ipairs { "mining", "herbalism", "skinning", "fishing" } do
    out[#out + 1] = "  " .. prof .. " = {"
    for bi, band in ipairs(BANDS[prof]) do
        local from, to = band[1], band[2]
        local list = pickZones(prof, band)
        out[#out + 1] = string.format("    { from = %d, to = %d, zones = {", from, to)
        local line = { string.format("%s %d-%d:", prof, from, to) }
        for zi, c in ipairs(list) do
            local z = zones[c.area]
            if SKILL[prof] then
                local sz = assert(size[z.map], 'no yard size for uiMap ' .. z.map)
                local circ = {}
                for _, cc in ipairs(zoneCircles(c.area).all) do circ[#circ + 1] = cc end
                for _, fp in ipairs(FLAGGED[z.map] or {}) do -- verified impassable points: hard 70 yd keep-out
                    circ[#circ + 1] = { fp[1] * sz[1] / 100, fp[2] * sz[2] / 100, r = FLAG_KEEPOUT }
                end
                local r0 = buildRoute(c.pts, sz[1], sz[2], circ, z.map)
                local variants = r0 and { r0, r0.second } or {}
                local rFirst
                for vi = 1, math.max(1, #variants) do
                local z = zones[c.area]
                if vi == 2 then
                    local t = {}
                    for k, v in pairs(z) do t[k] = v end
                    t.name = t.name .. " (2)"
                    z = t
                end
                local r = variants[vi]
                local gen = r
                if r then
                    local ov = overrides[string.format("%s:%d-%d:%d", prof, from, to, c.area)]
                    if ov and vi == 1 then r = applyOverride(gen, ov, c.pts, sz[1], sz[2], z.map) end
                end
                local rs = r and (string.format(" share = %.2f, stops = %d, len = %d,%s%s", r.share, r.stops, math.floor(r.len + 0.5), r.manual and " manual = true," or "", vi == 2 and " variant = 2," or "") .. (r.flat and (" route = { " .. table.concat(r.flat, ",") .. " }") or "")) or ""
                out[#out + 1] = string.format('        { area = %d, map = %d, side = "%s", nodes = %d, guide = %s,%s },',
                    c.area, z.map, z.side, c.nodes, tostring(c.guide and true or false), rs)
                if r then
                    nroutes = nroutes + 1
                    do
                        local W, H = sz[1], sz[2]
                        local nd, cov = {}, {}
                        for ni, p in ipairs(c.pts) do
                            nd[ni] = string.format("[%s,%s,%q]", r1(p[1]), r1(p[2]), p[3] or "")
                            local py = { p[1] * W / 100, p[2] * H / 100 }
                            local pl, best = r.polyY, math.huge
                            for k = 1, #pl do best = math.min(best, segDist(py, pl[k], pl[k % #pl + 1])) end
                            if best <= R then cov[#cov + 1] = ni - 1 end
                        end
                        local st = {}
                        for _, p in ipairs(r.stopsY) do st[#st + 1] = r1(p[1] / W * 100); st[#st + 1] = r1(p[2] / H * 100) end
                        reviewRoutes[#reviewRoutes + 1] = { rec = r, gen = gen, W = W, H = H, nd = nd, cov = cov, st = st, prof = prof, from = from, to = to,
                            id = string.format("%s-%d-%d%s", prof, bi, zi, vi == 2 and "b" or ""), et = c.et or 0, ea = c.ea or 0, z = z, guide = c.guide and true or false, nodes = c.nodes }
                    end
                    local check = checkScore(r)
                    local pruneStr = string.format("stops %d->%d tourLen %d->%d cov %d->%d of %d", gen.preStops or 0, gen.stops, math.floor((gen.preLen or 0) + 0.5), math.floor((gen.postLen or 0) + 0.5), gen.preCov or 0, gen.postCov or 0, gen.region or 0)
                    metricRows[#metricRows + 1] = { check = check, text = string.format("%-9s %3d-%-3d %-22s len=%5d share=%.2f stops=%2d cross=%d overlap=%.2f maxhop=%3d check=%.1f  [prune %s] excl=%d/%d", prof, from, to, z.name, math.floor(r.len + 0.5), r.share, r.stops, r.crossings, r.overlap, math.floor(r.maxhop + 0.5), check, pruneStr, c.et or 0, c.ea or 0), crossings = r.crossings }
                    if r.maxhop > globalMax then globalMax = r.maxhop end
                    do
                        local gm = gen.method or "?"
                        methodCount[gm] = (methodCount[gm] or 0) + 1
                        local fl = {}
                        for _, fp in ipairs(FLAGGED[z.map] or {}) do
                            local py = { fp[1] * sz[1] / 100, fp[2] * sz[2] / 100 }
                            local best = math.huge
                            for k = 1, #r.polyY do best = math.min(best, segDist(py, r.polyY[k], r.polyY[k % #r.polyY + 1])) end
                            fl[#fl + 1] = string.format("(%.1f,%.1f)=%dyd", fp[1], fp[2], math.floor(best + 0.5))
                            if best <= 60 then flagRows[#flagRows + 1] = string.format("VIOLATION %s %s %d-%d near (%.1f,%.1f): %d yd%s", prof, z.name, from, to, fp[1], fp[2], math.floor(best + 0.5), r.manual and " [manual]" or "") end
                        end
                        if r.maxslope and r.maxslope >= STEEP and not r.manual then slopeViol[#slopeViol + 1] = string.format("%s %s %d-%d slope=%.2f", prof, z.name, from, to, r.maxslope) end
                        metricRows[#metricRows].text = metricRows[#metricRows].text .. string.format(" method=%s%s slope=%s flagged=%s alt=[%s] usable=[%s] longPieces=%d comps=%d first=%d", gm, r.manual and "(manual)" or "", r.maxslope and string.format("%.2f", r.maxslope) or "n/a", #fl > 0 and table.concat(fl, ";") or "-", gen.alt or "", gen.usable or "", gen.longPieces or 0, gen.compCount or 0, gen.compNodes or 0)
                        totalLong = totalLong + (gen.longPieces or 0)
                        if #fl > 0 then flagRows[#flagRows + 1] = string.format("%s %s %d-%d %s%s", prof, z.name, from, to, table.concat(fl, " "), r.manual and " [manual]" or "") end
                    end
                end
                if vi == 1 then rFirst = r end
                end
                line[#line + 1] = string.format("%s%s[%s] n=%d%s", z.name, c.guide and "*" or "", z.side, c.nodes,
                    rFirst and string.format(" (stops %d, len %d yd, share %.2f, D=%d, maxseg %d yd, cross %d, overlap %.2f)", rFirst.stops, math.floor(rFirst.len + 0.5), rFirst.share, rFirst.D, math.floor(rFirst.maxhop + 0.5), rFirst.crossings or 0, rFirst.overlap or 0) or " (no route)")
            else
                out[#out + 1] = string.format('        { area = %d, map = %d, side = "%s" },', c.area, z.map, z.side)
                line[#line + 1] = z.name .. "[" .. z.side .. "]"
            end
        end
        out[#out + 1] = "    } },"
        report[#report + 1] = table.concat(line, "\n   ")
    end
    out[#out + 1] = "  },"
end
out[#out + 1] = "}"
out[#out + 1] = ""

local text = table.concat(out, "\n")
local f = assert(io.open(ROOT .. "/Data/Routes.lua", "wb"))
f:write(text); f:close()

print(table.concat(report, "\n"))
print(string.format("\nroutes=%d open=%d max stop hop overall=%d yd", nroutes, nopen, math.floor(globalMax + 0.5)))
do
    local parts = {}
    local date = os.date("%Y-%m-%d")
    for _, e in ipairs(reviewRoutes) do
        local r = e.rec
        local check = checkScore(r)
        parts[#parts + 1] = string.format('{"id":"%s","kind":"%s","from":%d,"to":%d,"area":%d,"map":%d,"zone":"%s","side":"%s","guide":%s,"len":%d,"share":%.2f,"stops":%d,"crossings":%d,"overlap":%.2f,"maxhop":%d,"check":%.1f,"D":%d,"R":%d,"yards":[%d,%d],"excluded":[%d,%d],"method":"%s","maxslope":%s,"manual":%s,"note":%q,"route":[%s],"generated":[%s],"stopsXY":[%s],"nodes":[%s],"covered":[%s]}',
            e.id, e.prof, e.from, e.to, e.z.area, e.z.map, e.z.name, e.z.side, tostring(e.guide), math.floor(r.len + 0.5), r.share, r.stops,
            r.crossings, r.overlap, math.floor(r.maxhop + 0.5), check, r.D, R, math.floor(e.W + 0.5), math.floor(e.H + 0.5),
            e.et, e.ea, r.manual and "manual" or (r.method or "tour"), r.maxslope and string.format("%.2f", r.maxslope) or "null", tostring(r.manual and true or false), r.note or "", table.concat(r.flat, ","), table.concat(e.gen.flat, ","), table.concat(e.st, ","), table.concat(e.nd, ","), table.concat(e.cov, ","))
    end
    os.execute('mkdir "' .. (ROOT .. "/tools/review"):gsub("/", "\\") .. '" 2>nul')
    local rf = assert(io.open(ROOT .. "/tools/review/review.json", "wb"))
    local body = '{"generated":"' .. date .. '","routes":[\n' .. table.concat(parts, ",\n") .. "\n]}\n"
    rf:write(body); rf:close()
    print(string.format("Wrote tools/review/review.json (%d bytes)", #body))
end
table.sort(metricRows, function(a, b) if a.check ~= b.check then return a.check > b.check end return a.text < b.text end)
do
    local lines, zero = {}, 0
    for _, r in ipairs(metricRows) do lines[#lines + 1] = r.text; if r.crossings == 0 then zero = zero + 1 end end
    local rf = assert(io.open(ROOT .. "/tools/data/route-report.txt", "wb"))
    rf:write("maxhop = longest segment of the final loop polyline (yd); check = crossings*3 + overlap*10 + (maxhop>300 and 2 or 0) + (share<0.3 and 1 or 0)\n")
    rf:write(table.concat(lines, "\n"), "\n"); rf:close()
    print(string.format("routes with 0 crossings: %d of %d", zero, #metricRows))
    print("top 15 by check score:\n" .. table.concat(lines, "\n", 1, math.min(15, #lines)))
end
do
    local mc = {}
    for k, v in pairs(methodCount) do mc[#mc + 1] = k .. "=" .. v end
    table.sort(mc)
    print("straight pieces > " .. PATH_CAP .. " yd before the cap (tour paths): " .. totalLong)
    print("methods (generated): " .. table.concat(mc, ", "))
    print("slope violations (generated): " .. (#slopeViol > 0 and table.concat(slopeViol, "; ") or "none"))
    print("flagged-point distances:" .. string.char(10) .. "  " .. table.concat(flagRows, string.char(10) .. "  "))
end
print(string.format("\nWrote Data/Routes.lua (%d bytes)", #text))
local um = {}
for n in pairs(unmatched) do um[#um + 1] = n end
table.sort(um)
print("Unmatched guide zone names: " .. (#um > 0 and table.concat(um, ", ") or "none"))
local ig = {}
for n in pairs(ignoredNames) do ig[#ig + 1] = n end
table.sort(ig)
print("Ignored node names: " .. (#ig > 0 and table.concat(ig, ", ") or "none"))
