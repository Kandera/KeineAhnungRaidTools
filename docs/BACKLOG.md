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
broken borders appear on the main window's buttons, the Loot Council windows, or both. Since 3.1.0
there is a second question worth asking: whether setting the Loot Council scale to anything other
than 100 changes the borders, which would confirm the rounding explanation outright.

Reported 2026-07-27.
