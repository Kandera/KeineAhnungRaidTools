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
-- "player" is not a fixed row. tests/raidsim.lua runs several real clients in one process, and each
-- of them has to see itself when it asks about "player" -- that is what makes an addon message
-- sent by one and received by another mean different things on each side. KARTTEST.activeUnit is
-- the unit token of whichever client's code is currently executing; with it unset (every other
-- test file) "player" behaves as it always did.
KARTTEST.activeUnit = nil
local function resolve(unit)
    if unit == "player" and KARTTEST.activeUnit then unit = KARTTEST.activeUnit end
    return roster[unit]
end

function _G.UnitExists(unit) return resolve(unit) ~= nil end
function _G.UnitName(unit)
    local m = resolve(unit)
    if not m then return nil end
    return m.name, m.realm
end
function _G.UnitGUID(unit) local m = resolve(unit) return m and m.guid or nil end
function _G.UnitIsGroupLeader(unit) local m = resolve(unit) return m and m.leader or false end
function _G.UnitIsGroupAssistant(unit) local m = resolve(unit) return m and m.assist or false end
function _G.UnitIsConnected(unit) local m = resolve(unit) return m == nil or m.offline ~= true end
function _G.UnitClass(unit)
    local m = resolve(unit)
    if not m then return nil end
    return m.class or "WARRIOR", m.classFile or m.class or "WARRIOR"
end
function _G.UnitIsUnit(a, b)
    local ma, mb = resolve(a), resolve(b)
    return ma ~= nil and ma == mb
end

-- Timers ------------------------------------------------------------------------------
-- Driven, not real: a test advances the clock deliberately so a retry or a confirmation delay can
-- be observed instead of waited for. KARTTEST.now is the same clock GetTime() reports.
KARTTEST.timers = {}

-- A delayed callback belongs to the client that scheduled it, and must run as that client -- the
-- session prompt, the raid-exit confirmation and the config retry are all C_Timer.After work that
-- asks who "player" is and sends addon messages. Firing them with nobody active made a raid-exit
-- confirmation re-read the group as still grouped and cancel itself. tests/raidsim.lua fills these
-- two hooks in; with no simulator loaded they stay nil and timers behave as they always did.
KARTTEST.CaptureContext = nil   -- () -> token describing whoever is executing now
KARTTEST.RestoreContext = nil   -- (token) -> the token that was in force before

local function captureContext()
    return KARTTEST.CaptureContext and KARTTEST.CaptureContext() or nil
end

_G.C_Timer = {
    After = function(delay, fn)
        KARTTEST.timers[#KARTTEST.timers + 1] =
            { at = KARTTEST.now + (delay or 0), fn = fn, ctx = captureContext() }
    end,
    NewTicker = function(_, fn) return { Cancel = function() end, _fn = fn } end,
    NewTimer = function(delay, fn)
        local entry = { at = KARTTEST.now + (delay or 0), fn = fn, ctx = captureContext() }
        KARTTEST.timers[#KARTTEST.timers + 1] = entry
        return { Cancel = function() entry.fn = function() end end }
    end,
}

-- Advances the clock by `seconds` and fires everything due, in time order. Returns how many ran.
function KARTTEST.AdvanceTime(seconds)
    local target = KARTTEST.now + (seconds or 0)
    local ran = 0
    while true do
        table.sort(KARTTEST.timers, function(a, b) return a.at < b.at end)
        local next_ = KARTTEST.timers[1]
        if not next_ or next_.at > target then break end
        table.remove(KARTTEST.timers, 1)
        KARTTEST.now = next_.at
        local restore = KARTTEST.RestoreContext
        local prev = restore and restore(next_.ctx)
        next_.fn()
        if restore then restore(prev) end
        ran = ran + 1
    end
    KARTTEST.now = target
    return ran
end
-- One client's group APIs can be made to disagree with the rest of the raid's. Two real situations
-- need that: someone who actually ports out, and -- the one that cost a session mid-boss -- the
-- moment during any roster change where the APIs briefly report no group at all on ONE machine
-- while everyone else reads normally. A shared flag cannot express either.
KARTTEST.solo = {} -- [unitToken] = true: this client alone reads the world as ungrouped
local function isSolo()
    return KARTTEST.activeUnit ~= nil and KARTTEST.solo[KARTTEST.activeUnit] == true
end
function _G.IsInRaid() if isSolo() then return false end return isRaid end
function _G.IsInGroup() if isSolo() then return false end return count > 0 end
function _G.GetNumGroupMembers() if isSolo() then return 0 end return count end
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
-- Unknown keys return a value that is BOTH callable and indexable, because addon code uses frames
-- both ways: `f:SetPoint(...)` is a method, `f.bg:SetAlpha(...)` is a child region created earlier
-- by a factory. A plain function covered the first and broke on the second. Calling one returns its
-- first argument, which for a method call is the frame itself, so chains keep working.
local frameMeta
frameMeta = {
    __index = function(t, k)
        local child = setmetatable({}, frameMeta)
        rawset(t, k, child)
        return child
    end,
    __call = function(_, first) return first end,
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

    -- Getters that must answer with something other than a frame, or callers that build strings and
    -- run loops from them go wrong in ways that look nothing like their cause -- a name concatenated
    -- into a lookup, a region count driving a for loop.
    function f:GetName() return name end
    function f:GetObjectType() return "Frame" end
    function f:GetNumRegions() return 0 end
    function f:GetNumPoints() return 0 end
    function f:GetRegions() return nil end
    function f:GetID() return 0 end

    local shown = true
    function f:Show() shown = true; return f end
    function f:Hide() shown = false; return f end
    function f:SetShown(v) shown = not not v; return f end
    function f:IsShown() return shown end
    function f:IsVisible() return shown end

    local text = ""
    function f:SetText(v) text = tostring(v or ""); return f end
    function f:GetText() return text end
    -- Layout code sizes badges and columns from measured text, so this has to be a number. Roughly
    -- font-size-agnostic: enough that "wider text is wider" holds, which is all any caller asks.
    function f:GetStringWidth() return #text * 6 end
    function f:GetStringHeight() return 12 end

    -- Scale and backdrop get real behavior for the pixel-border tests: SetPixelBackdrop reads the
    -- frame's effective scale to size its border, and RefreshPixelBorders has to hand the colors
    -- back over a SetBackdrop that drops them. Effective scale is the UI scale times the frame's
    -- own, which is all the real parent chain amounts to here (KART sets a scale on top-level
    -- windows only).
    local scale = 1
    function f:SetScale(value) scale = value; return f end
    function f:GetScale() return scale end
    function f:GetEffectiveScale() return KARTTEST.uiScale * scale end

    local backdrop, bg, edge
    function f:SetBackdrop(t) backdrop = t; return f end
    function f:GetBackdrop() return backdrop end
    -- `return bg and unpack(bg)` would truncate to a single value: these getters return all four
    -- components or nothing at all, like the real ones.
    function f:SetBackdropColor(...) bg = { ... }; return f end
    function f:GetBackdropColor() if bg then return unpack(bg) end end
    function f:SetBackdropBorderColor(...) edge = { ... }; return f end
    function f:GetBackdropBorderColor() if edge then return unpack(edge) end end

    if name == "KART_GearScanTooltip" then InstallScanTooltip(f) end

    return f
end
_G.UIParent = _G.CreateFrame("Frame")

-- Screen geometry -----------------------------------------------------------------------
-- Two numbers drive every pixel-border test: the physical screen height, and the UI scale that
-- WoW (or, in the reported case, some other addon) has put on UIParent. Their ratio decides how
-- many physical pixels one UI unit is worth -- exactly 1 when the scale matches the resolution,
-- 0.75 on the client that reported B23.
KARTTEST.physW, KARTTEST.physH = 1920, 1080
KARTTEST.uiScale = 768 / 1080 -- the value WoW picks itself, i.e. pixel-perfect

function _G.GetPhysicalScreenSize() return KARTTEST.physW, KARTTEST.physH end

-- Mirrors Blizzard's PixelUtil: the factor is 768 / physical height, set whenever the UI scale
-- changes, and GetNearestPixelSize converts a size in one frame's units to the nearest whole
-- number of physical pixels and back.
_G.PixelUtil = {
    GetPixelToUIUnitFactor = function() return 768 / KARTTEST.physH end,
    GetNearestPixelSize = function(uiUnitSize, layoutScale, minPixels)
        local factor = 768 / KARTTEST.physH
        local numPixels = math.floor(uiUnitSize * layoutScale / factor + 0.5)
        if minPixels then
            if uiUnitSize < 0 then
                if numPixels > -minPixels then numPixels = -minPixels end
            elseif numPixels < minPixels then
                numPixels = minPixels
            end
        end
        return numPixels * factor / layoutScale
    end,
}

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

-- Item database ------------------------------------------------------------------------
-- Registered by a test, keyed by itemID. Fixtures are taken from the guild's real loot history
-- rather than invented, so classID/subclassID are the values the live client actually reports.
KARTTEST.items = {} -- [itemID] = { name =, link =, quality =, ilvl =, classID =, subclassID =, equipLoc =, bind =, cached = }

function KARTTEST.AddItem(def)
    KARTTEST.items[def.id] = def
    def.link = def.link or ("|cffa335ee|Hitem:" .. def.id .. "::::::::80:::::|h[" .. def.name .. "]|h|r")
    return def
end

local function itemIDOf(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    return tonumber(v:match("item:(%d+)"))
end

local function itemOf(v)
    local id = itemIDOf(v)
    return id and KARTTEST.items[id] or nil
end

-- An uncached item answers nil from GetItemInfo, exactly as the live client does before the server
-- has sent it -- which is the state the "???" bug lived in.
_G.C_Item = {
    GetItemInfo = function(v)
        local it = itemOf(v)
        if not it or it.cached == false then return nil end
        return it.name, it.link, it.quality, it.ilvl, nil, nil, nil, nil, it.equipLoc,
               nil, nil, it.classID, it.subclassID, it.bind
    end,
    GetItemInfoInstant = function(v)
        local it = itemOf(v)
        -- Falls back to the flat equipLocs table the gear-scan tests drive, which predates the item
        -- database and only ever needed the fourth return.
        if not it then return nil, nil, nil, KARTTEST.equipLocs[v] end
        return it.id, nil, nil, it.equipLoc, nil, it.classID, it.subclassID
    end,
    GetItemIconByID = function(v)
        local it = itemOf(v)
        return it and ("Interface\\Icons\\" .. it.name) or nil
    end,
}

-- Item:CreateFromItemID():ContinueOnItemLoad(cb) -- the event-driven escape the addon uses when
-- polling has given up. The callback fires when a test marks the item cached.
KARTTEST.pendingItemLoads = {}
local function itemLoader(id)
    return {
        ContinueOnItemLoad = function(_, cb)
            local it = KARTTEST.items[id]
            if it and it.cached ~= false then return cb() end
            KARTTEST.pendingItemLoads[id] = KARTTEST.pendingItemLoads[id] or {}
            table.insert(KARTTEST.pendingItemLoads[id], cb)
        end,
        GetItemID = function() return id end,
    }
end

_G.Item = {
    CreateFromItemID   = function(_, id) return itemLoader(type(id) == "number" and id or itemIDOf(id)) end,
    CreateFromItemLink = function(_, link) return itemLoader(itemIDOf(link)) end,
}
-- Called both as Item:CreateFromItemID(id) and Item.CreateFromItemID(id) in the wild; accept either
-- by ignoring a leading self that is the Item table itself.
local rawCreateID, rawCreateLink = _G.Item.CreateFromItemID, _G.Item.CreateFromItemLink
_G.Item.CreateFromItemID = function(a, b) if a == _G.Item then return rawCreateID(a, b) end return rawCreateID(nil, a) end
_G.Item.CreateFromItemLink = function(a, b) if a == _G.Item then return rawCreateLink(a, b) end return rawCreateLink(nil, a) end

function KARTTEST.CacheItem(id)
    local it = KARTTEST.items[id]
    if it then it.cached = true end
    for _, cb in ipairs(KARTTEST.pendingItemLoads[id] or {}) do cb() end
    KARTTEST.pendingItemLoads[id] = nil
end

-- Blizzard's group loot ------------------------------------------------------------------
-- [rollID] = { itemID =, canNeed =, canTransmog =, live = }. `live` false models a roll this client
-- never got or that has already been rolled -- the case LC.HandleStart exists for.
KARTTEST.lootRolls = {}
KARTTEST.rolled = {}   -- [rollID] = { [unitToken] = rollType }

function _G.GetLootRollItemInfo(rollID)
    local r = KARTTEST.lootRolls[rollID]
    if not r or r.live == false then return nil end
    local it = KARTTEST.items[r.itemID]
    return "Interface\\Icons\\texture", it and it.name, 1, it and it.quality, r.bop ~= false,
           r.canNeed ~= false, true, false, nil, nil, nil, nil, r.canTransmog == true
end

function _G.GetLootRollItemLink(rollID)
    local r = KARTTEST.lootRolls[rollID]
    if not r or r.live == false then return nil end
    local it = KARTTEST.items[r.itemID]
    return it and it.link or nil
end

function _G.RollOnLoot(rollID, rollType)
    KARTTEST.rolled[rollID] = KARTTEST.rolled[rollID] or {}
    KARTTEST.rolled[rollID][KARTTEST.activeUnit or "player"] = rollType
end

-- Player info the council panel renders per candidate ------------------------------------
function _G.GetGuildInfo(unit)
    local m = resolve(unit)
    if not m or not m.guildRank then return nil end
    return "Guild", m.guildRank, 1
end
function _G.UnitLevel() return 80 end
function _G.GetItemQualityColor() return 1, 1, 1, "|cffffffff" end
function _G.CanInspect() return false end
function _G.NotifyInspect() end
function _G.ClearInspectPlayer() end
function _G.CheckInteractDistance() return false end
function _G.InCombatLockdown() return false end
function _G.IsShiftKeyDown() return false end
function _G.IsControlKeyDown() return false end
function _G.PlaySound() end
KARTTEST.instance = { name = "The Voidspire", difficultyID = 16, difficultyName = "Mythic" }
function _G.GetInstanceInfo()
    local i = KARTTEST.instance
    return i.name, "raid", i.difficultyID, i.difficultyName, 20, 0, false, 2912
end
function _G.CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a,
             GetRGB = function(s) return s.r, s.g, s.b end,
             GetRGBA = function(s) return s.r, s.g, s.b, s.a end,
             GenerateHexColor = function() return "ffffffff" end }
end

-- Chat / misc ---------------------------------------------------------------------------
function _G.SendChatMessage() end
function _G.IsInGuild() return false end
_G.UISpecialFrames = {}
-- Popups are recorded rather than shown, so a test can accept one deliberately. Several confirms
-- are load-bearing -- reassigning a winner routes THROUGH one -- and a stub that silently swallowed
-- them made the addon look broken when it was doing exactly the right thing.
KARTTEST.popups = {}
-- `owner` is whichever client raised it. A dialog is one player's screen: without this, a test could
-- accept a popup that was shown to somebody else entirely, and "the raid leader was asked" would be
-- indistinguishable from "everyone was asked".
function _G.StaticPopup_Show(which, a, b, data)
    KARTTEST.popups[#KARTTEST.popups + 1] =
        { which = which, a = a, b = b, data = data, owner = KARTTEST.activeUnit }
    return { data = data }
end
function _G.StaticPopup_Hide(which)
    for i = #KARTTEST.popups, 1, -1 do
        if KARTTEST.popups[i].which == which then table.remove(KARTTEST.popups, i) end
    end
end
-- Answers the most recent popup of that name the way a player clicking its accept button would.
function KARTTEST.AcceptPopup(which)
    for i = #KARTTEST.popups, 1, -1 do
        local p = KARTTEST.popups[i]
        if p.which == which and p.owner == KARTTEST.activeUnit then
            table.remove(KARTTEST.popups, i)
            -- The dialog table belongs to whichever client is executing (see raidsim), so this
            -- runs that client's handler and no one else's.
            local reg = (KARTTEST.PopupRegistry and KARTTEST.PopupRegistry()) or StaticPopupDialogs
            local def = reg[which]
            if def and def.OnAccept then def.OnAccept({ data = p.data }, p.data) end
            return true
        end
    end
    return false
end
_G.MenuUtil = { CreateContextMenu = function() end }
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
_G.CLASS_ICON_TEXCOORDS = {}
_G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
_G.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
_G.YES, _G.NO, _G.ACCEPT, _G.CANCEL, _G.OKAY, _G.CLOSE, _G.UNKNOWN = "Yes", "No", "Accept", "Cancel", "Okay", "Close", "Unknown"
_G.GameTooltip = _G.CreateFrame("Frame")

-- Socket text globals: KAGS scans _G for every "EMPTY_SOCKET_*" string rather than hardcoding
-- them, so the harness needs at least one to exercise that path.
_G.EMPTY_SOCKET_PRISMATIC = "Prismatic Socket"

-- The table StaticPopupDialogs entries are registered into. Real WoW creates it; here it only
-- needs to exist and hold whatever KAUI:RegisterStaticPopup puts in it.
_G.StaticPopupDialogs = {}
