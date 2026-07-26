-- Minimal WoW API surface for the offline harness. Deliberately incomplete: only what the
-- libraries touch at load time or on the code paths under test. A test that reaches beyond
-- this should fail loudly rather than pass against a convincing fake.

_G.strmatch = string.match
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- Group roster ------------------------------------------------------------------------
-- Members are { name =, realm =, guid =, nickname = }. Unit tokens are generated to match
-- KAUtil.EachGroupUnit's scheme exactly: raid1..raidN in a raid, party1..partyN-1 plus
-- "player" in a party.
local roster, isRaid, count = {}, false, 0

_G.KARTTEST = {}

function KARTTEST.SetRaid(members)
    roster, isRaid, count = {}, true, #members
    for i, m in ipairs(members) do roster["raid" .. i] = m end
end

function KARTTEST.SetParty(members)
    roster, isRaid, count = {}, false, #members
    for i, m in ipairs(members) do
        roster[i == #members and "player" or ("party" .. i)] = m
    end
end

function KARTTEST.SetNSAPI(enabled)
    _G.NSAPI = enabled and {
        GetName = function(_, unit)
            local m = roster[unit]
            return m and m.nickname or nil
        end,
    } or nil
end

KARTTEST.SetRaid({})
KARTTEST.SetNSAPI(false)

-- Unit API ----------------------------------------------------------------------------
function _G.UnitExists(unit) return roster[unit] ~= nil end
function _G.UnitName(unit)
    local m = roster[unit]
    if not m then return nil end
    return m.name, m.realm
end
function _G.UnitGUID(unit) return roster[unit] and roster[unit].guid or nil end
function _G.UnitIsGroupLeader(unit) return roster[unit] and roster[unit].leader or false end
function _G.UnitIsGroupAssistant(unit) return roster[unit] and roster[unit].assist or false end
function _G.IsInRaid() return isRaid end
function _G.IsInGroup() return count > 0 end
function _G.GetNumGroupMembers() return count end
function _G.Ambiguate(name, mode)
    if mode == "none" then return name end
    return (name:match("^([^%-]+)")) or name
end

-- Realm -------------------------------------------------------------------------------
KARTTEST.realm = "TarrenMill"
function _G.GetRealmName() return KARTTEST.realm end
function _G.GetNormalizedRealmName() return KARTTEST.realm end

-- Time --------------------------------------------------------------------------------
KARTTEST.now = 1000
function _G.GetTime() return KARTTEST.now end
_G.time = os.time

-- Frames ------------------------------------------------------------------------------
-- No-op frame: enough for a library that creates an event frame or a scanning tooltip at
-- load time. Any method call returns the frame itself so chains do not blow up. A few
-- methods get real behavior on top of that, because the settings-widget store-binding tests
-- need to drive them:
--   SetScript/GetScript actually store and retrieve a handler, so a test can pull out the
--   exact OnClick/OnValueChanged callback a factory registered and call it directly.
--   SetChecked/GetChecked round-trip a real boolean, since a checkbox's OnClick handler reads
--   self:GetChecked() to decide what value to write.
--   GetWidth/GetHeight return 0, a freshly created frame's real starting size, so a size
--   comparison (e.g. "skip rounding a frame this small") sees a number instead of the
--   catch-all's frame-returning stub.
-- HookScript is deliberately left on the catch-all: nothing under test invokes a hooked
-- handler, only ordinary SetScript ones, so a real implementation isn't needed yet.
local frameMeta
frameMeta = {
    __index = function(t, k)
        local fn = function(...) return t end
        rawset(t, k, fn)
        return fn
    end,
}
-- KAGS creates one real GameTooltip-templated frame at load time, named "KART_GearScanTooltip",
-- and reads its lines back out of _G["KART_GearScanTooltipTextLeft"<i>]:GetText(). Give that one
-- frame real ClearLines/SetInventoryItem/NumLines behavior, driven by a settable table of lines
-- per slot, so KAGS.CountMissingGear's socket check (and Utils.lua's enchant-name lookup) can
-- actually be exercised. Deliberately narrow: SetInventoryItem's unit argument is ignored (every
-- caller passes "player"), and a test asking for more lines than TOOLTIP_MAX_LINES fails loudly
-- rather than silently truncating.
KARTTEST.tooltipLines = {} -- [slot] = { "line 1", "line 2", ... }
local TOOLTIP_MAX_LINES = 20
local function InstallScanTooltip(f)
    local lines = {}
    function f:ClearLines() lines = {} end
    function f:SetInventoryItem(_, slot) lines = KARTTEST.tooltipLines[slot] or {} end
    function f:NumLines() return #lines end
    for i = 1, TOOLTIP_MAX_LINES do
        _G["KART_GearScanTooltipTextLeft" .. i] = { GetText = function() return lines[i] end }
    end
end

function _G.CreateFrame(_, name, _, _)
    local f = setmetatable({}, frameMeta)
    if name then _G[name] = f end

    local scripts = {}
    function f:SetScript(scriptType, handler) scripts[scriptType] = handler; return f end
    function f:GetScript(scriptType) return scripts[scriptType] end

    local checked = false
    function f:SetChecked(value) checked = not not value; return f end
    function f:GetChecked() return checked end

    function f:GetWidth() return 0 end
    function f:GetHeight() return 0 end

    if name == "KART_GearScanTooltip" then InstallScanTooltip(f) end

    return f
end
_G.UIParent = setmetatable({}, frameMeta)

-- Chat --------------------------------------------------------------------------------
KARTTEST.sent = {}
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
        KARTTEST.sent[#KARTTEST.sent + 1] =
            { prefix = prefix, msg = msg, channel = channel, target = target }
    end,
}
function KARTTEST.ClearSent() KARTTEST.sent = {} end

-- Items -------------------------------------------------------------------------------
KARTTEST.inventory = {}   -- [slot] = itemLink
function _G.GetInventoryItemLink(_, slot) return KARTTEST.inventory[slot] end
KARTTEST.weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
function _G.GetWeaponEnchantInfo() return unpack(KARTTEST.weaponEnchant) end
function _G.GetAverageItemLevel() return 0, KARTTEST.equippedIlvl or 0 end
-- [link] = equip location string (e.g. "INVTYPE_WEAPONMAINHAND"), so a test can give a fake
-- item link a configurable equip location without a real client's item database.
KARTTEST.equipLocs = {}
_G.C_Item = {
    GetItemInfoInstant = function(link) return nil, nil, nil, KARTTEST.equipLocs[link] end,
}

-- Socket text globals: KAGS scans _G for every "EMPTY_SOCKET_*" string rather than hardcoding
-- them, so the harness needs at least one to exercise that path.
_G.EMPTY_SOCKET_PRISMATIC = "Prismatic Socket"
