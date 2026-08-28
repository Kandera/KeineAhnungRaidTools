local addonName, KART = ...
KART.NT = KART.NT or {}
local NT = KART.NT

NT.DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }

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
