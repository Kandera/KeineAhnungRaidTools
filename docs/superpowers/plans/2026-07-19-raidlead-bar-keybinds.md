# Raidlead Bar Keybinds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let raid leads bind keys to 4 Raidlead Bar actions (Ready Check, Clear World Markers, Pull Timer, Buff-Checker Toggle) via a new card on the Raidlead settings tab.

**Architecture:** Four Raidlead Bar buttons get global frame names so `SetOverrideBindingClick` can address them by name. Bindings are stored in `KART_Settings.keybinds` and (re)applied by `KART.ApplyKeybinds()` on `ADDON_LOADED`. A new settings card provides one bind-button per action with click-to-capture / right-click-to-clear UX, guarded by `InCombatLockdown()`.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — this project has no automated test suite; verification is manual in-game (`/reload` + interact with UI).

## Global Constraints

- English source: code, comments, commit messages (per project CLAUDE.md). German strings only in `Locales/deDE.lua` values.
- Update `Locales/enUS.lua` first, then mirror every new string into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets one bullet (max 2 lines, bold lead) for this feature; mirror into `CHANGELOG-de.md` in the same task (per `CLAUDE.md`'s changelog-style rule).
- No individual keybinds for the 8 raid-target icons or 8 world-marker icons — out of scope.
- No collision detection against other addons'/Blizzard's bindings — last bind wins.
- Must not attempt to enter capture mode or clear a binding while `InCombatLockdown()` is true.

---

### Task 1: Name the four target buttons and add the keybinds default table

**Files:**
- Modify: `RaidleadBar.lua:158` (Clear World Markers button)
- Modify: `RaidleadBar.lua:159` (Ready Check button)
- Modify: `RaidleadBar.lua:176` (Pull Timer button, `KART.PullBtn`)
- Modify: `RaidleadBar.lua:162` (Buff-Checker toggle button)
- Modify: `Utils.lua:50-57` (`KART.Defaults` table)

**Interfaces:**
- Produces: global frame names `KART_RL_ClearWorldMarkersBtn`, `KART_RL_ReadyCheckBtn`, `KART_RL_PullTimerBtn`, `KART_RL_BuffCheckToggleBtn` — later tasks bind keys to these by name.
- Produces: `KART_Settings.keybinds` table, keys `readyCheck`, `clearWorldMarkers`, `pullTimer`, `buffCheckToggle`, each `nil` or a WoW binding string (e.g. `"SHIFT-F5"`).

`CreateBarButton`'s first arg to `CreateFrame` is currently always `nil` (anonymous). Give these four calls an explicit global name as the 2nd positional string passed into `CreateFrame("Button", <name>, parent, ...)` — this requires editing `CreateBarButton` itself to accept an optional `name` parameter, since it currently hardcodes `nil`.

- [ ] **Step 1: Add a `name` parameter to `CreateBarButton`**

In `RaidleadBar.lua`, change the function signature and the `CreateFrame` call:

```lua
-- 2. Lokale Hilfsfunktion für die Bar-Buttons
local function CreateBarButton(parent, x, y, width, height, func, texture, texCoords, text, macrotext, tooltipText, name)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate, BackdropTemplate")
```

(Only the signature line and the `CreateFrame` line change — everything else in the function body is untouched.)

- [ ] **Step 2: Pass names into the four target button calls**

Clear World Markers (currently line 158):

```lua
CreateBarButton(rlBar, 5 + 8*24, -29, 22, 22, nil, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil, nil, table.concat(clearWmMacro, "\n"), L.RL_CLEAR_WM, "KART_RL_ClearWorldMarkersBtn")
```

Ready Check (currently line 159):

```lua
CreateBarButton(rlBar, 225, -5, 22, 22, nil, "Interface\\RAIDFRAME\\ReadyCheck-Ready", nil, nil, "/readycheck", L.RL_READYCHECK, "KART_RL_ReadyCheckBtn")
```

Buff-Checker Toggle (currently lines 162-169) — add the name as the last argument:

```lua
CreateBarButton(rlBar, 249, -5, 22, 22, function(_, _, down)
    if down then return end
    if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then
        KART.BuffCheckFrame:Hide()
    else
        KART.ShowBuffCheck()
    end
end, 135932, nil, nil, nil, L.RL_BUFFCHECK, "KART_RL_BuffCheckToggleBtn")
```

Pull Timer (currently lines 176-183) — add the name as the last argument, keep assigning to `KART.PullBtn`:

```lua
KART.PullBtn = CreateBarButton(rlBar, 225, -29, 22, 22, function(_, button, down)
    if down then return end
    if button == "RightButton" then
        C_PartyInfo.DoCountdown(0)
    else
        C_PartyInfo.DoCountdown(KART_Settings and KART_Settings.pullTimerDuration or 10)
    end
end, "Interface\\ICONS\\Spell_Haste_Duration_01", nil, L.RL_PULL_LABEL, nil, L.RL_PULL_TIMER, "KART_RL_PullTimerBtn")
```

- [ ] **Step 3: Add the `keybinds` default table**

In `Utils.lua`, inside `KART.Defaults` (near `pullTimerDuration = 10,` at line 57), add:

```lua
    keybinds = { readyCheck = nil, clearWorldMarkers = nil, pullTimer = nil, buffCheckToggle = nil },
```

Note: `ADDON_LOADED`'s defaults-merge loop (`for k, v in pairs(KART.Defaults) do if KART_Settings[k] == nil then KART_Settings[k] = v end end`, `Core.lua:51-53`) is a shallow merge — since the whole `keybinds` table is `nil` on a fresh profile, it gets assigned by reference from `KART.Defaults.keybinds` once. `KART.Defaults.minimap = {}` (`Utils.lua:63`) is an existing table-valued default handled the exact same way — follow that precedent.

- [ ] **Step 4: Manual verification**

Run `/reload` in-game. No error should appear (a Lua error would show as a red chat message / `!BugGrabber` popup if installed). Open `/kart`, go to the Raidlead tab — the bar should look and behave exactly as before (this task only adds names and a settings table, no behavior change yet).

- [ ] **Step 5: Commit**

```bash
git add RaidleadBar.lua Utils.lua
git commit -m "feat: name Raidlead Bar action buttons, add keybinds default table"
```

---

### Task 2: `KART.ApplyKeybinds()` and load-time hook

**Files:**
- Modify: `RaidleadBar.lua` (add function near `KART.UpdateRaidleadBarVisibility`, after its definition ends at line 133)
- Modify: `Core.lua:162` (call site, right after `KART.UpdateRaidleadBarVisibility()`)

**Interfaces:**
- Consumes: `KART_Settings.keybinds` table from Task 1, global button names `KART_RL_ReadyCheckBtn`, `KART_RL_ClearWorldMarkersBtn`, `KART_RL_PullTimerBtn`, `KART_RL_BuffCheckToggleBtn`.
- Produces: `KART.ApplyKeybinds()` — no args, no return value. Later tasks (the settings UI) call this after every bind/clear.
- Produces: `KART.KeybindActions` — an ordered array the UI task (Task 4) iterates to build its 4 rows, each entry `{ key = "readyCheck", button = "KART_RL_ReadyCheckBtn" }` — no label field, since locale keys don't exist until Task 3; Task 4 maps `action.key` to a label itself.

- [ ] **Step 1: Write `KART.ApplyKeybinds` and the shared action list**

Add to `RaidleadBar.lua`, directly after the closing `end` of `KART.UpdateRaidleadBarVisibility` (line 133):

```lua
-- 4b. Keybind action list: shared between ApplyKeybinds and the settings-tab bind UI so both
-- stay in sync with a single source of truth for which 4 actions are bindable.
KART.KeybindActions = {
    { key = "readyCheck", button = "KART_RL_ReadyCheckBtn" },
    { key = "clearWorldMarkers", button = "KART_RL_ClearWorldMarkersBtn" },
    { key = "pullTimer", button = "KART_RL_PullTimerBtn" },
    { key = "buffCheckToggle", button = "KART_RL_BuffCheckToggleBtn" },
}

-- Applies every stored keybind as an override click-binding on its target button. Override
-- bindings work for both secure (Ready Check, Clear World Markers) and plain OnClick buttons
-- (Pull Timer, Buff-Checker Toggle) via the same call, and survive combat lockdown once set —
-- only the act of calling SetOverrideBindingClick itself is restricted while in combat, so this
-- must only run out of combat (mirrors KART.UpdateRaidleadBarVisibility's own guard).
function KART.ApplyKeybinds()
    if InCombatLockdown() then return end
    ClearOverrideBindings(rlBar)
    local binds = KART_Settings and KART_Settings.keybinds
    if not binds then return end
    for _, action in ipairs(KART.KeybindActions) do
        local key = binds[action.key]
        if key and key ~= "" then
            SetOverrideBindingClick(rlBar, false, key, action.button, "LeftButton")
        end
    end
end
```

- [ ] **Step 2: Call `ApplyKeybinds` on load**

In `Core.lua`, change line 162 from:

```lua
        KART.UpdateRaidleadBarVisibility()
```

to:

```lua
        KART.UpdateRaidleadBarVisibility()
        KART.ApplyKeybinds()
```

- [ ] **Step 3: Manual verification**

`/reload`. No Lua error. Since `KART_Settings.keybinds` is all-`nil` values at this point, `ApplyKeybinds` should be a no-op (loop finds no non-nil keys, sets nothing) — confirm no error and bar still works by mouse click.

- [ ] **Step 4: Commit**

```bash
git add RaidleadBar.lua Core.lua
git commit -m "feat: add KART.ApplyKeybinds, apply stored keybinds on load"
```

---

### Task 3: Locale strings

**Files:**
- Modify: `Locales/enUS.lua` (near the existing `SET_RL_*` / `RL_*` block, e.g. after line 50 `SET_PULL_TIMER`)
- Modify: `Locales/deDE.lua` (same location, mirrored)

**Interfaces:**
- Produces: locale keys consumed by Task 4's UI — `L.LABEL_RL_KEYBINDS`, `L.KB_READYCHECK`, `L.KB_CLEARWM`, `L.KB_PULLTIMER`, `L.KB_BUFFCHECK`, `L.KB_NOT_BOUND`, `L.KB_PRESS_KEY`, `L.KB_NOT_IN_COMBAT`, `L.DESC_KEYBINDS`.

- [ ] **Step 1: Add English strings**

In `Locales/enUS.lua`, after line 50 (`SET_PULL_TIMER = "Pull Timer Duration (Seconds)",`):

```lua
    LABEL_RL_KEYBINDS = "Keybinds",
    KB_READYCHECK = "Ready Check",
    KB_CLEARWM = "Clear World Markers",
    KB_PULLTIMER = "Pull Timer",
    KB_BUFFCHECK = "Buff-Checker Toggle",
    KB_NOT_BOUND = "Not Bound",
    KB_PRESS_KEY = "Press a key...",
    KB_NOT_IN_COMBAT = "Not in combat",
    DESC_KEYBINDS = "Left-click to bind a key, right-click to clear. Unavailable while in combat.",
```

- [ ] **Step 2: Add German strings**

In `Locales/deDE.lua`, at the same relative location (after the existing `SET_PULL_TIMER` line — locate it with the line number reported by reading the file, it mirrors `enUS.lua`'s line 50):

```lua
    LABEL_RL_KEYBINDS = "Tastenbelegung",
    KB_READYCHECK = "Bereitschaftscheck",
    KB_CLEARWM = "Weltmarkierungen löschen",
    KB_PULLTIMER = "Pull-Timer",
    KB_BUFFCHECK = "Buff-Checker ein/aus",
    KB_NOT_BOUND = "Nicht belegt",
    KB_PRESS_KEY = "Taste drücken...",
    KB_NOT_IN_COMBAT = "Nicht im Kampf möglich",
    DESC_KEYBINDS = "Linksklick zum Belegen, Rechtsklick zum Löschen. Im Kampf nicht verfügbar.",
```

- [ ] **Step 3: Manual verification**

`/reload`, open `/kart`, confirm no missing-locale errors (would show as `nil` concatenation errors if a key were mistyped and referenced already — not the case yet since nothing consumes them until Task 4). Skip if nothing to visually check yet; just confirm no Lua error on load.

- [ ] **Step 4: Commit**

```bash
git add Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add locale strings for Raidlead Bar keybind settings"
```

---

### Task 4: Settings UI — keybinds card on the Raidlead tab

**Files:**
- Modify: `MainFrame.lua` (insert after the existing `rlCard` block, i.e. after line 247 `KART.PullSlider = ...` and before the `-- 6. BuffChecker Panel Inhalt` comment at line 249)
- Modify: `MainFrame.lua:191-196` (`PANEL_CONTENT_HEIGHTS[2]`, currently `210`)
- Modify: `Core.lua:148-155` (add bind-button text sync alongside the existing `KART.BtnFont`/`KART.BtnLang` sync)

**Interfaces:**
- Consumes: `KART.KeybindActions` (Task 2), `KART.ApplyKeybinds()` (Task 2), `L.LABEL_RL_KEYBINDS`/`L.KB_*`/`L.DESC_KEYBINDS` (Task 3), `KART.CreateCard`/`KART.CreateModernButton` (existing, `Utils.lua`).
- Produces: 4 bind-buttons stored as `KART.KeybindButtons[actionKey]` — Task 4 Step 2 needs these to sync their displayed text once `KART_Settings` exists.

**Important — load-order constraint:** `MainFrame.lua` executes at addon file-load time, before `KART_Settings` is populated (that happens in `Core.lua`'s `ADDON_LOADED` handler, which runs after all files have loaded). This is why existing widgets in this codebase (e.g. `KART.CbActivate` in `Utils.lua`'s `CreateSettingsCheckbox`) never read `KART_Settings` at creation time — they're built with a neutral/default visual state, then synced afterward. `KART.BtnFont`/`KART.BtnLang` (`Core.lua:148-155`) show the exact pattern this task follows: both are `CreateModernButton`-based, and both get their `.text` set explicitly in the `ADDON_LOADED` handler, not at creation. The bind-buttons below follow the same rule: created with static placeholder text (`L.KB_NOT_BOUND`), synced to actual `KART_Settings.keybinds` values in Step 2.

- [ ] **Step 1: Add the keybinds card**

In `MainFrame.lua`, right after line 247 (`KART.PullSlider = ...`) and before the `-- 6. BuffChecker Panel Inhalt` comment:

```lua
-- Keybind card: one row per bindable Raidlead Bar action (Task list: KART.KeybindActions).
local kbCard = KART.CreateCard(KART.RaidleadPanel)
kbCard:SetPoint("TOPLEFT", rlCard, "BOTTOMLEFT", 0, -16)
kbCard:SetSize(500, 150)

local kbTitle = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
kbTitle:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, -14)
kbTitle:SetText(L.LABEL_RL_KEYBINDS)
table.insert(KART.DynamicLabels, kbTitle)

KART.KeybindButtons = {}
local kbLabels = {
    readyCheck = L.KB_READYCHECK,
    clearWorldMarkers = L.KB_CLEARWM,
    pullTimer = L.KB_PULLTIMER,
    buffCheckToggle = L.KB_BUFFCHECK,
}

-- Invisible key-listener used only while a bind-button is in capture mode; created once and
-- reused for whichever button is currently capturing (only one capture can be active at a time).
local kbListener = CreateFrame("Frame", nil, kbCard)
kbListener:Hide()
kbListener:EnableKeyboard(true)
kbListener:SetPropagateKeyboardInput(false)

local function StopCapture(activeBtn)
    kbListener:Hide()
    kbListener:SetScript("OnKeyDown", nil)
    if activeBtn then
        local current = KART_Settings and KART_Settings.keybinds and KART_Settings.keybinds[activeBtn.actionKey]
        activeBtn.text:SetText(current and current ~= "" and current or L.KB_NOT_BOUND)
    end
end

local function StartCapture(btn)
    btn.text:SetText(L.KB_PRESS_KEY)
    kbListener:Show()
    kbListener:SetScript("OnKeyDown", function(_, keyPressed)
        if keyPressed == "ESCAPE" then
            StopCapture(btn)
            return
        end
        -- Ignore bare modifier presses — wait for the actual key that completes the chord.
        if keyPressed == "LSHIFT" or keyPressed == "RSHIFT"
            or keyPressed == "LCTRL" or keyPressed == "RCTRL"
            or keyPressed == "LALT" or keyPressed == "RALT" then
            return
        end
        local binding = keyPressed
        if IsShiftKeyDown() then binding = "SHIFT-" .. binding end
        if IsControlKeyDown() then binding = "CTRL-" .. binding end
        if IsAltKeyDown() then binding = "ALT-" .. binding end
        KART_Settings.keybinds[btn.actionKey] = binding
        KART.ApplyKeybinds()
        StopCapture(btn)
    end)
end

for i, action in ipairs(KART.KeybindActions) do
    local yOff = -20 - (i - 1) * 30

    local label = kbCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 20, yOff)
    label:SetText(kbLabels[action.key])
    table.insert(KART.DynamicLabels, label)

    -- KART_Settings doesn't exist yet at this point in addon load (see load-order note above) —
    -- use the static placeholder; Step 2 below syncs the real value once ADDON_LOADED fires.
    local btn = KART.CreateModernButton(kbCard, L.KB_NOT_BOUND, L.DESC_KEYBINDS)
    btn:SetPoint("TOPLEFT", kbCard, "TOPLEFT", 260, yOff + 6)
    btn:SetSize(150, 22)
    btn.actionKey = action.key
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then
            self.text:SetText(L.KB_NOT_IN_COMBAT)
            C_Timer.After(1, function()
                local current = KART_Settings.keybinds[self.actionKey]
                self.text:SetText(current and current ~= "" and current or L.KB_NOT_BOUND)
            end)
            return
        end
        if button == "RightButton" then
            KART_Settings.keybinds[self.actionKey] = nil
            KART.ApplyKeybinds()
            self.text:SetText(L.KB_NOT_BOUND)
        else
            StartCapture(self)
        end
    end)
    KART.KeybindButtons[action.key] = btn
end
```

- [ ] **Step 2: Sync bind-button text once settings are loaded**

In `Core.lua`, right after line 155 (the closing `end` of the `KART.BtnLang` block, before the `KART.LC and KART.LC.BtnMinQuality` block at line 157):

```lua
        if KART.KeybindButtons then
            for key, btn in pairs(KART.KeybindButtons) do
                local bound = KART_Settings.keybinds and KART_Settings.keybinds[key]
                btn.text:SetText(bound and bound ~= "" and bound or L.KB_NOT_BOUND)
            end
        end
```

- [ ] **Step 3: Grow the Raidlead tab's scroll height**

In `MainFrame.lua`, change `PANEL_CONTENT_HEIGHTS[2]` (around line 193):

```lua
    [2] = 380, -- Raidlead: bar-settings card (180) + keybinds card (150) + gaps
```

- [ ] **Step 4: Manual verification**

`/reload`, open `/kart`, go to Raidlead tab. Confirm:
- New "Keybinds" card renders below the existing bar-settings card, 4 rows, all showing "Not Bound".
- Left-click a bind-button → text becomes "Press a key...". Press `F5` → text becomes `F5`, `KART_Settings.keybinds.readyCheck` is `"F5"` (check via `/dump KART_Settings.keybinds`).
- Pressing `F5` anywhere (bar visible, not typing in an edit box) now triggers a Ready Check — same as clicking the bar's Ready Check button.
- Press the bind-button again, then Escape → binding unchanged, text reverts to `F5`.
- Right-click the bound button → text becomes "Not Bound", `F5` no longer triggers Ready Check.
- Repeat bind for Clear World Markers, Pull Timer, Buff-Checker Toggle — each triggers the same effect as its bar button when the key is pressed, including with the raid frame not focused.
- `/reload` again with at least one binding set → binding persists and is re-applied (verify the key still works without re-visiting the settings UI).
- Enter combat (or `/console scriptErrors 1` + a test dummy) and click a bind-button → shows "Not in combat" briefly, no capture starts; right-click while in combat does not clear an existing binding.

- [ ] **Step 5: Commit**

```bash
git add MainFrame.lua Core.lua
git commit -m "feat: add keybind settings card to Raidlead tab"
```

---

### Task 5: Changelog

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

**Interfaces:** None (docs only).

This project has no "Unreleased" section convention — every existing entry (see `CHANGELOG.md:9-21`, the `## [2.0.0]` block) is a released, dated version bump. Follow that exact pattern: bump `KeineAhnungRaidTools.toc`'s `## Version:` line (currently `2.0.0`) to `2.1.0`, and add a matching changelog entry dated with today's date.

- [ ] **Step 1: Bump the addon version**

In `KeineAhnungRaidTools.toc`, change:

```
## Version: 2.0.0
```

to:

```
## Version: 2.1.0
```

- [ ] **Step 2: Add the English changelog entry**

In `CHANGELOG.md`, insert a new section above the existing `## [2.0.0] - 2026-07-18` entry (line 9):

```markdown
## [2.1.0] - 2026-07-19
### Added
- **Keybinds for Ready Check, Clear World Markers, Pull Timer, and Buff-Checker Toggle:** set in a new Keybinds card on the Raidlead tab.
```

- [ ] **Step 3: Mirror into German changelog**

In `CHANGELOG-de.md`, insert at the same relative position (above its own `## [2.0.0]` entry):

```markdown
## [2.1.0] - 2026-07-19
### Added
- **Tastenbelegung für Bereitschaftscheck, Weltmarkierungen löschen, Pull-Timer und Buff-Checker ein/aus:** einstellbar in einer neuen Tastenbelegung-Card im Raidlead-Tab.
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version to 2.1.0, changelog entry for Raidlead Bar keybinds"
```
