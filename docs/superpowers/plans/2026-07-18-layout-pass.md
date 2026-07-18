# Layout Pass Implementation Plan (bigger window, cards, white text)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** +25% default window size, all six tabs grouped into KART.CreateCard boxes with a wider-column re-layout, and gold label text switched to white.

**Architecture:** Geometry constants re-derived from the measured PNG ratios at art width 800 (factor 800/1292). Content column becomes 540; full-width cards are 500 at x=20, half cards 242 at x=20 / x=278. Widget factories keep their internal x=20; a second column inside a card is done via `ClearAllPoints()` + `SetPoint("TOPLEFT", <card>, "TOPLEFT", 260, y)` after creation (existing pattern: SldFrameStrata).

**Tech Stack:** WoW Retail addon, Lua 5.1. No test framework — per-task verification is greps + careful reads; in-game checklist at the end.

**Spec:** docs/superpowers/specs/2026-07-18-layout-pass-design.md

## Global Constraints

- Code comments in English.
- No new locale strings; no new settings.
- Deliberately colored text keeps its color: gray hints, amber raid-wide box (title, border, divider), green/red status labels, role-status label.
- Factories (Utils.lua) affect all KART windows — intended for text color, but factory geometry (sizes, x=20 default) must NOT change.
- Other windows' layouts (BuffChecker window, Loot History, vote/council popups) untouched.
- Version stays 2.0.0; changelog entries join the existing `## [2.0.0]` section.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Geometry constants (art width 800, s = 800/1292)

| Constant | Old | New |
|---|---|---|
| mainFrame SetSize | 743, 572 | 929, 715 |
| clickArea TOPLEFT / BOTTOMRIGHT | (52,-52) / (-51,51) | (65,-64) / (-64,64) |
| versionText BOTTOMLEFT | (14,10) | (18,12) |
| Tab size (Utils.lua CreateTabButton) | 140x25 | 176x28 |
| First tab TOPLEFT | (10,-60) | (12,-75) |
| scrollFrame TOPLEFT / BOTTOMRIGHT | (166,-12) / (-25,20) | (208,-14) / (-30,24) |
| scrollChild | 430x750 | 540x750 |
| closeBtn size / CENTER at TOPRIGHT | 30 / (-21,-20) | 36 / (-27,-24) |

---

### Task 1: Geometry scale-up

**Files:**
- Modify: `MainFrame.lua` (sections 2-4, 8), `Utils.lua` (CreateTabButton size only)

**Interfaces:**
- Produces: unchanged names; only sizes/offsets change. Sidebar column is now 200 wide (baked divider ratio), content column 540.

- [ ] **Step 1: MainFrame.lua — apply every "New" value from the geometry table above.** The affected lines (current state):
  - `mainFrame:SetSize(743, 572)` → `mainFrame:SetSize(929, 715)`
  - comment `-- Art width is fixed at 640 (scale factor 640/1292)` → `-- Art width is fixed at 800 (scale factor 800/1292)`
  - `clickArea:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 52, -52)` → `65, -64`
  - `clickArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -51, 51)` → `-64, 64`
  - `mainFrame.versionText:SetPoint("BOTTOMLEFT", clickArea, "BOTTOMLEFT", 14, 10)` → `18, 12`
  - `KART.BtnPromote:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 10, -60)` → `12, -75`
  - scroll comment `right of the baked sidebar divider (160px)` → `(200px)`
  - `scrollFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 166, -12)` → `208, -14`
  - `scrollFrame:SetPoint("BOTTOMRIGHT", clickArea, "BOTTOMRIGHT", -25, 20)` → `-30, 24`
  - `scrollChild:SetSize(430, 750)` → `540, 750`
  - `closeBtn:SetSize(30, 30)` → `36, 36`
  - `closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -21, -20)` → `-27, -24`

- [ ] **Step 2: Utils.lua — CreateTabButton: `b:SetSize(140, 25)` → `b:SetSize(176, 28)`.** Nothing else in the function.

- [ ] **Step 3: Verify:** `grep -n "743\|572\|166\|430, 750\|SetSize(140, 25)" MainFrame.lua Utils.lua` → no matches. Read the edited section once.

- [ ] **Step 4: Commit** — `git add MainFrame.lua Utils.lua && git commit -m "feat: scale main window up to 800px artwork width"` (+ trailer).

---

### Task 2: White label text

**Files:**
- Modify: `Utils.lua` (3 factory templates), `MainFrame.lua` (3 titles), `LootCouncil.lua` (BuildSettingsPanel templates), `Invite.lua` (WU.BuildPanel templates)

**Interfaces:** none — template names only.

- [ ] **Step 1: Utils.lua factory templates** (gold → white):
  - CreateSettingsCheckbox: `cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `"GameFontHighlightSmall"`
  - CreateSettingsSlider: `s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `"GameFontHighlightSmall"`
  - CreateCard: `card.titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")` → `"GameFontHighlightSmall"`

- [ ] **Step 2: MainFrame.lua titles:** `rlTitle` and `bcTitle` from `"GameFontNormal"` → `"GameFontHighlight"`; `settingsTitle` from `"GameFontNormalLarge"` → `"GameFontHighlightLarge"`. Do NOT touch promLabel/invLabel/alTitle — Task 3 recreates them.

- [ ] **Step 3: LootCouncil.lua, inside `LC.BuildSettingsPanel` only:** `title` `"GameFontNormalLarge"` → `"GameFontHighlightLarge"`; every `"GameFontNormalSmall"` in that function → `"GameFontHighlightSmall"` (boxTitle/hints keep their explicit SetTextColor overrides — leave those calls alone).

- [ ] **Step 4: Invite.lua, inside `WU.BuildPanel` only:** `title` `"GameFontNormalLarge"` → `"GameFontHighlightLarge"`; every `"GameFontNormalSmall"` in that function → `"GameFontHighlightSmall"` (statusLabel/emptyLabel SetTextColor calls stay).

- [ ] **Step 5: Verify:** `grep -n "GameFontNormal" MainFrame.lua` → no matches. `grep -n "GameFontNormal" Utils.lua` → no matches in the three factories (other occurrences elsewhere in Utils.lua, if any, stay). In LootCouncil.lua/Invite.lua, `GameFontNormal` remains only OUTSIDE BuildSettingsPanel/WU.BuildPanel.

- [ ] **Step 6: Commit** — `git add Utils.lua MainFrame.lua LootCouncil.lua Invite.lua && git commit -m "feat: white label text instead of WoW gold in settings panels"` (+ trailer).

---

### Task 3: MainFrame panel cards (Automation, Raidlead, BuffCheck, Settings)

**Files:**
- Modify: `MainFrame.lua` sections 5-7, `Droptimizer.lua` (BuildSyncStatus call site + parent)

**Interfaces:**
- Consumes: `KART.CreateCard(parent[, title])`, factories.
- Produces: `KART.SettingsColorCard` (card frame; Droptimizer parents its sync status to it). All existing widget globals keep their names and settingKeys.

- [ ] **Step 1: Raidlead card:** `rlCard:SetSize(290, 180)` → `rlCard:SetSize(500, 180)`. Content unchanged.

- [ ] **Step 2: BuffCheck card two-column.** `bcCard:SetSize(290, 290)` → `(500, 160)`. Column 1 (x=20 factory default): CbBcModuleEnabled yOffset −20 (unchanged), CbShowBuffCheck −50 (unchanged), CbGrayOffline yOffset `-235` → `-80`, BtnBuffPreview SetPoint `(20, -90)` → `(20, -115)`. Column 2 — after each slider's creation line add reposition:

```lua
KART.SldBuffCheckAlpha = KART.CreateSettingsSlider(bcCard, L.SET_BC_ALPHA, 0, 100, "buffCheckAlpha", -30, "KART_BuffCheckAlphaSlider", L.DESC_BC_ALPHA)
KART.SldBuffCheckAlpha:ClearAllPoints()
KART.SldBuffCheckAlpha:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -46)
KART.SldCombatDelay = KART.CreateSettingsSlider(bcCard, L.SET_BC_COMBAT_DELAY, 0, 30, "bcCombatDelay", -90, "KART_BuffCheckCombatDelaySlider", L.DESC_BC_COMBAT_DELAY)
KART.SldCombatDelay:ClearAllPoints()
KART.SldCombatDelay:SetPoint("TOPLEFT", bcCard, "TOPLEFT", 260, -106)
```

- [ ] **Step 3: Automation panel — replace the whole section 6 block (promLabel through CbInviteViaGuildChat) with a card layout.** Keep both EditBoxes' global/frame names, scripts, and `table.insert(KART.EditBoxes, …)` registrations identical; only parent/anchor/size/template change:

```lua
-- 6. Automation panel: promote/invite settings grouped into a card.
local autoCard = KART.CreateCard(KART.PromotePanel)
autoCard:SetPoint("TOPLEFT", KART.PromotePanel, "TOPLEFT", 20, -20)
autoCard:SetSize(500, 195)

local promLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promLabel:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 20, -15)
promLabel:SetText(L.LABEL_PROMOTE_NAMES)
table.insert(KART.DynamicLabels, promLabel)

KART.PromoteEditBox = CreateFrame("EditBox", "KART_PromoteEditBox", autoCard, "BackdropTemplate")
KART.PromoteEditBox:SetSize(460, 28)
KART.PromoteEditBox:SetPoint("TOPLEFT", promLabel, "BOTTOMLEFT", 0, -8)
-- (SetAutoFocus, SetBackdrop, SetBackdropColor, KART.EditBoxes insert, OnTextChanged,
--  OnEscapePressed: identical to the current block)

local invLabel = autoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
invLabel:SetPoint("TOPLEFT", KART.PromoteEditBox, "BOTTOMLEFT", 0, -14)
invLabel:SetText(L.LABEL_INVITE_KEYWORDS)
table.insert(KART.DynamicLabels, invLabel)

KART.InviteEditBox = CreateFrame("EditBox", "KART_InviteEditBox", autoCard, "BackdropTemplate")
KART.InviteEditBox:SetSize(460, 28)
KART.InviteEditBox:SetPoint("TOPLEFT", invLabel, "BOTTOMLEFT", 0, -8)
-- (rest identical to the current block)

KART.CbAutoRaid = KART.CreateSettingsCheckbox(autoCard, "KART_AutoRaidCheck", L.SET_AUTO_RAID, "autoConvertToRaid", -160, nil, L.DESC_AUTO_RAID)
KART.CbInviteViaGuildChat = KART.CreateSettingsCheckbox(autoCard, "KART_InviteViaGuildChatCheck", L.SET_INVITE_VIA_GUILD_CHAT, "inviteViaGuildChat", -160, nil, L.DESC_INVITE_VIA_GUILD_CHAT)
KART.CbInviteViaGuildChat:ClearAllPoints()
KART.CbInviteViaGuildChat:SetPoint("TOPLEFT", autoCard, "TOPLEFT", 260, -160)
```

- [ ] **Step 4: AutoLog card two-column.** `alTitle` template → `"GameFontHighlight"`, anchored `alTitle:SetPoint("TOPLEFT", autoCard, "BOTTOMLEFT", 0, -18)`. `alCard:SetSize(290, 310)` → `(500, 185)`. Column 1 (yOffsets change): CbAlEnabled −20, CbAlRaidLFR −50, CbAlRaidNormal −80, CbAlRaidHeroic −110, CbAlRaidMythic −140. Column 2 (reposition after creation, x=260): CbAlMythicPlus yOffset −20 then `ClearAllPoints` + `SetPoint("TOPLEFT", alCard, "TOPLEFT", 260, -20)`; SldAlMinKey yOffset −50 then reposition to `(260, -66)` (keep the existing `HookScript("OnValueChanged", AutoLogChanged)`); CbAlDungeons −110 → reposition `(260, -110)`; CbAlDelves −140 → reposition `(260, -140)`.

- [ ] **Step 5: Settings panel cards.** Keep `settingsTitle`. Replace the widget block (CbMinimap through BtnReset, and remove SldFrameStrata's old ClearAllPoints/SetPoint pair) with:

```lua
-- Card: window-level interface options
local ifCard = KART.CreateCard(KART.SettingsPanel)
ifCard:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -50)
ifCard:SetSize(242, 215)

KART.CbMinimap = KART.CreateSettingsCheckbox(ifCard, "KART_MinimapCheck", L.SET_MINIMAP, "showMinimapIcon", -20, function()
    KART.UpdateMinimapButton()
end, L.DESC_MINIMAP)
KART.SldUiScale = KART.CreateSettingsSlider(ifCard, L.SET_UI_SCALE, 50, 150, "uiScale", -60, "KART_UiScaleSlider", L.DESC_UI_SCALE)
KART.SldBgAlpha = KART.CreateSettingsSlider(ifCard, L.SET_BG_ALPHA, 20, 100, "bgAlpha", -105, "KART_BgAlphaSlider", L.DESC_BG_ALPHA)
KART.SldFrameStrata = KART.CreateSettingsSlider(ifCard, L.SET_FRAME_STRATA, 1, #KART.StrataLevels, "frameStrata", -150, "KART_FrameStrataSlider", L.DESC_FRAME_STRATA)
-- (UpdateStrataSliderText function + both HookScript lines: keep identical)

-- Card: text rendering
local txtCard = KART.CreateCard(KART.SettingsPanel)
txtCard:SetPoint("TOPLEFT", ifCard, "TOPRIGHT", 16, 0)
txtCard:SetSize(242, 215)

KART.SldMenuSize = KART.CreateSettingsSlider(txtCard, L.LABEL_FONT_SIZE_MENU, 8, 20, "menuFontSize", -20, "KART_MenuSizeSlider", L.DESC_MENU_SIZE)
KART.SldContentSize = KART.CreateSettingsSlider(txtCard, L.LABEL_FONT_SIZE_CONTENT, 8, 20, "contentFontSize", -65, "KART_ContentSizeSlider", L.DESC_CONTENT_SIZE)
KART.BtnFont = KART.CreateModernButton(txtCard, L.BTN_SELECT_FONT, L.DESC_SELECT_FONT)
KART.BtnFont:SetPoint("TOPLEFT", txtCard, "TOPLEFT", 20, -125)
-- (BtnFont OnClick: identical)
KART.BtnLang = KART.CreateModernButton(txtCard, (L.BTN_LANGUAGE_PREFIX or "Language: ") .. (L.LANG_AUTO or "Auto"), L.DESC_LANGUAGE)
KART.BtnLang:SetPoint("TOPLEFT", KART.BtnFont, "BOTTOMLEFT", 0, -10)
-- (BtnLang OnClick: identical)

-- Card: colors, reset, companion sync status (Droptimizer anchors into this card)
local colCard = KART.CreateCard(KART.SettingsPanel)
colCard:SetPoint("TOPLEFT", ifCard, "BOTTOMLEFT", 0, -20)
colCard:SetSize(500, 150)
KART.SettingsColorCard = colCard

KART.BtnAccentColor = KART.CreateModernButton(colCard, L.BTN_ACCENT_COLOR, L.DESC_ACCENT_COLOR)
KART.BtnAccentColor:SetPoint("TOPLEFT", colCard, "TOPLEFT", 20, -20)
-- (OnClick identical)
KART.ColorPreview = colCard:CreateTexture(nil, "OVERLAY")
-- (size/point/bg block identical, but bg texture also created on colCard)
KART.BtnReset = KART.CreateModernButton(colCard, L.BTN_RESET, L.DESC_RESET)
KART.BtnReset:SetPoint("TOPLEFT", KART.BtnAccentColor, "BOTTOMLEFT", 0, -16)
-- (OnClick identical)
```

- [ ] **Step 6: Droptimizer.lua — sync status must render above the card, not under it.** In `DT.BuildSyncStatus(parent)` nothing changes; change the call site:

```lua
if KART.SettingsPanel then
    DT.BuildSyncStatus(KART.SettingsColorCard or KART.SettingsPanel)
end
```
Also update that call's comment to mention the color card. The `SetPoint("TOPLEFT", KART.BtnReset, "BOTTOMLEFT", 0, -20)` anchor inside BuildSyncStatus stays valid.

- [ ] **Step 7: Verify:** `grep -n "SettingsPanel, \"KART_\|SettingsPanel, L\." MainFrame.lua` → no factory calls parented to the bare panel anymore (title excepted). `grep -n "ClearAllPoints" MainFrame.lua` → only the new column-2 repositions. All widget global names unchanged: `grep -c "KART.SldUiScale\|KART.CbMinimap\|KART.BtnFont\|KART.BtnLang\|KART.BtnAccentColor\|KART.BtnReset" MainFrame.lua` unchanged vs. before. Read sections 5-7 fully once.

- [ ] **Step 8: Commit** — `git add MainFrame.lua Droptimizer.lua && git commit -m "feat: card layout for Automation, Raidlead, BuffCheck and Settings tabs"` (+ trailer).

---

### Task 4: Loot Council panel cards

**Files:**
- Modify: `LootCouncil.lua` (`LC.BuildSettingsPanel`), `Droptimizer.lua` (`DT.BuildLootCouncilToggle` + call site)

**Interfaces:**
- Produces: `KART.LC.SettingsCard` (card holding the personal toggles; Droptimizer parents its toggle to it at yOffset −75).
- Everything else keeps its name; `LC.RelayoutRaidBox` contract unchanged (called from KART.UpdateStyles).

- [ ] **Step 1: Personal-toggles card.** After the title, insert:

```lua
    -- Personal preferences card (module toggle, autopass, Droptimizer slot at -75,
    -- compact vote layout, nicknames). Raid-wide settings live in the amber box below.
    local prefsCard = KART.CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -50)
    prefsCard:SetSize(500, 165)
    KART.LC.SettingsCard = prefsCard
```
Re-parent the four checkboxes to `prefsCard` with new yOffsets: CbModuleEnabled −15, CbAutoPass −45, CbCompactVoteLayout −105, CbShowNickNames −135. Update the slot-bookkeeping comments accordingly (Droptimizer slot is now −75 inside the card).

- [ ] **Step 2: Droptimizer.lua.** `DT.BuildLootCouncilToggle`: yOffset `-110` → `-75`; update its comment. Call site: `DT.BuildLootCouncilToggle(KART.LC.SettingsCard or KART.LootCouncilPanel)`.

- [ ] **Step 3: Raid-wide box widen + round.** `raidBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -210)` → `raidBox:SetPoint("TOPLEFT", prefsCard, "BOTTOMLEFT", 0, -20)`; `raidBox:SetSize(295, 362)` → `(500, 362)`; after the first `layoutRaidBox()` call add `KART.ApplyRoundedMask(raidBox, KART.Theme.CORNER_RADIUS_LG)` (masks track the corners on later SetHeight calls). Amber colors stay. `CONTENT_WIDTH = 265` → `460`; `KART.LC.RoleStatusLabel:SetWidth(260)` → `460`. Update the "box is only 295px wide" comment.

- [ ] **Step 4: Buttons below.** BtnTestLooter/BtnTestMaster `SetSize(122, 28)` → `(242, 28)`; looter anchor `("TOPLEFT", raidBox, "BOTTOMLEFT", 10, -16)` → `(…, 0, -16)`; master gap `8` → `16`. BtnHistory `SetSize(255, 28)` → `(500, 28)`.

- [ ] **Step 5: Verify:** `grep -n "CONTENT_WIDTH\|SetSize(122\|SetSize(295\|SetSize(255\|-110" LootCouncil.lua Droptimizer.lua` → no stale values (−110 may remain in unrelated code — check hits are outside the panel/toggle functions). Read BuildSettingsPanel + layoutRaidBox once: layout flow logic must be untouched.

- [ ] **Step 6: Commit** — `git add LootCouncil.lua Droptimizer.lua && git commit -m "feat: card layout for Loot Council tab"` (+ trailer).

---

### Task 5: WoWUtils panel card

**Files:**
- Modify: `Invite.lua` (`WU.BuildPanel`; check `WU.RefreshBossList` for row anchoring)

**Interfaces:** all `WU.*` names unchanged.

- [ ] **Step 1: Check first:** read `WU.RefreshBossList` (same file). If boss rows anchor LEFT/RIGHT-relative to `WU.bossListFrame` (they should), widening the panel needs no row changes; if any row element uses absolute x beyond ~270, report it in your report and adjust that element's anchor to a RIGHT-relative one.

- [ ] **Step 2: Import card.** After CbModuleEnabled (stays at −45 on the panel), wrap the import section:

```lua
    local importCard = KART.CreateCard(parent)
    importCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -85)
    importCard:SetSize(500, 190)
```
Re-parent and re-anchor into `importCard`: pasteLabel `(20, -15)`; pasteBG `(20, -35)`, `SetSize(460, 90)`; `WU.ImportEditBox:SetWidth(428)`; BtnImport `("TOPLEFT", 20, -135)` on importCard; BtnReset `SetSize(100, 26)`, `SetPoint("LEFT", WU.BtnImport, "RIGHT", 10, 0)`; statusLabel on importCard at `(20, -168)`.

- [ ] **Step 3: Boss list below the card.** sep `SetPoint("TOPLEFT", 5, -290)` / `SetPoint("TOPRIGHT", -5, -290)`; hBoss `(8, -300)`; hInvite `TOPRIGHT (-110, -300)`; hRemove `TOPRIGHT (-38, -300)`; bossListFrame `TOPLEFT (5, -316)` (RIGHT anchor stays).

- [ ] **Step 4: Verify:** `grep -n "SetSize(265\|SetWidth(234\|-200)\|-235)\|-248\|-258\|-274" Invite.lua` → no stale panel offsets. Read WU.BuildPanel once.

- [ ] **Step 5: Commit** — `git add Invite.lua && git commit -m "feat: card layout for WoWUtils tab"` (+ trailer).

---

### Task 6: Changelog

**Files:** `CHANGELOG.md`, `CHANGELOG-de.md`

- [ ] **Step 1:** In CHANGELOG.md's `## [2.0.0]` section under `### Changed`, append:

```markdown
- **Main window is larger by default and every tab groups its settings into cards.**
- **Settings labels now use the same white text style as the menu.**
```

- [ ] **Step 2:** Mirror in CHANGELOG-de.md under `### Geändert`:

```markdown
- **Hauptfenster ist standardmäßig größer und jeder Tab gruppiert seine Einstellungen in Cards.**
- **Einstellungs-Beschriftungen nutzen jetzt denselben weißen Textstil wie das Menü.**
```

- [ ] **Step 3: Commit** — `git add CHANGELOG.md CHANGELOG-de.md && git commit -m "docs: changelog for layout pass"` (+ trailer).

---

## Final in-game verification (user)

1. Window noticeably larger; artwork crisp; X, tabs, divider still aligned.
2. Every tab: controls inside dark cards, nothing floating on bare background, nothing overlapping, no widget hidden behind a card.
3. Automation: both editboxes full card width; toggles side by side; AutoLog two columns, min-key slider working.
4. Settings: two half cards side by side + color card below with Droptimizer sync status visible inside the card.
5. Loot Council: toggle card incl. Droptimizer gain% toggle; amber box wider with rounded corners; role status + wrapped labels flow correctly (also after changing font size); test/history buttons aligned.
6. WoWUtils: import card; paste box works; boss list rows use the full width.
7. No gold text left in any tab except the amber raid-wide box; hints still gray, status colors still green/red.
8. Font-size sliders + accent color still restyle everything live.
