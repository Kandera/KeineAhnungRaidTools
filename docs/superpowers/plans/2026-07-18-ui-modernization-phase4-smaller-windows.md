# UI Modernization Phase 4: Raidlead Bar, WoWUtils Panel, Ready-Check Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the theme foundation from earlier, already-merged phases
(`KART.Theme`, `KART.ApplyRoundedMask` from Phase 1; the row-stripe-via-Theme-color pattern from
Phase 2/3) to the three remaining smaller UI surfaces named in the design spec's rollout list:
the Raidlead Bar (`RaidleadBar.lua`), the WoWUtils import panel (`Invite.lua`, despite its
filename — see Scope Note below), and the Ready-Check reason dialog (`Core.lua`).

**Scope Note — `Droptimizer.lua` excluded:** the design spec listed `Droptimizer.lua` alongside
these three files, but it contains no `CreateFrame`/`SetBackdrop` calls at all (verified via
grep) — it's pure data-sync logic with no UI surface. Nothing to modernize there; this plan
covers the three files that actually have UI.

**Scope Note — `Invite.lua`:** despite the filename, this file implements the WoWUtils Import
feature (`KART.WU` namespace) — the Keyword Invite feature itself is pure logic with no UI
surface of its own (its settings live in `MainFrame.lua`'s Automation panel, already modernized
in Phase 1). This plan's Task 2 only touches `Invite.lua`'s WoWUtils boss-list panel.

**Architecture:** No new primitives needed — consumes what earlier phases already built
(`KART.ApplyRoundedMask`, `KART.Theme.CORNER_RADIUS_LG/SM`, `KART.Theme.Lighten`,
`KART.Theme.AccentColor`, `KART.Theme.Darken`). Every `KART.CreateModernButton`/
`CreateSettingsCheckbox` call in these three files already picked up the modernized look when
Phase 1 merged — no changes needed to those call sites.

**Tech Stack:** Lua 5.1 (WoW addon runtime), WoW retail Frame API.

## Global Constraints

- No new graphic/icon assets.
- No automated test runner exists for this addon — every verification step here is a manual
  in-game check, described but not executable in this pipeline.
- Code comments and commit messages in English (per `CLAUDE.md`).
- No SavedVariables schema changes.
- `KART.RegisterStrataFrame` (pre-existing, unrelated helper already used in all three files) must
  remain untouched — out of scope for this plan.
- `RaidleadBar.lua`'s buttons use `SecureActionButtonTemplate` for some (macro-bound) buttons.
  `KART.ApplyRoundedMask` only touches textures/masks, and `OnEnter`/`OnLeave` scripts are not
  protected/tainted actions in WoW's secure-template model, so styling changes here carry no
  taint risk — this is a purely cosmetic change on every button, secure or not.

---

### Task 1: Raidlead Bar — rounded corners and accent-derived hover

**Files:**
- Modify: `RaidleadBar.lua:31-78` (`CreateBarButton` local function)
- Modify: `RaidleadBar.lua:102-108` (`rlBar`'s backdrop setup)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG/SM`,
  `KART.Theme.AccentColor()`, `KART.Theme.Darken(r, g, b, amount)` (all Phase 1, `Utils.lua`)

- [ ] **Step 1: Round each bar button and derive its hover color from the accent color**

Replace `RaidleadBar.lua:31-78`:

```lua
-- 2. Lokale Hilfsfunktion für die Bar-Buttons
local function CreateBarButton(parent, x, y, width, height, func, texture, texCoords, text, macrotext, tooltipText)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, BackdropTemplate")
    b:SetSize(width or 22, height or 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameLevel(parent:GetFrameLevel() + 5)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    
    if texture then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(texture)
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if texCoords then b.icon:SetTexCoord(unpack(texCoords)) end
    end

    if text then
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
    end

    if macrotext then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", macrotext)
    else
        b:SetScript("OnClick", func)
    end
    b:SetScript("OnEnter", function(self) 
        self:SetBackdropColor(0, 0.5, 0.8, 1) 
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
    return b
end
```

with:

```lua
-- 2. Lokale Hilfsfunktion für die Bar-Buttons
local function CreateBarButton(parent, x, y, width, height, func, texture, texCoords, text, macrotext, tooltipText)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, BackdropTemplate")
    b:SetSize(width or 22, height or 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameLevel(parent:GetFrameLevel() + 5)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    KART.ApplyRoundedMask(b, KART.Theme.CORNER_RADIUS_SM)
    
    if texture then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(texture)
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if texCoords then b.icon:SetTexCoord(unpack(texCoords)) end
    end

    if text then
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
    end

    if macrotext then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", macrotext)
    else
        b:SetScript("OnClick", func)
    end
    -- Hover color now derives from the user's accent color (same KART.Theme.AccentColor +
    -- Darken pattern as KART.CreateModernButton) instead of a hard-coded blue, so this toolbar
    -- matches the rest of the modernized UI's hover feedback.
    b:SetScript("OnEnter", function(self)
        local r, g, bl = KART.Theme.AccentColor()
        self:SetBackdropColor(KART.Theme.Darken(r, g, bl, 0.35))
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
    return b
end
```

Note: `Darken(r, g, bl, 0.35)` returns 3 values with no alpha — `SetBackdropColor` needs a 4th
argument. Check `KART.Theme.Darken`'s actual return count in `Utils.lua` before finalizing this
call (Phase 1's Task 4 review found and fixed exactly this class of bug in a different function —
verify it doesn't recur here, and if `Darken` truly returns only 3 values, capture them into
locals and pass an explicit alpha, e.g. `local dr, dg, db = KART.Theme.Darken(r, g, bl, 0.35);
self:SetBackdropColor(dr, dg, db, 1)`).

- [ ] **Step 2: Round the bar's own outer corners**

Replace `RaidleadBar.lua:102-108`:

```lua
rlBar:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
rlBar:SetBackdropColor(0, 0, 0, 0.8)
rlBar:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
rlBar:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
rlBar:SetBackdropColor(0, 0, 0, 0.8)
rlBar:SetBackdropBorderColor(0, 0, 0, 1)
KART.ApplyRoundedMask(rlBar, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 3: Manual verification**

Run: `/reload`, enable the Raidlead Bar (`/kart` → Raidlead tab → toggle on). Expected: the bar's
outer corners are rounded, each of the 18 icon buttons (8 raid markers, 8 world markers, clear-WM,
ready-check, buff-check toggle, pull timer) has rounded corners, and hovering any button tints it
toward the configured accent color instead of the old hard-coded blue. Click a few buttons to
confirm they still function (e.g. `/wm` markers, ready check, pull timer macro).

- [ ] **Step 4: Commit**

```bash
git add RaidleadBar.lua
git commit -m "Round Raidlead Bar and its buttons, derive hover color from accent"
```

---

### Task 2: WoWUtils import panel — rounded paste box and Theme-driven row stripes

**Files:**
- Modify: `Invite.lua:294-303` (`pasteBG` creation inside `WU.BuildPanel`)
- Modify: `Invite.lua:218-247` (boss-list row creation/coloring inside `WU.RefreshBossList`)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG`,
  `KART.Theme.Lighten(r, g, b, amount)` (Phase 1, `Utils.lua`)

- [ ] **Step 1: Round the paste-text box**

Replace `Invite.lua:294-303`:

```lua
    local pasteBG = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pasteBG:SetSize(265, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -102)
    pasteBG:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    pasteBG:SetBackdropColor(0, 0, 0, 0.5)
    pasteBG:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
```

with:

```lua
    local pasteBG = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pasteBG:SetSize(265, 90)
    pasteBG:SetPoint("TOPLEFT", 20, -102)
    pasteBG:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    pasteBG:SetBackdropColor(0, 0, 0, 0.5)
    pasteBG:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    KART.ApplyRoundedMask(pasteBG, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 2: Route the boss-row zebra color through `KART.Theme.Lighten`**

Replace `Invite.lua:218-224` (the row's own `SetBackdrop` at creation — this call has no color
argument, only the backdrop shape/texture, so it's unaffected) — instead, the color is set later
on every refresh. Replace `Invite.lua:246`:

```lua
        row:SetBackdropColor(0.1, 0.1, 0.1, i % 2 == 0 and 0.4 or 0.15)
```

with:

```lua
        local br, bg, bb = (KART_Settings.bgR or 10)/100, (KART_Settings.bgG or 10)/100, (KART_Settings.bgB or 10)/100
        local lr, lg, lb = KART.Theme.Lighten(br, bg, bb, 0.06)
        row:SetBackdropColor(lr, lg, lb, i % 2 == 0 and 0.4 or 0.15)
```

This is the third instance of this exact pattern (Phase 2 `BuffChecker.lua`, Phase 3
`LootHistory.lua`) — same `KART_Settings.bgR/G/B` fields, same `or 10` defaults, same `0.06`
`Lighten` amount, same alpha-preserving approach (only the RGB source changes, the existing
`i % 2 == 0 and 0.4 or 0.15` alpha/parity ternary must stay byte-identical).

- [ ] **Step 3: Manual verification**

Run: `/reload`, `/kart` → WoWUtils tab, paste a WoWUtils export (or check with existing imported
bosses if any are already saved). Expected: the paste-text box has rounded corners, and the boss
rows still alternate light/dark bands (tint now derived from the user's configured background
color instead of a fixed near-black — same effect verified for the analogous Phase 2/3 changes).

- [ ] **Step 4: Commit**

```bash
git add Invite.lua
git commit -m "Round WoWUtils paste box; derive boss-row stripe color from background color"
```

---

### Task 3: Ready-Check reason dialog — rounded corners

**Files:**
- Modify: `Core.lua:500-510` (`KART.ShowReadyCheckReasonDialog`'s frame creation)
- Modify: `Core.lua:544-556` (`customInput` EditBox creation, same function)

**Interfaces:**
- Consumes: `KART.ApplyRoundedMask(frame, radius)`, `KART.Theme.CORNER_RADIUS_LG/SM` (Phase 1,
  `Utils.lua`)

- [ ] **Step 1: Round the dialog frame**

Replace `Core.lua:500-510`:

```lua
        local f = CreateFrame("Frame", "KART_RCReasonFrame", UIParent, "BackdropTemplate")
        f:SetSize(260, 115)
        f:SetPoint("CENTER", 0, 150)
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
```

with:

```lua
        local f = CreateFrame("Frame", "KART_RCReasonFrame", UIParent, "BackdropTemplate")
        f:SetSize(260, 115)
        f:SetPoint("CENTER", 0, 150)
        KART.RegisterStrataFrame(f, true)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        KART.ApplyRoundedMask(f, KART.Theme.CORNER_RADIUS_LG)
```

- [ ] **Step 2: Round the custom-reason text input**

Replace `Core.lua:544-556`:

```lua
        local customInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        customInput:SetSize(155, 25)
        customInput:SetPoint("BOTTOMLEFT", 10, 15)
        customInput:SetAutoFocus(false)
        customInput:SetFontObject("GameFontHighlightSmall")
        customInput:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        customInput:SetBackdropColor(0, 0, 0, 0.8)
        customInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        customInput:SetTextInsets(5, 5, 0, 0)
        customInput:SetMaxLetters(30) -- Verhindert, dass Leute ganze Romane schreiben
```

with:

```lua
        local customInput = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        customInput:SetSize(155, 25)
        customInput:SetPoint("BOTTOMLEFT", 10, 15)
        customInput:SetAutoFocus(false)
        customInput:SetFontObject("GameFontHighlightSmall")
        customInput:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        customInput:SetBackdropColor(0, 0, 0, 0.8)
        customInput:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        customInput:SetTextInsets(5, 5, 0, 0)
        customInput:SetMaxLetters(30) -- Verhindert, dass Leute ganze Romane schreiben
        KART.ApplyRoundedMask(customInput, KART.Theme.CORNER_RADIUS_SM)
```

- [ ] **Step 3: Manual verification**

Run: `/reload`, in a group, start a ready check and click "Not Ready" to trigger this dialog
(or trigger it via whatever test path already exists in the codebase, if any). Expected: the
dialog's outer corners are rounded, and the custom-reason text input has rounded corners matching
the search box style already shipped in Phase 3's Loot History window. Typing/sending a custom
reason still works.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "Round Ready-Check reason dialog and its custom-reason input"
```
