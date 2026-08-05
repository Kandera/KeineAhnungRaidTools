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

-- Two copies owed, one copy actually handed over ------------------------------------------------
-- The count in LC.tradeWindowItemStrings is not bookkeeping for its own sake: two pending entries
-- that share an item string are indistinguishable to everything downstream, so a completed trade
-- carrying ONE copy must confirm exactly one of them. Confirming both is the silent loss B60 is
-- about -- the raider is handed one item, the lootmaster's list says both are dealt with, and the
-- second is never traded and never missed by anybody.
--
-- The bag half cannot cover this: a copy is still sitting there, so confirmedByBags is false for
-- both entries and the count is the only thing deciding. A mutation run walked through it (B116).
do
    local _, lm, alric = TradeWith(function(a)
        return {
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 },
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 71 },
        }
    end, { [0] = { GLOVES } })   -- one physical copy, so only one can go into the window
    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "the one copy there is goes into the window")
    T.eq(KARTTEST.tradePlayerItems[2], nil, "and the second entry finds nothing to place")

    RaidSim.As(lm, function()
        lm.KART.LC.Trade.OnTradeAcceptUpdate()
        lm.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE)
        lm.KART.LC.Trade.OnTradeClosed()
    end)

    T.eq(#lm.KART.LC.pendingTrades, 1, "one of the two copies is still owed after the trade")
    T.eq(lm.KART.LC.pendingTrades[1].winnerKey, alric.guid, "and it is still owed to the same winner")
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

-- Closing the trade: what counts as "handed over" ---------------------------------------------------
-- B60's damage runs through this check. An obligation is cleared when the item demonstrably left --
-- either the trade window carried it, or it is no longer in our bags. The second half is what makes
-- "the lootmaster never had it" look like "the lootmaster already traded it": both are "not in my
-- bags". The two conditions have to hold TOGETHER -- a real link that IS still in the bags is an
-- obligation that has not been met, and clearing it there loses the item silently.
do
    local _, lm, alric = TradeWith(function(a)
        return { { itemLink = GLOVES, winnerKey = a.guid, rollID = 71 } }
    end, { [0] = { GLOVES } })

    -- The trade is closed without the item ever going across: nothing was put in the window on the
    -- partner's side, and the item is right there in the bags where it started.
    KARTTEST.tradePlayerItems = {}
    RaidSim.As(lm, function() lm.KART.LC.Trade.OnTradeClosed() end)

    T.eq(#lm.KART.LC.pendingTrades, 1,
        "an item still in our bags is still owed after a trade that carried nothing")
    T.eq(lm.KART.LC.pendingTrades[1].winnerKey, alric.guid, "to the same person")
end

-- The slot the client has not acknowledged yet (B122) ------------------------------------------------
-- Everything above runs against a harness that fills a trade slot the instant it is clicked. The live
-- client fills it when the SERVER answers, and between those two moments GetTradePlayerItemLink still
-- says the slot is empty. That gap is what put two items owed to one raider into one slot on a live
-- client: the first was swapped straight back out, the lootmaster's list showed both as dealt with,
-- and the raider was handed one item. Reported 2026-08-03, seen failing and succeeding in one evening,
-- which is what a race looks like from outside.
do
    KARTTEST.tradeSlotLag = true
    TradeWith(function(a)
        return {
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 },
            { itemLink = WEAPON, winnerKey = a.guid, rollID = 71 },
        }
    end, { [0] = { GLOVES, WEAPON } })
    KARTTEST.AdvanceTime(0) -- the server answers
    KARTTEST.tradeSlotLag = false

    T.eq(KARTTEST.tradePlayerItems[1], GLOVES, "the first item is still in the first slot")
    T.eq(KARTTEST.tradePlayerItems[2], WEAPON,
        "and the second took the next one, even though the client had not shown the first yet")
end

-- Two variants of one item, telling them apart (B127) ------------------------------------------------
-- A boss dropping the same slot twice at two levels is an ordinary evening, and the two links differ
-- only inside the bonus list -- which is where the defect lived: KAUtil.GetItemString matched
-- [-0-9:], a class with no comma in it, so it stopped at the first comma of a live Midnight bonus
-- list and returned a PREFIX carrying exactly one bonus id. Two variants that agree on their FIRST
-- bonus id compared EQUAL, and everything the trade path does is that comparison.
--
-- Built from the fixture's own link shape (see KARTTEST.AddItem) rather than an invented one: the
-- comma is the whole point, and a skeleton link without one cannot show this at all.
local BONUS_A = "11946,10390,12043,10255,1540,10879,11996"
local BONUS_B = "11946,10390,12043,10255,1540,10879,11997" -- same FIRST bonus id, different last one
local function Variant(bonus)
    return "|cffa335ee|Hitem:" .. F.GLOVES .. "::::::::80:268::14:8:" .. bonus ..
           ":::::|h[Ezzorak's Gloombind]|h|r"
end
local VARIANT_A, VARIANT_B = Variant(BONUS_A), Variant(BONUS_B)

-- The auto-fill hands over the variant that was actually won.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.tradePlayerItems = {}
    KARTTEST.tradeTargetItems = {}
    KARTTEST.cursorItem = nil
    -- The other variant sits in an EARLIER bag slot, so a comparison that cannot tell them apart
    -- finds it first and picks it up.
    KARTTEST.bags = { [0] = { VARIANT_B, VARIANT_A } }
    KARTTEST.tradePartnerUnit = alric.unit
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = { { itemLink = VARIANT_A, winnerKey = alric.guid, rollID = 72 } }
        lm.KART.LC.Trade.OnTradeShow()
    end)
    T.eq(KARTTEST.tradePlayerItems[1], VARIANT_A,
        "the variant that was won is placed in the trade window, not the other one")
end

-- ...and handing the other one over does NOT tick the obligation off.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    -- The owed variant is still in our bags, so the "no longer in my bags, so it must have gone"
    -- half of the check cannot answer this on its own -- the trade window has to.
    KARTTEST.bags = { [0] = { VARIANT_A } }
    KARTTEST.tradePlayerItems = { VARIANT_B } -- the wrong variant, put there by hand
    KARTTEST.tradeTargetItems = {}
    KARTTEST.tradePartnerUnit = alric.unit
    -- An occupied cursor makes Trade.OnTradeShow's auto-fill bail (it will not swap our item into
    -- whatever the player is mid-drag of). Kept occupied on purpose: letting the auto-fill also
    -- place the owed variant would answer the question this asks.
    KARTTEST.cursorItem = "|cffffffff|Hitem:6948::::::::80:::::|h[Hearthstone]|h|r"
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = { { itemLink = VARIANT_A, winnerKey = alric.guid, rollID = 73 } }
        lm.KART.LC.Trade.OnTradeShow()
        lm.KART.LC.Trade.OnTradeAcceptUpdate()
        lm.KART.LC.Trade.OnTradeInfoMessage(LE_GAME_ERR_TRADE_COMPLETE)
        lm.KART.LC.Trade.OnTradeClosed()
    end)
    KARTTEST.cursorItem = nil
    KARTTEST.tradePlayerItems = {}
    T.eq(#lm.KART.LC.pendingTrades, 1,
        "trading the other variant away leaves the obligation for the won one standing")
end

-- The duplicate ordinal counts real duplicates, not variants ------------------------------------------
-- " (1/2)" on both rows tells the lootmaster the two rolls are the SAME physical item. Two variants
-- are two different items and must not be labelled as one.
do
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.KART.LC.rollItems = { [74] = VARIANT_A, [75] = VARIANT_B }
        T.eq(lm.KART.LC.Trade.GetDuplicateOrdinal(74), "",
            "two variants of one item are not numbered as duplicates of each other")
    end)
    T.truthy(sim ~= nil)
end
