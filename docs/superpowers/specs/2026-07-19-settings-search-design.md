# Settings Search — Design

## Purpose

The main window now spans 6 tabs with multiple cards each (Automation, Raidlead, BuffCheck, Loot
Council, WoWUtils, Settings), and keeps growing (Keybinds, Profiles, and Raidlead-Only Settings
Sync all added new cards recently). Finding a specific setting means remembering which tab, then
scrolling. A search box lets the user type a setting's name and jump straight to it, like Windows
Settings search or ElvUI's config search.

Out of scope: searching inside Loot History (already has its own player/reason/item filter per the
README — a different, list-filtering feature, not a "find this control" feature); searching popup
windows outside the main tabbed window (Buff Checker, Loot Council vote/council panels, Loot
History); fuzzy/typo-tolerant matching (plain case-insensitive substring is enough for a short
settings-name search).

## Index: reuse `KART.DynamicLabels`, no per-widget registration

Every settings-related `FontString` created anywhere in this codebase already gets inserted into
`KART.DynamicLabels` — an existing, established convention (used by every checkbox label, slider
title, card title, hint text, and tab title across `MainFrame.lua`, `LootCouncil.lua`, `Invite.lua`,
`RaidleadBar.lua`, `Profiles.lua`, `BuffChecker.lua`'s settings). This feature does not add a new
registration call at each of those dozens of call sites — it builds its search index by walking the
existing list instead.

`KART.BuildSearchIndex()`: iterates `KART.DynamicLabels`; for each `FontString`, walks its
`GetParent()` chain until it finds one of the 6 known tab-content panels (`KART.PromotePanel`,
`KART.RaidleadPanel`, `KART.BuffCheckPanel`, `KART.SettingsPanel`, `KART.LootCouncilPanel`,
`KART.WoWUtilsPanel`); if found, records `{ text = fontString:GetText(), tabIndex = N, widget =
fontString }`. A `FontString` whose parent chain never reaches one of those 6 panels (e.g. one that
belongs to a popup window instead) is silently skipped — this is how the "only the 6 main tabs" rule
enforces itself without an explicit exclusion list.

Labels whose text is empty or `nil` at index-build time are skipped (defensive — none currently are,
but a future label built before its text is set could otherwise pollute the index with a blank
entry). The index is a `KART.SearchIndex` table, rebuilt on demand (see below), not persisted.

**Rebuild timing:** most of `KART.DynamicLabels`'s entries exist by the time `ADDON_LOADED` finishes
(everything is created at file-load time or `ADDON_LOADED`), but some are conditional
(`KART.LC.RelayoutRaidBox` re-wraps council/lootmaster hint text; new keybind rows, profile rows,
etc. are all created once, not dynamically added later). Given all `FontString`s are created once
at load and never destroyed, rebuilding the index once per search-box open (not on every keystroke)
is both correct and cheap enough — there is no need to rebuild on every filter keystroke, only when
the search popout is opened.

## UI

A small icon button, always visible regardless of the active tab, positioned in the plain
(non-baked-artwork) area of the header row next to the active tab's title — not overlapping the
baked logo/title zone at the very top of the window (that zone is fragile, per existing comments in
`MainFrame.lua` about the artwork's fixed geometry). Exact pixel anchor is an implementation detail
resolved by reading the current header layout, not fixed here.

Clicking it toggles a small popout frame anchored below the button: one `EditBox` (reuse
`KART.CreateStyledEditBox`, the existing styled edit box factory already used elsewhere in this
codebase) and a results list below it (up to 8 rows, each a clickable line of text). Typing
filters the already-built index case-insensitively by substring match against each entry's `text`;
results update on every keystroke (filtering an in-memory list of a few dozen entries is trivially
cheap — only the initial index *build* is deferred to open-time, not the per-keystroke filter).

If the query is empty, the popout shows no results (not the full unfiltered list — an empty query
isn't "browse everything," it's "haven't searched yet"). If there are zero matches for a non-empty
query, the results area shows nothing extra (an empty list is self-explanatory; no separate "no
results" string is needed for a single-purpose search box like this).

Pressing Escape or clicking outside the popout closes it without navigating. The popout auto-closes
after a result is clicked (see Jump below).

## Jump behavior

Clicking a result:
1. `KART.ShowTab(entry.tabIndex)` — switches to the tab containing the match (a no-op if already
   on that tab).
2. Scroll the shared content `scrollFrame` so `entry.widget` is visible: compute the target
   scroll offset from `entry.widget:GetTop()` relative to `scrollFrame:GetTop()` (standard WoW UI
   "scroll to anchor" idiom), clamped to `[0, maxScroll]` the same way `KART.UpdateScrollRange`
   already clamps.
3. Briefly highlight `entry.widget`: show a translucent accent-colored glow frame sized to the
   label (plus small padding), anchored over it, faded out via a ~1.5 second timer (reuse the
   existing accent-color/fade patterns already used elsewhere in this codebase, e.g. the slider
   thumb glow in `KART.CreateSettingsSlider`). One shared highlight frame is reused across
   searches (created once, re-anchored and re-shown per jump) rather than creating a new frame per
   search.
4. Close the popout and clear the search box's text.

## Testing

Manual (no automated test suite in this project): `/reload`, open `/kart`, click the search icon.
Type a setting name that exists on a non-active tab (e.g. "Pull Timer" while on the Automation
tab) — confirm a matching result appears. Click it — confirm the window switches to the Raidlead
tab, scrolls so the Pull Timer slider is visible, and the slider's label briefly glows. Type a
query matching multiple tabs (e.g. "quality" — matches both Loot Council's min-quality button and
possibly other labels) — confirm multiple results, each jumping correctly. Type a query with no
matches — confirm the popout shows no results and doesn't error. Press Escape — confirm the popout
closes without navigating. Confirm the search icon and popout do not visually overlap the baked
window artwork (logo/title/close-button hit areas) at default UI scale and at the extremes of the
"Window Scale" slider.
