# Coding standards

Read during review (`lua-reviewer`) and when writing changelog, locales, Lua, or SavedVariables. `lua-reviewer` does not own changelog; the suite and this file do.

## Language

English by default:

- Commit messages (subject and body).
- Code comments in all `.lua` files.
- Pull request titles/descriptions, issue text, release notes.
- Primary documentation: `README.md` and `CHANGELOG.md`.

Exceptions (intentionally German):

- **`Locales/deDE.lua`:** localized string *values* stay German. Comments inside it stay English.
- **`README-de.md` / `CHANGELOG-de.md`:** German mirrors of the English primaries. Update the English file first, then the `-de` file in the same turn.

When updating player-facing changelog, three files, English first: `CHANGELOG.md`, then `CHANGELOG-de.md`, then `KART.InGameChangelog` in `Utils.lua`. Same turn.

## Changelog style

Each entry is **one line, at most two lines for big changes**. Bold lead + short effect clause — often the bold lead alone is the whole entry (e.g. "**Settings tab moved to the bottom of the sidebar.**"). Never include: technical causes, "was X, now Y" explanations, design rationale, implementation details, examples. The commit message and code carry those — the changelog is for players skimming what changed.

## Lua 5.1 / LuaJIT

WoW runs Lua 5.1 on LuaJIT. No `goto`, `unpack` not `table.unpack`, no integer division, `#` on a sparse table is undefined.

## SavedVariables

No central migration. Each structure guards its own shape — `Droptimizer.lua` checks a `schemaVersion`, `OfficerNotes.MigrateOfficerNoteKey` renames a key. A shape change without such a guard corrupts existing users on their next login. The authoritative list of variables is the `.toc`. A leftover key after a schema split stays; do not rename it for a clearer name.

`.toc` files run before `ADDON_LOADED` fills those globals. Main-chunk widget paint that indexes `KART_Settings` (or any SavedVariables name) uses the invite-chip Nil-Guard. Fixture: `tests/test_mainframe.lua` (`before ADDON_LOADED`).

## UI escapes

Peer or player text that lands in `SetText`, `AddMessage`, or `print` treats `|c` `|H` `|T` as colour, links, and textures. Escape `|` to `||` like `RC_REASON` in `Core.lua`.

## Patch-bound ID tables

Enchant, spell and item ID tables are per-patch maintenance, not defects. `GOOD_ENCHANTS` in `Utils.lua` is the documented case; see `REVIEW-DECISIONS.md`.
