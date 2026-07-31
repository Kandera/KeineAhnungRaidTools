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

## How to read this

Ten out of ten means **in the game, with two clients, ten separate attempts** — not ten green test
runs. The automated suite is the floor, not the standard: it is 1263 assertions and a 30000-run
convergence soak, and it still cannot see a cursor, a Blizzard roll window, or a real reload.

Each item says what must be TRUE at the end, not what to click. If an item needs a third body, an alt
parked in the raid is enough.

## The numbers are labels; this is the order

C1 to C12 are names, not a running order -- "das bricht C7" has to mean the same thing next month, so
they do not get renumbered when the sequence is understood better. The sequence is written here
instead, and it is what `tests/test_manifest.lua` walks:

| | | |
|---|---|---|
| the raid forms | C1 | the session starts, everybody in it |
| | C2 | everybody on the raid's settings |
| first boss | C4 | the item is force-won |
| | C5 | everybody sees it, answers reach the council |
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

*Protects:* the council deciding on a partial tally. Do this one with several people answering at the
same moment.

## C6 — Collectibles, BoEs and anything below the threshold stay out

A mount, a pet, a housing item, a Bind-on-Equip and an item below the minimum quality all drop. KART
touches none of them: no force-win, no forced pass, Blizzard's own roll window behaves normally and
the raid rolls on them the way it would without the addon.

Its counterpart is C12: the same class, one subclass apart, and it must NOT be excluded.

*Protects:* housing decor being force-won, which has happened; a BoE the lootmaster can never hand
over through the trade window at all; and a session where Auto-Pass quietly hands every collectible
to whichever raider is NOT running KART.

## C7 — The award reaches the whole raid, once, and everyone agrees

Assign the item. Every client names the same winner. The winner is told. The holder gets a trade
reminder, and only the holder.

*Protects:* the raid disagreeing about its own record of the evening.

## C8 — A reload changes nothing

Reload mid-distribution — as the lootmaster, as a council member, and as a plain raider, one attempt
each. The session comes back, the item is still tracked, the trade deadline still counts from when
the boss died, and a re-decision after the reload is still a re-decision (it asks first, and the raid
follows it).

*Protects:* B34 (the four-hour clock restarting, which loses the item silently) and B77 (the person
who just decided being the only client showing their own decision).

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

| run | date | result |
|---|---|---|
| _(none yet)_ | | |

Fill this in. A Manifest with no recorded run is a list of intentions.
