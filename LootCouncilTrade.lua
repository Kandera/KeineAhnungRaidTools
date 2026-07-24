local addonName, KART = ...

KART.LC.Trade = KART.LC.Trade or {}
local Trade = KART.LC.Trade
local LC = KART.LC

-- =====================================================================
--  Result announcement & winner notification
-- =====================================================================

-- reason (optional) is appended to the chat announcement, e.g. "(BIS)"; blank for no reason.
-- reason also travels in the LC_RESULT broadcast so every KART user's loot history stays in sync.
function Trade.AnnounceResult(rollID, winnerKey, reason)
    -- Test rolls stay entirely local: no addon-channel broadcast (which would make every real
    -- raid member's client log a fake history entry / pop a fake "you win" for whoever the
    -- tester happened to click) and no raid-chat spam.
    if not LC.IsTestRoll(rollID) then
        -- Blizzard's rollID isn't guaranteed unique across two real rolls that resolve close
        -- together (e.g. several trash corpses looted within the same second) — it can get
        -- reused for a genuinely different item before every client's window for the first one
        -- has closed. Carrying the itemID lets Trade.HandleResult detect and ignore a result
        -- that landed on a stale, already-reused rollID instead of wrongly acting on it.
        local link = LC.rollItems[rollID] or ""
        local itemID = LC.IsRealItemLink(link) and (link:match("item:(%d+)") or "") or ""
        LC.SendLC("LC_RESULT:" .. rollID .. ":" .. winnerKey .. ":" .. itemID .. ":" .. (reason or ""))

        if winnerKey ~= "NONE" then
            local msg = string.format(KART.L.LC_RESULT_ANNOUNCE, KART.Identity.ResolveDisplayName(winnerKey), link)
            if reason and reason ~= "" then
                msg = msg .. " (" .. reason .. ")"
            end
            if IsInRaid() then
                SendChatMessage(msg, "RAID")   ---@diagnostic disable-line: deprecated
            elseif IsInGroup() then
                SendChatMessage(msg, "PARTY") ---@diagnostic disable-line: deprecated
            end
        end
    end

    if LC.councilPanel and LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
    end
end

local function DoAssignWinner(rollID, playerKey, reason, colorDef)
    local classFile
    local unit = KART.Identity.FindUnitForKey(playerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    Trade.AnnounceResult(rollID, playerKey, reason)

    if LC.IsTestRoll(rollID) then
        -- Test rolls never round-trip through the network (see AnnounceResult), so if the
        -- tester assigned the win to themselves, trigger the "you win" popup locally instead —
        -- and skip writing a fake entry into the real, persistent loot history.
        local myKey = (KART.Identity.ResolvePlayer("player"))
        if playerKey == myKey then
            Trade.ShowWinnerNotification(LC.rollItems[rollID])
        end
    else
        KART.LH.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(playerKey), reason, classFile, colorDef, rollID)
        -- Only the client that actually holds the item (the designated lootmaster, see
        -- LC.GetLootmaster/ForceWinRoll) needs a trade reminder — when the assigner (usually the
        -- raid leader) isn't also the lootmaster, they never physically have the item to trade.
        if LC.IsMe(LC.GetLootmaster()) then
            Trade.AddPendingTrade(rollID, playerKey)
        end
    end
    LC.assignedWinners[rollID] = playerKey
end

-- Awards the item to playerKey (a resolved player identity, see KART.Identity.ResolvePlayer) with
-- the given reason (may be "" for no reason) and logs it. colorDef is the vote-button definition
-- the reason was taken from (nil for "no reason"). If this rollID was already assigned, asks for
-- confirmation first to avoid accidental double entries.
function Trade.AssignWinner(rollID, playerKey, reason, colorDef)
    local prevWinner = LC.assignedWinners[rollID]
    if prevWinner then
        local dialog = StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] ---@diagnostic disable-line: undefined-global
        dialog.text = string.format(KART.L.LC_REASSIGN_CONFIRM_TEXT, KART.Identity.ResolveDisplayName(prevWinner), KART.Identity.ResolveDisplayName(playerKey))
        dialog.OnAccept = function() DoAssignWinner(rollID, playerKey, reason, colorDef) end
        StaticPopup_Show("KART_LC_REASSIGN_CONFIRM") ---@diagnostic disable-line: undefined-global
    else
        DoAssignWinner(rollID, playerKey, reason, colorDef)
    end
end

-- =====================================================================
--  Trade Reminder & Auto-Trade
-- =====================================================================
-- The loot council only decides WHO should get an item — Blizzard's master-loot mechanic still
-- hands the physical item to whoever looted it, so it has to be traded over manually afterwards.
-- This keeps a small reminder list of "who still needs to be traded what", and best-effort
-- auto-places the right item into the trade window once you actually open a trade with them.

-- Adds itemLink for rollID to the pending-trade list for playerShort, unless it's a test roll or
-- the winner is ourselves (nothing to hand over in either case). Replaces any existing pending
-- entry for the same rollID first, so reassigning an item doesn't leave a stale trade reminder
-- pointing at the previous winner.
function Trade.AddPendingTrade(rollID, playerKey)
    if LC.IsTestRoll(rollID) then return end
    local myKey = (KART.Identity.ResolvePlayer("player"))
    Trade.RemovePendingTrade(rollID)
    if playerKey == myKey then return end

    local lootedAt = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or GetTime()
    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerKey = playerKey, lootedAt = lootedAt})
    Trade.RefreshTradeReminder()
    Trade.StartTradeTimeoutTicker()
end

local TRADE_TIMEOUT_SECONDS = 2 * 60 * 60      -- Blizzard's fixed BoP trade-eligibility window
local TRADE_TIMEOUT_WARN_AT = 100 * 60         -- warn with 20 minutes left, same margin RCLootCouncil uses
local TRADE_TIMEOUT_CHECK_EVERY = 5 * 60

-- Warns once (per entry, via entry.timeoutWarned) as a pending trade's item approaches the end of
-- its 2-hour Bind-on-Pickup trade-eligibility window. Never removes the entry itself — that still
-- only happens via Trade.OnTradeClosed/manual done/reassignment, same as every other pending-trade
-- removal path; this is purely a heads-up so the lootmaster doesn't lose the item to the timer.
function Trade.CheckTradeTimeouts()
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
                entry.itemLink or "?", KART.Identity.ResolveDisplayName(entry.winnerKey), minutesLeft))
        end
    end
end

-- Lazily started on the first pending trade (not at addon load) so a raid that never uses Loot
-- Council never runs a background ticker at all. Safe to call repeatedly — no-ops if already running.
function Trade.StartTradeTimeoutTicker()
    if LC.tradeTimeoutTicker then return end
    LC.tradeTimeoutTicker = C_Timer.NewTicker(TRADE_TIMEOUT_CHECK_EVERY, Trade.CheckTradeTimeouts)
end

-- Removes the pending-trade entry for rollID, if any (reassignment, manual dismiss, or after the
-- item was successfully placed into an open trade window).
function Trade.RemovePendingTrade(rollID)
    for i = #LC.pendingTrades, 1, -1 do
        if LC.pendingTrades[i].rollID == rollID then
            table.remove(LC.pendingTrades, i)
        end
    end
    Trade.RefreshTradeReminder()
    -- Cancel the BoP-timeout ticker (see Trade.StartTradeTimeoutTicker) immediately once the last
    -- pending trade clears, instead of waiting up to TRADE_TIMEOUT_CHECK_EVERY (5 minutes) for the
    -- next periodic Trade.CheckTradeTimeouts to notice the list is empty.
    if #LC.pendingTrades == 0 and LC.tradeTimeoutTicker then
        LC.tradeTimeoutTicker:Cancel()
        LC.tradeTimeoutTicker = nil
    end
end

-- Fully forgets rollID's tracked state (vote/roll data, cached item link, assigned winner)
-- — called when a tab is dismissed or a session ends, so a later real roll that happens to
-- reuse the same small rollID integer never inherits stale data from a previous boss
-- (see the "wrong item posted on right-click assign" and "stale tabs after next boss" reports).
-- Note: pending trades are NOT cleared here; they are independent long-lived obligations that
-- should only be removed when the trade actually completes, is manually marked done, or is
-- reassigned to someone else.
function Trade.ClearRollState(rollID)
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
    if LC.rollLootedAt then LC.rollLootedAt[rollID] = nil end
end

function Trade.CreateTradeReminderFrame()
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(320, 40)
    f:SetPoint("CENTER", -220, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcTradeReminderPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText(KART.L.LC_TRADE_REMINDER_TITLE)

    f.rows = {}

    local pos = KART_Settings and KART_Settings.lcTradeReminderPos
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    LC.tradeReminderFrame = f
end

-- Rebuilds the reminder list from LC.pendingTrades; hides the frame entirely once it's empty.
function Trade.RefreshTradeReminder()
    if #LC.pendingTrades == 0 then
        if LC.tradeReminderFrame then LC.tradeReminderFrame:Hide() end
        return
    end

    if not LC.tradeReminderFrame then Trade.CreateTradeReminderFrame() end
    local f = LC.tradeReminderFrame

    for i, entry in ipairs(LC.pendingTrades) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetHeight(26)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -28, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            -- Fixed max width (rather than leaving it unbounded) so row.nameBtn below, anchored to
            -- this FontString's right edge, always keeps real, predictable clickable width — an
            -- unusually long item name would otherwise be able to push nameBtn's own width back
            -- toward zero, the same class of bug already fixed once for this button's anchoring.
            -- A name longer than this just visually clips instead of growing the layout further —
            -- SetWordWrap(false) already means it doesn't reflow, only how far it can push nameBtn.
            row.text:SetWidth(160)

            -- Separate, clickable element for just the winner's name — the item text above stays
            -- a plain FontString (no per-item action to take on it here).
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

            row.doneBtn = CreateFrame("Button", nil, row)
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
        row.nameBtn.text:SetText(KART.Identity.ResolveDisplayName(entry.winnerKey))
        local capturedRollID = entry.rollID
        local capturedWinnerKey = entry.winnerKey
        row.doneBtn:SetScript("OnClick", function() Trade.RemovePendingTrade(capturedRollID) end)
        row.nameBtn:SetScript("OnClick", function()
            local unit = capturedWinnerKey and KART.Identity.FindUnitForKey(capturedWinnerKey)
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, KART.Identity.ResolveDisplayName(capturedWinnerKey)))
                return
            end
            if not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, KART.Identity.ResolveDisplayName(capturedWinnerKey)))
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
    f:Show()
end

-- Removes rollID from LC.owedToMe, if present, and rebuilds the window.
function Trade.RemoveOwedItem(rollID)
    for i = #(LC.owedToMe or {}), 1, -1 do
        if LC.owedToMe[i].rollID == rollID then table.remove(LC.owedToMe, i) end
    end
    Trade.RefreshOwedReminder()
end

function Trade.CreateOwedReminderFrame()
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
function Trade.RefreshOwedReminder()
    LC.owedToMe = LC.owedToMe or {}
    if #LC.owedToMe == 0 then
        if LC.owedReminderFrame then LC.owedReminderFrame:Hide() end
        return
    end

    if not LC.owedReminderFrame then Trade.CreateOwedReminderFrame() end
    local f = LC.owedReminderFrame

    for i, entry in ipairs(LC.owedToMe) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetHeight(26)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -28, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            -- Fixed max width — see the identical comment in Trade.CreateTradeReminderFrame's own
            -- row.text for why (keeps row.nameBtn's clickable width real and predictable).
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

            row.doneBtn = CreateFrame("Button", nil, row)
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
        row.nameBtn.text:SetText(KART.Identity.ResolveDisplayName(entry.lootmasterKey))
        local capturedRollID = entry.rollID
        row.doneBtn:SetScript("OnClick", function() Trade.RemoveOwedItem(capturedRollID) end)
        row.nameBtn:SetScript("OnClick", function()
            local unit = KART.Identity.FindUnitForKey(entry.lootmasterKey)
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, KART.Identity.ResolveDisplayName(entry.lootmasterKey)))
                return
            end
            if not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, KART.Identity.ResolveDisplayName(entry.lootmasterKey)))
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

-- Finds itemLink in our own bags, returning (bag, slot) or nil if we're not carrying it (already
-- traded, mailed, or on a different character).
-- What's currently sitting in *our own* trade slots, rebuilt on every TRADE_ACCEPT_UPDATE — the
-- only reliable moment to read them, since the trade frame may already be tearing down by the
-- time UI_INFO_MESSAGE's trade-complete fires (see Trade.OnTradeInfoMessage). Keyed by item string
-- (bonus-ID aware, see KART.GetItemString), with a count rather than a plain boolean, so this composes
-- correctly with Trade.OnTradeClosed below even when a duplicate drop puts two copies of the exact
-- same item string in the trade window at once.
LC.tradeWindowItemStrings = LC.tradeWindowItemStrings or {}

function Trade.OnTradeAcceptUpdate()
    wipe(LC.tradeWindowItemStrings)
    for i = 1, 6 do -- MAX_TRADE_ITEMS - 1, fixed by the trade UI (slot 6 is "will not be traded")
        local link = GetTradePlayerItemLink(i) ---@diagnostic disable-line: undefined-global
        local itemString = KART.GetItemString(link)
        if itemString then
            LC.tradeWindowItemStrings[itemString] = (LC.tradeWindowItemStrings[itemString] or 0) + 1
        end
    end
end

-- Blizzard's own explicit trade-succeeded signal (LE_GAME_ERR_TRADE_COMPLETE) — a direct, first-
-- party confirmation rather than inferring success from bag contents. Only records that *a* trade
-- completed; Trade.OnTradeClosed cross-references LC.tradeWindowItemStrings to know *which* items.
function Trade.OnTradeInfoMessage(msgID)
    if msgID == LE_GAME_ERR_TRADE_COMPLETE then ---@diagnostic disable-line: undefined-global
        LC.tradeJustSucceeded = true
    end
end

local function FindItemInBags(itemLink)
    local wantString = KART.GetItemString(itemLink)
    if not wantString then return nil end
    for bag = 0, 4 do -- backpack (0) + 4 regular bag slots
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local bagLink = C_Container.GetContainerItemLink(bag, slot)
            if bagLink and KART.GetItemString(bagLink) == wantString then
                return bag, slot
            end
        end
    end
    return nil
end

-- "" normally, or " (i/N)" when N >= 2 currently-active rolls (LC.rollItems is only ever
-- populated for active ones — see Trade.ClearRollState) share the exact same item, bonus IDs
-- included. Ordered by ascending rollID so every client's ordinal for the same physical drop
-- agrees, since all clients see the same rollItems keys via the same broadcasts.
function Trade.GetDuplicateOrdinal(rollID)
    local myString = KART.GetItemString(LC.rollItems[rollID])
    if not myString then return "" end
    local matches = {}
    for otherRollID, link in pairs(LC.rollItems) do
        if KART.GetItemString(link) == myString then
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

-- Best-effort auto-trade: called on TRADE_SHOW. If the person we just opened a trade window with
-- has pending item(s) assigned to them, place the first one we can still find in our bags into an
-- empty trade slot. Only PLACES the item — the trade itself still has to be confirmed manually,
-- so a misclick or a slot mismatch is always caught by the normal trade-confirmation UI.
function Trade.OnTradeShow()
    if KART_Settings.lcModuleEnabled == false then return end

    local partnerName = UnitName("npc") -- the trade-partner unit token, a historical quirk of the trade API
    if not partnerName and TradeFrameRecipientNameText then ---@diagnostic disable-line: undefined-global
        partnerName = TradeFrameRecipientNameText:GetText() ---@diagnostic disable-line: undefined-global
        -- Blizzard renders a foreign-realm partner as "Name (*)" — the old sub(1, -4) kept the
        -- separating space, which made every downstream name match fail silently.
        if partnerName then
            partnerName = KART.TrimString(partnerName:gsub("%(%*%)", ""))
        end
    end
    if not partnerName then return end
    local partnerKey = (KART.Identity.ResolvePlayer(partnerName))
    -- Remembered for LC.OnTradeClosed, which fires after the trade frame (and UnitName("npc"))
    -- has already started tearing down, so the partner has to be captured here instead. Set
    -- unconditionally (not gated on #LC.pendingTrades, which is specifically this client's own
    -- "items I need to hand out" list) — a client can open this same trade with nothing of its
    -- own pending and still need to know who the partner was, e.g. the separate "items I'm owed"
    -- side the features plan adds, which checks this same field from the other direction.
    LC.currentTradePartnerKey = partnerKey

    for _, entry in ipairs(LC.pendingTrades) do
        -- Bail if the cursor is already carrying something (e.g. the player was mid-drag of an
        -- unrelated item) — picking up our item now would swap it into whatever slot that is.
        if entry.winnerKey == partnerKey and not GetCursorInfo() then ---@diagnostic disable-line: undefined-global
            local bag, slot = FindItemInBags(entry.itemLink)
            if bag then
                local freeSlot
                for i = 1, 6 do -- MAX_TRADE_ITEMS, fixed by the trade UI
                    if not GetTradePlayerItemLink(i) then ---@diagnostic disable-line: undefined-global
                        freeSlot = i
                        break
                    end
                end
                if freeSlot then
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(freeSlot) ---@diagnostic disable-line: undefined-global
                    -- Not removed here anymore — only once the trade actually completes (see
                    -- LC.OnTradeClosed), so a cancelled trade doesn't silently drop the reminder.
                end
            end
        end
    end
end

-- Runs when the trade window closes for any reason (completed, cancelled, partner walked away).
-- Two signals decide whether an entry actually completed: Blizzard's own trade-succeeded message
-- cross-referenced against LC.tradeWindowItemStrings (see Trade.OnTradeInfoMessage), and a bag
-- scan as a fallback for cases the first signal can't cover. Two passes over LC.pendingTrades
-- follow: Pass 1 confirms entries assigned to partnerKey, consuming the per-item-string count as
-- it goes; Pass 2 warns about entries assigned to someone else, but only for item strings whose
-- count Pass 1 didn't already exhaust — see the comments on each pass below.
function Trade.OnTradeClosed()
    local partnerKey = LC.currentTradePartnerKey
    local tradeSucceeded = LC.tradeJustSucceeded
    LC.currentTradePartnerKey = nil
    LC.tradeJustSucceeded = nil
    if not partnerKey then wipe(LC.tradeWindowItemStrings) return end

    -- Pass 1: entries actually assigned to partnerKey. Consumes LC.tradeWindowItemStrings' per-
    -- item-string COUNT (not just presence) as each is confirmed, so two pending entries that
    -- happen to share the exact same item string (a duplicate drop — see Trade.GetDuplicateOrdinal)
    -- can only be confirmed as many times as physical copies actually sat in the trade window.
    -- Without this, trading away one copy of a duplicate assigned twice to the same winner would
    -- silently mark BOTH entries complete, losing track of the second, still-owed item.
    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerKey == partnerKey then
            local itemString = KART.GetItemString(entry.itemLink)
            local remaining = itemString and LC.tradeWindowItemStrings[itemString]
            local confirmedByTrade = tradeSucceeded and remaining and remaining > 0
            local confirmedByBags = LC.IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink)
            if confirmedByTrade or confirmedByBags then
                if confirmedByTrade then LC.tradeWindowItemStrings[itemString] = remaining - 1 end
                Trade.RemovePendingTrade(entry.rollID)
            end
        end
    end

    -- Pass 2: entries assigned to someone else. Only warn if this item string still has an
    -- unconsumed count left after Pass 1 — otherwise a duplicate drop correctly assigned to two
    -- different winners (A and B) would falsely accuse "traded to the wrong person" every time the
    -- lootmaster correctly trades A's copy, just because B's still-pending entry shares the same
    -- item string. See Trade.GetDuplicateOrdinal for the same duplicate-drop scenario.
    -- warnedItemStrings caps this at one warning per item string per trade close: with 3+
    -- identical duplicate drops assigned to 3+ different other winners (rare), there's no way to
    -- tell which of them was the "real" intended recipient anyway, so warning once is more useful
    -- than spamming one message per pending entry for what's really a single physical mistake.
    local warnedItemStrings = {}
    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        if entry.winnerKey ~= partnerKey then
            local itemString = KART.GetItemString(entry.itemLink)
            local remaining = itemString and LC.tradeWindowItemStrings[itemString]
            if tradeSucceeded and remaining and remaining > 0 and not warnedItemStrings[itemString] then
                warnedItemStrings[itemString] = true
                print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADED_WRONG_PERSON,
                    entry.itemLink or "?", KART.Identity.ResolveDisplayName(entry.winnerKey), KART.Identity.ResolveDisplayName(partnerKey)))
            end
        end
    end

    -- Mirror check for the recipient side (Task 5's loop) — deliberately left as bag-scan-only.
    -- This task's stated scope (see the Root cause section above) is only the lootmaster-side
    -- signal; giving the recipient side the same UI_INFO_MESSAGE-based upgrade is a reasonable
    -- follow-up but wasn't asked for here — flag it rather than silently expanding scope.
    for i = #(LC.owedToMe or {}), 1, -1 do
        local entry = LC.owedToMe[i]
        if entry.lootmasterKey == partnerKey and LC.IsRealItemLink(entry.itemLink) and FindItemInBags(entry.itemLink) then
            Trade.RemoveOwedItem(entry.rollID)
        end
    end

    wipe(LC.tradeWindowItemStrings)
end

function Trade.ShowWinnerNotification(itemLink)
    if not LC.winnerFrame then
        local f = CreateFrame("Frame", "KART_LCWinnerFrame", UIParent, "BackdropTemplate")
        f:SetSize(290, 75)
        f:SetPoint("CENTER", 0, 160)
        KART.RegisterStrataFrame(f, true)
        KART.ApplyPopupArtwork(f)
        -- The winner popup keeps its celebratory green identity: a static green header line
        -- (deliberately not in the accent-line registry) under the green title.
        local winLine = f:CreateTexture(nil, "ARTWORK")
        winLine:SetHeight(1)
        winLine:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
        winLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
        winLine:SetColorTexture(0.1, 0.9, 0.1, 0.6)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -13)
        f.title:SetTextColor(0.1, 1, 0.1)

        f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.itemText:SetPoint("CENTER", 0, -10)
        f.itemText:SetWidth(270)

        LC.winnerFrame = f
    end

    local f = LC.winnerFrame
    f.title:SetText(KART.L.LC_YOU_WIN)
    f.itemText:SetText(itemLink or "")
    f:Show()
    if f.hideTimer then f.hideTimer:Cancel() end
    f.hideTimer = C_Timer.NewTimer(8, function() f:Hide() end)
end

-- Finds the button definition (with its color) whose label matches reason, for entries received
-- from other clients where only the label string traveled over the wire, not the color itself.
function Trade.ResolveColorForReason(reason)
    if not reason or reason == "" then return nil end
    for _, def in ipairs(LC.GetButtonConfig()) do
        if def.label == reason then return def end
    end
    return nil
end

function Trade.HandleResult(payload, senderKey)
    if not LC.IsSenderCouncil(senderKey) then return end
    -- payload = "rollID:winnerKey:itemID:reason"
    local rollID, winnerKey, itemID = payload:match("^(%d+):([^:]+):(%d*):")
    rollID = tonumber(rollID)
    if not rollID or not winnerKey then return end
    local reason = payload:match("^%d+:[^:]+:%d*:(.*)$") or ""

    -- Blizzard's rollID can get reused for a genuinely different item before every client has
    -- finished with the first one (see Trade.AnnounceResult) — if we're still tracking a real
    -- item for this rollID and it doesn't match what this result is actually for, this result
    -- belongs to a different, colliding roll. Ignore it entirely rather than closing/logging
    -- the wrong item's roll (this is the "vote window flashes open then immediately closes"
    -- bug during trash pulls with multiple simultaneous rolls).
    local localLink = LC.rollItems[rollID]
    if itemID ~= "" and LC.IsRealItemLink(localLink) then
        local localItemID = localLink:match("item:(%d+)")
        if localItemID and localItemID ~= itemID then return end
    end

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.Vote.RemoveVoteListItem(rollID)

    if winnerKey == "NONE" then return end

    local myKey = (KART.Identity.ResolvePlayer("player"))
    if winnerKey == myKey then
        Trade.ShowWinnerNotification(LC.rollItems[rollID])
        -- If I'm also the lootmaster, I already have the item — nothing to trade myself for.
        if not LC.IsMe(LC.GetLootmaster()) then
            LC.owedToMe = LC.owedToMe or {}
            table.insert(LC.owedToMe, {rollID = rollID, itemLink = LC.rollItems[rollID], lootmasterKey = LC.GetLootmaster()})
            Trade.RefreshOwedReminder()
        end
    end

    -- Every KART user logs the same entry locally, so everyone's loot history stays in sync
    -- without depending on the lootmaster being online later. The assigner already logged this
    -- locally (SendAddonMessage never echoes back to its own sender), so no duplicate here.
    local classFile
    local unit = KART.Identity.FindUnitForKey(winnerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    KART.LH.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(winnerKey), reason, classFile, Trade.ResolveColorForReason(reason), rollID)

    -- Same reasoning as DoAssignWinner: only the client physically holding the item (the
    -- designated lootmaster) needs a pending-trade reminder, regardless of who assigned it.
    if LC.IsMe(LC.GetLootmaster()) then
        Trade.AddPendingTrade(rollID, winnerKey)
    end
end
