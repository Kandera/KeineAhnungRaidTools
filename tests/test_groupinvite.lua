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

local invited = {}
env.C_PartyInfo = { InviteUnit = function(name) invited[#invited + 1] = name end }

local KART = {}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("GroupLogic.lua", "r")):read("*a"), "@GroupLogic.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end

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

-- Leave the harness as found, for whatever file runs next.
KARTTEST.activeUnit, KARTTEST.solo = prevActive, prevSolo
