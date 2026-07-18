# Layout Pass: Bigger Window, Cards Everywhere, De-Gold Text — Design

Date: 2026-07-18
Status: approved (follow-up to 2026-07-18-png-artwork-mainframe-design.md, after first in-game test)

## Goal

Three pieces of user feedback on the artwork window:
1. Default window too small, too much scrolling → +25% default size.
2. The dark card boxes (KART.CreateCard) look great → every tab groups its
   controls into cards, with a re-layout that uses the wider content column.
3. WoW-gold label text on the content side clashes with the white sidebar →
   labels/titles become white; deliberately colored text stays.

## 1. Geometry (art width 640 → 800)

Same measured PNG ratios as the artwork spec; scale factor s = 800/1292:

| Constant | Old (640) | New (800) |
|---|---|---|
| mainFrame | 743 x 572 | 929 x 715 |
| clickArea insets | (52,-52)/(-51,51) | (65,-64)/(-64,64) → art 800 x 587 |
| Sidebar divider | 160 | 200 |
| Tab buttons | 140x25 at (10,-60) | 176x28 at (12,-75) |
| Version text | (14,10) | (18,12) |
| Scroll area | (166,-12)/(-25,20) | (208,-14)/(-30,24) |
| scrollChild | 430x750 | 540x750 |
| Close button | 30x30 at (-21,-20) | 36x36 at (-27,-24) |

Content column: 540. Full-width card 500 at x=20; half card 242 at x=20 and
x=278 (16 gap). Widgets inside cards keep the factory default x=20; second
column inside a card sits at x=260 (via ClearAllPoints + SetPoint after
creation, same pattern SldFrameStrata already uses).

## 2. Cards per tab (mixed grid)

- **Automation:** Card "auto" (500) wraps promote label+editbox, invite
  label+editbox, and the two toggles side by side. AutoLog card (500)
  goes two-column: raid difficulties left; M+/min-key/dungeons/delves right.
- **Raidlead:** existing card widened to 500, content unchanged.
- **BuffCheck:** card 500, two-column (toggles+preview left, sliders right).
- **Settings:** half card "Interface" (minimap, window scale, opacity,
  window layer) beside half card "Text" (menu/content size, font, language);
  full card below (accent color + preview, reset, Droptimizer sync status —
  DT.BuildSyncStatus keeps anchoring to KART.BtnReset and moves with it).
- **Loot Council:** personal toggles (module, autopass, Droptimizer slot,
  compact layout, nicknames) wrapped in a card exposed as
  `KART.LC.SettingsCard`; Droptimizer parents its toggle to that card.
  The amber raid-wide box keeps its warning styling (semantic) but widens
  to 500 / CONTENT_WIDTH 460 and gets rounded corners. Test buttons 242
  side by side, history button 500.
- **WoWUtils:** import section (paste label, paste box 460 wide, import/
  reset buttons, status) in a card; boss list below widens with the panel
  (verify rows anchor relative before relying on it).

Existing per-tab section titles stay outside/above their cards.

## 3. Text colors

- Factories in Utils.lua switch label templates from gold to white:
  `CreateSettingsCheckbox` cb.text, `CreateSettingsSlider` s.title,
  `CreateCard` titleText → `GameFontHighlightSmall`.
- Panel titles and field labels in MainFrame.lua, LootCouncil.lua,
  Invite.lua: `GameFontNormal`/`GameFontNormalLarge`/`GameFontNormalSmall`
  → `GameFontHighlight`/`GameFontHighlightLarge`/`GameFontHighlightSmall`.
- Explicit `SetTextColor` calls (hints gray, raid-box amber, status
  green/red, role status) override templates and stay untouched. The
  raid-wide box's amber title/border is intentional and keeps its color.
- Factory-level change also affects other KART windows using these
  factories — intended, consistency.

## Out of scope

BuffChecker/LootHistory/vote windows' own layouts; no new locale strings;
no new settings. Version stays 2.0.0 on the branch (entries join the 2.0.0
changelog section; merge decision later).

## Risks

- LC raid box relies on layoutRaidBox() dynamic flow — only widths change,
  flow logic untouched.
- Two-column checkbox placement needs ClearAllPoints (factory hardcodes
  x=20); missing that shows as overlapping widgets in column 1.
- WU boss list rows: RefreshBossList row anchoring must be edge-relative;
  implementer verifies before widening.
