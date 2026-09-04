local addonName, KART = ...
local KASC = LibStub("KASC-1.0")
KART.BT = KART.BT or {}
local BT = KART.BT

local MAX_IMAGE_SIDE = 400

function BT.ParsePayload(payload)
    if type(payload) ~= "string" then return nil, 0 end
    local secStr, imgStr = payload:match("^(%d+):(%d+)$")
    if secStr then
        local seconds = tonumber(secStr)
        local img = tonumber(imgStr)
        if img ~= 1 then img = 0 end
        return seconds, img
    end
    secStr = payload:match("^(%d+)$")
    if not secStr then return nil, 0 end
    return tonumber(secStr), 0
end

function BT.FormatStatus(seconds, now)
    seconds = tonumber(seconds) or 0
    now = now or time()
    local minutes = math.floor(seconds / 60)
    return string.format(KART.L.BREAK_STATUS, minutes, date("%H:%M", now + seconds))
end

function BT.ContainSize(contentW, contentH, maxSide)
    maxSide = maxSide or MAX_IMAGE_SIDE
    contentW = tonumber(contentW) or 0
    contentH = tonumber(contentH) or 0
    if contentW <= 0 or contentH <= 0 then return maxSide, maxSide end
    local scale = maxSide / math.max(contentW, contentH)
    if scale > 1 then scale = 1 end
    return math.floor(contentW * scale + 0.5), math.floor(contentH * scale + 0.5)
end

function BT.ShouldRegisterSlash()
    return BigWigsLoader == nil and DBM == nil
end
