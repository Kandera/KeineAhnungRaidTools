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

RaidSim.As(me, function()
    local chunk = assert(loadstring(assert(io.open("MainFrame.lua", "r")):read("*a"), "@MainFrame.lua"))
    setfenv(chunk, me.env)
    chunk("KeineAhnungRaidTools", KART)
end)
T.truthy(KART.MainFrame and KART.ShowTab, "the main window builds")

local function As(fn) return RaidSim.As(me, fn) end

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
