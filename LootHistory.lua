local addonName, KART = ...

KART.LH = KART.LH or {}
local LH = KART.LH
local LC = KART.LC

LH.filters = { player = nil, reason = nil, search = "" }

-- =====================================================================
--  Helpers
-- =====================================================================

local function GetItemNameFromLink(link)
    if not link or link == "" then return "" end
    return link:match("%[(.-)%]") or link
end

-- Applies the window's current player/reason/search filters and returns the matching
-- entries newest-first. Shared by the window renderer and the JSON export, which must
-- always agree on what "currently visible" means.
local function GetFilteredEntries()
    local filtered = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        -- filters.player holds a stable id: a winnerKey (GUID) for modern entries, or a legacy
        -- display name. Match either so switching filters catches every entry for that person.
        local matchPlayer = (not LH.filters.player)
            or (e.winnerKey and e.winnerKey ~= "" and e.winnerKey == LH.filters.player)
            or (e.winner == LH.filters.player)
        local matchReason = (not LH.filters.reason) or ((e.reason or "") == LH.filters.reason)
        local matchSearch = true
        if LH.filters.search ~= "" then
            matchSearch = KART.CaseFold(GetItemNameFromLink(e.item)):find(LH.filters.search, 1, true) ~= nil
        end
        if matchPlayer and matchReason and matchSearch then
            table.insert(filtered, e)
        end
    end
    table.sort(filtered, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return filtered
end

local function JSONEscape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    -- Escape any remaining control characters (U+0000–U+001F) as \u00XX so the output is always
    -- valid JSON even if an item name or reason ever contains a stray control byte.
    s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", string.byte(c)) end)
    return s
end

local function JSONString(key, value)
    return string.format("\"%s\":\"%s\"", key, JSONEscape(value))
end

local function JSONNumber(key, value)
    return string.format("\"%s\":%d", key, value or 0)
end

-- Canonical English difficulty names for JSON export, keyed by Blizzard difficultyID (see
-- GetInstanceInfo/GetDifficultyInfo). The on-screen column stays localized; only the export is
-- normalized to English so a mixed-language raid still produces one consistent "instance" field.
-- Entries logged before difficultyID was tracked fall back to the stored string. History sync now
-- carries the difficultyID over the wire, so backfilled entries are English-canonical too.
local DIFFICULTY_EN = {
    [1]  = "Normal",          -- 5-player dungeon
    [2]  = "Heroic",          -- 5-player dungeon
    [3]  = "10 Player",       -- legacy raid
    [4]  = "25 Player",       -- legacy raid
    [5]  = "10 Player (Heroic)",
    [6]  = "25 Player (Heroic)",
    [7]  = "LFR",             -- legacy raid finder
    [8]  = "Mythic Keystone",
    [9]  = "40 Player",       -- legacy raid
    [14] = "Normal",          -- raid
    [15] = "Heroic",          -- raid
    [16] = "Mythic",          -- raid
    [17] = "LFR",             -- raid finder
    [23] = "Mythic",          -- 5-player dungeon
    [24] = "Timewalking",     -- dungeon
    [33] = "Timewalking",     -- raid
    [208] = "Delve",
}

-- Canonical English slot names for JSON export, keyed by INVTYPE_* token. Same reasoning as
-- DIFFICULTY_EN above: _G[token] would return the WoW *client-locale* slot name ("Kopf" on a
-- German client), so a mixed-language raid would produce inconsistent "equipLoc" fields. Mapping
-- the locale-independent token to its English name keeps the export English-canonical, matching
-- what an English client's RCLootCouncil export would contain.
local INVTYPE_EN = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_BODY = "Shirt",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back",
    INVTYPE_WEAPON = "One-Hand",
    INVTYPE_SHIELD = "Off Hand",
    INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held In Off-hand",
    INVTYPE_RANGED = "Ranged",
    INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Thrown",
    INVTYPE_RELIC = "Relic",
    INVTYPE_TABARD = "Tabard",
}

-- Canonical English item subtype for export, keyed by numeric classID/subClassID — locale-
-- independent, unlike C_Item.GetItemInfoInstant's localized itemSubType ("Platte" on a German
-- client). Same English-canonical reasoning as DIFFICULTY_EN/INVTYPE_EN. Covers armor and weapons
-- (the item classes that pass through Loot Council); anything else exports an empty subType rather
-- than leaking a localized name.
local SUBTYPE_EN = {
    [4] = { -- Armor
        [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate",
        [5] = "Cosmetic", [6] = "Shield",
    },
    [2] = { -- Weapon
        [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace",
        [6] = "Polearm", [7] = "Sword", [8] = "Sword", [9] = "Warglaive", [10] = "Staff",
        [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand",
        [20] = "Fishing Pole",
    },
}

local function SubTypeExport(classID, subClassID)
    local byClass = classID and SUBTYPE_EN[classID]
    return (byClass and subClassID and byClass[subClassID]) or ""
end

-- Localized difficulty name for on-screen display; falls back to the stored string for pre-id entries.
function LH.DifficultyDisplay(e)
    if e.difficultyID then
        local name = GetDifficultyInfo(e.difficultyID)
        if name and name ~= "" then return name end
    end
    return e.difficulty
end

-- Canonical English difficulty name for export; falls back to the stored (possibly localized) string.
function LH.DifficultyExport(e)
    return (e.difficultyID and DIFFICULTY_EN[e.difficultyID]) or e.difficulty or ""
end

-- =====================================================================
--  RCLootCouncil-compatible JSON export
-- =====================================================================
-- Mirrors the field set/order RCLootCouncil itself produces via its "Standard JSON output"
-- history export, so the result can be pasted into any tool built to read an RCLootCouncil
-- export (e.g. wowaudit). KART doesn't track everything RCLootCouncil does though — boss,
-- instance name, vote counts, replaced-gear links and the assigning loot master aren't logged
-- by LH.LogHistory — so those fields are exported empty/zeroed rather than fabricated.
-- Respects the history window's current player/reason/search filters, same as RCLootCouncil's
-- own export (which only exports what's currently visible).
function LH.BuildRCLootCouncilJSON()
    local entries = GetFilteredEntries()

    local objects = {}
    for i, e in ipairs(entries) do
        local itemID, subType, equipLocToken = 0, "", ""
        if KART.IsRealItemLink(e.item) then
            local id, _, _, eLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(e.item)
            itemID = id or 0
            subType = SubTypeExport(classID, subClassID)
            equipLocToken = eLoc or ""
        end

        local fields = {
            JSONString("player", e.winner),
            JSONString("date", date("%Y/%m/%d", e.time or 0)),
            JSONString("time", date("%H:%M:%S", e.time or 0)),
            JSONString("id", (e.time or 0) .. "-" .. i),
            JSONNumber("itemID", itemID),
            JSONString("itemString", (KART.GetItemString(e.item) or "")),
            JSONString("response", e.reason or ""),
            JSONNumber("votes", 0),
            JSONString("class", e.class or ""),
            JSONString("instance", LH.DifficultyExport(e)),
            JSONString("boss", ""),
            JSONString("gear1", ""),
            JSONString("gear2", ""),
            JSONString("responseID", "0"),
            JSONString("isAwardReason", "false"),
            JSONString("rollType", "normal"),
            JSONString("subType", subType),
            JSONString("equipLoc", (equipLocToken ~= "" and INVTYPE_EN[equipLocToken]) or ""),
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
        KART.RegisterStrataFrame(f, true)
        KART.ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetText(KART.L.LH_EXPORT_TITLE)
        table.insert(KART.DynamicLabels, f.title)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOP", 0, -32)
        f.hint:SetText(KART.L.LH_EXPORT_HINT)
        f.hint:SetTextColor(0.6, 0.6, 0.6)
        table.insert(KART.DynamicLabels, f.hint)

        -- Same inset/border colors as KART.CreateStyledEditBox (the multi-line export box lives
        -- inside a ScrollFrame, so the visual box is this frame); focus accent mirrored below.
        local scrollBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
        scrollBG:SetPoint("TOPLEFT", 15, -52)
        scrollBG:SetPoint("BOTTOMRIGHT", -15, 44)
        scrollBG:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        scrollBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
        scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
        KART.ApplyRoundedMask(scrollBG, KART.Theme.CORNER_RADIUS_LG)

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
        f.editBox:SetScript("OnEditFocusGained", function()
            local r, g, b = KART.Theme.AccentColor()
            scrollBG:SetBackdropBorderColor(r, g, b, 1)
        end)
        f.editBox:SetScript("OnEditFocusLost", function()
            scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
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

-- Returns the distinct winners as { id, label } entries. `id` is the stable identity (winnerKey
-- GUID when present, else the stored display name for legacy entries) and is what the filter stores;
-- `label` is the current resolved display — NSRT nickname / short name via Identity.ResolveDisplayName
-- — so the same person's entries logged under different display names collapse to one filter option.
function LH.GetUniquePlayers()
    local seen, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local id = (e.winnerKey and e.winnerKey ~= "" and e.winnerKey) or e.winner
        if id and id ~= "" and not seen[id] then
            seen[id] = true
            local label = e.winner
            if e.winnerKey and e.winnerKey ~= "" then
                label = KART.Identity.ResolveDisplayName(e.winnerKey) or e.winner
            end
            table.insert(list, { id = id, label = label })
        end
    end
    table.sort(list, function(a, b) return (a.label or "") < (b.label or "") end)
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

KART.RegisterStaticPopup("KART_LH_CLEAR_CONFIRM", {
    text = "Really clear loot history?", -- unconditionally overwritten with KART.L.LH_CLEAR_CONFIRM_TEXT below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(KART_LootHistory)
        LH.Refresh()
    end,
})

-- =====================================================================
--  Window
-- =====================================================================

function LH.CreateWindow()
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 430)
    f:SetPoint("CENTER")
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())
    f:Hide()

    -- Header zone: title on the artwork with an accent line below, matching the main window
    -- (the old flat gray header bar is gone; hdr survives as an invisible layout strip for
    -- the title and close button).
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    hdr:RegisterForDrag("LeftButton")
    hdr:SetScript("OnDragStart", function() f:StartMoving() end)
    hdr:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = f:GetLeft(), y = f:GetTop()}
        end
    end)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", 16, 0)
    f.title:SetText(KART.L.LH_TITLE)
    table.insert(KART.DynamicLabels, f.title)
    KART.CreateHeaderLine(f, -28)

    local closeBtn = KART.CreateHeaderIconButton(hdr, "×", function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", -4, 0)

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
    KART.ApplyRoundedMask(searchBox, KART.Theme.CORNER_RADIUS_SM)
    table.insert(KART.EditBoxes, searchBox)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        LH.filters.search = KART.CaseFold(self:GetText())
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
            for _, p in ipairs(LH.GetUniquePlayers()) do
                rootDescription:CreateButton(p.label, function()
                    LH.filters.player = p.id
                    self.text:SetText(p.label)
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
    -- Pagination fits every page to the visible area, so there's no inner scroll — disable the
    -- mouse wheel so it can't drag the (oversized, vestigial) child up into empty space.
    scrollFrame:EnableMouseWheel(false)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(520, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end
    KART.LHScrollThumb = thumb

    f.scrollChild = scrollChild
    f.scrollFrame = scrollFrame
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

    -- Pagination controls, anchored just left of the export button and growing leftward, so they
    -- never collide with the right-hand buttons regardless of their localized widths. The list uses
    -- a fit-to-window page size (see LH.Refresh) and so never scrolls — Prev/Next page through it.
    f.nextPageBtn = KART.CreateModernButton(f, ">")
    f.nextPageBtn:SetSize(24, 22)
    f.nextPageBtn:SetPoint("RIGHT", btnExport, "LEFT", -10, -1)
    f.nextPageBtn:SetScript("OnClick", function()
        LH.currentPage = (LH.currentPage or 1) + 1
        LH.Refresh() -- clamped inside Refresh
    end)

    f.pageIndicator = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pageIndicator:SetSize(70, 14)
    f.pageIndicator:SetJustifyH("CENTER")
    f.pageIndicator:SetPoint("RIGHT", f.nextPageBtn, "LEFT", -6, 1)
    f.pageIndicator:SetTextColor(0.6, 0.6, 0.6)

    f.prevPageBtn = KART.CreateModernButton(f, "<")
    f.prevPageBtn:SetSize(24, 22)
    f.prevPageBtn:SetPoint("RIGHT", f.pageIndicator, "LEFT", -6, -1)
    f.prevPageBtn:SetScript("OnClick", function()
        LH.currentPage = math.max(1, (LH.currentPage or 1) - 1)
        LH.Refresh()
    end)

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

    local filtered = GetFilteredEntries()

    local total = #(KART_LootHistory or {})
    f.countText:SetText(string.format(KART.L.LH_COUNT_FORMAT, #filtered, total))
    f.emptyLabel:SetShown(#filtered == 0)

    -- Fit-to-window page size from the visible row area (26px stride) so the list never needs an
    -- inner scrollbar. Cached once the frame has a real height (the first Refresh runs pre-Show, so
    -- GetHeight is 0 then); 11 until then — its true value at the default window size, so even that
    -- first pre-show render is already correct.
    if (not f.pageSize) and f.scrollFrame then
        local h = f.scrollFrame:GetHeight()
        if h and h > 0 then f.pageSize = math.max(1, math.floor(h / 26)) end
    end
    local pageSize = f.pageSize or 11

    -- Snap back to the first (newest) page whenever the active filter/search changes; Prev/Next move
    -- within the same result set and leave the signature untouched, so they don't trigger a reset.
    local sig = (LH.filters.player or "") .. "\1" .. (LH.filters.reason or "") .. "\1" .. (LH.filters.search or "")
    if sig ~= LH._lastFilterSig then
        LH.currentPage = 1
        LH._lastFilterSig = sig
    end

    local totalPages = math.max(1, math.ceil(#filtered / pageSize))
    LH.currentPage = math.min(math.max(LH.currentPage or 1, 1), totalPages)
    local startIdx = (LH.currentPage - 1) * pageSize

    if totalPages > 1 then
        f.pageIndicator:SetText(string.format(KART.L.LH_PAGE_INDICATOR, LH.currentPage, totalPages))
        f.pageIndicator:Show()
        f.prevPageBtn:Show(); f.nextPageBtn:Show()
        local pc = (LH.currentPage > 1) and 1 or 0.35
        f.prevPageBtn.text:SetTextColor(pc, pc, pc)
        local nc = (LH.currentPage < totalPages) and 1 or 0.35
        f.nextPageBtn.text:SetTextColor(nc, nc, nc)
    else
        f.pageIndicator:Hide()
        f.prevPageBtn:Hide(); f.nextPageBtn:Hide()
    end

    local pageCount = 0
    for i = 1, pageSize do
        local e = filtered[startIdx + i]
        if not e then break end
        pageCount = i
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
                if KART.IsRealItemLink(self.itemLink) then
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
        local lr, lg, lb = KART.GetRowStripeColor()
        row.bg:SetColorTexture(lr, lg, lb, i % 2 == 0 and 0.35 or 0.1)

        row.dateText:SetText(date("%d.%m %H:%M", e.time or 0))

        local nr, ng, nb = 0.8, 0.8, 0.8
        if e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class] then
            nr, ng, nb = RAID_CLASS_COLORS[e.class].r, RAID_CLASS_COLORS[e.class].g, RAID_CLASS_COLORS[e.class].b
        end
        row.playerText:SetText(e.winner)
        row.playerText:SetTextColor(nr, ng, nb)

        row.itemLink = e.item
        if KART.IsRealItemLink(e.item) then
            local itemID = C_Item.GetItemInfoInstant(e.item)
            local icon = itemID and C_Item.GetItemIconByID(itemID)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:Show()
            row.itemText:SetText(e.item)
        else
            row.icon:Hide()
            row.itemText:SetText(e.item ~= "" and e.item or "???")
        end

        local diffName = LH.DifficultyDisplay(e)
        row.difficultyText:SetText((diffName and diffName ~= "") and diffName or "—")

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

    for i = pageCount + 1, #f.rows do
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
        LH.currentPage = 1 -- always open on the first (newest) page
        LH.Refresh()
        LH.historyWindow:Show()
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
-- winnerKey is the stable identity key (GUID) for the winner; winnerDisplayName is only for display.
-- Storing the key lets the catch-up sync dedup two clients' entries for the same award even when
-- their display names differ (NSRT nickname on one, character short name on another).
function LH.LogHistory(itemLink, winnerDisplayName, reason, classFile, colorDef, rollID, winnerKey)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- Guards against double-logging the same win if a redelivered/duplicate LC_RESULT addon
    -- message ever reaches this client twice (HandleResult has no dedup of its own, unlike the
    -- history catch-up sync path in HandleHistoryEntry below). Only checks the most recent entries
    -- within the last few seconds — a genuine duplicate would land back-to-back, whereas a real
    -- re-roll of the exact same item to the exact same winner minutes later is a separate event.
    for i = #KART_LootHistory, math.max(1, #KART_LootHistory - 3), -1 do
        local e = KART_LootHistory[i]
        if e.item == (itemLink or "") and e.winner == (winnerDisplayName or "") and e.reason == (reason or "")
           and now - (e.time or 0) < 5 then
            return
        end
    end

    -- A reassignment (LC.AssignWinner called again for a rollID that was already assigned) must
    -- replace its previous history entry, not sit alongside it — otherwise the same physical item
    -- shows up twice in history with two different winners.
    if rollID then
        for i = #KART_LootHistory, 1, -1 do
            if KART_LootHistory[i].rollID == rollID and KART_LootHistory[i].item == (itemLink or "") then
                table.remove(KART_LootHistory, i)
                break
            end
        end
    end

    local _, _, difficultyID, difficultyName = GetInstanceInfo()
    table.insert(KART_LootHistory, {
        time         = now,
        item         = itemLink or "",
        winner       = winnerDisplayName or "",
        winnerKey    = winnerKey,
        reason       = reason or "",
        class        = classFile,
        color        = colorDef and {r = colorDef.r, g = colorDef.g, b = colorDef.b} or nil,
        difficulty   = difficultyName or "",
        difficultyID = difficultyID,
        rollID       = rollID,
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

function LH.RequestHistorySync()
    local latest = 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.time and e.time > latest then latest = e.time end
    end
    LC.SendLC("LC_HIST_REQ:" .. latest)
end

-- Runs on every peer that receives a sync request; only replies (via whisper-style addon message,
-- never a visible chat message) if it actually has entries the requester is missing.
function LH.HandleHistoryRequest(payload, senderFullName)
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

    -- Random base delay de-collides multiple answering peers; the per-entry 0.2s spacing keeps
    -- a 30-entry reply under the client's addon-message throttle instead of bursting one frame.
    local baseDelay = math.random() * 2
    for i, e in ipairs(toSend) do
        C_Timer.After(baseDelay + (i - 1) * 0.2, function()
            local colorPacked = ""
            if e.color then
                colorPacked = string.format("%d,%d,%d",
                    math.floor(e.color.r * 255), math.floor(e.color.g * 255), math.floor(e.color.b * 255))
            end
            -- Item field is last on purpose: item links are full of colons internally, so only the
            -- final field may contain them. winner (an NSRT nickname / free display name) and reason
            -- are free text too — strip any colons so the fixed fields stay position-stable.
            local winnerSafe = (e.winner or ""):gsub(":", "")
            local reasonSafe = (e.reason or ""):gsub(":", "")
            local winnerKey = e.winnerKey or "" -- stable identity key (GUID, no colons) for dedup
            -- Wire difficultyID (locale-independent), not the localized name: history is
            -- English-canonical, so the receiver derives both its own display name and the EN export
            -- from the id. rollID lets a later reassignment replace this entry instead of duplicating,
            -- and winnerKey lets the receiver dedup by identity rather than by (drifting) display name.
            local msg = string.format("LC_HIST_ENTRY:%d:%d:%d:%s:%s:%s:%s:%s:%s",
                e.time or 0, e.difficultyID or 0, e.rollID or 0, e.class or "", colorPacked,
                winnerKey, winnerSafe, reasonSafe, e.item or "")
            -- Full item links can run long (many bonus IDs + localized name); if the message would
            -- blow the 255-byte SendAddonMessage cap, fall back to the compact, locale-independent
            -- item string, which the receiver rebuilds into a full link.
            if #msg > 255 then
                local itemStr = KART.GetItemString(e.item)
                if itemStr then
                    msg = string.format("LC_HIST_ENTRY:%d:%d:%d:%s:%s:%s:%s:%s:%s",
                        e.time or 0, e.difficultyID or 0, e.rollID or 0, e.class or "", colorPacked,
                        winnerKey, winnerSafe, reasonSafe, itemStr)
                end
            end
            KART.Sync.Send(msg, "WHISPER", senderFullName)
        end)
    end
end

-- Runs on the requester when a peer whispers back a missing entry.
function LH.HandleHistoryEntry(payload, senderKey)
    -- Catch-up entries land in the permanent loot history — only accept them from someone
    -- actually in our current group, not from arbitrary whispers.
    if not (senderKey and KART.Identity.FindUnitForKey(senderKey)) then return end
    local t, diffID, rollID, classFile, colorPacked, winnerKey, winner, reason, item =
        payload:match("^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
    t = tonumber(t)
    if not t or not winner then return end
    diffID = tonumber(diffID); if diffID == 0 then diffID = nil end
    rollID = tonumber(rollID); if rollID == 0 then rollID = nil end
    if winnerKey == "" then winnerKey = nil end
    item = item or ""

    local color
    if colorPacked and colorPacked ~= "" then
        local cr, cg, cb = colorPacked:match("^(%d+),(%d+),(%d+)$")
        if cr then color = {r = tonumber(cr) / 255, g = tonumber(cg) / 255, b = tonumber(cb) / 255} end
    end

    -- The sender may have sent a bare item string (its full link was too long for one addon
    -- message). Rebuild a full, locally-localized link so display/tooltip/icon work; if the item
    -- isn't cached yet, store the string now and upgrade the entry in place once it loads.
    local needsRebuild = item ~= "" and not KART.IsRealItemLink(item) and item:match("^item:") ~= nil
    local itemLink = item
    if needsRebuild then
        local rebuilt = select(2, C_Item.GetItemInfo(item))
        if rebuilt then itemLink = rebuilt end
    end

    KART_LootHistory = KART_LootHistory or {}
    -- Locale-independent item string (not the full link, which differs between DE/EN clients and
    -- between a rebuilt link and a still-bare "item:" string). Used for both the reassignment
    -- match below and the duplicate check further down.
    local incomingStr = KART.GetItemString(itemLink)
    -- A reassignment carries the same rollID + item with a new winner — replace the prior entry
    -- for this roll rather than stacking a duplicate (mirrors LH.LogHistory). Matching item too
    -- guards against a manual rollID from a different session colliding on a different item.
    if rollID then
        for i = #KART_LootHistory, 1, -1 do
            local e = KART_LootHistory[i]
            local sameItem = (incomingStr and KART.GetItemString(e.item) == incomingStr) or (e.item == itemLink)
            if e.rollID == rollID and sameItem then
                table.remove(KART_LootHistory, i)
                break
            end
        end
    end
    -- Skip if we already have this award. Compare by the stable identity key + locale-independent
    -- item string (not display name + full link, which differ between DE/EN clients), and allow a
    -- few seconds of clock skew between the two clients that logged it.
    for _, e in ipairs(KART_LootHistory) do
        local sameWinner = (winnerKey and e.winnerKey == winnerKey) or (e.winner == winner)
        local sameItem = (incomingStr and KART.GetItemString(e.item) == incomingStr) or (e.item == itemLink)
        if sameWinner and sameItem and math.abs((e.time or 0) - t) <= 5 then
            return -- already have it (e.g. another peer answered first)
        end
    end

    table.insert(KART_LootHistory, {
        time         = t,
        item         = itemLink or "",
        winner       = winner,
        winnerKey    = winnerKey,
        reason       = reason or "",
        class        = (classFile ~= "" and classFile) or nil,
        color        = color,
        difficulty   = diffID and (GetDifficultyInfo(diffID) or "") or "",
        difficultyID = diffID,
        rollID       = rollID,
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end

    -- Item wasn't cached — once it loads, swap the bare string for a real link in place.
    if needsRebuild and not KART.IsRealItemLink(itemLink) then
        local itemID = tonumber(item:match("^item:(%d+)"))
        if itemID then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                local full = select(2, C_Item.GetItemInfo(item))
                if not full then return end
                for _, e in ipairs(KART_LootHistory or {}) do
                    local sameWinner = (winnerKey and e.winnerKey == winnerKey) or (e.winner == winner)
                    if e.time == t and sameWinner and e.item == item then
                        e.item = full
                        break
                    end
                end
                if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
                    KART.LH.Refresh()
                end
            end)
        end
    end
end
