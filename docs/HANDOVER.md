# Handover — KeineAhnungRaidTools (KART)

Written 2026-08-12, for an agent picking this project up on a different platform (Synara) with no
history in it. It assumes nothing about the machine and repeats things a long-running session would
already know. Read it top to bottom once; after that use it as a lookup table.

Its companion is `docs/superpowers/handovers/2026-08-12-project-memory-export.md` — every cross-session
memory Claude holds about this project, consolidated. That file is **not** in git (the repo is public
and it quotes the maintainer); it has to be transferred by hand.

State at the time of writing: version **3.4.1**, branch `main`, working tree clean apart from an
unstaged `CLAUDE.md` addition (the `.refs` paragraph in "Lua and WoW"). Suite: **4403 assertions,
0 failures, 29 s** on `luajit tests/run.lua`.

---

## 1. What the project is

A World of Warcraft addon in Lua, for one guild's raid team. Distributed on CurseForge
(project 1603461), Wago (`QN53ZOKB`) and GitHub Releases. Public repo:
`https://github.com/Kandera/KeineAhnungRaidTools`. Single author/maintainer: Kandera.

Five modules, of which one dominates everything:

| Module | Files | What it does |
| :--- | :--- | :--- |
| **Loot Council** | `LootCouncil*.lua`, `LootHistory.lua` (~1.15 MB of the ~1.5 MB tree) | Replaces Blizzard's roll window: an item drops, every raider votes, a council reads the votes, the lootmaster awards and trades it out. This is what the project is judged on. |
| Buff Checker | `BuffChecker.lua` | Pre-pull check of flasks, food, runes, enchants, sockets, durability across the raid. |
| Invite / Auto-Promote | `Invite.lua`, `GroupLogic.lua` | Keyword invites, mass invite, auto-promote by name list. |
| Raid Lead Bar | `RaidleadBar.lua` | Ready check, markers, pull timer, countdown. |
| Droptimizer / WoWUtils | `Droptimizer.lua`, `Invite.lua` (`KART.WU`) | Imports sim gains from WoWUtils and shows them in the council panel. |

Plus `AutoLog.lua` (combat logging), `Profiles.lua` (settings profiles), `MainFrame.lua` (settings
window), `Utils.lua` (addon-level glue), `Core.lua` (event and slash wiring, the only file the
offline harness cannot load).

**The competition matters.** The raid compares KART against RCLootCouncil2 and the officers have
said one visible stumble means switching back. When KART's design differs from RCLootCouncil's on
the hot path, read RC's source (`Classes/Utils/GroupLoot.lua`, `ml_core.lua`) and prefer their
answer. This is a standing instruction, not a suggestion.

---

## 2. The five things, and the Manifest

Before anything else, know what "done" means here.

**The five things every raider touches** (maintainer, 2026-08-11) — these must work "in 1 Million von
1 Million Fällen":

1. everybody auto-passes (nobody ever sees a Blizzard roll window)
2. everybody sees every item immediately
3. everybody can press their buttons
4. the council reads the votes correctly
5. the items get handed out

Anything that only happens after a disconnect, a relog or a mid-fight reload is second priority. A
manual repair step (`/kart add`) is **not** a fix — it is evidence of a defect. Red chat output
counts as a failure of the same kind: any red `KART:` line reads to the raid as "schon wieder
kaputt" whether or not it names a real fault.

**`docs/MANIFEST.md`** ("das Manifest") is the formal version of that: core functions **C1–C15**,
each held to *ten attempts in the game, ten successes* — not ten green test runs. Refer to items by
number ("das bricht C7"); numbers are stable names and are never renumbered. C13/C14 were added
2026-08-03 after the first live raid on 3.3.0, C15 later (recipes are BoE but still go through the
council). Changing an item is the maintainer's call.

**`docs/OWNERSHIP.md`** is the settled rule for who owns settings and who hands out loot:

- **Config owner** = the current raid leader, always, checked via `UnitIsGroupLeader`. Never derived
  from settings or from who started the session.
- **Loot owner** = whoever the raid config's Lootmaster field names. It normally names someone else;
  if it names nobody, the raid leader does it.

A change that touches ownership is a change to that document first.

---

## 2a. Where the project actually stands (2026-08-12)

The chapter this document was missing. Everything above says how the work is judged; this says what
the current score is.

**The Manifest has two recorded runs, and the last one is not a pass.**

| run | version | date | result |
| :--- | :--- | :--- | :--- |
| three-man `/kart add` | 3.2.0 | 2026-07-31 | clean |
| guild raid, ~20 people | 3.3.0 | 2026-08-03 | **C5, C11, C13, C14 failed; C7 and C12 damaged** |

There is no third row, and none is missing: **nothing has been raided since.** The evidence is in the
repo. The 2026-08-03 raid left fifteen reports, GitHub issues #18–#25 and nine backlog entries
(B118–B126) — that is what a raid looks like here. Everything found afterwards came from a probe
instead: B171 "found by simulating a whole evening", B174 "Not found by a probe. Stated by the
maintainer". Tags confirm the timeline: `v3.3.2` on 2026-08-05, then `v3.4.1` on 2026-08-11 (there is
no `v3.4.0` tag — the release planned for that evening went out as 3.4.1). So **3.4.1 has been
shipped for one day and never seen a raid**, and C5/C11/C13/C14 stand as failed. That is the live
Manifest state, not a bookkeeping gap.

**The Loot Council module is on probation.** Since 2026-08-06 there are no test raids any more. The
next real raid decides whether the module stays at all, and Auto-Pass is the yardstick
(`kart-module-on-trial`). Until that raid is through, everything downstream of it is a plan, not an
assignment.

**The next assignment is 3.5.0 — WoWUtils data in KART — and it is locked.** Scope settled
2026-08-10, not started. Spec:
`docs/superpowers/specs/2026-08-10-wowutils-data-in-kart-design.md` (12.8 KB, untracked like
everything under `docs/superpowers/` — it has to travel with the memory export).

The lock is deliberate, and the chain is: **raid → a Manifest run that puts C5, C13 and C14 back at
ten of ten → then 3.5.0.** All three failed on lost messages (B118). Introducing new message types
before that measurement makes the measurement unreadable — two changes at once, and a silent loss
could no longer be attributed.

Settled in that scope, not to be re-opened: no write-back to WoWUtils; no direct API access instead
of the bridge; no vault; the file pattern is dropped. Everything new travels `BULK`, never `NORMAL`;
nothing waits on the extra data; none of it enters the reload state (C8); and an empty cell must
distinguish three states, or C13 repeats. On the Companion side the one write path into the game —
`WriteBlock` in `KARTCompanion/SyncEngine.cs:100` — goes away, while `DT.GetGainPercent` stays intact
in the addon so the old route remains a real fallback.

---

## 3. Documents that govern the work — read order

| File | Read it | Why |
| :--- | :--- | :--- |
| `CLAUDE.md` | first, in full | Project conventions. Language rules, changelog style, the Manifest, Lua/WoW facts. |
| `AGENTS.md` | know it exists | Near-copy of `CLAUDE.md` for non-Claude agents. **Currently 26 lines short** — it is missing "Before proposing a change" and the whole "Lua and WoW" section. Synara probably reads this file: sync it. |
| `docs/MANIFEST.md` | in full, once | The standard. 328 lines, C1–C15. |
| `docs/OWNERSHIP.md` | in full, once | Who owns what. |
| `docs/REVIEW-DECISIONS.md` | in full, before reviewing anything | Findings deliberately **not** fixed. Re-raising one costs the maintainer a round of explanation. |
| `docs/BACKLOG.md` | headings only (`grep '^## '`), bodies on demand | 352 KB, 140 entries `B28`…`B175`. **Every heading carries its own verdict inline** (`FIXED`, `NO DEFECT`, `NARROWED`, `OPEN by choice`). Never read the body until a heading looks relevant. |
| `docs/BACKLOG-12.1.md` | when touching client-version behaviour | Findings measured on the 12.1 PTR. **Nothing there is applied until the guild's last 12.0.7 raid is over.** Entries are `P1`, `P2`… so they never collide with `Bnn`. |
| `docs/testsuite-brief.md` | before proposing test-suite work | A deferred project with a starting position already written. |

Rule of thumb the maintainer paid for twice: **check `REVIEW-DECISIONS.md` and the `BACKLOG.md`
headings before raising a concern.** These two documents exist to stop settled decisions being
re-opened.

---

## 4. Hard rules

These come from `CLAUDE.md` and from memory entries the maintainer has repeated. Breaking one
produces work that gets thrown away.

**Language.** Everything is English: commit messages, code comments, PRs, issues, `README.md`,
`CHANGELOG.md`. Intentional exceptions: the string *values* in `Locales/deDE.lua` (comments in it
are still English), and `README-de.md` / `CHANGELOG-de.md`, which are German mirrors. **English file
first, German mirrored in the same turn.** Some older code comments are still German — leave them
unless you are already editing that block.

**Changelog.** Every user-facing change updates `CHANGELOG.md` *and* `README.md` (relevant feature
section) *and* both `-de` mirrors, in the same turn, without being asked. Style: **one line per
entry**, at most two for a big change. Bold lead plus a short effect clause; often the bold lead
alone is the entry. Never: causes, "was X, now Y", rationale, implementation detail, examples.
Keep-a-Changelog headings (`### Added` / `### Changed` / `### Fixed` / `### Removed`). Pure internal
fixes still normally get a `Fixed` line; they do not touch README.

**No old versions, ever.** Nobody in the raid runs an outdated KART — it is mandatory and enforced
socially. `LC.PROTOCOL_VERSION` (currently `"3.4.0"`) and `LC.WarnOutdatedRaiders` exist to *name*
whoever has not updated, not to tolerate them. **Never** justify a fix, fallback or tolerance with
"an older client sends no X" or "a mixed-version raid". Wire formats may break compatibility freely.
When a field can legitimately be absent, the reason must be a real state of a *current* client (a
stand-in owner that never saw the roll start, an owner that reloaded) and must be named explicitly.

**Direct to `main`.** No feature branches; the whole history is direct-to-main. Don't default to a
worktree or branch without asking. (Exception the maintainer accepts: a throwaway worktree for a
mutation run, because those write mutated source to disk.)

**SavedVariables have no central migration.** Each structure guards its own shape — `Droptimizer.lua`
checks a `schemaVersion`, `OfficerNotes.MigrateOfficerNoteKey` renames a key. A shape change without
such a guard corrupts existing users on their next login. Authoritative list is the `.toc`:

```text
SavedVariables:             KART_Settings, KART_LootHistory, KART_LootHistoryClearedAt,
                            KART_LootHistoryEpoch, KART_LCOfficerNotes, KART_WoWUtilsCache,
                            KART_Profiles, KART_PlayerCache
SavedVariablesPerCharacter: KART_LCTrades, KART_LCSession
```

**Lua 5.1 on LuaJIT.** No `goto`, `unpack` not `table.unpack`, no integer division, no `//`.

**Enchant / spell / item ID tables are per-patch maintenance, not defects.** `GOOD_ENCHANTS` in
`Utils.lua` is the documented case (`REVIEW-DECISIONS.md`). Do not file them as bugs.

**Cost against reality.** Before designing a fix, ask how often the case actually occurs in a real
raid. That decides the size of the solution.

**Label every finding** as one of: Bug / Feature / Kein Loch / Entscheidung / Ungemessen.
("Testlücke" was deliberately removed from the vocabulary — coverage is measured, not guessed.)

---

## 5. Repository layout

```text
KeineAhnungRaidTools/
├── KeineAhnungRaidTools.toc     load order + SavedVariables — the authoritative file list
├── Libs/                        vendored + own libraries (see below)
├── Locales/enUS.lua, deDE.lua   key sets must match exactly (gated in CI)
├── media/                       textures, backgrounds
├── *.lua                        the addon, 19 files, load order in the .toc
├── tests/                       offline harness, 71 .lua files, ~1.6 MB
├── docs/                        MANIFEST, OWNERSHIP, REVIEW-DECISIONS, BACKLOG, BACKLOG-12.1,
│                                testsuite-brief, this file; superpowers/ is gitignored
├── .github/workflows/           check.yml, coverage.yml, release.yml
├── .claude/                     agents/ + hooks/ tracked; settings*.json local
├── .codex/                      same tooling for Codex; fully gitignored
├── .vscode/settings.json        gitignored — contents reproduced in §9
├── .luacheckrc                  the global whitelist; this is what catches typo'd globals
└── .pkgmeta                     BigWigs packager config (what ships to CurseForge)
```

### Libraries (`Libs/`)

Vendored verbatim, excluded from luacheck, never edited: `LibStub`, `CallbackHandler-1.0`,
`AceComm-3.0` (+ `ChatThrottleLib`), `LibDeflate`.

Own libraries, written for this project and shared with the sibling "KA" addons — these have their
own version numbers and their own rules:

| Library | Version | Responsibility |
| :--- | :--- | :--- |
| `KAUtil-1.0` | MINOR 6 | String/group/item-link/table helpers. No state, no strings, no dependencies. Also `IsSecret` — Midnight hands addons "secret values" that look like strings and throw on every string operation. |
| `KAGS-1.0` | MINOR 1 | Scans the **local player's own** gear for missing enchants/sockets/oils. Knows nothing about the network. |
| `KASC-1.0` | MINOR 6 | The comm layer: prefix, send wrapper, inbound dispatch, sender identity, responders. Runs over AceComm-3.0 since 2026-08-03. **There is no `KARTSync.lua`** — that name is stale. Governing asymmetry: KASC owns the *answering* side, consumers own the *receiving* side. |
| `KAUI-1.0` | MINOR 5 | Shared widget toolkit; per-namespace widget registries so two addons restyle only their own widgets. |

**The library boundary is enforced by a CI gate.** No file under `Libs/` may reference `KART.<x>` or
any of the addon's SavedVariables globals by name — `tests/check-moved.sh` fails the build if one
does.

### Widget-construction trap, repeated in five files

Settings widgets are built at **file load time**, before `Core.lua`'s `ADDON_LOADED` handler creates
`KART_Settings`. Passing the table directly freezes the widget onto `nil` forever. Every such file
passes a `store` function instead (`local function SettingsStore() return KART_Settings end`) and
KAUI resolves the global at click/drag time. See `ResolveStore` in `KAUI-1.0.lua`.

---

## 6. Environment setup

Two supported shapes. Do the checks at the end of whichever applies — they are the definition of
"the environment works".

### 6a. Linux container (Synara cloud, CI-like)

```bash
sudo apt-get update
sudo apt-get install -y luajit lua5.1 luarocks python3 git
sudo luarocks install luacheck
sudo luarocks install luacov          # only needed for coverage / mutation work
```

That is exactly what `.github/workflows/check.yml` and `coverage.yml` do. Nothing else is required
to run the full suite — the harness has no external Lua dependencies.

What does **not** exist in a container, and what to do instead:

| Missing | Consequence | Substitute |
| :--- | :--- | :--- |
| The WoW client | No in-game verification, so **no Manifest run** is possible | Deliver the change plus a precise in-game test recipe; the maintainer runs it. Say plainly that C-items are unverified. |
| `E:\World of Warcraft\...\AddOns\KeineAhnungRaidTools` junction | Edits are not live in a client | n/a in a container |
| `E:\Projects\.refs\wow-ui-source` | No local FrameXML mirror | `git clone https://github.com/Gethe/wow-ui-source` (see §10) |
| ketho.wow-api VS Code extension | No API annotations for the language server | Clone `https://github.com/Ketho/vscode-wow-api` and point the language server at its `Annotations/Core` (see §9) |
| PowerShell | `.claude/hooks/luacheck.ps1` cannot run | Use the bash port in §11 |

### 6b. Local Windows (this machine)

Everything is already installed. Versions as measured 2026-08-12:

| Tool | Version | Location |
| :--- | :--- | :--- |
| LuaJIT | 2.1.1720049189 | `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe` |
| Lua (PUC) | 5.4.6 | `%LOCALAPPDATA%\Programs\Lua\bin\lua.exe` — only luarocks' host, **not** what the addon runs on |
| LuaRocks | 3.9.2 | `%LOCALAPPDATA%\Programs\Lua\bin\luarocks.bat` |
| luacheck | 1.2.0 (on Lua 5.4) | `%LOCALAPPDATA%\Programs\luacheck\luacheck.exe` |
| luacov | 0.17.0-1, tree **Lua 5.1** | `C:\Users\max\.luarocks\lib\luarocks\rocks-5.1` |
| Python | 3.14.6 | for `tests/mutrun.py` only |
| git, gh | on PATH | `gh` is used for the API recipes in `BACKLOG-12.1.md` |

Two Windows-specific facts that cost time if unknown:

1. **LuaJIT does not look in luarocks' per-user tree.** `tests/run.lua` patches `package.path` with
   `$USERPROFILE/.luarocks/share/lua/5.1/…` itself before requiring luacov. If coverage silently
   says "luacov is not installed", that path is the thing to check.
2. **`rsync` and `zip` are not installed** and are not needed — only `release.yml` uses them, on an
   Ubuntu runner.
3. The shell scripts (`tests/check-moved.sh`, `tests/check-locale.sh`) need **bash**. Git Bash works;
   `check-locale.sh` writes scratch files to `/tmp`, which Git Bash provides.

### Verification that the environment works

```bash
luajit tests/run.lua          # expect: "4403 assertions, 0 failures", ~29 s, exit 0
luacheck .                    # expect: 0 warnings, 0 errors
bash tests/check-moved.sh     # expect: Gate 1 clean, Gate 2 clean, Gate 3 lists aliases
bash tests/check-locale.sh    # expect: "locale check: ok" + a note about unused keys
```

If all four pass, the environment is complete for everything except in-game work.

---

## 7. The test suite

### What it is

An **offline harness**: WoW's API is stubbed, the addon files are loaded as chunks the way the game
loads them, and several simulated clients exchange real addon messages inside one Lua process. It is
run with LuaJIT from the repo root — always the repo root, paths are relative.

```bash
luajit tests/run.lua
```

Four harness files, ~160 KB, about 10 % of `tests/`:

| File | Role |
| :--- | :--- |
| `tests/wow_stubs.lua` (1400+ lines) | Minimal WoW API. **Deliberately incomplete** — a test that reaches beyond it should fail loudly rather than pass against a convincing fake. Exports roster/state controls as the global `KARTTEST`. |
| `tests/raidsim.lua` (750+ lines) | A simulated raid. Loads the addon files **once per simulated client**, each in its own environment, and routes `C_ChatInfo.SendAddonMessage` between them — including the echo back to the sender, as the game does. Deliberately not simulated: rendering, taint, Blizzard's own loot roll. |
| `tests/lc_fixture.lua` (360+ lines) | The one raid every multi-client Loot Council test runs against: real item IDs, a mixed German/English roster, every raider on a different combination of personal switches. Shared, not copied — the fixture *is* part of what the tests assert. |
| `tests/run.lua` | Loader + assertions (`T.eq`, `T.truthy`, `T.is_nil`, `T.deep_eq`) exported as the global `T`. |

### Traps in the runner that will bite

- **Load order in `run.lua` is load-bearing and should not be.** The addon jitters its own replies
  with `math.random`, and several `test_lc_churn.lua` assertions turn on which jittered reply lands
  first. Inserting a file *anywhere above* `test_lc_churn.lua` changes the random stream and silently
  changes what those assertions measure. Reseeding per file — the obvious fix — makes five of them
  fail for real (see `B70`). **Until B70 is fixed, new test files go at the END of the list.**
- **`Core.lua` is not loadable offline** (it needs the game) and reports **zero executed lines** in
  coverage. That is expected. Its event and slash wiring is checked against the *source text* by
  `tests/test_core_wiring.lua` — anything new added to `Core.lua` gets a line there in the same commit.
- **`KARTTEST.FireEvent` only reaches the currently active client** (`reg.owner == owner` in
  `wow_stubs.lua`). A bare `KARTTEST.SetRestriction(...)` therefore closes the comms gate on exactly
  one client while the simulated guild reads the world normally. For anything hanging off a global
  event, loop over `sim.clients` and fire inside `RaidSim.As(c, ...)`. Two false findings on
  2026-08-06 came from exactly this.
- **`raidsim.lua` re-reads the addon source per client at runtime**, not once at start. So editing a
  `.lua` addon file while a long run is in progress changes the run from the next seed onward, and a
  `git checkout` mid-run produces `raidsim: cannot open LootCouncil.lua` as a fake test failure. Test
  files are safe (loaded once by `dofile`); addon files are not.

### Two scripts deliberately outside `run.lua`

```bash
luajit tests/check_the_five_at_raid_size.lua    # the five things, asked of EVERY client at raid size
luajit tests/measure_loot_under_throttle.lua    # loot distribution with ChatThrottleLib's limiter ON
```

Both are slow and are excluded on purpose. The suite's fixture is five clients by design; the first
script scales it to a real raid. The second prints numbers and asserts nothing — every other test
runs with the rate limiter switched **off**, so this is the only place the real wire is measured.
Run the first before a raid and after any change to the drop, vote, award or session paths; run the
second when the shape of the distribution changes (new message, bigger payload, another repeat).

### The soak

`tests/test_lc_soak.lua` runs randomized convergence scenarios. Inside the normal suite it does
150 seeds; the long run is 30000.

```bash
KART_SOAK_SEEDS=30000 luajit tests/run.lua     # the long run
KART_SOAK_ONLY=39 luajit tests/run.lua         # one seed, for debugging only
KART_SOAK_DEBUG=39                             # verbose trace for that seed
KART_SOAK_LISTFAILS=1                          # print "SEEDFAIL <n> <why>" per failure
KART_SOAK_TRACEROLLS=1 / KART_SOAK_TRACEITEMS=1
```

**Soak hygiene, learned the hard way:**

- **Individual seeds are not comparable between two builds.** The addon draws from the same
  `math.random` stream as the scenario generator, so any change to how often it rolls — even a
  different `IsLootOwner` answer — shifts every later draw. Seed 39 then runs a different scenario
  entirely. **Compare rates ("x of 8000"), never seed numbers.** A fix was once discarded over
  "seed 39 is red now", and seed 39 was simply running something else.
- **Commit before a confirmation run and keep your hands off the addon files.**
- **Never run a soak and a mutation run at the same time**, not even "briefly".
- In the last big soak, **13 of 17 deviations were the test environment, not the addon.** Mark and
  count first, diagnose second. A harness artifact costs exactly as much triage time as a real defect.
- Soaks that only compare clients against each other cannot see a state on which every client agrees
  and all of them are wrong. Add an absolute anchor when that matters.

---

## 8. Coverage, mutation testing, static gates

### luacov

```bash
KART_COVERAGE=1 luajit tests/run.lua
sed -n '/^Summary$/,$p' luacov.report.out
```

Opt-in on purpose. luacov installs a debug hook per executed line, which effectively turns LuaJIT's
compiler off — the run costs **15m02s** today. Outputs `luacov.stats.out` and `luacov.report.out` in
the repo root; both are gitignored. `run.lua` excludes `^tests/` and `^luacov` and calls
`coverage.shutdown()` plus the reporter *before* `os.exit`, because luacov's own exit hook never
fires from there. `raidsim` loads each addon file with an `@path` chunk name so counts land under
the real source paths even though each file is loaded once per simulated client.

The history is the method, and it is worth copying: coverage had grown to **83m51s** locally
(106m45s in CI). Commit `28b0663` measured *where* the time went — luacov charges one hook call per
executed line, so line events were the unit — and found **63.5 %** of the whole run in a single line
advancing simulated time across a week while `PumpComms` ticked every simulated client's `OnUpdate`
on queues that were empty throughout. The harness was pumping a despool frame that a real client
hides when its rings run dry: *less* faithful than the thing it stood in for, not merely slower.
Result 83m51s → 15m02s with the coverage summary unchanged file for file, uncovered lines identical
line for line, and 26 recorded mutations re-run to identical verdicts. **Measure first, fix the
harness, prove nothing changed. Do not start by deleting tests.**

### Mutation testing

```bash
KART_COVERAGE=1 luajit tests/run.lua                                   # precondition: fresh report
MUT_OUT=survivors.json python tests/mutrun.py LootCouncil.lua,LootCouncilVote.lua [limit]
MUT_SEEDS=1                                                            # optional, default "1"
```

Only lines luacov marks **executed** are mutated — a stale report silently measures the wrong thing.
Comments and strings are skipped. The script writes mutated source to disk and takes it back, so:
never run the suite by hand while it works, and after any interruption check `git status` for a
mutant left behind. Prefer a throwaway `git worktree` if a second session is active.

**Its limits, so they are not rediscovered:** the rule set knows only `<`, `>`, `<=`, `>=` and
`and`→`or`, and it **skips every line containing a quote**. So it never reaches `~=`/`==`
comparisons, `type(x) ~= "string"` guards, or calls like `LC.IsLootOwner()` — i.e. most of this
codebase. The answer that worked: **name a mutation set by hand**, one mutation per decision, each
phrased as "what a plausible wrong version would say" (flip every comparison, delete every clause,
strike each half of a "both sides must be comparable" pair, remove each cleanup line). That found
four gaps in B139 and thirteen in B141–B148 — all in fixes that had been written red-first, because
red-first covers the defect that prompted the change, not the decisions around it. It also cannot
lift a bound, only shift it by one (`<` → `<=`), so "runs forever or not at all" is *Ungemessen*.

**Five kinds of survivor**, and a finding must be sorted into one: a real gap; equivalent by
construction; defensive code nothing reaches; a comparison whose equality case an enclosing guard
already excluded; and **a guard that stands twice** — one mutation breaks only one of the pair, the
other catches it, so both report as alive and neither is a hole. Always look one level up before
writing a survivor down. **Results belong in `docs/BACKLOG.md`**, not in a temp-folder log; and line
numbers age fast (`LootCouncil.lua` went 3678 → 5261 → 6754 lines), so carry the *named clusters*
forward, never the numbers.

### Static gates

- **`luacheck .`** — configured by `.luacheckrc`. `std = "lua51"`, vendored libs excluded,
  `unused_args` off (WoW hands fixed signatures to every callback). Every WoW API the addon touches
  is listed in `read_globals`; the addon's own SavedVariables and named frames in `globals`.
  **Anything not listed is reported as an undefined global — that is the whole point:** it is what
  catches a typo'd global, which in Lua is otherwise silent until that exact line runs, possibly
  mid-raid. Adding a new API means adding it to `.luacheckrc` in the same commit.
- **`bash tests/check-moved.sh`** — three gates. (1) No symbol in `tests/moved-symbols.txt` may still
  be referenced as `KART.<name>`; luacheck cannot see this, because `KART` is a defined global and
  field access on a known table is not validated. (2) No file under `Libs/` may reference `KART.` or
  any SavedVariables global by name. (3) Informational: lists every `local x = KART.y` alias
  declaration, because the codebase aliases heavily and gate 1 is blind to call sites through an alias.
- **`bash tests/check-locale.sh`** — enUS and deDE must define the same key set (hard fail), and no
  `L.KEY` used in code may be undefined (hard fail). Defined-but-unused is deliberately *not* an
  error: BuffChecker carries keys as table fields (`labelKey = "BC_LABEL_FLASK"`) and resolves them
  at runtime, so a static sweep reports ~33 live keys as dead.

---

## 9. VS Code, and how to reproduce the editor setup elsewhere

`.vscode/` is **gitignored**, so nothing below arrives with a clone. Reproduce it.

### The two extensions that actually matter for this repo

| Extension | Version | Why |
| :--- | :--- | :--- |
| `sumneko.lua` | 3.19.0 | The Lua language server. Everything below is its configuration. |
| `ketho.wow-api` | 0.22.3 | Blizzard's generated API annotations, the event list with per-event arguments, and Blizzard's FrameXML source. **This is the sanctioned source for API facts** — never assert WoW API behaviour from memory. |

`.vscode/settings.json`, reproduced in full so it can be recreated anywhere:

```jsonc
{
  "Lua.runtime.version": "Lua 5.1",
  // Every stdlib is DISABLED: WoW does not expose io/os/package/debug, and the addon must not
  // learn to rely on them. string/table/math are re-supplied by the annotations instead.
  "Lua.runtime.builtin": {
    "basic": "disable", "debug": "disable", "io": "disable", "math": "disable",
    "os": "disable", "package": "disable", "string": "disable", "table": "disable",
    "utf8": "disable"
  },
  "Lua.workspace.library": [
    "~\\.vscode\\extensions\\ketho.wow-api-0.22.3\\Annotations\\Core"
  ],
  "Lua.diagnostics.globals": [
    "SlashCmdList", "ReloadUI", "PLAYER_DIFFICULTY1", "PLAYER_DIFFICULTY2", "PLAYER_DIFFICULTY6",
    "LOOT_FREE_FOR_ALL", "LOOT_GROUP_LOOT", "LOOT_MASTER_LOOTER", "LOOT_NEED_BEFORE_GREED",
    "LOOT_ROUND_ROBIN", "ITEM_QUALITY2_DESC", "ITEM_QUALITY3_DESC", "ITEM_QUALITY4_DESC",
    "StaticPopup_Hide", "UpdateInviteConfirmationDialogs", "LOOT_METHOD", "LOOT_THRESHOLD",
    "BNET_CLIENT_WOW", "ColorPickerFrame", "AddonCompartmentFrame", "RAID_CLASS_COLORS",
    "class", "UISpecialFrames", "NSAPI", "UIErrorsFrame", "RunNextFrame"
  ],
  "Lua.type.weakUnionCheck": true
}
```

**Without VS Code** (a container, a different editor, or a headless agent), the same setup is a
`.luarc.json` in the repo root plus a standalone `lua-language-server`, with the annotations cloned
from the extension's upstream repo:

```bash
git clone --depth 1 https://github.com/Ketho/vscode-wow-api /opt/wow-api
# then in .luarc.json: "workspace.library": ["/opt/wow-api/Annotations/Core"]
```

Keep the same three settings: `runtime.version` = `Lua 5.1`, the builtins disabled, the globals
whitelist. **Do not commit a `.luarc.json` without asking** — the repo has deliberately kept editor
config out of git so far.

Note the version skew, and the maintainer's ruling on it: the extension ships annotations for
**12.0.1** while the live client is **12.1**. That is not a reason to discard it — *"es gibt nicht
viele API-Änderungen in 12.1, also sind 12.0.1-Informationen immer noch besser als welche aus 11.x."*
An API backed by these annotations counts as a solid basis; what it does not replace is proof in the
game.

### Other extensions on this machine, and whether they concern this repo

| Extension | Relevance |
| :--- | :--- |
| `ms-python.python`, `debugpy`, `pylance` | `tests/mutrun.py` is the only Python here. |
| `github.vscode-github-actions` | Editing the three workflows. |
| `ms-vscode.powershell` | Editing `.claude/hooks/luacheck.ps1`. |
| `davidanson.vscode-markdownlint`, `shd101wyy.markdown-preview-enhanced` | `docs/`, README, CHANGELOG. |
| `anthropic.claude-code`, `singularityinc.claude-notifier` | The agent itself. |
| `actboy168.lua-debug` | A Lua debugger; usable for stepping through the offline harness. |
| `tyriar.luna-paint`, `tomoki1207.pdf`, `zainchen.json`, `mechatroner.rainbow-csv` | Incidental (textures under `media/`, exported CSV/JSON, reference PDFs). |
| `ms-dotnettools.*` | **KART-Companion** (C#), a *different* repo. |
| `bmewburn.vscode-intelephense-client` | The **KART Discord bot** (PHP), a *different* repo. |
| `ms-vscode.cpptools*`, `cmake-tools`, `docker/containers`, `bicep`, `remote-ssh`, `perl*`, `firefox-debug`, `prettier`, `github.remotehub`, `azure-repos` | Unrelated to KART. |

---

## 10. Reference sources for WoW API facts

Order of authority. **Never assert API behaviour from memory** — that rule is in `CLAUDE.md`.

1. **ketho.wow-api annotations** (12.0.1) —
   `C:\Users\max\.vscode\extensions\ketho.wow-api-0.22.3\Annotations\`:
   - `Core\Blizzard_APIDocumentationGenerated\*.lua` — signatures and field types
   - `Core\Data\Event.lua` — the event list *with the arguments per event*
   - `Annotations\FrameXML\...` — Blizzard's own use of an API, which settles ID spaces and ordering
2. **`E:\Projects\.refs\wow-ui-source`** — a local mirror of Blizzard's FrameXML source, sibling of
   this repo, **at version `12.0.7.68974`**. It is wired into *nothing*: no tool config loads it, it
   is not in the repo, and it is not in `.vscode/settings.json`. Pull it in as a secondary source
   when tracing FrameXML behaviour or a patch diff. It may lag the target patch — do not rely on it
   alone. Recreate elsewhere with `git clone https://github.com/Gethe/wow-ui-source` and check out
   the matching tag.
3. **`gh api` against the upstream repos**, the recipes live in `docs/BACKLOG-12.1.md`:

   ```sh
   gh api repos/Ketho/BlizzardInterfaceResources/compare/12.0.7...12.1.0   # GlobalAPI.lua, CVars.lua
   gh api repos/Gethe/wow-ui-source/compare/12.0.7...12.1.0                # FrameXML itself
   ```

   **Trap, paid for once:** GitHub's compare API returns at most **300 files**. This diff has more,
   so "the file is not in the list" proves nothing. Fetch both versions and diff locally:

   ```sh
   gh api repos/Gethe/wow-ui-source/contents/<path>?ref=12.0.7 --jq .content | base64 -d > a.lua
   gh api repos/Gethe/wow-ui-source/contents/<path>?ref=12.1.0 --jq .content | base64 -d > b.lua
   diff -u a.lua b.lua
   ```

4. `https://warcraft.wiki.gg/wiki/World_of_Warcraft_API` and Blizzard's game-data API docs.
5. **RCLootCouncil2** (`github.com/evil-morfar/RCLootCouncil2`) — not an API source, but the
   reference implementation for loot-council behaviour. Named explicitly by the maintainer.

Target client: **Midnight, 12.x**. The `.toc` declares interfaces `120005, 120007, 120100`.

---

## 11. Agent tooling in the repo

### `.claude/` (partly tracked — see `.gitignore`)

`.gitignore` uses `.claude/*` with negations so that `agents/` and `hooks/` are in the repo while
`settings.json`, `settings.local.json` and `worktrees/` stay local.

**`.claude/agents/lua-reviewer.md`** (tracked) — a review subagent for KART's Lua, aimed at the defect
classes static analysis cannot see: taint and protected calls, frame lifecycle, SavedVariables shape,
comm limits, event symmetry. Its design is worth copying to any platform:

- **Step 1 is reading the decisions, before any code:** `REVIEW-DECISIONS.md` in full,
  `OWNERSHIP.md` in full, `MANIFEST.md` in full, and every `'^## '` heading of `BACKLOG.md` (headings
  only — each carries its verdict inline; open a body only when a heading covers a finding you are
  holding). *"A finding that re-opens a settled decision is worse than no finding."*
- Default scope is the working-tree diff (`git diff HEAD`), because development goes direct to main.
- A diff hunk is never enough context: for every changed line, read the enclosing function.
- It does **not** assess test coverage — that job belongs to luacov and `mutrun.py`. It may say
  "this branch looks unreached" under *Ungemessen*, but only with the luacov check that would confirm
  or refute it named alongside.
- Its report is written in **German** (findings are read in conversation); only text destined for
  `docs/` is English.

**`.claude/hooks/luacheck.ps1`** (tracked) — a `PostToolUse` hook on `Edit|Write` that runs luacheck
on the file just edited. It closes the only window nothing else covers: CI runs on push, and the game
loads the working tree through the junction, but between an edit and starting WoW there is no check
at all — and a mistyped global is silent in Lua until that line runs, possibly mid-raid. It is silent
on success, reports on stderr with **exit 2** so the finding reaches the agent, skips non-Lua files
and `Libs/` quietly with exit 0, and *fails loudly* (also exit 2) if the hook itself is broken —
because a hook that fails quietly reads as "checked, clean" forever.

Wired in `.claude/settings.json`:

```jsonc
{ "hooks": { "PostToolUse": [ { "matcher": "Edit|Write", "hooks": [
  { "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"e:\\Projects\\KeineAhnungRaidTools\\.claude\\hooks\\luacheck.ps1\"" } ] } ] } }
```

**On a platform without PowerShell**, the equivalent is a few lines of shell. Same contract: exit 0
silently when the edit is none of its business, exit 2 loudly on a finding *or* on its own breakage.

```bash
#!/usr/bin/env bash
# reads the hook JSON on stdin; needs jq
raw=$(cat); [ -n "$raw" ] || { echo "luacheck hook broken: no stdin" >&2; exit 2; }
path=$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty') || exit 2
[ -n "$path" ] || exit 0
case "$path" in *.lua) ;; *) exit 0 ;; esac
root=$(git rev-parse --show-toplevel) || { echo "luacheck hook broken: not a repo" >&2; exit 2; }
rel=${path#"$root"/}; case "$rel" in Libs/*) exit 0 ;; esac
command -v luacheck >/dev/null || { echo "luacheck hook broken: not on PATH" >&2; exit 2; }
out=$(cd "$root" && luacheck --no-color --codes -- "$rel") && exit 0
printf 'luacheck: %s\n%s\n' "$rel" "$out" >&2; exit 2
```

**`.codex/`** is the same tooling for a different client (`hooks.json` + `agents/lua-reviewer.toml`,
pointing at the *same* `.claude/hooks/luacheck.ps1` file) and is fully gitignored. If Synara wants
its own directory, that is the pattern to copy — and add it to `.gitignore`, `.pkgmeta`'s `ignore:`
list and `release.yml`'s `--exclude` list, exactly as `.codex` and `.superpowers` are.

### Two gitignored working-note trees

- **`docs/superpowers/`** — `plans/`, `specs/`, `handovers/`. Internal working notes from planning
  sessions (39 plans, several specs, 5 handovers). The memory export lives here too. Local only.
- **`.superpowers/`** — scaffolding from subagent-driven-development runs: ledgers, briefings,
  reports, review diffs. Pure scaffolding; diagnoses that must survive go into `docs/BACKLOG.md` and
  into comments at the code.

The workflow those come from: batch bug reports, organize with cross-references, *then* plan;
subagent-driven development for anything plan-sized, but a genuinely small single-file fix gets fixed
directly — match ceremony to size. And: when a review finds a real defect that traces back to *the
plan text itself*, stop and ask before fixing, even when the fix is obvious. The plan's author should
not grade its own work.

### `AGENTS.md`

Tracked, a near-copy of `CLAUDE.md`, excluded from the shipped zip by both `.pkgmeta` and
`release.yml`. **It is currently 26 lines shorter than `CLAUDE.md`** — missing "Before proposing a
change" (the REVIEW-DECISIONS/BACKLOG rule) and the entire "Lua and WoW" section (API sources, the
`.refs` mirror, Lua 5.1 constraints, the KASC comm layer, SavedVariables migration, per-patch ID
tables). If Synara reads `AGENTS.md` rather than `CLAUDE.md`, **sync the two before starting work** —
otherwise the agent is missing the most operationally important half.

*(A memory entry says an untracked `AGENTS.md` is a Codex/Synara artifact that must not be committed.
That was true before; in this repo the file is now deliberately tracked. The memory still holds
elsewhere.)*

---

## 12. Claude's cross-session memory — where it is and why it is split

Not in the repo. `C:\Users\max\.claude\projects\<path-slug>\memory\*.md`, one fact per file with YAML
front matter, plus a `MEMORY.md` index loaded at session start.

**This project's memory is split across three stores** because the repo has been opened from three
different paths, and a session only loads the store matching its own path:

| Store | Files | Contains |
| :--- | :--- | :--- |
| `e--Projects` (opened one level up) | 44 | The bulk: workflow, testing, comms rework, releases, companion, issue handling |
| `e--World-of-Warcraft--…-KeineAhnungRaidTools` (opened through the junction) | 7 | Changelog/README rule, layout-timing feedback, companion repo split, older project state |
| `E--Projects-KeineAhnungRaidTools` (opened in the repo) | 2 | The five things; no-old-versions |

That split is why `CLAUDE.md` cites `feedback_changelog_readme` and `kart-soak-harness-vs-addon`,
which a session started *in the repo* cannot see. All 55 files, verbatim and thematically grouped,
are in `docs/superpowers/handovers/2026-08-12-project-memory-export.md`, with the four known-stale
entries corrected in its preamble. **Read that file once, fully.** It is the single largest body of
project knowledge that does not exist anywhere in the repository.

---

## 13. In-game verification

The automated suite is *the floor, not the standard*. It cannot see a cursor, a Blizzard roll window,
or a real reload — and the Manifest demands ten-of-ten in the game.

- `E:\World of Warcraft\_retail_\Interface\AddOns\KeineAhnungRaidTools` is a **junction to the
  repo**. Every commit is live in the client: no build, no copy step.
- `/reload` picks up changes to **existing** files. **New** files (a new `.lua`, a new texture) are
  only indexed at client start and fail silently until a **full restart**. Adding a file to the
  `.toc` and then wondering why it does not load is the classic hour lost here.
- Writing `/run` probes: `KART` is the addon's private vararg table, **not a global** —
  `/run print(KART.x)` errors with *"attempt to index global 'KART'"*. Reachable instead:
  `LibStub("KAUI-1.0").namespaces.KART` (registries `buttonTexts`, `labels`, `editBoxes`, plus
  `lastFont`/`lastContentSize`) and the SavedVariables (`KART_Settings`, `KART_LootHistory`,
  `KART_Profiles`, …). The chat box caps input at **255 characters**; longer probes are truncated
  mid-script — split them or use a macro.
- `/kart status` prints a local diagnostic block (module state, session state, lootmaster, vote
  buttons, tracked rolls) and is the first thing to ask for when an item is not showing up for
  someone. Full command list in `README.md`.
- Real-world conditions the raid actually produces: people port out mid-distribution and relog
  constantly, so the council must resynchronize **without the lootmaster doing anything**. There are
  no test raids any more — the next real raid is the test, and Auto-Pass is the yardstick.

---

## 14. CI and release

Three workflows, and the split between the first two is deliberate.

**`check.yml` — the gate.** On every push and PR: install luajit/lua5.1/luarocks + luacheck, then
`check-moved.sh`, `check-locale.sh`, `luacheck .`, `luajit tests/run.lua`. About **80 seconds** all
together. The maintainer ships fixes *during a raid night*; a gate that answers in eighty seconds is
the entire point. Do not add slow work to it.

**`coverage.yml` — on demand only** (`workflow_dispatch`), deliberately not scheduled. It ran inside
`check.yml` until 2026-08-10, by which point it took 107 minutes, and a push then showed a single
amber run for two hours with no way to see from outside that the part deciding "may this ship" had
finished in eighty seconds. It has never had a veto (`continue-on-error`). What it is actually *for*
is `mutrun.py`, which needs to know which lines the suite reaches at all — and the run that matters
for that is the **local** one, immediately before the sweep, on the tree being swept.

**`release.yml` — on tag `v*`.** Three jobs:

1. **build** — assembles `dist/KeineAhnungRaidTools/` with an `rsync --exclude` list that **mirrors
   `.pkgmeta`'s `ignore:` block**, zips it, extracts this version's section from `CHANGELOG.md`
   (falling back to the base version for a pre-release tag like `v3.4.1-beta1`, then to
   `[Unreleased]`), and creates the GitHub Release. Pre-release tags (any tag containing `-`) are
   marked prerelease automatically. **Keep the `.pkgmeta` ignore list and the rsync excludes in
   step** — a GitHub download that differs from the CurseForge one is a difference nobody thinks to
   check.
2. **discord** — final tags only. Posts the **German** changelog section to a webhook, downgrading
   `###` headings to bold (embeds do not render markdown headers) and splitting on line boundaries at
   4000 chars (Discord's embed description caps at 4096). Fails hard if `CHANGELOG-de.md` has no
   section for the version — so the German mirror is not optional.
3. **curseforge** — final tags only, `BigWigsMods/packager@v2`, uploading to CurseForge and Wago.

**Secrets** in the repository settings: `DISCORD_WEBHOOK`, `CF_API_TOKEN`, `WAGO_API_TOKEN`.

**Release checklist**, in order: suite green → `luacheck .` clean → both gate scripts clean →
Manifest run in the game for whatever the change touched → `CHANGELOG.md` + `CHANGELOG-de.md` +
`README*.md` updated → bump `## Version:` in the `.toc` → commit → tag `vX.Y.Z` → push tag.

**Commit style.** English, imperative, describing the *effect*, with the backlog number in
parentheses. Type prefixes are used for non-user-facing commits (`test:`, `docs:`, `fix(ci):`).
Recent examples:

```text
Stop telling the raid about a window we could not handle (B175)
Auto-Pass off the session, not off a message (B174)
test: ask the five, of every client, at raid size
docs: leave the double-loss divergence alone, and re-price B171 honestly
```

---

## 15. Neighbouring projects (separate repos, do not confuse)

- **KART-Companion** — C# tray app, `github.com/Kandera/KART-Companion`. Syncs WoWUtils droptimizer
  sims into the Loot Council. Split out of this repo on purpose: 99 % of users don't need it, and it
  would force .NET concerns onto every KART CI run. It has its own workflows, versioning and README;
  the addon repo only links to it. On this machine it is at `E:\Projects\KART-Companion`
  (`KARTCompanion\SyncEngine.cs` is the file §2a names). It used to sit under
  `E:\World of Warcraft\_retail_\Interface\AddOns\`, which is why older notes place it there — it is
  *not* a WoW addon and is no longer in that folder.
- **KART Discord bot** — PHP, `e:\Projects\KART-Discord-Bot`, deployed by FTP. Mirrors forum posts to
  GitHub issues and comments both ways.
- **WoWUtils** — a third-party service KART imports sim data from. The integration contract is in the
  memory export; the loot-history endpoint it would need does not exist yet.

The `lua-reviewer` agent is for **this repo's Lua only** — not the C# app, not the PHP bot.

---

## 16. First hour on a new platform — checklist

1. Clone the repo; confirm `git log --oneline -1` shows `cd12f4c` or later on `main`.
2. Install the toolchain (§6) and run all four verification commands. Expect
   **4403 assertions, 0 failures**. If the number differs, that is the first thing to explain.
3. Read, in this order: `CLAUDE.md` → `docs/MANIFEST.md` → `docs/OWNERSHIP.md` →
   `docs/REVIEW-DECISIONS.md` → `grep '^## ' docs/BACKLOG.md` → this file's §4 →
   the memory export in full.
4. Sync `AGENTS.md` with `CLAUDE.md` (§11) — or read `CLAUDE.md` instead, but do not work from the
   short one unknowingly.
5. Set up the language server with the WoW annotations (§9). Without it, API guesses will slip in,
   and "never assert API behaviour from memory" is a hard rule.
6. Set up an edit-time luacheck hook (§11) — this repo assumes one exists.
7. Decide with the maintainer how in-game verification happens on this platform. If Synara cannot
   reach the client, every Manifest item stays unverified and the handover of *that* step has to be
   explicit in each change.

## 17. The traps, in one list

- New test file goes at the **end** of `run.lua` (B70, random stream).
- `Core.lua`: 0 % coverage is correct; cover it in `test_core_wiring.lua`.
- Fire per-client events through `RaidSim.As`, not globally.
- No addon-file edits while a soak or mutation run is in flight; `git status` after any interruption.
- Compare soak results by **rate**, never by seed number.
- Refresh `luacov.report.out` before every mutation sweep; mutation line numbers age within days.
- New WoW API used ⇒ add it to `.luacheckrc` in the same commit.
- New locale key ⇒ both `enUS.lua` and `deDE.lua`, or CI fails.
- New file in the `.toc` ⇒ full WoW restart, `/reload` is not enough.
- SavedVariables shape change ⇒ its own guard, or existing users are corrupted on next login.
- New `Libs/` code must never touch `KART.` or a SavedVariables global.
- User-facing change ⇒ four documents (`CHANGELOG.md`, `CHANGELOG-de.md`, `README.md`,
  `README-de.md`), same turn.
- Never argue from "old clients" or "mixed-version raids".
- Coverage is never a release gate; the 80-second gate is never slowed down.
