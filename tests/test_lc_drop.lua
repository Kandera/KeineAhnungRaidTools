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
