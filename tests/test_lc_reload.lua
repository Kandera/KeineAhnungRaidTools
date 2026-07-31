-- B34: what a reload does to an item that is already in the lootmaster's bags but not yet decided.
--
-- Measured before it was fixed, because the backlog entry was wrong about it: the council's award
-- DOES still reach a reloaded lootmaster, and Trade.HandleResult rebuilds the item link from the
-- broadcast payload and creates the trade obligation. What did not survive was the CLOCK.
--
-- Blizzard's Bind-on-Pickup trade window is four hours of WALL clock, counted from the moment the
-- item was looted. The stamp was memory-only, so a reload made both the lootmaster's pending trade
-- and the winner's owed entry fall back to time() at AWARD time -- a countdown that started when the
-- boss died restarted from zero. KART then promised hours that did not exist and would warn about a
-- deadline already past. Nothing says a word and the item is simply lost.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local TRADE_WINDOW = 4 * 60 * 60

-- The lootmaster reloads mid-roll -----------------------------------------------------------------
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 80, F.GLOVES)

    local lootedAt = lm.KART.LC.rollLootedAt[80]
    T.truthy(lootedAt, "the loot time is stamped when the item drops")

    KARTTEST.AdvanceTime(120)
    lm = RaidSim.Reload(sim, "Bramor")
    T.eq(lm.KART.LC.rollLootedAt[80], lootedAt, "and it survives the lootmaster's reload")

    -- The council never reloaded, so it still has the tab and can decide.
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(80, sim.byName.Alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)

    local entry = lm.KART.LC.pendingTrades[1]
    T.truthy(entry, "the award still reaches the reloaded lootmaster as a trade obligation")
    T.eq(entry and entry.lootedAt, lootedAt,
        "dated from when the item dropped, not from when the council got round to it")
    -- Stated as the elapsed gap, not just as equality: with a wall clock that never moves the
    -- assertion above passes whether or not the stamp survived, because time() at award time IS the
    -- loot time. This is the part that fails if the clock stops advancing.
    T.eq(time() - (entry and entry.lootedAt or 0), 120,
        "and its four hours are already 120 seconds down, not restarted")
end

-- The winner reloads before the award --------------------------------------------------------------
-- Their own "you are owed this" entry carries the same deadline, and a plain raider's roll state is
-- pruned the moment their vote window closes -- so on that side the stamp is the ONLY thing left.
do
    local sim, _, council = F.NewRaid()
    F.Drop(sim, 81, F.GLOVES)

    local alric = sim.byName.Alric
    local lootedAt = alric.KART.LC.rollLootedAt[81]
    T.truthy(lootedAt, "the winner stamped the drop too")

    KARTTEST.AdvanceTime(120)
    alric = RaidSim.Reload(sim, "Alric")
    T.eq(alric.KART.LC.rollLootedAt[81], lootedAt, "and still has it after relogging")

    -- A reload leaves them with no council list, and Trade.HandleResult refuses an award from
    -- somebody it cannot confirm is council. The config comes back with the next roster change,
    -- which a raid produces constantly -- see the assertions further down for the case where it
    -- has not yet.
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(0)

    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(81, alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)

    local owed = alric.KART.LC.owedToMe[1]
    T.truthy(owed, "they are owed the item")
    T.eq(owed and owed.lootedAt, lootedAt, "with the real deadline, not a fresh four hours")
    T.eq(time() - (owed and owed.lootedAt or 0), 120, "already 120 seconds into it")
end

-- A stamp whose trade window closed while we were logged out ----------------------------------------
-- Past four hours the item cannot be traded at all, so keeping the stamp would only let a late award
-- build a reminder for something nobody can hand over.
do
    local sim = F.NewRaid()
    local bramor = sim.byName.Bramor
    bramor.env.KART_LCTrades.looted = {
        [90] = time() - (TRADE_WINDOW + 60),   -- closed an hour ago
        [91] = time() - 60,                    -- still open
    }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollLootedAt[90], "a stamp past the trade window is dropped on load")
    T.truthy(reloaded.KART.LC.rollLootedAt[91], "one still inside it is kept")
end

-- A SavedVariables file that comes back malformed ---------------------------------------------------
-- The whole table is read by rollID lookup, so a bad key is invisible until an award lands on it.
do
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.looted = { ["92"] = time() - 60 }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.truthy(reloaded.KART.LC.rollLootedAt[92], "a stringified rollID is read back as a number")
end

do
    -- On its own, not mixed in with sound entries: pairs() order decides whether a bad row is
    -- reached before or after the good ones, so a mixed table can pass by luck. What must hold is
    -- that one bad row cannot take the whole restore down with it -- and the restore is wrapped in a
    -- pcall at the call site, so a throw here is SILENT. The observable is further down.
    local sim, lm = F.NewRaid()
    lm.env.KART_LCTrades.looted = { [93] = "not a time" }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollLootedAt[93], "a stamp that is not a time is dropped")

    -- The restore ran to the end. Pointing the live table at the saved one is the LAST thing it
    -- does, so the two being the same table is the proof -- and it is checkable without a session,
    -- which a client that has just reloaded does not have yet.
    T.truthy(reloaded.KART.LC.rollLootedAt == reloaded.env.KART_LCTrades.looted,
        "and the restore still finished, so later stamps are still being saved")
end

-- New stamps keep persisting after the restore ------------------------------------------------------
-- The live table is pointed at the saved one, the same arrangement the two trade lists use; a copy
-- would have restored correctly once and then quietly stopped saving anything.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 82, F.GLOVES)
    T.eq(lm.env.KART_LCTrades.looted[82], lm.KART.LC.rollLootedAt[82],
        "a stamp taken after the restore is in the saved file straight away")
end

-- Raid lead moves: exactly one config owner, and it is the new leader ------------------------------
-- B70 was "nobody owns the config after a lead change, and the raid silently falls back to its own
-- defaults for the rest of the night". The ownership rule (docs/OWNERSHIP.md) removes the question:
-- ownership is raid lead, so it can never be held by nobody and never by two people. Both halves are
-- asserted, because both were real failures (B70 and B64).
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local first = sim.byName.Bramor
    RaidSim.As(first, function()
        first.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        first.env.KART_Settings.lcRollsEnabled   = true
        first.KART.LC.ApplyOwnConfig()
        first.KART.LC.SetSessionActive(true)
    end)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    local function ownerCount()
        local n, who = 0, nil
        for _, c in ipairs(sim.clients) do
            if RaidSim.As(c, c.KART.LC.IsConfigOwner) then n, who = n + 1, c.name end
        end
        return n, who
    end

    local n, who = ownerCount()
    T.eq(n, 1, "exactly one client owns the config")
    T.eq(who, "Bramor", "and it is the raid leader")

    RaidSim.Promote(sim, "Sinja")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    n, who = ownerCount()
    T.eq(n, 1, "still exactly one after the lead moves -- never nobody (B70), never two (B64)")
    T.eq(who, "Sinja", "and it is the new raid leader")
    T.eq(table.concat(F.Disagreements(sim), " | "), "", "with the raid of one mind about the config")
end

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

-- The empty-field setup announces its own weakness (B70 mitigation) ---------------------------------
-- Leaving the Lootmaster field empty is supported (B33): the raid leader's own settings become the
-- raid's. It is also the one setup that cannot survive the evening -- when raid lead moves, or a peer's
-- relay lands on this client first, the copy stops being the raid's and no successor can claim it.
-- Three attempts at making an ownerless config converge have each been rejected by the soak, so until
-- that is solved the setup says so at the one moment somebody is looking.
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local lead = sim.byName.Bramor
    local out = Capture(function()
        RaidSim.As(lead, function()
            lead.env.KART_Settings.lcLootmaster = ""
            lead.KART.LC.ApplyOwnConfig()
            lead.KART.LC.SetSessionActive(true)
        end)
    end)
    T.truthy(RaidSim.As(lead, lead.KART.LC.IsConfigOwner), "the empty-field leader does own the config")
    T.truthy(out:find(lead.KART.L.LC_LOOTMASTER_EMPTY_WARN, 1, true),
        "and is told the raid keeps it only while they hold raid lead")
end

-- ...and naming somebody silences it, because that is the fix ----------------------------------------
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local lead = sim.byName.Bramor
    local out = Capture(function()
        RaidSim.As(lead, function()
            lead.env.KART_Settings.lcLootmaster = "Bramor"   -- their own name is enough
            lead.KART.LC.ApplyOwnConfig()
            lead.KART.LC.SetSessionActive(true)
        end)
    end)
    T.truthy(RaidSim.As(lead, lead.KART.LC.IsConfigOwner), "a named lootmaster still owns the config")
    T.truthy(not out:find(lead.KART.L.LC_LOOTMASTER_EMPTY_WARN, 1, true),
        "and hears nothing, because the config is theirs by declaration")
end

-- B48: the council member who assigns to THEMSELVES gets their own reminder -----------------------
-- LC.owedToMe was populated only in Trade.HandleResult, i.e. only on a client that RECEIVED the
-- broadcast. The assigner does not process its own message, so the one person who could not see what
-- they were owed was the one who decided it -- while the lootmaster's queue was correct all along.
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 84, F.GLOVES)

    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(84, council.guid, "BIS", nil)   -- to themselves
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(#council.KART.LC.owedToMe, 1, "the assigner is owed the item they gave themselves")
    T.eq(council.KART.LC.owedToMe[1].rollID, 84, "for the right roll")
    T.eq(council.KART.LC.owedToMe[1].lootmasterKey, lm.guid, "by the person actually holding it")
    T.eq(council.KART.LC.owedToMe[1].lootedAt, council.KART.LC.rollLootedAt[84],
        "dated from the drop, so it expires with the real trade window")
    T.eq(#lm.KART.LC.pendingTrades, 1, "and the loot owner owes it")

    -- Reassigning away from themselves must take it back off, not leave a second one behind.
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(84, sim.byName.Alric.guid, "Upgrade", nil)
        KARTTEST.AcceptPopup("KART_LC_REASSIGN_CONFIRM")
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(#council.KART.LC.owedToMe, 0, "reassigning away drops their own entry")
end

do
    -- The loot owner assigning to themselves is owed nothing: the item is already in their bags.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 85, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(85, lm.guid, "BIS", nil) end)
    KARTTEST.AdvanceTime(0)
    T.eq(#lm.KART.LC.owedToMe, 0, "the loot owner is not owed an item they are holding")
end

-- B47: an obligation past Blizzard's trade window is dropped, not left looking live ---------------
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 86, F.GLOVES)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(86, council.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(#lm.KART.LC.pendingTrades, 1, "the lootmaster owes the item")
    T.eq(#council.KART.LC.owedToMe, 1, "and the winner is owed it")

    -- Past four hours it cannot be handed over at all. Pruning used to happen only in
    -- Trade.RestorePersistedTrades, which runs at ADDON_LOADED -- so a raid that never reloads never
    -- pruned, and dead rows sat in the list indistinguishable from live ones.
    KARTTEST.AdvanceTime(TRADE_WINDOW + 60)
    RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts)
    RaidSim.As(council, council.KART.LC.Trade.CheckTradeTimeouts)

    T.eq(#lm.KART.LC.pendingTrades, 0, "the dead obligation is gone from the lootmaster's list")
    T.eq(#council.KART.LC.owedToMe, 0, "and from the winner's")
end

do
    -- One still inside the window is untouched, so the pruning cannot be "clear the list".
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 87, F.GLOVES)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(87, council.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(0)
    KARTTEST.AdvanceTime(TRADE_WINDOW - 600)          -- ten minutes left
    RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts)
    T.eq(#lm.KART.LC.pendingTrades, 1, "an obligation still inside the window survives")
end

-- B77: a reload must not turn a re-decision into a first award ------------------------------------
-- Assigning reads LC.assignedWinners to decide whether this is a REASSIGNMENT -- and that table was
-- memory-only. Nothing restores it: the state request brings the session and the config back, the
-- roll catch-up brings the rolls, and the history catch-up runs on JOIN only.
--
-- So a council member who reloads mid-distribution comes back not knowing which items already have
-- a winner. Deciding one again read prevWinner = nil, skipped the confirm dialog, and broadcast the
-- reassign flag as 0. Every peer read that as a first award clashing with the one it held, applied
-- the B35 tie-break, and kept the older winner -- while the assigner's own local step wrote the new
-- one unconditionally. The one client showing the new winner was the person who had just decided
-- it, and nothing told them: HandleResult does not run on our own broadcast and no peer
-- re-announces.
do
    local sim, lm, council = F.NewRaid()
    local corvin, alric = sim.byName.Corvin, sim.byName.Alric
    F.Drop(sim, 92, F.GLOVES)

    -- Deliberately to the SMALLER key first, so a first award from the reloaded client would lose
    -- the tie-break. Awarding the other way round would pass whether this works or not.
    T.truthy(corvin.guid < alric.guid, "the first winner's key sorts below the second's")
    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(92, corvin.guid, "BIS", nil) end)
    T.eq(lm.KART.LC.assignedWinners[92], corvin.guid, "the raid has a winner")

    RaidSim.Reload(sim, "Merrit")
    RaidSim.EnterWorld(sim, "Merrit")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)          -- the state request and its answer
    -- Re-resolved, not kept: a reload replaces the client object.
    local reloaded = sim.byName.Merrit

    T.eq(reloaded.KART.LC.assignedWinners[92], corvin.guid,
        "and the client that reloaded still knows the item is decided")

    -- They change their mind. This is a reassignment, so it asks first and the raid is told so.
    RaidSim.As(reloaded, function()
        reloaded.KART.LC.Trade.AssignWinner(92, alric.guid, "Upgrade", nil)
        KARTTEST.AcceptPopup("KART_LC_REASSIGN_CONFIRM")
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(reloaded.KART.LC.assignedWinners[92], alric.guid, "their own client shows the new winner")
    T.eq(lm.KART.LC.assignedWinners[92], alric.guid, "and so does the lootmaster")
    T.eq(corvin.KART.LC.assignedWinners[92], alric.guid, "and the previous winner's own client")
end

do
    -- ...and the winner it comes back with belongs to the roll running NOW. Blizzard reuses a rollID
    -- for a different drop within seconds, and the history deliberately keeps both awards under that
    -- number (B74) -- so "the entry for this rollID" is not enough. Restoring the previous item's
    -- winner would make the new item look decided the moment its holder reloaded: no confirm dialog
    -- for whoever decides it, and a reassign flag on a first award.
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 93, F.GLOVES)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(93, sim.byName.Alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(5)

    F.Drop(sim, 93, F.WEAPON)        -- the same number, a genuinely different item
    T.is_nil(lm.KART.LC.assignedWinners[93], "the new item has no winner yet")

    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.eq(#(reloaded.env.KART_LootHistory or {}), 1, "the earlier award is still on record")
    T.is_nil(reloaded.KART.LC.assignedWinners[93],
        "but it is not restored as the winner of the item now under that number")
end
