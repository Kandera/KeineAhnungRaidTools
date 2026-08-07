-- A history entry too long for one addon message.
--
-- The catch-up sync used to send one LC_HIST_ENTRY per award, and SendAddonMessage takes 255 bytes.
-- Over that, four staggered fallbacks gave up the item link, then the item, then part of the reason
-- -- because each award was its own message and had to fit alone. Now the catch-up is answered in
-- packed LC_HIST_BATCH messages instead (see LH.HandleHistoryRequest / LC.PackPayload), and none of
-- that survives: an entry that would once have lost its reason to a byte cap now arrives whole. This
-- file is what is left of the old budget -- the reason a raid running "Zweitspec, aber nur wenn
-- niemand Mainspec braucht" style labels ever produced an entry too big for one message at all.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link

-- The lootmaster holds one award and a peer asks for the catch-up.
local function SyncOne(entry)
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = { entry } end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    return sim, lm, raider
end

-- An ordinary award arrives, so nothing below can pass by the sync simply never working ------------
do
    local sim, _, raider = SyncOne({
        time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
        reason = "BIS", class = "MAGE", rollID = 70,
    })
    T.eq(#raider.env.KART_LootHistory, 1, "an ordinary award reaches the peer")
    T.eq(raider.env.KART_LootHistory[1].winner, "Alric", "under the winner it was logged for")
    T.truthy(sim ~= nil)
end

-- A reason long enough to push the message over the cap ---------------------------------------------
do
    local longReason = string.rep("Zweitspec-wenn-frei ", 12)  -- 240 bytes
    local _, _, raider = SyncOne({
        time = time() - 60, item = GLOVES, winner = "Verylongname-Silvermoon",
        winnerKey = "Player-1096-0A1B2C3D", reason = longReason, class = "MAGE", rollID = 71,
    })
    T.eq(#raider.env.KART_LootHistory, 1,
        "an award whose reason will not fit still reaches the peer -- an entry is not lost to its own length")
end

-- The way a real raid gets there: umlauts and other multi-byte reasons round-trip whole -------------
-- The settings box limits a vote-button label to 128 LETTERS. A German label spends two bytes on
-- every umlaut, so "128 letters" is well over 200 bytes -- long enough that the record no longer
-- fits under PACK_MAX_MESSAGE and the batch goes out packed (LC.PackPayload). This used to be exactly
-- the case that got cut at a byte offset that could land inside a multi-byte character; now the whole
-- reason arrives, so an exact match is the only thing that could still be wrong -- a compression bug
-- mangling the bytes, say.
do
    local label = string.rep("üä", 60)
    local sim, _, raider = SyncOne({
        time = time() - 60, item = GLOVES, winner = "Verylongname-Silvermoon",
        winnerKey = "Player-1096-0A1B2C3D", reason = label, class = "MAGE", rollID = 73,
        id = "umlaut-1", epoch = 1,
    })
    T.eq(#raider.env.KART_LootHistory, 1, "the award reaches the peer")
    T.eq(raider.env.KART_LootHistory[1].reason, label, "the umlauts arrive whole, byte for byte")
    T.truthy(#RaidSim.Sent(sim, "LC_HIST_BATCH") > 0, "sent as a batch, not silently dropped")
end

do
    -- Three-byte characters -- the euro sign is three bytes, and item names carry it -- reachable
    -- without leaving Europe.
    local label = string.rep("€", 60)
    local _, _, raider = SyncOne({
        time = time() - 60, item = GLOVES, winner = "Verylongname-Silvermoon",
        winnerKey = "Player-1096-0A1B2C3D", reason = label, class = "MAGE", rollID = 74,
        id = "euro-1", epoch = 1,
    })
    T.eq(#raider.env.KART_LootHistory, 1, "the award reaches the peer")
    T.eq(raider.env.KART_LootHistory[1].reason, label, "the three-byte characters arrive whole")
end

-- ==========================================================================
--  What the catch-up accepts, and how much of it it sends
-- ==========================================================================

-- A timestamp from the future -----------------------------------------------------------------------
-- time() is each client's OS clock. A peer with a badly set one -- or a hostile one -- dating an entry
-- years ahead does not just add a wrong row: LH.RequestHistorySync asks for everything newer than the
-- newest entry it holds, so that date becomes the watermark and every future request asks for entries
-- newer than a date nobody will ever reach. Catch-up sync is then dead on this client for good, and
-- nothing says so.
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)

    -- Calling LH.HandleHistoryEntry directly, the per-record parser HandleHistoryBatch loops over --
    -- this guard is unrelated to batching and lives inside it, not at the batch level.
    local far = time() + 5 * 365 * 24 * 60 * 60
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%d:%s",
        far, "future-1", 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)
    T.eq(#lm.env.KART_LootHistory, 0, "an entry dated years ahead is refused")
end

do
    -- The boundary itself: a few minutes of clock drift between two raiders is ordinary and must not
    -- cost them an award, while years ahead is not drift.
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    local record = string.format("%d:16:71:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%d:%s",
        time() + 120, "drift-1", 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)
    T.eq(#lm.env.KART_LootHistory, 1, "two minutes of clock drift is accepted, not treated as an attack")
end

-- The client still asks its peers for what it is missing, from a reachable point in time ------------
-- The other half of the future-timestamp guard: refusing the bad entry must not also break the
-- client's OWN outgoing request -- the since-timestamp it sends is derived from its own held
-- entries, so a client that had accepted the bad one would ask from five years out forever after.
do
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
    local asks = RaidSim.Sent(sim, "LC_HIST_REQ")
    T.eq(#asks, 1, "the client asks its peers for what it is missing")
    local since = tonumber(((asks[1] or {}).msg or ""):match("^LC_HIST_REQ:%d+:%d+:(%d+)$"))
    T.truthy(since and since <= time(),
        "from a point in time that can actually be reached")
end

-- How much one answer may be --------------------------------------------------------------------
-- Packed into batches instead of one whisper per entry. A peer holding a long history answering in
-- full would still put a bounded number of messages on the wire, not one per entry it holds.
do
    local sim, lm, _, raider = F.NewRaid()
    local many = {}
    for i = 1, 80 do
        many[i] = { time = time() - 1000 + i, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
                    reason = "BIS", class = "MAGE", rollID = 200 + i, id = "many-" .. i, epoch = 1 }
    end
    RaidSim.As(lm, function() lm.env.KART_LootHistory = many end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    -- RaidSim.Messages, not RaidSim.Sent: a packed batch this size is over 255 bytes and the
    -- transport splits it into several chunks, so a plain prefix match on the log finds nothing.
    local sent = #RaidSim.Messages(sim, "LC_HIST_BATCH")
    T.truthy(sent > 0, "the peer answers a catch-up request")
    T.truthy(sent <= 2,
        "eighty entries at fifty per batch cost two messages, not one per entry it happens to hold ("
        .. sent .. ")")
    T.eq(#raider.env.KART_LootHistory, 80, "and all eighty still arrive")
end

-- Batching. The catch-up used to be one addon message per award -- up to thirty, stretched over eight
-- seconds, each one squeezed under 255 bytes by four staggered truncations that could cost the item
-- link, then the item, then part of the reason. Packed into batches none of that is needed, and the
-- entries arrive whole.

-- A 60-entry catch-up arrives complete, and cheaply -----------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    local entries = {}
    for i = 1, 60 do
        entries[i] = { time = time() - 3600 + i, item = GLOVES, winner = "Alric",
                       winnerKey = "Player-1-A", reason = "BIS", class = "MAGE", rollID = i,
                       id = "sync-" .. i, epoch = 1 }
    end
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 60, "all sixty awards arrive")
    T.truthy(#RaidSim.Messages(sim, "LC_HIST_BATCH") <= 3,
        "sixty awards cost at most three messages, not sixty")
end

-- A long reason is no longer truncated --------------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    local longReason = string.rep("Zweitspec-wenn-frei ", 12)  -- 240 bytes
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Verylongname-Silvermoon",
              winnerKey = "Player-1096-0A1B2C3D", reason = longReason, class = "MAGE",
              rollID = 71, id = "sync-long", epoch = 1 },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(raider.env.KART_LootHistory[1].reason, longReason,
        "the reason arrives whole -- a batch does not pay per award for its length")
    T.eq(raider.env.KART_LootHistory[1].item, GLOVES, "and so does the item link")
end

-- No batch is put on the wire that the decompressor will refuse ---------------------------------
-- A batch this size (150 entries, three batches of fifty) is split across several 255-byte chunks
-- by the transport, so a single log entry's .msg is not the full packed body to measure directly
-- (see RaidSim.Messages). What IS directly observable end to end is whether the receiver's own
-- decompressor ever refused one: PACK_MAX_BLOCK is enforced there, and a batch over it is counted
-- as packedUnreadable and its records are never stored -- so a clean packedUnreadable count together
-- with all 150 entries arriving is exactly the proof that no batch body exceeded it.
do
    local sim, lm, _, raider = F.NewRaid()
    local entries = {}
    for i = 1, 150 do
        entries[i] = { time = time() - 7200 + i, item = GLOVES, winner = "Verylongname-Silvermoon",
                       winnerKey = "Player-1096-0A1B2C3D", reason = string.rep("x", 120),
                       class = "MAGE", rollID = i, id = "big-" .. i, epoch = 1 }
    end
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {}
        raider.KART.LC.diag = raider.KART.LC.diag or {}
        raider.KART.LC.diag.packedUnreadable = 0
    end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 60)

    T.eq(raider.KART.LC.diag.packedUnreadable, 0, "no batch body exceeded PACK_MAX_BLOCK")
    T.eq(#raider.env.KART_LootHistory, 150, "and all 150 still arrive")
end

-- The checksum finds a hole BEHIND the watermark ---------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 300, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 1, id = "old-one", epoch = 1 },
            { time = time() - 60,  item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "new-one", epoch = 1 },
        }
    end)
    -- The raider holds only the NEWER of the two. The old watermark ("everything newer than my
    -- newest") can never ask for the older one -- that is the hole the checksum exists to find.
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "new-one", epoch = 1 },
        }
    end)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 2, "the entry older than the watermark is filled in")
end

-- Matching states say nothing at all ----------------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    local shared = {
        { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
          reason = "BIS", class = "MAGE", rollID = 1, id = "same-one", epoch = 1 },
    }
    RaidSim.As(lm, function() lm.env.KART_LootHistory = { shared[1] } end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = { shared[1] } end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#RaidSim.Messages(sim, "LC_HIST_BATCH"), 0,
        "two clients that already agree put nothing on the wire")
end

-- An entry below our epoch is discarded -------------------------------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    -- One record in the batch field order: item last, id and epoch just before it.
    local record = string.format("%d:0:0:MAGE::Player-1-A:Alric:BIS:%s:%d:%s",
        time() - 60, "1-bbb", 2, GLOVES)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 4
        raider.env.KART_LootHistory = {}
        raider.KART.LH.HandleHistoryBatch(
            string.format("2:%s:0:%s", lm.guid, record), lm.guid)
    end)
    T.eq(#raider.env.KART_LootHistory, 0, "a pre-wipe entry cannot be re-seeded into a wiped log")
end

-- An unreadable block is counted, not swallowed ------------------------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 1
        raider.env.KART_LootHistory = {}
        raider.KART.LC.diag = raider.KART.LC.diag or {}
        raider.KART.LC.diag.packedUnreadable = 0
        -- Flagged as packed, but the body is not a deflate block at all -- what a foreign LibDeflate
        -- or a truncated transfer produces.
        raider.KART.LH.HandleHistoryBatch(
            string.format("1:%s:1:%s", lm.guid, "not-a-deflate-block"), lm.guid)
    end)
    T.eq(#raider.env.KART_LootHistory, 0, "nothing is stored from a block that will not decompress")
    T.eq(raider.KART.LC.diag.packedUnreadable, 1,
        "and it is counted -- the alternative is a client that quietly loses a whole catch-up")
end

-- The full reconcile runs once a night, not once a relog ----------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    -- The peer is missing an entry BEHIND its watermark, so every request diverges on checksum and
    -- would otherwise pull the whole epoch again on each one.
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 300, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 1, id = "old-two", epoch = 1 },
            { time = time() - 60,  item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "new-two", epoch = 1 },
        }
    end)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "new-two", epoch = 1 },
        }
    end)

    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)
    T.eq(#raider.env.KART_LootHistory, 2, "the first reconcile fills the hole")

    -- A relog twenty minutes later. People port out mid-distribution and come back all evening; the
    -- full pull must not fire again for each of those.
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    KARTTEST.AdvanceTime(20 * 60)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#RaidSim.Messages(sim, "LC_HIST_BATCH"), 0,
        "the second divergence in the same night is not answered with another full pull")
end
