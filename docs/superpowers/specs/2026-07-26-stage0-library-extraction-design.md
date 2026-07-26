# Stage 0 — Library Extraction (KAUtil / KAGS / KASC / KAUI)

**Date:** 2026-07-26
**Target release:** v3.0.0
**Status:** design approved, implementation plan pending

Written in English per the project convention in `CLAUDE.md`.

---

## 1. Context

KeineAhnungRaidTools is 12285 lines of Lua across 19 files. The Loot Council feature set —
`LootCouncil.lua`, `LootCouncilOfficerNotes.lua`, `LootCouncilVote.lua`, `LootCouncilTrade.lua`,
`LootCouncilPanel.lua`, `LootCouncilSettings.lua` and `LootHistory.lua` — accounts for 6398 of
them, or 52%.

A possible future direction is to ship Loot Council as a standalone addon (working name **KALC**),
so that raiders who only need the vote popup do not have to install the full raid-lead toolkit.
That split is **deferred**: the adoption barrier that would justify it is anticipated, not
measured, and the addon is ~99% used by its own raid group.

Stage 0 is the preparation that is worth doing regardless of whether the split ever happens. It
extracts the genuinely shared parts into versioned LibStub libraries inside the existing addon,
which both cleans up the current structure and reduces the split — if it comes — to copying
folders.

### The constraint that shapes everything

If Loot Council ever ships standalone, a KALC-only raider must still be able to **answer**
`REQ_OIL`, `REQ_GEAR`, `REQ_ILVL` and `REQ_ENCH`, or the KART user's Buff Checker goes blind for
that player. Those responders currently live in `KARTSync.lua` and call `KART.SlotNeedsOil`,
`KART.CountMissingGear` and `KART.SerializeOwnEnchantIDs` in `Utils.lua:1094-1300`.

So the shared layer is not a thin transport. It has to carry the gear/enchant scanner too. This is
the single fact that drives the library cut below.

---

## 2. Goals and non-goals

### Goals

1. Four self-contained LibStub libraries with a strictly acyclic dependency graph and **zero**
   references back into `KART.*`.
2. `KARTSync.lua`'s hardcoded handler table replaced by a registration API, so the network layer
   holds no knowledge of Loot Council.
3. `Utils.lua` split along its three real responsibilities (UI toolkit, gear scanner, generic
   helpers) instead of holding all three.
4. Per-addon version handshake on the wire, so a later split needs no protocol change.
5. A verification harness that can catch refactor damage without entering the game.

### Non-goals

- No second addon, no second `.toc`, no second CurseForge project. **One addon throughout.**
- No SavedVariables migration. Every saved key keeps its name and meaning.
- No feature work, no behaviour change beyond the handshake format.
- No changes to `BuffChecker.lua`, `Invite.lua`, `RaidleadBar.lua`, `AutoLog.lua`,
  `GroupLogic.lua`, `Profiles.lua` or `Droptimizer.lua` beyond rewriting call sites and moving the
  message handlers those files own.

---

## 3. Architecture

### 3.1 File tree after Stage 0

```
KeineAhnungRaidTools/
  Libs/
    LibStub/LibStub.lua
    KAUtil-1.0/KAUtil-1.0.lua      ~120 lines, no dependencies
    KAGS-1.0/KAGS-1.0.lua          ~330 lines, gear/enchant scanning
    KASC-1.0/KASC-1.0.lua          ~430 lines, networking + identity
    KAUI-1.0/KAUI-1.0.lua          ~780 lines, widget toolkit
  Utils.lua                        1473 -> ~250 lines
  Identity.lua                     removed, moves wholly into KASC
  KARTSync.lua                     removed, transport into KASC, handlers to their owners
  <every other file stays where it is>
```

### 3.2 Dependency graph

```
KAUtil  <--  KAGS  <--  KASC
   ^                      ^
   |                      |
  KAUI                    |
   ^                      |
   +------- KART ---------+
```

Strictly acyclic. No library may reference `KART.*`; this is enforced mechanically (see §7.1).

### 3.3 Vendoring LibStub fixes a latent bug

`MainFrame.lua:3` calls `LibStub("LibSharedMedia-3.0", true)` unguarded. If no other addon supplies
the `LibStub` global, that is a load error, not a `nil` — the second argument only suppresses a
missing *library*, not a missing LibStub. The addon therefore depends today on NSRT or some other
addon providing LibStub. Vendoring it into `Libs/LibStub/` removes that unstated dependency.

### 3.4 Module contents

**KAUtil-1.0** — `TrimString`, `CaseFold`, `SplitString`, `IsRealItemLink`, `GetItemString`,
`IsFullNameInGroup` (with its `CanonRealm` helper), `EachGroupUnit`, `HasGroupPermissions`,
`DeepCopy`, `MergeDefaults`.

These are used by all three future sides (KART, KALC, and KASC itself). Without a shared home the
rule "no library reaches into `KART.*`" cannot be satisfied without duplicating
`IsFullNameInGroup` — which is the function carrying the network security gate, and therefore the
one function that must have exactly one definition.

**KAGS-1.0** — the hidden scanning tooltip, the `GOOD_ENCHANTS` tables and `IsGoodEnchant`,
`SlotNeedsOil`, `CountMissingGear`, `GetOwnEnchantIDs`, `SerializeOwnEnchantIDs`.

The diagnostic printers `PrintEnchantDump`, `StartEnchantScan` and `PrintEnchantScan` stay in
KART: the library supplies data, the addon prints it. This also keeps every user-visible string
out of the library.

A separate library rather than folding into KASC, because `docs/REVIEW-DECISIONS.md` records the
enchant lists as a deliberate per-patch maintenance item with its own churn rate. An enchant table
update should not bump the networking library's version.

**KASC-1.0** — the `KART` addon-message prefix, `Send`, `DefaultChannel`, the handler registry and
dispatcher, the group gate, all of `Identity.lua` **including the NSRT nickname resolution**, the
version handshake, and the four data responders (`REQ_OIL`, `REQ_ILVL`, `REQ_GEAR`, `REQ_ENCH`).

**KAUI-1.0** — every widget factory (`CreateModernButton`, `CreateCard`, `CreateSettingsCheckbox`,
`CreateSettingsSlider`, `CreateStyledEditBox`, `CreateTabButton`, `CreateHeaderLine`,
`CreateHeaderIconButton`, `ShowInputDialog`, `RegisterStaticPopup`, `OpenColorPicker`), the theme
maths (`Lighten`, `Darken`, `AccentColor`, `GetRowStripeColor`), strata management
(`GetWindowStrata`, `GetDialogStrata`, `RegisterStrataFrame`, `ApplyFrameStrata`),
`ApplyPopupArtwork`, `ApplyRoundedMask`, `StripScrollbarTextures`, `AddShowFade`,
`CreateGradientOverlay`, `SetGradientOverlayColor`, `GetFontPath`, `IsSavedPosOnScreen`, all
eleven widget registries (`Utils.lua:5-13`, `141-142`), the locale-refresher registry, and
`ApplyStyle`.

**Stays in KART** — `MainFrame.lua` in full (window, tabs, scroll frame, `ShowTab`,
`CreateTabTitle`, `UpdateScrollRange`), `UpdateMinimapButton` (LibDBIcon, fixed addon name),
`BuildSearchIndex` (tab mapping is addon-specific), `KART.Defaults`, the enchant-scan diagnostics,
and the KART-specific remainder of `UpdateStyles`.

---

## 4. KASC contract

### 4.1 The governing rule

**KASC owns the answering side; consumers own the receiving side.**

A client running only KALC must still answer `REQ_GEAR`, so the responder belongs in the library.
Filling `KART.GearCache` and refreshing the Buff Checker only matters to whoever renders it, so
that belongs in `BuffChecker.lua`. This asymmetry is the entire reason KASC exists as a separate
library rather than as a KART module.

### 4.2 Initialisation

```lua
local KASC = LibStub("KASC-1.0")

KASC:AttachCache(KART_PlayerCache)
KASC:RegisterAddon("KART", KART.Version)
KASC:RegisterCapability("LC", function() return KART_Settings.lcModuleEnabled ~= false end)
```

`AttachCache` keeps a list of tables. `RememberPlayer` writes to **all** attached tables; identity
lookups scan **all** of them. After a split each addon attaches its own SavedVariable and the two
stay consistent automatically, with no ownership question. Roughly 10 lines.

`RegisterAddon` must be called from `Core.lua`, because `KART.Version` is only assigned at
`Core.lua:3` and `Core.lua` is the last file in the `.toc`.

### 4.3 Handler registry

```lua
KASC:RegisterMessage("LC_VOTE", {
    payload = true,
    group   = true,
    enabled = function() return KART_Settings.lcModuleEnabled ~= false end,
}, function(payload, ctx) LC.Vote.HandleVote(payload, ctx:Key()) end)
```

| Option | Replaces | Meaning |
|---|---|---|
| `payload = true` | `PREFIX_HANDLERS` | token followed by `:rest`; the handler parses its own payload |
| `payload = false` | `EXACT_HANDLERS` | the token must be the entire message |
| `group = true` | `entry.group` | sender must pass `IsFullNameInGroup` |
| `enabled = fn` | `entry.lc` | arbitrary predicate — this is what removes all Loot Council knowledge from the library |

`ctx = { sender, shortName, channel }` plus a `ctx:Key()` method. Identity resolution stays **lazy**:
today only the handlers that need a key call `SenderKey(ctx)`, and resolving eagerly would scan up
to 40 units for every message including those that never use it.

Handler registration happens at file load time, before `ADDON_LOADED` registers the prefix. The
registry is a plain table, so this ordering is safe.

### 4.4 Message ownership after the move

| Message | New owner |
|---|---|
| `REQ_OIL` / `REQ_ILVL` / `REQ_GEAR` / `REQ_ENCH` — **answering** | KASC (calls KAGS) |
| `OIL` / `ILVL` / `GEAR` / `ENCH` — **receiving and caching** | `BuffChecker.lua` |
| `RC_REASON` | `Core.lua` — it owns the cache lifecycle (`Core.lua:310` wipes it on ready check) and the sending dialog (`Core.lua:512`); `BuffChecker.lua:978` only reads it |
| `REQ_EQUIP` / `EQUIP` | `LootCouncilPanel.lua` — `Council.GetOwnEquippedLink` is defined there at line 117 |
| the 14 `LC_*` messages | the owning LootCouncil file |
| `LC_HIST_REQ` / `LC_HIST_ENTRY` | `LootHistory.lua` |
| handshake | KASC |

Afterwards KASC contains **zero** references to `KART.LC`, `KART.LH` or `KART.BuffCheckFrame`;
`KARTSync.lua` has 23 today.

Side effect: `LootHistory.lua` currently has to load after the LootCouncil files because their
handlers reference `KART.LH`. With self-registration that ordering constraint disappears.

### 4.5 Wire format — hard cutover at v3.0.0

```
KA_HELLO_REQ                              -- replaces REQ_VERSION
KA_HELLO:KART=3.0.0+LC                    -- today
KA_HELLO:KART=3.1.0,KALC=1.0.0+LC         -- after a later split
```

Grammar: entries separated by `,`, each `name=version` with optional `+capability` suffixes.

**Name, version and capability are restricted to `[%w%.%-_]`; any entry containing anything else is
dropped.** This replaces the current `ver:gsub("|", "||")` defence at `KARTSync.lua:83` with a
whitelist — a `|` cannot enter the string at all, rather than being neutralised after the fact.
The version string is printed to chat and rendered in the council panel, so this matters.

2.9 clients are deliberately not accommodated. `VERSION` and `REQ_VERSION` are removed outright.
The raid updates together; the two external CurseForge users on an old version will simply not
appear in the version check until they update.

Library versions are **not** put on the wire. Nothing branches on them, so it would be speculative.

### 4.6 What KASC deliberately does not do

The update warning stays with the consumer. KASC only fires:

```lua
KASC:OnPeer(function(shortName, fullName, addons) ... end)
-- addons = { KART = { version = "3.0.0", caps = { LC = true } } }
```

This moves the `UpdateWarned` latch, the plausibility clamp (`nMaj <= oMaj + 1`) and the
`VERSION_CHECK_RES` print into `Core.lua`. All three are locale-dependent and none of them is a
networking concern.

**Consequence: none of the four libraries contains a single user-visible string, so none of them
needs locale handling.**

---

## 5. KAUI contract

### 5.1 Namespaces

KAUI is the only one of the four libraries with per-consumer state: the eleven widget registries.
If those stayed global, then after a split an `ApplyStyle` from KART would restyle KALC's widgets,
and a language switch in KART would fire KALC's locale refreshers.

```lua
local UI = LibStub("KAUI-1.0"):NewNamespace("KART")
KART.UI = UI
```

Each namespace owns its own registries and its own `ApplyStyle`. Shared code, separate state.

The added cost today is effectively nil: all 276 call sites change anyway, from
`KART.CreateModernButton(...)` to `KART.UI:CreateModernButton(...)`.

**No alias layer.** A shim such as `KART.CreateModernButton = function(...) return UI:... end`
would defeat the boundary the extraction exists to create, and would make a forgotten call site
invisible to the moved-symbol gate.

### 5.2 Settings binding is per call, not global

Two KAUI functions read and write `KART_Settings` directly today: `CreateSettingsCheckbox` via its
`settingKey` parameter, and `OpenColorPicker` via `rKey`/`gKey`/`bKey` (`Utils.lua:941-964`). Both
then call `KART.UpdateStyles()`.

A globally injected store (`KAUI:SetStore(KART_Settings)`) is ruled out: after a split there would
be two stores and one setter. The store moves into the call instead.

```lua
UI:CreateSettingsCheckbox(parent, {
    name    = "KART_LCAutoPass",
    label   = L.LC_AUTOPASS,
    store   = KART_Settings,
    key     = "lcAutoPass",
    y       = -40,
    onChanged = function() ... end,
    tooltip = L.DESC_LC_AUTOPASS,
})
```

The current seven-positional-parameter signature becomes an options table. With three of the seven
optional, this is not cosmetic — it is where a mis-shifted argument would otherwise pass silently.

`KART.UpdateStyles` is no longer called from inside the library. Checkboxes and sliders use
`onChanged`; the colour picker takes an `onApply` callback from its caller.

### 5.3 ApplyStyle

```lua
function KART.UpdateStyles()
    if not KART_Settings or not KART.MainFrame then return end
    KART.UI:ApplyStyle({
        font        = KART.UI:GetFontPath(KART_Settings.fontName),
        menuSize    = KART_Settings.menuFontSize,
        contentSize = KART_Settings.contentFontSize,
        strata      = KART_Settings.frameStrata,
        accent      = { KART_Settings.accentR/100, KART_Settings.accentG/100, KART_Settings.accentB/100 },
    })
    -- KART-specific remainder only: MainFrame alpha and scale, the LibDBIcon tint,
    -- KART.LC.RelayoutRaidBox, and the Loot History window's own title font.
end
```

`ApplyStyle` runs the registry loops that `Core.lua:396-434` runs today. Everything else stays in
`KART.UpdateStyles`.

### 5.4 Accent texture registry

`Core.lua:448-452` lists five scroll thumbs by name — `ScrollThumb`, `BuffScrollThumb`,
`WUPasteScrollThumb`, `LHScrollThumb`, `LHExportScrollThumb` — each with an identical line. A new
thumb must be added there by hand, and a forgotten one only shows up as "one scrollbar has the
wrong colour".

`UI:RegisterAccentTexture(tex, alpha)` at the creation site replaces this, and `ApplyStyle` tints
them in the same loop as `SliderThumbs` and `AccentLines`. Five special cases removed, future ones
covered automatically.

### 5.5 What stays in KART

`BuildSearchIndex` reads the labels through `UI:GetLabels()` but keeps the tab mapping
(`Utils.lua:1434-1441`) — which panels exist is addon-specific. `UpdateMinimapButton` and the
minimap icon tint stay too; both are bound to LibDBIcon and the literal addon name.

The label registry must preserve insertion order: `BuildSearchIndex` walks it in order, and the
order determines how search results are sorted.

---

## 6. Call-site volume

| Library | Call sites to rewrite |
|---|---|
| KAUI | 276 |
| KAUtil | 129 |
| KAGS | 22 |
| `DynamicLabels` inserts | 46 |

Roughly 470 mechanical rewrites. All of them are forced by the move itself — none is optional
churn.

---

## 7. Verification

Luacheck alone does **not** catch a forgotten `KART.CreateModernButton(...)` after the move: it
checks undefined *globals*, and `KART` remains a defined global. Field access on a known table is
not validated. Three separate layers are therefore needed.

### 7.1 Moved-symbol gate — catches the forgotten call site

A list of the ~55 moved symbol names plus a CI step asserting that none of them appears anywhere
as `KART.<name>`.

```
tests/moved-symbols.txt   -- CreateModernButton, TrimString, SlotNeedsOil, ...
tests/check-moved.sh      -- must produce no matches
```

The same script, inverted, enforces the other direction: `Libs/` must contain no `KART.` at all.

Both run locally in about a second. During the rewrite the match count is the primary progress
indicator: it has to reach zero.

### 7.2 Luacheck — catches typos, dead locals, shadowing

`.luacheckrc` declaring the WoW API as `read_globals` and the SavedVariables (`KART_Settings`,
`KART_LootHistory`, `KART_LCOfficerNotes`, `KART_WoWUtilsCache`, `KART_Profiles`,
`KART_PlayerCache`, `KART_LCTrades`) as writable globals. Its main value during this work is
flagging the orphaned locals and unused upvalues that cutting a function out reliably leaves
behind.

### 7.3 Offline harness — catches behaviour change

Pure logic only, no frames.

| File | Coverage |
|---|---|
| `tests/test_kautil.lua` | `TrimString`, `CaseFold` (including umlauts), `SplitString`, `IsRealItemLink`, `GetItemString`, `IsFullNameInGroup` (realm canonicalisation), `DeepCopy`, `MergeDefaults` (nested) |
| `tests/test_identity.lua` | all four `ResolvePlayer` branches (unit token, live name, cache, pending), **NSRT nickname resolution against a stubbed `NSAPI`**, `IsResolvedKey`, `AttachCache` with two tables |
| `tests/test_sync.lua` | exact vs payload dispatch, group gate, `enabled` gate, `ctx:Key()` laziness, `IsSlotList` and `ParseOilField` validation, **handshake serialise and parse including hostile input** (`\|cff00ff00`, doubled commas, empty version, oversized string) |
| `tests/test_kags.lua` | `SlotNeedsOil`, `IsGoodEnchant`, the serialisation format of `SerializeOwnEnchantIDs` |

`tests/wow_stubs.lua` provides `UnitName`, `UnitGUID`, `UnitExists`, `IsInRaid`, `IsInGroup`,
`GetNumGroupMembers`, `C_ChatInfo`, `GetTime`, `time`, `Ambiguate`, a no-op `CreateFrame`, and a
settable fake group roster.

This gives NSRT nickname handling its first regression test; today it is only verifiable in a raid.

Out of scope for the harness: all of KAUI (frames), `CountMissingGear` (depends on the scanning
tooltip and `C_Item.GetItemStats`), and anything visual.

### 7.4 Toolchain

**LuaJIT locally**, because it is 5.1-compatible and therefore matches WoW's semantics. The
difference is not academic: `tostring(3.0)` yields `"3"` under 5.1 and `"3.0"` under the 5.4
currently installed, and values like `tostring(mhID)` in the OIL responder go straight onto the
wire. Luacheck via luarocks.

CI installs `lua5.1` and `luacheck` and runs all three layers on `push` and `pull_request`. The
existing tag-triggered release workflow is untouched.

---

## 8. Implementation order

One release, seven separately committed steps, so that `git bisect` can attribute a later raid bug.

| # | Step | Checkpoint |
|---|---|---|
| 1 | Infrastructure: vendor LibStub, `.luacheckrc`, `tests/`, CI workflow, moved-symbol gate | CI green on **unchanged** code — proves the checks themselves work |
| 2 | KAUtil-1.0 (129 sites) | gate + tests + `/reload`, open every tab |
| 3 | KAGS-1.0 (22 sites) | gate + tests + Buff Checker advanced view unchanged |
| 4 | KAUI-1.0 (276 sites, namespace, options tables, accent registry) | gate + full UI checklist |
| 5 | KASC-1.0: transport and registry, **wire format unchanged** | gate + tests + raid: vote, trade, history sync, buff data |
| 6 | Handshake switched to `KA_HELLO` | tests + two clients simultaneously |
| 7 | `.toc`, changelogs ×4, exclude `tests/` and `.luacheckrc` from `.pkgmeta` and the release rsync | release zip contains no test files |

Steps 5 and 6 are deliberately separate: the registry rewrite and the protocol change are distinct
failure modes and both only surface in a raid.

Ordering rationale: KAUtil first because KAGS and KASC build on it; KAUI inserted before KASC
because it is verifiable visually without a raid.

---

## 9. New `.toc` load order

```
Libs\LibStub\LibStub.lua
Libs\KAUtil-1.0\KAUtil-1.0.lua
Libs\KAGS-1.0\KAGS-1.0.lua
Libs\KASC-1.0\KASC-1.0.lua
Libs\KAUI-1.0\KAUI-1.0.lua

Locales\enUS.lua
Locales\deDE.lua

Utils.lua
MainFrame.lua
GroupLogic.lua
RaidleadBar.lua
Profiles.lua
BuffChecker.lua
LootCouncil.lua
LootCouncilOfficerNotes.lua
LootCouncilVote.lua
LootCouncilTrade.lua
LootCouncilPanel.lua
LootCouncilSettings.lua
Droptimizer.lua
LootHistory.lua
Invite.lua
AutoLog.lua
Core.lua
```

`Identity.lua` and `KARTSync.lua` are removed.

---

## 10. Risks

**`KART.Version` ordering.** Assigned at `Core.lua:3`, and `Core.lua` loads last. `RegisterAddon`
must therefore live in `Core.lua`.

**`local L = KART.L` captured at load time.** Several files capture the table reference when they
load; `Core.lua:196-200` wipes and refills it later, which is why the reference must never be
replaced. No moved code may introduce a `KART.L = {...}`. That the libraries are string-free
removes this hazard from the library boundary entirely.

**Load-time panel construction.** `LootCouncilSettings.lua:495` builds the settings panel at load
time once `KART.LootCouncilPanel` exists (created in `MainFrame.lua:161`), and `Droptimizer.lua:219`
then anchors into `KART.LC.SettingsCard`. This chain stays exactly as it is.

**Label ordering.** The namespace label registry must preserve insertion order or search result
ordering changes.

**No data migration.** All SavedVariables and all settings keys keep their names. Upgrading from
2.9 to 3.0 preserves loot history, officer notes, profiles and outstanding trades. This is a hard
requirement, not an expected side effect.

---

## 11. Acceptance criteria

- Moved-symbol gate: **0 matches**
- `Libs/` contains **0** occurrences of `KART.`
- Luacheck: 0 warnings, or a documented exception in `.luacheckrc`
- Offline tests green under LuaJIT
- In-game checklist complete
- Raid test passed

---

## 12. In-game checklist

**UI** — open all six tabs · change font, accent colour, scale, frame strata and background opacity
and verify each takes effect in the main window **and in popups** · settings search finds a label
and jumps to the right tab · switch language and ReloadUI · switch profile · minimap button and
addon compartment

**Loot Council** — start a session · vote popup · council panel with equipped comparison and the
Droptimizer gain column · trade reminder · winner frame · Loot History including the export dialog

**Network** — Buff Checker advanced view shows enchants, gems, oil, item level and repair for every
raider · version check lists everyone · ready-check reason arrives

**NSRT** — the council panel shows nicknames · auto-promote and lootmaster lists match on nickname
rather than character name

---

## 13. Decision record

| Decision | Chosen | Rationale |
|---|---|---|
| Depth | Full split readiness | Chosen over hygiene-only; the seams must survive a later split without rework |
| Boundary mechanism | LibStub libraries in `Libs/` | The split becomes "copy the folder"; the boundary is enforced mechanically, not by discipline |
| Library granularity | Three, plus KAUtil | Enchant tables have their own churn rate and should not bump the networking library |
| KAUtil as a fourth library | Yes | Without it the no-upward-reference rule forces duplicating `IsFullNameInGroup`, which carries the security gate |
| Wire compatibility | Hard cutover, drop 2.9 support | The raid updates together; ~99% self-use |
| Verification | Luacheck + offline harness + moved-symbol gate | Luacheck alone cannot see field access on a known table |
| Toolchain | LuaJIT locally | 5.1 semantics; 5.4 number-to-string differences would reach the wire |
| Delivery | One v3.0.0 release, seven commits | Bisectable without three release cycles |
| Accent texture registry | Included | Removes the last five KART-specific names from the styling path |
| KAUI alias layer | Rejected | Would defeat the boundary and hide forgotten call sites from the gate |
