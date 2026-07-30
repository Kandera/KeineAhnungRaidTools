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

## B56 — a toy can be force-won when the Toy Box has not been populated

`LC.IsCollectibleItem` keeps mounts, pets and mount equipment out by subclass, so `C_ToyBox.GetToyInfo`
is the only thing keeping a toy out of Council — and toys share subclass 0 with the tier tokens the
carve-out was narrowed for. `GetToyInfo` answers nil whenever the Toy Box data has not loaded for the
session, e.g. on a fresh login where Collections was never opened. The item is then not a collectible,
the lootmaster force-wins it, and every Auto-Pass raider passes: the standing "collectibles never
enter Loot Council" rule broken in the same direction as the housing-decor incident of the same day.

Deliberately not fixed by guessing at another discriminator. Item level and bind type would separate
tokens from toys in every case checked, but neither was measured, and inventing an unmeasured rule is
exactly what produced the housing regression. It wants either a reliable "is this a toy" answer that
does not depend on Collections being loaded, or a measurement of what distinguishes the two.

## B57 — the council window kept every previous boss's items despite End Round (GitHub #15)

Reported with a screenshot showing items from earlier bosses still listed. The maintainer confirms he
pressed End Round and that he held raid lead, which means the sender check on the receiving side
(`IsSenderLootOwner`, falling back to raid leader when no config has been distributed) should have
passed, and `LC.ClearAllRolls` demonstrably clears the vote list and the tab strip and hides both
windows. No path in the code explains the report.

That evening also had continuous session failures and manual restarts, so the state the message
landed in is not reconstructable. Deferred to the next raid with a working session rather than fixed
speculatively. If it reproduces there, the next thing to establish is whether the peers received
`LC_END_ROUND` at all.

---

# Tier 0 — reopened

## B55 — confirm dialogs are buried again (was B8), and the old fix must never come back

B8's fix raised Blizzard's popup frame to the `TOOLTIP` stratum on show and restored it on hide. It
worked, and it broke the game: those frames are a shared pool, an insecure `SetFrameStrata` taints
the frame for the rest of the session, and the next Blizzard dialog handed that same pooled frame has
its protected calls refused — reported from a live raid as `ADDON_ACTION_FORBIDDEN ... tried to call
the protected function 'UpgradeItem()'`, with KART blamed for a dialog it never registered. Players
could not upgrade items until they reloaded.

The lift is gone as of 2026-07-29, so B8's original symptom is back: a consumer whose windows sit at
or above `DIALOG` buries its own confirm dialog behind the window that raised it, and pressing the
button looks like it did nothing.

The fix has to stay on our side of the frame boundary. Two candidates, both taint-free because they
only touch our own frames: lower the consumer's own windows while one of our popups is up, or stop
using Blizzard's StaticPopup for our own confirms and build them from `KAUI:ApplyPopupArtwork`, which
already backs every other window in the addon. Seven call sites use `RegisterStaticPopup` today.

---

# Tier A — the loot flow stops for the whole raid

B29 to B33 share one root: ownership and session state are distributed across clients with no single
authoritative holder. They want one design pass, not five patches.

## B29 — a departed lootmaster leaves the raid with no loot owner — FIXED 2026-07-30

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

`IsConfigOwner()` reads `KART_Settings.lcLootmaster` directly, so an empty field — an explicitly
supported setup per `LC_SET_LOOTMASTER_HINT` — means `ApplyOwnConfig` and `BroadcastRaidConfig` both
return early. `LC.CouncilNamesTable` stays empty on every client, so every listed council member gets
no panel all night, and every client falls back to its own button labels: the B25 vote-label mismatch
by another route. The role-status label meanwhile reports that all is well.

**Fixed 2026-07-30.** `IsConfigOwner` falls back to the raid leader on an empty field, exactly as
`IsLootOwner` already did — the two derivations disagreeing was the bug. The fallback stands down as
soon as somebody else actually claims the role, so it cannot fight a named lootmaster. Covered by
`tests/test_lc_baseflow.lua`.

## B58 — nobody hands a late joiner the config while the lootmaster is away

Follows from B29's fix, and is the price of not letting a stand-in rewrite the raid's settings.
`LC.HandleStateRequest` sends the config only if `LC.IsConfigOwner()`, and while a named lootmaster is
merely absent that is nobody: the stand-in leader owns the loot flow but not the settings, on purpose.
Anyone joining in that window gets the session flag and no config, so they run their own vote-button
labels, minimum quality and roll setting until the lootmaster returns or somebody names a successor.

Narrower than what it replaced — B29 left the whole raid unable to distribute anything — and it only
bites someone who joins during the gap. The fix is a way for the loot owner to forward the config
they are holding, rather than broadcasting their own, which needs `TryAcceptConfig` to stop rewriting
`raidConfig.lootmaster` to the sender. Not attempted while the base flow is still being proven.

## B59 — a lootmaster whose own field does not resolve owns nothing, and is never told

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

## B60 — the lootmaster losing Blizzard's roll is undetected, and the obligation auto-confirms

`ForceWinRoll` rolls and nothing checks the outcome. A raider not running KART can out-roll the
lootmaster; the council still awards, and `Trade.AddPendingTrade` records an obligation for an item
the lootmaster does not have. `Trade.OnTradeClosed` then reads "not in my bags" as "already traded"
and clears the reminder the next time that same winner is traded with for anything at all. The
reminder tidies itself away, the lootmaster believes it is done, the winner never receives anything,
and the history says they won it.

## B61 — council membership is only evaluated when the roll starts

`Council.ShowCouncilPanel` is called from the four roll-start sites and nowhere else, and
`LC.IsCouncil()` is read once, there. A client whose config arrives afterwards — a late retry
success, a state-request reply — is council from that moment on but has no tab for the items already
on the table, and cannot assign them. Narrow, because a client that late usually has no tracked items
either, but real for one that already had them.

## B62 — a client on the previous release rejects everything a stand-in or a successor sends

`LC_RESIGN` and `LC_SESSION_RESUME` are new tokens, and an older client drops an unknown token
silently. So a v3.2.1 client keeps naming a lootmaster who has left or stepped down, which makes
`IsSenderLootOwner` reject every `LC_START`, `LC_ACTIVE` and `LC_END_ROUND` from whoever actually
took over — no vote window on any item, for the rest of the raid, with nothing printed on either
side. Not fixable from our side; the raid has to be on one version. Worth saying out loud in the
release notes rather than discovering mid-boss.

## B63 — one broadcaster: if the loot owner gets no roll event, nobody sees the item

`LC_START` for a real drop is sent from exactly one place, inside the loot owner's own
`START_LOOT_ROLL` handler. The owner is subject to the same conditions as everyone else — out of
range, ineligible, released — and there is no fallback broadcaster. Meanwhile every other client's
Auto-Pass still fires, because that branch does not depend on the owner having acted. Visible outcome
is identical to "nobody stood in": Blizzard's window opens, every KART user passes, no vote window
anywhere.

## B64 — before the first config, the leader and the lootmaster both believe they own the loot flow

No config is on the wire until a session starts, so until then every client has
`raidConfig.lootmaster == ""` and the raid-leader fallback is live on the leader while the lootmaster's
own field makes them the owner too. Both are offered the session prompt; whoever answers first
decides. It converges once a named config lands (a named lootmaster now outranks an empty-field
claim, see B29/B33), but the window is real and the loser of the race spends it with
`sessionActive == false`.

---

# Tier B — an item is lost or awarded wrongly, silently

## B34 — a reload mid-roll loses the item entirely

Only `KART_LCTrades` and `KART_LootHistory` are SavedVariables, and `Trade.RestorePersistedTrades`
only rehydrates decided trades. Everything about an undecided roll — item link, votes, deadlines,
tabs — is in memory only. The lootmaster force-wins a Bind-on-Pickup item, reloads before the council
assigns, and `START_LOOT_ROLL` will not fire again: they hold a real item that no client, no saved
variable and no window still associates with a roll.

## B35 — two council members can award the same item at the same time

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

## B65 — once the lootmaster is gone for good, a later arrival gets no config at all

Standing in deliberately moves only the LOOT FLOW, not the config: the departed lootmaster's name
stays in `raidConfig.lootmaster` so they can pick the role back up when they return (see
`LC.HandleResign` and `LC.IsConfigOwner`). Nobody owns the config while that is true, so nobody
re-broadcasts it — and anyone joining afterwards has none. They still get the session, so they see
vote windows and answer them, but with THEIR OWN button labels, their own minimum quality and their
own roll setting. Their vote arrives at the council under a different label than they clicked.

Everyone who was already there keeps the raid's config, so the raid does not come apart; it is the
newcomer alone. Pinned by a test in `tests/test_lc_churn.lua` that asserts today's behaviour, so a
fix cannot land silently.

The obvious fix — let the stand-in relay the config they hold — is not a small change: a relayed
`LC_CONFIG` names someone other than its sender in the lootmaster field, which is exactly what
`TryAcceptConfig` rejects (B29/B33 hardened that on purpose). It needs its own token and its own
precedence rule, and that is a design change rather than a patch.

## B66 — an item announced while a client is deaf is lost to that client

`LC_START` and `LC_RESULT` are announced once and never re-requested. A client is deaf for two
ordinary reasons: it is still recovering from a reload (it has asked for the state and is waiting),
or Blizzard's chat throttle dropped the message. It then has no way back to that item — the loot
history catch-up runs on JOIN only, and there is no equivalent for rolls in flight.

Bounded in practice: that raider does not vote on that one item, and the council sees no answer from
them. The severe variant — the LOOTMASTER being the deaf one, so nobody force-wins — was narrowed by
making the state request's first retry come at 2s instead of 5s, and by letting ordinary raiders
answer a reloaded owner's request (see `LC.HandleStateRequest`). Narrowed, not closed.

A real fix is a catch-up for rolls in flight: on learning the session is running, ask for the rolls
currently open and rebuild them, the way `LH.RequestHistorySync` does for awards. That is a new
message and a new path, worth doing deliberately rather than the night before a raid.

`tests/test_lc_soak.lua` excludes exactly these two windows from its per-item comparison, and says so
where it does it — everything with a retry behind it is still held to the full standard.
