-- Stable award identity. Every client that logs the same award must store the same id, because the
-- id is what "the raid agrees this happened once" is defined over (C7) and what the union merge,
-- the export cut and the Companion archive all dedup on. rollID cannot do that job: it is a small
-- Blizzard number that comes round again every week.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
-- A full item link, for hand-built LC_HIST_BATCH/LC_HIST_ENTRY records (same convention as
-- test_lc_histsync_length.lua / test_loothistory_matching.lua).
local GLOVES = KARTTEST.items[F.GLOVES].link

-- Put one item on the table and award it, using only what lc_fixture.lua already offers -- the
-- fixture belongs to neither session and must not grow while B139 is working in this tree.
local function Award(sim, assigner, rollID, itemID, winner, reason)
    F.Drop(sim, rollID, itemID)
    RaidSim.As(assigner, function()
        assigner.KART.LC.Trade.AssignWinner(rollID, winner.guid, reason, nil)
    end)
    RaidSim.Drain(sim, 10)
end

-- LH.NewAwardID shape -------------------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    local a, b
    RaidSim.As(lm, function()
        a, b = lm.KART.LH.NewAwardID(), lm.KART.LH.NewAwardID()
    end)
    T.truthy(a:match("^%d+%-%x+$"), "an award id is <seconds>-<hex>")
    T.eq(a:find(":", 1, true), nil, "an award id carries no colon, so it is safe as a wire field")
    T.truthy(a ~= b, "two ids minted in the same second still differ")
end

-- The same award gets the same id on every client ---------------------------------------------
do
    local sim, lm, council, raider = F.NewRaid()
    Award(sim, lm, 60, F.GLOVES, raider, "BIS")

    local idLM      = lm.env.KART_LootHistory[1] and lm.env.KART_LootHistory[1].id
    local idCouncil = council.env.KART_LootHistory[1] and council.env.KART_LootHistory[1].id
    local idRaider  = raider.env.KART_LootHistory[1] and raider.env.KART_LootHistory[1].id

    T.truthy(idLM, "the assigner stores an id")
    T.eq(idCouncil, idLM, "the council member stores the assigner's id, not one of its own")
    T.eq(idRaider, idLM, "the raider stores the assigner's id too")
end

-- A locally logged award without a wire id still gets one --------------------------------------
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {}
        lm.KART.LH.LogHistory("item:1234", "Alric", "BIS", "MAGE", nil, 70, "Player-1-A", nil)
    end)
    T.truthy(lm.env.KART_LootHistory[1].id, "an award logged with no id is given one")
end

-- The epoch. A wipe is not an empty table, it is a number going up -- and it has to reach a client
-- that was not there when it was drawn (C3), including one that comes back a week later.
--
-- A counter and not a timestamp on purpose: entries carry time(), the LOCAL system clock of whoever
-- logged them, not GetServerTime(). Comparing those across clients against a wipe line would keep or
-- eat entries whenever two machines are a few minutes apart. A counter does not drift.

-- A higher epoch from the loot owner wipes what is below it ------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 3
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 3 },
        }
        raider.KART.LH.AdoptEpoch(4, lm.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 4, "the higher epoch is adopted")
    T.eq(#raider.env.KART_LootHistory, 0, "and everything below it is gone")
end

-- A higher epoch from someone who is not the loot owner changes nothing ------------------------
do
    local _, _, council, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 3
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 3 },
        }
        raider.KART.LH.AdoptEpoch(4, council.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 3, "a council member cannot wipe the raid")
    T.eq(#raider.env.KART_LootHistory, 1, "and the entry survives")
end

-- A lower epoch changes nothing ----------------------------------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 5
        raider.env.KART_LootHistory = {}
        raider.KART.LH.AdoptEpoch(2, lm.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 5, "an older epoch does not pull us backwards")
end

-- The absentee who comes back a week later ------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 1 },
        }
    end)
    -- RaidSim.Join takes a member def and hands back a brand-new client (fresh env, nothing
    -- persisted -- see RaidSim.Join's own comment), so the old `raider` reference is a corpse the
    -- moment it rejoins; the reassignment is what makes the assertions below look at the client that
    -- actually came back, not the one that left.
    local member = raider.member
    RaidSim.Leave(sim, raider.name)
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    KARTTEST.AdvanceTime(7 * 24 * 60 * 60)
    raider = RaidSim.Join(sim, member)
    RaidSim.EnterWorld(sim, raider.name)
    RaidSim.Drain(sim, 90)

    T.eq(raider.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
        "the returning raider ends on the raid's epoch")
    T.eq(#raider.env.KART_LootHistory, 0,
        "and does not keep the history the raid wiped while he was away")
end

-- Clearing is the loot owner's call, and only in a group -----------------------------------------
do
    local _, _, council = F.NewRaid()
    local before
    RaidSim.As(council, function()
        before = council.env.KART_LootHistoryEpoch
        council.env.KART_LootHistory = { { time = time(), id = "1-ccc", epoch = before } }
        council.KART.LH.ClearHistory()
    end)
    T.eq(council.env.KART_LootHistoryEpoch, before, "a council member's clear does not bump the epoch")
    T.eq(#council.env.KART_LootHistory, 1, "and does not empty the log")
end

-- The one-time purge on update -------------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = nil
        lm.env.KART_LootHistory = { { time = time(), item = "item:1", winner = "Alric" } }
        KARTTEST.FireEvent("ADDON_LOADED", "KeineAhnungRaidTools")
    end)
    T.eq(lm.env.KART_LootHistoryEpoch, 1, "a client with no epoch starts at 1")
    T.eq(#lm.env.KART_LootHistory, 0, "and its pre-id history is purged")
end

-- The genuinely first-ever load: no epoch AND no history table at all --------------------------
-- RaidSim.Boot always pre-seeds KART_LootHistory to a table, which a real brand-new install does
-- not have -- Core.lua's own `KART_LootHistory = KART_LootHistory or {}` is what creates it there,
-- and LootHistory.lua's ADDON_LOADED frame can register (and dispatch) before Core.lua's, per the
-- .toc's file order. LH.PurgeIfNoEpoch must not assume some other file already made the table.
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = nil
        lm.env.KART_LootHistory = nil
        lm.KART.LH.PurgeIfNoEpoch()
    end)
    T.eq(lm.env.KART_LootHistoryEpoch, 1, "a client with no history table at all still starts at 1")
    T.eq(#lm.env.KART_LootHistory, 0, "and ends up with an empty table, not a crash")
end

-- The award now carries the epoch it was decided in (Task 6a), not the receiver's guess at
-- delivery time. Three cases, on the wire, per the maintainer's ruling.

-- The delayed award that outlived a wipe is discarded (case 2) ----------------------------------
-- Held before it can send, so it is still in flight when the loot owner wipes the raid. Every
-- receiver -- not just the assigner, who wiped its own copy directly -- must end up without it.
do
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.Hold(sim, "LC_RESULT")
    Award(sim, lm, 300, F.GLOVES, raider, "BIS")
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    RaidSim.Drain(sim, 10)
    RaidSim.Release(sim, "LC_RESULT")
    RaidSim.Drain(sim, 10)

    local function hasRoll300(c)
        for _, e in ipairs(c.env.KART_LootHistory or {}) do
            if e.rollID == 300 then return true end
        end
        return false
    end
    for _, c in ipairs(sim.clients) do
        T.eq(hasRoll300(c), false, c.name .. " does not store the pre-wipe award")
    end
end

-- An award decided at a higher epoch, from the loot owner, is adopted along with its epoch
-- (case 3, authorized) ---------------------------------------------------------------------------
-- raider never hears the wipe broadcast itself (held back); the award from the loot owner is what
-- reaches it first, and that alone must be enough to bring it up to date.
do
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.Hold(sim, "LC_HIST_EPOCH")
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    RaidSim.Drain(sim, 10)
    T.eq(raider.env.KART_LootHistoryEpoch, nil, "raider has not heard the wipe broadcast yet")

    Award(sim, lm, 301, F.GLOVES, raider, "BIS")

    T.eq(raider.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
        "raider adopts the assigner's epoch along with the award")
    local stored
    for _, e in ipairs(raider.env.KART_LootHistory) do
        if e.rollID == 301 then stored = e end
    end
    T.truthy(stored, "raider stores the award")
    T.eq(stored and stored.epoch, lm.env.KART_LootHistoryEpoch, "stamped at the epoch it was decided in")

    RaidSim.Release(sim, "LC_HIST_EPOCH")
    RaidSim.Drain(sim, 10)
end

-- The same award from a council member who is not the loot owner is discarded, and the client
-- reads as stale afterwards (case 3, unauthorized) -----------------------------------------------
-- Only the loot owner's own broadcast may raise an epoch (Task 2, Task 4). raider is put a full
-- epoch behind the rest of the raid (as if it had missed the wipe broadcast, e.g. a disconnect)
-- while council legitimately holds the new one, then council -- not the loot owner -- awards.
do
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    RaidSim.Drain(sim, 10)
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {}

    Award(sim, council, 302, F.GLOVES, lm, "BIS")

    T.eq(raider.env.KART_LootHistoryEpoch, 1, "raider does not adopt an epoch from a non-owner")
    local hasRoll302 = false
    for _, e in ipairs(raider.env.KART_LootHistory) do
        if e.rollID == 302 then hasRoll302 = true end
    end
    T.eq(hasRoll302, false, "raider does not store the award either")
    RaidSim.As(raider, function() T.truthy(raider.KART.LH.IsStale(), "raider now reads as stale") end)
end

-- The loot-history catch-up path (LC_HIST_BATCH) asks the same question the award path does, and
-- must answer it the same way (code review finding on Task 6a, 2026-08-07). LH.HandleHistoryBatch
-- used to only check whether the batch epoch was BELOW ours; a batch answered by an ORDINARY group
-- member (anyone may answer LC_HIST_REQ, not just the loot owner -- see LH.HandleHistoryRequest)
-- carrying that member's own, legitimately higher epoch fell straight through and was stored above
-- this client's own epoch -- invisible to LH.HistoryChecksum's `(e.epoch or 1) == epoch` filter
-- forever. Both cases below go through LH.HandleHistoryBatch directly with a hand-built record,
-- the same convention test_lc_histsync_length.lua / test_loothistory_matching.lua use for
-- LH.HandleHistoryEntry.

-- A catch-up batch from someone who is not the loot owner, carrying a higher epoch, stores
-- nothing and leaves the client stale ------------------------------------------------------------
do
    local _, _, council, raider = F.NewRaid()
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {}
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%d:%s",
        time(), "batch-1", 2, GLOVES)

    RaidSim.As(raider, function()
        raider.KART.LH.HandleHistoryBatch("2:" .. council.guid .. ":0:" .. record, council.guid)
    end)

    T.eq(raider.env.KART_LootHistoryEpoch, 1, "raider does not adopt an epoch from a non-owner's batch")
    T.eq(#raider.env.KART_LootHistory, 0, "and stores nothing from it")
    RaidSim.As(raider, function() T.truthy(raider.KART.LH.IsStale(), "raider now reads as stale") end)
end

-- The same batch, from the loot owner, adopts the epoch and stores the entry ----------------------
-- This is also the intended-cost case the ruling calls out: a returning absentee resyncing while
-- the loot owner is around gets caught up in one step, epoch included.
do
    local _, lm, _, raider = F.NewRaid()
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {}
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%d:%s",
        time(), "batch-2", 2, GLOVES)

    RaidSim.As(raider, function()
        raider.KART.LH.HandleHistoryBatch("2:" .. lm.guid .. ":0:" .. record, lm.guid)
    end)

    T.eq(raider.env.KART_LootHistoryEpoch, 2, "raider adopts the loot owner's epoch from the batch")
    T.eq(#raider.env.KART_LootHistory, 1, "and stores the entry from it")
    T.eq(raider.env.KART_LootHistory[1] and raider.env.KART_LootHistory[1].epoch, 2,
        "stamped at the epoch it was answered at")
end

-- A reload changes nothing (C8) --------------------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    -- Bumped past 1 before the award, so the reload assertion below cannot be satisfied by
    -- LH.PurgeIfNoEpoch's nil->1 fallback -- which is exactly how this block used to pass before
    -- KART_LootHistoryEpoch was added to raidsim.lua's SAVED_VARIABLES list (see the comment there):
    -- the reload silently dropped the epoch to nil, the purge reset it to 1, and epochBefore/after
    -- both being 1 looked like the epoch had survived.
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    RaidSim.Drain(sim, 10)
    Award(sim, lm, 61, F.GLOVES, raider, "BIS")
    local idBefore    = raider.env.KART_LootHistory[1].id
    local epochBefore = raider.env.KART_LootHistoryEpoch
    T.truthy(epochBefore and epochBefore > 1, "the epoch is bumped past 1 before the reload")
    -- RaidSim.Reload REPLACES the client and returns the new one; the pre-reload `raider` object
    -- is left untouched (a corpse -- see its own comment), so without capturing the return value
    -- here every assertion below would be reading the SAME table it read before the reload ever
    -- ran, unable to fail no matter what RaidSim.Reload actually does. This is what let C8 "pass"
    -- before KART_LootHistoryEpoch was even added to SAVED_VARIABLES.
    raider = RaidSim.Reload(sim, raider.name)
    T.eq(raider.env.KART_LootHistory[1] and raider.env.KART_LootHistory[1].id, idBefore,
        "the award id survives a reload")
    T.eq(raider.env.KART_LootHistoryEpoch, epochBefore, "the epoch survives a reload")
end

-- Convergence. The three merge rules are meant to be commutative and idempotent: who talks to whom,
-- and in what order, must not change where the raid ends up. That is a property, not a case, so it is
-- checked by running the same awards and wipes through randomised orderings and losses and asserting
-- that every client lands on the same epoch and the same set of ids.
--
-- Deterministic seed: a soak that cannot be re-run on the failing input is a soak that reports
-- something nobody can fix. Compare by RATE across runs, never by seed number.
do
    for seed = 1, 40 do
        math.randomseed(seed)
        local sim, lm, council, raider = F.NewRaid()

        for i = 1, 12 do
            local winner = ({ council, raider, lm })[math.random(1, 3)]
            if math.random() < 0.25 then RaidSim.Hold(sim, "LC_RESULT") end
            Award(sim, lm, 200 + i, F.GLOVES, winner, "BIS")
            if math.random() < 0.25 then RaidSim.Release(sim, "LC_RESULT") end
            if i == 6 then RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end) end
            -- RaidSim.Reload REPLACES the client in the sim and returns the new one; the old
            -- `raider` reference becomes a corpse (see its own comment). Without capturing the
            -- return value here, every later iteration -- and the convergence assertions below --
            -- kept driving/reading the dead pre-reload client, which never receives another
            -- broadcast again. That made a real defect (the wire-guessed epoch, Task 6a Finding 2)
            -- indistinguishable from this harness bug: both left the post-reload raider looking
            -- behind the raid.
            if math.random() < 0.2 then raider = RaidSim.Reload(sim, raider.name) end
        end

        RaidSim.Release(sim, "LC_RESULT")
        RaidSim.Drain(sim, 300)

        local function idSet(c)
            local s = {}
            for _, e in ipairs(c.env.KART_LootHistory or {}) do s[e.id] = true end
            return s
        end

        T.eq(raider.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
            "seed " .. seed .. ": the raider ends on the lootmaster's epoch")
        T.eq(council.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
            "seed " .. seed .. ": the council member does too")
        T.deep_eq(idSet(raider), idSet(lm),
            "seed " .. seed .. ": the raider holds exactly the lootmaster's award ids")
        T.deep_eq(idSet(council), idSet(lm),
            "seed " .. seed .. ": and so does the council member")
    end
end
