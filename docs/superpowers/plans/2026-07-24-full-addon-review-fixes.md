# Full Addon Review — Findings & Decisions (2026-07-24)

Complete review of the whole addon (20 Lua files, ~10k lines) after the feature/bugfix wave.
Focus: code defects, cross-module wiring, DE/EN **client-locale** correctness (Blizzard APIs
return localized strings on a German client), and translation completeness.

Baseline verified clean: `enUS.lua`/`deDE.lua` have identical keys (311 each); all `KART.*`
cross-module calls resolve; addon-message handlers match; no raw `SendAddonMessage` outside
`KARTSync.lua`; language-apply logic (Auto → GetLocale, EN base + DE overlay, other clients fall
back to English) is correct.

## Fixed

| # | File | Fix |
|---|------|-----|
| 1 | BuffChecker.lua | Food fallback matched `"Satt"`, which never matches the German well-fed buff "Gut ges**ä**ttigt" → changed to `"gesättigt"`. DE client no longer false-flags food as missing. |
| 2 | Identity.lua | `FindUnitForName` / `ResolvePlayer` used ASCII-only `:lower()`, so umlaut names (Ö/Ä/Ü) never resolved → switched to `KART.CaseFold`. Affects council/lootmaster/auto-promote resolution. |
| 3 | Utils.lua | `GetNickname` returned `nick:lower()` → `KART.CaseFold(nick)` so NSRT nicknames with umlauts fold consistently with the lists they match against. |
| 3 | GroupLogic.lua | Invite-keyword / promote-name matching folded with `:lower()`; changed to `KART.CaseFold` on both the table build and the lookups so umlaut names/keywords match the folded nickname side. |
| 4 | MainFrame.lua | Settings search folded query + entries with `:lower()` → `KART.CaseFold` (umlaut queries now match). |
| 5 | LootHistory.lua | JSON export `equipLoc` used `_G[token]` = client-locale slot name → added `INVTYPE_EN` map so the export stays English-canonical (matches the file's difficulty-normalization design). |
| 11 | Utils.lua / Profiles.lua / MainFrame.lua | Input dialog + profile confirm popups used Blizzard `ACCEPT/CANCEL/YES/NO` globals (client locale). Added `BTN_ACCEPT/BTN_CANCEL/BTN_YES/BTN_NO` locale keys and set button captions at show-time so they follow the KART language. |
| 12 | Invite.lua | Tooltip `"EncounterID: "` routed through new `WU_ENCOUNTER_ID` key. |
| 14 | GroupLogic.lua | `inviteKeywords`/`promoteNames` `:lower()` had no nil-guard → `... or ""`. |
| 15 | LootCouncilTrade.lua | `HandleResult` rebuilt the item link only when `not itemLink`; a truthy `"???"` placeholder slipped through into history/popup → rebuild also when `not IsRealItemLink`. |
| 17 | LootCouncilPanel.lua | Straw-poll fill bar denominator was whole-raid `numMem`; only council members vote → now council size (`LC.CouncilNamesTable` count). Removed now-unused `numMem`. |
| 18 | Utils.lua | Slider whose saved value == min never fired `OnValueChanged`, leaving `valueText` blank → added `OnShow` hook to populate it (fixes AutoLog min-key slider on fresh install). |
| 19 | Core.lua | `buffCheckAlpha or 95` inconsistent with `Defaults.buffCheckAlpha = 90` → `or 90`. |
| 20 | KARTSync.lua | `LC_HIST_REQ`/`LC_HIST_ENTRY` called `KART.LH` under a gate that only checks `KART.LC` → added `if KART.LH` guard. |
| 21 | Profiles.lua | `LoadProfile` didn't apply a profile's stored language; the language picker itself reloads to switch, so `LoadProfile` now `ReloadUI()`s when the language differs. |
| 22 | Droptimizer.lua | `RefreshStatusLabel` ignored `schemaVersion`; a mismatch leaves the index empty but the label claimed N players → schema mismatch now shows "never synced". |
| 23 | LootCouncil.lua | Manual-roll trade-timeout clock started at assign time; now stamped at roll creation (`LC.rollLootedAt`), the earliest moment we control for a manually-added item. |
| 24 | LootHistory.lua | Reassignment de-dup matched by exact link equality; a bare `item:` string vs a full link could duplicate → now matches by locale-independent `GetItemString`. |

## Not a defect (verified, no change)

- **#16** Config-payload `:` in button/council labels: already defended — `StripColons` sanitizes all
  three edit boxes at input (`LootCouncilSettings.lua:33,185,209,264`), so colons never reach the
  `([^:]*)` parse. False alarm.

## Intentional — kept as-is (do not re-flag in future reviews)

Marked with `-- intentional: … (review 2026-07-24)` inline at each site.

- **#6** `LootCouncilPanel.lua` — "Item Level" prefix on the rolled-item ilvl label.
- **#7** `BuffChecker.lua` — "Rdy" column header (short abbreviation).
- **#8** `BuffChecker.lua` — German preview sample reasons ("Katze brennt", …) — settings-preview
  sample data only, never shown in a live ready-check.
- **#9** `BuffChecker.lua` — "?"/"OK" gear-check status glyphs.
- **#10** `LootCouncilVote.lua:85,412,659` — `"s"` seconds suffix on the vote timer. Works for DE
  and EN alike; left un-localized. (Recorded here only — no inline marker, to avoid noise on three
  identical lines.)
- **#13** `Invite.lua` — invitelist capture `[^;]+` is correct for the real WoWUtils export.
  Verified against a real multi-boss export: each `invitelist:` value ends with a trailing `;`
  (`...Name-Realm;`), so `[^;]+` stops at that semicolon and never bleeds into the next
  `EncounterID:` block; `%s+` absorbs the blank line between `Name:` and `invitelist:`. Umlaut /
  apostrophe player names (Shihoín, Belo'ren) are fine — not `;`.
