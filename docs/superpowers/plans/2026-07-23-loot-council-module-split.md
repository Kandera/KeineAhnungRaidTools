# LootCouncil.lua Module Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `LootCouncil.lua` (3914 lines, everything flat under `KART.LC`) into six files — the original file slimmed down plus four new sub-namespaced files (`KART.LC.Vote`, `KART.LC.Council`, `KART.LC.Trade`, `KART.LC.OfficerNotes`) plus the loot-history write/sync path moved into the existing `LootHistory.lua` (`KART.LH`) — with zero behavior change.

**Architecture:** Functions move into sub-namespaced files grouped by concern; every shared mutable state table and UI-widget field (`LC.votes`, `LC.councilPanel`, `LC.RaidBox`, etc.) stays flat on `KART.LC` untouched, since external files already read/write these directly. A small set of currently-`local` helper functions (`SendLC`, `GetChannel`, `IsTestRoll`, `GetVoteIconTexture`, `SetClassIconTexture`, `IsCouncil`, `IsSenderCouncil`, `IsRealItemLink`, `ParseItemColor`) turn out to be used across every section about to be split apart — since Lua's `local` is file-scoped, these must be promoted to flat `LC.*` functions *before* any file split, or every new file would need its own duplicate copy. That promotion is Task 1.

**Tech Stack:** WoW Lua addon (retail), no build step, no automated test suite. Verification is (a) an addon-wide grep sweep after every task confirming zero dangling references to a relocated function's old bare name remain anywhere, and (b) an in-client smoke test using the existing dev test harness (Settings tab → "Test Looter" / "Test Master" buttons, which call `LC.StartTest("looter")` / `LC.StartTest("master")`).

**Design doc:** `docs/superpowers/specs/2026-07-23-loot-council-module-split-design.md` — read this first. One refinement found while writing this plan, not yet reflected in the design doc's prose: the nine shared local helpers listed above need promoting to flat `LC.*` functions first (Task 1) — the design doc's "state stays flat" principle already covers this in spirit (these are stateless helpers, not per-module logic), it just didn't enumerate them explicitly because that requires reading every section's internals, done here.

## Global Constraints

- English source: code, comments, commit messages (`CLAUDE.md` convention).
- Direct commits to `main`, no feature branch — this project's established workflow.
- **No changelog entry, no `.toc` version bump.** Unlike the GUID-identity plan, this is a pure internal file reorganization with zero observable behavior change for players — per `CLAUDE.md`'s changelog rule ("the changelog is for players skimming what changed"), there is nothing for a player to skim here.
- **Every moved function's body is byte-identical to its original.** Only two things change per moved function: its `function LC.Foo(...)` def line becomes `function Vote.Foo(...)` (or `Council.`/`Trade.`/`OfficerNotes.`/`LH.` — using the file's own local alias, matching the existing `Identity.lua` pattern), and any call inside its body to another function that has *also* relocated becomes fully-qualified (e.g. `LC.LogHistory(...)` becomes `KART.LH.LogHistory(...)`).
- **Re-verify every line number below against the current file before editing.** This plan was written against a specific snapshot of `LootCouncil.lua`; earlier tasks in this same plan shrink the file, shifting every line number after the cut. Locate code by the function-name/section-comment anchors given, not by trusting a stale line number.
- **Grep sweep scope is addon-wide, every task.** A function relocating in task N may be called from files created in *earlier* tasks (already-extracted modules) as well as `Core.lua`, `Droptimizer.lua`, `MainFrame.lua`, and whatever remains of `LootCouncil.lua` itself. Search all of them, every time — do not assume a caller "hasn't been touched yet so it's not my problem."
- **New-file skeleton**, every new file, matching `Identity.lua`:
  ```lua
  local addonName, KART = ...

  KART.LC.Vote = KART.LC.Vote or {}
  local Vote = KART.LC.Vote
  ```
  (substitute the module name/namespace as appropriate; `LootHistory.lua` already has this skeleton with `KART.LH`/`LH`, nothing to add there).
- **New files require a full WoW client restart to load** (`/reload` only re-executes already-loaded files) — established project fact. Tasks that create a new file call for a restart in their manual-verification step; tasks that only edit existing files just need `/reload`.
- **Final confirmation happens in the raid-test session already planned for the bugfix pass** (see `[[kart-loot-council-plans-status]]`) — this plan's own manual-verification steps are solo smoke tests (`LC.StartTest`), not a substitute for that.

---

### Task 1: Promote nine shared local helpers to flat `LC.*`

**Files:**
- Modify: `LootCouncil.lua` (in place — no new file, no `.toc` change)

**Interfaces:**
- Produces: `LC.IsTestRoll(rollID)`, `LC.GetVoteIconTexture(index)`, `LC.SetClassIconTexture(tex, classFile)`, `LC.IsCouncil()`, `LC.IsSenderCouncil(senderKey)`, `LC.GetChannel()`, `LC.SendLC(msg)`, `LC.IsRealItemLink(link)`, `LC.ParseItemColor(link)` — every later task (2-6) consumes these instead of the bare local names.

**Root cause:** these nine are declared `local function Foo(...)` today, which is file-scoped in Lua — invisible outside `LootCouncil.lua`. Once split, `LootCouncilVote.lua` still needs `SendLC`/`GetVoteIconTexture`/`IsTestRoll`; `LootCouncilTrade.lua` still needs `SendLC`/`IsTestRoll`/`IsRealItemLink`; `LootCouncilPanel.lua` needs nearly all nine. Duplicating each into every file that needs it (the way `Identity.lua`'s comment explains it deliberately duplicated the narrow, 1-caller `EachGroupUnit`) doesn't fit here — these are used from essentially every section. Promoting once, before the split, is simpler and keeps a single definition.

- [ ] **Step 1: Change the nine def lines**

In `LootCouncil.lua`, locate and change each of these (all found by searching for the exact `local function` signature — none of these names appear more than once as a definition):

```lua
-- before                                          -- after
local function IsTestRoll(rollID)                  function LC.IsTestRoll(rollID)
local function GetVoteIconTexture(index)           function LC.GetVoteIconTexture(index)
local function SetClassIconTexture(tex, classFile) function LC.SetClassIconTexture(tex, classFile)
local function IsCouncil()                         function LC.IsCouncil()
local function IsSenderCouncil(senderKey)           function LC.IsSenderCouncil(senderKey)
local function GetChannel()                        function LC.GetChannel()
local function SendLC(msg)                         function LC.SendLC(msg)
local function IsRealItemLink(link)                function LC.IsRealItemLink(link)
local function ParseItemColor(link)                function LC.ParseItemColor(link)
```

Only the `local function Foo` → `function LC.Foo` prefix changes on each def line — function bodies are untouched. Note `SendLC`'s body calls `GetChannel()` internally — that internal call also needs the `LC.` prefix (see Step 2, it's covered by the same sweep).

- [ ] **Step 2: Sweep every call site and add the `LC.` prefix**

For each of the nine names, search `LootCouncil.lua` for bare calls (the name followed directly by `(`, NOT already preceded by `LC.`) and prefix each with `LC.`. Use the Grep tool with a pattern like this per name, e.g. for `IsTestRoll`:

```
pattern: (?<!LC\.)\bIsTestRoll\(
```

(Ripgrep in this environment rejects lookbehind — instead search `\bIsTestRoll\(` with output_mode content and line numbers, then visually confirm which hits already have `LC.` immediately before them and skip those; only the definition line itself and genuinely bare calls need changing.)

Repeat for `GetVoteIconTexture(`, `SetClassIconTexture(`, `IsCouncil(`, `IsSenderCouncil(`, `GetChannel(`, `SendLC(`, `IsRealItemLink(`, `ParseItemColor(`.

Known call sites from initial exploration (re-verify — this list may be incomplete, the grep sweep is the source of truth, not this list):
- `IsTestRoll`: inside vote-row rendering (compact + spacious), `RefreshCouncilRows`, `AnnounceResult`, `DoAssignWinner`, `AddPendingTrade`, `ToggleCouncilVote`, `HandleActive`/session-active detection, `StartTest`.
- `SendLC`: `BroadcastRaidConfig`, `HandleActive`(session broadcast)/`SetSessionActive`, `CheckRaidJoin`, `OnStartLootRoll` (roll cast + start broadcast), both vote-cast blocks, `AnnounceResult`, `RequestHistorySync`, `ToggleCouncilVote`, `SetOfficerNote`.
- `GetChannel`: only inside `SendLC`'s own body.
- `IsCouncil`: `HandleActive`, session-prompt logic.
- `IsSenderCouncil`: `HandleOfficerNote`, `HandleResult`.
- `GetVoteIconTexture`/`SetClassIconTexture`: vote-row rendering (compact + spacious) and council-row rendering.
- `IsRealItemLink`/`ParseItemColor`: `ResolveRollItemLink`, both vote-row renderers, `GetItemArmorRank`, council tab/row rendering, `GetItemString`.

- [ ] **Step 3: Verify zero bare references remain**

Run each of the nine grep searches again. Every remaining match must be either the new `function LC.Foo(...)` def line itself, or a call already written as `LC.Foo(...)`. Zero bare (unprefixed) matches should remain.

- [ ] **Step 4: Manual verification**

`/reload` (no new file, no `.toc` change). `/console scriptErrors 1` beforehand. Confirm no Lua error on load. Open Settings → Loot Council tab, click "Test Looter" — vote list should populate with icons exactly as before. Click "Test Master" — council panel should populate with rows exactly as before.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "refactor: promote shared local helpers to KART.LC before module split"
```

---

### Task 2: Extract `LootCouncilOfficerNotes.lua`

**Files:**
- Create: `LootCouncilOfficerNotes.lua`
- Modify: `KeineAhnungRaidTools.toc` (add the new file, right after `LootCouncil.lua`)
- Modify: `Core.lua` (`LC_ONOTE` dispatch arm)
- Modify: `LootCouncil.lua` (remove the moved code)

**Interfaces:**
- Produces: `OfficerNotes.SetOfficerNote(playerKey, noteText)`, `OfficerNotes.HandleOfficerNote(payload, senderKey)`, `OfficerNotes.MigrateOfficerNoteKey(oldKey)`, `OfficerNotes.ShowOfficerNoteDialog(playerKey, playerDisplayName)`.
- Consumes: `LC.SendLC`, `LC.IsSenderCouncil` (Task 1). Calls `LC.RefreshCouncilRows()` (still valid as-is — that function hasn't moved yet, stays in `LootCouncil.lua` until Task 6; do **not** change this call in this task).

**What moves** (currently the "Officer Notes" section, `LootCouncil.lua` — locate by the `-- Officer Notes (persistent, per-player — not tied to any one item/roll)` section-header comment): `LC.SetOfficerNote`, `LC.HandleOfficerNote`, `LC.MigrateOfficerNoteKey`, `LC.ShowOfficerNoteDialog`, and their section-header comment block. Stops right before `LC.ShowAssignMenu` (that function stays behind for now — it's Council-module content, moves in Task 6).

- [ ] **Step 1: Create `LootCouncilOfficerNotes.lua`**

```lua
local addonName, KART = ...

KART.LC.OfficerNotes = KART.LC.OfficerNotes or {}
local OfficerNotes = KART.LC.OfficerNotes
```

Then cut the four functions (with their section-header comment) verbatim out of `LootCouncil.lua` and paste below this skeleton, renaming only the four def lines:

```lua
-- before                                  -- after
function LC.SetOfficerNote(...)            function OfficerNotes.SetOfficerNote(...)
function LC.HandleOfficerNote(...)         function OfficerNotes.HandleOfficerNote(...)
function LC.MigrateOfficerNoteKey(...)     function OfficerNotes.MigrateOfficerNoteKey(...)
function LC.ShowOfficerNoteDialog(...)     function OfficerNotes.ShowOfficerNoteDialog(...)
```

Inside these bodies, any bare call to one of Task 1's promoted helpers (`LC.SendLC`, `LC.IsSenderCouncil`) is already correctly qualified from Task 1 — no change needed. Any call to `LC.RefreshCouncilRows` is left exactly as-is (see Interfaces above).

- [ ] **Step 2: Add to the `.toc`**

In `KeineAhnungRaidTools.toc`, change:

```
LootCouncil.lua
Droptimizer.lua
```

to:

```
LootCouncil.lua
LootCouncilOfficerNotes.lua
Droptimizer.lua
```

- [ ] **Step 3: Update `Core.lua`'s dispatch**

```lua
-- before
                elseif msg:sub(1, 9) == "LC_ONOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleOfficerNote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end

-- after
                elseif msg:sub(1, 9) == "LC_ONOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.OfficerNotes.HandleOfficerNote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end
```

- [ ] **Step 4: Sweep for any other caller of the four moved functions**

Search the whole addon (`*.lua`) for `LC.SetOfficerNote(`, `LC.HandleOfficerNote(`, `LC.MigrateOfficerNoteKey(`, `LC.ShowOfficerNoteDialog(`. `ShowOfficerNoteDialog` is expected to have a caller inside `LootCouncil.lua`'s still-unmoved `ShowAssignMenu` (Council-module content, Task 6) — that call becomes `KART.LC.OfficerNotes.ShowOfficerNoteDialog(...)` now, even though `ShowAssignMenu` itself doesn't move until Task 6. Fix every match found; zero bare matches should remain afterward (except the new def lines).

- [ ] **Step 5: Manual verification**

Full WoW client restart (new file added to `.toc`). `/console scriptErrors 1`. Confirm no Lua error on load. Via the "Test Master" council panel, right-click a test roll's row → assign menu → "Edit Note", set a note, confirm it saves and the note indicator dot appears on the row (this exercises `ShowOfficerNoteDialog` → `SetOfficerNote` → `RefreshCouncilRows`, i.e. confirms the deliberately-left `LC.RefreshCouncilRows()` call still resolves correctly since it hasn't moved yet).

- [ ] **Step 6: Commit**

```bash
git add LootCouncilOfficerNotes.lua LootCouncil.lua KeineAhnungRaidTools.toc Core.lua
git commit -m "refactor: extract officer notes into LootCouncilOfficerNotes.lua (KART.LC.OfficerNotes)"
```

---

### Task 3: Move loot-history write/sync path into `LootHistory.lua`

**Files:**
- Modify: `LootHistory.lua` (add four functions)
- Modify: `Core.lua` (`LC_HIST_REQ`/`LC_HIST_ENTRY` dispatch arms)
- Modify: `LootCouncil.lua` (remove the moved code; fix the two internal callers)

**Interfaces:**
- Produces: `LH.LogHistory(itemLink, winnerDisplayName, reason, classFile, colorDef, rollID)`, `LH.RequestHistorySync()`, `LH.HandleHistoryRequest(payload, senderFullName)`, `LH.HandleHistoryEntry(payload)`.
- Consumes: nothing from `KART.LC` — verified by reading all four function bodies during design: they only touch the `KART_LootHistory` saved variable and `KART.LH.historyWindow`/`KART.LH.Refresh()` (already same-file once moved).

**What moves** (currently the "Loot History" and "Loot History catch-up sync" sections in `LootCouncil.lua`, back-to-back): `LC.LogHistory`, the `MAX_HISTORY_ENTRIES` local constant, `LC.RequestHistorySync`, `LC.HandleHistoryRequest`, `LC.HandleHistoryEntry`, and the `HISTORY_SYNC_MAX_ENTRIES`/`HISTORY_SYNC_MAX_AGE` local constants. No `.toc` change needed — `LootHistory.lua` is already loaded.

- [ ] **Step 1: Append to `LootHistory.lua`**

Cut the two sections (both section-header comments, the three local constants, and the four functions) verbatim from `LootCouncil.lua`, paste at the end of `LootHistory.lua`, renaming only the four def lines:

```lua
-- before                              -- after
function LC.LogHistory(...)            function LH.LogHistory(...)
function LC.RequestHistorySync()       function LH.RequestHistorySync()
function LC.HandleHistoryRequest(...)  function LH.HandleHistoryRequest(...)
function LC.HandleHistoryEntry(...)    function LH.HandleHistoryEntry(...)
```

The three local constants (`MAX_HISTORY_ENTRIES`, `HISTORY_SYNC_MAX_ENTRIES`, `HISTORY_SYNC_MAX_AGE`) move as plain `local` declarations — `LootHistory.lua` doesn't currently declare anything with these names (confirm with a quick grep before pasting, to rule out a name collision with existing file-local constants).

- [ ] **Step 2: Update `Core.lua`'s dispatch**

```lua
-- before
                elseif msg:sub(1, 12) == "LC_HIST_REQ:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleHistoryRequest(msg:sub(13), sender) end
                elseif msg:sub(1, 14) == "LC_HIST_ENTRY:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleHistoryEntry(msg:sub(15)) end

-- after
                elseif msg:sub(1, 12) == "LC_HIST_REQ:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LH.HandleHistoryRequest(msg:sub(13), sender) end
                elseif msg:sub(1, 14) == "LC_HIST_ENTRY:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LH.HandleHistoryEntry(msg:sub(15)) end
```

(Guard condition stays `KART.LC and ...` — that condition is gating on the loot-council module being enabled at all, not on which file defines the handler.)

- [ ] **Step 3: Fix the two internal callers left behind in `LootCouncil.lua`**

`LC.CheckRaidJoin` calls `LC.RequestHistorySync()` — change to `KART.LH.RequestHistorySync()`.

`DoAssignWinner` (still in `LootCouncil.lua`'s Trade Reminder section, not yet extracted — that's Task 5) calls `LC.LogHistory(...)` in two places (once inside the normal assign path, once inside `LC.HandleResult`) — change both to `KART.LH.LogHistory(...)`.

- [ ] **Step 4: Sweep for any other caller**

Search the whole addon for `LC.LogHistory(`, `LC.RequestHistorySync(`, `LC.HandleHistoryRequest(`, `LC.HandleHistoryEntry(`. Zero bare matches should remain (besides the definitions, now in `LootHistory.lua`).

- [ ] **Step 5: Manual verification**

No new file, so `/reload` is sufficient. `/console scriptErrors 1`. Confirm no Lua error. Assign a test-roll item via "Test Master" → right-click → assign — open the Loot History window (Settings tab → History button) and confirm the test assignment appears (exercises `LH.LogHistory` from the still-in-`LootCouncil.lua` `DoAssignWinner`).

- [ ] **Step 6: Commit**

```bash
git add LootHistory.lua LootCouncil.lua Core.lua
git commit -m "refactor: move loot-history write/sync path into LootHistory.lua (KART.LH)"
```

---

### Task 4: Extract `LootCouncilVote.lua`

**Files:**
- Create: `LootCouncilVote.lua`
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `Core.lua` (`LC_VOTE`/`LC_ROLL`/`LC_CVOTE` dispatch arms)
- Modify: `LootCouncil.lua` (remove the moved code; fix internal callers)

**Interfaces:**
- Produces: `Vote.CreateVoteList()`, `Vote.ShowVotePopup(rollID, itemLink, seconds)`, `Vote.RemoveVoteListItem(rollID)`, `Vote.RefreshVoteListRows()`, `Vote.RefreshVoteListRowsIfShown()`, `Vote.RefreshVoteListRows_Spacious(f)`, `Vote.RefreshVoteListRows_Compact(f)`, `Vote.SetPlayerVote(rollID, playerKey, buttonIdx)`, `Vote.ToggleCouncilVote(rollID, candidateKey)`, `Vote.HandleVote(payload, senderKey)`, `Vote.HandleRoll(payload, senderKey)`, `Vote.HandleCouncilVote(payload, senderKey)`.
- Consumes: `LC.SendLC`, `LC.IsTestRoll`, `LC.GetVoteIconTexture`, `LC.IsRealItemLink`, `LC.ParseItemColor` (Task 1); `LC.CountVotes` (stays core, unchanged). Calls `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()` (Council — still valid as-is, Council moves in Task 6, do not change these calls now).

**What moves:** the entire "Vote List" section (`LC.votedByMe`/`LC.votedNoteByMe` state-table declarations stay behind — see note below — but `CreateVoteList` through `RefreshVoteListRows_Compact` move), plus `LC.SetPlayerVote` and `LC.ToggleCouncilVote` (currently located later in the file, just before the "Officer Notes" section that Task 2 already relocated), plus `LC.HandleVote`/`LC.HandleRoll`/`LC.HandleCouncilVote` (currently in the "Addon Message Handlers" section).

Note: `LC.votedByMe`/`LC.votedNoteByMe` are per-roll runtime state, same category as `LC.votes`/`LC.rolls` — per the design's Non-goals, state stays flat on `KART.LC`. Leave their declarations in `LootCouncil.lua`; only the functions move.

- [ ] **Step 1: Create `LootCouncilVote.lua`**

```lua
local addonName, KART = ...

KART.LC.Vote = KART.LC.Vote or {}
local Vote = KART.LC.Vote
```

Cut the functions listed above verbatim, paste below, renaming only the def lines (`LC.CreateVoteList` → `Vote.CreateVoteList`, etc. — mechanical 1:1 for every name in "Produces" above).

- [ ] **Step 2: Add to the `.toc`**

```
LootCouncil.lua
LootCouncilOfficerNotes.lua
LootCouncilVote.lua
Droptimizer.lua
```

- [ ] **Step 3: Update `Core.lua`'s dispatch**

```lua
-- before
                elseif msg:sub(1, 8) == "LC_VOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleVote(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 8) == "LC_ROLL:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleRoll(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 9) == "LC_CVOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleCouncilVote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end

-- after
                elseif msg:sub(1, 8) == "LC_VOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.Vote.HandleVote(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 8) == "LC_ROLL:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.Vote.HandleRoll(msg:sub(9), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 9) == "LC_CVOTE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.Vote.HandleCouncilVote(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end
```

- [ ] **Step 4: Sweep for other callers of every moved function**

Search the whole addon for each: `LC.CreateVoteList(`, `LC.ShowVotePopup(`, `LC.RemoveVoteListItem(`, `LC.RefreshVoteListRows(` (careful: this is a substring of `LC.RefreshVoteListRowsIfShown(` and `LC.RefreshVoteListRows_Spacious(`/`_Compact(` — search each full name separately), `LC.RefreshVoteListRowsIfShown(`, `LC.RefreshVoteListRows_Spacious(`, `LC.RefreshVoteListRows_Compact(`, `LC.SetPlayerVote(`, `LC.ToggleCouncilVote(`, `LC.HandleVote(`, `LC.HandleRoll(`, `LC.HandleCouncilVote(`.

Expected remaining callers to fix (in `LootCouncil.lua`'s still-unmoved core code): `LC.OnStartLootRoll` calls `LC.RefreshVoteListRows()` and `LC.ShowVotePopup(...)`; `CheckRaidJoin` calls `LC.RefreshVoteListRows()`. `LC.ShowAssignMenu` (unmoved, Task 6) calls `LC.SetPlayerVote(...)` and `LC.ToggleCouncilVote(...)` is called from `RefreshCouncilRows` (unmoved, Task 6) — fix these call sites now even though their *callers* haven't moved yet. Every one of these becomes `KART.LC.Vote.Foo(...)` (or `LC.Vote.Foo(...)`, same table, either spelling works since `local LC = KART.LC` already exists at the top of `LootCouncil.lua` — prefer `LC.Vote.Foo` for consistency with the rest of that file).

- [ ] **Step 5: Manual verification**

Full client restart (new file). `/console scriptErrors 1`. Confirm no Lua error. "Test Looter" → vote list appears, cast a vote and a roll, confirm the vote registers (council panel isn't open in looter-only test mode, but no error should occur from the `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()` calls inside `SetPlayerVote`/`ToggleCouncilVote` when the panel doesn't exist yet — these already guard on `LC.councilPanel` existing, unchanged behavior). "Test Master" → cast council votes on test rows, confirm they tally.

- [ ] **Step 6: Commit**

```bash
git add LootCouncilVote.lua LootCouncil.lua KeineAhnungRaidTools.toc Core.lua
git commit -m "refactor: extract vote list and vote/roll handling into LootCouncilVote.lua (KART.LC.Vote)"
```

---

### Task 5: Extract `LootCouncilTrade.lua`

**Files:**
- Create: `LootCouncilTrade.lua`
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `Core.lua` (`TRADE_SHOW`/`TRADE_CLOSED` events, `LC_RESULT` dispatch arm)
- Modify: `LootCouncil.lua` (remove the moved code; fix internal callers)

**Interfaces:**
- Produces: `Trade.AssignWinner(rollID, playerKey, reason, colorDef)`, `Trade.ClearRollState(rollID)`, `Trade.AddPendingTrade(rollID, playerKey)`, `Trade.RemovePendingTrade(rollID)`, `Trade.CreateTradeReminderFrame()`, `Trade.RefreshTradeReminder()`, `Trade.OnTradeShow()`, `Trade.OnTradeClosed()`, `Trade.AnnounceResult(rollID, winnerKey, reason)`, `Trade.ShowWinnerNotification(itemLink)`, `Trade.ResolveColorForReason(reason)`, `Trade.HandleResult(payload, senderKey)`. (`DoAssignWinner` is a local helper, moves too, stays local to this file, not exported.)
- Consumes: `KART.LH.LogHistory`, `KART.LH.RequestHistorySync`(Task 3 — `AssignWinner`/`HandleResult` call `LogHistory`; nothing here calls `RequestHistorySync`, that's `CheckRaidJoin`'s job, stays core); `LC.SendLC`, `LC.IsTestRoll`, `LC.IsRealItemLink` (Task 1); `LC.IsMe`, `LC.GetLootmaster` (stay core, unchanged). Calls `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()` (Council — still valid as-is until Task 6, do not change these calls now).

**What moves:** `DoAssignWinner` (local) + `LC.AssignWinner`, `LC.ClearRollState`, `LC.CreateTradeReminderFrame`, `LC.RefreshTradeReminder`, `GetItemString`/`FindItemInBags` (locals, stay local to this file — only used within this section), `LC.OnTradeShow`, `LC.OnTradeClosed`, `LC.AddPendingTrade`, `LC.RemovePendingTrade` (the "Trade Reminder & Auto-Trade" section), plus `LC.AnnounceResult`/`LC.ShowWinnerNotification` (the "Result announcement" section, physically earlier in the file but same concern), plus `LC.ResolveColorForReason`/`LC.HandleResult` (from "Addon Message Handlers").

- [ ] **Step 1: Create `LootCouncilTrade.lua`**

```lua
local addonName, KART = ...

KART.LC.Trade = KART.LC.Trade or {}
local Trade = KART.LC.Trade
```

Cut the functions listed above verbatim, paste below, renaming the def lines:

```lua
-- before                              -- after
local function DoAssignWinner(...)     local function DoAssignWinner(...)   -- unchanged, stays local
function LC.AssignWinner(...)          function Trade.AssignWinner(...)
function LC.ClearRollState(...)        function Trade.ClearRollState(...)
function LC.CreateTradeReminderFrame() function Trade.CreateTradeReminderFrame()
function LC.RefreshTradeReminder()     function Trade.RefreshTradeReminder()
local function GetItemString(...)      local function GetItemString(...)    -- unchanged, stays local
local function FindItemInBags(...)     local function FindItemInBags(...)   -- unchanged, stays local
function LC.OnTradeShow()              function Trade.OnTradeShow()
function LC.OnTradeClosed()            function Trade.OnTradeClosed()
function LC.AddPendingTrade(...)       function Trade.AddPendingTrade(...)
function LC.RemovePendingTrade(...)    function Trade.RemovePendingTrade(...)
function LC.AnnounceResult(...)        function Trade.AnnounceResult(...)
function LC.ShowWinnerNotification(...) function Trade.ShowWinnerNotification(...)
function LC.ResolveColorForReason(...) function Trade.ResolveColorForReason(...)
function LC.HandleResult(...)          function Trade.HandleResult(...)
```

Inside these bodies: `LC.LogHistory(...)` (two call sites, inside `DoAssignWinner` and inside `HandleResult`) becomes `KART.LH.LogHistory(...)` — these were already fixed in Task 3 while the code still lived in `LootCouncil.lua`; confirm they moved over correctly rather than re-editing them now.

- [ ] **Step 2: Add to the `.toc`**

```
LootCouncil.lua
LootCouncilOfficerNotes.lua
LootCouncilVote.lua
LootCouncilTrade.lua
Droptimizer.lua
```

- [ ] **Step 3: Update `Core.lua`**

```lua
-- before
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.OnTradeClosed() end

-- after
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.Trade.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.Trade.OnTradeClosed() end
```

```lua
-- before
                elseif msg:sub(1, 10) == "LC_RESULT:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleResult(msg:sub(11), (KART.Identity.ResolvePlayer(sender))) end

-- after
                elseif msg:sub(1, 10) == "LC_RESULT:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.Trade.HandleResult(msg:sub(11), (KART.Identity.ResolvePlayer(sender))) end
```

- [ ] **Step 4: Sweep for other callers**

Search the whole addon for: `LC.AssignWinner(`, `LC.ClearRollState(`, `LC.AddPendingTrade(`, `LC.RemovePendingTrade(`, `LC.AnnounceResult(`, `LC.ShowWinnerNotification(`, `LC.ResolveColorForReason(`, `LC.HandleResult(`, `LC.OnTradeShow(`, `LC.OnTradeClosed(`, `LC.CreateTradeReminderFrame(`, `LC.RefreshTradeReminder(`.

Expected remaining callers to fix, all in `LootCouncil.lua`'s still-unmoved core code or unmoved `ShowAssignMenu`/`RefreshCouncilRows`/`CloseCouncilTab` (Council, Task 6 — fix the call sites now regardless): `CheckRaidJoin` calls `LC.ClearRollState(...)` twice; `ShowAssignMenu` calls `LC.AssignWinner(...)` twice; `CloseCouncilTab` calls `LC.ClearRollState(...)`; `CreateCouncilPanel`'s minimize-all handling calls `LC.AnnounceResult(...)`.

- [ ] **Step 5: Manual verification**

Full client restart (new file). `/console scriptErrors 1`. Confirm no Lua error. "Test Master" → right-click a row → Assign — confirm the winner notification popup appears and (since it's a test roll) no real trade-reminder/announce fires. Confirm no error from the trade-reminder frame code paths (it's fine that no real trade happens in test mode — `IsTestRoll` gates that, unchanged).

- [ ] **Step 6: Commit**

```bash
git add LootCouncilTrade.lua LootCouncil.lua KeineAhnungRaidTools.toc Core.lua
git commit -m "refactor: extract winner assignment and trade reminder into LootCouncilTrade.lua (KART.LC.Trade)"
```

---

### Task 6: Extract `LootCouncilPanel.lua`

**Files:**
- Create: `LootCouncilPanel.lua`
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `Core.lua` (the `PLAYER_ENTERING_WORLD`/version-check `RefreshCouncilRows` call, `LC.councilPanel`-adjacent code is state access and stays untouched)
- Modify: `Droptimizer.lua` (`RefreshCouncilRows` call)
- Modify: every previously-created file (`LootCouncil.lua`, `LootCouncilOfficerNotes.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua`) — fix internal callers of the now-moved functions

**Interfaces:**
- Produces: `Council.GetEquippedForUnit(unit, rollItemLink)`, `Council.GetItemArmorRank(itemLink)`, `Council.IsArmorEligible(classFile, itemRank)`, `Council.ShowCouncilPanel(rollID, seconds)`, `Council.SwitchCouncilTab(rollID)`, `Council.CloseCouncilTab(rollID)`, `Council.RefreshCouncilTabs()`, `Council.CreateCouncilPanel()`, `Council.SetCouncilPanelMinimized(minimized)`, `Council.RefreshCouncilRows()`, `Council.ShowAssignMenu(anchor, rollID, playerKey, playerDisplayName, voteDef)`.
- Consumes: `KART.LC.Vote.ToggleCouncilVote`, `KART.LC.Vote.SetPlayerVote` (Task 4); `KART.LC.Trade.AssignWinner`, `KART.LC.Trade.AnnounceResult`, `KART.LC.Trade.ClearRollState` (Task 5); `KART.LC.OfficerNotes.ShowOfficerNoteDialog` (Task 2); `LC.SendLC`, `LC.IsTestRoll`, `LC.GetVoteIconTexture`, `LC.SetClassIconTexture`, `LC.IsRealItemLink`, `LC.ParseItemColor` (Task 1); `LC.CountVotes` (stays core).

**What moves:** the "Equipped-item helper" section, the "Armor-type eligibility" section, the entire "Council Panel" section (`ShowCouncilPanel` through `RefreshCouncilRows`), and `LC.ShowAssignMenu` (currently sitting just after where Task 2 removed Officer Notes). This is the largest single extraction (~1200 lines) — take it in the sub-steps below rather than one giant cut, to keep the diff reviewable.

- [ ] **Step 1: Create `LootCouncilPanel.lua`, move the two small helper sections**

```lua
local addonName, KART = ...

KART.LC.Council = KART.LC.Council or {}
local Council = KART.LC.Council
```

Cut "Equipped-item helper" (`LC.GetEquippedForUnit`) and "Armor-type eligibility" (`LC.GetItemArmorRank`, `LC.IsArmorEligible`) verbatim from `LootCouncil.lua`, paste below the skeleton, renaming the three def lines to `Council.GetEquippedForUnit`, `Council.GetItemArmorRank`, `Council.IsArmorEligible`.

- [ ] **Step 2: Move the tab-management functions**

Cut `LC.ShowCouncilPanel`, `LC.SwitchCouncilTab`, `LC.CloseCouncilTab`, `LC.RefreshCouncilTabs` verbatim, append to `LootCouncilPanel.lua`, renaming the four def lines to `Council.ShowCouncilPanel`/`Council.SwitchCouncilTab`/`Council.CloseCouncilTab`/`Council.RefreshCouncilTabs`. `CloseCouncilTab`'s body already calls `KART.LC.Trade.ClearRollState(...)` — Task 5 Step 4 already fixed this call site in place while it still lived in `LootCouncil.lua` — carry it over as-is, no further edit needed here.

- [ ] **Step 3: Move panel creation**

Cut `LC.CreateCouncilPanel` and `LC.SetCouncilPanelMinimized` verbatim, append, renaming to `Council.CreateCouncilPanel`/`Council.SetCouncilPanelMinimized`. `CreateCouncilPanel`'s body (the "minimize all, force-close with NONE reason" path) already calls `KART.LC.Trade.AnnounceResult(...)` — fixed in place by Task 5 Step 4 — carry over as-is.

- [ ] **Step 4: Move `RefreshCouncilRows`**

Cut `LC.RefreshCouncilRows` (the largest single function in the file, ~530 lines) verbatim, append, renaming to `Council.RefreshCouncilRows`. Its body already calls `KART.LC.Vote.ToggleCouncilVote(...)` — fixed in place by Task 4 Step 4 — carry over as-is. Its `LC.ShowAssignMenu(...)` call is a same-file call once `ShowAssignMenu` also lands here in Step 5; optionally tighten it to `Council.ShowAssignMenu(...)` for in-file consistency (matching how `Identity.lua` calls its own `ResolvePlayer`/`FindUnitForKey` without the `KART.` prefix internally) — either spelling resolves to the same table, so this is a style nicety, not a correctness requirement.

- [ ] **Step 5: Move `ShowAssignMenu`**

Cut `LC.ShowAssignMenu` verbatim from wherever it currently sits in `LootCouncil.lua` (right after where Task 2 removed the Officer Notes section), append, renaming to `Council.ShowAssignMenu`. Its body already calls `KART.LC.Trade.AssignWinner(...)` (two call sites, fixed by Task 5 Step 4) and `KART.LC.Vote.SetPlayerVote(...)` (fixed by Task 4 Step 4) — carry both over as-is, no further edit needed here.

- [ ] **Step 6: Add to the `.toc`**

```
LootCouncil.lua
LootCouncilOfficerNotes.lua
LootCouncilVote.lua
LootCouncilTrade.lua
LootCouncilPanel.lua
Droptimizer.lua
```

- [ ] **Step 7: Update `Core.lua` and `Droptimizer.lua`**

```lua
-- Core.lua, before
                    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                        KART.LC.RefreshCouncilRows()
                    end

-- after
                    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                        KART.LC.Council.RefreshCouncilRows()
                    end
```

```lua
-- Droptimizer.lua, before
            if KART.LC and KART.LC.RefreshCouncilRows then KART.LC.RefreshCouncilRows() end

-- after
            if KART.LC and KART.LC.Council and KART.LC.Council.RefreshCouncilRows then KART.LC.Council.RefreshCouncilRows() end
```

(The extra `KART.LC.Council and` guard mirrors the existing defensive style at this call site — `KART.LC.RefreshCouncilRows` used to double as both "does the module exist" and "does the function exist" checks; now that it's one level deeper, both levels get guarded the same way.)

- [ ] **Step 8: Sweep the entire addon for every remaining bare reference**

Search all `*.lua` files for each: `LC.GetEquippedForUnit(`, `LC.GetItemArmorRank(`, `LC.IsArmorEligible(`, `LC.ShowCouncilPanel(`, `LC.SwitchCouncilTab(`, `LC.CloseCouncilTab(`, `LC.RefreshCouncilTabs(`, `LC.CreateCouncilPanel(`, `LC.SetCouncilPanelMinimized(`, `LC.RefreshCouncilRows(`, `LC.ShowAssignMenu(`.

Expected remaining callers to fix, in `LootCouncil.lua`'s remaining core code: `LC.OnStartLootRoll` calls `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()`; `CheckRaidJoin` calls the same two. Also check `LootCouncilVote.lua` (Task 4's `RefreshVoteListRows_Spacious`/`_Compact` call `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()`) and `LootCouncilTrade.lua` (Task 5's `AnnounceResult`/`HandleResult` call `LC.RefreshCouncilRows()`/`LC.RefreshCouncilTabs()`) and `LootCouncilOfficerNotes.lua` (Task 2's `SetOfficerNote`/`HandleOfficerNote` call `LC.RefreshCouncilRows()`). All become `KART.LC.Council.Foo(...)`. Zero bare matches should remain anywhere afterward.

- [ ] **Step 9: Manual verification**

Full client restart (new file). `/console scriptErrors 1`. Confirm no Lua error. Run through the full flow once solo: "Test Master" → council panel opens with tabs for all four test items → cast votes/rolls → right-click a row → assign → confirm winner notification, note-taking, and tab close all work with no errors. This exercises every cross-module edge fixed in this task.

- [ ] **Step 10: Commit**

```bash
git add LootCouncilPanel.lua LootCouncil.lua LootCouncilOfficerNotes.lua LootCouncilVote.lua LootCouncilTrade.lua KeineAhnungRaidTools.toc Core.lua Droptimizer.lua
git commit -m "refactor: extract council panel UI into LootCouncilPanel.lua (KART.LC.Council)"
```

---

### Task 7: Final addon-wide audit

**Files:** none modified — this is a verification-only task, unless it finds something to fix.

- [ ] **Step 1: Full addon-wide grep for every relocated function's old bare name**

Every function name listed in the "Produces" line of Tasks 2-6 (37 functions total across `Vote`/`Council`/`Trade`/`OfficerNotes`/`LH`), searched as `LC.<Name>(` across every `*.lua` file in the addon. Confirm the only matches are: (a) already-correct `KART.LC.<Module>.<Name>(` or `<Module>.<Name>(` calls, or (b) the four/eleven/twelve/four def lines themselves in their new homes. Zero remaining bare `LC.<Name>(` matches.

- [ ] **Step 2: Confirm `LootCouncil.lua`'s remaining size**

`wc -l LootCouncil.lua` (or equivalent) — should now hold only: state-table declarations, the nine Task-1 helpers, the Helpers/Session-Prompt/START_LOOT_ROLL-handler/Settings-Panel/Test-Function sections, and the still-core message handlers (`HandleActive`, `HandleStart`, `HandleConfig`, `HandleSyncRequest`/`Accept`/`Decline`, `HandleStateRequest`). Expect roughly 1400-1600 lines remaining (down from 3914) — a rough sanity check, not an exact target.

- [ ] **Step 3: Full solo smoke test**

Full client restart. `/console scriptErrors 1`. Run "Test Looter" and "Test Master" in the same session (as the existing dev harness supports — one window shouldn't wipe the other's data, per `LC.StartTest`'s existing suppress-reset behavior). Cast votes, rolls, council votes; assign a winner; set an officer note; let a vote's countdown expire once to confirm auto-pass/timeout handling still works. No Lua errors anywhere in the flow.

- [ ] **Step 4: Note completion, defer to raid test**

This plan's scope ends here. Real confirmation happens in the live-raid test already planned for the bugfix pass (see project memory `[[kart-loot-council-plans-status]]`) — no separate raid-test cycle needed for this refactor specifically, per the design doc's Testing section.

- [ ] **Step 5: Commit (only if Step 1 or 2 found something to fix)**

```bash
git add -A
git commit -m "refactor: fix remaining stale references found in final module-split audit"
```
