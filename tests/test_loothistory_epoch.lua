-- Stable award identity. Every client that logs the same award must store the same id, because the
-- id is what "the raid agrees this happened once" is defined over (C7) and what the union merge,
-- the export cut and the Companion archive all dedup on. rollID cannot do that job: it is a small
-- Blizzard number that comes round again every week.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- Put one item on the table and award it, using only what lc_fixture.lua already offers -- the
-- fixture belongs to neither session and must not grow while B139 is working in this tree.
local function Award(sim, assigner, rollID, itemID, winner, reason)
    F.Drop(sim, rollID, itemID)
    RaidSim.As(assigner, function()
        assigner.KART.LC.Trade.AssignWinner(rollID, winner.guid, reason, nil)
    end)
    RaidSim.Drain(sim, 10)
end

-- LH.NewAwardID shape -------------------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    local a, b
    RaidSim.As(lm, function()
        a, b = lm.KART.LH.NewAwardID(), lm.KART.LH.NewAwardID()
    end)
    T.truthy(a:match("^%d+%-%x+$"), "an award id is <seconds>-<hex>")
    T.eq(a:find(":", 1, true), nil, "an award id carries no colon, so it is safe as a wire field")
    T.truthy(a ~= b, "two ids minted in the same second still differ")
end

-- The same award gets the same id on every client ---------------------------------------------
do
    local sim, lm, council, raider = F.NewRaid()
    Award(sim, lm, 60, F.GLOVES, raider, "BIS")

    local idLM      = lm.env.KART_LootHistory[1] and lm.env.KART_LootHistory[1].id
    local idCouncil = council.env.KART_LootHistory[1] and council.env.KART_LootHistory[1].id
    local idRaider  = raider.env.KART_LootHistory[1] and raider.env.KART_LootHistory[1].id

    T.truthy(idLM, "the assigner stores an id")
    T.eq(idCouncil, idLM, "the council member stores the assigner's id, not one of its own")
    T.eq(idRaider, idLM, "the raider stores the assigner's id too")
end

-- A locally logged award without a wire id still gets one --------------------------------------
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {}
        lm.KART.LH.LogHistory("item:1234", "Alric", "BIS", "MAGE", nil, 70, "Player-1-A", nil)
    end)
    T.truthy(lm.env.KART_LootHistory[1].id, "an award logged with no id is given one")
end

-- The epoch. A wipe is not an empty table, it is a number going up -- and it has to reach a client
-- that was not there when it was drawn (C3), including one that comes back a week later.
--
-- A counter and not a timestamp on purpose: entries carry time(), the LOCAL system clock of whoever
-- logged them, not GetServerTime(). Comparing those across clients against a wipe line would keep or
-- eat entries whenever two machines are a few minutes apart. A counter does not drift.

-- A higher epoch from the loot owner wipes what is below it ------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 3
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 3 },
        }
        raider.KART.LH.AdoptEpoch(4, lm.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 4, "the higher epoch is adopted")
    T.eq(#raider.env.KART_LootHistory, 0, "and everything below it is gone")
end

-- A higher epoch from someone who is not the loot owner changes nothing ------------------------
do
    local _, _, council, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 3
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 3 },
        }
        raider.KART.LH.AdoptEpoch(4, council.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 3, "a council member cannot wipe the raid")
    T.eq(#raider.env.KART_LootHistory, 1, "and the entry survives")
end

-- A lower epoch changes nothing ----------------------------------------------------------------
do
    local _, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistoryEpoch = 5
        raider.env.KART_LootHistory = {}
        raider.KART.LH.AdoptEpoch(2, lm.guid)
    end)
    T.eq(raider.env.KART_LootHistoryEpoch, 5, "an older epoch does not pull us backwards")
end

-- The absentee who comes back a week later ------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = "item:1", winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", id = "1-aaa", epoch = 1 },
        }
    end)
    -- RaidSim.Join takes a member def and hands back a brand-new client (fresh env, nothing
    -- persisted -- see RaidSim.Join's own comment), so the old `raider` reference is a corpse the
    -- moment it rejoins; the reassignment is what makes the assertions below look at the client that
    -- actually came back, not the one that left.
    local member = raider.member
    RaidSim.Leave(sim, raider.name)
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    KARTTEST.AdvanceTime(7 * 24 * 60 * 60)
    raider = RaidSim.Join(sim, member)
    RaidSim.EnterWorld(sim, raider.name)
    RaidSim.Drain(sim, 90)

    T.eq(raider.env.KART_LootHistoryEpoch, lm.env.KART_LootHistoryEpoch,
        "the returning raider ends on the raid's epoch")
    T.eq(#raider.env.KART_LootHistory, 0,
        "and does not keep the history the raid wiped while he was away")
end

-- Clearing is the loot owner's call, and only in a group -----------------------------------------
do
    local _, _, council = F.NewRaid()
    local before
    RaidSim.As(council, function()
        before = council.env.KART_LootHistoryEpoch
        council.env.KART_LootHistory = { { time = time(), id = "1-ccc", epoch = before } }
        council.KART.LH.ClearHistory()
    end)
    T.eq(council.env.KART_LootHistoryEpoch, before, "a council member's clear does not bump the epoch")
    T.eq(#council.env.KART_LootHistory, 1, "and does not empty the log")
end

-- The one-time purge on update -------------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = nil
        lm.env.KART_LootHistory = { { time = time(), item = "item:1", winner = "Alric" } }
        KARTTEST.FireEvent("ADDON_LOADED", "KeineAhnungRaidTools")
    end)
    T.eq(lm.env.KART_LootHistoryEpoch, 1, "a client with no epoch starts at 1")
    T.eq(#lm.env.KART_LootHistory, 0, "and its pre-id history is purged")
end

-- The genuinely first-ever load: no epoch AND no history table at all --------------------------
-- RaidSim.Boot always pre-seeds KART_LootHistory to a table, which a real brand-new install does
-- not have -- Core.lua's own `KART_LootHistory = KART_LootHistory or {}` is what creates it there,
-- and LootHistory.lua's ADDON_LOADED frame can register (and dispatch) before Core.lua's, per the
-- .toc's file order. LH.PurgeIfNoEpoch must not assume some other file already made the table.
do
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistoryEpoch = nil
        lm.env.KART_LootHistory = nil
        lm.KART.LH.PurgeIfNoEpoch()
    end)
    T.eq(lm.env.KART_LootHistoryEpoch, 1, "a client with no history table at all still starts at 1")
    T.eq(#lm.env.KART_LootHistory, 0, "and ends up with an empty table, not a crash")
end

-- A reload changes nothing (C8) --------------------------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    Award(sim, lm, 61, F.GLOVES, raider, "BIS")
    local idBefore    = raider.env.KART_LootHistory[1].id
    local epochBefore = raider.env.KART_LootHistoryEpoch
    RaidSim.Reload(sim, raider.name)
    T.eq(raider.env.KART_LootHistory[1].id, idBefore, "the award id survives a reload")
    T.eq(raider.env.KART_LootHistoryEpoch, epochBefore, "the epoch survives a reload")
end
