# Vote-Window Layouts (Spacious + Compact) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the loot-council vote window's single cramped layout with two selectable
personal styles — a resized "Spacious" card layout (new default) and a new "Compact" icon-chip
layout — toggled by a settings checkbox, so multiple simultaneous item rolls no longer read as a
squeezed wall of boxes.

**Architecture:** `LC.RefreshVoteListRows()` becomes a thin dispatcher that resizes the shared
vote-list window and delegates to one of two sibling renderers,
`LC.RefreshVoteListRows_Spacious()` (adapted from today's single implementation) or
`LC.RefreshVoteListRows_Compact()` (new). Each renderer owns its own recycled frame pool
(`f.rows` / `f.compactRows`) so the two widget trees never mix fields. Both pools expose a
`row.timerText` field so the frame's existing shared 1-second ticker can update either one
without knowing which style is active. The style choice lives in a new personal (not
raid-synced) setting, `KART_Settings.lcVoteLayoutCompact`.

**Tech Stack:** WoW addon Lua (`BackdropTemplate`, `CooldownFrameTemplate`), this project's own
`Utils.lua` helpers (`KART.CreateModernButton`, `KART.CreateGradientOverlay`,
`KART.CreateSettingsCheckbox`). No automated test framework exists in this codebase (pure WoW
addon, no headless Lua harness) — verification for every task happens in a live WoW client via
the addon's existing **Test** button (`LC.StartTest("looter")`, wired in
`LC.BuildSettingsPanel`), which spawns `TEST_ITEM_COUNT` (4) simulated simultaneous item rolls
using real item links. This is the project's established manual-verification path (see the
comment block above `local TEST_ITEMS` in LootCouncil.lua) and replaces the automated
test-run steps this skill template otherwise expects.

## Global Constraints

- English code comments only (project convention, see CLAUDE.md) — the chat/spec discussion is
  German, the code is not.
- `LC_*` locale keys must be added to **both** `Locales/enUS.lua` and `Locales/deDE.lua` in the
  same task (never one without the other).
- No new frame-recycling bugs: every new/resized widget must follow the existing pattern in this
  file of creating once (`if not row then ... end`) and repositioning/re-styling on every refresh.
- Both styles must render using only flat rects + `KART.CreateGradientOverlay` + colored 1px
  borders + `CooldownFrameTemplate` — no drop shadows or rounded corners (not available via this
  project's backdrop system; see the design doc's "Architektur" section).
- Update `CHANGELOG.md` and `CHANGELOG-de.md` together (see `feedback_changelog_readme` project
  convention) once all tasks are done.

---

### Task 1: Localization strings for the new setting

**Files:**
- Modify: `Locales/enUS.lua:135` (insert after `LC_DESC_AUTOPASS`)
- Modify: `Locales/deDE.lua:135` (insert after `LC_DESC_AUTOPASS`)

**Interfaces:**
- Produces: `KART.L.LC_SET_COMPACT_VOTE_LAYOUT`, `KART.L.LC_DESC_COMPACT_VOTE_LAYOUT` — consumed
  by Task 2's checkbox.

- [ ] **Step 1: Add the English strings**

In `Locales/enUS.lua`, right after line 135 (`LC_DESC_AUTOPASS = "..."`), add:

```lua
    LC_SET_COMPACT_VOTE_LAYOUT  = "Use compact vote window",
    LC_DESC_COMPACT_VOTE_LAYOUT = "Shows each active roll as a short single-line row with small icon-only vote buttons instead of full-size cards — trades readability for a much smaller window footprint. Your own personal choice, not synced from the raid leader.",
```

- [ ] **Step 2: Add the German strings**

In `Locales/deDE.lua`, right after line 135 (`LC_DESC_AUTOPASS = "..."`), add:

```lua
    LC_SET_COMPACT_VOTE_LAYOUT  = "Kompaktes Vote-Fenster verwenden",
    LC_DESC_COMPACT_VOTE_LAYOUT = "Zeigt jeden aktiven Roll als kurze einzeilige Zeile mit kleinen Icon-Buttons statt großer Karten — tauscht Lesbarkeit gegen einen deutlich kleineren Fensterbedarf. Deine persönliche Einstellung, wird nicht vom Raidleiter übernommen.",
```

- [ ] **Step 3: Verify the locale files still load**

In-game: `/reload`, then open the KART settings panel (any tab) and confirm no Lua error popped
up on load (a malformed locale table throws immediately on `/reload`).
Expected: no red Lua error, settings panel opens normally.

- [ ] **Step 4: Commit**

```bash
git add Locales/enUS.lua Locales/deDE.lua
git commit -m "Add locale strings for compact vote-window layout setting"
```

---

### Task 2: Personal setting + settings-panel checkbox

**Files:**
- Modify: `LootCouncil.lua:2812-2814` (insert new checkbox right after `CbAutoPass`)
- Modify: `LootCouncil.lua:2826` (`raidBox` Y-offset, to make room for the new checkbox)

**Interfaces:**
- Consumes: `KART.CreateSettingsCheckbox(parent, name, labelText, settingKey, yOffset, callback, tooltipText)` (Utils.lua:110), `KART.L.LC_SET_COMPACT_VOTE_LAYOUT` / `KART.L.LC_DESC_COMPACT_VOTE_LAYOUT` (Task 1).
- Produces: `KART_Settings.lcVoteLayoutCompact` (boolean, nil/false = Spacious), read by Task 5's
  dispatcher. `KART.LC.CbCompactVoteLayout` (checkbox widget reference, for consistency with the
  existing `KART.LC.CbAutoPass`/`KART.LC.CbModuleEnabled` pattern — nothing else reads it, but the
  pattern is followed so a future settings-reset routine can find it the same way the others are found).

**Context:** The existing checkbox column steps by 30px (`CbModuleEnabled` at -50, `CbAutoPass`
at -80, Droptimizer's module toggle reserved at -110 — see `Droptimizer.lua:128`). `raidBox`
currently starts right after that at -150, leaving no room for a fourth checkbox. The whole
settings panel lives inside a scrolling `scrollChild` sized `310x750` (`MainFrame.lua:112`), which
has generous headroom — shifting `raidBox` down by one more slot is safe.

- [ ] **Step 1: Shift `raidBox` down to make room**

In `LootCouncil.lua`, find:

```lua
    local raidBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    raidBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -150)
```

Change `-150` to `-180`.

- [ ] **Step 2: Add the new checkbox**

Right after the existing block:

```lua
    -- Personal preference — never overridden by the raid leader's settings.
    KART.LC.CbAutoPass = KART.CreateSettingsCheckbox(
        parent, "KART_LCAutoPass",
        L.LC_SET_AUTOPASS, "lcAutoPass", -80, nil, L.LC_DESC_AUTOPASS)
```

add:

```lua
    -- Personal preference, same reasoning as CbAutoPass above — the vote window's layout style
    -- is purely a display choice, so it's never synced from the raid leader. Slot -140: the next
    -- free step below the reserved Droptimizer slot at -110 (see Droptimizer.lua:128) and above
    -- raidBox, which was shifted from -150 to -180 to make room for this.
    KART.LC.CbCompactVoteLayout = KART.CreateSettingsCheckbox(
        parent, "KART_LCCompactVoteLayout",
        L.LC_SET_COMPACT_VOTE_LAYOUT, "lcVoteLayoutCompact", -140,
        LC.RefreshVoteListRows, L.LC_DESC_COMPACT_VOTE_LAYOUT)
```

(`LC.RefreshVoteListRows` as the callback is forward-referenced here — it already exists as a
function further down in the same file, and Lua resolves global/table function references at
call time, not definition time, so this is safe even though Task 5 is the one that makes this
function style-aware.)

- [ ] **Step 3: Verify in-game**

`/reload`, open the KART settings panel → Loot Council tab. Confirm:
- A new checkbox labeled "Kompaktes Vote-Fenster verwenden" (or the English string, depending on
  client locale) appears below the Droptimizer gain% checkbox and above the raid-wide gold box.
- The raid-wide gold box moved down and nothing overlaps it.
- Hovering the new checkbox shows the tooltip description.
- Toggling it on/off doesn't throw a Lua error (it calls `LC.RefreshVoteListRows`, which is a
  no-op with an empty `LC.voteListRolls`, so nothing visible happens yet — that's expected until
  Task 5).

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "Add personal setting + checkbox for compact vote-window layout"
```

---

### Task 3: Spacious layout renderer (resize + restyle the existing renderer)

**Files:**
- Modify: `LootCouncil.lua:571-819` (rename `LC.RefreshVoteListRows` to
  `LC.RefreshVoteListRows_Spacious`, resize per the design doc, add the quality-color accent
  strip)

**Interfaces:**
- Consumes: `LC.voteListRolls`, `LC.rollItems`, `LC.rollDeadlines`, `LC.votes`, `LC.votedByMe`,
  `LC.votedNoteByMe`, `LC.GetButtonConfig()`, `IsRealItemLink`, `ParseItemColor`,
  `GetVoteIconTexture`, `IsTestRoll`, `KART.CreateModernButton`, `KART.CreateGradientOverlay`,
  `KART.SetGradientOverlayColor` — all already used by today's `RefreshVoteListRows`, unchanged.
- Produces: `LC.RefreshVoteListRows_Spacious(f)` — takes the vote-list frame, resizes it to
  540px, (re)builds `f.rows[]`, sets `f:SetHeight(...)`. Every `row` in `f.rows` exposes
  `row.timerText` (already true today) for the shared ticker in Task 5.

**Context:** This task is a resize/restyle of the existing function, not a rewrite — the row
recycling pattern, vote-button click handling, note-box wiring, and tooltip hookup all stay
exactly as they are today. Only the layout constants change, plus one new element (the accent
strip).

- [ ] **Step 1: Rename the function and widen the window**

In `LootCouncil.lua`, find:

```lua
function LC.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if not LC.voteListFrame then LC.CreateVoteList() end
    local f = LC.voteListFrame
```

Replace with:

```lua
-- "Spacious" style: one card per item, full window width each, large touch targets. The default
-- and recommended style — see docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function LC.RefreshVoteListRows_Spacious(f)
    local WINDOW_W  = 540
    local CONTENT_W = WINDOW_W - 30 -- mirrors the scrollbar/padding reservation CreateVoteList already uses
    f:SetWidth(WINDOW_W)
    f.scrollChild:SetWidth(CONTENT_W)
```

(The `if #LC.voteListRolls == 0 ... end` / `if not LC.voteListFrame ...` guards and the initial
`local f = LC.voteListFrame` move into the new dispatcher in Task 5 — this function now receives
`f` as a parameter instead.)

- [ ] **Step 2: Replace the sizing constants**

Find:

```lua
    -- Sized with generous padding on purpose — the first version packed everything edge-to-edge
    -- with almost no breathing room between items, which read as a cramped wall of boxes.
    local buttons   = LC.GetButtonConfig()
    local cols      = math.min(#buttons, 3)
    local btnRows   = math.ceil(#buttons / cols)
    local MARGIN    = 8  -- left/right inner padding of each item block
    local BTN_GAP   = 8  -- horizontal gap between vote buttons
    local btnW      = math.floor((345 - MARGIN * 2 - (cols - 1) * BTN_GAP) / cols)
    local btnH      = 26
    local BTN_ROW_GAP = 6 -- vertical gap between rows of vote buttons
    local btnAreaH  = btnRows * btnH + (btnRows - 1) * BTN_ROW_GAP
    local BTN_TOP   = 30 -- title line + gap, i.e. how far down the button area starts
    local GAP_BTN_NOTE = 10
    local noteH     = 22
    local BOTTOM_PAD = 10
    local rowH      = BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD
    local ROW_GAP   = 12 -- gap between item blocks — was 5, the main source of the cramped look
```

Replace with:

```lua
    -- v2 sizing: each card is now the full window width (was a fraction of a narrower window),
    -- so every element scales up — this is what actually reads as "premium" rather than just
    -- "spaced out". cols capped at 5 (not the previous 3) so the default 5-category button set
    -- fits in a single row; a leader-configured 6th category still wraps to a second row instead
    -- of overflowing.
    local buttons   = LC.GetButtonConfig()
    local ICON_SIZE = 46
    local ACCENT_H  = 4  -- quality-color strip along the top edge of each card
    local MARGIN    = 16 -- left/right inner padding of each item block
    local cols      = math.min(#buttons, 5)
    local btnRows   = math.ceil(#buttons / cols)
    local BTN_GAP   = 10 -- horizontal gap between vote buttons
    local btnW      = math.floor((CONTENT_W - MARGIN * 2 - (cols - 1) * BTN_GAP) / cols)
    local btnH      = 34
    local BTN_ROW_GAP = 8 -- vertical gap between rows of vote buttons
    local btnAreaH  = btnRows * btnH + (btnRows - 1) * BTN_ROW_GAP
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls
```

- [ ] **Step 3: Add the accent strip and enlarge the icon/name/timer widgets**

Find the row-creation block (the `if not row then ... end` body) and, right after
`row:SetBackdropBorderColor(0, 0, 0, 1)`, add the accent strip texture:

```lua
            -- Quality-color strip along the card's top edge — the main visual cue that separates
            -- one card from the next, on top of the ROW_GAP spacing itself.
            row.accentStrip = row:CreateTexture(nil, "ARTWORK")
            row.accentStrip:SetPoint("TOPLEFT", 0, 0)
            row.accentStrip:SetPoint("TOPRIGHT", 0, 0)
            row.accentStrip:SetHeight(ACCENT_H)
```

Then find:

```lua
            row.itemIcon = row:CreateTexture(nil, "ARTWORK")
            row.itemIcon:SetSize(18, 18)
            row.itemIcon:SetPoint("TOPLEFT", MARGIN, -6)
```

Replace with:

```lua
            row.itemIcon = row:CreateTexture(nil, "ARTWORK")
            row.itemIcon:SetSize(ICON_SIZE, ICON_SIZE)
            row.itemIcon:SetPoint("TOPLEFT", MARGIN, -(ACCENT_H + MARGIN))
```

Find:

```lua
            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetPoint("TOPLEFT", row.itemIcon, "TOPRIGHT", 6, 2)
            row.itemText:SetWidth(226)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)
```

Replace with:

```lua
            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
            row.itemText:SetPoint("TOPLEFT", row.itemIcon, "TOPRIGHT", 10, -4)
            row.itemText:SetWidth(CONTENT_W - ICON_SIZE - MARGIN * 2 - 10 - 60) -- leaves room for the timer chip on the right
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(true)
            row.itemText:SetMaxLines(2)
```

Find:

```lua
            row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timerText:SetPoint("TOPRIGHT", -MARGIN, -8)
```

Replace with:

```lua
            row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timerText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            row.timerText:SetPoint("TOPRIGHT", -MARGIN, -(ACCENT_H + MARGIN + 2))
```

- [ ] **Step 4: Color the accent strip and enlarge the vote buttons**

Find (inside the per-row update section, right after `row.itemIconBorder:SetVertexColor(ir, ig, ib)`):

```lua
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
```

Add right after it:

```lua
        row.accentStrip:SetColorTexture(ir, ig, ib)
```

Find the button-sizing line inside the vote-button loop:

```lua
                btn:SetSize(btnW, btnH)
```

Leave this line as-is (it already uses the new `btnW`/`btnH` from Step 2 automatically) — no
change needed here, this step is just confirming it. Find instead:

```lua
                btn.text:ClearAllPoints()
                btn.text:SetPoint("CENTER", 6, 0)
```

Replace with:

```lua
                btn.text:ClearAllPoints()
                btn.text:SetPoint("CENTER", 8, 0)
                btn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
```

- [ ] **Step 5: Verify in-game**

Ensure `KART_Settings.lcVoteLayoutCompact` is off (default). `/reload`, open Loot Council
settings, click **Test (Looter)**. Confirm:
- Vote window is ~540px wide (roughly half the screen width at default UI scale — compare
  against the mockup at <https://claude.ai/code/artifact/284ff918-b018-430e-abfc-53a04432add3>,
  "Kasten-Stapel" section).
- 4 test items stack vertically, each with a colored strip along its top edge matching its item
  quality color, clearly separated by visible gaps.
- All vote buttons for each item sit in a single row (default button config has 5 categories).
- Casting a vote on one item hides its buttons/note and shows the "Voted: ..." badge, same as
  before.
- No Lua errors.

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua
git commit -m "Resize and restyle vote-window rows into the wider Spacious card layout"
```

---

### Task 4: Compact layout renderer (new)

**Files:**
- Modify: `LootCouncil.lua` (add a new function right after `LC.RefreshVoteListRows_Spacious`,
  i.e. after the code touched in Task 3)

**Interfaces:**
- Consumes: same shared state as Task 3 (`LC.voteListRolls`, `LC.rollItems`,
  `LC.rollDeadlines`, `LC.votes`, `LC.votedByMe`, `LC.votedNoteByMe`, `LC.GetButtonConfig()`,
  `IsRealItemLink`, `ParseItemColor`, `GetVoteIconTexture`, `IsTestRoll`,
  `KART.CreateGradientOverlay`, `KART.SetGradientOverlayColor`).
- Produces: `LC.RefreshVoteListRows_Compact(f)` — same contract as `_Spacious`: resizes `f`,
  (re)builds `f.compactRows[]`, sets `f:SetHeight(...)`. Every row in `f.compactRows` exposes
  `row.timerText` for the shared ticker.

- [ ] **Step 1: Write the function skeleton and row-recycling loop**

Add this new function right after the end of `LC.RefreshVoteListRows_Spacious` (i.e. after its
closing `end`):

```lua
-- "Compact" style: one short single-line row per item, vote buttons shrunk to icon-only chips.
-- Alternative for players who'd rather keep the window small than have large touch targets — see
-- docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function LC.RefreshVoteListRows_Compact(f)
    local WINDOW_W  = 430
    local CONTENT_W = WINDOW_W - 30
    f:SetWidth(WINDOW_W)
    f.scrollChild:SetWidth(CONTENT_W)

    local buttons  = LC.GetButtonConfig()
    local MARGIN   = 10
    local ICON_SIZE = 26
    local CHIP     = 24
    local CHIP_GAP = 5
    local HEADER_H = ICON_SIZE + MARGIN -- icon row height + top padding
    local ACTION_H = CHIP + 8           -- chip row height + its own top gap
    local rowH     = HEADER_H + ACTION_H + MARGIN -- + bottom padding
    local ROW_GAP  = 8

    f.compactRows = f.compactRows or {}

    for i, rollID in ipairs(LC.voteListRolls) do
        local row = f.compactRows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.scrollChild, "BackdropTemplate")
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.55)
            row:SetBackdropBorderColor(0, 0, 0, 1)

            row.itemIconBorder = row:CreateTexture(nil, "BACKGROUND")
            row.itemIconBorder:SetColorTexture(1, 1, 1, 1)

            row.itemIcon = row:CreateTexture(nil, "ARTWORK")
            row.itemIcon:SetSize(ICON_SIZE, ICON_SIZE)
            row.itemIcon:SetPoint("TOPLEFT", MARGIN, -MARGIN)
            row.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.itemIconBorder:SetPoint("TOPLEFT", row.itemIcon, -2, 2)
            row.itemIconBorder:SetPoint("BOTTOMRIGHT", row.itemIcon, 2, -2)

            row.itemCD = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
            row.itemCD:SetAllPoints(row.itemIcon)
            row.itemCD:SetHideCountdownNumbers(true)
            row.itemCD:SetDrawBling(false)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetPoint("TOPLEFT", row.itemIcon, "TOPRIGHT", 8, -2)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.itemHover = CreateFrame("Frame", nil, row)
            row.itemHover:SetPoint("TOPLEFT", row.itemIcon, "TOPLEFT")
            row.itemHover:SetPoint("BOTTOMRIGHT", row.itemText, "BOTTOMRIGHT")
            row.itemHover:EnableMouse(true)

            row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timerText:SetPoint("TOPRIGHT", -MARGIN, -MARGIN)

            row.chipArea = CreateFrame("Frame", nil, row)
            row.chipArea:SetPoint("TOPLEFT", row.itemIcon, "BOTTOMLEFT", 0, -8)
            row.chipButtons = {}

            row.votedBadge = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.votedBadge:SetPoint("LEFT", row.chipArea, "LEFT")
            row.votedBadge:SetHeight(CHIP)
            row.votedBadge:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.votedText = row.votedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.votedText:SetPoint("CENTER")

            -- Note is a floating overlay, not part of the row's own layout flow — this keeps
            -- every compact row a fixed, predictable height regardless of whether its note is
            -- open, so the vertical stacking math below never has to account for variable heights.
            row.notePencil = CreateFrame("Button", nil, row.chipArea)
            row.notePencil:SetSize(CHIP, CHIP)
            row.notePencil.text = row.notePencil:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.notePencil.text:SetPoint("CENTER")
            row.notePencil.text:SetText("\226\156\142") -- "✎"
            row.notePencil.text:SetTextColor(0.6, 0.6, 0.6)

            row.noteBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
            row.noteBox:SetFrameStrata("FULLSCREEN_DIALOG")
            row.noteBox:SetSize(200, 22)
            row.noteBox:SetAutoFocus(false)
            row.noteBox:SetMaxLetters(80)
            row.noteBox:SetFontObject("GameFontHighlightSmall")
            row.noteBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.noteBox:SetBackdropColor(0, 0, 0, 0.85)
            row.noteBox:SetTextInsets(6, 6, 0, 0)
            row.noteBox:SetPoint("TOPLEFT", row.notePencil, "BOTTOMLEFT", 0, -2)
            row.noteBox:Hide()
            row.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
            table.insert(KART.EditBoxes, row.noteBox)

            row.notePencil:SetScript("OnClick", function()
                if row.noteBox:IsShown() then
                    row.noteBox:Hide()
                else
                    row.noteBox:Show()
                    row.noteBox:SetFocus()
                end
            end)

            f.compactRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(rowH)
        row:Show()

        if row.currentRollID ~= rollID then
            row.currentRollID = rollID
            if row.noteBox then row.noteBox:SetText("") row.noteBox:Hide() end
        end

        local rollLink = LC.rollItems[rollID]
        row.itemText:SetText(rollLink or "???")
        row.itemText:SetWidth(CONTENT_W - ICON_SIZE - MARGIN * 2 - 8 - 60)

        local ir, ig, ib = ParseItemColor(rollLink)
        local iconTexture = IsRealItemLink(rollLink) and C_Item.GetItemIconByID(rollLink)
        if iconTexture then
            row.itemIcon:SetTexture(iconTexture)
            row.itemIcon:SetVertexColor(1, 1, 1)
        else
            row.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemIcon:SetVertexColor(ir, ig, ib)
        end
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
        row.itemText:SetTextColor(ir, ig, ib)

        local deadline  = LC.rollDeadlines[rollID]
        local remaining = deadline and math.max(0, math.ceil(deadline - GetTime())) or 0
        do
            local votedCount, total = LC.CountVotes(rollID)
            row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS or "(%d/%d)", votedCount, total))
        end
        if deadline then
            row.itemCD:SetCooldown(GetTime(), math.max(deadline - GetTime(), 0))
        end

        row.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[rollID]
            if not IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        row.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local voted    = LC.votedByMe[rollID]
        local votedDef = voted and buttons[tonumber(voted)]
        row.chipArea:SetShown(not voted)
        row.votedText:SetShown(voted ~= nil)
        row.votedBadge:SetShown(voted ~= nil)
        if voted then row.noteBox:Hide() end
        if votedDef then
            local label = votedDef.label
            local noteText = LC.votedNoteByMe[rollID]
            if noteText and noteText ~= "" then
                if #noteText > 30 then noteText = noteText:sub(1, 30) .. "..." end
                label = label .. " — \"" .. noteText .. "\""
            end
            row.votedText:SetText(string.format(KART.L.LC_VOTED_ROW, label))
            row.votedBadge:SetBackdropColor(votedDef.r, votedDef.g, votedDef.b, 0.18)
            row.votedBadge:SetBackdropBorderColor(votedDef.r, votedDef.g, votedDef.b, 0.7)
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, CONTENT_W - MARGIN * 2))
        end

        for bi = #buttons + 1, #row.chipButtons do
            if row.chipButtons[bi] then row.chipButtons[bi]:Hide() end
        end

        if not voted then
            for bi, def in ipairs(buttons) do
                local btn = row.chipButtons[bi]
                if not btn then
                    btn = CreateFrame("Button", nil, row.chipArea, "BackdropTemplate")
                    btn:SetSize(CHIP, CHIP)
                    btn:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
                    btn.grad = KART.CreateGradientOverlay(btn)
                    btn.iconTex = btn:CreateTexture(nil, "ARTWORK")
                    btn.iconTex:SetPoint("TOPLEFT", 4, -4)
                    btn.iconTex:SetPoint("BOTTOMRIGHT", -4, 4)
                    row.chipButtons[bi] = btn
                else
                    btn:Show()
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", row.chipArea, "TOPLEFT", (bi - 1) * (CHIP + CHIP_GAP), 0)
                btn:SetBackdropBorderColor(def.r, def.g, def.b, 1)
                KART.SetGradientOverlayColor(btn.grad, def.r, def.g, def.b, 0.22)
                btn.iconTex:SetTexture(GetVoteIconTexture(bi))

                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(def.label, def.r, def.g, def.b)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                local capturedIdx    = bi
                local capturedRollID = rollID
                btn:SetScript("OnClick", function()
                    if LC.votedByMe[capturedRollID] then return end
                    LC.votedByMe[capturedRollID] = capturedIdx
                    local note = KART.TrimString(row.noteBox and row.noteBox:GetText() or "")
                    LC.votedNoteByMe[capturedRollID] = note
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
                    row.notePencil:ClearAllPoints()
                    row.notePencil:SetPoint("LEFT", btn, "RIGHT", 6, 0)
                end
            end
        end
    end

    for i = #LC.voteListRolls + 1, #f.compactRows do
        if f.compactRows[i] then f.compactRows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #LC.voteListRolls * (rowH + ROW_GAP) + 12, 600))
end
```

- [ ] **Step 2: Verify in-game**

Toggle the new "Kompaktes Vote-Fenster verwenden" checkbox on (Task 2), then in the Loot Council
tab click **Test (Looter)**. Confirm:
- Window is ~430px wide, each of the 4 test items is a short single-line row (~40px tall).
- 5 small colored icon chips appear per row; hovering one shows its category label as a tooltip.
- Clicking a chip casts the vote (badge replaces the row content), same voting behavior as
  Spacious.
- Clicking the pencil icon opens a small note input below the row that doesn't shift any other
  row's position; typing a note and then voting shows the note text in the voted badge.
- No Lua errors.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "Add Compact vote-window layout renderer"
```

---

### Task 5: Dispatcher, ticker, and wiring

**Files:**
- Modify: `LootCouncil.lua` (add the new `LC.RefreshVoteListRows()` dispatcher; update
  `f.ticker` inside `LC.CreateVoteList`)

**Interfaces:**
- Consumes: `LC.RefreshVoteListRows_Spacious(f)` (Task 3), `LC.RefreshVoteListRows_Compact(f)`
  (Task 4), `KART_Settings.lcVoteLayoutCompact` (Task 2).
- Produces: `LC.RefreshVoteListRows()` — same public signature as before this whole plan started,
  so `LC.ShowVotePopup`, `LC.RemoveVoteListItem`, and every vote-button `OnClick` handler that
  already calls it need no changes.

- [ ] **Step 1: Add the dispatcher**

Add this function where the old `LC.RefreshVoteListRows()` used to start (right before
`LC.RefreshVoteListRows_Spacious`, which Task 3 renamed):

```lua
-- Thin dispatcher: resizes nothing itself, just picks which style actually builds the rows.
-- Hides the *inactive* style's row pool first so switching styles (or the very first refresh
-- after a `/reload`) never leaves a stale row from the other layout visible underneath.
function LC.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if not LC.voteListFrame then LC.CreateVoteList() end
    local f = LC.voteListFrame

    local compact = KART_Settings and KART_Settings.lcVoteLayoutCompact
    if compact then
        for _, row in ipairs(f.rows or {}) do row:Hide() end
        LC.RefreshVoteListRows_Compact(f)
    else
        for _, row in ipairs(f.compactRows or {}) do row:Hide() end
        LC.RefreshVoteListRows_Spacious(f)
    end
    f:Show()
end
```

Note: `f:Show()` moves here from the end of `_Spacious`/`_Compact` — remove the trailing
`f:Show()` line from the end of `LC.RefreshVoteListRows_Spacious` (Task 3's function) if it's
still there, since the dispatcher now owns it. `_Compact` (Task 4) never had one to remove.

- [ ] **Step 2: Make the ticker style-aware**

In `LC.CreateVoteList`, find:

```lua
        if changed then
            LC.RefreshVoteListRows()
        else
            for i, rid in ipairs(LC.voteListRolls) do
                local row = f.rows[i]
                if row and row:IsShown() then
```

Replace with:

```lua
        if changed then
            LC.RefreshVoteListRows()
        else
            local pool = (KART_Settings and KART_Settings.lcVoteLayoutCompact) and f.compactRows or f.rows
            for i, rid in ipairs(LC.voteListRolls) do
                local row = pool and pool[i]
                if row and row:IsShown() then
```

- [ ] **Step 3: Verify in-game — full pass**

`/reload`. In the Loot Council settings tab:
1. With the compact checkbox **off**, click **Test (Looter)** → confirm the Spacious layout from
   Task 3 renders correctly.
2. While it's still showing, tick the compact checkbox **on** → confirm the window immediately
   re-renders as the Compact layout (no leftover Spacious rows underneath, no Lua error).
3. Untick it again → confirm it switches back cleanly.
4. Let a test roll's timer run out (or reduce `lcVoteSeconds` to 5 first via the slider) →
   confirm the row disappears and the ticker doesn't error on the now-shorter `LC.voteListRolls`.
5. Vote on 2 of the 4 test items, leave 2 unvoted, wait a few seconds → confirm the "(x/y voted)"
   counts in the timer text update live for the still-unvoted rows in both styles.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "Wire up Spacious/Compact vote-window dispatcher and style-aware ticker"
```

---

### Task 6: Changelog

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

- [ ] **Step 1: Add an Unreleased entry to `CHANGELOG.md`**

Follow the existing `## [Unreleased]` section format used by prior entries (see recent commits
like `ef18b66` for the style). Summarize: vote window now offers two selectable personal layouts,
Spacious (new default, wider cards with more breathing room between simultaneous rolls) and
Compact (icon-chip rows for a smaller footprint), toggled via a new settings checkbox.

- [ ] **Step 2: Mirror the same entry into `CHANGELOG-de.md`** (German)

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "Update changelog for vote-window layout redesign"
```

---

## Self-Review Notes

- **Spec coverage:** Design doc's "Stil 1: Geräumig" → Task 3. "Stil 2: Kompakt" → Task 4.
  "Architektur" (setting, checkbox, dispatcher, shared ticker) → Tasks 2 and 5. "Lokalisierung" →
  Task 1. "Testing" (via `StartTest`) → verification steps in every task. "Offen für die
  Implementierung" (checkbox Y-offset) → resolved concretely in Task 2 (`-140`, `raidBox` shifted
  to `-180`), not left open.
- **Type/name consistency checked:** `row.timerText` is spelled identically in `_Spacious` and
  `_Compact` (required for Task 5's shared ticker to work against either pool).
  `f.rows` (Spacious) vs `f.compactRows` (Compact) are consistently named across Tasks 3-5.
  `LC.RefreshVoteListRows()` keeps its original zero-argument public signature so no caller
  elsewhere in the file needs to change.
