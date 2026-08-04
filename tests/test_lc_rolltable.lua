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

    T.eq(#RaidSim.Sent(sim, "LC_ROLL:"), 0, "nobody broadcasts a roll of their own any more")
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
