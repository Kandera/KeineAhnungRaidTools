local addonName, KART = ...
local L = KART.L
local LSM = LibStub("LibSharedMedia-3.0", true)

-- 1. Tab-Wechsel Logik (wird in KART Tabelle gespeichert)
function KART.ShowTab(tabIndex)
    local panels = {
        KART.PromotePanel,
        KART.RaidleadPanel,
        KART.BuffCheckPanel,
        KART.SettingsPanel,
        KART.LootCouncilPanel,
        KART.WoWUtilsPanel,
    }
    for i, panel in ipairs(panels) do
        if panel then panel:SetShown(i == tabIndex) end
    end

    -- Buttons are created further down in this file (after this function is defined), so guard
    -- against calling ShowTab before they exist (not expected in practice, but SetActive would
    -- error on a nil button otherwise).
    local buttons = {
        KART.BtnPromote,
        KART.BtnRaidlead,
        KART.BtnBuffCheck,
        KART.BtnSettings,
        KART.BtnLootCouncil,
        KART.BtnWoWUtils,
    }
    for i, btn in ipairs(buttons) do
        if btn then btn:SetActive(i == tabIndex) end
    end
end

-- 2. Hauptfenster Erstellung
local mainFrame = CreateFrame("Frame", "KART_MainFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(500, 420)
mainFrame:SetPoint("CENTER", UIParent, "CENTER")
mainFrame:SetMovable(true)
mainFrame:SetResizable(true)
mainFrame:SetResizeBounds(500, 300, 1000, 1000) -- Mindest- und Maximalgröße
mainFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
mainFrame:SetBackdropBorderColor(0, 0, 0, 1)
mainFrame.gradientBg = KART.CreateGradientOverlay(mainFrame)
mainFrame:Hide()
KART.AddShowFade(mainFrame)

-- Ermöglicht das Schließen des gesamten KART-Fensters mit der ESC-Taste
table.insert(UISpecialFrames, mainFrame:GetName())

-- Header & Dragging
mainFrame.header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
mainFrame.header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
mainFrame.header:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", 0, -25)
mainFrame.header:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
mainFrame.header:SetBackdropColor(0.15, 0.15, 0.15, 1)
mainFrame.header:SetBackdropBorderColor(0, 0, 0, 1)
mainFrame.header:EnableMouse(true)
mainFrame.header:SetScript("OnMouseDown", function() mainFrame:StartMoving() end)
mainFrame.header:SetScript("OnMouseUp", function() mainFrame:StopMovingOrSizing() end)

mainFrame.title = mainFrame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mainFrame.title:SetPoint("LEFT", mainFrame.header, "LEFT", 10, 0)
mainFrame.title:SetText(L.ADDON_TITLE .. " v" .. (KART.Version or "1.12.2")) -- Titeltext inkl. Version
KART.MainFrame = mainFrame -- Hauptframe in KART speichern

-- 3. Sidebar Menü
local mainInset = CreateFrame("Frame", nil, mainFrame)
mainInset:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 5, -30)
mainInset:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -5, 5)

mainInset.sidebarBG = mainInset:CreateTexture(nil, "BACKGROUND")
mainInset.sidebarBG:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 0, 0)
mainInset.sidebarBG:SetPoint("BOTTOMRIGHT", mainInset, "BOTTOMLEFT", 140, 0)
mainInset.sidebarBG:SetColorTexture(0.05, 0.05, 0.05, 0.8)

KART.BtnPromote = KART.CreateTabButton(mainFrame, L.TAB_PROMOTE)
KART.BtnPromote:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 5, -10)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.CreateTabButton(mainFrame, L.TAB_RAIDLEAD)
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.CreateTabButton(mainFrame, L.TAB_BUFFCHECK)
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnSettings = KART.CreateTabButton(mainFrame, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

KART.BtnLootCouncil = KART.CreateTabButton(mainFrame, L.TAB_LOOTCOUNCIL or "Loot Council")
KART.BtnLootCouncil:SetPoint("TOPLEFT", KART.BtnSettings, "BOTTOMLEFT", 0, -5)
KART.BtnLootCouncil:SetScript("OnClick", function() KART.ShowTab(5) end)

KART.BtnWoWUtils = KART.CreateTabButton(mainFrame, L.TAB_WOWUTILS or "WoWUtils")
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnLootCouncil, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(6) end)

-- Sichtbare Trennlinie (Vertical Divider)
mainInset.divider = mainInset:CreateTexture(nil, "BACKGROUND")
mainInset.divider:SetColorTexture(0.2, 0.2, 0.2, 1)
mainInset.divider:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 140, 0)
mainInset.divider:SetPoint("BOTTOMLEFT", mainInset, "BOTTOMLEFT", 140, 0)
mainInset.divider:SetWidth(1)

-- 4. Content Bereich (ScrollFrame)
local scrollFrame = CreateFrame("ScrollFrame", "KART_ContentScrollFrame", mainInset, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 145, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", mainInset, "BOTTOMRIGHT", -25, 25)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
-- Height has headroom beyond what the tallest tab (Loot Council's raid-wide settings box)
-- needs at the default font, since that box's height depends on wrapped label text and can
-- grow with the user's chosen font/size (see LC.RelayoutRaidBox) — better a bit of empty
-- scroll space than content silently clipped below the scrollable area.
scrollChild:SetSize(310, 750)
scrollFrame:SetScrollChild(scrollChild)

-- Panels erstellen
KART.PromotePanel = CreateFrame("Frame", nil, scrollChild)
KART.PromotePanel:SetAllPoints()

KART.RaidleadPanel = CreateFrame("Frame", nil, scrollChild)
KART.RaidleadPanel:SetAllPoints()

KART.BuffCheckPanel = CreateFrame("Frame", nil, scrollChild)
KART.BuffCheckPanel:SetAllPoints()

KART.SettingsPanel = CreateFrame("Frame", nil, scrollChild)
KART.SettingsPanel:SetAllPoints()

KART.LootCouncilPanel = CreateFrame("Frame", nil, scrollChild)
KART.LootCouncilPanel:SetAllPoints()
KART.LootCouncilPanel:Hide()

KART.WoWUtilsPanel = CreateFrame("Frame", nil, scrollChild)
KART.WoWUtilsPanel:SetAllPoints()
KART.WoWUtilsPanel:Hide()

-- Scrollbar Thumb für KART.UpdateStyles() registrieren
KART.ScrollThumb = KART.StripScrollbarTextures(scrollFrame)
if KART.ScrollThumb then KART.ScrollThumb:SetSize(8, 30) end

-- 5. Raidlead Panel Inhalt (Hier binden wir die RaidleadBar ein!)
local rlTitle = KART.RaidleadPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rlTitle:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -20)
rlTitle:SetText(L.LABEL_RAIDLEAD_TOOLS)
table.insert(KART.DynamicLabels, rlTitle)

-- Card groups all Raidlead Bar settings into one visually distinct panel instead of leaving
-- checkboxes/slider floating directly on the tab background.
local rlCard = KART.CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", rlTitle, "BOTTOMLEFT", 0, -10)
rlCard:SetSize(290, 180)

-- Checkbox zur Aktivierung
KART.CbActivate = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarCheck", L.SET_RL_ACTIVATE, "showRaidleadBar", -20, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_ACTIVATE)

-- Checkbox zum Sperren
KART.CbLock = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarLockCheck", L.SET_RL_LOCK, "lockRaidleadBar", -50, nil, L.DESC_RL_LOCK)

-- Checkbox für Auto-Hide
KART.CbAutoHide = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarAutoHideCheck", L.SET_RL_AUTOHIDE, "autoHideRaidleadBar", -80, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_AUTOHIDE)

-- Pull-Timer Slider (Verknüpfung mit KART_PullBtn aus RaidleadBar.lua)
KART.PullSlider = KART.CreateSettingsSlider(rlCard, L.SET_PULL_TIMER, 5, 30, "pullTimerDuration", -130, "KART_PullTimerSlider", L.DESC_PULL_TIMER)
KART.PullSlider:HookScript("OnValueChanged", function(self, value)
    if KART.PullBtn then -- Objekt aus RaidleadBar.lua
        if not InCombatLockdown() then
            KART.PullBtn:SetAttribute("macrotext", "/pull " .. floor(value))
        end
    end
end)

-- 6. BuffChecker Panel Inhalt
local bcTitle = KART.BuffCheckPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bcTitle:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -20)
bcTitle:SetText(L.LABEL_BUFFCHECK_SETTINGS)
table.insert(KART.DynamicLabels, bcTitle)

local bcCard = KART.CreateCard(KART.BuffCheckPanel)
bcCard:SetPoint("TOPLEFT", bcTitle, "BOTTOMLEFT", 0, -10)
bcCard:SetSize(290, 290)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
KART.CbBcModuleEnabled = KART.CreateSettingsCheckbox(bcCard, "KART_BcModuleEnabled", L.SET_BC_MODULE_ENABLED, "bcModuleEnabled", -20, nil, L.DESC_BC_MODULE_ENABLED)

KART.CbShowBuffCheck = KART.CreateSettingsCheckbox(bcCard, "KART_ShowBuffCheck", L.SET_BC_READYCHECK, "showBuffCheck", -50, nil, L.DESC_BC_READYCHECK)

KART.BtnBuffPreview = KART.CreateModernButton(bcCard, L.BTN_BUFF_PREVIEW)
KART.BtnBuffPreview:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 20, -90)
KART.BtnBuffPreview:SetScript("OnClick", function()
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
        KART.UpdateBuffCheck(true)
    end
end)

KART.SldBuffCheckAlpha = KART.CreateSettingsSlider(bcCard, L.SET_BC_ALPHA, 0, 100, "buffCheckAlpha", -145, "KART_BuffCheckAlphaSlider", L.DESC_BC_ALPHA)
KART.SldCombatDelay = KART.CreateSettingsSlider(bcCard, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -190, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY)
KART.CbGrayOffline = KART.CreateSettingsCheckbox(bcCard, "KART_GrayOffline", L.SET_GRAY_OFFLINE, "grayOffline", -235, nil, L.DESC_GRAY_OFFLINE)

-- 6. Automation Panel Inhalt (Auto-Promote + Auto-Invite per Whisper + Auto-Raid-Convert)
local promLabel = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
promLabel:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -20)
promLabel:SetText(L.LABEL_PROMOTE_NAMES)
table.insert(KART.DynamicLabels, promLabel)

KART.PromoteEditBox = CreateFrame("EditBox", "KART_PromoteEditBox", KART.PromotePanel, "BackdropTemplate")
KART.PromoteEditBox:SetSize(250, 30)
KART.PromoteEditBox:SetPoint("TOPLEFT", promLabel, "BOTTOMLEFT", 0, -10)
KART.PromoteEditBox:SetAutoFocus(false)
KART.PromoteEditBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
KART.PromoteEditBox:SetBackdropColor(0,0,0,0.5)
table.insert(KART.EditBoxes, KART.PromoteEditBox)
KART.PromoteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.promoteNames = self:GetText()
    KART.UpdateCache()
end) -- KART_Settings ist eine SavedVariable
KART.PromoteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local invLabel = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
invLabel:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -110)
invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
table.insert(KART.DynamicLabels, invLabel)

KART.InviteEditBox = CreateFrame("EditBox", "KART_InviteEditBox", KART.PromotePanel, "BackdropTemplate")
KART.InviteEditBox:SetSize(250, 30)
KART.InviteEditBox:SetPoint("TOPLEFT", invLabel, "BOTTOMLEFT", 0, -10)
KART.InviteEditBox:SetAutoFocus(false)
KART.InviteEditBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
KART.InviteEditBox:SetBackdropColor(0,0,0,0.5)
table.insert(KART.EditBoxes, KART.InviteEditBox)
KART.InviteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.inviteKeywords = self:GetText()
    KART.UpdateCache()
end)
KART.InviteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

KART.CbAutoRaid = KART.CreateSettingsCheckbox(KART.PromotePanel, "KART_AutoRaidCheck", L.SET_AUTO_RAID, "autoConvertToRaid", -190, nil, L.DESC_AUTO_RAID)
KART.CbInviteViaGuildChat = KART.CreateSettingsCheckbox(KART.PromotePanel, "KART_InviteViaGuildChatCheck", L.SET_INVITE_VIA_GUILD_CHAT, "inviteViaGuildChat", -225, nil, L.DESC_INVITE_VIA_GUILD_CHAT)

-- 7. Settings Panel Inhalt
local settingsTitle = KART.SettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
settingsTitle:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -20)
settingsTitle:SetText(L.LABEL_GENERAL_SETTINGS)
table.insert(KART.DynamicLabels, settingsTitle)

KART.CbMinimap = KART.CreateSettingsCheckbox(KART.SettingsPanel, "KART_MinimapCheck", L.SET_MINIMAP, "showMinimapIcon", -60, function()
    KART.UpdateMinimapButton()
end, L.DESC_MINIMAP)

KART.SldTitleSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_TITLE, 8, 20, "titleFontSize", -110, "KART_TitleSizeSlider", L.DESC_TITLE_SIZE)
KART.SldMenuSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -150, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -190, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)

-- Schriftart Button
KART.BtnFont = KART.CreateModernButton(KART.SettingsPanel, L.BTN_SELECT_FONT, L.DESC_SELECT_FONT)
KART.BtnFont:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -230)
KART.BtnFont:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
        rootDescription:CreateTitle(L.BTN_SELECT_FONT)
        if LSM then
            local fonts = LSM:List("font")
            for _, name in ipairs(fonts) do
                rootDescription:CreateButton(name, function() 
                    KART_Settings.fontName = name
                    KART.UpdateStyles()
                    self.text:SetText(L.BTN_FONT_PREFIX .. name)
                end)
            end
        else
            rootDescription:CreateButton("Friz Quadrata", function() end)
        end
    end)
end)

-- Sprache Button
KART.BtnLang = KART.CreateModernButton(KART.SettingsPanel, (L.BTN_LANGUAGE_PREFIX or "Language: ") .. (L.LANG_AUTO or "Auto"), L.DESC_LANGUAGE)
KART.BtnLang:SetPoint("TOPLEFT", KART.BtnFont, "TOPRIGHT", 10, 0)
KART.BtnLang:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.LABEL_LANGUAGE)
        local options = {
            {name = L.LANG_AUTO, value = "Auto"},
            {name = L.LANG_EN, value = "enUS"},
            {name = L.LANG_DE, value = "deDE"}
        }
        for _, opt in ipairs(options) do
            rootDescription:CreateButton(opt.name, function() 
                KART_Settings.language = opt.value
                ReloadUI()
            end)
        end
    end)
end)

KART.SldBgAlpha = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_BG_ALPHA, 0, 100, "bgAlpha", -300, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)

-- Color Buttons
KART.BtnAccentColor = KART.CreateModernButton(KART.SettingsPanel, L.BTN_ACCENT_COLOR, L.DESC_ACCENT_COLOR)
KART.BtnAccentColor:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -340)
KART.BtnAccentColor:SetScript("OnClick", function() KART.OpenColorPicker("accentR", "accentG", "accentB") end)

-- Vorschau für Akzentfarbe
KART.ColorPreview = KART.SettingsPanel:CreateTexture(nil, "OVERLAY")
KART.ColorPreview:SetSize(25, 25)
KART.ColorPreview:SetPoint("LEFT", KART.BtnAccentColor, "RIGHT", 10, 0)
KART.ColorPreview.bg = KART.SettingsPanel:CreateTexture(nil, "BACKGROUND")
KART.ColorPreview.bg:SetPoint("TOPLEFT", KART.ColorPreview, "TOPLEFT", -1, 1)
KART.ColorPreview.bg:SetPoint("BOTTOMRIGHT", KART.ColorPreview, "BOTTOMRIGHT", 1, -1)
KART.ColorPreview.bg:SetColorTexture(0, 0, 0, 1)

KART.BtnBgColor = KART.CreateModernButton(KART.SettingsPanel, L.BTN_BG_COLOR, L.DESC_BG_COLOR)
KART.BtnBgColor:SetPoint("TOPLEFT", KART.BtnAccentColor, "TOPRIGHT", 45, 0)
KART.BtnBgColor:SetScript("OnClick", function() KART.OpenColorPicker("bgR", "bgG", "bgB") end)

-- Vorschau für Hintergrundfarbe
KART.BgColorPreview = KART.SettingsPanel:CreateTexture(nil, "OVERLAY")
KART.BgColorPreview:SetSize(25, 25)
KART.BgColorPreview:SetPoint("LEFT", KART.BtnBgColor, "RIGHT", 10, 0)
KART.BgColorPreview.bg = KART.SettingsPanel:CreateTexture(nil, "BACKGROUND")
KART.BgColorPreview.bg:SetPoint("TOPLEFT", KART.BgColorPreview, "TOPLEFT", -1, 1)
KART.BgColorPreview.bg:SetPoint("BOTTOMRIGHT", KART.BgColorPreview, "BOTTOMRIGHT", 1, -1)
KART.BgColorPreview.bg:SetColorTexture(0, 0, 0, 1)

-- Reset Button
KART.BtnReset = KART.CreateModernButton(KART.SettingsPanel, L.BTN_RESET, L.DESC_RESET)
KART.BtnReset:SetPoint("TOPLEFT", KART.BtnAccentColor, "BOTTOMLEFT", 0, -20)
KART.BtnReset:SetScript("OnClick", function()
    for k, v in pairs(KART.Defaults) do KART_Settings[k] = v end
    ReloadUI() -- Einfachste Methode um alle UI Werte zurückzusetzen
end)

-- 8. Resize Handle (Unten Rechts)
mainFrame.resizeBtn = CreateFrame("Button", nil, mainFrame)
mainFrame.resizeBtn:SetSize(16, 16)
mainFrame.resizeBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
mainFrame.resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
mainFrame.resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
mainFrame.resizeBtn:SetScript("OnMouseDown", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
mainFrame.resizeBtn:SetScript("OnMouseUp", function() mainFrame:StopMovingOrSizing() end)

-- 8. Schließen Button
local closeBtn = CreateFrame("Button", nil, mainFrame.header, "BackdropTemplate")
closeBtn:SetPoint("RIGHT", mainFrame.header, "RIGHT", -5, 0)
closeBtn:SetSize(20, 20)
closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
closeBtn.text:SetPoint("CENTER", 0, 1)
closeBtn.text:SetText("×")
closeBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0, 0) end)
closeBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn
