# UI Modernization Phase 5: LootCouncil Window Corners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Round the six standalone window frames in `LootCouncil.lua` using the Phase 1
foundation (`KART.ApplyRoundedMask`), completing the UI modernization pass across the whole
addon.

**Scope decision (confirmed with user before writing this plan):** `LootCouncil.lua` already
received a dedicated redesign on 2026-07-15
(`docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md`) covering the Vote window's
layout/spacing (Spacious/Compact styles) and explicitly declared "no shadows/soft edges — WoW
stays flat rectangles" (`Utils.lua`'s `KART.ApplyRoundedMask` didn't exist yet at that time). The
Council Panel's row layout was explicitly out of scope for that redesign too. Re-touching either
of those now would be redundant with — or second-guess — very recent, deliberate design work. A
codebase check found:
- 19 calls to `KART.CreateModernButton`/`CreateSettingsCheckbox`/`CreateSettingsSlider` in this
  file already inherited the modernized look automatically when Phase 1 merged — no work needed.
- 0 calls to `KART.ApplyRoundedMask` anywhere in this file — the six standalone window frames are
  still sharp-cornered, unlike every other window across the rest of the addon (MainFrame,
  BuffChecker, Loot History, Raidlead Bar, Ready-Check dialog, WoWUtils panel — all rounded in
  earlier phases).

This plan's scope is therefore narrow and deliberate: round only the six outer window frames.
Per-item vote cards, council panel rows, and all layout/spacing decisions from the 2026-07-15
redesign are explicitly **not** touched.

**Architecture:** No new primitives needed — consumes `KART.ApplyRoundedMask` and
`KART.Theme.CORNER_RADIUS_LG`, both already in `Utils.lua` from Phase 1. Each of the six frames
gets exactly one `KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)` call, inserted
immediately after that frame's own `SetBackdropBorderColor` call — the same placement convention
used in every prior phase. All six frames are given an explicit `SetSize` before this insertion
point, so `ApplyRoundedMask`'s min-size guard (16px) never blocks any of them. Corner masks are
anchored per-corner (not stretched across the whole region — see Phase 1's Task 2 fix), so later
resizes of these frames (e.g. the Council Panel's minimize/restore between `COUNCIL_PANEL_HEIGHT`
and `COUNCIL_PANEL_MIN_H`, or the Vote List/Trade Reminder growing to fit more rows) do not
invalidate the rounding — no `OnSizeChanged` re-application is needed, matching the reasoning
already verified for the Buff-Checker and Loot History windows in earlier phases.

**Tech Stack:** Lua 5.1 (WoW addon runtime), WoW retail Frame API.

## Global Constraints

- No new graphic/icon assets.
- No automated test runner exists for this addon — every verification step here is a manual
  in-game check, described but not executable in this pipeline. `LootCouncil.lua` has its own
  Test Mode buttons (simulating both the looter's vote-list view and the loot-master's council
  panel, per `README.md`'s "Test Mode" feature) — use those where the brief references them.
- Code comments and commit messages in English (per `CLAUDE.md`).
- No SavedVariables schema changes.
- `KART.RegisterStrataFrame` (pre-existing, unrelated helper already used on all six frames) must
  remain untouched.
- Do NOT touch: `LC.RefreshVoteListRows_Spacious`/`_Compact` (per-item vote card layout/sizing),
  `LC.RefreshCouncilRows` (council panel row layout), the tab strip (`f.tabStrip`), or any
  color/spacing decision from the 2026-07-15 redesign. This plan's diff must touch only the six
  named frame-creation call sites, one line each.

---

### Task 1: Round all six LootCouncil window frames

**Files:**
- Modify: `LootCouncil.lua:328-334` (`LC.sessionPromptFrame`'s creation, inside the function that
  builds it around line 328)
- Modify: `LootCouncil.lua:482-491` (`KART_LCVoteList` frame creation)
- Modify: `LootCouncil.lua:1548-1557` (`KART_LCCouncilPanel` frame creation)
- Modify: `LootCouncil.lua:2630-2639` (`KART_LCTradeReminder` frame creation)
- Modify: `LootCouncil.lua:2838-2844` (`KART_LCOfficerNoteDialog` frame creation)
- Modify: `LootCouncil.lua:2945-2951` (`LC.winnerFrame` / `KART_LCWinnerFrame` creation)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG` (Phase 1,
  `Utils.lua`)

- [ ] **Step 1: Round the Session Prompt dialog**

Replace `LootCouncil.lua:328-334`:

```lua
    local f = CreateFrame("Frame", "KART_LCSessionPrompt", UIParent, "BackdropTemplate")
    f:SetSize(310, 115)
    f:SetPoint("CENTER", 0, 120)
    KART.RegisterStrataFrame(f, true)
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
    local f = CreateFrame("Frame", "KART_LCSessionPrompt", UIParent, "BackdropTemplate")
    f:SetSize(310, 115)
    f:SetPoint("CENTER", 0, 120)
    KART.RegisterStrataFrame(f, true)
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 2: Round the Vote List window**

Replace `LootCouncil.lua:482-491`:

```lua
    local f = CreateFrame("Frame", "KART_LCVoteList", UIParent, "BackdropTemplate")
    f:SetSize(380, 200)
    f:SetPoint("CENTER", 0, -80)
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
    local f = CreateFrame("Frame", "KART_LCVoteList", UIParent, "BackdropTemplate")
    f:SetSize(380, 200)
    f:SetPoint("CENTER", 0, -80)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

(Note: this frame is resized dynamically by `LC.RefreshVoteListRows_Spacious`/`_Compact` as rows
are added — per the Architecture section above, this is fine; the corner masks track the frame's
live corners without needing re-application.)

- [ ] **Step 3: Round the Council Panel**

Replace `LootCouncil.lua:1548-1557`:

```lua
    local f = CreateFrame("Frame", "KART_LCCouncilPanel", UIParent, "BackdropTemplate")
    f:SetSize(COUNCIL_PANEL_WIDTH, COUNCIL_PANEL_HEIGHT)
    f:SetPoint("CENTER", 220, 0)
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
    local f = CreateFrame("Frame", "KART_LCCouncilPanel", UIParent, "BackdropTemplate")
    f:SetSize(COUNCIL_PANEL_WIDTH, COUNCIL_PANEL_HEIGHT)
    f:SetPoint("CENTER", 220, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

(Note: `f.tabStrip`, the vertical tab strip protruding from the left edge, is a separate child
frame positioned outside `f`'s own bounds with a 30px top / 40px bottom inset — well clear of the
6px corner-mask radius, so no visual collision with the now-rounded left corners. Do not modify
`f.tabStrip` itself. Also note: this frame's height later toggles between `COUNCIL_PANEL_HEIGHT`
(462) and `COUNCIL_PANEL_MIN_H` (68) for the minimize feature — both comfortably clear the 16px
min-size guard, and per the Architecture section, no re-application is needed on that resize
either.)

- [ ] **Step 4: Round the Trade Reminder window**

Replace `LootCouncil.lua:2630-2639`:

```lua
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(260, 40)
    f:SetPoint("CENTER", -220, 0)
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
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(260, 40)
    f:SetPoint("CENTER", -220, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 5: Round the Officer Note dialog**

Replace `LootCouncil.lua:2838-2844`:

```lua
        local f = CreateFrame("Frame", "KART_LCOfficerNoteDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
        local f = CreateFrame("Frame", "KART_LCOfficerNoteDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 6: Round the Winner notification window**

Replace `LootCouncil.lua:2945-2951`:

```lua
        local f = CreateFrame("Frame", "KART_LCWinnerFrame", UIParent, "BackdropTemplate")
        f:SetSize(290, 75)
        f:SetPoint("CENTER", 0, 160)
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.04, 0.18, 0.04, 0.97)
        f:SetBackdropBorderColor(0.1, 0.9, 0.1, 1)
```

with:

```lua
        local f = CreateFrame("Frame", "KART_LCWinnerFrame", UIParent, "BackdropTemplate")
        f:SetSize(290, 75)
        f:SetPoint("CENTER", 0, 160)
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        f:SetBackdropColor(0.04, 0.18, 0.04, 0.97)
        f:SetBackdropBorderColor(0.1, 0.9, 0.1, 1)
        KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

Note this window intentionally keeps its own fixed green success color (not derived from
`KART.Theme`/accent) — that's existing, deliberate behavior (a green "you won" notification
should stay green regardless of the user's chosen accent color) and is out of scope to change.

- [ ] **Step 7: Manual verification**

Run: `/reload`, then exercise each of the six windows via the addon's own Test Mode where
available (per `README.md`'s Loot Council "Test Mode" feature — two test buttons simulate the
looter's vote-list view and the loot-master's council panel, including simultaneous multi-item
drops) and via normal flow for the rest:
- Session Prompt: enter a raid instance (or use test mode) to trigger "Enable Loot Council for
  this session?"
- Vote List: trigger the looter test button, check both Spacious and Compact layouts (toggle via
  Settings) still render with rounded outer corners regardless of style.
- Council Panel: trigger the loot-master test button, including its minimized state (minimize
  button) — corners should stay rounded in both states.
- Trade Reminder: complete a test assignment that requires a trade.
- Officer Note dialog: right-click a candidate row → "Edit Note".
- Winner notification: complete a test roll assignment.

Expected: all six windows show rounded outer corners; none of the internal row/card layouts,
spacing, or colors from the 2026-07-15 redesign changed.

- [ ] **Step 8: Commit**

```bash
git add LootCouncil.lua
git commit -m "Round LootCouncil's six standalone window frames"
```
