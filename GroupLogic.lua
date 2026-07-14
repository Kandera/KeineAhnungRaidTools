local addonName, KART = ...

-- Cache-Tabellen
KART.InviteKeywordsTable = {}
KART.PromoteNamesTable = {}

-- Aktualisiert die lokalen Such-Tabellen basierend auf den Einstellungen
function KART.UpdateCache()
    if KART_Settings then
        local keywords = KART.SplitString(KART_Settings.inviteKeywords:lower(), ";")
        KART.InviteKeywordsTable = {}
        for _, kw in ipairs(keywords) do 
            local trimmed = KART.TrimString(kw)
            if trimmed ~= "" then KART.InviteKeywordsTable[trimmed] = true end 
        end

        local names = KART.SplitString(KART_Settings.promoteNames:lower(), ";")
        KART.PromoteNamesTable = {}
        for _, name in ipairs(names) do KART.PromoteNamesTable[name] = true end
    end
end

-- Logik für Keyword-Einladungen
function KART.HandleChatInvite(msg, sender, event, ...)
    if type(msg) ~= "string" then return end
    local success, lowerMsg = pcall(string.lower, msg)
    if not success then return end
    
    local message = KART.TrimString(lowerMsg)
    
    if KART.InviteKeywordsTable[message] and (not IsInGroup() or KART.HasGroupPermissions()) then
        if KART_Settings.autoConvertToRaid and IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 and not InCombatLockdown() then
            C_PartyInfo.ConvertToRaid()
        end

        if event == "CHAT_MSG_BN_WHISPER" then
            local bnetIDAccount = select(11, ...)
            if bnetIDAccount then
                local accountInfo = C_BattleNet.GetAccountInfoByID(bnetIDAccount)
                if accountInfo and accountInfo.gameAccountInfo then
                    C_PartyInfo.InviteUnit(accountInfo.gameAccountInfo.gameAccountID)
                end
            end
        else
            C_PartyInfo.InviteUnit(sender)
        end
    end
end

-- GROUP_ROSTER_UPDATE fires in bursts during mass-invite/raid formation, and a full roster scan on
-- every single firing burns CPU for no benefit — the promote outcome only needs re-evaluating once
-- the roster has settled. Same leading-edge throttle pattern as KART.UpdateBuffCheckThrottled.
local isAutoPromoteThrottled = false
function KART.HandleAutoPromoteThrottled()
    if isAutoPromoteThrottled then return end
    isAutoPromoteThrottled = true
    C_Timer.After(1, function()
        isAutoPromoteThrottled = false
        KART.HandleAutoPromote()
    end)
end

-- Logik für Auto-Promote
function KART.HandleAutoPromote()
    if not UnitIsGroupLeader("player") or not (IsInGroup() or IsInRaid()) then return end
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    
    for i = 1, numMembers do
        local unit = isRaid and ("raid"..i) or (i == numMembers and "player" or "party"..i)
        local name = UnitName(unit)
        if name then
            local shortName = name:match("([^%-]+)")
            if shortName and KART.PromoteNamesTable[shortName:lower()] then
                if not UnitIsGroupAssistant(unit) and not UnitIsGroupLeader(unit) then
                    PromoteToAssistant(name)
                end
            end
        end
    end
end
