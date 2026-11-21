-- Run from the ProfPath folder:  lua tests/optimizer_spec.lua
local O = dofile("Optimizer.lua")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("ok   " .. name)
    else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, msg)
    if math.abs(a - b) > 1e-6 * math.max(1, math.abs(b)) then
        error((msg or "") .. " expected ~" .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local function R(t)
    t.learned = t.learned ~= false
    t.minSkill = t.minSkill or 1
    t.reagents = t.reagents or {}
    return t
end

-- price table: unit AH prices, flat (no depth) unless a function is given
local function ctxWith(prices, recipes, extra)
    local ctx = {
        skill = 1, target = 10, recipes = recipes, resaleFactor = 0,
        price = function(id, qty) local p = prices[id]; return p and p * qty or nil end,
    }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return ctx
end

test("chance: orange, yellow, gray", function()
    local r = R{ yellow = 10, gray = 20 }
    eq(O.chance(r, 5), 1)
    near(O.chance(r, 15), 0.5)
    eq(O.chance(r, 20), 0)
    eq(O.chance(R{ minSkill = 8, yellow = 10, gray = 20 }, 5), 0, "below min skill")
end)

test("single recipe covers range", function()
    local res = O.optimize(ctxWith({ [100] = 10 }, {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 2 } } },
    }))
    assert(res.ok)
    eq(#res.steps, 1, "steps")
    eq(res.steps[1].fromSkill, 1); eq(res.steps[1].toSkill, 10)
    near(res.steps[1].expectedCrafts, 9)
    eq(res.shopping[1].needed, 18)
    near(res.totalCost, 9 * (20 + 1))
end)

test("cheaper recipe wins", function()
    local res = O.optimize(ctxWith({ [100] = 10, [101] = 3 }, {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } },
    }))
    eq(#res.steps, 1); eq(res.steps[1].recipe.id, 2)
end)

test("learn cost flips the choice", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },             -- 10/craft
        R{ id = 2, yellow = 50, gray = 60, learned = false, learnCost = 200,
           reagents = { { 101, 1 } } },                                               -- 3/craft + 200
    }
    local res = O.optimize(ctxWith({ [100] = 10, [101] = 3 }, recipes))
    eq(res.steps[1].recipe.id, 1, "short range: learning not worth it")
    res = O.optimize(ctxWith({ [100] = 10, [101] = 3 }, recipes, { target = 50 }))
    eq(#res.steps, 1); eq(res.steps[1].recipe.id, 2, "long range: learning pays off")
    eq(res.steps[1].learnCost, 200)
end)

test("gray recipe never chosen", function()
    local res = O.optimize(ctxWith({ [100] = 1, [101] = 50 }, {
        R{ id = 1, yellow = 3, gray = 5, reagents = { { 100, 1 } } },
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } },
    }))
    for _, st in ipairs(res.steps) do
        if st.recipe.id == 1 then assert(st.toSkill <= 5, "used recipe 1 past gray") end
    end
    eq(res.steps[#res.steps].recipe.id, 2)
end)

test("yellow range uses expected crafts", function()
    -- skill 1..10 with yellow 1, gray 11: chance at s = (11-s)/10
    local res = O.optimize(ctxWith({ [100] = 10 }, {
        R{ id = 1, yellow = 1, gray = 11, reagents = { { 100, 1 } } },
    }))
    local expected = 0
    for s = 1, 9 do expected = expected + 10 / (11 - s) end
    near(res.steps[1].expectedCrafts, expected)
end)

test("missing price: recipe skipped and reported", function()
    local res = O.optimize(ctxWith({ [100] = 10 }, {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 999, 1 } } },
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
    }))
    assert(res.ok); eq(res.steps[1].recipe.id, 2); eq(res.missing[1], 999)
end)

test("no usable recipe: reports where it got stuck", function()
    local res = O.optimize(ctxWith({}, { R{ id = 1, yellow = 50, gray = 60, reagents = { { 999, 1 } } } }))
    eq(res.ok, false); eq(res.stuckAt, 1)
end)

test("gather: unpriced material you can gather is used, costs no gold", function()
    local recipes = { R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 2 } } } }
    eq(O.optimize(ctxWith({}, recipes)).ok, false, "without gathering")
    local res = O.optimize(ctxWith({}, recipes, { gather = function(id) return id == 100 and 5 or nil end }))
    assert(res.ok, "with gathering")
    eq(res.shopping[1].source, "gather")
    eq(res.cash, 0, "no gold spent")
    near(res.totalCost, 9 * (10 + 1), "valued at the gather value")
end)

test("gather: an AH price wins over gathering", function()
    local res = O.optimize(ctxWith({ [100] = 3 }, { R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } } },
        { gather = function() return 1 end }))
    eq(res.shopping[1].source, "ah")
end)

test("crafting an intermediate beats buying it", function()
    -- recipe 2 needs item 200 (AH 50) which recipe 1 makes from 2x item 100 (AH 5)
    local res = O.optimize(ctxWith({ [100] = 5, [200] = 50, [300] = 1000 }, {
        R{ id = 1, yellow = 1, gray = 1, productID = 200, productQty = 1, reagents = { { 100, 2 } } },
        R{ id = 2, yellow = 50, gray = 60, productID = 300, reagents = { { 200, 1 } } },
    }))
    eq(res.steps[1].recipe.id, 2)
    eq(#res.shopping, 1); eq(res.shopping[1].itemID, 100); eq(res.shopping[1].needed, 18)
end)

test("vendor price used when cheaper", function()
    local res = O.optimize(ctxWith({ [100] = 10 }, {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
    }, { vendorBuy = function(id) return id == 100 and 4 or nil end }))
    eq(res.shopping[1].source, "vendor"); eq(res.shopping[1].unitCost, 4)
end)

test("vendor wins a tie with the AH", function()
    local res = O.optimize(ctxWith({ [100] = 4 }, {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
    }, { vendorBuy = function(id) return id == 100 and 4 or nil end }))
    eq(res.shopping[1].source, "vendor")
end)

test("resale value lowers net cost and can flip choice", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, productID = 500, reagents = { { 100, 1 } } }, -- 10, sells 20
        R{ id = 2, yellow = 50, gray = 60, productID = 501, reagents = { { 101, 1 } } }, -- 6, worthless
    }
    local prices = { [100] = 10, [101] = 6, [500] = 20 }
    eq(O.optimize(ctxWith(prices, recipes, { resaleFactor = 0 })).steps[1].recipe.id, 2)
    eq(O.optimize(ctxWith(prices, recipes, { resaleFactor = 0.5 })).steps[1].recipe.id, 1)
end)

test("depth pass: bulk price flips choice", function()
    -- item 100 is cheap for the first 5, then expensive; item 101 is flat
    local function price(id, qty)
        if id == 100 then return qty <= 5 and qty * 2 or 10 + (qty - 5) * 20 end
        if id == 101 then return qty * 5 end
    end
    local res = O.optimize({
        skill = 1, target = 10, resaleFactor = 0, price = price,
        recipes = {
            R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
            R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } },
        },
    })
    eq(res.steps[#res.steps].recipe.id, 2)
end)

test("depth pass: raw materials of a newly crafted intermediate get bulk prices", function()
    -- Recipe needs 10x item 200. Item 200: 5 each in bulk-free AH... but only 3 listed cheap,
    -- then expensive -> pass 2 switches to crafting 200 from item 100. Item 100: 1 each for the
    -- first 10, then 50 each. Final plan must price item 100 in bulk, not at 1.
    local function price(id, qty)
        if id == 200 then return qty <= 3 and qty * 5 or 15 + (qty - 3) * 100 end
        if id == 100 then return qty <= 10 and qty or 10 + (qty - 10) * 50 end
        if id == 101 then return qty * 30 end
    end
    local maker = R{ id = 9, yellow = 1, gray = 1, productID = 200, reagents = { { 100, 1 } } }
    local A = R{ id = 1, yellow = 50, gray = 60, reagents = { { 200, 10 } } }
    local B = R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } } -- 30/craft flat
    local res = O.optimize({ skill = 1, target = 10, resaleFactor = 0, price = price, recipes = { maker, A, B } })
    -- A via crafting: 90 units of item 100 -> 10 + 80*50 = 4010 total, far above B's 9*31
    eq(res.steps[1].recipe.id, 2, "B wins once item 100 is priced for 90 units")
end)

test("budget: reaches as far as the gold allows, cheapest way", function()
    -- 1 point per craft at 11 copper (10 + 1 tie-break); 9 points to target 10
    local recipes = { R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } } }
    local function mk(t) return ctxWith({ [100] = 10 }, recipes, { target = t }) end
    local res, reach, limited = O.fitBudget(mk, 1, 10, 1000, "upfront")
    assert(not limited and reach == 10 and res.ok, "plenty of gold: full plan")
    res, reach, limited = O.fitBudget(mk, 1, 10, 45, "upfront")
    assert(limited and res.ok, "limited")
    eq(reach, 5, "45 copper buys 4 crafts at 10 -> skill 5")
    assert(O.planCost(res, "upfront") <= 45)
    res = O.fitBudget(mk, 1, 10, 5, "upfront")
    eq(res, nil, "cannot afford a single craft")
end)

test("budget: batch mode counts vendor returns, up-front does not", function()
    -- craft costs 10, product vends for 8: net 2 per craft
    local recipes = { R{ id = 1, yellow = 50, gray = 60, productID = 500, reagents = { { 100, 1 } } } }
    local function mk(t)
        return ctxWith({ [100] = 10 }, recipes, { target = t, vendorSell = function(id) return id == 500 and 8 or nil end })
    end
    local _, reachB = O.fitBudget(mk, 1, 10, 20, "batch")
    local _, reachU = O.fitBudget(mk, 1, 10, 20, "upfront")
    eq(reachB, 10, "net 2 x 9 = 18 fits 20 in batches")
    eq(reachU, 3, "up front: 20 buys 2 crafts")
end)

test("budget: random instances never exceed the budget", function()
    math.randomseed(11)
    local shortBy = {}
    for trial = 1, 200 do
        local nR, target = math.random(2, 5), math.random(5, 25)
        local prices, recipes = {}, {}
        for i = 1, nR do
            prices[100 + i] = math.random(1, 60)
            local yellow = math.random(1, 25)
            recipes[i] = R{ id = i, minSkill = math.random(1, 5), yellow = yellow, gray = yellow + math.random(1, 15),
                reagents = { { 100 + i, math.random(1, 3) } }, learned = math.random() < 0.7, learnCost = math.random(0, 100) }
        end
        local function mk(t) return ctxWith(prices, recipes, { target = t }) end
        local budget = math.random(10, 600)
        local res, reach = O.fitBudget(mk, 1, target, budget, "upfront")
        if res then
            assert(O.planCost(res, "upfront") <= budget + 1e-6, "trial " .. trial .. " over budget")
            assert(res.steps[#res.steps].toSkill == reach, "trial " .. trial .. " plan ends at reach")
        end
        -- furthest reachable by trying every target
        local brute = 1
        for t = 2, target do
            local r = O.optimize(mk(t))
            if r.ok and O.planCost(r, "upfront") <= budget then brute = t end
        end
        if brute > reach then shortBy[#shortBy + 1] = brute - reach end
    end
    local worst = 0
    for _, v in ipairs(shortBy) do worst = math.max(worst, v) end
    print(("     reach below best possible in %d/200 trials, worst by %d points"):format(#shortBy, worst))
    assert(#shortBy <= 10 and worst <= 2, "budget fitting falls short too often")
end)

test("remaining: crafted intermediates in bags are used before buying their materials", function()
    -- Fine Leather Tunic-like: 3 Cured Light Hide + 6 Light Leather + 4 Coarse Thread per craft.
    -- Cured Light Hide = 1 Light Hide + 1 Salt.
    local cured = R{ id = 9, yellow = 1, gray = 1, productID = 4231, reagents = { { 783, 1 }, { 4289, 1 } } }
    local tunic = R{ id = 1, yellow = 100, gray = 120, reagents = { { 4231, 3 }, { 2318, 6 }, { 2320, 4 } } }
    local inter = { { recipe = cured, crafts = 21 } }
    local function bags(t) return function(id) return t[id] or 0 end end

    -- the user's screenshot: 26 Cured Light Hide already, 7 crafts need 21 -> buy no Light Hide or Salt
    local short, used, left = O.remaining(tunic, 7, inter, bags({ [4231] = 26, [783] = 6, [4289] = 4, [2318] = 311, [2320] = 28 }))
    eq(short[783], nil, "no Light Hide to buy"); eq(short[4289], nil, "no Salt to buy")
    eq(left[cured], nil, "no hides to craft"); eq(used[4231], 21)

    -- 10 hides in bags, 6 Light Hide, 4 Salt: craft 11 more -> buy 5 Light Hide and 7 Salt
    short, used, left = O.remaining(tunic, 7, inter, bags({ [4231] = 10, [783] = 6, [4289] = 4, [2318] = 311, [2320] = 28 }))
    eq(left[cured], 11); eq(short[783], 5); eq(short[4289], 7); eq(short[2318], nil); eq(short[2320], nil)

    -- empty bags: everything from scratch
    short, used, left = O.remaining(tunic, 7, inter, bags({}))
    eq(left[cured], 21); eq(short[783], 21); eq(short[2318], 42); eq(short[2320], 28)
end)

test("free stock: starting stock is free, units bought later are not", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 10 } } }, -- 40/craft at full price
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 200, 3 } } },  -- 36/craft
    }
    local prices = { [100] = 4, [200] = 12 }
    -- 90 of item 100 in the starting stock: 9 crafts of A are free -> A wins
    eq(O.optimize(ctxWith(prices, recipes, { owned = { [100] = 90 }, free = { [100] = 90 } })).steps[1].recipe.id, 1)
    -- same 90 in bags but only bought after starting (no free stock): B still wins
    eq(O.optimize(ctxWith(prices, recipes, { owned = { [100] = 90 }, free = {} })).steps[1].recipe.id, 2)
end)

test("lots of owned stock doesn't pull in a route that needs far more of it", function()
    -- Real case (Tailoring): 726 owned Bolts of Runecloth made a bolt-hungry route look free; it
    -- needed 1799 bolts, so the plan cost more than with half the bolts. Here: 150 owned of 100.
    -- H needs 5 of item 100 per craft, L needs 1 plus 30c of item 200. 120 owned: averaged over
    -- what H needs, item 100 looks cheap enough that H stays best, but H buys far more of it.
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 }, { 200, 1 } } }, -- L
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 100, 5 } } },             -- H
    }
    local prices = { [100] = 10, [200] = 30 }
    local function withStock(n, extra)
        local e = { target = 60, owned = { [100] = n }, free = { [100] = n } }
        for k, v in pairs(extra or {}) do e[k] = v end
        return ctxWith(prices, recipes, e)
    end
    local res = O.optimize(withStock(120))
    assert(res.ok)
    local onlyL = O.optimize(withStock(120, { onlyLevel = { [1] = true } }))
    assert(res.cash <= onlyL.cash + 1e-6, ("plan %s > L with the stock %s"):format(res.cash, onlyL.cash))
    -- and more stock never costs more
    local more = O.optimize(withStock(240))
    assert(more.cash <= res.cash + 1e-6, ("240 owned %s > 120 owned %s"):format(more.cash, res.cash))
end)

test("tie-break: equal cost -> highest net yield, then shortest craft time, then recipe ID", function()
    -- Both crafts sell for more than their materials, so both cost 0 net (floored): a tie.
    local sells = { [500] = 15, [501] = 30 }
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, productID = 500, reagents = { { 100, 1 } } }, -- yields 5
        R{ id = 2, yellow = 50, gray = 60, productID = 501, reagents = { { 100, 1 } } }, -- yields 20
    }
    local res = O.optimize(ctxWith({ [100] = 10 }, recipes, { vendorSell = function(id) return sells[id] end }))
    eq(res.steps[1].recipe.id, 2, "higher net yield")
    eq(#res.steps, 1, "one recipe all the way")
    -- Same cost and yield: the shorter craft wins, whichever comes first in the list.
    recipes = {
        R{ id = 1, yellow = 50, gray = 60, castTime = 5000, reagents = { { 100, 1 } } },
        R{ id = 2, yellow = 50, gray = 60, castTime = 3000, reagents = { { 100, 1 } } },
    }
    eq(O.optimize(ctxWith({ [100] = 10 }, recipes)).steps[1].recipe.id, 2, "shorter craft time")
    recipes[1], recipes[2] = recipes[2], recipes[1]
    eq(O.optimize(ctxWith({ [100] = 10 }, recipes)).steps[1].recipe.id, 2, "shorter craft time, list reversed")
    -- Everything equal: the lower recipe ID, so the plan is the same every session.
    recipes = { R{ id = 7, yellow = 50, gray = 60, reagents = { { 100, 1 } } }, R{ id = 3, yellow = 50, gray = 60, reagents = { { 100, 1 } } } }
    eq(O.optimize(ctxWith({ [100] = 10 }, recipes)).steps[1].recipe.id, 3, "lower ID")
end)

test("free stock of a raw material is crafted into a bought intermediate, the rest is bought", function()
    -- Heavy Leather (4234) 221c on the AH, or 5 Medium Leather (2319) at 99c: buying is cheaper,
    -- unless the Medium Leather is already yours.
    local recipes = {
        R{ id = 1, yellow = 125, gray = 135, productID = 4234, reagents = { { 2319, 5 } } }, -- Heavy Leather (gray)
        R{ id = 2, yellow = 160, gray = 180, reagents = { { 4234, 10 } } },                   -- uses Heavy Leather
    }
    local prices = { [4234] = 221, [2319] = 99 }
    local function plan(n)
        local e = { skill = 160, target = 170 }
        if n then e.owned, e.free = { [2319] = n }, { [2319] = n } end
        return O.optimize(ctxWith(prices, recipes, e))
    end
    local function line(res, id) for _, sh in ipairs(res.shopping) do if sh.itemID == id then return sh end end end
    local none = plan()
    local heavy = line(none, 4234).needed
    local res = plan(60) -- 60 Medium = 12 Heavy
    eq(line(res, 4234).buy, heavy - 12, "buy the rest of the Heavy Leather")
    eq(line(res, 2319).buy, 0, "no Medium Leather bought")
    eq(res.intermediates[1] and res.intermediates[1].crafts, 12, "craft 12 Heavy Leather")
    assert(res.intermediates[1].fromStock, "marked as crafted from stock")
    near(none.cash - res.cash, 12 * 221, "saves 12 Heavy Leather")
    -- Bought Medium Leather (not free) is never crafted: 5 x 99 > 221.
    local later = O.optimize(ctxWith(prices, recipes, { skill = 160, target = 170, owned = { [2319] = 60 }, free = {} }))
    eq(#later.intermediates, 0, "bought stock isn't converted")
    -- Do it tab: craft what the bags hold Medium Leather for, buy the rest of the Heavy Leather.
    local bags = { [2319] = 23, [4234] = 4 }
    local short, used, craftsLeft = O.remaining(recipes[2], 3, res.intermediates, function(id) return bags[id] or 0 end)
    -- 3 crafts need 30 Heavy: 4 in bags, 4 crafted from 20 Medium (23 in bags), 22 to buy
    eq(used[4234], 4, "Heavy Leather from bags")
    eq(craftsLeft[recipes[1]], 4, "4 crafted from Medium in bags")
    eq(used[2319], 20, "20 Medium used")
    eq(short[4234], 22, "the rest bought ready-made")
    eq(short[2319], nil, "no Medium bought")
end)

test("free hides become cured hides with vendor salt, when that beats buying them", function()
    -- Cured Medium Hide (4233) 150c on the AH, or 1 Medium Hide (4232, yours) + 1 Salt (4289, vendor 50c).
    local recipes = {
        R{ id = 1, yellow = 115, gray = 125, productID = 4233, reagents = { { 4232, 1 }, { 4289, 1 } } },
        R{ id = 2, yellow = 160, gray = 180, reagents = { { 4233, 2 } } },
    }
    local function plan(salt)
        return O.optimize(ctxWith({ [4233] = 150, [4232] = 300 }, recipes, { skill = 160, target = 170,
            vendorBuy = function(id) if id == 4289 then return salt end end,
            owned = { [4232] = 10 }, free = { [4232] = 10 } }))
    end
    local function line(res, id) for _, sh in ipairs(res.shopping) do if sh.itemID == id then return sh end end end
    local res = plan(50)
    eq(res.intermediates[1] and res.intermediates[1].crafts, 10, "10 hides cured")
    eq(line(res, 4289).buy, 10, "10 salt bought")
    eq(line(res, 4289).source, "vendor", "salt from the vendor")
    eq(line(res, 4232).buy, 0, "no hides bought")
    -- Salt dearer than a ready-made cured hide: buy the cured hides instead.
    res = plan(200)
    eq(#res.intermediates, 0, "salt too dear: nothing cured")
    -- Do it tab: 6 hides in bags, no salt: cure 6 (buy 6 salt), buy the rest cured.
    res = plan(50)
    local bags = { [4232] = 6 }
    local short, used, craftsLeft = O.remaining(recipes[2], 8, res.intermediates, function(id) return bags[id] or 0 end)
    eq(craftsLeft[recipes[1]], 6, "6 cured from the hides in bags")
    eq(short[4289], 6, "6 salt to buy")
    eq(short[4233], 10, "10 cured hides to buy")
    eq(short[4232], nil, "no hides to buy")
end)

test("onlyLevel: a locked plan levels only with its recipes", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } }, -- 10
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } }, -- 5, cheaper
    }
    local res = O.optimize(ctxWith({ [100] = 10, [101] = 5 }, recipes, { onlyLevel = { [1] = true } }))
    eq(res.steps[1].recipe.id, 1, "locked to recipe 1")
    eq(O.optimize(ctxWith({ [100] = 10, [101] = 5 }, recipes)).steps[1].recipe.id, 2, "fresh plan picks 2")
end)

test("cooldown recipes never level; a missing tool is a one-time cost", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, noLevel = true, reagents = { { 100, 1 } } },     -- cheapest, but cooldown
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } },                     -- 20/craft
        R{ id = 3, yellow = 50, gray = 60, toolCost = 50, reagents = { { 102, 1 } } },      -- 10/craft + tool 50
    }
    local prices = { [100] = 1, [101] = 20, [102] = 10 }
    local res = O.optimize(ctxWith(prices, recipes, { target = 4 }))         -- 3 points: tool doesn't pay off
    eq(res.steps[1].recipe.id, 2, "short: no tool")
    res = O.optimize(ctxWith(prices, recipes, { target = 30 }))              -- 29 points: tool pays off
    eq(res.steps[1].recipe.id, 3, "long: buy the tool")
    eq(res.steps[1].learnCost, 50, "tool cost reported as the one-time cost")
    for _, st in ipairs(res.steps) do assert(st.recipe.id ~= 1, "cooldown recipe used") end
    assert(recipes[3].learned and recipes[3].toolCost == 50, "recipe state restored after re-solve")
end)

test("a few free units of a raw material don't make crafting the intermediate look free", function()
    -- Real case: 23 owned Medium Leather (98c), Heavy Leather 2s on the AH or crafted from 5 Medium.
    -- The cheap route buys Heavy Leather; crafting it from mostly bought Medium costs 4.9s each.
    local recipes = {
        R{ id = 1, yellow = 125, gray = 135, productID = 4234, reagents = { { 2319, 5 } } },        -- Heavy Leather
        R{ id = 2, yellow = 160, gray = 180, reagents = { { 4234, 10 }, { 2321, 2 } } },            -- Dusky-like
        R{ id = 3, yellow = 170, gray = 190, reagents = { { 7392, 4 }, { 4234, 10 }, { 2321, 2 } } }, -- Whelp-like
    }
    local ctx = ctxWith({ [4234] = 200, [2319] = 98, [2321] = 100, [7392] = 400 }, recipes,
        { skill = 150, target = 171, owned = { [2319] = 23 }, free = { [2319] = 23 } })
    local res = O.optimize(ctx)
    assert(res.ok)
    eq(res.steps[1].recipe.id, 2, "cheap route")
    for _, sh in ipairs(res.shopping) do
        if sh.itemID == 4234 then eq(sh.source, "ah", "Heavy Leather is bought") end
    end
end)

test("batch: fixed once set, learning the recipe doesn't grow it, counts down, then resizes", function()
    -- Real case: 5g budget, 15s learn cost -> 12 crafts; after learning, the gold would allow 13.
    local size, rec = O.batchSize(nil, 12, 0, 92)        -- nothing bought yet
    eq(size, 12, "first batch from the gold")
    size, rec = O.batchSize(rec, 12, 5, 92)               -- bought part of it
    eq(size, 12, "while buying: same batch, list shows the rest")
    size, rec = O.batchSize(rec, 12, 12, 92)              -- all bought
    eq(size, 12, "all in the bags")
    size, rec = O.batchSize(rec, 13, 12, 92)              -- learned the recipe: gold allows 13 now
    eq(size, 12, "learning the recipe doesn't grow the batch")
    size, rec = O.batchSize(rec, 13, 7, 87)               -- crafted 5
    eq(size, 7, "counts down while crafting, nothing to buy")
    size, rec = O.batchSize(rec, 13, 0, 80)               -- batch used up (vendored)
    eq(size, 13, "next batch sized fresh")
    eq(rec.ready, nil, "and not bought yet")
end)

test("batch: bags already holding nearly a full batch are adopted", function()
    local size = O.batchSize(nil, 13, 12, 92)             -- your state after the update
    eq(size, 12)
    size = O.batchSize(nil, 13, 4, 92)                    -- a few leftovers: normal batch
    eq(size, 13)
end)

test("owned materials are free", function()
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } },
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 } } },
    }
    local res = O.optimize(ctxWith({ [100] = 10, [101] = 5 }, recipes, { owned = { [100] = 20 }, ownedFree = true }))
    eq(res.steps[1].recipe.id, 1)
    eq(res.shopping[1].buy, 0)
end)

test("default: buying materials for the plan does not change the plan", function()
    -- A: 10 Light-Leather-like (item 100 at 4) per craft = 40. B: 3 of item 200 at 12 = 36 (cheaper).
    -- Player buys item 100 for... nothing: plan picks B. Now the player owns lots of item 100 (bought
    -- for some other reason): plan must still pick B, and with B's materials in the bags, still B.
    local recipes = {
        R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 10 } } },
        R{ id = 2, yellow = 50, gray = 60, reagents = { { 200, 3 } } },
    }
    local prices = { [100] = 4, [200] = 12 }
    eq(O.optimize(ctxWith(prices, recipes)).steps[1].recipe.id, 2, "empty bags: B")
    eq(O.optimize(ctxWith(prices, recipes, { owned = { [100] = 500 } })).steps[1].recipe.id, 2,
        "owning A's materials does not flip to A")
    local res = O.optimize(ctxWith(prices, recipes, { owned = { [200] = 15 } }))
    eq(res.steps[1].recipe.id, 2, "owning B's materials keeps B")
    eq(res.shopping[1].buy, 27 - 15, "and only the rest is bought")
    eq(res.cash, (27 - 15) * 12, "gold to spend counts only what is bought")
end)

test("random instances match brute force", function()
    -- Brute force: choose a subset of unlearned recipes to learn, then take the cheapest
    -- usable recipe at each level. That is the true optimum when learn cost is the only coupling.
    math.randomseed(42)
    local bad = 0
    for trial = 1, 300 do
        local nR, target = math.random(2, 5), math.random(5, 25)
        local prices, recipes = {}, {}
        for i = 1, nR do
            prices[100 + i] = math.random(1, 50)
            local yellow = math.random(1, 25)
            recipes[i] = R{ id = i, minSkill = math.random(1, 10), yellow = yellow,
                gray = yellow + math.random(1, 15), reagents = { { 100 + i, math.random(1, 3) } },
                learned = math.random() < 0.6, learnCost = math.random(0, 300) }
        end
        local res = O.optimize(ctxWith(prices, recipes, { target = target }))

        local unl = {}
        for i, r in ipairs(recipes) do if not r.learned then unl[#unl + 1] = i end end
        local best = math.huge
        for mask = 0, 2 ^ #unl - 1 do
            local avail, cost = {}, 0
            for i, r in ipairs(recipes) do avail[i] = r.learned end
            for b = 1, #unl do
                if math.floor(mask / 2 ^ (b - 1)) % 2 == 1 then
                    avail[unl[b]] = true; cost = cost + recipes[unl[b]].learnCost
                end
            end
            for s = 1, target - 1 do
                local m = math.huge
                for i, r in ipairs(recipes) do
                    local p = O.chance(r, s)
                    if avail[i] and p > 0 then
                        m = math.min(m, (prices[100 + i] * r.reagents[1][2] + 1) / p)
                    end
                end
                cost = cost + m
            end
            best = math.min(best, cost)
        end

        if best == math.huge then
            assert(not res.ok, "trial " .. trial .. ": found a path where none exists")
        else
            assert(res.ok, "trial " .. trial .. ": no path but brute force found " .. best)
            local sum = 0
            for _, st in ipairs(res.steps) do sum = sum + st.cost end
            near(sum, res.totalCost, "trial " .. trial .. " step sum")
            assert(res.totalCost >= best - 1e-6, "trial " .. trial .. ": beat the optimum?")
            if res.totalCost > best + 1e-6 then bad = bad + 1 end
        end
    end
    eq(bad, 0, "trials above the true optimum:")
end)

test("dominated: clearly pricier recipe pruned, close or unknown ones kept", function()
    local A = R{ id = 1, yellow = 60, gray = 70, reagents = { { 100, 1 } } }           -- 10/craft, orange to 60
    local B = R{ id = 2, yellow = 50, gray = 60, reagents = { { 101, 1 }, { 999, 1 } } } -- 101 known, 999 unknown
    local C = R{ id = 3, yellow = 50, gray = 60, reagents = { { 102, 1 } } }           -- 12: within 1.5x
    local D = R{ id = 4, yellow = 50, gray = 60, reagents = { { 998, 1 } } }           -- nothing known
    local E = R{ id = 5, yellow = 70, gray = 80, minSkill = 1, reagents = { { 101, 1 } } }
    local ctx = ctxWith({ [100] = 10, [101] = 100, [102] = 12 }, { A, B, C, D, E }, { target = 60 })
    local d = O.dominated(ctx, 1.5)
    assert(d[B], "B: known part alone is 10x A")
    assert(not d[A] and not d[C] and not d[D], "A, C, D kept")
    assert(d[E], "E is beaten everywhere A is usable")
    -- E is the only option above 60: kept there
    ctx = ctxWith({ [100] = 10, [101] = 100 }, { A, E }, { target = 75 })
    assert(not O.dominated(ctx, 1.5)[E], "E needed for 60-75")
end)

test("dominated: unknown product value needs double margin", function()
    local A = R{ id = 1, yellow = 50, gray = 60, reagents = { { 100, 1 } } }
    local B = R{ id = 2, yellow = 50, gray = 60, productID = 500, reagents = { { 101, 1 } } }
    local ctx = ctxWith({ [100] = 10, [101] = 20 }, { A, B }, { resaleFactor = 0.5 })
    assert(not O.dominated(ctx, 1.5)[B], "2x but product unpriced: could resell, keep")
    ctx = ctxWith({ [100] = 10, [101] = 40 }, { A, B }, { resaleFactor = 0.5 })
    assert(O.dominated(ctx, 1.5)[B], "4x even unpriced: prune")
end)

test("dominated: crafting an intermediate counts as its cheaper price", function()
    -- B needs item 200: AH 100, but a learned recipe makes it from item 100 at 5
    local maker = R{ id = 9, yellow = 1, gray = 1, productID = 200, reagents = { { 100, 1 } } }
    local A = R{ id = 1, yellow = 50, gray = 60, reagents = { { 101, 1 } } } -- 10/craft
    local B = R{ id = 2, yellow = 50, gray = 60, reagents = { { 200, 1 } } }
    local ctx = ctxWith({ [100] = 5, [101] = 10, [200] = 100 }, { maker, A, B })
    assert(not O.dominated(ctx, 1.5)[B], "B is cheap via crafting")
end)

test("random instances: pruning never loses the optimum", function()
    math.randomseed(7)
    local worse = 0
    for trial = 1, 300 do
        local nR, target = math.random(2, 6), math.random(5, 30)
        local prices, recipes = {}, {}
        for i = 1, nR do
            prices[100 + i] = math.random(1, 80)
            local yellow = math.random(1, 25)
            recipes[i] = R{ id = i, minSkill = math.random(1, 10), yellow = yellow,
                gray = yellow + math.random(1, 15), reagents = { { 100 + i, math.random(1, 3) } },
                learned = math.random() < 0.6, learnCost = math.random(0, 300) }
        end
        local full = O.optimize(ctxWith(prices, recipes, { target = target }))
        local d = O.dominated(ctxWith(prices, recipes, { target = target }), 1.5)
        local kept = {}
        for _, r in ipairs(recipes) do if not d[r] then kept[#kept + 1] = r end end
        local pruned = O.optimize(ctxWith(prices, kept, { target = target }))
        assert(full.ok == pruned.ok, "trial " .. trial .. ": pruning changed feasibility")
        if full.ok and pruned.totalCost > full.totalCost + 1e-6 then worse = worse + 1 end
    end
    eq(worse, 0, "trials where pruning made the path more expensive:")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
