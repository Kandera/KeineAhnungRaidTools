local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")

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
    -- intentional: the invitelist capture [^;]+ is correct for the real WoWUtils export — each
    -- invitelist is terminated by a trailing ";" ("...Name-Realm;"), so [^;]+ stops there and never
    -- bleeds into the next boss block; %s+ absorbs the blank line before "invitelist:". Verified
    -- against a real multi-boss export, not changed (review 2026-07-24).
    for encounterID, difficulty, bossName, playerStr in rawText:gmatch(
            "EncounterID:(%d+);Difficulty:([^;]+);Name:([^\n\r]+)%s+invitelist:([^;]+)") do

        bossName   = KAUtil.TrimString(bossName)
        difficulty = KAUtil.TrimString(difficulty)
        playerStr  = KAUtil.TrimString(playerStr)
        encounterID = tonumber(encounterID)

        local players = {}
        for p in playerStr:gmatch("%S+") do
            table.insert(players, p)
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
    -- Also drop the saved import text, otherwise the login/profile-switch auto-parse in
    -- KART.SyncSettingsToUI re-creates the whole list from it and the reset silently undoes itself
    -- on the next /reload (lastImportedText is a runtime field and never survives a session).
    KART_Settings.wuImportText = ""
    if WU.ImportEditBox then WU.ImportEditBox:SetText("") end
    WU.RefreshBossList()
end

-- =====================================================================
--  Actions
-- =====================================================================

function WU.InviteBoss(idx)
    if KART_Settings.wuModuleEnabled == false then return end
    local boss = WU.bosses[idx]
    if not boss then return end
    if not KAUtil.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
        return
    end

    -- Build a lookup of players already in the group (with and without realm).
    local alreadyIn = {}
    -- Seed with ourselves unconditionally: EachGroupUnit yields nothing while solo, so a bulk invite
    -- started alone (the case the deferred raid conversion below exists for) would otherwise try to
    -- invite the player themselves — a red "You can't invite yourself" error, and an invited count
    -- one too high.
    do
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
            -- CaseFold (not :lower()) so DE-realm umlaut names fold consistently with the boss list
            -- below — :lower() is ASCII-only and leaves Ö/Ä/Ü untouched (see Utils.lua CaseFold).
            alreadyIn[KAUtil.CaseFold(full)] = true
            alreadyIn[KAUtil.CaseFold(name)] = true
        end
    end

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

-- Removes current group members who are NOT in the boss's player list.
function WU.RemoveForBoss(idx)
    if KART_Settings.wuModuleEnabled == false then return end
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

    local keepSet = {}
    for _, p in ipairs(boss.players) do
        -- CaseFold (not :lower()) so umlaut names fold consistently with the roster check below.
        keepSet[KAUtil.CaseFold(p)] = true
        local short = p:match("([^%-]+)")
        if short then keepSet[KAUtil.CaseFold(short)] = true end
    end

    local removed = 0
    for unit in KAUtil.EachGroupUnit() do
        -- Never uninvite yourself. EachGroupUnit yields raid1..raidN in a raid (never the literal
        -- "player" token), so a plain unit ~= "player" guard would fail to exclude your own raid
        -- slot — UnitIsUnit matches the player under whatever token currently represents them, so
        -- a roster that doesn't list you can't get you kicked from your own raid.
        if not UnitIsUnit(unit, "player") then
            local name, realm = UnitName(unit)
            if name then
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                if not keepSet[KAUtil.CaseFold(full)] and not keepSet[KAUtil.CaseFold(name)] then
                    -- Uninvite the specific character (full Name-Realm) — the realm-free short name
                    -- is ambiguous when a same-named cross-realm twin is in the group.
                    UninviteUnit(full)
                    removed = removed + 1
                end
            end
        end
    end
    print(string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_REMOVED, removed, boss.name))
end

KART.RegisterStaticPopup("KART_WU_RESET_CONFIRM", {
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
            row = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetBackdrop({
                bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 6, 0)
            row.nameText:SetWidth(140)
            row.nameText:SetJustifyH("LEFT")
            table.insert(KART.DynamicLabels, row.nameText)

            row.btnInvite = KART.CreateModernButton(row, KART.L.WU_BTN_INVITE)
            row.btnInvite:SetSize(70, 22)
            row.btnInvite:SetPoint("RIGHT", row, "RIGHT", -76, 0)

            row.btnRemove = KART.CreateModernButton(row, KART.L.WU_BTN_REMOVE)
            row.btnRemove:SetSize(70, 22)
            row.btnRemove:SetPoint("RIGHT", row, "RIGHT", -2, 0)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i-1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT",   panel, "RIGHT",   0, 0)
        local lr, lg, lb = KART.GetRowStripeColor()
        row:SetBackdropColor(lr, lg, lb, i % 2 == 0 and 0.4 or 0.15)
        row:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)

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
    -- Boss list height feeds the WoWUtils tab's scroll range.
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
end

-- =====================================================================
--  Panel builder  (fills KART.WoWUtilsPanel)
-- =====================================================================

function WU.BuildPanel(parent)
    local L = KART.L

    KART.CreateTabTitle(6, L.WU_TITLE)

    -- Master switch: fully disables the WoWUtils import/invite module.
    KART.WU.CbModuleEnabled = KART.CreateSettingsCheckbox(
        parent, "KART_WUModuleEnabled",
        L.WU_SET_MODULE_ENABLED, "wuModuleEnabled", -7, nil, L.WU_DESC_MODULE_ENABLED)

    local importCard = KART.CreateCard(parent)
    importCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -47)
    importCard:SetSize(500, 190)

    local pasteLabel = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pasteLabel:SetPoint("TOPLEFT", 20, -15)
    pasteLabel:SetText(L.WU_LABEL_PASTE)
    table.insert(KART.DynamicLabels, pasteLabel)

    local pasteBG = CreateFrame("Frame", nil, importCard, "BackdropTemplate")
    pasteBG:SetSize(460, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -35)
    pasteBG:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    -- Same inset/border colors as KART.CreateStyledEditBox; the multi-line box can't use that
    -- factory directly (the EditBox lives inside a ScrollFrame, the visual box is this frame),
    -- so the focus accent is mirrored below via the inner EditBox's focus scripts.
    pasteBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
    pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    KART.ApplyRoundedMask(pasteBG, KART.Theme.CORNER_RADIUS_LG)

    local pasteScroll = CreateFrame("ScrollFrame", "KART_WUPasteScroll", pasteBG, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", 4, -4)
    pasteScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    KART.WUPasteScrollThumb = KART.StripScrollbarTextures(pasteScroll)
    if KART.WUPasteScrollThumb then KART.WUPasteScrollThumb:SetSize(6, 16) end

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
    WU.ImportEditBox:SetScript("OnTextChanged", function(self)
        if KART_Settings then KART_Settings.wuImportText = self:GetText() end
    end)
    WU.ImportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    WU.ImportEditBox:SetScript("OnEditFocusGained", function()
        local r, g, b = KART.Theme.AccentColor()
        pasteBG:SetBackdropBorderColor(r, g, b, 1)
    end)
    WU.ImportEditBox:SetScript("OnEditFocusLost", function()
        pasteBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
    end)
    pasteScroll:SetScrollChild(WU.ImportEditBox)
    table.insert(KART.EditBoxes, WU.ImportEditBox)

    WU.BtnImport = KART.CreateModernButton(importCard, L.WU_BTN_IMPORT)
    WU.BtnImport:SetSize(180, 26)
    WU.BtnImport:SetPoint("TOPLEFT", 20, -135)
    WU.BtnImport:SetScript("OnClick", function()
        if KART_Settings.wuModuleEnabled == false then return end
        local text = WU.ImportEditBox:GetText()
        if KAUtil.TrimString(text) ~= "" and text == WU.lastImportedText then
            -- Identical to what's already loaded (e.g. auto-parsed from the saved text at login) —
            -- re-parsing would duplicate every boss. Report it as already loaded instead.
            WU.statusLabel:SetText(string.format(L.WU_STATUS_LOADED, #WU.bosses))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
            return
        end
        -- Replace, don't append. Only the edit box's text is persisted (wuImportText), so the list
        -- has to be reconstructible from it alone — an appended second import would silently shrink
        -- back to just the last export on the next /reload or profile switch, and re-clicking Import
        -- on a box holding both exports would duplicate the first one as "Boss A"/"Boss B".
        -- Stacking several exports still works the intended way: paste them all into the box, which
        -- parses every EncounterID block it contains.
        local previous = WU.bosses
        WU.bosses = {}
        local count = WU.ParseImport(text)
        if count > 0 then
            WU.RefreshBossList()
            WU.statusLabel:SetText(string.format(L.WU_STATUS_LOADED, count))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
        else
            -- Nothing parsed — hand the previous list straight back instead of leaving the user with
            -- an empty one. (Rebuilding from wuImportText wouldn't work: the edit box's OnTextChanged
            -- has already overwritten it with the text that just failed to parse.)
            WU.bosses = previous
            WU.statusLabel:SetText(L.WU_STATUS_PARSE_ERROR)
            WU.statusLabel:SetTextColor(0.9, 0.3, 0.3)
        end
    end)

    WU.BtnReset = KART.CreateModernButton(importCard, L.WU_BTN_RESET)
    WU.BtnReset:SetSize(100, 26)
    WU.BtnReset:SetPoint("LEFT", WU.BtnImport, "RIGHT", 10, 0)
    WU.BtnReset:SetScript("OnClick", function()
        if KART_Settings.wuModuleEnabled == false then return end
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
    table.insert(KART.DynamicLabels, WU.statusLabel)

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  5, -252)
    sep:SetPoint("TOPRIGHT", -5, -252)

    local hBoss = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hBoss:SetPoint("TOPLEFT", 8, -262)
    hBoss:SetText("|cffaaaaaa" .. L.WU_COL_BOSS .. "|r")
    table.insert(KART.DynamicLabels, hBoss)

    local hInvite = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hInvite:SetPoint("TOPRIGHT", -110, -262)
    hInvite:SetText("|cffaaaaaa" .. L.WU_BTN_INVITE .. "|r")
    table.insert(KART.DynamicLabels, hInvite)

    local hRemove = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hRemove:SetPoint("TOPRIGHT", -38, -262)
    hRemove:SetText("|cffaaaaaa" .. L.WU_BTN_REMOVE .. "|r")
    table.insert(KART.DynamicLabels, hRemove)

    WU.bossListFrame = CreateFrame("Frame", nil, parent)
    WU.bossListFrame:SetPoint("TOPLEFT",  5, -278)
    WU.bossListFrame:SetPoint("RIGHT", parent, "RIGHT", -5, 0)
    WU.bossListFrame:SetHeight(24)
    WU.bossListFrame.rows = {}

    WU.bossListFrame.emptyLabel = WU.bossListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    WU.bossListFrame.emptyLabel:SetPoint("TOPLEFT", 6, -6)
    WU.bossListFrame.emptyLabel:SetText(L.WU_STATUS_EMPTY)
    WU.bossListFrame.emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    table.insert(KART.DynamicLabels, WU.bossListFrame.emptyLabel)

    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        KART.TabTitles[6]:SetText(Lx.WU_TITLE)
        KART.WU.CbModuleEnabled.text:SetText(Lx.WU_SET_MODULE_ENABLED)
        KART.WU.CbModuleEnabled.tooltipText = Lx.WU_DESC_MODULE_ENABLED
        pasteLabel:SetText(Lx.WU_LABEL_PASTE)
        WU.BtnImport.text:SetText(Lx.WU_BTN_IMPORT)
        WU.BtnReset.text:SetText(Lx.WU_BTN_RESET)
        -- Empty-state texts; SyncSettingsToUI overwrites the status right after these
        -- refreshers run when a saved import auto-parses.
        WU.statusLabel:SetText(Lx.WU_STATUS_EMPTY)
        WU.bossListFrame.emptyLabel:SetText(Lx.WU_STATUS_EMPTY)
        hBoss:SetText("|cffaaaaaa" .. Lx.WU_COL_BOSS .. "|r")
        hInvite:SetText("|cffaaaaaa" .. Lx.WU_BTN_INVITE .. "|r")
        hRemove:SetText("|cffaaaaaa" .. Lx.WU_BTN_REMOVE .. "|r")
    end)
end

-- Invite.lua loads after MainFrame.lua, so the panel already exists here.
if KART.WoWUtilsPanel then
    WU.BuildPanel(KART.WoWUtilsPanel)
end
