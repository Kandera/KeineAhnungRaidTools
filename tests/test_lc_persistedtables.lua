-- The two lists that have to agree about what a roll consists of.
--
-- Trade.ClearRollState is the addon's own definition of "everything tracked under a rollID" -- it is
-- what runs when an item is finished with. LC.PERSISTED_ROLL_TABLES is what a reload carries across
-- (B81). The comment on the second one states the rule outright:
--
--     "Add to ClearRollState and this list wants the same entry."
--
-- Nothing checked it. A rule that lives only in a comment is kept until the first person who does
-- not read that comment, and the way it fails is quiet: the new table simply is not restored, so
-- after a /reload one aspect of an item on the table is blank while everything around it is right.
-- Nobody connects that to a line added weeks earlier.
--
-- Read out of the SOURCE rather than off the live tables, the same tool tests/test_core_wiring.lua
-- uses: what is under test is the two lists as WRITTEN, since a missing entry is invisible at
-- runtime -- LC[name] is simply nil and both the save and the restore skip it without a word.

local council = assert(io.open("LootCouncil.lua", "r")):read("*a")
local trade   = assert(io.open("LootCouncilTrade.lua", "r")):read("*a")

-- The persisted list, as a set.
local persistedBlock = council:match("local PERSISTED_ROLL_TABLES = {(.-)}")
T.truthy(persistedBlock, "PERSISTED_ROLL_TABLES was found in LootCouncil.lua")
local persisted = {}
for name in persistedBlock:gmatch('"([%w_]+)"') do persisted[name] = true end

-- Every LC.<table>[rollID] that ClearRollState clears.
local clearBody = trade:match("function Trade%.ClearRollState%(rollID%)(.-)\nend\n")
T.truthy(clearBody, "Trade.ClearRollState was found in LootCouncilTrade.lua")
local cleared = {}
for name in clearBody:gmatch("LC%.([%w_]+)%[rollID%]") do cleared[name] = true end

local count = 0
for _ in pairs(cleared) do count = count + 1 end
T.truthy(count > 10, "and it clears the per-roll tables this test is about (" .. count .. " found)")

-- The deliberate omissions, named here so leaving one out is a decision somebody makes in this file
-- rather than something that happens by forgetting a line.
--
-- Two are persisted by another route:
--   rollDeadlines -- stored separately, converted to wall clock (GetTime does not survive a logout)
--   rollLootedAt  -- already persisted, by KART_LCTrades, where the BoP clock belongs
--
-- Three are IN-FLIGHT MARKERS rather than state, and restoring them would do harm rather than
-- nothing -- a request that is no longer in flight would never be made again:
--   equipRequestedRolls -- "we already asked this raider for their gear". Nothing is in flight after
--                          a reload and the answers are gone, so carrying the flag across would
--                          leave the council panel's equipped column permanently empty.
--   rollsPendingSince   -- when a roll arrived that we had no item for, GetTime()-based, and read
--                          only to tell an early roll from an orphan. After a restore the item is
--                          back, so the roll is not pending at all.
--   pendingItemLoads    -- an item load waiting on the client. No callback survives a reload.
local EXEMPT = {
    rollDeadlines = true, rollLootedAt = true,
    equipRequestedRolls = true, rollsPendingSince = true, pendingItemLoads = true,
}

for name in pairs(cleared) do
    if not EXEMPT[name] then
        T.truthy(persisted[name],
            "LC." .. name .. " is cleared per roll, so a reload has to carry it too " ..
            "(add it to PERSISTED_ROLL_TABLES, or to this test's EXEMPT list with a reason)")
    end
end

-- ...and nothing in the persisted list that the addon does not actually keep per roll: a name that
-- no longer exists is saved as nothing and restored as nothing, and reads like coverage it is not.
for name in pairs(persisted) do
    T.truthy(cleared[name],
        "PERSISTED_ROLL_TABLES lists LC." .. name .. ", which ClearRollState does not clear -- " ..
        "either it is not per-roll state, or clearing it was forgotten")
end
