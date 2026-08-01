-- WoW runs Lua 5.1. Every WoW API the addon touches is declared read-only here; the addon's
-- own SavedVariables are declared writable. Anything not listed is reported as an undefined
-- global, which is what catches a typo in a global name.
std = "lua51"
max_line_length = false
exclude_files = { "Libs/LibStub/" } -- vendored verbatim, not ours to lint

-- WoW hands every event/callback a fixed signature; addon code routinely ignores arguments
-- it doesn't need (e.g. `event` in an OnEvent handler). That is normal WoW addon style, not
-- a defect, so this category is disabled globally rather than annotated at each call site.
unused_args = false

-- Two blanket suppressions on the unchanged tree, both config-level so no addon file is touched:
--   211/addonName: every addon file destructures WoW's file-load vararg as (addonName, KART);
--     files that only need the table leave addonName unused by the load convention itself.
--   611, 612: pre-existing trailing/blank-line whitespace noise in a few files, orthogonal to
--     correctness -- fixing it would mean editing addon .lua files, which this task must not do.
ignore = { "211/addonName", "611", "612" }

-- The harness deliberately installs globals: run.lua exports the assertion helpers as T and
-- wow_stubs.lua exports the roster controls as KARTTEST, so every test file can use them
-- without a require. Declared here rather than excluding tests/ from linting altogether.
files["tests/"] = {
    globals = { "T", "KARTTEST", "NSAPI", "UIParent", "C_ChatInfo", "C_Item", "strmatch",
                "wipe", "UnitExists", "UnitName", "UnitGUID", "UnitIsGroupLeader",
                "UnitIsGroupAssistant", "IsInRaid", "IsInGroup", "GetNumGroupMembers",
                "Ambiguate", "GetRealmName", "GetNormalizedRealmName", "GetTime",
                "GetInventoryItemLink", "GetWeaponEnchantInfo", "GetAverageItemLevel",
                "CreateFrame", "time", "PixelUtil", "GetPhysicalScreenSize" },
}

-- MainFrame.lua:850 shadows the upvalue `L` (the locale table) from line 2. Single occurrence
-- in the whole tree; a real but narrow finding, reported as a concern rather than fixed here --
-- Task 1 vendors checks against unchanged code and must not edit addon files to satisfy them.
files["MainFrame.lua"] = { ignore = { "431" } }

globals = {
    -- SavedVariables
    "KART_Settings", "KART_LootHistory", "KART_LootHistoryClearedAt", "KART_LCOfficerNotes", "KART_WoWUtilsCache",
    "KART_Profiles", "KART_PlayerCache", "KART_LCTrades", "KART_LCSession",
    -- Named frames created by the addon and reached through _G
    "KART_GearScanTooltip",
    -- Addon-owned slash command registration
    "SLASH_KART1",
    -- Blizzard-provided table that addons are expected to add entries to, not just read
    "SlashCmdList",
    -- Blizzard-provided table that addons are expected to add named popups to, not just read
    "StaticPopupDialogs",
}

read_globals = {
    -- Libraries
    "LibStub", "NSAPI",
    -- WoW string/table aliases
    "strmatch", "wipe", "time", "date",
    -- Core API
    "CreateFrame", "UIParent", "GameTooltip", "GameFontHighlightSmall", "Item", "PixelUtil",
    "InCombatLockdown", "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
    -- Secret values (Midnight): data the client refuses to let an addon read. Absent on older
    -- clients, which is why KAUtil.IsSecret tests for it rather than calling it outright.
    "issecretvalue",
    "GetCursorInfo", "CreateColor", "ReloadUI", "SetCVar",
    "C_Timer", "C_PartyInfo", "C_BattleNet", "C_Container", "C_UnitAuras",
    "UISpecialFrames", "UIErrorsFrame", "ShoppingTooltip1", "ShoppingTooltip2",
    -- Unit / group API
    "UnitName", "UnitGUID", "UnitExists", "UnitClass", "UnitIsGroupLeader", "UnitIsGroupAssistant",
    "UnitIsUnit", "UnitIsConnected", "IsInRaid", "IsInGroup", "IsInGuild", "GetNumGroupMembers",
    "Ambiguate", "GetGuildInfo", "PromoteToAssistant", "UninviteUnit",
    "ClearOverrideBindings", "SetOverrideBindingClick", "GetReadyCheckStatus", "ConfirmReadyCheck",
    "GetRealmName", "GetNormalizedRealmName", "GetLocale", "GetInstanceInfo", "GetDifficultyInfo",
    -- Items / trade
    "GetInventoryItemLink", "GetAverageItemLevel", "GetWeaponEnchantInfo",
    "CheckInteractDistance", "InitiateTrade", "GetTradePlayerItemLink", "GetTradeTargetItemLink", "ClickTradeButton",
    "LE_GAME_ERR_TRADE_COMPLETE",
    -- Loot rolls
    "GetLootRollItemLink", "GetLootRollItemInfo", "RollOnLoot",
    -- Chat / time / misc
    "SendChatMessage", "GetTime", "LoggingCombat", "hooksecurefunc",
    "ColorPickerFrame", "StaticPopup_Show", "AddonCompartmentFrame", "MenuUtil",
    "C_ChatInfo", "C_Item", "C_AddOns", "C_ChallengeMode", "C_TransmogCollection",
    "C_MountJournal", "C_PetJournal", "C_ToyBox",
    "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
    -- Global string/color constants
    "YES", "NO", "ACCEPT", "CANCEL", "OKAY", "CLOSE", "UNKNOWN", "ENCHANTED_TOOLTIP",
    "CLASS_ICON_TEXCOORDS", "RAID_CLASS_COLORS", "ITEM_QUALITY_COLORS",
}
