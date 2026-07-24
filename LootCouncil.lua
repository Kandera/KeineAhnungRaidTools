local addonName, KART = ...

KART.LC = KART.LC or {}
local LC = KART.LC

LC.sessionActive        = false
LC.promptedThisSession  = false
LC.votes                = {}  -- [rollID][Identity key] = {idx, note}  (key is a GUID, see KART.Identity)
LC.rolls                = {}  -- [rollID][Identity key] = 1-100 random roll (opt-in, see lcRollsEnabled)
LC.councilVotes         = {}  -- [rollID][council member Identity key] = candidate Identity key they picked (tally only, not binding)
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
-- Seed off the session clock (base + seconds-of-epoch mod 100000, range 500000..599999) so a
-- mid-raid /reload doesn't restart the counter at the base and reuse an ID a peer is still
-- tracking from before the reload — which would show the old item and old votes under the new
-- roll. time() moves forward every reload, so each session's manual IDs occupy a distinct range.
LC.nextManualRollID = LC.nextManualRollID or (MANUAL_ROLL_ID_BASE + time() % 100000)

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
    -- Out-of-range index (labels allow up to 6 buttons, this list holds the 5 default semantics)
    -- falls back to the neutral catch-all icon (4), NOT Pass (the last entry, 5) — otherwise a
    -- configured 6th button would render with the green Pass chip.
    return VOTE_ICON_TEXTURES[index] or VOTE_ICON_TEXTURES[4]
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
    if UnitIsGroupLeader("player") or not LC.raidConfig.buttonLabels or LC.raidConfig.buttonLabels == "" then
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or KART.L.LC_DEFAULT_BUTTONS
    else
        raw = LC.raidConfig.buttonLabels
    end
    local parts = KART.SplitString(raw, ";")
    local result = {}
    for _, label in ipairs(parts) do
        local trimmed = KART.TrimString(label)
        if trimmed ~= "" and #result < 6 then
            -- Color by the COMPACTED position (#result+1), not the raw split index, so it matches the
            -- vote icon (chosen by the returned button's index). A whitespace-only label between real
            -- ones is dropped from result but would otherwise advance the split index, desyncing the
            -- two.
            local col = BUTTON_COLORS[#result + 1] or BUTTON_COLORS[6]
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
    if LC.CouncilNamesTable[senderKey] == true then return true end
    -- The council table can still hold this member under a pending-TEXT key (they were out of group
    -- when the leader's config was parsed, so ResolveConfigName couldn't produce their GUID yet)
    -- while senderKey is already a live GUID. GROUP_ROSTER_UPDATE's throttled retry would migrate it,
    -- but an authoritative LC_RESULT/LC_ONOTE can arrive inside that throttle window and get wrongly
    -- dropped. Force the synchronous, pending-only migration now, then re-check, so a genuine council
    -- member's message is never lost to that timing race.
    LC.RetryPendingResolutions()
    return LC.CouncilNamesTable[senderKey] == true
end

function LC.SendLC(msg)
    if IsInGroup() then
        KART.Sync.Send(msg)
    end
end

-- Minimum item quality is authoritative from the raid leader, same reasoning as GetButtonConfig.
-- NOTE: this does NOT gate Auto-Pass (see OnStartLootRoll) — that stays a personal preference.
function LC.GetRaidMinQuality()
    if UnitIsGroupLeader("player") then
        return KART_Settings.lcMinQuality or 4
    end
    return LC.raidConfig.minQuality or 4
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
        setAll({vf.title}, big) -- window title scales with lcFontSize like the council panel's does
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
    return LC.raidConfig.lootmaster or ""
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
    if UnitIsGroupLeader("player") or LC.raidConfig.rollsEnabled == nil then
        return KART_Settings.lcRollsEnabled == true
    end
    return LC.raidConfig.rollsEnabled == true
end

-- Sends the leader's authoritative settings (min quality, vote-button labels, rolls toggle,
-- lootmaster, council member list) to the raid so every client interprets votes/roles identically.
-- No-ops for non-leaders. Payload order is minQ:buttons:rolls:lootmaster:council — council stays
-- last because it's the only greedy (.*) capture in HandleConfig's pattern, so it's the only field
-- allowed to contain further colons; every field before it (lootmaster included) is one colon-free
-- segment, which is why the synced free-text fields strip colons at input (LootCouncilSettings).
--
-- SendAddonMessage payloads are capped at 255 bytes by the underlying chat protocol. Button
-- labels (up to 128 chars) plus a large council list (up to 255 chars, per its editbox's
-- SetMaxLetters) can together exceed that, and a transport-truncated message can make
-- HandleConfig's anchored payload pattern fail to match on every other client, leaving them
-- silently stuck on stale config. Trim the council list — the field most likely to grow large —
-- to whatever whole entries fit instead, and tell the leader locally so they know to shorten it.
local ADDON_MSG_MAX_BYTES = 255

-- Fits council (the ";"-separated, variable-length tail shared by LC_CONFIG and LC_SYNC_REQUEST)
-- into the addon-message byte budget left after prefix — dropping whole trailing entries rather than
-- splitting one mid-name, and warning the user locally when it had to. Returns the full payload.
local function BuildCouncilPayload(prefix, council)
    local budget = ADDON_MSG_MAX_BYTES - #prefix
    if #council > math.max(budget, 0) then
        council = (budget > 0 and council:sub(1, budget):match("^(.*);")) or ""
        print("|cffff0000KART:|r " .. KART.L.LC_CONFIG_TRUNCATED)
    end
    return prefix .. council
end

function LC.BroadcastRaidConfig()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    local minQ     = KART_Settings.lcMinQuality or 4
    local buttons  = KART_Settings.lcButtonLabels or ""
    local rolls    = KART_Settings.lcRollsEnabled and "1" or "0"
    -- Keep the full "Name-Realm" text (don't strip the realm): GetLootmaster resolves the same
    -- unstripped value on the leader, so stripping here would let a cross-realm lootmaster resolve
    -- to a different person (or a same-named local) on peers than on the leader.
    local lootmaster = KART.TrimString(KART_Settings.lcLootmaster or "")
    local council  = KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_CONFIG:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":"
    LC.SendLC(BuildCouncilPayload(prefix, council))
end

-- The council/lootmaster/button-label edit boxes fire OnTextChanged on every keystroke; broadcasting
-- the full raid config per letter floods the raid with addon messages. Coalesce edits into a single
-- broadcast ~1s after typing stops (trailing edge, so the final complete text is what actually goes
-- out — unlike the leading-edge throttles elsewhere, which would send partial text mid-word).
function LC.BroadcastRaidConfigThrottled()
    if LC._cfgBroadcastTimer then LC._cfgBroadcastTimer:Cancel() end
    LC._cfgBroadcastTimer = C_Timer.NewTimer(1, function()
        LC._cfgBroadcastTimer = nil
        LC.BroadcastRaidConfig()
    end)
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
    -- council is the (.*) capture — never nil once the match above succeeded (guarded by minQ).
    LC.raidConfig.councilMembers = council

    LC.CouncilNamesTable = {}
    for _, name in ipairs(KART.SplitString(council, ";")) do
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

    if LC.raidConfig.lootmaster and not KART.Identity.IsResolvedKey(LC.raidConfig.lootmaster) then
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
    -- Full "Name-Realm" text, not realm-stripped — same cross-realm consistency reason as
    -- LC.BroadcastRaidConfig above.
    local lootmaster = KART.TrimString(KART_Settings.lcLootmaster or "")
    local voteSeconds = KART_Settings.lcVoteSeconds or 20
    local council = KART_Settings.lcCouncilMembers or ""

    local prefix = "LC_SYNC_REQUEST:" .. minQ .. ":" .. buttons .. ":" .. rolls .. ":" .. lootmaster .. ":" .. voteSeconds .. ":"
    KART.Sync.Send(BuildCouncilPayload(prefix, council), "WHISPER", targetName)
end

function LC.ShowSyncTargetDialog()
    KART.ShowInputDialog({
        title = KART.L.LC_SYNC_TARGET_PROMPT,
        maxLetters = 48,
        emptyMessage = KART.L.LC_SYNC_TARGET_EMPTY,
        onAccept = function(text) LC.SendSettingsSync(text) end,
    })
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

KART.RegisterStaticPopup("KART_LC_SYNC_REQUEST", {
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
        KART.Sync.Send("LC_SYNC_ACCEPT", "WHISPER", data.sender)
    end,
    OnCancel = function(self, data)
        KART.Sync.Send("LC_SYNC_DECLINE", "WHISPER", data.sender)
    end,
})

LC.IsRealItemLink = KART.IsRealItemLink -- kept as LC.* alias; call sites across the LC modules use this name

-- Pulls the (r,g,b) quality colour out of the leading |cAARRGGBB escape of an item link/coloured
-- string — works uniformly for real item hyperlinks (colour = actual item quality) and test mode's
-- fake coloured-string items, so tab swatches never need to special-case which kind it is.
function LC.ParseItemColor(link)
    local hex = type(link) == "string" and link:match("|c(%x%x%x%x%x%x%x%x)")
    if not hex then return 0.5, 0.5, 0.5 end
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- Refresh the council panel after a vote/assignment mutation, but only when it's actually open: the
-- row list only matters for the currently-active tab, while the per-tab vote-count badges stay live
-- on every tab. This exact guard was copy-pasted across the handlers that mutate vote/assignment
-- state. Handlers that only ever touch the active roll's rows, or refresh unconditionally, keep
-- their own narrower guard on purpose.
function LC.RefreshCouncilIfShown(rollID)
    if not (LC.councilPanel and LC.councilPanel:IsShown()) then return end
    if LC.activeRollID == rollID then KART.LC.Council.RefreshCouncilRows() end
    KART.LC.Council.RefreshCouncilTabs()
end

-- Sets an item icon texture: the item's real icon when the link resolves, otherwise a generic
-- question-mark placeholder tinted with the item's quality colour (r,g,b — pass what
-- LC.ParseItemColor returned, which the caller usually also needs for the surrounding border/strip).
function LC.SetItemIcon(icon, link, r, g, b)
    local iconTexture = LC.IsRealItemLink(link) and C_Item.GetItemIconByID(link)
    if iconTexture then
        icon:SetTexture(iconTexture)
        icon:SetVertexColor(1, 1, 1)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetVertexColor(r, g, b)
    end
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

-- Forgets every tracked roll and closes both LC windows. Shared by the leader ending the session
-- (SetSessionActive) and a peer receiving LC_ACTIVE:0, so both sides converge to a clean slate
-- instead of the peer keeping stale tabs/votes/showall state around.
function LC.ClearAllRolls()
    for i = #LC.councilTabs, 1, -1 do
        LC.Trade.ClearRollState(LC.councilTabs[i])
    end
    for i = #LC.voteListRolls, 1, -1 do
        LC.Trade.ClearRollState(LC.voteListRolls[i])
    end
    wipe(LC.councilTabs)
    wipe(LC.voteListRolls)
    LC.showAllOverride = nil
    LC.activeRollID = nil
    if LC.councilPanel then LC.councilPanel:Hide() end
    if LC.voteListFrame then LC.voteListFrame:Hide() end
end

function LC.SetSessionActive(active)
    LC.sessionActive = active
    LC.SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if active then
        LC.BroadcastRaidConfig()
    else
        -- Ending the session forgets every tracked roll so the next boss starts clean instead of
        -- showing leftover tabs/votes from this one (see LC.ClearAllRolls / LC.Trade.ClearRollState).
        LC.ClearAllRolls()
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

    -- Keep any still-valid link we already had if this event's link is unresolved (PurgeStaleRoll
    -- above deliberately didn't purge on unresolved data) — clobbering it with "???" would blank a
    -- roll that was showing fine. Mirrors HandleStart's fallback chain.
    LC.rollItems[rollID] = itemLink or LC.rollItems[rollID] or "???"
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
        -- Leader never receives their own LC_START, so open their own vote window here too — the
        -- same both-windows treatment HandleStart gives every other client (review #29), otherwise
        -- the leader would be the one council member who couldn't cast their own vote.
        LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs)
    end
end

LC.votedByMe = LC.votedByMe or {} -- [rollID] = the buttonIdx WE cast (truthy = voted; tracked by
                                   -- rollID, not by row, since rows get recycled/reindexed as items expire)
LC.votedNoteByMe = LC.votedNoteByMe or {} -- [rollID] = the note text WE typed before voting, kept
                                   -- around purely so the "you voted" state can still show it —
                                   -- otherwise it vanishes the moment the note box hides, even
                                   -- though the raider clearly remembers writing it.

-- rollID -> shortName of whoever this roll has already been awarded to (guards against accidental
-- double-assignment when the assign menu is used more than once for the same item).
LC.assignedWinners = LC.assignedWinners or {}

KART.RegisterStaticPopup("KART_LC_REASSIGN_CONFIRM", { ---@diagnostic disable-line: undefined-global
    text = "Already assigned.", -- unconditionally overwritten with KART.L.LC_REASSIGN_CONFIRM_TEXT in LC.Trade.AssignWinner below
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
})

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
    local wasActive = LC.sessionActive
    LC.sessionActive = (value == "1")
    -- A peer receiving the leader's session-end must also drop its tracked rolls and close its
    -- windows, exactly like the leader's own SetSessionActive(false) — otherwise stale tabs, votes
    -- and a leftover /kart showall override survive into the next session.
    if wasActive and not LC.sessionActive then
        LC.ClearAllRolls()
    end
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
    end
    -- Council members also get the vote window now (review #29): a council member who is in the raid
    -- can declare their own BIS like any raider. The popup shows for everyone; council additionally
    -- gets the panel above.
    LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
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
        -- Start the BoP trade-timeout clock at roll creation rather than at assign time
        -- (AddPendingTrade's fallback): we can't know a manually-added item's real Blizzard loot
        -- time, but roll creation is the earliest, most conservative moment we control.
        LC.rollLootedAt = LC.rollLootedAt or {}
        LC.rollLootedAt[rollID] = GetTime()

        local msg = "LC_MANUAL_START:" .. rollID .. ":" .. seconds .. ":" .. itemLink
        -- Guard the 255-byte SendAddonMessage cap: a very long item link (many bonus IDs) would be
        -- silently dropped, desyncing peers while the lootmaster's own windows still open below.
        -- Fall back to the compact item string, which HandleManualStart rebuilds into a full link.
        if #msg > 255 then
            local itemStr = KART.GetItemString(itemLink)
            if itemStr then msg = "LC_MANUAL_START:" .. rollID .. ":" .. seconds .. ":" .. itemStr end
        end
        LC.SendLC(msg)

        -- SendAddonMessage never echoes back to its own sender, so the lootmaster has to open
        -- their own window locally, same as HandleStart does for every other client.
        if LC.IsCouncil() then
            KART.LC.Council.ShowCouncilPanel(rollID, seconds)
        end
        -- Council also gets the vote window (review #29) — see the same pattern in LC.HandleStart.
        LC.Vote.ShowVotePopup(rollID, itemLink, seconds)
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
    -- The sender may have sent a compact item string instead of the full link (oversized-link
    -- fallback, see LC.StartManualRoll). Rebuild a full link when the item is cached so it displays.
    if not LC.IsRealItemLink(itemLink) and itemLink:match("^item:") then
        itemLink = select(2, C_Item.GetItemInfo(itemLink)) or itemLink
    end

    LC.votes[rollID]     = LC.votes[rollID] or {}
    -- The payload link is always authoritative for a manual roll (there's no Blizzard roll behind
    -- it, so it arrives intact) — take it unconditionally rather than preferring possibly-stale
    -- state left over from an earlier roll that reused this ID.
    LC.rollItems[rollID] = itemLink

    if LC.IsCouncil() then
        KART.LC.Council.ShowCouncilPanel(rollID, secs or 20)
    end
    -- Council members also get the vote window now (review #29): a council member who is in the raid
    -- can declare their own BIS like any raider. The popup shows for everyone; council additionally
    -- gets the panel above.
    LC.Vote.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
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
                -- Offset per item so the fake votes aren't identical across items, but wrap into the
                -- valid 1..#buttons range from the start — with fewer than TEST_ITEM_COUNT buttons a
                -- bare itemIdx seed would be out of range and render as "-".
                local voteIdx = ((itemIdx - 1) % #buttons) + 1
                for unit in KART.EachGroupUnit() do
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
        end
        -- Match live: council now sees both windows (review #29), so a master-mode test does too.
        LC.Vote.ShowVotePopup(testRollID, LC.rollItems[testRollID], KART_Settings.lcVoteSeconds or 20)
    end

    print("|cff00ff00KART:|r " .. string.format(KART.L.LC_TEST_STARTED, TEST_ITEM_COUNT))
end
