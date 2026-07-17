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

## Changelog style: keep entries compact

Each changelog entry is **one bold lead-in plus 1–2 sentences** describing the user-visible effect. Include a technical cause only when it's one short parenthetical that helps users understand the fix (e.g. "WoW can't load JPG textures"). Leave out: implementation details, design rationale ("both preferences are common…"), exhaustive examples/enumerations, and background history. The commit message and code carry those — the changelog is for players skimming what changed.
