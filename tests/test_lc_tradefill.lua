-- Opening a trade with somebody you owe items to: the addon puts them in the trade window for you.
--
-- This is the last thing that happens to a piece of loot, and the two lines that do it -- pick the
-- item up out of the bag, drop it into a trade slot -- had never run. GetCursorInfo and
-- ClickTradeButton were both missing from the harness entirely, so the branch around them was
-- unreachable and everything below is new ground.
--
-- The harness fills a trade slot the INSTANT ClickTradeButton is called, which is the reading most
-- favourable to the addon: the real client only shows the item once the server answers. Nothing
-- here therefore depends on that timing.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link
local WEAPON = KARTTEST.items[F.WEAPON].link

-- Sets up a lootmaster owing `entries` to Alric, with those items in the bags, and opens the trade.
local function TradeWith(entries, bags)
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.tradePlayerItems = {}
    KARTTEST.tradeTargetItems = {}
    KARTTEST.cursorItem = nil
    KARTTEST.bags = bags
    -- "npc" is the trade partner during TRADE_SHOW; the addon resolves it to a key from there.
    KARTTEST.tradePartnerUnit = alric.unit
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = entries(alric)
        lm.KART.LC.Trade.OnTradeShow()
    end)
    return sim, lm, alric
end

-- One item ------------------------------------------------------------------------------------------
do
    local _, _, alric = TradeWith(function(a)
        return { { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 } }
    end, { [0] = { GLOVES } })
    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "the item owed is placed in the first trade slot")
    T.eq(KARTTEST.cursorItem, nil, "and the cursor is left empty rather than still holding it")
    T.truthy(alric ~= nil)
end

-- Two different items to the same person --------------------------------------------------------
-- A raider winning twice off one boss is an ordinary evening, and both have to end up in the window.
-- Two items landing in ONE slot would not be a harmless duplicate: the second click swaps the first
-- back out, and the raider is handed one item while the lootmaster's list shows both as dealt with.
-- The free slot is found by asking GetTradePlayerItemLink, so this holds as long as the client has
-- registered the previous click by then -- which the harness grants it (see the file header).
do
    TradeWith(function(a)
        return {
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 },
            { itemLink = WEAPON, winnerKey = a.guid, rollID = 71 },
        }
    end, { [0] = { GLOVES, WEAPON } })
    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "the first item takes the first slot")
    T.eq(KARTTEST.tradePlayerItems[2], WEAPON, "and the second takes the next one, not the same one")
end

-- Two copies of the same item -------------------------------------------------------------------
-- The case usedSlots was written for: both entries resolve to the first bag slot holding that link
-- unless the placed one is remembered.
do
    TradeWith(function(a)
        return {
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 },
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 71 },
        }
    end, { [0] = { GLOVES, GLOVES } })
    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "the first copy is placed")
    T.eq(KARTTEST.tradePlayerItems[2], GLOVES, "and the second copy comes from the other bag slot")
end

-- Somebody else's items are left alone ----------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    KARTTEST.tradePlayerItems = {}
    KARTTEST.cursorItem = nil
    KARTTEST.bags = { [0] = { GLOVES, WEAPON } }
    KARTTEST.tradePartnerUnit = alric.unit
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = {
            { itemLink = WEAPON, winnerKey = sinja.guid, rollID = 71 },
            { itemLink = GLOVES, winnerKey = alric.guid, rollID = 70 },
        }
        lm.KART.LC.Trade.OnTradeShow()
    end)
    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "only what this partner is owed goes in")
    T.eq(KARTTEST.tradePlayerItems[2], nil, "the item owed to somebody else stays in the bag")
end

-- A cursor that is already carrying something ----------------------------------------------------
-- Documented behaviour: picking our item up now would swap it into whatever the player was
-- mid-drag of, so nothing is placed at all.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.tradePlayerItems = {}
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.tradePartnerUnit = alric.unit
    KARTTEST.cursorItem = WEAPON
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = { { itemLink = GLOVES, winnerKey = alric.guid, rollID = 70 } }
        lm.KART.LC.Trade.OnTradeShow()
    end)
    T.eq(KARTTEST.tradePlayerItems[1], nil, "nothing is placed while the cursor is busy")
    T.eq(KARTTEST.cursorItem, WEAPON, "and what the player was carrying is still on it")
    KARTTEST.cursorItem = nil
end

-- Slots the player filled themselves --------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.tradePartnerUnit = alric.unit
    KARTTEST.cursorItem = nil
    KARTTEST.tradePlayerItems = { [1] = WEAPON } -- the lootmaster put something in slot 1 by hand
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = { { itemLink = GLOVES, winnerKey = alric.guid, rollID = 70 } }
        lm.KART.LC.Trade.OnTradeShow()
    end)
    T.eq(KARTTEST.tradePlayerItems[1], WEAPON, "an occupied slot is not overwritten")
    T.eq(KARTTEST.tradePlayerItems[2], GLOVES, "the owed item takes the next free one")
end
