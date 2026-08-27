local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")

KART.Version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"
KASC:RegisterAddon("KART", KART.Version)

local frame = CreateFrame("Frame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_OFFICER")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("READY_CHECK_CONFIRM")
frame:RegisterEvent("READY_CHECK_FINISHED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Not a combat event: this is Blizzard closing every UISpecialFrames entry when the player is
-- stunned, feared or knocked about, which takes this addon's windows with it. See
-- KART.RegisterEscapeFrame for the whole story.
frame:RegisterEvent("PLAYER_CONTROL_LOST")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("PLAYER_LOGOUT")
-- Border widths are in frame units, which stop being whole pixels when the UI scale or the
-- resolution changes under us (B23). Both events fire without the addon touching anything.
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")

-- DataBroker Object für Minimap und Compartment
local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("KeineAhnungRaidTools", {
    type = "launcher",
    text = "KART",
    icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.png",
    OnClick = function(_, button)
        if button == "LeftButton" then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        elseif button == "RightButton" then
            KART.MainFrame:Show() KART.ShowTab(4) -- MainFrame loads before Core (.toc), always exists here
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Keine Ahnung Raid Tools")
        tooltip:AddLine("|cffeda55f" .. KART.L.TOOLTIP_LEFTCLICK .. "|r " .. KART.L.TAB_PROMOTE)
        tooltip:AddLine("|cffeda55f" .. KART.L.TOOLTIP_RIGHTCLICK .. "|r " .. KART.L.TAB_SETTINGS)
    end,
})

-- Re-applies every current KART_Settings value to its UI widget and refreshes every
-- settings-dependent module cache. Called once from ADDON_LOADED, and again after a profile
-- switch (KART.LoadProfile, Profiles.lua) — must stay free of one-time initialization
-- (AddonCompartment registration, event handler setup) since those must never run twice.
function KART.SyncSettingsToUI()
    KART.UpdateCache()

    -- Each file that builds a settings widget paints it. Invite chips wait until UpdateStyles
    -- below: they read AccentColor, which is still the library default until then.
    if KART.SyncMainFrameWidgets then KART.SyncMainFrameWidgets() end
    if KART.RC and KART.RC.SyncWidgets then KART.RC.SyncWidgets() end
    if KART.WU and KART.WU.SyncWidgets then KART.WU.SyncWidgets() end
    if KART.CT and KART.CT.SyncWidgets then KART.CT.SyncWidgets() end
    -- Refresh styles AFTER the widgets have their values, so toggle-switch visuals (which only
    -- update via UpdateStyles/RefreshVisual) reflect the just-loaded state — matters after a profile
    -- switch, which has no separate UpdateStyles of its own the way ADDON_LOADED does.
    KART.UpdateStyles()
    -- Rebuild the boss buttons from the saved WoWUtils import so they're ready immediately on login.
    -- SyncSettingsToUI also runs on every profile switch, so this has to REPLACE the list rather
    -- than add to it — see WU.SyncBossesToSavedText.
    if KART.WU and KART.WU.SyncBossesToSavedText then KART.WU.SyncBossesToSavedText() end

    if KART.RefreshProfileButton then KART.RefreshProfileButton() end
    if KART.RefreshModuleChips then KART.RefreshModuleChips() end

    KART.UpdateMinimapButton()
    -- Applies the keybinds too (its tail call), since whether they may be bound at all depends on
    -- the bar's resulting visibility — see KART.ApplyKeybinds.
    KART.UpdateRaidleadBarVisibility()
    -- SetChecked/SetValue above don't fire the widgets' own callbacks, and the auto-log filters live
    -- entirely in theirs. Without this a profile switch changes the settings but never acts on them:
    -- switching away from the raid profile mid-instance would leave KART's combat log running, and
    -- switching to it after the pull would never start one.
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        KART_Settings = KART_Settings or {}
        KART_Profiles = KART_Profiles or {}
        KART_PlayerCache = KART_PlayerCache or {}
        KART_RCOwed = KART_RCOwed or {}
        KASC:AttachCache(KART_PlayerCache)
        KASC:Init("KART")
        -- Prune identity-cache entries not seen for 90+ days so the SavedVariable doesn't
        -- grow forever (it gains one entry per distinct group member ever encountered).
        local pruneCutoff = time() - 90 * 24 * 60 * 60
        for guid, entry in pairs(KART_PlayerCache) do
            if (entry.lastSeen or 0) < pruneCutoff then KART_PlayerCache[guid] = nil end
        end
        -- Reconcile the "KART owns the combat log" flag with reality.
        -- as well as on login, and LoggingCombat() SURVIVES a reload while it never survives a
        -- logout — so only clear the flag when nothing is actually logging. Clearing it
        -- unconditionally would orphan a log KART started before a mid-raid /reload, leaving it
        -- running forever because AutoLog.Evaluate's stop branch requires ownership.
        if not LoggingCombat() then KART_Settings.autoLogOwned = false end

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

        -- Fill in any missing defaults (top-level and nested). MergeDefaults deep-copies table
        -- defaults (keybinds, minimap) rather than assigning them by reference — a reference would
        -- let the live settings mutate KART.Defaults itself, which then made "Reset Defaults" a
        -- no-op for those keys within the same session — and merges sub-keys added by a later
        -- addon version into a settings blob saved before they existed.
        local hadInviteChannels = KART_Settings.inviteChannels ~= nil
        KAUtil.MergeDefaults(KART_Settings, KART.Defaults)
        if KART.CT and KART.CT.MigrateProfile then
            KART.CT.MigrateProfile(KART_Settings.ct)
        end
        if not hadInviteChannels then
            KART_Settings.inviteChannels.GUILD = KART_Settings.inviteViaGuildChat or false
        end

        if KART.RC then KART.RC.Enable() end
        if KART.RegisterNeighborAddons then KART.RegisterNeighborAddons() end

        -- Minimap Icon mit LibDBIcon registrieren (KART_Settings.minimap is guaranteed a table by
        -- the Defaults merge above — Defaults.minimap = {}).
        local dbIcon = LibStub("LibDBIcon-1.0", true)
        if dbIcon then
            dbIcon:Register("KeineAhnungRaidTools", ldb, KART_Settings.minimap)
            -- Register decides visibility from the saved table's own `hide` flag, which settings
            -- blobs written before that flag was maintained do not carry. Without this, a player
            -- who had turned the icon off got it back on every login (B4).
            KART.UpdateMinimapButton()
        end

        -- Re-apply every statically-built UI text with the now-selected language.
        KART.UI:ApplyLocaleRefreshers()

        KART.SyncSettingsToUI()
        if KART.CT then KART.CT.Enable() end

        AddonCompartmentFrame:RegisterAddon({
            text = "Keine Ahnung Raid Tools",
            icon = "Interface\\AddOns\\KeineAhnungRaidTools\\KAimg.png", -- addon icon path
            registerForAnyClick = true,
            func = function() 
                if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
            end,
        })
        
        -- Set the real version (KART.Version only becomes available here)
        if KART.MainFrame and KART.RefreshVersionText then
            KART.RefreshVersionText()
        elseif KART.MainFrame and KART.MainFrame.versionText then
            KART.MainFrame.versionText:SetText("v" .. KART.Version)
        end

        -- Styles nach der Erstellung aller Frames final anwenden
        KART.UpdateStyles()

    elseif event == "ADDON_LOADED" then
        if arg1 == "RCLootCouncil" and KART.RC then KART.RC.Enable() end
        if (arg1 == "RCLootCouncil" or arg1 == "NorthernSkyRaidTools" or arg1 == "wowutils")
            and KART.RegisterNeighborAddons then
            KART.RegisterNeighborAddons()
            KASC:AnnounceHelloIfChanged()
        end

    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER"
        or event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        local channels = KART_Settings.inviteChannels or {}
        local enabled = (event == "CHAT_MSG_WHISPER" and channels.WHISPER)
            or (event == "CHAT_MSG_BN_WHISPER" and channels.BN)
            or (event == "CHAT_MSG_GUILD" and channels.GUILD)
            or (event == "CHAT_MSG_OFFICER" and channels.OFFICER)
        if enabled then
            KART.HandleChatInvite(arg1, arg2, event, ...)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Before anything reads a unit token: the tokens have just been renumbered, so what this
        -- client last knew about raid7 is about somebody else now (see KART.UnitLeads).
        KART.ForgetUnitStanding()
        KART.UpdateRaidleadBarVisibility()

        -- Announce whenever the CHANNEL changes, not once per group. The old one-shot latch meant a
        -- party that converts to a raid never re-announced, and anyone who missed that single PARTY
        -- packet was never told again — leaving a permanent "no KART detected" marker on a raider
        -- who plainly had it (B19). Tracking the channel also covers rejoining a group of the same
        -- kind, since leaving clears it below.
        --
        -- AnnounceHelloIfChanged on top: it also fires when our capabilities change (enabling the
        -- Loot Council module, say) rather than only when the channel does.
        if IsInGroup() then
            local channel = KASC:DefaultChannel()
            if KART.announcedChannel ~= channel then
                KART.announcedChannel = channel
                KASC:AnnounceHello()
                -- Our own announce only tells the group about US — it does nothing for players who
                -- already announced before we joined, so pull everyone else's current version too,
                -- the same way /kart v does.
                KASC:RequestHello()
            else
                KASC:AnnounceHelloIfChanged()
            end
            -- ...and ask again for whatever never arrived. The announce above happens once per
            -- channel change, in the middle of raid formation, and an answer lost to Blizzard's rate
            -- limiter there stayed lost for the evening (B120). Self-limiting: it asks only about
            -- peers with no version recorded, so it goes quiet as soon as the table is complete.
            KART.RequestMissingHellosThrottled()
        else
            KART.announcedChannel = nil
        end

        -- Before the refresh below, so a departed player's data is gone rather than redrawn.
        KART.PruneDepartedPeers()
        -- Performance: Update BuffCheck nur wenn Fenster offen
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        if KART.RefreshStatusStripThrottled then KART.RefreshStatusStripThrottled() end

        -- The autoConvertToRaid setting itself does NOT trigger here: converting the instant a
        -- party reaches 5 members catches groups that never wanted a 6th. The setting instead
        -- converts when a 6th player requests an invite (GroupLogic.lua), or via a bulk WoWUtils
        -- invite (Invite.lua). The roster event below only serves the latter's deferred one-shot
        -- flag, converting once the invitees actually fill the party.
        if KART.pendingBulkRaidConvert and not InCombatLockdown() and UnitIsGroupLeader("player") and GetNumGroupMembers() >= 5 and not IsInRaid() then
            C_PartyInfo.ConvertToRaid()
        end
        -- One-shot flag set by a bulk WoWUtils invite (Invite.lua) that started while solo/small:
        -- convert once the invitees fill the party, then clear it (also on leaving the group).
        if IsInRaid() or not IsInGroup() then KART.pendingBulkRaidConvert = false end
        KART.HandleAutoPromoteThrottled()
        if KART.RC then KART.RC.OnRosterUpdate() end
        if KART.CT then KART.CT.Refresh() end
        
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        if KART.CT then KART.CT.Refresh() end
        
    elseif event == "READY_CHECK" then
        KART.ReadyCheckReasons = wipe(KART.ReadyCheckReasons or {})
        if KART.RCDialog then KART.RCDialog:Hide() end
        -- Arms the reason dialog for this check -- see READY_CHECK_CONFIRM below, which fires more
        -- than once for the same answer and would otherwise act on all of them.
        KART.rcSelfAnswered = false

        -- KART's own copy of the ready-check result, because Blizzard's GetReadyCheckStatus is
        -- cleared once the check resolves and the Buff Checker's Rdy column then goes blank -- which
        -- is precisely when it is wanted, to chase up whoever was not ready. Seeded as "waiting" for
        -- everyone so a player who never answers still reads as such afterwards, rather than as no
        -- entry at all. arg1 is the initiator, who counts as ready without ever confirming.
        KART.ReadyCheckStatus = wipe(KART.ReadyCheckStatus or {})
        for unit in KAUtil.EachGroupUnit() do
            local n = UnitName(unit)
            if n then KART.ReadyCheckStatus[n] = "waiting" end
        end
        if arg1 then KART.ReadyCheckStatus[arg1:match("([^%-]+)") or arg1] = "ready" end
        -- Also gate on the module toggle: ShowBuffCheck itself refuses and prints
        -- BC_MODULE_DISABLED_MSG when the module is off, which would spam chat on every single ready
        -- check for anyone who enabled "show on ready check" without enabling the module.
        if KART_Settings.showBuffCheck and KART_Settings.bcModuleEnabled ~= false and KART.ShowBuffCheck then
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
        -- Our own answer is what opens the extended ready check's reason dialog. This replaced a
        -- hooksecurefunc on the global ConfirmReadyCheck: that global still exists, and the hook
        -- still attaches to it, but Blizzard's ready-check frame no longer calls it, so the dialog
        -- never appeared for anyone (verified in-game 2026-07-27 -- declining printed no hook call).
        --
        -- arg1 is a UNIT TOKEN, not a name, and arrives as both "player" and the group token
        -- ("raid1"/"party1") for one single answer, so both fire here. rcSelfAnswered collapses that
        -- to one dialog per check; READY_CHECK above re-arms it.
        --
        -- READY_CHECK_FINISHED carries different arguments entirely, hence the event check.
        -- 0 is not treated as ready either -- the replaced hook accepted that shape and nothing
        -- documents which one this event uses.
        local isReady = arg2 and arg2 ~= 0
        if event == "READY_CHECK_CONFIRM" and arg1 then
            -- Every confirmation, not just our own: this is the snapshot the Rdy column falls back
            -- on once Blizzard clears its own status. Recording the same answer twice under two
            -- tokens is harmless -- both resolve to the same name and the same value.
            local n = UnitName(arg1)
            if n and KART.ReadyCheckStatus then
                KART.ReadyCheckStatus[n] = isReady and "ready" or "notready"
            end
        end
        if event == "READY_CHECK_CONFIRM" and not KART.rcSelfAnswered
           and arg1 and UnitIsUnit(arg1, "player") then
            KART.rcSelfAnswered = true
            if isReady then
                if KART.RCDialog then KART.RCDialog:Hide() end
            -- Raids only, not any group. A Mythic+ party ready-checks before nearly every pull, so
            -- in a five-man this asked for a written reason over and over for something the group
            -- would just say out loud (GitHub issue #10). The reason travels to the raid to spare
            -- twenty people a chat exchange; four people do not need it.
            elseif IsInRaid() and KART_Settings.rcReasonDialog ~= false then
                KART.ShowReadyCheckReasonDialog()
            end
        end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            KART.UpdateBuffCheckThrottled()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if KART.SetEditModeActive then KART.SetEditModeActive(false) end
        if KART.RCDialog then KART.RCDialog:Hide() end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
            local delay = KART_Settings.bcCombatDelay or 2
            KART.bcHideGen = (KART.bcHideGen or 0) + 1
            local myGen = KART.bcHideGen
            C_Timer.After(delay > 0 and delay or 0.01, function()
                -- Only hide if we're still in the same combat — a cancelled generation (combat
                -- ended, see PLAYER_REGEN_ENABLED) or a no-longer-in-combat state means the delayed
                -- hide is stale and would wrongly close a window the player is now free to read.
                if KART.bcHideGen == myGen and InCombatLockdown() and KART.BuffCheckFrame then
                    KART.BuffCheckFrame:Hide()
                end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        KART.bcHideGen = (KART.bcHideGen or 0) + 1 -- cancel any pending combat-hide from above
        -- Restore edit-mode strata skipped during combat (PaintEditOutline), then the bar
        -- reapplies yield-to-map. Also re-applies keybinds via its tail call, which covers
        -- the case where a login/reload during combat had to defer them (KART.keybindsPending,
        -- see KART.ApplyKeybinds).
        if KART.RefreshEditModeChrome then KART.RefreshEditModeChrome() end
        KART.UpdateRaidleadBarVisibility()
        if KART.HandleAutoPromote then KART.HandleAutoPromote() end
        if KART.RC and KART.RC.OnOwedOutOfCombat then KART.RC.OnOwedOutOfCombat() end
        if KART.CT then KART.CT.OnRegenEnabled() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin, arg2 = isReloadingUi. Only announce our version to the guild on an
        -- actual login/reload — this event also fires on every loading screen (zone/instance change),
        -- and re-announcing then just spams the guild addon channel.
        if arg1 or arg2 then
            C_Timer.After(5, function()
                if IsInGuild() then
                    KASC:AnnounceHello("GUILD")
                end
            end)
        end
        if KART.AutoLog then KART.AutoLog.Evaluate() end
        if KART.RegisterLibDurability then KART.RegisterLibDurability() end
        if KART.RC then KART.RC.HookVotingFrame() end
        if KART.CT then KART.CT.Refresh() end
    elseif event == "PLAYER_CONTROL_LOST" then
        KART.OnControlLost()
    elseif event == "CHALLENGE_MODE_START" then
        if KART.AutoLog then KART.AutoLog.Evaluate() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        KART.UI:RefreshPixelBorders()
    end
end)

-- =====================================================================
--  Addon-message handlers -- ready-check reasons
-- =====================================================================
-- Peer version bookkeeping (HELLO compare, UPDATE_AVAILABLE, neighbor versions) lives in
-- Utils.lua so RaidSim clients, which never load this file, still see it.

-- RC_REASON: Core.lua owns the cache's lifecycle (READY_CHECK above wipes KART.ReadyCheckReasons)
-- and the sending dialog (KART.ShowReadyCheckReasonDialog below), so the receiver lives here too.
KASC:RegisterMessage("RC_REASON", { payload = true, group = true }, function(payload, ctx)
    -- Free text from another client goes straight into a chat print and a tooltip, so strip the
    -- UI escape sequences WoW would otherwise render: |c/|r recoloring and |H...|h hyperlinks
    -- would let a raider inject fake colored text and clickable links into every officer's chat.
    if payload == "" then return end -- "" is truthy in Lua: an empty reason would still show the
                                     -- icon, with an empty tooltip behind it
    payload = payload:gsub("|", "||")
    KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
    KART.ReadyCheckReasons[ctx.shortName] = payload
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        print(string.format(KART.L.RC_REASON_RECEIVED, ctx.shortName, payload))
    end
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
end)

-- Styles Update (Muss global zugänglich sein)
function KART.UpdateStyles()
    if not KART_Settings or not KART.MainFrame then return end -- KART.MainFrame aus MainFrame.lua

    local fontPath = KART.UI:GetFontPath(KART_Settings.fontName)
    local r, g, b = KART_Settings.accentR/100, KART_Settings.accentG/100, KART_Settings.accentB/100
    local titleSize = KART_Settings.titleFontSize or 12 -- matches Defaults.titleFontSize
    local contentSize = KART_Settings.contentFontSize or 12 -- still needed below for the BuffChecker rows, which aren't part of KART.UI's generic registries

    KART.UI:ApplyStyle({
        font        = fontPath,
        menuSize    = KART_Settings.menuFontSize,
        contentSize = KART_Settings.contentFontSize,
        strata      = KART_Settings.frameStrata,
        accent      = { r, g, b },
        background  = { KART_Settings.bgR/100, KART_Settings.bgG/100, KART_Settings.bgB/100 },
    })

    -- The main window is a baked PNG artwork: no backdrop/gradient to tint.
    -- bgAlpha now controls whole-window opacity; floor of 20 so the window
    -- can never become fully invisible while still blocking mouse input.
    KART.MainFrame:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100)
    -- Deferred while the scale slider is being dragged: rescaling the window mid-drag moves the
    -- slider under the cursor, which feeds back into new values and makes the thumb jump. The
    -- slider's OnMouseUp hook (MainFrame.lua) re-runs UpdateStyles to apply the final value.
    if not (KART.SldUiScale and KART.SldUiScale.isDragging) then
        local scale = (KART_Settings.uiScale or 100) / 100
        KART.MainFrame:SetScale(scale)
        -- The flyout is parented to UIParent, not the main window, so it does not inherit that
        -- scale. Without this it stays native-size next to a scaled window.
        if KART.CtFlyout then KART.CtFlyout:SetScale(scale) end
    end

    if KART.ColorPreview then KART.ColorPreview:SetColorTexture(r, g, b, 1) end

    -- Minimap Icon Farbe anpassen
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then
        local iconButton = dbIcon:GetMinimapButton("KeineAhnungRaidTools")
        if iconButton and iconButton.icon then
            iconButton.icon:SetVertexColor(r, g, b)
        end
    end

    if KART.BuffCheckFrame then
        -- Artwork background: only the ground texture fades with buffCheckAlpha so rows,
        -- buttons and text stay fully readable at low opacities.
        if KART.BuffCheckFrame.bg then
            KART.BuffCheckFrame.bg:SetAlpha((KART_Settings.buffCheckAlpha or 90) / 100)
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

    if KART.UpdateScrollRange then KART.UpdateScrollRange() end

    -- Buff-Check names are truncated to fit their column by MEASURING them in the current font
    -- (see SetTruncatedName), so a font or size change invalidates every rendered name. Nothing
    -- else re-runs that until the next roster/aura event, so an open window would show overflowing
    -- names running into the next column until then.
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() and KART.UpdateBuffCheckThrottled then
        KART.UpdateBuffCheckThrottled()
    end

    -- Take-it width is measured in the live font; ApplyStyle restyles the label but does not
    -- re-fit the button.
    if KART.CT and KART.CT.RefreshAskButton then KART.CT.RefreshAskButton() end
    if KART.RefreshModuleChips then KART.RefreshModuleChips() end
    if KART.InviteChannelChips then
        for _, chip in ipairs(KART.InviteChannelChips) do chip:Refresh() end
    end
    if KART.TauntFilterChips then
        for _, chip in ipairs(KART.TauntFilterChips) do chip:Refresh() end
        if KART.LayoutTauntFilterChips then KART.LayoutTauntFilterChips() end
    end
    if KART.TauntChannelChips then
        for _, chip in ipairs(KART.TauntChannelChips) do chip:Refresh() end
        if KART.LayoutTauntChannelChips then KART.LayoutTauntChannelChips() end
    end
    if KART.CtPreviewStateChips then
        for _, chip in ipairs(KART.CtPreviewStateChips) do chip:Refresh() end
        if KART.LayoutCtPreviewStateChips then KART.LayoutCtPreviewStateChips() end
    end
    if KART.SwapSoundChips then
        for _, chip in ipairs(KART.SwapSoundChips) do chip:Refresh() end
        if KART.LayoutSwapSoundChips then KART.LayoutSwapSoundChips() end
    end
    if KART.RefreshVersionText then KART.RefreshVersionText() end

    -- Border widths are derived from each frame's effective scale (B23), and both size sliders
    -- have been applied by now -- the addon-wide one above, the Loot Council one in
    -- ApplyWindowChrome. Last in this function so nothing after it changes a scale again.
    KART.UI:RefreshPixelBorders()
end

-- UI für den erweiterten Ready-Check Grund
function KART.ShowReadyCheckReasonDialog()
    if not KART.RCDialog then
        local f = CreateFrame("Frame", "KART_RCReasonFrame", UIParent, "BackdropTemplate")
        f:SetSize(260, 115)
        f:SetPoint("CENTER", 0, 150)
        KART.UI:RegisterStrataFrame(f, true)
        KART.UI:SetPixelBackdrop(f, {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        KART.UI:ApplyRoundedMask(f, KAUI.CORNER_RADIUS_LG)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -10)
        f.title:SetText(KART.L.RC_REASON_TITLE)

        -- reasonKey names a localized preset (Bio/Drink/1min); a nil reasonKey with a fallback is
        -- the custom free-typed reason path (see the Send button / edit box below). The preset
        -- callers pass no fallback — their key always exists in KART.L, so the old literal fallbacks
        -- there were dead.
        local function sendReason(reasonKey, fallback)
            local text = fallback
            if reasonKey and KART.L[reasonKey] then
                text = KART.L[reasonKey]
            end
            if IsInGroup() then
                KASC:Send("RC_REASON:" .. text)
                -- Our own row, same as every receiver does for us. KASC drops our own message when
                -- it comes back (see Dispatch), so without this the one person whose reason it is
                -- is the one person whose buff-check row does not show it. Pipes escaped exactly
                -- like the receiver escapes them, so our row reads the same as everybody else's.
                KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
                KART.ReadyCheckReasons[UnitName("player")] = (text:gsub("|", "||"))
            end
            f:Hide()
        end

        local btnBio = KART.UI:CreateModernButton(f, KART.L.RC_REASON_BIO)
        btnBio:SetSize(75, 25)
        btnBio:SetPoint("TOPLEFT", 10, -35)
        btnBio:SetScript("OnClick", function() sendReason("RC_REASON_BIO") end)

        local btnDrink = KART.UI:CreateModernButton(f, KART.L.RC_REASON_DRINK)
        btnDrink:SetSize(75, 25)
        btnDrink:SetPoint("TOP", 0, -35)
        btnDrink:SetScript("OnClick", function() sendReason("RC_REASON_DRINK") end)

        local btn1Min = KART.UI:CreateModernButton(f, KART.L.RC_REASON_1MIN)
        btn1Min:SetSize(75, 25)
        btn1Min:SetPoint("TOPRIGHT", -10, -35)
        btn1Min:SetScript("OnClick", function() sendReason("RC_REASON_1MIN") end)

        -- Textfeld für eigenen Grund
        local customInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        customInput:SetSize(155, 25)
        customInput:SetPoint("BOTTOMLEFT", 10, 15)
        customInput:SetAutoFocus(false)
        customInput:SetFontObject("GameFontHighlightSmall")
        KART.UI:SetPixelBackdrop(customInput, {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        customInput:SetBackdropColor(0, 0, 0, 0.8)
        customInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        customInput:SetTextInsets(5, 5, 0, 0)
        customInput:SetMaxLetters(30) -- Verhindert, dass Leute ganze Romane schreiben
        KART.UI:ApplyRoundedMask(customInput, KAUI.CORNER_RADIUS_SM)
        KART.UI:RegisterEditBox(customInput)

        local btnSend = KART.UI:CreateModernButton(f, KART.L.RC_REASON_SEND)
        btnSend:SetSize(70, 25)
        btnSend:SetPoint("LEFT", customInput, "RIGHT", 10, 0)
        btnSend:SetScript("OnClick", function()
            local text = KAUtil.TrimString(customInput:GetText())
            if text ~= "" then sendReason(nil, text) end
        end)
        
        customInput:SetScript("OnEnterPressed", function(self)
            local text = KAUtil.TrimString(self:GetText())
            if text ~= "" then sendReason(nil, text) else self:ClearFocus() end
        end)
        customInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        f.customInput = customInput
        KART.RCDialog = f
        KART.UI:RegisterLabel(f.title)
        KART.UpdateStyles()
    end
    if KART.RCDialog.customInput then KART.RCDialog.customInput:SetText("") end
    KART.RCDialog:Show()
    -- Generation token so a second ready check within 15s doesn't get its dialog closed early by the
    -- first check's still-pending auto-hide timer.
    KART.rcDialogGen = (KART.rcDialogGen or 0) + 1
    local myGen = KART.rcDialogGen
    C_Timer.After(15, function()
        if KART.rcDialogGen == myGen and KART.RCDialog and KART.RCDialog:IsShown() then
            KART.RCDialog:Hide()
        end
    end)
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
        KASC:RequestHello(channel)
    elseif cmd == "ench" or cmd == "ench raid" then
        -- Maintenance tool, not a player feature: prints the enchant ids the client actually reports
        -- so GOOD_ENCHANTS (Utils.lua) and the oil's bestSpells (BuffChecker.lua) can be refilled
        -- from real data each tier instead of from memory. "raid" polls the whole group, since most
        -- slots accept several enchants and one character's dump can't show which.
        if cmd == "ench raid" then KART.StartEnchantScan() else KART.PrintEnchantDump() end
    elseif cmd == "ptr" then
        -- Maintenance tool, like /kart ench above and deliberately absent from /kart help: it prints
        -- what the CLIENT does, for whoever is porting the addon to a new game version.
        KART.PrintClientProbe()
    elseif cmd == "owed" then
        if KART.RC and KART.RC.OpenOwedWindow then KART.RC.OpenOwedWindow() end
    elseif cmd == "help" or cmd == "h" then
        print(KART.L.HELP_HEADER)
        print("  /kart - " .. KART.L.HELP_TOGGLE)
        print("  /kart version (v) - " .. KART.L.HELP_VERSION)
        print("  /kart ench [raid] - " .. KART.L.HELP_ENCH)
        print("  /kart owed - " .. KART.L.HELP_OWED)
        print("  /kart help (h) - " .. KART.L.HELP_HELP)
    else
        -- Sicherheitscheck: Falls das MainFrame (noch) nicht existiert, Fehler verhindern
        if KART.MainFrame then
            if KART.MainFrame:IsShown() then KART.MainFrame:Hide() else KART.MainFrame:Show() KART.ShowTab(1) end
        end
    end
end