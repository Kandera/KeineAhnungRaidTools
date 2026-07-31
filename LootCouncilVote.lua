local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")
local function lcEnabled() return KART_Settings.lcModuleEnabled ~= false end

KART.LC.Vote = KART.LC.Vote or {}
local Vote = KART.LC.Vote
local LC = KART.LC

-- The bare itemID this client currently tracks for a roll, or "" when it has no real link yet.
-- Carried with a vote so a network-delayed one for the PREVIOUS item cannot land in the new item's
-- tally after Blizzard reuses the rollID (B46) -- which it does within seconds on trash.
local function TrackedItemID(rollID)
    local link = LC.rollItems[rollID]
    return (type(link) == "string" and link:match("item:(%d+)")) or ""
end


-- =====================================================================
--  Vote List  (shown to non-council raiders via LC_START message)
-- =====================================================================
-- Every currently active roll gets its own row, all visible at once, so a raider can compare
-- everything that's dropped before deciding how to vote on each individually (e.g. BIS on one
-- item and Pass on another because they only actually want the one) — items are never hidden
-- behind each other, and voting on one never affects the others.

function Vote.CreateVoteList()
    local f = CreateFrame("Frame", "KART_LCVoteList", UIParent, "BackdropTemplate")
    f:SetSize(380, 200)
    f:SetPoint("CENTER", 0, -80)
    LC.RegisterWindow(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.UI:ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcVotePopupPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", 16, -10)
    f.title:SetText(KART.L.LC_VOTE_TITLE)
    KART.UI:CreateHeaderLine(f, -28)

    -- Closing just hides the window — it doesn't discard anything, so it comes back on its own
    -- as soon as a new item starts rolling (or can be reopened via any still-active row source).
    local closeBtn = KART.UI:CreateHeaderIconButton(f, "×", function() f:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LCVoteListScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(345, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.UI:StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end

    f.scrollChild = scrollChild
    f.rows = {}

    -- Restore saved position (reuses the old single-popup setting name)
    local pos = KART_Settings and KART_Settings.lcVotePopupPos
    if pos and type(pos) == "table" and KAUI.IsSavedPosOnScreen(pos.x, pos.y) then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    -- One shared ticker drives every row's countdown; a row is dropped once its own voting
    -- window closes. Only touches timer text on a normal tick — a full rebuild (which would
    -- reset in-progress note text) only happens when a row actually gets added or removed.
    -- Only runs while the window is actually visible: created on show, cancelled on hide, instead
    -- of ticking forever behind an IsShown guard. The guard stays as belt-and-braces.
    local function startVoteTicker()
        if f.ticker then return end
        f.ticker = C_Timer.NewTicker(1, function()
            if not f:IsShown() then return end
            local now = GetTime()
            local changed = Vote.PruneExpiredRolls()
            if changed then
                Vote.RefreshVoteListRows()
            else
                local pool = (KART_Settings and KART_Settings.lcVoteLayoutCompact) and f.compactRows or f.rows
                for i, rid in ipairs(Vote.GetVisibleRolls()) do
                    local row = pool and pool[i]
                    if row and row:IsShown() then
                        local deadline  = LC.rollDeadlines[rid]
                        local remaining = deadline and math.max(0, math.ceil(deadline - now)) or 0
                        local votedCount, total = LC.CountVotes(rid)
                        row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS, votedCount, total))
                    end
                end
            end
        end)
    end
    f:HookScript("OnShow", startVoteTicker)
    f:HookScript("OnHide", function() if f.ticker then f.ticker:Cancel() f.ticker = nil end end)
    if f:IsShown() then startVoteTicker() end

    LC.voteListFrame = f
    return f
end

-- Drops rolls whose voting window has closed from the list, and — for a non-council client that
-- isn't tracking them in a council tab — frees their per-roll state (votes/item/deadline) so it
-- doesn't accumulate for the whole session. The vote ticker only runs while the window is visible,
-- so this also runs from ShowVotePopup to sweep rolls that expired while the window was hidden.
-- Returns true if anything was removed.
function Vote.PruneExpiredRolls()
    local now = GetTime()
    local changed = false
    for i = #LC.voteListRolls, 1, -1 do
        local rid = LC.voteListRolls[i]
        local deadline = LC.rollDeadlines[rid]
        if deadline and now >= deadline then
            table.remove(LC.voteListRolls, i)
            changed = true
            local inCouncil = false
            for _, cid in ipairs(LC.councilTabs) do
                if cid == rid then inCouncil = true break end
            end
            if not inCouncil then LC.Trade.ClearRollState(rid) end
        end
    end
    return changed
end

-- Registers rollID as an active roll and (re)builds the list.
--
-- The two arguments behave differently on a repeat call for the same rollID, on purpose: itemLink is
-- only used the first time (LC.rollItems keeps the link it already has), while the deadline is RESET
-- every call. That reset is load-bearing — LC.StartTest reuses its four fixed test rollIDs and
-- refreshes their countdown by simply calling this again. In live play nothing calls this twice for
-- one roll (LC_START is sent once, and LC.HandleStateRequest deliberately doesn't replay it), so the
-- difference never shows up outside the test window.
function Vote.ShowVotePopup(rollID, itemLink, seconds)
    Vote.PruneExpiredRolls() -- clear anything that expired while the window was hidden before adding
    LC.rollItems[rollID]     = LC.rollItems[rollID] or itemLink
    LC.rollDeadlines[rollID] = GetTime() + (seconds or 20)

    local alreadyListed = false
    for _, rid in ipairs(LC.voteListRolls) do
        if rid == rollID then alreadyListed = true break end
    end
    if not alreadyListed then
        table.insert(LC.voteListRolls, rollID)
    end

    Vote.RefreshVoteListRows()
end

-- Removes rollID from the list (e.g. a result came in for it from elsewhere) and rebuilds.
function Vote.RemoveVoteListItem(rollID)
    for i = #LC.voteListRolls, 1, -1 do
        if LC.voteListRolls[i] == rollID then table.remove(LC.voteListRolls, i) end
    end
    -- ...IfShown, not the plain refresh: RefreshVoteListRows ends in an unconditional f:Show() when
    -- any roll remains, so refreshing here would pop the vote window back up on a client that had
    -- deliberately closed it (its "x" only hides). Removing an item must never open a window.
    -- When the window IS up, the normal refresh still runs and still hides it if this was the last row.
    Vote.RefreshVoteListRowsIfShown()
    if #LC.voteListRolls == 0 then LC.showAllOverride = nil end
end

-- Shared stand-in for LC.hiddenIrrelevant while the setting that fills it is off, so the filter
-- below can stay one expression without allocating a throwaway table several times a second.
local NO_HIDDEN = {}

-- Which of LC.voteListRolls actually get drawn. Two independent, purely personal reasons a roll is
-- left out, both lifted together by LC.showAllOverride (/kart showall):
--   * the player has voted on it and set lcVotedItemDisplay == "hide" (card/row disappears, window
--     shrinks);
--   * their class cannot use it and lcHideIrrelevant answered it for them (LC.hiddenIrrelevant).
-- The second reason is read through the LIVE setting rather than off the flag alone: switching
-- lcHideIrrelevant off has to bring those rows back for the rolls still running, not only from the
-- next batch on. The flag itself stays, so switching it on again re-hides exactly the same rolls.
-- Returns LC.voteListRolls itself (no copy) whenever neither reason removes anything — which needs
-- checking both, not just the voted one.
function Vote.GetVisibleRolls()
    local hideVoted = (KART_Settings and KART_Settings.lcVotedItemDisplay) == "hide"
    if LC.showAllOverride then return LC.voteListRolls end
    local hidden = (KART_Settings and KART_Settings.lcHideIrrelevant and LC.hiddenIrrelevant) or NO_HIDDEN
    if not hideVoted then
        local anyIrrelevant = false
        for _, rollID in ipairs(LC.voteListRolls) do
            if hidden[rollID] then anyIrrelevant = true break end
        end
        if not anyIrrelevant then return LC.voteListRolls end
    end
    local visible = {}
    for _, rollID in ipairs(LC.voteListRolls) do
        if not hidden[rollID] and not (hideVoted and LC.votedByMe[rollID]) then
            table.insert(visible, rollID)
        end
    end
    return visible
end

-- Thin dispatcher: resizes nothing itself, just picks which style actually builds the rows.
-- Hides the *inactive* style's row pool first so switching styles (or the very first refresh
-- after a `/reload`) never leaves a stale row from the other layout visible underneath.
function Vote.RefreshVoteListRows()
    -- Before anything is measured or drawn: an item answered automatically here changes both the
    -- visible-row set and the window height that follows from it.
    LC.Relevance.ApplyToPendingRolls()
    if #LC.voteListRolls == 0 then
        -- Every roll this batch tracked has now expired or been removed — /kart showall's
        -- override only ever meant "for the rolls currently on screen"; the next fresh batch
        -- should start clean, respecting the display setting again from roll one.
        LC.showAllOverride = nil
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if #Vote.GetVisibleRolls() == 0 then
        -- Every remaining roll is hidden — voted-and-hidden (lcVotedItemDisplay == "hide"),
        -- irrelevant-and-hidden (lcHideIrrelevant), or a mix of both. The batch itself isn't done
        -- (LC.voteListRolls is still non-empty, so showAllOverride must NOT reset here), there's
        -- just nothing left to show unless/until /kart showall or one of those two settings
        -- changing brings something back.
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if not LC.voteListFrame then Vote.CreateVoteList() end
    local f = LC.voteListFrame

    local compact = KART_Settings and KART_Settings.lcVoteLayoutCompact
    local needsRestyle
    if compact then
        for _, row in ipairs(f.rows or {}) do row:Hide() end
        needsRestyle = Vote.RefreshVoteListRows_Compact(f)
    else
        for _, row in ipairs(f.compactRows or {}) do row:Hide() end
        needsRestyle = Vote.RefreshVoteListRows_Spacious(f)
    end
    f:Show()

    -- The window (on first build) and anything newly registered with KART.UI above (close
    -- button, "Note" label, a newly pooled vote/chip button, note EditBox) registers *after* the
    -- last KART.UpdateStyles() call that ran before this point in the session, since this whole
    -- window is built lazily on first roll rather than at load (see B2 in BACKLOG.md). Re-applying
    -- here is what reaches a widget created by a later, larger batch of simultaneous rolls, or a
    -- vote-button set grown mid-session (LC.GetButtonConfig changing via a Settings-tab edit or an
    -- accepted config sync), not just whatever existed on the very first build.
    --
    -- Gated on needsRestyle (true only when this pass actually registered something new — see the
    -- flag of the same name inside RefreshVoteListRows_Spacious/_Compact, set both on a new row and
    -- on a new vote button within an existing row) rather than called on every refresh: this
    -- function runs on every new roll, every local vote, and every expiry sweep, which during
    -- active looting can be several times a second, and a full KART.UpdateStyles() re-applies far
    -- more than these widgets' font (main window scale/strata, every registered EditBox's font,
    -- the minimap icon tint, a BuffCheck refresh if that window is open) — cheap in isolation, but
    -- needless work on the refreshes where nothing new registered at all. A recycled/repositioned
    -- row or button never needs this, only a freshly created one.
    if needsRestyle and KART.UpdateStyles then KART.UpdateStyles() end
end

-- Vote.RefreshVoteListRows() always calls f:Show() when there's still a pending roll — deliberate
-- for real loot rolls (see the vote window's close-button comment: it "comes back on its own" so
-- a raider can't just dismiss an active vote), but wrong for a callback that merely changes how
-- the window LOOKS, like the compact-layout checkbox: toggling it while an old, not-yet-expired
-- test roll happens to still be tracked would otherwise pop the window back open and re-show
-- stale votes, reading as "a new test just started" even though nothing new was triggered. Only
-- re-render if the window is already visible; otherwise leave it hidden until something that
-- actually means "show this" (a new roll, a Test click) calls the dispatcher directly.
function Vote.RefreshVoteListRowsIfShown()
    if LC.voteListFrame and LC.voteListFrame:IsShown() then
        Vote.RefreshVoteListRows()
    end
end

-- Shared click path for both layouts' vote buttons. Test rolls stay local (no group to
-- broadcast to — see the original comment in the Spacious handler); real rolls broadcast.
function Vote.CastVote(rollID, buttonIdx, noteBox)
    -- A vote the player clicked is final. One that LC.Relevance cast on their behalf is not: the
    -- relevance check can be wrong, and the player's own correction has to win over it. HandleVote
    -- stores per sender and overwrites, so the council simply sees the corrected vote -- no protocol
    -- change and no double counting.
    if LC.votedByMe[rollID] and not LC.autoVotedByMe[rollID] then return end
    -- A stored vote at this point can only be an automatic one being overridden. Drop the hide flag
    -- with it: the row was hidden because the item looked useless to this player, the click just
    -- said otherwise, and leaving the flag set would make the row vanish again the moment
    -- /kart showall lapses (a new batch, or the last roll expiring).
    if LC.votedByMe[rollID] then LC.hiddenIrrelevant[rollID] = nil end
    LC.autoVotedByMe[rollID] = nil
    LC.votedByMe[rollID] = buttonIdx
    -- Strip pipes at input, the same way LootCouncilSettings strips colons from the synced fields:
    -- this note is rendered raw into every council member's tooltip, and "|c"/"|H"/"|T" escapes would
    -- otherwise let a raider inject coloured text, fake hyperlinks or textures there. Stripping (not
    -- escaping) at the source keeps the sender's own copy byte-identical to what the receivers store
    -- — HandleVote escapes on top of this, since a hostile client won't have stripped anything.
    local note = (KAUtil.TrimString(noteBox and noteBox:GetText() or ""):gsub("|", ""))
    LC.votedNoteByMe[rollID] = note

    -- Record our own vote locally regardless of test/real: KASC drops our own message when it comes back, see Dispatch, so it never reaches
    -- its own sender, so without this our own progress counter reads one short and a council member
    -- voting on their own drop wouldn't see themselves listed.
    -- How many buttons OUR list has. The index alone is meaningless to a receiver whose list is a
    -- different length -- it would resolve to a different label and be displayed as a confident
    -- fact (see B25 in docs/BACKLOG.md: a whole raid was scored against votes shifted by one).
    -- Carrying the count lets the council panel tell "they voted Offspec" apart from "I cannot know
    -- what they voted", which is the difference that matters when loot is being handed out.
    -- The button SET, not just how many there are: a same-length rename or reorder changes what an
    -- index means and used to slip through untouched (B43). See LC.ButtonFingerprint.
    local buttonCount = LC.ButtonFingerprint()

    local myKey = (KASC.Identity.ResolvePlayer("player"))
    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][myKey] = {idx = buttonIdx, note = note, count = buttonCount}
    -- Our own badge is resolved against whatever the button list says NOW, with nothing stored, so a
    -- mid-roll label edit told the raider they had voted something they never did (B45).
    LC.votedFpByMe[rollID] = buttonCount

    -- Test rolls stay local (no group to broadcast to); real rolls broadcast.
    if not LC.IsTestRoll(rollID) then
        -- "#" prefixes the count so a 3.0.x note that happens to start with digits and a colon
        -- ("5:30 uhr") can't be mistaken for one by the receiver's optional-field parse below.
        LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":#" .. buttonCount
            .. ":@" .. TrackedItemID(rollID) .. ":" .. note)
    end
    -- Both branches: refresh the council panel too, so a council member sees their own vote appear
    -- in the panel (rows + tab badge), not just in the vote list.
    LC.RefreshCouncilIfShown(rollID)
    Vote.RefreshVoteListRows()
end

-- "Spacious" style: one card per item, full window width each, large touch targets. The default
-- and recommended style — see docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function Vote.RefreshVoteListRows_Spacious(f)
    local WINDOW_W  = 540
    local CONTENT_W = WINDOW_W - 30 -- mirrors the scrollbar/padding reservation CreateVoteList already uses
    f:SetWidth(WINDOW_W)
    f.scrollChild:SetWidth(CONTENT_W)

    -- v2 sizing: each card is now the full window width (was a fraction of a narrower window),
    -- so every element scales up — this is what actually reads as "premium" rather than just
    -- "spaced out". cols capped at 5 (not the previous 3) so the default 5-category button set
    -- fits in a single row; a leader-configured 6th category still wraps to a second row instead
    -- of overflowing.
    local buttons   = LC.GetButtonConfig()
    local ICON_SIZE = 46
    local ACCENT_H  = 4  -- quality-color strip along the top edge of each card
    local MARGIN    = 16 -- left/right inner padding of each item block
    local cols      = math.min(#buttons, 5)
    local btnRows   = math.ceil(#buttons / cols)
    local BTN_GAP   = 10 -- horizontal gap between vote buttons
    local btnW      = math.floor((CONTENT_W - MARGIN * 2 - (cols - 1) * BTN_GAP) / cols)
    local btnH      = 34
    local BTN_ROW_GAP = 8 -- vertical gap between rows of vote buttons
    local btnAreaH  = btnRows * btnH + (btnRows - 1) * BTN_ROW_GAP
    local BTN_TOP   = MARGIN + ICON_SIZE + 15 -- header row (icon+name+timer) height, then a gap
    local GAP_BTN_NOTE = 13
    local noteH     = 24
    local BOTTOM_PAD = 16
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD -- unvoted height
    local VOTED_BADGE_H = 20 -- matches row.votedBadge:SetHeight(20) below
    local votedRowH = ACCENT_H + BTN_TOP + VOTED_BADGE_H + BOTTOM_PAD -- voted rows drop the button/note area entirely
    local shrinkVoted = KART_Settings.lcVotedItemDisplay == "shrink"
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls

    -- Tracks whether this pass registered anything new with KART.UI (a brand-new row, or a
    -- brand-new vote button within an existing row — LC.GetButtonConfig's category count can grow
    -- mid-session from a Settings-tab edit or an accepted config sync), as opposed to only reusing/
    -- repositioning pooled widgets already on screen. Returned to the caller
    -- (Vote.RefreshVoteListRows) so it only pays for a full KART.UpdateStyles() re-apply on the
    -- passes that actually register something new, not on every single vote/expiry refresh.
    local needsRestyle = false

    -- Same short-name extraction the test-roll vote branch further below already uses — this is
    -- the local player's own Droptimizer gain% for the item, not a per-candidate column (a
    -- vote-list row represents one item, not one candidate, so "the player" here is whoever is
    -- looking at their own vote window).
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")

    local visibleRolls = Vote.GetVisibleRolls()
    local y = 0 -- running offset, since voted rows may be shorter than unvoted ones (shrinkVoted)
    for i, rollID in ipairs(visibleRolls) do
        local row = f.rows[i]
        if not row then
            needsRestyle = true
            row = CreateFrame("Frame", nil, f.scrollChild, "BackdropTemplate")
            KART.UI:SetPixelBackdrop(row, {bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.55)
            row:SetBackdropBorderColor(0, 0, 0, 1)

            -- Quality-color strip along the card's top edge — the main visual cue that separates
            -- one card from the next, on top of the ROW_GAP spacing itself.
            row.accentStrip = row:CreateTexture(nil, "ARTWORK")
            row.accentStrip:SetPoint("TOPLEFT", 0, 0)
            row.accentStrip:SetPoint("TOPRIGHT", 0, 0)
            row.accentStrip:SetHeight(ACCENT_H)

            -- Accent frame behind the icon, tinted to the item's own quality colour — the cheap,
            -- crisp equivalent of a soft glow (a true blurred glow needs a bundled additive-blend
            -- texture WoW doesn't ship, see the earlier "what more effort actually costs" note).
            row.itemIconBorder = row:CreateTexture(nil, "BACKGROUND")
            row.itemIconBorder:SetColorTexture(1, 1, 1, 1)

            row.itemIcon = row:CreateTexture(nil, "ARTWORK")
            row.itemIcon:SetSize(ICON_SIZE, ICON_SIZE)
            row.itemIcon:SetPoint("TOPLEFT", MARGIN, -(ACCENT_H + MARGIN))
            row.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.itemIconBorder:SetPoint("TOPLEFT", row.itemIcon, -2, 2)
            row.itemIconBorder:SetPoint("BOTTOMRIGHT", row.itemIcon, 2, -2)

            -- Radial "time remaining" wipe — the same native Cooldown widget every spell/ability
            -- button already uses, so it animates on its own once set, no per-frame Lua needed.
            row.itemCD = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
            row.itemCD:SetAllPoints(row.itemIcon)
            row.itemCD:SetHideCountdownNumbers(true)
            row.itemCD:SetDrawBling(false)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
            row.itemText:SetPoint("TOPLEFT", row.itemIcon, "TOPRIGHT", 10, -4)
            row.itemText:SetWidth(CONTENT_W - ICON_SIZE - MARGIN * 2 - 10 - 60) -- leaves room for the timer chip on the right
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(true)
            row.itemText:SetMaxLines(2)

            -- FontStrings can't take mouse scripts directly; overlay a hover frame for the
            -- tooltip, spanning both the icon and the name so hovering either shows it.
            row.itemHover = CreateFrame("Frame", nil, row)
            row.itemHover:SetPoint("TOPLEFT", row.itemIcon, "TOPLEFT")
            row.itemHover:SetPoint("RIGHT", row.itemText, "RIGHT")
            -- Height set explicitly, NOT by anchoring the bottom to the item name. A FontString's
            -- box is its text's box: the name sits 4px below the icon's top and is ~17px tall for a
            -- single line, so the region ended 21px down against a 46px icon -- the lower half of
            -- the icon showed no tooltip at all, reported twice independently (B26, issues #7/#8).
            -- The max() also covers the compact layout, whose icon is smaller than a wrapped
            -- two-line name.
            row.itemHover:SetHeight(math.max(ICON_SIZE, 36))
            row.itemHover:EnableMouse(true)

            row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timerText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            row.timerText:SetPoint("TOPRIGHT", -MARGIN, -(ACCENT_H + MARGIN + 2))

            -- Own Droptimizer gain% for this item — mirrors the council panel's row.gainText
            -- (see LC.RefreshCouncilRows / KART.DT.GetGainPercent), just anchored under the
            -- timer chip instead of in its own column since a vote-list card has no columns.
            row.gainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.gainText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            row.gainText:SetPoint("TOPRIGHT", row.timerText, "BOTTOMRIGHT", 0, -4)

            row.btnArea = CreateFrame("Frame", nil, row)
            row.btnArea:SetPoint("TOPLEFT", MARGIN, -BTN_TOP)
            row.voteButtons = {}

            -- Small coloured chip instead of plain text, so "you already voted" reads as a status
            -- badge (matching the vote buttons' own material) rather than a leftover label.
            row.votedBadge = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.votedBadge:SetPoint("TOPLEFT", row.btnArea, "TOPLEFT", 0, -2)
            row.votedBadge:SetHeight(20)
            KART.UI:SetPixelBackdrop(row.votedBadge, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.votedText = row.votedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.votedText:SetPoint("CENTER")

            row.noteLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.noteLabel:SetText(KART.L.LC_NOTE_LABEL_SHORT)
            row.noteLabel:SetTextColor(0.6, 0.6, 0.6)
            KART.UI:RegisterLabel(row.noteLabel)

            row.noteBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
            row.noteBox:SetAutoFocus(false)
            row.noteBox:SetMaxLetters(80)
            row.noteBox:SetFontObject("GameFontHighlightSmall")
            KART.UI:SetPixelBackdrop(row.noteBox, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.noteBox:SetBackdropColor(0, 0, 0, 0.5)
            row.noteBox:SetTextInsets(6, 6, 0, 0)
            row.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            KART.UI:RegisterEditBox(row.noteBox)

            f.rows[i] = row
        end

        -- Resolved up here because the row HEIGHT depends on it. hasVote, not the raw LC.votedByMe
        -- flag: a stored vote index with no matching button (the leader shrank the label set after we
        -- voted) renders as unvoted below, so it must also lay out as unvoted — otherwise the row got
        -- shrunk to badge height while still showing the full button/note area inside it.
        local voted    = LC.votedByMe[rollID]
        -- Withheld when the button set has changed since we voted (B45): the index means something
        -- else now, and telling a raider they voted a label they never clicked is worse than telling
        -- them nothing. Same guard the council panel applies to everybody else's vote.
        local votedFp = LC.votedFpByMe[rollID]
        local votedStale = LC.VoteLabelStale(votedFp, buttons)
        local votedDef = (not votedStale) and voted and buttons[tonumber(voted)] or nil
        -- An answer LC.Relevance cast on the player's behalf leaves the row OPEN: CastVote lets
        -- exactly one automatic vote be overridden (see there), and the buttons that do the
        -- overriding only exist while hasVote is false. Rendered as a finished "you voted X" badge,
        -- the correction the tooltip promises would have nothing to click.
        local isAuto   = LC.autoVotedByMe[rollID] ~= nil
        local hasVote  = votedDef ~= nil and not isAuto

        local thisRowH = (shrinkVoted and hasVote) and votedRowH or rowH
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(thisRowH)
        y = y + thisRowH + ROW_GAP
        row.btnArea:SetPoint("RIGHT", -MARGIN, 0)
        row.btnArea:SetHeight(btnAreaH)
        row.noteLabel:ClearAllPoints()
        row.noteLabel:SetPoint("BOTTOMLEFT", MARGIN, BOTTOM_PAD)
        row.noteBox:ClearAllPoints()
        row.noteBox:SetHeight(noteH)
        row.noteBox:SetPoint("LEFT", row.noteLabel, "RIGHT", 6, 0)
        row.noteBox:SetPoint("RIGHT", -MARGIN, 0)
        row.noteBox:SetPoint("BOTTOM", 0, BOTTOM_PAD)
        row:Show()

        -- A new rollID landed on this recycled row (items above it expired and shifted the
        -- list) — reset anything that belongs to the previous item so nothing carries over.
        if row.currentRollID ~= rollID then
            row.currentRollID = rollID
            if row.noteBox then row.noteBox:SetText("") end
        end

        local rollLink = LC.rollItems[rollID]
        row.itemText:SetText((rollLink or "???") .. LC.Trade.GetDuplicateOrdinal(rollID))

        -- Real icon when we have one; otherwise the same tinted placeholder used by the council
        -- panel's tabs (see RefreshCouncilTabs), so both windows degrade the same way.
        local ir, ig, ib = LC.ParseItemColor(rollLink)
        LC.SetItemIcon(row.itemIcon, rollLink, ir, ig, ib)
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
        row.accentStrip:SetColorTexture(ir, ig, ib)

        local deadline  = LC.rollDeadlines[rollID]
        local remaining = deadline and math.max(0, math.ceil(deadline - GetTime())) or 0
        do
            local votedCount, total = LC.CountVotes(rollID)
            row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS, votedCount, total))
        end
        if deadline then
            row.itemCD:SetCooldown(GetTime(), math.max(deadline - GetTime(), 0))
        end

        -- Only shown when the module is on AND sim data actually exists for this item — unlike
        -- the council panel's column (always visible with a "—" placeholder), a bare-column look
        -- doesn't fit these compact cards, so no data means no line at all.
        local dtEnabled = KART_Settings.dtModuleEnabled ~= false
        local gainPct = dtEnabled and KART.DT and KART.DT.GetGainPercent and LC.rollItems[rollID]
            and KART.DT.GetGainPercent(myShort, LC.rollItems[rollID]) or nil
        if gainPct then
            local color = gainPct >= 0 and "|cff40c040" or "|cffc04040"
            row.gainText:SetText(string.format("%s: %s%+.1f%%|r", KART.L.DT_COL_GAIN, color, gainPct))
            row.gainText:Show()
        else
            row.gainText:Hide()
        end

        row.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[rollID]
            if not LC.IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        row.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- voted / votedDef / hasVote are resolved further up (the row height needs them) — see there
        -- for why a stored index with no matching button reads as unvoted.
        row.btnArea:SetShown(not hasVote)
        row.noteLabel:SetShown(not hasVote)
        row.noteBox:SetShown(not hasVote)
        row.votedText:SetShown(hasVote)
        row.votedBadge:SetShown(hasVote)
        if votedDef then
            -- The note the raider typed before voting is otherwise gone the moment the note box
            -- hides (see LC.votedNoteByMe) — show it alongside the vote so it's not just forgotten.
            local label = votedDef.label
            local noteText = LC.votedNoteByMe[rollID]
            if noteText and noteText ~= "" then
                if #noteText > 30 then noteText = noteText:sub(1, 30) .. "..." end
                label = label .. " — \"" .. noteText .. "\""
            end
            row.votedText:SetText(string.format(KART.L.LC_VOTED_ROW, label))
            row.votedBadge:SetBackdropColor(votedDef.r, votedDef.g, votedDef.b, 0.18)
            row.votedBadge:SetBackdropBorderColor(votedDef.r, votedDef.g, votedDef.b, 0.7)
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, CONTENT_W - MARGIN * 2))
        end

        for bi = #buttons + 1, #row.voteButtons do
            if row.voteButtons[bi] then row.voteButtons[bi]:Hide() end
        end

        -- hasVote, not voted: the button area is shown whenever hasVote is false, so it has to be
        -- populated in exactly those cases too. Keyed off the raw flag it stayed empty for a vote
        -- whose button no longer exists — a blank gap where the buttons should be.
        if not hasVote then
            for bi, def in ipairs(buttons) do
                local col = (bi - 1) % cols
                local brow = math.floor((bi - 1) / cols)

                local btn = row.voteButtons[bi]
                if not btn then
                    -- Pooled independently of the row itself: LC.GetButtonConfig's category count
                    -- can grow mid-session (a Settings-tab edit, or an accepted LC_SYNC_ACCEPT
                    -- config push), which adds a new button to an EXISTING row without that row
                    -- itself being new — CreateModernButton self-registers this button's label
                    -- with KART.UI just like a brand-new row's own widgets do, so this needs the
                    -- same needsRestyle signal, not just the "if not row" branch above.
                    needsRestyle = true
                    btn = KART.UI:CreateModernButton(row.btnArea, def.label)
                    btn.grad = KART.UI:CreateGradientOverlay(btn)
                    btn.iconTex = btn:CreateTexture(nil, "ARTWORK")
                    btn.iconTex:SetSize(13, 13)
                    btn.iconTex:SetPoint("LEFT", 6, 0)
                    btn.text:ClearAllPoints()
                    btn.text:SetPoint("CENTER", 8, 0)
                    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
                    row.voteButtons[bi] = btn
                else
                    btn:Show()
                    btn.text:SetText(def.label)
                end
                btn:SetSize(btnW, btnH)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", row.btnArea, "TOPLEFT", col * (btnW + BTN_GAP), -brow * (btnH + BTN_ROW_GAP))
                -- Full-strength border (was 0.55) plus a tinted gradient fill behind the label, so
                -- the category reads as the button's own material instead of just its outline.
                btn:SetBackdropBorderColor(def.r, def.g, def.b, 1)
                -- The only cue that KART already answered this row: its own answer's button burns
                -- brighter than the others and says so on hover. Deliberately not the voted badge —
                -- that shares row.btnArea's anchor, so showing both would stack them on top of each
                -- other; moving it needs real layout work and is the maintainer's call in-game.
                local autoPicked = isAuto and tonumber(voted) == bi
                KART.UI:SetGradientOverlayColor(btn.grad, def.r, def.g, def.b, autoPicked and 0.55 or 0.22)
                btn.tooltipText = autoPicked and KART.L.LC_AUTO_VOTED_HINT or nil
                btn.iconTex:SetTexture(LC.GetVoteIconTexture(bi, def))

                local capturedIdx    = bi
                local capturedRollID = rollID
                btn:SetScript("OnClick", function()
                    Vote.CastVote(capturedRollID, capturedIdx, row.noteBox)
                end)
            end
        end
    end

    for i = #visibleRolls + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f.scrollChild:SetHeight(math.max(y, 1))
    f:SetHeight(math.min(32 + y + 12, 600))

    LC.ApplyFontSize()
    return needsRestyle
end

-- "Compact" style: one short single-line row per item, vote buttons shrunk to icon-only chips.
-- Alternative for players who'd rather keep the window small than have large touch targets — see
-- docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function Vote.RefreshVoteListRows_Compact(f)
    local WINDOW_W  = 430
    local CONTENT_W = WINDOW_W - 30
    f:SetWidth(WINDOW_W)
    f.scrollChild:SetWidth(CONTENT_W)

    local buttons  = LC.GetButtonConfig()
    local MARGIN   = 10
    local ICON_SIZE = 26
    local CHIP     = 24
    local CHIP_GAP = 5
    local HEADER_H = ICON_SIZE + MARGIN -- icon row height + top padding
    local ACTION_H = CHIP + 8           -- chip row height + its own top gap
    local rowH     = HEADER_H + ACTION_H + MARGIN -- + bottom padding
    local ROW_GAP  = 8

    -- Same rationale as the Spacious renderer above: a vote-list row is one item, not one
    -- candidate, so the only "player" gain% that makes sense here is the local player's own.
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")

    f.compactRows = f.compactRows or {}

    -- Same reasoning as the Spacious renderer's needsRestyle above — row.noteBox below registers
    -- with KART.UI just like the Spacious "Note" label does, so this pass needs to report whether
    -- it created anything new too. Unlike Spacious, the chip buttons created further down (see
    -- row.chipButtons below) do NOT need the same treatment: they carry only a plain unregistered
    -- gradient texture (KART.UI:CreateGradientOverlay, which never registers anything) and an icon
    -- texture/tooltip, no registered FontString or EditBox of their own — confirmed by grepping
    -- this whole function for every KART.UI:Register*/Create* call.
    local needsRestyle = false

    local visibleRolls = Vote.GetVisibleRolls()
    for i, rollID in ipairs(visibleRolls) do
        local row = f.compactRows[i]
        if not row then
            needsRestyle = true
            row = CreateFrame("Frame", nil, f.scrollChild, "BackdropTemplate")
            KART.UI:SetPixelBackdrop(row, {bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.55)
            row:SetBackdropBorderColor(0, 0, 0, 1)

            row.itemIconBorder = row:CreateTexture(nil, "BACKGROUND")
            row.itemIconBorder:SetColorTexture(1, 1, 1, 1)

            row.itemIcon = row:CreateTexture(nil, "ARTWORK")
            row.itemIcon:SetSize(ICON_SIZE, ICON_SIZE)
            row.itemIcon:SetPoint("TOPLEFT", MARGIN, -MARGIN)
            row.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.itemIconBorder:SetPoint("TOPLEFT", row.itemIcon, -2, 2)
            row.itemIconBorder:SetPoint("BOTTOMRIGHT", row.itemIcon, 2, -2)

            row.itemCD = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
            row.itemCD:SetAllPoints(row.itemIcon)
            row.itemCD:SetHideCountdownNumbers(true)
            row.itemCD:SetDrawBling(false)

            row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemText:SetPoint("TOPLEFT", row.itemIcon, "TOPRIGHT", 8, -2)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetWordWrap(false)

            row.itemHover = CreateFrame("Frame", nil, row)
            row.itemHover:SetPoint("TOPLEFT", row.itemIcon, "TOPLEFT")
            row.itemHover:SetPoint("RIGHT", row.itemText, "RIGHT")
            -- Height set explicitly, NOT by anchoring the bottom to the item name. A FontString's
            -- box is its text's box: the name sits 4px below the icon's top and is ~17px tall for a
            -- single line, so the region ended 21px down against a 46px icon -- the lower half of
            -- the icon showed no tooltip at all, reported twice independently (B26, issues #7/#8).
            -- The max() also covers the compact layout, whose icon is smaller than a wrapped
            -- two-line name.
            row.itemHover:SetHeight(math.max(ICON_SIZE, 36))
            row.itemHover:EnableMouse(true)

            row.timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timerText:SetPoint("TOPRIGHT", -MARGIN, -MARGIN)

            -- Own Droptimizer gain% for this item — compact counterpart of the Spacious card's
            -- row.gainText above; smaller font to fit the tighter header row.
            row.gainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.gainText:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            row.gainText:SetPoint("TOPRIGHT", row.timerText, "BOTTOMRIGHT", 0, -2)

            row.chipArea = CreateFrame("Frame", nil, row)
            row.chipArea:SetPoint("TOPLEFT", row.itemIcon, "BOTTOMLEFT", 0, -8)
            row.chipArea:SetSize(CONTENT_W - MARGIN * 2, CHIP)
            row.chipButtons = {}

            row.votedBadge = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.votedBadge:SetPoint("LEFT", row.chipArea, "LEFT")
            row.votedBadge:SetHeight(CHIP)
            KART.UI:SetPixelBackdrop(row.votedBadge, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.votedText = row.votedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.votedText:SetPoint("CENTER")

            -- Note toggle sits inline after the last chip, same row — chipArea is wide enough
            -- (see the SetSize above) that there's room without wrapping to a second line.
            -- Native icon texture, not a Unicode glyph: WoW's default game fonts render most
            -- Dingbats/Geometric-Shapes glyphs (including the pencil "✎" this used before) as an
            -- empty "tofu" box — see the identical caveat already documented above
            -- VOTE_ICON_TEXTURES, which exists for exactly this reason. Reusing Blizzard's own
            -- guild-roster "edit public note" icon here since it's thematically exact.
            row.notePencil = CreateFrame("Button", nil, row.chipArea)
            row.notePencil:SetSize(CHIP, CHIP)
            row.notePencil.icon = row.notePencil:CreateTexture(nil, "ARTWORK")
            row.notePencil.icon:SetAllPoints()
            row.notePencil.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")

            row.noteBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
            row.noteBox:SetHeight(CHIP)
            row.noteBox:SetAutoFocus(false)
            row.noteBox:SetMaxLetters(80)
            row.noteBox:SetFontObject("GameFontHighlightSmall")
            KART.UI:SetPixelBackdrop(row.noteBox, {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.noteBox:SetBackdropColor(0, 0, 0, 0.85)
            row.noteBox:SetTextInsets(6, 6, 0, 0)
            row.noteBox:SetPoint("LEFT", row.notePencil, "RIGHT", 6, 0)
            row.noteBox:SetPoint("RIGHT", row.chipArea, "RIGHT", 0, 0)
            row.noteBox:Hide()
            row.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
            KART.UI:RegisterEditBox(row.noteBox)

            row.notePencil:SetScript("OnClick", function()
                if row.noteBox:IsShown() then
                    row.noteBox:Hide()
                else
                    row.noteBox:Show()
                    row.noteBox:SetFocus()
                end
            end)

            f.compactRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(rowH)
        row:Show()

        if row.currentRollID ~= rollID then
            row.currentRollID = rollID
            if row.noteBox then row.noteBox:SetText("") row.noteBox:Hide() end
        end

        local rollLink = LC.rollItems[rollID]
        row.itemText:SetText((rollLink or "???") .. LC.Trade.GetDuplicateOrdinal(rollID))
        row.itemText:SetWidth(CONTENT_W - ICON_SIZE - MARGIN * 2 - 8 - 60)

        local ir, ig, ib = LC.ParseItemColor(rollLink)
        LC.SetItemIcon(row.itemIcon, rollLink, ir, ig, ib)
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
        row.itemText:SetTextColor(ir, ig, ib)

        local deadline  = LC.rollDeadlines[rollID]
        local remaining = deadline and math.max(0, math.ceil(deadline - GetTime())) or 0
        do
            local votedCount, total = LC.CountVotes(rollID)
            row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS, votedCount, total))
        end
        if deadline then
            row.itemCD:SetCooldown(GetTime(), math.max(deadline - GetTime(), 0))
        end

        local dtEnabled = KART_Settings.dtModuleEnabled ~= false
        local gainPct = dtEnabled and KART.DT and KART.DT.GetGainPercent and LC.rollItems[rollID]
            and KART.DT.GetGainPercent(myShort, LC.rollItems[rollID]) or nil
        if gainPct then
            local color = gainPct >= 0 and "|cff40c040" or "|cffc04040"
            row.gainText:SetText(string.format("%s: %s%+.1f%%|r", KART.L.DT_COL_GAIN, color, gainPct))
            row.gainText:Show()
        else
            row.gainText:Hide()
        end

        row.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[rollID]
            if not LC.IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        row.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local voted    = LC.votedByMe[rollID]
        local votedDef = voted and buttons[tonumber(voted)]
        -- A stored vote index with no matching button (the leader shrank the label set after we
        -- voted) reads as unvoted, so the vote chips come back instead of an empty badge. So does an
        -- answer LC.Relevance cast on the player's behalf — same reasoning as the Spacious renderer:
        -- the chips are the only way to take CastVote up on its one allowed override.
        local isAuto   = LC.autoVotedByMe[rollID] ~= nil
        local hasVote  = votedDef ~= nil and not isAuto
        row.chipArea:SetShown(not hasVote)
        row.votedText:SetShown(hasVote)
        row.votedBadge:SetShown(hasVote)
        if hasVote then row.noteBox:Hide() end
        if votedDef then
            local label = votedDef.label
            local noteText = LC.votedNoteByMe[rollID]
            if noteText and noteText ~= "" then
                if #noteText > 30 then noteText = noteText:sub(1, 30) .. "..." end
                label = label .. " — \"" .. noteText .. "\""
            end
            row.votedText:SetText(string.format(KART.L.LC_VOTED_ROW, label))
            row.votedBadge:SetBackdropColor(votedDef.r, votedDef.g, votedDef.b, 0.18)
            row.votedBadge:SetBackdropBorderColor(votedDef.r, votedDef.g, votedDef.b, 0.7)
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, CONTENT_W - MARGIN * 2))
        end

        for bi = #buttons + 1, #row.chipButtons do
            if row.chipButtons[bi] then row.chipButtons[bi]:Hide() end
        end

        -- hasVote, not voted — same reasoning as the spacious layout: chipArea is shown whenever
        -- hasVote is false, so it has to be filled in exactly those cases.
        if not hasVote then
            for bi, def in ipairs(buttons) do
                local btn = row.chipButtons[bi]
                if not btn then
                    btn = CreateFrame("Button", nil, row.chipArea, "BackdropTemplate")
                    btn:SetSize(CHIP, CHIP)
                    KART.UI:SetPixelBackdrop(btn, {bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
                    -- Base fill, same as every other backdrop frame in this file (e.g. the row
                    -- backdrops above, or KART.UI:CreateModernButton's own vote buttons) — without
                    -- this the chip has no set background color, only the category-tinted border
                    -- set below, which at 24px is easy to mistake for "no button here at all".
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                    btn.grad = KART.UI:CreateGradientOverlay(btn)
                    btn.iconTex = btn:CreateTexture(nil, "ARTWORK")
                    btn.iconTex:SetPoint("TOPLEFT", 4, -4)
                    btn.iconTex:SetPoint("BOTTOMRIGHT", -4, 4)
                    row.chipButtons[bi] = btn
                else
                    btn:Show()
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", row.chipArea, "TOPLEFT", (bi - 1) * (CHIP + CHIP_GAP), 0)
                btn:SetBackdropBorderColor(def.r, def.g, def.b, 1)
                -- Same cue as the Spacious card: the chip KART answered with burns brighter and
                -- explains itself in its own tooltip, since a 24px chip row has nowhere to put a
                -- badge next to it (see the Spacious comment for why the badge itself can't serve).
                local autoPicked = isAuto and tonumber(voted) == bi
                KART.UI:SetGradientOverlayColor(btn.grad, def.r, def.g, def.b, autoPicked and 0.55 or 0.22)
                btn.iconTex:SetTexture(LC.GetVoteIconTexture(bi, def))

                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(def.label, def.r, def.g, def.b)
                    if autoPicked then GameTooltip:AddLine(KART.L.LC_AUTO_VOTED_HINT, nil, nil, nil, true) end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                local capturedIdx    = bi
                local capturedRollID = rollID
                btn:SetScript("OnClick", function()
                    Vote.CastVote(capturedRollID, capturedIdx, row.noteBox)
                end)

                -- Chip position doubles as the pencil icon's anchor point once all 5 default
                -- categories are laid out, so the note toggle sits right after the last chip.
                if bi == #buttons then
                    row.notePencil:ClearAllPoints()
                    row.notePencil:SetPoint("LEFT", btn, "RIGHT", 6, 0)
                end
            end
        end
    end

    for i = #visibleRolls + 1, #f.compactRows do
        if f.compactRows[i] then f.compactRows[i]:Hide() end
    end

    f.scrollChild:SetHeight(math.max(#visibleRolls * (rowH + ROW_GAP), 1))
    f:SetHeight(math.min(32 + #visibleRolls * (rowH + ROW_GAP) + 12, 600))

    LC.ApplyFontSize()
    return needsRestyle
end

--- Manually sets (overrides) a player's vote in the council panel — e.g. they voted verbally or
--- via whisper instead of clicking the vote popup. Purely a local display correction: unlike
--- AssignWinner, this never announces anything, never touches loot history, and never triggers
--- the reassignment-confirmation dialog. Any note the player already attached is kept as-is.
function Vote.SetPlayerVote(rollID, playerKey, buttonIdx)
    LC.votes[rollID] = LC.votes[rollID] or {}
    local prev = LC.votes[rollID][playerKey]
    local note = (prev and prev.note) or ""
    LC.votes[rollID][playerKey] = {idx = buttonIdx, note = note}

    LC.RefreshCouncilIfShown(rollID)
end

-- Toggles this council member's own (non-binding) pick for who should get rollID — clicking the
-- same candidate again retracts it, clicking a different one replaces it (one pick per item per
-- council member). Test rolls stay local like everywhere else; real rolls broadcast so every
-- council member's tally stays in sync.
function Vote.ToggleCouncilVote(rollID, candidateKey)
    local myKey = (KASC.Identity.ResolvePlayer("player"))
    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    local retracting = (LC.councilVotes[rollID][myKey] == candidateKey)
    LC.councilVotes[rollID][myKey] = (not retracting) and candidateKey or nil

    if not LC.IsTestRoll(rollID) then
        LC.SendLC("LC_CVOTE:" .. rollID .. ":@" .. TrackedItemID(rollID) .. ":"
            .. (retracting and "" or candidateKey))
    end

    KART.LC.Council.RefreshCouncilRows()
end

-- Splits an LC_VOTE payload into rollID, button index, the sender's button COUNT and the note.
--
-- Two shapes on the wire: "rollID:idx:#count:note" from 3.1 onwards, and 3.0.x's "rollID:idx:note"
-- without the count. The count stays optional so a mixed-version raid still registers every vote —
-- an old client's simply arrives without the information needed to detect a mismatch, which is the
-- 3.0.x situation regardless.
--
-- The "#" is what makes the optional field unambiguous. Notes are free text and colons are not
-- stripped from them, so a plain numeric field would swallow the start of a note like "5:30 uhr"
-- and read it as a count of 5. Covered by tests/test_lc_votewire.lua, which loads THIS function out
-- of this file rather than a copy of it.
--
-- Returns nil for rollID/idx when the payload is malformed; the caller drops the message on that.
local function ParseVotePayload(payload)
    -- One shape: "rollID:idx:#fingerprint:@itemID:note".
    --
    -- The two older shapes are gone, and B53 is why. 3.0.x sent "rollID:idx:note" with no markers at
    -- all, so a note that itself began with "#2:" was read as a fingerprint -- truncating what the
    -- raider wrote and fabricating a value the sender never sent, which then either wrongly tripped
    -- or wrongly satisfied the mismatch check. Notes are free text and colons are not stripped from
    -- them, so no single-marker format can be made unambiguous against one.
    --
    -- Requiring BOTH markers together settles it: a legacy note would have to begin with
    -- "#<digits>:@<digits>:" to be mistaken for one. Running the current version across the raid is
    -- already mandatory (see LC.PROTOCOL_VERSION), and a vote from an older client now simply does
    -- not parse instead of being silently misread -- which is the better of the two failures.
    local rollID, idx, count, itemID = payload:match("^(%d+):(%d+):#(%d+):@(%d*):")
    if not rollID then return nil end
    local note = payload:match("^%d+:%d+:#%d+:@%d*:(.*)") or ""
    return tonumber(rollID), tonumber(idx), tonumber(count), note, itemID
end

function Vote.HandleVote(payload, senderKey)
    -- Reject votes from anyone not actually in our group (CHAT_MSG_ADDON also delivers whispers) —
    -- otherwise a stranger's whisper lands in LC.votes and inflates the voted-count badge.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    local rollID, idx, count, note, itemID = ParseVotePayload(payload)
    if not rollID or not idx then return end
    -- Ignore votes for a roll we're no longer tracking (already resolved/pruned): a late straggler
    -- would otherwise re-create LC.votes[rollID] as an orphan that no cleanup path ever frees. Every
    -- peer processes LC_START (which sets rollItems) before any vote can be cast, so a legitimate
    -- vote never arrives before this is set.
    if not LC.rollItems[rollID] then return end
    -- ...and that it is the SAME item. Blizzard reuses a rollID for a genuinely different drop within
    -- seconds on trash, so a vote delayed by the network landed in the new item's tally, under a
    -- name that had never seen it (B46). Only when both sides know the item: an older client sends no
    -- itemID, and a roll we are still holding as "???" has none to compare against.
    local mine = TrackedItemID(rollID)
    if itemID and itemID ~= "" and mine ~= "" and itemID ~= mine then return end

    -- Free text from another client, rendered raw into the council row's note tooltip. Double the
    -- pipes so |c colour codes, |H hyperlinks and |T textures can't be injected there (same guard
    -- RC_REASON and LC_HIST_ENTRY already apply on their own receive side). Vote.CastVote strips
    -- them at input, so a well-behaved sender never has any left for this to escape.
    note = (note:gsub("|", "||"))

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderKey] = {idx = idx, note = note, count = count}

    -- Row list only matters for whichever roll is the active tab; the vote-count badge on every
    -- tab (including inactive ones) stays live regardless — see LC.RefreshCouncilIfShown.
    LC.RefreshCouncilIfShown(rollID)
end

-- Receives another raider's automatic 1-100 roll (see LC.OnStartLootRoll) — opt-in, analogous to
-- RCLootCouncil's Need roll. Purely informational, shown as its own column; never used to decide
-- anything automatically.
function Vote.HandleRoll(payload, senderKey)
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    local rollID, value = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    value  = tonumber(value)
    if not rollID or not value then return end
    -- Deliberately NOT gated on LC.rollItems[rollID] the way HandleVote/HandleCouncilVote are: a
    -- roll is auto-broadcast from START_LOOT_ROLL, so it can legitimately arrive before this client
    -- knows the roll exists (a client that gets no local START_LOOT_ROLL learns it only from
    -- LC_START, and other raiders broadcast their rolls at the same instant the leader does). Rolls
    -- are sent exactly once with no retry, so dropping one loses it permanently.
    --
    -- Accepting them means an untracked rollID can hold roll data indefinitely if the roll never
    -- materializes here at all. Stamp when that started so PurgeStaleRoll can tell a legitimately
    -- early roll (sub-second, its LC_START is already on the way) from an orphan left over from a
    -- previous roll that used this same ID. ClearAllRolls sweeps the rest at session end.
    if not LC.rollItems[rollID] then
        LC.rollsPendingSince = LC.rollsPendingSince or {}
        LC.rollsPendingSince[rollID] = LC.rollsPendingSince[rollID] or GetTime()
    end
    LC.rolls[rollID] = LC.rolls[rollID] or {}
    LC.rolls[rollID][senderKey] = value

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        KART.LC.Council.RefreshCouncilRows()
    end
end

-- Receives a council member's (non-binding) pick for who should get rollID — a straw-poll tally
-- only, never an assignment by itself. Like LC_VOTE, this trusts the sender rather than
-- re-verifying council membership over the wire (the panel that sends it is only ever shown to
-- council members in the first place — see IsCouncil in HandleStart/OnStartLootRoll).
function Vote.HandleCouncilVote(payload, senderKey)
    -- Council membership is intentionally trusted (see above), but the sender must at least be in
    -- our group — a bare whisper from outside must not land in the council straw-poll tally.
    if not (senderKey and KASC.Identity.FindUnitForKey(senderKey)) then return end
    -- "rollID:@itemID:candidate" since B46; "rollID:candidate" from older clients. The marker keeps
    -- the item apart from a candidate key, which is free-form text on the wire.
    local rollID, itemID, candidateKey = payload:match("^(%d+):@(%d*):(.*)$")
    if not rollID then
        rollID, candidateKey = payload:match("^(%d+):(.*)$")
    end
    rollID = tonumber(rollID)
    if not rollID then return end
    -- Ignore council votes for an untracked (already resolved/pruned) roll — see HandleVote:
    -- prevents an orphan LC.councilVotes[rollID] that no cleanup path frees.
    if not LC.rollItems[rollID] then return end
    -- Same reused-rollID guard as Vote.HandleVote (B46).
    local mineC = TrackedItemID(rollID)
    if itemID and itemID ~= "" and mineC ~= "" and itemID ~= mineC then return end

    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    if candidateKey == "" then
        LC.councilVotes[rollID][senderKey] = nil -- retracted their pick
    else
        LC.councilVotes[rollID][senderKey] = candidateKey
    end

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        KART.LC.Council.RefreshCouncilRows()
    end
end

-- =====================================================================
--  Addon-message registrations
-- =====================================================================
KASC:RegisterMessage("LC_VOTE", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) Vote.HandleVote(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_ROLL", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) Vote.HandleRoll(payload, ctx:Key()) end)
KASC:RegisterMessage("LC_CVOTE", { payload = true, group = true, enabled = lcEnabled },
    function(payload, ctx) Vote.HandleCouncilVote(payload, ctx:Key()) end)
