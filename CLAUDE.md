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
