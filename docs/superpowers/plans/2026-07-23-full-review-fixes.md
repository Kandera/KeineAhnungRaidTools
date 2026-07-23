# Full Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding from the 2026-07-23 full-addon review — 2 critical, 5 important, 12 minor bugs, 11 dead-code items, and the approved simplification refactors — in 7 sequential blocks.

**Architecture:** WoW Retail addon (single `KART` namespace shared via `local addonName, KART = ...`). No test framework exists — every task verifies via grep assertions plus an in-game check (`/reload` for edited files; a **full WoW client restart** is required whenever a file is added to the .toc). Blocks are ordered so earlier blocks never get rewritten by later ones (exception: Task 18's two-line fix is later absorbed by Task 34's refactor, which must preserve it).

**Tech Stack:** Lua 5.1 (WoW), WoW Retail API (Interface 12.x), LibStub, LibDataBroker, LibDBIcon, LibSharedMedia, optional LibDurability/NSRT.

## Global Constraints

- Comments and commit messages in English (repo CLAUDE.md).
- Locale: `Locales/enUS.lua` is the master; `deDE.lua` values stay German, its comments English. Every new user-facing string gets a key in **both** files.
- CHANGELOG entries: max 1–2 lines, bold lead + short clause, no causes. Update `CHANGELOG.md` first, mirror into `CHANGELOG-de.md` in the same commit.
- Commits go directly to `main`, one commit per task, conventional-commit style.
- After Block 2 lands: **`KART.L` is a stable table reference and must never be replaced**, only have its values swapped in place. New static UI text needs a locale-refresher entry.
- Decisions already made with the maintainer: K2 = full text refresh (Option A); W4 = lootmaster force-wins only BoP, council-relevant, non-collectible items and ALWAYS passes everything else (independent of their own Auto-Pass setting); M5 = Loot Council raid-only; S11 + S12 in scope, S13 (file renames) out of scope.

## Verification Toolkit (used by many tasks)

- Grep assertion: `grep -n "<pattern>" <file>` from repo root (Git Bash).
- In-game reload: `/reload` after copying files to the WoW AddOns folder (or working directly in it).
- Fresh-settings simulation: `/run KART_Settings.<key> = nil ReloadUI()`.
- Lua error visibility: `/console scriptErrors 1` once per client.

---

# Block 1 — Critical quick fixes (K1, W1, W2, W5+M4, M12, T1)

Small, independent edits. Ships first because K1 breaks logins for every 2.8.0 user who never touched the Loot Council font-size slider.

### Task 1: Add missing setting defaults (K1 crash fix)

**Files:**
- Modify: `Utils.lua` (KART.Defaults table, ~line 50–102)

**Interfaces:**
- Produces: `KART.Defaults.lcFontSize = 12`, `KART.Defaults.lcRollsEnabled = false`, `KART.Defaults.lcVotedItemDisplay = "full"` — Task 5's reset and Core's ADDON_LOADED merge rely on these existing.

- [ ] **Step 1: Add the three missing keys to KART.Defaults**

In `Utils.lua`, inside `KART.Defaults = { ... }`, directly below the line `lcVoteLayoutCompact = false,` insert:

```lua
    lcFontSize = 12,
    lcRollsEnabled = false,
    lcVotedItemDisplay = "full",
```

Why: `Core.lua:108` runs `widget:SetValue(KART_Settings[key])` for every mapped slider. `lcFontSize` had no default, so a nil value reached `Slider:SetValue(nil)` → Lua error that aborts the rest of ADDON_LOADED. `lcRollsEnabled`/`lcVotedItemDisplay` are checkbox/button-backed (nil is tolerated) but must exist so Reset (Task 5) actually resets them.

- [ ] **Step 2: Verify**

Run: `grep -n "lcFontSize\|lcRollsEnabled\|lcVotedItemDisplay" Utils.lua`
Expected: three hits inside the Defaults table.

In-game: `/run KART_Settings.lcFontSize = nil ReloadUI()` → no Lua error on load; Loot Council tab's font-size slider shows 12.

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "fix: add missing lcFontSize/lcRollsEnabled/lcVotedItemDisplay defaults (login error on fresh settings)"
```

### Task 2: Fetch LibDurability via LibStub in Core (W1)

**Files:**
- Modify: `Core.lua:271-275` (READY_CHECK branch)

- [ ] **Step 1: Replace the dead global lookup**

In `Core.lua`, READY_CHECK handler, replace:

```lua
            if LibDurability and LibDurability.RequestDurability then
                LibDurability:RequestDurability()
            end
```

with:

```lua
            -- LibDurability is LibStub-only (no global) — a bare global lookup here was always
            -- nil, so the durability request on ready check never fired.
            local durabilityLib = LibStub and LibStub("LibDurability", true)
            if durabilityLib and durabilityLib.RequestDurability then
                durabilityLib:RequestDurability()
            end
```

- [ ] **Step 2: Verify**

Run: `grep -n "LibDurability" Core.lua`
Expected: only the new `LibStub("LibDurability", true)` form; no bare `if LibDurability` remains.

In-game (group with BigWigs/MRT users): start a ready check with Buff-Checker open → Rep column fills without pressing Refresh.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "fix: request durability via LibStub on ready check (global LibDurability is always nil)"
```

### Task 3: Localize the ready-check reason print (W2)

**Files:**
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (BuffChecker section)
- Modify: `Core.lua:431`

- [ ] **Step 1: Add the locale key**

`Locales/enUS.lua`, below `RC_REASON_SEND = "Send",`:

```lua
    RC_REASON_RECEIVED = "|cff00ff00KART:|r %s is not ready: |cffffaa00%s|r",
```

`Locales/deDE.lua`, below `RC_REASON_SEND = "Senden",`:

```lua
    RC_REASON_RECEIVED = "|cff00ff00KART:|r %s ist nicht bereit: |cffffaa00%s|r",
```

- [ ] **Step 2: Use it in Core.lua**

Replace (line ~431):

```lua
                        print(string.format("|cff00ff00KART:|r %s ist nicht bereit: |cffffaa00%s|r", shortName, reason))
```

with:

```lua
                        print(string.format(KART.L.RC_REASON_RECEIVED, shortName, reason))
```

- [ ] **Step 3: Verify**

Run: `grep -n "RC_REASON_RECEIVED" Core.lua Locales/enUS.lua Locales/deDE.lua`
Expected: one use in Core, one definition per locale file.

- [ ] **Step 4: Commit**

```bash
git add Core.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "fix: localize the 'player is not ready' chat print (was hardcoded German)"
```

### Task 4: Version fallback + duplicate widget init (M12, T1)

**Files:**
- Modify: `Core.lua:3` and `Core.lua:54-59`

- [ ] **Step 1: Neutral version fallback**

Replace `Core.lua:3`:

```lua
KART.Version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.12.2"
```

with:

```lua
KART.Version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"
```

- [ ] **Step 2: Remove the duplicate widget initialization**

In `KART.SyncSettingsToUI()`, delete these lines (the `settingsMap` loop right below does exactly the same for all three widgets):

```lua
    -- Initialisiere UI Werte
    if KART.InviteEditBox then KART.InviteEditBox:SetText(KART_Settings.inviteKeywords) end -- KART.InviteEditBox aus MainFrame.lua
    if KART.PromoteEditBox then KART.PromoteEditBox:SetText(KART_Settings.promoteNames) end -- KART.PromoteEditBox aus MainFrame.lua

    -- Raidlead Panel Initialisierung
    if KART.CbActivate then KART.CbActivate:SetChecked(KART_Settings.showRaidleadBar) end
```

- [ ] **Step 3: Verify**

Run: `grep -n "1.12.2\|Initialisiere UI Werte" Core.lua`
Expected: no hits.
In-game: `/reload` → Automation tab keywords/promote names still populated (settingsMap path).

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "chore: neutral version fallback, drop widget init duplicated by settingsMap"
```

### Task 5: Full reset + deep-copied table defaults (W5, M4)

**Files:**
- Modify: `MainFrame.lua:563-568` (BtnReset OnClick)
- Modify: `Core.lua:167-169` (Defaults merge in ADDON_LOADED)

**Interfaces:**
- Consumes: `KART.DeepCopy` (Utils.lua), Task 1's new default keys.

- [ ] **Step 1: Make Reset a full wipe**

Replace the BtnReset handler body in `MainFrame.lua`:

```lua
KART.BtnReset:SetScript("OnClick", function()
    -- Full wipe, not a per-key overwrite: keys without a Defaults entry (window positions,
    -- sizes) must reset too. Tables are deep-copied so KART.Defaults itself is never shared
    -- into (and later mutated through) KART_Settings.
    wipe(KART_Settings)
    for k, v in pairs(KART.Defaults) do
        KART_Settings[k] = type(v) == "table" and KART.DeepCopy(v) or v
    end
    ReloadUI() -- Einfachste Methode um alle UI Werte zurückzusetzen
end)
```

- [ ] **Step 2: Deep-copy tables in the ADDON_LOADED merge**

In `Core.lua`, replace:

```lua
        for k, v in pairs(KART.Defaults) do
            if KART_Settings[k] == nil then KART_Settings[k] = v end
        end
```

with:

```lua
        -- Deep-copy table defaults (keybinds, minimap): assigning them by reference let the
        -- live settings mutate KART.Defaults itself, which then made "Reset Defaults" a no-op
        -- for those keys within the same session.
        for k, v in pairs(KART.Defaults) do
            if KART_Settings[k] == nil then
                KART_Settings[k] = type(v) == "table" and KART.DeepCopy(v) or v
            end
        end
```

- [ ] **Step 3: Verify**

In-game: move the Buff-Checker window, bind a key on the Raidlead tab, then Settings → Reset Defaults → after reload, window position and keybind are gone.
Grep: `grep -n "DeepCopy" Core.lua MainFrame.lua` → one hit each.

- [ ] **Step 4: Commit**

```bash
git add Core.lua MainFrame.lua
git commit -m "fix: Reset Defaults wipes everything incl. positions; deep-copy table defaults"
```

### Task 6: Block 1 changelog

**Files:**
- Modify: `CHANGELOG.md`, `CHANGELOG-de.md`

- [ ] **Step 1: Add entries (EN first, then mirror)**

`CHANGELOG.md` under a new `## Unreleased` heading (create if absent):

```markdown
- **Fixed a login error** for characters that never touched the Loot Council font-size slider.
- **Durability data now loads automatically on ready checks.**
- **"Player is not ready" chat messages now use your language.**
- **Reset Defaults now resets everything**, including window positions and keybinds.
```

`CHANGELOG-de.md` (mirror):

```markdown
- **Login-Fehler behoben** für Charaktere, die den Loot-Council-Schriftgrößen-Regler nie benutzt haben.
- **Haltbarkeitsdaten laden jetzt automatisch beim Ready-Check.**
- **"Spieler ist nicht bereit"-Chatmeldungen nutzen jetzt deine Sprache.**
- **Standardwerte-Reset setzt jetzt alles zurück**, inklusive Fensterpositionen und Tastenbelegung.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog for block 1 fixes"
```

---

# Block 2 — Locale system rework (K2, Option A)

Root problem: `enUS.lua` fills `KART.L` at file load; `Core.lua` **replaces the `KART.L` reference** at ADDON_LOADED. All UI built at file load (main window, LC settings panel, WU panel) is English forever, and files caching `local L = KART.L` (MainFrame, BuffChecker, RaidleadBar) keep the stale English table even for lazily built windows.

Fix (decided: Option A): (1) `KART.L` becomes a stable table whose **values** are swapped in place at ADDON_LOADED; (2) each file with load-time static text registers a **locale refresher** that re-applies its texts from `KART.L`; refreshers run once after locale selection (language changes already `ReloadUI()`, so one pass is sufficient); (3) UI factories stop capturing tooltip strings in closures so refreshers can update them.

### Task 7: Stable KART.L + refresher registry

**Files:**
- Modify: `Utils.lua` (top, after the registry tables ~line 13)
- Modify: `Core.lua:171-181` (language block)

**Interfaces:**
- Produces: `KART.RegisterLocaleRefresher(fn)` and `KART.ApplyLocaleRefreshers()` — Tasks 9–13 register refreshers; Core calls apply once at ADDON_LOADED.

- [ ] **Step 1: Add the registry to Utils.lua**

Below `KART.AccentLines = {}` insert:

```lua
-- Locale refreshers: files that build UI text at load time (before the saved language is
-- known) register a function here that re-applies all their static texts from KART.L.
-- Core.lua runs them once at ADDON_LOADED, right after the locale values are copied in.
-- KART.L itself is a STABLE table — its reference must never be replaced, only its values
-- swapped (files capture `local L = KART.L` at load time and keep that reference).
KART.LocaleRefreshers = {}
function KART.RegisterLocaleRefresher(fn)
    table.insert(KART.LocaleRefreshers, fn)
end
function KART.ApplyLocaleRefreshers()
    for _, fn in ipairs(KART.LocaleRefreshers) do fn() end
end
```

- [ ] **Step 2: Copy locale values in place in Core.lua**

Replace the language block in ADDON_LOADED:

```lua
        -- Sprache anwenden
        local currentLang = KART_Settings.language
        if currentLang == "Auto" then currentLang = GetLocale() end
        
        if currentLang == "deDE" and KART.L_deDE then
            setmetatable(KART.L_deDE, { __index = KART.L_enUS })
            KART.L = KART.L_deDE
        elseif KART.L_enUS then
            -- Fallback auf Englisch (enUS) für alle anderen Clients (z.B. frFR, ruRU)
            KART.L = KART.L_enUS
        end
```

with:

```lua
        -- Apply language: copy the chosen locale's VALUES into KART.L instead of replacing
        -- the reference — several files capture `local L = KART.L` at load time, and all
        -- statically-built UI re-reads via locale refreshers below. enUS is the base; deDE
        -- overlays it, so missing German keys fall back to English automatically.
        local currentLang = KART_Settings.language
        if currentLang == "Auto" then currentLang = GetLocale() end
        wipe(KART.L)
        for k, v in pairs(KART.L_enUS) do KART.L[k] = v end
        if currentLang == "deDE" and KART.L_deDE then
            for k, v in pairs(KART.L_deDE) do KART.L[k] = v end
        end
```

**Important:** this block must run **before** the `KART.Defaults` merge loop (move it up if needed — currently the merge sits above it). Final order inside ADDON_LOADED: saved-variable init → language default → **locale copy** → Defaults merge → minimap/dbIcon → `KART.ApplyLocaleRefreshers()` → `KART.SyncSettingsToUI()` → rest.

- [ ] **Step 3: Call the refreshers**

In `Core.lua` ADDON_LOADED, directly before `KART.SyncSettingsToUI()` add:

```lua
        -- Re-apply every statically-built UI text with the now-selected language.
        KART.ApplyLocaleRefreshers()
```

- [ ] **Step 4: Verify**

Run: `grep -n "setmetatable(KART.L_deDE" Core.lua` → no hits.
Run: `grep -n "ApplyLocaleRefreshers" Core.lua Utils.lua` → one call in Core, definition in Utils.
In-game: `/reload` → no errors (refresher list is still empty; texts unchanged until Tasks 9–13).

- [ ] **Step 5: Commit**

```bash
git add Utils.lua Core.lua
git commit -m "feat: stable KART.L with in-place locale copy + locale-refresher registry"
```

### Task 8: Factories read tooltips from mutable fields

**Files:**
- Modify: `Utils.lua` (`CreateModernButton`, `CreateSettingsCheckbox`, `CreateSettingsSlider`)
- Modify: `RaidleadBar.lua` (`CreateBarButton`)

**Interfaces:**
- Produces: every button/checkbox/slider exposes `.tooltipText` (buttons/checkboxes/sliders) that refreshers may overwrite; tooltip headline reads the widget's **current** label text instead of a load-time capture.

- [ ] **Step 1: CreateModernButton**

Replace its OnEnter/OnLeave block:

```lua
    b:SetScript("OnEnter", function(self)
        local r, g, bl = hoverColor()
        self:SetBackdropColor(r, g, bl, 1)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
```

with:

```lua
    -- Tooltip strings live on the button (not in this closure) so locale refreshers can
    -- update them after the saved language is applied; the headline is the button's current
    -- label so dynamic buttons (font/language pickers) always show their live text.
    b.tooltipText = tooltipText
    b:SetScript("OnEnter", function(self)
        local r, g, bl = hoverColor()
        self:SetBackdropColor(r, g, bl, 1)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
```

(OnLeave stays unchanged.)

- [ ] **Step 2: CreateSettingsCheckbox**

Replace the trailing tooltip block:

```lua
    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
```

with:

```lua
    cb.tooltipText = tooltipText
    cb:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

- [ ] **Step 3: CreateSettingsSlider**

Replace the trailing tooltip block:

```lua
    if tooltipText then
        s:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        s:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
```

with:

```lua
    s.tooltipText = tooltipText
    s:HookScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title:GetText() or "", 1, 1, 1)
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    s:HookScript("OnLeave", function() GameTooltip:Hide() end)
```

- [ ] **Step 4: RaidleadBar CreateBarButton**

Replace its OnEnter/OnLeave pair:

```lua
    b:SetScript("OnEnter", function(self)
        local r, g, bl = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.35)
        self:SetBackdropColor(dr, dg, db, 1)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) 
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.8) 
        if tooltipText then GameTooltip:Hide() end
    end)
```

with:

```lua
    b.tooltipText = tooltipText
    b:SetScript("OnEnter", function(self)
        local r, g, bl = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.35)
        self:SetBackdropColor(dr, dg, db, 1)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        GameTooltip:Hide()
    end)
```

- [ ] **Step 5: Verify**

In-game `/reload`: hover a settings checkbox, a slider, a modern button, a Raidlead bar button → tooltips identical to before.
Grep: `grep -n "tooltipText" Utils.lua RaidleadBar.lua | grep -v "self.tooltipText\|b.tooltipText\|cb.tooltipText\|s.tooltipText\|opts\|tooltipText)"` → no closure reads left.

- [ ] **Step 6: Commit**

```bash
git add Utils.lua RaidleadBar.lua
git commit -m "refactor: tooltips read mutable widget fields so locale refreshers can update them"
```

### Task 9: MainFrame locale refresher

**Files:**
- Modify: `MainFrame.lua` (collect loop labels; register refresher at end of file)

- [ ] **Step 1: Capture the keybind row labels**

In the keybind loop (`for i, action in ipairs(KART.KeybindActions) do`), the row label is a loop-local. Above the loop add `local kbRowLabels = {}`, and inside the loop after `table.insert(KART.DynamicLabels, label)` add:

```lua
    kbRowLabels[action.key] = label
```

- [ ] **Step 2: Register the refresher at the very end of MainFrame.lua**

Append (file scope — all the referenced locals `promLabel`, `invLabel`, `alTitle`, `kbTitle`, `profTitle`, `searchBtn`, `kbRowLabels` are visible here):

```lua
-- Re-applies every static text in this file from KART.L once the saved language is known
-- (see KART.RegisterLocaleRefresher in Utils.lua). Dynamic texts (BtnFont/BtnLang/BtnProfile
-- labels, keybind button captions, strata slider value) are handled by KART.SyncSettingsToUI.
KART.RegisterLocaleRefresher(function()
    local L = KART.L

    -- Sidebar tabs + fixed header titles
    KART.BtnPromote.text:SetText(L.TAB_PROMOTE)
    KART.BtnRaidlead.text:SetText(L.TAB_RAIDLEAD)
    KART.BtnBuffCheck.text:SetText(L.TAB_BUFFCHECK)
    KART.BtnLootCouncil.text:SetText(L.TAB_LOOTCOUNCIL)
    KART.BtnWoWUtils.text:SetText(L.TAB_WOWUTILS)
    KART.BtnSettings.text:SetText(L.TAB_SETTINGS)
    KART.TabTitles[1]:SetText(L.TAB_PROMOTE)
    KART.TabTitles[2]:SetText(L.LABEL_RAIDLEAD_TOOLS)
    KART.TabTitles[3]:SetText(L.LABEL_BUFFCHECK_SETTINGS)
    KART.TabTitles[4]:SetText(L.LABEL_GENERAL_SETTINGS)
    -- TabTitles[5]/[6] belong to LootCouncil.lua / Invite.lua and are refreshed there.

    -- Raidlead tab
    KART.CbActivate.text:SetText(L.SET_RL_ACTIVATE)   KART.CbActivate.tooltipText = L.DESC_RL_ACTIVATE
    KART.CbLock.text:SetText(L.SET_RL_LOCK)           KART.CbLock.tooltipText = L.DESC_RL_LOCK
    KART.CbAutoHide.text:SetText(L.SET_RL_AUTOHIDE)   KART.CbAutoHide.tooltipText = L.DESC_RL_AUTOHIDE
    KART.PullSlider.title:SetText(L.SET_PULL_TIMER)   KART.PullSlider.tooltipText = L.DESC_PULL_TIMER
    kbTitle:SetText(L.LABEL_RL_KEYBINDS)
    local kbKeyByAction = {
        readyCheck = "KB_READYCHECK", clearWorldMarkers = "KB_CLEARWM",
        pullTimer = "KB_PULLTIMER", buffCheckToggle = "KB_BUFFCHECK",
    }
    for actionKey, label in pairs(kbRowLabels) do
        label:SetText(L[kbKeyByAction[actionKey]])
    end
    for _, btn in pairs(KART.KeybindButtons) do
        btn.tooltipText = L.DESC_KEYBINDS
    end

    -- BuffCheck tab
    KART.CbBcModuleEnabled.text:SetText(L.SET_BC_MODULE_ENABLED)  KART.CbBcModuleEnabled.tooltipText = L.DESC_BC_MODULE_ENABLED
    KART.CbShowBuffCheck.text:SetText(L.SET_BC_READYCHECK)        KART.CbShowBuffCheck.tooltipText = L.DESC_BC_READYCHECK
    KART.CbGrayOffline.text:SetText(L.SET_GRAY_OFFLINE)           KART.CbGrayOffline.tooltipText = L.DESC_GRAY_OFFLINE
    KART.BtnBuffPreview.text:SetText(L.BTN_BUFF_PREVIEW)
    KART.SldBuffCheckAlpha.title:SetText(L.SET_BC_ALPHA)          KART.SldBuffCheckAlpha.tooltipText = L.DESC_BC_ALPHA
    KART.SldCombatDelay.title:SetText(L.SET_BC_COMBAT_DELAY)      KART.SldCombatDelay.tooltipText = L.DESC_BC_COMBAT_DELAY

    -- Automation tab
    promLabel:SetText(L.LABEL_PROMOTE_NAMES)
    invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
    KART.CbAutoRaid.text:SetText(L.SET_AUTO_RAID)                 KART.CbAutoRaid.tooltipText = L.DESC_AUTO_RAID
    KART.CbInviteViaGuildChat.text:SetText(L.SET_INVITE_VIA_GUILD_CHAT)
    KART.CbInviteViaGuildChat.tooltipText = L.DESC_INVITE_VIA_GUILD_CHAT
    alTitle:SetText(L.LABEL_AUTOLOG)
    KART.CbAlEnabled.text:SetText(L.SET_AL_ENABLED)               KART.CbAlEnabled.tooltipText = L.DESC_AL_ENABLED
    KART.CbAlRaidLFR.text:SetText(L.SET_AL_RAID_LFR)
    KART.CbAlRaidNormal.text:SetText(L.SET_AL_RAID_NORMAL)
    KART.CbAlRaidHeroic.text:SetText(L.SET_AL_RAID_HEROIC)
    KART.CbAlRaidMythic.text:SetText(L.SET_AL_RAID_MYTHIC)
    KART.CbAlMythicPlus.text:SetText(L.SET_AL_MPLUS)
    KART.CbAlDungeons.text:SetText(L.SET_AL_DUNGEONS)
    KART.CbAlDelves.text:SetText(L.SET_AL_DELVES)
    KART.SldAlMinKey.title:SetText(L.SET_AL_MIN_KEY)              KART.SldAlMinKey.tooltipText = L.DESC_AL_MIN_KEY

    -- Settings tab
    KART.CbMinimap.text:SetText(L.SET_MINIMAP)                    KART.CbMinimap.tooltipText = L.DESC_MINIMAP
    KART.SldUiScale.title:SetText(L.SET_UI_SCALE)                 KART.SldUiScale.tooltipText = L.DESC_UI_SCALE
    KART.SldBgAlpha.title:SetText(L.SET_BG_ALPHA)                 KART.SldBgAlpha.tooltipText = L.DESC_BG_ALPHA
    KART.SldFrameStrata.title:SetText(L.SET_FRAME_STRATA)         KART.SldFrameStrata.tooltipText = L.DESC_FRAME_STRATA
    KART.SldMenuSize.title:SetText(L.LABEL_FONT_SIZE_MENU)        KART.SldMenuSize.tooltipText = L.DESC_MENU_SIZE
    KART.SldContentSize.title:SetText(L.LABEL_FONT_SIZE_CONTENT)  KART.SldContentSize.tooltipText = L.DESC_CONTENT_SIZE
    KART.BtnFont.tooltipText = L.DESC_SELECT_FONT
    KART.BtnLang.tooltipText = L.DESC_LANGUAGE
    KART.BtnAccentColor.text:SetText(L.BTN_ACCENT_COLOR)          KART.BtnAccentColor.tooltipText = L.DESC_ACCENT_COLOR
    KART.BtnReset.text:SetText(L.BTN_RESET)                       KART.BtnReset.tooltipText = L.DESC_RESET
    profTitle:SetText(L.LABEL_PROFILES)
    KART.BtnProfileSaveNew.text:SetText(L.BTN_PROFILE_SAVE_NEW)   KART.BtnProfileSaveNew.tooltipText = L.DESC_PROFILE_SAVE_NEW
    KART.BtnProfileSave.text:SetText(L.BTN_PROFILE_SAVE)          KART.BtnProfileSave.tooltipText = L.DESC_PROFILE_SAVE
    KART.BtnProfileDelete.text:SetText(L.BTN_PROFILE_DELETE)      KART.BtnProfileDelete.tooltipText = L.DESC_PROFILE_DELETE

    -- Header search
    searchBtn.text:SetText(L.BTN_SEARCH)
    searchBtn.tooltipText = L.DESC_SEARCH
end)
```

- [ ] **Step 3: Verify**

In-game on a deDE client (or `/run KART_Settings.language = "deDE" ReloadUI()`): sidebar tabs, all four tab bodies show German. Switch `/run KART_Settings.language = "enUS" ReloadUI()` → English everywhere.

- [ ] **Step 4: Commit**

```bash
git add MainFrame.lua
git commit -m "feat: locale refresher for the main window's static texts"
```

### Task 10: LootCouncil settings panel refresher

**Files:**
- Modify: `LootCouncil.lua` (end of `LC.BuildSettingsPanel`, before `end`)

- [ ] **Step 1: Register the refresher inside BuildSettingsPanel**

Insert directly above the function's closing `end` (after the BtnHistory block — all referenced locals are in scope):

```lua
    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        KART.TabTitles[5]:SetText(Lx.LC_SETTINGS_TITLE)
        KART.LC.CbModuleEnabled.text:SetText(Lx.LC_SET_MODULE_ENABLED)        KART.LC.CbModuleEnabled.tooltipText = Lx.LC_DESC_MODULE_ENABLED
        KART.LC.CbAutoPass.text:SetText(Lx.LC_SET_AUTOPASS)                   KART.LC.CbAutoPass.tooltipText = Lx.LC_DESC_AUTOPASS
        KART.LC.CbCompactVoteLayout.text:SetText(Lx.LC_SET_COMPACT_VOTE_LAYOUT)
        KART.LC.CbCompactVoteLayout.tooltipText = Lx.LC_DESC_COMPACT_VOTE_LAYOUT
        KART.LC.CbShowNickNames.text:SetText(Lx.LC_SET_SHOW_NICKNAMES)        KART.LC.CbShowNickNames.tooltipText = Lx.LC_DESC_SHOW_NICKNAMES
        KART.LC.BtnVotedItemDisplay.tooltipText = Lx.LC_DESC_VOTED_DISPLAY -- label synced by SyncSettingsToUI
        boxTitle:SetText(Lx.LC_RAIDWIDE_TITLE)
        KART.LC.SldVoteTimer.title:SetText(Lx.LC_SET_VOTE_TIMER)              KART.LC.SldVoteTimer.tooltipText = Lx.LC_DESC_VOTE_TIMER
        KART.LC.SldFontSize.title:SetText(Lx.LC_SET_FONT_SIZE)                KART.LC.SldFontSize.tooltipText = Lx.LC_DESC_FONT_SIZE
        KART.LC.CbRollsEnabled.text:SetText(Lx.LC_SET_ROLLS_ENABLED)          KART.LC.CbRollsEnabled.tooltipText = Lx.LC_DESC_ROLLS_ENABLED
        lblButtons:SetText(Lx.LC_SET_BUTTONS)
        hint:SetText(Lx.LC_SET_BUTTONS_HINT)
        lblCouncil:SetText(Lx.LC_SET_COUNCIL)
        hintCouncil:SetText(Lx.LC_SET_COUNCIL_HINT)
        lblLootmaster:SetText(Lx.LC_SET_LOOTMASTER)
        hintLootmaster:SetText(Lx.LC_SET_LOOTMASTER_HINT)
        lblQuality:SetText(Lx.LC_SET_MIN_QUALITY)
        KART.LC.BtnMinQuality.tooltipText = Lx.LC_DESC_MIN_QUALITY -- label synced by SyncSettingsToUI
        KART.LC.BtnToggleSession.text:SetText(Lx.LC_BTN_TOGGLE)               KART.LC.BtnToggleSession.tooltipText = Lx.LC_DESC_TOGGLE
        KART.LC.BtnSyncSettings.text:SetText(Lx.LC_BTN_SYNC_SETTINGS)         KART.LC.BtnSyncSettings.tooltipText = Lx.LC_DESC_SYNC_SETTINGS
        KART.LC.BtnTestLooter.text:SetText(Lx.LC_BTN_TEST_LOOTER)             KART.LC.BtnTestLooter.tooltipText = Lx.LC_DESC_TEST_LOOTER
        KART.LC.BtnTestMaster.text:SetText(Lx.LC_BTN_TEST_MASTER)             KART.LC.BtnTestMaster.tooltipText = Lx.LC_DESC_TEST_MASTER
        KART.LC.BtnHistory.text:SetText(Lx.LC_BTN_HISTORY)                    KART.LC.BtnHistory.tooltipText = Lx.LC_DESC_HISTORY
        LC.UpdateRoleStatusLabel() -- reads KART.L live and re-flows the box
        layoutRaidBox() -- German/English label heights differ; re-measure everything
    end)
```

Note: `Lx` (not `L`) — `BuildSettingsPanel` already has `local L = KART.L` at its top; the refresher must read **current** values via `KART.L` at call time. (`local L` inside the function refers to the same stable table after Task 7, but `Lx = KART.L` keeps it explicit and safe.)

- [ ] **Step 2: Verify**

In-game deDE: Loot Council tab fully German incl. the amber raid-wide box; box height correct (no overlapping labels — layoutRaidBox re-ran).

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: locale refresher for the Loot Council settings panel"
```

### Task 11: WoWUtils panel + Droptimizer refreshers

**Files:**
- Modify: `Invite.lua` (end of `WU.BuildPanel`)
- Modify: `Droptimizer.lua` (end of `DT.BuildSyncStatus`)

- [ ] **Step 1: Invite.lua — insert above BuildPanel's closing `end`**

```lua
    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        KART.TabTitles[6]:SetText(Lx.WU_TITLE)
        KART.WU.CbModuleEnabled.text:SetText(Lx.WU_SET_MODULE_ENABLED)
        KART.WU.CbModuleEnabled.tooltipText = Lx.WU_DESC_MODULE_ENABLED
        pasteLabel:SetText(Lx.WU_LABEL_PASTE)
        WU.BtnImport.text:SetText(Lx.WU_BTN_IMPORT)
        WU.BtnReset.text:SetText(Lx.WU_BTN_RESET)
        -- Empty-state texts; SyncSettingsToUI overwrites the status right after these
        -- refreshers run when a saved import auto-parses.
        WU.statusLabel:SetText(Lx.WU_STATUS_EMPTY)
        WU.bossListFrame.emptyLabel:SetText(Lx.WU_STATUS_EMPTY)
        hBoss:SetText("|cffaaaaaa" .. Lx.WU_COL_BOSS .. "|r")
        hInvite:SetText("|cffaaaaaa" .. Lx.WU_BTN_INVITE .. "|r")
        hRemove:SetText("|cffaaaaaa" .. Lx.WU_BTN_REMOVE .. "|r")
    end)
```

- [ ] **Step 2: Droptimizer.lua — insert above BuildSyncStatus's closing `end`**

```lua
    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        if DT.CbModuleEnabled then
            DT.CbModuleEnabled.text:SetText(Lx.DT_SET_MODULE_ENABLED)
            DT.CbModuleEnabled.tooltipText = Lx.DT_DESC_MODULE_ENABLED
        end
        hint:SetText(Lx.DT_HINT_COMPANION)
        DT.RefreshStatusLabel()
    end)
```

- [ ] **Step 3: Verify**

In-game deDE: WoWUtils tab and the Droptimizer toggle/sync-status German.

- [ ] **Step 4: Commit**

```bash
git add Invite.lua Droptimizer.lua
git commit -m "feat: locale refreshers for WoWUtils panel and Droptimizer labels"
```

### Task 12: BuffChecker key-based labels + RaidleadBar tooltips

**Files:**
- Modify: `BuffChecker.lua` (BuffData table, SlotNames, new refresher)
- Modify: `RaidleadBar.lua` (end of file)

- [ ] **Step 1: Add label keys to KART.BuffData**

Each entry keeps its current `label = L.X` / `reportLabel = L.Y` values but additionally stores the key names. Full replacement table:

```lua
KART.BuffData = {
    { id = "int",    labelKey = "BC_LABEL_INT",    col = 2, icon = 135932,  class = "MAGE",    spells = {1459, 264760}, report = "buff", reportLabelKey = "BC_REPORT_INT" },
    { id = "sta",    labelKey = "BC_LABEL_STA",    col = 3, icon = 135987,  class = "PRIEST",  spells = {21562}, report = "buff", reportLabelKey = "BC_REPORT_STA" },
    { id = "motw",   labelKey = "BC_LABEL_MOTW",   col = 4, icon = 136078,  class = "DRUID",   spells = {1126, 384461}, report = "buff", reportLabelKey = "BC_REPORT_MOTW" },
    { id = "shout",  labelKey = "BC_LABEL_SHOUT",  col = 5, icon = 132333,  class = "WARRIOR", spells = {6673}, report = "buff", reportLabelKey = "BC_REPORT_SHOUT" },
    { id = "bronze", labelKey = "BC_LABEL_BRONZE", col = 6, icon = 4622448, class = "EVOKER",  spells = {364343, 381732}, nameMatch = "Bronze", report = "buff", reportLabelKey = "BC_REPORT_BRONZE" },
    { id = "sky",    labelKey = "BC_LABEL_SKY",    col = 7, icon = 4630367, class = "SHAMAN",  spells = {462854}, nameMatch = "Skyfury", report = "buff", reportLabelKey = "BC_REPORT_SKY" },
    { id = "food",   labelKey = "BC_LABEL_FOOD",   col = 8, icon = 134062,  spells = {1232585, 1233713}, isFood = true, report = "item", reportLabelKey = "BC_REPORT_FOOD" },
    { id = "flask",  labelKey = "BC_LABEL_FLASK",  col = 9, icon = 7548903, isFlask = true, report = "item", reportLabelKey = "BC_REPORT_FLASK" },
    { id = "vantus", labelKey = "BC_LABEL_VANTUS", col = 10, icon = 5976918, nameMatch = "Vantus" },
    { id = "rune",   labelKey = "BC_LABEL_RUNE",   col = 11, icon = 4549099, spells = {453112, 1264426}, isRune = true },
    { id = "repair", labelKey = "BC_LABEL_REPAIR", col = 12, isRepair = true },
    { id = "oil",    labelKey = "BC_LABEL_OIL",    col = 3, icon = 7548987, isOil = true, bestSpells = {8052}, wrongSpells = {8051}, page = "advanced" },
    { id = "enchants",labelKey= "BC_LABEL_ENCHANTS",col= 4, isGearCheck = "enchants", page = "advanced" },
    { id = "gems",   labelKey = "BC_LABEL_GEMS",   col = 5, isGearCheck = "gems", page = "advanced" }
}
```

Directly below the table add the resolver + SlotNames builder + refresher registration (replacing the current static `KART.SlotNames = { ... }` block):

```lua
-- label/reportLabel are resolved from keys so a locale change (applied after file load,
-- see KART.RegisterLocaleRefresher) reaches the baked-at-load BuffData table too.
local function ResolveBuffDataLabels()
    for _, d in ipairs(KART.BuffData) do
        d.label = L[d.labelKey]
        if d.reportLabelKey then d.reportLabel = L[d.reportLabelKey] end
    end
end
ResolveBuffDataLabels()

local function BuildSlotNames()
    KART.SlotNames = {
        ["1"] = L.SLOT_HEAD,
        ["2"] = L.SLOT_NECK,
        ["3"] = L.SLOT_SHOULDER,
        ["5"] = L.SLOT_CHEST,
        ["7"] = L.SLOT_LEGS,
        ["8"] = L.SLOT_FEET,
        ["9"] = L.SLOT_WRIST,
        ["10"] = L.SLOT_WAIST,
        ["11"] = L.SLOT_FINGER .. " 1",
        ["12"] = L.SLOT_FINGER .. " 2",
        ["16"] = L.SLOT_WEAPON,
        ["17"] = L.SLOT_OFFHAND,
    }
end
BuildSlotNames()

KART.RegisterLocaleRefresher(function()
    ResolveBuffDataLabels()
    BuildSlotNames()
    -- Window is built lazily (after the refreshers ran), so headers/buttons pick the fresh
    -- labels up at creation; nothing else to re-apply here.
end)
```

Note: `local L = KART.L` at the top of BuffChecker.lua is fine after Task 7 — same table, values swapped in place before the refresher runs.

- [ ] **Step 2: RaidleadBar tooltip refresher — append at end of file**

```lua
-- Bar buttons are created at file load with the pre-locale (English) tooltip strings;
-- re-point them at the selected language once it's known.
KART.RegisterLocaleRefresher(function()
    local tips = {
        KART_RL_ClearWorldMarkersBtn = KART.L.RL_CLEAR_WM,
        KART_RL_ReadyCheckBtn        = KART.L.RL_READYCHECK,
        KART_RL_BuffCheckToggleBtn   = KART.L.RL_BUFFCHECK,
        KART_RL_PullTimerBtn         = KART.L.RL_PULL_TIMER,
    }
    for btnName, tip in pairs(tips) do
        local btn = _G[btnName]
        if btn then btn.tooltipText = tip end
    end
    if KART.PullBtn and KART.PullBtn.text then KART.PullBtn.text:SetText(KART.L.RL_PULL_LABEL) end
end)
```

- [ ] **Step 3: Verify**

In-game deDE: Buff-Checker window column headers German ("Ausd", "Essen"…), report chat lines German; Raidlead bar tooltips German. Switch to enUS → English.

- [ ] **Step 4: Commit**

```bash
git add BuffChecker.lua RaidleadBar.lua
git commit -m "feat: key-based BuffChecker labels + RaidleadBar tooltip locale refresh"
```

### Task 13: Language matrix verification + changelog (Block 2 gate)

**Files:**
- Modify: `CHANGELOG.md`, `CHANGELOG-de.md`

- [ ] **Step 1: Manual verification matrix (deDE client)**

| Setting | Expectation |
|---|---|
| `language = "Auto"` | Entire UI German (tabs, all 6 tab bodies, tooltips, BuffChecker headers, Raidlead tooltips, popups) |
| `language = "enUS"` | Entire UI English after reload |
| `language = "deDE"` | Entire UI German after reload |

Also: vote window + council panel via "Test: Looter"/"Test: Lootmaster" in both languages; Loot History window; trade reminder titles (`/kart trade` with a pending test is not possible — verified via a later raid test instead, they read `KART.L` lazily).

- [ ] **Step 2: Changelog**

`CHANGELOG.md`:

```markdown
- **The whole UI now follows the language setting** — main window, settings and tooltips included.
```

`CHANGELOG-de.md`:

```markdown
- **Die gesamte Oberfläche folgt jetzt der Spracheinstellung** — inklusive Hauptfenster, Einstellungen und Tooltips.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog for locale system rework"
```

---

# Block 3 — Loot Council behavior (W4, M5, W3, M11, M10)

### Task 14: Lootmaster force-win rules (W4, maintainer-refined)

Decided behavior (maintainer, 2026-07-23): the lootmaster force-wins **only** items that are (a) at/above the raid minimum quality, (b) **not** Miscellaneous collectibles (classID 15: pets, toys, mounts, housing), and (c) **Bind-on-Pickup**. Everything else (trash below threshold, collectibles, BoE/non-binding items) the lootmaster **always passes — unconditionally, regardless of their own Auto-Pass setting** ("immer passen, wenn ich Lootmaster bin").

**Files:**
- Modify: `LootCouncil.lua` `LC.OnStartLootRoll` (~lines 766–822)

**Interfaces:**
- Consumes: `GetLootRollItemInfo(rollID)` 5th return `bindOnPickUp` (available without item cache, unlike `C_Item.GetItemInfo`); `C_Item.GetItemInfoInstant(itemLink)` 6th return `classID` (also cache-independent).

- [ ] **Step 1: Restructure the head of OnStartLootRoll**

Replace everything from `local lootmaster = LC.GetLootmaster()` down to (and including) the quality-gate block `if quality and quality < minQuality and classID ~= 15 then return end` with:

```lua
    -- Quality/bind data first — the lootmaster branch below depends on it. bindOnPickUp comes
    -- from GetLootRollItemInfo (reliable even for uncached items); classID via GetItemInfoInstant
    -- for the same reason (GetItemInfo returns nil until the item is cached).
    local _, _, _, quality, bindOnPickUp = GetLootRollItemInfo(rollID)
    local itemLink = GetLootRollItemLink(rollID)
    local classID = LC.IsRealItemLink(itemLink) and select(6, C_Item.GetItemInfoInstant(itemLink))
    -- Miscellaneous (classID 15: toys, pets, mounts, housing decor): never rarity-gated, since
    -- it's virtually always Common/Uncommon regardless of how desirable it is.
    local isCollectible = (classID == 15)
    local councilEngages = isCollectible or not (quality and quality < LC.GetRaidMinQuality())

    local lootmaster = LC.GetLootmaster()
    local isLootmaster = LC.IsMe(lootmaster)
    if isLootmaster and councilEngages and bindOnPickUp and not isCollectible then
        -- The lootmaster only needs to physically win items they must later hand out through
        -- Blizzard's 2-hour BoP trade window: council-relevant, BoP, non-collectible gear.
        ForceWinRoll(rollID)
        -- Blizzard's 2-hour Bind-on-Pickup trade window starts now, not whenever Council later
        -- decides a winner — see LC.CheckTradeTimeouts, which measures from this timestamp.
        LC.rollLootedAt = LC.rollLootedAt or {}
        LC.rollLootedAt[rollID] = GetTime()
    elseif isLootmaster then
        -- Everything the lootmaster does NOT force-win (collectibles, BoE/non-binding items,
        -- sub-threshold drops) they ALWAYS pass — deliberately independent of their own
        -- Auto-Pass setting, so those items cleanly go to the raid's normal rolls instead of
        -- silently piling up in the lootmaster's bags.
        RollOnLoot(rollID, 0)
    elseif KART_Settings.lcAutoPass then
        -- Auto-Pass is a personal preference and is intentionally independent of the raid's
        -- min-quality setting (that setting only gates whether Council itself engages).
        RollOnLoot(rollID, 0)
    end

    -- Below the raid-wide minimum rarity (and not a collectible): let Blizzard's own roll UI
    -- handle it, untouched.
    if not councilEngages then return end
```

The lines that previously computed `quality`/`minQuality`/`itemLink`/`classID` further down are now gone; the code continues with `local newItemID = ...` unchanged.

- [ ] **Step 2: Verify**

Grep: `grep -n "bindOnPickUp\|councilEngages" LootCouncil.lua` → only in the new block.
Grep: `grep -n "select(12, C_Item.GetItemInfo(itemLink))" LootCouncil.lua` → no hits.
In-game (raid test later): lootmaster passes on a BoE and on a pet drop **even with their own Auto-Pass disabled**, force-wins a BoP epic.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: lootmaster force-wins only council-relevant BoP gear (passes trash, collectibles, BoEs)"
```

### Task 15: Raid-only session toggle (M5)

**Files:**
- Modify: `LootCouncil.lua` (BtnToggleSession OnClick, ~line 1319)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

- [ ] **Step 1: Locale key**

enUS, below `LC_NOT_LEADER`:

```lua
    LC_RAID_ONLY           = "Loot Council only works in raid groups.",
```

deDE, same spot:

```lua
    LC_RAID_ONLY           = "Loot Council funktioniert nur in Schlachtzugsgruppen.",
```

- [ ] **Step 2: Gate the toggle on IsInRaid**

Replace the OnClick body:

```lua
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if not IsInRaid() then
            print("|cff00ff00KART:|r " .. KART.L.LC_RAID_ONLY)
        elseif UnitIsGroupLeader("player") then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)
```

- [ ] **Step 3: Verify**

In-game: solo/party click → raid-only message; raid leader click → toggles as before.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "fix: Loot Council session toggle is raid-only (matches CheckRaidJoin's session reset)"
```

### Task 16: Sender validation for unauthenticated LC messages (W3)

Rule set: `LC_ACTIVE` + `LC_START` accepted only from the current group leader; `LC_MANUAL_START` only from the designated lootmaster (clients without a synced raid config have lootmaster `""` and reject — acceptable, the state request on join fetches the config); `LC_HIST_ENTRY` only from someone currently in our group. `LC_HIST_REQ`, `LC_SYNC_ACCEPT/DECLINE` stay open (read-only/print-only).

**Files:**
- Modify: `Core.lua` (CHAT_MSG_ADDON dispatch lines for the four messages)
- Modify: `LootCouncil.lua` (`LC.HandleActive`, `LC.HandleStart`, `LC.HandleManualStart`)
- Modify: `LootHistory.lua` (`LH.HandleHistoryEntry`)

- [ ] **Step 1: Pass the resolved sender key in Core.lua**

```lua
                elseif msg:sub(1, 10) == "LC_ACTIVE:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleActive(msg:sub(11), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 9) == "LC_START:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleStart(msg:sub(10), (KART.Identity.ResolvePlayer(sender))) end
                elseif msg:sub(1, 16) == "LC_MANUAL_START:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleManualStart(msg:sub(17), (KART.Identity.ResolvePlayer(sender))) end
```

and:

```lua
                elseif msg:sub(1, 14) == "LC_HIST_ENTRY:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LH.HandleHistoryEntry(msg:sub(15), (KART.Identity.ResolvePlayer(sender))) end
```

- [ ] **Step 2: Guard the handlers**

`LootCouncil.lua` — add a shared local above `LC.HandleActive`:

```lua
-- Sender-authorization helper for messages that carry raid-wide authority: resolving to a
-- live unit first (rather than trusting the key alone) matters because CHAT_MSG_ADDON also
-- delivers whispers — someone not currently in our group is never authorized.
local function IsSenderGroupLeader(senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    return unit ~= nil and UnitIsGroupLeader(unit)
end

function LC.HandleActive(value, senderKey)
    -- Only the raid leader may flip the session flag — otherwise any group member could
    -- toggle Loot Council on/off for the whole raid with a forged LC_ACTIVE.
    if not IsSenderGroupLeader(senderKey) then return end
    LC.sessionActive = (value == "1")
end
```

`LC.HandleStart` — first lines become:

```lua
function LC.HandleStart(payload, senderKey)
    -- Only the leader broadcasts LC_START (see OnStartLootRoll) — reject forgeries that
    -- would pop fake vote windows on every client.
    if not IsSenderGroupLeader(senderKey) then return end
    -- payload = "rollID:seconds:itemID"
```

`LC.HandleManualStart` — first lines become:

```lua
function LC.HandleManualStart(payload, senderKey)
    -- Only the designated lootmaster legitimately sends manual rolls (see LC.StartManualRoll).
    -- A client without a synced raid config has lootmaster == "" and rejects — the state
    -- request on raid join (LC_STATE_REQ) closes that gap.
    local lootmaster = LC.GetLootmaster()
    if lootmaster == "" or senderKey ~= lootmaster then return end
```

`LootHistory.lua`:

```lua
function LH.HandleHistoryEntry(payload, senderKey)
    -- Catch-up entries land in the permanent loot history — only accept them from someone
    -- actually in our current group, not from arbitrary whispers.
    if not (senderKey and KART.Identity.FindUnitForKey(senderKey)) then return end
```

- [ ] **Step 3: Verify**

Grep: `grep -n "HandleActive(msg\|HandleStart(msg\|HandleManualStart(msg\|HandleHistoryEntry(msg" Core.lua` → all four pass the resolved sender.
In-game raid test: normal session start/roll flow unchanged (leader path); history catch-up on rejoin still works.

- [ ] **Step 4: Commit**

```bash
git add Core.lua LootCouncil.lua LootHistory.lua
git commit -m "fix: validate sender authority for LC_ACTIVE/LC_START/LC_MANUAL_START/LC_HIST_ENTRY"
```

### Task 17: Strip colons from synced free-text fields (M11)

**Files:**
- Modify: `LootCouncil.lua` (the three raid-wide edit boxes in BuildSettingsPanel)

- [ ] **Step 1: Add the sanitizer local (above BuildSettingsPanel)**

```lua
-- Colons are the LC_CONFIG/LC_SYNC payload separator (see LC.BroadcastRaidConfig) — a colon
-- inside any synced free-text field would make the receivers' payload pattern silently fail,
-- leaving every other client stuck on stale config. Strip them at input time.
local function StripColons(editBox)
    local text = editBox:GetText()
    if text:find(":", 1, true) then
        editBox:SetText((text:gsub(":", ""))) -- re-fires OnTextChanged with the clean text
        return true
    end
    return false
end
```

- [ ] **Step 2: Use it in the three OnTextChanged handlers**

ButtonLabelEditBox:

```lua
    eb:SetScript("OnTextChanged", function(self)
        if StripColons(self) then return end
        KART_Settings.lcButtonLabels = self:GetText()
        LC.BroadcastRaidConfig()
    end)
```

CouncilMembersEditBox (same pattern, keeps `LC.UpdateCouncilCache()` until Task 28 renames it) and LootmasterEditBox (same pattern with `LC.BroadcastRaidConfig()`).

- [ ] **Step 3: Verify**

In-game: type `BIS:test` into the vote-buttons field → colon disappears immediately, saved value has no colon.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua
git commit -m "fix: strip colons from synced Loot Council text fields (payload separator collision)"
```

### Task 18: Localized default vote-button labels (M10)

**Files:**
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`
- Modify: `Core.lua` (ADDON_LOADED, after the locale copy)
- Modify: `LootCouncil.lua` (`LC.GetButtonConfig` fallbacks)

- [ ] **Step 1: Locale keys**

enUS (Loot Council section):

```lua
    LC_DEFAULT_BUTTONS     = "BIS;Upgrade;Offspec;Other;Pass",
```

deDE:

```lua
    LC_DEFAULT_BUTTONS     = "BIS;Upgrade;Offspec;Sonstiges;Pass",
```

- [ ] **Step 2: Core.lua — localize the default before the Defaults merge**

Directly after the locale-copy block (Task 7) and **before** the Defaults merge loop, add:

```lua
        -- The default vote-button set is user-visible text — pick it from the active locale
        -- before the Defaults merge fills a fresh KART_Settings.
        KART.Defaults.lcButtonLabels = KART.L.LC_DEFAULT_BUTTONS
```

- [ ] **Step 3: LC.GetButtonConfig fallbacks**

Replace the `raw` selection:

```lua
    if UnitIsGroupLeader("player") or not (LC.raidConfig and LC.raidConfig.buttonLabels) then
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or KART.L.LC_DEFAULT_BUTTONS
    else
        raw = LC.raidConfig.buttonLabels
    end
```

Replace the hardcoded `if #result == 0 then result = { ... } end` list with:

```lua
    if #result == 0 then
        for i, label in ipairs(KART.SplitString(KART.L.LC_DEFAULT_BUTTONS, ";")) do
            local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
            table.insert(result, {label = label, r = col.r, g = col.g, b = col.b})
        end
    end
```

Note: `Utils.lua`'s `lcButtonLabels = "BIS;Upgrade;Offspec;Sonstiges;Pass"` literal stays as the pre-locale placeholder; add the comment `-- placeholder; localized in Core.lua ADDON_LOADED via LC_DEFAULT_BUTTONS` on that line.

- [ ] **Step 4: Verify**

`/run KART_Settings.lcButtonLabels = nil KART_Settings.language = "enUS" ReloadUI()` → vote-buttons field shows "BIS;Upgrade;Offspec;Other;Pass". Same with `deDE` → "…Sonstiges…".

- [ ] **Step 5: Commit**

```bash
git add Core.lua LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: localize the default vote-button labels"
```

### Task 19: Block 3 changelog

- [ ] **Step 1: Entries**

`CHANGELOG.md`:

```markdown
- **The lootmaster no longer force-wins trash, collectibles or BoE items** — only council-relevant BoP gear.
- **Loot Council is now explicitly raid-only.**
- **Session, roll-start and history-sync messages are now sender-verified.**
```

`CHANGELOG-de.md`:

```markdown
- **Der Lootmaster gewinnt nicht mehr automatisch Trash, Sammelobjekte oder BoE-Items** — nur noch Council-relevante BoP-Gegenstände.
- **Loot Council ist jetzt ausdrücklich Raid-only.**
- **Session-, Roll-Start- und History-Sync-Nachrichten werden jetzt auf ihren Absender geprüft.**
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog for block 3"
```

---

# Block 4 — Minor bug fixes (M1, M2, M3, M6, M7, M8, M9)

### Task 20: Trade/owed reminder stray done-buttons (M1)

**Files:**
- Modify: `LootCouncilTrade.lua:260` and `LootCouncilTrade.lua:383`

- [ ] **Step 1: Parent doneBtn to the row (both reminder windows)**

In `Trade.RefreshTradeReminder` and `Trade.RefreshOwedReminder`, change:

```lua
            row.doneBtn = CreateFrame("Button", nil, f)
```

to:

```lua
            row.doneBtn = CreateFrame("Button", nil, row) -- child of row so it hides with it
```

(Task 34 later merges both windows into one builder — it must keep this parenting.)

- [ ] **Step 2: Verify**

Grep: `grep -n "doneBtn = CreateFrame" LootCouncilTrade.lua` → both say `, row)`.
In-game (raid test): with 2 pending trades, mark one done → no floating checkmark remains.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilTrade.lua
git commit -m "fix: reminder done-buttons hide with their row (were parented to the window)"
```

### Task 21: Cross-realm trade partner name cleanup (M2)

**Files:**
- Modify: `LootCouncilTrade.lua:508-515` (`Trade.OnTradeShow`)

- [ ] **Step 1: Replace the manual "(*)" strip**

Replace:

```lua
        if partnerName and partnerName:find("(*)", 1, true) then
            partnerName = partnerName:sub(1, -4)
        end
```

with:

```lua
        -- Blizzard renders a foreign-realm partner as "Name (*)" — the old sub(1, -4) kept the
        -- separating space, which made every downstream name match fail silently.
        if partnerName then
            partnerName = KART.TrimString(partnerName:gsub("%(%*%)", ""))
        end
```

- [ ] **Step 2: Verify**

Grep: `grep -n 'sub(1, -4)' LootCouncilTrade.lua` → no hits.
`/run print("["..KART.TrimString(("Name (*)"):gsub("%(%*%)","")).."]")` → prints `[Name]`.

- [ ] **Step 3: Commit**

```bash
git add LootCouncilTrade.lua
git commit -m "fix: trim cross-realm '(*)' marker cleanly so auto-trade matches the partner"
```

### Task 22: Minimap table identity across profile loads (M3)

**Files:**
- Modify: `Profiles.lua` (`KART.LoadProfile`)

- [ ] **Step 1: Preserve the registered minimap table**

Replace `KART.LoadProfile` with:

```lua
function KART.LoadProfile(name)
    local snapshot = KART_Profiles[name]
    if not snapshot then return end
    -- LibDBIcon holds a REFERENCE to the minimap sub-table it was registered with (Core.lua
    -- ADDON_LOADED) — keep that table's identity across profile loads, otherwise icon position
    -- changes are written into an orphaned table until the next reload.
    local minimapTbl = KART_Settings.minimap
    wipe(KART_Settings)
    for k, v in pairs(KART.DeepCopy(snapshot)) do
        KART_Settings[k] = v
    end
    for k, v in pairs(KART.Defaults) do
        if KART_Settings[k] == nil then
            KART_Settings[k] = type(v) == "table" and KART.DeepCopy(v) or v
        end
    end
    if minimapTbl then
        local loaded = KART_Settings.minimap
        wipe(minimapTbl)
        if type(loaded) == "table" then
            for k, v in pairs(loaded) do minimapTbl[k] = v end
        end
        KART_Settings.minimap = minimapTbl
    end
    KART_Settings.activeProfile = name
    KART.SyncSettingsToUI()
end
```

- [ ] **Step 2: Verify**

In-game: load a profile, drag the minimap icon, `/reload` → position survives.

- [ ] **Step 3: Commit**

```bash
git add Profiles.lua
git commit -m "fix: keep LibDBIcon's minimap table identity across profile loads"
```

### Task 23: Search popout respects the window-layer setting (M6)

**Files:**
- Modify: `MainFrame.lua:654`

- [ ] **Step 1: Register as dialog instead of hardcoding DIALOG**

Replace:

```lua
searchPopout:SetFrameStrata("DIALOG")
```

with:

```lua
KART.RegisterStrataFrame(searchPopout, true) -- one stratum above the windows, follows the setting
```

- [ ] **Step 2: Verify**

In-game: set Window Layer slider to FULLSCREEN_DIALOG → search popout still opens **above** the main window.

- [ ] **Step 3: Commit**

```bash
git add MainFrame.lua
git commit -m "fix: search popout follows the configurable window layer instead of fixed DIALOG"
```

### Task 24: UnitName nil guard in BuffChecker (M7)

**Files:**
- Modify: `BuffChecker.lua:634`

- [ ] **Step 1: Fallback for nil names**

Replace:

```lua
        local nameStr = UnitName(unit)
```

with:

```lua
        local nameStr = UnitName(unit) or UNKNOWN -- roster churn can briefly yield nil; UNKNOWN is Blizzard's "Unknown"
```

- [ ] **Step 2: Verify**

Grep: `grep -n "UnitName(unit) or UNKNOWN" BuffChecker.lua` → one hit. All later `nameStr:match` calls are now nil-safe.

- [ ] **Step 3: Commit**

```bash
git add BuffChecker.lua
git commit -m "fix: guard BuffChecker row update against nil UnitName during roster churn"
```

### Task 25: Secure macro buttons fire once per click (M8)

**Files:**
- Modify: `RaidleadBar.lua` (`CreateBarButton`)

- [ ] **Step 1: Register clicks per button type**

Remove the early `b:RegisterForClicks("AnyUp", "AnyDown")` line and change the macro/func branch to:

```lua
    if macrotext then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", macrotext)
        -- Secure buttons execute on EVERY registered click transition — registering both Up
        -- and Down ran the macro twice per click. Down-only matches retail's default behavior.
        b:RegisterForClicks("AnyDown")
    else
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetScript("OnClick", func)
    end
```

- [ ] **Step 2: Verify**

In-game: click a raid-marker button once → marker set once (watch for set-then-instant-reset flicker: gone). Ready-check button fires a single check. Pull-timer + Buff-Checker buttons (Lua handlers) unchanged. Keybinds (Task list: readyCheck, clearWorldMarkers) still trigger.

- [ ] **Step 3: Commit**

```bash
git add RaidleadBar.lua
git commit -m "fix: secure macro bar buttons no longer double-fire (down-click only)"
```

### Task 26: Stagger history-sync replies (M9)

**Files:**
- Modify: `LootHistory.lua:707-720` (`LH.HandleHistoryRequest` reply loop)

- [ ] **Step 1: Spread the burst**

Replace the reply timer block:

```lua
    C_Timer.After(math.random() * 2, function()
        for _, e in ipairs(toSend) do
            ...
            C_ChatInfo.SendAddonMessage("KART", msg, "WHISPER", senderFullName)
        end
    end)
```

with:

```lua
    -- Random base delay de-collides multiple answering peers; the per-entry 0.2s spacing keeps
    -- a 30-entry reply under the client's addon-message throttle instead of bursting one frame.
    local baseDelay = math.random() * 2
    for i, e in ipairs(toSend) do
        C_Timer.After(baseDelay + (i - 1) * 0.2, function()
            local colorPacked = ""
            if e.color then
                colorPacked = string.format("%d,%d,%d",
                    math.floor(e.color.r * 255), math.floor(e.color.g * 255), math.floor(e.color.b * 255))
            end
            -- itemLink is last on purpose: item links are full of colons internally.
            local msg = string.format("LC_HIST_ENTRY:%d:%s:%s:%s:%s:%s:%s",
                e.time or 0, e.winner or "", e.difficulty or "", e.reason or "", e.class or "", colorPacked, e.item or "")
            C_ChatInfo.SendAddonMessage("KART", msg, "WHISPER", senderFullName)
        end)
    end
```

- [ ] **Step 2: Verify**

Grep: `grep -n "baseDelay" LootHistory.lua` → present; the old single `C_Timer.After(math.random() * 2` wrapper gone.

- [ ] **Step 3: Commit**

```bash
git add LootHistory.lua
git commit -m "fix: stagger loot-history sync replies to stay under the addon-message throttle"
```

### Task 27: Block 4 changelog

- [ ] **Step 1: Entries**

`CHANGELOG.md`:

```markdown
- **Fixed auto-trade for cross-realm winners.**
- **Minimap icon position now saves correctly after switching profiles.**
- **Raid-marker bar buttons no longer fire twice per click.**
- **Fixed a leftover checkmark button when clearing trade reminders.**
```

`CHANGELOG-de.md`:

```markdown
- **Auto-Trade für Cross-Realm-Gewinner repariert.**
- **Minimap-Icon-Position wird nach Profilwechsel wieder korrekt gespeichert.**
- **Raid-Marker-Buttons lösen nicht mehr doppelt pro Klick aus.**
- **Übriggebliebener Haken-Button beim Abhaken von Trade-Erinnerungen behoben.**
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog for block 4"
```

---

# Block 5 — Dead code removal (T2–T10)

### Task 28: Small removals (T2, T6, T7, T8, T9, T10)

**Files:**
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (drop `ADDON_TITLE`)
- Modify: `BuffChecker.lua:90` (offsets)
- Modify: `LootCouncilVote.lua:426` (badge cap)
- Modify: `LootCouncil.lua` + `Core.lua` (UpdateCouncilCache alias)
- Modify: `LootCouncilPanel.lua` (header SetShown hoist)
- Modify: `Core.lua` (REQ_ILVL/REQ_GEAR group guard)

- [ ] **Step 1: T2 — delete `ADDON_TITLE = ...` from both locale files** (never referenced).

- [ ] **Step 2: T6 — trim the unused offset**

`BuffChecker.lua`: `local offsets = {35, 145, 185, 225, 265, 310, 355, 395, 445, 495, 545, 590, 635}` → remove the trailing `, 635` (max used col is 12).

- [ ] **Step 3: T7 — un-stale the voted-badge width cap**

`LootCouncilVote.lua` (Spacious renderer): replace

```lua
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, 329))
```

with

```lua
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, CONTENT_W - MARGIN * 2))
```

- [ ] **Step 4: T8 — remove the UpdateCouncilCache alias**

Delete `LC.UpdateCouncilCache` (LootCouncil.lua:150-152). Replace its two call sites:
- `Core.lua:50`: `if KART.LC and KART.LC.UpdateCouncilCache then KART.LC.UpdateCouncilCache() end` → `if KART.LC and KART.LC.BroadcastRaidConfig then KART.LC.BroadcastRaidConfig() end`
- `LootCouncil.lua` CouncilMembersEditBox OnTextChanged: `LC.UpdateCouncilCache()` → `LC.BroadcastRaidConfig()`

- [ ] **Step 5: T9 — hoist per-row header toggles**

`LootCouncilPanel.lua` `RefreshCouncilRows`: move these two lines out of the member loop, placing them right after `local itemArmorRank = ...` near the top (compute `local rollsEnabled = LC.GetRollsEnabled()` and `local dtEnabled = KART_Settings.dtModuleEnabled ~= false` there too, and delete the in-loop duplicates):

```lua
    if panel.hRoll then panel.hRoll:SetShown(rollsEnabled) end
    if panel.hGain then panel.hGain:SetShown(dtEnabled) end
```

The loop keeps using the hoisted `rollsEnabled`/`dtEnabled` locals.

- [ ] **Step 6: T10 — group guard on sync replies**

`Core.lua` REQ_ILVL / REQ_GEAR branches: wrap the `C_ChatInfo.SendAddonMessage(...)` calls in `if IsInGroup() then ... end` (mirrors the REQ_OIL branch).

- [ ] **Step 7: Verify**

Greps: `grep -rn "ADDON_TITLE\|UpdateCouncilCache" *.lua Locales/*.lua` → no hits. `grep -n "329" LootCouncilVote.lua` → no badge-cap hit. In-game `/reload` → council test panel renders, Buff-Checker renders.

- [ ] **Step 8: Commit**

```bash
git add Locales/enUS.lua Locales/deDE.lua BuffChecker.lua LootCouncilVote.lua LootCouncil.lua LootCouncilPanel.lua Core.lua
git commit -m "chore: remove dead locale key, alias, stale constants; hoist header toggles; guard sync replies"
```

### Task 29: Roll-state + player-cache hygiene (T4, T5)

**Files:**
- Modify: `LootCouncilTrade.lua` (`Trade.ClearRollState`)
- Modify: `Core.lua` (ADDON_LOADED, after `KART_PlayerCache` init)

- [ ] **Step 1: T4 — clear rollLootedAt with the rest of the roll state**

Add to `Trade.ClearRollState`:

```lua
    if LC.rollLootedAt then LC.rollLootedAt[rollID] = nil end
```

- [ ] **Step 2: T5 — prune the player cache on login**

In `Core.lua` after `KART_PlayerCache = KART_PlayerCache or {}`:

```lua
        -- Prune identity-cache entries not seen for 90+ days so the SavedVariable doesn't
        -- grow forever (it gains one entry per distinct group member ever encountered).
        local pruneCutoff = time() - 90 * 24 * 60 * 60
        for guid, entry in pairs(KART_PlayerCache) do
            if (entry.lastSeen or 0) < pruneCutoff then KART_PlayerCache[guid] = nil end
        end
```

- [ ] **Step 3: Verify**

Grep: `grep -n "rollLootedAt" LootCouncilTrade.lua` → ClearRollState hit present. `/reload` clean.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilTrade.lua Core.lua
git commit -m "chore: clear rollLootedAt with roll state, prune stale player-cache entries"
```

### Task 30: Remove dead locale fallbacks (T3)

**Files:**
- Modify: all `*.lua` with literal-key fallbacks

Rule: `KART.L.SOME_KEY or "literal"` (and `L.SOME_KEY or "literal"`) is dead when `SOME_KEY` is a **literal** key — enUS fills `KART.L` at load, so the key always exists. **Keep** dynamic lookups (`KART.L["LC_QUALITY_" .. q] or ...`, `KART.L["LC_VOTED_DISPLAY_" .. mode] or ...`) — those compose keys at runtime.

- [ ] **Step 1: List all candidates**

Run: `grep -rnE '(KART\.L|[^%w]L)\.[A-Z][A-Z0-9_]+ or "' *.lua`

- [ ] **Step 2: Remove the `or "..."` part at every literal-key hit**

Example (Core.lua):

```lua
print(string.format(KART.L.UPDATE_AVAILABLE or "|cff00ff00KART:|r Ein Update ist verfügbar! ...", ver, KART.Version))
```

becomes

```lua
print(string.format(KART.L.UPDATE_AVAILABLE, ver, KART.Version))
```

Example (Invite.lua):

```lua
print("|cff00ff00KART:|r " .. (KART.L.WU_MSG_NOT_LEADER or "Only group leaders can invite players."))
```

becomes

```lua
print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
```

Apply file by file (Core, MainFrame, BuffChecker, Invite, LootCouncil*, LootHistory, Droptimizer). Do **not** touch the two dynamic-key sites (`LC.QualityLabel`, `LC.VotedItemDisplayLabel`).

- [ ] **Step 3: Verify**

Re-run the grep from Step 1 → only the two dynamic-key composition sites remain.
In-game `/reload` in both languages → no nil-concat errors anywhere (open every tab, Buff-Checker, history, test panels).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: drop dead 'or fallback' strings — enUS base guarantees every literal key"
```

---

# Block 6 — Simplifications (S1–S10, T11 folded into S5)

### Task 31: Shared group-unit iterator (S1)

**Files:**
- Modify: `Utils.lua` (new `KART.EachGroupUnit`)
- Modify: `Identity.lua` (drop local copy)
- Modify: `GroupLogic.lua` (`KART.HandleAutoPromote`)
- Modify: `LootCouncilPanel.lua` (`RefreshCouncilRows` members loop)
- Modify: `Invite.lua` (`WU.InviteBoss`, `WU.RemoveForBoss`)
- Modify: `LootCouncil.lua` (`LC.StartTest` pre-fill loop)

**Interfaces:**
- Produces: `KART.EachGroupUnit()` — generic-for iterator returning `unit, index` per current group member (raid: `raid1..N`; party: `party1..N-1` plus `player` last; empty group: nothing).

- [ ] **Step 1: Add the iterator to Utils.lua (below KART.HasGroupPermissions)**

```lua
-- Iterates every current raid/party unit token, including the player. Returns (unit, index)
-- so callers that pool rows by position keep their index. Yields nothing when not in a group.
function KART.EachGroupUnit()
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    local i = 0
    return function()
        i = i + 1
        if i > numMem then return nil end
        return (isRaid and ("raid" .. i) or (i == numMem and "player" or "party" .. i)), i
    end
end
```

- [ ] **Step 2: Identity.lua — delete the local `EachGroupUnit` and its "kept as its own local copy" comment; replace both uses (`FindUnitForName`, `Identity.FindUnitForKey`) with `for unit in KART.EachGroupUnit() do`.**

- [ ] **Step 3: GroupLogic.lua — HandleAutoPromote loop**

Replace:

```lua
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()

    for i = 1, numMembers do
        local unit = isRaid and ("raid"..i) or (i == numMembers and "player" or "party"..i)
```

with:

```lua
    for unit in KART.EachGroupUnit() do
```

(and remove the now-unused locals; the closing `end` count drops by zero — the `for` body is otherwise unchanged).

- [ ] **Step 4: LootCouncilPanel.lua — members loop**

Replace:

```lua
    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
```

with:

```lua
    local members = {}
    for unit in KART.EachGroupUnit() do
        local fullName = UnitName(unit)
```

`numMem` stays (used by CountVotes denominator / councilVoteBtn fill); `isRaid` becomes unused → delete its local.

- [ ] **Step 5: Invite.lua — both roster scans**

`WU.InviteBoss`:

```lua
    local alreadyIn = {}
    for unit in KART.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local full = (realm and realm ~= "") and (name.."-"..realm) or name
            alreadyIn[full:lower()] = true
            alreadyIn[name:lower()] = true
        end
    end
```

`WU.RemoveForBoss`:

```lua
    local removed = 0
    for unit in KART.EachGroupUnit() do
        if unit ~= "player" then
            local name, realm = UnitName(unit)
            if name then
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                if not keepSet[full:lower()] and not keepSet[name:lower()] then
                    UninviteUnit(name)
                    removed = removed + 1
                end
            end
        end
    end
```

(delete the superseded `isRaid`/`numMem` locals in both.)

- [ ] **Step 6: LootCouncil.lua — StartTest pre-fill**

Replace:

```lua
            if IsInGroup() then
                local isRaid  = IsInRaid()
                local numMem  = GetNumGroupMembers()
                local voteIdx = itemIdx -- offset per item so the fake votes aren't identical across items
                for i = 1, numMem do
                    local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
                    local name = UnitName(unit)
```

with:

```lua
            if IsInGroup() then
                local voteIdx = itemIdx -- offset per item so the fake votes aren't identical across items
                for unit in KART.EachGroupUnit() do
                    local name = UnitName(unit)
```

**Not converted:** `BuffChecker.lua`'s loop (solo fallback + fixed 40-row pool semantics differ deliberately — keep as is).

- [ ] **Step 7: Verify**

Grep: `grep -rn '"raid"\.\.i\|("raid" \.\. i)' *.lua` → only BuffChecker.lua and Utils.lua remain.
In-game: Test-Lootmaster in a group → rows for all members; WU invite/remove smoke test; auto-promote unchanged.

- [ ] **Step 8: Commit**

```bash
git add Utils.lua Identity.lua GroupLogic.lua LootCouncilPanel.lua Invite.lua LootCouncil.lua
git commit -m "refactor: shared KART.EachGroupUnit iterator replaces five copies of the roster loop"
```

### Task 32: Shared item-link helpers (S2)

**Files:**
- Modify: `Utils.lua` (new helpers)
- Modify: `LootCouncil.lua` (`LC.IsRealItemLink` becomes alias)
- Modify: `LootHistory.lua` (drop local `IsRealItemLink`/`GetItemStringFromLink`)
- Modify: `LootCouncilTrade.lua` (drop local `GetItemString`)

**Interfaces:**
- Produces: `KART.IsRealItemLink(link) -> boolean`, `KART.GetItemString(link) -> "item:..."|nil` (full bonus-ID-aware item string).

- [ ] **Step 1: Utils.lua — add below KART.SplitString**

```lua
-- Test mode uses plain coloured strings as fake items; guard against SetHyperlink on non-links.
function KART.IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Full item string (itemID + every bonus ID), not just the bare itemID — two drops can share
-- an itemID while being different variants, and comparing only itemID would treat them as
-- interchangeable (see the auto-trade and history-export call sites).
function KART.GetItemString(link)
    return KART.IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
end
```

- [ ] **Step 2: LootCouncil.lua — replace the function body with an alias**

```lua
LC.IsRealItemLink = KART.IsRealItemLink -- kept as LC.* alias; call sites across the LC modules use this name
```

(delete the old `function LC.IsRealItemLink(link) ... end`.)

- [ ] **Step 3: LootHistory.lua — delete the local `IsRealItemLink` and `GetItemStringFromLink`; replace uses:** `IsRealItemLink(` → `KART.IsRealItemLink(`, `GetItemStringFromLink(link)` → `(KART.GetItemString(link) or "")` (the JSON export expects `""`, not nil).

- [ ] **Step 4: LootCouncilTrade.lua — delete the local `GetItemString`; replace its uses with `KART.GetItemString`.**

- [ ] **Step 5: Verify**

Grep: `grep -rn "local function IsRealItemLink\|local function GetItemString\|GetItemStringFromLink" *.lua` → no hits.
In-game: history window renders, JSON export produces the same output as before for an entry with and without a real link.

- [ ] **Step 6: Commit**

```bash
git add Utils.lua LootCouncil.lua LootHistory.lua LootCouncilTrade.lua
git commit -m "refactor: single KART.IsRealItemLink/GetItemString instead of three copies"
```

### Task 33: Vote.CastVote extracted (S3)

**Files:**
- Modify: `LootCouncilVote.lua`

- [ ] **Step 1: Add above RefreshVoteListRows_Spacious**

```lua
-- Shared click path for both layouts' vote buttons. Test rolls stay local (no group to
-- broadcast to — see the original comment in the Spacious handler); real rolls broadcast.
function Vote.CastVote(rollID, buttonIdx, noteBox)
    if LC.votedByMe[rollID] then return end
    LC.votedByMe[rollID] = buttonIdx
    local note = KART.TrimString(noteBox and noteBox:GetText() or "")
    LC.votedNoteByMe[rollID] = note
    if LC.IsTestRoll(rollID) then
        local myKey = (KART.Identity.ResolvePlayer("player"))
        LC.votes[rollID] = LC.votes[rollID] or {}
        LC.votes[rollID][myKey] = {idx = buttonIdx, note = note}
        if LC.councilPanel and LC.councilPanel:IsShown() then
            if LC.activeRollID == rollID then KART.LC.Council.RefreshCouncilRows() end
            KART.LC.Council.RefreshCouncilTabs()
        end
    else
        LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":" .. note)
    end
    Vote.RefreshVoteListRows()
end
```

- [ ] **Step 2: Replace both OnClick bodies**

Spacious and Compact button handlers both become:

```lua
                btn:SetScript("OnClick", function()
                    Vote.CastVote(capturedRollID, capturedIdx, row.noteBox)
                end)
```

(delete the duplicated 20-line bodies; the `capturedIdx`/`capturedRollID` locals stay.)

- [ ] **Step 3: Verify**

Grep: `grep -c "LC.votedNoteByMe\[capturedRollID\]" LootCouncilVote.lua` → 0. `grep -c "Vote.CastVote" LootCouncilVote.lua` → 3 (definition + 2 call sites).
In-game: Test-Looter vote in both layouts (toggle compact checkbox) — voted badge + council panel update as before.

- [ ] **Step 4: Commit**

```bash
git add LootCouncilVote.lua
git commit -m "refactor: extract Vote.CastVote shared by both vote-list layouts"
```

### Task 34: LH.GetFilteredEntries (S4)

**Files:**
- Modify: `LootHistory.lua`

- [ ] **Step 1: Add helper (below GetItemNameFromLink)**

```lua
-- Applies the window's current player/reason/search filters and returns the matching
-- entries newest-first. Shared by the window renderer and the JSON export, which must
-- always agree on what "currently visible" means.
local function GetFilteredEntries()
    local filtered = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local matchPlayer = (not LH.filters.player) or (e.winner == LH.filters.player)
        local matchReason = (not LH.filters.reason) or ((e.reason or "") == LH.filters.reason)
        local matchSearch = true
        if LH.filters.search ~= "" then
            matchSearch = GetItemNameFromLink(e.item):lower():find(LH.filters.search, 1, true) ~= nil
        end
        if matchPlayer and matchReason and matchSearch then
            table.insert(filtered, e)
        end
    end
    table.sort(filtered, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return filtered
end
```

- [ ] **Step 2: Use it in both consumers**

`LH.BuildRCLootCouncilJSON`: delete its `entries` filter/sort block, start with `local entries = GetFilteredEntries()`.
`LH.Refresh`: delete its filter/sort block, use `local filtered = GetFilteredEntries()`.

- [ ] **Step 3: Verify**

Grep: `grep -c "matchPlayer" LootHistory.lua` → 1 (only inside the helper).
In-game: filter by player + search, export JSON → exported set equals visible rows.

- [ ] **Step 4: Commit**

```bash
git add LootHistory.lua
git commit -m "refactor: single filter path for history window and JSON export"
```

### Task 35: Row-stripe color helper (S5, T11)

**Files:**
- Modify: `Utils.lua` (new helper)
- Modify: `LootHistory.lua`, `BuffChecker.lua` (2 sites), `Invite.lua`

- [ ] **Step 1: Utils.lua — add below KART.Theme.AccentColor**

```lua
-- Base color for alternating row stripes: the configured window background lightened a touch.
-- bgR/bgG/bgB have no settings UI anymore (the background color picker was removed with the
-- artwork rework) but are kept as tunable saved values; this helper is their only consumer.
function KART.GetRowStripeColor()
    local br = (KART_Settings and KART_Settings.bgR or 10) / 100
    local bg = (KART_Settings and KART_Settings.bgG or 10) / 100
    local bb = (KART_Settings and KART_Settings.bgB or 10) / 100
    return KART.Theme.Lighten(br, bg, bb, 0.06)
end
```

- [ ] **Step 2: Replace the four duplicated computations**

Pattern at each site (`LootHistory.lua:546-548`, `BuffChecker.lua:518-521` preview, `BuffChecker.lua:625-628` live, `Invite.lua:247-249`):

```lua
        local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
        local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
```

becomes:

```lua
        local lr, lg, lb = KART.GetRowStripeColor()
```

- [ ] **Step 3: Verify**

Grep: `grep -rn "bgR or 10" *.lua` → only Utils.lua.
In-game: history rows, buff rows, boss-list rows still striped.

- [ ] **Step 4: Commit**

```bash
git add Utils.lua LootHistory.lua BuffChecker.lua Invite.lua
git commit -m "refactor: shared row-stripe color helper (documents the orphaned bgR/G/B keys)"
```

### Task 36: Unified reminder windows (S6)

**Files:**
- Modify: `LootCouncilTrade.lua` (replace `CreateTradeReminderFrame`, `CreateOwedReminderFrame`, `RefreshTradeReminder`, `RefreshOwedReminder`)

**Interfaces:**
- Consumes: `KART.Identity.ResolveDisplayName/FindUnitForKey`, `Trade.RemovePendingTrade`, `Trade.RemoveOwedItem` (unchanged signatures).
- Produces: unchanged public API — `Trade.RefreshTradeReminder()`, `Trade.RefreshOwedReminder()`; `LC.tradeReminderFrame`/`LC.owedReminderFrame` still set (Core's `/kart trade` uses the former).

- [ ] **Step 1: Add the shared builder + row renderer (replacing both Create*Frame functions)**

```lua
-- The "items still to trade" (lootmaster) and "items you still need to collect" (winner)
-- windows are structurally identical — one builder + one row renderer serves both.
local function CreateReminderFrame(frameName, titleText, posKey, defaultX)
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    f:SetSize(320, 40)
    f:SetPoint("CENTER", defaultX, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings[posKey] = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(titleText)
    f.rows = {}

    local pos = KART_Settings and KART_Settings[posKey]
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end
    return f
end

local function RefreshReminderRows(f, entries, getTargetKey, removeByRollID)
    for i, entry in ipairs(entries) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetHeight(26)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            -- Fixed max width so nameBtn keeps real, predictable clickable width — a long item
            -- name would otherwise push nameBtn's width toward zero. Long names clip instead.
            row.text:SetWidth(160)

            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetPoint("LEFT", row.text, "RIGHT", 4, 0)
            row.nameBtn:SetPoint("RIGHT")
            row.nameBtn:SetHeight(16)
            row.nameBtn.text = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameBtn.text:SetPoint("LEFT")
            row.nameBtn.text:SetPoint("RIGHT")
            row.nameBtn.text:SetJustifyH("LEFT")
            row.nameBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(KART.Theme.AccentColor()) end)
            row.nameBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)

            row.doneBtn = CreateFrame("Button", nil, row) -- child of row so it hides with it
            row.doneBtn:SetSize(16, 16)
            row.doneBtn:SetPoint("LEFT", row, "RIGHT", 8, 0)
            -- A real texture, not a "✓" font glyph — WoW's default game fonts don't include most
            -- symbol/dingbat Unicode ranges and silently render them as an empty box.
            row.doneBtn.icon = row.doneBtn:CreateTexture(nil, "ARTWORK")
            row.doneBtn.icon:SetAllPoints()
            row.doneBtn.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.doneBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(KART.L.LC_TRADE_REMINDER_DONE, 1, 1, 1) GameTooltip:Show() end)
            row.doneBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            f.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -8 - 26 - (i - 1) * 26)
        row:SetPoint("RIGHT", -28, 0)
        row.text:SetText(entry.itemLink or "???")
        local targetKey = getTargetKey(entry)
        row.nameBtn.text:SetText(KART.Identity.ResolveDisplayName(targetKey))
        local capturedRollID = entry.rollID
        row.doneBtn:SetScript("OnClick", function() removeByRollID(capturedRollID) end)
        row.nameBtn:SetScript("OnClick", function()
            local unit = targetKey and KART.Identity.FindUnitForKey(targetKey)
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, KART.Identity.ResolveDisplayName(targetKey)))
                return
            end
            if not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, KART.Identity.ResolveDisplayName(targetKey)))
                return
            end
            TargetUnit(unit)
            InitiateTrade(unit)
        end)
        row:Show()
    end
    for i = #entries + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end
    f:SetHeight(8 + 26 + #entries * 26 + 8)
    f:Show()
end
```

- [ ] **Step 2: Shrink the two refresh functions**

```lua
-- Rebuilds the reminder list from LC.pendingTrades; hides the frame entirely once it's empty.
function Trade.RefreshTradeReminder()
    if #LC.pendingTrades == 0 then
        if LC.tradeReminderFrame then LC.tradeReminderFrame:Hide() end
        return
    end
    if not LC.tradeReminderFrame then
        LC.tradeReminderFrame = CreateReminderFrame("KART_LCTradeReminder", KART.L.LC_TRADE_REMINDER_TITLE, "lcTradeReminderPos", -220)
    end
    RefreshReminderRows(LC.tradeReminderFrame, LC.pendingTrades,
        function(e) return e.winnerKey end, Trade.RemovePendingTrade)
end

-- Rebuilds the reminder list from LC.owedToMe; hides the frame entirely once it's empty.
function Trade.RefreshOwedReminder()
    LC.owedToMe = LC.owedToMe or {}
    if #LC.owedToMe == 0 then
        if LC.owedReminderFrame then LC.owedReminderFrame:Hide() end
        return
    end
    if not LC.owedReminderFrame then
        LC.owedReminderFrame = CreateReminderFrame("KART_LCOwedReminder", KART.L.LC_OWED_REMINDER_TITLE, "lcOwedReminderPos", 220)
    end
    RefreshReminderRows(LC.owedReminderFrame, LC.owedToMe,
        function(e) return e.lootmasterKey end, Trade.RemoveOwedItem)
end
```

Delete `Trade.CreateTradeReminderFrame` and `Trade.CreateOwedReminderFrame` entirely.

- [ ] **Step 3: Verify**

Grep: `grep -n "CreateTradeReminderFrame\|CreateOwedReminderFrame" LootCouncilTrade.lua` → no hits.
Raid test: both windows appear/refresh/mark-done as before; done-button hides with its row (Task 20 behavior preserved).

- [ ] **Step 4: Commit**

```bash
git add LootCouncilTrade.lua
git commit -m "refactor: one shared builder for the trade and owed reminder windows"
```

### Task 37: Generic input dialog (S7)

**Files:**
- Modify: `Utils.lua` (new `KART.ShowInputDialog`)
- Modify: `LootCouncil.lua` (`LC.ShowSyncTargetDialog`), `LootCouncilOfficerNotes.lua` (`ShowOfficerNoteDialog`), `Profiles.lua` (`KART.ShowSaveProfileDialog`)

**Interfaces:**
- Produces: `KART.ShowInputDialog(opts)` with `opts = { title, maxLetters, initialText, okLabel, allowEmpty, emptyMessage, onAccept(text) }`. `onAccept` receives the trimmed text; empty input either errors (`emptyMessage`) or is passed through (`allowEmpty = true`).

- [ ] **Step 1: Utils.lua — add near KART.CreateStyledEditBox**

```lua
-- Generic single-line input dialog, replacing three near-identical hand-rolled dialogs
-- (LC sync target, officer note, save profile). Hand-rolled rather than StaticPopup because
-- retail's StaticPopup doesn't reliably expose its edit box to OnAccept (see the original
-- ShowOfficerNoteDialog comment in git history for the full story).
local inputDialog
function KART.ShowInputDialog(opts)
    if not inputDialog then
        local f = CreateFrame("Frame", "KART_InputDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        KART.ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetWidth(270)
        f.title:SetWordWrap(true)

        f.editBox = KART.CreateStyledEditBox(f, "KART_InputDialogEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            local o = f.opts
            local text = KART.TrimString(f.editBox:GetText() or "")
            if text == "" and not o.allowEmpty then
                if o.emptyMessage then UIErrorsFrame:AddMessage(o.emptyMessage, 1, 0.1, 0.1, 1, 3) end
                return
            end
            f:Hide()
            o.onAccept(text)
        end

        f.btnOK = KART.CreateModernButton(f, ACCEPT)
        f.btnOK:SetSize(120, 26)
        f.btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        f.btnOK:SetScript("OnClick", accept)

        local btnCancel = KART.CreateModernButton(f, CANCEL)
        btnCancel:SetSize(120, 26)
        btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        inputDialog = f
    end
    local f = inputDialog
    f.opts = opts
    f.title:SetText(opts.title)
    f.btnOK.text:SetText(opts.okLabel or ACCEPT)
    f.editBox:SetMaxLetters(opts.maxLetters or 64)
    f.editBox:SetText(opts.initialText or "")
    f:Show()
    f.editBox:SetFocus()
    if (opts.initialText or "") ~= "" then f.editBox:HighlightText() end
end
```

- [ ] **Step 2: Replace the three call sites**

`LootCouncil.lua` — delete the `syncTargetDialog` local and the old builder; new body:

```lua
function LC.ShowSyncTargetDialog()
    KART.ShowInputDialog({
        title = KART.L.LC_SYNC_TARGET_PROMPT,
        maxLetters = 48,
        emptyMessage = KART.L.LC_SYNC_TARGET_EMPTY,
        onAccept = function(text) LC.SendSettingsSync(text) end,
    })
end
```

`LootCouncilOfficerNotes.lua` — delete `LC.officerNoteDialog` usage and the builder; new body:

```lua
function OfficerNotes.ShowOfficerNoteDialog(playerKey, playerDisplayName)
    KART.ShowInputDialog({
        title = string.format(KART.L.LC_OFFICER_NOTE_PROMPT, playerDisplayName),
        maxLetters = 120,
        initialText = KART_LCOfficerNotes[playerKey] or "",
        allowEmpty = true, -- empty input clears the note (see SetOfficerNote)
        okLabel = OKAY,
        onAccept = function(text) OfficerNotes.SetOfficerNote(playerKey, text) end,
    })
end
```

`Profiles.lua` — delete the `saveProfileDialog` local and builder; new body:

```lua
function KART.ShowSaveProfileDialog()
    KART.ShowInputDialog({
        title = KART.L.PROFILE_SAVE_NEW_TEXT,
        maxLetters = 32,
        emptyMessage = KART.L.PROFILE_NAME_EMPTY,
        onAccept = function(name)
            if KART_Profiles[name] then
                StaticPopupDialogs["KART_PROFILE_OVERWRITE_CONFIRM"].text = KART.L.PROFILE_OVERWRITE_CONFIRM_TEXT
                StaticPopup_Show("KART_PROFILE_OVERWRITE_CONFIRM", name, nil, { name = name })
            else
                KART.SaveProfile(name)
                KART.RefreshProfileButton()
            end
        end,
    })
end
```

- [ ] **Step 3: Verify**

Grep: `grep -rn "syncTargetDialog\|saveProfileDialog\|officerNoteDialog" *.lua` → no hits.
In-game: all three dialogs open, accept, cancel, ESC; officer-note dialog pre-fills and clears on empty accept; profile save with existing name shows overwrite popup.

- [ ] **Step 4: Commit**

```bash
git add Utils.lua LootCouncil.lua LootCouncilOfficerNotes.lua Profiles.lua
git commit -m "refactor: generic KART.ShowInputDialog replaces three hand-rolled dialogs"
```

### Task 38: Header icon-button factory (S8)

**Files:**
- Modify: `Utils.lua` (new factory)
- Modify: `LootCouncilVote.lua`, `LootCouncilPanel.lua` (close + minimize), `LootHistory.lua`, `BuffChecker.lua`
- Modify: `Core.lua` (remove BuffChecker's per-frame close-font line in UpdateStyles)

- [ ] **Step 1: Utils.lua — add below KART.CreateHeaderLine**

```lua
-- "×"/"-"/"+" header buttons used by every popup window. The glyph FontString registers in
-- KART.CloseButtonTexts so KART.UpdateStyles keeps its font in sync with the chosen font.
function KART.CreateHeaderIconButton(parent, glyph, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    btn.text:SetPoint("CENTER", 0, 1)
    btn.text:SetText(glyph or "×")
    table.insert(KART.CloseButtonTexts, btn.text)
    btn:SetScript("OnEnter", function(s) s.text:SetTextColor(KART.Theme.AccentColor()) end)
    btn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnClick", onClick)
    return btn
end
```

- [ ] **Step 2: Replace the five hand-built buttons** (keep each site's existing anchor/size line; delete the 8–10 line construction)

- `LootCouncilVote.lua` CreateVoteList: `local closeBtn = KART.CreateHeaderIconButton(f, "×", function() f:Hide() end)` + existing `closeBtn:SetPoint("TOPRIGHT", -6, -6)`.
- `LootCouncilPanel.lua` CreateCouncilPanel: closeBtn (glyph "×", `function() f:Hide() end`, point `("RIGHT", -4, 0)` on hdr) and minimizeBtn (glyph "-", `function() Council.SetCouncilPanelMinimized(not f.isMinimized) end`, point `("RIGHT", closeBtn, "LEFT", -2, 0)`); keep `f.minimizeBtn = minimizeBtn` (SetCouncilPanelMinimized swaps its glyph via `f.minimizeBtn.text:SetText`).
- `LootHistory.lua` CreateWindow: same pattern as vote list, parent `hdr`, point `("RIGHT", -4, 0)`.
- `BuffChecker.lua`: replace the 20x20 BackdropTemplate close button with `local close = KART.CreateHeaderIconButton(f, "×", function() f:Hide() end)` + `close:SetPoint("TOPRIGHT", -5, -2)`; keep `f.closeBtn = close`.

- [ ] **Step 3: Core.lua — remove the now-redundant special case**

Delete from UpdateStyles:

```lua
        if KART.BuffCheckFrame.closeBtn then
            KART.BuffCheckFrame.closeBtn.text:SetFont(fontPath, 14, "OUTLINE")
        end
```

(the CloseButtonTexts loop covers it now).

- [ ] **Step 4: Verify**

Grep: `grep -rn 'SetText("×")' *.lua` → only Utils.lua (council tab close "|cffff6666×|r" at 11px is a different, smaller element — leave it).
In-game: all five buttons hover-accent and close/minimize; font change restyles them.

- [ ] **Step 5: Commit**

```bash
git add Utils.lua LootCouncilVote.lua LootCouncilPanel.lua LootHistory.lua BuffChecker.lua Core.lua
git commit -m "refactor: shared header icon-button factory for popup close/minimize buttons"
```

### Task 39: Sliders opt out of full restyle (S9)

**Files:**
- Modify: `Utils.lua` (`CreateSettingsSlider` signature)
- Modify: `MainFrame.lua` (PullSlider, SldCombatDelay, SldAlMinKey), `LootCouncil.lua` (SldVoteTimer)

- [ ] **Step 1: Add the parameter**

```lua
function KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText, skipStyleRefresh)
```

and in its OnValueChanged:

```lua
        if not skipStyleRefresh and KART.UpdateStyles then KART.UpdateStyles() end
```

with a short comment:

```lua
        -- skipStyleRefresh: sliders whose value doesn't feed KART.UpdateStyles (pull timer,
        -- combat delay, min key level, vote timer) skip the full restyle on every drag tick.
```

- [ ] **Step 2: Pass `true` at the four non-style sliders**

- `MainFrame.lua` PullSlider: `..., "KART_PullTimerSlider", L.DESC_PULL_TIMER, true)`
- `MainFrame.lua` SldCombatDelay: `..., "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY, true)`
- `MainFrame.lua` SldAlMinKey: `..., "KART_AlMinKeySlider", L.DESC_AL_MIN_KEY, true)`
- `LootCouncil.lua` SldVoteTimer: `..., "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER, true)`

(All others — scale, alpha, strata, font sizes, buff-check alpha, LC font size — keep the live restyle.)

- [ ] **Step 3: Verify**

In-game: drag the pull-timer slider → value text updates, no visible restyle hitching; drag content-font slider → fonts still update live.

- [ ] **Step 4: Commit**

```bash
git add Utils.lua MainFrame.lua LootCouncil.lua
git commit -m "perf: non-style sliders skip the full UpdateStyles pass per drag tick"
```

### Task 40: Drop legacy numeric vote format (S10)

Every writer produces `{idx, note}` tables (HandleVote, CastVote, SetPlayerVote, StartTest); votes never persist across sessions and always arrive via our own parser — the numeric-format branches are unreachable.

**Files:**
- Modify: `LootCouncilPanel.lua` (3 sites), `LootCouncilVote.lua` (SetPlayerVote)

- [ ] **Step 1: RefreshCouncilRows members loop**

```lua
            local voteData = votes[key]
            -- Support both legacy number and new {idx, note} table
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
```

becomes:

```lua
            local voteData = votes[key] -- always {idx, note} — every writer produces tables
            local voteIdx  = voteData and voteData.idx
            local voteNote = (voteData and voteData.note) or ""
```

Apply the identical change in the test-roll self-row block.

- [ ] **Step 2: Tab hover tooltip (RefreshCouncilTabs)**

```lua
                local idx = type(voteData) == "table" and voteData.idx or voteData
```

becomes:

```lua
                local idx = voteData.idx
```

- [ ] **Step 3: Vote.SetPlayerVote**

```lua
    local prev = LC.votes[rollID][playerKey]
    local note = (type(prev) == "table" and prev.note) or ""
```

becomes:

```lua
    local prev = LC.votes[rollID][playerKey]
    local note = (prev and prev.note) or ""
```

- [ ] **Step 4: Verify**

Grep: `grep -rn 'type(voteData) == "table"\|type(prev) == "table"' *.lua` → no hits.
In-game: Test-Lootmaster → votes render, change-vote menu works, tab tooltips list votes.

- [ ] **Step 5: Commit**

```bash
git add LootCouncilPanel.lua LootCouncilVote.lua
git commit -m "refactor: drop unreachable legacy numeric vote-format handling"
```

---

# Block 7 — Structure (S11, S12)

### Task 41: Table-driven CHAT_MSG_ADDON dispatch (S11)

Replaces the ~30-branch `elseif msg:sub(...)` chain. **Must preserve Block 3 semantics**: sender-key pass-through for LC_ACTIVE/LC_START/LC_MANUAL_START/LC_HIST_ENTRY (Task 16) and the IsInGroup guards on sync replies (Task 28).

**Files:**
- Modify: `Core.lua` (new tables above `frame:SetScript("OnEvent", ...)`; slim CHAT_MSG_ADDON branch)

- [ ] **Step 1: Add the dispatch tables above the OnEvent SetScript**

```lua
-- CHAT_MSG_ADDON dispatch. A message is either a fixed token (EXACT_HANDLERS) or
-- "PREFIX:payload" (PREFIX_HANDLERS, keyed by the part before the FIRST colon — payloads may
-- contain further colons; each handler parses its own format). Entries with lc = true only
-- run while the Loot Council module is enabled; LC_SYNC_ACCEPT/DECLINE deliberately skip that
-- gate (a decline must still print even if the receiver just disabled the module).
-- ctx = { sender = full sender name, shortName, channel }.
local function SenderKey(ctx)
    return (KART.Identity.ResolvePlayer(ctx.sender))
end

local function HandleVersionMessage(payload, ctx, isAnnounce)
    local ver, lcFlag = payload:match("^([^:]+):?([01]?)$")
    ver = ver or payload

    KART.PlayerVersions = KART.PlayerVersions or {}
    KART.PlayerVersions[ctx.shortName] = ver
    if lcFlag == "1" or lcFlag == "0" then
        KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
        KART.PlayerLCEnabled[ctx.shortName] = (lcFlag == "1")
    end
    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
    end

    if not KART.UpdateWarned and ver ~= KART.Version then
        local nMaj, nMin, nPat = ver:match("(%d+)%.(%d+)%.(%d+)")
        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.(%d+)%.(%d+)")
        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0
        if nMaj > oMaj or (nMaj == oMaj and nMin > oMin) or (nMaj == oMaj and nMin == oMin and nPat > oPat) then
            KART.UpdateWarned = true
            print(string.format(KART.L.UPDATE_AVAILABLE, ver, KART.Version))
        end
    end

    if KART.VersionCheckActive and not isAnnounce then
        print(string.format(KART.L.VERSION_CHECK_RES, ctx.shortName, ver))
    end
end

local EXACT_HANDLERS = {
    REQ_OIL = { fn = function(_, ctx)
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        local outMH = (hasMH and mhID) and mhID or 0
        local outOH = (hasOH and ohID) and ohID or 0
        if IsInGroup() then
            C_ChatInfo.SendAddonMessage("KART", "OIL:" .. outMH .. ":" .. outOH, IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_ILVL = { fn = function(_, ctx)
        local _, equipped = GetAverageItemLevel()
        if equipped and IsInGroup() then
            C_ChatInfo.SendAddonMessage("KART", "ILVL:" .. string.format("%.1f", equipped), IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_GEAR = { fn = function(_, ctx)
        if IsInGroup() then
            local e, g = KART.CountMissingGear()
            C_ChatInfo.SendAddonMessage("KART", "GEAR:" .. e .. ":" .. g, IsInRaid() and "RAID" or "PARTY")
        end
    end },
    REQ_VERSION = { fn = function(_, ctx)
        local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
        if ctx.channel == "WHISPER" then
            C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, "WHISPER", ctx.sender)
        else
            C_ChatInfo.SendAddonMessage("KART", "VERSION:" .. KART.Version .. ":" .. lcFlag, ctx.channel)
        end
    end },
    LC_SYNC_ACCEPT  = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncAccept(ctx.shortName) end end },
    LC_SYNC_DECLINE = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncDecline(ctx.shortName) end end },
    LC_STATE_REQ    = { lc = true, fn = function(_, ctx) KART.LC.HandleStateRequest() end },
}

local PREFIX_HANDLERS = {
    OIL = { fn = function(payload, ctx)
        local mhID, ohID = payload:match("^(%d+):(%d+)$")
        if mhID and ohID then
            KART.OilCache = KART.OilCache or {}
            KART.OilCache[ctx.shortName] = { mh = tonumber(mhID), oh = tonumber(ohID) }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    ILVL = { fn = function(payload, ctx)
        local ilvl = tonumber(payload)
        if ilvl then
            KART.ILvlCache = KART.ILvlCache or {}
            KART.ILvlCache[ctx.shortName] = ilvl
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    GEAR = { fn = function(payload, ctx)
        local e, g = payload:match("^([^:]+):([^:]+)$")
        if e and g then
            KART.GearCache = KART.GearCache or {}
            KART.GearCache[ctx.shortName] = { enchants = e, gems = g }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    VERSION          = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, false) end },
    ANNOUNCE_VERSION = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, true) end },
    LC_ACTIVE       = { lc = true, fn = function(payload, ctx) KART.LC.HandleActive(payload, SenderKey(ctx)) end },
    LC_START        = { lc = true, fn = function(payload, ctx) KART.LC.HandleStart(payload, SenderKey(ctx)) end },
    LC_MANUAL_START = { lc = true, fn = function(payload, ctx) KART.LC.HandleManualStart(payload, SenderKey(ctx)) end },
    LC_VOTE         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleVote(payload, SenderKey(ctx)) end },
    LC_ROLL         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleRoll(payload, SenderKey(ctx)) end },
    LC_CVOTE        = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleCouncilVote(payload, SenderKey(ctx)) end },
    LC_ONOTE        = { lc = true, fn = function(payload, ctx) KART.LC.OfficerNotes.HandleOfficerNote(payload, SenderKey(ctx)) end },
    LC_RESULT       = { lc = true, fn = function(payload, ctx) KART.LC.Trade.HandleResult(payload, SenderKey(ctx)) end },
    LC_CONFIG       = { lc = true, fn = function(payload, ctx) KART.LC.HandleConfig(payload, SenderKey(ctx)) end },
    LC_HIST_REQ     = { lc = true, fn = function(payload, ctx) KART.LH.HandleHistoryRequest(payload, ctx.sender) end },
    LC_HIST_ENTRY   = { lc = true, fn = function(payload, ctx) KART.LH.HandleHistoryEntry(payload, SenderKey(ctx)) end },
    LC_SYNC_REQUEST = { lc = true, fn = function(payload, ctx) KART.LC.HandleSyncRequest(payload, ctx.sender, ctx.shortName) end },
    RC_REASON = { fn = function(payload, ctx)
        KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
        KART.ReadyCheckReasons[ctx.shortName] = payload
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            print(string.format(KART.L.RC_REASON_RECEIVED, ctx.shortName, payload))
        end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end },
}
```

- [ ] **Step 2: Replace the CHAT_MSG_ADDON branch body**

```lua
    elseif event == "CHAT_MSG_ADDON" and arg1 == "KART" then
        local msg = arg2
        local channel = select(1, ...)
        local sender = select(2, ...)
        if sender then
            local shortName = sender:match("([^%-]+)")
            if shortName then
                local ctx = { sender = sender, shortName = shortName, channel = channel }
                local prefix, payload = msg:match("^([^:]+):(.*)$")
                local entry = (prefix and PREFIX_HANDLERS[prefix]) or EXACT_HANDLERS[msg]
                if entry and not (entry.lc and not (KART.LC and KART_Settings.lcModuleEnabled ~= false)) then
                    entry.fn(payload, ctx)
                end
            end
        end
    end
```

- [ ] **Step 3: Verify — message-type parity check**

Before committing, run: `git show HEAD:Core.lua | grep -oE '"(REQ_[A-Z]+|LC_[A-Z_]+:?|OIL:|ILVL:|GEAR:|VERSION:|ANNOUNCE_VERSION:|RC_REASON:)"' | sort -u` and compare against the keys of both new tables — every old token must appear exactly once (VERSION/ANNOUNCE_VERSION as prefix keys, no-colon tokens as exact keys).

Behavior spot-checks in-game: `/kart v` prints versions; oil/ilvl/gear columns fill on Advanced view; RC reason prints for leader; LC vote round-trips in a raid test.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "refactor: table-driven CHAT_MSG_ADDON dispatch replaces the elseif chain"
```

### Task 42: Split settings panel into LootCouncilSettings.lua (S12)

**⚠ New file → testing requires a full WoW client restart, not `/reload`.**

**Files:**
- Create: `LootCouncilSettings.lua`
- Modify: `LootCouncil.lua` (remove moved code)
- Modify: `KeineAhnungRaidTools.toc`

**Interfaces:**
- Produces: unchanged public API — `LC.BuildSettingsPanel`, `LC.UpdateRoleStatusLabel`, `LC.RelayoutRaidBox`, `KART.LC.RaidBox`, `KART.LC.SettingsCard` and all `KART.LC.Cb*/Sld*/Btn*` widget fields keep their names (Core.lua's settingsMap and Droptimizer.lua depend on them).

- [ ] **Step 1: Create `LootCouncilSettings.lua`**

Header:

```lua
local addonName, KART = ...

-- Settings-panel UI for the Loot Council module (split out of LootCouncil.lua, which keeps
-- the session/roll/config logic). Loads after LootCouncilPanel.lua and before Droptimizer.lua,
-- which anchors its toggle into KART.LC.SettingsCard created here.
KART.LC = KART.LC or {}
local LC = KART.LC
```

Move — cut from `LootCouncil.lua`, paste unchanged below this header:
1. `LC.UpdateRoleStatusLabel` (incl. its comment block)
2. the `StripColons` local (Task 17)
3. `LC.BuildSettingsPanel` complete (incl. the locale refresher from Task 10 and the layoutRaidBox closure)
4. the trailing `if KART.LootCouncilPanel then LC.BuildSettingsPanel(KART.LootCouncilPanel) end`

- [ ] **Step 2: toc entry**

In `KeineAhnungRaidTools.toc` insert after `LootCouncilPanel.lua`:

```
LootCouncilPanel.lua
LootCouncilSettings.lua
Droptimizer.lua
```

- [ ] **Step 3: Verify**

Grep: `grep -n "BuildSettingsPanel\|UpdateRoleStatusLabel" LootCouncil.lua` → no definitions left (Core.lua still calls `KART.LC.UpdateRoleStatusLabel` — now provided by the new file).
Line count sanity: `wc -l LootCouncil.lua LootCouncilSettings.lua` → LootCouncil.lua roughly 370 lines lighter.
**Full WoW restart**, then: Loot Council tab renders completely, Droptimizer checkbox sits in the prefs card at -75, both test buttons + history button work, locale refresher still applies (switch language, reload).

- [ ] **Step 4: Commit**

```bash
git add LootCouncilSettings.lua LootCouncil.lua KeineAhnungRaidTools.toc
git commit -m "refactor: move Loot Council settings panel into LootCouncilSettings.lua"
```

### Task 43: Final sweep + release notes

- [ ] **Step 1: Whole-plan regression pass (in-game, deDE + enUS)**

- Login fresh-settings char (`/run KART_Settings = nil ReloadUI()`): no errors, defaults localized.
- All 6 tabs, Buff-Checker default + advanced, preview mode.
- Loot Council: Test Looter (both layouts), Test Lootmaster (tabs, assign, change vote, officer note), history window + JSON export, sync-settings dialog.
- Raidlead bar: markers (single fire), ready check, pull timer, keybinds, world-marker clear.
- Profiles: save/load/delete, minimap icon position persistence.
- Search: query + jump, popout above window at FULLSCREEN_DIALOG.

- [ ] **Step 2: Changelog (blocks 5–7 are internal — single line)**

`CHANGELOG.md`:

```markdown
- **Internal cleanup:** dead code removed, duplicated logic consolidated, addon-message handling restructured.
```

`CHANGELOG-de.md`:

```markdown
- **Interne Aufräumarbeiten:** toter Code entfernt, doppelte Logik zusammengeführt, Addon-Nachrichten-Verarbeitung restrukturiert.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md CHANGELOG-de.md
git commit -m "docs: changelog for internal cleanup blocks"
```

---

## Execution order & dependency notes

1. Blocks run strictly in order 1 → 7; within a block, tasks are independent unless noted.
2. Task 7 must precede Tasks 9–13 (refreshers need the registry) and Task 18 (locale copy must sit before the Defaults merge).
3. Task 16's Core.lua edits are absorbed verbatim by Task 41's dispatch tables — Task 41's parity check (Step 3) is the guard.
4. Task 20's `doneBtn` parenting is preserved inside Task 36's shared builder.
5. Task 28 (T8) renames a call Task 17 still writes (`LC.UpdateCouncilCache` in the council edit box) — Task 17 keeps the old name, Task 28 renames it; both note this.
6. Only Task 42 adds a file → only that task needs a full WoW restart to test.

## Deliberately NOT changed (reviewed, kept)

- BuffChecker's roster loop (solo fallback + 40-row pool semantics — excluded from S1).
- Officer notes broadcast to the whole raid channel (any addon can listen anyway; changing the transport is out of scope).
- `KART.PlayerVersions` short-name keying (documented as out of scope of the GUID identity rework).
- Auto-Pass firing below the min-quality threshold for regular raiders (documented personal-preference design).
- bgR/bgG/bgB saved values (kept, documented in `KART.GetRowStripeColor`).
- File names `Invite.lua`/`GroupLogic.lua` (S13 rejected by maintainer).

