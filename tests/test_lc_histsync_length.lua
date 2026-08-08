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

-- What a night's history actually looks like once it is packed.
--
-- Every batch fixture in this file used to be ONE item link, ONE winner and one constant reason
-- repeated n times. Deflate collapses that to a few hundred bytes however many entries are in it, so
-- the PACK_MAX_BLOCK assertion below could not fail whatever the batch size -- which is how a
-- 50-entry batch that a real raid packs to nearly 4 KB shipped green. A raid night has a different
-- item almost every drop, a different winner most of the time, reasons drawn from the raid's vote
-- buttons, and an award id per entry that is mostly incompressible by construction. That is the
-- entropy the compressor is really handed, so it is what these fixtures hand it.
-- Four bonus-list variants of each fixture item, which is what a tier's log really holds: the same
-- base items at different upgrade tracks, crests and tertiaries, so no two links are byte-identical
-- and the bonus lists themselves are the part deflate cannot fold away. Twelve items repeated
-- verbatim across 150 awards is a fixture, not a raid.
local ITEM_POOL = {}
for _, id in ipairs({ F.GLOVES, F.WEAPON, F.TOKEN, F.PLATE_CHEST, F.STAFF, F.SHIELD, F.STR_MACE,
                      F.INT_DAGGER, F.LONG_ITEM, F.TIER_TOKEN, F.RECIPE, F.BOE }) do
    local def = KARTTEST.items[id]
    for variant = 1, 4 do
        local bonus = {}
        for b = 1, 7 + variant do
            bonus[b] = tostring(10200 + (id + variant * 37 + b * 13) % 1800)
        end
        ITEM_POOL[#ITEM_POOL + 1] = "|cffa335ee|Hitem:" .. id .. "::::::::80:268::14:" .. #bonus
            .. ":" .. table.concat(bonus, ",") .. ":" .. (28 + variant) .. ":9:::::|h["
            .. def.name .. "]|h|r"
    end
end

-- A raid's worth of winners, not the fixture's five: a history entry's winner is a stored string, so
-- it needs no roster behind it, and a mythic roster is what a tier's log is spread over.
local WINNER_POOL = {}
for i = 1, 25 do
    WINNER_POOL[i] = { ("Raider%02d"):format(i), ("Player-1096-0A1B2%03X"):format(i), "MAGE" }
end

-- The labels this guild actually configures, long German ones included -- that is where
-- test_lc_histsync_length's own long-reason cases come from.
local REASON_POOL = { "BIS", "Mainspec", "Zweitspec, aber nur wenn niemand Mainspec braucht",
                      "Offspec", "Transmog", "Kleines Upgrade" }
-- false, not nil: a hole would break the modulo pick below, and "no reason colour" is a real case.
local COLOR_POOL = { false, { r = 0.2, g = 0.8, b = 0.2 }, { r = 0.9, g = 0.7, b = 0.1 },
                     { r = 0.4, g = 0.4, b = 0.9 } }
local DIFFICULTY_POOL = { 14, 15, 16 }

-- n entries with that spread. `tag` keeps two fixtures' ids apart within one run.
local function VariedEntries(n, tag)
    local out = {}
    for i = 1, n do
        local w = WINNER_POOL[(i - 1) % #WINNER_POOL + 1]
        local at = time() - 7200 + i * 7
        out[i] = {
            time = at,
            item = ITEM_POOL[(i - 1) % #ITEM_POOL + 1],
            winner = w[1], winnerKey = w[2], class = w[3],
            reason = REASON_POOL[(i - 1) % #REASON_POOL + 1],
            color = COLOR_POOL[(i - 1) % #COLOR_POOL + 1] or nil,
            difficultyID = DIFFICULTY_POOL[(i - 1) % #DIFFICULTY_POOL + 1],
            rollID = 100 + i,
            -- The shape LH.NewAwardID really mints: a timestamp plus six hex digits. That is most of
            -- a record's incompressible content, and a constant prefix with a counter after it is
            -- not -- the old "sync-1", "sync-2" ids deflate away to nothing.
            id = string.format("%s-%d-%03x%03x", tag, at, (i * 2654) % 0x1000, (i * 977) % 0x1000),
            epoch = 1,
        }
    end
    return out
end

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
    local record = string.format("%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        far, "future-1", "", 0, 1, GLOVES)
    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(record, raider.guid) end)
    T.eq(#lm.env.KART_LootHistory, 0, "an entry dated years ahead is refused")
end

do
    -- The boundary itself: a few minutes of clock drift between two raiders is ordinary and must not
    -- cost them an award, while years ahead is not drift.
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    local record = string.format("%d:16:71:MAGE:1,1,1:Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time() + 120, "drift-1", "", 0, 1, GLOVES)
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

-- ...and never from our own wipe clock -----------------------------------------------------------
-- The second half of the cross-client-clock fix, and the half nothing held: restoring the old
-- `local latest = KART_LootHistoryClearedAt or 0` floor in LH.RequestHistorySync left the suite
-- green (mutation testing, 2026-08-07), while only the matching read in LH.HandleHistoryEntry was
-- watched.
--
-- KART_LootHistoryClearedAt is OUR OS clock, stamped when WE wiped. Using it as the floor of an
-- outgoing request asks every peer for entries newer than a moment on a clock they do not share --
-- so an award made after that wipe by a client running a few minutes slow is dated below the floor,
-- is never asked for, and the full reconcile that would otherwise have carried it re-drops it every
-- time. The since-timestamp is "the newest thing I hold" and nothing else.
do
    local sim, lm = F.NewRaid()
    local function AskAndReadSince()
        RaidSim.ClearLog(sim)
        RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
        local sent = RaidSim.Sent(sim, "LC_HIST_REQ")
        T.eq(#sent, 1, "the client asks")
        return tonumber(((sent[1] or {}).msg or ""):match("^LC_HIST_REQ:%d+:%d+:(%d+)$"))
    end

    -- Freshly wiped: nothing held at all, and a wipe stamp on our own clock.
    local wipedAt = time()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {}
        lm.env.KART_LootHistoryClearedAt = wipedAt
    end)
    T.eq(AskAndReadSince(), 0,
        "a client holding nothing asks for everything, not only for what postdates its own wipe")

    -- Now it holds one entry, backfilled from a peer whose clock runs five minutes slow, so the
    -- award is dated BELOW our own wipe stamp although it was made after it.
    KARTTEST.AdvanceTime(60)
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = wipedAt - 300, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 3, id = "slow-clock-1", epoch = 1 },
        }
    end)
    T.eq(AskAndReadSince(), wipedAt - 300,
        "and asks from the newest entry it actually holds, not from the moment it wiped")
end

-- How much one answer may be --------------------------------------------------------------------
-- Packed into batches instead of one whisper per entry. A peer holding a long history answering in
-- full would still put a bounded number of messages on the wire, not one per entry it holds.
do
    local sim, lm, _, raider = F.NewRaid()
    local many = VariedEntries(80, "many")
    RaidSim.As(lm, function() lm.env.KART_LootHistory = many end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    -- RaidSim.Messages, not RaidSim.Sent: a packed batch this size is over 255 bytes and the
    -- transport splits it into several chunks, so a plain prefix match on the log finds nothing.
    local sent = #RaidSim.Messages(sim, "LC_HIST_BATCH")
    T.truthy(sent > 0, "the peer answers a catch-up request")
    -- What this fixture actually costs, not a round number with room above it. How many entries fit
    -- under PACK_MAX_BLOCK is decided by what they weigh once packed, so the count does move with the
    -- content -- but leaving headroom nobody measured is how a bound stops noticing anything: three
    -- is what eighty entries at this entropy pack into today, so three is what is asserted, and a
    -- change that makes the answer cost more has to be looked at rather than absorbed.
    T.truthy(sent <= 3,
        "eighty entries cost three messages, not one per entry it happens to hold ("
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
    local entries = VariedEntries(60, "sync")
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 60, "all sixty awards arrive")
    -- Three, which is the measured value. It was loosened to five during the fix wave for no reason
    -- the measurement supports, and a bound that sits two above what it is watching is a bound that
    -- has stopped watching. Names the count it saw, so a failure says what changed rather than only
    -- that something did.
    local sent60 = #RaidSim.Messages(sim, "LC_HIST_BATCH")
    T.truthy(sent60 <= 3,
        "sixty awards cost three messages, not sixty (" .. sent60 .. ")")
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
-- The full 150-entry dump, at the entropy a raid night has (see VariedEntries). PACK_MAX_BLOCK is
-- LootCouncil.lua's decompression-bomb ceiling and is enforced on the RECEIVING side: a block over
-- it comes back nil, the whole batch is counted as packedUnreadable and NONE of its records is
-- stored. So the sender cutting its batches by entry count alone is not a bandwidth question, it is
-- entries silently never arriving -- and it does not heal, because the same oversized batch is
-- rebuilt on the next join.
--
-- Measured two ways, because either alone can pass for the wrong reason. Wrapping the receiver's own
-- LC.UnpackPayload weighs every block that actually reached it against the real ceiling, and names
-- the byte count when one is over; the end-to-end count then says none was lost on some other path.
do
    local sim, lm, _, raider = F.NewRaid()
    local entries = VariedEntries(150, "big")
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)

    local blocks = {}
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {}
        raider.KART.LC.diag = raider.KART.LC.diag or {}
        raider.KART.LC.diag.packedUnreadable = 0
        local realUnpack = raider.KART.LC.UnpackPayload
        raider.KART.LC.UnpackPayload = function(blob)
            local out = realUnpack(blob)
            blocks[#blocks + 1] = { bytes = #blob, ok = out ~= nil }
            return out
        end
    end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 60)

    local refused, biggest = 0, 0
    for _, b in ipairs(blocks) do
        if not b.ok then refused = refused + 1 end
        if b.bytes > biggest then biggest = b.bytes end
    end
    T.truthy(#blocks > 0,
        "the answer went out packed at all -- an unpacked one would say nothing about the ceiling")
    T.eq(refused, 0, "every batch body was inside PACK_MAX_BLOCK (biggest seen: " .. biggest .. " B)")
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
    local record = string.format("%d:0:0:MAGE::Player-1-A:Alric:BIS:%s:%s:%d:%d:%s",
        time() - 60, "1-bbb", "", 0, 2, GLOVES)
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

-- The full reconcile runs once per cooldown, not once per relog ---------------------------------------
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
        "the second divergence inside the cooldown is not answered with another full pull")
end

-- and is granted again once the cooldown has passed ---------------------------------------------------
-- The other half of the throttle, and the reason it is an hour rather than an evening (maintainer's
-- ruling, 2026-08-07). Nothing acknowledges a batch -- LH.fullReconciled is stamped on SEND -- so a
-- full answer that never arrived spends the asker's allowance anyway. At six hours that client had no
-- history for the rest of the raid; at one hour the very next divergence past the window pulls it.
do
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 300, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 1, id = "cool-one", epoch = 1 },
            { time = time() - 60,  item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "cool-two", epoch = 1 },
        }
    end)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "cool-two", epoch = 1 },
        }
    end)

    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)
    T.eq(#raider.env.KART_LootHistory, 2, "the first reconcile fills the hole")

    -- Everything the first full answer delivered is gone again -- the client it reached was lost, or
    -- the answer never landed. The hole is BEHIND the watermark either way, so only a full pull can
    -- see it: raider's remaining entry is the NEWEST one, so its since-timestamp asks for nothing.
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 2, id = "cool-two", epoch = 1 },
        }
    end)
    -- Past HISTORY_FULL_COOLDOWN. At the old six hours this same wait was still inside the window and
    -- the client stayed one entry short until the next raid night.
    KARTTEST.AdvanceTime(61 * 60)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.truthy(#RaidSim.Messages(sim, "LC_HIST_BATCH") > 0,
        "a divergence past the cooldown is answered with a full pull again")
    T.eq(#raider.env.KART_LootHistory, 2,
        "so the entry behind the watermark is recovered the same evening, not the next one")
end

-- A granted full reconcile that sends nothing does not burn its allowance --------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    -- The peer's own history is empty at the moment it grants a full reconcile -- e.g. it just
    -- adopted a bumped epoch and has not caught up itself yet. Nothing survives the filter, so
    -- nothing is sent, even though a full answer was granted.
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 1, id = "asker-one", epoch = 1 },
        }
    end)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)
    T.eq(#RaidSim.Messages(sim, "LC_HIST_BATCH"), 0, "the empty peer sends nothing back")

    -- The peer backfills a real entry, dated well before that no-op grant, later in the same window.
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 3600, item = GLOVES, winner = "Sinja", winnerKey = "Player-1-S",
              reason = "OS", class = "PRIEST", rollID = 2, id = "peer-two", epoch = 1 },
        }
    end)
    KARTTEST.AdvanceTime(20 * 60)
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim, 30)

    T.eq(#raider.env.KART_LootHistory, 2,
        "and the backfilled entry still reaches the asker in the same window -- the empty answer did not spend the allowance")
end
