# Stage 0 Library Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the shared parts of KeineAhnungRaidTools into four self-contained LibStub libraries (KAUtil, KAGS, KASC, KAUI) inside the existing addon, so a later split into a standalone Loot Council addon becomes a folder copy rather than a rewrite.

**Architecture:** Four versioned LibStub libraries under `Libs/`, with a strictly acyclic dependency graph (`KAUtil <- KAGS <- KASC`, `KAUtil <- KAUI`, all four `<- KART`). No library may reference `KART.*`. The hardcoded addon-message handler table is replaced by a registration API so the network layer holds no Loot Council knowledge, and the version handshake becomes per-addon.

**Tech Stack:** Lua 5.1 (World of Warcraft client), LibStub, LuaJIT + luacheck for offline verification, GitHub Actions.

**Design spec:** `docs/superpowers/specs/2026-07-26-stage0-library-extraction-design.md`

## Global Constraints

- **One addon throughout.** No second `.toc`, no second CurseForge project, no separate distribution. `Libs/` lives inside `KeineAhnungRaidTools/`.
- **No library may contain the string `KART.`** — enforced by CI in Task 1.
- **No library may contain a user-visible string.** All printing and all locale lookups stay in the addon.
- **No SavedVariables migration.** `KART_Settings`, `KART_LootHistory`, `KART_LCOfficerNotes`, `KART_WoWUtilsCache`, `KART_Profiles`, `KART_PlayerCache` and `KART_LCTrades` keep every key name and meaning. Upgrading 2.9 → 3.0 must preserve loot history, officer notes, profiles and outstanding trades.
- **NSRT nickname resolution must keep working.** `GetNickname` uses `NSAPI:GetName(unit)` with no AddonName argument, wrapped in `pcall`, returning `(caseFoldedNick, originalNick)` and `nil` when the nickname equals the real name. This behaviour is load-bearing for Auto-Promote, the council member list, the lootmaster field and the council panel's name column.
- **`KART.L` is a stable table reference.** Files capture `local L = KART.L` at load time; `Core.lua:196-200` wipes and refills it. No moved code may write `KART.L = {...}`.
- **Project language is English** — code comments, commit messages, docs. German only in `Locales/deDE.lua` values, `README-de.md` and `CHANGELOG-de.md`.
- **Changelog style:** one line per entry, at most two for big changes. Bold lead plus short effect clause. No technical causes, no "was X, now Y".
- **Target release:** v3.0.0, single release, one commit per task so `git bisect` can attribute a later raid bug.
- Lua dialect is **5.1**. Use `luajit` locally, never the installed Lua 5.4 — `tostring(3.0)` differs between them and such values reach the wire.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `Libs/LibStub/LibStub.lua` | Vendored LibStub r2 |
| `Libs/KAUtil-1.0/KAUtil-1.0.lua` | String, group, item-link and table helpers. No dependencies. |
| `Libs/KAGS-1.0/KAGS-1.0.lua` | Gear and enchant scanning of the local player |
| `Libs/KASC-1.0/KASC-1.0.lua` | Addon-message transport, handler registry, identity resolution, data responders, handshake |
| `Libs/KAUI-1.0/KAUI-1.0.lua` | Widget toolkit with per-consumer namespaces |
| `.luacheckrc` | Static analysis config |
| `tests/moved-symbols.txt` | The list of symbols that must no longer appear as `KART.<name>` |
| `tests/check-moved.sh` | The moved-symbol gate and the reverse `Libs/` gate |
| `tests/wow_stubs.lua` | Minimal WoW API surface for the offline harness |
| `tests/run.lua` | Test runner and assertion helpers |
| `tests/test_kautil.lua` | KAUtil behaviour tests |
| `tests/test_kags.lua` | KAGS behaviour tests |
| `tests/test_identity.lua` | Identity and cache tests, including NSRT nicknames |
| `tests/test_sync.lua` | Dispatcher, gates and handshake tests |
| `.github/workflows/check.yml` | Runs all three verification layers on push and pull request |

**Deleted:** `Identity.lua`, `KARTSync.lua`

**Heavily modified:** `Utils.lua` (1473 → ~250 lines), `Core.lua`, `KeineAhnungRaidTools.toc`

**Call-site rewrites only:** `MainFrame.lua`, `BuffChecker.lua`, `Invite.lua`, `RaidleadBar.lua`, `Profiles.lua`, `GroupLogic.lua`, `AutoLog.lua`, `Droptimizer.lua`, `LootCouncil.lua`, `LootCouncilOfficerNotes.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua`, `LootCouncilPanel.lua`, `LootCouncilSettings.lua`, `LootHistory.lua`

---

## Task 1: Verification harness

Nothing moves in this task. The point is to have the checks in place and **green against unchanged code**, which is the only way to know the checks themselves work before they start guarding a refactor.

**Files:**
- Create: `Libs/LibStub/LibStub.lua`, `.luacheckrc`, `tests/moved-symbols.txt`, `tests/check-moved.sh`, `tests/wow_stubs.lua`, `tests/run.lua`, `.github/workflows/check.yml`
- Modify: `KeineAhnungRaidTools.toc`

**Interfaces:**
- Produces: `bash tests/check-moved.sh` (exit 0 = clean), `luajit tests/run.lua` (exit 0 = all assertions passed), globals `T.eq / T.truthy / T.is_nil / T.deep_eq` for later test files, globals `KARTTEST.SetRaid / SetParty / SetNSAPI / ClearSent` and the mutable fields `KARTTEST.realm / inventory / weaponEnchant / equippedIlvl / now / sent`. Tests that need to assert a raised error use `pcall` directly rather than a helper.

- [ ] **Step 1: Install the toolchain**

```bash
# LuaJIT is 5.1-compatible, which is what WoW runs. Do NOT use the Lua 5.4 already installed.
scoop install luajit
# luacheck via luarocks; if luarocks is unavailable, scoop install luarocks first
luarocks install luacheck
luajit -v      # expect: LuaJIT 2.x ... -- compatible with Lua 5.1
luacheck --version
```

- [ ] **Step 2: Vendor LibStub**

Create `Libs/LibStub/LibStub.lua` with the canonical LibStub r2 source (the public-domain
reference implementation, unmodified — do not hand-write a variant):

```lua
-- LibStub is a simple versioning stub meant for use in Libraries.  http://www.wowace.com/addons/libstub/ for more info
-- LibStub is hereby placed in the Public Domain
-- Credits: Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]

if not LibStub or LibStub.minor < LIBSTUB_MINOR then
	LibStub = LibStub or {libs = {}, minors = {} }
	_G[LIBSTUB_MAJOR] = LibStub
	LibStub.minor = LIBSTUB_MINOR

	function LibStub:NewLibrary(major, minor)
		assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
		minor = assert(tonumber(strmatch(minor, "%d+")), "Minor version must either be a number or contain a number.")

		local oldminor = self.minors[major]
		if oldminor and oldminor >= minor then return nil end
		self.minors[major], self.libs[major] = minor, self.libs[major] or {}
		return self.libs[major], oldminor
	end

	function LibStub:GetLibrary(major, silent)
		if not self.libs[major] and not silent then
			error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
		end
		return self.libs[major], self.minors[major]
	end

	function LibStub:IterateLibraries() return pairs(self.libs) end
	setmetatable(LibStub, { __call = LibStub.GetLibrary })
end
```

Note `strmatch` — a WoW global alias for `string.match`. The stub file in Step 5 provides it so
the offline harness can load this file unmodified.

- [ ] **Step 3: Add LibStub to the .toc as the first entry**

In `KeineAhnungRaidTools.toc`, insert above the `Locales\enUS.lua` line:

```
Libs\LibStub\LibStub.lua

```

This also removes a latent bug: `MainFrame.lua:3` calls `LibStub("LibSharedMedia-3.0", true)`
unguarded, so the addon currently fails to load if no other addon supplies the `LibStub` global.

- [ ] **Step 4: Write the moved-symbol gate**

Create `tests/moved-symbols.txt` — empty for now except the header comment, so the gate has
nothing to find yet:

```
# Symbols that have moved out of the KART table into a library.
# The gate asserts none of these still appears anywhere as KART.<name>.
# One bare symbol name per line; blank lines and # comments are ignored.
```

Create `tests/check-moved.sh`:

```bash
#!/usr/bin/env bash
# Two gates, both of which must stay clean:
#   1. No symbol listed in moved-symbols.txt may still be referenced as KART.<name>.
#      luacheck cannot catch this: KART is a defined global and field access on a known
#      table is not validated, so a forgotten call site would pass every other check.
#   2. No file under Libs/ may reference KART. at all -- that is the library boundary.
# Run from the repository root.
set -uo pipefail

fail=0

symbols=$(grep -vE '^\s*(#|$)' tests/moved-symbols.txt | tr -d '\r' | paste -sd'|' -)
if [ -n "$symbols" ]; then
  echo "== Gate 1: leftover KART.<moved symbol> references =="
  if grep -rnE "KART\.($symbols)\b" --include='*.lua' . ; then
    echo "FAIL: the references above must be rewritten to their library." >&2
    fail=1
  else
    echo "clean"
  fi
else
  echo "== Gate 1: skipped, no symbols listed yet =="
fi

echo "== Gate 2: KART. references inside Libs/ =="
if [ -d Libs ] && grep -rn 'KART\.' --include='*.lua' Libs/ ; then
  echo "FAIL: libraries must never reach back into the addon table." >&2
  fail=1
else
  echo "clean"
fi

exit $fail
```

- [ ] **Step 5: Run the gate against unchanged code**

```bash
bash tests/check-moved.sh
```

Expected: both gates report `clean`, exit code 0. Gate 1 reports "skipped".

- [ ] **Step 6: Write the luacheck config**

Create `.luacheckrc`:

```lua
-- WoW runs Lua 5.1. Every WoW API the addon touches is declared read-only here; the addon's
-- own SavedVariables are declared writable. Anything not listed is reported as an undefined
-- global, which is what catches a typo in a global name.
std = "lua51"
max_line_length = false
exclude_files = { "Libs/LibStub/" } -- vendored verbatim, not ours to lint

-- The harness deliberately installs globals: run.lua exports the assertion helpers as T and
-- wow_stubs.lua exports the roster controls as KARTTEST, so every test file can use them
-- without a require. Declared here rather than excluding tests/ from linting altogether.
files["tests/"] = {
    globals = { "T", "KARTTEST", "NSAPI", "UIParent", "C_ChatInfo", "C_Item", "strmatch",
                "strsplit", "wipe", "UnitExists", "UnitName", "UnitGUID", "UnitIsGroupLeader",
                "UnitIsGroupAssistant", "IsInRaid", "IsInGroup", "GetNumGroupMembers",
                "Ambiguate", "GetRealmName", "GetNormalizedRealmName", "GetTime",
                "GetInventoryItemLink", "GetWeaponEnchantInfo", "GetAverageItemLevel",
                "CreateFrame", "time" },
}

globals = {
    -- SavedVariables
    "KART_Settings", "KART_LootHistory", "KART_LCOfficerNotes", "KART_WoWUtilsCache",
    "KART_Profiles", "KART_PlayerCache", "KART_LCTrades",
    -- Named frames created by the addon and reached through _G
    "KART_GearScanTooltip",
}

read_globals = {
    -- Libraries
    "LibStub", "NSAPI",
    -- WoW string/table aliases
    "strmatch", "strsplit", "strjoin", "strtrim", "wipe", "tContains", "time", "date",
    -- Core API
    "CreateFrame", "UIParent", "GameTooltip", "GameFontHighlightSmall", "Item",
    "UnitName", "UnitGUID", "UnitExists", "UnitClass", "UnitIsGroupLeader", "UnitIsGroupAssistant",
    "IsInRaid", "IsInGroup", "GetNumGroupMembers", "Ambiguate",
    "GetRealmName", "GetNormalizedRealmName", "GetLocale",
    "GetInventoryItemLink", "GetAverageItemLevel", "GetWeaponEnchantInfo",
    "GetTime", "LoggingCombat", "ConfirmReadyCheck", "hooksecurefunc",
    "ColorPickerFrame", "StaticPopupDialogs", "StaticPopup_Show",
    "AddonCompartmentFrame", "C_ChatInfo", "C_Item", "C_AddOns", "C_ChallengeMode",
}
```

The list above covers what is needed to lint the current tree. If luacheck reports an
undefined global that is a genuine WoW API, add it to `read_globals` in the same commit.

- [ ] **Step 7: Run luacheck and fix or document what it finds**

```bash
luacheck .
```

Expected: zero warnings. Pre-existing warnings that are deliberate (for example an unused
`self` parameter kept for signature symmetry) get an inline `-- luacheck: ignore` with a
one-line reason, not a blanket suppression.

- [ ] **Step 8: Write the WoW API stubs**

Create `tests/wow_stubs.lua`:

```lua
-- Minimal WoW API surface for the offline harness. Deliberately incomplete: only what the
-- libraries touch at load time or on the code paths under test. A test that reaches beyond
-- this should fail loudly rather than pass against a convincing fake.

_G.strmatch = string.match
_G.strsplit = function(sep, str) return str:match("(.-)" .. sep .. "(.*)") end
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
-- load time. Any method call returns the frame itself so chains do not blow up.
local frameMeta
frameMeta = {
    __index = function(t, k)
        local fn = function(...) return t end
        rawset(t, k, fn)
        return fn
    end,
}
function _G.CreateFrame(_, name, _, _)
    local f = setmetatable({}, frameMeta)
    if name then _G[name] = f end
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
_G.C_Item = {
    GetItemInfo = function(link) return nil, link end,
    GetItemStats = function() return {} end,
}
```

- [ ] **Step 9: Write the test runner**

Create `tests/run.lua`:

```lua
-- Offline harness. Run from the repository root: luajit tests/run.lua
-- Loads the WoW stubs, then LibStub, then each library, then each test file. Library files
-- are loaded in dependency order; a library that fails to load is a hard failure here, which
-- is itself a useful check.

local total, failures = 0, 0

_G.T = {}

function T.eq(actual, expected, label)
    total = total + 1
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL  %s\n        expected: %s\n        actual:   %s",
            label, tostring(expected), tostring(actual)))
    end
end

function T.truthy(value, label) T.eq(not not value, true, label) end
function T.is_nil(value, label) T.eq(value == nil, true, label) end

function T.deep_eq(actual, expected, label)
    local function same(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    total = total + 1
    if not same(actual, expected) then
        failures = failures + 1
        print("FAIL  " .. label .. " (tables differ)")
    end
end

dofile("tests/wow_stubs.lua")
dofile("Libs/LibStub/LibStub.lua")

-- Library files, in dependency order. Extended by each task that adds a library.
-- (Task 2 adds KAUtil, Task 3 KAGS, Task 4 KAUI, Task 7 KASC.)

-- Test files. Extended by each task that adds tests.

print(string.format("\n%d assertions, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)
```

- [ ] **Step 10: Run the empty harness**

```bash
luajit tests/run.lua
```

Expected: `0 assertions, 0 failures`, exit code 0. This proves the stubs and LibStub load
cleanly under LuaJIT before any real test depends on them.

- [ ] **Step 11: Add the CI workflow**

Create `.github/workflows/check.yml`:

```yaml
name: Check

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Lua toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y luajit lua5.1 luarocks
          sudo luarocks install luacheck

      - name: Moved-symbol gate
        run: bash tests/check-moved.sh

      - name: Luacheck
        run: luacheck .

      - name: Offline tests
        run: luajit tests/run.lua
```

- [ ] **Step 12: Verify all three layers pass locally**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

Expected: all three succeed on the **unchanged** addon.

- [ ] **Step 13: Commit**

```bash
git add Libs/LibStub .luacheckrc tests .github/workflows/check.yml KeineAhnungRaidTools.toc
git commit -m "build: add the verification harness and vendor LibStub

Three layers, each catching something the others cannot. The moved-symbol gate is the
one that matters for the extraction that follows: luacheck validates undefined globals,
not field access on a known table, so a forgotten KART.<moved> call site would otherwise
pass every check and only surface in the game.

Vendoring LibStub also fixes a latent load failure -- MainFrame.lua called LibStub()
unguarded, so the addon depended on some other addon supplying the global."
```

---

## Task 2: KAUtil-1.0

**Files:**
- Create: `Libs/KAUtil-1.0/KAUtil-1.0.lua`, `tests/test_kautil.lua`
- Modify: `Utils.lua` (remove the moved functions), `KeineAhnungRaidTools.toc`, `tests/run.lua`, `tests/moved-symbols.txt`, and every file with a call site (129 total)

**Interfaces:**
- Consumes: `LibStub` (Task 1), `T.*` and `KARTTEST.*` (Task 1)
- Produces:
  - `KAUtil.TrimString(s) -> string`
  - `KAUtil.CaseFold(s) -> string` (non-strings pass through unchanged)
  - `KAUtil.SplitString(inputstr, sep) -> table`
  - `KAUtil.IsRealItemLink(link) -> boolean`
  - `KAUtil.GetItemString(link) -> string|nil`
  - `KAUtil.IsFullNameInGroup(fullName) -> boolean`
  - `KAUtil.EachGroupUnit() -> iterator yielding (unitToken, index)`
  - `KAUtil.HasGroupPermissions() -> boolean`
  - `KAUtil.DeepCopy(t) -> table`
  - `KAUtil.MergeDefaults(dst, defaults)` (mutates `dst`, returns nothing)

- [ ] **Step 1: Create the library skeleton**

Create `Libs/KAUtil-1.0/KAUtil-1.0.lua`:

```lua
-- KAUtil-1.0: string, group, item-link and table helpers shared by every KA addon and by the
-- other KA libraries. No dependencies, no user-visible strings, no state.
local MAJOR, MINOR = "KAUtil-1.0", 1
local KAUtil = LibStub:NewLibrary(MAJOR, MINOR)
if not KAUtil then return end
```

- [ ] **Step 2: Move the functions verbatim**

Cut the following from `Utils.lua` **together with their preceding comment blocks**, and paste
them into `KAUtil-1.0.lua` in this order, renaming the `KART.` prefix to `KAUtil.`:

| From `Utils.lua` | Becomes |
|---|---|
| `KART.TrimString` (line 179) | `KAUtil.TrimString` |
| the `CanonRealm` local (line 202) with its long comment block starting line 183 | stays a file-local `CanonRealm` |
| `KART.IsFullNameInGroup` (line 206) | `KAUtil.IsFullNameInGroup` |
| `KART.SplitString` (line 244) | `KAUtil.SplitString` |
| `KART.IsRealItemLink` (line 254) | `KAUtil.IsRealItemLink` |
| `KART.GetItemString` (line 261) | `KAUtil.GetItemString` |
| the `CASEFOLD_LATIN1` table (line 274) with its comment | stays a file-local table |
| `KART.CaseFold` (line 281) | `KAUtil.CaseFold` |
| `KART.HasGroupPermissions` (line 290) | `KAUtil.HasGroupPermissions` |
| `KART.EachGroupUnit` (line 296) | `KAUtil.EachGroupUnit` |
| `KART.DeepCopy` (line 1401) | `KAUtil.DeepCopy` |
| `KART.MergeDefaults` (line 1417) | `KAUtil.MergeDefaults` |

Ordering matters inside the file: `CanonRealm` calls `KAUtil.CaseFold`, and
`KAUtil.IsFullNameInGroup` calls `KAUtil.EachGroupUnit`. Both are resolved at call time rather
than load time, so any order works — but put `CaseFold` and `EachGroupUnit` first anyway so the
file reads top-down.

Internal references change with them: `KART.CaseFold` inside `CanonRealm` and inside
`IsFullNameInGroup` becomes `KAUtil.CaseFold`; `KART.EachGroupUnit` inside `IsFullNameInGroup`
becomes `KAUtil.EachGroupUnit`; `KART.DeepCopy` inside `MergeDefaults` and inside `DeepCopy`
itself becomes `KAUtil.DeepCopy`.

`KART.IsSavedPosOnScreen` (line 237) and its `POS_ON_SCREEN_MARGIN` constant stay in `Utils.lua`
for now — they go to KAUI in Task 4, because they depend on `UIParent`.

- [ ] **Step 3: Add the library to the .toc and the test runner**

`.toc`, directly after the LibStub line:

```
Libs\KAUtil-1.0\KAUtil-1.0.lua
```

`tests/run.lua`, under the "Library files" comment:

```lua
dofile("Libs/KAUtil-1.0/KAUtil-1.0.lua")
```

- [ ] **Step 4: Write the failing tests**

Create `tests/test_kautil.lua`:

```lua
local KAUtil = LibStub("KAUtil-1.0")

-- TrimString -------------------------------------------------------------------------
T.eq(KAUtil.TrimString("  hi  "), "hi", "TrimString strips both ends")
T.eq(KAUtil.TrimString("hi"), "hi", "TrimString leaves a clean string alone")
T.eq(KAUtil.TrimString("   "), "", "TrimString collapses whitespace-only to empty")

-- CaseFold ---------------------------------------------------------------------------
T.eq(KAUtil.CaseFold("ABC"), "abc", "CaseFold lowers ASCII")
T.eq(KAUtil.CaseFold("ÖLmann"), "ölmann", "CaseFold folds the German umlaut :lower() misses")
T.eq(KAUtil.CaseFold("Éclair"), "éclair", "CaseFold folds accented Latin-1 used by NSRT nicknames")
T.eq(KAUtil.CaseFold(42), 42, "CaseFold passes non-strings through unchanged")

-- SplitString ------------------------------------------------------------------------
T.deep_eq(KAUtil.SplitString("a;b;c", ";"), { "a", "b", "c" }, "SplitString splits on the separator")
T.deep_eq(KAUtil.SplitString("a b", nil), { "a", "b" }, "SplitString defaults to whitespace")
T.deep_eq(KAUtil.SplitString("a;;b", ";"), { "a", "b" }, "SplitString drops empty fields")

-- Item links -------------------------------------------------------------------------
local LINK = "|cffa335ee|Hitem:12345:7961::::::::80:::::|h[Test Blade]|h|r"
T.truthy(KAUtil.IsRealItemLink(LINK), "IsRealItemLink accepts a real link")
T.eq(KAUtil.IsRealItemLink("|cff00ff00Fake Item|r"), false, "IsRealItemLink rejects a coloured test string")
T.eq(KAUtil.IsRealItemLink(nil), false, "IsRealItemLink rejects nil")
T.eq(KAUtil.GetItemString(LINK), "item:12345:7961::::::::80:::::", "GetItemString keeps every bonus id")
T.is_nil(KAUtil.GetItemString("|cff00ff00Fake Item|r"), "GetItemString returns nil for a non-link")

-- EachGroupUnit ----------------------------------------------------------------------
KARTTEST.SetRaid({ { name = "Ann" }, { name = "Bob" }, { name = "Cid" } })
local units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "raid1", "raid2", "raid3" }, "EachGroupUnit yields raid tokens in a raid")

KARTTEST.SetParty({ { name = "Ann" }, { name = "Bob" }, { name = "Me" } })
units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "party1", "party2", "player" }, "EachGroupUnit yields player last in a party")

-- IsFullNameInGroup ------------------------------------------------------------------
-- The security gate. Realm is compared canonically on both sides: the sender is always
-- realm-qualified with the normalized spelling, while UnitName returns nil for a same-realm
-- unit and the display spelling ("Tarren Mill") for a cross-realm one.
KARTTEST.realm = "TarrenMill"
KARTTEST.SetRaid({
    { name = "Ann" },                              -- same realm, UnitName realm is nil
    { name = "Bob", realm = "Tarren Mill" },       -- display spelling of our own realm
    { name = "Cid", realm = "Silvermoon" },        -- genuinely cross-realm
})
T.truthy(KAUtil.IsFullNameInGroup("Ann-TarrenMill"), "same-realm member matches despite a nil unit realm")
T.truthy(KAUtil.IsFullNameInGroup("Bob-TarrenMill"), "display realm spelling canonicalizes to the same realm")
T.truthy(KAUtil.IsFullNameInGroup("Cid-Silvermoon"), "cross-realm member matches on its own realm")
T.eq(KAUtil.IsFullNameInGroup("Cid-TarrenMill"), false, "same short name on the wrong realm is rejected")
T.eq(KAUtil.IsFullNameInGroup("Dan-TarrenMill"), false, "a non-member is rejected")
T.eq(KAUtil.IsFullNameInGroup(""), false, "empty input is rejected")
T.eq(KAUtil.IsFullNameInGroup(nil), false, "nil input is rejected")
T.truthy(KAUtil.IsFullNameInGroup("ANN-tarrenmill"), "matching is case-insensitive on both parts")

-- DeepCopy / MergeDefaults -----------------------------------------------------------
local src = { a = 1, nested = { b = 2 } }
local copy = KAUtil.DeepCopy(src)
copy.nested.b = 99
T.eq(src.nested.b, 2, "DeepCopy does not share nested tables with the source")

local dst = { keep = "mine", nested = { existing = 1 } }
KAUtil.MergeDefaults(dst, { keep = "default", added = "new", nested = { existing = 9, fresh = 3 } })
T.eq(dst.keep, "mine", "MergeDefaults never overwrites an existing value")
T.eq(dst.added, "new", "MergeDefaults fills a missing top-level key")
T.eq(dst.nested.existing, 1, "MergeDefaults never overwrites a nested existing value")
T.eq(dst.nested.fresh, 3, "MergeDefaults fills a missing key inside an existing nested table")

local defaults = { nested = { x = 1 } }
local fresh = {}
KAUtil.MergeDefaults(fresh, defaults)
fresh.nested.x = 42
T.eq(defaults.nested.x, 1, "MergeDefaults deep-copies table defaults instead of sharing them")
```

Register it in `tests/run.lua` under the "Test files" comment:

```lua
dofile("tests/test_kautil.lua")
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
luajit tests/run.lua
```

Expected: PASS for every assertion. If `MergeDefaults` or `IsFullNameInGroup` fails here, the
move dropped or altered something — fix the library, never the test.

- [ ] **Step 6: Populate the moved-symbol gate**

Append to `tests/moved-symbols.txt`:

```
TrimString
IsFullNameInGroup
SplitString
IsRealItemLink
GetItemString
CaseFold
HasGroupPermissions
EachGroupUnit
DeepCopy
MergeDefaults
```

- [ ] **Step 7: Run the gate to see exactly what must be rewritten**

```bash
bash tests/check-moved.sh
```

Expected: FAIL, listing all 129 remaining call sites. This list is the work order for the
next step.

- [ ] **Step 8: Rewrite every call site**

In each file that appears in the gate output, add the library handle once near the top, after
the existing `local addonName, KART = ...` line:

```lua
local KAUtil = LibStub("KAUtil-1.0")
```

Then rewrite `KART.TrimString(` to `KAUtil.TrimString(` and so on for all ten symbols. Nothing
else changes — same arguments, same call semantics.

`Utils.lua` needs the handle too: `KART.BuildSearchIndex` and the gear-scanning block still use
these helpers.

- [ ] **Step 9: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

Expected: gate clean (0 matches), luacheck clean, tests pass.

- [ ] **Step 10: In-game smoke test**

Restart WoW fully — a new file is not picked up by `/reload`. Then:
- `/kart` opens the window, all six tabs render
- Buff Checker lists the raid or party
- Loot History opens and shows existing entries

- [ ] **Step 11: Commit**

```bash
git add Libs/KAUtil-1.0 tests KeineAhnungRaidTools.toc *.lua Locales
git commit -m "refactor: extract KAUtil-1.0

String, group, item-link and table helpers used by all three future sides -- the addon,
a possible standalone Loot Council, and KASC itself. IsFullNameInGroup carries the
addon-message security gate, so it is the one function that must have exactly one
definition rather than a copy per addon."
```

---

## Task 3: KAGS-1.0

**Files:**
- Create: `Libs/KAGS-1.0/KAGS-1.0.lua`, `tests/test_kags.lua`
- Modify: `Utils.lua:976-1224` (remove), `Utils.lua:1225-1309` (rewire the diagnostics), `BuffChecker.lua`, `KARTSync.lua`, `KeineAhnungRaidTools.toc`, `tests/run.lua`, `tests/moved-symbols.txt`

**Interfaces:**
- Consumes: `KAUtil` (Task 2)
- Produces:
  - `KAGS.ENCHANTABLE_SLOTS` — array `{1, 3, 5, 7, 8, 11, 12, 16, 17}`
  - `KAGS.SlotNeedsOil(slot) -> boolean`
  - `KAGS.CountMissingGear() -> (enchantList, gemList)` — two strings, each `"0"` or a comma-separated slot list with an optional `w` suffix
  - `KAGS.GetOwnEnchantIDs() -> table`
  - `KAGS.SerializeOwnEnchantIDs() -> string`
  - `KAGS.IsGoodEnchant(slot, enchantID) -> boolean`

- [ ] **Step 1: Create the library skeleton**

Create `Libs/KAGS-1.0/KAGS-1.0.lua`:

```lua
-- KAGS-1.0: scans the local player's own gear for missing enchants, empty sockets and weapon
-- oils. Split from the networking library on purpose -- the accepted-enchant tables are a
-- per-patch maintenance item (see docs/REVIEW-DECISIONS.md) and their churn should not bump
-- the network library's version.
--
-- Reads only the local player. Answering another client's request is KASC's job; this library
-- has no knowledge of the network at all.
local MAJOR, MINOR = "KAGS-1.0", 1
local KAGS = LibStub:NewLibrary(MAJOR, MINOR)
if not KAGS then return end

local KAUtil = LibStub("KAUtil-1.0")
```

- [ ] **Step 2: Move the scanning block verbatim**

Move `Utils.lua` lines **976 through 1224** into the library, keeping every comment. That block
is, in order:

- the `KART_GearScanTooltip` frame and its `SetOwner` call (976-981)
- `emptySocketTexts` / `GetEmptySocketTexts` (983-995)
- `CountEmptySockets` (997-1011)
- the `GOOD_ENCHANTS` table with its full provenance comment (1013-1070)
- `KART.ENCHANTABLE_SLOTS` (1072-1076) → becomes `KAGS.ENCHANTABLE_SLOTS`
- the "do not extend this from a raid survey" note (1078-1081)
- `OIL_EQUIP_LOCS` (1083-1089)
- `KART.SlotNeedsOil` (1091-…) → `KAGS.SlotNeedsOil`
- `IsGoodEnchant` → `KAGS.IsGoodEnchant`
- `KART.CountMissingGear` (1132) → `KAGS.CountMissingGear`
- `KART.GetOwnEnchantIDs` (1175) → `KAGS.GetOwnEnchantIDs`
- `KART.SerializeOwnEnchantIDs` (1191) → `KAGS.SerializeOwnEnchantIDs`

Stop **before** `KART.PrintEnchantDump` at line 1225. That function and
`KART.StartEnchantScan` (1264) and `KART.PrintEnchantScan` (1277) stay in `Utils.lua`: they
print and they use the network, both of which are addon concerns.

Rewire what stays: those three now read `KAGS.ENCHANTABLE_SLOTS`, `KAGS.GetOwnEnchantIDs()`
and `KAGS.SlotNeedsOil(...)` through a `local KAGS = LibStub("KAGS-1.0")` handle at the top of
`Utils.lua`.

If any moved function still references a KAUtil helper, it uses the `KAUtil` local declared in
the skeleton.

- [ ] **Step 3: Add to .toc and runner**

`.toc`, after the KAUtil line:

```
Libs\KAGS-1.0\KAGS-1.0.lua
```

`tests/run.lua`:

```lua
dofile("Libs/KAGS-1.0/KAGS-1.0.lua")
```

- [ ] **Step 4: Write the tests**

Create `tests/test_kags.lua`:

```lua
local KAGS = LibStub("KAGS-1.0")

-- ENCHANTABLE_SLOTS ------------------------------------------------------------------
-- Wrist(9) and Back(15) lost their enchants; Legs(7) takes a spellthread or armour kit but
-- still reports through this list. Off hand(17) is included and filtered per item by
-- SlotNeedsOil / SlotTakesEnchant, not by omission here.
T.deep_eq(KAGS.ENCHANTABLE_SLOTS, { 1, 3, 5, 7, 8, 11, 12, 16, 17 }, "enchantable slot list is unchanged")

-- IsGoodEnchant ----------------------------------------------------------------------
T.truthy(KAGS.IsGoodEnchant(1, 7961), "a confirmed head enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(5, 7987), "a confirmed chest enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(11, 7997), "a confirmed ring enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(16, 6241), "a death knight runeforge is accepted on a weapon")
T.eq(KAGS.IsGoodEnchant(1, 12345), false, "an unknown id on a listed slot is rejected")
-- A slot with no list falls back to a presence-only check, so the table can be filled in one
-- slot at a time without accusing correctly enchanted players in the meantime.
T.truthy(KAGS.IsGoodEnchant(9, 12345), "a slot with no list accepts any enchant")

-- SlotNeedsOil -----------------------------------------------------------------------
-- The equipped item decides, not the spec: a shield tank and an Arms warrior's empty off
-- hand stay out of the oil check while a Fury warrior gets both hands checked.
KARTTEST.inventory = {}
T.eq(KAGS.SlotNeedsOil(16), false, "an empty hand needs no oil")
T.eq(KAGS.SlotNeedsOil(17), false, "an empty off hand needs no oil")

-- SerializeOwnEnchantIDs -------------------------------------------------------------
-- Format contract, because this string goes on the wire: "slot=id" pairs joined by commas,
-- plus an "oil=id" entry for the temporary weapon enchant. The receiving parser in KASC
-- rejects the whole message on one malformed entry, so the shape must not drift.
KARTTEST.inventory = {}
KARTTEST.weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
local serialized = KAGS.SerializeOwnEnchantIDs()
T.eq(type(serialized), "string", "SerializeOwnEnchantIDs returns a string")
for entry in serialized:gmatch("[^,]+") do
    T.truthy(entry:match("^%w+=%d+$"), "every serialized entry matches key=digits: " .. entry)
end
```

Register in `tests/run.lua`:

```lua
dofile("tests/test_kags.lua")
```

- [ ] **Step 5: Run the tests**

```bash
luajit tests/run.lua
```

Expected: PASS. A failure on `IsGoodEnchant` means an id was lost in the move — compare against
`git show HEAD~1:Utils.lua` rather than adjusting the test.

- [ ] **Step 6: Add the symbols to the gate and rewrite call sites**

Append to `tests/moved-symbols.txt`:

```
SlotNeedsOil
CountMissingGear
GetOwnEnchantIDs
SerializeOwnEnchantIDs
ENCHANTABLE_SLOTS
```

```bash
bash tests/check-moved.sh
```

Expected: FAIL, listing 22 call sites plus the `ENCHANTABLE_SLOTS` uses. Rewrite each to
`KAGS.<name>`, adding `local KAGS = LibStub("KAGS-1.0")` at the top of `BuffChecker.lua`,
`KARTSync.lua` and `Utils.lua`.

- [ ] **Step 7: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

- [ ] **Step 8: In-game verification**

Full WoW restart, then in a group:
- Buff Checker advanced view shows the enchant column, gem column, oil column and item level
- Your own row matches what your character actually wears — check one slot deliberately
  unenchanted
- `/kart ench` prints ids with names
- `/kart ench raid` completes and prints the tally

- [ ] **Step 9: Commit**

```bash
git add Libs/KAGS-1.0 tests KeineAhnungRaidTools.toc *.lua
git commit -m "refactor: extract KAGS-1.0

The gear and enchant scanner. It has to be shared rather than addon-private: a client
running only the Loot Council side still has to answer REQ_GEAR and REQ_OIL, or the
Buff Checker goes blind for that player.

The diagnostics that print (/kart ench and the raid scan) stay in the addon -- the
library supplies data, the addon renders it."
```

---

## Task 4: KAUI-1.0 skeleton, registries and ApplyStyle

The widget factories move in Tasks 5 and 6. This task builds the namespace machinery they will
register into, and moves the pieces that have no widget-creation role.

**Files:**
- Create: `Libs/KAUI-1.0/KAUI-1.0.lua`
- Modify: `Utils.lua:5-13` (registries), `Utils.lua:20-26` (locale refreshers), `Utils.lua:136-178` (strata), `Utils.lua:237-242` (`IsSavedPosOnScreen`), `Utils.lua:331-387` (font and theme), `Core.lua:375-463` (`UpdateStyles`), `KeineAhnungRaidTools.toc`, `tests/run.lua`

**Interfaces:**
- Consumes: `KAUtil` (Task 2)
- Produces:
  - `KAUI:NewNamespace(name) -> ns` — repeated calls with the same name return the same namespace
  - `ns:ApplyStyle(spec)` where `spec = { font, menuSize, contentSize, strata, accent = {r, g, b} }` — no `titleSize`: window titles are styled per window by the consumer, since only the consumer knows which frames have one
  - `ns:RegisterAccentTexture(tex, alpha)`
  - `ns:RegisterLabel(fontString)`, `ns:GetLabels() -> array` in insertion order
  - `ns:RegisterEditBox(eb)`, `ns:RegisterButtonText(fs)`, `ns:RegisterCloseButtonText(fs)`, `ns:RegisterSliderThumb(tex)`, `ns:RegisterCheckVisual(tex)`, `ns:RegisterAccentLine(tex)`, `ns:RegisterTabButton(btn)`, `ns:RegisterToggleCheckbox(cb)`
  - `ns:RegisterStrataFrame(frame, isDialog)`, `ns:GetWindowStrata()`, `ns:GetDialogStrata()`, `ns:ApplyFrameStrata()`
  - `ns:RegisterLocaleRefresher(fn)`, `ns:ApplyLocaleRefreshers()`
  - `ns:AccentColor() -> r, g, b` (the accent last passed to `ApplyStyle`)
  - `KAUI.Lighten(r, g, b, amount)`, `KAUI.Darken(r, g, b, amount)` — stateless, library-level
  - `ns:GetRowStripeColor() -> r, g, b, a`
  - `ns:GetFontPath(name) -> string`
  - `KAUI.IsSavedPosOnScreen(x, y) -> boolean`

- [ ] **Step 1: Create the library with the namespace machinery**

Create `Libs/KAUI-1.0/KAUI-1.0.lua`:

```lua
-- KAUI-1.0: the shared widget toolkit. The only one of the KA libraries with per-consumer
-- state -- the widget registries that ApplyStyle walks. That state is held per namespace, so
-- two addons sharing this library each restyle only their own widgets and each fire only
-- their own locale refreshers.
local MAJOR, MINOR = "KAUI-1.0", 1
local KAUI = LibStub:NewLibrary(MAJOR, MINOR)
if not KAUI then return end

local KAUtil = LibStub("KAUtil-1.0")

KAUI.namespaces = KAUI.namespaces or {}

local nsProto = {}
local nsMeta = { __index = nsProto }

-- Every registry is an array, never a hash: BuildSearchIndex walks the labels in insertion
-- order and that order decides how search results are sorted.
local REGISTRIES = {
    "labels", "editBoxes", "buttonTexts", "closeButtonTexts",
    "sliderThumbs", "checkVisuals", "accentLines", "accentTextures",
    "tabButtons", "toggleCheckboxes", "localeRefreshers",
    "strataFrames", "strataDialogFrames",
}

function KAUI:NewNamespace(name)
    assert(type(name) == "string" and name ~= "", "KAUI: namespace name must be a non-empty string")
    if self.namespaces[name] then return self.namespaces[name] end
    local ns = setmetatable({ name = name, accent = { 1, 1, 1 } }, nsMeta)
    for _, key in ipairs(REGISTRIES) do ns[key] = {} end
    self.namespaces[name] = ns
    return ns
end
```

- [ ] **Step 2: Add the registration methods**

Append to the library:

```lua
-- Every registration method has the same shape: append and return the item so a call site can
-- wrap a creation expression. Accent textures are the one exception (they carry an alpha) and
-- get their own function below.
local function appender(registry)
    return function(ns, item)
        if not item then return item end
        ns[registry][#ns[registry] + 1] = item
        return item
    end
end

nsProto.RegisterLabel           = appender("labels")
nsProto.RegisterEditBox         = appender("editBoxes")
nsProto.RegisterButtonText      = appender("buttonTexts")
nsProto.RegisterCloseButtonText = appender("closeButtonTexts")
nsProto.RegisterSliderThumb     = appender("sliderThumbs")
nsProto.RegisterCheckVisual     = appender("checkVisuals")
nsProto.RegisterAccentLine      = appender("accentLines")
nsProto.RegisterTabButton       = appender("tabButtons")
nsProto.RegisterToggleCheckbox  = appender("toggleCheckboxes")

-- Accent textures carry their own alpha, so they are stored as { texture, alpha } pairs.
-- Replaces five hand-written lines in the consumer's UpdateStyles, one per scroll thumb, each
-- of which had to be remembered when a new scrollbar was added.
function nsProto:RegisterAccentTexture(tex, alpha)
    if not tex then return tex end
    self.accentTextures[#self.accentTextures + 1] = { tex, alpha or 0.6 }
    return tex
end

function nsProto:GetLabels() return self.labels end

function nsProto:RegisterLocaleRefresher(fn)
    self.localeRefreshers[#self.localeRefreshers + 1] = fn
end

function nsProto:ApplyLocaleRefreshers()
    for _, fn in ipairs(self.localeRefreshers) do fn() end
end
```

- [ ] **Step 3: Move the strata block**

Move `Utils.lua:136-178` into the library. `KART.StrataFrames` and `KART.StrataDialogFrames`
become `ns.strataFrames` and `ns.strataDialogFrames`; `KART.GetWindowStrata`,
`KART.GetDialogStrata`, `KART.RegisterStrataFrame` and `KART.ApplyFrameStrata` become
`nsProto:` methods. The `STRATA_ORDER` list and the `StrataIndex` local (line 144) stay
file-local in the library.

`ApplyFrameStrata` currently reads `KART_Settings.frameStrata`. It now reads `self.strata`,
which `ApplyStyle` sets.

- [ ] **Step 4: Move theme, font and position helpers**

Move into the library:
- `KART.Theme.Lighten` / `KART.Theme.Darken` (`Utils.lua:354`, `358`) → `KAUI.Lighten` / `KAUI.Darken`, stateless library functions
- `KART.Theme.AccentColor` (366) → `nsProto:AccentColor`, returning `unpack(self.accent)`
- `KART.GetRowStripeColor` (376) → `nsProto:GetRowStripeColor`
- `KART.GetFontPath` (331) → `nsProto:GetFontPath`, with the `LSM` local (`Utils.lua:3`) moved along as a library-level `local LSM = LibStub("LibSharedMedia-3.0", true)`
- `KART.IsSavedPosOnScreen` (237) and `POS_ON_SCREEN_MARGIN` (236) → `KAUI.IsSavedPosOnScreen`, a stateless library function

- [ ] **Step 5: Write ApplyStyle**

Append to the library:

```lua
-- Applies font and accent colour across every registered widget. Everything consumer-specific
-- -- window alpha, window scale, the minimap icon tint, a particular window's title font --
-- stays in the consumer's own UpdateStyles.
function nsProto:ApplyStyle(spec)
    local font        = spec.font
    local menuSize    = spec.menuSize or 11
    local contentSize = spec.contentSize or 12

    self.accent = spec.accent or self.accent
    local r, g, b = self.accent[1], self.accent[2], self.accent[3]

    if spec.strata then
        self.strata = spec.strata
        self:ApplyFrameStrata()
    end

    for _, fs in ipairs(self.buttonTexts) do fs:SetFont(font, menuSize, "") end
    for _, eb in ipairs(self.editBoxes) do eb:SetFont(font, contentSize, "") end
    for _, fs in ipairs(self.labels) do fs:SetFont(font, contentSize, "") end
    for _, fs in ipairs(self.closeButtonTexts) do fs:SetFont(font, 14, "OUTLINE") end

    for _, tex in ipairs(self.sliderThumbs) do tex:SetColorTexture(r, g, b, 1) end
    for _, tex in ipairs(self.checkVisuals) do tex:SetColorTexture(r, g, b, 1) end
    for _, tex in ipairs(self.accentLines) do tex:SetColorTexture(r, g, b, 0.6) end
    for _, entry in ipairs(self.accentTextures) do entry[1]:SetColorTexture(r, g, b, entry[2]) end

    -- Not simple SetColorTexture calls: these depend on Darken() with different amounts and on
    -- the widget's current checked/active state, so they cannot fold into the loops above.
    for _, btn in ipairs(self.tabButtons) do
        if btn.RefreshActiveColor then btn:RefreshActiveColor() end
    end
    for _, cb in ipairs(self.toggleCheckboxes) do
        if cb.RefreshVisual then cb:RefreshVisual() end
    end
end
```

- [ ] **Step 6: Add to .toc and runner**

`.toc`, after the KAGS line:

```
Libs\KAUI-1.0\KAUI-1.0.lua
```

`tests/run.lua`:

```lua
dofile("Libs/KAUI-1.0/KAUI-1.0.lua")
```

There is no `tests/test_kaui.lua`: the toolkit is frames all the way down and is verified in
the game. Loading it in the harness still proves the file parses and that `NewNamespace` does
not error at load.

- [ ] **Step 7: Create the namespace in the addon and rewire UpdateStyles**

In `Utils.lua`, near the top, replace the eleven registry table definitions
(`Utils.lua:5-13`, `20`, `141-142`) with:

```lua
local KAUI = LibStub("KAUI-1.0")
KART.UI = KAUI:NewNamespace("KART")
```

Rewrite `Core.lua:375-463` so that everything generic goes through the namespace:

```lua
function KART.UpdateStyles()
    if not KART_Settings or not KART.MainFrame then return end -- KART.MainFrame aus MainFrame.lua

    local fontPath = KART.UI:GetFontPath(KART_Settings.fontName)
    local r, g, b = KART_Settings.accentR/100, KART_Settings.accentG/100, KART_Settings.accentB/100
    local titleSize = KART_Settings.titleFontSize or 12 -- matches Defaults.titleFontSize

    KART.UI:ApplyStyle({
        font        = fontPath,
        menuSize    = KART_Settings.menuFontSize,
        contentSize = KART_Settings.contentFontSize,
        strata      = KART_Settings.frameStrata,
        accent      = { r, g, b },
    })

    -- The main window is a baked PNG artwork: no backdrop/gradient to tint.
    -- bgAlpha now controls whole-window opacity; floor of 20 so the window
    -- can never become fully invisible while still blocking mouse input.
    KART.MainFrame:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100)
    -- Deferred while the scale slider is being dragged: rescaling the window mid-drag moves the
    -- slider under the cursor, which feeds back into new values and makes the thumb jump. The
    -- slider's OnMouseUp hook (MainFrame.lua) re-runs UpdateStyles to apply the final value.
    if not (KART.SldUiScale and KART.SldUiScale.isDragging) then
        KART.MainFrame:SetScale((KART_Settings.uiScale or 100) / 100)
    end

    -- Ein Font-Wechsel kann Labels anders umbrechen lassen (mehr/weniger Zeilen) — Boxen mit
    -- text-abhängiger Höhenberechnung müssen danach neu positioniert werden.
    if KART.LC and KART.LC.RelayoutRaidBox then KART.LC.RelayoutRaidBox() end

    -- Farbvorschauen im Settings-Menü aktualisieren
    if KART.ColorPreview then KART.ColorPreview:SetColorTexture(r, g, b, 1) end

    -- Minimap Icon Farbe anpassen
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then
        local iconButton = dbIcon:GetMinimapButton("KeineAhnungRaidTools")
        if iconButton and iconButton.icon then
            iconButton.icon:SetVertexColor(r, g, b)
        end
    end

    if KART.LH and KART.LH.historyWindow then
        local w = KART.LH.historyWindow
        -- Artwork background: only the ground texture fades with bgAlpha, content stays solid.
        if w.bg then w.bg:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100) end
        if w.title then
            w.title:SetFont(fontPath, titleSize, "OUTLINE")
            w.title:SetTextColor(1, 1, 1)
        end
    end
end
```

The five per-name scroll-thumb lines (`Core.lua:448-452`) are **deleted**; each thumb's
creation site instead calls `KART.UI:RegisterAccentTexture(thumb, 0.6)`. Find them with:

```bash
grep -rn 'ScrollThumb' --include='*.lua' .
```

- [ ] **Step 8: Rewrite the remaining call sites for this task's symbols**

Append to `tests/moved-symbols.txt`:

```
DynamicLabels
EditBoxes
SliderThumbs
CheckVisuals
TabButtons
ToggleCheckboxes
ButtonTexts
CloseButtonTexts
AccentLines
LocaleRefreshers
StrataFrames
StrataDialogFrames
RegisterLocaleRefresher
ApplyLocaleRefreshers
GetWindowStrata
GetDialogStrata
RegisterStrataFrame
ApplyFrameStrata
Theme
GetRowStripeColor
GetFontPath
IsSavedPosOnScreen
```

```bash
bash tests/check-moved.sh
```

Rewrite each hit:
- `table.insert(KART.DynamicLabels, x)` → `KART.UI:RegisterLabel(x)` (46 sites)
- `table.insert(KART.EditBoxes, eb)` → `KART.UI:RegisterEditBox(eb)`, and the same shape for the other registries
- `KART.Theme.AccentColor()` → `KART.UI:AccentColor()`
- `KART.Theme.Darken(...)` / `KART.Theme.Lighten(...)` → `KAUI.Darken(...)` / `KAUI.Lighten(...)`
- `KART.RegisterStrataFrame(f, true)` → `KART.UI:RegisterStrataFrame(f, true)`
- `KART.GetFontPath(n)` → `KART.UI:GetFontPath(n)`
- `KART.IsSavedPosOnScreen(x, y)` → `KAUI.IsSavedPosOnScreen(x, y)`
- `KART.RegisterLocaleRefresher(fn)` → `KART.UI:RegisterLocaleRefresher(fn)`, and `KART.ApplyLocaleRefreshers()` in `Core.lua:221` → `KART.UI:ApplyLocaleRefreshers()`

Each file needs `local KAUI = LibStub("KAUI-1.0")` only if it calls a stateless library
function (`Lighten`, `Darken`, `IsSavedPosOnScreen`); namespace methods go through `KART.UI`.

`KART.BuildSearchIndex` (`Utils.lua:1448`) changes its first line to iterate
`KART.UI:GetLabels()`.

- [ ] **Step 9: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

- [ ] **Step 10: In-game verification — this is the risky one**

Full restart, then:
- All six tabs render with correct fonts
- Settings → change font: every label, edit box, button text and close × updates, in the main
  window **and** in Loot History, the council panel and the vote popup
- Settings → change accent colour: slider thumbs, checkbox tracks, header lines on popups,
  **all five scroll thumbs** and the minimap icon update
- Settings → change window scale and background opacity
- Settings → change frame strata, then open a popup and confirm it still sits above the window
- Settings search finds a label and jumps to the right tab
- Switch language → ReloadUI → all static text is in the new language

- [ ] **Step 11: Commit**

```bash
git add Libs/KAUI-1.0 tests KeineAhnungRaidTools.toc *.lua
git commit -m "refactor: extract the KAUI-1.0 namespace, registries and ApplyStyle

Widget registries move behind a per-consumer namespace. Global registries would mean that
after a split, one addon's ApplyStyle restyled the other's widgets and one addon's language
switch fired the other's locale refreshers.

Also folds the five hand-listed scroll thumbs into a generic accent-texture registry, so a
new scrollbar is covered automatically instead of by remembering to add a line."
```

---

## Task 5: KAUI-1.0 widget primitives

Pure moves — no signature changes. Splitting these from Task 6 keeps the signature-changing
work in its own reviewable commit.

**Files:**
- Modify: `Libs/KAUI-1.0/KAUI-1.0.lua`, `Utils.lua` (remove the moved factories), all call sites

**Interfaces:**
- Consumes: the namespace from Task 4
- Produces, all as `nsProto:` methods with unchanged argument lists:
  - `ns:ApplyPopupArtwork(frame) -> texture`
  - `ns:CreateHeaderLine(frame, y) -> texture`
  - `ns:CreateHeaderIconButton(parent, glyph, onClick) -> button`
  - `ns:ApplyRoundedMask(frame, radius)`
  - `ns:CreateModernButton(parent, text, tooltipText) -> button`
  - `ns:RegisterStaticPopup(name, def)`
  - `ns:CreateTabButton(parent, text) -> button`
  - `ns:StripScrollbarTextures(scrollFrame)`
  - `ns:AddShowFade(frame, duration)`
  - `ns:CreateGradientOverlay(frame) -> texture`
  - `ns:SetGradientOverlayColor(tex, r, g, b, alpha)`

- [ ] **Step 1: Move the factories**

Move these from `Utils.lua` into `Libs/KAUI-1.0/KAUI-1.0.lua`, with their comment blocks, each
becoming a `function nsProto:Name(...)` with `KART.` internal references rewritten:

| `Utils.lua` line | Becomes |
|---|---|
| 34 `KART.ApplyPopupArtwork` | `nsProto:ApplyPopupArtwork` |
| 52 `KART.CreateHeaderLine` | `nsProto:CreateHeaderLine` |
| 64 `KART.CreateHeaderIconButton` | `nsProto:CreateHeaderIconButton` |
| 388 `KART.ApplyRoundedMask` | `nsProto:ApplyRoundedMask` |
| 460 `KART.CreateModernButton` | `nsProto:CreateModernButton` |
| 509 `KART.RegisterStaticPopup` | `nsProto:RegisterStaticPopup` |
| 522 `KART.CreateTabButton` | `nsProto:CreateTabButton` |
| 1310 `KART.StripScrollbarTextures` | `nsProto:StripScrollbarTextures` |
| 1335 `KART.AddShowFade` | `nsProto:AddShowFade` |
| 1370 `KART.CreateGradientOverlay` | `nsProto:CreateGradientOverlay` |
| 1380 `KART.SetGradientOverlayColor` | `nsProto:SetGradientOverlayColor` |

Internal rewiring inside the moved bodies:
- `table.insert(KART.AccentLines, line)` → `self:RegisterAccentLine(line)`
- `table.insert(KART.ButtonTexts, btn.text)` → `self:RegisterButtonText(btn.text)`
- `table.insert(KART.TabButtons, btn)` → `self:RegisterTabButton(btn)`
- `table.insert(KART.CloseButtonTexts, fs)` → `self:RegisterCloseButtonText(fs)`
- `KART.Theme.Darken(...)` / `Lighten(...)` → `KAUI.Darken(...)` / `KAUI.Lighten(...)`
- `KART.Theme.AccentColor()` → `self:AccentColor()`
- `KART.ApplyRoundedMask(...)` → `self:ApplyRoundedMask(...)`

- [ ] **Step 2: Add the symbols to the gate**

Append to `tests/moved-symbols.txt`:

```
ApplyPopupArtwork
CreateHeaderLine
CreateHeaderIconButton
ApplyRoundedMask
CreateModernButton
RegisterStaticPopup
CreateTabButton
StripScrollbarTextures
AddShowFade
CreateGradientOverlay
SetGradientOverlayColor
```

- [ ] **Step 3: Rewrite the call sites**

```bash
bash tests/check-moved.sh
```

Rewrite each `KART.Name(args)` to `KART.UI:Name(args)`. The argument lists do not change, so
this is purely `KART.` → `KART.UI:`.

- [ ] **Step 4: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

- [ ] **Step 5: In-game verification**

Full restart, then:
- Every popup window (Loot History, its export dialog, the council panel, the vote list, the
  trade reminder, the winner frame, the session prompt) draws its artwork background, its
  accent header line and its close ×
- Tab buttons highlight correctly on click and keep the accent colour
- Every scrollbar renders without Blizzard's default textures
- The Loot Council session prompt fades in rather than appearing instantly
- Static popups (reassign confirm, clear-history confirm, close-session confirm, sync request)
  all appear and act correctly

- [ ] **Step 6: Commit**

```bash
git add Libs/KAUI-1.0 tests *.lua
git commit -m "refactor: move the KAUI widget primitives

Pure relocation, no signature changes -- the factories that take no settings binding move
first so the signature work in the next commit stands alone."
```

---

## Task 6: KAUI-1.0 settings widgets

These bind to a settings table, which the library cannot know. Their signatures change to
options tables.

**Files:**
- Modify: `Libs/KAUI-1.0/KAUI-1.0.lua`, `Utils.lua`, `Core.lua`, every settings-building call site

**Interfaces:**
- Consumes: the namespace from Task 4
- Produces:
  - `ns:CreateSettingsCheckbox(parent, opts) -> checkbox` where `opts = { name, label, store, key, y, onChanged, tooltip }`
  - `ns:CreateSettingsSlider(parent, opts) -> slider` where `opts = { name, label, min, max, store, key, y, tooltip, skipStyleRefresh, onChanged }`
  - `ns:CreateCard(parent, title) -> card` (unchanged signature)
  - `ns:CreateStyledEditBox(parent, name) -> editBox` (unchanged signature)
  - `ns:ShowInputDialog(opts)` (unchanged signature)
  - `ns:OpenColorPicker(opts)` where `opts = { store, rKey, gKey, bKey, onApply }`

- [ ] **Step 1: Move the four unchanged-signature widgets**

Move `KART.CreateCard` (`Utils.lua:765`), `KART.CreateStyledEditBox` (826) and
`KART.ShowInputDialog` (857) into the library as `nsProto:` methods, rewiring their internal
registry inserts (`table.insert(KART.DynamicLabels, card.titleText)` →
`self:RegisterLabel(card.titleText)`, `table.insert(KART.EditBoxes, eb)` →
`self:RegisterEditBox(eb)`) and their `KART.Theme.*` / `KART.ApplyRoundedMask` calls.

- [ ] **Step 2: Move the checkbox with an options-table signature**

Move `KART.CreateSettingsCheckbox` (`Utils.lua:589`). Its head becomes:

```lua
-- opts = {
--   name             frame name, or nil for an anonymous frame
--   label            visible text
--   store            the table holding the setting (the consumer's SavedVariables)
--   key              the field inside store
--   y                TOPLEFT y offset
--   onChanged        called after the value changes; replaces the old direct UpdateStyles call
--   tooltip          tooltip body text
-- }
-- The settings table is passed per call rather than injected once into the library: after a
-- split there would be two stores and one setter, and the last consumer to initialise would
-- silently win.
function nsProto:CreateSettingsCheckbox(parent, opts)
    local cb = CreateFrame("CheckButton", opts.name, parent, "BackdropTemplate")
```

Inside the body, every `KART_Settings[settingKey]` becomes `opts.store[opts.key]`, `labelText`
becomes `opts.label`, `yOffset` becomes `opts.y`, `tooltipText` becomes `opts.tooltip`, and the
`callback` invocation becomes `if opts.onChanged then opts.onChanged() end`. Any direct
`KART.UpdateStyles()` call inside the body is removed — the caller supplies it via `onChanged`.
`table.insert(KART.DynamicLabels, cb.text)` becomes `self:RegisterLabel(cb.text)`,
`table.insert(KART.CheckVisuals, dot)` becomes `self:RegisterCheckVisual(dot)`,
`KART.Theme.AccentColor()` becomes `self:AccentColor()`, and the registration into
`KART.ToggleCheckboxes` becomes `self:RegisterToggleCheckbox(cb)`.

- [ ] **Step 3: Move the slider the same way**

Move `KART.CreateSettingsSlider` (`Utils.lua:676`) with the equivalent options table
(`min`, `max`, `skipStyleRefresh` preserved as fields). `table.insert(KART.DynamicLabels, s.title)`
→ `self:RegisterLabel(s.title)`; the thumb registration → `self:RegisterSliderThumb(thumb)`.

- [ ] **Step 4: Move the colour picker**

Move `KART.OpenColorPicker` (`Utils.lua:936`):

```lua
-- opts = { store, rKey, gKey, bKey, onApply }
-- onApply runs after both the live-update and the cancel path, so the consumer restyles
-- itself instead of the library reaching into the addon.
function nsProto:OpenColorPicker(opts)
    -- The ORIGINAL 0-100 integers are kept for the cancel path below, not re-derived from the
    -- 0-1 values handed to the picker: round-tripping through /100 and math.floor(x*100) loses
    -- a whole unit for 29, 57 and 58 (binary floating point), so cancelling silently darkened
    -- the colour instead of restoring exactly what was there.
    local store = opts.store
    local origR = store[opts.rKey] or 100
    local origG = store[opts.gKey] or 100
    local origB = store[opts.bKey] or 100
    local startR, startG, startB = origR / 100, origG / 100, origB / 100

    local function onUpdate()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        if not r then return end
        -- Round (+0.5), don't truncate: the picker returns 0-1 floats and plain flooring drops
        -- a full unit off most of them (0.29 * 100 is 28.999…), so every pick drifted darker.
        store[opts.rKey] = math.floor(r * 100 + 0.5)
        store[opts.gKey] = math.floor(g * 100 + 0.5)
        store[opts.bKey] = math.floor(b * 100 + 0.5)
        if opts.onApply then opts.onApply() end
    end

    local function onCancel()
        store[opts.rKey] = origR
        store[opts.gKey] = origG
        store[opts.bKey] = origB
        if opts.onApply then opts.onApply() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR, g = startG, b = startB,
            swatchFunc = onUpdate,
            cancelFunc = onCancel,
        })
    end
end
```

- [ ] **Step 5: Add the symbols to the gate**

Append to `tests/moved-symbols.txt`:

```
CreateSettingsCheckbox
CreateSettingsSlider
CreateCard
CreateStyledEditBox
ShowInputDialog
OpenColorPicker
```

- [ ] **Step 6: Rewrite the call sites**

```bash
bash tests/check-moved.sh
```

`CreateCard`, `CreateStyledEditBox` and `ShowInputDialog` are a plain `KART.` → `KART.UI:`
swap. The checkbox, slider and colour picker need their arguments repacked. Worked example —
before:

```lua
KART.CreateSettingsCheckbox(prefsCard, "KART_LCAutoPass", L.LC_AUTOPASS, "lcAutoPass", -40,
    function() LC.RefreshCouncilRows() end, L.DESC_LC_AUTOPASS)
```

after:

```lua
KART.UI:CreateSettingsCheckbox(prefsCard, {
    name = "KART_LCAutoPass", label = L.LC_AUTOPASS,
    store = KART_Settings, key = "lcAutoPass", y = -40,
    onChanged = function() LC.RefreshCouncilRows() end,
    tooltip = L.DESC_LC_AUTOPASS,
})
```

Any call site whose old `callback` relied on the library calling `KART.UpdateStyles()` must now
say so explicitly:

```lua
onChanged = function() KART.UpdateStyles() end,
```

Find those by checking which settings are visual (font, sizes, accent, scale, opacity, strata)
in `Core.lua`'s settings panel.

The colour picker call site becomes:

```lua
KART.UI:OpenColorPicker({
    store = KART_Settings, rKey = "accentR", gKey = "accentG", bKey = "accentB",
    onApply = KART.UpdateStyles,
})
```

- [ ] **Step 7: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

At this point Gate 1 covers every KAUI symbol and must be clean.

- [ ] **Step 8: In-game verification**

Full restart, then walk **every** settings checkbox and slider in all six tabs:
- each reflects its saved value on open
- toggling one changes behaviour immediately and survives `/reload`
- the visual settings (font, font sizes, accent, scale, opacity, strata) still restyle live
- the accent colour picker updates live while dragging and **restores the exact previous
  colour on cancel** — pick 29, 57 or 58 deliberately, those are the values the rounding
  comment is about
- profile switching still applies every setting

- [ ] **Step 9: Commit**

```bash
git add Libs/KAUI-1.0 tests *.lua
git commit -m "refactor: move the KAUI settings widgets onto options tables

The checkbox, slider and colour picker bound directly to KART_Settings and called
KART.UpdateStyles themselves. Both are now passed in per call: a globally injected store
would mean two stores and one setter after a split.

The seven-positional-parameter checkbox signature becomes an options table on the way --
with three of the seven optional, a mis-shifted argument was otherwise silent."
```

---

## Task 7: KASC-1.0 transport, registry, identity and responders

The wire format stays byte-identical in this task. Only the code structure changes.

**Files:**
- Create: `Libs/KASC-1.0/KASC-1.0.lua`, `tests/test_identity.lua`, `tests/test_sync.lua`
- Delete: `Identity.lua`, `KARTSync.lua`
- Modify: `Core.lua`, `BuffChecker.lua`, `LootCouncil.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua`, `LootCouncilPanel.lua`, `LootCouncilOfficerNotes.lua`, `LootHistory.lua`, `Utils.lua`, `KeineAhnungRaidTools.toc`, `tests/run.lua`, `tests/moved-symbols.txt`

**Interfaces:**
- Consumes: `KAUtil` (Task 2), `KAGS` (Task 3)
- Produces:
  - `KASC:Init(prefix)` — registers the addon-message prefix; safe to call more than once
  - `KASC:AttachCache(tbl)` — identity persistence; multiple tables supported
  - `KASC:RegisterAddon(name, version)`
  - `KASC:RegisterCapability(addonName, capName, fn)`
  - `KASC:RegisterMessage(token, opts, fn)` with `opts = { payload, group, enabled }`
  - `KASC:Send(msg, channel, target)`
  - `KASC:DefaultChannel() -> "RAID"|"PARTY"`
  - `KASC.Identity.ResolvePlayer(input) -> key, isPending`
  - `KASC.Identity.FindUnitForKey(key) -> unit|nil`
  - `KASC.Identity.ResolveDisplayName(key) -> string`
  - `KASC.Identity.IsResolvedKey(key) -> boolean`
  - `KASC.Identity.GetNickname(unit) -> foldedNick|nil, originalNick|nil`
  - `ctx` passed to handlers: `{ sender, shortName, channel }` plus `ctx:Key()`

- [ ] **Step 1: Create the library skeleton and transport**

Create `Libs/KASC-1.0/KASC-1.0.lua`:

```lua
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
```

- [ ] **Step 2: Add the registration API**

```lua
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
```

- [ ] **Step 3: Move Identity, rewired onto the cache list**

Move all of `Identity.lua` into the library. Three changes:

1. `KART.GetNickname` (currently `Utils.lua:320`) moves in as `Identity.GetNickname` — it is
   what makes NSRT nicknames resolvable and belongs with the resolution it feeds. `KART.CaseFold`
   inside it becomes `KAUtil.CaseFold`.
2. `KART.EachGroupUnit` becomes `KAUtil.EachGroupUnit`; `KART.CaseFold` and `KART.TrimString`
   become their `KAUtil` equivalents; `KART.GetNickname` becomes `Identity.GetNickname`.
3. Every `KART_PlayerCache` access goes through the cache list:

```lua
-- Writes this player into every attached cache. After a split each addon attaches its own
-- SavedVariable and they stay consistent automatically, with no question of ownership.
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
```

`Identity.ResolvePlayer`'s cache branch calls `LookupCachedKey`; `Identity.ResolveDisplayName`
scans the caches the same way.

The `-- Reviewed 2026-07-25` comment block at the top of `Identity.lua` moves with the code
unchanged — it records a decision a future reviewer must not re-litigate.

- [ ] **Step 4: Add the dispatcher**

```lua
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
```

- [ ] **Step 5: Move the four responders in**

Move the `REQ_OIL`, `REQ_ILVL`, `REQ_GEAR` and `REQ_ENCH` bodies from `KARTSync.lua:121-147`
into the library, registering them at load time, with `KART.SlotNeedsOil` →
`KAGS.SlotNeedsOil`, `KART.CountMissingGear` → `KAGS.CountMissingGear` and
`KART.SerializeOwnEnchantIDs` → `KAGS.SerializeOwnEnchantIDs`:

```lua
-- The answering side. These must work in any KA client, including one that has no Buff
-- Checker of its own and will never render what it reports.
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
```

- [ ] **Step 6: Distribute the remaining handlers to their owners**

Move each remaining handler body out of `KARTSync.lua` into the file that owns its state, as a
`KASC:RegisterMessage(...)` call. Keep every comment. `KART.IsRealItemLink` and
`KART.GetItemString` inside the EQUIP handlers become `KAUtil.*`.

| Handler | Target file | Registration options |
|---|---|---|
| `OIL`, `ILVL`, `GEAR`, `ENCH` receivers, `IsSlotList`, `ParseOilField` | `BuffChecker.lua` | `{ payload = true, group = true }` |
| `RC_REASON` | `Core.lua` — it owns the cache lifecycle (`Core.lua:310` wipes it) and the sending dialog (`Core.lua:512`) | `{ payload = true, group = true }` |
| `REQ_EQUIP`, `EQUIP`, and the `EQUIP_ANSWER_COOLDOWN` / `lastEquipAnswer` locals | `LootCouncilPanel.lua` — `Council.GetOwnEquippedLink` is defined there at line 117 | `{ payload = true, group = true, enabled = lcEnabled }` |
| `LC_ACTIVE`, `LC_START`, `LC_MANUAL_START`, `LC_CONFIG`, `LC_STATE_REQ`, `LC_SYNC_REQUEST`, `LC_SYNC_ACCEPT`, `LC_SYNC_DECLINE` | `LootCouncil.lua` | see note below |
| `LC_VOTE`, `LC_ROLL`, `LC_CVOTE` | `LootCouncilVote.lua` | `{ payload = true, group = true, enabled = lcEnabled }` |
| `LC_ONOTE` | `LootCouncilOfficerNotes.lua` | `{ payload = true, group = true, enabled = lcEnabled }` |
| `LC_RESULT` | `LootCouncilTrade.lua` | `{ payload = true, group = true, enabled = lcEnabled }` |
| `LC_HIST_REQ`, `LC_HIST_ENTRY` | `LootHistory.lua` | `{ payload = true, group = true, enabled = lcEnabled }` |

Each Loot Council file declares the predicate once near the top:

```lua
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end
```

Three registrations keep their current exceptions and must not be given `lcEnabled` or `group`:
- `LC_SYNC_ACCEPT` and `LC_SYNC_DECLINE` are registered with **no** `enabled` and **no**
  `group` — a decline must still print even if the receiver just disabled the module, and the
  sync feature is an explicit whisper to someone outside the group.
- `LC_SYNC_REQUEST` keeps `enabled = lcEnabled` but **no** `group`, for the same reason; the
  receiver confirms it through a popup before anything is applied.
- `LC_STATE_REQ` is `{ payload = false, group = true, enabled = lcEnabled }` — it is a bare
  token with no payload.

- [ ] **Step 7: Keep the handshake byte-identical for now**

Move `HandleVersionMessage`, `REQ_VERSION`, `VERSION` and `ANNOUNCE_VERSION` into `Core.lua`
**unchanged**, registered through `KASC:RegisterMessage`. They still read `KART.PlayerVersions`,
`KART.PlayerLCEnabled`, `KART.UpdateWarned`, `KART.Version` and `KART.L`, all of which are
consumer state and now live in the consumer. Task 8 replaces this wholesale; keeping it
identical here means a raid failure in this task cannot be a protocol failure.

- [ ] **Step 8: Wire up the addon**

In `Core.lua`, inside the `ADDON_LOADED` branch **after** the SavedVariables are created:

```lua
KASC:AttachCache(KART_PlayerCache)
KASC:Init("KART")
```

and at file scope, after `KART.Version` is assigned at line 3:

```lua
KASC:RegisterAddon("KART", KART.Version)
KASC:RegisterCapability("KART", "LC", function() return KART_Settings.lcModuleEnabled ~= false end)
```

`KASC:Init` replaces the `ADDON_LOADED` prefix registration that used to live in
`KARTSync.lua:330-331`.

- [ ] **Step 9: Delete the old files and update the .toc**

```bash
git rm Identity.lua KARTSync.lua
```

`.toc`: remove the `Identity.lua` and `KARTSync.lua` lines, add after the KAGS line:

```
Libs\KASC-1.0\KASC-1.0.lua
```

`tests/run.lua`, after the KAGS line (KASC depends on both KAUtil and KAGS):

```lua
dofile("Libs/KASC-1.0/KASC-1.0.lua")
```

- [ ] **Step 10: Write the identity tests**

Create `tests/test_identity.lua`:

```lua
local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local cache = {}
KASC:AttachCache(cache)

-- Resolution branch 1: a live unit token ------------------------------------------------
KARTTEST.SetNSAPI(false)
KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })
local key, pending = Identity.ResolvePlayer("raid1")
T.eq(key, "Player-1234-AAAA", "a unit token resolves to its GUID")
T.eq(pending, false, "a unit token is never pending")
T.truthy(cache["Player-1234-AAAA"], "resolving a unit writes it into the attached cache")
T.eq(cache["Player-1234-AAAA"].name, "Ann", "the cached name is the realm-free short name")

-- Resolution branch 2: a live name ------------------------------------------------------
key, pending = Identity.ResolvePlayer("Ann-TarrenMill")
T.eq(key, "Player-1234-AAAA", "a realm-qualified sender resolves against the live group")
T.eq(pending, false, "a live name match is not pending")
T.eq(Identity.ResolvePlayer("ann"), "Player-1234-AAAA", "free-typed config text matches case-insensitively")

-- Resolution branch 3: the cache fallback -----------------------------------------------
KARTTEST.SetRaid({})
key, pending = Identity.ResolvePlayer("Ann")
T.eq(key, "Player-1234-AAAA", "someone no longer in the group resolves from the cache")
T.eq(pending, false, "a cache hit is not pending")

-- Resolution branch 4: pending ----------------------------------------------------------
key, pending = Identity.ResolvePlayer("Nobody")
T.eq(key, "nobody", "an unknown name yields trimmed, case-folded placeholder text")
T.eq(pending, true, "an unknown name is pending")
T.eq(Identity.IsResolvedKey("nobody"), false, "placeholder text is not a resolved key")
T.truthy(Identity.IsResolvedKey("Player-1234-AAAA"), "a GUID is a resolved key")

-- NSRT nicknames ------------------------------------------------------------------------
-- Load-bearing for Auto-Promote, the council member list, the lootmaster field and the
-- council panel's name column.
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Bob", guid = "Player-1234-BBBB", nickname = "Bobby" } })
local folded, original = Identity.GetNickname("raid1")
T.eq(folded, "bobby", "GetNickname returns the case-folded nickname first")
T.eq(original, "Bobby", "GetNickname returns the original casing second")
T.eq(Identity.ResolvePlayer("Bobby"), "Player-1234-BBBB", "a nickname resolves to the GUID")
T.eq(Identity.ResolvePlayer("bobby"), "Player-1234-BBBB", "nickname matching is case-insensitive")

KARTTEST.SetRaid({ { name = "Cid", guid = "Player-1234-CCCC", nickname = "Cid" } })
T.is_nil(Identity.GetNickname("raid1"), "NSAPI echoing the real name means no nickname is set")

KARTTEST.SetNSAPI(false)
T.is_nil(Identity.GetNickname("raid1"), "no NSRT installed means no nickname")

-- Umlaut nickname, the reason CaseFold exists ---------------------------------------------
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Dan", guid = "Player-1234-DDDD", nickname = "Öl" } })
T.eq(Identity.ResolvePlayer("öl"), "Player-1234-DDDD", "an umlaut nickname matches in either case")

-- Display names ---------------------------------------------------------------------------
T.eq(Identity.ResolveDisplayName("Player-1234-DDDD"), "Dan", "a live key renders as the unit name")
KARTTEST.SetRaid({})
T.eq(Identity.ResolveDisplayName("Player-1234-BBBB"), "Bobby", "an offline key renders from the cache nickname")
T.eq(Identity.ResolveDisplayName("Player-9999-ZZZZ"), "Player-9999-ZZZZ", "an unknown key renders as itself")

-- Multiple attached caches ------------------------------------------------------------------
local second = {}
KASC:AttachCache(second)
KASC:AttachCache(second) -- attaching twice must not duplicate
KARTTEST.SetNSAPI(false)
KARTTEST.SetRaid({ { name = "Eve", guid = "Player-1234-EEEE" } })
Identity.ResolvePlayer("raid1")
T.truthy(cache["Player-1234-EEEE"], "a write reaches the first attached cache")
T.truthy(second["Player-1234-EEEE"], "a write reaches every attached cache")
```

Register it in `tests/run.lua`.

- [ ] **Step 11: Write the dispatcher tests**

Create `tests/test_sync.lua`:

```lua
local KASC = LibStub("KASC-1.0")

KASC:Init("KART")
KARTTEST.SetNSAPI(false)
KARTTEST.realm = "TarrenMill"
KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })

-- Exact vs payload dispatch --------------------------------------------------------------
local hits = {}
KASC:RegisterMessage("TEST_EXACT", {}, function(payload) hits[#hits + 1] = { "exact", payload } end)
KASC:RegisterMessage("TEST_PAY", { payload = true }, function(payload) hits[#hits + 1] = { "pay", payload } end)

KASC.Dispatch("TEST_EXACT", "RAID", "Ann-TarrenMill")
T.eq(hits[1][1], "exact", "an exact token dispatches to its handler")

hits = {}
KASC.Dispatch("TEST_PAY:hello:world", "RAID", "Ann-TarrenMill")
T.eq(hits[1][1], "pay", "a payload token dispatches to its handler")
T.eq(hits[1][2], "hello:world", "the payload keeps every colon after the first")

hits = {}
KASC.Dispatch("TEST_EXACT:extra", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "an exact-only token with a payload is not dispatched")

hits = {}
KASC.Dispatch("UNKNOWN_TOKEN", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "an unregistered token is dropped")

-- The group gate ---------------------------------------------------------------------------
hits = {}
KASC:RegisterMessage("TEST_GATED", { payload = true, group = true },
    function() hits[#hits + 1] = true end)
KASC.Dispatch("TEST_GATED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 1, "a grouped sender passes the group gate")
KASC.Dispatch("TEST_GATED:x", "WHISPER", "Stranger-Silvermoon")
T.eq(#hits, 1, "an outsider is rejected by the group gate")
-- The realm is what makes this a real gate: resolution is short-name based, so a same-short-
-- named outsider would resolve onto the group member's GUID and pass every authority check.
KASC.Dispatch("TEST_GATED:x", "WHISPER", "Ann-Silvermoon")
T.eq(#hits, 1, "a same-short-name sender on another realm is rejected")

-- The enabled gate --------------------------------------------------------------------------
local moduleOn = false
hits = {}
KASC:RegisterMessage("TEST_ENABLED", { payload = true, enabled = function() return moduleOn end },
    function() hits[#hits + 1] = true end)
KASC.Dispatch("TEST_ENABLED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 0, "a disabled handler does not run")
moduleOn = true
KASC.Dispatch("TEST_ENABLED:x", "RAID", "Ann-TarrenMill")
T.eq(#hits, 1, "the same handler runs once enabled")

-- ctx ------------------------------------------------------------------------------------
local seen
KASC:RegisterMessage("TEST_CTX", { payload = true }, function(_, ctx) seen = ctx end)
KASC.Dispatch("TEST_CTX:x", "RAID", "Ann-TarrenMill")
T.eq(seen.sender, "Ann-TarrenMill", "ctx carries the full sender")
T.eq(seen.shortName, "Ann", "ctx carries the realm-free short name")
T.eq(seen.channel, "RAID", "ctx carries the channel")
T.eq(seen:Key(), "Player-1234-AAAA", "ctx:Key() resolves the sender")
T.eq(seen:Key(), "Player-1234-AAAA", "ctx:Key() is stable across calls")

-- Duplicate registration is a programming error, not a silent overwrite ---------------------
local ok = pcall(function()
    KASC:RegisterMessage("TEST_CTX", { payload = true }, function() end)
end)
T.eq(ok, false, "registering the same token twice raises")

-- Send ---------------------------------------------------------------------------------------
KARTTEST.ClearSent()
KASC:Send("HELLO")
T.eq(KARTTEST.sent[1].prefix, "KART", "Send uses the registered prefix")
T.eq(KARTTEST.sent[1].channel, "RAID", "Send defaults to RAID while in a raid")
KARTTEST.SetParty({ { name = "Ann", guid = "Player-1234-AAAA" } })
KARTTEST.ClearSent()
KASC:Send("HELLO")
T.eq(KARTTEST.sent[1].channel, "PARTY", "Send defaults to PARTY outside a raid")
```

Register it in `tests/run.lua`.

- [ ] **Step 12: Add the symbols to the gate**

Append to `tests/moved-symbols.txt`:

```
Sync
Identity
GetNickname
```

- [ ] **Step 13: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

Rewrite every remaining `KART.Sync.Send(` to `KASC:Send(`, `KART.Identity.` to
`KASC.Identity.` and `KART.GetNickname(` to `KASC.Identity.GetNickname(` until the gate is
clean.

- [ ] **Step 14: In-game verification — needs a second client**

Full restart on both clients, in a group:
- Buff Checker advanced shows oil, enchants, gems, item level and repair for the other player
- Ready-check decline reason arrives and prints for the leader
- Loot Council: start a session, the other client sees the vote popup, votes, the vote lands
- Council panel shows the other player's equipped item in the compare column
- Officer note syncs
- Trade reminder appears after an assignment, and the winner frame shows
- Loot History syncs an entry
- `/kart` version check lists both clients
- Disable the Loot Council module on one client and confirm `LC_*` messages are ignored there
  while the version check still reports it

- [ ] **Step 15: Commit**

```bash
git add -A
git commit -m "refactor: extract KASC-1.0 and replace the handler table with a registry

Handlers now register themselves from the file that owns their state, with an arbitrary
enabled predicate in place of the hardcoded Loot Council flag. KARTSync had 23 references
into KART.LC, KART.LH and the Buff Checker; the library now has none.

KASC owns the answering side of the data requests and consumers own the receiving side --
a client with no Buff Checker of its own still has to answer REQ_GEAR.

The wire format is deliberately untouched here so a raid failure in this commit cannot be
a protocol failure."
```

---

## Task 8: The KA_HELLO handshake

**Files:**
- Modify: `Libs/KASC-1.0/KASC-1.0.lua`, `Core.lua`, `tests/test_sync.lua`

**Interfaces:**
- Consumes: everything from Task 7
- Produces:
  - `KASC.SerializeHello() -> string`
  - `KASC.ParseHello(payload) -> table` mapping `addonName -> { version = string, caps = { [capName] = true } }`
  - `KASC:RequestHello()` — broadcasts `KA_HELLO_REQ` on the default channel
  - `KASC:OnPeer(fn)` fires `fn(shortName, fullName, addons)`

- [ ] **Step 1: Write the failing handshake tests**

Append to `tests/test_sync.lua`:

```lua
-- Handshake ---------------------------------------------------------------------------------
-- Name, version and capability are restricted to [%w%.%-_]; anything else drops the entry.
-- This replaces the old ver:gsub("|","||") defence with a whitelist, because the version
-- string is printed to chat and rendered in the council panel.
local parsed = KASC.ParseHello("KART=3.0.0+LC")
T.eq(parsed.KART.version, "3.0.0", "a single addon entry parses")
T.truthy(parsed.KART.caps.LC, "a capability suffix parses")

parsed = KASC.ParseHello("KART=3.1.0,KALC=1.0.0+LC")
T.eq(parsed.KART.version, "3.1.0", "the first of two addon entries parses")
T.eq(parsed.KALC.version, "1.0.0", "the second of two addon entries parses")
T.truthy(parsed.KALC.caps.LC, "the capability attaches to the right addon")
T.is_nil(parsed.KART.caps.LC, "a capability does not leak onto the other addon")

parsed = KASC.ParseHello("KART=3.0.0")
T.eq(parsed.KART.version, "3.0.0", "an entry with no capability parses")

-- Hostile and malformed input ------------------------------------------------------------
T.is_nil(KASC.ParseHello("KART=|cff00ff00ffff").KART, "a colour escape in the version drops the entry")
T.is_nil(KASC.ParseHello("KART=3.0.0+|Hitem:1|h").KART, "an escape in a capability drops the entry")
T.is_nil(KASC.ParseHello("KART=3.0.0+").KART, "a trailing plus with no capability drops the entry")
T.is_nil(KASC.ParseHello("=3.0.0").KART, "an empty name drops the entry")
T.is_nil(KASC.ParseHello("KART=").KART, "an empty version drops the entry")
T.deep_eq(KASC.ParseHello(",,"), {}, "a payload of separators yields nothing")
T.deep_eq(KASC.ParseHello(""), {}, "an empty payload yields nothing")
T.deep_eq(KASC.ParseHello(nil), {}, "a nil payload yields nothing")

-- One bad entry must not take a good one with it -------------------------------------------
parsed = KASC.ParseHello("KART=3.0.0,BAD=|cff00ff00")
T.eq(parsed.KART.version, "3.0.0", "a good entry survives alongside a rejected one")
T.is_nil(parsed.BAD, "the rejected entry is absent")

-- Serialisation round-trips ------------------------------------------------------------------
KASC:RegisterAddon("TESTADDON", "9.9.9")
KASC:RegisterCapability("TESTADDON", "CAP", function() return true end)
local round = KASC.ParseHello(KASC.SerializeHello())
T.eq(round.TESTADDON.version, "9.9.9", "a registered addon round-trips through the wire format")
T.truthy(round.TESTADDON.caps.CAP, "an enabled capability round-trips")

-- A capability whose predicate is false must not appear -----------------------------------------
KASC:RegisterAddon("TESTOFF", "1.0.0")
KASC:RegisterCapability("TESTOFF", "OFFCAP", function() return false end)
round = KASC.ParseHello(KASC.SerializeHello())
T.eq(round.TESTOFF.version, "1.0.0", "an addon with no enabled capability still appears")
T.is_nil(round.TESTOFF.caps.OFFCAP, "a disabled capability is omitted")
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
luajit tests/run.lua
```

Expected: FAIL with `attempt to call field 'ParseHello' (a nil value)`.

- [ ] **Step 3: Implement the handshake in KASC**

Append to `Libs/KASC-1.0/KASC-1.0.lua`:

```lua
-- Handshake. Grammar: entries separated by ",", each "name=version" with optional
-- "+capability" suffixes. Name, version and capability are restricted to [%w%.%-_], so a
-- colour escape or a hyperlink cannot reach the consumer's chat output or the council panel
-- at all -- a whitelist rather than escaping after the fact.
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
        if name and version and name:match(ENTRY_CHARS) and version:match(ENTRY_CHARS) then
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

function KASC:RequestHello()
    self:Send("KA_HELLO_REQ")
end

KASC:RegisterMessage("KA_HELLO_REQ", {}, function(_, ctx)
    if ctx.channel == "WHISPER" then
        KASC:Send("KA_HELLO:" .. KASC.SerializeHello(), "WHISPER", ctx.sender)
    else
        KASC:Send("KA_HELLO:" .. KASC.SerializeHello(), ctx.channel)
    end
end)

KASC:RegisterMessage("KA_HELLO", { payload = true }, function(payload, ctx)
    local peers = KASC.ParseHello(payload)
    for _, fn in ipairs(peerCallbacks) do fn(ctx.shortName, ctx.sender, peers) end
end)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
luajit tests/run.lua
```

Expected: PASS.

- [ ] **Step 5: Replace the old handshake in Core.lua**

Delete the `HandleVersionMessage` function and the `REQ_VERSION`, `VERSION` and
`ANNOUNCE_VERSION` registrations moved in during Task 7. Replace with:

```lua
-- Peer version bookkeeping. The comparison, the update warning and the chat output all live
-- here rather than in KASC: they are locale-dependent and none of them is a networking
-- concern.
KASC:OnPeer(function(shortName, _, peers)
    local kart = peers.KART
    if not kart then return end

    KART.PlayerVersions = KART.PlayerVersions or {}
    KART.PlayerVersions[shortName] = kart.version
    KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
    KART.PlayerLCEnabled[shortName] = kart.caps.LC or false

    -- Throttled: a raid join answers one request with one reply per raider, all at once.
    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRowsThrottled()
    end

    if not KART.UpdateWarned and kart.version ~= KART.Version then
        -- Lenient parse: a 2-part version ("2.9") or a trailing build suffix still yields
        -- usable numbers instead of failing the match outright and collapsing to 0.0.0.
        local nMaj, nMin, nPat = kart.version:match("(%d+)%.?(%d*)%.?(%d*)")
        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.?(%d*)%.?(%d*)")
        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0
        -- Sanity clamp before trusting the number: no handler authenticates a sender, so
        -- anyone can claim a huge version, and UpdateWarned latches after the first print --
        -- one bogus claim would suppress the real warning for the whole session. A genuine
        -- release never jumps more than a major ahead.
        local plausible = nMaj <= oMaj + 1
        if plausible and (nMaj > oMaj
            or (nMaj == oMaj and nMin > oMin)
            or (nMaj == oMaj and nMin == oMin and nPat > oPat)) then
            KART.UpdateWarned = true
            print(string.format(KART.L.UPDATE_AVAILABLE, kart.version, KART.Version))
        end
    end

    if KART.VersionCheckActive then
        print(string.format(KART.L.VERSION_CHECK_RES, shortName, kart.version))
    end
end)
```

The version string no longer needs `gsub("|", "||")`: `ParseHello`'s whitelist means a `|`
never reaches this function.

Every place that used to send `REQ_VERSION` or `ANNOUNCE_VERSION` now calls
`KASC:RequestHello()` or sends `KA_HELLO` directly. Find them with:

```bash
grep -rn 'REQ_VERSION\|ANNOUNCE_VERSION\|VERSION:' --include='*.lua' .
```

The guild announcement path that used `ANNOUNCE_VERSION` becomes
`KASC:Send("KA_HELLO:" .. KASC.SerializeHello(), "GUILD")`. Note that the old `isAnnounce`
flag existed only to suppress the `VERSION_CHECK_RES` print for announcements; keep that
behaviour by gating the print on `KART.VersionCheckActive`, which is already how it works.

- [ ] **Step 6: Verify all three layers**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

- [ ] **Step 7: In-game verification with two clients**

Both clients on the new build, full restart:
- `/kart` version check lists both clients with the right versions
- Disable the Loot Council module on one client; the council panel on the other shows it as
  LC-off
- Log in fresh with an outdated version number faked in the `.toc` on one client and confirm
  the other prints the update warning exactly once
- Confirm the guild announcement path still prints on login

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: per-addon KA_HELLO handshake

Replaces VERSION/REQ_VERSION, which carried exactly one version and one hardcoded Loot
Council flag per player. The new payload carries an entry per addon with named capability
suffixes, so a later split needs no protocol change.

2.9 clients are deliberately not accommodated. Name, version and capability are whitelisted
to [%w%.%-_] rather than escaped after the fact -- the version string is printed to chat and
rendered in the council panel."
```

---

## Task 9: Packaging and release

**Files:**
- Modify: `.pkgmeta`, `.github/workflows/release.yml`, `KeineAhnungRaidTools.toc`, `CHANGELOG.md`, `CHANGELOG-de.md`, `README.md`, `README-de.md`

- [ ] **Step 1: Keep the test files out of the shipped package**

In `.pkgmeta`, add to the `ignore` list:

```yaml
  - tests
  - .luacheckrc
  - docs
```

(`docs` is already listed; add the two new entries above it or below it, keeping the list
alphabetical is not required.)

In `.github/workflows/release.yml`, add to the `rsync` excludes in the "Build zip" step:

```
            --exclude='tests' \
            --exclude='.luacheckrc' \
            --exclude='docs' \
```

- [ ] **Step 2: Bump the version**

`KeineAhnungRaidTools.toc`:

```
## Version: 3.0.0
```

- [ ] **Step 3: Verify the built package**

```bash
mkdir -p /tmp/kartdist/KeineAhnungRaidTools
rsync -a --exclude='.git' --exclude='.github' --exclude='dist' --exclude='tests' \
      --exclude='.luacheckrc' --exclude='docs' . /tmp/kartdist/KeineAhnungRaidTools/
find /tmp/kartdist -name '*.lua' | grep -E 'tests/|docs/' && echo "FAIL: test files shipped" || echo "clean"
ls /tmp/kartdist/KeineAhnungRaidTools/Libs
```

Expected: `clean`, and `Libs` contains `LibStub`, `KAUtil-1.0`, `KAGS-1.0`, `KASC-1.0`,
`KAUI-1.0`.

- [ ] **Step 4: Write the changelog entries**

`CHANGELOG.md`, under a new `## [3.0.0]` heading. One line per entry, bold lead plus a short
effect clause — no technical causes, no implementation detail:

```markdown
## [3.0.0]

### Changed
- **Version check rebuilt.** Clients on 2.9 or older no longer appear in the list until they update.
- **Internal restructuring.** Shared code now lives in libraries; no settings, history or notes are affected.
```

Mirror into `CHANGELOG-de.md` in the same commit:

```markdown
## [3.0.0]

### Geändert
- **Versionsprüfung neu gebaut.** Clients mit 2.9 oder älter erscheinen erst nach einem Update wieder in der Liste.
- **Interne Umstrukturierung.** Geteilter Code liegt jetzt in Libraries; Einstellungen, Historie und Notizen bleiben unberührt.
```

- [ ] **Step 5: Final full verification**

```bash
bash tests/check-moved.sh && luacheck . && luajit tests/run.lua
```

Then confirm the acceptance criteria from the spec:

```bash
# No library may reach back into the addon table
grep -rn 'KART\.' --include='*.lua' Libs/ && echo "FAIL" || echo "clean"
# Identity.lua and KARTSync.lua are gone
ls Identity.lua KARTSync.lua 2>/dev/null && echo "FAIL: old files still present" || echo "clean"
```

- [ ] **Step 6: Full in-game checklist**

Run the complete checklist from the design spec §12 on a fresh WoW start, with a second
client in the group, and in a real raid before tagging:

**UI** — all six tabs · font, accent, scale, strata and background opacity each take effect in
the main window and in popups · settings search finds a label and jumps to its tab · language
switch plus ReloadUI · profile switch · minimap button and addon compartment

**Loot Council** — session start · vote popup · council panel with equipped compare and the
Droptimizer gain column · trade reminder · winner frame · Loot History and its export dialog

**Network** — Buff Checker advanced shows enchants, gems, oil, item level and repair for every
raider · version check lists everyone · ready-check reason arrives

**NSRT** — council panel shows nicknames · auto-promote and lootmaster lists match on nickname

**Upgrade** — start from a 2.9 SavedVariables file and confirm loot history, officer notes,
profiles and outstanding trades all survive

- [ ] **Step 7: Commit and tag**

```bash
git add -A
git commit -m "release: v3.0.0

Shared code extracted into four LibStub libraries inside the addon: KAUtil, KAGS, KASC
and KAUI. One addon still ships -- the libraries exist so that a later split into a
standalone Loot Council addon is a folder copy rather than a rewrite.

No SavedVariables change. The only user-visible difference is the rebuilt version check."
git tag v3.0.0
```

Do not push the tag until the raid test has passed — the tag triggers the CurseForge upload
and the Discord announcement.

---

## Notes for the implementer

**Every task ends with a full WoW restart, not `/reload`.** New files are only picked up on a
restart; `/reload` re-runs existing ones. A change that appears not to work is very often a
`/reload` that could not see a new file.

**Never fix a failing test by changing the test.** These tests encode current behaviour. If one
fails after a move, compare against the previous commit (`git show HEAD~1:Utils.lua`) — the move
dropped something.

**The gate output is the work order.** `bash tests/check-moved.sh` lists exactly the call sites
still to rewrite, with file and line. Work it top to bottom rather than searching by hand.

**Do not re-litigate documented decisions.** `docs/REVIEW-DECISIONS.md` records findings that
were examined and deliberately kept: the short-name-based identity matching with no ambiguity
guard, the hardcoded `GOOD_ENCHANTS` list with no opt-out, the missing purge on a manual roll id
collision. Moving that code does not reopen those decisions, and the comments recording them move
with it.
