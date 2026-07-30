local KASC = LibStub("KASC-1.0")

KASC:Init("KART")
KARTTEST.SetNSAPI(false)
KARTTEST.realm = "TarrenMill"
KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })

-- Exact vs payload dispatch --------------------------------------------------------------
local hits = {}
KASC:RegisterMessage("TEST_EXACT", {}, function(payload) hits[#hits + 1] = { "exact", payload } end)
KASC:RegisterMessage("TEST_PAY", { payload = true }, function(payload) hits[#hits + 1] = { "pay", payload } end)

KASC.Dispatch("TEST_EXACT", "RAID", "Ann-TarrenMill")
T.eq(hits[1][1], "exact", "an exact token dispatches to its handler")
T.eq(hits[1][2], nil, "an exact token's handler receives payload = nil, not the message or an empty string")

hits = {}
KASC.Dispatch("TEST_PAY:hello:world", "RAID", "Ann-TarrenMill")
T.eq(hits[1][1], "pay", "a payload token dispatches to its handler")
T.eq(hits[1][2], "hello:world", "the payload keeps every colon after the first")

hits = {}
KASC.Dispatch("TEST_EXACT:extra", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "an exact-only token with a payload is not dispatched")

hits = {}
KASC.Dispatch("UNKNOWN_TOKEN", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "an unregistered token is dropped")

-- The group gate ---------------------------------------------------------------------------
hits = {}
KASC:RegisterMessage("TEST_GATED", { payload = true, group = true },
    function() hits[#hits + 1] = true end)
KASC.Dispatch("TEST_GATED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 1, "a grouped sender passes the group gate")
KASC.Dispatch("TEST_GATED:x", "WHISPER", "Stranger-Silvermoon")
T.eq(#hits, 1, "an outsider is rejected by the group gate")
-- The realm is what makes this a real gate: resolution is short-name based, so a same-short-
-- named outsider would resolve onto the group member's GUID and pass every authority check.
KASC.Dispatch("TEST_GATED:x", "WHISPER", "Ann-Silvermoon")
T.eq(#hits, 1, "a same-short-name sender on another realm is rejected")

-- The enabled gate --------------------------------------------------------------------------
local moduleOn = false
hits = {}
KASC:RegisterMessage("TEST_ENABLED", { payload = true, enabled = function() return moduleOn end },
    function() hits[#hits + 1] = true end)
KASC.Dispatch("TEST_ENABLED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "a disabled handler does not run")
moduleOn = true
KASC.Dispatch("TEST_ENABLED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 1, "the same handler runs once enabled")

-- ctx ------------------------------------------------------------------------------------
local seen
KASC:RegisterMessage("TEST_CTX", { payload = true }, function(_, ctx) seen = ctx end)
KASC.Dispatch("TEST_CTX:x", "RAID", "Ann-TarrenMill")
T.eq(seen.sender, "Ann-TarrenMill", "ctx carries the full sender")
T.eq(seen.shortName, "Ann", "ctx carries the realm-free short name")
T.eq(seen.channel, "RAID", "ctx carries the channel")
T.eq(seen:Key(), "Player-1234-AAAA", "ctx:Key() resolves the sender")
T.eq(seen:Key(), "Player-1234-AAAA", "ctx:Key() is stable across calls")

-- Duplicate registration is a programming error, not a silent overwrite ---------------------
local ok = pcall(function()
    KASC:RegisterMessage("TEST_CTX", { payload = true }, function() end)
end)
T.eq(ok, false, "registering the same token twice raises")

-- Send ---------------------------------------------------------------------------------------
KARTTEST.ClearSent()
KASC:Send("HELLO")
T.eq(KARTTEST.sent[1].prefix, "KART", "Send uses the registered prefix")
T.eq(KARTTEST.sent[1].channel, "RAID", "Send defaults to RAID while in a raid")
KARTTEST.SetParty({ { name = "Ann", guid = "Player-1234-AAAA" } })
KARTTEST.ClearSent()
KASC:Send("HELLO")
T.eq(KARTTEST.sent[1].channel, "PARTY", "Send defaults to PARTY outside a raid")

-- The self gate ------------------------------------------------------------------------------
-- CHAT_MSG_ADDON fires on the SENDER too for every group and guild channel, so our own message
-- comes back looking exactly like a peer's. Every consumer already does its own side of the work
-- where it sends, so the echo has to die here -- see the comment on Dispatch. Ann is "player" in
-- the party set up just above.
hits = {}
KASC:RegisterMessage("TEST_ECHO", { payload = true }, function() hits[#hits + 1] = true end)
KASC.Dispatch("TEST_ECHO:x", "PARTY", "Ann-TarrenMill")
T.eq(#hits, 0, "our own message coming back is dropped")
KASC.Dispatch("TEST_ECHO:x", "PARTY", "Ann")
T.eq(#hits, 0, "the same, unqualified")
-- Name alone must not be the test: a stranger who happens to share our short name is a different
-- player, and silently swallowing their messages would be the same bug in the other direction.
KASC.Dispatch("TEST_ECHO:x", "WHISPER", "Ann-Silvermoon")
T.eq(#hits, 1, "our short name on another realm is somebody else, and still delivered")

-- Handshake ---------------------------------------------------------------------------------
-- Name, version and capability are restricted to [%w%.%-_]; anything else drops the entry.
-- This replaces the old ver:gsub("|","||") defence with a whitelist, because the version
-- string is printed to chat and rendered in the council panel.
local parsed = KASC.ParseHello("KART=3.0.0+LC")
T.eq(parsed.KART.version, "3.0.0", "a single addon entry parses")
T.truthy(parsed.KART.caps.LC, "a capability suffix parses")

parsed = KASC.ParseHello("KART=3.1.0,KALC=1.0.0+LC")
T.eq(parsed.KART.version, "3.1.0", "the first of two addon entries parses")
T.eq(parsed.KALC.version, "1.0.0", "the second of two addon entries parses")
T.truthy(parsed.KALC.caps.LC, "the capability attaches to the right addon")
T.is_nil(parsed.KART.caps.LC, "a capability does not leak onto the other addon")

parsed = KASC.ParseHello("KART=3.0.0")
T.eq(parsed.KART.version, "3.0.0", "an entry with no capability parses")

-- Hostile and malformed input ------------------------------------------------------------
T.is_nil(KASC.ParseHello("KART=|cff00ff00ffff").KART, "a colour escape in the version drops the entry")
T.is_nil(KASC.ParseHello("KART=3.0.0+|Hitem:1|h").KART, "an escape in a capability drops the entry")
T.is_nil(KASC.ParseHello("KART=3.0.0+").KART, "a trailing plus with no capability drops the entry")
T.is_nil(KASC.ParseHello("=3.0.0").KART, "an empty name drops the entry")
T.is_nil(KASC.ParseHello("KART=").KART, "an empty version drops the entry")
T.is_nil(KASC.ParseHello("KART=3.0.0=|cffff0000").KART, "a second = drops the entry instead of silently truncating the version")
T.is_nil(KASC.ParseHello("KART=1=2+LC").KART, "text before the first + must not be silently swallowed")
T.deep_eq(KASC.ParseHello(",,"), {}, "a payload of separators yields nothing")
T.deep_eq(KASC.ParseHello(""), {}, "an empty payload yields nothing")
T.deep_eq(KASC.ParseHello(nil), {}, "a nil payload yields nothing")

-- One bad entry must not take a good one with it -------------------------------------------
parsed = KASC.ParseHello("KART=3.0.0,BAD=|cff00ff00")
T.eq(parsed.KART.version, "3.0.0", "a good entry survives alongside a rejected one")
T.is_nil(parsed.BAD, "the rejected entry is absent")

-- Serialisation round-trips ------------------------------------------------------------------
KASC:RegisterAddon("TESTADDON", "9.9.9")
KASC:RegisterCapability("TESTADDON", "CAP", function() return true end)
local round = KASC.ParseHello(KASC.SerializeHello())
T.eq(round.TESTADDON.version, "9.9.9", "a registered addon round-trips through the wire format")
T.truthy(round.TESTADDON.caps.CAP, "an enabled capability round-trips")

-- A capability whose predicate is false must not appear -----------------------------------------
KASC:RegisterAddon("TESTOFF", "1.0.0")
KASC:RegisterCapability("TESTOFF", "OFFCAP", function() return false end)
round = KASC.ParseHello(KASC.SerializeHello())
T.eq(round.TESTOFF.version, "1.0.0", "an addon with no enabled capability still appears")
T.is_nil(round.TESTOFF.caps.OFFCAP, "a disabled capability is omitted")

-- The dispatcher wiring around the handshake -- not just the pure Serialize/Parse functions ----
KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })

KARTTEST.ClearSent()
KASC:RequestHello()
T.eq(KARTTEST.sent[1].msg, "KA_HELLO_REQ", "RequestHello broadcasts the request token")
T.eq(KARTTEST.sent[1].channel, "RAID", "RequestHello uses the default channel")
T.is_nil(KARTTEST.sent[1].target, "RequestHello is not targeted at anyone")

-- A non-whisper request is answered on the same channel it arrived on, broadcast to the group.
-- The expected payload is a LITERAL string, not KASC.SerializeHello() called again -- computing
-- the expectation from the function under test would pass for any output, including garbage.
-- Only TESTADDON (with its enabled CAP) and TESTOFF (with its disabled OFFCAP) have been
-- registered by this point, in that order, so this also pins SerializeHello's entry ordering,
-- which the earlier round-trip tests (going through a hash table) never verify.
KARTTEST.ClearSent()
KASC.Dispatch("KA_HELLO_REQ", "RAID", "Ann-TarrenMill")
-- The trailing ACK=1 marks this as an ANSWER rather than an unsolicited announcement, so a
-- consumer's version check prints a line only for clients that actually received its request
-- (B10). It rides in the normal entry grammar on purpose: a 3.0.x client parses it into a
-- peers.ACK nobody reads, where a new message token would have been invisible to it entirely.
T.eq(KARTTEST.sent[1].msg, "KA_HELLO:TESTADDON=9.9.9+CAP,TESTOFF=1.0.0,ACK=1",
    "a KA_HELLO_REQ is answered with the exact hello payload, in registration order, marked as a reply")
T.eq(KARTTEST.sent[1].channel, "RAID", "a non-whisper request is answered on the same channel")
T.is_nil(KARTTEST.sent[1].target, "a non-whisper reply is not targeted at anyone")

-- A whispered request is answered back to the whisperer specifically, not broadcast.
KARTTEST.ClearSent()
KASC.Dispatch("KA_HELLO_REQ", "WHISPER", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].channel, "WHISPER", "a whispered request is answered by whisper")
T.eq(KARTTEST.sent[1].target, "Ann-TarrenMill", "the whisper reply targets the requester")

-- Receiving a KA_HELLO fires every KASC:OnPeer callback with (shortName, fullName, parsed peers).
local peerCalls = {}
KASC:OnPeer(function(shortName, fullName, peers) peerCalls[#peerCalls + 1] = { shortName, fullName, peers } end)
KASC.Dispatch("KA_HELLO:HELLOTEST=1.2.3+X", "RAID", "Ann-TarrenMill")
T.eq(peerCalls[1][1], "Ann", "OnPeer receives the sender's short name")
T.eq(peerCalls[1][2], "Ann-TarrenMill", "OnPeer receives the sender's full realm-qualified name")
T.eq(peerCalls[1][3].HELLOTEST.version, "1.2.3", "OnPeer receives the parsed peer table, not the raw payload")

-- Solicited vs unsolicited, and that the marker never reaches a consumer -------------------------
-- OnPeer's fourth argument is what lets /kart v print a line only for clients that answered it.
local ackCalls = {}
KASC:OnPeer(function(shortName, _, peers, solicited)
    ackCalls[#ackCalls + 1] = { shortName = shortName, solicited = solicited, ack = peers.ACK, kart = peers.KART }
end)

KASC.Dispatch("KA_HELLO:KART=3.1.0,ACK=1", "RAID", "Ann-TarrenMill")
T.eq(ackCalls[1].solicited, true, "a hello carrying the ack marker is reported as a reply")
T.is_nil(ackCalls[1].ack, "the ack marker is stripped before consumers see the peer list")
T.eq(ackCalls[1].kart.version, "3.1.0", "the real addon entry survives alongside the marker")

KASC.Dispatch("KA_HELLO:KART=3.1.0", "RAID", "Ann-TarrenMill")
T.eq(ackCalls[2].solicited, false, "a hello without the marker is reported as an announcement")

-- An unsolicited announce must not record a different string than a reply does, or
-- AnnounceHelloIfChanged would fire a spurious extra announce after every version check.
KARTTEST.ClearSent()
KASC:AnnounceHello()
KASC:AnnounceHelloIfChanged()
T.eq(#KARTTEST.sent, 1, "an unchanged handshake is not announced twice")
KARTTEST.ClearSent()
KASC.Dispatch("KA_HELLO_REQ", "RAID", "Ann-TarrenMill")
KASC:AnnounceHelloIfChanged()
T.eq(#KARTTEST.sent, 1, "answering a request does not make the next announce look changed")
