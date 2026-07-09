**English** | [Deutsch](CHANGELOG-de.md)

# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.10.2] - 2026-07-09
### Fixed
- **CurseForge upload never actually ran:** The release workflow passed the API key to the BigWigsMods packager as `CF_API_TOKEN`, but the packager only recognizes `CF_API_KEY`. Every automated release job (including 1.10.1) therefore reported success while silently skipping the CurseForge upload — no file ever reached CurseForge. The workflow now passes the key under the name the packager expects.

## [1.10.1] - 2026-07-09
### Fixed
- **Addon icon missing from the release zip:** The GitHub release workflow excluded `*.jpg`/`*.png` files from the packaged zip, which also stripped `KAimg.jpg` — the file referenced by `IconTexture` in the TOC. Anyone installing from a GitHub/CurseForge release (as opposed to a git checkout) saw a blank icon in the AddOn list. The exclusion is gone; image files are now included again.

## [1.10.0] - 2026-07-08
### Added
- **Loot Council now shows all simultaneously dropped items at once instead of one after another:**
  - **Looter view:** The single voting popup has become a list — every currently running item gets its own row with its own vote buttons, its own note field, and its own countdown. This shows all drops at a glance and lets you decide independently per item (e.g. BIS on one, Pass on another) instead of having to clear one item before the next even becomes visible.
  - **Council/loot master view:** The panel now has a vertical tab strip on the left edge — one tab per currently running item, with the real item icon and a "votes/total" display. Assigning via right-click no longer closes the tab automatically, so you can switch back and forth between items calmly and change your mind if needed. Hovering over a tab immediately shows the full vote breakdown for that item, without switching to it at all. A new tab never yanks away the one currently being viewed — it only gets a small red "new" dot and waits. The "×" to close a single tab now only appears on hover (instead of sitting there permanently) so a normal click to switch tabs doesn't accidentally close one. A row's green winner highlight is now also per-item instead of global — previously, a player who had already been assigned an item stayed incorrectly marked green when switching to a different item.
  - Both test buttons ("Test Looter" / "Test Master") now distribute 4 simulated items at once for testing, so this exact behavior can be run through without a real raid. The test items are now real (but consequence-free) item links (Sulfuras, Thunderfury, Corrupted Ashbringer, Hand of Justice) instead of made-up strings — as a result, the tabs show real item icons, tooltips work, and the armor type hint as well as the gear comparison can also be tested in test mode. The trinket specifically covers the two-slot comparison (rings/trinkets check both slots and show the weaker piece) — the three weapons are all single-slot. Clicking the other test button no longer resets an already-running test round — previously, opening "Test Looter" while "Test Master" was already open (or vice versa) could silently rip the other window's tabs out from under it in the background; this only became visible on the next vote, which then incorrectly looked as if casting a vote made the tabs disappear and swallowed your own vote.
- **Test buttons in the Loot Council tab now work together:** A vote cast in the looter test window is immediately entered into the master test panel, even fully solo without a group at all — allowing the entire loot distribution flow to be run through alone, including assignment and the local "You won" popup. Test rolls stay strictly local: no broadcast to the group, no raid chat announcement, and no entry in the real (persistent) loot history — previously, a test run during an active raid could accidentally trigger a real winner announcement in raid chat and leave a fake entry in every other player's loot history.
- **1-100 random rolls in Loot Council (à la RCLootCouncil):** New option in the raid-wide settings ("Show 1-100 random rolls", only effective as raid lead). When enabled, every eligible raider automatically rolls a value from 1-100 as soon as an item comes up for vote — with no action needed, just like RCLootCouncil's need roll. The value appears as its own column in the council panel and is purely informational; it has no automatic effect on any assignment.
- **Council vote counter in the council panel:** Every row now has a "CV" button (Council Votes) that lets each council member vote for their favored candidate (clicking the same candidate again undoes the vote, clicking a different one replaces it). The number next to it shows how many council members currently voted for that player — purely for guidance; the actual assignment still only happens via right-click → Assign.
- **Persistent player notes in the council panel:** Right-click a row → "Edit Note" opens a text field for a permanent note about that player (e.g. "already has BIS trinket", "missed out on the last two items") — unlike a raider's per-vote note, this one isn't tied to a single item but appears for every item the player is listed under. It's distributed to all council members currently online and persists across reloads (its own SavedVariable); there is currently no reconciliation for council members who were offline while the note was written. The input window is its own small custom frame instead of a Blizzard StaticPopup — retail's reworked StaticPopup system (now routed through `Blizzard_StaticPopup_Game/GameDialog.lua`) no longer reliably exposed the input field as `self.editBox` in `OnAccept` and threw a Lua error on confirm.
- **Armor type hint in the council panel:** Rows for players who can't wear the current item's armor type at all (e.g. plate on a mage) are shown dimmed, with a tooltip hint. Purely visual — assigning via right-click still works for any row, in case the detection is ever wrong.
- **Trade reminder with auto-trade for Loot Council:** After an item is assigned to another player, KART remembers who still needs to be traded what, and shows a small, movable reminder window ("Items still to trade") with a list of all pending trades (a checkmark button to mark them off manually). If you then open a trade window with exactly the right player, the matching item is automatically placed from your bags into the trade window — the trade still has to be confirmed manually. Automatically cancels (the item stays in the reminder) if the item can no longer be found in your bags or something else is currently attached to your cursor.
- **Reset button in the WoWUtils tab:** Fully resets the imported boss list (with a confirmation dialog).

### Changed
- **Item icon in the vote list:** A small icon now also appears before the item name in the looter window (a real item icon for real items, a tinted placeholder otherwise) — matching the council panel.
- **Vote list in the looter window reworked, less cramped:** Window and spacing enlarged (more inner padding per item, more space between item blocks, more room around the note field), vote buttons slightly larger with a more subdued border color instead of a very bold one — previously everything sat nearly edge-to-edge and looked like a wall of boxes, especially with several items running at once.
- **A vote row closes/marks itself immediately after voting:** Instead of a "Vote cast!" intermediate state with a 2.5-second delay, the row now immediately shows "✓ Voted: <option>" — with several items running at once, this no longer wastes any time.
- **WoWUtils import across multiple difficulties:** A repeated import (e.g. pasting the Normal composition first, then the Heroic one) no longer overwrites the entire list. Entries are now merged based on EncounterID + Difficulty, so multiple difficulties of the same boss can stay in the list at the same time. The new Reset button is used to clear it completely.
- **Split-raid support in the WoWUtils import:** If a second import with a different roster is pasted for the same boss and difficulty (e.g. Team A / Team B for splits), it's no longer overwritten but added as its own entry. Entries with the same name are automatically made distinguishable as "Boss Name A", "Boss Name B", etc.

### Fixed
- **Empty boxes instead of icons in the council panel:** The new symbols (★ ☆ ● ✓) for the council vote button, the note marker, and the trade reminder weren't supported by WoW's default game fonts and were rendered as empty boxes ("tofu"). Replaced with plain ASCII text (e.g. "CV" instead of ★) or, for the trade reminder, with a real texture.
- **Column headers in the council panel didn't align with the values below them:** The headers (Player/iLvl/Vote/Roll/CV) had no fixed width or alignment, while the values below them sit centered at a fixed width in some cases (e.g. roll number, iLvl) — causing header and value to visibly drift apart. Every header now has exactly the same width, alignment, and X position as its column.
- **1-100 rolls stayed invisible even when enabled:** `LC.GetRollsEnabled()` only checked `UnitIsGroupLeader("player")`, which returns `false` without a group (e.g. when solo testing) — this always fell back to the (never synced) raid value instead of the local setting, keeping the rolls column hidden. Now uses the same fallback as `GetButtonConfig`: the local setting also applies when there's (not yet) any raid configuration.
- **Simultaneously dropped items overwrote each other in Loot Council:** The vote popup and council panel could previously only ever show exactly one roll at a time — if a boss dropped multiple items at once (the normal case, not the exception), each new roll immediately tore away the previous item's window before it could even be voted on or assigned. See the new list/tab view above, which fundamentally fixes this problem instead of just papering over it.
- **Comparison with the currently equipped item in the council panel never worked:** `C_Item.GetItemInfo()` returns a list of individual values, not a table — but the code only stored the first return value (the item name, a plain string) in a variable and then accessed it with `["equipLoc"]` / `["itemLevel"]`. Such an access on a string silently returns `nil`, so no matching equipment slot was ever found for any item — this affected not just test mode but every real loot assignment. The icon and item level of the currently equipped comparison item are now shown correctly.
- **"Change assignment" in the council panel incorrectly triggered a reassignment:** The submenu, when right-clicking an already-assigned item, showed a "reassign?" confirmation dialog even though it was only meant to correct a player's displayed vote (e.g. if someone voted via whisper instead of clicking). The menu entry is now called "Change Vote" and really only changes the vote — with no assignment, announcement, or confirmation dialog. Actual assignment (including reassignment with confirmation) now only happens via "Assign" or "Assign without reason".
- **Complete rework of the "Raid-wide settings" box (Loot Council) layout:** The box (title, role status, divider, vote timer slider, all labels/inputs/buttons) now positions itself entirely on its own: every element anchors to the actually measured bottom edge of the previous element instead of hardcoded pixel values. This fixes several related bugs at once:
  - Labels with longer text (especially German) stuck out past the right edge of the box → now have a fixed width with word wrap.
  - After a font/size change via `KART.UpdateStyles()` (which runs only after the panel is built), the line wrap would shift afterward and overlap the input fields → the layout is now automatically recalculated, both after `UpdateStyles()` and after every change of the role status text (raid lead/member).
  - The test buttons and the loot history button below stuck into the box because they were anchored at a fixed height based on the old static box height → now anchored to the box's actual bottom edge.
  - The box is also somewhat wider (280→295px), making better use of the available space; the scrollable area in the main window was proactively enlarged (600→750px) so nothing falls out of the visible/scrollable area at larger font sizes.

## [1.9.2] - 2026-07-07
### Fixed
- **Overlapping text in the Loot Council tab:** In the new "Raid-wide settings" box, the title and role status (e.g. "You are the raid lead") sat side by side on the same line in a box only 280px wide and collided in the middle. Both texts now sit stacked and were shortened significantly; all elements below were repositioned accordingly.

### Removed
- **`Minimap.lua`:** Dead file that hadn't been loaded by the TOC since version 1.1.1 (replaced by LibDBIcon) but was never actually deleted from the project. Among other things, it contained a second, never-executed version of `KART.UpdateMinimapButton()`.
- **Orphaned localization strings:** `BC_REPORT_ENCHANTS`, `BC_REPORT_GEMS`, `BC_REPORT_OIL` (never wired to a report field), `LC_DESC_COUNCIL` (never wired as a tooltip), `LC_NO_VOTE` (the code uses a hardcoded placeholder instead), and `SET_TITLE_SIZE` (duplicate of `LABEL_FONT_SIZE_TITLE`).

### Other
- **Added missing German translations:** `DESC_LANGUAGE`, `DESC_SELECT_FONT`, and `RC_REASON_SEND` previously fell back to English automatically and are now fully translated.

## [1.9.1] - 2026-07-07
### Fixed
- **Lua error on login:** `BuildSettingsPanel` in LootCouncil.lua accessed `KART_Settings.lcMinQuality` directly while building the UI — but at that point the SavedVariable doesn't exist yet (it's only initialized on `ADDON_LOADED`). The minimum quality button now uses placeholder text while building; the real stored value is pulled in immediately afterward as intended.

## [1.9.0] - 2026-07-06
### Added
- **Module toggles for Loot Council, Buff Checker, and WoWUtils:** Each module can now be individually disabled entirely — handy during a testing phase (e.g. when conflicting with RCLootCouncil) or to save CPU when raiders don't need certain features.
  - Disabling Loot Council stops processing any messages from other KART users entirely — no auto-pass, no popups.
  - Disabling the Buff Checker deliberately keeps the background KART sync active (oil/ilvl/gear answers for others) — only your own window is turned off, so the raid lead still sees correct data about this player.
- **Warning icon in the council panel:** Shows a red "!" per raider (with tooltip) if no KART was detected, an outdated version is running, or the player has disabled Loot Council locally.

### Changed
- **Raid-wide authority for Loot Council:** Voting timer, vote buttons, additional council members, and minimum item quality now always follow the raid lead's settings — not each individual player's local settings anymore. Prevents someone from, say, locally shortening the voting time or granting themselves unauthorized assignment rights via their own council list.
  - **Auto-pass is unaffected by this** and remains a purely personal setting.
  - The affected settings are now visually set apart in their own box in the options menu, including a live display of whether your own settings currently apply ("You are the raid lead" / "The raid lead's settings apply").

## [1.8.1] - 2026-07-06
### Changed
- **Buff Checker design:** Ready check reasons are no longer shown as inline text, but as a small golden info icon right after the name — the full text appears in the tooltip on hover. This keeps the layout stable regardless of text length, with no window resizing.

### Fixed
- **Addon icon in the WoW addon list:** The TOC file was missing the `## IconTexture` field, causing a question-mark placeholder to be shown instead of the icon in the Blizzard addon list (ESC → AddOns). The minimap icon was unaffected (its own mechanism via LibDBIcon). `KAimg.jpg` is now correctly referenced there too; visible after a full client restart or at the next login screen.
- **Buff Checker: ready check reasons overlapped buff icons:** Long "not ready" texts (e.g. AFK reasons) used to be appended directly as text after the player name, in a fixed-width column with no word wrap. As a result, longer texts immediately overlapped the buff icons until the window was manually widened.

## [1.8.0] - 2026-07-06
### Changed
- **"Auto-Invite" tab removed, "Auto-Promote" tab → "Automation":** Since the keyword-based auto-invite feature (whisper/guild chat/Battle.net) served its one remaining purpose, it was moved into the Auto-Promote tab. Since this tab now bundles several automation features (keyword auto-invite, auto-promote, auto-raid-convert), it was renamed to "Automation".
- **"Automatically convert to raid":** This setting moved from the Settings tab into the new Automation tab, right next to the other automatic group functions.

### Removed
- **Bulk invite ("Paste raid composition"):** The old copy-paste feature in the Auto-Invite tab has been completely removed — it was fully replaced by WoWUtils Import, which solves the same task more reliably and conveniently.

## [1.7.0] - 2026-07-06
### Added
- **Minimum item quality for Loot Council:** New setting (default: Epic) — items below the selected quality don't trigger Loot Council at all; the normal WoW roll window is used instead. Prevents unnecessary voting popups for trash loot.
- **Lock against double assignment:** If an item is assigned a second time via the assignment menu (e.g. by accident), a confirmation dialog appears before the actual assignment, showing both the previous and the new recipient.
- **Fully synchronized loot history:** Every KART user in the raid now automatically logs the same assignments (reason included) — not just the loot master anymore. This gives every player a complete, shared history regardless of who is currently assigning.
  - **Difficulty column:** Every history entry now additionally stores the raid difficulty (e.g. Heroic, Mythic) at the time of the assignment.
  - **Automatic catch-up sync:** If a player rejoins a raid after missing a session, their client silently queries the other KART users once for missing entries. Responses run exclusively over the invisible addon channel (no chat/whisper visible to the player), are capped at the last 30 missing entries or 14 days, and are answered with a slight delay to avoid traffic spikes.

## [1.6.0] - 2026-07-06
### Added
- **Loot History:** New module (`LootHistory.lua`) that permanently logs every item assigned via Loot Council (SavedVariable `KART_LootHistory`, max. 500 entries).
  - New window with date, class-colored player name, item (icon + hover tooltip), and reason.
  - **Filters:** Free-text search over the item name, dropdown filter by player, dropdown filter by reason (including "No reason"), plus a reset button.
  - Footer shows "X of Y entries"; **"Clear History"** button with a confirmation dialog.
  - The window is movable, its position is saved; reachable via a new "Loot History" button in the Loot Council options menu.
- **Assignment menu in the council panel:** Right-clicking a raider row now opens a context menu instead of assigning immediately:
  - **Assign:** Awards the item using the player's currently cast vote as the reason.
  - **Change assignment:** Submenu with all configured vote buttons to correct the reason afterward (e.g. from BIS to Upgrade).
  - **Assign without reason:** Awards the item with no reason given — handy when nobody wants the item but the loot history shouldn't be skewed.
  - The panel never closes on its own; only the "Close" button or the "×" close it.

### Changed
- **Left-click in the council panel:** No longer does anything (prevented accidental assignments); all actions now run through the new right-click menu.
- **Item icon in the council panel:** Every raider row now also shows the icon of the currently equipped comparison item in the matching slot, alongside the item level.
- **Real item tooltips:** The item name in the vote popup and the council panel is now hoverable and shows the full item tooltip; the council panel additionally compares each raider's equipped item side by side using the native comparison tooltip (`ShoppingTooltip`).
- **The loot master window no longer closes automatically** when assigning — allows corrections without reopening it.

## [1.5.0] - 2026-07-01
### Added
- **WoWUtils Import:** New module (`Invite.lua`) and new "WoWUtils" tab in the sidebar.
  - Raid setups can be pasted directly from WoWUtils into the addon (boss-by-boss format with `EncounterID`, `Difficulty`, `Name`, and `invitelist`).
  - After importing, each boss gets its own row with the player count.
  - **[Invite]:** Invites all players from that boss's list into the raid — members already in the raid are skipped (output: "X invited. (Y already in the raid)").
  - **[Remove]:** Kicks all current raid members who are NOT on the boss list — ideal for quickly switching between boss compositions.
  - The import is saved across sessions; parsed automatically on login.
  - The scrollbar in the input field now follows the addon's color scheme.

### Changed
- **Auto-Pass:** Now triggers immediately when a loot roll starts (`START_LOOT_ROLL`), instead of only after the winner is announced — prevents the raid lead from accidentally clicking Need/Greed/Transmog.
- **Note field in the vote popup:** Raiders can add an optional free-text comment to their vote (max. 80 characters). The note is visible to council members in that row's hover tooltip.
- **Movable windows with saved position:** The vote popup and council panel can now be dragged; the position is saved in the SavedVariables and restored the next time they're opened.
- **Sorting in the council panel:** Rows are sorted ascending by button index (BIS first, then Upgrade, etc.); non-voters end up at the bottom.
- **Right-click to reassign:** Right-clicking a row in the council panel reassigns the loot without closing the panel — for quick corrections without reopening it.
- **Winner highlight:** The most recently chosen winner row is highlighted green and stays marked until the panel is closed or a new winner is chosen.
- **Test mode split up:** The single "Start Test" button was replaced by two separate buttons:
  - **Test: Looter** — shows the vote popup including the note field, regardless of your own role.
  - **Test: Loot Master** — shows the council panel including pre-filled votes (from current group members), regardless of your own role.
- **Version number in the title:** The "v1.3.0" display in the main window title is now always read from the addon metadata, so it's always correct.

## [1.4.0] - 2026-07-01
### Added
- **Loot Council:** New module (`LootCouncil.lua`) for coordinated loot distribution in the raid.
  - When entering a raid, the raid lead is asked whether Loot Council should be enabled for this session – simply decline for fun runs.
  - **Raider voting:** As soon as an item is up for distribution (`START_LOOT_ROLL`), a popup with configurable vote buttons (default: BIS / Upgrade / Offspec / Other / Pass) appears simultaneously for all KART users. The voting time is adjustable (default: 20 sec).
  - **Council panel:** The raid lead and assistants instead see a scrollable panel with all raiders and their votes (class-colored). Clicking a player selects them as the winner.
  - **Winner notification:** The chosen player gets a green notification window. The decision is automatically announced in raid/party chat.
  - **Auto-Pass:** Optional checkbox – when enabled, all non-winners with KART pass immediately with no confirmation.
  - **Configurable buttons:** The number and labels of the vote buttons are freely configurable (semicolon-separated, up to 6 buttons).
  - **Manual toggle:** The session can be toggled at any time via the new "Loot Council" tab in the main window or a button.
  - **Extended council members:** In addition to the raid lead and assistants, any player can be named to the council by name – they see the council panel without needing assistant rank.
  - **Test function:** "Start Test" simulates the entire Loot Council flow with a classic dummy item. In a raid, existing group members are pre-filled with random test votes; solo, the vote popup appears to check the button layout.
- **New tab:** "Loot Council" in the main window sidebar with all related settings.
- **Localization:** All new text translated into German and English.

## [1.3.0] - 2026-06-12
### Added
- **Extended view:** The Buff Checker now has a button to switch between "Ready Check" (standard buffs) and "Extended".
- **Gear check:** The extended view now shows the exact item level, weapon oil, and missing enchants/gems via KART sync.
- **Gear tooltips:** If a player is missing enchants or gems, a tooltip in the Buff Checker shows exactly which armor slots are missing them on hover.
- **Scrollable text field:** The input field for bulk invite (raid composition) was enlarged and given a dynamic scrollbar.

### Changed
- **Default settings:** The raid lead bar and Buff Checker are now disabled by default on first install, to keep the interface tidy.
- **ESC key:** The main window and all text input fields can now be deselected/closed with the ESC key, as expected.

### Fixed
- **Network traffic:** Queries for the "Extended" view (iLvl, gear, oil) are no longer spammed in the background, but only load when switching views or clicking "Refresh".

## [1.2.0] - 2026-06-12
### Added
- **Enhanced ready check:** When players click "Not Ready", a small window now opens to specify a reason (AFK, drink, 1 min, or free text). The reasons are shown to the raid lead in chat and directly in the Buff Checker.
- **Addon sync (KART Sync):** KART now communicates invisibly with other KART users in the raid. Among other things, this reads out applied weapon oil exactly, even when Blizzard's API is limited.
- **Version checker:** KART compares versions within the guild/raid and posts a chat hint as soon as a newer version is available. `/kart v` can be used to check the KART versions of other players.
- **Tooltips for the raid lead bar:** The buttons on the raid lead bar (ready check, clear world markers, pull timer) now explain their function on hover.
- **Addon Compartment frame:** KART now hooks seamlessly into WoW's modern minimap dropdown menu (Dragonflight/TWW).
- **Font selection:** Thanks to LibSharedMedia integration, the addon's font can now be changed in the settings.
- **Language selection:** New dropdown in the settings to manually override the addon language (Auto/German/English).
- **Buff Checker preview:** A new "Toggle Preview" button allows testing the Buff Checker's layout and colors using sample data, without being in a raid.

### Changed
- **Buff Checker layout:** The Buff Checker window no longer has a fixed width and can be resized horizontally. The name column and buff icons now scale dynamically with the new width, so even long ready check reasons stay readable.
- The English translations (enUS) were substantially expanded to cover all new menus and reasons.

### Fixed
- Fixed a layout bug in the ready check dialog caused by overlapping SetPoint calls.
- Fixed a bug where the `enUS.lua` language file was out of sync with `deDE.lua`.

## [1.1.1] - 2026-05-24
### Changed
- Code cleanup: removed the obsolete `Minimap.lua` file (minimap logic is now handled more cleanly via LibDBIcon).

### Fixed
- **Crash when changing UI colors:** The deprecated color picker API was replaced with the modern `ColorPickerFrame` API, which no longer causes crashes.
- **Taint safety:** Automatic raid conversion on keyword and bulk invites now correctly blocks during combat (`InCombatLockdown`) to avoid Lua errors.
- **Taint safety:** The update process for the pull timer button on the raid lead bar was hardened against combat taints (`GROUP_ROSTER_UPDATE`).
- **Localization:** Fixed a missing fallback for game clients using other languages (e.g. French, Russian). The addon now always falls back to English (enUS) cleanly in those cases.
- **Critical bug:** The deprecated `table.wipe` function in the Buff Checker, since removed in retail WoW, was replaced with the modern global `wipe` function.

## [1.1.0] - 2026-05-21
### Added
- **Buff Checker:** New window for checking raid buffs, consumables, and durability.
- **Raid Lead Bar:** Interactive bar for markers, world markers, ready checks, and pull timer.
- **Localization:** Full support for German (deDE) and English (enUS).
- **Minimap management:** Integration of LibDBIcon for a movable icon.
- **Modern UI style:** Completely new sliders and checkboxes without default WoW textures.
- **Tooltips:** Detailed descriptions for all settings options.

### Changed
- Performance optimizations via event throttling (throttled buff updates).
- Improved architecture: frames are now only loaded on demand.
- Keyword search switched to hash tables for $O(1)$ complexity.

### Fixed
- Fixed a string concatenation bug in the language selector.
- Fixed a "table index is nil" error in core initialization.
- Automatic conversion to raid now correctly blocks during combat (taint avoidance).

## [1.0.0] - Initial Release
### Added
- Basic auto-invite functionality via keywords.
- Bulk invite system for raid compositions.
- Auto-promote system for assistant roles.

[Unreleased]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.10.0...HEAD
[1.10.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.2...v1.10.0
[1.9.2]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.1...v1.9.2
[1.9.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.8.1...v1.9.0
[1.8.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.5.0...v1.8.1
[1.5.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.3.0...v1.5.0
[1.3.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Kandera/KeineAhnungRaidTools/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Kandera/KeineAhnungRaidTools/releases/tag/v1.0.0

<!--
Note: 1.4.0, 1.6.0, 1.7.0, and 1.8.0 don't have their own git tag (not traceable as a
standalone commit state in the history) and are therefore not linked here.
From v1.8.1 onward, every version is consistently tagged, so future entries can be
linked in full.
-->
