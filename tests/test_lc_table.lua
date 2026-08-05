-- The table, said out loud, and the rule about who may still be handed an item off it.
--
-- B118. Every message that puts an item on the table is sent once, with no acknowledgement and
-- nothing that notices the silence. On 2026-08-03 that cost a raider an item outright -- other
-- raiders had the card, he had Blizzard's roll window and nothing else -- and it cost a council
-- member three rounds of cards because End Round never reached him.
--
-- Two mechanisms, and the line between them is the whole design:
--   * the heartbeat may only ever ADD. A client asks for what it is missing.
--   * removal comes from a person deciding it. End Round says so again rather than letting anybody
--     infer an item is gone from a list that stopped mentioning it.
-- The second half of that is not squeamishness. The loot role moves mid-round in this guild's raids
-- every evening (docs/MANIFEST.md), and a stand-in's table is empty the moment they take over: one
-- "here is everything that is open" from them, read as authoritative, deletes the item every council
-- member is voting on.
--
-- And the rule the maintainer settled the same evening: a late arrival is not handed a running item,
-- "der ist ja nicht mal lootberechtigt". Enforced at the source, by the one client that knows who was
-- standing there when the item dropped.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local LATECOMER = { name = "Torvi", realm = "TarrenMill", guid = "Player-1096-0A1B2C99",
                    class = "MAGE", locale = "enUS" }

-- The heartbeat, and a client that missed the announcement -------------------------------------------
do
    local sim, lm, council = F.NewRaid()

    -- The exact shape of the report: Blizzard raised no roll for this client -- dead, released, out of
    -- range -- so the announcement was its only way to hear about the item, and the announcement was
    -- lost. Other raiders had the card, this one had nothing.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 80, F.GLOVES, { bop = true, noRollFor = { Merrit = true } })
    -- Past the window the drop is collected in, so the announcement is made -- and lost -- while the
    -- blackhole is still up.
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    T.truthy(lm.KART.LC.rollItems[80], "the owner has the item")
    T.eq(council.KART.LC.rollItems[80], nil, "and the council member does not, having missed it")

    -- A poll interval later the owner says what is on the table, the council member notices the gap
    -- and asks, and the owner answers it.
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(3)
    T.truthy(#RaidSim.Sent(sim, "LC_TABLE") > 0, "the owner says what is on the table")
    T.truthy(#RaidSim.Sent(sim, "LC_ROLL_REQ") > 0, "the client missing an item asks for it")
    T.truthy(council.KART.LC.rollItems[80], "and gets it")
    T.eq(council.KART.LC.rollItems[80], lm.KART.LC.rollItems[80], "the same item, not a rebuilt guess")

    -- Asked once, not once per heartbeat: an answer can be on its way while the next one goes out.
    -- Far enough for the forced repeat to fall due, so there really is another heartbeat to stay
    -- quiet about.
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35)
    T.truthy(#RaidSim.Sent(sim, "LC_TABLE") > 0, "the table is said again")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_REQ"), 0, "and does not keep asking once it has it")
end

-- A change to the table reaches the raid inside one poll interval ------------------------------------
-- What the cadence is FOR. The message goes out when what it would say has changed, which is noticed
-- by a poll rather than by a call at every site that can change it -- three attempts at keeping that
-- list of sites by hand each missed one, and the missed one is always where the repair path dies.
do
    local sim = F.NewRaid()
    F.Drop(sim, 86, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(3) -- the first item is announced and its table said once

    RaidSim.ClearLog(sim)
    F.Drop(sim, 87, F.WEAPON, { bop = true })
    KARTTEST.AdvanceTime(3) -- the drop's own collection window, then one poll

    local said = RaidSim.Sent(sim, "LC_TABLE")
    T.truthy(#said > 0, "a table that changed is said again without waiting for the forced repeat")
    T.truthy(said[#said].msg:match("87=" .. F.WEAPON), "and the message names the item that changed it")
end

-- ...and a table that does NOT change is repeated at the forced interval, not at the poll ------------
do
    local sim = F.NewRaid()
    F.Drop(sim, 88, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(3)

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(28)
    T.eq(#RaidSim.Sent(sim, "LC_TABLE"), 0,
        "an unchanged table is not repeated once per poll for the rest of the distribution")
    KARTTEST.AdvanceTime(5)
    T.eq(#RaidSim.Sent(sim, "LC_TABLE"), 1,
        "but it is said again when the forced repeat falls due, for whoever was not listening")
end

-- ...and the poll stops once the table is empty -------------------------------------------------------
-- One last message so a client that missed End Round can drop its cards, and then silence: an idle
-- raid must not be paying for a poll that has nothing left to say. End Round is not the case under
-- test -- it stops the ticker outright (LC.ClearAllRolls) -- so the table is emptied the way a
-- distribution really ends it, one roll at a time leaving the owner's own tracking.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 89, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(3)

    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.LC.Trade.ClearRollState(89) end)
    KARTTEST.AdvanceTime(3)
    local said = RaidSim.Sent(sim, "LC_TABLE")
    T.eq(#said, 1, "the emptied table is said exactly once")
    T.truthy(said[1].msg:match("LC_TABLE:0:"), "and what it says is that there is nothing on it")

    KARTTEST.AdvanceTime(90)
    T.eq(#RaidSim.Sent(sim, "LC_TABLE"), 1, "after which nothing polls on")
end

-- A late arrival is not handed a running item ---------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 81, F.GLOVES, { bop = true })
    -- Announced before they walk in: that is what makes the distribution "already running".
    KARTTEST.AdvanceTime(1)

    local late = RaidSim.Join(sim, LATECOMER)
    KARTTEST.AdvanceTime(0)
    T.eq(late.KART.LC.rollItems[81], nil, "somebody who walks in mid-distribution has no card for it")

    -- ...and asking directly does not get them one, which is the case the old Blizzard-roll check used
    -- to cover and could not cover for a manually added item at all (B79).
    RaidSim.As(late, function() late.KART.LC.SendLC("LC_ROLL_REQ:81", lm.name .. "-" .. lm.realm) end)
    KARTTEST.AdvanceTime(1)
    T.eq(late.KART.LC.rollItems[81], nil, "and asking for it does not change that")

    -- The people who WERE here still get answered, from the same table.
    local was = sim.byName.Sinja
    RaidSim.As(was, function() was.KART.LC.Trade.ClearRollState(81) end)
    T.eq(was.KART.LC.rollItems[81], nil, "a raider who was here loses their copy somehow")
    RaidSim.As(was, function() was.KART.LC.SendLC("LC_ROLL_REQ:81", lm.name .. "-" .. lm.realm) end)
    KARTTEST.AdvanceTime(1)
    T.truthy(was.KART.LC.rollItems[81], "and is given it back, because they were standing there")
end

-- The heartbeat never removes anything ---------------------------------------------------------------
-- The half that was designed and deliberately not built. A stand-in whose own table is empty must not
-- be able to clear the raid's cards by saying so.
do
    local sim, _, council = F.NewRaid()
    F.Drop(sim, 82, F.GLOVES, { bop = true })
    T.truthy(council.KART.LC.rollItems[82], "the council member is on the item")

    -- The owner's own view goes blank -- a reload, a stand-in taking over -- and it broadcasts that.
    local owner = sim.byName.Bramor
    RaidSim.As(owner, function()
        owner.KART.LC.rollItems[82] = nil
        owner.KART.LC.rollDeadlines[82] = nil
        owner.KART.LC.SendTableHeartbeat()
    end)
    KARTTEST.AdvanceTime(0)
    T.truthy(council.KART.LC.rollItems[82],
        "and the council member still has the item it is voting on")
end

-- End Round says it more than once -------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 83, F.GLOVES, { bop = true })
    RaidSim.ClearLog(sim)

    RaidSim.As(lm, lm.KART.LC.EndRound)
    T.eq(#RaidSim.Sent(sim, "LC_END_ROUND"), 1, "End Round goes out immediately")
    KARTTEST.AdvanceTime(6)
    T.eq(#RaidSim.Sent(sim, "LC_END_ROUND"), 3, "and twice more, for the client that missed the first")

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.councilTabs, 0, c.name .. " has no cards left")
    end
end

-- ...but not once the round has restarted -------------------------------------------------------------
-- The repeat is a second chance at a message, not a standing order. An item dropping inside those five
-- seconds makes the old End Round untrue, and resending it would clear the NEW item off every peer
-- while the sender keeps it. Found by the convergence soak at seed 93, on the first run after the
-- repeat was added.
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 84, F.GLOVES, { bop = true })
    RaidSim.ClearLog(sim)

    RaidSim.As(lm, lm.KART.LC.EndRound)
    KARTTEST.AdvanceTime(1)
    F.Drop(sim, 85, F.WEAPON, { bop = true })
    KARTTEST.AdvanceTime(6)

    T.eq(#RaidSim.Sent(sim, "LC_END_ROUND"), 1, "the repeats are dropped once a new item is on the table")
    T.truthy(council.KART.LC.rollItems[85], "which is why the new item is still there")
    T.truthy(lm.KART.LC.rollItems[85], "on the owner's side too")
end
