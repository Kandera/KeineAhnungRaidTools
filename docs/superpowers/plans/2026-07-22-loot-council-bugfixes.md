# Loot Council Bugfixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 23 Loot Council / BuffChecker bugs reported after the latest testing pass, grouped by shared root cause so related symptoms are fixed together instead of patched individually.

**Architecture:** No new subsystems. Every fix is a targeted change inside the existing `LC_*` addon-message protocol, the existing per-rollID state tables (`LC.rollItems`, `LC.votes`, `LC.pendingTrades`, etc.), and the existing `Core.lua` event/message dispatcher. The one new wire message (`LC_STATE_REQ`) follows the exact request/response shape already used by `LC.RequestHistorySync`/`LC.HandleHistoryRequest`.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — this project has no automated test suite; verification is manual, in-game. Several tasks (state-sync, auto-trade) are inherently multi-player and need two characters/clients to verify fully; each task's verification step says so where it applies.

## Global Constraints

- English source: code, comments, commit messages. This plan touches no player-facing locale strings (no `Locales/enUS.lua`/`deDE.lua` changes needed — verified per-task below).
- `CHANGELOG.md` gets the fixes as `### Fixed` bullets (one line each, bold lead, no technical causes); mirror into `CHANGELOG-de.md` in the same task (Task 15).
- Bump `KeineAhnungRaidTools.toc`'s `## Version:` from `2.4.0` to `2.5.0` (Task 15).
- Every new/changed wire message reuses the existing `"KART"` addon-message prefix and the existing short-name (`:match("([^%-]+)")`) sender convention already used throughout `Core.lua`/`LootCouncil.lua` — this plan does not attempt to re-key identity by realm (see "Known gaps" at the end; that's a larger, separately-scoped change, not part of this fix pass).
- Do not touch `Features` from the separate features plan — this plan is bugfixes only, and per the project owner's instruction, the features plan is blocked until every task here is shipped.

## Bug-to-task map

| Bug # | Symptom (as reported) | Fixed by |
|---|---|---|
| 1 | Lootmaster's auto-Need/Greed never fires | Task 1 |
| 2 | Auto-Need/Greed does nothing when only Transmog is rollable | Task 2 |
| 3 | Loot history logs duplicate entries on reassignment | Task 5 |
| 4 | Right-click assign posts/trades the wrong item | Task 3 |
| 5 | Auto-Trade list doesn't tick off after a real trade | Task 7 |
| 6 | Auto-Trade list incomplete / not extended | Task 6 |
| 7 | Auto-Trade window can't be reopened after closing | Task 8 |
| 8 | LootCouncil window can't be reopened after closing | Task 8 |
| 9 | Some windows draggable only by body, not header | Task 9 |
| 10 | Toys/Housing items ignore the min-quality rule | Task 10 |
| 11 | Session doesn't end; stale tabs after next boss | Task 3 |
| 12 | Vote button shows wrong state (Need shown as Passed) | Task 1 (narrows the race to negligible; see Task 1 notes) |
| 13 | (historical precedent only, no live bug) | n/a — informs Task 13 |
| 14 | False "no KART" indicator / some players show nothing | Task 12 (no-KART part only; see "Known gaps") |
| 15 | Rolls randomly not displayed | Task 1 |
| 16 | LootCouncil window not shown for other-realm players | Not fixed — see "Known gaps" |
| 17 | Items show "???" for new boss loot | Task 4 |
| 18 | Items show "???" for fully German client | Task 4 |
| 19 | Normal loot window's close (X) button too small | Task 11 |
| 20 | Windows randomly open/close for one player | Not fixed — see "Known gaps" |
| 21 | Auto-Pass doesn't work for some players | Task 1 |
| 22 | Item tooltip missing in vote window | Task 4 (same stuck-`"???"` cause; no separate code change) |
| 23 | BuffChecker: food buff not shown active on German client | Task 13 |

---

### Task 1: Raid-state catch-up sync for late joiners/reloaders

**Files:**
- Modify: `LootCouncil.lua:509-537` (`LC.CheckRaidJoin`), `LootCouncil.lua:502-507` (`LC.SetSessionActive`, only for the reset-flag addition), new function near `LootCouncil.lua:245-260` (right after `LC.BroadcastRaidConfig`/`LC.HandleConfig`)
- Modify: `Core.lua:391-396` (`CHAT_MSG_ADDON` dispatcher, new branch)

**Interfaces:**
- Produces: `LC.HandleStateRequest()` — called from `Core.lua`'s dispatcher on `"LC_STATE_REQ"`; no return value.
- Consumes: existing `LC.BroadcastRaidConfig()` and `SendLC` (both already defined earlier in `LootCouncil.lua`, in scope for any function added later in the same file — same pattern `LC.SendSettingsSync` already relies on).

**Root cause (confirmed by reading the code, not guessed):** `LC.sessionActive`, `LC.raidConfig.rollsEnabled`, and `LC.raidConfig.buttonLabels` are populated only by one-shot broadcasts (`LC.SetSessionActive` sends `LC_ACTIVE:` exactly once, at the moment the leader toggles it; `LC.BroadcastRaidConfig` sends `LC_CONFIG:` only when the *leader's own* `GROUP_ROSTER_UPDATE` happens to fire while a session is active). A player who joins late, `/reload`s, or whose join event doesn't line up with the leader noticing a roster change is permanently stuck on stale/default values for the whole raid — `LC.OnStartLootRoll` returns at its `if not LC.sessionActive then return end` guard before Auto-Pass/Auto-Need-Greed/the opt-in roll ever run (Bugs 1, 21, 15), and `LC.GetButtonConfig` can resolve a vote index against the wrong label list during the same race window (Bug 12). This mirrors the request/response pattern the codebase already uses correctly for loot-history catch-up (`LC.RequestHistorySync`/`LC.HandleHistoryRequest`) — that pattern just was never extended to session/config state.

- [ ] **Step 1: Add `LC.stateSyncRequested` reset alongside the existing session reset**

In `LootCouncil.lua`, locate this exact block (the `if not IsInRaid() then` branch of `LC.CheckRaidJoin`):

```lua
function LC.CheckRaidJoin()
    if not IsInRaid() then
        LC.promptedThisSession = false
        LC.sessionActive = false
        LC.historySyncRequested = false
        return
    end
```

Change it to:

```lua
function LC.CheckRaidJoin()
    if not IsInRaid() then
        LC.promptedThisSession = false
        LC.sessionActive = false
        LC.historySyncRequested = false
        LC.stateSyncRequested = false
        return
    end
```

- [ ] **Step 2: Request the current session/config state once per raid join**

Immediately below that block, locate:

```lua
    -- Ask peers (once per raid join) for any loot-history entries logged while we weren't around.
    if not LC.historySyncRequested then
        LC.historySyncRequested = true
        LC.RequestHistorySync()
    end
```

Add directly after it:

```lua
    -- Ask the raid leader (once per raid join/reload) for the current session-active flag and
    -- raid-wide config, so a late joiner or a /reload'd client is never stuck on stale defaults
    -- until the leader happens to notice a roster change (see LC.HandleStateRequest below) — same
    -- request/response shape as the loot-history catch-up above.
    if not LC.stateSyncRequested then
        LC.stateSyncRequested = true
        SendLC("LC_STATE_REQ")
    end
```

- [ ] **Step 3: Add the leader-side responder**

In `LootCouncil.lua`, immediately after `LC.HandleConfig` (the function ending `LC.CouncilNamesTable[trimmed] = true end\nend`, right before the `LC.SendSettingsSync` comment block), add:

```lua
-- Answers an "LC_STATE_REQ" broadcast from a joining/reloading peer with the current session flag
-- and, if a session is active, the full raid config — a one-shot pull instead of waiting for the
-- leader's own roster-change handler to happen to fire (see LC.CheckRaidJoin). Only the actual
-- leader replies, same authority rule as LC.BroadcastRaidConfig itself.
function LC.HandleStateRequest()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    SendLC("LC_ACTIVE:" .. (LC.sessionActive and "1" or "0"))
    if LC.sessionActive then LC.BroadcastRaidConfig() end
end
```

- [ ] **Step 4: Wire `LC_STATE_REQ` into the `Core.lua` dispatcher**

In `Core.lua`, locate this exact sequence:

```lua
                elseif msg == "LC_SYNC_DECLINE" then
                    if KART.LC then KART.LC.HandleSyncDecline(shortName) end
                elseif msg:sub(1, 10) == "RC_REASON:" then
```

Insert a new arm between them:

```lua
                elseif msg == "LC_SYNC_DECLINE" then
                    if KART.LC then KART.LC.HandleSyncDecline(shortName) end
                elseif msg == "LC_STATE_REQ" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleStateRequest() end
                elseif msg:sub(1, 10) == "RC_REASON:" then
```

- [ ] **Step 5: Manual verification (needs two clients)**

On Client A (raid leader): create/join a raid, enable Loot Council, toggle the session on. On Client B: join the same raid *after* the session is already active. Confirm Client B's `/reload` also works — after reloading, Client B should have `LC.sessionActive == true` again within roughly a second (test via `/dump KART.LC.sessionActive` in Client B's chat, or simpler: have a raider with Auto-Pass enabled roll on a real drop right after joining/reloading — the Blizzard roll frame should be auto-passed immediately, not require a second drop before it starts working). No Lua error on either client.

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua Core.lua
git commit -m "fix: request current session state and raid config on join/reload instead of waiting for a passive rebroadcast"
```

---

### Task 2: Auto-Need/Greed fallback when only Transmog is rollable

**Files:**
- Modify: `LootCouncil.lua:546-555` (`ForceWinRoll`)

**Interfaces:** None (self-contained, no callers change).

**Root cause (confirmed against Blizzard's API):** `GetLootRollItemInfo(rollID)` returns 13 values in this order: `texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired, canTransmog`. `ForceWinRoll` only ever reads the 6th/7th/8th values (`canNeed`/`canGreed`/`canDisenchant`); when an item is already known/BoE-restricted so none of those three are true and only Transmog is legal, the function falls through all three `if`/`elseif` branches and does nothing. `RollOnLoot`'s transmog roll type is `4` (confirmed against TrinityCore's `Loot.h`, which mirrors the real client/server protocol enum: `ROLL_TRANSMOG = 4` — Blizzard does not expose a named `LOOT_ROLL_TYPE_TRANSMOG` global for this one, unlike need/greed/disenchant, so the plain number is used with a comment explaining it).

- [ ] **Step 1: Read `canTransmog` and add the fallback branch**

Locate:

```lua
local function ForceWinRoll(rollID)
    local _, _, _, _, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    if canNeed then
        RollOnLoot(rollID, 1)
    elseif canGreed then
        RollOnLoot(rollID, 2)
    elseif canDisenchant then
        RollOnLoot(rollID, 3)
    end
end
```

Replace with:

```lua
local function ForceWinRoll(rollID)
    local _, _, _, _, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if canNeed then
        RollOnLoot(rollID, 1)
    elseif canGreed then
        RollOnLoot(rollID, 2)
    elseif canDisenchant then
        RollOnLoot(rollID, 3)
    elseif canTransmog then
        RollOnLoot(rollID, 4) -- roll type 4 = Transmog; Blizzard doesn't expose a named constant for it
    end
end
```

- [ ] **Step 2: Manual verification**

Needs a real drop where only Transmog is legal for the lootmaster (e.g. an item they've already collected the appearance for and can't Need/Greed/DE) — hard to force on demand; verify opportunistically on the next raid, or ask the lootmaster to check an item already in their "known appearances" list drops and confirm it's auto-claimed instead of sitting unrolled. At minimum, `/reload` after this change and confirm no Lua error (a wrong return-position/typo here would only surface as a silent no-op, not an error, so watch for the specific in-raid case rather than relying on `/reload` alone).

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: auto-claim Transmog-only rolls for the designated lootmaster"
```

---

### Task 3: Clear per-rollID state on tab close/session end; fix stale-item priority in HandleStart

**Files:**
- Modify: `LootCouncil.lua:502-507` (`LC.SetSessionActive`), `LootCouncil.lua:1501-1517` (`LC.CloseCouncilTab`), `LootCouncil.lua:3111-3128` (`LC.HandleStart`), new function after `LC.RemovePendingTrade` (`LootCouncil.lua:2751-2760`)

**Interfaces:**
- Produces: `LC.ClearRollState(rollID)` — called from `LC.CloseCouncilTab` and `LC.SetSessionActive(false)`; no return value.

**Root cause (confirmed):** No code path ever clears `LC.rollItems[rollID]`, `LC.votes[rollID]`, `LC.rolls[rollID]`, `LC.assignedWinners[rollID]`, or pending-trade entries — not when a tab is closed (`LC.CloseCouncilTab` only removes the tab from the tab strip) and not when a session ends (`LC.SetSessionActive(false)` only flips the flag). Blizzard's `rollID`s are small integers that get reused across encounters within a session, so this state persists into the next boss (Bug 11 — stale tabs). Worse, `LC.HandleStart` (run on every client that isn't the one physically rolling) does `LC.rollItems[rollID] = LC.rollItems[rollID] or GetLootRollItemLink(rollID) or "???"` — it prefers *any* pre-existing value over a fresh fetch, so if the same `rollID` was used by an earlier, already-closed roll from a previous boss, its old item link is silently kept forever, and that stale link is exactly what `LC.ShowAssignMenu`/`LC.AnnounceResult` later use for the right-click chat announcement and trade (Bug 4).

- [ ] **Step 1: Add `LC.ClearRollState`**

In `LootCouncil.lua`, immediately after `LC.RemovePendingTrade` (the function ending `table.remove(LC.pendingTrades, i)\n        end\n    end\n    LC.RefreshTradeReminder()\nend`), add:

```lua
-- Fully forgets rollID's tracked state (vote/roll data, cached item link, assigned winner, any
-- pending trade) — called when a tab is dismissed or a session ends, so a later real roll that
-- happens to reuse the same small rollID integer never inherits stale data from a previous boss
-- (see the "wrong item posted on right-click assign" and "stale tabs after next boss" reports).
function LC.ClearRollState(rollID)
    LC.votes[rollID]           = nil
    LC.rolls[rollID]           = nil
    LC.councilVotes[rollID]    = nil
    LC.rollItems[rollID]       = nil
    LC.rollDeadlines[rollID]   = nil
    LC.rollDurations[rollID]   = nil
    LC.assignedWinners[rollID] = nil
    LC.votedByMe[rollID]       = nil
    LC.votedNoteByMe[rollID]   = nil
    LC.councilTabsNew[rollID]  = nil
    LC.RemovePendingTrade(rollID)
end
```

- [ ] **Step 2: Call it from `LC.CloseCouncilTab`**

Locate:

```lua
function LC.CloseCouncilTab(rollID)
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    LC.councilTabsNew[rollID] = nil
```

Replace with:

```lua
function LC.CloseCouncilTab(rollID)
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    LC.ClearRollState(rollID)
```

(This subsumes the old standalone `LC.councilTabsNew[rollID] = nil` line, which is now inside `LC.ClearRollState`.)

- [ ] **Step 3: Clear every tracked rollID and hide the panel when a session ends**

Locate:

```lua
function LC.SetSessionActive(active)
    LC.sessionActive = active
    SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if active then LC.BroadcastRaidConfig() end
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end
```

Replace with:

```lua
function LC.SetSessionActive(active)
    LC.sessionActive = active
    SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if active then
        LC.BroadcastRaidConfig()
    else
        -- Ending the session forgets every tracked roll so the next boss starts clean instead of
        -- showing leftover tabs/votes from this one (see LC.ClearRollState).
        for i = #LC.councilTabs, 1, -1 do
            LC.ClearRollState(LC.councilTabs[i])
        end
        for i = #LC.voteListRolls, 1, -1 do
            LC.ClearRollState(LC.voteListRolls[i])
        end
        wipe(LC.councilTabs)
        wipe(LC.voteListRolls)
        LC.activeRollID = nil
        if LC.councilPanel then LC.councilPanel:Hide() end
        if LC.voteListFrame then LC.voteListFrame:Hide() end
    end
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end
```

- [ ] **Step 4: Fix `HandleStart`'s stale-value priority**

Locate:

```lua
    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = LC.rollItems[rollID] or GetLootRollItemLink(rollID) or "???"
```

Replace with:

```lua
    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID] or "???"
```

(A fresh fetch now always wins over whatever was previously cached for this `rollID`; the old value is only used as a fallback if the fresh fetch itself comes back nil — see Task 4 for what happens then.)

- [ ] **Step 5: Manual verification**

`/reload`, no Lua error (`wipe` is a standard Blizzard global, already used elsewhere in the addon — confirm with a quick grep if unsure). In a real or test raid: open the council panel with a couple of tabs, toggle the session off via the existing "Toggle session" button, confirm the council panel and vote-list window both close and `LC.councilTabs`/`LC.voteListRolls` are both empty (`/dump #KART.LC.councilTabs`). Start a new session and confirm a fresh roll on the next boss creates a brand-new tab with the correct item, not a leftover one.

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: clear per-roll state on tab close/session end so stale rollIDs never leak into the next boss"
```

---

### Task 4: Retry item-link resolution instead of permanently caching "???"

**Files:**
- Modify: `LootCouncil.lua:557-593` (`LC.OnStartLootRoll`, adds the new local helper right before it), `LootCouncil.lua:3111-3128` (`LC.HandleStart`)

**Interfaces:**
- Produces: a file-local `ResolveRollItemLink(rollID)` function, called from both `LC.OnStartLootRoll` and `LC.HandleStart`.
- Consumes: `LC.RefreshVoteListRows()`, `LC.RefreshCouncilRows()`, `LC.RefreshCouncilTabs()` (all pre-existing).

**Root cause (confirmed):** `GetLootRollItemLink(rollID)` can return `nil` for a moment right when `START_LOOT_ROLL` fires, before the loot data has fully propagated client-side (most common for a brand-new item, e.g. from a just-released raid boss). Both `LC.OnStartLootRoll:581` and `LC.HandleStart:3119` (after Task 3's fix) fall back to the literal string `"???"` when that happens, and nothing ever retries — `"???"` is truthy in Lua, so it sticks forever, and `IsRealItemLink("???")` is false, so the tooltip (`LootCouncil.lua:964-970`/`:1231-1237`) also never shows.

- [ ] **Step 1: Add the retry helper**

In `LootCouncil.lua`, locate:

```lua
-- =====================================================================
--  START_LOOT_ROLL handler  (called from Core.lua)
-- =====================================================================

-- Claims rollID by whatever roll type is actually available, strongest first — used only for the
```

Insert a new block between the section header and that comment:

```lua
-- =====================================================================
--  START_LOOT_ROLL handler  (called from Core.lua)
-- =====================================================================

-- GetLootRollItemLink(rollID) can return nil for a moment right when the roll starts (most common
-- for a brand-new item whose data hasn't finished propagating client-side yet). Retries a handful
-- of times with backoff instead of permanently giving up — bails early if rollID's entry was
-- resolved by some other path in the meantime, or cleared entirely (tab closed/session ended, see
-- LC.ClearRollState), so a long-since-irrelevant timer never resurrects a forgotten roll.
local function ResolveRollItemLink(rollID, attempt)
    if LC.rollItems[rollID] ~= "???" then return end
    attempt = attempt or 1
    local link = GetLootRollItemLink(rollID)
    if link then
        LC.rollItems[rollID] = link
        LC.RefreshVoteListRows()
        if LC.councilPanel and LC.councilPanel:IsShown() then
            LC.RefreshCouncilRows()
            LC.RefreshCouncilTabs()
        end
    elseif attempt < 8 then
        C_Timer.After(0.25 * attempt, function() ResolveRollItemLink(rollID, attempt + 1) end)
    end
end

-- Claims rollID by whatever roll type is actually available, strongest first — used only for the
```

- [ ] **Step 2: Trigger the retry from `OnStartLootRoll`**

Locate:

```lua
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or "???"
    LC.votes[rollID]     = LC.votes[rollID] or {}
```

Replace with:

```lua
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
    LC.votes[rollID]     = LC.votes[rollID] or {}
```

- [ ] **Step 3: Trigger the retry from `HandleStart`**

Locate (this is the line Task 3 Step 4 already changed):

```lua
    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID] or "???"
```

Replace with:

```lua
    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID] or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
```

- [ ] **Step 4: Manual verification**

`/reload`, no Lua error. Hard to force a genuine `GetLootRollItemLink` miss on demand; verify opportunistically on the next fresh-tier boss kill — confirm an item that used to show "???" now either shows correctly right away or (if it briefly shows "???") corrects itself within a couple of seconds without needing any manual action, and that its tooltip works once it does.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: retry item-link resolution instead of permanently showing ??? for freshly-dropped loot"
```

---

### Task 5: Loot history — store rollID, replace instead of append on reassignment

**Files:**
- Modify: `LootCouncil.lua:2545-2578` (`LC.LogHistory`), `LootCouncil.lua:2690-2712` (`DoAssignWinner`), `LootCouncil.lua:3198-3226` (`LC.HandleResult`)

**Interfaces:**
- Changes `LC.LogHistory`'s signature from `LC.LogHistory(itemLink, winnerShort, reason, classFile, colorDef)` to `LC.LogHistory(itemLink, winnerShort, reason, classFile, colorDef, rollID)` — the new `rollID` parameter is optional (nil is handled) so any other future caller isn't forced to supply it, but both existing call sites are updated to pass it.

**Root cause (confirmed):** History entries never store which `rollID` they came from, so there's no way to tell "this is a new entry for the same physical item" from "this is an unrelated new win." `LC.LogHistory`'s only de-dup guard compares the last 3 entries for an identical `item + winner + reason` within 5 seconds — a genuine reassignment (different winner and/or reason) always misses that guard and gets appended, leaving the old entry for the same item behind.

- [ ] **Step 1: Store `rollID` on new entries and replace any existing entry for the same `rollID`**

Locate:

```lua
function LC.LogHistory(itemLink, winnerShort, reason, classFile, colorDef)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- Guards against double-logging the same win if a redelivered/duplicate LC_RESULT addon
    -- message ever reaches this client twice (HandleResult has no dedup of its own, unlike the
    -- history catch-up sync path in HandleHistoryEntry below). Only checks the most recent entries
    -- within the last few seconds — a genuine duplicate would land back-to-back, whereas a real
    -- re-roll of the exact same item to the exact same winner minutes later is a separate event.
    for i = #KART_LootHistory, math.max(1, #KART_LootHistory - 3), -1 do
        local e = KART_LootHistory[i]
        if e.item == (itemLink or "") and e.winner == (winnerShort or "") and e.reason == (reason or "")
           and now - (e.time or 0) < 5 then
            return
        end
    end

    local _, _, _, difficultyName = GetInstanceInfo()
    table.insert(KART_LootHistory, {
        time       = now,
        item       = itemLink or "",
        winner     = winnerShort or "",
        reason     = reason or "",
        class      = classFile,
        color      = colorDef and {r = colorDef.r, g = colorDef.g, b = colorDef.b} or nil,
        difficulty = difficultyName or "",
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end
```

Replace with:

```lua
function LC.LogHistory(itemLink, winnerShort, reason, classFile, colorDef, rollID)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- Guards against double-logging the same win if a redelivered/duplicate LC_RESULT addon
    -- message ever reaches this client twice (HandleResult has no dedup of its own, unlike the
    -- history catch-up sync path in HandleHistoryEntry below). Only checks the most recent entries
    -- within the last few seconds — a genuine duplicate would land back-to-back, whereas a real
    -- re-roll of the exact same item to the exact same winner minutes later is a separate event.
    for i = #KART_LootHistory, math.max(1, #KART_LootHistory - 3), -1 do
        local e = KART_LootHistory[i]
        if e.item == (itemLink or "") and e.winner == (winnerShort or "") and e.reason == (reason or "")
           and now - (e.time or 0) < 5 then
            return
        end
    end

    -- A reassignment (LC.AssignWinner called again for a rollID that was already assigned) must
    -- replace its previous history entry, not sit alongside it — otherwise the same physical item
    -- shows up twice in history with two different winners. Also requires the item to match:
    -- rollID alone is Blizzard's small, recyclable roll-ID integer, not a permanent identifier —
    -- KART_LootHistory is a persistent SavedVariable that can span weeks/months, so matching on
    -- rollID alone risks deleting an unrelated older entry once that small number gets reused for
    -- a completely different item (found in review, confirmed with the project owner).
    if rollID then
        for i = #KART_LootHistory, 1, -1 do
            if KART_LootHistory[i].rollID == rollID and KART_LootHistory[i].item == (itemLink or "") then
                table.remove(KART_LootHistory, i)
                break
            end
        end
    end

    local _, _, _, difficultyName = GetInstanceInfo()
    table.insert(KART_LootHistory, {
        time       = now,
        item       = itemLink or "",
        winner     = winnerShort or "",
        reason     = reason or "",
        class      = classFile,
        color      = colorDef and {r = colorDef.r, g = colorDef.g, b = colorDef.b} or nil,
        difficulty = difficultyName or "",
        rollID     = rollID,
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end
```

- [ ] **Step 2: Pass `rollID` from `DoAssignWinner`**

Locate:

```lua
    else
        LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef)
        LC.AddPendingTrade(rollID, playerShort)
    end
```

Replace with:

```lua
    else
        LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef, rollID)
        LC.AddPendingTrade(rollID, playerShort)
    end
```

- [ ] **Step 3: Pass `rollID` from `HandleResult`**

Locate:

```lua
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason))
end
```

Replace with:

```lua
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason), rollID)
end
```

- [ ] **Step 4: Manual verification**

`/reload`. Run a test roll (`/kart` → Loot Council → Test), assign it to a candidate, open the Loot History window and confirm one entry appears. Assign the *same* test roll to a different candidate (reassignment confirm popup) and confirm the history window now still shows exactly one entry for that item — updated to the new winner, not two entries.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: replace the existing loot-history entry on reassignment instead of appending a duplicate"
```

---

### Task 6: Populate the Auto-Trade list on the actual item holder's client

**Files:**
- Modify: `LootCouncil.lua:2690-2712` (`DoAssignWinner`), `LootCouncil.lua:3198-3226` (`LC.HandleResult`)

**Interfaces:** None new — both call sites already have `LC.AddPendingTrade`/`LC.GetLootmaster`/`LC.IsMe` in scope.

**Root cause (confirmed):** `LC.AddPendingTrade` is only ever called from `DoAssignWinner`, which runs on whichever client performs the right-click assignment (normally the raid leader, since the council panel that exposes the right-click menu is only shown to the leader). But the physical item always ends up in the *designated lootmaster's* bags (via `ForceWinRoll`, Task 2's function) — a separately-configured person who is frequently not the raid leader. `LC.HandleResult`, which runs on every other client including the lootmaster's own, never calls `LC.AddPendingTrade` at all. So whenever leader ≠ lootmaster, the reminder list is populated on the person who doesn't have the item, and never populated on the person who does.

- [ ] **Step 1: Gate `DoAssignWinner`'s call to only the actual item holder**

Locate:

```lua
    else
        LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef, rollID)
        LC.AddPendingTrade(rollID, playerShort)
    end
```

Replace with:

```lua
    else
        LC.LogHistory(LC.rollItems[rollID], playerShort, reason, classFile, colorDef, rollID)
        -- Only the client that actually holds the item (the designated lootmaster, see
        -- LC.GetLootmaster/ForceWinRoll) needs a trade reminder — when the assigner (usually the
        -- raid leader) isn't also the lootmaster, they never physically have the item to trade.
        if LC.IsMe(LC.GetLootmaster()) then
            LC.AddPendingTrade(rollID, playerShort)
        end
    end
```

- [ ] **Step 2: Add the same call to `HandleResult`, gated the same way**

Locate (the line Task 5 Step 3 already changed):

```lua
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason), rollID)
end
```

Replace with:

```lua
    LC.LogHistory(LC.rollItems[rollID], winner, reason, classFile, LC.ResolveColorForReason(reason), rollID)

    -- Same reasoning as DoAssignWinner: only the client physically holding the item (the
    -- designated lootmaster) needs a pending-trade reminder, regardless of who assigned it.
    if LC.IsMe(LC.GetLootmaster()) then
        LC.AddPendingTrade(rollID, winner)
    end
end
```

- [ ] **Step 3: Manual verification (needs two clients, and a raid leader ≠ lootmaster setup)**

On Client A (raid leader, NOT the designated lootmaster), set Client B's character as the designated lootmaster in the Loot Council raid-wide settings. Run a real or test roll, right-click assign it to some third candidate from Client A's council panel. Confirm the Auto-Trade reminder window appears on **Client B** (the lootmaster) listing the item, and does **not** appear on Client A.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: populate the auto-trade reminder on the lootmaster's client, not the assigner's"
```

---

### Task 7: Remove Auto-Trade entries only after a trade actually completes

**Files:**
- Modify: `LootCouncil.lua:2863-2899` (`LC.OnTradeShow`), new function directly after it
- Modify: `Core.lua:20` (event registration), `Core.lua:219-221` (event switch)

**Interfaces:**
- Produces: `LC.OnTradeClosed()` — called from `Core.lua`'s event switch on `TRADE_CLOSED`; no return value.

**Root cause (confirmed):** `LC.OnTradeShow` calls `LC.RemovePendingTrade(entry.rollID)` the moment the item is *placed* into a trade slot (`ClickTradeButton(freeSlot)`), not when the trade is actually accepted — so if the trade is later cancelled by either side, the entry is already gone even though nothing was actually handed over. Conversely, if placement fails silently (bag not found, all 6 trade slots already full, cursor busy), the entry is never removed even after the item is later traded some other way — there is no retry and no completion check either direction.

- [ ] **Step 1: Stop removing the entry at placement time; remember the trade partner**

Locate:

```lua
function LC.OnTradeShow()
    if KART_Settings.lcModuleEnabled == false then return end
    if #LC.pendingTrades == 0 then return end

    local partnerName = UnitName("npc") -- the trade-partner unit token, a historical quirk of the trade API
    if not partnerName and TradeFrameRecipientNameText then ---@diagnostic disable-line: undefined-global
        partnerName = TradeFrameRecipientNameText:GetText() ---@diagnostic disable-line: undefined-global
    end
    if not partnerName then return end
    local partnerShort = partnerName:match("([^%-]+)") or partnerName

    for _, entry in ipairs(LC.pendingTrades) do
        -- Bail if the cursor is already carrying something (e.g. the player was mid-drag of an
        -- unrelated item) — picking up our item now would swap it into whatever slot that is.
        if entry.winnerShort == partnerShort and not GetCursorInfo() then ---@diagnostic disable-line: undefined-global
            local bag, slot = FindItemInBags(entry.itemLink)
            if bag then
                local freeSlot
                for i = 1, 6 do -- MAX_TRADE_ITEMS, fixed by the trade UI
                    if not GetTradePlayerItemLink(i) then ---@diagnostic disable-line: undefined-global
                        freeSlot = i
                        break
                    end
                end
                if freeSlot then
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(freeSlot) ---@diagnostic disable-line: undefined-global
                    LC.RemovePendingTrade(entry.rollID)
                end
            end
        end
    end
end
```

Replace with:

```lua
function LC.OnTradeShow()
    if KART_Settings.lcModuleEnabled == false then return end

    local partnerName = UnitName("npc") -- the trade-partner unit token, a historical quirk of the trade API
    if not partnerName and TradeFrameRecipientNameText then ---@diagnostic disable-line: undefined-global
        partnerName = TradeFrameRecipientNameText:GetText() ---@diagnostic disable-line: undefined-global
    end
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
            local bag, slot = FindItemInBags(entry.itemLink)
            if bag then
                local freeSlot
                for i = 1, 6 do -- MAX_TRADE_ITEMS, fixed by the trade UI
                    if not GetTradePlayerItemLink(i) then ---@diagnostic disable-line: undefined-global
                        freeSlot = i
                        break
                    end
                end
                if freeSlot then
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(freeSlot) ---@diagnostic disable-line: undefined-global
                    -- Not removed here anymore — only once the trade actually completes (see
                    -- LC.OnTradeClosed), so a cancelled trade doesn't silently drop the reminder.
                end
            end
        end
    end
end

-- Runs when the trade window closes for any reason (completed, cancelled, partner walked away).
-- The only reliable way to tell "did it actually go through" is to check whether the item is
-- still in our bags: if it's gone, the trade succeeded and the reminder can be cleared; if it's
-- still there, nothing happened and the entry stays pending so the next trade attempt retries it.
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    LC.currentTradePartnerShort = nil
    if not partnerShort then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerShort == partnerShort and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end
```

- [ ] **Step 2: Register `TRADE_CLOSED` in `Core.lua`**

Locate:

```lua
frame:RegisterEvent("TRADE_SHOW")
```

Replace with:

```lua
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
```

- [ ] **Step 3: Dispatch it to `LC.OnTradeClosed`**

Locate:

```lua
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.OnTradeShow() end
```

Replace with:

```lua
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.OnTradeClosed() end
```

- [ ] **Step 4: Manual verification (needs two clients)**

As the lootmaster with a pending trade for player B: open a trade with B, confirm the item auto-places into a slot (unchanged behaviour), then **cancel** the trade — confirm the Auto-Trade reminder window still lists that item (it must NOT have been removed). Open the trade again with B and this time **complete** it — confirm the reminder entry disappears once the trade window closes.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua Core.lua
git commit -m "fix: only clear an auto-trade reminder once the trade actually completes, not on mere placement"
```

---

### Task 8: Slash-command reopen for the LootCouncil window and the Auto-Trade reminder

**Files:**
- Modify: `Core.lua:634-650` (`SlashCmdList["KART"]`)

**Interfaces:** None new — reuses `KART.LC.councilPanel`, `KART.LC.voteListFrame`, `KART.LC.tradeReminderFrame`, `KART.LC.councilTabs`, `KART.LC.voteListRolls`, `KART.LC.pendingTrades` (all pre-existing globals on the `LC` table).

**Root cause (confirmed):** Both windows only ever hide (via their close button, or via Escape through `UISpecialFrames`) and only ever reappear automatically the next time their underlying data changes (a new roll, a newly pending trade) — there is no manual way to bring back a window for data that's already being tracked.

- [ ] **Step 1: Add `lc` and `trade` subcommands**

Locate:

```lua
SLASH_KART1 = "/kart"
SlashCmdList["KART"] = function(msg) -- Slash-Befehl zum Öffnen/Schließen des Hauptfensters
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "version" or cmd == "v" then
        local channel = "GUILD"
        if IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY" end
        print(KART.L.VERSION_CHECK_REQ or "KART: Fordere Versionen an...")
        KART.VersionCheckActive = true
        C_Timer.After(5, function() KART.VersionCheckActive = false end)
        C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", channel)
    else
```

Replace with:

```lua
SLASH_KART1 = "/kart"
SlashCmdList["KART"] = function(msg) -- Slash-Befehl zum Öffnen/Schließen des Hauptfensters
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "version" or cmd == "v" then
        local channel = "GUILD"
        if IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY" end
        print(KART.L.VERSION_CHECK_REQ or "KART: Fordere Versionen an...")
        KART.VersionCheckActive = true
        C_Timer.After(5, function() KART.VersionCheckActive = false end)
        C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", channel)
    elseif cmd == "lc" then
        -- Reopens whichever Loot Council window still has tracked, unfinished rolls — does
        -- nothing (rather than error) if there's genuinely nothing being tracked right now.
        if KART.LC then
            if KART.LC.councilPanel and #KART.LC.councilTabs > 0 then
                KART.LC.councilPanel:Show()
            elseif KART.LC.voteListFrame and #KART.LC.voteListRolls > 0 then
                KART.LC.voteListFrame:Show()
            end
        end
    elseif cmd == "trade" then
        if KART.LC and KART.LC.tradeReminderFrame and #KART.LC.pendingTrades > 0 then
            KART.LC.tradeReminderFrame:Show()
        end
    else
```

- [ ] **Step 2: Manual verification**

Start a test roll (`/kart` → Loot Council → Test), close the vote/council window via its X button, run `/kart lc` and confirm it reopens. With a pending auto-trade entry present, close the reminder window (Escape) and run `/kart trade` and confirm it reopens. Run `/kart lc` and `/kart trade` with nothing tracked (empty tabs/pending list) and confirm neither errors nor pops open an empty window.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "feat: add /kart lc and /kart trade to reopen closed Loot Council/Auto-Trade windows"
```

---

### Task 9: Fix header-only drag on the Council Panel and Loot History window

**Files:**
- Modify: `LootCouncil.lua:1711-1714` (Council Panel header)
- Modify: `LootHistory.lua:255-258` (Loot History header)

**Interfaces:** None.

**Root cause (confirmed):** Both windows' title-bar strip (`hdr`) has `hdr:EnableMouse(true)` with no matching `hdr:RegisterForDrag`/`OnDragStart` — so `hdr` (which sits on top of the frame's own draggable area) swallows mouse-downs over the title without doing anything with them, leaving only the body (everywhere `hdr` doesn't cover) draggable.

- [ ] **Step 1: Make the Council Panel header draggable**

In `LootCouncil.lua`, locate:

```lua
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    KART.CreateHeaderLine(f, -28)
```

Replace with:

```lua
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    hdr:RegisterForDrag("LeftButton")
    hdr:SetScript("OnDragStart", function() f:StartMoving() end)
    hdr:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcCouncilPanelPos = {x = f:GetLeft(), y = f:GetTop()}
        end
    end)
    KART.CreateHeaderLine(f, -28)
```

(This duplicates the position-save logic from `f`'s own `OnDragStop` at `LootCouncil.lua:1692-1697` — dragging via the header has to persist the position the same way dragging via the body already does.)

- [ ] **Step 2: Make the Loot History header draggable**

In `LootHistory.lua`, locate:

```lua
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
```

Replace with:

```lua
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    hdr:RegisterForDrag("LeftButton")
    hdr:SetScript("OnDragStart", function() f:StartMoving() end)
    hdr:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcHistoryWindowPos = {x = f:GetLeft(), y = f:GetTop()}
        end
    end)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
```

- [ ] **Step 3: Manual verification**

`/reload`. Open the Council Panel (Test mode is fine) and drag it by clicking directly on the title text/bar — confirm it moves. Close and reopen (`/kart lc` from Task 8, or `/reload`) and confirm it reopened at the dragged position. Repeat for the Loot History window (drag by its title bar, reopen, confirm position persisted).

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua LootHistory.lua
git commit -m "fix: make the Council Panel and Loot History title bars actually draggable"
```

---

### Task 10: Exempt Toys and other Miscellaneous-class items from the min-quality filter

**Files:**
- Modify: `LootCouncil.lua:557-593` (`LC.OnStartLootRoll`, the quality-gate section)

**Interfaces:** None.

**Root cause (confirmed):** The gate is a pure rarity check (`if quality and quality < minQuality then return end`) with no item-class awareness at all, even though the codebase already has a working classID-based pattern to build on (`LC.GetItemArmorRank`, which reads `classID`/`subclassID` off `C_Item.GetItemInfo`). Toys are virtually always Common/Uncommon quality, and Player Housing decor items (Patch 12.0) are not equipment either — both get silently skipped before Council ever sees them. There is no dedicated, queryable "is this a housing decor item" API yet (checked — Blizzard's `C_HousingCatalog` namespace only covers browsing/placing items you already own, not classifying an arbitrary loot link), so this fix exempts item class 15 ("Miscellaneous") as a whole — the same catch-all class Blizzard has used for over a decade for toys, pets, mounts, and other non-equipment collectibles, and the most plausible home for housing decor drops too.

- [ ] **Step 1: Add the class-exemption check**

Locate:

```lua
    -- Below the raid-wide minimum rarity: let Blizzard's own roll UI handle it, untouched.
    local _, _, _, quality = GetLootRollItemInfo(rollID)
    local minQuality = LC.GetRaidMinQuality()
    if quality and quality < minQuality then return end
```

Replace with:

```lua
    -- Below the raid-wide minimum rarity: let Blizzard's own roll UI handle it, untouched — unless
    -- it's a Miscellaneous-class item (classID 15: toys, pets, mounts, housing decor, and similar
    -- non-equipment collectibles), which is never gated on rarity since it's virtually always
    -- Common/Uncommon regardless of how desirable it is.
    local _, _, _, quality = GetLootRollItemInfo(rollID)
    local minQuality = LC.GetRaidMinQuality()
    local itemLink = GetLootRollItemLink(rollID)
    local classID = IsRealItemLink(itemLink) and select(12, C_Item.GetItemInfo(itemLink))
    if quality and quality < minQuality and classID ~= 15 then return end
```

- [ ] **Step 2: Manual verification**

Set the raid min-quality to Epic. Run a test roll (`/kart` → Loot Council → Test) — test items are fake coloured strings, not real toys, so this specifically needs a real drop: on the next raid, confirm a dropped toy or (once available) a housing decor item is picked up by Council even though it's below Epic, while a genuine sub-Epic equippable item is still correctly skipped.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: never let the min-quality rule filter out toys, pets, mounts, or housing decor"
```

---

### Task 11: Enlarge the vote window's close button

**Files:**
- Modify: `LootCouncil.lua:642-643` (`LC.CreateVoteList`)

**Interfaces:** None.

**Root cause (confirmed):** This is the only close button in the codebase sized `20x20` — every other window's (Council Panel, Loot History, Trade Reminder popups) is `22x22`.

- [ ] **Step 1: Match the standard close-button size**

Locate:

```lua
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
```

Replace with:

```lua
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
```

- [ ] **Step 2: Manual verification**

`/reload`, open the vote list window (Test mode), confirm the × button is visibly the same size as the Council Panel's and clicking anywhere within the enlarged hitbox closes it.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: enlarge the vote window's close button to match every other window"
```

---

### Task 12: Automatically refresh version info on group join (fixes the false "no KART" indicator)

**Files:**
- Modify: `Core.lua:222-233` (`GROUP_ROSTER_UPDATE` handler)

**Interfaces:** None new — reuses the existing `"REQ_VERSION"`/`"VERSION:"` request/response pair (already used by `/kart v`).

**Root cause (confirmed):** `KART.PlayerVersions`/`KART.PlayerLCEnabled` are populated only by each player's own one-shot `"ANNOUNCE_VERSION:"` broadcast (sent once per group-membership, gated by `KART.VersionAnnouncedToGroup`). A late joiner never receives that broadcast retroactively from players who already announced before they joined — their `RefreshCouncilRows` reads `KART.PlayerVersions[short]` as `nil` for those players and shows the "No KART detected" status (`LC_STATUS_NO_KART`) even though `/kart v` (which does a full request/response round-trip) proves everyone is current. This does not explain every part of Bug 14 — see "Known gaps" below for the part this task doesn't fix.

- [ ] **Step 1: Request a fresh version round-trip whenever we announce our own**

Locate:

```lua
        if IsInGroup() and not KART.VersionAnnouncedToGroup then
            local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
            C_ChatInfo.SendAddonMessage("KART", "ANNOUNCE_VERSION:" .. KART.Version .. ":" .. lcFlag, IsInRaid() and "RAID" or "PARTY")
            KART.VersionAnnouncedToGroup = true
        elseif not IsInGroup() then
            KART.VersionAnnouncedToGroup = false
        end
```

Replace with:

```lua
        if IsInGroup() and not KART.VersionAnnouncedToGroup then
            local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
            C_ChatInfo.SendAddonMessage("KART", "ANNOUNCE_VERSION:" .. KART.Version .. ":" .. lcFlag, IsInRaid() and "RAID" or "PARTY")
            KART.VersionAnnouncedToGroup = true
            -- Our own one-shot announce only tells the group about US — it does nothing for
            -- players who already announced before we joined, so also pull everyone else's
            -- current version the same way /kart v already does, instead of only finding out
            -- about mismatches/missing-KART players whenever someone happens to run that manually.
            C_ChatInfo.SendAddonMessage("KART", "REQ_VERSION", IsInRaid() and "RAID" or "PARTY")
        elseif not IsInGroup() then
            KART.VersionAnnouncedToGroup = false
        end
```

- [ ] **Step 2: Manual verification (needs two clients)**

Client A already in a raid. Client B joins. On Client B, confirm (via `/dump KART.PlayerVersions`) that Client A's version is populated within a couple of seconds of joining, without needing to run `/kart v` manually. Open the Loot Council panel on Client B and confirm Client A doesn't show a false "No KART detected" warning.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "fix: request everyone's current version on join instead of only announcing our own"
```

---

### Task 13: BuffChecker — match buffs by spell ID instead of localized name substrings

**Files:**
- Modify: `BuffChecker.lua:7-19` (`KART.BuffData`, adds `spells` lists), `BuffChecker.lua:670-700` (the match logic)

**Interfaces:** None — `KART.BuffData` entries and the match loop are both internal to `BuffChecker.lua`.

**Root cause (confirmed):** Unlike `int`/`sta`/`motw`/`shout`/`bronze`/`sky`/`rune` (all matched by a real `spells = {spellID, ...}` list), the `food` entry has no spell IDs at all — detection depends entirely on `aura.name:find("Satt")` (German) / `aura.name:find("Well Fed")` (English) substrings, plus a non-standard `aura.isFullFood` field. This is the exact class of bug already fixed once for `RaidleadBar.lua`'s `/cwm all` keyword (see `CHANGELOG.md:51`, "Bugfix worldmaker" in the bug report) — a hardcoded localized string that silently fails whenever the buff's actual display text doesn't literally contain the expected substring.

This plan fixes the `food` buff specifically (the one reported broken); `flask`, `rune`, and `oil` use the same substring-matching pattern (`BuffChecker.lua:683-696`) but were not reported as broken, so per the project's surgical-changes convention they are left untouched here — flagged in "Known gaps" below as the same risk, not fixed pre-emptively.

**Spell IDs (confirmed against Wowhead's current live spell data, patch 12.0.7/12.1.0):** the raid brought 4 current-tier feasts — [Silvermoon Parade](https://www.wowhead.com/item=255845/silvermoon-parade), [Quel'dorei Medley](https://www.wowhead.com/item=242272/queldorei-medley), [Harandar Celebration](https://www.wowhead.com/item=255846/harandar-celebration), and [Blooming Feast](https://www.wowhead.com/item=242273/blooming-feast) — each of which also has a "Hearty" variant (e.g. Hearty Silvermoon Parade). All of them place a feast that, once eaten for 10+ seconds, grants the *same* two possible generic buffs regardless of which specific feast: **"Well Fed"** (spell ID `1232585`) from a regular feast, or **"Hearty Well Fed"** (spell ID `1233713`) from a Hearty one — both are auras (buffs), not the item-use/placement spell, and both are locale-independent (the same spell ID applies to every client regardless of language). This is why one `spells` list covering both IDs is enough for every current feast, without needing one entry per item.

- [ ] **Step 1: Add the spell IDs**

Locate:

```lua
    { id = "food",   label = L.BC_LABEL_FOOD,   col = 8, icon = 134062,  isFood = true, report = "item", reportLabel = L.BC_REPORT_FOOD },
```

Replace with:

```lua
    { id = "food",   label = L.BC_LABEL_FOOD,   col = 8, icon = 134062,  spells = {1232585, 1233713}, isFood = true, report = "item", reportLabel = L.BC_REPORT_FOOD },
```

- [ ] **Step 2: Keep the substring match only as a fallback, not the primary check**

Locate:

```lua
                    if buff.isFood and (aura.isFullFood or aura.name:find("Satt") or aura.name:find("Well Fed")) then match = true end
```

Replace with:

```lua
                    if buff.isFood and not match and (aura.name:find("Satt") or aura.name:find("Well Fed")) then match = true end
```

(The `buff.spells` check earlier in the same loop — `if buff.spells and type(aura.spellId) == "number" then ... end` — now runs first and sets `match = true` via spell ID `1232585`/`1233713` for both German and English clients identically; this line becomes a fallback only for a feast/food this plan didn't account for, dropping the non-standard `aura.isFullFood` field entirely since it was never a documented `AuraData` field.)

- [ ] **Step 3: Manual verification**

On a German client: eat one of the 4 current feasts (or its Hearty variant) long enough to become Well Fed, open BuffCheck, confirm the Food column shows active. Repeat on an English client. If a raider is using food from a source other than these 4 current feasts (e.g. a leftover older consumable), confirm the substring fallback from Step 2 still catches its English/German "Well Fed"/"Satt" text so it doesn't regress from before this fix.

- [ ] **Step 4: Commit**

```bash
git add BuffChecker.lua
git commit -m "fix: match the food buff by spell ID so it's detected correctly on non-English clients"
```

---

### Task 14: Manual verification pass for the "narrowed but not provably eliminated" bugs

**Files:** None — this is a verification-only task, no code changes.

This task exists because Task 1 substantially shrinks (but doesn't mathematically eliminate) the race window behind Bug 12, and because Bug 14's "some players show nothing at all" symptom was investigated in depth (see "Known gaps" below) without a conclusive fix. Rather than shipping speculative code for symptoms that couldn't be root-caused, this task asks the reporter to specifically watch for these on the next raid, now that Tasks 1–13 are in:

- [ ] **Step 1:** Over the next 1-2 raids, note whether Bug 12 (vote shown as wrong label) still occurs at all, and if so, whether it's during the first few seconds after someone joins/reloads (expected, tiny residual window) or persists longer (would mean Task 1 didn't fully address it and needs re-investigation).
- [ ] **Step 2:** For Bug 14's "shows nothing" symptom specifically (not the "no KART" indicator, which Task 12 fixes): if it recurs, capture `/dump KART.LC.votes[<rollID>]` on the viewer's client and ask the affected player to confirm (via `/dump KART.LC.votedByMe`) that their client believes it already sent the vote. That comparison is what would confirm or rule out the message-delivery vs. rendering hypotheses from the investigation.
- [ ] **Step 3:** No commit — this task only produces information for a possible follow-up plan.

---

### Task 15: Changelog and version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

**Interfaces:** None (docs only).

- [ ] **Step 1: Bump the addon version**

In `KeineAhnungRaidTools.toc`, change:

```
## Version: 2.4.0
```

to:

```
## Version: 2.5.0
```

- [ ] **Step 2: Add the English changelog entry**

In `CHANGELOG.md`, insert a new section above the existing `## [2.4.0] - 2026-07-19` entry:

```markdown
## [2.5.0] - 2026-07-22
### Fixed
- **Loot Council session state (session on/off, min-quality, vote labels, opt-in rolls) now syncs immediately when you join or `/reload`**, instead of only updating on the next roster change.
- **The designated lootmaster's auto-Need/Greed now also claims Transmog-only rolls**, instead of doing nothing.
- **Right-click assignment and the loot-history log no longer confuse items across bosses**, and a reassigned item replaces its old history entry instead of duplicating it.
- **Freshly-dropped loot no longer gets stuck showing "???"** in the vote window or council panel.
- **The Auto-Trade reminder now tracks correctly when the raid leader isn't the designated lootmaster**, and only clears an entry once the trade actually completes.
- **The Loot Council and Auto-Trade windows can be reopened with `/kart lc` and `/kart trade`** after closing them.
- **The Council Panel and Loot History windows can now be dragged by their title bar**, not just the body.
- **Toys, pets, mounts, and housing decor are no longer filtered out by the minimum-quality rule.**
- **The vote window's close button is bigger and easier to click.**
- **A player's KART status no longer falsely shows "not installed" right after joining.**
- **BuffCheck's food-buff detection now works correctly on German clients.**
```

- [ ] **Step 3: Mirror into German changelog**

In `CHANGELOG-de.md`, insert at the same relative position:

```markdown
## [2.5.0] - 2026-07-22
### Fixed
- **Der Loot-Council-Sitzungsstatus (An/Aus, Mindestqualität, Stimm-Labels, Opt-in-Würfe) synchronisiert sich jetzt sofort beim Beitreten/`/reload`**, statt erst bei der nächsten Rosteränderung.
- **Das automatische Need/Greed des Lootmasters beansprucht jetzt auch reine Transmog-Würfe**, statt nichts zu tun.
- **Rechtsklick-Zuweisung und Loot-Historie verwechseln Items nicht mehr zwischen Bossen**, und eine Neuzuteilung ersetzt den alten Historieneintrag statt ihn zu duplizieren.
- **Frisch gedroppte Beute bleibt nicht mehr dauerhaft bei "???" hängen** im Abstimmungsfenster oder Council-Panel.
- **Die Auto-Trade-Erinnerung funktioniert jetzt korrekt, wenn Raidleiter und Lootmaster unterschiedliche Personen sind**, und löscht einen Eintrag erst, wenn der Trade wirklich abgeschlossen ist.
- **Loot-Council- und Auto-Trade-Fenster lassen sich mit `/kart lc` und `/kart trade`** nach dem Schließen wieder öffnen.
- **Council-Panel und Loot-Historie lassen sich jetzt an der Titelleiste ziehen**, nicht nur am Fensterkörper.
- **Spielzeuge, Begleiter, Mounts und Wohnungsdeko werden nicht mehr von der Mindestqualitäts-Regel herausgefiltert.**
- **Der Schließen-Button im Abstimmungsfenster ist größer und leichter zu treffen.**
- **Der KART-Status eines Spielers zeigt nach dem Beitreten nicht mehr fälschlich "nicht installiert" an.**
- **Die Essensbuff-Erkennung im BuffCheck funktioniert jetzt auch auf deutschen Clients korrekt.**
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version to 2.5.0, changelog for the loot council bugfix pass"
```

---

## Known gaps — not fixed by this plan

Investigated in depth but no code-level cause could be confirmed; documented here instead of shipping a speculative fix, per the project's simplicity convention.

- **Bug 14, "some players show nothing, as if they never voted":** Confirmed this is *not* caused by `kartStatus`/the "no KART" indicator suppressing vote display — `RefreshCouncilRows` renders `voteText` independently of `kartStatus` (only a small warning icon depends on it). The vote-cast path itself (`LootCouncil.lua:1030-1052`) is also not gated by `LC.sessionActive`. No other static cause was found. Task 14 above sets up the specific comparison (`LC.votes[rollID]` on the viewer vs. `LC.votedByMe` on the voter) that would confirm whether this is a message-delivery issue or something else, next time it recurs.
- **Bug 16, LootCouncil window not shown for players on a different realm:** The broadcast path (`SendLC`/`CHAT_MSG_ADDON` on the RAID/PARTY channel) has no realm-based filtering anywhere in the addon, so on paper it should reach everyone. This may be a Blizzard-side limitation on addon-message delivery to certain cross-realm/connected-realm group configurations rather than an addon bug at all — if so, no code fix is possible, and `/kart lc` (Task 8) is the affected player's manual fallback once they notice Blizzard's own roll frame pop up with no KART window alongside it.
- **Bug 20, windows randomly open/close for one player:** `LC.RefreshVoteListRows` unconditionally re-shows the window while any roll is pending — confirmed deliberate, and it runs identically for everyone, so it doesn't explain a single-player-only symptom. No other trigger was found.
- **Realm-qualified identity (contributing factor for 14/16/20):** every vote/roll/version table in the addon is keyed by short character name only, with no realm suffix, everywhere in `LootCouncil.lua`/`Core.lua`. Two players who happen to share a short name (plausible in a larger or cross-realm raid) would silently collide. Fixing this properly means re-keying every one of these tables consistently — a much larger, separately-scoped change, not something to fold into this bugfix pass.
