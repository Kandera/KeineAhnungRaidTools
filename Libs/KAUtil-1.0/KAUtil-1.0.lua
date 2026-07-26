-- KAUtil-1.0: string, group, item-link and table helpers shared by every KA addon and by the
-- other KA libraries. No dependencies, no user-visible strings, no state.
local MAJOR, MINOR = "KAUtil-1.0", 1
local KAUtil = LibStub:NewLibrary(MAJOR, MINOR)
if not KAUtil then return end

function KAUtil.TrimString(s)
    return s:match("^%s*(.-)%s*$")
end

-- Case-fold for comparison/search. Lua 5.1's string.lower is ASCII-only, so German umlauts (common
-- on DE realms) don't fold — "Ö" stays "Ö" and never matches "ö". Folds the umlauts too. Not a full
-- Unicode fold, just the letters WoW's German client uses. Fold BOTH sides of any comparison so the
-- result is self-consistent regardless of how the other side cased its input.
-- Uppercase to lowercase for the whole Latin-1 Supplement block. :lower() is ASCII-only in WoW's
-- Lua, so every one of these has to be folded by hand or a config entry typed in the "wrong" case
-- never matches what the client returns. This used to cover Ä/Ö/Ü alone, which is enough for German
-- character and realm names but not for NSRT nicknames — those are free text, so a nickname like
-- "Éclair" entered as "éclair" in the council or promote list silently failed to match.
local CASEFOLD_LATIN1 = {
    ["À"]="à", ["Á"]="á", ["Â"]="â", ["Ã"]="ã", ["Ä"]="ä", ["Å"]="å", ["Æ"]="æ", ["Ç"]="ç",
    ["È"]="è", ["É"]="é", ["Ê"]="ê", ["Ë"]="ë", ["Ì"]="ì", ["Í"]="í", ["Î"]="î", ["Ï"]="ï",
    ["Ð"]="ð", ["Ñ"]="ñ", ["Ò"]="ò", ["Ó"]="ó", ["Ô"]="ô", ["Õ"]="õ", ["Ö"]="ö",
    ["Ø"]="ø", ["Ù"]="ù", ["Ú"]="ú", ["Û"]="û", ["Ü"]="ü", ["Ý"]="ý", ["Þ"]="þ",
}

function KAUtil.CaseFold(s)
    if type(s) ~= "string" then return s end
    -- "\195[\128-\191]" is exactly the two-byte UTF-8 range C3 80..C3 BF, i.e. all of Latin-1
    -- Supplement and nothing else — the multiplication/division signs and the already-lowercase
    -- half simply aren't in the table and pass through. Everything outside that range (ASCII,
    -- Cyrillic, ...) is left to :lower(), which is what the previous gsub chain did too.
    return (s:gsub("\195[\128-\191]", function(c) return CASEFOLD_LATIN1[c] or c end):lower())
end

function KAUtil.HasGroupPermissions()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Iterates every current raid/party unit token, including the player. Returns (unit, index)
-- so callers that pool rows by position keep their index. Yields nothing when not in a group.
function KAUtil.EachGroupUnit()
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    local i = 0
    return function()
        i = i + 1
        if i > numMem then return nil end
        return (isRaid and ("raid" .. i) or (i == numMem and "player" or "party" .. i)), i
    end
end

-- Whether fullName (a realm-qualified "Name-Realm", as CHAT_MSG_ADDON delivers its sender) is a
-- member of our current group. Used to authorize addon messages that make us answer with our own
-- data, write into a shared cache, or act on someone else's authority — CHAT_MSG_ADDON also carries
-- WHISPER and GUILD, and the "KART" prefix is public, so an unauthorized sender is entirely possible.
--
-- Compares name AND realm separately, never the raw concatenation, because the two sides spell the
-- realm differently:
--   * CHAT_MSG_ADDON's sender is ALWAYS realm-qualified, with the realm in normalized form
--     ("Bob-TarrenMill") — including for a sender on our own realm.
--   * UnitName(unit)'s realm return is nil for a same-realm unit, and for a cross-realm one it may
--     carry the display spelling ("Tarren Mill").
-- So the realm is canonicalized on both sides (separators stripped, case-folded, same treatment
-- Droptimizer applies for the same reason) and a missing realm on either side means "our realm".
-- A raw "name-realm" string compare would reject EVERY same-realm member, silently disabling every
-- handler gated on this.
--
-- Deliberately not routed through Identity.ResolvePlayer: that falls back to a short-name cache
-- lookup for anyone not currently in the group, which would map an outsider onto a same-short-named
-- group member and wrongly authorize them. That is exactly what this function exists to prevent.
local function CanonRealm(realm)
    return KAUtil.CaseFold(((realm or ""):gsub("[%s%-']", "")))
end

function KAUtil.IsFullNameInGroup(fullName)
    if type(fullName) ~= "string" or fullName == "" then return false end
    local wantName, wantRealm = fullName:match("^([^%-]+)%-?(.*)$")
    if not wantName then return false end
    local ownRealm = CanonRealm(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName())
    wantName  = KAUtil.CaseFold(wantName)
    wantRealm = CanonRealm(wantRealm)
    if wantRealm == "" then wantRealm = ownRealm end

    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local unitRealm = CanonRealm(realm)
            if unitRealm == "" then unitRealm = ownRealm end
            if KAUtil.CaseFold(name) == wantName and unitRealm == wantRealm then return true end
        end
    end
    return false
end

function KAUtil.SplitString(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

-- Test mode uses plain coloured strings as fake items; guard against SetHyperlink on non-links.
function KAUtil.IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Full item string (itemID + every bonus ID), not just the bare itemID — two drops can share
-- an itemID while being different variants, and comparing only itemID would treat them as
-- interchangeable (see the auto-trade and history-export call sites).
function KAUtil.GetItemString(link)
    return KAUtil.IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
end

-- Plain recursive table copy — KART_Settings only ever holds strings, numbers, booleans, and
-- nested plain tables (e.g. the keybinds/minimap sub-tables), so no metatable/function handling
-- is needed here.
function KAUtil.DeepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            copy[k] = KAUtil.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Recursively fills missing default keys into dst, at every level. Unlike a shallow merge, a nested
-- default table that already exists in dst gets its missing sub-keys added instead of being skipped
-- whole — so a settings/profile blob saved before a nested default gained a field still picks that
-- field up on load. Only fills gaps; never overwrites a value dst already holds.
function KAUtil.MergeDefaults(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = KAUtil.DeepCopy(v)
            else
                KAUtil.MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
