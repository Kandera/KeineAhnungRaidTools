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
-- Five are IN-FLIGHT MARKERS rather than state, and restoring them would do harm rather than
-- nothing -- a request that is no longer in flight would never be made again:
--   equipRequestedRolls -- "we already asked this raider for their gear". Nothing is in flight after
--                          a reload and the answers are gone, so carrying the flag across would
--                          leave the council panel's equipped column permanently empty.
--   rollsPendingSince   -- when a roll arrived that we had no item for, GetTime()-based, and read
--                          only to tell an early roll from an orphan. After a restore the item is
--                          back, so the roll is not pending at all.
--   pendingItemLoads    -- an item load waiting on the client. No callback survives a reload.
--   rollReqSent         -- "we already asked the owner about this roll", a timestamp read only to
--                          stop a burst of heartbeats turning into a burst of requests (B118).
--                          GetTime()-based, so it does not survive a logout in any meaningful form,
--                          and a restored client SHOULD ask again -- that is the whole point of it.
--   rollsAnswerAt       -- "an answer of ours to an LC_ROLLS_REQ is scheduled" (B131). The timer it
--                          belongs to is gone after a reload, so restoring the flag would leave this
--                          client permanently declining to answer a request it never answers.
--   rollUndecidedWarned -- "we have already said this undecided item is running out of trade time"
--                          (see WarnUndecided). A reload does not make the deadline less real, and
--                          the item is still on the table: saying it once more is the right side to
--                          be wrong on, while a restored flag would silence the one warning that
--                          exists for an item nobody has decided.
local EXEMPT = {
    rollDeadlines = true, rollLootedAt = true,
    equipRequestedRolls = true, rollsPendingSince = true, pendingItemLoads = true,
    rollReqSent = true, rollsAnswerAt = true, rollUndecidedWarned = true,
}

for name in pairs(cleared) do
    if not EXEMPT[name] then
        T.truthy(persisted[name],
            "LC." .. name .. " is cleared per roll, so a reload has to carry it too " ..
            "(add it to PERSISTED_ROLL_TABLES, or to this test's EXEMPT list with a reason)")
    end
end

-- The other direction, and its own deliberate omission. LC.rollRaidSnapshot is neither cleared with
-- the roll nor carried by the session snapshot, and both halves are on purpose: it is read by the
-- AWARD, which on a plain raider lands long after Vote.PruneExpiredRolls freed the roll at the vote
-- deadline, so by then it is on neither of the lists LC.SaveSessionSnapshot writes for and the
-- on-screen rule would drop exactly the entry still needed (B150). It lives in KART_LCTrades instead,
-- for every rollID and bounded by age -- the same arrangement rollLootedAt has, and the reason both
-- are exempt above. Named here so putting either the clear or the session entry back is a decision
-- somebody makes in this file rather than a line that looks like it was forgotten.
local PERSISTED_ELSEWHERE = { rollRaidSnapshot = true, rollLootedAt = true }

for name in pairs(PERSISTED_ELSEWHERE) do
    T.eq(persisted[name], nil,
        "LC." .. name .. " must NOT be in PERSISTED_ROLL_TABLES -- the award that reads it arrives " ..
        "after the roll has left every list that block saves for (B150); KART_LCTrades keeps it")
    T.truthy(trade:find("LC%." .. name .. "%s*=%s*[%w_]") ~= nil,
        "...and Trade.RestorePersistedTrades points LC." .. name .. " at the saved table, so every " ..
        "later write persists on its own")
end

-- ...and nothing in the persisted list that the addon does not actually keep per roll: a name that
-- no longer exists is saved as nothing and restored as nothing, and reads like coverage it is not.
for name in pairs(persisted) do
    T.truthy(cleared[name],
        "PERSISTED_ROLL_TABLES lists LC." .. name .. ", which ClearRollState does not clear -- " ..
        "either it is not per-roll state, or clearing it was forgotten")
end
