#!/usr/bin/env bash
# Locale gate. Two questions, only one of which can be answered without false positives.
#
# 1. Do enUS and deDE define the same key set?          -> hard failure
#    A key present in one file and missing in the other shows an empty string to every
#    player on that language. Nothing dynamic can hide this, so it gates the build.
#
# 2. Is a key used in code but defined nowhere?          -> hard failure
#    `L.FOO` resolves to nil and the label is blank, or a concatenation errors out.
#
# Deliberately NOT checked: defined-but-unused. Buff entries carry their key as a table
# field (`labelKey = "BC_LABEL_FLASK"` in BuffChecker.lua) and resolve it at runtime, so a
# static sweep reports 33 live keys as dead. Reported as a note, never as a failure.

set -uo pipefail
cd "$(dirname "$0")/.."

EN=Locales/enUS.lua
DE=Locales/deDE.lua
fail=0

# sed, not tr: tr works on the whole stream and would eat the newlines along with the
# whitespace, collapsing every key into a single line.
keys_of() {
    grep -oE '^[[:space:]]+[A-Z][A-Z0-9_]+[[:space:]]*=' "$1" \
        | sed 's/[^A-Z0-9_]//g' | sort -u
}

keys_of "$EN" > /tmp/kart_en.txt
keys_of "$DE" > /tmp/kart_de.txt

echo "enUS: $(wc -l < /tmp/kart_en.txt) keys, deDE: $(wc -l < /tmp/kart_de.txt) keys"

only_en=$(comm -23 /tmp/kart_en.txt /tmp/kart_de.txt)
only_de=$(comm -13 /tmp/kart_en.txt /tmp/kart_de.txt)

if [ -n "$only_en" ]; then
    echo "FAIL: defined in enUS.lua but missing from deDE.lua:"
    echo "$only_en" | sed 's/^/  /'
    fail=1
fi
if [ -n "$only_de" ]; then
    echo "FAIL: defined in deDE.lua but missing from enUS.lua:"
    echo "$only_de" | sed 's/^/  /'
    fail=1
fi

# Keys referenced from addon code. Locales/ defines them, Libs/ is vendored, tests/ builds
# its own fixtures -- none of the three are call sites.
grep -rhoE '\bL\.[A-Z][A-Z0-9_]+\b|\bL\["[A-Z][A-Z0-9_]+"\]' \
        --include='*.lua' --exclude-dir=Libs --exclude-dir=Locales --exclude-dir=tests . \
    | sed -E 's/^L\.//; s/^L\["//; s/"\]$//' \
    | sort -u > /tmp/kart_used.txt

undefined=$(comm -23 /tmp/kart_used.txt /tmp/kart_en.txt)
if [ -n "$undefined" ]; then
    echo "FAIL: used in code but defined in no locale file:"
    echo "$undefined" | sed 's/^/  /'
    fail=1
fi

unused=$(comm -13 /tmp/kart_used.txt /tmp/kart_en.txt | wc -l)
echo "note: $unused defined keys have no literal call site (expected -- see labelKey indirection)"

if [ "$fail" -eq 0 ]; then
    echo "locale check: ok"
fi
exit "$fail"
