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
