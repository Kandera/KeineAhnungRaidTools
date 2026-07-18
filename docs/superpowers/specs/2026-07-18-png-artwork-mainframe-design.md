# PNG-Artwork Main Window (EllesmereUI-style) — Design

Date: 2026-07-18
Status: approved (design discussion in session; all decisions confirmed by Max)

## Goal

Restyle the KART main menu window to match the EllesmereUI approach: the entire
window visual (frame, sidebar column, divider, logo, title, close "X") is baked
into one PNG (`media/backgrounds/kart-bg-dark.png`), rendered as a single
texture. Interactive elements become invisible hit areas positioned over the
baked-in graphics. Layout stays: tabs left, content right, close top-right.

Reference implementation: `EllesmereUI.lua` lines ~6406–6549 in
https://github.com/EllesmereGaming/EllesmereUI (bgFrame texture + fixed-size
clickArea + invisible close button over the painted X).

## Measured PNG geometry (source of truth for anchors)

File: `media/backgrounds/kart-bg-dark.png`, 1500 x 1154 px, transparent
drop-shadow margin around the window artwork. Measured via alpha/brightness
scan (not estimated):

| Feature | Pixels (full image) | Art-relative ratio |
|---|---|---|
| Opaque art bounding box | x 105–1396, y 104–1050 (1292 x 947) | aspect 1.3643 |
| Shadow margin | ~104 px on all four sides | 0.0805 of art width |
| Sidebar divider | x = 428 | 0.250 of art width |
| Close "X" glyph center | (1353, 143), glyph ~12 x 12 | x 0.9663, y 0.0417 |
| Sidebar header underline (below baked logo/title) | y ≈ 210 | 0.112 of art height |

All runtime anchors derive from these ratios so the art and hit areas stay
aligned at any scale.

## Decisions (confirmed)

1. **Fixed size + scale slider** (EUI pattern). Free resizing and the resize
   grabber are removed; a new "UI Scale" slider in Settings scales the whole
   window via `SetScale`. Rationale: baked artwork distorts under free resize
   and the X hit area would drift.
2. **Redundant settings removed**: background color picker (+ preview swatch)
   and title font size slider. The BG alpha slider stays but now controls
   whole-window opacity (`SetAlpha` on the main frame). Accent color, frame
   strata, menu/content font settings stay.
3. **Version number** moves to a small FontString at the bottom-left of the
   sidebar (title FontString in the header is removed; the PNG carries the
   title).

## Frame architecture (MainFrame.lua)

- `mainFrame`: sized to the **full PNG ratio** (1500:1154), default art width
  640 → frame ≈ 743 x 572. Holds the single BACKGROUND texture
  (`Interface\AddOns\KeineAhnungRaidTools\media\backgrounds\kart-bg-dark.png`,
  `SetAllPoints`). No backdrop, no gradient overlay. Mouse-transparent except
  via clickArea.
- `clickArea`: child frame covering the opaque art region (offsets from the
  measured margin ratios), centered. All interactive children anchor to it.
  Handles window dragging (whole-surface drag; the old header-only drag and
  the header bar itself are removed).
- **Close button**: invisible `Button` (~30 x 30 hit area) centered on the
  painted X (ratios above). Hover feedback: subtle highlight texture over the
  region. Click hides the frame. ESC-close (`UISpecialFrames`) and the
  show-fade stay unchanged.
- **Removed from the current implementation**: `SetBackdrop` calls, gradient
  overlay, header frame, logo texture, title FontString, sidebar color
  texture, divider texture, resize button, text-based "×" button.

## Sidebar / tabs

- Tab buttons keep their factory (`KART.CreateTabButton`) and click wiring but
  are restyled flat: transparent resting background, subtle white hover tint,
  active = accent bar + accent-tinted text. They sit on the baked sidebar
  column, starting below the baked logo/underline zone (~0.13 of art height).
- Tab column width follows the divider ratio (0.25 of art width) instead of
  the old fixed 140 px.
- Version FontString bottom-left in the sidebar (small, muted color).
- Content `ScrollFrame` anchors right of the divider ratio; scroll logic,
  panels, and panel contents unchanged.

## Settings panel changes

- Remove: `BtnBgColor` + `BgColorPreview`, `SldTitleSize`.
- Retarget: `SldBgAlpha` → whole-window opacity.
- Add: `SldUiScale` (50–150 %, default 100), new saved variable `uiScale` in
  `KART.Defaults`, applied via `mainFrame:SetScale()` on change and on login.
- Locales: add/remove the corresponding strings in `enUS.lua` and `deDE.lua`;
  remove now-unused ones.

## Out of scope

BuffChecker window, LootCouncil windows, RaidleadBar, Droptimizer — they keep
the current gradient style. Only the main menu window changes.

## Risks / notes

- Tab column must visually match the baked divider at runtime; mitigated by
  deriving every anchor from measured ratios rather than fixed pixels.
- `media/backgrounds/kart-bg-dark.png` is currently untracked; it ships with
  the addon and must be added to git and referenced with the full
  `Interface\AddOns\KeineAhnungRaidTools\media\...` path.
- Old saved variables (`bgR/bgG/bgB`, `titleFontSize`) become inert; leave
  them in saved data (harmless) but drop them from `KART.Defaults` and the UI.
- Docs: CHANGELOG.md / CHANGELOG-de.md one-liner, README.md / README-de.md
  screenshot/feature text if it mentions resizing.
