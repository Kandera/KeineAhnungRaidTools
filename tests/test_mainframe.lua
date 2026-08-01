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

-- Profiles.lua alongside it: the profile menu built below calls straight into KART.LoadProfile, and
-- raidsim does not carry that file (nothing in the loot flow touches it).
RaidSim.As(me, function()
    for _, path in ipairs({ "MainFrame.lua", "Profiles.lua" }) do
        local chunk = assert(loadstring(assert(io.open(path, "r")):read("*a"), "@" .. path))
        setfenv(chunk, me.env)
        chunk("KeineAhnungRaidTools", KART)
    end
end)
T.truthy(KART.MainFrame and KART.ShowTab, "the main window builds")

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

    -- Exactly one content panel visible at a time. Two showing at once is the shape of every
    -- "settings are drawn over the loot council tab" report.
    local visible = 0
    for _, panel in pairs({ KART.PromotePanel, KART.InvitePanel, KART.BuffPanel, KART.SettingsPanel,
                            KART.LootCouncilPanel, KART.WoWUtilsPanel }) do
        if panel and panel:IsShown() then visible = visible + 1 end
    end
    T.eq(visible, 1, "exactly one tab's panel is shown")
end

-- The settings search ------------------------------------------------------------------------------
do
    local index = As(KART.BuildSearchIndex)
    T.truthy(#index > 0, "the search index finds the settings widgets")

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
        raid   = { lcVoteSeconds = 42 },
        solo   = { lcVoteSeconds = 7 },
        alltag = { lcVoteSeconds = 21 },
    }
    As(function() KART.BtnProfile:GetScript("OnClick")(KART.BtnProfile) end)
    local labels = KARTTEST.MenuLabels()
    T.eq(#labels, 3, "every saved profile is listed")
    T.eq(labels[1] .. "," .. labels[2] .. "," .. labels[3], "alltag,raid,solo",
        "sorted, so the same profile is in the same place every time it is opened")

    T.truthy(As(function() return KARTTEST.ClickMenu("raid") end), "picking one loads it")
    T.eq(me.env.KART_Settings.lcVoteSeconds, 42, "the settings it stored are in force")
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

-- Reset --------------------------------------------------------------------------------------------
-- The one control here that cannot be undone. It wipes KART_Settings and rebuilds it from defaults.
do
    local S = me.env.KART_Settings
    S.lcVoteSeconds = 99
    S.inviteKeywords = "meins"
    S.minimap.hide = true
    local minimapTable = S.minimap
    local before = KARTTEST.reloads

    -- Through the button, not by calling the handler: the confirmation IS the feature here, and a
    -- reset that could be reached without it would be the finding.
    As(function() KART.BtnReset:GetScript("OnClick")(KART.BtnReset) end)
    T.eq(#KARTTEST.popups, 1, "the reset asks before it wipes anything")
    T.eq(me.env.KART_Settings.lcVoteSeconds, 99, "and changes nothing until it is answered")
    T.truthy(As(function() return KARTTEST.AcceptPopup("KART_RESET_CONFIRM") end),
        "and the confirmation is answerable")

    T.eq(me.env.KART_Settings.lcVoteSeconds, KART.Defaults.lcVoteSeconds,
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
