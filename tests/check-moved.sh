#!/usr/bin/env bash
# Two gates, both of which must stay clean:
#   1. No symbol listed in moved-symbols.txt may still be referenced as KART.<name>.
#      luacheck cannot catch this: KART is a defined global and field access on a known
#      table is not validated, so a forgotten call site would pass every other check.
#   2. No file under Libs/ may reference KART. at all -- that is the library boundary.
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

echo "== Gate 2: KART. references inside Libs/ =="
if [ -d Libs ] && grep -rn 'KART\.' --include='*.lua' Libs/ ; then
  echo "FAIL: libraries must never reach back into the addon table." >&2
  fail=1
else
  echo "clean"
fi

exit $fail
