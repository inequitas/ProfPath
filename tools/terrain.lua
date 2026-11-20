-- WDL terrain helper. Usage: local terrain = dofile("tools/terrain.lua")
-- Reads tools/data/terrain/<MapID>.wdl (coarse 17x17 height grid per ADT tile, 33.33 yd spacing).
local terrain = {}
local T = 533.33333
local here = (debug.getinfo(1, "S").source:match("^@(.*[/%\\])") or "./")
terrain.dataDir = here .. "data/terrain/"
terrain.csv = here .. "data/UiMapAssignment.csv"
-- Grid index convention: idx = row*17 + col (row = tile-y direction / north->south, col = tile-x / west->east).
terrain.transpose = false

local cache, asg = {}, nil

local function loadWdl(mapID)
    local f = io.open(terrain.dataDir .. mapID .. ".wdl", "rb")
    if not f then return nil end
    local d = f:read("a"); f:close()
    local pos, maof, tiles = 1, nil, {}
    while pos + 7 <= #d do
        local id = d:sub(pos, pos + 3):reverse()
        local size = string.unpack("<I4", d, pos + 4)
        if id == "MAOF" then maof = pos + 8 end
        pos = pos + 8 + size
    end
    if not maof then return nil end
    local obj = { tiles = tiles }
    for ty = 0, 63 do
        for tx = 0, 63 do
            local off = string.unpack("<I4", d, maof + (ty * 64 + tx) * 4)
            if off ~= 0 and d:sub(off + 1, off + 4):reverse() == "MARE" then
                local h = { string.unpack("<" .. string.rep("i2", 17 * 17), d, off + 9) }
                h[#h] = nil
                tiles[ty * 64 + tx] = h
            end
        end
    end
    local function cell(tx, ty, col, row)
        local h = tiles[ty * 64 + tx]
        if not h then return nil end
        if terrain.transpose then col, row = row, col end
        return h[row * 17 + col + 1]
    end
    function obj:height(wx, wy)
        local fx, fy = 32 - wy / T, 32 - wx / T
        local tx, ty = math.floor(fx), math.floor(fy)
        if tx < 0 or tx > 63 or ty < 0 or ty > 63 then return nil end
        local gx, gy = (fx - tx) * 16, (fy - ty) * 16
        local c, r = math.floor(gx), math.floor(gy)
        if c > 15 then c = 15 end
        if r > 15 then r = 15 end
        local u, v = gx - c, gy - r
        local a, b, c2, d2 = cell(tx, ty, c, r), cell(tx, ty, c + 1, r), cell(tx, ty, c, r + 1), cell(tx, ty, c + 1, r + 1)
        if not (a and b and c2 and d2) then return nil end
        return (a * (1 - u) + b * u) * (1 - v) + (c2 * (1 - u) + d2 * u) * v
    end
    return obj
end

function terrain.load(mapID)
    if cache[mapID] == nil then cache[mapID] = loadWdl(mapID) or false end
    return cache[mapID] or nil
end

local function assignment(uiMapID)
    if not asg then
        asg = {}
        local first = true
        for l in io.lines(terrain.csv) do
            if first then first = false else
                local c = {}
                for v in l:gmatch("([^,]*)") do c[#c + 1] = v end
                -- header: UiMin_0..UiMax_1 (1-4), Region_0..5 (5-10), ID, UiMapID(12), Order, MapID(14)
                local u = tonumber(c[12])
                if u and c[1] == "0" and c[2] == "0" and c[3] == "1" and c[4] == "1" and not asg[u] then
                    asg[u] = { map = tonumber(c[14]), x0 = tonumber(c[5]), y0 = tonumber(c[6]), x1 = tonumber(c[8]), y1 = tonumber(c[9]) }
                end
            end
        end
    end
    return asg[uiMapID]
end
terrain.assignment = assignment

-- zone(uiMapID) -> function(mx, my) -> height (mx,my percent 0-100)
function terrain.zone(uiMapID)
    local a = assignment(uiMapID)
    if not a then return nil end
    local obj = terrain.load(a.map)
    if not obj then return nil end
    return function(mx, my)
        return obj:height(a.x1 - my / 100 * (a.x1 - a.x0), a.y1 - mx / 100 * (a.y1 - a.y0))
    end
end

function terrain.size(uiMapID)
    local a = assignment(uiMapID)
    return a.y1 - a.y0, a.x1 - a.x0 -- yardsW, yardsH
end

-- max |rise/run| between samples every 15 yd along a straight segment (map percent).
function terrain.slopeAlong(uiMapID, x1, y1, x2, y2, yardsW, yardsH)
    local f = terrain.zone(uiMapID)
    if not f then return nil end
    local dx, dy = (x2 - x1) / 100 * yardsW, (y2 - y1) / 100 * yardsH
    local len = math.sqrt(dx * dx + dy * dy)
    local n = math.max(1, math.ceil(len / 15))
    local best, prof, prev = 0, {}, nil
    for i = 0, n do
        local t = i / n
        local h = f(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
        if h and prev then
            local s = math.abs(h - prev) / (len / n)
            prof[#prof + 1] = s
            if s > best then best = s end
        end
        prev = h
    end
    return best, prof
end

-- max slope to the 8 neighbours at `dist` yards around (mx,my)
function terrain.localSlope(uiMapID, mx, my, dist, yardsW, yardsH)
    local f = terrain.zone(uiMapID)
    local h0 = f(mx, my)
    if not h0 then return nil end
    local best = 0
    for dxs = -1, 1 do for dys = -1, 1 do
        if dxs ~= 0 or dys ~= 0 then
            local k = (dxs ~= 0 and dys ~= 0) and 0.70711 or 1
            local h = f(mx + dxs * k * dist / yardsW * 100, my + dys * k * dist / yardsH * 100)
            if h then best = math.max(best, math.abs(h - h0) / dist) end
        end
    end end
    return best, h0
end

-- grid[j][i] = local max slope for cells of stepPct (i,j from 0), sampled at cell centre
function terrain.steepGrid(uiMapID, stepPct, dist)
    local w, h = terrain.size(uiMapID)
    local g = {}
    local n = math.floor(100 / stepPct + 0.5)
    for j = 0, n - 1 do
        g[j] = {}
        for i = 0, n - 1 do
            g[j][i] = terrain.localSlope(uiMapID, (i + 0.5) * stepPct, (j + 0.5) * stepPct, dist or 30, w, h)
        end
    end
    return g
end

return terrain
