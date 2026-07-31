# Backlog — known defects, not scheduled

Defects found while working through the v3.0.0 library extraction and the raids after it, each with
a traced cause rather than a guess. This file exists so the diagnosis is not redone from scratch.

Companion to `REVIEW-DECISIONS.md`, which records findings deliberately **not** changed. This file
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

Entries marked **[opt-in]** can only fire while `lcHideIrrelevant` or `lcAutoTransmogVote` is on.
Both default to off, so an untouched install is not exposed to them.

---

# Tier 0 — reopened and unresolved

## The ownership rework, 2026-07-31 — what it closed

`docs/OWNERSHIP.md` replaces the derivation that B29–B33, B57, B58, B64, B69 and B70 all pull on.
Config ownership is the raid leader; the Lootmaster field is a designation that names somebody else.
Those entries are marked superseded rather than deleted, because each is a real failure this guild
paid for and the rules were written to make them unreachable rather than merely fixed.

Three of them are worth calling out, because the rework did not fix them — it removed the state they
needed:

* **B57** needed the leader's own client to believe it owned the loot flow while its peers held a
  config naming somebody else. The designation lives in the leader's own settings now, and
  `KART_Settings` is a SavedVariable, so it survives their reload and the two answers cannot come
  apart. Its test asserts the agreement.
* **B70** needed "nobody owns the config". Ownership is raid lead, which is never held by nobody and
  never by two people. Its test asserts exactly that across a lead change.
* **A nickname nobody can resolve** used to mean nobody owned the config and the whole raid silently
  kept its own roll setting. Ownership needs no name resolution at all now.

What the rework cost, recorded so it is not rediscovered as a bug: a raid-lead change switches the
raid to the new leader's settings. Confirmed with the maintainer, together with the requirement that
it must not be silent — `LC_CONFIG_OWNER_NOW` says so once per time the role arrives. One field is
exempt: an empty council list means "not configured", not "this raid has no council", because the
soak showed 94 of 3000 raids losing an award to a momentary leader who had never configured KART.


## B56 — a toy could be force-won — FIXED 2026-07-30, but not for the reason recorded

The entry described the cause as an unpopulated Toy Box: `C_ToyBox.GetToyInfo` would answer nil until
Collections had been opened, so a toy read as ordinary gear. Measured in a live client rather than
reasoned about, and **every part of that premise is false**. Fresh client restart, straight to the
probe, Collections never opened:

* `C_ToyBox.GetNumToys()` → 1144, `GetNumLearnedDisplayedToys()` → 425. The box is fully populated on
  login, and it holds far more than what the player has collected.
* `GetToyInfo(229828)` answers for a toy the player does **not** own.
* It answers while the box's own display filter is down to 41 entries, so it is not filter-scoped.

The real cause was one line above the toy lookup. `IsCollectibleItem` opened with
`if classID ~= 15 then return false end`, on the assumption that toys share the tier tokens' bucket.
Counting the classes of one player's 41 toys: **39 are classID 15, but 2 are classID 0 — Consumable**
(229828 is 0/8). Those two never reached the toy lookup at all. A toy in Consumable read as ordinary
Bind-on-Pickup gear: force-won by the lootmaster, passed by every Auto-Pass raider — the standing
rule broken, exactly as the entry said, through a bucket nobody had looked in.

The three journal lookups now run before the class is consulted. An item the client itself identifies
as a mount, pet or toy is one whatever compartment Blizzard filed it under, and no gear token appears
in any journal, so asking first cannot pull a token out of Council. The allow-list for Miscellaneous
is untouched — that is the part keeping housing decor out, and it still decides everything the
journals cannot name.

Covered in `tests/test_lc_collectible.lua`; the three new assertions were verified by re-gating the
journals behind `classID == 15` and confirming all three turn red.

## B57 — End Round cleared only the presser's own window (GitHub #15) — FIXED 2026-07-30

> **Superseded by the ownership rework, 2026-07-31 (see `docs/OWNERSHIP.md`).** Config ownership is
> the raid leader and nothing else, so the claim these entries arbitrate no longer exists. Kept as
> history: each one is a real failure this guild paid for, and the rules were written to make them
> unreachable rather than merely fixed.

Reported with a screenshot of items from earlier bosses still listed, by a maintainer who had pressed
End Round and held raid lead. No path in the code explained it, because each side of the exchange
looks correct on its own. They only disagree when compared:

* The button is enabled by the presser's own `LC.IsLootOwner`, which falls back to the raid leader
  whenever their client holds no config naming somebody else — normal after a reload while the config
  is slow to come back, or in a raid where it never reached them at all.
* Their peers judge the incoming `LC_END_ROUND` with `IsSenderLootOwner`, and THEY do hold a config
  naming the real lootmaster, so they threw it away.

The presser's window cleared, every other window kept the round, and nothing was printed on either
side. Reproduced in `tests/test_lc_churn.lua` by reloading the raid leader with `LC_CONFIG` and
`LC_CONFIG_RELAY` blackholed, which is exactly that state.

`LC.HandleEndRound` now accepts from any council member. That is the right width for what the action
does — it clears the current round's tabs and vote rows and does not touch the session — and a
council member can already assign an item outright, which is far more authority than clearing a
list. `IsSenderCouncil` accepts the loot owner too, so it is strictly wider than what it replaced.

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

## B70 — a raid-lead change during B69's grace leaves the raid with NO config at all — REGRESSION, introduced 2026-07-30

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

## B61 — council membership is only evaluated when the roll starts

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

## B64 — before the first config, the leader and the lootmaster both believe they own the loot flow

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

## B36 — "irrelevant" is far wider than the setting claims **[opt-in]**

`irrelevant = not canNeed` treats every reason Blizzard disables Need as "your class cannot equip
this": wrong loot specialization, level requirement, unique-equipped. `reasonNeed` sits in the same
return and is discarded. A Holy Paladin with hiding on never sees a strength plate chest they would
have taken for off-spec — the exact case the feature was designed to keep visible (GitHub issue #11).
The same expression turns an unknown `canNeed` into "irrelevant", which the file's own header forbids;
`needsAppearance` on the same line resolves unknown the safe way.

## B37 — the relevance snapshot outlives the roll it describes **[opt-in]**

`Trade.ClearRollState` deliberately keeps `relevanceSnapshot`, arguing the relevance frame has already
snapshotted the new item. That holds for the `LC.OnStartLootRoll` caller and not for `LC.HandleStart`,
which exists precisely for clients that got no local `START_LOOT_ROLL`. A raider who was dead for the
reused rollID gets the previous item's verdict applied to the new one — a best-in-slot piece
auto-passed without ever being drawn.

## B38 — the snapshot records no item identity, and is written for rolls Council ignores **[opt-in]**

The `START_LOOT_ROLL` handler has no `councilEngages` gate, and `LC.OnStartLootRoll` returns before
`PurgeStaleRoll` for rolls Council does not engage. So a trash Bind-on-Equip drop or collectible
reusing a live rollID silently rewrites the snapshot of the item currently being voted on, and nothing
purges it. Those are exactly the items trash drops constantly.

## B39 — the appearance fallback answers the wrong question **[opt-in]**

`NeedsAppearance`'s non-snapshot path asks "do I already own this appearance", never "can I collect
it": the sourceID from `C_TransmogCollection.GetItemInfo` is discarded and `PlayerCanCollectSource` is
never called. It is consulted only for items the player cannot equip — the population where the two
questions diverge — so it can broadcast a Transmog vote on an appearance that character can never
learn, and the council may award the item on the strength of it.

---

# Tier C — one player drops out of the round

## B40 — a "???" item link permanently blinds the reused-rollID detector

`LC.HandleStart` builds the link only from `GetLootRollItemLink`, which returns nil for a dead or
out-of-range client, and `ResolveRollItemLink` retries the same nil-returning API and gives up — even
though the `LC_START` payload carried the itemID, which the code parses and then never uses to rebuild
a link (`Trade.HandleResult` performs exactly that rebuild). `"???"` fails `IsRealItemLink`, so
`PurgeStaleRoll` bails for the rest of the session and every per-roll table survives into the next
item: the raider's row shows an old vote and they can never vote again.

## B41 — the voted-items filter removes the row the correction lives on **[opt-in]**

`Vote.GetVisibleRolls` tests `LC.votedByMe[rollID]` raw, without the `not isAuto` exemption both row
renderers apply. With "voted item display = hide" an auto-cast Transmog vote removes its own row on the
next refresh, so the hint "click any response to change it" points at a button that is not on screen —
and unticking the hide setting does not bring an auto-passed row back either, contrary to the guarantee
stated in that function.

## B42 — snapshots are swept before the vote row they belong to exists **[opt-in]**

The self-sweep protects `rollID` itself and entries in `LC.voteListRolls`, but on a non-lootmaster
client a roll only enters that list when `LC_START` arrives — one round trip after the local
`START_LOOT_ROLL`, by which time Auto-Pass has blanked `GetLootRollItemInfo`. On a multi-item boss each
roll's snapshot is deleted while handling the next one, so only the last item keeps Blizzard's verdict
and the rest fall through to the armor rule, which answers nil for weapons and jewellery.

---

# Tier D — the wrong thing is displayed

## B43 — the vote-count guard is length-only

`voteData.count` catches a change in the number of buttons, not a same-length rename or reorder. The
config owner editing labels mid-roll pushes the new set live, and votes cast before the edit are then
rendered under whatever the label became, with no "unknown" fallback.

## B44 — the council tab tooltip skips the guard entirely

It resolves `buttons[tonumber(voteData.idx)]` without reading `voteData.count`, so it states a label
with full confidence for the same vote the row list below it correctly renders as "?".

## B45 — the voter's own badge has no guard at all

`votedDef` is resolved against whatever `GetButtonConfig()` returns right now, with no stored count.
After a mid-roll label edit the raider is told they voted something they did not.

## B46 — a late vote is accepted onto a reused rollID

`Vote.HandleVote` and `Vote.HandleCouncilVote` check only that *some* item is tracked under the rollID,
not that it is the same one. A network-delayed vote for the previous item lands in the new item's tally.

---

# Tier E — cleanup, cosmetics, narrow triggers

## B47 — expired pending trades are pruned only by a reload

`Trade.CheckTradeTimeouts` warns and never removes; the only pruning happens in
`Trade.RestorePersistedTrades` at `ADDON_LOADED`. Hours past Blizzard's real trade window, dead entries
still sit in the reminder list, indistinguishable from live ones.

## B48 — a self-assigning council member gets no reminder

`LC.owedToMe` is populated only in `Trade.HandleResult`, i.e. only on a client that *received* the
broadcast. A council member who assigns an item to themselves never processes their own message and so
never gets their own "you are owed this" entry, though the lootmaster's queue is correct.

## B49 — hiding every row stops the pruner **[opt-in]**

The window hides when `GetVisibleRolls` comes back empty, and `OnHide` cancels the ticker that is the
only thing calling `Vote.PruneExpiredRolls` during a batch. The rolls never expire and never reach
`Trade.ClearRollState`; `/kart showall` later reopens long-dead rolls with live vote buttons.

## B50 — `relevanceHandled` ignores the settings that produced the answer **[opt-in]**

The latch is permanent per roll, so ticking the other switch mid-batch does nothing for rolls already
answered — the setting appears inert and the broadcast Pass stands.

## B51 — `/kart lc` shows frozen hidden rows **[opt-in]**

That path calls `voteListFrame:Show()` directly with no refresh, so the pool still holds the last drawn
layout: a window full of items the player was told were hidden, with stopped countdowns, until the
ticker's first prune hides it again.

## B52 — an accepted config does not repaint an open council panel

`LC.HandleConfig` omits the `RefreshCouncilPanelIfOpen()` call its own retry path makes, so a council
member keeps seeing votes under the old label set until some unrelated event refreshes the rows.

## B53 — a legacy note beginning with a hash and digits is misparsed

`ParseVotePayload`'s count disambiguator can match a pre-3.1 client's note, truncating it and
fabricating a count the sender never sent — which then either wrongly trips or wrongly satisfies the
mismatch check.

## B54 — auto-answers rebuild the window once per roll, nested **[opt-in]**

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
