local addonName, KART = ...
local KAUtil = LibStub("KAUtil-1.0")
local KASC = LibStub("KASC-1.0")

-- Cache-Tabellen
KART.InviteKeywordsTable = {}
KART.PromoteNamesTable = {}

-- Aktualisiert die lokalen Such-Tabellen basierend auf den Einstellungen
function KART.UpdateCache()
    if KART_Settings then
        local keywords = KAUtil.SplitString(KAUtil.CaseFold(KART_Settings.inviteKeywords or ""), ";")
        KART.InviteKeywordsTable = {}
        for _, kw in ipairs(keywords) do 
            local trimmed = KAUtil.TrimString(kw)
            if trimmed ~= "" then KART.InviteKeywordsTable[trimmed] = true end 
        end

        local names = KAUtil.SplitString(KAUtil.CaseFold(KART_Settings.promoteNames or ""), ";")
        KART.PromoteNamesTable = {}
        for _, name in ipairs(names) do
            -- Trim each entry (like the keywords above) — an untrimmed " bar" from "Foo; Bar" would
            -- never match a short name or NSRT nickname in HandleAutoPromote.
            local trimmed = KAUtil.TrimString(name)
            if trimmed ~= "" then
                KART.PromoteNamesTable[trimmed] = true
                -- Also store a realm-canonicalized form of any "Name-Realm" entry. UnitName returns
                -- a cross-realm unit's realm in its DISPLAY spelling ("Tarren Mill"), while a name
                -- pasted from the WoWUtils export carries the normalized one ("TarrenMill") — so the
                -- realm-qualified branch of HandleAutoPromote could never match for those players
                -- and they were silently never promoted (B15). Same canonicalization
                -- KAUtil.IsFullNameInGroup has always applied for the same reason.
                local base, realm = trimmed:match("^(.-)%-(.+)$")
                if base and realm then
                    KART.PromoteNamesTable[base .. "-" .. KAUtil.CanonRealm(realm)] = true
                end
            end
        end
    end
end

-- Logik für Keyword-Einladungen
function KART.HandleChatInvite(msg, sender, event, ...)
    if type(msg) ~= "string" then return end
    local message = KAUtil.TrimString(KAUtil.CaseFold(msg))

    if KART.InviteKeywordsTable[message] and (not IsInGroup() or KAUtil.HasGroupPermissions()) then
        if KART_Settings.autoConvertToRaid and UnitIsGroupLeader("player") and IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 and not InCombatLockdown() then
            C_PartyInfo.ConvertToRaid()
        end

        if event == "CHAT_MSG_BN_WHISPER" then
            local bnetIDAccount = select(11, ...)
            if bnetIDAccount then
                local accountInfo = C_BattleNet.GetAccountInfoByID(bnetIDAccount)
                local ga = accountInfo and accountInfo.gameAccountInfo
                -- InviteUnit needs a character name, not the numeric gameAccountID (passing the ID
                -- silently invites nobody). Resolve the friend's current WoW character from their
                -- Battle.net account info and invite that.
                if ga and ga.characterName and ga.characterName ~= "" then
                    local target = ga.characterName
                    if ga.realmName and ga.realmName ~= "" then
                        target = target .. "-" .. ga.realmName
                    end
                    C_PartyInfo.InviteUnit(target)
                end
            end
        else
            C_PartyInfo.InviteUnit(sender)
        end
    end
end

-- GROUP_ROSTER_UPDATE fires in bursts during mass-invite/raid formation, and a full roster scan on
-- every single firing burns CPU for no benefit — the promote outcome only needs re-evaluating once
-- the roster has settled. Same leading-edge throttle pattern as KART.UpdateBuffCheckThrottled.
local isAutoPromoteThrottled = false
function KART.HandleAutoPromoteThrottled()
    if isAutoPromoteThrottled then return end
    isAutoPromoteThrottled = true
    C_Timer.After(1, function()
        isAutoPromoteThrottled = false
        KART.HandleAutoPromote()
    end)
end

-- Logik für Auto-Promote
function KART.HandleAutoPromote()
    if not UnitIsGroupLeader("player") or not IsInGroup() then return end -- IsInRaid implies IsInGroup
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local shortName = name -- UnitName's first return is already realm-free
            -- Matches either the character's own short name (as always) or its Northern Sky Raid
            -- Tools nickname (see KASC.Identity.GetNickname), so a name in the promote list applies to
            -- every character sharing that nickname, not just one specific alt.
            local matches = shortName and KART.PromoteNamesTable[KAUtil.CaseFold(shortName)]
            if not matches and realm and realm ~= "" then
                -- Also accept a realm-qualified entry. "Name-Realm" is the format the WoWUtils
                -- export uses and the format this function itself passes to PromoteToAssistant, so a
                -- user copying a name from there would otherwise never get promoted.
                --
                -- Both spellings, because the two sides disagree: UnitName gives a cross-realm unit
                -- its display realm ("Tarren Mill") while the export gives the normalized one
                -- ("TarrenMill"). UpdateCache stores a canonicalized key alongside the raw entry,
                -- so checking the canonical form here closes the gap from the other end too (B15).
                local folded = KAUtil.CaseFold(name)
                matches = KART.PromoteNamesTable[folded .. "-" .. KAUtil.CaseFold(realm)]
                       or KART.PromoteNamesTable[folded .. "-" .. KAUtil.CanonRealm(realm)]
            end
            if not matches then
                local nick = KASC.Identity.GetNickname(unit)
                matches = nick ~= nil and KART.PromoteNamesTable[nick]
            end
            if matches then
                if not UnitIsGroupAssistant(unit) and not UnitIsGroupLeader(unit) then
                    -- Promote the specific character (full Name-Realm), not the realm-free short
                    -- name — two same-named cross-realm raiders would otherwise be ambiguous. The
                    -- NSRT nickname is only used for MATCHING above; the promote targets the real
                    -- character.
                    local target = (realm and realm ~= "") and (name .. "-" .. realm) or name
                    PromoteToAssistant(target)
                end
            end
        end
    end
end
