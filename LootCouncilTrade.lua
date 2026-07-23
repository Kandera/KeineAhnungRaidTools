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
        LC.SendLC("LC_RESULT:" .. rollID .. ":" .. winnerKey .. ":" .. (reason or ""))

        if winnerKey ~= "NONE" then
            local link = LC.rollItems[rollID] or ""
            local msg  = string.format(KART.L.LC_RESULT_ANNOUNCE, KART.Identity.ResolveDisplayName(winnerKey), link)
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

    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerKey = playerKey})
    Trade.RefreshTradeReminder()
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
end

function Trade.CreateTradeReminderFrame()
    local f = CreateFrame("Frame", "KART_LCTradeReminder", UIParent, "BackdropTemplate")
    f:SetSize(260, 40)
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
            row:SetHeight(20)
            row:SetPoint("LEFT", 10, 0)
            row:SetPoint("RIGHT", -28, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetPoint("RIGHT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row.doneBtn = CreateFrame("Button", nil, f)
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
        row:SetPoint("TOPLEFT", 10, -8 - 20 - (i - 1) * 20)
        row:SetPoint("RIGHT", -28, 0)
        row.text:SetText(string.format(KART.L.LC_TRADE_REMINDER_ROW, entry.itemLink or "???", KART.Identity.ResolveDisplayName(entry.winnerKey)))
        local capturedRollID = entry.rollID
        row.doneBtn:SetScript("OnClick", function() Trade.RemovePendingTrade(capturedRollID) end)
        row:Show()
    end
    for i = #LC.pendingTrades + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(8 + 20 + #LC.pendingTrades * 20 + 8)
    f:Show()
end

-- Finds itemLink in our own bags, returning (bag, slot) or nil if we're not carrying it (already
-- traded, mailed, or on a different character).
-- Full item string (itemID + every bonus ID: enchant, gems, suffix, upgrade level, etc.), not just
-- the bare itemID — two drops can share an itemID while being different variants (e.g. one has a
-- tertiary stat/bonus ID the other doesn't), and comparing only itemID would treat them as
-- interchangeable, letting auto-trade grab whichever copy happens to sort first in bags instead of
-- the exact one that was assigned. Same pattern LootHistory.lua's GetItemStringFromLink already uses.
local function GetItemString(link)
    return LC.IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
end

local function FindItemInBags(itemLink)
    local wantString = GetItemString(itemLink)
    if not wantString then return nil end
    for bag = 0, 4 do -- backpack (0) + 4 regular bag slots
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local bagLink = C_Container.GetContainerItemLink(bag, slot)
            if bagLink and GetItemString(bagLink) == wantString then
                return bag, slot
            end
        end
    end
    return nil
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
        -- Blizzard's trade frame displays a foreign-realm partner's name with a trailing "(*)"
        -- marker instead of "-Realm" — strip it so the short-name match below isn't corrupted.
        if partnerName and partnerName:find("(*)", 1, true) then
            partnerName = partnerName:sub(1, -4)
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
-- The only reliable way to tell "did it actually go through" is to check whether the item is
-- still in our bags: if it's gone, the trade succeeded and the reminder can be cleared; if it's
-- still there, nothing happened and the entry stays pending so the next trade attempt retries it.
function Trade.OnTradeClosed()
    local partnerKey = LC.currentTradePartnerKey
    LC.currentTradePartnerKey = nil
    if not partnerKey then return end

    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        -- Only treat "not found in bags" as "trade completed" for real, resolved item links.
        -- A "???" placeholder entry (async item-link resolution still pending) would always
        -- report "not found" since the placeholder is not a valid item ID to search bags for,
        -- so we'd falsely mark it completed. Leave such entries alone; the user's manual
        -- "done" checkmark button remains available as the fallback for that edge case.
        if entry.winnerKey == partnerKey and LC.IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink) then
            Trade.RemovePendingTrade(entry.rollID)
        end
    end
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
    -- payload = "rollID:winnerKey:reason"
    local rollID, winnerKey = payload:match("^(%d+):([^:]+)")
    rollID = tonumber(rollID)
    if not rollID or not winnerKey then return end
    local reason = payload:match("^%d+:[^:]+:(.*)$") or ""

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.Vote.RemoveVoteListItem(rollID)

    if winnerKey == "NONE" then return end

    local myKey = (KART.Identity.ResolvePlayer("player"))
    if winnerKey == myKey then
        Trade.ShowWinnerNotification(LC.rollItems[rollID])
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
