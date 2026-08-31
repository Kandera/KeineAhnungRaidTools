**English** | [Deutsch](https://github.com/Kandera/KeineAhnungRaidTools/blob/main/README-de.md)

# Keine Ahnung Raid Tools (KART)

A lightweight, modular World of Warcraft addon for raid and group leaders. Invites, readiness, a compact raidlead bar, Co-Tank, and — from 4.1 — Load & Send of the next [Northern Sky](https://github.com/Reloe/NorthernSkyRaidTools) shared note after a kill.

## Features

### 1. Automation
All automatic group functions on one tab:
*   **Keyword Invite:** Reacts to configurable keywords (e.g. "inv", "+") on the channels you enable: whisper, Battle.net, guild, and officer chat. Guild and officer are off by default so casual chat does not invite. If a keyword matched but the invite could not go out, KART replies on that same channel (including Battle.net).
*   **Auto-Promote:** Promotes predefined players to assistant when they join. Each entry is a character name or an NSRT nickname, so it still applies after they switch alts. Promote waits until combat ends.
*   **Auto-Raid:** Converts the group to a raid when a 6th player requests an invite; a full 5-man party stays a party.

### 2. Raid Lead Bar
A compact, movable bar:
*   **Raid Target Icons** and **World Markers.** Right-click a marker on the bar to clear that marker.
*   **Ready Check** and a native **Pull Timer** (no BigWigs/DBM; default 10 seconds).
*   **Look:** scale, button size, bar opacity, and layer (including under the world map). Optional combat auto-hide. Optional hide of Blizzard's raid manager while the bar is shown; Northern Sky is not touched.
*   **Keybinds** on the Raidlead tab (Ready Check, clear world markers, Pull Timer, Buff Checker). Once set, they keep working through combat lockdown.

### 3. Enhanced Ready Check
*   When players click "Not Ready", they pick a short reason (AFK, drink, 1 min) or type free text. The lead sees it in chat and as a hint icon on the Buff Checker (full text on hover).

### 4. Buff Checker & KART Sync
Raid-readiness window:
*   **Stat Check:** Intellect, Stamina, Mark of the Wild, Battle Shout, Blessing of the Bronze, and Skyfury.
*   **Consumables:** Food, Flask, Rune, plus **Healthstone** (the stone in bags) and **Soulstone**.
*   **Extended View (Gear Check):** Item level, missing enchants and gems, with a tooltip for which slots.
*   **Fleeting bags (Advanced):** how many cauldron potions and flasks each KART player has (`pots / flasks`). **Bag Check** asks the raid for those counts and does not post to chat. The Flask column on the ready-check view is still the aura.
*   **Weapon Oil & KART Sync:** Hidden addon messages read oil even when the player is too far to inspect.
*   **Durability** (needs *LibDurability*). **Report** posts missing buffs to raid or party; Shift-click Report whispers flask and food to whoever is missing them.
*   Opens on a ready check. Can be disabled to save CPU; background sync (oil/ilvl/gear for others) stays on.
*   **Advanced** shows whether RC, NSRT and WowUtils are current, outdated, or missing. **Check Addon Versions** on Settings sends a window to raiders who are behind.
*   The empty slot under Buff Check opens Role Poll, Convert, and Restrict Pings.

### 5. Co-Tank frame
*   Off until you enable it on the Co-Tank tab. The tab previews the row in town. Test mode keeps the invented row after you close the window.
*   Live: other tank's health, debuffs and buffs. Optional group/instance filters (dungeons stay off; raids on by default). Unlock to place it without a group. Left-click targets the other tank.
*   Look, Text and Auras open in a companion panel (bar texture and optional gradient, LibSharedMedia when installed).
*   Optional: say when you taunt, an on-screen **take it** button (or action-bar macro), and a short Taunt Swap line on the other tank. All off until you turn them on. Test mode for the line in town.

### 6. NSRT Notes
After a kill — and when the lead zones into the raid — KART loads and shares the next Northern Sky **shared** note so healers are not stuck on the previous boss.
*   Paste imported shared notes on the **Notes** tab. **Delete notes** next to Import clears the NSRT shared library and the paste box.
*   The list is Encounter Journal order, then extra notes. Drag to reorder (drop target highlights), skip, or click a boss to start there. Each row shows difficulty; Invite and Remove swap that boss's imported roster.
*   A designated **note operator** (often calling from town) owns the list when they are in the group, assistant, and not stale. Only the raid leader sets the operator name. The lead sends if the operator is missing or has no KART.
*   **Share now** waits while the raid is in combat, including when you are outside. In town, share uses the lead's published difficulty, not a local guess. The status line shows who would send.

### 7. RCLootCouncil companion
KART does not ship a built-in loot council. **Install [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil)** for session, voting, trade UI and loot history. **WowUtils** (addon + Bridge) paints sim columns on RC's voting frame.

KART adds three hooks:

*   **Council by nickname:** On Settings, the raid leader lists council as NSRT nicknames (or character names). KART pushes only GUIDs of members whose current alt is in the raid into RC's council list.
*   **Award relay:** Council clicks Award in RC; KART whispers the raid leader, whose client calls RC's `Award()` so the lead can keep trading.
*   **Winner trade reminder:** When you win an item, a small window lists what you are owed so you can walk to the lead. A row drops when you actually receive that item in trade. The lead still uses RC's Trade UI. Toggle on Settings (on by default); `/kart owed` reopens it.

This guild runs KART as a raid requirement. Other raiders still need RCLootCouncil and WowUtils (addon + Bridge). The old desktop **KART Companion** tray app is discontinued; it is not the WowUtils Bridge.

### 8. Customization (Settings)
*   Colors, transparency, fonts. Windows and text fields close or deselect with ESC.
*   English and German. Minimap icon or Addon Compartment.
*   **Edit Mode** dims the world with a Done banner so every enabled module frame can be placed in town without changing saved locks.
*   In-game changelog panel; footer links for CurseForge, Wago and GitHub (copy-from box).
*   Version check: `/kart v`. Modular disable for the Buff Checker.

## Requirements

*   **[Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools)** — shared notes (Notes tab) and nicknames for auto-promote and the RC council list. Character names still work when a nickname is absent.
*   **RCLootCouncil** — loot council (required for loot features).
*   **WowUtils addon** — RC voting-frame columns.
*   **WowUtils Bridge** — WowUtils' data pipe (not the discontinued KART Companion tray app).

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/kart` | Opens or closes the main configuration window. |
| `/kart version` (`/kart v`) | Requests the KART version from everyone in your current guild, raid, or party, and prints the responses. |
| `/kart owed` | Reopens the list of items you are still owed. |
| `/kart ench [raid]` | **Maintenance tool, not for regular play.** Prints enchant IDs for tier-table maintenance. |
| `/kart help` (`/kart h`) | Prints this command list. |

## Installation
1. Download the `KeineAhnungRaidTools` folder.
2. Copy it into your World of Warcraft directory: `_retail_\Interface\AddOns\`.
3. Start the game and enable the addon in the addon list.

## Contributors
*   **Author:** Kandera

## Third-party libraries
Bundled unmodified, each under its own license:

*   **[Ace3](https://www.wowace.com/projects/ace3)** (AceComm-3.0, CallbackHandler-1.0) — © Ace3 Development Team, BSD-style license.
*   **ChatThrottleLib** by Mikk — released into the Public Domain.

## License
This project is licensed under the MIT License - see the LICENSE.md file for details.

*Made for the guild "Keine Ahnung".*
