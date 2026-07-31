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

-- Losing raid lead is not a handover (B70, partial) -------------------------------------------------
-- An empty Lootmaster field means the raid leader's own settings ARE the raid's (B33). When raid lead
-- then moves, LC.ApplyOwnConfig used to treat that exactly like a deliberate handover: broadcast
-- LC_RESIGN and wipe our copy. Nothing was handed over, and the new leader cannot claim the config
-- (LC.IsConfigOwner needs sessionStartedByUs), so that wipe destroyed the only copy in existence and
-- the raid spent the night on its own defaults -- rolls off. This keeps the copy.
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
    T.truthy(first.KART.LC.raidConfig.fromSelf, "the empty-field leader holds the raid's config")

    RaidSim.ClearLog(sim)
    RaidSim.Promote(sim, "Sinja")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    T.eq(#RaidSim.Sent(sim, "LC_RESIGN"), 0, "losing raid lead is not announced as a handover")
    T.truthy(first.KART.LC.raidConfig.fromSelf,
        "and the config they were holding for the raid is still there to hand on")
    T.eq(RaidSim.As(first, first.KART.LC.GetRollsEnabled), true, "with the raid's roll setting intact")
    T.truthy(not RaidSim.As(first, first.KART.LC.IsConfigOwner),
        "while they have correctly stopped being the config owner")
end

-- A real handover still resigns ---------------------------------------------------------------------
-- The branch above must not swallow the case it was written for (B32): naming somebody else in the
-- Lootmaster field is a deliberate handover, and every peer has to be told to stop naming us.
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local first = sim.byName.Bramor
    RaidSim.As(first, function()
        first.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        first.KART.LC.ApplyOwnConfig()
        first.KART.LC.SetSessionActive(true)
    end)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    RaidSim.ClearLog(sim)

    RaidSim.As(first, function()
        first.env.KART_Settings.lcLootmaster = "Merrit"   -- handing the role over
        first.KART.LC.ApplyOwnConfig()
    end)
    T.eq(#RaidSim.Sent(sim, "LC_RESIGN"), 1, "naming somebody else still resigns out loud")
    T.truthy(next(first.KART.LC.raidConfig) == nil, "and drops our own copy")
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
