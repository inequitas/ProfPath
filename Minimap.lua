-- ProfPath minimap button: left-click opens/closes the window, right-click opens "Do it",
-- drag to move it around the minimap. Hide with /pp minimap off.
local _, ns = ...
local M = {}
ns.Minimap = M

local ICON = "Interface\\AddOns\\ProfPath\\Media\\icon"
local button

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function place()
    if not button then return end
    local a = math.rad(ProfPathDB.minimap.angle or 225)
    local r = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function dragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ProfPathDB.minimap.angle = math.deg(atan2(py / scale - my, px / scale - mx))
    place()
end

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ProfPath")
    local st = ns.state
    local step = st and st.result and st.result.ok and st.result.steps and st.result.steps[1]
    if st and st.prof then
        GameTooltip:AddLine(("%s %d / %d"):format(st.prof.name, st.prof.rank or 0, st.prof.max or 0), 1, 1, 1)
    end
    if step then
        GameTooltip:AddLine(("Now: %s until %d (about %d crafts)"):format(step.recipe.name or "?", step.toSkill,
            math.ceil(step.expectedCrafts - 1e-9)), 0.4, 0.8, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open / close", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Do it", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function create()
    button = CreateFrame("Button", "ProfPathMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 6, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then
            if not ns.UI.isShown() then ns.UI.toggle() end
            ns.UI.setTab(3)
        else
            ns.UI.toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
end

function M.refresh()
    if not ProfPathDB then return end
    ProfPathDB.minimap = ProfPathDB.minimap or { angle = 225 }
    if ProfPathDB.minimap.hide then
        if button then button:Hide() end
        return
    end
    if not button then create() end
    button:Show()
    place()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() M.refresh() end)
