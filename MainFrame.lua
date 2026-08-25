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
    if KART.UpdateCtFlyoutVisibility then KART.UpdateCtFlyoutVisibility() end
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
    if KART.UpdateCtFlyoutVisibility then KART.UpdateCtFlyoutVisibility() end
    if KART.CT and KART.CT.OnSettingsTab then KART.CT.OnSettingsTab(false) end
end)
mainFrame:HookScript("OnShow", function()
    if KART.UpdateCtFlyoutAnchor then KART.UpdateCtFlyoutAnchor() end
    if KART.UpdateCtFlyoutVisibility then KART.UpdateCtFlyoutVisibility() end
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
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

-- Footer links sit above the version string; WoW cannot open a browser, so click
-- shows the URL in a box the player can copy with Ctrl+C.
KART.FooterLinks = {}
do
    local linkDefs = {
        { localeKey = "LINK_CURSEFORGE", url = "https://www.curseforge.com/wow/addons/keine-ahnung-raid-tools" },
        { localeKey = "LINK_WAGO", url = "https://addons.wago.io/addons/qn53zokb" },
        { localeKey = "LINK_GITHUB", url = "https://github.com/Kandera/KeineAhnungRaidTools" },
    }
    local prev
    for i, def in ipairs(linkDefs) do
        local btn = CreateFrame("Button", nil, clickArea)
        btn:SetHeight(12)
        btn.url = def.url
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.text:SetText(L[def.localeKey])
        btn.text:SetTextColor(0.55, 0.55, 0.55)
        KART.UI:RegisterLabel(btn.text)
        btn:SetWidth(btn.text:GetStringWidth() + 2)
        btn:SetScript("OnClick", function(self) KART.CopyLink(self.url) end)
        btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) self.text:SetTextColor(0.55, 0.55, 0.55) end)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            btn:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 18, 28)
        end
        prev = btn
        KART.FooterLinks[i] = btn
    end
end

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
KART.BtnPromote = KART.UI:CreateTabButton(clickArea, L.TAB_PROMOTE, { moduleChip = true })
KART.BtnPromote:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 12, -75)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.UI:CreateTabButton(clickArea, L.TAB_RAIDLEAD, { moduleChip = true })
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.UI:CreateTabButton(clickArea, L.TAB_BUFFCHECK, { moduleChip = true })
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnWoWUtils = KART.UI:CreateTabButton(clickArea, L.TAB_WOWUTILS, { moduleChip = true })
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(5) end)

-- The Settings tab must always be the last entry in the sidebar. When adding a new tab
-- button, anchor it above this one (i.e. insert it between the previous last tab and
-- Settings, and re-anchor Settings to the new button).
KART.BtnCoTank = KART.UI:CreateTabButton(clickArea, L.TAB_COTANK, { moduleChip = true })
KART.BtnCoTank:SetPoint("TOPLEFT", KART.BtnWoWUtils, "BOTTOMLEFT", 0, -5)
KART.BtnCoTank:SetScript("OnClick", function() KART.ShowTab(6) end)

KART.SidebarSystemHeader = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.SidebarSystemHeader:SetPoint("TOPLEFT", KART.BtnCoTank, "BOTTOMLEFT", 2, -10)
KART.SidebarSystemHeader:SetText(L.LABEL_SYSTEM)
KART.UI:RegisterLabel(KART.SidebarSystemHeader)

KART.BtnSettings = KART.UI:CreateTabButton(clickArea, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.SidebarSystemHeader, "BOTTOMLEFT", -2, -4)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

-- Edit Mode and Changelog sit above the footer links, not in the tab list.
KART.BtnChangelog = KART.UI:CreateModernButton(clickArea, L.BTN_CHANGELOG, L.DESC_CHANGELOG)
KART.BtnChangelog:SetSize(176, 22)
KART.BtnChangelog:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 12, 46)
KART.BtnChangelog:SetScript("OnClick", function() KART.ShowChangelogPopup() end)

KART.BtnEditMode = KART.UI:CreateModernButton(clickArea, L.BTN_EDIT_MODE_OFF, L.DESC_EDIT_MODE)
KART.BtnEditMode:SetSize(176, 22)
KART.BtnEditMode:SetPoint("BOTTOMLEFT", KART.BtnChangelog, "TOPLEFT", 0, 5)
KART.BtnEditMode:SetScript("OnClick", function()
    KART.SetEditModeActive(not KART.IsEditModeActive())
end)
function KART.RefreshEditModeToggle()
    if not KART.BtnEditMode then return end
    local on = KART.IsEditModeActive()
    KART.BtnEditMode.text:SetText(on and L.BTN_EDIT_MODE_ON or L.BTN_EDIT_MODE_OFF)
    if on then
        local r, g, b = KART.UI:AccentColor()
        KART.BtnEditMode:SetBackdropColor(r, g, b, 0.7)
        KART.BtnEditMode:SetBackdropBorderColor(r, g, b, 1)
    else
        KART.BtnEditMode:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        KART.BtnEditMode:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

KART.ModuleChipKeys = {
    [KART.BtnPromote] = "autoModuleEnabled",
    [KART.BtnRaidlead] = "showRaidleadBar",
    [KART.BtnBuffCheck] = "bcModuleEnabled",
    [KART.BtnWoWUtils] = "wuModuleEnabled",
    [KART.BtnCoTank] = "ctModuleEnabled",
}
function KART.RefreshModuleChips()
    local s = KART_Settings
    if not s or not KART.ModuleChipKeys then return end
    for btn, key in pairs(KART.ModuleChipKeys) do
        if btn.SetModuleChipOn then btn:SetModuleChipOn(s[key] == true) end
    end
end

-- 4. Content area (ScrollFrame), right of the baked sidebar divider (200px).
-- Tonight strip sits just below the artwork's baked divider (~-48). The viewport starts
-- under that strip so scrolled content cannot cover the three glance fields.
local statusStrip = CreateFrame("Frame", nil, clickArea)
statusStrip:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 208, -52)
statusStrip:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -30, -52)
statusStrip:SetHeight(36)
KART.StatusStrip = statusStrip

local function MakeStatusCell(parent, x)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(170, 36)
    cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    cell.value = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cell.value:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -2)
    cell.value:SetJustifyH("LEFT")
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cell.label:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -2)
    cell.label:SetJustifyH("LEFT")
    KART.UI:RegisterLabel(cell.label)
    return cell
end

statusStrip.raid = MakeStatusCell(statusStrip, 0)
statusStrip.flask = MakeStatusCell(statusStrip, 180)
statusStrip.rc = MakeStatusCell(statusStrip, 360)
statusStrip.raidValue = statusStrip.raid.value
statusStrip.flaskValue = statusStrip.flask.value
statusStrip.rcValue = statusStrip.rc.value

function KART.RefreshStatusStrip()
    local strip = KART.StatusStrip
    if not strip then return end
    local L = KART.L
    local present, total = 0, 0
    if KART.WU and KART.WU.GroupPresenceForBoss then
        local idx = KART.WU.ActiveBossIndex and KART.WU.ActiveBossIndex()
        if idx then present, total = KART.WU.GroupPresenceForBoss(idx) end
    end
    strip.raid.label:SetText(L.STATUS_RAID or "in the raid")
    if total == 0 then
        strip.raidValue:SetText("—")
        strip.raidValue:SetTextColor(0.55, 0.55, 0.55)
    else
        strip.raidValue:SetText(present .. "/" .. total)
        if present < total then
            strip.raidValue:SetTextColor(unpack(KART.WARNING))
        else
            strip.raidValue:SetTextColor(unpack(KART.SUCCESS))
        end
    end
    local missing = (KART.CountMissingFlaskFood and KART.CountMissingFlaskFood()) or 0
    strip.flask.label:SetText(L.STATUS_FLASK_FOOD or "without flask/food")
    strip.flaskValue:SetText(tostring(missing))
    if missing > 0 then
        strip.flaskValue:SetTextColor(unpack(KART.DANGER))
    else
        strip.flaskValue:SetTextColor(unpack(KART.SUCCESS))
    end
    local rcOn = KART.RC and KART.RC.IsRCLoaded and KART.RC.IsRCLoaded()
    strip.rc.label:SetText(L.STATUS_RC or "RC loaded")
    strip.rcValue:SetText(rcOn and (L.STATUS_RC_ON or "on") or (L.STATUS_RC_OFF or "off"))
    if rcOn then
        strip.rcValue:SetTextColor(unpack(KART.SUCCESS))
    else
        strip.rcValue:SetTextColor(unpack(KART.WARNING))
    end
end

function KART.RefreshStatusStripThrottled()
    if KART._statusStripPending then return end
    KART._statusStripPending = true
    C_Timer.After(0.25, function()
        KART._statusStripPending = false
        if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
    end)
end

local scrollFrame = CreateFrame("ScrollFrame", "KART_ContentScrollFrame", clickArea, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 208, -92)
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
    [1] = 565, -- Automation: enable card + promote/invite card + AutoLog
    [2] = 460, -- Raidlead: two-column bar card + keybinds card + gaps
    [3] = 190, -- BuffCheck: one 160 card
    [4] = 580, -- Settings: two half cards + accent/profiles row + RC companion card
    [6] = 1240, -- Co-Tank: preview + module + size + taunt (Look/Text/Auras live in the flyout)
}
function KART.UpdateScrollRange()
    local tab = KART.CurrentTab
    if not tab then return end
    local h = PANEL_CONTENT_HEIGHTS[tab]
    if tab == 5 then
        -- Enable card + import card + separator/headers above the boss list + bottom padding.
        local bl = KART.WU and KART.WU.bossListFrame
        h = 332 + ((bl and bl:GetHeight()) or 24)
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
-- Toggles left, look sliders right: the old stacked cards left the right half of a 500-wide
-- card empty. Same two-column packing as the Buff-Checker card.
rlCard:SetSize(500, 248)

local function PinRlToggle(cb, y)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", rlCard, "TOPLEFT", 20, y)
    cb.text:SetWidth(190)
    cb.text:SetJustifyH("LEFT")
end

local function PinRlSlider(s, y)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", rlCard, "TOPLEFT", 260, y)
end

-- Checkbox zur Aktivierung
KART.CbActivate = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarCheck", label = L.SET_RL_ACTIVATE,
    store = SettingsStore, key = "showRaidleadBar", y = -20,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
        KART.RefreshModuleChips()
    end,
    tooltip = L.DESC_RL_ACTIVATE,
})
PinRlToggle(KART.CbActivate, -20)

-- Checkbox zum Sperren
KART.CbLock = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarLockCheck", label = L.SET_RL_LOCK,
    store = SettingsStore, key = "lockRaidleadBar", y = -50,
    tooltip = L.DESC_RL_LOCK,
})
PinRlToggle(KART.CbLock, -50)

-- Checkbox für Auto-Hide
KART.CbAutoHide = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarAutoHideCheck", label = L.SET_RL_AUTOHIDE,
    store = SettingsStore, key = "autoHideRaidleadBar", y = -80,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
    end,
    tooltip = L.DESC_RL_AUTOHIDE,
})
PinRlToggle(KART.CbAutoHide, -80)

KART.CbAutoHideCombat = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarCombatHideCheck", label = L.SET_RL_AUTOHIDE_COMBAT,
    store = SettingsStore, key = "autoHideRaidleadBarCombat", y = -110,
    onChanged = function()
        KART.UpdateRaidleadBarVisibility()
    end,
    tooltip = L.DESC_RL_AUTOHIDE_COMBAT,
})
PinRlToggle(KART.CbAutoHideCombat, -110)

KART.CbRlBarYieldMap = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RaidleadBarYieldMapCheck", label = L.SET_RL_YIELD_MAP,
    store = SettingsStore, key = "rlBarYieldToMap", y = -140,
    onChanged = function()
        if KART.ApplyRaidleadBarStrata then KART.ApplyRaidleadBarStrata() end
    end,
    tooltip = L.DESC_RL_YIELD_MAP,
})
PinRlToggle(KART.CbRlBarYieldMap, -140)

-- Ready-check reason prompt. Sits on this tab because the ready check itself is a Raidlead Bar
-- button; the dialog it controls lives in Core.lua (KART.ShowReadyCheckReasonDialog). The label
-- is long in both locales, so it stays in the left column and wraps rather than stretching
-- the card back to a single unused-right column.
KART.CbRcReasonDialog = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_RcReasonDialogCheck", label = L.SET_RL_RC_REASON,
    store = SettingsStore, key = "rcReasonDialog", y = -175,
    tooltip = L.DESC_RL_RC_REASON,
})
PinRlToggle(KART.CbRcReasonDialog, -175)

-- Pull-Timer Slider: the pull button (RaidleadBar.lua) reads pullTimerDuration
-- at click time, so no macrotext attribute needs updating here anymore.
KART.PullSlider = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_PullTimerSlider", label = L.SET_PULL_TIMER,
    min = 5, max = 30, store = SettingsStore, key = "pullTimerDuration", y = -20,
    tooltip = L.DESC_PULL_TIMER,
})
PinRlSlider(KART.PullSlider, -36)

KART.SldRlBarStrata = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_RlBarStrataSlider", label = L.SET_RL_STRATA,
    min = 1, max = #KART.StrataLevels, store = SettingsStore, key = "rlBarFrameStrata", y = -64,
    tooltip = L.DESC_RL_STRATA,
    onChanged = function()
        if KART.ApplyRaidleadBarStrata then KART.ApplyRaidleadBarStrata() end
    end,
    valueIsText = true,
})
PinRlSlider(KART.SldRlBarStrata, -80)
local function UpdateRlBarStrataSliderText(self)
    self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
end
KART.SldRlBarStrata:HookScript("OnValueChanged", UpdateRlBarStrataSliderText)
KART.SldRlBarStrata:HookScript("OnShow", UpdateRlBarStrataSliderText)

KART.SldRlBarScale = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_RlBarScaleSlider", label = L.SET_RL_SCALE,
    min = 50, max = 150, store = SettingsStore, key = "rlBarScale", y = -108,
    onChanged = function()
        if KART.ApplyRaidleadBarLook then KART.ApplyRaidleadBarLook() end
    end,
    tooltip = L.DESC_RL_SCALE,
})
PinRlSlider(KART.SldRlBarScale, -124)

KART.SldRlBarButtonSize = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_RlBarButtonSizeSlider", label = L.SET_RL_BUTTON_SIZE,
    min = 16, max = 32, store = SettingsStore, key = "rlBarButtonSize", y = -152,
    onChanged = function()
        if KART.ApplyRaidleadBarLook then KART.ApplyRaidleadBarLook() end
    end,
    tooltip = L.DESC_RL_BUTTON_SIZE,
})
PinRlSlider(KART.SldRlBarButtonSize, -168)

KART.SldRlBarAlpha = KART.UI:CreateSettingsSlider(rlCard, {
    name = "KART_RlBarAlphaSlider", label = L.SET_RL_ALPHA,
    min = 20, max = 100, store = SettingsStore, key = "rlBarAlpha", y = -196,
    onChanged = function()
        if KART.ApplyRaidleadBarLook then KART.ApplyRaidleadBarLook() end
    end,
    tooltip = L.DESC_RL_ALPHA,
})
PinRlSlider(KART.SldRlBarAlpha, -212)

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
    onChanged = function() KART.RefreshModuleChips() end,
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

local autoEnableCard = KART.UI:CreateCard(KART.PromotePanel)
autoEnableCard:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -12)
autoEnableCard:SetSize(500, 50)
KART.CbAutoModule = KART.UI:CreateSettingsCheckbox(autoEnableCard, {
    name = "KART_AutoModuleEnabled", label = L.SET_AUTO_MODULE_ENABLED,
    store = SettingsStore, key = "autoModuleEnabled", y = -20,
    tooltip = L.DESC_AUTO_MODULE_ENABLED,
    onChanged = function() KART.RefreshModuleChips() end,
})
KART.CbAutoModule.text:SetWidth(430)
KART.CbAutoModule.text:SetJustifyH("LEFT")

local autoCard = KART.UI:CreateCard(KART.PromotePanel)
autoCard:SetPoint("TOPLEFT", autoEnableCard, "BOTTOMLEFT", 0, -12)
autoCard:SetSize(500, 250)

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

-- MainFrame.lua runs before Core.lua's ADDON_LOADED, which is when KART_Settings first exists.
-- Chip Refresh/OnClick must not index it at file-load time; SyncSettingsToUI paints them after.
local function InviteChannels()
    if not KART_Settings then return nil end
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
    btn:SetPoint("TOPLEFT", chanLabel, "BOTTOMLEFT", xOff, -8)
    btn.tooltipText = L["DESC_INVITE_CHANNEL_" .. key]
    local function paint(on)
        local r, g, b = KART.UI:AccentColor()
        if on then
            btn:SetBackdropColor(r, g, b, 0.55)
            btn:SetBackdropBorderColor(r, g, b, 1)
            btn.text:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
            btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
            btn.text:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    local function refresh()
        local ch = InviteChannels()
        if not ch then return end
        btn.chipOn = ch[key] == true
        paint(btn.chipOn)
    end
    btn:SetScript("OnClick", function()
        local ch = InviteChannels()
        if not ch then return end
        ch[key] = not ch[key]
        if key == "GUILD" then KART_Settings.inviteViaGuildChat = ch[key] end
        refresh()
    end)
    -- CreateModernButton's OnLeave always paints the resting gray, which would make an ON chip
    -- look off the moment the mouse leaves. Hover/leave keep the on/off fill and only lift it.
    btn:SetScript("OnEnter", function(self)
        local r, g, b = KART.UI:AccentColor()
        if self.chipOn then
            local lr, lg, lb = KAUI.Lighten(r, g, b, 0.12)
            self:SetBackdropColor(lr, lg, lb, 0.75)
        else
            self:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        refresh()
    end)
    btn.Refresh = refresh
    refresh()
    return btn
end

KART.InviteChannelChips = {
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_WHISPER, "WHISPER", 0),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_BN, "BN", 114),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_GUILD, "GUILD", 228),
    CreateInviteChannelChip(autoCard, L.SET_INVITE_CHANNEL_OFFICER, "OFFICER", 342),
}

KART.CbAutoRaid = KART.UI:CreateSettingsCheckbox(autoCard, {
    name = "KART_AutoRaidCheck", label = L.SET_AUTO_RAID,
    store = SettingsStore, key = "autoConvertToRaid", y = -200,
    tooltip = L.DESC_AUTO_RAID,
})
KART.CbAutoRaid:ClearAllPoints()
KART.CbAutoRaid:SetPoint("TOPLEFT", KART.InviteChannelChips[1], "BOTTOMLEFT", 0, -14)
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

-- Card: accent, reset, and profiles on two filled rows. A full-width empty colour
-- card plus a tall profiles card wasted the middle of this tab; RC.BuildSettingsCard
-- still anchors under BtnProfile:GetParent(), so this stays that parent.
local colCard = KART.UI:CreateCard(KART.SettingsPanel)
colCard:SetPoint("TOPLEFT", ifCard, "BOTTOMLEFT", 0, -20)
colCard:SetSize(500, 88)
KART.SettingsColorCard = colCard

-- Color Buttons
KART.BtnAccentColor = KART.UI:CreateModernButton(colCard, L.BTN_ACCENT_COLOR, L.DESC_ACCENT_COLOR)
KART.BtnAccentColor:SetPoint("TOPLEFT", colCard, "TOPLEFT", 20, -16)
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
KART.BtnReset:SetPoint("TOPRIGHT", colCard, "TOPRIGHT", -20, -16)
-- Confirmed, like every other destructive action in the addon (boss-list reset, profile delete):
-- this discards every setting, window position and keybind with no undo.
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

KART.BtnProfile = KART.UI:CreateModernButton(colCard, L.PROFILE_LABEL_PREFIX .. L.PROFILE_NONE)
KART.BtnProfile:SetPoint("TOPLEFT", colCard, "TOPLEFT", 20, -50)
KART.BtnProfile:SetSize(176, 25)
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

KART.BtnProfileSaveNew = KART.UI:CreateModernButton(colCard, L.BTN_PROFILE_SAVE_NEW, L.DESC_PROFILE_SAVE_NEW)
KART.BtnProfileSaveNew:SetPoint("LEFT", KART.BtnProfile, "RIGHT", 6, 0)
KART.BtnProfileSaveNew:SetSize(118, 25)
KART.BtnProfileSaveNew:SetScript("OnClick", function()
    KART.ShowSaveProfileDialog()
end)

KART.BtnProfileSave = KART.UI:CreateModernButton(colCard, L.BTN_PROFILE_SAVE, L.DESC_PROFILE_SAVE)
KART.BtnProfileSave:SetPoint("LEFT", KART.BtnProfileSaveNew, "RIGHT", 6, 0)
KART.BtnProfileSave:SetSize(72, 25)
KART.BtnProfileSave:SetScript("OnClick", function()
    local name = KART_Settings.activeProfile
    if not name then return end
    KART.SaveProfile(name)
    KART.RefreshProfileButton()
end)

KART.BtnProfileDelete = KART.UI:CreateModernButton(colCard, L.BTN_PROFILE_DELETE, L.DESC_PROFILE_DELETE)
KART.BtnProfileDelete:SetPoint("LEFT", KART.BtnProfileSave, "RIGHT", 6, 0)
KART.BtnProfileDelete:SetSize(72, 25)
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
    if KART.UpdateCtFlyoutVisibility then KART.UpdateCtFlyoutVisibility() end
    KART.RefreshModuleChips()
end
local function CtLayoutChanged()
    if KART.CT and KART.CT.ApplyLayout then KART.CT.ApplyLayout() end
    CtRefresh()
    if KART.RefreshCtGradientSwatches then KART.RefreshCtGradientSwatches() end
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
ctModCard:SetSize(500, 110)

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
    store = CtStore, key = "testMode", y = -20,
    tooltip = L.DESC_CT_TESTMODE,
    onChanged = CtRefresh,
})
KART.CbCtTestMode:ClearAllPoints()
KART.CbCtTestMode:SetPoint("TOPLEFT", ctModCard, "TOPLEFT", 260, -20)
KART.CbCtTestMode.text:SetWidth(190)
KART.CbCtTestMode.text:SetJustifyH("LEFT")

KART.CbCtLock = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtLock", label = L.SET_CT_LOCK,
    store = CtStore, key = "locked", y = -50,
    tooltip = L.DESC_CT_LOCK,
    onChanged = CtRefresh,
})
KART.CbCtLock.text:SetWidth(190)
KART.CbCtLock.text:SetJustifyH("LEFT")

KART.CbCtOnlyGroup = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyGroup", label = L.SET_CT_ONLY_GROUP,
    store = CtStore, key = "onlyInGroup", y = -50,
    tooltip = L.DESC_CT_ONLY_GROUP,
    onChanged = CtRefresh,
})
KART.CbCtOnlyGroup:ClearAllPoints()
KART.CbCtOnlyGroup:SetPoint("TOPLEFT", ctModCard, "TOPLEFT", 260, -50)
KART.CbCtOnlyGroup.text:SetWidth(190)
KART.CbCtOnlyGroup.text:SetJustifyH("LEFT")

KART.CbCtOnlyInstance = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyInstance", label = L.SET_CT_ONLY_INSTANCE,
    store = CtStore, key = "onlyInInstance", y = -80,
    tooltip = L.DESC_CT_ONLY_INSTANCE,
    onChanged = CtRefresh,
})
KART.CbCtOnlyInstance.text:SetWidth(220)
KART.CbCtOnlyInstance.text:SetJustifyH("LEFT")

local ctRowCard = KART.UI:CreateCard(KART.CoTankPanel)
ctRowCard:SetPoint("TOPLEFT", ctModCard, "BOTTOMLEFT", 0, -20)
ctRowCard:SetSize(500, 120)

KART.SldCtWidth = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtWidthSlider", label = L.SET_CT_WIDTH,
    min = 100, max = 400, store = CtStore, key = "width", y = -20,
    onChanged = CtLayoutChanged,
})
KART.SldCtHeight = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtHeightSlider", label = L.SET_CT_HEIGHT,
    min = 20, max = 80, store = CtStore, key = "height", y = -20,
    onChanged = CtLayoutChanged,
})
KART.SldCtHeight:ClearAllPoints()
KART.SldCtHeight:SetPoint("TOPLEFT", ctRowCard, "TOPLEFT", 260, -36)
KART.SldCtScale = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtScaleSlider", label = L.SET_CT_SCALE,
    min = 50, max = 200, store = CtStore, key = "scale", y = -70,
    onChanged = function()
        CtStore().scale = KART.SldCtScale:GetValue() / 100
        CtLayoutChanged()
    end,
})

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

-- Co-Tank settings flyout (Look / Text / Auras), parented to UIParent beside the main window.
local ctFlyout = CreateFrame("Frame", "KART_CtFlyout", UIParent, "BackdropTemplate")
ctFlyout:SetSize(580, 700)
KART.UI:ApplyPopupArtwork(ctFlyout)
KART.UI:ApplyPopupChrome(ctFlyout, { title = L.TAB_COTANK })
KART.UI:RegisterStrataFrame(ctFlyout)
ctFlyout:SetClampedToScreen(true)
ctFlyout:SetMovable(true)
ctFlyout:EnableMouse(true)
ctFlyout:RegisterForDrag("LeftButton")
ctFlyout:SetScript("OnDragStart", function(self) self:StartMoving() end)
ctFlyout:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.userPlaced = true
end)
ctFlyout:Hide()
KART.CtFlyout = ctFlyout

function KART.UpdateCtFlyoutAnchor()
    if not KART.CtFlyout or not KART.MainFrame then return end
    if KART.CtFlyout.userPlaced then return end
    KART.CtFlyout:ClearAllPoints()
    KART.CtFlyout:SetPoint("TOPLEFT", KART.MainFrame, "TOPRIGHT", 8, -64)
end

function KART.UpdateCtFlyoutVisibility()
    if not KART.CtFlyout then return end
    local show = KART.CurrentTab == 6
        and KART.MainFrame and KART.MainFrame:IsShown()
        and KART_Settings and KART_Settings.ctModuleEnabled
    if show then
        KART.UpdateCtFlyoutAnchor()
        KART.CtFlyout:Show()
    else
        KART.CtFlyout:Hide()
    end
end

local ctFlyTabBar = CreateFrame("Frame", nil, ctFlyout)
ctFlyTabBar:SetPoint("TOPLEFT", ctFlyout, "TOPLEFT", 12, -36)
ctFlyTabBar:SetPoint("TOPRIGHT", ctFlyout, "TOPRIGHT", -12, -36)
ctFlyTabBar:SetHeight(28)
ctFlyTabBar:EnableMouse(true)
ctFlyTabBar:RegisterForDrag("LeftButton")
ctFlyTabBar:SetScript("OnDragStart", function() ctFlyout:StartMoving() end)
ctFlyTabBar:SetScript("OnDragStop", function()
    ctFlyout:StopMovingOrSizing()
    ctFlyout.userPlaced = true
end)

local ctFlyScroll = CreateFrame("ScrollFrame", "KART_CtFlyoutScroll", ctFlyout, "UIPanelScrollFrameTemplate")
ctFlyScroll:SetPoint("TOPLEFT", ctFlyout, "TOPLEFT", 12, -68)
ctFlyScroll:SetPoint("BOTTOMRIGHT", ctFlyout, "BOTTOMRIGHT", -28, 12)
local ctFlyChild = CreateFrame("Frame", nil, ctFlyScroll)
ctFlyScroll:SetScrollChild(ctFlyChild)
local ctFlyThumb = KART.UI:StripScrollbarTextures(ctFlyScroll)
if ctFlyThumb then ctFlyThumb:SetSize(8, 30) end
KART.UI:RegisterAccentTexture(ctFlyThumb, 0.6)
local ctFlyBar = _G["KART_CtFlyoutScrollScrollBar"]
if ctFlyBar then
    ctFlyBar:ClearAllPoints()
    ctFlyBar:SetPoint("TOPLEFT", ctFlyScroll, "TOPRIGHT", 6, -2)
    ctFlyBar:SetPoint("BOTTOMLEFT", ctFlyScroll, "BOTTOMRIGHT", 6, 2)
end
ctFlyScroll.scrollBarHideable = true

local ctFlyLook = CreateFrame("Frame", nil, ctFlyChild)
local ctFlyText = CreateFrame("Frame", nil, ctFlyChild)
local ctFlyAuras = CreateFrame("Frame", nil, ctFlyChild)
ctFlyLook:SetAllPoints()
ctFlyText:SetAllPoints()
ctFlyAuras:SetAllPoints()
ctFlyText:Hide()
ctFlyAuras:Hide()
KART.CtFlyoutPanels = { ctFlyLook, ctFlyText, ctFlyAuras }

local CT_FLYOUT_HEIGHTS = { 810, 490, 920 }
local function UpdateCtFlyoutScrollRange(tabIndex)
    local h = CT_FLYOUT_HEIGHTS[tabIndex] or 750
    ctFlyChild:SetSize(516, math.max(h, ctFlyScroll:GetHeight()))
    local maxScroll = math.max(0, ctFlyChild:GetHeight() - ctFlyScroll:GetHeight())
    if ctFlyScroll:GetVerticalScroll() > maxScroll then
        ctFlyScroll:SetVerticalScroll(maxScroll)
    end
end

function KART.ShowCtFlyoutTab(tabIndex)
    for i, panel in ipairs(KART.CtFlyoutPanels) do
        panel:SetShown(i == tabIndex)
    end
    if KART.CtFlyoutTabButtons then
        for i, btn in ipairs(KART.CtFlyoutTabButtons) do
            local active = i == tabIndex
            btn.text:SetTextColor(active and 1 or 0.75, active and 1 or 0.75, active and 1 or 0.75)
        end
    end
    UpdateCtFlyoutScrollRange(tabIndex)
end

KART.CtFlyoutTabButtons = {}
local function AddCtFlyoutTab(index, label, xOff)
    local btn = KART.UI:CreateModernButton(ctFlyTabBar, label)
    btn:SetSize(160, 24)
    btn:SetPoint("TOPLEFT", ctFlyTabBar, "TOPLEFT", xOff, 0)
    btn:SetScript("OnClick", function() KART.ShowCtFlyoutTab(index) end)
    KART.CtFlyoutTabButtons[index] = btn
    return btn
end
AddCtFlyoutTab(1, L.TAB_CT_LOOK, 0)
AddCtFlyoutTab(2, L.TAB_CT_TEXT, 168)
AddCtFlyoutTab(3, L.TAB_CT_AURAS, 336)
KART.ShowCtFlyoutTab(1)

clickArea:HookScript("OnDragStop", function()
    if KART.UpdateCtFlyoutAnchor then KART.UpdateCtFlyoutAnchor() end
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

local function CtTextureLabel(key)
    key = key or CtStore().healthTexture
    if not key then return L.CT_TEXTURE_SMOOTH end
    if key:find("WHITE8X8", 1, true) then return L.CT_TEXTURE_FLAT end
    if key:find("UI%-StatusBar", 1, true) then return L.CT_TEXTURE_SMOOTH end
    return key:match("[^\\]+$") or key
end

local function RefreshCtTextureBtn()
    if not KART_Settings or not KART.BtnCtHealthTexture then return end
    KART.BtnCtHealthTexture.text:SetText(L.SET_CT_HEALTH_TEXTURE .. ": " .. CtTextureLabel())
end

local ctLookCard = KART.UI:CreateCard(ctFlyLook)
ctLookCard:SetPoint("TOPLEFT", ctFlyLook, "TOPLEFT", 12, -12)
ctLookCard:SetSize(500, 540)

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

KART.BtnCtHealthTexture = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_TEXTURE, L.DESC_CT_HEALTH_TEXTURE)
KART.BtnCtHealthTexture:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -20)
KART.BtnCtHealthTexture:SetSize(220, 22)
KART.BtnCtHealthTexture:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_TEXTURE)
        if LSM then
            local textures = LSM:List("statusbar")
            for _, name in ipairs(textures) do
                rootDescription:CreateButton(name, function()
                    CtStore().healthTexture = name
                    RefreshCtTextureBtn()
                    CtLayoutChanged()
                end)
            end
        else
            rootDescription:CreateButton(L.CT_TEXTURE_SMOOTH, function()
                CtStore().healthTexture = "Interface\\TargetingFrame\\UI-StatusBar"
                RefreshCtTextureBtn()
                CtLayoutChanged()
            end)
            rootDescription:CreateButton(L.CT_TEXTURE_FLAT, function()
                CtStore().healthTexture = "Interface\\Buttons\\WHITE8X8"
                RefreshCtTextureBtn()
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

KART.BtnCtHealthColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_COLOR, L.DESC_CT_HEALTH_COLOR)
KART.BtnCtHealthColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -174)
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

KART.CbCtAbsorb = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtAbsorb", label = L.SET_CT_ABSORB,
    store = CtStore, key = "absorbShow", y = -292,
    onChanged = CtRefresh,
})
KART.CbCtAbsorb.text:SetWidth(430)
KART.CbCtAbsorb.text:SetJustifyH("LEFT")
KART.CbCtHealAbsorb = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtHealAbsorb", label = L.SET_CT_HEAL_ABSORB,
    store = CtStore, key = "healAbsorbShow", y = -318,
    onChanged = CtRefresh,
})
KART.CbCtHealAbsorb.text:SetWidth(430)
KART.CbCtHealAbsorb.text:SetJustifyH("LEFT")

KART.BtnCtAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_ABSORB_COLOR)
KART.BtnCtAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -350)
KART.BtnCtAbsorbColor:SetSize(220, 22)
KART.BtnCtAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().absorbColor, CtLayoutChanged)
end)
KART.SldCtAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtAbsorbAlphaSlider", label = L.SET_CT_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "absorbAlpha", y = -350,
    onChanged = function()
        CtStore().absorbAlpha = KART.SldCtAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtAbsorbAlpha:ClearAllPoints()
KART.SldCtAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -366)

KART.BtnCtHealAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEAL_ABSORB_COLOR)
KART.BtnCtHealAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -408)
KART.BtnCtHealAbsorbColor:SetSize(220, 22)
KART.BtnCtHealAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().healAbsorbColor, CtLayoutChanged)
end)
KART.SldCtHealAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtHealAbsorbAlphaSlider", label = L.SET_CT_HEAL_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "healAbsorbAlpha", y = -408,
    onChanged = function()
        CtStore().healAbsorbAlpha = KART.SldCtHealAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtHealAbsorbAlpha:ClearAllPoints()
KART.SldCtHealAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -424)

KART.CbCtGradient = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtGradient", label = L.SET_CT_GRADIENT, tooltip = L.DESC_CT_GRADIENT,
    store = CtStore, key = "gradient", y = -456,
    onChanged = CtLayoutChanged,
})

KART.BtnCtGradientFrom = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_GRADIENT_FROM)
KART.BtnCtGradientFrom:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -488)
KART.BtnCtGradientFrom:SetSize(220, 22)
KART.UI:AttachColorSwatch(KART.BtnCtGradientFrom)
KART.BtnCtGradientFrom:SetScript("OnClick", function()
    CtPickColor(CtStore().gradientFrom, CtLayoutChanged)
end)
KART.BtnCtGradientTo = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_GRADIENT_TO)
KART.BtnCtGradientTo:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -488)
KART.BtnCtGradientTo:SetSize(220, 22)
KART.UI:AttachColorSwatch(KART.BtnCtGradientTo)
KART.BtnCtGradientTo:SetScript("OnClick", function()
    CtPickColor(CtStore().gradientTo, CtLayoutChanged)
end)

function KART.RefreshCtGradientSwatches()
    if not KART_Settings or not KART.UI.PaintColorSwatch then return end
    local ct = CtStore()
    KART.UI:PaintColorSwatch(KART.BtnCtGradientFrom, ct.gradientFrom)
    KART.UI:PaintColorSwatch(KART.BtnCtGradientTo, ct.gradientTo)
end

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

local ctFadeCard = KART.UI:CreateCard(ctFlyLook)
ctFadeCard:SetPoint("TOPLEFT", ctLookCard, "BOTTOMLEFT", 0, -20)
ctFadeCard:SetSize(500, 250)

local ctTextCard = KART.UI:CreateCard(ctFlyText)
ctTextCard:SetPoint("TOPLEFT", ctFlyText, "TOPLEFT", 12, -12)
ctTextCard:SetSize(500, 490)

KART.BtnCtHealthText = KART.UI:CreateModernButton(ctTextCard, L.SET_CT_HEALTH_TEXT, L.DESC_CT_HEALTH_TEXT)
KART.BtnCtHealthText:SetPoint("TOPLEFT", ctTextCard, "TOPLEFT", 20, -20)
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

KART.SldCtNameMax = KART.UI:CreateSettingsSlider(ctTextCard, {
    name = "KART_CtNameMaxSlider", label = L.SET_CT_NAME_MAX,
    min = 4, max = 24, store = CtStore, key = "nameMaxLength", y = -20,
    onChanged = CtRefresh,
})
KART.SldCtNameMax:ClearAllPoints()
KART.SldCtNameMax:SetPoint("TOPLEFT", ctTextCard, "TOPLEFT", 260, -36)

KART.CtNameTextWidgets = CtBuildTextBlock(ctTextCard, -70, L.LABEL_CT_NAME_TEXT, CtNameStyle, "Name")
KART.CtHealthTextWidgets = CtBuildTextBlock(ctTextCard, -276, L.LABEL_CT_HEALTH_TEXT, CtHealthStyle, "Hp")

KART.CbCtRangeFadeOn = KART.UI:CreateSettingsCheckbox(ctFadeCard, {
    name = "KART_CtRangeFadeOn", label = L.SET_CT_RANGE_FADE_ON,
    store = CtStore, key = "rangeFade", y = -20,
    onChanged = CtRefresh,
})
KART.SldCtRangeFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtRangeFadeSlider", label = L.SET_CT_RANGE_FADE,
    min = 10, max = 100, store = CtStore, key = "rangeAlpha", y = -20,
    onChanged = function()
        CtStore().rangeAlpha = KART.SldCtRangeFade:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtRangeFade:ClearAllPoints()
KART.SldCtRangeFade:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -36)
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

local ctAuraCard = KART.UI:CreateCard(ctFlyAuras)
ctAuraCard:SetPoint("TOPLEFT", ctFlyAuras, "TOPLEFT", 12, -12)
ctAuraCard:SetSize(500, 900)

local ctDebuffTitle = ctAuraCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctDebuffTitle:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -16)
ctDebuffTitle:SetText(L.LABEL_CT_DEBUFFS)
KART.UI:RegisterHeading(ctDebuffTitle)

KART.CbCtDebuffShow = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtDebuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtDebuffs, key = "show", y = -48,
    onChanged = CtRefresh,
})
KART.SldCtDebuffMax = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtDebuffs, key = "max", y = -48,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffMax:ClearAllPoints()
KART.SldCtDebuffMax:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -64)

KART.SldCtDebuffSize = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 100, store = CtDebuffs, key = "size", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtDebuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtDebuffs, key = "spacing", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing:ClearAllPoints()
KART.SldCtDebuffSpacing:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -104)

KART.BtnCtDebuffAnchor = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtDebuffAnchor:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -128)
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
KART.BtnCtDebuffGrowth:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -128)
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

KART.CbCtHideLongDuration = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtHideLongDuration", label = L.SET_CT_HIDE_LONG_DURATION,
    tooltip = L.DESC_CT_HIDE_LONG_DURATION,
    store = CtDebuffs, key = "hideLongDuration", y = -360,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideLongDuration.text:SetWidth(430)
KART.CbCtHideLongDuration.text:SetJustifyH("LEFT")
KART.CbCtHideFatigue = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtHideFatigue", label = L.SET_CT_HIDE_FATIGUE,
    tooltip = L.DESC_CT_HIDE_FATIGUE,
    store = CtDebuffs, key = "hideFatigue", y = -388,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideFatigue.text:SetWidth(430)
KART.CbCtHideFatigue.text:SetJustifyH("LEFT")

local ctBuffTitle = ctAuraCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctBuffTitle:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -434)
ctBuffTitle:SetText(L.LABEL_CT_BUFFS)
KART.UI:RegisterHeading(ctBuffTitle)

KART.CbCtBuffShow = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtBuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtBuffs, key = "show", y = -464,
    onChanged = CtRefresh,
})
KART.SldCtBuffMax = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtBuffs, key = "max", y = -464,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffMax:ClearAllPoints()
KART.SldCtBuffMax:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -480)

KART.SldCtBuffSize = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 40, store = CtBuffs, key = "size", y = -504,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing = KART.UI:CreateSettingsSlider(ctAuraCard, {
    name = "KART_CtBuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtBuffs, key = "spacing", y = -504,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing:ClearAllPoints()
KART.SldCtBuffSpacing:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -520)

KART.BtnCtBuffAnchor = KART.UI:CreateModernButton(ctAuraCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtBuffAnchor:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 20, -544)
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
KART.BtnCtBuffGrowth:SetPoint("TOPLEFT", ctAuraCard, "TOPLEFT", 260, -544)
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

KART.CtDebuffExtra = CtAddStripExtras(ctAuraCard, CtDebuffs, "DebuffEx", -158)
KART.CtBuffExtra = CtAddStripExtras(ctAuraCard, CtBuffs, "BuffEx", -574)

KART.CbCtHideLongBuffs = KART.UI:CreateSettingsCheckbox(ctAuraCard, {
    name = "KART_CtHideLongBuffs", label = L.SET_CT_HIDE_LONG_DURATION,
    tooltip = L.DESC_CT_HIDE_LONG_BUFFS,
    store = CtBuffs, key = "hideLongDuration", y = -784,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideLongBuffs.text:SetWidth(430)
KART.CbCtHideLongBuffs.text:SetJustifyH("LEFT")

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
ctTauntCard:SetPoint("TOPLEFT", ctRowCard, "BOTTOMLEFT", 0, -20)
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

-- In-game changelog panel: short summary from KART.InGameChangelog (Utils.lua). Full history is CHANGELOG.md.
local function FormatChangelogLine(line)
    line = tostring(line or ""):gsub("%*%*(.-)%*%*", "|cffffffff%1|r")
    return "•  " .. line
end

function KART.ShowChangelogPopup()
    if not KART.changelogPopup then
        local f = CreateFrame("Frame", "KART_ChangelogPopup", UIParent, "BackdropTemplate")
        f:SetSize(460, 400)
        f:SetPoint("CENTER")
        KART.UI:RegisterStrataFrame(f, true)
        KART.UI:ApplyPopupArtwork(f)
        KART.UI:ApplyPopupChrome(f, { title = L.LABEL_CHANGELOG })
        KART.UI:AddShowFade(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetClampedToScreen(true)
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        KART.RegisterEscapeFrame(f)

        local scrollFrame = CreateFrame("ScrollFrame", "KART_ChangelogPopupScroll", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -48)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 20)
        local clThumb = KART.UI:StripScrollbarTextures(scrollFrame)
        if clThumb then clThumb:SetSize(8, 30) end
        KART.UI:RegisterAccentTexture(clThumb, 0.6)
        local clBar = _G["KART_ChangelogPopupScrollScrollBar"]
        if clBar then
            clBar:ClearAllPoints()
            clBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -2)
            clBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 2)
        end
        scrollFrame.scrollBarHideable = true

        f.scrollChild = CreateFrame("Frame", nil, scrollFrame)
        f.scrollChild:SetWidth(392)
        scrollFrame:SetScrollChild(f.scrollChild)
        f.scrollFrame = scrollFrame
        KART.changelogPopup = f
    end

    local f = KART.changelogPopup
    f.title:SetText(L.LABEL_CHANGELOG)

    if f.scrollChild then
        f.scrollChild:Hide()
        f.scrollChild:SetParent(nil)
    end
    local child = CreateFrame("Frame", nil, f.scrollFrame)
    child:SetWidth(392)
    f.scrollFrame:SetScrollChild(child)
    f.scrollChild = child

    local ar, ag, ab = KART.UI:AccentColor()
    local y = -4
    for _, block in ipairs(KART.InGameChangelog or {}) do
        local header = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        header:SetWidth(392)
        header:SetJustifyH("LEFT")
        header:SetText(block.version)
        header:SetTextColor(ar, ag, ab)
        KART.UI:RegisterLabel(header)
        header:SetTextColor(ar, ag, ab)
        y = y - header:GetStringHeight() - 10
        for _, line in ipairs(block.entries or {}) do
            local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            body:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y)
            body:SetWidth(384)
            body:SetJustifyH("LEFT")
            body:SetWordWrap(true)
            body:SetText(FormatChangelogLine(line))
            body:SetTextColor(0.82, 0.82, 0.82)
            KART.UI:RegisterLabel(body)
            body:SetTextColor(0.82, 0.82, 0.82)
            y = y - body:GetStringHeight() - 8
        end
        y = y - 12
    end
    child:SetHeight(math.abs(y) + 8)
    f.scrollFrame:SetVerticalScroll(0)
    f:Show()
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
    if KART.SidebarSystemHeader then KART.SidebarSystemHeader:SetText(L.LABEL_SYSTEM) end
    if KART.BtnChangelog then
        KART.BtnChangelog.text:SetText(L.BTN_CHANGELOG)
        KART.BtnChangelog.tooltipText = L.DESC_CHANGELOG
    end
    if KART.BtnEditMode then KART.RefreshEditModeToggle() end
    if KART.EditModeBanner and KART.EditModeBanner.title then
        KART.EditModeBanner.title:SetText(L.EDIT_MODE_BANNER)
    end
    if KART.BtnEditModeDone and KART.BtnEditModeDone.text then
        KART.BtnEditModeDone.text:SetText(L.BTN_EDIT_MODE_DONE)
    end
    if KART.FooterLinks then
        local keys = { "LINK_CURSEFORGE", "LINK_WAGO", "LINK_GITHUB" }
        for i, btn in ipairs(KART.FooterLinks) do
            if keys[i] then btn.text:SetText(L[keys[i]]) end
        end
    end
    KART.RefreshModuleChips()
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.LABEL_RAIDLEAD_TOOLS)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    if KART.TabTitles[6] then KART.TabTitles[6]:SetText(L.LABEL_COTANK_SETTINGS) end
    if KART.CtFlyoutTabButtons then
        KART.CtFlyoutTabButtons[1].text:SetText(L.TAB_CT_LOOK)
        KART.CtFlyoutTabButtons[2].text:SetText(L.TAB_CT_TEXT)
        KART.CtFlyoutTabButtons[3].text:SetText(L.TAB_CT_AURAS)
    end
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
    if KART.SldRlBarScale then
        KART.SldRlBarScale.title:SetText(L.SET_RL_SCALE)
        KART.SldRlBarScale.tooltipText = L.DESC_RL_SCALE
    end
    if KART.SldRlBarButtonSize then
        KART.SldRlBarButtonSize.title:SetText(L.SET_RL_BUTTON_SIZE)
        KART.SldRlBarButtonSize.tooltipText = L.DESC_RL_BUTTON_SIZE
    end
    if KART.SldRlBarAlpha then
        KART.SldRlBarAlpha.title:SetText(L.SET_RL_ALPHA)
        KART.SldRlBarAlpha.tooltipText = L.DESC_RL_ALPHA
    end
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
    if KART.CbCtHealAbsorb.text.SetWidth then KART.CbCtHealAbsorb.text:SetWidth(430) end
    KART.BtnCtHealthColor.tooltipText = L.DESC_CT_HEALTH_COLOR
    KART.BtnCtHealthText.tooltipText = L.DESC_CT_HEALTH_TEXT
    RefreshCtHealthColorBtn()
    RefreshCtHealthTextBtn()
    if RefreshCtFillBtn then RefreshCtFillBtn() end
    if RefreshCtTextureBtn then RefreshCtTextureBtn() end
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
    if KART.BtnCtHealthTexture then
        KART.BtnCtHealthTexture.tooltipText = L.DESC_CT_HEALTH_TEXTURE
        RefreshCtTextureBtn()
    end
    if KART.CbCtGradient then
        KART.CbCtGradient.text:SetText(L.SET_CT_GRADIENT)
        KART.CbCtGradient.tooltipText = L.DESC_CT_GRADIENT
    end
    if KART.BtnCtGradientFrom then
        KART.BtnCtGradientFrom.text:SetText(L.SET_CT_GRADIENT_FROM)
        if KART.UI.FitButtonToLabel then KART.UI:FitButtonToLabel(KART.BtnCtGradientFrom) end
    end
    if KART.BtnCtGradientTo then
        KART.BtnCtGradientTo.text:SetText(L.SET_CT_GRADIENT_TO)
        if KART.UI.FitButtonToLabel then KART.UI:FitButtonToLabel(KART.BtnCtGradientTo) end
    end
    if KART.RefreshCtGradientSwatches then KART.RefreshCtGradientSwatches() end
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
    if KART.CbCtHideLongDuration then
        KART.CbCtHideLongDuration.text:SetText(L.SET_CT_HIDE_LONG_DURATION)
        KART.CbCtHideLongDuration.tooltipText = L.DESC_CT_HIDE_LONG_DURATION
    end
    if KART.CbCtHideFatigue then
        KART.CbCtHideFatigue.text:SetText(L.SET_CT_HIDE_FATIGUE)
        KART.CbCtHideFatigue.tooltipText = L.DESC_CT_HIDE_FATIGUE
    end
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
    if KART.CT and KART.CT.RefreshAskButton then KART.CT.RefreshAskButton() end

    -- Automation tab
    KART.CbAutoModule.text:SetText(L.SET_AUTO_MODULE_ENABLED)
    KART.CbAutoModule.tooltipText = L.DESC_AUTO_MODULE_ENABLED
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
    KART.BtnProfileSaveNew.text:SetText(L.BTN_PROFILE_SAVE_NEW)   KART.BtnProfileSaveNew.tooltipText = L.DESC_PROFILE_SAVE_NEW
    KART.BtnProfileSave.text:SetText(L.BTN_PROFILE_SAVE)          KART.BtnProfileSave.tooltipText = L.DESC_PROFILE_SAVE
    KART.BtnProfileDelete.text:SetText(L.BTN_PROFILE_DELETE)      KART.BtnProfileDelete.tooltipText = L.DESC_PROFILE_DELETE

    -- Header search
    searchBtn.text:SetText(L.BTN_SEARCH)
    searchBtn.tooltipText = L.DESC_SEARCH
end)
