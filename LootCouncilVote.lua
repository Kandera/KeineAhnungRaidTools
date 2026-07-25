local addonName, KART = ...

KART.LC.Vote = KART.LC.Vote or {}
local Vote = KART.LC.Vote
local LC = KART.LC

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
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
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
    KART.CreateHeaderLine(f, -28)

    -- Closing just hides the window — it doesn't discard anything, so it comes back on its own
    -- as soon as a new item starts rolling (or can be reopened via any still-active row source).
    local closeBtn = KART.CreateHeaderIconButton(f, "×", function() f:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LCVoteListScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(345, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end

    f.scrollChild = scrollChild
    f.rows = {}

    -- Restore saved position (reuses the old single-popup setting name)
    local pos = KART_Settings and KART_Settings.lcVotePopupPos
    if pos and type(pos) == "table" and KART.IsSavedPosOnScreen(pos.x, pos.y) then
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

-- Registers rollID as an active roll and (re)builds the list. itemLink/seconds only matter the
-- first time a rollID is seen — LC.rollItems/LC.rollDeadlines are the source of truth afterwards.
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
    Vote.RefreshVoteListRows()
end

-- Thin dispatcher: resizes nothing itself, just picks which style actually builds the rows.
-- Hides the *inactive* style's row pool first so switching styles (or the very first refresh
-- after a `/reload`) never leaves a stale row from the other layout visible underneath.
-- Personal display preference (KART_Settings.lcVotedItemDisplay, see the settings dropdown in
-- Task 5 of this plan) — when set to "hide", a roll the local player has already voted on is left
-- out of the rendered list entirely (card/row disappears, window shrinks) unless
-- LC.showAllOverride is set (see /kart showall, Task 6). Returns LC.voteListRolls itself (no copy)
-- whenever nothing is being filtered, so callers that don't need filtering pay no extra cost.
function Vote.GetVisibleRolls()
    if (KART_Settings and KART_Settings.lcVotedItemDisplay) ~= "hide" or LC.showAllOverride then
        return LC.voteListRolls
    end
    local visible = {}
    for _, rollID in ipairs(LC.voteListRolls) do
        if not LC.votedByMe[rollID] then
            table.insert(visible, rollID)
        end
    end
    return visible
end

function Vote.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        -- Every roll this batch tracked has now expired or been removed — /kart showall's
        -- override only ever meant "for the rolls currently on screen"; the next fresh batch
        -- should start clean, respecting the display setting again from roll one.
        LC.showAllOverride = nil
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if #Vote.GetVisibleRolls() == 0 then
        -- Every remaining roll is voted-and-hidden (lcVotedItemDisplay == "hide") — the batch
        -- itself isn't done (LC.voteListRolls is still non-empty, so showAllOverride must NOT
        -- reset here), there's just nothing left to show unless/until /kart showall runs.
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if not LC.voteListFrame then Vote.CreateVoteList() end
    local f = LC.voteListFrame

    local compact = KART_Settings and KART_Settings.lcVoteLayoutCompact
    if compact then
        for _, row in ipairs(f.rows or {}) do row:Hide() end
        Vote.RefreshVoteListRows_Compact(f)
    else
        for _, row in ipairs(f.compactRows or {}) do row:Hide() end
        Vote.RefreshVoteListRows_Spacious(f)
    end
    f:Show()
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
    if LC.votedByMe[rollID] then return end
    LC.votedByMe[rollID] = buttonIdx
    local note = KART.TrimString(noteBox and noteBox:GetText() or "")
    LC.votedNoteByMe[rollID] = note

    -- Record our own vote locally regardless of test/real: SendAddonMessage never echoes back to
    -- its own sender, so without this our own progress counter reads one short and a council member
    -- voting on their own drop wouldn't see themselves listed.
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][myKey] = {idx = buttonIdx, note = note}

    -- Test rolls stay local (no group to broadcast to); real rolls broadcast.
    if not LC.IsTestRoll(rollID) then
        LC.SendLC("LC_VOTE:" .. rollID .. ":" .. buttonIdx .. ":" .. note)
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
            row = CreateFrame("Frame", nil, f.scrollChild, "BackdropTemplate")
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
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
            row.itemHover:SetPoint("BOTTOMRIGHT", row.itemText, "BOTTOMRIGHT")
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
            row.votedBadge:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            row.votedText = row.votedBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.votedText:SetPoint("CENTER")

            row.noteLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.noteLabel:SetText(KART.L.LC_NOTE_LABEL_SHORT)
            row.noteLabel:SetTextColor(0.6, 0.6, 0.6)
            table.insert(KART.DynamicLabels, row.noteLabel)

            row.noteBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
            row.noteBox:SetAutoFocus(false)
            row.noteBox:SetMaxLetters(80)
            row.noteBox:SetFontObject("GameFontHighlightSmall")
            row.noteBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.noteBox:SetBackdropColor(0, 0, 0, 0.5)
            row.noteBox:SetTextInsets(6, 6, 0, 0)
            row.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            table.insert(KART.EditBoxes, row.noteBox)

            f.rows[i] = row
        end

        local thisRowH = (shrinkVoted and LC.votedByMe[rollID]) and votedRowH or rowH
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

        local voted    = LC.votedByMe[rollID]
        local votedDef = voted and buttons[tonumber(voted)]
        -- A stored vote index with no matching button (the leader shrank the label set after we
        -- voted) reads as unvoted, so the vote buttons come back instead of an empty badge.
        local hasVote  = votedDef ~= nil
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

        if not voted then
            for bi, def in ipairs(buttons) do
                local col = (bi - 1) % cols
                local brow = math.floor((bi - 1) / cols)

                local btn = row.voteButtons[bi]
                if not btn then
                    btn = KART.CreateModernButton(row.btnArea, def.label)
                    btn.grad = KART.CreateGradientOverlay(btn)
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
                KART.SetGradientOverlayColor(btn.grad, def.r, def.g, def.b, 0.22)
                btn.iconTex:SetTexture(LC.GetVoteIconTexture(bi))

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

    local visibleRolls = Vote.GetVisibleRolls()
    for i, rollID in ipairs(visibleRolls) do
        local row = f.compactRows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.scrollChild, "BackdropTemplate")
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
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
            row.itemHover:SetPoint("BOTTOMRIGHT", row.itemText, "BOTTOMRIGHT")
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
            row.votedBadge:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

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
            row.noteBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.noteBox:SetBackdropColor(0, 0, 0, 0.85)
            row.noteBox:SetTextInsets(6, 6, 0, 0)
            row.noteBox:SetPoint("LEFT", row.notePencil, "RIGHT", 6, 0)
            row.noteBox:SetPoint("RIGHT", row.chipArea, "RIGHT", 0, 0)
            row.noteBox:Hide()
            row.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
            table.insert(KART.EditBoxes, row.noteBox)

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
        -- voted) reads as unvoted, so the vote chips come back instead of an empty badge.
        local hasVote  = votedDef ~= nil
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

        if not voted then
            for bi, def in ipairs(buttons) do
                local btn = row.chipButtons[bi]
                if not btn then
                    btn = CreateFrame("Button", nil, row.chipArea, "BackdropTemplate")
                    btn:SetSize(CHIP, CHIP)
                    btn:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
                    -- Base fill, same as every other backdrop frame in this file (e.g. the row
                    -- backdrops above, or KART.CreateModernButton's own vote buttons) — without
                    -- this the chip has no set background color, only the category-tinted border
                    -- set below, which at 24px is easy to mistake for "no button here at all".
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                    btn.grad = KART.CreateGradientOverlay(btn)
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
                KART.SetGradientOverlayColor(btn.grad, def.r, def.g, def.b, 0.22)
                btn.iconTex:SetTexture(LC.GetVoteIconTexture(bi))

                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(def.label, def.r, def.g, def.b)
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
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    local retracting = (LC.councilVotes[rollID][myKey] == candidateKey)
    LC.councilVotes[rollID][myKey] = (not retracting) and candidateKey or nil

    if not LC.IsTestRoll(rollID) then
        LC.SendLC("LC_CVOTE:" .. rollID .. ":" .. (retracting and "" or candidateKey))
    end

    KART.LC.Council.RefreshCouncilRows()
end

function Vote.HandleVote(payload, senderKey)
    -- Reject votes from anyone not actually in our group (CHAT_MSG_ADDON also delivers whispers) —
    -- otherwise a stranger's whisper lands in LC.votes and inflates the voted-count badge.
    if not (senderKey and KART.Identity.FindUnitForKey(senderKey)) then return end
    -- payload = "rollID:buttonIndex:note"
    local rollID, idx = payload:match("^(%d+):(%d+)")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end
    -- Ignore votes for a roll we're no longer tracking (already resolved/pruned): a late straggler
    -- would otherwise re-create LC.votes[rollID] as an orphan that no cleanup path ever frees. Every
    -- peer processes LC_START (which sets rollItems) before any vote can be cast, so a legitimate
    -- vote never arrives before this is set.
    if not LC.rollItems[rollID] then return end

    local note = payload:match("^%d+:%d+:(.*)") or ""

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderKey] = {idx = idx, note = note}

    -- Row list only matters for whichever roll is the active tab; the vote-count badge on every
    -- tab (including inactive ones) stays live regardless — see LC.RefreshCouncilIfShown.
    LC.RefreshCouncilIfShown(rollID)
end

-- Receives another raider's automatic 1-100 roll (see LC.OnStartLootRoll) — opt-in, analogous to
-- RCLootCouncil's Need roll. Purely informational, shown as its own column; never used to decide
-- anything automatically.
function Vote.HandleRoll(payload, senderKey)
    if not (senderKey and KART.Identity.FindUnitForKey(senderKey)) then return end
    local rollID, value = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    value  = tonumber(value)
    if not rollID or not value then return end
    -- Deliberately NOT gated on LC.rollItems[rollID] the way HandleVote/HandleCouncilVote are: a
    -- roll is auto-broadcast from START_LOOT_ROLL, so it can legitimately arrive before this client
    -- knows the roll exists (a client that gets no local START_LOOT_ROLL learns it only from
    -- LC_START, and other raiders broadcast their rolls at the same instant the leader does). Rolls
    -- are sent exactly once with no retry, so dropping one loses it permanently. Any orphan left by
    -- a roll that never materializes is swept by LC.ClearAllRolls at session end.
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
    if not (senderKey and KART.Identity.FindUnitForKey(senderKey)) then return end
    local rollID, candidateKey = payload:match("^(%d+):(.*)$")
    rollID = tonumber(rollID)
    if not rollID then return end
    -- Ignore council votes for an untracked (already resolved/pruned) roll — see HandleVote:
    -- prevents an orphan LC.councilVotes[rollID] that no cleanup path frees.
    if not LC.rollItems[rollID] then return end

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
