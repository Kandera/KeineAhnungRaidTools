-- The Manifest, walked end to end: docs/MANIFEST.md, C1 through C12.
--
-- Every one of these twelve is already covered somewhere in tests/ -- as a scenario built for the
-- defect that produced it. This file is not that, and it is not a copy of it. It runs ONE raid
-- through ONE session and takes the twelve in order, the way an evening actually goes: items drop
-- while somebody is still arriving, a reload lands mid-distribution, the lootmaster walks out, raid
-- lead changes hands, and only then does the round end. The C-numbers are LABELS, not the order:
-- the order is the evening, and where the two disagree there is a comment saying why.
--
-- That sequence is the point. Every defect found on 2026-07-31 was state from one item leaking into
-- the next, or state a client lost that nothing restored -- B71's stamp outliving its roll, B74's
-- history entry taken by a later drop, B77's assignedWinners gone after a reload. Twelve isolated
-- scenarios cannot see any of those, because each of them starts from a clean raid.
--
-- A break here names a C-number, and the Manifest says what that one costs a raid night.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop = F.NewRaid, F.Drop

local NEWCOMER = { name = "Torvi", realm = "TarrenMill", guid = "Player-1096-0A1B2C42",
                   class = "MAGE", locale = "enUS" }

-- One raid, one session, from here to the end of the file. Nothing below re-creates it.
local sim, lm, council, raider = NewRaid()

-- C1 -- the session starts, and everybody is in it -------------------------------------------------
for _, c in ipairs(sim.clients) do
    T.eq(c.KART.LC.sessionActive, true, "C1: " .. c.name .. " is in the session")
end

-- C2 -- every raider runs on the raid's settings, not their own ------------------------------------
-- The EFFECTIVE values, not the saved ones: the whole class of bug is those two disagreeing. Alric
-- and Sinja have never had the raid's settings written into their own saved variables.
do
    local buttons = RaidSim.As(lm, lm.KART.LC.GetButtonConfig)
    local quality = RaidSim.As(lm, lm.KART.LC.GetRaidMinQuality)
    for _, c in ipairs(sim.clients) do
        T.deep_eq(RaidSim.As(c, c.KART.LC.GetButtonConfig), buttons,
            "C2: " .. c.name .. " reads the raid's vote buttons")
        T.eq(RaidSim.As(c, c.KART.LC.GetRaidMinQuality), quality,
            "C2: " .. c.name .. " reads the raid's minimum quality")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            "C2: " .. c.name .. " reads the raid's roll setting")
    end
end

-- C4 -- the item is force-won, by exactly one person -----------------------------------------------
Drop(sim, 1, F.GLOVES)
T.eq(KARTTEST.rolled[1] and KARTTEST.rolled[1][lm.unit], 1, "C4: the lootmaster force-wins it")
for _, c in ipairs(sim.clients) do
    if c ~= lm then
        T.truthy((KARTTEST.rolled[1] or {})[c.unit] ~= 1, "C4: " .. c.name .. " does not roll Need")
    end
end

-- C5 -- everybody sees the item, and their answer reaches the council -------------------------------
for _, c in ipairs(sim.clients) do
    T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[1]),
        "C5: " .. c.name .. " has the item, by name")
end
do
    -- Several people answering in the same instant, which is the case worth running.
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(1, 1) end)
    RaidSim.As(sim.byName.Sinja, function() sim.byName.Sinja.KART.LC.Vote.CastVote(1, 2) end)
    RaidSim.As(sim.byName.Corvin, function() sim.byName.Corvin.KART.LC.Vote.CastVote(1, 3) end)
    KARTTEST.AdvanceTime(0)

    for _, c in ipairs(F.CouncilOf(sim)) do
        for _, voter in ipairs({ raider, sim.byName.Sinja, sim.byName.Corvin }) do
            local v = (c.KART.LC.votes[1] or {})[voter.guid]
            T.truthy(v, "C5: " .. c.name .. " has " .. voter.name .. "'s answer")
            T.truthy(not RaidSim.As(c, function() return c.KART.LC.VoteLabelStale(v.count, c.KART.LC.GetButtonConfig()) end),
                "C5: and reads it under the label " .. voter.name .. " actually clicked")
        end
    end
end

-- C3 -- someone who turns up mid-session gets all of it --------------------------------------------
-- Deliberately AFTER an item is already on the table: a late arrival must get the config and the
-- session without being pulled into a distribution that was already running.
do
    local torvi = RaidSim.Join(sim, NEWCOMER)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(10)

    T.eq(torvi.KART.LC.sessionActive, true, "C3: the newcomer is in the session")
    T.deep_eq(RaidSim.As(torvi, torvi.KART.LC.GetButtonConfig),
              RaidSim.As(lm, lm.KART.LC.GetButtonConfig), "C3: on the raid's vote buttons")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled), true, "C3: and the raid's roll setting")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetLootmaster),
         RaidSim.As(lm, lm.KART.LC.GetLootmaster), "C3: and agrees who hands out the loot")
end

-- C6 -- collectibles, BoEs and anything below the threshold stay out --------------------------------
do
    Drop(sim, 2, F.MOUNT)
    Drop(sim, 3, F.PET)
    Drop(sim, 4, F.HOUSING)
    Drop(sim, 5, F.BOE, { bop = false })
    Drop(sim, 6, F.RARE)

    for _, id in ipairs({ 2, 3, 4, 5 }) do
        for _, c in ipairs(sim.clients) do
            T.truthy(not c.KART.LC.rollItems[id],
                "C6: " .. c.name .. " never sees roll " .. id .. " in Loot Council")
            T.truthy(not (KARTTEST.rolled[id] or {})[c.unit],
                "C6: and roll " .. id .. " is neither won nor passed for them")
        end
    end
    -- The rare-quality BoP is the one exception, and it is not Council either: it is cleared out
    -- rather than hoarded, which is a pass and not a win.
    T.eq(KARTTEST.rolled[6] and KARTTEST.rolled[6][lm.unit], 0,
        "C6: a below-threshold BoP is passed, not force-won")
end

-- C7 -- the award reaches the whole raid, once, and everyone agrees ---------------------------------
do
    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(1, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[1], raider.guid, "C7: " .. c.name .. " names the same winner")
    end
    T.truthy(F.Owes(lm.KART.LC.pendingTrades, 1), "C7: the holder owes it")
    T.truthy(F.Owes(raider.KART.LC.owedToMe, 1), "C7: and the winner is told")
    for _, c in ipairs(sim.clients) do
        if c ~= lm then
            T.truthy(not F.Owes(c.KART.LC.pendingTrades, 1),
                "C7: " .. c.name .. " is not asked to hand over an item they never held")
        end
    end
end

-- C8 -- a reload changes nothing --------------------------------------------------------------------
-- Mid-distribution and as a COUNCIL member: the case that has to
-- survive is deciding again afterwards (B77) on top of the clock surviving (B34).
do
    local lootedAt = lm.KART.LC.rollLootedAt[1]
    T.truthy(lootedAt, "C8: the trade clock was stamped when the boss died")

    RaidSim.Reload(sim, council.name)
    RaidSim.EnterWorld(sim, council.name)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    local back = sim.byName[council.name]

    T.eq(back.KART.LC.sessionActive, true, "C8: the session comes back")
    T.eq(lm.KART.LC.rollLootedAt[1], lootedAt, "C8: and the trade clock still dates from the boss")
    T.eq(back.KART.LC.assignedWinners[1], raider.guid,
        "C8: the client that reloaded still knows what was already decided")

    -- ...so deciding it again is a RE-decision, and the raid follows it.
    RaidSim.As(back, function()
        back.KART.LC.Trade.AssignWinner(1, sim.byName.Corvin.guid, "Upgrade")
        KARTTEST.AcceptPopup("KART_LC_REASSIGN_CONFIRM")
    end)
    KARTTEST.AdvanceTime(0)
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[1], sim.byName.Corvin.guid,
            "C8: " .. c.name .. " follows the re-decision")
    end
end

-- C10 -- raid lead moving does not cost the raid anything -------------------------------------------
-- BEFORE C9 on purpose. A promotion can only lose the designation while there IS one, and after the
-- lootmaster walks out there is not -- run the other way round this passed on an empty field against
-- an empty field and tested nothing, which a mutation showed. Lead moving while the lootmaster is
-- still here is also the common case; them leaving is the exception.
do
    local before = RaidSim.As(sim.byName.Alric, sim.byName.Alric.KART.LC.GetLootmaster)
    T.eq(before, lm.guid, "C10: the raid has a designation to lose")

    RaidSim.Promote(sim, "Sinja")          -- Sinja has never filled the Lootmaster field in
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetLootmaster), before,
            "C10: " .. c.name .. " keeps the designation across the promotion")
    end
    F.AssertAgreed(sim, nil, "C10: the raid still agrees on the config after raid lead moved")

    local owners = 0
    for _, c in ipairs(sim.clients) do
        if RaidSim.As(c, c.KART.LC.IsConfigOwner) then owners = owners + 1 end
    end
    T.eq(owners, 1, "C10: exactly one client owns the config")

    -- ...and the new leader's settings still reach the raid. THIS is the split: Sinja leads, Bramor
    -- is designated, and they are different people -- the normal shape, and the one where nothing
    -- reached anybody until 2026-07-31. The relay covers a client with NO config; a client holding a
    -- stale one asks for nothing, so the config owner re-broadcasting on the next roster change is
    -- the only thing that gets there. That re-broadcast sat behind a loot-owner gate, so a leader who
    -- had designated somebody else never sent and the designee's own send returned at the
    -- config-owner check. No C caught it until this was added.
    local leader = sim.byName.Sinja
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcMinQuality = 3
        leader.KART.LC.ApplyOwnConfig()
    end)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetRaidMinQuality), 3,
            "C10: " .. c.name .. " picks up the new leader's settings on the next roster change")
    end
end

-- C9 -- the loot flow survives the lootmaster walking out -------------------------------------------
do
    RaidSim.Leave(sim, lm.name)
    local leader = RaidSim.Promote(sim, "Corvin")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    RaidSim.As(leader, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")

    T.truthy(RaidSim.As(leader, leader.KART.LC.IsLootOwner),
        "C9: the raid leader stands in once they accept")
    local anyOwner = false
    for _, c in ipairs(sim.clients) do
        if RaidSim.As(c, c.KART.LC.IsLootOwner) then anyOwner = true break end
    end
    T.truthy(anyOwner, "C9: somebody owns the loot flow")

    -- ...and the flow really continues: a new item is force-won by the stand-in.
    Drop(sim, 8, F.WEAPON)
    T.eq(KARTTEST.rolled[8] and KARTTEST.rolled[8][leader.unit], 1,
        "C9: the stand-in force-wins the next item")
end

-- C12 -- set tokens go through the council ----------------------------------------------------------
-- The last boss, which is where tokens actually come from -- and the far side of C6: a token and a
-- mount sit in the same item class and are told apart only by subclass. Deliberately NOT next to C6,
-- because adjacent they would share a state the evening does not give them.
do
    local owner
    for _, c in ipairs(sim.clients) do
        if RaidSim.As(c, c.KART.LC.IsLootOwner) then owner = c break end
    end
    Drop(sim, 9, F.TOKEN)
    T.eq(KARTTEST.rolled[9] and KARTTEST.rolled[9][owner.unit], 1, "C12: a set token IS force-won")
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[9]),
            "C12: " .. c.name .. " can vote on it")
    end

    -- All the way through, because C12 says "force-won, announced, voted on, awarded, handed over".
    RaidSim.As(owner, function() owner.KART.LC.Trade.AssignWinner(9, sim.byName.Merrit.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[9], sim.byName.Merrit.guid,
            "C12: " .. c.name .. " names the token's winner")
    end
    T.truthy(F.Owes(owner.KART.LC.pendingTrades, 9), "C12: and the holder owes it")
end

-- C11 -- ending the round ends it for everyone ------------------------------------------------------
do
    local decider
    for _, c in ipairs(sim.clients) do
        if RaidSim.As(c, c.KART.LC.IsLootOwner) then decider = c break end
    end
    T.truthy(decider, "C11: somebody can end the round")

    RaidSim.As(decider, decider.KART.LC.EndRound)
    KARTTEST.AdvanceTime(0)

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.councilTabs, 0, "C11: " .. c.name .. " has no council cards left")
        T.eq(#c.KART.LC.voteListRolls, 0, "C11: " .. c.name .. " has no vote window left")
        T.eq(c.KART.LC.sessionActive, true, "C11: and " .. c.name .. " is still in the session")
    end
end
