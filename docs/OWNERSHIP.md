# Ownership: who owns the settings, who hands out the loot

Maintainer's decision, 2026-08-17. **Loot rules live in [`docs/4.0-RC-COMPANION.md`](4.0-RC-COMPANION.md).**
This file keeps the raid-lead ownership that did not change in 4.0.

## Loot (4.0)

KART no longer runs a loot council. **RCLootCouncil** owns session, group loot, voting, trade and
history. The raid leader is RC's master looter.

KART's companion role:

1. The **raid leader** types council **nicknames** (or character names) into `rcCouncilMembers`.
   KART resolves them through Northern Sky and pushes the matching GUIDs into RC's council list.
2. **Council members** click Award in RC's voting frame; KART relays that click to the raid
   leader's client, which calls RC's `Award()` while the leader trades.
3. **Winners** see a KART owed reminder (personal toggle, default on) so they can walk to the
   lead and trade. RC's TradeUI remains the lead's list.

There is no separate lootmaster field in KART 4.0. The lead holds the items and the TradeUI.

Invite, auto-promote and buff-check ownership below is unchanged.

## Config owner — raid lead tools

**Config owner — the current raid leader.** `UnitIsGroupLeader` is a fact every client can check.
The raid-lead bar, invite keywords, auto-promote list and buff-check settings are each player's
own KART settings unless noted otherwise; they are not broadcast raid-wide like the old LC config
was.
NSRT Notes (`NT_STATE`, `NT_LEAD`, `NT_STATE_REQ`) is the exception: boss order, skips, cursor, operator name, generation and cursor checksum are raid-broadcast so the note operator and the lead share one stand. `NT_LEAD` is the lead's in-instance Restricted window; `NT_STATE_REQ` is a pull, not a push on hello. It is not loot-config sync.

## What must stay true (raid-lead tools)

Held to the 10-out-of-10 standard in `MANIFEST.md`: the companion must not hinder, abort, or
break RCLootCouncil's loot flow. Invite, promote and buff-check keep the bar they shipped
with before 4.0. Nick push and award relay are specified in `docs/4.0-RC-COMPANION.md`.
