local addonName, KART = ...
local KASC = LibStub("KASC-1.0")
local KAUtil = LibStub("KAUtil-1.0")
local KAUI = LibStub("KAUI-1.0")
KART.BT = KART.BT or {}
local BT = KART.BT

local MAX_IMAGE_SIDE = 400

function BT.ParsePayload(payload)
    if type(payload) ~= "string" then return nil, 0 end
    local secStr, imgStr = payload:match("^(%d+):(.+)$")
    if secStr then
        local seconds = tonumber(secStr)
        local img = (imgStr == "1") and 1 or 0
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

local BAR_HEIGHT = 28
local FRAME_WIDTH = 280

local function clearCloseTimer()
    local t = BT.closeAt
    if not t then return end
    if t.Cancel then t:Cancel() end
    t.fn = function() end
    BT.closeAt = nil
end

local function restorePosition(f)
    f:ClearAllPoints()
    local pos = KART_Settings and KART_Settings.breakWindowPos
    if pos and KAUI.IsSavedPosOnScreen(pos.x, pos.y) then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("CENTER")
    end
end

local function savePosition(f)
    if not KART_Settings then return end
    local x, y = f:GetLeft(), f:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    KART_Settings.breakWindowPos = { x = x, y = y }
end

local function applyMinimize()
    if BT.image then
        if BT.minimized then BT.image:Hide() else BT.image:Show() end
    end
    if BT.imageHolder then
        if BT.minimized then BT.imageHolder:Hide() else BT.imageHolder:Show() end
    end
    BT.ApplyLayout()
end

function BT.ApplyLayout()
    local f = BT.frame
    if not f then return end
    local barH = BAR_HEIGHT
    local imgH = 0
    f:SetSize(FRAME_WIDTH, barH + imgH)
end

function BT.EnsureFrame()
    if BT.frame then return BT.frame end
    local f = CreateFrame("Frame", "KART_BreakFrame", UIParent, "BackdropTemplate")
    BT.frame = f
    if KART.UI and KART.UI.RegisterStrataFrame then
        KART.UI:RegisterStrataFrame(f, true)
    else
        f:SetFrameStrata("DIALOG")
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetToplevel(true)
    if KART.UI and KART.UI.SetPixelBackdrop then
        KART.UI:SetPixelBackdrop(f, {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.06, 0.07, 0.08, 0.96)
        f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        if KART.UI.ApplyPopupArtwork then
            KART.UI:ApplyPopupArtwork(f)
        end
    else
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.06, 0.07, 0.08, 0.96)
        f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    end

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_HEIGHT)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local function onDragStart() f:StartMoving() end
    local function onDragStop()
        f:StopMovingOrSizing()
        savePosition(f)
    end
    f:SetScript("OnDragStart", onDragStart)
    f:SetScript("OnDragStop", onDragStop)
    bar:SetScript("OnDragStart", onDragStart)
    bar:SetScript("OnDragStop", onDragStop)

    local closeBtn = CreateFrame("Button", nil, bar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeBtn:SetScript("OnClick", function() BT.OnCancel() end)

    local minBtn = CreateFrame("Button", nil, bar)
    minBtn:SetSize(20, 20)
    minBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    local minText = minBtn:CreateFontString(nil, "OVERLAY")
    minText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    minText:SetPoint("CENTER")
    minText:SetText("_")
    minBtn:SetScript("OnClick", function()
        BT.minimized = not BT.minimized
        applyMinimize()
    end)

    BT.statusText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    BT.statusText:SetPoint("LEFT", bar, "LEFT", 8, 0)
    BT.statusText:SetPoint("RIGHT", minBtn, "LEFT", -6, 0)
    BT.statusText:SetJustifyH("LEFT")

    BT.imageHolder = CreateFrame("Frame", nil, f)
    BT.imageHolder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    BT.imageHolder:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
    BT.imageHolder:SetHeight(0)

    BT.ApplyLayout()
    f:Hide()
    return f
end

function BT.OnStart(seconds, showImages)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return end
    if seconds == 0 then return BT.OnCancel() end
    if seconds > 0 and seconds < 60 then return end
    if seconds > 3600 then return end
    BT.EnsureFrame()
    BT.wantPictures = showImages == true or showImages == 1
    BT.minimized = false
    applyMinimize()
    BT.ApplyLayout()
    restorePosition(BT.frame)
    BT.statusText:SetText(BT.FormatStatus(seconds, time()))
    BT.frame:Show()
    clearCloseTimer()
    BT.closeAt = C_Timer.NewTimer(seconds, function() BT.OnCancel() end)
end

function BT.OnCancel()
    clearCloseTimer()
    BT.wantPictures = false
    if BT.frame then BT.frame:Hide() end
end

function BT.SendBreak(seconds, showImages)
    local flag = (showImages == true or showImages == 1) and 1 or 0
    if IsInGroup() then
        KASC:Send("BRK:" .. tostring(seconds) .. ":" .. tostring(flag))
    end
end

function BT.SenderMayControl(ctx)
    if not ctx then return false end
    local leads, assists = false, false
    local found = false
    if KAUtil and KAUtil.EachGroupUnit then
        for unit in KAUtil.EachGroupUnit() do
            local name, realm = UnitName(unit)
            local full = realm and (name .. "-" .. realm) or name
            if full == ctx.sender or name == ctx.shortName then
                leads = KART.UnitLeads(unit)
                assists = KART.UnitAssists(unit)
                found = true
                break
            end
        end
    end
    if not found then
        local playerName, playerRealm = UnitName("player")
        if not playerName then return false end
        local playerFull = playerRealm and (playerName .. "-" .. playerRealm) or playerName
        if ctx.shortName ~= playerName and ctx.sender ~= playerFull then
            return false
        end
        leads = KART.UnitLeads("player")
        assists = KART.UnitAssists("player")
    end
    return leads or assists
end

KASC:RegisterMessage("BRK", { payload = true, group = true }, function(payload, ctx)
    if not BT.SenderMayControl(ctx) then return end
    local seconds, img = BT.ParsePayload(payload)
    if seconds == nil then return end
    if seconds == 0 then BT.OnCancel() return end
    BT.OnStart(seconds, img)
end)

