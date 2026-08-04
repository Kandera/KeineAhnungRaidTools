-- The roll table: the lootmaster draws for everybody, once, in one message.
--
-- Before this, every client drew its own number and broadcast it -- 25 messages in the same instant
-- for one drop, 25 separate things to lose, and regular ties because 25 independent draws out of
-- 1-100 collide. What replaces it is a single table drawn by the one client that already knows who
-- was standing there when the item dropped (LC.rollEligible, the same snapshot the catch-up
-- entitlement reads).

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- One drop, one table --------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)
    F.Drop(sim, 900, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    -- RaidSim.Sent matches on the raw bytes handed to C_ChatInfo.SendAddonMessage, which for a
    -- multipart message is a chunk carrying AceComm's own control byte before the token -- a prefix
    -- match would find nothing. This only works because the fixture's payload here stays under the
    -- single-part size limit; it will fail loudly, not silently, the day this message's payload grows
    -- past that limit.
    T.eq(#RaidSim.Sent(sim, "LC_ROLLS:"), 1, "the whole raid's rolls travel as one message")
    T.eq(RaidSim.Sent(sim, "LC_ROLLS:")[1].from, lm.name, "and the lootmaster is the one who sent it")
end

-- Everybody has a number, and no two are the same ------------------------------------------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 901, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local rolls = lm.KART.LC.rolls[901] or {}
    local count, seen, twice = 0, {}, false
    for _, value in pairs(rolls) do
        count = count + 1
        if seen[value] then twice = true end
        seen[value] = true
        T.truthy(value >= 1 and value <= 100, "every number is inside 1-100")
    end
    T.eq(count, #sim.clients, "every raider who was there has a number")
    T.eq(twice, false, "and no number was handed out twice")

    F.AssertAgreed(sim, 901, "about the rolls")
end

-- Somebody who was not there gets nothing ---------------------------------------------------------
-- The settled rule: a late arrival is not handed a running item. Before the table, they drew for
-- themselves the moment LC_START reached them and appeared in the council's tally anyway.
do
    local sim = F.NewRaid()
    F.Drop(sim, 902, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local late = RaidSim.Join(sim, { name = "Torvin", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C99", class = "WARRIOR", locale = "enUS" })
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.is_nil((council.KART.LC.rolls[902] or {})[late.guid], "a raider who joined afterwards has no number")
end

-- A table that never arrived is asked for, once ---------------------------------------------------
-- One message carrying the whole raid's rolls is also one message to lose, and losing it costs
-- everybody's numbers at once instead of one raider's. That is the trade this makes: it can be asked
-- for again, which 25 separate broadcasts never could.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    RaidSim.Blackhole(sim, "LC_ROLLS")
    F.Drop(sim, 903, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    T.eq(blind.KART.LC.rolls[903], nil, "the client that lost the table has no rolls for the item")

    -- The heartbeat is what makes it notice. Nothing is re-broadcast: it asks, and the owner answers
    -- that one client.
    RaidSim.Deliver(sim, "LC_ROLLS")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(15)

    -- RaidSim.Blackhole drops the broadcast before it reaches ANY recipient, not just Corvin's, so
    -- every other raid member is equally blind here -- counting the whole raid's requests would count
    -- them too. What this checks is the one thing the heartbeat promises per client: asked for, not
    -- re-asked for, while an answer could already be on its way.
    local blindAsks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == blind.name then blindAsks = blindAsks + 1 end
    end
    T.eq(blindAsks, 1, "it asks exactly once")
    T.deep_eq(blind.KART.LC.rolls[903], lm.KART.LC.rolls[903],
        "and afterwards it holds the same numbers as the lootmaster")
    F.AssertAgreed(sim, 903, "about the rolls after the catch-up")
end

-- ...but not by somebody who was not there ---------------------------------------------------------
do
    local sim = F.NewRaid()
    F.Drop(sim, 904, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local late = RaidSim.Join(sim, { name = "Torvid", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C98", class = "ROGUE", locale = "enUS" })
    KARTTEST.AdvanceTime(20)

    T.eq(late.KART.LC.rolls[904], nil,
        "a raider who joined after the announcement is not caught up with its rolls either")
end

-- The cooldown holds even while the answer is still missing, across a second heartbeat -------------
-- The "asks exactly once" test above cannot tell a live cooldown from a deleted one: its own answer
-- arrives within the same heartbeat tick that triggered the ask, so needRolls turns false before a
-- second heartbeat could ever fire, and nothing there actually exercises ROLL_REQ_COOLDOWN. Here the
-- catch-up's LC_ROLLS is held in flight -- never delivered, not lost -- so needRolls stays true past
-- a SECOND heartbeat, and only the cooldown timer stands between that and asking twice.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    -- The default vote window (20s) would close right on top of the second heartbeat (t=20) and
    -- take the rollID off the table for a reason that has nothing to do with the cooldown -- widen
    -- it so the only thing keeping the second heartbeat from producing a second ask is the cooldown
    -- itself.
    lm.env.KART_Settings.lcVoteSeconds = 60

    RaidSim.Blackhole(sim, "LC_ROLLS")
    F.Drop(sim, 906, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    T.eq(blind.KART.LC.rolls[906], nil, "the client that lost the table has no rolls for the item")

    -- Deliveries resume, but the catch-up's own LC_ROLLS is held rather than let through -- so the
    -- first ask's answer never lands, and the second heartbeat still finds the table missing.
    RaidSim.Deliver(sim, "LC_ROLLS")
    RaidSim.Hold(sim, "LC_ROLLS")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(21) -- past both the t=10 and t=20 heartbeat ticks

    local blindAsks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == blind.name then blindAsks = blindAsks + 1 end
    end
    T.eq(blindAsks, 1,
        "the cooldown keeps it from asking again at the second heartbeat while unanswered")
end

-- An ownership disagreement must not cost a raider the whole raid's numbers (B129) ------------------
-- The test holds the disagreement open deliberately: a promoted client reloads with its config wiped --
-- (empty Lootmaster field, LC.RelayRaidConfig's "ownership stays derived") and reads itself as loot
-- owner through the raid-leader fallback. The disagreement stays unresolved for the whole test
-- because what is under test is LC.HandleRolls's behavior DURING such disagreement, not how long
-- the disagreement persists in a real raid. The named lootmaster is still out there, unaware,
-- still drawing and sending tables under the old config. Before the roll table became one
-- authoritative message this cost nothing: every client drew its own number with no sender check at
-- all. Now the table is a single writer's state, and disagreeing about who that writer is used to
-- mean getting none of it -- permanently, for that item (seed 1728 in the deep soak).
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local alric = RaidSim.Reload(sim, "Alric")
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 905, F.WEAPON)
    KARTTEST.AdvanceTime(0.5)

    T.deep_eq(alric.KART.LC.rolls[905], lm.KART.LC.rolls[905],
        "the promoted-and-reloaded client ends up holding the same numbers as the lootmaster")
end

-- Two announcers, and everybody keeps the numbers of the one they listened to ---------------------
-- The window is B129's: a raid leader who picked its config back up from a peer has an empty
-- lootmaster field, so it reads itself as the loot owner while the real lootmaster does too. Before
-- this, both drew a table and the raid leader ended up holding numbers nobody else had -- for good,
-- because it refused the real owner's table AND the heartbeat that would have made it ask.
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric") or sim.byName.Alric
    RaidSim.As(leader, function() leader.KART.LC.SetSessionActive(true) end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 910, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    -- Merrit accepted an announcement from somebody. Whoever that was, Merrit's numbers are theirs.
    local merrit = sim.byName.Merrit
    local announcer = merrit.KART.LC.rollAnnouncedBy[910]
    T.truthy(announcer ~= nil, "a client records who announced the item it accepted")
    local source = (announcer == lm.guid) and lm or leader
    T.deep_eq(merrit.KART.LC.rolls[910], source.KART.LC.rolls[910],
        "and holds the table of that announcer, not of whoever it thinks is lootmaster")
end

-- A table from somebody who did not announce it cannot overwrite one that is there ----------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 911, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local merrit, alric = sim.byName.Merrit, sim.byName.Alric
    local before = {}
    for k, v in pairs(merrit.KART.LC.rolls[911]) do before[k] = v end

    -- Alric never announced 911. Hand Merrit a table from Alric by hand.
    RaidSim.As(merrit, function()
        merrit.KART.LC.HandleRolls("911:@" .. F.GLOVES .. ":" .. lm.guid .. "=1", alric.guid)
    end)
    T.deep_eq(merrit.KART.LC.rolls[911], before,
        "a table from somebody who did not announce the item leaves the existing one alone")
end

-- A peer answers when the announcer cannot ------------------------------------------------------
-- After a lootmaster handover the stand-in has no roster snapshot for items the previous owner
-- announced, so LC.MayCatchUp refuses every catch-up for them -- deliberately (B118). The numbers are
-- not secret, though: the whole raid holds the same table, so anybody who has it may hand it over.
--
-- Blackholing LC_ROLLS (as the earlier "asked once" case above does) would not fit here: that drops
-- the announcement's one broadcast for the WHOLE raid, so nobody but the announcer -- about to leave
-- -- ever holds real numbers. What this case needs is everybody holding the table normally and ONE
-- client losing its own copy, so a peer answering means something.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    -- Long past the point LC.OpenRollIDs would otherwise drop the roll from a heartbeat -- what is
    -- under test is recovery minutes into a distribution, not the ordinary 20-second vote window.
    lm.env.KART_Settings.lcVoteSeconds = 90
    F.Drop(sim, 920, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    RaidSim.As(blind, function() blind.KART.LC.rolls[920] = nil end)
    T.eq(blind.KART.LC.rolls[920], nil, "the client that lost the table has no rolls for the item")

    -- The announcer goes away and the raid leader stands in. Its heartbeat is what picks the item
    -- back up (see LC.EnsureTableTicker's OnAccept call) -- but its rollEligible snapshot is Bramor's
    -- to have, not its own, so MayCatchUp still refuses the ITEM (B118) while the numbers are there
    -- for anybody to hand over regardless.
    RaidSim.Leave(sim, "Bramor")
    local stand = sim.byName.Merrit
    -- The stand-in becomes the config owner too (docs/OWNERSHIP.md) and re-broadcasts its OWN
    -- settings on the roster change below; without this the raid-wide roll switch reverts to that
    -- client's untouched default (off) and needRolls never turns true anywhere.
    RaidSim.As(stand, function() stand.env.KART_Settings.lcRollsEnabled = true end)
    RaidSim.RosterUpdate(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(70)

    T.truthy(#RaidSim.Sent(sim, "LC_ROLLS_REQ") >= 1, "the client asks the group, not just the owner")
    T.truthy(blind.KART.LC.rolls[920] ~= nil, "and a peer that still holds the table answers it")
end

-- ...and exactly one peer answers ---------------------------------------------------------------
-- Every client in the raid holds this table. Answering all at once is the message storm this whole
-- rework exists to remove, so the answer is spread by each client's position in the sorted roster and
-- anybody who sees somebody else's answer drops their own.
do
    local sim = F.NewRaid()
    F.Drop(sim, 921, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local asker = sim.byName.Alric
    RaidSim.As(asker, function() asker.KART.LC.rolls[921] = nil end)
    RaidSim.ClearLog(sim)
    RaidSim.As(asker, function() asker.KART.LC.SendLC("LC_ROLLS_REQ:921") end)
    KARTTEST.AdvanceTime(5)

    T.eq(#RaidSim.Sent(sim, "LC_ROLLS:921:"), 1, "one answer reaches the group, not one per peer")
    T.truthy(asker.KART.LC.rolls[921] ~= nil, "and the asker has the table again")
end

-- The spread holds at a full raid, not just this fixture's five ------------------------------------
-- A hash of each client's own name was tried first here and measured to not hold at raid size: two
-- clients landing within a few milliseconds of each other is common enough (simulated: 25 random
-- names, 20,000 trials, the exact hash that was here -- 26% of full rosters collided that closely)
-- that ordinary addon-message jitter under a busy loot round's ChatThrottleLib queue can beat the
-- stand-down to it. LC.RollsAnswerSlot instead places each client by its POSITION in the sorted
-- roster, which guarantees N clients divide the window into N equal gaps -- provable directly, with
-- no simulated raid and no message delivery at all, which is the point of testing the function on its
-- own rather than the traffic it produces.
do
    local _, lm = F.NewRaid()
    local LC = lm.KART.LC

    local keys = {}
    for i = 1, 40 do keys[i] = string.format("Player-1096-%08X", i) end
    table.sort(keys)

    local slots = {}
    for i, key in ipairs(keys) do slots[i] = LC.RollsAnswerSlot(keys, key) end
    table.sort(slots)

    local minGap = math.huge
    for i = 2, #slots do minGap = math.min(minGap, slots[i] - slots[i - 1]) end
    -- The floor this is checked against, not the exact value: it only has to stay comfortably above
    -- ordinary addon-message jitter, and the guarantee holds for any N up to the addon's own maximum
    -- group size (LC.DrawRollTable's roll pool is sized for 40) -- not just the 250ms that size
    -- happens to work out to.
    T.truthy(minGap > 0.2, "a full 40-player raid still keeps every answer at least 200ms apart")

    -- The order of the roster does not matter, only membership: a different sort of the same 40 keys
    -- still divides the same window into the same equal gaps.
    local shuffled = {}
    for i, key in ipairs(keys) do shuffled[#keys - i + 1] = key end
    local slots2 = {}
    for i, key in ipairs(keys) do slots2[i] = LC.RollsAnswerSlot(shuffled, key) end
    table.sort(slots2)
    T.deep_eq(slots, slots2, "the gaps are the same however the caller happens to list the roster")
end
