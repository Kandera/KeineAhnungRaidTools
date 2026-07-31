# The Manifest

**The core functions, and the standard they are held to: ten times out of ten.** Named "das Manifest"
by the maintainer on 2026-07-31 so it can be pointed at in one word -- "gegen das Manifest getestet",
"das bricht C7". Use that name; it is the whole reason this file has a short one.

The standard, in the maintainer's own words about the ownership rework: *"Die Funktion ist eine der
10/10 Grundfunktionen die funktionieren muss."*

**DRAFT — the list below is derived, not dictated.** It comes from `docs/OWNERSHIP.md`, from the
failures the backlog records as having cost real raid evenings, and from the operating reality the
maintainer has described. It needs the maintainer's correction before it counts.

## How to read this

Ten out of ten means **in the game, with two clients, ten separate attempts** — not ten green test
runs. The automated suite is the floor, not the standard: it is 1263 assertions and a 30000-run
convergence soak, and it still cannot see a cursor, a Blizzard roll window, or a real reload.

Each item says what must be TRUE at the end, not what to click. If an item needs a third body, an alt
parked in the raid is enough.

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

A mount, a Bind-on-Equip and a rare-quality item drop. KART does not touch any of them: no force-win,
no forced pass, Blizzard's own roll window behaves normally.

*Protects:* housing decor being force-won, which has happened, and a BoE the lootmaster can never
hand over.

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

---

## What a failure means

One failure in ten is a failure. Write down what was on each screen at the moment it went wrong —
which client, what it showed, what the others showed. That is what makes it reproducible; the
convergence soak exists because "it broke somehow" cost three evenings before anything could be
measured.
