#!/usr/bin/env bash
# Three gates:
#   1. No symbol listed in moved-symbols.txt may still be referenced as KART.<name>.
#      luacheck cannot catch this: KART is a defined global and field access on a known
#      table is not validated, so a forgotten call site would pass every other check.
#   2. No file under Libs/ may reference KART.<anything>, nor any of the addon's SavedVariables
#      globals by name (KART_Settings and friends, from the .toc's SavedVariables lines) -- that
#      is the library boundary. The SavedVariables names don't contain the literal "KART."
#      substring, so a library function reading one straight out of the addon's own saved table
#      would otherwise slip past this gate even though it's the same class of coupling a shared
#      library must not have. Matched by exact name rather than a bare "KART_" prefix so this
#      doesn't also flag unrelated KART_-prefixed globals a library legitimately owns (e.g.
#      KAGS-1.0's own KART_GearScanTooltip frame).
#   3. (Informational, does not affect the exit code) List every `local <name> = KART.<x>`
#      alias declaration in the tree. The codebase aliases table members heavily (e.g.
#      `local Sync = KART.Sync`) and then calls through the alias, never re-spelling
#      `KART.`, which makes Gate 1 blind to those call sites. Coverage of aliasing today is
#      layered but accidental -- Gate 1 catches the alias *declaration* only because the
#      declaration itself contains the literal `KART.<symbol>`, and luacheck would catch an
#      orphaned alias variable as an undefined global after a move -- so this gate makes the
#      alias set explicit instead of relying on that, for whoever is moving a symbol to check
#      the listed files by hand.
# Run from the repository root.
set -uo pipefail

fail=0

symbols=$(grep -vE '^\s*(#|$)' tests/moved-symbols.txt | tr -d '\r' | paste -sd'|' -)
if [ -n "$symbols" ]; then
  echo "== Gate 1: leftover KART.<moved symbol> references =="
  if grep -rnE "KART\.($symbols)\b" --include='*.lua' . ; then
    echo "FAIL: the references above must be rewritten to their library." >&2
    fail=1
  else
    echo "clean"
  fi
else
  echo "== Gate 1: skipped, no symbols listed yet =="
fi

echo "== Gate 2: KART. references, and SavedVariables globals by name, inside Libs/ =="
savedvars='KART_Settings|KART_LootHistory|KART_LCOfficerNotes|KART_WoWUtilsCache|KART_Profiles|KART_PlayerCache|KART_LCTrades'
if [ -d Libs ] && grep -rnE "KART\.|\b($savedvars)\b" --include='*.lua' Libs/ ; then
  echo "FAIL: libraries must never reach back into the addon table or its SavedVariables." >&2
  fail=1
else
  echo "clean"
fi

echo "== Gate 3: KART.<x> alias declarations (informational, does not affect exit code) =="
if ! grep -rnE '^[[:space:]]*local[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*KART(\.[A-Za-z_][A-Za-z0-9_]*)+[[:space:]]*(--.*)?$' --include='*.lua' . ; then
  echo "none found"
fi

exit $fail
