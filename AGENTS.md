# Project Conventions

Changelog, locales, Lua 5.1, SavedVariables: `CODING_STANDARDS.md`.

## Domain

- **Manifest:** `docs/MANIFEST.md` — companion must not hinder, abort, or break RCLootCouncil's loot flow. "gegen das Manifest getestet" before calling a change done. The suite is the floor.
- **Ownership:** `docs/OWNERSHIP.md` — who owns settings vs who hands out loot. Touch that document first.
- **Settled:** `docs/REVIEW-DECISIONS.md` and `docs/BACKLOG.md` headings (`FIXED` / `NO DEFECT`) before raising a concern.
- Grill / glossary layout: `docs/agents/domain.md`.

## Navigation

- **Banners:** `grep -n '^-- =====' -A1 <file>`. Never read a large file whole. `LootCouncil.lua` (~6.8k, 27 banners) first.
- **Comm:** `Libs/KASC-1.0` (`KASC:Send`) over AceComm-3.0. There is no `KARTSync.lua`.
- **SavedVariables names:** the `.toc`. Shape rules in `CODING_STANDARDS.md`.

## API sources

- **ketho.wow-api** (12.0.1, client 12.1): `C:\Users\max\.vscode\extensions\ketho.wow-api-0.22.3\Annotations`. Addon targets Midnight (12.x). Ground API claims here or in FrameXML; do not assert from memory.
- **FrameXML mirror:** `E:\Projects\.refs\wow-ui-source` (sibling of this repo). Not auto-loaded. Secondary to ketho and the `gh api repos/Gethe/wow-ui-source` fetches in `docs/BACKLOG-12.1.md`; the mirror may lag the target patch.

## Live client

- **Crash / OOM / client dump:** `E:\World of Warcraft\_retail_\Errors\` first, then `_retail_\Logs\`.
- **Neighbour addons** (Northern Sky, WowUtils, RCLootCouncil): `E:\World of Warcraft\_retail_\Interface\AddOns\`.

## Raid chrome

Three UIs. Do not mix them up.

- **KART raidlead bar** — small 2-row bar (marks, world markers, ready check, buff, pull, tools). `RaidleadBar.lua`.
- **CompactRaidFrameManager** — Blizzard raid control. Optional hide: `hideBlizzardRaidManager` while the KART bar is shown. Default off.
- **Northern Sky** — large vertical NS panel. Unique NS content. Do not hide NS from KART; NS has its own QoL toggle under `/ns`.

## Agent skills

### Issue tracker

GitHub Issues on Kandera/KeineAhnungRaidTools. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles, matching label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.
