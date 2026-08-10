-- Which raid an award happened in: instance (the localized name) and instanceID (Blizzard's mapID),
-- next to each other on every award for the same reason difficulty sits beside difficultyID -- the
-- name is whatever the client's locale produced, the id is not.
--
-- Captured on LC.rollRaidSnapshot the moment the item enters the loot flow (a real roll starting or
-- a manual one) and read back by LH.LogHistory at award time, not read live there: LogHistory can run
-- long after the item dropped, once the lootmaster may have ported out or zoned, and a live read at
-- that point would silently write the wrong raid -- or none at all -- onto an award that plainly
-- belongs to the one it dropped in.
--
-- Note what this field is NOT: converged. Each client snapshots its own GetInstanceInfo(), so two
-- clients can legitimately hold different names for the same award id -- somebody standing in the
-- previous raid's entrance when the item drops writes that raid, and nothing ever reconciles the two
-- (LH.HistoryChecksum sums ids only, and LH.HandleHistoryEntry dedups on the id, so whoever logged it
-- first keeps their answer). Harmless while it is a label nobody acts on, and written down here
-- because the Companion is about to render it: a disagreement about this field is expected, not a
-- defect to hunt.

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
-- The instance a raider WALKS INTO, which is the whole of B153 and is not a raid: the guild runs a
-- key or a delve while the council is still deciding. A party instance on purpose -- the code reads
-- difficultyID and nothing else, so this is the case a fixture built only from raids cannot state,
-- and it is the one that was measured (The Voidspire in, Operation Floodgate out).
local FLOODGATE = { name = "Operation Floodgate", instanceType = "party",
                     difficultyID = 8, difficultyName = "Mythic Keystone", mapID = 2773 }
local function InFloodgate() KARTTEST.instance = FLOODGATE end
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

    -- And the ORDINARY record, which is the one an old client will actually be handed most of the
    -- time: no instance known, so the field is empty. Empty is not a name, and the checks above say
    -- nothing about it -- but it has to fail the old pattern for the same reason, since an empty slot
    -- where (%d+) is expected is the only thing standing between an old client and reading the
    -- instanceID behind it as an epoch.
    local emptyRecord = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:some-id:%s:%d:%d:%s",
        time(), "", 0, 1, GLOVES)
    T.eq((emptyRecord:match(OLD_PATTERN)), nil,
        "a record with NO instance fails an old client's pattern too -- fail-closed is the whole " ..
        "field layout, not just the case where a raid name happens to be known")
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
-- What arrives on the wire is free text from a peer, and it lands in a SavedVariable kept forever and
-- rendered by the history window and (shortly) the Companion. Two separate things are pinned here,
-- because the guard can fail in two ways: by being deleted, and by being moved.
-- ===================================================================================================
do
    InVoidspire()
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)

    -- Escape codes, no colons -- the record is hand-built here, so a colon in this field would shift
    -- every field behind it and this would be a test about field alignment instead. Colour codes are
    -- the realistic payload anyway: a |c or |H that survives unescaped is a permanent hyperlink in a
    -- window that renders this string for the rest of the addon's life.
    local NASTY = "|cffff0000Raid|Hitem|h|r"
    local record = string.format("%d:16:73:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "inject-check", NASTY, QUELDANAS.mapID, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)

    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the entry was stored")
    T.eq(stored.instance, (NASTY:gsub("|", "||")),
        "every pipe in the instance name is doubled on receive, exactly like winner and reason -- " ..
        "an escape code stored raw here is injected into a SavedVariable that is displayed forever")

    -- ...and the guard has to run BEFORE the empty-string fold, not after it. Moved below, the fold's
    -- nil would come back out of `(instance or ""):gsub(...)` as an empty STRING, and every award with
    -- no instance would carry "" instead of being absent -- which is what the whole normalization
    -- below it exists to prevent, and what the export and the Companion would then have to special-case.
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    local blank = string.format("%d:16:74:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "inject-order-check", "", 0, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(blank, raider.guid) end)
    T.eq(lm.env.KART_LootHistory[1].instance, nil,
        "an absent instance is still absent, not an empty string -- the pipe guard runs before the " ..
        "empty-fold, not after it")
end

-- An all-digit instance name is blanked on receive, because this client STORES and RE-SENDS whatever a
-- peer sent it -----------------------------------------------------------------------------------
--
-- The field ordering is fail-closed for everything GetInstanceInfo() can produce, so no honest client
-- originates one of these. The hole is the relay: a hostile group member whispers one crafted record
-- with instance = "9999999", a 3.4.0 client stores it unvalidated, and EntryRecord later re-sends it
-- verbatim. A 3.3.x peer answering a catch-up from that client reads 9999999 in its own epoch slot --
-- and a bogus epoch from a loot owner is adopted by LH.AdmitEpoch/LH.AdoptEpoch, wiping every entry
-- below it. Blanking it costs a cosmetic field on one award.
do
    InVoidspire()
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)

    local EPOCH_SHAPED = "9999999"
    local record = string.format("%d:16:75:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "digit-instance", EPOCH_SHAPED, QUELDANAS.mapID, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)

    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the record is still stored -- the award is real, only the field is not")
    T.eq(stored.instance, nil,
        "an all-digit instance name is refused on receive, so this client can never re-send one that " ..
        "an older peer would read as an epoch")
    T.eq(stored.instanceID, QUELDANAS.mapID, "the fields around it are untouched")

    -- The one that proves it is not simply refusing digits everywhere: a real raid name that merely
    -- CONTAINS digits is legitimate and must survive.
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    local mixed = string.format("%d:16:76:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time(), "mixed-instance", "Ulduar 25", QUELDANAS.mapID, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(mixed, raider.guid) end)
    T.eq(lm.env.KART_LootHistory[1].instance, "Ulduar 25",
        "a raid name that merely contains digits still arrives whole")
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
        T.eq(snap.item, tostring(F.GLOVES),
            "...and the item, which is what tells a later look from outside the instance apart " ..
            "from a rollID Blizzard has since handed to something else (B150)")
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

-- ...and the same raider again, with a reload in the middle of it (B150) ----------------------------
--
-- The vote deadline is only half of what stands between the drop and the award. The other half is a
-- /reload, which in this guild happens constantly mid-distribution (MANIFEST.md, the operating
-- reality). LC.SaveSessionSnapshot writes the per-roll tables only for the rolls that are ON SCREEN
-- -- council tabs and vote rows -- and by the vote deadline a plain raider has neither, so the
-- snapshot had nothing to come back from. What the award then wrote is the live GetInstanceInfo()
-- read this whole feature exists to avoid, permanently (the catch-up dedups on the award id) and
-- silently (LH.HistoryChecksum sums ids only). Asserted on the RAIDER, not the lootmaster: the
-- lootmaster still holds the council tab, so their copy was never the broken one.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 85, F.GLOVES)
    RaidSim.Drain(sim, 10)

    -- Past the vote deadline: the raider's row is gone, so there is nothing on screen for
    -- LC.SaveSessionSnapshot to carry this roll under.
    KARTTEST.AdvanceTime(60)
    T.eq(F.HasVoteRow(raider, 85), false, "the plain raider's vote row is gone before the reload")

    -- Ported out and THEN reloaded, in that order, which is the order the guild actually produces --
    -- somebody leaves for the other raid and relogs there while the council is still talking. It is
    -- also the only order that measures anything: reloading while still standing in the raid lets the
    -- catch-up re-snapshot the right answer by luck, so the snapshot could be lost entirely and every
    -- assertion below would still pass.
    InOpenWorld()

    raider = RaidSim.Reload(sim, "Alric")
    RaidSim.EnterWorld(sim, "Alric")
    -- A reload leaves them with no council list and Trade.HandleResult refuses an award from somebody
    -- it cannot confirm is council -- a raid produces roster changes constantly, and without one the
    -- award never reaches this client at all and the assertions below would pass on an empty history.
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(0)

    local snap = raider.KART.LC.rollRaidSnapshot[85]
    T.truthy(snap and snap.name == VOIDSPIRE.name,
        "the raid this item dropped in came back with the reload, for a roll that was on no list -- " ..
        "and the catch-up that re-announces the item did not overwrite it with the open world")

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(85, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)

    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the reloaded raider logged the award")
    T.eq(stored.instance, VOIDSPIRE.name,
        "and it still names the raid the item dropped in, across the vote deadline AND a reload")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "the instance id survived the reload too")
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

-- End Round does not take it either, which is the same exception LC.rollLootedAt has had all along
-- and was decided for this table on 2026-08-09 (see the comment in LC.ClearAllRolls).
--
-- Not a hypothetical ordering: End Round is one addon message and it does not reach every client at
-- the same moment -- "End Round did not end it for one council member, three rounds running" is on
-- the Manifest's own failure list (B118). So a raider can take LC_END and the award for the same item
-- in that order, and on 2026-08-03 somebody did. Driven that way here: the raider is handed End Round
-- while the council is still deciding, then the decision arrives. Wiping the snapshot there sent the
-- award back to the live GetInstanceInfo() read, which by then answers the open world -- and since the
-- table IS KART_LCTrades.raids, the wipe emptied the SavedVariable too, so a reload afterwards could
-- not repair it either.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 92, F.GLOVES)
    RaidSim.Drain(sim, 10)

    InOpenWorld()
    RaidSim.As(raider, function() raider.KART.LC.HandleEndRound(lm.guid) end)
    T.is_nil(raider.KART.LC.rollItems[92], "the raider's roll state is gone with the round")

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(92, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)

    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the award still reached the raider after End Round")
    T.eq(stored.instance, VOIDSPIRE.name,
        "and it names the raid the item dropped in -- End Round ends the ROLLS, not the record of " ..
        "where they came from")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "id included")
    T.truthy(raider.env.KART_LCTrades.raids[92],
        "...and the saved store still holds it, so a reload after End Round cannot lose it either")
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

-- ...and the other half of that sentinel: a read from outside an instance must not ERASE a raid this
-- roll already has (B150), when the caller is one that may inherit -- Blizzard re-raising this
-- client's own roll window, or the catch-up re-announcing a still-open item to a client that has just
-- reloaded. Either runs the snapshot a second time, and by then that client is usually standing
-- somewhere else, so an unconditional write would replace the answer the reload just rescued with the
-- live read the field exists to avoid. Driven directly here, because the two calls are what is under
-- test; the routes that produce them are driven end to end further down (B151).
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 86, F.GLOVES)
    T.eq(lm.KART.LC.rollRaidSnapshot[86].name, VOIDSPIRE.name, "the drop named the raid")

    InOpenWorld()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(86, GLOVES) end)
    local snap = lm.KART.LC.rollRaidSnapshot[86]
    T.eq(snap.name, VOIDSPIRE.name, "a second look from the open world leaves the raid standing")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")
end

-- ...but only for the SAME ITEM, which is half of what makes the rule above safe rather than a second
-- way of writing the wrong raid (B150); the other half is the caller, driven at the foot of this file
-- (B151). Blizzard reuses rollIDs and this table deliberately outlives the roll, so the number alone
-- proves nothing. Well inside the trade window on purpose: two raids in one evening is normal here,
-- so AGE cannot tell the two cases apart.
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 88, F.GLOVES)
    T.eq(lm.KART.LC.rollRaidSnapshot[88].name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(60 * 60) -- an hour later, still well inside the 4h trade window
    InOpenWorld()
    local WEAPON = KARTTEST.items[F.WEAPON].link
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(88, WEAPON) end)

    local snap = lm.KART.LC.rollRaidSnapshot[88]
    T.truthy(snap, "the roll still has an entry")
    T.is_nil(snap.name,
        "a DIFFERENT item under the same rollID is a new roll, so it does not inherit the raid the " ..
        "previous one dropped in -- the entry is blank, not last night's raid")
    T.is_nil(snap.id, "and no id either")

    -- And the award proves it is not merely the table that is right: this is the value that becomes
    -- permanent (LH.HandleHistoryEntry dedups on the award id) and checksum-invisible.
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 88, "Player-1-A")
    end)
    T.eq(lm.env.KART_LootHistory[1].instance, nil,
        "so the award carries no raid rather than confidently naming the wrong one")
end

-- An item this client could not identify counts as DIFFERENT, including when NEITHER side knows it.
-- Unknown matching unknown would inherit across exactly the reuse the check above refuses.
--
-- The row with no item is not invented: an announcement whose item part is empty is a payload shape
-- LC.HandleStart still accepts and resolves locally, so a client can genuinely hold the raid for a
-- roll it cannot name the item of.
do
    InVoidspire()
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function() raider.KART.LC.HandleStart("89:20:", lm.guid) end)
    local first = raider.KART.LC.rollRaidSnapshot[89]
    T.truthy(first, "an announcement with no item part still snapshots the raid")
    T.eq(first.name, VOIDSPIRE.name, "...naming it")
    T.is_nil(first.item, "...with no item, because the payload carried none")

    InOpenWorld()
    RaidSim.As(raider, function() raider.KART.LC.SnapshotRollInstance(89, nil) end)
    local snap = raider.KART.LC.rollRaidSnapshot[89]
    T.truthy(snap, "the roll still has an entry")
    T.is_nil(snap.name,
        "an unknown item does not match an unknown item -- two blanks are not proof this is the " ..
        "same roll, and the raid is not kept on them")
end

-- ...and the same keep from INSIDE another instance, which is B153 and is a REVERSAL: until
-- 2026-08-10 this branch overwrote unconditionally, and the block that stood here asserted exactly
-- that ("standing in a raid, the snapshot is taken again -- the keep is for the blank read, not for
-- every read"). The justification was that a read from inside an instance is a first-hand answer
-- about where this client is standing. It is -- and this field records where the ITEM DROPPED, which
-- for a repeat is a different question. The raider ports into a key while the council deliberates and
-- his award named the dungeon: measured at 5s, 30s and 90s alike, on shipped code identical back to
-- 70fff6d. So the keep is no longer gated on the branch, and the assertion is turned round with it.
--
-- Driven directly here, on the two calls under test; the route that actually produces them -- the
-- owner re-announcing a still-open roll to a raider who has walked out -- is at the foot of this file.
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 90, F.GLOVES)
    T.eq(lm.KART.LC.rollRaidSnapshot[90].name, VOIDSPIRE.name, "the drop named the raid")

    InFloodgate()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(90, GLOVES) end)
    local snap = lm.KART.LC.rollRaidSnapshot[90]
    T.eq(snap.name, VOIDSPIRE.name,
        "a second look from inside ANOTHER instance leaves the raid the item dropped in standing -- " ..
        "where this client walked to is not a second opinion about where the item dropped")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")

    -- The other raid, not just the other dungeon: docs/MANIFEST.md's operating reality is people
    -- porting out of one raid INTO ANOTHER, so a rule that only survived non-raid instances would
    -- miss the case it was written for -- and the code reads difficultyID, which cannot tell them
    -- apart, so nothing but a test says which of the two this covers.
    InQuelDanas()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(90, GLOVES) end)
    T.eq(lm.KART.LC.rollRaidSnapshot[90].name, VOIDSPIRE.name,
        "and walking into a second RAID does not take it either")
end

-- What the keep did NOT become on this branch: unconditional. Three things still overwrite a row from
-- inside an instance, and each is a mutation the block above cannot see on its own.
do
    -- A caller that can prove the item is only just being announced. Both manual doors do, and the
    -- number they hand out is minted by this client (LC.nextManualRollID), so it comes round again on
    -- its own counter -- this time with the client standing in a raid rather than in the open world,
    -- which is what the manual block further down drives.
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 95, F.GLOVES)
    T.eq(lm.KART.LC.rollRaidSnapshot[95].name, VOIDSPIRE.name, "the drop named the raid")

    InQuelDanas()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(95, GLOVES, true) end)
    T.eq(lm.KART.LC.rollRaidSnapshot[95].name, QUELDANAS.name,
        "a caller declaring a NEW drop still overwrites from inside an instance -- newDrop is what " ..
        "separates a fresh announcement from a repeat, and the fresh one is never kept")
    T.eq(lm.KART.LC.rollRaidSnapshot[95].id, QUELDANAS.mapID, "id included")

    -- A BLANK row is no answer rather than an older one, so the read from inside improves on it. This
    -- is the repair route the `prev.name ~= nil` half of the keep exists for: a client that was
    -- zoning, dead outside or freshly logged in when the announcement first landed holds a blank, and
    -- an in-instance read is the only thing that can ever name the raid for him.
    InOpenWorld()
    RaidSim.As(raider, function() raider.KART.LC.SnapshotRollInstance(99, GLOVES) end)
    T.is_nil(raider.KART.LC.rollRaidSnapshot[99].name, "the first read, from outside, named nothing")
    InVoidspire()
    RaidSim.As(raider, function() raider.KART.LC.SnapshotRollInstance(99, GLOVES) end)
    T.eq(raider.KART.LC.rollRaidSnapshot[99].name, VOIDSPIRE.name,
        "a blank row does not block the write -- being told about the item again while standing in " ..
        "the raid is what gives this client a raid at all")
    T.eq(raider.KART.LC.rollRaidSnapshot[99].id, VOIDSPIRE.mapID, "id included")

    -- And a row for a DIFFERENT item is the previous tenant of a reused rollID (B150), inside an
    -- instance exactly as outside one.
    InQuelDanas()
    local WEAPON = KARTTEST.items[F.WEAPON].link
    RaidSim.As(raider, function() raider.KART.LC.SnapshotRollInstance(99, WEAPON) end)
    T.eq(raider.KART.LC.rollRaidSnapshot[99].name, QUELDANAS.name,
        "a different item under the same number is a new roll and takes the raid it is standing in, " ..
        "not the one the previous tenant dropped in")
end

-- ...and the sweep that has to run before the keep now runs on this branch too, which it did not have
-- to before: a row older than the trade window is last night's, and inside an instance it would
-- otherwise be kept forever by a rollID Blizzard has since reused for the same item.
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 79, F.GLOVES)

    KARTTEST.AdvanceTime(5 * 60 * 60) -- past TRADE_TIMEOUT_SECONDS (4h)
    InQuelDanas()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(79, GLOVES) end)
    T.eq(lm.KART.LC.rollRaidSnapshot[79].name, QUELDANAS.name,
        "past the trade window the old raid is swept before the keep can read it, so the roll takes " ..
        "the raid it is actually in rather than last night's")
    T.eq(lm.KART.LC.rollRaidSnapshot[79].id, QUELDANAS.mapID, "id included")
end

-- ...but only while that raid can still belong to an award. Past the trade window it is last night's,
-- and a rollID Blizzard has since reused must not inherit it -- which is what keeps the rule above
-- from turning a stale entry into a permanent wrong answer.
do
    InVoidspire()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 87, F.GLOVES)

    KARTTEST.AdvanceTime(5 * 60 * 60) -- past TRADE_TIMEOUT_SECONDS (4h)
    InOpenWorld()
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(87, GLOVES) end)
    -- The entry EXISTS and is blank, which is not the same thing as being gone -- and the difference
    -- is load-bearing at LH.LogHistory, which reads "no snapshot" as permission to look live. An
    -- assertion that only says "no name" passes either way and would let the sweep-then-write become
    -- a plain sweep.
    local snap = lm.KART.LC.rollRaidSnapshot[87]
    T.truthy(snap, "the roll is snapshotted again rather than left with nothing")
    T.is_nil(snap.name,
        "a raid older than the trade window is not inherited -- it is swept first, so what the roll " ..
        "gets is the open world's own answer and not last night's")
    T.is_nil(snap.id, "and no id either")
end

-- The blank entry is REWRITTEN, not merely left alone, and that is what keeps it alive.
--
-- Two mutations hide here and nothing else in the suite sees either. Keeping on `prev ~= nil` instead
-- of on a NAMED prev never refreshes a blank row's `at`, so the sweep eventually drops it -- and a
-- roll with no snapshot at all is exactly what LH.LogHistory reads as permission to take a live
-- GetInstanceInfo(). The second is on the reader itself: `if snapshot then` deciding to look live only
-- when the snapshot has a NAME does the same thing in one step. Both end with the award naming
-- whatever raid the client happens to be standing in hours later, which is the failure this whole
-- field exists to prevent -- and this raid genuinely is somewhere else by then.
do
    InOpenWorld()
    local sim, lm = F.NewRaid()
    F.Drop(sim, 91, F.GLOVES)
    T.truthy(lm.KART.LC.rollRaidSnapshot[91], "a drop outside an instance still snapshots something")
    T.is_nil(lm.KART.LC.rollRaidSnapshot[91].name, "...blank, since difficultyID is 0")

    -- Three hours on, the catch-up re-announces the still-open item. Still outside an instance, so
    -- this is the keep branch reading a BLANK previous answer.
    KARTTEST.AdvanceTime(3 * 60 * 60)
    RaidSim.As(lm, function() lm.KART.LC.SnapshotRollInstance(91, GLOVES) end)

    -- Ninety more minutes: 4.5h since the drop, but only 1.5h since the rewrite above.
    KARTTEST.AdvanceTime(90 * 60)
    InQuelDanas()
    RaidSim.As(lm, function() lm.KART.LC.Trade.ClearRollState(999125) end) -- any clear runs the sweep
    T.truthy(lm.KART.LC.rollRaidSnapshot[91],
        "the blank entry survives the sweep, because the second look rewrote its `at` rather than " ..
        "returning early")

    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 91, "Player-1-A")
    end)
    local stored = lm.env.KART_LootHistory[1]
    T.truthy(stored, "the award was logged")
    T.eq(stored.instance, nil,
        "and it names NO raid -- a blank snapshot is an answer (this item dropped outside an " ..
        "instance), not a gap for the live read to fill with wherever this client stands now")
    T.eq(stored.instanceID, nil, "no id either")
end

-- ===================================================================================================
-- B151/B152: the same rollID, the same item -- who may inherit the raid, and who may not
-- ===================================================================================================
-- The item check above is not enough on its own, and the blocks here are the routes rather than the
-- function: what a route can drive, and a direct call cannot, is WHO IS CALLING.
--
-- The answer is not the same for every door, and it is not the same for every door that ANNOUNCES.
-- Only the two manual doors can prove an item is being named for the first time. LC.HandleStart
-- cannot: it serves the catch-up AND the owner's own re-announcement of a roll Blizzard re-raised,
-- and neither the message nor this client's state tells either of those apart from a genuinely new
-- drop under a number Blizzard has handed out again. It therefore keeps -- see the next block for
-- what that costs, which is measured here rather than argued away.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    -- Alric is dead when the boss dies, so Blizzard raises no roll on his client and the announcement
    -- is the only thing that reaches him: LC.HandleStart, the path the keep used to fire on.
    F.Drop(sim, 93, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[93] or {}).name, VOIDSPIRE.name,
        "the first raid's drop named the raid on the raider who only heard about it")

    -- The round ends, and an hour later the guild is in a different raid. The snapshot deliberately
    -- survives End Round (see LC.ClearAllRolls), which is exactly why the row under 93 is still there.
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    RaidSim.Drain(sim, 10)
    KARTTEST.AdvanceTime(60 * 60) -- still well inside the four-hour trade window

    InQuelDanas()
    -- A drop under a number nobody has used before, taken in the same breath as the reused one: it is
    -- what says the raid really did move, on the addon's own reading rather than on the fixture's.
    -- The lootmaster's snapshot for 93 can no longer say it (see below), and a scenario that cannot
    -- show its own premise is a scenario asserting nothing.
    F.Drop(sim, 78, F.WEAPON)
    T.eq((lm.KART.LC.rollRaidSnapshot[78] or {}).name, QUELDANAS.name,
        "the guild really is in the second raid -- a fresh number dropping here names it")

    F.Drop(sim, 93, F.GLOVES, { noRollFor = { Alric = true } })
    -- ...and this time Alric has ported out, which is what puts his read on the difficultyID == 0
    -- branch when the announcement lands.
    InOpenWorld()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)

    -- The lootmaster is standing in the second raid and his snapshot names the FIRST one. That is
    -- B153's fix widening this entry, and it is the assertion this block used to make the other way
    -- round ("the lootmaster, who is standing in it, names the second raid"): until 2026-08-10 the
    -- keep was refused for anyone inside an instance, so B151 cost the wrong raid only to clients who
    -- were outside. It now costs it to all of them, him included. Traded knowingly (see
    -- LC.SnapshotRollInstance): the narrower answer only held for the case retail raid loot does not
    -- produce -- one council-eligible itemID dropping in two different raid instances inside four
    -- hours, under a rollID Blizzard reused for it -- while what it cost was the raider porting out,
    -- which is every evening.
    T.eq((lm.KART.LC.rollRaidSnapshot[93] or {}).name, VOIDSPIRE.name,
        "and even the lootmaster standing in the second raid inherits the FIRST one now, because " ..
        "nothing on any client separates a reused number from the same drop being announced again")

    -- THE KNOWN COST, HELD OPEN ON PURPOSE (B151). The raider standing outside inherits raid ONE's
    -- name for raid TWO's drop, because an announcement of a reused number and a repeat of the first
    -- announcement are the same bytes and the same client state. Asserted as what it is rather than
    -- left to drift: it is permanent (LH.HandleHistoryEntry dedups on the award id) and
    -- checksum-invisible (LH.HistoryChecksum sums ids only), and the alternative -- refuse the keep
    -- here -- costs the ported-out raider his raid on an ordinary evening, which is B152 and is the
    -- block below. Reaching it needs one council-eligible itemID to drop in two different raid
    -- instances inside four hours, which retail raid loot does not do (Manifest C6).
    local snap = raider.KART.LC.rollRaidSnapshot[93]
    T.truthy(snap, "the raider snapshotted the second drop too")
    T.eq(snap.name, VOIDSPIRE.name,
        "and it still names the FIRST raid -- the accepted cost, because nothing in an announcement " ..
        "separates a reused number from the same drop being said again")
    T.eq(snap.id, VOIDSPIRE.mapID, "id and name travel together, right or wrong")

    -- The value that becomes permanent. Asserted on the plain raider, because the award is logged on
    -- every client from its own snapshot and his is the one that carries the wrong answer.
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(93, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    local stored = raider.env.KART_LootHistory[1]
    T.truthy(stored, "the raider logged the award")
    T.eq(stored.instance, VOIDSPIRE.name,
        "so his award names the wrong raid, which is what B151 costs and what the note in " ..
        "LC.SnapshotRollInstance says it costs")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "id too")
end

-- B152: THE SAME DOOR TWICE -- a second LC_DROP for a roll this client has already been told about.
--
-- This is the route the suite never drove, and it is why "an announcement is always an item dropping
-- now" survived a full mutation table: no mutation can find a route nothing drives. Blizzard re-raises
-- START_LOOT_ROLL for a roll that is still in progress -- the addon says so in the present tense in
-- LC.OnStartLootRoll's batch note, in LC.HandleStart's deadline note, and in tests/test_lc_rolls.lua
-- ("the re-raised roll is announced again") -- so the OWNER's handler runs a second time and an
-- ordinary LC_DROP goes out again with the same rollID and the same item. No catch-up, no reload, no
-- message the raider asked for.
--
-- And by then the raider is normally somewhere else: "Leute z.B. schon aus dem Raid porten und in
-- einen anderen gehen während die Lootverteilung startet ist normal" (docs/MANIFEST.md, the
-- operating reality, quoted as it stands there). Alric is dead when the boss dies, so the
-- announcement is the only thing that ever reaches him -- the one client for whom this snapshot has
-- no second source at all.
--
-- Driven through the wire on both sides, not by calling the handler: the whole point is that the
-- SECOND message is indistinguishable from the first, and only the owner's own re-raise produces it.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 96, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[96] or {}).name, VOIDSPIRE.name,
        "the drop named the raid on the raider who only heard about it")
    T.truthy(raider.KART.LC.rollAnnounced[96],
        "...and he counts as told about it, which is what makes the next message a REPEAT")

    -- Blizzard re-raises the still-running roll on the owner, who is of course still standing in the
    -- raid; the raider has ported out by the time the second announcement lands.
    KARTTEST.AdvanceTime(5)
    F.Drop(sim, 96, F.GLOVES, { noRollFor = { Alric = true } })
    InOpenWorld()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)

    T.eq(#RaidSim.Sent(sim, "LC_DROP"), 2,
        "the owner really did announce the same roll a second time -- the same door, twice")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0,
        "and nothing repaired anything: no catch-up was sent, so what reached him is the ordinary " ..
        "announcement and nothing else")
    T.eq((lm.KART.LC.rollRaidSnapshot[96] or {}).name, VOIDSPIRE.name,
        "the owner, still inside, still names the raid")

    local snap = raider.KART.LC.rollRaidSnapshot[96] or {}
    T.eq(snap.name, VOIDSPIRE.name,
        "and being told about the item AGAIN from the open world does not take the raid off it -- " ..
        "which is exactly what a fix that believed only the catch-up repeats an announcement did")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(96, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    local stored = raider.env.KART_LootHistory[1] or {}
    T.eq(stored.instance, VOIDSPIRE.name,
        "so the award on his own client still names the raid the item dropped in, rather than the " ..
        "blank an open-world read would have written")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "id on the award too")
end

-- ...and the same door twice again, this time with the raider's own row already GONE.
--
-- Written because of a candidate fix that looked like it worked: keep the raid when this client is
-- already flagged as told about the roll (LC.rollAnnounced). That flag does not live as long as the
-- snapshot does -- Vote.PruneExpiredRolls hands a plain raider's expired roll to
-- Trade.ClearRollState, which clears it about a second after the vote deadline (20s by default),
-- while the snapshot has to survive until the AWARD, which lands whenever the council is done. So the
-- flag is nil for most of the window this rule exists for, and a keep resting on it blanks the raid
-- for exactly the raider it was written for. Measured on this scenario: green at a 5-second gap,
-- red at 19, 25 and 45.
--
-- Nothing repairs him here either: no catch-up is sent (asserted), because he asked for nothing --
-- he is not on the council, his vote row simply ran out, and he never reloaded.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 97, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[97] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(45) -- past the vote deadline: his row, and the flag with it, are swept
    T.is_nil(raider.KART.LC.rollAnnounced[97],
        "his roll is gone, so nothing on this client still says it was ever announced to him")

    F.Drop(sim, 97, F.GLOVES, { noRollFor = { Alric = true } })
    InOpenWorld()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0, "and no repair was involved")
    T.eq((raider.KART.LC.rollRaidSnapshot[97] or {}).name, VOIDSPIRE.name,
        "the raid survives the repeat anyway -- the keep cannot depend on state the vote deadline " ..
        "takes away, because the award it is kept for lands long after that")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(97, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    T.eq((raider.env.KART_LootHistory[1] or {}).instance, VOIDSPIRE.name,
        "and so does the award, on the client whose row is the only copy of it")
end

-- The other side of the same rule: the catch-up repeats an announcement as well, and it is what
-- repairs the raider who ported out and RELOADED mid-distribution. Both repair routes -- the state
-- request's LC.SendOpenRolls and the heartbeat's LC.HandleRollRequest -- answer with that one token,
-- so this covers the message half of the re-announce; the block above covers the other half.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 94, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[94] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    -- Past the vote deadline, so his row is pruned and there is nothing of this roll on his screen for
    -- LC.SaveSessionSnapshot to write down. KART_LCTrades is what carries the raid across (B150).
    KARTTEST.AdvanceTime(60)
    local droppedAt = (raider.KART.LC.rollRaidSnapshot[94] or {}).at
    InOpenWorld() -- he ports out, then reloads
    raider = RaidSim.Reload(sim, "Alric")
    T.is_nil(raider.KART.LC.rollAnnounced[94],
        "the reload lost the announcement, which is what lets the catch-up through at all")
    T.eq((raider.KART.LC.rollRaidSnapshot[94] or {}).name, VOIDSPIRE.name,
        "...but not the raid, which came back off disk")

    -- No hand-driven message: the state request his own recovery sends is answered with the still-open
    -- roll, which is the route the keep exists for.
    RaidSim.EnterWorld(sim, "Alric")
    RaidSim.Drain(sim, 10)
    T.truthy(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP") > 0, "the owner re-announced the open roll to him")
    T.truthy(raider.KART.LC.rollAnnounced[94], "and this time he took it")

    local snap = raider.KART.LC.rollRaidSnapshot[94] or {}
    T.eq(snap.name, VOIDSPIRE.name,
        "and the raid it dropped in survived being told about it again from the open world")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")
    T.eq(snap.at, droppedAt,
        "the kept row keeps the DROP's timestamp rather than being rewritten with a fresh one, so it " ..
        "dies four hours after the item was looted -- which is when its trade window closes and no " ..
        "award can still be coming -- and not four hours after the last re-announce")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(94, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    T.eq((raider.env.KART_LootHistory[1] or {}).instance, VOIDSPIRE.name,
        "so the award still names the raid the item dropped in")
end

-- And the door with no message behind it: Blizzard hands this client's own roll window back after a
-- reload (LC.rollsSeenWhileUnaware is written for that same moment), which runs LC.OnStartLootRoll a
-- second time -- by then with the raider standing in the open world. A loot roll is only ever raised
-- on somebody who was in the instance when the boss died, so a roll arriving here while this client
-- reads as outside one cannot be a new drop, and it may inherit.
--
-- Merrit rather than Alric: he is the raider who clicks Blizzard's roll himself (lcAutoPass = false),
-- and a client that has already passed has no roll window left for the game to hand back.
do
    InVoidspire()
    local sim, _, council = F.NewRaid()
    F.Drop(sim, 98, F.GLOVES) -- his own Blizzard roll this time
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((council.KART.LC.rollRaidSnapshot[98] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(60)
    InOpenWorld()
    council = RaidSim.Reload(sim, "Merrit")
    RaidSim.EnterWorld(sim, "Merrit")
    RaidSim.Drain(sim, 10)
    T.truthy(council.KART.LC.sessionActive,
        "the reloaded client is back in the session, so its roll handler runs to the end")

    KARTTEST.AdvanceTime(30)
    RaidSim.As(council, function()
        KARTTEST.FireEvent("START_LOOT_ROLL", 98)
        council.KART.LC.OnStartLootRoll(98)
    end)
    T.eq(council.KART.LC.rollLootedAt[98], time(),
        "the handler ran all the way through -- it re-stamped the trade clock unconditionally")
    T.eq((council.KART.LC.rollRaidSnapshot[98] or {}).name, VOIDSPIRE.name,
        "...and left the raid standing, because this is his own roll coming back and not a new drop")
end

-- ===================================================================================================
-- B153: the same repeats again, from INSIDE ANOTHER INSTANCE -- the routes nothing drove
-- ===================================================================================================
-- Every block above sends the raider to the OPEN WORLD, and that is the whole of why B153 lived
-- through three rounds of this mechanism: no mutation can find a route nothing drives. The difference
-- is not cosmetic -- a blank read and a read from Operation Floodgate take different branches of
-- LC.SnapshotRollInstance, and until 2026-08-10 the second one overwrote the raid unconditionally, so
-- the award named the key the raider had walked into. Measured on shipped code at gaps of 5s, 30s and
-- 90s, identical back to 70fff6d.
--
-- What the guild actually does, in the maintainer's words: "In Midnight gibt es mehrere Raids mit
-- wenig Bossen, d.h. dass Leute z.B. schon aus dem Raid porten und in einen anderen gehen während die
-- Lootverteilung startet ist normal." (docs/MANIFEST.md, the operating reality.)
--
-- The same four doors as above, one block each, because each is reached on a client the others are
-- not.

-- 1. The owner's own re-announcement, with the roll still live -- the ordinary case, and the one that
--    needs nothing to go wrong: Blizzard re-raises START_LOOT_ROLL on the owner, a second LC_DROP
--    goes out, and by then the raider is in a key. Alric is dead when the boss dies, so the
--    announcement is the only thing that ever reaches him.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 100, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[100] or {}).name, VOIDSPIRE.name,
        "the drop named the raid on the raider who only heard about it")

    KARTTEST.AdvanceTime(5) -- the 5-second gap from the measurement
    F.Drop(sim, 100, F.GLOVES, { noRollFor = { Alric = true } })
    InFloodgate() -- he ports out of the raid and into a key, mid-distribution
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)

    T.eq(#RaidSim.Sent(sim, "LC_DROP"), 2,
        "the owner really did announce the same roll a second time")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0,
        "and nothing repaired anything -- what reached him is the ordinary announcement")

    local snap = raider.KART.LC.rollRaidSnapshot[100] or {}
    T.eq(snap.name, VOIDSPIRE.name,
        "being told about the item again from ANOTHER INSTANCE does not replace the raid it dropped " ..
        "in with the one he walked into (B153)")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(100, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    local stored = raider.env.KART_LootHistory[1] or {}
    T.eq(stored.instance, VOIDSPIRE.name,
        "so his award names the raid the item dropped in, not the dungeon -- which is the value that " ..
        "becomes permanent (LH.HandleHistoryEntry dedups on the award id) and checksum-invisible")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "id on the award too")
end

-- 2. The same, with his own row already gone -- the 30s and 90s rows of the measurement. Past the
--    vote deadline Vote.PruneExpiredRolls has taken the roll off his screen, so nothing on this
--    client still says he was ever told about it; the snapshot has to survive to the AWARD anyway.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 101, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[101] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(45) -- past the vote deadline
    T.is_nil(raider.KART.LC.rollAnnounced[101],
        "his roll is gone, so nothing on this client still says it was ever announced to him")

    F.Drop(sim, 101, F.GLOVES, { noRollFor = { Alric = true } })
    InFloodgate()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0, "and no repair was involved")
    T.eq((raider.KART.LC.rollRaidSnapshot[101] or {}).name, VOIDSPIRE.name,
        "the raid survives the repeat from inside the key as well, long after his row went")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(101, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    T.eq((raider.env.KART_LootHistory[1] or {}).instance, VOIDSPIRE.name,
        "and so does the award, on the client whose row is the only copy of it")
end

-- 3. The catch-up, to a raider who ported into ANOTHER RAID and relogged there -- which is the guild's
--    own habit twice over ("Bei uns reloggen Leute oft"). The reload loses the announcement flag, so
--    the owner answers his state request with the still-open roll, and the re-announcement lands while
--    he is standing in raid two. A raid rather than a key here on purpose: the code reads difficultyID
--    only, so raid-to-raid and raid-to-key are the same branch, and the operating reality names both.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 102, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((raider.KART.LC.rollRaidSnapshot[102] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(60) -- past the vote deadline: nothing of this roll is on his screen
    local droppedAt = (raider.KART.LC.rollRaidSnapshot[102] or {}).at
    InQuelDanas() -- he ports into the other raid, then relogs there
    raider = RaidSim.Reload(sim, "Alric")
    T.is_nil(raider.KART.LC.rollAnnounced[102],
        "the reload lost the announcement, which is what lets the catch-up through at all")

    RaidSim.EnterWorld(sim, "Alric")
    RaidSim.Drain(sim, 10)
    T.truthy(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP") > 0, "the owner re-announced the open roll to him")
    T.truthy(raider.KART.LC.rollAnnounced[102], "and this time he took it")

    local snap = raider.KART.LC.rollRaidSnapshot[102] or {}
    T.eq(snap.name, VOIDSPIRE.name,
        "the raid it dropped in survived being told about it again from inside the OTHER raid")
    T.eq(snap.id, VOIDSPIRE.mapID, "id included")
    T.eq(snap.at, droppedAt,
        "and the kept row still keeps the DROP's timestamp on this branch too, so it dies four hours " ..
        "after the item was looted rather than four hours after the last re-announce")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(102, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    T.eq((raider.env.KART_LootHistory[1] or {}).instance, VOIDSPIRE.name,
        "so the award names the raid the item dropped in, not the one he is standing in")
end

-- 4. And the door with no message behind it, from inside another instance: Blizzard hands this
--    client's own roll window back after a reload, which runs LC.OnStartLootRoll again -- by then with
--    the raider in a key. Merrit again, for the same reason as the block above: he clicks Blizzard's
--    roll himself, so he still has a roll window for the game to hand back.
do
    InVoidspire()
    local sim, _, council = F.NewRaid()
    F.Drop(sim, 103, F.GLOVES)
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((council.KART.LC.rollRaidSnapshot[103] or {}).name, VOIDSPIRE.name, "the drop named the raid")

    KARTTEST.AdvanceTime(60)
    InFloodgate()
    council = RaidSim.Reload(sim, "Merrit")
    RaidSim.EnterWorld(sim, "Merrit")
    RaidSim.Drain(sim, 10)
    T.truthy(council.KART.LC.sessionActive, "the reloaded client is back in the session")

    KARTTEST.AdvanceTime(30)
    -- BOTH calls belong, and which one carries which half was measured rather than assumed.
    -- KARTTEST.FireEvent reaches LootCouncilRelevance.lua's own START_LOOT_ROLL frame, which
    -- snapshots Blizzard's per-roll verdict before anything resolves the roll -- the same reason
    -- F.Drop fires the event before calling the handler. It does NOT reach LC.OnStartLootRoll:
    -- the frame that routes this event to it lives in Core.lua, which the offline harness cannot
    -- load at all (tests/run.lua says so, and tests/test_core_wiring.lua checks that wiring against
    -- the source instead). Measured by deleting each in turn: event only -> this block FAILS, the
    -- trade clock is never re-stamped; direct call only -> it passes, minus the relevance frame.
    -- So the direct call stands in for Core.lua's dispatcher and the event stands in for the game.
    RaidSim.As(council, function()
        KARTTEST.FireEvent("START_LOOT_ROLL", 103)
        council.KART.LC.OnStartLootRoll(103)
    end)
    T.eq(council.KART.LC.rollLootedAt[103], time(),
        "the handler ran all the way through -- it re-stamped the trade clock unconditionally")
    T.eq((council.KART.LC.rollRaidSnapshot[103] or {}).name, VOIDSPIRE.name,
        "...and left the raid standing, from inside the key as well as from the open world")
end

-- 5. WHAT THE KEEP COSTS ON THIS BRANCH, pinned rather than described: any WRONG NON-BLANK first
--    write is now permanent. Before 2026-08-10 an in-instance read overwrote, so a row written from
--    the wrong place repaired itself the moment this client stood in the right one. That repair
--    route is gone -- only a BLANK row is still repairable (the block above, rollID 99).
--
--    The route is not exotic: the item drops in raid TWO, the announcement reaches a client who is
--    still standing in raid ONE (zoning between two raids, or a catch-up minutes later while he is
--    somewhere else), so his FIRST write already names the wrong raid and is not blank. He then
--    zones into the raid it actually dropped in and is re-announced to -- and nothing repairs it.
--
--    Narrower than what the fix bought, and that is the whole of why it is a cost and not a defect:
--    B153 needs the client elsewhere at a REPEAT, which lands throughout the minutes of a
--    distribution -- exactly when people move. This needs him elsewhere at the FIRST announcement, a
--    second or two after the boss kill. Same two properties that made B153 worth fixing, though:
--    permanent (LH.HandleHistoryEntry dedups on the award id) and checksum-invisible
--    (LH.HistoryChecksum sums ids only). Asserted as the CURRENT behaviour, not as the wanted one.
do
    InQuelDanas()
    local sim, lm, _, raider = F.NewRaid()
    -- The item drops in raid TWO. Alric is dead when the boss dies, so no roll is raised on him and
    -- the announcement is the only thing that ever reaches him -- and it reaches him while he is
    -- still standing in raid ONE.
    F.Drop(sim, 120, F.GLOVES, { noRollFor = { Alric = true } })
    InVoidspire()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq((lm.KART.LC.rollRaidSnapshot[120] or {}).name, QUELDANAS.name,
        "the item really did drop in raid TWO -- the owner, who was standing in it, says so")
    local first = raider.KART.LC.rollRaidSnapshot[120] or {}
    T.eq(first.name, VOIDSPIRE.name,
        "and his FIRST write already names the wrong raid, and is not blank -- which is true on " ..
        "both sides of B153's fix, because a first write has nothing to keep")
    T.eq(first.id, VOIDSPIRE.mapID, "id too, wrong and non-blank together")

    -- He zones into the raid the item actually dropped in, and the owner re-announces the still-open
    -- roll. Until 2026-08-10 this read repaired him.
    KARTTEST.AdvanceTime(5)
    F.Drop(sim, 120, F.GLOVES, { noRollFor = { Alric = true } })
    InQuelDanas()
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 10)
    T.eq(#RaidSim.Sent(sim, "LC_DROP"), 2,
        "the owner really did announce the same roll a second time")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0,
        "and nothing else repaired anything -- what reached him is the ordinary announcement")

    local snap = raider.KART.LC.rollRaidSnapshot[120] or {}
    T.eq(snap.name, VOIDSPIRE.name,
        "standing in the RIGHT raid and being told about the item again no longer repairs a wrong " ..
        "non-blank row -- the keep cannot tell a wrong first answer from a right one, so this is " ..
        "the cost of B153's fix and it is permanent")
    T.eq(snap.id, VOIDSPIRE.mapID, "id stays wrong with it")

    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(120, raider.guid, "BIS", nil) end)
    RaidSim.Drain(sim, 10)
    local stored = raider.env.KART_LootHistory[1] or {}
    T.eq(stored.instance, VOIDSPIRE.name,
        "so his award names a raid the item never dropped in, on the client whose row is the only " ..
        "copy of it -- and no later read can take it back")
    T.eq(stored.instanceID, VOIDSPIRE.mapID, "id on the award too")
end

-- The two manual doors are new drops as well, and say so: nothing already stored under a number can
-- belong to an item somebody has only just typed in. A manual rollID is handed out by this client
-- rather than by Blizzard (LC.nextManualRollID), so the collision needs that counter's own ~28-hour
-- cycle to come round instead of Blizzard's seconds -- which is what is wound forward here.
do
    InVoidspire()
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(GLOVES) end)
    RaidSim.Drain(sim, 10)
    local rollID = lm.KART.LC.voteListRolls[1]
    T.eq((raider.KART.LC.rollRaidSnapshot[rollID] or {}).name, VOIDSPIRE.name,
        "the manually added item named the raid on the peer")

    KARTTEST.AdvanceTime(60 * 60) -- still inside the trade window

    -- From inside ANOTHER RAID first, which is where the fresh-announcement path can actually be seen
    -- to hold: this is the branch B153 turned into a keep, so a fix that stopped honouring newDrop
    -- here would leave raid ONE's name on an item somebody has just typed into raid TWO -- and the
    -- open-world half below cannot see that, because there the previous raid is replaced by a blank
    -- either way.
    InQuelDanas()
    RaidSim.As(raider, function()
        raider.KART.LC.HandleManualStart(rollID .. ":20:" .. GLOVES, lm.guid)
    end)
    T.eq((raider.KART.LC.rollRaidSnapshot[rollID] or {}).name, QUELDANAS.name,
        "the same number added again in a different raid takes THAT raid -- a manual add is always a " ..
        "new drop, and a new drop never keeps")

    InOpenWorld()
    RaidSim.As(raider, function()
        raider.KART.LC.HandleManualStart(rollID .. ":20:" .. GLOVES, lm.guid)
    end)
    T.is_nil((raider.KART.LC.rollRaidSnapshot[rollID] or {}).name,
        "the same number added again for the same item does not inherit the raid the first one " ..
        "dropped in -- LC.HandleManualStart only ever receives an item somebody has just added")

    RaidSim.As(lm, function()
        lm.KART.LC.nextManualRollID = rollID -- the counter has come round to it again
        lm.KART.LC.StartManualRoll(GLOVES)
    end)
    RaidSim.Drain(sim, 10)
    T.is_nil((lm.KART.LC.rollRaidSnapshot[rollID] or {}).name,
        "...and neither does the client that typed it")
end

-- All four doors into the flow take the snapshot, not just LC.OnStartLootRoll -------------------------
--
-- Each of the three below is reached on a client the others are not, so a missing call in any one of
-- them is a whole class of client with no raid on its awards -- and every one of those awards is
-- permanent and checksum-invisible (see the vote-deadline block above). LC.HandleStart in particular
-- is the client Blizzard raised no roll on at all: dead, released, out of range -- the client C13 and
-- C14 were written about. The manual pair is the maintainer's own three-man Manifest route.
--
-- Every door also has to hand the ITEM over, not just call the function: without it the row cannot
-- tell a catch-up re-announce from a rollID Blizzard has reused, and the keep in
-- LC.SnapshotRollInstance either stops working or starts inheriting (B150). Asserted on the stored
-- row rather than through a scenario, because two of the four doors have no second read behind them
-- today and a scenario for those would be invented rather than observed.
local GLOVES_ID = tostring(F.GLOVES)

do
    -- LC.HandleStart: Alric never gets a START_LOOT_ROLL, so LC.OnStartLootRoll cannot have run on
    -- his client and the announcement is the only thing that reaches him.
    InVoidspire()
    local sim, _, _, raider = F.NewRaid()
    F.Drop(sim, 84, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(2) -- the owner's collection window, then the announcement
    RaidSim.Drain(sim, 10)

    T.eq(raider.KART.LC.rollItems[84] ~= nil, true,
        "the raider Blizzard gave no roll window to still learned about the item")
    local snap = raider.KART.LC.rollRaidSnapshot[84]
    T.truthy(snap, "...and LC.HandleStart snapshotted the raid for him too")
    T.eq(snap.name, VOIDSPIRE.name, "...the right one")
    T.eq(snap.id, VOIDSPIRE.mapID, "...id included")
    T.eq(snap.item, GLOVES_ID, "...and the item the row has to compare against later")
end

do
    -- LC.StartManualRoll (the lootmaster's own /kart add) and LC.HandleManualStart (every peer's side
    -- of it). No Blizzard roll exists anywhere for a manual item, so these two are the only sources.
    InVoidspire()
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(GLOVES) end)
    RaidSim.Drain(sim, 10)

    local rollID = lm.KART.LC.voteListRolls[1]
    T.truthy(rollID, "the manual item is on the lootmaster's list")

    local own = lm.KART.LC.rollRaidSnapshot[rollID]
    T.truthy(own, "LC.StartManualRoll snapshotted the raid on the client that typed the command")
    T.eq(own.name, VOIDSPIRE.name, "...the right one")
    T.eq(own.id, VOIDSPIRE.mapID, "...id included")
    T.eq(own.item, GLOVES_ID, "...and the item")

    for _, c in ipairs({ council, raider }) do
        local peer = c.KART.LC.rollRaidSnapshot[rollID]
        T.truthy(peer, "LC.HandleManualStart snapshotted it on " .. c.name .. " as well")
        T.eq(peer.name, VOIDSPIRE.name, c.name .. " has the right raid")
        T.eq(peer.id, VOIDSPIRE.mapID, c.name .. " has the id too")
        T.eq(peer.item, GLOVES_ID, c.name .. " has the item too")
    end
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
