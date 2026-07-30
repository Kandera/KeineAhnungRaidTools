-- The vote-button list every raider's vote index is resolved against, and the separate rank the
-- council panel sorts by.
--
-- The offline harness loads libraries, not addon files -- LootCouncil.lua needs the addon's vararg
-- table and a live WoW to load at all. So this lifts the button helpers (and the colour/icon tables
-- they read) out of the source and compiles just those, the same way test_lc_votewire.lua does with
-- ParseVotePayload. Testing a copy pasted in here would pass forever after the real one changed,
-- which is worse than no test.
--
-- What makes this worth testing: **the index is a wire value and the rank is not.** The fixed
-- Transmog response was briefly moved in front of the last configured label so it would sort above
-- the people who passed. Both lists still had six entries, so the count guard in Vote.CastVote saw
-- nothing wrong, and for one raid evening every raider on the older build who pressed "Pass" was
-- displayed to the council as "Transmog". Position is now fixed and the ordering is a rank. These
-- assertions exist to keep those two apart.

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
    lift("\nlocal VOTE_ICON_TEXTURES = {.-\n}\n",               "VOTE_ICON_TEXTURES"),
    lift("\nfunction LC%.GetVoteIconTexture%(index, def%).-\nend\n", "GetVoteIconTexture"),
    lift("\nfunction LC%.GetButtonConfig%(%).-\nend\n",         "GetButtonConfig"),
    lift("\nfunction LC%.GetTransmogButtonIndex%(%).-\nend\n",  "GetTransmogButtonIndex"),
    lift("\nfunction LC%.GetVoteSortRank%(idx%).-\nend\n",      "GetVoteSortRank"),
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

local chunk = assert(loadstring(preamble .. lifted ..
    "\nreturn LC, KART_Settings, BUTTON_COLORS, TRANSMOG_ICON, VOTE_ICON_TEXTURES"))
local LC, KART_Settings, BUTTON_COLORS, TRANSMOG_ICON, VOTE_ICON_TEXTURES = chunk()
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
T.deep_eq(labelsOf(cfg), { "a", "b", "c", "d", "e", "Transmog" },
    "the sixth and seventh label are dropped, not the Transmog entry")

-- Transmog is always the LAST entry, and never the raid leader's to define ------------------------
KART_Settings.lcButtonLabels = "Need;Greed"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 3, "two configured labels yield two plus Transmog")
T.deep_eq(labelsOf(cfg), { "Need", "Greed", "Transmog" }, "Transmog is appended after the last label")
T.truthy(cfg[3].transmog, "the Transmog entry is flagged as such")
T.eq(cfg[3].icon, TRANSMOG_ICON, "the Transmog entry carries its own icon")
T.is_nil(cfg[1].transmog, "a configured label is never flagged as the Transmog response")
T.eq(LC.GetTransmogButtonIndex(), 3, "GetTransmogButtonIndex points at the last entry")
T.eq(LC.GetPassButtonIndex(), 2, "GetPassButtonIndex points at the last CONFIGURED label")

-- A raid leader cannot take the fixed entry over by naming a label after it.
KART_Settings.lcButtonLabels = "Transmog"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 2, "a label literally named Transmog does not replace the fixed entry")
T.is_nil(cfg[1].transmog, "the leader's own Transmog label stays a plain configured button")
T.truthy(cfg[2].transmog, "the fixed entry is still appended after it")

-- Pass and Transmog never collide -------------------------------------------------------------------
for n = 1, 6 do
    local parts = {}
    for i = 1, n do parts[i] = "L" .. i end
    KART_Settings.lcButtonLabels = table.concat(parts, ";")
    local pass, mog = LC.GetPassButtonIndex(), LC.GetTransmogButtonIndex()
    T.eq(mog, pass + 1, n .. " labels: Transmog is the entry after the last configured label")
    T.truthy(LC.GetButtonConfig()[mog].transmog, n .. " labels: the Transmog index is the fixed entry")
    T.is_nil(LC.GetButtonConfig()[pass].transmog, n .. " labels: the Pass index is a configured label")
end

-- The rank is a DIFFERENT question from the index ---------------------------------------------------
-- This is the separation the wire desync taught us. The index must stay put; the rank is free.
KART_Settings.lcButtonLabels = "BIS;Upgrade;Offspec;Other;Pass"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 6, "the default-shaped set is five labels plus Transmog")
T.eq(cfg[6].label, "Transmog", "Transmog holds the last index")
T.eq(cfg[5].label, "Pass", "and Pass keeps index 5, exactly where 3.2.0 put it")

T.truthy(LC.GetVoteSortRank(6) < LC.GetVoteSortRank(5),
    "Transmog nonetheless sorts ABOVE Pass on the council panel")
T.truthy(LC.GetVoteSortRank(4) < LC.GetVoteSortRank(6),
    "and below the last configured non-Pass response")
T.eq(LC.GetVoteSortRank(1), 1, "an ordinary index ranks as itself")
T.eq(LC.GetVoteSortRank(5), 5, "including the last configured label")
-- A vote from a client whose list is longer than ours must not collapse to the top.
T.eq(LC.GetVoteSortRank(9), 9, "an index beyond our own list keeps its raw value")
T.eq(LC.GetVoteSortRank(nil), math.huge, "an unusable index sorts last rather than first")

-- Icons travel with the entry, not with the final index ----------------------------------------------
T.eq(cfg[5].icon, VOTE_ICON_TEXTURES[5], "Pass carries the fifth icon")
T.eq(LC.GetVoteIconTexture(5, cfg[5]), VOTE_ICON_TEXTURES[5], "and the lookup honours it")
T.eq(LC.GetVoteIconTexture(6, cfg[6]), TRANSMOG_ICON, "while the Transmog entry keeps its own")

-- Empty and whitespace-only entries ------------------------------------------------------------------
-- Dropped entries must not advance the colour index either: a gap here would show one button wearing
-- another's colour.
KART_Settings.lcButtonLabels = "BIS;;   ;Upgrade"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Upgrade", "Transmog" }, "empty and whitespace-only labels are dropped")
T.eq(cfg[2].r, BUTTON_COLORS[2].r, "the surviving second label gets the second colour, not the fourth")
T.eq(cfg[2].g, BUTTON_COLORS[2].g, "the surviving second label gets the second colour, not the fourth (g)")
T.eq(LC.GetPassButtonIndex(), 2, "Pass follows the compacted list, not the raw split")

-- Nothing configurable left at all falls back to the defaults, so the raid always has a full set.
KART_Settings.lcButtonLabels = "  ;  ;"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Upgrade", "Offspec", "Other", "Pass", "Transmog" },
    "an all-whitespace field falls back to the default labels")
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
