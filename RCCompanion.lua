local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local mlMissingWarned = {}
local awardRegistered = false
local votingFrameHooked = false
local awardWrapped = false
local suppressAward = false

function RC.DisplayName(unitOrName)
    if UnitExists(unitOrName) then
        local _, original = Identity.GetNickname(unitOrName)
        if original then return original end
        return Ambiguate(UnitName(unitOrName) or unitOrName, "short")
    end
    local key = Identity.ResolvePlayer(unitOrName)
    local unit = Identity.FindUnitForKey(key)
    if unit then
        local _, original = Identity.GetNickname(unit)
        if original then return original end
    end
    return Ambiguate(unitOrName, "short")
end

local function WrapAward(addon)
    if awardWrapped then return true end
    local ml = _G.RCLootCouncilML
    if not ml or type(ml.Award) ~= "function" then return false end
    local originalAward = ml.Award
    ml.Award = function(self, session, winnerName, responseID)
        if suppressAward then return end
        if addon.isMasterLooter then
            return originalAward(self, session, winnerName, responseID)
        end
        RC.RequestAward(session, winnerName, responseID)
    end
    awardWrapped = true
    return true
end

local function HookSetCellName(vf)
    if type(vf.SetCellName) ~= "function" then return end
    local originalSetCellName = vf.SetCellName
    vf.SetCellName = function(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
        pcall(originalSetCellName, rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
        if frame and frame.text and data and data[realrow] and data[realrow].name then
            local display = RC.DisplayName(data[realrow].name)
            if type(frame.text.GetText) == "function" then
                local ok, prior = pcall(frame.text.GetText, frame.text)
                if ok and prior then
                    local prefix = prior:match("^(|T.-|t)")
                    if prefix then display = prefix .. display end
                end
            end
            pcall(frame.text.SetText, frame.text, display)
        end
    end
    if vf.scrollCols then
        for _, col in ipairs(vf.scrollCols) do
            if col.colName == "name" then
                col.DoCellUpdate = vf.SetCellName
            end
        end
    end
end

function RC.HookVotingFrame()
    if votingFrameHooked then return end
    local addon = RC.GetAddon()
    if not addon then return end
    if not WrapAward(addon) then return end
    local ok, vf = pcall(function() return addon:GetActiveModule("votingframe") end)
    if not ok or not vf or type(vf.RightClickMenu) ~= "function" then return end
    local menuFrame = _G.RCLootCouncil_VotingFrame_RightclickMenu
    if not menuFrame then return end
    local originalRightClickMenu = vf.RightClickMenu
    local function wrappedRightClickMenu(self, ...)
        if not addon.isMasterLooter and not addon.isCouncil then
            return originalRightClickMenu(self, ...)
        end
        local wasML = addon.isMasterLooter
        if not wasML then addon.isMasterLooter = true end
        suppressAward = true
        local callOk, err = pcall(originalRightClickMenu, self, ...)
        suppressAward = false
        addon.isMasterLooter = wasML
        if not callOk then error(err) end
    end
    vf.RightClickMenu = wrappedRightClickMenu
    menuFrame.initialize = wrappedRightClickMenu
    if type(_G.MSA_DropDownMenu_Initialize) == "function" then
        pcall(_G.MSA_DropDownMenu_Initialize, menuFrame, vf.RightClickMenu, "MENU")
    end
    HookSetCellName(vf)
    votingFrameHooked = true
end

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
    RC.HookVotingFrame()
end
