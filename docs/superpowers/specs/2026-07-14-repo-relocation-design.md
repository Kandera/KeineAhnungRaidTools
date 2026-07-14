# Repo Relocation: Move out of the WoW AddOns folder

## Problem

Both `KeineAhnungRaidTools` (the addon) and `KART-Companion` (the standalone
C# tray app) currently live directly inside
`E:\World of Warcraft\_retail_\Interface\AddOns\`. Neither belongs there as a
development workspace — `KART-Companion` in particular isn't even a WoW addon.

## Design

Move both repos to `E:\Projects\`:

- `E:\Projects\KeineAhnungRaidTools`
- `E:\Projects\KART-Companion`

Both moves are same-drive (`E:`), so they are plain renames/moves — `.git`
history, remotes, and working tree state are preserved untouched.

`KeineAhnungRaidTools` must still be loadable by the WoW client as an addon.
To achieve this without any copy step, a Windows directory junction is
created at the old location:

```
E:\World of Warcraft\_retail_\Interface\AddOns\KeineAhnungRaidTools
  -> (junction) -> E:\Projects\KeineAhnungRaidTools
```

Junctions (not symlinks) are used because they don't require administrator
privileges on Windows. The WoW client sees a normal-looking folder; every
saved change under `E:\Projects\KeineAhnungRaidTools` is immediately visible
in-game with no copy, no build step, and no git commit required.

`KART-Companion` does not get a junction. It was verified
(`SavedVariablesLocator.cs`) that the app takes the WoW installation root as
a runtime-configurable parameter rather than assuming it's co-located with
the WoW install, so it has no dependency on living inside the AddOns folder.

No hardcoded absolute paths referencing the old location were found in
either repo (checked for `_retail_`, `AddOns\...`, `E:\` — only incidental
"World of Warcraft" mentions in READMEs, which need no changes).

## Steps

1. Create `E:\Projects\`.
2. Move `AddOns\KeineAhnungRaidTools` -> `E:\Projects\KeineAhnungRaidTools`.
3. Move `AddOns\KART-Companion` -> `E:\Projects\KART-Companion`.
4. Create the junction: `AddOns\KeineAhnungRaidTools` -> `E:\Projects\KeineAhnungRaidTools`.
5. Verify: `git status` clean in both new locations, junction resolves
   correctly, WoW addon list still shows KeineAhnungRaidTools.

## Out of scope

- No copy-on-commit hook — the junction makes it unnecessary.
- No changes to CI/CD, `.pkgmeta`, or release packaging — those already
  operate on repo-relative paths and are unaffected by where the repo lives
  on disk.
