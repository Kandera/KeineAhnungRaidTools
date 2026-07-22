# Loot Council Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **BLOCKED until `docs/superpowers/plans/2026-07-22-loot-council-bugfixes.md` is fully shipped.** Per the project owner's explicit instruction, none of these tasks start before every task in that plan is done — several tasks here directly build on functions that plan adds (`LC.ClearRollState`, `LC.OnTradeClosed`/`TRADE_CLOSED` registration, the `/kart` subcommand dispatcher shape). Re-read the affected files against their post-bugfix state before starting — the bugfix plan shifts line numbers in `LootCouncil.lua` and `Core.lua` that this plan's line references below were taken against the *pre-bugfix* file.

**Goal:** Implement the 8 feature requests gathered after the bugfix testing pass.

**Architecture:** No new subsystems beyond what's described per-task. Every feature reuses the existing `LC_*` addon-message protocol, the existing per-rollID state tables, and the existing settings-slider/button helpers in `Utils.lua`.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — manual, in-game verification only. Several tasks need two characters/clients; noted per task.

## Global Constraints

- English source: code, comments, commit messages; mirror any new locale strings into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets these as `### Added` bullets (one line each, bold lead); mirror into `CHANGELOG-de.md` (Task 8).
- Bump `KeineAhnungRaidTools.toc`'s `## Version:` — this plan assumes the bugfix plan already shipped `2.5.0`, so this bumps `2.5.0` → `2.6.0` (confirm the actual current version at `KeineAhnungRaidTools.toc` before Task 8 in case other work landed in between).
- This plan does not touch the "Known gaps" items from the bugfix plan (Bugs 14b/16/20) — those remain open.

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

### Task 8: Changelog and version bump

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
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version, changelog for the loot council feature pass"
```
