local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

KART.LH = KART.LH or {}
local LH = KART.LH
local LC = KART.LC

LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }

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
        -- filters.playerIds is the SET of identities one person is known by in this log: their
        -- winnerKey (GUID) for entries written since 2.6.0, and their plain display name for
        -- everything older. One person, several ids, because that is what a history spanning the
        -- GUID migration actually contains.
        --
        -- It used to be a single id, and LH.GetUniquePlayers produced one entry per DISTINCT id --
        -- so anybody with history on both sides of that migration appeared in the filter twice under
        -- the same name, and neither of the two showed more than half of what they had won.
        local ids = LH.filters.playerIds
        local matchPlayer = (not ids)
            or (e.winnerKey and e.winnerKey ~= "" and ids[e.winnerKey])
            or (e.winner and ids[e.winner])
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
        KART.RegisterEscapeFrame(f)

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
-- One entry per PERSON, not per identity. Each carries every id that person is known by in this log:
-- their winnerKey for entries written since the GUID migration (2.6.0) and their display name for
-- everything older. Grouping by the displayed label is what makes the two halves one line in the
-- filter — and grouping by id, as this used to, put the same name in the list twice with half a
-- history behind each.
--
-- `id` is kept as a stable scalar because LH.Refresh builds its page-reset signature out of it; the
-- set beside it is what the filter actually matches on.
-- One entry per person for the history window's player filter.
--
-- Grouped by the DISPLAYED NAME, and that choice has a cost worth stating (B109). Two different
-- people who were ever logged under the same name -- somebody leaves and a later raider brings a
-- character of that name -- collapse into one filter entry showing both their histories.
--
-- Kept that way on purpose: the filter is a list of names a person picks from, so the name is the
-- only axis they can reason about, and grouping by key instead is precisely what B98 was. That bug
-- put ONE raider in the list twice, split their record down the middle, and gave no sign the other
-- half existed -- a wrong answer to the question actually being asked ("what has this person had?").
-- The namesake case answers that question too widely rather than too narrowly, is visible in the
-- rows themselves (they carry dates and items), and needs a name to be reused inside the 500 entries
-- the history keeps at all.
function LH.GetUniquePlayers()
    local byLabel, list = {}, {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local key = (e.winnerKey and e.winnerKey ~= "" and e.winnerKey) or nil
        local id = key or e.winner
        if id and id ~= "" then
            local label = e.winner
            if key then
                -- ResolveDisplayName answers with the KEY itself when it cannot place somebody --
                -- which is every raider who has since left the guild, since they are neither in the
                -- group nor in the name cache. Taking that as a label put raw GUIDs in the filter
                -- list ("Player-1096-0A1B2C3D") while the name they were logged under sat unused in
                -- the entry. Only a real answer wins over it.
                local resolved = KASC.Identity.ResolveDisplayName(key)
                if resolved and resolved ~= key and resolved ~= "?" then label = resolved end
            end
            label = label or e.winner or id
            local group = byLabel[label]
            if not group then
                group = { id = id, label = label, ids = {} }
                byLabel[label] = group
                table.insert(list, group)
            end
            group.ids[id] = true
            -- A keyed entry also answers to the name it was logged under, so a later legacy row for
            -- the same person still lands in this group rather than opening a second one.
            if key and e.winner and e.winner ~= "" then group.ids[e.winner] = true end
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

-- The one-time purge that opens the epoch scheme. A client with no epoch is one that has never run
-- a build with award ids, so everything it holds is unmergeable and unexportable: no id to dedup on,
-- no epoch to place it in. Emptying it is not data loss weighed against keeping it -- it is the only
-- state from which every client in the raid starts on the same number. Confirmed by the maintainer
-- on 2026-08-07; the stored data was test raids.
--
-- A function of its own, called from Core.lua's ADDON_LOADED block (after KART_LootHistory has been
-- given its table), and also wired to this file's own ADDON_LOADED registration below -- the test
-- harness loads LootHistory.lua but not Core.lua (see tests/raidsim.lua), so this is what lets the
-- purge run under KARTTEST.FireEvent at all. Idempotent either way, and NOT dependent on which of
-- the two registrations dispatches first: on a genuinely first-ever load both KART_LootHistory and
-- KART_LootHistoryEpoch are nil, and WoW dispatches ADDON_LOADED to frames in registration order --
-- LootHistory.lua's frame registers before Core.lua's (see the .toc's file order), so it can run
-- first and must not assume Core.lua's own `KART_LootHistory = KART_LootHistory or {}` already ran.
-- wipe(nil) errors, so this establishes the table itself rather than trusting it exists.
function LH.PurgeIfNoEpoch()
    if KART_LootHistoryEpoch ~= nil then return end
    KART_LootHistory = KART_LootHistory or {}
    wipe(KART_LootHistory)
    KART_LootHistoryEpoch = 1
end

-- Clearing draws a line rather than just emptying a table, and the line is what makes the clear
-- stick: LH.RequestHistorySync asks peers for what it is missing, and after a plain wipe that reads
-- as "send me everything", so the catch-up faithfully rebuilt exactly what had just been deleted
-- (reported by the maintainer, 2026-08-01).
--
-- The line used to be a personal timestamp, and personal is what was wrong with it. It protected the
-- wiper and nobody else: a raider absent when it was drawn kept last tier's entries, exported them,
-- and stayed permanently out of step with the raid. The line is now a raid-wide number.
--
-- The loot owner's call, and only in a group. Outside one there is nobody to tell, so the epoch would
-- rise in private and win the next raid's merge from an armchair.
function LH.ClearHistory()
    if not IsInGroup() or not LC.IsLootOwner() then return end
    KART_LootHistoryEpoch = (KART_LootHistoryEpoch or 1) + 1
    wipe(KART_LootHistory)
    KART_LootHistoryClearedAt = time()   -- display only now; the epoch is the watermark
    LC.SendLC("LC_HIST_EPOCH:" .. KART_LootHistoryEpoch)
    LH.Refresh()
end

-- Rule 1 of the merge: a higher epoch is a wipe, and it rides along in every message rather than
-- needing one of its own. Adopting it drops everything below it.
--
-- Gated on IsSenderLootOwner and not IsSenderCouncil, which is the check awards go through: a council
-- member may award, only the loot owner may wipe. The gate is what stands between one client with a
-- corrupted epoch and every log in the raid.
--
-- Monotone: it only ever moves up, and applying the same epoch twice does nothing the second time.
-- That is what makes the merge order-independent -- who talks to whom, and when, does not matter.
function LH.AdoptEpoch(epoch, originatorKey)
    epoch = tonumber(epoch)
    if not epoch or epoch <= (KART_LootHistoryEpoch or 1) then return false end
    if not LC.IsSenderLootOwner(originatorKey) then return false end

    KART_LootHistoryEpoch = epoch
    for i = #KART_LootHistory, 1, -1 do
        if (KART_LootHistory[i].epoch or 0) < epoch then table.remove(KART_LootHistory, i) end
    end
    LH.Refresh()
    return true
end

-- The single answer to "does this wire epoch admit its message", shared by every receipt path that
-- carries an epoch next to its payload: an award (LC_RESULT, Trade.HandleResult in
-- LootCouncilTrade.lua) and a catch-up answer (LC_HIST_BATCH, LH.HandleHistoryBatch below). These
-- used to ask the question two different ways (code review, Task 6a, 2026-08-07): the award path
-- got the maintainer's three-case ruling, while the catch-up path only ever checked whether the
-- batch epoch was BELOW ours -- so a batch from an ordinary group member (anyone may answer
-- LC_HIST_REQ, not just the loot owner; see LH.HandleHistoryRequest) carrying that member's own,
-- legitimately higher epoch fell straight through and was stored ABOVE this client's own
-- KART_LootHistoryEpoch, invisible to LH.HistoryChecksum's `(e.epoch or 1) == epoch` filter forever
-- -- exactly the state the ruling exists to prevent, and for exactly the reason it gives. One
-- implementation from here on; two shapes of the same rule only drift again.
--
-- originatorKey is whoever is actually vouching for wireEpoch being real: the assigner of an
-- award, or the peer who answered a catch-up request (their OWN epoch, not necessarily the loot
-- owner's).
--
-- Returns true when the caller should go on and process/store what came with this epoch, false
-- when the whole message must be discarded whole (not merely its history write). Three cases, per
-- the maintainer's ruling:
--   * wireEpoch == myEpoch: the ordinary case -- true, nothing else to do.
--   * wireEpoch < myEpoch: decided/answered before a wipe we have already adopted -- false, discard
--     the message whole. Merge rule 2.
--   * wireEpoch > myEpoch: the other side is ahead of us. If originatorKey is the loot owner, adopt
--     the epoch first (LH.AdoptEpoch discards everything below it) and return true -- merge rule 1.
--     Otherwise we have heard of an epoch we cannot verify: note it (LH.heardEpoch, surfaced as
--     LH.IsStale() in /kart status) and return false without adopting or storing anything.
--
-- Consequence worth stating plainly: a returning absentee who resyncs while the loot owner is
-- absent cannot adopt the new epoch from an ordinary peer's catch-up answer, so it stays stale
-- until the loot owner is around to vouch for it. That is the intended cost of "only the loot owner
-- may wipe" (Task 2, Task 4) -- the client refuses to award while stale, and /kart status shows the
-- condition, so nothing is lost quietly.
function LH.AdmitEpoch(wireEpoch, originatorKey)
    local myEpoch = KART_LootHistoryEpoch or 1
    if wireEpoch < myEpoch then
        return false
    elseif wireEpoch > myEpoch then
        if LC.IsSenderLootOwner(originatorKey) then
            LH.AdoptEpoch(wireEpoch, originatorKey)
            return true
        end
        LH.heardEpoch = math.max(LH.heardEpoch or 0, wireEpoch)
        return false
    end
    return true
end

-- True while we know of an epoch above our own that we could not adopt -- we are behind the raid and
-- our log is not the raid's log. Consumed by the award path: a client in this state must not write
-- into a record it cannot see all of.
function LH.IsStale()
    return (LH.heardEpoch or 0) > (KART_LootHistoryEpoch or 1)
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
    KART.RegisterEscapeFrame(f)
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
                LH.filters.player, LH.filters.playerIds = nil, nil
                self.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
                LH.Refresh()
            end)
            for _, p in ipairs(LH.GetUniquePlayers()) do
                rootDescription:CreateButton(p.label, function()
                    LH.filters.player, LH.filters.playerIds = p.id, p.ids
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
        LH.filters.player, LH.filters.playerIds = nil, nil
        LH.filters.reason = nil
        LH.filters.search = ""
        searchBox:SetText("")
        btnPlayerFilter.text:SetText(KART.L.LH_FILTER_ALL_PLAYERS)
        btnReasonFilter.text:SetText(KART.L.LH_FILTER_ALL_REASONS)
        LH.Refresh()
    end)
    f.btnReset = btnReset

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

-- A stable identity for one award, the same string on every client that logs it.
--
-- rollID cannot be it. It is a small Blizzard number and it comes round again every week, which is
-- why the revoke path had to be bounded to the roll actually being revoked (see LH.ForgetAward).
-- The export id cannot be it either: it is an index into the FILTERED list, so it changes with the
-- filter. The union merge, the export cut and the Companion archive all dedup on this string, so it
-- has to survive a week, a reload and a different filter.
--
-- Minted by whoever assigns and carried in LC_RESULT, because every client logs from that message --
-- a locally generated id would differ per client and the dedup would never match.
--
-- Colon-free by construction: it travels as a fixed field in a colon-separated payload whose tail is
-- free text.
local awardIDCounter = 0
function LH.NewAwardID()
    awardIDCounter = (awardIDCounter + 1) % 0x1000
    return string.format("%d-%03x%03x", time(), math.random(0, 0xFFF), awardIDCounter)
end

-- decisionEpoch (optional) is the epoch KART_LootHistoryEpoch held at the moment this award was
-- decided -- carried on the wire next to awardID since Task 6a, and threaded straight through by
-- both LC_RESULT call sites (Trade.DoAssignWinner and Trade.HandleResult) rather than re-derived
-- here. Absent for a locally logged award that never went over the wire (a test roll, or a manual
-- call with no awardID either): falls back to the current epoch, same as before Task 6a.
function LH.LogHistory(itemLink, winnerDisplayName, reason, classFile, colorDef, rollID, winnerKey, awardID, decisionEpoch)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- An id match is proof: same award, already stored. Checked before the rollID scan below, which
    -- can only ever be a guess -- a rollID is unique within one Blizzard session, not across a
    -- SavedVariable spanning weeks.
    if awardID then
        for _, e in ipairs(KART_LootHistory) do
            if e.id == awardID then return end
        end
    end

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
        id           = awardID or LH.NewAwardID(),
        epoch        = decisionEpoch or KART_LootHistoryEpoch or 1,
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
-- was assigned while they were away. On join, they broadcast their epoch, a checksum of what they
-- hold at it, and the newest entry they know of; any peer who diverges answers with the missing
-- entries packed into a handful of whispers (addon channel, invisible to the player) instead of one
-- message per award. Capped and time-scoped to keep this cheap even after long absences.

local HISTORY_SYNC_MAX_ENTRIES = 150
local HISTORY_SYNC_MAX_AGE     = 14 * 24 * 60 * 60 -- 14 days
-- Minimum seconds between two answered catch-up requests from the same player. Long enough to
-- absorb a rejoin burst, short enough that a genuine relog later in the raid still gets served.
local HISTORY_SYNC_ANSWER_COOLDOWN = 60

-- B66: an award this client could not authorise leaves a hole that nothing else fills.
--
-- Trade.HandleResult drops an LC_RESULT whose sender it cannot confirm is council, and that is the
-- right call -- it is what stands between the loot record and anybody in the group writing rows into
-- it. What was wrong is what happened next: nothing at all. LH.RequestHistorySync runs once per raid
-- JOIN, so a client still waiting for the raid's config when an award was announced is missing that
-- award for the rest of the evening, on the list the council reads to see who is already owed
-- something, with no sign of it on any screen.
--
-- The rejection is the one moment a client knows for certain that it is missing one, so it is where
-- the catch-up belongs. Delayed, because the config that would have authorised the sender is usually
-- seconds behind and asking after it lands costs nothing. Rate-limited, because a client whose
-- config never arrives would otherwise ask once per award for a whole distribution -- and the answer
-- to one request already carries everything the later ones would have asked for.
local UNAUTHORISED_SYNC_DELAY    = 5
local UNAUTHORISED_SYNC_COOLDOWN = 60

function LH.NoteUnauthorisedAward()
    local now = GetTime()
    if LH.lastUnauthorisedSync and (now - LH.lastUnauthorisedSync) < UNAUTHORISED_SYNC_COOLDOWN then
        return
    end
    LH.lastUnauthorisedSync = now
    C_Timer.After(UNAUTHORISED_SYNC_DELAY, function() LH.RequestHistorySync() end)
end

-- An order-independent fingerprint of what we hold at the current epoch.
--
-- It exists because the since-timestamp can only ever find what is missing AHEAD of it. A client that
-- is missing an entry OLDER than its newest one never asks for it and never gets it -- and the
-- catch-up sync backfills exactly such entries, so the hole is not hypothetical. A sum over ids
-- notices a set difference in one integer, without shipping the set.
--
-- Sum and not a running hash: peers hold the same entries in different ORDER (locally logged entries
-- interleave with backfilled ones), and a fingerprint that depends on order would report a difference
-- between two clients that agree.
function LH.HistoryChecksum()
    local epoch, sum = KART_LootHistoryEpoch or 1, 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if (e.epoch or 1) == epoch and e.id then
            local h = 0
            for i = 1, #e.id do h = (h * 31 + e.id:byte(i)) % 0x7FFFFFFF end
            sum = (sum + h) % 0x7FFFFFFF
        end
    end
    return sum
end

-- Seconds of quiet after the last roll closes before the catch-up may speak. The round is not over
-- when the winner is chosen: LC_RESULT, the winner notification and the trade reminder all still have
-- to get out, and those are the messages the raid is standing still for.
local GATE_GRACE = 5

-- The hard ceiling on parking, regardless of roll state. The release condition above is the roll
-- state, and the failure it has to survive is a roll that never closes -- the lootmaster walking out
-- (C9). Hanging the exit on the same state whose failure it catches is not an exit at all, and a
-- request parked forever is a raider with no history all evening that nobody can see (C14).
local GATE_MAX_PARK = 60

function LH.RequestHistorySync()
    if not LH.GateOpen() then
        -- LH.syncWanted holds the moment this deferral chain started, not just a flag -- read below
        -- to cap the wait, the same way LH.ParkRequest's own `entry.at` caps a parked answer. Without
        -- it, a client whose own gate never reopens (a council member sitting on a decided-but-still-
        -- tabbed roll) would keep rescheduling every GATE_GRACE seconds forever and never once ask.
        LH.syncWanted = LH.syncWanted or GetTime()
        if GetTime() - LH.syncWanted < GATE_MAX_PARK then
            return C_Timer.After(GATE_GRACE, LH.RequestHistorySync)
        end
        -- Past the cap: ask anyway, gate or no gate -- the same escape LH.ParkRequest's cap gives an
        -- answer that would otherwise never go out.
    end
    LH.syncWanted = nil

    -- Never earlier than the current epoch's start: the since-timestamp means "I have everything up
    -- to here", and a wipe is exactly such a line.
    local latest = KART_LootHistoryClearedAt or 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.time and e.time > latest then latest = e.time end
    end
    LC.SendLC(string.format("LC_HIST_REQ:%d:%d:%d",
        KART_LootHistoryEpoch or 1, LH.HistoryChecksum(), latest))
end

-- The first guess at how many entries go in one batch, and nothing more than a guess: what actually
-- decides is how big the batch is once PACKED, measured per batch in LH.AnswerHistoryRequest and
-- halved until it fits.
--
-- An entry count cannot decide it. Measured against this repo's own LibDeflate at PACK_LEVEL, using
-- the real EntryRecord layout and a real night's spread of items, winners and reasons, fifty entries
-- pack to roughly 3 KB -- well over PACK_MAX_BLOCK. That ceiling is enforced on the RECEIVING side:
-- LC.UnpackPayload refuses an oversized block, LH.HandleHistoryBatch counts it as packedUnreadable
-- and stores NONE of the batch. So a count-only cut is not a bandwidth question, it is a raider who
-- asked for a night they missed, got three answers, and kept nothing -- and it does not heal, because
-- the same oversized batch is rebuilt on the next join. Design §4 said this from the start: "the dump
-- is cut into batches, each staying under the limit."
--
-- PACK_MAX_BLOCK is not raised, and its number is deliberately not copied here either: it belongs to
-- LootCouncil.lua as its decompression-bomb ceiling, and a second copy would drift the day it moves.
-- The check asks LC.UnpackPayload instead -- the receiver's own answer to the only question that
-- matters, which is whether this block will come back as a string over there.
local HISTORY_BATCH_ENTRIES = 50

-- One full reconcile per asker per raid night. Six hours covers an evening and has reset by the next
-- one; a calendar day would not, since a raid that runs past midnight is one night.
local HISTORY_FULL_COOLDOWN = 6 * 60 * 60

-- One record, in the field order the receiver parses. The item is last because item links are full of
-- colons; winner and reason are free text, so their colons are stripped and the fixed fields stay
-- position-stable.
local function EntryRecord(e)
    local colorPacked = ""
    if e.color then
        colorPacked = string.format("%d,%d,%d",
            math.floor(e.color.r * 255), math.floor(e.color.g * 255), math.floor(e.color.b * 255))
    end
    return string.format("%d:%d:%d:%s:%s:%s:%s:%s:%s:%d:%s",
        e.time or 0, e.difficultyID or 0, e.rollID or 0, e.class or "", colorPacked,
        e.winnerKey or "", (e.winner or ""):gsub(":", ""), (e.reason or ""):gsub(":", ""),
        e.id or "", e.epoch or 1, e.item or "")
end

-- Whether any roll here is still undecided and therefore blocks the gate.
--
-- Undecided rolls only. LC.rollDeadlines[rollID] being present does not by itself mean a
-- distribution is in flight -- a council member's DECIDED roll deliberately stays there so its
-- tab can be reassigned (see Trade.DoAssignWinner: "the tab deliberately stays open"), and
-- Vote.PruneExpiredRolls explicitly skips clearing anything still tabbed. A plain raider's client
-- frees the roll at its own vote deadline, but a council member's does not -- so checking mere
-- presence would close this gate on the first item of the night for every council member (and
-- therefore the lootmaster) and never reopen it, taxing every history answer and every own
-- request from those clients the full GATE_MAX_PARK for the rest of the raid, every raid.
--
-- LC.assignedWinners[rollID] is set the instant a decision is made -- Trade.DoAssignWinner sets
-- it locally before Trade.AnnounceResult sends anything, and Trade.HandleResult sets it on every
-- receiving peer just as early -- so a roll stops blocking here at the same moment it stops being
-- "on the table," not merely once its tab eventually closes. Both LC.rollDeadlines and
-- LC.assignedWinners are wiped together (Trade.ClearRollState, and the bulk wipe in
-- LootCouncil.lua), so there is no window where one is stale relative to the other.
--
-- Shared by LH.GateOpen (mutating: extends the grace period as a side effect) and LH.GateStatus (a
-- pure read for diagnostics), so the two can never disagree on what counts as blocking.
local function AnyRollBlocking()
    for rollID in pairs(LC.rollDeadlines or {}) do
        if (LC.assignedWinners or {})[rollID] == nil then return true end
    end
    return false
end

function LH.GateOpen()
    if AnyRollBlocking() then
        LH.gateClosedUntil = GetTime() + GATE_GRACE
        return false
    end
    return GetTime() >= (LH.gateClosedUntil or 0)
end

-- The same gate LH.GateOpen reports, without its side effect. Diagnostics-only, for LH.PrintStatus.
--
-- LH.GateOpen re-stamps LH.gateClosedUntil to "now + GATE_GRACE" every time it sees a blocking roll --
-- correct for the request/answer paths, which call it to decide whether to act right now, but wrong
-- for a status line that is merely reporting the gate: the manifest's failure procedure is "run
-- /kart status when something looks stuck", which is exactly when this gets called several times in a
-- row, and a read-only diagnostic must not be the reason the gate stays held a little longer each time
-- somebody checks it.
function LH.GateStatus()
    if AnyRollBlocking() then return false end
    return GetTime() >= (LH.gateClosedUntil or 0)
end

-- One pending request per sender. A peer that asks three times while a boss is being distributed has
-- one question, and the answer to the last one already contains what the earlier ones would have got.
function LH.ParkRequest(payload, senderFullName)
    LH.parked = LH.parked or {}
    local existing = LH.parked[senderFullName]
    if existing then
        -- The payload is replaced -- the newest request's answer already covers whatever an older
        -- one asked for -- but `at` is NOT touched. GATE_MAX_PARK measures how long this sender has
        -- been waiting, not how long since their most recent nudge; a repeat request every few
        -- seconds (which is exactly what a client stuck deferring its own LH.RequestHistorySync
        -- would send) must not be able to push the hard cap out indefinitely.
        existing.payload = payload
        return
    end
    LH.parked[senderFullName] = { payload = payload, at = GetTime() }

    local function attempt()
        local entry = LH.parked and LH.parked[senderFullName]
        if not entry then return end
        if LH.GateOpen() or (GetTime() - entry.at) >= GATE_MAX_PARK then
            LH.parked[senderFullName] = nil
            -- Still a group member? The park spans up to a minute and whispers keep working after
            -- either side has left, so without this we would hand the log to somebody who has gone.
            --
            -- Calls LH.AnswerHistoryRequest directly, NOT LH.HandleHistoryRequest: the latter starts
            -- with the same gate check that parked this request in the first place. A council member
            -- keeps a decided roll's tab (and its LC.rollDeadlines entry) open indefinitely for
            -- reassignment, so their own LH.GateOpen() can stay false for the rest of the raid --
            -- the exact "never closes" case GATE_MAX_PARK exists for. Re-entering the gated function
            -- here would just re-park the request with its clock reset, forever, the moment that cap
            -- is what got it released.
            if KAUtil.IsFullNameInGroup(senderFullName) then
                LH.AnswerHistoryRequest(entry.payload, senderFullName)
            end
            return
        end
        C_Timer.After(1, attempt)
    end
    C_Timer.After(1, attempt)
end

-- What /kart status prints about the loot history. Facts only, one per line: the manifest's failure
-- procedure is "everybody run /kart status and paste it", so this is read across five clients at once
-- and has to be comparable at a glance rather than pretty on one.
-- One labelled line per fact, the same convention LC.PrintStatus states in its own comment: "One line
-- each, so a raider can paste the output and the question is settled." Five people paste this into the
-- same chat window at once, and a single packed sentence shifts every field's column between clients
-- the moment one digit differs in width.
--
-- Entries and checksum are deliberately the SAME scope (the current epoch only): KART_LootHistory can
-- still hold rows from a prior epoch that nothing has pruned yet, and printed side by side with no
-- qualifier, a client that simply kept more old-epoch rows than another would read as a sync problem
-- that is not actually one.
function LH.PrintStatus()
    local epoch = KART_LootHistoryEpoch or 1
    local entries = 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if (e.epoch or 1) == epoch then entries = entries + 1 end
    end
    local parked = 0
    for _ in pairs(LH.parked or {}) do parked = parked + 1 end

    print("  " .. KART.L.LH_STATUS_EPOCH .. ": " .. epoch)
    print("  " .. KART.L.LH_STATUS_ENTRIES .. ": " .. entries)
    print("  " .. KART.L.LH_STATUS_CHECKSUM .. ": " .. LH.HistoryChecksum())
    print("  " .. KART.L.LH_STATUS_PARKED .. ": " .. parked)
    -- LH.GateStatus, not LH.GateOpen: this is a read for display, not a decision to act on, and
    -- LH.GateOpen's grace-period stamp is a side effect that belongs to the request/answer paths only.
    print("  " .. KART.L.LH_STATUS_GATE .. ": "
        .. (LH.GateStatus() and KART.L.LH_STATUS_OPEN or KART.L.LH_STATUS_HELD))
    if LH.IsStale() then
        print(string.format(KART.L.LH_STATUS_STALE, LH.heardEpoch or 0, epoch))
    end
end

-- Runs on every peer that receives a sync request; only replies (via whisper-style addon message,
-- never a visible chat message) if it actually has entries the requester is missing.
function LH.HandleHistoryRequest(payload, senderFullName)
    -- Validated fully here (all three fields), even though LH.AnswerHistoryRequest below re-parses
    -- the same payload: a malformed payload must be rejected on arrival, not parked for up to a
    -- minute only to be dropped once it finally reaches the front of the queue.
    local theirEpoch = tonumber((payload:match("^(%d+):(%d+):(%d+)$")))
    if not theirEpoch or not senderFullName then return end
    -- Only answer group members. CHAT_MSG_ADDON also delivers whispers and the "KART" prefix is
    -- public, so without this any stranger could ask and be handed the raid's loot history.
    --
    -- Deliberately NOT via Identity.ResolvePlayer: for a sender who isn't in the group that falls
    -- back to the persistent cache, which matches on the realm-stripped short name — so an outsider
    -- "Bob-Silvermoon" would resolve onto group member "Bob-Ravencrest"'s GUID and pass. Match the
    -- full realm-qualified name against the live roster instead, which no outsider can satisfy.
    if not KAUtil.IsFullNameInGroup(senderFullName) then return end

    -- A distribution is running on this client: park the request instead of answering it. BULK
    -- traffic does not yield on its own (see the file header on ChatThrottleLib), so answering here
    -- would compete with the very messages the raid is standing still for.
    if not LH.GateOpen() then
        LH.ParkRequest(payload, senderFullName)
        return
    end

    LH.AnswerHistoryRequest(payload, senderFullName)
end

-- The actual answer. Split from LH.HandleHistoryRequest so LH.ParkRequest's release path can call it
-- without going back through the gate check above (see the comment there for why re-entering it would
-- defeat GATE_MAX_PARK).
function LH.AnswerHistoryRequest(payload, senderFullName)
    local theirEpoch, theirSum, sinceTime = payload:match("^(%d+):(%d+):(%d+)$")
    theirEpoch, theirSum, sinceTime = tonumber(theirEpoch), tonumber(theirSum), tonumber(sinceTime)
    if not theirEpoch then return end

    local myEpoch = KART_LootHistoryEpoch or 1
    -- The requester's own epoch travels in the header once again here (see LH.RequestHistorySync).
    -- A returning absentee's request is often the only message that ever reaches the loot owner's
    -- peers about them, so our own epoch rides back regardless of whether we have an entry to go
    -- with it -- otherwise the epoch that matters most would be exactly the one that never arrives.
    KASC:Send("LC_HIST_EPOCH:" .. myEpoch, "WHISPER", senderFullName, { prio = "BULK" })

    -- They are ahead of us. We have nothing they want, and their epoch is news: ask for it properly
    -- rather than adopting a number from an unauthenticated request.
    if theirEpoch > myEpoch then
        LH.heardEpoch = math.max(LH.heardEpoch or 0, theirEpoch)
        return
    end

    LH.historySyncAnswered = LH.historySyncAnswered or {}
    local now = time()
    if now - (LH.historySyncAnswered[senderFullName] or 0) < HISTORY_SYNC_ANSWER_COOLDOWN then return end

    -- Behind us, or diverged at the same epoch: the incremental answer cannot fix either, so send the
    -- whole epoch and let them dedup on id. Matching checksum at the same epoch: they agree with us
    -- and the wire stays empty.
    local full = (theirEpoch < myEpoch) or (theirSum ~= LH.HistoryChecksum())

    -- Throttled to once a night per asker. In this raid people port out mid-distribution and relog
    -- all evening, and every one of those joins asks again -- while a hole appears at most once. Ask
    -- a second time in the same night and you get the incremental answer; the hole is already filled
    -- by then, and if it is not, tomorrow's first join pulls it.
    LH.fullReconciled = LH.fullReconciled or {}
    local lastFull = LH.fullReconciled[senderFullName]
    -- Whether THIS request earns the stamp, decided now; written below only once the answer is known
    -- to be non-empty (matching LH.historySyncAnswered) -- a peer whose own history is empty, or has
    -- nothing surviving the epoch/cutoff filter, sends nothing back, and stamping it anyway would
    -- burn the asker's once-per-night allowance on a no-op: if this peer backfills real entries
    -- later in the same window, the asker's next request would be throttled into the incremental
    -- branch and those entries would not reach it until the cooldown expired.
    local grantFull = false
    if full then
        if lastFull and now - lastFull < HISTORY_FULL_COOLDOWN then
            full = false
            -- The incremental fallback below trusts sinceTime as "everything up to here is already
            -- theirs" -- true for an ordinary relog (SavedVariables persist), but not for an asker
            -- whose own copy is behind an EARLIER full answer we already gave them: an unreliable or
            -- reset sinceTime would then read as "send me everything again", which is exactly the
            -- repeat this cooldown exists to prevent. Floored at the last full answer, not raised
            -- above it: an asker with a genuinely newer sinceTime still gets exactly what changed.
            if sinceTime < lastFull then sinceTime = lastFull end
        else
            grantFull = true
        end
    end
    if not full and sinceTime == nil then return end

    local cutoff = now - HISTORY_SYNC_MAX_AGE
    local toSend = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local inEpoch = (e.epoch or 1) == myEpoch
        local wanted  = full or ((e.time or 0) > sinceTime)
        if inEpoch and wanted and (e.time or 0) > cutoff then table.insert(toSend, e) end
    end
    if #toSend == 0 then return end
    LH.historySyncAnswered[senderFullName] = now
    if grantFull then LH.fullReconciled[senderFullName] = now end

    table.sort(toSend, function(a, b) return (a.time or 0) < (b.time or 0) end)
    while #toSend > HISTORY_SYNC_MAX_ENTRIES do table.remove(toSend, 1) end

    local myKey = (KASC.Identity.ResolvePlayer("player"))
    local head  = string.format("LC_HIST_BATCH:%d:%s:", myEpoch, myKey)
    local first = 1
    while first <= #toSend do
        local count, msg = math.min(HISTORY_BATCH_ENTRIES, #toSend - first + 1), nil
        while true do
            local records = {}
            for i = first, first + count - 1 do records[#records + 1] = EntryRecord(toSend[i]) end
            local plain  = table.concat(records, "\n")
            local packed = LC.PackPayload(head .. "0:" .. plain, plain)
            if not packed then
                -- Small enough that it goes out as one plain message; no block, no ceiling.
                msg = head .. "0:" .. plain
                break
            end
            if LC.UnpackPayload(packed) then
                msg = head .. "1:" .. packed
                break
            end
            if count == 1 then
                -- One record that will not pack small enough on its own. Sent PLAIN instead:
                -- AceComm splits a message of any length and the receiver applies no ceiling to an
                -- unpacked body, so it costs chunks and loses nothing. Dropping it here would be the
                -- award silently never arriving, which is the whole failure this loop exists to
                -- close.
                msg = head .. "0:" .. plain
                break
            end
            count = math.floor(count / 2)
        end
        -- BULK: none of this is urgent, and all of it is exactly the traffic the loot flow must not
        -- wait for.
        KASC:Send(msg, "WHISPER", senderFullName, { prio = "BULK" })
        first = first + count
    end
end

-- Runs on the requester when a peer whispers back a batch of missing entries.
function LH.HandleHistoryBatch(payload, senderKey)
    local epoch, originatorKey, packed, body =
        payload:match("^(%d+):([^:]*):([01]):(.*)$")
    epoch = tonumber(epoch)
    if not epoch or not body then return end
    -- Catch-up entries land in the permanent loot history -- only from someone actually in our group,
    -- not from an arbitrary whisper.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end

    -- See LH.AdmitEpoch: below our epoch, or above it from someone who cannot vouch for a wipe, and
    -- the whole batch is discarded -- not just entries that fail some later filter.
    if not LH.AdmitEpoch(epoch, originatorKey) then return end

    if packed == "1" then
        body = LC.UnpackPayload(body)
        -- nil means the block will not come back as a string at all: too large to be ours, truncated,
        -- foreign or damaged. Treated as "this message says nothing" rather than storing half of it,
        -- and counted, because the alternative is a client that quietly loses a whole catch-up.
        if not body then
            LC.diag = LC.diag or {}
            LC.diag.packedUnreadable = (LC.diag.packedUnreadable or 0) + 1
            return
        end
    end

    for record in body:gmatch("[^\n]+") do
        LH.HandleHistoryEntry(record, senderKey)
    end
end

-- Runs once per record in a batch. Parses and stores one award.
--
-- In practice always reached through LH.HandleHistoryBatch, which already applies LH.AdmitEpoch to
-- the whole batch before looping into this function -- every record in one batch shares its header
-- epoch by construction (LH.AnswerHistoryRequest only ever sends entries at its OWN current epoch).
-- Applied again here anyway, on this record's own epoch field, rather than trusting the caller: this
-- function is reachable on its own (every direct call in this codebase's tests does exactly that),
-- and the one thing that must never happen -- an entry stored above this client's own epoch,
-- invisible to LH.HistoryChecksum forever -- must not depend on which path got here first.
function LH.HandleHistoryEntry(payload, senderKey)
    -- Catch-up entries land in the permanent loot history — only accept them from someone
    -- actually in our current group, not from arbitrary whispers.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    local t, diffID, rollID, classFile, colorPacked, winnerKey, winner, reason, id, epoch, item =
        payload:match("^(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(%d+):(.*)$")
    t = tonumber(t)
    if not t or not winner then return end
    if not LH.AdmitEpoch(tonumber(epoch) or 1, senderKey) then return end
    -- Reject a timestamp from the future. time() is each client's OS clock, so a peer with a badly
    -- set clock (or a hostile one) would otherwise write an entry dated years ahead — which then
    -- becomes the "since" watermark LH.RequestHistorySync sends, permanently asking every peer for
    -- entries newer than that date and silently killing catch-up sync for good.
    if t > time() + 300 then return end
    -- Older than the line the player drew when they last cleared. The request side already asks from
    -- there, but a clear can land between the request and the answer, with the deleted entries
    -- already on their way.
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
    -- The bare pattern takes the whole rest of the field ("^item:.+"), not a character class: a live
    -- bonus list contains commas, and a class-matched fallback would truncate the bare form at the
    -- first one while KAUtil.GetItemString keeps the link form whole — the two sides would stop
    -- reducing to the same key, which is the whole point of this function (B127).
    local function ItemKey(link)
        if type(link) ~= "string" then return nil end
        return KAUtil.GetItemString(link) or link:match("^item:.+")
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

    -- Rule 3: same epoch, new id -> store it. Same id -> we already have this award.
    if id and id ~= "" then
        for _, e in ipairs(KART_LootHistory) do
            if e.id == id then return end
        end
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
        id           = id,
        epoch        = tonumber(epoch) or 1,
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
KASC:RegisterMessage("LC_HIST_BATCH", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) LH.HandleHistoryBatch(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_HIST_EPOCH", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx)
        LH.heardEpoch = math.max(LH.heardEpoch or 0, tonumber(payload) or 0)
        LH.AdoptEpoch(payload, ctx:Key())
    end)

-- See LH.PurgeIfNoEpoch: Core.lua calls it directly from its own ADDON_LOADED block, but this file
-- keeps its own registration too so the purge runs even where Core.lua is not part of the picture.
local purgeFrame = CreateFrame("Frame")
purgeFrame:RegisterEvent("ADDON_LOADED")
purgeFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then LH.PurgeIfNoEpoch() end
end)
