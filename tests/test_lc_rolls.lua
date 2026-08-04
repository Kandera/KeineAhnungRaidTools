-- Who ends up with a number in the roll column, and who does not.
--
-- B121, and the Manifest's C13. The opt-in 1-100 roll was cast in LC.OnStartLootRoll and nowhere
-- else, and that function only ever runs on a client Blizzard raised its own roll on. Everybody
-- else -- dead, released, out of range, ineligible -- was permanently absent from the tie-breaker the
-- council reads, and an absent number looks exactly like a low one on that panel.
--
-- Reported twice from raids ("Rolls werden WIEDER nicht für jeden Char angezeigt"), which is why the
-- Manifest now carries it as an item of its own rather than as part of C5.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local function RollsOn(sim)
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function() c.env.KART_Settings.lcRollsEnabled = true end)
    end
end

-- A client Blizzard never asked to roll ---------------------------------------------------------
do
    local sim, lm, council = F.NewRaid()
    RollsOn(sim)
    RaidSim.As(lm, function() lm.KART.LC.ApplyOwnConfig() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    local absent = sim.byName.Sinja
    F.Drop(sim, 70, F.GLOVES, { bop = true, noRollFor = { Sinja = true } })
    -- Past the window a drop is collected in: the numbers travel with the announcement.
    KARTTEST.AdvanceTime(1)

    local rolls = council.KART.LC.rolls[70] or {}
    T.truthy(rolls[absent.guid],
        "a raider Blizzard gave no roll window to still lands in the council's roll column")
    T.truthy(rolls[lm.guid], "and so does everybody who did get one")

    -- Every client agrees on that raider's number, or two council members score their tie-break
    -- differently and the panel that decides disagrees with the panel next to it.
    for _, c in ipairs(sim.clients) do
        if c ~= absent then
            T.eq((c.KART.LC.rolls[70] or {})[absent.guid], rolls[absent.guid],
                c.name .. " sees the same number for them")
        end
    end
end

-- Never twice ---------------------------------------------------------------------------------------
-- The table is drawn once, by the ANNOUNCER (LC.DrawRollTable), and HandleStart never draws -- so the
-- risk this guards is on the announcer's own client, not on a raider receiving LC_START a second time.
-- Blizzard re-raises START_LOOT_ROLL for a roll still in progress, which reaches OnStartLootRoll and
-- then LC.DrawRollTable again on the same client; a second draw must not replace the numbers the raid
-- has already been shown.
do
    local sim, lm = F.NewRaid()
    RollsOn(sim)
    RaidSim.As(lm, function() lm.KART.LC.ApplyOwnConfig() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 71, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(1)
    local first = lm.KART.LC.rolls[71]
    T.truthy(first and next(first), "the table was drawn")

    -- Blizzard re-raising START_LOOT_ROLL for the SAME rollID and item, still running.
    F.Drop(sim, 71, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(1)
    T.deep_eq(lm.KART.LC.rolls[71], first, "and a second announcement does not redraw the table")
    -- The numbers travel inside the announcement now, so a re-raised roll necessarily carries them
    -- again. What must not happen is that they come back DIFFERENT: byte-identical messages are the
    -- proof that no second draw reached the wire.
    local sent = RaidSim.Sent(sim, "LC_DROP:")
    T.eq(#sent, 2, "the re-raised roll is announced again")
    T.eq(sent[2].msg, sent[1].msg, "nor broadcast it a second time")
end

-- ...but a rollID reused for a DIFFERENT item must draw a NEW table -----------------------------------
-- The other half of the same rule: PurgeStaleRoll has already emptied the table for a genuinely
-- different drop under this rollID by the time LC.DrawRollTable runs, so the guard above must not
-- catch this case too.
do
    local sim, lm = F.NewRaid()
    RollsOn(sim)
    RaidSim.As(lm, function() lm.KART.LC.ApplyOwnConfig() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 73, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(1)
    local first = lm.KART.LC.rolls[73]
    T.truthy(first and next(first), "the table was drawn")

    F.Drop(sim, 73, F.WEAPON, { bop = true })
    KARTTEST.AdvanceTime(1)
    local second = lm.KART.LC.rolls[73]
    T.truthy(second and next(second), "a fresh table was drawn for the new item")
    local sent = RaidSim.Sent(sim, "LC_DROP:")
    T.eq(#sent, 2, "and it was broadcast, once per drop")
    T.truthy(sent[1].msg ~= sent[2].msg, "with the new item's own numbers, not the previous item's")
end

-- Rolls switched off stay off -----------------------------------------------------------------------
-- The setting is the raid's, not the raider's (LC.GetRollsEnabled), and the new call site must not
-- become a way around it.
do
    local sim, lm, council = F.NewRaid()
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function() c.env.KART_Settings.lcRollsEnabled = false end)
    end
    RaidSim.As(lm, function() lm.KART.LC.ApplyOwnConfig() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 72, F.GLOVES, { bop = true, noRollFor = { Sinja = true } })
    KARTTEST.AdvanceTime(1)
    T.eq(next(council.KART.LC.rolls[72] or {}), nil, "nobody rolls when the raid has rolls turned off")
end
