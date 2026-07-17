# UI Modernization Phase 2: BuffChecker Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Phase 1 theme foundation (`docs/superpowers/plans/2026-07-17-ui-modernization-phase1-foundation.md`,
already merged) to the Buff-Checker window (`BuffChecker.lua`): round the window's outer corners,
route its scattered ad-hoc status colors through the fixed `KART.Theme.SUCCESS/WARNING/DANGER`
constants, and add subtle alternating row backgrounds so the dense player grid is easier to scan.

**Architecture:** No new primitives needed — this phase only *consumes* what Phase 1 already
built (`KART.ApplyRoundedMask`, `KART.Theme`). `KART.CreateModernButton` calls in this file
(`modeBtn`, `refreshBtn`, `reportBtn`) already picked up the modernized rounded/accent-hover look
automatically when Phase 1 merged — no changes needed to those three buttons.

**Tech Stack:** Lua 5.1 (WoW addon runtime), WoW retail Frame API.

## Global Constraints

- No new graphic/icon assets.
- No automated test runner exists for this addon — every verification step here is a manual
  in-game check (`/reload`, then open the Buff-Checker via its preview button or a real ready
  check), described but not executable in this pipeline.
- Code comments and commit messages in English (per `CLAUDE.md` — note existing comments in this
  file are German; leave those as-is, only new/modified lines must be English).
- `KART.Theme.SUCCESS/WARNING/DANGER` are `{r, g, b}` 0-1 arrays (index 1/2/3), consumed with
  `unpack(...)` — same pattern already used elsewhere in the merged Phase 1 code.
- Elements smaller than `KART.Theme.CORNER_RADIUS_MIN_SIZE` (16px, either dimension) skip
  rounding via `KART.ApplyRoundedMask`'s own guard — no need to special-case small elements here.
- Preserve all existing SavedVariables (`KART_Settings.bcWidth/bcHeight/bcPoint/...`) — no schema
  changes.

---

### Task 1: Round the Buff-Checker window's outer corners

**Files:**
- Modify: `BuffChecker.lua:80-88` (`f:SetBackdrop(...)` / `f.gradientBg` block inside
  `KART.CreateBuffCheckFrame`)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG` (both from
  Phase 1, already in `Utils.lua`)

- [ ] **Step 1: Apply the rounded mask after the frame's backdrop is set**

Replace `BuffChecker.lua:80-88`:

```lua
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetFrameStrata("HIGH")
    f.gradientBg = KART.CreateGradientOverlay(f)
    KART.AddShowFade(f)
```

with:

```lua
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetFrameStrata("HIGH")
    f.gradientBg = KART.CreateGradientOverlay(f)
    KART.AddShowFade(f)

    -- Round the window's outer corners to match the modernized MainFrame. The frame is created
    -- with an explicit SetSize above (never 0x0), so ApplyRoundedMask's min-size guard never
    -- blocks this — safe to call once here rather than hooking OnSizeChanged like KART.CreateCard
    -- does (that frame starts unsized; this one doesn't).
    KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, then `/kart` → BuffCheck tab → "Preview Buff Check" button.
Expected: the Buff-Checker window's four outer corners are visibly rounded instead of sharp
rectangles, matching the rounded look of the main `/kart` window. Resize the window via its
bottom-right grabber — corners should stay rounded (mask was applied once at creation to a
frame whose initial size never changes to 0x0, so no re-application is needed on resize; unlike
`CreateCard`, this frame's rounding doesn't depend on a later `SetSize` call).

- [ ] **Step 3: Commit**

```bash
git add BuffChecker.lua
git commit -m "Round Buff-Checker window's outer corners"
```

---

### Task 2: Route status colors through `KART.Theme`

**Files:**
- Modify: `BuffChecker.lua:366-425` (`setInd` local function)
- Modify: `BuffChecker.lua:537-581` (preview-mode color logic inside `KART.UpdateBuffCheck`)

**Interfaces:**
- Consumes: `KART.Theme.SUCCESS`, `KART.Theme.WARNING`, `KART.Theme.DANGER` (each `{r,g,b}`,
  from Phase 1, already in `Utils.lua`)

Only the three colors that have a direct Theme equivalent are replaced (green "good" →
`SUCCESS`, orange "warning threshold" → `WARNING`, red "missing/bad" → `DANGER`). Colors with no
Theme equivalent (expiring-yellow `1,0.8,0`, wrong-oil-purple `0.8,0.3,0.9`, unknown-gray
`0.5,0.5,0.5`, full-white `1,1,1`) are left as literals — adding new Theme fields for them is out
of this task's scope (the design spec only defines SUCCESS/WARNING/DANGER).

- [ ] **Step 1: Update `setInd`'s repair-percentage thresholds**

Replace `BuffChecker.lua:371-379`:

```lua
    if buffData.isRepair then
        local textObj = ind.text or ind
        textObj:SetText(math.floor(has) .. "%")
        if has < 20 then textObj:SetTextColor(1, 0.2, 0.2)
        elseif has < 50 then textObj:SetTextColor(1, 0.6, 0)
        else textObj:SetTextColor(0.2, 1, 0.2) end
        ind.tooltipTitle = nil
        ind.missingSlots = nil
        return
    end
```

with:

```lua
    if buffData.isRepair then
        local textObj = ind.text or ind
        textObj:SetText(math.floor(has) .. "%")
        if has < 20 then textObj:SetTextColor(unpack(KART.Theme.DANGER))
        elseif has < 50 then textObj:SetTextColor(unpack(KART.Theme.WARNING))
        else textObj:SetTextColor(unpack(KART.Theme.SUCCESS)) end
        ind.tooltipTitle = nil
        ind.missingSlots = nil
        return
    end
```

- [ ] **Step 2: Update `setInd`'s gear-check OK/missing colors**

Replace `BuffChecker.lua:382-399`:

```lua
    if buffData.isGearCheck then
        local textObj = ind.text or ind
        if has == "unknown" or not has then
            textObj:SetText("?")
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.missingSlots = nil
        elseif has == "0" then
            textObj:SetText("OK")
            textObj:SetTextColor(0.2, 1, 0.2)
            ind.missingSlots = nil
        else
            local count = select(2, has:gsub(",", "")) + 1
            textObj:SetText("-" .. count)
            textObj:SetTextColor(1, 0.2, 0.2)
            ind.missingSlots = has
            ind.tooltipTitle = buffData.reportLabel or buffData.label
        end
        return
    end
```

with:

```lua
    if buffData.isGearCheck then
        local textObj = ind.text or ind
        if has == "unknown" or not has then
            textObj:SetText("?")
            textObj:SetTextColor(0.5, 0.5, 0.5)
            ind.missingSlots = nil
        elseif has == "0" then
            textObj:SetText("OK")
            textObj:SetTextColor(unpack(KART.Theme.SUCCESS))
            ind.missingSlots = nil
        else
            local count = select(2, has:gsub(",", "")) + 1
            textObj:SetText("-" .. count)
            textObj:SetTextColor(unpack(KART.Theme.DANGER))
            ind.missingSlots = has
            ind.tooltipTitle = buffData.reportLabel or buffData.label
        end
        return
    end
```

- [ ] **Step 3: Update `setInd`'s buff-indicator "best"/missing icon tint**

Replace `BuffChecker.lua:406-424` (inside the `ind:SetDesaturated(not has)` branch):

```lua
    if has == "expiring" then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 0.8, 0)
                elseif has == "best" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(0.2, 1, 0.2) -- Grün für besten Rang
                elseif has == "wrong" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(0.8, 0.3, 0.9) -- Lila für falschen Rang
                elseif has == "unknown" then
                    ind:SetAlpha(0.3)
                    ind:SetVertexColor(0.5, 0.5, 0.5) -- Grau für fremde Spieler
    elseif has then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 1, 1)
    elseif classNeeded and not classes[classNeeded] then
        ind:SetAlpha(0.1)
        ind:SetVertexColor(0.5, 0.5, 0.5)
    else
        ind:SetAlpha(0.6)
        ind:SetVertexColor(1, 0.2, 0.2)
    end
```

with (only the two DANGER-equivalent branches and the "best" SUCCESS branch change; everything
else — including indentation quirks already present in the file — stays byte-identical):

```lua
    if has == "expiring" then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 0.8, 0)
                elseif has == "best" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(unpack(KART.Theme.SUCCESS))
                elseif has == "wrong" then
                    ind:SetAlpha(1.0)
                    ind:SetVertexColor(0.8, 0.3, 0.9) -- purple, no Theme equivalent
                elseif has == "unknown" then
                    ind:SetAlpha(0.3)
                    ind:SetVertexColor(0.5, 0.5, 0.5) -- gray, no Theme equivalent
    elseif has then
        ind:SetAlpha(1.0)
        ind:SetVertexColor(1, 1, 1)
    elseif classNeeded and not classes[classNeeded] then
        ind:SetAlpha(0.1)
        ind:SetVertexColor(0.5, 0.5, 0.5)
    else
        ind:SetAlpha(0.6)
        ind:SetVertexColor(unpack(KART.Theme.DANGER))
    end
```

- [ ] **Step 4: Update the preview-mode duplicate logic**

The `isPreview` branch inside `KART.UpdateBuffCheck` (`BuffChecker.lua:537-581`) duplicates the
same color choices for the 5 fake preview rows. Find and replace each matching literal with its
Theme equivalent, mirroring exactly the substitutions from Steps 1-3 above (repair `85%` →
`KART.Theme.SUCCESS`; gear-check `-1`/`OK` → `KART.Theme.DANGER`/`KART.Theme.SUCCESS`; the
"missing" red block inside the `(i + j) % 3 == 0` branch → `KART.Theme.DANGER`; the "vorhanden"
white block and the oil purple/green blocks stay as literals per the same no-Theme-equivalent
rule). Read the actual current file content for this range before editing — line numbers may
have shifted slightly after Steps 1-3's edits — and search for the literal RGB triples
`1, 0.2, 0.2` / `0.2, 1, 0.2` within this `isPreview` block specifically (not the two you already
changed in `setInd`, which is a different function above this one).

- [ ] **Step 5: Manual verification**

Run: `/reload`, then `/kart` → BuffCheck tab → "Preview Buff Check".
Expected: preview rows render identically to before this change (same colors visually — green
stays green, red stays red, orange stays orange) since `KART.Theme.SUCCESS/WARNING/DANGER`'s
default values are close to the original hard-coded literals. Toggle "Ansicht: Erweitert" to
check the gear-check `-1`/`OK` columns render with the same red/green as before.

- [ ] **Step 6: Commit**

```bash
git add BuffChecker.lua
git commit -m "Route Buff-Checker status colors through KART.Theme"
```

---

### Task 3: Alternating row backgrounds

**Files:**
- Modify: `BuffChecker.lua:142-224` (row-pool creation loop inside `KART.CreateBuffCheckFrame`)
- Modify: `BuffChecker.lua:603-607` (per-row loop inside `KART.UpdateBuffCheck`, where `row:Show()`
  is eventually called)

**Interfaces:**
- Consumes: `KART.Theme.Lighten` (Phase 1, `Utils.lua`)
- Produces: `row.stripeBg` (a `Texture` on each pooled row), shown/colored based on the row's
  index parity so the 40-row pool reads as alternating light/dark bands.

- [ ] **Step 1: Add a background stripe texture to each pooled row**

Find the row-pool loop in `KART.CreateBuffCheckFrame` (`BuffChecker.lua:144-147`, the
`for i = 1, 40 do local row = CreateFrame(...) ... end` block). Directly after the row's
`SetPoint` call and before `row.rcIcon = ...`, insert:

```lua
        -- Subtle alternating background so a dense 40-row player grid is easier to scan
        -- horizontally. Colored per-row in KART.UpdateBuffCheck (parity depends on the row's
        -- position in the currently-visible list, not its pool index, since rows are reused/
        -- reordered as group membership changes).
        row.stripeBg = row:CreateTexture(nil, "BACKGROUND")
        row.stripeBg:SetAllPoints(row)
        row.stripeBg:SetColorTexture(1, 1, 1, 1) -- color set per-frame below; alpha applied via SetVertexColor alpha channel
```

- [ ] **Step 2: Color and show the stripe per row during the update pass**

Find the per-player loop in `KART.UpdateBuffCheck` (`BuffChecker.lua:603`, `for i = 1, iterMax do
... local row = KART.BuffCheckFrame.rows[i] ...`). Directly after the line `local row =
KART.BuffCheckFrame.rows[i]`, insert:

```lua
        if row.stripeBg then
            if i % 2 == 0 then
                local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
                local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
                row.stripeBg:SetColorTexture(lr, lg, lb, 0.5)
            else
                row.stripeBg:Hide()
            end
        end
```

Then find the line a few statements later that shows the row (`row:Show()`, near the end of the
per-player loop body, `BuffChecker.lua:851` in the pre-Task-3 file) and add, directly before it:

```lua
        if row.stripeBg and i % 2 == 0 then row.stripeBg:Show() end
```

(Even rows are shown/colored above; odd rows are explicitly hidden above so the stripe never
lingers from a previous update pass on a row that's now odd-indexed.)

Also handle the `isPreview` branch (`BuffChecker.lua:509`, `for i = 1, 5 do local row =
KART.BuffCheckFrame.rows[i] ...`) the same way: add the identical `if row.stripeBg then ... end`
block (Lighten-based coloring for even `i`, `Hide()` for odd `i`) right after `local row =
KART.BuffCheckFrame.rows[i]` in that loop too, so the preview view also shows the striping.

- [ ] **Step 3: Hide stray stripes on rows outside the currently-visible range**

The existing `for _, row in ipairs(KART.BuffCheckFrame.rows) do row:Hide() end` near the top of
`KART.UpdateBuffCheck` (`BuffChecker.lua:492`) already hides the whole row (which implicitly hides
`stripeBg` too, since it's a child texture of a hidden frame) before each update pass rebuilds the
visible subset — no additional cleanup needed here. Confirm this by reading that line: it must
run before Steps 1-2's per-row logic on every call, which it already does (it's the very first
thing `KART.UpdateBuffCheck` does after the missing-buffs table reset).

- [ ] **Step 4: Manual verification**

Run: `/reload`, then `/kart` → BuffCheck tab → "Preview Buff Check". Expected: the 5 preview rows
alternate between the window's base background and a very slightly lighter tint, banding every
other row. Then close preview and run a real ready check (or `/reload` while grouped) to see it
with real player rows. Resize the window and scroll (if >40 players is not testable, at least
confirm no visual artifacts with the available group size) — stripes should stay aligned to their
row, not drift.

- [ ] **Step 5: Commit**

```bash
git add BuffChecker.lua
git commit -m "Add alternating row backgrounds to Buff-Checker player list"
```
