local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local function SettingsStore() return KART_Settings end

local mlMissingWarned = {}
local awardRegistered = false
local votingFrameHooked = false
local awardWrapped = false
local suppressAward = false

local function ShowNickNames()
    return KART_Settings and KART_Settings.rcShowNickNames ~= false
end

function RC.DisplayName(unitOrName)
    if UnitExists(unitOrName) then
        if ShowNickNames() then
            local _, original = Identity.GetNickname(unitOrName)
            if original then return original end
        end
        return Ambiguate(UnitName(unitOrName) or unitOrName, "short")
    end
    if ShowNickNames() then
        local key = Identity.ResolvePlayer(unitOrName)
        local unit = Identity.FindUnitForKey(key)
        if unit then
            local _, original = Identity.GetNickname(unit)
            if original then return original end
        end
    end
    return Ambiguate(unitOrName, "short")
end

local function WrapAward(addon)
    if awardWrapped then return true end
    local ml = _G.RCLootCouncilML
    if not ml or type(ml.Award) ~= "function" then return false end
    local originalAward = ml.Award
    ml.Award = function(self, session, winnerName, response, ...)
        if suppressAward then return end
        if addon.isMasterLooter then
            return originalAward(self, session, winnerName, response, ...)
        end
        RC.RequestAward(session, winnerName, response, ...)
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

-- RC's masterLooter is a Player table (name/guid/class), not a string. AceComm
-- WHISPER requires a character name.
local function WhisperName(ml)
    if type(ml) == "string" and ml ~= "" then return ml end
    if type(ml) == "table" then
        if type(ml.name) == "string" and ml.name ~= "" then return ml.name end
        if type(ml.GetName) == "function" then
            local ok, name = pcall(ml.GetName, ml)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
    end
    return nil
end

local function GetMLName()
    local addon = RC.GetAddon()
    if not addon then return nil end
    local fromField = WhisperName(addon.masterLooter)
    if fromField then return fromField end
    if type(addon.GetML) == "function" then
        local ok, ml = pcall(addon.GetML, addon)
        if ok then
            local fromGet = WhisperName(ml)
            if fromGet then return fromGet end
        end
    end
    if addon.isMasterLooter then
        return WhisperName(UnitName("player")) or UnitName("player")
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

function RC.RequestAward(session, winnerName, response, ...)
    if not RC.IsRCLoaded() then return end
    local addon = RC.GetAddon()
    if addon.isMasterLooter then
        local ml = _G.RCLootCouncilML
        if not ml then return end
        if type(ml.Award) ~= "function" then
            if not mlMissingWarned.Award then
                mlMissingWarned.Award = true
                print("|cffff0000KART:|r RCLootCouncilML Award is missing")
            end
            return
        end
        pcall(ml.Award, ml, session, winnerName, response, ...)
        return
    end
    if KASC.CommsRestricted() then
        print((KART.L and KART.L.RC_AWARD_RESTRICTED)
            or "Award relay blocked while addon comms are restricted.")
        return
    end
    local mlName = GetMLName()
    if not mlName then return end
    KASC:Send("RC_AWARD:" .. session .. ":" .. winnerName .. ":" .. tostring(response),
        "WHISPER", mlName, { prio = "ALERT" })
end

function RC.HandleAwardRequest(payload, ctx)
    if ctx.channel ~= "WHISPER" then return end
    local addon = RC.GetAddon()
    if not addon or not addon.isMasterLooter then return end
    local session, winner, response = payload:match("^(%d+):(.*):(.+)$")
    if not session then return end
    session = tonumber(session)
    local guid = Identity.ResolvePlayer(ctx.sender)
    if not IsCouncilGUID(guid) then return end
    local ml = _G.RCLootCouncilML
    if not ml then return end
    if type(ml.Award) ~= "function" then
        if not mlMissingWarned.Award then
            mlMissingWarned.Award = true
            print("|cffff0000KART:|r RCLootCouncilML Award is missing")
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
    CallMLMethod(ml, "UpdateGroupCouncil")
    CallMLMethod(ml, "SendCouncil")
end

function RC.ForcePushCouncil()
    local L = KART.L or {}
    if not RC.IsRCLoaded() then
        print(L.RC_SYNC_NOT_LOADED
            or "|cffff0000KART:|r RCLootCouncil is not loaded — cannot sync the council.")
        return false
    end
    if not UnitIsGroupLeader("player") then
        print(L.RC_SYNC_NOT_LEAD
            or "|cffff0000KART:|r Only the raid leader can sync the council to RCLootCouncil.")
        return false
    end
    local tokens = RC.SplitCouncilField(KART_Settings.rcCouncilMembers or "")
    local guids = RC.ResolvedCouncilGUIDs()
    RC.PushCouncilToRC()
    print(string.format(L.RC_SYNC_COUNCIL_DONE or "|cff00ff00KART:|r Council synced: %d of %d names.",
        #guids, #tokens))
    return true
end

function RC.OnRosterUpdate()
    RC.PushCouncilToRC()
    if RC.IsRCLoaded() and not votingFrameHooked then
        RC.HookVotingFrame()
    end
end

function RC.UpdateStatusLabel()
    local lbl = RC.StatusLabel
    if not lbl then return end
    local L = KART.L or {}
    if RC.IsRCLoaded() then
        lbl:SetText(L.RC_STATUS_DETECTED or "RCLootCouncil detected")
        lbl:SetTextColor(0.2, 0.8, 0.2)
    else
        lbl:SetText(L.RC_STATUS_MISSING or "RCLootCouncil not loaded")
        lbl:SetTextColor(0.8, 0.5, 0.2)
    end
end

function RC.BuildSettingsCard()
    if RC.settingsBuilt or not KART.SettingsPanel or not KART.UI then return end
    RC.settingsBuilt = true
    local L = KART.L or {}
    local CONTENT_WIDTH = 460

    local card = KART.UI:CreateCard(KART.SettingsPanel)
    if KART.BtnProfile then
        local profCard = KART.BtnProfile:GetParent()
        card:SetPoint("TOPLEFT", profCard, "BOTTOMLEFT", 0, -20)
    else
        card:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -400)
    end
    card:SetSize(500, 210)
    RC.SettingsCard = card

    RC.StatusLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    RC.StatusLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -20)
    RC.StatusLabel:SetWidth(CONTENT_WIDTH)
    RC.StatusLabel:SetJustifyH("LEFT")
    KART.UI:RegisterLabel(RC.StatusLabel)

    RC.CbShowNickNames = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_RCShowNickNames", label = L.RC_SET_SHOW_NICKNAMES or "Show NSRT nicknames in RC voting frame",
        store = SettingsStore, key = "rcShowNickNames", y = -45,
        tooltip = L.RC_DESC_SHOW_NICKNAMES,
    })

    RC.CbShowOwedReminder = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_RCShowOwedReminder",
        label = L.RC_SET_OWED_REMINDER or "Show a trade reminder when I win an item",
        store = SettingsStore, key = "rcShowOwedReminder", y = -70,
        tooltip = L.RC_DESC_OWED_REMINDER,
        onChanged = function()
            if RC.RefreshOwedDisplay then RC.RefreshOwedDisplay() end
        end,
    })

    local lblCouncil = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblCouncil:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -110)
    lblCouncil:SetWidth(CONTENT_WIDTH)
    lblCouncil:SetJustifyH("LEFT")
    lblCouncil:SetText(L.RC_SET_COUNCIL or "Council members (semicolon-separated):")
    KART.UI:RegisterLabel(lblCouncil)

    RC.CouncilMembersEditBox = KART.UI:CreateStyledEditBox(card, "KART_RCCouncilMembers")
    local eb = RC.CouncilMembersEditBox
    eb:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -130)
    eb:SetSize(CONTENT_WIDTH - 150, 28)
    eb:SetMaxLetters(255)
    eb:SetScript("OnTextChanged", function(self)
        KART_Settings.rcCouncilMembers = self:GetText()
        RC.PushCouncilToRC()
    end)

    RC.BtnSyncCouncil = KART.UI:CreateModernButton(card,
        L.RC_BTN_SYNC_COUNCIL or "Sync to RC", L.RC_DESC_SYNC_COUNCIL)
    RC.BtnSyncCouncil:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    RC.BtnSyncCouncil:SetSize(142, 28)
    RC.BtnSyncCouncil:SetScript("OnClick", function()
        RC.ForcePushCouncil()
    end)

    RC.UpdateStatusLabel()
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
    RC.BuildSettingsCard()
    RC.UpdateStatusLabel()
    if type(RC.EnableOwed) == "function" then RC.EnableOwed() end
    if not RC.IsRCLoaded() then
        if not RC.warnedMissing then
            RC.warnedMissing = true
            print((KART.L and KART.L.RC_NEED_ADDON)
                or "|cffff0000KART:|r RCLootCouncil is not loaded — install it to use the RC companion.")
        end
        return
    end
    RC.HookVotingFrame()
end
