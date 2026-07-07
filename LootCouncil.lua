local addonName, KART = ...

KART.LC = KART.LC or {}
local LC = KART.LC

LC.sessionActive        = false
LC.promptedThisSession  = false
LC.votes                = {}  -- [rollID][playerShortName] = {idx, note}
LC.rollItems            = {}  -- [rollID] = itemLink
LC.CouncilNamesTable    = {}  -- shortName:lower() -> true. Populated ONLY from the raid leader's
                               -- broadcast (LC_CONFIG) — never from local settings — so a regular
                               -- raider can't self-promote by editing their own council-member list.
LC.currentWinnerShort   = nil -- short name of last announced winner
LC.raidConfig           = {}  -- authoritative config received from the raid leader: minQuality, buttonLabels, councilMembers

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

-- Vote-button labels/colors are authoritative from the raid leader (LC.raidConfig), so every
-- raider's vote index maps to the SAME label in everyone's UI. The leader always uses their own
-- local setting directly (they ARE the source of truth); everyone else uses the synced value,
-- falling back to their own local setting only when solo / not yet synced (e.g. testing).
function LC.GetButtonConfig()
    local raw
    if UnitIsGroupLeader("player") or not (LC.raidConfig and LC.raidConfig.buttonLabels) then
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or "BIS;Upgrade;Offspec;Sonstiges;Pass"
    else
        raw = LC.raidConfig.buttonLabels
    end
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

-- Only the leader's own edits are authoritative; this just re-broadcasts them to the raid.
-- (Non-leaders calling this would have no effect, since BroadcastRaidConfig no-ops for them.)
function LC.UpdateCouncilCache()
    LC.BroadcastRaidConfig()
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

-- Minimum item quality is authoritative from the raid leader, same reasoning as GetButtonConfig.
-- NOTE: this does NOT gate Auto-Pass (see OnStartLootRoll) — that stays a personal preference.
function LC.GetRaidMinQuality()
    if UnitIsGroupLeader("player") then
        return KART_Settings.lcMinQuality or 4
    end
    return (LC.raidConfig and LC.raidConfig.minQuality) or 4
end

-- Sends the leader's authoritative settings (min quality, vote-button labels, council member list)
-- to the raid so every client interprets votes/roles identically. No-ops for non-leaders.
function LC.BroadcastRaidConfig()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    local minQ     = KART_Settings.lcMinQuality or 4
    local buttons  = KART_Settings.lcButtonLabels or ""
    local council  = KART_Settings.lcCouncilMembers or ""
    SendLC("LC_CONFIG:" .. minQ .. ":" .. buttons .. ":" .. council)
end

-- Applies a raid-config broadcast from the leader (called from Core.lua CHAT_MSG_ADDON).
function LC.HandleConfig(payload)
    local minQ, buttons, council = payload:match("^(%d+):([^:]*):(.*)$")
    if not minQ then return end

    LC.raidConfig.minQuality    = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels  = buttons
    LC.raidConfig.councilMembers = council or ""

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString((council or ""):lower(), ";")) do
        local trimmed = KART.TrimString(name)
        if trimmed ~= "" then LC.CouncilNamesTable[trimmed] = true end
    end
end

-- Test mode uses a plain coloured string as a fake item; guard against SetHyperlink on non-links.
local function IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Colored label for an item quality index (0=Poor .. 5=Legendary), used by the min-quality filter UI.
function LC.QualityLabel(q)
    local name = (KART.L and KART.L["LC_QUALITY_" .. q]) or tostring(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] ---@diagnostic disable-line: undefined-global
    if c then
        return c.hex .. name .. "|r"
    end
    return name
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
    if active then LC.BroadcastRaidConfig() end
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end

function LC.CheckRaidJoin()
    if not IsInRaid() then
        LC.promptedThisSession = false
        LC.sessionActive = false
        LC.historySyncRequested = false
        return
    end
    if KART_Settings.lcModuleEnabled == false then return end

    -- Ask peers (once per raid join) for any loot-history entries logged while we weren't around.
    if not LC.historySyncRequested then
        LC.historySyncRequested = true
        LC.RequestHistorySync()
    end

    if not UnitIsGroupLeader("player") then return end

    -- Re-broadcast the authoritative config on every roster change so late joiners get it too.
    if LC.sessionActive then LC.BroadcastRaidConfig() end

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
    if KART_Settings.lcModuleEnabled == false then return end
    if not LC.sessionActive then return end

    -- Auto-Pass is a personal preference and is intentionally independent of the raid's min-quality
    -- setting (that setting only gates whether Council itself engages) — evaluated unconditionally
    -- so a raider's own choice is never overridden by the raid leader's quality threshold.
    if KART_Settings.lcAutoPass then
        RollOnLoot(rollID, 0)
    end

    -- Below the raid-wide minimum rarity: let Blizzard's own roll UI handle it, untouched.
    local _, _, _, quality = GetLootRollItemInfo(rollID)
    local minQuality = LC.GetRaidMinQuality()
    if quality and quality < minQuality then return end

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
        f:SetScript("OnDragStop",  function(self)
            self:StopMovingOrSizing()
            if KART_Settings then
                KART_Settings.lcVotePopupPos = {x = self:GetLeft(), y = self:GetTop()}
            end
        end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 10, -10)

        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.itemText:SetPoint("TOPLEFT", 10, -28)
        f.itemText:SetWidth(240)
        f.itemText:SetJustifyH("LEFT")
        f.itemText:SetWordWrap(false)

        -- FontStrings can't take mouse scripts directly; overlay a hover frame for the tooltip.
        -- SetHyperlink on an equippable item triggers Blizzard's own compare-to-equipped tooltip automatically.
        f.itemHover = CreateFrame("Frame", nil, f)
        f.itemHover:SetAllPoints(f.itemText)
        f.itemHover:EnableMouse(true)
        f.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[f.rollID]
            if not IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        f.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.timerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.timerText:SetPoint("TOPRIGHT", -10, -10)

        -- Button area sits above the note field
        f.btnArea = CreateFrame("Frame", nil, f)
        f.btnArea:SetPoint("TOPLEFT", 10, -52)
        f.btnArea:SetPoint("BOTTOMRIGHT", -10, 62)

        -- Note label
        local noteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteLabel:SetPoint("BOTTOMLEFT", 10, 42)
        noteLabel:SetText(KART.L.LC_NOTE_LABEL or "Anmerkung (optional):")
        noteLabel:SetTextColor(0.65, 0.65, 0.65)
        table.insert(KART.DynamicLabels, noteLabel)

        -- Note editbox
        local noteBox = CreateFrame("EditBox", "KART_LCNoteBox", f, "BackdropTemplate")
        noteBox:SetSize(270, 24)
        noteBox:SetPoint("BOTTOMLEFT", 10, 12)
        noteBox:SetAutoFocus(false)
        noteBox:SetMaxLetters(80)
        noteBox:SetFontObject("GameFontHighlightSmall")
        noteBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        noteBox:SetBackdropColor(0, 0, 0, 0.5)
        noteBox:SetTextInsets(5, 5, 0, 0)
        noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        table.insert(KART.EditBoxes, noteBox)
        f.noteBox = noteBox

        f.voteButtons = {}
        LC.votePopup  = f
        popup         = f

        -- Restore saved position
        local pos = KART_Settings and KART_Settings.lcVotePopupPos
        if pos and type(pos) == "table" and pos.x and pos.y then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        end
    end

    popup.rollID = rollID
    popup.voted  = false
    popup.title:SetText(KART.L.LC_VOTE_TITLE)
    popup.itemText:SetText(itemLink or "???")
    if popup.noteBox then popup.noteBox:SetText("") end

    local buttons = LC.GetButtonConfig()
    local cols    = math.min(#buttons, 3)
    local rows    = math.ceil(#buttons / cols)
    local btnW    = math.floor((270 - (cols - 1) * 6) / cols)
    local btnH    = 28
    -- 52px header + button rows + 62px note area
    popup:SetHeight(52 + rows * (btnH + 6) + 62)

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
            local note = KART.TrimString(popup.noteBox and popup.noteBox:GetText() or "")
            SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
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
--  Equipped-item helper for council panel
-- =====================================================================

local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD           = {1},
    INVTYPE_NECK           = {2},
    INVTYPE_SHOULDER       = {3},
    INVTYPE_CHEST          = {5},
    INVTYPE_ROBE           = {5},
    INVTYPE_WAIST          = {6},
    INVTYPE_LEGS           = {7},
    INVTYPE_FEET           = {8},
    INVTYPE_WRIST          = {9},
    INVTYPE_HAND           = {10},
    INVTYPE_FINGER         = {11, 12},
    INVTYPE_TRINKET        = {13, 14},
    INVTYPE_CLOAK          = {15},
    INVTYPE_WEAPON         = {16},
    INVTYPE_2HWEAPON       = {16},
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND  = {17},
    INVTYPE_SHIELD         = {17},
    INVTYPE_HOLDABLE       = {17},
    INVTYPE_RANGED         = {18},
    INVTYPE_RANGEDRIGHT    = {18},
}

-- Returns (equippedLink, equippedIlvl) for the slot matching rollItemLink on unit.
-- For two-slot items (rings, trinkets) returns the lower-ilvl piece (most likely to be replaced).
function LC.GetEquippedForUnit(unit, rollItemLink)
    if not unit or not rollItemLink then return nil, nil end
    local rollInfo = C_Item.GetItemInfo(rollItemLink)
    if not rollInfo then return nil, nil end
    local slots = EQUIP_LOC_TO_SLOT[rollInfo["equipLoc"]]
    if not slots then return nil, nil end

    local bestLink, bestIlvl
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local info = C_Item.GetItemInfo(link)
            local ilvl = info and info["itemLevel"]
            if ilvl and (not bestIlvl or ilvl < bestIlvl) then
                bestLink  = link
                bestIlvl  = ilvl
            end
        end
    end
    return bestLink, bestIlvl
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
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcCouncilPanelPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
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

    -- FontStrings can't take mouse scripts directly; overlay a hover frame for the tooltip.
    f.itemHover = CreateFrame("Frame", nil, f)
    f.itemHover:SetAllPoints(f.itemText)
    f.itemHover:EnableMouse(true)
    f.itemHover:SetScript("OnEnter", function(self)
        local link = LC.rollItems[LC.activeRollID]
        if not IsRealItemLink(link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    f.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headers
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("TOPLEFT", 10, -56)
    hName:SetText(KART.L.LC_COL_NAME)

    local hIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", 100, -56)
    hIlvl:SetText("iLvl")
    hIlvl:SetTextColor(0.5, 0.5, 0.5)

    local hVote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hVote:SetPoint("TOPLEFT", 160, -56)
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

    -- Restore saved position
    local pos = KART_Settings and KART_Settings.lcCouncilPanelPos
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end
end

function LC.RefreshCouncilRows()
    local panel = LC.councilPanel
    if not panel then return end

    local rollID  = LC.activeRollID
    local votes   = (rollID and LC.votes[rollID]) or {}
    local buttons = LC.GetButtonConfig()
    local isRaid  = IsInRaid()
    local numMem  = GetNumGroupMembers()

    local rollItem = LC.rollItems[rollID]

    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short    = fullName:match("([^%-]+)")
            local voteData = votes[short]
            -- Support both legacy number and new {idx, note} table
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit(unit, rollItem)

            -- Flag raiders who are missing KART, running an outdated version, or have disabled
            -- their own Loot Council module locally (self excluded — we never receive our own
            -- version broadcast, so PlayerVersions never has an entry for "player").
            local kartStatus
            if unit ~= "player" then
                local ver = KART.PlayerVersions and KART.PlayerVersions[short]
                local lcEnabled = KART.PlayerLCEnabled and KART.PlayerLCEnabled[short]
                if not ver then
                    kartStatus = KART.L.LC_STATUS_NO_KART
                elseif ver ~= KART.Version then
                    kartStatus = string.format(KART.L.LC_STATUS_OLD_VERSION, ver)
                elseif lcEnabled == false then
                    kartStatus = KART.L.LC_STATUS_MODULE_DISABLED
                end
            end

            table.insert(members, {
                short = short, unit = unit,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = kartStatus,
            })
        end
    end

    -- Sort: voted rows first, sorted by button index ascending; unvoted last; alpha within group
    table.sort(members, function(a, b)
        if a.voteIdx ~= b.voteIdx then
            if a.voteIdx == nil then return false end
            if b.voteIdx == nil then return true end
            return tonumber(a.voteIdx) < tonumber(b.voteIdx)
        end
        return (a.short or "") < (b.short or "")
    end)

    for i, m in ipairs(members) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel.scrollChild, "BackdropTemplate")
            row:SetHeight(24)
            -- Left-click is intentionally inert; right-click opens the assign menu.
            row:RegisterForClicks("RightButtonUp")
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 6, 0)
            row.nameText:SetWidth(88)
            row.nameText:SetJustifyH("LEFT")

            -- Icon of the item currently equipped in the matching slot
            row.equipIcon = row:CreateTexture(nil, "ARTWORK")
            row.equipIcon:SetSize(18, 18)
            row.equipIcon:SetPoint("LEFT", 96, 0)
            row.equipIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Equipped item level in the matching slot
            row.equippedText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.equippedText:SetPoint("LEFT", 118, 0)
            row.equippedText:SetWidth(34)
            row.equippedText:SetJustifyH("CENTER")

            row.voteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.voteText:SetPoint("LEFT", 156, 0)
            row.voteText:SetWidth(100)
            row.voteText:SetJustifyH("LEFT")

            -- Small dot shown when raider left a note
            row.noteIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.noteIcon:SetPoint("RIGHT", -4, 0)
            row.noteIcon:SetWidth(16)
            row.noteIcon:SetJustifyH("CENTER")

            -- Warning shown when the raider is missing KART, outdated, or has LC disabled locally
            row.warnIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.warnIcon:SetPoint("RIGHT", row.noteIcon, "LEFT", -2, 0)
            row.warnIcon:SetWidth(14)
            row.warnIcon:SetJustifyH("CENTER")

            panel.rows[i] = row
        end

        local rowIdx              = i
        local isWinner            = (m.short == LC.currentWinnerShort)
        local capturedShort       = m.short
        local capturedRoll        = rollID
        local capturedNote        = m.voteNote or ""
        local capturedEquipLink   = m.equippedLink
        local capturedEquipIlvl   = m.equippedIlvl
        local capturedVoteDef     = m.voteDef
        local capturedKartStatus  = m.kartStatus

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * 26)
        row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
        row.memberShort = m.short

        -- Winner gets green highlight; others get alternating grey
        if isWinner then
            row:SetBackdropColor(0.05, 0.25, 0.05, 0.85)
            row:SetBackdropBorderColor(0.1, 0.8, 0.1, 1)
        else
            row:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
            row:SetBackdropBorderColor(0, 0, 0, 1)
        end

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

        -- Equipped item icon + ilvl column
        if capturedEquipLink then
            local icon = C_Item.GetItemIconByID(capturedEquipLink)
            row.equipIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.equipIcon:Show()
        else
            row.equipIcon:Hide()
        end
        if capturedEquipIlvl then
            row.equippedText:SetText("|cff888888" .. capturedEquipIlvl .. "|r")
        else
            row.equippedText:SetText("|cff444444—|r")
        end

        -- Vote column
        if m.voteDef then
            row.voteText:SetText(string.format("|cff%02x%02x%02x%s|r",
                math.floor(m.voteDef.r * 255),
                math.floor(m.voteDef.g * 255),
                math.floor(m.voteDef.b * 255),
                m.voteDef.label))
        else
            row.voteText:SetText("|cff666666-|r")
        end

        -- Note indicator dot
        row.noteIcon:SetText(capturedNote ~= "" and "|cff66aaff•|r" or "")

        -- Warning indicator: missing/outdated KART or Loot Council disabled on their end
        row.warnIcon:SetText(capturedKartStatus and "|cffff4444!|r" or "")

        -- Left-click has no function. Right-click opens the assign menu.
        -- The panel never closes on its own here — only the X / Close button does.
        row:SetScript("OnClick", function(self)
            if not capturedRoll or not capturedShort then return end
            LC.ShowAssignMenu(self, capturedRoll, capturedShort, capturedVoteDef)
        end)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.3, 0.15, 0.9)
            self:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if IsRealItemLink(rollItem) then
                GameTooltip:SetHyperlink(rollItem)
                GameTooltip:AddLine(" ")
            else
                GameTooltip:SetText(rollItem or "???", 1, 1, 1)
            end
            GameTooltip:AddLine(self.memberShort or "?", nr, ng, nb)
            if capturedNote ~= "" then
                GameTooltip:AddLine("\"" .. capturedNote .. "\"", 0.7, 0.7, 0.7, true)
            end
            if capturedKartStatus then
                GameTooltip:AddLine(capturedKartStatus, 1, 0.4, 0.4, true)
            end
            GameTooltip:AddLine(KART.L.LC_TOOLTIP_RCLICK or "Right-click: assign this item", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()

            -- Side-by-side comparison: this raider's currently equipped item in the matching slot
            if capturedEquipLink then
                ShoppingTooltip1:SetOwner(GameTooltip, "ANCHOR_LEFT")     ---@diagnostic disable-line: undefined-global
                ShoppingTooltip1:SetHyperlink(capturedEquipLink)          ---@diagnostic disable-line: undefined-global
                ShoppingTooltip1:Show()                                  ---@diagnostic disable-line: undefined-global
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.memberShort == LC.currentWinnerShort then
                self:SetBackdropColor(0.05, 0.25, 0.05, 0.85)
                self:SetBackdropBorderColor(0.1, 0.8, 0.1, 1)
            else
                self:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
            GameTooltip:Hide()
            ShoppingTooltip1:Hide() ---@diagnostic disable-line: undefined-global
        end)
    end

    for i = #members + 1, #panel.rows do
        if panel.rows[i] then panel.rows[i]:Hide() end
    end
end

-- =====================================================================
--  Result announcement & winner notification
-- =====================================================================

-- reason (optional) is appended to the chat announcement, e.g. "(BIS)"; blank for no reason.
-- reason also travels in the LC_RESULT broadcast so every KART user's loot history stays in sync.
function LC.AnnounceResult(rollID, winnerName, reason)
    LC.currentWinnerShort = (winnerName ~= "NONE") and winnerName or nil

    SendLC("LC_RESULT:" .. rollID .. ":" .. winnerName .. ":" .. (reason or ""))

    if winnerName ~= "NONE" then
        local link = LC.rollItems[rollID] or ""
        local msg  = string.format(KART.L.LC_RESULT_ANNOUNCE, winnerName, link)
        if reason and reason ~= "" then
            msg = msg .. " (" .. reason .. ")"
        end
        if IsInRaid() then
            SendChatMessage(msg, "RAID")   ---@diagnostic disable-line: deprecated
        elseif IsInGroup() then
            SendChatMessage(msg, "PARTY") ---@diagnostic disable-line: deprecated
        end
    end

    if LC.councilPanel and LC.councilPanel:IsShown() then
        LC.RefreshCouncilRows()
    end
end

-- =====================================================================
--  Loot History  (SavedVariable: KART_LootHistory)
-- =====================================================================

local MAX_HISTORY_ENTRIES = 500

-- classFile is captured on a best-effort basis (only known while the raider is in range/group).
-- colorDef (optional) is the button definition {r,g,b,...} the reason came from; stored so the
-- history keeps its original color even if button labels/colors are changed later.
-- Difficulty is captured locally on whichever client logs the entry (assigner or synced receiver),
-- since every client in the same instance sees the same difficulty.
function LC.LogHistory(itemLink, winnerShort, reason, classFile, colorDef)
    KART_LootHistory = KART_LootHistory or {}
    local _, _, _, difficultyName = GetInstanceInfo()
    table.insert(KART_LootHistory, {
        time       = time(),
        item       = itemLink or "",
        winner     = winnerShort or "",
        reason     = reason or "",
        class      = classFile,
        color      = colorDef and {r = colorDef.r, g = colorDef.g, b = colorDef.b} or nil,
        difficulty = difficultyName or "",
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end

-- =====================================================================
--  Loot History catch-up sync (silent — never touches chat, addon-channel only)
-- =====================================================================
-- When someone rejoins a raid after missing a session, their KART_LootHistory is missing whatever
-- was assigned while they were away. On join, they broadcast the timestamp of their newest known
-- entry; any peer who has newer entries whispers just those back (addon channel, invisible to the
-- player) after a small random delay so several peers answering at once don't all fire at exactly
-- the same instant. Capped and time-scoped to keep this cheap even after long absences.

local HISTORY_SYNC_MAX_ENTRIES = 30
local HISTORY_SYNC_MAX_AGE     = 14 * 24 * 60 * 60 -- 14 days

function LC.RequestHistorySync()
    local latest = 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.time and e.time > latest then latest = e.time end
    end
    SendLC("LC_HIST_REQ:" .. latest)
end

-- Runs on every peer that receives a sync request; only replies (via whisper-style addon message,
-- never a visible chat message) if it actually has entries the requester is missing.
function LC.HandleHistoryRequest(payload, senderFullName)
    local sinceTime = tonumber(payload)
    if not sinceTime or not senderFullName then return end

    local cutoff = time() - HISTORY_SYNC_MAX_AGE
    local toSend = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        if (e.time or 0) > sinceTime and (e.time or 0) > cutoff then
            table.insert(toSend, e)
        end
    end
    if #toSend == 0 then return end

    table.sort(toSend, function(a, b) return (a.time or 0) < (b.time or 0) end)
    if #toSend > HISTORY_SYNC_MAX_ENTRIES then
        local trimmed = {}
        for i = #toSend - HISTORY_SYNC_MAX_ENTRIES + 1, #toSend do
            table.insert(trimmed, toSend[i])
        end
        toSend = trimmed
    end

    C_Timer.After(math.random() * 2, function()
        for _, e in ipairs(toSend) do
            local colorPacked = ""
            if e.color then
                colorPacked = string.format("%d,%d,%d",
                    math.floor(e.color.r * 255), math.floor(e.color.g * 255), math.floor(e.color.b * 255))
            end
            -- itemLink is last on purpose: item links are full of colons internally.
            local msg = string.format("LC_HIST_ENTRY:%d:%s:%s:%s:%s:%s:%s",
                e.time or 0, e.winner or "", e.difficulty or "", e.reason or "", e.class or "", colorPacked, e.item or "")
            C_ChatInfo.SendAddonMessage("KART", msg, "WHISPER", senderFullName)
        end
    end)
end

-- Runs on the requester when a peer whispers back a missing entry.
function LC.HandleHistoryEntry(payload)
    local t, winner, difficulty, reason, classFile, colorPacked, itemLink =
        payload:match("^(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
    t = tonumber(t)
    if not t or not winner then return end

    KART_LootHistory = KART_LootHistory or {}
    for _, e in ipairs(KART_LootHistory) do
        if e.time == t and e.winner == winner and e.item == itemLink then
            return -- already have it (e.g. another peer answered first)
        end
    end

    local color
    if colorPacked and colorPacked ~= "" then
        local cr, cg, cb = colorPacked:match("^(%d+),(%d+),(%d+)$")
        if cr then color = {r = tonumber(cr) / 255, g = tonumber(cg) / 255, b = tonumber(cb) / 255} end
    end

    table.insert(KART_LootHistory, {
        time       = t,
        item       = itemLink or "",
        winner     = winner,
        reason     = reason or "",
        class      = (classFile ~= "" and classFile) or nil,
        color      = color,
        difficulty = difficulty or "",
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end

-- rollID -> shortName of whoever this roll has already been awarded to (guards against accidental
-- double-assignment when the assign menu is used more than once for the same item).
LC.assignedWinners = LC.assignedWinners or {}

StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] = { ---@diagnostic disable-line: undefined-global
    text = "Bereits zugewiesen.",
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function DoAssignWinner(rollID, playerShort, reason, colorDef)
    local classFile
    local unit = LC.FindUnitForShortName(playerShort)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.AnnounceResult(rollID, playerShort, reason)
    LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef)
    LC.assignedWinners[rollID] = playerShort
end

-- Awards the item to playerShort with the given reason (may be "" for no reason) and logs it.
-- colorDef is the vote-button definition the reason was taken from (nil for "no reason").
-- If this rollID was already assigned, asks for confirmation first to avoid accidental double entries.
function LC.AssignWinner(rollID, playerShort, reason, colorDef)
    local prevWinner = LC.assignedWinners[rollID]
    if prevWinner then
        local dialog = StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] ---@diagnostic disable-line: undefined-global
        dialog.text = string.format(KART.L.LC_REASSIGN_CONFIRM_TEXT, prevWinner, playerShort)
        dialog.OnAccept = function() DoAssignWinner(rollID, playerShort, reason, colorDef) end
        StaticPopup_Show("KART_LC_REASSIGN_CONFIRM") ---@diagnostic disable-line: undefined-global
    else
        DoAssignWinner(rollID, playerShort, reason, colorDef)
    end
end

-- Resolves a raid/party unit token for a given short (unrealmed) player name.
function LC.FindUnitForShortName(shortName)
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName and fullName:match("([^%-]+)") == shortName then
            return unit
        end
    end
    return nil
end

-- Right-click menu on a council row: quick-assign, change reason, or assign without a reason.
function LC.ShowAssignMenu(anchor, rollID, playerShort, voteDef)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(playerShort)

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN, function()
            LC.AssignWinner(rollID, playerShort, voteDef and voteDef.label or "", voteDef)
        end)

        -- No callback here on purpose: this makes CreateButton return a submenu descriptor.
        local changeMenu = rootDescription:CreateButton(KART.L.LC_MENU_CHANGE_ASSIGN) ---@diagnostic disable-line: missing-parameter
        for _, def in ipairs(LC.GetButtonConfig()) do
            changeMenu:CreateButton(def.label, function()
                LC.AssignWinner(rollID, playerShort, def.label, def)
            end)
        end

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN_NO_REASON, function()
            LC.AssignWinner(rollID, playerShort, "", nil)
        end)
    end)
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

    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = LC.rollItems[rollID] or GetLootRollItemLink(rollID) or "???"
    -- Auto-Pass already runs unconditionally in OnStartLootRoll for this player's own roll,
    -- so there's nothing left to do here for that.

    if IsCouncil() then
        if not (LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID) then
            LC.ShowCouncilPanel(rollID, secs or 20)
        end
    else
        LC.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end

function LC.HandleVote(payload, senderShort)
    -- payload = "rollID:buttonIndex:note"
    local rollID, idx = payload:match("^(%d+):(%d+)")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end

    local note = payload:match("^%d+:%d+:(.*)") or ""

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderShort] = {idx = idx, note = note}

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        LC.RefreshCouncilRows()
    end
end

-- Finds the button definition (with its color) whose label matches reason, for entries received
-- from other clients where only the label string traveled over the wire, not the color itself.
function LC.ResolveColorForReason(reason)
    if not reason or reason == "" then return nil end
    for _, def in ipairs(LC.GetButtonConfig()) do
        if def.label == reason then return def end
    end
    return nil
end

function LC.HandleResult(payload)
    -- payload = "rollID:winnerName:reason"
    local rollID, winner = payload:match("^(%d+):([^:]+)")
    rollID = tonumber(rollID)
    if not rollID or not winner then return end
    local reason = payload:match("^%d+:[^:]+:(.*)$") or ""

    -- Hide vote popup if open for this roll
    if LC.votePopup and LC.votePopup:IsShown() and LC.votePopup.rollID == rollID then
        LC.votePopup:Hide()
    end

    if winner == "NONE" then return end

    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    if winner == myShort then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
    end

    -- Every KART user logs the same entry locally, so everyone's loot history stays in sync
    -- without depending on the lootmaster being online later. The assigner already logged this
    -- locally (SendAddonMessage never echoes back to its own sender), so no duplicate here.
    local classFile
    local unit = LC.FindUnitForShortName(winner)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason))
end

-- =====================================================================
--  Test Function
-- =====================================================================

-- mode: "looter" = always show vote popup; "master" = always show council panel; nil = auto-detect
function LC.StartTest(mode)
    local testRollID = 99999
    local testItem   = "|cffff8000[Sulfuras, Hand von Ragnaros] (TEST)|r"
    local buttons    = LC.GetButtonConfig()

    LC.rollItems[testRollID] = testItem
    LC.votes[testRollID]     = {}

    -- Pre-fill votes from current group members so the council panel looks populated
    if IsInGroup() then
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
                    LC.votes[testRollID][short] = {idx = voteIdx, note = ""}
                    voteIdx = (voteIdx % #buttons) + 1
                end
            end
        end
    end

    local showCouncil
    if mode == "looter" then
        showCouncil = false
    elseif mode == "master" then
        showCouncil = true
    else
        -- Auto: follow actual role
        showCouncil = IsCouncil() and IsInGroup()
    end

    if showCouncil then
        LC.ShowCouncilPanel(testRollID, KART_Settings.lcVoteSeconds or 20)
    else
        LC.ShowVotePopup(testRollID, testItem, KART_Settings.lcVoteSeconds or 20)
    end

    print("|cff00ff00KART:|r " .. KART.L.LC_TEST_STARTED)
end

-- =====================================================================
--  Settings Panel  (fills KART.LootCouncilPanel created by MainFrame.lua)
-- =====================================================================

-- Updates the role-status line inside the raid-wide settings box. Called on build, and whenever
-- the group roster changes (leadership can change without a UI interaction).
function LC.UpdateRoleStatusLabel()
    local lbl = KART.LC.RoleStatusLabel
    if not lbl then return end
    if UnitIsGroupLeader("player") then
        lbl:SetText(KART.L.LC_ROLE_STATUS_LEADER)
        lbl:SetTextColor(0.3, 0.9, 0.3)
    else
        lbl:SetText(KART.L.LC_ROLE_STATUS_MEMBER)
        lbl:SetTextColor(0.9, 0.7, 0.2)
    end
end

function LC.BuildSettingsPanel(parent)
    local L = KART.L

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText(L.LC_SETTINGS_TITLE)
    table.insert(KART.DynamicLabels, title)

    -- Master switch: fully disables the module (e.g. during testing, or to avoid clashing with
    -- another loot addon like RCLootCouncil). Nothing below still runs when this is off.
    KART.LC.CbModuleEnabled = KART.CreateSettingsCheckbox(
        parent, "KART_LCModuleEnabled",
        L.LC_SET_MODULE_ENABLED, "lcModuleEnabled", -50, nil, L.LC_DESC_MODULE_ENABLED)

    -- Personal preference — never overridden by the raid leader's settings.
    KART.LC.CbAutoPass = KART.CreateSettingsCheckbox(
        parent, "KART_LCAutoPass",
        L.LC_SET_AUTOPASS, "lcAutoPass", -80, nil, L.LC_DESC_AUTOPASS)

    -- ================= Raid-wide settings box =================
    -- Everything in here only takes effect for the raid when YOU are the raid leader; otherwise
    -- the actual raid leader's values are used automatically. Visually set apart on purpose so
    -- nobody mistakes their own tweaks here for something that affects the current raid.
    local raidBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    raidBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -120)
    raidBox:SetSize(280, 362)
    raidBox:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    raidBox:SetBackdropColor(0.5, 0.4, 0.05, 0.12)
    raidBox:SetBackdropBorderColor(0.5, 0.4, 0.05, 0.6)

    -- Title and role-status stacked on their own lines (not side-by-side) — the box is only
    -- 280px wide, too narrow to fit both texts on one line without overlapping.
    local boxTitle = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boxTitle:SetPoint("TOPLEFT", 10, -8)
    boxTitle:SetText(L.LC_RAIDWIDE_TITLE)
    boxTitle:SetTextColor(0.9, 0.75, 0.3)
    table.insert(KART.DynamicLabels, boxTitle)

    KART.LC.RoleStatusLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.RoleStatusLabel:SetPoint("TOPLEFT", 10, -22)
    KART.LC.RoleStatusLabel:SetWidth(260)
    KART.LC.RoleStatusLabel:SetJustifyH("LEFT")
    table.insert(KART.DynamicLabels, KART.LC.RoleStatusLabel)

    local boxDivider = raidBox:CreateTexture(nil, "ARTWORK")
    boxDivider:SetColorTexture(0.5, 0.4, 0.05, 0.5)
    boxDivider:SetHeight(1)
    boxDivider:SetPoint("TOPLEFT", 8, -38)
    boxDivider:SetPoint("TOPRIGHT", -8, -38)

    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 60, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    local lblButtons = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblButtons:SetPoint("TOPLEFT", 20, -100)
    lblButtons:SetText(L.LC_SET_BUTTONS)
    table.insert(KART.DynamicLabels, lblButtons)

    KART.LC.ButtonLabelEditBox = CreateFrame("EditBox", "KART_LCButtonLabels", raidBox, "BackdropTemplate")
    local eb = KART.LC.ButtonLabelEditBox
    eb:SetSize(250, 28)
    eb:SetPoint("TOPLEFT", 20, -118)
    eb:SetAutoFocus(false)
    eb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    eb:SetBackdropColor(0, 0, 0, 0.5)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetMaxLetters(128)
    table.insert(KART.EditBoxes, eb)
    eb:SetScript("OnTextChanged", function(self)
        KART_Settings.lcButtonLabels = self:GetText()
        LC.BroadcastRaidConfig()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -155)
    hint:SetText(L.LC_SET_BUTTONS_HINT)
    hint:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hint)

    -- Council member names
    local lblCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblCouncil:SetPoint("TOPLEFT", 20, -182)
    lblCouncil:SetText(L.LC_SET_COUNCIL)
    table.insert(KART.DynamicLabels, lblCouncil)

    KART.LC.CouncilMembersEditBox = CreateFrame("EditBox", "KART_LCCouncilMembers", raidBox, "BackdropTemplate")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(250, 28)
    ebC:SetPoint("TOPLEFT", 20, -200)
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

    local hintCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintCouncil:SetPoint("TOPLEFT", 20, -237)
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintCouncil)

    -- Minimum item quality that triggers the Loot Council flow (full width)
    local lblQuality = raidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblQuality:SetPoint("TOPLEFT", 20, -264)
    lblQuality:SetText(L.LC_SET_MIN_QUALITY)
    table.insert(KART.DynamicLabels, lblQuality)

    -- Placeholder text only — KART_Settings doesn't exist yet at file-load time.
    -- Core.lua's ADDON_LOADED handler syncs the real value once settings are loaded.
    KART.LC.BtnMinQuality = KART.CreateModernButton(raidBox, LC.QualityLabel(4), L.LC_DESC_MIN_QUALITY)
    KART.LC.BtnMinQuality:SetSize(250, 28)
    KART.LC.BtnMinQuality:SetPoint("TOPLEFT", 20, -282)
    KART.LC.BtnMinQuality:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.LC_SET_MIN_QUALITY)
            for q = 0, 5 do
                rootDescription:CreateButton(LC.QualityLabel(q), function()
                    KART_Settings.lcMinQuality = q
                    self.text:SetText(LC.QualityLabel(q))
                    LC.BroadcastRaidConfig()
                end)
            end
        end)
    end)

    -- Toggle session (full width) — functionally always leader-gated already; lives in the
    -- raid-wide box too since it only ever does anything for the raid leader.
    KART.LC.BtnToggleSession = KART.CreateModernButton(raidBox, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(250, 28)
    KART.LC.BtnToggleSession:SetPoint("TOPLEFT", 20, -318)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if IsInGroup() and UnitIsGroupLeader("player") then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)
    -- ================= /Raid-wide settings box =================

    LC.UpdateRoleStatusLabel()

    -- Two test buttons side by side: Looter view / Lootmaster view
    KART.LC.BtnTestLooter = KART.CreateModernButton(parent, L.LC_BTN_TEST_LOOTER, L.LC_DESC_TEST_LOOTER)
    KART.LC.BtnTestLooter:SetSize(122, 28)
    KART.LC.BtnTestLooter:SetPoint("TOPLEFT", 20, -498)
    KART.LC.BtnTestLooter:SetScript("OnClick", function() LC.StartTest("looter") end)

    KART.LC.BtnTestMaster = KART.CreateModernButton(parent, L.LC_BTN_TEST_MASTER, L.LC_DESC_TEST_MASTER)
    KART.LC.BtnTestMaster:SetSize(122, 28)
    KART.LC.BtnTestMaster:SetPoint("LEFT", KART.LC.BtnTestLooter, "RIGHT", 8, 0)
    KART.LC.BtnTestMaster:SetScript("OnClick", function() LC.StartTest("master") end)

    -- Loot history (full width)
    KART.LC.BtnHistory = KART.CreateModernButton(parent, L.LC_BTN_HISTORY, L.LC_DESC_HISTORY)
    KART.LC.BtnHistory:SetSize(255, 28)
    KART.LC.BtnHistory:SetPoint("TOPLEFT", 20, -534)
    KART.LC.BtnHistory:SetScript("OnClick", function()
        if KART.LH then KART.LH.Toggle() end
    end)
end

-- Called at file load time; KART.LootCouncilPanel is created by MainFrame.lua
if KART.LootCouncilPanel then
    LC.BuildSettingsPanel(KART.LootCouncilPanel)
end
