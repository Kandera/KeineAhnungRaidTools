-- The vote-button list every raider's vote index is resolved against.
--
-- The offline harness loads libraries, not addon files -- LootCouncil.lua needs the addon's vararg
-- table and a live WoW to load at all. So this lifts the three button helpers (and the two colour/
-- icon tables they read) out of the source and compiles just those, the same way
-- test_lc_votewire.lua does with ParseVotePayload. Testing a copy pasted in here would pass forever
-- after the real one changed, which is worse than no test.
--
-- What makes this worth testing: the INDEX these functions return is what goes over the wire to the
-- whole raid, and the fixed Transmog response sits at a position that moves with the number of
-- configured labels. An off-by-one here makes every automatic vote announce the wrong label to every
-- council member -- worse than anything the relevance decision itself can get wrong -- and the
-- whitespace-label compaction inside GetButtonConfig is exactly the kind of place one hides.

local source = assert(io.open("LootCouncil.lua", "r"))
local text = source:read("*a")
source:close()

local function lift(pattern, what)
    local snippet = text:match(pattern)
    T.truthy(snippet, what .. " was found in LootCouncil.lua")
    return snippet or ""
end

local lifted = table.concat({
    lift("\nlocal BUTTON_COLORS = {.-\n}\n",                    "BUTTON_COLORS"),
    lift("\nlocal TRANSMOG_COLOR%s*=[^\n]+\n",                  "TRANSMOG_COLOR"),
    lift("\nlocal TRANSMOG_ICON%s*=[^\n]+\n",                   "TRANSMOG_ICON"),
    lift("\nfunction LC%.GetButtonConfig%(%).-\nend\n",         "GetButtonConfig"),
    lift("\nfunction LC%.GetTransmogButtonIndex%(%).-\nend\n",  "GetTransmogButtonIndex"),
    lift("\nfunction LC%.GetPassButtonIndex%(%).-\nend\n",      "GetPassButtonIndex"),
})

-- Everything the lifted code reaches for, as upvalues of the same chunk: the real KAUtil (splitting
-- and trimming is what the compaction below is made of, so stubbing it would test nothing), and
-- plain tables for the addon state. Locale values are placeholders -- these functions never inspect
-- label text, which is the whole reason a renamed last button votes Pass anyway.
local preamble = [[
local KAUtil = LibStub("KAUtil-1.0")
local KART = { L = {
    LC_DEFAULT_BUTTONS = "BIS;Upgrade;Offspec;Other;Pass",
    LC_BUTTON_TRANSMOG = "Transmog",
} }
local KART_Settings = {}
local LC = { raidConfig = {}, isOwner = true }
function LC.IsConfigOwner() return LC.isOwner end
]]

local chunk = assert(loadstring(preamble .. lifted .. "\nreturn LC, KART_Settings, BUTTON_COLORS, TRANSMOG_ICON"))
local LC, KART_Settings, BUTTON_COLORS, TRANSMOG_ICON = chunk()
T.eq(type(LC.GetButtonConfig), "function", "GetButtonConfig compiles standalone")

local function labelsOf(cfg)
    local out = {}
    for i, def in ipairs(cfg) do out[i] = def.label end
    return out
end

-- The 5-label cap ---------------------------------------------------------------------------------
KART_Settings.lcButtonLabels = "a;b;c;d;e;f;g"
local cfg = LC.GetButtonConfig()
T.eq(#cfg, 6, "seven configured labels yield five plus Transmog")
T.deep_eq(labelsOf(cfg), { "a", "b", "c", "d", "e", "Transmog" }, "the sixth and seventh label are dropped, not the Transmog entry")

-- Transmog is always last, always fixed --------------------------------------------------------------
KART_Settings.lcButtonLabels = "Need;Greed"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 3, "two configured labels yield two plus Transmog")
T.eq(cfg[#cfg].label, "Transmog", "Transmog is the last entry, not entry 6")
T.truthy(cfg[#cfg].transmog, "the Transmog entry is flagged as such")
T.eq(cfg[#cfg].icon, TRANSMOG_ICON, "the Transmog entry carries its own icon, since its index moves")
T.is_nil(cfg[1].transmog, "a configured label is never flagged as the Transmog response")
T.eq(LC.GetTransmogButtonIndex(), 3, "GetTransmogButtonIndex points at the last entry")

-- A raid leader cannot take the fixed entry over by naming a label after it.
KART_Settings.lcButtonLabels = "Transmog"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 2, "a label literally named Transmog does not replace the fixed entry")
T.is_nil(cfg[1].transmog, "the leader's own Transmog label stays a plain configured button")
T.truthy(cfg[2].transmog, "the fixed entry is still appended after it")

-- Pass never lands on the Transmog index ------------------------------------------------------------
for n = 1, 6 do
    local parts = {}
    for i = 1, n do parts[i] = "L" .. i end
    KART_Settings.lcButtonLabels = table.concat(parts, ";")
    local pass, mog = LC.GetPassButtonIndex(), LC.GetTransmogButtonIndex()
    T.eq(pass, mog - 1, n .. " labels: Pass is the entry before Transmog")
    T.is_nil(LC.GetButtonConfig()[pass].transmog, n .. " labels: the Pass index is a configured label")
end

-- Empty and whitespace-only entries ------------------------------------------------------------------
-- Dropped entries must not advance the colour index either: the vote icon is picked by the returned
-- entry's position, so a gap here would show one button wearing another's colour.
KART_Settings.lcButtonLabels = "BIS;;   ;Upgrade"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Upgrade", "Transmog" }, "empty and whitespace-only labels are dropped")
T.eq(cfg[2].r, BUTTON_COLORS[2].r, "the surviving second label gets the second colour, not the fourth")
T.eq(cfg[2].g, BUTTON_COLORS[2].g, "the surviving second label gets the second colour, not the fourth (g)")
T.eq(LC.GetPassButtonIndex(), 2, "Pass follows the compacted list, not the raw split")

-- Nothing configurable left at all falls back to the defaults, so the raid always has a full set.
KART_Settings.lcButtonLabels = "  ;  ;"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Upgrade", "Offspec", "Other", "Pass", "Transmog" }, "an all-whitespace field falls back to the default labels")
T.eq(LC.GetPassButtonIndex(), 5, "the default set votes Pass with index 5")

-- Where the labels come from ---------------------------------------------------------------------------
-- The config owner uses their own field; everyone else uses the synced one, and falls back to their
-- own only while nothing has been synced yet.
LC.isOwner = false
LC.raidConfig.buttonLabels = "R1;R2;R3"
KART_Settings.lcButtonLabels = "mine1;mine2"
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "R1", "R2", "R3", "Transmog" }, "a non-owner uses the synced labels")
LC.raidConfig.buttonLabels = ""
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "mine1", "mine2", "Transmog" }, "an unsynced non-owner falls back to their own labels")
LC.isOwner = true
LC.raidConfig.buttonLabels = "R1;R2;R3"
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "mine1", "mine2", "Transmog" }, "the config owner always uses their own labels")
