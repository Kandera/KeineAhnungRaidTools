# Loot Council GUID-Based Player Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace short-name-string player identity (`shortName:lower()`, realm-suffix stripped) with a stable, collision-proof key (`UnitGUID`, falling back to a cached realm-qualified name) everywhere `LootCouncil.lua` compares or stores "who is this player" — votes, rolls, council membership, the lootmaster field, assign/officer-note wire messages, and pending trades.

**Architecture:** One new file, `Identity.lua`, provides `KART.Identity.ResolvePlayer(input)` (unit token / full name / free-typed text → key, plus a `pending` flag), `KART.Identity.ResolveDisplayName(key)` (key → human-readable name for rendering), and `KART.Identity.FindUnitForKey(key)` (key → live unit token, replacing the existing short-name-based `LC.FindUnitForShortName`). A new account-wide SavedVariable, `KART_PlayerCache`, remembers each GUID's last-known name/nickname so players who aren't currently in the group can still be resolved. Every existing per-player table (`LC.votes`, `LC.rolls`, `LC.councilVotes`, `LC.CouncilNamesTable`, `LC.assignedWinners`, `LC.pendingTrades`, `KART_LCOfficerNotes`) switches its key from short-name text to this resolved key. Three wire messages that name a *third party* chosen by the sender's own client (`LC_RESULT`'s winner, `LC_CVOTE`'s candidate, `LC_ONOTE`'s subject) change payload shape to carry the resolved key instead of bare short-name text, closing the same collision hole one level removed from the sender-identity fix. Hard cutover, no mixed-version wire compatibility attempted (see design doc).

**Tech Stack:** WoW Lua addon (retail), no build step, no automated test suite — verification is diff review plus the existing dev test harness (`LC.StartTest`) as a smoke test, then real-raid testing.

**Design doc:** `docs/superpowers/specs/2026-07-23-loot-council-guid-identity-design.md` — read this first for the full rationale. Two refinements found while writing this plan, not yet reflected in the design doc's prose (both are implementation-detail simplifications of already-approved decisions, not new scope):

1. **No separate "pending" marker value.** `KART.Identity.ResolvePlayer` returns a second value, `isPending`; when pending, the returned "key" is just the trimmed/lowercased input text, which never matches the `"Player-<serverID>-<UID>"` shape a real `UnitGUID` always has. `KART.Identity.IsResolvedKey(key)` checks that shape, so callers can tell a resolved key from still-pending text by looking at the key alone — no parallel "pending" table/marker needed anywhere.
2. **`LC_ONOTE` has the exact same third-party-payload issue as `LC_RESULT`/`LC_CVOTE`** (found reading `LC.SetOfficerNote`/`LC.HandleOfficerNote` while writing Task 9 below) — it names its subject via bare short-name text too. Folded into the same fix category already approved for the other two messages.

## Global Constraints

- English source: code, comments, commit messages (this project's convention — see `CLAUDE.md`).
- `CHANGELOG.md`/`CHANGELOG-de.md` get one bullet each for this change (Task 13); bump `KeineAhnungRaidTools.toc`'s `## Version:` from `2.5.0` to `2.6.0` in the same task.
- Direct commits to `main`, no feature branch — this project's established workflow.
- Re-verify every line reference below against the current file before editing — this plan was written against a specific snapshot; unrelated commits may have shifted lines since.
- Out of scope (confirmed in the design doc, do not touch): `KART.OilCache`/`KART.ILvlCache`/`KART.GearCache`/`KART.PlayerVersions` in `Core.lua` (buff-checker, same weakness, separate future ticket), `KART.DT.GetGainPercent`'s `shortName` parameter (Droptimizer's own data model is short-name-text based, imported from an external report — has no GUID concept, must not be touched), `LC_HIST_REQ`/`LC_HIST_ENTRY`/`LC_SYNC_REQUEST`/`LC_SYNC_ACCEPT`/`LC_SYNC_DECLINE` (their sender-derived name parameters are display-only text, never used as a table key or identity comparison — verified by reading every call site).

---

### Task 1: `Identity.lua` — resolver core + `KART_PlayerCache`

**Files:**
- Create: `Identity.lua`
- Modify: `KeineAhnungRaidTools.toc` (add `Identity.lua` to the file list, add `KART_PlayerCache` to `SavedVariables`)

**Interfaces:**
- Produces: `KART.Identity.ResolvePlayer(input) -> key, isPending` — every later task's identity resolution goes through this.
- Produces: `KART.Identity.ResolveDisplayName(key) -> displayName` — used wherever a stored key must be rendered without a live unit in hand.
- Produces: `KART.Identity.FindUnitForKey(key) -> unit or nil` — replaces `LC.FindUnitForShortName` (removed in Task 6, once its last two callers migrate).
- Produces: `KART.Identity.IsResolvedKey(key) -> boolean` — used by the pending-retry logic (Task 10).
- Consumes: `KART.GetNickname(unit)`, `KART.TrimString(s)` (both in `Utils.lua`, loads before this file).

- [ ] **Step 1: Create `Identity.lua`**

```lua
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
```

- [ ] **Step 2: Wire `Identity.lua` into the `.toc`**

In `KeineAhnungRaidTools.toc`, locate:

```
## SavedVariables: KART_Settings, KART_LootHistory, KART_LCOfficerNotes, KART_WoWUtilsCache, KART_Profiles
```

Replace with:

```
## SavedVariables: KART_Settings, KART_LootHistory, KART_LCOfficerNotes, KART_WoWUtilsCache, KART_Profiles, KART_PlayerCache
```

Then locate:

```
Utils.lua
MainFrame.lua
```

Replace with:

```
Utils.lua
Identity.lua
MainFrame.lua
```

- [ ] **Step 3: Register the new SavedVariable's default init**

In `Core.lua`, locate:

```lua
        KART_Settings = KART_Settings or {}
        KART_LootHistory = KART_LootHistory or {}
        KART_LCOfficerNotes = KART_LCOfficerNotes or {}
        KART_WoWUtilsCache = KART_WoWUtilsCache or {}
        KART_Profiles = KART_Profiles or {}
```

Replace with:

```lua
        KART_Settings = KART_Settings or {}
        KART_LootHistory = KART_LootHistory or {}
        KART_LCOfficerNotes = KART_LCOfficerNotes or {}
        KART_WoWUtilsCache = KART_WoWUtilsCache or {}
        KART_Profiles = KART_Profiles or {}
        KART_PlayerCache = KART_PlayerCache or {}
```

- [ ] **Step 4: Manual verification**

Log in with the addon loaded (no Lua error on load — `/console scriptErrors 1` beforehand to be sure any error surfaces). Run `/dump KART.Identity.ResolvePlayer("player")` — expect a `"Player-..."`-shaped string as the first return, `false` as the second. Run `/dump KART.Identity.ResolvePlayer("nobody-online-right-now")` — expect the same trimmed/lowercased text back, `true` as the second return. Run `/dump KART_PlayerCache` — expect a table with one entry (yourself) after the first call.

- [ ] **Step 5: Commit**

```bash
git add Identity.lua KeineAhnungRaidTools.toc Core.lua
git commit -m "feat: add GUID-based player identity resolver and its persistent cache"
```

---

### Task 2: `Core.lua` — resolve sender identity for the six identity-bearing `LC_*` messages

**Files:**
- Modify: `Core.lua:384-395` (the `LC_VOTE`/`LC_ROLL`/`LC_CVOTE`/`LC_ONOTE`/`LC_RESULT`/`LC_CONFIG` dispatch arms)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer(input) -> key, isPending` (Task 1).

**Root cause:** `Core.lua:298` computes `local shortName = sender:match("([^%-]+)")` once, shared by every dispatch arm. Six of the ten `LC_*` arms pass this `shortName` into a handler that uses it as a table key or an authority-check identity comparison (`LC.votes[rollID][senderShort]`, `LC.CouncilNamesTable[senderShort]` via `IsSenderCouncil`/`HandleConfig`'s leader check) — these six need the resolved key instead. The other four (`LC_HIST_REQ`, `LC_SYNC_REQUEST`, `LC_SYNC_ACCEPT`, `LC_SYNC_DECLINE`) only ever print or display the name — verified by reading `LC.HandleHistoryRequest`/`LC.HandleSyncRequest`/`LC.HandleSyncAccept`/`LC.HandleSyncDecline`, none of which compare it against any table — so they're intentionally left unchanged. The `shortName` local itself, and the buff-checker branches (`OIL:`, `ILVL:`, `GEAR:`, `VERSION:`/`ANNOUNCE_VERSION:`) that also read it, are untouched (out of scope, see Global Constraints).

- [ ] **Step 1: Switch the six identity-bearing dispatch arms**

In `Core.lua`, locate this exact block:

```lua
                elseif msg:sub(1, 8) == "LC_VOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), shortName) end
                elseif msg:sub(1, 8) == "LC_ROLL:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleRoll(msg:sub(9), shortName) end
                elseif msg:sub(1, 9) == "LC_CVOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleCouncilVote(msg:sub(10), shortName) end
                elseif msg:sub(1, 9) == "LC_ONOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleOfficerNote(msg:sub(10), shortName) end
                elseif msg:sub(1, 10) == "LC_RESULT:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleResult(msg:sub(11), shortName) end
                elseif msg:sub(1, 10) == "LC_CONFIG:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleConfig(msg:sub(11), shortName) end
```

Replace with:

```lua
                elseif msg:sub(1, 8) == "LC_VOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 8) == "LC_ROLL:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleRoll(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 9) == "LC_CVOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleCouncilVote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 9) == "LC_ONOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleOfficerNote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 10) == "LC_RESULT:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleResult(msg:sub(11), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 10) == "LC_CONFIG:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleConfig(msg:sub(11), (KART.Identity.ResolvePlayer(sender))) end
```

(The extra parens around `KART.Identity.ResolvePlayer(sender)` truncate its second return value — these call sites only want the key, not the `isPending` flag, which matters here since `sender` is always a live raid/party member currently transmitting, so resolution always succeeds in practice.)

- [ ] **Step 2: Manual verification (needs two clients)**

With two KART clients in the same group, have Client B cast a vote or roll on a test item; on Client A run `/dump KART.LC.votes` (or watch the council panel populate) — the vote should land under a `"Player-..."`-shaped key, not a short name. No Lua error on either client.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "feat: resolve sender identity to a GUID-based key for loot-council wire messages"
```

---

### Task 3: Council/authority checks — `IsCouncil`, `IsSenderCouncil`, `LC.IsMe`, `LC.HandleConfig`'s leader check

**Files:**
- Modify: `LootCouncil.lua:144-169` (`IsCouncil`, `IsSenderCouncil`)
- Modify: `LootCouncil.lua:213-218` (`LC.IsMe`)
- Modify: `LootCouncil.lua:265-267` (`LC.HandleConfig`'s leader-authority check only — the config-parsing body is Task 4)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.FindUnitForKey` (Task 1).
- Produces: `IsCouncil()`, `IsSenderCouncil(senderKey)`, `LC.IsMe(configuredKey)` — same names/arities as today, callers elsewhere are unaffected by this task (their argument already carries the right kind of value once Tasks 2/4 land).

**Root cause:** `IsCouncil`/`IsSenderCouncil`/`LC.IsMe` all compare a short-name string against `LC.CouncilNamesTable`/a configured-name string — the exact collision-prone comparison this whole plan removes. `IsSenderCouncil` and `LC.HandleConfig`'s leader check both call `LC.FindUnitForShortName(senderShort)` to get a live unit for a `UnitIsGroupLeader`/`UnitClass` check; now that `senderShort` is already a resolved key (Task 2), the unit lookup must go by key (`KART.Identity.FindUnitForKey`), not by name. `LC.FindUnitForShortName` itself keeps existing for one more task (its other two callers, `DoAssignWinner` and `HandleResult`, migrate in Task 6, which then deletes it).

- [ ] **Step 1: `IsCouncil` and `IsSenderCouncil`**

In `LootCouncil.lua`, locate:

```lua
local function IsCouncil()
    if UnitIsGroupLeader("player") then return true end
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or ""):lower()
    if LC.CouncilNamesTable[myShort] == true then return true end
    -- Also match by Northern Sky Raid Tools nickname (see KART.GetNickname), so the council list
    -- can name a *person* once instead of every one of their alts individually.
    local nick = KART.GetNickname("player")
    return nick ~= nil and LC.CouncilNamesTable[nick] == true
end

-- Whether senderShort (as received off CHAT_MSG_ADDON, see Core.lua) currently holds council
-- status — used to validate the sender of messages that grant real authority (LC_RESULT logs a
-- permanent history entry and fires the "you win" popup; LC_ONOTE overwrites a persistent officer
-- note) before acting on them. Resolving against the live raid/party roster first, rather than
-- trusting the name string alone, matters because CHAT_MSG_ADDON also delivers whispers: a name
-- that isn't currently in our group is never authorized, even if it happens to match an entry in
-- CouncilNamesTable.
local function IsSenderCouncil(senderShort)
    local unit = senderShort and LC.FindUnitForShortName(senderShort)
    if not unit then return false end
    if UnitIsGroupLeader(unit) then return true end
    if LC.CouncilNamesTable[senderShort:lower()] == true then return true end
    -- Also match by Northern Sky Raid Tools nickname, same reasoning as IsCouncil above.
    local nick = KART.GetNickname(unit)
    return nick ~= nil and LC.CouncilNamesTable[nick] == true
end
```

Replace with:

```lua
local function IsCouncil()
    if UnitIsGroupLeader("player") then return true end
    local myKey = (KART.Identity.ResolvePlayer("player"))
    return LC.CouncilNamesTable[myKey] == true
end

-- Whether senderKey (already resolved off CHAT_MSG_ADDON's sender, see Core.lua) currently holds
-- council status — used to validate the sender of messages that grant real authority (LC_RESULT
-- logs a permanent history entry and fires the "you win" popup; LC_ONOTE overwrites a persistent
-- officer note) before acting on them. Resolving to a live unit first, rather than trusting the
-- key alone, matters because CHAT_MSG_ADDON also delivers whispers: someone not currently in our
-- group is never authorized, even if their key happens to match an entry in CouncilNamesTable.
local function IsSenderCouncil(senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    if not unit then return false end
    if UnitIsGroupLeader(unit) then return true end
    return LC.CouncilNamesTable[senderKey] == true
end
```

(`IsCouncil`'s nickname-matching comment no longer applies here as written — nickname matching still happens, just one layer down inside `ResolvePlayer`/`LC.CouncilNamesTable`'s own resolution in Task 4, not as a second explicit check in this function.)

- [ ] **Step 2: `LC.IsMe`**

Locate:

```lua
function LC.IsMe(configuredName)
    if not configuredName or configuredName == "" then return false end
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or ""):lower()
    if myShort == configuredName then return true end
    return KART.GetNickname("player") == configuredName
end
```

Replace with:

```lua
function LC.IsMe(configuredKey)
    if not configuredKey or configuredKey == "" then return false end
    return (KART.Identity.ResolvePlayer("player")) == configuredKey
end
```

- [ ] **Step 3: `LC.HandleConfig`'s leader-authority check**

Locate:

```lua
function LC.HandleConfig(payload, senderShort)
    local unit = senderShort and LC.FindUnitForShortName(senderShort)
    if not unit or not UnitIsGroupLeader(unit) then return end
```

Replace with:

```lua
function LC.HandleConfig(payload, senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    if not unit or not UnitIsGroupLeader(unit) then return end
```

- [ ] **Step 4: Manual verification**

Solo, run `/dump KART.LC` (module loaded, no error). With two clients in a group where Client B is on the council list (by short name) and Client A is not the leader: Client B casts a council vote or assigns a winner; Client A's `IsSenderCouncil` path should accept it (the assign/vote takes effect) exactly as before this change. No behavior difference for a normal (non-colliding) roster.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "refactor: resolve council/lootmaster identity checks through GUID-based keys"
```

---

### Task 4: `LC.CouncilNamesTable` / `LC.raidConfig.lootmaster` / `LC.GetLootmaster` — resolve config text to keys

**Files:**
- Modify: `LootCouncil.lua:190-205` (`LC.GetLootmaster`)
- Modify: `LootCouncil.lua:272-286` (`LC.HandleConfig`'s config-parsing body)

**Interfaces:**
- Produces: `LC.ResolveConfigName(text) -> key or nil` (new local function) — resolves free-typed config text (trimmed) to a key; used here and reused by Task 10's pending-retry.
- Consumes: `KART.Identity.ResolvePlayer` (Task 1).

**Root cause:** `LC.CouncilNamesTable`/`LC.raidConfig.lootmaster` are built from `KART_Settings.lcCouncilMembers`/`lcLootmaster` free text by stripping any `-Realm` suffix and lowercasing — the same collision-prone comparison. `LC.GetLootmaster`'s raid-leader branch reads `KART_Settings.lcLootmaster` directly (never goes through `HandleConfig`, since a client never receives its own broadcast) and must resolve the same way, on every read, so `LC.IsMe` (Task 3) gets a key regardless of whether the caller is the leader or not.

- [ ] **Step 1: Add the shared `LC.ResolveConfigName` helper**

In `LootCouncil.lua`, locate (this is `LC.GetLootmaster`, immediately before the change in Step 2):

```lua
function LC.GetLootmaster()
    if UnitIsGroupLeader("player") then
        local short = KART.TrimString(KART_Settings.lcLootmaster or ""):match("([^%-]+)") or ""
        return short:lower()
    end
    return (LC.raidConfig and LC.raidConfig.lootmaster) or ""
end
```

Replace with:

```lua
-- Resolves free-typed config text (a council-list entry, or the lootmaster field) to a stable
-- key via KART.Identity.ResolvePlayer, trimming first. Returns nil for blank text. Shared by
-- LC.HandleConfig (a received LC_CONFIG broadcast) and LC.GetLootmaster's raid-leader branch
-- below (the leader's own local settings, resolved fresh on every read rather than cached,
-- since the leader never receives its own broadcast to trigger HandleConfig).
function LC.ResolveConfigName(text)
    local trimmed = KART.TrimString(text or "")
    if trimmed == "" then return nil end
    return (KART.Identity.ResolvePlayer(trimmed))
end

function LC.GetLootmaster()
    if UnitIsGroupLeader("player") then
        return LC.ResolveConfigName(KART_Settings.lcLootmaster) or ""
    end
    return (LC.raidConfig and LC.raidConfig.lootmaster) or ""
end
```

- [ ] **Step 2: `LC.HandleConfig`'s config-parsing body**

Locate:

```lua
    LC.raidConfig.minQuality    = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels  = buttons
    LC.raidConfig.rollsEnabled  = (rolls == "1")
    LC.raidConfig.lootmaster    = (lootmaster or ""):lower()
    LC.raidConfig.councilMembers = council or ""

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString((council or ""):lower(), ";")) do
        -- Strip any "-Realm" suffix, same as the lootmaster field above — a self-check like
        -- IsCouncil() compares against UnitName("player"), which never carries a realm suffix for
        -- the local player, so a council-list entry typed as "Name-Realm" (e.g. copied from a
        -- raid frame showing a cross-realm member that way) would otherwise never match.
        local trimmed = KART.TrimString(name):match("([^%-]+)") or ""
        if trimmed ~= "" then LC.CouncilNamesTable[trimmed] = true end
    end
end
```

Replace with:

```lua
    LC.raidConfig.minQuality    = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels  = buttons
    LC.raidConfig.rollsEnabled  = (rolls == "1")
    LC.raidConfig.lootmaster    = LC.ResolveConfigName(lootmaster) or ""
    LC.raidConfig.councilMembers = council or ""

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString(council or "", ";")) do
        local key = LC.ResolveConfigName(name)
        if key then LC.CouncilNamesTable[key] = true end
    end
end
```

(`KART.SplitString` no longer needs the `:lower()` pre-pass — `LC.ResolveConfigName`/`KART.Identity.ResolvePlayer` already lowercase internally before matching or falling back to pending text.)

- [ ] **Step 3: Manual verification**

As raid leader, type a valid council member's short name into the council-list field — that member's `IsCouncil()` should return true on their own client after the next `LC_CONFIG` broadcast (settings change or `/reload`). Type a name for someone not currently online — no Lua error, and `LC.CouncilNamesTable` gets an entry keyed by the plain lowercased text (check via `/dump KART.LC.CouncilNamesTable`) rather than crashing or being silently dropped.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: resolve council list and lootmaster config text to GUID-based keys"
```

---

### Task 5: Vote/roll casting and receipt — `LC.OnStartLootRoll`, both vote-cast blocks, `LC.HandleVote`/`LC.HandleRoll`

**Files:**
- Modify: `LootCouncil.lua:656-661` (opt-in roll cast in `LC.OnStartLootRoll`)
- Modify: `LootCouncil.lua:1110-1112` and `LootCouncil.lua:1373-1375` (the two vote-cast blocks — compact and normal vote-popup layouts)
- Modify: `LootCouncil.lua:3290-3325` (`LC.HandleVote`, `LC.HandleRoll`)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer` (Task 1).

**Root cause:** `LC.votes[rollID][myShort]`/`LC.rolls[rollID][myShort]` are written using a short-name string computed from `UnitName("player")` at the moment of casting; every receipt handler stores under the sender-derived short name too. Both key schemes need to become the resolved key. The two near-identical vote-cast blocks are the compact and normal vote-popup layouts (`KART_Settings.lcVoteLayoutCompact`) — both cast the same way and both need the same change.

- [ ] **Step 1: Roll cast in `LC.OnStartLootRoll`**

Locate:

```lua
    if LC.GetRollsEnabled() then
        local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
        local myRoll  = math.random(1, 100)
        LC.rolls[rollID] = LC.rolls[rollID] or {}
        LC.rolls[rollID][myShort] = myRoll
        SendLC("LC_ROLL:" .. rollID .. ":" .. myRoll)
    end
```

Replace with:

```lua
    if LC.GetRollsEnabled() then
        local myKey  = (KART.Identity.ResolvePlayer("player"))
        local myRoll = math.random(1, 100)
        LC.rolls[rollID] = LC.rolls[rollID] or {}
        LC.rolls[rollID][myKey] = myRoll
        SendLC("LC_ROLL:" .. rollID .. ":" .. myRoll)
    end
```

- [ ] **Step 2: First vote-cast block (compact layout)**

Locate:

```lua
                    if IsTestRoll(capturedRollID) then
                        -- Test rolls have no real raid to broadcast to (and testing solo may
                        -- mean no group at all), so record the vote locally and push it
                        -- straight into the Test-Master council panel if it's open, instead of
                        -- relying on a round-trip through the addon channel that would never
                        -- come back to this same client.
                        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myShort] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
                end)
            end
        end
    end

    for i = #LC.voteListRolls + 1, #f.rows do
```

Replace with:

```lua
                    if IsTestRoll(capturedRollID) then
                        -- Test rolls have no real raid to broadcast to (and testing solo may
                        -- mean no group at all), so record the vote locally and push it
                        -- straight into the Test-Master council panel if it's open, instead of
                        -- relying on a round-trip through the addon channel that would never
                        -- come back to this same client.
                        local myKey = (KART.Identity.ResolvePlayer("player"))
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myKey] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
                end)
            end
        end
    end

    for i = #LC.voteListRolls + 1, #f.rows do
```

- [ ] **Step 3: Second vote-cast block (normal layout)**

Locate:

```lua
                    if IsTestRoll(capturedRollID) then
                        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myShort] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
                end)

                -- Chip position doubles as the pencil icon's anchor point once all 5 default
                -- categories are laid out, so the note toggle sits right after the last chip.
                if bi == #buttons then
```

Replace with:

```lua
                    if IsTestRoll(capturedRollID) then
                        local myKey = (KART.Identity.ResolvePlayer("player"))
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myKey] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
                end)

                -- Chip position doubles as the pencil icon's anchor point once all 5 default
                -- categories are laid out, so the note toggle sits right after the last chip.
                if bi == #buttons then
```

- [ ] **Step 4: `LC.HandleVote`/`LC.HandleRoll` parameter naming**

Locate:

```lua
function LC.HandleVote(payload, senderShort)
    -- payload = "rollID:buttonIndex:note"
    local rollID, idx = payload:match("^(%d+):(%d+)")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end

    local note = payload:match("^%d+:%d+:(.*)") or ""

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderShort] = {idx = idx, note = note}
```

Replace with:

```lua
function LC.HandleVote(payload, senderKey)
    -- payload = "rollID:buttonIndex:note"
    local rollID, idx = payload:match("^(%d+):(%d+)")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end

    local note = payload:match("^%d+:%d+:(.*)") or ""

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderKey] = {idx = idx, note = note}
```

Then locate:

```lua
function LC.HandleRoll(payload, senderShort)
    local rollID, value = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    value  = tonumber(value)
    if not rollID or not value then return end

    LC.rolls[rollID] = LC.rolls[rollID] or {}
    LC.rolls[rollID][senderShort] = value
```

Replace with:

```lua
function LC.HandleRoll(payload, senderKey)
    local rollID, value = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    value  = tonumber(value)
    if not rollID or not value then return end

    LC.rolls[rollID] = LC.rolls[rollID] or {}
    LC.rolls[rollID][senderKey] = value
```

- [ ] **Step 5: Manual verification (needs two clients)**

Cast a vote and (if enabled) a roll on both a real drop and a Test item. `/dump KART.LC.votes[<rollID>]`/`KART.LC.rolls[<rollID>]` should show `"Player-..."`-shaped keys, not short names, for both the local cast and a received vote/roll from the other client.

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: key vote/roll casting and receipt by resolved player identity"
```

---

### Task 6: `LC_RESULT` — `LC.AnnounceResult`, `DoAssignWinner`, `LC.AssignWinner`, `LC.HandleResult`, `LC.assignedWinners`

**Files:**
- Modify: `LootCouncil.lua:2585-2591` (`LC.AnnounceResult`)
- Modify: `LootCouncil.lua:2780-2822` (`DoAssignWinner`, `LC.AssignWinner`)
- Modify: `LootCouncil.lua:3358-3389` (`LC.HandleResult`)
- Modify: `LootCouncil.lua:3183-3195` (delete `LC.FindUnitForShortName` — its last two callers migrate in this task)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.ResolveDisplayName`, `KART.Identity.FindUnitForKey` (Task 1).
- Produces: `LC.AssignWinner(rollID, playerKey, reason, colorDef)`, `DoAssignWinner(rollID, playerKey, reason, colorDef)` — same arity, `playerKey` now holds a resolved key instead of a short-name string (Task 8 updates the caller, `LC.ShowAssignMenu`, to pass a key).

**Root cause:** `LC.AnnounceResult`'s `winnerName` parameter is bare short-name text, chosen by the assigning client from its own (locally unambiguous) roster view, broadcast in the `LC_RESULT` payload for every other client to reverse-resolve via the collision-prone `LC.FindUnitForShortName` — the identical hazard this plan removes from sender identity, just relocated into the payload. The fix: capture the resolved key at the point of assignment (a live unit is already in hand there, via `LC.ShowAssignMenu`'s row — see Task 8) and send that key in the payload; resolve back to a display name only at the point of logging/notifying a human.

- [ ] **Step 1: `LC.AnnounceResult`**

Locate:

```lua
function LC.AnnounceResult(rollID, winnerName, reason)
    -- Test rolls stay entirely local: no addon-channel broadcast (which would make every real
    -- raid member's client log a fake history entry / pop a fake "you win" for whoever's short
    -- name the tester happened to click) and no raid-chat spam.
    if not IsTestRoll(rollID) then
        SendLC("LC_RESULT:" .. rollID .. ":" .. winnerName .. ":" .. (reason or ""))

        if winnerName ~= "NONE" then
            local link = LC.rollItems[rollID] or ""
            local msg  = string.format(KART.L.LC_RESULT_ANNOUNCE, winnerName, link)
```

Replace with:

```lua
function LC.AnnounceResult(rollID, winnerKey, reason)
    -- Test rolls stay entirely local: no addon-channel broadcast (which would make every real
    -- raid member's client log a fake history entry / pop a fake "you win" for whoever the
    -- tester happened to click) and no raid-chat spam.
    if not IsTestRoll(rollID) then
        SendLC("LC_RESULT:" .. rollID .. ":" .. winnerKey .. ":" .. (reason or ""))

        if winnerKey ~= "NONE" then
            local link = LC.rollItems[rollID] or ""
            local msg  = string.format(KART.L.LC_RESULT_ANNOUNCE, KART.Identity.ResolveDisplayName(winnerKey), link)
```

- [ ] **Step 2: `DoAssignWinner`/`LC.AssignWinner`**

Locate:

```lua
local function DoAssignWinner(rollID, playerShort, reason, colorDef)
    local classFile
    local unit = LC.FindUnitForShortName(playerShort)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.AnnounceResult(rollID, playerShort, reason)

    if IsTestRoll(rollID) then
        -- Test rolls never round-trip through the network (see AnnounceResult), so if the
        -- tester assigned the win to themselves, trigger the "you win" popup locally instead —
        -- and skip writing a fake entry into the real, persistent loot history.
        local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
        if playerShort == myShort then
            LC.ShowWinnerNotification(LC.rollItems[rollID])
        end
    else
        LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef, rollID)
        -- Only the client that actually holds the item (the designated lootmaster, see
        -- LC.GetLootmaster/ForceWinRoll) needs a trade reminder — when the assigner (usually the
        -- raid leader) isn't also the lootmaster, they never physically have the item to trade.
        if LC.IsMe(LC.GetLootmaster()) then
            LC.AddPendingTrade(rollID, playerShort)
        end
    end
    LC.assignedWinners[rollID] = playerShort
end

-- Awards the item to playerShort with the given reason (may be "" for no reason) and logs it.
-- colorDef is the vote-button definition the reason was taken from (nil for "no reason").
-- If this rollID was already assigned, asks for confirmation first to avoid accidental double entries.
function LC.AssignWinner(rollID, playerShort, reason, colorDef)
    local prevWinner = LC.assignedWinners[rollID]
    if prevWinner then
        local dialog = StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] ---@diagnostic disable-line: undefined-global
        dialog.text = string.format(KART.L.LC_REASSIGN_CONFIRM_TEXT, prevWinner, playerShort)
        dialog.OnAccept = function() DoAssignWinner(rollID, playerShort, reason, colorDef) end
        StaticPopup_Show("KART_LC_REASSIGN_CONFIRM") ---@diagnostic disable-line: undefined-global
    else
        DoAssignWinner(rollID, playerShort, reason, colorDef)
    end
end
```

Replace with:

```lua
local function DoAssignWinner(rollID, playerKey, reason, colorDef)
    local classFile
    local unit = KART.Identity.FindUnitForKey(playerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.AnnounceResult(rollID, playerKey, reason)

    if IsTestRoll(rollID) then
        -- Test rolls never round-trip through the network (see AnnounceResult), so if the
        -- tester assigned the win to themselves, trigger the "you win" popup locally instead —
        -- and skip writing a fake entry into the real, persistent loot history.
        local myKey = (KART.Identity.ResolvePlayer("player"))
        if playerKey == myKey then
            LC.ShowWinnerNotification(LC.rollItems[rollID])
        end
    else
        LC.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(playerKey), reason, classFile, colorDef, rollID)
        -- Only the client that actually holds the item (the designated lootmaster, see
        -- LC.GetLootmaster/ForceWinRoll) needs a trade reminder — when the assigner (usually the
        -- raid leader) isn't also the lootmaster, they never physically have the item to trade.
        if LC.IsMe(LC.GetLootmaster()) then
            LC.AddPendingTrade(rollID, playerKey)
        end
    end
    LC.assignedWinners[rollID] = playerKey
end

-- Awards the item to playerKey (a resolved player identity, see KART.Identity.ResolvePlayer) with
-- the given reason (may be "" for no reason) and logs it. colorDef is the vote-button definition
-- the reason was taken from (nil for "no reason"). If this rollID was already assigned, asks for
-- confirmation first to avoid accidental double entries.
function LC.AssignWinner(rollID, playerKey, reason, colorDef)
    local prevWinner = LC.assignedWinners[rollID]
    if prevWinner then
        local dialog = StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] ---@diagnostic disable-line: undefined-global
        dialog.text = string.format(KART.L.LC_REASSIGN_CONFIRM_TEXT, KART.Identity.ResolveDisplayName(prevWinner), KART.Identity.ResolveDisplayName(playerKey))
        dialog.OnAccept = function() DoAssignWinner(rollID, playerKey, reason, colorDef) end
        StaticPopup_Show("KART_LC_REASSIGN_CONFIRM") ---@diagnostic disable-line: undefined-global
    else
        DoAssignWinner(rollID, playerKey, reason, colorDef)
    end
end
```

- [ ] **Step 3: `LC.HandleResult`**

Locate:

```lua
function LC.HandleResult(payload, senderShort)
    if not IsSenderCouncil(senderShort) then return end
    -- payload = "rollID:winnerName:reason"
    local rollID, winner = payload:match("^(%d+):([^:]+)")
    rollID = tonumber(rollID)
    if not rollID or not winner then return end
    local reason = payload:match("^%d+:[^:]+:(.*)$") or ""

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.RemoveVoteListItem(rollID)

    if winner == "NONE" then return end

    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    if winner == myShort then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
    end

    -- Every KART user logs the same entry locally, so everyone's loot history stays in sync
    -- without depending on the lootmaster being online later. The assigner already logged this
    -- locally (SendAddonMessage never echoes back to its own sender), so no duplicate here.
    local classFile
    local unit = LC.FindUnitForShortName(winner)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason), rollID)
```

Replace with:

```lua
function LC.HandleResult(payload, senderKey)
    if not IsSenderCouncil(senderKey) then return end
    -- payload = "rollID:winnerKey:reason"
    local rollID, winnerKey = payload:match("^(%d+):([^:]+)")
    rollID = tonumber(rollID)
    if not rollID or not winnerKey then return end
    local reason = payload:match("^%d+:[^:]+:(.*)$") or ""

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.RemoveVoteListItem(rollID)

    if winnerKey == "NONE" then return end

    local myKey = (KART.Identity.ResolvePlayer("player"))
    if winnerKey == myKey then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
    end

    -- Every KART user logs the same entry locally, so everyone's loot history stays in sync
    -- without depending on the lootmaster being online later. The assigner already logged this
    -- locally (SendAddonMessage never echoes back to its own sender), so no duplicate here.
    local classFile
    local unit = KART.Identity.FindUnitForKey(winnerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(winnerKey), reason, classFile, LC.ResolveColorForReason(reason), rollID)
```

- [ ] **Step 4: Delete `LC.FindUnitForShortName`**

Locate:

```lua
-- Resolves a raid/party unit token for a given short (unrealmed) player name.
function LC.FindUnitForShortName(shortName)
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName and fullName:match("([^%-]+)") == shortName then
            return unit
        end
    end
    return nil
end

```

Replace with: (nothing — delete these lines entirely; `KART.Identity.FindUnitForKey`, added in Task 1, has now replaced every one of its four callers)

- [ ] **Step 5: Manual verification (needs two clients)**

Assign a test-roll winner to yourself — the "you win" popup should still fire. With two real clients, have the council assign a real item to Client B; Client B gets the trade reminder (if they're the lootmaster) or Client A does; both clients' loot history shows Client B's correct display name, not a raw key. Reassign the same roll to a different winner — the confirmation dialog shows both the previous and new winner's display names, not GUIDs.

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: key winner assignment and the LC_RESULT wire message by resolved identity"
```

---

### Task 7: `LC_CVOTE` — `LC.ToggleCouncilVote`, `LC.HandleCouncilVote`, `LC.SetPlayerVote`

**Files:**
- Modify: `LootCouncil.lua:3064-3091` (`LC.SetPlayerVote`, `LC.ToggleCouncilVote`)
- Modify: `LootCouncil.lua:3331-3346` (`LC.HandleCouncilVote`)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer` (Task 1).
- Produces: `LC.SetPlayerVote(rollID, playerKey, buttonIdx)`, `LC.ToggleCouncilVote(rollID, candidateKey)` — same arity, now key-based (Task 8 updates their callers).

**Root cause:** Same shape as Task 6's `LC_RESULT` fix — `LC.ToggleCouncilVote`'s `candidateShort` is bare short-name text chosen from the voting council member's own roster view, broadcast for every other client to store under `LC.councilVotes[rollID][senderShort]`. Fix: resolve to a key at the point of casting, send the key in the `LC_CVOTE` payload.

- [ ] **Step 1: `LC.SetPlayerVote`**

Locate:

```lua
function LC.SetPlayerVote(rollID, playerShort, buttonIdx)
    LC.votes[rollID] = LC.votes[rollID] or {}
    local prev = LC.votes[rollID][playerShort]
    local note = (type(prev) == "table" and prev.note) or ""
    LC.votes[rollID][playerShort] = {idx = buttonIdx, note = note}
```

Replace with:

```lua
function LC.SetPlayerVote(rollID, playerKey, buttonIdx)
    LC.votes[rollID] = LC.votes[rollID] or {}
    local prev = LC.votes[rollID][playerKey]
    local note = (type(prev) == "table" and prev.note) or ""
    LC.votes[rollID][playerKey] = {idx = buttonIdx, note = note}
```

- [ ] **Step 2: `LC.ToggleCouncilVote`**

Locate:

```lua
function LC.ToggleCouncilVote(rollID, candidateShort)
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    local retracting = (LC.councilVotes[rollID][myShort] == candidateShort)
    LC.councilVotes[rollID][myShort] = (not retracting) and candidateShort or nil

    if not IsTestRoll(rollID) then
        SendLC("LC_CVOTE:" .. rollID .. ":" .. (retracting and "" or candidateShort))
    end

    LC.RefreshCouncilRows()
end
```

Replace with:

```lua
function LC.ToggleCouncilVote(rollID, candidateKey)
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    local retracting = (LC.councilVotes[rollID][myKey] == candidateKey)
    LC.councilVotes[rollID][myKey] = (not retracting) and candidateKey or nil

    if not IsTestRoll(rollID) then
        SendLC("LC_CVOTE:" .. rollID .. ":" .. (retracting and "" or candidateKey))
    end

    LC.RefreshCouncilRows()
end
```

- [ ] **Step 3: `LC.HandleCouncilVote`**

Locate:

```lua
function LC.HandleCouncilVote(payload, senderShort)
    local rollID, candidate = payload:match("^(%d+):(.*)$")
    rollID = tonumber(rollID)
    if not rollID then return end

    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    if candidate == "" then
        LC.councilVotes[rollID][senderShort] = nil -- retracted their pick
    else
        LC.councilVotes[rollID][senderShort] = candidate
    end
```

Replace with:

```lua
function LC.HandleCouncilVote(payload, senderKey)
    local rollID, candidateKey = payload:match("^(%d+):(.*)$")
    rollID = tonumber(rollID)
    if not rollID then return end

    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    if candidateKey == "" then
        LC.councilVotes[rollID][senderKey] = nil -- retracted their pick
    else
        LC.councilVotes[rollID][senderKey] = candidateKey
    end
```

- [ ] **Step 4: Manual verification (needs two clients)**

Two council members pick candidates for the same test/real item; `/dump KART.LC.councilVotes[<rollID>]` shows key→key entries on both clients. Retracting a pick (click the same candidate again) clears the entry as before.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: key council straw-poll voting and the LC_CVOTE wire message by resolved identity"
```

---

### Task 8: `LC.RefreshCouncilRows` — thread resolved keys through row-building, `LC.ShowAssignMenu`

**Files:**
- Modify: `LootCouncil.lua:2087-2157` (`members` table construction in `LC.RefreshCouncilRows`)
- Modify: `LootCouncil.lua:2301-2323` (captured row variables)
- Modify: `LootCouncil.lua:2449-2472` (council-vote-button tally + click handler)
- Modify: `LootCouncil.lua:2509-2520` (row click handler + `OnLeave` winner-highlight check)
- Modify: `LootCouncil.lua:3202-3226` (`LC.ShowAssignMenu`)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.ResolveDisplayName` (Task 1); `LC.SetPlayerVote(rollID, playerKey, buttonIdx)` (Task 7); `LC.AssignWinner(rollID, playerKey, reason, colorDef)` (Task 6); `LC.ShowOfficerNoteDialog` (updated in Task 9 to take a key — this task passes what Task 9 expects).
- Produces: `LC.ShowAssignMenu(anchor, rollID, playerKey, playerDisplayName, voteDef)` — signature gains a display-name parameter, since the menu title needs a human-readable name while every action inside now needs the key.

**Root cause:** Every per-row lookup into `LC.votes`/`LC.rolls`/`LC.councilVotes`/`LC.assignedWinners`/`KART_LCOfficerNotes` currently keys by `m.short` (the row's display short name) — all of those tables are now keyed by resolved identity (Tasks 4-7, 9), so row-building needs its own resolved key per member, kept alongside (not instead of) the existing display fields (`short`, `unit`, `nickname`), which stay unchanged for rendering.

- [ ] **Step 1: Add `key` to each member entry**

Locate:

```lua
    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short    = fullName:match("([^%-]+)")
            local voteData = votes[short]
            -- Support both legacy number and new {idx, note} table
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit(unit, rollItem)

            -- Flag raiders who are missing KART, running an outdated version, or have disabled
            -- their own Loot Council module locally (self excluded — we never receive our own
            -- version broadcast, so PlayerVersions never has an entry for "player").
            local kartStatus
            if unit ~= "player" then
                local ver = KART.PlayerVersions and KART.PlayerVersions[short]
                local lcEnabled = KART.PlayerLCEnabled and KART.PlayerLCEnabled[short]
                if not ver then
                    kartStatus = KART.L.LC_STATUS_NO_KART
                elseif ver ~= KART.Version then
                    kartStatus = string.format(KART.L.LC_STATUS_OLD_VERSION, ver)
                elseif lcEnabled == false then
                    kartStatus = KART.L.LC_STATUS_MODULE_DISABLED
                end
            end

            table.insert(members, {
                short = short, unit = unit,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = kartStatus,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][short],
                -- Nickname (see KART.GetNickname/lcShowNickNames) and guild rank are both purely
                -- display concerns, resolved once per refresh here rather than per-row-render.
                -- Second return value is the nickname in its original casing — the first
                -- (lowercased) is only for matching, never what should show up on screen.
                nickname = select(2, KART.GetNickname(unit)),
                guildRank = select(2, GetGuildInfo(unit)),
            })
        end
    end
```

Replace with:

```lua
    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short    = fullName:match("([^%-]+)")
            local key      = (KART.Identity.ResolvePlayer(unit))
            local voteData = votes[key]
            -- Support both legacy number and new {idx, note} table
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit(unit, rollItem)

            -- Flag raiders who are missing KART, running an outdated version, or have disabled
            -- their own Loot Council module locally (self excluded — we never receive our own
            -- version broadcast, so PlayerVersions never has an entry for "player"). PlayerVersions
            -- stays short-name keyed — out of scope for the identity rework, see the design doc.
            local kartStatus
            if unit ~= "player" then
                local ver = KART.PlayerVersions and KART.PlayerVersions[short]
                local lcEnabled = KART.PlayerLCEnabled and KART.PlayerLCEnabled[short]
                if not ver then
                    kartStatus = KART.L.LC_STATUS_NO_KART
                elseif ver ~= KART.Version then
                    kartStatus = string.format(KART.L.LC_STATUS_OLD_VERSION, ver)
                elseif lcEnabled == false then
                    kartStatus = KART.L.LC_STATUS_MODULE_DISABLED
                end
            end

            table.insert(members, {
                short = short, unit = unit, key = key,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = kartStatus,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][key],
                -- Nickname (see KART.GetNickname/lcShowNickNames) and guild rank are both purely
                -- display concerns, resolved once per refresh here rather than per-row-render.
                -- Second return value is the nickname in its original casing — the first
                -- (lowercased) is only for matching, never what should show up on screen.
                nickname = select(2, KART.GetNickname(unit)),
                guildRank = select(2, GetGuildInfo(unit)),
            })
        end
    end
```

- [ ] **Step 2: Test-roll self-row fallback**

Locate:

```lua
    if IsTestRoll(rollID) then
        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
        local alreadyListed = false
        for _, m in ipairs(members) do
            if m.short == myShort then alreadyListed = true break end
        end
        if not alreadyListed and myShort ~= "" then
            local voteData = votes[myShort]
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit("player", rollItem)
            table.insert(members, {
                short = myShort, unit = "player",
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = nil,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][myShort],
                nickname = select(2, KART.GetNickname("player")),
                guildRank = select(2, GetGuildInfo("player")),
            })
        end
    end
```

Replace with:

```lua
    if IsTestRoll(rollID) then
        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
        local myKey    = (KART.Identity.ResolvePlayer("player"))
        local alreadyListed = false
        for _, m in ipairs(members) do
            if m.short == myShort then alreadyListed = true break end
        end
        if not alreadyListed and myShort ~= "" then
            local voteData = votes[myKey]
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit("player", rollItem)
            table.insert(members, {
                short = myShort, unit = "player", key = myKey,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = nil,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][myKey],
                nickname = select(2, KART.GetNickname("player")),
                guildRank = select(2, GetGuildInfo("player")),
            })
        end
    end
```

- [ ] **Step 3: Captured row variables**

Locate:

```lua
        local rowIdx              = i
        -- Scoped per-roll (not a single global "last winner") — otherwise assigning item A to a
        -- player and then switching to item B's tab would keep that player highlighted green
        -- there too, even though they never won item B.
        local isWinner            = (rollID ~= nil and m.short == LC.assignedWinners[rollID])
        local capturedShort       = m.short
        local capturedRoll        = rollID
        local capturedNote        = m.voteNote or ""
        local capturedEquipLink   = m.equippedLink
        local capturedEquipIlvl   = m.equippedIlvl
        local capturedVoteDef     = m.voteDef
        local capturedKartStatus  = m.kartStatus
        local capturedOfficerNote = m.short and KART_LCOfficerNotes[m.short]
        local capturedGainPct, capturedGainSource
        if KART.DT and KART.DT.GetGainPercent and m.short then
            capturedGainPct, capturedGainSource = KART.DT.GetGainPercent(m.short, rollItem)
        end

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * 26)
        row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
        row.memberShort = m.short
```

Replace with:

```lua
        local rowIdx              = i
        -- Scoped per-roll (not a single global "last winner") — otherwise assigning item A to a
        -- player and then switching to item B's tab would keep that player highlighted green
        -- there too, even though they never won item B.
        local isWinner            = (rollID ~= nil and m.key == LC.assignedWinners[rollID])
        local capturedShort       = m.short
        local capturedKey         = m.key
        local capturedRoll        = rollID
        local capturedNote        = m.voteNote or ""
        local capturedEquipLink   = m.equippedLink
        local capturedEquipIlvl   = m.equippedIlvl
        local capturedVoteDef     = m.voteDef
        local capturedKartStatus  = m.kartStatus
        local capturedOfficerNote = m.key and KART_LCOfficerNotes[m.key]
        local capturedGainPct, capturedGainSource
        if KART.DT and KART.DT.GetGainPercent and m.short then
            -- Droptimizer's own cache is short-name-text keyed (imported from an external report,
            -- no GUID concept) — deliberately still m.short here, not m.key. See design doc.
            capturedGainPct, capturedGainSource = KART.DT.GetGainPercent(m.short, rollItem)
        end

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * 26)
        row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
        row.memberShort = m.short
        row.memberKey = m.key
```

- [ ] **Step 4: Council-vote-button tally + click handler**

Locate:

```lua
        -- Council straw-poll button: tally of how many council members (including possibly
        -- yourself) picked this candidate, and a toggle for your own pick.
        local myShort     = (UnitName("player") or ""):match("([^%-]+)") or ""
        local pollVotes    = (capturedRoll and LC.councilVotes[capturedRoll]) or {}
        local myPick       = pollVotes[myShort]
        local votedByMe    = (myPick == capturedShort)
        local pollCount    = 0
        for _, pick in pairs(pollVotes) do
            if pick == capturedShort then pollCount = pollCount + 1 end
        end
```

Replace with:

```lua
        -- Council straw-poll button: tally of how many council members (including possibly
        -- yourself) picked this candidate, and a toggle for your own pick.
        local myKey        = (KART.Identity.ResolvePlayer("player"))
        local pollVotes    = (capturedRoll and LC.councilVotes[capturedRoll]) or {}
        local myPick       = pollVotes[myKey]
        local votedByMe    = (myPick == capturedKey)
        local pollCount    = 0
        for _, pick in pairs(pollVotes) do
            if pick == capturedKey then pollCount = pollCount + 1 end
        end
```

Then locate:

```lua
        row.councilVoteBtn:SetScript("OnClick", function()
            if not capturedRoll or not capturedShort then return end
            LC.ToggleCouncilVote(capturedRoll, capturedShort)
        end)
```

Replace with:

```lua
        row.councilVoteBtn:SetScript("OnClick", function()
            if not capturedRoll or not capturedKey then return end
            LC.ToggleCouncilVote(capturedRoll, capturedKey)
        end)
```

- [ ] **Step 5: Row click handler (assign menu) + `OnLeave` winner-highlight check**

Locate:

```lua
        -- Left-click has no function. Right-click opens the assign menu.
        -- The panel never closes on its own here — only the X / Close button does.
        row:SetScript("OnClick", function(self)
            if not capturedRoll or not capturedShort then return end
            LC.ShowAssignMenu(self, capturedRoll, capturedShort, capturedVoteDef)
        end)
        -- Hover highlight only — no tooltip on the row itself. All tooltip content lives on
        -- the equip-icon hitbox below, so something is only shown while hovering that icon.
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.3, 0.15, 0.9)
            self:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
        end)
        row:SetScript("OnLeave", function(self)
            if self.memberShort == LC.assignedWinners[capturedRoll] then
                self:SetBackdropColor(0.28, 0.21, 0.03, 0.85)
                self:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            else
                self:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end)
```

Replace with:

```lua
        -- Left-click has no function. Right-click opens the assign menu.
        -- The panel never closes on its own here — only the X / Close button does.
        row:SetScript("OnClick", function(self)
            if not capturedRoll or not capturedKey then return end
            LC.ShowAssignMenu(self, capturedRoll, capturedKey, capturedShort, capturedVoteDef)
        end)
        -- Hover highlight only — no tooltip on the row itself. All tooltip content lives on
        -- the equip-icon hitbox below, so something is only shown while hovering that icon.
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.3, 0.15, 0.9)
            self:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
        end)
        row:SetScript("OnLeave", function(self)
            if self.memberKey == LC.assignedWinners[capturedRoll] then
                self:SetBackdropColor(0.28, 0.21, 0.03, 0.85)
                self:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            else
                self:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end)
```

- [ ] **Step 6: `LC.ShowAssignMenu`**

Locate:

```lua
function LC.ShowAssignMenu(anchor, rollID, playerShort, voteDef)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(playerShort)

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN, function()
            LC.AssignWinner(rollID, playerShort, voteDef and voteDef.label or "", voteDef)
        end)

        -- No callback here on purpose: this makes CreateButton return a submenu descriptor.
        local changeMenu = rootDescription:CreateButton(KART.L.LC_MENU_CHANGE_VOTE) ---@diagnostic disable-line: missing-parameter
        for i, def in ipairs(LC.GetButtonConfig()) do
            changeMenu:CreateButton(def.label, function()
                LC.SetPlayerVote(rollID, playerShort, i)
            end)
        end

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN_NO_REASON, function()
            LC.AssignWinner(rollID, playerShort, "", nil)
        end)

        rootDescription:CreateButton(KART.L.LC_MENU_EDIT_NOTE, function()
            LC.ShowOfficerNoteDialog(playerShort)
        end)
    end)
end
```

Replace with:

```lua
function LC.ShowAssignMenu(anchor, rollID, playerKey, playerDisplayName, voteDef)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(playerDisplayName)

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN, function()
            LC.AssignWinner(rollID, playerKey, voteDef and voteDef.label or "", voteDef)
        end)

        -- No callback here on purpose: this makes CreateButton return a submenu descriptor.
        local changeMenu = rootDescription:CreateButton(KART.L.LC_MENU_CHANGE_VOTE) ---@diagnostic disable-line: missing-parameter
        for i, def in ipairs(LC.GetButtonConfig()) do
            changeMenu:CreateButton(def.label, function()
                LC.SetPlayerVote(rollID, playerKey, i)
            end)
        end

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN_NO_REASON, function()
            LC.AssignWinner(rollID, playerKey, "", nil)
        end)

        rootDescription:CreateButton(KART.L.LC_MENU_EDIT_NOTE, function()
            LC.ShowOfficerNoteDialog(playerKey, playerDisplayName)
        end)
    end)
end
```

- [ ] **Step 7: Manual verification**

Open the council panel for a test roll; every row still shows the correct name/class icon/nickname/gear/gain% (all unchanged, display-only fields). Right-click a row: the assign menu title still shows the player's name, and Assign/Change Vote/Assign-No-Reason/Edit Note all still work exactly as before. The gold winner highlight persists correctly after switching tabs and back.

- [ ] **Step 8: Commit**

```bash
git add LootCouncil.lua
git commit -m "refactor: thread resolved player keys through council-row building and the assign menu"
```

---

### Task 9: `LC_ONOTE` — `LC.SetOfficerNote`, `LC.HandleOfficerNote`, `LC.ShowOfficerNoteDialog`

**Files:**
- Modify: `LootCouncil.lua:3102-3117` (`LC.SetOfficerNote`, `LC.HandleOfficerNote`)
- Modify: `LootCouncil.lua:~3160-3181` (`LC.ShowOfficerNoteDialog` — re-check the exact range against the current file; it's the function whose body was partially shown around line 3174 in earlier reads)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.IsResolvedKey` (Task 1).
- Produces: `LC.SetOfficerNote(playerKey, noteText)`, `LC.ShowOfficerNoteDialog(playerKey, playerDisplayName)`, `LC.MigrateOfficerNoteKey(oldKey) -> migrated (boolean)` (new helper, reused by Task 10's retry pass).

**Root cause:** `KART_LCOfficerNotes` is a third persisted, short-name-keyed table, and `LC_ONOTE`'s payload names its subject the same way `LC_RESULT`/`LC_CVOTE` did — bare short-name text chosen by the note-writer's own roster view, requiring the receiver to reverse-resolve it. Unlike `LC.votes`/`LC.rolls`, this table is **persisted** across sessions, so existing entries need a migration path rather than just a forward-only key-scheme switch — `LC.MigrateOfficerNoteKey` re-resolves one legacy entry when possible, leaving it untouched (never deleted) when it can't yet.

- [ ] **Step 1: `LC.SetOfficerNote`/`LC.HandleOfficerNote`**

In `LootCouncil.lua`, locate:

```lua
function LC.SetOfficerNote(shortName, noteText)
    noteText = KART.TrimString(noteText or "")
    KART_LCOfficerNotes[shortName] = (noteText ~= "") and noteText or nil
    SendLC("LC_ONOTE:" .. shortName .. ":" .. noteText)
    LC.RefreshCouncilRows()
end

function LC.HandleOfficerNote(payload, senderShort)
    if not IsSenderCouncil(senderShort) then return end
    local shortName, noteText = payload:match("^([^:]+):(.*)$")
    if not shortName then return end
    KART_LCOfficerNotes[shortName] = (noteText ~= "") and noteText or nil

    if LC.councilPanel and LC.councilPanel:IsShown() then
        LC.RefreshCouncilRows()
    end
```

Replace with:

```lua
function LC.SetOfficerNote(playerKey, noteText)
    noteText = KART.TrimString(noteText or "")
    KART_LCOfficerNotes[playerKey] = (noteText ~= "") and noteText or nil
    SendLC("LC_ONOTE:" .. playerKey .. ":" .. noteText)
    LC.RefreshCouncilRows()
end

function LC.HandleOfficerNote(payload, senderKey)
    if not IsSenderCouncil(senderKey) then return end
    local subjectKey, noteText = payload:match("^([^:]+):(.*)$")
    if not subjectKey then return end
    KART_LCOfficerNotes[subjectKey] = (noteText ~= "") and noteText or nil

    if LC.councilPanel and LC.councilPanel:IsShown() then
        LC.RefreshCouncilRows()
    end
```

- [ ] **Step 2: `LC.ShowOfficerNoteDialog`**

Locate:

```lua
function LC.ShowOfficerNoteDialog(shortName)
```

Replace with:

```lua
function LC.ShowOfficerNoteDialog(playerKey, playerDisplayName)
```

Locate:

```lua
        local function accept()
            if f.short then LC.SetOfficerNote(f.short, f.editBox:GetText()) end
            f:Hide()
        end
```

Replace with:

```lua
        local function accept()
            if f.key then LC.SetOfficerNote(f.key, f.editBox:GetText()) end
            f:Hide()
        end
```

Locate:

```lua
    local f = LC.officerNoteDialog
    f.short = shortName
    f.title:SetText(string.format(KART.L.LC_OFFICER_NOTE_PROMPT, shortName))
    f.editBox:SetText(KART_LCOfficerNotes[shortName] or "")
```

Replace with:

```lua
    local f = LC.officerNoteDialog
    f.key = playerKey
    f.title:SetText(string.format(KART.L.LC_OFFICER_NOTE_PROMPT, playerDisplayName))
    f.editBox:SetText(KART_LCOfficerNotes[playerKey] or "")
```

- [ ] **Step 3: One-time migration helper for legacy `KART_LCOfficerNotes` entries**

Immediately after `LC.HandleOfficerNote` (from Step 1), add:

```lua
-- Re-resolves one legacy (short-name-text-keyed) KART_LCOfficerNotes entry to a GUID-based key,
-- if the named player can currently be resolved (live in the group, or previously cached — see
-- KART.Identity.ResolvePlayer). Returns true if it migrated the entry, false if it's still
-- unresolvable (left untouched, never deleted, so no note is ever silently lost — retried again
-- next time this runs, see the GROUP_ROSTER_UPDATE hook that calls this).
function LC.MigrateOfficerNoteKey(oldKey)
    if KART.Identity.IsResolvedKey(oldKey) then return false end -- already migrated
    local newKey, isPending = KART.Identity.ResolvePlayer(oldKey)
    if isPending then return false end
    KART_LCOfficerNotes[newKey] = KART_LCOfficerNotes[oldKey]
    KART_LCOfficerNotes[oldKey] = nil
    return true
end
```

- [ ] **Step 4: Manual verification**

Set an officer note on a test-roll row via the assign menu's Edit Note button — the dialog title shows the player's name, the note saves and the note-dot indicator appears on their row. `/dump KART_LCOfficerNotes` shows it keyed by a `"Player-..."` key, not a short name. With two clients, one sets a note on the other — it appears on both (subject to `IsSenderCouncil` passing, same as before).

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: key officer notes and the LC_ONOTE wire message by resolved identity, with legacy-entry migration"
```

---

### Task 10: Pending-resolution retry on `GROUP_ROSTER_UPDATE` + settings-tab pending indicator

**Files:**
- Modify: `Core.lua:226-229` (`GROUP_ROSTER_UPDATE` handler)
- Modify: `LootCouncil.lua` (new throttled retry function, placed near `LC.HandleConfig`)
- Modify: `LootCouncil.lua:~3637-3658` (council-members editbox area — add a pending-count hint label)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (one new locale key)

**Interfaces:**
- Produces: `LC.RetryPendingResolutionsThrottled()` — called from `Core.lua`'s `GROUP_ROSTER_UPDATE` handler, mirrors the existing `KART.HandleAutoPromoteThrottled` leading-edge-throttle pattern in `GroupLogic.lua` (same `GROUP_ROSTER_UPDATE` fires in bursts during mass-invite/raid formation).
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.IsResolvedKey` (Task 1); `LC.ResolveConfigName` (Task 4); `LC.MigrateOfficerNoteKey` (Task 9).

**Root cause:** A council-list/lootmaster entry that couldn't resolve when first parsed (person not online yet), and a legacy `KART_LCOfficerNotes` entry not yet migrated, both need a retry once the roster changes — otherwise they'd stay stuck until the next unrelated settings change or reload. `Core.lua`'s `GROUP_ROSTER_UPDATE` already fires `KART.LC.CheckRaidJoin()` and (in `GroupLogic.lua`) a throttled `KART.HandleAutoPromoteThrottled()` for exactly this "roster settled, re-evaluate" reason — this task adds the identical throttle pattern for pending identity resolution.

- [ ] **Step 1: Add the throttled retry function**

In `LootCouncil.lua`, immediately after `LC.HandleConfig` (added to in Task 4), add:

```lua
-- GROUP_ROSTER_UPDATE fires in bursts during mass-invite/raid formation, and re-scanning every
-- pending entry on every single firing burns CPU for no benefit — same leading-edge throttle
-- pattern as KART.HandleAutoPromoteThrottled in GroupLogic.lua.
local isPendingResolutionThrottled = false
function LC.RetryPendingResolutionsThrottled()
    if isPendingResolutionThrottled then return end
    isPendingResolutionThrottled = true
    C_Timer.After(1, function()
        isPendingResolutionThrottled = false
        LC.RetryPendingResolutions()
    end)
end

-- Re-attempts resolution for every council-list/lootmaster entry still stuck on plain text (see
-- KART.Identity.IsResolvedKey), and migrates any KART_LCOfficerNotes entry still under its legacy
-- short-name key — both cases just mean "this person hadn't been seen yet" at the time they were
-- first parsed. Promotes them to a real key in place; still-unresolvable entries are left alone
-- and retried again next time the roster changes.
function LC.RetryPendingResolutions()
    for pendingText in pairs(LC.CouncilNamesTable) do
        if not KART.Identity.IsResolvedKey(pendingText) then
            local key = LC.ResolveConfigName(pendingText)
            if key and KART.Identity.IsResolvedKey(key) then
                LC.CouncilNamesTable[pendingText] = nil
                LC.CouncilNamesTable[key] = true
            end
        end
    end

    if LC.raidConfig and LC.raidConfig.lootmaster and not KART.Identity.IsResolvedKey(LC.raidConfig.lootmaster) then
        local key = LC.ResolveConfigName(LC.raidConfig.lootmaster)
        if key and KART.Identity.IsResolvedKey(key) then
            LC.raidConfig.lootmaster = key
        end
    end

    for oldKey in pairs(KART_LCOfficerNotes) do
        LC.MigrateOfficerNoteKey(oldKey)
    end
end
```

- [ ] **Step 2: Wire it into `Core.lua`'s `GROUP_ROSTER_UPDATE` handler**

Locate:

```lua
    elseif event == "GROUP_ROSTER_UPDATE" then
        if KART.LC then KART.LC.CheckRaidJoin() end
        if KART.LC and KART.LC.UpdateRoleStatusLabel then KART.LC.UpdateRoleStatusLabel() end
        KART.UpdateRaidleadBarVisibility()
```

Replace with:

```lua
    elseif event == "GROUP_ROSTER_UPDATE" then
        if KART.LC then KART.LC.CheckRaidJoin() end
        if KART.LC and KART.LC.UpdateRoleStatusLabel then KART.LC.UpdateRoleStatusLabel() end
        if KART.LC and KART.LC.RetryPendingResolutionsThrottled then KART.LC.RetryPendingResolutionsThrottled() end
        KART.UpdateRaidleadBarVisibility()
```

- [ ] **Step 3: New locale key**

In `Locales/enUS.lua`, locate:

```lua
    LC_SET_COUNCIL_HINT    = "The raid leader is always in the council. Assistants are not. Character name OR Northern Sky Raid Tools nickname — with a nickname this applies to every character sharing it.",
```

Add immediately after it:

```lua
    LC_SET_COUNCIL_PENDING = "%d name(s) not resolved yet — they'll be matched once seen online.",
```

In `Locales/deDE.lua`, locate:

```lua
    LC_SET_COUNCIL_HINT    = "Raidleiter ist immer automatisch im Council. Assistenten nicht. Charaktername ODER Northern Sky Raid Tools Nickname — bei Nickname zählt das für alle Charaktere mit diesem Nickname.",
```

Add immediately after it:

```lua
    LC_SET_COUNCIL_PENDING = "%d Name(n) noch nicht aufgelöst — werden erkannt, sobald die Person online gesehen wird.",
```

- [ ] **Step 4: Settings-tab pending-count label**

In `LootCouncil.lua`, locate:

```lua
    KART.LC.CouncilMembersEditBox = KART.CreateStyledEditBox(raidBox, "KART_LCCouncilMembers")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(CONTENT_WIDTH, 28)
    ebC:SetMaxLetters(255)
    ebC:SetScript("OnTextChanged", function(self)
        KART_Settings.lcCouncilMembers = self:GetText()
        LC.UpdateCouncilCache()
    end)

    local hintCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintCouncil:SetWidth(CONTENT_WIDTH)
    hintCouncil:SetJustifyH("LEFT")
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintCouncil)
```

Replace with:

```lua
    KART.LC.CouncilMembersEditBox = KART.CreateStyledEditBox(raidBox, "KART_LCCouncilMembers")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(CONTENT_WIDTH, 28)
    ebC:SetMaxLetters(255)
    ebC:SetScript("OnTextChanged", function(self)
        KART_Settings.lcCouncilMembers = self:GetText()
        LC.UpdateCouncilCache()
    end)

    local hintCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintCouncil:SetWidth(CONTENT_WIDTH)
    hintCouncil:SetJustifyH("LEFT")
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintCouncil)

    -- Subdued indicator for council-list entries not yet matched to a live player (see
    -- KART.Identity.IsResolvedKey/LC.RetryPendingResolutions) — hidden entirely once nothing is
    -- pending, so it never clutters the common case.
    KART.LC.CouncilPendingLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.CouncilPendingLabel:SetWidth(CONTENT_WIDTH)
    KART.LC.CouncilPendingLabel:SetJustifyH("LEFT")
    KART.LC.CouncilPendingLabel:SetTextColor(0.85, 0.65, 0.15)
    table.insert(KART.DynamicLabels, KART.LC.CouncilPendingLabel)

    local function UpdateCouncilPendingLabel()
        local pendingCount = 0
        for pendingText in pairs(LC.CouncilNamesTable) do
            if not KART.Identity.IsResolvedKey(pendingText) then pendingCount = pendingCount + 1 end
        end
        if pendingCount > 0 then
            KART.LC.CouncilPendingLabel:SetText(string.format(L.LC_SET_COUNCIL_PENDING, pendingCount))
            KART.LC.CouncilPendingLabel:Show()
        else
            KART.LC.CouncilPendingLabel:Hide()
        end
    end
    KART.LC.CouncilMembersEditBox:HookScript("OnShow", UpdateCouncilPendingLabel)
    hooksecurefunc(LC, "RetryPendingResolutions", UpdateCouncilPendingLabel)
```

- [ ] **Step 5: Manual verification**

Type a council-list entry for a real character who is currently offline; open the Loot Council settings tab — the pending-count label shows "1 name(s) not resolved yet". Log that character in and join the group; within ~1 second of the resulting `GROUP_ROSTER_UPDATE`, `/dump KART.LC.CouncilNamesTable` shows the entry now keyed by a `"Player-..."` key, and reopening the settings tab hides the pending label.

- [ ] **Step 6: Commit**

```bash
git add Core.lua LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: retry pending player-identity resolution on roster change, with a settings-tab indicator"
```

---

### Task 11: Pending trades — `LC.AddPendingTrade`, `LC.RefreshTradeReminder`, `LC.OnTradeShow`, `LC.OnTradeClosed`

**Files:**
- Modify: `LootCouncil.lua:19` (`LC.pendingTrades` declaration comment)
- Modify: `LootCouncil.lua:2836-2844` (`LC.AddPendingTrade`)
- Modify: `LootCouncil.lua:2950` (`LC.RefreshTradeReminder`'s row text)
- Modify: `LootCouncil.lua:2992-3058` (`LC.OnTradeShow`, `LC.OnTradeClosed`)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer`, `KART.Identity.ResolveDisplayName` (Task 1).

**Root cause:** `LC.pendingTrades[].winnerShort` is set from `DoAssignWinner`'s now-key-based `playerKey` (Task 6) — the field itself needs renaming/re-typing to hold a key, and everywhere it's compared (`LC.OnTradeShow`/`LC.OnTradeClosed` matching the trade partner) or displayed (`LC.RefreshTradeReminder`) needs the matching update. The trade partner's own identity (`partnerShort`, derived from the Blizzard trade-frame name) is exactly the same kind of short-name text this whole plan replaces.

- [ ] **Step 1: Update the `LC.pendingTrades` declaration comment**

Locate:

```lua
LC.pendingTrades        = {}  -- items assigned to someone else, not yet handed over: {rollID, itemLink, winnerShort}
```

Replace with:

```lua
LC.pendingTrades        = {}  -- items assigned to someone else, not yet handed over: {rollID, itemLink, winnerKey}
```

- [ ] **Step 2: `LC.AddPendingTrade`**

Locate:

```lua
function LC.AddPendingTrade(rollID, playerShort)
    if IsTestRoll(rollID) then return end
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    LC.RemovePendingTrade(rollID)
    if playerShort == myShort then return end

    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerShort = playerShort})
    LC.RefreshTradeReminder()
end
```

Replace with:

```lua
function LC.AddPendingTrade(rollID, playerKey)
    if IsTestRoll(rollID) then return end
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.RemovePendingTrade(rollID)
    if playerKey == myKey then return end

    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerKey = playerKey})
    LC.RefreshTradeReminder()
end
```

- [ ] **Step 3: `LC.RefreshTradeReminder`'s row text**

Locate:

```lua
        row.text:SetText(string.format(KART.L.LC_TRADE_REMINDER_ROW, entry.itemLink or "???", entry.winnerShort or "?"))
```

Replace with:

```lua
        row.text:SetText(string.format(KART.L.LC_TRADE_REMINDER_ROW, entry.itemLink or "???", KART.Identity.ResolveDisplayName(entry.winnerKey)))
```

- [ ] **Step 4: `LC.OnTradeShow`**

Locate:

```lua
    if not partnerName then return end
    local partnerShort = partnerName:match("([^%-]+)") or partnerName
    -- Remembered for LC.OnTradeClosed, which fires after the trade frame (and UnitName("npc"))
    -- has already started tearing down, so the partner has to be captured here instead. Set
    -- unconditionally (not gated on #LC.pendingTrades, which is specifically this client's own
    -- "items I need to hand out" list) — a client can open this same trade with nothing of its
    -- own pending and still need to know who the partner was, e.g. the separate "items I'm owed"
    -- side the features plan adds, which checks this same field from the other direction.
    LC.currentTradePartnerShort = partnerShort

    for _, entry in ipairs(LC.pendingTrades) do
        -- Bail if the cursor is already carrying something (e.g. the player was mid-drag of an
        -- unrelated item) — picking up our item now would swap it into whatever slot that is.
        if entry.winnerShort == partnerShort and not GetCursorInfo() then ---@diagnostic disable-line: undefined-global
```

Replace with:

```lua
    if not partnerName then return end
    local partnerKey = (KART.Identity.ResolvePlayer(partnerName))
    -- Remembered for LC.OnTradeClosed, which fires after the trade frame (and UnitName("npc"))
    -- has already started tearing down, so the partner has to be captured here instead. Set
    -- unconditionally (not gated on #LC.pendingTrades, which is specifically this client's own
    -- "items I need to hand out" list) — a client can open this same trade with nothing of its
    -- own pending and still need to know who the partner was, e.g. the separate "items I'm owed"
    -- side the features plan adds, which checks this same field from the other direction.
    LC.currentTradePartnerKey = partnerKey

    for _, entry in ipairs(LC.pendingTrades) do
        -- Bail if the cursor is already carrying something (e.g. the player was mid-drag of an
        -- unrelated item) — picking up our item now would swap it into whatever slot that is.
        if entry.winnerKey == partnerKey and not GetCursorInfo() then ---@diagnostic disable-line: undefined-global
```

- [ ] **Step 5: `LC.OnTradeClosed`**

Locate:

```lua
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    LC.currentTradePartnerShort = nil
    if not partnerShort then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        -- Only treat "not found in bags" as "trade completed" for real, resolved item links.
        -- A "???" placeholder entry (async item-link resolution still pending) would always
        -- report "not found" since the placeholder is not a valid item ID to search bags for,
        -- so we'd falsely mark it completed. Leave such entries alone; the user's manual
        -- "done" checkmark button remains available as the fallback for that edge case.
        if entry.winnerShort == partnerShort and IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end
```

Replace with:

```lua
function LC.OnTradeClosed()
    local partnerKey = LC.currentTradePartnerKey
    LC.currentTradePartnerKey = nil
    if not partnerKey then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        -- Only treat "not found in bags" as "trade completed" for real, resolved item links.
        -- A "???" placeholder entry (async item-link resolution still pending) would always
        -- report "not found" since the placeholder is not a valid item ID to search bags for,
        -- so we'd falsely mark it completed. Leave such entries alone; the user's manual
        -- "done" checkmark button remains available as the fallback for that edge case.
        if entry.winnerKey == partnerKey and IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end
```

- [ ] **Step 6: Manual verification (needs two clients)**

Assign an item to Client B; on the lootmaster's client, open a trade with Client B — the item should auto-place into the trade window exactly as before. Complete the trade — the reminder entry clears. Cancel a trade instead — the reminder stays.

- [ ] **Step 7: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: key pending-trade tracking and trade-partner matching by resolved identity"
```

---

### Task 12: Dev test harness — key roster-derived votes/rolls

**Files:**
- Modify: `LootCouncil.lua:3453-3477` (`LC.StartTest`'s pre-fill loop)

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer` (Task 1).

**Root cause:** The Test-button harness pre-fills fake votes/rolls for every current group member using `short` (from `UnitName(unit):match(...)`), keying `LC.votes`/`LC.rolls` the same short-name way real casting/receiving used to — needs the same key switch so the harness stays a faithful smoke test for the rest of this plan (Task 8's `RefreshCouncilRows` now reads these tables by `m.key`, not `m.short`).

- [ ] **Step 1: Update the self-roll**

Locate:

```lua
            local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
            local rollsOn = LC.GetRollsEnabled()
            if rollsOn and myShort ~= "" then
                LC.rolls[testRollID][myShort] = math.random(1, 100)
            end
```

Replace with:

```lua
            local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
            local myKey    = (KART.Identity.ResolvePlayer("player"))
            local rollsOn  = LC.GetRollsEnabled()
            if rollsOn and myShort ~= "" then
                LC.rolls[testRollID][myKey] = math.random(1, 100)
            end
```

(`myShort` stays declared — it's still used a few lines below for the `short ~= myShort` dedup comparison in Step 2, a display-name dedup ("don't fake a vote for myself"), not an identity-table key.)

- [ ] **Step 2: Update the pre-fill loop**

Locate:

```lua
            -- Pre-fill votes (and, if enabled, rolls) from current group members so the council
            -- panel looks populated
            if IsInGroup() then
                local isRaid  = IsInRaid()
                local numMem  = GetNumGroupMembers()
                local voteIdx = itemIdx -- offset per item so the fake votes aren't identical across items
                for i = 1, numMem do
                    local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
                    local name = UnitName(unit)
                    if name then
                        local short = name:match("([^%-]+)")
                        if short and short ~= myShort then
                            LC.votes[testRollID][short] = {idx = voteIdx, note = ""}
                            voteIdx = (voteIdx % #buttons) + 1
                            if rollsOn then LC.rolls[testRollID][short] = math.random(1, 100) end
                        end
                    end
                end
            end
```

Replace with:

```lua
            -- Pre-fill votes (and, if enabled, rolls) from current group members so the council
            -- panel looks populated
            if IsInGroup() then
                local isRaid  = IsInRaid()
                local numMem  = GetNumGroupMembers()
                local voteIdx = itemIdx -- offset per item so the fake votes aren't identical across items
                for i = 1, numMem do
                    local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
                    local name = UnitName(unit)
                    if name then
                        local short = name:match("([^%-]+)")
                        if short and short ~= myShort then
                            local key = (KART.Identity.ResolvePlayer(unit))
                            LC.votes[testRollID][key] = {idx = voteIdx, note = ""}
                            voteIdx = (voteIdx % #buttons) + 1
                            if rollsOn then LC.rolls[testRollID][key] = math.random(1, 100) end
                        end
                    end
                end
            end
```

- [ ] **Step 3: Manual verification**

Click a Test button (both Looter and Council/Master variants) solo and in a group — the council panel populates with fake votes/rolls for every group member exactly as before, and `/dump KART.LC.votes[99999]` shows key-based entries.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "test: key the dev test harness's pre-filled votes/rolls by resolved identity"
```

---

### Task 13: Changelog + version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc:5` (`## Version:`)
- Modify: `CHANGELOG.md`, `CHANGELOG-de.md`

**Interfaces:** None.

- [ ] **Step 1: Bump the version**

In `KeineAhnungRaidTools.toc`, locate:

```
## Version: 2.5.0
```

Replace with:

```
## Version: 2.6.0
```

- [ ] **Step 2: Changelog entries**

In `CHANGELOG.md`, add a new `## [2.6.0]` section (following this file's existing `## [x.y.z]` heading convention — check the file's top for the exact heading format used by the previous entry) with:

```markdown
### Fixed
- **Loot Council no longer confuses two players who share a character name across connected realms.** Votes, council membership, item assignments, and officer notes are now tracked by a permanent per-player identity instead of by name.
```

In `CHANGELOG-de.md`, add the mirrored entry:

```markdown
### Behoben
- **Der Loot Council verwechselt keine zwei Spieler mehr, die sich einen Charakternamen über verbundene Realms teilen.** Votes, Council-Mitgliedschaft, Item-Zuweisungen und Officer-Notizen werden jetzt anhand einer dauerhaften Pro-Spieler-Identität statt anhand des Namens verfolgt.
```

- [ ] **Step 3: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version to 2.6.0 for GUID-based loot council identity"
```

---

## Final whole-branch review

After all 13 tasks are committed, do one final full-diff read of every changed file against the design doc (same closing step the bugfix plan used, which caught 2 real cross-task bugs before merge). Pay particular attention to:

- Every remaining `.short`/`Short` variable in `LootCouncil.lua` that still gets used as a table key anywhere (a `Grep` for `\[.*[Ss]hort\]` and `\[.*[Ss]hort\]` across the file after all tasks land should turn up only genuinely display-only or Droptimizer-related uses).
- `LC.FindUnitForShortName` has no remaining references anywhere in the file (Task 6 deleted it).
- Every wire message's payload format matches what its corresponding `Handle*` function now parses (a mismatched `:match` pattern after a payload-shape change is a silent no-op, not a Lua error).
