local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")

-- This file's checkbox is built at file load time, before Core.lua's ADDON_LOADED handler has
-- created KART_Settings -- passing the table directly here would freeze it onto nil forever.
-- Passed as `store` instead of the table itself, so KAUI resolves the current global at click
-- time rather than capturing it now (see ResolveStore in KAUI-1.0.lua).
local function SettingsStore() return KART_Settings end

KART.DT = KART.DT or {}
local DT = KART.DT

-- Lookup built from KART_WoWUtilsCache (written by the external KART Companion app, never by
-- this addon) — key is lowercase "name-realm", value is the array of gain candidates for that
-- character. See KART_WoWUtilsCache's schema in the KART Companion project for the full contract.
DT.index = {}

-- WoWUtils' characterId (the exact string KART Companion writes as each cache key) formats the realm
-- as a lowercase slug: spaces become hyphens and apostrophes are dropped, so "Tarren Mill" becomes
-- "tarren-mill" and a full key looks like "thrall-tarren-mill" (confirmed against WoWUtils' OpenAPI
-- spec, example "thrall-tarren-mill", 2026-07-24). GetRealmName() on the addon side returns the
-- DISPLAY name ("Tarren Mill") instead, so a naive name.."-"..realm key ("thrall-tarren mill") would
-- never match the cache for ANY multi-word or apostrophe realm. Canonicalize both sides to the same
-- form by stripping spaces, hyphens and apostrophes out of the realm portion, so the space-vs-hyphen
-- and apostrophe differences collapse away regardless of WoWUtils' exact slug punctuation.
local function CanonicalizeRealm(realm)
    return (realm:gsub("[%s%-']", ""))
end

local function NormalizeKey(name, realm)
    if not name or name == "" then return nil end
    realm = (realm and realm ~= "") and realm or GetRealmName()
    if not realm or realm == "" then return nil end
    -- CaseFold (not :lower()) so umlaut names/realms fold the same way the index is built below — a
    -- name starting with "Ö" would otherwise never match its lowercased "ö" cache key. The single
    -- "-" between name and realm is the ONLY hyphen left (realm hyphens are stripped above), so the
    -- short-name split in FindPlayerCandidates stays unambiguous.
    return KAUtil.CaseFold(name) .. "-" .. KAUtil.CaseFold(CanonicalizeRealm(realm))
end

function DT.RebuildIndex()
    DT.index = {}
    local cache = KART_WoWUtilsCache
    if type(cache) ~= "table" or tonumber(cache.schemaVersion) ~= 1 or type(cache.players) ~= "table" then
        DT.RefreshStatusLabel()
        return
    end
    for key, candidates in pairs(cache.players) do
        if type(key) == "string" and type(candidates) == "table" then
            -- Re-canonicalize the companion's "name-realm-slug" key to the same form NormalizeKey
            -- produces (realm separators stripped). Split on the FIRST hyphen — WoW character names
            -- never contain one, so everything after it is the realm slug.
            local name, realm = key:match("^([^%-]+)%-(.+)$")
            if name and realm then
                DT.index[KAUtil.CaseFold(name) .. "-" .. KAUtil.CaseFold(CanonicalizeRealm(realm))] = candidates
            else
                DT.index[KAUtil.CaseFold(key)] = candidates -- malformed / realm-less key: keep as-is
            end
        end
    end
    DT.RefreshStatusLabel()
end

-- Finds the candidate list for a raid-roster short name. Tries THAT RAIDER's realm first, falling
-- back to a short-name-only match only if it's unambiguous, so two cross-realm namesakes in the
-- cache never silently pick the wrong one.
--
-- `realm` matters and used to be absent. Without it this asked about OUR realm for everybody, and
-- the ambiguity guard below only ever protected the fallback — so a cross-realm raider with a
-- namesake on our own realm got that namesake's key on the first try and the guard never ran. The
-- council then read somebody else's sim number under this raider's name, with no sign anything was
-- wrong, on the one screen that decides who gets the item. The realm was available the whole time:
-- it is UnitName's second return, which the panel discarded while splitting the short name out.
--
-- Empty or missing still means our own realm, which is the right default for the two vote-window
-- call sites — those ask about the player themselves.
local function FindPlayerCandidates(shortName, realm)
    local ownRealmKey = NormalizeKey(shortName, (realm and realm ~= "") and realm or GetRealmName())
    if ownRealmKey and DT.index[ownRealmKey] then return DT.index[ownRealmKey] end

    local shortLower = KAUtil.CaseFold(shortName)
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
--
-- `realm` is that RAIDER's realm, not ours, and leaving it out means our own -- see
-- FindPlayerCandidates for what asking the wrong realm cost.
-- Never errors on missing/malformed cache data — callers must treat nil as "no data".
function DT.GetGainPercent(shortName, itemLink, realm)
    if not shortName or not itemLink then return nil end
    if KART_Settings and KART_Settings.dtModuleEnabled == false then return nil end

    local itemId = C_Item.GetItemInfoInstant(itemLink)
    if not itemId then return nil end
    -- Effective (upgraded) item level of this specific link, not GetItemInfo's 4th return, which is
    -- the item's BASE ilvl — the tie-break below needs the actual rolled ilvl to pick the closest
    -- sim candidate when the same item was simmed at several upgrade tracks.
    local actualIlvl = C_Item.GetDetailedItemLevelInfo(itemLink)

    local candidates = FindPlayerCandidates(shortName, realm)
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
    -- tonumber, not a raw read: this whole table is written by the external companion app, and a
    -- non-numeric timestamp (an ISO-8601 string is the natural thing for an external writer to
    -- produce) would make the arithmetic below throw — from a 60s ticker, so once a minute forever.
    -- A nil here just falls into the "never synced" branch, which is the honest thing to show.
    local syncedAt = tonumber(cache and cache.syncedAt)

    -- Treat a schema-version mismatch as "never synced": RebuildIndex bails and leaves the index
    -- empty in that case, so gains silently don't work — reporting a player count would be a lie.
    if not syncedAt or (cache and tonumber(cache.schemaVersion) ~= 1) then
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
    if diffMin < 1 then relStr = L.DT_TIME_LT1M
    elseif diffMin < 60 then relStr = string.format(L.DT_TIME_MIN, diffMin)
    elseif diffMin < 1440 then relStr = string.format(L.DT_TIME_HOUR, math.floor(diffMin / 60))
    else relStr = string.format(L.DT_TIME_DAY, math.floor(diffMin / 1440)) end

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
    DT.CbModuleEnabled = KART.UI:CreateSettingsCheckbox(parent, {
        name = "KART_DTModuleEnabled", label = L.DT_SET_MODULE_ENABLED,
        store = SettingsStore, key = "dtModuleEnabled", y = -75,
        onChanged = function()
            if KART.LC and KART.LC.Council and KART.LC.Council.RefreshCouncilRows then KART.LC.Council.RefreshCouncilRows() end
        end,
        tooltip = L.DT_DESC_MODULE_ENABLED,
    })
end

-- Fills General Settings, anchored below the Reset button — sync status is about the companion
-- app, not about Loot Council itself, so it lives here rather than next to the toggle above.
function DT.BuildSyncStatus(parent)
    local L = KART.L

    DT.statusLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    DT.statusLabel:SetPoint("TOPLEFT", KART.BtnReset, "BOTTOMLEFT", 0, -20)
    DT.statusLabel:SetWidth(460)
    DT.statusLabel:SetJustifyH("LEFT")
    KART.UI:RegisterLabel(DT.statusLabel)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", DT.statusLabel, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(460)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L.DT_HINT_COMPANION)
    KART.UI:RegisterLabel(hint)

    DT.RefreshStatusLabel()

    -- The "synced Xm ago" relative time is otherwise only recomputed on rebuild/locale change and
    -- would sit stale while the panel stays open — refresh it periodically while it's visible.
    if not DT.statusTicker then
        DT.statusTicker = C_Timer.NewTicker(60, function()
            if DT.statusLabel and DT.statusLabel:IsVisible() then DT.RefreshStatusLabel() end
        end)
    end

    KART.UI:RegisterLocaleRefresher(function()
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
