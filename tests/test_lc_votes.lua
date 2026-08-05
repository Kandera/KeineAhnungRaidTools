-- The vote heartbeat: a vote repeats itself until the council has it.
--
-- The measurement behind this (B118, raid of 2026-08-03): four raiders pressed a button, their own
-- clients said "Voted: ...", and the council panel showed "-" for all four. One message, sent once,
-- with nothing that noticed it had not arrived.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop = F.NewRaid, F.Drop

-- RaidSim.Sent matches on the prefix, so "LC_VOTE" also catches every LC_VOTES heartbeat -- the same
-- trap the old vote-request token had in test_lc_churn.lua. Counting either one needs the exact token.
local function CountExact(sim, token)
    local n = 0
    for _, e in ipairs(RaidSim.Sent(sim, token)) do
        if e.msg:match("^" .. token .. ":") then n = n + 1 end
    end
    return n
end

-- One client, several items, one message -----------------------------------------------------------
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 80, F.GLOVES)
    Drop(sim, 81, F.WEAPON)
    Drop(sim, 82, F.PLATE_CHEST)
    KARTTEST.AdvanceTime(1)

    RaidSim.As(raider, function()
        raider.KART.LC.Vote.CastVote(80, 1)
        raider.KART.LC.Vote.CastVote(81, 2)
        raider.KART.LC.Vote.CastVote(82, 1)
    end)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(6)

    -- raider is Alric (F.NewRaid returns sim, lootmaster, council, raider), and this counts only
    -- what THEY sent -- everybody else in the fixture is voting too.
    local mine = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_VOTES")) do
        if e.from == raider.name then mine = mine + 1 end
    end
    T.eq(mine, 1, "three items are one heartbeat, not three")
end

-- The repair itself: the single vote is lost, the heartbeat brings it ------------------------------
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 83, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    RaidSim.Blackhole(sim, "LC_VOTE:")
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(83, 2) end)
    KARTTEST.AdvanceTime(1)
    T.is_nil((council.KART.LC.votes[83] or {})[raider.guid],
        "the one-shot vote is gone and the council has nothing")

    KARTTEST.AdvanceTime(6)
    local seen = (council.KART.LC.votes[83] or {})[raider.guid]
    T.truthy(seen, "the heartbeat delivers what the single message lost")
    T.eq(seen and seen.idx, 2, "with the answer they actually gave")
end

-- Nothing is deleted by silence -------------------------------------------------------------------
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 84, F.GLOVES)
    Drop(sim, 85, F.WEAPON)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(84, 1) end)
    KARTTEST.AdvanceTime(6)
    T.truthy((council.KART.LC.votes[84] or {})[raider.guid], "the council holds the vote for 84")

    -- A heartbeat that names 85 and says nothing about 84 -- which is what a client that has already
    -- pruned 84 sends. The vote for 84 must survive it.
    RaidSim.As(raider, function()
        raider.KART.LC.SendLC("LC_VOTES:85:1:#6:@249293:0:")
    end)
    KARTTEST.AdvanceTime(1)
    T.truthy((council.KART.LC.votes[84] or {})[raider.guid],
        "a roll the message does not mention keeps the vote it already had")
    T.truthy((council.KART.LC.votes[85] or {})[raider.guid], "and the one it does mention arrives")
end

-- The ticker stops when there is nothing left to say -----------------------------------------------
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 86, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(86, 1) end)
    -- Past the vote window and the prune sweep that follows it, so this raider tracks nothing.
    KARTTEST.AdvanceTime(30)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(20)
    T.eq(CountExact(sim, "LC_VOTES"), 0, "a client with no votes left is silent")
end

-- The other direction: not the voter is deaf, the council is ---------------------------------------
-- Both halves of the wire lose messages, and only one of them was ever repairable before: the old
-- vote-request came from the loot owner, so a council member who missed a vote had to hope the OWNER
-- noticed. A repeat does not care which end dropped it.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 87, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    RaidSim.Blackhole(sim, "LC_VOTE:")
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(87, 3) end)
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_VOTE:")

    KARTTEST.AdvanceTime(6)
    T.eq(((council.KART.LC.votes[87] or {})[raider.guid] or {}).idx, 3,
        "the repeat repairs whichever end lost the first message")
end

-- A note with the separator in it survives the round trip -------------------------------------------
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 88, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local note = "trade um 5:30; sonst mainspec"
    RaidSim.As(raider, function()
        local box = { GetText = function() return note end }
        raider.KART.LC.Vote.CastVote(88, 1, box)
    end)
    KARTTEST.AdvanceTime(6)

    T.eq(((council.KART.LC.votes[88] or {})[raider.guid] or {}).note, note,
        "a note carrying the entry separator arrives whole")
end

-- A stranger's heartbeat is not a vote --------------------------------------------------------------
do
    local sim, _, council = NewRaid()
    Drop(sim, 89, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local before = council.KART.LC.diag.refusedSender
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes("89:1:#6:@249331:0:", "Player-9999-DEADBEEF")
    end)
    T.is_nil((council.KART.LC.votes[89] or {})["Player-9999-DEADBEEF"],
        "a key that is in no group does not land in the tally")
    T.eq(council.KART.LC.diag.refusedSender, before + 1, "and is counted once for the message")
end

-- An unreadable packed block says nothing, rather than half of something ---------------------------
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 90, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local before = council.KART.LC.diag.packedUnreadable
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes("P:not a deflate block at all", raider.guid)
    end)
    T.eq(council.KART.LC.diag.packedUnreadable, before + 1,
        "a block that will not come back is counted, not stored")
    T.is_nil((council.KART.LC.votes[90] or {})[raider.guid], "and nothing is written from it")
end
