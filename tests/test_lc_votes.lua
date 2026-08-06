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

    -- A note is rendered raw into the council row's tooltip, and a sender that did not strip its own
    -- pipes is exactly what a hostile client looks like -- so the receiver doubles them, the way
    -- Vote.HandleVote does for the single message. Reachable only from a hand-written LC_VOTES,
    -- because Vote.CastVote strips the pipes at the sending end.
    local escape = "|cffff0000mine"
    RaidSim.As(raider, function()
        raider.KART.LC.SendLC("LC_VOTES:85:2:#6:@249293:" .. #escape .. ":" .. escape)
    end)
    KARTTEST.AdvanceTime(1)
    T.eq(((council.KART.LC.votes[85] or {})[raider.guid] or {}).note, "||cffff0000mine",
        "a pipe in a note arrives doubled, so it cannot colour anybody's tooltip")
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

    -- The immediate click message has to be gone, or it satisfies the assertion on its own and this
    -- test never exercises the length-prefix encoder it is here for -- the only test that does.
    RaidSim.Blackhole(sim, "LC_VOTE:")

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

-- One heartbeat is one redraw ----------------------------------------------------------------------
-- LC.RefreshCouncilIfShown rebuilds every tab whatever rollID it is handed, so calling it per entry
-- multiplied the cost by however many items the sender was carrying: twenty senders times twelve
-- entries every five seconds, each one walking all tabs with item-colour and icon lookups.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 93, F.GLOVES)
    Drop(sim, 94, F.WEAPON)
    Drop(sim, 95, F.PLATE_CHEST)
    KARTTEST.AdvanceTime(1)

    local calls, orig = 0, council.KART.LC.RefreshCouncilIfShown
    council.KART.LC.RefreshCouncilIfShown = function(...) calls = calls + 1 return orig(...) end
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes(
            "93:1:#6:@249331:0:;94:2:#6:@249293:0:;95:1:#6:@249405:0:", raider.guid)
    end)
    council.KART.LC.RefreshCouncilIfShown = orig

    T.eq(calls, 1, "three votes in one message are one redraw, not three")
    T.truthy((council.KART.LC.votes[95] or {})[raider.guid], "and every vote in it is still stored")
end

-- A message that says nothing is not a redraw ------------------------------------------------------
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 96, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local calls, orig = 0, council.KART.LC.RefreshCouncilIfShown
    council.KART.LC.RefreshCouncilIfShown = function(...) calls = calls + 1 return orig(...) end
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes("777:1:#6:@249331:0:", raider.guid)
    end)
    council.KART.LC.RefreshCouncilIfShown = orig

    T.eq(calls, 0, "a heartbeat that wrote nothing redraws nothing")
end

-- The receiver has a cap of its own ----------------------------------------------------------------
-- The sender caps at twelve entries, but AceComm reassembles a message of any length and an older or
-- modified sender is not bound by our cap. Same shape as LC.HandleDrop: stop at the bound, count it.
do
    local sim, _, council, raider = NewRaid()
    for rollID = 100, 113 do Drop(sim, rollID, F.GLOVES) end
    KARTTEST.AdvanceTime(1)

    local parts = {}
    for rollID = 100, 113 do parts[#parts + 1] = rollID .. ":1:#6:@249331:0:" end
    local before = council.KART.LC.diag.voteBatchCapped
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes(table.concat(parts, ";"), raider.guid)
    end)

    T.truthy((council.KART.LC.votes[111] or {})[raider.guid], "the twelfth entry is read")
    T.is_nil((council.KART.LC.votes[112] or {})[raider.guid], "the thirteenth is not")
    T.eq(council.KART.LC.diag.voteBatchCapped, before + 1,
        "and the cap is counted once for the message, not silently swallowed")
end

-- A heartbeat about rolls we no longer track is one refusal ----------------------------------------
-- Clients prune at slightly different instants, so a heartbeat landing in that gap is ordinary. Its
-- entries are one client's one statement; counting them one by one made a single message read as a
-- flood on the very instrument this was diagnosed with.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 114, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local before = council.KART.LC.diag.unknownRoll
    RaidSim.As(council, function()
        council.KART.LC.Vote.HandleVotes(
            "801:1:#6:@249331:0:;802:2:#6:@249293:0:;803:1:#6:@249405:0:", raider.guid)
    end)
    T.eq(council.KART.LC.diag.unknownRoll, before + 1,
        "three pruned rolls in one message are one refusal")
end

-- A reloaded voter keeps repeating -----------------------------------------------------------------
-- The one case the retired vote-request covered for free: it answered out of restored state and
-- needed no local timer. A reload leaves the votes and the rolls on disk but every ticker in memory,
-- and this guild's raiders reload mid-distribution as a matter of course.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 91, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(91, 2) end)
    KARTTEST.AdvanceTime(6)
    T.truthy((council.KART.LC.votes[91] or {})[raider.guid], "the council heard the vote once")

    -- The council forgets it -- which is the state the whole repeat exists to repair, and after the
    -- reload the voter is the only client left that can state it.
    council.KART.LC.votes[91] = nil

    local reloaded = RaidSim.Reload(sim, "Alric")
    RaidSim.RosterUpdate(sim)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(10)

    T.truthy(reloaded.KART.LC.votes[91], "the reloaded client still holds its own vote")
    T.eq(((council.KART.LC.votes[91] or {})[reloaded.guid] or {}).idx, 2,
        "and repeats it, so the council gets it back after the reload")
end

-- A tick with nothing to say is not the end of the heartbeat ---------------------------------------
-- During a loading screen UnitGUID("player") is nil, KASC.Identity.ResolvePlayer answers the literal
-- unit token, and this client finds no votes under that key. The votes are still live; only the
-- lookup is momentarily blind. Cancelling on that loses every repeat for the rest of the round.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 92, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(92, 3) end)
    KARTTEST.AdvanceTime(6)

    -- The blind moment, long enough to swallow a whole tick.
    KARTTEST.guidBlackout["player"] = true
    KARTTEST.AdvanceTime(6)
    KARTTEST.guidBlackout["player"] = nil

    council.KART.LC.votes[92] = nil
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(6)
    T.eq(((council.KART.LC.votes[92] or {})[raider.guid] or {}).idx, 3,
        "the heartbeat is still running once the client can see itself again")
end

-- How many LC_ROLL_REQ one client sent. The escalation (LC_ROLLS_REQ) is a different token and a
-- different decision, so it is deliberately not folded in here -- RaidSim.Sent matches on the
-- prefix and "LC_ROLL_REQ" does not match "LC_ROLLS_REQ".
local function AsksFrom(sim, client)
    local n = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == client.name then n = n + 1 end
    end
    return n
end

-- A vote naming a roll we do not have is a reason to ask for it ------------------------------------
-- The wire already says "you are missing something" every five seconds; before this only the owner's
-- table heartbeat was heard saying it, and that repeats at most every thirty (TABLE_RESEND_SECONDS).
-- A client whose LC_DROP was lost -- the loss B135 measured, where six clients held six different
-- subsets of one boss's rolls -- therefore sat blind for up to half a minute with the evidence
-- arriving six times over.
--
-- The heartbeat is blackholed for the whole test, so it cannot be the thing that repairs this: the
-- only message that ever names roll 120 to this client is another raider's vote.
do
    local sim, _, council, raider = NewRaid()

    RaidSim.Blackhole(sim, "LC_TABLE")
    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 120, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    T.eq(raider.KART.LC.rollItems[120], nil, "the deaf raider knows nothing of the drop")

    RaidSim.ClearLog(sim)
    RaidSim.As(council, function()
        council.KART.LC.SendLC("LC_VOTES:120:1:#6:@" .. F.GLOVES .. ":0:")
    end)
    KARTTEST.AdvanceTime(2)

    T.truthy(AsksFrom(sim, raider) >= 1, "a vote about a roll it does not track makes it ask the owner")
    T.truthy(raider.KART.LC.rollItems[120] ~= nil,
        "and the item is handed over well inside the heartbeat's thirty seconds")
    T.truthy(raider.KART.LC.rollDeadlines[120] ~= nil, "with a window to answer in")
end

-- ...but a client that WATCHED the roll expire still does not ask (B135) ----------------------------
-- Votes about a pruned roll arrive late by design -- clients prune at slightly different instants and
-- a council member keeps its tab long after the window closed -- so the untracked-vote drop is
-- ORDINARY traffic on an expired client. Asking on it would rebuild the 1,578-message queue through a
-- new door, five seconds at a time instead of thirty.
do
    local sim, _, council, raider = NewRaid()

    Drop(sim, 121, F.GLOVES)
    KARTTEST.AdvanceTime(23) -- past the default 20s window: the plain raider frees the roll
    T.eq(raider.KART.LC.rollItems[121], nil, "the raider watched the window close and freed the roll")
    T.truthy(raider.KART.LC.rollExpiredHere[121] ~= nil, "and holds the note that says so")

    RaidSim.ClearLog(sim)
    RaidSim.As(council, function()
        council.KART.LC.SendLC("LC_VOTES:121:1:#6:@" .. F.GLOVES .. ":0:")
    end)
    KARTTEST.AdvanceTime(2)

    T.eq(AsksFrom(sim, raider), 0, "a late vote is not a reason to fetch back what it watched close")
    T.eq(raider.KART.LC.rollItems[121], nil, "and the freed roll stays freed")
end

-- ...and neither does a client that threw the roll away itself (B123/B131) --------------------------
-- The other gate the heartbeat's ask already respects. A council member closes its tab after awarding
-- -- the ordinary end-of-item gesture -- while the rest of the raid is still voting and still saying
-- so every five seconds. Asking on that put the tab back on screen every thirty seconds; asking on
-- the votes would put it back every five.
do
    local sim = NewRaid()
    local council, peer = sim.byName.Merrit, sim.byName.Corvin

    Drop(sim, 122, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(122) end)
    T.eq(council.KART.LC.rollItems[122], nil, "closing the tab takes the item off that client")

    RaidSim.ClearLog(sim)
    RaidSim.As(peer, function()
        peer.KART.LC.SendLC("LC_VOTES:122:1:#6:@" .. F.GLOVES .. ":0:")
    end)
    KARTTEST.AdvanceTime(2)

    T.eq(AsksFrom(sim, council), 0, "it never asks for an item it threw away itself")
    T.eq(council.KART.LC.rollItems[122], nil, "so the tab it closed stays closed")
end

-- The two files have to mean the same thirty seconds -------------------------------------------------
-- The ask cooldown is a local in LootCouncil.lua and the vote path may not reach into it, so it is
-- stated twice. Two cooldowns that drift apart are two ask rates for one ask, which is exactly the
-- doubling the shared LC.rollReqSent table exists to prevent -- so the duplication is pinned here
-- rather than left to whoever next tunes one of them. Read out of the SOURCE, like
-- tests/test_lc_persistedtables.lua does for the two roll-state lists.
do
    local council = assert(io.open("LootCouncil.lua", "r")):read("*a")
    local vote    = assert(io.open("LootCouncilVote.lua", "r")):read("*a")
    local a = council:match("\nlocal ROLL_REQ_COOLDOWN = (%d+)")
    local b = vote:match("\nlocal ROLL_REQ_COOLDOWN = (%d+)")
    T.truthy(a, "LootCouncil.lua states the ask cooldown")
    T.truthy(b, "LootCouncilVote.lua states the ask cooldown")
    T.eq(b, a, "and the vote path asks at the same rate the heartbeat does")
end
