local addonName, KART = ...
local L = KART.L

-- 1. Icon-Koordinaten für Raid-Marker (4x2 Grid)
local iconCoords = {
    {0, 0.25, 0, 0.25},       -- Stern (1)
    {0.25, 0.5, 0, 0.25},     -- Kreis (2)
    {0.5, 0.75, 0, 0.25},     -- Diamant (3)
    {0.75, 1, 0, 0.25},       -- Dreieck (4)
    {0, 0.25, 0.25, 0.5},     -- Mond (5)
    {0.25, 0.5, 0.25, 0.5},   -- Quadrat (6)
    {0.5, 0.75, 0.25, 0.5},   -- Kreuz (7)
    {0.75, 1, 0.25, 0.5},     -- Totenkopf (8)
}

-- Mapping für farblich passende Worldmarker
local tmToWmMap = {5, 6, 3, 2, 7, 1, 4, 8}

local markerColors = {
    {1, 0.92, 0},   -- Yellow (Star)
    {1, 0.5, 0.1},  -- Orange (Circle)
    {0.8, 0.3, 0.9},-- Purple (Diamond)
    {0, 0.9, 0.1},  -- Green (Triangle)
    {0.75, 0.75, 0.85}, -- Silver (Moon)
    {0, 0.55, 1},   -- Blue (Square)
    {1, 0.1, 0.1},  -- Red (Cross)
    {0.95, 0.95, 0.95}, -- White (Skull)
}

-- 2. Lokale Hilfsfunktion für die Bar-Buttons
local function CreateBarButton(parent, x, y, width, height, func, texture, texCoords, text, macrotext, tooltipText, name)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate, BackdropTemplate")
    b:SetSize(width or 22, height or 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameLevel(parent:GetFrameLevel() + 5)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(b, KART.Theme.CORNER_RADIUS_SM)

    if texture then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(texture)
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if texCoords then b.icon:SetTexCoord(unpack(texCoords)) end
    end

    if text then
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
    end

    if macrotext then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", macrotext)
    else
        b:SetScript("OnClick", func)
    end
    -- Hover color now derives from the user's accent color (same KART.Theme.AccentColor +
    -- Darken pattern as KART.CreateModernButton) instead of a hard-coded blue, so this toolbar
    -- matches the rest of the modernized UI's hover feedback. Darken() returns only r, g, b (no
    -- alpha), so capture into locals and pass an explicit alpha to SetBackdropColor.
    b.tooltipText = tooltipText
    b:SetScript("OnEnter", function(self)
        local r, g, bl = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.35)
        self:SetBackdropColor(dr, dg, db, 1)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        GameTooltip:Hide()
    end)
    return b
end

-- 3. Frame Erstellung (Raidlead Bar)
local rlBar = CreateFrame("Frame", "KART_RaidleadBar", UIParent, "BackdropTemplate")
rlBar:SetSize(275, 56)
rlBar:SetPoint("TOP", UIParent, "TOP", 0, -50)
rlBar:SetMovable(true)
rlBar:EnableMouse(true)
rlBar:RegisterForDrag("LeftButton")
KART.RaidleadBar = rlBar
KART.RegisterStrataFrame(rlBar)

rlBar:SetScript("OnDragStart", function(self)
    if not KART_Settings.lockRaidleadBar then self:StartMoving() end
end) -- KART_Settings ist eine SavedVariable und daher global zugänglich
rlBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    KART_Settings.rlBarPoint = point
    KART_Settings.rlBarRelativePoint = relativePoint
    KART_Settings.rlBarX = xOfs
    KART_Settings.rlBarY = yOfs
end)

rlBar:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
rlBar:SetBackdropColor(0, 0, 0, 0.8)
rlBar:SetBackdropBorderColor(0, 0, 0, 1)
KART.ApplyRoundedMask(rlBar, KART.Theme.CORNER_RADIUS_LG)

-- 4. Sichtbarkeits-Funktion (im KART Table für Core.lua)
function KART.UpdateRaidleadBarVisibility()
    if InCombatLockdown() then return end -- Blockiert UI-Änderungen während des Kampfes

    if KART_Settings and KART_Settings.showRaidleadBar then -- KART_Settings ist eine SavedVariable und daher global zugänglich
        if KART_Settings.autoHideRaidleadBar and not IsInGroup() then
            rlBar:Hide()
        else
            rlBar:ClearAllPoints()
            rlBar:SetPoint(KART_Settings.rlBarPoint or "TOP", UIParent, KART_Settings.rlBarRelativePoint or "TOP", KART_Settings.rlBarX or 0, KART_Settings.rlBarY or -50)
            rlBar:Show()
        end
    else
        rlBar:Hide()
    end
end

-- Applies every stored keybind as an override click-binding on its target button. Override
-- bindings work for both secure (Ready Check, Clear World Markers) and plain OnClick buttons
-- (Pull Timer, Buff-Checker Toggle) via the same call, and survive combat lockdown once set —
-- only the act of calling SetOverrideBindingClick itself is restricted while in combat, so this
-- must only run out of combat (mirrors KART.UpdateRaidleadBarVisibility's own guard).
function KART.ApplyKeybinds()
    if InCombatLockdown() then return end
    ClearOverrideBindings(rlBar)
    local binds = KART_Settings and KART_Settings.keybinds
    if not binds then return end
    for _, action in ipairs(KART.KeybindActions) do
        local key = binds[action.key]
        if key and key ~= "" then
            SetOverrideBindingClick(rlBar, false, key, action.button, "LeftButton")
        end
    end
end

-- 5. Buttons initialisieren
-- Zeile 1: Raid Target Marker
for i = 1, 8 do
    local macro = ("/target [@target,noexists] player\n/tm %d"):format(i)
    CreateBarButton(rlBar, 5 + (i-1)*24, -5, 22, 22, nil, "Interface\\TargetingFrame\\UI-RaidTargetingIcons", iconCoords[i], nil, macro)
end

-- Zeile 2: World Marker
for i = 1, 8 do
    local wmID = tmToWmMap[i]
    local b = CreateBarButton(rlBar, 5 + (i-1)*24, -29, 22, 22, nil, nil, nil, nil, "/wm " .. wmID)
    local color = markerColors[i]
    b.marker = b:CreateTexture(nil, "OVERLAY")
    b.marker:SetColorTexture(color[1], color[2], color[3], 0.9)
    b.marker:SetSize(12, 12)
    b.marker:SetPoint("CENTER")
end

-- Clear each world marker by number: "/cwm all" only works on English clients
-- because the "all" keyword is localized (e.g. "alle" on German clients), and
-- ClearRaidMarker() is protected, so it must stay a secure macro.
local clearWmMacro = {}
for i = 1, 8 do clearWmMacro[i] = "/cwm " .. i end
CreateBarButton(rlBar, 5 + 8*24, -29, 22, 22, nil, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil, nil, table.concat(clearWmMacro, "\n"), L.RL_CLEAR_WM, "KART_RL_ClearWorldMarkersBtn")
CreateBarButton(rlBar, 225, -5, 22, 22, nil, "Interface\\RAIDFRAME\\ReadyCheck-Ready", nil, nil, "/readycheck", L.RL_READYCHECK, "KART_RL_ReadyCheckBtn")

-- Buff-Checker Toggle Button
CreateBarButton(rlBar, 249, -5, 22, 22, function(_, _, down)
    if down then return end -- Verhindert, dass der Klick doppelt (beim Drücken und Loslassen) ausgelöst wird
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
    end
end, 135932, nil, nil, nil, L.RL_BUFFCHECK, "KART_RL_BuffCheckToggleBtn") -- Icon: Arkane Brillanz (Buffs)

-- Start the countdown via C_PartyInfo.DoCountdown instead of a "/pull" macro:
-- "/pull" only exists when BigWigs/DBM is installed, while DoCountdown drives the
-- native Blizzard countdown (which those addons display too). Reading the duration
-- at click time also removes the need to rewrite a macrotext attribute on settings
-- changes (which was blocked during combat lockdown). Right-click cancels.
KART.PullBtn = CreateBarButton(rlBar, 225, -29, 22, 22, function(_, button, down)
    if down then return end
    if button == "RightButton" then
        C_PartyInfo.DoCountdown(0)
    else
        C_PartyInfo.DoCountdown(KART_Settings and KART_Settings.pullTimerDuration or 10)
    end
end, "Interface\\ICONS\\Spell_Haste_Duration_01", nil, L.RL_PULL_LABEL, nil, L.RL_PULL_TIMER, "KART_RL_PullTimerBtn")