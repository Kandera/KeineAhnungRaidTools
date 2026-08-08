-- LH.HandleHistoryEntry stores a bare "item:12345:..." string when C_Item.GetItemInfo cannot yet
-- resolve it (the item is not in this client's cache). The comment above the rebuild attempt has
-- always promised an upgrade "in place once it loads" -- but until now nothing ever registered one,
-- so an item that missed the synchronous attempt stayed a bare string forever, and the Companion
-- exporter reads that as an empty itemString and a raw "item:12345:..." itemName (docs/MANIFEST.md
-- C14, "nothing is lost quietly").
--
-- These three cases are the ones that make the continuation genuinely safe to fire late, well after
-- the entry that asked for it may no longer exist in the shape it was stored in:
--   1. the ordinary case -- the item loads, the entry is upgraded.
--   2. the entry is gone by the time the item loads (revoke, wipe, eviction) -- nothing throws.
--   3. a full link arrives for the same award in the meantime -- the late upgrade must not clobber it.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES_ID = F.GLOVES
local BARE_GLOVES = "item:" .. GLOVES_ID

local function Whisper(lm, raider, fields)
    local epoch = fields.epoch or 1
    local record = ("%d:16:%d:MAGE:1,1,1:%s:%s:%s:%s:%d:%s"):format(
        fields.time, fields.rollID, fields.winnerKey, fields.winner,
        fields.reason or "BIS", fields.id or "", epoch, fields.item or "")
    RaidSim.As(raider, function()
        raider.KASC:Send(("LC_HIST_BATCH:%d:%s:0:%s"):format(epoch, raider.guid, record),
            "WHISPER", lm.name)
    end)
    KARTTEST.AdvanceTime(1)
end

local function Hold(lm, entries)
    RaidSim.As(lm, function() lm.env.KART_LootHistory = entries end)
    return entries
end

-- 1. The item loads later, and the entry is upgraded in place ------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, {})
    KARTTEST.items[GLOVES_ID].cached = false

    Whisper(lm, raider, { time = now, rollID = 80, winnerKey = "Player-1-A", winner = "Alric",
                          item = BARE_GLOVES, id = "award-upgrade" })

    T.eq(lm.env.KART_LootHistory[1].item, BARE_GLOVES,
        "stored as the bare string while the item is still uncached")

    KARTTEST.CacheItem(GLOVES_ID)

    T.truthy(lm.KAUtil.IsRealItemLink(lm.env.KART_LootHistory[1].item),
        "and upgraded to a real link once the item loads")
    KARTTEST.items[GLOVES_ID].cached = nil
end

-- 2. The entry is gone by the time the item loads -- nothing throws ------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, {})
    KARTTEST.items[GLOVES_ID].cached = false

    Whisper(lm, raider, { time = now, rollID = 81, winnerKey = "Player-1-A", winner = "Alric",
                          item = BARE_GLOVES, id = "award-revoked" })
    T.eq(#lm.env.KART_LootHistory, 1, "the entry is stored while waiting on the item")

    -- A raid-wide wipe (or a revoke, or TrimHistory eviction) removes it before the item ever loads.
    Hold(lm, {})

    local ok = pcall(function() KARTTEST.CacheItem(GLOVES_ID) end)
    T.truthy(ok, "the late load does not throw once its entry is gone")
    T.eq(#lm.env.KART_LootHistory, 0, "and nothing is resurrected by the late callback")
    KARTTEST.items[GLOVES_ID].cached = nil
end

-- 3. A full link arrives for the same award in the meantime -- the late upgrade must not clobber it
do
    -- F.LONG_ITEM, not GLOVES: it carries baseIlvl, so the stub answers a DIFFERENT (base) variant
    -- for a bare id-only string than for the real link -- the same distinction B119 was about. That
    -- is what makes clobbering observable here: GLOVES' bare and full forms resolve to the identical
    -- string, so overwriting it with itself would pass whether or not the guard exists at all.
    local LONG_ID = F.LONG_ITEM
    local LONG_FULL = KARTTEST.items[LONG_ID].link
    local BARE_LONG = "item:" .. LONG_ID

    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, {})
    KARTTEST.items[LONG_ID].cached = false

    Whisper(lm, raider, { time = now, rollID = 82, winnerKey = "Player-1-A", winner = "Alric",
                          item = BARE_LONG, id = "award-raced" })
    T.eq(lm.env.KART_LootHistory[1].item, BARE_LONG, "stored bare, waiting on the item")

    -- Another peer's answer (or this client's own later sync) already resolved the same award to the
    -- real full link, in place, before the original client's item ever finished loading.
    RaidSim.As(lm, function() lm.env.KART_LootHistory[1].item = LONG_FULL end)

    KARTTEST.CacheItem(LONG_ID)

    T.eq(lm.env.KART_LootHistory[1].item, LONG_FULL,
        "the link another sync already delivered is left standing, not overwritten by the late load")
    KARTTEST.items[LONG_ID].cached = nil
end

-- 4. No id on the wire (an older sender) -- nothing safe to locate the entry by later, so no
-- continuation is registered at all; the entry stays bare rather than risk matching the wrong row.
do
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, {})
    KARTTEST.items[GLOVES_ID].cached = false

    Whisper(lm, raider, { time = now, rollID = 83, winnerKey = "Player-1-A", winner = "Alric",
                          item = BARE_GLOVES, id = "" })
    T.eq(lm.env.KART_LootHistory[1].item, BARE_GLOVES, "stored bare, with no id to track it by")

    KARTTEST.CacheItem(GLOVES_ID)

    T.eq(lm.env.KART_LootHistory[1].item, BARE_GLOVES,
        "and stays bare -- the item loading later does not touch an entry it cannot safely find again")
    KARTTEST.items[GLOVES_ID].cached = nil
end
