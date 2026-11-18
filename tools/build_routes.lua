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
local MAXNODES = 150
local DEDUPE = 0.4 -- map units
local R = 120                      -- yards: the route must pass within R of every covered node
local HOP_YARDS = { 250, 300, 350 } -- max hop between linked nodes/stops, tried in order
local SIMPLIFY = 15                -- yards: Douglas-Peucker tolerance (also the extra slack for coverage checks)
local STOP_HOP_EXTRA = 120         -- yards added to the hop limit between stops (stops are offset from nodes by up to R)
local UIMAPASSIGNMENT = os.getenv("PROFPATH_UIMAPASSIGNMENT")
    or "tools/data/UiMapAssignment.csv"

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
        if mi and md > tol then keep[mi] = true; rec(i, mi); rec(mi, j) end
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
local function untangle(poly0, limit)
    local poly = {}
    for i, p in ipairs(poly0) do poly[i] = p end
    local n = #poly
    if n < 4 then return poly end
    local cur = 0
    for i = 1, n do cur = cur + dist(poly[i], poly[i % n + 1]) end
    local maxLen = cur * 1.02
    for _ = 1, 1000 do
        local moved = false
        for i = 1, n - 2 do
            for j = i + 2, n do
                if not (i == 1 and j == n) then
                    local a, b, c, d = poly[i], poly[i + 1], poly[j], poly[j % n + 1]
                    if segCross(a, b, c, d) then
                        local n1, n2 = dist(a, c), dist(b, d)
                        local delta = n1 + n2 - dist(a, b) - dist(c, d)
                        if n1 <= limit and n2 <= limit and cur + delta <= maxLen then
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
local function buildRoute(pts, W, H)
    local n = #pts
    if n == 0 then return nil end
    local Q = {}
    for i, p in ipairs(pts) do Q[i] = { p[1] * W / 100, p[2] * H / 100 } end
    local D, comp, best, size, adj
    for _, d in ipairs(HOP_YARDS) do
        D = d
        comp, best, size, adj = components(Q, D)
        if size >= 0.6 * n then break end
    end
    local sel = {}
    for i = 1, n do if comp[i] == best then sel[#sel + 1] = i end end
    if #sel > MAXNODES then
        local seed = sel[1]
        for _, i in ipairs(sel) do if #adj[i] > #adj[seed] then seed = i end end
        local inRegion, region, bestD = { [seed] = true }, { seed }, {}
        local function relax(v)
            for _, w in ipairs(adj[v]) do
                if not inRegion[w] then
                    local d = dist(Q[v], Q[w])
                    if not bestD[w] or d < bestD[w] then bestD[w] = d end
                end
            end
        end
        relax(seed)
        while #region < MAXNODES do
            local pick, pd
            for w, d in pairs(bestD) do
                if not inRegion[w] and (not pd or d < pd or (d == pd and w < pick)) then pick, pd = w, d end
            end
            if not pick then break end
            inRegion[pick] = true; region[#region + 1] = pick; bestD[pick] = nil
            relax(pick)
        end
        sel = region
    end
    local m = #sel
    local N = {}
    for i, idx in ipairs(sel) do N[i] = Q[idx] end

    -- greedy set cover: candidates are node positions and midpoints of node pairs within 2R
    local cands = {}
    for i = 1, m do cands[#cands + 1] = N[i] end
    for i = 1, m do
        for j = i + 1, m do
            if dist(N[i], N[j]) <= 2 * R then
                cands[#cands + 1] = { (N[i][1] + N[j][1]) / 2, (N[i][2] + N[j][2]) / 2 }
            end
        end
    end
    local cover = {}
    for c, cp in ipairs(cands) do
        local s = {}
        for i = 1, m do if dist(cp, N[i]) <= R then s[#s + 1] = i end end
        cover[c] = s
    end
    local covered, ncov, S = {}, 0, {}
    while ncov < m do
        local bc, bn = nil, 0
        for c = 1, #cands do
            local k = 0
            for _, i in ipairs(cover[c]) do if not covered[i] then k = k + 1 end end
            if k > bn then bc, bn = c, k end
        end
        S[#S + 1] = cands[bc]
        for _, i in ipairs(cover[bc]) do if not covered[i] then covered[i] = true; ncov = ncov + 1 end end
    end
    local ns_ = #S
    local function coveredBy(stops)
        local k, list = 0, {}
        for i = 1, m do
            for _, s in ipairs(stops) do
                if dist(N[i], s) <= R then k = k + 1; list[#list + 1] = N[i]; break end
            end
        end
        return k, list
    end
    if ns_ < 2 then
        return { stops = ns_, share = m / n, D = D, maxhop = 0, len = 0, open = false }
    end

    -- walkable graph over the routed component (nodes within D), stops attached to nodes/stops within D
    local V = {}
    for i = 1, n do if comp[i] == best then V[#V + 1] = Q[i] end end
    local nv = #V
    for k = 1, ns_ do V[nv + k] = S[k] end
    local nV = #V
    local gadj = {}
    for i = 1, nV do gadj[i] = {} end
    for i = 1, nV do
        for j = i + 1, nV do
            local d = dist(V[i], V[j])
            if d <= D then
                gadj[i][#gadj[i] + 1] = { j, d }; gadj[j][#gadj[j] + 1] = { i, d }
            end
        end
    end
    local function dijkstra(src)
        local dd, prev, done = {}, {}, {}
        for i = 1, nV do dd[i] = math.huge end
        dd[src] = 0
        while true do
            local u, ud = nil, math.huge
            for i = 1, nV do if not done[i] and dd[i] < ud then u, ud = i, dd[i] end end
            if not u then break end
            done[u] = true
            for _, e in ipairs(gadj[u]) do
                local v = e[1]
                if not done[v] and ud + e[2] < dd[v] then dd[v] = ud + e[2]; prev[v] = u end
            end
        end
        return dd, prev
    end
    local DD, PREV = {}, {}
    for k = 1, ns_ do DD[k], PREV[k] = dijkstra(nv + k) end
    local function G(a, b) return DD[a][nv + b] end

    -- closed tour over the stops with graph distances: NN + 2-opt + or-opt, best of several starts
    local function tourCost(t)
        local c = 0
        for i = 1, #t do c = c + G(t[i], t[i % #t + 1]) end
        return c
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

    -- expand every hop into its graph path
    local raw = { S[tour[1]] }
    for i = 1, ns_ do
        local a, b = tour[i], tour[i % ns_ + 1]
        local path, v = {}, nv + b
        while v and v ~= nv + a do table.insert(path, 1, V[v]); v = PREV[a][v] end
        for _, p in ipairs(path) do
            local last = raw[#raw]
            if p[1] ~= last[1] or p[2] ~= last[2] then raw[#raw + 1] = p end
        end
    end
    if #raw > 1 and raw[#raw][1] == raw[1][1] and raw[#raw][2] == raw[1][2] then raw[#raw] = nil end

    local line = untangle(raw, D)
    local maxseg = 0
    local final
    for iters = 2, 0, -1 do
        local l = line
        for _ = 1, iters do l = chaikin(l, true) end
        l = simplify(l, true, SIMPLIFY)
        if covers(l, true, N, R + SIMPLIFY) then final = l; break end
    end
    do
        local ms = 0
        for i = 1, #final do ms = math.max(ms, dist(final[i], final[i % #final + 1])) end
        local again = untangle(final, math.max(D, ms))
        if covers(again, true, N, R + SIMPLIFY) then final = again end
    end
    local met = metrics(final)
    local flat = {}
    for _, p in ipairs(final) do
        flat[#flat + 1] = string.format("%.1f", p[1] / W * 100)
        flat[#flat + 1] = string.format("%.1f", p[2] / H * 100)
    end
    return { flat = flat, D = D, stops = ns_, share = m / n, open = false, maxhop = met.maxseg,
        len = met.len, pts = #final, crossings = met.crossings, overlap = met.overlap, stopsY = S, polyY = final }
end

---------------------------------------------------------------- Build
local function usefulPoints(prof, area, s)
    local pts = {}
    for name, req in pairs(SKILL[prof]) do
        if req <= s + 10 and req + 100 > s then
            local list = nodes[prof][name] and nodes[prof][name][area]
            if list then for _, p in ipairs(list) do pts[#pts + 1] = p end end
        end
    end
    table.sort(pts, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    return dedupe(pts)
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
            c.pts = usefulPoints(prof, area, from); c.nodes = #c.pts
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
                local pts = usefulPoints(prof, area, from)
                if #pts > 0 then others[#others + 1] = { area = area, pts = pts, nodes = #pts } end
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
                local r = buildRoute(c.pts, sz[1], sz[2])
                local rs = r and (string.format(" share = %.2f, stops = %d, len = %d,", r.share, r.stops, math.floor(r.len + 0.5)) .. (r.flat and (" route = { " .. table.concat(r.flat, ",") .. " }") or "")) or ""
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
                        reviewRoutes[#reviewRoutes + 1] = { rec = r, W = W, H = H, nd = nd, cov = cov, st = st, prof = prof, from = from, to = to,
                            id = string.format("%s-%d-%d", prof, bi, zi), z = z, guide = c.guide and true or false, nodes = c.nodes }
                    end
                    local check = r.crossings * 3 + r.overlap * 10 + (r.maxhop > 300 and 2 or 0) + (r.share < 0.3 and 1 or 0)
                    metricRows[#metricRows + 1] = { check = check, text = string.format("%-9s %3d-%-3d %-22s len=%5d share=%.2f stops=%2d cross=%d overlap=%.2f maxhop=%3d check=%.1f", prof, from, to, z.name, math.floor(r.len + 0.5), r.share, r.stops, r.crossings, r.overlap, math.floor(r.maxhop + 0.5), check), crossings = r.crossings }
                    if r.maxhop > globalMax then globalMax = r.maxhop end
                end
                line[#line + 1] = string.format("%s%s[%s] n=%d%s", z.name, c.guide and "*" or "", z.side, c.nodes,
                    r and string.format(" (stops %d, len %d yd, share %.2f, D=%d, maxseg %d yd, cross %d, overlap %.2f)", r.stops, math.floor(r.len + 0.5), r.share, r.D, math.floor(r.maxhop + 0.5), r.crossings or 0, r.overlap or 0) or " (no route)")
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
        local check = r.crossings * 3 + r.overlap * 10 + (r.maxhop > 300 and 2 or 0) + (r.share < 0.3 and 1 or 0)
        parts[#parts + 1] = string.format('{"id":"%s","kind":"%s","from":%d,"to":%d,"area":%d,"map":%d,"zone":"%s","side":"%s","guide":%s,"len":%d,"share":%.2f,"stops":%d,"crossings":%d,"overlap":%.2f,"maxhop":%d,"check":%.1f,"D":%d,"R":%d,"yards":[%d,%d],"route":[%s],"stopsXY":[%s],"nodes":[%s],"covered":[%s]}',
            e.id, e.prof, e.from, e.to, e.z.area, e.z.map, e.z.name, e.z.side, tostring(e.guide), math.floor(r.len + 0.5), r.share, r.stops,
            r.crossings, r.overlap, math.floor(r.maxhop + 0.5), check, r.D, R, math.floor(e.W + 0.5), math.floor(e.H + 0.5),
            table.concat(r.flat, ","), table.concat(e.st, ","), table.concat(e.nd, ","), table.concat(e.cov, ","))
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
print(string.format("\nWrote Data/Routes.lua (%d bytes)", #text))
local um = {}
for n in pairs(unmatched) do um[#um + 1] = n end
table.sort(um)
print("Unmatched guide zone names: " .. (#um > 0 and table.concat(um, ", ") or "none"))
local ig = {}
for n in pairs(ignoredNames) do ig[#ig + 1] = n end
table.sort(ig)
print("Ignored node names: " .. (#ig > 0 and table.concat(ig, ", ") or "none"))
