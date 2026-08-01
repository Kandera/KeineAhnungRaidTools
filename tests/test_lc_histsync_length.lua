-- A history entry that does not fit in one addon message.
--
-- The catch-up sync sends one LC_HIST_ENTRY per award, and SendAddonMessage takes 255 bytes. Over
-- that, nothing arrives -- not a truncated entry, no entry. The sender is told nothing either.
--
-- Two fallbacks exist for it: swap the full item link for the compact item string, and if that is
-- still too long, send the entry with an EMPTY item field. The comment on the second one states the
-- outcome as a fact -- "the entry still syncs; the item just shows blank" -- and that is what this
-- file is about, because nothing measured it.
--
-- The budget it has to fit into is small once the fixed part is counted: prefix, timestamp,
-- difficulty, rollID, class, packed colour and a GUID-shaped winner key come to roughly eighty
-- bytes, leaving about 175 for the winner's name and the REASON. The reason is a vote-button label,
-- and the settings box accepts 128 characters per label -- so "Zweitspec, aber nur wenn niemand
-- Mainspec braucht" is an ordinary thing for a raid leader to type, not an invented edge case.

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

-- Nothing is put on the wire that the client will refuse --------------------------------------------
-- The other half of the same statement: a message over the cap does not arrive, so sending one is
-- the same as sending nothing while believing otherwise.
do
    local sim, _, _ = SyncOne({
        time = time() - 60, item = GLOVES, winner = "Verylongname-Silvermoon",
        winnerKey = "Player-1096-0A1B2C3D",
        reason = string.rep("Zweitspec-wenn-frei ", 12), class = "MAGE", rollID = 72,
    })
    -- e.msg, not e: RaidSim.Sent returns log ENTRIES. Measuring the entry counts an array with no
    -- elements, which is 0 and always under the cap -- an assertion that cannot fail.
    for _, e in ipairs(RaidSim.Sent(sim, "LC_HIST_ENTRY")) do
        T.truthy(#e.msg <= 255,
            "every history message put on the wire fits the cap (" .. #e.msg .. " bytes)")
    end
end

-- The way a real raid gets there: umlauts ---------------------------------------------------------
-- The settings box limits a vote-button label to 128 LETTERS. A German label spends two bytes on
-- every umlaut, so "128 letters" is well over 200 bytes -- which is how an ordinary label, typed
-- into the ordinary field, produces a history entry too big for one message.
--
-- Walked across a range of WINNER NAME lengths, not reason lengths, and that distinction is the
-- whole point: how much has to go is (fixed part + reason) - 255, so the reason cancels out and the
-- cut lands at the same offset into it no matter how long it is. Lengthening the name moves the
-- fixed part, which is what walks the cut across the character boundaries. Measured, after a first
-- version of this file varied the reason and held the cut still at every one of its 25 steps.
--
-- Where the cut lands only falls INSIDE a character at some offsets: one length would pass
-- to go, and it only falls INSIDE a two-byte character at some of them. One length would pass
-- against a cut that counts bytes and knows nothing about characters.
local function IsValidUTF8(s)
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local extra
        if b < 0x80 then extra = 0
        elseif b >= 0xF0 then extra = 3
        elseif b >= 0xE0 then extra = 2
        elseif b >= 0xC0 then extra = 1
        else return false end
        for k = 1, extra do
            local c = s:byte(i + k)
            if not c or c < 0x80 or c >= 0xC0 then return false end
        end
        i = i + extra + 1
    end
    return true
end

do
    local checked, cut = 0, 0
    for pad = 0, 24 do
        local label = string.rep("üä", 60)
        local sim, _, raider = SyncOne({
            time = time() - 60, item = GLOVES,
            winner = "Name" .. string.rep("n", pad) .. "-Silvermoon",
            winnerKey = "Player-1096-0A1B2C3D", reason = label, class = "MAGE", rollID = 73 + pad,
        })
        checked = checked + 1
        if #raider.env.KART_LootHistory ~= 1 then
            T.truthy(false, "an award with a long German reason is lost at pad " .. pad)
            break
        end
        for _, e in ipairs(RaidSim.Sent(sim, "LC_HIST_ENTRY")) do
            if #e.msg > 255 then
                T.truthy(false, "a message over the cap went out at pad " .. pad .. " (" .. #e.msg .. ")")
                break
            end
        end
        local got = raider.env.KART_LootHistory[1].reason or ""
        if #got < #label then cut = cut + 1 end
        if not IsValidUTF8(got) then
            T.truthy(false, "the reason was cut inside a character at pad " .. pad)
            break
        end
    end
    T.eq(checked, 25, "every reason length in the range was tried")
    T.truthy(cut > 0, "and at least one of them actually had to be cut (" .. cut .. ")")
    T.truthy(IsValidUTF8("ü"), "the validator accepts a whole umlaut")
end

do
    -- Three-byte characters, which is where backing up needs a LOOP rather than a single step: an
    -- umlaut cut in half leaves one stray byte, "€" or a CJK glyph can leave two. Reachable without
    -- leaving Europe -- the euro sign is three bytes, and item names carry it.
    local checked = 0
    for pad = 0, 24 do
        local label = string.rep("€", 60)
        local _, _, raider = SyncOne({
            time = time() - 60, item = GLOVES,
            winner = "Name" .. string.rep("n", pad) .. "-Silvermoon",
            winnerKey = "Player-1096-0A1B2C3D", reason = label, class = "MAGE", rollID = 120 + pad,
        })
        checked = checked + 1
        if #raider.env.KART_LootHistory ~= 1 then
            T.truthy(false, "an award with a three-byte-character reason is lost at pad " .. pad)
            break
        end
        if not IsValidUTF8(raider.env.KART_LootHistory[1].reason or "") then
            T.truthy(false, "a three-byte character was cut apart at pad " .. pad)
            break
        end
    end
    T.eq(checked, 25, "every three-byte cut position was tried")
    T.truthy(not IsValidUTF8(string.char(195)), "and rejects a lead byte with nothing after it")
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
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)

    local far = time() + 5 * 365 * 24 * 60 * 60
    RaidSim.As(raider, function()
        raider.KASC:Send(("LC_HIST_ENTRY:%d:16:70:MAGE:1,1,1:Player-1-A:Alric:BIS:%s")
            :format(far, GLOVES), "WHISPER", lm.name)
    end)
    KARTTEST.AdvanceTime(1)
    T.eq(#lm.env.KART_LootHistory, 0, "an entry dated years ahead is refused")

    -- The point of refusing it: the catch-up still works afterwards.
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
    local asks = RaidSim.Sent(sim, "LC_HIST_REQ")
    T.eq(#asks, 1, "and the client still asks its peers for what it is missing")
    local since = tonumber(((asks[1] or {}).msg or ""):match("^LC_HIST_REQ:(%d+)"))
    T.truthy(since and since <= time(),
        "from a point in time that can actually be reached, not from the bad entry's date")
end

do
    -- The boundary itself: a few minutes of clock drift between two raiders is ordinary and must not
    -- cost them an award, while years ahead is not drift.
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function() lm.env.KART_LootHistory = {} end)
    RaidSim.As(raider, function()
        raider.KASC:Send(("LC_HIST_ENTRY:%d:16:71:MAGE:1,1,1:Player-1-A:Alric:BIS:%s")
            :format(time() + 120, GLOVES), "WHISPER", lm.name)
    end)
    KARTTEST.AdvanceTime(1)
    T.eq(#lm.env.KART_LootHistory, 1, "two minutes of clock drift is accepted, not treated as an attack")
end

-- How much one answer may be --------------------------------------------------------------------
-- One whisper per entry, staggered. A peer holding a long history answering in full would put
-- hundreds of messages on the wire for one raider walking in.
do
    local sim, lm, _, raider = F.NewRaid()
    local many = {}
    for i = 1, 80 do
        many[i] = { time = time() - 1000 + i, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
                    reason = "BIS", class = "MAGE", rollID = 200 + i }
    end
    RaidSim.As(lm, function() lm.env.KART_LootHistory = many end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)

    RaidSim.ClearLog(sim)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(30)

    local sent = #RaidSim.Sent(sim, "LC_HIST_ENTRY")
    T.truthy(sent > 0, "the peer answers a catch-up request")
    T.truthy(sent <= 30,
        "with a bounded number of messages, not one per entry it happens to hold (" .. sent .. ")")
end
