local addonName, KART = ...

KART.LC = KART.LC or {}
local LC = KART.LC

LC.sessionActive        = false
LC.promptedThisSession  = false
LC.votes                = {}  -- [rollID][playerShortName] = buttonIndex
LC.rollItems            = {}  -- [rollID] = itemLink
LC.CouncilNamesTable    = {}  -- shortName:lower() -> true

-- Preset accent colors per button position
local BUTTON_COLORS = {
    {r=1.0,  g=0.15, b=0.0 },
    {r=0.0,  g=0.85, b=0.25},
    {r=0.2,  g=0.4,  b=1.0 },
    {r=0.9,  g=0.75, b=0.0 },
    {r=0.55, g=0.55, b=0.55},
    {r=0.7,  g=0.3,  b=0.9 },
}

-- =====================================================================
--  Helpers
-- =====================================================================

function LC.GetButtonConfig()
    local raw = (KART_Settings and KART_Settings.lcButtonLabels) or "BIS;Upgrade;Offspec;Sonstiges;Pass"
    local parts = KART.SplitString(raw, ";")
    local result = {}
    for i, label in ipairs(parts) do
        local trimmed = KART.TrimString(label)
        if trimmed ~= "" and #result < 6 then
            local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
            table.insert(result, {label = trimmed, r = col.r, g = col.g, b = col.b})
        end
    end
    if #result == 0 then
        result = {
            {label="BIS",       r=1.0,  g=0.15, b=0.0 },
            {label="Upgrade",   r=0.0,  g=0.85, b=0.25},
            {label="Offspec",   r=0.2,  g=0.4,  b=1.0 },
            {label="Sonstiges", r=0.9,  g=0.75, b=0.0 },
            {label="Pass",      r=0.55, g=0.55, b=0.55},
        }
    end
    return result
end

function LC.UpdateCouncilCache()
    local raw = (KART_Settings and KART_Settings.lcCouncilMembers) or ""
    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString(raw:lower(), ";")) do
        local trimmed = KART.TrimString(name)
        if trimmed ~= "" then LC.CouncilNamesTable[trimmed] = true end
    end
end

local function IsCouncil()
    if UnitIsGroupLeader("player") then return true end
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or ""):lower()
    return LC.CouncilNamesTable[myShort] == true
end

local function GetChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

local function SendLC(msg)
    if IsInGroup() then
        C_ChatInfo.SendAddonMessage("KART", msg, GetChannel())
    end
end

-- =====================================================================
--  Session Prompt  (shown to RL when joining a raid)
-- =====================================================================

function LC.ShowSessionPrompt()
    if LC.sessionPromptFrame then
        LC.sessionPromptFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "KART_LCSessionPrompt", UIParent, "BackdropTemplate")
    f:SetSize(310, 115)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText(KART.L.LC_PROMPT_TITLE)

    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.desc:SetPoint("TOP", 0, -36)
    f.desc:SetText(KART.L.LC_PROMPT_TEXT)
    f.desc:SetWidth(285)
    f.desc:SetWordWrap(true)

    local btnYes = KART.CreateModernButton(f, KART.L.LC_PROMPT_YES)
    btnYes:SetSize(135, 28)
    btnYes:SetPoint("BOTTOMLEFT", 15, 12)
    btnYes:SetScript("OnClick", function()
        LC.SetSessionActive(true)
        f:Hide()
    end)

    local btnNo = KART.CreateModernButton(f, KART.L.LC_PROMPT_NO)
    btnNo:SetSize(135, 28)
    btnNo:SetPoint("BOTTOMRIGHT", -15, 12)
    btnNo:SetScript("OnClick", function()
        LC.SetSessionActive(false)
        f:Hide()
    end)

    LC.sessionPromptFrame = f
end

function LC.SetSessionActive(active)
    LC.sessionActive = active
    SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end

function LC.CheckRaidJoin()
    if not IsInRaid() then
        LC.promptedThisSession = false
        LC.sessionActive = false
        return
    end
    if not UnitIsGroupLeader("player") then return end
    if LC.promptedThisSession then return end
    LC.promptedThisSession = true
    -- Small delay so the roster is fully settled before showing the prompt
    C_Timer.After(3, function()
        if IsInRaid() and UnitIsGroupLeader("player") then
            LC.ShowSessionPrompt()
        end
    end)
end

-- =====================================================================
--  START_LOOT_ROLL handler  (called from Core.lua)
-- =====================================================================

function LC.OnStartLootRoll(rollID)
    if not LC.sessionActive then return end

    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or "???"
    LC.votes[rollID]     = LC.votes[rollID] or {}

    if UnitIsGroupLeader("player") then
        local secs = KART_Settings.lcVoteSeconds or 20
        SendLC("LC_START:" .. rollID .. ":" .. secs)
        LC.ShowCouncilPanel(rollID, secs)
    end
end

-- =====================================================================
--  Vote Popup  (shown to non-council raiders via LC_START message)
-- =====================================================================

function LC.ShowVotePopup(rollID, itemLink, seconds)
    local popup = LC.votePopup
    if not popup then
        local f = CreateFrame("Frame", "KART_LCVotePopup", UIParent, "BackdropTemplate")
        f:SetSize(290, 160)
        f:SetPoint("CENTER", 0, -80)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 10, -10)

        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.itemText:SetPoint("TOPLEFT", 10, -28)
        f.itemText:SetWidth(240)
        f.itemText:SetJustifyH("LEFT")
        f.itemText:SetWordWrap(false)

        f.timerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.timerText:SetPoint("TOPRIGHT", -10, -10)

        f.btnArea = CreateFrame("Frame", nil, f)
        f.btnArea:SetPoint("TOPLEFT", 10, -52)
        f.btnArea:SetPoint("BOTTOMRIGHT", -10, 10)

        f.voteButtons = {}
        LC.votePopup  = f
        popup         = f
    end

    popup.rollID = rollID
    popup.voted  = false
    popup.title:SetText(KART.L.LC_VOTE_TITLE)
    popup.itemText:SetText(itemLink or "???")

    local buttons = LC.GetButtonConfig()
    local cols    = math.min(#buttons, 3)
    local rows    = math.ceil(#buttons / cols)
    local btnW    = math.floor((270 - (cols - 1) * 6) / cols)
    local btnH    = 28
    popup:SetHeight(60 + rows * (btnH + 6) + 8)

    for i = #buttons + 1, #popup.voteButtons do
        if popup.voteButtons[i] then popup.voteButtons[i]:Hide() end
    end

    for i, def in ipairs(buttons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        local btn = popup.voteButtons[i]
        if not btn then
            btn = KART.CreateModernButton(popup.btnArea, def.label)
            popup.voteButtons[i] = btn
        else
            btn:Show()
            btn.text:SetText(def.label)
        end
        btn:SetSize(btnW, btnH)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", popup.btnArea, "TOPLEFT", col * (btnW + 6), -row * (btnH + 6))
        btn:SetBackdropBorderColor(def.r, def.g, def.b, 0.9)

        local capturedIdx    = i
        local capturedRollID = rollID
        btn:SetScript("OnClick", function()
            if popup.voted or popup.rollID ~= capturedRollID then return end
            popup.voted = true
            SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx)
            popup.title:SetText(KART.L.LC_VOTED)
            C_Timer.After(2.5, function()
                if popup.rollID == capturedRollID then popup:Hide() end
            end)
        end)
    end

    local remaining = seconds
    popup.timerText:SetText(remaining .. "s")
    if popup.timerTicker then popup.timerTicker:Cancel() end
    popup.timerTicker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if remaining <= 0 then
            popup.timerTicker:Cancel()
            if not popup.voted then popup:Hide() end
        else
            popup.timerText:SetText(remaining .. "s")
        end
    end, seconds)

    popup:Show()
end

-- =====================================================================
--  Council Panel  (shown to leader & assistants)
-- =====================================================================

function LC.ShowCouncilPanel(rollID, seconds)
    if not LC.councilPanel then LC.CreateCouncilPanel() end
    LC.activeRollID = rollID
    local panel = LC.councilPanel

    panel.itemText:SetText(LC.rollItems[rollID] or "???")
    panel.title:SetText(KART.L.LC_PANEL_TITLE)
    LC.RefreshCouncilRows()

    local remaining = seconds
    panel.timerText:SetText(remaining .. "s")
    if panel.timerTicker then panel.timerTicker:Cancel() end
    panel.timerTicker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if remaining <= 0 then
            panel.timerTicker:Cancel()
            panel.timerText:SetText(KART.L.LC_VOTING_DONE)
        else
            panel.timerText:SetText(remaining .. "s")
        end
    end, seconds)

    panel:Show()
end

function LC.CreateCouncilPanel()
    local f = CreateFrame("Frame", "KART_LCCouncilPanel", UIParent, "BackdropTemplate")
    f:SetSize(330, 440)
    f:SetPoint("CENTER", 220, 0)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, f:GetName())

    -- Header
    local hdr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    hdr:SetBackdropColor(0.14, 0.14, 0.14, 1)
    hdr:EnableMouse(true)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", 10, 0)

    f.timerText = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.timerText:SetPoint("RIGHT", -32, 0)

    local closeBtn = CreateFrame("Button", nil, hdr)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    closeBtn.text:SetPoint("CENTER", 0, 1)
    closeBtn.text:SetText("×")
    closeBtn:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 0, 0) end)
    closeBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Item display
    f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemText:SetPoint("TOPLEFT", 10, -36)
    f.itemText:SetWidth(310)
    f.itemText:SetJustifyH("LEFT")
    f.itemText:SetWordWrap(false)

    -- Column headers
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("TOPLEFT", 10, -56)
    hName:SetText(KART.L.LC_COL_NAME)

    local hVote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hVote:SetPoint("TOPLEFT", 185, -56)
    hVote:SetText(KART.L.LC_COL_VOTE)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.22, 0.22, 0.22, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 5, -67)
    divider:SetPoint("TOPRIGHT", -5, -67)

    -- Scrollable row area
    local scrollBG = CreateFrame("Frame", nil, f)
    scrollBG:SetPoint("TOPLEFT", 5, -70)
    scrollBG:SetPoint("BOTTOMRIGHT", -5, 48)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LCCouncilScroll", scrollBG, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT"); scrollFrame:SetPoint("BOTTOMRIGHT", -20, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(285, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end

    f.scrollChild = scrollChild
    f.rows        = {}

    -- Bottom: No Winner / Close
    local btnNoWinner = KART.CreateModernButton(f, KART.L.LC_BTN_NO_WINNER)
    btnNoWinner:SetSize(150, 28)
    btnNoWinner:SetPoint("BOTTOMLEFT", 10, 10)
    btnNoWinner:SetScript("OnClick", function()
        if LC.activeRollID then LC.AnnounceResult(LC.activeRollID, "NONE") end
        f:Hide()
    end)

    local btnClose = KART.CreateModernButton(f, KART.L.LC_BTN_CANCEL)
    btnClose:SetSize(150, 28)
    btnClose:SetPoint("BOTTOMRIGHT", -10, 10)
    btnClose:SetScript("OnClick", function() f:Hide() end)

    LC.councilPanel = f
end

function LC.RefreshCouncilRows()
    local panel = LC.councilPanel
    if not panel then return end

    local rollID  = LC.activeRollID
    local votes   = (rollID and LC.votes[rollID]) or {}
    local buttons = LC.GetButtonConfig()
    local isRaid  = IsInRaid()
    local numMem  = GetNumGroupMembers()

    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short   = fullName:match("([^%-]+)")
            local voteIdx = votes[short]
            local voteDef = voteIdx and buttons[voteIdx]
            table.insert(members, {short=short, unit=unit, voteIdx=voteIdx, voteDef=voteDef})
        end
    end

    table.sort(members, function(a, b)
        local av = a.voteIdx ~= nil
        local bv = b.voteIdx ~= nil
        if av ~= bv then return av end
        return (a.short or "") < (b.short or "")
    end)

    for i, m in ipairs(members) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel.scrollChild, "BackdropTemplate")
            row:SetHeight(24)
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 6, 0)
            row.nameText:SetWidth(170)
            row.nameText:SetJustifyH("LEFT")

            row.voteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.voteText:SetPoint("LEFT", 185, 0)
            row.voteText:SetWidth(95)
            row.voteText:SetJustifyH("LEFT")

            panel.rows[i] = row
        end

        local rowIdx = i
        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * 26)
        row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
        row:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
        row.memberShort = m.short

        -- Class colour for name
        local nr, ng, nb = 0.8, 0.8, 0.8
        if m.unit then
            local _, classFile = UnitClass(m.unit)
            if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                nr = RAID_CLASS_COLORS[classFile].r
                ng = RAID_CLASS_COLORS[classFile].g
                nb = RAID_CLASS_COLORS[classFile].b
            end
        end
        row.nameText:SetText(m.short or "?")
        row.nameText:SetTextColor(nr, ng, nb)

        if m.voteDef then
            row.voteText:SetText(string.format("|cff%02x%02x%02x%s|r",
                math.floor(m.voteDef.r * 255),
                math.floor(m.voteDef.g * 255),
                math.floor(m.voteDef.b * 255),
                m.voteDef.label))
        else
            row.voteText:SetText("|cff666666-|r")
        end

        local capturedShort = m.short
        local capturedRoll  = rollID
        local capturedNR, capturedNG, capturedNB = nr, ng, nb
        row:SetScript("OnClick", function()
            if capturedRoll and capturedShort then
                LC.AnnounceResult(capturedRoll, capturedShort)
                panel:Hide()
            end
        end)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.3, 0.15, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.memberShort or "?", capturedNR, capturedNG, capturedNB)
            GameTooltip:AddLine(KART.L.LC_TOOLTIP_WINNER, 0.9, 0.8, 0.1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
            GameTooltip:Hide()
        end)
    end

    for i = #members + 1, #panel.rows do
        if panel.rows[i] then panel.rows[i]:Hide() end
    end
end

-- =====================================================================
--  Result announcement & winner notification
-- =====================================================================

function LC.AnnounceResult(rollID, winnerName)
    SendLC("LC_RESULT:" .. rollID .. ":" .. winnerName)

    if winnerName ~= "NONE" then
        local link = LC.rollItems[rollID] or ""
        local msg  = string.format(KART.L.LC_RESULT_ANNOUNCE, winnerName, link)
        if IsInRaid()      then SendChatMessage(msg, "RAID")
        elseif IsInGroup() then SendChatMessage(msg, "PARTY") end
    end
end

function LC.ShowWinnerNotification(itemLink)
    if not LC.winnerFrame then
        local f = CreateFrame("Frame", "KART_LCWinnerFrame", UIParent, "BackdropTemplate")
        f:SetSize(290, 75)
        f:SetPoint("CENTER", 0, 160)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.04, 0.18, 0.04, 0.97)
        f:SetBackdropBorderColor(0.1, 0.9, 0.1, 1)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -13)
        f.title:SetTextColor(0.1, 1, 0.1)

        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.itemText:SetPoint("CENTER", 0, -10)
        f.itemText:SetWidth(270)

        LC.winnerFrame = f
    end

    local f = LC.winnerFrame
    f.title:SetText(KART.L.LC_YOU_WIN)
    f.itemText:SetText(itemLink or "")
    f:Show()
    if f.hideTimer then f.hideTimer:Cancel() end
    f.hideTimer = C_Timer.NewTimer(8, function() f:Hide() end)
end

-- =====================================================================
--  Addon Message Handlers  (called from Core.lua CHAT_MSG_ADDON)
-- =====================================================================

function LC.HandleActive(value)
    LC.sessionActive = (value == "1")
end

function LC.HandleStart(payload)
    -- payload = "rollID:seconds"
    local rollID, secs = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID then return end

    LC.votes[rollID]    = LC.votes[rollID] or {}
    LC.rollItems[rollID] = LC.rollItems[rollID] or GetLootRollItemLink(rollID) or "???"

    if IsCouncil() then
        if not (LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID) then
            LC.ShowCouncilPanel(rollID, secs or 20)
        end
    else
        LC.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end

function LC.HandleVote(payload, senderShort)
    -- payload = "rollID:buttonIndex"
    local rollID, idx = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderShort] = idx

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        LC.RefreshCouncilRows()
    end
end

function LC.HandleResult(payload)
    -- payload = "rollID:winnerName"
    local rollID, winner = payload:match("^(%d+):(.+)$")
    rollID = tonumber(rollID)
    if not rollID then return end

    -- Hide vote popup if open for this roll
    if LC.votePopup and LC.votePopup:IsShown() and LC.votePopup.rollID == rollID then
        LC.votePopup:Hide()
    end

    if winner == "NONE" then return end

    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""

    if winner == myShort then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
    elseif KART_Settings.lcAutoPass then
        RollOnLoot(rollID, 0)
    end
end

-- =====================================================================
--  Test Function
-- =====================================================================

function LC.StartTest()
    local testRollID = 99999
    local testItem   = "|cffff8000[Sulfuras, Hand von Ragnaros] (TEST)|r"
    local buttons    = LC.GetButtonConfig()

    LC.rollItems[testRollID] = testItem
    LC.votes[testRollID]     = {}

    if IsInGroup() then
        -- Pre-fill votes for current group members so council panel looks populated
        local isRaid  = IsInRaid()
        local numMem  = GetNumGroupMembers()
        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
        local voteIdx = 1
        for i = 1, numMem do
            local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
            local name = UnitName(unit)
            if name then
                local short = name:match("([^%-]+)")
                if short and short ~= myShort then
                    LC.votes[testRollID][short] = voteIdx
                    voteIdx = (voteIdx % #buttons) + 1
                end
            end
        end

        if IsCouncil() then
            LC.ShowCouncilPanel(testRollID, KART_Settings.lcVoteSeconds or 20)
        else
            LC.ShowVotePopup(testRollID, testItem, KART_Settings.lcVoteSeconds or 20)
        end
    else
        -- Solo: only vote popup makes sense (no group roster for council panel)
        LC.ShowVotePopup(testRollID, testItem, KART_Settings.lcVoteSeconds or 20)
    end

    print("|cff00ff00KART:|r " .. KART.L.LC_TEST_STARTED)
end

-- =====================================================================
--  Settings Panel  (fills KART.LootCouncilPanel created by MainFrame.lua)
-- =====================================================================

function LC.BuildSettingsPanel(parent)
    local L = KART.L

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(L.LC_SETTINGS_TITLE)
    table.insert(KART.DynamicLabels, title)

    KART.LC.CbAutoPass = KART.CreateSettingsCheckbox(
        parent, "KART_LCAutoPass",
        L.LC_SET_AUTOPASS, "lcAutoPass", -60, nil, L.LC_DESC_AUTOPASS)

    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        parent, L.LC_SET_VOTE_TIMER, 5, 60, "lcVoteSeconds",
        -110, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    local lblButtons = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblButtons:SetPoint("TOPLEFT", 20, -158)
    lblButtons:SetText(L.LC_SET_BUTTONS)
    table.insert(KART.DynamicLabels, lblButtons)

    KART.LC.ButtonLabelEditBox = CreateFrame("EditBox", "KART_LCButtonLabels", parent, "BackdropTemplate")
    local eb = KART.LC.ButtonLabelEditBox
    eb:SetSize(255, 28)
    eb:SetPoint("TOPLEFT", 20, -176)
    eb:SetAutoFocus(false)
    eb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    eb:SetBackdropColor(0, 0, 0, 0.5)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetMaxLetters(128)
    table.insert(KART.EditBoxes, eb)
    eb:SetScript("OnTextChanged", function(self) KART_Settings.lcButtonLabels = self:GetText() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -213)
    hint:SetText(L.LC_SET_BUTTONS_HINT)
    hint:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hint)

    -- Council member names
    local lblCouncil = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblCouncil:SetPoint("TOPLEFT", 20, -240)
    lblCouncil:SetText(L.LC_SET_COUNCIL)
    table.insert(KART.DynamicLabels, lblCouncil)

    KART.LC.CouncilMembersEditBox = CreateFrame("EditBox", "KART_LCCouncilMembers", parent, "BackdropTemplate")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(255, 28)
    ebC:SetPoint("TOPLEFT", 20, -258)
    ebC:SetAutoFocus(false)
    ebC:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    ebC:SetBackdropColor(0, 0, 0, 0.5)
    ebC:SetTextInsets(5, 5, 0, 0)
    ebC:SetMaxLetters(255)
    table.insert(KART.EditBoxes, ebC)
    ebC:SetScript("OnTextChanged", function(self)
        KART_Settings.lcCouncilMembers = self:GetText()
        LC.UpdateCouncilCache()
    end)
    ebC:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hintCouncil = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintCouncil:SetPoint("TOPLEFT", 20, -295)
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintCouncil)

    -- Toggle session (compact) + Test button side by side
    KART.LC.BtnToggleSession = KART.CreateModernButton(parent, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(122, 28)
    KART.LC.BtnToggleSession:SetPoint("TOPLEFT", 20, -325)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)

    KART.LC.BtnTest = KART.CreateModernButton(parent, L.LC_BTN_TEST, L.LC_DESC_TEST)
    KART.LC.BtnTest:SetSize(122, 28)
    KART.LC.BtnTest:SetPoint("LEFT", KART.LC.BtnToggleSession, "RIGHT", 8, 0)
    KART.LC.BtnTest:SetScript("OnClick", function() LC.StartTest() end)
end

-- Called at file load time; KART.LootCouncilPanel is created by MainFrame.lua
if KART.LootCouncilPanel then
    LC.BuildSettingsPanel(KART.LootCouncilPanel)
end
