-- The auto-response decision for an item in the vote window.
--
-- The offline harness loads libraries, not addon files -- LootCouncilRelevance.lua needs the addon's
-- vararg table to load at all. So this lifts DecideAutoResponse out of the source and compiles just
-- that function, the same way test_lc_votewire.lua does with ParseVotePayload. Testing a copy pasted
-- in here would pass forever after the real one changed, which is worse than no test.
--
-- What makes this worth testing: "not determinable" is a third state next to true and false, and it
-- must behave like "relevant" -- never like "irrelevant". Collapsing nil into false would silently
-- pass away items the player was eligible for.

local source = assert(io.open("LootCouncilRelevance.lua", "r"))
local text = source:read("*a")
source:close()

local fn = text:match("\nlocal function DecideAutoResponse%(facts%).-\nend\n")
T.truthy(fn, "DecideAutoResponse was found in LootCouncilRelevance.lua")

local chunk = assert(loadstring(fn .. "\nreturn DecideAutoResponse"))
local DecideAutoResponse = chunk()
T.eq(type(DecideAutoResponse), "function", "DecideAutoResponse compiles standalone")

local function check(label, facts, expected)
    T.eq(DecideAutoResponse(facts), expected, label)
end

-- Relevant items are never touched, whatever the switches say ------------------------------------
check("relevant, both off",   {irrelevant = false, needsAppearance = true,  hideIrrelevant = false, autoTransmog = false}, nil)
check("relevant, both on",    {irrelevant = false, needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  nil)
check("relevant, hide on",    {irrelevant = false, needsAppearance = false, hideIrrelevant = true,  autoTransmog = false}, nil)

-- Unknown relevance behaves exactly like relevant --------------------------------------------------
check("unknown, both on",     {irrelevant = nil,   needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  nil)
check("unknown, hide on",     {irrelevant = nil,   needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = false}, nil)

-- Irrelevant with both switches off is today's behaviour -------------------------------------------
check("irrelevant, both off", {irrelevant = true,  needsAppearance = true,  hideIrrelevant = false, autoTransmog = false}, nil)

-- Hiding alone --------------------------------------------------------------------------------------
check("hide, mog needed",     {irrelevant = true,  needsAppearance = true,  hideIrrelevant = true,  autoTransmog = false}, "pass")
check("hide, mog owned",      {irrelevant = true,  needsAppearance = false, hideIrrelevant = true,  autoTransmog = false}, "pass")
check("hide, mog unknown",    {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = false}, "pass")

-- Auto-transmog alone -------------------------------------------------------------------------------
check("mog on, needed",       {irrelevant = true,  needsAppearance = true,  hideIrrelevant = false, autoTransmog = true},  "transmog")
check("mog on, owned",        {irrelevant = true,  needsAppearance = false, hideIrrelevant = false, autoTransmog = true},  nil)
-- Unknown appearance must not vote: a wrong Transmog vote is a claim on an item, not just a hidden row.
check("mog on, unknown",      {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = false, autoTransmog = true},  nil)

-- Both switches: transmog wins when the appearance is missing, hiding takes over otherwise ----------
check("both, mog needed",     {irrelevant = true,  needsAppearance = true,  hideIrrelevant = true,  autoTransmog = true},  "transmog")
check("both, mog owned",      {irrelevant = true,  needsAppearance = false, hideIrrelevant = true,  autoTransmog = true},  "pass")
check("both, mog unknown",    {irrelevant = true,  needsAppearance = nil,   hideIrrelevant = true,  autoTransmog = true},  "pass")

-- ===================================================================================
-- The feature end to end, in a real raid (B36 onwards)
-- ===================================================================================
-- Everything above compiles one pure function out of the source. This half drives the whole path:
-- START_LOOT_ROLL fires on each client, LootCouncilRelevance.lua's own frame snapshots Blizzard's
-- verdict, and the vote-list refresh answers on the player's behalf.
--
-- None of this was reachable from the harness until RegisterEvent became real -- the snapshot frame
-- stored its handler and nothing ever called it, so 192 lines and ten backlog entries sat behind a
-- no-op stub.
local F = dofile("tests/lc_fixture.lua")

-- B36: "Blizzard says you may not Need this" is not "your class cannot equip this" ------------------
-- canNeed comes back false for a wrong loot specialization, a level requirement and a unique-equipped
-- item just as it does for armor your class can never wear -- one boolean for four questions, and
-- only the last of them is what this feature means. Reading it as "irrelevant" hid an off-spec
-- upgrade from the person who would have taken it (GitHub #11).
do
    local sim = F.NewRaid()
    local corvin = sim.byName.Corvin          -- PALADIN, hide-irrelevant ON
    -- Plate gloves, and Blizzard says no: on a Holy Paladin that is the loot specialization talking,
    -- not the armor class. Plate is exactly what a paladin wears.
    F.Drop(sim, 500, F.GLOVES, { canNeed = false })
    KARTTEST.AdvanceTime(1)

    T.truthy(not corvin.KART.LC.hiddenIrrelevant[500],
        "B36: plate is not hidden from a paladin just because Blizzard refused the Need roll")
    T.is_nil(corvin.KART.LC.votedByMe[500],
        "B36: and nothing was passed away on their behalf")
end

do
    -- ...and the case the feature IS for still works: the same plate on a priest.
    local sim = F.NewRaid()
    local sinja = sim.byName.Sinja            -- PRIEST, hide ON
    -- Transmog off for this drop, so the pass is what is being measured rather than a Transmog vote
    -- outranking it (see DecideAutoResponse).
    F.Drop(sim, 501, F.GLOVES, { canNeed = false, canTransmog = false })
    KARTTEST.AdvanceTime(1)

    T.truthy(sinja.KART.LC.hiddenIrrelevant[501], "B36: a priest still has plate hidden")
    T.eq(sinja.KART.LC.votedByMe[501], sinja.KART.LC.GetPassButtonIndex(),
        "B36: answered with the configured pass, so the council is not left waiting")
end

-- B39: "do I own this appearance" is not "can this character ever learn it" -------------------------
-- The fallback path -- an item with no Blizzard roll on this client, i.e. /kart add, or a client that
-- was dead when it dropped -- asked only whether the appearance was already collected. The sourceID
-- sitting right next to it was discarded and PlayerCanCollectSource never called. So it voted
-- Transmog on appearances this character can never learn, and the council awarded the item on the
-- strength of that vote.
do
    local sim = F.NewRaid()
    local alric = sim.byName.Alric            -- MAGE, auto-transmog ON, hide OFF
    -- Plate, so the armor check makes it irrelevant for a mage and the Transmog question is reached.
    -- An appearance that is NOT collected, and that this character can never collect.
    KARTTEST.appearances[F.GLOVES] = { appearance = 900, source = 901, collectible = false, owned = false }
    F.Drop(sim, 510, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    KARTTEST.appearances = {}

    T.is_nil(alric.KART.LC.votedByMe[510],
        "B39: no Transmog vote for an appearance this character can never learn")
end

do
    -- ...and one it CAN learn and does not have is still voted for, so the guard is not "never vote".
    local sim = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.appearances[F.GLOVES] = { appearance = 900, source = 902, collectible = true, owned = false }
    F.Drop(sim, 511, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    KARTTEST.appearances = {}

    T.eq(alric.KART.LC.votedByMe[511], alric.KART.LC.GetTransmogButtonIndex(),
        "B39: an appearance this character still needs is voted Transmog")
end
