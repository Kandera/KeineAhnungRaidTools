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
