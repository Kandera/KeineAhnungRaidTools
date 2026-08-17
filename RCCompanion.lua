local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local mlMissingWarned = {}
local awardRegistered = false

function RC.GetAddon()
    return _G.RCLootCouncil
end

function RC.IsRCLoaded()
    local loaded = _G.C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RCLootCouncil")
    return not not (loaded and RC.GetAddon())
end

function RC.SplitCouncilField(text)
    local out = {}
    for token in string.gmatch(text or "", "[^;,%s]+") do
        out[#out + 1] = KAUtil.TrimString(token)
    end
    return out
end

function RC.ResolvedCouncilGUIDs()
    local guids, seen = {}, {}
    for _, token in ipairs(RC.SplitCouncilField(KART_Settings.rcCouncilMembers or "")) do
        local key = (Identity.ResolvePlayer(token))
        if Identity.IsResolvedKey(key) and Identity.FindUnitForKey(key) and not seen[key] then
            seen[key] = true
            guids[#guids + 1] = key
        end
    end
    return guids
end

local function CallMLMethod(ml, name)
    local fn = ml[name]
    if type(fn) ~= "function" then
        if not mlMissingWarned[name] then
            mlMissingWarned[name] = true
            print("|cffff0000KART:|r RCLootCouncilML." .. name .. " is missing")
        end
        return
    end
    pcall(fn, ml)
end

local function GetMLName()
    local addon = RC.GetAddon()
    if not addon then return nil end
    if addon.masterLooter then return addon.masterLooter end
    if type(addon.GetML) == "function" then
        local ok, name = pcall(addon.GetML, addon)
        if ok and name then return name end
    end
    if addon.isMasterLooter then
        return UnitName("player")
    end
    return nil
end

local function IsCouncilGUID(guid)
    if not Identity.IsResolvedKey(guid) then return false end
    local addon = RC.GetAddon()
    local council = addon and addon.db and addon.db.profile and addon.db.profile.council
    if council then
        for _, g in ipairs(council) do
            if g == guid then return true end
        end
    end
    for _, g in ipairs(RC.ResolvedCouncilGUIDs()) do
        if g == guid then return true end
    end
    return false
end

function RC.RequestAward(session, winnerName, responseID)
    if not RC.IsRCLoaded() then return end
    local addon = RC.GetAddon()
    if addon.isMasterLooter then
        local ml = _G.RCLootCouncilML
        if not ml then return end
        if type(ml.Award) ~= "function" then
            if not mlMissingWarned.Award then
                mlMissingWarned.Award = true
                print("|cffff0000KART:|r RCLootCouncilML.Award is missing")
            end
            return
        end
        pcall(ml.Award, ml, session, winnerName, responseID)
        return
    end
    if KASC.CommsRestricted() then
        print((KART.L and KART.L.RC_AWARD_RESTRICTED)
            or "Award relay blocked while addon comms are restricted.")
        return
    end
    local mlName = GetMLName()
    if not mlName then return end
    KASC:Send("RC_AWARD:" .. session .. ":" .. winnerName .. ":" .. responseID,
        "WHISPER", mlName, { prio = "ALERT" })
end

function RC.HandleAwardRequest(payload, ctx)
    if ctx.channel ~= "WHISPER" then return end
    local addon = RC.GetAddon()
    if not addon or not addon.isMasterLooter then return end
    local session, winner, response = payload:match("^(%d+):(.*):(%d+)$")
    if not session then return end
    session = tonumber(session)
    response = tonumber(response)
    local guid = Identity.ResolvePlayer(ctx.sender)
    if not IsCouncilGUID(guid) then return end
    local ml = _G.RCLootCouncilML
    if not ml then return end
    if type(ml.Award) ~= "function" then
        if not mlMissingWarned.Award then
            mlMissingWarned.Award = true
            print("|cffff0000KART:|r RCLootCouncilML.Award is missing")
        end
        return
    end
    pcall(ml.Award, ml, session, winner, response)
end

function RC.PushCouncilToRC()
    if not UnitIsGroupLeader("player") or not RC.IsRCLoaded() then return end
    local addon = RC.GetAddon()
    addon.db.profile.council = RC.ResolvedCouncilGUIDs()
    local ml = _G.RCLootCouncilML
    if not ml then return end
    CallMLMethod(ml, "SendCouncil")
    CallMLMethod(ml, "UpdateGroupCouncil")
end

function RC.OnRosterUpdate()
    RC.PushCouncilToRC()
end

function RC.Enable()
    if not KART_Settings.rcCouncilMigrated then
        local rc = KART_Settings.rcCouncilMembers
        local lc = KART_Settings.lcCouncilMembers
        if (rc == nil or rc == "") and type(lc) == "string" and lc ~= "" then
            KART_Settings.rcCouncilMembers = lc
        end
        KART_Settings.rcCouncilMigrated = true
    end
    KART_Settings.rcCouncilMembers = KART_Settings.rcCouncilMembers or ""
    if not awardRegistered then
        awardRegistered = true
        KASC:RegisterMessage("RC_AWARD", { payload = true, group = true, enabled = RC.IsRCLoaded },
            function(payload, ctx)
                RC.HandleAwardRequest(payload, ctx)
            end)
    end
    if not RC.IsRCLoaded() then return end
end
