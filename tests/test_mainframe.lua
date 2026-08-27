-- The main window: switching tabs, the settings search, and the reset that wipes everything.
--
-- MainFrame.lua is fifty kilobytes of frame construction and the harness had never loaded a byte of
-- it. Most of that is layout and genuinely not worth asserting about -- but three things in it are
-- decisions rather than decoration, and one of them destroys every setting the player has.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim = F.NewRaid()
local me = sim.byName.Bramor
local KART = me.KART

-- Profiles.lua and RaidleadBar.lua alongside it, neither of which raidsim carries: the profile menu
-- calls straight into KART.LoadProfile, and recording a keybind ends by calling KART.ApplyKeybinds,
-- which is what puts the binding on the bar. Both are the real files rather than stand-ins, because
-- what those two controls do IS the call into them.
RaidSim.As(me, function()
    me.KART.CreateTabTitle = me.KART.CreateTabTitle or function() end
    for _, path in ipairs({ "MainFrame.lua", "CoTank.lua", "CoTankSettings.lua", "Profiles.lua", "RaidleadBar.lua" }) do
        local chunk = assert(loadstring(assert(io.open(path, "r")):read("*a"), "@" .. path))
        setfenv(chunk, me.env)
        chunk("KeineAhnungRaidTools", KART)
    end
end)
T.truthy(KART.MainFrame and KART.ShowTab, "the main window builds")
T.eq(#KART.FooterLinks, 3, "footer links survive load (SetFont before SetText)")
T.truthy(KART.BtnAddonNag, "Check Addon Versions is on the Settings tab")
T.eq(KART.BtnAddonNag:GetParent():GetParent(), KART.SettingsPanel,
    "Check Addon Versions sits on Settings, not Buff Check")
T.truthy(KART.SldCtSwapDuration, "Taunt Swap duration lives on the Co-Tank tab")

-- The locale refreshers, run the way Core.lua runs them: on load, and again whenever the language
-- is switched. Each one re-labels its widgets by hand, so it goes stale silently -- a renamed or
-- removed control leaves a nil index that throws only when somebody actually changes language.
do
    local ok, err = pcall(function() RaidSim.As(me, function() KART.UI:ApplyLocaleRefreshers() end) end)
    T.truthy(ok, "every registered locale refresher runs without error: " .. tostring(err))
end

local function As(fn) return RaidSim.As(me, fn) end

-- KART.SyncSettingsToUI lives in Core.lua, which needs the game and is not loadable here. Loading a
-- profile ends by calling it, and the one part of it this file is about is the profile button being
-- relabelled -- which Core does at Core.lua:157. tests/test_core_wiring.lua holds that call in place
-- against the source, so this stands in for it rather than inventing behaviour.
KART.SyncSettingsToUI = KART.SyncSettingsToUI or function()
    if KART.RefreshProfileButton then KART.RefreshProfileButton() end
end
-- Also Core.lua's, and pure restyling: it re-applies font, scale and colours to widgets already
-- built. Nothing below asserts on how anything looks, so a no-op is the honest stand-in.
KART.UpdateStyles = KART.UpdateStyles or function() end

-- Tabs ---------------------------------------------------------------------------------------------
do
    As(function() KART.ShowTab(1) end)
    T.eq(KART.CurrentTab, 1, "showing a tab records which one is current")
    As(function() KART.ShowTab(4) end)
    T.eq(KART.CurrentTab, 4, "and switching updates it")
    As(function() KART.ShowTab(5) end)
    T.eq(KART.CurrentTab, 5, "the WoWUtils tab is its own ShowTab index")
    T.truthy(KART.WoWUtilsPanel and KART.WoWUtilsPanel:IsShown(), "and shows the WoWUtils panel")
    T.eq(KART.PromotePanel:IsShown(), false, "not stacked on Automation")

    As(function() KART.ShowTab(6) end)
    T.eq(KART.CurrentTab, 6, "the Co-Tank tab is ShowTab index 6")
    T.truthy(KART.CoTankPanel and KART.CoTankPanel:IsShown(), "and shows the Co-Tank panel")
    T.eq(KART.SettingsPanel:IsShown(), false, "Settings is not shown on the Co-Tank tab")

    -- Exactly one content panel visible at a time. Two showing at once is the shape of every
    -- "settings are drawn over the loot council tab" report.
    local visible = 0
    for _, panel in pairs({ KART.PromotePanel, KART.RaidleadPanel, KART.BuffCheckPanel, KART.SettingsPanel, KART.WoWUtilsPanel, KART.CoTankPanel }) do
        if panel and panel:IsShown() then visible = visible + 1 end
    end
    T.eq(visible, 1, "exactly one tab's panel is shown")
end

-- Settings / Raidlead card packing: accent+profiles share a parent, look sliders sit on the
-- same card as the raidlead toggles. Two sparse full-width cards were the wasted middle.
do
    T.eq(KART.BtnProfile:GetParent(), KART.BtnAccentColor:GetParent(),
        "profile actions share the accent card")
    T.eq(KART.BtnReset:GetParent(), KART.BtnAccentColor:GetParent(),
        "reset sits on the same card as accent")
    T.eq(KART.SldRlBarScale:GetParent(), KART.CbActivate:GetParent(),
        "raidlead look sliders sit beside the toggles, not on a second empty card")
    local _, _, _, xStrip = KART.StatusStrip:GetPoint(1)
    T.eq(xStrip, 228, "tonight strip lines up with the settings cards")
    T.eq(KART.CbCtDebuffShow:GetParent(), KART.CtDebuffCard,
        "debuff strip settings sit on their own card")
    T.eq(KART.CbCtBuffShow:GetParent(), KART.CtBuffCard,
        "buff strip settings sit on a second card")
    T.truthy(KART.CbCtDebuffShow:GetParent() ~= KART.CbCtBuffShow:GetParent(),
        "and those cards are not the same frame")
end

-- Co-Tank settings flyout --------------------------------------------------------------------------
do
    T.eq(KART.CtFlyout:GetParent(), _G.UIParent, "the flyout is parented to UIParent, not the row")
    T.truthy(KART.BtnCtSettings, "a Settings button sits on the Co-Tank tab")
    T.eq(KART.BtnCtSettings:GetParent(), KART.CbCtModuleEnabled:GetParent(),
        "under the preview, on the same card as Test Mode")
    local function PointY(frame)
        local _, _, _, _, y = frame:GetPoint(1)
        return y
    end
    T.truthy(PointY(KART.CbCtTestMode) < PointY(KART.BtnCtSettings),
        "Test Mode sits below the Settings button")
    T.truthy(PointY(KART.CbCtOnlyGroup) < PointY(KART.CbCtTestMode),
        "Only in Group sits below Test Mode")
    me.env.KART_Settings.ctModuleEnabled = true
    As(function()
        KART.MainFrame:Show()
        KART.ShowTab(6)
    end)
    T.truthy(KART.CtFlyout:IsShown(), "opening Co-Tank with the module on shows the flyout")
    As(function()
        KART.CtFlyout.closeBtn:GetScript("OnClick")(KART.CtFlyout.closeBtn)
    end)
    T.eq(KART.CtFlyout:IsShown(), false, "X hides the flyout")
    As(function()
        KART.BtnCtSettings:GetScript("OnClick")(KART.BtnCtSettings)
    end)
    T.truthy(KART.CtFlyout:IsShown(), "Settings reopens the flyout after X")
    As(function() KART.ShowTab(4) end)
    T.eq(KART.CtFlyout:IsShown(), false, "switching away from Co-Tank hides the flyout")
    me.env.KART_Settings.ctModuleEnabled = false
end

-- The settings search ------------------------------------------------------------------------------
do
    local index = As(KART.BuildSearchIndex)
    T.truthy(#index >= 20, "the search index finds the settings widgets")

    local withTab, withWidget = 0, 0
    for _, e in ipairs(index) do
        if e.tabIndex then withTab = withTab + 1 end
        if e.widget then withWidget = withWidget + 1 end
    end
    T.eq(withTab, #index, "every entry knows which tab it lives on")
    T.eq(withWidget, #index, "and which widget to jump to -- an entry missing either cannot be used")

    -- Jumping is what the result rows do, and it must land on the entry's own tab.
    local target
    for _, e in ipairs(index) do if e.tabIndex ~= 1 then target = e break end end
    if target then
        As(function() KART.ShowTab(1) end)
        As(function() KART.JumpToSearchResult(target) end)
        T.eq(KART.CurrentTab, target.tabIndex, "a search result switches to the tab it belongs to")
    end
end

-- The three context menus in this file -----------------------------------------------------------
-- MenuUtil.CreateContextMenu was an empty stub until now, so the function that builds a menu's
-- entries had never run: none of these three had ever been opened by the suite.
do
    -- Profiles. The empty case is a real one -- a fresh install has none -- and it must say so
    -- rather than opening a menu with nothing in it.
    me.env.KART_Profiles = {}
    As(function() KART.BtnProfile:GetScript("OnClick")(KART.BtnProfile) end)
    T.eq(#KARTTEST.MenuLabels(), 1, "with no profiles saved the menu holds a single entry")
    T.truthy(not As(function() return KARTTEST.ClickMenu(KART.L.PROFILE_NONE_SAVED) end),
        "and it is inert, so there is nothing to click that could not work")
end

do
    me.env.KART_Profiles = {
        raid   = { pullTimerDuration = 42 },
        solo   = { pullTimerDuration = 7 },
        alltag = { pullTimerDuration = 21 },
    }
    As(function() KART.BtnProfile:GetScript("OnClick")(KART.BtnProfile) end)
    local labels = KARTTEST.MenuLabels()
    T.eq(#labels, 3, "every saved profile is listed")
    T.eq(labels[1] .. "," .. labels[2] .. "," .. labels[3], "alltag,raid,solo",
        "sorted, so the same profile is in the same place every time it is opened")

    T.truthy(As(function() return KARTTEST.ClickMenu("raid") end), "picking one loads it")
    T.eq(me.env.KART_Settings.pullTimerDuration, 42, "the settings it stored are in force")
    T.eq(me.env.KART_Settings.activeProfile, "raid", "and it is recorded as the active one")
    T.eq(KART.BtnProfile.text:GetText(), KART.L.PROFILE_LABEL_PREFIX .. "raid",
        "with the button naming it rather than still saying none")
end

do
    -- Language. The only menu entry in the addon that reloads the UI, which is a thing to do to
    -- somebody mid-raid -- so it must at least do it for a language that actually changed.
    local before = KARTTEST.reloads
    As(function() KART.BtnLang:GetScript("OnClick")(KART.BtnLang) end)
    T.eq(#KARTTEST.MenuLabels(), 3, "the language menu offers auto and the two locales")

    T.truthy(As(function() return KARTTEST.ClickMenu(KART.L.LANG_DE) end), "picking German is possible")
    T.eq(me.env.KART_Settings.language, "deDE", "which is what gets stored")
    T.eq(KARTTEST.reloads, before + 1, "and the reload that applies it happens")
    me.env.KART_Settings.language = "Auto"
end

do
    -- Fonts. Without LibSharedMedia there is exactly one, and it used to be a dead entry that set
    -- nothing -- picking the only font available has to still apply it.
    As(function() KART.BtnFont:GetScript("OnClick")(KART.BtnFont) end)
    local labels = KARTTEST.MenuLabels()
    T.truthy(#labels > 0, "the font menu is never empty")
    T.truthy(As(function() return KARTTEST.ClickMenu(labels[1]) end), "and its entries are clickable")
    T.eq(me.env.KART_Settings.fontName, labels[1], "picking one stores it")
    T.eq(KART.BtnFont.text:GetText(), KART.L.BTN_FONT_PREFIX .. labels[1],
        "and the button says which font is in use")
end

-- Module chips -------------------------------------------------------------------------------------
do
    As(function()
        me.env.KART_Settings.showRaidleadBar = true
        me.env.KART_Settings.bcModuleEnabled = false
        me.env.KART_Settings.ctModuleEnabled = true
        me.env.KART_Settings.autoModuleEnabled = true
        me.env.KART_Settings.wuModuleEnabled = false
        KART.RefreshModuleChips()
    end)
    T.eq(KART.BtnRaidlead.chip:GetText(), "ON", "raidlead chip reflects showRaidleadBar")
    T.eq(KART.BtnBuffCheck.chip:GetText(), "OFF", "buff check chip reflects bcModuleEnabled")
    T.eq(KART.BtnCoTank.chip:GetText(), "ON", "co-tank chip reflects ctModuleEnabled")
    T.eq(KART.BtnPromote.chip:GetText(), "ON", "automation chip reflects autoModuleEnabled")
    T.eq(KART.BtnWoWUtils.chip:GetText(), "OFF", "wowutils chip reflects wuModuleEnabled")
    T.is_nil(KART.BtnSettings.chip, "settings tab has no chip")
end

-- Invite channel chips are built at MainFrame file load, before Core.lua's ADDON_LOADED
-- creates KART_Settings. Refresh must no-op then, the same way KAUI ResolveStore defers.
do
    local saved = me.env.KART_Settings
    me.env.KART_Settings = nil
    local ok, err = pcall(function()
        for _, chip in ipairs(KART.InviteChannelChips) do chip:Refresh() end
    end)
    me.env.KART_Settings = saved
    T.truthy(ok, "invite chips refresh before ADDON_LOADED: " .. tostring(err))
    T.truthy(#KART.InviteChannelChips == 4, "four invite channel chips exist")
end

do
    -- Swap-line color preview and sound chips paint at file load, before ADDON_LOADED.
    local saved = me.env.KART_Settings
    me.env.KART_Settings = nil
    local ok, err = pcall(function()
        RaidSim.As(me, function()
            if KART.RefreshSwapSoundChips then KART.RefreshSwapSoundChips() end
        end)
    end)
    me.env.KART_Settings = saved
    T.truthy(ok, "swap-line chips refresh before ADDON_LOADED: " .. tostring(err))
end

do
    -- On vs off has to survive the mouse leaving: CreateModernButton's default OnLeave paints
    -- resting gray, which made every chip look off.
    As(function()
        me.env.KART_Settings.inviteChannels = {
            WHISPER = true, BN = false, GUILD = false, OFFICER = false,
        }
        for _, chip in ipairs(KART.InviteChannelChips) do chip:Refresh() end
    end)
    local onChip, offChip = KART.InviteChannelChips[1], KART.InviteChannelChips[2]
    local onR, onG, onB = onChip:GetBackdropBorderColor()
    local offR, offG, offB = offChip:GetBackdropBorderColor()
    T.truthy(onR ~= offR or onG ~= offG or onB ~= offB,
        "an on invite chip uses a different border than an off chip")
    As(function() onChip:GetScript("OnLeave")(onChip) end)
    local stayR, stayG, stayB = onChip:GetBackdropBorderColor()
    T.eq(stayR, onR, "leaving an on chip keeps the on border")
    T.eq(stayG, onG, "leaving an on chip keeps the on border")
    T.eq(stayB, onB, "leaving an on chip keeps the on border")
end

do
    -- CoTankSettings chips call KAUI.Lighten on hover; that file had no LibStub, so the live
    -- client threw as soon as the mouse entered Group / Dungeons / Raids.
    local chip = KART.CbCtTauntOnlyGroup
    T.truthy(chip and chip.GetScript, "taunt filter chips exist")
    local ok, err = pcall(function()
        As(function()
            chip:GetScript("OnEnter")(chip)
            chip:GetScript("OnLeave")(chip)
        end)
    end)
    T.truthy(ok, "hovering a taunt filter chip does not error: " .. tostring(err))
end

-- Keybinds -----------------------------------------------------------------------------------------
-- Recording a key is a small dialog with one rule in it that is not obvious: the key is TAKEN from
-- whoever held it. KART.ApplyKeybinds sets one override per action in list order, so two actions
-- sharing a binding meant the later one simply won while the earlier button went on displaying a key
-- that did nothing.
do
    local S = me.env.KART_Settings
    S.keybinds = {}
    KARTTEST.modifiers = {}

    local function Record(actionKey, key)
        local btn = KART.KeybindButtons[actionKey]
        As(function() btn:GetScript("OnClick")(btn, "LeftButton") end)
        As(function() KART.KeybindListener:GetScript("OnKeyDown")(KART.KeybindListener, key) end)
        return btn
    end

    local ready = Record("readyCheck", "F1")
    T.eq(S.keybinds.readyCheck, "F1", "a pressed key is stored against the action being recorded")
    T.eq(ready.text:GetText(), "F1", "and shown on its button")

    -- Modifiers are read at the moment the key lands, not from the key name -- and they go on in
    -- Blizzard's own order (ALT-CTRL-SHIFT-KEY), which is what SetOverrideBindingClick is given.
    KARTTEST.modifiers = { shift = true, alt = true }
    Record("pullTimer", "F2")
    T.eq(S.keybinds.pullTimer, "ALT-SHIFT-F2", "held modifiers become part of the binding")
    KARTTEST.modifiers = {}

    -- The rule: the same key on a second action takes it off the first.
    local pull = Record("pullTimer", "F1")
    T.eq(S.keybinds.pullTimer, "F1", "the second action gets the key")
    T.eq(S.keybinds.readyCheck, nil, "and the first no longer holds it")
    T.eq(ready.text:GetText(), KART.L.KB_NOT_BOUND,
        "with its button saying so, rather than displaying a key that would do nothing")
    T.truthy(pull ~= nil)

    -- Right-click clears, which is the only way back to unbound.
    As(function() pull:GetScript("OnClick")(pull, "RightButton") end)
    T.eq(S.keybinds.pullTimer, nil, "right-clicking a binding removes it")
    T.eq(pull.text:GetText(), KART.L.KB_NOT_BOUND, "and the button says it is unbound")
end

do
    -- Escape leaves the previous binding alone, and a bare modifier press is not a key.
    local S = me.env.KART_Settings
    S.keybinds = { readyCheck = "F5" }
    local btn = KART.KeybindButtons.readyCheck
    As(function() btn:GetScript("OnClick")(btn, "LeftButton") end)
    As(function() KART.KeybindListener:GetScript("OnKeyDown")(KART.KeybindListener, "LSHIFT") end)
    T.eq(S.keybinds.readyCheck, "F5", "holding a modifier alone does not end the recording")
    As(function() KART.KeybindListener:GetScript("OnKeyDown")(KART.KeybindListener, "ESCAPE") end)
    T.eq(S.keybinds.readyCheck, "F5", "and escape leaves the old binding in place")
end

-- Reset --------------------------------------------------------------------------------------------
-- The one control here that cannot be undone. It wipes KART_Settings and rebuilds it from defaults.
do
    local S = me.env.KART_Settings
    S.pullTimerDuration = 99
    S.inviteKeywords = "meins"
    S.minimap.hide = true
    local minimapTable = S.minimap
    local before = KARTTEST.reloads

    -- Through the button, not by calling the handler: the confirmation IS the feature here, and a
    -- reset that could be reached without it would be the finding.
    As(function() KART.BtnReset:GetScript("OnClick")(KART.BtnReset) end)
    T.eq(#KARTTEST.popups, 1, "the reset asks before it wipes anything")
    T.eq(me.env.KART_Settings.pullTimerDuration, 99, "and changes nothing until it is answered")
    T.truthy(As(function() return KARTTEST.AcceptPopup("KART_RESET_CONFIRM") end),
        "and the confirmation is answerable")

    T.eq(me.env.KART_Settings.pullTimerDuration, KART.Defaults.pullTimerDuration,
        "a changed setting is back at its default")
    T.eq(me.env.KART_Settings.inviteKeywords, KART.Defaults.inviteKeywords,
        "and so is a typed one")
    T.eq(KARTTEST.reloads, before + 1, "and the window is reloaded to redraw every widget")

    -- Deep-copied, not shared: a shallow copy would hand KART.Defaults' own nested table to
    -- KART_Settings, and the next thing the player toggled would edit the defaults themselves --
    -- so the reset after that would restore whatever they had just set.
    T.truthy(me.env.KART_Settings.minimap ~= KART.Defaults.minimap,
        "nested tables are copied rather than shared with the defaults")
    me.env.KART_Settings.minimap.hide = true
    T.truthy(not KART.Defaults.minimap.hide, "so editing them afterwards cannot reach the defaults")
    T.truthy(me.env.KART_Settings.minimap ~= minimapTable, "and the old table is genuinely replaced")
end

-- Tonight strip: three glance fields on the main window, no extra tab.
do
    T.truthy(KART.StatusStrip, "the main window has a status strip")
    T.truthy(KART.StatusStrip.raidValue and KART.StatusStrip.flaskValue and KART.StatusStrip.rcValue,
        "with raid, flask/food and RC cells")
    As(function() KART.RefreshStatusStrip() end)
    T.eq(KART.StatusStrip.raidValue:GetText(), "—",
        "no WoWUtils boss list is a dash, not 0/0")
end

do
    As(function()
        KART.WU.bosses = {}
        KART.WU.ParseImport(
            "EncounterID:1;Difficulty:Mythic;Name:Test\n"
            .. "invitelist:Bramor-TarrenMill,Alric-TarrenMill,Ghost-SomeRealm;\n")
        local present, total = KART.WU.GroupPresenceForBoss(1)
        T.eq(total, 3, "the boss list is the denominator")
        T.eq(present, 2, "Bramor and Alric are already in the raid")
        KART.RefreshStatusStrip()
        T.eq(KART.StatusStrip.raidValue:GetText(), "2/3", "the strip shows present/total")
        KART.WU.ResetBosses()
    end)
end

-- Changelog popup: WoW frames cannot be destroyed. Rebuilding the scroll child (and every
-- FontString/Texture on it) each open leaks for the rest of the session.
do
    As(function()
        local orig = _G.CreateFrame
        local n = 0
        _G.CreateFrame = function(...)
            n = n + 1
            return orig(...)
        end
        KART.ShowChangelogPopup()
        local afterFirst = n
        local child = KART.changelogPopup.scrollChild
        KART.changelogPopup:Hide()
        KART.ShowChangelogPopup()
        _G.CreateFrame = orig
        T.eq(KART.changelogPopup.scrollChild, child,
            "reopening changelog keeps the same scroll child")
        T.eq(n, afterFirst, "and creates no further frames, fontstrings or textures")
    end)
end

