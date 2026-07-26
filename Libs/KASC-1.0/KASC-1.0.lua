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
local MAJOR, MINOR = "KASC-1.0", 1
local KASC = LibStub:NewLibrary(MAJOR, MINOR)
if not KASC then return end

local KAUtil = LibStub("KAUtil-1.0")
local KAGS   = LibStub("KAGS-1.0")

KASC.Identity = KASC.Identity or {}
local Identity = KASC.Identity

local prefix
local handlers = { exact = {}, payload = {} }
local caches = {}
local addons = {}      -- array, insertion order, so the handshake is deterministic
local capabilities = {} -- array of { owner, name, fn }
local peerCallbacks = {}

function KASC:DefaultChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

function KASC:Send(msg, channel, target)
    C_ChatInfo.SendAddonMessage(prefix, msg, channel or self:DefaultChannel(), target)
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
-- pending-resolution retry (Task 10) to tell the two apart without a separate boolean tracked
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

    local token, payload = msg:match("^([^:]+):(.*)$")
    local entry = (token and handlers.payload[token]) or handlers.exact[msg]
    if not entry then return end
    if entry.enabled and not entry.enabled() then return end
    -- The resolved key alone is NOT proof of membership: resolution is short-name based, so an
    -- out-of-group player sharing a short name with a council member would otherwise resolve
    -- onto their GUID and pass every authority check. IsFullNameInGroup compares the realm too.
    if entry.group and not KAUtil.IsFullNameInGroup(sender) then return end

    entry.fn(payload, setmetatable(
        { sender = sender, shortName = shortName, channel = channel }, ctxMeta))
end

KASC.Dispatch = Dispatch -- exposed for the offline harness

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, msgPrefix, msg, ...)
    if event == "CHAT_MSG_ADDON" and msgPrefix == prefix then
        Dispatch(msg, (select(1, ...)), (select(2, ...)))
    end
end)

function KASC:Init(p)
    prefix = p
    C_ChatInfo.RegisterAddonMessagePrefix(p)
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

KASC:RegisterMessage("REQ_OIL", { group = true }, function()
    local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
    -- "n" for a hand that takes no oil at all (empty, shield, caster off-hand), so the receiver
    -- can tell it apart from a weapon that is simply unoiled ("0"). Only we see our own gear.
    local outMH = KAGS.SlotNeedsOil(16) and ((hasMH and mhID) and mhID or 0) or "n"
    local outOH = KAGS.SlotNeedsOil(17) and ((hasOH and ohID) and ohID or 0) or "n"
    if IsInGroup() then KASC:Send("OIL:" .. outMH .. ":" .. outOH) end
end)

KASC:RegisterMessage("REQ_ILVL", { group = true }, function()
    local _, equipped = GetAverageItemLevel()
    if equipped and IsInGroup() then
        KASC:Send("ILVL:" .. string.format("%.1f", equipped))
    end
end)

KASC:RegisterMessage("REQ_ENCH", { group = true }, function()
    -- Maintenance scan, not part of any display path -- it exists so the accepted-enchant
    -- lists can be checked against what the raid actually wears.
    if IsInGroup() then KASC:Send("ENCH:" .. KAGS.SerializeOwnEnchantIDs()) end
end)

KASC:RegisterMessage("REQ_GEAR", { group = true }, function()
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
function KASC:RequestHello(channel, target)
    self:Send("KA_HELLO_REQ", channel, target)
end

function KASC:AnnounceHello(channel, target)
    self:Send("KA_HELLO:" .. KASC.SerializeHello(), channel, target)
end

KASC:RegisterMessage("KA_HELLO_REQ", {}, function(_, ctx)
    if ctx.channel == "WHISPER" then
        KASC:AnnounceHello("WHISPER", ctx.sender)
    else
        KASC:AnnounceHello(ctx.channel)
    end
end)

KASC:RegisterMessage("KA_HELLO", { payload = true }, function(payload, ctx)
    local peers = KASC.ParseHello(payload)
    for _, fn in ipairs(peerCallbacks) do fn(ctx.shortName, ctx.sender, peers) end
end)
