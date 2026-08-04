local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

KART.LC.Trade = KART.LC.Trade or {}
local Trade = KART.LC.Trade
local LC = KART.LC

-- =====================================================================
--  Result announcement & winner notification
-- =====================================================================

-- reason (optional) is appended to the chat announcement, e.g. "(BIS)"; blank for no reason.
-- reason also travels in the LC_RESULT broadcast so every KART user's loot history stays in sync.
function Trade.AnnounceResult(rollID, winnerKey, reason, colorDef, deliberate)
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
        -- Carry the vote-button colour explicitly (r,g,b) rather than having the receiver re-derive
        -- it from the reason label — a peer that hasn't received LC_CONFIG yet would match the reason
        -- against its own locale defaults ("Other" vs "Sonstiges") and end up with no colour.
        local colorPacked = ""
        if colorDef then
            colorPacked = string.format("%d,%d,%d",
                math.floor((colorDef.r or 0) * 255), math.floor((colorDef.g or 0) * 255), math.floor((colorDef.b or 0) * 255))
        end
        -- The reassign flag (B35). It says "I could see a winner for this roll and replaced them on
        -- purpose", which is the one thing a receiver cannot work out for itself and the only thing
        -- that separates a confirmed reassignment from two council members clicking at once.
        --
        -- Placed BEFORE the reason, which is free text and has to stay the tail of the payload.
        LC.SendLC("LC_RESULT:" .. rollID .. ":" .. winnerKey .. ":" .. itemID .. ":" .. colorPacked
            .. ":" .. (deliberate and "1" or "0") .. ":" .. (reason or ""))

        if winnerKey ~= "NONE" then
            local msg = string.format(KART.L.LC_RESULT_ANNOUNCE, KASC.Identity.ResolveDisplayName(winnerKey), link)
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

local function DoAssignWinner(rollID, playerKey, reason, colorDef, deliberate)
    -- The roll may have been cleared (session end / tab close) between opening the reassign-confirm
    -- popup and accepting it — bail rather than logging a history entry with a nil item link.
    if not LC.rollItems[rollID] then return end
    local classFile
    local unit = KASC.Identity.FindUnitForKey(playerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    -- Recorded BEFORE the announce, which ends in a RefreshCouncilRows: the gold winner highlight
    -- reads LC.assignedWinners, so setting it afterwards left the assigner's own panel showing no
    -- winner at all until some unrelated event refreshed it — while every peer (Trade.HandleResult
    -- sets it first, then refreshes) showed the highlight immediately. Trade.AssignWinner has
    -- already read the previous winner for its confirm dialog by this point, so writing it here is
    -- safe. Row OnLeave re-reads this table live, which is why the highlight used to appear as soon
    -- as the mouse left the row — it looked intermittent rather than broken.
    LC.assignedWinners[rollID] = playerKey
    -- Our own rank, for the clash rule in Trade.HandleResult: a deliberate reassignment outranks a
    -- first award, so the person who confirmed a dialog naming both players is not overruled by
    -- somebody who never saw a winner at all.
    LC.assignedDeliberate[rollID] = deliberate or nil
    Trade.AnnounceResult(rollID, playerKey, reason, colorDef, deliberate)

    if LC.IsTestRoll(rollID) then
        -- Test rolls never round-trip through the network (see AnnounceResult), so if the
        -- tester assigned the win to themselves, trigger the "you win" popup locally instead —
        -- and skip writing a fake entry into the real, persistent loot history.
        local myKey = (KASC.Identity.ResolvePlayer("player"))
        if playerKey == myKey then
            Trade.ShowWinnerNotification(LC.rollItems[rollID])
        end
    else
        -- Same rule locally: our own earlier entry for this roll is superseded by this one.
        KART.LH.RemoveHistoryForRoll(rollID, LC.rollItems[rollID])
        KART.LH.LogHistory(LC.rollItems[rollID], KASC.Identity.ResolveDisplayName(playerKey), reason, classFile, colorDef, rollID, playerKey)
        -- B48: the assigner does not process its own broadcast (KASC drops the echo), so a council
        -- member who assigns an item to THEMSELVES never built their own "you are owed this" entry --
        -- while the lootmaster's queue was correct all along. The one person who cannot see what they
        -- are owed is the one who decided it.
        --
        -- Mirrors Trade.HandleResult's branch exactly, including the "I already hold it" case: being
        -- the loot owner means the item is in our own bags and there is nobody to be owed by.
        -- Unconditionally first: reassigning AWAY from ourselves has to take our own entry off, and
        -- reassigning to ourselves twice must not stack two. The branch below re-adds it if we are
        -- still the winner.
        local myKey = (KASC.Identity.ResolvePlayer("player"))
        if Trade.RemoveOwedEntry(rollID) then Trade.RefreshOwedReminderIfShown() end
        if playerKey == myKey and not LC.IsLootOwner() then
            local ownerKey = LC.GetLootOwnerKey()
            if ownerKey ~= "" then
                LC.owedToMe = LC.owedToMe or {}
                table.insert(LC.owedToMe, {
                    rollID = rollID, itemLink = LC.rollItems[rollID], lootmasterKey = ownerKey,
                    lootedAt = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or time(),
                })
                Trade.RefreshOwedReminder()
            end
        end

        -- Only the client that actually holds the item needs a trade reminder — an assigner who
        -- isn't the loot owner never physically has the item to trade.
        --
        -- Being the loot owner is not the same as holding it, and the two come apart in the ordinary
        -- course of a raid night: the lootmaster force-wins an item, ports out, and the raid leader
        -- stands in. The stand-in is the loot owner from that moment, but the item is in somebody
        -- else's bags. Recording an obligation for it is worse than recording none —
        -- Trade.OnTradeClosed reads "not in my bags" as "already traded" and clears the reminder the
        -- next time that winner is traded with for anything at all, so it tidies itself away, the
        -- raid believes the item was handed over, and the winner never receives it (backlog B60).
        if LC.IsLootOwner() then
            if LC.rollNotInOurBags[rollID] then
                print("|cffff0000KART:|r " .. KART.L.LC_TRADE_NOT_HELD)
            else
                Trade.AddPendingTrade(rollID, playerKey)
            end
        end
    end
    -- Take the decided item off our OWN vote list, the way Trade.HandleResult does for everybody
    -- else. Addon messages never echo back to their sender, so the one client that actually made the
    -- decision was the only one still looking at a live vote row for it — with buttons — long after
    -- the item was handed out. The lootmaster sees this worst, because being council he gets a vote
    -- row for every single drop, and closing the vote window stops the ticker that would eventually
    -- have pruned them (see Vote.PruneExpiredRolls). Reported as "die Lootliste hakt sich nicht ab".
    LC.Vote.RemoveVoteListItem(rollID)

    -- The tab deliberately stays open after an award: reassigning is a first-class feature, and
    -- Trade.AssignWinner's confirm dialog needs LC.assignedWinners, which ClearRollState would drop
    -- along with the tab. Tabs are cleared in bulk by "Close Session" (see the council panel).
end

-- Awards the item to playerKey (a resolved player identity, see KASC.Identity.ResolvePlayer) with
-- the given reason (may be "" for no reason) and logs it. colorDef is the vote-button definition
-- the reason was taken from (nil for "no reason"). If this rollID was already assigned, asks for
-- confirmation first to avoid accidental double entries.
function Trade.AssignWinner(rollID, playerKey, reason, colorDef)
    local prevWinner = LC.assignedWinners[rollID]
    if prevWinner then
        local dialog = StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] ---@diagnostic disable-line: undefined-global
        -- Set only the (language-dependent) template text; the two names fill its %s via the show
        -- args, and the assignment parameters ride along in `data` rather than a per-call OnAccept
        -- closure. A second reassign opened while this popup is still up gets its own `data`, so
        -- confirming either dialog runs its own assignment (the old closure-overwrite could run the
        -- wrong one).
        dialog.text = KART.L.LC_REASSIGN_CONFIRM_TEXT
        StaticPopup_Show("KART_LC_REASSIGN_CONFIRM", ---@diagnostic disable-line: undefined-global
            KASC.Identity.ResolveDisplayName(prevWinner),
            KASC.Identity.ResolveDisplayName(playerKey),
            { rollID = rollID, playerKey = playerKey, reason = reason, colorDef = colorDef })
    else
        DoAssignWinner(rollID, playerKey, reason, colorDef)
    end
end

-- Set once (not per Trade.AssignWinner call, which used to overwrite it): reads the per-show data
-- table so concurrent reassign popups can't run each other's assignment.
StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"].OnAccept = function(_, data) ---@diagnostic disable-line: undefined-global
    -- Reached only through the reassign dialog, so this assignment is deliberate by construction:
    -- a human read both names and confirmed (B35).
    if data then DoAssignWinner(data.rollID, data.playerKey, data.reason, data.colorDef, true) end
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
    local myKey = (KASC.Identity.ResolvePlayer("player"))
    Trade.RemovePendingTrade(rollID)
    if playerKey == myKey then return end

    -- Wall clock (time()), not GetTime(): this entry is persisted across sessions, see
    -- Trade.RestorePersistedTrades.
    local lootedAt = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or time()
    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerKey = playerKey, lootedAt = lootedAt})
    Trade.RefreshTradeReminder()
    Trade.StartTradeTimeoutTicker()
end

-- Blizzard's BoP trade-eligibility window: 4 hours, and it runs on WALL CLOCK — it keeps counting
-- down while the player is logged out. That's why every lootedAt stamp uses time() rather than
-- GetTime() (which resets each session and would only measure time spent online).
local TRADE_TIMEOUT_SECONDS = 4 * 60 * 60
local TRADE_TIMEOUT_WARN_AT = TRADE_TIMEOUT_SECONDS - 20 * 60 -- warn with 20 minutes left
local TRADE_TIMEOUT_CHECK_EVERY = 5 * 60

-- Warns once (per entry, via entry.timeoutWarned) as a pending trade's item approaches the end of
-- its Bind-on-Pickup trade-eligibility window (see TRADE_TIMEOUT_SECONDS). Never removes the entry itself — that still
-- only happens via Trade.OnTradeClosed/manual done/reassignment, same as every other pending-trade
-- removal path; this is purely a heads-up so the lootmaster doesn't lose the item to the timer.
function Trade.CheckTradeTimeouts()
    -- The winner's own obligations die on the same clock and are pruned below, so returning here
    -- when WE owe nothing left every "you are owed this" row alive for ever on the one client that
    -- has no pending trade of its own -- which is every winner who is not the lootmaster (B47).
    if #LC.pendingTrades == 0 and #(LC.owedToMe or {}) == 0 then
        if LC.tradeTimeoutTicker then LC.tradeTimeoutTicker:Cancel() LC.tradeTimeoutTicker = nil end
        return
    end
    local now = time() -- matches the wall-clock lootedAt stamps (see Trade.AddPendingTrade)
    local dropped = false
    -- Backwards: entries are removed in place, and Blizzard's window is wall clock, so several can
    -- come due in the same pass after a long fight.
    for i = #LC.pendingTrades, 1, -1 do
        local entry = LC.pendingTrades[i]
        local elapsed = now - (entry.lootedAt or now)
        -- B47: past the trade window the item cannot be handed over at all, and the entry stopped
        -- being a reminder and became a lie -- indistinguishable in the list from the ones that are
        -- still live, so the lootmaster works through it and cannot tell which rows are still worth
        -- chasing. Pruning happened only in Trade.RestorePersistedTrades, which runs at ADDON_LOADED:
        -- a raid that never reloads never prunes.
        if elapsed >= TRADE_TIMEOUT_SECONDS then
            table.remove(LC.pendingTrades, i)
            dropped = true
            -- Said once, at the moment it dies. A row vanishing from the reminder list on its own is
            -- exactly the kind of silence this addon has been paying for elsewhere.
            print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADE_EXPIRED,
                entry.itemLink or "?", KASC.Identity.ResolveDisplayName(entry.winnerKey)))
        elseif not entry.timeoutWarned and elapsed >= TRADE_TIMEOUT_WARN_AT then
            entry.timeoutWarned = true
            local minutesLeft = math.max(0, math.floor((TRADE_TIMEOUT_SECONDS - elapsed) / 60))
            print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADE_TIMEOUT_WARNING,
                entry.itemLink or "?", KASC.Identity.ResolveDisplayName(entry.winnerKey), minutesLeft))
        end
    end
    if dropped then Trade.RefreshTradeReminderIfShown() end

    -- The winner's own side of the same obligation, dying on the same clock.
    if LC.owedToMe then
        local owedDropped = false
        for i = #LC.owedToMe, 1, -1 do
            local e = LC.owedToMe[i]
            if (now - (e.lootedAt or now)) >= TRADE_TIMEOUT_SECONDS then
                table.remove(LC.owedToMe, i)
                owedDropped = true
            end
        end
        if owedDropped then Trade.RefreshOwedReminderIfShown() end
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
    Trade.RefreshTradeReminderIfShown()
    -- Cancel the BoP-timeout ticker (see Trade.StartTradeTimeoutTicker) immediately once the last
    -- pending trade clears, instead of waiting up to TRADE_TIMEOUT_CHECK_EVERY (5 minutes) for the
    -- next periodic Trade.CheckTradeTimeouts to notice the list is empty.
    if #LC.pendingTrades == 0 and LC.tradeTimeoutTicker then
        LC.tradeTimeoutTicker:Cancel()
        LC.tradeTimeoutTicker = nil
    end
end

-- Restores the outstanding trade obligations saved by the previous session and points LC's live
-- tables at the saved ones, so every later insert/remove persists automatically. Called once from
-- Core.lua's ADDON_LOADED, after the locale is available (the reminder rows render localized text).
--
-- These are real obligations with a hard Blizzard deadline (4 hours, wall clock), and a /reload used to drop them
-- silently: the lootmaster lost the reminder list, the auto-trade placement and the timeout warning
-- for items they were still holding, and every winner lost their "you're owed this" list.
--
-- Per-character, not account-wide (see the .toc): the items sit in one specific character's bags.
-- Entries past the trade window are dropped on load — the item can no longer be traded, so a
-- reminder for it would be noise.
function Trade.RestorePersistedTrades()
    KART_LCTrades = KART_LCTrades or {}
    local store = KART_LCTrades
    store.pending = type(store.pending) == "table" and store.pending or {}
    store.owed    = type(store.owed) == "table" and store.owed or {}
    store.looted  = type(store.looted) == "table" and store.looted or {}

    local now = time()
    local function pruneExpired(list)
        for i = #list, 1, -1 do
            local e = list[i]
            -- Drop malformed entries too (a schema change or a partially written SavedVariables
            -- file), so one bad row can't break every reminder render for the rest of the session.
            if type(e) ~= "table" or type(e.rollID) ~= "number"
               or type(e.lootedAt) ~= "number" or (now - e.lootedAt) >= TRADE_TIMEOUT_SECONDS then
                table.remove(list, i)
            end
        end
    end
    pruneExpired(store.pending)
    pruneExpired(store.owed)

    LC.pendingTrades = store.pending
    LC.owedToMe      = store.owed

    -- The BoP trade clock, kept for the same reason the two lists above are (B34). A roll that is
    -- still undecided when the lootmaster reloads leaves them holding a real item whose stamp was
    -- memory-only: when the council finally awards it, Trade.AddPendingTrade and the winner's
    -- owedToMe entry both fall back to time() at AWARD time, so a four-hour countdown that started
    -- when the boss died restarts from zero. KART then promises hours that do not exist and warns
    -- about a deadline that has already passed -- the item is simply lost, silently. Exactly the
    -- failure Trade.PruneExpiredLootStamps describes for a cleared stamp; a reload did the same
    -- thing to it.
    --
    -- Rebuilt rather than adopted wholesale: keys are rollIDs and a SavedVariables file can come
    -- back malformed or with them stringified, and the whole table is read by rollID lookup, so one
    -- bad key would go unnoticed until an award landed on it. Same defensiveness as pruneExpired.
    local looted = {}
    for rollID, stamp in pairs(store.looted) do
        local id = tonumber(rollID)
        if id and type(stamp) == "number" and (now - stamp) < TRADE_TIMEOUT_SECONDS then
            looted[id] = stamp
        end
    end
    -- Points the live table at the saved one, so every later stamp persists without a save step --
    -- the same arrangement as pendingTrades/owedToMe above. Assigned back into the store because the
    -- loop above built a new table.
    store.looted     = looted
    LC.rollLootedAt  = looted

    -- Which items already HAVE a winner, rebuilt from the loot history (B77).
    --
    -- Trade.AssignWinner reads LC.assignedWinners to tell a reassignment from a first award, and
    -- that table was memory-only. Nothing brought it back: the state request restores the session
    -- and the config, the roll catch-up restores the rolls, and the history catch-up runs on JOIN
    -- only. So a council member who reloaded mid-distribution and then decided an item again read
    -- prevWinner = nil, skipped the confirm dialog, and broadcast the reassign flag as 0 -- which
    -- every peer reads as a first award clashing with the one it holds, so the B35 tie-break kept
    -- the OLDER winner. The one client showing the new winner was the person who had just decided
    -- it, and nothing told them.
    --
    -- The history is the right source: it is persisted, every client logs every award, and it
    -- already carries the winner's identity key. `looted` above is the bound -- an entry only counts
    -- while the roll it belongs to is still inside the four-hour trade window, which is exactly the
    -- set of rolls that can still be re-decided. That also keeps last week's raid out of it without
    -- inventing a second timestamp.
    --
    -- assignedDeliberate is deliberately NOT restored. We cannot know from a history row whether
    -- somebody confirmed a dialog to produce it, and "not deliberate" is the answer that loses the
    -- tie-break rather than winning one it may not be entitled to.
    LC.assignedWinners = LC.assignedWinners or {}
    for _, e in ipairs(KART_LootHistory or {}) do
        local id = type(e) == "table" and type(e.rollID) == "number" and e.rollID or nil
        if id and looted[id] and type(e.winnerKey) == "string" and e.winnerKey ~= ""
           and type(e.time) == "number" and e.time >= looted[id] then
            LC.assignedWinners[id] = e.winnerKey
        end
    end

    if #LC.pendingTrades > 0 then
        Trade.RefreshTradeReminder()
        Trade.StartTradeTimeoutTicker()
    end
    if #LC.owedToMe > 0 then
        Trade.RefreshOwedReminder()
    end
end

-- Drops both halves of the "this roll has a winner" bookkeeping: the lootmaster's pending trade and
-- the winner's owed-item reminder. Used by every path that invalidates a previous award — a
-- reassignment (the old winner's obligations must go before the new one's are created) and a
-- revocation via "No Winner".
--
-- Single implementation on purpose: the local button and the peer-side LC_RESULT handler used to do
-- this separately, and the local one silently didn't, so whoever clicked "No Winner" kept a trade
-- reminder for an award nobody else still had.
-- Drops our own "you are owed this" entry for one roll. Split out because the assigner now builds
-- its own (B48) and a reassignment must not leave two behind.
function Trade.RemoveOwedEntry(rollID)
    if not LC.owedToMe then return false end
    local changed = false
    for i = #LC.owedToMe, 1, -1 do
        if LC.owedToMe[i].rollID == rollID then
            table.remove(LC.owedToMe, i)
            changed = true
        end
    end
    return changed
end

function Trade.ClearWinnerObligations(rollID)
    Trade.RemovePendingTrade(rollID) -- refreshes the trade reminder itself
    if Trade.RemoveOwedEntry(rollID) then Trade.RefreshOwedReminderIfShown() end
end

-- Drops LC.rollLootedAt stamps that are older than the Bind-on-Pickup trade window.
--
-- That table is the BoP trade CLOCK, not roll state, and it has to outlive the roll's own tracking:
-- for a non-council raider Vote.PruneExpiredRolls clears the roll the moment the vote window closes
-- (20s by default), while the award — which is what reads the stamp, via Trade.AddPendingTrade and
-- the winner's owedToMe entry — lands whenever the council is done. Clearing the stamp along with
-- the rest of the roll state made both fall back to time() at AWARD time, so the 4-hour countdown
-- started late and the reminder outlived the real deadline (badly so for a "/kart add" hours later).
-- Age is the natural bound instead: past the trade window the stamp can't matter to anything.
function Trade.PruneExpiredLootStamps()
    if not LC.rollLootedAt then return end
    local cutoff = time() - TRADE_TIMEOUT_SECONDS
    -- Assigning nil to keys that already exist is safe during a pairs() traversal; only ADDING new
    -- ones is undefined (see the collect-first loops in LC.RetryPendingResolutions).
    for rollID, stamp in pairs(LC.rollLootedAt) do
        if (stamp or 0) < cutoff then LC.rollLootedAt[rollID] = nil end
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
    LC.rollsFor[rollID]        = nil
    LC.councilVotes[rollID]    = nil
    LC.rollItems[rollID]       = nil
    LC.rollDeadlines[rollID]   = nil
    LC.rollDurations[rollID]   = nil
    LC.assignedWinners[rollID] = nil
    LC.assignedDeliberate[rollID] = nil
    LC.votedByMe[rollID]       = nil
    LC.votedFpByMe[rollID]     = nil
    LC.votedNoteByMe[rollID]   = nil
    LC.rollNotInOurBags[rollID]  = nil
    LC.rollAnnounced[rollID]     = nil
    LC.rollAnnouncedBy[rollID]   = nil
    LC.rollSeenHere[rollID]      = nil
    LC.relevanceHandled[rollID]  = nil
    LC.hiddenIrrelevant[rollID]  = nil
    LC.autoVotedByMe[rollID]     = nil
    -- Who was in the raid when this roll was announced (B118). Owner-side only, and it has to survive
    -- a reload with the roll it belongs to -- an owner that comes back without it would refuse every
    -- catch-up for an item still on the table.
    if LC.rollEligible then LC.rollEligible[rollID] = nil end
    -- "we have already asked the owner about this one", a timestamp and nothing else.
    if LC.rollReqSent then LC.rollReqSent[rollID] = nil end
    if LC.rollsAnswerAt then LC.rollsAnswerAt[rollID] = nil end
    -- LC.relevanceSnapshot is deliberately NOT cleared here, unlike the three above. On a reused
    -- rollID this runs from PurgeStaleRoll AFTER the relevance frame has already snapshotted the new
    -- item — that frame registers for START_LOOT_ROLL before Core.lua's dispatcher and therefore
    -- always sees the roll first — and dropping that fresh entry blinded the feature for exactly the
    -- case PurgeStaleRoll exists to handle: RollOnLoot has run by then, so the live
    -- GetLootRollItemInfo fallback is blank too and the item falls through to the armor path, which
    -- returns nil for weapons. The table's lifetime belongs to the self-sweep in
    -- LootCouncilRelevance.lua (the only clear path that knows whether a roll is still live) and to
    -- LC.ClearAllRolls' wipe.
    LC.councilTabsNew[rollID]  = nil
    -- LC.rollLootedAt[rollID] is deliberately NOT cleared here — see Trade.PruneExpiredLootStamps
    -- above. A rollID Blizzard reuses gets a fresh stamp from the roll-start handlers themselves.
    Trade.PruneExpiredLootStamps()
    if LC.equipRequestedRolls then LC.equipRequestedRolls[rollID] = nil end
    if LC.rollsPendingSince then LC.rollsPendingSince[rollID] = nil end
    -- Normally cleared by its own ContinueOnItemLoad callback; clear it here too so a callback that
    -- never resolves can't leave the latch set and block the async item load for a later roll that
    -- reuses this rollID (its iLvl/armor columns would stay blank).
    if LC.pendingItemLoads then LC.pendingItemLoads[rollID] = nil end
end

-- The "items still to trade" (lootmaster) and "items you still need to collect" (winner) windows
-- are structurally identical — one builder and one row renderer serve both.
local function CreateReminderFrame(frameName, titleText, posKey, defaultX)
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    f:SetSize(320, 40)
    f:SetPoint("CENTER", defaultX, 0)
    LC.RegisterWindow(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.UI:ApplyPopupArtwork(f)
    -- Clamped, like every Blizzard frame and like BuffChecker and the raidlead bar already were.
    -- Without it a window can be dragged past the edge of the game window -- reported from a live
    -- test in windowed mode on two monitors, where the desktop beyond the edge is real screen and
    -- there is nothing to stop the drag. KAUI.IsSavedPosOnScreen already refuses to RESTORE an
    -- off-screen position, so this is the other half: not getting there in the first place.
    f:SetClampedToScreen(true)
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

    -- These two windows shipped without one (B125, GitHub #24). Escape closed them -- they are in
    -- UISpecialFrames -- but nothing on screen said so, and the reporter drew the obvious conclusion
    -- instead: "no x, probably because the items are never handed over". Which was half right, and
    -- the other half is B122.
    --
    -- Closing HIDES and nothing more: the list is the obligation, not the window. Everything that
    -- removes an entry already refuses to reopen a closed window (Trade.RefreshTradeReminderIfShown),
    -- and `/kart trade` and `/kart owed` bring it back rebuilt.
    f.closeBtn = KART.UI:CreateHeaderIconButton(f, "×", function() f:Hide() end)
    f.closeBtn:SetPoint("TOPRIGHT", -4, -4)

    f.rows = {}

    local pos = KART_Settings and KART_Settings[posKey]
    if pos and type(pos) == "table" and KAUI.IsSavedPosOnScreen(pos.x, pos.y) then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    return f
end

-- Rebuilds f's rows from entries (LC.pendingTrades or LC.owedToMe). getTargetKey(entry) resolves
-- which player this row's trade partner is; removeByRollID(rollID) is called when a row's
-- done-button is clicked (Trade.RemovePendingTrade or Trade.RemoveOwedItem, per window).
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
            -- Fixed max width (rather than leaving it unbounded) so row.nameBtn below, anchored to
            -- this FontString's right edge, always keeps real, predictable clickable width — an
            -- unusually long item name would otherwise be able to push nameBtn's own width back
            -- toward zero, the same class of bug already fixed once for this button's anchoring.
            -- A name longer than this just visually clips instead of growing the layout further —
            -- SetWordWrap(false) already means it doesn't reflow, only how far it can push nameBtn.
            row.text:SetWidth(160)

            -- Separate, clickable element for just the target's name — the item text above stays
            -- a plain FontString (no per-item action to take on it here).
            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetPoint("LEFT", row.text, "RIGHT", 4, 0)
            row.nameBtn:SetPoint("RIGHT")
            row.nameBtn:SetHeight(16)
            row.nameBtn.text = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameBtn.text:SetPoint("LEFT")
            row.nameBtn.text:SetPoint("RIGHT")
            row.nameBtn.text:SetJustifyH("LEFT")
            row.nameBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(KART.UI:AccentColor()) end)
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
        row.nameBtn.text:SetText(KASC.Identity.ResolveDisplayName(targetKey))
        local capturedRollID = entry.rollID
        row.doneBtn:SetScript("OnClick", function() removeByRollID(capturedRollID) end)
        row.nameBtn:SetScript("OnClick", function()
            local unit = targetKey and KASC.Identity.FindUnitForKey(targetKey)
            if not unit then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_TARGET_NOT_FOUND, KASC.Identity.ResolveDisplayName(targetKey)))
                return
            end
            -- CheckInteractDistance is combat-restricted (returns nil in combat since 9.1), which
            -- would falsely report "out of range" even when standing on the winner — only gate on it
            -- out of combat; in combat just attempt the trade and let InitiateTrade fail if too far.
            if not InCombatLockdown() and not CheckInteractDistance(unit, 2) then
                print("|cffff0000KART:|r " .. string.format(KART.L.LC_TRADE_OUT_OF_RANGE, KASC.Identity.ResolveDisplayName(targetKey)))
                return
            end
            -- InitiateTrade takes the unit token directly and needs no prior target; TargetUnit is
            -- protected and would throw ADDON_ACTION_FORBIDDEN from this insecure OnClick.
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

-- What every REMOVAL path calls instead of the plain refresh above. Both reminder frames' "x" only
-- hides them, and RefreshReminderRows ends in an unconditional Show(), so dropping a single entry
-- re-opened a window the user had deliberately closed — completing a trade popped the lootmaster's
-- list straight back up, with the remaining rows. Same rule the vote list already follows (see
-- Vote.RefreshVoteListRowsIfShown): removing an item must never open a window. ADDING one still may,
-- which is why Trade.AddPendingTrade, the owed insert in Trade.HandleResult and the login restore all
-- keep calling the plain refresh. An emptied list still hides the frame — that runs inside the
-- refresh, which this only skips when the frame is already hidden anyway.
function Trade.RefreshTradeReminderIfShown()
    if LC.tradeReminderFrame and LC.tradeReminderFrame:IsShown() then Trade.RefreshTradeReminder() end
end

-- Removes rollID from LC.owedToMe, if present, and rebuilds the window.
function Trade.RemoveOwedItem(rollID)
    for i = #(LC.owedToMe or {}), 1, -1 do
        if LC.owedToMe[i].rollID == rollID then table.remove(LC.owedToMe, i) end
    end
    Trade.RefreshOwedReminderIfShown()
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

-- Owed-side counterpart to Trade.RefreshTradeReminderIfShown — see the reasoning there.
function Trade.RefreshOwedReminderIfShown()
    if LC.owedReminderFrame and LC.owedReminderFrame:IsShown() then Trade.RefreshOwedReminder() end
end

-- Finds itemLink in our own bags, returning (bag, slot) or nil if we're not carrying it (already
-- traded, mailed, or on a different character).
-- What's currently sitting in *our own* trade slots, rebuilt on every TRADE_ACCEPT_UPDATE — the
-- only reliable moment to read them, since the trade frame may already be tearing down by the
-- time UI_INFO_MESSAGE's trade-complete fires (see Trade.OnTradeInfoMessage). Keyed by item string
-- (bonus-ID aware, see KAUtil.GetItemString), with a count rather than a plain boolean, so this composes
-- correctly with Trade.OnTradeClosed below even when a duplicate drop puts two copies of the exact
-- same item string in the trade window at once.
LC.tradeWindowItemStrings = LC.tradeWindowItemStrings or {}

-- The same, read from the PARTNER's half of the window. The person handing an item over confirms it
-- from their own slots; the person receiving it has to read the other side, and had no equivalent at
-- all -- so their "you are owed this" reminder stood after the item had arrived, cleared only by
-- clicking its own tick, by a reassignment, or by the four-hour prune. Reported from a live test.
LC.tradeTargetItemStrings = LC.tradeTargetItemStrings or {}

function Trade.OnTradeAcceptUpdate()
    wipe(LC.tradeWindowItemStrings)
    wipe(LC.tradeTargetItemStrings)
    for i = 1, 6 do -- MAX_TRADE_ITEMS is 7; slots 1-6 are the tradeable slots (slot 7 is the "will not be traded" slot)
        local link = GetTradePlayerItemLink(i) ---@diagnostic disable-line: undefined-global
        local itemString = KAUtil.GetItemString(link)
        if itemString then
            LC.tradeWindowItemStrings[itemString] = (LC.tradeWindowItemStrings[itemString] or 0) + 1
        end
        local theirs = GetTradeTargetItemLink(i)
        local theirString = KAUtil.GetItemString(theirs)
        if theirString then
            LC.tradeTargetItemStrings[theirString] = (LC.tradeTargetItemStrings[theirString] or 0) + 1
        end
    end
end

-- Blizzard's own explicit trade-succeeded signal (LE_GAME_ERR_TRADE_COMPLETE) — a direct, first-
-- party confirmation rather than inferring success from bag contents. Only records that *a* trade
-- completed; Trade.OnTradeClosed cross-references LC.tradeWindowItemStrings to know *which* items.
function Trade.OnTradeInfoMessage(msgID)
    if msgID == LE_GAME_ERR_TRADE_COMPLETE then ---@diagnostic disable-line: undefined-global
        LC.tradeJustSucceeded = true
        -- ...and do the receiving side here as well as in Trade.OnTradeClosed, because the ORDER of
        -- these two is not guaranteed and this side has no second signal to fall back on. The
        -- giving side does -- it rescans its own bags -- so a trade-complete that arrives after the
        -- window has already closed still ticks the giver's list off and would silently leave the
        -- winner's standing. Reported from a live test after the first attempt shipped: the
        -- lootmaster's row cleared, the winner's did not. Whichever of the two fires last does the
        -- work; both are idempotent, since an entry can only be removed once.
        Trade.ConfirmOwedFromPartner(LC.currentTradePartnerKey or LC.lastTradePartnerKey)
    end
end

-- skip (optional): a set keyed "bag:slot" of slots to ignore, so a caller placing several copies of
-- the same item in one pass doesn't keep finding the same (now-locked) bag slot.
local function FindItemInBags(itemLink, skip)
    local wantString = KAUtil.GetItemString(itemLink)
    if not wantString then return nil end
    for bag = 0, 4 do -- backpack (0) + 4 regular bag slots
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local bagLink = C_Container.GetContainerItemLink(bag, slot)
            if bagLink and KAUtil.GetItemString(bagLink) == wantString
               and not (skip and skip[bag .. ":" .. slot]) then
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
    local myString = KAUtil.GetItemString(LC.rollItems[rollID])
    if not myString then return "" end
    local matches = {}
    for otherRollID, link in pairs(LC.rollItems) do
        if KAUtil.GetItemString(link) == myString then
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

    -- "npc" is the trade-partner unit token during TRADE_SHOW. Resolve it straight to a GUID key
    -- (cross-realm-safe) rather than via UnitName("npc"), which returned nil for foreign-realm
    -- partners and needed a TradeFrameRecipientNameText "(*)" text-parse fallback. UnitExists/UnitGUID
    -- stay valid exactly where UnitName didn't, so that whole fallback is unnecessary.
    if not UnitExists("npc") then return end
    local partnerKey = (KASC.Identity.ResolvePlayer("npc"))
    -- Remembered for LC.OnTradeClosed, which fires after the trade frame (and UnitName("npc"))
    -- has already started tearing down, so the partner has to be captured here instead. Set
    -- unconditionally (not gated on #LC.pendingTrades, which is specifically this client's own
    -- "items I need to hand out" list) — a client can open this same trade with nothing of its
    -- own pending and still need to know who the partner was, e.g. the separate "items I'm owed"
    -- side the features plan adds, which checks this same field from the other direction.
    LC.currentTradePartnerKey = partnerKey

    -- Two copies of the same item assigned to this partner would otherwise both resolve to the same
    -- first bag slot (the first gets locked into the trade, the second no-ops) — track placed slots
    -- so each copy takes a distinct one.
    local usedSlots = {}
    -- The trade slots this function has already dropped something into. Asking the client instead --
    -- which is what this did -- is a race it loses on any latency worth the name: the slot only fills
    -- once the server answers, so the second item owed to the same person found slot 1 still empty
    -- and took it, swapping the first one back out. The lootmaster's list then showed both as dealt
    -- with while the raider had been handed one (B122). Seen failing and succeeding in the same
    -- evening, which is what a race looks like from the outside.
    local placedSlots = {}
    for _, entry in ipairs(LC.pendingTrades) do
        -- Bail if the cursor is already carrying something (e.g. the player was mid-drag of an
        -- unrelated item) — picking up our item now would swap it into whatever slot that is.
        if entry.winnerKey == partnerKey and not GetCursorInfo() then ---@diagnostic disable-line: undefined-global
            local bag, slot = FindItemInBags(entry.itemLink, usedSlots)
            if bag then
                local freeSlot
                for i = 1, 6 do -- MAX_TRADE_ITEMS is 7; slots 1-6 are the tradeable slots (slot 7 is the "will not be traded" slot)
                    -- Both questions, and the second one is the fix: what the client already shows,
                    -- and what we have put there ourselves since it last answered.
                    if not GetTradePlayerItemLink(i) and not placedSlots[i] then ---@diagnostic disable-line: undefined-global
                        freeSlot = i
                        break
                    end
                end
                if freeSlot then
                    C_Container.PickupContainerItem(bag, slot)
                    ClickTradeButton(freeSlot) ---@diagnostic disable-line: undefined-global
                    placedSlots[freeSlot] = true
                    usedSlots[bag .. ":" .. slot] = true
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
-- Clears our own "you are owed this" rows for items that just crossed the trade window FROM
-- partnerKey. Consumes the per-item-string count for the same reason the giving side does: two
-- entries owed by the same person that share an item string can only be confirmed as many times as
-- copies actually arrived.
--
-- Deliberately no bag-contents fallback, which is where this is NOT symmetrical with the giving
-- side: "it is in my bags" is also true of a copy this player already owned, and ticking off a
-- reminder for an item nobody handed over is worse than leaving one standing. That is exactly why
-- the ordering has to be handled instead -- this side has only the one signal.
function Trade.ConfirmOwedFromPartner(partnerKey)
    if not partnerKey then return end
    for i = #(LC.owedToMe or {}), 1, -1 do
        local entry = LC.owedToMe[i]
        if entry.lootmasterKey == partnerKey then
            local itemString = KAUtil.GetItemString(entry.itemLink)
            local remaining = itemString and LC.tradeTargetItemStrings[itemString]
            if remaining and remaining > 0 then
                LC.tradeTargetItemStrings[itemString] = remaining - 1
                table.remove(LC.owedToMe, i)
                Trade.RefreshOwedReminderIfShown()
            end
        end
    end
end

function Trade.OnTradeClosed()
    local partnerKey = LC.currentTradePartnerKey
    -- Kept past the close: the trade-complete message can arrive after the window has gone, and the
    -- receiving side still needs to know who it was.
    LC.lastTradePartnerKey = partnerKey or LC.lastTradePartnerKey
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
            local itemString = KAUtil.GetItemString(entry.itemLink)
            local remaining = itemString and LC.tradeWindowItemStrings[itemString]
            local confirmedByTrade = tradeSucceeded and remaining and remaining > 0
            local confirmedByBags = LC.IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink)
            if confirmedByTrade or confirmedByBags then
                if confirmedByTrade then LC.tradeWindowItemStrings[itemString] = remaining - 1 end
                Trade.RemovePendingTrade(entry.rollID)
            end
        end
    end

    -- The receiving side of the same trade, if the trade-complete signal has already arrived. If it
    -- has not, Trade.OnTradeInfoMessage runs it when it does -- see there for why the order cannot
    -- be relied on.
    if tradeSucceeded then Trade.ConfirmOwedFromPartner(partnerKey) end

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
    for _, entry in ipairs(LC.pendingTrades) do -- read-only pass (only warns), no removal
        if entry.winnerKey ~= partnerKey then
            local itemString = KAUtil.GetItemString(entry.itemLink)
            local remaining = itemString and LC.tradeWindowItemStrings[itemString]
            if tradeSucceeded and remaining and remaining > 0 and not warnedItemStrings[itemString] then
                warnedItemStrings[itemString] = true
                print(string.format("|cffff0000KART:|r " .. KART.L.LC_TRADED_WRONG_PERSON,
                    entry.itemLink or "?", KASC.Identity.ResolveDisplayName(entry.winnerKey), KASC.Identity.ResolveDisplayName(partnerKey)))
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
        LC.RegisterWindow(f, true)
        KART.UI:ApplyPopupArtwork(f)
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
    if not LC.IsSenderCouncil(senderKey) then
        -- Refusing it is right; leaving it at that was not (B66). This is the one moment we know an
        -- award exists that we do not have, so it is where the loot-history catch-up is asked for.
        if KART.LH and KART.LH.NoteUnauthorisedAward then KART.LH.NoteUnauthorisedAward() end
        return
    end
    -- payload = "rollID:winnerKey:itemID:colorPacked:reason"
    -- Reviewed 2026-07-24, NOT a bug: this pattern requires the current 5-field wire format (4
    -- colons). A pre-itemID/pre-colorPacked build sends fewer fields and its result is dropped here
    -- before reaching the colour fallback below. That's intentional — running the current KART
    -- version is mandatory across a raid (an outdated sender already gets an "update available"
    -- warning), so cross-version wire compat is deliberately not supported. Do not re-flag.
    local rollID, winnerKey, itemID, colorPacked, deliberate =
        payload:match("^(%d+):([^:]+):(%d*):([^:]*):([01]):")
    rollID = tonumber(rollID)
    if not rollID or not winnerKey then return end
    local reason = payload:match("^%d+:[^:]+:%d*:[^:]*:[01]:(.*)$") or ""
    deliberate = deliberate == "1"

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

    -- A council peer who joined late never tracked this roll, so LC.rollItems[rollID] is nil and the
    -- winner notification / history / trade reminder would all show "???". Rebuild a link from the
    -- itemID carried in the payload (full link if the item is cached, bare item string otherwise).
    -- Rebuild when we have no link OR only a non-real placeholder ("???" from a late-joiner who saw
    -- LC_START but never resolved the link) — a truthy "???" would otherwise skip this and land in
    -- the winner popup / history.
    local itemLink = LC.rollItems[rollID]
    if (not itemLink or not LC.IsRealItemLink(itemLink)) and itemID ~= "" then
        itemLink = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
        LC.rollItems[rollID] = itemLink
    end

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.Vote.RemoveVoteListItem(rollID)

    -- Any previous award under this rollID is now void — drop the old winner's owed reminder and the
    -- lootmaster's pending trade before re-evaluating. A real winner below re-creates both; a
    -- reassignment back to the same player therefore can't stack duplicates. Must run BEFORE the
    -- NONE branch: revoking a winner has to clear their obligations too.
    -- B35: two council members award the same item at the same moment. Assigning is open to the whole
    -- council and the double-assign guard reads LC.assignedWinners LOCALLY, so with no message having
    -- arrived yet both see nil, both broadcast, and each overwrites the other's record on receipt --
    -- the two of them end up permanently swapped, and every other client keeps whichever message
    -- happened to reach it last, which is not the same message on every client.
    --
    -- Resolved by a rule every client can apply to (what I hold, what just arrived) and reach the
    -- same answer from, in either order:
    --   * a DELIBERATE reassignment outranks a first award -- somebody read a dialog naming both
    --     players and confirmed, and must not be overruled by a client that never saw a winner;
    --   * otherwise the smaller winner key wins. Arbitrary on purpose: neither council member is more
    --     right than the other, and what the raid needs is one answer, not the better one.
    --
    -- Order-independence is the whole point. min() and "deliberate beats first" are both commutative,
    -- so a client that receives A then B lands where one that receives B then A does.
    local held = LC.assignedWinners[rollID]
    if held and held ~= winnerKey and winnerKey ~= "NONE" then
        local heldDeliberate = LC.assignedDeliberate[rollID] and true or false
        local incomingWins
        if deliberate ~= heldDeliberate then
            incomingWins = deliberate
        else
            incomingWins = winnerKey < held
        end
        -- Said out loud on the screens that can act on it: the council decided it and the loot owner
        -- physically hands the item over. Silence here is how the raid ends up trading to somebody
        -- the panel in front of them never showed.
        if not deliberate and not heldDeliberate and (LC.IsCouncil() or LC.IsLootOwner()) then
            local kept = incomingWins and winnerKey or held
            print("|cffff0000KART:|r " .. string.format(KART.L.LC_AWARD_CLASH,
                LC.rollItems[rollID] or "?",
                KASC.Identity.ResolveDisplayName(held),
                KASC.Identity.ResolveDisplayName(winnerKey),
                KASC.Identity.ResolveDisplayName(kept)))
        end
        -- Losing the tie changes nothing at all: our obligations still belong to the winner we hold.
        if not incomingWins then return end
    end

    Trade.ClearWinnerObligations(rollID)

    if winnerKey == "NONE" then
        -- The item ended up with nobody, so any history entry naming a winner for it is now wrong.
        -- Every client logs the same award locally, so every client has to drop it locally too —
        -- the revoker does this itself (it does not process its own message, see the panel's No-Winner
        -- button and LC.StartManualRoll's re-decision path).
        KART.LH.RemoveHistoryForRoll(rollID, LC.rollItems[rollID])
        -- "No winner" mirrors the assigner's own local CloseCouncilTab (see the panel button): the
        -- assigner already closed and cleared its tab, and this broadcast is the peers' only signal
        -- (KASC drops our own message when it comes back). Without this, peers keep a ghost council tab
        -- with stale votes and a stale gold winner highlight from any prior assignment on this roll.
        KART.LC.Council.CloseCouncilTab(rollID)
        return
    end

    -- Council peers must see the same assigned winner the assigner recorded locally — the gold
    -- winner highlight (see RefreshCouncilRows) and a correct prevWinner on any later reassignment
    -- both read from LC.assignedWinners. The result broadcast is a peer's only signal (the assigner
    -- already set this in AssignWinner and does not process its own message), so mirror it here.
    LC.assignedWinners[rollID] = winnerKey
    LC.assignedDeliberate[rollID] = deliberate or nil
    LC.RefreshCouncilIfShown(rollID)

    local myKey = (KASC.Identity.ResolvePlayer("player"))

    if winnerKey == myKey then
        Trade.ShowWinnerNotification(LC.rollItems[rollID])
        -- If I'm the loot owner myself, I already have the item — nothing to trade myself for.
        -- GetLootOwnerKey resolves the raid leader when no lootmaster is configured (they hold the
        -- items in that case, see LC.IsLootOwner); "" only when neither can be resolved at all, and
        -- an owed entry with an empty key resolves to no unit, so its trade-partner name button
        -- would always fail.
        local lootmasterKey = LC.GetLootOwnerKey()
        if lootmasterKey ~= "" and not LC.IsMe(lootmasterKey) then
            LC.owedToMe = LC.owedToMe or {}
            -- lootedAt drives the same expiry the lootmaster's pending trade uses, and lets
            -- Trade.RestorePersistedTrades drop entries whose trade window closed while we were gone.
            -- Every client stamps LC.rollLootedAt when the roll starts (see LC.OnStartLootRoll /
            -- LC.HandleStart, and LC.StartManualRoll / LC.HandleManualStart for /kart add) and the
            -- stamp deliberately outlives the roll's own tracking (see
            -- Trade.PruneExpiredLootStamps), so this is the real loot time, not the award time; the
            -- time() fallback only covers a roll this client never saw start at all.
            table.insert(LC.owedToMe, {
                rollID = rollID, itemLink = LC.rollItems[rollID], lootmasterKey = lootmasterKey,
                lootedAt = (LC.rollLootedAt and LC.rollLootedAt[rollID]) or time(),
            })
            Trade.RefreshOwedReminder()
        end
    end

    -- Every KART user logs the same entry locally, so everyone's loot history stays in sync
    -- without depending on the lootmaster being online later. The assigner already logged this
    -- locally (KASC drops our own message when it comes back (see Dispatch)), so no duplicate here.
    local classFile
    local unit = KASC.Identity.FindUnitForKey(winnerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    -- Use the colour carried in the payload; only fall back to re-deriving it from the reason label
    -- if the sender was on an older build that didn't send one.
    local color
    if colorPacked and colorPacked ~= "" then
        local cr, cg, cb = colorPacked:match("^(%d+),(%d+),(%d+)$")
        if cr then color = {r = tonumber(cr) / 255, g = tonumber(cg) / 255, b = tonumber(cb) / 255} end
    end
    color = color or Trade.ResolveColorForReason(reason)
    -- Any earlier entry for this roll is superseded, whether by a confirmed reassignment or by the
    -- clash rule above (B35). Without this the raid converged on ONE winner and still disagreed about
    -- its own record of the evening: a client that saw both awards logged both, a client that saw
    -- only one logged one, and the assigners each logged their own pick locally. Found by the soak
    -- once it learned to make two council members decide at the same moment.
    -- itemLink, not LC.rollItems[rollID]: this is the item being logged one line down, and it was
    -- rebuilt from the itemID on the wire -- so it is right even on a client whose own tracking of
    -- that rollID is stale or was never there.
    KART.LH.RemoveHistoryForRoll(rollID, itemLink)
    KART.LH.LogHistory(itemLink, KASC.Identity.ResolveDisplayName(winnerKey), reason, classFile, color, rollID, winnerKey)

    -- Same reasoning as DoAssignWinner, including the "loot owner is not the same as holder" case.
    if LC.IsLootOwner() then
        if LC.rollNotInOurBags[rollID] then
            print("|cffff0000KART:|r " .. KART.L.LC_TRADE_NOT_HELD)
        else
            Trade.AddPendingTrade(rollID, winnerKey)
        end
    end

    -- The tab deliberately stays open here, exactly like on the assigner's own client (see
    -- DoAssignWinner): reassigning is a first-class feature and the council has to keep seeing the
    -- votes for a decided item. Closing it only on the peers — which is what an earlier version did —
    -- left the assigner with a tab nobody else had, and stripped the item's votes and winner
    -- highlight from every OTHER council member, the lootmaster included. Tabs are cleared in bulk
    -- by "Close Session" (see the council panel). Do not re-add a close here.
end

KASC:RegisterMessage("LC_RESULT", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) Trade.HandleResult(payload, ctx:Key()) end)
