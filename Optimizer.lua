-- ProfPath optimizer. Pure Lua: no WoW API calls, so it runs and is tested offline.
-- All money values are in copper.
--
-- Recipe (normalized):
--   { id, name, minSkill, yellow, gray, learned, learnCost, skillUps,
--     reagents = { {itemID, qty}, ... }, productID, productQty }
--   minSkill: skill needed to craft; yellow: skill where it stops being orange;
--   gray: skill where it stops giving points.
--
-- ctx:
--   skill, target               current and goal skill
--   recipes                     list of normalized recipes
--   price(itemID, qty)          total AH cost of buying qty, or nil if unknown
--   vendorBuy(itemID)           unit vendor price, or nil
--   vendorSell(itemID)          unit vendor sell value, or nil
--   owned[itemID]               units in bags/bank
--   resaleFactor (0.5)          share of AH value counted as recovered when selling products
--   free[itemID]                units that cost nothing (the stock you had when the plan started);
--                               other owned units are valued at what replacing them would cost, so
--                               buying for the plan never changes the plan, only the shopping list.
--   ownedFree (false)           shortcut: treat everything owned as free.
--   onlyLevel[recipeID]         if set, only these recipes may give skill points.
--   lockAt(skill) -> recipeID   if set, at each skill only that recipe may give points (a locked plan).

local _, ns = ...
ns = type(ns) == "table" and ns or {}

local O = {}
ns.Optimizer = O

local INF = math.huge
local CRAFT_TIEBREAK = 1 -- 1 copper per craft: prefer fewer crafts when costs tie
local AH_CUT = 0.95

-- One-time cost of starting to use a recipe: learning it (if not known) plus any tool you lack.
function O.oneTimeCost(r)
    return (r.learned and 0 or (r.learnCost or INF)) + (r.toolCost or 0)
end

function O.chance(r, s)
    if s < (r.minSkill or 0) or s >= r.gray then return 0 end
    if s < r.yellow then return 1 end
    return (r.gray - s) / (r.gray - r.yellow)
end

-- Unit cost of one reagent: cheapest of AH, vendor, or crafting it with a learned recipe.
-- Returns cost, source ("ah"|"vendor"|"craft"|nil), recipe used for crafting.
local function makeUnitCost(ctx, producers, missing)
    local memo, active = {}, {}
    local function unitCost(itemID)
        local m = memo[itemID]
        if m then return m[1], m[2], m[3] end
        if active[itemID] then return INF end -- cycle guard
        active[itemID] = true

        local best, src, via = INF, nil, nil
        local over = ctx.unitOverride and ctx.unitOverride[itemID]
        local ah = over or (ctx.price and ctx.price(itemID, 1))
        if ah and ah < best then best, src = ah, "ah" end
        local vb = ctx.vendorBuy and ctx.vendorBuy(itemID)
        -- On a tie the vendor wins: unlimited stock, and its price does not climb with quantity.
        if vb and vb <= best then best, src = vb, "vendor" end
        -- Nothing to buy: gather it yourself (ore, herbs, leather) if you can, valued at what it
        -- would sell for at a vendor.
        if best == INF and ctx.gather then
            local g = ctx.gather(itemID)
            if g then best, src = g, "gather" end
        end
        for _, r in ipairs(producers[itemID] or {}) do
            local c = ctx.effort or 0 -- optional cost per craft: prefer buying over lots of crafting
            for _, rg in ipairs(r.reagents) do
                c = c + unitCost(rg[1]) * rg[2]
                if c == INF then break end
            end
            c = c / (r.productQty or 1)
            if c < best then best, src, via = c, "craft", r end
        end

        active[itemID] = nil
        if best == INF then missing[itemID] = true end
        memo[itemID] = { best, src, via }
        return best, src, via
    end
    return unitCost
end

local function recovery(ctx, itemID)
    if not itemID then return 0 end
    local vs = (ctx.vendorSell and ctx.vendorSell(itemID)) or 0
    local ah = ctx.price and ctx.price(itemID, 1)
    local resale = ah and ah * AH_CUT * (ctx.resaleFactor or 0.5) or 0
    return math.max(vs, resale)
end

-- Cost of one craft, net of what the product is worth. Never below zero.
local function craftCost(ctx, r, unitCost)
    local c = 0
    for _, rg in ipairs(r.reagents) do
        c = c + unitCost(rg[1]) * rg[2]
    end
    if c == INF then return INF end
    c = c - recovery(ctx, r.productID) * (r.productQty or 1)
    return math.max(c, 0) + CRAFT_TIEBREAK + (ctx.effort or 0)
end

-- One DP pass. Returns steps, totalCost.
local function solve(ctx, unitCost)
    local s0, target = ctx.skill, ctx.target
    -- Only recipes that can give a point somewhere in [s0, target) take part in the search;
    -- the rest (e.g. known gray recipes kept to craft intermediates) only matter for unitCost.
    -- ctx.onlyLevel = { [recipeID] = true } limits which recipes may give points (a locked plan);
    -- other learned recipes can still craft intermediates.
    local recipes = {}
    for _, r in ipairs(ctx.recipes) do
        if r.gray > s0 and (r.minSkill or 0) < target and not r.noLevel
            and (not ctx.onlyLevel or ctx.onlyLevel[r.id]) then
            recipes[#recipes + 1] = r
        end
    end
    local net = {}
    for i, r in ipairs(recipes) do net[i] = craftCost(ctx, r, unitCost) end

    -- dist[s]: cheapest way to reach skill s.
    -- g[i]: cheapest way to be at skill s with recipe i learned and in use (contiguous run).
    -- enter[i][s]: true if run of recipe i at s started at s (paid learn cost), false if continued.
    -- pick[s+1]: recipe index used to go from s to s+1.
    local dist, pick, g, enter = { [s0] = 0 }, {}, {}, {}
    for i in ipairs(recipes) do g[i] = INF; enter[i] = {} end

    for s = s0, target - 1 do
        local best, bestI = INF, nil
        for i, r in ipairs(recipes) do
            local learn = O.oneTimeCost(r)
            local viaEnter = dist[s] + learn
            local viaCont = g[i]
            if viaEnter <= viaCont then g[i] = viaEnter; enter[i][s] = true
            else enter[i][s] = false end

            local p = O.chance(r, s)
            if ctx.lockAt and ctx.lockAt(s) ~= r.id then p = 0 end -- locked plan: this skill's recipe only
            if p > 0 and net[i] < INF and g[i] < INF then
                local step = g[i] + net[i] / (p * (r.skillUps or 1))
                if step < best then best, bestI = step, i end
                g[i] = step -- continuing with this recipe at s+1
            else
                g[i] = INF
            end
        end
        if not bestI then return nil, INF, s, dist end
        dist[s + 1], pick[s + 1] = best, bestI
    end

    -- Walk back. Each run of recipe i ends at a level reached via pick[] and is followed back
    -- through enter[i][] to where it started from dist[] (pick[] alone can leave the chosen run).
    local steps = {}
    local s = target
    while s > s0 do
        local i = pick[s]
        local r = recipes[i]
        local hi = s
        repeat s = s - 1 until enter[i][s]
        local learn = O.oneTimeCost(r)
        local prev = steps[1]
        if prev and prev.recipe == r and prev.learnCost == 0 then
            prev.fromSkill = s -- merge adjacent runs of the same recipe
            prev.learnCost = learn
            prev.cost = prev.cost + dist[hi] - dist[s]
        else
            table.insert(steps, 1, { recipe = r, fromSkill = s, toSkill = hi, learnCost = learn,
                cost = dist[hi] - dist[s] })
        end
    end
    for _, st in ipairs(steps) do
        local r, crafts = st.recipe, 0
        for k = st.fromSkill, st.toSkill - 1 do crafts = crafts + 1 / (O.chance(r, k) * (r.skillUps or 1)) end
        st.expectedCrafts = crafts
    end
    return steps, dist[target], nil, dist
end

-- Expand crafts into the raw materials to buy, following "craft" sources recursively.
-- Also returns how often each intermediate recipe must be crafted: { [recipe] = crafts }.
local function shoppingList(steps, unitCost)
    local need, crafted = {}, {}
    local function add(itemID, qty)
        local _, src, via = unitCost(itemID)
        if src == "craft" then
            local crafts = qty / (via.productQty or 1)
            crafted[via] = (crafted[via] or 0) + crafts
            for _, rg in ipairs(via.reagents) do add(rg[1], rg[2] * crafts) end
        else
            need[itemID] = (need[itemID] or 0) + qty
        end
    end
    for _, st in ipairs(steps) do
        for _, rg in ipairs(st.recipe.reagents) do add(rg[1], rg[2] * st.expectedCrafts) end
    end
    return need, crafted
end

-- zeroFree: true = owned stock costs nothing; false = limited (see freeAverage); "market" = owned
-- stock is priced like anything else when choosing recipes (only the shopping list subtracts it).
local function optimizeWith(ctx, zeroFree)
    local atMarket = zeroFree == "market"
    if atMarket then zeroFree = false end
    ctx.target = ctx.target or ctx.maxSkill
    local producers = {}
    for _, r in ipairs(ctx.recipes) do
        if r.learned and r.productID then
            producers[r.productID] = producers[r.productID] or {}
            table.insert(producers[r.productID], r)
        end
    end

    local owned = ctx.owned or {}
    -- free[itemID] = units that cost nothing (stock you started with). ownedFree = everything owned.
    local free = ctx.free or (ctx.ownedFree == true and owned) or {}

    -- Free stock only covers the units you have. Before the quantity needed is known, price a free
    -- item as the average over a typical amount (FREE_REF units) with the free units at 0, so a few
    -- free units don't make every further unit look free. (Treating owned items as costing nothing
    -- per unit made 23 owned Medium Leather turn crafting Heavy Leather "free" and flip the plan.)
    -- Items with no market price keep a full discount: there is nothing else to price them by.
    -- Later passes price each needed item for the full quantity (order-book depth), net of free
    -- units, and stop once the chosen recipes no longer change.
    local FREE_REF = 100
    local function freeAverage(itemID, n)
        local market = (ctx.price and ctx.price(itemID, FREE_REF)) or (ctx.vendorBuy and ctx.vendorBuy(itemID)
            and ctx.vendorBuy(itemID) * FREE_REF)
        if not market then return 0 end
        local buy = math.max(FREE_REF - n, 0)
        if buy == 0 then return 0 end
        local cost = (ctx.price and ctx.price(itemID, buy)) or market / FREE_REF * buy
        return cost / FREE_REF
    end
    local override = {}
    if atMarket then free = {} end -- choose as if nothing were owned
    for itemID, n in pairs(free) do if n > 0 then override[itemID] = zeroFree and 0 or freeAverage(itemID, n) end end

    local steps, total, stuckAt, unitCost, missing, need, dist
    local signature
    -- Converged when neither the steps nor the set of items to buy changed, so every bought item
    -- has been priced for the quantity actually needed (switching to crafting an intermediate brings
    -- new raw materials into the list, and those need their bulk price too).
    for _ = 1, 8 do
        if O.yield then O.yield() end -- let the game draw a frame (set by Core)
        ctx.unitOverride = override
        missing = {}
        unitCost = makeUnitCost(ctx, producers, missing)
        steps, total, stuckAt, dist = solve(ctx, unitCost)
        ctx.unitOverride = nil
        if not steps then
            -- dist: cheapest cost to reach each skill before getting stuck (used for budget fitting)
            return { ok = false, stuckAt = stuckAt, missing = missing, dist = dist }
        end
        need = shoppingList(steps, unitCost)

        local sig = {}
        for _, st in ipairs(steps) do sig[#sig + 1] = tostring(st.recipe.id) .. ":" .. st.fromSkill end
        local ids = {}
        for itemID in pairs(need) do ids[#ids + 1] = itemID end
        table.sort(ids)
        sig = table.concat(sig, ",") .. "|" .. table.concat(ids, ",")
        if sig == signature then break end
        signature = sig

        -- Keep earlier bulk prices for items that dropped out, so an alternative that brings them
        -- back is not suddenly priced at the single cheapest listing again.
        local prev = override
        override = {}
        for itemID, v in pairs(prev) do override[itemID] = v end
        for itemID, qty in pairs(need) do
            local n = math.ceil(qty - 1e-9)
            local have = free[itemID] or 0
            local buy = math.max(n - have, 0)
            if n > 0 then
                local cost = buy == 0 and 0 or (ctx.price and ctx.price(itemID, buy))
                if cost then override[itemID] = cost / n end
            end
        end
        -- Free items not in the current list keep their limited discount so alternatives can still
        -- use them (but only as far as the free units go).
        for itemID, n in pairs(free) do
            if n > 0 and not need[itemID] then override[itemID] = zeroFree and 0 or freeAverage(itemID, n) end
        end
    end

    -- The DP charges a learn cost per contiguous run. Re-solve with the chosen learn set marked
    -- as known and charge each once; this lets the path switch back and forth between them.
    local learnSet, learnSum = {}, 0
    for _, st in ipairs(steps) do
        if st.learnCost > 0 and not learnSet[st.recipe] then
            learnSet[st.recipe] = true; learnSum = learnSum + st.learnCost
        end
    end
    if learnSum > 0 then
        -- Mark the chosen recipes as free for the re-solve, then put back exactly what they were
        -- (a known recipe can still have a one-time cost: a tool you don't have).
        local saved = {}
        for r in pairs(learnSet) do
            saved[r] = { r.learned, r.toolCost, O.oneTimeCost(r) }
            r.learned, r.toolCost = true, nil
        end
        ctx.unitOverride = override
        local steps2, total2 = solve(ctx, unitCost)
        ctx.unitOverride = nil
        for r, s in pairs(saved) do r.learned, r.toolCost = s[1], s[2] end
        if steps2 and total2 + learnSum < total - 1e-6 then
            for _, st in ipairs(steps2) do
                if learnSet[st.recipe] then
                    learnSet[st.recipe] = nil
                    st.learnCost = saved[st.recipe][3]
                    st.cost = st.cost + st.learnCost
                end
            end
            steps, total = steps2, total2 + learnSum
            need = shoppingList(steps, unitCost)
        end
    end
    local _, crafted = shoppingList(steps, unitCost)

    -- Shopping list with what it really costs to buy the quantity (walking the AH order book).
    local shopping, cash = {}, 0
    for itemID, qty in pairs(need) do
        local n = math.ceil(qty - 1e-9)
        local owned = (ctx.owned and ctx.owned[itemID]) or 0
        local unit, src = unitCost(itemID)
        local buy = math.max(n - owned, 0)
        local lineCost = 0
        if buy > 0 then
            if src == "gather" then lineCost = 0 -- costs time, not gold
            elseif src == "vendor" then lineCost = ctx.vendorBuy(itemID) * buy
            else lineCost = (ctx.price and ctx.price(itemID, buy)) or unit * buy end
        end
        cash = cash + lineCost
        shopping[#shopping + 1] = {
            itemID = itemID, needed = n, owned = owned, buy = buy, source = src,
            lineCost = lineCost, unitCost = (src ~= "gather" and buy > 0) and lineCost / buy or unit,
        }
    end
    table.sort(shopping, function(a, b) return a.lineCost > b.lineCost end) -- biggest spend first

    -- Intermediates to craft first (e.g. cured hides), and what is spent on learning recipes.
    local intermediates = {}
    for r, n in pairs(crafted) do intermediates[#intermediates + 1] = { recipe = r, crafts = math.ceil(n - 1e-9) } end
    table.sort(intermediates, function(a, b) return (a.recipe.name or "") < (b.recipe.name or "") end)
    local learnTotal, back = 0, 0
    for _, st in ipairs(steps) do
        learnTotal = learnTotal + (st.learnCost or 0)
        local r = st.recipe
        st.sellBack = r.productID and recovery(ctx, r.productID) * (r.productQty or 1) * st.expectedCrafts or 0
        back = back + st.sellBack

        -- Per-step detail: each reagent per craft and how it is obtained, then the raw materials to
        -- buy and intermediates to craft for this step alone (priced for this step's quantity).
        st.reagents = {}
        for _, rg in ipairs(r.reagents) do
            local unit, src, via = unitCost(rg[1])
            st.reagents[#st.reagents + 1] = { itemID = rg[1], perCraft = rg[2], total = math.ceil(rg[2] * st.expectedCrafts - 1e-9),
                unitCost = unit, source = src, via = via }
        end
        local sNeed, sCrafted = shoppingList({ st }, unitCost)
        st.materials, st.cash = {}, 0
        for itemID, qty in pairs(sNeed) do
            local n = math.ceil(qty - 1e-9)
            local unit, src = unitCost(itemID)
            local cost = src == "gather" and 0 or src == "vendor" and ctx.vendorBuy(itemID) * n
                or (ctx.price and ctx.price(itemID, n)) or unit * n
            st.cash = st.cash + cost
            st.materials[#st.materials + 1] = { itemID = itemID, qty = n, source = src, lineCost = cost, unitCost = cost / n }
        end
        table.sort(st.materials, function(a, b) return a.lineCost > b.lineCost end)
        st.intermediates = {}
        for ir, n in pairs(sCrafted) do st.intermediates[#st.intermediates + 1] = { recipe = ir, crafts = math.ceil(n - 1e-9) } end
        table.sort(st.intermediates, function(a, b) return (a.recipe.name or "") < (b.recipe.name or "") end)
    end

    local missingList = {}
    for itemID in pairs(missing) do missingList[#missingList + 1] = itemID end
    table.sort(missingList)

    -- totalCost: net cost the path was optimised on. cash + learnTotal: gold you spend up front.
    -- sellBack: what selling the crafted items returns (vendor price, or AH share if resale is on).
    return { ok = true, steps = steps, totalCost = total, shopping = shopping, missing = missingList, dist = dist,
        intermediates = intermediates, cash = cash, learnTotal = learnTotal, sellBack = back }
end

-- Plans twice when you own free stock: once counting it as free from the start (best when it
-- covers what a route needs) and once pricing it as limited (so a few owned units can't make a
-- whole route look free), and keeps the plan that really costs less: gold spent, net of free
-- units, plus recipes, minus what vendoring returns.
function O.optimize(ctx)
    local free = ctx.free or (ctx.ownedFree == true and ctx.owned) or {}
    local a = optimizeWith(ctx, true)
    if not next(free) or not a.ok then
        if a.ok or not next(free) then return a end
    else
        -- The second pass only matters when this plan leans on owned items that don't cover what it
        -- needs (it priced them at 0 while the rest must be bought). Otherwise it's already right.
        local partial = false
        for _, sh in ipairs(a.shopping or {}) do
            local f = free[sh.itemID] or 0
            if f > 0 and sh.needed > f then partial = true; break end
        end
        if not partial then
            for _, it in ipairs(a.intermediates or {}) do
                for _, rg in ipairs(it.recipe.reagents or {}) do
                    local f = free[rg[1]] or 0
                    if f > 0 and rg[2] * it.crafts > f then partial = true; break end
                end
                if partial then break end
            end
        end
        if not partial then return a end
    end
    local b = optimizeWith(ctx, false)
    -- Third candidate: the route you'd pick owning nothing, with your stock then taken off its
    -- shopping list. One price per item can't say "free up to what you own, full price after", so a
    -- route that needs far more than you own can look cheap in a and b; this one never does.
    local c = optimizeWith(ctx, "market")
    if c.ok and (not b.ok or not a.ok) then
        if not b.ok then b = c else a = c end
        c = nil
    end
    if not a.ok then return b end
    if not b.ok then return a end
    -- gathered materials cost no gold but are not free: count them at their gather value
    local function real(r)
        local g = 0
        for _, sh in ipairs(r.shopping or {}) do
            if sh.source == "gather" then g = g + (sh.unitCost or 0) * (sh.buy or 0) end
        end
        return (r.cash or 0) + (r.learnTotal or 0) - (r.sellBack or 0) + g
    end
    local best = real(b) < real(a) and b or a
    if c and c.ok and real(c) < real(best) then best = c end
    return best
end

-- ---------- what is still missing for N crafts, given what is in the bags ----------
-- Top-down: each reagent comes out of the bags first; a shortfall of a crafted reagent (one of
-- `intermediates`, e.g. Cured Light Hide) becomes crafts of it, and only those crafts need raw
-- materials. Returns short[itemID] (to buy), used[itemID] (taken from bags), craftsLeft[recipe].
function O.remaining(recipe, crafts, intermediates, bagCount)
    local craftVia = {}
    for _, it in ipairs(intermediates or {}) do
        if it.recipe.productID then craftVia[it.recipe.productID] = it.recipe end
    end
    local avail, used, short, craftsLeft = {}, {}, {}, {}
    local function expand(itemID, qty)
        if avail[itemID] == nil then avail[itemID] = bagCount(itemID) or 0 end
        local take = math.min(avail[itemID], qty)
        avail[itemID] = avail[itemID] - take
        used[itemID] = (used[itemID] or 0) + take
        local rest = qty - take
        if rest <= 0 then return end
        local via = craftVia[itemID]
        if via then
            local c = math.ceil(rest / (via.productQty or 1) - 1e-9)
            craftsLeft[via] = (craftsLeft[via] or 0) + c
            for _, rg in ipairs(via.reagents) do expand(rg[1], rg[2] * c) end
        else
            short[itemID] = (short[itemID] or 0) + rest
        end
    end
    for _, rg in ipairs(recipe.reagents) do expand(rg[1], rg[2] * crafts) end
    return short, used, craftsLeft
end

-- ---------- batch size (batch mode, Do it tab) ----------
-- A batch is fixed once set. rec (remembered per step, or nil), fresh = crafts the gold allows now
-- (learn cost included), covered = crafts the bags hold materials for, crafts = crafts left in the
-- step. Returns crafts for this batch and the updated rec:
--   * new batch: sized from the gold, or adopts the bags if they already hold >= 85% of that;
--   * while buying (not all in the bags yet): the same size, so the list shows what's missing;
--   * once all bought: what the bags cover, counting down as you craft;
--   * used up (bags empty again): the next batch is sized fresh.
function O.batchSize(rec, fresh, covered, crafts)
    if rec and rec.ready and covered == 0 then rec = nil end
    if not rec then
        local n = (covered > 0 and covered >= math.floor(fresh * 0.85)) and covered or fresh
        rec = { n = n }
    end
    if covered >= rec.n then rec.ready = true end
    local size = rec.ready and math.max(1, math.min(crafts, covered)) or math.min(crafts, rec.n)
    return size, rec
end

-- ---------- fitting a plan to the gold you have ----------
-- Finds the furthest skill (<= target) reachable within `budget`, with the cheapest plan to get there.
-- mode "batch":   counts the net cost (gold spent minus what vendoring the crafted items returns), as
--                 when you buy for a batch, craft, vendor, and buy again.
-- mode "upfront": counts all gold spent with nothing sold back; the plan then minimises spending.
-- makeCtx(target) returns a fresh optimizer ctx. Returns result, reachedSkill, limited, fullCost
-- (result nil if not even one point is affordable; fullCost = cost of reaching target, if a path exists).
function O.planCost(res, mode)
    local spend = res.cash + res.learnTotal
    return mode == "upfront" and spend or spend - res.sellBack
end

function O.fitBudget(makeCtx, rank, target, budget, mode)
    local function run(t)
        local c = makeCtx(t)
        if mode == "upfront" then c.vendorSell, c.resaleFactor = nil, 0 end
        return O.optimize(c)
    end
    local full = run(target)
    local fullCost = full.ok and O.planCost(full, mode) or nil
    if full.ok and fullCost <= budget then return full, target, false, fullCost end

    -- Per-level cheapest costs from the full run give a first estimate (bulk prices there are for
    -- the full path's quantities, so slightly pessimistic); confirm with real plans and adjust.
    local d, s = full.dist or {}, rank
    for lvl = rank + 1, target do
        if d[lvl] and d[lvl] <= budget then s = lvl end
    end
    for _ = 1, 8 do
        if s <= rank then break end
        local r = run(s)
        if r.ok and O.planCost(r, mode) <= budget then
            local best, bestS = r, s
            for up = s + 1, math.min(target - 1, s + 3) do -- the estimate may be a little low
                local r2 = run(up)
                if r2.ok and O.planCost(r2, mode) <= budget then best, bestS = r2, up else break end
            end
            return best, bestS, true, fullCost
        end
        s = rank + math.floor((s - rank) * 0.85)
    end
    return nil, rank, true, fullCost
end

-- ---------- scan pruning ----------
-- Which recipes cannot be part of a cheap path, judged from the prices known so far?
-- Each recipe gets a LOWER bound per craft (unknown reagents count as free, intermediates as the
-- cheaper of buying and crafting). Fully priced recipes give a known cost per skill point at each
-- level. A recipe is dominated when, at every level it could give points in [skill, target), its
-- lower bound per point is above `factor` x the best known cost there. Items only such recipes use
-- need no scan. Unknown product value could still make a recipe cheap through resale, so those
-- recipes need twice the margin.
-- ctx: skill, target, recipes, price(id, qty), vendorBuy(id), vendorSell(id), owned, ownedFree,
--      resaleFactor. Returns { [recipe] = true }.
function O.dominated(ctx, factor)
    factor = factor or 1.5
    local s0, target = ctx.skill, ctx.target
    local makers = {}
    for _, r in ipairs(ctx.recipes) do
        if r.learned and r.productID then
            makers[r.productID] = makers[r.productID] or {}
            table.insert(makers[r.productID], r)
        end
    end

    -- known unit price (nil if unknown) and lower bound (0 if unknown)
    local memo, active = {}, {}
    local function unit(id)
        local m = memo[id]
        if m then return m[1], m[2] end
        if active[id] then return nil, 0 end
        active[id] = true
        local known
        local free = ctx.free or (ctx.ownedFree == true and ctx.owned) or {}
        if (free[id] or 0) > 0 then known = 0 end
        local ah = ctx.price and ctx.price(id, 1)
        local vb = ctx.vendorBuy and ctx.vendorBuy(id)
        for _, v in ipairs({ ah or false, vb or false }) do
            if v and (not known or v < known) then known = v end
        end
        local lb = known or 0
        for _, m2 in ipairs(makers[id] or {}) do
            local cKnown, cLb = 0, 0
            for _, rg in ipairs(m2.reagents) do
                local k, l = unit(rg[1])
                cKnown = (cKnown and k) and cKnown + k * rg[2] or nil
                cLb = cLb + l * rg[2]
            end
            local q = m2.productQty or 1
            if cKnown and (not known or cKnown / q < known) then known = cKnown / q end
            lb = math.min(lb, cLb / q)
        end
        active[id] = nil
        memo[id] = { known, lb }
        return known, lb
    end

    local best = {}
    for s = s0, target - 1 do best[s] = INF end
    local bounds = {}
    for _, r in ipairs(ctx.recipes) do
        local known, lb = 0, 0
        for _, rg in ipairs(r.reagents) do
            local k, l = unit(rg[1])
            known = (known and k) and known + k * rg[2] or nil
            lb = lb + l * rg[2]
        end
        local productKnown = true
        local rec = 0
        if r.productID then
            local ah = ctx.price and ctx.price(r.productID, 1)
            productKnown = ah ~= nil or (ctx.resaleFactor or 0.5) == 0
            rec = recovery(ctx, r.productID) * (r.productQty or 1)
        end
        local learn = O.oneTimeCost(r)
        if r.noLevel then learn = INF end -- never a leveling step, so never the yardstick
        bounds[r] = { lb = math.max(lb - rec, 0), margin = productKnown and factor or factor * 2 }

        -- Fully priced and already known (or free to learn): a cost per point you can always get.
        -- Recipes that still cost something to learn are not used as the yardstick: how many points
        -- their learn cost is spread over depends on the path, so it could understate their cost.
        if known and learn == 0 then
            local net = math.max(known - rec, 0) + CRAFT_TIEBREAK + (ctx.effort or 0)
            local lo, hi = math.max(s0, r.minSkill or 0), math.min(target, r.gray) - 1
            for s = lo, hi do
                local p = O.chance(r, s)
                if p > 0 then
                    local c = net / (p * (r.skillUps or 1))
                    if c < best[s] then best[s] = c end
                end
            end
        end
    end

    local out = {}
    for _, r in ipairs(ctx.recipes) do
        local b = bounds[r]
        local useful, beatenEverywhere = false, true
        for s = math.max(s0, r.minSkill or 0), math.min(target, r.gray) - 1 do
            local p = O.chance(r, s)
            if p > 0 then
                useful = true
                local perPoint = (b.lb + CRAFT_TIEBREAK + (ctx.effort or 0)) / (p * (r.skillUps or 1))
                if not (perPoint > b.margin * best[s]) then beatenEverywhere = false; break end
            end
        end
        if not useful or beatenEverywhere or r.noLevel then out[r] = true end
    end
    return out
end

return O
