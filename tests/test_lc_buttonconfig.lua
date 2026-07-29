-- The vote-button list every raider's vote index is resolved against.
--
-- The offline harness loads libraries, not addon files -- LootCouncil.lua needs the addon's vararg
-- table and a live WoW to load at all. So this lifts the button helpers (and the colour/icon tables
-- they read) out of the source and compiles just those, the same way test_lc_votewire.lua does with
-- ParseVotePayload. Testing a copy pasted in here would pass forever after the real one changed,
-- which is worse than no test.
--
-- What makes this worth testing: the INDEX these functions return is what goes over the wire to the
-- whole raid, AND it is the order the council panel sorts candidates by. The fixed Transmog response
-- sits second to last, a position that moves with the number of configured labels -- it shipped as
-- "last" in 3.2.0 and had to move, because appended after Pass it sorted every Transmog voter below
-- the people who wanted nothing. An off-by-one here makes every automatic vote announce the wrong
-- label to every council member, and the whitespace-label compaction is exactly the kind of place
-- one hides.

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
T.deep_eq(labelsOf(cfg), { "a", "b", "c", "d", "Transmog", "e" },
    "the sixth and seventh label are dropped, and Transmog slots in front of the last survivor")

-- Transmog sits second to last, and is never the raid leader's to define ---------------------------
KART_Settings.lcButtonLabels = "Need;Greed"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 3, "two configured labels yield two plus Transmog")
T.deep_eq(labelsOf(cfg), { "Need", "Transmog", "Greed" }, "Transmog goes in front of the last label")
T.truthy(cfg[2].transmog, "the Transmog entry is flagged as such")
T.eq(cfg[2].icon, TRANSMOG_ICON, "the Transmog entry carries its own icon, since its index moves")
T.is_nil(cfg[1].transmog, "a configured label is never flagged as the Transmog response")
T.eq(LC.GetTransmogButtonIndex(), 2, "GetTransmogButtonIndex points at the second-to-last entry")
T.eq(LC.GetPassButtonIndex(), 3, "GetPassButtonIndex points at the last entry")

-- A raid leader cannot take the fixed entry over by naming a label after it.
KART_Settings.lcButtonLabels = "Transmog"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 2, "a label literally named Transmog does not replace the fixed entry")
T.truthy(cfg[1].transmog, "the fixed entry still goes in front of the single configured label")
T.is_nil(cfg[2].transmog, "the leader's own Transmog label stays a plain configured button")

-- Pass and Transmog never collide -------------------------------------------------------------------
for n = 1, 6 do
    local parts = {}
    for i = 1, n do parts[i] = "L" .. i end
    KART_Settings.lcButtonLabels = table.concat(parts, ";")
    local pass, mog = LC.GetPassButtonIndex(), LC.GetTransmogButtonIndex()
    T.eq(mog, pass - 1, n .. " labels: Transmog is the entry before Pass")
    T.truthy(LC.GetButtonConfig()[mog].transmog, n .. " labels: the Transmog index really is the fixed entry")
    if n > 1 then
        T.is_nil(LC.GetButtonConfig()[pass].transmog, n .. " labels: the Pass index is a configured label")
    end
end

-- Icons travel with the entry, not with the final index ----------------------------------------------
-- Transmog's insertion pushes the last configured label one place along. Looked up by final index it
-- would fall off the end of VOTE_ICON_TEXTURES and lose its own chip for the neutral catch-all.
KART_Settings.lcButtonLabels = "BIS;Upgrade;Offspec;Other;Pass"
cfg = LC.GetButtonConfig()
T.eq(#cfg, 6, "the full default-shaped set is five labels plus Transmog")
T.eq(cfg[6].label, "Pass", "Pass ends up at index 6")
T.eq(cfg[6].icon, VOTE_ICON_TEXTURES[5], "Pass keeps the fifth icon after being shifted to index 6")
T.eq(LC.GetVoteIconTexture(6, cfg[6]), VOTE_ICON_TEXTURES[5], "and the icon lookup honours it")
T.eq(LC.GetVoteIconTexture(5, cfg[5]), TRANSMOG_ICON, "while the Transmog entry keeps its own")

-- Empty and whitespace-only entries ------------------------------------------------------------------
-- Dropped entries must not advance the colour index either: a gap here would show one button wearing
-- another's colour.
KART_Settings.lcButtonLabels = "BIS;;   ;Upgrade"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Transmog", "Upgrade" }, "empty and whitespace-only labels are dropped")
T.eq(cfg[3].r, BUTTON_COLORS[2].r, "the surviving second label keeps the second colour, not the fourth")
T.eq(cfg[3].g, BUTTON_COLORS[2].g, "the surviving second label keeps the second colour, not the fourth (g)")
T.eq(LC.GetPassButtonIndex(), 3, "Pass follows the compacted list, not the raw split")

-- Nothing configurable left at all falls back to the defaults, so the raid always has a full set.
KART_Settings.lcButtonLabels = "  ;  ;"
cfg = LC.GetButtonConfig()
T.deep_eq(labelsOf(cfg), { "BIS", "Upgrade", "Offspec", "Other", "Transmog", "Pass" },
    "an all-whitespace field falls back to the default labels")
T.eq(LC.GetPassButtonIndex(), 6, "the default set votes Pass with the last index")

-- Where the labels come from ---------------------------------------------------------------------------
-- The config owner uses their own field; everyone else uses the synced one, and falls back to their
-- own only while nothing has been synced yet.
LC.isOwner = false
LC.raidConfig.buttonLabels = "R1;R2;R3"
KART_Settings.lcButtonLabels = "mine1;mine2"
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "R1", "R2", "Transmog", "R3" }, "a non-owner uses the synced labels")
LC.raidConfig.buttonLabels = ""
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "mine1", "Transmog", "mine2" }, "an unsynced non-owner falls back to their own labels")
LC.isOwner = true
LC.raidConfig.buttonLabels = "R1;R2;R3"
T.deep_eq(labelsOf(LC.GetButtonConfig()), { "mine1", "Transmog", "mine2" }, "the config owner always uses their own labels")
