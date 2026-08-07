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
    -- purpose, see Trade.DoAssignWinner), so LC.rollDeadlines still holds it and lm.LH.GateOpen()
    -- stays false. The parked request is released by GATE_MAX_PARK instead, the same mechanism the
    -- next block exercises directly.
    KARTTEST.AdvanceTime(65)               -- past GATE_MAX_PARK
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
