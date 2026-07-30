-- The Loot Council base flow, across several real clients at once.
--
-- The maintainer's own words for what has to hold, ten times out of ten, and what four raid nights
-- failed to deliver:
--
--     Items droppen, jeder kann das Item sehen, seinen Button drücken und das Council sieht das
--     und kann verteilen.
--
-- Everything here is that sentence, made executable. Each assertion names which half it defends.
-- The raid itself, the item fixtures and the verbs that drive them live in tests/lc_fixture.lua.

local F = dofile("tests/lc_fixture.lua")
local RaidSim, MEMBERS = F.RaidSim, F.MEMBERS
local NewRaid, Drop, Owes, CouncilOf = F.NewRaid, F.Drop, F.Owes, F.CouncilOf

-- ===================================================================================
-- The session and the config reach everybody
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()

    for _, c in ipairs({ council, raider }) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " sees the session as running")
        T.eq(c.KART.LC.raidConfig.lootmaster, lm.guid, c.name .. " knows who the lootmaster is")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            c.name .. " uses the RAID's roll setting, not their own default")
    end
    -- Wrapped, like every call into client code: "player" only means someone while that client is
    -- the one executing, which is exactly what makes a multi-client harness able to tell them apart.
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil), "a configured council member is council")
    T.truthy(not RaidSim.As(raider, raider.KART.LC.IsCouncil), "a plain raider is not")
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG"), 1, "the config went out exactly once")
end

-- ===================================================================================
-- "Jeder kann das Item sehen"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 41, 249331)

    for _, c in ipairs(sim.clients) do
        local link = c.KART.LC.rollItems[41]
        T.truthy(c.KART.LC.IsRealItemLink(link), c.name .. " holds a real item link, not a placeholder")
        T.truthy(tostring(link):find("Ezzorak", 1, true), c.name .. " holds the RIGHT item")

        local listed = false
        for _, id in ipairs(c.KART.LC.voteListRolls) do if id == 41 then listed = true end end
        T.truthy(listed, c.name .. " has the item in their vote window")
    end

    -- The lootmaster has to physically win it to be able to trade it onward.
    T.eq(KARTTEST.rolled[41] and KARTTEST.rolled[41][lm.unit], 1, "the lootmaster rolled Need")
    T.eq(KARTTEST.rolled[41] and KARTTEST.rolled[41][raider.unit], 0, "a raider auto-passed")
    T.truthy(council.KART.LC.councilTabs[1] == 41, "the council panel has a tab for it")
end

-- ===================================================================================
-- "Seinen Button drücken und das Council sieht das"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 42, 249331)

    RaidSim.As(raider,  function() raider.KART.LC.Vote.CastVote(42, 1) end)
    RaidSim.As(council, function() council.KART.LC.Vote.CastVote(42, 2) end)

    local votes = lm.KART.LC.votes[42] or {}
    T.truthy(votes[raider.guid], "the lootmaster sees the raider's vote")
    T.truthy(votes[council.guid], "the lootmaster sees the council member's vote")
    T.eq(votes[raider.guid] and votes[raider.guid].idx, 1, "and the raider's choice is the one they pressed")
    T.eq(votes[council.guid] and votes[council.guid].idx, 2, "and the council member's is theirs")

    -- The count travels with the vote so a client with a different button list says "unknown"
    -- instead of confidently showing the wrong label. That guard is why a whole evening's votes
    -- were once read wrong.
    T.eq(votes[raider.guid] and votes[raider.guid].count,
        #RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
        "the vote carries the sender's button count")
end

-- ===================================================================================
-- "Und kann verteilen"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 43, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(43, 1) end)

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(43, raider.guid, "BIS") end)

    T.eq(lm.KART.LC.assignedWinners[43], raider.guid, "the lootmaster recorded the winner")
    T.eq(council.KART.LC.assignedWinners[43], raider.guid, "and the council sees the same winner")
    T.truthy(lm.KART.LC.pendingTrades and next(lm.KART.LC.pendingTrades),
        "the lootmaster is reminded to hand it over")

    -- Whoever decided it must not be left staring at a live vote row for an item already given out.
    for _, c in ipairs(sim.clients) do
        for _, id in ipairs(c.KART.LC.voteListRolls) do
            T.truthy(id ~= 43, c.name .. " no longer has the decided item in their vote window")
        end
    end
end

-- ===================================================================================
-- A client that never got its own loot roll still sees the item
-- ===================================================================================
-- Dead, out of range, ineligible, or simply beaten to it by the addon message. This is GitHub #12,
-- #13 and #16, reported by three people in one evening -- one of whom was alive and in range the
-- whole time, which is why the fix cannot depend on the reason.
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 44, 249293, { noRollFor = { Odin = true } })

    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[44]),
        "a client with no loot roll of its own still ends up with a real link")
    T.truthy(tostring(raider.KART.LC.rollItems[44]):find("Weight of Command", 1, true),
        "and it is the right item")
end

-- The same, with the item not yet in the client's cache: the name cannot be known yet, but the
-- icon can, and the link must upgrade itself the moment the item arrives.
do
    local sim, _, _, raider = NewRaid()
    KARTTEST.items[249293].cached = false
    Drop(sim, 45, 249293, { noRollFor = { Odin = true } })

    local parked = raider.KART.LC.rollItems[45]
    T.truthy(tostring(parked):find("item:249293", 1, true),
        "an uncached item is tracked by its ID rather than lost as '???'")

    KARTTEST.AdvanceTime(10)      -- exhaust the retry budget
    KARTTEST.CacheItem(249293)    -- the client finally learns the item
    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[45]),
        "and it becomes a real link once the item is known, however late")
    KARTTEST.items[249293].cached = nil
end

-- ===================================================================================
-- Tier tokens are ordinary Council loot; mounts are not
-- ===================================================================================
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 46, 249364)

    T.eq(KARTTEST.rolled[46] and KARTTEST.rolled[46][lm.unit], 1,
        "the lootmaster force-wins a tier token (GitHub #14)")
    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[46]),
        "and every raider gets to vote on it")
end

-- ===================================================================================
-- The 1-100 roll: mandatory, from everybody, visible to everybody
-- ===================================================================================
-- Opt-in raid-wide, and this raid has it on. It is the council's tie-breaker, so a roll that only
-- some clients produce is worse than none at all -- that is what "rolls kommen nicht an von allen"
-- looked like from the council panel.
do
    local sim, lm = NewRaid()
    Drop(sim, 50, 249331)

    local rolls = lm.KART.LC.rolls[50] or {}
    for _, c in ipairs(sim.clients) do
        local r = rolls[c.guid]
        T.truthy(r, "the lootmaster sees a roll from " .. c.name)
        T.truthy(type(r) == "number" and r >= 1 and r <= 100,
            c.name .. "'s roll is a number between 1 and 100")
    end

    -- Every council member scores against the same numbers, so they must agree exactly.
    for _, c in ipairs(CouncilOf(sim)) do
        for _, other in ipairs(sim.clients) do
            T.eq((c.KART.LC.rolls[50] or {})[other.guid], rolls[other.guid],
                c.name .. " sees the same roll for " .. other.name .. " as the lootmaster does")
        end
    end

    -- Exactly one roll per client per item: rolling twice would let someone re-roll a bad number.
    T.eq(#RaidSim.Sent(sim, "LC_ROLL:50:"), #sim.clients,
        "each client broadcast its roll exactly once")
end

-- With rolls switched off raid-wide, nobody rolls -- and nobody half-rolls.
do
    local sim, lm = NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    Drop(sim, 51, 249331)
    for _, c in ipairs(sim.clients) do
        T.truthy(not (lm.KART.LC.rolls[51] or {})[c.guid],
            "with rolls off raid-wide, " .. c.name .. " did not roll")
    end
end

-- ===================================================================================
-- The council decides together
-- ===================================================================================
do
    local sim, _, _, raider = NewRaid()
    local nara = sim.byName.Nara
    Drop(sim, 52, 249331)

    -- Both raiders declare an interest.
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(52, 1) end)
    RaidSim.As(nara,   function() nara.KART.LC.Vote.CastVote(52, 2) end)

    -- Every council member sees both, identically. A council scoring different ballots is the
    -- failure that cannot be noticed from inside the game.
    for _, c in ipairs(CouncilOf(sim)) do
        local v = c.KART.LC.votes[52] or {}
        T.eq(v[raider.guid] and v[raider.guid].idx, 1, c.name .. " sees Odin's vote")
        T.eq(v[nara.guid] and v[nara.guid].idx, 2, c.name .. " sees Nara's vote")
    end

    -- The straw poll: two council members pick Odin, one picks Nara.
    local council = CouncilOf(sim)
    RaidSim.As(council[1], function() council[1].KART.LC.Vote.ToggleCouncilVote(52, raider.guid) end)
    RaidSim.As(council[2], function() council[2].KART.LC.Vote.ToggleCouncilVote(52, raider.guid) end)
    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(52, nara.guid) end)

    for _, c in ipairs(council) do
        local poll = c.KART.LC.councilVotes[52] or {}
        T.eq(poll[council[1].guid], raider.guid, c.name .. " sees Kandera's pick")
        T.eq(poll[council[2].guid], raider.guid, c.name .. " sees Haerri's pick")
        T.eq(poll[council[3].guid], nara.guid,   c.name .. " sees Wuusch's pick")
    end

    -- Clicking the same candidate again retracts, and that reaches everyone too.
    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(52, nara.guid) end)
    for _, c in ipairs(council) do
        T.truthy(not (c.KART.LC.councilVotes[52] or {})[council[3].guid],
            c.name .. " sees Wuusch's pick retracted")
    end
end

-- A council member who is not the lootmaster may award, and everyone converges on it -- including
-- the lootmaster, who is the one who physically holds the item.
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 53, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(53, 1) end)

    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(53, raider.guid, "BIS") end)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[53], raider.guid,
            c.name .. " agrees on the winner a non-lootmaster council member picked")
    end
    T.truthy(lm.KART.LC.pendingTrades and next(lm.KART.LC.pendingTrades),
        "and the lootmaster -- not the assigner -- is the one reminded to trade it")
end

-- ===================================================================================
-- German and English clients in one raid must read the same vote the same way
-- ===================================================================================
-- The default button labels are localised -- "Other" against "Sonstiges" -- so language is a real
-- source of the one failure that cannot be seen from inside the game: two clients resolving the
-- same vote index to different words. The raid config is what makes them agree, which is also why
-- a raid where nobody distributes one is dangerous rather than merely degraded.
do
    local sim, lm = NewRaid()
    local de, en = sim.byName.Haerri, sim.byName.Wuusch
    T.eq(de.locale, "deDE", "the raid really does contain a German client")
    T.eq(en.locale, "enUS", "and an English one")

    local labelsOf = function(c)
        local out = {}
        for i, def in ipairs(RaidSim.As(c, c.KART.LC.GetButtonConfig)) do out[i] = def.label end
        return out
    end

    T.deep_eq(labelsOf(de), labelsOf(en),
        "with a raid config in force, a German and an English client read identical vote buttons")
    T.deep_eq(labelsOf(lm), labelsOf(en), "and both match the lootmaster's")

    -- And the votes themselves survive the round trip between them.
    Drop(sim, 54, 249331)
    RaidSim.As(en, function() en.KART.LC.Vote.CastVote(54, 4) end)
    local v = de.KART.LC.votes[54] or {}
    T.eq(v[en.guid] and v[en.guid].idx, 4, "a German client receives an English client's vote")
    T.eq(v[en.guid] and v[en.guid].count, #RaidSim.As(de, de.KART.LC.GetButtonConfig),
        "and agrees with it about how many buttons there were, so no mismatch is flagged")
end

-- ===================================================================================
-- A raid that never filled in the Lootmaster field
-- ===================================================================================
-- A documented, supported setup: leave it empty and the raid leader stands in. It used to stand in
-- for the LOOT half only -- the config half had no owner at all, so no client ever received one and
-- every raider silently ran their own vote buttons, their own minimum quality and their own roll
-- setting, which defaults to off. A whole raid not rolling, with the role-status label reporting
-- that all was well (B33).
do
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)
    local lm, council, raider = sim.byName.Kandera, sim.byName.Haerri, sim.byName.Odin

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster     = ""        -- deliberately blank
        lm.env.KART_Settings.lcCouncilMembers = "Kandera;Haerri;Wuusch"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "the raid leader owns the config when nobody is named")
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG"), 1, "so a config is broadcast after all")

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " is in the session")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            c.name .. " uses the raid's roll setting rather than their own")
        T.deep_eq(RaidSim.As(c, c.KART.LC.GetButtonConfig),
                  RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
            c.name .. " reads the same vote buttons as the leader")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil),
        "and the council list reached the council")

    Drop(sim, 72, 249331)
    T.eq(KARTTEST.rolled[72] and KARTTEST.rolled[72][lm.unit], 1,
        "the stand-in still force-wins the item")
    T.truthy((lm.KART.LC.rolls[72] or {})[raider.guid], "and the raid rolls on it")
end

-- Without a config, the same two clients disagree -- documented here because it is exactly what a
-- raid with no lootmaster set looks like, and the reason that state now prints a warning.
do
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)
    local de, en = sim.byName.Haerri, sim.byName.Wuusch
    local deLabels = RaidSim.As(de, de.KART.LC.GetButtonConfig)
    local enLabels = RaidSim.As(en, en.KART.LC.GetButtonConfig)
    T.truthy(deLabels[4].label ~= enLabels[4].label,
        "with no config distributed, a German and an English client name the same index differently")
end

-- ===================================================================================
-- The council's own controls: reassign, no winner, end round, notes
-- ===================================================================================
-- Every one of these changes what other people see, so every one of them is a place where two
-- clients can end up disagreeing. They are asserted from more than one client for that reason.
do
    local sim, lm, _, raider = NewRaid()
    local nara = sim.byName.Nara
    Drop(sim, 60, 249331)

    -- Award, then reassign to someone else. The second decision has to win everywhere, and the
    -- first winner's claim has to be gone -- not merely overwritten on the assigner's screen.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(60, raider.guid, "BIS") end)
    -- Reassigning asks first, deliberately: it is how an accidental double award is caught.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(60, nara.guid, "Upgrade") end)
    T.truthy(RaidSim.As(lm, KARTTEST.AcceptPopup, "KART_LC_REASSIGN_CONFIRM"),
        "reassigning a winner asks for confirmation first")

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[60], nara.guid, c.name .. " sees the reassigned winner")
    end
    T.truthy(not Owes(raider.KART.LC.owedToMe, 60), "the first winner is no longer owed the item")
    T.truthy(Owes(nara.KART.LC.owedToMe, 60), "and the new winner is")
end

do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 61, 249331)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(61, raider.guid, "BIS") end)

    -- "No winner" revokes: nobody is owed it, nobody has to trade it, and the tab is gone for the
    -- council too, since that decision is broadcast.
    -- Exactly what the panel's "No Winner" button does, in its order. The assigner never receives
    -- its own broadcast, so every step it performs for the raid it must also perform for itself.
    RaidSim.As(lm, function()
        lm.KART.LC.Trade.AnnounceResult(61, "NONE")
        lm.KART.LH.RemoveHistoryForRoll(61)
        lm.KART.LC.Trade.ClearWinnerObligations(61)
        lm.KART.LC.Council.CloseCouncilTab(61)
    end)

    T.truthy(not Owes(raider.KART.LC.owedToMe, 61), "revoking clears the winner's claim")
    for _, c in ipairs(sim.clients) do
        T.truthy(not c.KART.LC.assignedWinners[61], c.name .. " no longer shows a winner")
    end
end

do
    local sim, lm = NewRaid()
    Drop(sim, 62, 249331)
    Drop(sim, 63, 249293)

    -- End Round is the one bulk clear, and it has to reach everybody -- this is GitHub #15, where
    -- previous bosses' items stayed on the council panel.
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.councilTabs, 0, c.name .. " has no council tabs left after End Round")
        T.eq(#c.KART.LC.voteListRolls, 0, c.name .. " has no vote rows left either")
        T.truthy(not c.KART.LC.rollItems[62], c.name .. " forgot the first item")
        T.truthy(not c.KART.LC.rollItems[63], c.name .. " forgot the second item")
    end
    -- The session itself keeps running: End Round ends a distribution, not the evening.
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " is still in the session")
    end
end

do
    local sim, _, council, raider = NewRaid()

    -- An officer note is council-only information about a player, and it has to reach the other
    -- council members without reaching the player it is about.
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(raider.guid, "hat letzte Woche BIS bekommen")
    end)

    for _, c in ipairs(CouncilOf(sim)) do
        T.eq(c.env.KART_LCOfficerNotes[raider.guid], "hat letzte Woche BIS bekommen",
            c.name .. " sees the officer note")
    end
end

-- ===================================================================================
-- Handing the item over
-- ===================================================================================
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 64, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(64, 1) end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(64, raider.guid, "BIS") end)

    T.truthy(Owes(lm.KART.LC.pendingTrades, 64), "the lootmaster owes the item")
    T.truthy(Owes(raider.KART.LC.owedToMe, 64), "and the winner knows they are owed it")

    -- The trade happens: the obligation goes with the item.
    RaidSim.As(lm, function() lm.KART.LC.Trade.RemovePendingTrade(64) end)
    T.truthy(not Owes(lm.KART.LC.pendingTrades, 64),
        "the reminder clears once the item has been handed over")
end

-- ===================================================================================
-- NSRT nicknames
-- ===================================================================================
-- The guild runs Northern Sky, so the lootmaster field and the council list are often filled in
-- with nicknames rather than character names. Before 3.1.0 a client that could not read a nickname
-- rejected EVERY raid config, silently and permanently -- which is how a whole raid ended up on its
-- own vote buttons and never rolling. This is that path.
do
    KARTTEST.SetNSAPI(true)
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    members[1].nickname = "Kandy"    -- the lootmaster is known by a nickname
    members[2].nickname = "Haeri"

    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, council, raider = sim.byName.Kandera, sim.byName.Haerri, sim.byName.Odin

    RaidSim.As(lm, function()
        -- Typed the way the raid leader actually types it: nicknames, not character names.
        lm.env.KART_Settings.lcLootmaster     = "Kandy"
        lm.env.KART_Settings.lcCouncilMembers = "Kandy;Haeri"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "a lootmaster who typed their own NICKNAME still owns the config")
    for _, c in ipairs({ council, raider }) do
        T.eq(c.KART.LC.raidConfig.lootmaster, lm.guid,
            c.name .. " resolved the nickname to the right player")
        T.eq(c.KART.LC.sessionActive, true, c.name .. " got the session")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil),
        "a council member listed by nickname is council")

    Drop(sim, 70, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(70, 1) end)
    T.truthy((lm.KART.LC.votes[70] or {})[raider.guid],
        "and the whole loot flow still works with nicknames in play")

    KARTTEST.SetNSAPI(false)
end

-- ONE client in the raid cannot read nicknames -- Northern Sky missing, or its global sharing
-- switched off. That client must still end up with the raid's config. Before 3.1.0 it rejected
-- every config forever and silently fell back to its own vote buttons and its own roll setting,
-- which is how a full raid stopped rolling without anyone being able to see why.
do
    KARTTEST.SetNSAPI(true)
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    members[1].nickname = "Kandy"
    members[4].nsrt = false          -- Odin, blind to nicknames

    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, raider = sim.byName.Kandera, sim.byName.Odin

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster   = "Kandy"
        lm.env.KART_Settings.lcRollsEnabled = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.eq(raider.KART.LC.sessionActive, true,
        "a client that cannot read nicknames still joins the session")
    T.eq(raider.KART.LC.raidConfig.lootmaster, lm.guid,
        "and accepts the config on the sender's identity rather than the name it cannot resolve")
    T.eq(RaidSim.As(raider, raider.KART.LC.GetRollsEnabled), true,
        "and uses the RAID's roll setting, not its own -- this is what broke before 3.1.0")

    Drop(sim, 71, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(71, 1) end)
    T.truthy((lm.KART.LC.votes[71] or {})[raider.guid],
        "and votes normally for the rest of the evening")
    KARTTEST.SetNSAPI(false)
end

-- The other half of the same problem, and the one that actually bit last night: the LOOTMASTER
-- types a nickname their OWN client cannot resolve. Then nobody owns the config, nothing is
-- broadcast, and the session starts anyway -- so every raider silently keeps their own roll setting,
-- which defaults to off. This is why that state now prints a warning instead of passing in silence.
do
    KARTTEST.SetNSAPI(false)     -- nobody can resolve nicknames
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, raider = sim.byName.Kandera, sim.byName.Odin

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster   = "Kandy"   -- resolves to nobody, not even themselves
        lm.env.KART_Settings.lcRollsEnabled = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(not RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "a lootmaster whose own nickname does not resolve does not own the config")
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG"), 0, "so no config is broadcast at all")
    T.eq(raider.KART.LC.sessionActive, true, "while the session starts regardless")
    T.eq(RaidSim.As(raider, raider.KART.LC.GetRollsEnabled), false,
        "and every raider falls back to their own roll setting, which is off -- the missing rolls")
end
