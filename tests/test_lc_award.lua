-- B35: two council members award the same item at the same moment.
--
-- Assigning is deliberately open to the whole council, and the double-assign guard reads
-- LC.assignedWinners[rollID] LOCALLY. Addon messages never echo to their sender, so two assigners
-- each see nil, each broadcast, and each overwrites the other's record on receipt: the two of them
-- end up permanently swapped, and every other client keeps whichever message happened to arrive last
-- -- which is not the same message on every client, because two senders' messages interleave freely.
--
-- What gets traded is then whatever the lootmaster's copy says, and nobody has any reason to suspect
-- the council panel in front of them is showing a different winner than the next person's.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local function Capture(fn)
    local lines = {}
    local realPrint = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end

-- Two council members, same item, neither having seen the other ------------------------------------
do
    local sim, lm, council = F.NewRaid()
    -- The lootmaster is the second assigner, not Corvin: Corvin runs with lcHideIrrelevant on in the
    -- fixture, so an item he cannot use is auto-answered and dropped from his tracking, and he would
    -- have nothing to assign. Lootmaster plus one council member clicking at once is the likelier
    -- shape anyway -- the lootmaster is the one person looking at every single drop.
    local corvin = lm
    F.Drop(sim, 60, F.GLOVES)

    local alric, sinja = sim.byName.Alric, sim.byName.Sinja

    -- Both assign before either message is delivered, which is what "at the same time" means on the
    -- wire. RaidSim drains the queue when control returns to the test, so the two sends are staged
    -- inside one As() block each and the deliveries interleave afterwards.
    -- HELD, not dropped (RaidSim.Hold): the harness delivers to peers immediately, so without this
    -- the second assigner always sees the first one's decision and takes the reassign path instead --
    -- which is the opposite of the case under test. Holding the results models what "at the same
    -- moment" means on a real wire: both decisions made before either has landed anywhere.
    RaidSim.Hold(sim, "LC_RESULT")
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(60, alric.guid, "BIS", nil)
    end)
    RaidSim.As(corvin, function()
        corvin.KART.LC.Trade.AssignWinner(60, sinja.guid, "BIS", nil)
    end)
    local out = Capture(function()
        T.eq(RaidSim.Release(sim, "LC_RESULT"), 2, "both awards were on the wire before either landed")
        KARTTEST.AdvanceTime(0)
    end)
    T.truthy(not KARTTEST.popups["KART_LC_REASSIGN_CONFIRM"],
        "neither of them saw a reassign dialog, which is what makes this a clash")

    -- The raid must end up with ONE answer. Which one is not the point -- neither council member is
    -- more right than the other -- but every client showing the same one is, because the item is
    -- physically handed over on the strength of it.
    local winners = {}
    for _, c in ipairs(sim.clients) do
        winners[#winners + 1] = c.name .. "=" .. tostring(c.KART.LC.assignedWinners[60])
    end
    local first = sim.clients[1].KART.LC.assignedWinners[60]
    local agreed = true
    for _, c in ipairs(sim.clients) do
        if c.KART.LC.assignedWinners[60] ~= first then agreed = false end
    end
    T.truthy(agreed, "every client agrees who won: " .. table.concat(winners, " "))
    T.truthy(first == alric.guid or first == sinja.guid, "and it is one of the two people chosen")

    -- Silence is the other half of the defect: two people decided the same item and neither was told.
    T.truthy(out:find(lm.KART.L.LC_AWARD_CLASH:sub(1, 24), 1, true),
        "and the clash is said out loud rather than resolved behind their backs")

    -- Exactly one pending trade on the loot owner: the losing award must not leave an obligation
    -- behind, or the lootmaster hands the item to the wrong person and ticks it off.
    T.eq(#lm.KART.LC.pendingTrades, 1, "the loot owner owes exactly one item")
    T.eq(lm.KART.LC.pendingTrades[1].winnerKey, first, "to the winner everybody agrees on")
end

-- A deliberate reassignment still wins ---------------------------------------------------------------
-- The clash rule must not turn into "the first award can never be changed": reassigning is a
-- first-class feature, confirmed by a human in front of a dialog that names both players.
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 61, F.GLOVES)
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja

    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(61, alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[61], alric.guid, c.name .. " has the first winner")
    end

    -- Now the same council member changes their mind, which routes through the confirm dialog.
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(61, sinja.guid, "Upgrade", nil)
        KARTTEST.AcceptPopup("KART_LC_REASSIGN_CONFIRM")
    end)
    KARTTEST.AdvanceTime(0)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[61], sinja.guid, c.name .. " follows the reassignment")
    end
    T.eq(#lm.KART.LC.pendingTrades, 1, "and the loot owner still owes exactly one item")
    T.eq(lm.KART.LC.pendingTrades[1].winnerKey, sinja.guid, "to the new winner")
end

-- The same clash, resolved the same way, whichever award lands first --------------------------------
-- This is the property the rule actually has to have. "Every client agrees" can be satisfied by
-- accident on one arrival order; two senders' messages interleave freely, so a client that hears A
-- then B and one that hears B then A must land in the same place. Both halves of the rule are
-- commutative for that reason, and this is what says so.
local function ClashWinner(reverse)
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 62, F.GLOVES)
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja

    RaidSim.Hold(sim, "LC_RESULT")
    local first, second = council, lm
    local firstPick, secondPick = alric.guid, sinja.guid
    if reverse then
        first, second = lm, council
        firstPick, secondPick = sinja.guid, alric.guid
    end
    RaidSim.As(first, function() first.KART.LC.Trade.AssignWinner(62, firstPick, "BIS", nil) end)
    RaidSim.As(second, function() second.KART.LC.Trade.AssignWinner(62, secondPick, "BIS", nil) end)
    Capture(function()
        RaidSim.Release(sim, "LC_RESULT")
        KARTTEST.AdvanceTime(0)
    end)

    local agreed = sim.clients[1].KART.LC.assignedWinners[62]
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[62], agreed,
            c.name .. " agrees (reverse=" .. tostring(reverse) .. ")")
    end
    return agreed
end

T.eq(ClashWinner(false), ClashWinner(true),
    "the same two awards produce the same winner whichever order they land in")

-- A confirmed reassignment survives a first award that arrives late -------------------------------
-- The rank has to be recorded when an award is RECEIVED, not only when it is made here. A council
-- member whose client never saw the reassignment -- their copy of it was lost, which is what the
-- chat throttle does -- assigns the original winner and broadcasts a first award. Without the
-- received rank every peer would treat that as an ordinary clash and fall back to the smaller key,
-- undoing a decision a human confirmed in front of a dialog naming both players.
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 63, F.GLOVES)
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    T.truthy(alric.guid < sinja.guid, "Alric sorts first, so the tie-break would pick him")

    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(63, alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)

    -- Confirmed reassignment to the player the tie-break would NOT pick.
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(63, sinja.guid, "Upgrade", nil)
        KARTTEST.AcceptPopup("KART_LC_REASSIGN_CONFIRM")
    end)
    KARTTEST.AdvanceTime(0)
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[63], sinja.guid, c.name .. " has the reassigned winner")
    end

    -- The lootmaster's copy of the reassignment was lost, so their client still believes nobody has
    -- been assigned and makes a FIRST award for the original winner.
    lm.KART.LC.assignedWinners[63] = nil
    lm.KART.LC.assignedDeliberate[63] = nil
    Capture(function()
        RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(63, alric.guid, "BIS", nil) end)
        KARTTEST.AdvanceTime(0)
    end)

    for _, c in ipairs(sim.clients) do
        if c ~= lm then
            T.eq(c.KART.LC.assignedWinners[63], sinja.guid,
                c.name .. " keeps the confirmed reassignment")
        end
    end
end

-- B61/B52: a config that arrives AFTER the item did ------------------------------------------------
-- Council membership was evaluated once, at roll start, by the four sites that open the panel. A
-- client whose config lands afterwards -- a late retry, a state-request reply -- is council from that
-- moment on, but had no tab for the items already on the table and could not assign them. The panel
-- also kept rendering votes under the previous label set (B52), on the one screen that decides who
-- gets the item.
do
    local sim, lm = F.NewRaid()
    local corvin = sim.byName.Corvin

    -- A client that has not received the config yet: no council list, so not council.
    wipe(corvin.KART.LC.raidConfig)
    corvin.KART.LC.CouncilNamesTable = {}
    T.truthy(not RaidSim.As(corvin, corvin.KART.LC.IsCouncil), "not council while the config is missing")

    F.Drop(sim, 70, F.GLOVES)
    -- Past the window a drop is collected in, so the announcement has landed and this client is
    -- running the same vote clock as everybody else.
    KARTTEST.AdvanceTime(1)
    T.truthy(corvin.KART.LC.rollItems[70], "but the item still reaches them")
    T.eq(#corvin.KART.LC.councilTabs, 0, "with no council tab, because they are not council yet")

    local deadlineBefore = corvin.KART.LC.rollDeadlines[70]
    KARTTEST.AdvanceTime(5)

    -- The config finally lands.
    RaidSim.As(lm, function() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    T.truthy(RaidSim.As(corvin, corvin.KART.LC.IsCouncil), "the config makes them council")
    T.eq(#corvin.KART.LC.councilTabs, 1, "and the item already on the table gets its tab")
    T.eq(corvin.KART.LC.councilTabs[1], 70, "the right one")

    -- The remaining time is carried across, not restarted: the council decides when the shortest
    -- clock runs out, and a late arrival must not be looking at a longer vote than everybody else.
    T.truthy(deadlineBefore and corvin.KART.LC.rollDeadlines[70] <= deadlineBefore + 0.001,
        "with the vote it has left, not a fresh one")
end

do
    -- A roll whose vote is already over is not put back on the table. The deadline is pushed into the
    -- past directly rather than by advancing the clock: the pruner would otherwise drop the roll
    -- outright and the assertion would pass without the guard ever being consulted.
    local sim, lm = F.NewRaid()
    local corvin = sim.byName.Corvin
    wipe(corvin.KART.LC.raidConfig)
    corvin.KART.LC.CouncilNamesTable = {}
    F.Drop(sim, 71, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    corvin.KART.LC.rollDeadlines[71] = GetTime() - 1
    T.truthy(corvin.KART.LC.rollItems[71], "the roll is still tracked, so the guard is what decides")

    RaidSim.As(lm, function() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)
    for _, rid in ipairs(corvin.KART.LC.councilTabs) do
        T.truthy(rid ~= 71, "an expired roll is not reopened as a tab")
    end
end

do
    -- B52's own half: an OPEN council panel is repainted when a config lands, so the votes stop being
    -- rendered under the previous label set. Spied rather than rendered -- the stub panel draws
    -- nothing, and what matters is that the repaint is asked for.
    local sim, lm = F.NewRaid()
    local corvin = sim.byName.Corvin
    F.Drop(sim, 72, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    corvin.KART.LC.councilPanel:Show()

    local repainted = 0
    local orig = corvin.KART.LC.Council.RefreshCouncilRows
    corvin.KART.LC.Council.RefreshCouncilRows = function(...) repainted = repainted + 1 return orig(...) end
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "A;B;C;D;E"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    corvin.KART.LC.Council.RefreshCouncilRows = orig

    T.truthy(repainted > 0, "an open council panel is repainted when a config is accepted")
    T.deep_eq(RaidSim.As(corvin, corvin.KART.LC.GetButtonConfig),
              RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
        "and it is reading the new labels")
end

-- ===================================================================================
-- The reminder windows reopen with what is owed NOW
-- ===================================================================================
-- Found in the bug run for B51, which fixed the same defect in `/kart lc`: both reminder windows
-- only HIDE on their "x", and every removal path deliberately refuses to reopen a closed one
-- (Trade.RefreshTradeReminderIfShown). So a row ticked off, traded away or timed out while the
-- window was shut stayed in the frame's row pool, and `/kart trade` put that picture back on screen
-- -- an item the lootmaster had already handed over, still listed as owed.
local function ShownRows(frame)
    if not frame then return 0 end
    local n = 0
    for _, row in ipairs(frame.rows or {}) do if row:IsShown() then n = n + 1 end end
    return n
end

do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 70, F.GLOVES)
    F.Drop(sim, 71, F.WEAPON)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(70, sim.byName.Alric.guid, "BIS", nil)
        council.KART.LC.Trade.AssignWinner(71, sim.byName.Sinja.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(#lm.KART.LC.pendingTrades, 2, "the lootmaster owes two items")
    T.eq(ShownRows(lm.KART.LC.tradeReminderFrame), 2, "and both are listed")

    -- The lootmaster closes the list, then hands one of them over.
    lm.KART.LC.tradeReminderFrame:Hide()
    RaidSim.As(lm, function() lm.KART.LC.Trade.RemovePendingTrade(70) end)
    T.eq(#lm.KART.LC.pendingTrades, 1, "one obligation is settled")
    T.eq(ShownRows(lm.KART.LC.tradeReminderFrame), 2,
        "but the closed window still holds the layout it last drew")

    RaidSim.As(lm, function() lm.KART.LC.ReopenTradeReminder() end)
    T.truthy(lm.KART.LC.tradeReminderFrame:IsShown(), "/kart trade brings the list back")
    T.eq(ShownRows(lm.KART.LC.tradeReminderFrame), 1, "showing what is still owed, not what was")
end

do
    -- The winner's side of the same window, and the same command shape (/kart owed).
    local sim, _, council = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 72, F.GLOVES)
    F.Drop(sim, 73, F.WEAPON)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(72, alric.guid, "BIS", nil)
        council.KART.LC.Trade.AssignWinner(73, alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(ShownRows(alric.KART.LC.owedReminderFrame), 2, "the winner is owed two items")

    alric.KART.LC.owedReminderFrame:Hide()
    RaidSim.As(alric, function() alric.KART.LC.Trade.RemoveOwedItem(72) end)
    RaidSim.As(alric, function() alric.KART.LC.ReopenOwedReminder() end)
    T.eq(ShownRows(alric.KART.LC.owedReminderFrame), 1,
        "/kart owed lists only what has not arrived yet")
end
