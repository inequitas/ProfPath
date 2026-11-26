-- Loads every addon file in .toc order against stubbed WoW APIs and runs one full recalculation.
-- Run from the ProfPath folder:  lua tests/wow_sim.lua
local unpack = table.unpack or unpack

-- ---- stubs ----
local frames, events = {}, {}
local function newFrame()
    local f = { scripts = {}, shown = true } -- like WoW: new frames are shown
    function f:RegisterEvent(e) events[e] = events[e] or {}; table.insert(events[e], self) end
    function f:UnregisterEvent(e) end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture()
        return setmetatable({}, { __index = function() return function() end end })
    end
    function f:CreateFontString()
        local fs = {}
        function fs:SetText(t) self.text = t end
        function fs:GetStringHeight() return 100 end
        return setmetatable(fs, { __index = function() return function() end end })
    end
    frames[#frames + 1] = f
    return setmetatable(f, { __index = function() return function() end end })
end
local function fire(e, ...)
    for _, f in ipairs(events[e] or {}) do if f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end

CreateFrame = function() return newFrame() end
Minimap = newFrame()
Minimap.GetWidth = function() return 140 end
Minimap.GetCenter = function() return 1000, 800 end
Minimap.GetEffectiveScale = function() return 1 end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
GetCursorPosition = function() return 1000, 900 end -- straight above the minimap centre
UIParent, UISpecialFrames = {}, {}
tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }
time = os.time
GetTime = os.clock
GetBuildInfo = function() return "1.60.1", "70959", "Nov 17 2026", 16001 end
UnitName = function() return "Tester" end
simLevel = 5 -- below Journeyman's level 10: plans stop at the 75 cap unless a test raises it
UnitLevel = function() return simLevel end
GetRealmName = function() return "Realm" end
GetCoinTextureString = function(c) return c .. "c" end
GetItemInfo = function(id) return "Item" .. id end
simBags = { [2589] = 10 }
GetItemCount = function(id) return simBags[id] or 0 end
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i)
    if i == 1 then return "Tailoring", nil, rawget(_G, "simRank") or 1, 75, 0, 0, 197 end
    return "Herbalism", nil, 50, 75, 0, 0, 182
end
Enum = { AuctionHouseSortOrder = { Price = 0 } }
C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = 1, maxSkillLevel = 75, professionID = 197 } end,
    GetAllRecipeIDs = function() return { 2387, 3915, 12046 } end,
    GetRecipeInfo = function(id) return { learned = id ~= 12046, relativeDifficulty = 0, name = "R" .. id } end,
}
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id)
    return ({ [2589] = 20, [2996] = 120, [2320] = 15, [2568] = 300, [4000] = 500 })[id]
end } } }

-- allow only expected new globals from the addon
local allowed = { ProfPathDB = true, SLASH_PROFPATH1 = true, SLASH_PROFPATH2 = true }
setmetatable(_G, { __newindex = function(t, k, v)
    if not allowed[k] then error("addon leaked global: " .. tostring(k), 2) end
    rawset(t, k, v)
end })

-- ---- load in .toc order ----
local ns = {}
local files = {}
for line in io.lines("ProfPath.toc") do
    if not line:match("^##") and line:match("%S") then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, file in ipairs(files) do
    local chunk = assert(loadfile(file))
    chunk("ProfPath", ns)
end
print("loaded: " .. table.concat(files, ", "))

-- fake generated data (in place of Data/Recipes.lua output)
ns.Data = { build = "sim", skillLines = { [197] = "Tailoring", [2948] = "Tailoring" }, recipeItems = { [12046] = { 4000, 55 } },
    items = { [2320] = { 10, 2 }, [2568] = { 100, 20 } },
    recipes = {
        [3915]  = { 197, 1, 25, 55, 2996, 1, { 2589, 2 }, "Bolt of Linen Cloth" },
        [2387]  = { 197, 1, 35, 50, 2568, 1, { 2996, 1, 2320, 1 }, "Linen Cloak" },
        [12046] = { 197, 10, 70, 90, 999, 1, { 2996, 1 }, "Simple Kilt" },
    } }

fire("ADDON_LOADED", "ProfPath")
fire("TRADE_SKILL_SHOW")
SlashCmdList.PROFPATH("range all") -- plan to max for the first checks
SlashCmdList.PROFPATH("")          -- opens the window and recalculates
assert(ns.UI.isShown(), "first /pp opens the window")
local st = ns.state
assert(st.prof and st.prof.name == "Tailoring", "profession detected")
assert(st.result.ok, "path found")
for _, s in ipairs(st.result.steps) do
    print(("  %d-%d %s x%.1f cost %.0f learn %d"):format(s.fromSkill, s.toSkill, s.recipe.name, s.expectedCrafts, s.cost, s.learnCost))
end
assert(st.result.steps[#st.result.steps].toSkill == 75, "reaches 75")
for _, f in ipairs(frames) do
    if f.shown then end
end
SlashCmdList.PROFPATH("resale 0")
SlashCmdList.PROFPATH("target 40")
assert(st.result.steps[#st.result.steps].toSkill == 40, "target respected")
-- step detail: per-step reagents, intermediates and materials; selecting renders the panel
do
    SlashCmdList.PROFPATH("target max")
    local cloak
    for _, s in ipairs(st.result.steps) do if s.recipe.name == "Linen Cloak" then cloak = s end end
    assert(cloak and #cloak.reagents == 2, "cloak has 2 reagents")
    local bolt = cloak.reagents[1].itemID == 2996 and cloak.reagents[1] or cloak.reagents[2]
    assert(bolt.perCraft == 1 and bolt.total == math.ceil(cloak.expectedCrafts - 1e-9), "bolt per craft / total")
    local sumMat = 0
    for _, m in ipairs(cloak.materials) do sumMat = sumMat + m.lineCost end
    assert(math.abs(sumMat - cloak.cash) < 1e-6, "step materials add up")
    local kilt
    for _, s in ipairs(st.result.steps) do if s.recipe.id == 12046 then kilt = s end end
    assert(kilt and kilt.recipe.learnSource and kilt.recipe.learnSource.kind == "item", "kilt learned from recipe item")
    st.selected = kilt.recipe.id .. ":" .. kilt.fromSkill
    ns.UI.setTab(2)                    -- plan tab with the detail panel open
    ns.UI.setTab(3)                    -- do-it tab
    ns.UI.setTab(1)                    -- prepare tab
    assert(ns.UI.targetBox and ns.UI.targetBox.shown ~= false, "Prepare draws the gold and range choices")
    ns.UI.setTab(2)
    local clicked = 0
    for _, f in ipairs(frames) do if f.scripts.OnClick and f.shown then clicked = clicked + 1 end end
    assert(clicked >= #st.result.steps, "step rows are clickable")
    st.selected = nil
end

-- live tracking: crafts and points counted for luck; a skill-up re-plans; a planned step change alerts
do
    allowed.simRank = true
    SlashCmdList.PROFPATH("target max")
    local first = st.result.steps[1]
    assert(first.recipe.name == "Linen Cloak", "starts with Linen Cloak")
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2387)   -- craft at skill 1 (orange: expected +1)
    simRank = 2; fire("CHAT_MSG_SKILL")                         -- skill-up arrives
    local luck = ns.Track.luck(2387)
    assert(luck and luck:find("1 crafts gave 1 points"), "luck counted: " .. tostring(luck))
    -- jump to where the plan switches to Bolt of Linen Cloth: should alert "Step done"
    local boltStart
    for _, s in ipairs(st.result.steps) do if s.recipe.name == "Bolt of Linen Cloth" then boltStart = s.fromSkill end end
    assert(boltStart, "plan has a Bolt step")
    st.alert = nil
    simRank = boltStart; fire("CHAT_MSG_SKILL")
    assert(st.result.steps[1].recipe.name == "Bolt of Linen Cloth", "re-planned from the new skill")
    assert(st.alert and st.alert.text:find("Step done"), "step change alerted: " .. tostring(st.alert and st.alert.text))
    ns.UI.setTab(3)                                             -- banner + luck render
    -- tracking off: no re-plan on skill-up
    SlashCmdList.PROFPATH("track off")
    local before = st.result.steps[1].fromSkill
    simRank = boltStart + 1; fire("CHAT_MSG_SKILL")
    assert(st.result.steps[1].fromSkill == before, "no re-plan while tracking is off")
    SlashCmdList.PROFPATH("track on")
    simRank = nil
end

-- budget: plan fits the gold on hand
do
    local ch = ns.Recipes.char()
    local function unlock() ch.commit, ch.stock = {}, {}; ns.recalc() end -- opening Do it locks the plan
    unlock()
    allowed.GetMoney = true
    SlashCmdList.PROFPATH("target max")
    SlashCmdList.PROFPATH("budget upfront")
    GetMoney = function() return 10000000 end                -- 1000g: full plan
    ns.recalc()
    assert(st.budget and not st.budget.limited and st.target == 75, "rich: full plan")
    local fullSpend = st.result.cash + st.result.learnTotal
    GetMoney = function() return math.floor(fullSpend / 3) end -- a third of what it takes
    ns.recalc()
    assert(st.budget.limited and st.result.ok, "limited plan found")
    assert(st.target < 75 and st.target > 1, "stops early: " .. st.target)
    assert(st.result.cash + st.result.learnTotal <= GetMoney(), "fits the gold")
    ns.UI.setTab(1); ns.UI.setTab(2); ns.UI.setTab(3)        -- render with budget banners
    unlock()
    GetMoney = function() return 0 end
    ns.recalc()
    assert(st.result.broke, "no gold: says so")
    ns.UI.setTab(2)
    -- typed budget overrides bag gold; "mine" clears it
    assert(ns.parseMoney("1g 50s") == 15000 and ns.parseMoney("2") == 20000 and ns.parseMoney("50s") == 5000
        and ns.parseMoney("1.5") == 15000 and ns.parseMoney("1g50s20c") == 15020, "money parsing")
    assert(ns.parseMoney("abc") == nil and ns.parseMoney("5x") == nil and ns.parseMoney("") == nil, "bad input rejected")
    GetMoney = function() return 0 end
    SlashCmdList.PROFPATH("budget " .. math.floor(fullSpend / 3) .. "c")
    assert(st.budget.custom and st.budget.gold == math.floor(fullSpend / 3) and st.result.ok and st.budget.limited,
        "typed budget used instead of empty bags")
    ns.UI.setTab(1); ns.UI.setTab(2)
    -- batch mode with a budget below the first step's spend: Do it shows one batch
    SlashCmdList.PROFPATH("budget batch")
    local s1 = st.result.steps[1]
    if s1 then
        SlashCmdList.PROFPATH("budget " .. math.max(1, math.floor(s1.cash / 3)) .. "c")
        assert(st.result.ok, "batch plan ok")
        ns.UI.setTab(3)
        unlock()
    end
    SlashCmdList.PROFPATH("budget upfront")
    SlashCmdList.PROFPATH("budget mine")
    assert(not st.budget.custom and st.result.broke, "back to bag gold (empty)")
    SlashCmdList.PROFPATH("budget off")
    ns.recalc()
    assert(st.budget == nil and st.target == 75, "budget off: full plan")
    GetMoney = nil
    -- Do it: expand every later step's shopping list
    assert(#st.result.steps >= 2, "plan has later steps")
    st.expanded = {}
    for i = 2, #st.result.steps do
        local s = st.result.steps[i]
        st.expanded[s.recipe.id .. ":" .. s.fromSkill] = true
    end
    ns.UI.setTab(3)
    unlock()
end

-- locked plan: Do it locks; starting stock only goes down; better path offered; switch; unlock
do
    SlashCmdList.PROFPATH("target max")
    local char = ns.Recipes.char()
    char.commit, char.stock = {}, {}
    ns.recalc()
    assert(not st.committed, "not locked yet")
    simBags = { [2589] = 10 }
    ns.UI.setTab(3)                                       -- opening Do it locks the plan
    assert(st.committed, "locked on Do it")
    local stock = char.stock.Tailoring
    assert(stock and stock[2589] == 10, "starting stock recorded")
    local lockedIds = st.committed.ids
    simBags = { [2589] = 50 }; ns.recalc()                -- bought 40 more: not free
    assert(char.stock.Tailoring[2589] == 10, "bought units not added to free stock")
    simBags = { [2589] = 3 }; ns.recalc()                 -- used some
    assert(char.stock.Tailoring[2589] == 3, "stock goes down as it is used")
    simBags = { [2589] = 40 }; ns.recalc()                -- bought again
    assert(char.stock.Tailoring[2589] == 3, "still only 3 free")
    -- make the locked plan's first recipe expensive -> a cheaper fresh path is offered, not applied
    local firstID = st.result.steps[1].recipe.id
    local api = Auctionator.API.v1
    local realPrice = api.GetAuctionPriceByItemID
    api.GetAuctionPriceByItemID = function(c, id) if id == 2320 then return 100000 end return realPrice(c, id) end
    ProfPathDB.vendor[2320] = nil
    local oldItems = ns.Data.items[2320]; ns.Data.items[2320] = nil
    st.alert = nil
    ns.recalc()
    assert(st.committed and st.result.steps[1].recipe.id == firstID, "locked plan kept")
    if st.better then
        assert(st.alert and st.alert.text:find("cheaper path"), "cheaper path announced")
        ns.UI.setTab(3)
        ns.commitPlan(st.better.result)                   -- Switch to it
        assert(st.committed and st.committed.ids ~= lockedIds, "switched")
        assert(char.stock.Tailoring[2589] == 3, "switching keeps the stock")
    end
    api.GetAuctionPriceByItemID = realPrice; ns.Data.items[2320] = oldItems
    ns.uncommitPlan()                                     -- New plan
    assert(not st.committed and char.stock.Tailoring, "unlocked, stock kept")
    char.commit, char.stock = {}, {}
    simBags = { [2589] = 10 }
    ns.recalc()
end

-- ranks: a high-level character plans past the cap with the rank training included
do
    local ch = ns.Recipes.char(); ch.commit, ch.stock = {}, {}
    allowed.simLevel = true
    SlashCmdList.PROFPATH("target max")
    simLevel = 60
    ns.recalc()
    assert(st.target > 75, "plans past the 75 cap: " .. st.target)
    local rk = st.result.rankUps and st.result.rankUps[1]
    assert(rk and rk.name == "Journeyman" and rk.cap == 150, "Journeyman training in the plan")
    local learnWithout = 0
    for _, s in ipairs(st.result.steps) do learnWithout = learnWithout + (s.learnCost or 0) end
    assert(math.abs(st.result.learnTotal - learnWithout - rk.cost) < 1e-6, "rank cost counted")
    local rows = ns.UI.withRanks(st.result, 75)
    local rankAt
    for i, row in ipairs(rows) do if row.rank then rankAt = i end end
    assert(rankAt and rows[rankAt + 1] and rows[rankAt + 1].step.toSkill > 75, "rank shown before the step past 75")
    ns.UI.setTab(1); ns.UI.setTab(2)
    -- reaching the rank's required skill (50) announces it
    simRank = 49; fire("CHAT_MSG_SKILL")
    st.alert = nil
    simRank = 50; fire("CHAT_MSG_SKILL")
    assert(st.alert and st.alert.text:find("train Journeyman"), "rank-up announced: " .. tostring(st.alert and st.alert.text))
    ns.UI.setTab(3)                                              -- "Rank up first" task renders
    ch.commit, ch.stock = {}, {}
    simRank = nil; ns.recalc()
    -- captured trainer values replace the Classic defaults
    ProfPathDB.ranks = { Tailoring = { Journeyman = { cost = 777, req = 40, level = 8 } } }
    ns.recalc()
    rk = st.result.rankUps[1]
    assert(rk.cost == 777 and rk.req == 40 and not rk.estimated, "captured rank values used")
    -- level too low: stops at the cap
    simLevel = 5
    ns.recalc()
    assert(st.target <= 75 and st.rankBlocked, "level too low: stop at cap")
    ProfPathDB.ranks = nil
    ch.commit, ch.stock = {}, {}
    ns.recalc()
end

-- trainer visit: remembers where the trainer is, its ranks and recipe costs; waypoint
do
    for _, k in ipairs({ "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost",
        "GetTrainerServiceSkillReq", "GetTrainerServiceLevelReq", "GetTrainerServiceSkillLine", "C_Map",
        "UiMapPoint", "C_SuperTrack", "UnitFactionGroup", "pinned" }) do allowed[k] = true end
    local services = {
        { "Linen Cloak", "", "available", 50, 1, 5 },
        { "Expert Tailor", "", "unavailable", 10000, 125, 20 },
    }
    GetNumTrainerServices = function() return #services end
    GetTrainerServiceInfo = function(i) return services[i][1], services[i][2], services[i][3] end
    GetTrainerServiceCost = function(i) return services[i][4] end
    GetTrainerServiceSkillReq = function(i) return "Tailoring", services[i][5], true end
    GetTrainerServiceLevelReq = function(i) return services[i][6] end
    GetTrainerServiceSkillLine = function() return "Tailoring" end
    UnitFactionGroup = function() return "Alliance" end
    local realUnitName = UnitName
    UnitName = function(u) if u == "npc" then return "Sellandus" end return realUnitName(u) end
    C_Map = {
        GetBestMapForUnit = function() return 1453 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.432, 0.731 end } end,
        GetMapInfo = function() return { name = "Stormwind City" } end,
        SetUserWaypoint = function(p) _G.pinned = p end,
    }
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    fire("TRAINER_SHOW")
    local loc = ns.Recipes.trainerFor("Tailoring", "Expert")
    assert(loc and loc.npc == "Sellandus" and loc.zone == "Stormwind City", "trainer location remembered")
    assert(ns.Recipes.trainerText(loc) == "Sellandus, Stormwind City (43.2, 73.1)", ns.Recipes.trainerText(loc))
    assert(loc.ranks.Expert, "trainer teaches Expert")
    assert(ProfPathDB.ranks.Tailoring.Expert.req == 125 and ProfPathDB.ranks.Tailoring.Expert.level == 20, "rank captured")
    assert(ProfPathDB.trainer.Tailoring["Linen Cloak"].cost == 50, "recipe cost captured")
    assert(ProfPathDB.trainer.Tailoring["Expert Tailor"] == nil, "rank not stored as a recipe")
    assert(ns.Recipes.waypoint(loc) and pinned and pinned.m == 1453, "waypoint set")

    -- closest, using the built-in trainer list (Data/Trainers.lua) + the one we visited
    allowed.CreateVector2D = true
    CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    local KALIMDOR = { [1457] = true, [1439] = true, [1445] = true, [2521] = true }
    C_Map.GetWorldPosFromMapPos = function(map, v)                   -- 1000 yd per map, maps far apart
        return KALIMDOR[map] and 1 or 0, CreateVector2D(map * 10000 + v.x * 1000, v.y * 1000)
    end
    local here = { 1453, 0.432, 0.731 }                               -- standing at Sellandus
    C_Map.GetBestMapForUnit = function() return here[1] end
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return here[2], here[3] end } end
    local near, d = ns.Recipes.trainerFor("Tailoring")
    assert(near.npc == "Sellandus" and d < 1, "closest: " .. near.npc .. " " .. tostring(d))
    assert(ns.Recipes.trainerText(near, d):find("right here"), "right here")
    near, d = ns.Recipes.trainerFor("Tailoring", "Artisan")
    assert(near.npc == "Georgio Bolero" and d, "Artisan: the Stormwind Artisan Tailor, got " .. near.npc)
    local experts = ns.Recipes.trainersFor("Tailoring", "Expert")
    for _, e in ipairs(experts) do
        assert(e.loc.npc ~= "Lawrence Schneider", "a Journeyman trainer is not offered for Expert")
    end
    local hasNeutral
    for _, e in ipairs(ns.Recipes.trainersFor("Tailoring")) do
        if e.loc.npc == "Grarnik Goodstitch" then hasNeutral = true end
        assert(e.loc.npc ~= "Magar", "no Horde trainers for an Alliance character")
    end
    assert(hasNeutral, "neutral trainers included")
    here = { 1457, 0.624, 0.224 }                                     -- in Darnassus, at Me'lynn
    near, d = ns.Recipes.trainerFor("Tailoring")
    assert(near.npc == "Me'lynn" and d, "closest in Darnassus: " .. near.npc)
    near, d = ns.Recipes.trainerFor("Tailoring", "Expert")
    -- closest trainer that can teach it: an Expert (by title) here beats Sellandus on another continent
    assert(d and near.npc ~= "Sellandus" and (near.cap or 0) >= 225,
        "closest capable trainer, got " .. near.npc .. " " .. tostring(d))
    -- recipe needing skill 149: a Journeyman trainer is enough; 150 needs an Expert
    assert(ns.Recipes.rankForSkill(149) == "Journeyman" and ns.Recipes.rankForSkill(150) == "Expert"
        and ns.Recipes.rankForSkill(1) == "Apprentice" and ns.Recipes.rankForSkill(300) == "Artisan", "rankForSkill")
    ns.UI.setTab(1)                                                   -- trainer hint with alternative renders
    ns.UI.setTab(1); ns.UI.setTab(2)
    local ch = ns.Recipes.char(); ch.commit, ch.stock = {}, {}
    ProfPathDB.ranks, ProfPathDB.trainer.Tailoring, ProfPathDB.trainerLocs = nil, nil, nil
    UnitName = realUnitName
    ns.recalc()
end

-- profession selection: primary first, menu switches, choice remembered, opening a window switches
do
    local realGP, realGPI = GetProfessions, GetProfessionInfo
    GetProfessions = function() return 1, 2, nil, 3 end
    GetProfessionInfo = function(i)
        if i == 1 then return "Tailoring", nil, 40, 75, 0, 0, 197 end
        if i == 2 then return "Herbalism", nil, 50, 75, 0, 0, 182 end
        return "Cooking", nil, 10, 75, 0, 0, 185
    end
    ns.Data.recipes[99999] = { 185, 1, 20, 40, nil, 1, { 2589, 1 }, "Simple Stew" }
    ns.Data.skillLines[185] = "Cooking"
    ns.Recipes.invalidateCounts()
    local ch = ns.Recipes.char(); ch.selectedProf, ch.commit, ch.stock = nil, {}, {}
    ns.recalc()
    assert(#st.profs == 2, "two crafting professions listed")
    assert(st.prof.name == "Tailoring", "starts on the primary, not Cooking (alphabetically first)")
    ns.UI.toggleProfMenu()                                   -- open the menu
    ns.selectProfessionByName("Cooking")
    assert(st.prof.name == "Cooking" and ch.selectedProf == "Cooking", "menu switches and remembers")
    ns.recalc()
    assert(st.prof.name == "Cooking", "choice survives a recalculation")
    ns.selectProfession(1)                                   -- old next/prev still works
    assert(st.prof.name == "Tailoring")
    ns.Data.recipes[99999], ns.Data.skillLines[185] = nil, nil
    ns.Recipes.invalidateCounts()
    ch.selectedProf = nil
    GetProfessions, GetProfessionInfo = realGP, realGPI
    ns.recalc()
end

-- minimap button: created on login, clicks toggle the window, drag moves it, can be hidden
do
    fire("PLAYER_LOGIN")
    local btn
    for _, f in ipairs(frames) do
        if f.scripts.OnDragStart and f.scripts.OnClick and f.scripts.OnEnter then btn = f end
    end
    assert(btn and btn.shown, "minimap button created")
    local wasShown = ns.UI.isShown()
    btn.scripts.OnClick(btn, "LeftButton")
    assert(ns.UI.isShown() ~= wasShown, "left-click toggles the window")
    btn.scripts.OnClick(btn, "RightButton")
    assert(ns.UI.isShown(), "right-click opens Do it")
    btn.scripts.OnEnter(btn)                                  -- tooltip with the current step
    btn.scripts.OnDragStart(btn)
    btn.scripts.OnUpdate(btn)                                 -- cursor straight above: 90 degrees
    btn.scripts.OnDragStop(btn)
    assert(math.abs(ProfPathDB.minimap.angle - 90) < 1e-6, "drag sets the angle: " .. ProfPathDB.minimap.angle)
    SlashCmdList.PROFPATH("minimap off")
    assert(not btn.shown and ProfPathDB.minimap.hide, "hidden")
    SlashCmdList.PROFPATH("minimap on")
    assert(btn.shown, "shown again")
    local ch = ns.Recipes.char(); ch.commit, ch.stock = {}, {}  -- right-click opened Do it (locks)
    ns.recalc()
end

-- tools, cooldowns, specializations, starter recipes
do
    local ch = ns.Recipes.char(); ch.commit, ch.stock = {}, {}
    local D = ns.Data
    D.tools, D.toolNames, D.toolItems = { [2387] = { 900 } }, { [900] = "Sewing Needle" }, { [900] = { 7777 } }
    D.items[7777] = { 250, 50 }
    ProfPathDB.vendor[7777] = 250                                 -- a vendor sells the needle
    D.cooldown = { [3915] = 86400 }                               -- pretend Bolt of Linen has a 1-day cooldown
    D.recipes[55555] = { 197, 1, 30, 50, 2568, 1, { 2589, 1 }, "Spec Cloak" }
    D.recipeItems[55555] = { 4001, 1, 12345 }                     -- needs a specialization spell
    D.autoLearn = { [55555] = true }
    SlashCmdList.PROFPATH("target max")
    local recipes, info = ns.Recipes.build(st.prof)
    local byId = {}
    for _, r in ipairs(recipes) do byId[r.id] = r end
    assert(byId[2387].toolCost == 250 and byId[2387].toolsMissing[1].name == "Sewing Needle", "missing tool priced")
    assert(byId[3915] and byId[3915].noLevel, "known cooldown recipe kept as producer, not for leveling")
    assert(not byId[55555] and info.specSkipped == 1, "specialization recipe skipped")
    for _, s in ipairs(st.result.steps) do assert(s.recipe.id ~= 3915, "cooldown recipe used for leveling") end
    simBags[7777] = 1; ns.recalc()                                -- now carrying the needle
    recipes = ns.Recipes.build(st.prof)
    for _, r in ipairs(recipes) do if r.id == 2387 then assert(not r.toolCost, "tool in bags: no cost") end end
    simBags[7777] = nil
    ns.UI.setTab(2); ns.UI.setTab(3)                              -- tool rows render
    D.tools, D.toolNames, D.toolItems, D.cooldown, D.autoLearn = {}, {}, {}, {}, {}
    D.recipes[55555], D.recipeItems[55555] = nil, nil
    ch.commit, ch.stock = {}, {}
    ns.recalc()
end

-- learn requirement from the recipe item is respected
for _, s in ipairs(st.result.steps) do
    if s.recipe.id == 12046 then assert(s.fromSkill >= 55, "learned before required skill") end
end
SlashCmdList.PROFPATH("help")

-- range: plan only the next 20 points, and scan only items for recipes that matter there
SlashCmdList.PROFPATH("range 20")
assert(ProfPathDB.options.target == nil, "range clears a fixed target")
assert(st.target == 21, "target = rank 1 + 20, got " .. tostring(st.target))
local inList = {}
for _, id in ipairs(st.items) do inList[id] = true end
assert(not inList[4000] and not inList[999], "Simple Kilt (learnable at 55) not scanned")
assert(inList[2589] and inList[2320], "nearby reagents scanned")
SlashCmdList.PROFPATH("range all")
assert(st.target == 75)

-- AH scan: commodity results arrive via events; progress bar reaches total
local results = { [2589] = { { unitPrice = 18, quantity = 50 } }, [2320] = {} }
allowed.lastQuery, allowed.AuctionHouseFrame, allowed.C_AuctionHouse, allowed.throttled = true, true, true, true
AuctionHouseFrame = { IsShown = function() return true end }
C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    MakeItemKey = function(id) return { itemID = id } end,
    -- Like the real client: a throttled query is silently ignored (no MESSAGE_SENT event).
    SendSearchQuery = function(key)
        if _G.throttled then return end
        _G.lastQuery = key.itemID
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    end,
    GetNumCommoditySearchResults = function(id) return #(results[id] or {}) end,
    GetCommoditySearchResultInfo = function(id, i) return results[id][i] end,
}
-- Prices captured C_AuctionHouse at load; reload it so it sees the stub
assert(loadfile("Prices.lua"))("ProfPath", ns)
SlashCmdList.PROFPATH("target max")
local n = 0
ns.Prices.scan({ 2589, 2996 })
while ns.Prices.scanning and n < 10 do
    fire("COMMODITY_SEARCH_RESULTS_UPDATED", _G.lastQuery)
    n = n + 1
end
local p = ns.Prices.progress
assert(not ns.Prices.scanning, "scan finished")
assert(p.done == 2 and p.total == 2 and p.found == 1, ("progress %d/%d found %d"):format(p.done, p.total, p.found))
assert(ProfPathDB.prices[2589].unit == 18, "scanned price stored")
assert(#ProfPathDB.scanLog == 4, "scan log written: 2 sent + 2 results, got " .. #ProfPathDB.scanLog)

-- timeout, then a late reply: counted once, price kept; dropped message is resent
local clock = 0
GetTime = function() return clock end
results[3000] = { { unitPrice = 7, quantity = 5 } }
results[3001] = { { unitPrice = 9, quantity = 5 } }
ns.Prices.scan({ 3000, 3001 })
assert(_G.lastQuery == 3000)
clock = 6; ns.Prices.__tick()                       -- 3000 sent but unanswered: times out, 3001 is sent
assert(_G.lastQuery == 3001 and p ~= nil)
fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")     -- server drops 3001 -> resent
assert(_G.lastQuery == 3001, "dropped request resent")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3000)      -- late reply for 3000
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3001)
p = ns.Prices.progress
assert(not ns.Prices.scanning, "second scan finished")
assert(p.done == 2 and p.found == 2 and p.timeouts == 0, ("done %d found %d timeouts %d"):format(p.done, p.found, p.timeouts))
assert(ProfPathDB.prices[3000].unit == 7, "late reply stored")

-- second, fuller reply for an item updates the price without double counting
results[3002] = { { unitPrice = 50, quantity = 1 } }
ns.Prices.scan({ 3002 })
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3002)
assert(not ns.Prices.scanning)
results[3002] = { { unitPrice = 40, quantity = 1 }, { unitPrice = 50, quantity = 1 } }
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3002)       -- fuller reply after the scan ended
p = ns.Prices.progress
assert(ProfPathDB.prices[3002].unit == 40 and #ProfPathDB.prices[3002].book == 2, "fuller reply applied")
assert(p.done == 1 and p.found == 1, "not double counted")

-- throttled: the query is never sent -> back off and retry the same item, nothing lost
results[3100] = { { unitPrice = 12, quantity = 3 } }
_G.lastQuery, _G.throttled = nil, true
ns.Prices.scan({ 3100 })
clock = clock + 1.1; ns.Prices.__tick()              -- not confirmed after 1s -> back off 1s
p = ns.Prices.progress
assert(ns.Prices.scanning and p.done == 0 and p.timeouts == 0, "item kept for retry")
clock = clock + 0.5; ns.Prices.__tick()              -- still inside the backoff window
assert(p.retryIn == 1, "UI told how long until retry")
_G.throttled = false
clock = clock + 0.6; ns.Prices.__tick()              -- backoff over: resent and confirmed
assert(_G.lastQuery == 3100, "retried after backoff")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3100)
assert(not ns.Prices.scanning and p.done == 1 and p.found == 1 and p.timeouts == 0, "retry succeeded")
assert(ProfPathDB.prices[3100].unit == 12)

-- pruning: items the needed() check rejects are skipped, not searched
results[3300], results[3301] = { { unitPrice = 1, quantity = 1 } }, { { unitPrice = 1, quantity = 1 } }
local searched = {}
local origSend = C_AuctionHouse.SendSearchQuery
C_AuctionHouse.SendSearchQuery = function(key) searched[key.itemID] = true; origSend(key) end
ns.Prices.scan({ 3300, 3301 }, function(id) return id ~= 3301 end)
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 3300)
p = ns.Prices.progress
assert(not ns.Prices.scanning and p.skipped == 1 and p.done == 2 and searched[3300] and not searched[3301], "3301 skipped")
C_AuctionHouse.SendSearchQuery = origSend

-- itemNeeded wiring: works with the live recipe state
SlashCmdList.PROFPATH("range all")
assert(ns.itemNeeded(2589) == true, "bolt cloth still needed")

-- full snapshot: request -> event -> chunked read; keeps only crafting items; per-unit price from stacks
local auctions = {
    { 2320, 5, 50 },   -- thread: stack of 5 for 50 -> 10 each
    { 2320, 1, 8 },    -- single at 8
    { 777777, 1, 99 }, -- not a crafting item: ignored
    { 2568, 1, 0 },    -- bid-only (no buyout): ignored
}
C_AuctionHouse.ReplicateItems = function() _G.replicateAsked = true end
C_AuctionHouse.GetNumReplicateItems = function() return #auctions end
C_AuctionHouse.GetReplicateItemInfo = function(idx)
    local a = auctions[idx + 1]
    return "n", 0, a[2], 1, true, 1, "", 0, 0, a[3], 0, false, nil, nil, nil, 0, a[1], true
end
allowed.replicateAsked = true
local function runUpdates() for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1) end end end
ProfPathDB.lastSnapshot = nil
ns.Prices.fullScan()
assert(_G.replicateAsked and ns.Prices.snapshotting, "snapshot requested")
runUpdates()                                          -- waiting: just updates the bar
fire("REPLICATE_ITEM_LIST_UPDATE")
runUpdates()                                          -- reads all 4 rows in one chunk
assert(not ns.Prices.snapshotting and not ns.Prices.scanning, "snapshot finished")
assert(ProfPathDB.prices[2320].unit == 8 and #ProfPathDB.prices[2320].book == 2, "thread priced per unit")
assert(ProfPathDB.prices[2320].book[2][1] == 10, "stack buyout divided by count")
assert(ProfPathDB.prices[777777] == nil, "non-crafting items not stored")
assert(ns.Prices.snapshotReadyIn() > 0, "cooldown started")
_G.replicateAsked = false
ns.Prices.fullScan()
assert(not _G.replicateAsked, "cooldown respected")

-- permanently throttled: gives up after 5 retries and finishes
_G.throttled = true
results[3200] = {}
ns.Prices.scan({ 3200 })
for _ = 1, 200 do clock = clock + 1; ns.Prices.__tick() end
p = ns.Prices.progress
assert(not ns.Prices.scanning and p.timeouts == 1, "gave up cleanly")
assert(ProfPathDB.prices[3200] == nil, "not recorded as 'nothing listed'")
_G.throttled = false
print("sim ok")
