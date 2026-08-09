-- What makes two loot-history entries the same award, and what makes them two.
--
-- Every client logs its own history, and the catch-up sync fills the gaps from peers. Both halves of
-- that meet in LH.HandleHistoryEntry, which has to answer one question about every arriving award:
-- do I already have this? Answering yes too readily loses an award nobody will notice is gone --
-- the council reads this list to see who is already owed something. Answering no too readily leaves
-- the same award on the list twice.
--
-- The decisions here are each one operator wide, and each of them was unheld.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link
local WEAPON = KARTTEST.items[F.WEAPON].link

-- One award, told to `lm` by a raider, exactly as the catch-up sync words it (a single-record,
-- unpacked LC_HIST_BATCH -- see LH.HandleHistoryBatch / LH.HandleHistoryEntry).
local function Whisper(lm, raider, fields)
    local epoch = fields.epoch or 1
    local record = ("%d:16:%d:MAGE:1,1,1:%s:%s:%s:%s:%s:%d:%d:%s"):format(
        fields.time, fields.rollID, fields.winnerKey, fields.winner,
        fields.reason or "BIS", fields.id or "", fields.instance or "", fields.instanceID or 0,
        epoch, fields.item or "")
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

-- Whose award it is ------------------------------------------------------------------------------
do
    -- A reassignment carries the same roll and the same item with a NEW winner -- the council
    -- changed its mind, which happens on any evening where somebody points out a better case after
    -- the fact. Read as a duplicate of the award it replaces, the correction never lands, and this
    -- client keeps naming the wrong raider for the rest of the night.
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now, rollID = 70, class = "MAGE" } })

    Whisper(lm, raider, { time = now + 1, rollID = 70, winnerKey = "Player-1-S",
                          winner = "Sinja", item = GLOVES })

    T.eq(#lm.env.KART_LootHistory, 1, "the roll still holds one award")
    T.eq(lm.env.KART_LootHistory[1].winner, "Sinja",
        "and it names the raider it was reassigned to, not the one it was taken from")
end

-- Which item it is -------------------------------------------------------------------------------
do
    -- Two different items to the same raider inside the clock-skew window. That is an ordinary
    -- couple of seconds on a boss that drops two pieces for the same person -- and the entry
    -- already held carries no roll id, which is what a manual entry or one restored from an older
    -- release looks like, so the roll cannot tell them apart either.
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now, class = "MAGE" } })

    Whisper(lm, raider, { time = now + 1, rollID = 71, winnerKey = "Player-1-A",
                          winner = "Alric", item = WEAPON })

    T.eq(#lm.env.KART_LootHistory, 2, "a different item to the same raider is a second award")
end

do
    -- The same shape with the item field EMPTY. EntryRecord forwards whatever the stored entry's own
    -- item field holds, and that field can itself be empty -- an entry logged with no item, or one
    -- restored from an older SavedVariables file (see LH.HandleHistoryEntry). Nothing about the item
    -- can be compared then, so the roll id is the only thing left -- and against an entry that has
    -- none, that comparison has to fail rather than wave the award through as "the same".
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now, class = "MAGE" } })

    Whisper(lm, raider, { time = now + 1, rollID = 71, winnerKey = "Player-1-A",
                          winner = "Alric", item = "" })

    T.eq(#lm.env.KART_LootHistory, 2,
        "an award carrying no item is not swallowed by an unrelated one")
end

-- How far apart two clocks may be ------------------------------------------------------------------
do
    -- The window is five seconds of skew between the two clients that logged the same award, and
    -- five seconds is inside it. The two clients are two people's OS clocks; the difference is
    -- routinely a second or two and occasionally the whole window.
    -- The control first, because "one entry afterwards" is also what a message that never arrived
    -- looks like. Six seconds apart with a DIFFERENT roll is two awards, which proves the whisper
    -- reaches this client at all before the next assertion asks it not to add anything.
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now, rollID = 70, class = "MAGE" } })
    Whisper(lm, raider, { time = now + 6, rollID = 72, winnerKey = "Player-1-A",
                          winner = "Alric", item = GLOVES })
    T.eq(#lm.env.KART_LootHistory, 2, "a separate roll on the same item is a second award")

    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now, rollID = 70, class = "MAGE" } })
    Whisper(lm, raider, { time = now + 5, rollID = 70, winnerKey = "Player-1-A",
                          winner = "Alric", item = GLOVES })
    T.eq(#lm.env.KART_LootHistory, 1, "five seconds of skew is still the same award")
    -- And recognised as one rather than replaced by it. The count cannot tell those apart: an award
    -- that is not seen as a duplicate carries the same roll and item, so it REPLACES the entry
    -- instead of stacking a second one -- one row either way, with the peer's timestamp written
    -- over ours and this client's own record of when it happened gone.
    T.eq(lm.env.KART_LootHistory[1].time, now,
        "and the entry we logged ourselves is left as it stands, not rewritten by the peer's copy")
end

-- Who is allowed to write into it --------------------------------------------------------------
do
    -- Catch-up entries land in a SavedVariable that is kept forever. The "KART" addon prefix is
    -- public and CHAT_MSG_ADDON delivers whispers from anybody, so the sender being in our group is
    -- what stands between the loot record and a stranger writing rows into it. A key that resolves
    -- to nobody is not "probably fine".
    local _, lm = F.NewRaid()
    Hold(lm, {})
    local payload = ("%d:16:70:MAGE:1,1,1:Player-9-ZZZ:Nobody:BIS:::0:1:%s"):format(time(), GLOVES)

    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(payload, "Player-9-ZZZ") end)
    T.eq(#lm.env.KART_LootHistory, 0, "an entry from a key that is in no group is refused")

    RaidSim.As(lm, function() lm.KART.LH.HandleHistoryEntry(payload, nil) end)
    T.eq(#lm.env.KART_LootHistory, 0, "and so is one from no sender at all")
end

-- The two dated boundaries -----------------------------------------------------------------------
do
    -- Five minutes ahead is the line, and ON the line is drift rather than a broken clock. Refusing
    -- it costs the raider the award; the entry it is protecting against is dated years out.
    local _, lm, _, raider = F.NewRaid()
    Hold(lm, {})
    Whisper(lm, raider, { time = time() + 300, rollID = 70, winnerKey = "Player-1-A",
                          winner = "Alric", item = GLOVES })
    T.eq(#lm.env.KART_LootHistory, 1, "an entry exactly five minutes ahead is still accepted")
end

do
    -- The line a clear draws is the EPOCH, and it is the only thing allowed to draw it.
    --
    -- It used to be a timestamp comparison as well: an entry whose t was at or below our own
    -- KART_LootHistoryClearedAt was dropped. But t is the SENDER's time() and clearedAt is OURS, and
    -- comparing two clients' clocks against a wipe line is exactly what the epoch exists to abolish
    -- (design §2). The lootmaster wipes at 20:00 by their clock; a council member five minutes slow
    -- awards at 20:03 real and stamps 19:58; the lootmaster reconnects, asks for a catch-up, a peer
    -- answers with that entry at the current epoch -- and it was dropped. The lootmaster stayed
    -- permanently short an award the whole raid holds, its checksum never matched, and it pulled a
    -- full reconcile every night that re-sent and re-dropped the same row.
    local _, lm, _, raider = F.NewRaid()
    local cleared = time()
    Hold(lm, {})
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryClearedAt = cleared
        lm.env.KART_LootHistoryEpoch     = 2
    end)

    -- Decided before the wipe, and it says so: epoch 1 against our 2. Discarded by merge rule 2,
    -- whatever its timestamp claims -- this is the reply burst already in flight.
    Whisper(lm, raider, { time = cleared + 60, rollID = 70, winnerKey = "Player-1-A",
                          winner = "Alric", item = GLOVES, epoch = 1, id = "pre-wipe" })
    T.eq(#lm.env.KART_LootHistory, 0,
        "an award decided before the wipe stays cleared, even dated after it")

    -- Decided after the wipe by a client whose clock runs slow. At our own epoch, so it belongs to
    -- us however its timestamp reads.
    Whisper(lm, raider, { time = cleared - 300, rollID = 71, winnerKey = "Player-1-A",
                          winner = "Alric", item = GLOVES, epoch = 2, id = "post-wipe" })
    T.eq(#lm.env.KART_LootHistory, 1,
        "and an award at our epoch is not eaten by five minutes of clock difference")
    RaidSim.As(lm, function() lm.env.KART_LootHistoryClearedAt = nil end)
end

-- Answering a catch-up request -------------------------------------------------------------------
do
    -- What "everything newer than what I hold" means at the boundary: the requester names the
    -- timestamp of its newest entry, and that entry is one it already has. Sending it back is one
    -- whisper per catch-up that nobody needed.
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, {
        { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
          time = now - 20, rollID = 70, class = "MAGE" },
        { winner = "Sinja", winnerKey = "Player-1-S", item = GLOVES, reason = "OS",
          time = now - 10, rollID = 71, class = "PRIEST" },
    })
    -- The requester already holds the older of the two, so it asks from that entry's timestamp.
    Hold(raider, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                     time = now - 20, rollID = 70, class = "MAGE" } })

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    T.eq(#RaidSim.Sent(sim, "LC_HIST_BATCH"), 1,
        "only the award the requester is actually missing is sent back")
end

do
    -- A whole burst of awards carrying the SAME timestamp, which is what a boss dropping several
    -- pieces at once produces. They are sorted before they go out, and a comparator that answers
    -- "true" for two equal entries is not an ordering -- Lua is entitled to refuse it outright, and
    -- the whole answer is lost with it.
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    local many = {}
    for i = 1, 25 do
        many[i] = { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                    time = now - 100, rollID = 300 + i, class = "MAGE" }
    end
    Hold(lm, many)
    Hold(raider, {})

    RaidSim.ClearLog(sim)
    local ok = pcall(function()
        RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
        KARTTEST.AdvanceTime(30)
    end)
    T.truthy(ok, "a burst of awards sharing one timestamp is answered rather than refused")
    -- RaidSim.Messages, not RaidSim.Sent: 25 full item links push this batch well past 255 bytes,
    -- so the transport splits it and a plain prefix match on the log finds nothing.
    T.truthy(#RaidSim.Messages(sim, "LC_HIST_BATCH") > 0, "and the answer actually goes out")
end

do
    -- The cooldown on answering the same peer. A minute after the last answer is no longer the same
    -- request: somebody who disconnects and comes back is the entire point of catch-up sync, and
    -- being refused on the boundary leaves them without the evening's awards.
    local sim, lm, _, raider = F.NewRaid()
    local now = time()
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                 time = now - 30, rollID = 70, class = "MAGE" } })
    Hold(raider, {})

    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    Hold(raider, {})
    KARTTEST.AdvanceTime(30)          -- exactly 60 seconds after the answer
    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)
    T.truthy(#RaidSim.Sent(sim, "LC_HIST_BATCH") > 0,
        "a request a full minute after the last answer is answered again")
end

-- Logging our own award twice -----------------------------------------------------------------
-- The other half of the same question. LH.LogHistory runs off LC_RESULT, which has no dedup of its
-- own, so a redelivered message would otherwise write the award a second time.
do
    local _, lm = F.NewRaid()
    local now = time()

    -- A roll id on one side only. That is what a manual entry looks like, or one restored from a
    -- release that did not carry them -- and comparing two roll ids when only one exists answers
    -- "different" for what is plainly the same award arriving twice.
    Hold(lm, { { winner = "Alric", item = GLOVES, reason = "BIS", time = now, rollID = 70 } })
    RaidSim.As(lm, function() lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, nil, "Player-1-A") end)
    T.eq(#lm.env.KART_LootHistory, 1,
        "an award re-logged without a roll id is still recognised as the one already held")

    -- And the window that decides it when neither side has a roll id. Five seconds is outside it:
    -- the same item to the same raider that long apart is a re-roll, not a redelivered message,
    -- and swallowing it leaves the history showing one award while two were handed out.
    Hold(lm, { { winner = "Alric", item = GLOVES, reason = "BIS", time = now - 5 } })
    RaidSim.As(lm, function() lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, nil, "Player-1-A") end)
    T.eq(#lm.env.KART_LootHistory, 2, "five seconds later is a second award, not a redelivery")

    Hold(lm, { { winner = "Alric", item = GLOVES, reason = "BIS", time = now - 4 } })
    RaidSim.As(lm, function() lm.KART.LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, nil, "Player-1-A") end)
    T.eq(#lm.env.KART_LootHistory, 1, "while four seconds later is the same one arriving twice")
end

-- The cap on how much is kept --------------------------------------------------------------------
do
    -- Five hundred awards are kept and the oldest is dropped to make room. Dropping one row early
    -- means the list silently holds 499 forever -- and the row that goes is a real award somebody
    -- may still be owed.
    local _, lm = F.NewRaid()
    local now = time()
    local many = {}
    for i = 1, 500 do
        many[i] = { winner = "Alric", item = GLOVES, reason = "BIS", time = now - 1000 + i,
                    rollID = 1000 + i }
    end
    Hold(lm, many)
    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(WEAPON, "Sinja", "OS", "PRIEST", nil, 9999, "Player-1-S")
    end)
    T.eq(#lm.env.KART_LootHistory, 500, "the five hundred and first award evicts one, not two")
    T.eq(lm.env.KART_LootHistory[#lm.env.KART_LootHistory].winner, "Sinja",
        "and the new one is the one that stayed")
end

-- Two variants of one item (B127) ------------------------------------------------------------------
-- A boss dropping the same slot twice at two levels is an ordinary evening, and the two links differ
-- only inside the bonus list. The item comparison ran on KAUtil.GetItemString, which stopped at the
-- first comma of a live bonus list and kept exactly one bonus id -- so two variants agreeing on their
-- FIRST bonus id read as the same item, and the second award was dropped as a duplicate of the first.
--
-- Deliberately without a roll id on the entry already held: that is what a manual entry or one
-- restored from an older release looks like, and it leaves the item as the only discriminator, which
-- is the comparison under test.
do
    local _, lm, _, raider = F.NewRaid()
    local now = time()
    local function Variant(lastBonus)
        return "|cffa335ee|Hitem:" .. F.GLOVES .. "::::::::80:268::14:8:11946,10390,12043,10255," ..
               "1540,10879," .. lastBonus .. ":::::|h[Ezzorak's Gloombind]|h|r"
    end
    Hold(lm, { { winner = "Alric", winnerKey = "Player-1-A", item = Variant("11996"),
                 reason = "BIS", time = now, class = "MAGE" } })

    Whisper(lm, raider, { time = now + 1, rollID = 71, winnerKey = "Player-1-A",
                          winner = "Alric", item = Variant("11997") })

    T.eq(#lm.env.KART_LootHistory, 2,
        "a second variant of the same item is a second award, not a duplicate of the first")
end
