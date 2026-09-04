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

-- contentW/H are the unpadded pixels; texW/H are the PNG size (power of two).
BT.POOL = {
    { file = "1.png", contentW = 776, contentH = 960, texW = 1024, texH = 1024 },
    { file = "2.png", contentW = 1024, contentH = 1024, texW = 1024, texH = 1024 },
    { file = "3.png", contentW = 825, contentH = 1024, texW = 1024, texH = 1024 },
    { file = "4.png", contentW = 971, contentH = 975, texW = 1024, texH = 1024 },
    { file = "5.png", contentW = 1024, contentH = 1024, texW = 1024, texH = 1024 },
}

local function MediaBreak(file)
    return "Interface\\AddOns\\" .. addonName .. "\\media\\break\\" .. file
end

function BT.PickImage()
    local n = BT.POOL and #BT.POOL or 0
    if n == 0 then return nil end
    return BT.POOL[math.random(1, n)]
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
    local pad = 8
    local imgW, imgH = 0, 0
    if BT.wantPictures and not BT.minimized then
        local entry = BT.currentImage or BT.PickImage()
        BT.currentImage = entry
        if entry and BT.image then
            imgW, imgH = BT.ContainSize(entry.contentW, entry.contentH, MAX_IMAGE_SIDE)
            BT.image:ClearAllPoints()
            BT.image:SetPoint("TOP", f, "TOP", 0, -(barH + pad))
            BT.image:SetSize(imgW, imgH)
            BT.image:SetTexture(MediaBreak(entry.file))
            local u = entry.contentW / entry.texW
            local v = entry.contentH / entry.texH
            BT.image:SetTexCoord(0, u, 0, v)
            BT.image:Show()
        elseif BT.image then
            BT.image:SetTexture(nil)
            BT.image:Hide()
        end
    elseif BT.image then
        BT.image:Hide()
    end
    local width = math.max(FRAME_WIDTH, imgW + pad * 2)
    local height = barH + (imgH > 0 and (imgH + pad * 2) or 0)
    f:SetSize(width, height)
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

    BT.image = f:CreateTexture(nil, "ARTWORK")
    BT.image:Hide()

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
    BT.currentImage = nil
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
    BT.OnStart(seconds, showImages)
end

function BT.SenderMayControl(ctx)
    if not ctx or not ctx.sender then return false end
    if not KAUtil or not KAUtil.IsFullNameInGroup then return false end

    local function unitMayControl(unit)
        return KART.UnitLeads(unit) or KART.UnitAssists(unit)
    end

    if not KAUtil.IsFullNameInGroup(ctx.sender) then
        if not KAUtil.IsSelfFullName or not KAUtil.IsSelfFullName(ctx.sender) then
            return false
        end
        return unitMayControl("player")
    end

    local senderShort = ctx.shortName or ctx.sender:match("^([^%-]+)")
    if not senderShort then return false end

    local senderRealmRaw = ctx.sender:match("-(.+)$")
    local ownRealm = KAUtil.CanonRealm(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName())
    local wantSenderRealm = KAUtil.CanonRealm(senderRealmRaw)
    if wantSenderRealm == "" then wantSenderRealm = ownRealm end

    for unit in KAUtil.EachGroupUnit() do
        local name, realm = UnitName(unit)
        if name and KAUtil.CaseFold(name) == KAUtil.CaseFold(senderShort) then
            local unitRealm = KAUtil.CanonRealm(realm)
            if unitRealm == "" then unitRealm = ownRealm end
            if senderRealmRaw and senderRealmRaw ~= "" and unitRealm ~= wantSenderRealm then
                -- sender names a realm that does not match this unit
            else
                return unitMayControl(unit)
            end
        end
    end
    return false
end

KASC:RegisterMessage("BRK", { payload = true, group = true }, function(payload, ctx)
    if not BT.SenderMayControl(ctx) then return end
    local seconds, img = BT.ParsePayload(payload)
    if seconds == nil then return end
    if seconds == 0 then BT.OnCancel() return end
    BT.OnStart(seconds, img)
end)

local function SettingsStore() return KART_Settings end

if KART.SettingsPanel and KART.UI and KART.UI.CreateCard then
    local card = KART.UI:CreateCard(KART.SettingsPanel)
    local above = (KART.RC and KART.RC.SettingsCard) or KART.AddonVersionCard
    if above then
        card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -20)
    else
        card:SetPoint("TOPLEFT", KART.SettingsPanel, "TOPLEFT", 20, -12)
    end
    card:SetSize(500, 72)
    KART.CbBreakShowImages = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_BreakShowImages",
        label = KART.L.SET_BREAK_IMAGES,
        store = SettingsStore,
        key = "breakShowImages",
        y = -20,
        tooltip = KART.L.DESC_BREAK_IMAGES,
    })
    KART.UI:RegisterLocaleRefresher(function()
        local L = KART.L
        if KART.CbBreakShowImages then
            KART.CbBreakShowImages.text:SetText(L.SET_BREAK_IMAGES)
            KART.CbBreakShowImages.tooltipText = L.DESC_BREAK_IMAGES
        end
    end)
end

function BT.SyncWidgets()
    local settingsMap = {}
    if KART.CbBreakShowImages then settingsMap[KART.CbBreakShowImages] = "breakShowImages" end
    KART.ApplySettingsMap(settingsMap)
end

