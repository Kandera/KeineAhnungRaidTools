# Auto Combat Log — Design

Date: 2026-07-18
Status: Approved

## Goal

Automatically start WoW combat logging (`LoggingCombat`) when the player enters selected
content, and stop it again when leaving — configurable in the Automation tab: per content
type, with a difficulty filter for raids and a minimum keystone level for Mythic+.

## Scope

- **Raid** — per-difficulty toggles: LFR, Normal, Heroic, Mythic.
- **Mythic+** — single toggle plus "minimum keystone level" slider (2–20).
- **Dungeons** — single on/off toggle covering Normal / Heroic / Mythic 0 (no per-difficulty split).
- **Delves** — single on/off toggle (no tier filter).
- Advanced Combat Logging: the addon sets the `advancedCombatLogging` CVar to 1 whenever it
  starts logging (required for usable Warcraft Logs uploads).

Out of scope: log upload, per-boss logic, Timewalking, follower dungeons, scenario content
other than Delves.

## Detection

New module `AutoLog.lua` exposing `KART.AutoLog.Evaluate()`, driven by two events routed
through the existing central dispatcher in `Core.lua`:

- `PLAYER_ENTERING_WORLD` (already registered) — covers zoning in/out, reload, reconnect.
- `CHALLENGE_MODE_START` (newly registered) — a M+ dungeon is entered at difficultyID 23
  (Mythic); only when the key starts does the difficulty switch to 8, so re-evaluation on
  this event is required to catch the keystone level.

Content matching via `GetInstanceInfo()` difficultyID:

| Content | difficultyID | Setting key(s) |
|---|---|---|
| Raid LFR | 17 | `autoLogRaidLFR` |
| Raid Normal | 14 | `autoLogRaidNormal` |
| Raid Heroic | 15 | `autoLogRaidHeroic` |
| Raid Mythic | 16 | `autoLogRaidMythic` |
| Mythic+ | 8 | `autoLogMythicPlus` + `autoLogMinKey` |
| Dungeon | 1 / 2 / 23 | `autoLogDungeons` |
| Delve | 208 | `autoLogDelves` |

Keystone level via `C_ChallengeMode.GetActiveKeystoneInfo()` — valid both on
`CHALLENGE_MODE_START` and on `PLAYER_ENTERING_WORLD` mid-run (reconnect/reload). Log only
when level ≥ `autoLogMinKey`.

## Start/stop rules (ownership model)

Persistent flag `KART_Settings.autoLogOwned` (not shown in UI) records whether the addon
started the current logging session, surviving `/reload`.

On every evaluation:

1. Content matches, logging off → `SetCVar("advancedCombatLogging", 1)`,
   `LoggingCombat(true)`, `autoLogOwned = true`, chat message with content description.
2. Content matches, logging already on → leave as is (if not owned, ownership stays with
   the player).
3. No match, logging on, `autoLogOwned` → `LoggingCombat(false)`, `autoLogOwned = false`,
   chat message.
4. No match, logging on, not owned → never touch manually started logging.

Master toggle off (checkbox callback) → same as rule 3 if owned.
Master toggle `autoLogEnabled = false` short-circuits matching entirely.

## UI (Automation tab, `KART.PromotePanel`)

New card (existing `KART.CreateCard` pattern, 290 wide) below the current checkboxes,
with a FontString title "Auto Combat Log" above it (same pattern as Raidlead/BuffChecker
cards). Contents top-to-bottom, all via existing factories:

- Master checkbox `autoLogEnabled` (callback: evaluate; stop owned logging when disabled)
- 4 raid difficulty checkboxes (LFR / Normal / Heroic / Mythic)
- Mythic+ checkbox
- Minimum keystone level slider (2–20), `autoLogMinKey`
- Dungeons checkbox
- Delves checkbox

Checkbox/slider callbacks re-run `Evaluate()` so filter changes while inside an instance
take effect immediately. New widgets registered in the `settingsMap` init block in
`Core.lua` (login state restore); defaults added to `KART.Defaults` so the existing
reset-to-defaults path covers them.

Defaults: master off; when enabled, sensible presets: Heroic + Mythic raid on, M+ on with
min key 2, LFR/Normal/Dungeons/Delves off.

## Files touched

- `AutoLog.lua` (new) — evaluation + start/stop logic
- `KeineAhnungRaidTools.toc` — add AutoLog.lua
- `Core.lua` — register `CHALLENGE_MODE_START`, route both events, extend settingsMap
- `MainFrame.lua` — Automation tab card + widgets
- `Utils.lua` — defaults
- `Locales/enUS.lua`, `Locales/deDE.lua` — labels, tooltips, chat messages
- `CHANGELOG.md` / `CHANGELOG-de.md` — entry

## Error handling / edge cases

- Reload mid-instance: `autoLogOwned` persists → ownership retained, stop-on-exit works.
- Logging already running manually at zone-in: rule 2/4 — never claimed, never stopped.
- Key completes: difficulty stays 8 until zone-out → logging continues, stops on exit. Correct.
- Delve/dungeon IDs missing on future patch changes: unmatched IDs simply never log.

## Testing

No automated test harness exists for this WoW addon (in-game API). Verification:
`luacheck`-style syntax pass (`lua -p`-equivalent not available; rely on WoW load) plus
manual in-game checklist documented in the plan.
