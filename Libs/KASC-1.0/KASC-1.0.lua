-- KASC-1.0: the addon-message layer shared by every KA addon. Owns the prefix, the outbound
-- send wrapper, the inbound dispatch, sender identity resolution, and the responders for the
-- data requests any KA client must be able to answer.
--
-- The governing rule is an asymmetry: KASC owns the ANSWERING side, consumers own the
-- RECEIVING side. A client running only the Loot Council side still has to answer REQ_GEAR or
-- the asking client's Buff Checker goes blind for that player -- but filling a cache and
-- refreshing a panel only matters to whoever renders it.
--
-- No user-visible strings live here. Version comparison, update warnings and chat output are
-- consumer concerns, surfaced through OnPeer.
--
-- API style: colon (KASC:Foo) is every consumer-facing action -- Send, Init, the Register*
-- calls, OnPeer, and the handshake senders. Dot (KASC.Foo) marks the three pure codec/dispatch
-- functions -- SerializeHello, ParseHello, Dispatch -- which only transform their explicit
-- arguments, need no self, and are also handed out as bare function values (see Dispatch's
-- "exposed for the offline harness" assignment below).
local MAJOR, MINOR = "KASC-1.0", 6
local KASC = LibStub:NewLibrary(MAJOR, MINOR)
if not KASC then return end

local KAUtil = LibStub("KAUtil-1.0")
local KAGS   = LibStub("KAGS-1.0")
-- The transport. Everything this library sends goes through ChatThrottleLib's queue underneath it,
-- and everything it receives comes back out of AceComm already reassembled (see Send and Init).
local AceComm = LibStub("AceComm-3.0")

KASC.Identity = KASC.Identity or {}
local Identity = KASC.Identity

local prefix
local handlers = { exact = {}, payload = {} }
local caches = {}
local addons = {}      -- array, insertion order, so the handshake is deterministic
local capabilities = {} -- array of { owner, name, fn }
local peerCallbacks = {}
local lastAnnounced = {} -- channel -> the handshake string last sent there (see AnnounceHelloIfChanged)

function KASC:DefaultChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

-- Why any of this exists: on 2026-08-03 a raid lost four different messages -- an End Round, two roll
-- announcements and four votes -- and not one client anywhere said so. Every loss looked like a
-- different bug on a different screen, and telling them apart took the whole evening (B118, B120).
-- These counters are deliberately NOT a fix: they are what makes the next raid say which of the
-- possible causes it actually was, instead of another round of inference.
--
-- Since the transport moved onto ChatThrottleLib, a throttled send is retried rather than lost, so
-- "throttled" stopped being a loss and is not counted any more. What is left worth asking is whether
-- a message had to WAIT, which is what sendQueued answers -- and the library never reports a throttle
-- to its caller anyway (it re-queues silently), so the old counter could not have survived.
--
-- The RESULT CODE is gone with it, and not by choice: ChatThrottleLib hands its callback
-- (didSend, sendResult), but AceComm's shim takes only two arguments and drops the code on the way
-- through (AceComm-3.0 r14). What reaches a consumer is the boolean, so "it was refused" survives
-- and "this is what the client answered" does not. Patching the bundled library is the wrong trade:
-- it would have to be re-patched on every update, and the counter below already separates the three
-- causes that mattered on 2026-08-03.
--
-- Read back through KASC:Diagnostics(); KART prints them in /kart status when any of them is non-zero.
KASC.diag = KASC.diag or {
    sendRejected = 0,   -- the transport reported the message as not sent
    sendQueued = 0,     -- ...or it did not leave at once and waited in ChatThrottleLib's queue
    dropNotInGroup = 0, -- an otherwise valid message refused because its sender is not in our group
    dropUnknownToken = 0, -- a message in our prefix whose token this client has no handler for
    sendHeldBack = 0,   -- held while addon comms were restricted, and sent afterwards
    sendDroppedRestricted = 0, -- not worth holding, so dropped while restricted (heartbeats, requests)
    sendRetried = 0,    -- a refused guaranteed message put back on the wire (see SEND_RETRY_DELAYS)
    sendGaveUp = 0,     -- ...and still refused after the last attempt, so genuinely lost
    -- [token] = messages handed to the transport under that token, retries included -- they are wire
    -- traffic like any other. The counters above say whether the pipe struggled; this says WHICH
    -- conversation filled it, which is the question B135 could only answer offline. A table among
    -- numbers, so any consumer summing "the counters" must skip it (KART's /kart status names its
    -- fields instead of iterating, so nothing does that today).
    sentByToken = {},
}

-- =====================================================================
--  Addon restrictions
-- =====================================================================
-- Midnight gates parts of what an addon may do while an encounter or a Mythic+ run is active, and
-- announces it with ADDON_RESTRICTION_STATE_CHANGED (Enum.AddOnRestrictionType /
-- Enum.AddOnRestrictionState, both present in the 12.0.1 annotations). Addon messages are among the
-- things that stop going out.
--
-- Which matters here more than it looks: loot drops at the END of an encounter. A roll announcement
-- sent in that window is not delayed, it is gone -- and every client that missed it is left with an
-- item it never heard of, which is the shape of the losses on 2026-08-03 (B118).
--
-- ENCOUNTER and CHALLENGEMODE only, and that reading is taken from the addon that has been living
-- with this in production (RCLootCouncil's own comment: combat is the exception, and comms still work
-- inside instances with the map restriction on). It is an observation, not documentation -- so this
-- is written to fail SAFE in both directions: if the reading is too narrow the counters in
-- /kart status show sends being rejected anyway, and if it is too wide the only cost is that a
-- message waits for the encounter to end.
local RESTRICT_ENCOUNTER      = 1 -- Enum.AddOnRestrictionType.Encounter
local RESTRICT_CHALLENGE_MODE = 2 -- Enum.AddOnRestrictionType.ChallengeMode

local activeRestrictions = {}

local function CommsRestricted()
    return activeRestrictions[RESTRICT_ENCOUNTER] or activeRestrictions[RESTRICT_CHALLENGE_MODE] or false
end
KASC.CommsRestricted = CommsRestricted

-- The event above is the only thing that ever announced the gate, and a client that reloads or relogs
-- DURING an encounter was not there to hear it -- which is this guild's ordinary operating state,
-- people do it mid-pull (B140). It came back believing comms were open, so its guaranteed messages
-- skipped the hold queue, reached a transport that refused them, burned all three retries in six
-- seconds and ended in sendGaveUp: genuinely lost, the B118 shape the hold machinery exists to
-- prevent. So ask the client outright instead of waiting to be told.
--
-- Asked at BOTH load moments on purpose. Init runs on ADDON_LOADED, behind the loading screen, and
-- whether the client can already answer for the encounter it is reloading INTO is not something an
-- addon gets to decide; PLAYER_ENTERING_WORLD is the moment the world is there and the answer is
-- certainly true. Asking twice costs two API calls and covers a state that changed between them.
--
-- GetAddOnRestrictionState rather than IsAddOnRestrictionActive (both are in the 12.0.1 annotations):
-- it answers the same Enum.AddOnRestrictionState the event carries, so "Activating counts as active"
-- stays one rule in one place, and it is the one that keeps answering during the event's own dispatch.
-- pcall'd for the same reason the event registration below is: an older client has no such API, and
-- the cost of being wrong must be that this seed is inert, never that the library fails to load.
--
-- No flush here, and it only ever CLOSES the gate. Note what that does NOT say: PLAYER_ENTERING_WORLD
-- fires on every zone and instance transition, not only at load, so "nothing has been queued yet" --
-- which is what stood here -- is not true in general. What is true is that the queue can only hold
-- something while the gate is shut, and this function never opens it, so there is never anything to
-- flush AT this call. The release still arrives as ADDON_RESTRICTION_STATE_CHANGED and still flushes.
local function SeedRestrictions()
    local ask = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
    if not ask then return end
    for _, t in ipairs({ RESTRICT_ENCOUNTER, RESTRICT_CHALLENGE_MODE }) do
        local ok, state = pcall(ask, t)
        if ok and ((state == 2) or (state == 1)) then activeRestrictions[t] = true end
    end
end

-- Messages that must survive the restriction rather than be lost by it. Capped, deduplicated, and
-- flushed in order once comms come back. Everything else is dropped while restricted: a heartbeat or
-- a state request that arrives forty seconds late is noise, not repair.
local GUARANTEED_MAX = 40
local guaranteedQueue = {}

local function FlushGuaranteed()
    if #guaranteedQueue == 0 then return end
    local pending = guaranteedQueue
    guaranteedQueue = {}
    for _, m in ipairs(pending) do
        -- Options carried through, not dropped: a held message keeps the priority it was sent with,
        -- and the release is exactly the burst where that priority decides who waits for whom.
        KASC:Send(m.msg, m.channel, m.target, m.opts)
    end
end

function KASC:OnRestrictionChanged(restrictionType, state)
    -- "Activating" counts as active: the client raises it before the restriction is enforced, which is
    -- the one moment a send would still succeed -- and a message that goes out at the very start of an
    -- encounter is not what this is protecting.
    local active = (state == 2) or (state == 1) -- Active / Activating
    activeRestrictions[restrictionType] = active or nil
    if not CommsRestricted() then FlushGuaranteed() end
end

function KASC:Diagnostics()
    return KASC.diag
end

-- How long to wait before putting a refused guaranteed message back on the wire, one entry per
-- attempt. ChatThrottleLib retries exactly one failure of its own -- SendAddonMessageResult
-- .AddonMessageThrottle, see IsThrottledSendResult -- and hands every other result straight to the
-- callback as "not sent", which until now ended the message's life. It is not a rare path: a raid on
-- 2026-08-05 refused 71 of the lootmaster's sends with 1578 more waiting in the queue, and the
-- clients that lost an LC_DROP that way spent the evening with items they had never heard of --
-- no auto-pass, no vote row, and a "was never announced" line hours later.
--
-- Only guaranteed messages come back: those are the ones whose loss costs the raid something (see
-- the opts.guaranteed note below). A question or a heartbeat that fails has already been overtaken
-- by the next one. Bounded on purpose -- a client that cannot send at all must not spend the
-- evening trying, and three attempts across six seconds is the whole budget.
local SEND_RETRY_DELAYS = { 0.5, 1.5, 4 }

-- opts.guaranteed: this message is worth holding until comms come back (see CommsRestricted). Loot
-- announcements, awards, votes and the session flag are; heartbeats and requests are not.
-- opts.prio: ChatThrottleLib's priority -- "ALERT", "NORMAL" (the default) or "BULK". The three get
-- an equal share of the available bandwidth, so this decides who waits for whom when the pipe is
-- full. WHICH message deserves which is the consumer's knowledge and deliberately stays out of here;
-- see LC.SendLC for the table that holds it.
--
-- No return value any more. The transport answers asynchronously: a message can be queued now and
-- sent a moment later, so there is nothing truthful to hand back at the call site. What the send did
-- is recorded in KASC.diag instead.
function KASC:Send(msg, channel, target, opts)
    if CommsRestricted() then
        if opts and opts.guaranteed and #guaranteedQueue < GUARANTEED_MAX then
            for _, m in ipairs(guaranteedQueue) do
                -- Identical message, same destination: the sender is retrying inside the window, and
                -- delivering it twice afterwards is at best noise.
                if m.msg == msg and m.channel == channel and m.target == target then
                    return
                end
            end
            guaranteedQueue[#guaranteedQueue + 1] =
                { msg = msg, channel = channel, target = target, opts = opts }
            KASC.diag.sendHeldBack = KASC.diag.sendHeldBack + 1
        else
            KASC.diag.sendDroppedRestricted = KASC.diag.sendDroppedRestricted + 1
        end
        return
    end

    -- ChatThrottleLib calls this back SYNCHRONOUSLY when it sent straight away, and later -- or, if
    -- it re-queues after a throttle, not until the retry succeeds -- when it had to wait. That timing
    -- is the only signal a caller gets about which of the two happened, and it is what sendQueued is
    -- read from below.
    --
    -- The last argument is AceComm's, not CTL's: a BOOLEAN saying whether the message went out (see
    -- the note on KASC.diag). Only an explicit false counts -- a client that answers nothing at all
    -- reaches here as true, and "no answer" must never read as "everything failed".
    -- Which attempt this is, carried in the options so a retry can find its own place in
    -- SEND_RETRY_DELAYS. Absent on every call a consumer makes, which is what makes the first send
    -- attempt zero.
    local attempt = (opts and opts.attempt) or 0
    local guaranteed = opts and opts.guaranteed

    -- Counted where the message actually reaches the transport: a send refused by the restriction
    -- gate above never went anywhere, and a retry that lands here is a second real message.
    -- The `or {}` is the upgrade seam, not defensiveness: when an OLDER minor initialized KASC.diag
    -- first, `KASC.diag or {...}` above kept a table with no sentByToken in it, and this line is the
    -- first to touch the field after the LibStub handover.
    local token = msg:match("^([^:]+)") or msg
    KASC.diag.sentByToken = KASC.diag.sentByToken or {}
    KASC.diag.sentByToken[token] = (KASC.diag.sentByToken[token] or 0) + 1
    -- One retry per message, not one per chunk. AceComm splits anything over 255 bytes and gives
    -- every piece its own callback, so a pipe that refuses one piece usually refuses the rest --
    -- and re-sending the whole message once per refused chunk would multiply the traffic that
    -- caused the refusal in the first place.
    local retried = false

    local sentAtOnce = false
    local function OnSent(_, _, _, didSend)
        sentAtOnce = true
        if didSend ~= false then return end
        KASC.diag.sendRejected = KASC.diag.sendRejected + 1
        if not guaranteed or retried then return end
        retried = true
        local delay = SEND_RETRY_DELAYS[attempt + 1]
        if not delay then
            KASC.diag.sendGaveUp = KASC.diag.sendGaveUp + 1
            return
        end
        KASC.diag.sendRetried = KASC.diag.sendRetried + 1
        -- A copy, so the attempt number cannot leak back into the caller's own table -- consumers
        -- build these per send (see LC.SendLC) but a held message keeps its options across the
        -- restriction queue, and that table would otherwise carry a stale count into its release.
        local nextOpts = {}
        for k, v in pairs(opts) do nextOpts[k] = v end
        nextOpts.attempt = attempt + 1
        -- channel stays exactly as the caller gave it, nil included: re-resolving DefaultChannel at
        -- the next attempt is what keeps a party that became a raid in between from being addressed
        -- on the channel it no longer has.
        C_Timer.After(delay, function() KASC:Send(msg, channel, target, nextOpts) end)
    end

    AceComm:SendCommMessage(prefix, msg, channel or self:DefaultChannel(), target,
                            (opts and opts.prio) or "NORMAL", OnSent)

    if not sentAtOnce then KASC.diag.sendQueued = KASC.diag.sendQueued + 1 end
end

function KASC:AttachCache(tbl)
    assert(type(tbl) == "table", "KASC: cache must be a table")
    for _, t in ipairs(caches) do if t == tbl then return end end
    caches[#caches + 1] = tbl
end

function KASC:RegisterAddon(name, version)
    assert(type(name) == "string" and name:match("^[%w%.%-_]+$"), "KASC: bad addon name")
    assert(type(version) == "string" and version:match("^[%w%.%-_]+$"), "KASC: bad version")
    for _, a in ipairs(addons) do
        if a.name == name then a.version = version return end
    end
    addons[#addons + 1] = { name = name, version = version }
end

function KASC:RegisterCapability(owner, name, fn)
    assert(type(name) == "string" and name:match("^[%w%.%-_]+$"), "KASC: bad capability name")
    assert(type(fn) == "function", "KASC: capability must be a predicate function")
    capabilities[#capabilities + 1] = { owner = owner, name = name, fn = fn }
end

-- opts.payload  true  -> "TOKEN:rest", the handler parses its own payload
--               false -> the token must be the entire message
-- opts.group    true  -> the sender must be in our group, compared with realm
-- opts.enabled  fn    -> arbitrary predicate; this is what keeps feature knowledge out of here
function KASC:RegisterMessage(token, opts, fn)
    assert(type(token) == "string" and token ~= "", "KASC: token must be a non-empty string")
    assert(not token:find(":"), "KASC: token must not contain a colon")
    assert(type(fn) == "function", "KASC: handler must be a function")
    local bucket = opts.payload and handlers.payload or handlers.exact
    assert(not bucket[token], "KASC: duplicate handler for " .. token)
    bucket[token] = { group = opts.group, enabled = opts.enabled, fn = fn }
end

function KASC:OnPeer(fn)
    peerCallbacks[#peerCallbacks + 1] = fn
end

-- =====================================================================
--  Identity resolution
-- =====================================================================

-- Resolves unit's Northern Sky Raid Tools nickname, or nil if NSRT isn't installed, has no
-- nickname stored for that character, or its "Global Nicknames" master toggle is off. NSAPI is
-- NSRT's own public API global (see its NickNames.lua) — calling GetName with no AddonName
-- argument makes it honor only that master toggle instead of a per-addon toggle KART was never
-- registered for (which would otherwise always read as disabled, see NSAPI:GetName's own "if no
-- AddonName is given we assume it's from an old WeakAura" comment). Wrapped in pcall since this
-- reaches into another addon's code, which KASC never requires to be installed.
--
-- Returns two values: the lowercased nickname (for case-insensitive matching against configured
-- name lists — Auto-Promote, Loot Council members/lootmaster) and the nickname in its original
-- casing (for display, e.g. the council panel's name column). Extra return values are silently
-- dropped wherever a caller only wants the first one, so existing single-value call sites don't
-- need to change.
function Identity.GetNickname(unit)
    if not (unit and NSAPI and NSAPI.GetName and UnitExists(unit)) then return nil end
    local ok, nick = pcall(NSAPI.GetName, NSAPI, unit)
    if not ok or not nick or nick == "" then return nil end
    local realName = UnitName(unit)
    if nick == realName then return nil end -- no nickname set, NSAPI just echoed the real name back
    -- CaseFold (not :lower()) so an umlaut nickname folds the same way the promote/council
    -- lists and Identity's name matching fold their side — otherwise umlaut nicks never match.
    return KAUtil.CaseFold(nick), nick
end

-- Finds the current unit token matching name — compared against both the character name and the
-- NSRT nickname, exactly like LC.IsCouncil/LC.IsMe already do today.
--
-- Reviewed 2026-07-25, accepted as-is: matching is short-name based (UnitName's first return is
-- realm-free) and both this scan and the cache fallback in ResolvePlayer return the FIRST match
-- without an ambiguity guard. That's safe for this addon's use: the target raid never contains two
-- characters sharing a short name or an NSRT nickname (confirmed by the maintainer), so a collision
-- that would need a failsafe can't occur. Do not re-flag the missing ambiguity guard.
-- NOTE: because of that, resolution alone is NOT an authorization check — an out-of-group sender can
-- resolve onto a same-short-named group member. Anything acting on a sender's authority gates on
-- KAUtil.IsFullNameInGroup (see the `group` flag in KASC's dispatcher), which compares the realm too.
local function FindUnitForName(name)
    if not name or name == "" then return nil end
    -- CaseFold (not :lower()) so German umlaut names fold consistently — :lower() leaves
    -- Ö/Ä/Ü untouched, so a config name cased differently than the client returns wouldn't match.
    local lowerName = KAUtil.CaseFold(name)
    -- Also try the realm-stripped form. Input reaches here in two shapes: free-typed config text
    -- (short name or NSRT nickname, no realm) and a realm-qualified sender from CHAT_MSG_ADDON
    -- ("Bob-TarrenMill"). UnitName's first return is always realm-free, so the qualified shape can
    -- never match it directly — without this the live scan silently fails for every addon-message
    -- sender and resolution falls through to the persistent cache (or to "pending" on a cold cache,
    -- which drops the message entirely).
    -- Both forms are compared against both the character name and the NSRT nickname: a nickname
    -- containing a hyphen would otherwise be truncated by the split and stop matching.
    local shortName = KAUtil.CaseFold(name:match("^([^%-]+)") or name)
    for unit in KAUtil.EachGroupUnit() do
        local unitName = UnitName(unit)
        if unitName then
            local unitLower = KAUtil.CaseFold(unitName)
            if unitLower == lowerName or unitLower == shortName then return unit end
            local nick = Identity.GetNickname(unit)
            if nick and (nick == lowerName or nick == shortName) then return unit end
        end
    end
    return nil
end

-- Finds the current unit token whose UnitGUID matches key. Replaces LC.FindUnitForShortName
-- (short-name based, collision-prone) now that every caller holds a resolved key instead of a
-- short name.
function Identity.FindUnitForKey(key)
    if not key then return nil end
    for unit in KAUtil.EachGroupUnit() do
        if UnitGUID(unit) == key then return unit end
    end
    return nil
end

-- Writes this player into every attached cache. After a split each addon attaches its own
-- SavedVariable and they stay consistent automatically, with no question of ownership.
-- A silent no-op if nothing is attached yet -- there is nowhere to write, and this deliberately
-- does not create a fallback table to write into instead (a cache nothing persists would be worse
-- than dropping the write). Every call site here runs from a live event, and the shipped load order
-- always calls KASC:AttachCache before KASC:Init, so in practice this never fires with an empty
-- cache list -- but that guarantee lives in the consumer's wiring, not in this function.
local function RememberPlayer(guid, unit)
    local name = UnitName(unit)
    if not guid or not name then return end -- loading-screen edge: UnitGUID/UnitName can be nil
    local _, nick = Identity.GetNickname(unit)
    for _, cache in ipairs(caches) do
        cache[guid] = { name = Ambiguate(name, "none"), nickname = nick, lastSeen = time() }
    end
end

-- Scans every attached cache. Returns the first match; the target raid never contains two
-- characters sharing a short name or an NSRT nickname, which is why no ambiguity guard is
-- needed here (see docs/REVIEW-DECISIONS.md -- do not re-flag this).
local function LookupCachedKey(lowerInput)
    for _, cache in ipairs(caches) do
        for guid, entry in pairs(cache) do
            if (entry.name and KAUtil.CaseFold(entry.name) == lowerInput)
               or (entry.nickname and KAUtil.CaseFold(entry.nickname) == lowerInput) then
                return guid
            end
        end
    end
    return nil
end

-- Resolves input — a unit token, a full realm-qualified name (as delivered by CHAT_MSG_ADDON's
-- sender argument), or free-typed config text (short name or NSRT nickname) — to a stable key.
--
-- Returns key, isPending. isPending is true only when nobody in the group currently matches AND
-- no cache entry exists either; key is then just the trimmed, lowercased input text itself, so a
-- caller that stores it (e.g. the council list) has a stable placeholder to retry later — see
-- IsResolvedKey below for how a retry pass tells a real key apart from still-pending text.
function Identity.ResolvePlayer(input)
    if not input or input == "" then return input, true end

    -- Already a valid unit token. UnitGUID can momentarily be nil on a loading-screen edge; only
    -- treat it as resolved once we actually have a GUID, otherwise fall through to name/cache/pending.
    if UnitExists(input) then
        local guid = UnitGUID(input)
        if guid then
            RememberPlayer(guid, input)
            return guid, false
        end
    end

    -- Name string (full realm-qualified sender, or free-typed short name/nickname) — scan the
    -- group for a live match.
    local unit = FindUnitForName(input)
    if unit then
        local guid = UnitGUID(unit)
        if guid then
            RememberPlayer(guid, unit)
            return guid, false
        end
    end

    -- No live match — fall back to the persistent cache (last-known GUID for this name or
    -- nickname), for someone who was seen before but isn't currently in the group.
    -- Cache entries store the realm-free short name (UnitName), so normalize the input the same way
    -- — trimmed, realm stripped, case-folded — otherwise a realm-qualified sender ("Name-Realm" from
    -- CHAT_MSG_ADDON) never matches, and untrimmed input disagrees with the pending key below.
    local trimmed = KAUtil.TrimString(input)
    local lowerInput = KAUtil.CaseFold(trimmed:match("([^%-]+)") or trimmed)
    local cachedKey = LookupCachedKey(lowerInput)
    if cachedKey then return cachedKey, false end

    -- Never seen — pending.
    return KAUtil.CaseFold(KAUtil.TrimString(input)), true
end

-- Inverse of ResolvePlayer, for rendering a stored key back to a human-readable name. Only needed
-- where a key must be displayed without a live unit already in hand — UI row-building keeps
-- using UnitName(unit) directly for display, since it already has the unit token there.
function Identity.ResolveDisplayName(key)
    if not key then return "?" end
    local unit = Identity.FindUnitForKey(key)
    if unit then return Ambiguate(UnitName(unit), "short") end
    for _, cache in ipairs(caches) do
        local entry = cache[key]
        if entry then
            return entry.nickname or (entry.name and Ambiguate(entry.name, "short")) or key
        end
    end
    return key
end

-- A resolved key looks like a WoW GUID ("Player-1234-XXXXXXXX"); pending config text (see
-- ResolvePlayer) is just plain lowercased text and never matches this shape. Used by the
-- pending-resolution retry (LootCouncil.lua's LC.RetryPendingResolutions) to tell the two apart
-- without a separate boolean tracked
-- alongside every stored key.
function Identity.IsResolvedKey(key)
    return type(key) == "string" and key:match("^Player%-") ~= nil
end

-- =====================================================================
--  Dispatcher
-- =====================================================================

-- Identity resolution stays lazy. Resolving eagerly would scan up to 40 units for every
-- message including the many that never look at the sender's key.
local ctxProto = {}
local ctxMeta = { __index = ctxProto }

function ctxProto:Key()
    if self._key == nil then self._key = (Identity.ResolvePlayer(self.sender)) end
    return self._key
end

local function Dispatch(msg, channel, sender)
    if not sender then return end
    local shortName = sender:match("([^%-]+)")
    if not shortName then return end
    -- Our own message, coming back. CHAT_MSG_ADDON fires on the SENDER too for every group and
    -- guild channel (measured in a live client, 2026-07-30, on PARTY and on GUILD) -- the server
    -- reflects the message and nothing below this line can tell it apart from a peer's.
    --
    -- Every consumer is written the other way round: whatever the sender needs to do to its own
    -- state, it does itself, right where it sends (LC.ApplyOwnConfig, OnStartLootRoll opening its
    -- own windows, AssignWinner recording its own result). Letting the echo through runs all of
    -- that a second time -- harmless where it is repeatable, and not harmless where it is not: the
    -- echo of a raid leader's own LC_CONFIG marked their config as RECEIVED, which took the config
    -- ownership away from them on the empty-lootmaster-field setup, and their handover
    -- announcement with it.
    --
    -- Dropped here, once, rather than in twenty handlers: a self-check every handler has to
    -- remember is a self-check some handler will forget.
    if KAUtil.IsSelfFullName(sender) then return end

    local token, payload = msg:match("^([^:]+):(.*)$")
    local entry = (token and handlers.payload[token]) or handlers.exact[msg]
    -- Counted, because this is what a peer on a newer protocol looks like from here: the message
    -- arrives, is dropped without a word, and the two clients disagree about the evening (B62).
    if not entry then KASC.diag.dropUnknownToken = KASC.diag.dropUnknownToken + 1 return end
    if entry.enabled and not entry.enabled() then return end
    -- The resolved key alone is NOT proof of membership: resolution is short-name based, so an
    -- out-of-group player sharing a short name with a council member would otherwise resolve
    -- onto their GUID and pass every authority check. IsFullNameInGroup compares the realm too.
    -- Counted for the same reason: a roster that is briefly stale refuses the real sender's message,
    -- and the refusal is indistinguishable from the message never arriving (B118).
    if entry.group and not KAUtil.IsFullNameInGroup(sender) then
        KASC.diag.dropNotInGroup = KASC.diag.dropNotInGroup + 1
        return
    end

    entry.fn(payload, setmetatable(
        { sender = sender, shortName = shortName, channel = channel }, ctxMeta))
end

KASC.Dispatch = Dispatch -- exposed for the offline harness

-- CHAT_MSG_ADDON is AceComm's from here on (see Init): it owns the reassembly of anything longer
-- than one addon message, and a second listener on the raw event would hand the chunks of a
-- multipart message to Dispatch as if each were a message of its own.
local frame = CreateFrame("Frame")
-- pcall'd for the same reason Core.lua guards LOOT_HISTORY_UPDATE_DROP: RegisterEvent throws on a
-- name the client does not know, this one comes from annotations for a version the live client may
-- not be on yet, and the cost of being wrong must be "this one guard is inert", never "the library
-- fails to load and takes the addon with it".
pcall(frame.RegisterEvent, frame, "ADDON_RESTRICTION_STATE_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, a, b)
    -- ADDON_RESTRICTION_STATE_CHANGED: type, state.
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        KASC:OnRestrictionChanged(a, b)
    elseif event == "PLAYER_ENTERING_WORLD" then
        SeedRestrictions()
    end
end)

function KASC:Init(p)
    -- prefix is the library's only single-valued consumer-supplied state -- everything else
    -- (addons, capabilities, handlers, caches) fans out into an array or a registry keyed by
    -- name, so two consumers coexist there for free. A second consumer calling Init with a
    -- different prefix would silently repoint every future Send and every inbound filter onto
    -- its own channel instead, so fail loudly rather than let that happen quietly.
    assert(prefix == nil or prefix == p, "KASC: Init already called with a different prefix")
    prefix = p
    SeedRestrictions()
    -- AceComm registers the prefix itself, owns the event frame, and hands over a message that is
    -- already reassembled. Dispatch is unchanged behind it: the self-echo drop, the group check and
    -- the counters all sit where they sat.
    AceComm.RegisterComm(self, p, function(_, msg, channel, sender)
        Dispatch(msg, channel, sender)
    end)
end

-- =====================================================================
--  Responders — the answering side. These must work in any KA client, including one that has no
--  Buff Checker of its own and will never render what it reports.
-- =====================================================================
-- group = true on every one of these for a disclosure reason, not an authority one: the addon-
-- message prefix is public and CHAT_MSG_ADDON also delivers WHISPER and GUILD, so literally any player can
-- send REQ_OIL/REQ_ILVL/REQ_ENCH/REQ_GEAR, in or out of our group. Answering a request from outside
-- the group would hand a stranger our own gear, enchant and item-level state. That's also why every
-- reply below broadcasts to the group channel rather than replying to the sender directly — the
-- point is never to single-source data back to an asker, only to keep it inside the group.

-- Per-token answer cooldown. Every one of these is a raid-wide broadcast, so the first reply
-- already served everyone who asked -- anything inside the window is a duplicate that only costs
-- bandwidth. Without it, one Buff Checker refresh in a 20-man raid is 60 outbound answers, and a
-- few impatient clicks overrun Blizzard's chat rate limiter, which drops the overflow SILENTLY.
-- Nothing retries, so the rows that lost their answer stay empty for the rest of the session.
--
-- The same reasoning already carried REQ_EQUIP's own cooldown in the consumer (see
-- EQUIP_ANSWER_COOLDOWN in LootCouncilPanel.lua); these four never got one.
local ANSWER_COOLDOWN = 5
local lastAnswer = {} -- [token] = GetTime() of our last reply, written only on an actual send

local function OnAnswerCooldown(token)
    local now = GetTime()
    if now - (lastAnswer[token] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN then return true end
    lastAnswer[token] = now
    return false
end

KASC:RegisterMessage("REQ_OIL", { group = true }, function()
    if OnAnswerCooldown("REQ_OIL") then return end
    local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
    -- "n" for a hand that takes no oil at all (empty, shield, caster off-hand), so the receiver
    -- can tell it apart from a weapon that is simply unoiled ("0"). Only we see our own gear.
    local outMH = KAGS.SlotNeedsOil(16) and ((hasMH and mhID) and mhID or 0) or "n"
    local outOH = KAGS.SlotNeedsOil(17) and ((hasOH and ohID) and ohID or 0) or "n"
    if IsInGroup() then KASC:Send("OIL:" .. outMH .. ":" .. outOH) end
end)

KASC:RegisterMessage("REQ_ILVL", { group = true }, function()
    if OnAnswerCooldown("REQ_ILVL") then return end
    local _, equipped = GetAverageItemLevel()
    if equipped and IsInGroup() then
        KASC:Send("ILVL:" .. string.format("%.1f", equipped))
    end
end)

KASC:RegisterMessage("REQ_ENCH", { group = true }, function()
    if OnAnswerCooldown("REQ_ENCH") then return end
    -- Maintenance scan, not part of any display path -- it exists so the accepted-enchant
    -- lists can be checked against what the raid actually wears.
    if IsInGroup() then KASC:Send("ENCH:" .. KAGS.SerializeOwnEnchantIDs()) end
end)

KASC:RegisterMessage("REQ_GEAR", { group = true }, function()
    if OnAnswerCooldown("REQ_GEAR") then return end
    if IsInGroup() then
        local e, g = KAGS.CountMissingGear()
        KASC:Send("GEAR:" .. e .. ":" .. g)
    end
end)

-- =====================================================================
--  Handshake
-- =====================================================================
-- Grammar: entries separated by ",", each "name=version" with optional "+capability" suffixes.
-- Name, version and capability are restricted to [%w%.%-_], so a colour escape or a hyperlink
-- cannot reach the consumer's chat output or the council panel at all -- a whitelist rather than
-- escaping after the fact.
--
-- Library versions are deliberately absent: nothing branches on them, so putting them on the
-- wire would be speculative.
local ENTRY_CHARS = "^[%w%.%-_]+$"

function KASC.SerializeHello()
    local out = {}
    for _, addon in ipairs(addons) do
        local entry = addon.name .. "=" .. addon.version
        for _, cap in ipairs(capabilities) do
            if cap.owner == addon.name and cap.fn() then
                entry = entry .. "+" .. cap.name
            end
        end
        out[#out + 1] = entry
    end
    return table.concat(out, ",")
end

function KASC.ParseHello(payload)
    local result = {}
    if type(payload) ~= "string" or payload == "" then return result end
    for entry in payload:gmatch("[^,]+") do
        local name, version, rest = entry:match("^([^=+]+)=([^=+]+)(.*)$")
        -- rest must be nothing but zero or more "+capability" suffixes -- not just "no unknown
        -- characters in any capability we happen to find". Without this, a second "=" (e.g.
        -- "KART=3.0.0=x") or stray text before the first "+" (e.g. "KART=1=2+LC") was silently
        -- swallowed instead of rejecting the entry, because gmatch below only ever looks for
        -- "+"-prefixed runs and never verifies that they account for the whole tail. Lua patterns
        -- can't quantify a capture group, so this strips every well-formed "+xxx" chunk and
        -- requires nothing to be left over, rather than trying to anchor a repeated group.
        if name and version and rest and rest:gsub("%+[^+]*", "") == ""
           and name:match(ENTRY_CHARS) and version:match(ENTRY_CHARS) then
            local caps, ok = {}, true
            for cap in rest:gmatch("%+([^+]*)") do
                if cap:match(ENTRY_CHARS) then caps[cap] = true else ok = false end
            end
            -- One malformed capability drops the whole entry rather than silently reporting a
            -- peer as having fewer capabilities than it claimed.
            if ok then result[name] = { version = version, caps = caps } end
        end
    end
    return result
end

-- channel/target default the same way KASC:Send does (nil -> DefaultChannel(), untargeted), so a
-- caller that needs GUILD (or any other explicit channel) never has to know the wire token to get
-- it -- both entry points below exist so the "KA_HELLO"/"KA_HELLO_REQ" strings stay inside this
-- library and never need to be spelled out by a consumer.
-- BULK on both handshake senders, and this is the storm the priority split exists for: one version
-- check in a 25-man raid is answered by 24 clients inside three seconds (see HELLO_ANSWER_SPREAD).
-- None of it is urgent, and all of it used to compete with the loot flow for the same pipe.
function KASC:RequestHello(channel, target)
    self:Send("KA_HELLO_REQ", channel, target, { prio = "BULK" })
end

-- Marks a handshake sent in ANSWER to a request, so a consumer can tell a reply apart from an
-- unsolicited announcement. /kart v prints one line per answer, and a passive announcement landing
-- inside its window -- someone joining the group, or toggling a capability -- used to print a line
-- of its own, for a request that person never received (B10).
--
-- Carried as an extra pseudo-addon entry rather than a new message token, deliberately: the wire
-- grammar already accepts "name=version" entries and a 3.0.x client simply parses this one into a
-- peers.ACK nobody reads. A separate token would have been invisible to those clients entirely,
-- which would have broken cross-version version checks to fix a stray line of text.
local ACK_ENTRY = "ACK=1"

-- solicited: true when this answers a KA_HELLO_REQ (see the responder below). Only affects what
-- the receiving consumer is told; the addon/capability content is identical either way.
function KASC:AnnounceHello(channel, target, solicited)
    local payload = KASC.SerializeHello()
    -- Recorded WITHOUT the ack marker, so an unsolicited announce and a reply compare equal --
    -- otherwise AnnounceHelloIfChanged would fire an extra announce after every version check.
    lastAnnounced[channel or self:DefaultChannel()] = payload
    if solicited then payload = payload .. "," .. ACK_ENTRY end
    self:Send("KA_HELLO:" .. payload, channel, target, { prio = "BULK" })
end

-- Announces only if what we would say has changed since we last said it on this channel, or if we
-- have never said anything there.
--
-- Peers cache what a HELLO tells them (version, capabilities) until the next one arrives, so a
-- capability that flips after the announce leaves every other client holding a stale answer for the
-- rest of the session. That is not hypothetical: KART's Loot Council module defaults to OFF, so a
-- user enabling it after login was recorded as having it disabled everywhere, and every council
-- panel in the raid showed them as "Loot Council disabled on their end" while it plainly worked.
--
-- Per channel, because GUILD and the group channel are announced at different times and a peer on
-- one is not necessarily on the other.
function KASC:AnnounceHelloIfChanged(channel, target)
    local ch = channel or self:DefaultChannel()
    if lastAnnounced[ch] == KASC.SerializeHello() then return end
    self:AnnounceHello(channel, target)
end

-- Answers are spread over this, and the reason is the same one written above the four other
-- responders' cooldown -- it was simply never applied here. One request in a 25-man raid is answered
-- by 24 clients in the same instant; Blizzard's rate limiter drops the overflow silently, nothing
-- retries, and the peers whose answer was lost show up on every council panel in the raid as "no KART
-- detected" for the rest of the evening. That is not a reconstruction: it happened on 2026-08-03, and
-- one manual /kart v cleared the whole raid (B120).
local HELLO_ANSWER_SPREAD = 3

-- Each client's own slot in that window, from its NAME rather than from math.random. Two reasons, and
-- the second is the stronger one:
--   * randomness can collide -- twenty draws out of one window put several answers in the same
--     fraction of a second by chance, which is the thing being avoided;
--   * every client in a raid has a different name, so hashing it spreads them by construction, and
--     the same client answers in the same slot every time, which makes this testable at all.
local function SelfAnswerSlot()
    local name = UnitName("player") or ""
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 997 end
    return (h / 997) * HELLO_ANSWER_SPREAD
end

-- Cooled PER ASKER, not per token. The four responders above broadcast their answer, so the first
-- reply already served everyone and a second is pure duplication -- but a hello answered by whisper
-- goes to exactly one client, and a shared cooldown would silence every asker after the first.
KASC:RegisterMessage("KA_HELLO_REQ", {}, function(_, ctx)
    local whisper = ctx.channel == "WHISPER"
    if OnAnswerCooldown("KA_HELLO:" .. (whisper and ctx.sender or "GROUP")) then return end
    local channel = whisper and "WHISPER" or ctx.channel
    local target  = whisper and ctx.sender or nil
    C_Timer.After(SelfAnswerSlot(), function()
        KASC:AnnounceHello(channel, target, true)
    end)
end)

KASC:RegisterMessage("KA_HELLO", { payload = true }, function(payload, ctx)
    local peers = KASC.ParseHello(payload)
    local solicited = peers.ACK ~= nil
    peers.ACK = nil -- an internal marker, not a peer addon; consumers must never see it as one
    for _, fn in ipairs(peerCallbacks) do fn(ctx.shortName, ctx.sender, peers, solicited) end
end)
