local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")

-- This file's checkboxes/sliders are built at file load time, before Core.lua's ADDON_LOADED
-- handler has created KART_Settings -- passing the table directly here would freeze each widget
-- onto nil forever. Passed as `store` instead of the table itself, so KAUI resolves the current
-- global at click/drag time rather than capturing it now (see ResolveStore in KAUI-1.0.lua).
local function SettingsStore() return KART_Settings end

-- Settings-panel UI for the Loot Council module (split out of LootCouncil.lua, which keeps
-- the session/roll/config logic). Loads after LootCouncilPanel.lua and before Droptimizer.lua,
-- which anchors its toggle into KART.LC.SettingsCard created here.
KART.LC = KART.LC or {}
local LC = KART.LC

-- =====================================================================
--  Settings Panel  (fills KART.LootCouncilPanel created by MainFrame.lua)
-- =====================================================================

-- Updates the role-status line inside the raid-wide settings box. Called on build, whenever the
-- group roster changes (resolution of the lootmaster entry can change without a UI interaction),
-- and whenever the lootmaster field itself is edited.
--
-- Keys off LC.IsConfigOwner, not UnitIsGroupLeader: raid-wide authority follows the lootmaster entry
-- (see LC.HandleConfig). The old leader check told the actual lootmaster that their settings don't
-- count, and told a raid leader who isn't the lootmaster that theirs do — both exactly backwards.
function LC.UpdateRoleStatusLabel()
    local lbl = KART.LC.RoleStatusLabel
    if not lbl then return end
    local isOwner = LC.IsConfigOwner()
    local text
    if isOwner then
        text = KART.L.LC_ROLE_STATUS_OWNER
    elseif KAUtil.TrimString((KART_Settings and KART_Settings.lcLootmaster) or "") ~= "" then
        -- Field names someone who isn't us. Everything in this box is then inert — not just for the
        -- raid, but locally too: LC.ApplyOwnConfig no-ops for a non-owner, so our own council list
        -- never gets built either, and LC.IsLootOwner still falls back to the raid leader because no
        -- LC_CONFIG naming that person exists anywhere yet. A leader who fills the whole box in and
        -- types someone else's name gets exactly nothing, and the plain "the lootmaster's settings
        -- apply" reads like it's already taken care of — so say what's actually missing.
        text = KART.L.LC_ROLE_STATUS_FOREIGN
    else
        text = KART.L.LC_ROLE_STATUS_MEMBER
    end
    -- Nothing moved, so skip the re-flow below. Matters because the lootmaster edit box calls this on
    -- every keystroke, and the status only ever flips on the one keystroke that changes ownership.
    if lbl:GetText() == text then return end
    lbl:SetText(text)
    lbl:SetTextColor(isOwner and 0.3 or 0.9, isOwner and 0.9 or 0.7, isOwner and 0.3 or 0.2)
    -- The two texts wrap to a different number of lines, so the box below needs to re-flow too
    -- (no-op on the very first call, before layoutRaidBox() has run yet).
    if LC.RelayoutRaidBox then LC.RelayoutRaidBox() end
end

-- Shows the RAID's config in the raid-wide widgets while somebody else's is in force, instead of
-- the viewer's own dormant settings.
--
-- Those widgets are bound to KART_Settings, but an accepted LC_CONFIG lands in LC.raidConfig and
-- never touches KART_Settings — deliberately, so a raider's own setup survives for when they are
-- the lootmaster themselves. The visible result was a peer staring at empty Council and Lootmaster
-- boxes with "5 names not resolved yet" printed directly beneath them, because that counter reads
-- the effective table while the boxes read the dormant one (B20).
--
-- The viewer's own values are never overwritten: they stay in KART_Settings and come back the
-- moment no foreign config applies. LC.suppressFieldWrite exists for exactly that — SetText fires
-- OnTextChanged, which would otherwise write the raid's values straight into the viewer's settings
-- and broadcast them.
LC.suppressFieldWrite = false
function LC.RefreshRaidWideFields()
    local cfg = LC.raidConfig
    -- fromSelf marks a config we applied from our own settings (LC.ApplyOwnConfig); only a received
    -- one is somebody else's, and only then is there anything to show that isn't already shown.
    local foreign = not LC.IsConfigOwner() and cfg and not cfg.fromSelf and cfg.lootmaster and cfg.lootmaster ~= ""

    local buttons, council, lootmaster, rolls, minQ
    if foreign then
        buttons    = cfg.buttonLabels or ""
        council    = cfg.councilMembers or ""
        -- raidConfig.lootmaster is a resolved identity key, not the text that was typed. Show the
        -- name it resolves to; the key itself would be meaningless on screen.
        local unit = KASC.Identity.FindUnitForKey(cfg.lootmaster)
        lootmaster = (unit and UnitName(unit)) or "?"
        rolls      = cfg.rollsEnabled == true
        minQ       = cfg.minQuality or 4
    else
        buttons    = KART_Settings.lcButtonLabels or ""
        council    = KART_Settings.lcCouncilMembers or ""
        lootmaster = KART_Settings.lcLootmaster or ""
        rolls      = KART_Settings.lcRollsEnabled == true
        minQ       = KART_Settings.lcMinQuality or 4
    end

    -- Only when the text actually differs: SetText moves the caret to the end even when the content
    -- is identical, and this runs on every roster change — a lootmaster typing their council list
    -- while raiders trickle in would have the cursor jump out from under them.
    local function setIfChanged(eb, text)
        if eb and eb:GetText() ~= text then eb:SetText(text) end
    end

    LC.suppressFieldWrite = true
    setIfChanged(KART.LC.ButtonLabelEditBox, buttons)
    setIfChanged(KART.LC.CouncilMembersEditBox, council)
    setIfChanged(KART.LC.LootmasterEditBox, lootmaster)
    if KART.LC.CbRollsEnabled then KART.LC.CbRollsEnabled:SetChecked(rolls) end
    if KART.LC.BtnMinQuality then KART.LC.BtnMinQuality.text:SetText(LC.QualityLabel(minQ)) end
    LC.suppressFieldWrite = false

    -- Read-only while they show someone else's values: editing them would change nothing for the
    -- raid and would silently discard what the viewer had typed for themselves.
    for _, eb in ipairs({ KART.LC.ButtonLabelEditBox, KART.LC.CouncilMembersEditBox, KART.LC.LootmasterEditBox }) do
        if eb then
            eb:EnableMouse(not foreign)
            eb:EnableKeyboard(not foreign)
            if foreign then eb:ClearFocus() end
        end
    end
end

-- Colons are the LC_CONFIG/LC_SYNC payload separator (see LC.BroadcastRaidConfig) — a colon
-- inside any synced free-text field would make the receivers' payload pattern silently fail,
-- leaving every other client stuck on stale config. Strip them at input time.
local function StripColons(editBox)
    local text = editBox:GetText()
    if text:find(":", 1, true) then
        editBox:SetText((text:gsub(":", ""))) -- re-fires OnTextChanged with the clean text
        return true
    end
    return false
end

function LC.BuildSettingsPanel(parent)
    local L = KART.L

    KART.CreateTabTitle(5, L.LC_SETTINGS_TITLE)

    -- Personal preferences card (module toggle, autopass, Droptimizer slot at -75,
    -- compact vote layout, nicknames). Raid-wide settings live in the amber box below.
    local prefsCard = KART.UI:CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    prefsCard:SetSize(500, 425) -- 215 -> 260 for the font-size slider, -> 350 for the scale/layer pair, -> 425 for the two irrelevant-item switches
    KART.LC.SettingsCard = prefsCard

    -- Master switch: fully disables the module (e.g. during testing, or to avoid clashing with
    -- another loot addon like RCLootCouncil). Nothing below still runs when this is off.
    KART.LC.CbModuleEnabled = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCModuleEnabled", label = L.LC_SET_MODULE_ENABLED,
        store = SettingsStore, key = "lcModuleEnabled", y = -15,
        -- This flag rides along in the handshake as the "LC" capability, and peers cache what a
        -- handshake told them until the next one. Announce again, or everyone keeps showing the old
        -- answer for the rest of the session — with the default being OFF, switching it on after
        -- login left a red "Loot Council disabled on their end" on every council panel in the raid
        -- while it plainly worked (B19).
        onChanged = function()
            KASC:AnnounceHelloIfChanged()
            if IsInGuild() then KASC:AnnounceHelloIfChanged("GUILD") end
        end,
        tooltip = L.LC_DESC_MODULE_ENABLED,
    })

    -- Personal preference — never overridden by the raid leader's settings.
    KART.LC.CbAutoPass = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCAutoPass", label = L.LC_SET_AUTOPASS,
        store = SettingsStore, key = "lcAutoPass", y = -45,
        tooltip = L.LC_DESC_AUTOPASS,
    })

    -- Personal preference, same reasoning as CbAutoPass above — the vote window's layout style
    -- is purely a display choice, so it's never synced from the raid leader. Slot -105: the next
    -- free step below the reserved Droptimizer slot at -75 (see Droptimizer.lua:128), inside
    -- this card.
    KART.LC.CbCompactVoteLayout = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCCompactVoteLayout", label = L.LC_SET_COMPACT_VOTE_LAYOUT,
        store = SettingsStore, key = "lcVoteLayoutCompact", y = -105,
        onChanged = function() LC.Vote.RefreshVoteListRowsIfShown() end,
        tooltip = L.LC_DESC_COMPACT_VOTE_LAYOUT,
    })

    -- Personal preference, same reasoning as CbCompactVoteLayout above — purely how names render
    -- on YOUR OWN council panel, never synced. Needs Northern Sky Raid Tools installed with a
    -- nickname set per character to have any visible effect (see KASC.Identity.GetNickname); falls back to
    -- the character short name automatically otherwise. Slot -135: next free step below
    -- CbCompactVoteLayout, inside this card.
    KART.LC.CbShowNickNames = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCShowNickNames", label = L.LC_SET_SHOW_NICKNAMES,
        store = SettingsStore, key = "lcShowNickNames", y = -135,
        onChanged = function()
            if LC.councilPanel and LC.councilPanel:IsShown() then KART.LC.Council.RefreshCouncilRows() end
        end,
        tooltip = L.LC_DESC_SHOW_NICKNAMES,
    })

    -- Personal preference, same reasoning as CbCompactVoteLayout above — controls whether an
    -- already-voted item stays full-size, shrinks, or disappears entirely from YOUR OWN vote
    -- window (see Vote.GetVisibleRolls). Slot -175: next free step below CbShowNickNames, inside
    -- this card (card height bumped 165 -> 215 above to fit a 28px-tall button here instead of
    -- another checkbox row). Initial label is hardcoded to "full" — KART_Settings doesn't exist
    -- yet at file-load time, same reasoning as BtnMinQuality's own placeholder-text comment below;
    -- Core.lua's ADDON_LOADED handler syncs the real saved value once settings are loaded.
    KART.LC.BtnVotedItemDisplay = KART.UI:CreateModernButton(
        prefsCard, LC.VotedItemDisplayLabel("full"), L.LC_DESC_VOTED_DISPLAY)
    KART.LC.BtnVotedItemDisplay:SetPoint("TOPLEFT", 20, -175)
    KART.LC.BtnVotedItemDisplay:SetSize(460, 28)
    KART.LC.BtnVotedItemDisplay:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.LC_SET_VOTED_DISPLAY)
            for _, mode in ipairs({"full", "shrink", "hide"}) do
                rootDescription:CreateButton(LC.VotedItemDisplayLabel(mode), function()
                    KART_Settings.lcVotedItemDisplay = mode
                    self.text:SetText(LC.VotedItemDisplayLabel(mode))
                    LC.Vote.RefreshVoteListRowsIfShown()
                end)
            end
        end)
    end)

    -- Personal preference, moved here from the raid-wide box: font size is never part of the
    -- synced raid config (LC.BroadcastRaidConfig only carries min quality, button labels, the
    -- rolls toggle, the lootmaster and the council list) — it was sitting under the raid-wide
    -- heading by mistake. Key/onChanged/behaviour unchanged (see LC.ApplyFontSize). Slot -215:
    -- next free step below BtnVotedItemDisplay, inside this card (card height bumped 215 -> 260
    -- above to fit it).
    KART.LC.SldFontSize = KART.UI:CreateSettingsSlider(prefsCard, {
        name = "KART_LCFontSizeSlider", label = L.LC_SET_FONT_SIZE,
        min = 8, max = 20, store = SettingsStore, key = "lcFontSize", y = -215,
        tooltip = L.LC_DESC_FONT_SIZE,
        onChanged = function() KART.UpdateStyles() end,
    })

    -- Scale and layer for the Loot Council windows alone. KART_Settings.uiScale reaches
    -- KART.MainFrame and nothing else, so the two windows a raider actually stares at mid-pull had
    -- no scale control at all -- which is what makes the fixed layout bite at 1080p, where the whole
    -- interface is a third larger relative to the screen (B18/B22). Personal, never broadcast.
    KART.LC.SldScale = KART.UI:CreateSettingsSlider(prefsCard, {
        name = "KART_LCScaleSlider", label = L.LC_SET_SCALE,
        min = 50, max = 150, store = SettingsStore, key = "lcScale", y = -260,
        tooltip = L.LC_DESC_SCALE,
        onChanged = function() LC.ApplyWindowChrome() end,
    })

    KART.LC.SldStrata = KART.UI:CreateSettingsSlider(prefsCard, {
        name = "KART_LCStrataSlider", label = L.LC_SET_STRATA,
        min = 1, max = #KART.StrataLevels, store = SettingsStore, key = "lcFrameStrata", y = -305,
        tooltip = L.LC_DESC_STRATA,
        onChanged = function() LC.ApplyWindowChrome() end,
        valueIsText = true, -- shows the stratum NAME, so its value box stays read-only
    })
    -- Shows the stratum's NAME instead of the raw index, exactly as the main window's own layer
    -- slider does (see UpdateStrataSliderText in MainFrame.lua); OnShow covers the case where the
    -- initial SetValue doesn't fire because the saved value already equals the slider's.
    local function UpdateLCStrataText(self)
        self.valueText:SetText(KART.StrataLevels[math.floor(self:GetValue())] or "")
    end
    KART.LC.SldStrata:HookScript("OnValueChanged", UpdateLCStrataText)
    KART.LC.SldStrata:HookScript("OnShow", UpdateLCStrataText)

    -- Personal preferences, same reasoning as CbAutoPass above — which items YOUR OWN vote window
    -- bothers you with is your call, never the raid leader's. Slots -350/-380: the next free steps
    -- below SldStrata, inside this card (height bumped 350 -> 425 above to fit both).
    KART.LC.CbHideIrrelevant = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCHideIrrelevant", label = L.LC_SET_HIDE_IRRELEVANT,
        store = SettingsStore, key = "lcHideIrrelevant", y = -350,
        onChanged = function()
            -- ...IfShown alone would make this switch look dead exactly when it matters: if every
            -- roll of the batch was hidden, RefreshVoteListRows already hid the window itself, and
            -- the guard then refuses to reopen it. The rule it enforces (a display-only toggle must
            -- never pop the window over stale rolls — see Vote.RefreshVoteListRowsIfShown) still
            -- stands; this case is outside it, because a roll only carries the hide flag while it is
            -- live and being voted on, and the player just asked to see those.
            for _, rollID in ipairs(LC.voteListRolls) do
                if LC.hiddenIrrelevant[rollID] then
                    LC.Vote.RefreshVoteListRows()
                    return
                end
            end
            LC.Vote.RefreshVoteListRowsIfShown()
        end,
        tooltip = L.LC_DESC_HIDE_IRRELEVANT,
    })

    KART.LC.CbAutoTransmogVote = KART.UI:CreateSettingsCheckbox(prefsCard, {
        name = "KART_LCAutoTransmogVote", label = L.LC_SET_AUTO_TRANSMOG,
        store = SettingsStore, key = "lcAutoTransmogVote", y = -380,
        onChanged = function() LC.Vote.RefreshVoteListRowsIfShown() end,
        tooltip = L.LC_DESC_AUTO_TRANSMOG,
    })

    -- Droptimizer gain% column toggle (KART.DT.CbModuleEnabled) is built here too, by
    -- Droptimizer.lua — see the reserved -75 slot there. Kept in its own file since it's a
    -- different module, but it's a personal preference like CbAutoPass above, so it lives next
    -- to it rather than getting its own settings tab.

    -- ================= Raid-wide settings box =================
    -- Everything in here only takes effect for the raid when YOU are the one named in the Lootmaster
    -- field below (LC.IsConfigOwner) — that person owns the config and is the only one whose client
    -- broadcasts it; everyone else, raid leader included, automatically uses their values. Visually
    -- set apart on purpose so nobody mistakes their own tweaks here for something that affects the
    -- current raid.
    local raidBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    raidBox:SetPoint("TOPLEFT", prefsCard, "BOTTOMLEFT", 0, -20)
    raidBox:SetWidth(500) -- height is set by layoutRaidBox() from the measured content
    KART.UI:SetPixelBackdrop(raidBox, {bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    raidBox:SetBackdropColor(0.5, 0.4, 0.05, 0.12)
    raidBox:SetBackdropBorderColor(0.5, 0.4, 0.05, 0.6)

    -- Title and role-status stacked on their own lines (not side-by-side) — kept simple even
    -- now that the box is 500px wide, since role-status text length varies a lot by locale.
    -- Positions for all of this are set by layoutRaidBox() further down, not here.
    local boxTitle = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    boxTitle:SetText(L.LC_RAIDWIDE_TITLE)
    boxTitle:SetTextColor(0.9, 0.75, 0.3)
    KART.UI:RegisterLabel(boxTitle)

    KART.LC.RoleStatusLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.RoleStatusLabel:SetWidth(460)
    KART.LC.RoleStatusLabel:SetJustifyH("LEFT")
    KART.UI:RegisterLabel(KART.LC.RoleStatusLabel)
    LC.UpdateRoleStatusLabel() -- sets the text before layoutRaidBox() first measures it

    local boxDivider = raidBox:CreateTexture(nil, "ARTWORK")
    boxDivider:SetColorTexture(0.5, 0.4, 0.05, 0.5)
    boxDivider:SetHeight(1)
    boxDivider:SetPoint("TOPRIGHT", -8, -38) -- Y overridden by layoutRaidBox(); X stays fixed

    KART.LC.SldVoteTimer = KART.UI:CreateSettingsSlider(raidBox, {
        name = "KART_LCVoteTimerSlider", label = L.LC_SET_VOTE_TIMER,
        min = 5, max = 180, store = SettingsStore, key = "lcVoteSeconds", y = -52,
        tooltip = L.LC_DESC_VOTE_TIMER,
    })

    -- Opt-in random 1-100 roll per raider, shown as its own column in the council panel —
    -- analogous to RCLootCouncil's Need roll. Purely informational (see LC.Vote.HandleRoll).
    KART.LC.CbRollsEnabled = KART.UI:CreateSettingsCheckbox(raidBox, {
        name = "KART_LCRollsEnabled", label = L.LC_SET_ROLLS_ENABLED,
        store = SettingsStore, key = "lcRollsEnabled", y = -140,
        onChanged = LC.BroadcastRaidConfig,
        tooltip = L.LC_DESC_ROLLS_ENABLED,
    })

    -- From here on, labels can be longer than one line depending on locale (German text
    -- tends to run longer than English) AND depending on the user's chosen font/size in
    -- Settings, so every label gets a fixed width + word wrap. Positions are computed by
    -- layoutRaidBox() below from the actual measured height of each element instead of a
    -- hardcoded guess. Creation/static setup happens once here; layoutRaidBox() is re-run
    -- from KART.UpdateStyles() too, because that function swaps in the user's font *after*
    -- this panel is built, which can change how many lines a label wraps to.
    local CONTENT_WIDTH = 460

    local lblButtons = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblButtons:SetWidth(CONTENT_WIDTH)
    lblButtons:SetJustifyH("LEFT")
    lblButtons:SetText(L.LC_SET_BUTTONS)
    KART.UI:RegisterLabel(lblButtons)

    KART.LC.ButtonLabelEditBox = KART.UI:CreateStyledEditBox(raidBox, "KART_LCButtonLabels")
    local eb = KART.LC.ButtonLabelEditBox
    eb:SetSize(CONTENT_WIDTH, 28)
    eb:SetMaxLetters(128)
    eb:SetScript("OnTextChanged", function(self)
        if LC.suppressFieldWrite then return end -- programmatic fill (see LC.RefreshRaidWideFields)
        if StripColons(self) then return end
        KART_Settings.lcButtonLabels = self:GetText()
        LC.BroadcastRaidConfigThrottled()
    end)

    local hint = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetWidth(CONTENT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.LC_SET_BUTTONS_HINT)
    hint:SetTextColor(0.55, 0.55, 0.55)
    KART.UI:RegisterLabel(hint)

    -- Council member names
    local lblCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblCouncil:SetWidth(CONTENT_WIDTH)
    lblCouncil:SetJustifyH("LEFT")
    lblCouncil:SetText(L.LC_SET_COUNCIL)
    KART.UI:RegisterLabel(lblCouncil)

    KART.LC.CouncilMembersEditBox = KART.UI:CreateStyledEditBox(raidBox, "KART_LCCouncilMembers")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(CONTENT_WIDTH, 28)
    ebC:SetMaxLetters(255)
    ebC:SetScript("OnTextChanged", function(self)
        if LC.suppressFieldWrite then return end -- programmatic fill (see LC.RefreshRaidWideFields)
        if StripColons(self) then return end
        KART_Settings.lcCouncilMembers = self:GetText()
        LC.BroadcastRaidConfigThrottled()
    end)

    local hintCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintCouncil:SetWidth(CONTENT_WIDTH)
    hintCouncil:SetJustifyH("LEFT")
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    KART.UI:RegisterLabel(hintCouncil)

    -- Subdued indicator for council-list entries not yet matched to a live player (see
    -- KASC.Identity.IsResolvedKey/LC.RetryPendingResolutions) — hidden entirely once nothing is
    -- pending, so it never clutters the common case.
    KART.LC.CouncilPendingLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.CouncilPendingLabel:SetWidth(CONTENT_WIDTH)
    KART.LC.CouncilPendingLabel:SetJustifyH("LEFT")
    KART.LC.CouncilPendingLabel:SetTextColor(0.85, 0.65, 0.15)
    KART.UI:RegisterLabel(KART.LC.CouncilPendingLabel)

    local function UpdateCouncilPendingLabel()
        local pendingCount = 0
        for pendingText in pairs(LC.CouncilNamesTable) do
            if not KASC.Identity.IsResolvedKey(pendingText) then pendingCount = pendingCount + 1 end
        end
        if pendingCount > 0 then
            KART.LC.CouncilPendingLabel:SetText(string.format(L.LC_SET_COUNCIL_PENDING, pendingCount))
            KART.LC.CouncilPendingLabel:Show()
        else
            KART.LC.CouncilPendingLabel:Hide()
        end
        -- The label's shown/hidden state changes how much vertical space it occupies (see
        -- layoutRaidBox()) — re-flow the box the same way LC.UpdateRoleStatusLabel already does
        -- for its own height-dependent label, so everything below shifts to make/reclaim room.
        -- LC.RelayoutRaidBox self-guards on visibility and syncs the scroll range (see its
        -- definition below), so this fires cheaply even for the per-message pending-resolution retry.
        if LC.RelayoutRaidBox then LC.RelayoutRaidBox() end
    end
    KART.LC.CouncilMembersEditBox:HookScript("OnShow", UpdateCouncilPendingLabel)
    hooksecurefunc(LC, "RetryPendingResolutions", UpdateCouncilPendingLabel)

    -- Lootmaster: the one player who must physically win every roll (Need/Greed/Disenchant,
    -- never Pass — see ForceWinRoll in LC.OnStartLootRoll) so they can trade each item to whoever
    -- the council actually decided on. Deliberately a raid-leader-synced field, not a personal
    -- checkbox like CbAutoPass above — see LC.GetLootmaster.
    local lblLootmaster = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblLootmaster:SetWidth(CONTENT_WIDTH)
    lblLootmaster:SetJustifyH("LEFT")
    lblLootmaster:SetText(L.LC_SET_LOOTMASTER)
    KART.UI:RegisterLabel(lblLootmaster)

    KART.LC.LootmasterEditBox = KART.UI:CreateStyledEditBox(raidBox, "KART_LCLootmaster")
    local ebL = KART.LC.LootmasterEditBox
    ebL:SetSize(CONTENT_WIDTH, 28)
    ebL:SetMaxLetters(48)
    ebL:SetScript("OnTextChanged", function(self)
        if LC.suppressFieldWrite then return end -- programmatic fill (see LC.RefreshRaidWideFields)
        if StripColons(self) then return end
        KART_Settings.lcLootmaster = self:GetText()
        -- This field decides config ownership (LC.IsConfigOwner), so the role-status line above can
        -- flip on the very keystroke that names/unnames us — it would otherwise stay stale until the
        -- next roster change.
        LC.UpdateRoleStatusLabel()
        LC.BroadcastRaidConfigThrottled()
    end)

    local hintLootmaster = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintLootmaster:SetWidth(CONTENT_WIDTH)
    hintLootmaster:SetJustifyH("LEFT")
    hintLootmaster:SetText(L.LC_SET_LOOTMASTER_HINT)
    hintLootmaster:SetTextColor(0.55, 0.55, 0.55)
    KART.UI:RegisterLabel(hintLootmaster)

    -- Minimum item quality that triggers the Loot Council flow (full width)
    local lblQuality = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblQuality:SetWidth(CONTENT_WIDTH)
    lblQuality:SetJustifyH("LEFT")
    lblQuality:SetText(L.LC_SET_MIN_QUALITY)
    KART.UI:RegisterLabel(lblQuality)

    -- Placeholder text only — KART_Settings doesn't exist yet at file-load time.
    -- Core.lua's ADDON_LOADED handler syncs the real value once settings are loaded.
    KART.LC.BtnMinQuality = KART.UI:CreateModernButton(raidBox, LC.QualityLabel(4), L.LC_DESC_MIN_QUALITY)
    KART.LC.BtnMinQuality:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnMinQuality:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.LC_SET_MIN_QUALITY)
            for q = 0, 5 do
                rootDescription:CreateButton(LC.QualityLabel(q), function()
                    KART_Settings.lcMinQuality = q
                    self.text:SetText(LC.QualityLabel(q))
                    LC.BroadcastRaidConfig()
                end)
            end
        end)
    end)

    -- Toggle session (full width) — functionally always leader-gated already; lives in the
    -- raid-wide box too since it only ever does anything for the raid leader.
    KART.LC.BtnToggleSession = KART.UI:CreateModernButton(raidBox, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        -- Loot owner, not raid leader: the lootmaster runs the whole loot flow (see LC.IsLootOwner),
        -- and while no lootmaster is configured that check falls back to the leader anyway.
        if not IsInRaid() then
            print("|cff00ff00KART:|r " .. KART.L.LC_RAID_ONLY)
        elseif LC.IsLootOwner() then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)

    KART.LC.BtnSyncSettings = KART.UI:CreateModernButton(raidBox, L.LC_BTN_SYNC_SETTINGS, L.LC_DESC_SYNC_SETTINGS)
    KART.LC.BtnSyncSettings:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnSyncSettings:SetScript("OnClick", function()
        LC.ShowSyncTargetDialog()
    end)

    local function layoutRaidBox()
        local y = -8

        boxTitle:SetPoint("TOPLEFT", 10, y)
        y = y - boxTitle:GetStringHeight() - 6

        KART.LC.RoleStatusLabel:SetPoint("TOPLEFT", 10, y)
        y = y - KART.LC.RoleStatusLabel:GetStringHeight() - 8

        boxDivider:SetPoint("TOPLEFT", 8, y)
        y = y - 1 - 14

        KART.LC.SldVoteTimer:SetPoint("TOPLEFT", 20, y - 16) -- -16: slider's own title sits above it
        y = y - 16 - 14 - 18

        KART.LC.CbRollsEnabled:SetPoint("TOPLEFT", 20, y)
        y = y - 20 - 14

        lblButtons:SetPoint("TOPLEFT", 20, y)
        y = y - lblButtons:GetStringHeight() - 8

        eb:SetPoint("TOPLEFT", 20, y)
        y = y - eb:GetHeight() - 9

        hint:SetPoint("TOPLEFT", 20, y)
        y = y - hint:GetStringHeight() - 18

        lblCouncil:SetPoint("TOPLEFT", 20, y)
        y = y - lblCouncil:GetStringHeight() - 8

        ebC:SetPoint("TOPLEFT", 20, y)
        y = y - ebC:GetHeight() - 9

        hintCouncil:SetPoint("TOPLEFT", 20, y)
        y = y - hintCouncil:GetStringHeight() - 18

        KART.LC.CouncilPendingLabel:SetPoint("TOPLEFT", 20, y)
        if KART.LC.CouncilPendingLabel:IsShown() then
            y = y - KART.LC.CouncilPendingLabel:GetStringHeight() - 18
        end

        lblLootmaster:SetPoint("TOPLEFT", 20, y)
        y = y - lblLootmaster:GetStringHeight() - 8

        ebL:SetPoint("TOPLEFT", 20, y)
        y = y - ebL:GetHeight() - 9

        hintLootmaster:SetPoint("TOPLEFT", 20, y)
        y = y - hintLootmaster:GetStringHeight() - 18

        lblQuality:SetPoint("TOPLEFT", 20, y)
        y = y - lblQuality:GetStringHeight() - 8

        KART.LC.BtnMinQuality:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 10

        KART.LC.BtnToggleSession:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 10

        KART.LC.BtnSyncSettings:SetPoint("TOPLEFT", 20, y)
        y = y - 28 - 16

        raidBox:SetHeight(-y)
    end

    layoutRaidBox()
    KART.UI:ApplyRoundedMask(raidBox, KAUI.CORNER_RADIUS_LG)
    -- Exported entry point for every external caller (role-status change, pending-resolution retry,
    -- UpdateStyles). Two things the raw layoutRaidBox doesn't do:
    --  * Skip while off screen. IsVisible(), NOT IsShown(): tab switching hides the parent panel, so
    --    raidBox's own shown flag stays true forever and an IsShown() test would never skip anything.
    --    LC.IsSenderCouncil runs the pending-resolution retry for every unresolved LC message, which
    --    would otherwise re-flow an invisible box once per incoming vote.
    --  * Keep the scroll range in sync. The box's height feeds KART.UpdateScrollRange's tab-5 extent;
    --    growing it (e.g. the pending label appearing) while the tab is open would otherwise push the
    --    bottom buttons past the scrollable area until the user switched tabs and back.
    LC.RelayoutRaidBox = function()
        if not raidBox:IsVisible() then return end
        layoutRaidBox()
        if KART.UpdateScrollRange then KART.UpdateScrollRange() end
    end
    -- Catches up whatever was skipped while hidden. WoW fires OnShow on children when the parent
    -- becomes visible, so this runs on every switch back to the Loot Council tab.
    raidBox:HookScript("OnShow", function()
        layoutRaidBox()
        if KART.UpdateScrollRange then KART.UpdateScrollRange() end
    end)
    KART.LC.RaidBox = raidBox -- measured by KART.UpdateScrollRange (dynamic panel height)
    -- ================= /Raid-wide settings box =================

    -- Two test buttons side by side: Looter view / Lootmaster view.
    -- Anchored to raidBox's own BOTTOMLEFT (not a fixed offset from parent) so they always sit
    -- right below the box regardless of how tall it ends up being — the box's height depends on
    -- wrapped label text, which can vary by locale and by the user's chosen font/size.
    KART.LC.BtnTestLooter = KART.UI:CreateModernButton(parent, L.LC_BTN_TEST_LOOTER, L.LC_DESC_TEST_LOOTER)
    KART.LC.BtnTestLooter:SetSize(242, 28)
    KART.LC.BtnTestLooter:SetPoint("TOPLEFT", raidBox, "BOTTOMLEFT", 0, -16)
    KART.LC.BtnTestLooter:SetScript("OnClick", function() LC.StartTest("looter") end)

    KART.LC.BtnTestMaster = KART.UI:CreateModernButton(parent, L.LC_BTN_TEST_MASTER, L.LC_DESC_TEST_MASTER)
    KART.LC.BtnTestMaster:SetSize(242, 28)
    KART.LC.BtnTestMaster:SetPoint("LEFT", KART.LC.BtnTestLooter, "RIGHT", 16, 0)
    KART.LC.BtnTestMaster:SetScript("OnClick", function() LC.StartTest("master") end)

    -- Loot history (full width) — anchored below the test buttons for the same reason.
    KART.LC.BtnHistory = KART.UI:CreateModernButton(parent, L.LC_BTN_HISTORY, L.LC_DESC_HISTORY)
    KART.LC.BtnHistory:SetSize(500, 28)
    KART.LC.BtnHistory:SetPoint("TOPLEFT", KART.LC.BtnTestLooter, "BOTTOMLEFT", 0, -8)
    KART.LC.BtnHistory:SetScript("OnClick", function()
        if KART.LH then KART.LH.Toggle() end
    end)

    KART.UI:RegisterLocaleRefresher(function()
        local Lx = KART.L
        KART.TabTitles[5]:SetText(Lx.LC_SETTINGS_TITLE)
        KART.LC.CbModuleEnabled.text:SetText(Lx.LC_SET_MODULE_ENABLED)        KART.LC.CbModuleEnabled.tooltipText = Lx.LC_DESC_MODULE_ENABLED
        KART.LC.CbAutoPass.text:SetText(Lx.LC_SET_AUTOPASS)                   KART.LC.CbAutoPass.tooltipText = Lx.LC_DESC_AUTOPASS
        KART.LC.CbCompactVoteLayout.text:SetText(Lx.LC_SET_COMPACT_VOTE_LAYOUT)
        KART.LC.CbCompactVoteLayout.tooltipText = Lx.LC_DESC_COMPACT_VOTE_LAYOUT
        KART.LC.CbShowNickNames.text:SetText(Lx.LC_SET_SHOW_NICKNAMES)        KART.LC.CbShowNickNames.tooltipText = Lx.LC_DESC_SHOW_NICKNAMES
        KART.LC.CbHideIrrelevant.text:SetText(Lx.LC_SET_HIDE_IRRELEVANT)      KART.LC.CbHideIrrelevant.tooltipText = Lx.LC_DESC_HIDE_IRRELEVANT
        KART.LC.CbAutoTransmogVote.text:SetText(Lx.LC_SET_AUTO_TRANSMOG)      KART.LC.CbAutoTransmogVote.tooltipText = Lx.LC_DESC_AUTO_TRANSMOG
        KART.LC.BtnVotedItemDisplay.tooltipText = Lx.LC_DESC_VOTED_DISPLAY -- label synced by SyncSettingsToUI
        boxTitle:SetText(Lx.LC_RAIDWIDE_TITLE)
        KART.LC.SldVoteTimer.title:SetText(Lx.LC_SET_VOTE_TIMER)              KART.LC.SldVoteTimer.tooltipText = Lx.LC_DESC_VOTE_TIMER
        KART.LC.SldFontSize.title:SetText(Lx.LC_SET_FONT_SIZE)                KART.LC.SldFontSize.tooltipText = Lx.LC_DESC_FONT_SIZE
        KART.LC.CbRollsEnabled.text:SetText(Lx.LC_SET_ROLLS_ENABLED)          KART.LC.CbRollsEnabled.tooltipText = Lx.LC_DESC_ROLLS_ENABLED
        lblButtons:SetText(Lx.LC_SET_BUTTONS)
        hint:SetText(Lx.LC_SET_BUTTONS_HINT)
        lblCouncil:SetText(Lx.LC_SET_COUNCIL)
        hintCouncil:SetText(Lx.LC_SET_COUNCIL_HINT)
        lblLootmaster:SetText(Lx.LC_SET_LOOTMASTER)
        hintLootmaster:SetText(Lx.LC_SET_LOOTMASTER_HINT)
        lblQuality:SetText(Lx.LC_SET_MIN_QUALITY)
        KART.LC.BtnMinQuality.tooltipText = Lx.LC_DESC_MIN_QUALITY -- label synced by SyncSettingsToUI
        KART.LC.BtnToggleSession.text:SetText(Lx.LC_BTN_TOGGLE)               KART.LC.BtnToggleSession.tooltipText = Lx.LC_DESC_TOGGLE
        KART.LC.BtnSyncSettings.text:SetText(Lx.LC_BTN_SYNC_SETTINGS)         KART.LC.BtnSyncSettings.tooltipText = Lx.LC_DESC_SYNC_SETTINGS
        KART.LC.BtnTestLooter.text:SetText(Lx.LC_BTN_TEST_LOOTER)             KART.LC.BtnTestLooter.tooltipText = Lx.LC_DESC_TEST_LOOTER
        KART.LC.BtnTestMaster.text:SetText(Lx.LC_BTN_TEST_MASTER)             KART.LC.BtnTestMaster.tooltipText = Lx.LC_DESC_TEST_MASTER
        KART.LC.BtnHistory.text:SetText(Lx.LC_BTN_HISTORY)                    KART.LC.BtnHistory.tooltipText = Lx.LC_DESC_HISTORY
        LC.UpdateRoleStatusLabel() -- reads KART.L live and re-flows the box
        layoutRaidBox() -- German/English label heights differ; re-measure everything
    end)
end

-- Called at file load time; KART.LootCouncilPanel is created by MainFrame.lua
if KART.LootCouncilPanel then
    LC.BuildSettingsPanel(KART.LootCouncilPanel)
end
