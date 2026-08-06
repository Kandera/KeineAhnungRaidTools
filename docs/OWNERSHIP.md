# Ownership: who owns the settings, who hands out the loot

Maintainer's decision, 2026-07-31. This replaces the derivation that grew out of B29–B33, B64, B69
and B70. Those entries stay in the backlog as history; the rules below are what the code implements.

## The two roles are separate, and only one of them is claimed

**Config owner — the current raid leader.** Nobody else. Not derived from anybody's settings, not
from who started the session, not from what a client happens to be holding. `UnitIsGroupLeader` is a
fact every client can check about every other client, from its own roster, at any moment.

**Loot owner — whoever the raid config's Lootmaster field names.** That field lives on the config
owner's client and is a *designation*: the raid leader says who hands out the loot. It normally names
somebody else. If it names nobody, the raid leader does it themselves.

## Why this shape

The old rule asked "does my own Lootmaster field name me?", which made ownership something a client
CLAIMED rather than something the raid could observe. Everything expensive followed from that:

* Two clients could both believe they owned it (B64), or neither could (B70).
* A claim had to be defended against invented ones after a reload, which needed `fromSelf`,
  `sessionStartedByUs` and a timed grace — three pieces of state that each went wrong on their own
  (B69, B70).
* It put the burden on every raider to maintain a field the raid leader is the one who decides.
  Told plainly by the maintainer: "ich lege den Lootmaster als Raidlead fest" — a raid leader cannot
  make twenty people keep a setting in sync, and should not have to.

Raid lead is already the authority the game itself tracks and every client already agrees on. Using
it removes the claim, and with it the whole class of disagreement.

## The rules

1. `LC.IsConfigOwner()` is true exactly when we hold raid lead (or are not in a group at all, so
   solo testing still works).
2. Only the config owner broadcasts `LC_CONFIG`.
3. A received `LC_CONFIG` is accepted exactly when the sender holds raid lead, checked against our
   own roster. There is exactly one such client, so there is nothing to arbitrate.
4. The Lootmaster field is a designation. `declaredKey ~= senderKey` is the NORMAL case and must not
   be a rejection — that guard belonged to the old rule, where the sender had to be naming itself.
5. Changing the lootmaster means ending the session and starting it again. There is no mid-session
   handover, so no resign token and no successor negotiation is needed.
6. A designated lootmaster who is not in the raid falls back to the raid leader, who is asked before
   taking over (unchanged — standing in force-wins items into somebody's bags and is not done to
   them silently).
7. An empty Lootmaster field hands the loot to the raid leader only when it came from somebody who
   was allowed to name somebody: the config owner's own settings, or their `LC_CONFIG`. A relay
   names nobody — it does say **whether** the raid has named somebody and whether that person is
   here. If it says the raid has named somebody who is present, that person hands out the loot and
   the raid leader does not. If it says the raid has named somebody who is gone, that is the same
   situation as a lootmaster who has left the raid, and the raid leader is asked whether to stand in.
8. **Which items the lootmaster is given at all.** Bind-on-Pickup gear that is not a collectible,
   plus one named exception: a **recipe** (item class 9 -- recipes, patterns, plans, formulae),
   whatever it is bound as and whatever the raid's minimum quality is set to. Everything else
   Bind-on-Equip, and every collectible -- mounts, pets, toys, housing decor -- stays outside Loot
   Council entirely and is left to Blizzard's own roll window.

   The recipe exception was asked for on 2026-08-06 (#34): in this guild a recipe always ends up
   with the lootmaster, and nothing made that happen. It costs the guarantee the rest of the rule
   was written for -- a raider not running KART can win Blizzard's roll on a recipe, leaving the
   council to decide something nobody can hand over. Accepted because KART is mandatory here, which
   is an assumption about people rather than a guarantee from the code.

## What this costs

Raid lead moving mid-raid means the new leader's settings become the raid's. That is intended: the
raid leader is the authority, and the settings follow the authority rather than lagging behind it.
The Sync Settings button exists for the case that matters in practice — handing your base settings to
whoever stands in for you on an evening you are out, so they do not configure from scratch.

The deferral in rule 7 lasts only until that leader broadcasts a config of their own. A leader with an
empty Lootmaster field then puts that emptiness on the wire, the raid adopts it, and the loot falls
back to the leader — the same trade-off as above, one field over. What rule 7 buys is not a permanent
correction but the guarantee that the raid never has two people handing out loot at once: before the
broadcast the leader defers to a designation it cannot see, and after it the whole raid agrees there
is none.

## What must stay true

Held to the 10-out-of-10 standard in `MANIFEST.md` -- C1, C2, C3, C9 and C10 are these rules seen
from the raid's side.


* Exactly one client broadcasts a config at any moment, and every client can name which one.
* No client ever has to decide between two configs on content.
* A raider never needs to configure anything for the raid to work.
