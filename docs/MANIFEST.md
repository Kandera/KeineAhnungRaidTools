# The Manifest

**The core functions, and the standard they are held to: ten times out of ten.** Named "das Manifest"
by the maintainer on 2026-07-31 so it can be pointed at in one word -- "gegen das Manifest getestet",
"das bricht C7". Use that name; it is the whole reason this file has a short one.

The standard, in the maintainer's own words about the ownership rework: *"Die Funktion ist eine der
10/10 Grundfunktionen die funktionieren muss."*

**Settled by the maintainer on 2026-07-31.** It was drafted from `docs/OWNERSHIP.md`, from the
failures the backlog records as having cost real raid evenings, and from the operating reality
described below; the maintainer then widened C6 to name pets and housing items, and added C12. It
counts as it stands. Changing an item is the maintainer's call, not a side effect of changing code.

**Extended by the maintainer on 2026-08-03**, after the first live raid on 3.3.0: C13 (the rolls are
complete) and C14 (nothing is lost quietly), both named from failures that evening.

## How to read this

Ten out of ten means **in the game, with two clients, ten separate attempts** — not ten green test
runs. The automated suite is the floor, not the standard: it is 1263 assertions and a 30000-run
convergence soak, and it still cannot see a cursor, a Blizzard roll window, or a real reload.

Each item says what must be TRUE at the end, not what to click. If an item needs a third body, an alt
parked in the raid is enough.

## The numbers are labels; this is the order

C1 to C14 are names, not a running order -- "das bricht C7" has to mean the same thing next month, so
they do not get renumbered when the sequence is understood better. New items are appended at the end
of the numbering and slotted into the sequence below, which is why C13 and C14 sit at the first boss.
The sequence is written here instead, and it is what `tests/test_manifest.lua` walks:

| | | |
|---|---|---|
| the raid forms | C1 | the session starts, everybody in it |
| | C2 | everybody on the raid's settings |
| first boss | C4 | the item is force-won |
| | C5 | everybody sees it, answers reach the council |
| | C14 | and nothing is lost quietly on the way |
| | C13 | the rolls are complete before anyone decides |
| | C7 | the award converges, the holder owes it |
| between bosses | C3 | somebody turns up mid-session |
| | C6 | trash drops collectibles, BoEs, blues -- KART stays out |
| | C8 | somebody reloads mid-distribution |
| | C10 | raid lead changes hands |
| | C9 | the lootmaster walks out, the leader stands in |
| last boss | C12 | a set token, and it goes through the council |
| | C11 | End Round, and it ends for everyone |

C6 and C12 are two sides of one check and are deliberately far apart in the run: a token and a mount
sit in the same item class and are told apart only by subclass, and tokens really do come from the
last boss. Adjacent, they would share a state that the evening does not give them.

## The operating reality this has to survive

Stated by the maintainer, and every item below is written against it:

> "In Midnight gibt es mehrere Raids mit wenig Bossen, d.h. dass Leute z.B. schon aus dem Raid porten
> und in einen anderen gehen während die Lootverteilung startet ist normal. Das muss hier trotzdem
> funktionieren. [...] Bei uns reloggen Leute oft oder wechseln den Char - ich kann nicht jedes Mal
> /kart v machen für Settingspush und die Session restarten wenn einer umloggt."

So: **nobody is asked to do anything for the raid to work.** A raider configures nothing, and the
raid leader does not babysit anyone's settings.

---

## C1 — The session starts, and everybody is in it

Start the session. Every client in the raid says the session is running, without anyone being asked
and without a second attempt.

*Protects:* a session that exists only on the lootmaster's screen — the boss dies and nothing happens
anywhere.

## C2 — Every raider runs on the raid's settings, not their own

After the session starts, every client shows the raid's vote buttons, minimum quality and roll
setting. Check on someone who has never opened KART's settings.

*Protects:* a vote arriving at the council under a different label than the raider clicked. This is
the failure that scored a whole evening wrong (B25).

## C3 — Someone who turns up mid-session gets all of it

A third character joins after the session is running. Without anyone pressing anything, they end up
with the raid's config and the running session.

*Protects:* B65, and the gap fixed on 2026-07-31 where **nobody** re-broadcast the config in a split
raid — leader and lootmaster being different people was enough.

## C4 — The item is force-won, by exactly one person

A Bind-on-Pickup item drops. The designated lootmaster wins Blizzard's roll; nobody else rolls Need
on it; the item is in their bags.

*Protects:* the item leaving on a normal roll because the loot owner's client was between states.

## C5 — Everybody sees the item, and their answer reaches the council

Every eligible raider gets a vote window for that item. Each answer appears on every council member's
panel, under the label the raider actually clicked.

Include somebody running one of the two personal relevance switches, which are available again as of
2026-08-01. They change what a raider is SHOWN, never whether the council hears from them: an item
the switch hides is answered automatically, so the tally is complete either way, and the raider can
still change that answer — the row it is changed on stays on screen.

*Protects:* the council deciding on a partial tally. Do this one with several people answering at the
same moment.

## C6 — Collectibles, BoEs and anything below the threshold stay out

A mount, a pet, a toy, a piece of housing decor, a Bind-on-Equip and an item below the minimum
quality all drop. KART touches none of them: no force-win, no forced pass, Blizzard's own roll window
behaves normally and the raid rolls on them the way it would without the addon.

Housing decor is checked by ITEM CLASS, not by subclass: Midnight moved it out of Miscellaneous into
a class of its own, and mounts, pets and toys are the ones caught by their journal APIs whatever
class they sit in. A rule that only knows Miscellaneous lets furniture through.

Two counterparts, and both must NOT be excluded: C12 (a set token, the same class as a mount and one
subclass apart) and C15 (a recipe, which is Bind-on-Equip and goes in anyway).

*Protects:* housing decor being force-won, which has happened twice -- once as a subclass nobody
enumerated, once as a whole item class nobody had heard of; a BoE the lootmaster can never hand over
through the trade window at all; and a session where Auto-Pass quietly hands every collectible to
whichever raider is NOT running KART.

## C7 — The award reaches the whole raid, once, and everyone agrees

Assign the item. Every client names the same winner. The winner is told. The holder gets a trade
reminder, and only the holder.

*Protects:* the raid disagreeing about its own record of the evening.

## C8 — A reload changes nothing

Reload mid-distribution — as the lootmaster, as a council member, and as a plain raider, one attempt
each. The session comes back, the item is still on the council panel with the votes that were cast on
it, `/kart lc` opens that panel, the trade deadline still counts from when the boss died, and a
re-decision after the reload is still a re-decision (it asks first, and the raid follows it).

Do it BOTH while the vote timer is running and after it has run out. The second is the ordinary state
of a distribution — twenty seconds of voting, then however long the council takes — and it is the one
that used to lose the item outright for everybody.

*Protects:* B34 (the four-hour clock restarting, which loses the item silently), B77 (the person who
just decided being the only client showing their own decision) and B81 (the items disappearing
altogether, worst for the lootmaster, who nobody was allowed to answer).

## C9 — The loot flow survives the lootmaster walking out

The designated lootmaster leaves the raid mid-session. The raid leader is asked whether to take over,
and from the moment they accept the flow continues — new items are force-won and can be decided.

*Protects:* a raid standing still because the person named in a settings field ported to another
instance.

## C10 — Raid lead moving does not cost the raid anything

Hand raid lead to the other person and back. The raid keeps a working config throughout, the
designation is not silently wiped, and exactly one client is broadcasting at any moment.

*Protects:* B76 — a promotion to somebody with an empty Lootmaster field used to blank the raid's
designation, after which half the raid rejected the other half's announcements.

## C11 — Ending the round ends it for everyone

Press End Round with items still open. Every council panel and every raider's vote window is empty
afterwards, and the session is still running.

*Protects:* cards from the last boss still standing at the next one. Note that the tab's own × is
deliberately local and does NOT do this — see B79.

## C12 — Set tokens go through the council

A tier set token drops. It is treated exactly like a normal piece of gear: force-won, announced,
voted on, awarded, handed over.

*Protects:* the narrowest distinction in the whole item classification -- a token and a mount sit in
the same item class and are told apart only by subclass. Getting that wrong once already meant tokens
were skipped entirely and rolled on the normal way by nobody. Worth its own attempt precisely because
C6 and C12 are two sides of one check: C6 must exclude, C12 must not.

## C15 — A recipe reaches the lootmaster

A recipe or pattern drops -- Bind-on-Equip, and Rare while the raid's threshold is Epic. It is
treated exactly like a normal piece of gear: force-won by the lootmaster, announced, voted on,
awarded, handed over.

The other side of C6, and the reason both are worth their own attempt: C6 must keep every other BoE
out, and this one must let a recipe in, on a rule that reads the item class rather than the binding.

*Protects:* the requirement itself (#34) -- in this guild a recipe always ends up with the
lootmaster, and until 2026-08-06 nothing made that happen. Its own failure mode is the opposite of
C6's: an exception written one word too wide takes every BoE in the instance with it.

## C13 — The rolls are complete before anyone decides

With rolls turned on, every raider in the council list carries a number by the time the council reads
them. Include somebody Blizzard gave no roll window to at all — dead, released, out of range, or
ineligible — and somebody who reloaded between the drop and the vote.

An empty roll cell must mean "this person is not in this decision", never "their number did not make
it". If a number is genuinely unknown, the panel has to say so rather than render the same dash a
non-participant gets.

*Protects:* the tie-breaker being scored on a partial set. The council cannot see that a column is
incomplete — a missing 97 and a missing 3 look identical — so the whole value of the feature depends
on the set being whole. Added 2026-08-03 after the live test, where the rolls were incomplete for a
second time (B121, and B71 before it).

## C14 — Nothing is lost quietly

Run C5 again with the raid as it actually is: everybody answering within a few seconds of each other,
and people porting out, zoning and relogging while it happens. Afterwards the council's tally equals
the number of raiders who actually pressed something — ask them, do not read it off the same screen
that might be wrong.

And where something IS lost, some client says so. A raider whose answer never left, a council member
whose panel never heard about an item, a client that missed End Round: each of those must be visible
to somebody. A defect nobody can see is one that gets diagnosed for a whole evening.

*Protects:* the failure this whole list exists for. On 2026-08-03 four raiders pressed a button and
their votes never arrived, one raider never learned an item existed and lost it outright, and one
council member kept three rounds of cards because End Round never reached him -- and every one of
those clients was quietly certain it was fine (B118). This is deliberately not folded into C5: C5
proves the path works, C14 proves it survives twenty-five people and a normal evening.

---

## What a failure means

One failure in ten is a failure.

**When one breaks, say so in raid chat and have everybody run `/kart status`, then paste it.** That
is the whole procedure -- "write down what each screen showed" is not something anybody does mid-boss,
and the command exists so nobody has to. It prints, per client: whether the session is running and
whether that is an ANSWER or merely a starting value, where the config came from, who this client
reads as raid lead, who it reads as lootmaster, the buttons and roll setting in force, and every
rollID it is tracking.

Two clients giving different answers to "who is raid lead" or "who is lootmaster" is the shape almost
every failure this week had -- each client consistent with itself, which is what made them so quiet.
One word each, side by side, tells them apart in seconds. `/kart status` also names any raider on a
protocol too old to take part, which explains a whole evening of silence on its own (B62).

The convergence soak exists because "it broke somehow" cost three evenings before anything could be
measured. Do not let the raid test cost a fourth.

## Standing result

| run | version | date | scope | result |
|---|---|---|---|---|
| three-man `/kart add` | 3.2.0 | 2026-07-31 | C1, C2, C5, C7, C11 | clean, no complaint |
| **guild raid, ~20 people** | **3.3.0** | **2026-08-03** | C1, C2, C4, C5, C7, C11, C12, C13, C14 | **C5, C11, C13 and C14 failed. C7 and C12 damaged.** See below |

A Manifest with no recorded run is a list of intentions. This one now has one, and it is not a pass.

### The 2026-08-03 raid, item by item

Fifteen reports from the raid and GitHub issues #18-#25, traced to nine defects in `BACKLOG.md`
(B118-B126). What each item did:

**Failed.**

* **C5** -- one raider never learned an item existed (no card, no Auto-Pass, Blizzard's window left to
  him alone) while other raiders had it; four raiders pressed a button and their votes never reached
  the council. B118.
* **C11** -- End Round did not end it for one council member, three rounds running. He finished the
  evening with seven cards for three items. B118.
* **C13** -- rolls missing for part of the list, for the second time. B121.
* **C14** -- every one of the above happened silently. Nothing on any screen said a message had been
  lost, which is why it took the whole evening to tell four symptoms apart. B118.

**Damaged, not clean.**

* **C7** -- the award converged, but the handover did not: a raider who won two items got one placed in
  the trade window (B122), and one obligation was never ticked off. The "items you still need to
  collect" window then could not be closed at all (B125).
* **C12** -- a set token was announced and voted on, but shown as a different item, because items
  travel without their bonus IDs (B119). The same defect put "Item Level 44" on a 285 item across the
  raid.

**Held, as far as this evening reached.** C1 and C2: every `/kart status` seen said the session was on
and named the raid's own settings as in force. C4: the lootmaster held what he was supposed to hold.

**Not reached at all.** C3, C6, C8, C9, C10 -- nobody joined mid-session, no collectible or BoE dropped
where it was watched, nobody's reload was checked, the lootmaster did not walk out, lead did not move.

**The procedure worked.** `/kart status` from the affected client is what turned "items are doubled"
into a traced cause in one screenshot -- the tab list and `Council: 2 resolved, 3 not yet matched` were
both in it. Keep asking for it; it saved an evening of guessing here.

### What the three-man run does and does not say

Reported by the maintainer: 3.2.0, three people, items added with `/kart add`, everything behaved.
That is real evidence and it is written down as such -- but it is worth being exact about its
reach, because a Manifest that counts partial evidence as a pass is worse than an empty one.

**Covered.** C1 and C2 (the session and the settings reached all three), C5 (everybody saw the item
and their answers arrived), C7 (the award converged and the holder owed it), C11 (End Round).

**Not reachable that way, whatever the outcome looked like:**

* **C4** -- `/kart add` has no Blizzard roll behind it at all, which is the whole point of the
  command. Force-winning is exactly what it skips.
* **C6** and **C12** -- both need real drops: a mount, a pet, a housing item, a BoE and something
  below the threshold for one, a set token for the other.
* **C3**, **C9**, **C10** -- nobody joined, nobody left, lead did not move.
* **C8** -- nobody reloaded. This is the one that carries forward least: B81 landed after 3.2.0 and
  changed what a reload does, so a clean reload on 3.2.0 says nothing about the build shipping now.

**And it was 3.2.0.** 3.2.1, 3.2.2 and everything since sit between that evening and today,
including both relevance switches coming back and the whole snapshot-across-reload mechanism. The
row stays because it is true; it does not count toward the ten.
