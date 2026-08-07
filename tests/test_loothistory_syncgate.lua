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

-- Same two-step as tests/test_lc_award.lua uses: F.Drop puts the item on the table, AssignWinner
-- awards it. No fixture helper is added -- lc_fixture.lua is claimed by neither session.
local function Award(sim, assigner, rollID, itemID, winner, reason)
    F.Drop(sim, rollID, itemID)
    RaidSim.As(assigner, function()
        assigner.KART.LC.Trade.AssignWinner(rollID, winner.guid, reason, nil)
    end)
    RaidSim.Drain(sim, 10)
end

-- The peer's history, at the entropy a raid night has rather than the same link and the same reason
-- n times over. A single-link fixture deflates to a few hundred bytes whatever n is, so the gate
-- tests below would have been driving a catch-up of one message where a real one is several -- and
-- the whole point of the gate is what a real catch-up does to the pipe. Same reasoning, and the same
-- pools in miniature, as tests/test_lc_histsync_length.lua's VariedEntries.
local ITEM_POOL = {}
for _, id in ipairs({ F.GLOVES, F.WEAPON, F.TOKEN, F.PLATE_CHEST, F.STAFF, F.SHIELD, F.LONG_ITEM,
                      F.TIER_TOKEN }) do
    ITEM_POOL[#ITEM_POOL + 1] = KARTTEST.items[id].link
end
local REASON_POOL = { "BIS", "Mainspec", "Zweitspec, aber nur wenn niemand Mainspec braucht",
                      "Offspec", "Transmog" }

local function LoadedPeer(lm, raider, n)
    local entries = {}
    for i = 1, n do
        local at = time() - 3600 + i * 5
        entries[i] = {
            time = at, item = ITEM_POOL[(i - 1) % #ITEM_POOL + 1],
            winner = ("Raider%02d"):format((i - 1) % 25 + 1),
            winnerKey = ("Player-1096-0A1B2%03X"):format((i - 1) % 25 + 1),
            reason = REASON_POOL[(i - 1) % #REASON_POOL + 1], class = "MAGE", rollID = i,
            id = string.format("gate-%d-%03x%03x", at, (i * 2654) % 0x1000, (i * 977) % 0x1000),
            epoch = 1,
        }
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
    --
    -- Stepped in the transport's own slices rather than jumped, so the drop and the catch-up can be
    -- compared at the instant the drop lands. The property is "ALERT is not queued behind BULK", and
    -- a wall-clock constant is not that property: this used to assert "within a second", which held
    -- only because a 150-entry catch-up built from ONE item link and one repeated reason deflated to
    -- almost nothing, so there was never anything for the drop to overtake. What is asserted instead
    -- is the overtaking itself.
    local landed, historyThen
    for _ = 1, 20 do
        KARTTEST.AdvanceTime(0.1)
        -- LC_START is dead wire (see LootCouncil.lua's GUARANTEED_TOKENS comment) -- a real drop
        -- travels as LC_DROP, ALERT priority.
        if #RaidSim.Messages(sim, "LC_DROP") > 0 then
            landed, historyThen = true, #raider.env.KART_LootHistory
            break
        end
    end

    T.truthy(landed, "the item goes on the table with 150 entries queued behind it")
    T.truthy(historyThen and historyThen < 150,
        "and it gets there while the catch-up is still running -- ALERT is not queued behind BULK ("
        .. tostring(historyThen) .. " of 150 had arrived)")
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
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    local said = {}
    RaidSim.As(raider, function()
        local realPrint = raider.env.print
        raider.env.print = function(s) said[#said + 1] = tostring(s) end
        raider.KART.LC.Trade.AssignWinner(84, raider.guid, "BIS", nil)
        raider.env.print = realPrint
    end)
    RaidSim.Drain(sim, 5)

    T.eq(#RaidSim.Messages(sim, "LC_RESULT"), 0,
        "a stale client does not write into a record it cannot see all of")
    -- And leaves nothing behind locally either. Trade.AnnounceResult's own refusal comes too late:
    -- Trade.DoAssignWinner has already recorded the winner by then and goes on to log a history row
    -- with no awardID and no epoch, so LH.LogHistory mints a fresh id and stamps the local epoch.
    -- The panel shows a winner, the log gains a row no other client will ever hold, nothing goes on
    -- the wire and nothing is printed -- and that id then guarantees a permanent checksum mismatch.
    T.eq(#raider.env.KART_LootHistory, 0,
        "and does not write a phantom award into its own log that no other client holds")
    T.eq(raider.KART.LC.assignedWinners[84], nil, "nor a winner into its own council panel")
    T.truthy(#said > 0, "and it says the award did not happen (C14)")
end

-- ...and does not strike one either -------------------------------------------------------------------
-- The revoke half of the same rule (LootCouncil.lua, RevokePriorAward -- the /kart add path). Taking
-- an award BACK is a write into the raid's loot record exactly as making one is, so a client that may
-- not make one may not strike one. Trade.AnnounceResult's own refusal is too late here for the same
-- reason it was too late in Trade.DoAssignWinner: the local cleanup below it runs regardless, so a
-- stale client removed the history row, dropped the pending trade and closed the tab on its own screen
-- while the rest of the raid kept the award -- a divergence created by the very client that could see
-- least, and nothing said.
do
    local sim, lm, _, raider = F.NewRaid()
    Award(sim, lm, 88, F.GLOVES, raider, "BIS")
    T.eq(#lm.env.KART_LootHistory, 1, "the award is on the lootmaster's log to begin with")

    -- Behind the raid, and knows it -- the same state the block above puts a client in.
    RaidSim.As(lm, function()
        lm.KART.LH.heardEpoch = (lm.env.KART_LootHistoryEpoch or 1) + 1
        T.truthy(lm.KART.LH.IsStale(), "the lootmaster is behind the raid's epoch")
    end)

    RaidSim.ClearLog(sim)
    local said = {}
    RaidSim.As(lm, function()
        local realPrint = lm.env.print
        lm.env.print = function(s) said[#said + 1] = tostring(s) end
        -- Handing the same item back to the council is what triggers the revoke: the item can only be
        -- re-decided once whatever was decided about it last time has stopped being true.
        lm.KART.LC.StartManualRoll(KARTTEST.items[F.GLOVES].link)
        lm.env.print = realPrint
    end)
    RaidSim.Drain(sim, 10)

    T.eq(#RaidSim.Messages(sim, "LC_RESULT"), 0, "no revocation goes out to the raid")
    T.eq(#lm.env.KART_LootHistory, 1,
        "and the award is not struck from this client's log alone")
    T.eq(lm.KART.LC.assignedWinners[88], raider.guid, "the winner still stands on the panel")
    T.truthy(F.Owes(lm.KART.LC.pendingTrades, 88), "and the trade is still owed")
    -- The refusal itself, not merely "something was printed": /kart add prints on its own account
    -- whatever happens here, so a bare non-empty check would be satisfied by that alone.
    T.truthy(table.concat(said, "\n"):find(lm.KART.L.LH_AWARD_STALE, 1, true),
        "and the refusal is said out loud (C14)")
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
    -- The parked line specifically, label and count together. This used to search the whole output
    -- for the character "1", which "History epoch: 1" already supplies on its own -- so hardcoding
    -- the parked count to zero, or deleting the line from LH.PrintStatus altogether, left the suite
    -- green (mutation testing, 2026-08-07). A status line nobody reads is exactly the hold nobody can
    -- see that this block exists to forbid.
    T.truthy(joined:find(lm.KART.L.LH_STATUS_PARKED .. ": 1", 1, true),
        "the status names the one parked request, on its own labelled line")
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
