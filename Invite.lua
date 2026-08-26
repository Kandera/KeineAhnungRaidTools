local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")

-- This file's checkbox is built at file load time, before Core.lua's ADDON_LOADED handler has
-- created KART_Settings -- passing the table directly here would freeze it onto nil forever.
-- Passed as `store` instead of the table itself, so KAUI resolves the current global at click
-- time rather than capturing it now (see ResolveStore in KAUI-1.0.lua).
local function SettingsStore() return KART_Settings end

KART.WU = KART.WU or {}
local WU = KART.WU

WU.bosses = {}  -- { encounterID, difficulty, name, players[] }

-- =====================================================================
--  Parser
-- =====================================================================

-- Parses a WoWUtils export and adds the result to WU.bosses. Imports are never
-- wiped or overwritten by a later import: pasting Normal and then Heroic
-- keeps both difficulties, and pasting a second roster for the same boss +
-- difficulty (e.g. Split-Team B) keeps both rosters side by side instead of
-- replacing the first one. When more than one entry shares the same boss +
-- difficulty, they're labeled "Boss Name A", "Boss Name B", ... in import
-- order so they stay distinguishable. Use WU.ResetBosses() to clear everything.
function WU.ParseImport(rawText)
    if not rawText or KAUtil.TrimString(rawText) == "" then return 0 end

    local parsedCount = 0
    -- Capture: [^;]+ is correct for the real WoWUtils export — each invitelist is terminated by a
    -- trailing ";" ("...Name-Realm;"), so the match stops there and never bleeds into the next boss
    -- block; %s+ absorbs the blank line before "invitelist:". Verified against a real multi-boss
    -- export (review 2026-07-24). Split: the live list is comma-separated with no spaces
    -- ("Name-Realm,Name-Realm,..."), so splitting on %S+ made the whole line one player and every
    -- boss showed "(1)". Commas first, so a realm with a space stays one name; whitespace only
    -- when there is no comma, for older space-separated pastes.
    for encounterID, difficulty, bossName, playerStr in rawText:gmatch(
            "EncounterID:(%d+);Difficulty:([^;]+);Name:([^\n\r]+)%s+invitelist:([^;]+)") do

        bossName   = KAUtil.TrimString(bossName)
        difficulty = KAUtil.TrimString(difficulty)
        playerStr  = KAUtil.TrimString(playerStr)
        encounterID = tonumber(encounterID)

        local players = {}
        if playerStr:find(",", 1, true) then
            for p in playerStr:gmatch("[^,]+") do
                p = KAUtil.TrimString(p)
                if p ~= "" then table.insert(players, p) end
            end
        else
            for p in playerStr:gmatch("%S+") do
                table.insert(players, p)
            end
        end

        if #players > 0 then
            parsedCount = parsedCount + 1

            local groupCount = 0
            for _, boss in ipairs(WU.bosses) do
                if boss.encounterID == encounterID and boss.difficulty == difficulty then
                    groupCount = groupCount + 1
                end
            end

            if groupCount == 1 then
                -- A second entry for this boss+difficulty just showed up;
                -- retroactively label the first one "A" too.
                for _, boss in ipairs(WU.bosses) do
                    if boss.encounterID == encounterID and boss.difficulty == difficulty then
                        boss.name = boss.baseName .. " A"
                        break
                    end
                end
            end

            local name = bossName
            if groupCount > 0 then
                name = bossName .. " " .. string.char(65 + groupCount) -- B, C, D, ...
            end

            table.insert(WU.bosses, {
                encounterID = encounterID,
                difficulty  = difficulty,
                name        = name,
                baseName    = bossName,
                players     = players,
            })
        end
    end

    -- Remember the exact text we parsed, so the Import button can refuse to re-parse identical text
    -- (which would duplicate every boss as "Name A"/"Name B") — e.g. after the saved text was
    -- already auto-parsed at login. Genuinely additive imports paste *different* text each time.
    if parsedCount > 0 then WU.lastImportedText = rawText end
    return parsedCount
end

-- Commits a successful paste into KART_Settings.wuImportText. The edit box is a staging
-- area and must not overwrite this on every keystroke: a second paste would otherwise
-- erase the first export from SavedVariables, and a /reload would rebuild only the last
-- one. Sequential imports (Normal then Heroic, or a split roster) append here so login
-- and profile switch can reconstruct the stacked list.
local function CommitImportedText(text)
    local prev = WU.committedImportText
    if not prev or prev == "" then
        WU.committedImportText = text
    elseif prev ~= text then
        WU.committedImportText = prev .. "\n" .. text
    end
    if KART_Settings then KART_Settings.wuImportText = WU.committedImportText end
end

-- Import-button body, without the panel. ParseImport is additive; this function must not
-- wipe WU.bosses. Returns count, status where status is "ok", "same", "empty", or "error".
function WU.ImportPastedText(text)
    if not text or KAUtil.TrimString(text) == "" then return 0, "empty" end
    if text == WU.lastImportedText then
        return #WU.bosses, "same"
    end
    local count = WU.ParseImport(text)
    if count > 0 then
        CommitImportedText(text)
        if WU.RefreshBossList then WU.RefreshBossList() end
        if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
        return count, "ok"
    end
    return 0, "error"
end

-- Makes the in-memory boss list match KART_Settings.wuImportText exactly. Called from
-- KART.SyncSettingsToUI, which runs both at login and on every profile switch — so it must REPLACE
-- the list, not extend it: WU.ParseImport is deliberately additive (several exports can be stacked
-- by hand), which would otherwise leave the previous profile's bosses in place and relabel the
-- collisions "Boss A"/"Boss B". A profile whose import text is empty correctly ends up with no
-- bosses instead of inheriting the previous profile's.
--
-- Deliberately NOT gated on wuModuleEnabled: the module toggle disables the invite/remove ACTIONS
-- (each of those checks it directly) and has no callback of its own, so gating here would empty the
-- list on disable and never rebuild it on re-enable — the list would only come back via a manual
-- Import or a reload.
function WU.SyncBossesToSavedText()
    if not WU.ImportEditBox then return end
    local text = KART_Settings.wuImportText or ""
    WU.committedImportText = text
    if text == WU.lastImportedText then return end -- already exactly this list

    WU.bosses = {}
    WU.lastImportedText = nil
    local count = text ~= "" and WU.ParseImport(text) or 0
    if not WU.RefreshBossList then return end
    WU.RefreshBossList()
    if WU.statusLabel then
        if count > 0 then
            WU.statusLabel:SetText(string.format(KART.L.WU_STATUS_LOADED, count))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
        else
            WU.statusLabel:SetText(KART.L.WU_STATUS_EMPTY)
            WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

function WU.ResetBosses()
    WU.bosses = {}
    WU.lastImportedText = nil -- cleared list: allow re-importing the same text again
    WU.committedImportText = nil
    -- Also drop the saved import text, otherwise the login/profile-switch auto-parse in
    -- KART.SyncSettingsToUI re-creates the whole list from it and the reset silently undoes itself
    -- on the next /reload (lastImportedText is a runtime field and never survives a session).
    KART_Settings.wuImportText = ""
    WU.activeBossIdx = nil
    if WU.ImportEditBox then WU.ImportEditBox:SetText("") end
    WU.RefreshBossList()
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
end

-- =====================================================================
--  Actions
-- =====================================================================

-- Names currently in the group, keyed both as Name and Name-Realm, CaseFolded. Shared by invite
-- skip-logic and the tonight strip's 12/20 count so those two cannot disagree about who is here.
local function GroupNameSet()
    local alreadyIn = {}
    do
        -- Seed with ourselves unconditionally: EachGroupUnit yields nothing while solo, so a bulk
        -- invite started alone would otherwise try to invite the player themselves.
        local myName, myRealm = UnitName("player")
        if myName then
            alreadyIn[KAUtil.CaseFold(myName)] = true
            if myRealm and myRealm ~= "" then alreadyIn[KAUtil.CaseFold(myName.."-"..myRealm)] = true end
            local normalized = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
            if normalized and normalized ~= "" then
                alreadyIn[KAUtil.CaseFold(myName.."-"..normalized)] = true
            end
        end
    end
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local full = (realm and realm ~= "") and (name.."-"..realm) or name
            alreadyIn[KAUtil.CaseFold(full)] = true
            alreadyIn[KAUtil.CaseFold(name)] = true
        end
    end
    return alreadyIn
end

function WU.ActiveBossIndex()
    if WU.activeBossIdx and WU.bosses[WU.activeBossIdx] then return WU.activeBossIdx end
    if WU.bosses[1] then return 1 end
    return nil
end

-- How many of this boss's pasted names are already in the group. Denominator is the list
-- length, not GetNumGroupMembers: extras in the raid who are not on the list do not inflate 12/20.
function WU.GroupPresenceForBoss(idx)
    local boss = WU.bosses[idx]
    if not boss then return 0, 0 end
    local alreadyIn = GroupNameSet()
    local present = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)] then
            present = present + 1
        end
    end
    return present, #boss.players
end

function WU.InviteBoss(idx)
    if KART_Settings.wuModuleEnabled == false then
        print("|cff00ff00KART:|r " .. KART.L.WU_MODULE_DISABLED_MSG)
        return
    end
    local boss = WU.bosses[idx]
    if not boss then return end
    WU.activeBossIdx = idx
    -- "Not in a group at all" is not a lack of permission, it is the ordinary starting point: open
    -- the tab before the evening, click the first boss, and the invites go out. HasGroupPermissions
    -- answers false while ungrouped -- correctly, there is no group to lead -- so gating on it alone
    -- refused this feature at its main use, with a "you are not the leader" that made no sense to
    -- somebody standing alone. Same shape KART.HandleChatInvite has always used for the same reason.
    --
    -- The deferred raid conversion further down (KART.pendingBulkRaidConvert) exists only for the
    -- solo case and could never be reached, which is what gave this away.
    if IsInGroup() and not KAUtil.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
        return
    end

    -- Same lookup Invite and the tonight strip share, including the solo self-seed: EachGroupUnit
    -- yields nothing while solo, so without it a bulk invite started alone would try to invite the
    -- player themselves.
    local alreadyIn = GroupNameSet()

    -- Count who we'd actually invite (not already present) so we can decide up front whether the
    -- roster needs to be a raid. A party caps at 5, so without converting, invites past slot 5
    -- silently fail. Convert an existing party right now; if we're still solo, flag Core's
    -- GROUP_ROSTER_UPDATE handler to convert the moment the invitees fill the party — see
    -- KART.pendingBulkRaidConvert in Core.lua. An explicit bulk invite always intends a raid, so
    -- this ignores the autoConvertToRaid preference. (In-combat already returned above.)
    local toInvite = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if not (alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)]) then toInvite = toInvite + 1 end
    end
    -- Solo counts too: UnitIsGroupLeader("player") is false when ungrouped, which would skip the
    -- else-branch that flags the deferred conversion — so gate on "solo OR party leader" instead.
    -- (A party non-leader can't convert anyway, and a raid needs no conversion.)
    if (not IsInGroup() or UnitIsGroupLeader("player")) and not IsInRaid() and (GetNumGroupMembers() + toInvite) > 5 then
        if IsInGroup() then
            C_PartyInfo.ConvertToRaid()
        else
            KART.pendingBulkRaidConvert = true
            -- Expire the flag if the invites never land. It is otherwise only cleared once we're in
            -- a raid or out of a group, so a bulk invite nobody accepts would leave it armed for the
            -- session and silently convert some unrelated 5-man party an hour later.
            C_Timer.After(120, function() KART.pendingBulkRaidConvert = false end)
        end
    end

    local invited = 0
    local skipped = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)] then
            skipped = skipped + 1
        else
            C_PartyInfo.InviteUnit(player)
            invited = invited + 1
        end
    end

    local msg = string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_INVITED, invited, boss.name)
    if skipped > 0 then
        msg = msg .. string.format(" " .. KART.L.WU_MSG_ALREADY_IN, skipped)
    end
    print(msg)
end

-- Who WU.RemoveForBoss would uninvite, as full "Name-Realm" strings. Split out from the removing
-- itself so the confirmation below can say how many people it is about to throw out before it does.
--
-- Never ourselves. EachGroupUnit yields raid1..raidN in a raid and never the literal "player" token,
-- so a plain unit ~= "player" guard would fail to exclude your own raid slot — UnitIsUnit matches the
-- player under whatever token currently represents them, so a roster that does not list you cannot
-- get you kicked from your own raid.
local function PlanRemoval(boss)
    local keepSet = {}
    for _, p in ipairs(boss.players) do
        -- CaseFold (not :lower()) so umlaut names fold consistently with the roster check below.
        keepSet[KAUtil.CaseFold(p)] = true
        local short = p:match("([^%-]+)")
        if short then keepSet[KAUtil.CaseFold(short)] = true end
    end

    local out = {}
    for unit in KAUtil.EachGroupUnit() do
        if not UnitIsUnit(unit, "player") then
            local name, realm = UnitName(unit)
            if name then
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                if not keepSet[KAUtil.CaseFold(full)] and not keepSet[KAUtil.CaseFold(name)] then
                    -- The specific character (full Name-Realm) — the realm-free short name is
                    -- ambiguous when a same-named cross-realm twin is in the group.
                    out[#out + 1] = full
                end
            end
        end
    end
    return out
end

-- Removes current group members who are NOT in the boss's player list.
--
-- Asks first (B96). This is the most destructive thing the addon can do: it throws real people out
-- of the raid, they have to be re-invited and accept again, and there is no undo — while the button
-- is seventy pixels wide and sits directly beside "Invite". Resetting the boss LIST already asked,
-- and says "this cannot be undone"; removing people asked nothing at all.
--
-- The count is in the question, because "remove everyone not on this roster" reads very differently
-- when the answer is two people and when it is eighteen.
function WU.RemoveForBoss(idx)
    if KART_Settings.wuModuleEnabled == false then
        print("|cff00ff00KART:|r " .. KART.L.WU_MODULE_DISABLED_MSG)
        return
    end
    local boss = WU.bosses[idx]
    if not boss then return end
    -- Leader OR assistant may uninvite in-game, so gate the same way WU.InviteBoss does rather than
    -- being stricter (leader-only) for no reason.
    if not KAUtil.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
        return
    end

    local targets = PlanRemoval(boss)
    -- Nobody to remove: say so and ask nothing. A confirmation for a no-op is worse than none at
    -- all — it trains people to click straight through the one that matters.
    if #targets == 0 then
        print(string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_REMOVED, 0, boss.name))
        return
    end

    local dlg = StaticPopupDialogs["KART_WU_REMOVE_CONFIRM"]
    -- The template, not a pre-formatted string: the count rides in as a show argument below, which is
    -- how KART_WU_RESET_CONFIRM and KART_LC_REASSIGN_CONFIRM both do it. Formatting here AND passing
    -- the argument worked only because the finished text no longer contained a placeholder for it to
    -- land in -- a second one added to the locale string later would have found a filled-in text and
    -- an argument list that no longer matched it.
    dlg.text = KART.L.WU_REMOVE_CONFIRM_TEXT
    dlg.button1, dlg.button2 = KART.L.BTN_ACCEPT, KART.L.BTN_CANCEL
    -- The targets are resolved NOW and carried into the dialog, not re-derived on accept: the roster
    -- can change while the question sits on screen, and what the player agreed to is the number they
    -- were shown.
    StaticPopup_Show("KART_WU_REMOVE_CONFIRM", #targets, nil, { targets = targets, name = boss.name })
end

KART.UI:RegisterStaticPopup("KART_WU_REMOVE_CONFIRM", {
    text = "Remove %d players from the raid?", -- overwritten with KART.L.WU_REMOVE_CONFIRM_TEXT before every StaticPopup_Show
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data)
        if not (data and data.targets) then return end
        -- Both gates again, HERE (B108). WU.RemoveForBoss checks them when the question is asked, and
        -- what a confirmation is for is time to think -- during which the raid does not stand still.
        -- Losing lead mid-question is ordinary (a handover, a disconnect moving it), and the pull can
        -- land while the dialog is up.
        --
        -- The two fail differently, and the combat one is the reason this is a fix and not a tidy-up:
        -- UninviteUnit is NOT combat-protected, so the removals would genuinely go through mid-pull,
        -- which is exactly what the gate above exists to stop. Without lead the game refuses them
        -- instead -- the right outcome, but the count below is of attempts, not of successes, so it
        -- reported "2 players removed" to somebody who removed nobody.
        if not KAUtil.HasGroupPermissions() then
            print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
            return
        end
        if InCombatLockdown() then
            print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
            return
        end
        local removed = 0
        for _, full in ipairs(data.targets) do
            UninviteUnit(full)
            removed = removed + 1
        end
        print(string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_REMOVED, removed, data.name))
    end,
})

KART.UI:RegisterStaticPopup("KART_WU_RESET_CONFIRM", {
    text = "Really reset the boss list?", -- overwritten with KART.L.WU_RESET_CONFIRM_TEXT before every StaticPopup_Show call below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        WU.ResetBosses()
        if WU.statusLabel then
            WU.statusLabel:SetText(KART.L.WU_STATUS_EMPTY)
            WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end,
})

-- =====================================================================
--  Boss List UI
-- =====================================================================

local ROW_H   = 28
local ROW_GAP = 3

function WU.RefreshBossList()
    local panel = WU.bossListFrame
    if not panel then return end

    if panel.rows then
        for _, row in ipairs(panel.rows) do row:Hide() end
    end
    panel.rows = panel.rows or {}

    if #WU.bosses == 0 then
        panel.emptyLabel:Show()
        panel:SetHeight(24)
        if KART.UpdateScrollRange then KART.UpdateScrollRange() end
        return
    end
    panel.emptyLabel:Hide()

    local totalH = 0
    for i, boss in ipairs(WU.bosses) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetHeight(ROW_H)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 4, 0)
            row.nameText:SetJustifyH("LEFT")
            KART.UI:RegisterLabel(row.nameText)

            row.btnRemove = KART.UI:CreateModernButton(row, KART.L.WU_BTN_REMOVE)
            row.btnRemove:SetSize(80, 22)
            row.btnRemove:SetPoint("RIGHT", row, "RIGHT", -4, 0)

            row.btnInvite = KART.UI:CreateModernButton(row, KART.L.WU_BTN_INVITE)
            row.btnInvite:SetSize(80, 22)
            row.btnInvite:SetPoint("RIGHT", row.btnRemove, "LEFT", -8, 0)

            row.nameText:SetPoint("RIGHT", row.btnInvite, "LEFT", -10, 0)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i-1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT",   panel, "RIGHT",   0, 0)

        row.nameText:SetText(boss.name .. " |cff888888(" .. #boss.players .. ")|r")

        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(boss.name, 1, 0.82, 0)
            GameTooltip:AddLine(boss.difficulty, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(KART.L.WU_ENCOUNTER_ID .. (boss.encounterID or "?"), 0.5, 0.5, 0.5)
            GameTooltip:AddLine(#boss.players .. " " .. KART.L.WU_PLAYERS, 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.btnInvite:SetScript("OnClick", function() WU.InviteBoss(i) end)
        row.btnRemove:SetScript("OnClick", function() WU.RemoveForBoss(i) end)

        row:Show()
        totalH = i * (ROW_H + ROW_GAP)
    end

    panel:SetHeight(math.max(totalH, 24))
    if WU.bossListCard then
        WU.bossListCard:SetHeight(math.max(totalH, 24) + 24)
    end
    -- Boss list height feeds the WoWUtils tab's scroll range.
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
end

-- =====================================================================
--  Panel builder  (fills KART.WoWUtilsPanel)
-- =====================================================================

function WU.BuildPanel(parent)
    local L = KART.L

    KART.CreateTabTitle(5, L.WU_TITLE)

    local wuEnableCard = KART.UI:CreateCard(parent)
    wuEnableCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    wuEnableCard:SetSize(500, 50)
    KART.CbWuModule = KART.UI:CreateSettingsCheckbox(wuEnableCard, {
        name = "KART_WuModuleEnabled", label = L.SET_WU_MODULE_ENABLED,
        store = SettingsStore, key = "wuModuleEnabled", y = -20,
        tooltip = L.DESC_WU_MODULE_ENABLED,
        onChanged = function()
            if KART.RefreshModuleChips then KART.RefreshModuleChips() end
        end,
    })
    KART.CbWuModule.text:SetWidth(430)
    KART.CbWuModule.text:SetJustifyH("LEFT")

    local importCard = KART.UI:CreateCard(parent)
    importCard:SetPoint("TOPLEFT", wuEnableCard, "BOTTOMLEFT", 0, -12)
    importCard:SetSize(500, 190)

    local pasteLabel = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pasteLabel:SetPoint("TOPLEFT", 20, -15)
    pasteLabel:SetText(L.WU_LABEL_PASTE)
    KART.UI:RegisterLabel(pasteLabel)

    local pasteBG = CreateFrame("Frame", nil, importCard, "BackdropTemplate")
    pasteBG:SetSize(460, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -35)
    KART.UI:SetPixelBackdrop(pasteBG, {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    -- Same inset/border colors as KART.UI:CreateStyledEditBox; the multi-line box can't use that
    -- factory directly (the EditBox lives inside a ScrollFrame, the visual box is this frame),
    -- so the focus accent is mirrored below via the inner EditBox's focus scripts.
    pasteBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
    pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    KART.UI:ApplyRoundedMask(pasteBG, KAUI.CORNER_RADIUS_LG)

    local pasteScroll = CreateFrame("ScrollFrame", "KART_WUPasteScroll", pasteBG, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", 4, -4)
    pasteScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local pasteScrollThumb = KART.UI:StripScrollbarTextures(pasteScroll)
    if pasteScrollThumb then pasteScrollThumb:SetSize(6, 16) end
    KART.UI:RegisterAccentTexture(pasteScrollThumb, 0.6)

    WU.ImportEditBox = CreateFrame("EditBox", "KART_WUImportEditBox", pasteScroll)
    WU.ImportEditBox:SetWidth(428)
    -- An EditBox with no explicit height auto-sizes to a single line, far shorter than the
    -- visible paste box (pasteBG, 90px tall) — clicking anywhere below that first line then hits
    -- empty scroll-frame space instead of the EditBox, so the cursor never activates there. Fix:
    -- give it a fixed height comfortably taller than the viewport, so every click inside the
    -- visible box lands on the EditBox, and pasted text beyond the viewport still scrolls.
    WU.ImportEditBox:SetHeight(300)
    WU.ImportEditBox:SetMultiLine(true)
    WU.ImportEditBox:SetAutoFocus(false)
    WU.ImportEditBox:SetFontObject("GameFontHighlightSmall")
    -- Staging only. wuImportText is committed on a successful Import (see
    -- WU.ImportPastedText); writing it here erased stacked exports the moment the
    -- next paste replaced the box.
    WU.ImportEditBox:SetScript("OnTextChanged", function() end)
    WU.ImportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    WU.ImportEditBox:SetScript("OnEditFocusGained", function()
        local r, g, b = KART.UI:AccentColor()
        pasteBG:SetBackdropBorderColor(r, g, b, 1)
    end)
    WU.ImportEditBox:SetScript("OnEditFocusLost", function()
        pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    pasteScroll:SetScrollChild(WU.ImportEditBox)
    KART.UI:RegisterEditBox(WU.ImportEditBox)

    -- Catches clicks on the empty part of the box and hands focus to the EditBox.
    --
    -- The SetHeight(300) above was the first attempt at this and does not hold: a multi-line EditBox
    -- auto-sizes its height to its own text, so the forced height survives only until the first text
    -- change. After that the frame is one line tall, everything below it is bare ScrollFrame, and
    -- clicking there did nothing -- only the top of the visible box started editing (B6).
    --
    -- Deliberately a sibling BEHIND the scroll frame rather than an overlay: the EditBox keeps
    -- receiving the clicks that land on it, so the caret still goes exactly where it is clicked, and
    -- only clicks that would otherwise have hit nothing reach this.
    local pasteClickCatcher = CreateFrame("Frame", nil, pasteBG)
    pasteClickCatcher:SetAllPoints(pasteScroll)
    pasteClickCatcher:SetFrameLevel(math.max(pasteScroll:GetFrameLevel() - 1, 0))
    pasteClickCatcher:EnableMouse(true)
    pasteClickCatcher:SetScript("OnMouseDown", function()
        WU.ImportEditBox:SetFocus()
        WU.ImportEditBox:SetCursorPosition(#WU.ImportEditBox:GetText())
    end)

    WU.BtnImport = KART.UI:CreateModernButton(importCard, L.WU_BTN_IMPORT)
    WU.BtnImport:SetSize(180, 26)
    WU.BtnImport:SetPoint("TOPLEFT", 20, -135)
    WU.BtnImport:SetScript("OnClick", function()
        local text = WU.ImportEditBox:GetText()
        local _, status = WU.ImportPastedText(text)
        if status == "same" or status == "ok" then
            WU.statusLabel:SetText(string.format(L.WU_STATUS_LOADED, #WU.bosses))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
        elseif status == "empty" then
            return
        else
            WU.statusLabel:SetText(L.WU_STATUS_PARSE_ERROR)
            WU.statusLabel:SetTextColor(0.9, 0.3, 0.3)
        end
    end)

    WU.BtnReset = KART.UI:CreateModernButton(importCard, L.WU_BTN_RESET)
    WU.BtnReset:SetSize(100, 26)
    WU.BtnReset:SetPoint("LEFT", WU.BtnImport, "RIGHT", 10, 0)
    WU.BtnReset:SetScript("OnClick", function()
        -- Also offer the reset when the visible list is empty but a saved import text still exists:
        -- that text is what rebuilds the list on the next login/profile switch, so it is exactly what
        -- needs clearing (see WU.ResetBosses). Only a truly clean slate is a no-op.
        if #WU.bosses == 0 and (KART_Settings.wuImportText or "") == "" then return end
        StaticPopupDialogs["KART_WU_RESET_CONFIRM"].text = L.WU_RESET_CONFIRM_TEXT
        StaticPopup_Show("KART_WU_RESET_CONFIRM")
    end)

    WU.statusLabel = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    WU.statusLabel:SetPoint("TOPLEFT", 20, -168)
    WU.statusLabel:SetText(L.WU_STATUS_EMPTY)
    WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
    KART.UI:RegisterLabel(WU.statusLabel)

    local wuBossTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    wuBossTitle:SetPoint("TOPLEFT", importCard, "BOTTOMLEFT", 0, -18)
    wuBossTitle:SetText(L.WU_LABEL_BOSSES)
    KART.UI:RegisterLabel(wuBossTitle)

    local bossCard = KART.UI:CreateCard(parent)
    bossCard:SetPoint("TOPLEFT", wuBossTitle, "BOTTOMLEFT", 0, -10)
    bossCard:SetSize(500, 48)
    WU.bossListCard = bossCard

    WU.bossListFrame = CreateFrame("Frame", nil, bossCard)
    WU.bossListFrame:SetPoint("TOPLEFT", bossCard, "TOPLEFT", 16, -12)
    WU.bossListFrame:SetPoint("BOTTOMRIGHT", bossCard, "BOTTOMRIGHT", -16, 12)
    WU.bossListFrame.rows = {}

    WU.bossListFrame.emptyLabel = WU.bossListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    WU.bossListFrame.emptyLabel:SetPoint("TOPLEFT", 4, -2)
    WU.bossListFrame.emptyLabel:SetText(L.WU_STATUS_EMPTY)
    WU.bossListFrame.emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    KART.UI:RegisterLabel(WU.bossListFrame.emptyLabel)

    KART.UI:RegisterLocaleRefresher(function()
        local Lx = KART.L
        if KART.TabTitles and KART.TabTitles[5] then
            KART.TabTitles[5]:SetText(Lx.WU_TITLE)
        end
        if KART.CbWuModule then
            KART.CbWuModule.text:SetText(Lx.SET_WU_MODULE_ENABLED)
            KART.CbWuModule.tooltipText = Lx.DESC_WU_MODULE_ENABLED
        end
        pasteLabel:SetText(Lx.WU_LABEL_PASTE)
        WU.BtnImport.text:SetText(Lx.WU_BTN_IMPORT)
        WU.BtnReset.text:SetText(Lx.WU_BTN_RESET)
        -- Empty-state texts; SyncSettingsToUI overwrites the status right after these
        -- refreshers run when a saved import auto-parses.
        WU.statusLabel:SetText(Lx.WU_STATUS_EMPTY)
        WU.bossListFrame.emptyLabel:SetText(Lx.WU_STATUS_EMPTY)
        wuBossTitle:SetText(Lx.WU_LABEL_BOSSES)
        if WU.bossListFrame.rows then
            for _, row in ipairs(WU.bossListFrame.rows) do
                if row.btnInvite and row.btnInvite.text then
                    row.btnInvite.text:SetText(Lx.WU_BTN_INVITE)
                end
                if row.btnRemove and row.btnRemove.text then
                    row.btnRemove.text:SetText(Lx.WU_BTN_REMOVE)
                end
            end
        end
    end)
end

-- Invite.lua loads after MainFrame.lua, so the panel already exists here.
if KART.WoWUtilsPanel then
    WU.BuildPanel(KART.WoWUtilsPanel)
end
