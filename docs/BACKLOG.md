# Backlog — known defects, not scheduled

Defects found while working through the v3.0.0 library extraction and the raids after it, each with
a traced cause rather than a guess. This file exists so the diagnosis is not redone from scratch.

Companion to `MANIFEST.md` (the core functions and the 10-out-of-10 standard they are held to) and to
`REVIEW-DECISIONS.md`, which records findings deliberately **not** changed. This file
records findings that *should* change, eventually. An entry is deleted once it is fixed — the code
and its comments carry the diagnosis from then on, and `git log --grep=Bnn` finds the commit.

Client-version work lives in `BACKLOG-12.1.md` instead: what the 12.1 client changes underneath KART,
numbered `Pn`, held until the last 12.0.7 raid is over.

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

### Answered 2026-08-03, both halves

**The rule, from the maintainer:** a late arrival is not handed a running item — *"der ist ja nicht mal
lootberechtigt"*. It is now enforced where it can actually be known: `LC.rollEligible[rollID]` records
the roster at the moment the owner announces, and every catch-up path requires a strict yes before
answering (B118). A manually added item is covered by the same record, which is what the Blizzard check
could never do for it.

**And "the plain raider was sent a catch-up and did not apply it" is explained.** It was
`LC.HandleRollCatchup`'s own guard, `if not GetLootRollItemLink(rollID) then return end`: after a
reload that answers nil, so the catch-up was discarded by the client that had asked for it. The guard
was the entitlement proof, and now that entitlement is decided by the sender it is gone. Measured
against no live raid yet — the suite covers it, the Manifest counts C8 in the game.

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

## B111 — FIXED 2026-08-01 — the two lists that define a roll agreed only by hand

Raised while reading LootCouncil.lua's unpushed diff. `PERSISTED_ROLL_TABLES` carries the rule in a
comment -- "Add to ClearRollState and this list wants the same entry" -- and nothing checked it. A
rule that lives only in a comment is kept until the first person who does not read it, and it fails
quietly: the new table is simply not restored, so after a reload one aspect of an item on the table
is blank while everything around it is right, weeks after the line that caused it was written.

Both lists are read out of the source and compared now. It immediately found three tables that
`ClearRollState` clears and the snapshot does not carry -- and all three turn out to be right to
leave out, which is the answer worth having written down: `equipRequestedRolls`, `rollsPendingSince`
and `pendingItemLoads` are in-flight markers rather than state, and restoring them would do harm
rather than nothing. A restored "we already asked this raider for their gear" would stop the question
ever being asked again, leaving the council panel's equipped column empty for the session.

The comment also claimed "minus three" where it is five, and named `relevanceSnapshot` among them --
which is not in `ClearRollState` at all.

## B112 — FIXED 2026-08-01 — a loot-history entry could be too long to sync, and was simply lost

Seventeenth bug run: the same mutation sweep as B107, over the modules the first sweep did not cover.
82 survivors, mostly display colours and nil guards -- and two identical `if #msg > 255` in the
history catch-up, which is the same shape as B107 with the same consequence.

`LH.HandleHistoryRequest` sends one `LC_HIST_ENTRY` per award and has two fallbacks for the byte cap:
swap the full item link for the compact item string, then send an empty item field. The comment on
the second states the outcome as fact -- "the entry still syncs; the item just shows blank" -- and it
did not hold. Over the cap NOTHING arrives, so the award was missing from that peer's history with
nothing said on either side.

Reachable from the ordinary settings box, not from an edge case. The reason is a vote-button label,
the field limits those to 128 LETTERS, and a German label spends two bytes on every umlaut -- so
"Zweitspec für Nebenrolle über Mainspec" style labels produce entries that fit `LC_RESULT` (fewer
fields) and not `LC_HIST_ENTRY`. The reason is cut to fit now, on a character boundary, because the
receiver stores whatever arrives and the history window renders it.

**The test for it was wrong twice before it was right**, and both are worth recording:

* it first walked 25 REASON lengths, which moves nothing: the amount to cut is
  `(fixed part + reason) - 255`, so the reason cancels and the cut lands at the same offset into it
  every time. A probe printed the byte class it landed on -- "lead" 25 times out of 25. Walking the
  WINNER NAME is what moves the cut across character boundaries.
* with only umlauts it still could not tell the two-byte rewind loop from the single lead-byte step,
  because for a two-byte character they do the same thing. Three-byte characters (the euro sign is
  one, and item names carry it) separate them.

All three guards turn the suite red when removed, one per guard.

## B113 — FIXED 2026-08-01 — the catch-up's two unheld guards, one with lasting damage

From the same sweep as B112. Both could be removed without the suite noticing.

**A timestamp from the future.** `time()` is each client's OS clock. An entry dated years ahead is
not just a wrong row: `LH.RequestHistorySync` asks for everything newer than the newest entry it
holds, so that date becomes the watermark and every later request asks for entries newer than a date
nobody reaches. Catch-up is dead on that client for good, and nothing says so -- one raider with a
badly set clock is enough. Held on both sides now: years ahead refused, two minutes of ordinary drift
accepted (drift between two raiders must not cost an award), and the client demonstrably still asks
from a reachable date afterwards.

**How much one answer may be.** Without the entry cap a peer holding a long history puts one whisper
per entry on the wire because one raider walked in.

Three assertions of mine were fixed with it, and the mistake is the one this whole stretch keeps
finding: `RaidSim.Sent` returns log ENTRIES, so `#msg` measured an array with no elements -- always 0,
always under the cap, an assertion that cannot fail. Caught only because another test in the same
file crashed on the same confusion. `test_lc_churn` and `test_lc_soak` had it right already.

## B114 — NO DEFECT 2026-08-02 — the third 255-byte site, and a mutant that marks unreachable code

The equipped-item exchange (`REQ_EQUIP` / `EQUIP`) is the addon's third message-length site, after
the raid config (B107) and the history catch-up (B112) -- and the only one that resolves it by
DROPPING the message rather than shortening it. That is correct here and would be wrong there: a
missing comparison renders as "no data", while a missing award is gone from the record.

Two guards had no test and now do: the per-slot answer cooldown (the panel refreshes on every
incoming vote, and without it every raider answers every refresh), and the compact-link fallback --
measured, a max-crafted link is 309 bytes and the reply still goes out in 57, because
`KAUtil.GetItemString` keeps the item id and drops the bonus list the length came from.

**The drop itself cannot be tested, and that is the finding.** With any real item link the fallback
always produces something short, so `if #msg > 255 then return end` is unreachable. Its mutant
survives for that reason -- not because a test is missing. Worth writing down as a third category
alongside "real gap" and "equivalent mutant": a survivor can also be marking defensive code that
nothing can reach, and chasing it is time spent on an assertion that could never fail.

## B117 — NARROWED 2026-08-05 — the twentieth run's leftovers, re-measured against a file that moved

The original entry (2026-08-02) listed 64 surviving line numbers across `LootCouncil.lua` and
`LootCouncilVote.lua`. **Those numbers are gone from this entry, and deleting them is the finding.**
49 commits went over `LootCouncil.lua` between then and now — the comms rework, AceComm, one message
per boss, the heartbeat, LibDeflate, B127/B130/B135 — and the file went from 3678 lines to 5261. Every
number in that list pointed somewhere else. They were evidence that a measurement had happened, not a
worklist, and keeping them would have cost the next session an afternoon before it noticed.

What does not age is a cluster named after the function it lives in. That is how this entry is
written now.

**Re-measured 2026-08-05 against `f47b239`,** with `tests/mutrun.py` (in the repo, `tests/mutrun.py`
— an earlier note claiming it lives in a temp directory was wrong):

| file | executed | mutable | alive |
|---|---|---|---|
| `LootCouncil.lua` | 1501 | 130 | 59 |
| `LootCouncilVote.lua` | 665 | 40 | 18 |

`LootCouncilVote.lua` was re-measured after B118 landed, because B118 rewrote it — 260 lines of vote
heartbeat, a wire format carrying several votes at once, and `LC_VOTE_REQ` gone. Re-measuring rather
than carrying the older figures forward is the whole point of this entry; the alternative is another
list of numbers that describe a file nobody has any more.

Two further "survivors" in the first run were prose: the rules matched an arrow inside a trailing
comment (`-- resolved KASC.Identity key -> true`), mutated the comment, and reported a green suite.
Fixed in `tests/mutrun.py` rather than written down as findings — the same discipline as B115, where
13 of 17 discrepancies turned out to be the harness.

**Cluster 1, the state-request answers — CLOSED.** `LC.HandleStateRequest` has one rule that matters:
exactly one client may state the raid's config *as* the raid's config, and that is whoever the
lootmaster field names. Everybody else answers with `LC_CONFIG_RELAY`, which a receiver accepts only
into an empty config and which therefore cannot overwrite or clear anything. Two mutations walked
straight through it. Dropping the ownership self-gate in `LC.BroadcastRaidConfig` turns every
session-active client into a second voice, and it is the roster-change path that makes it bite —
that one calls the broadcast with no ownership test of its own, deliberately, *because* the
broadcast self-gates. Losing the branch that picks relay over broadcast costs the backstop instead:
the raid keeps its config and the next person to ask gets nothing. Both are held now in
`tests/test_lc_churn.lua`. B130 is why this got more important, not less: a relay now carries a
statement about the lootmaster, and a state report is a relay.

**Cluster 2, the retry budgets — measured, and the answer is that this tool cannot ask the
question.** `LC.RetryPendingConfig`'s own cap is held: its `attempts >= PENDING_CONFIG_MAX_ATTEMPTS`
comparison dies against the suite. The survivors around `START_ROLL_MAX_ATTEMPTS`, `ROLL_CATCHUP_MAX`,
`ROLL_REQ_COOLDOWN`, `TABLE_RESEND_SECONDS`, `ROLL_ORPHAN_GRACE`, `SESSION_RESTORE_MAX`,
`PACK_MAX_MESSAGE`, `PACK_MAX_BLOCK` and `WIRE_HEADROOM` are all the same shape: the operator set can
only turn `<` into `<=`, which moves the edge by one attempt or one second and leaves the bound
standing. "Runs forever or not at all" is not reachable that way, and nobody in a raid can tell twelve
retries from thirteen. **Ungemessen**, not a gap — and re-deriving that is what this paragraph is for.

**A fifth kind of survivor: a guard written twice.** The loot owner must not answer "your session is
still running", and `LC.HandleStateRequest` says so before scheduling the delayed answer and again
inside it. Break either comparison and the other one holds, so both are reported alive and neither is
a hole. Same shape in `LC.SendTableHeartbeat`, whose ownership check is repeated by the ticker that is
its only caller. This joins the four in B115/B116 (real gap; equivalent by construction; defensive
code nothing reaches; a comparison whose equal case an enclosing guard excluded). The rule for the
next run: before writing a survivor down, look for the same test one frame up.

**Recorded, not chased.** The `LC_LOOTMASTER_CLASH` warning gate (a message, no state) and the choice
between answering at once and answering jittered — the second is a message-volume decision and a
wrong answer costs whispers, not correctness. And roughly eight survivors of the form `#list > 0`
mutated to `>= 0`, every one of them on a display or `/kart status` path: the empty case is never
exercised, which is true and cheap and not what an evening is for.

**Skip.** Most of `LootCouncilVote.lua` is the vote window drawing itself — thresholds and nil guards
on widget plumbing. Its unit lookup in the vote handler is known and is NOT a gap: `LC.IsSenderLootOwner`
on the next line refuses everything the lookup would have let through. Recorded in the bug-run-20
commit; do not re-chase it.

**B118's new code, measured on arrival, and clean.** Three survivors are in the vote heartbeat and its
wire format, and all three are non-gaps. `#parts >= VOTES_MAX_ENTRIES` lets one extra vote into a
message when its edge moves — it never drops one, and the packing measures the finished message
anyway. `noteLen > #payload` in the parser cannot reach its equal case: the entry's own header stands
in front of the note, so the length is always strictly smaller. `pos <= #payload` differs only on a
single stray byte in a payload that is already damaged. Worth stating because a fresh format is
exactly where a real framing gap would be, and this one does not have one.

## B116 — CLOSED 2026-08-05 — LootCouncilTrade.lua swept at last, and Core.lua held where it can be

The sweep the entry below asked for, run on 2026-08-05 against `f47b239`: **474 executed lines, 31
mutable, 14 alive** — the same 31 candidates as on 2026-08-02, three fewer survivors, and this time
every one of the fourteen is accounted for rather than counted.

**Closed by tests written here:**

* **The award clash message.** `kept = incomingWins and winnerKey or held` mutated to `or` makes
  `kept` the boolean `true`, and the line then names `true` as the winner the raid kept. A second
  mutation widened the guard above it, putting a red line about a conflict nobody can act on in front
  of every raider instead of the two screens that decide and hand the item over. Both lived because
  `tests/test_lc_award.lua` reached the first 24 characters of `LC_AWARD_CLASH` and stopped — the
  text in front of the first placeholder. Held now by the fixed text that FOLLOWS the last
  placeholder (taken from the locale string, so it holds in either language) and by attributing each
  printed line to the client that printed it.
* **One copy of a duplicate confirms one entry.** `remaining > 0` in both directions —
  `Trade.OnTradeClosed` on the giving side and `Trade.ConfirmOwedFromPartner` on the receiving one —
  mutated to `>= 0` and nothing noticed. The comment above that line already describes exactly what
  it costs: two pending entries sharing an item string are indistinguishable, so a completed trade
  carrying ONE copy must confirm one of them; confirming both hands the raider one item while both
  screens call it dealt with, and the second is never traded and never missed. The bag scan cannot
  cover it, because a copy is still sitting in the bags. This is B60's silent loss, reached a third
  way. Held now in `tests/test_lc_tradefill.lua` and `tests/test_lc_reload.lua`.

**Not gaps, and why — so this is not re-derived on the next run:** the `< / <=` on the assignment
tie-break sits inside `if held and held ~= winnerKey`, so the equal case cannot arise (the fourth
kind of survivor, named in the entry below). The nil guards on `KART_Settings`, `LC.owedReminderFrame`
and `KART.LH` are defensive code the harness cannot reach. The trade-timeout boundaries
(`TRADE_TIMEOUT_SECONDS`, `TRADE_TIMEOUT_WARN_AT`) and the stale-stamp cutoff move by one second on a
float clock. The `#LC.pendingTrades > 0` pair is the reminder window's own display path. All
**Ungemessen or Kein Loch**, none worth an evening.

**Core.lua — the standing rule held, and it had drifted.** The file still reports zero executed lines
and does not appear in the coverage report at all, so `tests/test_core_wiring.lua` remains the only
thing that can hold it. The comms rework added five call sites there and the wiring test covered
three. The `GUILD_ROSTER_UPDATE` branch was asserted as registered and routed but never as *doing*
anything, and a plain source search could not tell an empty branch from a wired one because the same
call also stands in the `KASC:OnPeer` handler — that assertion is scoped to the branch now.
`PLAYER_ENTERING_WORLD`'s `RetryPendingResolutions` was not asserted at all; the existing line names
the throttled variant, a different call at a different site, and the un-throttled one covers the
client that loaded LAST, for which no other addon ever finishes loading. **The rule stands: anything
new in `Core.lua` gets a line in that file in the same commit.**

## B116 — the original entry, 2026-08-02 — LootCouncilTrade.lua has never been swept, and Core.lua cannot be

The nineteenth bug run, over the files today's B60 and B66 work touched. Two things came out of it
that are not about those fixes.

**Core.lua reports zero executed lines.** The harness does not load it — it needs the game to exist —
so every line of event routing in that file is invisible to the suite AND to the mutation sweep. The
answer is not to load it: it is `tests/test_core_wiring.lua`, which asserts the exact registrations
and calls against the source text. B60's own wiring went in without that check and had to be added
afterwards, which is the second time this file has caught a feature that was one event name away from
doing nothing while its own tests stayed green. **Anything new in Core.lua wants a line there in the
same commit.**

**LootCouncilTrade.lua has 31 mutable executed lines and 17 survivors**, and it has never been part of
a sweep — B107 and B112 covered other modules, B115 covered five more. Not chased here, because that
is a bug run of its own and this one was scoped to today's changes. Three of the seventeen are worth
starting with:

**`:857` is closed as of 2026-08-02.** `confirmedByBags = LC.IsRealItemLink(entry.itemLink) and not
FindItemInBags(entry.itemLink)` is the exact "not in my bags" reasoning B60 is about, and nothing
held the `and`. With an `or` there, any trade with that partner clears the obligation while the item
is still sitting in the bags — which is the silent loss B60 describes, reached from the other side.
Held now in `tests/test_lc_tradefill.lua`: a trade that carries nothing leaves the item owed.

**`:1023` is an equivalent mutant, and the proof is three lines up.** `incomingWins = winnerKey < held`
sits inside `if held and held ~= winnerKey`, so the two are never equal and `<` and `<=` cannot
disagree. Worth writing down rather than re-deriving: this is the fourth kind of survivor after "real
gap", "equivalent by construction" and "defensive code nothing reaches" — a comparison whose
equal case an enclosing guard has already excluded.

**Still open: `:1028` and `:1029`,** the award-clash message. `kept = incomingWins and winnerKey or
held` mutated to `or` makes `kept` the boolean, so the line names the winner that was kept as
`true` — the message is informational, but it is printed on the two screens that can act on a clash
and naming nobody is worse than not printing. `:1028` decides when the line is printed at all.
Neither is chased here; both want a test that drives two council members awarding one roll to
different winners in the same moment, which is B35's scenario.

Two survivors are in code written today and both are recorded rather than chased:
`LootCouncilTrade:954` is `KART.LH or KART.LH.NoteUnauthorisedAward`, which cannot differ because
`KART.LH` is always truthy by the time that line runs — the same equivalent-in-effect shape as
`:982` and `:1251` in B115. `LootHistory:1021`'s cooldown boundary IS now held: a request exactly a
minute after the last one is allowed, because a distribution runs far longer than that.

## B115 — NO DEFECT 2026-08-02 — the eighteenth bug run found no bug, and three lies in the harness

The same mutation sweep as B107 and B112, over the same five modules, after the tests those runs
produced. 96 candidates, and **not one of them was a defect** — every survivor marked an assertion
that was missing over code that turned out to be right. Nothing reached the changelog, because
nothing changed for a player.

That is worth recording precisely because the three runs before it each found something. A sweep
that comes back empty is the expected outcome eventually, and mistaking it for "the tool stopped
working" is how a run gets abandoned one round before it would have paid off again.

The confirmation sweep afterwards: 138 mutable executed lines, 93 dead, 45 alive.

| module | mutable | dead | alive |
| --- | ---: | ---: | ---: |
| Invite.lua | 12 | 12 | 0 |
| BuffChecker.lua | 32 | 29 | 3 |
| LootCouncilSettings.lua | 6 | 5 | 1 |
| LootHistory.lua | 42 | 28 | 14 |
| LootCouncilPanel.lua | 46 | 19 | 27 |

**The panel is where the next run starts.** Nineteen of forty-six is the worst coverage of the five
by a wide margin, and what survives there is not scattered: the equipped-item exchange's nil guards
and the test-roll row, both of which need a fixture that does not exist yet.

**Three lies in the harness, all the same shape.** Each was a convenient answer that made the branch
under test unreachable, so the assertion could not be written at all — the same failure the frame
catch-all's own comment calls the most expensive one in the harness:

* `SetTextColor` / `SetVertexColor` / `SetDesaturated` went to the catch-all and did nothing. Colour
  IS the answer in the buff grid: the durability column says 19% in red and 51% in green with the
  same three digits, and a missing buff is a red icon while a column nobody in the raid can fill is
  a dim one.
* `GetWidth` answered 0 for every frame. The buff check truncates each name against its own
  `GetWidth()`, so every name in every test was cut down to "..." and the whole binary search was
  unassertable. A size that was set is answered with now; one that never was is still 0.
* `RAID_CLASS_COLORS` answered EVERY key with white, so "this client does not know that class" could
  not happen. It is an ordinary state — history entries outlive expansions in a SavedVariable and
  the class arrives from a peer as a bare string — and two different screens colour a name by it.

**Two of my own assertions could not fail, and both are one mistake:** measuring a COUNT where the
defect changes a VALUE.

* five seconds of clock skew leaves one history row whether the arriving award is recognised as a
  duplicate or REPLACES the row it matched — same roll, same item, so nothing stacks. What separates
  them is whose timestamp survives.
* "hold one entry, expect one entry" is also what a whisper that never arrived looks like. Every
  such test needs a control that proves delivery before it asks for nothing to happen.

Neither showed up as a failure. The mutant is what said so, which is the argument for running the
sweep against new tests rather than trusting them green.

**What survives, and why none of it is a gap.** Recorded so the next run does not re-chase them:

* *provably equivalent* — `LootHistory:1008` and `:1048` compute the same answer either way (a
  maximum, and a trim that takes exactly the whole list); `BuffChecker:938` leaves a negative
  remaining, which is not "expiring" on either side.
* *only differ on invalid input* — the three UTF-8 rewinds (`BuffChecker:680`, `LootHistory:1119`
  and `:1123`) turn on byte 0xC0, which valid UTF-8 never contains (leads are 0xC2–0xF4);
  `BuffChecker:678` and `LootHistory:1117` need a string that opens with a continuation byte.
* *equivalent in effect* — `LootHistory:917`, `:982`, `:1251` and `:1256` cost an extra call into a
  function that guards itself (`LH.Refresh` returns immediately with no window).
* *harmless boundary* — the 255-byte guards choose the shorter of two item forms one byte earlier.
  The entry still arrives.
* *unassertable, not unheld* — `LootHistory:653` differs only in where the window ends up, and the
  harness deliberately answers "I do not know" for a frame's position.
* *noise* — `LootCouncilSettings:170` mutates a `->` inside a trailing comment. The runner skips
  whole-line comments but not trailing ones.

The runner itself now lives at `tests/mutrun.py` instead of a temp directory, with what it needs and
what must not run beside it in the header. `tests` is in `.pkgmeta`'s ignore list, so nothing there
reaches the packaged addon.

**One thing to know before writing a test against the buff grid:** `KART.BuffStatesCache` is wiped
before EVERY player (`BuffChecker.lua`, the per-unit loop). Reading it after a render shows the last
raider in the roster, never the player — the player's own answer is only on their row. That cost a
detour here and will cost the next one the same.

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

## B60 — the lootmaster losing Blizzard's roll is undetected — ANSWERED 2026-08-02; IRRELEVANT IN AN ORGANISED GUILD, by the maintainer's call (NARROWED 2026-07-30)

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

**The original half is answered as of 2026-08-02, and needs proving in the game.** The roll's actual
outcome IS readable: `C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)` carries the
`winner` of every drop (name, GUID and an `isSelf` flag) along with `allPassed`, and
`LOOT_HISTORY_UPDATE_DROP` fires with both ids when one resolves. Verified against the generated API
annotations shipped with the ketho.wow-api extension, which are for 12.0.1 while the live client is
12.1 — one minor version back, and per the maintainer 12.1 changed little, so this is a solid source
rather than a guess. What it still is not is a run in the game.

`LC.HandleLootHistoryDrop` reads the drop, and tells the loot owner when the winner is somebody else
and the item is one this client rolled on. Held by `tests/test_lc_lostroll.lua`: the line names the
winner and the item, is said once per drop rather than once per update of it, and is not said when we
won, when everybody passed, when the item is one the council never took up, when the reader is not
the loot owner, or when the roll was learned from somebody else's `LC_START`.

**Where the match is loose, and why it is allowed to be.** Blizzard's `rollID` and the loot history's
`encounterID` + `lootListID` are different id spaces with no documented bridge — Blizzard's own
LootHistory frame works purely in the latter and never mentions a roll id. So the drop is matched by
ITEM STRING (`KAUtil.GetItemString`, the same comparison `Trade.GetDuplicateOrdinal` and
`LH.HandleHistoryEntry` use), and two identical tokens off one boss would match the same one.

Comparing the raw links instead would have been the worse mistake, and a code review caught it: the
two sides come from different producers — ours from `GetLootRollItemLink`, Blizzard's from
`C_LootHistory` — and a link carries a colour escape that different client versions write
differently (`|cffa335ee` against `|cnIQ4:`, documented next to `KAUtil.GetItemString`). One byte
apart and the whole feature is a silent no-op, which looks exactly like the state before it existed
and so would never have been reported.

**Two records are consulted, not one, and the second is the load-bearing one.**
`Vote.PruneExpiredRolls` frees `LC.rollItems` once the VOTE window closes — twenty seconds by
default — for any client holding no council tab, and tabs exist only for council members. A
lootmaster who is not in the council list is an ordinary setup (this release's own changelog says the
raid leader is not in it automatically), and Blizzard resolves a group-loot roll long after twenty
seconds. Matching only against `LC.rollItems` would have left this feature structurally dead in that
whole configuration. `LC.pendingTrades` outlives it: it is the promise the warning is actually about,
it carries the item link, and it lives as long as the four-hour trade window.

That is why this only ever prints. Marking the roll as not-held on a link match would take a trade
reminder away from an item the lootmaster really is holding, turning a rare miss into a routine one.
A false positive costs a glance in the bags; a false negative is exactly the state before this
existed. Nothing about the distribution is decided from here.

**Priority, settled by the maintainer on 2026-08-02: irrelevant in an organised guild structure.**
Every route to this failure needs somebody in the raid answering Blizzard's roll window by hand —
Auto-Pass switched off, the Loot Council module switched off, or an `LC_START` lost to the chat
throttle. KART is mandatory for this guild, and a member who breaks that on a raid night does not
stay in the guild. The technical routes are known and are not the point: the social rule is the
enforcement, and it is stronger than the code could be.

The detection is kept because it is already written and costs nothing — it prints one line and
changes no state, so it is inert when it never matches. What it does NOT justify is further work:
do not build roll-outcome handling out into anything larger, and do not raise this entry as an open
risk again.

**Still to do in the game if this is ever exercised, and it cannot be done anywhere else:** confirm the event fires for group
loot in 12.1, that `lootListID` is stable across the updates of one drop, and that the item hyperlink
matches the one `GetLootRollItemLink` gave us for the same item. The harness can only prove the
addon's own reasoning about the answer; it invents the answer itself.

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

**Raised to 3.3.0 on 2026-08-02, deliberately against that rule, and the reason is worth keeping.**
The branch had run 70 commits past 3.2.2 while both the `.toc` and the floor still said 3.2.2, so two
builds that behave nothing alike would have reported the same version to each other and
`LC.OutdatedRaiders` — the one check meant to tell the loot owner who cannot take part — could not
have told them apart. The diff was measured first: no new wire token and no new send site, so by the
letter of the rule the floor should have stayed. It was moved anyway, by the maintainer's decision,
because what changed is the shared flow — who owns the council list, what survives a reload, what the
history catch-up carries — enough that a peer left on 3.2.2 is worth naming before the first boss.

The rule itself stands. This is the exception it is measured against, not a precedent for moving the
floor with every release: the next bump wants the same measurement, and the same argument made out
loud, or it should not move.

## B63 — one broadcaster: if the loot owner gets no roll event, nobody sees the item — NARROWED 2026-07-30; remainder OPEN BY CHOICE, re-checked 2026-08-02

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

**Re-checked 2026-08-02: nothing here is waiting to be done.** Both halves that were fixed are held
by `tests/test_lc_autopass.lua` — nobody passes an item the council never took up and Blizzard's
window is left live for them, and after the wait the item is named to exactly the people it affects
and to nobody else. What is left is not an open defect but the rejected design: a second broadcaster
would announce items the loot owner never won, and a vote whose winner can never be handed the item
is a decision nobody can execute. Filed under choice, not under work.

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

## B34 — a reload mid-roll loses the item entirely — FIXED 2026-08-02, the last of it by B81 (NARROWED 2026-07-30, and the entry above was wrong)

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

**Both remainders are closed as of 2026-08-02.** They were written here on 2026-07-30 as "still open,
deliberately" and "not fixed here", and that wording outlived the work that closed them — which is
its own lesson about leaving a residual paragraph in an entry whose heading has moved on.

*The reloaded lootmaster's vote row and council tab* were the whole subject of **B81** two days
later, and the fix went the other way from the one guessed at here: not persisting open rolls into
the protocol or widening who may answer `LC_ROLL_CATCHUP`, but each client keeping its OWN tracked
rolls in SavedVariables and picking them up at load (`LC.SaveSessionSnapshot` on `PLAYER_LOGOUT`,
`LC.RestoreSessionSnapshot` at `ADDON_LOADED`). No protocol change and no rule about late arrivals,
because a client can only ever restore what it already had. Held by `tests/test_lc_reload.lua`: the
reloaded lootmaster still has the tab, knows which item it is, has all five votes back, and
`ReopenTrackedWindow` gets them to it — which is the report itself, "`/kart lc` opens nothing".

*The award landing while a reloaded raider has no council list* does not happen. `LC.IsSenderCouncil`
answers on `LC.IsSenderLootOwner` FIRST and only then consults `LC.CouncilNamesTable`, so an award
from the loot owner needs no council list on the receiving side at all. Measured rather than reasoned
about: a plain raider reloads, no roster update is allowed to run, the lootmaster assigns, and the
award arrives as both an owed entry and a history row. That assertion is in `test_lc_reload.lua` now,
because the guard it depends on is one line and nothing else was watching it.

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

**The first of the two remaining halves is closed as of 2026-08-02.** `LC_RESULT` had no equivalent:
an award announced while a client could not authorise the sender — its council list had not arrived —
was missing from that client's loot history for the rest of the evening, because
`LH.RequestHistorySync` runs once per raid JOIN and nothing else asks.

Measured first, because the shape had narrowed since this was written: the loot owner is authorised
with no council list at all (`LC.IsSenderCouncil` answers on `IsSenderLootOwner` before it consults
the table — see B34), so the case is an award from a council member who is NOT the loot owner,
reaching a client that has reloaded and is still waiting for the config. A test reproduces exactly
that and was red.

Closed the way the entry itself proposed: the rejection asks. `LH.NoteUnauthorisedAward` is called
from `Trade.HandleResult` where the result is dropped — the one moment a client knows for certain
that an award exists which it does not have. Delayed five seconds, because the config that would have
authorised the sender is usually seconds behind and asking after it lands costs nothing; and
rate-limited to once a minute, because a client whose config never arrives sees a whole distribution
it cannot authorise, and one request per award would put the raid's history on the wire over and over
for nothing — the answer to the first already carries what the later ones would ask for. Both
properties are held: the award arrives, and four unauthorised awards in a row produce one request.

**The second half stays open — but its stated reason is out of date as of 2026-08-02.** It read:
*"Blizzard offers no way to enumerate the rolls currently open, so a lootmaster that reloads and
misses a drop cannot ask for it back — it can only recover fast enough not to miss it."* That was
written on 2026-07-30, before anyone had looked at `C_LootHistory`.

Looking it up for B60 turned that claim over. `C_LootHistory.GetAllEncounterInfos()` lists the
encounters, `GetSortedDropsForEncounter(encounterID)` lists each drop in one with its
`itemHyperlink` and this client's own `playerRollState`, and `GetSortedInfoForDrop` gives the roll
in full. A loot owner coming back from a reload could therefore ask BLIZZARD what dropped and what
it did with its own roll, instead of depending on a peer to tell it — which is the dependency this
half of the entry is entirely about.

**Not built, and not to be treated as settled either way.** What is written above is read off the
generated API annotations for 12.0.1 (see B60 for the same caveat), and three things would have to
hold before it means anything: that the encounter is still listed after a reload, that a drop the
council never announced is distinguishable from one it did, and that `playerRollState` says
something useful for a roll this client force-won before the reload. None of that can be answered
outside the game.

Until then the recovery is unchanged: the 2-second first retry and the raider-supplied session
resume. What has changed is that "cannot be closed" is no longer the right words for it — it is
"not attempted, on a lead that is one in-game session away from being worth something".

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

---

# The live raid test, 2026-08-03

The first full evening on 3.3.0 with the whole guild, run against `MANIFEST.md`. Fifteen reports from
the raid plus GitHub issues #18–#25 reduce to the nine entries below — every report is mapped in a
heading, so nothing is filed twice under two names.

**Two Manifest items failed outright: C5 and C11.** The run is recorded in `MANIFEST.md`'s standing
result table, with what it did and did not reach.

Where a cause was traced to the line, it says so. Where it is still a hypothesis, it says that too and
names the measurement that would settle it — the evening ended before the send probe could be run, and
guessing past that point is how B70 cost three attempts.

## B118 — FIXED 2026-08-03 — a lost addon message costs the item, and nothing in a running session notices

**All three halves are fixed, the vote last, at the bottom of this entry.**

*The item.* The loot owner now broadcasts what is on the table every ten seconds while anything is on
it (`LC_TABLE`), a client missing one of those rolls asks for it (`LC_ROLL_REQ`, at most once per roll
per 30s), and the owner answers with the catch-up that already existed. `LC.HandleRollCatchup` no
longer demands that Blizzard gave this client the same roll — that demand was the defect: it threw the
catch-up away on exactly the clients that needed it (dead, released, out of range have no roll either)
and could never be satisfied at all by a manually added item.

*Who may be caught up.* Entitlement moved to the one client that can know it. `LC.rollEligible[rollID]`
records the roster at the moment the owner announces, and both catch-up paths require a strict yes
before answering — **the maintainer's rule, 2026-08-03: a late arrival is not handed a running item,
"der ist ja nicht mal lootberechtigt".** A roll with no record is refused rather than given the benefit
of the doubt. This is also what finally closes B79.

*End Round.* Sent three times over five seconds instead of once, and the repeat is dropped if an item
has appeared in the meantime.

**The half that was designed, written, and taken back out before it ever ran:** the heartbeat's
mirror image, "you are holding a card I did not list, drop it". It loses a whole distribution in the
case this guild has every raid — the lootmaster ports out mid-round, the stand-in's own table is empty
at that moment, and one heartbeat from them would tell every council member to drop the item they are
voting on. C5 and C11 broken by the mechanism meant to protect them. **Deletion has to come from
somebody deciding it, never from somebody else's silence.** Do not re-propose it; that is what the End
Round repeat is for.

The convergence soak caught the first version of the repeat immediately (seed 93): a roll starting
inside those five seconds was cleared off every peer while the sender kept it. 2000 seeds clean after
the guard.

Held by `tests/test_lc_table.lua`, and by `tests/test_lc_persistedtables.lua` for the new per-roll
table — an owner who reloads mid-round without `rollEligible` would refuse every catch-up for the
items still on their own table.

*The vote, and it is the fourth measurement in the table below.* Four raiders pressed a button and the
council never saw it — settled the same way as the item and End Round above: repeat it until it is
seen, rather than ask for it once and hope the ask arrives. Every client now repeats its own votes on a
heartbeat (`LC_VOTES`), bundled across every roll it is still tracking rather than one message per vote,
phased from the client's own position in the roster so the whole raid does not answer in the same
instant. `LC_VOTE_REQ` is gone with it — there is nothing left to ask for, because the vote itself keeps
arriving. A receiver only ever adds a vote it does not already have, never removes one, for the same
reason deletion stays out of the item heartbeat above.

### The original diagnosis, kept for the measurements

Reports #1, #7, #11, #13, #15; GitHub #18, #19, #21, #25. The most expensive defect of the evening, and
the reason four different symptoms looked like four different bugs.

**Four measurements, three different messages, three different clients:**

| lost | what was seen | what it proves |
|---|---|---|
| `LC_END_ROUND` | a council member's `/kart status` listing tabs `1,2,3,4,5,6,7` — the same items three times over, after three `/kart add` rounds with End Round pressed between them | his client never cleared. `LC.EndRound` sends once and clears itself locally; there is no acknowledgement and no second attempt |
| `LC_START` ×3 | KART's own `LC_ROLL_UNANNOUNCED` printed three times in one second on a raider's screen | that line only prints when `LC.rollAnnounced[rollID]` is still false `ANNOUNCE_WAIT` (45s) after this client's OWN roll started, with the roll still live |
| `LC_START` ×1 | a raider had no vote card for *Endless March Waistwrap* while other raiders did; Blizzard's window stayed up, and Auto-Pass had passed the same boss's other three items for him | the message reached the raid and not him. Also rules out the min-quality branch (`LootCouncil.lua:3052`), which would have passed it silently instead |
| `LC_VOTE` ×4 | four raiders confirmed, asked directly, that they pressed a button; the council panel showed `-` for all four | their clients recorded the vote locally and told them "Voted: …". Nothing on either screen said it had not gone out |

**Which side loses it.** The loot owner's own card is built locally (`LootCouncil.lua:3117-3122`), never
from the wire, so the lootmaster seeing an item proves nothing about delivery — that was checked, and
briefly mis-scored during the evening. It was settled by asking the raid: **other raiders did have the
belt's card.** So the send succeeded and one recipient lost it. A sender-side throttle cannot explain
that case, whatever it may explain about B120.

**Three ways a receiver drops it, all silent:**

* the dispatcher's group gate, `KAUtil.IsFullNameInGroup(sender)` (`KASC-1.0.lua:300`) — a roster that
  is briefly stale discards the real sender's message;
* `LC.IsSenderLootOwner` (`LootCouncil.lua:707-722`) — a lootmaster key that has not resolved yet
  refuses everything. The affected client printed `Council: 2 resolved, 3 not yet matched` in the same
  status (see B126);
* Blizzard simply not delivering to a client on a loading screen or zoning — which the operating
  reality in `MANIFEST.md` guarantees will happen every evening.

All three end in a bare `return`. Nothing anywhere counts them, so from outside they are
indistinguishable, and the first fix is therefore not a fix.

**The shape of the fix, in order:**

1. **Count the drops and print them in `/kart status`** — per gate, per session. No behaviour change.
   One raid then says which of the three it is, instead of another evening of inference.
2. **Recovery must not hang on `LC_STATE_REQ`.** `LC_ROLL_CATCHUP` already exists and already solves
   this (B66) — it is only ever triggered by a client that joins or reloads. A client that stays put
   and misses a message has no way back to the item at all. A periodic "what is on the table?" while a
   session is active covers every cause above without needing to know which one it was.
3. **End Round needs the same treatment from the other end**: a round/generation number carried on the
   messages that follow, so a client that missed the end learns it from the next message it does get
   rather than never.

Note for whoever builds (2): a manually added item cannot prove entitlement the way a real drop can —
`HandleRollCatchup` asks Blizzard for the roll, and `/kart add` items have no Blizzard roll. B79 records
that problem and the rule decision it needs; this entry does not re-open it.

## B119 — FIXED 2026-08-03 — items arrive without their bonus IDs, so half the raid votes on a different item

**Fixed the same evening.** `LC_START` and `LC_ROLL_CATCHUP` now carry the full item string
(`LC.ItemPayload`), the receiver rebuilds from that string rather than from the id inside it, and both
resolver paths follow. A bare id is still accepted on the way in, so a raid running two builds for one
evening does not lose the item on the older half — and the payload falls back to the bare id when the
string would push the message past 255 bytes, because a lossy item beats a dropped message.

The wire format changed, so `LC.PROTOCOL_VERSION` moves to 3.3.1 with it: a 3.3.0 client cannot parse
the new payload at all, and `/kart status` naming them is how that gets noticed in ten seconds instead
of over an evening (B62).

Held by `tests/test_lc_itemwire.lua`, which needed the harness to learn something first: its item
database was keyed on the bare id, so both forms of the same item answered with the same link and no
test could see this defect. `def.baseIlvl` now models the base variant, opt-in per fixture item, and
one assertion in the file exists purely to prove the harness can tell the two apart — without it every
other assertion there would also pass on the old payload.

**Still owed:** an in-game confirmation. The Manifest counts C5 and C12 in the raid, not in the suite.

Report #12; GitHub #20, #22, #23. Measured from a screenshot: the vote window's tooltip read
*Light's March Bracers, **Item Level 44**, Item ID 249326* next to an equipped 285 — the base version of
the item, with base stats and base item level.

`LC_START` carries `rollID:seconds:itemID` and nothing else (`LootCouncil.lua:3101`). Every client that
does not get its own `START_LOOT_ROLL` rebuilds the link from that bare ID (`LootCouncil.lua:3341`, and
the same fallback again in `ResolveRollItemLink`, `LootCouncil.lua:2702`). An itemID alone carries
neither bonus IDs nor upgrade level, so those clients render a different item than the one on the floor.

Three consequences, all reported separately during the evening:

* the tooltip and the ilvl column state a level nobody in the raid is looking at;
* the Droptimizer gain column stays empty — that lookup is bonus-ID exact (`KAUtil.GetItemString`), and
  a base link never matches a sim entry;
* a set token "is not shown, or another item replaces it" (GitHub #22), the same defect on the item
  class where it is most visible. That one also touches **C12**.

**The constraint on the fix, and it is the whole difficulty:** the itemID fallback exists because of
GitHub #12, #13 and #16 — items rendering as `???` with no name and no icon, reported by three people
out of one raid. The comment at `LootCouncil.lua:3329-3342` names those issues. A fix that carries bonus
IDs must keep the name-and-icon behaviour, or it trades this defect back for the older one.

The manual path is the working precedent: send the full link, fall back to the compact item string only
when the 255-byte cap would be hit (`LootCouncil.lua:3458-3465`) — and `KAUtil.GetItemString` keeps the
bonus list, so even that fallback is bonus-exact.

## B120 — FIXED 2026-08-03 — the handshake is announced once, in the noisiest minute of the evening

**Fixed the same evening**, on both halves.

*Answering:* the `KA_HELLO_REQ` responder now takes the per-asker answer cooldown the four other
responders have always had, and answers in its own slot inside a three-second window. The slot comes
from a hash of the client's own NAME rather than from `math.random` — random draws collide, every
raider's name is different, and a deterministic slot is the only version of this that can be asserted
at all (it also keeps the suite's random stream where `tests/test_lc_churn.lua` needs it, see the note
in `tests/run.lua`). Cooled per asker rather than per token, because unlike the four broadcast
responders a hello can be answered by whisper to exactly one client — a shared cooldown would silence
every asker after the first.

*Asking:* `KART.RequestMissingHellos` (Utils.lua), hung on the roster event through a 15-second
leading-edge throttle. It asks only about peers with no version recorded, so it goes quiet the moment
the table is complete — which is what makes it affordable on an event that fires all evening. Two
shapes on purpose: more than five unknown is one broadcast (formation, or our own reload — whispering
two dozen people there would BE the burst), a handful is one whisper each (the ordinary mid-evening
loss, which nobody else needs to hear about).

Held by `tests/test_hello.lua` and the wiring line in `tests/test_core_wiring.lua` — Core.lua cannot be
loaded by the harness, and this feature is one missing call away from doing nothing while its own
tests stay green.

**Still unmeasured, and deliberately left that way:** whether the losses were the throttle at all. The
send probe never ran. B118's counters answer it from the next raid without anyone having to type
anything, and this fix is worth having either way — nothing here depends on the cause being the
limiter, only on answers not arriving.

Reports #8 and #9, which are one marker and not two: the red `!` on a council row IS the
`LC_STATUS_NO_KART` warning (`LootCouncilPanel.lua:1062-1063`).

Every council panel in the raid showed `NO KART DETECTED` on nearly every row while the whole raid was
demonstrably running 3.3.0 (`/kart status`: *Raiders below KART 3.3.0: 0*). **One `/kart v` cleared it
raid-wide**, and it stayed clear — measured during the evening. So reception, parsing and rendering are
sound; the data had simply never arrived.

`KA_HELLO` is the only token in `KASC` with **no answer cooldown and no jitter**
(`KASC-1.0.lua:488-494`). The four tokens that do have one carry the reasoning in a comment right above
them (`KASC-1.0.lua:338-346`): one request answered by twenty clients in the same instant overruns
Blizzard's rate limiter, which drops the overflow silently, and nothing retries. KART asks exactly once
per channel change (`Core.lua:330-341`) — i.e. during raid formation, when every other client is doing
the same thing.

**Unmeasured, and cheap to measure:** whether the drop is the throttle. `C_ChatInfo.SendAddonMessage`
returns `Enum.SendAddonMessageResult` (12.0.1 annotations; `AddonMessageThrottle = 3`,
`ChannelThrottle = 8`) and `KASC:Send` throws it away (`KASC-1.0.lua:40-42`). Reading it costs three
lines, proves or kills this entry, and is the same hook a send queue would need anyway.

Fix: cooldown and jitter on the `KA_HELLO` answer, and a re-request that is not tied to a channel change.

## B121 — FIXED 2026-08-03 — a client with no roll of its own never rolls, and its row stays empty all evening

**Fixed the same evening.** `LC.HandleStart` now casts this client's own roll too, so the path that
exists specifically for clients Blizzard gave no roll to finally produces one. `RollForSelf` refuses to
draw twice for the same roll, which is what makes it safe to call from both start paths — on a client
that gets Blizzard's event AND the owner's announcement they both run, and a second draw would replace
a number the raid has already been shown, on the screen that decides who gets the item.

The raid-wide rolls setting still gates it (`LC.GetRollsEnabled`): the new call site must not become a
way around a raid that has the feature off.

Held by `tests/test_lc_rolls.lua`, which asserts the absent raider's number reaches every client and
that all of them agree on it — two council members scoring a tie-break differently is the failure this
is really about.

**Not addressed here:** `LC.OnStartLootRoll` still returns early while `LC.sessionActive` is false, so
a client whose session flag is out of step is silent on its own event. It now rolls from the
announcement instead, which covers the case in practice, but the session flag going out of step is
B118's territory and not a roll problem.

Report #3, reported twice now ("Rolls werden **wieder** nicht für jeden Char angezeigt").

`RollForSelf` is called from `LC.OnStartLootRoll` (`LootCouncil.lua:3111`) and from
`LC.HandleManualStart`. It is NOT called from `LC.HandleStart` — the handler that exists precisely for
clients Blizzard gave no roll to (dead, released, out of range, ineligible), as its own comment says
(`LootCouncil.lua:3329-3335`). `OnStartLootRoll` additionally returns early while `LC.sessionActive` is
false (`:2968`), so a client whose session flag is out of step is silent too.

Those raiders are then permanently absent from the tie-breaker the council reads, with no way to tell a
missing number from a low one. Note the interaction with B118: a lost `LC_START` produces the same empty
column, so the two are told apart by WHICH raiders are affected, not by the symptom.

The Manifest gains an item for this — see C13.

## B122 — FIXED 2026-08-03 — the second item into a trade window is a race, and the harness always lets it win

**Fixed the same evening.** `Trade.OnTradeShow` counts the slots it has placed into itself instead of
asking the client, exactly the way `usedSlots` already tracked bag slots two lines above. The client's
answer is still consulted — a slot the player filled by hand is still occupied — but it is no longer
the only source.

The harness learned the timing rather than gaining another assertion against the old behaviour:
`KARTTEST.tradeSlotLag` holds a placement until the next `AdvanceTime`, which is what the live client
does. Off by default, so every test written before this keeps meaning what it meant.

Reports #5 and #10. Seen failing early in the evening (two items won, one placed) and succeeding later
the same evening with the same shape — which is the finding: it is timing, not logic.

`Trade.OnTradeShow` looks for a free slot with `GetTradePlayerItemLink(i)` immediately after the previous
iteration's `ClickTradeButton` (`LootCouncilTrade.lua:785-793`). The real client only fills that slot
once the server answers, so on a slow answer the second item resolves to slot 1 again and swaps the
first back out. `tests/test_lc_tradefill.lua` states the assumption in its own header — *"The harness
fills a trade slot the INSTANT ClickTradeButton is called"* — so the suite can never see this.

The follow-on is report #10: an item that never entered the window is never in
`LC.tradeWindowItemStrings`, so `Trade.OnTradeClosed` cannot tick it off, and the lootmaster's list keeps
an obligation that was already handed over — or drops one that was not.

Fix: count the slots this function has placed into itself rather than asking the client, exactly the way
`usedSlots` already tracks bag slots two lines above. The harness change is to stop answering instantly,
not to add another assertion against the current behaviour.

## B123 — FIXED 2026-08-03 — the council panel reopens itself on every roster change

**Fixed the same evening.** The panel records that the player put it away (`OnHide`, so every route
out counts — the Close button, the window's x, Escape), and `Council.ShowCouncilPanel` no longer forces
it back on screen for an item it is already showing. A genuinely new item clears the flag, and so does
`/kart lc`, which is somebody asking for it by hand.

B61's catch-up is untouched: a client whose config lands late still gets its tabs built. It just does
not get the window pushed into its face for the twentieth time.

Report #6: a council member votes on everything, closes the panel, and it is back immediately.

The config owner re-broadcasts on every roster change — deliberately, and the comment says so
(`LootCouncil.lua:912`). The receive path accepts it unconditionally, with no "this is the config I
already hold" short-circuit, and ends in `LC.OnConfigAccepted` → `LC.CatchUpCouncilPanel` →
`Council.ShowCouncilPanel` → `panel:Show()` (`LootCouncil.lua:1344-1350`, `:1399-1412`,
`LootCouncilPanel.lua:297`).

B61 is why that chain exists — a client whose config lands late IS council from that moment and needs the
items already on the table. The defect is that it cannot tell that case from a config it has held for
twenty minutes. In this guild's raids people port out and relog constantly (`MANIFEST.md`, operating
reality), so the panel reopens over and over.

Fix: catch up only when membership or the tracked set actually changed, and never re-show a panel the
player closed while its tabs are unchanged.

## B124 — FIXED 2026-08-03 — guild ranks are read from data nobody asked the client to load

**Fixed the same evening.** `KART.RequestGuildRoster` (throttled to Blizzard's own ten-second limit)
runs from the council panel's row refresh, and `GUILD_ROSTER_UPDATE` redraws the rows when the data
lands — asynchronously, long after the rows were first drawn, which is why asking alone would not have
been enough. Display only, no wire traffic. Wiring held by `tests/test_core_wiring.lua`.

Report #4. The council panel reads `select(2, GetGuildInfo(unit))` per row
(`LootCouncilPanel.lua:1082`, `:1117`) and renders `-` when that comes back nil.

For units other than the player, that call answers only once the client holds guild data. KART never
requests the roster and never listens for `GUILD_ROSTER_UPDATE` — not one occurrence of either in the
tree, harness stub aside. So the column is filled only for people who happened to have their guild frame
open, which is exactly the reported pattern: missing for the raid, present on some screenshots.

Fix: request the roster once when the panel is first built, and refresh the rows on
`GUILD_ROSTER_UPDATE`. Display only, no wire traffic.

## B125 — FIXED 2026-08-03 — the owed-items window cannot be closed

**Fixed the same evening.** Both reminder windows get the same header close button every other KART
window has (`KAUI:CreateHeaderIconButton`). Closing hides and nothing more — the list is the
obligation, not the window — and `/kart trade` / `/kart owed` bring it back rebuilt.

The reporter's second guess was right and is a different entry: while an item is never ticked off, the
window has nothing to empty itself with. That is B122.

GitHub #24. `CreateReminderFrame` builds a title and rows and no close button at all
(`LootCouncilTrade.lua:491-528`). The frame is in `UISpecialFrames`, so Escape closes it; nothing on
screen says so, and the reporter's reading — "no x, probably because the items are never handed over" —
is what any raider would conclude.

It is also downstream of B122: while an obligation is never ticked off, the window has nothing to empty
itself with, so the two read as one bug from the outside.

Fix: the same close button every other KART window has (`KAUI.CLOSE_BUTTON_GLYPH_SIZE`), and a decision
about what closing it means — "hide until the next change" or "stop reminding me this session". The
reminder windows deliberately refuse to reopen themselves today
(`Trade.RefreshTradeReminderIfShown`), so that answer has to be written down rather than assumed.

## B126 — FIXED 2026-08-03 — identity resolution is never retried when NSRT finishes loading

**Fixed the same evening.** `ADDON_LOADED` for any OTHER addon now re-runs the pending resolutions
(throttled), and a delayed pass follows the login/reload branch of `PLAYER_ENTERING_WORLD`. Both are
moments a nickname source can appear without the roster moving, which was the whole gap: the retry
hung on `GROUP_ROSTER_UPDATE` alone, so what actually healed it in the raid was an unrelated roster
change that happened to follow.

Wiring held by `tests/test_core_wiring.lua`; Core.lua cannot be loaded by the harness.

Report #2, and visible in the same `/kart status` as B118: **`Council: 2 resolved, 3 not yet matched`**.
Reported as "a council member could only be resolved after opening and closing NSRT once".

`Identity.GetNickname` reaches into NSRT's `NSAPI` global and returns nil while that addon has not set it
up yet (`KASC-1.0.lua:99-108`). Nicknames are how this guild names people in the council and lootmaster
fields, so a client that starts before NSRT is ready holds plain text where everyone else holds keys. The
retry pass (`LC.RetryPendingResolutions`) is driven by `GROUP_ROSTER_UPDATE` and by nothing else —
opening the NSRT window is not a roster change, so what actually healed it was whatever roster event
happened to follow.

Unresolved keys are not cosmetic: they are what `LC.IsSenderLootOwner`, `LC.IsSenderCouncil` and the
vote/roll lookups compare against, so this feeds B118's second gate and leaves rows blank that are merely
unmatched.

Fix: retry on `ADDON_LOADED` for the optional dependency as well, and once more a few seconds after
`PLAYER_ENTERING_WORLD` — both are moments a nickname source can appear without the roster moving.

## B127 — FIXED 2026-08-05 — GetItemString returned a prefix of the item string, and its comment said otherwise

Found while fixing B119, not reported by anybody — which is the concerning part.

`KAUtil.GetItemString` matches `(item:[%-%d:]+)`. That character class has no comma in it, and a live
Midnight link carries commas inside its bonus list (`…:14:8:11946,10390,12043,…`, the shape the harness
fixture takes from a real loot history). So the match stops at the first comma and the function returns
`item:249326::::::::80:268::14:8:11946` — the item id, some of the modifiers, and exactly one bonus id
out of seven.

Its own comment claims the opposite: *"Full item string (itemID + every bonus ID)"*. B114 recorded the
truncation as a length measurement — "the reply still goes out in 57, because `KAUtil.GetItemString`
keeps the item id and drops the bonus list" — without noticing that dropping the bonus list is not what
the function is documented to do.

**What it can cost.** Two callers compare items with it:

* `Trade.OnTradeAcceptUpdate` / `Trade.OnTradeClosed` — which item in the trade window was handed over.
  Two variants of one item that share their first bonus id compare EQUAL, so the wrong obligation is
  ticked off. Both would have to be in one trade at once, which is rare and not impossible: a boss
  dropping the same slot twice at two levels is an ordinary evening.
* the loot-history export and its duplicate matching, same shape.

The REQ_EQUIP responder used it as a size guard, where a prefix was harmless and the shortening was in
fact the point.

**The migration this entry was blocked on does not exist, and that is worth as much as the fix.** The
note above said the fix was held back because entries already in `KART_LCTrades` and `KART_LootHistory`
"were written with truncated strings". They were not. Both stores persist the LINK, never the string:
`LootCouncilTrade.lua` writes `itemLink = LC.rollItems[rollID]` into every pending/owed entry, and
`LootHistory.lua` writes `item = itemLink or ""`. The item string is recomputed from that link every
time a comparison runs, so widening the function moves both sides of every comparison at once and there
is nothing on disk to migrate. Checked before relying on it. A "blocked on a migration" note is worth
re-reading against the code before it costs a second release.

**The fix.** `KAUtil.GetItemString` matches by delimiter now — `|H(item:[^|]+)|h`, from `item:` to the
closing `|h` — so it makes no assumption about which separators a client build writes inside the string.
That is exactly what B119's `KAUtil.GetFullItemString` already did beside it, so the two became ONE
function under the name the call sites read best: every caller either compares two drops for sameness or
has to rebuild the same item elsewhere, and both jobs want the whole string. Two names only ever
documented the bug.

Two things came along with it:

* The history dedup's bare-string fallback (`^item:[%-%d:]+`, for the entries the oversized-link path
  sends without a link) had the same comma-blind class and would have truncated one side of the
  comparison while the link side stayed whole. Widened to `^item:.+`.
* The REQ_EQUIP responder's 255-byte guard is gone. Its premise died with the AceComm transport rework:
  a message over the cap is split and reassembled, not truncated, so there is nothing to guard against —
  and the shortening only ever fitted because `GetItemString` was dropping the bonus list by accident.
  The link goes out whole. The receiver still accepts a shortened reply, because the protocol version did
  not change and a client on the older responder is in the same raid.

**Covered by tests that failed first**, all built from the fixture's own link shape (the comma is the
whole point; a skeleton link cannot show this at all): the auto-fill places the variant that was won
rather than another variant in an earlier bag slot; trading the other variant away leaves the obligation
standing; `Trade.GetDuplicateOrdinal` does not number two variants as duplicates of each other; a second
variant arriving over the history sync is a second award, not a duplicate; and the unit-level assertion
that the comma-separated bonus list survives at all.

## B128 — FIXED 2026-08-03 — Midnight blocks addon messages during an encounter, and KART never knew

Found by comparing against RCLootCouncil, at the maintainer's suggestion — *"man muss das Rad nicht
immer neu erfinden"* — and it is the single most likely explanation for the losses B118 records.

Midnight gates what an addon may do while certain states are active and announces it with
`ADDON_RESTRICTION_STATE_CHANGED` (`Enum.AddOnRestrictionType` = Combat, **Encounter**,
**ChallengeMode**, PvPMatch, Map; `Enum.AddOnRestrictionState` = Inactive/Activating/Active). Addon
messages are among the things that stop going out. Both enums and `C_RestrictedActions` are in the
12.0.1 annotations, so this is not a 12.1 problem — it is live now.

**Why it lands exactly on this addon:** loot drops at the END of an encounter. Every roll
announcement KART sends goes out in the one window where this is either still active or in the middle
of switching off. A message sent then is not delayed, it is gone, and nothing retried.

Before this, KART contained zero occurrences of the event, the enums, or `C_RestrictedActions`.

**The fix.** `KASC` tracks the state and refuses to send while Encounter or ChallengeMode is active.
Messages marked `guaranteed` are held (capped at 40, deduplicated) and flushed in order the moment the
restriction lifts; everything else is dropped and counted. `LC.SendLC` decides which is which by
token, and the rule is *"would the raid be wrong afterwards if this never arrived?"* — announcements,
awards, votes, the session flag and the config are held; heartbeats and requests are not, because a
question answered forty seconds late is noise.

**Which two restriction types count is an OBSERVATION, not documentation.** It follows the addon that
has been living with this in production, whose own comment says combat is the exception and comms
still work inside instances with the map restriction on. Written to fail safe both ways: too narrow
and the send counters in `/kart status` show the rejections anyway, too wide and a message waits for
the encounter to end.

`/kart status` reports both new counters. **That is what settles whether this was the cause of
2026-08-03** — if held-back and dropped-in-restriction are non-zero next raid, the evening is
explained; if they stay at zero while an item goes missing, it was not this.

Held by `tests/test_diagnostics.lua`, with `KARTTEST.SetRestriction` driving the real event.

## B129 — FIXED 2026-08-04 — an ownership disagreement used to cost nothing, and now it costs the whole raid's numbers

Found by the deep soak, seed 1728 of 2000: one client in the announcer's own eligibility snapshot,
entitled to a number, ended up with none — permanently, for that item.

**Why it lands exactly on this addon.** Two commits ago the 1-100 rolls moved from every client
drawing its own number to the lootmaster drawing the whole raid's numbers once and sending them as a
single authoritative `LC_ROLLS`. The receiver's rule for accepting it is `LC.IsSenderLootOwner`, and
that is a question two clients can answer differently: a raid leader who reloads (or turns up late)
picks up a relayed config with the lootmaster field blanked on purpose — "ownership stays derived",
see `LC.HandleConfigRelay` — reads itself as loot owner through the raid-leader fallback, and keeps
reading that way for the seconds until the next roster settle tells it otherwise. The named lootmaster
is still out there, unaware, still announcing. A client sitting in that window refuses the real
owner's table outright: wrong sender, as far as it is concerned.

Before the move to a single writer this cost nothing — every client drew independently with no sender
check at all, so an ownership disagreement was invisible. Now the data has exactly one writer, and
disagreeing about who that writer is means getting none of it.

**And the repair path could not reach it.** `LC.HandleTable`, the heartbeat that is what makes a
client notice it is missing a table and ask again, opens with the identical guard. So the client that
refused the table also refuses the heartbeat that would have made it ask, and the request-again
promise `00d0d54` made never gets a chance to run.

**The fix.** One condition in `LC.HandleRolls`, the same fill-a-void shape `LC.HandleConfigRelay`
already uses a few hundred lines above it: `LC.IsSenderLootOwner` still decides whether an incoming
table REPLACES one we hold, but a client holding no table at all for that rollID now accepts it
regardless. A sender we do recognise as owner still overwrites whatever is there, so the single-writer
property is intact for every table that has already landed — the only new behaviour is that a client
with nothing takes what it is offered. `LC_ROLLS` is registered `group = true`, so KASC's dispatcher
has already confirmed the sender is in the raid before the handler ever runs; nothing else needed
checking. `LC.HandleTable` and the catch-up path are untouched — this is the smaller of the two holes
the diagnosis found, and the only one that needed closing.

Held by a new case in `tests/test_lc_rolltable.lua`: a client is promoted and reloaded, then the test
holds the ownership disagreement open deliberately — the client reads itself as loot owner while the
named lootmaster still holds the real authority — because what is under test is `LC.HandleRolls`'s
behaviour DURING such a disagreement, not how long it persists in a real raid. The client is asserted
to end up holding the same numbers as the lootmaster anyway. The deep soak (2000 seeds, seed 1728
included) is clean.

## B130 — FIXED 2026-08-05 — a relayed config now says whether the raid has a lootmaster, so a reloaded raid leader no longer claims a loot flow that is already running

Found in review of the roll-table fix above; closed after two more rounds of review, one of them a
reverted attempt.

**The mechanism this closed.** `LC.IsLootOwner()` falls back to `UnitIsGroupLeader('player')` whenever
`LC.GetLootmaster()` answers `""`. A raid leader whose `raidConfig.lootmaster` was blanked by
`LC.HandleConfigRelay` read an empty key exactly like a raid that never had a lootmaster at all — there
was nothing on the wire to tell the two apart. `LootmasterAbsent()` returns false for an empty key (there
is no absent NAMED lootmaster to be absent), the stand-in-consent gate that would otherwise ask before
taking over was skipped entirely, and the raid-leader fallback answered `true` on its own — while the
real lootmaster stood next to them, still running the loot flow.

**What closed it.** `LC_CONFIG_RELAY` now carries a third value in the reserved lootmaster slot: `""`
(nobody named), `"1"` (named and present), `"0"` (named and gone). The key itself still does not travel
— only the config owner may name anybody — but a relay can now say whether the raid HAS a designation
without saying who it is. "Named and present" makes a receiving client defer instead of falling back to
raid lead; "named and gone" opens the same stand-in dialog a roster update already opens. An
`ApplyOwnConfig` with an empty own field cannot erase this on its own — only another relay, the config
owner's own `LC_CONFIG`, or a field naming somebody can — and only a raid-wide broadcast clears it, not
a targeted sync-request answer, so a leader who reloads mid-round and immediately asks for a sync does
not get to read that answer as "gone" either.

**Two residuals, both narrower than what this replaced.**

* A relay-fed client forwards what it was told rather than recomputing it, so a stale `"0"` is possible:
  a client is told once that the lootmaster is gone, the lootmaster returns, nothing re-evaluates that
  client's own field for it, and it later answers a reloading leader's state request with `"0"` —
  raising a stand-in prompt nobody needed. Still strictly narrower than what B130 was about: before this
  fix, that leader simply claimed ownership with no prompt at all. It closes itself at the leader's own
  next raid-wide broadcast, and even before that a human has to click yes before anything happens.
* That self-closing has a limit worth naming: it lasts only until the leader's own next raid-wide
  broadcast. After that the raid agrees on exactly one announcer again — who may be the wrong one, and
  that is B76's documented tension, untouched by this change. What B130's fix buys is that the raid
  never runs with TWO announcers, not a permanent correction of who the one announcer is.

**How this was arrived at, because it is worth more than the description of the fix.** A first attempt
(`d6a7bf3`) tried to remember the PROVENANCE of the config instead — mark it "came from a relay" and
derive the third state from that marker. It was reverted (`74f58a8`) after review reproduced two
defects: the marker was wiped by `GROUP_ROSTER_UPDATE` within seconds of being set, and narrowing it
enough to survive that let the original B130 defect back in through the gap the narrowing opened. The
rule gap this looked like it needed did not exist — **B76** had already decided, on 2026-07-31, that an
empty field KEEPS what the raid has rather than overwriting it. What was actually missing was not a
principle but one bit of information the relay was throwing away on the wire: whether the raid has a
lootmaster at all. Once that bit travels, B76's existing rule is enough.

## B131 — FIXED 2026-08-04 — a lost roll table cannot always be asked for again after a lootmaster handover

Found in review of the roll table change; not new to it.

`LC.MayCatchUp` returns `nil` — not `false` — when `LC.rollEligible[rollID]` was never recorded for that
rollID, and `LC.HandleRollRequest` requires the strict `true` that rule was written for (B118: "a late
arrival is not handed a running item"). A stand-in owner — the raid leader who takes over when the named
lootmaster ports out, this guild's normal operating event — never ran `SnapshotEligible` for items the
PREVIOUS owner announced before the handover, because that snapshot is taken once, by whoever announces,
at announce time. So after the handover, no client can recover a lost roll table for anything announced
earlier: it just re-asks every `ROLL_REQ_COOLDOWN` and is silently refused, forever, for that item.

This is not a defect the roll table introduced — it is B118's settled strict-yes rule doing exactly the
job it was written for, applied to data (`LC.rollEligible`) that rule already governed before this
change existed. `LC.MayCatchUp` and B118's strict-yes rule are untouched by the fix below: they still
decide, unaltered, who gets the *item*. What changed is that the numbers are no longer tied to that
decision at all — they are not a secret, since the whole raid already holds the same table, so anybody
who still has it may hand it over regardless of who currently owns the item.

**The fix.** A second, group-wide request. `LC.HandleTable`'s existing per-roll ask still whispers the
believed owner first, exactly as before; if `ROLL_REQ_COOLDOWN` (30s) passes with the table still
missing, the client broadcasts `LC_ROLLS_REQ:<rollID>` to the whole group instead of asking the same
owner again. Every client still holding a non-empty table for that rollID answers — spread by its own
POSITION in the sorted roster (`LC.RollsAnswerSlot`) rather than all firing at once, and each drops its
own planned answer the moment it sees somebody else's `LC_ROLLS` for the same rollID land first. The
answer is a normal `LC_ROLLS` broadcast, so it runs through the same precedence B130 established: a peer
is never the announcer, so its table can only ever fill a void, never overwrite what the announcer said.

A hash of each client's own name was written first — the construction KASC's handshake uses for the same
problem — and `7123117` replaced it, because it was measured not to hold at raid size: 25 random names,
20,000 trials, the exact hash that was here, and 26% of full rosters put two clients within a few
milliseconds of each other, which is well inside the jitter a busy loot round's `ChatThrottleLib` queue
adds. A hash spreads by luck. Position in a list every client can see identically divides the window
into N equal gaps by construction. What that costs instead is a stronger requirement — every client must
independently produce the SAME ordering, where the hash needed no agreement at all — and the code says
what happens when they briefly do not: the spacing degrades and two clients may answer, which is one
extra broadcast and nothing else. See the comment above `ROLLS_ANSWER_SPREAD` for the real margin, which
is 250ms at a 40-man and the same order as the jitter it has to beat.

`LC_ROLLS_REQ` is not on `GUARANTEED_TOKENS`, for the same reason `LC_ROLL_REQ` is not: it is a
question, and a question that arrives forty seconds late is noise — the asker has already asked again by
then.

**Knowingly left open: a plain raider never lets go of a caught-up expired item.** An item is now askable
for as long as it is still tracked rather than only while its timer runs, so a raider can be handed one
whose voting has already closed. `LC.HandleStart`'s `secs == 0` branch tracks it deliberately without a
vote row — the row would flash up and `Vote.PruneExpiredRolls` would tear the whole repair back down a
tick later — and that sweep walks `LC.voteListRolls` and nothing else. So the roll has no way out: it
stays tracked on that client until the round or the session ends, on somebody who is not on the council
and has nothing left to decide about it.

The consequence is bounded but real. If that same client later stands in as loot owner — the lootmaster
ports out, this guild's normal operating event — its own heartbeat then names those long-dead rollIDs to
the whole raid, and every peer that pruned them properly reads that as "I am missing this" and asks. What
it does NOT do is put the items back: answering a request needs `LC.rollEligible` for that rollID, and a
client that received the item as a catch-up never announced it and therefore never had that snapshot, so
`LC.MayCatchUp` refuses — the strict-yes rule from B118, doing here exactly what this entry is about
elsewhere. The cost is a question and a refusal per pruned peer every `ROLL_REQ_COOLDOWN` until End Round
or the session end clears the table, not a resurrected item.

Left open rather than fixed, because every fix on offer is worse than the noise. Ageing a tracked roll out
by its own deadline is the deletion-from-silence the whole heartbeat design refuses (see the comment above
`TABLE_HEARTBEAT_SECONDS`), and dropping the catch-up for closed items instead gives back the very repair
this change exists for. `LC.rollDismissed` does not help here either: nobody dismissed anything — this
client was handed something it never asked to keep.

One related gap closed alongside it: `LC.EnsureTableTicker` only ever started on the client that first
announced an item, so a departed lootmaster's own heartbeat died with them and nothing replaced it —
leaving the second request above unreachable for anything announced before a handover, exactly the B131
scenario. Accepting the `KART_LC_STAND_IN` prompt now also calls `LC.EnsureTableTicker`, so the stand-in
picks up heartbeat duty for whatever is still open the moment it takes over, item eligibility (B118)
notwithstanding.

`LC.rollDismissed`, the dismissal memory this same request loop defers to, had its own reused-rollID
gap, and the first attempt at it weakened the handover case this entry is about: a dismissal was
forgotten when the owner's heartbeat stopped LISTING that rollID, and a stand-in's table is
legitimately shorter than the previous owner's, so a closed tab could come back once. Both are closed
by the wire change in B132 below — absence is no longer read as evidence of anything.

## B132 — FIXED 2026-08-04 — the heartbeat named the number on the table but never the item on it

Found in review of the request loop above (B131), not by the soak. Two cases, one root, one fix.

**The root.** `LC_TABLE` — the loot owner's ten-second "here is what is still on my table" — carried
rollIDs and nothing else. Blizzard hands the same rollID to an unrelated item within seconds on trash,
so a receiver reading that list could never tell a repeat of a roll from a REUSE of its number. Both
cases below are that one blind spot, seen from two sides.

**Case 1: a reuse nothing else on the wire named.** `LC.HandleRollCatchup` refuses to hand a client
anything under a rollID it once dismissed, and `LC.HandleTable`'s request gate refuses to even ask for
one — both deliberately, so a raider who closed the tab is not reopened into an item they are finished
with (B131). What the raider dismissed was an ITEM; the gate could only read a NUMBER. A client that
dismissed roll N, then got a genuinely new item under N, and missed that item's `LC_START` — the exact
broadcast the heartbeat exists to stand in for — was deaf to it: nothing asked, and an unsolicited
`LC_ROLL_CATCHUP` was refused on arrival.

Storing the dismissed itemID rather than a bare flag (`LC.rollDismissed[rollID]`, 2026-08-04) fixed
that everywhere an item is actually named — the catch-up, `LC.HandleRolls`, `Trade.HandleResult` — and
in practice the roll table repaired the case, since it reaches the whole raid and names its item. It
left exactly one hole: a raid with rolls switched off, where the heartbeat is the ONLY message that
ever reaches a client which missed the announcement, and the heartbeat named no items.

**Case 2: the stand-in weakening.** The same change made `LC.HandleTable` forget a dismissal whose
rollID the owner no longer LISTED, so a stale note could not gate a later reuse of that number. That
inference is wrong for this guild's normal operating event. A stand-in's table holds only what that
client itself announced, so after a handover it is legitimately shorter than the previous owner's, and
"absent" is not "gone". Worst case a closed tab reopened once. It was written down against B131 rather
than hidden, and guards for an empty list and a truncated one could not see it — nothing in the
message said the list was a stand-in's.

**The fix, decided by the maintainer knowing it is a wire change.** `LC_TABLE` now names the item
alongside each rollID: `LC_TABLE:<count>:<rollID>=<itemID>,<rollID>=<itemID>,...`.

* An **itemID, never a link**. Six digits against fifty-plus, and the same item's link differs per
  drop by its bonus ids — which is the comparison this message must never make (`LC.PayloadItemID`
  exists for that reason). At the widest rollID this addon can produce (six digits:
  `MANUAL_ROLL_ID_BASE` plus a five-digit remainder) twelve entries and their commas are 167 bytes,
  about 180 with the token and count in front — so `TABLE_MAX_IDS` is unchanged at 12 and the
  heartbeat still fits a single addon message. (Recorded as "about 160" when the change went in;
  corrected in review, same conclusion.) AceComm would split a longer one rather than lose it, but a
  heartbeat costing three chunks every ten seconds all evening is a bad trade for a message whose
  whole point is being cheap enough to repeat.
* **`=0` for a roll the owner cannot name itself** — an `LC_START` that carried no itemID leaves
  "???" tracked (B40). Still listed, deliberately: a roll the owner is vague about is exactly the one
  a receiver most needs to hear exists. The receiver reads it as "unknown", never as a mismatch, so
  the ask still happens and no comparison is made.
* The leading **count stays**, unread — but for the reason found in review, not the one first written
  down. Its VALUE is inert (no 3.3.1 reader looks at it, and the 3.3.0 reader's `shown == total` guard
  can never hold against a doubled list); its FIELD is load-bearing. The receiver splits the payload
  with `^(%d+):?(.*)$`, so a message without the count would parse `980=249331,981=…` as count 980 and
  list `=249331,981=…` — swallowing the first entry silently. It also keeps the payload's first field
  the shape a 3.3.0 client parses.

**What the receiver does with it.**

* A dismissal is forgotten when the heartbeat shows a **DIFFERENT** item under that id — never when
  the id is merely absent. That closes case 2 outright: absence stops being evidence, so the
  absence-based sweep and its guards for an empty and a truncated list are gone with it. Nothing is
  lost by removing them: a number that leaves the table and comes back for a new item is NAMED on the
  very next heartbeat, which is strictly more than the sweep could see, and it also catches the reuse
  the sweep could not — where the number never left the table at all.
* A client **holding** an item under an id the heartbeat now names differently is looking at a reuse
  it missed. That is `PurgeStaleRoll`'s transition already — it drops the dismissal note, the previous
  item's votes, tab and vote row, and keeps rolls already cast for the item now arriving — so it is
  called (`LC.PurgeStaleRoll`) rather than reimplemented, and there is one answer to "this id belongs
  to a different item now" instead of two that can drift. Called only on a proven difference, which
  means a COMPARABLE PAIR on both sides: `PurgeStaleRoll` clears the dismissal unconditionally at its
  top, which is right for a roll START and wrong for a heartbeat repeating the item this client
  deliberately closed — and a held `"???"` is not a difference at all (below).
* A client holding an unreadable **`"???"`** (B40) under an id the heartbeat names is **repaired in
  place**, never purged (corrected in review, 2026-08-04; the first version of this change purged).
  `PurgeStaleRoll`'s B40 branch states its own premise — a new item IS arriving under this ID — and
  both of its other callers are roll starts that re-track the arriving item immediately afterwards. A
  heartbeat is the opposite: a repeat of the same roll, re-tracking nothing. Purging there cost the
  raid's whole vote for that item (`LC.votes`, `LC.councilVotes`, the tab, the vote row, the deadline)
  and left the client depending on a round trip a stand-in can refuse — `LC.MayCatchUp` wants an
  `LC.rollEligible` snapshot only the announcing client ever takes, and `Vote.ScheduleVoteCatchup`
  fires once shortly before the deadline, so council cards lost after that point never come back. The
  itemID is in the message, so `LC.rollItems[rollID]` is rebuilt from it exactly as
  `Trade.HandleResult` does at award time and nothing is cleared.
* `LC.rollReqSent[rollID]` is **cleared where a purge happens**. The ask that follows is about a
  different item than the one that stamped it; `PurgeStaleRoll` cannot do it (on the dismissal-only
  path it returns at "nothing tracked under this ID", before `Trade.ClearRollState`, the only other
  clearer), and `LC.HandleRollsRequest` pushes an existing stamp forward every time a peer escalates
  `LC_ROLLS_REQ` for that number — so the deferral was never bounded by `ROLL_REQ_COOLDOWN`, as first
  recorded. Clearing also puts the first question back to the owner instead of the group.
* The heartbeat is therefore now **authoritative about item identity**, which is a new surface and is
  named as such in the code: an owner that is itself stale — it missed the `LC_START` for a reuse and
  still tracks the previous item — names the old item and makes a client that dismissed or holds the
  new one drop that and ask again. Before this change no heartbeat could touch a tracked item or a
  note at all. Self-limiting (the answer is whatever is really on the table, and the next heartbeat
  agrees), but it is a channel for one client's staleness to reach the rest of the raid.

**Protocol version stays `3.3.1`.** The last release tag is `v3.3.0`, 3.3.1 is unreleased, and a
3.3.0 client is already reported as outdated by this build. What a 3.3.0 client actually does with the
new payload, since its `LC.HandleTable` scans the list with a bare `%d+`: it reads the itemIDs as
rollIDs too, so `LC_TABLE:2:980=249331,981=249293` is seen as four ids — 980, 249331, 981, 249293 —
and it asks for the two nonsense ones. **Those asks are refused harmlessly and were confirmed to be**:
`LC.HandleRollRequest` returns at `not itemID or not LC.RollTracked(rollID)` before it sends anything
or counts anything, and the group-wide `LC_ROLLS_REQ` escalation is dropped by every peer at "nothing
to give". Measured against the fixture raid: catch-ups answered for 980 and 981 only, nothing for the
item ids, `diag.refusedSender` unchanged at 0. A 3.3.0 client also stops running its own absence
sweep, because its `shown == total` guard never holds against a doubled list — which leaves it on the
pre-B132 behaviour of keeping notes longer, not on a wrong one. In the other direction a 3.3.0 OWNER's
item-less list parses on a 3.3.1 receiver as "unknown item" for every entry, which is exactly the old
behaviour.

**Covered by** `tests/test_lc_rolltable.lua`, next to B131's own: a dismissed id reused for a
different item, with rolls switched off so the heartbeat is the only witness — no `LC_START`, no roll
table — a client parked on `"???"` whose card keeps its votes, its tab and its deadline through the
heartbeat that names the item, and a stand-in whose table is genuinely shorter (a plain raider, whose
`Vote.PruneExpiredRolls` has dropped the roll) not costing a valid dismissal. The last replaces the
case that asserted the opposite. All three fail before the change they belong to; the `"???"` case
fails on the votes it loses and on having to ask at all, and the stand-in case carries its own proof
that the client is reading the stand-in's heartbeat rather than ignoring its sender. `luacheck` 5
warnings / 0 errors, the suite 0 failures, and the deep soak at `KART_SOAK_SEEDS=2000` 0 failures.

**What is left.** One branch, and it is the one the note format cannot express:
`Council.CloseCouncilTab` stores `true` rather than an itemID when the item was never resolved, and
every reader needs a comparable string — the heartbeat clause above, `LC.ForgetDismissalIfReused` and
`LC.HandleRollCatchup` all skip or refuse on a boolean. So: a council member closes an unidentifiable
tab under N (`LC.rollDismissed[N] = true`), Blizzard reuses N for a real item, and that client misses
the `LC_START`. The heartbeat lists `N=249331`, the purge clause is skipped (nothing tracked, and a
boolean cannot be shown to differ), the request gate refuses to ask, and an unsolicited catch-up is
refused on arrival. That client is deaf to the item until End Round, `LC.ClearAllRolls` or a reload —
the original B132 symptom, surviving on the one branch above. Until this change the absence sweep was
the only thing that could ever drop such a note, and the sweep is gone with the inference it rested on.

**Why it is deliberately not patched.** The obvious fix — forget a `true` note as soon as the
heartbeat names any concrete item under that id — re-breaks B131 for exactly the raider it protects:
the client that closed a tab it could not read is the one whose note would be discarded on the very
next heartbeat, putting the item it deliberately finished with back on its screen every thirty
seconds. That is a worse failure than the one being fixed, and it lands on the same person. This is
also not a regression against the last release: 3.3.0 behaved this way for **every** dismissal, not
just the unreadable ones. It costs one client the visibility of one item; the roll table, the
council's decision and every other client's copy of both are untouched.

**What is not changed.** `LC.MayCatchUp` and B118's strict-yes rule, the "it only ever adds" rule above
`TABLE_HEARTBEAT_SECONDS` — a heartbeat still never takes an item off anybody's screen — and
`LC.ForgetDismissalIfReused`, which `LC.HandleRolls` and `Trade.HandleResult` still use where they name
an item themselves.

## B133 — OPEN 2026-08-04 — a client that joins inside the collection window is handed the boss it missed

Found in review of the one-message-per-boss change (`LC_DROP`), not by a raid.

A boss's items are now collected for half a second and announced together, so the announcement leaves
up to 500 ms after the loot event instead of inside the same frame. A client that joins the group in
that gap receives it like everybody else — it is an ordinary group broadcast — and `LC.HandleStart`
gives them a vote row and a popup for a boss they were not standing at.

**What is NOT affected, and it is worth being exact.** `SnapshotEligible` runs at the loot event, so
the joiner is not in `LC.rollEligible` and `LC.MayCatchUp` still refuses them every catch-up. B118's
strict rule is untouched and so is `docs/OWNERSHIP.md`. They also hold no number of their own: the
table was drawn against the snapshot they are not in, and they store it exactly as the rest of the
raid does — with no entry for themselves. So the shape in the raid is a person on the council panel
with a vote and an empty roll column.

**Why it is deliberately not fixed — and this is a decision, not an unfinished job.** The reasoning
this entry used to carry (the message does not name the participants, so the receiver has nothing to
check itself against) is stale: since the batching change the head list names every participant, and
a receiver could compare its own identity key against it in about three lines. So the next reader
will see an easy fix. It must not be taken, for one reason:

The head names identity keys as the ANNOUNCER resolved them. A raider whose key the announcer
recorded as a pending text placeholder — which `SnapshotEligible`'s own comment says it deliberately
keeps, because it happens — would not find its own resolved GUID in that list. A receiver that
excludes itself on that basis gets no vote row, no popup and no card for an item it is fully entitled
to, and nothing anywhere says so.

That trades a VISIBLE wrong inclusion — a joiner on the council panel with a vote and an empty roll
column, which the council can see and ignore — for a SILENT wrong exclusion. This codebase's own
history is unambiguous about which of those costs more: the whole B118/B129/B131 line of work exists
because a silent loss costs a raid night and a visible oddity does not. The item is also not
misassigned in the meantime — the council still decides, and it can see that this raider has no roll
number.

Stays OPEN because the behaviour is still wrong, not because the fix is unknown.

## B134 — OPEN 2026-08-04 — a reload inside the collection window loses a whole boss, and the belt only mostly works

Found in the same review as B133.

`LC.pendingDrop` is runtime state. A loot owner who reloads, disconnects or crashes inside the half
second between the loot event and the flush comes back without the batch, and the announcement is
simply never made. `ForceWinRoll` has already run by then, so the items are physically in the
lootmaster's bags while nobody in the raid — the lootmaster included — has a card for the boss that
just died.

**Loud, not silent,** which is why it is recorded rather than engineered around: the whole raid can
see that a boss dropped nothing, and `/kart add` is the standing manual recovery for exactly this.
Weighed against the trigger — a reload landing inside one 0.5 s window per boss — persisting the batch
would be more machinery than the risk earns.

**The cheap belt, taken.** Core.lua already handles `PLAYER_LOGOUT`, which fires for a /reload, a
logout and a quit alike, so flushing there is one line next to `SaveSessionSnapshot` and it is in.
Recorded honestly: it is a belt, not a fix. `ChatThrottleLib` sends inline when there is bandwidth
free and queues otherwise, and a queued message is despooled from an `OnUpdate` that will not run
again — so a batch that goes out during a quiet moment survives the reload, and one sent while the
pipe is already congested does not. A crash raises no `PLAYER_LOGOUT` at all.

**And a third way it does nothing, checked 2026-08-05.** `LC_DROP` is a guaranteed token, so while
the encounter restriction is active `KASC:Send` does not send it at all — it holds it in
`guaranteedQueue` until `OnRestrictionChanged` releases it. That queue is runtime state like
`LC.pendingDrop` is, so a reload inside the restriction window takes the belt's own message with it.
Loot drops at the end of an encounter, which is exactly when that window is closing, so this is not
an exotic corner. It does not change the verdict — the loss is still loud and `/kart add` is still
the recovery — but the belt is thinner than the paragraph above alone reads.

## B135 — FIXED 2026-08-05 — a batch can flush after a peer's table for the same rollID has already landed

Found in review of the one-message-per-boss change (`LC_DROP`), not by a raid.

`FlushPendingDrop` serializes from `LC.rolls[rollID]` at send time, so in the B130
ownership-disagreement corner — where a peer's table for the arriving item is already stored under
that id when the batch flushes — the departing entry could carry the wrong numbers. Unreachable on
the owner's own path (it draws its own table), and the receiver's length check does not catch it
since the lengths match.

**What closed it.** The entry no longer reads shared mutable state late: it carries its own copy of
the numbers, taken when the entry is created, and `LC.SerializeDrop` writes that copy instead of
`LC.rolls[e.rollID]`. Half a second of other clients' traffic can no longer reach what a departing
entry says.

The copy is handed out by `LC.DrawnKeys` as a second return value, next to the head it derives from
the very same read — deliberately, and it is the whole point of putting it there. The head is
DERIVED from the numbers because computing the two separately broke this invariant three times
(see the block comment above `LC.DrawnKeys`), so a snapshot taken at a second site would have been
the fourth. A caller that keeps both keeps a pair that cannot have drifted.

Both entry-building paths take it. `LC.StartManualRoll` serializes in the same breath and could not
have drifted, but there is one entry shape and one rule about where an entry's numbers come from.

Covered by a test in `tests/test_lc_drop.lua` that replaces `LC.rolls[rollID]` with a foreign table
of the same length while the entry sits in the batch, and asserts the raid is handed the numbers the
entry was created with. It fails against the old code.
