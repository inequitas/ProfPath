-- Costs a fixed leveling guide with the same data, prices and model ProfPath uses, next to
-- ProfPath's own plan over the same range.
-- Usage: lua tests/compare_guide.lua <SavedVariables path>
REPRO_LIB = true
arg = { arg[1], "Leatherworking", "150", "0" }
local START, TARGET = 75, 150
os.getenv = (function(real) return function(k) if k == "PP_START" then return tostring(START) end return real(k) end end)(os.getenv)
local E = dofile("tests/repro_real.lua")
local O, money = E.O, E.money

-- Wowhead WoW Forever LW guide (updated 2026-11-04), steps covering 75-150.
local GUIDE = {
    { 75, 85, "Embossed Leather Gloves" },
    { 85, 100, "Fine Leather Belt" },
    { 100, 115, "Dark Leather Pants" },
    { 115, 118, "Gray Leather Boots" },
    { 118, 125, "Dark Leather Belt" },
    { 125, 135, "Cured Heavy Hide" },
    { 135, 143, "Dark Leather Belt" },
    { 143, 145, "Cured Heavy Hide" },
    { 145, 150, "Toughened Leather Gloves" },
}

local byName = {}
for _, r in ipairs(E.recipes) do byName[r.name] = byName[r.name] or r end

-- Producers (learned) so intermediates can be crafted, as in the optimizer.
local producers = {}
for _, r in ipairs(E.recipes) do if r.learned then producers[#producers + 1] = r end end

local function run(recipes, from, to)
    return O.optimize({ skill = from, target = to, recipes = recipes, price = E.ahTotal, vendorBuy = E.vendorBuy,
        vendorSell = E.vendorSell, owned = {}, resaleFactor = 0, ownedFree = true })
end

print(("Guide path %d-%d, costed with your prices (each step forced to the guide's recipe):"):format(START, TARGET))
local gCash, gLearn, gBack, gCrafts = 0, 0, 0, 0
local learnedOnce = {}
for _, g in ipairs(GUIDE) do
    local r = byName[g[3]]
    if not r then
        print(("  %d-%d %-26s NOT IN DATA"):format(g[1], g[2], g[3]))
    else
        -- learn cost charged once per recipe; force this recipe alone (plus producers for intermediates)
        local saveL, saveC = r.learned, r.learnCost
        if learnedOnce[r] then r.learned = true end
        local list = { r }
        for _, p in ipairs(producers) do if p ~= r then list[#list + 1] = p end end
        -- producers must not be used as leveling steps: make them unable to give points here
        local saved = {}
        for i = 2, #list do saved[list[i]] = list[i].gray; list[i].gray = math.min(list[i].gray, g[1]) end
        local res = run(list, g[1], g[2])
        for p, gr in pairs(saved) do p.gray = gr end
        r.learned, r.learnCost = saveL, saveC
        learnedOnce[r] = true
        if not res.ok then
            print(("  %d-%d %-26s no path (yellow %d gray %d, min %d, learn %s) stuck at %s"):format(g[1], g[2], g[3],
                r.yellow, r.gray, r.minSkill, r.learnCost and money(r.learnCost) or "?", tostring(res.stuckAt)))
        else
            local st = res.steps[1]
            local crafts = 0
            for _, s in ipairs(res.steps) do crafts = crafts + s.expectedCrafts end
            gCash, gLearn, gBack, gCrafts = gCash + res.cash, gLearn + res.learnTotal, gBack + res.sellBack, gCrafts + crafts
            print(("  %d-%d %-26s x%3.0f  spend %-13s back %-13s (yellow %d gray %d)"):format(g[1], g[2], g[3], crafts,
                money(res.cash + res.learnTotal), money(res.sellBack), r.yellow, r.gray))
        end
    end
end
print(("  GUIDE TOTAL: %0.f crafts, spend %s, back %s, net %s"):format(gCrafts, money(gCash + gLearn), money(gBack),
    money(gCash + gLearn - gBack)))

print()
print(("ProfPath plan %d-%d with the same prices:"):format(START, TARGET))
local res = run(E.recipes, START, TARGET)
if not res.ok then print("  no path, stuck at " .. tostring(res.stuckAt)) return end
local crafts = 0
for _, s in ipairs(res.steps) do
    crafts = crafts + s.expectedCrafts
    print(("  %d-%d %-26s x%3.0f  learn %s (yellow %d gray %d)"):format(s.fromSkill, s.toSkill, s.recipe.name,
        s.expectedCrafts, money(s.learnCost), s.recipe.yellow, s.recipe.gray))
end
for _, it in ipairs(res.intermediates) do print(("  craft first: %s x%d"):format(it.recipe.name, it.crafts)) end
print(("  PROFPATH TOTAL: %.0f crafts, spend %s, back %s, net %s"):format(crafts, money(res.cash + res.learnTotal),
    money(res.sellBack), money(res.cash + res.learnTotal - res.sellBack)))
