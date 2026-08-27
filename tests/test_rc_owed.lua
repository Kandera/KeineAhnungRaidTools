dofile("tests/rc_stub.lua")

local env = setmetatable({}, { __index = _G })
local KART = {}
env.KART = KART
_G.KART = KART
local function LoadAddonFile(path)
    local chunk = assert(loadstring(assert(io.open(path, "r")):read("*a"), "@" .. path))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
LoadAddonFile("RCCompanion.lua")
LoadAddonFile("RCOwed.lua")
local RC = KART.RC

local LINK = "|cffa335ee|Hitem:19019::::::::80:::::::::|h[Thunderfury]|h|r"
local LINK2 = "|cffa335ee|Hitem:17182::::::::80:::::::::|h[Sulfuras]|h|r"

local function AsBob()
    KARTTEST.SetRaid({
        { name = "Lead", guid = "Player-1-AAAA", leader = true },
        { name = "Bob",  guid = "Player-1-BBBB" },
        { name = "Ann",  guid = "Player-1-CCCC" },
    })
    KARTTEST.activeUnit = "raid2"
end

local function ResetOwed()
    _G.KART_Settings = _G.KART_Settings or {}
    KART_Settings.rcShowOwedReminder = true
    KARTTEST.inCombat = false
    KARTTEST.rcLootTable = { [1] = { link = LINK }, [2] = { link = LINK2 } }
    KARTTEST.initiatedTrades = {}
    KARTTEST.inRange = {}
    KARTTEST.tradeTargetItems = {}
    RC.EnableOwed()
    local store = RC.EnsureOwedStore()
    wipe(store.items)
    store.dismissed = false
    store.schemaVersion = 1
end

KARTTEST.InstallRC()
KART.L = KART.L or {}
AsBob()
ResetOwed()

RC.HandleOwedAward(1, "Bob-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 1, "winner records the awarded item")
T.eq(RC.OwedItems()[1].link, LINK, "owed row keeps the loot-table link")
T.eq(RC.OwedItems()[1].trader, "Lead-TarrenMill", "owed row names the trader")
T.eq(RC.OwedShouldShow(), true, "winner sees the owed window")

local leadSnap = KARTTEST.activeUnit
KARTTEST.activeUnit = "raid1"
ResetOwed()
RC.HandleOwedAward(1, "Bob-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 0, "trader does not get a winner owed row")
T.eq(RC.OwedShouldShow(), false, "trader does not open the winner window")
KARTTEST.activeUnit = leadSnap
ResetOwed()

RC.HandleOwedAward(1, "Bob-TarrenMill", "Bob-TarrenMill")
T.eq(#RC.OwedItems(), 0, "winning your own item is not owed")

RC.HandleOwedAward(1, "Bob-TarrenMill", "Lead-TarrenMill")
KART_Settings.rcShowOwedReminder = false
T.eq(#RC.OwedItems(), 1, "the off switch still keeps the owed list")
T.eq(RC.OwedShouldShow(), false, "the off switch hides the window")
T.eq(RC.OpenOwedWindow(), false, "/kart owed respects the off switch")

KART_Settings.rcShowOwedReminder = true
RC.DismissOwed()
T.eq(RC.OwedShouldShow(), false, "closing the window keeps it closed")
T.eq(RC.OpenOwedWindow(), true, "/kart owed reopens a dismissed list")

RC.DismissOwed()
RC.HandleOwedAward(2, "Bob-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 2, "a second session is a second owed row")
T.eq(RC.OwedShouldShow(), true, "a new win reopens a dismissed window")

RC.HandleOwedAward(1, "Ann-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 1, "re-award to someone else drops our row for that session")
T.eq(RC.OwedItems()[1].session, 2, "the other session stays owed")

RC.HandleOwedIncomingLinks({ LINK2 })
T.eq(#RC.OwedItems(), 0, "receiving the item in trade clears the owed row")

ResetOwed()
KARTTEST.inCombat = true
RC.HandleOwedAward(1, "Bob-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 1, "an award in combat is still recorded")
T.eq(RC.OwedShouldShow(), false, "the window does not pop in combat")
KARTTEST.inCombat = false
RC.OnOwedOutOfCombat()
T.eq(RC.OwedShouldShow(), true, "the window appears after combat if still owed")

ResetOwed()
RC.EnableOwed()
RCLootCouncil.TradeUI:OnAwardReceived(1, "Bob-TarrenMill", "Lead-TarrenMill")
T.eq(#RC.OwedItems(), 1, "TradeUI OnAwardReceived hook records a win")

KARTTEST.inRange["Lead"] = true
T.eq(RC.TryTradeOwed(1), true, "a click in range opens trade with the trader")
T.eq(KARTTEST.initiatedTrades[1], "Lead", "InitiateTrade uses the short trader name")

RCLootCouncil.TradeUI.isTrading = true
KARTTEST.initiatedTrades = {}
T.eq(RC.TryTradeOwed(1), false, "owed does not InitiateTrade while a trade is already open")
T.eq(#KARTTEST.initiatedTrades, 0, "and does not call InitiateTrade")
RCLootCouncil.TradeUI.isTrading = false

ResetOwed()
RC.EnableOwed()
local origLink = GetTradeTargetItemLink
_G.GetTradeTargetItemLink = function() error("secret trade link") end
local ok = pcall(function()
    RCLootCouncil.TradeUI:OnEvent_UI_INFO_MESSAGE("UI_INFO_MESSAGE", _G.LE_GAME_ERR_TRADE_COMPLETE)
end)
_G.GetTradeTargetItemLink = origLink
T.eq(ok, true, "RC TRADE_COMPLETE still runs when a trade link is secret")

AsBob()
ResetOwed()
RC.HandleOwedAward(1, "Bob-TarrenMill", "Lead-TarrenMill")
KARTTEST.tradeTargetItems = { LINK }
RCLootCouncil.TradeUI:OnEvent_UI_INFO_MESSAGE("UI_INFO_MESSAGE", _G.LE_GAME_ERR_TRADE_COMPLETE)
T.eq(#RC.OwedItems(), 0, "a completed trade still clears the owed row via RC's handler")

local store = RC.EnsureOwedStore()
store.schemaVersion = nil
store.items = "nope"
store.leftover = true
RC.EnableOwed()
T.eq(RC.EnsureOwedStore().schemaVersion, 1, "a shapeless store is rebuilt")
T.eq(type(RC.EnsureOwedStore().items), "table", "rebuilt store has an items list")
