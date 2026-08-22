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
        KART.CoTankPanel,
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
        KART.BtnCoTank,
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
    if KART.CT and KART.CT.OnSettingsTab then
        local open = tabIndex == 6 and KART.MainFrame and KART.MainFrame:IsShown()
        KART.CT.OnSettingsTab(open and true or false)
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
mainFrame:HookScript("OnHide", function()
    if KART.CT and KART.CT.OnSettingsTab then KART.CT.OnSettingsTab(false) end
end)

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
KART.BtnCoTank = KART.UI:CreateTabButton(clickArea, L.TAB_COTANK)
KART.BtnCoTank:SetPoint("TOPLEFT", KART.BtnWoWUtils, "BOTTOMLEFT", 0, -5)
KART.BtnCoTank:SetScript("OnClick", function() KART.ShowTab(6) end)

KART.BtnSettings = KART.UI:CreateTabButton(clickArea, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnCoTank, "BOTTOMLEFT", 0, -5)
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

KART.CoTankPanel = CreateFrame("Frame", nil, scrollChild)
KART.CoTankPanel:SetAllPoints()
KART.CoTankPanel:Hide()

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
    [6] = 3380, -- Co-Tank: preview + module + row + look + text + fade + auras + taunt
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
rlCard:SetSize(500, 330)

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

KART.CbAutoHideCombat = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarCombatHideCheck", label = L.SET_RL_AUTOHIDE_COMBAT,
    store = SettingsStore, key = "autoHideRaidleadBarCombat", y = -110,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility()
    end,
    tooltip = L.DESC_RL_AUTOHIDE_COMBAT,
})

-- Ready-check reason prompt. Sits on this tab because the ready check itself is a Raidlead Bar
-- button; the dialog it controls lives in Core.lua (KART.ShowReadyCheckReasonDialog).
KART.CbRcReasonDialog = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RcReasonDialogCheck", label = L.SET_RL_RC_REASON,
    store = SettingsStore, key = "rcReasonDialog", y = -140,
    tooltip = L.DESC_RL_RC_REASON,
})

-- Pull-Timer Slider: the pull button (RaidleadBar.lua) reads pullTimerDuration
-- at click time, so no macrotext attribute needs updating here anymore.
KART.PullSlider = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_PullTimerSlider", label = L.SET_PULL_TIMER,
    min = 5, max = 30, store = SettingsStore, key = "pullTimerDuration", y = -190,
    tooltip = L.DESC_PULL_TIMER,
})

KART.SldRlBarStrata = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_RlBarStrataSlider", label = L.SET_RL_STRATA,
    min = 1, max = #KART.StrataLevels, store = SettingsStore, key = "rlBarFrameStrata", y = -240,
    tooltip = L.DESC_RL_STRATA,
    onChanged = function()
        if KART.ApplyRaidleadBarStrata then KART.ApplyRaidleadBarStrata() end
    end,
    valueIsText = true,
})
local function UpdateRlBarStrataSliderText(self)
    self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
end
KART.SldRlBarStrata:HookScript("OnValueChanged", UpdateRlBarStrataSliderText)
KART.SldRlBarStrata:HookScript("OnShow", UpdateRlBarStrataSliderText)

KART.CbRlBarYieldMap = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarYieldMapCheck", label = L.SET_RL_YIELD_MAP,
    store = SettingsStore, key = "rlBarYieldToMap", y = -280,
    onChanged = function()
        if KART.ApplyRaidleadBarStrata then KART.ApplyRaidleadBarStrata() end
    end,
    tooltip = L.DESC_RL_YIELD_MAP,
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
autoCard:SetSize(500, 220)

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

local function InviteChannels()
    KART_Settings.inviteChannels = KART_Settings.inviteChannels or {}
    return KART_Settings.inviteChannels
end

local chanLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
chanLabel:SetPoint("TOPLEFT", KART.InviteEditBox, "BOTTOMLEFT", 0, -14)
chanLabel:SetText(L.SET_INVITE_CHANNELS)
KART.UI:RegisterLabel(chanLabel)

local function CreateInviteChannelChip(parent, label, key, xOff)
    local btn = KART.UI:CreateModernButton(parent, label)
    btn:SetSize(108, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, -130)
    btn.tooltipText = L["DESC_INVITE_CHANNEL_" .. key]
    local function refresh()
        local on = InviteChannels()[key]
        if on then
            local r, g, b = KART.UI:AccentColor()
            btn:SetBackdropColor(KAUI.Darken(r, g, b, 0.35), KAUI.Darken(r, g, b, 0.35),
                KAUI.Darken(r, g, b, 0.35), 1)
            btn.text:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            btn.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    btn:SetScript("OnClick", function()
        local ch = InviteChannels()
        ch[key] = not ch[key]
        if key == "GUILD" then KART_Settings.inviteViaGuildChat = ch[key] end
        refresh()
    end)
    btn.Refresh = refresh
    refresh()
    return btn
end

KART.InviteChannelChips = {
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_WHISPER, "WHISPER", 20),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_BN, "BN", 134),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_GUILD, "GUILD", 248),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_OFFICER, "OFFICER", 362),
}

KART.CbAutoRaid = KART.UI:CreateSettingsCheckbox(autoCard, {
    name = "KART_AutoRaidCheck", label = L.SET_AUTO_RAID,
    store = SettingsStore, key = "autoConvertToRaid", y = -168,
    tooltip = L.DESC_AUTO_RAID,
})
KART.CbAutoRaid.text:SetWidth(430)
KART.CbAutoRaid.text:SetJustifyH("LEFT")

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

-- 8b. Co-Tank panel (settings for KART.CT; CT may be nil until CoTank.lua loads in a later task)
local function CtStore() KART_Settings.ct = KART_Settings.ct or {}; return KART_Settings.ct end
local function CtDebuffs() local ct = CtStore(); ct.debuffs = ct.debuffs or {}; return ct.debuffs end
local function CtBuffs() local ct = CtStore(); ct.buffs = ct.buffs or {}; return ct.buffs end
local function CtNameStyle() local ct = CtStore(); ct.nameStyle = ct.nameStyle or {}; return ct.nameStyle end
local function CtHealthStyle() local ct = CtStore(); ct.healthStyle = ct.healthStyle or {}; return ct.healthStyle end
local function CtTargetBorder() local ct = CtStore(); ct.targetBorder = ct.targetBorder or {}; return ct.targetBorder end

local function CtRefresh()
    if KART.CT and KART.CT.Refresh then KART.CT.Refresh() end
end
local function CtEnable()
    if KART.CT and KART.CT.Enable then KART.CT.Enable() end
    if KART.CurrentTab == 6 and KART.MainFrame and KART.MainFrame:IsShown()
        and KART.CT and KART.CT.HostPreview then
        KART.CT.HostPreview()
    end
end
local function CtLayoutChanged()
    if KART.CT and KART.CT.ApplyLayout then KART.CT.ApplyLayout() end
    CtRefresh()
end

local function CtPickColor(tbl, after)
    if not tbl then return end
    local store = {
        r = math.floor(((tbl.r or 1) * 100) + 0.5),
        g = math.floor(((tbl.g or 1) * 100) + 0.5),
        b = math.floor(((tbl.b or 1) * 100) + 0.5),
    }
    KART.UI:OpenColorPicker({
        store = store, rKey = "r", gKey = "g", bKey = "b",
        onApply = function()
            tbl.r = store.r / 100
            tbl.g = store.g / 100
            tbl.b = store.b / 100
            if after then after() end
        end,
    })
end

KART.CreateTabTitle(6, L.LABEL_COTANK_SETTINGS)

local ctPreviewCard = KART.UI:CreateCard(KART.CoTankPanel)
ctPreviewCard:SetPoint("TOPLEFT", KART.CoTankPanel, "TOPLEFT", 20, -12)
ctPreviewCard:SetSize(500, 240)
local ctPreviewTitle = ctPreviewCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctPreviewTitle:SetPoint("TOPLEFT", ctPreviewCard, "TOPLEFT", 16, -12)
ctPreviewTitle:SetText(L.LABEL_CT_PREVIEW)
KART.UI:RegisterLabel(ctPreviewTitle)
KART.CtPreviewSlot = CreateFrame("Frame", nil, ctPreviewCard)
KART.CtPreviewSlot:SetPoint("TOPLEFT", ctPreviewCard, "TOPLEFT", 16, -36)
KART.CtPreviewSlot:SetPoint("BOTTOMRIGHT", ctPreviewCard, "BOTTOMRIGHT", -16, 44)
if KART.CtPreviewSlot.SetClipsChildren then
    KART.CtPreviewSlot:SetClipsChildren(false)
end
KART.CtAuraEngineNote = ctPreviewCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.CtAuraEngineNote:SetPoint("BOTTOMLEFT", ctPreviewCard, "BOTTOMLEFT", 16, 10)
KART.CtAuraEngineNote:SetPoint("BOTTOMRIGHT", ctPreviewCard, "BOTTOMRIGHT", -16, 10)
KART.CtAuraEngineNote:SetJustifyH("LEFT")
KART.CtAuraEngineNote:SetText(L.SET_CT_AURA_ENGINE)
KART.UI:RegisterLabel(KART.CtAuraEngineNote)

local ctModCard = KART.UI:CreateCard(KART.CoTankPanel)
ctModCard:SetPoint("TOPLEFT", ctPreviewCard, "BOTTOMLEFT", 0, -20)
ctModCard:SetSize(500, 180)

KART.CbCtModuleEnabled = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtModuleEnabled", label = L.SET_CT_MODULE_ENABLED,
    store = SettingsStore, key = "ctModuleEnabled", y = -20,
    tooltip = L.DESC_CT_MODULE_ENABLED,
    onChanged = CtEnable,
})
KART.CbCtModuleEnabled.text:SetWidth(190)
KART.CbCtModuleEnabled.text:SetJustifyH("LEFT")

KART.CbCtTestMode = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtTestMode", label = L.SET_CT_TESTMODE,
    store = CtStore, key = "testMode", y = -50,
    tooltip = L.DESC_CT_TESTMODE,
    onChanged = CtRefresh,
})
KART.CbCtTestMode.text:SetWidth(190)
KART.CbCtTestMode.text:SetJustifyH("LEFT")

KART.CbCtLock = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtLock", label = L.SET_CT_LOCK,
    store = CtStore, key = "locked", y = -80,
    tooltip = L.DESC_CT_LOCK,
    onChanged = CtRefresh,
})
KART.CbCtLock.text:SetWidth(190)
KART.CbCtLock.text:SetJustifyH("LEFT")

KART.CbCtOnlyGroup = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyGroup", label = L.SET_CT_ONLY_GROUP,
    store = CtStore, key = "onlyInGroup", y = -110,
    tooltip = L.DESC_CT_ONLY_GROUP,
    onChanged = CtRefresh,
})
KART.CbCtOnlyGroup.text:SetWidth(190)
KART.CbCtOnlyGroup.text:SetJustifyH("LEFT")

KART.CbCtOnlyInstance = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyInstance", label = L.SET_CT_ONLY_INSTANCE,
    store = CtStore, key = "onlyInInstance", y = -140,
    tooltip = L.DESC_CT_ONLY_INSTANCE,
    onChanged = CtRefresh,
})
KART.CbCtOnlyInstance.text:SetWidth(220)
KART.CbCtOnlyInstance.text:SetJustifyH("LEFT")

local ctRowCard = KART.UI:CreateCard(KART.CoTankPanel)
ctRowCard:SetPoint("TOPLEFT", ctModCard, "BOTTOMLEFT", 0, -20)
ctRowCard:SetSize(500, 230)

KART.SldCtWidth = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtWidthSlider", label = L.SET_CT_WIDTH,
    min = 100, max = 400, store = CtStore, key = "width", y = -20,
    onChanged = CtLayoutChanged,
})
KART.SldCtHeight = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtHeightSlider", label = L.SET_CT_HEIGHT,
    min = 20, max = 80, store = CtStore, key = "height", y = -60,
    onChanged = CtLayoutChanged,
})
KART.SldCtScale = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtScaleSlider", label = L.SET_CT_SCALE,
    min = 50, max = 200, store = CtStore, key = "scale", y = -100,
    onChanged = function()
        CtStore().scale = KART.SldCtScale:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtRangeFade = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtRangeFadeSlider", label = L.SET_CT_RANGE_FADE,
    min = 10, max = 100, store = CtStore, key = "rangeAlpha", y = -140,
    onChanged = function()
        CtStore().rangeAlpha = KART.SldCtRangeFade:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtNameMax = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtNameMaxSlider", label = L.SET_CT_NAME_MAX,
    min = 4, max = 24, store = CtStore, key = "nameMaxLength", y = -180,
    onChanged = CtRefresh,
})

KART.CbCtAbsorb = KART.UI:CreateSettingsCheckbox(ctRowCard, {
    name = "KART_CtAbsorb", label = L.SET_CT_ABSORB,
    store = CtStore, key = "absorbShow", y = -20,
    onChanged = CtRefresh,
})
KART.CbCtAbsorb:ClearAllPoints()
KART.CbCtAbsorb:SetPoint("TOPLEFT", ctRowCard, "TOPLEFT", 260, -20)
KART.CbCtAbsorb.text:SetWidth(192)
KART.CbCtAbsorb.text:SetJustifyH("LEFT")

KART.CbCtHealAbsorb = KART.UI:CreateSettingsCheckbox(ctRowCard, {
    name = "KART_CtHealAbsorb", label = L.SET_CT_HEAL_ABSORB,
    store = CtStore, key = "healAbsorbShow", y = -50,
    onChanged = CtRefresh,
})
KART.CbCtHealAbsorb:ClearAllPoints()
KART.CbCtHealAbsorb:SetPoint("TOPLEFT", ctRowCard, "TOPLEFT", 260, -50)
KART.CbCtHealAbsorb.text:SetWidth(192)
KART.CbCtHealAbsorb.text:SetJustifyH("LEFT")

local CT_HEALTH_COLOR_L = {
    class = function() return L.CT_HEALTH_COLOR_CLASS end,
    custom = function() return L.CT_HEALTH_COLOR_CUSTOM end,
    health = function() return L.CT_HEALTH_COLOR_HEALTH end,
}
local CT_HEALTH_TEXT_L = {
    percent = function() return L.CT_HEALTH_TEXT_PERCENT end,
    current = function() return L.CT_HEALTH_TEXT_CURRENT end,
    both = function() return L.CT_HEALTH_TEXT_BOTH end,
    deficit = function() return L.CT_HEALTH_TEXT_DEFICIT end,
}
local CT_ANCHOR_L = {
    TOPLEFT = function() return L.CT_ANCHOR_TOPLEFT end,
    TOPRIGHT = function() return L.CT_ANCHOR_TOPRIGHT end,
    BOTTOMLEFT = function() return L.CT_ANCHOR_BOTTOMLEFT end,
    BOTTOMRIGHT = function() return L.CT_ANCHOR_BOTTOMRIGHT end,
}
local CT_GROWTH_L = {
    right = function() return L.CT_GROWTH_RIGHT end,
    left = function() return L.CT_GROWTH_LEFT end,
    up = function() return L.CT_GROWTH_UP end,
    down = function() return L.CT_GROWTH_DOWN end,
}
local CT_ANCHOR_OPTS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local CT_GROWTH_OPTS = { "right", "left", "up", "down" }

local function RefreshCtHealthColorBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthColor or "class"
    local labelFn = CT_HEALTH_COLOR_L[mode]
    KART.BtnCtHealthColor.text:SetText(L.SET_CT_HEALTH_COLOR .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtHealthTextBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthText or "both"
    local labelFn = CT_HEALTH_TEXT_L[mode]
    KART.BtnCtHealthText.text:SetText(L.SET_CT_HEALTH_TEXT .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtStripEnumBtn(btn, title, storeFn, key, labelMap, default)
    if not KART_Settings then return end
    local mode = storeFn()[key] or default
    local labelFn = labelMap[mode]
    btn.text:SetText(title .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtDebuffAnchorBtn()
    RefreshCtStripEnumBtn(KART.BtnCtDebuffAnchor, L.SET_CT_AURA_ANCHOR, CtDebuffs, "anchor", CT_ANCHOR_L, "TOPLEFT")
end
local function RefreshCtDebuffGrowthBtn()
    RefreshCtStripEnumBtn(KART.BtnCtDebuffGrowth, L.SET_CT_AURA_GROWTH, CtDebuffs, "growth", CT_GROWTH_L, "right")
end
local function RefreshCtBuffAnchorBtn()
    RefreshCtStripEnumBtn(KART.BtnCtBuffAnchor, L.SET_CT_AURA_ANCHOR, CtBuffs, "anchor", CT_ANCHOR_L, "BOTTOMRIGHT")
end
local function RefreshCtBuffGrowthBtn()
    RefreshCtStripEnumBtn(KART.BtnCtBuffGrowth, L.SET_CT_AURA_GROWTH, CtBuffs, "growth", CT_GROWTH_L, "left")
end

KART.BtnCtHealthColor = KART.UI:CreateModernButton(ctRowCard, L.SET_CT_HEALTH_COLOR, L.DESC_CT_HEALTH_COLOR)
KART.BtnCtHealthColor:SetPoint("TOPLEFT", ctRowCard, "TOPLEFT", 260, -90)
KART.BtnCtHealthColor:SetSize(220, 22)
KART.BtnCtHealthColor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_COLOR)
        for _, opt in ipairs({ "class", "custom", "health" }) do
            rootDescription:CreateButton(CT_HEALTH_COLOR_L[opt](), function()
                CtStore().healthColor = opt
                RefreshCtHealthColorBtn()
                CtRefresh()
            end)
        end
    end)
end)

KART.BtnCtHealthText = KART.UI:CreateModernButton(ctRowCard, L.SET_CT_HEALTH_TEXT, L.DESC_CT_HEALTH_TEXT)
KART.BtnCtHealthText:SetPoint("TOPLEFT", KART.BtnCtHealthColor, "BOTTOMLEFT", 0, -10)
KART.BtnCtHealthText:SetSize(220, 22)
KART.BtnCtHealthText:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_TEXT)
        for _, opt in ipairs({ "percent", "current", "both", "deficit" }) do
            rootDescription:CreateButton(CT_HEALTH_TEXT_L[opt](), function()
                CtStore().healthText = opt
                RefreshCtHealthTextBtn()
                CtRefresh()
            end)
        end
    end)
end)

local CT_FILL_L = {
    right = function() return L.CT_FILL_RIGHT end,
    left = function() return L.CT_FILL_LEFT end,
    up = function() return L.CT_FILL_UP end,
    down = function() return L.CT_FILL_DOWN end,
}
local CT_FILL_OPTS = { "right", "left", "up", "down" }
local CT_OUTLINE_L = {
    NONE = function() return L.CT_OUTLINE_NONE end,
    OUTLINE = function() return L.CT_OUTLINE_OUTLINE end,
    THICKOUTLINE = function() return L.CT_OUTLINE_THICK end,
}
local CT_OUTLINE_OPTS = { "NONE", "OUTLINE", "THICKOUTLINE" }
local CT_TEXT_ANCHOR_OPTS = { "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }

local function RefreshCtFillBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthFill or "right"
    local labelFn = CT_FILL_L[mode]
    KART.BtnCtHealthFill.text:SetText(L.SET_CT_HEALTH_FILL .. ": " .. (labelFn and labelFn() or mode))
end

local ctLookCard = KART.UI:CreateCard(KART.CoTankPanel)
ctLookCard:SetPoint("TOPLEFT", ctRowCard, "BOTTOMLEFT", 0, -20)
ctLookCard:SetSize(500, 420)

KART.BtnCtHealthFill = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_FILL, L.DESC_CT_HEALTH_FILL)
KART.BtnCtHealthFill:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -20)
KART.BtnCtHealthFill:SetSize(220, 22)
KART.BtnCtHealthFill:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_FILL)
        for _, opt in ipairs(CT_FILL_OPTS) do
            rootDescription:CreateButton(CT_FILL_L[opt](), function()
                CtStore().healthFill = opt
                RefreshCtFillBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.SldCtHealthAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtHealthAlphaSlider", label = L.SET_CT_HEALTH_ALPHA,
    min = 10, max = 100, store = CtStore, key = "healthAlpha", y = -60,
    onChanged = function()
        CtStore().healthAlpha = KART.SldCtHealthAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtTrackAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtTrackAlphaSlider", label = L.SET_CT_TRACK_ALPHA,
    min = 0, max = 100, store = CtStore, key = "trackAlpha", y = -60,
    onChanged = function()
        CtStore().trackAlpha = KART.SldCtTrackAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtTrackAlpha:ClearAllPoints()
KART.SldCtTrackAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -76)

KART.BtnCtCustomColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_CUSTOM_COLOR)
KART.BtnCtCustomColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -110)
KART.BtnCtCustomColor:SetSize(220, 22)
KART.BtnCtCustomColor:SetScript("OnClick", function()
    CtPickColor(CtStore().healthCustom, CtLayoutChanged)
end)
KART.BtnCtBgColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_BG_COLOR)
KART.BtnCtBgColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -110)
KART.BtnCtBgColor:SetSize(220, 22)
KART.BtnCtBgColor:SetScript("OnClick", function()
    CtPickColor(CtStore().bgColor, CtLayoutChanged)
end)

KART.BtnCtHealthHigh = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_HIGH)
KART.BtnCtHealthHigh:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -142)
KART.BtnCtHealthHigh:SetSize(220, 22)
KART.BtnCtHealthHigh:SetScript("OnClick", function()
    CtPickColor(CtStore().healthHigh, CtLayoutChanged)
end)
KART.BtnCtHealthMid = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_MID)
KART.BtnCtHealthMid:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -142)
KART.BtnCtHealthMid:SetSize(220, 22)
KART.BtnCtHealthMid:SetScript("OnClick", function()
    CtPickColor(CtStore().healthMid, CtLayoutChanged)
end)
KART.BtnCtHealthLow = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_LOW)
KART.BtnCtHealthLow:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -174)
KART.BtnCtHealthLow:SetSize(220, 22)
KART.BtnCtHealthLow:SetScript("OnClick", function()
    CtPickColor(CtStore().healthLow, CtLayoutChanged)
end)

KART.SldCtBgAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtBgAlphaSlider", label = L.SET_CT_BG_ALPHA,
    min = 10, max = 100, store = CtStore, key = "bgAlpha", y = -210,
    onChanged = function()
        CtStore().bgAlpha = KART.SldCtBgAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtBorderSize = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtBorderSizeSlider", label = L.SET_CT_BORDER_SIZE,
    min = 0, max = 4, store = CtStore, key = "borderSize", y = -210,
    onChanged = CtLayoutChanged,
})
KART.SldCtBorderSize:ClearAllPoints()
KART.SldCtBorderSize:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -226)

KART.BtnCtBorderColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_BORDER_COLOR)
KART.BtnCtBorderColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -260)
KART.BtnCtBorderColor:SetSize(220, 22)
KART.BtnCtBorderColor:SetScript("OnClick", function()
    CtPickColor(CtStore().borderColor, CtLayoutChanged)
end)

KART.BtnCtAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_ABSORB_COLOR)
KART.BtnCtAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -292)
KART.BtnCtAbsorbColor:SetSize(220, 22)
KART.BtnCtAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().absorbColor, CtLayoutChanged)
end)
KART.SldCtAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtAbsorbAlphaSlider", label = L.SET_CT_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "absorbAlpha", y = -292,
    onChanged = function()
        CtStore().absorbAlpha = KART.SldCtAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtAbsorbAlpha:ClearAllPoints()
KART.SldCtAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -308)

KART.BtnCtHealAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEAL_ABSORB_COLOR)
KART.BtnCtHealAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -350)
KART.BtnCtHealAbsorbColor:SetSize(220, 22)
KART.BtnCtHealAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().healAbsorbColor, CtLayoutChanged)
end)
KART.SldCtHealAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtHealAbsorbAlphaSlider", label = L.SET_CT_HEAL_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "healAbsorbAlpha", y = -350,
    onChanged = function()
        CtStore().healAbsorbAlpha = KART.SldCtHealAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtHealAbsorbAlpha:ClearAllPoints()
KART.SldCtHealAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -366)

local function CtBuildTextBlock(card, y0, title, storeFn, prefix)
    local titleFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0)
    titleFS:SetText(title)
    KART.UI:RegisterLabel(titleFS)

    local show = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Show", label = L.SET_CT_TEXT_SHOW,
        store = storeFn, key = "show", y = y0 - 24,
        onChanged = CtLayoutChanged,
    })
    local size = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "Size", label = L.SET_CT_TEXT_SIZE,
        min = 0, max = 32, store = storeFn, key = "size", y = y0 - 24,
        onChanged = CtLayoutChanged,
    })
    size:ClearAllPoints()
    size:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 40)

    local colorBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_COLOR)
    colorBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 80)
    colorBtn:SetSize(220, 22)
    colorBtn:SetScript("OnClick", function()
        local st = storeFn()
        st.color = st.color or { r = 1, g = 1, b = 1 }
        CtPickColor(st.color, CtLayoutChanged)
    end)
    local classCb = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Class", label = L.SET_CT_TEXT_CLASS,
        store = storeFn, key = "classColor", y = y0 - 80,
        onChanged = CtLayoutChanged,
    })
    classCb:ClearAllPoints()
    classCb:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 80)

    local outlineBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_OUTLINE)
    outlineBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 112)
    outlineBtn:SetSize(220, 22)
    local function refreshOutline()
        local mode = storeFn().outline or "OUTLINE"
        local labelFn = CT_OUTLINE_L[mode]
        outlineBtn.text:SetText(L.SET_CT_TEXT_OUTLINE .. ": " .. (labelFn and labelFn() or mode))
    end
    outlineBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.SET_CT_TEXT_OUTLINE)
            for _, opt in ipairs(CT_OUTLINE_OPTS) do
                rootDescription:CreateButton(CT_OUTLINE_L[opt](), function()
                    storeFn().outline = opt
                    refreshOutline()
                    CtLayoutChanged()
                end)
            end
        end)
    end)

    local anchorBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_ANCHOR)
    anchorBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 112)
    anchorBtn:SetSize(220, 22)
    local function refreshAnchor()
        local mode = storeFn().anchor or "LEFT"
        anchorBtn.text:SetText(L.SET_CT_TEXT_ANCHOR .. ": " .. mode)
    end
    anchorBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.SET_CT_TEXT_ANCHOR)
            for _, opt in ipairs(CT_TEXT_ANCHOR_OPTS) do
                rootDescription:CreateButton(opt, function()
                    storeFn().anchor = opt
                    refreshAnchor()
                    CtLayoutChanged()
                end)
            end
        end)
    end)

    local nudgeX = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeX", label = L.SET_CT_TEXT_NUDGE_X,
        min = -40, max = 40, store = storeFn, key = "x", y = y0 - 150,
        onChanged = CtLayoutChanged,
    })
    local nudgeY = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeY", label = L.SET_CT_TEXT_NUDGE_Y,
        min = -40, max = 40, store = storeFn, key = "y", y = y0 - 150,
        onChanged = CtLayoutChanged,
    })
    nudgeY:ClearAllPoints()
    nudgeY:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 166)

    return {
        show = show, size = size, colorBtn = colorBtn, classCb = classCb,
        outlineBtn = outlineBtn, refreshOutline = refreshOutline,
        anchorBtn = anchorBtn, refreshAnchor = refreshAnchor,
        nudgeX = nudgeX, nudgeY = nudgeY, titleFS = titleFS,
    }
end

local ctTextCard = KART.UI:CreateCard(KART.CoTankPanel)
ctTextCard:SetPoint("TOPLEFT", ctLookCard, "BOTTOMLEFT", 0, -20)
ctTextCard:SetSize(500, 430)
KART.CtNameTextWidgets = CtBuildTextBlock(ctTextCard, -14, L.LABEL_CT_NAME_TEXT, CtNameStyle, "Name")
KART.CtHealthTextWidgets = CtBuildTextBlock(ctTextCard, -220, L.LABEL_CT_HEALTH_TEXT, CtHealthStyle, "Hp")

local ctFadeCard = KART.UI:CreateCard(KART.CoTankPanel)
ctFadeCard:SetPoint("TOPLEFT", ctTextCard, "BOTTOMLEFT", 0, -20)
ctFadeCard:SetSize(500, 250)

KART.CbCtRangeFadeOn = KART.UI:CreateSettingsCheckbox(ctFadeCard, {
    name = "KART_CtRangeFadeOn", label = L.SET_CT_RANGE_FADE_ON,
    store = CtStore, key = "rangeFade", y = -20,
    onChanged = CtRefresh,
})
KART.SldCtDeadFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtDeadFadeSlider", label = L.SET_CT_DEAD_FADE,
    min = 10, max = 100, store = CtStore, key = "deadFade", y = -60,
    onChanged = function()
        CtStore().deadFade = KART.SldCtDeadFade:GetValue() / 100
        CtRefresh()
    end,
})
KART.SldCtOfflineFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtOfflineFadeSlider", label = L.SET_CT_OFFLINE_FADE,
    min = 10, max = 100, store = CtStore, key = "offlineFade", y = -60,
    onChanged = function()
        CtStore().offlineFade = KART.SldCtOfflineFade:GetValue() / 100
        CtRefresh()
    end,
})
KART.SldCtOfflineFade:ClearAllPoints()
KART.SldCtOfflineFade:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -76)

KART.CbCtTargetBorder = KART.UI:CreateSettingsCheckbox(ctFadeCard, {
    name = "KART_CtTargetBorder", label = L.SET_CT_TARGET_BORDER,
    store = CtTargetBorder, key = "show", y = -110,
    tooltip = L.DESC_CT_TARGET_BORDER,
    onChanged = CtRefresh,
})
KART.SldCtTargetBorderSize = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtTargetBorderSize", label = L.SET_CT_TARGET_BORDER_SIZE,
    min = 1, max = 6, store = CtTargetBorder, key = "size", y = -150,
    onChanged = CtLayoutChanged,
})
KART.BtnCtTargetBorderColor = KART.UI:CreateModernButton(ctFadeCard, L.SET_CT_TARGET_BORDER_COLOR)
KART.BtnCtTargetBorderColor:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -166)
KART.BtnCtTargetBorderColor:SetSize(220, 22)
KART.BtnCtTargetBorderColor:SetScript("OnClick", function()
    local tb = CtTargetBorder()
    tb.color = tb.color or { r = 1, g = 0.85, b = 0.2 }
    CtPickColor(tb.color, CtLayoutChanged)
end)

local ctAuraCard = KART.UI:CreateCard(KART.CoTankPanel)
ctAuraCard:SetPoint("TOPLEFT", ctFadeCard, "BOTTOMLEFT", 0, -20)
ctAuraCard:SetSize(500, 760)

local ctDebuffTitle = ctAuraCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctDebuffTitle:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -14)
ctDebuffTitle:SetText(L.LABEL_CT_DEBUFFS)
KART.UI:RegisterLabel(ctDebuffTitle)

KART.CbCtDebuffShow = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtDebuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtDebuffs, key = "show", y = -40,
    onChanged = CtRefresh,
})
KART.SldCtDebuffMax = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtDebuffs, key = "max", y = -40,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffMax:ClearAllPoints()
KART.SldCtDebuffMax:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -56)

KART.SldCtDebuffSize = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 40, store = CtDebuffs, key = "size", y = -80,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtDebuffs, key = "spacing", y = -80,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing:ClearAllPoints()
KART.SldCtDebuffSpacing:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -96)

KART.BtnCtDebuffAnchor = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtDebuffAnchor:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -120)
KART.BtnCtDebuffAnchor:SetSize(220, 22)
KART.BtnCtDebuffAnchor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_ANCHOR)
        for _, opt in ipairs(CT_ANCHOR_OPTS) do
            rootDescription:CreateButton(CT_ANCHOR_L[opt](), function()
                CtDebuffs().anchor = opt
                RefreshCtDebuffAnchorBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.BtnCtDebuffGrowth = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_GROWTH, L.DESC_CT_AURA_GROWTH)
KART.BtnCtDebuffGrowth:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -120)
KART.BtnCtDebuffGrowth:SetSize(220, 22)
KART.BtnCtDebuffGrowth:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_GROWTH)
        for _, opt in ipairs(CT_GROWTH_OPTS) do
            rootDescription:CreateButton(CT_GROWTH_L[opt](), function()
                CtDebuffs().growth = opt
                RefreshCtDebuffGrowthBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

local ctBuffTitle = ctAuraCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctBuffTitle:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -164)
ctBuffTitle:SetText(L.LABEL_CT_BUFFS)
KART.UI:RegisterLabel(ctBuffTitle)

KART.CbCtBuffShow = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtBuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtBuffs, key = "show", y = -190,
    onChanged = CtRefresh,
})
KART.SldCtBuffMax = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtBuffs, key = "max", y = -190,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffMax:ClearAllPoints()
KART.SldCtBuffMax:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -206)

KART.SldCtBuffSize = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 40, store = CtBuffs, key = "size", y = -230,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtBuffs, key = "spacing", y = -230,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing:ClearAllPoints()
KART.SldCtBuffSpacing:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -246)

KART.BtnCtBuffAnchor = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtBuffAnchor:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -270)
KART.BtnCtBuffAnchor:SetSize(220, 22)
KART.BtnCtBuffAnchor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_ANCHOR)
        for _, opt in ipairs(CT_ANCHOR_OPTS) do
            rootDescription:CreateButton(CT_ANCHOR_L[opt](), function()
                CtBuffs().anchor = opt
                RefreshCtBuffAnchorBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.BtnCtBuffGrowth = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_GROWTH, L.DESC_CT_AURA_GROWTH)
KART.BtnCtBuffGrowth:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -270)
KART.BtnCtBuffGrowth:SetSize(220, 22)
KART.BtnCtBuffGrowth:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_GROWTH)
        for _, opt in ipairs(CT_GROWTH_OPTS) do
            rootDescription:CreateButton(CT_GROWTH_L[opt](), function()
                CtBuffs().growth = opt
                RefreshCtBuffGrowthBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

local function CtAddStripExtras(card, storeFn, prefix, y0)
    local perRow = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "PerRow", label = L.SET_CT_AURA_PER_ROW,
        min = 1, max = 20, store = storeFn, key = "perRow", y = y0,
        onChanged = CtLayoutChanged,
    })
    local border = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "Border", label = L.SET_CT_AURA_BORDER,
        min = 0, max = 4, store = storeFn, key = "borderSize", y = y0,
        onChanged = CtLayoutChanged,
    })
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 16)

    local nudgeX = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeX", label = L.SET_CT_AURA_NUDGE_X,
        min = -60, max = 60, store = storeFn, key = "x", y = y0 - 40,
        onChanged = CtLayoutChanged,
    })
    local nudgeY = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeY", label = L.SET_CT_AURA_NUDGE_Y,
        min = -60, max = 60, store = storeFn, key = "y", y = y0 - 40,
        onChanged = CtLayoutChanged,
    })
    nudgeY:ClearAllPoints()
    nudgeY:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 56)

    local borderColor = KART.UI:CreateModernButton(card, L.SET_CT_AURA_BORDER_COLOR)
    borderColor:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 90)
    borderColor:SetSize(220, 22)
    borderColor:SetScript("OnClick", function()
        local st = storeFn()
        st.borderColor = st.borderColor or { r = 0, g = 0, b = 0 }
        CtPickColor(st.borderColor, CtLayoutChanged)
    end)

    local swipe = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Swipe", label = L.SET_CT_AURA_SWIPE,
        store = storeFn, key = "swipe", y = y0 - 90,
        onChanged = CtLayoutChanged,
    })
    swipe:ClearAllPoints()
    swipe:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 90)

    local countdown = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Countdown", label = L.SET_CT_AURA_COUNTDOWN,
        store = storeFn, key = "countdown", y = y0 - 120,
        onChanged = CtLayoutChanged,
    })
    local cdSize = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "CdSize", label = L.SET_CT_AURA_COUNTDOWN_SIZE,
        min = 0, max = 24, store = storeFn, key = "countdownSize", y = y0 - 120,
        onChanged = CtLayoutChanged,
    })
    cdSize:ClearAllPoints()
    cdSize:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 136)

    local stacks = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Stacks", label = L.SET_CT_AURA_STACKS,
        store = storeFn, key = "stacks", y = y0 - 160,
        onChanged = CtLayoutChanged,
    })
    local stSize = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "StSize", label = L.SET_CT_AURA_STACKS_SIZE,
        min = 0, max = 24, store = storeFn, key = "stacksSize", y = y0 - 160,
        onChanged = CtLayoutChanged,
    })
    stSize:ClearAllPoints()
    stSize:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 176)

    return {
        perRow = perRow, border = border, nudgeX = nudgeX, nudgeY = nudgeY,
        borderColor = borderColor, swipe = swipe, countdown = countdown,
        cdSize = cdSize, stacks = stacks, stSize = stSize,
    }
end

KART.CtDebuffExtra = CtAddStripExtras(ctAuraCard, CtDebuffs, "DebuffEx", -310)
KART.CtBuffExtra = CtAddStripExtras(ctAuraCard, CtBuffs, "BuffEx", -510)

local ctAuraChromeNote = ctAuraCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctAuraChromeNote:SetPoint("BOTTOMLEFT", ctAuraCard, "BOTTOMLEFT", 20, 12)
ctAuraChromeNote:SetPoint("BOTTOMRIGHT", ctAuraCard, "BOTTOMRIGHT", -20, 12)
ctAuraChromeNote:SetJustifyH("LEFT")
ctAuraChromeNote:SetWordWrap(true)
ctAuraChromeNote:SetText(L.SET_CT_AURA_DUMMY_CHROME)
KART.UI:RegisterLabel(ctAuraChromeNote)

local function CtTaunt()
    local ct = CtStore()
    ct.taunt = ct.taunt or {}
    return ct.taunt
end
local function CtTauntChannels()
    local t = CtTaunt()
    t.channels = t.channels or {}
    return t.channels
end
local function CtTauntChanged()
    if KART.CT and KART.CT.RefreshAskButton then KART.CT.RefreshAskButton() end
end

local ctTauntCard = KART.UI:CreateCard(KART.CoTankPanel)
ctTauntCard:SetPoint("TOPLEFT", ctAuraCard, "BOTTOMLEFT", 0, -20)
ctTauntCard:SetSize(500, 320)

local ctTauntTitle = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctTauntTitle:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 20, -14)
ctTauntTitle:SetText(L.LABEL_CT_TAUNT)
KART.UI:RegisterLabel(ctTauntTitle)

KART.CbCtTauntAnnounce = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntAnnounce", label = L.SET_CT_TAUNT_ANNOUNCE,
    store = CtTaunt, key = "announce", y = -36,
    tooltip = L.DESC_CT_TAUNT_ANNOUNCE,
})
KART.CbCtTauntAnnounce.text:SetWidth(430)
KART.CbCtTauntAnnounce.text:SetJustifyH("LEFT")

KART.CbCtTauntOnlyGroup = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntOnlyGroup", label = L.SET_CT_TAUNT_ONLY_GROUP,
    store = CtTaunt, key = "onlyInGroup", y = -66,
    tooltip = L.DESC_CT_TAUNT_ONLY_GROUP,
})
KART.CbCtTauntOnlyInstance = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntOnlyInstance", label = L.SET_CT_TAUNT_ONLY_INSTANCE,
    store = CtTaunt, key = "onlyInInstance", y = -66,
    tooltip = L.DESC_CT_TAUNT_ONLY_INSTANCE,
})
KART.CbCtTauntOnlyInstance:ClearAllPoints()
KART.CbCtTauntOnlyInstance:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 260, -66)
KART.CbCtTauntOnlyInstance.text:SetWidth(192)
KART.CbCtTauntOnlyInstance.text:SetJustifyH("LEFT")

local ctTauntChanTitle = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctTauntChanTitle:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 20, -100)
ctTauntChanTitle:SetText(L.SET_CT_TAUNT_CHANNELS)
KART.UI:RegisterLabel(ctTauntChanTitle)

KART.CbCtTauntWhisper = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntWhisper", label = L.SET_CT_TAUNT_WHISPER,
    store = CtTauntChannels, key = "WHISPER", y = -116,
})
KART.CbCtTauntGroup = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntGroup", label = L.SET_CT_TAUNT_GROUP,
    store = CtTauntChannels, key = "GROUP", y = -116,
})
KART.CbCtTauntGroup:ClearAllPoints()
KART.CbCtTauntGroup:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 260, -116)
KART.CbCtTauntGroup.text:SetWidth(192)
KART.CbCtTauntGroup.text:SetJustifyH("LEFT")

KART.CbCtTauntRW = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntRW", label = L.SET_CT_TAUNT_RW,
    store = CtTauntChannels, key = "RAID_WARNING", y = -146,
})
KART.CbCtTauntSay = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntSay", label = L.SET_CT_TAUNT_SAY,
    store = CtTauntChannels, key = "SAY", y = -146,
})
KART.CbCtTauntSay:ClearAllPoints()
KART.CbCtTauntSay:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 260, -146)

KART.CbCtTauntYell = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntYell", label = L.SET_CT_TAUNT_YELL,
    store = CtTauntChannels, key = "YELL", y = -176,
})

local ctTauntMsgLabel = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctTauntMsgLabel:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 20, -210)
ctTauntMsgLabel:SetText(L.SET_CT_TAUNT_MESSAGE)
KART.UI:RegisterLabel(ctTauntMsgLabel)

KART.EbCtTauntMessage = KART.UI:CreateStyledEditBox(ctTauntCard, "KART_CtTauntMessage")
KART.EbCtTauntMessage:SetSize(460, 28)
KART.EbCtTauntMessage:SetPoint("TOPLEFT", ctTauntMsgLabel, "BOTTOMLEFT", 0, -6)
KART.EbCtTauntMessage:SetMaxLetters(200)
KART.EbCtTauntMessage:SetScript("OnTextChanged", function(self)
    CtTaunt().message = self:GetText()
end)

local ctTauntPlace = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctTauntPlace:SetPoint("TOPLEFT", KART.EbCtTauntMessage, "BOTTOMLEFT", 0, -6)
ctTauntPlace:SetWidth(460)
ctTauntPlace:SetJustifyH("LEFT")
ctTauntPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS)
KART.UI:RegisterLabel(ctTauntPlace)

local ctAskCard = KART.UI:CreateCard(KART.CoTankPanel)
ctAskCard:SetPoint("TOPLEFT", ctTauntCard, "BOTTOMLEFT", 0, -20)
ctAskCard:SetSize(500, 340)

local ctAskTitle = ctAskCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctAskTitle:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 20, -14)
ctAskTitle:SetText(L.LABEL_CT_TAUNT_ASK)
KART.UI:RegisterLabel(ctAskTitle)

KART.CbCtTauntButton = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntButton", label = L.SET_CT_TAUNT_BUTTON,
    store = CtTaunt, key = "button", y = -36,
    tooltip = L.DESC_CT_TAUNT_BUTTON,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntButton.text:SetWidth(430)
KART.CbCtTauntButton.text:SetJustifyH("LEFT")

KART.CbCtTauntBtnLock = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnLock", label = L.SET_CT_TAUNT_BTN_LOCK,
    store = CtTaunt, key = "locked", y = -66,
    tooltip = L.DESC_CT_TAUNT_BTN_LOCK,
})
KART.CbCtTauntBtnGroup = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnGroup", label = L.SET_CT_TAUNT_BTN_GROUP,
    store = CtTaunt, key = "buttonOnlyInGroup", y = -96,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntBtnRaid = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnRaid", label = L.SET_CT_TAUNT_BTN_RAID,
    store = CtTaunt, key = "buttonOnlyInRaid", y = -96,
    tooltip = L.DESC_CT_TAUNT_BTN_RAID,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntBtnRaid:ClearAllPoints()
KART.CbCtTauntBtnRaid:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 260, -96)
KART.CbCtTauntBtnRaid.text:SetWidth(192)
KART.CbCtTauntBtnRaid.text:SetJustifyH("LEFT")

KART.SldCtTauntSize = KART.UI:CreateSettingsSlider(ctAskCard, {
    name = "KART_CtTauntSizeSlider", label = L.SET_CT_TAUNT_SIZE,
    min = 20, max = 80, store = CtTaunt, key = "size", y = -136,
    onChanged = CtTauntChanged,
})

local ctAskMsgLabel = ctAskCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctAskMsgLabel:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 20, -186)
ctAskMsgLabel:SetText(L.SET_CT_TAUNT_ASK)
KART.UI:RegisterLabel(ctAskMsgLabel)

KART.EbCtTauntAsk = KART.UI:CreateStyledEditBox(ctAskCard, "KART_CtTauntAsk")
KART.EbCtTauntAsk:SetSize(460, 28)
KART.EbCtTauntAsk:SetPoint("TOPLEFT", ctAskMsgLabel, "BOTTOMLEFT", 0, -6)
KART.EbCtTauntAsk:SetMaxLetters(200)
KART.EbCtTauntAsk:SetScript("OnTextChanged", function(self)
    CtTaunt().ask = self:GetText()
end)

local ctAskPlace = ctAskCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctAskPlace:SetPoint("TOPLEFT", KART.EbCtTauntAsk, "BOTTOMLEFT", 0, -6)
ctAskPlace:SetWidth(460)
ctAskPlace:SetJustifyH("LEFT")
ctAskPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS)
KART.UI:RegisterLabel(ctAskPlace)

KART.BtnCtTauntMacro = KART.UI:CreateModernButton(ctAskCard, L.BTN_CT_TAUNT_MACRO, L.DESC_CT_TAUNT_MACRO)
KART.BtnCtTauntMacro:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 20, -280)
KART.BtnCtTauntMacro:SetSize(280, 24)
KART.BtnCtTauntMacro:SetScript("OnClick", function()
    if not KART.CT or not KART.CT.CreateAskMacro then return end
    local result = KART.CT.CreateAskMacro()
    if result == "combat" and UIErrorsFrame then
        UIErrorsFrame:AddMessage(L.ERR_CT_TAUNT_MACRO_COMBAT, 1, 0.1, 0.1, 1, 3)
    end
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
    KART.BtnCoTank.text:SetText(L.TAB_COTANK)
    KART.BtnSettings.text:SetText(L.TAB_SETTINGS)
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.LABEL_RAIDLEAD_TOOLS)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    if KART.TabTitles[6] then KART.TabTitles[6]:SetText(L.LABEL_COTANK_SETTINGS) end
    -- TabTitles[5] belongs to Invite.lua and is refreshed there.

    -- Raidlead tab
    KART.CbActivate.text:SetText(L.SET_RL_ACTIVATE)   KART.CbActivate.tooltipText = L.DESC_RL_ACTIVATE
    KART.CbLock.text:SetText(L.SET_RL_LOCK)           KART.CbLock.tooltipText = L.DESC_RL_LOCK
    KART.CbAutoHide.text:SetText(L.SET_RL_AUTOHIDE)   KART.CbAutoHide.tooltipText = L.DESC_RL_AUTOHIDE
    KART.CbAutoHideCombat.text:SetText(L.SET_RL_AUTOHIDE_COMBAT)
    KART.CbAutoHideCombat.tooltipText = L.DESC_RL_AUTOHIDE_COMBAT
    KART.CbRcReasonDialog.text:SetText(L.SET_RL_RC_REASON)
    KART.CbRcReasonDialog.tooltipText = L.DESC_RL_RC_REASON
    KART.PullSlider.title:SetText(L.SET_PULL_TIMER)   KART.PullSlider.tooltipText = L.DESC_PULL_TIMER
    KART.SldRlBarStrata.title:SetText(L.SET_RL_STRATA) KART.SldRlBarStrata.tooltipText = L.DESC_RL_STRATA
    KART.CbRlBarYieldMap.text:SetText(L.SET_RL_YIELD_MAP)
    KART.CbRlBarYieldMap.tooltipText = L.DESC_RL_YIELD_MAP
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

    -- Co-Tank tab
    KART.CbCtModuleEnabled.text:SetText(L.SET_CT_MODULE_ENABLED)  KART.CbCtModuleEnabled.tooltipText = L.DESC_CT_MODULE_ENABLED
    KART.CbCtTestMode.text:SetText(L.SET_CT_TESTMODE)             KART.CbCtTestMode.tooltipText = L.DESC_CT_TESTMODE
    KART.CbCtLock.text:SetText(L.SET_CT_LOCK)                     KART.CbCtLock.tooltipText = L.DESC_CT_LOCK
    if KART.CbCtOnlyGroup then
        KART.CbCtOnlyGroup.text:SetText(L.SET_CT_ONLY_GROUP)
        KART.CbCtOnlyGroup.tooltipText = L.DESC_CT_ONLY_GROUP
    end
    if KART.CbCtOnlyInstance then
        KART.CbCtOnlyInstance.text:SetText(L.SET_CT_ONLY_INSTANCE)
        KART.CbCtOnlyInstance.tooltipText = L.DESC_CT_ONLY_INSTANCE
    end
    if ctPreviewTitle then ctPreviewTitle:SetText(L.LABEL_CT_PREVIEW) end
    if KART.CtAuraEngineNote then KART.CtAuraEngineNote:SetText(L.SET_CT_AURA_ENGINE) end
    KART.SldCtWidth.title:SetText(L.SET_CT_WIDTH)
    KART.SldCtHeight.title:SetText(L.SET_CT_HEIGHT)
    KART.SldCtScale.title:SetText(L.SET_CT_SCALE)
    KART.SldCtRangeFade.title:SetText(L.SET_CT_RANGE_FADE)
    KART.SldCtNameMax.title:SetText(L.SET_CT_NAME_MAX)
    KART.CbCtAbsorb.text:SetText(L.SET_CT_ABSORB)
    KART.CbCtHealAbsorb.text:SetText(L.SET_CT_HEAL_ABSORB)
    KART.BtnCtHealthColor.tooltipText = L.DESC_CT_HEALTH_COLOR
    KART.BtnCtHealthText.tooltipText = L.DESC_CT_HEALTH_TEXT
    RefreshCtHealthColorBtn()
    RefreshCtHealthTextBtn()
    if RefreshCtFillBtn then RefreshCtFillBtn() end
    if KART.SldCtHealthAlpha then KART.SldCtHealthAlpha.title:SetText(L.SET_CT_HEALTH_ALPHA) end
    if KART.SldCtTrackAlpha then KART.SldCtTrackAlpha.title:SetText(L.SET_CT_TRACK_ALPHA) end
    if KART.SldCtBgAlpha then KART.SldCtBgAlpha.title:SetText(L.SET_CT_BG_ALPHA) end
    if KART.SldCtBorderSize then KART.SldCtBorderSize.title:SetText(L.SET_CT_BORDER_SIZE) end
    if KART.SldCtAbsorbAlpha then KART.SldCtAbsorbAlpha.title:SetText(L.SET_CT_ABSORB_ALPHA) end
    if KART.SldCtHealAbsorbAlpha then KART.SldCtHealAbsorbAlpha.title:SetText(L.SET_CT_HEAL_ABSORB_ALPHA) end
    if KART.BtnCtCustomColor then KART.BtnCtCustomColor.text:SetText(L.SET_CT_CUSTOM_COLOR) end
    if KART.BtnCtBgColor then KART.BtnCtBgColor.text:SetText(L.SET_CT_BG_COLOR) end
    if KART.BtnCtHealthHigh then KART.BtnCtHealthHigh.text:SetText(L.SET_CT_HEALTH_HIGH) end
    if KART.BtnCtHealthMid then KART.BtnCtHealthMid.text:SetText(L.SET_CT_HEALTH_MID) end
    if KART.BtnCtHealthLow then KART.BtnCtHealthLow.text:SetText(L.SET_CT_HEALTH_LOW) end
    if KART.BtnCtBorderColor then KART.BtnCtBorderColor.text:SetText(L.SET_CT_BORDER_COLOR) end
    if KART.BtnCtAbsorbColor then KART.BtnCtAbsorbColor.text:SetText(L.SET_CT_ABSORB_COLOR) end
    if KART.BtnCtHealAbsorbColor then KART.BtnCtHealAbsorbColor.text:SetText(L.SET_CT_HEAL_ABSORB_COLOR) end
    if KART.BtnCtHealthFill then KART.BtnCtHealthFill.tooltipText = L.DESC_CT_HEALTH_FILL end
    if KART.CbCtRangeFadeOn then KART.CbCtRangeFadeOn.text:SetText(L.SET_CT_RANGE_FADE_ON) end
    if KART.SldCtDeadFade then KART.SldCtDeadFade.title:SetText(L.SET_CT_DEAD_FADE) end
    if KART.SldCtOfflineFade then KART.SldCtOfflineFade.title:SetText(L.SET_CT_OFFLINE_FADE) end
    if KART.CbCtTargetBorder then
        KART.CbCtTargetBorder.text:SetText(L.SET_CT_TARGET_BORDER)
        KART.CbCtTargetBorder.tooltipText = L.DESC_CT_TARGET_BORDER
    end
    if KART.SldCtTargetBorderSize then KART.SldCtTargetBorderSize.title:SetText(L.SET_CT_TARGET_BORDER_SIZE) end
    if KART.BtnCtTargetBorderColor then KART.BtnCtTargetBorderColor.text:SetText(L.SET_CT_TARGET_BORDER_COLOR) end
    local function relabelText(w, title)
        if not w then return end
        if w.titleFS then w.titleFS:SetText(title) end
        if w.show then w.show.text:SetText(L.SET_CT_TEXT_SHOW) end
        if w.size then w.size.title:SetText(L.SET_CT_TEXT_SIZE) end
        if w.colorBtn then w.colorBtn.text:SetText(L.SET_CT_TEXT_COLOR) end
        if w.classCb then w.classCb.text:SetText(L.SET_CT_TEXT_CLASS) end
        if w.nudgeX then w.nudgeX.title:SetText(L.SET_CT_TEXT_NUDGE_X) end
        if w.nudgeY then w.nudgeY.title:SetText(L.SET_CT_TEXT_NUDGE_Y) end
        if w.refreshOutline then w.refreshOutline() end
        if w.refreshAnchor then w.refreshAnchor() end
    end
    relabelText(KART.CtNameTextWidgets, L.LABEL_CT_NAME_TEXT)
    relabelText(KART.CtHealthTextWidgets, L.LABEL_CT_HEALTH_TEXT)
    local function relabelStripExtra(extra)
        if not extra then return end
        extra.perRow.title:SetText(L.SET_CT_AURA_PER_ROW)
        extra.border.title:SetText(L.SET_CT_AURA_BORDER)
        extra.nudgeX.title:SetText(L.SET_CT_AURA_NUDGE_X)
        extra.nudgeY.title:SetText(L.SET_CT_AURA_NUDGE_Y)
        extra.borderColor.text:SetText(L.SET_CT_AURA_BORDER_COLOR)
        extra.swipe.text:SetText(L.SET_CT_AURA_SWIPE)
        extra.countdown.text:SetText(L.SET_CT_AURA_COUNTDOWN)
        extra.cdSize.title:SetText(L.SET_CT_AURA_COUNTDOWN_SIZE)
        extra.stacks.text:SetText(L.SET_CT_AURA_STACKS)
        extra.stSize.title:SetText(L.SET_CT_AURA_STACKS_SIZE)
    end
    relabelStripExtra(KART.CtDebuffExtra)
    relabelStripExtra(KART.CtBuffExtra)
    if ctAuraChromeNote then ctAuraChromeNote:SetText(L.SET_CT_AURA_DUMMY_CHROME) end
    ctDebuffTitle:SetText(L.LABEL_CT_DEBUFFS)
    ctBuffTitle:SetText(L.LABEL_CT_BUFFS)
    KART.CbCtDebuffShow.text:SetText(L.SET_CT_AURA_SHOW)
    KART.SldCtDebuffMax.title:SetText(L.SET_CT_AURA_MAX)
    KART.SldCtDebuffSize.title:SetText(L.SET_CT_AURA_SIZE)
    KART.SldCtDebuffSpacing.title:SetText(L.SET_CT_AURA_SPACING)
    KART.BtnCtDebuffAnchor.tooltipText = L.DESC_CT_AURA_ANCHOR
    KART.BtnCtDebuffGrowth.tooltipText = L.DESC_CT_AURA_GROWTH
    RefreshCtDebuffAnchorBtn()
    RefreshCtDebuffGrowthBtn()
    KART.CbCtBuffShow.text:SetText(L.SET_CT_AURA_SHOW)
    KART.SldCtBuffMax.title:SetText(L.SET_CT_AURA_MAX)
    KART.SldCtBuffSize.title:SetText(L.SET_CT_AURA_SIZE)
    KART.SldCtBuffSpacing.title:SetText(L.SET_CT_AURA_SPACING)
    KART.BtnCtBuffAnchor.tooltipText = L.DESC_CT_AURA_ANCHOR
    KART.BtnCtBuffGrowth.tooltipText = L.DESC_CT_AURA_GROWTH
    RefreshCtBuffAnchorBtn()
    RefreshCtBuffGrowthBtn()
    if ctTauntTitle then ctTauntTitle:SetText(L.LABEL_CT_TAUNT) end
    if ctTauntChanTitle then ctTauntChanTitle:SetText(L.SET_CT_TAUNT_CHANNELS) end
    if ctTauntMsgLabel then ctTauntMsgLabel:SetText(L.SET_CT_TAUNT_MESSAGE) end
    if ctTauntPlace then ctTauntPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS) end
    if ctAskTitle then ctAskTitle:SetText(L.LABEL_CT_TAUNT_ASK) end
    if ctAskMsgLabel then ctAskMsgLabel:SetText(L.SET_CT_TAUNT_ASK) end
    if ctAskPlace then ctAskPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS) end
    if KART.CbCtTauntAnnounce then
        KART.CbCtTauntAnnounce.text:SetText(L.SET_CT_TAUNT_ANNOUNCE)
        KART.CbCtTauntAnnounce.tooltipText = L.DESC_CT_TAUNT_ANNOUNCE
    end
    if KART.CbCtTauntOnlyGroup then
        KART.CbCtTauntOnlyGroup.text:SetText(L.SET_CT_TAUNT_ONLY_GROUP)
        KART.CbCtTauntOnlyGroup.tooltipText = L.DESC_CT_TAUNT_ONLY_GROUP
    end
    if KART.CbCtTauntOnlyInstance then
        KART.CbCtTauntOnlyInstance.text:SetText(L.SET_CT_TAUNT_ONLY_INSTANCE)
        KART.CbCtTauntOnlyInstance.tooltipText = L.DESC_CT_TAUNT_ONLY_INSTANCE
    end
    if KART.CbCtTauntWhisper then KART.CbCtTauntWhisper.text:SetText(L.SET_CT_TAUNT_WHISPER) end
    if KART.CbCtTauntGroup then KART.CbCtTauntGroup.text:SetText(L.SET_CT_TAUNT_GROUP) end
    if KART.CbCtTauntRW then KART.CbCtTauntRW.text:SetText(L.SET_CT_TAUNT_RW) end
    if KART.CbCtTauntSay then KART.CbCtTauntSay.text:SetText(L.SET_CT_TAUNT_SAY) end
    if KART.CbCtTauntYell then KART.CbCtTauntYell.text:SetText(L.SET_CT_TAUNT_YELL) end
    if KART.CbCtTauntButton then
        KART.CbCtTauntButton.text:SetText(L.SET_CT_TAUNT_BUTTON)
        KART.CbCtTauntButton.tooltipText = L.DESC_CT_TAUNT_BUTTON
    end
    if KART.CbCtTauntBtnLock then
        KART.CbCtTauntBtnLock.text:SetText(L.SET_CT_TAUNT_BTN_LOCK)
        KART.CbCtTauntBtnLock.tooltipText = L.DESC_CT_TAUNT_BTN_LOCK
    end
    if KART.CbCtTauntBtnGroup then KART.CbCtTauntBtnGroup.text:SetText(L.SET_CT_TAUNT_BTN_GROUP) end
    if KART.CbCtTauntBtnRaid then
        KART.CbCtTauntBtnRaid.text:SetText(L.SET_CT_TAUNT_BTN_RAID)
        KART.CbCtTauntBtnRaid.tooltipText = L.DESC_CT_TAUNT_BTN_RAID
    end
    if KART.SldCtTauntSize then KART.SldCtTauntSize.title:SetText(L.SET_CT_TAUNT_SIZE) end
    if KART.BtnCtTauntMacro then
        KART.BtnCtTauntMacro.text:SetText(L.BTN_CT_TAUNT_MACRO)
        KART.BtnCtTauntMacro.tooltipText = L.DESC_CT_TAUNT_MACRO
    end

    -- Automation tab
    promLabel:SetText(L.LABEL_PROMOTE_NAMES)
    invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
    chanLabel:SetText(L.SET_INVITE_CHANNELS)
    if KART.InviteChannelChips then
        local chipLabels = {
            WHISPER = L.SET_INVITE_CHANNEL_WHISPER,
            BN = L.SET_INVITE_CHANNEL_BN,
            GUILD = L.SET_INVITE_CHANNEL_GUILD,
            OFFICER = L.SET_INVITE_CHANNEL_OFFICER,
        }
        local chipKeys = { "WHISPER", "BN", "GUILD", "OFFICER" }
        for i, chip in ipairs(KART.InviteChannelChips) do
            local key = chipKeys[i]
            chip.text:SetText(chipLabels[key])
            chip.tooltipText = L["DESC_INVITE_CHANNEL_" .. key]
        end
    end
    KART.CbAutoRaid.text:SetText(L.SET_AUTO_RAID)                 KART.CbAutoRaid.tooltipText = L.DESC_AUTO_RAID
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
