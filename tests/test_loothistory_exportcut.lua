-- The export cut. WoWUtils does not dedup on import, so importing one raid and then the next lands
-- the first raid's drops twice. The cut is per award and keyed on the stable id, NOT on a timestamp:
-- the catch-up sync backfills entries OLDER than everything already stored, and a timestamp cut would
-- drop every one of those through the gap and never export them at all.
--
-- Three states, and the difference is load-bearing:
--   exported == false  -> new, has not been exported
--   exported == true   -> exported
--   exported == nil    -> written by a build before this one; counts as exported
--
-- Writing the rule as `not e.exported` would collapse nil into new and invert the migration, so the
-- checks below are written against the exact values rather than against truthiness.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim = F.NewRaid()
local me = sim.byName.Bramor
local KART = me.KART
local LH = KART.LH

local function As(fn, ...) return RaidSim.As(me, fn, ...) end
local GLOVES = KARTTEST.items[F.GLOVES].link

-- A newly logged award is new, not exported -------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {}
        LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 90, "Player-1-A", "id-1", 1)
    end)
    local e = me.env.KART_LootHistory[1]
    T.eq(e.exported, false, "a freshly logged award is stamped exported = false, not left nil")
end

-- The mark is personal and must not travel. One player's export bookkeeping says nothing about
-- anybody else's, and an entry arriving through the catch-up is new to whoever receives it.
do
    local sim2, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 91, id = "wire-1", epoch = 1,
              exported = true },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim2, 30)

    T.eq(#raider.env.KART_LootHistory, 1, "the award reaches the peer")
    T.eq(raider.env.KART_LootHistory[1].exported, nil,
        "but the sender's export mark does not travel with it")
end

-- C8, "a reload changes nothing". The mark lives on the entry and the history is a SavedVariable, so
-- this should hold by construction -- which is exactly why it is worth pinning, since nothing else
-- would notice if the entry were ever rebuilt on load instead of restored.
do
    local sim3, _, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 92, id = "reload-1", epoch = 1,
              exported = true },
        }
    end)
    raider = RaidSim.Reload(sim3, raider.name)
    T.eq(raider.env.KART_LootHistory[1].exported, true, "the export mark survives a reload")
end
