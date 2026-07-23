local addonName, KART = ...

KART.Identity = KART.Identity or {}
local Identity = KART.Identity

-- Iterates every current raid/party unit token, including the player — the same isRaid/numMem
-- loop already used in a few places in this addon (LC.FindUnitForShortName, which this module
-- replaces; KART.HandleAutoPromote in GroupLogic.lua; LC.RefreshCouncilRows in LootCouncil.lua).
-- Kept as its own local copy here rather than extracting a shared helper, to avoid touching
-- those unrelated call sites for this change.
local function EachGroupUnit()
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    local i = 0
    return function()
        i = i + 1
        if i > numMem then return nil end
        return isRaid and ("raid" .. i) or (i == numMem and "player" or "party" .. i)
    end
end

-- Finds the current unit token matching name — compared both as a realm-qualified full name
-- (via Ambiguate(fullName, "none"), which only keeps the "-Realm" suffix when two identically-
-- named characters would otherwise collide) and as an NSRT nickname, exactly like
-- LC.IsCouncil/LC.IsMe already do today. A name that IS genuinely ambiguous (two live matches)
-- deliberately fails to match here rather than guessing one of them — ResolvePlayer below falls
-- through to "pending" in that case, which is strictly safer than the short-name collision this
-- module exists to remove.
local function FindUnitForName(name)
    if not name or name == "" then return nil end
    local lowerName = name:lower()
    for unit in EachGroupUnit() do
        local fullName = UnitName(unit)
        if fullName then
            if Ambiguate(fullName, "none"):lower() == lowerName then return unit end
            local nick = KART.GetNickname(unit)
            if nick and nick == lowerName then return unit end
        end
    end
    return nil
end

-- Finds the current unit token whose UnitGUID matches key. Replaces LC.FindUnitForShortName
-- (short-name based, collision-prone) now that every caller holds a resolved key instead of a
-- short name.
function Identity.FindUnitForKey(key)
    if not key then return nil end
    for unit in EachGroupUnit() do
        if UnitGUID(unit) == key then return unit end
    end
    return nil
end

-- Writes/refreshes this player's entry in the persistent cross-session cache, used to resolve
-- config text for someone not currently in the group (see ResolvePlayer's cache fallback below).
local function RememberPlayer(guid, unit)
    KART_PlayerCache = KART_PlayerCache or {}
    local _, nick = KART.GetNickname(unit)
    KART_PlayerCache[guid] = {
        name = Ambiguate(UnitName(unit), "none"),
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

    -- Already a valid unit token.
    if UnitExists(input) then
        local guid = UnitGUID(input)
        RememberPlayer(guid, input)
        return guid, false
    end

    -- Name string (full realm-qualified sender, or free-typed short name/nickname) — scan the
    -- group for a live match.
    local unit = FindUnitForName(input)
    if unit then
        local guid = UnitGUID(unit)
        RememberPlayer(guid, unit)
        return guid, false
    end

    -- No live match — fall back to the persistent cache (last-known GUID for this name or
    -- nickname), for someone who was seen before but isn't currently in the group.
    local lowerInput = input:lower()
    if KART_PlayerCache then
        for guid, entry in pairs(KART_PlayerCache) do
            if (entry.name and entry.name:lower() == lowerInput) or (entry.nickname and entry.nickname:lower() == lowerInput) then
                return guid, false
            end
        end
    end

    -- Never seen — pending.
    return KART.TrimString(input):lower(), true
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
