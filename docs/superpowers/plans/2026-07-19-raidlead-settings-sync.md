# Raidlead-Only Settings Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a player whisper their Loot Council raid-wide-authority settings (6 fields) to one named target character, who must explicitly accept before anything changes on their end.

**Architecture:** A new whisper-based addon-message pair (`LC_SYNC_REQUEST:` / `LC_SYNC_ACCEPT` / `LC_SYNC_DECLINE`), reusing the existing `"KART"` addon-message prefix and the existing 255-byte truncation approach from `LC.BroadcastRaidConfig`. Sender side is a new button + name-entry popup in `LootCouncil.lua`'s raid-wide settings box. Receiver side is a new branch in `Core.lua`'s existing `CHAT_MSG_ADDON` dispatcher plus a confirm popup that applies the 6 fields into `KART_Settings` and calls the existing `KART.SyncSettingsToUI()` (from the Profiles feature) to refresh the UI.

**Tech Stack:** WoW Lua addon (retail), no build step, no test runner — this project has no automated test suite; verification is manual, in-game, with two characters (this feature is inherently two-player — one client alone cannot fully verify it).

## Global Constraints

- English source: code, comments, commit messages. Update `Locales/enUS.lua` first, mirror into `Locales/deDE.lua` in the same task.
- `CHANGELOG.md` gets one bullet (max 2 lines, bold lead); mirror into `CHANGELOG-de.md` in the same task.
- Exactly 6 fields are synced, no more, no less: `lcMinQuality`, `lcButtonLabels`, `lcRollsEnabled`, `lcLootmaster`, `lcVoteSeconds`, `lcCouncilMembers`.
- No leader-gate on the sending side (deliberate one-to-one consent-gated action, not an automatic raid-wide effect).
- The 255-byte `SendAddonMessage` payload limit applies; truncate the council-member list the same way `LC.BroadcastRaidConfig` already does, reusing the existing `KART.L.LC_CONFIG_TRUNCATED` message for the truncation warning (do not add a new truncation string).
- `CHAT_MSG_ADDON`'s `sender` argument cannot be spoofed by another addon — no additional trust/leader check is needed before showing the receiver's confirm popup (the popup itself, requiring an explicit human Accept click, is the trust boundary).

---

### Task 1: Locale strings

**Files:**
- Modify: `Locales/enUS.lua` (after the existing `LC_DESC_TOGGLE` line — search for `LC_BTN_TOGGLE`)
- Modify: `Locales/deDE.lua` (same relative location)

**Interfaces:**
- Produces locale keys consumed by Tasks 2 and 3: `LC_BTN_SYNC_SETTINGS`, `LC_DESC_SYNC_SETTINGS`, `LC_SYNC_TARGET_PROMPT`, `LC_SYNC_TARGET_EMPTY`, `LC_SYNC_REQUEST_TEXT`, `LC_SYNC_ACCEPTED_MSG`, `LC_SYNC_DECLINED_MSG`.

- [ ] **Step 1: Add English strings**

In `Locales/enUS.lua`, immediately after line 196 (`LC_DESC_TOGGLE = "Manually enable or disable Loot Council for the current raid session. Only works when you are the raid leader.",`), add:

```lua
    LC_BTN_SYNC_SETTINGS  = "Sync Settings to Player...",
    LC_DESC_SYNC_SETTINGS = "Send your Loot Council raid-wide settings to one player by name. They must accept before anything changes on their end.",
    LC_SYNC_TARGET_PROMPT = "Enter the character name to sync settings to:",
    LC_SYNC_TARGET_EMPTY  = "Enter a character name.",
    LC_SYNC_REQUEST_TEXT  = "Raidlead-Only Settings Sync from Player %s",
    LC_SYNC_ACCEPTED_MSG  = "%s accepted your raidlead settings sync.",
    LC_SYNC_DECLINED_MSG  = "%s declined your raidlead settings sync.",
```

- [ ] **Step 2: Add German strings**

In `Locales/deDE.lua`, immediately after line 196 (the German `LC_DESC_TOGGLE` line), add:

```lua
    LC_BTN_SYNC_SETTINGS  = "Settings an Spieler senden...",
    LC_DESC_SYNC_SETTINGS = "Sendet deine Loot-Council-Raid-Einstellungen an einen Spieler per Namen. Er muss zustimmen, bevor sich bei ihm etwas ändert.",
    LC_SYNC_TARGET_PROMPT = "Charaktername eingeben, an den synchronisiert werden soll:",
    LC_SYNC_TARGET_EMPTY  = "Bitte einen Charakternamen eingeben.",
    LC_SYNC_REQUEST_TEXT  = "Raidleiter-Settings-Sync von Spieler %s",
    LC_SYNC_ACCEPTED_MSG  = "%s hat deinen Raidleiter-Settings-Sync angenommen.",
    LC_SYNC_DECLINED_MSG  = "%s hat deinen Raidleiter-Settings-Sync abgelehnt.",
```

- [ ] **Step 3: Manual verification**

`/reload`. No Lua error (a stray comma/quote mistake would break the whole addon's load). Nothing references these keys yet, so no visual change is expected.

- [ ] **Step 4: Commit**

```bash
git add Locales/enUS.lua Locales/deDE.lua
git commit -m "feat: add locale strings for raidlead-only settings sync"
```

---

### Task 2: Sender side — send function, button, name-entry popup

**Files:**
- Modify: `LootCouncil.lua` (new function after `LC.HandleConfig`, new `StaticPopupDialogs` entry, new button in the raid-wide settings box, one addition to `layoutRaidBox`)

**Interfaces:**
- Consumes: locale keys from Task 1 (`LC_BTN_SYNC_SETTINGS`, `LC_DESC_SYNC_SETTINGS`, `LC_SYNC_TARGET_PROMPT`, `LC_SYNC_TARGET_EMPTY`, `KART.L.LC_CONFIG_TRUNCATED` — pre-existing), the file-local `ADDON_MSG_MAX_BYTES` constant (already defined at `LootCouncil.lua:244`, in scope for any function defined later in the same file), `KART.TrimString` (existing helper, already used by `LC.BroadcastRaidConfig`).
- Produces: `LC.SendSettingsSync(targetName)` — no return value, whispers the sync-request payload. Task 3 does not call this directly but must produce a compatible payload format on the receiving end (documented below) that this function's output must match exactly.

**Wire format produced by this task (Task 3's receiver must parse this exact shape):**
```
LC_SYNC_REQUEST:<minQuality>:<buttonLabels>:<rollsEnabled 0|1>:<lootmaster>:<voteSeconds>:<councilMembers>
```

- [ ] **Step 1: Add `LC.SendSettingsSync`**

In `LootCouncil.lua`, immediately after the closing `end` of `LC.HandleConfig` (the function ending with `LC.CouncilNamesTable[trimmed] = true end\nend`, right before the `-- Test mode uses a plain coloured string...` comment), add:

```lua
-- Whispers the sender's current Loot Council raid-wide-authority settings to targetName as a
-- sync request; the receiver decides via a confirm popup whether to apply them (Core.lua
-- CHAT_MSG_ADDON -> LC.HandleSyncRequest). Same 255-byte payload budget and council-list
-- truncation approach as LC.BroadcastRaidConfig above.
function LC.SendSettingsSync(targetName)
    local minQ = KART_Settings.lcMinQuality or 4
    local buttons = KART_Settings.lcButtonLabels or ""
    local rolls = KART_Settings.lcRollsEnabled and "1" or "0"
    local lootmaster = KART.TrimString(KART_Settings.lcLootmaster or ""):match("([^%-]+)") or ""
    local voteSeconds = KART_Settings.lcVoteSeconds or 20
    local council = KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_SYNC_REQUEST:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":" .. voteSeconds .. ":"
    local budget = ADDON_MSG_MAX_BYTES - #prefix
    if #council > math.max(budget, 0) then
        council = (budget > 0 and council:sub(1, budget):match("^(.*);")) or ""
        print("|cffff0000KART:|r " .. (KART.L.LC_CONFIG_TRUNCATED or "Council member list too long, truncated for broadcast."))
    end
    C_ChatInfo.SendAddonMessage("KART", prefix .. council, "WHISPER", targetName)
end
```

- [ ] **Step 2: Add the target-name popup**

Directly after the function added in Step 1, add:

```lua
StaticPopupDialogs["KART_LC_SYNC_TARGET"] = {
    text = "Enter the character name to sync settings to:", -- overwritten with KART.L.LC_SYNC_TARGET_PROMPT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 48,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        name = name and name:match("^%s*(.-)%s*$") or ""
        if name == "" then
            UIErrorsFrame:AddMessage(KART.L.LC_SYNC_TARGET_EMPTY, 1, 0.1, 0.1, 1, 3)
            StaticPopup_Show("KART_LC_SYNC_TARGET")
            return
        end
        LC.SendSettingsSync(name)
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        StaticPopupDialogs["KART_LC_SYNC_TARGET"].OnAccept(dialog)
        dialog:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

- [ ] **Step 3: Add the button and wire it into the raid-wide settings box layout**

Locate this exact code (the `BtnToggleSession` block, immediately before `local function layoutRaidBox()`):

```lua
    KART.LC.BtnToggleSession = KART.CreateModernButton(raidBox, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if IsInGroup() and UnitIsGroupLeader("player") then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)

    local function layoutRaidBox()
```

Insert a new button block between the `BtnToggleSession` block and `local function layoutRaidBox()`:

```lua
    KART.LC.BtnToggleSession = KART.CreateModernButton(raidBox, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if IsInGroup() and UnitIsGroupLeader("player") then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)

    KART.LC.BtnSyncSettings = KART.CreateModernButton(raidBox, L.LC_BTN_SYNC_SETTINGS, L.LC_DESC_SYNC_SETTINGS)
    KART.LC.BtnSyncSettings:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnSyncSettings:SetScript("OnClick", function()
        StaticPopupDialogs["KART_LC_SYNC_TARGET"].text = KART.L.LC_SYNC_TARGET_PROMPT
        StaticPopup_Show("KART_LC_SYNC_TARGET")
    end)

    local function layoutRaidBox()
```

Then, inside `layoutRaidBox`, locate this exact tail (the last two statements before `raidBox:SetHeight(-y)`):

```lua
        KART.LC.BtnToggleSession:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 16

        raidBox:SetHeight(-y)
    end
```

Change it to:

```lua
        KART.LC.BtnToggleSession:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 10

        KART.LC.BtnSyncSettings:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 16

        raidBox:SetHeight(-y)
    end
```

`raidBox`'s height and the tab's scroll range are both computed dynamically from this function's final `y` (see `KART.UpdateScrollRange` in `MainFrame.lua`, which reads `KART.LC.RaidBox:GetHeight()` at render time) — no manual `PANEL_CONTENT_HEIGHTS` edit is needed for this tab, unlike the Raidlead/Settings tabs in earlier features.

- [ ] **Step 4: Manual verification**

`/reload`, open `/kart`, go to the Loot Council tab. Confirm the raid-wide settings box now shows a "Sync Settings to Player..." button below "Toggle session", with no visual overlap or clipping. Click it — a popup with a text field appears. Type a name and press Enter (or click the accept button) — popup closes (no error, even though nothing exists yet to receive `LC_SYNC_REQUEST:` — Task 3 adds that; sending to a name with no listener, or to yourself, is harmless and just does nothing observable). Click the button again and submit an empty name — popup reopens with an error message shown via `UIErrorsFrame`.

- [ ] **Step 5: Commit**

```bash
git add LootCouncil.lua
git commit -m "feat: add sender-side raidlead settings sync (button, popup, whisper send)"
```

---

### Task 3: Receiver side — dispatch, confirm popup, apply, ack

**Files:**
- Modify: `LootCouncil.lua` (new functions `LC.HandleSyncRequest`, `LC.HandleSyncAccept`, `LC.HandleSyncDecline`, new `StaticPopupDialogs` entry)
- Modify: `Core.lua` (three new branches in the existing `CHAT_MSG_ADDON` dispatcher)

**Interfaces:**
- Consumes: the wire format from Task 2 (`LC_SYNC_REQUEST:<minQuality>:<buttonLabels>:<rollsEnabled>:<lootmaster>:<voteSeconds>:<councilMembers>`), locale keys from Task 1 (`LC_SYNC_REQUEST_TEXT`, `LC_SYNC_ACCEPTED_MSG`, `LC_SYNC_DECLINED_MSG`), `KART.SyncSettingsToUI()` (already exists, added by an earlier feature's `Core.lua` refactor — no changes needed to it, only a call site).
- Produces: `LC.HandleSyncRequest(payload, sender, senderShort)`, `LC.HandleSyncAccept(senderShort)`, `LC.HandleSyncDecline(senderShort)` — all called only from `Core.lua`'s `CHAT_MSG_ADDON` handler, added in this same task.

- [ ] **Step 1: Add the receiver-side functions**

In `LootCouncil.lua`, immediately after `LC.SendSettingsSync` and its `StaticPopupDialogs["KART_LC_SYNC_TARGET"]` entry (added in Task 2), add:

```lua
-- Runs when a sync-request whisper arrives (Core.lua CHAT_MSG_ADDON -> LC_SYNC_REQUEST:). Shows
-- a confirm popup naming the sender; settings are only applied if the user explicitly accepts.
-- sender is the raw, realm-qualified whisper-reply target; senderShort is for the popup text.
function LC.HandleSyncRequest(payload, sender, senderShort)
    local minQ, buttons, rolls, lootmaster, voteSeconds, council =
        payload:match("^(%d+):([^:]*):([01]):([^:]*):(%d+):(.*)$")
    if not minQ then return end

    StaticPopupDialogs["KART_LC_SYNC_REQUEST"].text = KART.L.LC_SYNC_REQUEST_TEXT
    StaticPopup_Show("KART_LC_SYNC_REQUEST", senderShort, nil, {
        sender = sender,
        minQuality = tonumber(minQ),
        buttonLabels = buttons,
        rollsEnabled = (rolls == "1"),
        lootmaster = lootmaster,
        voteSeconds = tonumber(voteSeconds),
        councilMembers = council,
    })
end

function LC.HandleSyncAccept(senderShort)
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_SYNC_ACCEPTED_MSG, senderShort))
end

function LC.HandleSyncDecline(senderShort)
    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_SYNC_DECLINED_MSG, senderShort))
end

StaticPopupDialogs["KART_LC_SYNC_REQUEST"] = {
    text = "Raidlead-Only Settings Sync from Player %s", -- overwritten with KART.L.LC_SYNC_REQUEST_TEXT before every StaticPopup_Show call
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        KART_Settings.lcMinQuality = data.minQuality
        KART_Settings.lcButtonLabels = data.buttonLabels
        KART_Settings.lcRollsEnabled = data.rollsEnabled
        KART_Settings.lcLootmaster = data.lootmaster
        KART_Settings.lcVoteSeconds = data.voteSeconds
        KART_Settings.lcCouncilMembers = data.councilMembers
        KART.SyncSettingsToUI()
        C_ChatInfo.SendAddonMessage("KART", "LC_SYNC_ACCEPT", "WHISPER", data.sender)
    end,
    OnCancel = function(self, data)
        C_ChatInfo.SendAddonMessage("KART", "LC_SYNC_DECLINE", "WHISPER", data.sender)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

`OnCancel` fires for both an explicit Cancel-button click and dismissal via Escape (this dialog has `hideOnEscape = true`) — both correctly count as "decline" for this feature's purposes.

- [ ] **Step 2: Wire the three new message types into `Core.lua`'s dispatcher**

In `Core.lua`, locate this exact sequence inside the `CHAT_MSG_ADDON` branch (the `LC_HIST_ENTRY:` handler, one of the `elseif` arms):

```lua
                elseif msg:sub(1, 14) == "LC_HIST_ENTRY:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleHistoryEntry(msg:sub(15)) end
```

Immediately after that arm (before the next `elseif` or the closing of the chain — insert it as a new arm right after this one), add:

```lua
                elseif msg:sub(1, 16) == "LC_SYNC_REQUEST:" then
                    if KART.LC and KART_Settings.lcModuleEnabled ~= false then KART.LC.HandleSyncRequest(msg:sub(17), sender, shortName) end
                elseif msg == "LC_SYNC_ACCEPT" then
                    if KART.LC then KART.LC.HandleSyncAccept(shortName) end
                elseif msg == "LC_SYNC_DECLINE" then
                    if KART.LC then KART.LC.HandleSyncDecline(shortName) end
```

(`"LC_SYNC_REQUEST:"` is 16 characters including the trailing colon — `msg:sub(1, 16)` extracts exactly that prefix, and `msg:sub(17)` is everything after it, matching the payload `LC.SendSettingsSync` builds in Task 2.)

- [ ] **Step 3: Manual verification**

Requires two WoW clients/characters (this feature cannot be verified with one). On Client A: Loot Council tab, change one of the 6 synced settings (e.g. Min Item Quality) to a distinct value. Click "Sync Settings to Player...", enter Client B's exact character name, submit. On Client B: a popup appears reading "Raidlead-Only Settings Sync from Player <A's name>". Click Accept — popup closes, open Client B's Loot Council settings tab and confirm all 6 fields now match Client A's values. Client A's chat shows `"KART: <B's name> accepted your raidlead settings sync."`. Repeat the whole flow but click Decline (or press Escape) on Client B this time — confirm Client B's settings are unchanged, and Client A's chat shows the declined message instead.

- [ ] **Step 4: Commit**

```bash
git add LootCouncil.lua Core.lua
git commit -m "feat: add receiver-side raidlead settings sync (confirm popup, apply, ack)"
```

---

### Task 4: Changelog + version bump

**Files:**
- Modify: `KeineAhnungRaidTools.toc`
- Modify: `CHANGELOG.md`
- Modify: `CHANGELOG-de.md`

**Interfaces:** None (docs only).

This project has no "Unreleased" section — every entry is a released, dated version bump. Bump
`KeineAhnungRaidTools.toc`'s `## Version:` line from `2.2.0` to `2.3.0`, dated with today's date.

- [ ] **Step 1: Bump the addon version**

In `KeineAhnungRaidTools.toc`, change:

```
## Version: 2.2.0
```

to:

```
## Version: 2.3.0
```

- [ ] **Step 2: Add the English changelog entry**

In `CHANGELOG.md`, insert a new section above the existing `## [2.2.0] - 2026-07-19` entry:

```markdown
## [2.3.0] - 2026-07-19
### Added
- **Raidlead-Only Settings Sync:** send your Loot Council raid-wide settings to a specific player by name from the Loot Council tab — they see a confirmation popup and must accept before anything changes.
```

- [ ] **Step 3: Mirror into German changelog**

In `CHANGELOG-de.md`, insert at the same relative position:

```markdown
## [2.3.0] - 2026-07-19
### Added
- **Raidleiter-Settings-Sync:** sende deine Loot-Council-Raid-Einstellungen an einen bestimmten Spieler per Namen im Loot-Council-Tab — er sieht ein Bestätigungsfenster und muss zustimmen, bevor sich etwas ändert.
```

- [ ] **Step 4: Commit**

```bash
git add KeineAhnungRaidTools.toc CHANGELOG.md CHANGELOG-de.md
git commit -m "chore: bump version to 2.3.0, changelog entry for raidlead settings sync"
```
