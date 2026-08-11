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

-- Two copies of one item are one card, and one answer ----------------------------------------------
-- A boss dropping the same item twice gives it two rollIDs and, until now, two cards: the raider
-- clicked twice for one decision, and the class the council then chased was "answered (1/2), missed
-- (2/2)". The council side stays per copy -- the two are awarded to different people -- so only the
-- RAIDER's card merges.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 130, F.GLOVES)
    Drop(sim, 131, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local visible
    RaidSim.As(raider, function() visible = raider.KART.LC.Vote.GetVisibleRolls() end)
    T.eq(#visible, 1, "two copies of one item are one card")
    T.eq(visible[1], 130, "and it is the first copy, the one the ordinal calls (1/2)")
    T.eq(F.HasVoteRow(raider, 131), true, "the second copy is still tracked, just not drawn twice")
    T.eq(#council.KART.LC.councilTabs, 2, "while the council still scores each copy on its own tab")

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(130, 2) end)
    KARTTEST.AdvanceTime(1)

    T.eq(((council.KART.LC.votes[130] or {})[raider.guid] or {}).idx, 2, "one click answers the copy shown")
    T.eq(((council.KART.LC.votes[131] or {})[raider.guid] or {}).idx, 2, "and the copy it stands for")

    local mine = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_VOTE:")) do
        if e.from == raider.name and e.msg:match("^LC_VOTE:") then mine = mine + 1 end
    end
    T.eq(mine, 2, "as one message per copy -- the council needs both -- and not one per copy per copy")
end

-- ...and a copy that arrives after the answer inherits it -------------------------------------------
-- The two drops do not have to be simultaneous. A raider who has already answered must not be asked
-- again by a card that opens seconds later for the same item.
do
    local sim, _, council, raider = NewRaid()
    Drop(sim, 132, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(132, 1) end)
    KARTTEST.AdvanceTime(1)

    Drop(sim, 133, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    T.eq(((council.KART.LC.votes[133] or {})[raider.guid] or {}).idx, 1,
        "a copy that arrives after the answer is answered the same way")
    T.eq(raider.KART.LC.votedByMe[133], 1, "and the raider is not asked a second time")
end

-- ...and the merged card runs on the earlier of the two windows -------------------------------------
-- The copies start apart, so their deadlines are apart. The card is drawn for the lower rollID -- the
-- ordinal's (1/2) -- and that one can be the LATER of the two; showing its timer would tell the
-- raider they have time they do not have for the other copy.
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 141, F.GLOVES)
    KARTTEST.AdvanceTime(3)
    Drop(sim, 140, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local shown, own, earlier
    RaidSim.As(raider, function()
        shown   = raider.KART.LC.Vote.CardDeadline(140)
        own     = raider.KART.LC.rollDeadlines[140]
        earlier = raider.KART.LC.rollDeadlines[141]
    end)
    T.eq(shown, earlier, "the merged card counts down the earlier window")
    T.truthy(shown < own, "which is not the window of the copy it is drawn for")
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

-- A round that ended is not a gap to repair ---------------------------------------------------------
-- The vote heartbeat repeats a bundle every five seconds and is NORMAL priority, while LC_END_ROUND
-- is ALERT and guaranteed -- so on a busy pipe a bundle sent moments before the round ended lands
-- after it. By then LC.ClearAllRolls has wiped rollItems, rollExpiredHere, rollDismissed AND
-- rollReqSent, so every gate E1's ask has is open and every entry in that bundle looks like a roll
-- this client was never told about. Each straggler then whispers the owner about a roll nobody has
-- any more, all of them refused by LC.HandleRollRequest -- one ask per sender per item, which at
-- raid size is the whole raid asking at once.
--
-- The same wipe is what let F's ack-driven ask fire again after every End Round repeat (there are
-- three, 0/2/5 s apart), measured at three times the asks of the tree before these packages.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 140, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(140, 1) end)

    -- Held, not blackholed: this message is not lost, it is SLOW -- which is the whole case.
    RaidSim.Hold(sim, "LC_VOTES")
    KARTTEST.AdvanceTime(8)

    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    KARTTEST.AdvanceTime(1)
    T.is_nil(raider.KART.LC.rollItems[140], "the round is over and the roll is gone from the raid")

    RaidSim.ClearLog(sim)
    T.truthy(RaidSim.Release(sim, "LC_VOTES") > 0, "and a heartbeat from before it now lands")
    KARTTEST.AdvanceTime(2)

    T.eq(CountExact(sim, "LC_ROLL_REQ"), 0,
        "nobody asks the owner to hand back a roll the whole raid has just finished with")
end

-- An empty stamp still counts as "cannot tell" (B149 gap 1) -----------------------------------------
-- Vote.CastVote stamps a vote with TrackedItemID(rollID), which falls back to "" when the voter's own
-- link has not arrived -- the raider is looking at "???" and has nothing to stamp with. LC.VoteIsForItem
-- treats an empty stamp as unknown, therefore counted, per its own comment ("cannot-tell counts as
-- belonging"). Losing that branch compares "" against the reader's real itemID, which is never equal,
-- and the vote silently disappears from the tally on every client that DOES know the item.
do
    local sim, lm, _, raider = NewRaid()

    -- The raider never got Blizzard's own roll, and the announcement that would tell it the item is
    -- blackholed -- the same "???" construction test_lc_rolltable.lua uses for this state.
    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 150, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.As(raider, function() raider.KART.LC.HandleStart("150:20:", lm.guid) end)
    T.eq(raider.KART.LC.rollItems[150], "???", "the raider holds an item it cannot read")

    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(150, 1) end)
    KARTTEST.AdvanceTime(1)

    T.eq(lm.KART.LC.votes[150][raider.guid].item, "",
        "the vote arrives stamped empty -- there was nothing to stamp it with")
    T.eq(RaidSim.As(lm, function() return lm.KART.LC.CountVotes(150) end), 1,
        "and still counts on the lootmaster, who knows exactly what item is on the table")
end

-- An unreadable OWN item does not blank a card that is voting fine (B149 gap 2) ----------------------
-- The other half of the same guard, called out by the function's own comment: "refusing those would
-- blank a whole raid's votes over a link that had not arrived yet." Here it is the READER, not the
-- voter, holding "???" -- and two other raiders vote with real stamps because THEY can read their own
-- copies. Losing the mine=="" branch compares a real itemID against "" for both of them, which is
-- never equal, and the reader's card would show no votes at all.
do
    local sim, lm, council, raider = NewRaid()
    local sinja = sim.byName.Sinja

    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 151, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.As(council, function() council.KART.LC.HandleStart("151:20:", lm.guid) end)
    T.eq(council.KART.LC.rollItems[151], "???", "the reader cannot read its own copy of the item")

    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(151, 1) end)
    RaidSim.As(sinja, function() sinja.KART.LC.Vote.CastVote(151, 2) end)
    KARTTEST.AdvanceTime(1)

    T.truthy(council.KART.LC.votes[151][raider.guid].item ~= "",
        "the raider's own copy resolved fine, so its vote carries a real stamp")
    T.eq(RaidSim.As(council, function() return council.KART.LC.CountVotes(151) end), 2,
        "and both real-stamped votes still count on the client that cannot read its own")
end

-- The copy that opened before its own announcement went out (B167) ---------------------------------
-- E2 makes one card answer for every copy of an item: click once, and Vote.CastVote fans the answer
-- out to the other copies. A copy that arrives AFTER the raider has already answered inherits instead
-- -- InheritCopyAnswer, called from Vote.ShowVotePopup.
--
-- On the LOOT OWNER that call has to be held back, and Vote.ApplyInheritedAnswers on the prune tick is
-- what comes back for it. The owner tracks a roll from its own START_LOOT_ROLL and announces it a
-- moment later, once the batch it belongs to is flushed (LC.pendingDrop) -- so in between it is the
-- only client that knows the number exists, and a vote sent for it is refused by every receiver as
-- untracked. Found by the soak walk at seed 25, on a reused rollID: the announcer inherited its copy's
-- answer, the message went out ahead of the announcement, and that client stood alone with a vote
-- nobody could accept until the next heartbeat repeated it.
--
-- Vote.ApplyInheritedAnswers had no test: mutating it to a no-op left the whole suite green. It is the
-- half of E2 that runs on the one client whose vote the rest of the raid cannot repair, which is what
-- makes the silence expensive rather than merely untidy.
do
    local sim, lm = F.NewRaid()

    F.Drop(sim, 3101, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(lm, function() lm.KART.LC.Vote.CastVote(3101, 1) end)
    T.eq(lm.KART.LC.votedByMe[3101], 1, "the setup: the owner has answered the first copy")

    -- A second copy of the SAME item. While the batch is still collecting, the raid has not been told
    -- this number exists at all.
    F.Drop(sim, 3102, F.GLOVES)
    T.truthy(lm.KART.LC.pendingDrop ~= nil, "the second copy is still inside the collection window")
    T.is_nil(lm.KART.LC.votedByMe[3102],
        "B167: nothing is inherited while the raid could not accept a vote for it yet")

    -- Past DROP_COLLECT the batch goes out -- but ShowVotePopup already ran and was held back, so the
    -- answer is still missing at this point. This is the assertion the retry exists for.
    KARTTEST.AdvanceTime(0.6)
    T.eq(lm.KART.LC.pendingDrop, nil, "the batch has been announced")
    T.is_nil(lm.KART.LC.votedByMe[3102],
        "B167: and the card that opened before it was announced is still unanswered")

    -- The prune ticker comes round and picks it up.
    KARTTEST.AdvanceTime(1.2)
    T.eq(lm.KART.LC.votedByMe[3102], 1,
        "B167: Vote.ApplyInheritedAnswers casts the answer the raider already gave, without a second click")
end

-- What a merged card says it stands for (B168) -------------------------------------------------------
-- Vote.CardItemSuffix is the raider's only on-screen sign that one card answers for more than one
-- item. Mutating it to "" left the whole suite green, so nothing held it -- including the contract its
-- own comment states, which was written during this review when a "disagreement" with
-- Trade.GetDuplicateOrdinal was raised and withdrawn.
--
-- That contract, asserted here rather than only described: the count is HOW MANY COPIES THIS ANSWER
-- COVERS -- DuplicateGroup's set, the copies still answerable on this client -- and deliberately not
-- the ordinal's denominator, which counts every copy in LC.rollItems including closed and awarded
-- ones. The two answer different questions and must not be "reconciled".
do
    local sim = F.NewRaid()
    local raider = sim.byName.Alric

    -- One item on its own: no marking at all.
    F.Drop(sim, 3201, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.eq(RaidSim.As(raider, function() return raider.KART.LC.Vote.CardItemSuffix(3201) end), "",
        "B168: a single drop carries no copy marking")

    -- A second copy of the same item, both answerable: one card, and it says it stands for two.
    F.Drop(sim, 3202, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.eq(RaidSim.As(raider, function() return raider.KART.LC.Vote.CardItemSuffix(3201) end), " (2x)",
        "B168: two answerable copies make one card that says it answers for both")

    -- A third, to prove the number is counted rather than hardcoded for the pair.
    F.Drop(sim, 3203, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.eq(RaidSim.As(raider, function() return raider.KART.LC.Vote.CardItemSuffix(3201) end), " (3x)",
        "B168: and three copies say three")

    -- A DIFFERENT item under its own number is not a copy of anything.
    F.Drop(sim, 3204, F.WEAPON)
    KARTTEST.AdvanceTime(1)
    T.eq(RaidSim.As(raider, function() return raider.KART.LC.Vote.CardItemSuffix(3204) end), "",
        "B168: and a different item is not folded in with them")
end
