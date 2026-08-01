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
    for _, msg in ipairs(RaidSim.Sent(sim, "LC_HIST_ENTRY")) do
        T.truthy(#msg <= 255,
            "every history message put on the wire fits the cap (" .. #msg .. " bytes)")
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
        for _, msg in ipairs(RaidSim.Sent(sim, "LC_HIST_ENTRY")) do
            if #msg > 255 then
                T.truthy(false, "a message over the cap went out at pad " .. pad .. " (" .. #msg .. ")")
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
