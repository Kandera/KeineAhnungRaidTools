# Fable Review Fixes — Design

**Date:** 2026-07-24
**Goal:** Fix the confirmed findings from the second-pass Fable review of KeineAhnungRaidTools, plus one new feature (council self-vote), while leaving intentional behaviors untouched.

**Context:** A full second-pass review surfaced 33 findings. The top-tier bugs (scroll ranges, library bundling, keystroke spam, vote/council sync) were independently verified against current code before scoping. This spec captures the agreed scope and the three design-bearing items in detail; the remaining items are mechanical and enumerated for the implementation plan.

---

## Scope

**In (fix this pass):**

| # | Item | Area |
|---|------|------|
| 1 | Vote window can't scroll — `scrollChild` height never updated | LootCouncilVote |
| 2 | Council panel rows past ~31 unreachable — fixed 800px child | LootCouncilPanel |
| 3 | Loot history — **pagination** (see design) | LootHistory |
| 4 | Libraries not bundled, bare `LibStub` unguarded | .pkgmeta / TOC / Utils / Core |
| 5 | `BroadcastRaidConfig` fires per keystroke — debounce | LootCouncilSettings |
| 6 | Own vote missing from own counter on real rolls | LootCouncilVote |
| 7 | Assignments not synced to council peers | LootCouncilTrade |
| 8 | LibDurability callback registered only at file-load | BuffChecker |
| 15 | History `difficulty` localized — **normalize export to EN** (see design) | LootHistory |
| 16 | No-op line `KART.L_enUS = KART.L_enUS or {}` | Locales/enUS |
| 17 | Dead fallback params `sendReason("...", "Bio")` | Core |
| 18 | `KART_LCOfficerNotes` grows unbounded — add pruning | Core / OfficerNotes |
| 19 | Vote-list + council tickers run forever — cancel on hide | LootCouncilVote / Panel |
| 20 | Item icon+border+placeholder setup duplicated 4× → `LC.SetItemIcon` | Vote / Panel |
| 21 | "Refresh council if open" block duplicated ~6× → `LC.RefreshCouncilIfShown` | LootCouncil |
| 22 | Payload build + 255-byte truncation duplicated → shared builder | LootCouncil |
| 23 | BuffChecker state-merge duplicated 2× → `MergeBuffState` | BuffChecker |
| 24 | `(UnitName("player")):match(...)` / re-resolve each refresh → cache own key | BuffChecker |
| 25 | Ready-check icon mapping duplicated 2× → small table | BuffChecker |
| 26 | StaticPopup boilerplate 6× → mini factory | (various) |
| 28 | `Trade.OnTradeShow` use `Identity.ResolvePlayer("npc")` | LootCouncilTrade |
| 29 | **Council self-vote** — new feature (see design) | LootCouncil / Vote |
| 31 | `StartManualRoll` use leader `lcVoteSeconds`, not local | LootCouncil |
| 32 | Broken indentation in `setInd` elseif cascade | BuffChecker |
| 33 | Duplicate section number "-- 6." | MainFrame |

**Out (intentional / deferred):**

- **9** Food fallback `find("Satt")` — needs in-game verification, deferred.
- **10** Aura name fallbacks DE+EN only — intended (guild addon).
- **11** "Item Level " hardcoded — common WoW term, keep.
- **12** Preview reasons hardcoded German — keep.
- **13** "Rdy" header hardcoded — common, keep.
- **14** German date format for all — keep.
- **27** Spacious/Compact renderer share ~60% — big refactor, risk, deferred.
- **30** WU-Import accumulation — intended, no-op.

---

## Design: #29 Council self-vote

**Decision:** Option B — council members get **both** windows.

Roll-start currently routes as a hard either/or in three spots
(`LootCouncil.lua:821` HandleStart, `:856` StartManualRoll, `:886`
HandleManualStart) plus the test loop (`StartTest`, ~`:987`):

```lua
if LC.IsCouncil() then
    KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
else
    LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
end
```

Change: when `LC.IsCouncil()`, call `ShowCouncilPanel` **and** `ShowVotePopup`
for the same roll. A council member who is also a raid member can now declare
their own BIS in the vote list, exactly like any raider. No new UI.

This depends on the **#6 fix**: `Vote.CastVote` for real (non-test) rolls must
also insert the local vote before broadcasting, so the caster's own vote counts
locally and shows in their own counter:

```lua
-- in Vote.CastVote, the non-test branch (currently only SendLC):
local myKey = (KART.Identity.ResolvePlayer("player"))
LC.votes[rollID] = LC.votes[rollID] or {}
LC.votes[rollID][myKey] = {idx = buttonIdx, note = note}
LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":" .. note)
```

Guard against double-counting: `HandleVote` (the receiver of `LC_VOTE`) must not
clobber or reject the sender's own already-inserted entry — but since
`SendAddonMessage` never echoes to the sender, the caster never receives their
own `LC_VOTE`, so no extra guard is needed. Verify this assumption during
implementation by reading `HandleVote`.

## Design: #3 History pagination

**Decision:** Fit-to-visible page size, no inner scroll.

The history window is 560×430; the visible row area is ~301px = ~11 rows at
26px. Pagination replaces the (currently broken) inner scroll entirely.

- **Page size:** computed once from the visible area — `floor(visibleHeight / 26)`,
  min 1. No scrollbar; the page always fits.
- **Controls:** Prev / Next buttons + a "Seite X / Y" (localized) label in the
  footer, left of the Clear button. Buttons disable at the ends.
- **State:** `LH.currentPage` (1-based). Any filter/search change or a new
  logged entry resets to page 1. Newest-first order is unchanged
  (`GetFilteredEntries`).
- **Rendering:** `LH.Refresh` renders only the current page's slice
  (`filtered[(page-1)*pageSize + 1 .. page*pageSize]`), so at most `pageSize`
  row frames exist. Rows keep their reuse pattern; surplus rows hidden.
- The fixed-800px `scrollChild` becomes irrelevant; rows anchor to it as before,
  but only ~11 exist so nothing is clipped. (No `scrollChild:SetHeight` needed
  here — that fix is only for Vote/Council.)

New localized keys: `LH_PAGE_INDICATOR` ("Seite %d / %d" / "Page %d / %d"),
`LH_BTN_PREV`, `LH_BTN_NEXT` (or reuse arrow glyphs "‹"/"›" without new keys —
implementer's choice, arrows preferred to avoid new strings).

## Design: #15 Export difficulty in English

**Decision:** Store canonical `difficultyID`; UI stays localized; export is EN.

`GetInstanceInfo()` returns `name, instanceType, difficultyID, difficultyName, …`.
Both log sites currently store only the localized `difficultyName`
(`LootHistory.lua:628` and the manual/peer path `:731`).

- **Log:** also store `difficultyID` on each entry.
- **UI display:** when `difficultyID` present, show `GetDifficultyInfo(id)`
  localized name; else fall back to the stored `difficulty` string (old entries).
- **Export (JSON):** map `difficultyID` → a fixed EN string via a small local
  table (e.g. 14→"Normal", 15→"Heroic", 16→"Mythic", 17→"LFR"); fall back to the
  stored string when no id. Verify the exact id→name set against the current
  raid difficulty IDs during implementation.
- **Old entries:** no migration — they lack `difficultyID` and export their
  stored (possibly localized) string. Best effort.

---

## Scroll fixes #1 / #2 (mechanical)

Both windows set the outer frame height but never the `scrollChild` height, so
the scroll range is 0. Fix: after laying out rows in the refresh function, set
`scrollChild:SetHeight(contentHeight)` from the actual row count — the pattern
`MainFrame.lua:210` already uses.

- **#1 Vote:** in `RefreshVoteListRows_Spacious` / `_Compact`, after the final
  `y` accumulation, `f.scrollChild:SetHeight(math.max(y, 1))`.
- **#2 Council:** in `RefreshCouncilRows`, `f.scrollChild:SetHeight(#members * 26)`
  (or the actual per-row stride used there).

## Library bundling #4 (packaging)

The packaged CurseForge zip (project id 1603461) ships no libs: no `Libs/`
folder, no `externals` in `.pkgmeta`, no LibStub embed in the TOC. Bare
`LibStub("LibDataBroker-1.1")` (`Core.lua:26`) errors if no other addon provides
LibStub. Fix:

- Add an `externals` block to `.pkgmeta` pulling LibStub, LibDataBroker-1.1,
  LibDBIcon-1.0, LibSharedMedia-3.0 into `Libs/…`.
- Add an embeds/library load file (or list the lib `.xml`/`.lua` in the TOC
  before the addon files) so the packaged build loads them.
- Guard the one unguarded call (`Core.lua:26`) defensively so a mispackaged
  build degrades instead of hard-erroring.

Exact library paths/versions and the embed mechanism are verified during
implementation against a test package build.

---

## Testing

No Lua test harness exists in the repo. Verification is:

- **Code inspection** of each change against the finding.
- **In-game `/reload`** — all changes are to existing files (no new files), so a
  reload suffices (a full restart is only needed for newly added files).
- Manual scenarios: 4-item vote scroll, 30+ council rows, history paging, a
  keystroke burst in settings (one broadcast after idle), a council member
  casting their own vote, a reassignment reflected on a peer.

## Out of scope

Items 9, 10, 11, 12, 13, 14, 27, 30 as listed above. The big Spacious/Compact
renderer refactor (#27) is explicitly deferred to avoid risk unless that code is
being reworked anyway.
