-- ProfPath recipes: player's professions, learned recipes, and normalized recipe lists.
local _, ns = ...
local R = {}
ns.Recipes = R

local function charKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

function R.char()
    local key = charKey()
    ProfPathDB.chars[key] = ProfPathDB.chars[key] or { learned = {}, live = {}, skill = {} }
    return ProfPathDB.chars[key]
end

-- Several skill lines share a name (e.g. 165 and 2945 "Leatherworking"); use the one with recipes.
local recipeCount
local function countRecipes()
    if recipeCount then return recipeCount end
    recipeCount = {}
    for _, d in pairs(ns.Data.recipes) do recipeCount[d[1]] = (recipeCount[d[1]] or 0) + 1 end
    return recipeCount
end

local function skillLineByName(name)
    local best, bestN = nil, 0
    for id, n in pairs(ns.Data.skillLines) do
        local c = countRecipes()[id] or 0
        if n == name and c > bestN then best, bestN = id, c end
    end
    return best
end

local function hasRecipes(skillLine) return skillLine and (countRecipes()[skillLine] or 0) > 0 end
function R.invalidateCounts() recipeCount = nil end -- after ns.Data changes (tests)

-- List of { name, skillLine, rank, max } for the player's crafting professions.
function R.professions()
    local list, seen = {}, {}
    local function add(name, rank, max, skillLine)
        if not name or seen[name] then return end
        if not hasRecipes(skillLine) then skillLine = skillLineByName(name) end
        local hasLive = next(R.char().live[name] or {}) ~= nil
        if not (hasRecipes(skillLine) or hasLive) then return end -- gathering, weapon skills, etc.
        seen[name] = true
        list[#list + 1] = { name = name, skillLine = skillLine, rank = rank, max = max }
    end
    if GetProfessions and GetProfessionInfo then
        -- GetProfessions returns nil for slots you don't have (e.g. 1, 2, nil, nil, nil, 6), so check
        -- every slot instead of stopping at the first gap.
        local res = { pcall(GetProfessions) }
        if res[1] then
            for i = 2, 8 do
                local idx = res[i]
                if idx then
                    local name, _, rank, max, _, _, skillLine = GetProfessionInfo(idx)
                    add(name, rank, max, skillLine)
                end
            end
        end
    end
    if #list == 0 and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            if not isHeader then add(name, rank, max) end
        end
    end
    -- Last resort: whatever the profession window last reported.
    for name, s in pairs(R.char().skill) do add(name, s.rank, s.max, s.skillLine) end
    table.sort(list, function(x, y) return x.name < y.name end)
    return list
end

-- ---------- live capture from the profession window ----------

local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

local function currentLine()
    local T = C_TradeSkillUI
    if T.GetBaseProfessionInfo then
        local ok, info = pcall(T.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionName then
            return info.professionName, info.skillLevel, info.maxSkillLevel, info.professionID
        end
    end
    if T.GetTradeSkillLine then
        local ok, id, name, rank, max = pcall(T.GetTradeSkillLine)
        if ok and name then return name, rank, max, id end
    end
end

local function schematic(id)
    local T = C_TradeSkillUI
    if not T.GetRecipeSchematic then return end
    local ok, s = pcall(T.GetRecipeSchematic, id, false)
    if not ok or type(s) ~= "table" then return end
    local reagents = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        if r and r.itemID and (slot.quantityRequired or 0) > 0 then
            reagents[#reagents + 1] = { r.itemID, slot.quantityRequired }
        end
    end
    return reagents, s.outputItemID, s.quantityMin
end

function R.captureWindow()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    local name, rank, max, lineID = currentLine()
    if not name then return end
    local c = R.char()
    local line = hasRecipes(lineID) and lineID or skillLineByName(name)
    if not line then return end -- gathering profession window (e.g. Skinning): nothing to craft
    c.skill[name] = { rank = rank, max = max, skillLine = line, t = time() }
    -- You just opened this profession's window: show it in ProfPath too (once per opening).
    if R.switchOnOpen then c.selectedProf, R.switchOnOpen = name, false end
    local learned, live = {}, {}
    local mismatches = 0
    -- GetAllRecipeIDs also returns recipes of other professions; keep only this skill line's.
    local function inLine(id)
        local d = ns.Data.recipes[id]
        if d then return d[1] == line end
        if T.IsRecipeInSkillLine then
            local ok, yes = pcall(T.IsRecipeInSkillLine, id, lineID)
            return ok and yes
        end
        return false
    end
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local ok, info = pcall(T.GetRecipeInfo, id)
        if ok and info and not info.isGatheringRecipe and inLine(id) then
            if info.learned then learned[id] = true end
            local color = DIFF[info.relativeDifficulty]
            local data = ns.Data.recipes[id]
            if data and color and rank then
                local r = { minSkill = data[2], yellow = data[3], gray = data[4] }
                local expect = rank >= r.gray and "gray" or rank >= (r.yellow + r.gray) / 2 and "green"
                    or rank >= r.yellow and "yellow" or "orange"
                if expect ~= color then mismatches = mismatches + 1 end
            elseif not data and color then
                local reagents, product, qty = schematic(id)
                if reagents and #reagents > 0 then
                    live[id] = { name = info.name, color = color, atSkill = rank, reagents = reagents,
                        productID = product, productQty = qty or 1, learned = info.learned }
                end
            end
        end
    end
    c.learned[name] = learned
    c.live[name] = live
    c.mismatches = c.mismatches or {}
    c.mismatches[name] = mismatches
    if ns.requestRecalc then ns.requestRecalc() end
end

-- ---------- normalized recipes for the optimizer ----------

-- Rough thresholds from a single colour reading, for recipes missing from the static data.
local function estimate(color, s)
    if color == "orange" then return s + 5, s + 25 end
    if color == "yellow" then return s, s + 15 end
    if color == "green" then return s - 10, s + 5 end
    return s - 20, s
end

-- ---------- profession ranks ----------
-- Classic values; replaced by what the trainer shows once it lists the rank (Capture.lua).
R.RANKS = {
    { name = "Apprentice", cap = 75, req = 1, level = 5, cost = 10 },
    { name = "Journeyman", cap = 150, req = 50, level = 10, cost = 500 },
    { name = "Expert", cap = 225, req = 125, level = 20, cost = 10000 },
    { name = "Artisan", cap = 300, req = 200, level = 35, cost = 50000 },
}

-- Ranks to train to plan up to `want`, in order, and the highest cap reachable. Stops at a rank
-- your character level does not allow yet. Each entry: name, cap, req (skill), level, cost, estimated.
function R.rankPath(prof, want, playerLevel)
    local cap = prof.max or 75
    local list, blocked = {}, nil
    local captured = ProfPathDB.ranks and ProfPathDB.ranks[prof.name] or {}
    for _, rk in ipairs(R.RANKS) do
        if rk.cap > cap and want > cap then
            local c = captured[rk.name]
            local e = { name = rk.name, cap = rk.cap, req = c and c.req or rk.req, level = c and c.level or rk.level,
                cost = c and c.cost or rk.cost, estimated = c == nil }
            if playerLevel and playerLevel < e.level then blocked = e; break end
            list[#list + 1] = e
            cap = rk.cap
        end
    end
    return list, cap, blocked
end

-- ---------- where the trainers are ----------
-- World position of a map point: continent and yards, so distances can be compared.
local function worldPos(mapID, x, y)
    if not (mapID and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not cont or not pos then return nil end
    local wx, wy = pos:GetXY()
    return cont, wx, wy
end

local function playerWorldPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not p then return nil end
    local x, y = p:GetXY()
    return worldPos(map, x, y)
end

local RANK_CAP = {}
for _, rk in ipairs(R.RANKS) do RANK_CAP[rk.name] = rk.cap end

-- All known trainers for a profession on your side: the built-in list (Data/Trainers.lua, from
-- Wowhead) merged with trainers you have opened (what you saw in game wins).
local function knownTrainers(profName)
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local side = faction == "Alliance" and 1 or faction == "Horde" and 2 or nil
    local out, byKey = {}, {}
    for _, row in ipairs(ns.TrainerData and ns.TrainerData[profName] or {}) do
        if not side or row[4] == 0 or row[4] == side then
            local loc = { npc = row[2], title = row[3], mapID = row[5], zone = row[6], x = row[7] / 100, y = row[8] / 100,
                cap = row[9], static = true }
            byKey[row[2]] = loc
            out[#out + 1] = loc
        end
    end
    for _, seen in pairs(ProfPathDB.trainerLocs and ProfPathDB.trainerLocs[profName] or {}) do
        if not (faction and seen.faction and seen.faction ~= faction) then
            local loc = byKey[seen.npc]
            if loc then -- same NPC: keep the list's title/cap, add what we saw
                loc.ranks, loc.visited = seen.ranks, true
                if seen.x then loc.mapID, loc.x, loc.y, loc.zone = seen.mapID, seen.x, seen.y, seen.zone end
            else
                local copy = {}
                for k, v in pairs(seen) do copy[k] = v end
                copy.visited = true
                out[#out + 1] = copy
            end
        end
    end
    return out
end

-- Trainers for a profession (and rank, if given), best first:
--   * for a rank: trainers seen teaching it in game, then those whose title says they teach it;
--     trainers whose title shows a lower rank are left out;
--   * nearest on your continent first, then everything else.
-- Returns a list of { loc, dist } (dist in yards, nil if on another continent or unknown).
function R.trainersFor(profName, rankName)
    local need = rankName and RANK_CAP[rankName]
    local pc, px, py = playerWorldPos()
    local list = {}
    for _, loc in ipairs(knownTrainers(profName)) do
        local seenTeaches = rankName and loc.ranks and loc.ranks[rankName]
        local titleOk = not need or (loc.cap or 0) == 0 or loc.cap >= need
        if seenTeaches or titleOk then
            local c, wx, wy = worldPos(loc.mapID, loc.x, loc.y)
            local dist = (pc and c == pc) and math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2) or nil
            local tier = seenTeaches and 0 or (need and (loc.cap or 0) >= need) and 1 or 2
            list[#list + 1] = { loc = loc, dist = dist, tier = tier }
        end
    end
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
        if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
        return (a.loc.zone or "") .. a.loc.npc < (b.loc.zone or "") .. b.loc.npc
    end)
    return list
end

-- Best trainer: loc, distance.
function R.trainerFor(profName, rankName)
    local first = R.trainersFor(profName, rankName)[1]
    if first then return first.loc, first.dist end
end

function R.trainerText(loc, dist)
    if not loc then return nil end
    local s = loc.x and loc.y and ("%s, %s (%.1f, %.1f)"):format(loc.npc, loc.zone, loc.x * 100, loc.y * 100)
        or ("%s, %s"):format(loc.npc, loc.zone)
    if dist then
        s = s .. (dist < 60 and ", right here" or (", about %d yd away"):format(math.floor(dist / 10 + 0.5) * 10))
    end
    return s
end

-- Map pin on a trainer: TomTom if loaded, otherwise the game's own waypoint.
function R.waypoint(loc)
    if not (loc and loc.mapID and loc.x and loc.y) then return false end
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, loc.mapID, loc.x, loc.y, { title = loc.npc, persistent = false })
        return true
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.mapID, loc.x, loc.y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        return ok
    end
    return false
end

-- ---------- trainer recipes the trainer has not shown yet ----------
-- Trainers only list recipes up to your current rank, so recipes past the cap have no captured
-- cost. Required skill: from your trainer data, gear is learnable at yellow minus the yellow-gray
-- gap (Light Leather Pants: yellow 100, gray 130, needs 70); materials (gap 10 or less) at yellow.
local function estimateReq(r)
    local gap = r.gray - r.yellow
    return gap <= 10 and r.yellow or (r.yellow - gap)
end

-- Cost: from captured trainer costs near that skill; above the highest captured skill, scaled
-- up with the square of the skill (trainer prices climb steeply).
local function costModel(prof)
    local rows, byName = {}, ProfPathDB.trainer[prof.name] or {}
    for _, v in pairs(byName) do
        if type(v) == "table" and v.req and v.cost and v.cost > 0 then rows[#rows + 1] = v end
    end
    local maxReq = 0
    for _, v in ipairs(rows) do maxReq = math.max(maxReq, v.req) end
    local function median(list)
        if #list == 0 then return nil end
        table.sort(list)
        return list[math.floor((#list + 1) / 2)]
    end
    return function(req)
        if #rows == 0 then return math.max(100, math.floor(2000 * (req / 150) ^ 2)) end
        if req <= maxReq then
            local near = {}
            for _, v in ipairs(rows) do if math.abs(v.req - req) <= 15 then near[#near + 1] = v.cost end end
            local m = median(near)
            if m then return m end
        end
        local top = {}
        for _, v in ipairs(rows) do if v.req >= maxReq - 10 then top[#top + 1] = v.cost end end
        return math.floor(median(top) * math.max(1, (req / math.max(maxReq, 1)) ^ 2))
    end
end

-- Learn cost and required skill for an unlearned recipe: recipe item (AH or vendor price, item's
-- required skill) or trainer (captured cost and requirement). Cost nil = unknown.
local function learnInfo(prof, id, name)
    local ri = ns.Data.recipeItems[id]
    local t = ProfPathDB.trainer[prof.name]
    local te = t and t[name]
    if type(te) == "number" then te = { cost = te } end -- older saved format
    local cost, req, source
    if te then cost, req, source = te.cost, te.req, { kind = "trainer" } end
    if ri then
        local v = ns.Prices.vendorBuy(ri[1])
        local ah = ns.Prices.ahUnit(ri[1])
        local itemCost = (v and ah) and math.min(v, ah) or v or ah
        if itemCost and (not cost or itemCost < cost) then
            cost, req = itemCost, ri[2]
            source = { kind = "item", itemID = ri[1], from = (v and (not ah or v <= ah)) and "vendor" or "AH" }
        end
        req = req or ri[2]
    end
    return cost, req, source
end

-- ---------- specializations and tools ----------

-- Do you know this spell (a specialization such as Tribal Leatherworking or Armorsmith)?
local function knowsSpell(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    return false
end
R.knowsSpell = knowsSpell

local function inBags(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and (count(itemID) or 0) > 0
end

-- Cheapest way to get one of an item: vendor, auction house, or crafting it from a recipe in the
-- data (one level: its materials at vendor/AH prices). Returns cost, "vendor"|"AH"|"craft", or nil.
local makers -- [itemID] = recipe data rows that create it (built once)
local function itemCost(itemID)
    if not makers then
        makers = {}
        for _, d in pairs(ns.Data.recipes) do
            if d[5] then makers[d[5]] = makers[d[5]] or {}; table.insert(makers[d[5]], d) end
        end
    end
    local best, how
    local v = ns.Prices.vendorBuy(itemID)
    if v then best, how = v, "vendor" end
    local ah = ns.Prices.ahUnit(itemID)
    if ah and (not best or ah < best) then best, how = ah, "AH" end
    for _, d in ipairs(makers[itemID] or {}) do
        local c, rg = 0, d[7]
        for i = 1, #rg, 2 do
            local u = ns.Prices.vendorBuy(rg[i]) or ns.Prices.ahUnit(rg[i])
            if not u then c = nil; break end
            c = c + u * rg[i + 1]
        end
        if c and (not best or c / (d[6] or 1) < best) then best, how = c / (d[6] or 1), "craft" end
    end
    return best, how
end

-- Per tool category: do you carry one, and what does the cheapest one cost? Cached per build
-- (many recipes share a tool), cleared at the start of every R.build.
local toolCache = {}
local function toolStatus(c)
    local s = toolCache[c]
    if s then return s end
    local items = ns.Data.toolItems and ns.Data.toolItems[c] or {}
    s = { name = ns.Data.toolNames and ns.Data.toolNames[c] or "a tool" }
    for _, id in ipairs(items) do if inBags(id) then s.have = true end end
    if not s.have then
        for _, id in ipairs(items) do
            local cost, how = itemCost(id)
            if cost and (not s.cost or cost < s.cost) then s.cost, s.how, s.itemID = cost, how, id end
        end
    end
    toolCache[c] = s
    return s
end

-- For a recipe's required tools: which you lack, and what getting them costs.
-- Returns missing = { {name, cost, how, itemID}, ... }, totalCost (nil if one has no known cost).
function R.toolsNeeded(recipeID)
    local cats = ns.Data.tools and ns.Data.tools[recipeID]
    if not cats then return nil end
    local missing, total = {}, 0
    for _, c in ipairs(cats) do
        local s = toolStatus(c)
        if not s.have then
            missing[#missing + 1] = s
            total = (total and s.cost) and total + s.cost or nil
        end
    end
    if #missing == 0 then return nil end
    return missing, total
end

-- Returns recipes, info = { unknownLearn = n, estimated = n, noLearnedData = bool }
function R.build(prof)
    local c = R.char()
    local learned = c.learned[prof.name]
    local info = { unknownLearn = 0, estimated = 0, estimatedLearn = 0, specSkipped = 0, cooldownSkipped = 0,
        toolSkipped = 0, noLearnedData = learned == nil,
        trainerSeen = ProfPathDB.trainerSeen[prof.name] ~= nil, mismatches = c.mismatches and c.mismatches[prof.name] }
    learned = learned or {}
    local list = {}
    local estCost = costModel(prof)
    toolCache = {} -- bags and prices may have changed since the last build
    for id, d in pairs(ns.Data.recipes) do
        -- Keep learned gray recipes: they can still craft intermediates for other recipes.
        if d[1] == prof.skillLine and (d[4] > (prof.rank or 0) or learned[id]) then
            local reagents = {}
            local rg = d[7]
            for i = 1, #rg, 2 do reagents[#reagents + 1] = { rg[i], rg[i + 1] } end
            local r = { id = id, name = d[8], minSkill = d[2], yellow = d[3], gray = d[4],
                productID = d[5], productQty = d[6] or 1, reagents = reagents, learned = learned[id] == true }
            local ri = ns.Data.recipeItems[id]
            local skip
            -- Long cooldown (transmutes, Mooncloth): never a leveling step; still a known producer.
            if ns.Data.cooldown and ns.Data.cooldown[id] then
                r.noLevel, r.cooldown = true, ns.Data.cooldown[id]
                if not r.learned then skip = true; info.cooldownSkipped = info.cooldownSkipped + 1 end
            end
            -- Specialization recipe you can't learn (e.g. Tribal Leatherworking without that spec).
            if not skip and not r.learned and ri and (ri[3] or 0) ~= 0 and not knowsSpell(ri[3]) then
                skip = true
                info.specSkipped = info.specSkipped + 1
            end
            -- Starter recipes come with the profession.
            if not skip and not r.learned and ns.Data.autoLearn and ns.Data.autoLearn[id] then
                r.learned = true
            end
            -- Tools you don't carry: the cheapest way to get them is a one-time cost of this recipe.
            if not skip then
                local missing, toolCost = R.toolsNeeded(id)
                if missing then
                    if toolCost then
                        r.toolCost, r.toolsMissing = toolCost, missing
                    else
                        skip = true
                        info.toolSkipped = info.toolSkipped + 1
                    end
                end
            end
            if skip then r = nil end
            if r and not r.learned then
                local cost, req, source = learnInfo(prof, id, r.name)
                -- No recipe item and no trainer entry: a trainer recipe the trainer could not show yet
                -- (needs a higher rank, or the trainer was never visited). Estimate it. If the trainer
                -- was visited and should have listed it (within your current cap), it is a drop or
                -- quest recipe: leave it unknown.
                if not cost and not ns.Data.recipeItems[id] then
                    local er = estimateReq(r)
                    if not info.trainerSeen or er > (prof.max or 0) then
                        cost, req = estCost(er), er
                        source = { kind = "trainer", estimated = true }
                        info.estimatedLearn = info.estimatedLearn + 1
                    end
                end
                r.learnCost, r.learnSource, r.learnReq = cost, source, req
                if req and req > r.minSkill then r.minSkill = req end
                if not cost then info.unknownLearn = info.unknownLearn + 1 end
            end
            if r then list[#list + 1] = r end
        end
    end
    for id, l in pairs(c.live[prof.name] or {}) do
        if not ns.Data.recipes[id] and l.color ~= "gray" then
            local y, g = estimate(l.color, l.atSkill or prof.rank or 1)
            local r = { id = id, name = l.name, minSkill = 0, yellow = y, gray = g, productID = l.productID,
                productQty = l.productQty, reagents = l.reagents, learned = l.learned, estimated = true }
            if not r.learned then
                local cost, req, source = learnInfo(prof, id, r.name)
                r.learnCost, r.minSkill, r.learnSource, r.learnReq = cost, req or 0, source, req
                if not cost then info.unknownLearn = info.unknownLearn + 1 end
            end
            info.estimated = info.estimated + 1
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end) -- deterministic tie-breaks
    return list, info
end

-- Items worth pricing: reagents, products and recipe items of recipes that can give points
-- between rank and target, plus reagents of learned recipes that make one of those reagents
-- (intermediates such as cured hides), followed down the chain.
function R.itemsToPrice(recipes, rank, target)
    local set, out = {}, {}
    local function add(id) if id and not set[id] then set[id] = true; out[#out + 1] = id end end
    local makers = {}
    for _, r in ipairs(recipes) do
        if r.learned and r.productID then makers[r.productID] = makers[r.productID] or {}; table.insert(makers[r.productID], r) end
    end
    -- users[itemID] = recipes (that can give points) whose cost depends on the item
    local users = {}
    local function use(id, root)
        if not id then return end
        add(id)
        users[id] = users[id] or {}
        users[id][#users[id] + 1] = root
    end
    local function addReagents(r, root, seen)
        if seen[r] then return end
        seen[r] = true
        for _, rg in ipairs(r.reagents) do
            use(rg[1], root)
            for _, m in ipairs(makers[rg[1]] or {}) do addReagents(m, root, seen) end
        end
    end
    for _, r in ipairs(recipes) do
        local ri = ns.Data.recipeItems[r.id]
        -- Unlearned with no trainer cost and no recipe item: cannot be learned, so not worth scanning.
        local learnable = r.learned or r.learnCost or ri
        local relevant = learnable and r.gray > (rank or 0) and (r.minSkill or 0) < (target or math.huge)
        if relevant then
            addReagents(r, r, {})
            use(r.productID, r)
            if not r.learned and ri then use(ri[1], r) end
        end
    end
    -- Scan items of learned recipes first (they set the price bar others are pruned against),
    -- then items used by many recipes.
    local learnedItem = {}
    for id, us in pairs(users) do
        for _, r in ipairs(us) do if r.learned then learnedItem[id] = true end end
    end
    table.sort(out, function(a, b)
        if (learnedItem[a] or false) ~= (learnedItem[b] or false) then return learnedItem[a] == true end
        local na, nb = #(users[a] or {}), #(users[b] or {})
        if na ~= nb then return na > nb end
        return a < b
    end)
    return out, users
end
