-- Rebuilds a profession plan offline from the real data file and the player's SavedVariables.
-- Usage (from the ProfPath folder):  lua tests/repro_real.lua <SavedVariables path> [profession] [target] [resale]
local svPath, profName, target, resale = arg[1], arg[2] or "Leatherworking", tonumber(arg[3]), tonumber(arg[4])
local ns = {}
assert(loadfile("Data/Recipes.lua"))(nil, ns)
local O = assert(loadfile("Optimizer.lua"))(nil, ns)
dofile(svPath)
local DB = ProfPathDB

local char
for _, c in pairs(DB.chars) do if c.skill[profName] then char = c end end
local sk = char.skill[profName]
local line, rank = sk.skillLine, tonumber(os.getenv("PP_START") or "") or sk.rank -- PP_START: plan from another skill
target = target or sk.max
local learned = char.learned[profName] or {}
local trainer = DB.trainer[profName] or {}

local function ahTotal(id, qty)
    local e = DB.prices[id]
    if not e or not e.unit then return nil end
    if not e.book or #e.book == 0 then return e.unit * qty end
    local left, total, last = qty, 0, e.unit
    for _, lot in ipairs(e.book) do
        local take = math.min(left, lot[2])
        total, left, last = total + take * lot[1], left - take, lot[1]
        if left <= 0 then return total end
    end
    return total + left * last * 1.25
end
-- PP_TRACE=<itemID> prints every bulk price lookup for that item
local traceID = tonumber(os.getenv("PP_TRACE") or "")
if traceID then
    local realTotal = ahTotal
    ahTotal = function(id, qty)
        local v = realTotal(id, qty)
        if id == traceID then print(("  trace ahTotal(%d, %d) = %s"):format(id, qty, tostring(v))) end
        return v
    end
end
-- Same as Prices.vendorBuy: merchant visits first, then the seed list at the data's vendor price.
local SEED = { 2320, 2321, 4291, 8343, 14341, 3371, 3372, 8925, 18256, 2880, 3466, 4289, 2678, 2692, 3713,
    2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290, 4470, 5140, 6217 }
local seed = {}
for _, id in ipairs(SEED) do seed[id] = true end
local function vendorBuy(id)
    if DB.vendor[id] then return DB.vendor[id] end
    local d = seed[id] and ns.Data.items[id]
    if d and d[1] > 0 then return d[1] end
end
local function vendorSell(id) local d = ns.Data.items[id]; return d and d[2] end

local recipes = {}
for id, d in pairs(ns.Data.recipes) do
    if d[1] == line and (d[4] > rank or learned[id]) then
        local rg = {}
        for i = 1, #d[7], 2 do rg[#rg + 1] = { d[7][i], d[7][i + 1] } end
        local r = { id = id, name = d[8], minSkill = d[2], yellow = d[3], gray = d[4], productID = d[5],
            productQty = d[6] or 1, reagents = rg, learned = learned[id] == true }
        if not r.learned then
            local te = trainer[r.name]
            if type(te) == "number" then te = { cost = te } end
            local ri = ns.Data.recipeItems[id]
            local cost, req = te and te.cost, te and te.req
            if ri then
                local p = vendorBuy(ri[1]) or ahTotal(ri[1], 1)
                if p and (not cost or p < cost) then cost, req = p, ri[2] end
                req = req or ri[2]
            end
            r.learnCost = cost
            if req and req > r.minSkill then r.minSkill = req end
        end
        recipes[#recipes + 1] = r
    end
end
table.sort(recipes, function(a, b) return a.id < b.id end)

local names = {}
for id, d in pairs(ns.Data.recipes) do names[d[5] or -1] = d[8] end
local function iname(id) return names[id] or ("item " .. id) end
local function money(c) c = math.floor(c + 0.5); return ("%dg %ds %dc"):format(c // 10000, (c // 100) % 100, c % 100) end

if REPRO_LIB then -- used by tests/compare_guide.lua
    return { O = O, ns = ns, DB = DB, recipes = recipes, rank = rank, target = target, ahTotal = ahTotal,
        vendorBuy = vendorBuy, vendorSell = vendorSell, trainer = trainer, learned = learned, money = money, iname = iname }
end

local res = O.optimize({ skill = rank, target = target, recipes = recipes, price = ahTotal, vendorBuy = vendorBuy,
    vendorSell = vendorSell, owned = {}, resaleFactor = resale or 0, ownedFree = true,
    effort = tonumber(os.getenv("PP_EFFORT") or "0") })
print(("%s %d -> %d, resale %s: ok=%s total=%s"):format(profName, rank, target, tostring(resale or 0.5),
    tostring(res.ok), money(res.totalCost or 0)) .. (res.stuckAt and (" stuck at " .. res.stuckAt) or ""))
for _, s in ipairs(res.steps or {}) do
    print(("  %d-%d %s x%.0f  cost %s  learn %s  yellow %d gray %d"):format(s.fromSkill, s.toSkill, s.recipe.name,
        s.expectedCrafts, money(s.cost), money(s.learnCost), s.recipe.yellow, s.recipe.gray))
end
local cash = 0
for _, s in ipairs(res.shopping or {}) do
    local total = (s.source == "ah" and ahTotal(s.itemID, s.buy)) or s.unitCost * s.buy
    cash = cash + total
    print(("  buy %s x%d  unit %s (%s)  total %s"):format(iname(s.itemID), s.buy, money(s.unitCost), s.source or "?", money(total)))
end
print("  cash for materials (script): " .. money(cash))
if res.ok then
    print(("  optimizer: materials %s + recipes %s, sell back %s, net %s"):format(money(res.cash),
        money(res.learnTotal), money(res.sellBack), money(res.cash + res.learnTotal - res.sellBack)))
    for _, it in ipairs(res.intermediates) do print(("  craft first: %s x%d"):format(it.recipe.name, it.crafts)) end
end
