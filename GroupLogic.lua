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
                -- Also store a realm-canonicalized form of any "Name-Realm" entry. The two sides
                -- spell a realm differently — UnitName gives a cross-realm unit its DISPLAY realm
                -- ("Tarren Mill") while a list can just as easily carry the normalized one
                -- ("TarrenMill") — so the realm-qualified branch of HandleAutoPromote could never
                -- match one against the other, and those players were silently never promoted (B15).
                -- Same canonicalization KAUtil.IsFullNameInGroup has always applied for the same
                -- reason.
                local base, realm = trimmed:match("^(.-)%-(.+)$")
                if base and realm then
                    KART.PromoteNamesTable[base .. "-" .. KAUtil.CanonRealm(realm)] = true
                end
            end
        end
    end
end

-- Auto-reply when a keyword matched but no invite went out (not leader, full party with convert
-- off, or combat). Whispers the sender only -- never the guild/officer channel -- debounced per
-- name so a burst of messages does not spam.
KART.inviteAutoReplyAt = KART.inviteAutoReplyAt or {}

function KART.MaybeInviteAutoReply(sender, reasonKey)
    if not sender or sender == "" then return end
    if KAUtil.IsSecret(sender) then return end
    local now = GetTime()
    local debounceKey = KAUtil.CaseFold(sender)
    local last = KART.inviteAutoReplyAt[debounceKey]
    if last and (now - last) < 5 then return end
    KART.inviteAutoReplyAt[debounceKey] = now
    local msg = KART.L["INVITE_REPLY_" .. reasonKey]
    if msg and msg ~= "" then
        SendChatMessage(msg, "WHISPER", nil, sender)
    end
end

-- Logik für Keyword-Einladungen
function KART.HandleChatInvite(msg, sender, event, ...)
    -- Explicit false only: a missing key (older SavedVariables, isolated tests) keeps the
    -- historic default-on behaviour. MergeDefaults fills the key on a live login.
    if KART_Settings.autoModuleEnabled == false then return end
    if type(msg) ~= "string" then return end
    -- A message the client will not let us read cannot be checked against the invite keyword, so
    -- there is nothing to decide here. The type check above does NOT cover this: a secret string
    -- answers "string" and then throws on the first string operation, which is how this arrived --
    -- 54 errors in one session of world content, one per incoming whisper (GitHub #17). Stopping
    -- here rather than inside KAUtil.CaseFold is deliberate: the message is used again as a table
    -- key below, and an unreadable message is not a missing keyword but a question we cannot ask.
    if KAUtil.IsSecret(msg) then return end
    local message = KAUtil.TrimString(KAUtil.CaseFold(msg))

    if not KART.InviteKeywordsTable[message] then return end

    local canAct = not IsInGroup() or KAUtil.HasGroupPermissions()
    if not canAct then
        KART.MaybeInviteAutoReply(sender, "NOT_LEADER")
        return
    end

    local target
    if event == "CHAT_MSG_BN_WHISPER" then
        local bnetIDAccount = select(11, ...)
        if bnetIDAccount then
            local accountInfo = C_BattleNet.GetAccountInfoByID(bnetIDAccount)
            local ga = accountInfo and accountInfo.gameAccountInfo
            -- InviteUnit needs a character name, not the numeric gameAccountID (passing the ID
            -- silently invites nobody). Resolve the friend's current WoW character from their
            -- Battle.net account info and invite that.
            if ga and ga.characterName and ga.characterName ~= "" then
                target = ga.characterName
                if ga.realmName and ga.realmName ~= "" then
                    target = target .. "-" .. ga.realmName
                end
            end
        end
    else
        target = sender
    end

    if not target then return end

    -- InviteUnit on a full 5-man does not invite: it asks the player to convert
    -- (CONVERT_TO_RAID / "your group is full"). ConvertToRaid() first does not skip that
    -- confirm, and the group is still a party until the server answers. ConfirmInviteUnit
    -- is the skip: it converts and invites in one shot, which is what autoConvertToRaid
    -- already opted into.
    local fullSixth = IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5
        and not KAUtil.IsFullNameInGroup(target)
    local convert = KART_Settings.autoConvertToRaid and UnitIsGroupLeader("player")
        and fullSixth and not InCombatLockdown()
    if convert then
        C_PartyInfo.ConfirmInviteUnit(target)
        return
    end

    if fullSixth and not KART_Settings.autoConvertToRaid then
        KART.MaybeInviteAutoReply(sender, "FULL")
        return
    end

    if InCombatLockdown() then
        KART.MaybeInviteAutoReply(sender, "COMBAT")
        return
    end

    C_PartyInfo.InviteUnit(target)
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
    if KART_Settings.autoModuleEnabled == false then return end
    -- PromoteToAssistant is HasRestrictions (C_PartyInfo). Calling it while InCombatLockdown is
    -- ADDON_ACTION_BLOCKED — the live stack is GROUP_ROSTER_UPDATE → this function via the 1s
    -- throttle. Keyword invites already refuse in combat; Core.lua retries this on
    -- PLAYER_REGEN_ENABLED so someone who joined mid-pull still gets assistant afterwards.
    if InCombatLockdown() then return end
    if not UnitIsGroupLeader("player") or not IsInGroup() then return end -- IsInRaid implies IsInGroup
    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name then
            local shortName = name -- UnitName's first return is already realm-free
            -- Matches either the character's own short name (as always) or its Northern Sky Raid
            -- Tools nickname (see KASC.Identity.GetNickname), so a name in the promote list applies to
            -- every character sharing that nickname, not just one specific alt.
            local matches = shortName and KART.PromoteNamesTable[KAUtil.CaseFold(shortName)]
            -- UnitName answers "" for somebody on our own realm -- that is how the game says "same
            -- realm as you", not "no realm". Reading it as "nothing to qualify" skipped the branch
            -- below entirely, so a realm-qualified entry for one of our OWN players matched nothing
            -- at all — so an entry typed with a realm only ever worked for people from somewhere
            -- else, which is the opposite of what anyone writing one would expect. Same shape as
            -- B15, same silence.
            --
            -- Only for MATCHING. `realm` itself stays as the game reported it, because it is also
            -- what the promote below targets, and a same-realm character is addressed by plain name.
            local matchRealm = (realm ~= "" and realm) or GetRealmName()
            if not matches and matchRealm and matchRealm ~= "" then
                -- Also accept a realm-qualified entry. "Name-Realm" is the format this function
                -- itself hands to PromoteToAssistant, so it is the spelling anyone reading the
                -- addon's own output would reasonably type back in.
                --
                -- Both spellings, because the two sides disagree: UnitName gives a cross-realm unit
                -- its display realm ("Tarren Mill") while the export gives the normalized one
                -- ("TarrenMill"). UpdateCache stores a canonicalized key alongside the raw entry,
                -- so checking the canonical form here closes the gap from the other end too (B15).
                local folded = KAUtil.CaseFold(name)
                matches = KART.PromoteNamesTable[folded .. "-" .. KAUtil.CaseFold(matchRealm)]
                       or KART.PromoteNamesTable[folded .. "-" .. KAUtil.CanonRealm(matchRealm)]
            end
            if not matches then
                local nick = KASC.Identity.GetNickname(unit)
                matches = nick ~= nil and KART.PromoteNamesTable[nick]
            end
            if matches then
                if not KART.UnitAssists(unit) and not KART.UnitLeads(unit) then
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
