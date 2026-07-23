# GUID-Based Player Identity for Loot Council — Design

Date: 2026-07-23
Status: approved (pre-implementation; corresponds to Task 8 of `docs/superpowers/plans/2026-07-22-loot-council-features.md`, which explicitly scoped this out as needing its own brainstorming + writing-plans pass)

## Goal

`LootCouncil.lua` identifies players by comparing lowercased, realm-suffix-stripped short names (`shortName:lower()`) everywhere: vote/roll tables, the council membership list, the raid lootmaster field, and every wire-protocol dispatch. Two different players who share a short character name on different connected realms collide under this scheme — the addon silently treats them as the same person (shared votes, shared council membership, shared roll value).

This design replaces short-name identity with a stable, collision-proof key (Blizzard's `UnitGUID`, falling back to a realm-qualified name for players not currently visible), matching the approach used by the reference implementation `RCLootCouncil2` (`github.com/evil-morfar/RCLootCouncil2`, `Classes/Data/Player.lua` / `Council.lua`).

## Non-goals

- **Buff-checker caches** (`KART.OilCache`, `KART.ILvlCache`, `KART.GearCache`, `KART.PlayerVersions` in `Core.lua`) share the same short-name weakness but are out of scope here — lower impact (no loot-award consequence), left for a separate future ticket.
- **Sender-identity wire format does not change.** Sender identity already arrives for free via Blizzard's `CHAT_MSG_ADDON` event `sender` argument (a full, realm-qualified name) — no change needed to how a message's *sender* is identified. This does **not** cover messages whose payload names a *third party* chosen by the sender's own client — see "Third-party identity in wire payloads" below, where two payloads (`LC_RESULT`, `LC_CVOTE`) do change shape.
- **No backward-compatibility shim.** Hard cutover — every raid member is expected to update together. A client that hasn't updated keeps the old (buggy) short-name behavior locally; this causes no crash or protocol break, since the wire format is unchanged. The existing `KART.PlayerVersions` mismatch notice covers alerting users to update, same as any other feature release.
- **NSRT nickname feature is unaffected.** It's a separate, existing mechanism (config text matched against `KART.GetNickname(unit)` for visible raid members) that continues to work exactly as today — see "Nickname interaction" below for how it composes with the new resolver.

## Architecture

New file `Identity.lua` (sibling to `Utils.lua`), added to `KeineAhnungRaidTools.toc`.

### `KART.Identity.ResolvePlayer(input) -> key`

Takes a unit token (`"player"`, `"raid5"`), a full realm-qualified name (`"Foo-Realm"`, e.g. a `CHAT_MSG_ADDON` sender), or free-typed config text (short name or NSRT nickname). Resolution order:

1. **Input is a visible unit token or resolves to one** → `UnitGUID(unit)`.
2. **Input is a name string, not currently a resolvable unit** → scan the roster (`player`, `party1-4`, `raid1-40`) comparing both `UnitName(unit)` (realm-qualified via `Ambiguate(name, "none")`) and `KART.GetNickname(unit)` against the input. On match, `UnitGUID(unit)`.
3. **No roster match** → look up `input` in `KART_PlayerCache` (reverse index: last-known name/nickname → GUID) for a previously-seen player who isn't currently in the group.
4. **No cache entry either** → the resolution is *pending*. Return the trimmed/lowercased input text itself, tagged as unresolved (see "Settings & pending resolution").

Every successful resolution through steps 1-2 writes/refreshes `KART_PlayerCache[guid] = {name = "Foo-Realm", nickname = "kandera-or-nil", lastSeen = time()}`.

### `KART.Identity.ResolveDisplayName(key) -> shortName`

Inverse lookup for UI rendering: if `key` is a GUID, resolve via visible roster first, then `KART_PlayerCache[key].name` as fallback, then `Ambiguate(..., "short")`. Existing UI row-building code (which already has a `unit` token while iterating the roster) keeps using `UnitName(unit)` directly for display — this function is only needed where a stored key must be rendered without a live unit in hand (e.g. a council member who has since left the raid).

### `KART_PlayerCache` (new SavedVariable)

Account-wide (matches the existing pattern: `KART_Settings`, `KART_LootHistory`, `KART_LCOfficerNotes`, `KART_WoWUtilsCache`, `KART_Profiles` are all account-wide, no `SavedVariablesPerCharacter`). Added to the `.toc` `SavedVariables` line.

```lua
KART_PlayerCache = {
    [guid] = { name = "Foo-Realm", nickname = "kandera", lastSeen = <epoch> },
}
```

No eviction policy is needed initially — the table stores one small record per distinct player ever seen, which stays small for a guild-sized raid roster over realistic addon lifetimes.

## Nickname interaction

NSRT nicknames are unaffected as a *feature* but participate in resolver step 2: matching config text against a visible unit checks both `Ambiguate(name, "none")` and `KART.GetNickname(unit)`, exactly like today's `LC.IsCouncil`/`LC.IsMe` dual-check — only now the match produces a resolved key (stored/compared going forward) instead of being re-compared as text on every check. A nickname typed for someone not currently visible follows the same pending path as any other unresolved config entry (step 4), resolved once that person is next seen.

## Data flow

### Receiving a wire message (`Core.lua`, `CHAT_MSG_ADDON`)

`Core.lua:298` currently computes `local shortName = sender:match("([^%-]+)")` once, shared by both buff-checker branches (`OIL:`, `ILVL:`, `GEAR:`, `VERSION:`/`ANNOUNCE_VERSION:` — out of scope, untouched) and `LC_*` branches (lines 384-405, in scope). Only the ten `LC_*` dispatch call-sites change, replacing the `shortName` argument with `KART.Identity.ResolvePlayer(sender)`:

```lua
-- before
elseif msg:sub(1, 8) == "LC_VOTE:" then
    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), shortName) end

-- after
elseif msg:sub(1, 8) == "LC_VOTE:" then
    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), KART.Identity.ResolvePlayer(sender)) end
```

The `shortName` local itself, and every buff-checker branch that reads it, is untouched.

### Vote/roll/council tables (`LootCouncil.lua`)

- `LC.votes[rollID][key]`, `LC.rolls[rollID][key]` — `key` is now an `Identity.ResolvePlayer` result everywhere a `myShort`/`senderShort`/`playerShort`/`short` variable was previously used as a table key (vote cast, roll cast, `HandleVote`/`HandleRoll`/`HandleCouncilVote` receipt handlers, the dev test harness around line 3446). These tables are per-roll runtime state only — never persisted across a reload, so no migration concern.
- `LC.CouncilNamesTable[key] = true` — built by resolving each comma-separated entry of `KART_Settings.lcCouncilMembers` (see below) instead of storing the raw lowercased text.
- `LC.raidConfig.lootmaster` — stores the resolved key instead of the lowercased text string.
- `LC.IsCouncil(unit)` / `LC.IsMe(configuredName)` / `LC.GetLootmaster()` — compare `KART.Identity.ResolvePlayer(unit-or-input)` against the stored key rather than doing their own text comparison.
- UI row-building (~2100-2360) keeps using `UnitName(unit)`/`KART.GetNickname(unit)` for on-screen display exactly as today — only the table keys used to look up vote/roll data for a given row change to the resolved key.

### Third-party identity in wire payloads

Two messages don't just carry a sender — their payload *names a specific other player*, chosen by the sender from their own (locally unambiguous) roster view: `LC_RESULT`'s winner field (`LC.AnnounceResult`) and `LC_CVOTE`'s candidate field (`LC.ToggleCouncilVote`). Today both send bare short-name text, forcing every *receiver* to reverse-resolve that text against their own roster (`LC.FindUnitForShortName`) — the identical collision hazard this design otherwise removes, just relocated into the payload instead of the sender field.

Fix: at the point these values are captured — always from a UI action where a live `unit`/roster row is in hand (the assign-menu click, the council-vote-pick click) — capture `KART.Identity.ResolvePlayer(unit)` instead of (or alongside) the display short name, and send that resolved key in the payload:

- `LC_RESULT:rollID:key:reason` — `key` replaces the bare winner name. `LC.AssignWinner`/`DoAssignWinner`/`LC.AnnounceResult`'s `winnerName` parameter carries the resolved key end-to-end; `LC.LogHistory` and any chat/UI announcement resolve it to a display name via `KART.Identity.ResolveDisplayName(key)` only at the point of rendering/logging text, same as everywhere else in this design.
- `LC_CVOTE:rollID:key` — `key` replaces `candidateShort`. `LC.councilVotes[rollID][voterKey] = candidateKey`.
- Downstream state that stores one of these values also switches to the resolved key: `LC.assignedWinners[rollID]`, `LC.pendingTrades[].winnerShort` (renamed in intent, not necessarily in field name, to hold a key), and `LC.SetPlayerVote`'s `LC.votes[rollID][key]`.
- This is a wire-format change for exactly these two messages — consistent with the hard-cutover decision already made; no mixed-version compatibility is attempted, same as the rest of this design.

### Officer notes (`KART_LCOfficerNotes`)

A third persistent, short-name-keyed table, found during implementation planning and not in the original scope: `KART_LCOfficerNotes[shortName]` (a free-text council note about a person, set locally via `LC.ShowOfficerNoteDialog`/read at `LootCouncil.lua:3177`, and broadcast/received via `LC_ONOTE` → `LC.HandleOfficerNote`). Same collision bug as everything else here, and it's the one piece of per-player state that *is* persisted across sessions (unlike `LC.votes`/`LC.rolls`), so it needs an explicit migration step, not just a forward-only key-scheme switch:

- `LC_ONOTE` payload's sender-derived key already changes for free (it goes through the same `Core.lua` dispatch fix as `LC_VOTE`/`LC_ROLL`/`LC_CVOTE`).
- `KART_LCOfficerNotes` moves from `[shortName] = noteText` to `[key] = noteText`.
- **One-time migration on first load after update:** iterate the existing `KART_LCOfficerNotes` table, attempt `KART.Identity.ResolvePlayer(oldShortNameKey)` for each entry (roster/cache lookup, same as any other resolution). Where it resolves, insert under the new key and remove the old entry. Where it doesn't resolve (person not seen since update), **leave the old text-keyed entry in place** rather than deleting it — it stays inert (not read by the new key-based lookups) until that person is next seen, at which point a follow-up pass (piggybacked on the same pending-resolution retry as the council list, see below) picks it up and migrates it then. No note is ever silently dropped.

### Settings & pending resolution

`KART_Settings.lcCouncilMembers`/`lcLootmaster` **remain free-text fields** — the raid leader keeps typing comma-separated short names or nicknames, no UI change. Resolution happens where the text is turned into `LC.CouncilNamesTable`/`LC.raidConfig.lootmaster` (`LC.HandleConfig` and the raid-leader-side equivalent around line 250-285):

- Each entry resolves via `KART.Identity.ResolvePlayer` at sync-build/receive time.
- An entry that can't be resolved (person not currently visible, no cache hit) is stored as a **pending marker** (e.g. `LC.CouncilNamesTable[trimmedText] = "pending"` instead of `true`) rather than dropped. The council/lootmaster UI shows a subdued indicator for pending entries ("resolves once seen online").
- A `GROUP_ROSTER_UPDATE` handler re-attempts resolution for any pending entries whenever the roster changes, promoting them to a real key once the named person becomes visible — no manual re-save required.

### Existing saved data / upgrade path

No migration script is needed for settings or runtime state:

- `KART_Settings.lcCouncilMembers`/`lcLootmaster` are already plain text and stay plain text — only the in-memory interpretation changes, on next load.
- `LC.votes`/`LC.rolls`/`LC.councilVotes`/`LC.assignedWinners`/`LC.pendingTrades` never persist across sessions — new key scheme applies from the first roll cast after updating.
- `KART_PlayerCache` starts empty and fills in as players are seen during normal play; until a given player is seen once post-update, their config-list entry is simply pending (see above) rather than incorrectly matched, which is a strict improvement over the current silent-collision behavior.

`KART_LCOfficerNotes` is the one exception — it does persist, and does need the one-time best-effort migration described above ("Officer notes" section).

## Files touched

- **New:** `Identity.lua` (resolver, cache read/write, pending-retry on roster update).
- **New:** `KART_PlayerCache` entry in `KeineAhnungRaidTools.toc` `SavedVariables` line.
- **Changed:** `Core.lua` — the ten `LC_*` dispatch lines (384-405) only.
- **Changed:** `LootCouncil.lua` — vote/roll cast + receipt handlers, `LC.CouncilNamesTable` build/check, `LC.IsCouncil`/`LC.IsMe`/`LC.GetLootmaster`, `LC.AssignWinner`/`DoAssignWinner`/`LC.AnnounceResult`/`LC.HandleResult` (winner key + `LC_RESULT` payload), `LC.ToggleCouncilVote`/`LC.HandleCouncilVote` (candidate key + `LC_CVOTE` payload), `LC.SetPlayerVote`, `LC.AddPendingTrade`/`LC.pendingTrades`, `KART_LCOfficerNotes` read/write/broadcast + one-time migration pass, dev test harness (~3446). UI display code changes only where it reads a table keyed by the old short name — rendering itself (`UnitName`/`GetNickname` calls) is untouched.

Exact line numbers will shift by the time an implementation plan is written (per the bugfix/feature plans' own convention) — re-verify against the current file at that point.

## Testing

No automated test suite or CI exists for this project (confirmed project convention — verification is diff review plus real-play testing). Verification plan:

1. **Dev test harness** (~line 3446, simulates multiple local players) as a first smoke test — confirms nothing regresses in normal single-realm play before any real raid exposure.
2. **Real raid test** — normal operation (no known realm collision in the roster) should show zero behavior change from a player's perspective. A genuine test of the fix itself requires two council/raid members who share a short name across connected realms; opportunistic if such a pair is available, not a blocker for shipping.
