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

-- The cut ignores the window filters; "everything" keeps respecting them.
--
-- This is the one rule worth stating twice, because the alternative fails silently. Filter to one
-- player, press the cut, and a filter-respecting cut marks only that player's awards -- the rest of
-- the same evening stays unmarked and comes round again next time, while the player believes the
-- night is done. "Everything" is a VIEW and may follow the filters; the cut is BOOKKEEPING and must
-- not depend on how a filter happens to be set.
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000003, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-1", epoch = 1, exported = false },
            { time = 1785000002, item = GLOVES, winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", id = "cut-2", epoch = 1, exported = false },
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-3", epoch = 1, exported = true },
            { time = 1785000000, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-4", epoch = 1 },   -- legacy: no field at all
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
    end)

    T.eq(#As(LH.UnexportedEntries), 2, "only the two entries at exported == false count as new")
    T.eq(#As(LH.FilteredEntries), 4, "everything shows all four")

    -- Now filter to one player and ask again.
    As(function() LH.filters.playerIds = { ["K-A"] = true } end)
    T.eq(#As(LH.UnexportedEntries), 2,
        "the cut still covers both players' new awards while a player filter is active")
    T.eq(#As(LH.FilteredEntries), 3, "everything follows the filter, as it always has")
    As(function() LH.filters.playerIds = nil end)
end

-- A legacy entry counts as exported, an explicit false does not -----------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mig-1", epoch = 1 },                   -- no field
            { time = 1785000000, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mig-2", epoch = 1, exported = false },
        }
    end)
    local new = As(LH.UnexportedEntries)
    T.eq(#new, 1, "an entry written before this version counts as already exported")
    T.eq(new[1].id, "mig-2", "and the one that is genuinely new is the one with exported == false")
end

-- Marking sets the mark and says so ----------------------------------------------------------------
do
    local lines = {}
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mark-1", epoch = 1, exported = false },
            { time = 1785000000, item = GLOVES, winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", id = "mark-2", epoch = 1, exported = false },
        }
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.MarkExported(LH.UnexportedEntries())
        me.env.print = realPrint
    end)

    T.eq(me.env.KART_LootHistory[1].exported, true, "the first award is marked")
    T.eq(me.env.KART_LootHistory[2].exported, true, "and so is the second")
    T.eq(#As(LH.UnexportedEntries), 0, "nothing is left new afterwards")
    T.eq(#lines, 1, "marking prints exactly one line")
    T.truthy(lines[1]:find("2", 1, true), "and the line names how many were marked")
end

-- The JSON is byte-identical to what it was ---------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1786090821, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "json-1", epoch = 3, exported = false },
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
    end)
    local json = As(LH.BuildRCLootCouncilJSON)

    T.eq(json:find("exported", 1, true), nil, "the mark does not leak into the export")
    T.eq(json:find("epoch", 1, true), nil, "and neither does the epoch")
    T.truthy(json:find('"player":"Alric"', 1, true), "the export still says what it always said")
end

-- Passing an explicit list overrides the filters ------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "pick-1", epoch = 1, exported = false },
            { time = 1785000000, item = "item:1234", winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", class = "MAGE", id = "pick-2", epoch = 1, exported = true },
        }
        LH.filters = { player = nil, playerIds = { ["K-S"] = true }, reason = nil, search = "" }
    end)
    local json = As(function() return LH.BuildRCLootCouncilJSON(LH.UnexportedEntries()) end)

    T.truthy(json:find('"player":"Alric"', 1, true),
        "an explicit list is exported whole, regardless of the window filter")
    T.eq(json:find('"player":"Sinja"', 1, true), nil, "and nothing outside that list appears")
    As(function() LH.filters.playerIds = nil end)
end
