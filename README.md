**English** | [Deutsch](README-de.md)

# Keine Ahnung Raid Tools (KART)

A lightweight, modular World of Warcraft addon built specifically for raid and group leaders. It streamlines invite management, raid-readiness checks, and gives quick access to essential raid lead tools.

## Features

### 1. Automation
All automatic group functions bundled into a single tab:
*   **Keyword Invite:** Reacts to configurable keywords (e.g. "inv", "+") in whispers, guild chat, or Battle.net messages. The guild-chat trigger is a separate toggle (disabled by default) to avoid accidental invites from casual guild chat.
*   **Auto-Promote:** Automatically promotes predefined players to assistant as soon as they join the group. Ideal for co-leads and fixed raid roles. Each entry accepts either a character name or a [Northern Sky Raid Tools](https://github.com/Reloe/NorthernSkyRaidTools) (NSRT) nickname, so it keeps applying automatically even after that person switches to a different character.
*   **Auto-Raid:** Automatically converts the group into a raid once more than 5 members join.

### 2. Raid Lead Bar
A compact, movable bar for quick access to:
*   **Raid Target Icons:** Set markers on targets.
*   **World Markers:** Place colored pillars on the terrain.
*   **Ready Check:** Instantly start a ready check.
*   **Pull Timer:** Customizable countdown for pull start (native WoW countdown, no BigWigs/DBM required; default: 10 seconds).

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

### 5. Loot Council
Coordinated loot distribution directly inside the addon, no external tools required:
*   **Session Activation:** When entering a raid, the raid lead is asked whether Loot Council should be enabled for this session (simply decline for fun runs). Can be toggled manually at any time.
*   **Raider Voting:** As soon as an item is up for distribution, a list with up to five configurable vote buttons (default: BIS / Upgrade / Offspec / Other / Pass) plus a fixed Transmog button appears simultaneously for all raiders, along with an optional note field to comment on their own vote. When multiple items drop at once (the normal case for most bosses), each item gets its own row with its own countdown — all drops are visible at the same time, so you can decide independently per item (e.g. BIS on one, Pass on another) instead of having to clear one item before the next even becomes visible. A row marks itself as done immediately after voting and disappears once its own voting time runs out. A personal settings toggle switches this list between a spacious layout (larger cards, the default) and a compact one (smaller single-line rows with icon-only vote chips) for a much smaller window footprint. Two further personal toggles keep items your class cannot equip out of your way: one hides them and answers them with your last configured response, the other votes Transmog on them while their appearance is still missing from your collection — both are off by default, and `/kart showall` brings a hidden item back.
*   **Council Panel:** The council members the raid leader lists — plus whoever hands out the loot, who is always in the council — see a movable, scrollable panel with all votes (class-colored), sorted by vote priority. It also shows, per player, the item level (including icon) of the currently equipped comparison item in the relevant slot, so it's immediately clear who would get an upgrade, plus a Guild Rank column right next to the name to make it easy to spot alts of the same player at a glance. A minimize button collapses the panel down to just its header and item name so it can stay on screen during normal raiding, without losing track of any active vote in the background. An optional personal toggle shows each candidate's NSRT nickname instead of their character name here, falling back to the character name automatically wherever no nickname is set. When multiple rolls run at the same time, each item gets its own tab on the left edge (colored by item quality, with a "votes/total" display) — clicking switches the view without an assignment automatically closing the tab, so you can calmly compare between items and change your mind if needed. Hovering over a tab immediately shows the full vote breakdown for that item, even without switching to it; a newly arriving tab only gets a small "new" dot instead of yanking away the tab you're currently viewing.
*   **Lootmaster:** The raid lead can designate one player — by character name or by NSRT nickname — who must win every roll (Need, or Greed/Disenchant if Need isn't available) instead of passing, so they can physically receive each item and hand it out to whoever the council picked. Overrides that player's own Auto-Pass setting; controlled by the raid lead like the council member list below, not something a raider can turn off for themselves.
*   **1-100 Random Rolls (à la RCLootCouncil):** Optionally enabled via a setting (raid lead setting). When enabled, every eligible raider automatically rolls a value from 1-100 as soon as an item comes up for vote — shown as its own column in the council panel, purely informational with no automatic effect on the assignment.
*   **Council Vote Counter:** Every row in the council panel has a "CV" button that lets each council member mark their personal favorite; the number next to it shows the total council votes for that player. Purely for guidance — the actual assignment still only happens via right-click → Assign.
*   **Persistent Player Notes:** Via "Edit Note" in the right-click menu, you can attach a permanent note to a player (e.g. "already has BIS trinket"), visible for every item, not just a single one — unlike a raider's per-vote note. It's distributed to all currently online council members and survives reloads.
*   **Armor Type Hint:** Rows for players who can't wear the current item's armor type at all (e.g. plate on a mage) are shown dimmed — purely visual, assigning via right-click still works for any row.
*   **Right-Click Assignment:** Right-clicking a raider row opens a menu with three options — **Assign** (uses the submitted vote as the reason) and **Assign without reason** (handy when nobody wants the item, without polluting the loot history) both award the item; a lock with a confirmation dialog prevents accidental double assignments. **Change Vote** (submenu with all configured vote buttons) is purely cosmetic and awards nothing — it only lets you manually correct a player's displayed vote, e.g. if someone voted via whisper instead of clicking. An assignment does not automatically close its tab — the "×" directly on the tab dismisses only that one item, "No Winner" closes its tab automatically as well, and the "Close" button or the "×" in the top right only minimizes the whole window (all tabs are preserved and reappear on the next item).
*   **Winner Notification:** The chosen player receives a green notification window; the decision is automatically announced in raid/party chat.
*   **Trade Reminder with Auto-Trade:** After an item is assigned to another player, KART remembers who still needs to be traded what, and shows a small, movable reminder window with all pending trades (including a manual checkmark button). If you open a trade window with exactly the right player, the matching item is automatically placed from your bags into the trade window — the trade still has to be confirmed manually.
*   **Auto-Pass:** Optional checkbox – as soon as a loot roll starts, all KART users automatically pass, so nobody accidentally clicks Need/Greed/Transmog while the council is voting. This setting is always purely personal and independent of the minimum item quality.
*   **Raid-Wide Authority:** Voting timer, vote buttons, the council member list, minimum item quality, and the random rolls option always apply raid-wide according to the raid lead's settings — not each individual player's local settings. This prevents someone from, say, adding themselves to the council without authorization or shortening the voting time for their own benefit. Visually set apart in its own box in the options menu, with a live display of the current role ("You are the raid lead" / "Raid lead's settings apply"). Council members, like the Lootmaster above, can each be entered as a character name or an NSRT nickname.
*   **Minimum Item Quality:** Items below the selected quality (default: Epic) don't trigger Loot Council at all — the normal WoW roll window is used instead.
*   **Loot History:** Fully synchronized, searchable log of all assignments (item, player, reason, raid difficulty, timestamp). Filter by player, reason, and item name, plus a button to clear the history. Every KART user automatically keeps the same history — not just the loot master. If someone rejoins a raid after missing a session, clients silently reconcile missing entries via the addon channel, with nothing shown in chat.
*   **Module Toggle:** Loot Council can be fully disabled (e.g. during a testing phase or when conflicting with another loot addon like RCLootCouncil) — no messages from other KART users are processed at all, no auto-pass, no popups.
*   **KART Status Warning:** In the council panel, a red icon per raider indicates that KART wasn't detected, an outdated version is running, or the player has disabled Loot Council locally (details in the tooltip).
*   **Test Mode:** Two test buttons simulate the flow from the looter's perspective (vote list) and from the loot master's perspective (council panel with tabs), independent of your actual raid role — and they work together: a vote cast in the looter test window immediately shows up in the open master test panel, even fully solo without a group. Four real (but consequence-free) items are distributed at once (three weapons plus one trinket, so the two-slot comparison for rings/trinkets gets tested too), so you can also test the behavior with multiple simultaneous drops (vote list and tab bar) — including real item icons, tooltips, armor type hints, and gear comparison. Test rolls stay purely local (no broadcast, no raid chat announcement, no entry in the real loot history, no trade reminder).

### 6. WoWUtils Import
*   Raid compositions can be imported directly from WoWUtils via copy-paste (boss-by-boss format with encounter, difficulty, and invite list).
*   Each imported boss gets its own row with a player count and two buttons:
    *   **Invite:** Invites all players from the boss list who aren't already in the raid (members already present are skipped).
    *   **Remove:** Kicks all current raid members who are NOT on the boss list – ideal for quickly switching between boss compositions.
*   Multiple imports are merged instead of overwritten: if you paste the Normal composition first and then the Heroic one, both difficulties stay in the list at the same time (matched by encounter + difficulty). A **Reset** button (with confirmation) clears the list entirely.
*   **Split Raids:** If you import a second, different roster for the same boss and difficulty (e.g. Team A and Team B for a split), it isn't overwritten but added as its own row, automatically distinguishable as "Boss Name A" / "Boss Name B", etc.
*   The import is saved across sessions and loaded automatically on login.
*   **Module Toggle:** Can be fully disabled if not needed.

### 7. Droptimizer Gains
*   Shows a **Gain** column in the Loot Council panel with each candidate's simulated %DPS/HPS gain from the item currently being rolled, sourced from droptimizer sims already imported into WoWUtils (Raidbots or QE Live).
*   Requires the separate **[KART Companion](https://github.com/Kandera/KART-Companion)** app — a small system-tray tool in its own repository, since WoW addons can't reach the internet on their own. Most raiders don't need it: only one person, typically the loot master/officer, has to run it, since the WoWUtils group key already grants access to the whole roster's sim data.
*   The companion syncs on an interval (or on demand) into a dedicated SavedVariable the addon reads on `/reload` — it never touches your regular settings or loot history.
*   Hover a candidate's small equipped-item icon to see the rolled item and their currently equipped item side by side.
*   **Module Toggle:** Off by default; enable via "Show droptimizer gain % in Loot Council" in the Loot Council settings. Sync status (last synced, player count) is shown in General Settings.

### 8. Customization (Settings)
*   Fully customizable interface (colors, transparency, fonts).
*   Standard-compliant controls: windows and text fields can be closed/deselected with ESC.
*   English and German language support.
*   Access via minimap icon or the Addon Compartment frame.
*   Version checker: check whether all raiders are running the latest KART version (`/kart v`).
*   **Modular Disabling:** Loot Council, Buff Checker, WoWUtils, and Droptimizer Gains can each be individually disabled — handy during testing phases or to save CPU for raiders who don't need certain features.

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/kart` | Opens or closes the main configuration window. |

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
