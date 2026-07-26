local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")

KART.Identity = KART.Identity or {}
local Identity = KART.Identity

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
-- KAUtil.IsFullNameInGroup (see the `group` flag in KARTSync's dispatcher), which compares the realm too.
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
            local nick = KART.GetNickname(unit)
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

-- Writes/refreshes this player's entry in the persistent cross-session cache, used to resolve
-- config text for someone not currently in the group (see ResolvePlayer's cache fallback below).
local function RememberPlayer(guid, unit)
    local name = UnitName(unit)
    if not guid or not name then return end -- loading-screen edge: UnitGUID/UnitName can be nil
    KART_PlayerCache = KART_PlayerCache or {}
    local _, nick = KART.GetNickname(unit)
    KART_PlayerCache[guid] = {
        name = Ambiguate(name, "none"),
        nickname = nick,
        lastSeen = time(),
    }
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
    if KART_PlayerCache then
        for guid, entry in pairs(KART_PlayerCache) do
            if (entry.name and KAUtil.CaseFold(entry.name) == lowerInput) or (entry.nickname and KAUtil.CaseFold(entry.nickname) == lowerInput) then
                return guid, false
            end
        end
    end

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
    if KART_PlayerCache and KART_PlayerCache[key] then
        local entry = KART_PlayerCache[key]
        return entry.nickname or (entry.name and Ambiguate(entry.name, "short")) or key
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
