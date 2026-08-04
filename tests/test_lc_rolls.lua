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
-- The table is drawn once, by the announcer, and HandleStart never draws (see LC.DrawRollTable) -- so
-- a late duplicate of the announcement must not disturb a table the raid has already been shown.
do
    local sim, lm, council, raider = F.NewRaid()
    RollsOn(sim)
    RaidSim.As(lm, function() lm.KART.LC.ApplyOwnConfig() lm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 71, F.GLOVES, { bop = true })
    local first = (council.KART.LC.rolls[71] or {})[raider.guid]
    T.truthy(first, "the raider rolled")

    -- The announcement again, as a late duplicate would arrive.
    RaidSim.As(raider, function()
        raider.KART.LC.HandleStart("71:20:" .. F.GLOVES, lm.guid)
    end)
    KARTTEST.AdvanceTime(0)
    T.eq((council.KART.LC.rolls[71] or {})[raider.guid], first,
        "and a second announcement does not make them roll again")
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
    T.eq(next(council.KART.LC.rolls[72] or {}), nil, "nobody rolls when the raid has rolls turned off")
end
