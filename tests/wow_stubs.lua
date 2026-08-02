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
-- "npc" is the trade partner during TRADE_SHOW (see LC.Trade.OnTradeShow). Point it at a roster
-- row so a test can trade with a real raid member rather than a name string.
KARTTEST.tradePartnerUnit = nil
local function resolve(unit)
    if unit == "player" and KARTTEST.activeUnit then unit = KARTTEST.activeUnit end
    if unit == "npc" then unit = KARTTEST.tradePartnerUnit end
    return roster[unit]
end

-- The two trade windows, as lists of item links: what WE put in, and what the partner put in.
-- Both are needed, and from opposite sides -- the person handing an item over confirms it from
-- their own slots, the person receiving it from the partner's.
-- Bags, as a flat list of item links per bag. Empty by default, which is the honest state for
-- everybody except whoever is holding an item they have not handed over yet.
KARTTEST.bags = {}
_G.C_Container = {
    GetContainerNumSlots     = function(bag) return #(KARTTEST.bags[bag] or {}) end,
    GetContainerItemLink     = function(bag, slot) return (KARTTEST.bags[bag] or {})[slot] end,
    -- Puts the bag item on the cursor, which is what makes GetCursorInfo answer and what
    -- ClickTradeButton then drops into a trade slot.
    PickupContainerItem      = function(bag, slot)
        KARTTEST.cursorItem = (KARTTEST.bags[bag] or {})[slot]
    end,
    GetContainerItemInfo     = function() return nil end,
}

-- Auras, per unit, in the order the buff check walks them. Absent until now, which is why the whole
-- buff-check render -- the screen a raid leader reads before the pull -- had never run: the loop
-- over C_UnitAuras is the first thing it does per player.
-- Each entry is {name=, spellId=, expirationTime=}; expirationTime is GetTime()-based, as in the
-- game, and 0/absent means "does not expire".
KARTTEST.auras = {}
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if filter and filter ~= "HELPFUL" then return nil end
        return (KARTTEST.auras[unit] or {})[index]
    end,
}

-- Blizzard's ready-check state, which it clears again the moment the check resolves -- the addon
-- keeps its own snapshot for exactly that reason, and only one of the two paths could be reached
-- while this was missing.
KARTTEST.readyCheck = {}
function _G.GetReadyCheckStatus(unit) return KARTTEST.readyCheck[unit] end

KARTTEST.tradePlayerItems = {}
KARTTEST.tradeTargetItems = {}
function _G.GetTradePlayerItemLink(i) return KARTTEST.tradePlayerItems[i] end
function _G.GetTradeTargetItemLink(i) return KARTTEST.tradeTargetItems[i] end

-- The cursor, and the two calls that put a bag item into a trade slot. Both were absent, so the
-- two lines in Trade.OnTradeShow that actually hand an item over had never run.
--
-- The trade slot is filled the INSTANT ClickTradeButton is called here -- the reading most
-- favourable to the addon, since the real client only shows the item once the server answers
-- (TRADE_PLAYER_ITEM_CHANGED). Anything this finds is therefore not an artefact of the timing.
KARTTEST.cursorItem = nil
function _G.GetCursorInfo()
    if not KARTTEST.cursorItem then return nil end
    return "item", nil, nil, KARTTEST.cursorItem
end
function _G.ClearCursor() KARTTEST.cursorItem = nil end
function _G.ClickTradeButton(slot)
    if not KARTTEST.cursorItem then return end
    KARTTEST.tradePlayerItems[slot] = KARTTEST.cursorItem
    KARTTEST.cursorItem = nil
end
_G.LE_GAME_ERR_TRADE_COMPLETE = 401

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
-- KARTTEST.guidBlackout[unit] models the loading-screen edge the identity code is written around:
-- the player is in the group and answers UnitName, but UnitGUID is momentarily nil. It is the one
-- state in which a sender passes KASC's name-based group filter and still cannot be resolved to
-- anybody -- which is exactly what the second guard in each loot handler is for.
KARTTEST.guidBlackout = {}
function _G.UnitGUID(unit)
    if KARTTEST.guidBlackout[unit] then return nil end
    local m = resolve(unit)
    return m and m.guid or nil
end
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
-- Handing out assistant is a real change to somebody else's raid, so it is recorded rather than
-- swallowed: what matters about Auto-Promote is WHO it targets and in what spelling, and a no-op
-- stub can answer neither. Absent entirely until 2026-08-01, which is why KART.HandleAutoPromote had
-- never run in a test -- the call would simply have thrown.
KARTTEST.promoted = {}
function _G.PromoteToAssistant(target)
    KARTTEST.promoted[#KARTTEST.promoted + 1] = target
end
function KARTTEST.ClearPromoted() KARTTEST.promoted = {} end

-- Inviting and removing people, recorded for the same reason as the promote above: these change
-- somebody else's evening, and the only thing worth asserting about them is WHO was named. Neither
-- existed in the harness until 2026-08-01 -- WU.InviteBoss and WU.RemoveForBoss had never run in a
-- test, and a call would have thrown.
KARTTEST.invited, KARTTEST.uninvited = {}, {}
function _G.UninviteUnit(target)
    KARTTEST.uninvited[#KARTTEST.uninvited + 1] = target
end
_G.C_PartyInfo = _G.C_PartyInfo or {}
function _G.C_PartyInfo.InviteUnit(target)
    KARTTEST.invited[#KARTTEST.invited + 1] = target
end
function _G.C_PartyInfo.ConvertToRaid() KARTTEST.convertedToRaid = true end
function KARTTEST.ClearInvites()
    KARTTEST.invited, KARTTEST.uninvited = {}, {}
    KARTTEST.convertedToRaid = false
end
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

-- Wall clock, and it moves with KARTTEST.AdvanceTime like every other clock here. It used to be
-- os.time directly, which meant the one deadline in this addon that is measured in WALL clock -- the
-- four-hour Bind-on-Pickup trade window -- could not be advanced by a test at all: no assertion could
-- reach the timeout warning, the expiry pruning, or what a reload does to the countdown.
--
-- Offset from a fixed epoch rather than from the real one, so a failure reproduces tomorrow as well.
KARTTEST.epoch = 1785000000
function _G.time() return KARTTEST.epoch + math.floor(KARTTEST.now) end

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

-- Frames that asked to hear an event, in registration order, tagged with the client that created
-- them. RegisterEvent used to be a no-op, so a frame that drives real behaviour off an event --
-- LootCouncilRelevance.lua snapshots Blizzard's per-roll verdict the instant START_LOOT_ROLL
-- fires -- stored its handler and was never called. 192 lines of the addon were unreachable from
-- the harness, and its own three assertions could not have noticed.
--
-- Tagged by OWNER because raidsim runs several clients in one process: each loads the addon files
-- into its own environment and so creates its own frames, and firing an event has to reach one
-- client's handlers and nobody else's.
KARTTEST.eventFrames = {}

-- Fires one event at the frames of the client currently executing, in the order they registered
-- -- which is load order, and load order is what decides whether the relevance snapshot sees a
-- roll before Core.lua's dispatcher has resolved it away.
function KARTTEST.FireEvent(event, ...)
    local owner = KARTTEST.frameOwner
    for _, reg in ipairs(KARTTEST.eventFrames) do
        if reg.event == event and reg.owner == owner then
            local handler = reg.frame:GetScript("OnEvent")
            if handler then handler(reg.frame, event, ...) end
        end
    end
end

function _G.CreateFrame(_, name, parent, _)
    local f = setmetatable({}, frameMeta)
    if name then _G[name] = f end
    -- The parent was discarded, and the catch-all answers every unknown method with the frame
    -- itself -- so GetParent returned the frame and any walk up the chain looped forever.
    -- KART.BuildSearchIndex does exactly that walk, to find which tab a label lives on, so the
    -- settings search could not be exercised at all until this existed.
    function f:GetParent() return parent end
    function f:SetParent(p) parent = p end
    local owner = KARTTEST.frameOwner

    local scripts = {}
    function f:SetScript(scriptType, handler) scripts[scriptType] = handler; return f end
    function f:GetScript(scriptType) return scripts[scriptType] end
    function f:RegisterEvent(event)
        for _, reg in ipairs(KARTTEST.eventFrames) do
            if reg.frame == f and reg.event == event then return f end
        end
        KARTTEST.eventFrames[#KARTTEST.eventFrames + 1] = { frame = f, event = event, owner = owner }
        return f
    end
    function f:UnregisterEvent(event)
        for i = #KARTTEST.eventFrames, 1, -1 do
            local reg = KARTTEST.eventFrames[i]
            if reg.frame == f and reg.event == event then table.remove(KARTTEST.eventFrames, i) end
        end
        return f
    end

    local checked = false
    function f:SetChecked(value) checked = not not value; return f end
    function f:GetChecked() return checked end

    -- A size that was never set is 0, which is a freshly created frame's real starting size and what
    -- a "skip rounding a frame this small" comparison needs to see. A size that WAS set is answered
    -- with, like a real frame -- the buff check's name column truncates against its own
    -- GetWidth(), so a stub that always said 0 cut every name in the harness down to "..." and made
    -- the entire column unassertable.
    local width, height = 0, 0
    function f:SetWidth(v) width = tonumber(v) or 0; return f end
    function f:SetHeight(v) height = tonumber(v) or 0; return f end
    function f:SetSize(w, h) width, height = tonumber(w) or 0, tonumber(h) or 0; return f end
    function f:GetWidth() return width end
    function f:GetHeight() return height end
    function f:GetSize() return width, height end

    -- Screen position: nil, because this harness has no layout and cannot answer where a widget
    -- sits. nil is the truthful answer rather than a convenient zero -- the game returns it too,
    -- for an unanchored or hidden region, which is why every caller here already guards for it
    -- (`if top and scrollTop then`). A zero would sail past those guards into arithmetic that
    -- silently means nothing.
    function f:GetTop() return nil end
    function f:GetBottom() return nil end
    function f:GetLeft() return nil end
    function f:GetRight() return nil end

    -- Frame level IS a number and gets arithmetic done to it (`parent:GetFrameLevel() + 10`).
    local frameLevel = 1
    function f:SetFrameLevel(v) frameLevel = tonumber(v) or frameLevel end
    function f:GetFrameLevel() return frameLevel end

    -- Frame strata is real state rather than a no-op. KAUI moves every window it owns down below
    -- Blizzard's DIALOG stratum while one of the addon's own confirm dialogs is up, and back
    -- afterwards (B55) -- "did it actually move, and did it come back" is the whole assertion, and
    -- a stub that swallowed the write would report a broken clamp as working. MEDIUM is what a
    -- freshly created frame carries in the game.
    local strata = "MEDIUM"
    function f:SetFrameStrata(value) strata = value end
    function f:GetFrameStrata() return strata end

    -- Alpha is real state for the same reason: it is how a control is greyed out and how the Loot
    -- Council windows follow the opacity setting, so "is it dimmed" has to be answerable.
    local alpha = 1
    function f:SetAlpha(value) alpha = value end
    function f:GetAlpha() return alpha end

    -- Whether a control accepts input is real state too, and for the same reason as alpha: the
    -- raid-wide settings box makes its fields read-only while somebody else's config is in force,
    -- and "is this box editable" is the only way to check that. Without these the catch-all answered
    -- something truthy for everything and a test asking the question measured the stub.
    -- Scroll offset, as a number rather than the catch-all's frame: KART.UpdateScrollRange clamps
    -- the current offset against the new range, and comparing a frame to a number is an error that
    -- reads nothing like "this getter was never stubbed".
    -- Anchors, remembered rather than discarded. The addon reads its OWN position back through
    -- GetPoint to save it (the drag handlers on the raidlead bar and the buff-check window), so
    -- without this the whole save-and-restore-position path answered with a frame.
    local points = {}
    function f:SetPoint(a, b, c, d, e)
        -- The three shapes the game accepts: (point), (point, x, y) and
        -- (point, relativeTo, relativePoint, x, y).
        local entry
        if type(b) == "number" then entry = { a, nil, a, b, c }
        elseif c == nil and b == nil then entry = { a, nil, a, 0, 0 }
        else entry = { a, b, c, d or 0, e or 0 } end
        points[#points + 1] = entry
    end
    function f:ClearAllPoints() points = {} end
    function f:GetNumPointsSet() return #points end
    function f:GetPoint(i)
        local p = points[i or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end

    local vScroll = 0
    function f:SetVerticalScroll(value) vScroll = tonumber(value) or 0 end
    function f:GetVerticalScroll() return vScroll end

    local mouseEnabled, keyboardEnabled = true, true
    function f:EnableMouse(on) mouseEnabled = on ~= false end
    function f:IsMouseEnabled() return mouseEnabled end
    function f:EnableKeyboard(on) keyboardEnabled = on ~= false end
    function f:IsKeyboardEnabled() return keyboardEnabled end

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

    -- Colour is the whole answer for a column that has no text: the buff-check grid says "you are
    -- missing this" by tinting an icon red and "this is about to run out" by tinting it amber, and
    -- the durability column says 19% in red and 51% in green with the same three digits. On the
    -- catch-all all of that was a no-op, so an assertion about it could not be written at all.
    -- SetTexture/SetColorTexture are write-only in the real API; these getters exist for the harness
    -- alone, because "which icon is on this row" and "is this stripe shaded" are otherwise
    -- unobservable and the addon decides both from data that can be wrong.
    local texture, colorTexture
    function f:SetTexture(v) texture = v; return f end
    function f:GetTexture() return texture end
    function f:SetColorTexture(...) colorTexture = { ... }; return f end
    function f:GetColorTexture() if colorTexture then return unpack(colorTexture) end end

    local textColor, vertexColor, desaturated
    function f:SetTextColor(...) textColor = { ... }; return f end
    function f:GetTextColor() if textColor then return unpack(textColor) end end
    function f:SetVertexColor(...) vertexColor = { ... }; return f end
    function f:GetVertexColor() if vertexColor then return unpack(vertexColor) end end
    function f:SetDesaturated(v) desaturated = v and true or false; return f end
    function f:IsDesaturated() return desaturated end

    -- Where the mouse is. The catch-all answered this with the frame -- truthy for every frame at
    -- once, which is not a state a mouse can be in. The council panel's tab close button decides
    -- whether to hide itself from exactly this, and got it wrong twice in ways that cost clicks, so
    -- "the cursor is on that one and not on this one" has to be expressible.
    function f:IsMouseOver() return KARTTEST.mouseOver == f end

    -- Textures and font strings are their OWN regions. The catch-all answered both with the frame
    -- itself, so every texture and label a frame owned was the same object: a row's twelve buff
    -- indicators all wrote over one another, and hiding a label hid the window it sat on. Anything
    -- asserting on a region was really asserting on its parent.
    --
    -- Built from CreateFrame so they answer the same getters (alpha, shown, text, colour) -- the
    -- game's regions are not frames, but every method the addon calls on one is a method a frame
    -- here already has, and a second near-identical factory would drift.
    function f:CreateTexture() return _G.CreateFrame("Frame", nil, f) end
    function f:CreateFontString() return _G.CreateFrame("Frame", nil, f) end

    if name == "KART_GearScanTooltip" then InstallScanTooltip(f) end

    return f
end
_G.UIParent = _G.CreateFrame("Frame")
-- Sized, now that a set size is answered with: KAUI.IsSavedPosOnScreen divides by UIParent's width
-- and height, so with both at 0 every saved window position read as off-screen and the restore path
-- was unreachable. Matches KARTTEST.physW/physH below, which is what the game's own default scale
-- assumes.
_G.UIParent:SetSize(1920, 1080)

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
    -- The EFFECTIVE item level of one specific link, upgrades included -- which is not
    -- GetItemInfo's fourth return, that being the item's base level. Droptimizer needs the
    -- difference: the same item simmed at several upgrade tracks appears more than once in the
    -- companion's cache, and the rolled level is what picks the right candidate. Absent here until
    -- 2026-08-01, which is one of the reasons that module had never executed in a test at all.
    -- detailedIlvl = false means the client cannot answer yet, which is what the real one does for an
    -- item this client has not cached -- on a fresh login, every item that has not dropped. Falling
    -- back to the base level unconditionally made that case unreachable, and it is a case with its
    -- own branch: with no level to measure against, Droptimizer picks the largest gain instead of
    -- the closest one.
    GetDetailedItemLevelInfo = function(v)
        local it = itemOf(v)
        if not it or it.detailedIlvl == false then return nil end
        return it.detailedIlvl or it.ilvl
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
            -- Who asked is remembered with the callback, the same way the timer stub does it: this
            -- runs later, from KARTTEST.CacheItem, and a callback that refreshes a window can send
            -- addon messages -- which belong to that client and to nobody else.
            table.insert(KARTTEST.pendingItemLoads[id], {
                fn = cb,
                owner = KARTTEST.frameOwner,
                ctx = KARTTEST.CaptureContext and KARTTEST.CaptureContext() or nil,
            })
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
    local prevOwner = KARTTEST.frameOwner
    for _, pending in ipairs(KARTTEST.pendingItemLoads[id] or {}) do
        KARTTEST.frameOwner = pending.owner
        local prevCtx = pending.ctx and KARTTEST.RestoreContext(pending.ctx)
        pending.fn()
        if prevCtx then KARTTEST.RestoreContext(prevCtx) end
    end
    KARTTEST.frameOwner = prevOwner
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

-- Transmog appearances, for the FALLBACK path in LootCouncilRelevance.lua -- the one taken by an
-- item that never had a Blizzard roll on this client (/kart add, or a client that was dead when
-- it dropped). Three separate facts, because the addon has to ask three separate questions and
-- conflating any two of them is what B39 was:
--   appearance  -- does this item have an appearance at all (rings and trinkets do not)
--   collectible -- can THIS character ever learn that source
--   owned       -- has it already been collected
KARTTEST.appearances = {}
local function appearanceFor(link)
    local id = tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
    return id and KARTTEST.appearances[id] or nil
end
_G.C_TransmogCollection = {
    GetItemInfo = function(link)
        local a = appearanceFor(link)
        if not a or not a.appearance then return nil end
        return a.appearance, a.source
    end,
    PlayerCanCollectSource = function(sourceID)
        for _, a in pairs(KARTTEST.appearances) do
            if a.source == sourceID then return a.collectible ~= false end
        end
        return true
    end,
    PlayerHasTransmogByItemInfo = function(link)
        local a = appearanceFor(link)
        return a ~= nil and a.owned == true
    end,
}

function _G.GetLootRollItemInfo(rollID)
    local r = rollFor(rollID)
    if not r then return nil end
    local it = KARTTEST.items[r.itemID]
    -- canGreed/canDisenchant were hardcoded true/false, which meant ForceWinRoll always found SOME
    -- roll type available and the "the lootmaster cannot roll on this at all" shape -- a real one, the
    -- game offers different subsets per item and per character -- could not be produced at all.
    return "Interface\\Icons\\texture", it and it.name, 1, it and it.quality, r.bop ~= false,
           r.canNeed ~= false, r.canGreed ~= false, r.canDisenchant == true,
           nil, nil, nil, nil, r.canTransmog == true
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
-- Combat lockdown is a switch a test flips, not a constant. Half this addon has a branch for it
-- -- the raidlead bar refuses to change frames, keybinds defer themselves -- and a hard false
-- meant none of those branches had ever run.
KARTTEST.inCombat = false
function _G.InCombatLockdown() return KARTTEST.inCombat end

-- Override bindings outrank the player's own keybinds for the whole session, so which frame owns
-- them and whether they were given back is the only interesting thing about them.
KARTTEST.overrideBindings = {}
function _G.SetOverrideBindingClick(owner, _, key, button)
    KARTTEST.overrideBindings[owner] = KARTTEST.overrideBindings[owner] or {}
    KARTTEST.overrideBindings[owner][key] = button or true
end
function _G.ClearOverrideBindings(owner) KARTTEST.overrideBindings[owner] = nil end

-- Values the client refuses to let an addon read (see KAUtil.IsSecret). A real secret string throws
-- on every string operation and cannot be built in plain Lua, so what is modelled here is the part
-- that actually matters: it looks like an ordinary string to `type()`, and issecretvalue is the only
-- way to tell. A test marks a string secret by putting it in this table.
KARTTEST.secretValues = {}
function _G.issecretvalue(value)
    return KARTTEST.secretValues[value] == true
end
-- WoW exposes Lua's os.date under this name. The loot-history export formats every row's date and
-- time through it, which is why that whole path had never run here before 2026-08-01.
_G.date = os.date
-- Blizzard's post-hook. Real behaviour, not a no-op: the settings panel hooks its own edit boxes
-- through this, so swallowing the hook would silently disable whatever it installed.
function _G.hooksecurefunc(a, b, c)
    local tbl, name, hook = a, b, c
    if type(a) == "string" then tbl, name, hook = _G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = orig and orig(...)
        hook(...)
        return r
    end
end
-- Counted, not performed. Two paths end in a reload rather than doing the work themselves -- the
-- settings reset and a profile that changes the language -- and "did it reload" is the only way to
-- tell those apart from a path that quietly did nothing.
KARTTEST.reloads = 0
function _G.ReloadUI() KARTTEST.reloads = KARTTEST.reloads + 1 end
-- The three modifiers, driven by a settable table so a test can record a bound key the way a player
-- holding one would. Alt was the one missing entirely, which is the only one that could not be
-- pressed while recording a keybind.
KARTTEST.modifiers = {}
function _G.IsShiftKeyDown() return KARTTEST.modifiers.shift or false end
function _G.IsControlKeyDown() return KARTTEST.modifiers.ctrl or false end
function _G.IsAltKeyDown() return KARTTEST.modifiers.alt or false end
function _G.PlaySound() end
-- instanceType is part of the answer, not decoration: "none" is where the player spends most of
-- their time, and anything deciding on the difficultyID alone has to say what it expects that ID to
-- be out there. Defaults to a raid because that is what almost every test here is about.
KARTTEST.instance = { name = "The Voidspire", instanceType = "raid",
                      difficultyID = 16, difficultyName = "Mythic" }
function _G.GetInstanceInfo()
    local i = KARTTEST.instance
    return i.name, i.instanceType or "raid", i.difficultyID, i.difficultyName, 20, 0, false, 2912
end

-- Combat logging, as real state: AutoLog's whole job is deciding when to turn this on and, more
-- delicately, when it is allowed to turn it back off. None of these three existed here before
-- 2026-08-01, so KART.AutoLog.Evaluate had never run.
KARTTEST.logging = false
KARTTEST.cvars = {}
function _G.LoggingCombat(on)
    if on ~= nil then KARTTEST.logging = not not on end
    return KARTTEST.logging
end
function _G.SetCVar(name, value) KARTTEST.cvars[name] = value end
function _G.GetCVar(name) return KARTTEST.cvars[name] end
KARTTEST.keystoneLevel = 0
_G.C_ChallengeMode = {
    GetActiveKeystoneInfo = function() return KARTTEST.keystoneLevel end,
}
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
-- Visible chat, recorded rather than swallowed. The 255-byte cap is the client's own and is the
-- whole reason this is worth modelling: a longer line does not get truncated into something the raid
-- can still read, it does not arrive at all. Anything over the cap is recorded under `refused` so a
-- test can assert about the message that was never sent, which is what a silent failure looks like
-- from the inside.
KARTTEST.chat = {}
function _G.SendChatMessage(msg, channel)
    msg = tostring(msg or "")
    KARTTEST.chat[#KARTTEST.chat + 1] =
        { msg = msg, channel = channel, refused = #msg > 255, by = KARTTEST.activeUnit }
end
function KARTTEST.ClearChat() KARTTEST.chat = {} end
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
    -- The text the PLAYER ends up reading, resolved the way the game resolves it: the dialog's own
    -- `text` with the show arguments substituted into it. Recording only `a` and `b` meant a
    -- confirmation could be asserted on without anybody checking that the question it asks actually
    -- names them -- which is the whole point of a count in a "remove N players?" dialog.
    local reg = (KARTTEST.PopupRegistry and KARTTEST.PopupRegistry()) or StaticPopupDialogs
    local def = reg and reg[which]
    local shown = def and def.text
    if shown and (a ~= nil or b ~= nil) then
        local ok, formatted = pcall(string.format, shown, a, b)
        if ok then shown = formatted end
    end
    KARTTEST.popups[#KARTTEST.popups + 1] =
        { which = which, a = a, b = b, data = data, text = shown, owner = KARTTEST.activeUnit }
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
-- Context menus. This was an empty stub, which meant the initializer -- the function that builds
-- every entry the menu will contain -- was never called: eight menus across the addon, and not one
-- of their bodies had ever run. The addon uses exactly two of Blizzard's root-description methods,
-- so answering them honestly is cheap.
--
-- Entries are recorded in the order they are created, which is the order they appear on screen, and
-- a button's function is kept so a test can click it.
-- CreateButton WITHOUT a function is Blizzard's way of declaring a submenu: the returned descriptor
-- takes further entries of its own. LootCouncilPanel's "change vote" menu is built that way, so a
-- descriptor that could not do it would fail the moment the menu opened.
local function NewMenuNode()
    local node = { entries = {} }
    function node:CreateTitle(text)
        table.insert(self.entries, { kind = "title", text = text })
    end
    function node:CreateButton(text, fn)
        local entry = NewMenuNode()
        entry.kind, entry.text, entry.fn = "button", text, fn
        -- Greyed-out entries are still shown; KARTTEST.ClickMenu refuses them the way the game does.
        function entry.SetEnabled(_, on) entry.disabled = not on end
        table.insert(self.entries, entry)
        return entry
    end
    return node
end

_G.MenuUtil = {
    CreateContextMenu = function(owner, initializer)
        local root = NewMenuNode()
        initializer(owner, root)
        KARTTEST.lastMenu = root
        return root
    end,
}
-- Clicks a widget the way the game delivers a click: a frame with the mouse disabled never receives
-- one, so calling its OnClick directly is a stronger act than a player is capable of. Returns
-- whether the click landed.
function KARTTEST.Click(widget, button)
    if not widget or (widget.IsMouseEnabled and not widget:IsMouseEnabled()) then return false end
    local onClick = widget.GetScript and widget:GetScript("OnClick")
    if not onClick then return false end
    onClick(widget, button or "LeftButton")
    return true
end

-- Finds a button by label in the most recent menu, descending into submenus, so a test names the
-- entry it means rather than a path.
local function FindMenuEntry(node, label)
    for _, entry in ipairs((node or {}).entries or {}) do
        if entry.kind == "button" and entry.text == label then return entry end
        local nested = FindMenuEntry(entry, label)
        if nested then return nested end
    end
    return nil
end
-- Clicks that entry the way a player would. Returns false if the menu has no such entry, or if it
-- is greyed out -- so a test can assert on an option being absent or inert as well as on what it
-- does.
function KARTTEST.ClickMenu(label)
    local entry = FindMenuEntry(KARTTEST.lastMenu, label)
    if not entry or entry.disabled then return false end
    if entry.fn then entry.fn() end
    return true
end
-- The labels of the most recent menu's top-level buttons, titles excluded.
function KARTTEST.MenuLabels()
    local out = {}
    for _, entry in ipairs((KARTTEST.lastMenu or {}).entries or {}) do
        if entry.kind == "button" then out[#out + 1] = entry.text end
    end
    return out
end
-- The labels inside the submenu hanging off that entry.
function KARTTEST.SubmenuLabels(label)
    local out = {}
    for _, entry in ipairs((FindMenuEntry(KARTTEST.lastMenu, label) or {}).entries or {}) do
        if entry.kind == "button" then out[#out + 1] = entry.text end
    end
    return out
end
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
-- Only the real class tokens, and nil for anything else -- which is what the game answers too.
-- A blanket __index returning white for EVERY key made "this client does not know that class"
-- unreachable in the harness, and that is not a corner case: history entries outlive expansions in
-- a SavedVariable, the class arrives from a peer as a bare string, and the row colours by it.
local CLASS_TOKENS = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
-- The group-loot roll OUTCOME (B60). Blizzard resolves a drop and raises LOOT_HISTORY_UPDATE_DROP
-- with an encounter and a loot-list id; the winner is read back out of C_LootHistory. Driven by a
-- table here, keyed the same way the real API is indexed.
--   KARTTEST.lootDrops["<encounterID>:<lootListID>"] = { itemHyperlink = ..., winner = {...} }
KARTTEST.lootDrops = {}
_G.C_LootHistory = {
    GetSortedInfoForDrop = function(encounterID, lootListID)
        return KARTTEST.lootDrops[tostring(encounterID) .. ":" .. tostring(lootListID)]
    end,
}

-- Distinct per class, so "this row is coloured by the RIGHT class" is a question that can be asked
-- at all -- with every token answering white, a correct colour and a fallback were the same value.
-- These are NOT Blizzard's palette and deliberately so: a test that pinned a real hex would be
-- asserting a fact this file cannot know. What it can honestly promise is that two classes differ
-- and that the unknown-class fallback (which every reader spells 0.8/0.8/0.8 or 1/1/1) differs from
-- all of them.
_G.RAID_CLASS_COLORS = {}
for i, token in ipairs(CLASS_TOKENS) do
    _G.RAID_CLASS_COLORS[token] = { r = i / 20, g = 0.5, b = 1 - i / 20 }
end

-- The class icon's slice of Blizzard's shared circle texture. LC.SetClassIconTexture hides the icon
-- when the token is missing here, and an empty table meant it hid it for EVERY class in every test
-- -- so three lines of that function had never run. The coordinates are a 4x4 grid because the real
-- sheet is one; which class sits in which cell is not something this harness needs to be right
-- about, and no test may assert a specific cell.
_G.CLASS_ICON_TEXCOORDS = {}
for i, token in ipairs(CLASS_TOKENS) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    _G.CLASS_ICON_TEXCOORDS[token] = { col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25 }
end
_G.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
_G.YES, _G.NO, _G.ACCEPT, _G.CANCEL, _G.OKAY, _G.CLOSE, _G.UNKNOWN = "Yes", "No", "Accept", "Cancel", "Okay", "Close", "Unknown"
_G.GameTooltip = _G.CreateFrame("Frame")

-- Socket text globals: KAGS scans _G for every "EMPTY_SOCKET_*" string rather than hardcoding
-- them, so the harness needs at least one to exercise that path.
_G.EMPTY_SOCKET_PRISMATIC = "Prismatic Socket"

-- The table StaticPopupDialogs entries are registered into. Real WoW creates it; here it only
-- needs to exist and hold whatever KAUI:RegisterStaticPopup puts in it.
_G.StaticPopupDialogs = {}
