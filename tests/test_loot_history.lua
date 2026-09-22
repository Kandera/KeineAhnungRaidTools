local KASC = LibStub("KASC-1.0")
KASC:Init("KART")

local KART = {}
_G.KART = KART
KART.UnitLeads = function(unit) return UnitIsGroupLeader(unit) end
KART.UnitAssists = function(unit) return UnitIsGroupAssistant(unit) end

local chunk = assert(loadstring(assert(io.open("LootHistory.lua", "r")):read("*a"), "@LootHistory.lua"))
chunk("KeineAhnungRaidTools", KART)
local LH = KART.LH

local rosterBefore = KARTTEST.SnapshotRoster()
local activeBefore = KARTTEST.activeUnit

-- Later files replace the transport. RaidSim's sender errors when no client is active, and
-- ChatThrottleLib swallows that, so a send looks successful and never reaches KARTTEST.sent.
-- This file is single-client: put the recording stub back, open the restriction gate, and
-- give the throttle budget room because nothing here despools a queue.
local sendBefore = _G.C_ChatInfo.SendAddonMessage
_G.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
    KARTTEST.sent[#KARTTEST.sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
    return 0
end
KARTTEST.SetRestriction(1, 0)
KARTTEST.SetRestriction(2, 0)
ChatThrottleLib.avail = 999999
ChatThrottleLib.bQueueing = false

local function SentWith(prefix)
    local hits = {}
    for _, sent in ipairs(KARTTEST.sent) do
        if type(sent.msg) == "string" and string.find(sent.msg, prefix, 1, true) then
            hits[#hits + 1] = sent
        end
    end
    return hits
end

local function Ctx(name)
    return { sender = name .. "-TarrenMill", shortName = name }
end

local function SeedRow(id, epoch, winner)
    return LH.EncodeRow({
        id = id, epoch = epoch, time = 1787097600 + 20, dateStr = "2026/09/22",
        item = "item:" .. id, winner = winner,
        reason = "Mainspec", boss = "Vorasius", difficulty = "Mythic", difficultyID = 16,
        instance = "The Voidspire", instanceID = 2912, session = 1,
    })
end

-- Store and codec ------------------------------------------------------------------------
_G.KART_LootHistory = nil
_G.KART_LootHistoryEpoch = nil
local history, epoch = LH.EnsureStore()
T.eq(type(history), "table", "missing history becomes a table")
T.eq(epoch, 1, "missing epoch becomes 1")
_G.KART_LootHistory = "bad"
_G.KART_LootHistoryEpoch = "bad"
history, epoch = LH.EnsureStore()
T.eq(type(history), "table", "a non-table history is replaced")
T.eq(epoch, 1, "a non-number epoch is replaced")

local row = {
    id = "10-001", epoch = 1, time = 10, item = "|cffa335ee|Hitem:12345::::::::::::|h[Blade]|h|r",
    winner = "Ann", reason = "Mainspec", boss = "Vorasius", class = "WARRIOR",
    color = { r = 0.2, g = 0.8, b = 0.2 }, difficulty = "Mythic", difficultyID = 16,
    instance = "The Voidspire", instanceID = 2912, session = 3,
}
local again = LH.DecodeRow(LH.EncodeRow(row))
T.eq(again.item, row.item, "an item link survives the field split")
T.eq(again.boss, "Vorasius", "boss round-trips")
T.eq(again.color.r, 0.2, "color r round-trips")
T.eq(again.session, 3, "session round-trips")
T.eq(again.difficultyID, 16, "difficulty id round-trips")

_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
LH.Put(row)
LH.Put({ id = "10-001", epoch = 1, time = 11, item = "x", winner = "Bob" })
T.eq(#KART_LootHistory, 1, "the same award id is one row")

_G.KART_LootHistory = {}
LH.Put({ id = "10-001", epoch = 1, time = 10, item = "blade", winner = "Ann" })
LH.Put({ id = "9-001", epoch = 1, time = 9, item = "y", winner = "Cat" })
LH.Put({ id = "8-001", epoch = 2, time = 8, item = "z", winner = "Ann" })
local visible = LH.VisibleRows("ann")
T.eq(#visible, 1, "the name filter is the current epoch only")
T.eq(visible[1].winner, "Ann", "the current epoch's Ann is the visible row")

local sumA = LH.Checksum()
LH.Put({ id = "7-001", epoch = 1, time = 7, item = "q", winner = "Dan" })
local sumB = LH.Checksum()
T.eq(sumA ~= sumB, true, "a new id changes the checksum")
KART_LootHistory[1], KART_LootHistory[#KART_LootHistory] =
    KART_LootHistory[#KART_LootHistory], KART_LootHistory[1]
T.eq(LH.Checksum(), sumB, "checksum follows the set of ids, not insertion order")

-- Award flush -----------------------------------------------------------------------------
local function ResetLog()
    _G.KART_LootHistory = {}
    _G.KART_LootHistoryEpoch = 1
    _G.RCLootCouncilML = { running = false }
    KARTTEST.ClearSent()
    LH.ResetAwardState()
end

ResetLog()
RCLootCouncilML.running = true
LH.OnAwardSuccess(2, "Ann", "normal", "|cffa335ee|Hitem:12345::::::::::::|h[Blade]|h|r", "Mainspec")
LH.OnHistorySend({
    lootWon = "|cffa335ee|Hitem:12345::::::::::::|h[Blade]|h|r",
    boss = "Vorasius", class = "WARRIOR", color = { r = 1, g = 0, b = 0 },
}, "Ann", 2)
T.eq(#KART_LootHistory, 0, "the row waits until the next frame")
KARTTEST.AdvanceTime(0)
T.eq(#KART_LootHistory, 1, "award success plus history event is one row")
T.eq(KART_LootHistory[1].boss, "Vorasius", "the history event supplies the boss")
T.eq(KART_LootHistory[1].winner, "Ann", "the winner is the awarded player")
T.eq(KART_LootHistory[1].reason, "Mainspec", "the response text is the reason")
T.eq(#SentWith("LH_ADD:"), 1, "the row is broadcast as LH_ADD")

ResetLog()
RCLootCouncilML.running = true
LH.OnAwardSuccess(1, "Ann", "normal", "item:1", "Free")
KARTTEST.AdvanceTime(0)
T.eq(#KART_LootHistory, 1, "an award with no history event is still stored")
T.eq(KART_LootHistory[1].reason, "Free", "a log=false reason is kept")

ResetLog()
LH.OnHistorySend({ lootWon = "item:bonus", boss = "Bonus" }, "Bob", nil)
T.eq(#KART_LootHistory, 1, "a history event with no stashed award is its own row")
T.eq(KART_LootHistory[1].boss, "Bonus", "the standalone history event keeps its boss")

ResetLog()
RCLootCouncilML.running = true
LH.OnAwardSuccess(1, "Ann", "normal", "item:1", "Mainspec")
KARTTEST.AdvanceTime(0)
local firstId = KART_LootHistory[1].id
local firstGen = KART_LootHistory[1].generation
LH.OnAwardSuccess(1, "Bob", "normal", "item:1", "Offspec")
KARTTEST.AdvanceTime(0)
T.eq(#KART_LootHistory, 1, "a re-award in the same generation replaces the row")
T.eq(KART_LootHistory[1].winner, "Bob", "the replacement winner is the new one")
T.eq(KART_LootHistory[1].generation, firstGen, "re-award stays in the generation")
local repl = SentWith("LH_REPL:")
T.eq(#repl, 1, "re-award broadcasts LH_REPL")
T.truthy(repl[1].msg:find(firstId, 1, true) ~= nil, "LH_REPL names the replaced id")

ResetLog()
RCLootCouncilML.running = true
LH.OnAwardSuccess(1, "Ann", "normal", "item:1", "Mainspec")
KARTTEST.AdvanceTime(0)
RCLootCouncilML.running = false
LH.PollRunning()
RCLootCouncilML.running = true
LH.OnAwardSuccess(1, "Cat", "normal", "item:9", "Mainspec")
KARTTEST.AdvanceTime(0)
T.eq(#KART_LootHistory, 2, "a new session does not replace the previous session's row")

-- RC returns before it emits a history event. The row is still ours.
do
    local ml = { TrackAndLogLoot = function() return nil end }
    LH.HookTrackAndLog(ml)
    _G.KART_LootHistory = {}
    _G.KART_LootHistoryEpoch = 1
    LH.ResetAwardState()
    ml:TrackAndLogLoot("Ann", "item:bonus", "BONUSROLL", "Boss", nil, nil, nil, "Ann")
    T.eq(#KART_LootHistory, 1, "a bonus roll is logged when RC's history event never fires")
    T.eq(KART_LootHistory[1].responseID, "BONUSROLL", "the bonus roll keeps its response id")
    _G.KART_LootHistory = {}
    LH.ResetAwardState()
    _G.RCLootCouncilML = { running = true }
    LH.OnAwardSuccess(1, "Ann", "normal", "item:1", "Free")
    ml:TrackAndLogLoot("Ann", "item:1", 1, "Boss", { text = "Free", log = false, sort = 403 }, 1)
    KARTTEST.AdvanceTime(0)
    T.eq(#KART_LootHistory, 1, "an award RC refuses to log is still one KART row")
    T.eq(KART_LootHistory[1].reason, "Free", "the reason RC skipped is the one we kept")
end

-- Authority and epoch ---------------------------------------------------------------------
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Aide", guid = "Player-1-BBBB", assist = true },
    { name = "Raider", guid = "Player-1-CCCC" },
})
KARTTEST.activeUnit = "raid2"

_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
LH.AcceptAdd(SeedRow("a1", 1, "Ann"), Ctx("Raider"))
T.eq(#KART_LootHistory, 0, "a raider who is not an assistant cannot append")
LH.AcceptAdd(SeedRow("a1", 1, "Ann"), Ctx("Aide"))
T.eq(#KART_LootHistory, 1, "an assistant can append")
LH.AcceptAdd(SeedRow("a1", 1, "Ann"), Ctx("Aide"))
T.eq(#KART_LootHistory, 1, "the same id from the wire is still one row")

LH.AcceptRepl("a1\001" .. SeedRow("a2", 1, "Bob"), Ctx("Aide"))
T.eq(#KART_LootHistory, 1, "a replacement removes only the named id")
T.eq(KART_LootHistory[1].id, "a2", "the new id is the one in the replacement")
T.eq(KART_LootHistory[1].winner, "Bob", "the replacement carries the new winner")
LH.Put({ id = "old-week", epoch = 1, time = 1, item = "item:a2", winner = "Ann" })
LH.AcceptRepl("a2\001" .. SeedRow("a3", 1, "Cat"), Ctx("Lead"))
T.eq(#KART_LootHistory, 2, "a different id with the same item stays")

LH.AcceptEpoch("2", Ctx("Aide"))
T.eq(KART_LootHistoryEpoch, 1, "an assistant cannot bump the epoch")
LH.AcceptEpoch("2", Ctx("Lead"))
T.eq(KART_LootHistoryEpoch, 2, "the leader's higher epoch is stored")
T.eq(#KART_LootHistory, 0, "rows from a lower epoch are deleted")
T.eq(LH.Checksum(), 0, "deleted ids leave the checksum")

KARTTEST.activeUnit = "raid1"
T.eq(LH.Clear(), true, "the leader can clear")
T.eq(KART_LootHistoryEpoch, 3, "clear bumps the epoch by one")

-- Catch-up --------------------------------------------------------------------------------
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Aide", guid = "Player-1-BBBB", assist = true },
})
KARTTEST.activeUnit = "raid1"
_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
_G.RCLootCouncilML = { running = true }
LH.ResetAwardState()
LH.PollRunning()
for i = 1, 3 do
    LH.Put({ id = "k" .. i, epoch = 1, time = 1787097600 + 1000 + i, item = "i",
             winner = "A", reason = "M", dateStr = "2026/08/20" })
end
LH.Put({ id = "ancient", epoch = 1, time = time() - (15 * 24 * 60 * 60), item = "i",
         winner = "A", reason = "M" })

KARTTEST.ClearSent()
LH.HandleRequest(string.format("%d\001%d\001%d", 1, 0, 0), Ctx("Aide"))
T.eq(#SentWith("LH_BATCH:"), 0, "a request during a running session is not answered yet")
KARTTEST.AdvanceTime(30)
LH.HandleRequest(string.format("%d\001%d\001%d", 1, 0, 0), Ctx("Aide"))
KARTTEST.AdvanceTime(29)
T.eq(#SentWith("LH_BATCH:"), 0, "a repeat request does not push the 60 second cap out")
KARTTEST.AdvanceTime(2)
local parkedAnswer = SentWith("LH_BATCH:")
T.eq(#parkedAnswer, 1, "the parked request is answered once 60 seconds have passed")
T.eq(parkedAnswer[1].channel, "WHISPER", "the catch-up answer is a whisper")
T.eq(parkedAnswer[1].target, "Aide-TarrenMill", "the whisper goes to the asker")

local function BatchRowCount(msg)
    local payload = string.sub(msg, 10)
    local countText, rest = payload:match("^%d+\001(%d+)\001(.*)$")
    if not countText then return 0, 0 end
    if rest == "" then return 0, tonumber(countText) end
    local n = 1
    for _ in rest:gmatch("\002") do n = n + 1 end
    return n, tonumber(countText)
end
local n, count = BatchRowCount(parkedAnswer[1].msg)
T.eq(n, 3, "the answer drops the 15 day row")
T.eq(count, 3, "the batch count matches the rows")

RCLootCouncilML.running = false
LH.PollRunning()
KARTTEST.ClearSent()
LH.ResetAwardState()
_G.RCLootCouncilML = { running = false }
LH.PollRunning()
KARTTEST.AdvanceTime(5)
LH.HandleRequest(string.format("%d\001%d\001%d", 1, LH.Checksum(), 0), Ctx("Aide"))
T.eq(#KARTTEST.sent, 0, "a matching checksum is not answered")

for i = 1, 151 do
    LH.Put({ id = "n" .. i, epoch = 1, time = 1787097600 + 200000 - i, item = "i",
             winner = "A", reason = "M", dateStr = "2026/08/21" })
end
T.eq(#LH.CatchUpRows(0), 150, "a catch-up answer stops at 150 rows")
local oldestKept = LH.CatchUpRows(0)[1]
T.truthy((oldestKept.time or 0) > time() - (15 * 24 * 60 * 60), "the kept rows are inside 14 days")

_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 2
local body = {}
for i = 1, 3 do
    body[#body + 1] = LH.EncodeRow({ id = "low" .. i, epoch = 1, time = time(), item = "i",
                                      winner = "A", reason = "M" })
end
LH.AcceptBatch("1\0013\001" .. table.concat(body, "\002"), Ctx("Aide"))
T.eq(#KART_LootHistory, 0, "a lower epoch batch is discarded")

_G.KART_LootHistory = { { id = "old", epoch = 1, time = 1, item = "x", winner = "Ann" } }
_G.KART_LootHistoryEpoch = 1
local newer = LH.EncodeRow({ id = "new", epoch = 2, time = 1787097600 + 10, item = "y",
                              winner = "Bob", reason = "M", dateStr = "2026/08/19" })
LH.AcceptBatch("2\0011\001" .. newer, Ctx("Aide"))
T.eq(KART_LootHistoryEpoch, 1, "an assistant's higher epoch batch is discarded")
LH.AcceptBatch("2\0011\001" .. newer, Ctx("Lead"))
T.eq(KART_LootHistoryEpoch, 2, "the leader's higher epoch batch is adopted")
T.eq(#KART_LootHistory, 1, "the adopted batch replaces the old epoch")
T.eq(KART_LootHistory[1].id, "new", "the adopted row is the one in the batch")

_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
_G.RCLootCouncilML = { running = true }
LH.ResetAwardState()
LH.PollRunning()
LH.Put({ id = "recent", epoch = 1, time = 1787097600 + 5000, item = "i", winner = "A",
         reason = "M", dateStr = "2026/08/20" })
RCLootCouncilML.running = false
LH.PollRunning()
KARTTEST.ClearSent()
LH.HandleRequest(string.format("%d\001%d\001%d", 1, 0, 0), Ctx("Aide"))
T.eq(#SentWith("LH_BATCH:"), 0, "the gate stays shut for 5 seconds after the session ends")
KARTTEST.AdvanceTime(5)
T.eq(#SentWith("LH_BATCH:"), 1, "the parked request is answered once the grace ends")

-- RC listener -----------------------------------------------------------------------------
local registered = {}
LH.RegisterRC({
    RegisterMessage = function(_, message, fn) registered[message] = fn end,
})
T.eq(type(registered.RCMLAwardSuccess), "function", "the award event is registered")
T.eq(type(registered.RCMLLootHistorySend), "function", "the history event is registered")
_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
_G.RCLootCouncilML = { running = true }
LH.ResetAwardState()
registered.RCMLAwardSuccess(nil, 4, "Ann", "normal", "item:4", "Mainspec")
registered.RCMLLootHistorySend(nil, {
    lootWon = "item:4", boss = "Chimaerus", votes = 3,
    itemReplaced1 = "Old Helm", itemReplaced2 = "Old Helm 2",
    response = "Mainspec", responseID = 1, isAwardReason = false,
    note = "bis", owner = "Lead-TarrenMill", id = "1785001000-7",
    date = "2026/09/22", time = "18:00:00", instance = "The Voidspire-Mythic",
    class = "WARRIOR",
}, "Ann", nil, "Chimaerus", nil, 4, nil)
KARTTEST.AdvanceTime(0)
local stored = KART_LootHistory[1]
T.eq(stored and stored.boss, "Chimaerus", "the RC message shape reaches the store")
T.eq(stored.votes, 3, "RC vote count is kept")
T.eq(stored.gear1, "Old Helm", "replaced gear is kept")
T.eq(stored.note, "bis", "the council note is kept")
T.eq(stored.owner, "Lead-TarrenMill", "the item owner is kept")
T.eq(stored.id, "1785001000-7", "the export id is RC's history id")
local json = LH.BuildRCLootCouncilJSON({ stored })
T.truthy(json:find('"votes":3', 1, true) ~= nil, "JSON votes match RC")
T.truthy(json:find('"id":"1785001000-7"', 1, true) ~= nil, "JSON id matches RC")
T.truthy(json:find('"instance":"The Voidspire-Mythic"', 1, true) ~= nil, "JSON instance is name-difficulty")
T.truthy(json:find('"gear1":"Old Helm"', 1, true) ~= nil, "JSON gear1 matches RC")
T.truthy(json:find('"note":"bis"', 1, true) ~= nil, "JSON note matches RC")
T.truthy(json:find('"date":"2026/09/22"', 1, true) ~= nil, "JSON date is RC's date string")
T.truthy(json:find('"owner":"Lead-TarrenMill"', 1, true) ~= nil, "JSON owner matches RC")
T.truthy(json:find('"servertime":"1785001000"', 1, true) ~= nil, "JSON servertime is the id prefix")

KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Aide", guid = "Player-1-BBBB", assist = true },
})
KARTTEST.activeUnit = "raid2"
_G.KART_LootHistory = {}
_G.KART_LootHistoryEpoch = 1
LH.AcceptAdd(LH.EncodeRow({
    id = "too-old", epoch = 1, time = 1787097600 - 10, dateStr = "2026/08/18",
    item = "Old", winner = "Ann", reason = "Mainspec",
}), Ctx("Aide"))
T.eq(#KART_LootHistory, 0, "a synced row from before 19 Aug 2026 is dropped")
LH.AcceptAdd(LH.EncodeRow({
    id = "on-day", epoch = 1, time = 1787097600 + 10, dateStr = "2026/08/19",
    item = "New", winner = "Ann", reason = "Mainspec",
}), Ctx("Aide"))
T.eq(#KART_LootHistory, 1, "a synced row from 19 Aug 2026 is kept")
LH.Put({ id = "stale", epoch = 1, time = 1787097600 - 50, dateStr = "2026/08/01",
         item = "Stale", winner = "Ann", reason = "Mainspec" })
local caught = LH.CatchUpRows(0)
T.eq(#caught, 1, "catch-up does not send rows from before the cutoff")
T.eq(caught[1].id, "on-day", "catch-up sends the row on the cutoff day")

LH.filters.search = "bob"
LH.filters.playerIds = nil
LH.filters.reason = nil
_G.KART_LootHistory = {
    { id = "by-item", epoch = 1, time = 1787097600 + 1, dateStr = "2026/08/19",
      item = "Blade", winner = "Ann", reason = "" },
    { id = "by-name", epoch = 1, time = 1787097600 + 2, dateStr = "2026/08/19",
      item = "Helm", winner = "Bob", reason = "" },
}
local found = LH.FilteredEntries()
T.eq(#found, 1, "search matches a winner name")
T.eq(found[1].id, "by-name", "the name hit is Bob's row")
LH.filters.search = "blade"
found = LH.FilteredEntries()
T.eq(#found, 1, "search still matches an item")
T.eq(found[1].id, "by-item", "the item hit is the blade")
LH.filters.search = ""

LH.filters.hideBonus = true
_G.KART_LootHistory = {
    { id = "won", epoch = 1, time = 1787097600 + 1, dateStr = "2026/08/19",
      item = "Blade", winner = "Ann", reason = "Mainspec", responseID = 1 },
    { id = "bonus", epoch = 1, time = 1787097600 + 2, dateStr = "2026/08/19",
      item = "Trinket", winner = "Ann", reason = "Bonus Loot", responseID = "BONUSROLL" },
}
found = LH.FilteredEntries()
T.eq(#found, 1, "hiding bonus rolls drops them from the list")
T.eq(found[1].id, "won", "the council award stays visible")
LH.filters.hideBonus = false
found = LH.FilteredEntries()
T.eq(#found, 2, "bonus rolls show again when the filter is off")

_G.KART_LootHistory = {
    { id = "keep-me", epoch = 1, time = 1787097600 + 5, dateStr = "2026/08/20",
      item = "Helm", winner = "Ann", reason = "Mainspec", note = "bis" },
    { id = "drop-me", epoch = 1, time = 1787097600 + 6, dateStr = "2026/08/20",
      item = "Blade", winner = "Bob", reason = "Offspec", note = "no" },
}
_G.KART_LootHistoryEpoch = 1
_G.KART_LootHistoryDeleted = nil
LH.Forget("drop-me")
T.eq(#KART_LootHistory, 1, "one row is deleted")
T.eq(KART_LootHistory[1].id, "keep-me", "the other row stays")
T.eq(KART_LootHistory[1].note, "bis", "the note stays on the remaining row")
T.eq(LH.IsDeleted("drop-me"), true, "the deleted id is remembered")
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Aide", guid = "Player-1-BBBB", assist = true },
    { name = "Raider", guid = "Player-1-CCCC" },
})
KARTTEST.activeUnit = "raid2"
LH.AcceptAdd(LH.EncodeRow({
    id = "drop-me", epoch = 1, time = 1787097600 + 6, dateStr = "2026/08/20",
    item = "Blade", winner = "Bob", reason = "Offspec",
}), Ctx("Aide"))
T.eq(#KART_LootHistory, 1, "a deleted id is not synced back")
LH.AcceptDelete("keep-me", Ctx("Raider"))
T.eq(#KART_LootHistory, 1, "a raider cannot delete someone else's row")
LH.AcceptDelete("keep-me", Ctx("Aide"))
T.eq(#KART_LootHistory, 0, "an assistant can delete a row for the raid")

_G.KART_LootHistory = {
    { id = "old-award", epoch = 1, time = 1787097600 - 100, dateStr = "2026/08/01",
      item = "|Hitem:9|h[Old]|h", winner = "Ann-TarrenMill", reason = "Mainspec" },
    { id = "new-award", epoch = 1, time = 1787097600 + 50, dateStr = "2026/09/01",
      item = "|Hitem:9|h[New]|h", winner = "Ann-TarrenMill", reason = "Offspec", color = { r = 0, g = 1, b = 0 } },
    { id = "other", epoch = 1, time = 1787097600 + 60, dateStr = "2026/09/02",
      item = "|Hitem:8|h[Helm]|h", winner = "Bob-TarrenMill", reason = "Mainspec" },
    { id = "bonus", epoch = 1, time = 1787097600 + 70, dateStr = "2026/09/03",
      item = "|Hitem:9|h[Bonus]|h", winner = "Ann-TarrenMill", reason = "Bonus Loot",
      responseID = "BONUSROLL" },
}
_G.KART_LootHistoryEpoch = 1
local recent = LH.RecentFor("Ann", 5)
T.eq(#recent, 1, "recent awards skip the cutoff and bonus loot")
T.eq(recent[1].reason, "Offspec", "the kept award is the newer one")
local winners = LH.WinnersOf("|cffa335ee|Hitem:9:::::::::|h[New]|h")
T.eq(winners["Ann-TarrenMill"] and winners["Ann-TarrenMill"][1].response, "Offspec",
    "winners of an item come from KART, matched by item id")
T.is_nil(winners["Bob-TarrenMill"], "a different item is not a winner of this one")
T.eq(#winners["Ann-TarrenMill"], 1, "bonus loot is not listed as an award of this item")

local companion = assert(io.open("RCCompanion.lua", "r")):read("*a")
T.truthy(not companion:find("LH_ADD", 1, true), "the companion award wrap does not send history")
T.truthy(not companion:find("OnAwardSuccess", 1, true), "the companion award wrap does not record history")

KARTTEST.RestoreRoster(rosterBefore)
KARTTEST.activeUnit = activeBefore
_G.C_ChatInfo.SendAddonMessage = sendBefore
