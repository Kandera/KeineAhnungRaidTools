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
LC.CouncilNamesTable    = {}  -- shortName:lower() -> true. Populated ONLY from the raid leader's
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

-- Which mode (true = council/master, false = looter) last actually (re)populated the test data
-- in LC.StartTest — nil until the first test run. Lets StartTest tell "the OTHER test window is
-- still open, don't wipe its data out from under it" apart from "the SAME window got re-clicked,
-- treat that as an explicit restart" (see the sessionActive/suppressReset comment in StartTest).
LC.testSessionShowCouncil = nil

local function IsTestRoll(rollID)
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
local function GetVoteIconTexture(index)
    return VOTE_ICON_TEXTURES[index] or VOTE_ICON_TEXTURES[#VOTE_ICON_TEXTURES]
end

-- Round class icon (the same atlas used by default raid/party frames) so a council-row candidate's
-- class reads at a glance without parsing the class-coloured name text.
local function SetClassIconTexture(tex, classFile)
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
        raw = (KART_Settings and KART_Settings.lcButtonLabels) or "BIS;Upgrade;Offspec;Sonstiges;Pass"
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
        result = {
            {label="BIS",       r=1.0,  g=0.15, b=0.0 },
            {label="Upgrade",   r=0.0,  g=0.85, b=0.25},
            {label="Offspec",   r=0.2,  g=0.4,  b=1.0 },
            {label="Sonstiges", r=0.9,  g=0.75, b=0.0 },
            {label="Pass",      r=0.55, g=0.55, b=0.55},
        }
    end
    return result
end

-- Only the leader's own edits are authoritative; this just re-broadcasts them to the raid.
-- (Non-leaders calling this would have no effect, since BroadcastRaidConfig no-ops for them.)
function LC.UpdateCouncilCache()
    LC.BroadcastRaidConfig()
end

local function IsCouncil()
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
local function IsSenderCouncil(senderKey)
    local unit = senderKey and KART.Identity.FindUnitForKey(senderKey)
    if not unit then return false end
    if UnitIsGroupLeader(unit) then return true end
    return LC.CouncilNamesTable[senderKey] == true
end

local function GetChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

local function SendLC(msg)
    if IsInGroup() then
        C_ChatInfo.SendAddonMessage("KART", msg, GetChannel())
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

-- Whether configuredName (trimmed+lowercased text from the lootmaster field, see LC.GetLootmaster)
-- identifies the local player — by character short name, same as always, or by Northern Sky Raid
-- Tools nickname (see KART.GetNickname in Utils.lua), so a raid leader can name a *person* once
-- ("kandera") instead of re-typing the field whenever that person switches characters. Every alt
-- just needs the same NSRT nickname set, which raiders already do for the addon's other
-- nickname-aware features.
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
    SendLC(prefix .. council)
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
        LC.MigrateOfficerNoteKey(oldKey)
    end
end

-- Answers an "LC_STATE_REQ" broadcast from a joining/reloading peer with the current session flag
-- and, if a session is active, the full raid config — a one-shot pull instead of waiting for the
-- leader's own roster-change handler to happen to fire (see LC.CheckRaidJoin). Only the actual
-- leader replies, same authority rule as LC.BroadcastRaidConfig itself.
function LC.HandleStateRequest()
    if not (IsInGroup() and UnitIsGroupLeader("player")) then return end
    SendLC("LC_ACTIVE:" .. (LC.sessionActive and "1" or "0"))
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
-- as self.editBox to its callbacks — same fix already applied to LC.ShowOfficerNoteDialog below
-- (see its comment for the full "attempt to index field 'editBox' (a nil value)" story). Owning
-- the frame ourselves means the edit box reference always exists.
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
local function IsRealItemLink(link)
    return type(link) == "string" and link:find("|Hitem:") ~= nil
end

-- Pulls the (r,g,b) quality colour out of the leading |cAARRGGBB escape of an item link/coloured
-- string — works uniformly for real item hyperlinks (colour = actual item quality) and test mode's
-- fake coloured-string items, so tab swatches never need to special-case which kind it is.
local function ParseItemColor(link)
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
    SendLC("LC_ACTIVE:" .. (active and "1" or "0"))
    if active then
        LC.BroadcastRaidConfig()
    else
        -- Ending the session forgets every tracked roll so the next boss starts clean instead of
        -- showing leftover tabs/votes from this one (see LC.ClearRollState).
        for i = #LC.councilTabs, 1, -1 do
            LC.ClearRollState(LC.councilTabs[i])
        end
        for i = #LC.voteListRolls, 1, -1 do
            LC.ClearRollState(LC.voteListRolls[i])
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
        LC.RequestHistorySync()
    end

    -- Ask the raid leader (once per raid join/reload) for the current session-active flag and
    -- raid-wide config, so a late joiner or a /reload'd client is never stuck on stale defaults
    -- until the leader happens to notice a roster change (see LC.HandleStateRequest below) — same
    -- request/response shape as the loot-history catch-up above.
    if not LC.stateSyncRequested then
        LC.stateSyncRequested = true
        SendLC("LC_STATE_REQ")
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
-- LC.ClearRollState), so a long-since-irrelevant timer never resurrects a forgotten roll.
local function ResolveRollItemLink(rollID, attempt)
    if LC.rollItems[rollID] ~= "???" then return end
    attempt = attempt or 1
    local link = GetLootRollItemLink(rollID)
    if link then
        LC.rollItems[rollID] = link
        LC.RefreshVoteListRows()
        if LC.councilPanel and LC.councilPanel:IsShown() then
            LC.RefreshCouncilRows()
            LC.RefreshCouncilTabs()
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

function LC.OnStartLootRoll(rollID)
    if KART_Settings.lcModuleEnabled == false then return end
    if not LC.sessionActive then return end

    local lootmaster = LC.GetLootmaster()

    if LC.IsMe(lootmaster) then
        -- The lootmaster is the one exception to Auto-Pass: they must physically win every item
        -- (regardless of their own local Auto-Pass setting) so they can trade it out afterwards —
        -- see LC.GetLootmaster for why this is raid-leader-controlled, not a personal toggle.
        ForceWinRoll(rollID)
    elseif KART_Settings.lcAutoPass then
        -- Auto-Pass is a personal preference and is intentionally independent of the raid's
        -- min-quality setting (that setting only gates whether Council itself engages) —
        -- evaluated unconditionally so a raider's own choice is never overridden by the raid
        -- leader's quality threshold.
        RollOnLoot(rollID, 0)
    end

    -- Below the raid-wide minimum rarity: let Blizzard's own roll UI handle it, untouched — unless
    -- it's a Miscellaneous-class item (classID 15: toys, pets, mounts, housing decor, and similar
    -- non-equipment collectibles), which is never gated on rarity since it's virtually always
    -- Common/Uncommon regardless of how desirable it is.
    local _, _, _, quality = GetLootRollItemInfo(rollID)
    local minQuality = LC.GetRaidMinQuality()
    local itemLink = GetLootRollItemLink(rollID)
    local classID = IsRealItemLink(itemLink) and select(12, C_Item.GetItemInfo(itemLink))
    if quality and quality < minQuality and classID ~= 15 then return end

    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or "???"
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
        SendLC("LC_ROLL:" .. rollID .. ":" .. myRoll)
    end

    if UnitIsGroupLeader("player") then
        local secs = KART_Settings.lcVoteSeconds or 20
        SendLC("LC_START:" .. rollID .. ":" .. secs)
        LC.ShowCouncilPanel(rollID, secs)
    end
end

-- =====================================================================
--  Vote List  (shown to non-council raiders via LC_START message)
-- =====================================================================
-- Every currently active roll gets its own row, all visible at once, so a raider can compare
-- everything that's dropped before deciding how to vote on each individually (e.g. BIS on one
-- item and Pass on another because they only actually want the one) — items are never hidden
-- behind each other, and voting on one never affects the others.

LC.votedByMe = LC.votedByMe or {} -- [rollID] = true once WE cast a vote for it (tracked by rollID,
                                   -- not by row, since rows get recycled/reindexed as items expire)
LC.votedNoteByMe = LC.votedNoteByMe or {} -- [rollID] = the note text WE typed before voting, kept
                                   -- around purely so the "you voted" state can still show it —
                                   -- otherwise it vanishes the moment the note box hides, even
                                   -- though the raider clearly remembers writing it.

function LC.CreateVoteList()
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
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    closeBtn.text:SetPoint("CENTER", 0, 1)
    closeBtn.text:SetText("×")
    table.insert(KART.CloseButtonTexts, closeBtn.text)
    closeBtn:SetScript("OnEnter", function(s) s.text:SetTextColor(KART.Theme.AccentColor()) end)
    closeBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

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
    if pos and type(pos) == "table" and pos.x and pos.y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end

    -- One shared ticker drives every row's countdown; a row is dropped once its own voting
    -- window closes. Only touches timer text on a normal tick — a full rebuild (which would
    -- reset in-progress note text) only happens when a row actually gets added or removed.
    f.ticker = C_Timer.NewTicker(1, function()
        if not f:IsShown() then return end
        local now = GetTime()
        local changed = false
        for i = #LC.voteListRolls, 1, -1 do
            local rid = LC.voteListRolls[i]
            local deadline = LC.rollDeadlines[rid]
            if deadline and now >= deadline then
                table.remove(LC.voteListRolls, i)
                changed = true
            end
        end
        if changed then
            LC.RefreshVoteListRows()
        else
            local pool = (KART_Settings and KART_Settings.lcVoteLayoutCompact) and f.compactRows or f.rows
            for i, rid in ipairs(LC.voteListRolls) do
                local row = pool and pool[i]
                if row and row:IsShown() then
                    local deadline  = LC.rollDeadlines[rid]
                    local remaining = deadline and math.max(0, math.ceil(deadline - now)) or 0
                    local votedCount, total = LC.CountVotes(rid)
                    row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS or "(%d/%d)", votedCount, total))
                end
            end
        end
    end)

    LC.voteListFrame = f
    return f
end

-- Registers rollID as an active roll and (re)builds the list. itemLink/seconds only matter the
-- first time a rollID is seen — LC.rollItems/LC.rollDeadlines are the source of truth afterwards.
function LC.ShowVotePopup(rollID, itemLink, seconds)
    LC.rollItems[rollID]     = LC.rollItems[rollID] or itemLink
    LC.rollDeadlines[rollID] = GetTime() + (seconds or 20)

    local alreadyListed = false
    for _, rid in ipairs(LC.voteListRolls) do
        if rid == rollID then alreadyListed = true break end
    end
    if not alreadyListed then
        table.insert(LC.voteListRolls, rollID)
    end

    LC.RefreshVoteListRows()
end

-- Removes rollID from the list (e.g. a result came in for it from elsewhere) and rebuilds.
function LC.RemoveVoteListItem(rollID)
    for i = #LC.voteListRolls, 1, -1 do
        if LC.voteListRolls[i] == rollID then table.remove(LC.voteListRolls, i) end
    end
    LC.RefreshVoteListRows()
end

-- Thin dispatcher: resizes nothing itself, just picks which style actually builds the rows.
-- Hides the *inactive* style's row pool first so switching styles (or the very first refresh
-- after a `/reload`) never leaves a stale row from the other layout visible underneath.
function LC.RefreshVoteListRows()
    if #LC.voteListRolls == 0 then
        if LC.voteListFrame then LC.voteListFrame:Hide() end
        return
    end
    if not LC.voteListFrame then LC.CreateVoteList() end
    local f = LC.voteListFrame

    local compact = KART_Settings and KART_Settings.lcVoteLayoutCompact
    if compact then
        for _, row in ipairs(f.rows or {}) do row:Hide() end
        LC.RefreshVoteListRows_Compact(f)
    else
        for _, row in ipairs(f.compactRows or {}) do row:Hide() end
        LC.RefreshVoteListRows_Spacious(f)
    end
    f:Show()
end

-- LC.RefreshVoteListRows() always calls f:Show() when there's still a pending roll — deliberate
-- for real loot rolls (see the vote window's close-button comment: it "comes back on its own" so
-- a raider can't just dismiss an active vote), but wrong for a callback that merely changes how
-- the window LOOKS, like the compact-layout checkbox: toggling it while an old, not-yet-expired
-- test roll happens to still be tracked would otherwise pop the window back open and re-show
-- stale votes, reading as "a new test just started" even though nothing new was triggered. Only
-- re-render if the window is already visible; otherwise leave it hidden until something that
-- actually means "show this" (a new roll, a Test click) calls the dispatcher directly.
function LC.RefreshVoteListRowsIfShown()
    if LC.voteListFrame and LC.voteListFrame:IsShown() then
        LC.RefreshVoteListRows()
    end
end

-- "Spacious" style: one card per item, full window width each, large touch targets. The default
-- and recommended style — see docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function LC.RefreshVoteListRows_Spacious(f)
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
    local rowH      = ACCENT_H + BTN_TOP + btnAreaH + GAP_BTN_NOTE + noteH + BOTTOM_PAD
    local ROW_GAP   = 22 -- gap between item blocks — was 12, still too tight for 2+ simultaneous rolls

    -- Same short-name extraction the test-roll vote branch further below already uses — this is
    -- the local player's own Droptimizer gain% for the item, not a per-candidate column (a
    -- vote-list row represents one item, not one candidate, so "the player" here is whoever is
    -- looking at their own vote window).
    local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")

    for i, rollID in ipairs(LC.voteListRolls) do
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

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("RIGHT", f.scrollChild, "RIGHT", 0, 0)
        row:SetHeight(rowH)
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
        row.itemText:SetText(rollLink or "???")

        -- Real icon when we have one; otherwise the same tinted placeholder used by the council
        -- panel's tabs (see RefreshCouncilTabs), so both windows degrade the same way.
        local ir, ig, ib = ParseItemColor(rollLink)
        local iconTexture = IsRealItemLink(rollLink) and C_Item.GetItemIconByID(rollLink)
        if iconTexture then
            row.itemIcon:SetTexture(iconTexture)
            row.itemIcon:SetVertexColor(1, 1, 1)
        else
            row.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemIcon:SetVertexColor(ir, ig, ib)
        end
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
        row.accentStrip:SetColorTexture(ir, ig, ib)

        local deadline  = LC.rollDeadlines[rollID]
        local remaining = deadline and math.max(0, math.ceil(deadline - GetTime())) or 0
        do
            local votedCount, total = LC.CountVotes(rollID)
            row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS or "(%d/%d)", votedCount, total))
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
            row.gainText:SetText(string.format("%s: %s%+.1f%%|r", KART.L.DT_COL_GAIN or "Gain", color, gainPct))
            row.gainText:Show()
        else
            row.gainText:Hide()
        end

        row.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[rollID]
            if not IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        row.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local voted    = LC.votedByMe[rollID]
        local votedDef = voted and buttons[tonumber(voted)]
        row.btnArea:SetShown(not voted)
        row.noteLabel:SetShown(not voted)
        row.noteBox:SetShown(not voted)
        row.votedText:SetShown(voted ~= nil)
        row.votedBadge:SetShown(voted ~= nil)
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
            row.votedBadge:SetWidth(math.min(row.votedText:GetStringWidth() + 20, 329))
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
                btn.iconTex:SetTexture(GetVoteIconTexture(bi))

                local capturedIdx    = bi
                local capturedRollID = rollID
                btn:SetScript("OnClick", function()
                    if LC.votedByMe[capturedRollID] then return end
                    LC.votedByMe[capturedRollID] = capturedIdx
                    local note = KART.TrimString(row.noteBox and row.noteBox:GetText() or "")
                    LC.votedNoteByMe[capturedRollID] = note
                    if IsTestRoll(capturedRollID) then
                        -- Test rolls have no real raid to broadcast to (and testing solo may
                        -- mean no group at all), so record the vote locally and push it
                        -- straight into the Test-Master council panel if it's open, instead of
                        -- relying on a round-trip through the addon channel that would never
                        -- come back to this same client.
                        local myKey = (KART.Identity.ResolvePlayer("player"))
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myKey] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
                end)
            end
        end
    end

    for i = #LC.voteListRolls + 1, #f.rows do
        if f.rows[i] then f.rows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #LC.voteListRolls * (rowH + ROW_GAP) + 12, 600))
end

-- "Compact" style: one short single-line row per item, vote buttons shrunk to icon-only chips.
-- Alternative for players who'd rather keep the window small than have large touch targets — see
-- docs/superpowers/specs/2026-07-15-vote-window-layouts-design.md.
function LC.RefreshVoteListRows_Compact(f)
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

    for i, rollID in ipairs(LC.voteListRolls) do
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
        row.itemText:SetText(rollLink or "???")
        row.itemText:SetWidth(CONTENT_W - ICON_SIZE - MARGIN * 2 - 8 - 60)

        local ir, ig, ib = ParseItemColor(rollLink)
        local iconTexture = IsRealItemLink(rollLink) and C_Item.GetItemIconByID(rollLink)
        if iconTexture then
            row.itemIcon:SetTexture(iconTexture)
            row.itemIcon:SetVertexColor(1, 1, 1)
        else
            row.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemIcon:SetVertexColor(ir, ig, ib)
        end
        row.itemIconBorder:SetVertexColor(ir, ig, ib)
        row.itemText:SetTextColor(ir, ig, ib)

        local deadline  = LC.rollDeadlines[rollID]
        local remaining = deadline and math.max(0, math.ceil(deadline - GetTime())) or 0
        do
            local votedCount, total = LC.CountVotes(rollID)
            row.timerText:SetText(remaining .. "s  " .. string.format(KART.L.LC_VOTES_PROGRESS or "(%d/%d)", votedCount, total))
        end
        if deadline then
            row.itemCD:SetCooldown(GetTime(), math.max(deadline - GetTime(), 0))
        end

        local dtEnabled = KART_Settings.dtModuleEnabled ~= false
        local gainPct = dtEnabled and KART.DT and KART.DT.GetGainPercent and LC.rollItems[rollID]
            and KART.DT.GetGainPercent(myShort, LC.rollItems[rollID]) or nil
        if gainPct then
            local color = gainPct >= 0 and "|cff40c040" or "|cffc04040"
            row.gainText:SetText(string.format("%s: %s%+.1f%%|r", KART.L.DT_COL_GAIN or "Gain", color, gainPct))
            row.gainText:Show()
        else
            row.gainText:Hide()
        end

        row.itemHover:SetScript("OnEnter", function(self)
            local link = LC.rollItems[rollID]
            if not IsRealItemLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end)
        row.itemHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local voted    = LC.votedByMe[rollID]
        local votedDef = voted and buttons[tonumber(voted)]
        row.chipArea:SetShown(not voted)
        row.votedText:SetShown(voted ~= nil)
        row.votedBadge:SetShown(voted ~= nil)
        if voted then row.noteBox:Hide() end
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
                btn.iconTex:SetTexture(GetVoteIconTexture(bi))

                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(def.label, def.r, def.g, def.b)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                local capturedIdx    = bi
                local capturedRollID = rollID
                btn:SetScript("OnClick", function()
                    if LC.votedByMe[capturedRollID] then return end
                    LC.votedByMe[capturedRollID] = capturedIdx
                    local note = KART.TrimString(row.noteBox and row.noteBox:GetText() or "")
                    LC.votedNoteByMe[capturedRollID] = note
                    if IsTestRoll(capturedRollID) then
                        local myKey = (KART.Identity.ResolvePlayer("player"))
                        LC.votes[capturedRollID] = LC.votes[capturedRollID] or {}
                        LC.votes[capturedRollID][myKey] = {idx = capturedIdx, note = note}
                        if LC.councilPanel and LC.councilPanel:IsShown() then
                            if LC.activeRollID == capturedRollID then LC.RefreshCouncilRows() end
                            LC.RefreshCouncilTabs()
                        end
                    else
                        SendLC("LC_VOTE:" .. capturedRollID .. ":" .. capturedIdx .. ":" .. note)
                    end
                    LC.RefreshVoteListRows()
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

    for i = #LC.voteListRolls + 1, #f.compactRows do
        if f.compactRows[i] then f.compactRows[i]:Hide() end
    end

    f:SetHeight(math.min(32 + #LC.voteListRolls * (rowH + ROW_GAP) + 12, 600))
end

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
function LC.GetEquippedForUnit(unit, rollItemLink)
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
function LC.GetItemArmorRank(itemLink)
    if not IsRealItemLink(itemLink) then return nil end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)
    if classID ~= 4 then return nil end -- 4 = Armor
    return ARMOR_SUBCLASS_RANK[subclassID]
end

-- Returns false (ineligible) only when we're SURE the class can't equip this armor type; true
-- for everything else, including when either side of the check is unknown — this is a visual
-- hint, not a hard filter, so it must never hide someone who might actually be eligible.
function LC.IsArmorEligible(classFile, itemRank)
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
function LC.ShowCouncilPanel(rollID, seconds)
    if not LC.councilPanel then LC.CreateCouncilPanel() end
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
            LC.SetCouncilPanelMinimized(false)
        end
    end

    if not LC.activeRollID then
        LC.SwitchCouncilTab(rollID)
    else
        LC.RefreshCouncilTabs()
    end

    panel:Show()
end

-- Switches the panel's row list over to rollID and clears its "new" marker.
function LC.SwitchCouncilTab(rollID)
    local panel = LC.councilPanel
    if not panel then return end

    LC.activeRollID = rollID
    LC.councilTabsNew[rollID] = nil
    panel.itemText:SetText(LC.rollItems[rollID] or "???")
    panel.title:SetText(KART.L.LC_PANEL_TITLE)

    local link = LC.rollItems[rollID]
    local ir, ig, ib = ParseItemColor(link)
    local iconTexture = IsRealItemLink(link) and C_Item.GetItemIconByID(link)
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

    LC.RefreshCouncilRows()
    LC.RefreshCouncilTabs()
end

-- Removes rollID's tab (e.g. "No Winner", or manually dismissed via the tab's own "x"). Switches
-- to another remaining tab if there is one, otherwise hides the whole panel.
function LC.CloseCouncilTab(rollID)
    for i = #LC.councilTabs, 1, -1 do
        if LC.councilTabs[i] == rollID then table.remove(LC.councilTabs, i) end
    end
    LC.ClearRollState(rollID)

    if LC.activeRollID == rollID then
        if LC.councilTabs[1] then
            LC.SwitchCouncilTab(LC.councilTabs[1])
        else
            LC.activeRollID = nil
            if LC.councilPanel then LC.councilPanel:Hide() end
        end
    else
        LC.RefreshCouncilTabs()
    end
end

-- Rebuilds the vertical tab strip on the left edge of the panel from LC.councilTabs. Each tab
-- shows the item's actual icon (real items) or a colour-tinted placeholder (test items), plus a
-- voted/total badge; hovering one previews the full per-player vote breakdown without switching
-- to it. Its "x" only appears on hover — it used to sit flush in the corner at all times, which
-- made it very easy to close a tab by accident while just trying to click it to switch.
function LC.RefreshCouncilTabs()
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
        local r, g, b = ParseItemColor(link)
        if rollID == LC.activeRollID then
            tab:SetBackdropBorderColor(1, 0.85, 0.2, 1)
            tab.activeGlow:Show()
        else
            tab:SetBackdropBorderColor(r, g, b, 0.9)
            tab.activeGlow:Hide()
        end

        -- Real items show their actual icon; test mode has no real item to fetch an icon for,
        -- so it gets a generic placeholder tinted with the item's own colour instead.
        local iconTexture = IsRealItemLink(link) and C_Item.GetItemIconByID(link)
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
        tab:SetScript("OnClick", function() LC.SwitchCouncilTab(capturedRollID) end)
        tab.closeBtn:SetScript("OnClick", function() LC.CloseCouncilTab(capturedRollID) end)
        tab:SetScript("OnEnter", function(self)
            tab.closeBtn:Show()

            local hoverLink = LC.rollItems[capturedRollID]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if IsRealItemLink(hoverLink) then
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
                local idx = type(voteData) == "table" and voteData.idx or voteData
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

function LC.CreateCouncilPanel()
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

    local closeBtn = CreateFrame("Button", nil, hdr)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    closeBtn.text:SetPoint("CENTER", 0, 1)
    closeBtn.text:SetText("×")
    table.insert(KART.CloseButtonTexts, closeBtn.text)
    closeBtn:SetScript("OnEnter", function(s) s.text:SetTextColor(KART.Theme.AccentColor()) end)
    closeBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    -- Only hides the window — the active roll's tab (and all others) stay tracked and reappear
    -- next time the panel is shown; this is a deliberate "get it out of my way for now", not a
    -- "discard" action. Use a tab's own "x" to actually dismiss an item, or the "-" button (below)
    -- to shrink the panel down to just its header instead of hiding it outright.
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Collapses the panel to just its title bar + item name, keeping it out of the way during
    -- normal raiding without losing track of what's being voted on (tabs/rows are hidden, not
    -- discarded — see LC.SetCouncilPanelMinimized). Sits left of the close button, same style.
    local minimizeBtn = CreateFrame("Button", nil, hdr)
    minimizeBtn:SetSize(22, 22)
    minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    minimizeBtn.text = minimizeBtn:CreateFontString(nil, "OVERLAY")
    minimizeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    minimizeBtn.text:SetPoint("CENTER", 0, 1)
    minimizeBtn.text:SetText("-")
    table.insert(KART.CloseButtonTexts, minimizeBtn.text)
    minimizeBtn:SetScript("OnEnter", function(s) s.text:SetTextColor(KART.Theme.AccentColor()) end)
    minimizeBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 1, 1) end)
    minimizeBtn:SetScript("OnClick", function() LC.SetCouncilPanelMinimized(not f.isMinimized) end)
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
        if not IsRealItemLink(link) then return end
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

    -- Guild rank, right after Name (see row.rankText) — purely so alts are easier to spot at a
    -- glance among a roster of otherwise-unfamiliar names; blank/"-" for anyone not in a guild.
    local hRank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRank:SetPoint("TOPLEFT", 136, -80)
    hRank:SetWidth(60)
    hRank:SetJustifyH("CENTER")
    hRank:SetText(KART.L.LC_COL_RANK)
    hRank:SetTextColor(0.5, 0.5, 0.5)

    local hIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", 206, -80)
    hIlvl:SetWidth(68) -- spans the equip icon + ilvl number (+/- delta) together
    hIlvl:SetJustifyH("CENTER")
    hIlvl:SetText("iLvl")
    hIlvl:SetTextColor(0.5, 0.5, 0.5)

    local hVote = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hVote:SetPoint("TOPLEFT", 282, -80)
    hVote:SetWidth(100)
    hVote:SetJustifyH("LEFT")
    hVote:SetText(KART.L.LC_COL_VOTE)

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

    -- Droptimizer gain % — sourced from KART_WoWUtilsCache (written by the external KART
    -- Companion app, see Droptimizer.lua), shown/hidden with dtModuleEnabled just like hRoll
    -- is shown/hidden with lcRollsEnabled below.
    local hGain = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hGain:SetPoint("TOPLEFT", 481, -80)
    hGain:SetWidth(44)
    hGain:SetJustifyH("CENTER")
    hGain:SetText(KART.L.DT_COL_GAIN or "Gain")
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
            LC.AnnounceResult(LC.activeRollID, "NONE")
            LC.CloseCouncilTab(LC.activeRollID)
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
function LC.SetCouncilPanelMinimized(minimized)
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

function LC.RefreshCouncilRows()
    local panel = LC.councilPanel
    if not panel then return end

    local rollID  = LC.activeRollID
    local votes   = (rollID and LC.votes[rollID]) or {}
    local buttons = LC.GetButtonConfig()
    local isRaid  = IsInRaid()
    local numMem  = GetNumGroupMembers()

    local rollItem = LC.rollItems[rollID]
    if rollID and rollItem and IsRealItemLink(rollItem) and not LC.pendingItemLoads[rollID]
       and not C_Item.GetItemInfo(rollItem) then
        LC.pendingItemLoads[rollID] = true
        Item:CreateFromItemLink(rollItem):ContinueOnItemLoad(function()
            LC.pendingItemLoads[rollID] = nil
            if LC.activeRollID == rollID and LC.councilPanel and LC.councilPanel:IsShown() then
                LC.RefreshCouncilRows()
            end
        end)
    end
    local itemArmorRank = LC.GetItemArmorRank(rollItem)

    -- Rolled item's own ilvl, purely to show a +/- delta next to each candidate's equipped ilvl
    -- (see the equippedText update below) — nil until the item link is cached, same as everywhere
    -- else in this function that reads C_Item.GetItemInfo.
    local rollItemIlvl
    if rollItem and IsRealItemLink(rollItem) then
        local _, _, _, ilvl = C_Item.GetItemInfo(rollItem)
        rollItemIlvl = ilvl
    end
    if panel.ilvlText then
        panel.ilvlText:SetText(rollItemIlvl and ("Item Level " .. rollItemIlvl) or "")
    end

    local members = {}
    for i = 1, numMem do
        local unit = isRaid and ("raid"..i) or (i == numMem and "player" or "party"..i)
        local fullName = UnitName(unit)
        if fullName then
            local short    = fullName:match("([^%-]+)")
            local key      = (KART.Identity.ResolvePlayer(unit))
            local voteData = votes[key]
            -- Support both legacy number and new {idx, note} table
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit(unit, rollItem)

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
    if IsTestRoll(rollID) then
        local myShort = ((UnitName("player") or ""):match("([^%-]+)") or "")
        local myKey    = (KART.Identity.ResolvePlayer("player"))
        local alreadyListed = false
        for _, m in ipairs(members) do
            if m.short == myShort then alreadyListed = true break end
        end
        if not alreadyListed and myShort ~= "" then
            local voteData = votes[myKey]
            local voteIdx  = voteData and (type(voteData) == "table" and voteData.idx or voteData)
            local voteNote = voteData and type(voteData) == "table" and voteData.note or ""
            local voteDef  = voteIdx and buttons[tonumber(voteIdx)]
            local equippedLink, equippedIlvl = LC.GetEquippedForUnit("player", rollItem)
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
            -- LC.ToggleCouncilVote. Every viewer of this panel is themselves a council member
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
        SetClassIconTexture(row.classIcon, classFile)

        -- Armor-type eligibility is a soft visual hint, never a hard block (right-click assign
        -- still works either way) — dims the row and greys the name so obviously-wrong
        -- candidates (e.g. a plate item on a cloth wearer) stand out less among real contenders.
        local armorIneligible = not LC.IsArmorEligible(classFile, itemArmorRank)
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
        local dtEnabled = KART_Settings.dtModuleEnabled ~= false
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
            row.voteIcon:SetTexture(GetVoteIconTexture(tonumber(m.voteIdx)))
            row.voteIcon:Show()
        else
            row.voteText:SetText("|cff666666-|r")
            row.voteIcon:Hide()
        end

        -- Opt-in 1-100 roll column — entirely hidden (not just blank) when the raid leader has
        -- rolls turned off, both to save space and to avoid implying a feature that isn't active.
        local rollsEnabled = LC.GetRollsEnabled()
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
        if panel.hRoll then panel.hRoll:SetShown(rollsEnabled) end
        if panel.hGain then panel.hGain:SetShown(dtEnabled) end

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
            LC.ToggleCouncilVote(capturedRoll, capturedKey)
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
            LC.ShowAssignMenu(self, capturedRoll, capturedKey, capturedShort, capturedVoteDef)
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
            if IsRealItemLink(rollItem) then
                GameTooltip:SetHyperlink(rollItem)
                GameTooltip:AddLine(" ")
                if ShoppingTooltip1 then ShoppingTooltip1:Hide() end ---@diagnostic disable-line: undefined-global
                if ShoppingTooltip2 then ShoppingTooltip2:Hide() end ---@diagnostic disable-line: undefined-global
            else
                GameTooltip:SetText(rollItem or "???", 1, 1, 1)
            end
            GameTooltip:AddLine(capturedShort or "?", nr, ng, nb)
            if dtEnabled and capturedGainPct then
                GameTooltip:AddLine(string.format(KART.L.DT_TOOLTIP_GAIN or "Gain: %+.1f%% (%s)",
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
            GameTooltip:AddLine(KART.L.LC_TOOLTIP_RCLICK or "Right-click: assign this item", 0.5, 0.5, 0.5, true)
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
end

-- =====================================================================
--  Result announcement & winner notification
-- =====================================================================

-- reason (optional) is appended to the chat announcement, e.g. "(BIS)"; blank for no reason.
-- reason also travels in the LC_RESULT broadcast so every KART user's loot history stays in sync.
function LC.AnnounceResult(rollID, winnerKey, reason)
    -- Test rolls stay entirely local: no addon-channel broadcast (which would make every real
    -- raid member's client log a fake history entry / pop a fake "you win" for whoever the
    -- tester happened to click) and no raid-chat spam.
    if not IsTestRoll(rollID) then
        SendLC("LC_RESULT:" .. rollID .. ":" .. winnerKey .. ":" .. (reason or ""))

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
        LC.RefreshCouncilRows()
    end
end

-- =====================================================================
--  Loot History  (SavedVariable: KART_LootHistory)
-- =====================================================================

local MAX_HISTORY_ENTRIES = 500

-- classFile is captured on a best-effort basis (only known while the raider is in range/group).
-- colorDef (optional) is the button definition {r,g,b,...} the reason came from; stored so the
-- history keeps its original color even if button labels/colors are changed later.
-- Difficulty is captured locally on whichever client logs the entry (assigner or synced receiver),
-- since every client in the same instance sees the same difficulty.
function LC.LogHistory(itemLink, winnerDisplayName, reason, classFile, colorDef, rollID)
    KART_LootHistory = KART_LootHistory or {}
    local now = time()

    -- Guards against double-logging the same win if a redelivered/duplicate LC_RESULT addon
    -- message ever reaches this client twice (HandleResult has no dedup of its own, unlike the
    -- history catch-up sync path in HandleHistoryEntry below). Only checks the most recent entries
    -- within the last few seconds — a genuine duplicate would land back-to-back, whereas a real
    -- re-roll of the exact same item to the exact same winner minutes later is a separate event.
    for i = #KART_LootHistory, math.max(1, #KART_LootHistory - 3), -1 do
        local e = KART_LootHistory[i]
        if e.item == (itemLink or "") and e.winner == (winnerDisplayName or "") and e.reason == (reason or "")
           and now - (e.time or 0) < 5 then
            return
        end
    end

    -- A reassignment (LC.AssignWinner called again for a rollID that was already assigned) must
    -- replace its previous history entry, not sit alongside it — otherwise the same physical item
    -- shows up twice in history with two different winners.
    if rollID then
        for i = #KART_LootHistory, 1, -1 do
            if KART_LootHistory[i].rollID == rollID and KART_LootHistory[i].item == (itemLink or "") then
                table.remove(KART_LootHistory, i)
                break
            end
        end
    end

    local _, _, _, difficultyName = GetInstanceInfo()
    table.insert(KART_LootHistory, {
        time       = now,
        item       = itemLink or "",
        winner     = winnerDisplayName or "",
        reason     = reason or "",
        class      = classFile,
        color      = colorDef and {r = colorDef.r, g = colorDef.g, b = colorDef.b} or nil,
        difficulty = difficultyName or "",
        rollID     = rollID,
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end

-- =====================================================================
--  Loot History catch-up sync (silent — never touches chat, addon-channel only)
-- =====================================================================
-- When someone rejoins a raid after missing a session, their KART_LootHistory is missing whatever
-- was assigned while they were away. On join, they broadcast the timestamp of their newest known
-- entry; any peer who has newer entries whispers just those back (addon channel, invisible to the
-- player) after a small random delay so several peers answering at once don't all fire at exactly
-- the same instant. Capped and time-scoped to keep this cheap even after long absences.

local HISTORY_SYNC_MAX_ENTRIES = 30
local HISTORY_SYNC_MAX_AGE     = 14 * 24 * 60 * 60 -- 14 days

function LC.RequestHistorySync()
    local latest = 0
    for _, e in ipairs(KART_LootHistory or {}) do
        if e.time and e.time > latest then latest = e.time end
    end
    SendLC("LC_HIST_REQ:" .. latest)
end

-- Runs on every peer that receives a sync request; only replies (via whisper-style addon message,
-- never a visible chat message) if it actually has entries the requester is missing.
function LC.HandleHistoryRequest(payload, senderFullName)
    local sinceTime = tonumber(payload)
    if not sinceTime or not senderFullName then return end

    local cutoff = time() - HISTORY_SYNC_MAX_AGE
    local toSend = {}
    for _, e in ipairs(KART_LootHistory or {}) do
        if (e.time or 0) > sinceTime and (e.time or 0) > cutoff then
            table.insert(toSend, e)
        end
    end
    if #toSend == 0 then return end

    table.sort(toSend, function(a, b) return (a.time or 0) < (b.time or 0) end)
    if #toSend > HISTORY_SYNC_MAX_ENTRIES then
        local trimmed = {}
        for i = #toSend - HISTORY_SYNC_MAX_ENTRIES + 1, #toSend do
            table.insert(trimmed, toSend[i])
        end
        toSend = trimmed
    end

    C_Timer.After(math.random() * 2, function()
        for _, e in ipairs(toSend) do
            local colorPacked = ""
            if e.color then
                colorPacked = string.format("%d,%d,%d",
                    math.floor(e.color.r * 255), math.floor(e.color.g * 255), math.floor(e.color.b * 255))
            end
            -- itemLink is last on purpose: item links are full of colons internally.
            local msg = string.format("LC_HIST_ENTRY:%d:%s:%s:%s:%s:%s:%s",
                e.time or 0, e.winner or "", e.difficulty or "", e.reason or "", e.class or "", colorPacked, e.item or "")
            C_ChatInfo.SendAddonMessage("KART", msg, "WHISPER", senderFullName)
        end
    end)
end

-- Runs on the requester when a peer whispers back a missing entry.
function LC.HandleHistoryEntry(payload)
    local t, winner, difficulty, reason, classFile, colorPacked, itemLink =
        payload:match("^(%d+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
    t = tonumber(t)
    if not t or not winner then return end

    KART_LootHistory = KART_LootHistory or {}
    for _, e in ipairs(KART_LootHistory) do
        if e.time == t and e.winner == winner and e.item == itemLink then
            return -- already have it (e.g. another peer answered first)
        end
    end

    local color
    if colorPacked and colorPacked ~= "" then
        local cr, cg, cb = colorPacked:match("^(%d+),(%d+),(%d+)$")
        if cr then color = {r = tonumber(cr) / 255, g = tonumber(cg) / 255, b = tonumber(cb) / 255} end
    end

    table.insert(KART_LootHistory, {
        time       = t,
        item       = itemLink or "",
        winner     = winner,
        reason     = reason or "",
        class      = (classFile ~= "" and classFile) or nil,
        color      = color,
        difficulty = difficulty or "",
    })
    if #KART_LootHistory > MAX_HISTORY_ENTRIES then
        table.remove(KART_LootHistory, 1)
    end
    if KART.LH and KART.LH.historyWindow and KART.LH.historyWindow:IsShown() then
        KART.LH.Refresh()
    end
end

-- rollID -> shortName of whoever this roll has already been awarded to (guards against accidental
-- double-assignment when the assign menu is used more than once for the same item).
LC.assignedWinners = LC.assignedWinners or {}

StaticPopupDialogs["KART_LC_REASSIGN_CONFIRM"] = { ---@diagnostic disable-line: undefined-global
    text = "Already assigned.", -- unconditionally overwritten with KART.L.LC_REASSIGN_CONFIRM_TEXT in LC.AssignWinner below
    button1 = YES, ---@diagnostic disable-line: undefined-global
    button2 = NO,  ---@diagnostic disable-line: undefined-global
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function DoAssignWinner(rollID, playerKey, reason, colorDef)
    local classFile
    local unit = KART.Identity.FindUnitForKey(playerKey)
    if unit then
        local _, cf = UnitClass(unit)
        classFile = cf
    end
    LC.AnnounceResult(rollID, playerKey, reason)

    if IsTestRoll(rollID) then
        -- Test rolls never round-trip through the network (see AnnounceResult), so if the
        -- tester assigned the win to themselves, trigger the "you win" popup locally instead —
        -- and skip writing a fake entry into the real, persistent loot history.
        local myKey = (KART.Identity.ResolvePlayer("player"))
        if playerKey == myKey then
            LC.ShowWinnerNotification(LC.rollItems[rollID])
        end
    else
        LC.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(playerKey), reason, classFile, colorDef, rollID)
        -- Only the client that actually holds the item (the designated lootmaster, see
        -- LC.GetLootmaster/ForceWinRoll) needs a trade reminder — when the assigner (usually the
        -- raid leader) isn't also the lootmaster, they never physically have the item to trade.
        if LC.IsMe(LC.GetLootmaster()) then
            LC.AddPendingTrade(rollID, playerKey)
        end
    end
    LC.assignedWinners[rollID] = playerKey
end

-- Awards the item to playerKey (a resolved player identity, see KART.Identity.ResolvePlayer) with
-- the given reason (may be "" for no reason) and logs it. colorDef is the vote-button definition
-- the reason was taken from (nil for "no reason"). If this rollID was already assigned, asks for
-- confirmation first to avoid accidental double entries.
function LC.AssignWinner(rollID, playerKey, reason, colorDef)
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
function LC.AddPendingTrade(rollID, playerKey)
    if IsTestRoll(rollID) then return end
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.RemovePendingTrade(rollID)
    if playerKey == myKey then return end

    table.insert(LC.pendingTrades, {rollID = rollID, itemLink = LC.rollItems[rollID], winnerKey = playerKey})
    LC.RefreshTradeReminder()
end

-- Removes the pending-trade entry for rollID, if any (reassignment, manual dismiss, or after the
-- item was successfully placed into an open trade window).
function LC.RemovePendingTrade(rollID)
    for i = #LC.pendingTrades, 1, -1 do
        if LC.pendingTrades[i].rollID == rollID then
            table.remove(LC.pendingTrades, i)
        end
    end
    LC.RefreshTradeReminder()
end

-- Fully forgets rollID's tracked state (vote/roll data, cached item link, assigned winner)
-- — called when a tab is dismissed or a session ends, so a later real roll that happens to
-- reuse the same small rollID integer never inherits stale data from a previous boss
-- (see the "wrong item posted on right-click assign" and "stale tabs after next boss" reports).
-- Note: pending trades are NOT cleared here; they are independent long-lived obligations that
-- should only be removed when the trade actually completes, is manually marked done, or is
-- reassigned to someone else.
function LC.ClearRollState(rollID)
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

function LC.CreateTradeReminderFrame()
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
function LC.RefreshTradeReminder()
    if #LC.pendingTrades == 0 then
        if LC.tradeReminderFrame then LC.tradeReminderFrame:Hide() end
        return
    end

    if not LC.tradeReminderFrame then LC.CreateTradeReminderFrame() end
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
        row.doneBtn:SetScript("OnClick", function() LC.RemovePendingTrade(capturedRollID) end)
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
    return IsRealItemLink(link) and link:match("(item:[%-%d:]+)") or nil
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
function LC.OnTradeShow()
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
function LC.OnTradeClosed()
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
        if entry.winnerKey == partnerKey and IsRealItemLink(entry.itemLink) and not FindItemInBags(entry.itemLink) then
            LC.RemovePendingTrade(entry.rollID)
        end
    end
end

--- Manually sets (overrides) a player's vote in the council panel — e.g. they voted verbally or
--- via whisper instead of clicking the vote popup. Purely a local display correction: unlike
--- AssignWinner, this never announces anything, never touches loot history, and never triggers
--- the reassignment-confirmation dialog. Any note the player already attached is kept as-is.
function LC.SetPlayerVote(rollID, playerKey, buttonIdx)
    LC.votes[rollID] = LC.votes[rollID] or {}
    local prev = LC.votes[rollID][playerKey]
    local note = (type(prev) == "table" and prev.note) or ""
    LC.votes[rollID][playerKey] = {idx = buttonIdx, note = note}

    if LC.councilPanel and LC.councilPanel:IsShown() then
        if LC.activeRollID == rollID then LC.RefreshCouncilRows() end
        LC.RefreshCouncilTabs()
    end
end

-- Toggles this council member's own (non-binding) pick for who should get rollID — clicking the
-- same candidate again retracts it, clicking a different one replaces it (one pick per item per
-- council member). Test rolls stay local like everywhere else; real rolls broadcast so every
-- council member's tally stays in sync.
function LC.ToggleCouncilVote(rollID, candidateKey)
    local myKey = (KART.Identity.ResolvePlayer("player"))
    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    local retracting = (LC.councilVotes[rollID][myKey] == candidateKey)
    LC.councilVotes[rollID][myKey] = (not retracting) and candidateKey or nil

    if not IsTestRoll(rollID) then
        SendLC("LC_CVOTE:" .. rollID .. ":" .. (retracting and "" or candidateKey))
    end

    LC.RefreshCouncilRows()
end

-- =====================================================================
--  Officer Notes  (persistent, per-player — not tied to any one item/roll)
-- =====================================================================
-- Distinct from the per-vote note a raider attaches to their own vote: this is a standing
-- council note about a PERSON (e.g. "already has BIS trinket", "missed the last two items"),
-- visible on every item they show up on. Saved locally (KART_LCOfficerNotes, survives reload)
-- and broadcast on edit so every currently-online council member's client converges — there's
-- no catch-up sync on raid join the way loot history has, so someone who was offline when a
-- note was written won't see it until it's edited again while they're online.
function LC.SetOfficerNote(playerKey, noteText)
    noteText = KART.TrimString(noteText or "")
    KART_LCOfficerNotes[playerKey] = (noteText ~= "") and noteText or nil
    SendLC("LC_ONOTE:" .. playerKey .. ":" .. noteText)
    LC.RefreshCouncilRows()
end

function LC.HandleOfficerNote(payload, senderKey)
    if not IsSenderCouncil(senderKey) then return end
    local subjectKey, noteText = payload:match("^([^:]+):(.*)$")
    if not subjectKey then return end
    KART_LCOfficerNotes[subjectKey] = (noteText ~= "") and noteText or nil

    if LC.councilPanel and LC.councilPanel:IsShown() then
        LC.RefreshCouncilRows()
    end
end

-- Re-resolves one legacy (short-name-text-keyed) KART_LCOfficerNotes entry to a GUID-based key,
-- if the named player can currently be resolved (live in the group, or previously cached — see
-- KART.Identity.ResolvePlayer). Returns true if it migrated the entry, false if it's still
-- unresolvable (left untouched, never deleted, so no note is ever silently lost — retried again
-- next time this runs, see the GROUP_ROSTER_UPDATE hook that calls this).
function LC.MigrateOfficerNoteKey(oldKey)
    if KART.Identity.IsResolvedKey(oldKey) then return false end -- already migrated
    local newKey, isPending = KART.Identity.ResolvePlayer(oldKey)
    if isPending then return false end
    KART_LCOfficerNotes[newKey] = KART_LCOfficerNotes[oldKey]
    KART_LCOfficerNotes[oldKey] = nil
    return true
end

-- A hand-rolled little dialog instead of StaticPopupDialogs — retail's StaticPopup system was
-- reworked (routes through Blizzard_StaticPopup_Game/GameDialog.lua now) and no longer reliably
-- exposes the edit box as `self.editBox` inside OnAccept (errored with "attempt to index field
-- 'editBox' (a nil value)" there, even though OnShow's `self.editBox` worked fine — the popup
-- frame passed to the two callbacks isn't consistently the same shape). Owning the whole frame
-- ourselves means the edit box reference is always exactly what we created it as.
function LC.ShowOfficerNoteDialog(playerKey, playerDisplayName)
    if not LC.officerNoteDialog then
        local f = CreateFrame("Frame", "KART_LCOfficerNoteDialog", UIParent, "BackdropTemplate")
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

        f.editBox = KART.CreateStyledEditBox(f, "KART_LCOfficerNoteEditBox")
        f.editBox:SetSize(260, 26)
        f.editBox:SetPoint("TOP", 0, -46)
        f.editBox:SetMaxLetters(120)
        -- Fallback font until the next KART.UpdateStyles pass — this dialog is created lazily,
        -- long after the login-time style pass already ran.
        f.editBox:SetFontObject("GameFontHighlightSmall")

        local function accept()
            if f.key then LC.SetOfficerNote(f.key, f.editBox:GetText()) end
            f:Hide()
        end

        local btnOK = KART.CreateModernButton(f, OKAY) ---@diagnostic disable-line: undefined-global
        btnOK:SetSize(120, 26)
        btnOK:SetPoint("BOTTOMLEFT", 15, 12)
        btnOK:SetScript("OnClick", accept)

        local btnCancel = KART.CreateModernButton(f, CANCEL) ---@diagnostic disable-line: undefined-global
        btnCancel:SetSize(120, 26)
        btnCancel:SetPoint("BOTTOMRIGHT", -15, 12)
        btnCancel:SetScript("OnClick", function() f:Hide() end)

        f.editBox:SetScript("OnEnterPressed", accept)
        f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)

        LC.officerNoteDialog = f
    end

    local f = LC.officerNoteDialog
    f.key = playerKey
    f.title:SetText(string.format(KART.L.LC_OFFICER_NOTE_PROMPT, playerDisplayName))
    f.editBox:SetText(KART_LCOfficerNotes[playerKey] or "")
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end

--- Right-click menu on a council row: quick-assign, manually correct this player's vote, or
--- assign without a reason. Assign / Assign-without-reason are the only two actions that go
--- through AssignWinner (which announces the result and asks for reassignment confirmation if
--- the item was already assigned to someone else) — "Change vote" only edits which vote is shown
--- for this player (e.g. they voted verbally/via whisper) and must never assign anything itself.
function LC.ShowAssignMenu(anchor, rollID, playerKey, playerDisplayName, voteDef)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(playerDisplayName)

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN, function()
            LC.AssignWinner(rollID, playerKey, voteDef and voteDef.label or "", voteDef)
        end)

        -- No callback here on purpose: this makes CreateButton return a submenu descriptor.
        local changeMenu = rootDescription:CreateButton(KART.L.LC_MENU_CHANGE_VOTE) ---@diagnostic disable-line: missing-parameter
        for i, def in ipairs(LC.GetButtonConfig()) do
            changeMenu:CreateButton(def.label, function()
                LC.SetPlayerVote(rollID, playerKey, i)
            end)
        end

        rootDescription:CreateButton(KART.L.LC_MENU_ASSIGN_NO_REASON, function()
            LC.AssignWinner(rollID, playerKey, "", nil)
        end)

        rootDescription:CreateButton(KART.L.LC_MENU_EDIT_NOTE, function()
            LC.ShowOfficerNoteDialog(playerKey, playerDisplayName)
        end)
    end)
end

function LC.ShowWinnerNotification(itemLink)
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

-- =====================================================================
--  Addon Message Handlers  (called from Core.lua CHAT_MSG_ADDON)
-- =====================================================================

function LC.HandleActive(value)
    LC.sessionActive = (value == "1")
end

function LC.HandleStart(payload)
    -- payload = "rollID:seconds"
    local rollID, secs = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    secs   = tonumber(secs)
    if not rollID then return end

    LC.votes[rollID]     = LC.votes[rollID] or {}
    LC.rollItems[rollID] = GetLootRollItemLink(rollID) or LC.rollItems[rollID] or "???"
    if LC.rollItems[rollID] == "???" then ResolveRollItemLink(rollID) end
    -- Auto-Pass already runs unconditionally in OnStartLootRoll for this player's own roll,
    -- so there's nothing left to do here for that.

    if IsCouncil() then
        LC.ShowCouncilPanel(rollID, secs or 20)
    else
        LC.ShowVotePopup(rollID, LC.rollItems[rollID], secs or 20)
    end
end

function LC.HandleVote(payload, senderKey)
    -- payload = "rollID:buttonIndex:note"
    local rollID, idx = payload:match("^(%d+):(%d+)")
    rollID = tonumber(rollID)
    idx    = tonumber(idx)
    if not rollID or not idx then return end

    local note = payload:match("^%d+:%d+:(.*)") or ""

    LC.votes[rollID] = LC.votes[rollID] or {}
    LC.votes[rollID][senderKey] = {idx = idx, note = note}

    if LC.councilPanel and LC.councilPanel:IsShown() then
        -- Row list only matters for whichever roll is the active tab; the vote-count badge on
        -- every tab (including inactive ones) should stay live regardless.
        if LC.activeRollID == rollID then LC.RefreshCouncilRows() end
        LC.RefreshCouncilTabs()
    end
end

-- Receives another raider's automatic 1-100 roll (see LC.OnStartLootRoll) — opt-in, analogous to
-- RCLootCouncil's Need roll. Purely informational, shown as its own column; never used to decide
-- anything automatically.
function LC.HandleRoll(payload, senderKey)
    local rollID, value = payload:match("^(%d+):(%d+)$")
    rollID = tonumber(rollID)
    value  = tonumber(value)
    if not rollID or not value then return end

    LC.rolls[rollID] = LC.rolls[rollID] or {}
    LC.rolls[rollID][senderKey] = value

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        LC.RefreshCouncilRows()
    end
end

-- Receives a council member's (non-binding) pick for who should get rollID — a straw-poll tally
-- only, never an assignment by itself. Like LC_VOTE, this trusts the sender rather than
-- re-verifying council membership over the wire (the panel that sends it is only ever shown to
-- council members in the first place — see IsCouncil in HandleStart/OnStartLootRoll).
function LC.HandleCouncilVote(payload, senderKey)
    local rollID, candidateKey = payload:match("^(%d+):(.*)$")
    rollID = tonumber(rollID)
    if not rollID then return end

    LC.councilVotes[rollID] = LC.councilVotes[rollID] or {}
    if candidateKey == "" then
        LC.councilVotes[rollID][senderKey] = nil -- retracted their pick
    else
        LC.councilVotes[rollID][senderKey] = candidateKey
    end

    if LC.councilPanel and LC.councilPanel:IsShown() and LC.activeRollID == rollID then
        LC.RefreshCouncilRows()
    end
end

-- Finds the button definition (with its color) whose label matches reason, for entries received
-- from other clients where only the label string traveled over the wire, not the color itself.
function LC.ResolveColorForReason(reason)
    if not reason or reason == "" then return nil end
    for _, def in ipairs(LC.GetButtonConfig()) do
        if def.label == reason then return def end
    end
    return nil
end

function LC.HandleResult(payload, senderKey)
    if not IsSenderCouncil(senderKey) then return end
    -- payload = "rollID:winnerKey:reason"
    local rollID, winnerKey = payload:match("^(%d+):([^:]+)")
    rollID = tonumber(rollID)
    if not rollID or not winnerKey then return end
    local reason = payload:match("^%d+:[^:]+:(.*)$") or ""

    -- A result came in for this roll — remove it from our vote list, if it's still there.
    LC.RemoveVoteListItem(rollID)

    if winnerKey == "NONE" then return end

    local myKey = (KART.Identity.ResolvePlayer("player"))
    if winnerKey == myKey then
        LC.ShowWinnerNotification(LC.rollItems[rollID])
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
    LC.LogHistory(LC.rollItems[rollID], KART.Identity.ResolveDisplayName(winnerKey), reason, classFile, LC.ResolveColorForReason(reason), rollID)

    -- Same reasoning as DoAssignWinner: only the client physically holding the item (the
    -- designated lootmaster) needs a pending-trade reminder, regardless of who assigned it.
    if LC.IsMe(LC.GetLootmaster()) then
        LC.AddPendingTrade(rollID, winnerKey)
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
        showCouncil = IsCouncil() and IsInGroup()
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
        if IsTestRoll(rid) then sessionActive = true break end
    end
    if not sessionActive then
        for _, rid in ipairs(LC.councilTabs) do
            if IsTestRoll(rid) then sessionActive = true break end
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
            LC.ShowCouncilPanel(testRollID, KART_Settings.lcVoteSeconds or 20)
        else
            LC.ShowVotePopup(testRollID, LC.rollItems[testRollID], KART_Settings.lcVoteSeconds or 20)
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

function LC.BuildSettingsPanel(parent)
    local L = KART.L

    KART.CreateTabTitle(5, L.LC_SETTINGS_TITLE)

    -- Personal preferences card (module toggle, autopass, Droptimizer slot at -75,
    -- compact vote layout, nicknames). Raid-wide settings live in the amber box below.
    local prefsCard = KART.CreateCard(parent)
    prefsCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -12)
    prefsCard:SetSize(500, 165)
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
        LC.RefreshVoteListRowsIfShown, L.LC_DESC_COMPACT_VOTE_LAYOUT)

    -- Personal preference, same reasoning as CbCompactVoteLayout above — purely how names render
    -- on YOUR OWN council panel, never synced. Needs Northern Sky Raid Tools installed with a
    -- nickname set per character to have any visible effect (see KART.GetNickname); falls back to
    -- the character short name automatically otherwise. Slot -135: next free step below
    -- CbCompactVoteLayout, inside this card.
    KART.LC.CbShowNickNames = KART.CreateSettingsCheckbox(
        prefsCard, "KART_LCShowNickNames",
        L.LC_SET_SHOW_NICKNAMES, "lcShowNickNames", -135,
        function()
            if LC.councilPanel and LC.councilPanel:IsShown() then LC.RefreshCouncilRows() end
        end, L.LC_DESC_SHOW_NICKNAMES)

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
        raidBox, L.LC_SET_VOTE_TIMER, 5, 60, "lcVoteSeconds",
        -52, "KART_LCVoteTimerSlider", L.LC_DESC_VOTE_TIMER)

    -- Opt-in random 1-100 roll per raider, shown as its own column in the council panel —
    -- analogous to RCLootCouncil's Need roll. Purely informational (see LC.HandleRoll).
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
        if IsInGroup() and UnitIsGroupLeader("player") then
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
end

-- Called at file load time; KART.LootCouncilPanel is created by MainFrame.lua
if KART.LootCouncilPanel then
    LC.BuildSettingsPanel(KART.LootCouncilPanel)
end
