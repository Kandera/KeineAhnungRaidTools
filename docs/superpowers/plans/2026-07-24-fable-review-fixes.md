# Fable Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 25 in-scope findings from the 2026-07-24 second-pass Fable review — scroll ranges, library bundling, keystroke spam, vote/council sync, one new feature (council self-vote), history pagination, EN export, plus dead-code and simplification cleanups — in 6 ordered blocks.

**Architecture:** WoW Retail addon, single `KART` namespace shared via `local addonName, KART = ...`. No test framework exists — every task verifies via grep assertions plus an in-game `/reload` check. No new files are added, so `/reload` always suffices (a full client restart is only needed for newly `.toc`-listed files). Blocks are ordered so bug fixes land before the simplify/dedup block that absorbs their callsites.

**Tech Stack:** Lua 5.1 (WoW), WoW Retail API (Interface 12.x), LibStub, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, optional LibDurability.

**Design doc:** `docs/superpowers/specs/2026-07-24-fable-review-fixes-design.md`

## Global Constraints

- Comments and commit messages in English (repo CLAUDE.md).
- Locale: `Locales/enUS.lua` is the master; `deDE.lua` values stay German, its comments English. Every new user-facing string gets a key in **both** files.
- `KART.L` is a stable table reference — never replace it, only swap values in place. New static UI text needs a locale-refresher entry (`KART.DynamicLabels`).
- CHANGELOG entries: max 1–2 lines, bold lead + short clause, no causes. Update `CHANGELOG.md` first, mirror into `CHANGELOG-de.md` in the same commit. Only user-facing changes get an entry (features/visible bugfixes — not internal dedup).
- Commits go directly to `main`, one commit per task, conventional-commit style.

## Verification Toolkit

- Grep assertion: `grep -n "<pattern>" <file>` from repo root.
- In-game reload: `/reload`.
- Fresh-settings sim: `/run KART_Settings.<key> = nil ReloadUI()`.
- Lua error visibility: `/console scriptErrors 1` once per client.

---

# Block 1 — High-impact bug fixes

Independent, land first — these hit the next raid.

### Task 1: Scroll-range fix for Vote + Council windows (#1, #2)

**Files:**
- Modify: `LootCouncilVote.lua` — `RefreshVoteListRows_Spacious`, `RefreshVoteListRows_Compact` (the two renderers; each accumulates a `y` layout cursor and ends with `f:SetHeight(math.min(32 + y + 12, 600))` at ~`:487` / ~`:745`).
- Modify: `LootCouncilPanel.lua` — `RefreshCouncilRows` (positions member rows; scrollChild fixed at `:556`).

**Interfaces:**
- Consumes: `f.scrollChild` (both windows), the per-row stride already used by each renderer.
- Produces: correct scroll range; no signature changes.

- [ ] **Step 1: Vote — set scrollChild height from content**

In both `RefreshVoteListRows_Spacious` and `_Compact`, immediately before the existing `f:SetHeight(math.min(32 + ... , 600))`, add:

```lua
    f.scrollChild:SetHeight(math.max(y, 1))
```

(Use the same `y` cursor each renderer already accumulates for total content height; for `_Compact` it is `#visibleRolls * (rowH + ROW_GAP)`.)

- [ ] **Step 2: Council — set scrollChild height from row count**

In `RefreshCouncilRows`, after the member-row layout loop, add (using the actual per-row stride — read it from the loop, it is the same `-(i-1)*STRIDE` pattern the rows are positioned with):

```lua
    f.scrollChild:SetHeight(math.max(#members * ROW_STRIDE, 1))
```

- [ ] **Step 3: Verify**

Run: `grep -n "scrollChild:SetHeight" LootCouncilVote.lua LootCouncilPanel.lua`
Expected: one hit per renderer in Vote, one in Council.

In-game: start a 4-item test roll (`/kart` test) → all 4 cards reachable by scroll. Council panel with 30+ raid members → last rows reachable.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilVote.lua LootCouncilPanel.lua
git commit -m "fix: update scrollChild height so vote list and council panel scroll to their last rows"
```

### Task 2: Debounce BroadcastRaidConfig on text edits (#5)

**Files:**
- Modify: `LootCouncilSettings.lua` — the three `OnTextChanged` handlers at `:184` (buttons), `:208` (council), `:263` (lootmaster), each currently calling `LC.BroadcastRaidConfig()` directly.

**Interfaces:**
- Produces: `LC.BroadcastRaidConfigThrottled()` — a debounced wrapper other callers may reuse.

- [ ] **Step 1: Add a debounced wrapper**

In `LootCouncil.lua` near `BroadcastRaidConfig`, add:

```lua
-- OnTextChanged fires per keystroke; broadcasting the full raid config on every letter floods
-- the raid with addon messages. Coalesce edits into a single broadcast ~1s after typing stops
-- (mirrors HandleAutoPromoteThrottled's debounce approach).
function LC.BroadcastRaidConfigThrottled()
    if LC._cfgBroadcastTimer then LC._cfgBroadcastTimer:Cancel() end
    LC._cfgBroadcastTimer = C_Timer.NewTimer(1, function()
        LC._cfgBroadcastTimer = nil
        LC.BroadcastRaidConfig()
    end)
end
```

- [ ] **Step 2: Point the three handlers at it**

In `LootCouncilSettings.lua`, replace each `LC.BroadcastRaidConfig()` inside the three `OnTextChanged` handlers with `LC.BroadcastRaidConfigThrottled()`. Leave any non-OnTextChanged callers of `BroadcastRaidConfig` unchanged.

- [ ] **Step 3: Verify**

Run: `grep -n "BroadcastRaidConfig" LootCouncilSettings.lua`
Expected: three `BroadcastRaidConfigThrottled` calls, no bare `BroadcastRaidConfig()` in the OnTextChanged handlers.

In-game (as raid leader, `/console scriptErrors 1`, watch with an addon-msg monitor or just confirm no error): type a full council list fast → one broadcast ~1s after the last keystroke.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua LootCouncilSettings.lua
git commit -m "fix: debounce raid-config broadcast so settings edits send once, not per keystroke"
```

### Task 3: Count the caster's own vote locally on real rolls (#6)

**Files:**
- Modify: `LootCouncilVote.lua` — `Vote.CastVote` (`:191`), the non-test (`else`) branch that currently only calls `LC.SendLC`.

**Interfaces:**
- Consumes: `KART.Identity.ResolvePlayer("player")`, `LC.votes`.
- Produces: `LC.votes[rollID][myKey]` populated for real rolls too — Task 6 (self-vote) relies on this.

- [ ] **Step 1: Read HandleVote first**

Confirm the `LC_VOTE` receiver (`LC.HandleVote`) does not need the sender's own message (it never receives it — `SendAddonMessage` doesn't echo), so a local insert cannot double-count.

- [ ] **Step 2: Insert the local vote before broadcasting**

In `Vote.CastVote`, change the `else` branch from:

```lua
    else
        LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":" .. note)
    end
```

to:

```lua
    else
        -- SendAddonMessage never echoes back to its own sender, so record our own vote locally
        -- (same as the test branch and LC_ROLL do) — otherwise our own counter reads one short.
        local myKey = (KART.Identity.ResolvePlayer("player"))
        LC.votes[rollID] = LC.votes[rollID] or {}
        LC.votes[rollID][myKey] = {idx = buttonIdx, note = note}
        LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":" .. note)
    end
```

- [ ] **Step 3: Verify**

Run: `grep -n "LC.votes\[rollID\]\[myKey\]" LootCouncilVote.lua`
Expected: appears in both the test branch and the new real-roll branch.

In-game: on a real roll, cast a vote → own counter includes self immediately.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "fix: record own vote locally on real rolls so the caster's counter includes themselves"
```

### Task 4: Sync assignment result to council peers (#7)

**Files:**
- Modify: `LootCouncilTrade.lua` — `Trade.HandleResult` (`:564`), after it resolves `winnerKey`/`rollID`.

**Interfaces:**
- Consumes: `LC.assignedWinners`, `KART.LC.Council.RefreshCouncilRows`, panel-shown check.
- Produces: `LC.assignedWinners[rollID]` set on every client receiving a result.

- [ ] **Step 1: Record the winner + refresh the panel on peers**

In `Trade.HandleResult`, after the `winnerKey == "NONE"` early-return (so NONE clears nothing extra) and once a real winner is known, set the shared state and refresh the council panel if it's open:

```lua
    -- Council peers must see the same assigned winner the assigner recorded locally (gold-highlight
    -- + correct prevWinner on any later reassignment) — the result broadcast is the only signal
    -- they get, so mirror it into the shared state here.
    LC.assignedWinners[rollID] = winnerKey
    if LC.RefreshCouncilIfShown then LC.RefreshCouncilIfShown(rollID) end
```

(If Task 12's `RefreshCouncilIfShown` helper is not yet present when this task runs, inline the existing guard instead: `if LC.councilPanel and LC.councilPanel:IsShown() then if LC.activeRollID == rollID then KART.LC.Council.RefreshCouncilRows() end KART.LC.Council.RefreshCouncilTabs() end`.)

- [ ] **Step 2: Verify**

Run: `grep -n "assignedWinners\[rollID\] = winnerKey" LootCouncilTrade.lua`
Expected: one hit in `HandleResult`.

In-game (two council clients): assign a winner on client A → client B's open panel shows the gold winner highlight; a reassign on B confirms with the correct previous winner.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilTrade.lua
git commit -m "fix: record assigned winner on council peers so highlights and reassign confirms stay in sync"
```

### Task 5: Register LibDurability callback in ADDON_LOADED (#8)

**Files:**
- Modify: `BuffChecker.lua:60` (file-load `LibStub("LibDurability", true)`), and the addon's ADDON_LOADED / init path (find where BuffChecker initializes).

- [ ] **Step 1: Re-fetch + register on load, not only at parse time**

`BuffChecker.lua:60` captures `LibDurability` at file-parse time; if the provider addon (e.g. MRT — "M" > "K") loads after KART, it is nil forever and the Repair column stays 100% for others. Move the callback registration into the addon's load handler so it retries once the provider is present. Add a guarded `LibStub("LibDurability", true)` re-fetch there and register the durability callback if not already registered (idempotent flag `BC._durabilityRegistered`).

Exact hook location + callback signature verified against the current registration code during implementation.

- [ ] **Step 2: Verify**

Run: `grep -n "LibDurability\|_durabilityRegistered" BuffChecker.lua`
Expected: a load-time re-fetch + idempotent registration.

In-game (MRT loaded): open Buff-Checker → other players' repair % populates without a reload.

- [ ] **Step 3: Commit**

```bash
git add BuffChecker.lua
git commit -m "fix: register LibDurability callback on load so late-loading providers still feed repair data"
```

---

# Block 2 — Features

### Task 6: Council self-vote — show both windows (#29)

**Files:**
- Modify: `LootCouncil.lua` — `HandleStart` (`:821`), `StartManualRoll` (`:856`), `HandleManualStart` (`:886`), and the `StartTest` "master" loop (~`:987`).

**Interfaces:**
- Consumes: Task 3's local-vote insert (so a council member's own vote counts).

- [ ] **Step 1: Add ShowVotePopup alongside ShowCouncilPanel**

In each of the three routing spots, change the branch so council also gets the vote list:

```lua
    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    else
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
```

(For `StartManualRoll`/`HandleManualStart` use their local `itemLink`/`seconds` variables as those callsites already do.) In `StartTest`'s master branch, also call `ShowVotePopup` for each test roll so testing matches live.

- [ ] **Step 2: Verify**

Run: `grep -n "ShowVotePopup" LootCouncil.lua`
Expected: appears inside the `IsCouncil()` branch of all three roll-start paths + the test loop.

In-game (as a council member in a raid): a roll opens both the council panel and the vote list; casting a BIS vote there broadcasts and appears in counters everywhere.

- [ ] **Step 3: Changelog + commit**

Add to `CHANGELOG.md` (and mirror `CHANGELOG-de.md`):
`- **Council members can now cast their own loot vote.**`

```bash
git add LootCouncil.lua CHANGELOG.md CHANGELOG-de.md
git commit -m "feat: let council members cast their own vote by also showing them the vote window"
```

### Task 7: History pagination (#3)

**Files:**
- Modify: `LootHistory.lua` — window build (footer area ~`:420-430`), `LH.Refresh` (`:455`), filter/search handlers (`:310-358`), the log-append refresh (`:634`).
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` — page indicator key.

**Interfaces:**
- Produces: `LH.currentPage`, page-size computed from the visible area; `LH.Refresh` renders only the current page slice.

- [ ] **Step 1: Add locale key**

`Locales/enUS.lua`: `LH_PAGE_INDICATOR = "Page %d / %d",`
`Locales/deDE.lua`: `LH_PAGE_INDICATOR = "Seite %d / %d",`
(Prev/Next use glyphs "‹"/"›" — no new keys.)

- [ ] **Step 2: Add footer controls**

In the window build, next to the count/Clear footer, add a Prev button, a page-indicator FontString (register in `KART.DynamicLabels`), and a Next button. Prev/Next adjust `LH.currentPage` (clamped) and call `LH.Refresh()`.

- [ ] **Step 3: Page-slice the render**

In `LH.Refresh`, compute:

```lua
    local pageSize = math.max(1, math.floor(f.scrollChild:GetHeight() > 0
        and (scrollFrame_visible_height) / 26 or 11))
```

Use the scroll frame's actual visible height (read it in the build and store on `f`, e.g. `f.pageSize`), so page size is fixed at build time. Then render only
`filtered[(LH.currentPage-1)*pageSize + 1 .. LH.currentPage*pageSize]`, hide surplus rows, update the indicator `LH_PAGE_INDICATOR` with `currentPage` / `ceil(#filtered/pageSize)`, and enable/disable Prev/Next at the bounds.

- [ ] **Step 4: Reset to page 1 on filter/search/new-entry**

In every filter/search handler and the log-append refresh path, set `LH.currentPage = 1` before `LH.Refresh()`. Clamp `currentPage` to the new page count inside `Refresh` (a filter can shrink the list).

- [ ] **Step 5: Verify**

Run: `grep -n "currentPage\|LH_PAGE_INDICATOR\|pageSize" LootHistory.lua`
Expected: page state + slice + indicator present.

In-game: open history with >page-size entries → only one page renders, Prev/Next work, indicator correct; applying a filter jumps to page 1.

- [ ] **Step 6: Changelog + commit**

`- **Loot history is now paginated.**` (both changelogs).

```bash
git add LootHistory.lua Locales/enUS.lua Locales/deDE.lua CHANGELOG.md CHANGELOG-de.md
git commit -m "feat: paginate loot history so large logs stay navigable and cheap to render"
```

### Task 8: Export loot-history difficulty in English (#15)

**Files:**
- Modify: `LootHistory.lua` — both log sites (`:620-628` and the manual/peer path `:731`), the row display (`:547`), and the JSON export builder (find `GetInstanceInfo`/export function).

- [ ] **Step 1: Store difficultyID on log**

At `:620`, capture the id: `local _, _, difficultyID, difficultyName = GetInstanceInfo()` and add `difficultyID = difficultyID,` to the inserted entry table. Do the same at the second log site (`:731`) using whatever difficulty source it has (store `difficultyID` if available, else leave nil).

- [ ] **Step 2: UI display prefers localized-from-id, falls back to string**

At the row render (`:547`), when `e.difficultyID` is present use `GetDifficultyInfo(e.difficultyID)`'s localized name; else use the stored `e.difficulty` string; else "—".

- [ ] **Step 3: Export maps id → EN**

In the JSON export builder, add a local id→EN table (verify the current retail raid difficulty ids during implementation, e.g. `{[14]="Normal",[15]="Heroic",[16]="Mythic",[17]="LFR"}`) and emit the EN name when `difficultyID` is set, else the stored string.

- [ ] **Step 4: Verify**

Run: `grep -n "difficultyID\|GetDifficultyInfo" LootHistory.lua`
Expected: stored on log, used in display + export.

In-game: log an item, export → `instance`/difficulty field reads the EN name regardless of client language.

- [ ] **Step 5: Commit**

```bash
git add LootHistory.lua
git commit -m "fix: store canonical difficulty id and export it in English (mixed-language raids logged inconsistently)"
```

---

# Block 3 — Packaging

### Task 9: Bundle libraries + guard bare LibStub (#4)

**Files:**
- Modify: `.pkgmeta` (add `externals`), `KeineAhnungRaidTools.toc` (load embeds), create `Libs/` via packager, `Core.lua:26` (guard).

- [ ] **Step 1: Add externals to .pkgmeta**

```yaml
externals:
  Libs/LibStub: https://repos.wowace.com/wow/libstub/trunk
  Libs/LibDataBroker-1.1: https://repos.wowace.com/wow/libdatabroker-1-1/trunk
  Libs/LibDBIcon-1.0:
    url: https://repos.wowace.com/wow/libdbicon-1-0/trunk
    tag: latest
  Libs/LibSharedMedia-3.0: https://repos.wowace.com/wow/libsharedmedia-3-0/trunk
```

(Verify exact repo URLs/versions against a current CurseForge addon during implementation.)

- [ ] **Step 2: Load embeds in the TOC**

Add an embeds load list (either a `Libs/embeds.xml` referenced first in the TOC, or list each lib's `.lua`/`.xml` before `Utils.lua`). LibStub must load first.

- [ ] **Step 3: Guard the one unguarded call**

`Core.lua:26` — wrap so a mispackaged build degrades instead of hard-erroring:

```lua
local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
local ldbObject = ldb and ldb:NewDataObject("KeineAhnungRaidTools", { ... })
```

Guard the later `ldbObject` uses (minimap button registration) with `if ldbObject then`.

- [ ] **Step 4: Verify**

Run: `grep -n "externals" .pkgmeta` and confirm a local packager build (or manual `Libs/` copy) produces a zip where `Libs/LibStub/LibStub.lua` exists and the TOC loads it first.

In-game (disable all other addons that provide LibStub): KART loads with no Lua error.

- [ ] **Step 5: Commit**

```bash
git add .pkgmeta KeineAhnungRaidTools.toc Core.lua
git commit -m "fix: bundle LibStub/LDB/LibDBIcon/LSM via .pkgmeta and guard the LDB call (packaged addon dead without a lib provider)"
```

---

# Block 4 — Correctness cleanups

### Task 10: Prune KART_LCOfficerNotes (#18)

**Files:**
- Modify: `Core.lua` — near the `KART_PlayerCache` 90-day prune (`:283`).

- [ ] **Step 1: Add matching prune**

Mirror the `KART_PlayerCache` pruning for `KART_LCOfficerNotes` (drop entries older than the same retention window; verify the note entry shape has a timestamp — if not, prune by whatever staleness signal PlayerCache uses / add a `time` stamp on write).

- [ ] **Step 2: Verify**

Run: `grep -n "KART_LCOfficerNotes" Core.lua`
Expected: a prune pass alongside PlayerCache.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "fix: prune stale officer notes so KART_LCOfficerNotes stops growing unbounded"
```

### Task 11: Cancel list/council tickers on hide (#19)

**Files:**
- Modify: `LootCouncilVote.lua:67` (vote-list ticker), `LootCouncilPanel.lua:602` (council ticker).

- [ ] **Step 1: Cancel on hide, recreate on show**

Both tickers currently run forever with an `IsShown()` guard. Change each frame's `OnHide` to cancel its ticker and `OnShow` to (re)create it. Keep the `IsShown()` guard inside as a belt-and-braces.

- [ ] **Step 2: Verify**

Run: `grep -n "OnHide\|NewTicker\|:Cancel()" LootCouncilVote.lua LootCouncilPanel.lua`
Expected: ticker created on show, cancelled on hide.

In-game: open/close both windows repeatedly → no error, countdowns still tick when open.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilVote.lua LootCouncilPanel.lua
git commit -m "refactor: cancel vote-list and council tickers on hide instead of running them forever"
```

### Task 12: StartManualRoll uses leader vote seconds (#31)

**Files:**
- Modify: `LootCouncil.lua:838` (`StartManualRoll`).

- [ ] **Step 1: Use the leader-authoritative value**

`StartManualRoll` reads `KART_Settings.lcVoteSeconds` (the local lootmaster's own value). Change it to the same leader-synced value the rest of the flow uses (verify the accessor — likely `LC.GetVoteSeconds()` or the synced config field; match `HandleStart`'s source).

- [ ] **Step 2: Verify**

Run: `grep -n "lcVoteSeconds\|GetVoteSeconds" LootCouncil.lua`
Expected: `StartManualRoll` uses the same source as `HandleStart`.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: manual rolls use the leader's configured vote duration, not the lootmaster's local value"
```

---

# Block 5 — Simplification / dedup

Land after Blocks 1–4 so helpers absorb the already-fixed callsites. Each task is internal-only (no changelog).

### Task 13: LC.SetItemIcon helper (#20)

**Files:**
- Modify: `LootCouncilVote.lua` (`:375`, `:628`), `LootCouncilPanel.lua` (`:154`, `:268`).

- [ ] **Step 1: Extract helper**

Add `function LC.SetItemIcon(icon, border, link)` capturing the shared icon-texture + border + placeholder(question-mark) logic these four sites duplicate (read all four, confirm identical, factor differences into params). Replace each site with a call.

- [ ] **Step 2: Verify** — `grep -n "LC.SetItemIcon" *.lua` → one definition, four calls. In-game: icons still render in vote cards + council tabs.

- [ ] **Step 3: Commit** — `refactor: extract LC.SetItemIcon to dedupe icon/border/placeholder setup`

### Task 14: LC.RefreshCouncilIfShown helper (#21)

**Files:**
- Modify: `LootCouncil.lua` (helper + callsites in HandleVote, HandleRoll, HandleCouncilVote, SetPlayerVote, CastVote test branch, ResolveRollItemLink, HandleOfficerNote), and adopt it in `LootCouncilTrade.lua:HandleResult` (Task 4).

- [ ] **Step 1: Add helper**

```lua
-- Refresh the council panel only if it's open and looking at this roll — the "refresh council if
-- shown" guard was copy-pasted across every handler that mutates vote/assignment state.
function LC.RefreshCouncilIfShown(rollID)
    if not (LC.councilPanel and LC.councilPanel:IsShown()) then return end
    if LC.activeRollID == rollID then KART.LC.Council.RefreshCouncilRows() end
    KART.LC.Council.RefreshCouncilTabs()
end
```

(Verify each callsite's exact refresh set matches this before replacing — some may only call one of the two refreshers; keep behavior identical.)

- [ ] **Step 2: Verify** — `grep -n "RefreshCouncilIfShown" *.lua` → one definition, all adopted sites. In-game: votes still refresh the open panel.

- [ ] **Step 3: Commit** — `refactor: extract LC.RefreshCouncilIfShown to dedupe the panel-refresh guard`

### Task 15: Shared addon-message payload builder (#22)

**Files:**
- Modify: `LootCouncil.lua` — `BroadcastRaidConfig` (`:298`), `SendSettingsSync` (`:407`).

- [ ] **Step 1: Extract the payload-build + 255-byte truncation these two share into a local helper; call from both. Keep the wire format byte-identical.**

- [ ] **Step 2: Verify** — grep the helper; in-game config sync still works between two clients.

- [ ] **Step 3: Commit** — `refactor: share the raid-config payload builder between broadcast and settings sync`

### Task 16: BuffChecker dedup — merge, icon table, cached key (#23, #24, #25)

**Files:**
- Modify: `BuffChecker.lua` (`:727-736` & `:792-803` merge; ready-check icon mapping preview vs real; `(UnitName("player")):match` / per-refresh `ResolvePlayer("player")`).

- [ ] **Step 1:** Extract `MergeBuffState(id, state)` from the two near-identical merges (#23).
- [ ] **Step 2:** Pull the `136814/136813/136815` ready-check icon mapping into one small local table used by both preview and real (#25).
- [ ] **Step 3:** Cache the player's own key/short-name once (GUID never changes) instead of re-matching + re-resolving every refresh (#24).
- [ ] **Step 4: Verify** — grep for `MergeBuffState`, the icon table, the cached key; in-game buff check unchanged.
- [ ] **Step 5: Commit** — `refactor: dedupe BuffChecker state-merge, ready-check icons, and own-key lookup`

### Task 17: StaticPopup factory (#26)

**Files:**
- Modify: the ~6 `StaticPopupDialogs[...]` definitions (grep `StaticPopupDialogs` across `*.lua`).

- [ ] **Step 1:** Add a small factory that fills the identical `timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3` boilerplate, letting each definition pass only its text/buttons/handlers. Only fold in dialogs that share all four values.
- [ ] **Step 2: Verify** — grep the factory; trigger each popup in-game.
- [ ] **Step 3: Commit** — `refactor: add a StaticPopup factory for the shared dialog boilerplate`

### Task 18: Trade.OnTradeShow via Identity.ResolvePlayer("npc") (#28)

**Files:**
- Modify: `LootCouncilTrade.lua` — `Trade.OnTradeShow`.

- [ ] **Step 1:** Replace the `UnitName("npc")` + `TradeFrameRecipientNameText` text-resolution path with `KART.Identity.ResolvePlayer("npc")` (the unit token exists during the trade; cross-realm-safe). Drop the now-dead text fallback.
- [ ] **Step 2: Verify** — grep confirms no `TradeFrameRecipientNameText` left in the function; in-game trade still identifies the partner (incl. cross-realm).
- [ ] **Step 3: Commit** — `refactor: resolve trade partner via Identity.ResolvePlayer("npc")`

---

# Block 6 — Dead code + cosmetic

### Task 19: Dead-code + cosmetic sweep (#16, #17, #32, #33)

**Files:**
- Modify: `Locales/enUS.lua:338`, `Core.lua:626`ff, `BuffChecker.lua:424-432`, `MainFrame.lua:344`/`:382`.

- [ ] **Step 1:** Remove the no-op `KART.L_enUS = KART.L_enUS or {}` at `enUS.lua:338` (#16).
- [ ] **Step 2:** Drop the unreachable fallback params in `sendReason("RC_REASON_BIO", "Bio")` etc. at `Core.lua:626`ff — keys always exist in `KART.L` (#17). Verify each key exists in both locales before removing its fallback.
- [ ] **Step 3:** Fix the broken `setInd` elseif-cascade indentation at `BuffChecker.lua:424-432` (#32).
- [ ] **Step 4:** Renumber the duplicated `-- 6.` section comment at `MainFrame.lua:344`/`:382` (#33).
- [ ] **Step 5: Verify** — `grep -n "L_enUS = KART.L_enUS" Locales/enUS.lua` → no hit; visual check of the other three. `/reload` → no error.
- [ ] **Step 6: Commit** — `refactor: remove dead no-op/fallbacks and fix indentation + duplicate section number`

---

## Self-Review

- **Coverage:** All 25 in-scope items map to a task — 1,2→T1; 5→T2; 6→T3; 7→T4; 8→T5; 29→T6; 3→T7; 15→T8; 4→T9; 18→T10; 19→T11; 31→T12; 20→T13; 21→T14; 22→T15; 23/24/25→T16; 26→T17; 28→T18; 16/17/32/33→T19.
- **Dependencies:** T3 before T6 (self-vote needs local vote insert); T4 may reference T14's helper (inline fallback noted); T13/T14 land after their callsites are fixed.
- **Deferred/out:** 9, 10, 11, 12, 13, 14, 27, 30 — not in any task, by design.
- **Implementation-time verifies (not placeholders):** exact lib repo URLs/versions (T9), retail difficulty ids (T8), LibDurability callback signature + hook (T5), per-row strides (T1), officer-note timestamp shape (T10), leader vote-seconds accessor (T12) — each is a "read the current code / confirm the external fact" step, not undefined work.
