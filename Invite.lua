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
    local boss = WU.bosses[idx]
    if not boss then return end
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
            row = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            row:SetHeight(ROW_H)
            KART.UI:SetPixelBackdrop(row, {
                bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 6, 0)
            row.nameText:SetWidth(140)
            row.nameText:SetJustifyH("LEFT")
            KART.UI:RegisterLabel(row.nameText)

            row.btnInvite = KART.UI:CreateModernButton(row, KART.L.WU_BTN_INVITE)
            row.btnInvite:SetSize(70, 22)
            row.btnInvite:SetPoint("RIGHT", row, "RIGHT", -76, 0)

            row.btnRemove = KART.UI:CreateModernButton(row, KART.L.WU_BTN_REMOVE)
            row.btnRemove:SetSize(70, 22)
            row.btnRemove:SetPoint("RIGHT", row, "RIGHT", -2, 0)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i-1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT",   panel, "RIGHT",   0, 0)
        local lr, lg, lb = KART.UI:GetRowStripeColor()
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
--  Panel builder  (fills the Automation tab's WoWUtils paste section)
-- =====================================================================

function WU.BuildPanel(parent)
    local L = KART.L

    local wuTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    wuTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -430)
    wuTitle:SetText(L.WU_TITLE)
    KART.UI:RegisterLabel(wuTitle)

    local importCard = KART.UI:CreateCard(parent)
    importCard:SetPoint("TOPLEFT", wuTitle, "BOTTOMLEFT", 0, -10)
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
    WU.ImportEditBox:SetScript("OnTextChanged", function(self)
        if KART_Settings then KART_Settings.wuImportText = self:GetText() end
    end)
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

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  5, -252)
    sep:SetPoint("TOPRIGHT", -5, -252)

    local hBoss = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hBoss:SetPoint("TOPLEFT", 8, -262)
    hBoss:SetText("|cffaaaaaa" .. L.WU_COL_BOSS .. "|r")
    KART.UI:RegisterLabel(hBoss)

    local hInvite = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hInvite:SetPoint("TOPRIGHT", -110, -262)
    hInvite:SetText("|cffaaaaaa" .. L.WU_BTN_INVITE .. "|r")
    KART.UI:RegisterLabel(hInvite)

    local hRemove = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hRemove:SetPoint("TOPRIGHT", -38, -262)
    hRemove:SetText("|cffaaaaaa" .. L.WU_BTN_REMOVE .. "|r")
    KART.UI:RegisterLabel(hRemove)

    WU.bossListFrame = CreateFrame("Frame", nil, parent)
    WU.bossListFrame:SetPoint("TOPLEFT",  5, -278)
    WU.bossListFrame:SetPoint("RIGHT", parent, "RIGHT", -5, 0)
    WU.bossListFrame:SetHeight(24)
    WU.bossListFrame.rows = {}

    WU.bossListFrame.emptyLabel = WU.bossListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    WU.bossListFrame.emptyLabel:SetPoint("TOPLEFT", 6, -6)
    WU.bossListFrame.emptyLabel:SetText(L.WU_STATUS_EMPTY)
    WU.bossListFrame.emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    KART.UI:RegisterLabel(WU.bossListFrame.emptyLabel)

    KART.UI:RegisterLocaleRefresher(function()
        local Lx = KART.L
        wuTitle:SetText(Lx.WU_TITLE)
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
if KART.PromotePanel then
    WU.BuildPanel(KART.PromotePanel)
end
