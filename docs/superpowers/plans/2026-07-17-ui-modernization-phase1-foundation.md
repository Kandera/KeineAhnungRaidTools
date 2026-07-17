# UI Modernization Phase 1: Theme Foundation + MainFrame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared, reusable "modern theme" primitives (rounded corners, toggle-switch
checkboxes, redesigned sliders/buttons, card panels, accent-driven hover states) in `Utils.lua`
and wire them into `MainFrame.lua`, so the main `/kart` config window (Sidebar, Automation,
Raidlead, BuffCheck, Settings tabs) is fully modernized and every other window that already
calls the shared factory functions (`CreateModernButton`, `CreateSettingsCheckbox`,
`CreateSettingsSlider`) picks up the new look automatically.

**Architecture:** Pure native WoW Frame API (`CreateFrame`/`BackdropTemplate`/`MaskTexture`), no
new dependencies. A new `KART.Theme` table centralizes color-derivation math and corner-radius
constants; a new `KART.ApplyRoundedMask` helper wraps `SetMask` with a `pcall` safety net and an
automatic small-element fallback. Existing factory functions are edited in place — their public
signatures are unchanged, so every existing call site across the addon keeps working without
modification.

**Tech Stack:** Lua 5.1 (WoW addon runtime), WoW retail Frame API (`CreateMaskTexture`,
`SetMask`, `BackdropTemplate`), `LibSharedMedia-3.0` (already a dependency, for fonts).

## Global Constraints

- No new grafik/icon assets — everything must be buildable from `CreateTexture`/`CreateMaskTexture`
  and existing Blizzard shared textures (see spec `docs/superpowers/specs/2026-07-17-ui-modernization-design.md`).
- The existing accent-/background-color picker system (`KART_Settings.accentR/G/B`,
  `bgR/G/B`) must keep working — no new SavedVariables fields, no schema change to
  `KART.Defaults` in `Utils.lua:13-51`.
- All `SetMask` usage must be wrapped in `pcall` (API shape varies across client versions) with a
  clean fallback to unrounded corners — never let a mask failure break layout or visibility.
- Elements smaller than `KART.Theme.CORNER_RADIUS_MIN_SIZE` (16px, in either dimension) skip
  rounding entirely.
- No automated test runner exists for this addon (Lua/WoW client only, confirmed via
  `.github/workflows/release.yml` — release-only, no lint/test job). Every verification step in
  this plan is a manual in-game check: `/reload`, then `/kart`, then a described visual
  inspection. Follow the project's own testing convention of using existing "Test Mode" buttons
  where available.
- Code comments in English only (per `CLAUDE.md`).
- Commit messages in English.

---

### Task 1: Theme tokens and color-derivation helpers

**Files:**
- Modify: `Utils.lua` (add new section after line 97, before `-- UI Factory: Modern Button`)

**Interfaces:**
- Produces: `KART.Theme.CORNER_RADIUS_LG` (number, 6), `KART.Theme.CORNER_RADIUS_SM` (number, 3),
  `KART.Theme.CORNER_RADIUS_MIN_SIZE` (number, 16), `KART.Theme.SUCCESS` / `WARNING` / `DANGER`
  (each `{r, g, b}` 0-1 tables), `KART.Theme.Lighten(r, g, b, amount)` → `r, g, b`,
  `KART.Theme.Darken(r, g, b, amount)` → `r, g, b`.

- [ ] **Step 1: Add the `KART.Theme` table with constants**

Insert into `Utils.lua` right after line 97 (`return "Fonts\\FRIZQT__.TTF"` / `end`), before the
`-- UI Factory: Modern Button` comment:

```lua
-- Central theme tokens: corner radii, fixed status colors, and color-derivation helpers used by
-- every UI factory function below. Kept as plain data + pure functions (no frame references) so
-- KART.UpdateStyles() can call these fresh on every settings change without caching stale colors.
KART.Theme = {
    CORNER_RADIUS_LG = 6,       -- panels, cards, main window
    CORNER_RADIUS_SM = 3,       -- buttons, checkboxes, slider thumb
    CORNER_RADIUS_MIN_SIZE = 16, -- elements smaller than this (either dimension) stay unrounded

    SUCCESS = {0.35, 0.75, 0.35},
    WARNING = {0.90, 0.70, 0.20},
    DANGER  = {0.85, 0.30, 0.30},
}

-- Lightens/darkens an RGB triple by `amount` (0-1), clamped to [0,1]. Used to derive hover/
-- pressed/disabled states from the user's chosen accent or background color instead of hard-
-- coding separate state colors that would drift out of sync with a custom accent.
function KART.Theme.Lighten(r, g, b, amount)
    return math.min(r + amount, 1), math.min(g + amount, 1), math.min(b + amount, 1)
end

function KART.Theme.Darken(r, g, b, amount)
    return math.max(r - amount, 0), math.max(g - amount, 0), math.max(b - amount, 0)
end
```

- [ ] **Step 2: Manual verification**

Run: `/reload` in-game, then `/kart` to open the main window.
Expected: window still opens normally, no Lua error (check with `/console scriptErrors 1`
beforehand if unsure). This step only adds data/pure functions, so nothing visible changes yet —
the check confirms no syntax error was introduced.

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Add KART.Theme constants and color-derivation helpers"
```

---

### Task 2: Rounded-corner mask helper

**Files:**
- Modify: `Utils.lua` (add after the `KART.Theme` block from Task 1)

**Interfaces:**
- Consumes: `KART.Theme.CORNER_RADIUS_MIN_SIZE` (Task 1)
- Produces: `KART.ApplyRoundedMask(frame, radius)` — applies a rounded-corner mask to `frame`'s
  backdrop (and `frame.gradientBg` if present); safe no-op on failure or on elements below the
  minimum size. Idempotent — safe to call again after a resize.

- [ ] **Step 1: Add `KART.ApplyRoundedMask`**

```lua
-- Applies a rounded-corner mask to a BackdropTemplate frame's backdrop artwork (and its gradient
-- overlay, if any — see KART.CreateGradientOverlay). Uses WoW's built-in scalable circle mask
-- texture cropped per-corner rather than a custom asset, since no image-generation tool is
-- available for this project (see docs/superpowers/specs/2026-07-17-ui-modernization-design.md).
-- Wrapped in pcall: SetMask's exact behavior has shifted across client versions, and a failure
-- here must never break the frame's layout or visibility, only skip the rounding.
function KART.ApplyRoundedMask(frame, radius)
    if not frame then return end
    local w, h = frame:GetWidth(), frame:GetHeight()
    if w < KART.Theme.CORNER_RADIUS_MIN_SIZE or h < KART.Theme.CORNER_RADIUS_MIN_SIZE then
        return -- too small to round without looking broken
    end

    local function maskRegion(region)
        if not region then return end
        local ok, mask = pcall(function()
            local m = frame:CreateMaskTexture(nil, "OVERLAY")
            m:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(region)
            region:AddMaskTexture(m)
            return m
        end)
        if not ok then return end
        return mask
    end

    if frame.backdropTexture then maskRegion(frame.backdropTexture) end
    -- BackdropTemplate doesn't expose its background texture by name; fall back to scanning
    -- regions for the backdrop's own artwork layer.
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then
            maskRegion(region)
        end
    end
    if frame.gradientBg then maskRegion(frame.gradientBg) end
end
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, then in-game execute:
```
/run KART.ApplyRoundedMask(KART.MainFrame, KART.Theme.CORNER_RADIUS_LG)
```
Expected: no Lua error printed to chat. (Visual confirmation of actual rounding happens once this
is wired into a real frame in Task 3+ — this step only confirms the helper itself doesn't error.)

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Add KART.ApplyRoundedMask corner-rounding helper"
```

---

### Task 3: Modernize `CreateModernButton`

**Files:**
- Modify: `Utils.lua:99-130` (existing `KART.CreateModernButton` function)

**Interfaces:**
- Consumes: `KART.Theme.Lighten/Darken` (Task 1), `KART.ApplyRoundedMask` (Task 2)
- Produces: `KART.CreateModernButton(parent, text, tooltipText)` — same signature and return
  value (a `Button` frame with `.text` FontString) as before, so every existing call site
  (`MainFrame.lua`, `BuffChecker.lua`, `LootCouncil.lua`, etc.) keeps working unchanged.

- [ ] **Step 1: Replace the function body**

Replace `Utils.lua:99-130` (from `-- UI Factory: Modern Button` through the closing `end` of
`CreateModernButton`) with:

```lua
-- UI Factory: Modern Button
function KART.CreateModernButton(parent, text, tooltipText)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(130, 25)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(b, KART.Theme.CORNER_RADIUS_SM)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    table.insert(KART.ButtonTexts, b.text)

    -- Hover/leave color fade uses a short alpha-blended color animation instead of an instant
    -- SetBackdropColor swap, and derives from the user's accent color (KART_Settings.accentR/G/B)
    -- via KART.Theme.Lighten rather than a hard-coded gray, so custom accent colors are respected
    -- in the hover state too.
    local function hoverColor()
        local r = (KART_Settings and KART_Settings.accentR or 0) / 100
        local g = (KART_Settings and KART_Settings.accentG or 60) / 100
        local bl = (KART_Settings and KART_Settings.accentB or 100) / 100
        return KART.Theme.Darken(r, g, bl, 0.55) -- darkened accent, not full brightness, so text stays readable
    end

    b:SetScript("OnEnter", function(self)
        local r, g, bl = hoverColor()
        self:SetBackdropColor(r, g, bl, 1)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        GameTooltip:Hide()
    end)
    return b
end
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, then `/kart`. Hover over any sidebar tab button or a settings button (e.g. "Select
Font" in the Settings tab).
Expected: button corners are visibly rounded (not sharp rectangles), and hovering tints the
button toward the configured accent color (default: dark blue) instead of flat gray. Click
around to confirm buttons still trigger their actions (tabs still switch, font/language menus
still open).

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Modernize CreateModernButton: rounded corners, accent-derived hover"
```

---

### Task 4: Toggle-switch checkboxes

**Files:**
- Modify: `Utils.lua:132-173` (existing `KART.CreateSettingsCheckbox` function)

**Interfaces:**
- Consumes: `KART.Theme.Lighten/Darken` (Task 1), `KART.ApplyRoundedMask` (Task 2)
- Produces: `KART.CreateSettingsCheckbox(parent, name, labelText, settingKey, yOffset, callback,
  tooltipText)` — same signature and return value (a `CheckButton`) as before. `cb:GetChecked()`
  and `cb:SetChecked()` keep working since it's still a real `CheckButton`; only the visuals
  change from square+checkmark to a pill-shaped switch with a sliding dot.

- [ ] **Step 1: Replace the function body**

Replace `Utils.lua:132-173` (from `-- Weitere UI-Hilfsfunktionen...` through the closing `end` of
`CreateSettingsCheckbox`) with:

```lua
-- Weitere UI-Hilfsfunktionen (Slider/Checkbox) hier implementieren...
-- Toggle-switch style: a pill-shaped track (34x16) with a round dot that slides between left
-- (off) and right (on). Still a real CheckButton under the hood so GetChecked/SetChecked and the
-- existing OnClick wiring below are unchanged for every call site.
function KART.CreateSettingsCheckbox(parent, name, labelText, settingKey, yOffset, callback, tooltipText)
    local cb = CreateFrame("CheckButton", name, parent, "BackdropTemplate")
    cb:SetSize(34, 16)
    cb:SetPoint("TOPLEFT", 20, yOffset)

    cb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(0, 0, 0, 0.5)
    cb:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    -- Pill track is fully rounded: half its own height, which is below CORNER_RADIUS_MIN_SIZE, so
    -- it needs its own mask call with a radius large enough to round the full end-caps rather than
    -- going through the generic small-corner path.
    KART.ApplyRoundedMask(cb, 8)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.text:SetText(labelText)
    table.insert(KART.DynamicLabels, cb.text)

    -- Sliding dot: positioned left when unchecked, right when checked. Reused as the "checked
    -- texture" so WoW's own CheckButton show/hide-on-check logic still drives visibility, but its
    -- position (not just visibility) is updated in the click handler below.
    local dot = cb:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", cb, "LEFT", 2, 0)
    cb:SetCheckedTexture(dot)
    table.insert(KART.CheckVisuals, dot)

    -- Checked texture only shows/hides by default; here it must always render (the dot represents
    -- "off" position too) — track color communicates on/off state.
    dot:Show()

    local function refreshVisual(self)
        local checked = self:GetChecked()
        dot:ClearAllPoints()
        if checked then
            dot:SetPoint("RIGHT", self, "RIGHT", -2, 0)
        else
            dot:SetPoint("LEFT", self, "LEFT", 2, 0)
        end
        local r = (KART_Settings and KART_Settings.accentR or 0) / 100
        local g = (KART_Settings and KART_Settings.accentG or 60) / 100
        local bl = (KART_Settings and KART_Settings.accentB or 100) / 100
        if checked then
            self:SetBackdropColor(KART.Theme.Darken(r, g, bl, 0.35))
        else
            self:SetBackdropColor(0, 0, 0, 0.5)
        end
    end

    cb:SetScript("OnClick", function(self)
        KART_Settings[settingKey] = self:GetChecked()
        refreshVisual(self)
        if callback then callback() end
    end)
    -- Initial state (e.g. when the panel is first built, before any user click) still needs the
    -- dot in the correct position — CheckButton's own SetChecked (called elsewhere when settings
    -- load) doesn't fire OnClick, so hook OnShow as a catch-all.
    cb:HookScript("OnShow", function(self) refreshVisual(self) end)

    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, then `/kart`, open the "Raidlead" tab.
Expected: the "Activate Raidlead Bar" control renders as a pill-shaped switch (not a square), the
dot sits left when off / right when on, and clicking it toggles both the visual and the actual
setting (verify by checking the Raidlead Bar actually shows/hides in-game, since its callback is
wired to `KART.UpdateRaidleadBarVisibility`).

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Redesign CreateSettingsCheckbox as a toggle switch"
```

---

### Task 5: Slim slider with round thumb and hover glow

**Files:**
- Modify: `Utils.lua:175-223` (existing `KART.CreateSettingsSlider` function)

**Interfaces:**
- Consumes: `KART.Theme.Lighten/Darken` (Task 1), `KART.ApplyRoundedMask` (Task 2)
- Produces: `KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name,
  tooltipText)` — same signature and return value (a `Slider` with `.title`/`.valueText`
  FontStrings) as before.

- [ ] **Step 1: Replace the function body**

Replace `Utils.lua:175-223` with:

```lua
function KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText)
    local s = CreateFrame("Slider", name, parent, "BackdropTemplate")
    s:SetSize(180, 4) -- thin track instead of the old 14px-tall bar
    s:SetPoint("TOPLEFT", 20, yOffset - 16) -- 16px Platz für das Label oben
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    s:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0, 0, 0, 0.5)
    s:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    KART.ApplyRoundedMask(s, 2) -- track is only 4px tall; skips rounding via the min-size guard, kept for future-proofing if track height changes

    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.title:SetText(labelText)
    table.insert(KART.DynamicLabels, s.title)

    s.valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)

    -- Soft glow behind the thumb, hidden by default, faded in on hover/drag via the same
    -- AddShowFade-style alpha animation used for window show transitions (see below).
    local glow = s:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(20, 20)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetAlpha(0)
    table.insert(KART.SliderThumbs, glow) -- colored alongside the thumb in KART.UpdateStyles

    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 12)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    s:SetThumbTexture(thumb)
    table.insert(KART.SliderThumbs, thumb)
    local thumbMask = s:CreateMaskTexture(nil, "OVERLAY")
    local maskOk = pcall(function()
        thumbMask:SetTexture("Interface\\Masks\\CircleMaskScalable", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        thumbMask:SetAllPoints(thumb)
        thumb:AddMaskTexture(thumbMask)
    end)
    if not maskOk then thumbMask:Hide() end

    local function positionGlow()
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", thumb, "CENTER")
    end

    s:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value)
        KART_Settings[settingKey] = val
        self.valueText:SetText(val)
        positionGlow()
        if KART.UpdateStyles then KART.UpdateStyles() end
    end)
    s:SetScript("OnEnter", function() glow:SetAlpha(0.35) end)
    s:SetScript("OnLeave", function() if not s.isDragging then glow:SetAlpha(0) end end)
    s:HookScript("OnMouseDown", function() s.isDragging = true; glow:SetAlpha(0.5) end)
    s:HookScript("OnMouseUp", function() s.isDragging = false; glow:SetAlpha(0) end)

    if tooltipText then
        s:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        s:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return s
end
```

Note: `glow` is deliberately added to `KART.SliderThumbs` so the existing loop in
`KART.UpdateStyles` (`Core.lua:421`, `for _, thumb in ipairs(KART.SliderThumbs) do
thumb:SetColorTexture(r, g, b, 1) end`) colors it with the accent color automatically — no change
needed in `Core.lua` for this task.

- [ ] **Step 2: Manual verification**

Run: `/reload`, then `/kart`, open the "Raidlead" tab, hover and drag the "Pull Timer" slider.
Expected: track is a thin bar, thumb is a small circle, a soft accent-colored glow appears behind
the thumb while hovering or dragging and disappears on release/leave. Dragging still updates the
value text and (per existing behavior) the Pull button's macro text.

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Redesign CreateSettingsSlider: thin track, round thumb, hover glow"
```

---

### Task 6: `CreateCard` panel primitive

**Files:**
- Modify: `Utils.lua` (add new function after `CreateSettingsSlider`, before
  `KART.UpdateMinimapButton`)

**Interfaces:**
- Consumes: `KART.Theme.CORNER_RADIUS_LG`, `KART.Theme.Darken` (Task 1), `KART.ApplyRoundedMask`
  (Task 2)
- Produces: `KART.CreateCard(parent, title)` → returns `card` (a `Frame` with `BackdropTemplate`).
  If `title` is non-nil, `card.titleText` is a FontString already registered in
  `KART.DynamicLabels`. Caller is responsible for sizing/positioning the returned frame and
  placing content inside it (mirrors how `KART.PromotePanel` etc. are used today — this is a
  container, not a layout manager).

- [ ] **Step 1: Add `KART.CreateCard`**

```lua
-- UI Factory: Card panel — a rounded, slightly recessed container used to visually group related
-- settings (e.g. all Raidlead Bar options) instead of leaving controls floating directly on the
-- tab background. Draws a second, 2px-larger, darker backdrop behind the card as a cheap "shadow"
-- (WoW has no real blur/drop-shadow primitive), then the card's own backdrop on top.
function KART.CreateCard(parent, title)
    local shadow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    shadow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    shadow:SetBackdropColor(0, 0, 0, 0.35)

    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", shadow, "TOPLEFT", -2, 2)
    card:SetPoint("BOTTOMRIGHT", shadow, "BOTTOMRIGHT", 2, -2)
    card.shadow = shadow
    -- Keep the shadow following the card's own points instead of the other way around: callers
    -- position/size `card` (the frame they get back), and the shadow tracks it automatically.
    card:HookScript("OnSizeChanged", function()
        shadow:ClearAllPoints()
        shadow:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        shadow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
    end)

    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    card:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(card, KART.Theme.CORNER_RADIUS_LG)
    KART.ApplyRoundedMask(shadow, KART.Theme.CORNER_RADIUS_LG)

    if title then
        card.titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.titleText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        card.titleText:SetText(title)
        table.insert(KART.DynamicLabels, card.titleText)
    end

    return card
end
```

- [ ] **Step 2: Manual verification**

Run: `/reload`, then in-game execute:
```
/run local c = KART.CreateCard(KART.SettingsPanel, "Test Card"); c:SetSize(200,80); c:SetPoint("CENTER")
```
Expected: opening `/kart` → Settings tab shows a rounded card with a faint shadow and the label
"Test Card" in the top-left, centered on the panel. (This is a throwaway manual check — no
permanent call site is added in this task.)

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "Add KART.CreateCard panel primitive"
```

---

### Task 7: Tab buttons with active-state accent bar

**Files:**
- Modify: `Utils.lua` (add new function near `CreateModernButton`)
- Modify: `MainFrame.lua:71-93` (sidebar tab button creation)
- Modify: `MainFrame.lua:6-18` (`KART.ShowTab`, to drive the new active-state visual)

**Interfaces:**
- Consumes: `KART.Theme.Lighten/Darken` (Task 1)
- Produces: `KART.CreateTabButton(parent, text)` → returns `btn` (a `Button`) with
  `btn:SetActive(isActive)` method that toggles the accent-bar + background highlight.
  `KART.ShowTab(tabIndex)` keeps its existing signature/behavior (panel show/hide) and gains a
  call to each tab button's `SetActive`.

- [ ] **Step 1: Add `KART.CreateTabButton` to `Utils.lua`**

Add directly after the closing `end` of `CreateModernButton` (Task 3's edit):

```lua
-- UI Factory: Sidebar tab button. Like CreateModernButton but adds a left-edge accent bar and a
-- lighter background when marked active via :SetActive(true), so the current tab reads clearly
-- against the rest of the sidebar instead of only differing by text color.
function KART.CreateTabButton(parent, text)
    local b = KART.CreateModernButton(parent, text)
    b:SetSize(130, 25)

    local accentBar = b:CreateTexture(nil, "OVERLAY")
    accentBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:Hide()
    table.insert(KART.SliderThumbs, accentBar) -- reuse the accent-coloring loop in KART.UpdateStyles

    function b:SetActive(isActive)
        accentBar:SetShown(isActive)
        if isActive then
            local r = (KART_Settings and KART_Settings.accentR or 0) / 100
            local g = (KART_Settings and KART_Settings.accentG or 60) / 100
            local bl = (KART_Settings and KART_Settings.accentB or 100) / 100
            b:SetBackdropColor(KART.Theme.Darken(r, g, bl, 0.6))
        else
            b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        end
    end
    b:SetActive(false)
    return b
end
```

- [ ] **Step 2: Wire it into `MainFrame.lua`'s sidebar**

Replace `MainFrame.lua:71-93`:

```lua
KART.BtnPromote = KART.CreateModernButton(mainFrame, L.TAB_PROMOTE)
KART.BtnPromote:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 5, -10)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.CreateModernButton(mainFrame, L.TAB_RAIDLEAD)
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.CreateModernButton(mainFrame, L.TAB_BUFFCHECK)
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnSettings = KART.CreateModernButton(mainFrame, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

KART.BtnLootCouncil = KART.CreateModernButton(mainFrame, L.TAB_LOOTCOUNCIL or "Loot Council")
KART.BtnLootCouncil:SetPoint("TOPLEFT", KART.BtnSettings, "BOTTOMLEFT", 0, -5)
KART.BtnLootCouncil:SetScript("OnClick", function() KART.ShowTab(5) end)

KART.BtnWoWUtils = KART.CreateModernButton(mainFrame, L.TAB_WOWUTILS or "WoWUtils")
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnLootCouncil, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(6) end)
```

with:

```lua
KART.BtnPromote = KART.CreateTabButton(mainFrame, L.TAB_PROMOTE)
KART.BtnPromote:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 5, -10)
KART.BtnPromote:SetScript("OnClick", function() KART.ShowTab(1) end)

KART.BtnRaidlead = KART.CreateTabButton(mainFrame, L.TAB_RAIDLEAD)
KART.BtnRaidlead:SetPoint("TOPLEFT", KART.BtnPromote, "BOTTOMLEFT", 0, -5)
KART.BtnRaidlead:SetScript("OnClick", function() KART.ShowTab(2) end)

KART.BtnBuffCheck = KART.CreateTabButton(mainFrame, L.TAB_BUFFCHECK)
KART.BtnBuffCheck:SetPoint("TOPLEFT", KART.BtnRaidlead, "BOTTOMLEFT", 0, -5)
KART.BtnBuffCheck:SetScript("OnClick", function() KART.ShowTab(3) end)

KART.BtnSettings = KART.CreateTabButton(mainFrame, L.TAB_SETTINGS)
KART.BtnSettings:SetPoint("TOPLEFT", KART.BtnBuffCheck, "BOTTOMLEFT", 0, -5)
KART.BtnSettings:SetScript("OnClick", function() KART.ShowTab(4) end)

KART.BtnLootCouncil = KART.CreateTabButton(mainFrame, L.TAB_LOOTCOUNCIL or "Loot Council")
KART.BtnLootCouncil:SetPoint("TOPLEFT", KART.BtnSettings, "BOTTOMLEFT", 0, -5)
KART.BtnLootCouncil:SetScript("OnClick", function() KART.ShowTab(5) end)

KART.BtnWoWUtils = KART.CreateTabButton(mainFrame, L.TAB_WOWUTILS or "WoWUtils")
KART.BtnWoWUtils:SetPoint("TOPLEFT", KART.BtnLootCouncil, "BOTTOMLEFT", 0, -5)
KART.BtnWoWUtils:SetScript("OnClick", function() KART.ShowTab(6) end)
```

- [ ] **Step 3: Drive `SetActive` from `KART.ShowTab`**

Replace `MainFrame.lua:6-18`:

```lua
-- 1. Tab-Wechsel Logik (wird in KART Tabelle gespeichert)
function KART.ShowTab(tabIndex)
    local panels = {
        KART.PromotePanel,
        KART.RaidleadPanel,
        KART.BuffCheckPanel,
        KART.SettingsPanel,
        KART.LootCouncilPanel,
        KART.WoWUtilsPanel,
    }
    for i, panel in ipairs(panels) do
        if panel then panel:SetShown(i == tabIndex) end
    end
end
```

with:

```lua
-- 1. Tab-Wechsel Logik (wird in KART Tabelle gespeichert)
function KART.ShowTab(tabIndex)
    local panels = {
        KART.PromotePanel,
        KART.RaidleadPanel,
        KART.BuffCheckPanel,
        KART.SettingsPanel,
        KART.LootCouncilPanel,
        KART.WoWUtilsPanel,
    }
    for i, panel in ipairs(panels) do
        if panel then panel:SetShown(i == tabIndex) end
    end

    -- Buttons are created further down in this file (after this function is defined), so guard
    -- against calling ShowTab before they exist (not expected in practice, but SetActive would
    -- error on a nil button otherwise).
    local buttons = {
        KART.BtnPromote,
        KART.BtnRaidlead,
        KART.BtnBuffCheck,
        KART.BtnSettings,
        KART.BtnLootCouncil,
        KART.BtnWoWUtils,
    }
    for i, btn in ipairs(buttons) do
        if btn then btn:SetActive(i == tabIndex) end
    end
end
```

- [ ] **Step 4: Manual verification**

Run: `/reload`, then `/kart`. Click through all six sidebar tabs.
Expected: the currently active tab shows a 3px accent-colored bar on its left edge and a
darker-accent-tinted background; clicking another tab moves the bar/highlight there and the
correct panel content still shows (Promote/Raidlead/BuffCheck/Settings/LootCouncil/WoWUtils).

- [ ] **Step 5: Commit**

```bash
git add Utils.lua MainFrame.lua
git commit -m "Add active-tab accent indicator via KART.CreateTabButton"
```

---

### Task 8: Group MainFrame settings controls into cards

**Files:**
- Modify: `MainFrame.lua:140-167` (Raidlead panel content)
- Modify: `MainFrame.lua:169-194` (BuffChecker panel content)

**Interfaces:**
- Consumes: `KART.CreateCard` (Task 6)

- [ ] **Step 1: Wrap the Raidlead panel controls in a card**

Replace `MainFrame.lua:140-167`:

```lua
-- 5. Raidlead Panel Inhalt (Hier binden wir die RaidleadBar ein!)
local rlTitle = KART.RaidleadPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rlTitle:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -20)
rlTitle:SetText(L.LABEL_RAIDLEAD_TOOLS)
table.insert(KART.DynamicLabels, rlTitle)

-- Checkbox zur Aktivierung
KART.CbActivate = KART.CreateSettingsCheckbox(KART.RaidleadPanel, "KART_RaidleadBarCheck", L.SET_RL_ACTIVATE, "showRaidleadBar", -50, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_ACTIVATE)

-- Checkbox zum Sperren
KART.CbLock = KART.CreateSettingsCheckbox(KART.RaidleadPanel, "KART_RaidleadBarLockCheck", L.SET_RL_LOCK, "lockRaidleadBar", -80, nil, L.DESC_RL_LOCK)

-- Checkbox für Auto-Hide
KART.CbAutoHide = KART.CreateSettingsCheckbox(KART.RaidleadPanel, "KART_RaidleadBarAutoHideCheck", L.SET_RL_AUTOHIDE, "autoHideRaidleadBar", -110, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_AUTOHIDE)

-- Pull-Timer Slider (Verknüpfung mit KART_PullBtn aus RaidleadBar.lua)
KART.PullSlider = KART.CreateSettingsSlider(KART.RaidleadPanel, L.SET_PULL_TIMER, 5, 30, "pullTimerDuration", -160, "KART_PullTimerSlider", L.DESC_PULL_TIMER)
KART.PullSlider:HookScript("OnValueChanged", function(self, value)
    if KART.PullBtn then -- Objekt aus RaidleadBar.lua
        if not InCombatLockdown() then
            KART.PullBtn:SetAttribute("macrotext", "/pull " .. floor(value))
        end
    end
end)
```

with:

```lua
-- 5. Raidlead Panel Inhalt (Hier binden wir die RaidleadBar ein!)
local rlTitle = KART.RaidleadPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rlTitle:SetPoint("TOPLEFT", KART.RaidleadPanel, "TOPLEFT", 20, -20)
rlTitle:SetText(L.LABEL_RAIDLEAD_TOOLS)
table.insert(KART.DynamicLabels, rlTitle)

-- Card groups all Raidlead Bar settings into one visually distinct panel instead of leaving
-- checkboxes/slider floating directly on the tab background.
local rlCard = KART.CreateCard(KART.RaidleadPanel)
rlCard:SetPoint("TOPLEFT", rlTitle, "BOTTOMLEFT", 0, -10)
rlCard:SetSize(290, 180)

-- Checkbox zur Aktivierung
KART.CbActivate = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarCheck", L.SET_RL_ACTIVATE, "showRaidleadBar", -20, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_ACTIVATE)

-- Checkbox zum Sperren
KART.CbLock = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarLockCheck", L.SET_RL_LOCK, "lockRaidleadBar", -50, nil, L.DESC_RL_LOCK)

-- Checkbox für Auto-Hide
KART.CbAutoHide = KART.CreateSettingsCheckbox(rlCard, "KART_RaidleadBarAutoHideCheck", L.SET_RL_AUTOHIDE, "autoHideRaidleadBar", -80, function()
    KART.UpdateRaidleadBarVisibility() -- Funktion aus RaidleadBar.lua
end, L.DESC_RL_AUTOHIDE)

-- Pull-Timer Slider (Verknüpfung mit KART_PullBtn aus RaidleadBar.lua)
KART.PullSlider = KART.CreateSettingsSlider(rlCard, L.SET_PULL_TIMER, 5, 30, "pullTimerDuration", -130, "KART_PullTimerSlider", L.DESC_PULL_TIMER)
KART.PullSlider:HookScript("OnValueChanged", function(self, value)
    if KART.PullBtn then -- Objekt aus RaidleadBar.lua
        if not InCombatLockdown() then
            KART.PullBtn:SetAttribute("macrotext", "/pull " .. floor(value))
        end
    end
end)
```

Note: checkbox/slider `yOffset` values are now relative to `rlCard` (top-left of the card) rather
than `KART.RaidleadPanel`, and are shifted up (e.g. `-50` → `-20`) to account for the card's own
~24px top padding before content starts, and the card height (180) is sized to fit the lowest
control (slider at `-130` plus its ~30px footprint plus bottom padding).

- [ ] **Step 2: Wrap the BuffChecker panel controls in a card**

Replace `MainFrame.lua:169-194`:

```lua
-- 6. BuffChecker Panel Inhalt
local bcTitle = KART.BuffCheckPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bcTitle:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -20)
bcTitle:SetText(L.LABEL_BUFFCHECK_SETTINGS)
table.insert(KART.DynamicLabels, bcTitle)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
KART.CbBcModuleEnabled = KART.CreateSettingsCheckbox(KART.BuffCheckPanel, "KART_BcModuleEnabled", L.SET_BC_MODULE_ENABLED, "bcModuleEnabled", -50, nil, L.DESC_BC_MODULE_ENABLED)

KART.CbShowBuffCheck = KART.CreateSettingsCheckbox(KART.BuffCheckPanel, "KART_ShowBuffCheck", L.SET_BC_READYCHECK, "showBuffCheck", -80, nil, L.DESC_BC_READYCHECK)

KART.BtnBuffPreview = KART.CreateModernButton(KART.BuffCheckPanel, L.BTN_BUFF_PREVIEW)
KART.BtnBuffPreview:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -120)
KART.BtnBuffPreview:SetScript("OnClick", function()
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
        KART.UpdateBuffCheck(true)
    end
end)

KART.SldBuffCheckAlpha = KART.CreateSettingsSlider(KART.BuffCheckPanel, L.SET_BC_ALPHA, 0, 100, "buffCheckAlpha", -175, "KART_BuffCheckAlphaSlider", L.DESC_BC_ALPHA)
KART.SldCombatDelay = KART.CreateSettingsSlider(KART.BuffCheckPanel, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -220, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY)
KART.CbGrayOffline = KART.CreateSettingsCheckbox(KART.BuffCheckPanel, "KART_GrayOffline", L.SET_GRAY_OFFLINE, "grayOffline", -265, nil, L.DESC_GRAY_OFFLINE)
```

with:

```lua
-- 6. BuffChecker Panel Inhalt
local bcTitle = KART.BuffCheckPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bcTitle:SetPoint("TOPLEFT", KART.BuffCheckPanel, "TOPLEFT", 20, -20)
bcTitle:SetText(L.LABEL_BUFFCHECK_SETTINGS)
table.insert(KART.DynamicLabels, bcTitle)

local bcCard = KART.CreateCard(KART.BuffCheckPanel)
bcCard:SetPoint("TOPLEFT", bcTitle, "BOTTOMLEFT", 0, -10)
bcCard:SetSize(290, 290)

-- Master switch: fully disables the Buff-Checker window/UI (saves CPU). The KART Sync responder
-- (oil/ilvl/gear) keeps answering regardless, so the raid leader still sees accurate data for you.
KART.CbBcModuleEnabled = KART.CreateSettingsCheckbox(bcCard, "KART_BcModuleEnabled", L.SET_BC_MODULE_ENABLED, "bcModuleEnabled", -20, nil, L.DESC_BC_MODULE_ENABLED)

KART.CbShowBuffCheck = KART.CreateSettingsCheckbox(bcCard, "KART_ShowBuffCheck", L.SET_BC_READYCHECK, "showBuffCheck", -50, nil, L.DESC_BC_READYCHECK)

KART.BtnBuffPreview = KART.CreateModernButton(bcCard, L.BTN_BUFF_PREVIEW)
KART.BtnBuffPreview:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 20, -90)
KART.BtnBuffPreview:SetScript("OnClick", function()
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
        KART.UpdateBuffCheck(true)
    end
end)

KART.SldBuffCheckAlpha = KART.CreateSettingsSlider(bcCard, L.SET_BC_ALPHA, 0, 100, "buffCheckAlpha", -145, "KART_BuffCheckAlphaSlider", L.DESC_BC_ALPHA)
KART.SldCombatDelay = KART.CreateSettingsSlider(bcCard, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -190, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY)
KART.CbGrayOffline = KART.CreateSettingsCheckbox(bcCard, "KART_GrayOffline", L.SET_GRAY_OFFLINE, "grayOffline", -235, nil, L.DESC_GRAY_OFFLINE)
```

- [ ] **Step 3: Manual verification**

Run: `/reload`, then `/kart`. Open the "Raidlead" tab: expect the three toggle switches and pull
timer slider to sit inside one rounded card with a visible shadow, no controls clipped or
overlapping. Open the "BuffCheck" tab: same check, plus click "Preview Buff Check" to confirm the
button (now inside the card) still opens the preview window.

- [ ] **Step 4: Commit**

```bash
git add MainFrame.lua
git commit -m "Group Raidlead and BuffCheck panel controls into cards"
```

---

## Follow-up phases (not part of this plan)

Per the design spec's rollout order, the remaining windows (`BuffChecker.lua`'s own frame/rows,
`LootCouncil.lua`'s 41 ad-hoc styling call sites across the council panel/vote cards/tabs/raid-
wide box, `LootHistory.lua`, `RaidleadBar.lua`, `Invite.lua`, `Core.lua`'s ready-check popup, and
`Droptimizer.lua`) each need their own plan written after reading those files in full — several
are large (`LootCouncil.lua` is 3526 lines) and deserve accurate, non-speculative task steps
rather than placeholder code. Write each as a separate
`docs/superpowers/plans/YYYY-MM-DD-ui-modernization-phase-N-<file>.md` once this foundation has
landed and been visually verified in-game.
