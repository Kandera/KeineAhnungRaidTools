local addonName, KART = ...
KART.NT = KART.NT or {}
local NT = KART.NT

NT.DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
NT.VALID_DIFFICULTY = { [14] = true, [15] = true, [16] = true }

-- =====================================================================
--  Sequence: header, cursor, generation, order, who sends
-- =====================================================================

local function djb2(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

function NT.Checksum(str)
    return djb2(str or "")
end

function NT.ParseNoteHeader(str)
    if type(str) ~= "string" then return nil end
    local first = str:match("^[^\n]*") or ""
    local enc = tonumber(first:match("EncounterID:(%d+)"))
    local diff = first:match("Difficulty:([^;\n]+)")
    local name = first:match("Name:([^;\n]+)")
    if diff then diff = (diff:match("^%s*(.-)%s*$")) end
    if name then name = (name:match("^%s*(.-)%s*$")) end
    return enc, diff, name
end

function NT.NextAfter(order, skipped, killedEncID)
    skipped = skipped or {}
    local seen = false
    for _, id in ipairs(order or {}) do
        if seen and not skipped[id] then return id end
        if id == killedEncID then seen = true end
    end
    return nil
end

function NT.ApplyKill(order, skipped, killedEncID)
    return NT.NextAfter(order, skipped, killedEncID)
end

function NT.AurasSecret()
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if not fn then return false end
    local ok, secret = pcall(fn)
    return ok and secret and true or false
end

function NT.ShouldEnqueueKill(kill)
    return kill ~= nil and kill ~= 0
end

function NT.ShouldEnqueueZone(prevVisit, newVisit, instanceType, difficultyID, isLead)
    if not isLead then return false end
    if instanceType ~= "raid" then return false end
    if not NT.VALID_DIFFICULTY[difficultyID] then return false end
    if not newVisit then return false end
    return prevVisit ~= newVisit
end

-- Leave (open world / wrong difficulty) drops the visit so a later re-enter is new.
-- Must run even when the module is off, otherwise hearth-while-disabled sticks the token.
function NT.ClearVisitIfLeftRaid()
    if not KART_Settings then return false end
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" or not NT.VALID_DIFFICULTY[difficultyID] then
        NT.lastVisit = nil
        KART_Settings.ntLastVisit = 0
        return true
    end
    return false
end

function NT.AcceptGeneration(localGen, incomingGen)
    localGen = tonumber(localGen) or 0
    incomingGen = tonumber(incomingGen) or 0
    return incomingGen > localGen
end

function NT.BumpGeneration(localGen, lastReceived)
    local a = tonumber(localGen) or 0
    local b = tonumber(lastReceived) or 0
    if b > a then a = b end
    return a + 1
end

function NT.InstanceKey(mapId, difficultyID)
    return tostring(mapId or 0) .. ":" .. tostring(difficultyID or 0)
end

function NT.EnsureShape(settings)
    if not settings then return end
    if settings.ntModuleEnabled == nil then settings.ntModuleEnabled = false end
    settings.ntOperatorName = settings.ntOperatorName or ""
    settings.ntOrderByInstance = settings.ntOrderByInstance or {}
    if settings.ntLastVisit == nil then settings.ntLastVisit = 0 end
    if settings.ntGeneration == nil then settings.ntGeneration = 0 end
    settings.ntEditor = settings.ntEditor or ""
end

function NT.LocalGeneration()
    if KART_Settings then
        local g = tonumber(KART_Settings.ntGeneration)
        if g then return g end
    end
    return tonumber(NT.generation) or 0
end

local function escapeUI(s)
    return tostring(s or ""):gsub("|", "||")
end

function NT.PlayerPrint(msg)
    print(escapeUI(msg))
end

local function bumpAndPublish()
    if not KART_Settings then return end
    -- Spec: checksum is the cursor note that would be sent, not the last sent body.
    local cursor = tonumber(KART_Settings.ntCursor) or 0
    local _, diff = NT.RaidMapDiff()
    local diffName = NT.DIFFICULTY_NAMES[diff]
    local noteName = (cursor ~= 0 and diffName) and NT.NoteNameForEncounter(cursor, diffName) or nil
    KART_Settings.ntChecksum = (noteName and NT.CursorChecksum(noteName)) or ""
    if NT.LocalMayPublishState() then
        local nextGen = NT.BumpGeneration(NT.generation or 0, KART_Settings.ntGeneration)
        NT.generation = nextGen
        KART_Settings.ntGeneration = nextGen
        local name = UnitName("player")
        if name then KART_Settings.ntEditor = name end
        NT.PublishState()
    end
    if NT.RefreshBossList then NT.RefreshBossList() end
    if NT.statusLabel and NT.RefreshStatus then NT.RefreshStatus() end
end

function NT.SetOrder(mapKey, order)
    if not KART_Settings or not mapKey then return end
    NT.EnsureShape(KART_Settings)
    local bag = KART_Settings.ntOrderByInstance[mapKey]
    if not bag then
        bag = { order = {}, skipped = {} }
        KART_Settings.ntOrderByInstance[mapKey] = bag
    end
    local copy = {}
    for i, id in ipairs(order or {}) do copy[i] = id end
    bag.order = copy
    bag.skipped = bag.skipped or {}
    bumpAndPublish()
end

function NT.SetSkipped(mapKey, encID, skipped)
    if not KART_Settings or not mapKey or not encID then return end
    NT.EnsureShape(KART_Settings)
    local bag = KART_Settings.ntOrderByInstance[mapKey]
    if not bag then
        bag = { order = {}, skipped = {} }
        KART_Settings.ntOrderByInstance[mapKey] = bag
    end
    bag.skipped = bag.skipped or {}
    if skipped then
        bag.skipped[encID] = true
    else
        bag.skipped[encID] = nil
    end
    if skipped and tonumber(KART_Settings.ntCursor) == encID then
        KART_Settings.ntCursor = NT.ResolveSendableCursor(encID) or 0
    end
    bumpAndPublish()
end

-- Local GetInstanceInfo when that is a notes-valid raid; otherwise the published stand.
function NT.RaidMapDiff()
    local _, instanceType, diff = GetInstanceInfo()
    local mapId = select(8, GetInstanceInfo())
    if instanceType == "raid" and NT.VALID_DIFFICULTY[diff] then
        if KART_Settings then
            KART_Settings.ntMapId = mapId
            KART_Settings.ntDiff = diff
        end
        return mapId, diff
    end
    if KART_Settings then
        local standMap = tonumber(KART_Settings.ntMapId) or 0
        local standDiff = tonumber(KART_Settings.ntDiff) or 0
        if standMap ~= 0 and NT.VALID_DIFFICULTY[standDiff] then
            return standMap, standDiff
        end
    end
    return mapId, diff
end

function NT.CurrentMapKey()
    local mapId, diff = NT.RaidMapDiff()
    return NT.InstanceKey(mapId, diff)
end

function NT.Move(i, j)
    if not KART_Settings then return end
    local key = NT._listMapKey or NT.CurrentMapKey()
    if not key then return end
    NT.EnsureShape(KART_Settings)
    local bag = KART_Settings.ntOrderByInstance[key]
    if not bag or not bag.order then return end
    local ia, ib = i, j
    local idA = NT._visibleIds and NT._visibleIds[i]
    local idB = NT._visibleIds and NT._visibleIds[j]
    if idA and idB then
        ia, ib = nil, nil
        for idx, id in ipairs(bag.order) do
            if id == idA then ia = idx end
            if id == idB then ib = idx end
        end
    end
    if not ia or not ib or ia == ib then return end
    local item = table.remove(bag.order, ia)
    if not item then return end
    table.insert(bag.order, ib, item)
    NT.SetOrder(key, bag.order)
end

-- Tests inject NT._encountersForMap; live clients walk the Encounter Journal.
-- Do not numeric-sort encounter IDs: EJ / injected order is kill order.
function NT.EncountersFromEJ()
    local out = {}
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_GetEncounterInfoByIndex) ~= "function" then
        return out
    end
    local mapId = NT.RaidMapDiff()
    local journalId
    if type(EJ_GetInstanceForMap) == "function" and mapId then
        journalId = EJ_GetInstanceForMap(mapId)
    end
    if (not journalId or journalId == 0) and type(EJ_GetInstanceByIndex) == "function" then
        local numTiers = EJ_GetNumTiers() or 0
        local tier = numTiers > 1 and (numTiers - 1) or numTiers
        if tier >= 1 and type(EJ_SelectTier) == "function" then EJ_SelectTier(tier) end
        local idx = 1
        while true do
            local instId = EJ_GetInstanceByIndex(idx, true)
            if not instId then break end
            local infoMap
            if type(EJ_GetInstanceInfo) == "function" then
                infoMap = select(10, EJ_GetInstanceInfo(instId))
            end
            if mapId and infoMap == mapId then
                journalId = instId
                break
            end
            idx = idx + 1
        end
    end
    if not journalId or journalId == 0 then return out end
    if type(EJ_SelectInstance) == "function" then EJ_SelectInstance(journalId) end
    local i = 1
    while true do
        local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalId)
        if not name then break end
        out[#out + 1] = { id = dungeonEncounterID, name = name }
        i = i + 1
    end
    return out
end

function NT.EncountersForMap()
    if type(NT._encountersForMap) == "function" then
        return NT._encountersForMap() or {}
    end
    return NT.EncountersFromEJ()
end

function NT.DefaultEncounterOrder()
    local list = NT.EncountersForMap()
    local order = {}
    for i, enc in ipairs(list) do
        order[i] = enc.id
    end
    return order
end

-- ActiveReminder matching this encounter wins; otherwise first sorted name.
-- Reviewed 2026-08-28: NSRT has no import order. See docs/REVIEW-DECISIONS.md.
function NT.NoteNameForEncounter(encID, difficultyName)
    if not encID or not difficultyName then return nil end
    if type(NSRT) == "table" and type(NSRT.ActiveReminder) == "string" and NSRT.ActiveReminder ~= "" then
        local body = NT.NoteBody(NSRT.ActiveReminder)
        if body then
            local enc, diff = NT.ParseNoteHeader(body)
            if enc == encID and diff == difficultyName then
                return NSRT.ActiveReminder
            end
        end
    end
    for _, n in ipairs(NT.ListSharedNotes(difficultyName)) do
        if n.encID == encID then return n.name end
    end
    return nil
end

function NT.ResetOrder()
    if not KART_Settings then return end
    local key = NT._listMapKey or NT.CurrentMapKey()
    NT.EnsureShape(KART_Settings)
    KART_Settings.ntOrderByInstance[key] = {
        order = NT.DefaultEncounterOrder(),
        skipped = {},
    }
    bumpAndPublish()
end

function NT.MatchOperator(operatorName, unitName, realm, nickname)
    if not operatorName or operatorName == "" or not unitName then return false end
    local KAUtil = LibStub("KAUtil-1.0")
    local fold = function(s) return KAUtil.CaseFold(s) end
    local want = fold(operatorName)
    if want == fold(unitName) then return true end
    if nickname and want == fold(nickname) then return true end
    if realm and realm ~= "" then
        local qualified = fold(unitName) .. "-" .. fold(realm)
        local canon = fold(unitName) .. "-" .. KAUtil.CanonRealm(realm)
        if want == qualified or want == canon then return true end
        -- operator typed with a space in the realm
        if want == fold(unitName .. "-" .. realm) then return true end
        local opBase, opRealm = operatorName:match("^(.-)%-(.+)$")
        if opBase and opRealm then
            local opCanon = fold(opBase) .. "-" .. KAUtil.CanonRealm(opRealm)
            if opCanon == qualified or opCanon == canon then return true end
        end
    end
    return false
end

function NT.ChooseSender(opts)
    if not opts or opts.moduleEnabled == false or not opts.hasNote then return nil end
    local opOk = opts.operatorPresent and opts.operatorAssist and opts.operatorKart and opts.checksumMatch
    if opOk then return "operator" end
    if opts.isLead then return "lead" end
    return nil
end

-- =====================================================================
--  NSRT adapter (globals at call time — OptionalDep may load after this file)
-- =====================================================================

function NT.HasNSRT()
    return type(NSRT) == "table"
end

function NT.NoteBody(name)
    if type(name) ~= "string" or name == "" then return nil end
    if type(NSRT) ~= "table" or type(NSRT.Reminders) ~= "table" then return nil end
    local body = NSRT.Reminders[name]
    if type(body) ~= "string" or body == "" then return nil end
    return body
end

function NT.ListSharedNotes(difficultyName)
    local out = {}
    if type(NSRT) ~= "table" or type(NSRT.Reminders) ~= "table" then return out end
    local names = {}
    for name, body in pairs(NSRT.Reminders) do
        if type(name) == "string" and type(body) == "string" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local body = NSRT.Reminders[name]
        local enc, diff = NT.ParseNoteHeader(body)
        if enc and diff == difficultyName then
            out[#out + 1] = { name = name, encID = enc, body = body }
        end
    end
    return out
end

function NT.Share(name)
    local NSI = NorthernSkyRaidTools
    if type(NSI) ~= "table" then return false end
    if type(NSI.SetReminder) ~= "function" or type(NSI.Broadcast) ~= "function" then return false end
    if type(NSRT) ~= "table" or type(NSRT.Reminders) ~= "table" then return false end
    local body = NSRT.Reminders[name]
    if type(body) ~= "string" or body == "" then return false end
    local okSet = pcall(NSI.SetReminder, NSI, name)
    if not okSet then return false end
    local okSend = pcall(NSI.Broadcast, NSI, "NSI_REM_SHARE", "RAID", NSRT.Reminders[name], nil, true)
    if not okSend then return false end
    NT.pendingFlush = nil
    return true
end

function NT.CursorChecksum(name)
    local body = NT.NoteBody(name)
    if not body then return nil end
    return NT.Checksum(body)
end

-- =====================================================================
--  KASC NT_STATE / NT_FLUSH / NT_LEAD / NT_STATE_REQ (IDs only — never the note body)
-- =====================================================================

local KASC = LibStub("KASC-1.0")

NT.generation = NT.generation or 0

function NT.KascEnabled()
    return KART_Settings ~= nil and KART_Settings.ntModuleEnabled == true
end

local function csvFromList(list)
    local parts = {}
    for i, id in ipairs(list or {}) do
        parts[i] = tostring(id)
    end
    return table.concat(parts, ",")
end

local function csvFromSet(set)
    local parts = {}
    for id in pairs(set or {}) do
        parts[#parts + 1] = tostring(id)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function listFromCsv(csv)
    local out = {}
    if not csv or csv == "" then return out end
    for piece in csv:gmatch("[^,]+") do
        local n = tonumber(piece)
        if n then out[#out + 1] = n end
    end
    return out
end

local function setFromCsv(csv)
    local out = {}
    if not csv or csv == "" then return out end
    for piece in csv:gmatch("[^,]+") do
        local n = tonumber(piece)
        if n then out[n] = true end
    end
    return out
end

-- Wire: gen \t editor \t operator \t mapId \t diff \t cursor \t checksum \t orderCsv \t skipCsv
function NT.EncodeState(state)
    if type(state) ~= "table" then return nil end
    return table.concat({
        tostring(state.gen or 0),
        state.editor or "",
        state.operator or "",
        tostring(state.mapId or 0),
        tostring(state.diff or 0),
        tostring(state.cursor or 0),
        state.checksum or "",
        csvFromList(state.order),
        csvFromSet(state.skipped),
    }, "\t")
end

function NT.DecodeState(payload)
    if type(payload) ~= "string" then return nil end
    local gen, editor, operator, mapId, diff, cursor, checksum, orderCsv, skipCsv =
        payload:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if not gen then return nil end
    return {
        gen = tonumber(gen) or 0,
        editor = editor,
        operator = operator,
        mapId = tonumber(mapId) or 0,
        diff = tonumber(diff) or 0,
        cursor = tonumber(cursor) or 0,
        checksum = checksum,
        order = listFromCsv(orderCsv),
        skipped = setFromCsv(skipCsv),
    }
end

function NT.ApplyRemoteState(settings, incoming)
    if type(settings) ~= "table" or type(incoming) ~= "table" then return false end
    local localGen = settings.ntGeneration or NT.generation or 0
    if not NT.AcceptGeneration(localGen, incoming.gen) then return false end

    local prevMap = tonumber(settings.ntMapId) or 0
    local prevDiff = tonumber(settings.ntDiff) or 0
    local lackedStand = prevMap == 0 or not NT.VALID_DIFFICULTY[prevDiff]

    NT.EnsureShape(settings)
    settings.ntGeneration = tonumber(incoming.gen) or 0
    settings.ntEditor = incoming.editor or ""
    if incoming.operator ~= nil then
        settings.ntOperatorName = incoming.operator
    end
    settings.ntMapId = tonumber(incoming.mapId) or 0
    settings.ntDiff = tonumber(incoming.diff) or 0
    settings.ntCursor = tonumber(incoming.cursor) or 0
    settings.ntChecksum = incoming.checksum or ""

    local key = NT.InstanceKey(settings.ntMapId, settings.ntDiff)
    local order = {}
    for i, id in ipairs(incoming.order or {}) do
        order[i] = id
    end
    local skipped = {}
    for id in pairs(incoming.skipped or {}) do
        skipped[id] = true
    end
    settings.ntOrderByInstance[key] = { order = order, skipped = skipped }

    NT.generation = settings.ntGeneration
    if NT.RefreshBossList then NT.RefreshBossList() end
    if NT.RefreshStatus then NT.RefreshStatus() end
    -- NT_FLUSH is ALERT; NT_STATE is NORMAL. Retry only when we had no stand to Share with.
    if NT.pendingFlush then
        if lackedStand then
            NT.ApplyFlushAndShare(NT.pendingFlush)
        else
            NT.pendingFlush = nil
        end
    end
    return true
end

local function localStateFromSettings(settings)
    if type(settings) ~= "table" then return nil end
    local mapId = settings.ntMapId or 0
    local diff = settings.ntDiff or 0
    local key = NT.InstanceKey(mapId, diff)
    local bag = settings.ntOrderByInstance and settings.ntOrderByInstance[key] or nil
    return {
        gen = settings.ntGeneration or NT.generation or 0,
        editor = settings.ntEditor or "",
        operator = settings.ntOperatorName or "",
        mapId = mapId,
        diff = diff,
        cursor = settings.ntCursor or 0,
        checksum = settings.ntChecksum or "",
        order = (bag and bag.order) or {},
        skipped = (bag and bag.skipped) or {},
    }
end

-- Who may publish NT_STATE: raid lead or the matched note operator (design).
local function playerRealm()
    local _, realm = UnitName("player")
    if realm and realm ~= "" then return realm end
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
end

function NT.LocalMayPublishState()
    if UnitIsGroupLeader("player") then return true end
    if not KART_Settings then return false end
    local name = UnitName("player")
    if not name then return false end
    local nick = KASC.Identity.GetNickname("player")
    return NT.MatchOperator(KART_Settings.ntOperatorName, name, playerRealm(), nick)
end

function NT.SenderMayPublishState(ctx, settings)
    if not ctx or not settings then return false end
    if KART.SenderIsGroupLeader and KART.SenderIsGroupLeader(ctx) then return true end
    local realm = (ctx.sender and ctx.sender:match("^[^%-]+%-(.+)$")) or ""
    local nick
    local key = ctx.Key and ctx:Key()
    if key and KASC.Identity.IsResolvedKey(key) then
        local unit = KASC.Identity.FindUnitForKey(key)
        if unit then nick = KASC.Identity.GetNickname(unit) end
    end
    return NT.MatchOperator(settings.ntOperatorName, ctx.shortName, realm, nick)
end

-- Local GetInstanceInfo is a notes-valid raid. Not RaidMapDiff: town must not look in-raid
-- just because a stand is published.
function NT.LocalInstanceIsNotesRaid()
    local _, instanceType, diff = GetInstanceInfo()
    return instanceType == "raid" and NT.VALID_DIFFICULTY[diff] == true
end

-- Operator in town: block Share now when the lead is inside and Restricted.
-- Fail-open until the first NT_LEAD (leadInRaid nil). Lead uses local AurasSecret, not the echo.
function NT.LeadWindowBlocksShare()
    if UnitIsGroupLeader("player") then return false end
    if NT.leadInRaid == nil then return false end
    return NT.leadInRaid == true and NT.leadRestricted == true
end

function NT.DecodeLeadWindow(payload)
    if type(payload) ~= "string" then return nil end
    local a, b = payload:match("^([01])\t([01])$")
    if not a then return nil end
    return a == "1", b == "1"
end

function NT.ApplyLeadWindow(inRaid, restricted)
    NT.leadInRaid = not not inRaid
    NT.leadRestricted = not not restricted
    if NT._shareQueued and not NT.LeadWindowBlocksShare() and not NT.AurasSecret() then
        if NT.ShareIfChosen() then
            local c = tonumber(KART_Settings and KART_Settings.ntCursor) or 0
            NT._queueShareCursor = c
            -- Overlap with NT_FLUSH is the same click; a later visit must still Share this id.
            C_Timer.After(2, function()
                if NT._queueShareCursor == c then NT._queueShareCursor = nil end
            end)
        end
    end
end

function NT.PublishLeadWindow(force)
    if not NT.KascEnabled() then return end
    if not UnitIsGroupLeader("player") then return end
    local inRaid = NT.LocalInstanceIsNotesRaid()
    local restricted = NT.AurasSecret()
    local payload = (inRaid and "1" or "0") .. "\t" .. (restricted and "1" or "0")
    if not force and NT._lastLeadPayload == payload then return end
    NT._lastLeadPayload = payload
    KASC:Send("NT_LEAD:" .. payload, nil, nil, { prio = "NORMAL", guaranteed = true })
end

-- Publish only on local edit or after a successful local share that changes checksum.
-- Never publish from KASC:OnPeer / peer hello — returning clients pull via NT_STATE_REQ.
function NT.PublishState()
    if not NT.KascEnabled() then return end
    if not NT.LocalMayPublishState() then return end
    local state = localStateFromSettings(KART_Settings)
    if not state then return end
    local encoded = NT.EncodeState(state)
    if not encoded then return end
    KASC:Send("NT_STATE:" .. encoded, nil, nil, { prio = "NORMAL", guaranteed = true })
end

function NT.RequestState()
    if not NT.KascEnabled() then return end
    if not IsInGroup() then return end
    KASC:Send("NT_STATE_REQ", nil, nil, { prio = "NORMAL", guaranteed = true })
end

local STATE_ANSWER_COOLDOWN = 5

function NT.AnswerStateRequest()
    if not NT.KascEnabled() then return end
    if not NT.LocalMayPublishState() then return end
    local now = GetTime()
    if now - (NT._lastStateAnswer or -STATE_ANSWER_COOLDOWN) < STATE_ANSWER_COOLDOWN then return end
    NT._lastStateAnswer = now
    NT.PublishState()
    NT.PublishLeadWindow(true)
end

function NT.RequestFlush(encID)
    if not NT.KascEnabled() then return end
    if not UnitIsGroupLeader("player") then return end
    if not NT.LocalInstanceIsNotesRaid() then return end
    local id = tonumber(encID)
    if not id then return end
    KASC:Send("NT_FLUSH:" .. tostring(id), nil, nil, { prio = "ALERT", guaranteed = true })
    NT.ApplyFlushAndShare(id)
end

-- Guard: test_mainframe reloads Notes.lua after MainFrame; KASC rejects duplicate tokens.
if KASC and not KASC._kartNtState then
    KASC._kartNtState = true
    KASC:RegisterMessage("NT_STATE", { payload = true, group = true, enabled = NT.KascEnabled }, function(payload, ctx)
        local incoming = NT.DecodeState(payload)
        if not incoming then return end
        if not NT.SenderMayPublishState(ctx, KART_Settings) then return end
        NT.ApplyRemoteState(KART_Settings, incoming)
    end)

    KASC:RegisterMessage("NT_FLUSH", { payload = true, group = true, enabled = NT.KascEnabled }, function(payload, ctx)
        if not (KART.SenderIsGroupLeader and KART.SenderIsGroupLeader(ctx)) then return end
        local encID = tonumber(payload)
        if not encID then return end
        NT.ApplyFlushAndShare(encID)
    end)

    KASC:RegisterMessage("NT_LEAD", { payload = true, group = true, enabled = NT.KascEnabled }, function(payload, ctx)
        if not (KART.SenderIsGroupLeader and KART.SenderIsGroupLeader(ctx)) then return end
        local inRaid, restricted = NT.DecodeLeadWindow(payload)
        if inRaid == nil then return end
        NT.ApplyLeadWindow(inRaid, restricted)
    end)

    KASC:RegisterMessage("NT_STATE_REQ", { group = true, enabled = NT.KascEnabled }, function()
        NT.AnswerStateRequest()
    end)
end

-- =====================================================================
--  Events: kill / zone-in enqueue; lead-only flush when auras are clear
-- =====================================================================

local flushWaitGen = 0

local function orderBag(settings, difficultyID)
    NT.EnsureShape(settings)
    local mapId = tonumber(settings.ntMapId) or 0
    local diff = tonumber(settings.ntDiff) or difficultyID or 0
    if mapId == 0 or not NT.VALID_DIFFICULTY[diff] then
        local liveMap, liveDiff = NT.RaidMapDiff()
        if mapId == 0 then mapId = liveMap end
        if not NT.VALID_DIFFICULTY[diff] then diff = liveDiff end
    end
    local bag = settings.ntOrderByInstance[NT.InstanceKey(mapId, diff)]
    local order = (bag and bag.order) or {}
    local skipped = (bag and bag.skipped) or {}
    if #order == 0 then
        order = NT.DefaultEncounterOrder()
    end
    return order, skipped
end

function NT.ResolveSendableCursor(cursor)
    if not KART_Settings then return nil end
    local order, skipped = orderBag(KART_Settings)
    local _, diff = NT.RaidMapDiff()
    local diffName = NT.DIFFICULTY_NAMES[diff]
    cursor = tonumber(cursor) or 0
    local function sendable(id)
        if not id or skipped[id] then return false end
        if not NT.HasNSRT() then return true end
        return NT.NoteNameForEncounter(id, diffName) ~= nil
    end
    if cursor ~= 0 and sendable(cursor) then return cursor end
    local seen = (cursor == 0)
    for _, id in ipairs(order) do
        if seen and sendable(id) then return id end
        if cursor ~= 0 and id == cursor then seen = true end
    end
    return nil
end

local function cursorOrFirst(settings)
    return NT.ResolveSendableCursor(tonumber(settings.ntCursor) or 0)
end

function NT.SkipAndAdvance()
    if not KART_Settings then return end
    local cursor = tonumber(KART_Settings.ntCursor) or 0
    if cursor == 0 then return end
    local key = NT._listMapKey or NT.CurrentMapKey()
    if not key then return end
    NT.SetSkipped(key, cursor, true)
end

function NT.ShareIfChosen()
    local L = KART.L or {}
    if not NT.HasNSRT() then
        local msg = L.NT_STATUS_NO_NSRT or ""
        NT.SetStatus(msg)
        NT.PlayerPrint(msg)
        return false
    end
    local cursor = KART_Settings and tonumber(KART_Settings.ntCursor) or 0
    if cursor ~= 0 then
        local sendable = NT.ResolveSendableCursor(cursor)
        if sendable then
            cursor = sendable
            KART_Settings.ntCursor = sendable
        else
            cursor = 0
        end
    end
    if cursor == 0 then
        NT.SetStatus(L.NT_STATUS_LAST_BOSS or "")
        return false
    end
    local _, diff = NT.RaidMapDiff()
    local diffName = NT.DIFFICULTY_NAMES[diff]
    local noteName = NT.NoteNameForEncounter(cursor, diffName)
    if not noteName then
        local msg = L.NT_STATUS_NO_NOTE or ""
        NT.SetStatus(msg)
        NT.PlayerPrint(msg)
        return false
    end
    local opts = NT.SenderOpts(noteName)
    local weOp = NT.WeAreOperator()
    local weLead = UnitIsGroupLeader("player") and true or false
    if opts.operatorPresent and not opts.operatorAssist then
        local msg = L.NT_STATUS_PROMOTE or ""
        NT.SetStatus(msg)
        NT.PlayerPrint(msg)
        if not weLead then return false end
    end
    local who = NT.ChooseSender(opts)
    if who == "lead" and opts.operatorPresent and not opts.checksumMatch then
        local msg = L.NT_STATUS_STALE or ""
        NT.SetStatus(msg)
        NT.PlayerPrint(msg)
    end
    local weSend = (who == "operator" and weOp) or (who == "lead" and weLead)
    if not weSend then return false end
    if NT.Share(noteName) then
        NT._shareQueued = nil
        local label = (who == "operator" and (KART_Settings.ntOperatorName or "")) or (UnitName("player") or "")
        NT.SetStatus(string.format(L.NT_STATUS_SENDER or "%s", label))
        local sum = NT.CursorChecksum(noteName)
        if KART_Settings and sum then
            KART_Settings.ntChecksum = sum
            bumpAndPublish()
        end
        return true
    end
    local msg = L.NT_STATUS_NO_NSRT or ""
    NT.SetStatus(msg)
    NT.PlayerPrint(msg)
    return false
end

function NT.ApplyFlushAndShare(encID)
    local id = tonumber(encID)
    if not id or not KART_Settings then return end
    NT.pendingFlush = id
    local sendable = NT.ResolveSendableCursor(id)
    KART_Settings.ntCursor = sendable or id
    -- Queued Share now already Load & Sent this cursor when NT_LEAD unblocked; skip the overlap.
    if sendable and sendable == NT._queueShareCursor then
        NT._queueShareCursor = nil
    elseif sendable then
        NT._queueShareCursor = nil
        NT.ShareIfChosen()
    end
    -- Keep the flag only when Share failed for lack of a notes-valid stand (FLUSH before STATE).
    -- Otherwise a leftover id rewinds the cursor on the next ApplyRemoteState.
    if NT.pendingFlush then
        local mapId, diff = NT.RaidMapDiff()
        if mapId and mapId ~= 0 and NT.VALID_DIFFICULTY[diff] then
            NT.pendingFlush = nil
        end
    end
end

-- Wait until auras are not secret and the lead window is not Restricted, then flush or Share.
local function scheduleLeadFlush(cursor)
    if not cursor then return end
    flushWaitGen = flushWaitGen + 1
    local myGen = flushWaitGen
    local function attempt()
        if myGen ~= flushWaitGen then return end
        NT.PublishLeadWindow()
        if NT.AurasSecret() or NT.LeadWindowBlocksShare() then
            C_Timer.After(1, attempt)
            return
        end
        if UnitIsGroupLeader("player") then
            if NT.LocalInstanceIsNotesRaid() then
                NT.RequestFlush(cursor)
            else
                NT.ShareIfChosen()
            end
        else
            NT.ShareIfChosen()
        end
    end
    attempt()
end

function NT.EnqueueFlush(cursor)
    scheduleLeadFlush(cursor)
end

local function operatorUnit()
    if not KART_Settings then return nil end
    local op = KART_Settings.ntOperatorName
    if not op or op == "" then return nil end
    local KAUtil = LibStub("KAUtil-1.0")
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        local nick = KASC.Identity.GetNickname(unit)
        if NT.MatchOperator(op, name, realm, nick) then return unit, name end
    end
    return nil
end

function NT.WeAreOperator()
    if not KART_Settings then return false end
    local name, realm = UnitName("player")
    if not name then return false end
    local nick = KASC.Identity.GetNickname("player")
    return NT.MatchOperator(KART_Settings.ntOperatorName, name, realm ~= "" and realm or playerRealm(), nick)
end

function NT.SenderOpts(noteName)
    local settings = KART_Settings
    local unit = operatorUnit()
    local checksum = noteName and NT.CursorChecksum(noteName) or nil
    local published = settings and settings.ntChecksum or ""
    local checksumMatch = (not published or published == "") or (checksum ~= nil and checksum == published)
    local kartUp = false
    if unit then
        local short = UnitName(unit)
        kartUp = (KART.PlayerVersions and short and KART.PlayerVersions[short] ~= nil)
            or NT.WeAreOperator()
    end
    return {
        moduleEnabled = settings and settings.ntModuleEnabled == true,
        isLead = UnitIsGroupLeader("player") and true or false,
        operatorPresent = unit ~= nil,
        operatorAssist = unit ~= nil and (UnitIsGroupAssistant(unit) or UnitIsGroupLeader(unit)) and true or false,
        operatorKart = kartUp,
        checksumMatch = checksumMatch,
        hasNote = noteName ~= nil,
    }
end

function NT.SetStatus(msg)
    if NT.statusLabel and NT.statusLabel.SetText then
        NT.statusLabel:SetText(escapeUI(msg))
    end
end

function NT.RefreshStatus()
    local L = KART.L or {}
    if not NT.HasNSRT() then
        NT.SetStatus(L.NT_STATUS_NO_NSRT or "")
        return
    end
    if NT.AurasSecret() or NT.LeadWindowBlocksShare() then
        NT.SetStatus(L.NT_STATUS_QUEUED or "")
        return
    end
    local cursor = NT.ResolveSendableCursor(KART_Settings and tonumber(KART_Settings.ntCursor) or 0)
    if not cursor then
        NT.SetStatus(L.NT_STATUS_LAST_BOSS or "")
        return
    end
    local _, diff = NT.RaidMapDiff()
    local noteName = NT.NoteNameForEncounter(cursor, NT.DIFFICULTY_NAMES[diff])
    if not noteName then
        NT.SetStatus(L.NT_STATUS_NO_NOTE or "")
        return
    end
    local opts = NT.SenderOpts(noteName)
    if opts.operatorPresent and not opts.operatorAssist then
        NT.SetStatus(L.NT_STATUS_PROMOTE or "")
        return
    end
    if opts.operatorPresent and not opts.checksumMatch then
        NT.SetStatus(L.NT_STATUS_STALE or "")
        return
    end
    local who = NT.ChooseSender(opts)
    if who == "operator" then
        NT.SetStatus(string.format(L.NT_STATUS_SENDER or "%s", KART_Settings.ntOperatorName or ""))
        return
    end
    if who == "lead" then
        local op = KART_Settings and KART_Settings.ntOperatorName or ""
        if op ~= "" and not opts.operatorPresent then
            NT.SetStatus(string.format(L.NT_STATUS_OPERATOR_GONE or "%s", op))
            return
        end
        NT.SetStatus(string.format(L.NT_STATUS_SENDER or "%s", UnitName("player") or ""))
        return
    end
    NT.SetStatus("")
end

function NT.ShareNow()
    local L = KART.L or {}
    if NT.AurasSecret() or NT.LeadWindowBlocksShare() then
        NT.SetStatus(L.NT_STATUS_QUEUED or "")
        NT._shareQueued = true
        local cursor = KART_Settings and tonumber(KART_Settings.ntCursor)
        if cursor and cursor ~= 0 then NT.EnqueueFlush(cursor) end
        return
    end
    NT.ShareIfChosen()
end

local function maybePullState()
    if not IsInGroup() then
        NT._stateRequested = nil
        return
    end
    if NT._stateRequested then return end
    NT.RequestState()
    NT._stateRequested = true
end

function NT.OnModuleEnabled()
    NT._stateRequested = nil
    maybePullState()
    if UnitIsGroupLeader("player") then NT.PublishLeadWindow() end
end

local windowPollGen = 0

local function ensureLeadWindowPoll()
    if not NT.KascEnabled() or not UnitIsGroupLeader("player") then return end
    if not NT.LocalInstanceIsNotesRaid() then
        NT.PublishLeadWindow()
        return
    end
    if NT._windowPolling then return end
    NT._windowPolling = true
    windowPollGen = windowPollGen + 1
    local my = windowPollGen
    local function tick()
        if my ~= windowPollGen then return end
        if not NT.KascEnabled() or not UnitIsGroupLeader("player") or not NT.LocalInstanceIsNotesRaid() then
            NT._windowPolling = nil
            NT.PublishLeadWindow()
            return
        end
        NT.PublishLeadWindow()
        C_Timer.After(1, tick)
    end
    tick()
end

function NT.OnEvent(e, ...)
    if e == "ENCOUNTER_END" then
        NT.RaidMapDiff()
        local encID, _, _, _, kill = ...
        if not NT.ShouldEnqueueKill(kill) then return end
        if not KART_Settings then return end
        local order, skipped = orderBag(KART_Settings)
        local cursor = NT.NextAfter(order, skipped, encID)
        if cursor then cursor = NT.ResolveSendableCursor(cursor) end
        KART_Settings.ntCursor = cursor
        -- Publish before NT_FLUSH so the town operator has map/diff when they are the sender.
        bumpAndPublish()
        if cursor then scheduleLeadFlush(cursor) end
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        NT.RaidMapDiff()
        local _, instanceType, difficultyID = GetInstanceInfo()
        local visit = select(8, GetInstanceInfo())
        local isLead = UnitIsGroupLeader("player") and true or false
        if not KART_Settings then return end
        NT.EnsureShape(KART_Settings)
        -- Pull even in town (operator / relog). Once per group; leave group clears the flag.
        maybePullState()
        if isLead then
            NT.PublishLeadWindow()
            ensureLeadWindowPoll()
        end
        -- Left the raid (or not a notes-valid difficulty): drop the visit so a later
        -- hearth/re-enter of the same map id is treated as a new visit.
        if NT.ClearVisitIfLeftRaid() then
            return
        end
        -- 0/nil = no previous visit (Defaults use 0 so test_locales is happy).
        local prev = NT.lastVisit or KART_Settings.ntLastVisit
        if prev == 0 then prev = nil end
        if not NT.ShouldEnqueueZone(prev, visit, instanceType, difficultyID, isLead) then
            return
        end
        local cursor = cursorOrFirst(KART_Settings)
        if not cursor then return end
        KART_Settings.ntCursor = cursor
        NT.lastVisit = visit
        KART_Settings.ntLastVisit = visit
        -- Publish before NT_FLUSH so the town operator has map/diff when they are the sender.
        bumpAndPublish()
        scheduleLeadFlush(cursor)
        return
    end

    if e == "GROUP_ROSTER_UPDATE" then
        maybePullState()
        if UnitIsGroupLeader("player") then
            NT.PublishLeadWindow()
            ensureLeadWindowPoll()
        end
        if NT.RefreshStatus then NT.RefreshStatus() end
    end
end

-- Guard: second Notes.lua load must not register a second event frame.
if not NT._eventFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, e, ...)
        if not KART_Settings then return end
        if KART_Settings.ntModuleEnabled ~= true then
            if e == "PLAYER_ENTERING_WORLD" then NT.ClearVisitIfLeftRaid() end
            if e == "GROUP_ROSTER_UPDATE" and not IsInGroup() then
                NT._stateRequested = nil
            end
            return
        end
        NT.OnEvent(e, ...)
    end)
    NT._eventFrame = f
end

-- =====================================================================
--  Notes panel
-- =====================================================================

local ROW_H = 28
local ROW_GAP = 3

local function visibleBossRows()
    local key = NT.CurrentMapKey()
    if KART_Settings then NT.EnsureShape(KART_Settings) end
    local bag = KART_Settings and KART_Settings.ntOrderByInstance[key]
    local order = (bag and bag.order and #bag.order > 0) and bag.order or NT.DefaultEncounterOrder()
    local skipped = (bag and bag.skipped) or {}
    local names = {}
    for _, enc in ipairs(NT.EncountersForMap()) do
        names[enc.id] = enc.name
    end
    local _, diff = NT.RaidMapDiff()
    local diffName = NT.DIFFICULTY_NAMES[diff]
    local noteByEnc = {}
    if diffName then
        for _, n in ipairs(NT.ListSharedNotes(diffName)) do
            noteByEnc[n.encID] = n.name
            if not names[n.encID] then names[n.encID] = n.name end
        end
    end
    local hasNSRT = NT.HasNSRT()
    local rows = {}
    for _, id in ipairs(order) do
        if not hasNSRT or noteByEnc[id] then
            rows[#rows + 1] = {
                id = id,
                name = names[id] or tostring(id),
                skipped = skipped[id] and true or false,
            }
        end
    end
    return rows, key
end

function NT.RefreshBossList()
    local panel = NT.bossListFrame
    if not panel or NT._refreshingList then return end
    NT._refreshingList = true
    local L = KART.L or {}
    if panel.rows then
        for _, row in ipairs(panel.rows) do row:Hide() end
    end
    panel.rows = panel.rows or {}

    local bosses, key = visibleBossRows()
    NT._listMapKey = key
    NT._visibleIds = {}
    for n, boss in ipairs(bosses) do NT._visibleIds[n] = boss.id end
    local cursor = KART_Settings and tonumber(KART_Settings.ntCursor) or 0

    if #bosses == 0 then
        if panel.emptyLabel then panel.emptyLabel:Show() end
        panel:SetHeight(24)
        if NT.bossListCard then NT.bossListCard:SetHeight(48) end
        if KART.UpdateScrollRange then KART.UpdateScrollRange() end
        NT._refreshingList = false
        return
    end
    if panel.emptyLabel then panel.emptyLabel:Hide() end

    local totalH = 0
    for i, boss in ipairs(bosses) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetHeight(ROW_H)
            row:EnableMouse(true)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetJustifyH("LEFT")
            KART.UI:RegisterLabel(row.nameText)

            row.skipStore = {}
            row.skip = KART.UI:CreateSettingsCheckbox(row, {
                name = nil, label = L.NT_SKIP, y = 0,
                store = row.skipStore, key = "skipped",
                onChanged = function()
                    if NT._refreshingList then return end
                    if row.encID and NT._listMapKey then
                        NT.SetSkipped(NT._listMapKey, row.encID, row.skip:GetChecked())
                    end
                end,
            })
            row.skip:ClearAllPoints()
            row.skip:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.skip.text:SetWidth(70)
            row.nameText:SetPoint("RIGHT", row.skip, "LEFT", -10, 0)

            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                NT._dragFrom = self.index
            end)
            row:SetScript("OnDragStop", function()
                local dest
                local foci = GetMouseFoci and GetMouseFoci()
                if type(foci) == "table" then
                    for n = 1, #foci do
                        local f = foci[n]
                        while f do
                            if f.encID and f.index then dest = f break end
                            f = f.GetParent and f:GetParent()
                        end
                        if dest then break end
                    end
                end
                local from = NT._dragFrom
                NT._dragFrom = nil
                if from and dest and dest.index and from ~= dest.index then
                    NT.Move(from, dest.index)
                end
            end)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        local label = i .. ". " .. (boss.name or "")
        if boss.id == cursor then label = "> " .. label end
        row.encID = boss.id
        row.index = i
        row.nameText:SetText(escapeUI(label))
        row.skip:SetChecked(boss.skipped)

        row:Show()
        totalH = i * (ROW_H + ROW_GAP)
    end

    panel:SetHeight(math.max(totalH, 24))
    if NT.bossListCard then
        NT.bossListCard:SetHeight(math.max(totalH, 24) + 52)
    end
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
    NT._refreshingList = false
end

function NT.BuildPanel(parent)
    if NT._panelBuilt then return end
    NT._panelBuilt = true
    local L = KART.L
    local function SettingsStore() return KART_Settings end

    local enableCard = KART.UI:CreateCard(parent)
    enableCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    enableCard:SetSize(500, 50)
    KART.CbNtModuleEnabled = KART.UI:CreateSettingsCheckbox(enableCard, {
        name = "KART_NtModuleEnabled", label = L.SET_NT_MODULE_ENABLED,
        store = SettingsStore, key = "ntModuleEnabled", y = -20,
        tooltip = L.DESC_NT_MODULE_ENABLED,
        onChanged = function()
            if KART.RefreshModuleChips then KART.RefreshModuleChips() end
            if KART_Settings and KART_Settings.ntModuleEnabled then
                NT.OnModuleEnabled()
            end
        end,
    })
    KART.CbNtModuleEnabled.text:SetWidth(430)
    KART.CbNtModuleEnabled.text:SetJustifyH("LEFT")

    local opCard = KART.UI:CreateCard(parent)
    opCard:SetPoint("TOPLEFT", enableCard, "BOTTOMLEFT", 0, -12)
    opCard:SetSize(500, 90)

    local opLabel = opCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    opLabel:SetPoint("TOPLEFT", opCard, "TOPLEFT", 20, -15)
    opLabel:SetText(L.NT_LABEL_OPERATOR)
    KART.UI:RegisterLabel(opLabel)

    NT.OperatorEditBox = KART.UI:CreateStyledEditBox(opCard, "KART_NtOperatorEditBox")
    NT.OperatorEditBox:SetSize(460, 28)
    NT.OperatorEditBox:SetPoint("TOPLEFT", opLabel, "BOTTOMLEFT", 0, -8)
    NT.OperatorEditBox:SetScript("OnTextChanged", function(self)
        if not KART_Settings then return end
        KART_Settings.ntOperatorName = self:GetText() or ""
    end)
    NT.OperatorEditBox:SetScript("OnEditFocusLost", function(self)
        if not KART_Settings then return end
        local text = self:GetText() or ""
        KART_Settings.ntOperatorName = text
        if text ~= NT._publishedOperatorName then
            NT._publishedOperatorName = text
            bumpAndPublish()
        end
        NT.RefreshStatus()
    end)
    NT.OperatorEditBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.NT_LABEL_OPERATOR, 1, 1, 1)
        GameTooltip:AddLine(L.DESC_NT_OPERATOR, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    NT.OperatorEditBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local bossCard = KART.UI:CreateCard(parent)
    bossCard:SetPoint("TOPLEFT", opCard, "BOTTOMLEFT", 0, -12)
    bossCard:SetSize(500, 80)
    NT.bossListCard = bossCard

    NT.BtnResetOrder = KART.UI:CreateModernButton(bossCard, L.NT_BTN_RESET_ORDER)
    NT.BtnResetOrder:SetSize(160, 24)
    NT.BtnResetOrder:SetPoint("TOPRIGHT", bossCard, "TOPRIGHT", -12, -10)
    NT.BtnResetOrder:SetScript("OnClick", function() NT.ResetOrder() end)

    NT.bossListFrame = CreateFrame("Frame", nil, bossCard)
    NT.bossListFrame:SetPoint("TOPLEFT", bossCard, "TOPLEFT", 16, -38)
    NT.bossListFrame:SetPoint("BOTTOMRIGHT", bossCard, "BOTTOMRIGHT", -16, 12)
    NT.bossListFrame.rows = {}

    NT.bossListFrame.emptyLabel = NT.bossListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    NT.bossListFrame.emptyLabel:SetPoint("TOPLEFT", 4, -2)
    NT.bossListFrame.emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    KART.UI:RegisterLabel(NT.bossListFrame.emptyLabel)

    local shareCard = KART.UI:CreateCard(parent)
    shareCard:SetPoint("TOPLEFT", bossCard, "BOTTOMLEFT", 0, -12)
    shareCard:SetSize(500, 80)

    NT.BtnShareNow = KART.UI:CreateModernButton(shareCard, L.NT_BTN_SHARE)
    NT.BtnShareNow:SetSize(180, 26)
    NT.BtnShareNow:SetPoint("TOPLEFT", 20, -16)
    NT.BtnShareNow:SetScript("OnClick", function() NT.ShareNow() end)

    NT.BtnSkipAdvance = KART.UI:CreateModernButton(shareCard, L.NT_BTN_SKIP_ADVANCE)
    NT.BtnSkipAdvance:SetSize(200, 26)
    NT.BtnSkipAdvance:SetPoint("LEFT", NT.BtnShareNow, "RIGHT", 10, 0)
    NT.BtnSkipAdvance:SetScript("OnClick", function() NT.SkipAndAdvance() end)

    NT.statusLabel = shareCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    NT.statusLabel:SetPoint("TOPLEFT", 20, -50)
    NT.statusLabel:SetPoint("RIGHT", shareCard, "RIGHT", -20, 0)
    NT.statusLabel:SetJustifyH("LEFT")
    NT.statusLabel:SetTextColor(0.5, 0.5, 0.5)
    KART.UI:RegisterLabel(NT.statusLabel)

    NT.RefreshBossList()
    NT.RefreshStatus()

    if parent.HookScript then
        parent:HookScript("OnShow", function()
            NT.RefreshBossList()
            NT.RefreshStatus()
        end)
    end

    KART.UI:RegisterLocaleRefresher(function()
        local Lx = KART.L
        if KART.CbNtModuleEnabled then
            KART.CbNtModuleEnabled.text:SetText(Lx.SET_NT_MODULE_ENABLED)
            KART.CbNtModuleEnabled.tooltipText = Lx.DESC_NT_MODULE_ENABLED
        end
        if opLabel then opLabel:SetText(Lx.NT_LABEL_OPERATOR) end
        if NT.BtnResetOrder and NT.BtnResetOrder.text then
            NT.BtnResetOrder.text:SetText(Lx.NT_BTN_RESET_ORDER)
        end
        if NT.BtnShareNow and NT.BtnShareNow.text then
            NT.BtnShareNow.text:SetText(Lx.NT_BTN_SHARE)
        end
        if NT.BtnSkipAdvance and NT.BtnSkipAdvance.text then
            NT.BtnSkipAdvance.text:SetText(Lx.NT_BTN_SKIP_ADVANCE)
        end
        if NT.bossListFrame and NT.bossListFrame.rows then
            for _, row in ipairs(NT.bossListFrame.rows) do
                if row.skip and row.skip.text then row.skip.text:SetText(Lx.NT_SKIP) end
            end
        end
        NT.RefreshStatus()
    end)
end

function NT.SyncWidgets()
    local settingsMap = {}
    if KART.CbNtModuleEnabled then settingsMap[KART.CbNtModuleEnabled] = "ntModuleEnabled" end
    if NT.OperatorEditBox then settingsMap[NT.OperatorEditBox] = "ntOperatorName" end
    KART.ApplySettingsMap(settingsMap)
    NT.RefreshBossList()
    NT.RefreshStatus()
end

if KART.NotesPanel then
    NT.BuildPanel(KART.NotesPanel)
end
