# The Manifest

**The standard KART is held to: ten times out of ten, in the game.**
Named "das Manifest" so it can be pointed at in one word — "gegen das Manifest getestet".

**Settled for 4.0 on 2026-08-17.** Built-in loot council items C1–C15 are retired. Loot session,
force-win, voting, trade reminders and loot history are **RCLootCouncil's** job.

## The 4.0 rule

The companion must not hinder, abort, or break RCLootCouncil's loot flow.

That is the whole Manifest. Nick-stable council and award relay are features, specified in
[`docs/4.0-RC-COMPANION.md`](4.0-RC-COMPANION.md). A missed nick or a failed whisper is a companion
bug. A hung, cancelled, or corrupted RC session is a Manifest failure.

## How to read this

Ten out of ten means **in the game, with two clients, ten separate attempts** — not ten green test
runs. The automated suite is the floor, not the standard.

## Raid-lead tools (unchanged scope)

Invite keywords, auto-promote, auto-raid conversion, raid-lead bar, enhanced ready-check reasons,
buff checker and KART Sync, profiles and settings UI — same product as before 4.0, minus
built-in loot council, droptimizer column and the discontinued desktop KART Companion.

## What a failure means

One failure in ten is a failure. Note both clients' RC session state (open, awarded, aborted)
and whether KART was in the path (`/kart v`).

## Standing result

| run | version | date | scope | result |
|---|---|---|---|---|
| three-man `/kart add` | 3.2.0 | 2026-07-31 | built-in LC smoke | historical — LC removed in 4.0 |
| **guild raid** | **3.3.0** | **2026-08-03** | built-in LC Manifest | **historical — see CHANGELOG; LC removed in 4.0** |

4.0 is not called done until this rule holds 10/10 in-game.
