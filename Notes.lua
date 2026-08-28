local addonName, KART = ...
KART.NT = KART.NT or {}
local NT = KART.NT
local KAUI = LibStub("KAUI-1.0")

NT.DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
NT.DIFFICULTY_IDS = { Normal = 14, Heroic = 15, Mythic = 16 }
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

-- List labels: EJ names have no difficulty; Reloe extra-instance names often already
-- end in " - Heroic". Strip a Normal/Heroic/Mythic suffix, then pin the list difficulty.
function NT.DisplayBossName(name, difficultyName)
    name = tostring(name or "")
    if name == "" then return name end
    -- Lua 5.1 patterns have no |; Reloe names are "Nymrissa - Heroic".
    local base = name:match("^(.*) %- Normal%s*$")
        or name:match("^(.*) %- Heroic%s*$")
        or name:match("^(.*) %- Mythic%s*$")
    if base and base ~= "" then name = base end
    if not difficultyName or difficultyName == "" then return name end
    return name .. " - " .. difficultyName
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
        NT._queueShareCursor = nil
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

-- Tonight's start. Does not skip earlier bosses; they stay on the list.
-- Town (no group): anyone may set it locally. In a group: lead or operator.
function NT.SetCursor(encID)
    if not KART_Settings or not encID then return end
    if not NT.LocalMayPublishState() and IsInGroup() then return end
    NT.EnsureShape(KART_Settings)
    encID = tonumber(encID)
    if not encID then return end
    if tonumber(KART_Settings.ntCursor) == encID then return end
    KART_Settings.ntCursor = encID
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
    -- Operator in town before anyone zones in: pick the current-tier raid
    -- whose encounters overlap imported NSRT notes (not the world-boss journal).
    local infMap, infDiff = NT.InferRaidStand()
    if infMap and NT.VALID_DIFFICULTY[infDiff] then
        return infMap, infDiff
    end
    return mapId, diff
end

-- Live instance stamps ntMapId/ntDiff; Infer does not. Flush/Share wait for this.
function NT.HasPublishedStand(settings)
    settings = settings or KART_Settings
    if type(settings) ~= "table" then return false end
    local standMap = tonumber(settings.ntMapId) or 0
    local standDiff = tonumber(settings.ntDiff) or 0
    return standMap ~= 0 and NT.VALID_DIFFICULTY[standDiff] == true
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
        local function ensure(id)
            for _, x in ipairs(bag.order) do
                if x == id then return end
            end
            bag.order[#bag.order + 1] = id
        end
        ensure(idA)
        ensure(idB)
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

-- Last EJ tier is Mythic+; current expansion raids are numTiers-1 (AutoNote / RC).
local function ejRaidTier()
    if type(EJ_GetNumTiers) ~= "function" then return nil end
    local num = EJ_GetNumTiers() or 0
    if num <= 0 then return nil end
    return num > 1 and (num - 1) or num
end

local function ejEncounters(journalId)
    local out = {}
    if not journalId or journalId == 0 then return out end
    if type(EJ_GetEncounterInfoByIndex) ~= "function" then return out end
    if type(EJ_SelectInstance) == "function" then EJ_SelectInstance(journalId) end
    local i = 1
    while true do
        local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalId)
        if not name then break end
        if dungeonEncounterID then
            out[#out + 1] = { id = dungeonEncounterID, name = name }
        end
        i = i + 1
    end
    return out
end

-- No live raid and no published stand: difficulty from imported notes, map from
-- the current-tier EJ raid with the most matching encounter IDs. Index 1 is world bosses.
function NT.InferRaidStand()
    local counts = { Normal = 0, Heroic = 0, Mythic = 0 }
    if type(NSRT) == "table" and type(NSRT.Reminders) == "table" then
        for _, body in pairs(NSRT.Reminders) do
            if type(body) == "string" then
                local _, diff = NT.ParseNoteHeader(body)
                if diff and counts[diff] then counts[diff] = counts[diff] + 1 end
            end
        end
    end
    local bestName, bestN = nil, 0
    local prefer = { "Mythic", "Heroic", "Normal" }
    for i = 1, #prefer do
        local name = prefer[i]
        if counts[name] > bestN then
            bestName, bestN = name, counts[name]
        end
    end
    if not bestName then return nil end
    local noteSet = {}
    if type(NSRT) == "table" and type(NSRT.Reminders) == "table" then
        for _, body in pairs(NSRT.Reminders) do
            if type(body) == "string" then
                local enc, diff = NT.ParseNoteHeader(body)
                if enc and diff == bestName then noteSet[enc] = true end
            end
        end
    end
    local tier = ejRaidTier()
    if not tier or type(EJ_GetInstanceByIndex) ~= "function" then return nil end
    if type(EJ_SelectTier) == "function" then EJ_SelectTier(tier) end
    local bestMap, bestScore = nil, 0
    local idx = 2
    while true do
        local instId = EJ_GetInstanceByIndex(idx, true)
        if not instId then break end
        local score = 0
        local encs = ejEncounters(instId)
        for n = 1, #encs do
            if noteSet[encs[n].id] then score = score + 1 end
        end
        if score > bestScore then
            local mapId = type(EJ_GetInstanceInfo) == "function" and select(10, EJ_GetInstanceInfo(instId)) or nil
            if mapId and mapId ~= 0 then
                bestScore = score
                bestMap = mapId
            end
        end
        idx = idx + 1
    end
    if not bestMap or bestScore == 0 then return nil end
    return bestMap, NT.DIFFICULTY_IDS[bestName]
end

-- Tests inject NT._encountersForMap; live clients walk the Encounter Journal.
-- Do not numeric-sort encounter IDs: EJ / injected order is kill order.
function NT.EncountersFromEJ()
    local out = {}
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_GetEncounterInfoByIndex) ~= "function" then
        return out
    end
    local mapId = NT.RaidMapDiff()
    if not mapId or mapId == 0 then return out end
    local journalId
    if type(EJ_GetInstanceForMap) == "function" then
        journalId = EJ_GetInstanceForMap(mapId)
    end
    if (not journalId or journalId == 0) and type(EJ_GetInstanceByIndex) == "function" then
        local tier = ejRaidTier()
        if tier and type(EJ_SelectTier) == "function" then EJ_SelectTier(tier) end
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
    return ejEncounters(journalId)
end

function NT.EncountersForMap()
    if type(NT._encountersForMap) == "function" then
        return NT._encountersForMap() or {}
    end
    return NT.EncountersFromEJ()
end

-- Notes whose encounter is not in this map's EJ (other raid, or a 1-boss lair)
-- still belong on the list. The night may interleave two raids; do not filter
-- those ids out. Reviewed 2026-08-28: docs/REVIEW-DECISIONS.md.
function NT.AppendMissingNoteIds(order, difficultyName)
    local seen = {}
    local out = {}
    for _, id in ipairs(order or {}) do
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    if not difficultyName then return out end
    for _, n in ipairs(NT.ListSharedNotes(difficultyName)) do
        local id = n.encID
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

function NT.DefaultEncounterOrder()
    local list = NT.EncountersForMap()
    local order = {}
    for _, enc in ipairs(list) do
        if enc.id then
            order[#order + 1] = enc.id
        end
    end
    local _, diff = NT.RaidMapDiff()
    return NT.AppendMissingNoteIds(order, NT.DIFFICULTY_NAMES[diff])
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

-- wipeAll: a new library (import / delete). Last night's drag bags must not survive.
function NT.ResetOrder(resetCursor, wipeAll)
    if not KART_Settings then return end
    NT.EnsureShape(KART_Settings)
    if wipeAll then
        KART_Settings.ntOrderByInstance = {}
        NT._listMapKey = nil
    end
    local key = NT._listMapKey or NT.CurrentMapKey()
    KART_Settings.ntOrderByInstance[key] = {
        order = NT.DefaultEncounterOrder(),
        skipped = {},
    }
    if resetCursor then
        KART_Settings.ntCursor = 0
    end
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

-- Paste box: Reloe's shared import on this client. Does not put the body on KASC.
function NT.ImportReminderText(str)
    if type(str) ~= "string" then str = "" end
    str = str:match("^%s*(.-)%s*$") or ""
    if str == "" then return "empty" end
    local n = 0
    for _ in str:gmatch("EncounterID:") do
        n = n + 1
    end
    if n == 0 then return "parse" end
    local NSI = NorthernSkyRaidTools
    if type(NSI) ~= "table" or type(NSI.ImportFullReminderString) ~= "function" then
        return "no_nsrt"
    end
    local ok = pcall(NSI.ImportFullReminderString, NSI, str, false, false)
    if not ok then return "no_nsrt" end
    -- A new paste is a new library. Do not keep last night's drag order.
    NT.ResetOrder(true, true)
    local WU = KART.WU
    if WU and type(WU.ReplaceImportedText) == "function" then
        WU.ReplaceImportedText(str)
    end
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
    if NT.RefreshStatus then NT.RefreshStatus() end
    return "ok", n
end

function NT.ClearImportEditBox()
    if NT.ImportEditBox and NT.ImportEditBox.SetText then
        NT.ImportEditBox:SetText("")
    end
end

function NT.DeleteSharedNotes()
    local NSI = NorthernSkyRaidTools
    if type(NSI) ~= "table" or type(NSI.RemoveReminder) ~= "function" then
        return "no_nsrt"
    end
    local names = {}
    if type(NSI.GetAllReminderNames) == "function" then
        local ok, list = pcall(NSI.GetAllReminderNames, NSI, false)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local entry = list[i]
                local name = type(entry) == "table" and entry.name or entry
                if type(name) == "string" then names[#names + 1] = name end
            end
        end
    end
    if #names == 0 and type(NSRT) == "table" and type(NSRT.Reminders) == "table" then
        for name in pairs(NSRT.Reminders) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    if #names == 0 then
        NT.ClearImportEditBox()
        return "empty"
    end
    for i = 1, #names do
        pcall(NSI.RemoveReminder, NSI, names[i], false)
    end
    if type(NSI.UpdateReminderFrame) == "function" then
        pcall(NSI.UpdateReminderFrame, NSI, true)
    end
    NT.ResetOrder(true, true)
    if NT.RefreshStatus then NT.RefreshStatus() end
    NT.ClearImportEditBox()
    return "ok", #names
end

if KART.UI and KART.UI.RegisterStaticPopup then
    KART.UI:RegisterStaticPopup("KART_NT_DELETE_CONFIRM", {
        text = (KART.L and KART.L.NT_DELETE_CONFIRM)
            or "Delete all shared notes from Northern Sky on this character?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            local Lx = KART.L or {}
            local status, n = NT.DeleteSharedNotes()
            local msg
            if status == "ok" then
                msg = string.format(Lx.NT_STATUS_DELETED or "%d", n or 0)
            elseif status == "empty" then
                msg = Lx.NT_STATUS_DELETE_EMPTY or ""
            else
                msg = Lx.NT_STATUS_NO_NSRT or ""
            end
            if NT.importStatusLabel and NT.importStatusLabel.SetText then
                NT.importStatusLabel:SetText(escapeUI(msg))
            end
            if NT.SetStatus then NT.SetStatus(msg) end
            if msg ~= "" then NT.PlayerPrint(msg) end
        end,
    })
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

-- NT_STATE is tab-separated; a tab in a field shifts every later column.
local function wireField(s)
    return (tostring(s or ""):gsub("[\t\r\n]", ""))
end

-- Wire: gen \t editor \t operator \t mapId \t diff \t cursor \t checksum \t orderCsv \t skipCsv
function NT.EncodeState(state)
    if type(state) ~= "table" then return nil end
    return table.concat({
        tostring(state.gen or 0),
        wireField(state.editor),
        wireField(state.operator),
        tostring(state.mapId or 0),
        tostring(state.diff or 0),
        tostring(state.cursor or 0),
        wireField(state.checksum),
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

    local lackedStand = not NT.HasPublishedStand(settings)

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
    if NT.SyncOperatorEditBox then NT.SyncOperatorEditBox() end
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

-- The operator *name* is a raid stand. Only the lead writes it. A raider typing
-- their own name must not become LocalMayPublishState and must not bump generation.
function NT.MayEditOperator()
    return UnitIsGroupLeader("player") and true or false
end

function NT.SyncOperatorEditBox()
    local box = NT.OperatorEditBox
    if not box then return end
    local name = (KART_Settings and KART_Settings.ntOperatorName) or ""
    NT._syncingOperator = true
    if box.SetText then box:SetText(name) end
    NT._syncingOperator = false
    if NT.MayEditOperator() then
        if box.Enable then box:Enable() end
    else
        if box.Disable then box:Disable() end
    end
end

function NT.CommitOperatorName(text)
    if not KART_Settings then return false end
    if not NT.MayEditOperator() then
        NT.SyncOperatorEditBox()
        return false
    end
    text = wireField(text)
    KART_Settings.ntOperatorName = text
    if text ~= NT._publishedOperatorName then
        NT._publishedOperatorName = text
        bumpAndPublish()
    end
    if NT.RefreshStatus then NT.RefreshStatus() end
    return true
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

-- Overlap with NT_FLUSH is the same click; a later visit must still Share this id.
local flushWaitGen = 0

local function cancelScheduledFlush()
    flushWaitGen = flushWaitGen + 1
end

local function rememberQueuedShare()
    NT._queueShareCursor = tonumber(KART_Settings and KART_Settings.ntCursor) or 0
end

-- Infer is town UI, not a stand. Queue-skip would drop pendingFlush before STATE.
local function shareQueuedIfPublished()
    if not NT.HasPublishedStand(KART_Settings) then return false end
    if NT.ShareIfChosen() then
        rememberQueuedShare()
        return true
    end
    return false
end

function NT.ApplyLeadWindow(inRaid, restricted)
    NT.leadInRaid = not not inRaid
    NT.leadRestricted = not not restricted
    if NT._shareQueued and not NT.LeadWindowBlocksShare() and not NT.AurasSecret() then
        if shareQueuedIfPublished() then
            -- Share now already sent; do not let the Restricted retry Share again.
            cancelScheduledFlush()
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
    local diffName = NT.DIFFICULTY_NAMES[diff]
    if diffName then
        order = NT.AppendMissingNoteIds(order, diffName)
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
    local cursor = NT.ResolveSendableCursor(tonumber(KART_Settings.ntCursor) or 0)
    if not cursor then
        NT.SetStatus((KART.L or {}).NT_STATUS_LAST_BOSS or "")
        return
    end
    local key = NT._listMapKey or NT.CurrentMapKey()
    if not key then return end
    KART_Settings.ntCursor = cursor
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
    local cursor = NT.ResolveSendableCursor(KART_Settings and tonumber(KART_Settings.ntCursor) or 0)
    if not cursor then
        NT.SetStatus(L.NT_STATUS_LAST_BOSS or "")
        return false
    end
    if KART_Settings then KART_Settings.ntCursor = cursor end
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
    local weLead = NT.LocalIsLead()
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
    -- Infer is town UI, not a stand. Share and clear the flag only after live/published map+diff.
    local published = NT.HasPublishedStand(KART_Settings)
    -- Queued Share now already Load & Sent this cursor when NT_LEAD unblocked; skip the overlap.
    if sendable and sendable == NT._queueShareCursor then
        NT._queueShareCursor = nil
        NT.pendingFlush = nil
        cancelScheduledFlush()
    elseif sendable and published then
        NT._queueShareCursor = nil
        if NT.ShareIfChosen() then
            cancelScheduledFlush()
        end
    end
    -- Keep the flag only when Share failed for lack of a published stand (FLUSH before STATE).
    -- Otherwise a leftover id rewinds the cursor on the next ApplyRemoteState.
    if NT.pendingFlush and published then
        NT.pendingFlush = nil
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
                shareQueuedIfPublished()
            end
        elseif not (NT.LocalInstanceIsNotesRaid() and NT.leadInRaid == true) then
            -- In-instance operator waits for NT_FLUSH from the lead.
            shareQueuedIfPublished()
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

-- No group: you are the sender. UnitIsGroupLeader is false when ungrouped.
function NT.LocalIsLead()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") and true or false
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
        isLead = NT.LocalIsLead(),
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
        NT._queueShareCursor = nil
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
        if NT.SyncOperatorEditBox then NT.SyncOperatorEditBox() end
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

local function rowUnderMouse()
    local foci = GetMouseFoci and GetMouseFoci()
    if type(foci) ~= "table" then return nil end
    for n = 1, #foci do
        local f = foci[n]
        while f do
            if f.encID and f.index then return f end
            f = f.GetParent and f:GetParent()
        end
    end
    return nil
end

-- During a drag the source keeps mouse capture, so GetMouseFoci stays on it.
-- Cursor geometry is what actually follows the pointer across rows.
local function rowAtCursor()
    local panel = NT.bossListFrame
    if not panel or not panel.rows then return nil end
    if type(GetCursorPosition) == "function" then
        local cx, cy = GetCursorPosition()
        if cx and cy then
            for _, r in ipairs(panel.rows) do
                if r.IsShown and r:IsShown() then
                    local scale = r.GetEffectiveScale and r:GetEffectiveScale() or 1
                    if scale and scale ~= 0 then
                        local x, y = cx / scale, cy / scale
                        local left = r.GetLeft and r:GetLeft()
                        local right = r.GetRight and r:GetRight()
                        local top = r.GetTop and r:GetTop()
                        local bottom = r.GetBottom and r:GetBottom()
                        if left and right and top and bottom
                            and x >= left and x <= right
                            and y <= top and y >= bottom then
                            return r
                        end
                    end
                end
            end
        end
    end
    return rowUnderMouse()
end

local function paintDragHighlight(source)
    local panel = NT.bossListFrame
    if not panel or not panel.rows then return end
    local dest = rowAtCursor()
    local ar, ag, ab = 0.3, 0.7, 1
    if KART.UI and KART.UI.AccentColor then
        ar, ag, ab = KART.UI:AccentColor()
    end
    for _, r in ipairs(panel.rows) do
        if r.SetAlpha then
            if r == source then
                r:SetAlpha(0.45)
            else
                r:SetAlpha(1)
            end
        end
        if r.nameText and r.nameText.SetTextColor then
            if dest and r == dest and r ~= source then
                r.nameText:SetTextColor(ar, ag, ab)
            else
                r.nameText:SetTextColor(1, 1, 1)
            end
        end
        if r.dropTint then
            if dest and r == dest and r ~= source then
                if r.dropTint.SetColorTexture then
                    r.dropTint:SetColorTexture(ar, ag, ab, 0.28)
                end
                if r.dropTint.Show then r.dropTint:Show() end
            elseif r.dropTint.Hide then
                r.dropTint:Hide()
            end
        end
    end
end

local function clearDragHighlight()
    local panel = NT.bossListFrame
    if not panel or not panel.rows then return end
    for _, r in ipairs(panel.rows) do
        if r.SetAlpha then r:SetAlpha(1) end
        if r.nameText and r.nameText.SetTextColor then
            r.nameText:SetTextColor(1, 1, 1)
        end
        if r.dropTint and r.dropTint.Hide then r.dropTint:Hide() end
        if r.SetScript then r:SetScript("OnUpdate", nil) end
    end
end

-- Matching WU.bosses row for this encounter + list difficulty. Count 0 and
-- a nil index mean notes-only (Invite/Remove stay disabled).
function NT.WuPlayersFor(encID, diffName)
    if not (KART.WU and KART.WU.IndexForEncounter) then return 0, nil end
    local idx = KART.WU.IndexForEncounter(encID, diffName)
    if not idx then return 0, nil end
    local entry = KART.WU.bosses and KART.WU.bosses[idx]
    return (entry and #(entry.players or {})) or 0, idx
end

local function visibleBossRows()
    local key = NT.CurrentMapKey()
    if KART_Settings then NT.EnsureShape(KART_Settings) end
    local bag = KART_Settings and KART_Settings.ntOrderByInstance[key]
    local order = (bag and bag.order and #bag.order > 0) and bag.order or NT.DefaultEncounterOrder()
    local skipped = (bag and bag.skipped) or {}
    local names = {}
    for _, enc in ipairs(NT.EncountersForMap()) do
        if enc.id then
            names[enc.id] = enc.name
        end
    end
    local _, diff = NT.RaidMapDiff()
    local diffName = NT.DIFFICULTY_NAMES[diff]
    if diffName then
        order = NT.AppendMissingNoteIds(order, diffName)
    end
    local noteByEnc = {}
    if diffName then
        for _, n in ipairs(NT.ListSharedNotes(diffName)) do
            noteByEnc[n.encID] = n.name
            if not names[n.encID] then
                local _, _, headerName = NT.ParseNoteHeader(n.body)
                names[n.encID] = headerName or n.name
            end
        end
    end
    local hasNSRT = NT.HasNSRT()
    local rows = {}
    for _, id in ipairs(order) do
        if not hasNSRT or noteByEnc[id] then
            local playerCount, wuIndex = NT.WuPlayersFor(id, diffName)
            rows[#rows + 1] = {
                id = id,
                name = NT.DisplayBossName(names[id] or tostring(id), diffName),
                skipped = skipped[id] and true or false,
                playerCount = playerCount,
                wuIndex = wuIndex,
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
        if panel.emptyLabel then
            panel.emptyLabel:SetText(L.NT_STATUS_LAST_BOSS or "")
            panel.emptyLabel:Show()
        end
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
            row.btnRemove = KART.UI:CreateModernButton(row, L.WU_BTN_REMOVE)
            row.btnRemove:SetSize(80, 22)
            row.btnRemove:SetPoint("RIGHT", row, "RIGHT", -4, 0)

            row.btnInvite = KART.UI:CreateModernButton(row, L.WU_BTN_INVITE)
            row.btnInvite:SetSize(80, 22)
            row.btnInvite:SetPoint("RIGHT", row.btnRemove, "LEFT", -8, 0)

            row.skip:ClearAllPoints()
            row.skip:SetPoint("RIGHT", row.btnInvite, "LEFT", -8, 0)
            -- CreateSettingsCheckbox puts the label to the right of the pill; on a
            -- right-aligned row that hangs outside the card. Flip it to the left.
            row.skip.text:ClearAllPoints()
            row.skip.text:SetPoint("RIGHT", row.skip, "LEFT", -8, 0)
            row.skip.text:SetJustifyH("RIGHT")
            row.nameText:SetPoint("RIGHT", row.skip.text, "LEFT", -10, 0)

            row.dropTint = row:CreateTexture(nil, "BACKGROUND")
            row.dropTint:SetAllPoints()
            row.dropTint:Hide()

            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                NT._dragFrom = self.index
                NT._justDragged = false
                if GameTooltip then GameTooltip:Hide() end
                paintDragHighlight(self)
                self:SetScript("OnUpdate", function()
                    paintDragHighlight(self)
                end)
            end)
            row:SetScript("OnDragStop", function()
                local dest = rowAtCursor()
                local from = NT._dragFrom
                NT._dragFrom = nil
                clearDragHighlight()
                local moved = from and dest and dest.index and from ~= dest.index
                NT._justDragged = moved and true or nil
                if moved then
                    NT.Move(from, dest.index)
                end
            end)
            row:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                if NT._justDragged then
                    NT._justDragged = nil
                    return
                end
                local foci = GetMouseFoci and GetMouseFoci()
                if type(foci) == "table" then
                    for n = 1, #foci do
                        local f = foci[n]
                        while f do
                            if self.skip and (f == self.skip or f == self.skip.text) then return end
                            if self.btnInvite and (f == self.btnInvite or f == self.btnInvite.text) then return end
                            if self.btnRemove and (f == self.btnRemove or f == self.btnRemove.text) then return end
                            f = f.GetParent and f:GetParent()
                        end
                    end
                end
                if self.encID then NT.SetCursor(self.encID) end
            end)
            row:SetScript("OnEnter", function(self)
                local Lx = KART.L or {}
                if not GameTooltip or not Lx.DESC_NT_SET_CURSOR then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(Lx.DESC_NT_SET_CURSOR, 1, 1, 1)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        local label = i .. ". " .. escapeUI(boss.name or "")
        if boss.id == cursor then label = "> " .. label end
        if (boss.playerCount or 0) > 0 then
            label = label .. " |cff888888(" .. boss.playerCount .. ")|r"
        end
        row.encID = boss.id
        row.index = i
        row.wuIndex = boss.wuIndex
        row.nameText:SetText(label)
        row.skip:SetChecked(boss.skipped)

        local canAct = boss.wuIndex
            and KART.WU
            and not (KART_Settings and KART_Settings.wuModuleEnabled == false)
        if canAct then
            row.btnInvite:Enable()
            row.btnRemove:Enable()
        else
            row.btnInvite:Disable()
            row.btnRemove:Disable()
        end
        row.btnInvite:SetScript("OnClick", function()
            if row.wuIndex and KART.WU then KART.WU.InviteBoss(row.wuIndex) end
        end)
        row.btnRemove:SetScript("OnClick", function()
            if row.wuIndex and KART.WU then KART.WU.RemoveForBoss(row.wuIndex) end
        end)

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
    enableCard:SetSize(500, 88)
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

    KART.CbWuModule = KART.UI:CreateSettingsCheckbox(enableCard, {
        name = "KART_WuModuleEnabled", label = L.SET_WU_MODULE_ENABLED,
        store = SettingsStore, key = "wuModuleEnabled", y = -52,
        tooltip = L.DESC_WU_MODULE_ENABLED,
        onChanged = function()
            if KART.RefreshModuleChips then KART.RefreshModuleChips() end
            NT.RefreshBossList()
        end,
    })
    KART.CbWuModule.text:SetWidth(430)
    KART.CbWuModule.text:SetJustifyH("LEFT")

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
        if NT._syncingOperator then return end
        if not KART_Settings then return end
        if not NT.MayEditOperator() then return end
        KART_Settings.ntOperatorName = self:GetText() or ""
    end)
    NT.OperatorEditBox:SetScript("OnEditFocusLost", function(self)
        NT.CommitOperatorName(self:GetText() or "")
    end)
    NT.OperatorEditBox:SetScript("OnEnter", function(self)
        local Lx = KART.L or {}
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Lx.NT_LABEL_OPERATOR, 1, 1, 1)
        GameTooltip:AddLine(Lx.DESC_NT_OPERATOR, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    NT.OperatorEditBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    NT.SyncOperatorEditBox()

    local importCard = KART.UI:CreateCard(parent)
    importCard:SetPoint("TOPLEFT", opCard, "BOTTOMLEFT", 0, -12)
    importCard:SetSize(500, 190)

    local pasteLabel = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pasteLabel:SetPoint("TOPLEFT", 20, -15)
    pasteLabel:SetText(L.NT_LABEL_PASTE)
    KART.UI:RegisterLabel(pasteLabel)

    local pasteBG = CreateFrame("Frame", nil, importCard, "BackdropTemplate")
    pasteBG:SetSize(460, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -35)
    KART.UI:SetPixelBackdrop(pasteBG, {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    pasteBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
    pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    KART.UI:ApplyRoundedMask(pasteBG, KAUI.CORNER_RADIUS_LG)

    local pasteScroll = CreateFrame("ScrollFrame", "KART_NTPasteScroll", pasteBG, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", 4, -4)
    pasteScroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local pasteScrollThumb = KART.UI:StripScrollbarTextures(pasteScroll)
    if pasteScrollThumb then pasteScrollThumb:SetSize(6, 16) end
    KART.UI:RegisterAccentTexture(pasteScrollThumb, 0.6)

    NT.ImportEditBox = CreateFrame("EditBox", "KART_NTImportEditBox", pasteScroll)
    NT.ImportEditBox:SetWidth(428)
    NT.ImportEditBox:SetHeight(300)
    NT.ImportEditBox:SetMultiLine(true)
    NT.ImportEditBox:SetAutoFocus(false)
    NT.ImportEditBox:SetFontObject("GameFontHighlightSmall")
    NT.ImportEditBox:SetScript("OnTextChanged", function() end)
    NT.ImportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    NT.ImportEditBox:SetScript("OnEditFocusGained", function()
        local r, g, b = KART.UI:AccentColor()
        pasteBG:SetBackdropBorderColor(r, g, b, 1)
    end)
    NT.ImportEditBox:SetScript("OnEditFocusLost", function()
        pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    pasteScroll:SetScrollChild(NT.ImportEditBox)
    KART.UI:RegisterEditBox(NT.ImportEditBox)

    local pasteClickCatcher = CreateFrame("Frame", nil, pasteBG)
    pasteClickCatcher:SetAllPoints(pasteScroll)
    pasteClickCatcher:SetFrameLevel(math.max(pasteScroll:GetFrameLevel() - 1, 0))
    pasteClickCatcher:EnableMouse(true)
    pasteClickCatcher:SetScript("OnMouseDown", function()
        NT.ImportEditBox:SetFocus()
        NT.ImportEditBox:SetCursorPosition(#NT.ImportEditBox:GetText())
    end)

    NT.BtnImport = KART.UI:CreateModernButton(importCard, L.NT_BTN_IMPORT)
    NT.BtnImport:SetSize(180, 26)
    NT.BtnImport:SetPoint("TOPLEFT", 20, -135)
    NT.BtnImport:SetScript("OnEnter", function(self)
        local Lx = KART.L or {}
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Lx.NT_BTN_IMPORT, 1, 1, 1)
        GameTooltip:AddLine(Lx.DESC_NT_PASTE, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    NT.BtnImport:SetScript("OnLeave", function() GameTooltip:Hide() end)
    NT.BtnImport:SetScript("OnClick", function()
        local Lx = KART.L or {}
        local text = NT.ImportEditBox and NT.ImportEditBox:GetText() or ""
        local status, n = NT.ImportReminderText(text)
        local msg
        if status == "ok" then
            msg = string.format(Lx.NT_STATUS_IMPORTED or "%d", n or 0)
        elseif status == "empty" then
            msg = Lx.NT_STATUS_IMPORT_EMPTY or ""
        elseif status == "parse" then
            msg = Lx.NT_STATUS_IMPORT_PARSE or ""
        else
            msg = Lx.NT_STATUS_NO_NSRT or ""
        end
        if NT.importStatusLabel and NT.importStatusLabel.SetText then
            NT.importStatusLabel:SetText(escapeUI(msg))
        end
        NT.SetStatus(msg)
        if status ~= "ok" and msg ~= "" then NT.PlayerPrint(msg) end
    end)

    NT.BtnDeleteNotes = KART.UI:CreateModernButton(importCard, L.NT_BTN_DELETE)
    NT.BtnDeleteNotes:SetSize(180, 26)
    NT.BtnDeleteNotes:SetPoint("LEFT", NT.BtnImport, "RIGHT", 10, 0)
    NT.BtnDeleteNotes:SetScript("OnEnter", function(self)
        local Lx = KART.L or {}
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Lx.NT_BTN_DELETE, 1, 1, 1)
        GameTooltip:AddLine(Lx.DESC_NT_DELETE, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    NT.BtnDeleteNotes:SetScript("OnLeave", function() GameTooltip:Hide() end)
    NT.BtnDeleteNotes:SetScript("OnClick", function()
        local Lx = KART.L or {}
        if StaticPopupDialogs and StaticPopupDialogs["KART_NT_DELETE_CONFIRM"] then
            StaticPopupDialogs["KART_NT_DELETE_CONFIRM"].text = Lx.NT_DELETE_CONFIRM or ""
        end
        StaticPopup_Show("KART_NT_DELETE_CONFIRM")
    end)

    NT.importStatusLabel = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    NT.importStatusLabel:SetPoint("TOPLEFT", 20, -168)
    NT.importStatusLabel:SetPoint("RIGHT", importCard, "RIGHT", -20, 0)
    NT.importStatusLabel:SetJustifyH("LEFT")
    NT.importStatusLabel:SetTextColor(0.5, 0.5, 0.5)
    KART.UI:RegisterLabel(NT.importStatusLabel)

    local bossCard = KART.UI:CreateCard(parent)
    bossCard:SetPoint("TOPLEFT", importCard, "BOTTOMLEFT", 0, -12)
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
            NT.SyncOperatorEditBox()
        end)
    end

    KART.UI:RegisterLocaleRefresher(function()
        local Lx = KART.L
        if KART.CbNtModuleEnabled then
            KART.CbNtModuleEnabled.text:SetText(Lx.SET_NT_MODULE_ENABLED)
            KART.CbNtModuleEnabled.tooltipText = Lx.DESC_NT_MODULE_ENABLED
        end
        if KART.CbWuModule then
            KART.CbWuModule.text:SetText(Lx.SET_WU_MODULE_ENABLED)
            KART.CbWuModule.tooltipText = Lx.DESC_WU_MODULE_ENABLED
        end
        if opLabel then opLabel:SetText(Lx.NT_LABEL_OPERATOR) end
        if pasteLabel then pasteLabel:SetText(Lx.NT_LABEL_PASTE) end
        if NT.BtnImport and NT.BtnImport.text then
            NT.BtnImport.text:SetText(Lx.NT_BTN_IMPORT)
        end
        if NT.BtnDeleteNotes and NT.BtnDeleteNotes.text then
            NT.BtnDeleteNotes.text:SetText(Lx.NT_BTN_DELETE)
        end
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
                if row.btnInvite and row.btnInvite.text then
                    row.btnInvite.text:SetText(Lx.WU_BTN_INVITE)
                end
                if row.btnRemove and row.btnRemove.text then
                    row.btnRemove.text:SetText(Lx.WU_BTN_REMOVE)
                end
            end
        end
        NT.RefreshStatus()
    end)
end

function NT.SyncWidgets()
    local settingsMap = {}
    if KART.CbNtModuleEnabled then settingsMap[KART.CbNtModuleEnabled] = "ntModuleEnabled" end
    if KART.CbWuModule then settingsMap[KART.CbWuModule] = "wuModuleEnabled" end
    if NT.OperatorEditBox then settingsMap[NT.OperatorEditBox] = "ntOperatorName" end
    KART.ApplySettingsMap(settingsMap)
    NT.SyncOperatorEditBox()
    NT.RefreshBossList()
    NT.RefreshStatus()
end

if KART.NotesPanel then
    NT.BuildPanel(KART.NotesPanel)
end
