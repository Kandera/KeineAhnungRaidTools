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

-- Neither of the two old confirmations fires, and the item is still ticked off ---------------------
-- Reported 2026-08-05: "nach auto trade wird nicht abgehakt", and separately "wenn ein item 2 spieler
-- gewinnt wird 0/2 abgehakt". Both are the same hole. The trade-complete signal is deliberately NOT
-- sent here -- we cannot prove every client raises it -- and the bag scan that stands in for it runs
-- inside TRADE_CLOSED, before the server has applied the swap, so it still finds the item and
-- confirms nothing. What is left is counting: one copy fewer in the bags is one copy handed over.
do
    local _, lm = TradeWith(function(a)
        return { { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 } }
    end, { [0] = { GLOVES } })

    RaidSim.As(lm, function()
        lm.KART.LC.Trade.OnTradeAcceptUpdate()
        -- No OnTradeInfoMessage: this is the client that never reports LE_GAME_ERR_TRADE_COMPLETE.
        lm.KART.LC.Trade.OnTradeClosed()
    end)
    T.eq(#lm.KART.LC.pendingTrades, 1,
        "nothing is confirmed while the bags still show the item -- the server has not applied it yet")

    KARTTEST.bags = { [0] = {} } -- the swap lands
    KARTTEST.AdvanceTime(2)
    T.eq(#lm.KART.LC.pendingTrades, 0, "and the recount a moment later ticks it off")
end

do
    -- The duplicate case, which is where a presence check cannot help at all: two copies owed to the
    -- same winner, one handed over. Exactly one entry may clear -- confirming both loses an item
    -- nobody will miss, clearing neither is the "0 of 2" the lootmaster saw.
    local _, lm, alric = TradeWith(function(a)
        return {
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 },
            { itemLink = GLOVES, winnerKey = a.guid, rollID = 71 },
        }
    end, { [0] = { GLOVES, GLOVES } })

    RaidSim.As(lm, function()
        lm.KART.LC.Trade.OnTradeAcceptUpdate()
        lm.KART.LC.Trade.OnTradeClosed()
    end)

    KARTTEST.bags = { [0] = { GLOVES } } -- one copy left
    KARTTEST.AdvanceTime(2)
    T.eq(#lm.KART.LC.pendingTrades, 1, "one of the two copies is confirmed, not both and not neither")
    T.eq(lm.KART.LC.pendingTrades[1].winnerKey, alric.guid, "and the other is still owed to the winner")
end

do
    -- ...and a trade that was cancelled changes nothing, because nothing left the bags.
    local _, lm = TradeWith(function(a)
        return { { itemLink = GLOVES, winnerKey = a.guid, rollID = 70 } }
    end, { [0] = { GLOVES } })

    RaidSim.As(lm, function()
        lm.KART.LC.Trade.OnTradeAcceptUpdate()
        lm.KART.LC.Trade.OnTradeClosed()
    end)
    KARTTEST.AdvanceTime(2)
    T.eq(#lm.KART.LC.pendingTrades, 1, "a cancelled trade leaves the obligation standing")
end

-- The BoP trade clock: what it says, and when ------------------------------------------------------

local TRADE_WINDOW = 4 * 60 * 60

-- Returns everything printed while fn ran.
local function Capture(fn)
    local lines = {}
    local realPrint = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end

-- A lootmaster owing one item, with the clock wound forward to `elapsed` seconds since it dropped.
local function OwingSince(elapsed)
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.bags = { [0] = { GLOVES } }
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = {
            { itemLink = GLOVES, winnerKey = alric.guid, rollID = 90, lootedAt = time() - elapsed },
        }
    end)
    return sim, lm
end

-- Mid-pull, the chat line waits (B3) --------------------------------------------------------------
-- The 5-minute ticker lands whenever it lands, and a raid spends most of its evening in a pull. A
-- trade warning printed there is read after the fight if at all, and it arrives on top of whatever
-- the player is actually doing.
do
    local _, lm = OwingSince(TRADE_WINDOW - 600) -- ten minutes of trade window left
    KARTTEST.inCombat = true
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(out, "", "nothing is said while the raid is in combat")

    KARTTEST.inCombat = false
    local after = Capture(function()
        RaidSim.As(lm, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    T.truthy(after:find("Gloombind", 1, true),
        "and the warning arrives once the pull is over: " .. after)
end

-- ...while the obligation itself still dies on schedule -------------------------------------------
-- Only the PRINT waits. An entry past the window is a lie whether or not anybody is in combat, and
-- leaving it in the list until the fight ends is exactly the "row that looks live but is dead" B47
-- removed.
do
    local _, lm = OwingSince(TRADE_WINDOW + 60)
    KARTTEST.inCombat = true
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(#lm.KART.LC.pendingTrades, 0, "the dead obligation is dropped mid-pull like any other")
    T.eq(out, "", "but the line about it waits")

    KARTTEST.inCombat = false
    local after = Capture(function()
        RaidSim.As(lm, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    T.truthy(after:find("Gloombind", 1, true), "and is said afterwards: " .. after)
end

-- The item nobody has decided yet (B1) --------------------------------------------------------------
-- Every warning above needs an AWARD to exist first: pendingTrades and owedToMe are both built when a
-- winner is named. An item the council never got round to -- the lootmaster ported out, the pull
-- started, the tab sat there -- has a live four-hour clock and nothing watching it, so it dies in
-- silence and the raid finds out never.

-- Winds the drop's loot stamp back on this client, as if the boss had died `elapsed` seconds ago.
local function StampedSince(client, rollID, elapsed)
    RaidSim.As(client, function() client.KART.LC.rollLootedAt[rollID] = time() - elapsed end)
end

do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 91, F.GLOVES)
    T.truthy(lm.KART.LC.tradeTimeoutTicker ~= nil,
        "holding an undecided item is enough to run the clock, with nothing yet owed to anybody")

    StampedSince(lm, 91, TRADE_WINDOW - 600) -- ten minutes of trade window left
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.truthy(out:find("Gloombind", 1, true),
        "the holder is warned about an item the council never decided: " .. out)

    local again = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(again, "", "and told once, not every five minutes")
end

do
    -- A DECIDED item is somebody's pending trade and is warned about as one -- naming it twice would
    -- put two lines about the same item on the same screen.
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 92, F.GLOVES)
    local alric = sim.byName.Alric
    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(92, alric.guid, "BIS", nil) end)
    KARTTEST.AdvanceTime(0)

    StampedSince(lm, 92, TRADE_WINDOW - 600)
    RaidSim.As(lm, function() lm.KART.LC.pendingTrades[1].lootedAt = time() - (TRADE_WINDOW - 600) end)
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    local mentions = select(2, out:gsub("Gloombind", ""))
    T.eq(mentions, 1, "one line about a decided item, not two: " .. out)
end

do
    -- ...and the warning belongs to whoever is holding the item. Every client in the raid stamps the
    -- same clock (the winner's own reminder is measured from it), so a raider who cannot hand
    -- anything over would otherwise be nagged about every drop of the evening.
    local sim = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 93, F.GLOVES)
    StampedSince(alric, 93, TRADE_WINDOW - 600)
    local out = Capture(function() RaidSim.As(alric, alric.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(out, "", "a plain raider hears nothing about an item they are not holding")
end

-- Who on this list is reachable right now (B2) ------------------------------------------------------
-- The lootmaster works the reminder list by walking up to people, and range was discoverable only by
-- clicking a row and being told no. The colour answers the question the list is actually asked.
-- Plain white for a row nothing has coloured yet, so an uncoloured row reads as a wrong colour
-- rather than crashing the assertion.
local function NameColor(btn)
    local r, g, b = btn.text:GetTextColor()
    return r or 1, g or 1, b or 1
end

do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.inRange = {}
    RaidSim.As(lm, function()
        lm.KART.LC.pendingTrades = {
            { itemLink = GLOVES, winnerKey = alric.guid, rollID = 94, lootedAt = time() },
        }
        lm.KART.LC.Trade.RefreshTradeReminder()
    end)
    local nameBtn = lm.KART.LC.tradeReminderFrame.rows[1].nameBtn
    local r, g = NameColor(nameBtn)
    T.truthy(r > g, "a winner standing too far away reads red")

    KARTTEST.inRange[alric.unit] = true
    KARTTEST.AdvanceTime(1)
    r, g = NameColor(nameBtn)
    T.truthy(g > r, "and turns green when they walk into range, without anybody clicking anything")

    -- CheckInteractDistance is combat-restricted (it answers nil since 9.1), so a red row in a pull
    -- would mean "we cannot tell" while looking exactly like "they are not here".
    KARTTEST.inCombat = true
    KARTTEST.AdvanceTime(1)
    local br, bg, bb = NameColor(nameBtn)
    T.truthy(br > 0.9 and bg > 0.9 and bb < 0.5,
        "in combat the client refuses to answer, and the row says so rather than lying red")
    KARTTEST.inCombat = false
    KARTTEST.AdvanceTime(1)

    nameBtn:GetScript("OnEnter")(nameBtn)
    nameBtn:GetScript("OnLeave")(nameBtn)
    r, g = NameColor(nameBtn)
    T.truthy(g > r, "and the mouse leaving the row gives the range colour back, not plain white")

    RaidSim.As(lm, function() lm.KART.LC.tradeReminderFrame:Hide() end)
    KARTTEST.AdvanceTime(1)
    T.eq(lm.KART.LC.tradeRangeTicker, nil,
        "a closed window stops asking the client where everybody is standing")
end

-- The item's own clock, not ours (B4) ---------------------------------------------------------------
-- Everything above measures from a stamp KART writes itself. Blizzard writes the truth into the
-- item's tooltip, as localized TEXT -- there is no API that answers it as a number -- and reading it
-- is the difference between a deadline we believe and the one the client will actually enforce.
do
    local _, lm = F.NewRaid()
    local Parse = lm.KART.LC.Trade.ParseTradeTimeText
    T.eq(Parse("1 hour 59 min"), 3600 + 59 * 60, "an hour and a bit reads back as seconds")
    T.eq(Parse("14 min"), 14 * 60, "so does a bare minute count")
    T.eq(Parse("nothing about time"), nil, "and text with no duration in it is no opinion at all")

    -- The whole point of parsing against the client's own duration globals rather than against
    -- English: this guild raids in two languages and the German client says something else entirely.
    local hours, minutes = _G.INT_SPELL_DURATION_HOURS, _G.INT_SPELL_DURATION_MIN
    _G.INT_SPELL_DURATION_HOURS = "%d |4Stunde:Stunden;"
    _G.INT_SPELL_DURATION_MIN   = "%d |4Min.:Min.;"
    T.eq(Parse("1 Stunde 59 Min."), 3600 + 59 * 60, "a German client's tooltip reads the same")
    _G.INT_SPELL_DURATION_HOURS, _G.INT_SPELL_DURATION_MIN = hours, minutes
end

do
    -- The stamp says three hours left, the item says ten minutes. The item wins: a stamp taken at
    -- award time on a client that never saw the roll start, or one carried across a reload, can be
    -- minutes or hours out, and the raid finds out when the trade is refused.
    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = 10 * 60 }
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.truthy(out:find("Gloombind", 1, true),
        "the warning follows the item's own clock, not our stamp: " .. out)
    T.eq(#lm.KART.LC.pendingTrades, 1, "and the obligation itself still stands")
    KARTTEST.bagTradeTime = {}
end

do
    -- An item that is bound with no trade line at all can never be handed over. A four-hour promise
    -- for it is worse than no promise: the lootmaster works the list, the winner waits for a trade
    -- that cannot happen, and nothing ever says so.
    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = "bound" }
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(#lm.KART.LC.pendingTrades, 0, "an item that can never be traded comes off the list")
    T.truthy(out:find("Gloombind", 1, true), "and is said out loud rather than vanishing: " .. out)
    KARTTEST.bagTradeTime = {}
end

do
    -- No copy in our bags -- the stand-in loot owner case (B60), where the item is in somebody
    -- else's inventory. The tooltip cannot be read at all there, and "cannot read" must never be
    -- treated as "no time left".
    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = {} }
    KARTTEST.bagTradeTime = {}
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(#lm.KART.LC.pendingTrades, 1, "an item we cannot see is left exactly as it was")
    T.eq(out, "", "and nothing is said about it")
end

-- An item past its window is not an item that never had one ----------------------------------------
-- B4 reads the trade clock off the item, and an item whose four hours ran out is soulbound with no
-- trade line -- exactly what "bound to us, never keepable" looks like. The untradeable branch was
-- tested first, so the ordinary expiry (B47) told the lootmaster the promise was never keepable: a
-- false statement that hides both the real cause and the behaviour that would fix it. The two are
-- told apart by our own stamp, which is the one thing that knows the item WAS tradeable at 20:00.
do
    local _, lm = OwingSince(TRADE_WINDOW + 60) -- awarded four hours and a minute ago
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = "bound" }
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    KARTTEST.bagTradeTime = {}

    T.eq(#lm.KART.LC.pendingTrades, 0, "the row still comes off the list")
    T.truthy(out:find("Handelsfenster", 1, true) ~= nil,
        "and it is reported as a window that ran out, not as one that never existed: " .. out)
    T.truthy(out:find("nie übergeben", 1, true) == nil,
        "so the lootmaster is not told the item could never have been handed over")
end

-- The clock keeps running for what is still undecided -----------------------------------------------
-- B1's warning rides the same ticker as the trade obligations, and the ticker was cancelled the
-- moment the last PENDING TRADE cleared. Trade the one item you awarded and the warning for the one
-- the council never decided stops with it -- on the last boss of the night there is no further
-- START_LOOT_ROLL to restart it, so the item dies exactly as silently as before B1.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 91, F.GLOVES)   -- awarded below
    F.Drop(sim, 92, F.WEAPON)   -- never decided
    KARTTEST.AdvanceTime(1)

    RaidSim.As(lm, function()
        lm.KART.LC.Trade.AssignWinner(91, alric.guid, "BIS", nil)
    end)
    KARTTEST.AdvanceTime(1)
    T.truthy(lm.KART.LC.tradeTimeoutTicker ~= nil, "the ticker is running for the awarded item")

    RaidSim.As(lm, function() lm.KART.LC.Trade.RemovePendingTrade(91) end)
    T.truthy(lm.KART.LC.rollItems[92] ~= nil and lm.KART.LC.assignedWinners[92] == nil,
        "the second item is still on the table and still undecided")
    T.truthy(lm.KART.LC.tradeTimeoutTicker ~= nil,
        "so handing over the awarded one does not stop the clock on it")
end

-- ...and it is running again after a reload with nothing but undecided items ------------------------
-- The state B1 exists for: the boss is dead, the council is talking, nobody has awarded anything --
-- and the lootmaster reloads. There is no pending trade to restore, so the restore path started no
-- ticker at all and the four-hour clock ran out unwatched.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 93, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.truthy(lm.KART.LC.rollLootedAt[93] ~= nil, "the drop is stamped before the reload")

    local back = RaidSim.Reload(sim, "Bramor")
    KARTTEST.AdvanceTime(1)
    T.eq(#back.KART.LC.pendingTrades, 0, "nothing was awarded, so there is no obligation to restore")
    T.truthy(back.KART.LC.rollItems[93] ~= nil, "the undecided item itself came back")
    T.truthy(back.KART.LC.tradeTimeoutTicker ~= nil,
        "and its deadline is being watched again")
end
