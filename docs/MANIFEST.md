# The Manifest

**The core functions KART still owns, and the standard they are held to: ten times out of ten.**
Named "das Manifest" so it can be pointed at in one word — "gegen das Manifest getestet".

**Settled for 4.0 on 2026-08-17.** Built-in loot council items C1–C15 are retired. Loot session,
force-win, voting, trade reminders and loot history are **RCLootCouncil's** job. KART ships a
companion only; see [`docs/4.0-RC-COMPANION.md`](4.0-RC-COMPANION.md) for the full split.

## How to read this

Ten out of ten means **in the game, with two clients, ten separate attempts** — not ten green test
runs. The automated suite is the floor, not the standard.

## KART 4.0 — RC companion contracts

These two behaviours are KART-owned in 4.0. Everything else about loot is RC's.

### Contract 1 — Nicknames survive an alt swap

The raid leader maintains `rcCouncilMembers` as nicks (or names). On roster change and when the
field is edited, KART writes only the GUIDs of council nicks whose **current alt is in the group**
into RC's council table. A nick whose player is on a bench alt is omitted until they join; stale
GUIDs from last week's alt are not kept. Non-lead clients never write RC's council table.

**Protects:** recouncil every time someone swaps to an offspec alt mid-tier.

### Contract 2 — Council click awards on the lead's client

When a council member who is **not** RC's master looter clicks Award, KART whispers the raid
leader; the leader's client calls RC's `Award()`. Council members need KART for the relay; the
leader needs KART to receive it. RC absent: KART still runs invites, promote and buffs; loot is
unmodified Blizzard group loot.

**Protects:** the raid-lead tank stuck in RC's voting frame while the council decides.

## Raid-lead tools (unchanged scope)

Invite keywords, auto-promote, auto-raid conversion, raid-lead bar, enhanced ready-check reasons,
buff checker and KART Sync, profiles and settings UI — same product scope as before 4.0, minus
built-in loot council, droptimizer column and the Companion tray app.

## What a failure means

One failure in ten is a failure. For companion defects, note both clients' RC council list and
whether the Award whisper reached the leader (`/kart v` still prints KART versions).

## Standing result

| run | version | date | scope | result |
|---|---|---|---|---|
| three-man `/kart add` | 3.2.0 | 2026-07-31 | built-in LC smoke | historical — LC removed in 4.0 |
| **guild raid** | **3.3.0** | **2026-08-03** | built-in LC Manifest | **historical — see CHANGELOG; LC removed in 4.0** |

4.0 companion contracts are held to 10/10 in-game before release is called done.
