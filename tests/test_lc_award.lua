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
