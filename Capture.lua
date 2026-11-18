-- ProfPath capture: remembers vendor prices and trainer recipe costs as the player visits NPCs.
local _, ns = ...

local function merchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    end
    if GetMerchantItemInfo then
        local _, _, price, quantity, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
        return price, quantity, numAvailable, extendedCost
    end
end

local function captureMerchant()
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local itemID = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, available, extended = merchantItem(i)
        if itemID and price and price > 0 and not extended and available == -1 then
            ProfPathDB.vendor[itemID] = price / math.max(stack or 1, 1)
        end
    end
end

-- Trainer list: store cost by recipe name, per profession name.
local function captureTrainer()
    if not GetNumTrainerServices then return end
    local prof = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(1)
    if not prof then
        local title = ClassTrainerFrame and ClassTrainerFrame.TitleText and ClassTrainerFrame.TitleText:GetText()
        prof = title
    end
    if not prof then return end
    local t = ProfPathDB.trainer[prof] or {}
    ProfPathDB.ranks = ProfPathDB.ranks or {}
    local ranks = ProfPathDB.ranks[prof] or {}
    for i = 1, GetNumTrainerServices() do
        -- name, rank/subtext, category ("available" | "unavailable" | "used" | "header")
        local name, sub, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            local req
            if GetTrainerServiceSkillReq then
                local _, rank = GetTrainerServiceSkillReq(i)
                req = tonumber(rank)
            end
            local level = GetTrainerServiceLevelReq and tonumber(GetTrainerServiceLevelReq(i)) or nil
            -- Profession ranks ("Expert Leatherworker", or "Leatherworking" with subtext "Expert").
            local isRank
            for _, rk in ipairs(ns.Recipes.RANKS) do
                local label = name .. " " .. (type(sub) == "string" and sub or "")
                if label:find(rk.name) then
                    ranks[rk.name] = { cost = cost, req = req, level = level }
                    isRank = true
                end
            end
            -- Other languages: a rank is listed under the profession's own name; tell which one by
            -- its skill requirement (50, 125, 200) or, failing that, its level requirement.
            if not isRank and name == prof then
                for _, rk in ipairs(ns.Recipes.RANKS) do
                    if (req and req == rk.req) or (not req and level and level == rk.level) then
                        ranks[rk.name] = { cost = cost, req = req, level = level }
                        isRank = true
                    end
                end
            end
            if not isRank then t[name] = { cost = cost, req = req } end
        end
    end
    ProfPathDB.ranks[prof] = ranks

    -- Where this trainer stands (NPC spawns are not in the game data, so we learn them by visiting).
    local ok, loc = pcall(function()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if not mapID then return nil end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        local x, y
        if pos then x, y = pos:GetXY() end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local taught = {}
        for rkName in pairs(ranks) do taught[rkName] = true end
        -- World position (yards) and instance, to measure distance from wherever you are later.
        local wy, wx, _, inst
        if UnitPosition then wy, wx, _, inst = UnitPosition("player") end
        return { npc = UnitName("npc") or "Trainer", mapID = mapID, zone = info and info.name or "?",
            x = x, y = y, wx = wx, wy = wy, inst = inst,
            faction = UnitFactionGroup and UnitFactionGroup("player") or nil, ranks = taught, t = time() }
    end)
    if ok and loc then
        ProfPathDB.trainerLocs = ProfPathDB.trainerLocs or {}
        local list = ProfPathDB.trainerLocs[prof] or {}
        list[loc.npc .. "@" .. loc.mapID] = loc
        ProfPathDB.trainerLocs[prof] = list
    end
    ProfPathDB.trainer[prof] = t
    ProfPathDB.trainerSeen[prof] = time()
    if ns.requestRecalc then ns.requestRecalc() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("TRAINER_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if not ProfPathDB then return end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        pcall(captureMerchant)
    else
        local ok, err = pcall(captureTrainer)
        if not ok then ns.chat("trainer capture failed: " .. tostring(err)) end
    end
end)
