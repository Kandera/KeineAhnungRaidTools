local addonName, KART = ...

-- KARTSync: the addon-message networking layer. Owns the "KART" addon-message prefix, the
-- outbound Send() wrapper (prefix + default raid/party channel), and the inbound CHAT_MSG_ADDON
-- dispatch table every other module registers its handlers into. Previously this all lived
-- inline in Core.lua's OnEvent, with 20 call sites elsewhere each re-deriving the raid/party
-- channel and calling C_ChatInfo.SendAddonMessage directly.
KART.Sync = KART.Sync or {}
local Sync = KART.Sync

local PREFIX = "KART"
Sync.PREFIX = PREFIX

-- Raid channel while in a raid, otherwise party. The default channel for anything that doesn't
-- need an explicit WHISPER/GUILD/reply-to-sender target.
function Sync.DefaultChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

function Sync.Send(msg, channel, target)
    C_ChatInfo.SendAddonMessage(PREFIX, msg, channel or Sync.DefaultChannel(), target)
end

-- Whether an incoming request may be answered at all. CHAT_MSG_ADDON also delivers WHISPER and
-- GUILD, and the "KART" prefix is public, so any player can send a request — answering one from
-- outside the group discloses our gear/enchant/ilvl state to a stranger. Every data-reply handler
-- below gates on this; replies always go to the group channel, never back to the whisperer.
local function SenderInGroup(ctx)
    return KART.IsFullNameInGroup(ctx.sender)
end

-- CHAT_MSG_ADDON dispatch. A message is either a fixed token (EXACT_HANDLERS) or
-- "PREFIX:payload" (PREFIX_HANDLERS, keyed by the part before the FIRST colon — payloads may
-- contain further colons; each handler parses its own format). Entries with lc = true only
-- run while the Loot Council module is enabled; LC_SYNC_ACCEPT/DECLINE deliberately skip that
-- gate (a decline must still print even if the receiver just disabled the module).
-- ctx = { sender = full sender name, shortName, channel }.
local function SenderKey(ctx)
    return (KART.Identity.ResolvePlayer(ctx.sender))
end

-- Per-equipLoc cooldown for answering REQ_EQUIP. Council.RequestEquipForRoll dedups per REQUESTING
-- client, so a 5-member council sends five identical requests for the same slot and we used to
-- broadcast five identical replies to the whole raid — councilSize * raidSize messages per item,
-- each one waking every open council panel. The answer is a raid-wide broadcast, so the first reply
-- already served every requester; anything arriving inside this window is a duplicate. Well below a
-- vote window, and our equipped item can't meaningfully change mid-loot anyway.
local EQUIP_ANSWER_COOLDOWN = 5
local lastEquipAnswer = {} -- [equipLoc] = GetTime() of our last reply; only written on an actual send,
                           -- so a bogus token from an unknown sender can't grow this table

-- Whether s is a well-formed missing-slot list as KART.CountMissingGear produces them: "0", or one
-- or more inventory slot numbers separated by single commas. Used to reject a malformed GEAR reply
-- before it reaches the cache (see the GEAR handler below).
-- Spelled out rather than one anchored pattern: Lua patterns can't quantify a group, so
-- "^%d+(,%d+)*$" silently matches nothing at all.
local function IsSlotList(s)
    if s:find("[^%d,]") then return false end -- digits and separators only
    if s:find(",,") or s:find("^,") or s:find(",$") then return false end -- no empty entries
    return s ~= ""
end

local function HandleVersionMessage(payload, ctx, isAnnounce)
    local ver, lcFlag = payload:match("^([^:]+):?([01]?)$")
    ver = ver or payload
    -- Version strings are printed to chat and rendered in the council panel. This handler is
    -- deliberately ungated (ANNOUNCE_VERSION travels over GUILD, so the sender need not be grouped),
    -- which means the string is untrusted — double the pipes so it can't carry colour codes or
    -- hyperlinks into either.
    ver = ver:gsub("|", "||")

    KART.PlayerVersions = KART.PlayerVersions or {}
    KART.PlayerVersions[ctx.shortName] = ver
    if lcFlag == "1" or lcFlag == "0" then
        KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
        KART.PlayerLCEnabled[ctx.shortName] = (lcFlag == "1")
    end
    -- Throttled: a raid join answers one REQ_VERSION with one reply per raider, all at once.
    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRowsThrottled()
    end

    if not KART.UpdateWarned and ver ~= KART.Version then
        -- Lenient parse: a 2-part version ("2.9") or a trailing build suffix still yields usable
        -- numbers (missing parts fall to 0 via the tonumber-or-0 below) instead of failing the
        -- match outright and collapsing to 0.0.0, which would suppress the update warning entirely.
        local nMaj, nMin, nPat = ver:match("(%d+)%.?(%d*)%.?(%d*)")
        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.?(%d*)%.?(%d*)")
        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0
        -- Sanity clamp before trusting the number. ANNOUNCE_VERSION also travels over GUILD and no
        -- handler here authenticates its sender, so anyone can claim "VERSION:99" — and since
        -- UpdateWarned latches after the first print, one bogus claim would suppress the real update
        -- warning for the whole session. A genuine release never jumps more than a major ahead.
        local plausible = nMaj <= oMaj + 1
        if plausible and (nMaj > oMaj or (nMaj == oMaj and nMin > oMin) or (nMaj == oMaj and nMin == oMin and nPat > oPat)) then
            KART.UpdateWarned = true
            print(string.format(KART.L.UPDATE_AVAILABLE, ver, KART.Version))
        end
    end

    if KART.VersionCheckActive and not isAnnounce then
        print(string.format(KART.L.VERSION_CHECK_RES, ctx.shortName, ver))
    end
end

local EXACT_HANDLERS = {
    REQ_OIL = { group = true, fn = function(_, ctx)
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        local outMH = (hasMH and mhID) and mhID or 0
        local outOH = (hasOH and ohID) and ohID or 0
        if IsInGroup() then
            Sync.Send("OIL:" .. outMH .. ":" .. outOH)
        end
    end },
    REQ_ILVL = { group = true, fn = function(_, ctx)
        local _, equipped = GetAverageItemLevel()
        if equipped and IsInGroup() then
            Sync.Send("ILVL:" .. string.format("%.1f", equipped))
        end
    end },
    REQ_GEAR = { group = true, fn = function(_, ctx)
        if IsInGroup() then
            local e, g = KART.CountMissingGear()
            Sync.Send("GEAR:" .. e .. ":" .. g)
        end
    end },
    REQ_VERSION = { fn = function(_, ctx)
        local lcFlag = (KART_Settings.lcModuleEnabled ~= false) and "1" or "0"
        if ctx.channel == "WHISPER" then
            Sync.Send("VERSION:" .. KART.Version .. ":" .. lcFlag, "WHISPER", ctx.sender)
        else
            Sync.Send("VERSION:" .. KART.Version .. ":" .. lcFlag, ctx.channel)
        end
    end },
    LC_SYNC_ACCEPT  = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncAccept(ctx.shortName) end end },
    LC_SYNC_DECLINE = { fn = function(_, ctx) if KART.LC then KART.LC.HandleSyncDecline(ctx.shortName) end end },
    LC_STATE_REQ    = { lc = true, group = true, fn = function(_, ctx) KART.LC.HandleStateRequest(ctx.sender) end },
}

local PREFIX_HANDLERS = {
    OIL = { group = true, fn = function(payload, ctx)
        local mhID, ohID = payload:match("^(%d+):(%d+)")
        if mhID and ohID then
            KART.OilCache = KART.OilCache or {}
            KART.OilCache[ctx.shortName] = { mh = tonumber(mhID), oh = tonumber(ohID) }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    ILVL = { group = true, fn = function(payload, ctx)
        local ilvl = tonumber(payload)
        if ilvl then
            KART.ILvlCache = KART.ILvlCache or {}
            KART.ILvlCache[ctx.shortName] = ilvl
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    GEAR = { group = true, fn = function(payload, ctx)
        local e, g = payload:match("^([^:]+):([^:]+)")
        -- Validate the shape before caching. Both fields are slot lists — "0" for "nothing missing",
        -- otherwise comma-separated inventory slot NUMBERS (see KART.CountMissingGear) — but the
        -- captures above accept any colon-free text. BuffChecker renders an unrecognized slot through
        -- string.format(BC_SLOT_FALLBACK, s), whose "%d" throws a Lua error on non-numeric input, so a
        -- broken or hostile client could make the Advanced-view tooltip error on every hover. Rejecting
        -- the whole message is also what keeps a bogus "-5 missing" count out of the cache.
        if e and g and IsSlotList(e) and IsSlotList(g) then
            KART.GearCache = KART.GearCache or {}
            KART.GearCache[ctx.shortName] = { enchants = e, gems = g }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    REQ_EQUIP = { lc = true, group = true, fn = function(payload, ctx)
        -- A council member's open panel is asking what we've got equipped in the rolled item's
        -- slot (payload = equipLoc token). Reply with our own link so they can show the comparison
        -- for a raider they can't inspect locally. Modeled on REQ_GEAR, but carries a payload so it
        -- lives here in PREFIX_HANDLERS (unlike the payload-less REQ_OIL/REQ_ILVL/REQ_GEAR above).
        if not IsInGroup() then return end
        local now = GetTime()
        if now - (lastEquipAnswer[payload] or -EQUIP_ANSWER_COOLDOWN) < EQUIP_ANSWER_COOLDOWN then return end
        local link = KART.LC and KART.LC.Council and KART.LC.Council.GetOwnEquippedLink(payload)
        if link then
            local msg = "EQUIP:" .. payload .. ":" .. link
            -- A max-crafted/heavily-bonused link can exceed the 255-byte addon-message cap and get
            -- its trailing link truncated into garbage; fall back to the compact item string (the
            -- EQUIP receiver rebuilds it into a full link), same guard as the history sync.
            if #msg > 255 then
                local itemStr = KART.GetItemString(link)
                if itemStr then msg = "EQUIP:" .. payload .. ":" .. itemStr end
            end
            -- Still over budget (or no item string to fall back to): drop the reply entirely rather
            -- than let SendAddonMessage truncate the link into something the receiver would cache as
            -- garbage. Missing data renders as "no comparison"; corrupt data renders as a wrong one.
            if #msg > 255 then return end
            lastEquipAnswer[payload] = now
            Sync.Send(msg)
        end
    end },
    EQUIP = { lc = true, group = true, fn = function(payload, ctx)
        -- Reply to our REQ_EQUIP: equipLoc token, then the sender's equipped link (which itself
        -- contains colons, so it must be the rest of the payload). Cached per short name + slot,
        -- read by Council.GetEquippedForUnit as the fallback for un-inspectable raid members.
        local equipLoc, link = payload:match("^([^:]+):(.+)$")
        if equipLoc and link then
            -- Sender may have sent a compact item string (oversized-link fallback above); rebuild a
            -- full link when the item is cached so the tooltip and ilvl comparison work, mirroring
            -- the history-sync rebuild.
            local itemStr = (not KART.IsRealItemLink(link)) and link:match("^item:%d+") and link or nil
            if itemStr then
                link = select(2, C_Item.GetItemInfo(itemStr)) or link
            end
            KART.EquipCache = KART.EquipCache or {}
            KART.EquipCache[ctx.shortName] = KART.EquipCache[ctx.shortName] or {}
            local shortName = ctx.shortName
            KART.EquipCache[shortName][equipLoc] = link
            -- Item not cached yet: nothing re-asks for it (Council.RequestEquipForRoll dedups per
            -- roll), so the bare string would stay in the cache all session and the Equipped column
            -- would keep showing a placeholder icon. Upgrade it in place once the item loads.
            if itemStr and not KART.IsRealItemLink(link) then
                local itemID = tonumber(itemStr:match("^item:(%d+)"))
                if itemID then
                    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                        local full = select(2, C_Item.GetItemInfo(itemStr))
                        if not full then return end
                        local slotCache = KART.EquipCache and KART.EquipCache[shortName]
                        -- Only replace if it's still the same bare string (a newer reply may have
                        -- landed for this slot in the meantime).
                        if slotCache and slotCache[equipLoc] == itemStr then
                            slotCache[equipLoc] = full
                            if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                                KART.LC.Council.RefreshCouncilRowsThrottled()
                            end
                        end
                    end)
                end
            end
            -- Throttled: one item can draw councilSize * raidSize of these (see EQUIP_ANSWER_COOLDOWN
            -- and Council.RefreshCouncilRowsThrottled), and they all land within the same second.
            if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                KART.LC.Council.RefreshCouncilRowsThrottled()
            end
        end
    end },
    VERSION          = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, false) end },
    ANNOUNCE_VERSION = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, true) end },
    -- group = true on every LC message that carries authority or writes tracked state. The sender's
    -- resolved key alone is NOT proof of membership: Identity resolution is short-name based (see
    -- Identity.lua), so an out-of-group player sharing a short name with a council member would
    -- otherwise resolve onto their GUID and pass IsSenderCouncil/IsSenderGroupLeader. The three
    -- LC_SYNC_* messages are deliberately left ungated — that feature is an explicit whisper to
    -- someone outside the group, and the receiver confirms it via popup before anything is applied.
    LC_ACTIVE       = { lc = true, group = true, fn = function(payload, ctx) KART.LC.HandleActive(payload, SenderKey(ctx)) end },
    LC_START        = { lc = true, group = true, fn = function(payload, ctx) KART.LC.HandleStart(payload, SenderKey(ctx)) end },
    LC_MANUAL_START = { lc = true, group = true, fn = function(payload, ctx) KART.LC.HandleManualStart(payload, SenderKey(ctx)) end },
    LC_VOTE         = { lc = true, group = true, fn = function(payload, ctx) KART.LC.Vote.HandleVote(payload, SenderKey(ctx)) end },
    LC_ROLL         = { lc = true, group = true, fn = function(payload, ctx) KART.LC.Vote.HandleRoll(payload, SenderKey(ctx)) end },
    LC_CVOTE        = { lc = true, group = true, fn = function(payload, ctx) KART.LC.Vote.HandleCouncilVote(payload, SenderKey(ctx)) end },
    LC_ONOTE        = { lc = true, group = true, fn = function(payload, ctx) KART.LC.OfficerNotes.HandleOfficerNote(payload, SenderKey(ctx)) end },
    LC_RESULT       = { lc = true, group = true, fn = function(payload, ctx) KART.LC.Trade.HandleResult(payload, SenderKey(ctx)) end },
    LC_CONFIG       = { lc = true, group = true, fn = function(payload, ctx) KART.LC.HandleConfig(payload, SenderKey(ctx)) end },
    LC_HIST_REQ     = { lc = true, group = true, fn = function(payload, ctx) if KART.LH then KART.LH.HandleHistoryRequest(payload, ctx.sender) end end },
    LC_HIST_ENTRY   = { lc = true, group = true, fn = function(payload, ctx) if KART.LH then KART.LH.HandleHistoryEntry(payload, SenderKey(ctx)) end end },
    LC_SYNC_REQUEST = { lc = true, fn = function(payload, ctx) KART.LC.HandleSyncRequest(payload, ctx.sender, ctx.shortName) end },
    RC_REASON = { group = true, fn = function(payload, ctx)
        -- Free text from another client goes straight into a chat print and a tooltip, so strip the
        -- UI escape sequences WoW would otherwise render: |c/|r recoloring and |H...|h hyperlinks
        -- would let a raider inject fake colored text and clickable links into every officer's chat.
        if payload == "" then return end -- "" is truthy in Lua: an empty reason would still show the
                                         -- icon, with an empty tooltip behind it
        payload = payload:gsub("|", "||")
        KART.ReadyCheckReasons = KART.ReadyCheckReasons or {}
        KART.ReadyCheckReasons[ctx.shortName] = payload
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            print(string.format(KART.L.RC_REASON_RECEIVED, ctx.shortName, payload))
        end
        if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
    end },
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif event == "CHAT_MSG_ADDON" and arg1 == PREFIX then
        local msg = arg2
        local channel = select(1, ...)
        local sender = select(2, ...)
        if sender then
            local shortName = sender:match("([^%-]+)")
            if shortName then
                local ctx = { sender = sender, shortName = shortName, channel = channel }
                local prefix, payload = msg:match("^([^:]+):(.*)$")
                local entry = (prefix and PREFIX_HANDLERS[prefix]) or EXACT_HANDLERS[msg]
                if entry and not (entry.lc and not (KART.LC and KART_Settings.lcModuleEnabled ~= false))
                   and not (entry.group and not SenderInGroup(ctx)) then
                    entry.fn(payload, ctx)
                end
            end
        end
    end
end)
