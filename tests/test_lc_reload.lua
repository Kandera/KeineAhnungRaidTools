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

-- Booting a client must not leave its event registrations behind ------------------------------------
-- Not about the addon: about the harness being able to run long enough to find things. Every retained
-- registration pins the whole client environment -- ten loaded chunks and every table in them -- so a
-- leak of one per boot cost about 3 MB per raid and took the 10000-seed soak out of memory around
-- seed 8000, which reads as a failed run rather than as what it was.
--
-- The cause was ownership: KASC registers a CHAT_MSG_ADDON frame of its own, and the libraries were
-- loaded before the owner was set, so nothing could ever match those for removal. Cheap to assert,
-- and it fails here in a second instead of after twenty minutes of soak.
do
    F.NewRaid()
    local settled = #KARTTEST.eventFrames
    T.truthy(settled > 0, "a booted raid registers for events at all")

    for _ = 1, 5 do
        local sim = F.NewRaid()
        RaidSim.Reload(sim, "Bramor")
        RaidSim.Reload(sim, "Alric")
    end
    T.eq(#KARTTEST.eventFrames, settled,
        "five more raids and ten reloads later, nothing is left registered")
end

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
    -- that one bad row cannot take the whole restore down with it.
    --
    -- The pcall is the HARNESS's (raidsim.lua), not the game's: Core.lua calls
    -- Trade.RestorePersistedTrades unguarded from ADDON_LOADED, so a throw in here does not "fail
    -- silently" -- it aborts the rest of that handler. LC.RestoreSessionSnapshot never runs, so the
    -- items still on the table are gone; KART.SyncSettingsToUI never runs; the addon compartment is
    -- never registered. One malformed SavedVariables row would cost the whole login. The observable
    -- is further down.
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

-- The raid each item dropped in, kept the same way and for the same reason (B150) --------------------
-- LC.rollRaidSnapshot is read by the AWARD, which on a plain raider lands long after their vote row
-- was pruned at the deadline -- so LC.SaveSessionSnapshot, which writes only what is on screen, has
-- nothing to carry it under and a reload used to lose it. It lives here instead, for every rollID.
do
    local sim = F.NewRaid()
    local bramor = sim.byName.Bramor
    bramor.env.KART_LCTrades.raids = {
        [94] = { name = "Last Night's Raid", id = 2800, at = time() - (TRADE_WINDOW + 60) },
        [95] = { name = "The Voidspire", id = 2912, at = time() - 60 },
    }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollRaidSnapshot[94],
        "a snapshot past the trade window is dropped on load, so the store cannot grow across nights")
    local kept = reloaded.KART.LC.rollRaidSnapshot[95]
    T.eq(kept and kept.name, "The Voidspire", "one still inside it comes back whole")
    T.eq(kept and kept.id, 2912, "id included")
end

-- A SavedVariables file that comes back malformed ----------------------------------------------------
-- Same exposure as the stamps above and then some: these values are written straight onto an award by
-- LH.LogHistory, so a row of the wrong shape surfaces as a broken history entry rather than as a load
-- error. Each bad row on its own, since pairs() order otherwise decides whether it is reached at all.
do
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.raids = { ["96"] = { name = "The Voidspire", id = 2912, at = time() - 60 } }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.truthy(reloaded.KART.LC.rollRaidSnapshot[96], "a stringified rollID is read back as a number")
end

do
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.raids = { [97] = { name = "The Voidspire", at = "not a time" } }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollRaidSnapshot[97], "a row with no usable age is dropped")
    T.truthy(reloaded.KART.LC.rollRaidSnapshot == reloaded.env.KART_LCTrades.raids,
        "and the restore still finished, so later snapshots are still being saved")
end

do
    -- Not a bad row but a bad STORE -- an older build, a schema change, or a file that came back
    -- half-written. Walking it would throw, and Core.lua calls the restore unguarded from
    -- ADDON_LOADED (only the harness wraps it), so the throw takes the rest of that handler with it:
    -- the trade restore ends one step before it points the live tables anywhere, and
    -- LC.RestoreSessionSnapshot, KART.SyncSettingsToUI and the compartment registration behind it
    -- never run at all.
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.raids = "not a table at all"
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.truthy(type(reloaded.env.KART_LCTrades.raids) == "table"
             and reloaded.KART.LC.rollRaidSnapshot == reloaded.env.KART_LCTrades.raids,
        "a store that is not a table is replaced rather than walked, and the restore still finishes")
end

do
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.raids = {
        [98] = { name = { "not a name" }, id = 2912, at = time() - 60 },
        [99] = { name = "The Voidspire", id = "not an id", at = time() - 60 },
    }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollRaidSnapshot[98],
        "a raid name that is not a string is dropped rather than written onto an award")
    T.is_nil(reloaded.KART.LC.rollRaidSnapshot[99], "and so is an id that is not a number")
end

do
    -- A ROW that is not a table -- the shape the store's own `looted` half legitimately has, so an
    -- older file, a half-written one or a schema that moved is exactly how it turns up. This is the
    -- one bad row that does not merely get dropped: without the type check the `.at` read below it
    -- throws, and Core.lua calls this restore unguarded from ADDON_LOADED (see above), so it would
    -- take the session restore and the rest of the login with it.
    local sim = F.NewRaid()
    sim.byName.Bramor.env.KART_LCTrades.raids = { [95] = 42 }
    local reloaded = RaidSim.Reload(sim, "Bramor")
    T.is_nil(reloaded.KART.LC.rollRaidSnapshot[95], "a row that is not a table at all is dropped")
    T.truthy(reloaded.KART.LC.rollRaidSnapshot == reloaded.env.KART_LCTrades.raids,
        "and the restore still finished, so later snapshots are still being saved")
end

-- New snapshots keep persisting after the restore ----------------------------------------------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 83, F.GLOVES)
    T.eq(lm.env.KART_LCTrades.raids[83], lm.KART.LC.rollRaidSnapshot[83],
        "a snapshot taken after the restore is in the saved file straight away")
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

-- The winner's "you are owed this" clears when the item actually arrives ---------------------------
-- Reported from a live test with /kart add: the lootmaster hands the item over, it disappears from
-- THEIR list, and the winner's own reminder keeps standing. Trade.OnTradeClosed does the whole job
-- on the giving side -- it reads the trade window and their own bags -- and there was no equivalent
-- on the receiving side, so LC.owedToMe was only ever cleared by clicking its own tick, by a
-- reassignment, or by the four-hour prune.
--
-- The field it needs was already there and even said so: LC.currentTradePartnerKey is set
-- unconditionally in Trade.OnTradeShow, for "the separate items-I'm-owed side ... which checks this
-- same field from the other direction". This is that side.
do
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 110, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(110, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)

    T.truthy(F.Owes(lm.KART.LC.pendingTrades, 110), "the lootmaster owes it")
    T.truthy(F.Owes(raider.KART.LC.owedToMe, 110), "and the winner is told they are owed it")

    -- The trade, from the WINNER's client: the lootmaster is the partner, and the item is in the
    -- partner's half of the window, not in ours.
    local link = raider.KART.LC.rollItems[110]
    KARTTEST.tradePartnerUnit = lm.unit
    KARTTEST.tradePlayerItems = {}
    KARTTEST.tradeTargetItems = { link }
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.OnTradeShow()
        raider.KART.LC.Trade.OnTradeAcceptUpdate()
        raider.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE)
        raider.KART.LC.Trade.OnTradeClosed()
    end)
    KARTTEST.tradePartnerUnit, KARTTEST.tradeTargetItems = nil, {}

    T.truthy(not F.Owes(raider.KART.LC.owedToMe, 110),
        "once it arrives, the winner's reminder is gone")
end

do
    -- ...and a trade that did NOT go through leaves it standing. The item sitting in the window is
    -- not the same as having been given it: either side can close the trade at the last moment, and
    -- there is deliberately no bag-contents fallback on this side -- "it is in my bags" is also true
    -- of a copy this player already owned, and clearing a reminder for an item nobody handed over is
    -- worse than leaving one up.
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 111, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(111, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)

    KARTTEST.tradePartnerUnit = lm.unit
    KARTTEST.tradeTargetItems = { raider.KART.LC.rollItems[111] }
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.OnTradeShow()
        raider.KART.LC.Trade.OnTradeAcceptUpdate()
        raider.KART.LC.Trade.OnTradeClosed()          -- closed, never completed
    end)
    KARTTEST.tradePartnerUnit, KARTTEST.tradeTargetItems = nil, {}

    T.truthy(F.Owes(raider.KART.LC.owedToMe, 111),
        "a cancelled trade leaves the winner still owed it")
end

do
    -- The order of TRADE_CLOSED and Blizzard's trade-complete message is not guaranteed, and the
    -- first attempt at this only did the work in TRADE_CLOSED. The giving side has a second signal
    -- -- it rescans its own bags -- so it ticks off either way; the receiving side has only the one,
    -- so a trade-complete arriving after the window closed left the winner's row standing while the
    -- lootmaster's cleared. That is exactly what came back from the live test.
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 112, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(112, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)
    T.truthy(F.Owes(raider.KART.LC.owedToMe, 112), "the winner is owed it")

    KARTTEST.tradePartnerUnit = lm.unit
    KARTTEST.tradeTargetItems = { raider.KART.LC.rollItems[112] }
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.OnTradeShow()
        raider.KART.LC.Trade.OnTradeAcceptUpdate()
        raider.KART.LC.Trade.OnTradeClosed()                              -- window goes first...
        raider.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE) -- ...signal after
    end)
    KARTTEST.tradePartnerUnit, KARTTEST.tradeTargetItems = nil, {}

    T.truthy(not F.Owes(raider.KART.LC.owedToMe, 112),
        "the reminder clears whichever of the two signals lands last")
end

do
    -- ...and the other way round: the completion message arriving BEFORE the window contents were
    -- last read. Then the item strings are not there yet when it fires, and only the pass at
    -- TRADE_CLOSED can see them. Both entry points are kept for that reason -- neither one alone
    -- covers both orders, and this side has no bag scan to fall back on.
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 113, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(113, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)

    KARTTEST.tradePartnerUnit = lm.unit
    KARTTEST.tradeTargetItems = {}
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.OnTradeShow()
        raider.KART.LC.Trade.OnTradeAcceptUpdate()                        -- window still empty
        raider.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE) -- signal, nothing to see
        KARTTEST.tradeTargetItems = { raider.KART.LC.rollItems[113] }
        raider.KART.LC.Trade.OnTradeAcceptUpdate()                        -- contents land late
        raider.KART.LC.Trade.OnTradeClosed()
    end)
    KARTTEST.tradePartnerUnit, KARTTEST.tradeTargetItems = nil, {}

    T.truthy(not F.Owes(raider.KART.LC.owedToMe, 113),
        "a completion message that lands before the contents still clears at the close")
end

-- ...and two copies of one item, of which one arrives ----------------------------------------------
-- The receiving side counts copies for the same reason the giving side does: two entries for the
-- same item string are indistinguishable, so a trade carrying one copy may clear exactly one of
-- them. Clearing both leaves the raider believing they have everything while the lootmaster's list
-- still says one is owed -- and the two screens disagreeing is how an item stops being anybody's
-- problem. The mirror of the giving-side case in tests/test_lc_tradefill.lua; a mutation run walked
-- through both (B116).
do
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 114, F.GLOVES)
    F.Drop(sim, 115, F.GLOVES)
    RaidSim.As(lm, function()
        lm.KART.LC.Trade.AssignWinner(114, raider.guid, "BIS")
        lm.KART.LC.Trade.AssignWinner(115, raider.guid, "BIS")
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(#raider.KART.LC.owedToMe, 2, "the winner is owed both copies")

    KARTTEST.tradePartnerUnit = lm.unit
    KARTTEST.tradeTargetItems = { raider.KART.LC.rollItems[114] }   -- one copy in the window
    RaidSim.As(raider, function()
        raider.KART.LC.Trade.OnTradeShow()
        raider.KART.LC.Trade.OnTradeAcceptUpdate()
        raider.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE)
        raider.KART.LC.Trade.OnTradeClosed()
    end)
    KARTTEST.tradePartnerUnit, KARTTEST.tradeTargetItems = nil, {}

    T.eq(#raider.KART.LC.owedToMe, 1, "one copy arrived, so one is still owed")
end

-- ===================================================================================
-- B81: a reload keeps the items on the table
-- ===================================================================================
-- Measured on 2026-08-01, and the backlog entry understated it. LC.SendOpenRolls answers only from
-- the loot owner and only for rolls whose vote timer is still running, so:
--
--   * the loot owner reloading is answered by nobody -- they are the only one allowed to answer;
--   * everyone else loses the item outright the moment the vote window has closed, which is most of
--     a distribution;
--   * the one client that did recover a row got it back with an empty tally, because votes are not
--     part of the catch-up at all;
--   * a "/kart add" item can never come back that way even in principle -- HandleRollCatchup proves
--     entitlement by asking Blizzard for a roll that never existed.
--
-- Fixed locally instead: every client writes its own tracked rolls to SavedVariables at logout and
-- picks them back up at load, while the session is still the one they belonged to. No protocol, no
-- question of whom to believe, and it covers the manual half for free.
do
    local sim, lm, council, raider = F.NewRaid()
    F.Drop(sim, 90, F.WEAPON)
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function() c.KART.LC.Vote.CastVote(90, 1, nil) end)
    end
    -- Past the vote window, which is where every client used to lose the item completely: this is
    -- the ordinary state of a distribution, not an edge case.
    KARTTEST.AdvanceTime(60)
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: the item is on the lootmaster's council panel")

    local votesBefore = 0
    for _ in pairs(lm.KART.LC.votes[90] or {}) do votesBefore = votesBefore + 1 end
    T.eq(votesBefore, 5, "B81: with the whole raid's votes on it")

    lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")
    KARTTEST.AdvanceTime(1)

    T.eq(#lm.KART.LC.councilTabs, 1, "B81: the reloaded lootmaster still has the item")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[90]), "B81: and knows which item it is")
    local votesAfter = 0
    for _ in pairs(lm.KART.LC.votes[90] or {}) do votesAfter = votesAfter + 1 end
    T.eq(votesAfter, 5, "B81: and every vote that was cast on it")

    -- ...and can get to it. This is the report itself -- "/kart lc opens nothing" -- and having the
    -- state back is not enough on its own: the council panel is built lazily, so after a reload
    -- LC.councilPanel is nil and the command used to fall straight through its own guard.
    RaidSim.As(lm, function() lm.KART.LC.ReopenTrackedWindow() end)
    T.truthy(lm.KART.LC.councilPanel and lm.KART.LC.councilPanel:IsShown(),
        "B81: /kart lc opens the council panel again")
    T.eq(lm.KART.LC.activeRollID, 90, "B81: showing the item it was showing before")

    -- The point of getting it back: they can finish the distribution.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(90, raider.guid, "BIS", nil) end)
    KARTTEST.AdvanceTime(0)
    T.eq(council.KART.LC.assignedWinners[90], raider.guid,
        "B81: and the award reaches the raid from the client that reloaded")
end

do
    -- A council member reloading is the same case, and used to lose the tab just as completely.
    local sim = F.NewRaid()
    F.Drop(sim, 91, F.WEAPON)
    KARTTEST.AdvanceTime(60)
    local council = RaidSim.Reload(sim, "Merrit")
    RaidSim.EnterWorld(sim, "Merrit")
    KARTTEST.AdvanceTime(1)
    T.eq(#council.KART.LC.councilTabs, 1, "B81: a council member keeps the item across a reload too")
end

do
    -- The manual half: "/kart add" has no Blizzard roll behind it, so no message-based catch-up can
    -- ever restore it. This is the case the report started from.
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.KART.LC.StartManualRoll("|cffa335ee|Hitem:249293::::::::80:::::::::|h[Weight of Command]|h|r")
    end)
    KARTTEST.AdvanceTime(1)
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: a manually added item is on the panel")

    lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")
    KARTTEST.AdvanceTime(1)
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: and survives the reload, which no catch-up could do")
end

do
    -- An item that was still a bare "item:12345" string when the client stopped. That is what
    -- LC.HandleStart leaves behind until the client caches the item, and a reload is exactly when
    -- that cache is coldest -- so a restored roll could otherwise render as "item:249293" instead
    -- of a name for the whole distribution, which is the shape of GitHub #12, #13 and #16.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 97, F.WEAPON)
    KARTTEST.AdvanceTime(1)
    lm.KART.LC.rollItems[97] = "item:249293"
    T.truthy(not lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[97]), "the link is not a real one yet")

    lm = RaidSim.Reload(sim, "Bramor")
    KARTTEST.AdvanceTime(5)
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[97]),
        "B81: a restored item finishes resolving its link instead of staying a bare string")
end

do
    -- The bound that matters most in practice: a snapshot is only worth anything while the raid it
    -- belonged to is still running, and the client cannot know that at load -- the answer arrives
    -- from the raid (LC_ACTIVE / LC_SESSION_RESUME). If it never does, the restored items are last
    -- night's, and leaving them would put a stale tab in tonight's council panel. This models the
    -- ordinary case of logging back in shortly after a raid, alone: nobody asks, nobody answers.
    local sim = F.NewRaid()
    F.Drop(sim, 95, F.WEAPON)
    KARTTEST.AdvanceTime(60)

    local lm = RaidSim.Reload(sim, "Bramor")
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: the items come back first, before anybody has answered")
    T.eq(lm.KART.LC.sessionActive, false, "B81: with no session yet")

    KARTTEST.AdvanceTime(90)
    T.eq(#lm.KART.LC.councilTabs, 0, "B81: and are dropped again when no raid confirms them")
end

do
    -- ...and a session that DOES come back keeps them, for as long as the distribution takes.
    local sim = F.NewRaid()
    F.Drop(sim, 96, F.WEAPON)
    KARTTEST.AdvanceTime(60)

    local lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(10)
    T.eq(lm.KART.LC.sessionActive, true, "B81: the raid confirms the session")

    KARTTEST.AdvanceTime(300)
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: so the item stays for as long as the council needs")
end

do
    -- The bound that keeps it from resurrecting the wrong evening: a snapshot older than the
    -- restore window is discarded, whatever it says.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 92, F.WEAPON)
    KARTTEST.AdvanceTime(60)
    RaidSim.As(lm, function() lm.KART.LC.SaveSessionSnapshot() end)
    local stale = lm.env.KART_LCSession
    T.truthy(stale.savedAt, "B81: a snapshot is written for the items on the table")

    -- A client handed YESTERDAY's file. Age is measured in wall clock, not GetTime, for the same
    -- reason the BoP trade stamp is (B34): GetTime counts from when the client process started, so
    -- it says nothing at all across a logout.
    lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.As(lm, function() lm.KART.LC.ClearAllRolls() end)
    stale.savedAt = stale.savedAt - (60 * 60 * 24)
    lm.env.KART_LCSession = stale
    RaidSim.As(lm, function() lm.KART.LC.RestoreSessionSnapshot() end)
    T.eq(#lm.KART.LC.councilTabs, 0, "B81: yesterday's snapshot is not brought back")
end

do
    -- ...and a snapshot from a session that was ENDED is not brought back either. Ending the session
    -- is how a raid says "we are done with this", and a reload must not undo that.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 93, F.WEAPON)
    KARTTEST.AdvanceTime(60)
    RaidSim.As(lm, function() lm.KART.LC.SetSessionActive(false) end)
    KARTTEST.AdvanceTime(0)

    lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")
    KARTTEST.AdvanceTime(1)
    T.eq(#lm.KART.LC.councilTabs, 0, "B81: an ended session leaves nothing to come back to")
end

do
    -- Reloading TWICE, before the raid has confirmed the session. This is where gating the snapshot
    -- on LC.sessionActive would have thrown away exactly what the first reload rescued: the rolls are
    -- back, but whether the raid is still in a session is the raid's answer and has not arrived yet.
    local sim = F.NewRaid()
    F.Drop(sim, 94, F.WEAPON)
    KARTTEST.AdvanceTime(60)

    local lm = RaidSim.Reload(sim, "Bramor")
    T.eq(lm.KART.LC.sessionActive, false, "B81: a reloaded client does not know about the session yet")
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: but it does have the item back")

    lm = RaidSim.Reload(sim, "Bramor")
    T.eq(#lm.KART.LC.councilTabs, 1, "B81: and still has it after reloading again in that window")

    RaidSim.EnterWorld(sim, "Bramor")
    F.RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(10)
    T.eq(lm.KART.LC.sessionActive, true, "B81: with the session coming back the normal way")
end

-- A reload with nothing owed --------------------------------------------------------------------
-- Trade.RestorePersistedTrades opens the trade-reminder window when there are obligations to show.
-- A mutation run flagged its "are there any" check as held by nothing; measuring showed why that is
-- harmless -- Trade.RefreshTradeReminder makes the same check itself and hides the window instead,
-- so the outer one only saves a call. What is worth holding is the OUTCOME, because two independent
-- places have to agree on it for a reload to stay quiet: nothing owed, no window.
do
    local sim, lm = F.NewRaid()
    T.eq(#lm.KART.LC.pendingTrades, 0, "nobody is owed anything")
    T.eq(#lm.KART.LC.owedToMe, 0, "and nothing is owed to us")

    lm = RaidSim.Reload(sim, "Bramor")
    T.truthy(not (lm.KART.LC.tradeReminderFrame and lm.KART.LC.tradeReminderFrame:IsShown()),
        "a reload with no obligations opens no trade reminder")
    T.truthy(not (lm.KART.LC.owedReminderFrame and lm.KART.LC.owedReminderFrame:IsShown()),
        "and no owed reminder either")
end

-- B34's second half: an award landing while a reloaded raider has no council list ------------------
-- Recorded on 2026-07-30 as "also found on the way, not fixed here": a raider who reloads has no
-- council list until the next roster change, and Trade.HandleResult refuses an award from a sender
-- it cannot confirm is council -- so an award landing in that gap was dropped entirely, with no owed
-- entry and no history. A raid produces roster changes constantly, so the window is short. It is
-- also exactly as long as it takes somebody to click Assign, which is what happens in that window.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 91, F.GLOVES)

    local raider = RaidSim.Reload(sim, "Alric")
    RaidSim.EnterWorld(sim, "Alric")
    -- Deliberately NO roster update: that is the event the gap is measured against.

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(91, raider.guid, "BIS", nil) end)
    KARTTEST.AdvanceTime(1)

    T.eq(#raider.KART.LC.owedToMe, 1,
        "an award reaching a raider who has just reloaded is recorded, not dropped")
    T.eq(#raider.env.KART_LootHistory, 1, "and reaches their loot history")
end

-- B66's first remaining half: an award this client could not authorise ---------------------------
-- LC_RESULT is announced once and never re-requested. A client that cannot confirm the SENDER is
-- council drops it -- and LH.RequestHistorySync runs once per raid join, so the hole it leaves is
-- permanent for the evening. The window is a reloaded client before the raid's config reaches it,
-- and the sender that needs authorising is a council member who is not the loot owner (the loot
-- owner is authorised without any council list at all -- see B34).
do
    local sim, _, council = F.NewRaid()
    F.Drop(sim, 92, F.GLOVES)

    local raider = RaidSim.Reload(sim, "Alric")
    -- The gap itself: this client knows nothing about who is on the council yet.
    RaidSim.As(raider, function()
        raider.KART.LC.CouncilNamesTable = {}
        raider.KART.LC.raidConfig = { councilMembers = "", fromSelf = false }
    end)

    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(92, sim.byName.Sinja.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(2)
    T.eq(#raider.env.KART_LootHistory, 0, "the award itself is refused, which is the right call")

    -- ...and then asked for, which is the part that was missing. The delay is deliberate: the config
    -- that would have authorised the sender is usually seconds behind.
    KARTTEST.AdvanceTime(30)
    T.eq(#raider.env.KART_LootHistory, 1,
        "an award a reloaded client could not authorise still reaches its loot history")
end

do
    -- Rate-limited: a client whose config never arrives sees a whole distribution it cannot
    -- authorise, and one request per award would put the raid's history on the wire over and over.
    -- The answer to the first request already carries everything the later ones would ask for.
    local sim, _, council = F.NewRaid()
    local raider = RaidSim.Reload(sim, "Alric")
    RaidSim.As(raider, function()
        raider.KART.LC.CouncilNamesTable = {}
        raider.KART.LC.raidConfig = { councilMembers = "", fromSelf = false }
    end)

    RaidSim.ClearLog(sim)
    for i = 1, 4 do
        F.Drop(sim, 100 + i, F.GLOVES)
        RaidSim.As(council, function()
            council.KART.LC.Trade.AssignWinner(100 + i, sim.byName.Sinja.guid, "BIS", nil)
        end)
        KARTTEST.AdvanceTime(6)
    end

    -- The four rolls just opened are still open on the raider's own client (it never authorised
    -- the council's LC_RESULT, so it never closed any of them locally) -- and the sync gate (Task 4)
    -- correctly holds the deferred request back until they are gone. Advance past the last one's
    -- vote deadline so the gate opens and the request that has been retrying every GATE_GRACE
    -- seconds finally gets through.
    KARTTEST.AdvanceTime(20)

    -- Counted across the whole raid rather than by sender: the request goes out from inside a timer,
    -- and which client the harness calls "active" at that moment is not the sender's identity.
    -- Nobody else in this block has a reason to ask.
    T.eq(#RaidSim.Sent(sim, "LC_HIST_REQ"), 1,
        "four unauthorised awards in a row produce one catch-up request, not four")

    -- The far end of the cooldown. A minute after the last request is a new one -- a distribution
    -- runs far longer than that, and a client still unable to authorise anything an hour in has
    -- been missing awards the whole time.
    KARTTEST.AdvanceTime(60)
    RaidSim.ClearLog(sim)
    F.Drop(sim, 110, F.GLOVES)
    RaidSim.As(council, function()
        council.KART.LC.Trade.AssignWinner(110, sim.byName.Sinja.guid, "BIS", nil)
    end)
    -- Same reasoning as above: this roll's own vote deadline has to pass, and the gate has to see
    -- it close, before the deferred request can get out.
    KARTTEST.AdvanceTime(30)
    T.eq(#RaidSim.Sent(sim, "LC_HIST_REQ"), 1, "and a minute later it asks again")
end

-- B158: the boss dies while the LOOTMASTER is still asking whether a session is running -------------
-- LC.OnStartLootRoll returns on its second line while LC.sessionActive is false, and every reload,
-- relog and disconnect lands in that window: the state request takes seconds (STATE_REQ_BACKOFF).
-- B148 built the repair for it -- the roll is remembered in LC.rollsSeenWhileUnaware and the handler
-- is run for real once the state arrives (LC.ReplaySeenWhileUnaware).
--
-- That repair cannot reach the one client the raid cannot do without. ReplayOne refuses any roll
-- without LC.rollAnnounced, and LC.HandleStart is the only writer of that flag -- the announcer never
-- runs it for its own roll, because KASC drops the self-echo. So on the loot owner the flag is nil by
-- construction, the replay refuses, and the roll stays in the list for ever.
--
-- What that costs is not a missing Auto-Pass. Nothing force-wins the item (C4), nothing announces it
-- (C5), and the raid never learns it existed: it leaves on Blizzard's ordinary roll while the council
-- panel stays empty. /kart status says "unaware" on the one client the Manifest asks to be photographed.
do
    local sim, lm = F.NewRaid()

    -- The lootmaster reloads and comes back mid-question, which is the ordinary state after one.
    local back = RaidSim.Reload(sim, lm.name)
    T.eq(back.KART.LC.sessionStateKnown, false, "the setup: the reloaded lootmaster is still asking")
    T.eq(back.KART.LC.sessionActive, false, "...and reads the session as off until it is told")

    -- The boss dies inside that window.
    RaidSim.ClearLog(sim)
    F.Drop(sim, 1200, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.truthy(back.KART.LC.rollsSeenWhileUnaware[1200], "the roll is remembered rather than forgotten")
    T.eq(#RaidSim.Sent(sim, "LC_DROP"), 0, "and nothing is announced yet, correctly")

    -- The raid answers: a session IS running.
    RaidSim.As(back, function() back.KART.LC.HandleActive("1", back.guid) end)
    KARTTEST.AdvanceTime(2)

    T.eq(back.KART.LC.rollsSeenWhileUnaware[1200], nil,
        "B158: the replay reaches the loot owner's own roll -- nothing else ever will, since only " ..
        "LC.HandleStart sets LC.rollAnnounced and the owner never runs it for its own drop")
    T.truthy(back.KART.LC.rollItems[1200] ~= nil,
        "B158: so the lootmaster tracks the item")
    T.truthy(#RaidSim.Sent(sim, "LC_DROP") > 0,
        "B158: and the raid is told the item exists (C5) instead of it leaving on Blizzard's own roll")
end

-- B161: a client that becomes loot owner mid-roll must not force-win it a second time -------------
-- The other end of the same replay (B158), and older than it. ReplayOne runs LC.OnStartLootRoll,
-- whose owner branch force-wins -- and IsLootOwner is asked at replay time, not at the drop. So a
-- client that was session-unaware while a roll was live and is the loot owner by the time the state
-- arrives rolls Need on an item the previous owner already force-won. Blizzard awards the higher of
-- the two, so the item can end up with the wrong person entirely: C4 says force-won BY EXACTLY ONE
-- PERSON, and C7's holder then owes an item that is not in their bags.
--
-- Both ways in are Manifest items: the designation moving (C10) and the lootmaster walking out so the
-- leader stands in (C9). Both land inside Blizzard's own roll window, which is minutes, and every
-- reload, relog and disconnect puts a client in the unaware state to begin with.
--
-- Pre-B158 the gate was LC.rollAnnounced alone, and a client that RECEIVED the announcement while
-- unaware had it -- so this was reachable before that commit too. What separates the two cases is
-- exactly the announcement: an announced roll already has an owner who took it up, and a replay must
-- not take it up again; an UNANNOUNCED one has none, which is the whole of B158.
do
    local sim, lm = F.NewRaid()
    local heir = sim.byName.Merrit

    -- The heir is mid-reload when the boss dies: it remembers the roll and does nothing with it.
    RaidSim.As(heir, function()
        heir.KART.LC.sessionActive = false
        heir.KART.LC.sessionStateKnown = false
    end)
    F.Drop(sim, 1210, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.truthy(heir.KART.LC.rollsSeenWhileUnaware[1210], "the setup: the heir remembered the roll")
    T.eq((KARTTEST.rolled[1210] or {})[lm.unit], 1, "and the real lootmaster force-won it")
    T.is_nil((KARTTEST.rolled[1210] or {})[heir.unit], "while the heir answered nothing")

    -- The designation moves to the heir while the roll is still live -- the pattern this codebase uses
    -- to move the loot role between two named clients (see tests/test_lc_ownership.lua).
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(1)
    T.truthy(RaidSim.As(heir, heir.KART.LC.IsLootOwner), "the heir owns the loot flow now")

    -- ...and only now does it learn a session is running. Driven directly: the state answer from the
    -- previous owner is refused by LC.IsSenderLootOwner once the designation has moved, which is the
    -- sender guard working, and not what is under test here.
    RaidSim.As(heir, function()
        heir.KART.LC.sessionActive = true
        heir.KART.LC.sessionStateKnown = true
        heir.KART.LC.ReplaySeenWhileUnaware()
    end)
    KARTTEST.AdvanceTime(1)

    T.is_nil((KARTTEST.rolled[1210] or {})[heir.unit],
        "B161: the new owner does not roll Need on an item the previous one already force-won")
    T.eq((KARTTEST.rolled[1210] or {})[lm.unit], 1,
        "and the original force-win is untouched")
    T.is_nil(heir.KART.LC.rollsSeenWhileUnaware[1210],
        "B161: the entry is still let go, so it cannot be retried on the next replay either")
end

-- B164: a restored config must not be trusted field by field ---------------------------------------
-- CLAUDE.md states the standing hazard outright: SavedVariables have no central migration, each
-- structure guards its own shape, and a shape a reader does not expect corrupts existing users on
-- their next login. Trade.RestorePersistedTrades follows that rule meticulously -- every row of its
-- store is type-checked and rebuilt rather than adopted. The config restore added in the same range
-- copies field by field with no check at all:
--
--     for key, value in pairs(store.config) do LC.raidConfig[key] = value end
--
-- and LC.GetRaidMinQuality hands minQuality straight into `quality < LC.GetRaidMinQuality()` in
-- LC.OnStartLootRoll. Measured: a table or a string there errors on EVERY Bind-on-Pickup drop, which
-- is the loot flow stopping for that client for the rest of the evening.
--
-- Not reachable through the addon's own writers -- TryAcceptConfig does `tonumber(minQ) or 4` and
-- LC.ApplyOwnConfig writes scalars -- so this is about what a truncated or hand-edited file carries.
-- The comment on SaveSessionSnapshot already claims "flat scalars throughout"; this makes the reader
-- enforce the claim instead of trusting it.
do
    local CASES = {
        { "a table where a number belongs",  { minQuality = {},    buttonLabels = "BIS;Upgrade" } },
        { "a string where a number belongs", { minQuality = "4",   buttonLabels = "BIS;Upgrade" } },
        { "a table where a string belongs",  { minQuality = 4,     buttonLabels = {} } },
        { "a nested table",                  { minQuality = 4,     nested = { deep = {} } } },
    }
    local rollID = 2100
    for _, case in ipairs(CASES) do
        rollID = rollID + 1
        local sim = F.NewRaid()
        local raider = sim.byName.Alric
        raider.env.KART_LCSession = { savedAt = time(), config = case[2], council = {} }
        RaidSim.As(raider, function() raider.KART.LC.RestoreSessionSnapshot() end)

        local ok = pcall(function()
            F.Drop(sim, rollID, F.GLOVES)
            KARTTEST.AdvanceTime(1)
        end)
        T.truthy(ok, "B164: " .. case[1] .. " in a restored config does not break the next drop")
    end

    -- ...and a healthy config still comes back, which is what the restore is for (D2).
    local sim = F.NewRaid()
    local raider = sim.byName.Alric
    raider.env.KART_LCSession = {
        savedAt = time(),
        config = { minQuality = 3, buttonLabels = "BIS;Upgrade;Offspec", rollsEnabled = true },
        council = {},
    }
    RaidSim.As(raider, function() raider.KART.LC.RestoreSessionSnapshot() end)
    T.eq(raider.KART.LC.raidConfig.minQuality, 3, "B164: a healthy minQuality is still restored")
    T.eq(raider.KART.LC.raidConfig.buttonLabels, "BIS;Upgrade;Offspec",
        "B164: and so are the raid's button labels")
end
