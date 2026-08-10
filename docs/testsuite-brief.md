# Test suite review — handover brief

Written 2026-08-07 out of a tooling/workflow session. Purpose: hand the test-suite
project a starting position so the same ground is not covered twice.

Status: **not started.** Deferred deliberately — current suite runtime is tiring but
acceptable, and there are two to three days between fixes.

## Measured facts

```text
measured 2026-08-10

tests/                 1.6 MB, 69 .lua files      (1.4 MB / 65 three days earlier)
harness                wow_stubs.lua 80K + raidsim.lua 44K + lc_fixture.lua 24K
                       + run.lua 12K  =  160K, ~10% of the suite
largest tests          test_lc_churn 88K, test_loothistory_instance 80K,
                       test_lc_rolltable 76K, test_lc_baseflow 56K
runtime                fast gate ~80 s   |   plain run 21.0 s   |   coverage 15m02s
                       (coverage was 83m51s local / 106m45s CI before 28b0663)
```

From project memory (`kart-soak-harness-vs-addon`): in the last soak run **13 of 17
deviations were the test environment, not the addon.**

## The framing question

Not "which tests are slow" — that leads to trimming the wrong things.

**"Which tests exercise the harness instead of the addon?"**

The 13-of-17 number says the harness has become a source of findings in its own right.
A harness artifact costs the same time to triage as a real defect. Suite growth past
that point buys noise, not safety.

## The precedent this project should copy

Commit 28b0663 is the shape of the answer, and it was already found once. Coverage had
grown to 83m51s. Nothing was deleted. The cost was measured instead — luacov charges one
debug-hook call per executed line, so line events were the unit — and 63.5% of the entire
run traced to a single line advancing simulated time across a week while `PumpComms`
ticked every simulated client's `OnUpdate` on queues that were empty throughout. The
harness was pumping a despool frame that a real client hides when its rings run dry, so
it was *less* faithful than what it stood in for, not merely slower.

Result: 83m51s → 15m02s, coverage summary unchanged file for file, uncovered lines
identical line for line, 26 recorded mutations re-run with identical verdicts.

Read that as the method, not as a finished job: **measure where the time goes, then fix
the harness — do not start by removing tests.** The win came out of fidelity, and the
proof it changed nothing was the unchanged coverage report and the re-run mutations. Any
trimming this project proposes should be able to show the same kind of proof.

## Trim criterion candidate

The Manifest (`docs/MANIFEST.md`) is the standard: core functions C1–C12, ten attempts
in the game, ten successes. The suite is explicitly the floor, not the standard.

So the question per test is traceability, not coverage:

- does it defend a C-number, or
- does it pin a documented fix from `docs/BACKLOG.md`?

Neither → candidate for removal. Both → load-bearing regardless of size.

## Must not break

1. **The fast gate stays fast and independent.** `.github/workflows/check.yml` runs
   `check-moved.sh`, `luacheck .` and `luajit tests/run.lua` — about 80 seconds all together.
   Coverage was split into its own on-demand `coverage.yml` on 2026-08-10, after it had grown
   to **107 minutes** (luacov turns LuaJIT's compiler off, and the loot-history tests advance
   simulated time across the four-hour trade window second by second). Deliberately not on a
   schedule. Fixes ship during a raid night; a gate that answers in eighty seconds is the
   point. Do not fold coverage back into the gate, and do not put this project's work in
   front of it either.

   That 107-minute figure is also the clearest measure of the problem this project exists
   for. It is not the gate that hurts — it is what the suite costs once something has to
   walk every branch of it.

2. **Run `tests/mutrun.py` before removing anything.** Coverage says a line was executed;
   mutation says someone cared. A test that looks redundant but kills mutants is
   load-bearing. Survivors are the map for where the suite is thin — use them, don't
   trim against coverage alone.

3. **Diagnostic-counter tests stay.** `tests/test_diagnostics.lua` exists because of the
   raid of 2026-08-03, where four messages went missing and no client could say why.
   Its counters do not fix anything; they make the *next* incident distinguishable.
   That class of test is the highest-value thing in the suite — it is the only bridge
   between a live-only failure and a reproducible one. Never trim for size.

## Decisions taken elsewhere that touch this

From the same session, for the planned `lua-reviewer` agent:

- The reviewer does **not** assess test coverage. Reading a diff to guess at coverage is
  weaker and dearer than measuring it. That job stays with luacov and `mutrun.py`.
- "Testlücke" was removed from the reviewer's label vocabulary for that reason.
- It may still note "this branch looks unreached" under **Ungemessen**, but only with the
  luacov check that confirms or refutes it named alongside. A suspicion with a named
  test, never a claim.

## Open, deliberately not answered

As coverage approaches every branch, the suite grows without bound. Acknowledged, parked.
Decide it inside this project rather than drifting into it.

## Related

`docs/MANIFEST.md`, `docs/BACKLOG.md`, `docs/REVIEW-DECISIONS.md`, `tests/mutrun.py`,
`tests/test_diagnostics.lua`, `.github/workflows/check.yml`
