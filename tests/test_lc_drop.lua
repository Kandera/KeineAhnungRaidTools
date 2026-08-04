-- One message per boss.
--
-- A boss drops several items at once and KART used to announce each on its own: six items in a
-- 25-man raid were six LC_START plus six roll tables, and three quarters of that was the same 25
-- identity keys repeated six times because the messages knew nothing of each other. This collects
-- what falls inside half a second and names the participants once.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- Every announcement on the wire, however many chunks it took.
--
-- RaidSim.Sent matches the raw bytes handed to C_ChatInfo.SendAddonMessage, and this message is the
-- first in the addon that routinely exceeds 255 bytes: three items in a five-man fixture is already
-- two chunks, and the transport stamps AceComm's own control byte in front of each. So a prefix match
-- on the token alone finds NOTHING for a batch that had to be split -- which would read as "nothing
-- was sent" rather than as "it was sent in two pieces". One message is one unsplit send or one FIRST
-- chunk ("\001"); the continuation chunks carry "\002"/"\003" and are deliberately not counted.
local function Announced(sim)
    local out = RaidSim.Sent(sim, "LC_DROP:")
    for _, e in ipairs(RaidSim.Sent(sim, "\001LC_DROP:")) do out[#out + 1] = e end
    return out
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
    RaidSim.Join(sim, { name = "Torvi", realm = "TarrenMill", guid = "Player-1096-0A1B2C42",
                        class = "MAGE", locale = "enUS" })
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

-- Rolls switched off raid-wide ----------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
    end)
    KARTTEST.AdvanceTime(0.5)
    F.Drop(sim, 958, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.truthy(council.KART.LC.rollItems[958] ~= nil, "the item arrives with rolls switched off")
    T.eq(next(council.KART.LC.rolls[958] or {}), nil, "and carries no numbers")
end
