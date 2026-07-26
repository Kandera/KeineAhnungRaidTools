local addonName, KART = ...
local KAGS = LibStub("KAGS-1.0")
local KASC = LibStub("KASC-1.0")

local KAUI = LibStub("KAUI-1.0")
KART.UI = KAUI:NewNamespace("KART")

-- KART.L itself is a STABLE table — its reference must never be replaced, only its values
-- swapped (files capture `local L = KART.L` at load time and keep that reference). Locale
-- refreshers (functions that re-apply static UI text once the saved language is known) are
-- registered via KART.UI:RegisterLocaleRefresher; Core.lua runs them once at ADDON_LOADED,
-- right after the locale values are copied into KART.L.
KART.L = KART.L or {}

-- Standardeinstellungen
KART.Defaults = {
    inviteKeywords = "inv;+;invite",
    inviteViaGuildChat = false,
    promoteNames = "",
    showRaidleadBar = false,
    lockRaidleadBar = false,
    autoHideRaidleadBar = false,
    pullTimerDuration = 10,
    keybinds = {}, -- filled per-action at runtime (see KART.ApplyKeybinds); nil fields in a table literal are a no-op anyway
    bcModuleEnabled = false,
    showBuffCheck = false,
    buffCheckAlpha = 90,
    bcCombatDelay = 2,
    grayOffline = true,
    minimap = {},
    showMinimapIcon = true,
    autoConvertToRaid = false,
    titleFontSize = 12,
    menuFontSize = 11,
    contentFontSize = 12,
    bgAlpha = 85,
    uiScale = 100, -- whole-window scale in percent (PNG-artwork window is not freely resizable)
    fontName = "Friz Quadrata",
    accentR = 0, accentG = 60, accentB = 100,
    bgR = 10, bgG = 10, bgB = 10,
    language = "Auto",
    lcModuleEnabled = false,
    lcAutoPass = true,
    lcVoteSeconds = 20,
    lcButtonLabels = "BIS;Upgrade;Offspec;Sonstiges;Pass", -- placeholder; localized in Core.lua ADDON_LOADED via LC_DEFAULT_BUTTONS
    lcCouncilMembers = "",
    lcLootmaster = "",
    lcShowNickNames = false,
    lcVoteLayoutCompact = false,
    lcFontSize = 12,
    lcRollsEnabled = false,
    lcVotedItemDisplay = "full",
    wuModuleEnabled = false,
    wuImportText = "",
    dtModuleEnabled = false,
    lcVotePopupPos = false,
    lcCouncilPanelPos = false,
    lcHistoryWindowPos = false,
    lcMinQuality = 4,
    frameStrata = 4, -- index into KART.StrataLevels (4 = HIGH)
    autoLogEnabled = false,
    autoLogRaidLFR = false,
    autoLogRaidNormal = false,
    autoLogRaidHeroic = false,
    autoLogRaidMythic = false,
    autoLogMythicPlus = false,
    autoLogMinKey = 2,
    autoLogDungeons = false,
    autoLogDelves = false,
    autoLogOwned = false, -- hidden: whether the addon (not the player) started the current combat log
}

-- Ordered list of WoW frame strata a KART window may sit on, kept here (rather than only inside
-- KAUI-1.0's own copy) purely so the settings-tab strata slider (MainFrame.lua) has a name list
-- and count to build its range and value display from. The strata registries and the apply/
-- register logic itself live in KAUI-1.0 now; see KART.UI:RegisterStrataFrame et al.
KART.StrataLevels = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

-- Fixed status colors used by the addon's own remaining UI code (BuffChecker gear-check
-- indicators). Kept as plain data (no frame references) so KART.UpdateStyles() and callers can
-- read them fresh on every settings change without caching stale colors. Corner radii, font
-- path, accent color and the widget factories all moved to KAUI-1.0.
KART.SUCCESS = {0.35, 0.75, 0.35}
KART.WARNING = {0.90, 0.70, 0.20}
KART.DANGER  = {0.85, 0.30, 0.30}

function KART.UpdateMinimapButton()
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not dbIcon then return end
    if KART_Settings.showMinimapIcon then
        dbIcon:Show("KeineAhnungRaidTools")
    else
        dbIcon:Hide("KeineAhnungRaidTools")
    end
    -- LibDBIcon only reads minimapPos out of its saved table when told to refresh. A profile switch
    -- swaps that table's contents (Profiles.lua keeps the table's identity for exactly this reason),
    -- so without this the icon keeps the previous profile's angle until the next drag or reload.
    if dbIcon.Refresh then
        pcall(dbIcon.Refresh, dbIcon, "KeineAhnungRaidTools", KART_Settings.minimap)
    end
end

-- The enchant's display NAME for `slot`, read off the item tooltip's "Enchanted: X" line.
--
-- This is the piece that makes the whole exercise verifiable. The item link carries only the numeric
-- id, and a bare number can't be checked against anything — which is how a table of invented ids got
-- shipped in the first place. The name can: it maps straight onto a published list of the tier's
-- enchants, so an id is only ever accepted once its name has been confirmed as one of them.
local function EnchantNameForSlot(slot)
    if not ENCHANTED_TOOLTIP then return nil end ---@diagnostic disable-line: undefined-global
    -- ENCHANTED_TOOLTIP is Blizzard's own localized "Enchanted: %s" template. Escaping it and then
    -- turning its %s into a capture keeps this working on a German client ("Verzaubert: %s") without
    -- hardcoding either language.
    local pattern = "^" .. ENCHANTED_TOOLTIP ---@diagnostic disable-line: undefined-global
        :gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        :gsub("%%%%s", "(.+)")
    KART_GearScanTooltip:ClearLines()
    KART_GearScanTooltip:SetInventoryItem("player", slot)
    for i = 1, KART_GearScanTooltip:NumLines() do
        local fs = _G["KART_GearScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        local name = text and text:match(pattern)
        if name then return name end
    end
    return nil
end

function KART.PrintEnchantDump()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_PERMANENT)
    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            print(string.format("  slot %d: -", slot))
        else
            local enchant = link:match("item:%d+:(%d*):")
            local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            print(string.format("  slot %d: enchant=%s  [%s]  equipLoc=%s  %s",
                slot,
                (enchant and enchant ~= "" and enchant ~= "0") and enchant or "NONE",
                EnchantNameForSlot(slot) or "?",
                tostring(equipLoc),
                C_Item.GetItemInfo(link) or "?"))
        end
    end

    local hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = GetWeaponEnchantInfo()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_TEMPORARY)
    print(string.format("  main hand: has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasMH), tostring(mhID), tostring(mhExp), tostring(KAGS.SlotNeedsOil(16))))
    print(string.format("  off hand:  has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasOH), tostring(ohID), tostring(ohExp), tostring(KAGS.SlotNeedsOil(17))))
end

-- Answers to a raid scan, keyed by short name so a repeated reply replaces rather than double-counts.
KART.EnchantScan = KART.EnchantScan or {}

-- Asks every KART user in the group for their enchant ids and prints the tally a few seconds later.
--
-- READ THIS BEFORE USING THE OUTPUT: the tally shows what the raid WEARS, which is not the same as
-- what is CORRECT. Pasting it into GOOD_ENCHANTS (Libs/KAGS-1.0/KAGS-1.0.lua) would bless whatever
-- outdated enchant someone happens to have — the list would then approve exactly the case the
-- check is meant to catch. There is no in-game API that ranks an enchantID, so correctness can
-- only come from outside the game.
--
-- What it is actually good for is spotting outliers by eye: when eighteen people share an id on a
-- slot and one person has a different one, that one is worth a look. A human reads that; the code
-- must not.
function KART.StartEnchantScan()
    if not IsInGroup() then
        print("|cffff0000KART:|r " .. KART.L.ENCH_SCAN_NOT_IN_GROUP)
        return
    end
    wipe(KART.EnchantScan)
    -- Our own answer: SendAddonMessage never echoes back to its sender.
    KART.EnchantScan[UnitName("player") or "?"] = KAGS.GetOwnEnchantIDs()
    KASC:Send("REQ_ENCH")
    print("|cff00ff00KART:|r " .. KART.L.ENCH_SCAN_START)
    C_Timer.After(5, KART.PrintEnchantScan)
end

function KART.PrintEnchantScan()
    local perSlot, responders = {}, 0
    for _, ids in pairs(KART.EnchantScan) do
        responders = responders + 1
        for slot, id in pairs(ids) do
            perSlot[slot] = perSlot[slot] or {}
            perSlot[slot][id] = (perSlot[slot][id] or 0) + 1
        end
    end

    print("|cff00ff00KART|r " .. string.format(KART.L.ENCH_SCAN_RESULT, responders))
    local order = {}
    for _, s in ipairs(KAGS.ENCHANTABLE_SLOTS) do order[#order + 1] = s end
    order[#order + 1] = "oil"
    for _, slot in ipairs(order) do
        local counts = perSlot[slot]
        if counts then
            local list = {}
            for id, n in pairs(counts) do list[#list + 1] = { id = id, n = n } end
            -- Most-used first, so the common enchants read as the accepted set and any one-off
            -- (the likely outdated one) sits at the end.
            table.sort(list, function(a, b)
                if a.n ~= b.n then return a.n > b.n end
                return a.id < b.id
            end)
            local parts = {}
            for _, e in ipairs(list) do parts[#parts + 1] = e.id .. " (x" .. e.n .. ")" end
            print(string.format("  %s: %s", tostring(slot), table.concat(parts, ", ")))
        end
    end
end

-- Keybind action list: shared between ApplyKeybinds and the settings-tab bind UI so both
-- stay in sync with a single source of truth for which 4 actions are bindable. Lives in
-- Utils.lua (rather than RaidleadBar.lua where ApplyKeybinds is defined) because it loads
-- before MainFrame.lua, which reads it at file-load time to build the keybind settings card.
KART.KeybindActions = {
    { key = "readyCheck", button = "KART_RL_ReadyCheckBtn" },
    { key = "clearWorldMarkers", button = "KART_RL_ClearWorldMarkersBtn" },
    { key = "pullTimer", button = "KART_RL_PullTimerBtn" },
    { key = "buffCheckToggle", button = "KART_RL_BuffCheckToggleBtn" },
}

-- Maps each of the 6 main-window tab-content panels to its ShowTab index. Used by
-- KART.BuildSearchIndex to figure out which tab a given label belongs to, by walking up the
-- label's parent chain until one of these panels is found.
local SEARCH_TAB_PANELS = {
    { panel = "PromotePanel", tabIndex = 1 },
    { panel = "RaidleadPanel", tabIndex = 2 },
    { panel = "BuffCheckPanel", tabIndex = 3 },
    { panel = "SettingsPanel", tabIndex = 4 },
    { panel = "LootCouncilPanel", tabIndex = 5 },
    { panel = "WoWUtilsPanel", tabIndex = 6 },
}

-- Builds the settings search index by walking KART.UI's label registry — every settings label
-- already gets registered there by its creation site (checkboxes, sliders, card titles, hints,
-- tab titles), so no per-widget registration is needed here. A label whose parent chain never
-- reaches one of the 6 main tab panels (e.g. one that belongs to a popup window like Loot
-- History) is silently skipped, which is how "only the 6 main tabs are searchable" enforces itself.
function KART.BuildSearchIndex()
    local index = {}
    for _, fs in ipairs(KART.UI:GetLabels()) do
        local text = fs:GetText()
        -- Skip hidden labels: a FontString keeps its text after :Hide(), so a conditionally-shown one
        -- (e.g. the council pending-resolution label) would stay searchable and its result row would
        -- scroll to and highlight an invisible, zero-content strip of the panel.
        if text and text ~= "" and fs:IsShown() then
            local ancestor = fs:GetParent()
            local tabIndex
            while ancestor and not tabIndex do
                for _, entry in ipairs(SEARCH_TAB_PANELS) do
                    if ancestor == KART[entry.panel] then
                        tabIndex = entry.tabIndex
                        break
                    end
                end
                ancestor = ancestor:GetParent()
            end
            if tabIndex then
                table.insert(index, { text = text, tabIndex = tabIndex, widget = fs })
            end
        end
    end
    return index
end
