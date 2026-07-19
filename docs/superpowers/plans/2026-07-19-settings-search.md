# Settings Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user type a setting's name into a search box and jump straight to it — correct tab shown, scrolled into view, briefly highlighted.

**Architecture:** A pure data function (`KART.BuildSearchIndex`) walks the existing `KART.DynamicLabels` list (every settings label already registers there) and maps each label to its containing main-window tab, with zero new registration calls at any existing settings call site. A small always-visible button opens a popout with an edit box and up to 8 pooled result rows; clicking a row switches tabs, scrolls the shared content frame, and briefly highlights the matched label.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — this project has no automated test suite; verification is manual in-game.

## Global Constraints

- English source: code, comments, commit messages. Update `Locales/enUS.lua` first, mirror into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets one bullet (max 2 lines, bold lead); mirror into `CHANGELOG-de.md` in the same task.
- Only the 6 main tab panels are searchable (`KART.PromotePanel`, `KART.RaidleadPanel`, `KART.BuffCheckPanel`, `KART.SettingsPanel`, `KART.LootCouncilPanel`, `KART.WoWUtilsPanel`); popup windows (Loot History, Buff Checker, Loot Council vote/council panels) are out of scope and must never appear in results — enforced structurally by the index only including labels whose parent chain reaches one of those 6 panels.
- No per-widget registration at any existing settings creation site — the index is built purely by walking `KART.DynamicLabels`.
- Plain case-insensitive substring match; no fuzzy matching.
- Index is rebuilt once per popout-open, not on every keystroke (filtering an already-built in-memory list on every keystroke is fine and expected; rebuilding the whole index every keystroke is not).

---

### Task 1: `KART.BuildSearchIndex()`

**Files:**
- Modify: `Utils.lua` (add near the end of the file, after `KART.DeepCopy`)

**Interfaces:**
- Produces: `KART.BuildSearchIndex()` — no args, returns an array of `{ text = string, tabIndex = 1..6, widget = FontString }`. Task 2 calls this once each time the search popout opens.

- [ ] **Step 1: Add the index builder**

In `Utils.lua`, add at the end of the file (after `KART.DeepCopy`):

```lua
-- Maps each of the 6 main-window tab-content panels to its ShowTab index. Used by
-- KART.BuildSearchIndex to figure out which tab a given label belongs to, by walking up the
-- label's parent chain until one of these panels is found.
local SEARCH_TAB_PANELS = {
    { panel = "PromotePanel", tabIndex = 1 },
    { panel = "RaidleadPanel", tabIndex = 2 },
    { panel = "BuffCheckPanel", tabIndex = 3 },
    { panel = "SettingsPanel", tabIndex = 4 },
    { panel = "LootCouncilPanel", tabIndex = 5 },
    { panel = "WoWUtilsPanel", tabIndex = 6 },
}

-- Builds the settings search index by walking KART.DynamicLabels — every settings label already
-- gets inserted there by its creation site (checkboxes, sliders, card titles, hints, tab titles),
-- so no per-widget registration is needed here. A label whose parent chain never reaches one of
-- the 6 main tab panels (e.g. one that belongs to a popup window like Loot History) is silently
-- skipped, which is how "only the 6 main tabs are searchable" enforces itself.
function KART.BuildSearchIndex()
    local index = {}
    for _, fs in ipairs(KART.DynamicLabels) do
        local text = fs:GetText()
        if text and text ~= "" then
            local ancestor = fs:GetParent()
            local tabIndex
            while ancestor and not tabIndex do
                for _, entry in ipairs(SEARCH_TAB_PANELS) do
                    if ancestor == KART[entry.panel] then
                        tabIndex = entry.tabIndex
                        break
                    end
                end
                ancestor = ancestor:GetParent()
            end
            if tabIndex then
                table.insert(index, { text = text, tabIndex = tabIndex, widget = fs })
            end
        end
    end
    return index
end
```

- [ ] **Step 2: Manual verification**

`/reload`, open `/kart`, then open the Lua error console or use `/dump` (or, simpler, add a temporary `/run print(#KART.BuildSearchIndex())` in chat — this is a throwaway diagnostic command, not code you add to the addon) to confirm it returns a number greater than 0 (there are dozens of labels across the 6 tabs). No Lua error.

- [ ] **Step 3: Commit**

```bash
git add Utils.lua
git commit -m "feat: add KART.BuildSearchIndex for settings search"
```

---

### Task 2: Search button, popout, filtering, jump

**Files:**
- Modify: `MainFrame.lua` (new button, popout frame, 8 pooled result rows, filter logic, jump logic)
- Modify: `Locales/enUS.lua` (2 new keys)
- Modify: `Locales/deDE.lua` (same 2 keys, mirrored)

**Interfaces:**
- Consumes: `KART.BuildSearchIndex()` (Task 1), `KART.ShowTab(tabIndex)` (existing), `KART.CreateStyledEditBox(parent, name)` (existing, `Utils.lua`), `KART.Theme.AccentColor()`/`KART.Theme.Darken()` (existing), `scrollFrame`/`scrollChild` (existing file-local variables in `MainFrame.lua`, already in scope for any code added later in the same file).
- Produces: `KART.JumpToSearchResult(entry)` — takes one index entry (as produced by Task 1), switches tabs, scrolls, and highlights. Not consumed outside this task, but named for clarity/future reuse.

- [ ] **Step 1: Add locale strings**

In `Locales/enUS.lua`, after line 17 (`LABEL_GENERAL_SETTINGS = "General Settings",`), add:

```lua
    BTN_SEARCH = "Search",
    DESC_SEARCH = "Search for a setting by name and jump straight to it.",
```

In `Locales/deDE.lua`, at the same relative location:

```lua
    BTN_SEARCH = "Suche",
    DESC_SEARCH = "Nach einer Einstellung suchen und direkt dorthin springen.",
```

- [ ] **Step 2: Add the search button and popout frame**

In `MainFrame.lua`, locate this exact code (the close button, near the end of the file):

```lua
-- 8. Close button: invisible hit area over the X baked into the artwork.
-- HIGHLIGHT-layer texture shows automatically on hover, no scripts needed.
local closeBtn = CreateFrame("Button", nil, clickArea)
closeBtn:SetSize(36, 36)
closeBtn:SetPoint("CENTER", clickArea, "TOPRIGHT", -27, -24)
local closeHover = closeBtn:CreateTexture(nil, "HIGHLIGHT")
closeHover:SetAllPoints()
closeHover:SetColorTexture(1, 1, 1, 0.08)
closeBtn:SetScript("OnClick", function() KART.MainFrame:Hide() end)
mainFrame.closeBtn = closeBtn
```

Immediately after that block, add:

```lua
-- 9. Settings search: small always-visible button + popout (edit box + up to 8 result rows).
-- Positioned left of the close button, in the same header row as the active tab's title, well
-- clear of the close button's hit area (closeBtn spans roughly x -45..-9, y -42..-6 from
-- clickArea's TOPRIGHT) and of the baked logo/title zone above y -22.
local searchBtn = KART.CreateModernButton(clickArea, L.BTN_SEARCH, L.DESC_SEARCH)
searchBtn:SetSize(70, 22)
searchBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -70, -20)

local searchPopout = CreateFrame("Frame", nil, clickArea, "BackdropTemplate")
searchPopout:SetPoint("TOPRIGHT", searchBtn, "BOTTOMRIGHT", 0, -6)
searchPopout:SetSize(260, 40)
searchPopout:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
searchPopout:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
searchPopout:SetBackdropBorderColor(0, 0, 0, 1)
searchPopout:SetFrameStrata("DIALOG")
searchPopout:Hide()
KART.ApplyRoundedMask(searchPopout, KART.Theme.CORNER_RADIUS_SM)

local searchBox = KART.CreateStyledEditBox(searchPopout, "KART_SearchBox")
searchBox:SetSize(240, 26)
searchBox:SetPoint("TOPLEFT", searchPopout, "TOPLEFT", 10, -8)
searchBox:SetMaxLetters(64)

-- 8 pooled, reusable result rows — created once, re-labeled and shown/hidden per search rather
-- than creating/destroying frames on every keystroke.
local RESULT_ROW_COUNT = 8
local resultRows = {}
for i = 1, RESULT_ROW_COUNT do
    local row = CreateFrame("Button", nil, searchPopout, "BackdropTemplate")
    row:SetSize(240, 20)
    row:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -4 - (i - 1) * 22)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0, 0, 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function(self)
        local r, g, b = KART.Theme.AccentColor()
        local dr, dg, db = KART.Theme.Darken(r, g, b, 0.45)
        self:SetBackdropColor(dr, dg, db, 0.5)
    end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
    row:Hide()
    resultRows[i] = row
end

local searchIndex = {}
local function CloseSearchPopout()
    searchPopout:Hide()
    searchBox:SetText("")
    searchBox:ClearFocus()
end
KART.HideSearchPopout = CloseSearchPopout

local function FilterSearch(query)
    query = query:lower()
    local shown = 0
    if query ~= "" then
        for _, entry in ipairs(searchIndex) do
            if shown >= RESULT_ROW_COUNT then break end
            if entry.text:lower():find(query, 1, true) then
                shown = shown + 1
                local row = resultRows[shown]
                row.text:SetText(entry.text)
                row.entry = entry
                row:Show()
            end
        end
    end
    for i = shown + 1, RESULT_ROW_COUNT do
        resultRows[i]:Hide()
    end
    searchPopout:SetHeight(40 + shown * 22)
end

for _, row in ipairs(resultRows) do
    row:SetScript("OnClick", function(self)
        if self.entry then KART.JumpToSearchResult(self.entry) end
    end)
end

searchBox:SetScript("OnTextChanged", function(self)
    FilterSearch(self:GetText())
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    CloseSearchPopout()
end)

searchBtn:SetScript("OnClick", function()
    if searchPopout:IsShown() then
        CloseSearchPopout()
    else
        searchIndex = KART.BuildSearchIndex()
        FilterSearch("")
        searchPopout:Show()
        searchBox:SetFocus()
    end
end)
```

- [ ] **Step 3: Add `KART.JumpToSearchResult`**

Immediately after the block added in Step 2, add:

```lua
-- Translucent highlight shown briefly over a search result's matched label. One shared frame,
-- re-parented and re-anchored per jump rather than creating a new frame per search.
local searchHighlight = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
searchHighlight:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
searchHighlight:Hide()

-- Switches to the result's tab, scrolls the shared content frame so the matched label sits
-- ~40px below the viewport's top edge (not flush against it), and briefly highlights the label.
function KART.JumpToSearchResult(entry)
    KART.ShowTab(entry.tabIndex)

    local widget = entry.widget
    local top = widget:GetTop()
    local scrollTop = scrollFrame:GetTop()
    if top and scrollTop then
        local delta = top - scrollTop + 40
        local maxScroll = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local newScroll = math.max(0, math.min(scrollFrame:GetVerticalScroll() + delta, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end

    searchHighlight:SetParent(widget:GetParent())
    searchHighlight:ClearAllPoints()
    searchHighlight:SetPoint("TOPLEFT", widget, "TOPLEFT", -6, 6)
    searchHighlight:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 6, -6)
    searchHighlight:SetFrameLevel(widget:GetParent():GetFrameLevel() + 10)
    local r, g, b = KART.Theme.AccentColor()
    searchHighlight:SetBackdropColor(r, g, b, 0.35)
    searchHighlight:Show()
    C_Timer.After(1.5, function() searchHighlight:Hide() end)

    KART.HideSearchPopout()
end
```

`scrollFrame` and `scrollChild` are file-local variables already declared earlier in `MainFrame.lua` (created in section "4. Content area") — this code must be added AFTER that point in the file (the close button, and therefore this new section, already is), so both are in scope.

- [ ] **Step 4: Manual verification**

`/reload`, open `/kart`. Confirm the "Search" button appears near the top-right, doesn't visually overlap the close button or the baked logo/title artwork. Click it — an empty popout with just the edit box appears (no rows, since the query is empty). Type a setting name that lives on a different tab than the current one (e.g. type "Pull Timer" while on the Automation tab) — a matching row appears. Click it — window switches to the Raidlead tab, scrolls so the Pull Timer slider is visible without it being flush at the very top, and a colored highlight briefly flashes around its label then fades after ~1.5s. Reopen search, type something matching 3+ labels across different tabs (e.g. "quality") — confirm multiple rows, each correctly jumping. Type a query matching nothing — confirm the popout shrinks to show no rows and nothing errors. Press Escape while typing — confirm the popout closes without navigating. Click the Search button again while the popout is open — confirm it closes (toggle behavior) instead of reopening. Repeat the whole check at both extremes of the Settings tab's "Window Scale" slider to confirm no new overlap appears at other scales.

- [ ] **Step 5: Commit**

```bash
git add MainFrame.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add settings search (button, popout, filter, jump-to-setting)"
```

---

### Task 3: Changelog + version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

**Interfaces:** None (docs only).

This project has no "Unreleased" section — every entry is a released, dated version bump. Bump
`KeineAhnungRaidTools.toc`'s `## Version:` line from `2.3.0` to `2.4.0`, dated with today's date.

- [ ] **Step 1: Bump the addon version**

In `KeineAhnungRaidTools.toc`, change:

```
## Version: 2.3.0
```

to:

```
## Version: 2.4.0
```

- [ ] **Step 2: Add the English changelog entry**

In `CHANGELOG.md`, insert a new section above the existing `## [2.3.0] - 2026-07-19` entry:

```markdown
## [2.4.0] - 2026-07-19
### Added
- **Settings search:** a new Search button on the main window lets you type a setting's name and jump straight to it — correct tab, scrolled into view, briefly highlighted.
```

- [ ] **Step 3: Mirror into German changelog**

In `CHANGELOG-de.md`, insert at the same relative position:

```markdown
## [2.4.0] - 2026-07-19
### Added
- **Einstellungen-Suche:** ein neuer Suche-Button im Hauptfenster — Einstellungsnamen eintippen und direkt dorthin springen, mit passendem Tab und kurzem Highlight.
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version to 2.4.0, changelog entry for settings search"
```
