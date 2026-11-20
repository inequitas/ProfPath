--@debug@
-- Test-only tools, stripped from release builds (the whole file sits in a debug block).
-- /pp debug opens a panel that pretends you have a gathering profession at any skill, so the zone
-- lists, loops and hot spots can be checked without the profession.
local _, ns = ...

local KINDS = {
    { name = "Mining", line = 186 },
    { name = "Herbalism", line = 182 },
    { name = "Skinning", line = 393 },
    { name = "Fishing", line = 356 },
}

local function fake() return ProfPathDB and ProfPathDB.debugFake end

-- Add (or override) the fake profession in the list ProfPath plans from.
local realProfessions = ns.Recipes.professions
ns.Recipes.professions = function()
    local list = realProfessions()
    local f = fake()
    if not f then return list end
    for i = #list, 1, -1 do
        if list[i].name == f.name then table.remove(list, i) end
    end
    list[#list + 1] = { name = f.name, skillLine = f.line, rank = f.rank, max = 300 }
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- The fake skill also counts for "gather it yourself" while planning other professions.
local realGather = ns.Recipes.gatherSkills
ns.Recipes.gatherSkills = function()
    local out = realGather()
    local f = fake()
    local kind = f and ns.Gather and ns.Gather.lines[f.line]
    if kind then out[kind] = f.rank end
    return out
end

local panel
local function refresh()
    local f = fake()
    if panel then
        panel.label:SetText(f and ("Pretending: %s %d"):format(f.name, f.rank) or "Not pretending (pick a profession)")
    end
    if f then ns.Recipes.char().selectedProf = f.name end
    if ns.recalc then ns.recalc() end
end

local function set(name, line)
    local f = fake()
    local rank = (f and f.rank) or 1
    ProfPathDB.debugFake = { name = name, line = line, rank = rank }
    refresh()
end

local function add(n)
    local f = fake()
    if not f then return end
    f.rank = math.max(1, math.min(300, f.rank + n))
    refresh()
end

local function build()
    panel = CreateFrame("Frame", "ProfPathDebugPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(330, 150)
    panel:SetPoint("TOPRIGHT", -40, -200)
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.TitleText then panel.TitleText:SetText("ProfPath test: pretend profession") end
    panel.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.label:SetPoint("TOPLEFT", 14, -32)
    local function button(text, x, y, w, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn)
        return b
    end
    for i, k in ipairs(KINDS) do
        button(k.name, 12 + (i - 1) * 77, -52, 75, function() set(k.name, k.line) end)
    end
    local steps = { -25, -5, -1, 1, 5, 25 }
    for i, n in ipairs(steps) do
        button((n > 0 and "+" or "") .. n, 12 + (i - 1) * 51, -82, 49, function() add(n) end)
    end
    button("Stop pretending", 12, -112, 140, function()
        ProfPathDB.debugFake = nil
        refresh()
    end)
    button("Open ProfPath", 160, -112, 150, function()
        if not ns.UI.isShown() then ns.UI.toggle() end
    end)
end

local function toggle()
    if not panel then build() end
    if panel:IsShown() then panel:Hide() else panel:Show(); refresh() end
end

-- /pp debug (chained in front of the normal slash handler)
local realSlash = SlashCmdList.PROFPATH
SlashCmdList.PROFPATH = function(msg)
    if (msg or ""):lower():match("^%s*debug%s*$") then return toggle() end
    return realSlash(msg)
end
--@end-debug@
