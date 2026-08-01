local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

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
            matchSearch = KAUtil.CaseFold(GetItemNameFromLink(e.item)):find(LH.filters.search, 1, true) ~= nil
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
        if KAUtil.IsRealItemLink(e.item) then
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
            JSONString("itemString", (KAUtil.GetItemString(e.item) or "")),
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
        KART.UI:RegisterStrataFrame(f, true)
        KART.UI:ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        -- Clamped, like every Blizzard frame. Without it a window can be dragged past the edge of the
        -- game window -- reported from a live test in windowed mode on two monitors, where the desktop
        -- beyond the edge is real screen and nothing stops the drag. KAUI.IsSavedPosOnScreen already
        -- refuses to RESTORE an off-screen position; this is the other half.
        f:SetClampedToScreen(true)
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetText(KART.L.LH_EXPORT_TITLE)
        KART.UI:RegisterLabel(f.title)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOP", 0, -32)
        f.hint:SetText(KART.L.LH_EXPORT_HINT)
        f.hint:SetTextColor(0.6, 0.6, 0.6)
        KART.UI:RegisterLabel(f.hint)

        -- Same inset/border colors as KART.UI:CreateStyledEditBox (the multi-line export box lives
        -- inside a ScrollFrame, so the visual box is this frame); focus accent mirrored below.
        local scrollBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
        scrollBG:SetPoint("TOPLEFT", 15, -52)
        scrollBG:SetPoint("BOTTOMRIGHT", -15, 44)
        KART.UI:SetPixelBackdrop(scrollBG, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        scrollBG:SetBackdropColor(0.03, 0.05, 0.08, 0.9)
        scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
        KART.UI:ApplyRoundedMask(scrollBG, KAUI.CORNER_RADIUS_LG)

        local scroll = CreateFrame("ScrollFrame", "KART_LHExportScroll", scrollBG, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -22, 4)

        local exportScrollThumb = KART.UI:StripScrollbarTextures(scroll)
        if exportScrollThumb then exportScrollThumb:SetSize(6, 16) end
        KART.UI:RegisterAccentTexture(exportScrollThumb, 0.6)

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
            local r, g, b = KART.UI:AccentColor()
            scrollBG:SetBackdropBorderColor(r, g, b, 1)
        end)
        f.editBox:SetScript("OnEditFocusLost", function()
            scrollBG:SetBackdropBorderColor(0.15, 0.2, 0.26, 1)
        end)
        scroll:SetScrollChild(f.editBox)

        local btnClose = KART.UI:CreateModernButton(f, CLOSE) ---@diagnostic disable-line: undefined-global
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
                label = KASC.Identity.ResolveDisplayName(e.winnerKey) or e.winner
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

-- Clearing draws a line rather than just emptying a table, and the line is what makes the clear
-- stick. LH.RequestHistorySync asks peers for everything newer than the newest entry it holds; after
-- a wipe that is zero, which reads as "send me everything you have" -- so the catch-up faithfully
-- rebuilt exactly what had just been deleted, and a season started with last tier's items still in
-- the list. Reported by the maintainer, 2026-08-01.
--
-- Switching the sync off is not the alternative: the whole reason it exists is that items decided
-- while you were absent still reach the list you export. A line keeps both -- nothing older than it
-- ever comes back, everything after it still does.
--
-- Personal and account-wide, like the history itself. It is not synced and nobody else's clear
-- affects yours.
function LH.ClearHistory()
    wipe(KART_LootHistory)
    KART_LootHistoryClearedAt = time()
    LH.Refresh()
end

KART.UI:RegisterStaticPopup("KART_LH_CLEAR_CONFIRM", {
    text = "Really clear loot history?", -- unconditionally overwritten with KART.L.LH_CLEAR_CONFIRM_TEXT below
    button1 = YES,
    button2 = NO,
    OnAccept = function() LH.ClearHistory() end,
})

-- =====================================================================
--  Window
-- =====================================================================

function LH.CreateWindow()
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 430)
    f:SetPoint("CENTER")
    KART.UI:RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.UI:ApplyPopupArtwork(f)
    -- Clamped, like every Blizzard frame. Without it a window can be dragged past the edge of the
    -- game window -- reported from a live test in windowed mode on two monitors, where the desktop
    -- beyond the edge is real screen and nothing stops the drag. KAUI.IsSavedPosOnScreen already
    -- refuses to RESTORE an off-screen position; this is the other half.
    f:SetClampedToScreen(true)
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
    KART.UI:RegisterLabel(f.title)
    KART.UI:CreateHeaderLine(f, -28)

    local closeBtn = KART.UI:CreateHeaderIconButton(hdr, "×", function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", -4, 0)

    -- Filter row: item search + player filter + reason filter + reset
    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchHint:SetPoint("TOPLEFT", 10, -32)
    searchHint:SetText(KART.L.LH_SEARCH_LABEL)
    searchHint:SetTextColor(0.55, 0.55, 0.55)
    KART.UI:RegisterLabel(searchHint)

    local searchBox = CreateFrame("EditBox", "KART_LHSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", 10, -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    KART.UI:SetPixelBackdrop(searchBox, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    searchBox:SetBackdropColor(0, 0, 0, 0.5)
    searchBox:SetTextInsets(5, 5, 0, 0)
    searchBox:SetMaxLetters(40)
    KART.UI:ApplyRoundedMask(searchBox, KAUI.CORNER_RADIUS_SM)
    KART.UI:RegisterEditBox(searchBox)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        LH.filters.search = KAUtil.CaseFold(self:GetText())
        LH.Refresh()
    end)
    f.searchBox = searchBox

    local btnPlayerFilter = KART.UI:CreateModernButton(f, KART.L.LH_FILTER_ALL_PLAYERS)
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

    local btnReasonFilter = KART.UI:CreateModernButton(f, KART.L.LH_FILTER_ALL_REASONS)
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

    local btnReset = KART.UI:CreateModernButton(f, KART.L.LH_BTN_RESET_FILTERS)
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
    KART.UI:RegisterLabel(hDate)

    local hPlayer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPlayer:SetPoint("TOPLEFT", 80, -78)
    hPlayer:SetText(KART.L.LH_COL_PLAYER)
    KART.UI:RegisterLabel(hPlayer)

    local hItem = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hItem:SetPoint("TOPLEFT", 172, -78)
    hItem:SetText(KART.L.LH_COL_ITEM)
    KART.UI:RegisterLabel(hItem)

    local hDifficulty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDifficulty:SetPoint("TOPLEFT", 368, -78)
    hDifficulty:SetText(KART.L.LH_COL_DIFFICULTY)
    KART.UI:RegisterLabel(hDifficulty)

    local hReason = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hReason:SetPoint("TOPLEFT", 440, -78)
    hReason:SetText(KART.L.LH_COL_REASON)
    KART.UI:RegisterLabel(hReason)

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

    local thumb = KART.UI:StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end
    KART.UI:RegisterAccentTexture(thumb, 0.6)

    f.scrollChild = scrollChild
    f.scrollFrame = scrollFrame
    f.rows        = {}

    -- Empty-state label
    f.emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.emptyLabel:SetPoint("TOP", 0, -20)
    f.emptyLabel:SetText(KART.L.LH_EMPTY)
    f.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    f.emptyLabel:Hide()
    KART.UI:RegisterLabel(f.emptyLabel)

    -- Footer: entry count + clear button
    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.countText:SetPoint("BOTTOMLEFT", 10, 12)
    f.countText:SetTextColor(0.6, 0.6, 0.6)
    KART.UI:RegisterLabel(f.countText)

    local btnClear = KART.UI:CreateModernButton(f, KART.L.LH_BTN_CLEAR)
    btnClear:SetSize(140, 24)
    btnClear:SetPoint("BOTTOMRIGHT", -10, 8)
    btnClear:SetScript("OnClick", function()
        StaticPopupDialogs["KART_LH_CLEAR_CONFIRM"].text = KART.L.LH_CLEAR_CONFIRM_TEXT
        StaticPopup_Show("KART_LH_CLEAR_CONFIRM")
    end)

    local btnExport = KART.UI:CreateModernButton(f, KART.L.LH_BTN_EXPORT_JSON, KART.L.LH_BTN_EXPORT_JSON_TIP)
    btnExport:SetSize(150, 24)
    btnExport:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMLEFT", -6, 0)
    btnExport:SetScript("OnClick", function() LH.ShowExportDialog() end)

    -- Pagination controls, anchored just left of the export button and growing leftward, so they
    -- never collide with the right-hand buttons regardless of their localized widths. The list uses
    -- a fit-to-window page size (see LH.Refresh) and so never scrolls — Prev/Next page through it.
    f.nextPageBtn = KART.UI:CreateModernButton(f, ">")
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

    f.prevPageBtn = KART.UI:CreateModernButton(f, "<")
    f.prevPageBtn:SetSize(24, 22)
    f.prevPageBtn:SetPoint("RIGHT", f.pageIndicator, "LEFT", -6, -1)
    f.prevPageBtn:SetScript("OnClick", function()
        LH.currentPage = math.max(1, (LH.currentPage or 1) - 1)
        LH.Refresh()
    end)

    LH.historyWindow = f

    -- Restore saved position
    local pos = KART_Settings and KART_Settings.lcHistoryWindowPos
    if pos and type(pos) == "table" and KAUI.IsSavedPosOnScreen(pos.x, pos.y) then
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
            KART.UI:RegisterLabel(row.dateText)
            row.dateText:SetPoint("LEFT", 6, 0)
            row.dateText:SetWidth(68)
            row.dateText:SetJustifyH("LEFT")

            row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.playerText)
            row.playerText:SetPoint("LEFT", 76, 0)
            row.playerText:SetWidth(88)
            row.playerText:SetJustifyH("LEFT")

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 166, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.itemText)
            row.itemText:SetPoint("LEFT", 188, 0)
            row.itemText:SetWidth(176)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.difficultyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.difficultyText)
            row.difficultyText:SetPoint("LEFT", 368, 0)
            row.difficultyText:SetWidth(68)
            row.difficultyText:SetJustifyH("LEFT")
            row.difficultyText:SetTextColor(0.7, 0.7, 0.7)

            row.reasonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            KART.UI:RegisterLabel(row.reasonText)
            row.reasonText:SetPoint("LEFT", 440, 0)
            row.reasonText:SetWidth(80)
            row.reasonText:SetJustifyH("LEFT")

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if KAUtil.IsRealItemLink(self.itemLink) then
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
        local lr, lg, lb = KART.UI:GetRowStripeColor()
        row.bg:SetColorTexture(lr, lg, lb, i % 2 == 0 and 0.35 or 0.1)

        row.dateText:SetText(date("%d.%m %H:%M", e.time or 0))

        local nr, ng, nb = 0.8, 0.8, 0.8
        if e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class] then
            nr, ng, nb = RAID_CLASS_COLORS[e.class].r, RAID_CLASS_COLORS[e.class].g, RAID_CLASS_COLORS[e.class].b
        end
        row.playerText:SetText(e.winner)
        row.playerText:SetTextColor(nr, ng, nb)

        row.itemLink = e.item
        if KAUtil.IsRealItemLink(e.item) then
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
-- Enforces MAX_HISTORY_ENTRIES by dropping the entry with the OLDEST timestamp, not index 1.
-- Insertion order only equals chronological order for locally-logged awards; the catch-up sync
-- appends backfilled entries that are older than everything already stored, so a plain remove(1)
-- would evict the NEWEST rows — one per received entry.
local function TrimHistory()
    while #KART_LootHistory > MAX_HISTORY_ENTRIES do
        local oldestIdx, oldestTime = 1, (KART_LootHistory[1] and KART_LootHistory[1].time) or 0
        for i = 2, #KART_LootHistory do
            local t = KART_LootHistory[i].time or 0
            if t < oldestTime then oldestIdx, oldestTime = i, t end
        end
        table.remove(KART_LootHistory, oldestIdx)
    end
end

-- Drops rollID's history entry, if it has one. Used when an award is revoked ("No Winner", or a
-- "/kart add" re-decision of an already-awarded item): the item then has no winner, so leaving the
-- old attribution in the log would credit someone who never received it — and since the re-decision
-- gets a fresh rollID, the dedupe in LogHistory/HandleHistoryEntry (which matches on rollID) can't
-- collapse the two entries later. Runs on every client, so all logs stay identical: the revoker
-- calls it locally, everyone else through Trade.HandleResult's "NONE" branch.
--
-- Bounded to the roll actually being revoked. A rollID identifies a roll only within the session
-- Blizzard issued it in — they are small integers and they come round again every evening — while
-- KART_LootHistory is a SavedVariable holding up to 500 awards across many raid nights. Matching on
-- the ID alone therefore reached back into previous weeks: pressing "No Winner" on tonight's roll 47
-- silently deleted a completely unrelated award made under roll 47 last Tuesday, on every client in
-- the raid at once, with the loot history being precisely what the council consults to decide who is
-- owed something.
--
-- LC.rollLootedAt[rollID] is stamped the moment this roll starts, on every client and on all three
-- entry paths (a real drop, an LC_START from the owner, and /kart add), so an entry older than it
-- belongs to an earlier roll by definition. That also covers the within-session reuse the rest of
-- the module already guards against. The age bound is the fallback for a roll whose stamp we never
-- saw; it is deliberately generous, since the cost of keeping one stale entry is a line in a log and
-- the cost of removing the wrong one is somebody's record of an item they actually won.
local REVOKE_MAX_AGE = 12 * 60 * 60

-- itemLink says WHICH roll under this ID is being superseded, and it is the discriminator that
-- actually works. The time bound alone reads "everything logged since this roll started", which a
-- client that never saw it start cannot evaluate -- it falls back to twelve hours and takes the
-- previous item's award with it. That is not hypothetical: a raider who joins mid-evening is handed
-- the earlier awards by the history catch-up and then loses them to the next drop that reuses the
-- number, so the raid agrees on every winner and disagrees about its own record of the evening.
-- Same rule LH.LogHistory already applies to its own replacement pass, now applied here too.
--
-- Unknown on either side counts as belonging: an entry restored from an older version carries no
-- parseable item, and a caller that has not resolved the link yet passes none. Refusing to act there
-- would leave the duplicate this function exists to remove.
local function ItemIDOf(link)
    return (type(link) == "string" and link:match("item:(%d+)")) or nil
end

function LH.RemoveHistoryForRoll(rollID, itemLink)
    if not rollID or not KART_LootHistory then return end
    local since  = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or (time() - REVOKE_MAX_AGE)
    local wantID = ItemIDOf(itemLink)
    local changed = false
    for i = #KART_LootHistory, 1, -1 do
        local e = KART_LootHistory[i]
        local sameItem = wantID == nil or ItemIDOf(e.item) == nil or ItemIDOf(e.item) == wantID
        if e.rollID == rollID and sameItem and (e.time or 0) >= since then
            table.remove(KART_LootHistory, i)
            changed = true
        end
    end
    if changed and LH.historyWindow and LH.historyWindow:IsShown() then LH.Refresh() end
end

function LH.LogHistory(itemLink, winnerDisplayName, reason, classFile, colorDef, rollID, winnerKey)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- Guards against double-logging the same win if a redelivered/duplicate LC_RESULT addon
    -- message ever reaches this client twice (HandleResult has no dedup of its own, unlike the
    -- history catch-up sync path in HandleHistoryEntry below). Only checks the most recent entries
    -- within the last few seconds — a genuine duplicate would land back-to-back, whereas a real
    -- re-roll of the exact same item to the exact same winner minutes later is a separate event.
    --
    -- Matched on the rollID whenever there is one, because two identical drops awarded to the same
    -- player back to back are indistinguishable from a redelivered message by item/winner/reason
    -- alone -- and were being swallowed, leaving the trade reminder correctly listing two items
    -- while the history showed one (B13). Different drops always carry different rollIDs; a
    -- redelivered message carries the same one, so this tells them apart exactly instead of
    -- guessing from a five-second window.
    for i = #KART_LootHistory, math.max(1, #KART_LootHistory - 3), -1 do
        local e = KART_LootHistory[i]
        local sameEvent
        if rollID and e.rollID then
            sameEvent = e.rollID == rollID
        else
            -- No rollID on one side (a manual entry, or one restored from an older version):
            -- fall back to the original heuristic rather than logging a certain duplicate.
            sameEvent = now - (e.time or 0) < 5
        end
        if sameEvent and e.item == (itemLink or "") and e.winner == (winnerDisplayName or "")
           and e.reason == (reason or "") then
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
    -- Normalize the non-instance sentinel 0 to nil, matching LH.HandleHistoryEntry. 0 is truthy in
    -- Lua, so leaving it would make DifficultyDisplay/Export take the ID branch (which resolves to
    -- nothing for 0) instead of the stored-name fallback — the two write paths must agree here.
    if difficultyID == 0 then difficultyID = nil end ---@diagnostic disable-line: cast-local-type
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
    TrimHistory()
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
-- Minimum seconds between two answered catch-up requests from the same player. Long enough to
-- absorb a rejoin burst, short enough that a genuine relog later in the raid still gets served.
local HISTORY_SYNC_ANSWER_COOLDOWN = 60

function LH.RequestHistorySync()
    -- Never earlier than the last clear (see LH.ClearHistory). The since-timestamp already means
    -- "I have everything up to here", so a line drawn by hand fits it exactly and no peer needs to
    -- know anything about it.
    local latest = KART_LootHistoryClearedAt or 0
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
    -- Only answer group members. CHAT_MSG_ADDON also delivers whispers and the "KART" prefix is
    -- public, so without this any stranger could whisper LC_HIST_REQ and exfiltrate our loot history
    -- (winners, items, reasons).
    --
    -- Deliberately NOT via Identity.ResolvePlayer: for a sender who isn't in the group that falls
    -- back to the persistent cache, which matches on the realm-stripped short name — so an outsider
    -- "Bob-Silvermoon" would resolve onto group member "Bob-Ravencrest"'s GUID and pass. Match the
    -- full realm-qualified name against the live roster instead, which no outsider can satisfy.
    if not KAUtil.IsFullNameInGroup(senderFullName) then return end
    -- Rate-limit the reply burst per sender: each answered request queues up to
    -- HISTORY_SYNC_MAX_ENTRIES timers spanning ~8s, so a peer repeatedly leaving and rejoining would
    -- otherwise stack bursts until the outgoing messages hit the client's throttle and the server's
    -- spam kick. A cooldown rather than a once-per-session latch, and applied only once we actually
    -- have something to send (below): a legitimate re-request after a disconnect — the entire point
    -- of catch-up sync — must not be blocked by an earlier request that turned out to be a no-op.
    LH.historySyncAnswered = LH.historySyncAnswered or {}
    local now = time()
    if now - (LH.historySyncAnswered[senderFullName] or 0) < HISTORY_SYNC_ANSWER_COOLDOWN then return end

    local cutoff = now - HISTORY_SYNC_MAX_AGE
    local toSend = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        if (e.time or 0) > sinceTime and (e.time or 0) > cutoff then
            table.insert(toSend, e)
        end
    end
    if #toSend == 0 then return end
    LH.historySyncAnswered[senderFullName] = now

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
            -- Re-check membership at fire time, not just when the request arrived: the burst spans
            -- ~8 seconds, and whispers keep working after either side has left the group — so
            -- without this we'd keep streaming loot history to someone who is no longer authorized.
            if not KAUtil.IsFullNameInGroup(senderFullName) then return end
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
                local itemStr = KAUtil.GetItemString(e.item)
                if itemStr then
                    msg = string.format("LC_HIST_ENTRY:%d:%d:%d:%s:%s:%s:%s:%s:%s",
                        e.time or 0, e.difficultyID or 0, e.rollID or 0, e.class or "", colorPacked,
                        winnerKey, winnerSafe, reasonSafe, itemStr)
                end
            end
            -- Still over budget (a non-link item, or a very long nickname + reason): send an empty
            -- item field rather than let SendAddonMessage truncate the trailing item into garbage.
            -- The entry still syncs; the item just shows blank on the receiver instead of corrupt.
            if #msg > 255 then
                msg = string.format("LC_HIST_ENTRY:%d:%d:%d:%s:%s:%s:%s:%s:%s",
                    e.time or 0, e.difficultyID or 0, e.rollID or 0, e.class or "", colorPacked,
                    winnerKey, winnerSafe, reasonSafe, "")
            end
            KASC:Send(msg, "WHISPER", senderFullName)
        end)
    end
end

-- Runs on the requester when a peer whispers back a missing entry.
function LH.HandleHistoryEntry(payload, senderKey)
    -- Catch-up entries land in the permanent loot history — only accept them from someone
    -- actually in our current group, not from arbitrary whispers.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    local t, diffID, rollID, classFile, colorPacked, winnerKey, winner, reason, item =
        payload:match("^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
    t = tonumber(t)
    if not t or not winner then return end
    -- Reject a timestamp from the future. time() is each client's OS clock, so a peer with a badly
    -- set clock (or a hostile one) would otherwise write an entry dated years ahead — which then
    -- becomes the "since" watermark LH.RequestHistorySync sends, permanently asking every peer for
    -- entries newer than that date and silently killing catch-up sync for good.
    if t > time() + 300 then return end
    -- Older than the line the player drew when they last cleared. The request side already asks from
    -- there, but a reply burst spans about eight seconds -- so a clear can land in the middle of one,
    -- with the deleted entries already on their way.
    if t <= (KART_LootHistoryClearedAt or 0) then return end
    -- Free text from another client, rendered raw into the history window and the export. Double the
    -- pipes so |c colour codes and |H hyperlinks can't be injected into a SavedVariable that is then
    -- displayed forever. (RC_REASON does the same on its own receive side.)
    winner = winner:gsub("|", "||")
    reason = (reason or ""):gsub("|", "||")
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
    local needsRebuild = item ~= "" and not KAUtil.IsRealItemLink(item) and item:match("^item:") ~= nil
    local itemLink = item
    if needsRebuild then
        local rebuilt = select(2, C_Item.GetItemInfo(item))
        if rebuilt then itemLink = rebuilt end
    end

    KART_LootHistory = KART_LootHistory or {}
    -- Locale-independent item string (not the full link, which differs between DE/EN clients and
    -- between a rebuilt link and a still-bare "item:" string). Used for both the reassignment
    -- match below and the duplicate check further down.
    -- KAUtil.GetItemString only recognizes a FULL link ("|Hitem:..."), so it returns nil for the bare
    -- "item:12345:..." string the oversized-link fallback sends — which is also exactly the case
    -- where the local rebuild above can fail (item not in the client's cache yet). Fall back to the
    -- bare form so both sides still reduce to the same locale-independent key.
    local function ItemKey(link)
        if type(link) ~= "string" then return nil end
        return KAUtil.GetItemString(link) or link:match("^item:[%-%d:]+")
    end
    local incomingStr = ItemKey(itemLink)
    -- The sender drops the item field entirely when even the compact item string won't fit the
    -- 255-byte cap (see LH.HandleHistoryRequest). An empty item can't be compared by item at all:
    -- matching on `e.item == ""` would both miss the copy we already hold under its real link (→
    -- duplicate) and collide with any other item-less award for the same winner (→ wrongly dropped).
    -- Fall back to rollID, which identifies the award on its own.
    local itemUnknown = (itemLink == "")
    local function SameItemAs(e)
        if itemUnknown then return rollID ~= nil and e.rollID == rollID end
        return (incomingStr and ItemKey(e.item) == incomingStr) or (e.item == itemLink)
    end
    -- Skip if we already have this award. Compare by the stable identity key + locale-independent
    -- item string (not display name + full link, which differ between DE/EN clients), and allow a
    -- few seconds of clock skew between the two clients that logged it. Runs BEFORE the reassignment
    -- removal below: a re-sent award we already hold (small clock skew between the two loggers, both
    -- carrying the same rollID) must be recognized as a duplicate and skipped, not needlessly removed
    -- and reinserted with the peer's timestamp/wire data.
    for _, e in ipairs(KART_LootHistory) do
        local sameWinner = (winnerKey and e.winnerKey == winnerKey) or (e.winner == winner)
        local sameItem = SameItemAs(e)
        -- The rollID is what tells two awards apart when nothing else does. A boss dropping the
        -- same token twice and the council handing both to the same raider within a few seconds
        -- matches on winner, item AND the clock-skew window — so without this the second award was
        -- read as a re-send of the first and dropped. Everyone who was in the raid logged both
        -- (LH.LogHistory keys on the rollID); only whoever caught up later ended up with one, and
        -- the council reads exactly that list to see who is already owed something.
        --
        -- Only when BOTH sides have one: a manual or legacy entry without a rollID still falls back
        -- to winner + item + the time window, which is all it has.
        local sameRoll = rollID == nil or e.rollID == nil or e.rollID == rollID
        if sameWinner and sameItem and sameRoll and math.abs((e.time or 0) - t) <= 5 then
            return -- already have it (e.g. another peer answered first)
        end
    end
    -- A reassignment carries the same rollID + item with a NEW winner — replace the prior entry
    -- for this roll rather than stacking a duplicate (mirrors LH.LogHistory). Matching item too
    -- guards against a manual rollID from a different session colliding on a different item. (A
    -- same-winner re-send was already caught by the duplicate check above, so anything still
    -- matching this rollID here is a genuine winner change.)
    if rollID then
        for i = #KART_LootHistory, 1, -1 do
            local e = KART_LootHistory[i]
            if e.rollID == rollID and SameItemAs(e) then
                table.remove(KART_LootHistory, i)
                break
            end
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
    TrimHistory()
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end

    -- Item wasn't cached — once it loads, swap the bare string for a real link in place.
    if needsRebuild and not KAUtil.IsRealItemLink(itemLink) then
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

-- =====================================================================
--  Addon-message registrations
-- =====================================================================
KASC:RegisterMessage("LC_HIST_REQ", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LH.HandleHistoryRequest(payload, ctx.sender) end)
KASC:RegisterMessage("LC_HIST_ENTRY", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LH.HandleHistoryEntry(payload, ctx:Key()) end)
