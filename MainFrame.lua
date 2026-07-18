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

-- 2. Main window (PNG artwork, EllesmereUI-style)
-- All geometry derives from the measured layout of kart-bg-dark.png:
-- image 1500x1154, opaque art box x 105-1396 / y 104-1050 (1292x947),
-- sidebar divider at art x 323, close-X center at art (1248, 39).
-- Art width is fixed at 800 (scale factor 800/1292); the window is not
-- freely resizable because the baked artwork would distort and the
-- invisible hit areas (close X, sidebar) would drift off their graphics.
-- Users scale the whole window via the Settings "Window Scale" slider.
local mainFrame = CreateFrame("Frame", "KART_MainFrame", UIParent)
mainFrame:SetSize(929, 715) -- full PNG footprint incl. transparent shadow margin
mainFrame:SetPoint("CENTER", UIParent, "CENTER")
mainFrame:SetMovable(true)

mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND")
mainFrame.bg:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-bg-dark.png")
mainFrame.bg:SetAllPoints()

KART.RegisterStrataFrame(mainFrame)
mainFrame:Hide()
KART.AddShowFade(mainFrame)

-- Allows closing the whole KART window with the ESC key
table.insert(UISpecialFrames, mainFrame:GetName())
KART.MainFrame = mainFrame

-- clickArea covers the opaque artwork region (shadow margin excluded).
-- Every interactive child anchors to it; it also blocks clicks from
-- falling through the window and handles whole-surface dragging (the
-- old header bar is baked into the PNG now).
local clickArea = CreateFrame("Frame", nil, mainFrame)
clickArea:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 65, -64)
clickArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -64, 64)
clickArea:EnableMouse(true)
clickArea:RegisterForDrag("LeftButton")
clickArea:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
clickArea:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)
mainFrame.clickArea = clickArea

-- Version string, bottom-left of the baked sidebar. Core.lua overwrites
-- the text once KART.Version is known (ADDON_LOADED).
mainFrame.versionText = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainFrame.versionText:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 18, 12)
mainFrame.versionText:SetText("v" .. (KART.Version or ""))

-- 3. Sidebar menu and tabs
-- Tabs start below the baked logo/title/underline zone of the artwork.
KART.BtnPromote = KART.CreateTabButton(clickArea, L.TAB_PROMOTE)
KART.BtnPromote:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 12, -75)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.CreateTabButton(clickArea, L.TAB_RAIDLEAD)
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.CreateTabButton(clickArea, L.TAB_BUFFCHECK)
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnLootCouncil = KART.CreateTabButton(clickArea, L.TAB_LOOTCOUNCIL or "Loot Council")
KART.BtnLootCouncil:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnLootCouncil:SetScript("OnClick", function() KART.ShowTab(5) end)

KART.BtnWoWUtils = KART.CreateTabButton(clickArea, L.TAB_WOWUTILS or "WoWUtils")
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnLootCouncil, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(6) end)

-- The Settings tab must always be the last entry in the sidebar. When adding a new tab
-- button, anchor it above this one (i.e. insert it between the previous last tab and
-- Settings, and re-anchor Settings to the new button).
KART.BtnSettings = KART.CreateTabButton(clickArea, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnWoWUtils, "BOTTOMLEFT", 0, -5)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

-- 4. Content area (ScrollFrame), right of the baked sidebar divider (200px)
local scrollFrame = CreateFrame("ScrollFrame", "KART_ContentScrollFrame", clickArea, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 208, -14)
scrollFrame:SetPoint("BOTTOMRIGHT", clickArea, "BOTTOMRIGHT", -30, 24)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
-- Height has headroom beyond what the tallest tab (Loot Council's raid-wide settings box)
-- needs at the default font, since that box's height depends on wrapped label text and can
-- grow with the user's chosen font/size (see LC.RelayoutRaidBox) — better a bit of empty
-- scroll space than content silently clipped below the scrollable area.
scrollChild:SetSize(540, 750)
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
local rlTitle = KART.RaidleadPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
rlTitle:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -20)
rlTitle:SetText(L.LABEL_RAIDLEAD_TOOLS)
table.insert(KART.DynamicLabels, rlTitle)

-- Card groups all Raidlead Bar settings into one visually distinct panel instead of leaving
-- checkboxes/slider floating directly on the tab background.
local rlCard = KART.CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", rlTitle, "BOTTOMLEFT", 0, -10)
rlCard:SetSize(500, 180)

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

-- Pull-Timer Slider: the pull button (RaidleadBar.lua) reads pullTimerDuration
-- at click time, so no macrotext attribute needs updating here anymore.
KART.PullSlider = KART.CreateSettingsSlider(rlCard, L.SET_PULL_TIMER, 5, 30, "pullTimerDuration", -130, "KART_PullTimerSlider", L.DESC_PULL_TIMER)

-- 6. BuffChecker Panel Inhalt
local bcTitle = KART.BuffCheckPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bcTitle:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -20)
bcTitle:SetText(L.LABEL_BUFFCHECK_SETTINGS)
table.insert(KART.DynamicLabels, bcTitle)

local bcCard = KART.CreateCard(KART.BuffCheckPanel)
bcCard:SetPoint("TOPLEFT", bcTitle, "BOTTOMLEFT", 0, -10)
bcCard:SetSize(500, 160)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
KART.CbBcModuleEnabled = KART.CreateSettingsCheckbox(bcCard, "KART_BcModuleEnabled", L.SET_BC_MODULE_ENABLED, "bcModuleEnabled", -20, nil, L.DESC_BC_MODULE_ENABLED)

KART.CbShowBuffCheck = KART.CreateSettingsCheckbox(bcCard, "KART_ShowBuffCheck", L.SET_BC_READYCHECK, "showBuffCheck", -50, nil, L.DESC_BC_READYCHECK)

KART.CbGrayOffline = KART.CreateSettingsCheckbox(bcCard, "KART_GrayOffline", L.SET_GRAY_OFFLINE, "grayOffline", -80, nil, L.DESC_GRAY_OFFLINE)

KART.BtnBuffPreview = KART.CreateModernButton(bcCard, L.BTN_BUFF_PREVIEW)
KART.BtnBuffPreview:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 20, -115)
KART.BtnBuffPreview:SetScript("OnClick", function()
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
        KART.UpdateBuffCheck(true)
    end
end)

KART.SldBuffCheckAlpha = KART.CreateSettingsSlider(bcCard, L.SET_BC_ALPHA, 0, 100, "buffCheckAlpha", -30, "KART_BuffCheckAlphaSlider", L.DESC_BC_ALPHA)
KART.SldBuffCheckAlpha:ClearAllPoints()
KART.SldBuffCheckAlpha:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -46)
KART.SldCombatDelay = KART.CreateSettingsSlider(bcCard, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -90, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY)
KART.SldCombatDelay:ClearAllPoints()
KART.SldCombatDelay:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -106)

-- 6. Automation panel: promote/invite settings grouped into a card.
local autoCard = KART.CreateCard(KART.PromotePanel)
autoCard:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -20)
autoCard:SetSize(500, 195)

local promLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promLabel:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 20, -15)
promLabel:SetText(L.LABEL_PROMOTE_NAMES)
table.insert(KART.DynamicLabels, promLabel)

KART.PromoteEditBox = CreateFrame("EditBox", "KART_PromoteEditBox", autoCard, "BackdropTemplate")
KART.PromoteEditBox:SetSize(460, 28)
KART.PromoteEditBox:SetPoint("TOPLEFT", promLabel, "BOTTOMLEFT", 0, -8)
KART.PromoteEditBox:SetAutoFocus(false)
KART.PromoteEditBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
KART.PromoteEditBox:SetBackdropColor(0,0,0,0.5)
table.insert(KART.EditBoxes, KART.PromoteEditBox)
KART.PromoteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.promoteNames = self:GetText()
    KART.UpdateCache()
end) -- KART_Settings ist eine SavedVariable
KART.PromoteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local invLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
invLabel:SetPoint("TOPLEFT", KART.PromoteEditBox, "BOTTOMLEFT", 0, -14)
invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
table.insert(KART.DynamicLabels, invLabel)

KART.InviteEditBox = CreateFrame("EditBox", "KART_InviteEditBox", autoCard, "BackdropTemplate")
KART.InviteEditBox:SetSize(460, 28)
KART.InviteEditBox:SetPoint("TOPLEFT", invLabel, "BOTTOMLEFT", 0, -8)
KART.InviteEditBox:SetAutoFocus(false)
KART.InviteEditBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
KART.InviteEditBox:SetBackdropColor(0,0,0,0.5)
table.insert(KART.EditBoxes, KART.InviteEditBox)
KART.InviteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.inviteKeywords = self:GetText()
    KART.UpdateCache()
end)
KART.InviteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

KART.CbAutoRaid = KART.CreateSettingsCheckbox(autoCard, "KART_AutoRaidCheck", L.SET_AUTO_RAID, "autoConvertToRaid", -160, nil, L.DESC_AUTO_RAID)
KART.CbInviteViaGuildChat = KART.CreateSettingsCheckbox(autoCard, "KART_InviteViaGuildChatCheck", L.SET_INVITE_VIA_GUILD_CHAT, "inviteViaGuildChat", -160, nil, L.DESC_INVITE_VIA_GUILD_CHAT)
KART.CbInviteViaGuildChat:ClearAllPoints()
KART.CbInviteViaGuildChat:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 260, -160)

-- Auto Combat Log card: content filters for AutoLog.lua. Widget callbacks re-evaluate
-- immediately so toggling a filter while already inside an instance takes effect without
-- re-zoning (including stopping an addon-owned log when the master switch goes off).
local alTitle = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alTitle:SetPoint("TOPLEFT", autoCard, "BOTTOMLEFT", 0, -18)
alTitle:SetText(L.LABEL_AUTOLOG)
table.insert(KART.DynamicLabels, alTitle)

local alCard = KART.CreateCard(KART.PromotePanel)
alCard:SetPoint("TOPLEFT", alTitle, "BOTTOMLEFT", 0, -10)
alCard:SetSize(500, 185)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.CreateSettingsCheckbox(alCard, "KART_AlEnabled", L.SET_AL_ENABLED, "autoLogEnabled", -20, AutoLogChanged, L.DESC_AL_ENABLED)
KART.CbAlRaidLFR = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidLFR", L.SET_AL_RAID_LFR, "autoLogRaidLFR", -50, AutoLogChanged)
KART.CbAlRaidNormal = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidNormal", L.SET_AL_RAID_NORMAL, "autoLogRaidNormal", -80, AutoLogChanged)
KART.CbAlRaidHeroic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidHeroic", L.SET_AL_RAID_HEROIC, "autoLogRaidHeroic", -110, AutoLogChanged)
KART.CbAlRaidMythic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidMythic", L.SET_AL_RAID_MYTHIC, "autoLogRaidMythic", -140, AutoLogChanged)
KART.CbAlMythicPlus = KART.CreateSettingsCheckbox(alCard, "KART_AlMythicPlus", L.SET_AL_MPLUS, "autoLogMythicPlus", -20, AutoLogChanged)
KART.CbAlMythicPlus:ClearAllPoints()
KART.CbAlMythicPlus:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -20)
KART.SldAlMinKey = KART.CreateSettingsSlider(alCard, L.SET_AL_MIN_KEY, 2, 20, "autoLogMinKey", -50, "KART_AlMinKeySlider", L.DESC_AL_MIN_KEY)
KART.SldAlMinKey:HookScript("OnValueChanged", AutoLogChanged)
KART.SldAlMinKey:ClearAllPoints()
KART.SldAlMinKey:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -66)
KART.CbAlDungeons = KART.CreateSettingsCheckbox(alCard, "KART_AlDungeons", L.SET_AL_DUNGEONS, "autoLogDungeons", -110, AutoLogChanged)
KART.CbAlDungeons:ClearAllPoints()
KART.CbAlDungeons:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -110)
KART.CbAlDelves = KART.CreateSettingsCheckbox(alCard, "KART_AlDelves", L.SET_AL_DELVES, "autoLogDelves", -140, AutoLogChanged)
KART.CbAlDelves:ClearAllPoints()
KART.CbAlDelves:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -140)

-- 7. Settings Panel Inhalt
local settingsTitle = KART.SettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
settingsTitle:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -20)
settingsTitle:SetText(L.LABEL_GENERAL_SETTINGS)
table.insert(KART.DynamicLabels, settingsTitle)

-- Card: window-level interface options
local ifCard = KART.CreateCard(KART.SettingsPanel)
ifCard:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -50)
ifCard:SetSize(242, 215)

KART.CbMinimap = KART.CreateSettingsCheckbox(ifCard, "KART_MinimapCheck", L.SET_MINIMAP, "showMinimapIcon", -20, function()
    KART.UpdateMinimapButton()
end, L.DESC_MINIMAP)
KART.SldUiScale = KART.CreateSettingsSlider(ifCard, L.SET_UI_SCALE, 50, 150, "uiScale", -60, "KART_UiScaleSlider", L.DESC_UI_SCALE)
KART.SldBgAlpha = KART.CreateSettingsSlider(ifCard, L.SET_BG_ALPHA, 20, 100, "bgAlpha", -105, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)

-- Window layer slider: value is an index into KART.StrataLevels, shown as the strata name
-- instead of the raw number (the factory's own handler writes the number first, this hook
-- overwrites it right after; OnShow covers the case where the initial SetValue doesn't fire
-- because the saved value equals the slider's current one).
KART.SldFrameStrata = KART.CreateSettingsSlider(ifCard, L.SET_FRAME_STRATA, 1, #KART.StrataLevels, "frameStrata", -150, "KART_FrameStrataSlider", L.DESC_FRAME_STRATA)
local function UpdateStrataSliderText(self)
    self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
end
KART.SldFrameStrata:HookScript("OnValueChanged", UpdateStrataSliderText)
KART.SldFrameStrata:HookScript("OnShow", UpdateStrataSliderText)

-- Card: text rendering
local txtCard = KART.CreateCard(KART.SettingsPanel)
txtCard:SetPoint("TOPLEFT", ifCard, "TOPRIGHT", 16, 0)
txtCard:SetSize(242, 215)

KART.SldMenuSize = KART.CreateSettingsSlider(txtCard, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -20, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(txtCard, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -65, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)

-- Schriftart Button
KART.BtnFont = KART.CreateModernButton(txtCard, L.BTN_SELECT_FONT, L.DESC_SELECT_FONT)
KART.BtnFont:SetPoint("TOPLEFT", txtCard, "TOPLEFT", 20, -125)
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
KART.BtnLang = KART.CreateModernButton(txtCard, (L.BTN_LANGUAGE_PREFIX or "Language: ") .. (L.LANG_AUTO or "Auto"), L.DESC_LANGUAGE)
KART.BtnLang:SetPoint("TOPLEFT", KART.BtnFont, "BOTTOMLEFT", 0, -10)
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

-- Card: colors, reset, companion sync status (Droptimizer anchors into this card)
local colCard = KART.CreateCard(KART.SettingsPanel)
colCard:SetPoint("TOPLEFT", ifCard, "BOTTOMLEFT", 0, -20)
colCard:SetSize(500, 150)
KART.SettingsColorCard = colCard

-- Color Buttons
KART.BtnAccentColor = KART.CreateModernButton(colCard, L.BTN_ACCENT_COLOR, L.DESC_ACCENT_COLOR)
KART.BtnAccentColor:SetPoint("TOPLEFT", colCard, "TOPLEFT", 20, -20)
KART.BtnAccentColor:SetScript("OnClick", function() KART.OpenColorPicker("accentR", "accentG", "accentB") end)

-- Vorschau für Akzentfarbe
KART.ColorPreview = colCard:CreateTexture(nil, "OVERLAY")
KART.ColorPreview:SetSize(25, 25)
KART.ColorPreview:SetPoint("LEFT", KART.BtnAccentColor, "RIGHT", 10, 0)
KART.ColorPreview.bg = colCard:CreateTexture(nil, "BACKGROUND")
KART.ColorPreview.bg:SetPoint("TOPLEFT", KART.ColorPreview, "TOPLEFT", -1, 1)
KART.ColorPreview.bg:SetPoint("BOTTOMRIGHT", KART.ColorPreview, "BOTTOMRIGHT", 1, -1)
KART.ColorPreview.bg:SetColorTexture(0, 0, 0, 1)

-- Reset Button
KART.BtnReset = KART.CreateModernButton(colCard, L.BTN_RESET, L.DESC_RESET)
KART.BtnReset:SetPoint("TOPLEFT", KART.BtnAccentColor, "BOTTOMLEFT", 0, -16)
KART.BtnReset:SetScript("OnClick", function()
    for k, v in pairs(KART.Defaults) do KART_Settings[k] = v end
    ReloadUI() -- Einfachste Methode um alle UI Werte zurückzusetzen
end)

-- 8. Close button: invisible hit area over the X baked into the artwork.
-- HIGHLIGHT-layer texture shows automatically on hover, no scripts needed.
local closeBtn = CreateFrame("Button", nil, clickArea)
closeBtn:SetSize(36, 36)
closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -27, -24)
local closeHover = closeBtn:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.08)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn
