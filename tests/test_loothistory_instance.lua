-- Which raid an award happened in: instance (the localized name) and instanceID (Blizzard's mapID),
-- next to each other on every award for the same reason difficulty sits beside difficultyID -- the
-- name is whatever the client's locale produced, the id is not.
--
-- Captured on LC.rollRaidSnapshot the moment the item enters the loot flow (a real roll starting or
-- a manual one) and read back by LH.LogHistory at award time, not read live there: LogHistory can run
-- long after the item dropped, once the lootmaster may have ported out or zoned, and a live read at
-- that point would silently write the wrong raid -- or none at all -- onto an award that plainly
-- belongs to the one it dropped in.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link

-- The ambient fixture instance (see tests/wow_stubs.lua). Restored explicitly at the top of every
-- section below rather than relied on as a default: other test files in this suite point
-- KARTTEST.instance elsewhere and never restore it, so a test that assumes the ambient value is
-- reading whatever the file before it left behind.
local VOIDSPIRE = { name = "The Voidspire", instanceType = "raid",
                     difficultyID = 16, difficultyName = "Mythic", mapID = 2912 }
local function InVoidspire() KARTTEST.instance = VOIDSPIRE end
-- A second, distinct raid -- different name AND different id, so a test can tell "the id travels
-- independently of the name" from "the two just happen to move together".
local QUELDANAS = { name = "March on Quel'Danas", instanceType = "raid",
                     difficultyID = 17, difficultyName = "Heroic", mapID = 2802 }
local function InQuelDanas() KARTTEST.instance = QUELDANAS end
-- Open world: difficultyID 0 is the sentinel LH.LogHistory already normalizes to nil for
-- difficultyID/difficulty, and the same sentinel now governs instance/instanceID (see
-- LC.SnapshotRollInstance). Give it its own nonzero mapID so a mutant that stops gating on
-- difficultyID and starts gating on mapID instead is not accidentally covered up by both being 0.
local OPEN_WORLD = { name = "Elwynn Forest", instanceType = "none",
                     difficultyID = 0, difficultyName = "", mapID = 37 }
local function InOpenWorld() KARTTEST.instance = OPEN_WORLD end
-- A name that actually contains a colon -- unrealistic for a real WoW instance, but the wire format
-- has to survive one regardless (same reasoning as winner/reason, which strip colons for the same
-- reason). This is what pins EntryRecord's `:gsub(":", "")` on the instance field specifically; a
-- test built only from realistic names (no colons) cannot fail if that stripping is dropped.
local COLON_RAID = { name = "Sunwell Plateau: The Trial", instanceType = "raid",
                      difficultyID = 20, difficultyName = "Mythic", mapID = 3079 }

InVoidspire()

-- ===================================================================================================
-- PRIORITY: an item link full of colons survives EntryRecord -> HandleHistoryEntry's parse -> the
-- stored entry, unchanged -- with the new fields present in the record and empty in this case, since
-- nothing was known about the instance for this award.
-- ===================================================================================================
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
              time = now, rollID = 70, class = "MAGE", id = "colon-check", epoch = 1 },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    local sent = RaidSim.Sent(sim, "LC_HIST_BATCH")
    T.eq(#sent, 1, "the catch-up answer goes out")
    -- A single small record packs to nothing (LC.PackPayload returns nil under its own byte floor)
    -- and travels plain, so the wire text itself can be inspected directly.
    T.truthy(sent[1].msg:find(GLOVES, 1, true) ~= nil,
        "the full item link, colons and all, is present verbatim on the wire -- the new fields did " ..
        "not shift where the item field starts")

    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the peer stored the award")
    T.eq(stored.item, GLOVES, "the item link survived the round trip unchanged, colons included")
    T.eq(stored.winner, "Alric", "the fields around the new ones are unaffected")
    T.eq(stored.instance, nil, "instance is absent, not an empty string, when nothing was known")
    T.eq(stored.instanceID, nil, "instanceID is absent too")
end

-- The same round trip, with real instance data present this time -----------------------------------
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
              time = now, rollID = 71, class = "MAGE", id = "instance-check", epoch = 1,
              instance = QUELDANAS.name, instanceID = QUELDANAS.mapID },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the peer stored the award")
    T.eq(stored.item, GLOVES, "the item link still survives, now with real data ahead of it")
    T.eq(stored.instance, QUELDANAS.name, "the instance name crossed the wire")
    T.eq(stored.instanceID, QUELDANAS.mapID, "the instance id crossed the wire too, independently")

    -- Pins the real EntryRecord output against an old client's pattern -- not a hand-built stand-in
    -- for it (see the block below, which only demonstrates the reasoning). A mutation that reordered
    -- the wire fields (e.g. instanceID before instance) but kept EntryRecord and the parser agreeing
    -- with EACH OTHER would sail through every round-trip assertion above; this is what would still
    -- catch it, because it inspects the actual bytes this build put on the wire.
    local OLD_PATTERN =
        "^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(%d+):(.*)$"
    local sent = RaidSim.Sent(sim, "LC_HIST_BATCH")
    T.eq(#sent, 1, "the answer for the real-instance award went out")
    local realRecord = sent[1].msg:match("^LC_HIST_BATCH:%d+:[^:]*:0:(.*)$")
    T.truthy(realRecord, "the plain (unpacked) record text is readable")
    T.eq((realRecord:match(OLD_PATTERN)), nil,
        "the record THIS BUILD actually sends still fails an old client's pattern outright, " ..
        "rather than being misread")
end

-- The instance field's own colons are stripped, exactly like winner and reason -- otherwise an
-- internal colon would shift every field after it, corrupting instanceID, epoch and the item link
-- that follows it -----------------------------------------------------------------------------------
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
              time = now, rollID = 72, class = "MAGE", id = "colon-instance-check", epoch = 1,
              instance = COLON_RAID.name, instanceID = COLON_RAID.mapID },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the award still arrives despite the colon in the instance name")
    T.eq(stored.instance, (COLON_RAID.name:gsub(":", "")),
        "the colon is stripped from the instance name, same as winner/reason")
    T.eq(stored.instanceID, COLON_RAID.mapID,
        "instanceID is unaffected -- the colon in the name did not shift it out of position")
    T.eq(stored.item, GLOVES,
        "and the item link after it, colons and all, still arrives whole -- an unstripped colon " ..
        "in instance would have shifted every field behind it, this one included")
end

-- ===================================================================================================
-- Field order: why the name goes before the id, and why an old client is safe either way it fails.
-- ===================================================================================================
do
    -- An old client's parser expects a bare (%d+) for the epoch right after `id`. Simulated here with
    -- the OLD 11-field pattern applied to a NEW-format record -- not by running an old build, which
    -- this suite has no way to do, but by asking the same question an old client's LH.HandleHistoryEntry
    -- would: does this string match my pattern at all.
    local OLD_PATTERN =
        "^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(%d+):(.*)$"

    local newRecord = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:some-id:%s:%d:%d:%s",
        time(), QUELDANAS.name, QUELDANAS.mapID, 1, GLOVES)

    T.eq((newRecord:match(OLD_PATTERN)), nil,
        "an old client's pattern cannot match a record carrying a raid NAME where it expects the " ..
        "epoch -- the whole record fails to parse and is discarded, not misread")

    -- The danger this placement avoids: if instanceID (a plain number) had been placed first instead
    -- of instance (a name), an old client's (%d+) would have matched it as the epoch. Demonstrated
    -- directly: a record with the id-then-name order DOES match the old pattern, and the epoch slot
    -- captures the instanceID.
    local idFirstRecord = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:some-id:%d:%s:%d:%s",
        time(), QUELDANAS.mapID, QUELDANAS.name, 1, GLOVES)
    local _, _, _, _, _, _, _, _, _, oldEpochSlot = idFirstRecord:match(OLD_PATTERN)
    T.eq(tonumber(oldEpochSlot), QUELDANAS.mapID,
        "id-before-name WOULD have let an old client read a real instanceID as the epoch -- " ..
        "confirming name-before-id is the safe order, not an arbitrary one")
end

-- Wire normalization: "0" and "" both fold to nil on receive, matching the snapshot side -------------
do
    InVoidspire()
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    local record = string.format("%d:16:72:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "zero-check", "", 0, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)

    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the entry was stored")
    T.eq(stored.instance, nil, "an empty instance field on the wire is stored as absent")
    T.eq(stored.instanceID, nil, "a zero instanceID on the wire is stored as absent, same as difficultyID")
end

-- ===================================================================================================
-- The design point: snapshot at roll start, not a live read at award time.
-- ===================================================================================================

-- The item enters the flow in one raid; by the time it is awarded, this client reads live as being
-- somewhere else entirely (ported out mid-distribution, C13/C14's operating reality). The award must
-- still carry the ORIGINAL raid, on every client that logs it -- the assigner and every peer that
-- receives the result.
do
    InVoidspire()
    local sim, lm, council, raider = F.NewRaid()
    F.Drop(sim, 80, F.GLOVES)

    -- Confirm the snapshot was actually taken before moving the goalposts -- this is what
    -- LC.SnapshotRollInstance is for, and the rest of this test is meaningless if it did not run.
    RaidSim.As(lm, function()
        local snap = lm.KART.LC.rollRaidSnapshot[80]
        T.truthy(snap, "the roll start snapshotted an instance")
        T.eq(snap.name, VOIDSPIRE.name, "...the one the client was actually in")
        T.eq(snap.id, VOIDSPIRE.mapID, "...id included")
    end)

    -- Every client in the raid now reads live as being in the open world -- exactly what a live
    -- GetInstanceInfo() read at award time would see if this were not snapshotted.
    InOpenWorld()

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(80, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)

    for _, c in ipairs({ lm, council, raider }) do
        local stored = c.env.KART_LootHistory[1]
        T.truthy(stored, c.name .. " logged the award")
        T.eq(stored.instance, VOIDSPIRE.name,
            c.name .. " kept the instance the item actually dropped in, not the live read at award time")
        T.eq(stored.instanceID, VOIDSPIRE.mapID, c.name .. " kept the instance id too")
    end
end

-- The same thing again, but with the raid's real clock between the drop and the award -- which is the
-- case the block above cannot reach, because it awards within the vote window.
--
-- A plain raider is not on the council, so Vote.PruneExpiredRolls frees the whole roll the moment the
-- VOTE deadline passes (20s by default) while the council is still deliberating. If the snapshot goes
-- with it, the award that lands minutes later finds nothing and falls back to a live read -- and the
-- raider has usually ported out by then, so it writes nil. That copy is permanent (LH.HandleHistoryEntry
-- dedups on the award id, so no catch-up ever repairs it) and silent (LH.HistoryChecksum sums ids only,
-- so the raider and the lootmaster report the same checksum while holding different data -- C14 exactly
-- as written). It is also the copy that matters: the winner is usually a plain raider, and their own
-- history is what goes to the Companion.
do
    InVoidspire()
    local sim, lm, council, raider = F.NewRaid()
    F.Drop(sim, 82, F.GLOVES)
    RaidSim.Drain(sim, 10)

    -- Past the vote deadline, still short of a decision: the council deliberates, the raider's client
    -- has already closed the item off its screen.
    KARTTEST.AdvanceTime(60)
    T.eq(F.HasVoteRow(raider, 82), false,
        "the plain raider's vote window closed while the council was still talking")
    T.eq(raider.KART.LC.rollItems[82], nil, "...and their roll state went with it")
    T.truthy(raider.KART.LC.rollRaidSnapshot[82],
        "but the raid snapshot did NOT -- the award has not been logged yet and it is the only thing " ..
        "that still knows which raid this item dropped in")

    -- Everyone has ported out by now, which is exactly what a live read at award time would see.
    InOpenWorld()

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(82, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)

    for _, c in ipairs({ lm, council, raider }) do
        local stored = c.env.KART_LootHistory[1]
        T.truthy(stored, c.name .. " logged the award")
        T.eq(stored.instance, VOIDSPIRE.name,
            c.name .. " still names the raid the item dropped in, a full vote window after the drop")
        T.eq(stored.instanceID, VOIDSPIRE.mapID, c.name .. " kept the instance id too")
    end
end

-- ...and the bound that replaces the clear: past the Bind-on-Pickup trade window the snapshot cannot
-- matter to any award still to come, so it goes -- the same age bound Trade.PruneExpiredLootStamps
-- puts on the BoP clock, for the same reason it is not cleared with the roll.
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 83, F.GLOVES)
    RaidSim.Drain(sim, 10)
    T.truthy(lm.KART.LC.rollRaidSnapshot[83], "the snapshot is there while the item can still be traded")

    KARTTEST.AdvanceTime(5 * 60 * 60) -- past TRADE_TIMEOUT_SECONDS (4h)
    RaidSim.As(lm, function() lm.KART.LC.Trade.ClearRollState(999123) end) -- any clear runs the sweep
    T.eq(lm.KART.LC.rollRaidSnapshot[83], nil,
        "past the trade window the snapshot is swept by age, so it cannot accumulate for the session")
end

-- LC.SnapshotRollInstance's own sentinel: a roll that starts while this client reads as being in the
-- open world snapshots nothing, rather than the zone name -- checked directly on the snapshot table,
-- not through an award, so this is about LC.SnapshotRollInstance specifically and not about
-- LH.LogHistory's separate live-fallback normalization tested further below.
do
    InOpenWorld()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 81, F.GLOVES)

    RaidSim.As(lm, function()
        local snap = lm.KART.LC.rollRaidSnapshot[81]
        T.truthy(snap, "the roll start still snapshots something")
        T.eq(snap.name, nil, "...but no name, since difficultyID is 0 (not really an instance)")
        T.eq(snap.id, nil, "...and no id either, even though GetInstanceInfo answers a real mapID")
    end)
end

-- Fallback: no snapshot exists for this roll (a manually-logged award with no matching roll, or a
-- roll this client never saw enter the flow) -- reads live instead ----------------------------------
do
    InQuelDanas()
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    -- rollID 999999 was never dropped on this client, so LC.rollRaidSnapshot holds nothing for it.
    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 999999, "Player-1-A")
    end)

    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the manual award was logged")
    T.eq(stored.instance, QUELDANAS.name, "with no snapshot to read, it falls back to a live read")
    T.eq(stored.instanceID, QUELDANAS.mapID, "id included in the live fallback too")
end

-- The live fallback normalizes the same sentinel the snapshot does: difficultyID == 0 means neither
-- field is written, not that the open-world zone gets recorded as the "instance" ---------------------
do
    InOpenWorld()
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 999998, "Player-1-A")
    end)

    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the manual award was logged")
    T.eq(stored.instance, nil,
        "the live fallback in the open world stores no instance name, even though GetInstanceInfo " ..
        "answers one (Elwynn Forest) -- difficultyID 0 says it does not count")
    T.eq(stored.instanceID, nil, "and no instanceID either, even though the live mapID is nonzero")
end

InVoidspire()
