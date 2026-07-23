# Loot Council Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **The bugfix plan (`docs/superpowers/plans/2026-07-22-loot-council-bugfixes.md`) has shipped** — all 15 tasks plus its final-review fixes are merged to `main`. Three small, standalone fixes landed *after* that plan closed, found via live raid testing (not part of either plan's task list, but affecting code this plan builds on): a council-member-list realm-suffix strip in `LC.HandleConfig`, a bonus-ID-aware rewrite of `FindItemInBags` (now compares full item strings, not bare itemID — Tasks 9/10/12 below reuse this via `GetItemString`), and a cross-realm `"(*)"` trade-frame name-marker strip in `LC.OnTradeShow`. **Re-read every file against its current state before starting any task below** — line references throughout this plan were taken at different points across all of this churn and will have drifted; treat every "Locate" block as a search target to confirm, not a trusted line number.

**Goal:** Implement the 11 feature requests/improvements gathered after the bugfix testing pass and a follow-up review of RCLootCouncil's approach to the same problems (Tasks 8-12).

**Architecture:** No new subsystems beyond what's described per-task. Every feature reuses the existing `LC_*` addon-message protocol, the existing per-rollID state tables, and the existing settings-slider/button helpers in `Utils.lua`.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — manual, in-game verification only. Several tasks need two characters/clients; noted per task.

## Global Constraints

- English source: code, comments, commit messages; mirror any new locale strings into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets these as `### Added` bullets (one line each, bold lead); mirror into `CHANGELOG-de.md` (Task 13).
- Bump `KeineAhnungRaidTools.toc`'s `## Version:` — confirm the actual current version at `KeineAhnungRaidTools.toc` before Task 13 (the bugfix plan and its post-close fixes may have already bumped it past what this note assumed when written).
- This plan does not touch the "Known gaps" items from the bugfix plan (Bugs 14b/16/20) — those remain open.
- Task 8 (GUID-based identity) is a scoping/architecture note, not an executable task — see its own text for why. Do not skip straight past it; it documents a real, confirmed 45-occurrence pattern that Tasks 9-12 deliberately do NOT fix (they keep using short-name matching, consistent with the rest of the file, since re-architecting identity is explicitly out of scope for this plan).

---

### Task 1: `/kart add <item1> <item2> ...` — the lootmaster manually adds item(s) to Loot Council for (re)distribution

**Confirmed design (resolved from the earlier open question):** only the **designated lootmaster** (`LC.GetLootmaster()`/`LC.IsMe`, not the raid leader generically) may run this — "for other players this doesn't work" is a requirement, not just an observation. This also resolves the earlier "who becomes the pending-trade holder" question for free: since only the lootmaster can ever create one of these rolls, the bugfix plan's Task 6 gate (`if LC.IsMe(LC.GetLootmaster()) then LC.AddPendingTrade(...) end`) already does the right thing with **no changes needed there at all** — it was written for "whoever physically holds the item," and the lootmaster manually adding an item they're already holding is exactly that case. The command also takes **multiple item links in one call** (`/kart add <item1> <item2> ...`), each becoming its own independent roll/vote.

**Files:**
- Modify: `Core.lua:634-650` (`SlashCmdList["KART"]`)
- Modify: `LootCouncil.lua` (new function near `LC.HandleStart`, new message handler, new `SendLC`-based broadcast)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (new "not the lootmaster" / usage strings)

**Interfaces:**
- Produces: `LC.StartManualRoll(itemsText)` — called from `Core.lua`'s slash handler with everything typed after `add `, original case preserved (unlike every other subcommand, which is matched case-insensitively). Parses out every item link found in `itemsText` (any amount of whitespace between them) and starts one roll per link.
- Produces: `LC.HandleManualStart(payload)` — called from `Core.lua`'s `CHAT_MSG_ADDON` dispatcher on `"LC_MANUAL_START:"`, once per item (the sender broadcasts one message per link, not a single batched one).

- [ ] **Step 1: Preserve case for the `add` subcommand while keeping every other subcommand's existing case-insensitive matching**

In `Core.lua`, locate:

```lua
SLASH_KART1 = "/kart"
SlashCmdList["KART"] = function(msg) -- Slash-Befehl zum Öffnen/Schließen des Hauptfensters
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "version" or cmd == "v" then
```

Replace with:

```lua
SLASH_KART1 = "/kart"
SlashCmdList["KART"] = function(msg) -- Slash-Befehl zum Öffnen/Schließen des Hauptfensters
    -- rawMsg keeps original case (needed for the "add" subcommand's item-link arguments — item
    -- hyperlinks use case-sensitive |H/|h control codes that :lower() would corrupt); cmd is the
    -- lowercased form every other subcommand below already matches against.
    local rawMsg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd = rawMsg:lower()
    if cmd == "version" or cmd == "v" then
```

- [ ] **Step 2: Add the `add` subcommand**

Locate (this is the `lc`/`trade` block the bugfix plan's Task 8 added):

```lua
    elseif cmd == "lc" then
```

Insert directly before it:

```lua
    elseif cmd == "add" or cmd:match("^add%s") then
        local itemsText = rawMsg:match("^%S+%s+(.+)$") or ""
        if KART.LC then KART.LC.StartManualRoll(itemsText) end
    elseif cmd == "lc" then
```

- [ ] **Step 3: Add `LC.StartManualRoll` and its own rollID range**

In `LootCouncil.lua`, locate the `TEST_ROLL_ID`/`IsTestRoll` block:

```lua
local TEST_ROLL_ID    = 99999
local TEST_ITEM_COUNT = #TEST_ITEMS
```

Add directly after it:

```lua
-- Manually-added items (see LC.StartManualRoll) get their own rollID range, well clear of both
-- real server-issued rollIDs and the fixed TEST_ROLL_ID block above — each item /kart add starts
-- increments past the last one used, since (unlike the 4 fixed test slots) any number of these
-- can exist. Already comfortably outside IsTestRoll's range (99999..100002), so no separate
-- IsManualRoll check is needed anywhere — AddPendingTrade's existing IsTestRoll guard already
-- treats these as real rolls, which is exactly the wanted behavior (unlike test rolls, they
-- should be tradeable).
local MANUAL_ROLL_ID_BASE = 500000
LC.nextManualRollID = LC.nextManualRollID or MANUAL_ROLL_ID_BASE
```

Then, near `LC.HandleStart` (after it, since it needs `ResolveRollItemLink` already in scope from earlier in the file), add:

```lua
-- Entry point for /kart add <item1> <item2> ... — lets the designated lootmaster hand item(s)
-- they're currently holding back to Council for a (re)decision, without a real Blizzard loot
-- roll behind them. Only the lootmaster may do this — same person ForceWinRoll makes physically
-- win every real drop, so they're always the one actually holding whatever they manually add too.
function LC.StartManualRoll(itemsText)
    if not LC.IsMe(LC.GetLootmaster()) then
        print("|cffff0000KART:|r " .. KART.L.LC_NOT_LOOTMASTER)
        return
    end

    local seconds = KART_Settings.lcVoteSeconds or 20
    local startedAny = false

    -- Matches each complete item hyperlink (|cAARRGGBB|Hitem:...|h[Name]|h|r) regardless of how
    -- many are pasted in one command or how much whitespace separates them — a plain word-split
    -- would break apart item names that contain spaces (e.g. "[Sulfuras, Hand von Ragnaros]").
    for itemLink in (itemsText or ""):gmatch("|c%x%x%x%x%x%x%x%x|Hitem:.-|h|r") do
        startedAny = true
        local rollID = LC.nextManualRollID
        LC.nextManualRollID = LC.nextManualRollID + 1

        LC.rollItems[rollID] = itemLink
        LC.votes[rollID]     = {}

        SendLC("LC_MANUAL_START:" .. rollID .. ":" .. seconds .. ":" .. itemLink)

        -- SendAddonMessage never echoes back to its own sender, so the lootmaster has to open
        -- their own window locally, same as HandleStart does for every other client.
        if IsCouncil() then
            LC.ShowCouncilPanel(rollID, seconds)
        else
            LC.ShowVotePopup(rollID, itemLink, seconds)
        end
    end

    if not startedAny then
        print("|cffff0000KART:|r " .. KART.L.LC_MANUAL_ADD_USAGE)
    end
end

-- Peer side of LC.StartManualRoll — mirrors LC.HandleStart, minus the GetLootRollItemLink call
-- (there's no real Blizzard roll behind a manually-added item, so the link always arrives intact
-- in the payload itself). Fires once per item — the sender broadcasts one LC_MANUAL_START per
-- link, not a single batched message.
function LC.HandleManualStart(payload)
    local rollID, secs, itemLink = payload:match("^(%d+):(%d+):(.*)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID or not itemLink or itemLink == "" then return end

    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = LC.rollItems[rollID] or itemLink

    if IsCouncil() then
        LC.ShowCouncilPanel(rollID, secs or 20)
    else
        LC.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end
```

- [ ] **Step 4: Add the two locale strings**

In `Locales/enUS.lua`, near `LC_NOT_LEADER`, add:

```lua
    LC_NOT_LOOTMASTER   = "Only the designated lootmaster can add items to Loot Council.",
    LC_MANUAL_ADD_USAGE = "Usage: /kart add <item link> [item link] ... (shift-click items into the command)",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_NOT_LOOTMASTER   = "Nur der festgelegte Lootmaster kann Items zu Loot Council hinzufügen.",
    LC_MANUAL_ADD_USAGE = "Verwendung: /kart add <Item-Link> [Item-Link] ... (Items per Shift-Klick in den Befehl einfügen)",
```

- [ ] **Step 5: Manual verification (needs two clients — one of them the designated lootmaster, one not)**

As a raider who is **not** the designated lootmaster, type `/kart add ` then shift-click a real item, submit — confirm the "only the designated lootmaster" message prints and no vote window opens anywhere. As the designated lootmaster, shift-click **two** different items into the same `/kart add` command (e.g. `/kart add [item1] [item2]`) and submit — confirm two independent tabs/rows appear (one per item) on the lootmaster's own client and on a second client. Vote and assign one of them; confirm history logs it and the trade reminder shows up on the lootmaster's own client. Run `/kart add` with no item link (as the lootmaster) and confirm the usage message prints instead of silently doing nothing.

- [ ] **Step 6: Commit**

```bash
git add Core.lua LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add /kart add so the lootmaster can hand item(s) back to Loot Council without a real loot roll"
```

---

### Task 2: Shrink a voted row in the Spacious vote-list layout

**Files:**
- Modify: `LootCouncil.lua:773-914` (`LC.RefreshVoteListRows_Spacious`)

**Interfaces:** None.

**Root cause / current behavior (confirmed):** `row.btnArea` (the vote buttons) and `row.noteBox`/`row.noteLabel` are already hidden once voted (`row.btnArea:SetShown(not voted)`, etc. — this already exists), replaced by `row.votedBadge` showing the chosen label plus the note text inline. But every row still uses one fixed `rowH` computed once for the whole list and positioned on a uniform grid (`row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))`), so a voted row's now-empty button/note area stays reserved as dead space instead of the card actually shrinking.

- [ ] **Step 1: Compute a per-row height instead of one fixed `rowH`, and position rows cumulatively**

Locate:

```lua
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls
```

Replace with:

```lua
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD -- unvoted height
    local VOTED_BADGE_H = 20 -- matches row.votedBadge:SetHeight(20) below
    local votedRowH = ACCENT_H + BTN_TOP + VOTED_BADGE_H + BOTTOM_PAD -- voted rows drop the button/note area entirely
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls
```

- [ ] **Step 2: Track a running Y offset instead of the uniform grid formula**

Locate:

```lua
    for i, rollID in ipairs(LC.voteListRolls) do
        local row = f.rows[i]
```

Replace with:

```lua
    local y = 0 -- running offset, since voted rows are now shorter than unvoted ones
    for i, rollID in ipairs(LC.voteListRolls) do
        local row = f.rows[i]
```

Then locate:

```lua
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(rowH)
        row.btnArea:SetPoint("RIGHT", -MARGIN, 0)
```

Replace with:

```lua
        local thisRowH = LC.votedByMe[rollID] and votedRowH or rowH
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(thisRowH)
        y = y + thisRowH + ROW_GAP
        row.btnArea:SetPoint("RIGHT", -MARGIN, 0)
```

- [ ] **Step 3: Size the scroll child to the accumulated height instead of the old uniform formula**

Find where `f.scrollChild`'s height gets set at the end of this function (search for `scrollChild:SetHeight` within `LC.RefreshVoteListRows_Spacious` — it currently multiplies `rowH + ROW_GAP` by the row count) and change it to use the final `y` value from the loop above instead, the same way any accumulator-based list height is normally finalized. If no such explicit height-set line exists in this function (the scroll frame may size itself from `UIPanelScrollFrameTemplate` automatically off the children's anchors), skip this step — confirm by checking whether the vote list's scrollbar behaves correctly in Step 4 before assuming it's needed.

- [ ] **Step 4: Manual verification**

`/reload`, switch to the Spacious (non-compact) layout if compact is currently on. Run a test roll with 2+ items, vote on one but not the others. Confirm the voted item's card visibly shrinks (button area and note box gone, just the header + voted badge left) while unvoted cards stay full height, and confirm the badge text (including any note) is still fully readable, not clipped. Confirm the list still scrolls correctly with a mix of voted/unvoted rows.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: shrink a vote-list card once you've voted on it, instead of leaving the button area empty"
```

---

### Task 3: Auto-close the Test: Looter window after its vote timer

**Files:** Likely none — see below.

**Investigation note:** Static analysis found the vote-list window (`LC.voteListFrame`, what "Test: Looter" — `LC.StartTest("looter")` — populates and shows) already has a working per-second ticker (`LootCouncil.lua:678-704`) that removes each `rollID` from `LC.voteListRolls` once `GetTime() >= LC.rollDeadlines[rollID]`, and `LC.RefreshVoteListRows` already hides the frame once the list is empty. `LC.ShowVotePopup` (called for test items the same as real ones) sets `LC.rollDeadlines[rollID] = GetTime() + (seconds or 20)` once per `StartTest` click, with nothing that continuously refreshes it. **This should already auto-close within `lcVoteSeconds` of clicking "Test: Looter".**

- [ ] **Step 1: Confirm actual current behavior before writing any fix**

Click "Test: Looter", start a stopwatch, and wait `lcVoteSeconds` (default 20s, or whatever it's set to) without touching anything else. If the window closes on its own: this feature is already done, no code change needed — close this task. If it does **not** close: that contradicts the static analysis above and means something else is keeping it alive (a candidate to check first: whether `f:IsShown()` was somehow `false` right when the ticker checked, or whether some other code re-adds the rollID to `LC.voteListRolls` after the ticker removes it) — re-open this task with the actual repro details (does it happen every time or intermittently? does `/dump LC.voteListRolls` still show the test rollIDs after the expected close time?) as its own investigation before writing a fix.

- [ ] **Step 2: If a fix was needed, commit it here (no placeholder — write the real diagnosis and fix once Step 1's repro is known).**

---

### Task 4: Trade Reminder window — click a name to auto-trade, plus more room

**Files:**
- Modify: `LootCouncil.lua:2762-2846` (`LC.CreateTradeReminderFrame`, `LC.RefreshTradeReminder`)

**Interfaces:** None new — reuses `LC.FindUnitForShortName` (existing).

**Root cause / gap (confirmed):** each row is one combined FontString (`"%s -> %s"`, item then winner name) with no click handling at all beyond the existing "mark as done" checkbox — there's no way to interact with the name specifically. `CheckInteractDistance(unit, 2)` (trade range) and `InitiateTrade(unit)` are standard, well-established WoW APIs for exactly this (verified against Warcraft Wiki) but aren't used anywhere in this codebase yet.

- [ ] **Step 1: Split the combined text into an item label and a clickable name button; enlarge the frame and its row spacing**

Locate:

```lua
function LC.CreateTradeReminderFrame()
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(260, 40)
    f:SetPoint("CENTER", -220, 0)
```

Replace with:

```lua
function LC.CreateTradeReminderFrame()
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(320, 40)
    f:SetPoint("CENTER", -220, 0)
```

Locate:

```lua
        row = CreateFrame("Frame", nil, f)
            row:SetHeight(20)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -28, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetPoint("RIGHT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row.doneBtn = CreateFrame("Button", nil, f)
```

Replace with:

```lua
        row = CreateFrame("Frame", nil, f)
            row:SetHeight(26)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -28, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            -- Separate, clickable element for just the winner's name — the item text above stays
            -- a plain FontString (no per-item action to take on it here).
            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetPoint("LEFT", row.text, "RIGHT", 4, 0)
            row.nameBtn:SetHeight(16)
            row.nameBtn.text = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameBtn.text:SetPoint("LEFT")
            row.nameBtn.text:SetPoint("RIGHT")
            row.nameBtn.text:SetJustifyH("LEFT")
            row.nameBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(KART.Theme.AccentColor()) end)
            row.nameBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)

            row.doneBtn = CreateFrame("Button", nil, f)
```

- [ ] **Step 2: Wire the name button to target + trade, with a range check**

Locate:

```lua
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -8 - 20 - (i - 1) * 20)
        row:SetPoint("RIGHT", -28, 0)
        row.text:SetText(string.format(KART.L.LC_TRADE_REMINDER_ROW, entry.itemLink or "???", entry.winnerShort or "?"))
        local capturedRollID = entry.rollID
        row.doneBtn:SetScript("OnClick", function() LC.RemovePendingTrade(capturedRollID) end)
        row:Show()
    end
    for i = #LC.pendingTrades + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(8 + 20 + #LC.pendingTrades * 20 + 8)
```

Replace with:

```lua
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -8 - 26 - (i - 1) * 26)
        row:SetPoint("RIGHT", -28, 0)
        row.text:SetText(entry.itemLink or "???")
        row.nameBtn.text:SetText(entry.winnerShort or "?")
        local capturedRollID = entry.rollID
        local capturedWinnerShort = entry.winnerShort
        row.doneBtn:SetScript("OnClick", function() LC.RemovePendingTrade(capturedRollID) end)
        row.nameBtn:SetScript("OnClick", function()
            local unit = capturedWinnerShort and LC.FindUnitForShortName(capturedWinnerShort)
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, capturedWinnerShort or "?"))
                return
            end
            if not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, capturedWinnerShort))
                return
            end
            TargetUnit(unit)
            InitiateTrade(unit)
        end)
        row:Show()
    end
    for i = #LC.pendingTrades + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(8 + 26 + #LC.pendingTrades * 26 + 8)
```

- [ ] **Step 3: Add the two new locale strings**

In `Locales/enUS.lua`, near `LC_TRADE_REMINDER_DONE`, add:

```lua
    LC_TRADE_TARGET_NOT_FOUND = "%s isn't in your group.",
    LC_TRADE_OUT_OF_RANGE     = "Get closer to %s to trade.",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_TRADE_TARGET_NOT_FOUND = "%s ist nicht in deiner Gruppe.",
    LC_TRADE_OUT_OF_RANGE     = "Geh näher an %s heran, um zu traden.",
```

- [ ] **Step 4: Manual verification (needs two clients)**

With a pending trade entry showing, click the winner's name while out of trade range — confirm the "get closer" message prints and no trade window opens. Move into range and click again — confirm you're targeted onto them and the trade window opens. Confirm the window is visibly wider and rows have more breathing room than before.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: click a name in the trade reminder to target and initiate the trade; enlarge the window"
```

---

### Task 5: Player-side reminder to trade the lootmaster for an item you won

**Files:**
- Modify: `LootCouncil.lua:3198-3226` (`LC.HandleResult`, adds population), new function pair mirroring `LC.CreateTradeReminderFrame`/`LC.RefreshTradeReminder`, new function mirroring `LC.OnTradeClosed` (from the bugfix plan's Task 7)
- Modify: `LootCouncil.lua` (`LC.ClearRollState`, extend to clear the new table)

**Interfaces:**
- Produces: `LC.owedToMe` — array of `{rollID, itemLink, lootmasterShort}`.
- Produces: `LC.FindUnitForLootmaster()` — resolves `LC.GetLootmaster()`'s value (which, per its own doc comment, may be a real short name OR an NSRT nickname — **not** safe to pass straight into `LC.FindUnitForShortName`) to an actual raid unit token, the same way `LC.IsMe` resolves it against just "player".
- Produces: `LC.CreateOwedReminderFrame()`, `LC.RefreshOwedReminder()` — near-exact mirrors of the lootmaster's own `LC.CreateTradeReminderFrame`/`LC.RefreshTradeReminder`, shown to the item's winner instead.

**Root cause / gap (confirmed):** the winner of an item currently only gets an 8-second `LC.ShowWinnerNotification` popup (`LootCouncil.lua:3212-3214`) — nothing persists afterward telling them "you still need to go trade the lootmaster for this." Unlike `LC.FindUnitForShortName` (used correctly elsewhere for real short names), `LC.GetLootmaster()`'s value cannot be matched directly against `UnitName(unit)` — it's lowercased, and per its own doc comment may be an NSRT nickname instead of a character name at all.

- [ ] **Step 1: Add the nickname-aware lootmaster unit resolver**

In `LootCouncil.lua`, immediately after `LC.IsMe` (the function ending `return KART.GetNickname("player") == configuredName\nend`), add:

```lua
-- Same resolution LC.IsMe does for "am I the lootmaster", generalized to "which raid unit is the
-- lootmaster" — needed because LC.GetLootmaster()'s value may be a real short name OR an NSRT
-- nickname (see its own doc comment), so it can't be matched directly against LC.FindUnitForShortName
-- (which only ever compares against real UnitName() short names).
function LC.FindUnitForLootmaster()
    local configuredName = LC.GetLootmaster()
    if configuredName == "" then return nil end
    local isRaid = IsInRaid()
    local numMem = GetNumGroupMembers()
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short = (fullName:match("([^%-]+)") or ""):lower()
            if short == configuredName or KART.GetNickname(unit) == configuredName then
                return unit
            end
        end
    end
    return nil
end
```

- [ ] **Step 2: Populate `LC.owedToMe` when you win something**

Locate (from the bugfix plan's Task 6, which already added an `LC.AddPendingTrade` call to `HandleResult`):

```lua
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    if winner == myShort then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
    end
```

Replace with:

```lua
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    if winner == myShort then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
        -- If I'm also the lootmaster, I already have the item — nothing to trade myself for.
        if not LC.IsMe(LC.GetLootmaster()) then
            LC.owedToMe = LC.owedToMe or {}
            table.insert(LC.owedToMe, {rollID = rollID, itemLink = LC.rollItems[rollID], lootmasterShort = LC.GetLootmaster()})
            LC.RefreshOwedReminder()
        end
    end
```

- [ ] **Step 3: Add the owed-reminder frame (near-mirror of `LC.CreateTradeReminderFrame`/`LC.RefreshTradeReminder`)**

Add directly after `LC.RefreshTradeReminder` (the function from the bugfix plan ending `f:SetHeight(...)\nend`):

```lua
-- Removes rollID from LC.owedToMe, if present, and rebuilds the window.
function LC.RemoveOwedItem(rollID)
    for i = #(LC.owedToMe or {}), 1, -1 do
        if LC.owedToMe[i].rollID == rollID then table.remove(LC.owedToMe, i) end
    end
    LC.RefreshOwedReminder()
end

function LC.CreateOwedReminderFrame()
    local f = CreateFrame("Frame", "KART_LCOwedReminder", UIParent, "BackdropTemplate")
    f:SetSize(320, 40)
    f:SetPoint("CENTER", 220, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcOwedReminderPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(KART.L.LC_OWED_REMINDER_TITLE)

    f.rows = {}

    local pos = KART_Settings and KART_Settings.lcOwedReminderPos
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    LC.owedReminderFrame = f
end

-- Rebuilds the reminder list from LC.owedToMe; hides the frame entirely once it's empty.
function LC.RefreshOwedReminder()
    LC.owedToMe = LC.owedToMe or {}
    if #LC.owedToMe == 0 then
        if LC.owedReminderFrame then LC.owedReminderFrame:Hide() end
        return
    end

    if not LC.owedReminderFrame then LC.CreateOwedReminderFrame() end
    local f = LC.owedReminderFrame

    for i, entry in ipairs(LC.owedToMe) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetHeight(26)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -10, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetPoint("LEFT", row.text, "RIGHT", 4, 0)
            row.nameBtn:SetHeight(16)
            row.nameBtn.text = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameBtn.text:SetPoint("LEFT")
            row.nameBtn.text:SetPoint("RIGHT")
            row.nameBtn.text:SetJustifyH("LEFT")
            row.nameBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(KART.Theme.AccentColor()) end)
            row.nameBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)

            f.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -8 - 26 - (i - 1) * 26)
        row:SetPoint("RIGHT", -10, 0)
        row.text:SetText(entry.itemLink or "???")
        row.nameBtn.text:SetText(entry.lootmasterShort or "?")
        row.nameBtn:SetScript("OnClick", function()
            local unit = LC.FindUnitForLootmaster()
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, entry.lootmasterShort or "?"))
                return
            end
            if not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, entry.lootmasterShort or "?"))
                return
            end
            TargetUnit(unit)
            InitiateTrade(unit)
        end)
        row:Show()
    end
    for i = #LC.owedToMe + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(8 + 26 + #LC.owedToMe * 26 + 8)
    f:Show()
end
```

- [ ] **Step 4: Clear it on `TRADE_CLOSED` (reusing the bugfix plan's Task 7 event) and on `LC.ClearRollState`**

Locate `LC.OnTradeClosed` (added by the bugfix plan):

```lua
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    LC.currentTradePartnerShort = nil
    if not partnerShort then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerShort == partnerShort and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end
```

Replace with:

```lua
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    LC.currentTradePartnerShort = nil
    if not partnerShort then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerShort == partnerShort and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end

    -- Mirror check for the recipient side: if I just traded with the lootmaster and the item I
    -- was owed is now in MY bags, the trade succeeded from my end too.
    for i = #(LC.owedToMe or {}), 1, -1 do
        local entry = LC.owedToMe[i]
        if entry.lootmasterShort == partnerShort and FindItemInBags(entry.itemLink) then
            LC.RemoveOwedItem(entry.rollID)
        end
    end
end
```

This relies on `LC.currentTradePartnerShort` being set even when *you* have nothing pending to place yourself — the bugfix plan's Task 7 already sets it unconditionally, before its own `#LC.pendingTrades` handling, specifically so a winner with nothing of their own pending (the normal case) still gets it populated when they open a trade with the lootmaster. No further change needed here — just confirm this is still true against the actual shipped code before relying on it.

Locate `LC.ClearRollState` (added by the bugfix plan):

```lua
function LC.ClearRollState(rollID)
    LC.votes[rollID]           = nil
    LC.rolls[rollID]           = nil
    LC.councilVotes[rollID]    = nil
    LC.rollItems[rollID]       = nil
    LC.rollDeadlines[rollID]   = nil
    LC.rollDurations[rollID]   = nil
    LC.assignedWinners[rollID] = nil
    LC.votedByMe[rollID]       = nil
    LC.votedNoteByMe[rollID]   = nil
    LC.councilTabsNew[rollID]  = nil
    LC.RemovePendingTrade(rollID)
end
```

Replace with:

```lua
function LC.ClearRollState(rollID)
    LC.votes[rollID]           = nil
    LC.rolls[rollID]           = nil
    LC.councilVotes[rollID]    = nil
    LC.rollItems[rollID]       = nil
    LC.rollDeadlines[rollID]   = nil
    LC.rollDurations[rollID]   = nil
    LC.assignedWinners[rollID] = nil
    LC.votedByMe[rollID]       = nil
    LC.votedNoteByMe[rollID]   = nil
    LC.councilTabsNew[rollID]  = nil
    LC.RemovePendingTrade(rollID)
    LC.RemoveOwedItem(rollID)
end
```

- [ ] **Step 5: Add the locale string**

In `Locales/enUS.lua`, near `LC_TRADE_REMINDER_TITLE`, add:

```lua
    LC_OWED_REMINDER_TITLE = "Items you still need to collect",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_OWED_REMINDER_TITLE = "Items, die du noch abholen musst",
```

- [ ] **Step 6: Manual verification (needs two clients)**

Have Client A (not the lootmaster) win an item via Council. Confirm the winner-notification popup shows as before, and confirm a new "Items you still need to collect" window also appears on Client A listing the item and the lootmaster's name. Click the lootmaster's name while out of range — confirm the range message. Move into range, click again, confirm targeting + trade window opens, complete the trade, confirm the entry disappears from Client A's window (and the corresponding entry disappears from the lootmaster's own Trade Reminder window per the bugfix plan's Task 7).

- [ ] **Step 7: Commit**

```bash
git add LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add a player-side reminder + one-click trade to collect an item you won from Council"
```

---

### Task 6: Raise the vote timer's maximum from 60 to 180 seconds

**Files:**
- Modify: `LootCouncil.lua:3430-3432` (`KART.LC.SldVoteTimer`)

**Interfaces:** None — `KART.CreateSettingsSlider` (`Utils.lua:500`) is a generic, reusable helper already used by other settings sliders in the addon; only this one call site's arguments change.

- [ ] **Step 1: Raise the max**

Locate:

```lua
    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 60, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)
```

Replace with:

```lua
    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 180, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)
```

- [ ] **Step 2: Manual verification**

`/reload`, open Loot Council settings, drag the vote-timer slider to its new maximum and confirm it reads 180 (not clipped/truncated by the slider's value-text width), confirm dragging works smoothly across the wider range, and confirm a real/test roll actually waits the configured duration before its deadline passes.

- [ ] **Step 3: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: allow the vote timer to be set up to 3 minutes instead of 1"
```

---

### Task 7: A dedicated, working font-size setting for the Loot Council windows

**Files:**
- Modify: `LootCouncil.lua:1711-1867` (`LC.CreateCouncilPanel`, exposes the column-header FontStrings as `f.` fields)
- Modify: `LootCouncil.lua:773-914` / `1055-1210` (end of `RefreshVoteListRows_Spacious`/`_Compact`, adds a call)
- Modify: `LootCouncil.lua:1968-2220` (end of `RefreshCouncilRows`), `LootCouncil.lua` (end of `RefreshCouncilTabs`)
- Modify: `LootCouncil.lua:3430-3439` (raid-wide settings box, adds a new slider next to the vote-timer one)
- Modify: `Core.lua:416-543` (`KART.UpdateStyles`, adds one call)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua` (new slider label/tooltip)

**Interfaces:**
- Produces: `LC.ApplyFontSize()` — re-applies `KART_Settings.lcFontSize` (a new, LootCouncil-specific setting, independent from the main window's `contentFontSize`) to every text element in the vote-list window and the council panel. Called from `KART.UpdateStyles()` (so it participates in the existing settings-change refresh) and from the end of each of the four refresh functions listed above (so newly-created rows/tabs get sized immediately, not just on the next settings change).

**Root cause (confirmed):** both LootCouncil windows mix hardcoded literal point sizes (`SetFont("Fonts\\FRIZQT__.TTF", 14, "")` on item text, `12`/`11` on timer/gain text) with completely untouched Blizzard font templates (`GameFontHighlightSmall`/`GameFontNormalSmall`/`GameFontHighlight` on most row text, column headers, and the council panel's own title) — and *neither* path is wired into `KART.UpdateStyles()`, unlike the Main window, Loot History, and BuffCheck windows, which all explicitly re-apply `KART_Settings.contentFontSize`/`titleFontSize` on every settings change. This is exactly "some things scale, most don't" — the one element that *does* already track font-size settings correctly is `row.noteLabel` (registered in `KART.DynamicLabels`), which is the exception, not the rule. Per the request, this adds a **separate** `lcFontSize` setting rather than wiring these into the existing global `contentFontSize`, since these windows' dense grid/card layouts don't necessarily want the same size as the rest of the addon.

- [ ] **Step 1: Expose the council panel's column-header FontStrings as `f.` fields**

Locate (only `hRoll` is currently exposed, for an unrelated show/hide reason):

```lua
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
```

Change to:

```lua
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hName = hName
```

Apply the identical one-line addition (`f.hRank = hRank`, `f.hIlvl = hIlvl`, `f.hVote = hVote`, `f.hCouncilVotes = hCouncilVotes`, `f.hGain = hGain`) immediately after each of the other five column-header `local h... = f:CreateFontString(...)` lines in this same block (`hRank`, `hIlvl`, `hVote`, `hCouncilVotes`, `hGain` — `hRoll` already has its `f.hRoll = hRoll` line, don't duplicate it).

- [ ] **Step 2: Add `LC.ApplyFontSize()`**

Add it near the top of `LootCouncil.lua`, after `LC.GetRaidMinQuality`/before the `GetButtonConfig`/`GetLootmaster` block (anywhere after `KART.GetFontPath` is known to exist, which it does — `Core.lua`'s `KART.UpdateStyles` already calls it, so it's a `KART.` global, not file-scoped):

```lua
-- Applies the LootCouncil-specific font size (KART_Settings.lcFontSize, independent from the main
-- window's Content Font Size) to every text element in the vote-list window and the council panel
-- — see the root-cause note on this task for why neither window currently tracks any font setting
-- at all. Three tiers relative to the base size preserve the existing visual hierarchy (item name
-- and window title bigger, column headers smaller) while making all of them move together.
function LC.ApplyFontSize()
    local fontPath = KART.GetFontPath(KART_Settings.fontName)
    local base  = KART_Settings.lcFontSize or 12
    local big   = base + 2   -- item name / window title
    local small = math.max(8, base - 2) -- column headers

    local function setAll(list, size)
        for _, elem in ipairs(list) do
            if elem then elem:SetFont(fontPath, size, "") end
        end
    end

    local vf = LC.voteListFrame
    if vf then
        for _, row in ipairs(vf.rows or {}) do
            setAll({row.itemText}, big)
            setAll({row.timerText, row.gainText, row.votedText}, base)
            for _, btn in ipairs(row.voteButtons or {}) do
                if btn.text then btn.text:SetFont(fontPath, base, "") end
            end
        end
        for _, row in ipairs(vf.compactRows or {}) do
            setAll({row.itemText}, big)
            setAll({row.timerText, row.gainText, row.votedText}, base)
            -- Compact layout's vote "chips" are icon-only (see RefreshVoteListRows_Compact) —
            -- no button text to size here.
        end
    end

    local cp = LC.councilPanel
    if cp then
        setAll({cp.title, cp.itemText}, big)
        setAll({cp.timerText, cp.ilvlText}, base)
        setAll({cp.hName, cp.hRank, cp.hIlvl, cp.hVote, cp.hRoll, cp.hCouncilVotes, cp.hGain}, small)
        for _, row in ipairs(cp.rows or {}) do
            setAll({row.nameText, row.rankText, row.equippedText, row.voteText, row.rollText, row.gainText}, base)
            if row.councilVoteBtn and row.councilVoteBtn.text then
                row.councilVoteBtn.text:SetFont(fontPath, base, "")
            end
        end
        for _, tab in ipairs(cp.tabs or {}) do
            if tab.countText then tab.countText:SetFont(fontPath, small, "") end
        end
    end
end
```

- [ ] **Step 3: Call it at the end of the row/tab refresh functions, so newly-created rows are sized immediately**

At the end of `LC.RefreshVoteListRows_Spacious`, `LC.RefreshVoteListRows_Compact`, `LC.RefreshCouncilRows`, and `LC.RefreshCouncilTabs` — locate each function's final `end` and add a call directly before it:

```lua
    LC.ApplyFontSize()
end
```

(If a function's last statement is itself inside a conditional block whose closing `end` isn't the function's own final `end`, add the call right before the function's own closing `end`, not an inner one — check indentation to tell them apart.)

- [ ] **Step 4: Call it from `KART.UpdateStyles` too, so changing the setting updates already-open windows**

In `Core.lua`, locate:

```lua
    -- Font changes can re-flow the Loot Council raid box (RelayoutRaidBox above), which
    -- changes the active tab's content height — keep the scroll range in sync.
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
end
```

Replace with:

```lua
    if KART.LC and KART.LC.ApplyFontSize then KART.LC.ApplyFontSize() end

    -- Font changes can re-flow the Loot Council raid box (RelayoutRaidBox above), which
    -- changes the active tab's content height — keep the scroll range in sync.
    if KART.UpdateScrollRange then KART.UpdateScrollRange() end
end
```

- [ ] **Step 5: Add the new slider next to the vote-timer one**

Locate (this is the vote-timer slider, right before the rolls-enabled checkbox):

```lua
    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 180, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    -- Opt-in random 1-100 roll per raider, shown as its own column in the council panel —
```

Replace with:

```lua
    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 180, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    -- Independent from the main window's Content Font Size — the vote-list/council-panel grid
    -- layouts don't necessarily want the same size as the rest of the addon (see LC.ApplyFontSize).
    KART.LC.SldFontSize = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_FONT_SIZE, 8, 20, "lcFontSize",
        -104, "KART_LCFontSizeSlider", L.LC_DESC_FONT_SIZE)
    KART.LC.SldFontSize:HookScript("OnValueChanged", function() if LC.ApplyFontSize then LC.ApplyFontSize() end end)

    -- Opt-in random 1-100 roll per raider, shown as its own column in the council panel —
```

This adds a slider 52px below the vote-timer one (matching the `-52`/`-104` vertical rhythm already used for the settings in this box) and hooks its value change straight to `LC.ApplyFontSize` for live preview while dragging, in addition to the `KART.UpdateStyles()` call `KART.CreateSettingsSlider`'s own `OnValueChanged` already triggers (see `Utils.lua:557`).

Locating this insertion point shifts everything below it in `layoutRaidBox` down — check whether any other slider/checkbox in this box is positioned with a hardcoded Y-offset relative to a *following* element rather than computed relative to the previous one (the raidlead-settings-sync plan's own note about `layoutRaidBox` computing a running `y` suggests it's dynamic, in which case no other position needs manual adjustment — confirm this against the actual code before assuming it).

- [ ] **Step 6: Add the locale strings**

In `Locales/enUS.lua`, near `LC_SET_VOTE_TIMER`/`LC_DESC_VOTE_TIMER`, add:

```lua
    LC_SET_FONT_SIZE  = "Loot Council Font Size",
    LC_DESC_FONT_SIZE = "Text size for the vote window and council panel, independent from the main window's font size.",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_SET_FONT_SIZE  = "Loot-Council-Schriftgröße",
    LC_DESC_FONT_SIZE = "Textgröße für Abstimmungsfenster und Council-Panel, unabhängig von der Schriftgröße des Hauptfensters.",
```

- [ ] **Step 7: Manual verification**

`/reload`, open Loot Council settings, drag the new font-size slider — confirm both windows visibly update live while dragging (via the `OnValueChanged` hook from Step 5), not just after releasing. Run a test roll and confirm item text, timer, vote-button labels, and (with the council panel open) column headers and per-row text all scale together, keeping their existing relative size differences (item name still visibly bigger than a column header, etc.). Close and reopen both windows and confirm the size persists across `/reload`.

- [ ] **Step 8: Commit**

```bash
git add LootCouncil.lua Core.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add a dedicated, working font-size setting for the Loot Council windows"
```

---

### Task 8: GUID-based player identity — architecture note (needs its own dedicated plan, not implemented here)

**This task is intentionally not code-complete.** It documents a real, confirmed root cause and points at the right fix, but the fix touches too much of the file to respons­ibly spec line-by-line in this document — it needs its own `superpowers:brainstorming` + `superpowers:writing-plans` pass before any of it is implemented. Do not attempt to execute this task from the text below alone.

**Root cause (confirmed):** every identity check in `LootCouncil.lua` compares short-name strings (`shortName:lower()`, stripped of any realm suffix via `:match("([^%-]+)")`) — never a permanent, unique identifier. A grep for this pattern (`[senderShort]`, `[shortName]`, `[myShort]`, `[playerShort]`, `[winnerShort]`, `CouncilNamesTable[...]`, and the realm-strip idiom itself) turns up **45 occurrences** across the file. Two real, different players who happen to share a short character name — on different (connected) realms, which the fixed council-list realm-suffix bug above specifically has to account for — silently collide under this scheme: `LC.votes[rollID][shortName]`, `LC.rolls[rollID][shortName]`, `LC.CouncilNamesTable[shortName]`, `LC.raidConfig.lootmaster`, `KART.PlayerVersions[shortName]` and every other per-player table in the addon would treat them as the same person.

**How RCLootCouncil avoids this class of bug entirely:** confirmed by reading its actual source (`Classes/Data/Council.lua`, `Classes/Data/Player.lua` in `github.com/evil-morfar/RCLootCouncil2`). It never compares name strings for identity. Every player is resolved once, via `Player:Get(input)`, to a `Player` object keyed by **`UnitGUID`** — a permanent, globally-unique Blizzard identifier that has no realm ambiguity and cannot collide, ever. Council membership is `council[guid] = player` (`Council:Add`/`Council:Contains`/`Council:Remove`), not `council[name] = true`. Name strings are only ever used at two boundaries: parsing user input (via Blizzard's own `Ambiguate(name, "none")`, which is the correct built-in API for exactly this ambiguity — confirmed via Warcraft Wiki: `"none"` returns the bare name when unambiguous and automatically keeps the `-Realm` suffix only when two same-named characters would otherwise collide) and formatting a name for display (`Ambiguate(name, "short")`, always bare). Between those two boundaries, only the GUID is ever compared.

**What the equivalent fix in KART would mean (scope, not a task list):**
- A `Player`-like resolution step (`LC.ResolvePlayer(input)` or similar) that turns any short name, full name, nickname, or unit token into a stable key — most simply the raw `UnitGUID`, falling back to the realm-qualified `Ambiguate(name, "none")` string for players not currently in the group (a GUID can only be obtained for someone actually visible/grouped; RCLootCouncil's own `Player:Get` has the same fallback chain — cache, then guild roster, then a logged failure).
- Every one of the ~45 sites above re-keyed to use that stable key instead of the bare short name — this includes the wire protocol (`LC_VOTE`, `LC_ROLL`, `LC_CVOTE`, `LC_RESULT`, version announces, etc.), which currently transmits short names on the assumption the receiver can re-derive the same short name locally; a GUID-based scheme would need to either transmit GUIDs directly (they're safe to send, unlike sensitive data) or transmit the realm-qualified name and resolve to GUID on receipt.
- `LC.CouncilNamesTable`/`KART_Settings.lcCouncilMembers`/`KART_Settings.lcLootmaster` (free-text fields the raid leader types names into) would need a resolution step at save-time (parse each typed name via `Ambiguate`/roster lookup into a GUID or realm-qualified form) rather than storing the raw typed text.
- A persistent, cross-session player cache (`KART_PlayerCache` or similar, modeled on RCLootCouncil's `addon.db.global.playerCache`) so nicknames/names typed for someone not currently in the raid can still resolve later once that GUID is seen again.

This is a multi-file, multi-week-scale rewrite touching the wire protocol, every vote/roll/council table, and the settings UI — not a bugfix-sized change. Flagging it here, with the concrete evidence and the reference implementation to copy from, so it can be scoped as its own project when there's appetite for it.

---

### Task 9: Reliable trade-completion detection via `UI_INFO_MESSAGE`, not just a bag re-scan

**Files:**
- Modify: `Core.lua` (register `TRADE_ACCEPT_UPDATE` and `UI_INFO_MESSAGE`, two new dispatch arms)
- Modify: `LootCouncil.lua` (`LC.OnTradeClosed`, two new functions, one new state table)

**Interfaces:**
- Produces: `LC.OnTradeAcceptUpdate()` — called from `Core.lua`'s `TRADE_ACCEPT_UPDATE` handler.
- Produces: `LC.OnTradeInfoMessage(msgID)` — called from `Core.lua`'s `UI_INFO_MESSAGE` handler, passed Blizzard's `arg1`.
- Produces: `LC.tradeWindowItemStrings` — a set (`[itemString] = true`) of exactly what's currently sitting in *our own* trade slots, rebuilt every time the trade offer changes. Consumed by this task's own `LC.OnTradeClosed` rewrite and by Task 10 (wrong-trade-partner warning), which reads the same table.

**Root cause this improves on:** the bugfix plan's Task 7 (already shipped) treats "the item is no longer in my bags" as the only completion signal. That's a reasonable fallback, but it's indirect — it infers success from an absence, and (as the FindItemInBags fix above already had to account for) bag contents can change for unrelated reasons. RCLootCouncil's `TradeUI.lua` instead listens for Blizzard's own explicit trade-succeeded signal: `UI_INFO_MESSAGE` firing with `arg1 == LE_GAME_ERR_TRADE_COMPLETE` (confirmed present in RCLootCouncil's shipped, working `OnEvent_UI_INFO_MESSAGE`). Pairing that with a `TRADE_ACCEPT_UPDATE` snapshot of exactly which items were in the trade window (also copied from RCLootCouncil's pattern — it does not trust re-reading trade slots at `UI_INFO_MESSAGE` time, since the frame may already be tearing down by then) gives a precise, first-party "yes, specifically this item was just traded" signal, with the existing bag-scan kept as a fallback for the rare case the event doesn't fire.

- [ ] **Step 1: Register the two new events**

In `Core.lua`, locate:

```lua
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
```

Replace with:

```lua
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("UI_INFO_MESSAGE")
```

- [ ] **Step 2: Dispatch both events**

Locate:

```lua
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.OnTradeClosed() end
```

Replace with:

```lua
    elseif event == "TRADE_SHOW" then
        if KART.LC then KART.LC.OnTradeShow() end

    elseif event == "TRADE_CLOSED" then
        if KART.LC then KART.LC.OnTradeClosed() end

    elseif event == "TRADE_ACCEPT_UPDATE" then
        if KART.LC then KART.LC.OnTradeAcceptUpdate() end

    elseif event == "UI_INFO_MESSAGE" then
        if KART.LC then KART.LC.OnTradeInfoMessage(arg1) end
```

- [ ] **Step 3: Add the snapshot table and the two new handlers**

In `LootCouncil.lua`, locate (this is `GetItemString`, added by the standalone bonus-ID-matching fix that already shipped):

```lua
local function GetItemString(link)
    return IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
end
```

Add directly after it:

```lua
-- What's currently sitting in *our own* trade slots, rebuilt on every TRADE_ACCEPT_UPDATE — the
-- only reliable moment to read them, since the trade frame may already be tearing down by the
-- time UI_INFO_MESSAGE's trade-complete fires (see LC.OnTradeInfoMessage). Keyed by item string
-- (bonus-ID aware, see GetItemString) so this composes correctly with LC.OnTradeClosed below.
LC.tradeWindowItemStrings = LC.tradeWindowItemStrings or {}

function LC.OnTradeAcceptUpdate()
    wipe(LC.tradeWindowItemStrings)
    for i = 1, 6 do -- MAX_TRADE_ITEMS - 1, fixed by the trade UI (slot 6 is "will not be traded")
        local link = GetTradePlayerItemLink(i) ---@diagnostic disable-line: undefined-global
        local itemString = GetItemString(link)
        if itemString then LC.tradeWindowItemStrings[itemString] = true end
    end
end

-- Blizzard's own explicit trade-succeeded signal (LE_GAME_ERR_TRADE_COMPLETE) — a direct, first-
-- party confirmation rather than inferring success from bag contents. Only records that *a* trade
-- completed; LC.OnTradeClosed cross-references LC.tradeWindowItemStrings to know *which* items.
function LC.OnTradeInfoMessage(msgID)
    if msgID == LE_GAME_ERR_TRADE_COMPLETE then ---@diagnostic disable-line: undefined-global
        LC.tradeJustSucceeded = true
    end
end
```

- [ ] **Step 4: Use both signals in `LC.OnTradeClosed`, keeping the bag-scan as a fallback**

Locate:

```lua
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    LC.currentTradePartnerShort = nil
    if not partnerShort then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        -- Only treat "not found in bags" as "trade completed" for real, resolved item links.
        -- A "???" placeholder entry (async item-link resolution still pending) would always
        -- report "not found" since the placeholder is not a valid item ID to search bags for,
        -- so we'd falsely mark it completed. Leave such entries alone; the user's manual
        -- "done" checkmark button remains available as the fallback for that edge case.
        if entry.winnerShort == partnerShort and IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end
```

Replace with:

```lua
function LC.OnTradeClosed()
    local partnerShort = LC.currentTradePartnerShort
    local tradeSucceeded = LC.tradeJustSucceeded
    LC.currentTradePartnerShort = nil
    LC.tradeJustSucceeded = nil
    if not partnerShort then wipe(LC.tradeWindowItemStrings) return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerShort == partnerShort then
            -- Primary signal: Blizzard confirmed a trade completed, and this exact item (bonus
            -- IDs included) was one of the items we placed in it.
            local itemString = GetItemString(entry.itemLink)
            local confirmedByTrade = tradeSucceeded and itemString and LC.tradeWindowItemStrings[itemString]
            -- Fallback signal (bugfix plan Task 7): the item is simply gone from our bags. Only
            -- trusted for a real, resolved link — see the "???" placeholder note this replaces.
            local confirmedByBags = IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink)
            if confirmedByTrade or confirmedByBags then
                LC.RemovePendingTrade(entry.rollID)
            end
        end
    end
    wipe(LC.tradeWindowItemStrings)
end
```

- [ ] **Step 5: Manual verification (needs two clients)**

As the lootmaster, open a trade with the winner of a pending item, let auto-trade place it, complete the trade normally. Confirm the entry disappears from the trade reminder immediately (same as before this task). Then repeat but **cancel** the trade instead of completing it — confirm the entry stays pending (unchanged from before). This task's behavioral difference is only observable in edge cases the old bag-scan got wrong (e.g. a duplicate-itemID-different-bonus-ID situation) — no separate observable-in-game test exists for "why" it's more correct, only that the normal cases still work identically.

- [ ] **Step 6: Commit**

```bash
git add Core.lua LootCouncil.lua
git commit -m "feat: confirm trade completion via UI_INFO_MESSAGE instead of only a bag re-scan"
```

---

### Task 10: Warn the lootmaster if an item gets traded to the wrong person

**Files:**
- Modify: `LootCouncil.lua` (`LC.OnTradeClosed`, extended further — builds directly on Task 9's `LC.tradeWindowItemStrings`)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:** Consumes `LC.tradeWindowItemStrings` (Task 9). No new interfaces produced.

**Root cause / feature motivation:** copied from RCLootCouncil's `TradeUI.lua`, which sends a `trade_WrongWinner` comm when the trader hands an item to someone other than its recorded recipient. KART has no equivalent — if the lootmaster fat-fingers a trade to the wrong raider, nothing says so; the pending-trade entry for the *real* winner just sits there looking untouched, with no signal that the physical item is now gone to someone else entirely.

- [ ] **Step 1: Detect it inside the same loop Task 9 added**

Locate (this is Task 9's finished `LC.OnTradeClosed`, specifically its loop body):

```lua
    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerShort == partnerShort then
            -- Primary signal: Blizzard confirmed a trade completed, and this exact item (bonus
            -- IDs included) was one of the items we placed in it.
            local itemString = GetItemString(entry.itemLink)
            local confirmedByTrade = tradeSucceeded and itemString and LC.tradeWindowItemStrings[itemString]
            -- Fallback signal (bugfix plan Task 7): the item is simply gone from our bags. Only
            -- trusted for a real, resolved link — see the "???" placeholder note this replaces.
            local confirmedByBags = IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink)
            if confirmedByTrade or confirmedByBags then
                LC.RemovePendingTrade(entry.rollID)
            end
        end
    end
    wipe(LC.tradeWindowItemStrings)
```

Replace with:

```lua
    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        local itemString = GetItemString(entry.itemLink)
        if entry.winnerShort == partnerShort then
            local confirmedByTrade = tradeSucceeded and itemString and LC.tradeWindowItemStrings[itemString]
            local confirmedByBags = IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink)
            if confirmedByTrade or confirmedByBags then
                LC.RemovePendingTrade(entry.rollID)
            end
        elseif tradeSucceeded and itemString and LC.tradeWindowItemStrings[itemString] then
            -- This item was assigned to someone else entirely, but it was just traded away in a
            -- trade with partnerShort instead — the wrong recipient. Warn loudly; the pending
            -- entry is left in place since the real winner still hasn't received their item.
            print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADED_WRONG_PERSON,
                entry.itemLink or "?", entry.winnerShort or "?", partnerShort))
        end
    end
    wipe(LC.tradeWindowItemStrings)
```

- [ ] **Step 2: Add the warning locale string**

In `Locales/enUS.lua`, near the other `LC_TRADE_` strings, add:

```lua
    LC_TRADED_WRONG_PERSON = "You just traded %s to the wrong person! It was assigned to %s, not %s.",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_TRADED_WRONG_PERSON = "Du hast %s an die falsche Person getradet! Es war %s zugewiesen, nicht %s.",
```

- [ ] **Step 3: Manual verification (needs three characters — lootmaster + the real winner + a third, wrong recipient)**

Assign an item to Winner A. As the lootmaster, deliberately trade the item to a different raider, B, instead. Confirm KART prints the wrong-person warning naming the item, A, and B. Confirm the pending-trade entry for A is still there afterward (unchanged — the real winner still needs the item). Then complete the trade correctly with A and confirm no warning and the entry clears normally.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: warn the lootmaster if an assigned item gets traded to the wrong person"
```

---

### Task 11: Warn before a pending trade's 2-hour Bind-on-Pickup trade window expires

**Files:**
- Modify: `LootCouncil.lua` (`LC.OnStartLootRoll`, `LC.AddPendingTrade`, one new ticker, one new function)
- Modify: `Locales/enUS.lua`, `Locales/deDE.lua`

**Interfaces:**
- Produces: `LC.rollLootedAt` — `[rollID] = GetTime()`, the moment the lootmaster actually won the item (this is when Blizzard's own 2-hour BoP trade-eligibility clock starts, not whenever Council later gets around to deciding a winner — those can be minutes to tens of minutes apart).
- Produces: `LC.CheckTradeTimeouts()` — periodic check, warns once per pending entry as it crosses 100 minutes elapsed (20 minutes of the 2-hour window left, matching RCLootCouncil's own `TIME_REMAINING_WARNING` constant).

**Root cause / feature motivation:** WoW's Bind-on-Pickup trade eligibility lasts exactly 2 hours from the moment the item was looted. KART currently has no awareness of this at all — a pending-trade reminder can sit untouched indefinitely with no warning that the underlying item is about to become permanently untradeable. RCLootCouncil tracks this explicitly (`TIME_REMAINING_WARNING = 1200` seconds, `TradeUI:CheckTimeRemaining`, checked every `TIME_REMAINING_INTERVAL = 300` seconds).

- [ ] **Step 1: Record when the item was actually looted**

Locate (inside `LC.OnStartLootRoll`):

```lua
    if LC.IsMe(lootmaster) then
        -- The lootmaster is the one exception to Auto-Pass: they must physically win every item
        -- (regardless of their own local Auto-Pass setting) so they can trade it out afterwards —
        -- see LC.GetLootmaster for why this is raid-leader-controlled, not a personal toggle.
        ForceWinRoll(rollID)
    elseif KART_Settings.lcAutoPass then
```

Replace with:

```lua
    if LC.IsMe(lootmaster) then
        -- The lootmaster is the one exception to Auto-Pass: they must physically win every item
        -- (regardless of their own local Auto-Pass setting) so they can trade it out afterwards —
        -- see LC.GetLootmaster for why this is raid-leader-controlled, not a personal toggle.
        ForceWinRoll(rollID)
        -- Blizzard's 2-hour Bind-on-Pickup trade window starts now, not whenever Council later
        -- decides a winner — see LC.CheckTradeTimeouts, which measures from this timestamp.
        LC.rollLootedAt = LC.rollLootedAt or {}
        LC.rollLootedAt[rollID] = GetTime()
    elseif KART_Settings.lcAutoPass then
```

- [ ] **Step 2: Carry that timestamp onto the pending-trade entry**

Locate:

```lua
function LC.AddPendingTrade(rollID, playerShort)
    if IsTestRoll(rollID) then return end
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    LC.RemovePendingTrade(rollID)
    if playerShort == myShort then return end

    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerShort = playerShort})
    LC.RefreshTradeReminder()
end
```

Replace with:

```lua
function LC.AddPendingTrade(rollID, playerShort)
    if IsTestRoll(rollID) then return end
    local myShort = (UnitName("player") or ""):match("([^%-]+)") or ""
    LC.RemovePendingTrade(rollID)
    if playerShort == myShort then return end

    local lootedAt = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or GetTime()
    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerShort = playerShort, lootedAt = lootedAt})
    LC.RefreshTradeReminder()
    LC.StartTradeTimeoutTicker()
end
```

- [ ] **Step 3: Add the ticker and the check it runs**

Add directly after `LC.AddPendingTrade` (same file):

```lua
local TRADE_TIMEOUT_SECONDS = 2 * 60 * 60      -- Blizzard's fixed BoP trade-eligibility window
local TRADE_TIMEOUT_WARN_AT = 100 * 60         -- warn with 20 minutes left, same margin RCLootCouncil uses
local TRADE_TIMEOUT_CHECK_EVERY = 5 * 60

-- Warns once (per entry, via entry.timeoutWarned) as a pending trade's item approaches the end of
-- its 2-hour Bind-on-Pickup trade-eligibility window. Never removes the entry itself — that still
-- only happens via LC.OnTradeClosed/manual done/reassignment, same as every other pending-trade
-- removal path; this is purely a heads-up so the lootmaster doesn't lose the item to the timer.
function LC.CheckTradeTimeouts()
    if #LC.pendingTrades == 0 then
        if LC.tradeTimeoutTicker then LC.tradeTimeoutTicker:Cancel() LC.tradeTimeoutTicker = nil end
        return
    end
    local now = GetTime()
    for _, entry in ipairs(LC.pendingTrades) do
        local elapsed = now - (entry.lootedAt or now)
        if not entry.timeoutWarned and elapsed >= TRADE_TIMEOUT_WARN_AT then
            entry.timeoutWarned = true
            local minutesLeft = math.max(0, math.floor((TRADE_TIMEOUT_SECONDS - elapsed) / 60))
            print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADE_TIMEOUT_WARNING,
                entry.itemLink or "?", entry.winnerShort or "?", minutesLeft))
        end
    end
end

-- Lazily started on the first pending trade (not at addon load) so a raid that never uses Loot
-- Council never runs a background ticker at all. Safe to call repeatedly — no-ops if already running.
function LC.StartTradeTimeoutTicker()
    if LC.tradeTimeoutTicker then return end
    LC.tradeTimeoutTicker = C_Timer.NewTicker(TRADE_TIMEOUT_CHECK_EVERY, LC.CheckTradeTimeouts)
end
```

- [ ] **Step 4: Add the warning locale string**

In `Locales/enUS.lua`, near the other `LC_TRADE_` strings, add:

```lua
    LC_TRADE_TIMEOUT_WARNING = "%s (assigned to %s) has only %d minutes left before it can no longer be traded!",
```

In `Locales/deDE.lua`, at the same relative position:

```lua
    LC_TRADE_TIMEOUT_WARNING = "%s (zugewiesen an %s) kann nur noch %d Minuten getradet werden!",
```

- [ ] **Step 5: Manual verification**

This one is impractical to wait out for real (100 minutes) — instead, temporarily change `TRADE_TIMEOUT_WARN_AT` to a small value (e.g. `10`) and `TRADE_TIMEOUT_CHECK_EVERY` to `5` locally while testing, assign an item, wait ~15 seconds, confirm the warning prints once (not repeatedly), then revert both constants to their real values (`100 * 60` / `5 * 60`) before committing. Confirm `#LC.pendingTrades == 0` correctly cancels the ticker (no background timer left running with nothing to check) by clearing all pending trades and checking `LC.tradeTimeoutTicker` is `nil` afterward (e.g. via `/dump KART.LC.tradeTimeoutTicker`).

- [ ] **Step 6: Commit**

```bash
git add LootCouncil.lua Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: warn before a pending trade's 2-hour BoP trade window expires"
```

---

### Task 12: Show "(1/N)" when two or more currently-active rolls are the exact same item

**Files:**
- Modify: `LootCouncil.lua` (new function, three call sites: Spacious vote-list row, Compact vote-list row, council panel's selected-item header)

**Interfaces:**
- Produces: `LC.GetDuplicateOrdinal(rollID)` — returns `""` normally, or `" (i/N)"` when `N ≥ 2` currently-active rolls share the exact same item (bonus IDs included, via the same `GetItemString` the trade-matching fixes use), ordered by ascending rollID so the same physical drop always gets the same ordinal on every client.

**Root cause / feature motivation:** when a boss drops the exact same item twice (same itemID, same bonus IDs — not the tertiary-stat-variant case, which the auto-trade fix already distinguishes), Blizzard issues two independent rolls, not one combined roll (confirmed — Blizzard's group-loot design only stops one person winning *both*, it doesn't merge the rolls). KART shows both as separate rows/tabs, but with identical icon, name, and item link, there's nothing distinguishing them — a voter can't tell which row is "theirs" if they're mentally tracking two, and the lootmaster sees two visually-identical tabs. This doesn't corrupt any data (each rollID's votes stay correctly separate under the hood, per `LC.RefreshCouncilRows`/`LC.HandleVote`), but it's a real source of confusion this task closes with a simple visual marker.

- [ ] **Step 1: Add `LC.GetDuplicateOrdinal`**

Locate (immediately after `FindItemInBags`, which this function's use of `GetItemString` depends on being already defined earlier in the file):

```lua
local function FindItemInBags(itemLink)
```

Add directly before it (same relative position as `GetItemString`, which already precedes `FindItemInBags` — insert this new function after `GetItemString`'s closing `end` and before `FindItemInBags`'s definition):

```lua
-- "" normally, or " (i/N)" when N >= 2 currently-active rolls (LC.rollItems is only ever
-- populated for active ones — see LC.ClearRollState) share the exact same item, bonus IDs
-- included. Ordered by ascending rollID so every client's ordinal for the same physical drop
-- agrees, since all clients see the same rollItems keys via the same broadcasts.
function LC.GetDuplicateOrdinal(rollID)
    local myString = GetItemString(LC.rollItems[rollID])
    if not myString then return "" end
    local matches = {}
    for otherRollID, link in pairs(LC.rollItems) do
        if GetItemString(link) == myString then
            table.insert(matches, otherRollID)
        end
    end
    if #matches < 2 then return "" end
    table.sort(matches)
    for i, id in ipairs(matches) do
        if id == rollID then return string.format(" (%d/%d)", i, #matches) end
    end
    return ""
end
```

- [ ] **Step 2: Use it in the Spacious vote-list row**

Locate:

```lua
        row.itemText:SetText(rollLink or "???")
```

(This exact line appears twice — once in `LC.RefreshVoteListRows_Spacious`, once in `LC.RefreshVoteListRows_Compact`. Both need the identical change; do both.)

Replace each occurrence with:

```lua
        row.itemText:SetText((rollLink or "???") .. LC.GetDuplicateOrdinal(rollID))
```

- [ ] **Step 3: Use it in the council panel's selected-item header**

Locate (inside `LC.SwitchCouncilTab`):

```lua
    panel.itemText:SetText(LC.rollItems[rollID] or "???")
```

Replace with:

```lua
    panel.itemText:SetText((LC.rollItems[rollID] or "???") .. LC.GetDuplicateOrdinal(rollID))
```

- [ ] **Step 4: Manual verification (needs a real or Test-mode duplicate drop)**

Using Test mode, start two test rolls for the exact same item (`LC.StartTest` with the same test item twice, or trigger two real rolls of an identical drop). Confirm both the vote-list rows (Spacious and Compact) and the council panel's header show "(1/2)"/"(2/2)" appended to the item name, consistently ordered the same way across a second client. Confirm a *non*-duplicate roll shows no ordinal suffix at all (not even "(1/1)").

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: mark simultaneous identical-item rolls with a (1/N) ordinal so they're distinguishable"
```

---

### Task 13: Changelog and version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

Confirm the actual current version in `KeineAhnungRaidTools.toc` first (this plan assumes the bugfix plan already shipped `2.5.0`).

- [ ] **Step 1: Bump the addon version**

In `KeineAhnungRaidTools.toc`, change the `## Version:` line to the next minor version after whatever the bugfix plan left it at (e.g. `2.5.0` → `2.6.0`).

- [ ] **Step 2: Add the English changelog entry**

In `CHANGELOG.md`, insert a new section above the previous version's entry:

```markdown
## [2.6.0] - <today's date>
### Added
- **`/kart add <item link>` hands an item back to Loot Council for a decision**, without needing a real loot roll.
- **A voted-on item's card shrinks** in the normal vote-list view instead of leaving empty space where the buttons were.
- **Click a name in the trade reminder to target and open a trade with them** (range-checked).
- **A new reminder window tells you when you still need to trade the lootmaster** for something you won, with the same one-click trade.
- **The vote timer can now be set up to 3 minutes**, up from 1.
- **The Loot Council windows have their own font-size setting**, and it now actually applies to everything in them.
- **Trade completion is now confirmed directly**, not just inferred from your bags.
- **You'll be warned if you trade an assigned item to the wrong person.**
- **You'll be warned before a pending trade's 2-hour tradeable window runs out.**
- **When the same item drops twice at once, each one is now marked "(1/2)"/"(2/2)"** so you can tell them apart.
```

- [ ] **Step 3: Mirror into German changelog**

In `CHANGELOG-de.md`, insert at the same relative position:

```markdown
## [2.6.0] - <today's date>
### Added
- **`/kart add <Item-Link>` gibt ein Item zur Entscheidung an Loot Council zurück**, ohne echten Lootwurf.
- **Eine abgestimmte Item-Karte schrumpft** in der normalen Abstimmungsansicht, statt leeren Platz zu lassen, wo die Buttons waren.
- **Klick auf einen Namen in der Trade-Erinnerung zielt auf die Person und öffnet den Handel** (mit Reichweitenprüfung).
- **Ein neues Erinnerungsfenster zeigt dir, wenn du noch den Lootmaster für ein gewonnenes Item traden musst**, mit demselben Ein-Klick-Handel.
- **Der Abstimmungs-Timer kann jetzt auf bis zu 3 Minuten eingestellt werden**, vorher 1 Minute.
- **Die Loot-Council-Fenster haben jetzt eine eigene Schriftgrößen-Einstellung**, die jetzt tatsächlich überall darin greift.
- **Trade-Abschluss wird jetzt direkt bestätigt**, nicht mehr nur aus deinen Taschen geraten.
- **Du wirst gewarnt, wenn du ein zugewiesenes Item an die falsche Person tradest.**
- **Du wirst gewarnt, bevor das 2-Stunden-Handelsfenster eines ausstehenden Trades abläuft.**
- **Wenn das gleiche Item doppelt gleichzeitig droppt, wird jedes jetzt mit "(1/2)"/"(2/2)" markiert**, damit du sie unterscheiden kannst.
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version, changelog for the loot council feature pass"
```
