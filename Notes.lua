local addonName, KART = ...
KART.NT = KART.NT or {}
local NT = KART.NT

NT.DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
NT.VALID_DIFFICULTY = { [14] = true, [15] = true, [16] = true }

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

-- NSRT / NorthernSkyRaidTools are resolved as globals at call time (chunk env), never captured
-- at load and never via _G — OptionalDep may load after this file; tests inject into the sandbox.

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
    for name, body in pairs(NSRT.Reminders) do
        if type(body) == "string" then
            local enc, diff = NT.ParseNoteHeader(body)
            if enc and diff == difficultyName then
                out[#out + 1] = { name = name, encID = enc, body = body }
            end
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
    return okSend and true or false
end

function NT.CursorChecksum(name)
    local body = NT.NoteBody(name)
    if not body then return nil end
    return NT.Checksum(body)
end

-- =====================================================================
--  KASC NT_STATE / NT_FLUSH (IDs only — never the note body)
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

-- Publish only on local edit or after a successful local share that changes checksum.
-- Never publish from KASC:OnPeer / peer hello — returning clients pull.
function NT.PublishState()
    if not NT.KascEnabled() then return end
    if not NT.LocalMayPublishState() then return end
    local state = localStateFromSettings(KART_Settings)
    if not state then return end
    local encoded = NT.EncodeState(state)
    if not encoded then return end
    KASC:Send("NT_STATE:" .. encoded, nil, nil, { prio = "NORMAL", guaranteed = true })
end

function NT.RequestFlush(encID)
    if not NT.KascEnabled() then return end
    local id = tonumber(encID)
    if not id then return end
    KASC:Send("NT_FLUSH:" .. tostring(id), nil, nil, { prio = "ALERT", guaranteed = true })
end

KASC:RegisterMessage("NT_STATE", { payload = true, group = true, enabled = NT.KascEnabled }, function(payload, ctx)
    local incoming = NT.DecodeState(payload)
    if not incoming then return end
    if not NT.SenderMayPublishState(ctx, KART_Settings) then return end
    NT.ApplyRemoteState(KART_Settings, incoming)
end)

KASC:RegisterMessage("NT_FLUSH", { payload = true, group = true, enabled = NT.KascEnabled }, function(payload)
    local encID = tonumber(payload)
    if not encID then return end
    NT.pendingFlush = encID
end)

-- =====================================================================
--  Events: kill / zone-in enqueue; lead-only flush when auras are clear
-- =====================================================================

local flushWaitGen = 0

local function orderBag(settings, difficultyID)
    NT.EnsureShape(settings)
    local mapId = settings.ntMapId or 0
    local diff = settings.ntDiff or difficultyID or 0
    local bag = settings.ntOrderByInstance[NT.InstanceKey(mapId, diff)]
    return (bag and bag.order) or {}, (bag and bag.skipped) or {}
end

local function firstSendable(order, skipped)
    for _, id in ipairs(order) do
        if not skipped[id] then return id end
    end
    return nil
end

local function cursorOrFirst(settings, difficultyID)
    local order, skipped = orderBag(settings, difficultyID)
    local cursor = tonumber(settings.ntCursor) or 0
    if cursor ~= 0 and not skipped[cursor] then return cursor end
    return firstSendable(order, skipped)
end

-- Wait until auras are not secret (poll 1s, max ~60s), then lead-only RequestFlush.
local function scheduleLeadFlush(cursor)
    if not cursor then return end
    flushWaitGen = flushWaitGen + 1
    local myGen = flushWaitGen
    local ticks = 0
    local function attempt()
        if myGen ~= flushWaitGen then return end
        if NT.AurasSecret() then
            ticks = ticks + 1
            if ticks >= 60 then return end
            C_Timer.After(1, attempt)
            return
        end
        if UnitIsGroupLeader("player") then
            NT.RequestFlush(cursor)
        end
    end
    attempt()
end

function NT.OnEvent(e, ...)
    if e == "ENCOUNTER_END" then
        local encID, _, _, _, kill = ...
        if not NT.ShouldEnqueueKill(kill) then return end
        if not KART_Settings then return end
        local order, skipped = orderBag(KART_Settings, select(3, GetInstanceInfo()))
        local cursor = NT.NextAfter(order, skipped, encID)
        KART_Settings.ntCursor = cursor
        if cursor then scheduleLeadFlush(cursor) end
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        local _, instanceType, difficultyID = GetInstanceInfo()
        local visit = select(8, GetInstanceInfo())
        local isLead = UnitIsGroupLeader("player") and true or false
        if not NT.ShouldEnqueueZone(NT.lastVisit, visit, instanceType, difficultyID, isLead) then
            return
        end
        NT.lastVisit = visit
        if not KART_Settings then return end
        local cursor = cursorOrFirst(KART_Settings, difficultyID)
        if cursor then
            KART_Settings.ntCursor = cursor
            scheduleLeadFlush(cursor)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, e, ...)
    if not KART_Settings or KART_Settings.ntModuleEnabled ~= true then return end
    NT.OnEvent(e, ...)
end)

function NT.BuildPanel(parent)
    -- Panel widgets land in Task 7 / Task 8.
end

if KART.NotesPanel then
    NT.BuildPanel(KART.NotesPanel)
end
