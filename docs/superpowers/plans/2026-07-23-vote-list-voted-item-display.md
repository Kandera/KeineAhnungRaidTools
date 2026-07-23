# Vote-List Voted-Item Display Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a personal three-way setting controlling what happens to a vote-list item once the local player has voted on it (`full` = today's behavior, `shrink` = card shrinks but stays visible, `hide` = disappears entirely from both layouts), plus `/kart showall` to reveal hidden items again.

**Architecture:** A new `Vote.GetVisibleRolls()` function (`LootCouncilVote.lua`) becomes the single source of "which rollIDs to actually render," used by both layout renderers and the shared countdown ticker's fast-path — everywhere else (expiry, vote state, pending trades) keeps operating on the full `LC.voteListRolls` unchanged. The three-way setting is a `KART.CreateModernButton` + `MenuUtil.CreateContextMenu` picker (same pattern as the existing min-quality button), not a checkbox, since it's not binary.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — manual, in-game verification only (see project memory: no automated test suite exists, this is permanent). Interim verification before Task 5 lands uses `/run KART_Settings.lcVotedItemDisplay = "..."` since the settings UI doesn't exist yet in earlier tasks.

## Global Constraints

- English source: code, comments, commit messages; mirror any new locale strings into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets user-facing changes as `### Added` bullets (one line each, bold lead); mirror into `CHANGELOG-de.md` in the same task (Task 7).
- Bump `KeineAhnungRaidTools.toc`'s `## Version:` from `2.6.0` to `2.7.0` (Task 7) — confirmed current version before writing this plan. **Note for whoever picks up the still-blocked `docs/superpowers/plans/2026-07-22-loot-council-features.md` feature plan later:** that plan's own Task 13 also targets `2.7.0`. Whichever of the two plans ships second must re-target `2.8.0` instead — check `KeineAhnungRaidTools.toc`'s actual version at that time, don't trust either plan's hardcoded number blindly.
- This plan only touches the vote-list window (`LootCouncilVote.lua`, `KART.LC.Vote`) shown to non-council raiders. The council panel (`LootCouncilPanel.lua`, `KART.LC.Council`) is explicitly out of scope — see the spec.
- Full design context: `docs/superpowers/specs/2026-07-23-vote-list-voted-item-display-design.md`.

---

### Task 1: `Vote.GetVisibleRolls()` and the `/kart showall` override lifecycle

**Files:**
- Modify: `LootCouncilVote.lua:136-153` (`Vote.RefreshVoteListRows`, adds a new function directly above it and one line inside it)

**Interfaces:**
- Produces: `Vote.GetVisibleRolls()` — returns `LC.voteListRolls` unfiltered when `KART_Settings.lcVotedItemDisplay ~= "hide"` or `LC.showAllOverride` is set; otherwise returns a new array with every rollID the local player has already voted on (`LC.votedByMe[rollID]` truthy) removed. Consumed by Tasks 2, 3, and 4.
- Produces: `LC.showAllOverride` — plain boolean field on shared `LC` (not persisted, not synced), set by `/kart showall` (Task 6), cleared automatically here once `LC.voteListRolls` empties out.

**Root cause / current behavior:** `Vote.RefreshVoteListRows_Spacious`/`_Compact` and the ticker in `Vote.CreateVoteList` all iterate `LC.voteListRolls` directly with no concept of "hide this one from view but keep tracking it." This task adds the filtering primitive; it isn't wired into any renderer yet (that's Tasks 2-4), so this task alone has no visible effect in-game beyond what `/dump` can show.

- [ ] **Step 1: Add `Vote.GetVisibleRolls()` and the override-reset**

Locate (`LootCouncilVote.lua`):

```lua
function Vote.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
```

Replace with:

```lua
-- Personal display preference (KART_Settings.lcVotedItemDisplay, see the settings dropdown in
-- Task 5 of this plan) — when set to "hide", a roll the local player has already voted on is left
-- out of the rendered list entirely (card/row disappears, window shrinks) unless
-- LC.showAllOverride is set (see /kart showall, Task 6). Returns LC.voteListRolls itself (no copy)
-- whenever nothing is being filtered, so callers that don't need filtering pay no extra cost.
function Vote.GetVisibleRolls()
    if (KART_Settings and KART_Settings.lcVotedItemDisplay) ~= "hide" or LC.showAllOverride then
        return LC.voteListRolls
    end
    local visible = {}
    for _, rollID in ipairs(LC.voteListRolls) do
        if not LC.votedByMe[rollID] then
            table.insert(visible, rollID)
        end
    end
    return visible
end

function Vote.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        -- Every roll this batch tracked has now expired or been removed — /kart showall's
        -- override only ever meant "for the rolls currently on screen"; the next fresh batch
        -- should start clean, respecting the display setting again from roll one.
        LC.showAllOverride = nil
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
```

- [ ] **Step 2: Manual verification**

`/reload`. Run `/run KART.LC.StartTest("looter")` to populate the vote-list window with the default test items (or use the in-game "Test: Looter" button). With the window open, run `/dump KART.LC.Vote.GetVisibleRolls()` — confirm it returns a table with the same entries as `/dump KART.LC.voteListRolls` (since `lcVotedItemDisplay` isn't `"hide"` yet, nothing is filtered — this is expected at this stage of the plan, filtering isn't wired into rendering until Task 2/3). Then run `/run KART_Settings.lcVotedItemDisplay = "hide"` and vote on one item via its button — `/dump KART.LC.Vote.GetVisibleRolls()` should now return one fewer entry than `/dump KART.LC.voteListRolls`. Run `/run KART_Settings.lcVotedItemDisplay = "full"` afterward to reset for the next task's testing.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "feat: add Vote.GetVisibleRolls, the filtering primitive for hiding voted items"
```

---

### Task 2: Spacious renderer — filter hidden items, shrink voted ones when the mode is "shrink"

**Files:**
- Modify: `LootCouncilVote.lua:171-460` (`Vote.RefreshVoteListRows_Spacious`)

**Interfaces:**
- Consumes: `Vote.GetVisibleRolls()` (Task 1).

**Root cause / current behavior:** the renderer iterates `LC.voteListRolls` directly (no filtering) and uses one fixed `rowH` for every row regardless of voted state (no shrinking). This task makes it iterate the filtered list (so `hide` mode actually removes voted cards) and, independently, gives a voted row a shorter height when `KART_Settings.lcVotedItemDisplay == "shrink"` (this is the behavior originally scoped as its own Task 2 in `docs/superpowers/plans/2026-07-22-loot-council-features.md`, now folded into this setting instead of being unconditional).

- [ ] **Step 1: Compute a per-row height (only used in `shrink` mode) instead of one fixed `rowH`**

Locate:

```lua
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls
```

Replace with:

```lua
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD -- unvoted height
    local VOTED_BADGE_H = 20 -- matches row.votedBadge:SetHeight(20) below
    local votedRowH = ACCENT_H + BTN_TOP + VOTED_BADGE_H + BOTTOM_PAD -- voted rows drop the button/note area entirely
    local shrinkVoted = KART_Settings.lcVotedItemDisplay == "shrink"
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls
```

- [ ] **Step 2: Iterate the filtered list and track a running Y offset instead of the uniform grid formula**

Locate:

```lua
    for i, rollID in ipairs(LC.voteListRolls) do
        local row = f.rows[i]
```

Replace with:

```lua
    local visibleRolls = Vote.GetVisibleRolls()
    local y = 0 -- running offset, since voted rows may be shorter than unvoted ones (shrinkVoted)
    for i, rollID in ipairs(visibleRolls) do
        local row = f.rows[i]
```

- [ ] **Step 3: Use the per-row height and running offset when positioning each card**

Locate:

```lua
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(rowH)
        row.btnArea:SetPoint("RIGHT", -MARGIN, 0)
```

Replace with:

```lua
        local thisRowH = (shrinkVoted and LC.votedByMe[rollID]) and votedRowH or rowH
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(thisRowH)
        y = y + thisRowH + ROW_GAP
        row.btnArea:SetPoint("RIGHT", -MARGIN, 0)
```

- [ ] **Step 4: Size the outer frame to the accumulated height and hide the correct tail of recycled rows**

Locate (this is the function's final block):

```lua
    for i = #LC.voteListRolls + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #LC.voteListRolls * (rowH + ROW_GAP) + 12, 600))
end
```

Replace with:

```lua
    for i = #visibleRolls + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + y + 12, 600))
end
```

- [ ] **Step 5: Manual verification**

`/reload`, make sure the Spacious (non-compact) layout is active (`/run KART_Settings.lcVoteLayoutCompact = false`). Start a test roll with 3+ items (`KART.LC.StartTest("looter")`).

*Mode `full` (default):* `/run KART_Settings.lcVotedItemDisplay = "full"`. Vote on one item — confirm it stays full-size with the voted badge, same as before this plan.

*Mode `shrink`:* `/run KART_Settings.lcVotedItemDisplay = "shrink"`. Vote on another item — confirm its card shrinks to header + badge only (button area and note box gone), other cards stay full height, list still scrolls correctly.

*Mode `hide`:* `/run KART_Settings.lcVotedItemDisplay = "hide"`. Vote on the last item — confirm its card disappears entirely and the window shrinks (not just that item's card — the whole frame height). `/run KART_Settings.lcVotedItemDisplay = "full"` afterward to reset for the next task.

- [ ] **Step 6: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "feat: filter and shrink voted vote-list cards in the Spacious layout per lcVotedItemDisplay"
```

---

### Task 3: Compact renderer — filter hidden items (no shrink, per design decision)

**Files:**
- Modify: `LootCouncilVote.lua:465-730` (`Vote.RefreshVoteListRows_Compact`)

**Interfaces:**
- Consumes: `Vote.GetVisibleRolls()` (Task 1).

**Root cause / current behavior:** same filtering gap as Task 2, but Compact rows already collapse to just their badge on vote (`row.chipArea:SetShown(not voted)`) at a fixed row height — per the design spec, `shrink` mode intentionally looks identical to `full` mode here (no extra shrink logic needed), so this task is filtering-only.

- [ ] **Step 1: Iterate the filtered list**

Locate:

```lua
    for i, rollID in ipairs(LC.voteListRolls) do
        local row = f.compactRows[i]
```

Replace with:

```lua
    local visibleRolls = Vote.GetVisibleRolls()
    for i, rollID in ipairs(visibleRolls) do
        local row = f.compactRows[i]
```

(The row-positioning code further down already derives its Y position from the loop's own `i`, so no separate edit is needed there — swapping the loop's source is enough to renumber/reposition the remaining rows.)

- [ ] **Step 2: Hide the correct tail of recycled rows and size the frame from the filtered count**

Locate (this is the function's final block):

```lua
    for i = #LC.voteListRolls + 1, #f.compactRows do
        if f.compactRows[i] then f.compactRows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #LC.voteListRolls * (rowH + ROW_GAP) + 12, 600))
end
```

Replace with:

```lua
    for i = #visibleRolls + 1, #f.compactRows do
        if f.compactRows[i] then f.compactRows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #visibleRolls * (rowH + ROW_GAP) + 12, 600))
end
```

- [ ] **Step 3: Manual verification**

`/reload`, switch to Compact layout (`/run KART_Settings.lcVoteLayoutCompact = true`). Start a test roll with 3+ items. `/run KART_Settings.lcVotedItemDisplay = "hide"`, vote on one item — confirm its row disappears and the window shrinks, remaining rows shift up with no gap. `/run KART_Settings.lcVotedItemDisplay = "full"` — vote on another item — confirm it stays visible with just the badge (unchanged from pre-plan behavior). Reset to `"full"` afterward.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "feat: filter hidden voted items out of the Compact vote-list layout"
```

---

### Task 4: Countdown ticker — use the filtered list for its per-row fast path

**Files:**
- Modify: `LootCouncilVote.lua:76-102` (`Vote.CreateVoteList`, the shared `f.ticker`)

**Interfaces:**
- Consumes: `Vote.GetVisibleRolls()` (Task 1).

**Root cause / current behavior:** the ticker's expiry pass (removing rolls whose deadline has passed from `LC.voteListRolls`) must keep operating on the full list — a hidden item still needs to expire on schedule even while off-screen. But its "fast path" (updating each visible row's countdown text without a full rebuild, taken when nothing expired this tick) matches `pool[i]` against `LC.voteListRolls[i]` by position — once Tasks 2/3 make the renderers draw from the filtered list, `pool[i]` no longer corresponds to `LC.voteListRolls[i]` whenever something is hidden, so the countdown text for a shown row could get written from the wrong rollID's deadline.

- [ ] **Step 1: Use the filtered list in the fast path only**

Locate (inside `Vote.CreateVoteList`'s ticker — note the *expiry* loop right above this, which iterates `LC.voteListRolls` directly, is not part of this Locate block and must not change):

```lua
            local pool = (KART_Settings and KART_Settings.lcVoteLayoutCompact) and f.compactRows or f.rows
            for i, rid in ipairs(LC.voteListRolls) do
```

Replace with:

```lua
            local pool = (KART_Settings and KART_Settings.lcVoteLayoutCompact) and f.compactRows or f.rows
            for i, rid in ipairs(Vote.GetVisibleRolls()) do
```

- [ ] **Step 2: Manual verification**

`/reload`. Start a test roll with 3+ items, `/run KART_Settings.lcVotedItemDisplay = "hide"`, vote on the first item (its card disappears, per Task 2/3). Watch the remaining cards' countdown timers for at least 3-4 seconds — confirm each still counts down correctly and matches its own item (no swapped/frozen timers). This is the one behavioral difference Task 4 fixes that isn't visible from a single glance — the bug it prevents only shows up over time as the ticker's fast path runs repeatedly. Reset `/run KART_Settings.lcVotedItemDisplay = "full"` afterward.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "fix: keep the vote-list countdown ticker's fast path in sync with the filtered row list"
```

---

### Task 5: Settings UI — three-way "voted item display" picker

**Files:**
- Modify: `LootCouncil.lua:513-520` (near `LC.QualityLabel`, adds a sibling label helper)
- Modify: `LootCouncil.lua:935-970` (`prefsCard` construction — resizes the card, adds the new button after `CbShowNickNames`)
- Modify: `Core.lua:137-139` (`KART.UpdateStyles`, adds a sync line so the button's text reflects the saved setting on login/`/reload`)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Produces: `LC.VotedItemDisplayLabel(mode)` — localized label for a mode string (`"full"`/`"shrink"`/`"hide"`), mirrors `LC.QualityLabel`'s pattern (locale-key lookup, no color coding needed here).
- Produces: `KART.LC.BtnVotedItemDisplay` — the button widget, referenced by `Core.lua`'s login-time sync line the same way `KART.LC.BtnMinQuality` already is.

**Root cause / current behavior:** `KART_Settings.lcVotedItemDisplay` doesn't exist as a concept anywhere yet outside this plan's own code — Tasks 1-4 already read it (defaulting safely via `~= "hide"` and `== "shrink"` comparisons, which are both false for a `nil` value, i.e. behave as `"full"` until this task ships), but there's no way for a player to actually set it without `/run` until this task lands.

- [ ] **Step 1: Add the label helper next to `LC.QualityLabel`**

Locate:

```lua
function LC.QualityLabel(q)
    local name = (KART.L and KART.L["LC_QUALITY_" .. q]) or tostring(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] ---@diagnostic disable-line: undefined-global
    if c then
        return c.hex .. name .. "|r"
    end
    return name
end
```

Add directly after it:

```lua
-- Localized label for the "voted item display" button (KART_Settings.lcVotedItemDisplay) —
-- mirrors LC.QualityLabel's lookup pattern, just without quality-color coding (there's no
-- natural color axis for full/shrink/hide the way there is for item quality).
function LC.VotedItemDisplayLabel(mode)
    return (KART.L and KART.L["LC_VOTED_DISPLAY_" .. (mode or "full"):upper()]) or mode or "full"
end
```

- [ ] **Step 2: Resize `prefsCard` and add the button after `CbShowNickNames`**

Locate:

```lua
    local prefsCard = KART.CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    prefsCard:SetSize(500, 165)
    KART.LC.SettingsCard = prefsCard
```

Replace with:

```lua
    local prefsCard = KART.CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    prefsCard:SetSize(500, 215)
    KART.LC.SettingsCard = prefsCard
```

Locate:

```lua
    KART.LC.CbShowNickNames = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCShowNickNames",
        L.LC_SET_SHOW_NICKNAMES, "lcShowNickNames", -135,
        function()
            if LC.councilPanel and LC.councilPanel:IsShown() then KART.LC.Council.RefreshCouncilRows() end
        end, L.LC_DESC_SHOW_NICKNAMES)

    -- Droptimizer gain% column toggle (KART.DT.CbModuleEnabled) is built here too, by
    -- Droptimizer.lua — see the reserved -75 slot there. Kept in its own file since it's a
    -- different module, but it's a personal preference like CbAutoPass above, so it lives next
    -- to it rather than getting its own settings tab.
```

Replace with:

```lua
    KART.LC.CbShowNickNames = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCShowNickNames",
        L.LC_SET_SHOW_NICKNAMES, "lcShowNickNames", -135,
        function()
            if LC.councilPanel and LC.councilPanel:IsShown() then KART.LC.Council.RefreshCouncilRows() end
        end, L.LC_DESC_SHOW_NICKNAMES)

    -- Personal preference, same reasoning as CbCompactVoteLayout above — controls whether an
    -- already-voted item stays full-size, shrinks, or disappears entirely from YOUR OWN vote
    -- window (see Vote.GetVisibleRolls). Slot -175: next free step below CbShowNickNames, inside
    -- this card (card height bumped 165 -> 215 above to fit a 28px-tall button here instead of
    -- another checkbox row). Initial label is hardcoded to "full" — KART_Settings doesn't exist
    -- yet at file-load time, same reasoning as BtnMinQuality's own placeholder-text comment below;
    -- Core.lua's ADDON_LOADED handler syncs the real saved value once settings are loaded.
    KART.LC.BtnVotedItemDisplay = KART.CreateModernButton(
        prefsCard, LC.VotedItemDisplayLabel("full"), L.LC_DESC_VOTED_DISPLAY)
    KART.LC.BtnVotedItemDisplay:SetPoint("TOPLEFT", 20, -175)
    KART.LC.BtnVotedItemDisplay:SetSize(460, 28)
    KART.LC.BtnVotedItemDisplay:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.LC_SET_VOTED_DISPLAY)
            for _, mode in ipairs({"full", "shrink", "hide"}) do
                rootDescription:CreateButton(LC.VotedItemDisplayLabel(mode), function()
                    KART_Settings.lcVotedItemDisplay = mode
                    self.text:SetText(LC.VotedItemDisplayLabel(mode))
                    LC.Vote.RefreshVoteListRowsIfShown()
                end)
            end
        end)
    end)

    -- Droptimizer gain% column toggle (KART.DT.CbModuleEnabled) is built here too, by
    -- Droptimizer.lua — see the reserved -75 slot there. Kept in its own file since it's a
    -- different module, but it's a personal preference like CbAutoPass above, so it lives next
    -- to it rather than getting its own settings tab.
```

- [ ] **Step 3: Sync the button's text to the saved setting on login/`/reload`**

Locate (`Core.lua`):

```lua
    if KART.LC and KART.LC.BtnMinQuality and KART.LC.QualityLabel then
        KART.LC.BtnMinQuality.text:SetText(KART.LC.QualityLabel(KART_Settings.lcMinQuality or 4))
    end
```

Replace with:

```lua
    if KART.LC and KART.LC.BtnMinQuality and KART.LC.QualityLabel then
        KART.LC.BtnMinQuality.text:SetText(KART.LC.QualityLabel(KART_Settings.lcMinQuality or 4))
    end

    if KART.LC and KART.LC.BtnVotedItemDisplay and KART.LC.VotedItemDisplayLabel then
        KART.LC.BtnVotedItemDisplay.text:SetText(KART.LC.VotedItemDisplayLabel(KART_Settings.lcVotedItemDisplay or "full"))
    end
```

- [ ] **Step 4: Add the locale strings**

In `Locales/enUS.lua`, near `LC_SET_SHOW_NICKNAMES`/`LC_DESC_SHOW_NICKNAMES`, add:

```lua
    LC_SET_VOTED_DISPLAY      = "Voted item display",
    LC_DESC_VOTED_DISPLAY     = "What happens to an item in your vote window once you've voted on it.",
    LC_VOTED_DISPLAY_FULL     = "Voted items: stay full-size",
    LC_VOTED_DISPLAY_SHRINK   = "Voted items: shrink",
    LC_VOTED_DISPLAY_HIDE     = "Voted items: hide (use /kart showall to bring them back)",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_SET_VOTED_DISPLAY      = "Anzeige abgestimmter Items",
    LC_DESC_VOTED_DISPLAY     = "Was mit einem Item in deinem Abstimmungsfenster passiert, sobald du abgestimmt hast.",
    LC_VOTED_DISPLAY_FULL     = "Abgestimmte Items: bleiben normal groß",
    LC_VOTED_DISPLAY_SHRINK   = "Abgestimmte Items: werden kleiner",
    LC_VOTED_DISPLAY_HIDE     = "Abgestimmte Items: ausblenden (mit /kart showall wieder einblenden)",
```

- [ ] **Step 5: Manual verification**

`/reload`, open Loot Council settings — confirm the new button shows "Voted items: stay full-size" (or the German equivalent), matching the actual current `KART_Settings.lcVotedItemDisplay` (nil at this point, so the `"full"` fallback). Click it — confirm a 3-item context menu appears with the three labels. Pick "shrink" — confirm the button's own text updates immediately to reflect it. Start a test roll and confirm the mode picked here actually drives the behavior verified in Tasks 2-4 (no more need for `/run`). `/reload` again and confirm the button still shows "shrink" (persisted + synced correctly on login).

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua Core.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add a settings picker for the voted-item display mode"
```

---

### Task 6: `/kart showall` slash command

**Files:**
- Modify: `Core.lua` (`SlashCmdList["KART"]`, adds a branch and a `/kart help` line)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Consumes: `LC.showAllOverride` (Task 1), `LC.Vote.RefreshVoteListRows()` (existing).

**Root cause / current behavior:** with `hide` mode shipped (Task 2/3), a player has no way to bring back an already-voted item's card once it's gone — e.g. to double check what they voted, or compare it against a still-open item. This command sets the override and forces an immediate refresh.

- [ ] **Step 1: Add the `showall` branch and the help-text line**

Locate:

```lua
    elseif cmd == "trade" then
        if KART.LC and KART.LC.tradeReminderFrame and #KART.LC.pendingTrades > 0 then
            KART.LC.tradeReminderFrame:Show()
        end
    elseif cmd == "help" or cmd == "h" then
        print(KART.L.HELP_HEADER or "KART slash commands:")
        print("  /kart - " .. (KART.L.HELP_TOGGLE or "open/close the main window"))
        print("  /kart version (v) - " .. (KART.L.HELP_VERSION or "request everyone's KART version"))
        print("  /kart lc - " .. (KART.L.HELP_LC or "reopen the Loot Council window if something's still active"))
        print("  /kart trade - " .. (KART.L.HELP_TRADE or "reopen the trade reminder if something's still pending"))
        print("  /kart help (h) - " .. (KART.L.HELP_HELP or "show this help"))
    else
```

Replace with:

```lua
    elseif cmd == "trade" then
        if KART.LC and KART.LC.tradeReminderFrame and #KART.LC.pendingTrades > 0 then
            KART.LC.tradeReminderFrame:Show()
        end
    elseif cmd == "showall" then
        -- Reveals every currently active roll in the vote-list window, including ones already
        -- voted on and hidden by KART_Settings.lcVotedItemDisplay == "hide" (see
        -- Vote.GetVisibleRolls). No-op if nothing is currently tracked, same as /kart lc / /kart trade.
        if KART.LC and KART.LC.Vote then
            KART.LC.showAllOverride = true
            KART.LC.Vote.RefreshVoteListRows()
        end
    elseif cmd == "help" or cmd == "h" then
        print(KART.L.HELP_HEADER or "KART slash commands:")
        print("  /kart - " .. (KART.L.HELP_TOGGLE or "open/close the main window"))
        print("  /kart version (v) - " .. (KART.L.HELP_VERSION or "request everyone's KART version"))
        print("  /kart lc - " .. (KART.L.HELP_LC or "reopen the Loot Council window if something's still active"))
        print("  /kart trade - " .. (KART.L.HELP_TRADE or "reopen the trade reminder if something's still pending"))
        print("  /kart showall - " .. (KART.L.HELP_SHOWALL or "reveal already-voted items hidden by your display setting"))
        print("  /kart help (h) - " .. (KART.L.HELP_HELP or "show this help"))
    else
```

- [ ] **Step 2: Add the locale string**

In `Locales/enUS.lua`, near the other `HELP_` strings, add:

```lua
    HELP_SHOWALL = "reveal already-voted items hidden by your display setting",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    HELP_SHOWALL = "bereits abgestimmte, ausgeblendete Items wieder anzeigen",
```

- [ ] **Step 3: Manual verification**

`/reload`. Set the display mode to `hide` (via the Task 5 UI or `/run KART_Settings.lcVotedItemDisplay = "hide"`), start a test roll with 3 items, vote on all 3 — confirm the vote-list window closes entirely (nothing left to show). Run `/kart showall` — confirm the window reopens showing all 3 items (now all displaying their voted badges, full-size, per the spec's "no extra visual state" decision). Wait for all 3 to expire naturally, start a fresh test roll — confirm it starts hidden-by-default again (override didn't leak into the new batch). Also run `/kart help` and confirm the `showall` line appears.

- [ ] **Step 4: Commit**

```bash
git add Core.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add /kart showall to reveal voted items hidden by the display setting"
```

---

### Task 7: Changelog and version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

Confirm the actual current version in `KeineAhnungRaidTools.toc` first (this plan assumes it's still `2.6.0` — see the Global Constraints note above about the other, still-blocked feature plan also targeting `2.7.0`).

- [ ] **Step 1: Bump the addon version**

Locate (`KeineAhnungRaidTools.toc`):

```
## Version: 2.6.0
```

Replace with:

```
## Version: 2.7.0
```

- [ ] **Step 2: Add the English changelog entry**

Locate (`CHANGELOG.md`):

```markdown
## [2.6.0] - 2026-07-23
### Fixed
- **Loot Council no longer confuses two players who share a character name across connected realms.** Votes, council membership, item assignments, and officer notes are now tracked per player.
```

Replace with:

```markdown
## [2.7.0] - 2026-07-23
### Added
- **Choose what happens to an item in your vote window once you've voted on it**: stay full-size (default), shrink, or hide completely. New setting in Loot Council settings.
- **`/kart showall`** brings back any items hidden by that setting.

## [2.6.0] - 2026-07-23
### Fixed
- **Loot Council no longer confuses two players who share a character name across connected realms.** Votes, council membership, item assignments, and officer notes are now tracked per player.
```

- [ ] **Step 3: Mirror into German changelog**

Locate (`CHANGELOG-de.md`):

```markdown
## [2.6.0] - 2026-07-23
### Behoben
- **Der Loot Council verwechselt keine zwei Spieler mehr, die sich einen Charakternamen über verbundene Realms teilen.** Votes, Council-Mitgliedschaft, Item-Zuweisungen und Officer-Notizen werden jetzt pro Spieler verfolgt.
```

Replace with:

```markdown
## [2.7.0] - 2026-07-23
### Added
- **Wähle, was mit einem Item in deinem Abstimmungsfenster passiert, sobald du abgestimmt hast**: normal groß bleiben (Standard), kleiner werden, oder komplett ausblenden. Neue Einstellung in den Loot-Council-Einstellungen.
- **`/kart showall`** holt ausgeblendete Items zurück.

## [2.6.0] - 2026-07-23
### Behoben
- **Der Loot Council verwechselt keine zwei Spieler mehr, die sich einen Charakternamen über verbundene Realms teilen.** Votes, Council-Mitgliedschaft, Item-Zuweisungen und Officer-Notizen werden jetzt pro Spieler verfolgt.
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version, changelog for the voted-item display feature"
```
