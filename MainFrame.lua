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

    -- Fixed header-zone title of the active tab (created via KART.CreateTabTitle).
    for i, t in pairs(KART.TabTitles or {}) do
        t:SetShown(i == tabIndex)
    end

    -- Scroll range depends on the active tab's content height (KART.UpdateScrollRange is
    -- defined further down in this file, after the scroll frame exists).
    KART.CurrentTab = tabIndex
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
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

-- Per-tab header titles live OUTSIDE the scroll frame, fixed in the artwork's header zone
-- (between the window top and the baked divider line at ~-48 from clickArea top). The scroll
-- viewport starts below that line, so scrolled content can never slide up over the header.
-- KART.ShowTab toggles which title is visible.
KART.TabTitles = {}
function KART.CreateTabTitle(tabIndex, text)
    local fs = clickArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 228, -22)
    fs:SetText(text)
    fs:Hide() -- ShowTab reveals the active tab's title
    table.insert(KART.DynamicLabels, fs)
    KART.TabTitles[tabIndex] = fs
    return fs
end

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

KART.BtnLootCouncil = KART.CreateTabButton(clickArea, L.TAB_LOOTCOUNCIL)
KART.BtnLootCouncil:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnLootCouncil:SetScript("OnClick", function() KART.ShowTab(5) end)

KART.BtnWoWUtils = KART.CreateTabButton(clickArea, L.TAB_WOWUTILS)
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnLootCouncil, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(6) end)

-- The Settings tab must always be the last entry in the sidebar. When adding a new tab
-- button, anchor it above this one (i.e. insert it between the previous last tab and
-- Settings, and re-anchor Settings to the new button).
KART.BtnSettings = KART.CreateTabButton(clickArea, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnWoWUtils, "BOTTOMLEFT", 0, -5)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

-- 4. Content area (ScrollFrame), right of the baked sidebar divider (200px).
-- The viewport starts at -52, just below the artwork's baked divider line (~-48), so
-- scrolled content is clipped there instead of sliding up over the header zone.
local scrollFrame = CreateFrame("ScrollFrame", "KART_ContentScrollFrame", clickArea, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 208, -52)
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

-- Re-anchor the scrollbar to span the full viewport (which itself starts below the baked
-- divider line now); the hidden arrow buttons don't need the template's 16px reserves.
local contentScrollBar = _G["KART_ContentScrollFrameScrollBar"]
if contentScrollBar then
    contentScrollBar:ClearAllPoints()
    contentScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -2)
    contentScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 2)
end
-- Lets the template's own OnScrollRangeChanged hide the bar at range 0 instead of merely
-- disabling it; KART.UpdateScrollRange below also toggles it explicitly for immediate effect.
scrollFrame.scrollBarHideable = true

-- Per-tab scroll range. With the old fixed 750px scroll child, every tab was scrollable even
-- when its content fully fit into view (e.g. Raidlead). Static content heights for the fixed
-- tabs; Loot Council and WoWUtils are measured live because the amber raid box (wrapped text)
-- and the boss list (row count) vary. The child height is floored to the visible height so the
-- scroll range collapses to zero when everything fits. Heights include headroom for large
-- content fonts where a title's wrap height feeds into the layout (Automation's AutoLog title).
local PANEL_CONTENT_HEIGHTS = {
    [1] = 475, -- Automation: promote/invite card + AutoLog title + card
    [2] = 398, -- Raidlead: bar-settings card (180) + keybinds card (168) + gaps
    [3] = 190, -- BuffCheck: one 160 card
    [4] = 555, -- Settings: two half cards + color card + profiles card
}
function KART.UpdateScrollRange()
    local tab = KART.CurrentTab
    if not tab then return end
    local h = PANEL_CONTENT_HEIGHTS[tab]
    if tab == 5 then
        -- 292 = prefs card block above the raid box + buttons below it + bottom padding
        local rb = KART.LC and KART.LC.RaidBox
        h = 292 + ((rb and rb:GetHeight()) or 420)
    elseif tab == 6 then
        -- 293 = import card block + separator/headers above the boss list + bottom padding
        local bl = KART.WU and KART.WU.bossListFrame
        h = 293 + ((bl and bl:GetHeight()) or 24)
    end
    scrollChild:SetHeight(math.max(h or 750, scrollFrame:GetHeight()))
    -- Clamp instead of hard-resetting, so restyles (font slider) don't yank the view to the top.
    local maxScroll = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    end
    -- No scrollbar when there is nothing to scroll.
    if contentScrollBar then contentScrollBar:SetShown(maxScroll > 0) end
end

-- 5. Raidlead Panel Inhalt (Hier binden wir die RaidleadBar ein!)
-- Tab titles are fixed header-zone FontStrings (KART.CreateTabTitle), outside the scroll
-- region; every tab's first card starts uniformly at -12 inside the scroll child, which
-- itself begins just below the artwork's baked divider line.
KART.CreateTabTitle(2, L.LABEL_RAIDLEAD_TOOLS)

-- Card groups all Raidlead Bar settings into one visually distinct panel instead of leaving
-- checkboxes/slider floating directly on the tab background.
local rlCard = KART.CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -12)
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
KART.PullSlider = KART.CreateSettingsSlider(rlCard, L.SET_PULL_TIMER, 5, 30, "pullTimerDuration", -130, "KART_PullTimerSlider", L.DESC_PULL_TIMER, true)

-- Keybind card: one row per bindable Raidlead Bar action (Task list: KART.KeybindActions).
local kbCard = KART.CreateCard(KART.RaidleadPanel)
kbCard:SetPoint("TOPLEFT", rlCard, "BOTTOMLEFT", 0, -16)
kbCard:SetSize(500, 168)

local kbTitle = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
kbTitle:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, -14)
kbTitle:SetText(L.LABEL_RL_KEYBINDS)
table.insert(KART.DynamicLabels, kbTitle)

KART.KeybindButtons = {}
local kbLabels = {
    readyCheck = L.KB_READYCHECK,
    clearWorldMarkers = L.KB_CLEARWM,
    pullTimer = L.KB_PULLTIMER,
    buffCheckToggle = L.KB_BUFFCHECK,
}

-- Invisible key-listener used only while a bind-button is in capture mode; created once and
-- reused for whichever button is currently capturing (only one capture can be active at a time).
local kbListener = CreateFrame("Frame", nil, kbCard)
kbListener:Hide()
kbListener:EnableKeyboard(true)
kbListener:SetPropagateKeyboardInput(false)

local function StopCapture(activeBtn)
    kbListener:Hide()
    kbListener:SetScript("OnKeyDown", nil)
    if activeBtn then
        local current = KART_Settings and KART_Settings.keybinds and KART_Settings.keybinds[activeBtn.actionKey]
        activeBtn.text:SetText(current and current ~= "" and current or L.KB_NOT_BOUND)
    end
end

local function StartCapture(btn)
    btn.text:SetText(L.KB_PRESS_KEY)
    kbListener:Show()
    kbListener:SetScript("OnKeyDown", function(_, keyPressed)
        if keyPressed == "ESCAPE" then
            StopCapture(btn)
            return
        end
        -- Ignore bare modifier presses — wait for the actual key that completes the chord.
        if keyPressed == "LSHIFT" or keyPressed == "RSHIFT"
            or keyPressed == "LCTRL" or keyPressed == "RCTRL"
            or keyPressed == "LALT" or keyPressed == "RALT" then
            return
        end
        local binding = keyPressed
        if IsShiftKeyDown() then binding = "SHIFT-" .. binding end
        if IsControlKeyDown() then binding = "CTRL-" .. binding end
        if IsAltKeyDown() then binding = "ALT-" .. binding end
        KART_Settings.keybinds[btn.actionKey] = binding
        KART.ApplyKeybinds()
        StopCapture(btn)
    end)
end

local kbRowLabels = {}
for i, action in ipairs(KART.KeybindActions) do
    local yOff = -38 - (i - 1) * 30

    local label = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, yOff)
    label:SetText(kbLabels[action.key])
    table.insert(KART.DynamicLabels, label)
    kbRowLabels[action.key] = label

    -- KART_Settings doesn't exist yet at this point in addon load (see load-order note above) —
    -- use the static placeholder; Step 2 below syncs the real value once ADDON_LOADED fires.
    local btn = KART.CreateModernButton(kbCard, L.KB_NOT_BOUND, L.DESC_KEYBINDS)
    btn:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 260, yOff + 6)
    btn:SetSize(150, 22)
    btn.actionKey = action.key
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then
            self.text:SetText(L.KB_NOT_IN_COMBAT)
            C_Timer.After(1, function()
                local current = KART_Settings and KART_Settings.keybinds and KART_Settings.keybinds[self.actionKey]
                self.text:SetText(current and current ~= "" and current or L.KB_NOT_BOUND)
            end)
            return
        end
        if button == "RightButton" then
            KART_Settings.keybinds[self.actionKey] = nil
            KART.ApplyKeybinds()
            self.text:SetText(L.KB_NOT_BOUND)
        else
            StartCapture(self)
        end
    end)
    KART.KeybindButtons[action.key] = btn
end

-- 6. BuffChecker Panel Inhalt
KART.CreateTabTitle(3, L.LABEL_BUFFCHECK_SETTINGS)

local bcCard = KART.CreateCard(KART.BuffCheckPanel)
bcCard:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -12)
bcCard:SetSize(500, 160)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
-- Labels must not cross into the neighboring column / past the card edge (FontStrings don't clip).
KART.CbBcModuleEnabled = KART.CreateSettingsCheckbox(bcCard, "KART_BcModuleEnabled", L.SET_BC_MODULE_ENABLED, "bcModuleEnabled", -20, nil, L.DESC_BC_MODULE_ENABLED)
KART.CbBcModuleEnabled.text:SetWidth(190)
KART.CbBcModuleEnabled.text:SetJustifyH("LEFT")

KART.CbShowBuffCheck = KART.CreateSettingsCheckbox(bcCard, "KART_ShowBuffCheck", L.SET_BC_READYCHECK, "showBuffCheck", -50, nil, L.DESC_BC_READYCHECK)
KART.CbShowBuffCheck.text:SetWidth(190)
KART.CbShowBuffCheck.text:SetJustifyH("LEFT")

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
KART.SldCombatDelay = KART.CreateSettingsSlider(bcCard, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -90, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY, true)
KART.SldCombatDelay:ClearAllPoints()
KART.SldCombatDelay:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -106)

-- 6. Automation panel: promote/invite settings grouped into a card.
KART.CreateTabTitle(1, L.TAB_PROMOTE)

local autoCard = KART.CreateCard(KART.PromotePanel)
autoCard:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -12)
autoCard:SetSize(500, 195)

local promLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promLabel:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 20, -15)
promLabel:SetText(L.LABEL_PROMOTE_NAMES)
table.insert(KART.DynamicLabels, promLabel)

KART.PromoteEditBox = KART.CreateStyledEditBox(autoCard, "KART_PromoteEditBox")
KART.PromoteEditBox:SetSize(460, 28)
KART.PromoteEditBox:SetPoint("TOPLEFT", promLabel, "BOTTOMLEFT", 0, -8)
KART.PromoteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.promoteNames = self:GetText()
    KART.UpdateCache()
end) -- KART_Settings ist eine SavedVariable

local invLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
invLabel:SetPoint("TOPLEFT", KART.PromoteEditBox, "BOTTOMLEFT", 0, -14)
invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
table.insert(KART.DynamicLabels, invLabel)

KART.InviteEditBox = KART.CreateStyledEditBox(autoCard, "KART_InviteEditBox")
KART.InviteEditBox:SetSize(460, 28)
KART.InviteEditBox:SetPoint("TOPLEFT", invLabel, "BOTTOMLEFT", 0, -8)
KART.InviteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.inviteKeywords = self:GetText()
    KART.UpdateCache()
end)

KART.CbAutoRaid = KART.CreateSettingsCheckbox(autoCard, "KART_AutoRaidCheck", L.SET_AUTO_RAID, "autoConvertToRaid", -160, nil, L.DESC_AUTO_RAID)
KART.CbAutoRaid.text:SetWidth(190)
KART.CbAutoRaid.text:SetJustifyH("LEFT")
KART.CbInviteViaGuildChat = KART.CreateSettingsCheckbox(autoCard, "KART_InviteViaGuildChatCheck", L.SET_INVITE_VIA_GUILD_CHAT, "inviteViaGuildChat", -160, nil, L.DESC_INVITE_VIA_GUILD_CHAT)
KART.CbInviteViaGuildChat:ClearAllPoints()
KART.CbInviteViaGuildChat:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 260, -160)
KART.CbInviteViaGuildChat.text:SetWidth(192)
KART.CbInviteViaGuildChat.text:SetJustifyH("LEFT")

-- Auto Combat Log card: content filters for AutoLog.lua. Widget callbacks re-evaluate
-- immediately so toggling a filter while already inside an instance takes effect without
-- re-zoning (including stopping an addon-owned log when the master switch goes off).
local alTitle = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alTitle:SetPoint("TOPLEFT", autoCard, "BOTTOMLEFT", 0, -18)
alTitle:SetText(L.LABEL_AUTOLOG)
table.insert(KART.DynamicLabels, alTitle)

local alCard = KART.CreateCard(KART.PromotePanel)
alCard:SetPoint("TOPLEFT", alTitle, "BOTTOMLEFT", 0, -10)
alCard:SetSize(500, 200)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.CreateSettingsCheckbox(alCard, "KART_AlEnabled", L.SET_AL_ENABLED, "autoLogEnabled", -20, AutoLogChanged, L.DESC_AL_ENABLED)
KART.CbAlRaidLFR = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidLFR", L.SET_AL_RAID_LFR, "autoLogRaidLFR", -50, AutoLogChanged)
KART.CbAlRaidNormal = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidNormal", L.SET_AL_RAID_NORMAL, "autoLogRaidNormal", -80, AutoLogChanged)
KART.CbAlRaidHeroic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidHeroic", L.SET_AL_RAID_HEROIC, "autoLogRaidHeroic", -110, AutoLogChanged)
KART.CbAlRaidMythic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidMythic", L.SET_AL_RAID_MYTHIC, "autoLogRaidMythic", -140, AutoLogChanged)
KART.CbAlMythicPlus = KART.CreateSettingsCheckbox(alCard, "KART_AlMythicPlus", L.SET_AL_MPLUS, "autoLogMythicPlus", -50, AutoLogChanged)
KART.CbAlMythicPlus:ClearAllPoints()
KART.CbAlMythicPlus:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -50)
KART.CbAlMythicPlus.text:SetWidth(192)
KART.CbAlMythicPlus.text:SetJustifyH("LEFT")
KART.SldAlMinKey = KART.CreateSettingsSlider(alCard, L.SET_AL_MIN_KEY, 2, 20, "autoLogMinKey", -80, "KART_AlMinKeySlider", L.DESC_AL_MIN_KEY, true)
KART.SldAlMinKey:HookScript("OnValueChanged", AutoLogChanged)
KART.SldAlMinKey:ClearAllPoints()
KART.SldAlMinKey:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -96)
KART.CbAlDungeons = KART.CreateSettingsCheckbox(alCard, "KART_AlDungeons", L.SET_AL_DUNGEONS, "autoLogDungeons", -140, AutoLogChanged)
KART.CbAlDungeons:ClearAllPoints()
KART.CbAlDungeons:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -140)
KART.CbAlDungeons.text:SetWidth(192)
KART.CbAlDungeons.text:SetJustifyH("LEFT")
KART.CbAlDelves = KART.CreateSettingsCheckbox(alCard, "KART_AlDelves", L.SET_AL_DELVES, "autoLogDelves", -170, AutoLogChanged)
KART.CbAlDelves:ClearAllPoints()
KART.CbAlDelves:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -170)
KART.CbAlDelves.text:SetWidth(192)
KART.CbAlDelves.text:SetJustifyH("LEFT")

-- 7. Settings Panel Inhalt
KART.CreateTabTitle(4, L.LABEL_GENERAL_SETTINGS)

-- Card: window-level interface options
local ifCard = KART.CreateCard(KART.SettingsPanel)
ifCard:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -12)
ifCard:SetSize(242, 215)

KART.CbMinimap = KART.CreateSettingsCheckbox(ifCard, "KART_MinimapCheck", L.SET_MINIMAP, "showMinimapIcon", -20, function()
    KART.UpdateMinimapButton()
end, L.DESC_MINIMAP)
KART.SldUiScale = KART.CreateSettingsSlider(ifCard, L.SET_UI_SCALE, 50, 150, "uiScale", -60, "KART_UiScaleSlider", L.DESC_UI_SCALE)
-- Applying SetScale live while dragging rescales the window under the cursor, which shifts the
-- cursor's position on the track and makes the thumb jump back and forth. UpdateStyles skips the
-- scale during the drag (checks isDragging, set by the factory); apply the final value on release.
-- This hook runs after the factory's own OnMouseUp hook, so isDragging is already false here.
KART.SldUiScale:HookScript("OnMouseUp", function() KART.UpdateStyles() end)
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
KART.BtnLang = KART.CreateModernButton(txtCard, L.BTN_LANGUAGE_PREFIX .. L.LANG_AUTO, L.DESC_LANGUAGE)
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
    -- Full wipe, not a per-key overwrite: keys without a Defaults entry (window positions,
    -- sizes) must reset too. Tables are deep-copied so KART.Defaults itself is never shared
    -- into (and later mutated through) KART_Settings.
    wipe(KART_Settings)
    for k, v in pairs(KART.Defaults) do
        KART_Settings[k] = type(v) == "table" and KART.DeepCopy(v) or v
    end
    ReloadUI() -- Einfachste Methode um alle UI Werte zurückzusetzen
end)

-- Card: settings profiles (save/switch/delete named KART_Settings snapshots)
local profCard = KART.CreateCard(KART.SettingsPanel)
profCard:SetPoint("TOPLEFT", colCard, "BOTTOMLEFT", 0, -20)
profCard:SetSize(500, 100)

local profTitle = profCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profTitle:SetPoint("TOPLEFT", profCard, "TOPLEFT", 20, -14)
profTitle:SetText(L.LABEL_PROFILES)
table.insert(KART.DynamicLabels, profTitle)

KART.BtnProfile = KART.CreateModernButton(profCard, L.PROFILE_LABEL_PREFIX .. L.PROFILE_NONE)
KART.BtnProfile:SetPoint("TOPLEFT", profCard, "TOPLEFT", 20, -34)
KART.BtnProfile:SetSize(200, 25)
KART.BtnProfile:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.LABEL_PROFILES)
        local names = {}
        for name in pairs(KART_Profiles) do table.insert(names, name) end
        table.sort(names)
        if #names == 0 then
            local noneItem = rootDescription:CreateButton(L.PROFILE_NONE_SAVED, function() end)
            noneItem:SetEnabled(false)
        end
        for _, name in ipairs(names) do
            rootDescription:CreateButton(name, function()
                KART.LoadProfile(name)
            end)
        end
    end)
end)

KART.BtnProfileSaveNew = KART.CreateModernButton(profCard, L.BTN_PROFILE_SAVE_NEW, L.DESC_PROFILE_SAVE_NEW)
KART.BtnProfileSaveNew:SetPoint("TOPLEFT", profCard, "TOPLEFT", 20, -69)
KART.BtnProfileSaveNew:SetScript("OnClick", function()
    KART.ShowSaveProfileDialog()
end)

KART.BtnProfileSave = KART.CreateModernButton(profCard, L.BTN_PROFILE_SAVE, L.DESC_PROFILE_SAVE)
KART.BtnProfileSave:SetPoint("TOPLEFT", KART.BtnProfileSaveNew, "TOPRIGHT", 10, 0)
KART.BtnProfileSave:SetScript("OnClick", function()
    local name = KART_Settings.activeProfile
    if not name then return end
    KART.SaveProfile(name)
    KART.RefreshProfileButton()
end)

KART.BtnProfileDelete = KART.CreateModernButton(profCard, L.BTN_PROFILE_DELETE, L.DESC_PROFILE_DELETE)
KART.BtnProfileDelete:SetPoint("TOPLEFT", KART.BtnProfileSave, "TOPRIGHT", 10, 0)
KART.BtnProfileDelete:SetScript("OnClick", function()
    local name = KART_Settings.activeProfile
    if not name then return end
    StaticPopupDialogs["KART_PROFILE_DELETE_CONFIRM"].text = KART.L.PROFILE_DELETE_CONFIRM_TEXT
    StaticPopup_Show("KART_PROFILE_DELETE_CONFIRM", name, nil, { name = name })
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

-- 9. Settings search: small always-visible button + popout (edit box + up to 8 result rows).
-- Positioned left of the close button, in the same header row as the active tab's title, well
-- clear of the close button's hit area (closeBtn spans roughly x -45..-9, y -42..-6 from
-- clickArea's TOPRIGHT) and of the baked logo/title zone above y -22.
local searchBtn = KART.CreateModernButton(clickArea, L.BTN_SEARCH, L.DESC_SEARCH)
searchBtn:SetSize(70, 22)
searchBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -70, -20)

local searchPopout = CreateFrame("Frame", nil, clickArea, "BackdropTemplate")
searchPopout:SetPoint("TOPRIGHT", searchBtn, "BOTTOMRIGHT", 0, -6)
searchPopout:SetSize(260, 40)
searchPopout:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
searchPopout:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
searchPopout:SetBackdropBorderColor(0, 0, 0, 1)
KART.RegisterStrataFrame(searchPopout, true) -- one stratum above the windows, follows the setting
searchPopout:Hide()
KART.ApplyRoundedMask(searchPopout, KART.Theme.CORNER_RADIUS_SM)

local searchBox = KART.CreateStyledEditBox(searchPopout, "KART_SearchBox")
searchBox:SetSize(240, 26)
searchBox:SetPoint("TOPLEFT", searchPopout, "TOPLEFT", 10, -8)
searchBox:SetMaxLetters(64)

-- 8 pooled, reusable result rows — created once, re-labeled and shown/hidden per search rather
-- than creating/destroying frames on every keystroke.
local RESULT_ROW_COUNT = 8
local resultRows = {}
for i = 1, RESULT_ROW_COUNT do
    local row = CreateFrame("Button", nil, searchPopout, "BackdropTemplate")
    row:SetSize(240, 20)
    row:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -4 - (i - 1) * 22)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0, 0, 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function(self)
        local r, g, b = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, b, 0.45)
        self:SetBackdropColor(dr, dg, db, 0.5)
    end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
    row:Hide()
    resultRows[i] = row
end

local searchIndex = {}
local function CloseSearchPopout()
    searchPopout:Hide()
    searchBox:SetText("")
    searchBox:ClearFocus()
end
KART.HideSearchPopout = CloseSearchPopout

local function FilterSearch(query)
    query = query:lower()
    local shown = 0
    if query ~= "" then
        for _, entry in ipairs(searchIndex) do
            if shown >= RESULT_ROW_COUNT then break end
            if entry.text:lower():find(query, 1, true) then
                shown = shown + 1
                local row = resultRows[shown]
                row.text:SetText(entry.text)
                row.entry = entry
                row:Show()
            end
        end
    end
    for i = shown + 1, RESULT_ROW_COUNT do
        resultRows[i]:Hide()
    end
    searchPopout:SetHeight(40 + shown * 22)
end

for _, row in ipairs(resultRows) do
    row:SetScript("OnClick", function(self)
        if self.entry then KART.JumpToSearchResult(self.entry) end
    end)
end

searchBox:SetScript("OnTextChanged", function(self)
    FilterSearch(self:GetText())
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    CloseSearchPopout()
end)

searchBtn:SetScript("OnClick", function()
    if searchPopout:IsShown() then
        CloseSearchPopout()
    else
        searchIndex = KART.BuildSearchIndex()
        FilterSearch("")
        searchPopout:Show()
        searchBox:SetFocus()
    end
end)

-- Translucent highlight shown briefly over a search result's matched label. One shared frame,
-- re-parented and re-anchored per jump rather than creating a new frame per search.
local searchHighlight = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
searchHighlight:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
searchHighlight:Hide()

-- Switches to the result's tab, scrolls the shared content frame so the matched label sits
-- ~40px below the viewport's top edge (not flush against it), and briefly highlights the label.
function KART.JumpToSearchResult(entry)
    KART.ShowTab(entry.tabIndex)

    local widget = entry.widget
    local top = widget:GetTop()
    local scrollTop = scrollFrame:GetTop()
    if top and scrollTop then
        local delta = top - scrollTop + 40
        local maxScroll = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local newScroll = math.max(0, math.min(scrollFrame:GetVerticalScroll() + delta, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end

    searchHighlight:SetParent(widget:GetParent())
    searchHighlight:ClearAllPoints()
    searchHighlight:SetPoint("TOPLEFT", widget, "TOPLEFT", -6, 6)
    searchHighlight:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 6, -6)
    searchHighlight:SetFrameLevel(widget:GetParent():GetFrameLevel() + 10)
    local r, g, b = KART.Theme.AccentColor()
    searchHighlight:SetBackdropColor(r, g, b, 0.35)
    searchHighlight:Show()
    C_Timer.After(1.5, function() searchHighlight:Hide() end)

    KART.HideSearchPopout()
end

-- Re-applies every static text in this file from KART.L once the saved language is known
-- (see KART.RegisterLocaleRefresher in Utils.lua). Dynamic texts (BtnFont/BtnLang/BtnProfile
-- labels, keybind button captions, strata slider value) are handled by KART.SyncSettingsToUI.
KART.RegisterLocaleRefresher(function()
    local L = KART.L

    -- Sidebar tabs + fixed header titles
    KART.BtnPromote.text:SetText(L.TAB_PROMOTE)
    KART.BtnRaidlead.text:SetText(L.TAB_RAIDLEAD)
    KART.BtnBuffCheck.text:SetText(L.TAB_BUFFCHECK)
    KART.BtnLootCouncil.text:SetText(L.TAB_LOOTCOUNCIL)
    KART.BtnWoWUtils.text:SetText(L.TAB_WOWUTILS)
    KART.BtnSettings.text:SetText(L.TAB_SETTINGS)
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.LABEL_RAIDLEAD_TOOLS)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    -- TabTitles[5]/[6] belong to LootCouncil.lua / Invite.lua and are refreshed there.

    -- Raidlead tab
    KART.CbActivate.text:SetText(L.SET_RL_ACTIVATE)   KART.CbActivate.tooltipText = L.DESC_RL_ACTIVATE
    KART.CbLock.text:SetText(L.SET_RL_LOCK)           KART.CbLock.tooltipText = L.DESC_RL_LOCK
    KART.CbAutoHide.text:SetText(L.SET_RL_AUTOHIDE)   KART.CbAutoHide.tooltipText = L.DESC_RL_AUTOHIDE
    KART.PullSlider.title:SetText(L.SET_PULL_TIMER)   KART.PullSlider.tooltipText = L.DESC_PULL_TIMER
    kbTitle:SetText(L.LABEL_RL_KEYBINDS)
    local kbKeyByAction = {
        readyCheck = "KB_READYCHECK", clearWorldMarkers = "KB_CLEARWM",
        pullTimer = "KB_PULLTIMER", buffCheckToggle = "KB_BUFFCHECK",
    }
    for actionKey, label in pairs(kbRowLabels) do
        label:SetText(L[kbKeyByAction[actionKey]])
    end
    for _, btn in pairs(KART.KeybindButtons) do
        btn.tooltipText = L.DESC_KEYBINDS
    end

    -- BuffCheck tab
    KART.CbBcModuleEnabled.text:SetText(L.SET_BC_MODULE_ENABLED)  KART.CbBcModuleEnabled.tooltipText = L.DESC_BC_MODULE_ENABLED
    KART.CbShowBuffCheck.text:SetText(L.SET_BC_READYCHECK)        KART.CbShowBuffCheck.tooltipText = L.DESC_BC_READYCHECK
    KART.CbGrayOffline.text:SetText(L.SET_GRAY_OFFLINE)           KART.CbGrayOffline.tooltipText = L.DESC_GRAY_OFFLINE
    KART.BtnBuffPreview.text:SetText(L.BTN_BUFF_PREVIEW)
    KART.SldBuffCheckAlpha.title:SetText(L.SET_BC_ALPHA)          KART.SldBuffCheckAlpha.tooltipText = L.DESC_BC_ALPHA
    KART.SldCombatDelay.title:SetText(L.SET_BC_COMBAT_DELAY)      KART.SldCombatDelay.tooltipText = L.DESC_BC_COMBAT_DELAY

    -- Automation tab
    promLabel:SetText(L.LABEL_PROMOTE_NAMES)
    invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
    KART.CbAutoRaid.text:SetText(L.SET_AUTO_RAID)                 KART.CbAutoRaid.tooltipText = L.DESC_AUTO_RAID
    KART.CbInviteViaGuildChat.text:SetText(L.SET_INVITE_VIA_GUILD_CHAT)
    KART.CbInviteViaGuildChat.tooltipText = L.DESC_INVITE_VIA_GUILD_CHAT
    alTitle:SetText(L.LABEL_AUTOLOG)
    KART.CbAlEnabled.text:SetText(L.SET_AL_ENABLED)               KART.CbAlEnabled.tooltipText = L.DESC_AL_ENABLED
    KART.CbAlRaidLFR.text:SetText(L.SET_AL_RAID_LFR)
    KART.CbAlRaidNormal.text:SetText(L.SET_AL_RAID_NORMAL)
    KART.CbAlRaidHeroic.text:SetText(L.SET_AL_RAID_HEROIC)
    KART.CbAlRaidMythic.text:SetText(L.SET_AL_RAID_MYTHIC)
    KART.CbAlMythicPlus.text:SetText(L.SET_AL_MPLUS)
    KART.CbAlDungeons.text:SetText(L.SET_AL_DUNGEONS)
    KART.CbAlDelves.text:SetText(L.SET_AL_DELVES)
    KART.SldAlMinKey.title:SetText(L.SET_AL_MIN_KEY)              KART.SldAlMinKey.tooltipText = L.DESC_AL_MIN_KEY

    -- Settings tab
    KART.CbMinimap.text:SetText(L.SET_MINIMAP)                    KART.CbMinimap.tooltipText = L.DESC_MINIMAP
    KART.SldUiScale.title:SetText(L.SET_UI_SCALE)                 KART.SldUiScale.tooltipText = L.DESC_UI_SCALE
    KART.SldBgAlpha.title:SetText(L.SET_BG_ALPHA)                 KART.SldBgAlpha.tooltipText = L.DESC_BG_ALPHA
    KART.SldFrameStrata.title:SetText(L.SET_FRAME_STRATA)         KART.SldFrameStrata.tooltipText = L.DESC_FRAME_STRATA
    KART.SldMenuSize.title:SetText(L.LABEL_FONT_SIZE_MENU)        KART.SldMenuSize.tooltipText = L.DESC_MENU_SIZE
    KART.SldContentSize.title:SetText(L.LABEL_FONT_SIZE_CONTENT)  KART.SldContentSize.tooltipText = L.DESC_CONTENT_SIZE
    KART.BtnFont.tooltipText = L.DESC_SELECT_FONT
    KART.BtnLang.tooltipText = L.DESC_LANGUAGE
    KART.BtnAccentColor.text:SetText(L.BTN_ACCENT_COLOR)          KART.BtnAccentColor.tooltipText = L.DESC_ACCENT_COLOR
    KART.BtnReset.text:SetText(L.BTN_RESET)                       KART.BtnReset.tooltipText = L.DESC_RESET
    profTitle:SetText(L.LABEL_PROFILES)
    KART.BtnProfileSaveNew.text:SetText(L.BTN_PROFILE_SAVE_NEW)   KART.BtnProfileSaveNew.tooltipText = L.DESC_PROFILE_SAVE_NEW
    KART.BtnProfileSave.text:SetText(L.BTN_PROFILE_SAVE)          KART.BtnProfileSave.tooltipText = L.DESC_PROFILE_SAVE
    KART.BtnProfileDelete.text:SetText(L.BTN_PROFILE_DELETE)      KART.BtnProfileDelete.tooltipText = L.DESC_PROFILE_DELETE

    -- Header search
    searchBtn.text:SetText(L.BTN_SEARCH)
    searchBtn.tooltipText = L.DESC_SEARCH
end)
