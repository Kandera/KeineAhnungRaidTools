-- Parallel loot history. RCLootCouncil still runs the session and keeps its own history.
-- This file only listens for the award events and syncs a second log. It must not wrap Award.
local addonName, KART = ...
KART.LH = KART.LH or {}
local LH = KART.LH
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")

LH.filters = { player = nil, playerIds = nil, reason = nil, search = "", hideBonus = false }

-- Drops, and refuses to import or sync, anything from before this morning.
-- 19 Aug 2026 00:00:00 UTC. RC stores dates as YYYY/MM/DD, which sorts as text.
local HISTORY_CUTOFF_DATE = "2026/08/19"
local HISTORY_CUTOFF_UNIX = 1787097600

local function BeforeCutoff(dateStr, unixTime)
    if type(dateStr) == "string" and dateStr:match("^%d%d%d%d/%d%d/%d%d$") then
        return dateStr < HISTORY_CUTOFF_DATE
    end
    if type(unixTime) == "number" then
        return unixTime < HISTORY_CUTOFF_UNIX
    end
    return false
end

local function RowBeforeCutoff(row)
    if type(row) ~= "table" then return false end
    return BeforeCutoff(row.dateStr, row.time)
end

local MAX_STORE = 5000
local MAX_BATCH = 150
local MAX_AGE = 14 * 24 * 60 * 60
local GATE_GRACE = 5
local GATE_MAX_PARK = 60
local ANSWER_COOLDOWN = 60
local SEP = "\001"
local ROW_SEP = "\002"
local ROW_FIELDS = {
    "id", "epoch", "time", "item", "winner", "reason", "boss", "class",
    "colorR", "colorG", "colorB", "difficulty", "difficultyID", "instance", "instanceID", "session",
    "votes", "gear1", "gear2", "responseID", "isAwardReason", "note", "owner",
    "dateStr", "timeStr", "instanceLabel",
}
local ROW_MIN = 16

local stash = nil
local generation = 0
local wasRunning = false
local runningFellAt = 0
local awardCounter = 0
local wasGrouped = false
local parked = {}
local answeredAt = {}

local function Split(s, sep)
    local out, startAt = {}, 1
    if s == nil then return out end
    while true do
        local a, b = string.find(s, sep, startAt, true)
        if not a then
            out[#out + 1] = string.sub(s, startAt)
            return out
        end
        out[#out + 1] = string.sub(s, startAt, a - 1)
        startAt = b + 1
    end
end

local function EmptyToNil(s)
    if s == nil or s == "" then return nil end
    return s
end

local function WipeMap(map)
    for k in pairs(map) do map[k] = nil end
end

function LH.ResetAwardState()
    stash = nil
    generation = 0
    wasRunning = false
    runningFellAt = 0
    awardCounter = 0
    wasGrouped = false
    WipeMap(parked)
    WipeMap(answeredAt)
end

function LH.EnsureStore()
    if type(KART_LootHistory) ~= "table" then KART_LootHistory = {} end
    local epoch = tonumber(KART_LootHistoryEpoch)
    if not epoch then
        epoch = 1
        KART_LootHistoryEpoch = 1
    end
    return KART_LootHistory, epoch
end

function LH.EncodeRow(row)
    row = row or {}
    local color = row.color or {}
    local values = {
        row.id, row.epoch, row.time, row.item, row.winner, row.reason, row.boss, row.class,
        color.r, color.g, color.b, row.difficulty, row.difficultyID, row.instance, row.instanceID,
        row.session, row.votes, row.gear1, row.gear2, row.responseID,
        row.isAwardReason and "1" or "", row.note, row.owner, row.dateStr, row.timeStr, row.instanceLabel,
    }
    local parts = {}
    for i = 1, #ROW_FIELDS do
        local v = values[i]
        parts[i] = v == nil and "" or tostring(v)
    end
    return table.concat(parts, SEP)
end

function LH.DecodeRow(payload)
    if type(payload) ~= "string" or payload == "" then return nil end
    local parts = Split(payload, SEP)
    if #parts < ROW_MIN then return nil end
    local r = tonumber(parts[9])
    local g = tonumber(parts[10])
    local b = tonumber(parts[11])
    return {
        id = EmptyToNil(parts[1]),
        epoch = tonumber(parts[2]),
        time = tonumber(parts[3]),
        item = parts[4] or "",
        winner = parts[5] or "",
        reason = parts[6] or "",
        boss = EmptyToNil(parts[7]),
        class = EmptyToNil(parts[8]),
        color = (r and g and b) and { r = r, g = g, b = b } or nil,
        difficulty = parts[12] or "",
        difficultyID = tonumber(parts[13]),
        instance = EmptyToNil(parts[14]),
        instanceID = tonumber(parts[15]),
        session = tonumber(parts[16]),
        votes = tonumber(parts[17]),
        gear1 = EmptyToNil(parts[18]),
        gear2 = EmptyToNil(parts[19]),
        responseID = EmptyToNil(parts[20]),
        isAwardReason = parts[21] == "1",
        note = EmptyToNil(parts[22]),
        owner = EmptyToNil(parts[23]),
        dateStr = EmptyToNil(parts[24]),
        timeStr = EmptyToNil(parts[25]),
        instanceLabel = EmptyToNil(parts[26]),
    }
end

local function Trim()
    while #KART_LootHistory > MAX_STORE do
        local oldest, oldestTime = 1, KART_LootHistory[1].time or 0
        for i = 2, #KART_LootHistory do
            local t = KART_LootHistory[i].time or 0
            if t < oldestTime then oldest, oldestTime = i, t end
        end
        table.remove(KART_LootHistory, oldest)
    end
end

function LH.Put(row)
    LH.EnsureStore()
    if type(row) ~= "table" or not row.id then return nil end
    for i, existing in ipairs(KART_LootHistory) do
        if existing.id == row.id then
            KART_LootHistory[i] = row
            return row
        end
    end
    KART_LootHistory[#KART_LootHistory + 1] = row
    Trim()
    return row
end

function LH.Checksum()
    local _, epoch = LH.EnsureStore()
    local ids = {}
    for _, row in ipairs(KART_LootHistory) do
        if (row.epoch or 1) == epoch and row.id then ids[#ids + 1] = row.id end
    end
    table.sort(ids)
    local h = 0
    for _, id in ipairs(ids) do
        for i = 1, #id do
            h = (h * 31 + string.byte(id, i)) % 0x7FFFFFFF
        end
    end
    return h
end

function LH.VisibleRows(filter)
    local _, epoch = LH.EnsureStore()
    local want = filter and filter ~= "" and KAUtil.CaseFold(filter) or nil
    local out = {}
    for _, row in ipairs(KART_LootHistory) do
        if (row.epoch or 1) == epoch then
            local winner = row.winner or ""
            if not want or string.find(KAUtil.CaseFold(winner), want, 1, true) then
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return out
end

local function MLRunning()
    local ml = _G.RCLootCouncilML
    return ml and ml.running and true or false
end

function LH.PollRunning()
    local running = MLRunning()
    if running and not wasRunning then generation = generation + 1 end
    if wasRunning and not running then runningFellAt = GetTime() + GATE_GRACE end
    wasRunning = running
    return running
end

local function InstanceFields()
    local name, _, difficultyID, difficultyName, _, _, _, mapID = GetInstanceInfo()
    if difficultyID == 0 then return nil, nil, nil, nil end
    return name, mapID, difficultyName, difficultyID
end

local function ColorOf(color)
    if type(color) ~= "table" then return nil end
    local r = color.r or color[1]
    local g = color.g or color[2]
    local b = color.b or color[3]
    if not (r and g and b) then return nil end
    return { r = r, g = g, b = b }
end

local function NewId()
    awardCounter = (awardCounter + 1) % 0x1000
    return string.format("%d-%03x", time(), awardCounter)
end

-- Fields RC's own JSON export reads off the history entry. Copied from the
-- RCMLLootHistorySend table so a later export matches that file.
local function CopyHistoryFields(into, history)
    if type(history) ~= "table" then return end
    if history.boss then into.boss = history.boss end
    if history.class then into.class = history.class end
    local color = ColorOf(history.color)
    if color then into.color = color end
    if history.id then into.rcId = history.id end
    if history.date then into.dateStr = history.date end
    if history.time then into.timeStr = history.time end
    if history.votes ~= nil then into.votes = history.votes end
    if history.itemReplaced1 then into.gear1 = history.itemReplaced1 end
    if history.itemReplaced2 then into.gear2 = history.itemReplaced2 end
    if history.responseID ~= nil then into.responseID = history.responseID end
    if history.isAwardReason ~= nil then into.isAwardReason = history.isAwardReason and true or false end
    if type(history.note) == "string" and history.note ~= "" then into.note = history.note end
    if history.owner then into.owner = history.owner end
    if history.instance then into.instanceLabel = history.instance end
    if history.response and history.response ~= "" then into.reason = history.response end
end

local function SendRow(row, replacedId)
    local payload = LH.EncodeRow(row)
    if replacedId then
        KASC:Send("LH_REPL:" .. replacedId .. SEP .. payload, nil, nil, { guaranteed = true })
    else
        KASC:Send("LH_ADD:" .. payload, nil, nil, { guaranteed = true })
    end
end

function LH.Flush()
    local pending = stash
    stash = nil
    if not pending then return end
    LH.PollRunning()
    local _, epoch = LH.EnsureStore()
    local instance, instanceID, difficulty, difficultyID = InstanceFields()
    local replaced
    for i = #KART_LootHistory, 1, -1 do
        local existing = KART_LootHistory[i]
        if existing.generation == generation and existing.session == pending.session
            and pending.session ~= nil then
            replaced = existing.id
            table.remove(KART_LootHistory, i)
            break
        end
    end
    local row = {
        id = NewId(),
        epoch = epoch,
        time = time(),
        item = pending.item or "",
        winner = pending.winner or "",
        reason = pending.reason or "",
        boss = pending.boss,
        class = pending.class,
        color = pending.color,
        difficulty = difficulty or "",
        difficultyID = difficultyID,
        instance = instance,
        instanceID = instanceID,
        session = pending.session,
        generation = generation,
        votes = pending.votes,
        gear1 = pending.gear1,
        gear2 = pending.gear2,
        responseID = pending.responseID,
        isAwardReason = pending.isAwardReason and true or false,
        note = pending.note,
        owner = pending.owner,
        dateStr = pending.dateStr,
        timeStr = pending.timeStr,
        instanceLabel = pending.instanceLabel,
        exported = false,
    }
    if pending.rcId then row.id = pending.rcId end
    LH.Put(row)
    SendRow(row, replaced)
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.OnAwardSuccess(session, winner, status, link, responseText)
    stash = {
        session = session,
        winner = winner or "",
        item = link or "",
        reason = responseText or "",
        status = status,
    }
    C_Timer.After(0, LH.Flush)
end

function LH.OnHistorySend(history, winner, session)
    LH._historyNoted = true
    history = history or {}
    local item = history.lootWon or ""
    local same = stash and stash.session == session and session ~= nil
        and stash.winner == (winner or "")
        and stash.item == item
    if same then
        CopyHistoryFields(stash, history)
        return
    end
    -- A bonus roll or auto-award is its own row. Leave a council award that is still
    -- waiting for the next frame in the stash.
    LH.PollRunning()
    local _, epoch = LH.EnsureStore()
    local instance, instanceID, difficulty, difficultyID = InstanceFields()
    local row = {
        id = NewId(),
        epoch = epoch,
        time = time(),
        item = item,
        winner = winner or "",
        reason = history.response or "",
        boss = history.boss,
        class = history.class,
        color = ColorOf(history.color),
        difficulty = difficulty or "",
        difficultyID = difficultyID,
        instance = instance,
        instanceID = instanceID,
        session = session,
        generation = generation,
        votes = history.votes,
        gear1 = history.itemReplaced1,
        gear2 = history.itemReplaced2,
        responseID = history.responseID,
        isAwardReason = history.isAwardReason and true or false,
        note = type(history.note) == "string" and history.note or nil,
        owner = history.owner,
        dateStr = history.date,
        timeStr = history.time,
        instanceLabel = history.instance,
        exported = false,
    }
    if history.id then row.id = history.id end
    LH.Put(row)
    SendRow(row, nil)
end

-- RC drops the history event when logging is off or the award reason says log = false.
-- Session awards are already stashed by RCMLAwardSuccess and flushed on their own.
-- Everything else (bonus roll, personal loot, auto award) is written here from the
-- arguments, before we care whether RC kept the row.
function LH.OnTrackWithoutHistory(winner, link, responseID, boss, reason, session, candData, owner)
    local item = link or ""
    if stash and session ~= nil and stash.session == session
        and stash.winner == (winner or "") and stash.item == item then
        if boss and not stash.boss then stash.boss = boss end
        if type(reason) == "table" then
            if reason.text and reason.text ~= "" then stash.reason = reason.text end
            stash.isAwardReason = true
            stash.responseID = reason.sort and (reason.sort - 400) or responseID
            stash.color = ColorOf(reason.color) or stash.color
        elseif responseID ~= nil then
            stash.responseID = responseID
        end
        if type(candData) == "table" then
            if candData.votes ~= nil then stash.votes = candData.votes end
            if type(candData.note) == "string" and candData.note ~= "" then stash.note = candData.note end
        end
        if owner and not stash.owner then stash.owner = owner end
        return
    end
    local responseText, responseId, isReason = "", responseID, false
    if type(reason) == "table" then
        responseText = reason.text or ""
        isReason = true
        if reason.sort then responseId = reason.sort - 400 end
    elseif type(responseID) == "string" then
        responseText = responseID
    end
    LH.OnHistorySend({
        lootWon = item,
        boss = boss,
        response = responseText,
        responseID = responseId,
        isAwardReason = isReason,
        color = type(reason) == "table" and reason.color or nil,
        votes = type(candData) == "table" and candData.votes or nil,
        note = type(candData) == "table" and candData.note or nil,
        owner = owner,
    }, winner, session)
end

function LH.HookTrackAndLog(ml)
    if not ml or ml._kartTrackHooked or type(ml.TrackAndLogLoot) ~= "function" then return end
    local orig = ml.TrackAndLogLoot
    ml.TrackAndLogLoot = function(self, winner, link, responseID, boss, reason, session, candData, owner)
        LH._historyNoted = false
        local ok, result = pcall(orig, self, winner, link, responseID, boss, reason, session, candData, owner)
        if not LH._historyNoted then
            LH.OnTrackWithoutHistory(winner, link, responseID, boss, reason, session, candData, owner)
        end
        if not ok then error(result, 0) end
        return result
    end
    ml._kartTrackHooked = true
end

local function UnitForSender(fullName)
    if type(fullName) ~= "string" or not KAUtil.IsFullNameInGroup(fullName) then return nil end
    local wantName, wantRealm = fullName:match("^([^%-]+)%-?(.*)$")
    if not wantName then return nil end
    wantName = KAUtil.CaseFold(wantName)
    wantRealm = KAUtil.CanonRealm(wantRealm)
    local ownRealm = KAUtil.CanonRealm(GetRealmName())
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name and KAUtil.CaseFold(name) == wantName then
            local have = KAUtil.CanonRealm(realm)
            if have == "" then have = ownRealm end
            local want = wantRealm == "" and ownRealm or wantRealm
            if want == have then return unit end
        end
    end
end

function LH.SenderMayLog(ctx)
    local unit = ctx and UnitForSender(ctx.sender)
    if not unit then return false end
    return KART.UnitLeads(unit) or KART.UnitAssists(unit)
end

local function SenderIsLeader(ctx)
    local unit = ctx and UnitForSender(ctx.sender)
    return unit and KART.UnitLeads(unit) or false
end

function LH.AcceptAdd(payload, ctx)
    if not LH.SenderMayLog(ctx) then return end
    local row = LH.DecodeRow(payload)
    if not row or not row.id or RowBeforeCutoff(row) or LH.IsDeleted(row.id) then return end
    LH.Put(row)
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.AcceptRepl(payload, ctx)
    if not LH.SenderMayLog(ctx) then return end
    local parts = Split(payload, SEP)
    local oldId = parts[1]
    if not oldId or oldId == "" then return end
    table.remove(parts, 1)
    local row = LH.DecodeRow(table.concat(parts, SEP))
    if not row or not row.id or RowBeforeCutoff(row) or LH.IsDeleted(row.id) then return end
    LH.EnsureStore()
    for i = #KART_LootHistory, 1, -1 do
        if KART_LootHistory[i].id == oldId then
            table.remove(KART_LootHistory, i)
            break
        end
    end
    LH.Put(row)
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.AcceptEpoch(payload, ctx)
    local epoch = tonumber(payload)
    if not epoch or not SenderIsLeader(ctx) then return end
    local _, mine = LH.EnsureStore()
    if epoch <= mine then return end
    KART_LootHistoryEpoch = epoch
    for i = #KART_LootHistory, 1, -1 do
        if (KART_LootHistory[i].epoch or 1) < epoch then table.remove(KART_LootHistory, i) end
    end
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.DeletedIds()
    if type(KART_LootHistoryDeleted) ~= "table" then KART_LootHistoryDeleted = {} end
    return KART_LootHistoryDeleted
end

function LH.SameWinner(stored, asked)
    if type(stored) ~= "string" or type(asked) ~= "string" then return false end
    if stored == asked then return true end
    local function short(n)
        return (n:match("^([^%-]+)")) or n
    end
    return short(stored) == short(asked)
end

local function IsBonusEntry(e)
    local id = e and e.responseID
    return id == "BONUSROLL" or id == "BONUS_ROLL"
end

function LH.RecentFor(name, limit)
    LH.EnsureStore()
    limit = limit or 5
    local pool = {}
    for _, e in ipairs(KART_LootHistory) do
        if LH.SameWinner(e.winner, name) and not IsBonusEntry(e)
            and not LH.IsDeleted(e.id) and not RowBeforeCutoff(e) then
            pool[#pool + 1] = e
        end
    end
    table.sort(pool, function(a, b) return (a.time or 0) > (b.time or 0) end)
    local out = {}
    for i = 1, math.min(limit, #pool) do
        local e = pool[i]
        out[i] = { item = e.item, reason = e.reason, dateStr = e.dateStr, color = e.color }
    end
    return out
end

function LH.WinnersOf(link)
    local want = type(link) == "string" and link:match("item:(%d+)")
    if not want then return {} end
    LH.EnsureStore()
    local out = {}
    for _, e in ipairs(KART_LootHistory) do
        local id = type(e.item) == "string" and e.item:match("item:(%d+)")
        if id == want and not IsBonusEntry(e) and not LH.IsDeleted(e.id) and not RowBeforeCutoff(e) then
            local name = e.winner or ""
            local color = e.color or {}
            out[name] = out[name] or {}
            out[name][#out[name] + 1] = {
                lootWon = e.item,
                response = e.reason or "",
                color = { color[1] or color.r or 1, color[2] or color.g or 1, color[3] or color.b or 1 },
            }
        end
    end
    return out
end

function LH.IsDeleted(id)
    return type(id) == "string" and id ~= "" and LH.DeletedIds()[id] == true
end

-- Drops one row and remembers the id, so a later catch-up cannot put it back.
function LH.Forget(id)
    if type(id) ~= "string" or id == "" then return end
    LH.DeletedIds()[id] = true
    LH.EnsureStore()
    for i = #KART_LootHistory, 1, -1 do
        if KART_LootHistory[i].id == id then table.remove(KART_LootHistory, i) end
    end
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.DeleteEntry(id)
    LH.Forget(id)
    if KART.UnitLeads("player") or KART.UnitAssists("player") then
        KASC:Send("LH_DEL:" .. id, nil, nil, { guaranteed = true })
    end
end

function LH.ConfirmDelete(id)
    if type(id) ~= "string" or id == "" or not KART.UI then return end
    if GameTooltip then GameTooltip:Hide() end
    StaticPopupDialogs["KART_LH_DELETE_CONFIRM"].text = KART.L.LH_DELETE_CONFIRM_TEXT
    StaticPopup_Show("KART_LH_DELETE_CONFIRM", nil, nil, id)
end

function LH.AcceptDelete(payload, ctx)
    if not LH.SenderMayLog(ctx) then return end
    local id = payload and payload:match("^([^" .. SEP .. "]+)")
    if not id or id == "" then return end
    LH.Forget(id)
end

function LH.Clear()
    if not KART.UnitLeads("player") then return false end
    local _, epoch = LH.EnsureStore()
    local nextEpoch = epoch + 1
    KART_LootHistoryEpoch = nextEpoch
    for i = #KART_LootHistory, 1, -1 do
        if (KART_LootHistory[i].epoch or 1) < nextEpoch then table.remove(KART_LootHistory, i) end
    end
    KASC:Send("LH_EPOCH:" .. nextEpoch, nil, nil, { guaranteed = true })
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
    return true
end

function LH.CatchUpRows(sinceTime)
    local _, epoch = LH.EnsureStore()
    local now = time()
    local rows = {}
    sinceTime = sinceTime or 0
    for _, row in ipairs(KART_LootHistory) do
        local when = row.time or 0
        if (row.epoch or 1) == epoch and when > sinceTime and (now - when) <= MAX_AGE
            and not RowBeforeCutoff(row) then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return (a.time or 0) < (b.time or 0) end)
    while #rows > MAX_BATCH do table.remove(rows, 1) end
    return rows
end

local function NewestTime()
    local _, epoch = LH.EnsureStore()
    local newest = 0
    for _, row in ipairs(KART_LootHistory) do
        if (row.epoch or 1) == epoch and (row.time or 0) > newest then newest = row.time end
    end
    return newest
end

function LH.RequestSync()
    local _, epoch = LH.EnsureStore()
    KASC:Send(string.format("LH_REQ:%d%s%d%s%d", epoch, SEP, LH.Checksum(), SEP, NewestTime()),
        nil, nil, { prio = "BULK", guaranteed = true })
end

function LH.OnGroupUpdate()
    local grouped = IsInGroup() or IsInRaid()
    if grouped and not wasGrouped then LH.RequestSync() end
    wasGrouped = grouped and true or false
end

local function GateOpen()
    LH.PollRunning()
    if MLRunning() then return false end
    return GetTime() >= (runningFellAt or 0)
end

local function Answer(payload, sender)
    local theirEpoch, theirSum, sinceTime = payload:match("^(%d+)" .. SEP .. "(%d+)" .. SEP .. "(%d+)$")
    theirEpoch, theirSum, sinceTime = tonumber(theirEpoch), tonumber(theirSum), tonumber(sinceTime)
    if not theirEpoch then return end
    local _, myEpoch = LH.EnsureStore()
    if theirEpoch ~= myEpoch then
        KASC:Send("LH_EPOCH:" .. myEpoch, "WHISPER", sender, { prio = "BULK", guaranteed = true })
    end
    if theirEpoch > myEpoch then
        if SenderIsLeader({ sender = sender }) then
            LH.AcceptEpoch(tostring(theirEpoch), { sender = sender })
        end
        return
    end
    if theirEpoch == myEpoch and theirSum == LH.Checksum() then return end
    local rows = LH.CatchUpRows(sinceTime)
    if #rows == 0 then return end
    local encoded = {}
    for i, row in ipairs(rows) do encoded[i] = LH.EncodeRow(row) end
    KASC:Send(string.format("LH_BATCH:%d%s%d%s%s", myEpoch, SEP, #rows, SEP, table.concat(encoded, ROW_SEP)),
        "WHISPER", sender, { prio = "BULK", guaranteed = true })
    answeredAt[sender] = GetTime()
end

local function Release(sender)
    local entry = parked[sender]
    if not entry then return end
    if GateOpen() or (GetTime() - entry.at) >= GATE_MAX_PARK then
        parked[sender] = nil
        if KAUtil.IsFullNameInGroup(sender) then Answer(entry.payload, sender) end
        return
    end
    C_Timer.After(1, function() Release(sender) end)
end

function LH.HandleRequest(payload, ctx)
    if not (ctx and ctx.sender and payload and payload:match("^%d+" .. SEP .. "%d+" .. SEP .. "%d+$")) then
        return
    end
    if not KAUtil.IsFullNameInGroup(ctx.sender) then return end
    local last = answeredAt[ctx.sender]
    if last and (GetTime() - last) < ANSWER_COOLDOWN then return end
    if not GateOpen() then
        local existing = parked[ctx.sender]
        if existing then
            existing.payload = payload
        else
            parked[ctx.sender] = { payload = payload, at = GetTime() }
            C_Timer.After(1, function() Release(ctx.sender) end)
        end
        return
    end
    Answer(payload, ctx.sender)
end

function LH.AcceptBatch(payload, ctx)
    if not LH.SenderMayLog(ctx) then return end
    local epochText, countText, rest = payload:match("^(%d+)" .. SEP .. "(%d+)" .. SEP .. "(.*)$")
    local epoch, count = tonumber(epochText), tonumber(countText)
    if not epoch or not count then return end
    local _, mine = LH.EnsureStore()
    if epoch < mine then return end
    if epoch > mine then
        if not SenderIsLeader(ctx) then return end
        LH.AcceptEpoch(tostring(epoch), ctx)
    end
    if not rest or rest == "" then return end
    local n = 0
    for piece in (rest .. ROW_SEP):gmatch("(.-)" .. ROW_SEP) do
        if n >= count or n >= MAX_BATCH then break end
        local row = LH.DecodeRow(piece)
        if row and row.id and not RowBeforeCutoff(row) and not LH.IsDeleted(row.id) then LH.Put(row) end
        n = n + 1
    end
    if LH.historyWindow and LH.historyWindow:IsShown() and LH.Refresh then LH.Refresh() end
end

function LH.RegisterRC(target)
    if LH._rcListening or not target or not target.RegisterMessage then return end
    target:RegisterMessage("RCMLAwardSuccess", function(_, session, winner, status, link, responseText)
        LH.OnAwardSuccess(session, winner, status, link, responseText)
    end)
    target:RegisterMessage("RCMLLootHistorySend", function(_, history, winner, _, _, _, session)
        LH.OnHistorySend(history, winner, session)
    end)
    LH.HookTrackAndLog(_G.RCLootCouncilML)
    LH._rcListening = true
end


local function GetItemNameFromLink(link)
    if not link or link == "" then return "" end
    return link:match("%[(.-)%]") or link
end

-- Applies the window's current player/reason/search filters and returns the matching
-- entries newest-first. Shared by the window renderer and the JSON export, which must
-- always agree on what "currently visible" means.
local function GetFilteredEntries()
    local filtered = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        -- filters.playerIds is the SET of identities one person is known by in this log: their
        -- winnerKey (GUID) for entries written since 2.6.0, and their plain display name for
        -- everything older. One person, several ids, because that is what a history spanning the
        -- GUID migration actually contains.
        --
        -- It used to be a single id, and LH.GetUniquePlayers produced one entry per DISTINCT id --
        -- so anybody with history on both sides of that migration appeared in the filter twice under
        -- the same name, and neither of the two showed more than half of what they had won.
        local ids = LH.filters.playerIds
        local matchPlayer = (not ids)
            or (e.winnerKey and e.winnerKey ~= "" and ids[e.winnerKey])
            or (e.winner and ids[e.winner])
        local matchReason = (not LH.filters.reason) or ((e.reason or "") == LH.filters.reason)
        local responseID = e.responseID
        local isBonus = responseID == "BONUSROLL" or responseID == "BONUS_ROLL"
        local matchBonus = not LH.filters.hideBonus or not isBonus
        local matchSearch = true
        if LH.filters.search ~= "" then
            local itemName = KAUtil.CaseFold(GetItemNameFromLink(e.item))
            local winner = KAUtil.CaseFold(e.winner or "")
            matchSearch = itemName:find(LH.filters.search, 1, true) ~= nil
                or winner:find(LH.filters.search, 1, true) ~= nil
        end
        if matchPlayer and matchReason and matchBonus and matchSearch then
            table.insert(filtered, e)
        end
    end
    table.sort(filtered, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return filtered
end

-- The same query under a name outside this file. The export dialog needs to COUNT what "everything"
-- would produce, and a second implementation of the filter rules would drift from this one.
LH.FilteredEntries = GetFilteredEntries

-- Every award still waiting to be exported, newest first.
--
-- Deliberately does NOT go through GetFilteredEntries. "Everything" is a view and may follow the
-- window's player/reason/search filters; this is bookkeeping. A filter-respecting cut would mark only
-- the filtered slice as exported and leave the rest of the same evening looking unexported forever --
-- silently, because the player who set the filter sees a plausible list either way.
--
-- Compared against false rather than tested for truthiness: an entry with no field at all was written
-- before this version and counts as already exported, and `not e.exported` would collapse the two.
function LH.UnexportedEntries()
    local out = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.exported == false then table.insert(out, e) end
    end
    table.sort(out, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return out
end

-- Marks a list as exported. Called from the dialog's button, never from opening it: the addon cannot
-- see whether the text was copied, let alone whether the WoWUtils import succeeded, so the only
-- honest moment is one the player chooses.
--
-- The chat line matters more than it looks. The dialog is about to be closed, and this line is what
-- tells the player later that they really did press the button -- the difference between "I think I
-- exported that" and a record.
-- Only entries at exactly false are marked and counted, for the same three-state reason as
-- LH.UnexportedEntries: an entry with no field already counts as exported, so touching it would count
-- it into a number the New side and the button label never showed -- and the chat line's whole job is
-- to agree with the button that was pressed.
--
-- The line goes out on every press, including the one that finds nothing left to do. Zero is an
-- answer, and a press with no line at all is the one case where the player is left with "I think I
-- pressed it" -- exactly the state this line exists to abolish.
function LH.MarkExported(entries)
    local n = 0
    for _, e in ipairs(entries or {}) do
        if e.exported == false then
            e.exported = true
            n = n + 1
        end
    end
    print("|cffff0000KART:|r " .. string.format(KART.L.LH_EXPORT_MARKED, n))
    LH.Refresh()
end

-- Every entry from `list` that is still present in KART_LootHistory, matched by table identity (not
-- by field, since two unrelated entries can otherwise look identical). This is what keeps the export
-- dialog's stashed f.markable honest at press time: a stashed render can outlive the entries it was
-- rendered from, because TrimHistory's 500-entry cap, the reassignment removal in LH.LogHistory and
-- in LH.HandleHistoryEntry, LH.RemoveHistoryForRoll's revoke path, a raid-wide wipe (LH.ClearHistory)
-- and an adopted epoch (LH.AdoptEpoch) can all drop an entry out of KART_LootHistory while the dialog
-- sits open with a reference to it. Filtering at the one place the list is actually used closes every
-- one of those doors at once, including any opened later, instead of chasing each removal site.
local function StillInHistory(list)
    local present = {}
    for _, e in ipairs(KART_LootHistory or {}) do present[e] = true end
    local out = {}
    for _, e in ipairs(list or {}) do
        if present[e] then table.insert(out, e) end
    end
    return out
end

local function JSONEscape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    -- Escape any remaining control characters (U+0000–U+001F) as \u00XX so the output is always
    -- valid JSON even if an item name or reason ever contains a stray control byte.
    s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", string.byte(c)) end)
    return s
end

local function JSONString(key, value)
    return string.format("\"%s\":\"%s\"", key, JSONEscape(value))
end

local function JSONNumber(key, value)
    return string.format("\"%s\":%d", key, value or 0)
end

-- Canonical English difficulty names for JSON export, keyed by Blizzard difficultyID (see
-- GetInstanceInfo/GetDifficultyInfo). The on-screen column stays localized; only the export is
-- normalized to English so a mixed-language raid still produces one consistent "instance" field.
-- Entries logged before difficultyID was tracked fall back to the stored string. History sync now
-- carries the difficultyID over the wire, so backfilled entries are English-canonical too.
local DIFFICULTY_EN = {
    [1]  = "Normal",          -- 5-player dungeon
    [2]  = "Heroic",          -- 5-player dungeon
    [3]  = "10 Player",       -- legacy raid
    [4]  = "25 Player",       -- legacy raid
    [5]  = "10 Player (Heroic)",
    [6]  = "25 Player (Heroic)",
    [7]  = "LFR",             -- legacy raid finder
    [8]  = "Mythic Keystone",
    [9]  = "40 Player",       -- legacy raid
    [14] = "Normal",          -- raid
    [15] = "Heroic",          -- raid
    [16] = "Mythic",          -- raid
    [17] = "LFR",             -- raid finder
    [23] = "Mythic",          -- 5-player dungeon
    [24] = "Timewalking",     -- dungeon
    [33] = "Timewalking",     -- raid
    [208] = "Delve",
}

-- Canonical English slot names for JSON export, keyed by INVTYPE_* token. Same reasoning as
-- DIFFICULTY_EN above: _G[token] would return the WoW *client-locale* slot name ("Kopf" on a
-- German client), so a mixed-language raid would produce inconsistent "equipLoc" fields. Mapping
-- the locale-independent token to its English name keeps the export English-canonical, matching
-- what an English client's RCLootCouncil export would contain.
local INVTYPE_EN = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_BODY = "Shirt",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back",
    INVTYPE_WEAPON = "One-Hand",
    INVTYPE_SHIELD = "Off Hand",
    INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held In Off-hand",
    INVTYPE_RANGED = "Ranged",
    INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Thrown",
    INVTYPE_RELIC = "Relic",
    INVTYPE_TABARD = "Tabard",
}

-- Canonical English item subtype for export, keyed by numeric classID/subClassID — locale-
-- independent, unlike C_Item.GetItemInfoInstant's localized itemSubType ("Platte" on a German
-- client). Same English-canonical reasoning as DIFFICULTY_EN/INVTYPE_EN. Covers armor and weapons
-- (the item classes that pass through Loot Council); anything else exports an empty subType rather
-- than leaking a localized name.
local SUBTYPE_EN = {
    [4] = { -- Armor
        [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate",
        [5] = "Cosmetic", [6] = "Shield",
    },
    [2] = { -- Weapon
        [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace",
        [6] = "Polearm", [7] = "Sword", [8] = "Sword", [9] = "Warglaive", [10] = "Staff",
        [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand",
        [20] = "Fishing Pole",
    },
}

local function SubTypeExport(classID, subClassID)
    local byClass = classID and SUBTYPE_EN[classID]
    return (byClass and subClassID and byClass[subClassID]) or ""
end

-- Localized difficulty name for on-screen display; falls back to the stored string for pre-id entries.
function LH.DifficultyDisplay(e)
    if e.difficultyID then
        local name = GetDifficultyInfo(e.difficultyID)
        if name and name ~= "" then return name end
    end
    return e.difficulty
end

-- Canonical English difficulty name for export; falls back to the stored (possibly localized) string.
function LH.DifficultyExport(e)
    return (e.difficultyID and DIFFICULTY_EN[e.difficultyID]) or e.difficulty or ""
end

-- =====================================================================
--  RCLootCouncil-compatible JSON export
-- =====================================================================
-- Mirrors the field set/order RCLootCouncil itself produces via its "Standard JSON output"
-- history export, so the result can be pasted into any tool built to read an RCLootCouncil
-- export (e.g. wowaudit). Field order matches LootHistory:ExportJSON. Values RC did not
-- send (a log=false award never fires RCMLLootHistorySend) stay empty rather than invented.
-- Respects the history window's current player/reason/search filters, same as RCLootCouncil's
-- own export (which only exports what's currently visible).
function LH.BuildRCLootCouncilJSON(entries)
    -- Defaults to what the window is showing, which is what RCLootCouncil's own export does and what
    -- every existing caller expects. The cut passes its own list instead.
    entries = entries or GetFilteredEntries()

    local objects = {}
    for i, e in ipairs(entries) do
        local itemID, subType, equipLoc = 0, "", ""
        if KAUtil.IsRealItemLink(e.item) then
            local id, _, subName, eLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(e.item)
            itemID = id or 0
            subType = (subName and subName ~= "") and subName or SubTypeExport(classID, subClassID)
            equipLoc = (eLoc and _G[eLoc]) or (eLoc and INVTYPE_EN[eLoc]) or ""
        end
        local exportId = e.id or ((e.time or 0) .. "-" .. i)
        local instanceField = e.instanceLabel
        if not instanceField or instanceField == "" then
            if e.instance and e.instance ~= "" then
                instanceField = e.instance .. ((e.difficulty and e.difficulty ~= "") and ("-" .. e.difficulty) or "")
            else
                instanceField = LH.DifficultyExport(e)
            end
        end

        local fields = {
            JSONString("player", e.winner),
            JSONString("date", e.dateStr or date("!%Y/%m/%d", e.time or 0)),
            JSONString("time", e.timeStr or date("!%H:%M:%S", e.time or 0)),
            JSONString("id", exportId),
            JSONNumber("itemID", itemID),
            JSONString("itemString", (KAUtil.GetItemString(e.item) or "")),
            JSONString("response", e.reason or ""),
            JSONNumber("votes", e.votes or 0),
            JSONString("class", e.class or ""),
            JSONString("instance", instanceField),
            JSONString("boss", e.boss or ""),
            JSONString("gear1", e.gear1 or ""),
            JSONString("gear2", e.gear2 or ""),
            JSONString("responseID", e.responseID ~= nil and tostring(e.responseID) or "0"),
            JSONString("isAwardReason", tostring(e.isAwardReason or false)),
            JSONString("rollType", "normal"),
            JSONString("subType", subType),
            JSONString("equipLoc", equipLoc),
            JSONString("note", e.note or ""),
            JSONString("owner", e.owner or "Unknown"),
            JSONString("itemName", GetItemNameFromLink(e.item)),
            JSONString("servertime", exportId:match("^(%d+)") or tostring(e.time or 0)),
        }
        table.insert(objects, "{" .. table.concat(fields, ",") .. "}")
    end

    return "[" .. table.concat(objects, ",") .. "]"
end

-- Recomputes everything the dialog displays from the history, in one place, so the open path, the tab
-- switch and the post-marking update cannot drift apart.
function LH.RefreshExportDialog()
    local f = LH.exportDialog
    if not f then return end

    local newOnes  = LH.UnexportedEntries()
    local filtered = LH.FilteredEntries()

    f.btnNew.text:SetText(string.format(KART.L.LH_EXPORT_TAB_NEW, #newOnes))
    f.btnAll.text:SetText(string.format(KART.L.LH_EXPORT_TAB_ALL, #filtered))

    local r, g, b = KART.UI:AccentColor()
    local active, idle = (f.mode == "new") and f.btnNew or f.btnAll,
                         (f.mode == "new") and f.btnAll or f.btnNew
    active:SetBackdropBorderColor(r, g, b, 1)
    idle:SetBackdropBorderColor(0, 0, 0, 1)

    local shown = (f.mode == "new") and newOnes or filtered
    local json  = LH.BuildRCLootCouncilJSON(shown)
    f.editBox.text = json
    f.editBox:SetText(json)

    -- The list the mark button will mark: the one that was actually rendered and counted here, kept
    -- on the frame rather than queried again when the button is pressed. LH.Refresh does not reach
    -- this dialog, so an award logged while it sits open is in neither the JSON on screen nor the
    -- count on the button -- and a fresh query at click time would mark it anyway, recording as
    -- exported something that was never in the text the player copied. What is marked and what was
    -- copied cannot be allowed to drift apart.
    f.markable = newOnes

    -- The count rides in the label so the button cannot be read as "mark everything".
    f.btnMark.text:SetText(string.format(KART.L.LH_EXPORT_MARK, #newOnes))
    f.btnMark:SetShown(f.mode == "new")
    -- Disabled rather than hidden at zero: a button that disappears raises the question of whether it
    -- was missed. Dimming the label too, because the backdrop does not grey itself out.
    if #newOnes > 0 then
        f.btnMark:Enable()
        f.btnMark.text:SetTextColor(1, 1, 1)
    else
        f.btnMark:Disable()
        f.btnMark.text:SetTextColor(0.4, 0.4, 0.4)
    end
end

function LH.SetExportMode(mode)
    if not LH.exportDialog then return end
    LH.exportDialog.mode = mode
    LH.RefreshExportDialog()
end

-- Hand-rolled dialog (not a StaticPopup, same reasoning as LC.ShowOfficerNoteDialog in
-- LootCouncil.lua) showing the export text in a read-only, pre-selected edit box so the user
-- can Ctrl+C it out — WoW addons have no filesystem access to write a file directly.
function LH.ShowExportDialog()
    if not LH.exportDialog then
        local f = CreateFrame("Frame", "KART_LHExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 320)
        f:SetPoint("CENTER")
        KART.UI:RegisterStrataFrame(f, true)
        KART.UI:ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        -- Clamped, like every Blizzard frame. Without it a window can be dragged past the edge of the
        -- game window -- reported from a live test in windowed mode on two monitors, where the desktop
        -- beyond the edge is real screen and nothing stops the drag. KAUI.IsSavedPosOnScreen already
        -- refuses to RESTORE an off-screen position; this is the other half.
        f:SetClampedToScreen(true)
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        KART.RegisterEscapeFrame(f)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetText(KART.L.LH_EXPORT_TITLE)
        KART.UI:RegisterLabel(f.title)

        -- The two sides, as buttons rather than a dropdown: both counts have to be readable without
        -- opening anything. Together they are the only place the player can see whether the
        -- bookkeeping still adds up -- "New (0) · All (487)" means everything is exported, while
        -- "New (0) · All (0)" means the log was cleared. Two numbers, two cases, no extra text.
        f.btnNew = KART.UI:CreateModernButton(f, "")
        f.btnNew:SetSize(120, 22)
        f.btnNew:SetPoint("TOPLEFT", 15, -32)
        f.btnNew:SetScript("OnClick", function() LH.SetExportMode("new") end)

        f.btnAll = KART.UI:CreateModernButton(f, "")
        f.btnAll:SetSize(120, 22)
        f.btnAll:SetPoint("LEFT", f.btnNew, "RIGHT", 6, 0)
        f.btnAll:SetScript("OnClick", function() LH.SetExportMode("all") end)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOP", 0, -58)
        f.hint:SetText(KART.L.LH_EXPORT_HINT)
        f.hint:SetTextColor(0.6, 0.6, 0.6)
        KART.UI:RegisterLabel(f.hint)

        -- Same inset/border colors as KART.UI:CreateStyledEditBox (the multi-line export box lives
        -- inside a ScrollFrame, so the visual box is this frame); focus accent mirrored below.
        local scrollBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
        scrollBG:SetPoint("TOPLEFT", 15, -78)
        scrollBG:SetPoint("BOTTOMRIGHT", -15, 44)
        KART.UI:SetPixelBackdrop(scrollBG, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        scrollBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
        scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
        KART.UI:ApplyRoundedMask(scrollBG, KAUI.CORNER_RADIUS_LG)

        local scroll = CreateFrame("ScrollFrame", "KART_LHExportScroll", scrollBG, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -22, 4)

        local exportScrollThumb = KART.UI:StripScrollbarTextures(scroll)
        if exportScrollThumb then exportScrollThumb:SetSize(6, 16) end
        KART.UI:RegisterAccentTexture(exportScrollThumb, 0.6)

        f.editBox = CreateFrame("EditBox", "KART_LHExportEditBox", scroll)
        f.editBox:SetWidth(420)
        f.editBox:SetMultiLine(true)
        f.editBox:SetAutoFocus(false)
        f.editBox:SetFontObject("GameFontHighlightSmall")
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Read-only: revert any edit attempt back to the export text instead of blocking input
        -- (there's no native read-only flag on EditBox), so selecting/copying still works freely.
        f.editBox:SetScript("OnTextChanged", function(self)
            if self.text and self:GetText() ~= self.text then
                self:SetText(self.text)
                self:HighlightText()
            end
        end)
        f.editBox:SetScript("OnEditFocusGained", function()
            local r, g, b = KART.UI:AccentColor()
            scrollBG:SetBackdropBorderColor(r, g, b, 1)
        end)
        f.editBox:SetScript("OnEditFocusLost", function()
            scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
        end)
        scroll:SetScrollChild(f.editBox)

        local btnClose = KART.UI:CreateModernButton(f, CLOSE) ---@diagnostic disable-line: undefined-global
        btnClose:SetSize(120, 26)
        btnClose:SetPoint("BOTTOM", 0, 12)
        btnClose:SetScript("OnClick", function() f:Hide() end)

        f.btnMark = KART.UI:CreateModernButton(f, "")
        f.btnMark:SetSize(190, 26)
        f.btnMark:SetPoint("BOTTOMLEFT", 15, 12)
        f.btnMark:SetScript("OnClick", function()
            -- Filtered through StillInHistory at the moment of the click, not trusted as stashed: any
            -- entry f.markable held that has since left KART_LootHistory is dropped here rather than
            -- marked or counted. Skipping LH.MarkExported entirely when nothing survives (rather than
            -- calling it with an empty list) matters because that call is the one that prints a count,
            -- and a press that never had anything real to mark must not print one. RefreshExportDialog
            -- still runs either way, so the labels catch up to the current state regardless.
            local markable = f.markable and StillInHistory(f.markable)
            if markable and #markable > 0 then LH.MarkExported(markable) end
            LH.RefreshExportDialog()
        end)

        LH.exportDialog = f
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    local f = LH.exportDialog
    f.mode = "new"
    LH.RefreshExportDialog()
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end

-- Returns the distinct winners as { id, label } entries. `id` is the stable identity (winnerKey
-- GUID when present, else the stored display name for legacy entries) and is what the filter stores;
-- `label` is the current resolved display — NSRT nickname / short name via Identity.ResolveDisplayName
-- — so the same person's entries logged under different display names collapse to one filter option.
-- One entry per PERSON, not per identity. Each carries every id that person is known by in this log:
-- their winnerKey for entries written since the GUID migration (2.6.0) and their display name for
-- everything older. Grouping by the displayed label is what makes the two halves one line in the
-- filter — and grouping by id, as this used to, put the same name in the list twice with half a
-- history behind each.
--
-- `id` is kept as a stable scalar because LH.Refresh builds its page-reset signature out of it; the
-- set beside it is what the filter actually matches on.
-- One entry per person for the history window's player filter.
--
-- Grouped by the DISPLAYED NAME, and that choice has a cost worth stating (B109). Two different
-- people who were ever logged under the same name -- somebody leaves and a later raider brings a
-- character of that name -- collapse into one filter entry showing both their histories.
--
-- Kept that way on purpose: the filter is a list of names a person picks from, so the name is the
-- only axis they can reason about, and grouping by key instead is precisely what B98 was. That bug
-- put ONE raider in the list twice, split their record down the middle, and gave no sign the other
-- half existed -- a wrong answer to the question actually being asked ("what has this person had?").
-- The namesake case answers that question too widely rather than too narrowly, is visible in the
-- rows themselves (they carry dates and items), and needs a name to be reused inside the 500 entries
-- the history keeps at all.
function LH.GetUniquePlayers()
    local byLabel, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local key = (e.winnerKey and e.winnerKey ~= "" and e.winnerKey) or nil
        local id = key or e.winner
        if id and id ~= "" then
            local label = e.winner
            if key then
                -- ResolveDisplayName answers with the KEY itself when it cannot place somebody --
                -- which is every raider who has since left the guild, since they are neither in the
                -- group nor in the name cache. Taking that as a label put raw GUIDs in the filter
                -- list ("Player-1096-0A1B2C3D") while the name they were logged under sat unused in
                -- the entry. Only a real answer wins over it.
                local resolved = KASC.Identity.ResolveDisplayName(key)
                if resolved and resolved ~= key and resolved ~= "?" then label = resolved end
            end
            label = label or e.winner or id
            local group = byLabel[label]
            if not group then
                group = { id = id, label = label, ids = {} }
                byLabel[label] = group
                table.insert(list, group)
            end
            group.ids[id] = true
            -- A keyed entry also answers to the name it was logged under, so a later legacy row for
            -- the same person still lands in this group rather than opening a second one.
            if key and e.winner and e.winner ~= "" then group.ids[e.winner] = true end
        end
    end
    table.sort(list, function(a, b) return (a.label or "") < (b.label or "") end)
    return list
end

function LH.GetUniqueReasons()
    local seen, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local r = e.reason or ""
        if not seen[r] then
            seen[r] = true
            table.insert(list, r)
        end
    end
    table.sort(list)
    return list
end

if KART.UI then
    KART.UI:RegisterStaticPopup("KART_LH_CLEAR_CONFIRM", {
        text = "Really clear loot history?", -- overwritten with KART.L.LH_CLEAR_CONFIRM_TEXT before show
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            if not LH.Clear() then
                print("|cffff0000KART:|r " .. KART.L.LH_CLEAR_NEEDS_OWNER)
            end
        end,
    })
    KART.UI:RegisterStaticPopup("KART_LH_DELETE_CONFIRM", {
        text = "Delete this loot history entry?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, data)
            LH.DeleteEntry(data)
        end,
    })
end

-- =====================================================================
--  Window
-- =====================================================================

function LH.CreateWindow()
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(720, 430)
    f:SetPoint("CENTER")
    KART.UI:RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.UI:ApplyPopupArtwork(f)
    -- Clamped, like every Blizzard frame. Without it a window can be dragged past the edge of the
    -- game window -- reported from a live test in windowed mode on two monitors, where the desktop
    -- beyond the edge is real screen and nothing stops the drag. KAUI.IsSavedPosOnScreen already
    -- refuses to RESTORE an off-screen position; this is the other half.
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    KART.RegisterEscapeFrame(f)
    f:Hide()

    -- Header zone: title on the artwork with an accent line below, matching the main window
    -- (the old flat gray header bar is gone; hdr survives as an invisible layout strip for
    -- the title and close button).
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    hdr:RegisterForDrag("LeftButton")
    hdr:SetScript("OnDragStart", function() f:StartMoving() end)
    hdr:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = f:GetLeft(), y = f:GetTop()}
        end
    end)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", 16, 0)
    f.title:SetText(KART.L.LH_TITLE)
    KART.UI:RegisterLabel(f.title)
    KART.UI:CreateHeaderLine(f, -28)

    local closeBtn = KART.UI:CreateHeaderIconButton(hdr, "×", function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", -4, 0)

    -- The artwork background does not survive free resizing, same as the main window.
    -- Scale the whole frame. Apply it when the drag ends: scaling mid-drag moves the
    -- thumb under the cursor.
    local function ApplyHistoryScale()
        local pct = (KART_Settings and KART_Settings.lcHistoryScale) or 100
        f:SetScale(pct / 100)
    end
    f.scaleSlider = KART.UI:CreateSettingsSlider(hdr, {
        name = "KART_LHScaleSlider",
        label = KART.L.LH_SCALE,
        min = 50, max = 150,
        store = function()
            if not KART_Settings then KART_Settings = {} end
            return KART_Settings
        end,
        key = "lcHistoryScale",
        y = 0,
        tooltip = KART.L.LH_SCALE_TIP,
        onChanged = function()
            if f.scaleSlider and f.scaleSlider.isDragging then return end
            ApplyHistoryScale()
        end,
    })
    f.scaleSlider:ClearAllPoints()
    f.scaleSlider:SetPoint("RIGHT", closeBtn, "LEFT", -56, 0)
    f.scaleSlider.title:ClearAllPoints()
    f.scaleSlider.title:SetPoint("RIGHT", f.scaleSlider, "LEFT", -6, 0)
    f.scaleSlider:SetValue((KART_Settings and KART_Settings.lcHistoryScale) or 100)
    f.scaleSlider:HookScript("OnMouseUp", ApplyHistoryScale)

    -- Filter row: item search + player filter + reason filter + reset
    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("TOPLEFT", 10, -32)
    searchHint:SetText(KART.L.LH_SEARCH_LABEL)
    searchHint:SetTextColor(0.55, 0.55, 0.55)
    KART.UI:RegisterLabel(searchHint)

    local searchBox = CreateFrame("EditBox", "KART_LHSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", 10, -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    KART.UI:SetPixelBackdrop(searchBox, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    searchBox:SetBackdropColor(0, 0, 0, 0.5)
    searchBox:SetTextInsets(5, 5, 0, 0)
    searchBox:SetMaxLetters(40)
    KART.UI:ApplyRoundedMask(searchBox, KAUI.CORNER_RADIUS_SM)
    KART.UI:RegisterEditBox(searchBox)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        LH.filters.search = KAUtil.CaseFold(self:GetText())
        LH.Refresh()
    end)
    f.searchBox = searchBox

    local btnPlayerFilter = KART.UI:CreateModernButton(f, KART.L.LH_FILTER_ALL_PLAYERS)
    btnPlayerFilter:SetSize(105, 22)
    btnPlayerFilter:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    btnPlayerFilter:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(KART.L.LH_FILTER_PLAYER)
            rootDescription:CreateButton(KART.L.LH_FILTER_ALL_PLAYERS, function()
                LH.filters.player, LH.filters.playerIds = nil, nil
                self.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
                LH.Refresh()
            end)
            for _, p in ipairs(LH.GetUniquePlayers()) do
                rootDescription:CreateButton(p.label, function()
                    LH.filters.player, LH.filters.playerIds = p.id, p.ids
                    self.text:SetText(p.label)
                    LH.Refresh()
                end)
            end
        end)
    end)
    f.btnPlayerFilter = btnPlayerFilter

    local btnReasonFilter = KART.UI:CreateModernButton(f, KART.L.LH_FILTER_ALL_REASONS)
    btnReasonFilter:SetSize(105, 22)
    btnReasonFilter:SetPoint("LEFT", btnPlayerFilter, "RIGHT", 6, 0)
    btnReasonFilter:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(KART.L.LH_FILTER_REASON)
            rootDescription:CreateButton(KART.L.LH_FILTER_ALL_REASONS, function()
                LH.filters.reason = nil
                self.text:SetText(KART.L.LH_FILTER_ALL_REASONS)
                LH.Refresh()
            end)
            for _, r in ipairs(LH.GetUniqueReasons()) do
                local label = (r == "") and KART.L.LH_NO_REASON or r
                rootDescription:CreateButton(label, function()
                    LH.filters.reason = r
                    self.text:SetText(label)
                    LH.Refresh()
                end)
            end
        end)
    end)
    f.btnReasonFilter = btnReasonFilter

    local function BonusButtonText()
        return LH.filters.hideBonus and KART.L.LH_BONUS_SHOW or KART.L.LH_BONUS_HIDE
    end
    local btnBonus = KART.UI:CreateModernButton(f, BonusButtonText())
    btnBonus:SetSize(108, 22)
    btnBonus:SetPoint("LEFT", btnReasonFilter, "RIGHT", 6, 0)
    btnBonus:SetScript("OnClick", function(self)
        LH.filters.hideBonus = not LH.filters.hideBonus
        self.text:SetText(BonusButtonText())
        LH.Refresh()
    end)
    f.btnBonus = btnBonus

    local btnReset = KART.UI:CreateModernButton(f, KART.L.LH_BTN_RESET_FILTERS)
    btnReset:SetSize(56, 22)
    btnReset:SetPoint("LEFT", btnBonus, "RIGHT", 6, 0)
    btnReset:SetScript("OnClick", function()
        LH.filters.player, LH.filters.playerIds = nil, nil
        LH.filters.reason = nil
        LH.filters.search = ""
        LH.filters.hideBonus = false
        searchBox:SetText("")
        btnPlayerFilter.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
        btnReasonFilter.text:SetText(KART.L.LH_FILTER_ALL_REASONS)
        btnBonus.text:SetText(BonusButtonText())
        LH.Refresh()
    end)
    f.btnReset = btnReset

    -- Column headers
    local hDate = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDate:SetPoint("TOPLEFT", 10, -78)
    hDate:SetText(KART.L.LH_COL_DATE)
    KART.UI:RegisterLabel(hDate)

    local hPlayer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPlayer:SetPoint("TOPLEFT", 80, -78)
    hPlayer:SetText(KART.L.LH_COL_PLAYER)
    KART.UI:RegisterLabel(hPlayer)

    local hItem = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hItem:SetPoint("TOPLEFT", 172, -78)
    hItem:SetText(KART.L.LH_COL_ITEM)
    KART.UI:RegisterLabel(hItem)

    local hDifficulty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDifficulty:SetPoint("TOPLEFT", 368, -78)
    hDifficulty:SetText(KART.L.LH_COL_DIFFICULTY)
    KART.UI:RegisterLabel(hDifficulty)

    local hReason = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hReason:SetPoint("TOPLEFT", 440, -78)
    hReason:SetText(KART.L.LH_COL_REASON)
    KART.UI:RegisterLabel(hReason)

    local hNote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hNote:SetPoint("TOPLEFT", 548, -78)
    hNote:SetText(KART.L.LH_COL_NOTE)
    KART.UI:RegisterLabel(hNote)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.22, 0.22, 0.22, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 5, -92)
    divider:SetPoint("TOPRIGHT", -5, -92)

    -- Scrollable row area
    local scrollBG = CreateFrame("Frame", nil, f)
    scrollBG:SetPoint("TOPLEFT", 5, -95)
    scrollBG:SetPoint("BOTTOMRIGHT", -5, 34)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LHScroll", scrollBG, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT"); scrollFrame:SetPoint("BOTTOMRIGHT", -20, 0)
    -- Pagination fits every page to the visible area, so there's no inner scroll — disable the
    -- mouse wheel so it can't drag the (oversized, vestigial) child up into empty space.
    scrollFrame:EnableMouseWheel(false)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(680, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.UI:StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end
    KART.UI:RegisterAccentTexture(thumb, 0.6)

    f.scrollChild = scrollChild
    f.scrollFrame = scrollFrame
    f.rows        = {}

    -- Empty-state label
    f.emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.emptyLabel:SetPoint("TOP", 0, -20)
    f.emptyLabel:SetText(KART.L.LH_EMPTY)
    f.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    f.emptyLabel:Hide()
    KART.UI:RegisterLabel(f.emptyLabel)

    -- Footer: entry count + clear button
    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countText:SetPoint("BOTTOMLEFT", 10, 12)
    f.countText:SetTextColor(0.6, 0.6, 0.6)
    KART.UI:RegisterLabel(f.countText)

    local btnClear = KART.UI:CreateModernButton(f, KART.L.LH_BTN_CLEAR)
    btnClear:SetSize(140, 24)
    btnClear:SetPoint("BOTTOMRIGHT", -10, 8)
    btnClear:SetScript("OnClick", function()
        StaticPopupDialogs["KART_LH_CLEAR_CONFIRM"].text = KART.L.LH_CLEAR_CONFIRM_TEXT
        StaticPopup_Show("KART_LH_CLEAR_CONFIRM")
    end)

    local btnExport = KART.UI:CreateModernButton(f, KART.L.LH_BTN_EXPORT_JSON, KART.L.LH_BTN_EXPORT_JSON_TIP)
    btnExport:SetSize(150, 24)
    btnExport:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMLEFT", -6, 0)
    btnExport:SetScript("OnClick", function() LH.ShowExportDialog() end)

    -- Pagination controls, anchored just left of the export button and growing leftward, so they
    -- never collide with the right-hand buttons regardless of their localized widths. The list uses
    -- a fit-to-window page size (see LH.Refresh) and so never scrolls — Prev/Next page through it.
    f.nextPageBtn = KART.UI:CreateModernButton(f, ">")
    f.nextPageBtn:SetSize(24, 22)
    f.nextPageBtn:SetPoint("RIGHT", btnExport, "LEFT", -10, -1)
    f.nextPageBtn:SetScript("OnClick", function()
        LH.currentPage = (LH.currentPage or 1) + 1
        LH.Refresh() -- clamped inside Refresh
    end)

    f.pageIndicator = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pageIndicator:SetSize(70, 14)
    f.pageIndicator:SetJustifyH("CENTER")
    f.pageIndicator:SetPoint("RIGHT", f.nextPageBtn, "LEFT", -6, 1)
    f.pageIndicator:SetTextColor(0.6, 0.6, 0.6)

    f.prevPageBtn = KART.UI:CreateModernButton(f, "<")
    f.prevPageBtn:SetSize(24, 22)
    f.prevPageBtn:SetPoint("RIGHT", f.pageIndicator, "LEFT", -6, -1)
    f.prevPageBtn:SetScript("OnClick", function()
        LH.currentPage = math.max(1, (LH.currentPage or 1) - 1)
        LH.Refresh()
    end)

    LH.historyWindow = f

    -- Restore saved position
    local pos = KART_Settings and KART_Settings.lcHistoryWindowPos
    if pos and type(pos) == "table" and KAUI.IsSavedPosOnScreen(pos.x, pos.y) then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    return f
end

-- =====================================================================
--  Refresh / Toggle
-- =====================================================================

function LH.Refresh()
    local f = LH.historyWindow
    if not f then return end

    local filtered = GetFilteredEntries()

    local total = #(KART_LootHistory or {})
    f.countText:SetText(string.format(KART.L.LH_COUNT_FORMAT, #filtered, total))
    f.emptyLabel:SetShown(#filtered == 0)

    -- Fit-to-window page size from the visible row area (26px stride) so the list never needs an
    -- inner scrollbar. Cached once the frame has a real height (the first Refresh runs pre-Show, so
    -- GetHeight is 0 then); 11 until then — its true value at the default window size, so even that
    -- first pre-show render is already correct.
    if (not f.pageSize) and f.scrollFrame then
        local h = f.scrollFrame:GetHeight()
        if h and h > 0 then f.pageSize = math.max(1, math.floor(h / 26)) end
    end
    local pageSize = f.pageSize or 11

    -- Snap back to the first (newest) page whenever the active filter/search changes; Prev/Next move
    -- within the same result set and leave the signature untouched, so they don't trigger a reset.
    local sig = (LH.filters.player or "") .. "\1" .. (LH.filters.reason or "") .. "\1"
        .. (LH.filters.search or "") .. "\1" .. (LH.filters.hideBonus and "1" or "0")
    if sig ~= LH._lastFilterSig then
        LH.currentPage = 1
        LH._lastFilterSig = sig
    end

    local totalPages = math.max(1, math.ceil(#filtered / pageSize))
    LH.currentPage = math.min(math.max(LH.currentPage or 1, 1), totalPages)
    local startIdx = (LH.currentPage - 1) * pageSize

    if totalPages > 1 then
        f.pageIndicator:SetText(string.format(KART.L.LH_PAGE_INDICATOR, LH.currentPage, totalPages))
        f.pageIndicator:Show()
        f.prevPageBtn:Show(); f.nextPageBtn:Show()
        local pc = (LH.currentPage > 1) and 1 or 0.35
        f.prevPageBtn.text:SetTextColor(pc, pc, pc)
        local nc = (LH.currentPage < totalPages) and 1 or 0.35
        f.nextPageBtn.text:SetTextColor(nc, nc, nc)
    else
        f.pageIndicator:Hide()
        f.prevPageBtn:Hide(); f.nextPageBtn:Hide()
    end

    local pageCount = 0
    for i = 1, pageSize do
        local e = filtered[startIdx + i]
        if not e then break end
        pageCount = i
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.scrollChild)
            row:SetHeight(24)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.dateText)
            row.dateText:SetPoint("LEFT", 6, 0)
            row.dateText:SetWidth(68)
            row.dateText:SetJustifyH("LEFT")

            row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.playerText)
            row.playerText:SetPoint("LEFT", 76, 0)
            row.playerText:SetWidth(88)
            row.playerText:SetJustifyH("LEFT")

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 166, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.itemText)
            row.itemText:SetPoint("LEFT", 188, 0)
            row.itemText:SetWidth(176)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.difficultyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.difficultyText)
            row.difficultyText:SetPoint("LEFT", 368, 0)
            row.difficultyText:SetWidth(68)
            row.difficultyText:SetJustifyH("LEFT")
            row.difficultyText:SetTextColor(0.7, 0.7, 0.7)

            row.reasonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.reasonText)
            row.reasonText:SetPoint("LEFT", 440, 0)
            row.reasonText:SetWidth(100)
            row.reasonText:SetJustifyH("LEFT")
            row.reasonText:SetWordWrap(false)

            row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.noteText)
            row.noteText:SetPoint("LEFT", 548, 0)
            row.noteText:SetPoint("RIGHT", -24, 0)
            row.noteText:SetJustifyH("LEFT")
            row.noteText:SetWordWrap(false)
            row.noteText:SetTextColor(0.75, 0.75, 0.75)

            -- Mouse belongs to the column, not the row. The item tooltip only opens
            -- over the item, without the equipped-gear comparison. The note tooltip
            -- only opens over the note.
            row.itemHit = CreateFrame("Frame", nil, row)
            row.itemHit:SetPoint("LEFT", 160, 0)
            row.itemHit:SetSize(200, 24)
            row.itemHit:EnableMouse(true)
            row.itemHit:SetScript("OnEnter", function(self)
                local link = self:GetParent().itemLink
                if not KAUtil.IsRealItemLink(link) then return end
                -- Set before SetHyperlink: FinalizeItemTooltip reads this and skips the
                -- equipped-gear comparison. Shift-compare still asks for it, so clear
                -- afterwards as well. OnHide resets the flag.
                if GameTooltip_SuppressAutomaticCompareItem then
                    GameTooltip_SuppressAutomaticCompareItem(GameTooltip)
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
                if TooltipComparisonManager then TooltipComparisonManager:Clear(GameTooltip) end
            end)
            row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row.noteHit = CreateFrame("Frame", nil, row)
            row.noteHit:SetPoint("LEFT", 548, 0)
            row.noteHit:SetPoint("RIGHT", row, "RIGHT", -24, 0)
            row.noteHit:SetHeight(24)
            row.noteHit:EnableMouse(true)
            row.noteHit:SetScript("OnEnter", function(self)
                local note = self:GetParent().note
                if type(note) ~= "string" or note == "" then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText((note:gsub("|", "||")), 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row.noteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row.deleteBtn = CreateFrame("Button", nil, row)
            row.deleteBtn:SetSize(18, 18)
            row.deleteBtn:SetPoint("RIGHT", -2, 0)
            row.deleteBtn.text = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.deleteBtn.text:SetPoint("CENTER")
            row.deleteBtn.text:SetText("×")
            row.deleteBtn:SetScript("OnClick", function(self)
                LH.ConfirmDelete(self:GetParent().entryId)
            end)
            row.deleteBtn:SetScript("OnEnter", function(self)
                self.text:SetTextColor(KART.UI:AccentColor())
            end)
            row.deleteBtn:SetScript("OnLeave", function(self)
                self.text:SetTextColor(1, 1, 1)
            end)

            f.rows[i] = row
        end

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        local lr, lg, lb = KART.UI:GetRowStripeColor()
        row.bg:SetColorTexture(lr, lg, lb, i % 2 == 0 and 0.35 or 0.1)

        row.dateText:SetText(date("%d.%m %H:%M", e.time or 0))

        local nr, ng, nb = 0.8, 0.8, 0.8
        if e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class] then
            nr, ng, nb = RAID_CLASS_COLORS[e.class].r, RAID_CLASS_COLORS[e.class].g, RAID_CLASS_COLORS[e.class].b
        end
        row.playerText:SetText(e.winner)
        row.playerText:SetTextColor(nr, ng, nb)

        row.itemLink = e.item
        if KAUtil.IsRealItemLink(e.item) then
            local itemID = C_Item.GetItemInfoInstant(e.item)
            local icon = itemID and C_Item.GetItemIconByID(itemID)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:Show()
            row.itemText:SetText(e.item)
        else
            row.icon:Hide()
            row.itemText:SetText(e.item ~= "" and e.item or "???")
        end

        local diffName = LH.DifficultyDisplay(e)
        row.difficultyText:SetText((diffName and diffName ~= "") and diffName or "—")

        if e.reason and e.reason ~= "" then
            local c = e.color
            if c then
                row.reasonText:SetText(string.format("|cff%02x%02x%02x%s|r",
                    math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), e.reason))
            else
                row.reasonText:SetText(e.reason)
            end
        else
            row.reasonText:SetText("|cff666666" .. KART.L.LH_NO_REASON .. "|r")
        end

        row.entryId = e.id
        row.note = e.note
        row.noteText:SetText(((e.note or ""):gsub("|", "||")))
    end

    for i = pageCount + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end
end

function LH.Toggle()
    if not LH.historyWindow then
        LH.CreateWindow()
        if KART.UpdateStyles then KART.UpdateStyles() end
    end
    if LH.historyWindow:IsShown() then
        LH.historyWindow:Hide()
    else
        LH.currentPage = 1 -- always open on the first (newest) page
        LH.Refresh()
        LH.historyWindow:Show()
    end
end

function LH.InstallEvents()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "GROUP_ROSTER_UPDATE" then
            LH.OnGroupUpdate()
            return
        end
        if name ~= "RCLootCouncil" then return end
        local AceEvent = LibStub("AceEvent-3.0", true)
        if not AceEvent then return end
        local listener = {}
        AceEvent:Embed(listener)
        LH.RegisterRC(listener)
        LH.HookTrackAndLog(_G.RCLootCouncilML)
    end)
    LH.eventFrame = frame
end

KASC:RegisterMessage("LH_ADD", { payload = true, group = true }, LH.AcceptAdd)
KASC:RegisterMessage("LH_REPL", { payload = true, group = true }, LH.AcceptRepl)
KASC:RegisterMessage("LH_REQ", { payload = true, group = true }, LH.HandleRequest)
KASC:RegisterMessage("LH_BATCH", { payload = true, group = true }, LH.AcceptBatch)
KASC:RegisterMessage("LH_EPOCH", { payload = true, group = true }, LH.AcceptEpoch)
KASC:RegisterMessage("LH_DEL", { payload = true, group = true }, LH.AcceptDelete)

LH.InstallEvents()
LH.HookTrackAndLog(_G.RCLootCouncilML)
