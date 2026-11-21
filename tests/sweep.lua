-- Plans every crafting profession 1->300 with the real addon and real saved prices (tests/real_sim.lua),
-- each with empty bags, bags that cover part of the materials, and bags that cover all of them, and
-- checks that the totals stay sane. Run from the ProfPath folder:
--   lua tests/sweep.lua <SavedVariables path> [profession filter]
-- Exits 1 when a check fails.
local sv, only = arg[1], arg[2]
assert(sv, "usage: lua tests/sweep.lua <SavedVariables path> [profession]")
local LUA = arg[-1] or "lua"
local PROFS = {
    { "Alchemy", 171 }, { "Blacksmithing", 164 }, { "Cooking", 185 }, { "Enchanting", 333 },
    { "Engineering", 202 }, { "First Aid", 129 }, { "Leatherworking", 165 }, { "Tailoring", 197 },
}
local isWin = package.config:sub(1, 1) == "\\"

local function run(prof, line, bags, gather)
    local env = { "PP_FAKE=" .. line, "PP_REPORT=1", "PP_FULL=1", "PP_GATHER=" .. (gather and "on" or "off"),
        "PP_BAGS=" .. bags }
    local cmd
    if isWin then
        local sets = {}
        for _, e in ipairs(env) do sets[#sets + 1] = 'set "' .. e .. '"' end
        cmd = table.concat(sets, " && ") .. ' && "' .. LUA .. '" tests/real_sim.lua "' .. sv .. '" "' .. prof .. '" 1 2>&1'
    else
        cmd = table.concat(env, " ") .. " '" .. LUA .. "' tests/real_sim.lua '" .. sv .. "' '" .. prof .. "' 1 2>&1"
    end
    local p = io.popen(cmd)
    local out = p:read("a"); p:close()
    local r = { shop = {}, steps = {}, raw = out }
    for l in out:gmatch("[^\n]+") do
        local t, c, le, b, n, last = l:match("^REPORT total=(%-?%d+) cash=(%-?%d+) learn=(%-?%d+) back=(%-?%d+) steps=(%d+) last=(%d+)")
        if t then
            r.total, r.cash, r.learn, r.back = tonumber(t), tonumber(c), tonumber(le), tonumber(b)
            r.nsteps, r.last = tonumber(n), tonumber(last)
        end
        local id, need, own, buy, src, cost, unit = l:match("^SHOP (%d+) needed=(%d+) owned=(%d+) buy=(%d+) src=(%S+) cost=(%d+) unit=([%d%.]+)")
        if id then
            r.shop[#r.shop + 1] = { id = tonumber(id), needed = tonumber(need), owned = tonumber(own), buy = tonumber(buy),
                src = src, cost = tonumber(cost), unit = tonumber(unit) }
        end
        if l:match("^STEP ") then r.steps[#r.steps + 1] = l end
        if l:match("^lua") or l:match("stack traceback") then r.err = true end
    end
    return r
end

local function g(c) return ("%.2fg"):format((c or 0) / 10000) end
local fails, results = 0, {}
local function check(ok, prof, what)
    if not ok then fails = fails + 1; print(("  FAIL %s: %s"):format(prof, what)) end
end

for _, p in ipairs(PROFS) do
    local prof, line = p[1], p[2]
    if not only or prof:lower():find(only:lower(), 1, true) then
        local empty = run(prof, line, "", false)
        print(("%s empty: total %s (cash %s + learn %s - back %s), %d steps to %s"):format(prof, g(empty.total),
            g(empty.cash), g(empty.learn), g(empty.back), empty.nsteps or 0, tostring(empty.last)))
        check(not empty.err, prof, "Lua error:\n" .. empty.raw:sub(1, 600))
        check(empty.total ~= nil, prof, "no plan with empty bags")
        if empty.total then
            check((empty.last or 0) >= 300, prof, "plan stops at " .. tostring(empty.last) .. ", not 300")
            check(empty.cash + empty.learn > 0, prof, "spends nothing")
            -- Bags: the three biggest bought materials. Partly = half of each, full = all of each.
            table.sort(empty.shop, function(a, b) return a.cost > b.cost end)
            local partly, full, value, valueP = {}, {}, 0, 0
            for i = 1, math.min(3, #empty.shop) do
                local s = empty.shop[i]
                if s.buy > 0 and s.src ~= "vendor" then
                    local half = math.max(1, s.needed // 2)
                    partly[#partly + 1] = s.id .. "=" .. half
                    full[#full + 1] = s.id .. "=" .. s.needed
                    value, valueP = value + s.cost, valueP + s.cost * half / s.needed
                end
            end
            local prevNet
            for _, case in ipairs({ { "partly", table.concat(partly, ","), valueP }, { "full", table.concat(full, ","), value } }) do
                local name, bags, worth = case[1], case[2], case[3]
                local r = run(prof, line, bags, false)
                check(not r.err and r.total, prof, name .. " bags: no plan / Lua error\n" .. r.raw:sub(1, 600))
                if r.total then
                    -- net gold: spent (materials + recipes) minus what vendoring the crafts returns. The
                    -- plan minimises this, so owned stock may buy a route that costs more up front but
                    -- sells back for more.
                    local net, netE = r.cash + r.learn - r.back, empty.cash + empty.learn - empty.back
                    print(("  %s bags (%s, worth %s): net %s vs %s empty (spend %s vs %s)"):format(name, bags, g(worth),
                        g(net), g(netE), g(r.cash + r.learn), g(empty.cash + empty.learn)))
                    -- Owning materials must never make the plan cost more gold net...
                    check(net <= netE + 50, prof, ("%s bags: net %s > empty %s"):format(name, g(net), g(netE)))
                    -- ...and can save at most what the bags are worth (plus 10% for a cheaper route).
                    check(netE - net <= worth * 1.1 + 100, prof, ("%s bags save %s, more than they are worth (%s)"):format(
                        name, g(netE - net), g(worth)))
                    -- More of the same stock never makes the plan dearer.
                    check(not prevNet or net <= prevNet + 50, prof, ("%s bags: net %s > partly bags %s"):format(
                        name, g(net), g(prevNet or 0)))
                    prevNet = net
                    check((r.last or 0) >= 300, prof, name .. " bags: plan stops at " .. tostring(r.last))
                    -- Owned counts never exceed what the bags hold.
                    for _, s in ipairs(r.shop) do
                        local held = tonumber(bags:match("%f[%d]" .. s.id .. "=(%d+)")) or 0
                        check(s.owned <= held, prof, ("%s bags: item %d owned %d > held %d"):format(name, s.id, s.owned, held))
                    end
                end
            end
            -- Gathering on: still a plan, and gathered items cost no gold.
            local gr = run(prof, line, "", true)
            check(not gr.err and gr.total, prof, "gather on: no plan / Lua error")
            if gr.total then
                for _, s in ipairs(gr.shop) do
                    check(s.src ~= "gather" or s.cost == 0, prof, ("gathered item %d costs %s"):format(s.id, g(s.cost)))
                end
            end
        end
    end
end
print(fails == 0 and "sweep: all checks passed" or ("sweep: %d check(s) failed"):format(fails))
os.exit(fails == 0 and 0 or 1)
