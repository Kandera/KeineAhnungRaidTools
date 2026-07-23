# LootCouncil.lua Module Split — Design

Date: 2026-07-23
Status: approved (pre-implementation; done ahead of `docs/superpowers/plans/2026-07-22-loot-council-features.md`, which is otherwise blocked on the raid test of the bugfix pass — this is prep work while that test is pending, not part of the feature plan itself)

## Goal

`LootCouncil.lua` has grown to 3914 lines / 191KB, by far the largest file in the addon (next biggest is `MainFrame.lua` at 36KB). It already contains 14 clearly comment-delimited sections, but everything lives flat under `KART.LC` in one file. This design splits it into multiple files along those existing section boundaries, grouping related functions under sub-namespaces, done now — before the 12-task feature plan adds another round of code to the same file.

Pure structural refactor: **no behavior change, no new features, no wire-protocol change.** Every moved function keeps its exact body; only its file location and, for most, its namespace prefix change.

## Non-goals

- **No change to shared runtime state.** Every mutable state table currently on `KART.LC` (`LC.votes`, `LC.rolls`, `LC.councilVotes`, `LC.rollItems`, `LC.pendingTrades`, `LC.raidConfig`, `LC.sessionActive`, `LC.councilTabs`, `LC.voteListRolls`, `LC.assignedWinners`, etc.) and every UI-frame/widget field (`LC.councilPanel`, `LC.voteListFrame`, `LC.tradeReminderFrame`, `LC.RaidBox`, all Settings-panel widget fields) stays flat on `KART.LC`, not moved into a sub-namespace. `Core.lua`, `MainFrame.lua`, and `Droptimizer.lua` already read/write these directly today (e.g. `KART.LC.councilTabs`, `KART.LC.RaidBox`); sub-namespacing them would multiply the external call-site changes for no benefit, since these are data/widgets, not the thing this split is trying to organize.
- **No merge of the Loot-History write/sync path into anything new** — it moves into the existing `LootHistory.lua` (`KART.LH`), not a new file. See "History" below.
- **No renaming of functions themselves**, only their namespace prefix (e.g. `LC.HandleVote` becomes `LC.Vote.HandleVote`, body untouched).
- **No TOC load-order dependency introduced.** No split file calls into another module at file-load time (top level) — only inside function bodies, which run later at gameplay time after all files are loaded. The only top-level code in each file is the standard idempotent guard (`KART.LC.Vote = KART.LC.Vote or {}`), matching the existing `Identity.lua` pattern.

## Architecture

Six files total — one existing file extended, four new files, and the original file slimmed down but keeping its name and its role as the shared/core file.

| File | Namespace | Contents |
|---|---|---|
| `LootCouncil.lua` (slimmed) | `KART.LC` (flat) | All shared state tables; Helpers section (raid config, council-membership cache, channel/send, lootmaster, settings-sync dialogs); Session Prompt; `START_LOOT_ROLL` handler; Settings Panel; dev Test Function; `HandleActive`/`HandleStart`/`HandleConfig`/`HandleSyncRequest`/`HandleSyncAccept`/`HandleSyncDecline`/`HandleStateRequest` |
| `LootCouncilVote.lua` (new) | `KART.LC.Vote` | Vote List UI (`CreateVoteList`, `ShowVotePopup`, `RemoveVoteListItem`, `RefreshVoteListRows` + Spacious/Compact variants), `SetPlayerVote`, `ToggleCouncilVote`, `HandleVote`, `HandleRoll`, `HandleCouncilVote` |
| `LootCouncilPanel.lua` (new) | `KART.LC.Council` | Equipped-item helper, armor-eligibility helper, Council Panel UI (`ShowCouncilPanel`, `SwitchCouncilTab`, `CloseCouncilTab`, `RefreshCouncilTabs`, `CreateCouncilPanel`, `SetCouncilPanelMinimized`, `RefreshCouncilRows`), `ShowAssignMenu` |
| `LootCouncilTrade.lua` (new) | `KART.LC.Trade` | `AssignWinner`/`DoAssignWinner`, `ClearRollState`, `AddPendingTrade`/`RemovePendingTrade`, Trade Reminder & Auto-Trade section, `AnnounceResult`, `ShowWinnerNotification`, `ResolveColorForReason`, `HandleResult` |
| `LootCouncilOfficerNotes.lua` (new) | `KART.LC.OfficerNotes` | `SetOfficerNote`, `HandleOfficerNote`, `MigrateOfficerNoteKey`, `ShowOfficerNoteDialog` |
| `LootHistory.lua` (existing, extended) | `KART.LH` | + `LogHistory`, `RequestHistorySync`, `HandleHistoryRequest`, `HandleHistoryEntry` (moved in from `LootCouncil.lua`) |

Each new file follows the exact pattern already established by `Identity.lua`:

```lua
local addonName, KART = ...
KART.LC.Vote = KART.LC.Vote or {}
local Vote = KART.LC.Vote
```

### Why History moves into `LootHistory.lua` rather than a new `LootCouncil.lua`-family file

The "Loot History" and "Loot History catch-up sync" sections (`LogHistory`, `RequestHistorySync`, `HandleHistoryRequest`, `HandleHistoryEntry`) were checked line-by-line: none of them read or write any `LC.*` state — they only touch `KART_LootHistory` (the saved variable) and call `KART.LH.Refresh()`/check `KART.LH.historyWindow`. They already reach *out* to `KART.LH` today. Moving them there removes a forward-reference instead of creating one, and puts the entire "loot history" concern (write path + display/export) in one file.

## External call-site updates required

Every place outside `LootCouncil.lua` that calls a function being relocated to a sub-namespace must update to the new path. Full sweep of the addon found these (state/widget-field reads like `KART.LC.councilTabs` are untouched per Non-goals above):

**`Core.lua`:**
```lua
-- before                                         -- after
KART.LC.HandleVote(...)                           KART.LC.Vote.HandleVote(...)
KART.LC.HandleRoll(...)                           KART.LC.Vote.HandleRoll(...)
KART.LC.HandleCouncilVote(...)                    KART.LC.Vote.HandleCouncilVote(...)
KART.LC.HandleOfficerNote(...)                    KART.LC.OfficerNotes.HandleOfficerNote(...)
KART.LC.HandleResult(...)                         KART.LC.Trade.HandleResult(...)
KART.LC.HandleHistoryRequest(...)                 KART.LH.HandleHistoryRequest(...)
KART.LC.HandleHistoryEntry(...)                   KART.LH.HandleHistoryEntry(...)
KART.LC.OnTradeShow()                              KART.LC.Trade.OnTradeShow()
KART.LC.OnTradeClosed()                            KART.LC.Trade.OnTradeClosed()
KART.LC.RefreshCouncilRows()                       KART.LC.Council.RefreshCouncilRows()
```

**`Droptimizer.lua`:**
```lua
KART.LC.RefreshCouncilRows()                       KART.LC.Council.RefreshCouncilRows()
```

Everything else `Core.lua`/`MainFrame.lua`/`Droptimizer.lua` reference (`HandleActive`, `HandleStart`, `HandleConfig`, `HandleSyncRequest/Accept/Decline`, `HandleStateRequest`, `OnStartLootRoll`, `CheckRaidJoin`, `UpdateCouncilCache`, `UpdateRoleStatusLabel`, `RetryPendingResolutionsThrottled`, `QualityLabel`, `RelayoutRaidBox`, `RaidBox`, all Settings-panel widget fields, all state-table fields) stays on flat `KART.LC` and needs no change, since the file that owns them keeps the `LootCouncil.lua`/`LootCouncil` name.

## Internal call-site updates required

Within the split-out code itself, any call from one relocated function into another now-relocated function (in a different file) must become fully-qualified. Known cases found during exploration:

- `LC.Trade.AssignWinner` / `LC.Trade.HandleResult` call what is now `KART.LH.LogHistory` (was `LC.LogHistory`).
- `LC.CheckRaidJoin` (stays core) calls what is now `KART.LH.RequestHistorySync` (was `LC.RequestHistorySync`).
- `LC.Council.ShowAssignMenu` calls into `LC.Trade.AssignWinner`.
- Various Vote/Council code calls core Helpers (`LC.CountVotes`, `LC.QualityLabel`, `LC.GetLootmaster`, etc.) — these stay flat on `KART.LC`, so these call sites are unchanged.

This list is not guaranteed exhaustive from manual reading alone — the implementation plan must include a grep-and-verify pass (searching for every relocated function's old bare name, e.g. `LC.LogHistory`, `LC.HandleResult`, `LC.RefreshCouncilRows`, across all `.lua` files) to confirm no stale reference remains, the same discipline used for the GUID-identity rename (see `[[kart-loot-council-plans-status]]`).

## TOC changes

`KeineAhnungRaidTools.toc` currently loads `LootCouncil.lua` between `BuffChecker.lua` and `Droptimizer.lua`. The four new files are inserted immediately after `LootCouncil.lua`, in this order (order is for readability only, not functionally required — see Non-goals):

```
BuffChecker.lua
LootCouncil.lua
LootCouncilVote.lua
LootCouncilPanel.lua
LootCouncilTrade.lua
LootCouncilOfficerNotes.lua
Droptimizer.lua
LootHistory.lua
...
```

`LootHistory.lua`'s existing position (after `Droptimizer.lua`) is unaffected — its added functions have no load-order requirement either, for the same reason.

## Testing approach

No automated test harness exists for this addon (WoW addon, manually tested in-client). Verification plan:

1. `/reload` is insufficient for new files (per project experience — a full WoW client restart is required to pick up new files added to the `.toc`).
2. After restart, run the existing dev Test Function (`LC.StartTest("looter")` and `LC.StartTest("master")`, exposed via the Settings-panel test buttons) to smoke-test vote casting, rolling, council voting, and assignment end-to-end without a real raid.
3. Final confirmation happens in a live raid test, same as the bugfix pass — this split should ideally be verified in the *same* upcoming raid test session already planned for the bugfix pass, to avoid a second separate raid-test cycle.

## Out of scope

- Any of the 3 known bugfix gaps (14b, 16, 20) or the feature plan's 12 remaining tasks — untouched by this refactor.
- Renumbering or editing the section-header comments beyond moving them with their code.
