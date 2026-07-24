local addonName, KART = ...

KART.LC = KART.LC or {}
local LC = KART.LC

LC.sessionActive        = false
LC.promptedThisSession  = false
LC.votes                = {}  -- [rollID][playerShortName] = {idx, note}
LC.rolls                = {}  -- [rollID][playerShortName] = 1-100 random roll (opt-in, see lcRollsEnabled)
LC.councilVotes         = {}  -- [rollID][councilMemberShortName] = candidateShortName they picked (tally only, not binding)
LC.rollItems            = {}  -- [rollID] = itemLink
LC.voteListRolls        = {}  -- ordered list of rollIDs currently shown as rows in the looter's vote list
LC.councilTabs          = {}  -- ordered list of rollIDs currently shown as tabs in the council panel
LC.councilTabsNew       = {}  -- [rollID] = true while a tab hasn't been switched to yet (unseen-item marker)
LC.rollDeadlines        = {}  -- [rollID] = GetTime() timestamp when voting closes, shared by both UIs
LC.rollDurations        = {}  -- [rollID] = original vote-window length in seconds, used only to size
                               -- the council header's time-bar fill (rollDeadlines alone gives a
                               -- deadline but not the window's original length)
LC.pendingTrades        = {}  -- items assigned to someone else, not yet handed over: {rollID, itemLink, winnerKey}
LC.CouncilNamesTable    = {}  -- resolved KART.Identity key -> true. Populated ONLY from the raid leader's
                               -- broadcast (LC_CONFIG) — never from local settings — so a regular
                               -- raider can't self-promote by editing their own council-member list.
LC.raidConfig           = {}  -- authoritative config received from the raid leader: minQuality, buttonLabels, councilMembers

-- Items simulated by the Test buttons (StartTest) — several so the vote-list/council-panel
-- handling of multiple simultaneous rolls can actually be tested (multiple items dropping at
-- once is the normal case in a real raid, not the exception). Real item links, not fake strings
-- — so tabs show real icons and the armor-eligibility / equipped-item comparison features have
-- real item data to work with in test mode too. The trinket is included specifically so the
-- two-slot comparison logic in GetEquippedForUnit (rings/trinkets check both slots and show
-- whichever is weaker) has something to actually exercise — the three weapons are all
-- single-slot. Safe to use for testing regardless: everything that matters (no broadcast, no
-- chat announce, no loot history entry, no trade reminder) is gated on the rollID being a test
-- roll (see IsTestRoll), not on whether the item link itself is real. "(TEST)" sits inside the
-- hyperlink's own label so it shows up wherever the link is displayed as text, without breaking
-- GameTooltip:SetHyperlink (which ignores the label and looks up the real item by ID) or
-- IsRealItemLink.
local TEST_ITEMS = {
    "|cffff8000|Hitem:17182:0:0:0:0:0:0:0:0:0:0:0|h[Sulfuras, Hand von Ragnaros] (TEST)|h|r",
    "|cffff8000|Hitem:19019:0:0:0:0:0:0:0:0:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker] (TEST)|h|r",
    "|cffff8000|Hitem:22691:0:0:0:0:0:0:0:0:0:0:0|h[Corrupted Ashbringer] (TEST)|h|r",
    "|cffa335ee|Hitem:12938:0:0:0:0:0:0:0:0:0:0:0|h[Hand of Justice] (TEST)|h|r",
}

-- Fixed rollID range used by the Test buttons: TEST_ROLL_ID .. TEST_ROLL_ID + TEST_ITEM_COUNT -
-- 1, one per simulated item (see TEST_ITEMS). Kept separate from real, server-issued rollIDs so
-- test votes/assignments never collide with a live roll, and so the vote/assign/announce logic
-- below can special-case them: no addon-channel broadcast, no raid-chat spam, no permanent
-- loot-history entry — testing must stay entirely local to the tester's client.
local TEST_ROLL_ID    = 99999
local TEST_ITEM_COUNT = #TEST_ITEMS

-- Manually-added items (see LC.StartManualRoll) get their own rollID range, well clear of both
-- real server-issued rollIDs and the fixed TEST_ROLL_ID block above — each item /kart add starts
-- increments past the last one used, since (unlike the 4 fixed test slots) any number of these
-- can exist. Already comfortably outside IsTestRoll's range (99999..100002), so no separate
-- IsManualRoll check is needed anywhere — AddPendingTrade's existing IsTestRoll guard already
-- treats these as real rolls, which is exactly the wanted behavior (unlike test rolls, they
-- should be tradeable).
local MANUAL_ROLL_ID_BASE = 500000
LC.nextManualRollID = LC.nextManualRollID or MANUAL_ROLL_ID_BASE

-- Which mode (true = council/master, false = looter) last actually (re)populated the test data
-- in LC.StartTest — nil until the first test run. Lets StartTest tell "the OTHER test window is
-- still open, don't wipe its data out from under it" apart from "the SAME window got re-clicked,
-- treat that as an explicit restart" (see the sessionActive/suppressReset comment in StartTest).
LC.testSessionShowCouncil = nil

function LC.IsTestRoll(rollID)
    return rollID ~= nil and rollID >= TEST_ROLL_ID and rollID < TEST_ROLL_ID + TEST_ITEM_COUNT
end

-- Preset accent colors per button position
local BUTTON_COLORS = {
    {r=1.0,  g=0.15, b=0.0 },
    {r=0.0,  g=0.85, b=0.25},
    {r=0.2,  g=0.4,  b=1.0 },
    {r=0.9,  g=0.75, b=0.0 },
    {r=0.55, g=0.55, b=0.55},
    {r=0.7,  g=0.3,  b=0.9 },
}

-- Native icon textures used as small chips on vote buttons/pills, one per button *position* (not
-- tied to label text, since labels are leader-configurable free text — see GetButtonConfig). All
-- five are Blizzard's own default group-loot icons, reused purely because they already ship with
-- the client and render correctly at small sizes — Unicode symbol glyphs (★ ▲ etc.) were
-- considered and rejected: WoW's default game fonts render most of the Geometric Shapes/Dingbats
-- blocks as an empty "tofu" box (the reason row.councilVoteBtn.text below is ASCII-only already).
local VOTE_ICON_TEXTURES = {
    "Interface\\Buttons\\UI-GroupLoot-Dice-Up",   -- 1: strongest want (BIS)
    "Interface\\Buttons\\UI-GroupLoot-Coin-Up",   -- 2: secondary want (Upgrade)
    "Interface\\Buttons\\UI-GroupLoot-DE-Up",     -- 3: alternate use (Offspec)
    "Interface\\COMMON\\help-i",                  -- 4: catch-all (Sonstiges)
    "Interface\\Buttons\\UI-GroupLoot-Pass-Up",   -- 5: Pass
}
function LC.GetVoteIconTexture(index)
    return VOTE_ICON_TEXTURES[index] or VOTE_ICON_TEXTURES[#VOTE_ICON_TEXTURES]
end

-- Round class icon (the same atlas used by default raid/party frames) so a council-row candidate's
-- class reads at a glance without parsing the class-coloured name text.
function LC.SetClassIconTexture(tex, classFile)
    if not (classFile and CLASS_ICON_TEXCOORDS and CLASS_ICON_TEXCOORDS[classFile]) then
        tex:Hide()
        return
    end
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circle")
    tex:SetTexCoord(unpack(CLASS_ICON_TEXCOORDS[classFile]))
    tex:Show()
end

-- =====================================================================
--  Helpers
-- =====================================================================

-- Vote-button labels/colors are authoritative from the raid leader (LC.raidConfig), so every
-- raider's vote index maps to the SAME label in everyone's UI. The leader always uses their own
-- local setting directly (they ARE the source of truth); everyone else uses the synced value,
-- falling back to their own local setting only when solo / not yet synced (e.g. testing).
function LC.GetButtonConfig()
    local raw
    if UnitIsGroupLeader("player") or not (LC.raidConfig and LC.raidConfig.buttonLabels) then
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or KART.L.LC_DEFAULT_BUTTONS
    else
        raw = LC.raidConfig.buttonLabels
    end
    local parts = KART.SplitString(raw, ";")
    local result = {}
    for i, label in ipairs(parts) do
        local trimmed = KART.TrimString(label)
        if trimmed ~= "" and #result < 6 then
            local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
            table.insert(result, {label = trimmed, r = col.r, g = col.g, b = col.b})
        end
    end
    if #result == 0 then
        for i, label in ipairs(KART.SplitString(KART.L.LC_DEFAULT_BUTTONS, ";")) do
            local col = BUTTON_COLORS[i] or BUTTON_COLORS[6]
            table.insert(result, {label = label, r = col.r, g = col.g, b = col.b})
        end
    end
    return result
end

-- Only the leader's own edits are authoritative; this just re-broadcasts them to the raid.
-- (Non-leaders calling this would have no effect, since BroadcastRaidConfig no-ops for them.)
function LC.UpdateCouncilCache()
    LC.BroadcastRaidConfig()
end

function LC.IsCouncil()
    if UnitIsGroupLeader("player") then return true end
    local myKey = (KART.Identity.ResolvePlayer("player"))
    return LC.CouncilNamesTable[myKey] == true
end

-- Whether senderKey (already resolved off CHAT_MSG_ADDON's sender, see Core.lua) currently holds
-- council status — used to validate the sender of messages that grant real authority (LC_RESULT
-- logs a permanent history entry and fires the "you win" popup; LC_ONOTE overwrites a persistent
-- officer note) before acting on them. Resolving to a live unit first, rather than trusting the
-- key alone, matters because CHAT_MSG_ADDON also delivers whispers: someone not currently in our
-- group is never authorized, even if their key happens to match an entry in CouncilNamesTable.
function LC.IsSenderCouncil(senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    if not unit then return false end
    if UnitIsGroupLeader(unit) then return true end
    return LC.CouncilNamesTable[senderKey] == true
end

function LC.GetChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

function LC.SendLC(msg)
    if IsInGroup() then
        C_ChatInfo.SendAddonMessage("KART", msg, LC.GetChannel())
    end
end

-- Minimum item quality is authoritative from the raid leader, same reasoning as GetButtonConfig.
-- NOTE: this does NOT gate Auto-Pass (see OnStartLootRoll) — that stays a personal preference.
function LC.GetRaidMinQuality()
    if UnitIsGroupLeader("player") then
        return KART_Settings.lcMinQuality or 4
    end
    return (LC.raidConfig and LC.raidConfig.minQuality) or 4
end

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

-- The designated lootmaster (trimmed, lowercase, "" = none) — same authority reasoning as
-- GetButtonConfig/GetRaidMinQuality: only the raid leader's own local setting is authoritative,
-- everyone else (including the designated lootmaster themselves) goes by the synced value. This
-- is deliberately NOT a personal toggle like lcAutoPass — see LC.OnStartLootRoll, which overrides
-- a raider's own Auto-Pass preference when they are this person, precisely so it can't be turned
-- off by anyone except the raid leader reassigning it.
--
-- The stored value can be either a character short name OR a Northern Sky Raid Tools nickname —
-- LC.IsMe (below) is what actually resolves it against the local player, trying both.

-- Resolves free-typed config text (a council-list entry, or the lootmaster field) to a stable
-- key via KART.Identity.ResolvePlayer, trimming first. Returns nil for blank text. Shared by
-- LC.HandleConfig (a received LC_CONFIG broadcast) and LC.GetLootmaster's raid-leader branch
-- below (the leader's own local settings, resolved fresh on every read rather than cached,
-- since the leader never receives its own broadcast to trigger HandleConfig).
function LC.ResolveConfigName(text)
    local trimmed = KART.TrimString(text or "")
    if trimmed == "" then return nil end
    return (KART.Identity.ResolvePlayer(trimmed))
end

function LC.GetLootmaster()
    if UnitIsGroupLeader("player") then
        return LC.ResolveConfigName(KART_Settings.lcLootmaster) or ""
    end
    return (LC.raidConfig and LC.raidConfig.lootmaster) or ""
end

-- Whether configuredKey (a resolved KART.Identity key, see LC.GetLootmaster/LC.ResolveConfigName)
-- identifies the local player. Resolution (character short name vs. Northern Sky Raid Tools
-- nickname, see KART.GetNickname in Utils.lua) already happened upstream when the key was
-- produced, so a raid leader can name a *person* once ("kandera") instead of re-typing the field
-- whenever that person switches characters — every alt just needs the same NSRT nickname set,
-- which raiders already do for the addon's other nickname-aware features.
function LC.IsMe(configuredKey)
    if not configuredKey or configuredKey == "" then return false end
    return (KART.Identity.ResolvePlayer("player")) == configuredKey
end

-- Random 1-100 rolls are an opt-in raid-wide feature (analogous to RCLootCouncil's Need roll),
-- same authority reasoning as GetButtonConfig/GetRaidMinQuality.
function LC.GetRollsEnabled()
    -- Same fallback shape as GetButtonConfig: trust our own local setting when solo/not yet
    -- synced too, not just when we're actually the leader — otherwise UnitIsGroupLeader("player")
    -- being false while ungrouped (e.g. solo testing) would always read as "rolls off", no
    -- matter what the checkbox says, since LC.raidConfig.rollsEnabled never gets synced there.
    if UnitIsGroupLeader("player") or not (LC.raidConfig and LC.raidConfig.rollsEnabled ~= nil) then
        return KART_Settings.lcRollsEnabled == true
    end
    return LC.raidConfig.rollsEnabled == true
end

-- Sends the leader's authoritative settings (min quality, vote-button labels, rolls toggle,
-- council member list) to the raid so every client interprets votes/roles identically. No-ops
-- for non-leaders. Council members stays last in the payload since it's free text (raider names
-- separated by semicolons, not colons) — everything after the rolls flag is captured greedily.
--
-- SendAddonMessage payloads are capped at 255 bytes by the underlying chat protocol. Button
-- labels (up to 128 chars) plus a large council list (up to 255 chars, per its editbox's
-- SetMaxLetters) can together exceed that, and a transport-truncated message can make
-- HandleConfig's anchored payload pattern fail to match on every other client, leaving them
-- silently stuck on stale config. Trim the council list — the field most likely to grow large —
-- to whatever whole entries fit instead, and tell the leader locally so they know to shorten it.
local ADDON_MSG_MAX_BYTES = 255
function LC.BroadcastRaidConfig()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    local minQ     = KART_Settings.lcMinQuality or 4
    local buttons  = KART_Settings.lcButtonLabels or ""
    local rolls    = KART_Settings.lcRollsEnabled and "1" or "0"
    local lootmaster = KART.TrimString(KART_Settings.lcLootmaster or ""):match("([^%-]+)") or ""
    local council  = KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_CONFIG:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":"
    local budget = ADDON_MSG_MAX_BYTES - #prefix
    if #council > math.max(budget, 0) then
        council = (budget > 0 and council:sub(1, budget):match("^(.*);")) or ""
        print("|cffff0000KART:|r " .. (KART.L.LC_CONFIG_TRUNCATED or "Council member list too long, truncated for broadcast."))
    end
    LC.SendLC(prefix .. council)
end

-- Applies a raid-config broadcast from the leader (called from Core.lua CHAT_MSG_ADDON). Only
-- accepted from the actual current raid/party leader — otherwise a forged LC_CONFIG could add the
-- sender's own name to CouncilNamesTable below and self-promote to council on every client.
function LC.HandleConfig(payload, senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    if not unit or not UnitIsGroupLeader(unit) then return end

    local minQ, buttons, rolls, lootmaster, council = payload:match("^(%d+):([^:]*):([01]):([^:]*):(.*)$")
    if not minQ then return end

    LC.raidConfig.minQuality    = tonumber(minQ) or 4
    LC.raidConfig.buttonLabels  = buttons
    LC.raidConfig.rollsEnabled  = (rolls == "1")
    LC.raidConfig.lootmaster    = LC.ResolveConfigName(lootmaster) or ""
    LC.raidConfig.councilMembers = council or ""

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString(council or "", ";")) do
        local key = LC.ResolveConfigName(name)
        if key then LC.CouncilNamesTable[key] = true end
    end
end

-- GROUP_ROSTER_UPDATE fires in bursts during mass-invite/raid formation, and re-scanning every
-- pending entry on every single firing burns CPU for no benefit — same leading-edge throttle
-- pattern as KART.HandleAutoPromoteThrottled in GroupLogic.lua.
local isPendingResolutionThrottled = false
function LC.RetryPendingResolutionsThrottled()
    if isPendingResolutionThrottled then return end
    isPendingResolutionThrottled = true
    C_Timer.After(1, function()
        isPendingResolutionThrottled = false
        LC.RetryPendingResolutions()
    end)
end

-- Re-attempts resolution for every council-list/lootmaster entry still stuck on plain text (see
-- KART.Identity.IsResolvedKey), and migrates any KART_LCOfficerNotes entry still under its legacy
-- short-name key — both cases just mean "this person hadn't been seen yet" at the time they were
-- first parsed. Promotes them to a real key in place; still-unresolvable entries are left alone
-- and retried again next time the roster changes.
function LC.RetryPendingResolutions()
    -- Collect first, mutate second — Lua's pairs()/next() traversal is undefined if a new key
    -- (not already present) is added to the table mid-loop, which LC.CouncilNamesTable[key] = true
    -- below would otherwise do for every newly-resolved entry.
    local pendingCouncilEntries = {}
    for pendingText in pairs(LC.CouncilNamesTable) do
        if not KART.Identity.IsResolvedKey(pendingText) then
            table.insert(pendingCouncilEntries, pendingText)
        end
    end
    for _, pendingText in ipairs(pendingCouncilEntries) do
        local key = LC.ResolveConfigName(pendingText)
        if key and KART.Identity.IsResolvedKey(key) then
            LC.CouncilNamesTable[pendingText] = nil
            LC.CouncilNamesTable[key] = true
        end
    end

    if LC.raidConfig and LC.raidConfig.lootmaster and not KART.Identity.IsResolvedKey(LC.raidConfig.lootmaster) then
        local key = LC.ResolveConfigName(LC.raidConfig.lootmaster)
        if key and KART.Identity.IsResolvedKey(key) then
            LC.raidConfig.lootmaster = key
        end
    end

    -- Same collect-first reasoning: LC.MigrateOfficerNoteKey adds a new key to KART_LCOfficerNotes
    -- on a successful migration, which is unsafe to do while pairs() is still traversing that
    -- same table.
    local legacyOfficerNoteKeys = {}
    for oldKey in pairs(KART_LCOfficerNotes) do
        table.insert(legacyOfficerNoteKeys, oldKey)
    end
    for _, oldKey in ipairs(legacyOfficerNoteKeys) do
        KART.LC.OfficerNotes.MigrateOfficerNoteKey(oldKey)
    end
end

-- Answers an "LC_STATE_REQ" broadcast from a joining/reloading peer with the current session flag
-- and, if a session is active, the full raid config — a one-shot pull instead of waiting for the
-- leader's own roster-change handler to happen to fire (see LC.CheckRaidJoin). Only the actual
-- leader replies, same authority rule as LC.BroadcastRaidConfig itself.
function LC.HandleStateRequest()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    LC.SendLC("LC_ACTIVE:" .. (LC.sessionActive and "1" or "0"))
    if LC.sessionActive then LC.BroadcastRaidConfig() end
end

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

-- Hand-rolled dialog instead of StaticPopupDialogs' hasEditBox: retail's StaticPopup system
-- (routed through Blizzard_StaticPopup_Game/GameDialog.lua) doesn't reliably expose the edit box
-- as self.editBox to its callbacks — same fix already applied to OfficerNotes.ShowOfficerNoteDialog
-- in LootCouncilOfficerNotes.lua (see its comment for the full "attempt to index field 'editBox'
-- (a nil value)" story). Owning the frame ourselves means the edit box reference always exists.
local syncTargetDialog

function LC.ShowSyncTargetDialog()
    if not syncTargetDialog then
        local f = CreateFrame("Frame", "KART_LCSyncTargetDialog", UIParent, "BackdropTemplate")
        f:SetSize(300, 120)
        f:SetPoint("CENTER")
        KART.RegisterStrataFrame(f, true)
        KART.ApplyPopupArtwork(f)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, f:GetName())

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetWidth(270)
        f.title:SetWordWrap(true)

        f.editBox = KART.CreateStyledEditBox(f, "KART_LCSyncTargetEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetMaxLetters(48)
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            local name = f.editBox:GetText()
            name = name and name:match("^%s*(.-)%s*$") or ""
            if name == "" then
                UIErrorsFrame:AddMessage(KART.L.LC_SYNC_TARGET_EMPTY, 1, 0.1, 0.1, 1, 3)
                return
            end
            f:Hide()
            LC.SendSettingsSync(name)
        end

        local btnOK = KART.CreateModernButton(f, ACCEPT)
        btnOK:SetSize(120, 26)
        btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        btnOK:SetScript("OnClick", accept)

        local btnCancel = KART.CreateModernButton(f, CANCEL)
        btnCancel:SetSize(120, 26)
        btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)

        syncTargetDialog = f
    end

    local f = syncTargetDialog
    f.title:SetText(KART.L.LC_SYNC_TARGET_PROMPT)
    f.editBox:SetText("")
    f:Show()
    f.editBox:SetFocus()
end

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

-- Test mode uses a plain coloured string as a fake item; guard against SetHyperlink on non-links.
function LC.IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Pulls the (r,g,b) quality colour out of the leading |cAARRGGBB escape of an item link/coloured
-- string — works uniformly for real item hyperlinks (colour = actual item quality) and test mode's
-- fake coloured-string items, so tab swatches never need to special-case which kind it is.
function LC.ParseItemColor(link)
    local hex = type(link) == "string" and link:match("|c(%x%x%x%x%x%x%x%x)")
    if not hex then return 0.5, 0.5, 0.5 end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- Counts how many people have voted on rollID so far, and a rough denominator (current group
-- size, at least 1) for a "voted/total" badge. The denominator is approximate — not everyone in
-- the group necessarily has KART or is eligible — but good enough for an at-a-glance indicator.
function LC.CountVotes(rollID)
    local voted = 0
    for _ in pairs(LC.votes[rollID] or {}) do voted = voted + 1 end
    return voted, math.max(GetNumGroupMembers(), 1)
end

-- Colored label for an item quality index (0=Poor .. 5=Legendary), used by the min-quality filter UI.
function LC.QualityLabel(q)
    local name = (KART.L and KART.L["LC_QUALITY_" .. q]) or tostring(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] ---@diagnostic disable-line: undefined-global
    if c then
        return c.hex .. name .. "|r"
    end
    return name
end

-- Localized label for the "voted item display" button (KART_Settings.lcVotedItemDisplay) —
-- mirrors LC.QualityLabel's lookup pattern, just without quality-color coding (there's no
-- natural color axis for full/shrink/hide the way there is for item quality).
function LC.VotedItemDisplayLabel(mode)
    return (KART.L and KART.L["LC_VOTED_DISPLAY_" .. (mode or "full"):upper()]) or mode or "full"
end

-- =====================================================================
--  Session Prompt  (shown to RL when joining a raid)
-- =====================================================================

function LC.ShowSessionPrompt()
    if LC.sessionPromptFrame then
        LC.sessionPromptFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "KART_LCSessionPrompt", UIParent, "BackdropTemplate")
    f:SetSize(310, 115)
    f:SetPoint("CENTER", 0, 120)
    KART.RegisterStrataFrame(f, true)
    KART.ApplyPopupArtwork(f)
    table.insert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText(KART.L.LC_PROMPT_TITLE)

    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.desc:SetPoint("TOP", 0, -36)
    f.desc:SetText(KART.L.LC_PROMPT_TEXT)
    f.desc:SetWidth(285)
    f.desc:SetWordWrap(true)

    local btnYes = KART.CreateModernButton(f, KART.L.LC_PROMPT_YES)
    btnYes:SetSize(135, 28)
    btnYes:SetPoint("BOTTOMLEFT", 15, 12)
    btnYes:SetScript("OnClick", function()
        LC.SetSessionActive(true)
        f:Hide()
    end)

    local btnNo = KART.CreateModernButton(f, KART.L.LC_PROMPT_NO)
    btnNo:SetSize(135, 28)
    btnNo:SetPoint("BOTTOMRIGHT", -15, 12)
    btnNo:SetScript("OnClick", function()
        LC.SetSessionActive(false)
        f:Hide()
    end)

    LC.sessionPromptFrame = f
end

function LC.SetSessionActive(active)
    LC.sessionActive = active
    LC.SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if active then
        LC.BroadcastRaidConfig()
    else
        -- Ending the session forgets every tracked roll so the next boss starts clean instead of
        -- showing leftover tabs/votes from this one (see LC.Trade.ClearRollState).
        for i = #LC.councilTabs, 1, -1 do
            LC.Trade.ClearRollState(LC.councilTabs[i])
        end
        for i = #LC.voteListRolls, 1, -1 do
            LC.Trade.ClearRollState(LC.voteListRolls[i])
        end
        wipe(LC.councilTabs)
        wipe(LC.voteListRolls)
        LC.activeRollID = nil
        if LC.councilPanel then LC.councilPanel:Hide() end
        if LC.voteListFrame then LC.voteListFrame:Hide() end
    end
    print("|cff00ff00KART:|r " .. (active and KART.L.LC_SESSION_ON or KART.L.LC_SESSION_OFF))
end

function LC.CheckRaidJoin()
    if not IsInRaid() then
        LC.promptedThisSession = false
        LC.sessionActive = false
        LC.historySyncRequested = false
        LC.stateSyncRequested = false
        return
    end
    if KART_Settings.lcModuleEnabled == false then return end

    -- Ask peers (once per raid join) for any loot-history entries logged while we weren't around.
    if not LC.historySyncRequested then
        LC.historySyncRequested = true
        KART.LH.RequestHistorySync()
    end

    -- Ask the raid leader (once per raid join/reload) for the current session-active flag and
    -- raid-wide config, so a late joiner or a /reload'd client is never stuck on stale defaults
    -- until the leader happens to notice a roster change (see LC.HandleStateRequest below) — same
    -- request/response shape as the loot-history catch-up above.
    if not LC.stateSyncRequested then
        LC.stateSyncRequested = true
        LC.SendLC("LC_STATE_REQ")
    end

    if not UnitIsGroupLeader("player") then return end

    -- Re-broadcast the authoritative config on every roster change so late joiners get it too.
    if LC.sessionActive then LC.BroadcastRaidConfig() end

    if LC.promptedThisSession then return end
    LC.promptedThisSession = true
    -- Small delay so the roster is fully settled before showing the prompt
    C_Timer.After(3, function()
        if IsInRaid() and UnitIsGroupLeader("player") then
            LC.ShowSessionPrompt()
        end
    end)
end

-- =====================================================================
--  START_LOOT_ROLL handler  (called from Core.lua)
-- =====================================================================

-- GetLootRollItemLink(rollID) can return nil for a moment right when the roll starts (most common
-- for a brand-new item whose data hasn't finished propagating client-side yet). Retries a handful
-- of times with backoff instead of permanently giving up — bails early if rollID's entry was
-- resolved by some other path in the meantime, or cleared entirely (tab closed/session ended, see
-- LC.Trade.ClearRollState), so a long-since-irrelevant timer never resurrects a forgotten roll.
local function ResolveRollItemLink(rollID, attempt)
    if LC.rollItems[rollID] ~= "???" then return end
    attempt = attempt or 1
    local link = GetLootRollItemLink(rollID)
    if link then
        LC.rollItems[rollID] = link
        LC.Vote.RefreshVoteListRows()
        if LC.councilPanel and LC.councilPanel:IsShown() then
            KART.LC.Council.RefreshCouncilRows()
            KART.LC.Council.RefreshCouncilTabs()
        end
    elseif attempt < 8 then
        C_Timer.After(0.25 * attempt, function() ResolveRollItemLink(rollID, attempt + 1) end)
    end
end

-- Claims rollID by whatever roll type is actually available, strongest first — used only for the
-- designated lootmaster (see LC.GetLootmaster), who must win every item so they can hand it to
-- whoever the council actually decided on via trade (see LC.pendingTrades). Never passes.
local function ForceWinRoll(rollID)
    local _, _, _, _, _, canNeed, canGreed, canDisenchant, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if canNeed then
        RollOnLoot(rollID, 1)
    elseif canGreed then
        RollOnLoot(rollID, 2)
    elseif canDisenchant then
        RollOnLoot(rollID, 3)
    elseif canTransmog then
        RollOnLoot(rollID, 4) -- roll type 4 = Transmog; Blizzard doesn't expose a named constant for it
    end
end

-- Blizzard's rollID can be reused for a genuinely different item before the previous roll's
-- state (votes, deadline, tab / vote-list entry) under that same ID has been cleared — most
-- commonly several trash corpses looted within the same second. Called with the incoming roll's
-- bare itemID whenever a roll starts (locally via OnStartLootRoll, or via a received LC_START);
-- if a DIFFERENT real item is already tracked under this rollID, wipes its stale state first so
-- the new roll starts clean instead of silently inheriting old votes or reusing an old tab/row
-- for the wrong item. newItemID == "" means "not resolved yet" — never purge on unresolved data,
-- only on a confirmed different item (see the LC_RESULT-side fix this complements, in
-- Trade.HandleResult, for the other half of this same rollID-collision class of bug).
local function PurgeStaleRoll(rollID, newItemID)
    if not newItemID or newItemID == "" then return end
    local oldLink = LC.rollItems[rollID]
    if not LC.IsRealItemLink(oldLink) then return end
    local oldItemID = oldLink:match("item:(%d+)")
    if not oldItemID or oldItemID == newItemID then return end

    for i = #LC.voteListRolls, 1, -1 do
        if LC.voteListRolls[i] == rollID then table.remove(LC.voteListRolls, i) end
    end
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    if LC.activeRollID == rollID then LC.activeRollID = nil end
    LC.Trade.ClearRollState(rollID)
end

function LC.OnStartLootRoll(rollID)
    if KART_Settings.lcModuleEnabled == false then return end
    if not LC.sessionActive then return end

    -- Quality/bind data first — the lootmaster branch below depends on it. bindOnPickUp comes
    -- from GetLootRollItemInfo (reliable even for uncached items); classID via GetItemInfoInstant
    -- for the same reason (GetItemInfo returns nil until the item is cached).
    local _, _, _, quality, bindOnPickUp = GetLootRollItemInfo(rollID)
    local itemLink = GetLootRollItemLink(rollID)
    local classID = LC.IsRealItemLink(itemLink) and select(6, C_Item.GetItemInfoInstant(itemLink))
    -- Miscellaneous (classID 15: toys, pets, mounts, housing decor): never rarity-gated, since
    -- it's virtually always Common/Uncommon regardless of how desirable it is.
    local isCollectible = (classID == 15)
    local councilEngages = isCollectible or not (quality and quality < LC.GetRaidMinQuality())

    local lootmaster = LC.GetLootmaster()
    local isLootmaster = LC.IsMe(lootmaster)
    if isLootmaster and councilEngages and bindOnPickUp and not isCollectible then
        -- The lootmaster only needs to physically win items they must later hand out through
        -- Blizzard's 2-hour BoP trade window: council-relevant, BoP, non-collectible gear.
        ForceWinRoll(rollID)
        -- Blizzard's 2-hour Bind-on-Pickup trade window starts now, not whenever Council later
        -- decides a winner — see LC.CheckTradeTimeouts, which measures from this timestamp.
        LC.rollLootedAt = LC.rollLootedAt or {}
        LC.rollLootedAt[rollID] = GetTime()
    elseif isLootmaster then
        -- Everything the lootmaster does NOT force-win (collectibles, BoE/non-binding items,
        -- sub-threshold drops) they ALWAYS pass — deliberately independent of their own
        -- Auto-Pass setting, so those items cleanly go to the raid's normal rolls instead of
        -- silently piling up in the lootmaster's bags.
        RollOnLoot(rollID, 0)
    elseif KART_Settings.lcAutoPass then
        -- Auto-Pass is a personal preference and is intentionally independent of the raid's
        -- min-quality setting (that setting only gates whether Council itself engages).
        RollOnLoot(rollID, 0)
    end

    -- Below the raid-wide minimum rarity (and not a collectible): let Blizzard's own roll UI
    -- handle it, untouched.
    if not councilEngages then return end

    local newItemID = LC.IsRealItemLink(itemLink) and (itemLink:match("item:(%d+)") or "") or ""
    PurgeStaleRoll(rollID, newItemID)

    LC.rollItems[rollID] = itemLink or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
    LC.votes[rollID]     = LC.votes[rollID] or {}

    -- Opt-in random 1-100 roll (RCLootCouncil-style "Need roll"), purely informational. Every
    -- eligible raider's client independently receives this same START_LOOT_ROLL event, so this
    -- is the one place that reliably runs once per roll for everyone, council members included.
    if LC.GetRollsEnabled() then
        local myKey  = (KART.Identity.ResolvePlayer("player"))
        local myRoll = math.random(1, 100)
        LC.rolls[rollID] = LC.rolls[rollID] or {}
        LC.rolls[rollID][myKey] = myRoll
        LC.SendLC("LC_ROLL:" .. rollID .. ":" .. myRoll)
    end

    if UnitIsGroupLeader("player") then
        local secs = KART_Settings.lcVoteSeconds or 20
        LC.SendLC("LC_START:" .. rollID .. ":" .. secs .. ":" .. newItemID)
        KART.LC.Council.ShowCouncilPanel(rollID, secs)
    end
end

LC.votedByMe = LC.votedByMe or {} -- [rollID] = true once WE cast a vote for it (tracked by rollID,
                                   -- not by row, since rows get recycled/reindexed as items expire)
LC.votedNoteByMe = LC.votedNoteByMe or {} -- [rollID] = the note text WE typed before voting, kept
                                   -- around purely so the "you voted" state can still show it —
                                   -- otherwise it vanishes the moment the note box hides, even
                                   -- though the raider clearly remembers writing it.

-- rollID -> shortName of whoever this roll has already been awarded to (guards against accidental
-- double-assignment when the assign menu is used more than once for the same item).
LC.assignedWinners = LC.assignedWinners or {}

StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] = { ---@diagnostic disable-line: undefined-global
    text = "Already assigned.", -- unconditionally overwritten with KART.L.LC_REASSIGN_CONFIRM_TEXT in LC.Trade.AssignWinner below
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =====================================================================
--  Addon Message Handlers  (called from Core.lua CHAT_MSG_ADDON)
-- =====================================================================

-- Sender-authorization helper for messages that carry raid-wide authority: resolving to a
-- live unit first (rather than trusting the key alone) matters because CHAT_MSG_ADDON also
-- delivers whispers — someone not currently in our group is never authorized.
local function IsSenderGroupLeader(senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    return unit ~= nil and UnitIsGroupLeader(unit)
end

function LC.HandleActive(value, senderKey)
    -- Only the raid leader may flip the session flag — otherwise any group member could
    -- toggle Loot Council on/off for the whole raid with a forged LC_ACTIVE.
    if not IsSenderGroupLeader(senderKey) then return end
    LC.sessionActive = (value == "1")
end

function LC.HandleStart(payload, senderKey)
    -- Only the leader broadcasts LC_START (see OnStartLootRoll) — reject forgeries that
    -- would pop fake vote windows on every client.
    if not IsSenderGroupLeader(senderKey) then return end
    -- payload = "rollID:seconds:itemID"
    local rollID, secs, itemID = payload:match("^(%d+):(%d+):?(%d*)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID then return end

    PurgeStaleRoll(rollID, itemID)

    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID] or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
    -- Auto-Pass already runs unconditionally in OnStartLootRoll for this player's own roll,
    -- so there's nothing left to do here for that.

    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
    else
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end

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

        LC.SendLC("LC_MANUAL_START:" .. rollID .. ":" .. seconds .. ":" .. itemLink)

        -- SendAddonMessage never echoes back to its own sender, so the lootmaster has to open
        -- their own window locally, same as HandleStart does for every other client.
        if LC.IsCouncil() then
            KART.LC.Council.ShowCouncilPanel(rollID, seconds)
        else
            LC.Vote.ShowVotePopup(rollID, itemLink, seconds)
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
function LC.HandleManualStart(payload, senderKey)
    -- Only the designated lootmaster legitimately sends manual rolls (see LC.StartManualRoll).
    -- A client without a synced raid config has lootmaster == "" and rejects — the state
    -- request on raid join (LC_STATE_REQ) closes that gap.
    local lootmaster = LC.GetLootmaster()
    if lootmaster == "" or senderKey ~= lootmaster then return end
    local rollID, secs, itemLink = payload:match("^(%d+):(%d+):(.*)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID or not itemLink or itemLink == "" then return end

    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = LC.rollItems[rollID] or itemLink

    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
    else
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end

-- =====================================================================
--  Test Function
-- =====================================================================

-- mode: "looter" = always show vote popup; "master" = always show council panel; nil = auto-detect
function LC.StartTest(mode)
    local buttons = LC.GetButtonConfig()

    local showCouncil
    if mode == "looter" then
        showCouncil = false
    elseif mode == "master" then
        showCouncil = true
    else
        -- Auto: follow actual role
        showCouncil = LC.IsCouncil() and IsInGroup()
    end

    -- A test session is "active" if EITHER window still has test rolls tracked. If so, this
    -- click just adds/refreshes the OTHER window on top of it — it must never reset the shared
    -- item/vote data, since that data is exactly what the already-open window is displaying.
    -- Clicking "Test Looter" while "Test Master" is still showing its tabs (or vice versa) used
    -- to wipe LC.councilTabs/LC.voteListRolls out from under the other, already-visible window
    -- without ever telling it to re-render — the stale tabs would then only get cleaned up (i.e.
    -- appear to "vanish") whenever something else happened to trigger a refresh later, such as a
    -- vote coming in, which made it look like voting itself was breaking the council panel.
    local sessionActive = false
    for _, rid in ipairs(LC.voteListRolls) do
        if LC.IsTestRoll(rid) then sessionActive = true break end
    end
    if not sessionActive then
        for _, rid in ipairs(LC.councilTabs) do
            if LC.IsTestRoll(rid) then sessionActive = true break end
        end
    end

    -- sessionActive alone isn't enough to decide whether to keep old test data: every click (see
    -- the ShowVotePopup/ShowCouncilPanel loop below) refreshes each test item's deadline to
    -- now+seconds regardless of sessionActive, so a test roll never actually expires as long as
    -- someone keeps clicking a Test button — sessionActive would stay true forever, permanently
    -- skipping the reset below and making every vote "stick" across restarts of the SAME window.
    -- Only suppress the reset when a DIFFERENT window's mode is what's actually keeping the
    -- session alive (the looter+master-open-simultaneously scenario this check exists for, per
    -- the comment above) — re-clicking the SAME mode is always an explicit "start a fresh test".
    local suppressReset = sessionActive and LC.testSessionShowCouncil ~= nil and LC.testSessionShowCouncil ~= showCouncil
    LC.testSessionShowCouncil = showCouncil

    if not suppressReset then
        for itemIdx, testItem in ipairs(TEST_ITEMS) do
            local testRollID = TEST_ROLL_ID + (itemIdx - 1)

            LC.rollItems[testRollID]       = testItem
            LC.votes[testRollID]           = {}
            LC.rolls[testRollID]           = {}
            LC.councilVotes[testRollID]    = {}
            LC.assignedWinners[testRollID] = nil -- fresh test run, forget any winner assigned in a previous one
            LC.votedByMe[testRollID]       = nil -- forget our own vote from a previous test run too
            LC.councilTabsNew[testRollID]  = nil

            local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
            local myKey    = (KART.Identity.ResolvePlayer("player"))
            local rollsOn  = LC.GetRollsEnabled()
            if rollsOn and myShort ~= "" then
                LC.rolls[testRollID][myKey] = math.random(1, 100)
            end

            -- Pre-fill votes (and, if enabled, rolls) from current group members so the council
            -- panel looks populated
            if IsInGroup() then
                local isRaid  = IsInRaid()
                local numMem  = GetNumGroupMembers()
                local voteIdx = itemIdx -- offset per item so the fake votes aren't identical across items
                for i = 1, numMem do
                    local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
                    local name = UnitName(unit)
                    if name then
                        local short = name:match("([^%-]+)")
                        if short and short ~= myShort then
                            local key = (KART.Identity.ResolvePlayer(unit))
                            LC.votes[testRollID][key] = {idx = voteIdx, note = ""}
                            voteIdx = (voteIdx % #buttons) + 1
                            if rollsOn then LC.rolls[testRollID][key] = math.random(1, 100) end
                        end
                    end
                end
            end
        end
    end

    -- Kick off all test items at once: the vote list shows every one as its own row, and the
    -- council panel gets a tab per item — exactly like multiple real items dropping from a boss
    -- at nearly the same time.
    for itemIdx = 1, TEST_ITEM_COUNT do
        local testRollID = TEST_ROLL_ID + (itemIdx - 1)
        if showCouncil then
            KART.LC.Council.ShowCouncilPanel(testRollID, KART_Settings.lcVoteSeconds or 20)
        else
            LC.Vote.ShowVotePopup(testRollID, LC.rollItems[testRollID], KART_Settings.lcVoteSeconds or 20)
        end
    end

    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_TEST_STARTED, TEST_ITEM_COUNT))
end

-- =====================================================================
--  Settings Panel  (fills KART.LootCouncilPanel created by MainFrame.lua)
-- =====================================================================

-- Updates the role-status line inside the raid-wide settings box. Called on build, and whenever
-- the group roster changes (leadership can change without a UI interaction).
function LC.UpdateRoleStatusLabel()
    local lbl = KART.LC.RoleStatusLabel
    if not lbl then return end
    if UnitIsGroupLeader("player") then
        lbl:SetText(KART.L.LC_ROLE_STATUS_LEADER)
        lbl:SetTextColor(0.3, 0.9, 0.3)
    else
        lbl:SetText(KART.L.LC_ROLE_STATUS_MEMBER)
        lbl:SetTextColor(0.9, 0.7, 0.2)
    end
    -- The leader/member texts wrap to a different number of lines, so the box below needs to
    -- re-flow too (no-op on the very first call, before layoutRaidBox() has run yet).
    if LC.RelayoutRaidBox then LC.RelayoutRaidBox() end
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
    local prefsCard = KART.CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    prefsCard:SetSize(500, 215)
    KART.LC.SettingsCard = prefsCard

    -- Master switch: fully disables the module (e.g. during testing, or to avoid clashing with
    -- another loot addon like RCLootCouncil). Nothing below still runs when this is off.
    KART.LC.CbModuleEnabled = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCModuleEnabled",
        L.LC_SET_MODULE_ENABLED, "lcModuleEnabled", -15, nil, L.LC_DESC_MODULE_ENABLED)

    -- Personal preference — never overridden by the raid leader's settings.
    KART.LC.CbAutoPass = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCAutoPass",
        L.LC_SET_AUTOPASS, "lcAutoPass", -45, nil, L.LC_DESC_AUTOPASS)

    -- Personal preference, same reasoning as CbAutoPass above — the vote window's layout style
    -- is purely a display choice, so it's never synced from the raid leader. Slot -105: the next
    -- free step below the reserved Droptimizer slot at -75 (see Droptimizer.lua:128), inside
    -- this card.
    KART.LC.CbCompactVoteLayout = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCCompactVoteLayout",
        L.LC_SET_COMPACT_VOTE_LAYOUT, "lcVoteLayoutCompact", -105,
        function() LC.Vote.RefreshVoteListRowsIfShown() end, L.LC_DESC_COMPACT_VOTE_LAYOUT)

    -- Personal preference, same reasoning as CbCompactVoteLayout above — purely how names render
    -- on YOUR OWN council panel, never synced. Needs Northern Sky Raid Tools installed with a
    -- nickname set per character to have any visible effect (see KART.GetNickname); falls back to
    -- the character short name automatically otherwise. Slot -135: next free step below
    -- CbCompactVoteLayout, inside this card.
    KART.LC.CbShowNickNames = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCShowNickNames",
        L.LC_SET_SHOW_NICKNAMES, "lcShowNickNames", -135,
        function()
            if LC.councilPanel and LC.councilPanel:IsShown() then KART.LC.Council.RefreshCouncilRows() end
        end, L.LC_DESC_SHOW_NICKNAMES)

    -- Personal preference, same reasoning as CbCompactVoteLayout above — controls whether an
    -- already-voted item stays full-size, shrinks, or disappears entirely from YOUR OWN vote
    -- window (see Vote.GetVisibleRolls). Slot -175: next free step below CbShowNickNames, inside
    -- this card (card height bumped 165 -> 215 above to fit a 28px-tall button here instead of
    -- another checkbox row). Initial label is hardcoded to "full" — KART_Settings doesn't exist
    -- yet at file-load time, same reasoning as BtnMinQuality's own placeholder-text comment below;
    -- Core.lua's ADDON_LOADED handler syncs the real saved value once settings are loaded.
    KART.LC.BtnVotedItemDisplay = KART.CreateModernButton(
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

    -- Droptimizer gain% column toggle (KART.DT.CbModuleEnabled) is built here too, by
    -- Droptimizer.lua — see the reserved -75 slot there. Kept in its own file since it's a
    -- different module, but it's a personal preference like CbAutoPass above, so it lives next
    -- to it rather than getting its own settings tab.

    -- ================= Raid-wide settings box =================
    -- Everything in here only takes effect for the raid when YOU are the raid leader; otherwise
    -- the actual raid leader's values are used automatically. Visually set apart on purpose so
    -- nobody mistakes their own tweaks here for something that affects the current raid.
    local raidBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    raidBox:SetPoint("TOPLEFT", prefsCard, "BOTTOMLEFT", 0, -20)
    raidBox:SetSize(500, 362)
    raidBox:SetBackdrop({bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    raidBox:SetBackdropColor(0.5, 0.4, 0.05, 0.12)
    raidBox:SetBackdropBorderColor(0.5, 0.4, 0.05, 0.6)

    -- Title and role-status stacked on their own lines (not side-by-side) — kept simple even
    -- now that the box is 500px wide, since role-status text length varies a lot by locale.
    -- Positions for all of this are set by layoutRaidBox() further down, not here.
    local boxTitle = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    boxTitle:SetText(L.LC_RAIDWIDE_TITLE)
    boxTitle:SetTextColor(0.9, 0.75, 0.3)
    table.insert(KART.DynamicLabels, boxTitle)

    KART.LC.RoleStatusLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.RoleStatusLabel:SetWidth(460)
    KART.LC.RoleStatusLabel:SetJustifyH("LEFT")
    table.insert(KART.DynamicLabels, KART.LC.RoleStatusLabel)
    LC.UpdateRoleStatusLabel() -- sets the text before layoutRaidBox() first measures it

    local boxDivider = raidBox:CreateTexture(nil, "ARTWORK")
    boxDivider:SetColorTexture(0.5, 0.4, 0.05, 0.5)
    boxDivider:SetHeight(1)
    boxDivider:SetPoint("TOPRIGHT", -8, -38) -- Y overridden by layoutRaidBox(); X stays fixed

    KART.LC.SldVoteTimer = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_VOTE_TIMER, 5, 180, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    -- Independent from the main window's Content Font Size — the vote-list/council-panel grid
    -- layouts don't necessarily want the same size as the rest of the addon (see LC.ApplyFontSize).
    KART.LC.SldFontSize = KART.CreateSettingsSlider(
        raidBox, L.LC_SET_FONT_SIZE, 8, 20, "lcFontSize",
        -104, "KART_LCFontSizeSlider", L.LC_DESC_FONT_SIZE)
    -- No separate OnValueChanged hook needed: KART.CreateSettingsSlider's own OnValueChanged
    -- (Utils.lua) already calls KART.UpdateStyles() live during drag, which already calls
    -- LC.ApplyFontSize() (see Core.lua) — a second call here would just reapply the same sizes
    -- again on every drag tick for no extra effect.

    -- Opt-in random 1-100 roll per raider, shown as its own column in the council panel —
    -- analogous to RCLootCouncil's Need roll. Purely informational (see LC.Vote.HandleRoll).
    KART.LC.CbRollsEnabled = KART.CreateSettingsCheckbox(
        raidBox, "KART_LCRollsEnabled",
        L.LC_SET_ROLLS_ENABLED, "lcRollsEnabled", -140, LC.BroadcastRaidConfig, L.LC_DESC_ROLLS_ENABLED)

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
    table.insert(KART.DynamicLabels, lblButtons)

    KART.LC.ButtonLabelEditBox = KART.CreateStyledEditBox(raidBox, "KART_LCButtonLabels")
    local eb = KART.LC.ButtonLabelEditBox
    eb:SetSize(CONTENT_WIDTH, 28)
    eb:SetMaxLetters(128)
    eb:SetScript("OnTextChanged", function(self)
        if StripColons(self) then return end
        KART_Settings.lcButtonLabels = self:GetText()
        LC.BroadcastRaidConfig()
    end)

    local hint = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetWidth(CONTENT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.LC_SET_BUTTONS_HINT)
    hint:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hint)

    -- Council member names
    local lblCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblCouncil:SetWidth(CONTENT_WIDTH)
    lblCouncil:SetJustifyH("LEFT")
    lblCouncil:SetText(L.LC_SET_COUNCIL)
    table.insert(KART.DynamicLabels, lblCouncil)

    KART.LC.CouncilMembersEditBox = KART.CreateStyledEditBox(raidBox, "KART_LCCouncilMembers")
    local ebC = KART.LC.CouncilMembersEditBox
    ebC:SetSize(CONTENT_WIDTH, 28)
    ebC:SetMaxLetters(255)
    ebC:SetScript("OnTextChanged", function(self)
        if StripColons(self) then return end
        KART_Settings.lcCouncilMembers = self:GetText()
        LC.UpdateCouncilCache()
    end)

    local hintCouncil = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintCouncil:SetWidth(CONTENT_WIDTH)
    hintCouncil:SetJustifyH("LEFT")
    hintCouncil:SetText(L.LC_SET_COUNCIL_HINT)
    hintCouncil:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintCouncil)

    -- Subdued indicator for council-list entries not yet matched to a live player (see
    -- KART.Identity.IsResolvedKey/LC.RetryPendingResolutions) — hidden entirely once nothing is
    -- pending, so it never clutters the common case.
    KART.LC.CouncilPendingLabel = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    KART.LC.CouncilPendingLabel:SetWidth(CONTENT_WIDTH)
    KART.LC.CouncilPendingLabel:SetJustifyH("LEFT")
    KART.LC.CouncilPendingLabel:SetTextColor(0.85, 0.65, 0.15)
    table.insert(KART.DynamicLabels, KART.LC.CouncilPendingLabel)

    local function UpdateCouncilPendingLabel()
        local pendingCount = 0
        for pendingText in pairs(LC.CouncilNamesTable) do
            if not KART.Identity.IsResolvedKey(pendingText) then pendingCount = pendingCount + 1 end
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
    table.insert(KART.DynamicLabels, lblLootmaster)

    KART.LC.LootmasterEditBox = KART.CreateStyledEditBox(raidBox, "KART_LCLootmaster")
    local ebL = KART.LC.LootmasterEditBox
    ebL:SetSize(CONTENT_WIDTH, 28)
    ebL:SetMaxLetters(48)
    ebL:SetScript("OnTextChanged", function(self)
        if StripColons(self) then return end
        KART_Settings.lcLootmaster = self:GetText()
        LC.BroadcastRaidConfig()
    end)

    local hintLootmaster = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintLootmaster:SetWidth(CONTENT_WIDTH)
    hintLootmaster:SetJustifyH("LEFT")
    hintLootmaster:SetText(L.LC_SET_LOOTMASTER_HINT)
    hintLootmaster:SetTextColor(0.55, 0.55, 0.55)
    table.insert(KART.DynamicLabels, hintLootmaster)

    -- Minimum item quality that triggers the Loot Council flow (full width)
    local lblQuality = raidBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblQuality:SetWidth(CONTENT_WIDTH)
    lblQuality:SetJustifyH("LEFT")
    lblQuality:SetText(L.LC_SET_MIN_QUALITY)
    table.insert(KART.DynamicLabels, lblQuality)

    -- Placeholder text only — KART_Settings doesn't exist yet at file-load time.
    -- Core.lua's ADDON_LOADED handler syncs the real value once settings are loaded.
    KART.LC.BtnMinQuality = KART.CreateModernButton(raidBox, LC.QualityLabel(4), L.LC_DESC_MIN_QUALITY)
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
    KART.LC.BtnToggleSession = KART.CreateModernButton(raidBox, L.LC_BTN_TOGGLE, L.LC_DESC_TOGGLE)
    KART.LC.BtnToggleSession:SetSize(CONTENT_WIDTH, 28)
    KART.LC.BtnToggleSession:SetScript("OnClick", function()
        if not IsInRaid() then
            print("|cff00ff00KART:|r " .. KART.L.LC_RAID_ONLY)
        elseif UnitIsGroupLeader("player") then
            LC.SetSessionActive(not LC.sessionActive)
        else
            print("|cff00ff00KART:|r " .. KART.L.LC_NOT_LEADER)
        end
    end)

    KART.LC.BtnSyncSettings = KART.CreateModernButton(raidBox, L.LC_BTN_SYNC_SETTINGS, L.LC_DESC_SYNC_SETTINGS)
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
    KART.ApplyRoundedMask(raidBox, KART.Theme.CORNER_RADIUS_LG)
    LC.RelayoutRaidBox = layoutRaidBox
    KART.LC.RaidBox = raidBox -- measured by KART.UpdateScrollRange (dynamic panel height)
    -- ================= /Raid-wide settings box =================

    -- Two test buttons side by side: Looter view / Lootmaster view.
    -- Anchored to raidBox's own BOTTOMLEFT (not a fixed offset from parent) so they always sit
    -- right below the box regardless of how tall it ends up being — the box's height depends on
    -- wrapped label text, which can vary by locale and by the user's chosen font/size.
    KART.LC.BtnTestLooter = KART.CreateModernButton(parent, L.LC_BTN_TEST_LOOTER, L.LC_DESC_TEST_LOOTER)
    KART.LC.BtnTestLooter:SetSize(242, 28)
    KART.LC.BtnTestLooter:SetPoint("TOPLEFT", raidBox, "BOTTOMLEFT", 0, -16)
    KART.LC.BtnTestLooter:SetScript("OnClick", function() LC.StartTest("looter") end)

    KART.LC.BtnTestMaster = KART.CreateModernButton(parent, L.LC_BTN_TEST_MASTER, L.LC_DESC_TEST_MASTER)
    KART.LC.BtnTestMaster:SetSize(242, 28)
    KART.LC.BtnTestMaster:SetPoint("LEFT", KART.LC.BtnTestLooter, "RIGHT", 16, 0)
    KART.LC.BtnTestMaster:SetScript("OnClick", function() LC.StartTest("master") end)

    -- Loot history (full width) — anchored below the test buttons for the same reason.
    KART.LC.BtnHistory = KART.CreateModernButton(parent, L.LC_BTN_HISTORY, L.LC_DESC_HISTORY)
    KART.LC.BtnHistory:SetSize(500, 28)
    KART.LC.BtnHistory:SetPoint("TOPLEFT", KART.LC.BtnTestLooter, "BOTTOMLEFT", 0, -8)
    KART.LC.BtnHistory:SetScript("OnClick", function()
        if KART.LH then KART.LH.Toggle() end
    end)

    KART.RegisterLocaleRefresher(function()
        local Lx = KART.L
        KART.TabTitles[5]:SetText(Lx.LC_SETTINGS_TITLE)
        KART.LC.CbModuleEnabled.text:SetText(Lx.LC_SET_MODULE_ENABLED)        KART.LC.CbModuleEnabled.tooltipText = Lx.LC_DESC_MODULE_ENABLED
        KART.LC.CbAutoPass.text:SetText(Lx.LC_SET_AUTOPASS)                   KART.LC.CbAutoPass.tooltipText = Lx.LC_DESC_AUTOPASS
        KART.LC.CbCompactVoteLayout.text:SetText(Lx.LC_SET_COMPACT_VOTE_LAYOUT)
        KART.LC.CbCompactVoteLayout.tooltipText = Lx.LC_DESC_COMPACT_VOTE_LAYOUT
        KART.LC.CbShowNickNames.text:SetText(Lx.LC_SET_SHOW_NICKNAMES)        KART.LC.CbShowNickNames.tooltipText = Lx.LC_DESC_SHOW_NICKNAMES
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
