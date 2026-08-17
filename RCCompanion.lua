local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC
local KAUtil = LibStub("KAUtil-1.0")
local Identity = LibStub("KASC-1.0").Identity

local mlMissingWarned = {}

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
    if not RC.IsRCLoaded() then return end
end
