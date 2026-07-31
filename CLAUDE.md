# Project Conventions

## Language: English by default

This project is maintained in **English**. Unless explicitly noted otherwise below, everything happens in English:

- **Commit messages** (subject and body).
- **Code comments** in all `.lua` files.
- **Pull request titles/descriptions, issue text, release notes.**
- **Primary documentation:** `README.md` and `CHANGELOG.md` are the English, primary versions.

### Explicit exceptions (intentionally German)

- **`Locales/deDE.lua`:** The actual localized string *values* stay German — that's the whole point of the file. Comments inside it should still be English.
- **`README-de.md` / `CHANGELOG-de.md`:** Maintained as German mirrors of the English primaries. Always update the English file first, then mirror the change into the `-de` file in the same turn.

When updating `CHANGELOG.md`/`README.md` for a user-facing change, update `CHANGELOG-de.md`/`README-de.md` alongside it — see the more detailed doc-update workflow in project memory (`feedback_changelog_readme`).

## Changelog style: one line per entry

Each changelog entry is **one line, at most two lines for big changes**. Bold lead + short effect clause — often the bold lead alone is the whole entry (e.g. "**Settings tab moved to the bottom of the sidebar.**"). Never include: technical causes, "was X, now Y" explanations, design rationale, implementation details, examples. The commit message and code carry those — the changelog is for players skimming what changed.

## The Manifest

`docs/MANIFEST.md` is the list of core functions and the standard they are held to: **ten attempts in
the game, ten successes.** Refer to it by that name -- "gegen das Manifest getestet", "das bricht C7"
-- and check a change against it before calling the change done. The automated suite is the floor,
not the standard: it cannot see a cursor, a Blizzard roll window or a real reload.

`docs/OWNERSHIP.md` is the settled rule for who owns the settings and who hands out the loot. A
change that touches ownership is a change to that document first.
