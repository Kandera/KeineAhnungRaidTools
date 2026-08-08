-- Stable award identity. Every client that logs the same award must store the same id, because the
-- id is what "the raid agrees this happened once" is defined over (C7) and what the union merge,
-- the export cut and the Companion archive all dedup on. rollID cannot do that job: it is a small
-- Blizzard number that comes round again every week.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
-- A full item link, for hand-built LC_HIST_BATCH records (same convention as
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
    -- RaidSim.Join takes a member def and hands back a brand-new client (fresh env, nothing
    -- persisted -- see RaidSim.Join's own comment), so the old `raider` reference is a corpse the
    -- moment it rejoins; the reassignment is what makes the assertions below look at the client that
    -- actually came back, not the one that left.
    local member = raider.member
    RaidSim.Leave(sim, raider.name)
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    KARTTEST.AdvanceTime(7 * 24 * 60 * 60)
    raider = RaidSim.Join(sim, member)

    -- The log he comes back WITH, written onto the client that actually returns. This block used to
    -- seed the client that LEFT, which RaidSim.Join then replaced -- so the entry never existed on
    -- the machine being asserted about and the assertion below was reading a freshly booted, empty
    -- history. Deleting that setup entirely left the whole suite green (mutation testing,
    -- 2026-08-07), which is what "vacuous" means in practice. A real absentee's SavedVariables hold
    -- last tier's rows at last tier's epoch, and that is the only thing there is to wipe.
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {
        { time = time() - 7 * 24 * 60 * 60, item = GLOVES, winner = "Alric",
          winnerKey = "Player-1-A", reason = "BIS", class = "MAGE", rollID = 5,
          id = "last-tier-1", epoch = 1 },
    }
    T.eq(#raider.env.KART_LootHistory, 1, "he comes back still holding last tier's log")

    RaidSim.EnterWorld(sim, raider.name)
    RaidSim.Drain(sim, 90)

    T.eq(raider.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
        "the returning raider ends on the raid's epoch")
    T.eq(#raider.env.KART_LootHistory, 0,
        "and does not keep the history the raid wiped while he was away")
end

-- Everything the confirmation dialog is allowed to do, and what it says when it will not do it.
--
-- A refusal that prints nothing is the same defect as everything else this module exists to close: a
-- dialog that appears to work and then does not (C14).
local function ClearWith(client)
    local lines = {}
    RaidSim.As(client, function()
        local realPrint = client.env.print
        client.env.print = function(s) lines[#lines + 1] = tostring(s) end
        client.KART.LH.ClearHistory()
        client.env.print = realPrint
    end)
    return table.concat(lines, "\n")
end

-- Clearing is the loot owner's call, and only in a group -----------------------------------------
do
    local _, _, council = F.NewRaid()
    local before
    RaidSim.As(council, function()
        before = council.env.KART_LootHistoryEpoch
        council.env.KART_LootHistory = { { time = time(), id = "1-ccc", epoch = before } }
    end)
    local said = ClearWith(council)
    T.eq(council.env.KART_LootHistoryEpoch, before, "a council member's clear does not bump the epoch")
    T.eq(#council.env.KART_LootHistory, 1, "and does not empty the log")
    T.truthy(said ~= "", "and the button says why it did nothing")
end

-- Outside a group nobody clears either, and it says so ---------------------------------------------
-- The third refusal, and the one nothing reached: deleting its print left the suite green (mutation
-- testing, 2026-08-07) while the other two were held. A raid-wide clear is a broadcast, and alone
-- there is nobody to send it to -- so the epoch would rise in private and walk into the next raid
-- ahead of everyone, from a dialog that appeared to work.
do
    local _, lm = F.NewRaid()
    local before
    RaidSim.As(lm, function()
        before = lm.env.KART_LootHistoryEpoch
        lm.env.KART_LootHistory = { { time = time(), id = "1-eee", epoch = before or 1 } }
    end)
    -- This one client alone reads the world as ungrouped -- the raid around it is untouched, which
    -- is how the harness models somebody who has actually left (see KARTTEST.solo).
    KARTTEST.solo[lm.unit] = true
    local said = ClearWith(lm)
    KARTTEST.solo[lm.unit] = nil

    T.eq(lm.env.KART_LootHistoryEpoch, before, "a clear outside a group does not bump the epoch")
    T.eq(#lm.env.KART_LootHistory, 1, "and does not empty the log")
    T.truthy(said:find(lm.KART.L.LH_CLEAR_NEEDS_GROUP, 1, true),
        "and it names the reason rather than failing silently")
end

-- With no lootmaster set, nobody clears -- not even the raid leader -------------------------------
-- LC.IsLootOwner falls back to the raid leader while no lootmaster is configured, so the loot flow
-- survives the lootmaster walking out. That fallback was never a right to empty every log in the
-- raid, and through the shipped UI it was reachable from a five-man: lead one, press Clear History,
-- and an account-wide epoch rises that walks into the next raid ahead of everybody.
do
    local _, lm = F.NewRaid()
    local before
    RaidSim.As(lm, function()
        -- The raid config's own field, not KART_Settings: an EMPTY Lootmaster setting means "not
        -- configured" and is deliberately never written into the raid config (see LC.ApplyOwnConfig
        -- and B76), so clearing the setting cannot produce this state. This is the raid that never
        -- filled the field in -- the documented setup, and the one a five-man is.
        lm.KART.LC.raidConfig.lootmaster = ""
        before = lm.env.KART_LootHistoryEpoch
        lm.env.KART_LootHistory = { { time = time(), id = "1-ddd", epoch = before or 1 } }
    end)
    T.truthy(RaidSim.As(lm, function() return lm.KART.LC.IsLootOwner() end),
        "the raid leader still stands in for the loot flow")
    local said = ClearWith(lm)
    T.eq(lm.env.KART_LootHistoryEpoch, before, "but their clear does not bump the epoch")
    T.eq(#lm.env.KART_LootHistory, 1, "and does not empty the log")
    T.truthy(said ~= "", "and it says so instead of failing silently")
end

-- A peer's own epoch cannot switch off loot awarding for the raid --------------------------------
-- LH.heardEpoch drives LH.IsStale(), and LH.IsStale() is a hard early return in
-- Trade.AnnounceResult. It used to be raised with no authority check at all from two paths that
-- carry nothing but a peer's statement about its own client: the LC_HIST_REQ header a joiner
-- broadcasts, and the LC_HIST_EPOCH whisper any group member may send. One client whose epoch had
-- run ahead therefore put every client that heard it -- the lootmaster included -- into refusing to
-- award, for the rest of the night, with nothing printed anywhere.
do
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.As(council, function()
        council.env.KART_LootHistoryEpoch = 99      -- bumped somewhere else entirely
        council.KART.LH.RequestHistorySync()
    end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    for _, c in ipairs(sim.clients) do
        if c ~= council then
            T.eq(RaidSim.As(c, function() return c.KART.LH.IsStale() end), false,
                c.name .. " is not put out of action by a group member's own epoch")
        end
    end

    F.Drop(sim, 90, F.GLOVES)
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(90, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    T.truthy(#RaidSim.Messages(sim, "LC_RESULT") > 0, "and the raid can still award loot")
end

-- The same over LC_HIST_EPOCH: from a group member it changes nothing, from the loot owner it is
-- the wipe -------------------------------------------------------------------------------------
do
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.As(council, function() council.KART.LC.SendLC("LC_HIST_EPOCH:9") end)
    RaidSim.Drain(sim, 10)
    T.eq(RaidSim.As(raider, function() return raider.KART.LH.IsStale() end), false,
        "a group member's epoch broadcast does not make anybody stale")
    T.eq(raider.env.KART_LootHistoryEpoch, nil, "nor is it adopted")

    RaidSim.As(lm, function() lm.KART.LC.SendLC("LC_HIST_EPOCH:9") end)
    RaidSim.Drain(sim, 10)
    T.eq(raider.env.KART_LootHistoryEpoch, 9, "the loot owner's epoch is adopted")
    T.eq(RaidSim.As(raider, function() return raider.KART.LH.IsStale() end), false,
        "and adopting it is not a reason to read as behind the raid")
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
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "batch-1", "", 0, 2, GLOVES)

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
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "batch-2", "", 0, 2, GLOVES)

    RaidSim.As(raider, function()
        raider.KART.LH.HandleHistoryBatch("2:" .. lm.guid .. ":0:" .. record, lm.guid)
    end)

    T.eq(raider.env.KART_LootHistoryEpoch, 2, "raider adopts the loot owner's epoch from the batch")
    T.eq(#raider.env.KART_LootHistory, 1, "and stores the entry from it")
    T.eq(raider.env.KART_LootHistory[1] and raider.env.KART_LootHistory[1].epoch, 2,
        "stamped at the epoch it was answered at")
end

-- The two LH.AdmitEpoch guards, held one at a time -------------------------------------------------
-- LH.HandleHistoryBatch checks the batch HEADER's epoch and LH.HandleHistoryEntry checks each
-- RECORD's own. In every case above the two numbers are the same, so either guard alone caught
-- everything and deleting either one on its own left the whole suite green (mutation testing,
-- 2026-08-07) -- two guards, one of them provably free. The two blocks below separate them: each
-- reaches a state only ONE of them can refuse.

-- The header alone is above our epoch: only the batch-level guard can refuse this -----------------
-- The records claim our own epoch, so the per-record guard admits every one of them. What the batch
-- guard is for is stated in its own comment: a header we cannot admit discards the message WHOLE,
-- "not just entries that fail some later filter" -- because the header is the peer's claim about the
-- message, and a claim we cannot verify makes the contents unverifiable too.
do
    local _, _, council, raider = F.NewRaid()
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {}
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "hdr-only", "", 0, 1, GLOVES)

    RaidSim.As(raider, function()
        raider.KART.LH.HandleHistoryBatch("2:" .. council.guid .. ":0:" .. record, council.guid)
    end)

    T.eq(#raider.env.KART_LootHistory, 0,
        "a batch whose header we cannot admit is discarded whole, records and all")
    T.eq(raider.env.KART_LootHistoryEpoch, 1, "and its epoch is not adopted from a non-owner")
    RaidSim.As(raider, function()
        T.truthy(raider.KART.LH.IsStale(), "the refused header still leaves the client knowing it is behind")
    end)
end

-- The record alone is above our epoch: only the per-record guard can refuse this -------------------
-- Reached without a batch header at all. LH.HandleHistoryEntry is a public function and every direct
-- call in this suite enters it this way, so "the batch already checked" is not something it may
-- assume -- and what it must never do is store a row above this client's own epoch, which
-- LH.HistoryChecksum would then never look at again (see the block below).
do
    local _, _, council, raider = F.NewRaid()
    raider.env.KART_LootHistoryEpoch = 1
    raider.env.KART_LootHistory = {}
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "rec-only", "", 0, 2, GLOVES)

    RaidSim.As(raider, function()
        raider.KART.LH.HandleHistoryEntry(record, council.guid)
    end)

    T.eq(#raider.env.KART_LootHistory, 0,
        "a single record above our epoch is refused on its own account, with no batch header to help")
    T.eq(raider.env.KART_LootHistoryEpoch, 1, "and does not raise the epoch either")
end

-- Why that matters: a row above our own epoch is invisible to the divergence check ------------------
-- LH.HistoryChecksum only sums entries at the CURRENT epoch. That filter is the whole reason the two
-- guards above exist -- a row stored above our epoch is not merely wrong, it is unreachable: it takes
-- no part in the fingerprint the catch-up compares, so no peer ever notices it, no answer ever
-- mentions it, and it sits in the SavedVariable being exported for ever. Nothing observed that
-- consequence, so deleting the filter left the suite green too.
do
    local _, lm = F.NewRaid()
    local atEpoch, withFuture
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = 1
        lm.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "chk-here", epoch = 1 },
        }
        atEpoch = lm.KART.LH.HistoryChecksum()
        lm.env.KART_LootHistory[2] =
            { time = time() - 30, item = GLOVES, winner = "Sinja", winnerKey = "Player-1-S",
              reason = "OS", id = "chk-ahead", epoch = 2 }
        withFuture = lm.KART.LH.HistoryChecksum()
    end)
    T.truthy(atEpoch ~= 0, "the checksum is not simply zero for everything")
    T.eq(withFuture, atEpoch,
        "a row stored above our own epoch takes no part in the fingerprint peers compare")
end

-- ...and the catch-up therefore never asks about it --------------------------------------------------
-- The same fact end to end, which is what "held forever and never compared" actually looks like: the
-- asker and its peer agree on the fingerprint although the asker is carrying a row the peer has never
-- heard of, so the wire stays empty and nothing on either client can ever notice.
do
    local sim, lm, _, raider = F.NewRaid()
    local shared = { time = time() - 600, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
                     reason = "BIS", class = "MAGE", rollID = 1, id = "both-hold-this", epoch = 1 }
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = 1
        lm.env.KART_LootHistory = { shared }
    end)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 1
        raider.env.KART_LootHistory = {
            shared,
            -- The stray row. Newest, so it is also what the since-timestamp is taken from -- the
            -- incremental half of the request cannot see past it either.
            { time = time() - 60, item = GLOVES, winner = "Sinja", winnerKey = "Player-1-S",
              reason = "OS", class = "PRIEST", rollID = 2, id = "stray-ahead", epoch = 2 },
        }
    end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#RaidSim.Messages(sim, "LC_HIST_BATCH"), 0,
        "the two clients read as agreeing, though one is holding a row the other never heard of")
    T.eq(#raider.env.KART_LootHistory, 2, "and the stray row is still sitting there, uncompared")
end

-- The epoch an award was DECIDED in is not the epoch of whoever logs it ------------------------------
-- LH.LogHistory's decisionEpoch parameter exists because the two can be different numbers, and
-- stamping the local one would make a pre-wipe award look like part of the current epoch: it would
-- join the checksum, survive the next LH.AdoptEpoch, and be exported as this tier's -- on this client
-- alone, since nobody else holds it. Both wire paths normalise the two through LH.AdmitEpoch before
-- they get here (an award below our epoch is discarded, one above it is adopted first), so the only
-- place the parameter can be seen doing its job is at LH.LogHistory's own boundary -- and until this
-- block, replacing it with the local epoch changed nothing anywhere in the suite.
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = 3
        lm.env.KART_LootHistory = {}
        -- Decided at 2, logged by a client already at 3.
        lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 71, "Player-1-A", "pre-wipe-1", 2)
    end)

    T.eq(lm.env.KART_LootHistory[1] and lm.env.KART_LootHistory[1].epoch, 2,
        "the award is stamped with the epoch it was decided in, not this client's")
    T.eq(RaidSim.As(lm, function() return lm.KART.LH.HistoryChecksum() end), 0,
        "so it stays out of the fingerprint for an epoch it does not belong to")
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
-- that every client lands on the same epoch and the same multiset of ids.
--
-- Deterministic seed: a soak that cannot be re-run on the failing input is a soak that reports
-- something nobody can fix. Compare by RATE across runs, never by seed number.
--
-- What each part of this is here for, because an earlier version of it could not fail on the things
-- it claimed to check (code review, 2026-08-07):
--
--   * a MULTISET of ids, not a set keyed by id. C7 is "the award reaches the whole raid, ONCE", and
--     "once" is defined over the id -- so a set collapses two copies of one award into one key, and
--     a dedup that had broken outright, filling every log with doubles, read as convergence.
--   * the WINNER is part of that key. The winner is drawn at random per award, and until the key
--     included it that draw was inert: pinning it to a constant left the whole check green, so the
--     loop said nothing about a receiver that agreed which awards happened and disagreed about who
--     got them -- which is the one thing the raid actually argues about afterwards.
--   * EVERY client, not the three the fixture happens to name.
--   * the catch-up tokens are delayed and lost as well as LC_RESULT. Only LC_RESULT was ever held,
--     so LC_HIST_REQ / LC_HIST_BATCH / LC_HIST_EPOCH -- the whole catch-up machinery -- were only
--     ever exercised in one ordering, in order, with nothing lost.
--   * more than one client calls ClearHistory, and one of them is not entitled to -- and, separately,
--     a non-owner puts a higher epoch on the wire directly. ClearHistory REFUSES a non-owner before
--     it sends anything, so the entitlement half of the loop was only ever exercising that refusal;
--     nothing ever made LH.AdoptEpoch's IsSenderLootOwner gate the thing standing between one bad
--     client and every log in the raid, which is what it is for.
--   * somebody ports out and comes back, which is the case a raid-wide wipe exists for (C3).
local CATCHUP_TOKENS = { "LC_HIST_REQ", "LC_HIST_BATCH", "LC_HIST_EPOCH" }

do
    for seed = 1, 40 do
        math.randomseed(seed)
        local sim, lm, council, raider = F.NewRaid()
        -- Which tokens are currently delayed, and which are currently being lost. Kept apart because
        -- the wire checks Blackhole first: a token in both states is only ever dropped, so a test
        -- that put it in both would think it was exercising a delay and be exercising a loss.
        local held, dark = {}, {}

        for i = 1, 12 do
            local winner = ({ council, raider, lm })[math.random(1, 3)]
            if math.random() < 0.25 then RaidSim.Hold(sim, "LC_RESULT") end
            -- An award that nobody but the assigner ever hears. It is the checksum's job to notice
            -- (the hole is BEHIND the watermark by the time anyone asks), and the answer to it is a
            -- full reconcile -- which re-sends every award the asker already holds. That surplus is
            -- what the id dedup is for, and without a genuinely lost award nothing in this soak ever
            -- made a peer send one.
            local lostResult = math.random() < 0.2
            if lostResult then RaidSim.Blackhole(sim, "LC_RESULT") end

            -- One catch-up token per round, either merely slow or lost outright for a while.
            local tok = CATCHUP_TOKENS[math.random(1, #CATCHUP_TOKENS)]
            if not held[tok] and not dark[tok] then
                local r = math.random()
                if r < 0.2 then
                    RaidSim.Hold(sim, tok); held[tok] = true
                elseif r < 0.35 then
                    RaidSim.Blackhole(sim, tok); dark[tok] = true
                end
            end

            Award(sim, lm, 200 + i, F.GLOVES, winner, "BIS")
            if lostResult then RaidSim.Deliver(sim, "LC_RESULT") end

            if math.random() < 0.25 then RaidSim.Release(sim, "LC_RESULT") end
            for _, t in ipairs(CATCHUP_TOKENS) do
                if held[t] and math.random() < 0.4 then RaidSim.Release(sim, t); held[t] = nil end
                if dark[t] and math.random() < 0.4 then RaidSim.Deliver(sim, t); dark[t] = nil end
            end

            if i == 6 then RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end) end
            -- A second wiper, and one who may not: only the loot owner's word raises an epoch, so
            -- the council member's press must leave the raid exactly where it was. Both land while
            -- awards and epoch messages are still in flight, which is the ordering the merge rules
            -- exist for.
            if i == 8 then RaidSim.As(council, function() council.KART.LH.ClearHistory() end) end
            -- The same client's word, this time put on the wire directly rather than through the
            -- dialog that refuses it. LH.ClearHistory checks entitlement BEFORE it sends, so the
            -- press above never produced an unauthorised LC_HIST_EPOCH at all -- it exercised the
            -- refusal and stopped there, and the gate inside LH.AdoptEpoch that the whole scheme
            -- rests on was never asked anything by this loop. A number far above anything the
            -- lootmaster ever reaches, so adopting it would be unmistakable: every log in the raid
            -- emptied, on one group member's say-so.
            if i == 9 then
                RaidSim.As(council, function() council.KART.LC.SendLC("LC_HIST_EPOCH:99") end)
            end
            if i == 10 then RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end) end

            -- Ports out to the other split raid and comes back with nothing: a fresh client, no
            -- saved history, no epoch. Everything it ends up with has to arrive over the wire.
            if i == 7 then
                local member = raider.member
                RaidSim.Leave(sim, raider.name)
                RaidSim.Drain(sim, 30)
                raider = RaidSim.Join(sim, member)
                RaidSim.EnterWorld(sim, raider.name)
                RaidSim.Drain(sim, 60)
            end

            -- RaidSim.Reload REPLACES the client in the sim and returns the new one; the old
            -- `raider` reference becomes a corpse (see its own comment). Without capturing the
            -- return value here, every later iteration -- and the convergence assertions below --
            -- kept driving/reading the dead pre-reload client, which never receives another
            -- broadcast again. That made a real defect (the wire-guessed epoch, Task 6a Finding 2)
            -- indistinguishable from this harness bug: both left the post-reload raider looking
            -- behind the raid.
            if math.random() < 0.2 then raider = RaidSim.Reload(sim, raider.name) end

            -- A few seconds between drops, which is what a distribution looks like. Without it the
            -- whole run happens inside one second of time(): RaidSim.Drain only moves the clock while
            -- something is actually queued, so twelve awards, two wipes and a rejoin all carried the
            -- SAME timestamp -- and every since-timestamp comparison in the catch-up (which is what
            -- an incremental answer is) degenerated to comparing a number with itself.
            KARTTEST.AdvanceTime(5)
        end

        RaidSim.Release(sim, "LC_RESULT")
        for _, t in ipairs(CATCHUP_TOKENS) do
            RaidSim.Release(sim, t)
            RaidSim.Deliver(sim, t)
        end
        RaidSim.Drain(sim, 300)

        -- The evening's ordinary churn, which is what the catch-up is FOR: people port out and relog
        -- all night, and every one of those joins asks its peers for what it is missing. Far enough
        -- apart that HISTORY_SYNC_ANSWER_COOLDOWN has expired between the rounds.
        for _ = 1, 2 do
            KARTTEST.AdvanceTime(90)
            for _, c in ipairs(sim.clients) do
                RaidSim.As(c, function() c.KART.LH.RequestHistorySync() end)
            end
            KARTTEST.AdvanceTime(90)
            RaidSim.Drain(sim, 300)
        end

        -- And then the next raid night, because the once-a-night full reconcile is deliberately not
        -- available twice in one evening (design §3, variant C: "if it is not, tomorrow's first join
        -- pulls it"). A hole that survives the first night therefore has to close on the next one, or
        -- the merge rules are not converging at all -- they are merely usually lucky.
        --
        -- Logging in again IS the reset: LH.fullReconciled and LH.historySyncAnswered are memory-only,
        -- while the history and the epoch are SavedVariables and survive. Cheaper and more honest than
        -- winding the clock forward six hours.
        local names = {}
        for i, c in ipairs(sim.clients) do names[i] = c.name end
        for _, name in ipairs(names) do RaidSim.Reload(sim, name) end
        for _, name in ipairs(names) do RaidSim.EnterWorld(sim, name) end
        -- Past GATE_MAX_PARK: a council member comes back with its decided rolls restored and tabbed,
        -- so its own gate can be shut from the first instant, and the hard cap is what releases it.
        KARTTEST.AdvanceTime(120)
        RaidSim.Drain(sim, 300)
        KARTTEST.AdvanceTime(120)
        RaidSim.Drain(sim, 300)

        -- A COUNT per (id, winner) pair, not a set of ids: two copies of one award have to be
        -- visible as two, and a client that agrees which awards happened while recording a
        -- different winner for one of them has not converged either. Folding the winner into the
        -- key rather than asserting it separately is what makes the random winner draw above mean
        -- something -- with every award going to the same player, a receiver that stored the wrong
        -- winner would be storing the right one by accident.
        local function awardKeys(c)
            local s = {}
            for _, e in ipairs(c.env.KART_LootHistory or {}) do
                local k = tostring(e.id) .. " -> " .. tostring(e.winnerKey or e.winner)
                s[k] = (s[k] or 0) + 1
            end
            return s
        end
        -- Every reference held above is a corpse after the reloads (see RaidSim.Reload).
        local owner = sim.byName[lm.name]
        local wantIDs, wantEpoch = awardKeys(owner), owner.env.KART_LootHistoryEpoch

        -- Three: the epoch starts at 1 and the LOOTMASTER drew the line twice. This is an absolute
        -- anchor and not another comparison between clients, because agreement is not correctness
        -- here -- a raid that adopts one bad client's epoch adopts it in UNISON, so every
        -- client-against-client assertion below reads a perfectly converged raid sitting on a number
        -- nobody was entitled to announce. Deleting LH.AdoptEpoch's IsSenderLootOwner gate lands the
        -- whole raid on 99 (see the broadcast at i == 9) and is invisible to everything else here.
        T.eq(wantEpoch, 3,
            "seed " .. seed .. ": the raid ends on the epoch its lootmaster drew, and on no other")

        for _, c in ipairs(sim.clients) do
            T.eq(c.env.KART_LootHistoryEpoch, wantEpoch,
                "seed " .. seed .. ": " .. c.name .. " ends on the lootmaster's epoch")
            T.deep_eq(awardKeys(c), wantIDs,
                "seed " .. seed .. ": " .. c.name
                .. " holds exactly the lootmaster's awards, once each, to the same winners")
        end
    end
end
