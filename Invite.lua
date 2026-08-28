local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")

KART.WU = KART.WU or {}
local WU = KART.WU

WU.bosses = {}  -- { encounterID, difficulty, name, players[] }

-- =====================================================================
--  Parser
-- =====================================================================

-- Parses a notes / WoWUtils paste into WU.bosses. Each EncounterID: block is
-- one boss; invitelist: may sit after timer lines. Header fields are matched
-- by name (EncounterID / Difficulty / Name), not by order. Blocks with no
-- invitelist are skipped (notes-only). Callers that need a fresh library wipe
-- WU.bosses first (ReplaceImportedText, SyncBossesToSavedText).
function WU.ParseImport(rawText)
    if not rawText or KAUtil.TrimString(rawText) == "" then return 0 end

    local parsedCount = 0
    local starts = {}
    local pos = 1
    while true do
        local s = rawText:find("EncounterID:", pos, true)
        if not s then break end
        starts[#starts + 1] = s
        pos = s + 12
    end

    local function addBoss(encounterID, difficulty, bossName, playerStr)
        local players = {}
        if playerStr:find(",", 1, true) then
            for p in playerStr:gmatch("[^,]+") do
                p = KAUtil.TrimString(p)
                if p ~= "" then table.insert(players, p) end
            end
        else
            for p in playerStr:gmatch("%S+") do
                table.insert(players, p)
            end
        end
        if #players == 0 then return end

        parsedCount = parsedCount + 1
        local groupCount = 0
        for _, boss in ipairs(WU.bosses) do
            if boss.encounterID == encounterID and boss.difficulty == difficulty then
                groupCount = groupCount + 1
            end
        end
        if groupCount == 1 then
            for _, boss in ipairs(WU.bosses) do
                if boss.encounterID == encounterID and boss.difficulty == difficulty then
                    boss.name = boss.baseName .. " A"
                    break
                end
            end
        end
        local name = bossName
        if groupCount > 0 then
            name = bossName .. " " .. string.char(65 + groupCount)
        end
        table.insert(WU.bosses, {
            encounterID = encounterID,
            difficulty  = difficulty,
            name        = name,
            baseName    = bossName,
            players     = players,
        })
    end

    for i = 1, #starts do
        local s = starts[i]
        local e = starts[i + 1] and (starts[i + 1] - 1) or #rawText
        local block = rawText:sub(s, e)
        local firstLine = block:match("^[^\n\r]+") or block
        local enc = tonumber(firstLine:match("EncounterID:(%d+)"))
        local diff = firstLine:match("Difficulty:([^;\n]+)")
        local name = firstLine:match("Name:([^;\n]+)")
        if diff then diff = KAUtil.TrimString(diff) end
        if name then name = KAUtil.TrimString(name) end
        local playerStr = block:match("invitelist:([^;]+)")
        if enc and diff and name and playerStr then
            addBoss(enc, diff, name, KAUtil.TrimString(playerStr))
        end
    end

    if parsedCount > 0 then WU.lastImportedText = rawText end
    return parsedCount
end

-- Notes paste: the blob is the whole evening. Wipe the previous invite library.
function WU.ReplaceImportedText(text)
    text = text or ""
    WU.bosses = {}
    WU.lastImportedText = nil
    WU.activeBossIdx = nil
    local trimmed = KAUtil.TrimString(text)
    local count = 0
    if trimmed ~= "" then
        count = WU.ParseImport(text)
    end
    WU.committedImportText = text
    if KART_Settings then KART_Settings.wuImportText = text end
    if WU.RefreshBossList then WU.RefreshBossList() end
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
    if trimmed == "" then return 0, "empty" end
    return count, "ok"
end

-- Commits a successful paste into KART_Settings.wuImportText. The edit box is a staging
-- area and must not overwrite this on every keystroke: a second paste would otherwise
-- erase the first export from SavedVariables, and a /reload would rebuild only the last
-- one. Sequential imports (Normal then Heroic, or a split roster) append here so login
-- and profile switch can reconstruct the stacked list.
local function CommitImportedText(text)
    local prev = WU.committedImportText
    if not prev or prev == "" then
        WU.committedImportText = text
    elseif prev ~= text then
        WU.committedImportText = prev .. "\n" .. text
    end
    if KART_Settings then KART_Settings.wuImportText = WU.committedImportText end
end

-- Import-button body, without the panel. ParseImport is additive; this function must not
-- wipe WU.bosses. Returns count, status where status is "ok", "same", "empty", or "error".
function WU.ImportPastedText(text)
    if not text or KAUtil.TrimString(text) == "" then return 0, "empty" end
    if text == WU.lastImportedText then
        return #WU.bosses, "same"
    end
    local count = WU.ParseImport(text)
    if count > 0 then
        CommitImportedText(text)
        if WU.RefreshBossList then WU.RefreshBossList() end
        if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
        return count, "ok"
    end
    return 0, "error"
end

-- Makes the in-memory boss list match KART_Settings.wuImportText exactly. Called from
-- KART.SyncSettingsToUI, which runs both at login and on every profile switch — so it must REPLACE
-- the list, not extend it: WU.ParseImport is deliberately additive (several exports can be stacked
-- by hand), which would otherwise leave the previous profile's bosses in place and relabel the
-- collisions "Boss A"/"Boss B". A profile whose import text is empty correctly ends up with no
-- bosses instead of inheriting the previous profile's.
--
-- Deliberately NOT gated on wuModuleEnabled: the module toggle disables the invite/remove ACTIONS
-- (each of those checks it directly) and has no callback of its own, so gating here would empty the
-- list on disable and never rebuild it on re-enable — the list would only come back via a manual
-- Import or a reload.
function WU.SyncBossesToSavedText()
    local text = (KART_Settings and KART_Settings.wuImportText) or ""
    WU.committedImportText = text
    if text == WU.lastImportedText then return end

    WU.bosses = {}
    WU.lastImportedText = nil
    local count = text ~= "" and WU.ParseImport(text) or 0
    if WU.RefreshBossList then WU.RefreshBossList() end
    if WU.statusLabel then
        if count > 0 then
            WU.statusLabel:SetText(string.format(KART.L.WU_STATUS_LOADED, count))
            WU.statusLabel:SetTextColor(0.2, 0.8, 0.2)
        else
            WU.statusLabel:SetText(KART.L.WU_STATUS_EMPTY)
            WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

function WU.ResetBosses()
    WU.bosses = {}
    WU.lastImportedText = nil -- cleared list: allow re-importing the same text again
    WU.committedImportText = nil
    -- Also drop the saved import text, otherwise the login/profile-switch auto-parse in
    -- KART.SyncSettingsToUI re-creates the whole list from it and the reset silently undoes itself
    -- on the next /reload (lastImportedText is a runtime field and never survives a session).
    KART_Settings.wuImportText = ""
    WU.activeBossIdx = nil
    if WU.ImportEditBox then WU.ImportEditBox:SetText("") end
    if WU.RefreshBossList then WU.RefreshBossList() end
    if KART.RefreshStatusStrip then KART.RefreshStatusStrip() end
end

-- =====================================================================
--  Actions
-- =====================================================================

-- Names currently in the group, keyed both as Name and Name-Realm, CaseFolded. Shared by invite
-- skip-logic and the tonight strip's 12/20 count so those two cannot disagree about who is here.
local function GroupNameSet()
    local alreadyIn = {}
    do
        -- Seed with ourselves unconditionally: EachGroupUnit yields nothing while solo, so a bulk
        -- invite started alone would otherwise try to invite the player themselves.
        local myName, myRealm = UnitName("player")
        if myName then
            alreadyIn[KAUtil.CaseFold(myName)] = true
            if myRealm and myRealm ~= "" then alreadyIn[KAUtil.CaseFold(myName.."-"..myRealm)] = true end
            local normalized = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
            if normalized and normalized ~= "" then
                alreadyIn[KAUtil.CaseFold(myName.."-"..normalized)] = true
            end
        end
    end
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local full = (realm and realm ~= "") and (name.."-"..realm) or name
            alreadyIn[KAUtil.CaseFold(full)] = true
            alreadyIn[KAUtil.CaseFold(name)] = true
        end
    end
    return alreadyIn
end

function WU.IndexForEncounter(encID, difficulty)
    encID = tonumber(encID)
    if not encID or type(difficulty) ~= "string" or difficulty == "" then return nil end
    for i, boss in ipairs(WU.bosses) do
        if boss.encounterID == encID and boss.difficulty == difficulty then
            return i
        end
    end
    return nil
end

function WU.ActiveBossIndex()
    local NT = KART.NT
    if NT and KART_Settings then
        local cursor = tonumber(KART_Settings.ntCursor) or 0
        if cursor ~= 0 and NT.RaidMapDiff and NT.DIFFICULTY_NAMES then
            local _, diff = NT.RaidMapDiff()
            local diffName = NT.DIFFICULTY_NAMES[diff]
            local idx = diffName and WU.IndexForEncounter(cursor, diffName)
            if idx then return idx end
        end
    end
    if WU.activeBossIdx and WU.bosses[WU.activeBossIdx] then return WU.activeBossIdx end
    if WU.bosses[1] then return 1 end
    return nil
end

-- How many of this boss's pasted names are already in the group. Denominator is the list
-- length, not GetNumGroupMembers: extras in the raid who are not on the list do not inflate 12/20.
function WU.GroupPresenceForBoss(idx)
    local boss = WU.bosses[idx]
    if not boss then return 0, 0 end
    local alreadyIn = GroupNameSet()
    local present = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)] then
            present = present + 1
        end
    end
    return present, #boss.players
end

function WU.InviteBoss(idx)
    if KART_Settings.wuModuleEnabled == false then
        print("|cff00ff00KART:|r " .. KART.L.WU_MODULE_DISABLED_MSG)
        return
    end
    local boss = WU.bosses[idx]
    if not boss then return end
    WU.activeBossIdx = idx
    -- "Not in a group at all" is not a lack of permission, it is the ordinary starting point: open
    -- the tab before the evening, click the first boss, and the invites go out. HasGroupPermissions
    -- answers false while ungrouped -- correctly, there is no group to lead -- so gating on it alone
    -- refused this feature at its main use, with a "you are not the leader" that made no sense to
    -- somebody standing alone. Same shape KART.HandleChatInvite has always used for the same reason.
    --
    -- The deferred raid conversion further down (KART.pendingBulkRaidConvert) exists only for the
    -- solo case and could never be reached, which is what gave this away.
    if IsInGroup() and not KAUtil.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
        return
    end

    -- Same lookup Invite and the tonight strip share, including the solo self-seed: EachGroupUnit
    -- yields nothing while solo, so without it a bulk invite started alone would try to invite the
    -- player themselves.
    local alreadyIn = GroupNameSet()

    -- Count who we'd actually invite (not already present) so we can decide up front whether the
    -- roster needs to be a raid. A party caps at 5, so without converting, invites past slot 5
    -- silently fail. Convert an existing party right now; if we're still solo, flag Core's
    -- GROUP_ROSTER_UPDATE handler to convert the moment the invitees fill the party — see
    -- KART.pendingBulkRaidConvert in Core.lua. An explicit bulk invite always intends a raid, so
    -- this ignores the autoConvertToRaid preference. (In-combat already returned above.)
    local toInvite = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if not (alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)]) then toInvite = toInvite + 1 end
    end
    -- Solo counts too: UnitIsGroupLeader("player") is false when ungrouped, which would skip the
    -- else-branch that flags the deferred conversion — so gate on "solo OR party leader" instead.
    -- (A party non-leader can't convert anyway, and a raid needs no conversion.)
    if (not IsInGroup() or UnitIsGroupLeader("player")) and not IsInRaid() and (GetNumGroupMembers() + toInvite) > 5 then
        if IsInGroup() then
            C_PartyInfo.ConvertToRaid()
        else
            KART.pendingBulkRaidConvert = true
            -- Expire the flag if the invites never land. It is otherwise only cleared once we're in
            -- a raid or out of a group, so a bulk invite nobody accepts would leave it armed for the
            -- session and silently convert some unrelated 5-man party an hour later.
            C_Timer.After(120, function() KART.pendingBulkRaidConvert = false end)
        end
    end

    local invited = 0
    local skipped = 0
    for _, player in ipairs(boss.players) do
        local short = player:match("([^%-]+)") or player
        if alreadyIn[KAUtil.CaseFold(player)] or alreadyIn[KAUtil.CaseFold(short)] then
            skipped = skipped + 1
        else
            C_PartyInfo.InviteUnit(player)
            invited = invited + 1
        end
    end

    local msg = string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_INVITED, invited, boss.name)
    if skipped > 0 then
        msg = msg .. string.format(" " .. KART.L.WU_MSG_ALREADY_IN, skipped)
    end
    print(msg)
end

-- Who WU.RemoveForBoss would uninvite, as full "Name-Realm" strings. Split out from the removing
-- itself so the confirmation below can say how many people it is about to throw out before it does.
--
-- Never ourselves. EachGroupUnit yields raid1..raidN in a raid and never the literal "player" token,
-- so a plain unit ~= "player" guard would fail to exclude your own raid slot — UnitIsUnit matches the
-- player under whatever token currently represents them, so a roster that does not list you cannot
-- get you kicked from your own raid.
local function PlanRemoval(boss)
    local keepSet = {}
    for _, p in ipairs(boss.players) do
        -- CaseFold (not :lower()) so umlaut names fold consistently with the roster check below.
        keepSet[KAUtil.CaseFold(p)] = true
        local short = p:match("([^%-]+)")
        if short then keepSet[KAUtil.CaseFold(short)] = true end
    end

    local out = {}
    for unit in KAUtil.EachGroupUnit() do
        if not UnitIsUnit(unit, "player") then
            local name, realm = UnitName(unit)
            if name then
                local full = (realm and realm ~= "") and (name.."-"..realm) or name
                if not keepSet[KAUtil.CaseFold(full)] and not keepSet[KAUtil.CaseFold(name)] then
                    -- The specific character (full Name-Realm) — the realm-free short name is
                    -- ambiguous when a same-named cross-realm twin is in the group.
                    out[#out + 1] = full
                end
            end
        end
    end
    return out
end

-- Removes current group members who are NOT in the boss's player list.
--
-- Asks first (B96). This is the most destructive thing the addon can do: it throws real people out
-- of the raid, they have to be re-invited and accept again, and there is no undo — while the button
-- is seventy pixels wide and sits directly beside "Invite". Resetting the boss LIST already asked,
-- and says "this cannot be undone"; removing people asked nothing at all.
--
-- The count is in the question, because "remove everyone not on this roster" reads very differently
-- when the answer is two people and when it is eighteen.
function WU.RemoveForBoss(idx)
    if KART_Settings.wuModuleEnabled == false then
        print("|cff00ff00KART:|r " .. KART.L.WU_MODULE_DISABLED_MSG)
        return
    end
    local boss = WU.bosses[idx]
    if not boss then return end
    -- Leader OR assistant may uninvite in-game, so gate the same way WU.InviteBoss does rather than
    -- being stricter (leader-only) for no reason.
    if not KAUtil.HasGroupPermissions() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
        return
    end
    if InCombatLockdown() then
        print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
        return
    end

    local targets = PlanRemoval(boss)
    -- Nobody to remove: say so and ask nothing. A confirmation for a no-op is worse than none at
    -- all — it trains people to click straight through the one that matters.
    if #targets == 0 then
        print(string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_REMOVED, 0, boss.name))
        return
    end

    local dlg = StaticPopupDialogs["KART_WU_REMOVE_CONFIRM"]
    -- The template, not a pre-formatted string: the count rides in as a show argument below, which is
    -- how KART_WU_RESET_CONFIRM and KART_LC_REASSIGN_CONFIRM both do it. Formatting here AND passing
    -- the argument worked only because the finished text no longer contained a placeholder for it to
    -- land in -- a second one added to the locale string later would have found a filled-in text and
    -- an argument list that no longer matched it.
    dlg.text = KART.L.WU_REMOVE_CONFIRM_TEXT
    dlg.button1, dlg.button2 = KART.L.BTN_ACCEPT, KART.L.BTN_CANCEL
    -- The targets are resolved NOW and carried into the dialog, not re-derived on accept: the roster
    -- can change while the question sits on screen, and what the player agreed to is the number they
    -- were shown.
    StaticPopup_Show("KART_WU_REMOVE_CONFIRM", #targets, nil, { targets = targets, name = boss.name })
end

KART.UI:RegisterStaticPopup("KART_WU_REMOVE_CONFIRM", {
    text = "Remove %d players from the raid?", -- overwritten with KART.L.WU_REMOVE_CONFIRM_TEXT before every StaticPopup_Show
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data)
        if not (data and data.targets) then return end
        -- Both gates again, HERE (B108). WU.RemoveForBoss checks them when the question is asked, and
        -- what a confirmation is for is time to think -- during which the raid does not stand still.
        -- Losing lead mid-question is ordinary (a handover, a disconnect moving it), and the pull can
        -- land while the dialog is up.
        --
        -- The two fail differently, and the combat one is the reason this is a fix and not a tidy-up:
        -- UninviteUnit is NOT combat-protected, so the removals would genuinely go through mid-pull,
        -- which is exactly what the gate above exists to stop. Without lead the game refuses them
        -- instead -- the right outcome, but the count below is of attempts, not of successes, so it
        -- reported "2 players removed" to somebody who removed nobody.
        if not KAUtil.HasGroupPermissions() then
            print("|cff00ff00KART:|r " .. KART.L.WU_MSG_NOT_LEADER)
            return
        end
        if InCombatLockdown() then
            print("|cff00ff00KART:|r " .. KART.L.WU_MSG_COMBAT)
            return
        end
        local removed = 0
        for _, full in ipairs(data.targets) do
            UninviteUnit(full)
            removed = removed + 1
        end
        print(string.format("|cff00ff00KART:|r " .. KART.L.WU_MSG_REMOVED, removed, data.name))
    end,
})

KART.UI:RegisterStaticPopup("KART_WU_RESET_CONFIRM", {
    text = "Really reset the boss list?", -- overwritten with KART.L.WU_RESET_CONFIRM_TEXT before every StaticPopup_Show call below
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        WU.ResetBosses()
        if WU.statusLabel then
            WU.statusLabel:SetText(KART.L.WU_STATUS_EMPTY)
            WU.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end,
})

-- Notes owns the boss-list chrome (count, Invite, Remove). Parser / invite /
-- remove stay here so the tonight strip and bulk invite keep one owner.
function WU.RefreshBossList()
    if KART.NT and type(KART.NT.RefreshBossList) == "function" then
        KART.NT.RefreshBossList()
    end
end

function WU.SyncWidgets()
    local settingsMap = {}
    if KART.CbWuModule then settingsMap[KART.CbWuModule] = "wuModuleEnabled" end
    KART.ApplySettingsMap(settingsMap)
end

