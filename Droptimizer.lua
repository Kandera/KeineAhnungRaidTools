local addonName, KART = ...

KART.DT = KART.DT or {}
local DT = KART.DT

-- Lookup built from KART_WoWUtilsCache (written by the external KART Companion app, never by
-- this addon) — key is lowercase "name-realm", value is the array of gain candidates for that
-- character. See KART_WoWUtilsCache's schema in the KART Companion project for the full contract.
DT.index = {}

local function NormalizeKey(name, realm)
    if not name or name == "" then return nil end
    realm = (realm and realm ~= "") and realm or GetRealmName()
    if not realm or realm == "" then return nil end
    return (name .. "-" .. realm):lower()
end

function DT.RebuildIndex()
    DT.index = {}
    local cache = KART_WoWUtilsCache
    if type(cache) ~= "table" or cache.schemaVersion ~= 1 or type(cache.players) ~= "table" then
        DT.RefreshStatusLabel()
        return
    end
    for key, candidates in pairs(cache.players) do
        if type(key) == "string" and type(candidates) == "table" then
            DT.index[key:lower()] = candidates
        end
    end
    DT.RefreshStatusLabel()
end

-- Finds the candidate list for a raid-roster short name. Tries the player's own realm first
-- (the common case); falls back to a short-name-only match only if it's unambiguous, so two
-- cross-realm namesakes in the cache never silently pick the wrong one.
local function FindPlayerCandidates(shortName)
    local ownRealmKey = NormalizeKey(shortName, GetRealmName())
    if ownRealmKey and DT.index[ownRealmKey] then return DT.index[ownRealmKey] end

    local shortLower = shortName:lower()
    local match, matchCount = nil, 0
    for key, candidates in pairs(DT.index) do
        if key:match("^([^%-]+)") == shortLower then
            matchCount = matchCount + 1
            match = candidates
        end
    end
    if matchCount == 1 then return match end
    return nil
end

-- Returns gainPct, source for the given player/item, or nil if there's no sim data for it.
-- Never errors on missing/malformed cache data — callers must treat nil as "no data".
function DT.GetGainPercent(shortName, itemLink)
    if not shortName or not itemLink then return nil end
    if KART_Settings and KART_Settings.dtModuleEnabled == false then return nil end

    local itemId = C_Item.GetItemInfoInstant(itemLink)
    if not itemId then return nil end
    local _, _, _, actualIlvl = C_Item.GetItemInfo(itemLink)

    local candidates = FindPlayerCandidates(shortName)
    if not candidates then return nil end

    local matches = {}
    for _, c in ipairs(candidates) do
        if type(c) == "table" and c.itemId == itemId and type(c.gainPct) == "number" then
            table.insert(matches, c)
        end
    end
    if #matches == 0 then return nil end
    if #matches == 1 then return matches[1].gainPct, matches[1].source end

    -- Same item can appear more than once (different ilvl/upgrade track, or a trinket that
    -- fits both trinket1/trinket2): prefer whichever candidate's ilvl is closest to the item
    -- actually being rolled; if that's unknown, fall back to the largest gain among them.
    if actualIlvl then
        local best
        for _, c in ipairs(matches) do
            if type(c.ilvl) == "number" and (not best or math.abs(c.ilvl - actualIlvl) < math.abs(best.ilvl - actualIlvl)) then
                best = c
            end
        end
        if best then return best.gainPct, best.source end
    end

    local best = matches[1]
    for _, c in ipairs(matches) do
        if (c.gainPct or -math.huge) > (best.gainPct or -math.huge) then best = c end
    end
    return best.gainPct, best.source
end

-- =====================================================================
--  Settings  (no dedicated tab — the toggle lives in Loot Council's settings,
--  next to its other personal-preference checkboxes; sync status lives in
--  General Settings, since it's about the companion app, not Loot Council itself)
-- =====================================================================

function DT.RefreshStatusLabel()
    if not DT.statusLabel then return end
    local L = KART.L
    local cache = KART_WoWUtilsCache
    local syncedAt = cache and cache.syncedAt

    if not syncedAt then
        DT.statusLabel:SetText(L.DT_STATUS_NEVER_SYNCED)
        DT.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        return
    end

    local playerCount = 0
    if type(cache.players) == "table" then
        for _ in pairs(cache.players) do playerCount = playerCount + 1 end
    end

    local diffMin = math.floor((time() - syncedAt) / 60)
    local relStr
    if diffMin < 1 then relStr = "<1m"
    elseif diffMin < 60 then relStr = diffMin .. "m"
    elseif diffMin < 1440 then relStr = math.floor(diffMin / 60) .. "h"
    else relStr = math.floor(diffMin / 1440) .. "d" end

    DT.statusLabel:SetText(string.format(L.DT_STATUS_SYNCED_FORMAT, relStr, playerCount))
    DT.statusLabel:SetTextColor(0.6, 0.9, 0.6)
end

-- Fills the -75 slot reserved for this in LC.BuildSettingsPanel (LootCouncil.lua), inside the
-- personal-preferences card, right below CbAutoPass — a personal preference like that one, not
-- raid-wide, so it doesn't belong in the raid-wide box.
function DT.BuildLootCouncilToggle(parent)
    local L = KART.L

    -- Master switch: fully disables the gain% column in Loot Council. The addon never holds a
    -- WoWUtils credential itself — all networking happens in the external KART Companion app,
    -- which only hands data to us via KART_WoWUtilsCache.
    DT.CbModuleEnabled = KART.CreateSettingsCheckbox(
        parent, "KART_DTModuleEnabled",
        L.DT_SET_MODULE_ENABLED, "dtModuleEnabled", -75, function()
            if KART.LC and KART.LC.Council and KART.LC.Council.RefreshCouncilRows then KART.LC.Council.RefreshCouncilRows() end
        end, L.DT_DESC_MODULE_ENABLED)
end

-- Fills General Settings, anchored below the Reset button — sync status is about the companion
-- app, not about Loot Council itself, so it lives here rather than next to the toggle above.
function DT.BuildSyncStatus(parent)
    local L = KART.L

    DT.statusLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    DT.statusLabel:SetPoint("TOPLEFT", KART.BtnReset, "BOTTOMLEFT", 0, -20)
    DT.statusLabel:SetWidth(460)
    DT.statusLabel:SetJustifyH("LEFT")
    table.insert(KART.DynamicLabels, DT.statusLabel)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", DT.statusLabel, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(460)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L.DT_HINT_COMPANION)
    table.insert(KART.DynamicLabels, hint)

    DT.RefreshStatusLabel()

    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        if DT.CbModuleEnabled then
            DT.CbModuleEnabled.text:SetText(Lx.DT_SET_MODULE_ENABLED)
            DT.CbModuleEnabled.tooltipText = Lx.DT_DESC_MODULE_ENABLED
        end
        hint:SetText(Lx.DT_HINT_COMPANION)
        DT.RefreshStatusLabel()
    end)
end

-- Droptimizer.lua loads after MainFrame.lua and LootCouncil.lua, so both panels (and
-- KART.BtnReset, built inline in MainFrame.lua) already exist here.
if KART.LootCouncilPanel then
    DT.BuildLootCouncilToggle(KART.LC.SettingsCard or KART.LootCouncilPanel)
end
if KART.SettingsPanel then
    -- Parent to the color/reset card (not the bare panel) so the sync status renders above
    -- the card's backdrop instead of underneath it.
    DT.BuildSyncStatus(KART.SettingsColorCard or KART.SettingsPanel)
end
