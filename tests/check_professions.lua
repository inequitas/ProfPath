-- Plans every crafting profession offline with real data and saved prices, in rank bands, as a
-- fresh character (nothing learned; trainer recipes at estimated cost). Flags anything odd.
-- Usage (from the ProfPath folder): lua tests/check_professions.lua <SavedVariables path>
local ns = {}
assert(loadfile("Data/Recipes.lua"))(nil, ns)
local O = assert(loadfile("Optimizer.lua"))(nil, ns)
dofile(arg[1])
local DB, D = ProfPathDB, ns.Data

local SEED = { 2320, 2321, 4291, 8343, 14341, 3371, 3372, 8925, 18256, 2880, 3466, 4289, 2678, 2692, 3713,
    2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290, 4470, 5140, 6217 }
local seed = {}
for _, id in ipairs(SEED) do seed[id] = true end
local function vendorBuy(id)
    if DB.vendor[id] then return DB.vendor[id] end
    local d = seed[id] and D.items[id]
    if d and d[1] > 0 then return d[1] end
end
local function vendorSell(id) local d = D.items[id]; return d and d[2] end
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
local function money(c) c = math.floor(c + 0.5); return ("%dg%02ds"):format(c // 10000, (c // 100) % 100) end
local function estReq(y, g) local gap = g - y; return gap <= 10 and y or (y - gap) end

-- Cheapest way to get a tool category (vendor, AH, or crafting it), as the addon does.
local makers = {}
for _, d in pairs(D.recipes) do if d[5] then makers[d[5]] = makers[d[5]] or {}; table.insert(makers[d[5]], d) end end
local function itemCost(id)
    local best = vendorBuy(id) or (ahTotal(id, 1))
    for _, d in ipairs(makers[id] or {}) do
        local c = 0
        for i = 1, #d[7], 2 do
            local u = vendorBuy(d[7][i]) or ahTotal(d[7][i], 1)
            if not u then c = nil; break end
            c = c + u * d[7][i + 1]
        end
        if c and (not best or c < best) then best = c end
    end
    return best
end
local toolPrice = {}
local function toolCost(spell)
    local cats, total = D.tools and D.tools[spell], 0
    if not cats then return 0 end
    for _, c in ipairs(cats) do
        if toolPrice[c] == nil then
            local best = false
            for _, id in ipairs(D.toolItems[c] or {}) do
                local p = itemCost(id)
                if p and (not best or p < best) then best = p end
            end
            toolPrice[c] = best
        end
        if not toolPrice[c] then return nil end
        total = total + toolPrice[c]
    end
    return total
end

local LINES = { 197, 164, 202, 171, 333, 185, 129, 186, 165 }
local BANDS = { { 1, 75 }, { 75, 150 }, { 150, 225 }, { 225, 300 } }

for _, line in ipairs(LINES) do
    local recipes = {}
    for id, d in pairs(D.recipes) do
        if d[1] == line then
            local rg = {}
            for i = 1, #d[7], 2 do rg[#rg + 1] = { d[7][i], d[7][i + 1] } end
            local r = { id = id, name = d[8], minSkill = d[2], yellow = d[3], gray = d[4], productID = d[5],
                productQty = d[6] or 1, reagents = rg, learned = false }
            local ri = D.recipeItems[id]
            if r.yellow <= 1 or (D.autoLearn and D.autoLearn[id]) then
                r.learned = true -- starter recipe: known, no learn cost or skill requirement
            elseif ri then
                local p = vendorBuy(ri[1]) or ahTotal(ri[1], 1)
                r.learnCost, r.minSkill = p, math.max(r.minSkill, ri[2])
            else
                local req = estReq(r.yellow, r.gray)
                r.learnCost, r.minSkill = math.max(100, math.floor(2000 * (req / 150) ^ 2)), math.max(r.minSkill, req)
            end
            if D.cooldown and D.cooldown[id] then r.noLevel = true end            -- transmutes, Mooncloth
            local spec = ri and (ri[3] or 0) ~= 0                                -- needs a specialization
            local tc = toolCost(id)
            if tc and tc > 0 then r.toolCost = tc end
            if not spec and tc then recipes[#recipes + 1] = r end
        end
    end
    table.sort(recipes, function(a, b) return a.id < b.id end)
    print(("== %s (%d recipes)"):format(D.skillLines[line] or line, #recipes))
    for _, b in ipairs(BANDS) do
        local res = O.optimize({ skill = b[1], target = b[2], recipes = recipes, price = ahTotal, vendorBuy = vendorBuy,
            vendorSell = vendorSell, owned = {}, resaleFactor = 0 })
        if not res.ok then
            print(("  %3d-%3d  NO PATH, stuck at %s (%d unpriced materials)"):format(b[1], b[2], tostring(res.stuckAt),
                #(function() local t = {} for k in pairs(res.missing or {}) do t[#t + 1] = k end return t end)()))
        else
            local crafts, names = 0, {}
            for _, s in ipairs(res.steps) do
                crafts = crafts + s.expectedCrafts
                names[#names + 1] = ("%s %d-%d"):format(s.recipe.name, s.fromSkill, s.toSkill)
            end
            print(("  %3d-%3d  spend %-9s net %-9s crafts %4.0f  %s"):format(b[1], b[2], money(res.cash + res.learnTotal),
                money(res.cash + res.learnTotal - res.sellBack), crafts, table.concat(names, " > ")))
        end
    end
end
