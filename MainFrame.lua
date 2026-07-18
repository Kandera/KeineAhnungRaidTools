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

-- Auto Combat Log card: content filters for AutoLog.lua. Widget callbacks re-evaluate
-- immediately so toggling a filter while already inside an instance takes effect without
-- re-zoning (including stopping an addon-owned log when the master switch goes off).
local alTitle = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alTitle:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -265)
alTitle:SetText(L.LABEL_AUTOLOG)
table.insert(KART.DynamicLabels, alTitle)

local alCard = KART.CreateCard(KART.PromotePanel)
alCard:SetPoint("TOPLEFT", alTitle, "BOTTOMLEFT", 0, -10)
alCard:SetSize(290, 310)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.CreateSettingsCheckbox(alCard, "KART_AlEnabled", L.SET_AL_ENABLED, "autoLogEnabled", -20, AutoLogChanged, L.DESC_AL_ENABLED)
KART.CbAlRaidLFR = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidLFR", L.SET_AL_RAID_LFR, "autoLogRaidLFR", -50, AutoLogChanged)
KART.CbAlRaidNormal = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidNormal", L.SET_AL_RAID_NORMAL, "autoLogRaidNormal", -80, AutoLogChanged)
KART.CbAlRaidHeroic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidHeroic", L.SET_AL_RAID_HEROIC, "autoLogRaidHeroic", -110, AutoLogChanged)
KART.CbAlRaidMythic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidMythic", L.SET_AL_RAID_MYTHIC, "autoLogRaidMythic", -140, AutoLogChanged)
KART.CbAlMythicPlus = KART.CreateSettingsCheckbox(alCard, "KART_AlMythicPlus", L.SET_AL_MPLUS, "autoLogMythicPlus", -170, AutoLogChanged)
KART.SldAlMinKey = KART.CreateSettingsSlider(alCard, L.SET_AL_MIN_KEY, 2, 20, "autoLogMinKey", -200, "KART_AlMinKeySlider", L.DESC_AL_MIN_KEY)
KART.SldAlMinKey:HookScript("OnValueChanged", AutoLogChanged)
KART.CbAlDungeons = KART.CreateSettingsCheckbox(alCard, "KART_AlDungeons", L.SET_AL_DUNGEONS, "autoLogDungeons", -250, AutoLogChanged)
KART.CbAlDelves = KART.CreateSettingsCheckbox(alCard, "KART_AlDelves", L.SET_AL_DELVES, "autoLogDelves", -280, AutoLogChanged)

-- 7. Settings Panel Inhalt
local settingsTitle = KART.SettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
settingsTitle:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -20)
settingsTitle:SetText(L.LABEL_GENERAL_SETTINGS)
table.insert(KART.DynamicLabels, settingsTitle)

KART.CbMinimap = KART.CreateSettingsCheckbox(KART.SettingsPanel, "KART_MinimapCheck", L.SET_MINIMAP, "showMinimapIcon", -60, function()
    KART.UpdateMinimapButton()
end, L.DESC_MINIMAP)

KART.SldMenuSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -110, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -150, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)
KART.SldUiScale = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_UI_SCALE, 50, 150, "uiScale", -190, "KART_UiScaleSlider", L.DESC_UI_SCALE)

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

KART.SldBgAlpha = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_BG_ALPHA, 20, 100, "bgAlpha", -300, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)

-- Window layer slider: value is an index into KART.StrataLevels, shown as the strata name
-- instead of the raw number (the factory's own handler writes the number first, this hook
-- overwrites it right after; OnShow covers the case where the initial SetValue doesn't fire
-- because the saved value equals the slider's current one).
KART.SldFrameStrata = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_FRAME_STRATA, 1, #KART.StrataLevels, "frameStrata", -300, "KART_FrameStrataSlider", L.DESC_FRAME_STRATA)
KART.SldFrameStrata:ClearAllPoints()
KART.SldFrameStrata:SetPoint("LEFT", KART.SldBgAlpha, "RIGHT", 40, 0)
local function UpdateStrataSliderText(self)
    self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
end
KART.SldFrameStrata:HookScript("OnValueChanged", UpdateStrataSliderText)
KART.SldFrameStrata:HookScript("OnShow", UpdateStrataSliderText)

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

-- Reset Button
KART.BtnReset = KART.CreateModernButton(KART.SettingsPanel, L.BTN_RESET, L.DESC_RESET)
KART.BtnReset:SetPoint("TOPLEFT", KART.BtnAccentColor, "BOTTOMLEFT", 0, -20)
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
