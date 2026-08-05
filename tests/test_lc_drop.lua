-- One message per boss.
--
-- A boss drops several items at once and KART used to announce each on its own: six items in a
-- 25-man raid were six LC_START plus six roll tables, and three quarters of that was the same 25
-- identity keys repeated six times because the messages knew nothing of each other. This collects
-- what falls inside half a second and names the participants once.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- Counted with RaidSim.Messages, not RaidSim.Sent: a batch of three items in this five-client fixture
-- is already two chunks on the wire, and a prefix match on the token would find neither of them.
local function Announced(sim) return RaidSim.Messages(sim, "LC_DROP:") end

local TORVI = { name = "Torvi", realm = "TarrenMill", guid = "Player-1096-0A1B2C42",
                class = "MAGE", locale = "enUS" }

-- Blizzard re-raises START_LOOT_ROLL for a roll that is STILL RUNNING -- the same event again, on the
-- same client, for the same item. That premise is the whole point: LC.DrawRollTable's guard, and the
-- batch's own dedupe, exist for exactly this event, and both need the roll to be live to be reached.
--
-- The stub closes a roll for whoever has answered it (the real API goes blank the moment you roll),
-- and the lootmaster force-won this one when it dropped -- so `rolledBy` is cleared to put it back in
-- the state Blizzard raises the event from. Driven only on the announcer, rather than through F.Drop,
-- which would re-record who Blizzard raised the roll on and hand a newcomer a roll the game never
-- would.
local function ReRaise(lm, rollID)
    KARTTEST.lootRolls[rollID].rolledBy = nil
    RaidSim.As(lm, function()
        KARTTEST.FireEvent("START_LOOT_ROLL", rollID)
        lm.KART.LC.OnStartLootRoll(rollID)
    end)
    KARTTEST.AdvanceTime(1)
end

-- The invariant, read back off the raid: whatever numbers a client ended up holding for this item are
-- the ANNOUNCER'S OWN table -- the one that was drawn rather than parsed -- and nobody holds a number
-- that was never cast. Both halves are needed. A head naming somebody the draw never covered puts a 0
-- in their row; a head that has lost somebody drops a real number instead; and either way the
-- announcer is left the only client in the raid holding a different table from everyone else, which
-- is what every bad raid night has looked like from the inside.
local function AssertNumbersIntact(sim, lm, rollID, what)
    for _, c in ipairs(sim.clients) do
        local held = c.KART.LC.rolls[rollID]
        if held then
            T.deep_eq(held, lm.KART.LC.rolls[rollID],
                c.name .. " holds the announcer's own table (" .. what .. ")")
        end
        for who, value in pairs(held or {}) do
            T.truthy(value >= 1 and value <= 100,
                "nobody is handed a number they never rolled (" .. what .. "/" .. who .. ")")
        end
    end
end

-- Three items, one message ------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)

    F.Drop(sim, 950, F.GLOVES)
    F.Drop(sim, 951, F.WEAPON)
    F.Drop(sim, 952, F.TOKEN)
    KARTTEST.AdvanceTime(1)

    T.eq(#RaidSim.Sent(sim, "LC_START:"), 0, "no item is announced on its own any more")
    T.eq(#Announced(sim), 1, "the three of them travel as one message")
    T.eq(Announced(sim)[1].from, lm.name, "sent by the loot owner")

    local council = sim.byName.Merrit
    for _, id in ipairs({ 950, 951, 952 }) do
        T.truthy(council.KART.LC.rollItems[id] ~= nil, "every item of the batch arrives (" .. id .. ")")
        T.deep_eq(council.KART.LC.rolls[id], lm.KART.LC.rolls[id],
            "and its rolls arrive with it (" .. id .. ")")
    end
    F.AssertAgreed(sim, 950, "about the first item of a batch")
    F.AssertAgreed(sim, 952, "about the last item of a batch")
end

-- The numbers belong to the right people ----------------------------------------------------------
-- The head names the participants once and each item lists its numbers in that order, so an
-- off-by-one in either half would hand somebody else's roll to a raider. Asserted against the
-- lootmaster's own table, which is the one that was drawn rather than parsed.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 953, F.GLOVES)
    F.Drop(sim, 954, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    for _, id in ipairs({ 953, 954 }) do
        for _, c in ipairs(sim.clients) do
            T.eq(council.KART.LC.rolls[id][c.guid], lm.KART.LC.rolls[id][c.guid],
                "each raider's own number survives the shared key list (" .. id .. "/" .. c.name .. ")")
        end
    end
end

-- An item that misses the window gets its own message ----------------------------------------------
do
    local sim = F.NewRaid()
    F.Drop(sim, 955, F.GLOVES)
    KARTTEST.AdvanceTime(2)
    RaidSim.ClearLog(sim)
    F.Drop(sim, 956, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    T.eq(#Announced(sim), 1, "a later drop opens a new window rather than joining a closed one")
    local council = sim.byName.Merrit
    T.truthy(council.KART.LC.rollItems[956] ~= nil, "and arrives")
end

-- A full item string survives the split -------------------------------------------------------------
-- The reason the full string travels at all is B119: an itemID alone carries no bonus ids, so the
-- whole raid read "Item Level 44" off a 285 item. That string contains both colons and commas, which
-- is exactly what a naive separator choice would break.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 957, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.eq(council.KART.LC.rollItems[957], lm.KART.LC.rollItems[957],
        "the receiver rebuilds the same item the announcer sent")
end

-- Two items of one boss whose participants differ ---------------------------------------------------
-- The head names the participants ONCE and every entry's numbers are ordered by it, so an item drawn
-- against a different set of people cannot ride in the same message: a key the head does not carry has
-- nowhere to put its number, and a key it carries that this item never drew for would travel as a 0
-- nobody rolled -- accepted as authoritative, because it came from the recorded announcer.
--
-- SnapshotEligible runs per item against a fresh identity walk, so this is not exotic: somebody
-- walking in between two items of one boss does it, and so does a name resolving from a pending text
-- key to a GUID in the same half second. Splitting the batch is a fine answer; a silent 0 is not.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 959, F.GLOVES)
    RaidSim.Join(sim, TORVI)
    F.Drop(sim, 960, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    for _, id in ipairs({ 959, 960 }) do
        for _, c in ipairs(sim.clients) do
            local held = c.KART.LC.rolls[id]
            if held then
                T.deep_eq(held, lm.KART.LC.rolls[id],
                    c.name .. " holds the announcer's own table for " .. id)
            end
            for who, value in pairs(held or {}) do
                T.truthy(value >= 1 and value <= 100,
                    "and nobody is handed a number they never rolled (" .. id .. "/" .. who .. ")")
            end
        end
    end
end

-- A rollID reused for a different item INSIDE the window ---------------------------------------------
-- Blizzard hands the same number to an unrelated drop within seconds -- several trash corpses looted in
-- the same second is the documented trigger -- so it lands inside a collection window as readily as
-- outside one. One number cannot carry two items in one message: the receiver's own reuse rule would
-- purge whichever of them it read first. So the batch splits, and the rule that has to hold is that
-- NOTHING THAT ENTERED A BATCH DISAPPEARS UNSENT. The lootmaster has already force-won the first item,
-- so an entry dropped here is an item sitting in his bags that the raid never saw a card for -- silent,
-- with nothing on any screen to notice it by.
do
    local sim = F.NewRaid()
    RaidSim.ClearLog(sim)

    F.Drop(sim, 970, F.GLOVES)
    F.Drop(sim, 970, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    local sent = Announced(sim)
    T.eq(#sent, 2, "the item that had the number first is still announced, in a message of its own")
    T.truthy(sent[1] and sent[1].msg:find("item:" .. F.GLOVES, 1, true),
        "the first message names the item that dropped first")
    T.truthy(sent[2] and sent[2].msg:find("item:" .. F.WEAPON, 1, true),
        "and the second names the one that took its number")

    local council = sim.byName.Merrit
    T.truthy(tostring(council.KART.LC.rollItems[970]):find("item:" .. F.WEAPON, 1, true),
        "the raid ends up on the item the number belongs to now")
    F.AssertAgreed(sim, 970, "about a number that changed hands inside one window")
end

-- ...and the SAME item re-raised inside the window is not written into it twice -----------------------
-- Blizzard re-raises START_LOOT_ROLL for a roll that is still running. That is not a reuse and the
-- batch stays whole -- but the entry must not be added a second time either: duplicated bytes, and the
-- vote catch-up scheduled twice for one item.
do
    local sim = F.NewRaid()
    RaidSim.ClearLog(sim)

    F.Drop(sim, 971, F.GLOVES)
    F.Drop(sim, 971, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local sent = Announced(sim)
    T.eq(#sent, 1, "a roll re-raised for the same item stays in the one message")
    local _, written = sent[1].msg:gsub("971#", "")
    T.eq(written, 1, "and is written into it once, not twice")
end

-- A roll RE-RAISED after the participant set changed -------------------------------------------------
-- Blizzard raises START_LOOT_ROLL again for a roll that is still running, and by then the roster walk
-- can answer differently -- but LC.DrawRollTable refuses to redraw a table the raid has already been
-- shown, and rightly so. So the numbers belong to the OLD set while the fresh snapshot names the new
-- one, and a head taken from the snapshot ships numbers drawn against something else. That is the
-- third instance of one defect (the batch split had already been taught to compare a snapshot against
-- the batch head -- but this path runs with no batch open at all, so the comparison never happened).
--
-- Which is why the head is no longer compared to anything: it is DERIVED from LC.rolls[rollID], the
-- numbers' own authority (LC.DrawnKeys). Three ways the sets can part, all of them ordinary.

-- (1) A pending text key resolves to a GUID between the two raises. The likeliest live trigger, and
-- the exact instability the split rule's own comment cites: SnapshotEligible deliberately keeps a
-- raider whose name has not resolved yet under a text key, and the moment it does resolve the SET
-- changes without a single person moving.
do
    local sim, lm = F.NewRaid()
    local late = sim.byName.Sinja
    KARTTEST.guidBlackout[late.unit] = true
    F.Drop(sim, 989, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    KARTTEST.guidBlackout[late.unit] = nil

    ReRaise(lm, 989)
    T.truthy(lm.KART.LC.rolls[989][late.guid] == nil,
        "the draw still belongs to the set it was made against, text key and all")
    AssertNumbersIntact(sim, lm, 989, "a key resolved between two raises")
end

-- (2) Somebody walks in between the two raises.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 990, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    RaidSim.Join(sim, TORVI)
    ReRaise(lm, 990)

    for _, c in ipairs(sim.clients) do
        T.eq((c.KART.LC.rolls[990] or {})[TORVI.guid], nil,
            "the newcomer gets no number for an item that dropped before them (" .. c.name .. ")")
    end
    AssertNumbersIntact(sim, lm, 990, "a raider joined between two raises")
end

-- (3) ...and the mirror: somebody ports out between them, which drops a REAL number rather than
-- inventing one. Just as bad -- the raider it belonged to is missing from every peer's tally while the
-- announcer still has them.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 992, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    local gone = sim.byName.Sinja
    RaidSim.Leave(sim, "Sinja")
    ReRaise(lm, 992)

    T.truthy(lm.KART.LC.rolls[992][gone.guid] ~= nil,
        "the departed raider's own number is still part of the roll they were there for")
    AssertNumbersIntact(sim, lm, 992, "a raider left between two raises")
end

-- Rolls switched off raid-wide ----------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
    end)
    KARTTEST.AdvanceTime(0.5)
    RaidSim.ClearLog(sim)
    F.Drop(sim, 958, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.truthy(council.KART.LC.rollItems[958] ~= nil, "the item arrives with rolls switched off")
    T.eq(next(council.KART.LC.rolls[958] or {}), nil, "and carries no numbers")
    -- ...and no NAME LIST either (design §B/§F). The head exists to order the numbers, so with no
    -- numbers it orders nothing -- and it is the most expensive part of the message: 25 identity keys
    -- is ~525 bytes, on the one ALERT message this whole change exists to shrink. It used to carry the
    -- whole roster because it was built from LC.rollEligible, which SnapshotEligible writes whether or
    -- not the raid rolls at all.
    T.eq(#Announced(sim), 1, "the item is still announced")
    T.truthy(Announced(sim)[1].msg:match("^LC_DROP:%d+:r:;"), "and names nobody in the head")
end

-- /kart add with several links is one message too --------------------------------------------------
-- The list is already complete when the command runs, so nothing has to be waited for -- but it is
-- the same message, with the same shared participant list, and the receiver routes it into the
-- manual handling because a manually added item has no Blizzard roll behind it.
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)

    local links = KARTTEST.items[F.GLOVES].link .. " " .. KARTTEST.items[F.WEAPON].link
    RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(links) end)
    KARTTEST.AdvanceTime(1)

    T.eq(#RaidSim.Sent(sim, "LC_MANUAL_START:"), 0, "manual items are not announced one by one either")
    -- Counted with Announced (RaidSim.Messages), not a bare RaidSim.Sent: two full item strings plus
    -- the shared key list is already over the 255-byte cap, so this lands as a split message and a
    -- plain prefix search on the token would find nothing (see the comment on RaidSim.Messages).
    T.eq(#Announced(sim), 1, "they travel as one message")

    local council = sim.byName.Merrit
    local tracked = 0
    for _, link in pairs(council.KART.LC.rollItems) do
        if link then tracked = tracked + 1 end
    end
    T.truthy(tracked >= 2, "and both of them arrive")
end

-- /kart add with more links than one message can carry refuses the surplus, loudly ------------------
-- The receiver caps a batch at TABLE_MAX_IDS (12, see the test above). Left unchecked on the sender,
-- a 13th link would still open its own roll and windows locally on the lootmaster while every peer
-- silently dropped it at the cap -- the lootmaster would believe an item was announced that never
-- reached anybody. StartManualRoll must refuse the surplus before any of that happens, and say so.
do
    local function Capture(fn)
        local lines = {}
        local realPrint = _G.print
        _G.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
            lines[#lines + 1] = table.concat(parts, " ")
        end
        local ok, err = pcall(fn)
        _G.print = realPrint
        if not ok then error(err, 0) end
        return table.concat(lines, "\n")
    end

    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)

    local link = KARTTEST.items[F.GLOVES].link
    local links = {}
    for i = 1, 13 do links[i] = link end

    local output = Capture(function()
        RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(table.concat(links, " ")) end)
    end)
    KARTTEST.AdvanceTime(1)

    local trackedLocally = 0
    for _, itemLink in pairs(lm.KART.LC.rollItems) do
        if itemLink then trackedLocally = trackedLocally + 1 end
    end
    T.eq(trackedLocally, 12, "the lootmaster itself opens twelve, never the thirteenth")

    local council = sim.byName.Merrit
    local trackedRemote = 0
    for _, itemLink in pairs(council.KART.LC.rollItems) do
        if itemLink then trackedRemote = trackedRemote + 1 end
    end
    T.eq(trackedRemote, 12, "and the raid receives the same twelve")

    T.truthy(output:find(string.format(lm.KART.L.LC_MANUAL_ADD_CAPPED, 12, 1), 1, true),
        "the surplus is refused with a printed message, not silently")
end

-- What one message may do to a client that receives it ----------------------------------------------
-- LC_START was one item per message, so one message was one popup. A batch is a list, and both of the
-- things a list can do that a single item could not are answered here. Driven through LC.HandleDrop
-- directly: what is under test is what the RECEIVER accepts, and no sender in this addon builds either
-- of these shapes.
local function ReceiveDrop(lm, to, payload)
    RaidSim.As(to, function() to.KART.LC.HandleDrop(payload, lm.guid) end)
end

local function HeadAndNums(sim)
    local keys = {}
    for _, c in ipairs(sim.clients) do keys[#keys + 1] = c.guid end
    table.sort(keys)
    local nums = {}
    for i = 1, #keys do nums[i] = i end
    return table.concat(keys, ","), table.concat(nums, ",")
end

-- The entry count is bounded, so one message cannot open windows without end ------------------------
-- Bounded by TABLE_MAX_IDS (12), the number of rolls the heartbeat can name at once: past that the
-- raid could not be repaired back into agreement about the extra items anyway.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit
    local head, nums = HeadAndNums(sim)

    local parts = {}
    for i = 1, 20 do
        parts[#parts + 1] = (800 + i) .. "#" .. nums .. "#item:" .. F.GLOVES
    end
    ReceiveDrop(lm, council, "20:r:" .. head .. ";" .. table.concat(parts, ";"))

    local tracked = 0
    for i = 1, 20 do if council.KART.LC.rollItems[800 + i] then tracked = tracked + 1 end end
    T.eq(tracked, 12, "a batch of twenty items opens twelve, not twenty")
    T.eq(council.KART.LC.diag.dropCapped, 1, "hitting the cap bumps a diagnostic instead of staying silent")
end

-- An entry that names no item leaves nothing behind ------------------------------------------------
-- The two halves of an entry are one message and must agree about whether it described an item at
-- all. A manual item has no Blizzard roll behind it to rebuild a link from, so an empty item string
-- announces nothing -- and its numbers, applied anyway, would be an orphan table under a rollID no
-- screen can show and no repair can resolve.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit
    local head, nums = HeadAndNums(sim)

    ReceiveDrop(lm, council, "20:m:" .. head .. ";777#" .. nums .. "#")

    T.eq(council.KART.LC.rollItems[777], nil, "an entry naming no item announces nothing")
    T.eq(council.KART.LC.rolls[777], nil, "and leaves no numbers behind under it either")
end

-- ...but a refused ANNOUNCER still does not cost a raider the numbers (B129) -----------------------
-- The other half of that verdict, and the half that must NOT be shared. A client whose ownership view
-- disagrees with the real owner's refuses the announcement and would be left with no numbers for that
-- item permanently -- the heartbeat that could prompt it to ask again gates on the same check. The
-- numbers have their own weaker rule for exactly this ("fills a void, never replaces").
do
    local sim = F.NewRaid()
    local plain, notOwner = sim.byName.Alric, sim.byName.Sinja
    local head, nums = HeadAndNums(sim)
    local before = plain.KART.LC.diag.refusedSender

    -- From a group member who is NOT the loot owner, which is what an ownership disagreement looks
    -- like from the receiving end -- the real owner sending under a config this client no longer
    -- agrees with reaches it in exactly this shape.
    RaidSim.As(plain, function()
        plain.KART.LC.HandleDrop("20:r:" .. head .. ";778#" .. nums .. "#item:" .. F.GLOVES,
            notOwner.guid)
    end)

    T.eq(plain.KART.LC.diag.refusedSender, before + 1, "the announcement itself is refused")
    T.eq(plain.KART.LC.rollItems[778], nil, "so no window opens for it")
    T.truthy(plain.KART.LC.rolls[778] ~= nil,
        "but the numbers still fill a void, or the disagreement would cost them permanently (B129)")
end

-- The primitives that drop and hold a message can see a SPLIT one -----------------------------------
-- A boss's batch is several chunks on the wire, and only the FIRST of them carries the token -- the
-- rest lead with AceComm's control byte. RaidSim.Blackhole and RaidSim.Hold matched the raw chunk, so
-- they silently no-opped for exactly the message this file is about: a test asserting "the repair
-- reaches it anyway" would have passed without anything ever being dropped. A silent no-op in a test
-- primitive is worse than a broken one, so it is held to a test of its own.
--
-- It takes a REAL-SIZED raid to reach that shape now. Packed (see the packing tests at the end of this
-- file), three items among the fixture's five clients fit in one chunk with room to spare; six items
-- among twenty-five do not, and that is the message a boss actually produces. Measured here: 436 bytes
-- across two chunks, against 156 for the five-client batch this used to send.
local function BigRaid(extra)
    local sim = F.NewRaid()
    for i = 1, extra or 20 do
        RaidSim.Join(sim, { name = "Extra" .. i, realm = "TarrenMill",
                            guid = string.format("Player-1096-0B%06X", i),
                            class = "MAGE", locale = "enUS" })
    end
    return sim
end

local BIG_BATCH = { F.GLOVES, F.WEAPON, F.TOKEN, F.PLATE_CHEST, F.GLOVES, F.WEAPON }

do
    local sim = BigRaid()
    RaidSim.Blackhole(sim, "LC_DROP")
    RaidSim.ClearLog(sim)

    for i, itemID in ipairs(BIG_BATCH) do F.Drop(sim, 979 + i, itemID) end
    KARTTEST.AdvanceTime(1)

    T.eq(#Announced(sim), 1, "the batch was sent")
    T.truthy(#RaidSim.Sent(sim, "\001LC_DROP") > 0, "and was too long to fit in one chunk")

    -- Probed on what only the MESSAGE can deliver. Every client in the raid gets its own
    -- START_LOOT_ROLL and tracks the item from that, so LC.rollItems says nothing about whether the
    -- announcement arrived -- the numbers and the recorded announcer come from nowhere else.
    local council = sim.byName.Merrit
    for i = 1, #BIG_BATCH do
        local id = 979 + i
        T.eq(council.KART.LC.rolls[id], nil,
            "a blackholed split message reaches nobody (" .. id .. ")")
        T.eq(council.KART.LC.rollAnnouncedBy[id], nil, "nor does its announcement (" .. id .. ")")
    end
end

-- ...and the same message, merely SLOW, arrives whole once it is let go.
do
    local sim = BigRaid()
    RaidSim.Hold(sim, "LC_DROP")

    for i, itemID in ipairs(BIG_BATCH) do F.Drop(sim, 999 + i, itemID) end
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.eq(council.KART.LC.rolls[1000], nil, "a held split message has not arrived yet")

    RaidSim.Release(sim, "LC_DROP")
    KARTTEST.AdvanceTime(0)

    -- Pins this block's own premise rather than inheriting it from BigRaid()/BIG_BATCH: what is under
    -- test is that Release lets EVERY chunk of a split message go, and a batch that quietly stopped
    -- splitting would leave that passing while testing nothing.
    T.truthy(#RaidSim.Sent(sim, "\001LC_DROP") > 0, "the message it let go was a split one")

    for i = 1, #BIG_BATCH do
        local id = 999 + i
        T.truthy(council.KART.LC.rolls[id] ~= nil,
            "and every chunk of it is let go together, so it reassembles (" .. id .. ")")
    end
end

-- Packed, and only when it buys a chunk ----------------------------------------------------------
-- Measured before this was built: 25 raiders and six items are 1624 bytes, seven chunks of 254, and
-- three quarters of it is the same identity keys and the same item-string shapes over and over --
-- which is what a compressor is for. Encoding it for the addon channel costs 0-3 bytes, not the
-- third one would expect, because it escapes nulls rather than re-encoding everything.
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)
    F.Drop(sim, 960, F.GLOVES)
    F.Drop(sim, 961, F.WEAPON)
    F.Drop(sim, 962, F.TOKEN)
    KARTTEST.AdvanceTime(1)

    local msg = Announced(sim)[1]
    T.truthy(msg ~= nil, "the batch went out")
    T.truthy(msg.msg:sub(1, 8) == "LC_DROP:", "and still opens in plain text, so the guards can read it")
    T.truthy(#msg.msg <= 255, "packed, not carried whole (" .. #msg.msg .. " bytes)")

    local council = sim.byName.Merrit
    for _, id in ipairs({ 960, 961, 962 }) do
        T.truthy(council.KART.LC.rollItems[id] ~= nil, "every item survives the round trip (" .. id .. ")")
        T.deep_eq(council.KART.LC.rolls[id], lm.KART.LC.rolls[id], "and its rolls do too (" .. id .. ")")
    end
    F.AssertAgreed(sim, 961, "about a packed batch")
end

-- A small message stays readable ------------------------------------------------------------------
-- Packing something that fits in one chunk anyway costs time and buys nothing, and makes the wire
-- log unreadable for whoever is debugging the next raid night. Asserted on a short LC_DROP, which is
-- a message that actually reaches the packing decision -- LC_TABLE never calls it at all, so pointing
-- this at the heartbeat proved nothing about the threshold.
do
    local sim = F.NewRaid()
    RaidSim.ClearLog(sim)
    F.Drop(sim, 965, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local sent = RaidSim.Sent(sim, "LC_DROP:")
    T.eq(#sent, 1, "one item among five raiders is one message")
    T.truthy(sent[1].msg:match("^LC_DROP:%d+:r:") ~= nil,
        "the kind letter stays lower case, which is what says the rest is plain")
    T.truthy(sent[1].msg:find("item:" .. F.GLOVES, 1, true) ~= nil, "and it stays readable on the wire")
end

-- The decision is made against the MESSAGE, not the payload ---------------------------------------
-- The head is part of what the transport weighs: AceComm sends one part iff the whole string is 255
-- bytes or less, and "LC_ROLLS:" is nine of them. Judging the payload alone left a band where a
-- message went out split AND unpacked -- exactly the outcome packing exists to prevent -- and a
-- ten-man group's catch-up roll table sat in it. Sized here so the plain message lands just over the
-- limit while its payload is still under: the band, and nothing else.
do
    local sim = BigRaid(5)
    local lm = sim.byName.Bramor
    F.Drop(sim, 966, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    -- The plain form this table WOULD have had, built to the serializer's own format because that is
    -- the length being asserted about. A group whose plain message no longer lands in the band fails
    -- here with the number, rather than passing while testing something else.
    local parts = {}
    for key, value in pairs(lm.KART.LC.rolls[966]) do parts[#parts + 1] = key .. "=" .. value end
    table.sort(parts)
    local plain = "LC_ROLLS:966:@" .. F.GLOVES .. ":" .. table.concat(parts, ",")
    T.truthy(#plain > 255 and #plain <= 264,
        "this group's plain roll table is inside the band (" .. #plain .. " bytes)")

    local wire = RaidSim.As(lm, function() return lm.KART.LC.SerializeRollTable(966) end)
    T.truthy(#wire <= 255, "so it is packed and goes out as one chunk (" .. #wire .. " bytes)")
end

-- A block that cannot be unpacked is refused, not half-stored ------------------------------------
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit
    local before = council.KART.LC.rollItems[963]
    RaidSim.As(council, function()
        council.KART.LC.HandleDrop("20:R:not a valid deflate block at all", lm.guid)
    end)
    T.eq(council.KART.LC.rollItems[963], before, "a corrupt block changes nothing")
end

-- A roll table is packed on the same terms, and refused on the same terms -------------------------
-- The catch-up answer (LC_ROLLS) carries the same identity keys as the batch and crosses a chunk at
-- the same raid size: 25 raiders is three chunks in plain text and one packed. Driven at the handler,
-- because what a repair is worth is what the client that lost the table ends up holding.
do
    local sim = BigRaid()
    local lm = sim.byName.Bramor
    F.Drop(sim, 964, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local wire = RaidSim.As(lm, function() return lm.KART.LC.SerializeRollTable(964) end)
    T.truthy(wire:sub(1, 11) == "LC_ROLLS:P:", "a raid-sized table travels packed (" .. #wire .. " bytes)")
    T.truthy(#wire <= 254, "and fits in one chunk")

    local council = sim.byName.Merrit
    council.KART.LC.rolls[964] = nil
    RaidSim.As(council, function()
        council.KART.LC.HandleRolls(wire:match("^LC_ROLLS:(.*)$"), lm.guid)
    end)
    T.deep_eq(council.KART.LC.rolls[964], lm.KART.LC.rolls[964],
        "and a client that lost it gets the announcer's own table back")

    -- Same rule as the batch: a block that will not come back leaves the client with the gap it had,
    -- which the heartbeat's repair path can still fill, rather than half a table it would never ask
    -- about again.
    council.KART.LC.rolls[964] = nil
    RaidSim.As(council, function()
        council.KART.LC.HandleRolls("P:not a valid deflate block at all", lm.guid)
    end)
    T.eq(council.KART.LC.rolls[964], nil, "a corrupt table changes nothing either")
end

-- A refused block is COUNTED, on both handlers -----------------------------------------------------
-- The one refusal in these two handlers that used to be silent, and the worst one to be silent about:
-- every other refusal here is on /kart status (refusedSender, unknownRoll, rollsConflict, dropCapped),
-- while this one costs the client a whole boss's items and left nothing to read on either end. The
-- failure it exists for is a LibDeflate mismatch -- LibStub hands out the highest minor ANY addon
-- loaded, so a raider is not guaranteed to be running the copy KART ships.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit
    local before = council.KART.LC.diag.packedUnreadable

    RaidSim.As(council, function()
        council.KART.LC.HandleDrop("20:R:not a valid deflate block at all", lm.guid)
    end)
    T.eq(council.KART.LC.diag.packedUnreadable, before + 1, "a batch that will not unpack is counted")

    RaidSim.As(council, function()
        council.KART.LC.HandleRolls("P:not a valid deflate block at all", lm.guid)
    end)
    T.eq(council.KART.LC.diag.packedUnreadable, before + 2, "and so is a roll table that will not")
end

-- A block too large to be ours is refused before it is expanded ------------------------------------
-- AceComm reassembles a multipart message of any length, so without a cap a group member could send
-- one small block that expands to megabytes on every client in the raid, where plain text cost the
-- raid exactly what it weighed. Driven with a block that decompresses PERFECTLY -- the same payload
-- goes in plain and is accepted below -- so what is under test is the size refusal itself and not
-- another way of failing to read the thing.
do
    local sim, lm = F.NewRaid()
    local head, nums = HeadAndNums(sim)
    local LibDeflate = LibStub("LibDeflate")

    -- Padding the compressor cannot get rid of, so the BLOCK crosses the cap rather than the payload.
    -- It rides in the item string, which is the last field of an entry and may hold anything.
    math.randomseed(20260805)
    local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-"
    local pad = {}
    for i = 1, 6000 do
        local n = math.random(#alphabet)
        pad[i] = alphabet:sub(n, n)
    end
    local payload = head .. ";968#" .. nums .. "#item:" .. F.GLOVES .. ":" .. table.concat(pad)
    local blob = LibDeflate:EncodeForWoWAddonChannel(
        LibDeflate:CompressDeflate(payload, { level = 1 }))
    T.truthy(#blob > 2048, "the block is over the cap (" .. #blob .. " bytes)")

    local capped = sim.byName.Merrit
    local before = capped.KART.LC.diag.packedUnreadable
    ReceiveDrop(lm, capped, "20:R:" .. blob)
    T.eq(capped.KART.LC.rollItems[968], nil, "an oversized block announces nothing")
    T.eq(capped.KART.LC.diag.packedUnreadable, before + 1,
        "and is counted on the same line as one that cannot be read at all")

    -- The premise, without which the assertions above would pass on a payload that was simply bad:
    -- unpacked, this very payload IS a batch, and the same client takes it.
    local plainClient = sim.byName.Alric
    ReceiveDrop(lm, plainClient, "20:r:" .. payload)
    T.truthy(plainClient.KART.LC.rollItems[968] ~= nil,
        "the same payload sent plain is a batch this client accepts")
end
