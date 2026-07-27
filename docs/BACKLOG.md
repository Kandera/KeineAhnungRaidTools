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
