local addonName, KART = ...

local miniButton = CreateFrame("Button", "KART_MinimapButton", Minimap)
miniButton:SetSize(31, 31)
miniButton:SetFrameLevel(10)
miniButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = miniButton:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.jpg")
icon:SetSize(20, 20)
icon:SetPoint("CENTER")

function KART.UpdateMinimapButton()
    if not KART_Settings then return end
    miniButton:SetShown(KART_Settings.showMinimapIcon)
    local angle = KART_Settings.minimapPos or 45
    local x = math.cos(math.rad(angle)) * 80
    local y = math.sin(math.rad(angle)) * 80
    miniButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

miniButton:SetMovable(true)
miniButton:RegisterForDrag("LeftButton")
miniButton:SetScript("OnDragStart", function(self)
    self:StartMoving()
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        KART_Settings.minimapPos = math.deg(math.atan2(py - my, px - mx))
        KART.UpdateMinimapButton()
    end)
end)
miniButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
end)

miniButton:SetScript("OnClick", function()
    if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end -- KART.MainFrame und KART.ShowTab aus MainFrame.lua
end)

miniButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Keine Ahnung Raid Tools")
    GameTooltip:Show()
end)
miniButton:SetScript("OnLeave", function() GameTooltip:Hide() end)