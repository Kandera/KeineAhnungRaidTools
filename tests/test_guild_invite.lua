-- Guild-rank bulk invite: collect online members of selected ranks, then the same
-- InviteNameList pipeline WoWUtils bulk invite uses.
--
-- Invite.lua is loaded the way WoW loads it -- a chunk called with (addonName, KART) --
-- because CollectOnlineGuildNamesByRanks, InviteNameList and InviteGuildRanks share
-- GroupNameSet and the confirm popup registered at file load.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = { autoModuleEnabled = true, inviteGuildRanks = {}, wuModuleEnabled = true }
local KART = {
    UI = {
        RegisterStaticPopup = function(_, name, def)
            StaticPopupDialogs[name] = def
        end,
    },
    L = {
        AUTO_MODULE_DISABLED_MSG = "automation off",
        GI_MSG_NOT_GUILD = "not guild",
        GI_MSG_NONE = "none to invite",
        GI_CONFIRM_TEXT = "Invite %d online guild members (%s)?",
        WU_MSG_NOT_LEADER = "not leader",
        WU_MSG_COMBAT = "combat",
        WU_MSG_INVITED = "%d players invited for %s.",
        WU_MSG_ALREADY_IN = "(%d already in raid)",
        WU_MODULE_DISABLED_MSG = "disabled",
        BTN_ACCEPT = "Accept",
        BTN_CANCEL = "Cancel",
        WU_REMOVE_CONFIRM_TEXT = "Remove %d?",
        WU_RESET_CONFIRM_TEXT = "Reset?",
        WU_STATUS_EMPTY = "empty",
    },
}
env.KART = KART

local roster = {}
local inGuild = true
env.IsInGuild = function() return inGuild end
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
    local m = roster[i]
    if not m then return end
    return m.name, m.rankName or "Rank", m.rankIndex, 80, "Warrior", "Stormwind",
        "", "", m.isOnline, 0, "WARRIOR", 0, 0, m.isMobile == true, false, 0, "Player-1-" .. i
end
env.GuildControlGetNumRanks = function() return 4 end
env.GuildControlGetRankName = function(i)
    return ({ "Guild Master", "Officer", "Raider", "Trial" })[i]
end

do
    local chunk = assert(loadstring(assert(io.open("Invite.lua", "r"):read("*a")), "@Invite.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
KART.L = env.KART.L or KART.L
local WU = KART.WU

local function Names(list)
    local out = {}
    for i, n in ipairs(list) do out[i] = n end
    table.sort(out)
    return table.concat(out, ",")
end

-- CollectOnlineGuildNamesByRanks -------------------------------------------------------
do
    roster = {
        { name = "Raiderone-Blackmoore", rankIndex = 2, isOnline = true },
        { name = "Offlineguy-Blackmoore", rankIndex = 2, isOnline = false },
        { name = "Officer-Blackmoore", rankIndex = 1, isOnline = true },
        { name = "Gmchar-Blackmoore", rankIndex = 0, isOnline = true },
        { name = "Mobileonly-Blackmoore", rankIndex = 2, isOnline = false, isMobile = true },
        { name = "Trial-Blackmoore", rankIndex = 3, isOnline = true },
    }
    local got = KART.CollectOnlineGuildNamesByRanks({ [2] = true })
    T.eq(Names(got), "Raiderone-Blackmoore",
        "only online members of the selected rank are collected")
end

do
    local got = KART.CollectOnlineGuildNamesByRanks({ [0] = true })
    T.eq(got[1], "Gmchar-Blackmoore", "rank index 0 (guild master) is selectable")
end

do
    local got = KART.CollectOnlineGuildNamesByRanks({ [2] = true, [3] = true })
    T.eq(Names(got), "Raiderone-Blackmoore,Trial-Blackmoore",
        "multiple selected ranks are unioned")
end

do
    local got = KART.CollectOnlineGuildNamesByRanks({})
    T.eq(#got, 0, "an empty rank set collects nobody")
end

do
    inGuild = false
    local got = KART.CollectOnlineGuildNamesByRanks({ [2] = true })
    T.eq(#got, 0, "not in a guild collects nobody")
    inGuild = true
end

-- InviteNameList -----------------------------------------------------------------------
local prevRoster = KARTTEST.SnapshotRoster()
local prevCombat = KARTTEST.inCombat
KARTTEST.ClearInvites()
KARTTEST.popups = {}

do
    KARTTEST.SetRaid({})
    KARTTEST.ClearInvites()
    KART.InviteNameList({ "Alpha-Blackmoore", "Bravo-Thrall" }, "Raider")
    T.eq(#KARTTEST.invited, 2, "a solo bulk invite sends both names")
    T.eq(KARTTEST.invited[1], "Alpha-Blackmoore", "first name is invited")
    T.eq(KARTTEST.invited[2], "Bravo-Thrall", "second name is invited")
end

do
    KARTTEST.SetParty({
        { name = "Other", realm = "Blackmoore" },
        { name = "Already", realm = "Blackmoore", leader = true },
    })
    KARTTEST.ClearInvites()
    KART.InviteNameList({ "Already-Blackmoore", "Newbie-Blackmoore" }, "Raider")
    T.eq(#KARTTEST.invited, 1, "someone already in the group is not re-invited")
    T.eq(KARTTEST.invited[1], "Newbie-Blackmoore", "only the missing name is invited")
end

do
    KARTTEST.SetRaid({})
    KARTTEST.ClearInvites()
    KARTTEST.inCombat = true
    KART.InviteNameList({ "Alpha-Blackmoore" }, "Raider")
    T.eq(#KARTTEST.invited, 0, "combat refuses the bulk invite")
    KARTTEST.inCombat = false
end

do
    KARTTEST.SetParty({
        { name = "Lead", realm = "TarrenMill", leader = true },
        { name = "Me", realm = "TarrenMill" },
    })
    -- SetParty puts the last member on "player". They are not the leader.
    KARTTEST.ClearInvites()
    KART.InviteNameList({ "Newbie-Blackmoore" }, "Raider")
    T.eq(#KARTTEST.invited, 0, "a grouped non-leader cannot bulk invite")
end

do
    -- Six names from solo: party would overflow, so the deferred raid convert flag is armed.
    -- SetRaid({}) still reports IsInRaid, which skips the convert; solo is the real starting point.
    local prevActive, prevSolo = KARTTEST.activeUnit, KARTTEST.solo
    KARTTEST.activeUnit = "player"
    KARTTEST.solo = { player = true }
    KART.pendingBulkRaidConvert = false
    KARTTEST.ClearInvites()
    KART.InviteNameList({
        "A-Blackmoore", "B-Blackmoore", "C-Blackmoore",
        "D-Blackmoore", "E-Blackmoore", "F-Blackmoore",
    }, "Raider")
    T.eq(#KARTTEST.invited, 6, "six solo invites still go out")
    T.eq(KART.pendingBulkRaidConvert, true, "and the deferred raid convert is armed")
    KART.pendingBulkRaidConvert = false
    KARTTEST.activeUnit, KARTTEST.solo = prevActive, prevSolo
end

do
    WU.bosses = { { name = "Nymrissa", players = { "Alric-TarrenMill" } } }
    env.KART_Settings.wuModuleEnabled = false
    KARTTEST.SetRaid({})
    KARTTEST.ClearInvites()
    WU.InviteBoss(1)
    T.eq(#KARTTEST.invited, 0, "InviteBoss still respects the wowutils module switch")
    env.KART_Settings.wuModuleEnabled = true
end

-- InviteGuildRanks ---------------------------------------------------------------------
local function AcceptGuildConfirm()
    return KARTTEST.AcceptPopup("KART_GI_CONFIRM")
end

do
    env.KART_Settings.autoModuleEnabled = false
    KARTTEST.SetRaid({})
    KARTTEST.ClearInvites()
    KARTTEST.popups = {}
    KART.InviteGuildRanks()
    T.eq(#KARTTEST.popups, 0, "a disabled automation module shows no confirm")
    T.eq(#KARTTEST.invited, 0, "and invites nobody")
    env.KART_Settings.autoModuleEnabled = true
end

do
    roster = {
        { name = "Raiderone-Blackmoore", rankIndex = 2, isOnline = true },
        { name = "Trial-Blackmoore", rankIndex = 3, isOnline = true },
    }
    env.KART_Settings.inviteGuildRanks = { [2] = true, [3] = true }
    KARTTEST.SetRaid({})
    KARTTEST.ClearInvites()
    KARTTEST.popups = {}
    KART.InviteGuildRanks()
    T.eq(#KARTTEST.popups, 1, "matching online ranks raise a confirm")
    T.eq(KARTTEST.popups[1].which, "KART_GI_CONFIRM", "the guild-invite confirm is the one shown")
    T.eq(KARTTEST.popups[1].a, 2, "the confirm names the pending count")
    T.eq(#KARTTEST.invited, 0, "nobody is invited until the confirm is accepted")
    T.truthy(AcceptGuildConfirm(), "the confirm can be accepted")
    T.eq(#KARTTEST.invited, 2, "accepting invites the collected names")
end

do
    roster = {
        { name = "Raiderone-Blackmoore", rankIndex = 2, isOnline = true },
    }
    env.KART_Settings.inviteGuildRanks = { [2] = true }
    KARTTEST.SetParty({
        { name = "Raiderone", realm = "Blackmoore", leader = true },
    })
    KARTTEST.ClearInvites()
    KARTTEST.popups = {}
    KART.InviteGuildRanks()
    T.eq(#KARTTEST.popups, 0, "already-in-group members do not raise a confirm")
    T.eq(#KARTTEST.invited, 0, "and are not invited")
end

do
    env.KART_Settings.inviteGuildRanks = {}
    KARTTEST.SetRaid({})
    KARTTEST.popups = {}
    KART.InviteGuildRanks()
    T.eq(#KARTTEST.popups, 0, "no selected ranks shows no confirm")
end

KARTTEST.RestoreRoster(prevRoster)
KARTTEST.inCombat = prevCombat
KARTTEST.ClearInvites()
KARTTEST.popups = {}
