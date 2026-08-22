-- Keyword invites, and the one input the addon may not read.
--
-- GroupLogic.lua is loaded the way WoW loads it -- a chunk called with (addonName, KART) -- rather
-- than having its functions lifted out, because what is under test spans two of them: UpdateCache
-- builds the keyword table, HandleChatInvite decides against it, and testing either alone would
-- miss the case-folding contract between them.
--
-- Why this file exists at all: Blizzard hands chat text written by strangers to addons as a SECRET
-- VALUE. It answers "string" to type() and throws on the first string operation, so the type guard
-- that had always been there let it straight through into KAUtil.CaseFold. Reported from a live
-- client doing world content -- 54 errors in one session, one per incoming whisper (GitHub #17).

local KAUtil = LibStub("KAUtil-1.0")

-- One client's environment: reads fall through to the shared stubs, writes stay here.
local env = setmetatable({}, { __index = _G })
env.KART_Settings = { inviteKeywords = "inv;invite", autoConvertToRaid = false }

env.KART_L = {
    INVITE_REPLY_NOT_LEADER = "not leader",
    INVITE_REPLY_FULL = "full",
    INVITE_REPLY_COMBAT = "combat",
}

local invited = {}
local converted = false
local confirmed = {}
env.C_PartyInfo = {
    InviteUnit = function(name) invited[#invited + 1] = name end,
    ConvertToRaid = function() converted = true end,
    ConfirmInviteUnit = function(name) confirmed[#confirmed + 1] = name end,
}

local KART = {}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("GroupLogic.lua", "r")):read("*a"), "@GroupLogic.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
KART.L = env.KART_L

-- Solo, so the "not IsInGroup()" half of the permission check is the live one. Set explicitly
-- rather than assumed: whatever roster a previous test file installed is still there, and with one
-- in place IsInGroup() is true and every invite below is refused for want of group permissions --
-- which is how the first run of this file failed.
local prevActive, prevSolo = KARTTEST.activeUnit, KARTTEST.solo
KARTTEST.activeUnit = "player"
KARTTEST.solo = { player = true }

KART.UpdateCache()
T.truthy(KART.InviteKeywordsTable["inv"], "the keyword table is built from the setting")

local function Invite(msg, sender)
    invited = {}
    converted = false
    confirmed = {}
    local ok, err = pcall(KART.HandleChatInvite, msg, sender, "CHAT_MSG_WHISPER")
    return ok, invited, err
end

-- The ordinary path, so the test below cannot pass by the invite simply never working ------------
do
    local ok, got = Invite("inv", "Alric-TarrenMill")
    T.truthy(ok, "a plain whisper is handled without error")
    T.eq(got[1], "Alric-TarrenMill", "and the keyword invites the sender")
end

-- Case and whitespace, which is what CaseFold and TrimString are there for ----------------------
do
    local _, got = Invite("  INV  ", "Sinja-TarrenMill")
    T.eq(got[1], "Sinja-TarrenMill", "the match is case- and whitespace-insensitive")
end

do
    local _, got = Invite("not a keyword", "Merrit-TarrenMill")
    T.eq(#got, 0, "an unrelated whisper invites nobody")
end

-- The secret message (GitHub #17) ---------------------------------------------------------------
-- The stub cannot make string operations throw, so the assertion is the OTHER observable: a message
-- whose text would match must not be acted on, because the client did not let us read that text.
-- Anything else would mean the addon decided using a value it is not allowed to see.
do
    local secret = "inv"
    KARTTEST.secretValues[secret] = true
    local ok, got = Invite(secret, "Fremd-TarrenMill")
    KARTTEST.secretValues[secret] = nil

    T.truthy(ok, "a secret whisper is handled without error")
    T.eq(#got, 0, "and invites nobody -- its text was never readable, so there is no keyword to match")
end

-- KAUtil.IsSecret itself, including the clients that have no such API ---------------------------
do
    local s = "whatever"
    KARTTEST.secretValues[s] = true
    T.eq(KAUtil.IsSecret(s), true, "IsSecret reports a value the client marked secret")
    KARTTEST.secretValues[s] = nil
    T.eq(KAUtil.IsSecret(s), false, "and reports an ordinary string as readable")
    T.eq(KAUtil.IsSecret(nil), false, "nil is not secret")

    -- Older clients have no issecretvalue at all, and there nothing is secret. Answering false is
    -- correct; erroring on the missing global would break every caller on those clients.
    local real = _G.issecretvalue
    _G.issecretvalue = nil
    T.eq(KAUtil.IsSecret("x"), false, "a client without the API reports nothing secret")
    _G.issecretvalue = real
end

-- A non-string is still rejected before any of this ---------------------------------------------
do
    local ok, got = Invite(nil, "Alric-TarrenMill")
    T.truthy(ok, "a nil message is handled without error")
    T.eq(#got, 0, "and invites nobody")
end

-- Battle.net whispers, where the sender is not a character at all ------------------------------
-- CHAT_MSG_BN_WHISPER hands over a numeric Battle.net account id, and InviteUnit takes a character
-- name: passing the id silently invites nobody. The friend's current character has to be looked up,
-- and it may not exist -- somebody whispering from the app, or playing another Blizzard game, has an
-- account but no WoW character to invite.
local accounts = {}
env.C_BattleNet = { GetAccountInfoByID = function(id) return accounts[id] end }

-- The id is CHAT_MSG_BN_WHISPER's thirteenth event argument, and HandleChatInvite takes the first
-- three by name -- so it is the eleventh of the varargs, which is what select(11, ...) reads. The
-- ten placeholders below are the event arguments in between; getting the count wrong is exactly the
-- mistake this path cannot survive, so it is spelled out rather than counted in the head.
local function BNInvite(msg, bnetID)
    invited = {}
    local ok, err = pcall(KART.HandleChatInvite, msg, "SomeBattleTag", "CHAT_MSG_BN_WHISPER",
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, bnetID)
    return ok, invited, err
end

do
    accounts[77] = { gameAccountInfo = { characterName = "Alric", realmName = "TarrenMill" } }
    local ok, got = BNInvite("inv", 77)
    T.truthy(ok, "a Battle.net whisper is handled without error")
    T.eq(got[1], "Alric-TarrenMill", "and invites the friend's character, realm-qualified")
    T.truthy(got[1] ~= 77, "rather than the account id, which would invite nobody at all")
end

do
    -- Same realm as us: the game leaves realmName empty, and appending a bare "-" would produce a
    -- name that matches nobody.
    accounts[78] = { gameAccountInfo = { characterName = "Sinja", realmName = "" } }
    local _, got = BNInvite("inv", 78)
    T.eq(got[1], "Sinja", "a friend on our own realm is invited by plain name")
end

do
    -- The friend is online on Battle.net but not in WoW.
    accounts[79] = { gameAccountInfo = { characterName = "" } }
    local ok, got = BNInvite("inv", 79)
    T.truthy(ok, "a friend with no character is handled without error")
    T.eq(#got, 0, "and nobody is invited")

    accounts[80] = {}
    local ok2, got2 = BNInvite("inv", 80)
    T.truthy(ok2, "and so is an account the client knows nothing about")
    T.eq(#got2, 0, "with nobody invited there either")
end

do
    local _, got = BNInvite("not a keyword", 77)
    T.eq(#got, 0, "an unrelated Battle.net whisper invites nobody")
end

-- Auto-Raid conversion, the whole point of GroupLogic's part of the setting now (2026-08-12) -------
-- Before, the party converted the instant it hit 5 members (a Core.lua roster-event check, since
-- removed); this branch is the only place autoConvertToRaid acts on a chat invite. InviteUnit on a
-- full party raises CONVERT_TO_RAID instead of inviting, so the 6th seat must go through
-- ConfirmInviteUnit. The group of 5 is installed here rather than inherited from the solo setup
-- above -- which means overriding KARTTEST.solo for the duration, same as the file-level override
-- at the top exists for.
do
    local prevRoster = KARTTEST.SnapshotRoster()
    local prevSolo2 = KARTTEST.solo
    KARTTEST.solo = {}
    env.KART_Settings.autoConvertToRaid = true
    KARTTEST.SetParty({
        { name = "Merrit", realm = "TarrenMill" },
        { name = "Corvin", realm = "TarrenMill" },
        { name = "Alric", realm = "TarrenMill" },
        { name = "Sinja", realm = "TarrenMill" },
        { name = "Bramor", realm = "TarrenMill", leader = true },
    })

    local ok, got = Invite("inv", "Kandera-TarrenMill")
    T.truthy(ok, "a keyword whisper that would be a 6th member is handled without error")
    T.eq(confirmed[1], "Kandera-TarrenMill",
        "and ConfirmInviteUnit skips the CONVERT_TO_RAID popup InviteUnit would raise on a full party")
    T.eq(#got, 0, "InviteUnit is not used for that 6th seat")
    T.truthy(not converted, "ConvertToRaid is not the path; the confirm-invite converts as part of inviting")

    local ok2, got2 = Invite("inv", "Alric-TarrenMill")
    T.truthy(ok2, "a keyword whisper from an existing member is handled without error")
    T.eq(#confirmed, 0, "and does not confirm-invite -- that member already has a seat (FIX 1)")
    T.truthy(not converted, "and does not ConvertToRaid either")
    T.eq(got2[1], "Alric-TarrenMill", "though the sender is still invited like any other match")

    env.KART_Settings.autoConvertToRaid = false
    KARTTEST.solo = prevSolo2
    KARTTEST.RestoreRoster(prevRoster)
end

-- Auto-reply: keyword matched but no invite went out -------------------------------------------
local function LastWhisper()
    for i = #KARTTEST.chat, 1, -1 do
        local line = KARTTEST.chat[i]
        if line.channel == "WHISPER" then return line end
    end
end

do
    local prevRoster = KARTTEST.SnapshotRoster()
    local prevSolo2 = KARTTEST.solo
    KARTTEST.solo = {}
    KARTTEST.SetParty({
        { name = "Corvin", realm = "TarrenMill", leader = true },
        { name = "Merrit", realm = "TarrenMill" },
    })
    KARTTEST.activeUnit = "player"
    KART.inviteAutoReplyAt = {}

    KARTTEST.ClearChat()
    Invite("inv", "Kandera-TarrenMill")
    local reply = LastWhisper()
    T.truthy(reply, "a keyword from a non-leader gets an auto-reply whisper")
    T.eq(reply.target, "Kandera-TarrenMill", "and it goes to the sender")
    T.eq(reply.msg, "not leader", "explaining the player is not the leader")
    T.eq(#invited, 0, "and nobody is invited")

    KARTTEST.solo = prevSolo2
    KARTTEST.RestoreRoster(prevRoster)
end

do
    local prevRoster = KARTTEST.SnapshotRoster()
    local prevSolo2 = KARTTEST.solo
    KARTTEST.solo = {}
    env.KART_Settings.autoConvertToRaid = false
    KARTTEST.SetParty({
        { name = "Merrit", realm = "TarrenMill" },
        { name = "Corvin", realm = "TarrenMill" },
        { name = "Alric", realm = "TarrenMill" },
        { name = "Sinja", realm = "TarrenMill" },
        { name = "Bramor", realm = "TarrenMill", leader = true },
    })
    KARTTEST.activeUnit = "player"
    KART.inviteAutoReplyAt = {}

    KARTTEST.ClearChat()
    Invite("inv", "Kandera-TarrenMill")
    local reply = LastWhisper()
    T.truthy(reply, "a 6th keyword with convert off gets an auto-reply")
    T.eq(reply.msg, "full", "because the group is full and convert is off")
    T.eq(#invited, 0, "and InviteUnit is not used")
    T.eq(#confirmed, 0, "nor ConfirmInviteUnit")

    KARTTEST.solo = prevSolo2
    KARTTEST.RestoreRoster(prevRoster)
end

do
    local prevRoster = KARTTEST.SnapshotRoster()
    local prevCombat = KARTTEST.inCombat
    KARTTEST.inCombat = true
    KARTTEST.activeUnit = "player"
    KART.inviteAutoReplyAt = {}

    KARTTEST.ClearChat()
    Invite("inv", "Kandera-TarrenMill")
    local reply = LastWhisper()
    T.truthy(reply, "a keyword whisper in combat gets an auto-reply")
    T.eq(reply.msg, "combat", "because invites are blocked in combat")
    T.eq(#invited, 0, "and nobody is invited")

    KARTTEST.inCombat = prevCombat
    KARTTEST.RestoreRoster(prevRoster)
end

do
    KART.inviteAutoReplyAt = {}
    KARTTEST.ClearChat()
    Invite("inv", "Kandera-TarrenMill")
    T.eq(#KARTTEST.chat, 0, "a successful solo invite sends no auto-reply")
end

do
    KART.inviteAutoReplyAt = {}
    local prevRoster = KARTTEST.SnapshotRoster()
    local prevSolo2 = KARTTEST.solo
    KARTTEST.solo = {}
    KARTTEST.SetParty({
        { name = "Corvin", realm = "TarrenMill", leader = true },
        { name = "Merrit", realm = "TarrenMill" },
    })
    KARTTEST.activeUnit = "player"

    KARTTEST.ClearChat()
    Invite("inv", "Kandera-TarrenMill")
    Invite("inv", "Kandera-TarrenMill")
    T.eq(#KARTTEST.chat, 1, "auto-reply debounces repeated requests from the same name")

    KARTTEST.solo = prevSolo2
    KARTTEST.RestoreRoster(prevRoster)
end

do
    local secret = "inv"
    KARTTEST.secretValues[secret] = true
    KARTTEST.ClearChat()
    local ok = Invite(secret, "Fremd-TarrenMill")
    KARTTEST.secretValues[secret] = nil
    T.truthy(ok, "a secret keyword is handled without error")
    T.eq(#KARTTEST.chat, 0, "and gets no auto-reply either")
end

-- Leave the harness as found, for whatever file runs next.
KARTTEST.activeUnit, KARTTEST.solo = prevActive, prevSolo
