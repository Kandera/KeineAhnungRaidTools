local addonName, KART = ...

KART.LC.Council = KART.LC.Council or {}
local Council = KART.LC.Council
local LC = KART.LC

-- =====================================================================
--  Equipped-item helper for council panel
-- =====================================================================

local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD           = {1},
    INVTYPE_NECK           = {2},
    INVTYPE_SHOULDER       = {3},
    INVTYPE_CHEST          = {5},
    INVTYPE_ROBE           = {5},
    INVTYPE_WAIST          = {6},
    INVTYPE_LEGS           = {7},
    INVTYPE_FEET           = {8},
    INVTYPE_WRIST          = {9},
    INVTYPE_HAND           = {10},
    INVTYPE_FINGER         = {11, 12},
    INVTYPE_TRINKET        = {13, 14},
    INVTYPE_CLOAK          = {15},
    INVTYPE_WEAPON         = {16},
    INVTYPE_2HWEAPON       = {16},
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND  = {17},
    INVTYPE_SHIELD         = {17},
    INVTYPE_HOLDABLE       = {17},
    INVTYPE_RANGED         = {18},
    INVTYPE_RANGEDRIGHT    = {18},
}

-- Returns (equippedLink, equippedIlvl) for the slot matching rollItemLink on unit.
-- For two-slot items (rings, trinkets) returns the lower-ilvl piece (most likely to be replaced).
function Council.GetEquippedForUnit(unit, rollItemLink)
    if not unit or not rollItemLink then return nil, nil end
    -- C_Item.GetItemInfo returns a list of separate values, not a table — grabbing only the
    -- first one (itemName, a string) and then indexing it with ["equipLoc"]/["itemLevel"]
    -- silently returned nil every time (string indexing just falls through to nil), so this
    -- comparison never found a matching slot for ANY item, test or real.
    local itemName, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(rollItemLink)
    if not itemName then return nil, nil end
    local slots = EQUIP_LOC_TO_SLOT[itemEquipLoc]
    if not slots then return nil, nil end

    local bestLink, bestIlvl
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, _, _, ilvl = C_Item.GetItemInfo(link)
            if ilvl and (not bestIlvl or ilvl < bestIlvl) then
                bestLink  = link
                bestIlvl  = ilvl
            end
        end
    end
    return bestLink, bestIlvl
end

-- =====================================================================
--  Armor-type eligibility  (soft visual hint only — never blocks assignment)
-- =====================================================================
-- WoW's armor proficiency is cumulative (a plate class can also wear mail/leather/cloth), so
-- eligibility for an item of a given type only needs proficiency >= that type's rank.
local ARMOR_RANK = {CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4}
local CLASS_MAX_ARMOR = {
    MAGE = "CLOTH", PRIEST = "CLOTH", WARLOCK = "CLOTH",
    DRUID = "LEATHER", ROGUE = "LEATHER", MONK = "LEATHER", DEMONHUNTER = "LEATHER",
    HUNTER = "MAIL", SHAMAN = "MAIL", EVOKER = "MAIL",
    WARRIOR = "PLATE", PALADIN = "PLATE", DEATHKNIGHT = "PLATE",
}
-- Blizzard's armor-subclass IDs already run Cloth=1..Plate=4; kept as an explicit lookup rather
-- than relied upon directly so a future API change can't silently break this. Anything not
-- listed (0=Miscellaneous — rings/necks/cloaks/trinkets, or 6=Shield) has no weight restriction.
local ARMOR_SUBCLASS_RANK = {[1] = 1, [2] = 2, [3] = 3, [4] = 4}

-- Returns the item's armor rank (1-4) if it's a cloth/leather/mail/plate piece, else nil (no
-- restriction — jewelry, weapons, shields etc. are never flagged as "ineligible").
function Council.GetItemArmorRank(itemLink)
    if not LC.IsRealItemLink(itemLink) then return nil end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)
    if classID ~= 4 then return nil end -- 4 = Armor
    return ARMOR_SUBCLASS_RANK[subclassID]
end

-- Returns false (ineligible) only when we're SURE the class can't equip this armor type; true
-- for everything else, including when either side of the check is unknown — this is a visual
-- hint, not a hard filter, so it must never hide someone who might actually be eligible.
function Council.IsArmorEligible(classFile, itemRank)
    if not itemRank or not classFile then return true end
    local maxType = CLASS_MAX_ARMOR[classFile]
    if not maxType then return true end
    return ARMOR_RANK[maxType] >= itemRank
end

-- =====================================================================
--  Council Panel  (shown to leader & assistants)
-- =====================================================================
-- Every currently active roll gets its own tab on the left edge of the panel instead of hiding
-- behind whichever roll happened to start last — clicking a tab switches the row list to that
-- item, so the council can freely compare and decide across everything currently on the table
-- (e.g. someone might prefer a different item once they see what else dropped).

-- Registers rollID as an active roll and (re)shows the panel. If nothing is currently being
-- reviewed, switches straight to it; otherwise just adds its tab without yanking the panel away
-- from whatever the council is currently looking at (the new tab gets a "new" marker instead).
function Council.ShowCouncilPanel(rollID, seconds)
    if not LC.councilPanel then Council.CreateCouncilPanel() end
    local panel = LC.councilPanel

    LC.rollDeadlines[rollID] = GetTime() + (seconds or 20)
    LC.rollDurations[rollID] = seconds or 20

    local alreadyTabbed = false
    for _, rid in ipairs(LC.councilTabs) do
        if rid == rollID then alreadyTabbed = true break end
    end
    if not alreadyTabbed then
        table.insert(LC.councilTabs, rollID)
        if LC.activeRollID and LC.activeRollID ~= rollID then
            LC.councilTabsNew[rollID] = true
        end
        -- A genuinely new item dropped while the panel was minimized — expand it back so it
        -- can't be missed, rather than leaving council members to notice the tab count on their
        -- own. Re-votes/re-shows of an already-tabbed roll never trigger this.
        if panel.isMinimized then
            Council.SetCouncilPanelMinimized(false)
        end
    end

    if not LC.activeRollID then
        Council.SwitchCouncilTab(rollID)
    else
        Council.RefreshCouncilTabs()
    end

    panel:Show()
end

-- Switches the panel's row list over to rollID and clears its "new" marker.
function Council.SwitchCouncilTab(rollID)
    local panel = LC.councilPanel
    if not panel then return end

    LC.activeRollID = rollID
    LC.councilTabsNew[rollID] = nil
    panel.itemText:SetText((LC.rollItems[rollID] or "???") .. LC.Trade.GetDuplicateOrdinal(rollID))
    panel.title:SetText(KART.L.LC_PANEL_TITLE)

    local link = LC.rollItems[rollID]
    local ir, ig, ib = LC.ParseItemColor(link)
    local iconTexture = LC.IsRealItemLink(link) and C_Item.GetItemIconByID(link)
    if iconTexture then
        panel.itemIcon:SetTexture(iconTexture)
        panel.itemIcon:SetVertexColor(1, 1, 1)
    else
        panel.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        panel.itemIcon:SetVertexColor(ir, ig, ib)
    end
    panel.itemIconBorder:SetVertexColor(ir, ig, ib)
    local deadline = LC.rollDeadlines[rollID]
    if deadline then
        panel.itemCD:SetCooldown(GetTime(), math.max(deadline - GetTime(), 0))
    end

    Council.RefreshCouncilRows()
    Council.RefreshCouncilTabs()
end

-- Removes rollID's tab (e.g. "No Winner", or manually dismissed via the tab's own "x"). Switches
-- to another remaining tab if there is one, otherwise hides the whole panel.
function Council.CloseCouncilTab(rollID)
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    LC.Trade.ClearRollState(rollID)

    if LC.activeRollID == rollID then
        if LC.councilTabs[1] then
            Council.SwitchCouncilTab(LC.councilTabs[1])
        else
            LC.activeRollID = nil
            if LC.councilPanel then LC.councilPanel:Hide() end
        end
    else
        Council.RefreshCouncilTabs()
    end
end

-- Rebuilds the vertical tab strip on the left edge of the panel from LC.councilTabs. Each tab
-- shows the item's actual icon (real items) or a colour-tinted placeholder (test items), plus a
-- voted/total badge; hovering one previews the full per-player vote breakdown without switching
-- to it. Its "x" only appears on hover — it used to sit flush in the corner at all times, which
-- made it very easy to close a tab by accident while just trying to click it to switch.
function Council.RefreshCouncilTabs()
    local panel = LC.councilPanel
    if not panel then return end

    for i, rollID in ipairs(LC.councilTabs) do
        local tab = panel.tabs[i]
        if not tab then
            tab = CreateFrame("Button", nil, panel.tabStrip, "BackdropTemplate")
            tab:SetSize(40, 40)
            tab:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2})
            tab:SetBackdropColor(0.15, 0.15, 0.15, 0.9)

            -- Accent frame behind the active tab only — same crisp-border-instead-of-blur
            -- approximation used on the vote-popup item icon (see row.itemIconBorder).
            tab.activeGlow = tab:CreateTexture(nil, "BACKGROUND")
            tab.activeGlow:SetColorTexture(1, 0.85, 0.2, 0.55)
            tab.activeGlow:SetPoint("TOPLEFT", -3, 3)
            tab.activeGlow:SetPoint("BOTTOMRIGHT", 3, -3)
            tab.activeGlow:Hide()

            tab.icon = tab:CreateTexture(nil, "ARTWORK")
            tab.icon:SetPoint("TOPLEFT", 3, -3)
            tab.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            tab.countBG = tab:CreateTexture(nil, "OVERLAY")
            tab.countBG:SetColorTexture(0, 0, 0, 0.6)
            tab.countBG:SetPoint("BOTTOMLEFT", 3, 3)
            tab.countBG:SetPoint("BOTTOMRIGHT", -3, 3)
            tab.countBG:SetHeight(12)

            tab.countText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tab.countText:SetPoint("CENTER", tab.countBG, "CENTER", 0, 0)

            tab.newDot = tab:CreateTexture(nil, "OVERLAY")
            tab.newDot:SetSize(8, 8)
            tab.newDot:SetPoint("TOPRIGHT", -2, -2)
            tab.newDot:SetColorTexture(1, 0.2, 0.2, 1)

            -- Hidden until the tab itself is hovered (see OnEnter/OnLeave below) so a normal
            -- click anywhere on the tab can never land on it by accident.
            tab.closeBtn = CreateFrame("Button", nil, tab)
            tab.closeBtn:SetSize(14, 14)
            tab.closeBtn:SetPoint("TOPRIGHT", -1, -1)
            tab.closeBtn:Hide()
            tab.closeBtn.bg = tab.closeBtn:CreateTexture(nil, "BACKGROUND")
            tab.closeBtn.bg:SetAllPoints()
            tab.closeBtn.bg:SetColorTexture(0, 0, 0, 0.7)
            tab.closeBtn.text = tab.closeBtn:CreateFontString(nil, "OVERLAY")
            tab.closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            tab.closeBtn.text:SetPoint("CENTER")
            tab.closeBtn.text:SetText("|cffff6666×|r")

            panel.tabs[i] = tab
        end

        tab:ClearAllPoints()
        tab:SetPoint("TOP", panel.tabStrip, "TOP", 0, -(i - 1) * 44)

        local link = LC.rollItems[rollID]
        local r, g, b = LC.ParseItemColor(link)
        if rollID == LC.activeRollID then
            tab:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            tab.activeGlow:Show()
        else
            tab:SetBackdropBorderColor(r, g, b, 0.9)
            tab.activeGlow:Hide()
        end

        -- Real items show their actual icon; test mode has no real item to fetch an icon for,
        -- so it gets a generic placeholder tinted with the item's own colour instead.
        local iconTexture = LC.IsRealItemLink(link) and C_Item.GetItemIconByID(link)
        if iconTexture then
            tab.icon:SetTexture(iconTexture)
            tab.icon:SetVertexColor(1, 1, 1)
        else
            tab.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            tab.icon:SetVertexColor(r, g, b)
        end

        local voted, total = LC.CountVotes(rollID)
        tab.countText:SetText(voted .. "/" .. total)
        tab.newDot:SetShown(LC.councilTabsNew[rollID] == true)

        local capturedRollID = rollID
        tab:SetScript("OnClick", function() Council.SwitchCouncilTab(capturedRollID) end)
        tab.closeBtn:SetScript("OnClick", function() Council.CloseCouncilTab(capturedRollID) end)
        tab:SetScript("OnEnter", function(self)
            tab.closeBtn:Show()

            local hoverLink = LC.rollItems[capturedRollID]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if LC.IsRealItemLink(hoverLink) then
                GameTooltip:SetHyperlink(hoverLink)
                GameTooltip:AddLine(" ")
                -- SetHyperlink auto-triggers Blizzard's own gear-comparison tooltip (comparing
                -- against the *viewer's* equipped item) — not wanted on the tab strip, this is
                -- just "which item is this tab", not a personal upgrade check.
                if ShoppingTooltip1 then ShoppingTooltip1:Hide() end ---@diagnostic disable-line: undefined-global
                if ShoppingTooltip2 then ShoppingTooltip2:Hide() end ---@diagnostic disable-line: undefined-global
            else
                GameTooltip:SetText(hoverLink or "???", 1, 1, 1)
            end
            -- Full vote breakdown so the council can compare items without switching tabs.
            local buttons  = LC.GetButtonConfig()
            local anyVotes = false
            for key, voteData in pairs(LC.votes[capturedRollID] or {}) do
                anyVotes = true
                local idx = voteData.idx
                local def = idx and buttons[tonumber(idx)]
                GameTooltip:AddDoubleLine(KART.Identity.ResolveDisplayName(key), def and def.label or "?", 0.9, 0.9, 0.9, def and def.r or 0.6, def and def.g or 0.6, def and def.b or 0.6)
            end
            if not anyVotes then
                GameTooltip:AddLine(KART.L.LC_TAB_NO_VOTES_YET, 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function()
            -- The close button sits on top of the tab, so moving the mouse onto it also fires
            -- the tab's OnLeave (WoW's mouse-focus is topmost-frame-only, not parent-aware). If we
            -- unconditionally hid closeBtn here, that hide would immediately re-trigger tab's
            -- OnEnter next frame, which re-shows it, which re-triggers OnLeave — an infinite
            -- show/hide flicker that also ate every click before it could register. Only hide it
            -- once the mouse has actually left both the tab and the button itself.
            if not tab.closeBtn:IsMouseOver() then
                tab.closeBtn:Hide()
            end
            GameTooltip:Hide()
        end)
        tab.closeBtn:SetScript("OnEnter", function()
            -- Tooltip covers the item preview, not "you're about to close this" info, so hide it
            -- while over the close button instead of letting it fight for space with the button.
            GameTooltip:Hide()
        end)
        tab.closeBtn:SetScript("OnLeave", function()
            if not tab:IsMouseOver() then
                tab.closeBtn:Hide()
            end
        end)
        tab:Show()
    end

    for i = #LC.councilTabs + 1, #panel.tabs do
        if panel.tabs[i] then panel.tabs[i]:Hide() end
    end
    panel.tabStrip:SetShown(#LC.councilTabs > 0)

    LC.ApplyFontSize()
end

-- Panel width: wide enough that raider names and vote labels never truncate/wrap even with the
-- class-icon and vote-icon columns added (see RefreshCouncilRows) — a fixed-width table with real
-- names in it will always eventually clip someone, so this errs wide rather than clever-wrapping.
-- +70 over the original 555/520 (panel/scrollChild) for the guild-rank column inserted right
-- after Name (see hRank/row.rankText below) — every column from iLvl rightward is shifted by
-- this same DELTA so all existing gaps between columns stay exactly as they were.
local COUNCIL_PANEL_WIDTH   = 625
local COUNCIL_PANEL_HEIGHT  = 462
local COUNCIL_PANEL_MIN_H   = 68 -- header + item icon/name only, see LC.SetCouncilPanelMinimized

function Council.CreateCouncilPanel()
    local f = CreateFrame("Frame", "KART_LCCouncilPanel", UIParent, "BackdropTemplate")
    f:SetSize(COUNCIL_PANEL_WIDTH, COUNCIL_PANEL_HEIGHT)
    f:SetPoint("CENTER", 220, 0)
    KART.RegisterStrataFrame(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    KART.ApplyPopupArtwork(f)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcCouncilPanelPos = {x = self:GetLeft(), y = self:GetTop()}
        end
    end)
    table.insert(UISpecialFrames, f:GetName())

    -- Vertical tab strip protruding from the left edge — one tab per active roll (see
    -- RefreshCouncilTabs). Lives outside f's own backdrop/width on purpose, like a browser's
    -- side tabs, so it doesn't eat into the row list's already-tight column layout.
    f.tabStrip = CreateFrame("Frame", nil, f)
    f.tabStrip:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, -30)
    f.tabStrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -4, 40)
    f.tabStrip:SetWidth(40)
    f.tabs = {}

    -- Header zone: title on the artwork with an accent line below, matching the main window
    -- (no flat gray bar anymore; hdr survives as an invisible layout strip for title/buttons).
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(26)
    hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT")
    hdr:EnableMouse(true)
    hdr:RegisterForDrag("LeftButton")
    hdr:SetScript("OnDragStart", function() f:StartMoving() end)
    hdr:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if KART_Settings then
            KART_Settings.lcCouncilPanelPos = {x = f:GetLeft(), y = f:GetTop()}
        end
    end)
    KART.CreateHeaderLine(f, -28)

    f.title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", 16, 0)

    -- Anchored to the minimize button once it exists (below) rather than a hardcoded offset from
    -- hdr's right edge — a hardcoded number silently overlapped the "-"/"×" buttons the moment a
    -- longer string (e.g. the "Done" text) or the button layout changed.
    f.timerText = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    -- Only hides the window — the active roll's tab (and all others) stay tracked and reappear
    -- next time the panel is shown; this is a deliberate "get it out of my way for now", not a
    -- "discard" action. Use a tab's own "x" to actually dismiss an item, or the "-" button (below)
    -- to shrink the panel down to just its header instead of hiding it outright.
    local closeBtn = KART.CreateHeaderIconButton(hdr, "×", function() f:Hide() end)
    closeBtn:SetPoint("RIGHT", -4, 0)

    -- Collapses the panel to just its title bar + item name, keeping it out of the way during
    -- normal raiding without losing track of what's being voted on (tabs/rows are hidden, not
    -- discarded — see LC.SetCouncilPanelMinimized). Sits left of the close button, same style.
    local minimizeBtn = KART.CreateHeaderIconButton(hdr, "-", function() Council.SetCouncilPanelMinimized(not f.isMinimized) end)
    minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    f.minimizeBtn = minimizeBtn
    f.timerText:SetPoint("RIGHT", minimizeBtn, "LEFT", -6, 0)

    -- Item display: icon (with quality-tinted accent border + native cooldown-style vote-timer
    -- wipe, same technique as the vote-popup row icon) plus the item name beside it.
    f.itemIconBorder = f:CreateTexture(nil, "BACKGROUND")
    f.itemIconBorder:SetColorTexture(1, 1, 1, 1)

    f.itemIcon = f:CreateTexture(nil, "ARTWORK")
    f.itemIcon:SetSize(30, 30)
    f.itemIcon:SetPoint("TOPLEFT", 10, -34)
    f.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.itemIconBorder:SetPoint("TOPLEFT", f.itemIcon, -2, 2)
    f.itemIconBorder:SetPoint("BOTTOMRIGHT", f.itemIcon, 2, -2)

    f.itemCD = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.itemCD:SetAllPoints(f.itemIcon)
    f.itemCD:SetHideCountdownNumbers(true)
    f.itemCD:SetDrawBling(false)

    f.itemText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemText:SetPoint("LEFT", f.itemIcon, "RIGHT", 8, 8)
    f.itemText:SetWidth(527)
    f.itemText:SetJustifyH("LEFT")
    f.itemText:SetWordWrap(false)

    -- "iLvl" left unlocalized on purpose, same as the hIlvl column header below.
    f.ilvlText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ilvlText:SetPoint("TOPLEFT", f.itemText, "BOTTOMLEFT", 0, -2)
    f.ilvlText:SetTextColor(0.6, 0.6, 0.55)

    -- Slim fill bar showing the vote window's remaining time as a fraction (see LC.rollDurations),
    -- updated alongside f.timerText by the same ticker below.
    f.timeBar = CreateFrame("StatusBar", nil, f)
    f.timeBar:SetPoint("TOPLEFT", 10, -70)
    f.timeBar:SetPoint("TOPRIGHT", -10, -70)
    f.timeBar:SetHeight(4)
    f.timeBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.timeBar:SetStatusBarColor(0.82, 0.65, 0.24, 1)
    f.timeBar:SetMinMaxValues(0, 1)
    f.timeBar:SetValue(1)
    f.timeBarBG = f:CreateTexture(nil, "BACKGROUND")
    f.timeBarBG:SetAllPoints(f.timeBar)
    f.timeBarBG:SetColorTexture(0, 0, 0, 0.6)

    -- FontStrings can't take mouse scripts directly; overlay a hover frame for the tooltip.
    f.itemHover = CreateFrame("Frame", nil, f)
    f.itemHover:SetAllPoints(f.itemText)
    f.itemHover:EnableMouse(true)
    f.itemHover:SetScript("OnEnter", function(self)
        local link = LC.rollItems[LC.activeRollID]
        if not LC.IsRealItemLink(link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    f.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headers
    local hName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Every header below is positioned/sized/justified to exactly match its column's row widget
    -- (see the row.* creation block in RefreshCouncilRows) — row content sits 5px further right
    -- than f's own left edge (the scroll area's own inset), so headers carry the same +5 here.
    hName:SetPoint("TOPLEFT", 11, -80)
    hName:SetWidth(100)
    hName:SetJustifyH("LEFT")
    hName:SetText(KART.L.LC_COL_NAME)
    f.hName = hName

    -- Guild rank, right after Name (see row.rankText) — purely so alts are easier to spot at a
    -- glance among a roster of otherwise-unfamiliar names; blank/"-" for anyone not in a guild.
    local hRank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRank:SetPoint("TOPLEFT", 136, -80)
    hRank:SetWidth(60)
    hRank:SetJustifyH("CENTER")
    hRank:SetText(KART.L.LC_COL_RANK)
    hRank:SetTextColor(0.5, 0.5, 0.5)
    f.hRank = hRank

    local hIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", 206, -80)
    hIlvl:SetWidth(68) -- spans the equip icon + ilvl number (+/- delta) together
    hIlvl:SetJustifyH("CENTER")
    hIlvl:SetText("iLvl")
    hIlvl:SetTextColor(0.5, 0.5, 0.5)
    f.hIlvl = hIlvl

    local hVote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hVote:SetPoint("TOPLEFT", 282, -80)
    hVote:SetWidth(100)
    hVote:SetJustifyH("LEFT")
    hVote:SetText(KART.L.LC_COL_VOTE)
    f.hVote = hVote

    local hRoll = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRoll:SetPoint("TOPLEFT", 400, -80)
    hRoll:SetWidth(34)
    hRoll:SetJustifyH("CENTER")
    hRoll:SetText(KART.L.LC_COL_ROLL)
    hRoll:SetTextColor(0.5, 0.5, 0.5)
    f.hRoll = hRoll -- hidden/shown with the rolls-enabled setting, see RefreshCouncilRows

    local hCouncilVotes = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCouncilVotes:SetPoint("TOPLEFT", 438, -80)
    hCouncilVotes:SetWidth(40)
    hCouncilVotes:SetJustifyH("CENTER")
    hCouncilVotes:SetText("CV") -- "Council Votes" — plain ASCII, see the note in RefreshCouncilRows
    hCouncilVotes:SetTextColor(0.5, 0.5, 0.5)
    f.hCouncilVotes = hCouncilVotes

    -- Droptimizer gain % — sourced from KART_WoWUtilsCache (written by the external KART
    -- Companion app, see Droptimizer.lua), shown/hidden with dtModuleEnabled just like hRoll
    -- is shown/hidden with lcRollsEnabled below.
    local hGain = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hGain:SetPoint("TOPLEFT", 481, -80)
    hGain:SetWidth(44)
    hGain:SetJustifyH("CENTER")
    hGain:SetText(KART.L.DT_COL_GAIN)
    hGain:SetTextColor(0.5, 0.5, 0.5)
    f.hGain = hGain

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.22, 0.22, 0.22, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 5, -91)
    divider:SetPoint("TOPRIGHT", -5, -91)

    -- Scrollable row area
    local scrollBG = CreateFrame("Frame", nil, f)
    scrollBG:SetPoint("TOPLEFT", 5, -94)
    scrollBG:SetPoint("BOTTOMRIGHT", -5, 48)

    local scrollFrame = CreateFrame("ScrollFrame", "KART_LCCouncilScroll", scrollBG, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT"); scrollFrame:SetPoint("BOTTOMRIGHT", -20, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(590, 800)
    scrollFrame:SetScrollChild(scrollChild)

    local thumb = KART.StripScrollbarTextures(scrollFrame)
    if thumb then thumb:SetSize(8, 20) end

    f.scrollChild = scrollChild
    f.rows        = {}

    -- Bottom: No Winner / Close
    local btnNoWinner = KART.CreateModernButton(f, KART.L.LC_BTN_NO_WINNER)
    btnNoWinner:SetSize(150, 28)
    btnNoWinner:SetPoint("BOTTOMLEFT", 10, 10)
    btnNoWinner:SetScript("OnClick", function()
        if LC.activeRollID then
            LC.Trade.AnnounceResult(LC.activeRollID, "NONE")
            Council.CloseCouncilTab(LC.activeRollID)
        end
    end)

    local btnClose = KART.CreateModernButton(f, KART.L.LC_BTN_CANCEL)
    btnClose:SetSize(150, 28)
    btnClose:SetPoint("BOTTOMRIGHT", -10, 10)
    btnClose:SetScript("OnClick", function() f:Hide() end)

    -- Everything below the header + item name — hidden as a group when minimized (see
    -- LC.SetCouncilPanelMinimized). Column headers, the divider, the whole scroll/row area, the
    -- tab strip, and the bottom action buttons all go away; the header bar and item name stay put
    -- so a minimized panel still tells you *something* is waiting on a decision.
    f.collapsible = {
        hName, hIlvl, hVote, hRoll, hCouncilVotes, hGain,
        divider, scrollBG, btnNoWinner, btnClose, f.tabStrip,
        f.timeBar, f.timeBarBG,
    }

    LC.councilPanel = f

    -- Restore saved position
    local pos = KART_Settings and KART_Settings.lcCouncilPanelPos
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    -- Single shared ticker drives the header countdown for whichever roll is currently active —
    -- avoids juggling a per-call ticker across tab switches.
    f.timerTicker = C_Timer.NewTicker(1, function()
        if not f:IsShown() or not LC.activeRollID then return end
        local deadline = LC.rollDeadlines[LC.activeRollID]
        if not deadline then f.timerText:SetText("") return end
        local remaining = math.ceil(deadline - GetTime())
        f.timerText:SetText(remaining > 0 and (remaining .. "s") or KART.L.LC_VOTING_DONE)

        local duration = LC.rollDurations[LC.activeRollID] or 20
        f.timeBar:SetMinMaxValues(0, duration)
        f.timeBar:SetValue(math.max(remaining, 0))
    end)

    -- Dedicated tooltip for the equipped-item icon hover (see RefreshCouncilRows) — deliberately
    -- NOT Blizzard's shared ShoppingTooltip1/2: those are also driven automatically by Blizzard's
    -- own "compare to my own gear" tooltip hook whenever GameTooltip shows an equippable item
    -- (i.e. on every row hover, comparing against the viewer's own gear), which fought with this
    -- addon's actual goal here — comparing a specific raid candidate's equipped item to the
    -- item being rolled. A fully separate frame sidesteps that collision entirely.
    LC.equipCompareTooltip = CreateFrame("GameTooltip", "KART_LCEquipCompareTooltip", UIParent, "GameTooltipTemplate")
end

-- Collapses/restores the council panel to just its header + item name (see f.collapsible, set up
-- in CreateCouncilPanel) — lets council members keep it on screen during normal raiding without
-- the full row list permanently in the way, without losing the panel's position/tracked tabs the
-- way fully hiding it (the "x" button) would feel like.
function Council.SetCouncilPanelMinimized(minimized)
    local f = LC.councilPanel
    if not f then return end
    f.isMinimized = minimized
    for _, widget in ipairs(f.collapsible) do
        widget:SetShown(not minimized)
    end
    f:SetHeight(minimized and COUNCIL_PANEL_MIN_H or COUNCIL_PANEL_HEIGHT)
    if f.minimizeBtn then f.minimizeBtn.text:SetText(minimized and "+" or "-") end
end

-- Freshly-dropped items are frequently not yet cached client-side when the panel first renders,
-- which makes C_Item.GetItemInfo return nil (see GetEquippedForUnit/GetItemArmorRank above) and
-- leaves the equipped-ilvl/armor-eligibility columns blank or wrong for the rest of the roll
-- unless some other event happens to trigger a refresh in the meantime. Kick off an async load
-- once per rollID and re-render when it completes, instead of depending on luck.
LC.pendingItemLoads = LC.pendingItemLoads or {}

function Council.RefreshCouncilRows()
    local panel = LC.councilPanel
    if not panel then return end

    local rollID  = LC.activeRollID
    local votes   = (rollID and LC.votes[rollID]) or {}
    local buttons = LC.GetButtonConfig()
    local numMem  = GetNumGroupMembers()

    local rollItem = LC.rollItems[rollID]
    if rollID and rollItem and LC.IsRealItemLink(rollItem) and not LC.pendingItemLoads[rollID]
       and not C_Item.GetItemInfo(rollItem) then
        LC.pendingItemLoads[rollID] = true
        Item:CreateFromItemLink(rollItem):ContinueOnItemLoad(function()
            LC.pendingItemLoads[rollID] = nil
            if LC.activeRollID == rollID and LC.councilPanel and LC.councilPanel:IsShown() then
                Council.RefreshCouncilRows()
            end
        end)
    end
    local itemArmorRank = Council.GetItemArmorRank(rollItem)

    local rollsEnabled = LC.GetRollsEnabled()
    local dtEnabled = KART_Settings.dtModuleEnabled ~= false
    if panel.hRoll then panel.hRoll:SetShown(rollsEnabled) end
    if panel.hGain then panel.hGain:SetShown(dtEnabled) end

    -- Rolled item's own ilvl, purely to show a +/- delta next to each candidate's equipped ilvl
    -- (see the equippedText update below) — nil until the item link is cached, same as everywhere
    -- else in this function that reads C_Item.GetItemInfo.
    local rollItemIlvl
    if rollItem and LC.IsRealItemLink(rollItem) then
        local _, _, _, ilvl = C_Item.GetItemInfo(rollItem)
        rollItemIlvl = ilvl
    end
    if panel.ilvlText then
        panel.ilvlText:SetText(rollItemIlvl and ("Item Level " .. rollItemIlvl) or "")
    end

    local members = {}
    for unit in KART.EachGroupUnit() do
        local fullName = UnitName(unit)
        if fullName then
            local short    = fullName:match("([^%-]+)")
            local key      = (KART.Identity.ResolvePlayer(unit))
            local voteData = votes[key] -- always {idx, note} — every writer produces tables
            local voteIdx  = voteData and voteData.idx
            local voteNote = (voteData and voteData.note) or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = Council.GetEquippedForUnit(unit, rollItem)

            -- Flag raiders who are missing KART, running an outdated version, or have disabled
            -- their own Loot Council module locally (self excluded — we never receive our own
            -- version broadcast, so PlayerVersions never has an entry for "player"). PlayerVersions
            -- stays short-name keyed — out of scope for the identity rework, see the design doc.
            local kartStatus
            if unit ~= "player" then
                local ver = KART.PlayerVersions and KART.PlayerVersions[short]
                local lcEnabled = KART.PlayerLCEnabled and KART.PlayerLCEnabled[short]
                if not ver then
                    kartStatus = KART.L.LC_STATUS_NO_KART
                elseif ver ~= KART.Version then
                    kartStatus = string.format(KART.L.LC_STATUS_OLD_VERSION, ver)
                elseif lcEnabled == false then
                    kartStatus = KART.L.LC_STATUS_MODULE_DISABLED
                end
            end

            table.insert(members, {
                short = short, unit = unit, key = key,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = kartStatus,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][key],
                -- Nickname (see KART.GetNickname/lcShowNickNames) and guild rank are both purely
                -- display concerns, resolved once per refresh here rather than per-row-render.
                -- Second return value is the nickname in its original casing — the first
                -- (lowercased) is only for matching, never what should show up on screen.
                nickname = select(2, KART.GetNickname(unit)),
                guildRank = select(2, GetGuildInfo(unit)),
            })
        end
    end

    -- Test rolls must work with zero group members too (testing fully solo, no party at all),
    -- where the loop above never runs. Add ourselves manually so there's always at least one
    -- row to vote on and assign to.
    if LC.IsTestRoll(rollID) then
        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
        local myKey    = (KART.Identity.ResolvePlayer("player"))
        local alreadyListed = false
        for _, m in ipairs(members) do
            if m.short == myShort then alreadyListed = true break end
        end
        if not alreadyListed and myShort ~= "" then
            local voteData = votes[myKey] -- always {idx, note} — every writer produces tables
            local voteIdx  = voteData and voteData.idx
            local voteNote = (voteData and voteData.note) or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = Council.GetEquippedForUnit("player", rollItem)
            table.insert(members, {
                short = myShort, unit = "player", key = myKey,
                voteIdx = voteIdx, voteNote = voteNote, voteDef = voteDef,
                equippedLink = equippedLink, equippedIlvl = equippedIlvl,
                kartStatus = nil,
                rollValue = rollID and LC.rolls[rollID] and LC.rolls[rollID][myKey],
                nickname = select(2, KART.GetNickname("player")),
                guildRank = select(2, GetGuildInfo("player")),
            })
        end
    end

    -- Sort: voted rows first, sorted by button index ascending; unvoted last; alpha within group
    table.sort(members, function(a, b)
        if a.voteIdx ~= b.voteIdx then
            if a.voteIdx == nil then return false end
            if b.voteIdx == nil then return true end
            return tonumber(a.voteIdx) < tonumber(b.voteIdx)
        end
        return (a.short or "") < (b.short or "")
    end)

    for i, m in ipairs(members) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel.scrollChild, "BackdropTemplate")
            row:SetHeight(24)
            -- Left-click is intentionally inert; right-click opens the assign menu.
            row:RegisterForClicks("RightButtonUp")
            row:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})

            -- Round class icon (see SetClassIconTexture) so class reads at a glance without
            -- parsing the class-coloured name text next to it.
            row.classIcon = row:CreateTexture(nil, "ARTWORK")
            row.classIcon:SetSize(14, 14)
            row.classIcon:SetPoint("LEFT", 6, 0)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row.classIcon, "RIGHT", 3, 0)
            row.nameText:SetWidth(100)
            row.nameText:SetJustifyH("LEFT")

            -- Guild rank (see hRank/m.guildRank) — dim like the other secondary-info columns,
            -- "-" when the candidate isn't in a guild at all.
            row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.rankText:SetPoint("LEFT", 136, 0)
            row.rankText:SetWidth(60)
            row.rankText:SetJustifyH("CENTER")

            -- Icon of the item currently equipped in the matching slot
            row.equipIcon = row:CreateTexture(nil, "ARTWORK")
            row.equipIcon:SetSize(18, 18)
            row.equipIcon:SetPoint("LEFT", 201, 0)
            row.equipIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Textures can't take OnEnter/OnLeave themselves, so this invisible frame sits over
            -- the icon purely to scope the equipped-item comparison tooltip (ShoppingTooltip1,
            -- see below) to just the icon — it used to show for the whole row, which made it
            -- pop up on almost any mouse movement over a row.
            row.equipHitbox = CreateFrame("Frame", nil, row)
            row.equipHitbox:SetAllPoints(row.equipIcon)
            row.equipHitbox:EnableMouse(true)

            -- Equipped item level in the matching slot
            row.equippedText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.equippedText:SetPoint("LEFT", 223, 0)
            row.equippedText:SetWidth(46)
            row.equippedText:SetJustifyH("CENTER")

            -- Same vote-category icon used on the vote-popup buttons (see VOTE_ICON_TEXTURES),
            -- so a vote reads as an icon+colour tag instead of colour-coded text alone.
            row.voteIcon = row:CreateTexture(nil, "ARTWORK")
            row.voteIcon:SetSize(12, 12)
            row.voteIcon:SetPoint("LEFT", 277, 0)

            row.voteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.voteText:SetPoint("LEFT", row.voteIcon, "RIGHT", 3, 0)
            row.voteText:SetWidth(95)
            row.voteText:SetJustifyH("LEFT")

            -- Opt-in 1-100 roll (see lcRollsEnabled); hidden entirely when the raid has it off.
            row.rollText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.rollText:SetPoint("LEFT", 395, 0)
            row.rollText:SetWidth(34)
            row.rollText:SetJustifyH("CENTER")

            -- Council straw-poll: click to vote for this candidate (toggles), shows a running
            -- tally of how many council members picked them. Purely informational — see
            -- LC.Vote.ToggleCouncilVote. Every viewer of this panel is themselves a council member
            -- (the panel is only ever shown to council — see IsCouncil in HandleStart), so the
            -- button is always available, not gated behind any extra role check.
            row.councilVoteBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            row.councilVoteBtn:SetSize(40, 18)
            row.councilVoteBtn:SetPoint("LEFT", 433, 0)
            row.councilVoteBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            row.councilVoteBtn:SetBackdropColor(0, 0, 0, 0.4)

            -- Fill proportional to pollCount/numMem, so the tally reads as a bar at a glance
            -- instead of requiring the number to be read every time (see the update below).
            row.councilVoteBtn.fill = row.councilVoteBtn:CreateTexture(nil, "ARTWORK")
            row.councilVoteBtn.fill:SetColorTexture(1, 0.85, 0.2, 1)
            row.councilVoteBtn.fill:SetPoint("TOPLEFT", 1, -1)
            row.councilVoteBtn.fill:SetPoint("BOTTOMLEFT", 1, 1)

            row.councilVoteBtn.text = row.councilVoteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.councilVoteBtn.text:SetPoint("CENTER")

            -- Small dot shown when raider left a note
            row.noteIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.noteIcon:SetPoint("RIGHT", -4, 0)
            row.noteIcon:SetWidth(16)
            row.noteIcon:SetJustifyH("CENTER")

            -- FontStrings can't take mouse scripts directly (see row.itemHover elsewhere) — this
            -- is the note's own dedicated tooltip, separate from the equip-icon one, so the note
            -- text only shows up when someone actually hovers the note dot itself.
            -- Sized explicitly rather than SetAllPoints(row.noteIcon): the icon is a FontString
            -- that shows nothing but "" when there's no note, and an unset/auto height on empty
            -- text collapses towards 0 — which would leave no real hit target to hover even once
            -- a note exists (SetAllPoints is a live constraint, so it inherits that collapse). A
            -- fixed, generous size sidesteps that and is also just easier to actually hit.
            row.noteHitbox = CreateFrame("Frame", nil, row)
            row.noteHitbox:SetSize(18, 18)
            row.noteHitbox:SetPoint("CENTER", row.noteIcon)
            row.noteHitbox:EnableMouse(true)

            -- Warning shown when the raider is missing KART, outdated, or has LC disabled locally
            row.warnIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.warnIcon:SetPoint("RIGHT", row.noteIcon, "LEFT", -2, 0)
            row.warnIcon:SetWidth(14)
            row.warnIcon:SetJustifyH("CENTER")

            -- Persistent officer note about this player (see LC.SetOfficerNote) — a different
            -- colour from the per-vote note dot so the two aren't mistaken for one another.
            row.officerNoteIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.officerNoteIcon:SetPoint("RIGHT", row.warnIcon, "LEFT", -2, 0)
            row.officerNoteIcon:SetWidth(14)
            row.officerNoteIcon:SetJustifyH("CENTER")

            row.officerNoteHitbox = CreateFrame("Frame", nil, row)
            row.officerNoteHitbox:SetAllPoints(row.officerNoteIcon)
            row.officerNoteHitbox:EnableMouse(true)

            -- Droptimizer gain % for the item currently being rolled — see Droptimizer.lua
            -- (KART.DT.GetGainPercent). Sits in the space opened up by the wider panel/scrollChild
            -- between councilVoteBtn and the right-anchored note/warn/officerNote icons.
            row.gainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.gainText:SetPoint("LEFT", 481, 0)
            row.gainText:SetWidth(44)
            row.gainText:SetJustifyH("CENTER")

            panel.rows[i] = row
        end

        local rowIdx              = i
        -- Scoped per-roll (not a single global "last winner") — otherwise assigning item A to a
        -- player and then switching to item B's tab would keep that player highlighted green
        -- there too, even though they never won item B.
        local isWinner            = (rollID ~= nil and m.key == LC.assignedWinners[rollID])
        local capturedShort       = m.short
        local capturedKey         = m.key
        local capturedRoll        = rollID
        local capturedNote        = m.voteNote or ""
        local capturedEquipLink   = m.equippedLink
        local capturedEquipIlvl   = m.equippedIlvl
        local capturedVoteDef     = m.voteDef
        local capturedKartStatus  = m.kartStatus
        local capturedOfficerNote = m.key and KART_LCOfficerNotes[m.key]
        local capturedGainPct, capturedGainSource
        if KART.DT and KART.DT.GetGainPercent and m.short then
            -- Droptimizer's own cache is short-name-text keyed (imported from an external report,
            -- no GUID concept) — deliberately still m.short here, not m.key. See design doc.
            capturedGainPct, capturedGainSource = KART.DT.GetGainPercent(m.short, rollItem)
        end

        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(rowIdx - 1) * 26)
        row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", 0, 0)
        row.memberKey = m.key

        -- Winner gets a gold highlight (not green — green is already the "Upgrade" vote colour,
        -- see BUTTON_COLORS/VOTE_ICON_TEXTURES, and a row could easily be both at once); others
        -- get alternating grey.
        if isWinner then
            row:SetBackdropColor(0.28, 0.21, 0.03, 0.85)
            row:SetBackdropBorderColor(1, 0.85, 0.2, 1)
        else
            row:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
            row:SetBackdropBorderColor(0, 0, 0, 1)
        end

        -- Class colour for name
        local nr, ng, nb = 0.8, 0.8, 0.8
        local classFile
        if m.unit then
            local _, cf = UnitClass(m.unit)
            classFile = cf
            if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                nr = RAID_CLASS_COLORS[classFile].r
                ng = RAID_CLASS_COLORS[classFile].g
                nb = RAID_CLASS_COLORS[classFile].b
            end
        end
        LC.SetClassIconTexture(row.classIcon, classFile)

        -- Armor-type eligibility is a soft visual hint, never a hard block (right-click assign
        -- still works either way) — dims the row and greys the name so obviously-wrong
        -- candidates (e.g. a plate item on a cloth wearer) stand out less among real contenders.
        local armorIneligible = not Council.IsArmorEligible(classFile, itemArmorRank)
        local capturedArmorIneligible = armorIneligible
        if armorIneligible then
            nr, ng, nb = nr * 0.5, ng * 0.5, nb * 0.5
        end

        -- lcShowNickNames is a personal display preference (see CbShowNickNames) — falls back to
        -- the character short name whenever no nickname is available, so the toggle is always
        -- safe to leave on even for raiders without NSRT or without a nickname set.
        local displayName = (KART_Settings.lcShowNickNames and m.nickname) or m.short or "?"
        row.nameText:SetText(displayName)
        row.nameText:SetTextColor(nr, ng, nb)

        row.rankText:SetText(m.guildRank or "-")
        row.rankText:SetTextColor(0.55, 0.55, 0.55)

        -- Equipped item icon + ilvl column
        if capturedEquipLink then
            local icon = C_Item.GetItemIconByID(capturedEquipLink)
            row.equipIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.equipIcon:Show()
        else
            row.equipIcon:Hide()
        end
        if capturedEquipIlvl then
            -- +/- delta vs the rolled item's own ilvl, so an upgrade/downgrade reads at a glance
            -- without mentally subtracting two numbers per row.
            local deltaStr = ""
            if rollItemIlvl then
                local diff = rollItemIlvl - capturedEquipIlvl
                if diff > 0 then
                    deltaStr = " |cff40c040+" .. diff .. "|r"
                elseif diff < 0 then
                    deltaStr = " |cffc04040" .. diff .. "|r"
                end
            end
            row.equippedText:SetText("|cff888888" .. capturedEquipIlvl .. "|r" .. deltaStr)
        else
            row.equippedText:SetText("|cff444444—|r")
        end

        -- Droptimizer gain % column — entirely hidden when the module is off, matching the
        -- rollText pattern below.
        row.gainText:SetShown(dtEnabled)
        if dtEnabled then
            if capturedGainPct then
                local color = capturedGainPct >= 0 and "|cff40c040" or "|cffc04040"
                row.gainText:SetText(string.format("%s%+.1f%%|r", color, capturedGainPct))
            else
                row.gainText:SetText("|cff444444—|r")
            end
        end

        -- Vote column
        if m.voteDef then
            row.voteText:SetText(string.format("|cff%02x%02x%02x%s|r",
                math.floor(m.voteDef.r * 255),
                math.floor(m.voteDef.g * 255),
                math.floor(m.voteDef.b * 255),
                m.voteDef.label))
            row.voteIcon:SetTexture(LC.GetVoteIconTexture(tonumber(m.voteIdx)))
            row.voteIcon:Show()
        else
            row.voteText:SetText("|cff666666-|r")
            row.voteIcon:Hide()
        end

        -- Opt-in 1-100 roll column — entirely hidden (not just blank) when the raid leader has
        -- rolls turned off, both to save space and to avoid implying a feature that isn't active.
        row.rollText:SetShown(rollsEnabled)
        if rollsEnabled then
            if m.rollValue then
                -- A hot roll (>=85) gets a brighter gold plus a native FontString glow (no CSS
                -- box-shadow equivalent exists here, but SetShadowColor/SetShadowOffset is free).
                if m.rollValue >= 85 then
                    row.rollText:SetText("|cffffe066" .. m.rollValue .. "|r")
                    row.rollText:SetShadowColor(1, 0.7, 0.1, 0.9)
                    row.rollText:SetShadowOffset(0, 0)
                else
                    row.rollText:SetText("|cffffd200" .. m.rollValue .. "|r")
                    row.rollText:SetShadowColor(0, 0, 0, 1)
                    row.rollText:SetShadowOffset(1, -1)
                end
            else
                row.rollText:SetText("|cff444444—|r")
                row.rollText:SetShadowColor(0, 0, 0, 1)
                row.rollText:SetShadowOffset(1, -1)
            end
        end

        -- Council straw-poll button: tally of how many council members (including possibly
        -- yourself) picked this candidate, and a toggle for your own pick.
        local myKey        = (KART.Identity.ResolvePlayer("player"))
        local pollVotes    = (capturedRoll and LC.councilVotes[capturedRoll]) or {}
        local myPick       = pollVotes[myKey]
        local votedByMe    = (myPick == capturedKey)
        local pollCount    = 0
        for _, pick in pairs(pollVotes) do
            if pick == capturedKey then pollCount = pollCount + 1 end
        end
        -- Plain ASCII only (no ★/☆) — WoW's default game fonts don't have glyphs for most
        -- symbol/dingbat Unicode ranges and silently render them as an empty box ("tofu").
        row.councilVoteBtn.text:SetText((votedByMe and "|cffffd200+" or "|cff888888") .. pollCount .. "|r")
        if votedByMe then
            row.councilVoteBtn:SetBackdropBorderColor(1, 0.85, 0.2, 1)
        else
            row.councilVoteBtn:SetBackdropBorderColor(0, 0, 0, 1)
        end
        row.councilVoteBtn.fill:SetShown(pollCount > 0)
        if pollCount > 0 then
            row.councilVoteBtn.fill:SetWidth(38 * math.min(pollCount / math.max(numMem, 1), 1))
            row.councilVoteBtn.fill:SetAlpha(votedByMe and 0.4 or 0.22)
        end
        row.councilVoteBtn:SetScript("OnClick", function()
            if not capturedRoll or not capturedKey then return end
            LC.Vote.ToggleCouncilVote(capturedRoll, capturedKey)
        end)
        row.councilVoteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(KART.L.LC_COUNCIL_VOTE_TOOLTIP, 1, 1, 1)
            GameTooltip:Show()
        end)
        row.councilVoteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Note indicator dot — the note text itself only shows on its own dedicated tooltip here,
        -- not on the equip-icon hover (see row.equipHitbox above), so it doesn't show up every
        -- time someone just wants to compare gear.
        row.noteIcon:SetText(capturedNote ~= "" and "|cff66aaff•|r" or "")
        row.noteHitbox:SetScript("OnEnter", function(self)
            if capturedNote == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("\"" .. capturedNote .. "\"", 0.9, 0.9, 0.9, 1, true)
            GameTooltip:Show()
        end)
        row.noteHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Warning indicator: missing/outdated KART or Loot Council disabled on their end
        row.warnIcon:SetText(capturedKartStatus and "|cffff4444!|r" or "")

        -- Persistent officer-note indicator — same bullet glyph as the per-vote note dot above
        -- (proven to render fine), just a different colour so the two aren't confused.
        row.officerNoteIcon:SetText(capturedOfficerNote and "|cffffaa00•|r" or "")
        row.officerNoteHitbox:SetScript("OnEnter", function(self)
            if not capturedOfficerNote then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(capturedOfficerNote, 1, 0.7, 0.2, 1, true)
            GameTooltip:Show()
        end)
        row.officerNoteHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Left-click has no function. Right-click opens the assign menu.
        -- The panel never closes on its own here — only the X / Close button does.
        row:SetScript("OnClick", function(self)
            if not capturedRoll or not capturedKey then return end
            Council.ShowAssignMenu(self, capturedRoll, capturedKey, capturedShort, capturedVoteDef)
        end)
        -- Hover highlight only — no tooltip on the row itself. All tooltip content lives on
        -- the equip-icon hitbox below, so something is only shown while hovering that icon.
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.3, 0.15, 0.9)
            self:SetBackdropBorderColor(0.4, 0.7, 0.3, 1)
        end)
        row:SetScript("OnLeave", function(self)
            if self.memberKey == LC.assignedWinners[capturedRoll] then
                self:SetBackdropColor(0.28, 0.21, 0.03, 0.85)
                self:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            else
                self:SetBackdropColor(0.1, 0.1, 0.1, rowIdx % 2 == 0 and 0.35 or 0.1)
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end)

        -- Everything shows only while hovering the small equip icon: the rolled item (right
        -- side, via GameTooltip) side-by-side with this raider's currently equipped item in
        -- the matching slot (left side, via LC.equipCompareTooltip — a separate frame, not
        -- Blizzard's shared ShoppingTooltip1/2, which auto-compares against the VIEWER's own
        -- gear and would otherwise fight with this).
        row.equipHitbox:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if LC.IsRealItemLink(rollItem) then
                GameTooltip:SetHyperlink(rollItem)
                GameTooltip:AddLine(" ")
                if ShoppingTooltip1 then ShoppingTooltip1:Hide() end ---@diagnostic disable-line: undefined-global
                if ShoppingTooltip2 then ShoppingTooltip2:Hide() end ---@diagnostic disable-line: undefined-global
            else
                GameTooltip:SetText(rollItem or "???", 1, 1, 1)
            end
            GameTooltip:AddLine(capturedShort or "?", nr, ng, nb)
            if dtEnabled and capturedGainPct then
                GameTooltip:AddLine(string.format(KART.L.DT_TOOLTIP_GAIN,
                    capturedGainPct, capturedGainSource or "?"), 0.6, 0.9, 0.6, true)
            end
            -- Raider note / officer note deliberately NOT shown here anymore — they have their
            -- own dedicated tooltip on row.noteIcon/row.officerNoteIcon below, so hovering the
            -- equip icon (which people do constantly, just to compare gear) doesn't also dump
            -- someone's comment into the tooltip every time.
            if capturedArmorIneligible then
                GameTooltip:AddLine(KART.L.LC_ARMOR_INELIGIBLE, 0.6, 0.6, 0.6, true)
            end
            if capturedKartStatus then
                GameTooltip:AddLine(capturedKartStatus, 1, 0.4, 0.4, true)
            end
            GameTooltip:AddLine(KART.L.LC_TOOLTIP_RCLICK, 0.5, 0.5, 0.5, true)
            GameTooltip:Show()

            if capturedEquipLink and LC.equipCompareTooltip then
                LC.equipCompareTooltip:SetOwner(row, "ANCHOR_LEFT")
                LC.equipCompareTooltip:SetHyperlink(capturedEquipLink)
                LC.equipCompareTooltip:Show()
            end
        end)
        row.equipHitbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if LC.equipCompareTooltip then LC.equipCompareTooltip:Hide() end
        end)
    end

    for i = #members + 1, #panel.rows do
        if panel.rows[i] then panel.rows[i]:Hide() end
    end

    panel.scrollChild:SetHeight(math.max(#members * 26, 1))

    LC.ApplyFontSize()
end

--- Right-click menu on a council row: quick-assign, manually correct this player's vote, or
--- assign without a reason. Assign / Assign-without-reason are the only two actions that go
--- through AssignWinner (which announces the result and asks for reassignment confirmation if
--- the item was already assigned to someone else) — "Change vote" only edits which vote is shown
--- for this player (e.g. they voted verbally/via whisper) and must never assign anything itself.
function Council.ShowAssignMenu(anchor, rollID, playerKey, playerDisplayName, voteDef)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(playerDisplayName)

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN, function()
            LC.Trade.AssignWinner(rollID, playerKey, voteDef and voteDef.label or "", voteDef)
        end)

        -- No callback here on purpose: this makes CreateButton return a submenu descriptor.
        local changeMenu = rootDescription:CreateButton(KART.L.LC_MENU_CHANGE_VOTE) ---@diagnostic disable-line: missing-parameter
        for i, def in ipairs(LC.GetButtonConfig()) do
            changeMenu:CreateButton(def.label, function()
                LC.Vote.SetPlayerVote(rollID, playerKey, i)
            end)
        end

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN_NO_REASON, function()
            LC.Trade.AssignWinner(rollID, playerKey, "", nil)
        end)

        rootDescription:CreateButton(KART.L.LC_MENU_EDIT_NOTE, function()
            KART.LC.OfficerNotes.ShowOfficerNoteDialog(playerKey, playerDisplayName)
        end)
    end)
end
