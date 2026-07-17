local addonName, KART = ...

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
    if not rawText or KART.TrimString(rawText) == "" then return 0 end

    local parsedCount = 0
    for encounterID, difficulty, bossName, playerStr in rawText:gmatch(
            "EncounterID:(%d+);Difficulty:([^;]+);Name:([^\n\r]+)%s+invitelist:([^;]+)") do

        bossName   = KART.TrimString(bossName)
        difficulty = KART.TrimString(difficulty)
        playerStr  = KART.TrimString(playerStr)
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

    return parsedCount
end

function WU.ResetBosses()
    WU.bosses = {}
    WU.RefreshBossList()
end

-- =====================================================================
--  Actions
-- =====================================================================

function WU.InviteBoss(idx)
    if KART_Settings.wuModuleEnabled == false then return end
    local boss = WU.bosses[idx]
    if not boss then return end
    if not KART.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. (KART.L.WU_MSG_NOT_LEADER or "Only group leaders can invite players."))
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. (KART.L.WU_MSG_COMBAT or "Cannot invite during combat."))
        return
    end

    if KART_Settings.autoConvertToRaid and IsInGroup() and not IsInRaid() and not InCombatLockdown() then
        C_PartyInfo.ConvertToRaid()
    end

    -- Build a lookup of players already in the group (with and without realm).
    local alreadyIn = {}
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local name, realm = UnitName(unit)
        if name then
            local full = (realm and realm ~= "") and (name.."-"..realm) or name
            alreadyIn[full:lower()] = true
            alreadyIn[name:lower()] = true
        end
    end

    local invited = 0
    local skipped = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if alreadyIn[player:lower()] or alreadyIn[short:lower()] then
            skipped = skipped + 1
        else
            C_PartyInfo.InviteUnit(player)
            invited = invited + 1
        end
    end

    local msg = string.format("|cff00ff00KART:|r " .. (KART.L.WU_MSG_INVITED or "%d players invited for %s."), invited, boss.name)
    if skipped > 0 then
        msg = msg .. string.format(" " .. (KART.L.WU_MSG_ALREADY_IN or "(%d already in raid)"), skipped)
    end
    print(msg)
end

-- Removes current group members who are NOT in the boss's player list.
function WU.RemoveForBoss(idx)
    if KART_Settings.wuModuleEnabled == false then return end
    local boss = WU.bosses[idx]
    if not boss then return end
    if not UnitIsGroupLeader("player") then
        print("|cff00ff00KART:|r " .. (KART.L.WU_MSG_NOT_LEADER or "Only the raid leader can remove players."))
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. (KART.L.WU_MSG_COMBAT or "Cannot remove during combat."))
        return
    end

    local keepSet = {}
    for _, p in ipairs(boss.players) do
        keepSet[p:lower()] = true
        local short = p:match("([^%-]+)")
        if short then keepSet[short:lower()] = true end
    end

    local isRaid  = IsInRaid()
    local numMem  = GetNumGroupMembers()
    local removed = 0
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        if unit ~= "player" then
            local name, realm = UnitName(unit)
            if name then
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                if not keepSet[full:lower()] and not keepSet[name:lower()] then
                    UninviteUnit(name)
                    removed = removed + 1
                end
            end
        end
    end
    print(string.format("|cff00ff00KART:|r " .. (KART.L.WU_MSG_REMOVED or "%d players removed for %s."), removed, boss.name))
end

StaticPopupDialogs["KART_WU_RESET_CONFIRM"] = {
    text = "Really reset the boss list?", -- overwritten with KART.L.WU_RESET_CONFIRM_TEXT before every StaticPopup_Show call below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        WU.ResetBosses()
        if WU.statusLabel then
            WU.statusLabel:SetText(KART.L.WU_STATUS_EMPTY or "Noch kein Import.")
            WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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

            row.btnInvite = KART.CreateModernButton(row, KART.L.WU_BTN_INVITE or "Einladen")
            row.btnInvite:SetSize(70, 22)
            row.btnInvite:SetPoint("RIGHT", row, "RIGHT", -76, 0)

            row.btnRemove = KART.CreateModernButton(row, KART.L.WU_BTN_REMOVE or "Entfernen")
            row.btnRemove:SetSize(70, 22)
            row.btnRemove:SetPoint("RIGHT", row, "RIGHT", -2, 0)

            panel.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i-1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT",   panel, "RIGHT",   0, 0)
        local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
        local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
        row:SetBackdropColor(lr, lg, lb, i % 2 == 0 and 0.4 or 0.15)
        row:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)

        row.nameText:SetText(boss.name .. " |cff888888(" .. #boss.players .. ")|r")

        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(boss.name, 1, 0.82, 0)
            GameTooltip:AddLine(boss.difficulty, 0.7, 0.7, 0.7)
            GameTooltip:AddLine("EncounterID: " .. (boss.encounterID or "?"), 0.5, 0.5, 0.5)
            GameTooltip:AddLine(#boss.players .. " " .. (KART.L.WU_PLAYERS or "Spieler"), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local capturedIdx = i
        row.btnInvite:SetScript("OnClick", function() WU.InviteBoss(capturedIdx) end)
        row.btnRemove:SetScript("OnClick", function() WU.RemoveForBoss(capturedIdx) end)

        row:Show()
        totalH = i * (ROW_H + ROW_GAP)
    end

    panel:SetHeight(math.max(totalH, 24))
end

-- =====================================================================
--  Panel builder  (fills KART.WoWUtilsPanel)
-- =====================================================================

function WU.BuildPanel(parent)
    local L = KART.L

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(L.WU_TITLE or "WoWUtils Import")
    table.insert(KART.DynamicLabels, title)

    -- Master switch: fully disables the WoWUtils import/invite module.
    KART.WU.CbModuleEnabled = KART.CreateSettingsCheckbox(
        parent, "KART_WUModuleEnabled",
        L.WU_SET_MODULE_ENABLED, "wuModuleEnabled", -45, nil, L.WU_DESC_MODULE_ENABLED)

    local pasteLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pasteLabel:SetPoint("TOPLEFT", 20, -85)
    pasteLabel:SetText(L.WU_LABEL_PASTE or "WoWUtils Export hier einfügen:")
    table.insert(KART.DynamicLabels, pasteLabel)

    local pasteBG = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pasteBG:SetSize(265, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -102)
    pasteBG:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    pasteBG:SetBackdropColor(0, 0, 0, 0.5)
    pasteBG:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    KART.ApplyRoundedMask(pasteBG, KART.Theme.CORNER_RADIUS_LG)

    local pasteScroll = CreateFrame("ScrollFrame", "KART_WUPasteScroll", pasteBG, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", 4, -4)
    pasteScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    KART.WUPasteScrollThumb = KART.StripScrollbarTextures(pasteScroll)
    if KART.WUPasteScrollThumb then KART.WUPasteScrollThumb:SetSize(6, 16) end

    WU.ImportEditBox = CreateFrame("EditBox", "KART_WUImportEditBox", pasteScroll)
    WU.ImportEditBox:SetWidth(234)
    WU.ImportEditBox:SetMultiLine(true)
    WU.ImportEditBox:SetAutoFocus(false)
    WU.ImportEditBox:SetFontObject("GameFontHighlightSmall")
    WU.ImportEditBox:SetScript("OnTextChanged", function(self)
        if KART_Settings then KART_Settings.wuImportText = self:GetText() end
    end)
    WU.ImportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pasteScroll:SetScrollChild(WU.ImportEditBox)
    table.insert(KART.EditBoxes, WU.ImportEditBox)

    WU.BtnImport = KART.CreateModernButton(parent, L.WU_BTN_IMPORT or "Importieren")
    WU.BtnImport:SetSize(180, 26)
    WU.BtnImport:SetPoint("TOPLEFT", 20, -200)
    WU.BtnImport:SetScript("OnClick", function()
        if KART_Settings.wuModuleEnabled == false then return end
        local text = WU.ImportEditBox:GetText()
        local count = WU.ParseImport(text)
        if count > 0 then
            WU.RefreshBossList()
            WU.statusLabel:SetText(string.format(L.WU_STATUS_LOADED or "%d Bosse geladen.", count))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
        else
            WU.statusLabel:SetText(L.WU_STATUS_PARSE_ERROR or "Kein gültiges WoWUtils-Format gefunden.")
            WU.statusLabel:SetTextColor(0.9, 0.3, 0.3)
        end
    end)

    WU.BtnReset = KART.CreateModernButton(parent, L.WU_BTN_RESET or "Zurücksetzen")
    WU.BtnReset:SetSize(77, 26)
    WU.BtnReset:SetPoint("TOPLEFT", 208, -200)
    WU.BtnReset:SetScript("OnClick", function()
        if KART_Settings.wuModuleEnabled == false then return end
        if #WU.bosses == 0 then return end
        StaticPopupDialogs["KART_WU_RESET_CONFIRM"].text = L.WU_RESET_CONFIRM_TEXT or "Boss-Liste wirklich zurücksetzen?"
        StaticPopup_Show("KART_WU_RESET_CONFIRM")
    end)

    WU.statusLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    WU.statusLabel:SetPoint("TOPLEFT", 20, -235)
    WU.statusLabel:SetText(L.WU_STATUS_EMPTY or "Noch kein Import.")
    WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
    table.insert(KART.DynamicLabels, WU.statusLabel)

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.22, 0.22, 0.22, 1)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  5, -248)
    sep:SetPoint("TOPRIGHT", -5, -248)

    local hBoss = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hBoss:SetPoint("TOPLEFT", 8, -258)
    hBoss:SetText("|cffaaaaaa" .. (L.WU_COL_BOSS or "Boss") .. "|r")
    table.insert(KART.DynamicLabels, hBoss)

    local hInvite = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hInvite:SetPoint("TOPRIGHT", -110, -258)
    hInvite:SetText("|cffaaaaaa" .. (L.WU_BTN_INVITE or "Einl.") .. "|r")
    table.insert(KART.DynamicLabels, hInvite)

    local hRemove = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRemove:SetPoint("TOPRIGHT", -38, -258)
    hRemove:SetText("|cffaaaaaa" .. (L.WU_BTN_REMOVE or "Entf.") .. "|r")
    table.insert(KART.DynamicLabels, hRemove)

    WU.bossListFrame = CreateFrame("Frame", nil, parent)
    WU.bossListFrame:SetPoint("TOPLEFT",  5, -274)
    WU.bossListFrame:SetPoint("RIGHT", parent, "RIGHT", -5, 0)
    WU.bossListFrame:SetHeight(24)
    WU.bossListFrame.rows = {}

    WU.bossListFrame.emptyLabel = WU.bossListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    WU.bossListFrame.emptyLabel:SetPoint("TOPLEFT", 6, -6)
    WU.bossListFrame.emptyLabel:SetText(L.WU_STATUS_EMPTY or "Noch kein Import.")
    WU.bossListFrame.emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    table.insert(KART.DynamicLabels, WU.bossListFrame.emptyLabel)
end

-- Invite.lua loads after MainFrame.lua, so the panel already exists here.
if KART.WoWUtilsPanel then
    WU.BuildPanel(KART.WoWUtilsPanel)
end
