# Auto Combat Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-start/stop WoW combat logging based on content filters (raid difficulty, M+ min key level, dungeons, delves), configured in the Automation tab.

**Architecture:** New `AutoLog.lua` module holds all matching/start/stop logic behind `KART.AutoLog.Evaluate()`. The existing central event dispatcher in `Core.lua` routes `PLAYER_ENTERING_WORLD` and the newly registered `CHALLENGE_MODE_START` to it. UI is one new card in the Automation tab (`KART.PromotePanel`) built from the existing checkbox/slider/card factories.

**Tech Stack:** WoW Lua addon (Interface 12.x), no external libs, no automated test harness — verification is a manual in-game checklist.

## Global Constraints

- Code comments in English (project CLAUDE.md).
- `Locales/deDE.lua` string values German, comments English.
- Changelog entries: bold lead + 1–2 sentences; update `CHANGELOG.md` first, mirror to `CHANGELOG-de.md` same turn.
- All toggles default **off** (user decision); `autoLogMinKey` default 2.
- Never touch logging the addon didn't start (`KART_Settings.autoLogOwned` ownership flag, persisted).

---

### Task 1: Defaults + Locales

**Files:**
- Modify: `Utils.lua:53` (KART.Defaults table, before `frameStrata`)
- Modify: `Locales/enUS.lua` (Settings/Checkboxes block ~line 52, Tooltips block ~line 116)
- Modify: `Locales/deDE.lua` (equivalent blocks)

**Interfaces:**
- Produces: settings keys `autoLogEnabled`, `autoLogRaidLFR`, `autoLogRaidNormal`, `autoLogRaidHeroic`, `autoLogRaidMythic`, `autoLogMythicPlus`, `autoLogMinKey`, `autoLogDungeons`, `autoLogDelves`, `autoLogOwned`; locale keys `LABEL_AUTOLOG`, `SET_AL_*`, `DESC_AL_*`, `MSG_AL_STARTED`, `MSG_AL_STOPPED`.

- [ ] **Step 1: Add defaults to `KART.Defaults` in Utils.lua** (after `lcMinQuality = 4,`):

```lua
    autoLogEnabled = false,
    autoLogRaidLFR = false,
    autoLogRaidNormal = false,
    autoLogRaidHeroic = false,
    autoLogRaidMythic = false,
    autoLogMythicPlus = false,
    autoLogMinKey = 2,
    autoLogDungeons = false,
    autoLogDelves = false,
    autoLogOwned = false, -- hidden: whether the addon (not the player) started the current combat log
```

- [ ] **Step 2: Add enUS strings** (after `SET_PULL_TIMER` in the Settings block):

```lua
    LABEL_AUTOLOG = "Auto Combat Log",
    SET_AL_ENABLED = "Enable auto combat logging",
    SET_AL_RAID_LFR = "Raid: LFR",
    SET_AL_RAID_NORMAL = "Raid: Normal",
    SET_AL_RAID_HEROIC = "Raid: Heroic",
    SET_AL_RAID_MYTHIC = "Raid: Mythic",
    SET_AL_MPLUS = "Mythic+ Keystone",
    SET_AL_MIN_KEY = "Minimum keystone level",
    SET_AL_DUNGEONS = "Dungeons (Normal/Heroic/Mythic 0)",
    SET_AL_DELVES = "Delves",
```

And in the Tooltips block:

```lua
    DESC_AL_ENABLED = "Automatically starts combat logging when you enter content selected below and stops it when you leave. Logging you started manually via /combatlog is never touched.",
    DESC_AL_MIN_KEY = "Keys below this level are not logged.",
    MSG_AL_STARTED = "Combat logging started (%s).",
    MSG_AL_STOPPED = "Combat logging stopped.",
```

- [ ] **Step 3: Mirror into deDE.lua** (German values, English comments):

```lua
    LABEL_AUTOLOG = "Auto-Combat-Log",
    SET_AL_ENABLED = "Automatisches Combat-Logging aktivieren",
    SET_AL_RAID_LFR = "Raid: LFR",
    SET_AL_RAID_NORMAL = "Raid: Normal",
    SET_AL_RAID_HEROIC = "Raid: Heroisch",
    SET_AL_RAID_MYTHIC = "Raid: Mythisch",
    SET_AL_MPLUS = "Mythisch+ Schlüsselstein",
    SET_AL_MIN_KEY = "Mindest-Keystufe",
    SET_AL_DUNGEONS = "Dungeons (Normal/Heroisch/Mythisch 0)",
    SET_AL_DELVES = "Tiefen",
    DESC_AL_ENABLED = "Startet das Combat-Logging automatisch beim Betreten des unten ausgewählten Contents und stoppt es beim Verlassen. Manuell per /combatlog gestartetes Logging wird nie angefasst.",
    DESC_AL_MIN_KEY = "Keys unterhalb dieser Stufe werden nicht geloggt.",
    MSG_AL_STARTED = "Combat-Logging gestartet (%s).",
    MSG_AL_STOPPED = "Combat-Logging gestoppt.",
```

- [ ] **Step 4: Commit**

```bash
git add Utils.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add auto combat log defaults and locale strings"
```

---

### Task 2: AutoLog.lua module + TOC

**Files:**
- Create: `AutoLog.lua`
- Modify: `KeineAhnungRaidTools.toc:22` (add line before `Core.lua`)

**Interfaces:**
- Consumes: settings keys from Task 1, `KART.L` locale table.
- Produces: `KART.AutoLog.Evaluate()` — no args, no return; safe to call any time (guards nil settings).

- [ ] **Step 1: Create `AutoLog.lua`:**

```lua
local addonName, KART = ...

-- Auto Combat Log: starts/stops LoggingCombat() based on the content filters configured in
-- the Automation tab. Evaluation is event-driven (PLAYER_ENTERING_WORLD, CHALLENGE_MODE_START
-- routed here from Core.lua) plus re-runs from the settings widgets' callbacks.
KART.AutoLog = {}

-- Maps GetInstanceInfo() difficultyIDs to the settings toggle that must be on for that
-- content. Mythic Keystone runs are detected via the active keystone instead (see below),
-- because the key level filter needs C_ChallengeMode data, not just the difficultyID.
local DIFFICULTY_TOGGLES = {
    [17]  = "autoLogRaidLFR",
    [14]  = "autoLogRaidNormal",
    [15]  = "autoLogRaidHeroic",
    [16]  = "autoLogRaidMythic",
    [1]   = "autoLogDungeons", -- Normal
    [2]   = "autoLogDungeons", -- Heroic
    [23]  = "autoLogDungeons", -- Mythic 0
    [208] = "autoLogDelves",
}

-- Returns match, description. An active keystone run is checked first: on
-- CHALLENGE_MODE_START the difficultyID may not have flipped to 8 (Mythic Keystone) yet,
-- but GetActiveKeystoneInfo() is already valid — and it also covers reconnecting/reloading
-- mid-run via PLAYER_ENTERING_WORLD.
local function MatchContent()
    if not KART_Settings.autoLogEnabled then return false end
    local name, _, difficultyID, difficultyName = GetInstanceInfo()
    local keyLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    if keyLevel and keyLevel > 0 then
        if not KART_Settings.autoLogMythicPlus then return false end
        if keyLevel < (KART_Settings.autoLogMinKey or 2) then return false end
        return true, string.format("%s +%d", name or "M+", keyLevel)
    end
    local toggle = DIFFICULTY_TOGGLES[difficultyID]
    if toggle and KART_Settings[toggle] then
        return true, string.format("%s, %s", name or "?", difficultyName or "?")
    end
    return false
end

function KART.AutoLog.Evaluate()
    if not KART_Settings then return end -- settings not loaded yet (widget init during login)
    local match, desc = MatchContent()
    if match then
        if not LoggingCombat() then
            -- Advanced Combat Logging is required for usable Warcraft Logs uploads; the
            -- checkbox in Blizzard's options only sets this same CVar.
            SetCVar("advancedCombatLogging", 1)
            LoggingCombat(true)
            KART_Settings.autoLogOwned = true
            print("|cff00ff00KART:|r " .. string.format(KART.L.MSG_AL_STARTED, desc))
        end
        -- Already logging but not owned: the player started it manually — leave ownership
        -- (and the later stop decision) with them.
    elseif LoggingCombat() and KART_Settings.autoLogOwned then
        LoggingCombat(false)
        KART_Settings.autoLogOwned = false
        print("|cff00ff00KART:|r " .. KART.L.MSG_AL_STOPPED)
    end
end
```

- [ ] **Step 2: Add to TOC** between `Invite.lua` and `Core.lua`:

```
Invite.lua
AutoLog.lua
Core.lua
```

- [ ] **Step 3: Syntax check** (if a lua binary is available: `lua -e "loadfile('AutoLog.lua')"`; otherwise careful read-through — WoW load is the real gate).

- [ ] **Step 4: Commit**

```bash
git add AutoLog.lua KeineAhnungRaidTools.toc
git commit -m "feat: add AutoLog module for automatic combat logging"
```

---

### Task 3: Core.lua wiring

**Files:**
- Modify: `Core.lua:17` (event registration block)
- Modify: `Core.lua:242` (PLAYER_ENTERING_WORLD handler)
- Modify: `Core.lua:110` (settingsMap block)

**Interfaces:**
- Consumes: `KART.AutoLog.Evaluate()` (Task 2), widget references `KART.CbAlEnabled` etc. (Task 4 — guarded with `if`, so this task works before Task 4 lands).

- [ ] **Step 1: Register event** after `frame:RegisterEvent("PLAYER_ENTERING_WORLD")`:

```lua
frame:RegisterEvent("CHALLENGE_MODE_START")
```

- [ ] **Step 2: Route events.** In the `elseif event == "PLAYER_ENTERING_WORLD" then` branch, append after the existing version-announce block:

```lua
        if KART.AutoLog then KART.AutoLog.Evaluate() end
```

And add a new branch:

```lua
    elseif event == "CHALLENGE_MODE_START" then
        if KART.AutoLog then KART.AutoLog.Evaluate() end
```

- [ ] **Step 3: Extend settingsMap** (after the `KART.CbInviteViaGuildChat` line):

```lua
        if KART.CbAlEnabled then settingsMap[KART.CbAlEnabled] = "autoLogEnabled" end
        if KART.CbAlRaidLFR then settingsMap[KART.CbAlRaidLFR] = "autoLogRaidLFR" end
        if KART.CbAlRaidNormal then settingsMap[KART.CbAlRaidNormal] = "autoLogRaidNormal" end
        if KART.CbAlRaidHeroic then settingsMap[KART.CbAlRaidHeroic] = "autoLogRaidHeroic" end
        if KART.CbAlRaidMythic then settingsMap[KART.CbAlRaidMythic] = "autoLogRaidMythic" end
        if KART.CbAlMythicPlus then settingsMap[KART.CbAlMythicPlus] = "autoLogMythicPlus" end
        if KART.SldAlMinKey then settingsMap[KART.SldAlMinKey] = "autoLogMinKey" end
        if KART.CbAlDungeons then settingsMap[KART.CbAlDungeons] = "autoLogDungeons" end
        if KART.CbAlDelves then settingsMap[KART.CbAlDelves] = "autoLogDelves" end
```

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "feat: wire AutoLog evaluation into event dispatcher"
```

---

### Task 4: Automation tab UI card

**Files:**
- Modify: `MainFrame.lua:259` (after `KART.CbInviteViaGuildChat`, before the Settings Panel section)

**Interfaces:**
- Consumes: `KART.CreateCard`, `KART.CreateSettingsCheckbox`, `KART.CreateSettingsSlider`, locale keys from Task 1, `KART.AutoLog.Evaluate`.
- Produces: widgets `KART.CbAlEnabled`, `KART.CbAlRaidLFR`, `KART.CbAlRaidNormal`, `KART.CbAlRaidHeroic`, `KART.CbAlRaidMythic`, `KART.CbAlMythicPlus`, `KART.SldAlMinKey`, `KART.CbAlDungeons`, `KART.CbAlDelves` (names must match Task 3's settingsMap).

- [ ] **Step 1: Add card + widgets** after the `KART.CbInviteViaGuildChat` line:

```lua
-- Auto Combat Log card: content filters for AutoLog.lua. Widget callbacks re-evaluate
-- immediately so toggling a filter while already inside an instance takes effect without
-- re-zoning (including stopping an addon-owned log when the master switch goes off).
local alTitle = KART.PromotePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alTitle:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -265)
alTitle:SetText(L.LABEL_AUTOLOG)
table.insert(KART.DynamicLabels, alTitle)

local alCard = KART.CreateCard(KART.PromotePanel)
alCard:SetPoint("TOPLEFT", alTitle, "BOTTOMLEFT", 0, -10)
alCard:SetSize(290, 310)

local function AutoLogChanged()
    if KART.AutoLog then KART.AutoLog.Evaluate() end
end

KART.CbAlEnabled = KART.CreateSettingsCheckbox(alCard, "KART_AlEnabled", L.SET_AL_ENABLED, "autoLogEnabled", -20, AutoLogChanged, L.DESC_AL_ENABLED)
KART.CbAlRaidLFR = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidLFR", L.SET_AL_RAID_LFR, "autoLogRaidLFR", -50, AutoLogChanged)
KART.CbAlRaidNormal = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidNormal", L.SET_AL_RAID_NORMAL, "autoLogRaidNormal", -80, AutoLogChanged)
KART.CbAlRaidHeroic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidHeroic", L.SET_AL_RAID_HEROIC, "autoLogRaidHeroic", -110, AutoLogChanged)
KART.CbAlRaidMythic = KART.CreateSettingsCheckbox(alCard, "KART_AlRaidMythic", L.SET_AL_RAID_MYTHIC, "autoLogRaidMythic", -140, AutoLogChanged)
KART.CbAlMythicPlus = KART.CreateSettingsCheckbox(alCard, "KART_AlMythicPlus", L.SET_AL_MPLUS, "autoLogMythicPlus", -170, AutoLogChanged)
KART.SldAlMinKey = KART.CreateSettingsSlider(alCard, L.SET_AL_MIN_KEY, 2, 20, "autoLogMinKey", -200, "KART_AlMinKeySlider", L.DESC_AL_MIN_KEY)
KART.SldAlMinKey:HookScript("OnValueChanged", AutoLogChanged)
KART.CbAlDungeons = KART.CreateSettingsCheckbox(alCard, "KART_AlDungeons", L.SET_AL_DUNGEONS, "autoLogDungeons", -250, AutoLogChanged)
KART.CbAlDelves = KART.CreateSettingsCheckbox(alCard, "KART_AlDelves", L.SET_AL_DELVES, "autoLogDelves", -280, AutoLogChanged)
```

Note: scrollChild is 310×750 (`MainFrame.lua:133`); card bottom lands at ~585, fits without height change.

- [ ] **Step 2: Commit**

```bash
git add MainFrame.lua
git commit -m "feat: add Auto Combat Log card to Automation tab"
```

---

### Task 5: Changelog + verification

**Files:**
- Modify: `CHANGELOG.md` (Unreleased section)
- Modify: `CHANGELOG-de.md` (same entry, German)

- [ ] **Step 1: CHANGELOG.md** under `## [Unreleased]`:

```markdown
### Added
- **Auto Combat Log:** a new card in the Automation tab starts combat logging automatically when you enter selected content — raids per difficulty (LFR/Normal/Heroic/Mythic), Mythic+ with a minimum keystone level, dungeons, and Delves — and stops it when you leave. Advanced Combat Logging is enabled automatically; logging you start manually via /combatlog is never touched.
```

- [ ] **Step 2: Mirror to CHANGELOG-de.md.**

- [ ] **Step 3: Manual in-game checklist** (document for user, cannot be automated):
  1. `/reload` — no Lua errors, Automation tab shows the new card, all toggles off.
  2. Enable master + Raid: Heroic, zone into a Heroic raid → chat message, `/combatlog` state on.
  3. Zone out → logging stops with chat message.
  4. Start `/combatlog` manually in open world, zone into non-matching content and out → logging untouched.
  5. Enable M+ with min key 10, start a +2 → no logging; start a +10 → logging starts on key start.
  6. Toggle master off while addon-logging inside an instance → logging stops.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog entry for auto combat log"
```
