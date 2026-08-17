local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local L = KART.L
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Every checkbox/slider below is built at file load time, before Core.lua's ADDON_LOADED handler
-- has created KART_Settings -- passing the table directly here would freeze each widget onto nil
-- forever. Passed as `store` instead of the table itself, so KAUI resolves the current global at
-- click/drag time rather than capturing it now (see ResolveStore in KAUI-1.0.lua).
local function SettingsStore() return KART_Settings end

-- 1. Tab-Wechsel Logik (wird in KART Tabelle gespeichert)
function KART.ShowTab(tabIndex)
    local panels = {
        KART.PromotePanel,
        KART.RaidleadPanel,
        KART.BuffCheckPanel,
        KART.SettingsPanel,
        KART.WoWUtilsPanel,
    }
    for i, panel in ipairs(panels) do
        if panel then panel:SetShown(i == tabIndex) end
    end

    local buttons = {
        KART.BtnPromote,
        KART.BtnRaidlead,
        KART.BtnBuffCheck,
        KART.BtnSettings,
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
-- Clamped, like every Blizzard frame. Without it the window can be dragged past the edge of the
-- game window -- reported from a live test in windowed mode on two monitors, where the desktop
-- beyond the edge is real screen and nothing stops the drag. The drag is started from clickArea
-- further down, but the clamp belongs to the frame that actually MOVES.
mainFrame:SetClampedToScreen(true)

mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND")
mainFrame.bg:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-bg-dark.png")
mainFrame.bg:SetAllPoints()

KART.UI:RegisterStrataFrame(mainFrame)
mainFrame:Hide()
KART.UI:AddShowFade(mainFrame)

-- Allows closing the whole KART window with the ESC key
KART.RegisterEscapeFrame(mainFrame)
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
    KART.UI:RegisterLabel(fs)
    KART.TabTitles[tabIndex] = fs
    return fs
end

-- 3. Sidebar menu and tabs
-- Tabs start below the baked logo/title/underline zone of the artwork.
KART.BtnPromote = KART.UI:CreateTabButton(clickArea, L.TAB_PROMOTE)
KART.BtnPromote:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 12, -75)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.UI:CreateTabButton(clickArea, L.TAB_RAIDLEAD)
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.UI:CreateTabButton(clickArea, L.TAB_BUFFCHECK)
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnWoWUtils = KART.UI:CreateTabButton(clickArea, L.TAB_WOWUTILS)
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(5) end)

-- The Settings tab must always be the last entry in the sidebar. When adding a new tab
-- button, anchor it above this one (i.e. insert it between the previous last tab and
-- Settings, and re-anchor Settings to the new button).
KART.BtnSettings = KART.UI:CreateTabButton(clickArea, L.TAB_SETTINGS)
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

KART.WoWUtilsPanel = CreateFrame("Frame", nil, scrollChild)
KART.WoWUtilsPanel:SetAllPoints()
KART.WoWUtilsPanel:Hide()

-- Scrollbar Thumb, accent-tinted via KART.UI's accent-texture registry
local scrollThumb = KART.UI:StripScrollbarTextures(scrollFrame)
if scrollThumb then scrollThumb:SetSize(8, 30) end
KART.UI:RegisterAccentTexture(scrollThumb, 0.6)

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
-- tabs; WoWUtils is measured live because the boss list (row count) varies. The child height
-- is floored to the visible height so the scroll range collapses to zero when everything fits.
-- Heights include headroom for large content fonts where a title's wrap height feeds into the
-- layout (Automation's AutoLog title).
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
        -- Import card + separator/headers above the boss list + bottom padding.
        local bl = KART.WU and KART.WU.bossListFrame
        h = 270 + ((bl and bl:GetHeight()) or 24)
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
local rlCard = KART.UI:CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -12)
rlCard:SetSize(500, 210)

-- Checkbox zur Aktivierung
KART.CbActivate = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarCheck", label = L.SET_RL_ACTIVATE,
    store = SettingsStore, key = "showRaidleadBar", y = -20,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
    end,
    tooltip = L.DESC_RL_ACTIVATE,
})

-- Checkbox zum Sperren
KART.CbLock = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarLockCheck", label = L.SET_RL_LOCK,
    store = SettingsStore, key = "lockRaidleadBar", y = -50,
    tooltip = L.DESC_RL_LOCK,
})

-- Checkbox für Auto-Hide
KART.CbAutoHide = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarAutoHideCheck", label = L.SET_RL_AUTOHIDE,
    store = SettingsStore, key = "autoHideRaidleadBar", y = -80,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
    end,
    tooltip = L.DESC_RL_AUTOHIDE,
})

-- Ready-check reason prompt. Sits on this tab because the ready check itself is a Raidlead Bar
-- button; the dialog it controls lives in Core.lua (KART.ShowReadyCheckReasonDialog).
KART.CbRcReasonDialog = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RcReasonDialogCheck", label = L.SET_RL_RC_REASON,
    store = SettingsStore, key = "rcReasonDialog", y = -110,
    tooltip = L.DESC_RL_RC_REASON,
})

-- Pull-Timer Slider: the pull button (RaidleadBar.lua) reads pullTimerDuration
-- at click time, so no macrotext attribute needs updating here anymore.
KART.PullSlider = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_PullTimerSlider", label = L.SET_PULL_TIMER,
    min = 5, max = 30, store = SettingsStore, key = "pullTimerDuration", y = -160,
    tooltip = L.DESC_PULL_TIMER,
})

-- Keybind card: one row per bindable Raidlead Bar action (Task list: KART.KeybindActions).
local kbCard = KART.UI:CreateCard(KART.RaidleadPanel)
kbCard:SetPoint("TOPLEFT", rlCard, "BOTTOMLEFT", 0, -16)
kbCard:SetSize(500, 168)

local kbTitle = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
kbTitle:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, -14)
kbTitle:SetText(L.LABEL_RL_KEYBINDS)
KART.UI:RegisterLabel(kbTitle)

-- [actionKey] = its bind button. Read back by the locale refresher, by KART.SyncSettingsToUI (which
-- repaints every caption after a profile load) and by StartCapture, which updates the caption of a
-- DIFFERENT action when it takes that action's key away. One registry — don't add a second local one.
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
KART.KeybindListener = kbListener -- so the capture rules can be exercised from tests/test_mainframe.lua
kbListener:Hide()
kbListener:EnableKeyboard(true)
kbListener:SetPropagateKeyboardInput(false)

-- The bind button currently in capture mode, if any (only one capture is active at a time).
local kbActiveBtn

local function StopCapture(activeBtn)
    kbListener:Hide()
    kbListener:SetScript("OnKeyDown", nil)
    kbActiveBtn = nil
    if activeBtn then
        local current = KART_Settings and KART_Settings.keybinds and KART_Settings.keybinds[activeBtn.actionKey]
        activeBtn.text:SetText(current and current ~= "" and current or L.KB_NOT_BOUND)
    end
end

local function StartCapture(btn)
    -- Cancel any capture already in progress on a different button, so its caption doesn't stay
    -- stuck on "press a key".
    if kbActiveBtn and kbActiveBtn ~= btn then
        StopCapture(kbActiveBtn)
    end
    kbActiveBtn = btn
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
        -- Take the key off whoever else holds it, the way Blizzard's own keybind UI does. Two
        -- actions sharing a binding isn't something KART.ApplyKeybinds can honour: it sets one
        -- override per action in list order, so the later action simply won and the earlier button
        -- went on displaying a key that did nothing. Stealing it makes the settings tell the truth.
        for _, other in ipairs(KART.KeybindActions) do
            if other.key ~= btn.actionKey and KART_Settings.keybinds[other.key] == binding then
                KART_Settings.keybinds[other.key] = nil
                local otherBtn = KART.KeybindButtons[other.key]
                if otherBtn then otherBtn.text:SetText(L.KB_NOT_BOUND) end
            end
        end
        KART_Settings.keybinds[btn.actionKey] = binding
        KART.ApplyKeybinds()
        StopCapture(btn)
    end)
end

-- Cancel an in-progress capture when the panel hides (tab switch or window close) — otherwise the
-- key listener silently resumes on reopen and binds the next keypress the player makes.
kbCard:HookScript("OnHide", function()
    if kbActiveBtn then StopCapture(kbActiveBtn) end
end)

local kbRowLabels = {}
for i, action in ipairs(KART.KeybindActions) do
    local yOff = -38 - (i - 1) * 30

    local label = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, yOff)
    label:SetText(kbLabels[action.key])
    KART.UI:RegisterLabel(label)
    kbRowLabels[action.key] = label

    -- KART_Settings doesn't exist yet at this point in addon load (see load-order note above) —
    -- use the static placeholder; Step 2 below syncs the real value once ADDON_LOADED fires.
    local btn = KART.UI:CreateModernButton(kbCard, L.KB_NOT_BOUND, L.DESC_KEYBINDS)
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

local bcCard = KART.UI:CreateCard(KART.BuffCheckPanel)
bcCard:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -12)
bcCard:SetSize(500, 160)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
-- Labels must not cross into the neighboring column / past the card edge (FontStrings don't clip).
KART.CbBcModuleEnabled = KART.UI:CreateSettingsCheckbox(bcCard, {
    name = "KART_BcModuleEnabled", label = L.SET_BC_MODULE_ENABLED,
    store = SettingsStore, key = "bcModuleEnabled", y = -20,
    tooltip = L.DESC_BC_MODULE_ENABLED,
})
KART.CbBcModuleEnabled.text:SetWidth(190)
KART.CbBcModuleEnabled.text:SetJustifyH("LEFT")

KART.CbShowBuffCheck = KART.UI:CreateSettingsCheckbox(bcCard, {
    name = "KART_ShowBuffCheck", label = L.SET_BC_READYCHECK,
    store = SettingsStore, key = "showBuffCheck", y = -50,
    tooltip = L.DESC_BC_READYCHECK,
})
KART.CbShowBuffCheck.text:SetWidth(190)
KART.CbShowBuffCheck.text:SetJustifyH("LEFT")

KART.CbGrayOffline = KART.UI:CreateSettingsCheckbox(bcCard, {
    name = "KART_GrayOffline", label = L.SET_GRAY_OFFLINE,
    store = SettingsStore, key = "grayOffline", y = -80,
    tooltip = L.DESC_GRAY_OFFLINE,
})

KART.BtnBuffPreview = KART.UI:CreateModernButton(bcCard, L.BTN_BUFF_PREVIEW)
KART.BtnBuffPreview:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 20, -115)
KART.BtnBuffPreview:SetScript("OnClick", function()
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
        KART.UpdateBuffCheck(true)
    end
end)

KART.SldBuffCheckAlpha = KART.UI:CreateSettingsSlider(bcCard, {
    name = "KART_BuffCheckAlphaSlider", label = L.SET_BC_ALPHA,
    min = 0, max = 100, store = SettingsStore, key = "buffCheckAlpha", y = -30,
    tooltip = L.DESC_BC_ALPHA,
    onChanged = function() KART.UpdateStyles() end,
})
KART.SldBuffCheckAlpha:ClearAllPoints()
KART.SldBuffCheckAlpha:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -46)
KART.SldCombatDelay = KART.UI:CreateSettingsSlider(bcCard, {
    name = "KART_BuffCheckCombatDelaySlider", label = L.SET_BC_COMBAT_DELAY,
    min = 0, max = 30, store = SettingsStore, key = "bcCombatDelay", y = -90,
    tooltip = L.DESC_BC_COMBAT_DELAY,
})
KART.SldCombatDelay:ClearAllPoints()
KART.SldCombatDelay:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -106)

-- 7. Automation panel: promote/invite settings grouped into a card.
KART.CreateTabTitle(1, L.TAB_PROMOTE)

local autoCard = KART.UI:CreateCard(KART.PromotePanel)
autoCard:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -12)
autoCard:SetSize(500, 195)

local promLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promLabel:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 20, -15)
promLabel:SetText(L.LABEL_PROMOTE_NAMES)
KART.UI:RegisterLabel(promLabel)

KART.PromoteEditBox = KART.UI:CreateStyledEditBox(autoCard, "KART_PromoteEditBox")
KART.PromoteEditBox:SetSize(460, 28)
KART.PromoteEditBox:SetPoint("TOPLEFT", promLabel, "BOTTOMLEFT", 0, -8)
KART.PromoteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.promoteNames = self:GetText()
    KART.UpdateCache()
end) -- KART_Settings ist eine SavedVariable

local invLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
invLabel:SetPoint("TOPLEFT", KART.PromoteEditBox, "BOTTOMLEFT", 0, -14)
invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
KART.UI:RegisterLabel(invLabel)

KART.InviteEditBox = KART.UI:CreateStyledEditBox(autoCard, "KART_InviteEditBox")
KART.InviteEditBox:SetSize(460, 28)
KART.InviteEditBox:SetPoint("TOPLEFT", invLabel, "BOTTOMLEFT", 0, -8)
KART.InviteEditBox:SetScript("OnTextChanged", function(self)
    KART_Settings.inviteKeywords = self:GetText()
    KART.UpdateCache()
end)

KART.CbAutoRaid = KART.UI:CreateSettingsCheckbox(autoCard, {
    name = "KART_AutoRaidCheck", label = L.SET_AUTO_RAID,
    store = SettingsStore, key = "autoConvertToRaid", y = -160,
    tooltip = L.DESC_AUTO_RAID,
})
KART.CbAutoRaid.text:SetWidth(190)
KART.CbAutoRaid.text:SetJustifyH("LEFT")
KART.CbInviteViaGuildChat = KART.UI:CreateSettingsCheckbox(autoCard, {
    name = "KART_InviteViaGuildChatCheck", label = L.SET_INVITE_VIA_GUILD_CHAT,
    store = SettingsStore, key = "inviteViaGuildChat", y = -160,
    tooltip = L.DESC_INVITE_VIA_GUILD_CHAT,
})
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
KART.UI:RegisterLabel(alTitle)

local alCard = KART.UI:CreateCard(KART.PromotePanel)
alCard:SetPoint("TOPLEFT", alTitle, "BOTTOMLEFT", 0, -10)
alCard:SetSize(500, 200)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlEnabled", label = L.SET_AL_ENABLED,
    store = SettingsStore, key = "autoLogEnabled", y = -20,
    onChanged = AutoLogChanged, tooltip = L.DESC_AL_ENABLED,
})
KART.CbAlRaidLFR = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlRaidLFR", label = L.SET_AL_RAID_LFR,
    store = SettingsStore, key = "autoLogRaidLFR", y = -50,
    onChanged = AutoLogChanged,
})
KART.CbAlRaidNormal = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlRaidNormal", label = L.SET_AL_RAID_NORMAL,
    store = SettingsStore, key = "autoLogRaidNormal", y = -80,
    onChanged = AutoLogChanged,
})
KART.CbAlRaidHeroic = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlRaidHeroic", label = L.SET_AL_RAID_HEROIC,
    store = SettingsStore, key = "autoLogRaidHeroic", y = -110,
    onChanged = AutoLogChanged,
})
KART.CbAlRaidMythic = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlRaidMythic", label = L.SET_AL_RAID_MYTHIC,
    store = SettingsStore, key = "autoLogRaidMythic", y = -140,
    onChanged = AutoLogChanged,
})
KART.CbAlMythicPlus = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlMythicPlus", label = L.SET_AL_MPLUS,
    store = SettingsStore, key = "autoLogMythicPlus", y = -50,
    onChanged = AutoLogChanged,
})
KART.CbAlMythicPlus:ClearAllPoints()
KART.CbAlMythicPlus:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -50)
KART.CbAlMythicPlus.text:SetWidth(192)
KART.CbAlMythicPlus.text:SetJustifyH("LEFT")
KART.SldAlMinKey = KART.UI:CreateSettingsSlider(alCard, {
    name = "KART_AlMinKeySlider", label = L.SET_AL_MIN_KEY,
    min = 2, max = 20, store = SettingsStore, key = "autoLogMinKey", y = -80,
    tooltip = L.DESC_AL_MIN_KEY,
})
KART.SldAlMinKey:HookScript("OnValueChanged", AutoLogChanged)
KART.SldAlMinKey:ClearAllPoints()
KART.SldAlMinKey:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -96)
KART.CbAlDungeons = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlDungeons", label = L.SET_AL_DUNGEONS,
    store = SettingsStore, key = "autoLogDungeons", y = -140,
    onChanged = AutoLogChanged,
})
KART.CbAlDungeons:ClearAllPoints()
KART.CbAlDungeons:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -140)
KART.CbAlDungeons.text:SetWidth(192)
KART.CbAlDungeons.text:SetJustifyH("LEFT")
KART.CbAlDelves = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlDelves", label = L.SET_AL_DELVES,
    store = SettingsStore, key = "autoLogDelves", y = -170,
    onChanged = AutoLogChanged,
})
KART.CbAlDelves:ClearAllPoints()
KART.CbAlDelves:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -170)
KART.CbAlDelves.text:SetWidth(192)
KART.CbAlDelves.text:SetJustifyH("LEFT")

-- 8. Settings Panel Inhalt
KART.CreateTabTitle(4, L.LABEL_GENERAL_SETTINGS)

-- Card: window-level interface options
local ifCard = KART.UI:CreateCard(KART.SettingsPanel)
ifCard:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -12)
ifCard:SetSize(242, 215)

KART.CbMinimap = KART.UI:CreateSettingsCheckbox(ifCard, {
    name = "KART_MinimapCheck", label = L.SET_MINIMAP,
    store = SettingsStore, key = "showMinimapIcon", y = -20,
    onChanged = function()
        KART.UpdateMinimapButton()
    end,
    tooltip = L.DESC_MINIMAP,
})
KART.SldUiScale = KART.UI:CreateSettingsSlider(ifCard, {
    name = "KART_UiScaleSlider", label = L.SET_UI_SCALE,
    min = 50, max = 150, store = SettingsStore, key = "uiScale", y = -60,
    tooltip = L.DESC_UI_SCALE,
    onChanged = function() KART.UpdateStyles() end,
})
-- Applying SetScale live while dragging rescales the window under the cursor, which shifts the
-- cursor's position on the track and makes the thumb jump back and forth. UpdateStyles skips the
-- scale during the drag (checks isDragging, set by the factory); apply the final value on release.
-- This hook runs after the factory's own OnMouseUp hook, so isDragging is already false here.
KART.SldUiScale:HookScript("OnMouseUp", function() KART.UpdateStyles() end)
KART.SldBgAlpha = KART.UI:CreateSettingsSlider(ifCard, {
    name = "KART_BgAlphaSlider", label = L.SET_BG_ALPHA,
    min = 20, max = 100, store = SettingsStore, key = "bgAlpha", y = -105,
    tooltip = L.DESC_BG_ALPHA,
    onChanged = function() KART.UpdateStyles() end,
})

-- Window layer slider: value is an index into KART.StrataLevels, shown as the strata name
-- instead of the raw number (the factory's own handler writes the number first, this hook
-- overwrites it right after; OnShow covers the case where the initial SetValue doesn't fire
-- because the saved value equals the slider's current one).
KART.SldFrameStrata = KART.UI:CreateSettingsSlider(ifCard, {
    name = "KART_FrameStrataSlider", label = L.SET_FRAME_STRATA,
    min = 1, max = #KART.StrataLevels, store = SettingsStore, key = "frameStrata", y = -150,
    tooltip = L.DESC_FRAME_STRATA,
    onChanged = function() KART.UpdateStyles() end,
    valueIsText = true, -- shows the stratum NAME, so its value box stays read-only
})
local function UpdateStrataSliderText(self)
    self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
end
KART.SldFrameStrata:HookScript("OnValueChanged", UpdateStrataSliderText)
KART.SldFrameStrata:HookScript("OnShow", UpdateStrataSliderText)

-- Card: text rendering
local txtCard = KART.UI:CreateCard(KART.SettingsPanel)
txtCard:SetPoint("TOPLEFT", ifCard, "TOPRIGHT", 16, 0)
txtCard:SetSize(242, 215)

KART.SldMenuSize = KART.UI:CreateSettingsSlider(txtCard, {
    name = "KART_MenuSizeSlider", label = L.LABEL_FONT_SIZE_MENU,
    min = 8, max = 20, store = SettingsStore, key = "menuFontSize", y = -20,
    tooltip = L.DESC_MENU_SIZE,
    onChanged = function() KART.UpdateStyles() end,
})
KART.SldContentSize = KART.UI:CreateSettingsSlider(txtCard, {
    name = "KART_ContentSizeSlider", label = L.LABEL_FONT_SIZE_CONTENT,
    min = 8, max = 20, store = SettingsStore, key = "contentFontSize", y = -65,
    tooltip = L.DESC_CONTENT_SIZE,
    onChanged = function() KART.UpdateStyles() end,
})

-- Schriftart Button
KART.BtnFont = KART.UI:CreateModernButton(txtCard, L.BTN_SELECT_FONT, L.DESC_SELECT_FONT)
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
            -- No LibSharedMedia: only the built-in default is available — make the entry actually
            -- apply it (set + restyle + relabel) instead of being a dead no-op button.
            rootDescription:CreateButton("Friz Quadrata", function()
                KART_Settings.fontName = "Friz Quadrata"
                KART.UpdateStyles()
                self.text:SetText(L.BTN_FONT_PREFIX .. "Friz Quadrata")
            end)
        end
    end)
end)

-- Sprache Button
KART.BtnLang = KART.UI:CreateModernButton(txtCard, L.BTN_LANGUAGE_PREFIX .. L.LANG_AUTO, L.DESC_LANGUAGE)
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
local colCard = KART.UI:CreateCard(KART.SettingsPanel)
colCard:SetPoint("TOPLEFT", ifCard, "BOTTOMLEFT", 0, -20)
colCard:SetSize(500, 150)
KART.SettingsColorCard = colCard

-- Color Buttons
KART.BtnAccentColor = KART.UI:CreateModernButton(colCard, L.BTN_ACCENT_COLOR, L.DESC_ACCENT_COLOR)
KART.BtnAccentColor:SetPoint("TOPLEFT", colCard, "TOPLEFT", 20, -20)
KART.BtnAccentColor:SetScript("OnClick", function()
    KART.UI:OpenColorPicker({
        store = KART_Settings, rKey = "accentR", gKey = "accentG", bKey = "accentB",
        onApply = KART.UpdateStyles,
    })
end)

-- Vorschau für Akzentfarbe
KART.ColorPreview = colCard:CreateTexture(nil, "OVERLAY")
KART.ColorPreview:SetSize(25, 25)
KART.ColorPreview:SetPoint("LEFT", KART.BtnAccentColor, "RIGHT", 10, 0)
KART.ColorPreview.bg = colCard:CreateTexture(nil, "BACKGROUND")
KART.ColorPreview.bg:SetPoint("TOPLEFT", KART.ColorPreview, "TOPLEFT", -1, 1)
KART.ColorPreview.bg:SetPoint("BOTTOMRIGHT", KART.ColorPreview, "BOTTOMRIGHT", 1, -1)
KART.ColorPreview.bg:SetColorTexture(0, 0, 0, 1)

-- Reset Button
KART.BtnReset = KART.UI:CreateModernButton(colCard, L.BTN_RESET, L.DESC_RESET)
KART.BtnReset:SetPoint("TOPLEFT", KART.BtnAccentColor, "BOTTOMLEFT", 0, -16)
-- Confirmed, like every other destructive action in the addon (boss-list reset, profile delete):
-- this discards every setting, window position and keybind with no undo, and the button sits one
-- 16px gap below the accent-colour button.
KART.UI:RegisterStaticPopup("KART_RESET_CONFIRM", {
    text = "Really reset all settings?", -- overwritten with KART.L.DESC_RESET before each Show below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        -- Full wipe, not a per-key overwrite: keys without a Defaults entry (window positions,
        -- sizes) must reset too. Tables are deep-copied so KART.Defaults itself is never shared
        -- into (and later mutated through) KART_Settings.
        wipe(KART_Settings)
        for k, v in pairs(KART.Defaults) do
            KART_Settings[k] = type(v) == "table" and KAUtil.DeepCopy(v) or v
        end
        ReloadUI() -- Einfachste Methode um alle UI Werte zurückzusetzen
    end,
})
KART.BtnReset:SetScript("OnClick", function()
    StaticPopupDialogs["KART_RESET_CONFIRM"].text = KART.L.DESC_RESET
    StaticPopup_Show("KART_RESET_CONFIRM")
end)

-- Card: settings profiles (save/switch/delete named KART_Settings snapshots)
local profCard = KART.UI:CreateCard(KART.SettingsPanel)
profCard:SetPoint("TOPLEFT", colCard, "BOTTOMLEFT", 0, -20)
profCard:SetSize(500, 100)

local profTitle = profCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profTitle:SetPoint("TOPLEFT", profCard, "TOPLEFT", 20, -14)
profTitle:SetText(L.LABEL_PROFILES)
KART.UI:RegisterLabel(profTitle)

KART.BtnProfile = KART.UI:CreateModernButton(profCard, L.PROFILE_LABEL_PREFIX .. L.PROFILE_NONE)
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

KART.BtnProfileSaveNew = KART.UI:CreateModernButton(profCard, L.BTN_PROFILE_SAVE_NEW, L.DESC_PROFILE_SAVE_NEW)
KART.BtnProfileSaveNew:SetPoint("TOPLEFT", profCard, "TOPLEFT", 20, -69)
KART.BtnProfileSaveNew:SetScript("OnClick", function()
    KART.ShowSaveProfileDialog()
end)

KART.BtnProfileSave = KART.UI:CreateModernButton(profCard, L.BTN_PROFILE_SAVE, L.DESC_PROFILE_SAVE)
KART.BtnProfileSave:SetPoint("TOPLEFT", KART.BtnProfileSaveNew, "TOPRIGHT", 10, 0)
KART.BtnProfileSave:SetScript("OnClick", function()
    local name = KART_Settings.activeProfile
    if not name then return end
    KART.SaveProfile(name)
    KART.RefreshProfileButton()
end)

KART.BtnProfileDelete = KART.UI:CreateModernButton(profCard, L.BTN_PROFILE_DELETE, L.DESC_PROFILE_DELETE)
KART.BtnProfileDelete:SetPoint("TOPLEFT", KART.BtnProfileSave, "TOPRIGHT", 10, 0)
KART.BtnProfileDelete:SetScript("OnClick", function()
    local name = KART_Settings.activeProfile
    if not name then return end
    local dlg = StaticPopupDialogs["KART_PROFILE_DELETE_CONFIRM"]
    dlg.text = KART.L.PROFILE_DELETE_CONFIRM_TEXT
    dlg.button1, dlg.button2 = KART.L.BTN_YES, KART.L.BTN_NO
    StaticPopup_Show("KART_PROFILE_DELETE_CONFIRM", name, nil, { name = name })
end)

-- 9. Close button: invisible hit area over the X baked into the artwork.
-- HIGHLIGHT-layer texture shows automatically on hover, no scripts needed.
local closeBtn = CreateFrame("Button", nil, clickArea)
closeBtn:SetSize(36, 36)
closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -27, -24)
local closeHover = closeBtn:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.08)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn

-- 10. Settings search: small always-visible button + popout (edit box + up to 8 result rows).
-- Positioned left of the close button, in the same header row as the active tab's title, well
-- clear of the close button's hit area (closeBtn spans roughly x -45..-9, y -42..-6 from
-- clickArea's TOPRIGHT) and of the baked logo/title zone above y -22.
local searchBtn = KART.UI:CreateModernButton(clickArea, L.BTN_SEARCH, L.DESC_SEARCH)
searchBtn:SetSize(70, 22)
searchBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -70, -20)

local searchPopout = CreateFrame("Frame", nil, clickArea, "BackdropTemplate")
searchPopout:SetPoint("TOPRIGHT", searchBtn, "BOTTOMRIGHT", 0, -6)
searchPopout:SetSize(260, 40)
KART.UI:SetPixelBackdrop(searchPopout, {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
searchPopout:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
searchPopout:SetBackdropBorderColor(0, 0, 0, 1)
KART.UI:RegisterStrataFrame(searchPopout, true) -- one stratum above the windows, follows the setting
searchPopout:Hide()
KART.UI:ApplyRoundedMask(searchPopout, KAUI.CORNER_RADIUS_SM)

local searchBox = KART.UI:CreateStyledEditBox(searchPopout, "KART_SearchBox")
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
        local r, g, b = KART.UI:AccentColor()
        local dr, dg, db = KAUI.Darken(r, g, b, 0.45)
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
-- The popout is a child of clickArea, so closing the main window only makes it invisible — its shown
-- flag and its query text survive. Reopening would bring back a stale search whose result rows point
-- at whatever tab happens to be active now. Close it properly whenever the window goes away.
mainFrame:HookScript("OnHide", CloseSearchPopout)

local function FilterSearch(query)
    query = KAUtil.CaseFold(query)
    local shown = 0
    if query ~= "" then
        for _, entry in ipairs(searchIndex) do
            if shown >= RESULT_ROW_COUNT then break end
            if KAUtil.CaseFold(entry.text):find(query, 1, true) then
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
        local delta = scrollTop - top - 40
        local maxScroll = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local newScroll = math.max(0, math.min(scrollFrame:GetVerticalScroll() + delta, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end

    searchHighlight:SetParent(widget:GetParent())
    searchHighlight:ClearAllPoints()
    searchHighlight:SetPoint("TOPLEFT", widget, "TOPLEFT", -6, 6)
    searchHighlight:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 6, -6)
    searchHighlight:SetFrameLevel(widget:GetParent():GetFrameLevel() + 10)
    local r, g, b = KART.UI:AccentColor()
    searchHighlight:SetBackdropColor(r, g, b, 0.35)
    searchHighlight:Show()
    -- Generation token so jumping to a second result within 1.5s doesn't get its highlight hidden
    -- early by the first jump's still-pending timer.
    KART.searchHighlightGen = (KART.searchHighlightGen or 0) + 1
    local myGen = KART.searchHighlightGen
    C_Timer.After(1.5, function()
        if KART.searchHighlightGen == myGen then searchHighlight:Hide() end
    end)

    KART.HideSearchPopout()
end

-- Re-applies every static text in this file from KART.L once the saved language is known
-- (see KART.UI:RegisterLocaleRefresher in Utils.lua). Dynamic texts (BtnFont/BtnLang/BtnProfile
-- labels, keybind button captions, strata slider value) are handled by KART.SyncSettingsToUI.
KART.UI:RegisterLocaleRefresher(function()
    local L = KART.L

    -- Sidebar tabs + fixed header titles
    KART.BtnPromote.text:SetText(L.TAB_PROMOTE)
    KART.BtnRaidlead.text:SetText(L.TAB_RAIDLEAD)
    KART.BtnBuffCheck.text:SetText(L.TAB_BUFFCHECK)
    KART.BtnWoWUtils.text:SetText(L.TAB_WOWUTILS)
    KART.BtnSettings.text:SetText(L.TAB_SETTINGS)
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.LABEL_RAIDLEAD_TOOLS)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    -- TabTitles[5] belongs to Invite.lua and is refreshed there.

    -- Raidlead tab
    KART.CbActivate.text:SetText(L.SET_RL_ACTIVATE)   KART.CbActivate.tooltipText = L.DESC_RL_ACTIVATE
    KART.CbLock.text:SetText(L.SET_RL_LOCK)           KART.CbLock.tooltipText = L.DESC_RL_LOCK
    KART.CbAutoHide.text:SetText(L.SET_RL_AUTOHIDE)   KART.CbAutoHide.tooltipText = L.DESC_RL_AUTOHIDE
    KART.CbRcReasonDialog.text:SetText(L.SET_RL_RC_REASON)
    KART.CbRcReasonDialog.tooltipText = L.DESC_RL_RC_REASON
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
