-- The gate. ChatThrottleLib splits the pipe evenly across its three priorities, so BULK does not
-- yield -- it takes about a third even while ALERT traffic waits, out of a budget shared with every
-- other addon in the client. A 150-entry catch-up therefore competes with the distribution unless
-- something harder than a priority stops it.
--
-- Parked and not dropped, because a request that is thrown away is a raider who gets no history all
-- evening (B66). And capped, because the release condition is the roll state whose failure it exists
-- to survive (C9, the lootmaster walks out): without the cap the parked request sits there forever
-- and nobody can see it, which is exactly what C14 forbids.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link

-- Same two-step as tests/test_lc_award.lua uses: F.Drop puts the item on the table, AssignWinner
-- awards it. No fixture helper is added -- lc_fixture.lua is claimed by neither session.
local function Award(sim, assigner, rollID, itemID, winner, reason)
    F.Drop(sim, rollID, itemID)
    RaidSim.As(assigner, function()
        assigner.KART.LC.Trade.AssignWinner(rollID, winner.guid, reason, nil)
    end)
    RaidSim.Drain(sim, 10)
end

local function LoadedPeer(lm, raider, n)
    local entries = {}
    for i = 1, n do
        entries[i] = { time = time() - 3600 + i, item = GLOVES, winner = "Alric",
                       winnerKey = "Player-1-A", reason = "BIS", class = "MAGE", rollID = i,
                       id = "gate-" .. i, epoch = 1 }
    end
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
end

-- A request during an open roll is not answered yet ---------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 60)
    F.Drop(sim, 80, F.GLOVES)              -- a roll is now open on every client
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)

    T.eq(#RaidSim.Messages(sim, "LC_HIST_BATCH"), 0,
        "nothing goes out while a roll is open here")
    T.eq(#raider.env.KART_LootHistory, 0, "so the raider has nothing yet")
end

-- and is answered once the round is over ----------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 60)
    F.Drop(sim, 81, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(81, raider.guid, "BIS", nil) end)
    -- Awarding does not close lm's own council tab for roll 81 (reassigning stays possible on
    -- purpose, see Trade.DoAssignWinner) -- LC.rollDeadlines still holds it. But LC.assignedWinners
    -- is set the same instant the award is made, and LH.GateOpen() only counts UNDECIDED rolls as
    -- blocking, so the gate opens through the ordinary grace path (GATE_GRACE after the last time a
    -- roll here was actually still undecided) -- not through GATE_MAX_PARK, which the next block
    -- exercises directly.
    KARTTEST.AdvanceTime(10)               -- past GATE_GRACE
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 61,
        "the parked request is answered after the round -- 60 caught up plus the award just made")
end

-- A roll that never closes still releases the request ---------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 60)
    F.Drop(sim, 82, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)
    -- No award, no End Round: the lootmaster walked out and the roll stays open forever.
    KARTTEST.AdvanceTime(65)                -- past GATE_MAX_PARK
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 60,
        "the hard cap answers the request even though the roll never closed")
end

-- A repeat request from the same sender does not push the park deadline out ------------------------
-- Reproduces the reviewer's finding: three requests at 50-second intervals with the gate held shut
-- must not keep the entry parked through all three, releasing only once resends stop. GATE_MAX_PARK
-- measures how long the SENDER has been waiting, not how long since their most recent nudge.
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 5)
    -- Only lm sees this roll -- keeps lm's own gate shut (undecided, forever, since it is never
    -- awarded) without also gating raider's own LH.RequestHistorySync, so each of the three calls
    -- below sends immediately rather than queueing behind raider's own defer loop.
    F.Drop(sim, 85, F.GLOVES, { noRollFor = { [raider.name] = true } })
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)

    -- Two more requests from the same sender, each comfortably inside the FIRST one's 60-second
    -- park window -- exactly the "asks again while still waiting" case LH.ParkRequest exists to
    -- collapse into a single answer, not one that should also push the deadline back.
    KARTTEST.AdvanceTime(20)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)
    KARTTEST.AdvanceTime(20)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)

    -- 45s since the LAST resend (t=40), but 85s since the FIRST request (t=0) that actually parked.
    -- If a resend reset the clock, this would still be gated shut -- only 45s would have passed since
    -- that reset. It must not be: the cap has to fire off the original park time.
    KARTTEST.AdvanceTime(45)
    RaidSim.Drain(sim, 5)

    T.eq(#raider.env.KART_LootHistory, 5,
        "the cap fires off the FIRST request's park time, not the latest resend's")
end

-- A client whose own gate never reopens still asks, eventually -------------------------------------
-- The asking side's own analog to GATE_MAX_PARK: LH.RequestHistorySync must not defer forever just
-- because this client's own gate never opens.
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 7)
    -- Hold raider's own gate shut directly, without routing a real drop through F.Drop: lm is the
    -- loot owner and registers its OWN roll synchronously the moment an item drops (see the earlier
    -- blocks), so a real drop here would also shut lm's gate -- and this block is specifically about
    -- isolating the ASKING side's cap (raider's) from the ANSWERING side's (lm's), which the next
    -- block already covers on its own. LH.GateOpen() only reads LC.rollDeadlines/LC.assignedWinners,
    -- so writing the one entry it cares about directly reaches the same state a real, permanently
    -- undecided roll would.
    RaidSim.As(raider, function() raider.KART.LC.rollDeadlines[86] = GetTime() + 999 end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)

    T.eq(#RaidSim.Sent(sim, "LC_HIST_REQ"), 0,
        "raider's own gate is shut (its roll is still undecided), so nothing goes out yet")

    -- No award, no End Round -- raider's own roll never closes either. Past GATE_MAX_PARK the request
    -- must go out anyway, or raider silently never catches up for the rest of the session.
    KARTTEST.AdvanceTime(65)
    RaidSim.Drain(sim, 5)

    T.eq(#raider.env.KART_LootHistory, 7,
        "the cap makes the client ask anyway, even though its own gate never opened")
end

-- The distribution is not delayed by a queued catch-up ---------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 150)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.ClearLog(sim)
    F.Drop(sim, 83, F.GLOVES)
    -- RaidSim.Drain only advances the clock while something is already queued in CTL, and at this
    -- exact instant nothing is (the earlier catch-up request/answer already settled, and the drop's
    -- own collection window is a plain C_Timer.After, not a queued message) -- so it would return
    -- immediately without ever reaching DROP_COLLECT. Advance the clock directly instead, the same
    -- way tests/test_lc_baseflow.lua waits for a drop's own LC_DROP.
    KARTTEST.AdvanceTime(1)

    -- LC_START is dead wire (see LootCouncil.lua's GUARANTEED_TOKENS comment) -- a real drop travels
    -- as LC_DROP, ALERT priority.
    T.truthy(#RaidSim.Messages(sim, "LC_DROP") > 0,
        "the item goes on the table within a second with 150 entries queued behind it")
end

-- A client behind the raid's epoch does not award ---------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = 2
        lm.KART.LH.heardEpoch = 2
    end)
    RaidSim.As(raider, function() raider.KART.LH.heardEpoch = 5 end)   -- behind, and knows it
    RaidSim.ClearLog(sim)
    F.Drop(sim, 84, F.GLOVES)
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.AssignWinner(84, raider.guid, "BIS", nil)
    end)
    RaidSim.Drain(sim, 5)

    T.eq(#RaidSim.Messages(sim, "LC_RESULT"), 0,
        "a stale client does not write into a record it cannot see all of")
end

-- A parked request has to be visible. The manifest names /kart status as the thing a raid runs when
-- something is wrong mid-boss, and a hold that nobody can see is the shape C14 exists to forbid.
do
    local sim, lm, _, raider = F.NewRaid()
    LoadedPeer(lm, raider, 10)
    F.Drop(sim, 85, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    RaidSim.Drain(sim, 3)

    local lines = {}
    RaidSim.As(lm, function()
        local realPrint = lm.env.print
        lm.env.print = function(s) lines[#lines + 1] = tostring(s) end
        lm.KART.LH.PrintStatus()
        lm.env.print = realPrint
    end)

    local joined = table.concat(lines, "\n")
    T.truthy(joined:find("1", 1, true), "the status names the one parked request")
    T.truthy(joined:lower():find("hist"), "and says what it is about")
end

-- LH.PrintStatus must not perturb the gate it merely reports on ------------------------------------
-- LH.GateOpen is not a pure read: whenever it finds an undecided roll it stamps
-- LH.gateClosedUntil = GetTime() + GATE_GRACE as a side effect. Calling it three times in a row while
-- a roll is still undecided -- exactly what running /kart status repeatedly while something looks
-- stuck does -- must not push that stamp out to the time of the LAST status call. If it did, resolving
-- the roll the instant after would still find the gate held for another GATE_GRACE seconds, delaying
-- release of parked sync requests and a stuck client's own catch-up for no reason but having checked.
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function() lm.KART.LC.rollDeadlines[87] = GetTime() + 999 end)

    RaidSim.As(lm, function()
        local realPrint = lm.env.print
        lm.env.print = function() end
        for _ = 1, 3 do
            lm.KART.LH.PrintStatus()
            KARTTEST.AdvanceTime(2)
        end
        lm.env.print = realPrint
    end)

    -- Resolve the roll right in the same instant as the last PrintStatus call above.
    RaidSim.As(lm, function() lm.KART.LC.assignedWinners[87] = true end)

    T.truthy(RaidSim.As(lm, function() return lm.KART.LH.GateOpen() end),
        "the gate reopens immediately once the roll resolves -- PrintStatus did not hold it shut")
end
