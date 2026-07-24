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

-- Reply channel/target for a request handler: whisper straight back to the sender when the request
-- itself arrived as a whisper (a targeted single-player query), otherwise the default broadcast
-- channel. Matches REQ_VERSION's behavior so every request/response pair round-trips on one channel.
local function ReplyTo(ctx)
    if ctx.channel == "WHISPER" then return "WHISPER", ctx.sender end
    return Sync.DefaultChannel(), nil
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

local function HandleVersionMessage(payload, ctx, isAnnounce)
    local ver, lcFlag = payload:match("^([^:]+):?([01]?)$")
    ver = ver or payload

    KART.PlayerVersions = KART.PlayerVersions or {}
    KART.PlayerVersions[ctx.shortName] = ver
    if lcFlag == "1" or lcFlag == "0" then
        KART.PlayerLCEnabled = KART.PlayerLCEnabled or {}
        KART.PlayerLCEnabled[ctx.shortName] = (lcFlag == "1")
    end
    if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
        KART.LC.Council.RefreshCouncilRows()
    end

    if not KART.UpdateWarned and ver ~= KART.Version then
        -- Lenient parse: a 2-part version ("2.9") or a trailing build suffix still yields usable
        -- numbers (missing parts fall to 0 via the tonumber-or-0 below) instead of failing the
        -- match outright and collapsing to 0.0.0, which would suppress the update warning entirely.
        local nMaj, nMin, nPat = ver:match("(%d+)%.?(%d*)%.?(%d*)")
        local oMaj, oMin, oPat = KART.Version:match("(%d+)%.?(%d*)%.?(%d*)")
        nMaj, nMin, nPat = tonumber(nMaj) or 0, tonumber(nMin) or 0, tonumber(nPat) or 0
        oMaj, oMin, oPat = tonumber(oMaj) or 0, tonumber(oMin) or 0, tonumber(oPat) or 0
        if nMaj > oMaj or (nMaj == oMaj and nMin > oMin) or (nMaj == oMaj and nMin == oMin and nPat > oPat) then
            KART.UpdateWarned = true
            print(string.format(KART.L.UPDATE_AVAILABLE, ver, KART.Version))
        end
    end

    if KART.VersionCheckActive and not isAnnounce then
        print(string.format(KART.L.VERSION_CHECK_RES, ctx.shortName, ver))
    end
end

local EXACT_HANDLERS = {
    REQ_OIL = { fn = function(_, ctx)
        local hasMH, _, _, mhID, hasOH, _, _, ohID = GetWeaponEnchantInfo()
        local outMH = (hasMH and mhID) and mhID or 0
        local outOH = (hasOH and ohID) and ohID or 0
        if IsInGroup() then
            Sync.Send("OIL:" .. outMH .. ":" .. outOH, ReplyTo(ctx))
        end
    end },
    REQ_ILVL = { fn = function(_, ctx)
        local _, equipped = GetAverageItemLevel()
        if equipped and IsInGroup() then
            Sync.Send("ILVL:" .. string.format("%.1f", equipped), ReplyTo(ctx))
        end
    end },
    REQ_GEAR = { fn = function(_, ctx)
        if IsInGroup() then
            local e, g = KART.CountMissingGear()
            Sync.Send("GEAR:" .. e .. ":" .. g, ReplyTo(ctx))
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
    LC_STATE_REQ    = { lc = true, fn = function(_, ctx) KART.LC.HandleStateRequest() end },
}

local PREFIX_HANDLERS = {
    OIL = { fn = function(payload, ctx)
        local mhID, ohID = payload:match("^(%d+):(%d+)")
        if mhID and ohID then
            KART.OilCache = KART.OilCache or {}
            KART.OilCache[ctx.shortName] = { mh = tonumber(mhID), oh = tonumber(ohID) }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    ILVL = { fn = function(payload, ctx)
        local ilvl = tonumber(payload)
        if ilvl then
            KART.ILvlCache = KART.ILvlCache or {}
            KART.ILvlCache[ctx.shortName] = ilvl
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    GEAR = { fn = function(payload, ctx)
        local e, g = payload:match("^([^:]+):([^:]+)")
        if e and g then
            KART.GearCache = KART.GearCache or {}
            KART.GearCache[ctx.shortName] = { enchants = e, gems = g }
            if KART.BuffCheckFrame and KART.BuffCheckFrame:IsShown() then KART.UpdateBuffCheckThrottled() end
        end
    end },
    REQ_EQUIP = { lc = true, fn = function(payload, ctx)
        -- A council member's open panel is asking what we've got equipped in the rolled item's
        -- slot (payload = equipLoc token). Reply with our own link so they can show the comparison
        -- for a raider they can't inspect locally. Modeled on REQ_GEAR, but carries a payload so it
        -- lives here in PREFIX_HANDLERS (unlike the payload-less REQ_OIL/REQ_ILVL/REQ_GEAR above).
        if not IsInGroup() then return end
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
            Sync.Send(msg)
        end
    end },
    EQUIP = { lc = true, fn = function(payload, ctx)
        -- Reply to our REQ_EQUIP: equipLoc token, then the sender's equipped link (which itself
        -- contains colons, so it must be the rest of the payload). Cached per short name + slot,
        -- read by Council.GetEquippedForUnit as the fallback for un-inspectable raid members.
        local equipLoc, link = payload:match("^([^:]+):(.+)$")
        if equipLoc and link then
            -- Sender may have sent a compact item string (oversized-link fallback above); rebuild a
            -- full link when the item is cached so the tooltip and ilvl comparison work, mirroring
            -- the history-sync rebuild.
            if not KART.IsRealItemLink(link) and link:match("^item:") then
                link = select(2, C_Item.GetItemInfo(link)) or link
            end
            KART.EquipCache = KART.EquipCache or {}
            KART.EquipCache[ctx.shortName] = KART.EquipCache[ctx.shortName] or {}
            KART.EquipCache[ctx.shortName][equipLoc] = link
            if KART.LC and KART.LC.councilPanel and KART.LC.councilPanel:IsShown() then
                KART.LC.Council.RefreshCouncilRows()
            end
        end
    end },
    VERSION          = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, false) end },
    ANNOUNCE_VERSION = { fn = function(payload, ctx) HandleVersionMessage(payload, ctx, true) end },
    LC_ACTIVE       = { lc = true, fn = function(payload, ctx) KART.LC.HandleActive(payload, SenderKey(ctx)) end },
    LC_START        = { lc = true, fn = function(payload, ctx) KART.LC.HandleStart(payload, SenderKey(ctx)) end },
    LC_MANUAL_START = { lc = true, fn = function(payload, ctx) KART.LC.HandleManualStart(payload, SenderKey(ctx)) end },
    LC_VOTE         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleVote(payload, SenderKey(ctx)) end },
    LC_ROLL         = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleRoll(payload, SenderKey(ctx)) end },
    LC_CVOTE        = { lc = true, fn = function(payload, ctx) KART.LC.Vote.HandleCouncilVote(payload, SenderKey(ctx)) end },
    LC_ONOTE        = { lc = true, fn = function(payload, ctx) KART.LC.OfficerNotes.HandleOfficerNote(payload, SenderKey(ctx)) end },
    LC_RESULT       = { lc = true, fn = function(payload, ctx) KART.LC.Trade.HandleResult(payload, SenderKey(ctx)) end },
    LC_CONFIG       = { lc = true, fn = function(payload, ctx) KART.LC.HandleConfig(payload, SenderKey(ctx)) end },
    LC_HIST_REQ     = { lc = true, fn = function(payload, ctx) if KART.LH then KART.LH.HandleHistoryRequest(payload, ctx.sender) end end },
    LC_HIST_ENTRY   = { lc = true, fn = function(payload, ctx) if KART.LH then KART.LH.HandleHistoryEntry(payload, SenderKey(ctx)) end end },
    LC_SYNC_REQUEST = { lc = true, fn = function(payload, ctx) KART.LC.HandleSyncRequest(payload, ctx.sender, ctx.shortName) end },
    RC_REASON = { fn = function(payload, ctx)
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
                if entry and not (entry.lc and not (KART.LC and KART_Settings.lcModuleEnabled ~= false)) then
                    entry.fn(payload, ctx)
                end
            end
        end
    end
end)
