"""Systematic mutation run.

For each candidate line in a target file, apply one small mutation, run the suite, and record
whether it stayed GREEN. A green run means no assertion depends on that decision.

Only lines the coverage report marks as EXECUTED are mutated -- mutating a line the suite never
reaches proves nothing. Comments and strings are skipped.

Needs a fresh luacov.report.out in the repo root:

    KART_COVERAGE=1 luajit tests/run.lua
    MUT_OUT=survivors.json python tests/mutrun.py LootHistory.lua,Invite.lua

Never run the suite by hand while this is working -- it writes mutated addon source to disk and
takes it back, so a parallel run measures somebody else's code.
"""
import os, re, subprocess, sys, json

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

TARGETS = sys.argv[1].split(",")
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
SEEDS = os.environ.get("MUT_SEEDS", "1")


def executed_lines(target):
    """Line numbers luacov recorded as hit, 1-based."""
    text = open("luacov.report.out", encoding="utf-8", errors="replace").read().split("\n")
    start = None
    for i, l in enumerate(text):
        if l.strip() == target:
            start = i + 2
            break
    if start is None:
        return set()
    hit, n = set(), 0
    for l in text[start:]:
        if l.startswith("====="):
            break
        n += 1
        m = re.match(r"^\s*(\d+)\s", l)
        if m and int(m.group(1)) > 0:
            hit.add(n)
    return hit


# (pattern, replacement) applied to the first match on a line.
RULES = [
    (r">=", ">"),
    (r"<=", "<"),
    (r"(?<![<>=~])>(?!=)", ">="),
    (r"(?<![<>=~])<(?!=)", "<="),
    (r"\band\b", "or"),
]


def candidates(path, hit):
    raw = open(path, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(nl)
    out = []
    for idx, line in enumerate(lines):
        n = idx + 1
        if n not in hit:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        if '"' in line or "'" in line:      # keep string contents out of it
            continue
        for pat, rep in RULES:
            if re.search(pat, line):
                out.append((n, pat, rep))
                break
    return raw, nl, lines, out


results = []
for target in TARGETS:
    hit = executed_lines(target)
    raw, nl, original, cands = candidates(target, hit)
    print("%s: %d executed lines, %d mutable" % (target, len(hit), len(cands)), flush=True)
    for (n, pat, rep) in cands[:LIMIT]:
        lines = list(original)
        mutated = re.sub(pat, rep, lines[n - 1], count=1)
        if mutated == lines[n - 1]:
            continue
        lines[n - 1] = mutated
        # try/finally, not two statements in a row: a Ctrl-C or a killed terminal between the
        # mutating write and the restoring one leaves a flipped operator in the addon's own source,
        # where the next commit picks it up. The file is under the repo now, not in a temp directory.
        try:
            open(target, "wb").write(nl.join(lines).encode("utf-8"))
            env = dict(os.environ, KART_SOAK_SEEDS=SEEDS)
            try:
                rc = subprocess.run(["luajit", "tests/run.lua"], capture_output=True,
                                    env=env, timeout=300).returncode
            except subprocess.TimeoutExpired:
                rc = -1  # a hang counts as caught
        finally:
            open(target, "wb").write(raw.encode("utf-8"))   # always restore verbatim
        if rc == 0:
            results.append({"file": target, "line": n, "was": original[n - 1].strip(),
                            "now": mutated.strip()})
            print("  SURVIVED %s:%d  %s" % (target, n, mutated.strip()[:100]), flush=True)

json.dump(results, open(os.environ.get("MUT_OUT", "mutants.json"), "w"), indent=1)
print("\n%d survivors" % len(results))
