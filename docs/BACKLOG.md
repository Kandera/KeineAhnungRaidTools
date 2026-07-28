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
B28 — was fixed for the 3.1.0 release and removed. That is the whole file bar B23; each fix names
its number in the commit subject or body.

---

## B23 — Button borders render incomplete at 1080p (GitHub issue #5)

**A different symptom from B18**, reported by Syks via Discord and filed as
[issue #5](https://github.com/Kandera/KeineAhnungRaidTools/issues/5): the frames *around buttons*
come out incomplete. B18 was about everything being proportionally larger; this is about border
pixels going missing.

**2026-07-28 — measured, and fixed.** The reporter's client returned:

    UIParent:GetEffectiveScale()  0.53333336
    UIParent:GetWidth/GetHeight   2560 x 1440
    GetPhysicalScreenSize()       1920 x 1080

0.53333 is 768/1440: the interface is scaled for a 1440-line screen while WoW renders 1080 lines,
so one UI unit is 1080/1440 = **0.75 physical pixels** and a 1-unit border cannot be drawn whole.
WoW puts down 1 pixel along part of the edge and 0 along the rest, which is the reported symptom
exactly; it also explains why the gap moves to a different side when the window is rescaled. With
the "Use UI Scale" checkbox unticked WoW would have chosen 768/1080 itself, so something else on
that client — a UI pack, most likely — sets UIParent's scale. Strictly this affects every hairline
in that interface, not only ours.

Fixed by deriving `edgeSize` from each frame's effective scale via `PixelUtil.GetNearestPixelSize`
(`KAUI:SetPixelBackdrop`, applied at all 25 backdrop sites), with `KAUI:RefreshPixelBorders`
re-deriving after anything that changes a scale. On a client whose scale matches its resolution
that call returns exactly 1 and nothing renders differently — verified in `tests/test_kaui.lua`.

**Not fixed, and worth knowing before this is re-opened:** only the border *width* is snapped, not
child *positions*. At 0.75 pixels per unit an integer offset still lands between pixels, so an edge
can read as soft rather than crisp. If the reporter still sees something after this, that is the
next place to look — and the honest answer there may be that his UI scale wants correcting rather
than our anchors.

Reported 2026-07-27. Awaiting confirmation in-game.
