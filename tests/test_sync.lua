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
