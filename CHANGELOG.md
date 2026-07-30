**English** | [Deutsch](CHANGELOG-de.md)

# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.2.2] - 2026-07-29
### Fixed
- **Blizzard's own confirmation dialogs work again.** Upgrading an item could be refused outright until you reloaded.
- **KART's own confirmation dialogs are visible again**, instead of opening behind the window that raised them.
- **Tier set tokens go through the Loot Council again**, instead of being rolled on the normal way by nobody.
- **Toys stay out of the Loot Council**, instead of being force-won by the lootmaster.
- **Items show their icon for players whose client had no loot roll of its own**, and their name as soon as the item is known, instead of a question mark all vote long.
- **An item disappears from the vote window of whoever decided it.**
- **Transmog votes are listed above the players who passed.**
- **A player joining or leaving no longer ends the session.**
- **The start prompt can no longer end a session that is already running.**
- **The Lootmaster field stays editable when the lootmaster has left the raid**, so a replacement can be named.
- **Starting a session warns you when no Lootmaster is set**, instead of silently leaving every raider on their own vote buttons and roll setting.
- **A lootmaster who reloads picks the running session back up**, instead of ending it for everyone who asks them about it.
- **Zoning in or reloading restores the session**, without waiting for someone to join or leave the raid first.
- **A raid that leaves the Lootmaster field empty gets a raid-wide config again**, so nobody is left on their own vote buttons and roll setting.
- **The raid config reaches players whose client cannot read Northern Sky nicknames.**
- **A lootmaster who leaves the raid no longer blocks loot distribution for everyone.** The raid leader is offered the role and takes it over on confirmation.
- **Naming a successor in the Lootmaster field is announced to the raid**, instead of leaving everyone pointed at the person who stepped down.
- **A raid leader with an empty Lootmaster field can no longer displace the lootmaster the raid already has.**
- **Closing the start prompt with Escape leaves the question open**, instead of silently meaning "no session" for the rest of the evening.
- **A session that never reached you is asked for again**, rather than once and never.
- **Revoking an award no longer deletes an unrelated award from a previous raid.**
- **An item whose data is slow to arrive is waited for**, instead of being skipped without a word.
- **A raid leader who distributes loot without a named Lootmaster keeps control of the raid-wide settings**, instead of losing it the moment they send them.
- **Handing the Lootmaster role over reaches the raid again.**
- **Someone joining later gets the whole loot history**, instead of losing one of two identical items awarded to the same player.
- **A lootmaster who reloads gets the session back even when no council member is there to tell them**, instead of force-winning nothing for the rest of the evening.
- **A client that lost the session asks for it back sooner**, and keeps asking on every roster change instead of giving up after the first round of tries.
- **Anyone joining after the Lootmaster has left still gets the raid's vote buttons, minimum quality and roll setting**, instead of quietly falling back to their own.
- **A raid leader who reloads no longer replaces the raid's settings with their own**, which used to leave half the raid on different vote buttons and no rolls.
- **The session is confirmed by any raider who knows**, not only by the one client running the loot flow.
- **An item that dropped while your client was reloading still reaches you**, so you can answer it and the council is not left waiting.
- **End Round clears the round for the whole raid**, not just for whoever pressed it. (#15)

## [3.2.1] - 2026-07-29
### Fixed
- **The two irrelevant-item switches keep their state after a reload**, instead of showing themselves as off while still taking effect.
- **Both switches follow a language change** like every other setting.

## [3.2.0] - 2026-07-28
### Added
- **Items your class cannot equip can now be hidden from the vote window.** They are answered with your last configured response automatically, so the council is not left waiting.
- **KART can vote Transmog for you on items you cannot equip but whose appearance you still need.**
- **A fixed Transmog button is now always the last vote response.** Freely configurable labels drop from six to five.

## [3.1.1] - 2026-07-28
### Fixed
- **Window and button borders draw solid at every UI scale**, instead of breaking into pieces on an interface scaled for a larger screen.

## [3.1.0] - 2026-07-28
### Added
- **`/kart status` prints the Loot Council state your own client is actually using** — lootmaster, council, rolls and vote buttons.
- **The Loot Council windows have their own scale and layer setting**, independent of the rest of the addon.

### Changed
- **Slider values can be typed in**, not only dragged.
- **A KART window comes to the front when you click it**, so two overlapping windows can be reordered.
- **The ready-check reason prompt is offered in raids only**, no longer before every Mythic+ pull.

### Fixed
- **The raid's Loot Council settings now reach everyone.** A raider whose client could not read the lootmaster's nickname silently kept their own vote buttons, roll setting and council list — so their votes showed up under the wrong label and they never rolled.
- **A rejected raid config says so** instead of failing in silence.
- **A vote carries the button it was cast on.** Two clients with different button lists no longer show each other the wrong choice.
- **An oversized council config is refused instead of sent truncated**, which used to leave the whole raid on stale settings.
- **Alone, you can be your own lootmaster again** — the loot-owner controls stay usable outside a group.
- **Raiders see the Loot Council settings actually in force**, not their own unsent ones.
- **The peer status marker refreshes** instead of freezing on its first reading.
- **Gear and durability data is dropped for players who left the group.**
- **Two identical items awarded seconds apart record two history entries**, not one.
- **The data responders are rate-limited and Refresh is debounced**, so one click no longer floods the raid.
- **Background opacity reaches the Loot Council windows.**
- **The item tooltip covers the whole icon in the vote window.** (#7, #8)
- **A council tab no longer closes when you meant to switch to it.** (#9)
- **The WoW Utils paste box takes focus over its whole height.**
- **Auto-Promote matches a cross-realm name in either spelling.**
- **The minimap icon stays switched off** across a reload and a new session.
- **A confirm dialog always opens in front of the window that raised it**, whatever layer the windows are set to.
- **A widget built after the last restyle uses the chosen font** instead of Blizzard's default.
- **`/kart v` counts replies only**, not silent clients.
- **A setting changed by a profile switch now takes effect** instead of being stored and ignored.

## [3.0.2] - 2026-07-27
### Fixed
- **The extended ready check works again.** Declining a ready check offers the reason buttons and the free-text box.
- **The Buff Checker keeps the ready-check result and the reasons after the check ends**, instead of clearing both at the moment they become useful.

### Added
- **The reason prompt can be switched off** under Raidlead Tools, for anyone who would rather just decline.

## [3.0.1] - 2026-07-27
### Changed
- **"Close Session" is now "End Round".** It clears the current round for everyone without turning off the whole Loot Council session.
- **The Loot Council font-size slider moved to the personal-settings card**, next to the other personal display options.

### Fixed
- **Hovering the red "!" warning icon on a council row now shows what it means.**
- **Loot Council settings (button labels, minimum quality, council list) now reach every raider in a freshly-formed group, even before NSRT has synced the lootmaster's nickname.**

## [3.0.0] - 2026-07-27
### Changed
- **Version check rebuilt.** Clients on 2.9 or older no longer appear in the list until they update.
- **This release includes a large internal rework.** Everything you've saved carries over — settings, loot history, officer notes, profiles and outstanding trades.

### Fixed
- **`/kart add` works with shift-clicked items again.**
- **The window close button is bigger and easier to click.**
- **Loot Council windows now follow the font setting.**

## [2.9.0] - 2026-07-25
### Added
- **The whole UI now follows the language setting** — main window, settings and tooltips included.
- **Council members can now cast their own loot vote.**
- **Loot history is now paginated.**
- **The council panel now shows what each candidate has equipped** in the dropped item's slot, with the item-level difference.
- **The Vantus rune is now detected by spell**, not by buff name.
- **The Buff-Checker now flags outdated enchants**, not just missing ones — the tooltip names the slot carrying the wrong one. Only the top craft quality counts.
- **Off-rank weapon oil is now shown as wrong** — the current oils and sharpening stones count as good, and shaman weapon imbues are not nagged about.
- **`/kart add <item link>` hands an item back to Loot Council for a decision**, without needing a real loot roll. Re-adding an already-awarded item revokes that award first.
- **Click a name in the trade reminder to target and open a trade with them** (range-checked).
- **A new reminder window tells you when you still need to trade the lootmaster** for something you won, with the same one-click trade.
- **The vote timer can now be set up to 3 minutes**, up from 1.
- **The Loot Council windows have their own font-size setting**, and it now actually applies to everything in them.
- **Trade completion is now confirmed directly**, not just inferred from your bags.
- **You'll be warned if you trade an assigned item to the wrong person.**
- **You'll be warned before a pending trade's 4-hour tradeable window runs out** — the timer keeps counting while you're offline.
- **When the same item drops twice at once, each one is now marked "(1/2)"/"(2/2)"** so you can tell them apart.
- **Choose what happens to an item in your vote window once you've voted on it**: stay full-size (default), shrink, or hide completely. New setting in Loot Council settings.
- **`/kart showall`** brings back any items hidden by that setting.
- **`/kart owed`** reopens the list of items you're still owed.
- **`/kart ench`** prints your own enchant ids, for keeping the enchant check current.

### Changed
- **Both weapons are now checked for oil** — a dual wielder with only one oiled weapon is flagged, while an empty off-hand or a shield is not asked for one.
- **Trade reminders and owed items now survive a reload or relog.**
- **New "Close Session" button in the council panel** ends the session and clears every open item at once. Lootmaster only.
- **Only the configured lootmaster sets the raid's Loot Council config** — passing raid lead no longer overwrites it. Use the Sync button to hand the settings over.
- **Mounts, pets, toys, housing items and Bind-on-Equip drops never go through Loot Council** — they are rolled the normal way and Auto-Pass leaves them alone.
- **The lootmaster now runs the whole loot flow** — session, rolls and awards. The raid leader only stands in while no lootmaster is set.
- **Internal cleanup:** dead code removed, duplicated logic consolidated, addon-message handling restructured.

### Fixed
- **The Buff-Checker now checks the off-hand enchant** on a second weapon — shields and caster off-hands take none.
- **A buff that merely has "oil" in its name no longer triggers a false oil warning.**
- **Items added with `/kart add` now roll like a normal drop** — the council's Roll column stayed empty for them.
- **Re-adding an awarded item now frees it even after its council tab was closed**, which is when it usually happens.
- **Binding a key already used by another Raidlead action now takes it from that action**, instead of both showing it and only one working.
- **Names and nicknames with accents now match** wherever umlauts already did.
- **A one-hand drop now compares against the candidate's weapon**, not against their shield or off-hand.
- **The council's equipped-item column no longer trusts a broken reply** from another raider.
- **A closed trade or owed reminder stays closed** when an entry is cleared — only winning something new reopens it.
- **"No Winner" now also removes the item from loot history**, instead of leaving it credited to the revoked winner.
- **An item with two sockets now reports both empty ones**, not just one.
- **Starting a session now reaches the raid when the lootmaster isn't the raid leader** — including for anyone joining later.
- **A raid leader reloading mid-raid no longer stops the raid's vote windows** while items keep being won.
- **The winner's row turns gold right away** for whoever assigned the item, not only for everyone else.
- **The Loot Council settings tab no longer breaks on login.**
- **The lootmaster works again when they aren't also the raid leader** — winning rolls, `/kart add`, trade reminders, the council panel and Close Session were all dead for them.
- **The lootmaster no longer has to be listed as a council member** to get the council panel and have their awards count.
- **A mount whose data hasn't loaded yet no longer slips into Loot Council.**
- **The council panel no longer warns that you are missing KART** on your own row.
- **A decided item keeps its council tab on every client**, not just on the one who assigned it.
- **Vote notes and officer notes can no longer smuggle colour codes or links** into other people's tooltips.
- **The council panel no longer stutters while loot is being handled.**
- **The "you're owed this" timer now starts when the item drops**, not when the council decides.
- **The raid-wide settings box now says correctly whether your settings apply to the raid** — and how to get them there when they don't.
- **The Buff-Checker no longer errors on a broken gear reply** from another raider.
- **Cancelling the accent-colour picker restores the exact colour you had**, and picking one no longer darkens it slightly.
- **Gear, item level and ready-check sync works again for everyone on your own realm.**
- **A late raid join no longer wipes the whole raid's in-progress loot rolls.**
- **Revoking a winner now clears the trade reminder everywhere**, including for whoever revoked it.
- **A raid's loot state no longer carries over** into the next raid or the next session.
- **The Loot History button at the bottom of the Loot Council tab is reachable again.**
- **Minimizing the council panel no longer makes it jump** across the screen.
- **Closing a council tab no longer re-opens the vote window** or leaves a stuck entry in it.
- **The Buff-Checker settings preview no longer disappears** while you adjust the sliders.
- **Window opacity no longer resets itself** when you reopen the window.
- **The Raidlead bar no longer appears mid-fight** after a reload.
- **Switching profiles now applies the auto combat log settings.**
- **Importing a boss list no longer duplicates it** — neither on re-import nor after logging in.
- **Reset now asks for confirmation** before clearing all settings.
- **Rolls are no longer lost** for raiders who weren't eligible for the item.
- **Gear, item level and ready-check data can no longer be requested or spoofed** by players outside your group.
- **The boss list now follows the active profile** instead of stacking up, and a reset survives a reload.
- **Empty gem sockets now name the right slot** — gloves, belt, trinkets and cloak included.
- **A minimized council panel stays minimized** while votes come in.
- **Auto combat log no longer keeps running** after a reload mid-raid.
- **Raidlead bar keybinds are released** when the bar is hidden or disabled.
- **Windows saved off-screen now come back on-screen** — Buff-Check, Raidlead bar and the council windows.
- **Loot history is no longer sent to players outside your group.**
- **Officer note tooltips now show on hover again.**
- **"No winner" now clears the item for the whole council**, not just whoever clicked it.
- **Manual rolls and loot results are no longer occasionally dropped** right after someone joins the raid.
- **Equipped-item comparison no longer breaks** for very long item links.
- **Auto combat log no longer stops a log you started yourself.**
- **Long names with umlauts no longer render broken** in the buff check.
- **Remove-for-boss no longer risks kicking yourself** from a raid.
- **Bulk-inviting a full boss roster while solo now converts to a raid** so every invite lands.
- **Droptimizer gains now show for players on multi-word or apostrophe realms.**
- **Pull-timer and buff-check keybinds now trigger reliably.**
- **Bulk invite and remove now match names correctly on German realms.**
- **No more phantom "you're owed an item" reminder** when no lootmaster is set.
- **A sixth custom vote button no longer shows the Pass icon.**
- **Bulk WoWUtils invites now auto-convert to a raid** so rosters over five actually fill up.
- **Loot history player filter now groups a person's entries together** even across a nickname and a character name.
- **Skyfury now detects correctly on German clients.**
- **Vote window no longer shows a blank badge** when the leader shortens the vote buttons after you've voted.
- **Profiles now keep newer default settings** when loaded.
- **Fixed a login error** for characters that never touched the Loot Council font-size slider.
- **Durability data now loads automatically on ready checks.**
- **Reset Defaults now resets everything**, including window positions and keybinds.
- **Assign menu and equip tooltip now show nicknames** when that setting is on, instead of always the short name.
- **Loot Council is now explicitly raid-only.**
- **Session, roll-start and history-sync messages are now sender-verified.**
- **Fixed auto-trade for cross-realm winners.**
- **Minimap icon position now saves correctly after switching profiles.**
- **Raid-marker bar buttons no longer fire twice per click.**
- **Fixed a leftover checkmark button when clearing trade reminders.**
- **Loot history no longer duplicates entries across German and English clients**, and difficulty is now recorded consistently in English.
- **Ranged and one-hand weapons now show the equipped item** in the council panel.
- **Keybinds now apply after a reload or login during combat.**
- **The settings search now scrolls to the matched setting.**
- **Battle.net whisper invites now actually invite** the whispering friend.
- **Auto-convert to raid now triggers with a full 5-player party.**
- **Manual rolls after a `/reload` no longer show a stale item.**
- **The "you still need to collect" reminder now clears on reassignment** and no longer stacks duplicates.
- **Clicking a trade partner during combat no longer wrongly reports "out of range".**
- **Both copies of a duplicated drop are now auto-placed into the trade.**
- **Peers are only flagged as outdated when actually on an older version.**
- **History search now finds items whose names start with an umlaut.**
- **Buff-check reports now list the correct missing players.**
- **Raid assistants can now remove players for a boss**, matching invite.
- **Uninvite now targets the correct character** when two share a name across realms.
- **The Loot Council font-size slider no longer overlaps the rolls checkbox.**
- **Ready-check and buff-check windows no longer close early** when triggered again in quick succession.
- **Keybind capture no longer sticks on the wrong button** or resumes after the window closes.
- **Droptimizer now picks the correct upgrade track** when an item was simmed at several.
- **Officer notes no longer grow without bound.**
- **Well-fed food buffs are now detected on German clients.**
- **Player names with umlauts now resolve** for council, lootmaster and auto-promote.
- **Loot won by a late-joining council member no longer logs as "???".**
- **The council straw-poll bar now fills correctly.**
- **Settings sliders now show their value right away** instead of staying blank until first dragged.
- **Loading a profile now applies its saved language.**
- **Loot Council no longer confuses two players who share a character name across connected realms.** Votes, council membership, item assignments, and officer notes are now tracked per player.
- **Loot Council session state (session on/off, min-quality, vote labels, opt-in rolls) now syncs immediately when you join or `/reload`**, instead of only updating on the next roster change.
- **The designated lootmaster's auto-Need/Greed now also claims Transmog-only rolls**, instead of doing nothing.
- **Right-click assignment and the loot-history log no longer confuse items across bosses**, and a reassigned item replaces its old history entry instead of duplicating it.
- **Freshly-dropped loot no longer gets stuck showing "???"** in the vote window or council panel.
- **The Auto-Trade reminder now tracks correctly when the raid leader isn't the designated lootmaster**, and only clears an entry once the trade actually completes.
- **The Loot Council and Auto-Trade windows can be reopened with `/kart lc` and `/kart trade`** after closing them.
- **The Council Panel and Loot History windows can now be dragged by their title bar**, not just the body.
- **Toys, pets, mounts, and housing decor are no longer filtered out by the minimum-quality rule.**
- **The vote window's close button is bigger and easier to click.**
- **A player's KART status no longer falsely shows "not installed" right after joining.**

## [2.4.0] - 2026-07-19
### Added
- **Settings search:** a new Search button on the main window lets you type a setting's name and jump straight to it — correct tab, scrolled into view, briefly highlighted.

## [2.3.0] - 2026-07-19
### Added
- **Raidlead-Only Settings Sync:** send your Loot Council raid-wide settings to a specific player by name from the Loot Council tab — they see a confirmation popup and must accept before anything changes.

## [2.2.0] - 2026-07-19
### Added
- **Settings Profiles:** save your current settings as a named profile, switch between saved profiles, and delete them from a new card on the Settings tab.

## [2.1.0] - 2026-07-19
### Added
- **Keybinds for Ready Check, Clear World Markers, Pull Timer, and Buff-Checker Toggle:** set in a new Keybinds card on the Raidlead tab.

## [2.0.0] - 2026-07-18
### Changed
- **Main window redesigned with a full artwork background** — sidebar, title and close button are part of the new look.
- **Free window resizing replaced by a "Window Scale" slider in Settings.**
- **Main window is larger by default and every tab groups its settings into cards.**
- **Settings labels now use the same white text style as the menu.**
- **Input fields restyled to match the card look** — rounded, with an accent-colored border while typing.
- **Buff-Checker window redesigned with its own artwork background** — accent header line, matching close and resize corners.
- **Loot History, vote window, council panel and all smaller dialogs share the new artwork look.**

### Removed
- **Background color and title font size settings.**

## [1.19.0] - 2026-07-18
### Added
- **Auto Combat Log:** new Automation tab card starts/stops combat logging automatically for selected content (raid difficulties, Mythic+ with minimum key level, dungeons, Delves).

### Changed
- **Settings tab moved to the bottom of the sidebar.**

### Fixed
- **"Show NSRT nicknames" and "Compact vote window" toggles no longer show as off after a reload.**

## [1.18.1] - 2026-07-18
### Fixed
- **Minimap button no longer black:** the minimap and AddOn-compartment icons still pointed to the old JPG file after the PNG switch (WoW can't load JPG textures). Both now use the PNG.
- **Pull timer and Clear World Markers now work for everyone:** the Raidlead Bar buttons used the `/pull` command (only exists with BigWigs/DBM installed) and `/cwm all` (the "all" keyword is localized, so it failed on non-English clients). The pull button now starts the native WoW countdown and the clear button removes each marker by number, so both work regardless of installed addons or client language.

## [1.18.0] - 2026-07-18
### Added
- **Guild logo in the title bar:** the KA logo now appears next to the main window's title. The logo was also converted from JPG to PNG, fixing the addon icon in the game's AddOns list (WoW can't load JPG textures).
- **Configurable window layer:** a new "Window Layer" slider in Settings controls which UI layer (frame strata) all KART windows are drawn on — raise it above other UI or keep the addon in the background. Confirmation popups always sit one layer above so they can't get buried.

### Changed
- **Design-Updates:** modernized look across every window — rounded corners, refreshed buttons, checkboxes, and sliders.

## [1.17.0] - 2026-07-17
### Added
- **Droptimizer gain% now shown in the Vote window too:** each item card in your personal vote popup shows your own synced Droptimizer gain% for that item (colour-coded, same as the Loot Council panel's Gain column) whenever sim data exists for it — no more switching to the council panel just to check if an item is actually an upgrade for you before voting.

## [1.16.1] - 2026-07-15
### Fixed
- **Advanced-tab gem check no longer reports false positives:** it relied on `C_Item.GetItemStats`, which can keep reporting an `EMPTY_SOCKET_*` stat for an item that was already gemmed earlier in the session (its cached item link predates the gem). The check now reads the socket state from a hidden tooltip scan instead, matching exactly what you see when hovering the item, so already-gemmed pieces are no longer counted as missing.

## [1.16.0] - 2026-07-15
### Added
- **Northern Sky Raid Tools nickname support:** the Lootmaster field, the additional council members list, and the Auto-Promote name list now all accept an NSRT nickname in addition to a character short name. Naming a nickname (e.g. "Kandera") applies to every character sharing that nickname, so it keeps working automatically when that person switches alts — no manual re-typing needed. Falls back to plain character-name matching for anyone without NSRT installed or without a nickname set. Requires Northern Sky Raid Tools to be installed; KART never bundles its own nickname system.
- **Show NSRT nicknames in the Loot Council panel:** a new personal settings checkbox displays each candidate's NSRT nickname instead of their character name in the council/lootmaster panel. Off by default; falls back to the character name automatically wherever no nickname is available.
- **Guild Rank column in the Loot Council panel:** a new column right after the player name shows each candidate's guild rank, making it easier to spot which raiders are alts of the same player.

## [1.15.0] - 2026-07-15
### Added
- **Loot Council vote window layout options:** Choose between two layouts with a new settings checkbox: "Spacious" (new default) shows a wider window with larger vote cards and a colored quality-tinted accent strip per item; "Compact" uses single-line rows with icon-only vote-chip buttons for a smaller footprint. Your preference is saved per character.

## [1.14.0] - 2026-07-14
### Added
- **Raid-leader-assigned Lootmaster:** a new field in Loot Council settings lets the raid leader designate one player who must win every roll (Need, or Greed/Disenchant if Need isn't available) instead of passing, so they can physically receive each item and trade it out to whoever the council actually picked. This overrides that player's own Auto-Pass setting — it's synced from the raid leader like the council member list, not a personal toggle anyone can turn off for themselves.

## [1.13.0] - 2026-07-14
### Added
- **Loot Council panel can now be minimized:** a new "-" button next to the close button collapses the panel down to just its header and item name, so it can stay on screen during normal raiding without the full candidate list in the way. Tabs, votes, and everything else stay tracked while minimized, and the panel automatically expands again the moment a genuinely new item starts a roll, so nothing gets missed.
- **Visual refresh for both Loot Council windows:** vote buttons and council rows now show a small icon per vote category (Blizzard's own default group-loot icons, not custom art) alongside their existing colour-coding; the currently-rolled item's icon gets a quality-tinted accent border and a native radial countdown wipe (the same `Cooldown` widget every ability button already uses); council rows show a round class icon, an ilvl +/- delta against the rolled item, and roll values ≥85 get a gold glow; the council-vote tally button now fills proportionally instead of showing a bare number; the active tab gets a gold accent glow; and the vote popup shows a running "X/Y voted" count next to its timer.

### Changed
- **Loot Council panel is noticeably wider:** name and vote columns were clipping or wrapping real player names and vote labels at the old fixed width — that no longer happens, even with the new icon columns added.
- **The winning candidate's row is now highlighted gold instead of green:** green is also the "Upgrade" vote colour, so a row could end up ambiguously both at once; gold doesn't collide with any vote category.
- **A raider's own note is now still visible after voting, not just before:** the vote popup used to hide the note the moment you voted; the "you voted" badge now shows it alongside the chosen category (truncated if long) instead of discarding it from view.
- **Council row tooltips are more targeted:** hovering the equipped-item icon (item comparison) no longer also shows the raider's note or officer note — those now have their own dedicated tooltip on the note/officer-note icons themselves, so a routine gear comparison doesn't dump someone's comment into view every time. Hovering an item tab in the left-edge strip no longer triggers Blizzard's own gear-comparison tooltip either — not useful there, only "which item is this" is.

### Fixed
- **The council panel's minimize button overlapped the header timer/"Done" text:** the timer was anchored with a hardcoded offset from the window edge that didn't account for the new minimize button; it's now anchored to the button itself instead.

## [1.12.5] - 2026-07-14
### Security
- **Loot Council no longer trusts unverified senders for config, results, and officer notes:** Three addon-message handlers accepted their payload from any sender without checking who actually sent it — a forged `LC_CONFIG` broadcast could add the sender's own name to the council list on every client, a forged loot result could write a fake entry into everyone's loot history and pop a false "You Win" popup, and a forged officer note could overwrite any player's note with no authorization at all. All three now verify the sender is the actual current raid/party leader (config) or a council member (results, officer notes) against the live roster before acting, which also closes the whisper vector since a sender who isn't in your group can never pass that check.

### Fixed
- **Version-check replies sent via whisper never arrived:** `SendAddonMessage` requires an explicit whisper target that the reply wasn't passing; whispering a version request to someone now actually gets an answer back.
- **Missing gem sockets were only detected on English/German clients:** The gear-check's empty-socket detection matched tooltip text in specific languages instead of reading item stats directly, so it silently under-reported missing gems on every other supported locale. Now locale-independent.
- **A malformed Droptimizer cache entry could break the entire Loot Council candidate list:** Gain %/item level values synced from the external KART Companion app weren't checked to actually be numbers before use; a bad entry now gets skipped instead of erroring out the whole row list.
- **A loot history entry with a missing timestamp could stop the history list from refreshing:** Added the same fallback already used elsewhere in the file for this case.
- **Buff-Checker player names could visually run into the ready-check reason icon:** The name column had a fixed pixel width that didn't account for a larger content font size (adjustable in Settings) or long name-realm strings — WoW doesn't clip text that overflows a FontString's set width on its own. Overly long names are now truncated with "…" to always fit the column.
- **A Loot Council candidate's equipped-ilvl and armor-eligibility columns could stay blank for a whole roll:** Freshly-dropped items are often not yet cached client-side, and nothing retried once the data actually loaded. The panel now loads the missing item data in the background and refreshes automatically once it's available.
- **A redelivered loot result could log the same win twice in Loot History:** Added a short dedup window, matching the safeguard the history catch-up sync already had.

### Changed
- **A raid leader's Loot Council config with a very long council member list is now truncated instead of risking silent corruption:** Vote-button labels plus a long council list could together exceed the addon-message size limit, which could make other clients silently fail to apply the config at all. It's now trimmed to whatever fits, with a warning printed to the leader so they know to shorten it.
- **Visual polish pass:** The main window and Buff-Checker now fade in smoothly instead of popping in instantly, panel backgrounds have a subtle gradient instead of being perfectly flat (derived from your existing background color, so custom themes still apply), and the Loot History / Loot Council close buttons now respect your chosen UI font instead of always using the default Blizzard font.

## [1.12.1] - 2026-07-13
### Changed
- **Droptimizer Gains no longer has its own settings tab:** The "Show droptimizer gain % in Loot Council" toggle moved into Loot Council's settings (next to Auto-Pass), and the sync status (last synced, player count) moved into General Settings — one less tab to hunt through for two settings that logically belong to the features they affect.

## [1.12.0] - 2026-07-13
### Added
- **Loot History can now be exported as JSON:** A new "Export JSON" button in the Loot History window opens a copyable JSON dump of the currently filtered entries, using the same field set/order as RCLootCouncil's own "Standard JSON output" export, so it can be pasted into any tool built to read an RCLootCouncil export. KART doesn't track everything RCLootCouncil does (boss, instance name, vote counts, replaced-gear links, assigning loot master), so those fields are exported empty/zeroed rather than fabricated.
- **Droptimizer gain % in Loot Council:** A new "Gain" column in the Loot Council panel shows each candidate's simulated %DPS/HPS gain from the item currently being rolled, sourced from droptimizer sims they've already imported into WoWUtils (Raidbots or QE Live). This requires the new [**KART Companion**](https://github.com/Kandera/KART-Companion) app (a separate, standalone project — a system-tray tool most users won't need) running on an officer's PC, since the addon itself has no way to reach the internet; the companion syncs the data into a new SavedVariable the addon reads on `/reload`. New "Show droptimizer gain % in Loot Council" toggle (off by default) in the new Droptimizer settings tab.

### Fixed
- **Loot Council row hover showed an item-comparison tooltip everywhere, not just over the equipped-item icon:** Blizzard's own tooltip system also auto-compares any item shown in a `GameTooltip` against your own equipped gear, which fought with the addon's own (different) comparison against the raid candidate's gear and made it show up on almost any mouse movement over a row, obscuring the Roll/CV/Gain columns. Tooltips now only appear while hovering the small equipped-item icon, and show the rolled item and that candidate's equipped item side by side via a dedicated tooltip frame instead of Blizzard's shared one.

## [1.11.1] - 2026-07-13
### Changed
- **Declared compatibility with retail patch 12.1:** Added Interface version `120100` to the TOC.

### Fixed
- **Loot Council tab close button ("×") was unclickable and flickered on hover:** The close button is a child frame stacked on top of the tab, so moving the mouse onto it also fired the tab's own `OnLeave` (WoW's mouse focus only tracks the topmost frame, not parent frames). That immediately hid the button, which put the mouse back over the tab, re-triggering `OnEnter` and re-showing it — an infinite show/hide loop that also swallowed every click before it could register. The button now stays visible as long as the mouse is over either the tab or the button itself, and the tooltip hides instead of fighting the button for space.
- **Trade reminder rows showed a tofu box instead of an arrow:** `"%s → %s"` used a Unicode arrow character not covered by WoW's default game fonts, so it rendered as an empty box between the item and the winner's name — the same class of bug already worked around for the checkmark icon. Replaced with a plain ASCII `->`.

## [1.11.0] - 2026-07-09
### Added
- **Guild-chat auto-invite can now be turned off separately:** The keyword-invite feature (e.g. typing "inv" or "+") worked in both whispers and guild chat, which could lead to accidental invites from casual guild chat conversation. A new checkbox ("Allow auto-invite via Guild chat") in Automation settings lets you disable the guild-chat trigger while keeping whisper-based invites active.

### Changed
- **Several defaults for fresh installations have been adjusted:** Guild-chat auto-invite, the Buff-Checker module, Loot Council, WoWUtils Import, Auto-Raid-Convert, and the Raidlead Bar's auto-hide-when-solo now default to **off**; Loot Council's Auto-Pass now defaults to **on**. This only affects new installs and "Reset Defaults" — existing configurations are not changed.

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
