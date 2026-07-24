local addonName, KART = ...

KART.Version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"
local frame = CreateFrame("Frame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("READY_CHECK_CONFIRM")
frame:RegisterEvent("READY_CHECK_FINISHED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("UI_INFO_MESSAGE")

-- DataBroker Object für Minimap und Compartment
local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("KeineAhnungRaidTools", {
    type = "launcher",
    text = "KART",
    icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.png",
    OnClick = function(_, button)
        if button == "LeftButton" then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        elseif button == "RightButton" then
            if KART.MainFrame then KART.MainFrame:Show() KART.ShowTab(4) end
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Keine Ahnung Raid Tools")
        tooltip:AddLine("|cffeda55fLeft-Click:|r " .. KART.L.TAB_PROMOTE)
        tooltip:AddLine("|cffeda55fRight-Click:|r " .. KART.L.TAB_SETTINGS)
    end,
})

-- Re-applies every current KART_Settings value to its UI widget and refreshes every
-- settings-dependent module cache. Called once from ADDON_LOADED, and again after a profile
-- switch (KART.LoadProfile, Profiles.lua) — must stay free of one-time initialization
-- (AddonCompartment registration, hooksecurefunc) since those must never run twice.
function KART.SyncSettingsToUI()
    KART.UpdateCache()
    if KART.LC and KART.LC.BroadcastRaidConfig then KART.LC.BroadcastRaidConfig() end
    if KART.DT and KART.DT.RebuildIndex then KART.DT.RebuildIndex() end
    KART.UpdateStyles()

    -- Sammel-Initialisierung der UI Elemente
    local settingsMap = {}
    if KART.InviteEditBox then settingsMap[KART.InviteEditBox] = "inviteKeywords" end
    if KART.PromoteEditBox then settingsMap[KART.PromoteEditBox] = "promoteNames" end
    if KART.CbActivate then settingsMap[KART.CbActivate] = "showRaidleadBar" end
    if KART.CbLock then settingsMap[KART.CbLock] = "lockRaidleadBar" end
    if KART.CbAutoHide then settingsMap[KART.CbAutoHide] = "autoHideRaidleadBar" end
    if KART.PullSlider then settingsMap[KART.PullSlider] = "pullTimerDuration" end
    if KART.CbBcModuleEnabled then settingsMap[KART.CbBcModuleEnabled] = "bcModuleEnabled" end
    if KART.CbShowBuffCheck then settingsMap[KART.CbShowBuffCheck] = "showBuffCheck" end
    if KART.LC and KART.LC.CbModuleEnabled then settingsMap[KART.LC.CbModuleEnabled] = "lcModuleEnabled" end
    if KART.LC and KART.LC.CbAutoPass then settingsMap[KART.LC.CbAutoPass] = "lcAutoPass" end
    if KART.LC and KART.LC.CbCompactVoteLayout then settingsMap[KART.LC.CbCompactVoteLayout] = "lcVoteLayoutCompact" end
    if KART.LC and KART.LC.CbShowNickNames then settingsMap[KART.LC.CbShowNickNames] = "lcShowNickNames" end
    if KART.LC and KART.LC.CbRollsEnabled then settingsMap[KART.LC.CbRollsEnabled] = "lcRollsEnabled" end
    if KART.LC and KART.LC.SldVoteTimer then settingsMap[KART.LC.SldVoteTimer] = "lcVoteSeconds" end
    if KART.LC and KART.LC.SldFontSize then settingsMap[KART.LC.SldFontSize] = "lcFontSize" end
    if KART.LC and KART.LC.ButtonLabelEditBox then settingsMap[KART.LC.ButtonLabelEditBox] = "lcButtonLabels" end
    if KART.LC and KART.LC.CouncilMembersEditBox then settingsMap[KART.LC.CouncilMembersEditBox] = "lcCouncilMembers" end
    if KART.LC and KART.LC.LootmasterEditBox then settingsMap[KART.LC.LootmasterEditBox] = "lcLootmaster" end
    if KART.WU and KART.WU.CbModuleEnabled then settingsMap[KART.WU.CbModuleEnabled] = "wuModuleEnabled" end
    if KART.WU and KART.WU.ImportEditBox then settingsMap[KART.WU.ImportEditBox] = "wuImportText" end
    if KART.DT and KART.DT.CbModuleEnabled then settingsMap[KART.DT.CbModuleEnabled] = "dtModuleEnabled" end
    if KART.SldBuffCheckAlpha then settingsMap[KART.SldBuffCheckAlpha] = "buffCheckAlpha" end
    if KART.SldCombatDelay then settingsMap[KART.SldCombatDelay] = "bcCombatDelay" end
    if KART.CbGrayOffline then settingsMap[KART.CbGrayOffline] = "grayOffline" end
    if KART.CbMinimap then settingsMap[KART.CbMinimap] = "showMinimapIcon" end
    if KART.CbAutoRaid then settingsMap[KART.CbAutoRaid] = "autoConvertToRaid" end
    if KART.CbInviteViaGuildChat then settingsMap[KART.CbInviteViaGuildChat] = "inviteViaGuildChat" end
    if KART.CbAlEnabled then settingsMap[KART.CbAlEnabled] = "autoLogEnabled" end
    if KART.CbAlRaidLFR then settingsMap[KART.CbAlRaidLFR] = "autoLogRaidLFR" end
    if KART.CbAlRaidNormal then settingsMap[KART.CbAlRaidNormal] = "autoLogRaidNormal" end
    if KART.CbAlRaidHeroic then settingsMap[KART.CbAlRaidHeroic] = "autoLogRaidHeroic" end
    if KART.CbAlRaidMythic then settingsMap[KART.CbAlRaidMythic] = "autoLogRaidMythic" end
    if KART.CbAlMythicPlus then settingsMap[KART.CbAlMythicPlus] = "autoLogMythicPlus" end
    if KART.SldAlMinKey then settingsMap[KART.SldAlMinKey] = "autoLogMinKey" end
    if KART.CbAlDungeons then settingsMap[KART.CbAlDungeons] = "autoLogDungeons" end
    if KART.CbAlDelves then settingsMap[KART.CbAlDelves] = "autoLogDelves" end
    if KART.SldUiScale then settingsMap[KART.SldUiScale] = "uiScale" end
    if KART.SldMenuSize then settingsMap[KART.SldMenuSize] = "menuFontSize" end
    if KART.SldContentSize then settingsMap[KART.SldContentSize] = "contentFontSize" end
    if KART.SldBgAlpha then settingsMap[KART.SldBgAlpha] = "bgAlpha" end
    if KART.SldFrameStrata then settingsMap[KART.SldFrameStrata] = "frameStrata" end

    for widget, key in pairs(settingsMap) do
        if widget then
            if widget.SetChecked then widget:SetChecked(KART_Settings[key])
            elseif widget.SetValue then widget:SetValue(KART_Settings[key])
            elseif widget.SetText then widget:SetText(KART_Settings[key]) end
        end
    end
    -- Auto-parse saved WoWUtils import so boss buttons are ready immediately on login
    if KART.WU and KART.WU.ImportEditBox and KART_Settings.wuModuleEnabled ~= false and KART_Settings.wuImportText ~= "" then
        local count = KART.WU.ParseImport(KART_Settings.wuImportText)
        if count > 0 and KART.WU.RefreshBossList then
            KART.WU.RefreshBossList()
            if KART.WU.statusLabel then
                KART.WU.statusLabel:SetText(string.format(KART.L.WU_STATUS_LOADED, count))
                KART.WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
            end
        end
    end

    if KART.BtnFont then KART.BtnFont.text:SetText(KART.L.BTN_FONT_PREFIX .. (KART_Settings.fontName or "Standard")) end

    if KART.BtnLang then
        local langText = KART.L.LANG_AUTO
        if KART_Settings.language == "enUS" then langText = KART.L.LANG_EN
        elseif KART_Settings.language == "deDE" then langText = KART.L.LANG_DE end
        KART.BtnLang.text:SetText(KART.L.BTN_LANGUAGE_PREFIX .. langText)
    end

    if KART.KeybindButtons then
        for key, btn in pairs(KART.KeybindButtons) do
            local bound = KART_Settings.keybinds and KART_Settings.keybinds[key]
            btn.text:SetText(bound and bound ~= "" and bound or KART.L.KB_NOT_BOUND)
        end
    end

    if KART.LC and KART.LC.BtnMinQuality and KART.LC.QualityLabel then
        KART.LC.BtnMinQuality.text:SetText(KART.LC.QualityLabel(KART_Settings.lcMinQuality or 4))
    end

    if KART.LC and KART.LC.BtnVotedItemDisplay and KART.LC.VotedItemDisplayLabel then
        KART.LC.BtnVotedItemDisplay.text:SetText(KART.LC.VotedItemDisplayLabel(KART_Settings.lcVotedItemDisplay or "full"))
    end

    if KART.RefreshProfileButton then KART.RefreshProfileButton() end

    KART.UpdateMinimapButton()
    KART.UpdateRaidleadBarVisibility()
    KART.ApplyKeybinds()
end

-- CHAT_MSG_ADDON dispatch. A message is either a fixed token (EXACT_HANDLERS) or
-- "PREFIX:payload" (PREFIX_HANDLERS, keyed by the part before the FIRST colon — payloads may
-- contain further colons; each handler parses its own format). Entries with lc = true only
-- run while the Loot Council module is enabled; LC_SYNC_ACCEPT/DECLINE deliberately skip that
-- gate (a decline must still print even if the receiver just disabled the module).
-- ctx = { sender = full sender name, shortName, channel }.
local function SenderKey(ctx)
    return (KART.Identity.ResolvePlayer(ctx.sender))
end

local function HandleVersionMessage(payload, ctx, isAnnounce)
    local ver, lcFlag = payload:match("^([^:]+):?([01]?)$")
    ver = ver or payload

    KART.PlayerVersions = KART.PlayerVersions or {}
    KART.PlayerVersions[ctx.shortName] = ver
    if lcFlag == "1" or lcFlag == "0" then
        KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
        KART.PlayerLCEnabled[ctx.shortName] = (lcFlag == "1")
    end
    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
    end

    if not KART.UpdateWarned and ver ~= KART.Version then
        local nMaj, nMin, nPat = ver:match("(%d+)%.(%d+)%.(%d+)")
        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.(%d+)%.(%d+)")
        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0
        if nMaj > oMaj or (nMaj == oMaj and nMin > oMin) or (nMaj == oMaj and nMin == oMin and nPat > oPat) then
            KART.UpdateWarned = true
            print(string.format(KART.L.UPDATE_AVAILABLE, ver, KART.Version))
        end
    end

    if KART.VersionCheckActive and not isAnnounce then
        print(string.format(KART.L.VERSION_CHECK_RES, ctx.shortName, ver))
    end
end

local EXACT_HANDLERS = {
    REQ_OIL = { fn = function(_, ctx)
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        local outMH = (hasMH and mhID) and mhID or 0
        local outOH = (hasOH and ohID) and ohID or 0
        if IsInGroup() then
            C_ChatInfo.SendAddonMessage("KART", "OIL:" .. outMH .. ":" .. outOH, IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_ILVL = { fn = function(_, ctx)
        local _, equipped = GetAverageItemLevel()
        if equipped and IsInGroup() then
            C_ChatInfo.SendAddonMessage("KART", "ILVL:" .. string.format("%.1f", equipped), IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_GEAR = { fn = function(_, ctx)
        if IsInGroup() then
            local e, g = KART.CountMissingGear()
            C_ChatInfo.SendAddonMessage("KART", "GEAR:" .. e .. ":" .. g, IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_VERSION = { fn = function(_, ctx)
        local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
        if ctx.channel == "WHISPER" then
            C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, "WHISPER", ctx.sender)
        else
            C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, ctx.channel)
        end
    end },
    LC_SYNC_ACCEPT  = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncAccept(ctx.shortName) end end },
    LC_SYNC_DECLINE = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncDecline(ctx.shortName) end end },
    LC_STATE_REQ    = { lc = true, fn = function(_, ctx) KART.LC.HandleStateRequest() end },
}

local PREFIX_HANDLERS = {
    OIL = { fn = function(payload, ctx)
        local mhID, ohID = payload:match("^(%d+):(%d+)")
        if mhID and ohID then
            KART.OilCache = KART.OilCache or {}
            KART.OilCache[ctx.shortName] = { mh = tonumber(mhID), oh = tonumber(ohID) }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    ILVL = { fn = function(payload, ctx)
        local ilvl = tonumber(payload)
        if ilvl then
            KART.ILvlCache = KART.ILvlCache or {}
            KART.ILvlCache[ctx.shortName] = ilvl
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    GEAR = { fn = function(payload, ctx)
        local e, g = payload:match("^([^:]+):([^:]+)")
        if e and g then
            KART.GearCache = KART.GearCache or {}
            KART.GearCache[ctx.shortName] = { enchants = e, gems = g }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    VERSION          = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, false) end },
    ANNOUNCE_VERSION = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, true) end },
    LC_ACTIVE       = { lc = true, fn = function(payload, ctx) KART.LC.HandleActive(payload, SenderKey(ctx)) end },
    LC_START        = { lc = true, fn = function(payload, ctx) KART.LC.HandleStart(payload, SenderKey(ctx)) end },
    LC_MANUAL_START = { lc = true, fn = function(payload, ctx) KART.LC.HandleManualStart(payload, SenderKey(ctx)) end },
    LC_VOTE         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleVote(payload, SenderKey(ctx)) end },
    LC_ROLL         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleRoll(payload, SenderKey(ctx)) end },
    LC_CVOTE        = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleCouncilVote(payload, SenderKey(ctx)) end },
    LC_ONOTE        = { lc = true, fn = function(payload, ctx) KART.LC.OfficerNotes.HandleOfficerNote(payload, SenderKey(ctx)) end },
    LC_RESULT       = { lc = true, fn = function(payload, ctx) KART.LC.Trade.HandleResult(payload, SenderKey(ctx)) end },
    LC_CONFIG       = { lc = true, fn = function(payload, ctx) KART.LC.HandleConfig(payload, SenderKey(ctx)) end },
    LC_HIST_REQ     = { lc = true, fn = function(payload, ctx) KART.LH.HandleHistoryRequest(payload, ctx.sender) end },
    LC_HIST_ENTRY   = { lc = true, fn = function(payload, ctx) KART.LH.HandleHistoryEntry(payload, SenderKey(ctx)) end },
    LC_SYNC_REQUEST = { lc = true, fn = function(payload, ctx) KART.LC.HandleSyncRequest(payload, ctx.sender, ctx.shortName) end },
    RC_REASON = { fn = function(payload, ctx)
        KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
        KART.ReadyCheckReasons[ctx.shortName] = payload
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            print(string.format(KART.L.RC_REASON_RECEIVED, ctx.shortName, payload))
        end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end },
}

frame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        C_ChatInfo.RegisterAddonMessagePrefix("KART")

        KART_Settings = KART_Settings or {}
        KART_LootHistory = KART_LootHistory or {}
        KART_LCOfficerNotes = KART_LCOfficerNotes or {}
        KART_WoWUtilsCache = KART_WoWUtilsCache or {}
        KART_Profiles = KART_Profiles or {}
        KART_PlayerCache = KART_PlayerCache or {}
        -- Prune identity-cache entries not seen for 90+ days so the SavedVariable doesn't
        -- grow forever (it gains one entry per distinct group member ever encountered).
        local pruneCutoff = time() - 90 * 24 * 60 * 60
        for guid, entry in pairs(KART_PlayerCache) do
            if (entry.lastSeen or 0) < pruneCutoff then KART_PlayerCache[guid] = nil end
        end
        if KART_Settings.language == nil then KART_Settings.language = "Auto" end

        -- Apply language: copy the chosen locale's VALUES into KART.L instead of replacing
        -- the reference — several files capture `local L = KART.L` at load time, and all
        -- statically-built UI re-reads via locale refreshers below. enUS is the base; deDE
        -- overlays it, so missing German keys fall back to English automatically.
        local currentLang = KART_Settings.language
        if currentLang == "Auto" then currentLang = GetLocale() end
        wipe(KART.L)
        for k, v in pairs(KART.L_enUS) do KART.L[k] = v end
        if currentLang == "deDE" and KART.L_deDE then
            for k, v in pairs(KART.L_deDE) do KART.L[k] = v end
        end

        -- The default vote-button set is user-visible text — pick it from the active locale
        -- before the Defaults merge fills a fresh KART_Settings.
        KART.Defaults.lcButtonLabels = KART.L.LC_DEFAULT_BUTTONS

        -- Deep-copy table defaults (keybinds, minimap): assigning them by reference let the
        -- live settings mutate KART.Defaults itself, which then made "Reset Defaults" a no-op
        -- for those keys within the same session.
        for k, v in pairs(KART.Defaults) do
            if KART_Settings[k] == nil then
                KART_Settings[k] = type(v) == "table" and KART.DeepCopy(v) or v
            end
        end

        -- Minimap Icon mit LibDBIcon registrieren
        KART_Settings.minimap = KART_Settings.minimap or {}
        local dbIcon = LibStub("LibDBIcon-1.0", true)
        if dbIcon then
            dbIcon:Register("KeineAhnungRaidTools", ldb, KART_Settings.minimap)
        end

        -- Re-apply every statically-built UI text with the now-selected language.
        KART.ApplyLocaleRefreshers()

        KART.SyncSettingsToUI()

        AddonCompartmentFrame:RegisterAddon({
            text = "Keine Ahnung Raid Tools",
            icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.png", -- addon icon path
            registerForAnyClick = true,
            func = function() 
                if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
            end,
        })
        
        -- Hook für den erweiterten Ready-Check
        hooksecurefunc("ConfirmReadyCheck", function(isReady)
            if not isReady or isReady == 0 then
                if IsInGroup() then
                    KART.ShowReadyCheckReasonDialog()
                end
            else
                if KART.RCDialog then KART.RCDialog:Hide() end
            end
        end)

        -- Set the real version (KART.Version only becomes available here)
        if KART.MainFrame and KART.MainFrame.versionText then
            KART.MainFrame.versionText:SetText("v" .. KART.Version)
        end

        -- Styles nach der Erstellung aller Frames final anwenden
        KART.UpdateStyles()

    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        if event ~= "CHAT_MSG_GUILD" or KART_Settings.inviteViaGuildChat then
            KART.HandleChatInvite(arg1, arg2, event, ...)
        end

    elseif event == "START_LOOT_ROLL" then
        if KART.LC then KART.LC.OnStartLootRoll(arg1) end

    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.Trade.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.Trade.OnTradeClosed() end

    elseif event == "TRADE_ACCEPT_UPDATE" then
        if KART.LC then KART.LC.Trade.OnTradeAcceptUpdate() end

    elseif event == "UI_INFO_MESSAGE" then
        if KART.LC then KART.LC.Trade.OnTradeInfoMessage(arg1) end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if KART.LC then KART.LC.CheckRaidJoin() end
        if KART.LC and KART.LC.UpdateRoleStatusLabel then KART.LC.UpdateRoleStatusLabel() end
        if KART.LC and KART.LC.RetryPendingResolutionsThrottled then KART.LC.RetryPendingResolutionsThrottled() end
        KART.UpdateRaidleadBarVisibility()

        if IsInGroup() and not KART.VersionAnnouncedToGroup then
            local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
            C_ChatInfo.SendAddonMessage("KART", "ANNOUNCE_VERSION:" .. KART.Version .. ":" .. lcFlag, IsInRaid() and "RAID" or "PARTY")
            KART.VersionAnnouncedToGroup = true
            -- Our own one-shot announce only tells the group about US — it does nothing for
            -- players who already announced before we joined, so also pull everyone else's
            -- current version the same way /kart v already does, instead of only finding out
            -- about mismatches/missing-KART players whenever someone happens to run that manually.
            C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", IsInRaid() and "RAID" or "PARTY")
        elseif not IsInGroup() then
            KART.VersionAnnouncedToGroup = false
        end

        -- Performance: Update BuffCheck nur wenn Fenster offen
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end

        if KART_Settings.autoConvertToRaid and not InCombatLockdown() and UnitIsGroupLeader("player") and GetNumGroupMembers() > 5 and not IsInRaid() then
            C_PartyInfo.ConvertToRaid()
        end
        KART.HandleAutoPromoteThrottled()
        
    elseif event == "READY_CHECK" then
        KART.ReadyCheckReasons = wipe(KART.ReadyCheckReasons or {})
        if KART.RCDialog then KART.RCDialog:Hide() end
        if KART_Settings.showBuffCheck and KART.ShowBuffCheck then
            KART.ShowBuffCheck()
            -- LibDurability is LibStub-only (no global) — a bare global lookup here was always
            -- nil, so the durability request on ready check never fired.
            local durabilityLib = LibStub and LibStub("LibDurability", true)
            if durabilityLib and durabilityLib.RequestDurability then
                durabilityLib:RequestDurability()
            end
        end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            KART.UpdateBuffCheckThrottled()
        end
    elseif event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            KART.UpdateBuffCheckThrottled()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if KART.RCDialog then KART.RCDialog:Hide() end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            local delay = KART_Settings.bcCombatDelay or 2
            C_Timer.After(delay > 0 and delay or 0.01, function()
                if KART.BuffCheckFrame then
                    KART.BuffCheckFrame:Hide()
                end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Aktualisiert ausstehende UI- und Makro-Änderungen (z.B. Pull-Timer), 
        -- die während des Kampfes sicherheitshalber blockiert wurden.
        KART.UpdateRaidleadBarVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, function()
            if IsInGuild() then
                local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
                C_ChatInfo.SendAddonMessage("KART", "ANNOUNCE_VERSION:" .. KART.Version .. ":" .. lcFlag, "GUILD")
            end
        end)
        if KART.AutoLog then KART.AutoLog.Evaluate() end
        -- Retry now that every addon has loaded — a LibDurability provider that loads after KART
        -- (e.g. MRT) is nil at BuffChecker parse time. Idempotent (see KART.RegisterLibDurability).
        if KART.RegisterLibDurability then KART.RegisterLibDurability() end
    elseif event == "CHALLENGE_MODE_START" then
        if KART.AutoLog then KART.AutoLog.Evaluate() end
    elseif event == "CHAT_MSG_ADDON" and arg1 == "KART" then
        local msg = arg2
        local channel = select(1, ...)
        local sender = select(2, ...)
        if sender then
            local shortName = sender:match("([^%-]+)")
            if shortName then
                local ctx = { sender = sender, shortName = shortName, channel = channel }
                local prefix, payload = msg:match("^([^:]+):(.*)$")
                local entry = (prefix and PREFIX_HANDLERS[prefix]) or EXACT_HANDLERS[msg]
                if entry and not (entry.lc and not (KART.LC and KART_Settings.lcModuleEnabled ~= false)) then
                    entry.fn(payload, ctx)
                end
            end
        end
    end
end)

-- Styles Update (Muss global zugänglich sein)
function KART.UpdateStyles()
    if not KART_Settings or not KART.MainFrame then return end -- KART.MainFrame aus MainFrame.lua
    KART.ApplyFrameStrata()
    local fontPath = KART.GetFontPath(KART_Settings.fontName)
    local r, g, b = KART_Settings.accentR/100, KART_Settings.accentG/100, KART_Settings.accentB/100
    local titleSize = KART_Settings.titleFontSize or 11
    local menuSize = KART_Settings.menuFontSize or 11
    local contentSize = KART_Settings.contentFontSize or 12
    
    -- The main window is a baked PNG artwork: no backdrop/gradient to tint.
    -- bgAlpha now controls whole-window opacity; floor of 20 so the window
    -- can never become fully invisible while still blocking mouse input.
    KART.MainFrame:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100)
    -- Deferred while the scale slider is being dragged: rescaling the window mid-drag moves the
    -- slider under the cursor, which feeds back into new values and makes the thumb jump. The
    -- slider's OnMouseUp hook (MainFrame.lua) re-runs UpdateStyles to apply the final value.
    if not (KART.SldUiScale and KART.SldUiScale.isDragging) then
        KART.MainFrame:SetScale((KART_Settings.uiScale or 100) / 100)
    end

    -- Sidebar Buttons
    for _, btnText in ipairs(KART.ButtonTexts) do
        btnText:SetFont(fontPath, menuSize, "")
    end

    -- Eingabefelder
    for _, eb in ipairs(KART.EditBoxes) do
        eb:SetFont(fontPath, contentSize, "")
    end
    
    -- Alle registrierten Labels (Slider-Beschriftungen etc.) aktualisieren
    for _, label in ipairs(KART.DynamicLabels) do
        label:SetFont(fontPath, contentSize, "")
    end

    -- Close-button "×" glyphs not already covered by a per-frame update below (Loot History,
    -- Loot Council's vote popup and council panel) — see KART.CloseButtonTexts in Utils.lua.
    for _, t in ipairs(KART.CloseButtonTexts) do
        t:SetFont(fontPath, 14, "OUTLINE")
    end

    -- Ein Font-Wechsel kann Labels anders umbrechen lassen (mehr/weniger Zeilen) — Boxen mit
    -- text-abhängiger Höhenberechnung müssen danach neu positioniert werden.
    if KART.LC and KART.LC.RelayoutRaidBox then KART.LC.RelayoutRaidBox() end

    -- Slider-Thumbs und Checkboxen färben
    for _, thumb in ipairs(KART.SliderThumbs) do thumb:SetColorTexture(r, g, b, 1) end
    for _, check in ipairs(KART.CheckVisuals) do check:SetColorTexture(r, g, b, 1) end
    -- Header lines on popup windows (see KART.CreateHeaderLine)
    for _, line in ipairs(KART.AccentLines or {}) do line:SetColorTexture(r, g, b, 0.6) end

    -- Re-apply the active tab's background tint and each checked toggle's track color, since
    -- those aren't simple SetColorTexture calls (they depend on Darken() with different amounts
    -- and on current checked/active state) and so can't be folded into the loops above.
    for _, btn in ipairs(KART.TabButtons or {}) do
        if btn.RefreshActiveColor then btn:RefreshActiveColor() end
    end
    for _, cb in ipairs(KART.ToggleCheckboxes or {}) do
        if cb.RefreshVisual then cb:RefreshVisual() end
    end

    -- Farbvorschauen im Settings-Menü aktualisieren
    if KART.ColorPreview then KART.ColorPreview:SetColorTexture(r, g, b, 1) end

    -- Minimap Icon Farbe anpassen
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then
        local iconButton = dbIcon:GetMinimapButton("KeineAhnungRaidTools")
        if iconButton and iconButton.icon then
            iconButton.icon:SetVertexColor(r, g, b)
        end
    end

    if KART.ScrollThumb then KART.ScrollThumb:SetColorTexture(r, g, b, 0.6) end -- KART.ScrollThumb aus MainFrame.lua
    if KART.BuffScrollThumb then KART.BuffScrollThumb:SetColorTexture(r, g, b, 0.6) end
    if KART.WUPasteScrollThumb then KART.WUPasteScrollThumb:SetColorTexture(r, g, b, 0.6) end
    if KART.LHScrollThumb then KART.LHScrollThumb:SetColorTexture(r, g, b, 0.6) end
    if KART.LHExportScrollThumb then KART.LHExportScrollThumb:SetColorTexture(r, g, b, 0.6) end

    if KART.LH and KART.LH.historyWindow then
        local w = KART.LH.historyWindow
        -- Artwork background: only the ground texture fades with bgAlpha, content stays solid.
        if w.bg then w.bg:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100) end
        if w.title then
            w.title:SetFont(fontPath, titleSize, "OUTLINE")
            w.title:SetTextColor(1, 1, 1)
        end
    end

    if KART.BuffCheckFrame then
        -- Artwork background: only the ground texture fades with buffCheckAlpha so rows,
        -- buttons and text stay fully readable at low opacities.
        if KART.BuffCheckFrame.bg then
            KART.BuffCheckFrame.bg:SetAlpha((KART_Settings.buffCheckAlpha or 95) / 100)
        end
        if KART.BuffCheckFrame.title then
            KART.BuffCheckFrame.title:SetFont(fontPath, titleSize, "OUTLINE")
            KART.BuffCheckFrame.title:SetTextColor(1, 1, 1)
        end
        -- Headers im BuffChecker
        if KART.BuffCheckFrame.hName then KART.BuffCheckFrame.hName:SetFont(fontPath, 10, "") end
        if KART.BuffCheckFrame.hRdy then KART.BuffCheckFrame.hRdy:SetFont(fontPath, 10, "") end
        if KART.BuffCheckFrame.hIlvl then KART.BuffCheckFrame.hIlvl:SetFont(fontPath, 10, "") end
        if KART.BuffCheckFrame.headerStrings then
            for _, h in pairs(KART.BuffCheckFrame.headerStrings) do
                h:SetFont(fontPath, 10, "")
            end
        end
        -- Spielerzeilen im BuffChecker
        if KART.BuffCheckFrame.rows then
            for _, row in ipairs(KART.BuffCheckFrame.rows) do
                if row.name then row.name:SetFont(fontPath, contentSize, "") end
                if row.ilvlText then row.ilvlText:SetFont(fontPath, contentSize, "") end
                for _, ind in pairs(row.indicators) do
                    if ind.SetFont then ind:SetFont(fontPath, contentSize, "") end
                    if ind.text and ind.text.SetFont then ind.text:SetFont(fontPath, contentSize, "") end
                end
            end
        end
    end

    if KART.LC and KART.LC.ApplyFontSize then KART.LC.ApplyFontSize() end

    -- Font changes can re-flow the Loot Council raid box (RelayoutRaidBox above), which
    -- changes the active tab's content height — keep the scroll range in sync.
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
end

-- UI für den erweiterten Ready-Check Grund
function KART.ShowReadyCheckReasonDialog()
    if not KART.RCDialog then
        local f = CreateFrame("Frame", "KART_RCReasonFrame", UIParent, "BackdropTemplate")
        f:SetSize(260, 115)
        f:SetPoint("CENTER", 0, 150)
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -10)
        f.title:SetText(KART.L.RC_REASON_TITLE)

        local function sendReason(reasonKey, fallback)
            local text = fallback
            if reasonKey and KART.L[reasonKey] then
                text = KART.L[reasonKey]
            end
            local chan = IsInRaid() and "RAID" or "PARTY"
            if IsInGroup() then
                C_ChatInfo.SendAddonMessage("KART", "RC_REASON:" .. text, chan)
            end
            f:Hide()
        end

        local btnBio = KART.CreateModernButton(f, KART.L.RC_REASON_BIO)
        btnBio:SetSize(75, 25)
        btnBio:SetPoint("TOPLEFT", 10, -35)
        btnBio:SetScript("OnClick", function() sendReason("RC_REASON_BIO", "Bio") end)

        local btnDrink = KART.CreateModernButton(f, KART.L.RC_REASON_DRINK)
        btnDrink:SetSize(75, 25)
        btnDrink:SetPoint("TOP", 0, -35)
        btnDrink:SetScript("OnClick", function() sendReason("RC_REASON_DRINK", "Trinken") end)

        local btn1Min = KART.CreateModernButton(f, KART.L.RC_REASON_1MIN)
        btn1Min:SetSize(75, 25)
        btn1Min:SetPoint("TOPRIGHT", -10, -35)
        btn1Min:SetScript("OnClick", function() sendReason("RC_REASON_1MIN", "1 Min") end)

        -- Textfeld für eigenen Grund
        local customInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        customInput:SetSize(155, 25)
        customInput:SetPoint("BOTTOMLEFT", 10, 15)
        customInput:SetAutoFocus(false)
        customInput:SetFontObject("GameFontHighlightSmall")
        customInput:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        customInput:SetBackdropColor(0, 0, 0, 0.8)
        customInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        customInput:SetTextInsets(5, 5, 0, 0)
        customInput:SetMaxLetters(30) -- Verhindert, dass Leute ganze Romane schreiben
        KART.ApplyRoundedMask(customInput, KART.Theme.CORNER_RADIUS_SM)
        table.insert(KART.EditBoxes, customInput)
        
        local btnSend = KART.CreateModernButton(f, KART.L.RC_REASON_SEND)
        btnSend:SetSize(70, 25)
        btnSend:SetPoint("LEFT", customInput, "RIGHT", 10, 0)
        btnSend:SetScript("OnClick", function()
            local text = KART.TrimString(customInput:GetText())
            if text ~= "" then sendReason(nil, text) end
        end)
        
        customInput:SetScript("OnEnterPressed", function(self)
            local text = KART.TrimString(self:GetText())
            if text ~= "" then sendReason(nil, text) else self:ClearFocus() end
        end)
        customInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        f.customInput = customInput
        KART.RCDialog = f
        table.insert(KART.DynamicLabels, f.title)
        KART.UpdateStyles()
    end
    if KART.RCDialog.customInput then KART.RCDialog.customInput:SetText("") end
    KART.RCDialog:Show()
    C_Timer.After(15, function() if KART.RCDialog and KART.RCDialog:IsShown() then KART.RCDialog:Hide() end end)
end

SLASH_KART1 = "/kart"
SlashCmdList["KART"] = function(msg) -- Slash-Befehl zum Öffnen/Schließen des Hauptfensters
    -- rawMsg keeps original case (needed for the "add" subcommand's item-link arguments — item
    -- hyperlinks use case-sensitive |H/|h control codes that :lower() would corrupt); cmd is the
    -- lowercased form every other subcommand below already matches against.
    local rawMsg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = rawMsg:lower()
    if cmd == "version" or cmd == "v" then
        local channel = "GUILD"
        if IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY" end
        print(KART.L.VERSION_CHECK_REQ)
        KART.VersionCheckActive = true
        C_Timer.After(5, function() KART.VersionCheckActive = false end)
        C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", channel)
    elseif cmd == "add" or cmd:match("^add%s") then
        local itemsText = rawMsg:match("^%S+%s+(.+)$") or ""
        if KART.LC then KART.LC.StartManualRoll(itemsText) end
    elseif cmd == "lc" then
        -- Reopens whichever Loot Council window still has tracked, unfinished rolls — does
        -- nothing (rather than error) if there's genuinely nothing being tracked right now.
        if KART.LC then
            if KART.LC.councilPanel and #KART.LC.councilTabs > 0 then
                KART.LC.councilPanel:Show()
            elseif KART.LC.voteListFrame and #KART.LC.voteListRolls > 0 then
                KART.LC.voteListFrame:Show()
            end
        end
    elseif cmd == "trade" then
        if KART.LC and KART.LC.tradeReminderFrame and #KART.LC.pendingTrades > 0 then
            KART.LC.tradeReminderFrame:Show()
        end
    elseif cmd == "showall" then
        -- Reveals every currently active roll in the vote-list window, including ones already
        -- voted on and hidden by KART_Settings.lcVotedItemDisplay == "hide" (see
        -- Vote.GetVisibleRolls). No-op if nothing is currently tracked, same as /kart lc / /kart trade.
        if KART.LC and KART.LC.Vote then
            KART.LC.showAllOverride = true
            KART.LC.Vote.RefreshVoteListRows()
        end
    elseif cmd == "help" or cmd == "h" then
        print(KART.L.HELP_HEADER)
        print("  /kart - " .. KART.L.HELP_TOGGLE)
        print("  /kart version (v) - " .. KART.L.HELP_VERSION)
        print("  /kart lc - " .. KART.L.HELP_LC)
        print("  /kart add <item link> - " .. KART.L.HELP_ADD)
        print("  /kart trade - " .. KART.L.HELP_TRADE)
        print("  /kart showall - " .. KART.L.HELP_SHOWALL)
        print("  /kart help (h) - " .. KART.L.HELP_HELP)
    else
        -- Sicherheitscheck: Falls das MainFrame (noch) nicht existiert, Fehler verhindern
        if KART.MainFrame then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        end
    end
end