local addonName, KART = ...

KART.Version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.12.2"
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
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("TRADE_SHOW")

-- DataBroker Object für Minimap und Compartment
local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("KeineAhnungRaidTools", {
    type = "launcher",
    text = "KART",
    icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.jpg",
    OnClick = function(_, button)
        if button == "LeftButton" then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        elseif button == "RightButton" then
            if KART.MainFrame then KART.MainFrame:Show() KART.ShowTab(4) end
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Keine Ahnung Raid Tools")
        tooltip:AddLine("|cffeda55fLeft-Click:|r " .. (KART.L.TAB_PROMOTE or "Open"))
        tooltip:AddLine("|cffeda55fRight-Click:|r " .. (KART.L.TAB_SETTINGS or "Settings"))
    end,
})

frame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        C_ChatInfo.RegisterAddonMessagePrefix("KART")

        KART_Settings = KART_Settings or {}
        KART_LootHistory = KART_LootHistory or {}
        KART_LCOfficerNotes = KART_LCOfficerNotes or {}
        KART_WoWUtilsCache = KART_WoWUtilsCache or {}
        if KART_Settings.language == nil then KART_Settings.language = "Auto" end

        for k, v in pairs(KART.Defaults) do
            if KART_Settings[k] == nil then KART_Settings[k] = v end
        end

        -- Sprache anwenden
        local currentLang = KART_Settings.language
        if currentLang == "Auto" then currentLang = GetLocale() end
        
        if currentLang == "deDE" and KART.L_deDE then
            setmetatable(KART.L_deDE, { __index = KART.L_enUS })
            KART.L = KART.L_deDE
        elseif KART.L_enUS then
            -- Fallback auf Englisch (enUS) für alle anderen Clients (z.B. frFR, ruRU)
            KART.L = KART.L_enUS
        end

        KART.UpdateCache()
        if KART.LC and KART.LC.UpdateCouncilCache then KART.LC.UpdateCouncilCache() end
        if KART.DT and KART.DT.RebuildIndex then KART.DT.RebuildIndex() end
        KART.UpdateStyles()

        -- Minimap Icon mit LibDBIcon registrieren
        KART_Settings.minimap = KART_Settings.minimap or {}
        local dbIcon = LibStub("LibDBIcon-1.0", true)
        if dbIcon then
            dbIcon:Register("KeineAhnungRaidTools", ldb, KART_Settings.minimap)
        end
        
        -- Initialisiere UI Werte
        if KART.InviteEditBox then KART.InviteEditBox:SetText(KART_Settings.inviteKeywords) end -- KART.InviteEditBox aus MainFrame.lua
        if KART.PromoteEditBox then KART.PromoteEditBox:SetText(KART_Settings.promoteNames) end -- KART.PromoteEditBox aus MainFrame.lua
        
        -- Raidlead Panel Initialisierung
        if KART.CbActivate then KART.CbActivate:SetChecked(KART_Settings.showRaidleadBar) end

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
        if KART.LC and KART.LC.CbRollsEnabled then settingsMap[KART.LC.CbRollsEnabled] = "lcRollsEnabled" end
        if KART.LC and KART.LC.SldVoteTimer then settingsMap[KART.LC.SldVoteTimer] = "lcVoteSeconds" end
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
        if KART.SldTitleSize then settingsMap[KART.SldTitleSize] = "titleFontSize" end
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
                    KART.WU.statusLabel:SetText(string.format(KART.L.WU_STATUS_LOADED or "%d bosses loaded.", count))
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

        if KART.LC and KART.LC.BtnMinQuality and KART.LC.QualityLabel then
            KART.LC.BtnMinQuality.text:SetText(KART.LC.QualityLabel(KART_Settings.lcMinQuality or 4))
        end

        KART.UpdateMinimapButton()
        KART.UpdateRaidleadBarVisibility()

        AddonCompartmentFrame:RegisterAddon({
            text = "Keine Ahnung Raid Tools",
            icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.jpg", -- Pfad zum Addon-Icon
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

        -- Korrekte Version in Titelleiste setzen (KART.Version ist erst hier verfügbar)
        if KART.MainFrame and KART.MainFrame.title then
            KART.MainFrame.title:SetText((KART.L.ADDON_TITLE or "Keine Ahnung Raid Tools") .. " v" .. KART.Version)
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
        if KART.LC then KART.LC.OnTradeShow() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if KART.LC then KART.LC.CheckRaidJoin() end
        if KART.LC and KART.LC.UpdateRoleStatusLabel then KART.LC.UpdateRoleStatusLabel() end
        KART.UpdateRaidleadBarVisibility()

        if IsInGroup() and not KART.VersionAnnouncedToGroup then
            local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
            C_ChatInfo.SendAddonMessage("KART", "ANNOUNCE_VERSION:" .. KART.Version .. ":" .. lcFlag, IsInRaid() and "RAID" or "PARTY")
            KART.VersionAnnouncedToGroup = true
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
            if LibDurability and LibDurability.RequestDurability then
                LibDurability:RequestDurability()
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
    elseif event == "CHAT_MSG_ADDON" and arg1 == "KART" then
        local msg = arg2
        local channel = select(1, ...)
        local sender = select(2, ...)
        
        if sender then
            local shortName = sender:match("([^%-]+)")
            if shortName then
                if msg == "REQ_OIL" then
                    local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
                    local outMH = (hasMH and mhID) and mhID or 0
                    local outOH = (hasOH and ohID) and ohID or 0
                    if IsInGroup() then
                        C_ChatInfo.SendAddonMessage("KART", "OIL:" .. outMH .. ":" .. outOH, IsInRaid() and "RAID" or "PARTY")
                    end
                elseif msg:sub(1, 4) == "OIL:" then
                    local mhID, ohID = msg:match("OIL:(%d+):(%d+)")
                    if mhID and ohID then
                        KART.OilCache = KART.OilCache or {}
                        KART.OilCache[shortName] = { mh = tonumber(mhID), oh = tonumber(ohID) }
                        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
                            KART.UpdateBuffCheckThrottled()
                        end
                    end
                elseif msg == "REQ_ILVL" then
                    local _, equipped = GetAverageItemLevel()
                    if equipped then
                        C_ChatInfo.SendAddonMessage("KART", "ILVL:" .. string.format("%.1f", equipped), IsInRaid() and "RAID" or "PARTY")
                    end
                elseif msg:sub(1, 5) == "ILVL:" then
                    local ilvl = tonumber(msg:sub(6))
                    if ilvl then
                        KART.ILvlCache = KART.ILvlCache or {}
                        KART.ILvlCache[shortName] = ilvl
                        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
                            KART.UpdateBuffCheckThrottled()
                        end
                    end
                elseif msg == "REQ_GEAR" then
                    local e, g = KART.CountMissingGear()
                    C_ChatInfo.SendAddonMessage("KART", "GEAR:" .. e .. ":" .. g, IsInRaid() and "RAID" or "PARTY")
                elseif msg:sub(1, 5) == "GEAR:" then
                    local e, g = msg:match("GEAR:([^:]+):([^:]+)")
                    if e and g then
                        KART.GearCache = KART.GearCache or {}
                        KART.GearCache[shortName] = { enchants = e, gems = g }
                        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
                            KART.UpdateBuffCheckThrottled()
                        end
                    end
                elseif msg == "REQ_VERSION" then
                    local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
                    if channel == "WHISPER" then
                        C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, "WHISPER", sender)
                    else
                        C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, channel)
                    end
                elseif msg:sub(1, 8) == "VERSION:" or msg:sub(1, 17) == "ANNOUNCE_VERSION:" then
                    local isAnnounce = (msg:sub(1, 17) == "ANNOUNCE_VERSION:")
                    local rest = isAnnounce and msg:sub(18) or msg:sub(9)
                    local ver, lcFlag = rest:match("^([^:]+):?([01]?)$")
                    ver = ver or rest

                    KART.PlayerVersions = KART.PlayerVersions or {}
                    KART.PlayerVersions[shortName] = ver
                    if lcFlag == "1" or lcFlag == "0" then
                        KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
                        KART.PlayerLCEnabled[shortName] = (lcFlag == "1")
                    end
                    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                        KART.LC.RefreshCouncilRows()
                    end

                    if not KART.UpdateWarned and ver ~= KART.Version then
                        local nMaj, nMin, nPat = ver:match("(%d+)%.(%d+)%.(%d+)")
                        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.(%d+)%.(%d+)")
                        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
                        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0

                        if nMaj > oMaj or (nMaj == oMaj and nMin > oMin) or (nMaj == oMaj and nMin == oMin and nPat > oPat) then
                            KART.UpdateWarned = true
                            print(string.format(KART.L.UPDATE_AVAILABLE or "|cff00ff00KART:|r Ein Update ist verfügbar! Version %s ist neu (Du hast %s).", ver, KART.Version))
                        end
                    end

                    if KART.VersionCheckActive and not isAnnounce then
                        print(string.format(KART.L.VERSION_CHECK_RES or "KART Version von %s: %s", shortName, ver))
                    end
                elseif msg:sub(1, 10) == "LC_ACTIVE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleActive(msg:sub(11)) end
                elseif msg:sub(1, 9) == "LC_START:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleStart(msg:sub(10)) end
                elseif msg:sub(1, 8) == "LC_VOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), shortName) end
                elseif msg:sub(1, 8) == "LC_ROLL:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleRoll(msg:sub(9), shortName) end
                elseif msg:sub(1, 9) == "LC_CVOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleCouncilVote(msg:sub(10), shortName) end
                elseif msg:sub(1, 9) == "LC_ONOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleOfficerNote(msg:sub(10), shortName) end
                elseif msg:sub(1, 10) == "LC_RESULT:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleResult(msg:sub(11), shortName) end
                elseif msg:sub(1, 10) == "LC_CONFIG:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleConfig(msg:sub(11), shortName) end
                elseif msg:sub(1, 12) == "LC_HIST_REQ:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleHistoryRequest(msg:sub(13), sender) end
                elseif msg:sub(1, 14) == "LC_HIST_ENTRY:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleHistoryEntry(msg:sub(15)) end
                elseif msg:sub(1, 10) == "RC_REASON:" then
                    local reason = msg:sub(11)
                    KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
                    KART.ReadyCheckReasons[shortName] = reason
                    
                    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
                        print(string.format("|cff00ff00KART:|r %s ist nicht bereit: |cffffaa00%s|r", shortName, reason))
                    end
                    
                    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
                        KART.UpdateBuffCheckThrottled()
                    end
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
    local br, bg, bb = KART_Settings.bgR/100, KART_Settings.bgG/100, KART_Settings.bgB/100
    local titleSize = KART_Settings.titleFontSize or 11
    local menuSize = KART_Settings.menuFontSize or 11
    local contentSize = KART_Settings.contentFontSize or 12
    
    KART.MainFrame:SetBackdropColor(br, bg, bb, KART_Settings.bgAlpha / 100)
    KART.SetGradientOverlayColor(KART.MainFrame.gradientBg, br, bg, bb, KART_Settings.bgAlpha / 100)
    if KART.MainFrame.title then
        KART.MainFrame.title:SetFont(fontPath, titleSize, "OUTLINE")
        KART.MainFrame.title:SetTextColor(r, g, b)
    end

    if KART.MainFrame.closeBtn then
        KART.MainFrame.closeBtn.text:SetFont(fontPath, 14, "OUTLINE")
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
    if KART.BgColorPreview then KART.BgColorPreview:SetColorTexture(br, bg, bb, 1) end

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
        w:SetBackdropColor(br, bg, bb, KART_Settings.bgAlpha / 100)
        if w.title then
            w.title:SetFont(fontPath, titleSize, "OUTLINE")
            w.title:SetTextColor(r, g, b)
        end
    end

    if KART.BuffCheckFrame then
        KART.BuffCheckFrame:SetBackdropColor(br, bg, bb, (KART_Settings.buffCheckAlpha or 95) / 100)
        KART.SetGradientOverlayColor(KART.BuffCheckFrame.gradientBg, br, bg, bb, (KART_Settings.buffCheckAlpha or 95) / 100)
        if KART.BuffCheckFrame.title then
            KART.BuffCheckFrame.title:SetFont(fontPath, titleSize, "OUTLINE")
            KART.BuffCheckFrame.title:SetTextColor(r, g, b)
        end
        if KART.BuffCheckFrame.closeBtn then
            KART.BuffCheckFrame.closeBtn.text:SetFont(fontPath, 14, "OUTLINE")
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

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -10)
        f.title:SetText(KART.L.RC_REASON_TITLE or "Nicht bereit? Grund:")

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

        local btnBio = KART.CreateModernButton(f, KART.L.RC_REASON_BIO or "Bio")
        btnBio:SetSize(75, 25)
        btnBio:SetPoint("TOPLEFT", 10, -35)
        btnBio:SetScript("OnClick", function() sendReason("RC_REASON_BIO", "Bio") end)

        local btnDrink = KART.CreateModernButton(f, KART.L.RC_REASON_DRINK or "Trinken")
        btnDrink:SetSize(75, 25)
        btnDrink:SetPoint("TOP", 0, -35)
        btnDrink:SetScript("OnClick", function() sendReason("RC_REASON_DRINK", "Trinken") end)

        local btn1Min = KART.CreateModernButton(f, KART.L.RC_REASON_1MIN or "1 Min")
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
        table.insert(KART.EditBoxes, customInput)
        
        local btnSend = KART.CreateModernButton(f, KART.L.RC_REASON_SEND or "Senden")
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
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "version" or cmd == "v" then
        local channel = "GUILD"
        if IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY" end
        print(KART.L.VERSION_CHECK_REQ or "KART: Fordere Versionen an...")
        KART.VersionCheckActive = true
        C_Timer.After(5, function() KART.VersionCheckActive = false end)
        C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", channel)
    else
        -- Sicherheitscheck: Falls das MainFrame (noch) nicht existiert, Fehler verhindern
        if KART.MainFrame then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        end
    end
end