# Backlog — known defects, not scheduled

Defects found while working through the v3.0.0 library extraction, each with a traced cause rather
than a guess. None is scheduled; this file exists so the diagnosis is not redone from scratch.

Companion to `REVIEW-DECISIONS.md`, which records findings deliberately **not** changed. This file
records findings that *should* change, eventually.

Most of these surfaced because the addon was clicked through systematically for the first time
during the v3.0.0 in-game checkpoints. Six of the remaining eight pre-date the refactor and were
confirmed identical before and after it. Two were introduced by it and are marked as such — they must
not drift into being treated as pre-existing.

**2026-07-27:** B1 (shift-clicked items) and B5 (small close button) were fixed and removed from
this file; see the commit that fixed them for details.

---

## B2 — The font setting does not reach some widgets

**Symptom:** changing the font leaves these unchanged: the sidebar tab buttons; the Language, Accent
Colour, Reset Defaults and Profile buttons; and all Loot History table row content.

**Cause:** not fully diagnosed for the sidebar tab buttons or the Language/Accent Colour/Reset
Defaults/Profile buttons — unlike Loot History's rows (below), the sidebar tabs *are* registered via
`CreateTabButton`'s self-registration, so an unregistered-widget explanation doesn't obviously fit;
worth a fresh look rather than assuming the same cause. For Loot History specifically: its per-row
FontStrings were never registered into a styling registry — only the column headers were.

**Fix direction (Loot History rows):** register row FontStrings as they are created.

**Pre-existing** — a task-4 investigation compared both commits and found zero regressions; the
registration calls, registry membership and styling loops are mechanically identical. The refactor
did centralise the registries, so this is now easier to fix than it was.

**2026-07-27:** the Loot Council half of this entry (the vote frame's "Note" label, the council
panel's "No Winner"/"Close Session"/"Close" buttons, and the session-invite prompt's Yes/No buttons —
all built lazily, after the last `ApplyStyle`, and never re-styled afterwards) was fixed and removed
from this entry's symptom list. This entry now covers only the three symptoms listed above.

---

## B3 — Background opacity never reaches the Loot Council windows

**Symptom:** the background-opacity setting has no effect on either Loot Council window.

**Cause:** the `bgAlpha` block only ever wired the main window and the Loot History window. The two
Loot Council windows' `.bg` textures were never connected to it.

**Pre-existing.**

---

## B4 — The minimap toggle leaves the button behind

**Symptom:** turning the minimap icon off hides the icon texture but not the button frame.

**Cause:** `KART.UpdateMinimapButton` calls LibDBIcon's `Show`/`Hide`. Untouched by the refactor.

**Pre-existing.**

---

## B6 — The WoW Utils paste box only takes focus in its upper part

**Symptom:** clicking the middle of the paste box does not start editing; only the top does.

**Cause:** unresolved. Note that `Invite.lua:408-413` already carries a fix attempt for exactly this
— the EditBox is given `SetHeight(300)`, taller than the 90px viewport, so that clicks below the
first line still land on it — together with a comment explaining the reasoning. That line is present
and unchanged, so the fix is incomplete rather than absent.

**Fix direction:** start from that comment rather than re-deriving the problem.

**Pre-existing.**

---

## B7 — Solo, a lootmaster configured by name or nickname cannot be resolved

**Symptom:** alone, with yourself entered as lootmaster, every loot-owner control stays disabled —
"Close Session" greyed out, and so on.

**Cause:** `KAUtil.EachGroupUnit` derives its token count from `GetNumGroupMembers()`, which is `0`
outside a group. The iterator therefore yields nothing and `"player"` is never visited, so live name
and nickname matching cannot find you at all. `LC.IsMe` then compares your own GUID against
unresolved config text and returns false.

The only rescue is `ResolvePlayer`'s persistent `KART_PlayerCache` fallback, which is warmed as a
side effect of resolving `"player"` — so behaviour can differ between a cold first call and a later
refresh.

**Open design question:** should `EachGroupUnit` yield `"player"` when solo? That is a behaviour
decision, not a repair. Note that `KAUtil.EachGroupUnit` now lives in a library with a roster stub,
so whichever way it is decided, `KARTTEST.SetParty({})` makes it a three-line regression test.

**Pre-existing** — byte-for-byte identical to its pre-refactor form.

---

## B8 — Blizzard confirm dialogs can be buried under KART windows

**Symptom:** pressing "Close Session" appears to do nothing. The confirm dialog does open — behind
the council panel.

**Cause:** KART windows take their stratum from the user's frame-strata setting; Blizzard's
`StaticPopup` frames are fixed at `DIALOG`. At the default `HIGH` the popups sit on top correctly,
but any setting of `DIALOG` or above puts the window over them. Affects all four confirm dialogs:
close-session, reassign, clear-history and sync-request.

KART's *own* drawn dialogs are immune — they register with `isDialog = true`, and `GetDialogStrata`
always returns one stratum above the windows. Only the Blizzard popups escape that system.

**Fix directions:** clamp the window stratum below `DIALOG`; raise the popup frames after showing
them; or replace the four with KART-drawn dialogs registered as dialogs. All four now go through a
single `RegisterStaticPopup`, so there is one place to do it.

**Pre-existing.**

---

## B9 — `skipStyleRefresh` silently suppresses `onChanged`

**Symptom:** none today.

**Cause:** the flag's original job was to suppress the widget factory's own hardcoded
`UpdateStyles()` call. That call no longer exists — a caller wanting no restyle simply omits
`onChanged`. The flag now suppresses the caller's own callback instead.

**Consequence if it bites:** adding an `onChanged` to `KART_PullTimerSlider`,
`KART_BuffCheckCombatDelaySlider`, `KART_AlMinKeySlider` or `KART_LCVoteTimerSlider` would silently
never fire, with no error. The factory's doc comment warns about it.

**Introduced by the v3.0.0 refactor.** Not pre-existing.

---

## B10 — One extra version-check line from a passive announcement

**Symptom:** a passive handshake announcement landing inside the ~5-second `/kart version` window
prints a result line where it previously printed none.

**Cause:** the old `ANNOUNCE_VERSION` handler suppressed that print unconditionally via an
`isAnnounce` flag; the new handshake has only the `VersionCheckActive` gate. The printed line is
accurate, so the impact is cosmetic.

**Introduced by the v3.0.0 refactor**, and sanctioned during it. Verify in the first raid test
before deciding whether it is worth changing.

---

---

## B11 — A raider with their own name in the Lootmaster field never sees a vote window

**Symptom:** one specific raider silently receives no vote popup all evening. Invisible from the
lootmaster's side — their council row just never fills in.

**Cause:** `LC.IsConfigOwner` (`LootCouncil.lua:421`) reads *that client's own*
`KART_Settings.lcLootmaster`. If it names themselves, `GetLootmaster()` returns their own key, so
`LC.IsSenderLootOwner` compares the real lootmaster's key against their own and rejects every
`LC_START`, `LC_MANUAL_START` and `LC_ACTIVE`.

Anyone who once tried the addon solo is a candidate, because entering yourself is the natural thing
to do when testing alone.

**Fix direction:** the lootmaster identity that governs *incoming* authority should come from the
raid config the lootmaster broadcasts, not from the receiver's own settings. Distinguish "who I
think the lootmaster is" from "who this raid's lootmaster is".

**Pre-existing.** Found by the loot-flow audit, 2026-07-27.

---

## B12 — A client that cannot yet resolve the lootmaster drops the raid config, permanently

**Properly fixed on `fix/config-acceptance`. The 3.0.1 retry treated a symptom and missed the
disease.**

The retry assumed the failure was *timing* — that NSRT would eventually deliver the nickname. For a
client with Northern Sky's **"Global Nicknames" toggle off** (or without NSRT at all) the nickname
never arrives, because `NSAPI:GetName` echoes the real name and `KASC.Identity.GetNickname` correctly
reduces that to `nil`. Twelve attempts changed nothing, and the client then used its own settings for
the rest of the raid. Confirmed 2026-07-27 with the affected raider.

`TryAcceptConfig` now decides on the **sender's identity**, which always resolves, instead of on the
declared name. Only a client whose own settings name it lootmaster broadcasts at all, so the sender's
identity already carries what the name was consulted for. The name is still checked when it *does*
resolve and still rejects a payload naming somebody else — the guard survives, the dead end does not.
Two further consequences: the retry machinery was repointed at `no-sender`, the one genuinely
transient reason left, and a rejection now prints its reason instead of failing silently.

The rest of this entry documents the original, narrower diagnosis. Kept because the timing case is
real and the retry still covers it.

**Symptom (until the retry succeeds):** the council is not yet extended with the configured members,
and raiders keep their own local button labels instead of the raid's.

**Cause:** `LC.HandleConfig` accepts a config only when the payload's lootmaster field resolves,
**on the receiver**, to the sender's key. When the field holds an NSRT nickname, the receiver needs
NSRT to already know that nickname for that character.

**NSRT distributes nicknames between clients over time.** Start a session immediately after the raid
forms and the peers have not received the lootmaster's nickname yet, so `NSAPI:GetName` gives them
nothing and the first resolution attempt(s) fail. The lootmaster's own client resolves its own
nickname fine, so the broadcast does go out — the failure is entirely on the receiving side.

(An earlier diagnosis blamed a cold `KART_PlayerCache`. That was wrong: `ResolvePlayer` scans the
live roster first and calls `GetNickname` itself, reaching the cache only after that scan fails.)

**Two paths back to a good config:** it *is* re-broadcast — on every roster change while the session
is active (`LootCouncil.lua:1089`) and in reply to `LC_STATE_REQ` — and, since 3.0.1, a rejected
payload also retries itself on a local timer. A roster change during an active session re-broadcasts
the config too, and a fresh "lootmaster-unresolved" rejection replaces the pending payload and resets
its attempt count back to 0, so the two mechanisms reinforce each other in practice.

**Large mitigation:** if the lootmaster is also the raid leader, `IsSenderLootOwner` and
`IsSenderCouncil` fall back to `UnitIsGroupLeader` and this failure class cannot occur — this also
sidesteps the `LC_ACTIVE` gap below entirely.

**Workaround, removes the dependency entirely:** put the lootmaster's **character name** in the
field rather than the NSRT nickname. Nothing then depends on NSRT having synced, for the config or
for `LC_ACTIVE` below.

**Remaining gap 1 — the council panel lags a successful retry by one item.** Panel visibility is
decided once, at the moment a roll starts (`LC.IsCouncil()`, checked in `LC.HandleStart` and
friends). A council member who becomes eligible while the retry is still pending gets correct button
labels and minimum quality immediately, but the item already rolling when the retry succeeds still
only shows them the vote popup — the council panel appears starting with the *next* item.

**Remaining gap 2 — `LC_ACTIVE` is not retried at all, and this is the more serious one.** A peer in
the B12 window validates `LC_ACTIVE` through `LC.IsSenderLootOwner`, which falls back to
`UnitIsGroupLeader` while it doesn't yet know the lootmaster. If the lootmaster is **not** the raid
leader, that fallback rejects the sender, so a peer can end up with a correctly retried config while
`LC.sessionActive` stays false. `LC.OnStartLootRoll` then returns early for them, so **their
auto-pass never fires** — an item they should have silently passed on instead pops Blizzard's own
Need/Greed roll window, which reads as a completely unrelated bug. `LC_ACTIVE` has no retry of its
own (it's a one-shot broadcast at session start and a one-shot `LC_STATE_REQ` reply), so nothing
currently re-delivers it once rejected. A `/reload` recovers, since it re-sends a fresh
`LC_STATE_REQ`, by which point NSRT has usually caught up. Keeping the lootmaster as raid leader
avoids this class entirely (see the large mitigation above).

**Pre-existing.** Diagnosis corrected 2026-07-27 after a live raid test. Config-retry landed in
3.0.1 the same day; the `LC_ACTIVE` gap above did not.

---

## B13 — Two byte-identical items awarded to one player within five seconds record one history entry

**Symptom:** the trade reminder correctly lists two items; the loot history shows one.

**Cause:** `LH.LogHistory`'s duplicate guard (`LootHistory.lua:818-824`) suppresses a second call
with the same item link, winner and reason inside five seconds. `DoAssignWinner` still creates the
second pending trade, so the two disagree.

Needs a genuine duplicate drop awarded twice to the same person back to back. Items differing in
bonus IDs or item level produce different strings and are not affected. The result is at least
consistent across all clients.

**Pre-existing.** Found by the loot-flow audit, 2026-07-27.

---

## B14 — An oversized LC_CONFIG can leave the whole raid on stale config

**Symptom:** nobody's configuration updates, indefinitely.

**Cause:** `BuildCouncilPayload` (`LootCouncil.lua:403`) trims only the council list to fit the
255-byte addon-message limit. If the fixed part alone — button labels up to 128 characters plus the
lootmaster field — already exceeds the budget, the remaining budget goes negative, the council list
becomes empty, and the still-oversized message is truncated by the transport. `HandleConfig`'s
anchored pattern then fails on every client.

**Early warning:** the `LC_CONFIG_TRUNCATED` line printed locally to the lootmaster.

**Fix direction:** treat the fixed part as part of the budget and refuse to send, loudly, rather than
sending something no client can parse.

**Pre-existing.** Found by the loot-flow audit, 2026-07-27.

---

## Operational note — the Loot Council session does not survive a /reload

Not a defect, but the single most likely way for loot distribution to silently stop working.

`LC.sessionActive` resets to false on load. With the session off, `LC.OnStartLootRoll` returns
immediately: the lootmaster does not auto-win Blizzard's roll, no `LC_START` is broadcast, and
nobody sees a vote window. The item goes to whoever wins Blizzard's roll.

The session prompt does return by itself, but only on the next `GROUP_ROSTER_UPDATE` and with a
three-second delay, which is easy to miss mid-pull.

**Recovery:** Loot Council settings tab, "Toggle Session".

**Worth considering:** persisting the session state across a reload the way the combat-log ownership
flag already is.

---

## Stale comment — `LC.assignedWinners`

`LootCouncil.lua:1206-1207` documents the table as mapping rollID to a short name. It holds a
resolved GUID. Every reader compares GUIDs, so only the comment is wrong.

---

## B15 — Auto-Promote's realm-qualified match can never fire for some cross-realm players

**Symptom:** a specific raider is never promoted to assistant. No error, nothing happens.

**Cause:** `GroupLogic.lua:86-91` builds its comparison key as `name .. "-" .. realm`, using the realm
exactly as `UnitName` returns it. For a cross-realm unit that can be the *display* spelling with a
space — "Tarren Mill". A promote-list entry pasted from the WoWUtils export carries the normalized
form, "TarrenMill", so the two never match.

This codebase already solves the same problem elsewhere: `KAUtil.IsFullNameInGroup` canonicalizes
both sides, stripping spaces and hyphens, precisely because the two spellings differ. Auto-Promote's
realm-qualified branch does not.

The short-name branch still covers the common case, so this only bites on a deliberately
realm-qualified entry.

**Workaround:** enter that person by short name instead.

**Fix direction:** canonicalize the realm on both sides, the way `IsFullNameInGroup` does. Note its
`CanonRealm` is currently a file-local in KAUtil and would need exporting.

**Pre-existing.** Found by the raid-lead audit, 2026-07-27.

---

## B16 — The four data responders have no answer cooldown, and Refresh is not debounced

**Symptom:** after mashing the Buff Checker's Refresh button in a full raid, some rows keep showing
`?` and grey oil for the rest of the session.

**Cause:** `BuffChecker.lua:371-377` fires `REQ_OIL`, `REQ_ILVL` and `REQ_GEAR` back to back, and
every KART client in the raid answers immediately. None of the four responders in
`Libs/KASC-1.0/KASC-1.0.lua` carries an answer cooldown, and the Refresh button itself is not
debounced. One click in a 20-man raid is 60 outbound answers; several clicks overrun Blizzard's chat
rate limiter, which silently drops the overflow. **Nothing retries.**

The addon already knows this pattern is dangerous — the structurally identical `REQ_EQUIP` responder
carries `EQUIP_ANSWER_COOLDOWN = 5` for exactly this reason. These four never got one.

**Workaround:** click Refresh once and wait, rather than clicking again when data does not appear
immediately.

**Fix direction:** the per-request cooldown `REQ_EQUIP` already uses, plus debouncing the button.

**Pre-existing.** Found by the Buff Checker audit, 2026-07-27.

---

## B17 — Peer gear data never expires and staleness is invisible

**Symptom:** the advanced page shows hour-old data for a peer, rendered identically to fresh data.

**Cause:** `RequestAdvancedData` is a local closure inside the frame builder, reachable only from the
mode button and the Refresh button. Neither `KART.ShowBuffCheck` nor the automatic open on
`READY_CHECK` requests anything, and `GROUP_ROSTER_UPDATE` only refreshes the display. The caches
carry no timestamp and are never purged on a roster change. `KART.BuffCheckMode` is not reset on
close, so reopening straight into a stale advanced page is the normal case.

Someone who re-oiled, re-gemmed or swapped weapons since the last Refresh still shows their old
state. Someone who joined since then shows `?`, which is at least honest.

Arguably deliberate — a comment says the one-shot fetch avoids constant spam — but the staleness is
not signalled to the user in any way.

**Pre-existing.** Found by the Buff Checker audit, 2026-07-27.

---

## Smaller items from the 2026-07-27 audits

All pre-existing, all low impact, recorded so they are not rediscovered.

**Sequential short-name reuse poisons the peer caches.** All six are short-name keyed and never
cleared on a roster change. If `Bob-Silvermoon` leaves and `Bob-Ravencrest` joins mid-session, the
new Bob inherits the old Bob's oil, gear, item level and durability until the next Refresh. This is
*not* the accepted simultaneous-namesake decision in `REVIEW-DECISIONS.md`, which concerns two
namesakes present at once.

**`ILVL` is validated by `tonumber` and nothing else** (`BuffChecker.lua:1078`). A peer fully
controls their own displayed item level: `ILVL:0x1F` caches 31, `ILVL:1e400` renders the literal
string `inf`, `ILVL:-99` renders `-99.0`. The other three receivers do validate.

**An empty `ENCH:` payload caches an empty table**, so `/kart ench raid` counts that player as a
responder with zero enchants. Maintenance path only; nothing renders it.

**`GetAverageItemLevel`'s second return is unguarded on the render side** (`BuffChecker.lua:993`)
while the responder that sends the same value does guard it. A nil during a loading screen would
throw inside `UpdateBuffCheck` and abort the row rebuild half-drawn.

**Your own ready-check decline reason never reaches your own row.** `sendReason` broadcasts
`RC_REASON` but never writes the local cache, and RAID/PARTY messages do not echo to their sender.
Everyone else sees your reason; you do not.

**The `GEAR` payload match is unanchored**, so trailing junk after the two slot lists is accepted.
Harmless — both captured fields still pass through `IsSlotList` — but it is the one receiver whose
pattern does not pin the whole payload.

**The same realm-spelling inconsistency as B15 exists in `WU.InviteBoss` and `WU.RemoveForBoss`**,
but is masked because both also check a plain short-name key. Only relevant if the project's
no-namesake convention ever changes.

**`KART.keybindsPending` is set and cleared but never read** (`RaidleadBar.lua:176-179`). Harmless
dead state — `PLAYER_REGEN_ENABLED` re-applies keybinds unconditionally anyway.

**`KAUI.ShowInputDialog` falls back to Blizzard's client-locale `ACCEPT`/`CANCEL`** when a caller
omits the label options, which would show the client's language rather than the user's chosen one.
All three current call sites pass them explicitly; the trap is for a future consumer.

---

## B18 — Cramped and overlapping layout at 1080p

**Symptom:** a raider playing at 1920x1080 reports the interface is very tight and elements
partially overlap. The maintainer plays at 2560x1440 and sees none of it.

**Not yet diagnosed.** The addon's main window is a fixed 929x715 frame built around a baked PNG
whose geometry is derived from measured pixel positions of the artwork (see the comment above the
main frame in `MainFrame.lua`), and the window is deliberately not freely resizable because the
artwork would distort. Users scale it through the Window Scale slider instead. Popup windows size
themselves independently.

**Mechanism, established 2026-07-27** from the raider's Graphics and KART settings:

They run with **"Use UI Scale" switched off**, which makes one UI unit equal one physical pixel and
therefore makes `UIParent` exactly as many units tall as the screen has pixels — 1080 for them, 1440
for the maintainer. With identical settings their whole interface is **1.33x larger relative to the
screen**. The main window is a fixed 929x715 units (`MainFrame.lua:62`), so:

| | UIParent height in units | window occupies |
|---|---|---|
| maintainer, 1440p | 1440 | 50% |
| raider, 1080p | 1080 | 66% |

They are already at their floor: with UI scale off WoW is showing the smallest interface it can, and
enabling it only makes things larger. Nothing on the WoW side is left to turn.

**Ruled out: a popup sized from the screen dimensions.** No window derives its size from the screen.
The only place `UIParent`'s dimensions are read is `KAUI.IsSavedPosOnScreen`
(`Libs/KAUI-1.0/KAUI-1.0.lua:145`), which validates a stored position rather than sizing anything.

**Immediate workaround:** Window Scale 75 on the affected client. 1080/1440 = 0.75, which reproduces
the maintainer's proportions exactly.

**The real gap that leaves.** `KART_Settings.uiScale` is applied to `KART.MainFrame` alone
(`Core.lua:505`). The Loot Council vote window and council panel — the two a raider actually looks at
during a raid — are not covered by it, so a 1080p raider has no scale lever for them at all, only the
font-size settings. A per-window scale, or extending the existing slider to the Loot Council frames,
is the fix worth designing.

**Ruled out: font settings overflowing fixed-width columns.** The affected raider runs every font
size at its default (`titleFontSize` 12, `menuFontSize` 11, `contentFontSize` 12, `lcFontSize` 12).

**No layout defect is involved.** With defaults everywhere and nothing sized from the screen, that
client's geometry is identical to the maintainer's, pixel for pixel — only the canvas underneath is a
third smaller. What reads as "overlapping" is KART windows intersecting each other and the rest of
the interface because less room is left beside them, not text drawn over text. The vote window
supplied as evidence bears that out: no overlap in it, buttons wrapping correctly, and it is not even
a fixed size — it starts at 380x200 and grows with its content.

So B18 reduces entirely to the missing scale lever above. Building that closes it; nothing else needs
finding. A screenshot would still be worth having if overlap ever shows up *inside* one window rather
than between two.

Reported 2026-07-27, fully explained the same day.

---

## B19 — The peer status marker is a one-shot snapshot and never refreshes

**Symptom:** two 3.0.1 clients in the same group, Loot Council demonstrably working in both
directions, each showing a red `!` on the other's council row — with *different* reasons. One saw
"Loot Council disabled on their end", the other "No KART detected" for a player who was plainly
running it.

**Cause.** `LootCouncilPanel.lua` renders the marker purely from `KART.PlayerVersions[short]` and
`KART.PlayerLCEnabled[short]`, and both tables are only ever written by the `KA_HELLO` callback in
`Core.lua`. A HELLO goes out in exactly three situations:

- `PLAYER_ENTERING_WORLD` on login/reload, five seconds later, GUILD only
- the first `GROUP_ROSTER_UPDATE` while in a group, latched by `KART.VersionAnnouncedToGroup`
- as a reply to someone else's `KA_HELLO_REQ` (`/kart v`)

So `caps.LC` is a snapshot taken at announce time. It comes from
`KART_Settings.lcModuleEnabled ~= false`, and **the default for that setting is `false`**
(`Utils.lua`). Nothing re-announces when the toggle changes — grep for `AnnounceHello` finds only
the two call sites above. A peer who enables the module after their HELLO went out is recorded as
`false` on every other client until someone runs `/kart v` or reloads.

The missing-KART direction belongs to the same family. The group announce is one-shot per join and
`AnnounceHello()` picks `DefaultChannel()`, which is `PARTY` until the group is a raid. A client
that misses that single packet, or joins around a party-to-raid conversion, is never told again.

**Confirmed 2026-07-27:** toggling the module and then running `/kart v` cleared the marker on both
clients at once. That rules out the parser and pins the announce path.

**Fix direction** (three parts, all in `KASC-1.0`/`Core.lua`):
1. Remember the last serialized HELLO string; re-announce when `SerializeHello()` differs. Hook it
   to the module toggle so a capability change propagates immediately.
2. Replace the `VersionAnnouncedToGroup` boolean with the channel last announced to, so a
   party-to-raid conversion re-announces and re-requests.
3. Throttle both, leading-edge, like `KART.HandleAutoPromoteThrottled` — `GROUP_ROSTER_UPDATE`
   fires in bursts during raid formation.

**Workaround until then:** `/kart v` in the raid clears a stale marker for everyone.

Reported 2026-07-27, cause confirmed the same day. Pre-existing — the one-shot announce predates
the library extraction; only the capability field is new in 3.0.

---

## B20 — A non-lootmaster's raid-wide fields show their own config, not the one in force

**Symptom:** a raider receiving the lootmaster's config correctly — loot distribution working, vote
buttons correct — sees the "Additional council members" and "Lootmaster" boxes empty, while the
line directly beneath them reads "5 name(s) not resolved yet".

**Cause.** Two adjacent widgets read from two different sources:

- the edit boxes are bound to `KART_Settings.lcCouncilMembers` / `.lcLootmaster` (`Core.lua:76-77`)
  — the viewer's **own** saved config
- the pending counter walks `LC.CouncilNamesTable` (`LootCouncilSettings.lua:277`) — the
  **effective** table, which on a peer holds the received raid config

An accepted `LC_CONFIG` lands in `LC.raidConfig` and `LC.CouncilNamesTable`, never in
`KART_Settings`. That part is deliberate: a peer's own setup must survive intact for when they are
the lootmaster themselves. The consequence is that a peer can never see what is actually in force,
and the counter contradicts the empty box next to it.

Not a data defect — the config arrives and applies. Display only.

**Chosen direction** (decided 2026-07-27): while a raid config is in force and the viewer is not the
config owner, the boxes show the **effective** values read-only. Own values stay stored untouched
and reappear once no raid config applies. Requires care in two places: the settings-push in
`Core.lua` must not write the displayed raid values back into `KART_Settings`, and the boxes must
re-render when a config arrives, not only on show.

Reported 2026-07-27.

---

## B21 — The extended ready check never offers the reason dialog to the other player

**Symptom:** a raider who declines a ready check is never given the KART reason dialog — neither the
three preset buttons nor the free-text box. The receiving side is therefore never exercised either.

**Where it is not.** The dialog itself (`KART.ShowReadyCheckReasonDialog`, `Core.lua:546`) has no
settings gate at all — nothing in `KART_Settings` can switch the feature off, so a disabled module
is ruled out. `RC_REASON` sends and receives normally (`Core.lua:428`, `Core.lua:575`).

Everything therefore hangs on the single trigger, `Core.lua:249`:

```lua
hooksecurefunc("ConfirmReadyCheck", function(isReady) ... end)
```

**Ruled out 2026-07-27**, by testing:
- *A replacement ready-check UI on the raider's client.* Everyone involved uses the stock Blizzard
  popup, and it fails for the maintainer's own client too.
- *The dialog opening behind another window* (the B8 shape). Checked, not it.
- *The hook failing to install.* `hooksecurefunc` on a nil global raises, which would abort the rest
  of the `ADDON_LOADED` branch — including the version text two lines below at `Core.lua:260`. That
  text renders correctly, so the global exists and the hook is attached.

**Cause, confirmed in-game 2026-07-27.** The hook sits on a function Blizzard's ready-check frame no
longer calls. Declining a check on a client whose `ConfirmReadyCheck` global demonstrably exists,
and which therefore demonstrably has the hook attached, produced no hook call at all.

Which function the frame uses instead never needs answering, because the trigger should not depend
on it.

**Fix.** `READY_CHECK_CONFIRM` carries `(unit, isReady)`, is already registered (`Core.lua:18`) and
already handled (`Core.lua:335`, currently only refreshing the Buff Checker). Gated on
`UnitIsUnit(unit, "player")` it is the whole trigger: a false `isReady` opens the dialog, a true one
hides it, which is exactly what the hook's `else` branch did. The `hooksecurefunc` block at
`Core.lua:249` then goes away entirely.

Three observations from the probe that the implementation has to respect:

- **`unit` is a unit token, not a name** — seen as `player`, `raid1`, `party1`, `raid2`. Compare with
  `UnitIsUnit`, never against `UnitName`.
- **The event fires twice per confirmation**, once under the generic token and once under the group
  token: `player` then `raid1` for the viewer's own decline, `party1` then `raid2` for a peer's. Only
  one `READY_CHECK` preceded each pair, so that is one answer reported twice, not two checks.
  Unguarded, the dialog is rebuilt and its auto-hide generation bumped twice.
- **A ready check's initiator never gets a popup** — they count as ready automatically, so there is
  no `READY_CHECK_CONFIRM` for them and nothing to decline. Not a defect, but it means whoever always
  starts the check never sees the reason dialog, and it invalidates any solo test.

The probe that established all of the above, run in a group of two before declining a check
(255-character chat limit — this is two lines, not one):

```
/run KP=CreateFrame("Frame") KP:SetScript("OnEvent",function(_,e,a,b) print(e,tostring(a),tostring(b)) end) KP:RegisterEvent("READY_CHECK_CONFIRM")
/run hooksecurefunc("ConfirmReadyCheck",function(r) print("HOOK",tostring(r)) end)
```

Observed: `READY_CHECK_CONFIRM player false` printed on the declining client, `HOOK` never did.

**Alternative considered and rejected: KART running its own ready check.** The reason dialog is
already KART's own frame — only the "somebody declined" signal comes from Blizzard, and the event
supplies it. Replacing the check itself would cost the `GetReadyCheckStatus` integration the Buff
Checker's Rdy column depends on (`BuffChecker.lua:815`), would miss every check started through
`/readycheck`, a raid frame or another addon, and would only reach raiders running KART. Worth
revisiting only if the reason buttons should live *inside* the ready-check popup, saving a click —
that is the one thing Blizzard's window cannot do.

Reported 2026-07-27, cause confirmed the same day. Pre-existing — untouched by the library
extraction.

---

## B22 — The Loot Council windows need their own scale and their own strata

**Decided 2026-07-27, partly implemented.** `KART_Settings.uiScale` is applied to `KART.MainFrame`
alone (`Core.lua:505`) and `frameStrata` is one value for the whole KAUI namespace
(`Libs/KAUI-1.0/KAUI-1.0.lua:117-131`). The vote window and the council panel — the two a raider
actually looks at mid-pull — therefore have no scale lever at all, which is what makes B18 bite at
1080p, and they cannot be lifted above a boss mod independently either.

**Read B24 before building the strata half.** The request for it came from issue #4, whose actual
cause is that no KART window is ever raised on click. A separate Loot Council stratum would only
separate Loot Council windows from the *main* window; two Loot Council windows overlapping each other
— the likely case in that report — would be unchanged, because both move together. The scale half
stands on its own regardless.

**Scope, as chosen:** every window the Loot Council itself opens — vote list, council panel, trade
reminders and their confirm dialogs. **Not** the loot history, which is read outside a raid where no
space pressure exists. The scale slider is **absolute**, 100 meaning unscaled, exactly like the main
window's — not a multiplier on top of it, so the number shown is the size.

**Implementation, written but not committed** (stashed as *"wip: independent Loot Council scale +
strata (B22)"*):

- `LC.windowFrames` / `LC.windowDialogs` registries plus `LC.RegisterWindow(frame, isDialog)`, a
  drop-in replacement for `KART.UI:RegisterStrataFrame` at the five Loot Council call sites
  (`LootCouncil.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua` twice, `LootCouncilPanel.lua`).
- `LC.ApplyWindowChrome`, applying to one frame at registration and to all of them from
  `KART.UpdateStyles`. Dialogs keep KAUI's rule of sitting one stratum above the windows.
- `lcScale` (default 100) and `lcFrameStrata` (default 4 = HIGH) in `KART.Defaults`.
- Two sliders in `prefsCard` (`LootCouncilSettings.lua`), the personal card — never the raid-wide
  box, since neither belongs in the broadcast config. Card height 260 -> 350.
- `settingsMap` entries so a profile switch carries them, and locale keys in both languages.

Owning this in the Loot Council layer rather than in KAUI is also what keeps it separable for a
future KALC split: the module takes its own window chrome with it.

**Still to do:** the five call-site swaps, the sliders, the locales, the `settingsMap` entries, and
the `KART.UpdateStyles` hook.

---

## B23 — Button borders render incomplete at 1080p (GitHub issue #5)

**A different symptom from B18**, reported by Syks via Discord and filed as
[issue #5](https://github.com/Kandera/KeineAhnungRaidTools/issues/5): the frames *around buttons*
come out incomplete. B18 is about everything being proportionally larger; this is about border
pixels going missing.

**The reporter states "WoW UI Scale ist 100%", which contradicts the Graphics screenshot supplied
for B18** — there the "Use UI Scale" checkbox is clearly unticked, with the slider greyed at 100%.
The two states predict opposite outcomes, so this has to be settled before anything is built:

- **Unticked:** WoW uses the pixel-perfect automatic scale. `UIParent`'s effective scale is 1.0, one
  UI unit is exactly one physical pixel, and a 1-unit border is exactly one pixel. Borders should be
  crisp — this setting cannot be the cause.
- **Ticked at 100%:** `UIParent` is 768 units tall against 1080 physical pixels, an effective scale
  of 1.40625. A 1-unit backdrop edge then lands on 1.40625 physical pixels and rounds inconsistently
  along its own length, which is exactly how borders come out broken.

**Why the maintainer would not see it either way:** at 1440p the same ticked setting gives
1440/768 = 1.875, which rounds a 1-unit edge up to a solid 2 pixels rather than down.

**The lead, if it is the second case.** Every backdrop in the addon uses `edgeSize = 1`
(`Libs/KAUI-1.0/KAUI-1.0.lua` five times, plus `Core.lua`, `Invite.lua`, `LootCouncilPanel.lua`),
and **`PixelUtil` is used nowhere** — no border is snapped to the physical pixel grid. WoW provides
`PixelUtil`/`GetPhysicalScreenSize` for precisely this problem.

**What to ask the reporter:** whether the "Use UI Scale" checkbox is ticked or not, and whether the
broken borders appear on the main window's buttons, the Loot Council windows, or both.

Reported 2026-07-27.

---

## B24 — Two overlapping KART windows can never be reordered (GitHub issue #4)

**Symptom:** where two KART windows overlap, the one on top is not the one that was clicked last,
and there is no way to bring the other forward.
[Issue #4](https://github.com/Kandera/KeineAhnungRaidTools/issues/4), reported by Wuusch via Discord.

**Cause, confirmed by absence.** `SetToplevel`, `Raise` and `SetFrameLevel` appear **nowhere in the
addon** — zero occurrences across every file. Every window is therefore left at whatever frame level
WoW assigned when it was created, and since they all share one stratum
(`KART.UI:RegisterStrataFrame`), their z-order is fixed by creation order for the whole session.
Clicking does nothing, because nothing listens.

**Fix:** `frame:SetToplevel(true)` on each top-level window. WoW then raises that frame above others
in its stratum when it is clicked, which is the behaviour every other movable window in the game
has. The frames are already mouse-enabled and draggable, so nothing else is needed. One line per
window, applied where each is created — the same set `KART.UI:RegisterStrataFrame` is already called
on, which makes the registration functions the natural place to do it once rather than by hand at
every site.

**Why the B22 strata setting does not cover this.** A per-module stratum only separates Loot Council
windows from the main window. Two Loot Council windows against each other — the vote window over the
council panel, most likely what the screenshot shows — sit on the same stratum either way and stay
frozen in creation order. Toplevel handling is the fix; a second stratum is at best a partial
workaround for one pairing.

Reported 2026-07-27, cause established the same day.

---

## B25 — A vote is a bare index, so divergent button lists mislabel it silently

**Severity: this one changes who gets loot.** Every other entry here is cosmetic or an annoyance.
Observed live 2026-07-27: five raiders shown as voting "Transmog" on one item, and at least one
raider certain they pressed something else.

**Cause.** `LC_VOTE` carries the button's *position* and nothing else
(`LootCouncilVote.lua:271`), and the council panel resolves that position against **the viewer's own**
list (`LootCouncilPanel.lua:997`, `buttons[tonumber(voteIdx)]` over `LC.GetButtonConfig()`). Nothing
ties the number to the label the voter actually read.

Clients diverge whenever the raid config has not arrived: `LC.GetButtonConfig` then falls back to the
client's own `lcButtonLabels` (`LootCouncil.lua:142`). With a six-button list against the five-button
default (`BIS;Upgrade;Offspec;Sonstiges;Pass`), every position from 4 up shifts by one — pressing
**Sonstiges** displays as **Transmog**. That matches the observation: five "Transmog" votes on an item
few would want for transmog, where "Sonstiges" is the plausible choice.

**The same root explains the missing rolls** reported alongside it. Without a received config,
`LC.GetRollsEnabled` falls back to the client's own `lcRollsEnabled` (`LootCouncil.lua:386`), whose
default is `false` — so those clients never roll at all. Some rows show a number, others a dash.

**Not introduced by the library extraction:** `git grep` confirms `LC_VOTE` already sent a bare index
in `v2.9.0:LootCouncilVote.lua:247`. The extraction only made the config-delivery gaps (B12, B19)
easier to hit, which is what exposes it.

**Fix directions, in order of value:**
1. **Make the mismatch visible instead of silent.** Send the voter's button count, or a short hash of
   their list, alongside the index; render a vote whose list does not match as explicitly unknown
   rather than as a confident wrong label. A loot council acting on a wrong label is worse than one
   acting on a visible gap.
2. **Close the delivery gaps** so divergence stops happening — B12's retry covers only an unresolved
   lootmaster, and B19's one-shot announce leaves clients stale.
3. Sending the label text instead of the index would be order-independent, but labels are
   user-editable free text and the payload shares a 255-byte budget — see B14 on truncation.

**Root cause confirmed 2026-07-27, and fixed on `fix/config-acceptance`.** The affected raider had
Northern Sky's **"Global Nicknames" master toggle switched off**. `NSAPI:GetName` then echoes the
character's real name back, `KASC.Identity.GetNickname` correctly turns that into `nil`
(`Libs/KASC-1.0/KASC-1.0.lua:103`), and the lootmaster's nickname therefore never resolved on that
client — not slowly, never. `TryAcceptConfig` rejected every broadcast for good, so the client fell
back to its own settings for all three synced values at once:

| symptom | because it used its own |
|---|---|
| votes shown under the wrong label | vote button list — the index shifts against the panel's list |
| no roll at all | `lcRollsEnabled`, whose default is `false` |
| never in council | council list, which is empty |

That also explains why the remedies failed: `/kart v` carries no config, and a session restart
re-broadcasts one that is rejected identically.

`TryAcceptConfig` now decides on the sender's identity, which always resolves — see the entry for
B12. The label-shift hazard itself remains: a vote is still a bare index, so any future divergence
would still mislabel silently rather than warn. Fix direction 1 above is still worth building.

One detail unexplained: a raider reported pressing "Offspec", position 3 in both lists, where the
shift alone predicts a match. Either a misremembering or a third list in play — not worth chasing
now that the cause of the divergence is gone.

Reported 2026-07-27 after a live raid, cause confirmed the same evening.

---

## B26 — The vote window's item tooltip only covers the upper half of the icon (issues #7, #8)

**Reported twice independently** — Wuusch and Shadowhuntr, the second explicitly on 1440p — which
makes it confirmed rather than suspected.

**Cause, arithmetic.** The hover frame spans from the icon's top-left to the **item name's**
bottom-right (`LootCouncilVote.lua:376-377`). The name is anchored 4px below the icon's top edge and
is roughly 17px tall for a single line at font size 14, so the hover region ends 21px down — against
an icon that is **46px** tall in the spacious layout (`LootCouncilVote.lua:293`).

21 of 46 is, precisely, the upper half.

The compact layout uses a 26px icon (`LootCouncilVote.lua:594`), where the same 21px covers 81% and
nobody notices. Both layouts build the hover identically (`:376` and `:648`).

A two-line item name pushes the region to ~38px and hides the bug, which is why it can look
intermittent.

**Fix:** anchor the hover's bottom to the icon's bottom rather than the text's. In the spacious
layout that covers everything, since 46px exceeds even a two-line name. In the compact layout a
two-line name would extend ~8px below a 26px icon and lose its tooltip there — worth accepting, or
worth sizing the frame to the taller of the two at refresh time.

Reported 2026-07-27.

---

## B27 — A council tab closes when you meant to switch to it (issue #9)

**Symptom:** "clicking an item can make them disappear" — härikini.

**Cause.** Each tab is a 40x40 button carrying a 14x14 close button in its top-right corner, hidden
until the tab is hovered (`LootCouncilPanel.lua:402-406`). `Council.CloseCouncilTab` then drops the
roll entirely: the tab, the vote-list row and the trade state.

The comment above `Council.RefreshCouncilTabs` says the hover-only reveal exists precisely because
an always-visible x "made it very easy to close a tab by accident". It does not achieve that. **You
have to hover a tab in order to click it**, so the x appears exactly when the pointer is already
there — hover-only prevents stray clicks from someone not interacting at all, which was never the
failure. A pointer arriving in the top-right corner still closes instead of switching.

**Fix directions:** anchor the x just outside the tab's own hit area so a tab click can never reach
it; or reveal it only after a deliberate hover delay; or require a modifier. The first is the only
one that makes the mistake structurally impossible.

Reported 2026-07-27.

---

## B28 — Slider values cannot be typed (issue #6)

**Request** from Syks: every numeric setting is a slider only, and the number beside it is not
editable. Typing an exact value would be easier than dragging for one.

Affects every `KART.UI:CreateSettingsSlider` — window scale, background opacity, font sizes, vote
timer, pull timer, and the strata slider, whose value renders as a name rather than a number and
would need its own handling or exclusion.

The factory lives in `KAUI-1.0`, so this is one change in the library rather than per call site. It
needs care in two places: the strata slider overwrites its own value text through a hook
(`MainFrame.lua`, `UpdateStrataSliderText`), and the scale slider defers applying while dragging
(`isDragging`, see `Core.lua:504`) — a typed value has no drag to end, so it must apply on its own.

Reported 2026-07-27.

---

## Library-boundary items, relevant only if the Loot Council half is ever split out

These do not affect the shipped addon at all. They are prerequisites for the split the libraries
were built to enable.

**Only `KAUI-1.0` survives a library MINOR upgrade.** It deliberately persists its `namespaces` and
`nsProto` tables on the library object and documents why. `KASC-1.0` keeps `prefix`, `handlers`,
`caches`, `addons`, `capabilities` and `peerCallbacks` as file-locals and registers its
`CHAT_MSG_ADDON` frame at file scope; `KAGS-1.0` caches `emptySocketTexts` in a file-local and
creates its scanning tooltip at file scope.

With two addons shipping different library MINORs in one session, the newer `KASC` would start with
empty registries while the older copy's event frame stayed alive and kept dispatching against the
old handler table, and `KAGS` would create a second frame under the same global name, orphaning the
first. Zero consequence while one addon ships.

**`KAGS-1.0` owns globals named after one consumer** — `KART_GearScanTooltip` and
`KART_GearScanTooltipTextLeft<i>`. This is load-bearing: WoW exposes tooltip FontStrings only
through `_G` lookup by name, so the frame must have a known global name. `tests/check-moved.sh`
carves it out of the library-boundary gate deliberately. Left alone on purpose; a rename would break
the lookup.

---

## Minor items from the v3.0.0 verification harness

**`MainFrame.lua:850` shadows the `L` upvalue** (the locale table). Pre-existing, single occurrence,
silenced by a file-scoped `.luacheckrc` entry rather than by editing the addon. Worth looking at
whenever `MainFrame.lua` is next edited.

**The moved-symbol gate's regex has no left word boundary.** It fails toward noise rather than
toward a missed hit, so it is safe as-is.

---

## Not a defect — recorded so it is not re-reported

**Pre-2.9.0 loot-history rows show duplicate awards and mixed-language difficulty names.** Both
causes were fixed long ago: dedup keys on `winnerKey` plus a locale-independent item string, and
`difficultyID` travels the wire instead of the localized name. Old rows lack `winnerKey` and
`difficultyID`, so they cannot be merged retroactively without guessing. They age out via
`MAX_HISTORY_ENTRIES = 500`.

The maintainer chose to delete the history instead. **Caveat if that is done again:**
`RequestHistorySync` sends the newest timestamp it holds, which is `0` after a wipe, so peers who
still hold the old rows replay all of them on the next raid join. Everyone has to clear, or clear
after the last shared raid.

---

## Observation — GUILD addon messages do reach their own sender

Observed 2026-07-27 on 3.0.0: `/kart v` while solo sends `KA_HELLO_REQ` on GUILD and the sending
client receives its own `KA_HELLO` back, printing itself in the version-check results.

This contradicts the common assumption — stated in `KART.StartEnchantScan`'s comment — that
`SendAddonMessage` never echoes to its sender. That comment concerns the RAID/PARTY channel, where
the assumption still appears to hold (the scan adds its own entry by hand and does not show a
duplicate). Both can be true at once: no echo in the group channel, echo in the guild channel.

Not a defect, and unchanged from 2.9 behaviour. Recorded because it invalidates a load-bearing
assumption about one channel, and because it means a solo `/kart v` is **not** evidence that two
separate clients interoperate — the round trip is entirely local.
