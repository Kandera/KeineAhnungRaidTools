# Backlog — known defects, not scheduled

Defects found while working through the v3.0.0 library extraction and the raids after it, each with
a traced cause rather than a guess. This file exists so the diagnosis is not redone from scratch.

Companion to `MANIFEST.md` (the core functions and the 10-out-of-10 standard they are held to) and to
`REVIEW-DECISIONS.md`, which records findings deliberately **not** changed. This file
records findings that *should* change, eventually. An entry is deleted once it is fixed — the code
and its comments carry the diagnosis from then on, and `git log --grep=Bnn` finds the commit.

**2026-07-27:** B1 (shift-clicked items) and B5 (small close button) were fixed and removed.

**2026-07-28:** B2 (the font setting not reaching some widgets) was removed. Its Loot Council and
Loot History halves were fixed; the remaining half — the sidebar tabs and the Language/Accent
Colour/Reset Defaults/Profile buttons — was measured in-game and does not reproduce. Wrapping
`ApplyStyle` showed it receiving the newly chosen font path on every dropdown click, and comparing
`GetFont()` across the whole `buttonTexts` registry under a deliberately distinctive font returned
zero widgets differing from the reference. Do not re-open without a fresh reproduction.

**2026-07-28:** B4 (the minimap toggle leaving the button behind) was fixed and removed. The cause
was not the `Show`/`Hide` pair it was filed against: LibDBIcon keeps its own `hide` flag inside the
saved table it is registered with, and both `Register` and `Refresh` decide visibility from that flag
alone. KART never wrote it, so the `Refresh` call at the end of `KART.UpdateMinimapButton` undid the
`Hide` two lines above it, and every login re-showed the icon regardless of the checkbox.

Ruled out while diagnosing, and worth not re-deriving: the *invisible but still clickable* button
reported alongside this is `EllesmereUIMinimap`, which reparents every LibDBIcon button into a flyout
panel and holds it at alpha 0 while that panel is collapsed. Not a KART defect, and not fixable from
our side.

**2026-07-28:** B8 (Blizzard confirm dialogs buried under KART windows) was fixed and removed.
`RegisterStaticPopup` now lifts the popup frame on show and restores it on hide. It lifts to
`TOOLTIP` rather than `GetDialogStrata()` on purpose: the Loot Council windows carry their own
stratum setting since B22, so one-above-the-shared-setting would still land under them.

**2026-07-28:** everything else that was still open — B3, B6, B7, B9 through B22, and B24 through
B28 — was fixed for the 3.1.0 release and removed. Each fix names its number in the commit subject
or body.

**2026-07-29:** B23 (button borders incomplete at 1080p) was fixed and removed, confirmed in-game by
the reporter. The border *width* is snapped to whole physical pixels; child *positions* are not, so
on a client whose UI scale does not match its resolution an edge can still read as soft rather than
broken. That limitation was stated in GitHub issue #5 when it was closed.

**2026-07-29:** a five-agent read-only review swept the whole Loot Council after one raid evening
turned up three defects. Everything it found is below, ordered by what it costs the raid rather than
by where it lives. Five entries were fixed the same evening and never got a number: the locked
Lootmaster field, the session prompt ending a live session, two bare `IsInRaid()` calls, the latched
lootmaster-clash warning, and `StartTest` missing `equipRequestedRolls`.

Ten entries below carried an **[opt-in]** marker while the two relevance switches
(`lcHideIrrelevant`, `lcAutoTransmogVote`) were held off in the options: B36 to B39, B41, B42, B49 to
B51 and B54. All ten are fixed and both switches are available again as of 2026-08-01, so the marker
is gone. Until that pass the feature had never executed in a test at all -- `RegisterEvent` was a
no-op in the harness, so its own frame never received START_LOOT_ROLL.

## Reading this file

**Every heading carries its own status**, so "what is still open?" is one look at the headings and
never a read of the bodies. Anything without one of these words is open:

| in the heading | means |
|---|---|
| `FIXED` | done, with the date and the tests that hold it |
| `NARROWED` | the entry overstated it; what is left is written down |
| `DISSOLVED` / `SUPERSEDED` | the situation it describes cannot arise any more, usually because a rule changed underneath it. Kept as history -- each one is a failure this guild paid for, and the rules exist to make them unreachable rather than merely patched |
| `MITIGATED` | not fixable here; the damage is reduced and the real fix is named |
| `OPEN, by choice` | measured, understood, and deliberately left -- the reasoning and the options are in the entry |
| `NO DEFECT` | looked for, measured, nothing there. Kept because the absence is itself a result -- and because the next person to wonder should find the measurement rather than repeat it |

Keep it that way. A status that lives only in the body reads as open to anybody scanning, which is
exactly how B64 and B70 kept coming back up after they had stopped being real.

---

# Tier 0 — reopened and unresolved

## B81 — FIXED 2026-08-01 — a reload lost the open items, and worst for the one client that must not lose them

Found in the live v3.2.2-beta1 test, 2026-07-31, first as "`/kart add` items are gone after a
reload". Measured afterwards, and it is **not** specific to `/kart add`. One real drop, then one
client reloads:

```
Bramor  (raid lead AND lootmaster)   1 roll -> 0    catch-ups sent to them: 0
Merrit  (council, not lootmaster)    1 roll -> 1    recovered
Alric   (plain raider)               1 roll -> 0    catch-up sent, not applied
```

### The lootmaster's case, which is the maintainer's own

`LC.SendOpenRolls` opens with `if not (... and LC.IsLootOwner()) then return end`, and says so:
*"Last, and only from the loot owner: the items still on the table."* One broadcaster, which is the
right rule for announcing — but the catch-up is a REPLY, and the client that most needs one is the
loot owner coming back from a reload. Nobody is allowed to answer them, so nothing does.

That is the exact shape reported: raid lead and lootmaster in one person, two items on the table,
reload, `/kart lc` opens nothing while `/kart status` correctly says the session is running. They
force-win nothing from that point on and every peer still shows both items.

### `/kart add` on top

A real drop at least has a recovery path when somebody else is the loot owner: `HandleRollCatchup`
proves entitlement by asking Blizzard for the roll. A manually added item has no Blizzard roll behind
it -- that is the point of `/kart add` -- so it can never be restored that way even in principle, and
nothing persists it (`KART_LCTrades` holds decided trades, `KART_LootHistory` holds awards).

### Not yet explained

The plain raider was SENT a catch-up and did not apply it. Measure that before fixing anything --
guessing at it is how three attempts were wasted on B70.

### The shape a fix would have

Peers other than the loot owner must be able to answer a state request with the open rolls, and
`LC_MANUAL_START` (`LC.HandleManualStart`, no Blizzard-roll requirement) is the existing token for
the manual half.

The open question is the one the Blizzard check answers for free today: **a state request is also
what a late JOINER sends**, and a late arrival must not be pulled into a distribution already
running. Real rolls tell the two apart by asking Blizzard; manual rolls have nothing to ask. That is
a rule decision, not a patch.

## B80 — OPEN, by choice — the raid leader is not in the council list

Reported from the live v3.2.2-beta1 test, 2026-07-31, and explicitly NOT blocking the guild release:
the workaround is to put yourself in the list, which takes one edit.

`LC.IsCouncil` and `LC.IsSenderCouncil` read `LC.CouncilNamesTable`, which is built from the config's
council list and nothing else. The raid leader owns the config (`docs/OWNERSHIP.md`) but is not
implied by it, so a leader who designates somebody else as lootmaster and does not name themselves
sits outside the council: no panel, and their own awards would be rejected by everybody.

**Maintainer's call, 2026-08-01: no rule. The council list stays the only source.** Whoever decides
is written in it, the raid leader included. The alternative was a second implicit special case next
to the loot owner's, and it would have taken the choice away from a raid leader who deliberately
does not want to vote on the loot they are leading for. One edit in a field they already own is the
better trade.

So this is not a defect in the code, and nothing about it goes into `docs/OWNERSHIP.md` — the
document already says the council list is the raid leader's to set.

## B83 — FIXED 2026-08-01 — a relevance switch reopened a window holding only test rolls

Found in the bug run for B36-B54, and introduced by B50's own fix. Widening the switch callbacks to
reach a hidden window is right for LIVE rolls -- the hiding is what emptied it -- but it also reached
a window holding nothing but `/kart test` items. LC.Relevance exempts test rolls outright, so neither
switch can change anything about them, and putting the window back over them is exactly what
`Vote.RefreshVoteListRowsIfShown` exists to prevent.

## B84 — FIXED 2026-08-01 — re-answering an item re-broadcast an unchanged vote

Also from the bug run, also in B50's fix. Flipping a switch mid-boss reconsiders every item on screen
at once, and most come out the same way -- so one toggle sent the council a burst of LC_VOTE messages
saying what it already knew. That is the shape Blizzard's chat throttle swallows, and it takes
somebody else's message with it. The stamp and the hide flag are still updated every time; only the
vote is now conditional on having changed.

## B85 — FIXED 2026-08-01 — restored items never gave up on themselves

From the bug run, in B81's fix. A snapshot is only worth anything while the raid it belonged to is
still running, and the client cannot know that at load -- the answer arrives from the raid. If it
never does, the items are last night's, and the restored tabs would sit in the panel into the next
evening: the "stale tabs after next boss" failure again. They now wait a minute for the raid to
confirm and drop themselves if it does not. The wait is long on purpose -- a reloaded loot owner is
the slowest client to hear back, because their session has to be handed to them rather than confirmed.

## B86 — FIXED 2026-08-01 — /kart trade and /kart owed showed a frozen list

The same defect as B51, in the two sibling commands, which were not looked at when it was fixed. Both
reminder windows only HIDE on their "x", and every removal path deliberately refuses to reopen a
closed one -- so an obligation ticked off, traded away or timed out while the window was shut stayed
in the row pool, and the command put that picture straight back on screen.

## B87 — FIXED 2026-08-01 — a restored item stayed a bare item string

From the bug run, in B81's fix. A snapshot carries whatever `LC.rollItems` held, and what
`LC.HandleStart` leaves behind until the client has cached an item is a bare `item:12345` string. A
reload is when that cache is coldest, and nothing would ever look at the roll again -- the resolver
runs from the two start handlers and a restored roll goes through neither. So it would have rendered
as `item:249293` for the whole distribution: GitHub #12, #13 and #16 all over again.

## B88 — FIXED 2026-08-01 — clearing the loot history did not keep it cleared

Reported by the maintainer: "I clear the history and another player syncs it straight back, so at the
start of a season I still have last tier's items in the list."

`LH.RequestHistorySync` asks for everything newer than the newest entry it holds, and after a wipe
that is zero -- which reads as "send me everything". Switching the sync off is not the alternative,
and the report says why: the whole reason it exists is that items decided while you were absent still
reach the list you export.

A clear now draws a line (`KART_LootHistoryClearedAt`) and the request asks from there. The
since-timestamp already means "I have everything up to here", so no protocol changes and no peer
needs to know about it. Both sides are needed: the request side means nothing is put on the wire at
all, and the receive side covers the race it cannot -- a reply burst spans about eight seconds, so a
clear can land in the middle of one.

Not covered, and nothing asks for it: deleting a SINGLE entry. There is no such control -- the window
offers a full clear, and a revoked award is removed on every client at once by the same broadcast.

## B91 — FIXED 2026-08-01 — the buff report was silently dropped on the pull it mattered on

Found in the BuffChecker bug run, picked because that file is 1161 lines the suite had never executed
a line of -- proven by `SendChatMessage` being a bare no-op stub.

`SendChatMessage` takes at most 255 bytes, and a longer line is not truncated into something the raid
can still read: it does not arrive at all. Two of the twelve checks report NAMES -- food and flask,
which are the two most commonly missing things in any raid -- and the name list was concatenated into
one message however long it came out.

Fifteen people without food, several of them cross-realm, is an ordinary pull and comes to well over
the cap. So the report did nothing, silently, on exactly the pull it exists for, with nothing printed
on either side.

Split on name boundaries now, never inside one, with the label repeated on each line so the second
line still says what it is about. A single name too long on its own goes out alone and the client
refuses that one line rather than the whole report. Three mutations: one message however long, the cap
raised out of reach, and a split after every name -- each turns a different assertion red.

The stub records chat now and marks anything over the cap as refused, so this class of silent failure
is visible to any later test rather than swallowed.

## B92 — FIXED 2026-08-01 — a realm-qualified promote entry never matched anyone on our own realm

Found in the Invite/GroupLogic/RaidleadBar bug run, picked because Auto-Promote acts on other
people's raid and had no test at all -- `PromoteToAssistant` was not even defined in the harness, so
`KART.HandleAutoPromote` would simply have thrown if anything had called it.

`UnitName` answers `""` for the realm of somebody on our own realm. That is the game saying "same
realm as you", not "no realm" -- and `HandleAutoPromote` read it as the latter, skipping its
realm-qualified branch entirely. So an entry like `Wuusch-TarrenMill` matched nothing for a player
standing on our own realm.

So an entry typed with a realm only ever worked for people from somewhere ELSE, which is the
opposite of what anyone writing one would expect -- exactly the shape of B15, which fixed the
cross-realm half of the same question and left this one open.

**Never hit in practice, and the first framing of this entry was wrong about why.** It claimed the
names come from the WoWUtils export, which qualifies everybody -- repeated from a comment B15 left in
`GroupLogic.lua` and never checked. There is no such path: the WoWUtils module imports INVITE lists
and writes nothing into the promote field, which is a separate, hand-typed setting. Asked rather than
assumed, 2026-08-01: the maintainer types short names and NS nicknames only, never realm-qualified.
The claim is out of the code comments and the changelog as well as out of this entry.

The fix stands on its own without it. The field accepts `Name-Realm`, the code has a branch for it,
and `PromoteToAssistant` is handed exactly that spelling by this very function -- so it is what
anyone reading the addon's own output would type back in, and it matched nobody on their own realm.

Fixed for MATCHING only: the realm the game reported is still what `PromoteToAssistant` targets,
because a same-realm character is addressed by plain name. Three mutations, each red on a different
assertion -- reading the empty realm as "nothing to qualify", using the match realm as the promote
target, and dropping the canonical key `UpdateCache` stores beside each entry.

Twelve assertions now cover the rest of it as well: case and spacing, a non-leader promoting nobody,
someone already an assistant being left alone, a namesake on another realm not being the person
named, and the nickname path.

## B93 — FIXED 2026-08-01 — a corrupt profile wiped every setting on the way to failing

Found in the profiles bug run. `KART.LoadProfile` checked its snapshot for PRESENCE and not for
being a table, and it does that check before `wipe(KART_Settings)`. A snapshot that came back as a
string therefore passed the guard, the settings were wiped, and `KAUtil.DeepCopy` then threw on
`pairs()` -- so the player lost every setting they had AND got a Lua error, instead of a profile that
simply refused to load.

`KART_Profiles` is a SavedVariable: hand-edited, half-written after a crash, or touched by another
addon. This is the same defensiveness `Trade.RestorePersistedTrades` and the loot-history handler
already apply to their own persisted data; profiles had none.

The mutation is unusually loud -- putting the presence check back does not fail an assertion, it
aborts the whole suite, which is exactly what it does to the addon.

Nothing else in that file needed changing. The deep-copy isolation, the minimap table keeping its
identity for LibDBIcon, re-deriving `autoLogOwned` from what is actually running, merging in defaults
a profile predates, the language-change reload, and deleting a profile leaving the loaded settings
alone all held -- and now have nineteen assertions holding them, each mutation-verified.

## B94 — NO DEFECT 2026-08-01 — the locale bug run found nothing, and that is the interesting part

Fifth and last of the 2026-08-01 bug runs. Three axes checked, all clean:

* every locale key the addon reads is defined -- 360 written-out references plus the ones reached by
  name (BuffData's labelKey/reportLabelKey, `"LC_QUALITY_" .. n`, the voted-display modes);
* no key is defined and never reached -- the 31 that look unused are all the dynamic families above;
* 43 `string.format` call sites all pass exactly as many arguments as their string has placeholders.

Worth writing down because of what it says about the other four. Locales were the ONE area entering
these bug runs with a test of their own, and the one area with nothing to find. Droptimizer,
BuffChecker, Auto-Promote and Profiles each had none -- proven, not assumed, by the stub each one
needed being absent from the harness entirely -- and each produced a real defect: B89, B91, B92, B93.

The three checks are tests now rather than a one-off scan, since two of them cover classes the
existing DE/EN comparison structurally cannot see: a key nothing defines renders as nil and throws on
the first concat, and a call site with the wrong argument count throws at the moment it prints --
which on a warning path means the client fails exactly when it was trying to say something was wrong.

## B95 — FIXED 2026-08-01 — a bulk invite could not start a raid, which is what it is for

Found in the WoWUtils bug run, which happened because a claim about that module in B92's write-up
turned out to be unchecked -- so the module itself got looked at properly. It had no test:
`UninviteUnit` and `C_PartyInfo` were absent from the harness entirely, so `WU.InviteBoss` and
`WU.RemoveForBoss` had never run a line.

`WU.InviteBoss` gated on `KAUtil.HasGroupPermissions()`, which answers false while ungrouped --
correctly, there is no group to lead. But "not in a group at all" is not a lack of permission, it is
the ordinary starting point: open the tab before the evening, click the first boss, and the invites
go out. Instead the player got "you are not the leader" while standing alone, and nothing happened.

The giveaway is in the same function: `KART.pendingBulkRaidConvert`, the deferred raid conversion,
exists ONLY for the solo case and could never be reached. `KART.HandleChatInvite` has always used the
right shape for the same question (`not IsInGroup() or HasGroupPermissions()`); this one forgot half
of it.

## B96 — FIXED 2026-08-01 — throwing people out of the raid asked nothing

Same bug run. "Remove" un-invites every group member who is not on the selected boss's roster. It is
the most destructive thing this addon can do -- real people leave the raid, they have to be invited
again and accept again, and there is no undo -- and it ran on a single click of a seventy-pixel
button sitting directly beside "Invite".

Resetting the boss LIST already asked, and its text says "this cannot be undone". Removing humans
asked nothing. Everywhere else in the addon confirms far less: reassigning a winner routes through a
dialog, ending a session asks, the raid leader is asked before standing in as lootmaster.

It asks now, and the count is in the question -- "remove everyone not on this roster" reads very
differently at two people than at eighteen. The targets are resolved before the question and carried
into the dialog rather than re-derived on accept, so the roster changing while the question sits on
screen cannot turn a "yes" to two into a "yes" to eighteen. Nothing to remove still asks nothing: a
confirmation for a no-op only teaches people to click through the one that matters.

## B97 — FIXED 2026-08-01 — Auto Combat Log decided on a difficulty ID alone

Seventh bug run. AutoLog.lua is 69 lines and had no test: `LoggingCombat`, `SetCVar` and
`C_ChallengeMode` were all absent from the harness, so `KART.AutoLog.Evaluate` had never run a line.

`MatchContent` read `GetInstanceInfo()` and threw away the instanceType, deciding purely on the
difficultyID against a table that claims `[1] = autoLogDungeons` for Normal dungeons. That makes the
whole feature depend on an unstated assumption about what that API answers OUTSIDE an instance -- and
1 is exactly the value the assumption is about. Anyone with the dungeon toggle on would have been
logging while flying around a capital city, for hours, with a file to match.

Not proven live from here -- the API's out-of-instance value cannot be read off the source, and this
is written down as the defensive gap it is rather than as a confirmed field report. The guard removes
the dependency either way and costs one comparison.

The guard is "not the open world", NOT an allow-list of party/raid: delves are in the table (208) and
report neither, so the stricter rule would have quietly stopped logging them while looking like the
safer choice. A mutation to exactly that stricter form is red for that reason.

Twenty assertions cover the rest, and the ones that matter are about STOPPING, which is the expensive
direction: a log the player started by hand is never stopped, never adopted while KART walks into
matching content, and a stale ownership claim -- `autoLogOwned` is a SavedVariable, `LoggingCombat`
is not -- is dropped before it can make the next hand-started log look like ours. Getting that wrong
is a raid night with no Warcraft Logs upload that nobody notices until the next morning.

## B98 — FIXED 2026-08-01 — one raider was two entries in the loot-history filter

Eighth bug run. The history's JSON export had no test either -- `date` was missing from the harness,
so `LH.BuildRCLootCouncilJSON` had never run a line.

`LH.GetUniquePlayers` produced one entry per distinct IDENTITY, not per person: a `winnerKey` for
entries written since the GUID migration (2.6.0) and a plain display name for everything older. So
anybody with history on both sides of that migration appeared in the filter TWICE under the same
name, and neither of the two showed more than half of what they had won -- with nothing to suggest
the other half existed.

Grouped by the displayed person now, carrying the set of ids they are known by, and the filter
matches any of them. `filters.player` stays a scalar because `LH.Refresh` builds its page-reset
signature out of it; `filters.playerIds` is what the matching actually uses.

## B99 — FIXED 2026-08-01 — the history filter listed departed raiders as raw GUIDs

Same function, found while fixing the one above. `KASC.Identity.ResolveDisplayName` answers with the
KEY ITSELF when it cannot place somebody -- which is every raider who has since left the guild, since
they are in neither the group nor the name cache. Taken as a label, that put
`Player-1096-0A1B2C3D` in the filter list while the name they were logged under sat unused in the
entry beside it.

Only a real answer wins over the stored name now. Worth knowing about `ResolveDisplayName` generally:
it never fails, it degrades to the key, so every caller that renders its result has to decide whether
that is acceptable output.

## B100 — NO DEFECT 2026-08-01 — officer notes, settings defaults, MainFrame

Bug runs nine and ten, both clean, and both now carry tests where they had none.

**Officer notes** (15 assertions): written locally and broadcast, colons and pipes stripped before
either so both sides keep byte-identical text, a pipe arriving over the wire escaped rather than
trusted, a note from somebody who is not council refused, and the pre-GUID key migration -- which
moves a legacy note onto the resolved key, leaves an unresolvable one alone rather than dropping it,
and does not clobber a newer note already written under the key. All of it already held.

**Settings defaults**: every `KART_Settings.x` the addon reads was checked against `KART.Defaults`.
Eleven are absent, all of them deliberately -- `activeProfile`, and window geometry written when a
window is first moved -- and every reader of those supplies its own fallback (`KART_Settings.bcX or
200`). A read with no default and no fallback is nil on a fresh install and takes whichever branch
the reader did not mean, silently and only for new users, so the check is a test now with the eleven
listed by name: a genuinely forgotten default cannot hide among them.

**Utils and MainFrame** beyond that are UI construction and `KART.IsOlderVersion`, which
tests/test_lc_version.lua already covers to the corners (two-part versions, build suffixes, and never
calling a NEWER peer outdated).

## B101 — NO DEFECT 2026-08-01 — the three UI files, and eight harness gaps behind them

Bug runs eleven to thirteen, covering the last addon files with no test at all:
`LootCouncilSettings.lua`, `MainFrame.lua`, `RaidleadBar.lua`. No defect in any of them.

What the 49 new assertions hold, all of which already worked:

* **the raid-wide settings box** -- a peer sees the RAID's council list, lootmaster (by name, not by
  key) and vote buttons while their own settings sit untouched underneath (B20); the borrowed fields
  are read-only; the lootmaster field, and only that one, becomes editable the moment its owner is
  gone, which is the raid's only way back to a loot flow; and the role label tells owner, plain
  member and "you named a third party and the whole box is inert" apart.
* **the main window** -- one tab panel visible at a time, every search entry knowing both its tab and
  its widget, and the reset asking first, changing nothing until answered, and DEEP-copying the
  defaults rather than handing its own nested tables out.
* **the raidlead bar** -- auto-hide keyed off being alone rather than off the setting, the saved
  position restored rather than the hard-coded default, the combat guard leaving the frame alone
  until combat ends, and the override bindings given back when the bar hides. That last one is the
  only thing in the file that can break something outside it: override bindings outrank the player's
  own keys for the whole session.

**Eight harness gaps, which is the real result of these three runs.** Each had made a whole class of
behaviour unreachable, and one of them hung the suite outright:

| gap | what it hid |
|---|---|
| `CreateFrame` discarded the parent; the catch-all returned the frame itself | `GetParent` looped forever -- the settings search walks that chain |
| `EnableMouse` / `EnableKeyboard` unstubbed | "is this box editable" answered truthy for everything |
| `SetPoint` discarded anchors, `GetPoint` returned a frame | every save-and-restore-position path |
| `InCombatLockdown` hard-coded false | every combat branch in the addon |
| `SetOverrideBindingClick` / `ClearOverrideBindings` absent | whether a hidden bar frees its keys |
| `GetTop`/`GetBottom`/`GetLeft`/`GetRight` returned a frame | now nil, which is what the game answers for an unanchored region -- and what every caller already guards for |
| `GetVerticalScroll`, `GetFrameLevel` returned a frame | arithmetic on both |
| `hooksecurefunc`, `ReloadUI`, `date` missing entirely | the settings panel's hooks, the two reload paths, the whole JSON export |

## B102 — FIXED 2026-08-01 — a corrected vote outlived the item it was made about

Fourteenth bug run, which stopped asking which FILE had no test and started asking which LINES had
never run. Coverage put the loot-history window at 41% and BuffChecker at 20%, and the first thing it
turned up was not in either of them: `MenuUtil.CreateContextMenu` was an empty stub, so the
initializer that builds a menu's entries had never run anywhere in the suite. Eight menus, none of
them ever opened.

One of the eight is the right-click menu on a council row, and its "change vote" entry calls
`Vote.SetPlayerVote` -- the way a lootmaster records an answer somebody called out on voice. That was
the only one of the addon's three vote writers that stored neither the item the vote was about nor
the button set its index was chosen from. Both readers treat a missing stamp as "cannot tell, so show
it", which is the right answer for a vote from an older client and the wrong one for a vote typed on
this screen a moment ago:

* Blizzard hands the same rollID to a genuinely different drop within seconds on trash. The addon
  deliberately does not wipe votes on reuse -- the reader decides per vote, from the stamp (B46). An
  unstamped correction passed that test and was drawn as that raider's answer to an item they had
  never been shown, and counted in the "x of y answered" badge on it.
* Rename the vote buttons mid-item and the correction was re-captioned rather than marked unreadable,
  which is B43 and B45 through the one door they had not been closed on.

Both stamps are set now, so the three writers agree. Five assertions turn red with the line reverted.

## B103 — FIXED 2026-08-01 — the borrowed minimum-quality and rolls controls took clicks

Found in the same run, opening the remaining seven menus. The read-only rule for a foreign raid
config (B20) is written for EditBoxes -- `EnableMouse`/`EnableKeyboard` over a list of them -- and the
raid-wide box holds two controls that are not: the minimum-quality menu button and the rolls
checkbox.

Both write into the VIEWER'S OWN settings on click and then call `LC.BroadcastRaidConfig`, which
refuses to send for a non-owner. So a council member glancing at the raid's minimum quality and
clicking it discarded their own stored value, changed nothing for the raid, and had the display
snapped back by the next `RefreshRaidWideFields` with nothing to show that anything had happened. It
surfaces much later, when that client becomes the config owner -- a lootmaster leaving is enough --
and the raid runs on a minimum quality nobody chose.

Measured rather than argued: the test set the viewer's own quality to 3, clicked "2" in the borrowed
menu, and read 1 back out of their settings.

Both are covered by the same lock now. `KARTTEST.Click` was added alongside it, because the assertion
has to be about a path a player can reach: a frame with the mouse disabled never receives a click in
the game, so calling its `OnClick` script directly is a stronger act than a player is capable of.

## B104 — NO DEFECT 2026-08-01 — what the fourteenth run turned up that was the harness

The run's other four areas were clean, and each one cost a harness gap to reach. Recorded because the
last of them invalidated assertions that had been passing:

| gap | what it hid |
|---|---|
| `MenuUtil.CreateContextMenu` an empty stub | all eight context menus -- their entries were never built, let alone clicked |
| `GetCursorInfo`, `ClickTradeButton` absent | the two lines that actually put an item into the trade window |
| `C_UnitAuras`, `GetReadyCheckStatus` absent | the whole buff-check render, which is the screen a raid leader reads before the pull (20% -> 69%) |
| `C_BattleNet` absent | the Battle.net whisper invite, which must resolve a friend's character rather than pass the numeric account id to `InviteUnit` |
| `IsAltKeyDown` absent | the one modifier that could not be held while recording a keybind |
| item-load callbacks carried no client | with real regions the refresh they trigger reaches a `SendAddonMessage`, which belongs to one client and not to whoever is executing |
| **`CreateTexture`/`CreateFontString` answered with the FRAME** | every region a frame owned was the same object |

The last one is the one to remember. A buff-check row's twelve indicators were all one texture
writing over each other, and `label:Hide()` hid the window the label sat on. Every assertion about a
region was really an assertion about its parent -- and the proof is a mutation: switching the aura
scan's entire name-match branch off changed nothing until regions became distinct, and turns the
suite red now.

What was checked and holds: the history window's paging, both its filter menus and the reset button;
the trade fill, for one item, two items to one person, two copies of one item, somebody else's item,
a busy cursor and a slot the player filled by hand; the three main-window menus, including a profile
list that is sorted and an empty one that is inert; the aura scan by spell id, by name in either
locale, the class gate that stops a report naming people for a buff nobody present can cast, and a
private aura not taking the rest of that player's auras down with it; the Battle.net invite,
including a friend with no WoW character to invite; the keybind recorder, where a key is taken off
whoever held it; and the WoWUtils Import button, which replaces rather than appends, ignores
identical text, and hands the previous roster back when a paste parses to nothing.

Coverage over the addon went from 71% to 82% across the run. What is left is overwhelmingly frame
construction -- `BuffChecker.lua` and `Invite.lua` are both half panel-building by line count -- and
the remaining logic in it was walked by hand rather than left unread.

Two lines were added to the addon purely to make a rule reachable, both in the same shape as their
neighbours: `f.btnReset` on the history window (the only one of its four filter controls not hung on
the frame) and `KART.KeybindListener`. Neither changes behaviour.

## B105 — FIXED 2026-08-01 — the suite had an expiry date, and it expired mid-run

Fifteenth bug run. Found by accident and worth the entry on its own: the same commit that had just
run green went red half an hour later, with nothing changed. Three assertions in
`tests/test_lc_baseflow.lua`, all about revoking an award without reaching back into a previous raid.

The harness clock runs from a FIXED epoch (`KARTTEST.epoch = 1785000000`, 2026-07-25) precisely so a
failure reproduces tomorrow as well. That one assertion mixed the real clock in: it dated its "last
Tuesday" entry with `os.time() - 7 days`. Once the real world was more than a week past that epoch,
"last Tuesday" landed AFTER the harness's today, `RemoveHistoryForRoll`'s twelve-hour revoke window
swallowed it, and the assertion measured the opposite of what it says. The crossover was 2026-08-01
at about 17:53 UTC.

It is the same defect class as a stub that answers too generously — an assertion that passes for a
reason that has nothing to do with the code — with a delay fuse on it. `time()` now, and it is the
only place in the suite that ever reached for the real clock (checked: every other `os.` in
`tests/` is `os.getenv`).

## B106 — NO DEFECT 2026-08-01 — the fifteenth run's four areas, and the getter behind them

The run's method: instrument the harness's catch-all — the metatable that answers any unknown
capitalised method with the frame itself — and let the suite report which methods actually go through
it. 59 names, and all but one are setters whose return value nobody reads. The exception:

| gap | what it hid |
|---|---|
| `IsMouseOver` came from the catch-all | truthy for every frame at once, which is not a state a mouse can be in |
| `GetDetailedItemLevelInfo` fell back to the base item level | the branch for an item this client cannot answer for yet was unreachable |

**The tab "x"** (`tests/test_lc_tabhover.lua`). `tests/test_lc_chrome.lua` checked this against the
SOURCE and said why: "neither is reachable from this harness (both need a real cursor)". It is now,
so the two bugs the tab strip paid for are held by behaviour: moving onto the x does not take it away
(the flicker that ate every click), and a refresh with the cursor resting on it leaves it there
(every incoming vote triggers one). What stays a source check is the part a harness with no layout
still cannot answer — where the two frames sit relative to each other.

**The compact vote layout** (`tests/test_lc_votecompact.lua`). Two renderers share the vote window;
every test in the suite ran the spacious one, and the compact renderer's 163 lines were at zero. A
raider who ticks that box was on code no assertion had ever reached, including the chips they answer
with. Held now: the answer lands, the note typed into that row travels with it, an automatic answer
leaves the chips on offer, and switching layouts does not leave both drawn at once.

**Truncating a name.** The buff check cuts a name that does not fit its column by binary search over
BYTE indices, and a German umlaut is two bytes. Never run — every fixture name fitted. Every cut
width on a name full of two-byte characters is walked now and the result validated as UTF-8.

**The gain tie-break, and the nine locale refreshers.** Droptimizer prefers the sim candidate closest
to the rolled item level and falls back to the largest gain when that level is unknown; only the
first half had a test. The refreshers re-label their widgets by hand, one line per widget, so they go
stale silently — a renamed control leaves a nil index that throws only when somebody changes their
language. None of the nine had ever been called.

Coverage went 82% -> 86% across the run. No defect in any of the four.

## B107 — NO DEFECT 2026-08-01 — the sixteenth run: mutating the loot core, and what survived

The previous run's find (B105) was, underneath, a test that was green for a reason unrelated to the
code. This run looks for that systematically instead of by accident: mutate a decision in the loot
core, run the suite, and record every mutant it fails to notice. A survivor is not a defect — it is
a decision no assertion depends on.

Scope: `LootCouncil.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua`, restricted to lines coverage
proves the suite executes (mutating unreachable code proves nothing) and to two rules — moving a
boundary (`>=` <-> `>`) and weakening a conjunction (`and` -> `or`). 83 survivors out of ~200
mutants, each one a candidate needing a human verdict.

**Two classes were worked through. The rest are recorded, not cleared** — mostly `X and X.y` nil
guards, where the mutant is usually equivalent, and second-clocked timeouts where an off-by-one
second cannot be observed.

**Six identical authority guards (worked through).** Every one of `HandleConfig`,
`HandleSessionResume`, `HandleVoteRequest`, `HandleVote`, `HandleRoll` and `HandleCouncilVote` opens
with `if not (senderKey and FindUnitForKey(senderKey)) then return end`, and all six survived being
switched off.

The first test written for it *passed and proved nothing*, which is worth more than the fix: it sent
from a player who had left the raid, and was caught one layer earlier by KASC's own group filter
(`entry.group` -> `KAUtil.IsFullNameInGroup`), already held by `tests/test_kasc_responders.lua`. The
messages never reached the handlers, every mutant still survived, and the file would have read as
coverage of something it never touched.

The two layers ask different questions — KASC compares the sender's NAME, the handler asks whether
the resolved KEY belongs to anybody present — and they disagree in exactly one state, the one the
identity code is written around: a group member whose `UnitGUID` is momentarily nil during a loading
screen. `KARTTEST.guidBlackout` models it, and with it **two of the six turn out to be the only
defence at their site**: `HandleVote` and `HandleCouncilVote`, where without the guard a vote lands
in the raid's loot state under a pending-text key like `sinja` instead of a GUID, on the panel that
hands out the item. Both are held now. The other four have a later authority check that refuses the
same sender anyway — defence in depth, and the reason their mutants are not worth chasing.

**The 255-byte cap on the raid config (worked through).** `BuildCouncilPayload` fits the council list
into what is left of an addon message after the prefix, and all three of its boundaries survived
being moved. Going over is not a partial send: every receiver's anchored pattern fails on the
fragment, so the whole raid silently stays on its previous config with nothing printed on either
side — the failure the function was written for, and one this addon has already paid for once. Now
measured at exactly 255, at one over, at a cut that must land on a separator rather than mid-name, at
a prefix that leaves no room at all (button labels run to 128 characters and the lootmaster field is
unbounded, so it is reachable from the settings panel), and at a council list of umlaut names, since
the budget counts BYTES.

**Measured and dismissed.** `RestorePersistedTrades`'s "are there any obligations" check is
redundant: `RefreshTradeReminder` makes the same check itself and hides the window. The outcome is
held anyway, because two independent places have to agree on it for a reload to stay quiet.

No defect in the addon. Two test gaps closed at the places that write loot state.

## B108 — FIXED 2026-08-01 — the confirmation asked, then removed people anyway

Found by reading the diff of everything unpushed since v3.2.2, rather than by a bug run — the first
review in this stretch that read the addon changes as CODE instead of scanning them for leftovers.

`WU.RemoveForBoss` checks both of its gates -- do I have the permissions, am I in combat -- when the
question is ASKED. What a confirmation buys is time to think, and the raid does not stand still
during it: lead moves (a handover, a disconnect), or the pull happens while the dialog is up. The
`OnAccept` then ran the uninvites under whatever was true by then.

The two fail differently, and only one of them is cosmetic:

* **Combat.** `UninviteUnit` is NOT combat-protected. The removals genuinely go through mid-pull,
  which is the exact thing the gate was written to prevent.
* **Permissions.** The game refuses each call, which is the right outcome — but the loop counts
  attempts, not successes, so it printed "2 players removed" to somebody who removed nobody.

Both gates re-checked in `OnAccept` now. The targets stay frozen from when the question was asked
(that part was already right and deliberate — what the player agreed to is the number they saw).

Two assertions turn red with the gates taken back out, one per gate.

While in there: the dialog now takes the locale template with the count as a show argument, the way
`KART_WU_RESET_CONFIRM` and `KART_LC_REASSIGN_CONFIRM` both do it. Formatting it in place AND passing
the argument worked only because the finished text had no placeholder left for the argument to land
in — a second one added to the locale string later would have found a filled-in text and an argument
list that no longer matched. `KARTTEST.popups` records the resolved text now, so "the question names
the number" — which is what B96 was for — is an assertion rather than an assumption.

## B109 — OPEN, by choice — two people of one name are one entry in the history filter

Raised by the same review. `LH.GetUniquePlayers` groups by DISPLAYED NAME, so two different people
ever logged under the same name — somebody leaves the guild and a later raider brings a character of
that name — collapse into a single filter entry showing both their records.

Kept, and now written down where the code makes the choice. The filter is a list of names a person
picks from, so the name is the only axis they can reason about. Grouping by key instead is precisely
what B98 was: it put ONE raider in the list twice, split their record down the middle, and gave no
sign the other half existed — a wrong answer to the question actually being asked. The namesake case
answers that same question too widely rather than too narrowly, stays visible in the rows themselves
(they carry dates and items), and needs a name to be reused within the 500 entries the history keeps.

## B110 — NO DEFECT 2026-08-01 — the report line that cannot be split

Also from the review, and recorded because the first reading of it was wrong. `SplitNameLines` only
measures from the SECOND name onwards: a single name that is already over the cap with the label in
front of it goes out whole and is refused by the client.

That is deliberate and says so in the comment directly above it ("cannot be helped"). What the split
is actually for is that such a line must not take the rest with it, and that had no test. It does
now: one impossible name plus six ordinary ones, and the six still reach the raid.

## B89 — FIXED 2026-08-01 — a cross-realm raider was shown a namesake's sim number

Found in the Droptimizer bug run, which was picked BECAUSE that module had no tests at all -- the
missing `C_Item.GetDetailedItemLevelInfo` stub proves it had never executed in the harness, since the
first line of `GetGainPercent` that reaches it would have thrown.

`FindPlayerCandidates` looked the raider up under OUR realm first and only fell back to a short-name
match, where its ambiguity guard lives. For a cross-realm raider with a same-named character on our
own realm, the first try hit and the guard never ran -- so the council read somebody else's sim number
under this raider's name, confidently, with no sign anything was wrong, on the one screen that decides
who gets the item.

The realm was available the whole time. `UnitName` returns it as a second value and
`Council.RefreshCouncilRows` discarded it while splitting the short name out. It is now carried on the
member table and passed through; absent still means our own realm, which is right for the two
vote-window call sites, since those ask about the player themselves.

Both halves are mutation-verified, and Droptimizer.lua is now loaded per client in the harness so the
panel's own call is exercised rather than only the module beneath it.

## B90 — OPEN, by choice — the loot history is capped, not pruned by age

Raised by the maintainer as "the history is never cleaned up, so it clutters players' disks". Measured
against a real SavedVariables file on 2026-08-01 rather than reasoned about:

```
75.5 KB total
  50.9 KB  67.4%  KART_WoWUtilsCache
  10.6 KB  14.1%  KART_LootHistory      (31 entries, 352 bytes each)
   7.1 KB   9.4%  KART_Settings
   4.4 KB   5.9%  KART_PlayerCache
   2.3 KB   3.0%  KART_Profiles
   0.2 KB   0.2%  KART_LCOfficerNotes
```

The history is not the bulk, and it is already bounded: `MAX_HISTORY_ENTRIES` is 500 and `TrimHistory`
drops the OLDEST TIMESTAMP rather than index 1 (the catch-up sync appends older entries, so a plain
`remove(1)` would evict the newest). Worst case is about 172 KB, permanently, and the file measured
sits at 6% of that cap. Two thirds of it is the companion app's own cache, which is replaced wholesale
on each sync rather than grown.

So no age prune. It would cost exactly what the maintainer wants kept -- the export to WoWUtils -- and
would save at most 170 KB. Revisit only if a real file is ever measured well past that.

## B82 — FIXED 2026-07-31 — a window could be dragged off the screen

Reported from the live v3.2.2-beta1 test, 2026-07-31. Dragging a KART window past the edge of the
game window leaves it partly or wholly outside, where it cannot be grabbed back.

Blizzard's own frames clamp to the screen; two of KART's did (the buff checker and the raidlead bar)
and the other six did not. All eight clamp now.

The other half was already there: `KAUI.IsSavedPosOnScreen` refuses to RESTORE a saved position
that is off-screen, so a window stranded before this fix comes home by itself on the next load, at
its default place. Nothing to migrate.

Guarded by a source-level check over every file that starts a drag, because none of these frames
can be dragged from the harness. What it really protects is the next window somebody adds: the
pattern is four lines of boilerplate and the clamp is the one that is easy to leave out -- which is
exactly how six of them ended up without it.

## B79 — OPEN, by choice — the tab's x and "No Winner" look alike and do different things

Raised by the maintainer on 2026-07-31, after seeing the sequence measured. Not a defect: both
buttons do what they were written to do. The problem is that you cannot tell from the screen which
one you pressed.

Measured, closing two cards with the tab's x and the other two with "No Winner":

```
whoever pressed them   0 cards, panel closed
every other council    2 cards still open  -- the two dismissed with the x
the raiders            2 vote windows still open
next boss              1 card for them, 3 for the council
```

"No Winner" broadcasts `LC_RESULT ... NONE` and the whole raid drops the item. The x sends nothing --
it means "off my screen". Both leave the same empty panel behind, so the person who pressed them has
no way to know half the raid is still looking at the last boss. Neither ends the session; only Close
Session does. `LC.EndRound` is what clears everything for everyone, and it does (asserted in
`tests/test_lc_chrome.lua`, along with the difference itself, so nobody quietly makes the two match).

**Left as it is for now, deliberately** -- in the maintainer's words, unsure how involved changing it
is without breaking something, but it could be better. Recorded so the next pass starts from the
measurement rather than re-deriving it.

The three shapes considered, with what each costs:

* **The x clears for everyone.** Same reach as "No Winner", minus the history entry and the trade
  obligation. Costs: a mis-click takes the item away from the whole raid and there is no undo -- the
  reason the button was moved outside the tab in the first place (B27, issue #9).
* **The x stays local but says so.** When the last card is dismissed locally while others still hold
  some, offer "2 items are still open for the council -- End Round?". Nothing silently diverges, and
  no new way to lose an item.
* **Drop the x.** One meaning per button: "No Winner" for one item, End Round for the round.


**Standing measurement, 2026-07-31:** 0 of 30000 soak runs disagree, and the Manifest run (C1-C12,
`tests/test_manifest.lua`) is green.

**The first live test of v3.2.2-beta1 found four things the harness could not.** One is fixed (the
winner's reminder not clearing when the item arrives). Three are open below: B81, B80 and B82. That
ratio is the point of running it in a raid at all -- 0 of 30000 and a green Manifest still left a
reload that loses every `/kart add` item.
`KART_SOAK_SEEDS=30000` is the deeper run worth doing before a raid night; `KART_SOAK_ONLY=<seed>`
runs a single one, which is the whole debugger.

The number is worth keeping current: a new signature standing next to a known-empty result is a new
finding rather than noise, and the last pass showed how much that matters -- of the seventeen breaks
at 30000 seeds, thirteen turned out to be the harness asking for something a raid cannot do.

## Found 2026-07-31 by three new soak steps

The soak learned three things it could not do before -- two council members awarding the same item at
the same moment, a vote button renamed mid-roll, and a rollID handed to a different item -- and each
found a defect within its first few hundred seeds. All are fixed, and the steps now run as part of
the ordinary soak rather than behind a flag, so the gate covers them from here on.

## B78 — FIXED 2026-07-31 — a two-second blip cost a raider their vote for good

Found by the soak at 30000 seeds, seeds 9545 and 11091. In both, the client missing a vote was the
one whose group APIs had just blipped -- the state the maintainer has watched cost a session
mid-boss, where for a moment one client's `IsInGroup`/`IsInRaid` answer "no".

While that lasts, KASC rejects every group-gated message on that client. That guard is right; the
consequence is not survivable for the tokens with no retry. `LC_VOTE` and `LC_RESULT` are announced
exactly once and nothing acknowledges them (B66), so whatever was said in those seconds is gone --
for that one client, silently, with the raid around them carrying on.

Rolls have a catch-up (`LC_ROLL_CATCHUP`) and history has one (on join). Votes have neither. The
council panel is the one screen where a missing vote changes a decision, and it is also the natural
place to ask for them again: a council member who notices a gap could re-request the tally for a
live roll, the same way a joiner re-requests the state.

Closed with `LC_VOTE_REQ`: a few seconds before the window shuts, the loot owner asks once for the
votes on that item and everyone who voted says theirs again, jittered. Asked by the loot owner and
nobody else -- the same "exactly one broadcaster" rule `LC_START` follows, so three council members
cannot turn it into three rounds -- and answered to the whole raid rather than to the asker, so every
client's tally converges rather than only the one that noticed. Each client re-sends its OWN vote and
nothing else, which needs no trust rules of its own and cannot spread a wrong tally. Three clauses,
all red when removed: the sender must be the loot owner, the scheduler must still be the loot owner
when it fires (the role moves mid-round), and the request has to go out at all.

**The soak stopped reporting this** in the same pass -- a blipped client is dropped from the
comparison for rolls that were live, exactly as a reloaded one is. That exclusion stays: a blip can
still cost an `LC_RESULT`, which has no catch-up of its own.

## B77 — FIXED 2026-07-31 — a council member who reloads was overruled on their own re-decision

Found by the soak: 2 of 30000 runs, seeds 12530 and 29229. Reproduce with `KART_SOAK_ONLY=29229
KART_SOAK_DEBUG=29229`.

`LC.assignedWinners` does not survive a reload, and nothing restores it: the state request brings
the session and the config back, the roll catch-up brings the rolls, and the history catch-up runs
on JOIN only. So a council member who reloads mid-distribution comes back not knowing which items
already have a winner.

Measured on seed 29229. Merrit awards roll 200 to Corvin at t=1012. Merrit reloads. At t=1017 Merrit
awards the same roll to Alric -- and `Trade.AssignWinner` reads `prevWinner = nil`, so it never
shows the reassign dialog and `Trade.AnnounceResult` sends the reassign flag as **0**. Every peer
then reads it as a first award clashing with the one it holds, applies the B35 tie-break (neither
side deliberate, so the smaller winner key wins), and keeps Corvin. Merrit's own local step wrote
Alric unconditionally.

The result: the one client showing Alric is the person who just decided it, and the rest of the raid
shows Corvin. Nothing tells them. `Trade.HandleResult` does not run on our own broadcast, no peer
re-announces, and the clash warning is only printed by clients that *received* two awards -- the
loser of a tie it never knew it was in stays silent. The lootmaster then hands the item to somebody
the deciding council member's panel says did not win it.

### The fix

`KART_LootHistory` is persisted and every client logs every award, so `LC.assignedWinners` is
rebuildable on load for rolls still inside the trade window -- the same bound
`Trade.RestorePersistedTrades` already uses for the obligations it restores. `AssignWinner` would
then see the previous winner, show the dialog, and send the flag as 1, which outranks a first award
everywhere and is the behaviour B35 was written to produce.

Applied. `looted` is the bound -- an entry only counts while the roll it belongs to is still inside
the four-hour trade window, which is exactly the set of rolls that can still be re-decided, and it
keeps last week's raid out without inventing a second timestamp. The entry must also be NEWER than
that stamp: the history deliberately keeps both awards made under a reused rollID (B74), and
restoring the previous item's winner would make the new item look decided. `assignedDeliberate` is
not restored -- a history row cannot say whether somebody confirmed a dialog, and "not deliberate"
is the answer that loses a tie-break rather than winning one it may not be entitled to. Both
clauses go red when removed.

## B76 — FIXED 2026-07-31 — an empty Lootmaster field wiped the raid's designation

Found by the soak: 2 of 30000 runs, seeds 6151 and 16848. It needs no reload at all -- one promotion
is enough, and the reload only made it likelier by clearing what was in memory.

### What happens

"An EMPTY council list means *not configured*, not *this raid has no council*" was written for
exactly this shape and stopped one field over. Raid lead moves to somebody who has never filled the
Lootmaster field in -- a stand-in, or a promotion by accident -- `LC.ApplyOwnConfig` writes their
empty field in as the raid's designation, and from that instant they answer `LC.IsLootOwner` with
"yes" while everybody else still points at the person actually handing out the loot. Both halves stay
internally consistent, which is what makes it so quiet.

An item dropping in that window is force-won by the new leader and announced by them -- and every
client that still holds the designation rejects the `LC_START`, because `LC.HandleStart` opens with
`IsSenderLootOwner`. The roll then exists on part of the raid, and a vote cast on it is dropped for
good by the rest.

### The fix, and the second bug it exposed

The rule now holds for the designation too: an empty field keeps what the raid has, a field with a
name replaces it outright, and a designee who has LEFT is cleared (`LC.GetLootmaster` masks a name
that is no longer in the group, and that case must still clear -- keeping it would point the raid at
an empty chair). `LC.BroadcastRaidConfig` sends the designation IN FORCE rather than the raw field,
for the same reason it already sends the council list in force: a client with no config yet has
nothing to keep, so a newcomer would otherwise be the only person in the raid who does not know who
hands out the loot.

That alone took the soak from 4 disagreements in 30000 runs to **2885 in 8000**, and the cause was a
separate defect it had been hiding:

> The config re-broadcast on every roster change sat behind `if not LC.IsLootOwner() then return end`
> -- a gate whose stated purpose is the session prompt below it.

The config belongs to the raid LEADER and the loot flow to whoever they designate, and in the normal
split setup those are different people. Behind that gate, a leader who had designated somebody else
never re-broadcast, and the designee's own send returned immediately at the config-owner check --
**so in a split raid nobody re-sent the config on a roster change at all**, and every late arrival
ran the evening on their own vote buttons, minimum quality and roll setting. It was invisible only
because an empty Lootmaster field used to make the leader the loot owner as well. The re-broadcast
now sits above the gate; `BroadcastRaidConfig` self-gates on `IsConfigOwner`, so it needs no
ownership test of its own.

Three of the four clauses go red when removed. The fourth -- reading `LC.GetLootmaster()` rather than
the stored key, so a departed designee still clears -- has its own test but stays green under
mutation: another path already clears that case. Kept because it states the intent, not because it is
proven.

**Measured after: 0 of 8000 runs disagree.**

Two existing tests asserted the old behaviour and were rewritten, not deleted: with the re-broadcast
restored, a promotion really does move the raid onto the new leader's settings. That is the rule
`LC_CONFIG_OWNER_NOW` announces, and it was simply never reaching anyone.

## B75 — FIXED 2026-07-31 — two clients with amnesia confirm each other, and the raid splits

Found by the soak at 6000 seeds, seed 5013.

"An EMPTY council list means *not configured*, not *this raid has no council*" has to hold at all
three sites that write the field. It held in `TryAcceptConfig` and in `LC.ApplyOwnConfig`. The third
is `LC.HandleConfigRelay` -- the path a reloaded raid leader depends on, since a leader rejects
every config that is not from a leader and a relay is the only way one gets its state back.

Every peer answers a state request at once, spread over a fraction of a second. Measured: the first
answer came from another client that had just reloaded and had no council list either. It was taken,
it cleared the marker that says "still waiting", and the real list -- 0.17 seconds behind it, from a
client that had been in the raid all evening -- was rejected as "we already have a config". Two
clients with amnesia confirmed each other. Half the raid then held the council list and half held
nothing, and `Trade.HandleResult` gates on `LC.IsSenderCouncil`, so every award from the other half
is rejected -- the same 94-per-3000 silent award loss that put the rule in `TryAcceptConfig`.

Two clauses, both mutation-verified: a relay that carries a list is taken even when we already have
a config, and an empty list never replaces one we hold. Between them the field only ever moves from
no-list to list, so peers still answering cannot swap it back and forth.

## B74 — FIXED 2026-07-31 — a mid-raid joiner loses the awards it was just handed

Found by the soak on the first clean pass after B71, seed 1716.

Awarding an item clears any history entry for that rollID first, so a reassignment or a clash
replaces its own record instead of sitting next to it (B35). Which entries count as "that rollID"
was decided by time alone: everything logged since `LC.rollLootedAt[rollID]`, the moment this client
saw that roll start. A client that never saw it start has no stamp and fell back to a twelve-hour
window -- so it removed the entry for a *previous* item that had reused the same number, which every
client that had been in the raid kept.

That client is the ordinary mid-evening joiner. It is handed the earlier awards by the history
catch-up, and the next drop to reuse one of those numbers takes them straight back out. The raid
agreed on every winner and disagreed about its own record of the evening, on exactly the clients
that had joined late -- and the council reads that record to decide who is owed something.

`LH.RemoveHistoryForRoll` now takes the item as well, which is the discriminator that actually works
and the one `LH.LogHistory` already applies to its own replacement pass. Unknown on either side
counts as belonging, the same rule votes follow (B46): an entry logged while the link was still
"???" is still superseded by the reassignment that names it.

## B71 — FIXED 2026-07-31 — a reused rollID lost rolls, in two unrelated ways

**The first half**, fixed when the step was written: a client purges everything under a rollID when
it processes its own `START_LOOT_ROLL` -- but peers broadcast their rolls for the NEW item at that
same instant, so a client that had already RECEIVED some of them wiped them a moment later with its
own purge. Whoever ran their handler first lost the rolls of everybody behind them, and the council
scored its tie-break on a partial set. `LC_ROLL` now carries the itemID and `LC.rollsFor` records
which item the stored rolls belong to, so a purge keeps the ones already cast for the item arriving.
29 disagreements per 3000 before, 14 after.

**The second half** is `LC.rollsPendingSince`. A roll is accepted for a rollID this client does not
know yet -- `LC_ROLL` is broadcast from `START_LOOT_ROLL` and routinely beats the `LC_START` that
explains it -- and the stamp records when that wait began, so `PurgeStaleRoll` can throw the data
away if the roll never materialises. Nothing cleared the stamp when the roll *did* materialise: on
the path where `LC_START` arrived inside the grace window, `PurgeStaleRoll` returned at "nothing
tracked under this ID" before reaching any cleanup. The stamp then sat there for the rest of the
session. The next time Blizzard reused the ID, the orphan sweep read it as "this data has been
waiting twenty minutes" and wiped -- except the table no longer held the orphan, it held the rolls
peers had just broadcast for the NEW item. Only the clients that had missed that `LC_START` were
hit, so the raid disagreed about who rolled what.

The wait now ends where it actually ends: `PurgeStaleRoll` clears the stamp unconditionally, because
reaching it means a roll under this ID is being processed right now. Covered in
`tests/test_lc_votelabels.lua`; removing the line puts it back to red.

**Twelve of the fourteen breaks were the step, not the addon.** It picked the new item from three
without excluding the one already on the table, so a third of the time it re-announced the *same*
item -- which is not a reuse at all but Blizzard re-raising the event for the roll already running,
and the addon deliberately keeps the rolls already cast for it. The step then re-recorded the
population, so a raider who joined after the original drop was expected to hold rolls broadcast
before they were in the raid. The step now always picks a different item; the re-announced-identical
case has its own test.

## B72, B73 — FIXED 2026-07-31, and both were the same thing

Both were caused by the reused-rollID guard added the same morning for B46, which DROPPED a vote
whose itemID did not match what this client was holding. A vote is sent exactly once with no retry,
and the two clients need not disagree about which item is current -- ours may be the stale half. So
the guard threw away legitimate votes for good whenever our own link was the one that was behind,
which is a worse failure than the one it was written for.

Recorded instead of dropped, and read instead of received: the vote carries the item it was cast for,
`LC.VoteIsForItem` decides at every reader (the council rows, the tab tooltip, the answered-count
badge), and a vote that turns out to belong after all is still there to be counted. Unknown on either
side counts as belonging -- an older client sends no item, and a roll still held as "???" has none to
compare against, and refusing those would blank a whole raid's votes over a link that had not arrived.

Confirmed by the soak: with the three new steps enabled, `council` and `votes` disagreements went from
one each per 3000 to none.



---

# Tier 0 — reopened

## B55 — confirm dialogs are buried again (was B8) — FIXED 2026-07-30, and the old fix must never come back

B8's fix raised Blizzard's popup frame to the `TOOLTIP` stratum on show and restored it on hide. It
worked, and it broke the game: those frames are a shared pool, an insecure `SetFrameStrata` taints
the frame for the rest of the session, and the next Blizzard dialog handed that same pooled frame has
its protected calls refused — reported from a live raid as `ADDON_ACTION_FORBIDDEN ... tried to call
the protected function 'UpgradeItem()'`, with KART blamed for a dialog it never registered. Players
could not upgrade items until they reloaded.

The lift is gone as of 2026-07-29, so B8's original symptom is back: a consumer whose windows sit at
or above `DIALOG` buries its own confirm dialog behind the window that raised it, and pressing the
button looks like it did nothing.

**FIXED 2026-07-30** by the first of the two candidates: lower our own windows while one of our
popups is up, rather than lifting Blizzard's frame. (The other candidate — dropping StaticPopup and
building the confirms out of `KAUI:ApplyPopupArtwork` across all eight call sites — was not needed.)

Every path that sets a stratum goes through `nsProto:CurrentStrata`, so the clamp also covers the two
cases a one-shot lowering would miss: a window built while the dialog is open (the vote window
opening on an incoming roll), and a settings or profile change mid-dialog calling `ApplyFrameStrata`.
Windows configured below `DIALOG` are left alone — they were never buried, and moving them would
override a player who chose `MEDIUM` on purpose.

The state is a set keyed by the popup frame, not a counter. `StaticPopup_Show` on a dialog that is
already up reuses the same frame and fires `OnShow` again with no `OnHide` in between; a counter
would be left one too high and the windows would stay lowered for the rest of the session.

The Loot Council windows keep their own list and their own stratum setting so the module stays
separable (B22), so KAUI's clamp cannot reach them; they subscribe through the new
`RegisterPopupYielder`. They are the ones actually in the way — the stand-in prompt is raised while
the council panel is open, and a raid whose lootmaster has left waits on somebody pressing a button
they cannot see.

Covered in `tests/test_kaui.lua` (library contract) and `tests/test_lc_chrome.lua` (the real
stand-in prompt against real Loot Council windows), which needed frame strata to become real state
in the stubs rather than a swallowed write. Five mutations were run — removing either clamp, dropping
the subscription, counting instead of keying, and clamping windows that sit below `DIALOG` — and each
turns its own assertions red.

**Confirmed in a client by the maintainer, 2026-07-30**, which is the half the harness cannot
answer: the dialog renders on top, and the windows come back where they were.

The regression that caused all of this stays guarded separately: `tests/test_kaui.lua` observes the
popup frame through `RegisterStaticPopup` and fails if anything writes its stratum, level or parent,
or leaves bookkeeping on it.

---

# Tier A — the loot flow stops for the whole raid

B29 to B33 share one root: ownership and session state are distributed across clients with no single
authoritative holder. They want one design pass, not five patches.

## B70 — a raid-lead change during B69's grace leaves the raid with NO config at all — DISSOLVED 2026-07-31 by the ownership rework

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

**This is B33 again — the whole raid silently not rolling — and this session's own B69 fix opened it.
Fix before the raid.** Measured, not deduced; the probe below prints `LC_CONFIG so far: 0` at every
step.

The sequence, none of it exotic:

1. Somebody with an EMPTY Lootmaster field holds raid lead and starts the session. That is the
   documented, supported setup (B33) — the leader stands in as loot owner.
2. Nobody has told them what the raid was already doing, so B69 sets `configClaimUnverified` and
   holds their config back for `CONFIG_CLAIM_GRACE` (10 seconds).
3. Raid lead moves to somebody else inside those 10 seconds. A raid forming does this constantly.
4. The grace expires. `BroadcastRaidConfig` now returns at its own `IsConfigOwner()` check, because
   the sender is not the leader any more. The held config is dropped on the floor, silently.
5. The NEW leader never becomes config owner either: `LC.IsConfigOwner`'s raid-leader fallback
   requires `sessionStartedByUs`, and they were TOLD about the session rather than having declared
   it. That requirement is deliberate — it is the other half of B69 — and correct on its own.

Result: no `LC_CONFIG` is ever broadcast by anyone, for the rest of the raid. Every client falls back
to its own `lcRollsEnabled`, which defaults to off. Nothing is printed. This is exactly the evening
the guild already lost once.

**Why it was not caught.** `tests/test_lc_churn.lua` covers this scenario and was passing — by luck.
The addon jitters its replies with `math.random`, and whether a peer's jittered answer lands inside
the first 5 seconds (clearing `configClaimUnverified` before the promote) depends on the random
stream that whatever test file ran previously happened to leave behind. Reseeding `math.random`
before each test file — which is plainly the right thing, since otherwise adding any test file
anywhere silently changes what a later file measures — turns five of those assertions red. That
reseeding is written and was taken back out; it belongs with this fix, and `tests/run.lua` carries a
comment saying so.

**Do not fix it by deleting the grace.** Tried and measured: it takes the five promote assertions
green again but turns two B69 assertions red. The grace covers the window *before* you have been told
anything, which is exactly when `IsConfigOwner`'s `sessionStartedByUs` guard has nothing to bite on —
`sessionActive` is still false there, so the guard does not fire and a reloaded leader claims freely.
The grace is load-bearing for that. Keep it.

### Step 1, done — losing raid lead is not a handover

`LC.ApplyOwnConfig`'s not-owner branch treated "raid lead moved away from me" exactly like "I typed
somebody else's name in the Lootmaster field": it broadcast `LC_RESIGN` and wiped our copy. With an
empty field nothing was handed over, our settings are still the ones the raid is running on, and —
because the new leader cannot claim the config — that copy is the only one in existence. Erasing it
is what turned a lead change into a config-less raid. It is now kept, distinguished by whether our
own field names anybody. Both directions are mutation-checked.

That alone does **not** fix B70. Two measured blockers remain.

### Blocker 1 — `LC.RelayRaidConfig` refuses to relay a `fromSelf` config

So the surviving copy still cannot reach the new leader: 25 `LC_STATE_REQ` go out in the probe and
`LC_CONFIG_RELAY` stays at 0. The refusal is deliberate and correct for what it was written against —
a config a client *invented from its own defaults* after a reload cleared `raidConfig` must never
spread. But it cannot tell that apart from the empty-field leader's config, which is `fromSelf` and
is genuinely the raid's (B33).

The discriminator that separates them is `sessionStartedByUs`: a client that DECLARED the session
owns its settings by construction; one that reloaded into a session did not. Which leads to:

### Blocker 2 — `sessionStartedByUs` is cleared on the client that declared the session — CAUSE FOUND

`LC.HandleActive`, confirmed by instrumenting all four writers. The empty-field declarer keeps asking
the raid what is going on (`StateStillNeeded` is true for them: their config is `fromSelf` and their
own field names nobody), somebody answers `LC_ACTIVE:1` — confirming the very session they started —
and `HandleActive`'s unconditional "told, not decided" clears the flag. From that moment they no
longer count as the person who started it. `HandleSessionResume` is not it; it returns early while
`sessionActive` is true.

### The relay-based fix was BUILT, MEASURED AND REJECTED — do not rebuild it

All three edits were written and they do work for the case: with per-file reseeding on, the five
promote assertions go green and the raid gets its config. Then the soak said no.

    soak: 16 of 3000 runs disagreed
        13  config.rollsEnabled     (first at seed 183)
         3  config.buttons          (first at seed 678)

Config disagreement is the exact failure class this whole tier is about, so it is not shippable.
Verified as caused by the change, not by the reseeding: at HEAD with reseeding on, the soak is clean
and only the five known churn assertions fail.

What the three edits were, so nobody redoes them:

1. `HandleActive` keeps `sessionStartedByUs` when the message merely confirms a session we declared
   and are still in.
2. `RelayRaidConfig` relays a `fromSelf` config when we declared the session.
3. One shared `ConfigIsSelfInvented()` predicate for `RelayRaidConfig`, `HandleConfigRelay` and
   `StateStillNeeded`, which had drifted — two knew about the own-field case, none about the declarer.

**Why it leaks.** It makes the declarer's config sticky: they keep it, relay it, and refuse relayed
overwrites. That is a second authoritative source alongside any real lootmaster's. Once a real
lootmaster broadcasts C2, the declarer still holds C1 and hands it to anyone with an empty config,
re-injecting a config the raid has moved off. They stand down only once C2 reaches them through
`TryAcceptConfig` — and the window before that is the 0.5%. Bisecting confirmed no single one of the
three is responsible; reverting `HandleConfigRelay` alone takes 16 down to 10.

### The ownership-based fix was built too, and measurement moved the target

Second attempt, following the note this entry used to end with: make ownership follow the
DECLARATION rather than the current raid lead (`IsConfigOwner` returns true for a declarer who still
holds a `fromSelf` config, even without the lead), keep `sessionStartedByUs` through a confirming
`LC_ACTIVE`, and broadcast when `HandleActive` clears the held-back claim. That last one closes a
real gap on its own: the note in `HandleActive` saying a "broadcast if we own the config" branch is
unreachable is true only for a NAMED lootmaster — with an empty field `GetLootmaster()` is `""`,
`IsSenderLootOwner` falls back to the raid leader, and somebody else's `LC_ACTIVE` IS accepted by a
client that owns the config. Clearing the flag without sending leaves the config waiting for a roster
change that may never come.

It still did not converge, and probing why produced the fact that matters most:

    declared      : own=true  unverif=true startedBy=true fromSelf=true  CONFIG=0
    settle 5s     : own=false unverif=true startedBy=true fromSelf=nil   CONFIG=0
    promote +5s   : own=false unverif=nil  startedBy=true fromSelf=nil   CONFIG=0

**The declarer has already lost its config at the FIRST roster settle, while still holding raid
lead.** The promote is a red herring — by the time lead moves there is nothing left to lose. Verified
byte-identical at HEAD with no changes applied, so this is pre-existing, not something the two
attempts introduced.

It is also timing-dependent: the committed step-1 test asserts `fromSelf` is still set after exactly
that sequence and passes, while the same sequence in a probe file placed later in the run — different
message jitter — loses it. Both orderings are reachable. That is the same order-dependence the
per-file reseeding exists to remove, and it is why this must be pinned with a deterministic seed
before anything else is tried.

### Root cause, MEASURED — and why the obvious fix for it is wrong

Instrumenting `IsConfigOwner`'s conditions one by one (rather than reasoning about them) gives it in
one line:

    roster    : fromSelf=true why=lead=true
    !! HandleConfigRelay overwrote our own config
    +5s       : fromSelf=nil  why=received-config-in-force

**`LC.HandleConfigRelay` replaces the declarer's own config with a forwarded copy.** Its
"self-invented" test is `fromSelf and not ownField`, and the empty-field declarer's config matches
that exactly while being the config the whole raid is running on. The overwrite clears `fromSelf`,
which drops them out of `IsConfigOwner`, and nobody else can claim it.

Third attempt fixed precisely that — `selfInvented` also requires `not (sessionActive and
sessionStartedByUs)`. It works: the declarer keeps its config through every roster update and does
finally broadcast. **The soak rejected it too: 9 of 3000, again split on `rollsEnabled` and the vote
buttons.**

That is the third rejection in the same shape, and the pattern is now clear enough to state as a
rule: **anything that makes the declarer's config survive independently creates a second
authoritative copy, and the raid splits.** Whatever the relay overwrite costs, it is currently also
the mechanism by which everybody converges on ONE config. Do not attack it directly again.

### What is actually wrong, and the one thing left to try

The declarer's config is never broadcast in the first place — B69's grace holds it, and by the time
the grace expires a relay has already replaced it. Everything downstream is that one fact playing
out. So the fix belongs at the send, not at the overwrite.

Attempt three also tried the narrow version of that: have `HandleActive` broadcast when it clears the
held-back claim. **Measured as dead code, and the note in `HandleActive` claiming such a branch is
unreachable is RIGHT** — a correction to what the previous commit here said. The sender of a
confirming `LC_ACTIVE` is only accepted when we are NOT the raid leader (`IsSenderLootOwner` falls
back to the leader for an empty field), and at that point `IsConfigOwner()` is false anyway. The
branch cannot fire without also changing the ownership rule, which is attempt two, which the soak
rejected.

Left to try, in order: (1) does the grace need to withhold the config from the RAID at all, or only
withhold the *claim* — i.e. send it as a relay-shaped fill-a-void message immediately and the
authoritative `LC_CONFIG` after the grace? (2) failing that, treat the empty-field-plus-declaration
setup as needing a real lootmaster name and say so out loud at session start, rather than trying to
make an ownerless config converge.

Needs the soak (`KART_SOAK_SEEDS=3000`) to confirm, since B69 itself was found there. And it needs
the per-file `math.randomseed` in `tests/run.lua` — written and taken back out twice now, because
with it the five promote assertions are red until B70 is actually fixed. Put it back as part of the
fix, not before.

## B29 — a departed lootmaster leaves the raid with no loot owner — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

`LC.raidConfig.lootmaster` is written only by `TryAcceptConfig`/`ApplyOwnConfig` and never
invalidated; neither `TearDownForRaidExit` nor `ClearAllRolls` touch it, and nothing prunes it on a
roster change. When the named lootmaster disconnects, `GetLootmaster()` still returns their key, so
`IsLootOwner()` is false for everybody — the `UnitIsGroupLeader` fallback is unreachable while the
string is non-empty. Nobody force-wins, nobody broadcasts `LC_START`, and the session cannot be ended
by anyone. `raidConfig` survives leaving the raid, so the same client is still stuck in the next one.

Partially mitigated 2026-07-29: the Lootmaster field is editable again once the configured owner is
absent, so a replacement can name themselves. The stale key itself is still never invalidated.

**Fixed 2026-07-30.** The key is checked against the live roster at the moment of use rather than
cleared on every path that could make it stale — the difference between an open-ended obligation and
a closed one. Presence means "in the raid", not "online": a disconnected lootmaster keeps the role,
since their bags still hold the loot. The role then falls to the raid leader, but not silently — they
are asked first, because standing in means every council-eligible item is force-won into their own
bags. The claim lapses by itself the moment the lootmaster is back in the roster. `raidConfig` is now
wiped on a confirmed raid exit as well, which closes the cross-raid half. Covered by
`tests/test_lc_churn.lua`.

Deliberately NOT part of this: the stand-in does not become the CONFIG owner. Pushing their own
settings over the raid would erase the name the lootmaster reclaims on the way back and take the
council list with it if that leader never filled one in. See B58 for what that leaves open.

## B30 — a reloaded loot owner is answered by nobody, and their session stays off — FIXED 2026-07-30

`LC.HandleStateRequest` replies only if `LC.IsLootOwner()`. After the lootmaster reloads their own
`sessionActive` is false and they send `LC_STATE_REQ`; on every peer the loot owner resolves to the
reloading player, so no peer replies. The raid still believes the session runs while the one client
that must win the items has it off: `OnStartLootRoll` returns early, so no force-win, no `LC_START`,
no vote windows anywhere, while Auto-Pass raiders keep passing. Workaround until fixed: toggle the
session by hand after every reload.

**Worse than described, confirmed by `tests/test_lc_churn.lua` 2026-07-30.** The reloaded owner does
not merely fail to recover — they actively tear the session down for everyone else. They are still
the loot owner, so `LC.HandleStateRequest` answers every incoming `LC_STATE_REQ` with `LC_ACTIVE:0`,
one whisper per asker, and each recipient runs `LC.ClearAllRolls`. Message trace from the harness,
after Bramor reloads mid-distribution and one roster change follows:

```
Merrit   LC_STATE_REQ  -> RAID
Bramor   LC_ACTIVE:0   -> Merrit-TarrenMill
Corvin   LC_STATE_REQ  -> RAID
Bramor   LC_ACTIVE:0   -> Corvin-TarrenMill
...
```

The whisper-instead-of-broadcast fix already in `HandleStateRequest` limits the blast radius to
whoever asks; it does not stop it. Anyone whose latches re-arm (see `LC.CheckRaidJoin`) asks, so in a
raid where people join and leave constantly this reaches everyone. This is the second mechanism
behind "session geht rando zu".

**Fixed 2026-07-30.** Two halves. `LC.sessionStateKnown` separates "no session" from "I have not
found out yet", and only the first is ever quoted to a peer — so a freshly loaded owner answers
nothing instead of answering wrongly. And `LC_SESSION_RESUME`: a council member (or the raid leader)
whose own session is running replies to an `LC_STATE_REQ` from the person they believe owns it,
saying so. Accepted only by the client the claim is about, and only in the "on" direction. Covered by
`tests/test_lc_churn.lua`.

## B31 — post-reload recovery hangs on an event that may never come again — FIXED 2026-07-30

`LC.CheckRaidJoin` is wired to `GROUP_ROSTER_UPDATE` only. `PLAYER_ENTERING_WORLD` is registered and
handled but never calls it. If the roster event after a reload arrives while `GetNumGroupMembers()`
is still 0, the exit-confirm branch runs and returns; the re-check a few seconds later sees the raid
again and returns without ever running the in-raid branch. With a static roster nothing else fires,
so `LC_STATE_REQ`, the loot-history catch-up and the session prompt are all skipped. Compounds B30.

**Fixed 2026-07-30.** `PLAYER_ENTERING_WORLD` now calls `LC.CheckRaidJoin` too — the one event a
reload and a zone change always raise. Guarded by a source check in `tests/test_lc_churn.lua`, since
the harness does not load `Core.lua`.

## B32 — handing the lootmaster role over broadcasts nothing — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

Typing a successor's name makes `IsConfigOwner()` false on the outgoing owner's own client, so
`ApplyOwnConfig` wipes `raidConfig` and `CouncilNamesTable` and returns, and `BroadcastRaidConfig`
returns without sending. Peers still name the outgoing owner; the successor's own field does not name
them either. Lands straight in B29.

**Fixed 2026-07-30.** `LC_RESIGN`, sent before the outgoing owner erases its own copy — nothing else
on the wire can express "I am no longer the lootmaster", since a config broadcast is gated on owning
the config, which they have just stopped doing. Receivers clear `raidConfig.lootmaster` and nothing
else, so everyone falls back to the raid leader by derivation until the successor's own config
arrives. Its own token rather than a config with an empty field: an older client would accept that
and record the person stepping DOWN as lootmaster. Covered by `tests/test_lc_churn.lua`.

## B33 — an empty Lootmaster field means no config owner at all — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

`IsConfigOwner()` reads `KART_Settings.lcLootmaster` directly, so an empty field — an explicitly
supported setup per `LC_SET_LOOTMASTER_HINT` — means `ApplyOwnConfig` and `BroadcastRaidConfig` both
return early. `LC.CouncilNamesTable` stays empty on every client, so every listed council member gets
no panel all night, and every client falls back to its own button labels: the B25 vote-label mismatch
by another route. The role-status label meanwhile reports that all is well.

**Fixed 2026-07-30.** `IsConfigOwner` falls back to the raid leader on an empty field, exactly as
`IsLootOwner` already did — the two derivations disagreeing was the bug. The fallback stands down as
soon as somebody else actually claims the role, so it cannot fight a named lootmaster. Covered by
`tests/test_lc_baseflow.lua`.

## B68 — a config a client invented for itself counts as an answer, so it stops asking — FIXED 2026-07-30

`StateStillNeeded()` asked only WHETHER a config is present, never where it came from:

```lua
return LC.sessionActive and next(LC.raidConfig) == nil
```

After a reload the table is empty, the raid-leader fallback in `LC.IsConfigOwner` goes live for a
moment, and `LC.ApplyOwnConfig` writes this client's OWN settings in with `fromSelf` set. From then
on `next(LC.raidConfig) ~= nil`, the question answers "nothing left to ask", and the retry chain
stops for good — while nothing else re-sends a config to a client that has not asked for one.

The client then runs the whole evening on its own settings. The roll setting is the expensive half:
it decides whether that raider rolls at all, so a raider who reloads late simply stops rolling and
nobody, themselves included, has any way to see it. Same cost as B25, reached from a different
direction.

**Measured effect: 12 of 3000 runs disagreed before, 8 after** (the `rollsEnabled` family 9 -> 7,
the `buttons` family 3 -> 1). It is a real improvement and it is NOT the whole story -- see B69.

Found by `tests/test_lc_soak.lua`, which turned it up as 9 of 12 breaks in 3000 runs once two
harness defects stopped hiding it — see the note below. `KART_SOAK_DEBUG=878`: Sinja reloads at the
second-to-last step and ends with `rollsEnabled=false` while every config on the wire carries `1`,
and the run's own settle gives it two roster updates and 120 seconds to correct itself.

The guard now uses the same predicate `LC.HandleConfigRelay` already uses to decide whether an
incoming relay may overwrite what a client holds: `fromSelf` AND no lootmaster named in its own
settings. A leader who typed their own name in the field owns that config on purpose and is not
asking anybody about it.

### Two harness defects were hiding this, and both are worth not re-deriving

* `RaidSim.Leave` removed the client and never reassigned raid lead, so a raid whose leader left had
  **nobody in charge** — a state WoW never produces. With no lootmaster configured the raid leader
  stands in, so a leaderless raid had no loot owner at all, nobody broadcast `LC_START`, and every
  client sat on an item Blizzard had rolled with no vote window. That looked exactly like a protocol
  defect and was written up as one. It was 10 of the 13 breaks, and all of them vanished when the
  harness started promoting somebody.
* The soak's own "is anybody still the lootmaster" check read `if not GetLootmaster()`, which can
  never fire: the function answers `""` and `""` is truthy in Lua. It was also the wrong question —
  an empty field is the NORMAL state of a raid whose leader stands in. It now asserts that at least
  one client answers `IsLootOwner()`, which is what would have caught the leaderless raid at once.

## B69 — a reloaded raid leader answers "start a session?" and pushes its own settings over the raid's — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

The residue of B68: 7 of 3000 soak runs, `KART_SOAK_DEBUG=878`. Traced end to end rather than
guessed at — two guesses about this area were wrong first, and both are recorded below so they are
not made again.

The chain, from the trace:

1. Bramor (the lootmaster) leaves. Raid lead ends up with Merrit, whose own Lootmaster field is empty
   and whose own `lcRollsEnabled` is the default `false`, while the raid is running on `true`.
2. Merrit reloads. Everything runtime is gone: no config, `sessionActive` false, and crucially
   `sessionStateKnown` false — it has asked the raid and nobody has answered yet.
3. Three seconds after the roster settles, `CheckRaidJoin` offers Merrit the session prompt. The
   guard there is `not LC.sessionActive`, which is true — but only because Merrit has not been told
   yet. The state-request backoff is 2/5/15/45 seconds, so the first answer need not have arrived.
4. Merrit answers yes. `sessionStartedByUs` is set, which makes `LC.IsConfigOwner` true for a raid
   leader with an empty field (the fallback B67 deliberately left open for the legitimate case), and
   `BroadcastRaidConfig` puts Merrit's OWN settings on the wire — `rollsEnabled = false`.
5. Sinja, freshly reloaded and holding nothing, accepts it: `TryAcceptConfig` writes `false` and
   clears `fromSelf`, so B68's guard cannot see it either. Sinja stops asking and ends the raid not
   rolling on anything.

`sessionStartedByUs` is asserting something untrue at step 4. Merrit did not start the session the
raid is in; it declared a new one locally because it had not heard about the existing one yet.

### The fix: the session starts at once, the CONFIG waits

Neither of the two obvious directions was taken. Gating the prompt on `LC.sessionStateKnown` is right
in principle and costs the ordinary case — on a genuinely fresh raid nobody ever answers, so the
prompt would wait out the whole backoff (~67 s) where today it appears after 3. Making a later,
truer config win needs a precedence rule receivers cannot always evaluate.

What is in place instead separates the two halves of "yes":

* The session starts immediately. Nothing about the prompt changed.
* The CONFIG is held back, and only when BOTH are true: this client was never told what the raid was
  already running, AND its own Lootmaster field is empty, so its claim rests purely on the raid-lead
  fallback. A lootmaster who names themselves — the maintainer's own setup — is never affected.
* It is released the moment anybody answers (`LC.HandleActive`, `LC.HandleSessionResume`), and
  otherwise after `CONFIG_CLAIM_GRACE` (10 s), at which point the config goes out as normal. A raid
  that IS running answers in under seven seconds; one that does not answer has nothing to say, and
  then these settings ARE the raid's — the documented empty-field setup (B33).

The guard sits in `LC.BroadcastRaidConfig`, not only at the point the session starts: every roster
change re-broadcasts, so a one-off check would be undone by the next person walking in.

**Measured over the same 3000 scripts: 8 runs disagreed before, 3 after.** Both halves of the guard
were mutation-checked: removing the check in the broadcast, and never setting the marker, each turn
the bootstrap test red.

### The last three, and a guard that was already there

Holding the config back stops a client from SENDING an invented one within the grace. It does not
stop one that gets out anyway — seed 1377 is a reload whose replies were swallowed by a chat
throttle, so the ten seconds expired in silence and the client concluded, wrongly, that the raid had
nothing to tell it. "Nobody answered" and "nobody's answer got through" look identical from inside.

`LC.TryAcceptConfig` already refused an unnamed config from a client holding one that named a
resolved lootmaster ("weaker-claim"). That guard could not fire here, and the reason is worth
keeping: a config that arrived through `LC.HandleConfigRelay` carries NO lootmaster, because the
relayer must not write itself in (B65). Blanking that field also strips the thing the guard reads, so
a perfectly good relayed config was overwritten by the first invented one that came along.

The guard now also counts where a config CAME FROM: one we received outranks an unnamed one, name or
no name. A client holding nothing still takes it, so the empty-field bootstrap (B33) keeps working,
and a NAMED config never reaches this check at all — **handing the lootmaster role over is
unaffected**, which is the case that matters most here.

**With that, 0 of 3000.** Across the day the soak went 13 → 0.

Both remaining candidates were then mutation-checked against each other, and the result changed what
shipped: raising `CONFIG_CLAIM_GRACE` from 10 to 30 seconds (to outlast a throttle burst) and the
weaker-claim widening turned out to be REDUNDANT — each alone closes all three cases. Only the
widening shipped, because it addresses the cause and does not depend on a timing window. The grace
stayed at 10, and the reason 30 was tried and rejected is recorded at the constant so nobody retunes
it back on the same reasoning.

**The cost, stated because it narrows a documented setup:** in a raid deliberately run with NOBODY in
the Lootmaster field, the leader's later CHANGES no longer reach clients that already hold a config —
only the first one does. Confirmed with the maintainer (2026-07-30) that this raid never runs that
way: the field always names somebody, and the config is shared in advance with everyone who might
take over.

`tests/test_lc_baseflow.lua`'s B33 bootstrap changed with it, and deliberately: it now asserts that
the config waits AND that it arrives afterwards. The old single assertion could not tell the
difference.

### Two wrong turns, recorded so they are not repeated

* *"The raid holds two incompatible views of the lootmaster."* It does not. The RAW `raidConfig.
  lootmaster` differs between clients, but `PresentLootmaster` blanks a named lootmaster who is no
  longer in the group (B29), so the EFFECTIVE answer agrees everywhere. Read `GetLootmaster()`, never
  the raw field.
* *"Merrit never broadcast a config — the wire only shows relays."* It did. The wire dump truncates
  and the `LC_CONFIG` prefix also matches `LC_CONFIG_RELAY`, so the real broadcast was hidden among
  them. A probe inside `TryAcceptConfig` printed `rolls=0` on the first run and settled it.

## B58 — nobody hands a late joiner the config while the lootmaster is away — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

Follows from B29's fix, and is the price of not letting a stand-in rewrite the raid's settings.
`LC.HandleStateRequest` sends the config only if `LC.IsConfigOwner()`, and while a named lootmaster is
merely absent that is nobody: the stand-in leader owns the loot flow but not the settings, on purpose.
Anyone joining in that window gets the session flag and no config, so they run their own vote-button
labels, minimum quality and roll setting until the lootmaster returns or somebody names a successor.

Fixed by the work done for B65, which asked for the same thing from the other end — a lootmaster gone
for good rather than merely away — and built exactly the mechanism this entry asked for:
`LC.RelayRaidConfig` forwards the config a client is holding instead of broadcasting its own, and
`LC.HandleConfigRelay` accepts it without letting the relayer's name become the raid's lootmaster.
`LC.HandleStateRequest` reaches it through the `elseif` branch that runs when nobody owns the config,
which is precisely this state.

Confirmed rather than assumed: `tests/test_lc_churn.lua` builds the state (named lootmaster leaves,
raid leader stands in, all five clients assert they do NOT own the config), lets somebody join, and
checks they end up on the raid's vote buttons, roll setting and council. Removing the `elseif` branch
turns those three red, along with eleven other assertions and the soak.

## B59 — a lootmaster whose own field does not resolve owns nothing, and is never told — FIXED 2026-07-31

**Most of this went with the ownership rework** (`docs/OWNERSHIP.md`): `LC.IsConfigOwner` reads no
name at all now, so a client whose field cannot be placed loses nothing. What was left is the
designation not taking, on the one client that can fix it -- the config owner types a name, their own
client cannot place it, `LC.GetLootmaster` falls back to them, and they hand out the loot themselves.
Safe, but not what was asked for. It is now said at session start, naming the text that failed.

The trap this entry named is what the fix turns on: `ResolvePlayer` returns a PENDING TEXT key, never
nil, so the check is `IsResolvedKey` rather than a nil test. The test was written first and failed
against the nil version.

`LC.IsConfigOwner` compares `LC.IsMe(declaredKey)` with no fallback, and `KASC.Identity.ResolvePlayer`
returns a pending TEXT key rather than nil for a name it cannot place. A lootmaster who types their
own Northern Sky nickname on a client that cannot read nicknames therefore owns neither the config
nor the loot flow, and the raid leader silently takes both roles. The one warning that would say so
(`LC_LOOTMASTER_UNRESOLVED`) is printed from `LC.SetSessionActive`, which they never reach — they are
not the loot owner, so they are never offered the session prompt either. The only trace is the
role-status label in a settings tab they have no reason to open.

Not fixed by adding a chat warning on sight: the same condition is true, harmlessly and constantly,
for anyone whose Lootmaster field names a person who has not loaded in yet. Wants a rule that can
tell "names me, unresolvable" apart from "names someone else, not here yet".

## B60 — the lootmaster losing Blizzard's roll is undetected — NARROWED 2026-07-30

`ForceWinRoll` rolls and nothing checks the outcome. A raider not running KART can out-roll the
lootmaster; the council still awards, and `Trade.AddPendingTrade` records an obligation for an item
the lootmaster does not have. `Trade.OnTradeClosed` then reads "not in my bags" as "already traded"
and clears the reminder the next time that same winner is traded with for anything at all. The
reminder tidies itself away, the lootmaster believes it is done, the winner never receives anything,
and the history says they won it.

**Half of it is closed.** The obligation was created for whoever was loot owner at award time, and
that is not the same client as the holder once the role moves — the lootmaster force-wins, ports out
mid-distribution, the raid leader stands in, and the stand-in was handed a reminder for an item it
had never had. `LC.rollNotInOurBags` now separates the two: set when a roll is learned from somebody
else's `LC_START`, cleared when we force-win it ourselves, and the reminder follows it rather than
the role. The loot owner is told when one is skipped (`LC_TRADE_NOT_HELD`) instead of it happening
silently. Covered in `tests/test_lc_churn.lua`, including the stale-mark case on a reused rollID;
three mutations, each red on its own assertions.

**What remains is the original half:** the lootmaster force-wins, genuinely loses Blizzard's roll,
and nothing notices. `rollNotInOurBags` cannot see that — from the client's point of view it did
everything right. It wants the roll's actual outcome, which the addon does not currently read.

Settling the holder question was also a precondition for B63: a fallback broadcaster would announce
items the loot owner never won, and without this guard every one of them would have created exactly
this obligation.

## B61 — council membership is only evaluated when the roll starts — FIXED 2026-07-31

`Council.ShowCouncilPanel` is called from the four roll-start sites and nowhere else, and
`LC.IsCouncil()` is read once, there. A client whose config arrives afterwards — a late retry
success, a state-request reply — is council from that moment on but has no tab for the items already
on the table, and cannot assign them. Narrow, because a client that late usually has no tracked items
either, but real for one that already had them.

## B62 — a client on the previous release rejects everything a stand-in or a successor sends — MITIGATED 2026-07-30

`LC_SESSION_RESUME` is a new token (`LC_RESIGN` was one too, and the ownership rework removed it), and an older client drops an unknown token
silently. So a v3.2.1 client keeps naming a lootmaster who has left or stepped down, which makes
`IsSenderLootOwner` reject every `LC_START`, `LC_ACTIVE` and `LC_END_ROUND` from whoever actually
took over — no vote window on any item, for the rest of the raid, with nothing printed on either
side.

**Not fixed, and cannot be:** the broken half is running code we cannot change, so the raid still has
to be on one version. What changed is that it is no longer a mystery. `LC.PROTOCOL_VERSION` names the
release the wire protocol requires (3.2.2, where those four tokens landed), `LC.OutdatedRaiders`
answers who in the group is below it, and the loot owner is told — once per name — when the session
starts and again whenever a peer's version arrives. `/kart status` carries the same list for
everybody, because the person pasting that output is usually the one who cannot see an item.

Three deliberate omissions, each of which would otherwise produce a false alarm on a screen that has
to stay worth reading: ourselves (we never process our own version broadcast, so there is no entry),
anyone with no version entry at all (no KART, or simply no hello yet — the council panel already
marks that per row and this warning cannot tell the two apart), and anyone whose Loot Council module
is switched off, since their client neither sends nor rejects anything.

The hook is Core.lua's `KASC:OnPeer` handler rather than `GROUP_ROSTER_UPDATE`: a version arrives
asynchronously, well after the join that asked for it, so the roster event knows nothing yet.

Watch when raising the floor: `LC.PROTOCOL_VERSION` is a hand-maintained constant and must move only
when a release genuinely changes the wire, never with every version bump — pointing it at the current
version would name every raider who simply has not updated a patch release yet, and the warning would
stop being read.

## B63 — one broadcaster: if the loot owner gets no roll event, nobody sees the item — NARROWED 2026-07-30

`LC_START` for a real drop is sent from exactly one place, inside the loot owner's own
`START_LOOT_ROLL` handler. The owner is subject to the same conditions as everyone else — out of
range, ineligible, released — and there is no fallback broadcaster. Meanwhile every other client's
Auto-Pass still fires, because that branch does not depend on the owner having acted. Visible outcome
is identical to "nobody stood in": Blizzard's window opens, every KART user passes, no vote window
anywhere.

**Still one broadcaster.** A fallback broadcaster was designed and rejected: announcing an item the
owner never rolled on produces a vote whose winner can never be handed the item — a decision nobody
can execute, which is exactly the trap the collectible carve-out exists to avoid. So the item still
does not reach the council when the owner misses the event.

**What was fixed is the loss.** Auto-Pass no longer fires on faith. It passes only once the council
demonstrably has the item, so when nothing is announced Blizzard's window is left alone and the raid
rolls on the item the way it would without this addon — instead of every KART user passing at once
and handing it to whoever is not running the addon.

The pass now runs from whichever of the two paths completes the pair, so arrival order does not
matter: `LC.rollAnnounced` (the owner's `LC_START` landed) and `LC.rollSeenHere` (we have processed
our own roll event). The second is not bookkeeping for its own sake — answering a roll makes
Blizzard's API go blank for it, so passing from a message that beat the local event left
`OnStartLootRoll` with no quality, no bind flag and no link, and it returned before the 1-100 roll.
The base-flow tests caught that during development; do not remove that condition.

Below the raid's rarity threshold nothing changed: the council never announces those, so there is
nothing to wait for and making Auto-Pass wait would leave a rare on everyone's screen forever.

**Known cost, accepted deliberately.** A client whose `LC_START` was swallowed by the chat throttle
now keeps its roll window instead of passing, so an Auto-Pass raider could in principle click Need on
an item the lootmaster has already force-won. Bounded — the owner rolled Need too, and an Auto-Pass
raider is by definition somebody who does not click loot windows — and much smaller than an item lost
by the whole raid passing at once. B66's catch-up covers the deaf client when a state request follows.

After a wait derived from the owner's own link-retry budget (not a hand-picked number: they can
legitimately spend that whole budget before sending anything), a client that heard nothing says so
and names the item. Only Auto-Pass users are told — they are the ones whose expectation was not met
and who are now looking at a window they have to answer themselves.

## B64 — before the first config, the leader and the lootmaster both believe they own the loot flow — SUPERSEDED 2026-07-31 by the ownership rework

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

No config is on the wire until a session starts, so until then every client has
`raidConfig.lootmaster == ""` and the raid-leader fallback is live on the leader while the lootmaster's
own field makes them the owner too. Both are offered the session prompt; whoever answers first
decides. It converges once a named config lands (a named lootmaster now outranks an empty-field
claim, see B29/B33), but the window is real and the loser of the race spends it with
`sessionActive == false`.

---

# Tier B — an item is lost or awarded wrongly, silently

## B34 — a reload mid-roll loses the item entirely — NARROWED 2026-07-30, and the entry above was wrong

Only `KART_LCTrades` and `KART_LootHistory` are SavedVariables, and `Trade.RestorePersistedTrades`
only rehydrates decided trades. Everything about an undecided roll — item link, votes, deadlines,
tabs — is in memory only. The lootmaster force-wins a Bind-on-Pickup item, reloads before the council
assigns, and `START_LOOT_ROLL` will not fire again: they hold a real item that no client, no saved
variable and no window still associates with a roll.

**Measured, and the paragraph above overstates it.** The council's award DOES still reach a reloaded
lootmaster: `Trade.HandleResult` rebuilds the item link from the broadcast payload and creates the
trade obligation, in the split raid as well as the simple one. Probed before anything was changed.

**What was genuinely lost was the CLOCK, and that is what loses items.** Blizzard's Bind-on-Pickup
trade window is four hours of *wall* clock from the moment the item was looted. `LC.rollLootedAt` was
memory-only, so after a reload both `Trade.AddPendingTrade` and the winner's `owedToMe` entry fell
back to `time()` at AWARD time — a countdown that started when the boss died restarted from zero.
KART then promised hours that did not exist and would warn about a deadline already past. Exactly the
failure `Trade.PruneExpiredLootStamps` documents for a cleared stamp; a reload did the same thing to
it. **Fixed:** the stamps persist alongside the two trade lists in `KART_LCTrades`, pruned by the
same four-hour rule and rebuilt defensively on load.

The harness could not have caught this before, because `time()` was `os.time` and no test could
advance a wall clock. It is now offset from `KARTTEST.now` like every other clock.

**Still open, deliberately:** the reloaded lootmaster's own vote row and council tab do not come back,
so they cannot vote on or award an item they are holding. Another council member can, which is the
normal case. It only becomes a dead end when the lootmaster is the *only* council member left, and
`/kart add` is the manual way out. Restoring the windows means persisting open rolls or widening who
may answer `LC_ROLL_CATCHUP` — `HandleStart` requires `IsSenderLootOwner`, and that trust is not
worth widening casually. Its own task.

**Also found on the way:** a raider who reloads has no council list until the next roster change, and
`Trade.HandleResult` refuses an award from a sender it cannot confirm is council — so an award landing
in that gap is dropped entirely, with no owed entry and no history. A raid produces roster changes
constantly, so the window is short, but it is real. Not fixed here.

## B35 — two council members can award the same item at the same time — FIXED 2026-07-31

Resolved by a rule every client applies to (what I hold, what just arrived) and reaches the same
answer from in either order: a DELIBERATE reassignment outranks a first award, and otherwise the
smaller winner key wins. Arbitrary on purpose -- neither council member is more right than the other,
and what the raid needs is one answer, not the better one. Both halves are commutative, which is what
makes the arrival order irrelevant; the test asserts exactly that rather than asserting a winner.

`LC_RESULT` carries a reassign flag for it. That is the one thing a receiver cannot work out for
itself, and it is what separates a confirmed reassignment from two people clicking at once.

**Harness:** `RaidSim.Hold`/`Release` had to be added -- this could not be built before. `Blackhole`
models a message that is LOST; peers were delivered to immediately, so the second assigner always saw
the first one's decision and took the reassign path, which is the opposite of the case.

Not independently reachable, and kept as hygiene rather than covered: clearing the rank in
`Trade.ClearRollState`. Every write path sets the rank alongside the winner, so a stale rank is
overwritten before anything reads it.


Assigning is deliberately open to the whole council, and `Trade.AssignWinner`'s only double-assign
guard reads `LC.assignedWinners[rollID]` locally. Addon messages never echo to their sender, so two
assigners each see nil, each broadcast, and each overwrite the other's record on receipt. Both clients
end up permanently disagreeing about the winner, and what actually gets traded is whichever message
reached the lootmaster last.

## B36 — "irrelevant" is far wider than the setting claims — FIXED 2026-08-01

`irrelevant = not canNeed` treats every reason Blizzard disables Need as "your class cannot equip
this": wrong loot specialization, level requirement, unique-equipped. `reasonNeed` sits in the same
return and is discarded. A Holy Paladin with hiding on never sees a strength plate chest they would
have taken for off-spec — the exact case the feature was designed to keep visible (GitHub issue #11).
The same expression turns an unknown `canNeed` into "irrelevant", which the file's own header forbids;
`needsAppearance` on the same line resolves unknown the safe way.

## B37 — the relevance snapshot outlives the roll it describes — FIXED 2026-08-01

`Trade.ClearRollState` deliberately keeps `relevanceSnapshot`, arguing the relevance frame has already
snapshotted the new item. That holds for the `LC.OnStartLootRoll` caller and not for `LC.HandleStart`,
which exists precisely for clients that got no local `START_LOOT_ROLL`. A raider who was dead for the
reused rollID gets the previous item's verdict applied to the new one — a best-in-slot piece
auto-passed without ever being drawn.

## B38 — the snapshot records no item identity, and is written for rolls Council ignores — FIXED 2026-08-01

The `START_LOOT_ROLL` handler has no `councilEngages` gate, and `LC.OnStartLootRoll` returns before
`PurgeStaleRoll` for rolls Council does not engage. So a trash Bind-on-Equip drop or collectible
reusing a live rollID silently rewrites the snapshot of the item currently being voted on, and nothing
purges it. Those are exactly the items trash drops constantly.

## B39 — the appearance fallback answers the wrong question — FIXED 2026-08-01

`NeedsAppearance`'s non-snapshot path asks "do I already own this appearance", never "can I collect
it": the sourceID from `C_TransmogCollection.GetItemInfo` is discarded and `PlayerCanCollectSource` is
never called. It is consulted only for items the player cannot equip — the population where the two
questions diverge — so it can broadcast a Transmog vote on an appearance that character can never
learn, and the council may award the item on the strength of it.

---

# Tier C — one player drops out of the round

## B40 — a "???" item link permanently blinds the reused-rollID detector — FIXED 2026-07-31

`LC.HandleStart` builds the link only from `GetLootRollItemLink`, which returns nil for a dead or
out-of-range client, and `ResolveRollItemLink` retries the same nil-returning API and gives up — even
though the `LC_START` payload carried the itemID, which the code parses and then never uses to rebuild
a link (`Trade.HandleResult` performs exactly that rebuild). `"???"` fails `IsRealItemLink`, so
`PurgeStaleRoll` bails for the rest of the session and every per-roll table survives into the next
item: the raider's row shows an old vote and they can never vote again.

## B41 — the voted-items filter removes the row the correction lives on — FIXED 2026-08-01

`Vote.GetVisibleRolls` tests `LC.votedByMe[rollID]` raw, without the `not isAuto` exemption both row
renderers apply. With "voted item display = hide" an auto-cast Transmog vote removes its own row on the
next refresh, so the hint "click any response to change it" points at a button that is not on screen —
and unticking the hide setting does not bring an auto-passed row back either, contrary to the guarantee
stated in that function.

## B42 — snapshots are swept before the vote row they belong to exists — FIXED 2026-08-01

The self-sweep protects `rollID` itself and entries in `LC.voteListRolls`, but on a non-lootmaster
client a roll only enters that list when `LC_START` arrives — one round trip after the local
`START_LOOT_ROLL`, by which time Auto-Pass has blanked `GetLootRollItemInfo`. On a multi-item boss each
roll's snapshot is deleted while handling the next one, so only the last item keeps Blizzard's verdict
and the rest fall through to the armor rule, which answers nil for weapons and jewellery.

---

# Tier D — the wrong thing is displayed

## B43 — the vote-count guard is length-only — FIXED 2026-07-31

`voteData.count` catches a change in the number of buttons, not a same-length rename or reorder. The
config owner editing labels mid-roll pushes the new set live, and votes cast before the edit are then
rendered under whatever the label became, with no "unknown" fallback.

## B44 — the council tab tooltip skips the guard entirely — FIXED 2026-07-31

It resolves `buttons[tonumber(voteData.idx)]` without reading `voteData.count`, so it states a label
with full confidence for the same vote the row list below it correctly renders as "?".

## B45 — the voter's own badge has no guard at all — FIXED 2026-07-31

`votedDef` is resolved against whatever `GetButtonConfig()` returns right now, with no stored count.
After a mid-roll label edit the raider is told they voted something they did not.

## B46 — a late vote is accepted onto a reused rollID — FIXED 2026-07-31

`Vote.HandleVote` and `Vote.HandleCouncilVote` check only that *some* item is tracked under the rollID,
not that it is the same one. A network-delayed vote for the previous item lands in the new item's tally.

---

# Tier E — cleanup, cosmetics, narrow triggers

## B47 — expired pending trades are pruned only by a reload — FIXED 2026-07-31

`Trade.CheckTradeTimeouts` warns and never removes; the only pruning happens in
`Trade.RestorePersistedTrades` at `ADDON_LOADED`. Hours past Blizzard's real trade window, dead entries
still sit in the reminder list, indistinguishable from live ones.

## B48 — a self-assigning council member gets no reminder — FIXED 2026-07-31

`LC.owedToMe` is populated only in `Trade.HandleResult`, i.e. only on a client that *received* the
broadcast. A council member who assigns an item to themselves never processes their own message and so
never gets their own "you are owed this" entry, though the lootmaster's queue is correct.

## B49 — hiding every row stops the pruner — FIXED 2026-08-01

The window hides when `GetVisibleRolls` comes back empty, and `OnHide` cancels the ticker that is the
only thing calling `Vote.PruneExpiredRolls` during a batch. The rolls never expire and never reach
`Trade.ClearRollState`; `/kart showall` later reopens long-dead rolls with live vote buttons.

## B50 — `relevanceHandled` ignores the settings that produced the answer — FIXED 2026-08-01

The latch is permanent per roll, so ticking the other switch mid-batch does nothing for rolls already
answered — the setting appears inert and the broadcast Pass stands.

## B51 — `/kart lc` shows frozen hidden rows — FIXED 2026-08-01

That path calls `voteListFrame:Show()` directly with no refresh, so the pool still holds the last drawn
layout: a window full of items the player was told were hidden, with stopped countdowns, until the
ticker's first prune hides it again.

## B52 — an accepted config does not repaint an open council panel — FIXED 2026-07-31

`LC.HandleConfig` omits the `RefreshCouncilPanelIfOpen()` call its own retry path makes, so a council
member keeps seeing votes under the old label set until some unrelated event refreshes the rows.

## B53 — a legacy note beginning with a hash and digits is misparsed — FIXED 2026-07-31

`ParseVotePayload`'s count disambiguator can match a pre-3.1 client's note, truncating it and
fabricating a count the sender never sent — which then either wrongly trips or wrongly satisfies the
mismatch check.

## B54 — auto-answers rebuild the window once per roll, nested — FIXED 2026-08-01

`ApplyToPendingRolls` runs at the top of `RefreshVoteListRows`, and `CastVote` ends in
`RefreshVoteListRows`, so N simultaneous auto-answered drops produce N nested full rebuilds in one
frame. Bounded and correct, but a visible hitch exactly when the window first appears.

## B65 — once the lootmaster is gone for good, a later arrival gets no config at all — FIXED 2026-07-30

Standing in deliberately moves only the LOOT FLOW, not the config: the departed lootmaster's name
stays in `raidConfig.lootmaster` so they can pick the role back up when they return. Nobody owned the
config while that was true, so nobody re-broadcast it, and anyone joining afterwards ran the evening
on their own vote buttons, minimum quality and roll setting — their vote reaching the council under a
different label than they clicked.

Fixed with `LC_CONFIG_RELAY`: whoever still holds the config the raid agreed hands it on, in reply to
a state request, with the lootmaster field EMPTY — "here is what the raid settled on", not "and I am
in charge of it", so ownership stays derived and the real lootmaster reclaims it by coming back. The
receiver's rule is what makes it safe from any sender: it fills a void, or replaces a config the
client invented from its own defaults (the raid leader after a reload, see below). It can never
replace a config that was received or that its owner declared.

Two things surfaced underneath it, both fixed here:
* With the config owner gone, a reload cleared `raidConfig` and left `IsConfigOwner`'s `fromSelf`
  guard nothing to bite on, so the raid leader silently became the config owner and wrote their own
  defaults — usually rolls off and an empty council list — into the raid's config.
* The state request stopped once the SESSION flag was known, so a client that learned the session and
  missed the config never asked again. It now asks while either is missing.

## B66 — an item announced while a client is deaf — NARROWED 2026-07-30

`LC_START` and `LC_RESULT` are announced once and never re-requested. A client is deaf for two
ordinary reasons: it is still recovering from a reload (it has asked for the state and is waiting),
or Blizzard's chat throttle dropped the message.

**Rolls now have a catch-up.** The loot owner lists the rolls still open when it answers a state
request (`LC.SendOpenRolls` / `LC_ROLL_CATCHUP`), so a client that was deaf gets its vote row back
and the council gets an answer from it after all. What keeps that from breaking the rule about late
arrivals is the receiving side: the roll is rebuilt only if Blizzard gave *this* client the same
roll, which is its own proof of having been in the raid when the boss died. A client that already
answered has no roll left either, so an item it has decided is not put back in front of it.

**Two halves remain open:**

* `LC_RESULT` has no equivalent. An award announced while a client could not authorise the sender
  — its council list had not arrived — is missing from that client's loot history, and
  `LH.RequestHistorySync` only runs on join. A history catch-up on *rejecting* a result would close
  it.
* The loot owner's own deafness cannot be repaired by anyone. Blizzard offers no way to enumerate
  the rolls currently open, so a lootmaster that reloads and misses a drop cannot ask for it back —
  it can only recover fast enough not to miss it. That is what the 2-second first retry and the
  raider-supplied session resume are for. Narrowed, not closed.

`tests/test_lc_soak.lua` excludes exactly these windows from its per-item comparison, and says so
where it does it — everything with a retry behind it is still held to the full standard.

## B67 — a reloaded raid leader replaced the raid's settings with its own — FIXED 2026-07-30

Found by `tests/test_lc_soak.lua` seed 254. With the lootmaster gone for good nobody owns the config,
and the raid leader reloads. Their `raidConfig` comes back empty, which leaves the `fromSelf` check in
`LC.IsConfigOwner` nothing to look at, so the empty-field rule made them the config owner:
`LC.ApplyOwnConfig` wrote their own defaults in — rolls off, empty council list — and
`LC.BroadcastRaidConfig` sent those to the raid as the real thing.

It only half-landed, which is what made it expensive. Clients that still remembered the previous
lootmaster rejected it as a weaker claim; anyone who had joined or reloaded since took it. The raid
split down the middle over its own settings and the half holding the leader's defaults stopped
rolling.

Fixed with the distinction `fromSelf` was reaching for and could not survive a reload: did we START
this session, or did we walk into one. `LC.sessionStartedByUs` is set where the flag is decided
(`LC.SetSessionActive`) and cleared where it is merely learned (`LC.HandleActive`,
`LC.HandleSessionResume`, the raid-exit teardown). The raid-leader fallback claims the config only in
the first case — which keeps B33's documented empty-field setup working, because there the flag is
set one line before it is read.

Note for anyone re-deriving this: the guard looks inert in a hand-built scenario, because a council
member relays the raid's config the instant it is asked and heals the leader before it can do damage.
It is load-bearing only when the config is slow or lost, which is why its test forces that ordering
by blackholing `LC_CONFIG_RELAY`. Removing the guard turns four assertions red.
