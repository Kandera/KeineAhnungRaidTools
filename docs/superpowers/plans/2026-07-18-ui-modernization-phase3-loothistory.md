# UI Modernization Phase 3: Loot History Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Phase 1 theme foundation (`docs/superpowers/plans/2026-07-17-ui-modernization-phase1-foundation.md`,
already merged) to the Loot History window (`LootHistory.lua`): round the main window and the
JSON export dialog's outer corners, round the search box, and route the existing row zebra-stripe
background through `KART.Theme.Lighten` so it tracks the user's configured background color
instead of a hard-coded near-black.

**Architecture:** No new primitives needed — consumes what Phase 1 already built
(`KART.ApplyRoundedMask`, `KART.Theme`). The player/reason filter buttons and the Clear/Export
buttons already use `KART.CreateModernButton`, so they picked up the modernized rounded/
accent-hover look automatically when Phase 1 merged — no changes needed there. Note: this file's
row backgrounds already alternate (`row.bg:SetColorTexture(0.1, 0.1, 0.1, i % 2 == 0 and 0.35 or
0.1)`, line 529) — Task 3 below only changes the *color source*, not the striping logic itself
(which already exists and is correct).

**Tech Stack:** Lua 5.1 (WoW addon runtime), WoW retail Frame API.

## Global Constraints

- No new graphic/icon assets.
- No automated test runner exists for this addon — every verification step here is a manual
  in-game check (`/reload`, then `/kart` → Loot Council tab → "History" or equivalent trigger),
  described but not executable in this pipeline.
- Code comments and commit messages in English (per `CLAUDE.md`).
- `KART.Theme.SUCCESS/WARNING/DANGER`, `KART.Theme.Lighten/Darken`, `KART.ApplyRoundedMask`,
  `KART.Theme.CORNER_RADIUS_LG/SM/MIN_SIZE` all already exist in `Utils.lua` from Phase 1 —
  consumed, not redefined.
- No SavedVariables schema changes.
- `KART.RegisterStrataFrame` (a helper added by unrelated, separately-merged work already in
  `main`) is already used in this file for frame-strata management — do not touch it, it's out of
  scope for this UI-modernization plan.

---

### Task 1: Round the main window and export dialog corners

**Files:**
- Modify: `LootHistory.lua:108-115` (`LH.ShowExportDialog`'s frame creation)
- Modify: `LootHistory.lua:226-235` (`LH.CreateWindow`'s frame creation)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG` (Phase 1,
  `Utils.lua`)

- [ ] **Step 1: Round the export dialog**

Replace `LootHistory.lua:108-115`:

```lua
        local f = CreateFrame("Frame", "KART_LHExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 320)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
        local f = CreateFrame("Frame", "KART_LHExportDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 320)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        -- Matches the rounded window look introduced across the rest of the addon in the UI
        -- modernization pass. Frame is given an explicit SetSize above, so the mask's min-size
        -- guard never blocks this (same reasoning as the Buff-Checker window's identical call).
        KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 2: Round the main history window**

Replace `LootHistory.lua:226-235`:

```lua
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 430)
    f:SetPoint("CENTER")
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
    local f = CreateFrame("Frame", "KART_LootHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 430)
    f:SetPoint("CENTER")
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    -- Outer window rounding only — the header bar (created below) stays a flat rectangle
    -- overlapping the window's top edge, same convention as MainFrame's own header in the
    -- Phase 1 modernization, so it isn't independently rounded here.
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 3: Manual verification**

Run: `/reload`, then open the Loot History window (via the Loot Council panel's history button)
and separately click "Export JSON" to open the export dialog.
Expected: both windows' four outer corners are visibly rounded, matching the rounded look of the
main `/kart` window and the Buff-Checker window. The header bar inside the history window (title
+ close button) stays a flat rectangle — no visual clash where it meets the now-rounded top
corners (its sharp corners sit slightly inset from the window edge already, per its own
`SetPoint("TOPLEFT")`/`SetPoint("TOPRIGHT")` anchoring).

- [ ] **Step 4: Commit**

```bash
git add LootHistory.lua
git commit -m "Round Loot History window and export dialog corners"
```

---

### Task 2: Round the search box

**Files:**
- Modify: `LootHistory.lua:278-287` (`searchBox` creation inside `LH.CreateWindow`)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_SM` (Phase 1,
  `Utils.lua`)

- [ ] **Step 1: Apply the small-radius mask to the search box**

Replace `LootHistory.lua:278-287`:

```lua
    local searchBox = CreateFrame("EditBox", "KART_LHSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", 10, -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    searchBox:SetBackdropColor(0, 0, 0, 0.5)
    searchBox:SetTextInsets(5, 5, 0, 0)
    searchBox:SetMaxLetters(40)
```

with:

```lua
    local searchBox = CreateFrame("EditBox", "KART_LHSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", 10, -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    searchBox:SetBackdropColor(0, 0, 0, 0.5)
    searchBox:SetTextInsets(5, 5, 0, 0)
    searchBox:SetMaxLetters(40)
    KART.ApplyRoundedMask(searchBox, KART.Theme.CORNER_RADIUS_SM)
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, open the Loot History window.
Expected: the item-search edit box (top-left, next to the "Search:" label) has visibly rounded
corners matching the filter/reset buttons beside it, instead of a sharp rectangle. Typing into it
still filters rows normally (the mask only affects the backdrop texture, not input behavior).

- [ ] **Step 3: Commit**

```bash
git add LootHistory.lua
git commit -m "Round Loot History search box corners"
```

---

### Task 3: Theme-driven row zebra-stripe color

**Files:**
- Modify: `LootHistory.lua:529` (`row.bg:SetColorTexture(...)` inside `LH.Refresh`)

**Interfaces:**
- Consumes: `KART.Theme.Lighten(r, g, b, amount)` (Phase 1, `Utils.lua`)

The row-pool already creates a `BACKGROUND`-layer `row.bg` texture (`LootHistory.lua:477-478`)
and already alternates its alpha by row parity (`LootHistory.lua:529`) — this task only changes
the *color* fed into that existing call from a hard-coded near-black to one derived from the
user's configured background color, matching the approach already used for the Buff-Checker
window's row striping (Phase 2, `docs/superpowers/plans/2026-07-17-ui-modernization-phase2-buffchecker.md`).

- [ ] **Step 1: Replace the hard-coded stripe color**

Replace `LootHistory.lua:529`:

```lua
        row.bg:SetColorTexture(0.1, 0.1, 0.1, i % 2 == 0 and 0.35 or 0.1)
```

with:

```lua
        local br, bg_, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
        local lr, lg, lb = KART.Theme.Lighten(br, bg_, bb, 0.06)
        row.bg:SetColorTexture(lr, lg, lb, i % 2 == 0 and 0.35 or 0.1)
```

(Local variable named `bg_` with a trailing underscore, not `bg`, because `bg` is already bound
above in the same `for i, e in ipairs(filtered) do` loop as the second parameter of the
`ipairs`-style variables from the enclosing `LH.Refresh` scope — check the actual surrounding code
for any existing `bg`/`b` locals in scope at this exact point before finalizing the name, and pick
whatever non-colliding name reads clearest; `bg_` is just the plan's suggestion, not mandatory.)

- [ ] **Step 2: Manual verification**

Run: `/reload`, open the Loot History window with existing history entries (or generate a few via
the Loot Council test mode, if the history is currently empty).
Expected: alternating rows still visibly band light/dark as before, but the tint now derives from
the user's configured background color (Settings tab → background color picker) rather than a
fixed near-black — changing the background color in Settings and reopening the Loot History
window should visibly shift the stripe tint to match.

- [ ] **Step 3: Commit**

```bash
git add LootHistory.lua
git commit -m "Derive Loot History row stripe color from user's background color"
```
