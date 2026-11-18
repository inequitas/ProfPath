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
            for _, p in ipairs(pts) do bucket[area][#bucket[area] + 1] = { p[1], p[2] } end
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

    -- tour over stops: nearest neighbour, 2-opt, or-opt (long hops cost 10x)
    local DS = D + STOP_HOP_EXTRA -- stops sit up to R away from the nodes they cover, so allow that slack on stop-to-stop hops
    local function cost(a, b)
        local d = dist(S[a], S[b])
        return d > DS and d * 10 or d
    end
    local start = 1
    for i = 2, ns_ do if S[i][1] < S[start][1] then start = i end end
    local tour, used = { start }, { [start] = true }
    for _ = 2, ns_ do
        local cur, bj, bd = tour[#tour], nil, math.huge
        for j = 1, ns_ do
            if not used[j] then
                local d = cost(cur, j)
                if d < bd then bd, bj = d, j end
            end
        end
        tour[#tour + 1] = bj; used[bj] = true
    end
    local function tourCost(t)
        local c = 0
        for i = 1, #t do c = c + cost(t[i], t[i % #t + 1]) end
        return c
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
                        if cost(a, c) + cost(b, d) - cost(a, b) - cost(c, d) < -1e-9 then
                            local lo, hi = i + 1, j
                            while lo < hi do tour[lo], tour[hi] = tour[hi], tour[lo]; lo = lo + 1; hi = hi - 1 end
                            improved = true
                        end
                    end
                end
            end
            -- or-opt: move a segment of 1..3 stops elsewhere
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

    -- cut at long hops; keep the stretch covering the most nodes
    local longs = {}
    for i = 1, ns_ do
        if dist(S[tour[i]], S[tour[i % ns_ + 1]]) > DS then longs[#longs + 1] = i end
    end
    if os.getenv("RDEBUG") then io.stderr:write(string.format("m=%d stops=%d longs=%d D=%d\n", m, ns_, #longs, D)) end
    local seq, open = {}, false
    if #longs == 0 then
        for i = 1, ns_ do seq[i] = S[tour[i]] end
    else
        open = true
        local bestStretch, bestK = nil, -1
        for li = 1, #longs do
            local from = longs[li] % ns_ + 1 -- first stop after this long hop
            local to = longs[li % #longs + 1] -- last stop before the next long hop
            local stretch = {}
            local idx = from
            while true do
                stretch[#stretch + 1] = S[tour[idx]]
                if idx == to then break end
                idx = idx % ns_ + 1
            end
            local k = coveredBy(stretch)
            if k > bestK then bestK, bestStretch = k, stretch end
        end
        seq = bestStretch
    end
    local kcov, covList = coveredBy(seq)
    local maxhop = 0
    for i = 1, #seq - (open and 1 or 0) do
        local d = dist(seq[i], seq[i % #seq + 1])
        if #seq > 1 and d > maxhop then maxhop = d end
    end
    if #seq < 2 then
        return { stops = #seq, share = kcov / n, D = D, maxhop = 0, len = 0, open = open }
    end
    if #seq == 2 then open = true end
    local nstops = #seq
    -- make it a loop: Dijkstra return leg over the node graph, penalising nodes near the outward path
    local back, retMax, retFail
    if open and #seq >= 2 then
        local V = {}
        for i = 1, n do if comp[i] == best then V[#V + 1] = Q[i] end end
        local nv = #V
        local sIdx, tIdx = nv + 1, nv + 2 -- temporary vertices: first stop (target) / last stop (source)
        V[sIdx] = seq[1]; V[tIdx] = seq[#seq]
        local function nearOut(p)
            local b = math.huge
            for i = 1, #seq - 1 do b = math.min(b, segDist(p, seq[i], seq[i + 1])) end
            return b
        end
        local pen = {}
        for i = 1, nv do pen[i] = nearOut(V[i]) <= R / 2 end
        local function w(a, b)
            local d = dist(V[a], V[b])
            if d > D then return nil end
            return (pen[a] or pen[b]) and d * 4 or d
        end
        local src, dst = tIdx, sIdx
        local dd, prev, done = {}, {}, {}
        for i = 1, nv + 2 do dd[i] = math.huge end
        dd[src] = 0
        while true do
            local u, ud = nil, math.huge
            for i = 1, nv + 2 do if not done[i] and dd[i] < ud then u, ud = i, dd[i] end end
            if not u or u == dst then break end
            done[u] = true
            for v = 1, nv + 2 do
                if not done[v] and v ~= u and not ((u > nv) and (v > nv)) then
                    local c = w(u, v)
                    if c and ud + c < dd[v] then dd[v] = ud + c; prev[v] = u end
                end
            end
        end
        if dd[dst] < math.huge then
            local leg = {}
            local v = prev[dst]
            while v and v ~= src do table.insert(leg, 1, V[v]); v = prev[v] end
            -- leg runs from the last stop to the first stop (exclusive of both)
            local walk = { seq[#seq] }
            for _, p in ipairs(leg) do walk[#walk + 1] = p end
            walk[#walk + 1] = seq[1]
            retMax = 0
            for i = 1, #walk - 1 do retMax = math.max(retMax, dist(walk[i], walk[i + 1])) end
            local tot, near = 0, 0
            for i = 1, #walk - 1 do
                local a, b = walk[i], walk[i + 1]
                local L = dist(a, b)
                local k = math.max(1, math.ceil(L / 20))
                for s = 0, k - 1 do
                    local t = (s + 0.5) / k
                    local p = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
                    tot = tot + 1
                    if nearOut(p) <= R / 2 then near = near + 1 end
                end
            end
            back = tot > 0 and near / tot or 0
            local newseq = {}
            for _, p in ipairs(seq) do newseq[#newseq + 1] = p end
            for _, p in ipairs(leg) do newseq[#newseq + 1] = p end
            seq = newseq
            open = false
            maxhop = math.max(maxhop, retMax)
        else
            retFail = true
        end
    end

    -- smooth (2 Chaikin passes, else 1, else 0), simplify, verify coverage within R + SIMPLIFY
    local final
    for iters = 2, 0, -1 do
        local line = seq
        for _ = 1, iters do line = chaikin(line, not open) end
        line = simplify(line, not open, SIMPLIFY)
        if covers(line, not open, covList, R + SIMPLIFY) then final = line; smoothed = iters; break end
    end
    local flat = {}
    for _, p in ipairs(final) do
        flat[#flat + 1] = string.format("%.1f", p[1] / W * 100)
        flat[#flat + 1] = string.format("%.1f", p[2] / H * 100)
    end
    return { flat = flat, D = D, stops = nstops, share = kcov / n, open = open, maxhop = maxhop, back = back, retMax = retMax, retFail = retFail,
        len = polyLen(final, not open), pts = #final }
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
local nret, retList, failList, retMaxAll = 0, {}, {}, 0
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
    for _, band in ipairs(BANDS[prof]) do
        local from, to = band[1], band[2]
        local list = pickZones(prof, band)
        out[#out + 1] = string.format("    { from = %d, to = %d, zones = {", from, to)
        local line = { string.format("%s %d-%d:", prof, from, to) }
        for _, c in ipairs(list) do
            local z = zones[c.area]
            if SKILL[prof] then
                local sz = assert(size[z.map], 'no yard size for uiMap ' .. z.map)
                local r = buildRoute(c.pts, sz[1], sz[2])
                local rs = r and (string.format(" share = %.2f, stops = %d, len = %d,%s%s", r.share, r.stops, math.floor(r.len + 0.5), r.back and string.format(" back = %.2f,", r.back) or "", r.open and " open = true," or "") .. (r.flat and (" route = { " .. table.concat(r.flat, ",") .. " }") or "")) or ""
                out[#out + 1] = string.format('        { area = %d, map = %d, side = "%s", nodes = %d, guide = %s,%s },',
                    c.area, z.map, z.side, c.nodes, tostring(c.guide and true or false), rs)
                if r then
                    nroutes = nroutes + 1
                    if r.open then nopen = nopen + 1 end
                    if r.back then nret = nret + 1; retList[#retList + 1] = string.format("%s %s %d-%d back=%.2f maxhop=%d", prof, z.name, from, to, r.back, math.floor(r.retMax + 0.5)); if r.retMax > retMaxAll then retMaxAll = r.retMax end end
                    if r.retFail then failList[#failList + 1] = string.format("%s %s %d-%d", prof, z.name, from, to) end
                    if r.maxhop > globalMax then globalMax = r.maxhop end
                end
                line[#line + 1] = string.format("%s%s[%s] n=%d%s", z.name, c.guide and "*" or "", z.side, c.nodes,
                    r and string.format(" (stops %d, len %d yd, share %.2f, D=%d, maxhop %d yd%s%s)", r.stops, math.floor(r.len + 0.5), r.share, r.D, math.floor(r.maxhop + 0.5), r.open and ", OPEN" or "", r.flat and "" or ", NO LINE") or " (no route)")
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
print(string.format("return legs=%d, max return hop=%d yd", nret, math.floor(retMaxAll + 0.5)))
print("back>0.5: " .. table.concat((function() local t = {} for _, l in ipairs(retList) do if tonumber(l:match("back=([%d.]+)")) > 0.5 then t[#t + 1] = l end end return t end)(), "; "))
print("return failed (kept open): " .. table.concat(failList, "; "))
if os.getenv("RDEBUG") then print(table.concat(retList, "\n")) end
print(string.format("\nWrote Data/Routes.lua (%d bytes)", #text))
local um = {}
for n in pairs(unmatched) do um[#um + 1] = n end
table.sort(um)
print("Unmatched guide zone names: " .. (#um > 0 and table.concat(um, ", ") or "none"))
local ig = {}
for n in pairs(ignoredNames) do ig[#ig + 1] = n end
table.sort(ig)
print("Ignored node names: " .. (#ig > 0 and table.concat(ig, ", ") or "none"))
