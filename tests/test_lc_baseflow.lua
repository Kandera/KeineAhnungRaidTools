-- The Loot Council base flow, across several real clients at once.
--
-- The maintainer's own words for what has to hold, ten times out of ten, and what four raid nights
-- failed to deliver:
--
--     Items droppen, jeder kann das Item sehen, seinen Button drücken und das Council sieht das
--     und kann verteilen.
--
-- Everything here is that sentence, made executable. Each assertion names which half it defends.
-- Item fixtures are real drops from the guild's own loot history, with the classID/subclassID the
-- live client reports -- invented IDs were what let the tier-token bug hide.

local RaidSim = dofile("tests/raidsim.lua")

KARTTEST.AddItem({ id = 249331, name = "Ezzorak's Gloombind", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 4, equipLoc = "INVTYPE_HAND", bind = 1 })
KARTTEST.AddItem({ id = 249293, name = "Weight of Command", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 4, equipLoc = "INVTYPE_2HWEAPON", bind = 1 })
KARTTEST.AddItem({ id = 249364, name = "Voidcured Unraveled Nullcore", quality = 4, ilvl = 285,
                   classID = 15, subclassID = 0, bind = 1 })

-- A council of three plus two plain raiders. More than one council member is the point: the whole
-- feature is several people deciding together, and a "council" of one cannot show a tally going out
-- of sync, a straw poll disagreeing, or a second council member's assignment reaching the first.
--
-- Every raider also runs a DIFFERENT combination of the personal switches, because a raid where
-- everyone is on defaults is a raid nobody has. The base flow has to hold for all of them at once:
-- whatever someone has switched on for themselves, the council must still see their answer.
local SETTINGS = {
    Kandera = {},                                                    -- lootmaster, defaults
    Haerri  = { lcAutoPass = false },                                -- clicks Blizzard's roll himself
    Wuusch  = { lcHideIrrelevant = true },                           -- hides what he cannot equip
    Odin    = { lcAutoTransmogVote = true },                         -- wants the appearances
    Nara    = { lcHideIrrelevant = true, lcAutoTransmogVote = true },-- both
}

local MEMBERS = {
    { name = "Kandera", realm = "Blackmoore", guid = "Player-1-K", class = "DEATHKNIGHT", leader = true, locale = "deDE" },
    { name = "Haerri",  realm = "Blackmoore", guid = "Player-1-H", class = "DRUID",       locale = "deDE" },
    { name = "Wuusch",  realm = "Blackmoore", guid = "Player-1-W", class = "PALADIN",     locale = "enUS" },
    { name = "Odin",    realm = "Blackmoore", guid = "Player-1-O", class = "MAGE",        locale = "enUS" },
    { name = "Nara",    realm = "Blackmoore", guid = "Player-1-N", class = "PRIEST",      locale = "deDE" },
}

-- Builds a raid whose lootmaster is Kandera and whose council is Kandera + Haerri, then starts the
-- session the way the settings toggle does. Returns the sim and the three clients.
local function NewRaid()
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)

    local lm, council, raider = sim.byName.Kandera, sim.byName.Haerri, sim.byName.Odin

    for name, opts in pairs(SETTINGS) do
        local c = sim.byName[name]
        for k, v in pairs(opts) do c.env.KART_Settings[k] = v end
    end

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster     = "Kandera"
        lm.env.KART_Settings.lcCouncilMembers = "Kandera;Haerri;Wuusch"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)
    return sim, lm, council, raider
end

-- pendingTrades and owedToMe are ordered lists of entries, not maps: an item can be owed twice over
-- an evening and order is what the reminder window shows.
local function Owes(list, rollID)
    for _, e in ipairs(list or {}) do if e.rollID == rollID then return e end end
    return nil
end

-- Every client the raid config lists as council.
local function CouncilOf(sim)
    return { sim.byName.Kandera, sim.byName.Haerri, sim.byName.Wuusch }
end

-- One item drops. Blizzard raises START_LOOT_ROLL on every eligible client independently; the loot
-- owner's handler is what broadcasts LC_START to the rest, so running them in this order is the
-- realistic case and also the awkward one (peers hear about the roll before their own event).
local function Drop(sim, rollID, itemID, opts)
    opts = opts or {}
    KARTTEST.lootRolls[rollID] = { itemID = itemID, canNeed = opts.canNeed, canTransmog = opts.canTransmog }
    for _, c in ipairs(sim.clients) do
        if not (opts.noRollFor and opts.noRollFor[c.name]) then
            RaidSim.As(c, function() c.KART.LC.OnStartLootRoll(rollID) end)
        end
    end
    KARTTEST.AdvanceTime(0)
end

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
    local sim, lm, council, raider = NewRaid()
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
    local sim, lm, council, raider = NewRaid()
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
    local sim, lm, council = NewRaid()
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
