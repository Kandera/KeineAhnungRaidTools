local _, KART = ...
local LC = KART.LC

-- =====================================================================
--  Vote-window relevance  (which items are worth showing to THIS player)
-- =====================================================================
-- Two personal settings decide what happens to an item the player's class cannot equip: hide it
-- (voting the last configured response, so the council is not left waiting on a vote that will
-- never come) and/or vote Transmog on it while its appearance is still missing. Blizzard's own
-- loot roll is not involved anywhere in this file.

LC.Relevance = LC.Relevance or {}

-- Pure decision core, deliberately free of any WoW API call so tests/test_lc_relevance.lua can
-- compile it standalone. facts.irrelevant and facts.needsAppearance are three-state: true, false,
-- or nil for "could not be determined".
--
-- nil must behave like "relevant" and like "appearance owned" -- never the other way round. Both
-- automatic answers are claims made on the player's behalf, and a wrong one is expensive: hiding
-- passes away an item they were eligible for, and voting Transmog puts their name on an item they
-- may already have the appearance of.
local function DecideAutoResponse(facts)
    if facts.irrelevant ~= true then return nil end
    if facts.autoTransmog and facts.needsAppearance == true then return "transmog" end
    if facts.hideIrrelevant then return "pass" end
    return nil
end

LC.Relevance.DecideAutoResponse = DecideAutoResponse
