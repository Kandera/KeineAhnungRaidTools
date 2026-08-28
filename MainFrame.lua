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

-- White-on-transparent PNGs under Media/; tab glyphs tint with the label, brand marks do not.
local function Media(file)
    return "Interface\\AddOns\\" .. addonName .. "\\media\\" .. file
end

local function AttachButtonGlyph(btn, file)
    if not btn then return end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetTexture(Media(file))
    icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.glyph = icon
    if btn.text then
        btn.text:ClearAllPoints()
        btn.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        btn.text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        if btn.text.SetJustifyH then btn.text:SetJustifyH("LEFT") end
    end
end

-- 1. Tab-Wechsel Logik (wird in KART Tabelle gespeichert)
function KART.ShowTab(tabIndex)
    local panels = {
        KART.PromotePanel,
        KART.RaidleadPanel,
        KART.BuffCheckPanel,
        KART.SettingsPanel,
        KART.WoWUtilsPanel,
        KART.CoTankPanel,
        KART.NotesPanel,
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
        KART.BtnNotes,
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
    if tabIndex == 7 and KART.NT then
        if KART.NT.RefreshBossList then KART.NT.RefreshBossList() end
        if KART.NT.RefreshStatus then KART.NT.RefreshStatus() end
    end
    if KART.CT and KART.CT.OnSettingsTab then
        local open = tabIndex == 6 and KART.MainFrame and KART.MainFrame:IsShown()
        KART.CT.OnSettingsTab(open and true or false)
    end
end

-- 2. Main window (PNG artwork, EllesmereUI-style)
-- All geometry derives from the measured layout of kart-bg-dark.png:
-- image 1500x1154, opaque art box x 105-1396 / y 104-1050 (1292x947),
-- sidebar divider at art x 323, close-X center at art (1248, 39) -- live glyph,
-- the baked artwork X was painted out of kart-bg-dark.png.
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
mainFrame:HookScript("OnShow", function()
    if KART.CT and KART.CT.OnSettingsTab then
        KART.CT.OnSettingsTab(KART.CurrentTab == 6)
    end
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
-- the text once KART.Version is known (ADDON_LOADED). Kept off the label
-- registry so content font size cannot blow it up next to the store links.
mainFrame.versionText = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainFrame.versionText:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 18, 12)
mainFrame.versionText:SetTextColor(0.45, 0.45, 0.45)
function KART.RefreshVersionText()
    local v = KART.Version or ""
    local by = (KART.L and KART.L.FOOTER_BY) or "by Kandera"
    mainFrame.versionText:SetText("v" .. v .. "  ·  " .. by)
    local font = KART.UI.lastFont or "Fonts\\FRIZQT__.TTF"
    mainFrame.versionText:SetFont(font, 10, "")
    if KART.PaintCloseButton then KART.PaintCloseButton() end
end
KART.RefreshVersionText()

-- Footer links sit above the version string; WoW cannot open a browser, so click
-- shows the URL in a box the player can copy with Ctrl+C. Kept off the label
-- registry so they follow the version line (10px), not the content-font slider.
KART.FooterLinks = {}
local FOOTER_LINK_FONT = 10
function KART.RefreshFooterLinks()
    local font = KART.UI.lastFont or "Fonts\\FRIZQT__.TTF"
    for _, btn in ipairs(KART.FooterLinks) do
        btn.text:SetFont(font, FOOTER_LINK_FONT, "")
        btn:SetWidth((btn.text:GetStringWidth() or 36) + 10)
    end
end
do
    local linkDefs = {
        { localeKey = "LINK_CURSEFORGE", url = "https://www.curseforge.com/wow/addons/keine-ahnung-raid-tools", color = { 0.95, 0.45, 0.22 }, icon = Media("logo-curseforge.png") },
        { localeKey = "LINK_WAGO", url = "https://addons.wago.io/addons/qn53zokb", color = { 0.85, 0.70, 0.25 }, icon = Media("logo-wago.png") },
        { localeKey = "LINK_GITHUB", url = "https://github.com/Kandera/KeineAhnungRaidTools", color = { 0.72, 0.78, 0.86 }, icon = Media("logo-github.png") },
    }
    local prev
    for i, def in ipairs(linkDefs) do
        local btn = CreateFrame("Button", nil, clickArea)
        btn:SetHeight(14)
        btn.url = def.url
        btn.brand = def.color
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(8, 8)
        btn.icon:SetTexture(def.icon)
        -- Icon and text both anchor to the button, not each other's string height,
        -- so GitHub (no descenders) does not sit above CurseForge/Wago.
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.text = btn:CreateFontString(nil, "OVERLAY")
        -- SetFont before SetText: a FontString with no inherit object raises
        -- "Font not set" and aborts the rest of this file (blank main window).
        btn.text:SetFont(KART.UI.lastFont or "Fonts\\FRIZQT__.TTF", FOOTER_LINK_FONT, "")
        btn.text:SetPoint("LEFT", btn, "LEFT", 10, 0)
        btn.text:SetText(L[def.localeKey])
        btn.text:SetTextColor(def.color[1], def.color[2], def.color[3])
        btn:SetScript("OnClick", function(self) KART.CopyLink(self.url) end)
        btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(self.brand[1], self.brand[2], self.brand[3])
        end)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            btn:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 12, 28)
        end
        prev = btn
        KART.FooterLinks[i] = btn
    end
    KART.RefreshFooterLinks()
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
KART.SidebarModulesHeader = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.SidebarModulesHeader:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 14, -76)
KART.SidebarModulesHeader:SetText(L.LABEL_MODULES)
KART.UI:RegisterLabel(KART.SidebarModulesHeader)

KART.BtnPromote = KART.UI:CreateTabButton(clickArea, L.TAB_PROMOTE, { moduleChip = true, icon = Media("tab-automation.png") })
KART.BtnPromote:SetPoint("TOPLEFT", KART.SidebarModulesHeader, "BOTTOMLEFT", -2, -4)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.UI:CreateTabButton(clickArea, L.TAB_RAIDLEAD, { moduleChip = true, icon = Media("tab-raidlead.png") })
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.UI:CreateTabButton(clickArea, L.TAB_BUFFCHECK, { moduleChip = true, icon = Media("tab-buffcheck.png") })
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnWoWUtils = KART.UI:CreateTabButton(clickArea, L.TAB_WOWUTILS, { moduleChip = true, icon = Media("tab-wowutils.png") })
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(5) end)

-- The Settings tab must always be the last entry in the sidebar. When adding a new tab
-- button, anchor it above this one (i.e. insert it between the previous last tab and
-- Settings, and re-anchor Settings to the new button).
KART.BtnCoTank = KART.UI:CreateTabButton(clickArea, L.TAB_COTANK, { moduleChip = true, icon = Media("tab-cotank.png") })
KART.BtnCoTank:SetPoint("TOPLEFT", KART.BtnWoWUtils, "BOTTOMLEFT", 0, -5)
KART.BtnCoTank:SetScript("OnClick", function() KART.ShowTab(6) end)

KART.BtnNotes = KART.UI:CreateTabButton(clickArea, L.TAB_NOTES, { moduleChip = true, icon = Media("tab-wowutils.png") })
KART.BtnNotes:SetPoint("TOPLEFT", KART.BtnCoTank, "BOTTOMLEFT", 0, -5)
KART.BtnNotes:SetScript("OnClick", function() KART.ShowTab(7) end)

KART.SidebarSystemHeader = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.SidebarSystemHeader:SetPoint("TOPLEFT", KART.BtnNotes, "BOTTOMLEFT", 2, -10)
KART.SidebarSystemHeader:SetText(L.LABEL_SYSTEM)
KART.UI:RegisterLabel(KART.SidebarSystemHeader)

KART.BtnSettings = KART.UI:CreateTabButton(clickArea, L.TAB_SETTINGS, { icon = Media("tab-settings.png") })
KART.BtnSettings:SetPoint("TOPLEFT", KART.SidebarSystemHeader, "BOTTOMLEFT", -2, -4)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

-- Edit Mode and Changelog sit above the footer links, not in the tab list.
KART.BtnChangelog = KART.UI:CreateModernButton(clickArea, L.BTN_CHANGELOG, L.DESC_CHANGELOG)
KART.BtnChangelog:SetSize(176, 22)
KART.BtnChangelog:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 12, 46)
AttachButtonGlyph(KART.BtnChangelog, "tab-changelog.png")
KART.BtnChangelog:SetScript("OnClick", function() KART.ShowChangelogPopup() end)

KART.BtnEditMode = KART.UI:CreateModernButton(clickArea, L.BTN_EDIT_MODE_OFF, L.DESC_EDIT_MODE)
KART.BtnEditMode:SetSize(176, 22)
KART.BtnEditMode:SetPoint("BOTTOMLEFT", KART.BtnChangelog, "TOPLEFT", 0, 5)
AttachButtonGlyph(KART.BtnEditMode, "tab-editmode.png")
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
    [KART.BtnNotes] = "ntModuleEnabled",
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
statusStrip:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 228, -52)
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
        strip.rcValue:SetText(rcOn and (L.STATUS_RC_ON or "ON") or (L.STATUS_RC_OFF or "OFF"))
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
KART.CreateTabTitle(6, KART.L.LABEL_COTANK_SETTINGS)

KART.NotesPanel = CreateFrame("Frame", nil, scrollChild)
KART.NotesPanel:SetAllPoints()
KART.NotesPanel:Hide()
KART.CreateTabTitle(7, L.TAB_NOTES)

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
    [1] = 535, -- Automation: enable card + promote/invite card + AutoLog
    [2] = 520, -- Raidlead: bar card + Keybinds heading + bind card
    [3] = 190, -- BuffCheck: one 160 card
    [4] = 670, -- Settings: two half cards + accent/profiles + addon versions + RC companion
    [6] = 1484, -- Co-Tank: preview + module + size + taunt/swap + swap-line settings
    [7] = 520, -- Notes: enable + operator + import + boss list + share; live-measured below
}
function KART.UpdateScrollRange()
    local tab = KART.CurrentTab
    if not tab then return end
    local h = PANEL_CONTENT_HEIGHTS[tab]
    if tab == 5 then
        -- Enable + import cards, Bosses heading, and the boss card (grows with the list).
        local card = KART.WU and KART.WU.bossListCard
        h = 280 + ((card and card:GetHeight()) or 48)
    elseif tab == 7 then
        -- Enable + operator + import + share cards, and the boss card (grows with the list).
        local card = KART.NT and KART.NT.bossListCard
        h = 472 + ((card and card:GetHeight()) or 80)
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
KART.CreateTabTitle(2, L.TAB_RAIDLEAD)

-- Card groups all Raidlead Bar settings into one visually distinct panel instead of leaving
-- checkboxes/slider floating directly on the tab background.
local rlCard = KART.UI:CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -12)
-- Toggles left, look sliders right: the old stacked cards left the right half of a 500-wide
-- card empty. Same two-column packing as the Buff-Checker card.
rlCard:SetSize(500, 280)

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

KART.CbHideBlizzardRaidManager = KART.UI:CreateSettingsCheckbox(rlCard, {
    name = "KART_HideBlizzardRaidManagerCheck", label = L.SET_RL_HIDE_BLIZZARD,
    store = SettingsStore, key = "hideBlizzardRaidManager", y = -210,
    onChanged = function()
        if KART.ApplyBlizzardRaidManagerVisibility then
            KART.ApplyBlizzardRaidManagerVisibility(not (KART.ShouldHideBlizzardRaidManager
                and KART.ShouldHideBlizzardRaidManager()))
        end
    end,
    tooltip = L.DESC_RL_HIDE_BLIZZARD,
})
PinRlToggle(KART.CbHideBlizzardRaidManager, -210)

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
    self.valueText:SetText(KART.StrataSliderLabel(self:GetValue()))
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

-- Keybind card: heading sits above the card, same pattern as Auto Combat Log.
local kbTitle = KART.RaidleadPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
kbTitle:SetPoint("TOPLEFT", rlCard, "BOTTOMLEFT", 0, -18)
kbTitle:SetText(L.LABEL_RL_KEYBINDS)
KART.UI:RegisterLabel(kbTitle)

local kbCard = KART.UI:CreateCard(KART.RaidleadPanel)
kbCard:SetPoint("TOPLEFT", kbTitle, "BOTTOMLEFT", 0, -10)
kbCard:SetSize(500, 148)

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
    local yOff = -20 - (i - 1) * 30

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
alCard:SetSize(500, 170)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlEnabled", label = L.SET_AL_ENABLED,
    store = SettingsStore, key = "autoLogEnabled", y = -20,
    onChanged = AutoLogChanged, tooltip = L.DESC_AL_ENABLED,
})
KART.CbAlEnabled.text:SetWidth(430)
KART.CbAlEnabled.text:SetJustifyH("LEFT")
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
    store = SettingsStore, key = "autoLogDungeons", y = -110,
    onChanged = AutoLogChanged,
})
KART.CbAlDungeons:ClearAllPoints()
KART.CbAlDungeons:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -110)
KART.CbAlDungeons.text:SetWidth(192)
KART.CbAlDungeons.text:SetJustifyH("LEFT")
KART.CbAlDelves = KART.UI:CreateSettingsCheckbox(alCard, {
    name = "KART_AlDelves", label = L.SET_AL_DELVES,
    store = SettingsStore, key = "autoLogDelves", y = -140,
    onChanged = AutoLogChanged,
})
KART.CbAlDelves:ClearAllPoints()
KART.CbAlDelves:SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -140)
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
    self.valueText:SetText(KART.StrataSliderLabel(self:GetValue()))
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

-- Raid-lead version check: a window for raiders whose RC / NSRT / WowUtils is behind yours.
-- Lives on Settings, not Buff Check — it is not a buff-checker control.
local addonVerCard = KART.UI:CreateCard(KART.SettingsPanel)
addonVerCard:SetPoint("TOPLEFT", colCard, "BOTTOMLEFT", 0, -20)
addonVerCard:SetSize(500, 72)
KART.AddonVersionCard = addonVerCard

KART.BtnAddonNag = KART.UI:CreateModernButton(addonVerCard, L.BTN_ADDON_NAG, L.DESC_ADDON_NAG)
KART.BtnAddonNag:SetPoint("TOPLEFT", addonVerCard, "TOPLEFT", 20, -14)
KART.BtnAddonNag:SetSize(240, 25)
KART.BtnAddonNag:SetScript("OnClick", function()
    if KART.BroadcastAddonNag then KART.BroadcastAddonNag() end
end)

KART.AddonVersionNote = addonVerCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.AddonVersionNote:SetPoint("TOPLEFT", KART.BtnAddonNag, "BOTTOMLEFT", 0, -8)
KART.AddonVersionNote:SetWidth(460)
KART.AddonVersionNote:SetJustifyH("LEFT")
KART.AddonVersionNote:SetWordWrap(true)
KART.AddonVersionNote:SetText(L.NOTE_ADDON_VERSIONS)
KART.UI:RegisterLabel(KART.AddonVersionNote)

-- 9. Close button. The artwork no longer has a baked X; this glyph is the only one.
-- Not RegisterCloseButtonText: that restyle path forces 18px OUTLINE. Size stays
-- fixed; color follows the accent picker. Vertically centered with Search.
local CLOSE_GLYPH_SIZE = 32
local closeBtn = CreateFrame("Button", nil, clickArea)
closeBtn:SetSize(40, 40)
closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -22, -31)
closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
closeBtn.text:SetFont(KART.UI.lastFont or "Fonts\\FRIZQT__.TTF", CLOSE_GLYPH_SIZE, "")
closeBtn.text:SetPoint("CENTER", 0, 1)
closeBtn.text:SetText("×")
function KART.PaintCloseButton()
    closeBtn.text:SetFont(KART.UI.lastFont or "Fonts\\FRIZQT__.TTF", CLOSE_GLYPH_SIZE, "")
    if not closeBtn.isHovered then
        closeBtn.text:SetTextColor(KART.UI:AccentColor())
    end
end
KART.PaintCloseButton()
closeBtn:SetScript("OnEnter", function(self)
    self.isHovered = true
    self.text:SetTextColor(1, 1, 1)
end)
closeBtn:SetScript("OnLeave", function(self)
    self.isHovered = false
    self.text:SetTextColor(KART.UI:AccentColor())
end)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn

-- 10. Settings search: small always-visible button + popout (edit box + up to 8 result rows).
-- Positioned left of the close button, in the same header row as the active tab's title, well
-- clear of the close button's hit area (closeBtn is 40×40, centered at -22,-31 from
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
function KART.ShowChangelogPopup()
    local bodyW = 528
    if not KART.changelogPopup then
        local f = CreateFrame("Frame", "KART_ChangelogPopup", UIParent, "BackdropTemplate")
        f:SetSize(580, 540)
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
        f.scrollChild:SetWidth(bodyW)
        scrollFrame:SetScrollChild(f.scrollChild)
        f.scrollFrame = scrollFrame
        KART.changelogPopup = f
    end

    local f = KART.changelogPopup
    f.title:SetText(L.LABEL_CHANGELOG)

    -- Reuse the scroll child and its regions. WoW cannot destroy frames; a new child (and a
    -- FontString/Texture per line) on every open leaked for the rest of the session.
    local child = f.scrollChild
    child:SetWidth(bodyW)
    child:Show()
    child.kartFS = child.kartFS or {}
    child.kartTex = child.kartTex or {}
    local fsUsed, texUsed = 0, 0
    local function NextFS()
        fsUsed = fsUsed + 1
        local fs = child.kartFS[fsUsed]
        if not fs then
            fs = child:CreateFontString(nil, "OVERLAY")
            child.kartFS[fsUsed] = fs
        end
        fs:Show()
        return fs
    end
    local function NextTex()
        texUsed = texUsed + 1
        local tex = child.kartTex[texUsed]
        if not tex then
            tex = child:CreateTexture(nil, "ARTWORK")
            child.kartTex[texUsed] = tex
        end
        tex:Show()
        return tex
    end

    local ar, ag, ab = KART.UI:AccentColor()
    local font = KART.UI.lastFont or "Fonts\\FRIZQT__.TTF"
    local headerSize = (KART.UI.lastMenuSize or 11) + 6
    local contentSize = KART.UI.lastContentSize or 12
    local leadSize = contentSize + 1
    local restSize = math.max(9, contentSize - 2)
    local innerW = bodyW - 8
    local y = -4
    for _, block in ipairs(KART.InGameChangelog or {}) do
        local header = NextFS()
        header:SetFont(font, headerSize, "")
        header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        header:SetWidth(bodyW)
        header:SetJustifyH("LEFT")
        header:SetText(block.version)
        header:SetTextColor(ar, ag, ab)
        y = y - (header:GetStringHeight() or headerSize) - 6
        local rule = NextTex()
        rule:SetColorTexture(ar, ag, ab, 0.45)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        rule:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)
        y = y - 10
        for _, line in ipairs(block.entries or {}) do
            local lead, rest = KART.ParseChangelogLine(line)
            -- One FontString cannot mix sizes. Lead is the short name (white, slightly
            -- larger, outline for weight); the note is smaller and dimmer beside it.
            local leadFS = NextFS()
            leadFS:SetFont(font, leadSize, "OUTLINE")
            leadFS:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            leadFS:SetJustifyH("LEFT")
            leadFS:SetTextColor(1, 1, 1)
            leadFS:SetText("•  " .. lead)
            local usedH = leadFS:GetStringHeight() or leadSize
            if rest == "" then
                leadFS:SetWidth(innerW)
                leadFS:SetWordWrap(true)
                usedH = leadFS:GetStringHeight() or leadSize
            else
                leadFS:SetWordWrap(false)
                local leadW = leadFS:GetStringWidth() or 0
                local note = NextFS()
                note:SetFont(font, restSize, "")
                note:SetJustifyH("LEFT")
                note:SetWordWrap(true)
                note:SetTextColor(0.70, 0.70, 0.70)
                note:SetText(rest)
                local stacked = leadW > innerW * 0.55
                local tight = rest:find("^[,.;:]")
                if stacked then
                    note:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y - usedH - 2)
                    note:SetWidth(innerW - 14)
                else
                    local gap = tight and 1 or 6
                    local baseline = math.floor((leadSize - restSize) / 2)
                    note:SetPoint("TOPLEFT", leadFS, "TOPRIGHT", gap, -baseline)
                    note:SetWidth(math.max(40, innerW - leadW - gap))
                end
                local noteH = note:GetStringHeight() or restSize
                if stacked then
                    usedH = usedH + 2 + noteH
                else
                    usedH = math.max(usedH, noteH + (math.floor((leadSize - restSize) / 2)))
                end
            end
            y = y - usedH - 8
        end
        y = y - 14
    end
    child:SetHeight(math.abs(y) + 8)
    f.scrollFrame:SetVerticalScroll(0)
    f:Show()
end

-- Re-applies widgets in this file from KART_Settings after load and profile switch.
-- Core.lua fans out here; a missing settingsMap line leaves the checkbox showing off.
function KART.SyncMainFrameWidgets()
    local settingsMap = {}
    if KART.InviteEditBox then settingsMap[KART.InviteEditBox] = "inviteKeywords" end
    if KART.PromoteEditBox then settingsMap[KART.PromoteEditBox] = "promoteNames" end
    if KART.CbActivate then settingsMap[KART.CbActivate] = "showRaidleadBar" end
    if KART.CbLock then settingsMap[KART.CbLock] = "lockRaidleadBar" end
    if KART.CbAutoHide then settingsMap[KART.CbAutoHide] = "autoHideRaidleadBar" end
    if KART.CbAutoHideCombat then settingsMap[KART.CbAutoHideCombat] = "autoHideRaidleadBarCombat" end
    if KART.CbRcReasonDialog then settingsMap[KART.CbRcReasonDialog] = "rcReasonDialog" end
    if KART.PullSlider then settingsMap[KART.PullSlider] = "pullTimerDuration" end
    if KART.CbBcModuleEnabled then settingsMap[KART.CbBcModuleEnabled] = "bcModuleEnabled" end
    if KART.CbAutoModule then settingsMap[KART.CbAutoModule] = "autoModuleEnabled" end
    if KART.CbShowBuffCheck then settingsMap[KART.CbShowBuffCheck] = "showBuffCheck" end
    if KART.SldBuffCheckAlpha then settingsMap[KART.SldBuffCheckAlpha] = "buffCheckAlpha" end
    if KART.SldCombatDelay then settingsMap[KART.SldCombatDelay] = "bcCombatDelay" end
    if KART.CbGrayOffline then settingsMap[KART.CbGrayOffline] = "grayOffline" end
    if KART.CbMinimap then settingsMap[KART.CbMinimap] = "showMinimapIcon" end
    if KART.CbAutoRaid then settingsMap[KART.CbAutoRaid] = "autoConvertToRaid" end
    if KART.CbAlEnabled then settingsMap[KART.CbAlEnabled] = "autoLogEnabled" end
    if KART.CbAlRaidLFR then settingsMap[KART.CbAlRaidLFR] = "autoLogRaidLFR" end
    if KART.CbAlRaidNormal then settingsMap[KART.CbAlRaidNormal] = "autoLogRaidNormal" end
    if KART.CbAlRaidHeroic then settingsMap[KART.CbAlRaidHeroic] = "autoLogRaidHeroic" end
    if KART.CbAlRaidMythic then settingsMap[KART.CbAlRaidMythic] = "autoLogRaidMythic" end
    if KART.CbAlMythicPlus then settingsMap[KART.CbAlMythicPlus] = "autoLogMythicPlus" end
    if KART.SldAlMinKey then settingsMap[KART.SldAlMinKey] = "autoLogMinKey" end
    if KART.CbAlDungeons then settingsMap[KART.CbAlDungeons] = "autoLogDungeons" end
    if KART.CbAlDelves then settingsMap[KART.CbAlDelves] = "autoLogDelves" end
    if KART.SldUiScale then settingsMap[KART.SldUiScale] = "uiScale" end
    if KART.SldMenuSize then settingsMap[KART.SldMenuSize] = "menuFontSize" end
    if KART.SldContentSize then settingsMap[KART.SldContentSize] = "contentFontSize" end
    if KART.SldBgAlpha then settingsMap[KART.SldBgAlpha] = "bgAlpha" end
    if KART.SldFrameStrata then settingsMap[KART.SldFrameStrata] = "frameStrata" end
    if KART.SldRlBarStrata then settingsMap[KART.SldRlBarStrata] = "rlBarFrameStrata" end
    if KART.CbRlBarYieldMap then settingsMap[KART.CbRlBarYieldMap] = "rlBarYieldToMap" end
    if KART.CbHideBlizzardRaidManager then settingsMap[KART.CbHideBlizzardRaidManager] = "hideBlizzardRaidManager" end
    if KART.SldRlBarScale then settingsMap[KART.SldRlBarScale] = "rlBarScale" end
    if KART.SldRlBarButtonSize then settingsMap[KART.SldRlBarButtonSize] = "rlBarButtonSize" end
    if KART.SldRlBarAlpha then settingsMap[KART.SldRlBarAlpha] = "rlBarAlpha" end
    KART.ApplySettingsMap(settingsMap)

    if KART.BtnFont then KART.BtnFont.text:SetText(KART.L.BTN_FONT_PREFIX .. (KART_Settings.fontName or "Standard")) end

    if KART.BtnLang then
        local langText = KART.L.LANG_AUTO
        if KART_Settings.language == "enUS" then langText = KART.L.LANG_EN
        elseif KART_Settings.language == "deDE" then langText = KART.L.LANG_DE end
        KART.BtnLang.text:SetText(KART.L.BTN_LANGUAGE_PREFIX .. langText)
    end

    if KART.KeybindButtons then
        for key, btn in pairs(KART.KeybindButtons) do
            local bound = KART_Settings.keybinds and KART_Settings.keybinds[key]
            btn.text:SetText(bound and bound ~= "" and bound or KART.L.KB_NOT_BOUND)
        end
    end
end

-- Re-applies every static text in this file from KART.L once the saved language is known
-- (see KART.UI:RegisterLocaleRefresher in Utils.lua). Dynamic texts (BtnFont/BtnLang/BtnProfile
-- labels, keybind button captions, strata slider value) are handled by KART.SyncMainFrameWidgets.
KART.UI:RegisterLocaleRefresher(function()
    local L = KART.L

    -- Sidebar tabs + fixed header titles
    KART.BtnPromote.text:SetText(L.TAB_PROMOTE)
    KART.BtnRaidlead.text:SetText(L.TAB_RAIDLEAD)
    KART.BtnBuffCheck.text:SetText(L.TAB_BUFFCHECK)
    KART.BtnWoWUtils.text:SetText(L.TAB_WOWUTILS)
    KART.BtnCoTank.text:SetText(L.TAB_COTANK)
    if KART.BtnNotes then KART.BtnNotes.text:SetText(L.TAB_NOTES) end
    KART.BtnSettings.text:SetText(L.TAB_SETTINGS)
    if KART.SidebarModulesHeader then KART.SidebarModulesHeader:SetText(L.LABEL_MODULES) end
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
        if KART.RefreshFooterLinks then KART.RefreshFooterLinks() end
    end
    if KART.RefreshVersionText then KART.RefreshVersionText() end
    KART.RefreshModuleChips()
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.TAB_RAIDLEAD)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    if KART.TabTitles[6] then KART.TabTitles[6]:SetText(L.LABEL_COTANK_SETTINGS) end
    if KART.TabTitles[7] then KART.TabTitles[7]:SetText(L.TAB_NOTES) end
    -- TabTitles[5] belongs to Invite.lua and is refreshed there.

    -- Raidlead tab
    KART.CbActivate.text:SetText(L.SET_RL_ACTIVATE)   KART.CbActivate.tooltipText = L.DESC_RL_ACTIVATE
    KART.CbLock.text:SetText(L.SET_RL_LOCK)           KART.CbLock.tooltipText = L.DESC_RL_LOCK
    KART.CbAutoHide.text:SetText(L.SET_RL_AUTOHIDE)   KART.CbAutoHide.tooltipText = L.DESC_RL_AUTOHIDE
    KART.CbAutoHideCombat.text:SetText(L.SET_RL_AUTOHIDE_COMBAT)
    KART.CbAutoHideCombat.tooltipText = L.DESC_RL_AUTOHIDE_COMBAT
    KART.CbRcReasonDialog.text:SetText(L.SET_RL_RC_REASON)
    KART.CbRcReasonDialog.tooltipText = L.DESC_RL_RC_REASON
    if KART.CbHideBlizzardRaidManager then
        KART.CbHideBlizzardRaidManager.text:SetText(L.SET_RL_HIDE_BLIZZARD)
        KART.CbHideBlizzardRaidManager.tooltipText = L.DESC_RL_HIDE_BLIZZARD
    end
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
    if KART.BtnAddonNag then
        KART.BtnAddonNag.text:SetText(L.BTN_ADDON_NAG)
        KART.BtnAddonNag.tooltipText = L.DESC_ADDON_NAG
    end
    if KART.AddonVersionNote then KART.AddonVersionNote:SetText(L.NOTE_ADDON_VERSIONS) end

    -- Header search
    searchBtn.text:SetText(L.BTN_SEARCH)
    searchBtn.tooltipText = L.DESC_SEARCH
end)
