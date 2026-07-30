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
-- Forward declaration: the group-API stubs further down define this, and the unit stubs above them
-- need it. Same file, one chunk, so the upvalue is shared.
local isSolo
local function resolve(unit)
    if unit == "player" and KARTTEST.activeUnit then unit = KARTTEST.activeUnit end
    return roster[unit]
end

function _G.UnitExists(unit) return resolve(unit) ~= nil end
-- The real UnitName returns an EMPTY realm for a player on your own realm, and only names the realm
-- for a genuine cross-realm one. Returning it unconditionally, with a fixture whose members all sat
-- on a realm the client was not on, meant every same-realm branch of the group-membership check --
-- the path taken by essentially every message in a normal guild raid -- was never executed. Every
-- authorization gate in the addon was being validated in a configuration that cannot occur.
function _G.UnitName(unit)
    local m = resolve(unit)
    if not m then return nil end
    if m.realm == KARTTEST.realm then return m.name, "" end
    return m.name, m.realm
end
function _G.UnitGUID(unit) local m = resolve(unit) return m and m.guid or nil end
-- A client that reads itself as ungrouped is not a raid leader either. Leaving the leader flag on
-- during a simulated blip produced a state the game cannot be in -- no group, no members, still
-- leader -- and every raid-leader fallback in the addon took the wrong branch through it, in the
-- very tests that defend against blips.
function _G.UnitIsGroupLeader(unit)
    if isSolo() and (unit == "player" or unit == KARTTEST.activeUnit) then return false end
    local m = resolve(unit)
    return m and m.leader or false
end
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
    -- A ticker that actually ticks. It used to be a stub that never fired, which made every
    -- countdown, sweep and timeout in the addon dead in tests: the vote window's own pruner, the
    -- council panel's timer and the trade-timeout check. A test that then called the pruner itself
    -- was asserting about its own call rather than about the addon's wiring -- cut the ticker out of
    -- the addon entirely and the suite stayed green while no vote row ever closed in a raid.
    NewTicker = function(interval, fn)
        local entry = { at = KARTTEST.now + (interval or 1), fn = fn, every = interval or 1,
                        ctx = captureContext() }
        KARTTEST.timers[#KARTTEST.timers + 1] = entry
        return { Cancel = function() entry.every = nil; entry.fn = function() end end }
    end,
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
        -- A timer that sends gets its own message back, same as any other send.
        if KARTTEST.FlushEcho then KARTTEST.FlushEcho() end
        ran = ran + 1
        -- A ticker re-arms itself, unless it was cancelled while running.
        if next_.every then
            next_.at = KARTTEST.now + next_.every
            KARTTEST.timers[#KARTTEST.timers + 1] = next_
        end
    end
    KARTTEST.now = target
    return ran
end
-- One client's group APIs can be made to disagree with the rest of the raid's. Two real situations
-- need that: someone who actually ports out, and -- the one that cost a session mid-boss -- the
-- moment during any roster change where the APIs briefly report no group at all on ONE machine
-- while everyone else reads normally. A shared flag cannot express either.
KARTTEST.solo = {} -- [unitToken] = true: this client alone reads the world as ungrouped
function isSolo()
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
-- An unknown key answers nil, like a real frame -- with one exception: a PascalCase name is a
-- Blizzard frame METHOD, and there are hundreds of those the addon may call. Those return a callable
-- that hands back its first argument, so `f:SetPoint(...)` chains keep working.
--
-- The blanket "every unknown key is a truthy child table" this replaces was the single most
-- expensive lie in the harness. Every `if f.ticker then return end` and `if not row.x then` took the
-- wrong branch silently -- the vote window's own countdown ticker was NEVER created in any test
-- because of exactly that line, so the expiry sweep it drives went untested while a test that called
-- the sweep by hand reported it working. Lowercase keys are how this addon stores its own state on a
-- frame, so the split is reliable here.
local frameMeta
local function methodStub() end
frameMeta = {
    __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return methodStub end
        return nil
    end,
    __call = function(_, first) return first end,
}
methodStub = function(first) return first end
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

    -- Frame strata is real state rather than a no-op. KAUI moves every window it owns down below
    -- Blizzard's DIALOG stratum while one of the addon's own confirm dialogs is up, and back
    -- afterwards (B55) -- "did it actually move, and did it come back" is the whole assertion, and
    -- a stub that swallowed the write would report a broken clamp as working. MEDIUM is what a
    -- freshly created frame carries in the game.
    local strata = "MEDIUM"
    function f:SetFrameStrata(value) strata = value end
    function f:GetFrameStrata() return strata end

    -- Getters that must answer with something other than a frame, or callers that build strings and
    -- run loops from them go wrong in ways that look nothing like their cause -- a name concatenated
    -- into a lookup, a region count driving a for loop.
    function f:GetName() return name end
    function f:GetObjectType() return "Frame" end
    function f:GetNumRegions() return 0 end
    function f:GetNumPoints() return 0 end
    function f:GetRegions() return nil end
    function f:GetID() return 0 end

    -- Show/Hide fire their scripts, because closing a window is a real event in this addon and not
    -- only a rendering concern: Escape closes anything registered in UISpecialFrames without running
    -- any button handler, so OnHide is the ONLY place a dialog can notice it was dismissed rather
    -- than answered. A stub that swallowed it made that whole class of bug invisible.
    local shown = true
    local function fire(f_, script)
        local handler = f_:GetScript(script)
        if handler then handler(f_) end
    end
    function f:Show()
        local was = shown; shown = true
        if not was then fire(f, "OnShow") end
        return f
    end
    function f:Hide()
        local was = shown; shown = false
        if was then fire(f, "OnHide") end
        return f
    end
    function f:SetShown(v) if v then return f:Show() end return f:Hide() end
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
-- Registered by a test, keyed by itemID. Fixtures are taken from a real loot history
-- rather than invented, so classID/subclassID are the values the live client actually reports.
KARTTEST.items = {} -- [itemID] = { name =, link =, quality =, ilvl =, classID =, subclassID =, equipLoc =, bind =, cached = }

function KARTTEST.AddItem(def)
    KARTTEST.items[def.id] = def
    -- Shaped like a real Midnight drop, bonus IDs and all. The old skeleton link was ~55 bytes where
    -- a live one is 100-200+, which meant no message the suite produced ever came close to the
    -- transport's 255-byte cap and none of the addon's three guards against it was ever exercised.
    def.link = def.link or ("|cffa335ee|Hitem:" .. def.id ..
        "::::::::80:268::14:8:11946,10390,12043,10255,1540,10879,11996:::::|h[" .. def.name .. "]|h|r")
    return def
end

-- The real item API takes an ID, an "item:NNN" string or a full link interchangeably. A bare numeric
-- STRING is the form the addon actually passes on the path that rebuilds an item from a message
-- payload -- payload captures are strings -- and a stub that only understood numbers and links made
-- that whole rebuild answer nil.
local function itemIDOf(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    return tonumber(v:match("item:(%d+)")) or tonumber(v)
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

-- A loot roll exists PER CLIENT. Blizzard raises START_LOOT_ROLL only on clients eligible for that
-- item, and on everyone else GetLootRollItemInfo/Link answer nil forever -- which is the entire
-- reason LC.HandleStart has to rebuild the link from the message payload. A shared table answered
-- every client with a full link, so that rebuild path was never executed by any test and three
-- raiders' worth of "???" could have come straight back unnoticed.
--
-- `notFor` marks the clients this roll never reached; `rolledBy` closes it for whoever has answered
-- it, because the real API goes blank the moment you roll and the addon uses exactly that as its
-- "is this roll still live?" probe.
local function rollFor(rollID)
    local r = KARTTEST.lootRolls[rollID]
    if not r or r.live == false then return nil end
    local unit = KARTTEST.activeUnit or "player"
    -- Who Blizzard actually raised this roll on, by NAME rather than unit token: a join or a leave
    -- renumbers every token behind it (see RaidSim.Reindex), so a token recorded when the boss died
    -- means somebody else ten seconds later.
    --
    -- The stub used to answer for anyone not explicitly excluded, which made GetLootRollItemLink
    -- true for a player who joined AFTER the boss died -- something the game cannot do, and the
    -- exact fact LC.HandleRollCatchup relies on to keep a late arrival out of a distribution
    -- already running.
    if r.forNames then
        local m = roster[unit]
        if not (m and r.forNames[m.name]) then return nil end
    end
    if r.notFor and r.notFor[unit] then return nil end
    if r.rolledBy and r.rolledBy[unit] then return nil end
    return r
end

function _G.GetLootRollItemInfo(rollID)
    local r = rollFor(rollID)
    if not r then return nil end
    local it = KARTTEST.items[r.itemID]
    return "Interface\\Icons\\texture", it and it.name, 1, it and it.quality, r.bop ~= false,
           r.canNeed ~= false, true, false, nil, nil, nil, nil, r.canTransmog == true
end

function _G.GetLootRollItemLink(rollID)
    local r = rollFor(rollID)
    if not r then return nil end
    -- `linkPending` models the real transient the addon retries for: the roll exists and its texture
    -- is there, but the link has not propagated to this client yet. Deliberately NOT tied to the
    -- item cache -- GetLootRollItemLink comes with the roll and answers for items GetItemInfo still
    -- knows nothing about, which is exactly why the addon can rebuild a name from an itemID at all.
    if r.linkPending then return nil end
    local it = KARTTEST.items[r.itemID]
    return it and it.link or nil
end

function _G.RollOnLoot(rollID, rollType)
    KARTTEST.rolled[rollID] = KARTTEST.rolled[rollID] or {}
    local unit = KARTTEST.activeUnit or "player"
    KARTTEST.rolled[rollID][unit] = rollType
    local r = KARTTEST.lootRolls[rollID]
    if r then
        r.rolledBy = r.rolledBy or {}
        r.rolledBy[unit] = true
    end
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

-- Values the client refuses to let an addon read (see KAUtil.IsSecret). A real secret string throws
-- on every string operation and cannot be built in plain Lua, so what is modelled here is the part
-- that actually matters: it looks like an ordinary string to `type()`, and issecretvalue is the only
-- way to tell. A test marks a string secret by putting it in this table.
KARTTEST.secretValues = {}
function _G.issecretvalue(value)
    return KARTTEST.secretValues[value] == true
end
function _G.IsShiftKeyDown() return false end
function _G.IsControlKeyDown() return false end
function _G.PlaySound() end
KARTTEST.instance = { name = "The Voidspire", difficultyID = 16, difficultyName = "Mythic" }
function _G.GetInstanceInfo()
    local i = KARTTEST.instance
    return i.name, "raid", i.difficultyID, i.difficultyName, 20, 0, false, 2912
end
-- Loot history stamps every entry with the difficulty it was won on, and the catch-up sync resolves
-- a received difficulty ID back to its name.
function _G.GetDifficultyInfo(id)
    local i = KARTTEST.instance
    if id ~= i.difficultyID then return nil end
    return i.difficultyName, "raid", false, false, false, false, id
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
-- The real one returns nil when it could not show the dialog -- all four popup slots are in use, or
-- the name was never registered. Callers that latch "already asked" before checking that return
-- value burn the latch on a question nobody was shown. KARTTEST.popupsBlocked models a full pool.
function _G.StaticPopup_Show(which, a, b, data)
    if KARTTEST.popupsBlocked then return nil end
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
