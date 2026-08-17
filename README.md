**English** | [Deutsch](https://github.com/Kandera/KeineAhnungRaidTools/blob/main/README-de.md)

# Keine Ahnung Raid Tools (KART)

A lightweight, modular World of Warcraft addon built specifically for raid and group leaders. It streamlines invite management, raid-readiness checks, and gives quick access to essential raid lead tools.

## Features

### 1. Automation
All automatic group functions bundled into a single tab:
*   **Keyword Invite:** Reacts to configurable keywords (e.g. "inv", "+") in whispers, guild chat, or Battle.net messages. The guild-chat trigger is a separate toggle (disabled by default) to avoid accidental invites from casual guild chat.
*   **Auto-Promote:** Automatically promotes predefined players to assistant as soon as they join the group. Ideal for co-leads and fixed raid roles. Each entry accepts either a character name or a [Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools) (NSRT) nickname, so it keeps applying automatically even after that person switches to a different character.
*   **Auto-Raid:** Automatically converts the group into a raid when a 6th player requests an invite; a full 5-man party stays a party.

### 2. Raid Lead Bar
A compact, movable bar for quick access to:
*   **Raid Target Icons:** Set markers on targets.
*   **World Markers:** Place colored pillars on the terrain.
*   **Ready Check:** Instantly start a ready check.
*   **Pull Timer:** Customizable countdown for pull start (native WoW countdown, no BigWigs/DBM required; default: 10 seconds).
*   **Keybinds:** Ready Check, Clear World Markers, Pull Timer, and the Buff Checker toggle can each be bound to a key from the Raid Lead settings tab (click a bind button, then press the key; binding it there steals the key from whichever action already had it, like Blizzard's own keybind UI). Bindings keep working through combat lockdown once set.

### 3. Enhanced Ready Check
*   When players click "Not Ready", a modern window opens where they can select a quick reason (AFK, drink, 1 min) or enter custom free text. These reasons are posted to the raid lead in chat and shown in the Buff Checker via a small hint icon next to the player's name (full text in tooltip on hover) — regardless of text length, without breaking the layout.

### 4. Buff Checker & KART Sync
A detailed window for checking raid readiness:
*   **Stat Check:** Checks Intellect, Stamina, Mark of the Wild, Battle Shout, Blessing of the Bronze, and Skyfury.
*   **Consumables:** Shows who has an active Food, Flask, or Rune buff.
*   **Extended View (Gear Check):** A dedicated view shows exact item level as well as missing enchants and gems. An interactive tooltip shows exactly which armor slots are missing them.
*   **Weapon Oil & KART Sync:** Hidden addon messages between KART users read out the exact weapon oil status, even when players are too far away to inspect.
*   **Durability:** Shows equipment repair status (requires *LibDurability*).
*   **Report Function:** Posts missing buffs directly to raid or party chat.
*   **Ready Check Integration:** Opens automatically when a ready check starts.
*   **Module Toggle:** The Buff Checker can be fully disabled to save CPU when not needed. The background KART sync (oil/ilvl/gear answers for others) stays active regardless, so the raid lead still sees correct data about this player.

### 5. RCLootCouncil companion
KART 4.0 no longer ships a built-in loot council. **Install [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil)** for session, voting, trade UI and loot history. The raid also runs the **WowUtils** addon (distributed with RC) for sim columns on RC's voting frame.

KART adds two hooks on top of RC:

*   **Council by nickname:** On the Settings tab, the raid leader lists council members as [Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools) nicknames (or character names). KART pushes only the GUIDs of members whose current alt is in the raid into RC's council list whenever the roster changes.
*   **Award relay:** Council members click Award in RC's voting frame; KART whispers the raid leader, whose client calls RC's `Award()` so the lead can keep trading instead of living in the voting UI.

Everyone who should click Award, and the raid leader who receives those clicks, needs KART. Other raiders need RC and WowUtils only.

### 6. WoWUtils roster paste (Automation tab)
*   Raid compositions can be imported from WoWUtils via copy-paste on the **Automation** tab (boss-by-boss format with encounter, difficulty, and invite list).
*   Each imported boss gets its own row with **Invite** and **Remove** buttons to swap compositions quickly.
*   Multiple imports merge by encounter + difficulty; **Reset** clears the saved list.

### 7. Customization (Settings)
*   Fully customizable interface (colors, transparency, fonts).
*   Standard-compliant controls: windows and text fields can be closed/deselected with ESC.
*   English and German language support.
*   Access via minimap icon or the Addon Compartment frame.
*   Version checker: check whether all raiders are running the latest KART version (`/kart v`).
*   **Modular disabling:** The Buff Checker can be fully disabled to save CPU when not needed.

## Requirements

*   **RCLootCouncil** — loot council (required for loot features).
*   **WowUtils** — RC voting-frame columns (installed alongside RC in this guild).
*   **Northern Sky Raid Tools** (optional) — nicknames for auto-promote and RC council list; falls back to character names when absent.

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/kart` | Opens or closes the main configuration window. |
| `/kart version` (`/kart v`) | Requests the KART version from everyone in your current guild, raid, or party, and prints the responses. |
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
*   **[LibDeflate](https://github.com/SafeteeWoW/LibDeflate)** by Haoqian He — zlib license.

## License
This project is licensed under the MIT License - see the LICENSE.md file for details.

*Made for the guild "Keine Ahnung".*
