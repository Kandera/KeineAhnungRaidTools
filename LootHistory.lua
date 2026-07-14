local addonName, KART = ...

KART.LH = KART.LH or {}
local LH = KART.LH

LH.filters = { player = nil, reason = nil, search = "" }

-- =====================================================================
--  Helpers
-- =====================================================================

local function IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

local function GetItemNameFromLink(link)
    if not link or link == "" then return "" end
    return link:match("%[(.-)%]") or link
end

local function GetItemStringFromLink(link)
    return IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or ""
end

local function JSONEscape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("\t", "\\t")
    return s
end

local function JSONString(key, value)
    return string.format("\"%s\":\"%s\"", key, JSONEscape(value))
end

local function JSONNumber(key, value)
    return string.format("\"%s\":%d", key, value or 0)
end

-- =====================================================================
--  RCLootCouncil-compatible JSON export
-- =====================================================================
-- Mirrors the field set/order RCLootCouncil itself produces via its "Standard JSON output"
-- history export, so the result can be pasted into any tool built to read an RCLootCouncil
-- export (e.g. wowaudit). KART doesn't track everything RCLootCouncil does though — boss,
-- instance name, vote counts, replaced-gear links and the assigning loot master aren't logged
-- by LC.LogHistory — so those fields are exported empty/zeroed rather than fabricated.
-- Respects the history window's current player/reason/search filters, same as RCLootCouncil's
-- own export (which only exports what's currently visible).
function LH.BuildRCLootCouncilJSON()
    local entries = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local matchPlayer = (not LH.filters.player) or (e.winner == LH.filters.player)
        local matchReason = (not LH.filters.reason) or ((e.reason or "") == LH.filters.reason)
        local matchSearch = true
        if LH.filters.search ~= "" then
            matchSearch = GetItemNameFromLink(e.item):lower():find(LH.filters.search, 1, true) ~= nil
        end
        if matchPlayer and matchReason and matchSearch then
            table.insert(entries, e)
        end
    end
    table.sort(entries, function(a, b) return (a.time or 0) > (b.time or 0) end)

    local objects = {}
    for i, e in ipairs(entries) do
        local itemID, subType, equipLocToken = 0, "", ""
        if IsRealItemLink(e.item) then
            local id, _, sType, eLoc = C_Item.GetItemInfoInstant(e.item)
            itemID = id or 0
            subType = sType or ""
            equipLocToken = eLoc or ""
        end

        local fields = {
            JSONString("player", e.winner),
            JSONString("date", date("%Y/%m/%d", e.time or 0)),
            JSONString("time", date("%H:%M:%S", e.time or 0)),
            JSONString("id", (e.time or 0) .. "-" .. i),
            JSONNumber("itemID", itemID),
            JSONString("itemString", GetItemStringFromLink(e.item)),
            JSONString("response", e.reason or ""),
            JSONNumber("votes", 0),
            JSONString("class", e.class or ""),
            JSONString("instance", e.difficulty or ""),
            JSONString("boss", ""),
            JSONString("gear1", ""),
            JSONString("gear2", ""),
            JSONString("responseID", "0"),
            JSONString("isAwardReason", "false"),
            JSONString("rollType", "normal"),
            JSONString("subType", subType),
            JSONString("equipLoc", equipLocToken ~= "" and (_G[equipLocToken] or "") or ""),
            JSONString("note", ""),
            JSONString("owner", ""),
            JSONString("itemName", GetItemNameFromLink(e.item)),
            JSONString("servertime", tostring(e.time or 0)),
        }
        table.insert(objects, "{" .. table.concat(fields, ",") .. "}")
    end

    return "[" .. table.concat(objects, ",") .. "]"
end

-- Hand-rolled dialog (not a StaticPopup, same reasoning as LC.ShowOfficerNoteDialog in
-- LootCouncil.lua) showing the export text in a read-only, pre-selected edit box so the user
-- can Ctrl+C it out — WoW addons have no filesystem access to write a file directly.
function LH.ShowExportDialog()
    if not LH.exportDialog then
        local f = CreateFrame("Frame", "KART_LHExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetText(KART.L.LH_EXPORT_TITLE)
        table.insert(KART.DynamicLabels, f.title)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOP", 0, -32)
        f.hint:SetText(KART.L.LH_EXPORT_HINT)
        f.hint:SetTextColor(0.6, 0.6, 0.6)
        table.insert(KART.DynamicLabels, f.hint)

        local scrollBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
        scrollBG:SetPoint("TOPLEFT", 15, -52)
        scrollBG:SetPoint("BOTTOMRIGHT", -15, 44)
        scrollBG:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        scrollBG:SetBackdropColor(0, 0, 0, 0.5)
        scrollBG:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

        local scroll = CreateFrame("ScrollFrame", "KART_LHExportScroll", scrollBG, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -22, 4)

        KART.LHExportScrollThumb = KART.StripScrollbarTextures(scroll)
        if KART.LHExportScrollThumb then KART.LHExportScrollThumb:SetSize(6, 16) end

        f.editBox = CreateFrame("EditBox", "KART_LHExportEditBox", scroll)
        f.editBox:SetWidth(420)
        f.editBox:SetMultiLine(true)
        f.editBox:SetAutoFocus(false)
        f.editBox:SetFontObject("GameFontHighlightSmall")
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Read-only: revert any edit attempt back to the export text instead of blocking input
        -- (there's no native read-only flag on EditBox), so selecting/copying still works freely.
        f.editBox:SetScript("OnTextChanged", function(self)
            if self.text and self:GetText() ~= self.text then
                self:SetText(self.text)
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(f.editBox)

        local btnClose = KART.CreateModernButton(f, CLOSE) ---@diagnostic disable-line: undefined-global
        btnClose:SetSize(120, 26)
        btnClose:SetPoint("BOTTOM", 0, 12)
        btnClose:SetScript("OnClick", function() f:Hide() end)

        LH.exportDialog = f
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    local f = LH.exportDialog
    local json = LH.BuildRCLootCouncilJSON()
    f.editBox.text = json
    f.editBox:SetText(json)
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end

function LH.GetUniquePlayers()
    local seen, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.winner and e.winner ~= "" and not seen[e.winner] then
            seen[e.winner] = true
            table.insert(list, e.winner)
        end
    end
    table.sort(list)
    return list
end

function LH.GetUniqueReasons()
    local seen, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local r = e.reason or ""
        if not seen[r] then
            seen[r] = true
            table.insert(list, r)
        end
    end
    table.sort(list)
    return list
end

StaticPopupDialogs["KART_LH_CLEAR_CONFIRM"] = {
    text = "Really clear loot history?", -- unconditionally overwritten with KART.L.LH_CLEAR_CONFIRM_TEXT below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(KART_LootHistory)
        LH.Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =====================================================================
--  Window
-- =====================================================================

function LH.CreateWindow()
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 430)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())
    f:Hide()

    -- Header
    local hdr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    hdr:SetBackdropColor(0.14, 0.14, 0.14, 1)
    hdr:EnableMouse(true)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", 10, 0)
    f.title:SetText(KART.L.LH_TITLE)
    table.insert(KART.DynamicLabels, f.title)

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

    -- Filter row: item search + player filter + reason filter + reset
    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("TOPLEFT", 10, -32)
    searchHint:SetText(KART.L.LH_SEARCH_LABEL)
    searchHint:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, searchHint)

    local searchBox = CreateFrame("EditBox", "KART_LHSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", 10, -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    searchBox:SetBackdropColor(0, 0, 0, 0.5)
    searchBox:SetTextInsets(5, 5, 0, 0)
    searchBox:SetMaxLetters(40)
    table.insert(KART.EditBoxes, searchBox)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        LH.filters.search = self:GetText():lower()
        LH.Refresh()
    end)
    f.searchBox = searchBox

    local btnPlayerFilter = KART.CreateModernButton(f, KART.L.LH_FILTER_ALL_PLAYERS)
    btnPlayerFilter:SetSize(105, 22)
    btnPlayerFilter:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    btnPlayerFilter:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(KART.L.LH_FILTER_PLAYER)
            rootDescription:CreateButton(KART.L.LH_FILTER_ALL_PLAYERS, function()
                LH.filters.player = nil
                self.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
                LH.Refresh()
            end)
            for _, name in ipairs(LH.GetUniquePlayers()) do
                rootDescription:CreateButton(name, function()
                    LH.filters.player = name
                    self.text:SetText(name)
                    LH.Refresh()
                end)
            end
        end)
    end)
    f.btnPlayerFilter = btnPlayerFilter

    local btnReasonFilter = KART.CreateModernButton(f, KART.L.LH_FILTER_ALL_REASONS)
    btnReasonFilter:SetSize(105, 22)
    btnReasonFilter:SetPoint("LEFT", btnPlayerFilter, "RIGHT", 6, 0)
    btnReasonFilter:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(KART.L.LH_FILTER_REASON)
            rootDescription:CreateButton(KART.L.LH_FILTER_ALL_REASONS, function()
                LH.filters.reason = nil
                self.text:SetText(KART.L.LH_FILTER_ALL_REASONS)
                LH.Refresh()
            end)
            for _, r in ipairs(LH.GetUniqueReasons()) do
                local label = (r == "") and KART.L.LH_NO_REASON or r
                rootDescription:CreateButton(label, function()
                    LH.filters.reason = r
                    self.text:SetText(label)
                    LH.Refresh()
                end)
            end
        end)
    end)
    f.btnReasonFilter = btnReasonFilter

    local btnReset = KART.CreateModernButton(f, KART.L.LH_BTN_RESET_FILTERS)
    btnReset:SetSize(56, 22)
    btnReset:SetPoint("LEFT", btnReasonFilter, "RIGHT", 6, 0)
    btnReset:SetScript("OnClick", function()
        LH.filters.player = nil
        LH.filters.reason = nil
        LH.filters.search = ""
        searchBox:SetText("")
        btnPlayerFilter.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
        btnReasonFilter.text:SetText(KART.L.LH_FILTER_ALL_REASONS)
        LH.Refresh()
    end)

    -- Column headers
    local hDate = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDate:SetPoint("TOPLEFT", 10, -78)
    hDate:SetText(KART.L.LH_COL_DATE)
    table.insert(KART.DynamicLabels, hDate)

    local hPlayer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPlayer:SetPoint("TOPLEFT", 80, -78)
    hPlayer:SetText(KART.L.LH_COL_PLAYER)
    table.insert(KART.DynamicLabels, hPlayer)

    local hItem = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hItem:SetPoint("TOPLEFT", 172, -78)
    hItem:SetText(KART.L.LH_COL_ITEM)
    table.insert(KART.DynamicLabels, hItem)

    local hDifficulty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDifficulty:SetPoint("TOPLEFT", 368, -78)
    hDifficulty:SetText(KART.L.LH_COL_DIFFICULTY)
    table.insert(KART.DynamicLabels, hDifficulty)

    local hReason = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hReason:SetPoint("TOPLEFT", 440, -78)
    hReason:SetText(KART.L.LH_COL_REASON)
    table.insert(KART.DynamicLabels, hReason)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.22, 0.22, 0.22, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 5, -92)
    divider:SetPoint("TOPRIGHT", -5, -92)

    -- Scrollable row area
    local scrollBG = CreateFrame("Frame", nil, f)
    scrollBG:SetPoint("TOPLEFT", 5, -95)
    scrollBG:SetPoint("BOTTOMRIGHT", -5, 34)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LHScroll", scrollBG, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT"); scrollFrame:SetPoint("BOTTOMRIGHT", -20, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(520, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end
    KART.LHScrollThumb = thumb

    f.scrollChild = scrollChild
    f.rows        = {}

    -- Empty-state label
    f.emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.emptyLabel:SetPoint("TOP", 0, -20)
    f.emptyLabel:SetText(KART.L.LH_EMPTY)
    f.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    f.emptyLabel:Hide()
    table.insert(KART.DynamicLabels, f.emptyLabel)

    -- Footer: entry count + clear button
    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countText:SetPoint("BOTTOMLEFT", 10, 12)
    f.countText:SetTextColor(0.6, 0.6, 0.6)
    table.insert(KART.DynamicLabels, f.countText)

    local btnClear = KART.CreateModernButton(f, KART.L.LH_BTN_CLEAR)
    btnClear:SetSize(140, 24)
    btnClear:SetPoint("BOTTOMRIGHT", -10, 8)
    btnClear:SetScript("OnClick", function()
        StaticPopupDialogs["KART_LH_CLEAR_CONFIRM"].text = KART.L.LH_CLEAR_CONFIRM_TEXT
        StaticPopup_Show("KART_LH_CLEAR_CONFIRM")
    end)

    local btnExport = KART.CreateModernButton(f, KART.L.LH_BTN_EXPORT_JSON, KART.L.LH_BTN_EXPORT_JSON_TIP)
    btnExport:SetSize(150, 24)
    btnExport:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMLEFT", -6, 0)
    btnExport:SetScript("OnClick", function() LH.ShowExportDialog() end)

    LH.historyWindow = f

    -- Restore saved position
    local pos = KART_Settings and KART_Settings.lcHistoryWindowPos
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    return f
end

-- =====================================================================
--  Refresh / Toggle
-- =====================================================================

function LH.Refresh()
    local f = LH.historyWindow
    if not f then return end

    local filtered = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local matchPlayer = (not LH.filters.player) or (e.winner == LH.filters.player)
        local matchReason = (not LH.filters.reason) or ((e.reason or "") == LH.filters.reason)
        local matchSearch = true
        if LH.filters.search ~= "" then
            local itemName = GetItemNameFromLink(e.item):lower()
            matchSearch = itemName:find(LH.filters.search, 1, true) ~= nil
        end
        if matchPlayer and matchReason and matchSearch then
            table.insert(filtered, e)
        end
    end

    table.sort(filtered, function(a, b) return (a.time or 0) > (b.time or 0) end)

    local total = #(KART_LootHistory or {})
    f.countText:SetText(string.format(KART.L.LH_COUNT_FORMAT, #filtered, total))
    f.emptyLabel:SetShown(#filtered == 0)

    for i, e in ipairs(filtered) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.scrollChild)
            row:SetHeight(24)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.dateText:SetPoint("LEFT", 6, 0)
            row.dateText:SetWidth(68)
            row.dateText:SetJustifyH("LEFT")

            row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.playerText:SetPoint("LEFT", 76, 0)
            row.playerText:SetWidth(88)
            row.playerText:SetJustifyH("LEFT")

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 166, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetPoint("LEFT", 188, 0)
            row.itemText:SetWidth(176)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.difficultyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.difficultyText:SetPoint("LEFT", 368, 0)
            row.difficultyText:SetWidth(68)
            row.difficultyText:SetJustifyH("LEFT")
            row.difficultyText:SetTextColor(0.7, 0.7, 0.7)

            row.reasonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.reasonText:SetPoint("LEFT", 440, 0)
            row.reasonText:SetWidth(80)
            row.reasonText:SetJustifyH("LEFT")

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if IsRealItemLink(self.itemLink) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            f.rows[i] = row
        end

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row.bg:SetColorTexture(0.1, 0.1, 0.1, i % 2 == 0 and 0.35 or 0.1)

        row.dateText:SetText(date("%d.%m %H:%M", e.time or 0))

        local nr, ng, nb = 0.8, 0.8, 0.8
        if e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class] then
            nr, ng, nb = RAID_CLASS_COLORS[e.class].r, RAID_CLASS_COLORS[e.class].g, RAID_CLASS_COLORS[e.class].b
        end
        row.playerText:SetText(e.winner)
        row.playerText:SetTextColor(nr, ng, nb)

        row.itemLink = e.item
        if IsRealItemLink(e.item) then
            local itemID = C_Item.GetItemInfoInstant(e.item)
            local icon = itemID and C_Item.GetItemIconByID(itemID)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:Show()
            row.itemText:SetText(e.item)
        else
            row.icon:Hide()
            row.itemText:SetText(e.item ~= "" and e.item or "???")
        end

        row.difficultyText:SetText((e.difficulty and e.difficulty ~= "") and e.difficulty or "—")

        if e.reason and e.reason ~= "" then
            local c = e.color
            if c then
                row.reasonText:SetText(string.format("|cff%02x%02x%02x%s|r",
                    math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), e.reason))
            else
                row.reasonText:SetText(e.reason)
            end
        else
            row.reasonText:SetText("|cff666666" .. KART.L.LH_NO_REASON .. "|r")
        end
    end

    for i = #filtered + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end
end

function LH.Toggle()
    if not LH.historyWindow then
        LH.CreateWindow()
        if KART.UpdateStyles then KART.UpdateStyles() end
    end
    if LH.historyWindow:IsShown() then
        LH.historyWindow:Hide()
    else
        LH.Refresh()
        LH.historyWindow:Show()
    end
end
