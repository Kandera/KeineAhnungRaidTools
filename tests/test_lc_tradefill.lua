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

-- ...and from the pending trade itself, not only from an undecided item (B144, B149 mutation gap) ----
-- The block above restarts the ticker through LC.RestoreSessionSnapshot's own check, and that one
-- only ever runs when there is still something on LC.councilTabs/LC.voteListRolls for
-- LC.SaveSessionSnapshot to have written a store.tables for in the first place -- with nothing on the
-- panel at all it returns before ever writing one, and LC.RestoreSessionSnapshot bails out on the
-- other side before reaching its own AnythingOnTheTradeClock() check. That is exactly the ordinary
-- shape of a BoP obligation: the item is awarded, the tab is closed (End Round, or the lootmaster
-- dismissing it), and only the trade reminder is left. Without Trade.RestorePersistedTrades starting
-- the clock on its OWN pending-trade table, a reload in that shape restores the reminder row with no
-- clock behind it at all: no 20-minutes-left warning, no expiry, until something unrelated happens to
-- start one.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 94, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(94, alric.guid, "BIS", nil) end)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(lm, function() lm.KART.LC.Council.CloseCouncilTab(94) end)
    T.truthy(#lm.KART.LC.pendingTrades > 0, "the setup: a pending trade obligation exists before the reload")
    T.eq(#lm.KART.LC.councilTabs, 0, "and nothing at all is left on the council panel")

    local back = RaidSim.Reload(sim, "Bramor")
    T.truthy(#back.KART.LC.pendingTrades > 0, "the pending trade itself came back")
    T.truthy(back.KART.LC.tradeTimeoutTicker ~= nil,
        "Gap 6 (B144): and its clock is running again, from the pending trade alone -- nothing was " ..
        "left on the table for LC.RestoreSessionSnapshot's own check to see")
end

-- A localized sentence with a positional argument must not blow up the ticker -----------------------
-- BIND_TRADE_TIME_REMAINING is Blizzard's own string and several locales write it with a positional
-- insertion ("%1$s") rather than a bare "%s". The escape class covered every magic character except
-- the one that matters here -- "%" itself -- so the pattern came out holding "%1", which Lua reads as
-- a BACK-REFERENCE and refuses: "invalid capture index", thrown out of the five-minute ticker on the
-- first tooltip line it reads. Not a degraded reading, an error, and it takes the whole pass with it
-- -- expiry pruning included. This guild ships enUS and deDE only, but nothing about the parser knows
-- that, and RC strips the same insertion for the same reason.
do
    local realBind = _G.BIND_TRADE_TIME_REMAINING
    _G.BIND_TRADE_TIME_REMAINING = "Handelbar für: %1$s"

    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = 30 * 60 }
    local ok = pcall(function()
        Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    end)
    KARTTEST.bagTradeTime = {}
    _G.BIND_TRADE_TIME_REMAINING = realBind

    T.eq(ok, true, "a locale that numbers its insertion does not error the trade-timeout pass")
    T.eq(#lm.KART.LC.pendingTrades, 1, "and the obligation is still standing afterwards")
end

-- Warbound counts as bound ---------------------------------------------------------------------------
-- The untradeable reading keys off the tooltip's bound line, and only ITEM_SOULBOUND was matched.
-- Midnight hands out plenty that is account- or warbound instead, and for those the reading came back
-- nil -- "says nothing" -- so B4's valuable half never fired for them.
do
    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = { GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = "warbound" }
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    KARTTEST.bagTradeTime = {}

    T.eq(#lm.KART.LC.pendingTrades, 0, "an item bound to the account can never be handed over either")
    T.truthy(out:find("Gloombind", 1, true) ~= nil, "and it is said out loud: " .. out)
end

-- Two copies, and the live one decides -----------------------------------------------------------
-- FindItemInBags answers with whichever slot it reaches first. A second, fully bound copy of the same
-- item from an earlier lockout sitting in a lower bag slot therefore answered for the live one -- and
-- since B4 the consequence is destructive rather than merely wrong: the obligation is DELETED and
-- announced as never keepable, which no later pass undoes.
do
    local _, lm = OwingSince(60)
    KARTTEST.bags = { [0] = { GLOVES, GLOVES } }
    KARTTEST.bagTradeTime = { [GLOVES] = { "bound", 30 * 60 } }
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    KARTTEST.bagTradeTime = {}

    T.eq(#lm.KART.LC.pendingTrades, 1,
        "the copy that CAN still be traded is the one that answers for the obligation")
    T.eq(out, "", "so nothing is said about handing it over being impossible")
end

-- A warning nobody heard has not been given ---------------------------------------------------------
-- B3 holds the chat line back until the pull is over; the "said once" latch was set when the line was
-- QUEUED, not when it was said. LC.pendingTrades is the saved table itself (Trade.RestorePersistedTrades
-- points the live list at store.pending), so the latch persists immediately -- and a reload or a
-- disconnect inside that pull leaves the entry marked as warned about with nobody ever having been
-- warned. The 20-minutes-left warning is the one thing standing between the lootmaster and losing the
-- item to the timer, and it never comes again.
--
-- The undecided warning beside it already gets this right, by keeping its latch memory-only on
-- purpose: "after a reload the deadline is still real, and hearing about it once more is the right
-- side to be wrong on". Same rule, arrived at from the other end.
do
    local _, lm = OwingSince(TRADE_WINDOW - 600) -- ten minutes of trade window left
    KARTTEST.inCombat = true
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(out, "", "nothing is said while the raid is in combat")
    T.is_nil(lm.KART.LC.pendingTrades[1].timeoutWarned,
        "and the entry does not yet count as warned about, because nobody has been warned")

    -- The ticker comes round again inside the same pull. That must not queue a second copy.
    Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)

    KARTTEST.inCombat = false
    local after = Capture(function()
        RaidSim.As(lm, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    local seen = select(2, after:gsub("Gloombind", ""))
    T.eq(seen, 1, "the warning arrives once the pull is over, once: " .. after)
    T.eq(lm.KART.LC.pendingTrades[1].timeoutWarned, true, "and only now does it count as said")
end

-- The durable notice queue (B4's rest, closed 2026-08-07) -------------------------------------------
-- deferredNotices is memory-only, so a reload or disconnect DURING a pull used to lose whatever it
-- was holding. For the two warnings that costs nothing -- both are regenerated from state that IS
-- persisted (see the block above and B1's ticker). But LC_TRADE_EXPIRED and LC_TRADE_UNTRADEABLE fire
-- because an entry was just REMOVED from LC.pendingTrades, and that removal survives a reload while
-- the explanation for it did not: a row vanished from the trade reminder with nothing said. Only
-- those two are written into KART_LCTrades now.

-- The loss this fixes: an expired trade during a pull, a reload before the pull ends, and the
-- explanation still reaching the player afterwards. Without persisting the queue this line is gone
-- for good the moment the client reloads.
do
    local sim, lm = OwingSince(TRADE_WINDOW + 60) -- already past the window
    KARTTEST.inCombat = true
    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(#lm.KART.LC.pendingTrades, 0, "the dead obligation is dropped mid-pull, same as before (B47)")
    T.eq(out, "", "and the line about it waits for the pull to end, same as before (B3)")

    -- The client reloads before the pull is over.
    local back = RaidSim.Reload(sim, "Bramor")
    T.eq(#back.KART.LC.pendingTrades, 0, "the removal itself already survived a reload before this fix")

    KARTTEST.inCombat = false
    local after = Capture(function()
        RaidSim.As(back, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    T.truthy(after:find("Gloombind", 1, true),
        "and now the explanation reaches the player too, once the pull ends: " .. after)
end

-- The two warnings are NOT persisted -- the five-minute ticker regenerates LC_TRADE_TIMEOUT_WARNING
-- from LC.pendingTrades itself (which IS persisted), and a restored notice could never carry its
-- onSaid closure, so entry.timeoutWarned would never latch and the line would queue again every five
-- minutes. Writing it to the durable store as well would print it twice.
do
    local sim, lm = OwingSince(TRADE_WINDOW - 600) -- ten minutes of trade window left
    -- OwingSince replaces LC.pendingTrades outright rather than inserting into it, so it does not
    -- keep KART_LCTrades.pending pointed at the same table the way Trade.AddPendingTrade does. This
    -- test reloads the client and needs the entry itself (not just a queued notice) to come back, so
    -- the alias has to be restored by hand first.
    lm.env.KART_LCTrades.pending = lm.KART.LC.pendingTrades
    KARTTEST.inCombat = true
    Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    T.eq(#(lm.env.KART_LCTrades.notices or {}), 0,
        "the 20-minutes-left warning does not go into the durable queue")

    local back = RaidSim.Reload(sim, "Bramor")
    T.eq(#(back.env.KART_LCTrades.notices or {}), 0, "still nothing durable after the reload")

    KARTTEST.inCombat = false
    local afterReload = Capture(function()
        RaidSim.As(back, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    T.eq(afterReload, "", "nothing was waiting to be said -- it was never queued in the first place")

    -- The ticker comes back round (this is what actually regenerates the warning).
    local out = Capture(function() RaidSim.As(back, back.KART.LC.Trade.CheckTradeTimeouts) end)
    local seen = select(2, out:gsub("Gloombind", ""))
    T.eq(seen, 1, "and it is said exactly once after the reload, not twice: " .. out)
end

-- Stale entries are dropped -- a queued line describes a four-hour clock (TRADE_TIMEOUT_SECONDS), and
-- once that clock has run out the explanation is moot. Same convention as
-- Trade.RestorePersistedTrades's pruneExpired for store.pending/store.owed. A fresh entry rides
-- alongside the stale one as a positive control: without it, a broken delayed-print branch would
-- pass this block just as well as a working one, because there would be nothing left to print either
-- way.
do
    local sim, lm = F.NewRaid()
    lm.env.KART_LCTrades.notices = {
        { text = "|cffff0000KART:|r stale " .. GLOVES, at = time() - (TRADE_WINDOW + 60) },
        { text = "|cffff0000KART:|r fresh " .. WEAPON, at = time() },
    }
    local back
    local atReload = Capture(function() back = RaidSim.Reload(sim, "Bramor") end)
    T.eq(atReload, "", "nothing prints at the moment of the reload itself")
    T.eq(#(back.env.KART_LCTrades.notices or {}), 1,
        "the stale entry is dropped from the store at load, the fresh one stays")

    local tooSoon = Capture(function() KARTTEST.AdvanceTime(4) end)
    T.eq(tooSoon, "", "and nothing prints before the five-second delay is up")

    local out = Capture(function() KARTTEST.AdvanceTime(2) end) -- now six seconds since the reload
    T.truthy(out:find("fresh", 1, true) ~= nil, "the fresh entry prints once the delay elapses: " .. out)
    T.truthy(out:find("stale", 1, true) == nil, "and the stale one, already dropped, never does: " .. out)
end

-- The cap holds and drops the oldest -- 21 removals in the same pull, one over the 20-entry guard
-- rail. Unlike LC.rollsSeenWhileUnaware (keyed by rollID, no order, must drop the newest), this is a
-- sequence: the entry queued first is the one dropped, and every entry queued after it survives.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.bags = { [0] = { GLOVES, WEAPON } }
    KARTTEST.bagTradeTime = { [GLOVES] = "bound", [WEAPON] = "bound" }

    -- Processed backwards (#list down to 1), so entry 21 -- the WEAPON one -- is the first one
    -- queued, and the twenty GLOVES entries after it are queued later.
    local entries = {}
    for i = 1, 20 do
        entries[i] = { itemLink = GLOVES, winnerKey = alric.guid, rollID = i, lootedAt = time() - 60 }
    end
    entries[21] = { itemLink = WEAPON, winnerKey = alric.guid, rollID = 21, lootedAt = time() - 60 }
    RaidSim.As(lm, function() lm.KART.LC.pendingTrades = entries end)

    KARTTEST.inCombat = true
    Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)
    KARTTEST.bagTradeTime = {}

    local notices = lm.env.KART_LCTrades.notices or {}
    T.eq(#notices, 20, "the durable queue caps at 20")
    local sawOldest = false
    for _, n in ipairs(notices) do
        if n.text:find(WEAPON, 1, true) then sawOldest = true end
    end
    T.eq(sawOldest, false, "the oldest -- queued first -- is the one dropped")
end

-- A reload mid-pull does not print into the fight -- the whole reason this mechanism exists. Still in
-- combat when Trade.RestorePersistedTrades runs, the restored lines belong back in the in-memory
-- queue so the ordinary PLAYER_REGEN_ENABLED drain prints them, not straight into the pull.
do
    local sim, lm = OwingSince(TRADE_WINDOW + 60)
    KARTTEST.inCombat = true
    Capture(function() RaidSim.As(lm, lm.KART.LC.Trade.CheckTradeTimeouts) end)

    local back
    local atReload = Capture(function() back = RaidSim.Reload(sim, "Bramor") end)
    T.eq(atReload, "", "nothing prints at the moment of the reload itself")

    local stillInCombat = Capture(function() KARTTEST.AdvanceTime(10) end)
    T.eq(stillInCombat, "",
        "and nothing prints while the fight is still going, even once the usual few-seconds-after-" ..
        "load delay would have elapsed")

    KARTTEST.inCombat = false
    local after = Capture(function()
        RaidSim.As(back, function() KARTTEST.FireEvent("PLAYER_REGEN_ENABLED") end)
    end)
    T.truthy(after:find("Gloombind", 1, true), "only once combat ends does it arrive: " .. after)
end
