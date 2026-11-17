-- ProfPath live tracking while you level:
--  * counts crafts of each recipe and the skill points they gave, against the expected points
--    (sum of skill-up chances at the skill each craft was made), so luck is visible;
--  * re-plans from the current skill on every skill-up, even with the window closed;
--  * alerts when the recommended recipe changes (planned step change, or something became cheaper).
local _, ns = ...
local T = {}
ns.Track = T

local prevPlan          -- last plan seen: { prof = name, steps = { {from, to, id, name}, ... } }
local lastRank = {}     -- [profession name] = rank last seen
local lastCraftID       -- recipe of the most recent craft (gets the credit for the next skill-up)
local checkPending = false

local function track()
    local c = ns.Recipes.char()
    c.track = c.track or {}
    return c.track
end
T.data = track

-- Called at the end of every recalculation: remember the plan for the next comparison.
function T.remember()
    local st = ns.state
    if not (st.prof and st.result and st.result.ok) then return end
    local steps = {}
    for _, s in ipairs(st.result.steps) do
        steps[#steps + 1] = { from = s.fromSkill, to = s.toSkill, id = s.recipe.id, name = s.recipe.name }
    end
    prevPlan = { prof = st.prof.name, steps = steps }
    lastRank[st.prof.name] = lastRank[st.prof.name] or st.prof.rank
end

local function planAt(plan, s)
    for _, st in ipairs(plan.steps) do
        if s >= st.from and s < st.to then return st end
    end
end

local function alert(msg)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("ProfPath: " .. msg, 1, 0.82, 0) end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    ns.chat(msg)
    ns.state.alert = { text = msg, t = time() }
end
T.notify = alert

-- Skill went up: credit the last crafted recipe, re-plan from here, and say so if the recipe to
-- craft now differs from what the previous plan had for this skill.
local function onSkillUp(profName, old, new)
    local tr = lastCraftID and track()[lastCraftID]
    if tr then tr.points = tr.points + (new - old) end

    local before = prevPlan
    -- re-plan the profession that just went up, even if the window shows another one
    ns.Recipes.char().selectedProf = profName
    ns.recalc()
    local st = ns.state

    -- Reached the skill to train the next rank: say so once, then re-plan after training.
    local nextRank = st.rankUps and st.rankUps[1]
    if nextRank and old < nextRank.req and new >= nextRank.req then
        alert(("You can train %s %s now (cap %d -> %d). Visit a trainer; ProfPath re-plans with the new recipes.")
            :format(nextRank.name, profName, st.prof and st.prof.max or 0, nextRank.cap))
        return
    end
    if not (before and before.prof == profName and st.prof and st.prof.name == profName) then return end
    if not (st.result and st.result.ok and st.result.steps[1]) then return end
    local now = st.result.steps[1]
    local was = planAt(before, new)
    local first = before.steps[1]
    if first and now.recipe.id ~= first.id then
        if (was and was.id == now.recipe.id) or st.committed then
            -- planned progression (a locked plan only changes recipe at its own steps)
            alert(("Step done! Now craft %s until skill %d."):format(now.recipe.name or "?", now.toSkill))
        else
            alert(("Switch now: %s is cheaper than %s from skill %d."):format(now.recipe.name or "?",
                first.name or "?", new))
        end
        track()[now.recipe.id] = nil -- fresh luck count for the new step
    end
end

local function checkSkill()
    checkPending = false
    if not (ProfPathDB and ProfPathDB.options.track) then return end
    for _, p in ipairs(ns.Recipes.professions()) do
        local old = lastRank[p.name]
        lastRank[p.name] = p.rank
        if old and p.rank and p.rank > old then onSkillUp(p.name, old, p.rank) end
    end
end

local function requestCheck()
    if checkPending then return end
    checkPending = true
    C_Timer.After(0.5, checkSkill)
end
T.requestCheck = requestCheck

-- A craft finished: count it and add its skill-up chance at the current skill to "expected".
local function onCast(spellID)
    local d = ns.Data.recipes[spellID]
    if not d then return end
    local profName = ns.Data.skillLines[d[1]]
    local rank = profName and lastRank[profName]
    if not rank then
        for _, p in ipairs(ns.Recipes.professions()) do
            lastRank[p.name] = lastRank[p.name] or p.rank
            if p.skillLine == d[1] then rank = p.rank end
        end
    end
    local tr = track()[spellID]
    if not tr then tr = { crafts = 0, points = 0, expected = 0 }; track()[spellID] = tr end
    tr.crafts = tr.crafts + 1
    if rank then
        tr.expected = tr.expected + ns.Optimizer.chance({ minSkill = 0, yellow = d[3], gray = d[4] }, rank)
    end
    lastCraftID = spellID
    requestCheck()
end

-- Raw luck numbers for a recipe: crafts, points gained, points expected (nil if nothing crafted).
function T.luckData(recipeID)
    local tr = track()[recipeID]
    if not tr or tr.crafts == 0 then return nil end
    return tr.crafts, tr.points, tr.expected
end

-- Luck summary for a recipe, or nil if nothing crafted yet.
function T.luck(recipeID)
    local tr = track()[recipeID]
    if not tr or tr.crafts == 0 then return nil end
    local ratio = tr.expected > 0 and tr.points / tr.expected or 1
    local verdict = ratio < 0.85 and "|cffff8800unlucky|r" or ratio > 1.15 and "|cff40c040lucky|r" or "on track"
    return ("So far %d crafts gave %d points (expected %.1f): %s"):format(tr.crafts, tr.points, tr.expected, verdict)
end

local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("SKILL_LINES_CHANGED")
pcall(f.RegisterEvent, f, "CHAT_MSG_SKILL")
f:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if not (ProfPathDB and ProfPathDB.options.track) then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and spellID then onCast(spellID) end
    else
        requestCheck()
    end
end)
