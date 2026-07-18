# PNG-Artwork Main Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the KART main menu as an EllesmereUI-style window: one baked PNG carries the entire visual (frame, sidebar, logo, title, close X); interactive elements become invisible hit areas; free resizing is replaced by a scale slider.

**Architecture:** `mainFrame` is sized to the full PNG footprint and shows a single BACKGROUND texture. An inner `clickArea` frame covers the opaque artwork region; every widget anchors to it. All geometry derives from measured pixel ratios of `kart-bg-dark.png` (see constants below). Settings lose the background-color picker and title-size slider, gain a UI-scale slider.

**Tech Stack:** WoW Retail addon, Lua 5.1, WoW widget API. No test framework exists — each task ends with a static grep-verification; final in-game verification checklist at the end.

**Spec:** `docs/superpowers/specs/2026-07-18-png-artwork-mainframe-design.md`

## Global Constraints

- Code comments in English (project CLAUDE.md).
- Changelog entries: one line, max two, bold lead + short clause, no causes (project CLAUDE.md).
- Update English docs first, then mirror into `-de` files in the same task.
- Surgical changes only: do not touch BuffChecker, LootCouncil, LootHistory, RaidleadBar windows.
- `bgR/bgG/bgB` and `titleFontSize` MUST stay in `KART.Defaults` — other windows read them in `KART.UpdateStyles()`.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Measured geometry constants (single source of truth)

PNG `media/backgrounds/kart-bg-dark.png` is 1500x1154. Opaque art box: x 105–1396, y 104–1050 (1292x947). Divider at image x=428 (art x=323). X-glyph center at image (1353, 143) = art (1248, 39).

Chosen art width 640 → scale factor s = 640/1292 ≈ 0.4954:

| Constant | Value | Derivation |
|---|---|---|
| mainFrame size | 743 x 572 | 1500·s x 1154·s |
| clickArea insets | TOPLEFT (52, -52), BOTTOMRIGHT (-51, 51) | margins 105/104/103/103 · s → art area 640x469 |
| Sidebar width | 160 | 323·s |
| Close button center | (-21, -20) from clickArea TOPRIGHT | art (1248, 39)·s = (618, 19.5); 640-618=22 |
| Tab column x / first tab y | 10 / -60 | below baked logo+underline zone (underline at art y≈106 → 52.5 scaled) |
| Content scroll area | TOPLEFT (166, -12), BOTTOMRIGHT (-25, 20) of clickArea | right of 160-divider + padding |

---

### Task 1: MainFrame artwork rebuild

**Files:**
- Modify: `MainFrame.lua` (sections 2, 3, 4 anchor lines, 8; delete header/inset/resize/close-text code)
- Modify: `Core.lua:184-187` (login version text) and `Core.lua:391-410` (UpdateStyles main-frame block)

**Interfaces:**
- Consumes: `KART.RegisterStrataFrame`, `KART.AddShowFade`, `KART.CreateTabButton` (existing signatures).
- Produces: `KART.MainFrame` (unchanged global), `KART.MainFrame.clickArea` (new frame, used by Task 1 internally), `KART.MainFrame.closeBtn` (Button without `.text`), `KART.MainFrame.versionText` (FontString; Core.lua login block sets its text). `mainFrame.header`, `mainFrame.title`, `mainFrame.logo`, `mainFrame.resizeBtn`, `mainFrame.gradientBg`, local `mainInset` no longer exist — nothing outside `MainFrame.lua`/`Core.lua` references them (verified by grep during planning).

- [ ] **Step 1: Replace MainFrame.lua section 2 (lines 35–80: frame creation through `KART.MainFrame = mainFrame`) with:**

```lua
-- 2. Main window (PNG artwork, EllesmereUI-style)
-- All geometry derives from the measured layout of kart-bg-dark.png:
-- image 1500x1154, opaque art box x 105-1396 / y 104-1050 (1292x947),
-- sidebar divider at art x 323, close-X center at art (1248, 39).
-- Art width is fixed at 640 (scale factor 640/1292); the window is not
-- freely resizable because the baked artwork would distort and the
-- invisible hit areas (close X, sidebar) would drift off their graphics.
-- Users scale the whole window via the Settings "Window Scale" slider.
local mainFrame = CreateFrame("Frame", "KART_MainFrame", UIParent)
mainFrame:SetSize(743, 572) -- full PNG footprint incl. transparent shadow margin
mainFrame:SetPoint("CENTER", UIParent, "CENTER")
mainFrame:SetMovable(true)

mainFrame.bg = mainFrame:CreateTexture(nil, "BACKGROUND")
mainFrame.bg:SetTexture("Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-bg-dark.png")
mainFrame.bg:SetAllPoints()

KART.RegisterStrataFrame(mainFrame)
mainFrame:Hide()
KART.AddShowFade(mainFrame)

-- Allows closing the whole KART window with the ESC key
table.insert(UISpecialFrames, mainFrame:GetName())
KART.MainFrame = mainFrame

-- clickArea covers the opaque artwork region (shadow margin excluded).
-- Every interactive child anchors to it; it also blocks clicks from
-- falling through the window and handles whole-surface dragging (the
-- old header bar is baked into the PNG now).
local clickArea = CreateFrame("Frame", nil, mainFrame)
clickArea:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 52, -52)
clickArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -51, 51)
clickArea:EnableMouse(true)
clickArea:RegisterForDrag("LeftButton")
clickArea:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
clickArea:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)
mainFrame.clickArea = clickArea

-- Version string, bottom-left of the baked sidebar. Core.lua overwrites
-- the text once KART.Version is known (ADDON_LOADED).
mainFrame.versionText = clickArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainFrame.versionText:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 14, 10)
mainFrame.versionText:SetText("v" .. (KART.Version or ""))
```

This removes: `BackdropTemplate` on the frame, `SetBackdrop`/`SetBackdropBorderColor`, `SetResizable`/`SetResizeBounds`, `gradientBg`, the whole header frame block (drag scripts, logo texture, title FontString).

- [ ] **Step 2: Replace section 3's `mainInset` block (old lines 82–90) — delete `mainInset` creation and `sidebarBG`; re-anchor the first tab.**

Old:
```lua
local mainInset = CreateFrame("Frame", nil, mainFrame)
...
mainInset.sidebarBG:SetColorTexture(0.05, 0.05, 0.05, 0.8)
```
New: nothing (deleted). Then change the first tab's anchor from
```lua
KART.BtnPromote:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 5, -10)
```
to
```lua
-- Tabs start below the baked logo/title/underline zone of the artwork.
KART.BtnPromote:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 10, -60)
```
The remaining five tab buttons chain off `BtnPromote` via `BOTTOMLEFT` anchors — leave them unchanged (including the "Settings must stay last" comment block).

- [ ] **Step 3: Delete the divider texture block (old lines 119–124, `mainInset.divider`) — the divider is baked into the PNG.**

- [ ] **Step 4: Re-anchor the content ScrollFrame (old lines 127–129) to clickArea and widen the scroll child:**

```lua
-- 4. Content area (ScrollFrame), right of the baked sidebar divider (160px)
local scrollFrame = CreateFrame("ScrollFrame", "KART_ContentScrollFrame", clickArea, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 166, -12)
scrollFrame:SetPoint("BOTTOMRIGHT", clickArea, "BOTTOMRIGHT", -25, 20)
```
And change `scrollChild:SetSize(310, 750)` to `scrollChild:SetSize(430, 750)` (content column grew from ~310 to ~449 px; keep headroom comment above it unchanged).

- [ ] **Step 5: Delete section 8's resize handle block (old lines 396–403, `mainFrame.resizeBtn`) entirely.**

- [ ] **Step 6: Replace the close button block (old lines 405–416) with an invisible hit area over the painted X:**

```lua
-- 8. Close button: invisible hit area over the X baked into the artwork.
-- HIGHLIGHT-layer texture shows automatically on hover, no scripts needed.
local closeBtn = CreateFrame("Button", nil, clickArea)
closeBtn:SetSize(30, 30)
closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -21, -20)
local closeHover = closeBtn:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.08)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn
```

- [ ] **Step 7: Core.lua login block — replace the title-version assignment (lines 184–187):**

Old:
```lua
        -- Korrekte Version in Titelleiste setzen (KART.Version ist erst hier verfügbar)
        if KART.MainFrame and KART.MainFrame.title then
            KART.MainFrame.title:SetText((KART.L.ADDON_TITLE or "Keine Ahnung Raid Tools") .. " v" .. KART.Version)
        end
```
New:
```lua
        -- Set the real version (KART.Version only becomes available here)
        if KART.MainFrame and KART.MainFrame.versionText then
            KART.MainFrame.versionText:SetText("v" .. KART.Version)
        end
```

- [ ] **Step 8: Core.lua UpdateStyles — replace the main-frame styling block (lines 401–410):**

Old:
```lua
    KART.MainFrame:SetBackdropColor(br, bg, bb, KART_Settings.bgAlpha / 100)
    KART.SetGradientOverlayColor(KART.MainFrame.gradientBg, br, bg, bb, KART_Settings.bgAlpha / 100)
    if KART.MainFrame.title then
        KART.MainFrame.title:SetFont(fontPath, titleSize, "OUTLINE")
        KART.MainFrame.title:SetTextColor(r, g, b)
    end

    if KART.MainFrame.closeBtn then
        KART.MainFrame.closeBtn.text:SetFont(fontPath, 14, "OUTLINE")
    end
```
New:
```lua
    -- The main window is a baked PNG artwork: no backdrop/gradient to tint.
    -- bgAlpha now controls whole-window opacity; floor of 20 so the window
    -- can never become fully invisible while still blocking mouse input.
    KART.MainFrame:SetAlpha(math.max(20, KART_Settings.bgAlpha or 85) / 100)
```
(`br, bg, bb` and `titleSize` stay — Loot History and BuffChecker below still use them.)

- [ ] **Step 9: Static verification**

Run: `grep -n "mainInset\|resizeBtn\|mainFrame.header\|mainFrame.title\|mainFrame.logo\|gradientBg" MainFrame.lua`
Expected: no matches.
Run: `grep -n "MainFrame.title\|MainFrame.closeBtn.text" Core.lua`
Expected: no matches.
Read the full new MainFrame.lua top section once for syntax sanity (no Lua toolchain available).

- [ ] **Step 10: Commit**

```bash
git add MainFrame.lua Core.lua
git commit -m "feat: rebuild main window on baked PNG artwork (EUI-style)"
```

---

### Task 2: Flat sidebar tab buttons

**Files:**
- Modify: `Utils.lua:304-369` (`KART.CreateTabButton`)

**Interfaces:**
- Consumes: `KART.Theme.AccentColor()`, `KART.Theme.Darken()`, `KART.ButtonTexts`, `KART.SliderThumbs`, `KART.TabButtons` (all existing).
- Produces: `KART.CreateTabButton(parent, text)` returning a Button with `:SetActive(bool)` and `:RefreshActiveColor()` — same public surface as before (MainFrame.lua and `KART.UpdateStyles()` rely on these names). No longer built on `CreateModernButton`.

- [ ] **Step 1: Replace the whole `KART.CreateTabButton` function (including its leading comment block) with:**

```lua
-- UI Factory: Sidebar tab button, flat style for the PNG-artwork sidebar.
-- Transparent at rest so the baked artwork shows through; subtle white tint
-- on hover; active tab gets a translucent accent fill, a left accent bar and
-- full-white text. Standalone (not built on CreateModernButton) because that
-- factory's opaque backdrop and border would cover the artwork.
function KART.CreateTabButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(140, 25)
    b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    b:SetBackdropColor(0, 0, 0, 0)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetText(text)
    table.insert(KART.ButtonTexts, b.text)

    local accentBar = b:CreateTexture(nil, "OVERLAY")
    accentBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:Hide()
    table.insert(KART.SliderThumbs, accentBar) -- reuse the accent-coloring loop in KART.UpdateStyles

    local isActive = false

    -- Translucent so the artwork stays visible beneath the active fill.
    local function activeColor()
        local r, g, bl = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.45)
        return dr, dg, db, 0.35
    end

    local function restingColor(self)
        if isActive then
            self:SetBackdropColor(activeColor())
        else
            self:SetBackdropColor(0, 0, 0, 0)
        end
        b.text:SetTextColor(isActive and 1 or 0.75, isActive and 1 or 0.75, isActive and 1 or 0.75)
    end

    b:SetScript("OnEnter", function(self)
        if not isActive then self:SetBackdropColor(1, 1, 1, 0.06) end
        b.text:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        restingColor(self)
    end)

    function b:SetActive(active)
        isActive = active
        accentBar:SetShown(active)
        b:RefreshActiveColor()
    end

    -- Re-applies the current active/inactive color using the latest accent
    -- color; called from KART.UpdateStyles() when the accent changes.
    function b:RefreshActiveColor()
        if not b:IsMouseOver() then
            restingColor(b)
        end
    end

    table.insert(KART.TabButtons, b)
    b:SetActive(false)
    return b
end
```

- [ ] **Step 2: Static verification**

Run: `grep -n "CreateTabButton" MainFrame.lua Utils.lua`
Expected: 6 call sites in MainFrame.lua unchanged; one definition in Utils.lua.
Run: `grep -rn "CreateTabButton" --include=*.lua | grep -v "MainFrame\|Utils"`
Expected: no other consumers.

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "feat: flat sidebar tab style for artwork window"
```

---

### Task 3: Settings — remove bg-color/title-size, add Window Scale

**Files:**
- Modify: `Utils.lua:15-65` (`KART.Defaults`: add `uiScale`)
- Modify: `MainFrame.lua` section 7 (settings panel widgets)
- Modify: `Core.lua` (settingsMap lines 123/126 area; `UpdateStyles` scale + preview line 453)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Consumes: `KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText)` (existing).
- Produces: `KART.SldUiScale` (Slider, settingKey `"uiScale"`), `KART_Settings.uiScale` (number 50–150, default 100). Removes `KART.SldTitleSize`, `KART.BtnBgColor`, `KART.BgColorPreview` globals on the KART table.

- [ ] **Step 1: Utils.lua Defaults — add below `bgAlpha = 85,`:**

```lua
    uiScale = 100, -- whole-window scale in percent (PNG-artwork window is not freely resizable)
```
Do NOT remove `titleFontSize` or `bgR/bgG/bgB` — other windows read them in UpdateStyles.

- [ ] **Step 2: MainFrame.lua settings panel — remove the `SldTitleSize` line and re-stack the font sliders:**

Old:
```lua
KART.SldTitleSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_TITLE, 8, 20, "titleFontSize", -110, "KART_TitleSizeSlider", L.DESC_TITLE_SIZE)
KART.SldMenuSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -150, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -190, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)
```
New:
```lua
KART.SldMenuSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -110, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(KART.SettingsPanel, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -150, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)
KART.SldUiScale = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_UI_SCALE, 50, 150, "uiScale", -190, "KART_UiScaleSlider", L.DESC_UI_SCALE)
```

- [ ] **Step 3: MainFrame.lua — raise the BG alpha slider floor (full invisibility would leave an invisible click-blocking window):**

Old: `KART.SldBgAlpha = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_BG_ALPHA, 0, 100, "bgAlpha", -300, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)`
New: `KART.SldBgAlpha = KART.CreateSettingsSlider(KART.SettingsPanel, L.SET_BG_ALPHA, 20, 100, "bgAlpha", -300, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)`

- [ ] **Step 4: MainFrame.lua — delete the `BtnBgColor` block and its `BgColorPreview` block (old lines 375–386). `BtnReset` anchors to `BtnAccentColor`, so it is unaffected.**

- [ ] **Step 5: Core.lua settingsMap — remove the `SldTitleSize` line, add `SldUiScale`:**

Old: `if KART.SldTitleSize then settingsMap[KART.SldTitleSize] = "titleFontSize" end`
New: `if KART.SldUiScale then settingsMap[KART.SldUiScale] = "uiScale" end`

- [ ] **Step 6: Core.lua UpdateStyles — apply the scale next to the SetAlpha line from Task 1, and drop the bg preview:**

Add directly under the `SetAlpha` line:
```lua
    KART.MainFrame:SetScale((KART_Settings.uiScale or 100) / 100)
```
Delete: `if KART.BgColorPreview then KART.BgColorPreview:SetColorTexture(br, bg, bb, 1) end`

- [ ] **Step 7: Locales — enUS.lua first, then mirror deDE.lua:**

Remove from both: `LABEL_FONT_SIZE_TITLE`, `DESC_TITLE_SIZE`, `BTN_BG_COLOR`, `DESC_BG_COLOR`.
Add to enUS:
```lua
    SET_UI_SCALE = "Window Scale",
    DESC_UI_SCALE = "Scales the whole main window (in percent). Replaces free resizing, which the artwork background does not support.",
```
Update in enUS: `DESC_BG_ALPHA = "Controls the transparency of the whole main window.",`
Add to deDE:
```lua
    SET_UI_SCALE = "Fenster-Skalierung",
    DESC_UI_SCALE = "Skaliert das gesamte Hauptfenster (in Prozent). Ersetzt das freie Ändern der Fenstergröße, das der Artwork-Hintergrund nicht unterstützt.",
```
Update in deDE: `DESC_BG_ALPHA = "Steuert die Transparenz des gesamten Hauptfensters.",`

- [ ] **Step 8: Static verification**

Run: `grep -rn "SldTitleSize\|BtnBgColor\|BgColorPreview\|LABEL_FONT_SIZE_TITLE\|DESC_TITLE_SIZE\|BTN_BG_COLOR\|DESC_BG_COLOR" --include=*.lua`
Expected: no matches.
Run: `grep -rn "uiScale\|SET_UI_SCALE" --include=*.lua`
Expected: Utils.lua (default), MainFrame.lua (slider), Core.lua (settingsMap + UpdateStyles), both locale files.

- [ ] **Step 9: Commit**

```bash
git add Utils.lua MainFrame.lua Core.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: window scale slider; drop bg-color and title-size settings"
```

---

### Task 4: Docs

**Files:**
- Modify: `CHANGELOG.md`, `CHANGELOG-de.md` (English first, then mirror)
- Check: `README.md`, `README-de.md` for mentions of resizing/window customization; update only if present.

- [ ] **Step 1: Add an Unreleased section to CHANGELOG.md above `## [1.19.0]`:**

```markdown
## [Unreleased]
### Changed
- **Main window redesigned with a full artwork background** — sidebar, title and close button are part of the new look.
- **Free window resizing replaced by a "Window Scale" slider in Settings.**

### Removed
- **Background color and title font size settings.**
```

- [ ] **Step 2: Mirror into CHANGELOG-de.md:**

```markdown
## [Unreleased]
### Geändert
- **Hauptfenster mit neuem Artwork-Hintergrund gestaltet** — Sidebar, Titel und Schließen-Button sind Teil des neuen Looks.
- **Freies Fenster-Resizing ersetzt durch einen „Fenster-Skalierung"-Regler in den Einstellungen.**

### Entfernt
- **Einstellungen für Hintergrundfarbe und Titel-Schriftgröße.**
```

- [ ] **Step 3: `grep -in "resiz\|background color\|hintergrundfarbe" README.md README-de.md` — update matching feature descriptions if any; otherwise skip.**

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md README.md README-de.md
git commit -m "docs: changelog for artwork main window"
```

---

## Final in-game verification (user, after Task 4)

`/reload`, then:

1. Open window (minimap icon): artwork renders, no black backdrop behind it, shadow margin transparent.
2. Tabs sit on the baked sidebar, divider aligns with the artwork line; active tab shows accent bar + translucent fill.
3. Click the painted X → window closes. ESC → window closes. Drag anywhere on the window body → moves.
4. Settings: Window Scale slider resizes the whole window crisply; BG opacity slider fades the whole window (floor 20 %); no bg-color button, no title-size slider.
5. Version string bottom-left of sidebar shows current version.
6. Every tab's content renders inside the content column (no overlap with sidebar art); scroll works.
7. BuffChecker and Loot Council windows still look as before (unchanged).
8. Accent color change recolors tabs/sliders, including the active tab fill.

Any failure: report exact symptom back; anchors are all derived from the constants table above — fix there, not by eyeballing.
