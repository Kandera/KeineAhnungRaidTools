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

`docs/MANIFEST.md` is the 10/10 in-game bar: the companion must not hinder, abort, or break
RCLootCouncil's loot flow. Refer to it by that name -- "gegen das Manifest getestet" -- and
check a change against it before calling the change done. The automated suite is the floor,
not the standard: it cannot see a cursor, a Blizzard roll window or a real reload.

`docs/OWNERSHIP.md` is the settled rule for who owns the settings and who hands out the loot. A
change that touches ownership is a change to that document first.

## Before proposing a change

`docs/REVIEW-DECISIONS.md` records findings we deliberately did not change, and the
`docs/BACKLOG.md` headings carry their own verdict (`FIXED` / `NO DEFECT`). Check both before
raising a concern. Re-opening a settled decision costs a round of explanation that these
documents exist to prevent.

## Lua and WoW

- **Never read a large file whole.** `grep -n '^-- =====' -A1 <file>` prints its section banners
  with current line numbers; read only the range you need. `LootCouncil.lua` (~6.8k lines) has 27
  and is always worth grepping first; the other files carry the same banner style but fewer of
  them. A new section of a few hundred lines gets a banner in that style.
- **API facts come from the ketho.wow-api annotations** (12.0.1, client 12.1). The addon targets
  Midnight (12.x). Never assert API behaviour from memory.
- **A local mirror of Blizzard's FrameXML source sits at `E:\Projects\.refs\wow-ui-source`**
  (one level above this repo, sibling of `KeineAhnungRaidTools`). Not wired into any tool
  config — nothing loads it automatically. Pull it in as a secondary source when tracing FrameXML
  behaviour or patch diffs, alongside the ketho annotations and the `gh api repos/Gethe/wow-ui-source`
  fetches in `docs/BACKLOG-12.1.md` — don't rely on it alone, it may lag the target patch.
- **WoW runs Lua 5.1 on LuaJIT.** No `goto`, `unpack` not `table.unpack`, no integer division.
- **The comm layer is `Libs/KASC-1.0` (`KASC:Send`)**, over AceComm-3.0 since 2026-08-03. There
  is no `KARTSync.lua`.
- **SavedVariables have no central migration.** Each structure guards its own shape --
  `Droptimizer.lua` checks a `schemaVersion`, `OfficerNotes.MigrateOfficerNoteKey` renames a key.
  A shape change without such a guard corrupts existing users on their next login. The
  authoritative list of variables is the `.toc`.
- **Enchant, spell and item ID tables are per-patch maintenance, not defects.** `GOOD_ENCHANTS`
  in `Utils.lua` is the documented case, see `REVIEW-DECISIONS.md`.
