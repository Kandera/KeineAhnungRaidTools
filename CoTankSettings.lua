-- Co-Tank settings tab and Look/Text/Auras flyout. Same module as CoTank.lua (KART.CT).
local addonName, KART = ...
KART.CT = KART.CT or {}
local CT = KART.CT
local L = KART.L

local function SettingsStore() return KART_Settings end

local function CtStore() KART_Settings.ct = KART_Settings.ct or {}; return KART_Settings.ct end
local function CtDebuffs() local ct = CtStore(); ct.debuffs = ct.debuffs or {}; return ct.debuffs end
local function CtBuffs() local ct = CtStore(); ct.buffs = ct.buffs or {}; return ct.buffs end
local function CtNameStyle() local ct = CtStore(); ct.nameStyle = ct.nameStyle or {}; return ct.nameStyle end
local function CtHealthStyle() local ct = CtStore(); ct.healthStyle = ct.healthStyle or {}; return ct.healthStyle end
local function CtTargetBorder() local ct = CtStore(); ct.targetBorder = ct.targetBorder or {}; return ct.targetBorder end

local function CtRefresh()
    if CT.Refresh then CT.Refresh() end
end
local function CtEnable()
    if CT.Enable then CT.Enable() end
    if KART.CurrentTab == 6 and KART.MainFrame and KART.MainFrame:IsShown()
        and CT.OnSettingsTab then
        CT.OnSettingsTab(true)
    elseif CT.UpdateFlyoutVisibility then
        CT.UpdateFlyoutVisibility()
    end
    if KART.RefreshModuleChips then KART.RefreshModuleChips() end
end
local function CtLayoutChanged()
    if CT.ApplyLayout then CT.ApplyLayout() end
    CtRefresh()
    if CT.RefreshGradientSwatches then CT.RefreshGradientSwatches() end
end

local function CtPickColor(tbl, after)
    if not tbl then return end
    local store = {
        r = math.floor(((tbl.r or 1) * 100) + 0.5),
        g = math.floor(((tbl.g or 1) * 100) + 0.5),
        b = math.floor(((tbl.b or 1) * 100) + 0.5),
    }
    KART.UI:OpenColorPicker({
        store = store, rKey = "r", gKey = "g", bKey = "b",
        onApply = function()
            tbl.r = store.r / 100
            tbl.g = store.g / 100
            tbl.b = store.b / 100
            if after then after() end
        end,
    })
end


local ctPreviewCard = KART.UI:CreateCard(KART.CoTankPanel)
ctPreviewCard:SetPoint("TOPLEFT", KART.CoTankPanel, "TOPLEFT", 20, -12)
ctPreviewCard:SetSize(500, 240)
local ctPreviewTitle = ctPreviewCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctPreviewTitle:SetPoint("TOPLEFT", ctPreviewCard, "TOPLEFT", 16, -12)
ctPreviewTitle:SetText(L.LABEL_CT_PREVIEW)
KART.UI:RegisterLabel(ctPreviewTitle)
KART.CtPreviewSlot = CreateFrame("Frame", nil, ctPreviewCard)
KART.CtPreviewSlot:SetPoint("TOPLEFT", ctPreviewCard, "TOPLEFT", 16, -36)
KART.CtPreviewSlot:SetPoint("BOTTOMRIGHT", ctPreviewCard, "BOTTOMRIGHT", -16, 44)
if KART.CtPreviewSlot.SetClipsChildren then
    KART.CtPreviewSlot:SetClipsChildren(false)
end
KART.CtAuraEngineNote = ctPreviewCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
KART.CtAuraEngineNote:SetPoint("BOTTOMLEFT", ctPreviewCard, "BOTTOMLEFT", 16, 10)
KART.CtAuraEngineNote:SetPoint("BOTTOMRIGHT", ctPreviewCard, "BOTTOMRIGHT", -16, 10)
KART.CtAuraEngineNote:SetJustifyH("LEFT")
KART.CtAuraEngineNote:SetText(L.SET_CT_AURA_ENGINE)
KART.UI:RegisterLabel(KART.CtAuraEngineNote)

local ctModCard = KART.UI:CreateCard(KART.CoTankPanel)
ctModCard:SetPoint("TOPLEFT", ctPreviewCard, "BOTTOMLEFT", 0, -20)
ctModCard:SetSize(500, 110)

KART.CbCtModuleEnabled = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtModuleEnabled", label = L.SET_CT_MODULE_ENABLED,
    store = SettingsStore, key = "ctModuleEnabled", y = -20,
    tooltip = L.DESC_CT_MODULE_ENABLED,
    onChanged = CtEnable,
})
KART.CbCtModuleEnabled.text:SetWidth(190)
KART.CbCtModuleEnabled.text:SetJustifyH("LEFT")

KART.CbCtTestMode = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtTestMode", label = L.SET_CT_TESTMODE,
    store = CtStore, key = "testMode", y = -20,
    tooltip = L.DESC_CT_TESTMODE,
    onChanged = CtRefresh,
})
KART.CbCtTestMode:ClearAllPoints()
KART.CbCtTestMode:SetPoint("TOPLEFT", ctModCard, "TOPLEFT", 260, -20)
KART.CbCtTestMode.text:SetWidth(190)
KART.CbCtTestMode.text:SetJustifyH("LEFT")

KART.CbCtLock = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtLock", label = L.SET_CT_LOCK,
    store = CtStore, key = "locked", y = -50,
    tooltip = L.DESC_CT_LOCK,
    onChanged = CtRefresh,
})
KART.CbCtLock.text:SetWidth(190)
KART.CbCtLock.text:SetJustifyH("LEFT")

KART.CbCtOnlyGroup = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyGroup", label = L.SET_CT_ONLY_GROUP,
    store = CtStore, key = "onlyInGroup", y = -50,
    tooltip = L.DESC_CT_ONLY_GROUP,
    onChanged = CtRefresh,
})
KART.CbCtOnlyGroup:ClearAllPoints()
KART.CbCtOnlyGroup:SetPoint("TOPLEFT", ctModCard, "TOPLEFT", 260, -50)
KART.CbCtOnlyGroup.text:SetWidth(190)
KART.CbCtOnlyGroup.text:SetJustifyH("LEFT")

KART.CbCtOnlyInstance = KART.UI:CreateSettingsCheckbox(ctModCard, {
    name = "KART_CtOnlyInstance", label = L.SET_CT_ONLY_INSTANCE,
    store = CtStore, key = "onlyInInstance", y = -80,
    tooltip = L.DESC_CT_ONLY_INSTANCE,
    onChanged = CtRefresh,
})
KART.CbCtOnlyInstance.text:SetWidth(220)
KART.CbCtOnlyInstance.text:SetJustifyH("LEFT")

local ctRowCard = KART.UI:CreateCard(KART.CoTankPanel)
ctRowCard:SetPoint("TOPLEFT", ctModCard, "BOTTOMLEFT", 0, -20)
ctRowCard:SetSize(500, 120)

KART.SldCtWidth = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtWidthSlider", label = L.SET_CT_WIDTH,
    min = 100, max = 400, store = CtStore, key = "width", y = -20,
    onChanged = CtLayoutChanged,
})
KART.SldCtHeight = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtHeightSlider", label = L.SET_CT_HEIGHT,
    min = 20, max = 80, store = CtStore, key = "height", y = -20,
    onChanged = CtLayoutChanged,
})
KART.SldCtHeight:ClearAllPoints()
KART.SldCtHeight:SetPoint("TOPLEFT", ctRowCard, "TOPLEFT", 260, -36)
KART.SldCtScale = KART.UI:CreateSettingsSlider(ctRowCard, {
    name = "KART_CtScaleSlider", label = L.SET_CT_SCALE,
    min = 50, max = 200, store = CtStore, key = "scale", y = -70,
    onChanged = function()
        CtStore().scale = KART.SldCtScale:GetValue() / 100
        CtLayoutChanged()
    end,
})

local CT_HEALTH_COLOR_L = {
    class = function() return L.CT_HEALTH_COLOR_CLASS end,
    custom = function() return L.CT_HEALTH_COLOR_CUSTOM end,
    health = function() return L.CT_HEALTH_COLOR_HEALTH end,
}
local CT_HEALTH_TEXT_L = {
    percent = function() return L.CT_HEALTH_TEXT_PERCENT end,
    current = function() return L.CT_HEALTH_TEXT_CURRENT end,
    both = function() return L.CT_HEALTH_TEXT_BOTH end,
    deficit = function() return L.CT_HEALTH_TEXT_DEFICIT end,
}
local CT_ANCHOR_L = {
    TOPLEFT = function() return L.CT_ANCHOR_TOPLEFT end,
    TOPRIGHT = function() return L.CT_ANCHOR_TOPRIGHT end,
    BOTTOMLEFT = function() return L.CT_ANCHOR_BOTTOMLEFT end,
    BOTTOMRIGHT = function() return L.CT_ANCHOR_BOTTOMRIGHT end,
}
local CT_GROWTH_L = {
    right = function() return L.CT_GROWTH_RIGHT end,
    left = function() return L.CT_GROWTH_LEFT end,
    up = function() return L.CT_GROWTH_UP end,
    down = function() return L.CT_GROWTH_DOWN end,
}
local CT_ANCHOR_OPTS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local CT_GROWTH_OPTS = { "right", "left", "up", "down" }

local function RefreshCtHealthColorBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthColor or "class"
    local labelFn = CT_HEALTH_COLOR_L[mode]
    KART.BtnCtHealthColor.text:SetText(L.SET_CT_HEALTH_COLOR .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtHealthTextBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthText or "both"
    local labelFn = CT_HEALTH_TEXT_L[mode]
    KART.BtnCtHealthText.text:SetText(L.SET_CT_HEALTH_TEXT .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtStripEnumBtn(btn, title, storeFn, key, labelMap, default)
    if not KART_Settings then return end
    local mode = storeFn()[key] or default
    local labelFn = labelMap[mode]
    btn.text:SetText(title .. ": " .. (labelFn and labelFn() or mode))
end
local function RefreshCtDebuffAnchorBtn()
    RefreshCtStripEnumBtn(KART.BtnCtDebuffAnchor, L.SET_CT_AURA_ANCHOR, CtDebuffs, "anchor", CT_ANCHOR_L, "TOPLEFT")
end
local function RefreshCtDebuffGrowthBtn()
    RefreshCtStripEnumBtn(KART.BtnCtDebuffGrowth, L.SET_CT_AURA_GROWTH, CtDebuffs, "growth", CT_GROWTH_L, "right")
end
local function RefreshCtBuffAnchorBtn()
    RefreshCtStripEnumBtn(KART.BtnCtBuffAnchor, L.SET_CT_AURA_ANCHOR, CtBuffs, "anchor", CT_ANCHOR_L, "BOTTOMRIGHT")
end
local function RefreshCtBuffGrowthBtn()
    RefreshCtStripEnumBtn(KART.BtnCtBuffGrowth, L.SET_CT_AURA_GROWTH, CtBuffs, "growth", CT_GROWTH_L, "left")
end

-- Co-Tank settings flyout (Look / Text / Auras), parented to UIParent beside the main window.
local ctFlyout = CreateFrame("Frame", "KART_CtFlyout", UIParent, "BackdropTemplate")
ctFlyout:SetSize(580, 700)
KART.UI:ApplyPopupArtwork(ctFlyout)
KART.UI:ApplyPopupChrome(ctFlyout, { title = L.TAB_COTANK })
KART.UI:RegisterStrataFrame(ctFlyout)
ctFlyout:SetClampedToScreen(true)
ctFlyout:SetMovable(true)
ctFlyout:EnableMouse(true)
ctFlyout:RegisterForDrag("LeftButton")
ctFlyout:SetScript("OnDragStart", function(self) self:StartMoving() end)
ctFlyout:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.userPlaced = true
end)
ctFlyout:Hide()
KART.CtFlyout = ctFlyout

function CT.UpdateFlyoutAnchor()
    if not KART.CtFlyout or not KART.MainFrame then return end
    if KART.CtFlyout.userPlaced then return end
    KART.CtFlyout:ClearAllPoints()
    KART.CtFlyout:SetPoint("TOPLEFT", KART.MainFrame, "TOPRIGHT", 8, -64)
end

function CT.UpdateFlyoutVisibility()
    if not KART.CtFlyout then return end
    local show = KART.CurrentTab == 6
        and KART.MainFrame and KART.MainFrame:IsShown()
        and KART_Settings and KART_Settings.ctModuleEnabled
    if show then
        CT.UpdateFlyoutAnchor()
        KART.CtFlyout:Show()
    else
        KART.CtFlyout:Hide()
    end
end

local ctFlyTabBar = CreateFrame("Frame", nil, ctFlyout)
ctFlyTabBar:SetPoint("TOPLEFT", ctFlyout, "TOPLEFT", 12, -36)
ctFlyTabBar:SetPoint("TOPRIGHT", ctFlyout, "TOPRIGHT", -12, -36)
ctFlyTabBar:SetHeight(28)
ctFlyTabBar:EnableMouse(true)
ctFlyTabBar:RegisterForDrag("LeftButton")
ctFlyTabBar:SetScript("OnDragStart", function() ctFlyout:StartMoving() end)
ctFlyTabBar:SetScript("OnDragStop", function()
    ctFlyout:StopMovingOrSizing()
    ctFlyout.userPlaced = true
end)

local ctFlyScroll = CreateFrame("ScrollFrame", "KART_CtFlyoutScroll", ctFlyout, "UIPanelScrollFrameTemplate")
ctFlyScroll:SetPoint("TOPLEFT", ctFlyout, "TOPLEFT", 12, -68)
ctFlyScroll:SetPoint("BOTTOMRIGHT", ctFlyout, "BOTTOMRIGHT", -28, 12)
local ctFlyChild = CreateFrame("Frame", nil, ctFlyScroll)
ctFlyScroll:SetScrollChild(ctFlyChild)
local ctFlyThumb = KART.UI:StripScrollbarTextures(ctFlyScroll)
if ctFlyThumb then ctFlyThumb:SetSize(8, 30) end
KART.UI:RegisterAccentTexture(ctFlyThumb, 0.6)
local ctFlyBar = _G["KART_CtFlyoutScrollScrollBar"]
if ctFlyBar then
    ctFlyBar:ClearAllPoints()
    ctFlyBar:SetPoint("TOPLEFT", ctFlyScroll, "TOPRIGHT", 6, -2)
    ctFlyBar:SetPoint("BOTTOMLEFT", ctFlyScroll, "BOTTOMRIGHT", 6, 2)
end
ctFlyScroll.scrollBarHideable = true

local ctFlyLook = CreateFrame("Frame", nil, ctFlyChild)
local ctFlyText = CreateFrame("Frame", nil, ctFlyChild)
local ctFlyAuras = CreateFrame("Frame", nil, ctFlyChild)
ctFlyLook:SetAllPoints()
ctFlyText:SetAllPoints()
ctFlyAuras:SetAllPoints()
ctFlyText:Hide()
ctFlyAuras:Hide()
KART.CtFlyoutPanels = { ctFlyLook, ctFlyText, ctFlyAuras }

local CT_FLYOUT_HEIGHTS = { 860, 490, 980 }
local function UpdateCtFlyoutScrollRange(tabIndex)
    local h = CT_FLYOUT_HEIGHTS[tabIndex] or 750
    ctFlyChild:SetSize(516, math.max(h, ctFlyScroll:GetHeight()))
    local maxScroll = math.max(0, ctFlyChild:GetHeight() - ctFlyScroll:GetHeight())
    if ctFlyScroll:GetVerticalScroll() > maxScroll then
        ctFlyScroll:SetVerticalScroll(maxScroll)
    end
end

function KART.ShowCtFlyoutTab(tabIndex)
    for i, panel in ipairs(KART.CtFlyoutPanels) do
        panel:SetShown(i == tabIndex)
    end
    if KART.CtFlyoutTabButtons then
        for i, btn in ipairs(KART.CtFlyoutTabButtons) do
            local active = i == tabIndex
            btn.text:SetTextColor(active and 1 or 0.75, active and 1 or 0.75, active and 1 or 0.75)
        end
    end
    UpdateCtFlyoutScrollRange(tabIndex)
end

KART.CtFlyoutTabButtons = {}
local function AddCtFlyoutTab(index, label, xOff)
    local btn = KART.UI:CreateModernButton(ctFlyTabBar, label)
    btn:SetSize(160, 24)
    btn:SetPoint("TOPLEFT", ctFlyTabBar, "TOPLEFT", xOff, 0)
    btn:SetScript("OnClick", function() KART.ShowCtFlyoutTab(index) end)
    KART.CtFlyoutTabButtons[index] = btn
    return btn
end
AddCtFlyoutTab(1, L.TAB_CT_LOOK, 0)
AddCtFlyoutTab(2, L.TAB_CT_TEXT, 168)
AddCtFlyoutTab(3, L.TAB_CT_AURAS, 336)
KART.ShowCtFlyoutTab(1)

if KART.MainFrame and KART.MainFrame.clickArea then
    KART.MainFrame.clickArea:HookScript("OnDragStop", function()
        if CT.UpdateFlyoutAnchor then CT.UpdateFlyoutAnchor() end
    end)
end

local CT_FILL_L = {
    right = function() return L.CT_FILL_RIGHT end,
    left = function() return L.CT_FILL_LEFT end,
    up = function() return L.CT_FILL_UP end,
    down = function() return L.CT_FILL_DOWN end,
}
local CT_FILL_OPTS = { "right", "left", "up", "down" }
local CT_OUTLINE_L = {
    NONE = function() return L.CT_OUTLINE_NONE end,
    OUTLINE = function() return L.CT_OUTLINE_OUTLINE end,
    THICKOUTLINE = function() return L.CT_OUTLINE_THICK end,
}
local CT_OUTLINE_OPTS = { "NONE", "OUTLINE", "THICKOUTLINE" }
local CT_TEXT_ANCHOR_OPTS = { "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }

local function RefreshCtFillBtn()
    if not KART_Settings then return end
    local mode = CtStore().healthFill or "right"
    local labelFn = CT_FILL_L[mode]
    KART.BtnCtHealthFill.text:SetText(L.SET_CT_HEALTH_FILL .. ": " .. (labelFn and labelFn() or mode))
end

local function CtTextureLabel(key)
    key = key or CtStore().healthTexture
    if not key then return L.CT_TEXTURE_SMOOTH end
    if key:find("WHITE8X8", 1, true) then return L.CT_TEXTURE_FLAT end
    if key:find("UI%-StatusBar", 1, true) then return L.CT_TEXTURE_SMOOTH end
    return key:match("[^\\]+$") or key
end

local function RefreshCtTextureBtn()
    if not KART_Settings or not KART.BtnCtHealthTexture then return end
    KART.BtnCtHealthTexture.text:SetText(L.SET_CT_HEALTH_TEXTURE .. ": " .. CtTextureLabel())
end

local ctLookCard = KART.UI:CreateCard(ctFlyLook)
ctLookCard:SetPoint("TOPLEFT", ctFlyLook, "TOPLEFT", 12, -12)
ctLookCard:SetSize(500, 540)

KART.BtnCtHealthFill = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_FILL, L.DESC_CT_HEALTH_FILL)
KART.BtnCtHealthFill:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -20)
KART.BtnCtHealthFill:SetSize(220, 22)
KART.BtnCtHealthFill:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_FILL)
        for _, opt in ipairs(CT_FILL_OPTS) do
            rootDescription:CreateButton(CT_FILL_L[opt](), function()
                CtStore().healthFill = opt
                RefreshCtFillBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.BtnCtHealthTexture = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_TEXTURE, L.DESC_CT_HEALTH_TEXTURE)
KART.BtnCtHealthTexture:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -20)
KART.BtnCtHealthTexture:SetSize(220, 22)
KART.BtnCtHealthTexture:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_TEXTURE)
        if LSM then
            local textures = LSM:List("statusbar")
            for _, name in ipairs(textures) do
                rootDescription:CreateButton(name, function()
                    CtStore().healthTexture = name
                    RefreshCtTextureBtn()
                    CtLayoutChanged()
                end)
            end
        else
            rootDescription:CreateButton(L.CT_TEXTURE_SMOOTH, function()
                CtStore().healthTexture = "Interface\\TargetingFrame\\UI-StatusBar"
                RefreshCtTextureBtn()
                CtLayoutChanged()
            end)
            rootDescription:CreateButton(L.CT_TEXTURE_FLAT, function()
                CtStore().healthTexture = "Interface\\Buttons\\WHITE8X8"
                RefreshCtTextureBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.SldCtHealthAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtHealthAlphaSlider", label = L.SET_CT_HEALTH_ALPHA,
    min = 10, max = 100, store = CtStore, key = "healthAlpha", y = -60,
    onChanged = function()
        CtStore().healthAlpha = KART.SldCtHealthAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtTrackAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtTrackAlphaSlider", label = L.SET_CT_TRACK_ALPHA,
    min = 0, max = 100, store = CtStore, key = "trackAlpha", y = -60,
    onChanged = function()
        CtStore().trackAlpha = KART.SldCtTrackAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtTrackAlpha:ClearAllPoints()
KART.SldCtTrackAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -76)

KART.BtnCtCustomColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_CUSTOM_COLOR)
KART.BtnCtCustomColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -110)
KART.BtnCtCustomColor:SetSize(220, 22)
KART.BtnCtCustomColor:SetScript("OnClick", function()
    CtPickColor(CtStore().healthCustom, CtLayoutChanged)
end)
KART.BtnCtBgColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_BG_COLOR)
KART.BtnCtBgColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -110)
KART.BtnCtBgColor:SetSize(220, 22)
KART.BtnCtBgColor:SetScript("OnClick", function()
    CtPickColor(CtStore().bgColor, CtLayoutChanged)
end)

KART.BtnCtHealthHigh = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_HIGH)
KART.BtnCtHealthHigh:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -142)
KART.BtnCtHealthHigh:SetSize(220, 22)
KART.BtnCtHealthHigh:SetScript("OnClick", function()
    CtPickColor(CtStore().healthHigh, CtLayoutChanged)
end)
KART.BtnCtHealthMid = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_MID)
KART.BtnCtHealthMid:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -142)
KART.BtnCtHealthMid:SetSize(220, 22)
KART.BtnCtHealthMid:SetScript("OnClick", function()
    CtPickColor(CtStore().healthMid, CtLayoutChanged)
end)
KART.BtnCtHealthLow = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_LOW)
KART.BtnCtHealthLow:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -174)
KART.BtnCtHealthLow:SetSize(220, 22)
KART.BtnCtHealthLow:SetScript("OnClick", function()
    CtPickColor(CtStore().healthLow, CtLayoutChanged)
end)

KART.BtnCtHealthColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEALTH_COLOR, L.DESC_CT_HEALTH_COLOR)
KART.BtnCtHealthColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -174)
KART.BtnCtHealthColor:SetSize(220, 22)
KART.BtnCtHealthColor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_COLOR)
        for _, opt in ipairs({ "class", "custom", "health" }) do
            rootDescription:CreateButton(CT_HEALTH_COLOR_L[opt](), function()
                CtStore().healthColor = opt
                RefreshCtHealthColorBtn()
                CtRefresh()
            end)
        end
    end)
end)

KART.SldCtBgAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtBgAlphaSlider", label = L.SET_CT_BG_ALPHA,
    min = 10, max = 100, store = CtStore, key = "bgAlpha", y = -210,
    onChanged = function()
        CtStore().bgAlpha = KART.SldCtBgAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtBorderSize = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtBorderSizeSlider", label = L.SET_CT_BORDER_SIZE,
    min = 0, max = 4, store = CtStore, key = "borderSize", y = -210,
    onChanged = CtLayoutChanged,
})
KART.SldCtBorderSize:ClearAllPoints()
KART.SldCtBorderSize:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -226)

KART.BtnCtBorderColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_BORDER_COLOR)
KART.BtnCtBorderColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -260)
KART.BtnCtBorderColor:SetSize(220, 22)
KART.BtnCtBorderColor:SetScript("OnClick", function()
    CtPickColor(CtStore().borderColor, CtLayoutChanged)
end)

KART.CbCtAbsorb = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtAbsorb", label = L.SET_CT_ABSORB,
    store = CtStore, key = "absorbShow", y = -292,
    onChanged = CtRefresh,
})
KART.CbCtAbsorb.text:SetWidth(430)
KART.CbCtAbsorb.text:SetJustifyH("LEFT")
KART.CbCtHealAbsorb = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtHealAbsorb", label = L.SET_CT_HEAL_ABSORB,
    store = CtStore, key = "healAbsorbShow", y = -318,
    onChanged = CtRefresh,
})
KART.CbCtHealAbsorb.text:SetWidth(430)
KART.CbCtHealAbsorb.text:SetJustifyH("LEFT")

KART.BtnCtAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_ABSORB_COLOR)
KART.BtnCtAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -350)
KART.BtnCtAbsorbColor:SetSize(220, 22)
KART.BtnCtAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().absorbColor, CtLayoutChanged)
end)
KART.SldCtAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtAbsorbAlphaSlider", label = L.SET_CT_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "absorbAlpha", y = -350,
    onChanged = function()
        CtStore().absorbAlpha = KART.SldCtAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtAbsorbAlpha:ClearAllPoints()
KART.SldCtAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -366)

KART.BtnCtHealAbsorbColor = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_HEAL_ABSORB_COLOR)
KART.BtnCtHealAbsorbColor:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -408)
KART.BtnCtHealAbsorbColor:SetSize(220, 22)
KART.BtnCtHealAbsorbColor:SetScript("OnClick", function()
    CtPickColor(CtStore().healAbsorbColor, CtLayoutChanged)
end)
KART.SldCtHealAbsorbAlpha = KART.UI:CreateSettingsSlider(ctLookCard, {
    name = "KART_CtHealAbsorbAlphaSlider", label = L.SET_CT_HEAL_ABSORB_ALPHA,
    min = 10, max = 100, store = CtStore, key = "healAbsorbAlpha", y = -408,
    onChanged = function()
        CtStore().healAbsorbAlpha = KART.SldCtHealAbsorbAlpha:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtHealAbsorbAlpha:ClearAllPoints()
KART.SldCtHealAbsorbAlpha:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -424)

KART.CbCtGradient = KART.UI:CreateSettingsCheckbox(ctLookCard, {
    name = "KART_CtGradient", label = L.SET_CT_GRADIENT, tooltip = L.DESC_CT_GRADIENT,
    store = CtStore, key = "gradient", y = -456,
    onChanged = CtLayoutChanged,
})

KART.BtnCtGradientFrom = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_GRADIENT_FROM)
KART.BtnCtGradientFrom:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 20, -488)
KART.BtnCtGradientFrom:SetSize(220, 22)
KART.UI:AttachColorSwatch(KART.BtnCtGradientFrom)
KART.BtnCtGradientFrom:SetScript("OnClick", function()
    CtPickColor(CtStore().gradientFrom, CtLayoutChanged)
end)
KART.BtnCtGradientTo = KART.UI:CreateModernButton(ctLookCard, L.SET_CT_GRADIENT_TO)
KART.BtnCtGradientTo:SetPoint("TOPLEFT", ctLookCard, "TOPLEFT", 260, -488)
KART.BtnCtGradientTo:SetSize(220, 22)
KART.UI:AttachColorSwatch(KART.BtnCtGradientTo)
KART.BtnCtGradientTo:SetScript("OnClick", function()
    CtPickColor(CtStore().gradientTo, CtLayoutChanged)
end)

function CT.RefreshGradientSwatches()
    if not KART_Settings or not KART.UI.PaintColorSwatch then return end
    local ct = CtStore()
    KART.UI:PaintColorSwatch(KART.BtnCtGradientFrom, ct.gradientFrom)
    KART.UI:PaintColorSwatch(KART.BtnCtGradientTo, ct.gradientTo)
end

local function CtBuildTextBlock(card, y0, title, storeFn, prefix)
    local titleFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0)
    titleFS:SetText(title)
    KART.UI:RegisterLabel(titleFS)

    local show = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Show", label = L.SET_CT_TEXT_SHOW,
        store = storeFn, key = "show", y = y0 - 24,
        onChanged = CtLayoutChanged,
    })
    local size = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "Size", label = L.SET_CT_TEXT_SIZE,
        min = 0, max = 32, store = storeFn, key = "size", y = y0 - 24,
        onChanged = CtLayoutChanged,
    })
    size:ClearAllPoints()
    size:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 40)

    local colorBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_COLOR)
    colorBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 80)
    colorBtn:SetSize(220, 22)
    colorBtn:SetScript("OnClick", function()
        local st = storeFn()
        st.color = st.color or { r = 1, g = 1, b = 1 }
        CtPickColor(st.color, CtLayoutChanged)
    end)
    local classCb = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Class", label = L.SET_CT_TEXT_CLASS,
        store = storeFn, key = "classColor", y = y0 - 80,
        onChanged = CtLayoutChanged,
    })
    classCb:ClearAllPoints()
    classCb:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 80)

    local outlineBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_OUTLINE)
    outlineBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 112)
    outlineBtn:SetSize(220, 22)
    local function refreshOutline()
        local mode = storeFn().outline or "OUTLINE"
        local labelFn = CT_OUTLINE_L[mode]
        outlineBtn.text:SetText(L.SET_CT_TEXT_OUTLINE .. ": " .. (labelFn and labelFn() or mode))
    end
    outlineBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.SET_CT_TEXT_OUTLINE)
            for _, opt in ipairs(CT_OUTLINE_OPTS) do
                rootDescription:CreateButton(CT_OUTLINE_L[opt](), function()
                    storeFn().outline = opt
                    refreshOutline()
                    CtLayoutChanged()
                end)
            end
        end)
    end)

    local anchorBtn = KART.UI:CreateModernButton(card, L.SET_CT_TEXT_ANCHOR)
    anchorBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 112)
    anchorBtn:SetSize(220, 22)
    local function refreshAnchor()
        local mode = storeFn().anchor or "LEFT"
        anchorBtn.text:SetText(L.SET_CT_TEXT_ANCHOR .. ": " .. mode)
    end
    anchorBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateTitle(L.SET_CT_TEXT_ANCHOR)
            for _, opt in ipairs(CT_TEXT_ANCHOR_OPTS) do
                rootDescription:CreateButton(opt, function()
                    storeFn().anchor = opt
                    refreshAnchor()
                    CtLayoutChanged()
                end)
            end
        end)
    end)

    local nudgeX = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeX", label = L.SET_CT_TEXT_NUDGE_X,
        min = -40, max = 40, store = storeFn, key = "x", y = y0 - 150,
        onChanged = CtLayoutChanged,
    })
    local nudgeY = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeY", label = L.SET_CT_TEXT_NUDGE_Y,
        min = -40, max = 40, store = storeFn, key = "y", y = y0 - 150,
        onChanged = CtLayoutChanged,
    })
    nudgeY:ClearAllPoints()
    nudgeY:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 166)

    return {
        show = show, size = size, colorBtn = colorBtn, classCb = classCb,
        outlineBtn = outlineBtn, refreshOutline = refreshOutline,
        anchorBtn = anchorBtn, refreshAnchor = refreshAnchor,
        nudgeX = nudgeX, nudgeY = nudgeY, titleFS = titleFS,
    }
end

local ctFadeCard = KART.UI:CreateCard(ctFlyLook)
ctFadeCard:SetPoint("TOPLEFT", ctLookCard, "BOTTOMLEFT", 0, -20)
ctFadeCard:SetSize(500, 280)

local ctTextCard = KART.UI:CreateCard(ctFlyText)
ctTextCard:SetPoint("TOPLEFT", ctFlyText, "TOPLEFT", 12, -12)
ctTextCard:SetSize(500, 490)

KART.BtnCtHealthText = KART.UI:CreateModernButton(ctTextCard, L.SET_CT_HEALTH_TEXT, L.DESC_CT_HEALTH_TEXT)
KART.BtnCtHealthText:SetPoint("TOPLEFT", ctTextCard, "TOPLEFT", 20, -20)
KART.BtnCtHealthText:SetSize(220, 22)
KART.BtnCtHealthText:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_HEALTH_TEXT)
        for _, opt in ipairs({ "percent", "current", "both", "deficit" }) do
            rootDescription:CreateButton(CT_HEALTH_TEXT_L[opt](), function()
                CtStore().healthText = opt
                RefreshCtHealthTextBtn()
                CtRefresh()
            end)
        end
    end)
end)

KART.SldCtNameMax = KART.UI:CreateSettingsSlider(ctTextCard, {
    name = "KART_CtNameMaxSlider", label = L.SET_CT_NAME_MAX,
    min = 4, max = 24, store = CtStore, key = "nameMaxLength", y = -20,
    onChanged = CtRefresh,
})
KART.SldCtNameMax:ClearAllPoints()
KART.SldCtNameMax:SetPoint("TOPLEFT", ctTextCard, "TOPLEFT", 260, -36)

KART.CtNameTextWidgets = CtBuildTextBlock(ctTextCard, -70, L.LABEL_CT_NAME_TEXT, CtNameStyle, "Name")
KART.CtHealthTextWidgets = CtBuildTextBlock(ctTextCard, -276, L.LABEL_CT_HEALTH_TEXT, CtHealthStyle, "Hp")

KART.CbCtRangeFadeOn = KART.UI:CreateSettingsCheckbox(ctFadeCard, {
    name = "KART_CtRangeFadeOn", label = L.SET_CT_RANGE_FADE_ON,
    store = CtStore, key = "rangeFade", y = -20,
    onChanged = CtRefresh,
})
KART.SldCtRangeFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtRangeFadeSlider", label = L.SET_CT_RANGE_FADE,
    min = 10, max = 100, store = CtStore, key = "rangeAlpha", y = -20,
    onChanged = function()
        CtStore().rangeAlpha = KART.SldCtRangeFade:GetValue() / 100
        CtLayoutChanged()
    end,
})
KART.SldCtRangeFade:ClearAllPoints()
KART.SldCtRangeFade:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -36)
KART.SldCtDeadFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtDeadFadeSlider", label = L.SET_CT_DEAD_FADE,
    min = 10, max = 100, store = CtStore, key = "deadFade", y = -60,
    onChanged = function()
        CtStore().deadFade = KART.SldCtDeadFade:GetValue() / 100
        CtRefresh()
    end,
})
KART.SldCtOfflineFade = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtOfflineFadeSlider", label = L.SET_CT_OFFLINE_FADE,
    min = 10, max = 100, store = CtStore, key = "offlineFade", y = -60,
    onChanged = function()
        CtStore().offlineFade = KART.SldCtOfflineFade:GetValue() / 100
        CtRefresh()
    end,
})
KART.SldCtOfflineFade:ClearAllPoints()
KART.SldCtOfflineFade:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -76)

KART.CbCtTargetBorder = KART.UI:CreateSettingsCheckbox(ctFadeCard, {
    name = "KART_CtTargetBorder", label = L.SET_CT_TARGET_BORDER,
    store = CtTargetBorder, key = "show", y = -110,
    tooltip = L.DESC_CT_TARGET_BORDER,
    onChanged = CtRefresh,
})
KART.SldCtTargetBorderSize = KART.UI:CreateSettingsSlider(ctFadeCard, {
    name = "KART_CtTargetBorderSize", label = L.SET_CT_TARGET_BORDER_SIZE,
    min = 1, max = 6, store = CtTargetBorder, key = "size", y = -150,
    onChanged = CtLayoutChanged,
})
KART.BtnCtTargetBorderColor = KART.UI:CreateModernButton(ctFadeCard, L.SET_CT_TARGET_BORDER_COLOR)
KART.BtnCtTargetBorderColor:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 260, -166)
KART.BtnCtTargetBorderColor:SetSize(220, 22)
KART.BtnCtTargetBorderColor:SetScript("OnClick", function()
    local tb = CtTargetBorder()
    tb.color = tb.color or { r = 1, g = 0.85, b = 0.2 }
    CtPickColor(tb.color, CtLayoutChanged)
end)

local ctPreviewAsLabel = ctFadeCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctPreviewAsLabel:SetPoint("TOPLEFT", ctFadeCard, "TOPLEFT", 20, -200)
ctPreviewAsLabel:SetText(L.SET_CT_PREVIEW_AS)
KART.UI:RegisterLabel(ctPreviewAsLabel)

local ctPreviewStateHost = CreateFrame("Frame", nil, ctFadeCard)
ctPreviewStateHost:SetPoint("TOPLEFT", ctPreviewAsLabel, "BOTTOMLEFT", 0, -8)
ctPreviewStateHost:SetSize(460, 48)

local function PaintCtPreviewStateChip(btn, on)
    local r, g, b = KART.UI:AccentColor()
    if on then
        btn:SetBackdropColor(r, g, b, 0.55)
        btn:SetBackdropBorderColor(r, g, b, 1)
        btn.text:SetTextColor(1, 1, 1)
    else
        btn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        btn.text:SetTextColor(0.55, 0.55, 0.55)
    end
end

local function CtPreviewStateIs(key)
    local state = KART.CT and KART.CT.previewState or "ok"
    if state ~= "oor" and state ~= "dead" and state ~= "offline" then
        state = "ok"
    end
    return state == key
end

local function RefreshCtPreviewStateChips()
    if not KART.CtPreviewStateChips then return end
    for _, chip in ipairs(KART.CtPreviewStateChips) do
        local on = CtPreviewStateIs(chip.stateKey)
        chip.chipOn = on
        PaintCtPreviewStateChip(chip, on)
    end
end

local function CreateCtPreviewStateChip(label, key)
    local btn = KART.UI:CreateModernButton(ctPreviewStateHost, label)
    btn:SetHeight(22)
    btn.stateKey = key
    local function refresh()
        btn.chipOn = CtPreviewStateIs(key)
        PaintCtPreviewStateChip(btn, btn.chipOn)
    end
    btn:SetScript("OnClick", function()
        if KART.CT and KART.CT.SetPreviewState then
            KART.CT.SetPreviewState(key)
        end
        RefreshCtPreviewStateChips()
    end)
    btn:SetScript("OnEnter", function(self)
        local r, g, b = KART.UI:AccentColor()
        if self.chipOn then
            local lr, lg, lb = KAUI.Lighten(r, g, b, 0.12)
            self:SetBackdropColor(lr, lg, lb, 0.75)
        else
            self:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
    end)
    btn:SetScript("OnLeave", function() refresh() end)
    btn.Refresh = refresh
    refresh()
    return btn
end

KART.CtPreviewStateChips = {
    CreateCtPreviewStateChip(L.SET_CT_PREVIEW_OK, "ok"),
    CreateCtPreviewStateChip(L.SET_CT_PREVIEW_OOR, "oor"),
    CreateCtPreviewStateChip(L.SET_CT_PREVIEW_DEAD, "dead"),
    CreateCtPreviewStateChip(L.SET_CT_PREVIEW_OFFLINE, "offline"),
}

function KART.LayoutCtPreviewStateChips()
    local chips = KART.CtPreviewStateChips
    if not chips then return end
    local gap, maxW, h = 4, 460, 22
    local cols = 2
    local w = math.floor((maxW - gap * (cols - 1)) / cols)
    local font = KART.UI.lastFont or "Fonts\\FRIZQT__.TTF"
    for i, chip in ipairs(chips) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        chip:SetSize(w, h)
        chip.text:SetFont(font, 9, "")
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", ctPreviewStateHost, "TOPLEFT", col * (w + gap), -row * (h + gap))
    end
    ctPreviewStateHost:SetHeight(h * 2 + gap)
end
KART.LayoutCtPreviewStateChips()

local ctDebuffTitle = ctFlyAuras:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctDebuffTitle:SetPoint("TOPLEFT", ctFlyAuras, "TOPLEFT", 12, -12)
ctDebuffTitle:SetText(L.LABEL_CT_DEBUFFS)
KART.UI:RegisterHeading(ctDebuffTitle)

local ctDebuffCard = KART.UI:CreateCard(ctFlyAuras)
ctDebuffCard:SetPoint("TOPLEFT", ctDebuffTitle, "BOTTOMLEFT", 0, -10)
ctDebuffCard:SetSize(500, 430)
KART.CtDebuffCard = ctDebuffCard

KART.CbCtDebuffShow = KART.UI:CreateSettingsCheckbox(ctDebuffCard, {
    name = "KART_CtDebuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtDebuffs, key = "show", y = -48,
    onChanged = CtRefresh,
})
KART.SldCtDebuffMax = KART.UI:CreateSettingsSlider(ctDebuffCard, {
    name = "KART_CtDebuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtDebuffs, key = "max", y = -48,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffMax:ClearAllPoints()
KART.SldCtDebuffMax:SetPoint("TOPLEFT", ctDebuffCard, "TOPLEFT", 260, -64)

KART.SldCtDebuffSize = KART.UI:CreateSettingsSlider(ctDebuffCard, {
    name = "KART_CtDebuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 100, store = CtDebuffs, key = "size", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing = KART.UI:CreateSettingsSlider(ctDebuffCard, {
    name = "KART_CtDebuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtDebuffs, key = "spacing", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtDebuffSpacing:ClearAllPoints()
KART.SldCtDebuffSpacing:SetPoint("TOPLEFT", ctDebuffCard, "TOPLEFT", 260, -104)

KART.BtnCtDebuffAnchor = KART.UI:CreateModernButton(ctDebuffCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtDebuffAnchor:SetPoint("TOPLEFT", ctDebuffCard, "TOPLEFT", 20, -128)
KART.BtnCtDebuffAnchor:SetSize(220, 22)
KART.BtnCtDebuffAnchor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_ANCHOR)
        for _, opt in ipairs(CT_ANCHOR_OPTS) do
            rootDescription:CreateButton(CT_ANCHOR_L[opt](), function()
                CtDebuffs().anchor = opt
                RefreshCtDebuffAnchorBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.BtnCtDebuffGrowth = KART.UI:CreateModernButton(ctDebuffCard, L.SET_CT_AURA_GROWTH, L.DESC_CT_AURA_GROWTH)
KART.BtnCtDebuffGrowth:SetPoint("TOPLEFT", ctDebuffCard, "TOPLEFT", 260, -128)
KART.BtnCtDebuffGrowth:SetSize(220, 22)
KART.BtnCtDebuffGrowth:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_GROWTH)
        for _, opt in ipairs(CT_GROWTH_OPTS) do
            rootDescription:CreateButton(CT_GROWTH_L[opt](), function()
                CtDebuffs().growth = opt
                RefreshCtDebuffGrowthBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.CbCtHideLongDuration = KART.UI:CreateSettingsCheckbox(ctDebuffCard, {
    name = "KART_CtHideLongDuration", label = L.SET_CT_HIDE_LONG_DURATION,
    tooltip = L.DESC_CT_HIDE_LONG_DURATION,
    store = CtDebuffs, key = "hideLongDuration", y = -360,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideLongDuration.text:SetWidth(430)
KART.CbCtHideLongDuration.text:SetJustifyH("LEFT")
KART.CbCtHideFatigue = KART.UI:CreateSettingsCheckbox(ctDebuffCard, {
    name = "KART_CtHideFatigue", label = L.SET_CT_HIDE_FATIGUE,
    tooltip = L.DESC_CT_HIDE_FATIGUE,
    store = CtDebuffs, key = "hideFatigue", y = -388,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideFatigue.text:SetWidth(430)
KART.CbCtHideFatigue.text:SetJustifyH("LEFT")

local ctBuffTitle = ctFlyAuras:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctBuffTitle:SetPoint("TOPLEFT", ctDebuffCard, "BOTTOMLEFT", 0, -18)
ctBuffTitle:SetText(L.LABEL_CT_BUFFS)
KART.UI:RegisterHeading(ctBuffTitle)

local ctBuffCard = KART.UI:CreateCard(ctFlyAuras)
ctBuffCard:SetPoint("TOPLEFT", ctBuffTitle, "BOTTOMLEFT", 0, -10)
ctBuffCard:SetSize(500, 450)
KART.CtBuffCard = ctBuffCard

KART.CbCtBuffShow = KART.UI:CreateSettingsCheckbox(ctBuffCard, {
    name = "KART_CtBuffShow", label = L.SET_CT_AURA_SHOW,
    store = CtBuffs, key = "show", y = -48,
    onChanged = CtRefresh,
})
KART.SldCtBuffMax = KART.UI:CreateSettingsSlider(ctBuffCard, {
    name = "KART_CtBuffMaxSlider", label = L.SET_CT_AURA_MAX,
    min = 1, max = 16, store = CtBuffs, key = "max", y = -48,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffMax:ClearAllPoints()
KART.SldCtBuffMax:SetPoint("TOPLEFT", ctBuffCard, "TOPLEFT", 260, -64)

KART.SldCtBuffSize = KART.UI:CreateSettingsSlider(ctBuffCard, {
    name = "KART_CtBuffSizeSlider", label = L.SET_CT_AURA_SIZE,
    min = 12, max = 40, store = CtBuffs, key = "size", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing = KART.UI:CreateSettingsSlider(ctBuffCard, {
    name = "KART_CtBuffSpacingSlider", label = L.SET_CT_AURA_SPACING,
    min = 0, max = 8, store = CtBuffs, key = "spacing", y = -88,
    onChanged = CtLayoutChanged,
})
KART.SldCtBuffSpacing:ClearAllPoints()
KART.SldCtBuffSpacing:SetPoint("TOPLEFT", ctBuffCard, "TOPLEFT", 260, -104)

KART.BtnCtBuffAnchor = KART.UI:CreateModernButton(ctBuffCard, L.SET_CT_AURA_ANCHOR, L.DESC_CT_AURA_ANCHOR)
KART.BtnCtBuffAnchor:SetPoint("TOPLEFT", ctBuffCard, "TOPLEFT", 20, -128)
KART.BtnCtBuffAnchor:SetSize(220, 22)
KART.BtnCtBuffAnchor:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_ANCHOR)
        for _, opt in ipairs(CT_ANCHOR_OPTS) do
            rootDescription:CreateButton(CT_ANCHOR_L[opt](), function()
                CtBuffs().anchor = opt
                RefreshCtBuffAnchorBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

KART.BtnCtBuffGrowth = KART.UI:CreateModernButton(ctBuffCard, L.SET_CT_AURA_GROWTH, L.DESC_CT_AURA_GROWTH)
KART.BtnCtBuffGrowth:SetPoint("TOPLEFT", ctBuffCard, "TOPLEFT", 260, -128)
KART.BtnCtBuffGrowth:SetSize(220, 22)
KART.BtnCtBuffGrowth:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L.SET_CT_AURA_GROWTH)
        for _, opt in ipairs(CT_GROWTH_OPTS) do
            rootDescription:CreateButton(CT_GROWTH_L[opt](), function()
                CtBuffs().growth = opt
                RefreshCtBuffGrowthBtn()
                CtLayoutChanged()
            end)
        end
    end)
end)

local function CtAddStripExtras(card, storeFn, prefix, y0)
    local perRow = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "PerRow", label = L.SET_CT_AURA_PER_ROW,
        min = 1, max = 20, store = storeFn, key = "perRow", y = y0,
        onChanged = CtLayoutChanged,
    })
    local border = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "Border", label = L.SET_CT_AURA_BORDER,
        min = 0, max = 4, store = storeFn, key = "borderSize", y = y0,
        onChanged = CtLayoutChanged,
    })
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 16)

    local nudgeX = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeX", label = L.SET_CT_AURA_NUDGE_X,
        min = -60, max = 60, store = storeFn, key = "x", y = y0 - 40,
        onChanged = CtLayoutChanged,
    })
    local nudgeY = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "NudgeY", label = L.SET_CT_AURA_NUDGE_Y,
        min = -60, max = 60, store = storeFn, key = "y", y = y0 - 40,
        onChanged = CtLayoutChanged,
    })
    nudgeY:ClearAllPoints()
    nudgeY:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 56)

    local borderColor = KART.UI:CreateModernButton(card, L.SET_CT_AURA_BORDER_COLOR)
    borderColor:SetPoint("TOPLEFT", card, "TOPLEFT", 20, y0 - 90)
    borderColor:SetSize(220, 22)
    borderColor:SetScript("OnClick", function()
        local st = storeFn()
        st.borderColor = st.borderColor or { r = 0, g = 0, b = 0 }
        CtPickColor(st.borderColor, CtLayoutChanged)
    end)

    local swipe = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Swipe", label = L.SET_CT_AURA_SWIPE,
        store = storeFn, key = "swipe", y = y0 - 90,
        onChanged = CtLayoutChanged,
    })
    swipe:ClearAllPoints()
    swipe:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 90)

    local countdown = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Countdown", label = L.SET_CT_AURA_COUNTDOWN,
        store = storeFn, key = "countdown", y = y0 - 120,
        onChanged = CtLayoutChanged,
    })
    local cdSize = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "CdSize", label = L.SET_CT_AURA_COUNTDOWN_SIZE,
        min = 0, max = 24, store = storeFn, key = "countdownSize", y = y0 - 120,
        onChanged = CtLayoutChanged,
    })
    cdSize:ClearAllPoints()
    cdSize:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 136)

    local stacks = KART.UI:CreateSettingsCheckbox(card, {
        name = "KART_Ct" .. prefix .. "Stacks", label = L.SET_CT_AURA_STACKS,
        store = storeFn, key = "stacks", y = y0 - 160,
        onChanged = CtLayoutChanged,
    })
    local stSize = KART.UI:CreateSettingsSlider(card, {
        name = "KART_Ct" .. prefix .. "StSize", label = L.SET_CT_AURA_STACKS_SIZE,
        min = 0, max = 24, store = storeFn, key = "stacksSize", y = y0 - 160,
        onChanged = CtLayoutChanged,
    })
    stSize:ClearAllPoints()
    stSize:SetPoint("TOPLEFT", card, "TOPLEFT", 260, y0 - 176)

    return {
        perRow = perRow, border = border, nudgeX = nudgeX, nudgeY = nudgeY,
        borderColor = borderColor, swipe = swipe, countdown = countdown,
        cdSize = cdSize, stacks = stacks, stSize = stSize,
    }
end

KART.CtDebuffExtra = CtAddStripExtras(ctDebuffCard, CtDebuffs, "DebuffEx", -158)
KART.CtBuffExtra = CtAddStripExtras(ctBuffCard, CtBuffs, "BuffEx", -158)

KART.CbCtHideLongBuffs = KART.UI:CreateSettingsCheckbox(ctBuffCard, {
    name = "KART_CtHideLongBuffs", label = L.SET_CT_HIDE_LONG_DURATION,
    tooltip = L.DESC_CT_HIDE_LONG_BUFFS,
    store = CtBuffs, key = "hideLongDuration", y = -360,
    onChanged = CtLayoutChanged,
})
KART.CbCtHideLongBuffs.text:SetWidth(430)
KART.CbCtHideLongBuffs.text:SetJustifyH("LEFT")

local ctAuraChromeNote = ctBuffCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctAuraChromeNote:SetPoint("BOTTOMLEFT", ctBuffCard, "BOTTOMLEFT", 20, 12)
ctAuraChromeNote:SetPoint("BOTTOMRIGHT", ctBuffCard, "BOTTOMRIGHT", -20, 12)
ctAuraChromeNote:SetJustifyH("LEFT")
ctAuraChromeNote:SetWordWrap(true)
ctAuraChromeNote:SetText(L.SET_CT_AURA_DUMMY_CHROME)
KART.UI:RegisterLabel(ctAuraChromeNote)

local function CtTaunt()
    local ct = CtStore()
    ct.taunt = ct.taunt or {}
    return ct.taunt
end
local function CtTauntChannels()
    local t = CtTaunt()
    t.channels = t.channels or {}
    return t.channels
end
local function CtTauntChanged()
    if KART.CT and KART.CT.RefreshAskButton then KART.CT.RefreshAskButton() end
end

local ctTauntTitle = KART.CoTankPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctTauntTitle:SetPoint("TOPLEFT", ctRowCard, "BOTTOMLEFT", 0, -18)
ctTauntTitle:SetText(L.LABEL_CT_TAUNT)
KART.UI:RegisterLabel(ctTauntTitle)

local ctTauntCard = KART.UI:CreateCard(KART.CoTankPanel)
ctTauntCard:SetPoint("TOPLEFT", ctTauntTitle, "BOTTOMLEFT", 0, -10)
ctTauntCard:SetSize(500, 252)

KART.CbCtTauntAnnounce = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntAnnounce", label = L.SET_CT_TAUNT_ANNOUNCE,
    store = CtTaunt, key = "announce", y = -32,
    tooltip = L.DESC_CT_TAUNT_ANNOUNCE,
})
KART.CbCtTauntAnnounce.text:SetWidth(430)
KART.CbCtTauntAnnounce.text:SetJustifyH("LEFT")

KART.CbCtTauntOnlyGroup = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntOnlyGroup", label = L.SET_CT_TAUNT_ONLY_GROUP,
    store = CtTaunt, key = "onlyInGroup", y = -54,
    tooltip = L.DESC_CT_TAUNT_ONLY_GROUP,
})
KART.CbCtTauntOnlyGroup.text:SetWidth(430)
KART.CbCtTauntOnlyGroup.text:SetJustifyH("LEFT")

KART.CbCtTauntOnlyDungeon = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntOnlyDungeon", label = L.SET_CT_TAUNT_ONLY_DUNGEON,
    store = CtTaunt, key = "onlyInDungeon", y = -76,
    tooltip = L.DESC_CT_TAUNT_ONLY_DUNGEON,
})
KART.CbCtTauntOnlyDungeon.text:SetWidth(192)
KART.CbCtTauntOnlyDungeon.text:SetJustifyH("LEFT")

KART.CbCtTauntOnlyRaid = KART.UI:CreateSettingsCheckbox(ctTauntCard, {
    name = "KART_CtTauntOnlyRaid", label = L.SET_CT_TAUNT_ONLY_RAID,
    store = CtTaunt, key = "onlyInRaid", y = -76,
    tooltip = L.DESC_CT_TAUNT_ONLY_RAID,
})
KART.CbCtTauntOnlyRaid:ClearAllPoints()
KART.CbCtTauntOnlyRaid:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 260, -76)
KART.CbCtTauntOnlyRaid.text:SetWidth(192)
KART.CbCtTauntOnlyRaid.text:SetJustifyH("LEFT")

local ctTauntChanTitle = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctTauntChanTitle:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 20, -100)
ctTauntChanTitle:SetText(L.SET_CT_TAUNT_CHANNELS)
KART.UI:RegisterLabel(ctTauntChanTitle)

-- Packed chip row, same ON/OFF fill as invite channels: five labels in a line
-- (wrapping if a locale is long) instead of a tight two-column checkbox stack.
local tauntChipHost = CreateFrame("Frame", nil, ctTauntCard)
tauntChipHost:SetPoint("TOPLEFT", ctTauntCard, "TOPLEFT", 20, -118)
tauntChipHost:SetSize(460, 22)

local function PaintTauntChannelChip(btn, on)
    local r, g, b = KART.UI:AccentColor()
    if on then
        btn:SetBackdropColor(r, g, b, 0.55)
        btn:SetBackdropBorderColor(r, g, b, 1)
        btn.text:SetTextColor(1, 1, 1)
    else
        btn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        btn.text:SetTextColor(0.55, 0.55, 0.55)
    end
end

local function CreateTauntChannelChip(label, key)
    local btn = KART.UI:CreateModernButton(ctTauntCard, label)
    btn:SetHeight(22)
    local function refresh()
        if not KART_Settings then
            btn.chipOn = false
            PaintTauntChannelChip(btn, false)
            return
        end
        local ch = CtTauntChannels()
        btn.chipOn = ch[key] == true
        PaintTauntChannelChip(btn, btn.chipOn)
    end
    function btn:SetChecked(value)
        self.chipOn = not not value
        PaintTauntChannelChip(self, self.chipOn)
    end
    function btn:GetChecked()
        return self.chipOn
    end
    btn:SetScript("OnClick", function()
        if not KART_Settings then return end
        local ch = CtTauntChannels()
        ch[key] = not ch[key]
        refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        local r, g, b = KART.UI:AccentColor()
        if self.chipOn then
            local lr, lg, lb = KAUI.Lighten(r, g, b, 0.12)
            self:SetBackdropColor(lr, lg, lb, 0.75)
        else
            self:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
    end)
    btn:SetScript("OnLeave", function() refresh() end)
    btn.Refresh = refresh
    btn.channelKey = key
    refresh()
    return btn
end

KART.CbCtTauntWhisper = CreateTauntChannelChip(L.SET_CT_TAUNT_WHISPER, "WHISPER")
KART.CbCtTauntGroup = CreateTauntChannelChip(L.SET_CT_TAUNT_GROUP, "GROUP")
KART.CbCtTauntRW = CreateTauntChannelChip(L.SET_CT_TAUNT_RW, "RAID_WARNING")
KART.CbCtTauntSay = CreateTauntChannelChip(L.SET_CT_TAUNT_SAY, "SAY")
KART.CbCtTauntYell = CreateTauntChannelChip(L.SET_CT_TAUNT_YELL, "YELL")
KART.TauntChannelChips = {
    KART.CbCtTauntWhisper, KART.CbCtTauntGroup, KART.CbCtTauntRW,
    KART.CbCtTauntSay, KART.CbCtTauntYell,
}

function KART.LayoutTauntChannelChips()
    -- One row of equal chips; wrapping left Yell on its own line and a hole on the right.
    local n = #KART.TauntChannelChips
    local gap, maxW, h = 4, 460, 22
    local w = math.floor((maxW - gap * (n - 1)) / n)
    local font = KART.UI.lastFont or "Fonts\\FRIZQT__.TTF"
    for i, chip in ipairs(KART.TauntChannelChips) do
        chip:SetSize(w, h)
        chip.text:SetFont(font, 9, "")
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", tauntChipHost, "TOPLEFT", (i - 1) * (w + gap), 0)
    end
    tauntChipHost:SetHeight(h)
end
KART.LayoutTauntChannelChips()

local ctTauntMsgLabel = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctTauntMsgLabel:SetPoint("TOPLEFT", tauntChipHost, "BOTTOMLEFT", 0, -12)
ctTauntMsgLabel:SetText(L.SET_CT_TAUNT_MESSAGE)
KART.UI:RegisterLabel(ctTauntMsgLabel)

KART.EbCtTauntMessage = KART.UI:CreateStyledEditBox(ctTauntCard, "KART_CtTauntMessage")
KART.EbCtTauntMessage:SetSize(460, 28)
KART.EbCtTauntMessage:SetPoint("TOPLEFT", ctTauntMsgLabel, "BOTTOMLEFT", 0, -6)
KART.EbCtTauntMessage:SetMaxLetters(200)
KART.EbCtTauntMessage:SetScript("OnTextChanged", function(self)
    CtTaunt().message = self:GetText()
end)

local ctTauntPlace = ctTauntCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctTauntPlace:SetPoint("TOPLEFT", KART.EbCtTauntMessage, "BOTTOMLEFT", 0, -6)
ctTauntPlace:SetWidth(460)
ctTauntPlace:SetJustifyH("LEFT")
ctTauntPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS)
KART.UI:RegisterLabel(ctTauntPlace)

local ctAskTitle = KART.CoTankPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ctAskTitle:SetPoint("TOPLEFT", ctTauntCard, "BOTTOMLEFT", 0, -18)
ctAskTitle:SetText(L.LABEL_CT_TAUNT_ASK)
KART.UI:RegisterLabel(ctAskTitle)

local ctAskCard = KART.UI:CreateCard(KART.CoTankPanel)
ctAskCard:SetPoint("TOPLEFT", ctAskTitle, "BOTTOMLEFT", 0, -10)
ctAskCard:SetSize(500, 268)

KART.CbCtTauntButton = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntButton", label = L.SET_CT_TAUNT_BUTTON,
    store = CtTaunt, key = "button", y = -32,
    tooltip = L.DESC_CT_TAUNT_BUTTON,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntButton.text:SetWidth(430)
KART.CbCtTauntButton.text:SetJustifyH("LEFT")

KART.CbCtTauntBtnLock = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnLock", label = L.SET_CT_TAUNT_BTN_LOCK,
    store = CtTaunt, key = "locked", y = -54,
    tooltip = L.DESC_CT_TAUNT_BTN_LOCK,
})
KART.CbCtTauntBtnGroup = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnGroup", label = L.SET_CT_TAUNT_BTN_GROUP,
    store = CtTaunt, key = "buttonOnlyInGroup", y = -76,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntBtnGroup.text:SetWidth(192)
KART.CbCtTauntBtnGroup.text:SetJustifyH("LEFT")
KART.CbCtTauntBtnRaid = KART.UI:CreateSettingsCheckbox(ctAskCard, {
    name = "KART_CtTauntBtnRaid", label = L.SET_CT_TAUNT_BTN_RAID,
    store = CtTaunt, key = "buttonOnlyInRaid", y = -76,
    tooltip = L.DESC_CT_TAUNT_BTN_RAID,
    onChanged = CtTauntChanged,
})
KART.CbCtTauntBtnRaid:ClearAllPoints()
KART.CbCtTauntBtnRaid:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 260, -76)
KART.CbCtTauntBtnRaid.text:SetWidth(192)
KART.CbCtTauntBtnRaid.text:SetJustifyH("LEFT")

KART.SldCtTauntSize = KART.UI:CreateSettingsSlider(ctAskCard, {
    name = "KART_CtTauntSizeSlider", label = L.SET_CT_TAUNT_SIZE,
    min = 20, max = 80, store = CtTaunt, key = "size", y = -108,
    onChanged = CtTauntChanged,
})

local ctAskMsgLabel = ctAskCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ctAskMsgLabel:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 20, -156)
ctAskMsgLabel:SetText(L.SET_CT_TAUNT_ASK)
KART.UI:RegisterLabel(ctAskMsgLabel)

KART.EbCtTauntAsk = KART.UI:CreateStyledEditBox(ctAskCard, "KART_CtTauntAsk")
KART.EbCtTauntAsk:SetSize(460, 28)
KART.EbCtTauntAsk:SetPoint("TOPLEFT", ctAskMsgLabel, "BOTTOMLEFT", 0, -6)
KART.EbCtTauntAsk:SetMaxLetters(200)
KART.EbCtTauntAsk:SetScript("OnTextChanged", function(self)
    CtTaunt().ask = self:GetText()
end)

local ctAskPlace = ctAskCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ctAskPlace:SetPoint("TOPLEFT", KART.EbCtTauntAsk, "BOTTOMLEFT", 0, -6)
ctAskPlace:SetWidth(460)
ctAskPlace:SetJustifyH("LEFT")
ctAskPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS)
KART.UI:RegisterLabel(ctAskPlace)

KART.BtnCtTauntMacro = KART.UI:CreateModernButton(ctAskCard, L.BTN_CT_TAUNT_MACRO, L.DESC_CT_TAUNT_MACRO)
KART.BtnCtTauntMacro:SetPoint("TOPLEFT", ctAskCard, "TOPLEFT", 20, -228)
KART.BtnCtTauntMacro:SetSize(280, 24)
KART.BtnCtTauntMacro:SetScript("OnClick", function()
    if not KART.CT or not KART.CT.CreateAskMacro then return end
    local result = KART.CT.CreateAskMacro()
    if result == "combat" and UIErrorsFrame then
        UIErrorsFrame:AddMessage(L.ERR_CT_TAUNT_MACRO_COMBAT, 1, 0.1, 0.1, 1, 3)
    end
end)


KART.UI:RegisterLocaleRefresher(function()
    L = KART.L
    -- Co-Tank tab
    KART.CbCtModuleEnabled.text:SetText(L.SET_CT_MODULE_ENABLED)  KART.CbCtModuleEnabled.tooltipText = L.DESC_CT_MODULE_ENABLED
    KART.CbCtTestMode.text:SetText(L.SET_CT_TESTMODE)             KART.CbCtTestMode.tooltipText = L.DESC_CT_TESTMODE
    KART.CbCtLock.text:SetText(L.SET_CT_LOCK)                     KART.CbCtLock.tooltipText = L.DESC_CT_LOCK
    if KART.CbCtOnlyGroup then
        KART.CbCtOnlyGroup.text:SetText(L.SET_CT_ONLY_GROUP)
        KART.CbCtOnlyGroup.tooltipText = L.DESC_CT_ONLY_GROUP
    end
    if KART.CbCtOnlyInstance then
        KART.CbCtOnlyInstance.text:SetText(L.SET_CT_ONLY_INSTANCE)
        KART.CbCtOnlyInstance.tooltipText = L.DESC_CT_ONLY_INSTANCE
    end
    if ctPreviewTitle then ctPreviewTitle:SetText(L.LABEL_CT_PREVIEW) end
    if KART.CtAuraEngineNote then KART.CtAuraEngineNote:SetText(L.SET_CT_AURA_ENGINE) end
    KART.SldCtWidth.title:SetText(L.SET_CT_WIDTH)
    KART.SldCtHeight.title:SetText(L.SET_CT_HEIGHT)
    KART.SldCtScale.title:SetText(L.SET_CT_SCALE)
    KART.SldCtRangeFade.title:SetText(L.SET_CT_RANGE_FADE)
    KART.SldCtNameMax.title:SetText(L.SET_CT_NAME_MAX)
    KART.CbCtAbsorb.text:SetText(L.SET_CT_ABSORB)
    KART.CbCtHealAbsorb.text:SetText(L.SET_CT_HEAL_ABSORB)
    if KART.CbCtHealAbsorb.text.SetWidth then KART.CbCtHealAbsorb.text:SetWidth(430) end
    KART.BtnCtHealthColor.tooltipText = L.DESC_CT_HEALTH_COLOR
    KART.BtnCtHealthText.tooltipText = L.DESC_CT_HEALTH_TEXT
    RefreshCtHealthColorBtn()
    RefreshCtHealthTextBtn()
    if RefreshCtFillBtn then RefreshCtFillBtn() end
    if RefreshCtTextureBtn then RefreshCtTextureBtn() end
    if KART.SldCtHealthAlpha then KART.SldCtHealthAlpha.title:SetText(L.SET_CT_HEALTH_ALPHA) end
    if KART.SldCtTrackAlpha then KART.SldCtTrackAlpha.title:SetText(L.SET_CT_TRACK_ALPHA) end
    if KART.SldCtBgAlpha then KART.SldCtBgAlpha.title:SetText(L.SET_CT_BG_ALPHA) end
    if KART.SldCtBorderSize then KART.SldCtBorderSize.title:SetText(L.SET_CT_BORDER_SIZE) end
    if KART.SldCtAbsorbAlpha then KART.SldCtAbsorbAlpha.title:SetText(L.SET_CT_ABSORB_ALPHA) end
    if KART.SldCtHealAbsorbAlpha then KART.SldCtHealAbsorbAlpha.title:SetText(L.SET_CT_HEAL_ABSORB_ALPHA) end
    if KART.BtnCtCustomColor then KART.BtnCtCustomColor.text:SetText(L.SET_CT_CUSTOM_COLOR) end
    if KART.BtnCtBgColor then KART.BtnCtBgColor.text:SetText(L.SET_CT_BG_COLOR) end
    if KART.BtnCtHealthHigh then KART.BtnCtHealthHigh.text:SetText(L.SET_CT_HEALTH_HIGH) end
    if KART.BtnCtHealthMid then KART.BtnCtHealthMid.text:SetText(L.SET_CT_HEALTH_MID) end
    if KART.BtnCtHealthLow then KART.BtnCtHealthLow.text:SetText(L.SET_CT_HEALTH_LOW) end
    if KART.BtnCtBorderColor then KART.BtnCtBorderColor.text:SetText(L.SET_CT_BORDER_COLOR) end
    if KART.BtnCtAbsorbColor then KART.BtnCtAbsorbColor.text:SetText(L.SET_CT_ABSORB_COLOR) end
    if KART.BtnCtHealAbsorbColor then KART.BtnCtHealAbsorbColor.text:SetText(L.SET_CT_HEAL_ABSORB_COLOR) end
    if KART.BtnCtHealthFill then KART.BtnCtHealthFill.tooltipText = L.DESC_CT_HEALTH_FILL end
    if KART.BtnCtHealthTexture then
        KART.BtnCtHealthTexture.tooltipText = L.DESC_CT_HEALTH_TEXTURE
        RefreshCtTextureBtn()
    end
    if KART.CbCtGradient then
        KART.CbCtGradient.text:SetText(L.SET_CT_GRADIENT)
        KART.CbCtGradient.tooltipText = L.DESC_CT_GRADIENT
    end
    if KART.BtnCtGradientFrom then
        KART.BtnCtGradientFrom.text:SetText(L.SET_CT_GRADIENT_FROM)
        if KART.UI.FitButtonToLabel then KART.UI:FitButtonToLabel(KART.BtnCtGradientFrom) end
    end
    if KART.BtnCtGradientTo then
        KART.BtnCtGradientTo.text:SetText(L.SET_CT_GRADIENT_TO)
        if KART.UI.FitButtonToLabel then KART.UI:FitButtonToLabel(KART.BtnCtGradientTo) end
    end
    if CT.RefreshGradientSwatches then CT.RefreshGradientSwatches() end
    if KART.CbCtRangeFadeOn then KART.CbCtRangeFadeOn.text:SetText(L.SET_CT_RANGE_FADE_ON) end
    if KART.SldCtDeadFade then KART.SldCtDeadFade.title:SetText(L.SET_CT_DEAD_FADE) end
    if KART.SldCtOfflineFade then KART.SldCtOfflineFade.title:SetText(L.SET_CT_OFFLINE_FADE) end
    if KART.CbCtTargetBorder then
        KART.CbCtTargetBorder.text:SetText(L.SET_CT_TARGET_BORDER)
        KART.CbCtTargetBorder.tooltipText = L.DESC_CT_TARGET_BORDER
    end
    if KART.SldCtTargetBorderSize then KART.SldCtTargetBorderSize.title:SetText(L.SET_CT_TARGET_BORDER_SIZE) end
    if KART.BtnCtTargetBorderColor then KART.BtnCtTargetBorderColor.text:SetText(L.SET_CT_TARGET_BORDER_COLOR) end
    if ctPreviewAsLabel then ctPreviewAsLabel:SetText(L.SET_CT_PREVIEW_AS) end
    if KART.CtPreviewStateChips then
        local labels = {
            ok = L.SET_CT_PREVIEW_OK,
            oor = L.SET_CT_PREVIEW_OOR,
            dead = L.SET_CT_PREVIEW_DEAD,
            offline = L.SET_CT_PREVIEW_OFFLINE,
        }
        for _, chip in ipairs(KART.CtPreviewStateChips) do
            if chip.text and labels[chip.stateKey] then
                chip.text:SetText(labels[chip.stateKey])
            end
        end
        if KART.LayoutCtPreviewStateChips then KART.LayoutCtPreviewStateChips() end
    end
    local function relabelText(w, title)
        if not w then return end
        if w.titleFS then w.titleFS:SetText(title) end
        if w.show then w.show.text:SetText(L.SET_CT_TEXT_SHOW) end
        if w.size then w.size.title:SetText(L.SET_CT_TEXT_SIZE) end
        if w.colorBtn then w.colorBtn.text:SetText(L.SET_CT_TEXT_COLOR) end
        if w.classCb then w.classCb.text:SetText(L.SET_CT_TEXT_CLASS) end
        if w.nudgeX then w.nudgeX.title:SetText(L.SET_CT_TEXT_NUDGE_X) end
        if w.nudgeY then w.nudgeY.title:SetText(L.SET_CT_TEXT_NUDGE_Y) end
        if w.refreshOutline then w.refreshOutline() end
        if w.refreshAnchor then w.refreshAnchor() end
    end
    relabelText(KART.CtNameTextWidgets, L.LABEL_CT_NAME_TEXT)
    relabelText(KART.CtHealthTextWidgets, L.LABEL_CT_HEALTH_TEXT)
    local function relabelStripExtra(extra)
        if not extra then return end
        extra.perRow.title:SetText(L.SET_CT_AURA_PER_ROW)
        extra.border.title:SetText(L.SET_CT_AURA_BORDER)
        extra.nudgeX.title:SetText(L.SET_CT_AURA_NUDGE_X)
        extra.nudgeY.title:SetText(L.SET_CT_AURA_NUDGE_Y)
        extra.borderColor.text:SetText(L.SET_CT_AURA_BORDER_COLOR)
        extra.swipe.text:SetText(L.SET_CT_AURA_SWIPE)
        extra.countdown.text:SetText(L.SET_CT_AURA_COUNTDOWN)
        extra.cdSize.title:SetText(L.SET_CT_AURA_COUNTDOWN_SIZE)
        extra.stacks.text:SetText(L.SET_CT_AURA_STACKS)
        extra.stSize.title:SetText(L.SET_CT_AURA_STACKS_SIZE)
    end
    relabelStripExtra(KART.CtDebuffExtra)
    relabelStripExtra(KART.CtBuffExtra)
    if ctAuraChromeNote then ctAuraChromeNote:SetText(L.SET_CT_AURA_DUMMY_CHROME) end
    ctDebuffTitle:SetText(L.LABEL_CT_DEBUFFS)
    ctBuffTitle:SetText(L.LABEL_CT_BUFFS)
    KART.CbCtDebuffShow.text:SetText(L.SET_CT_AURA_SHOW)
    KART.SldCtDebuffMax.title:SetText(L.SET_CT_AURA_MAX)
    KART.SldCtDebuffSize.title:SetText(L.SET_CT_AURA_SIZE)
    KART.SldCtDebuffSpacing.title:SetText(L.SET_CT_AURA_SPACING)
    if KART.CbCtHideLongDuration then
        KART.CbCtHideLongDuration.text:SetText(L.SET_CT_HIDE_LONG_DURATION)
        KART.CbCtHideLongDuration.tooltipText = L.DESC_CT_HIDE_LONG_DURATION
    end
    if KART.CbCtHideFatigue then
        KART.CbCtHideFatigue.text:SetText(L.SET_CT_HIDE_FATIGUE)
        KART.CbCtHideFatigue.tooltipText = L.DESC_CT_HIDE_FATIGUE
    end
    KART.BtnCtDebuffAnchor.tooltipText = L.DESC_CT_AURA_ANCHOR
    KART.BtnCtDebuffGrowth.tooltipText = L.DESC_CT_AURA_GROWTH
    RefreshCtDebuffAnchorBtn()
    RefreshCtDebuffGrowthBtn()
    KART.CbCtBuffShow.text:SetText(L.SET_CT_AURA_SHOW)
    KART.SldCtBuffMax.title:SetText(L.SET_CT_AURA_MAX)
    KART.SldCtBuffSize.title:SetText(L.SET_CT_AURA_SIZE)
    KART.SldCtBuffSpacing.title:SetText(L.SET_CT_AURA_SPACING)
    KART.BtnCtBuffAnchor.tooltipText = L.DESC_CT_AURA_ANCHOR
    KART.BtnCtBuffGrowth.tooltipText = L.DESC_CT_AURA_GROWTH
    RefreshCtBuffAnchorBtn()
    RefreshCtBuffGrowthBtn()
    if ctTauntTitle then ctTauntTitle:SetText(L.LABEL_CT_TAUNT) end
    if ctTauntChanTitle then ctTauntChanTitle:SetText(L.SET_CT_TAUNT_CHANNELS) end
    if ctTauntMsgLabel then ctTauntMsgLabel:SetText(L.SET_CT_TAUNT_MESSAGE) end
    if ctTauntPlace then ctTauntPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS) end
    if ctAskTitle then ctAskTitle:SetText(L.LABEL_CT_TAUNT_ASK) end
    if ctAskMsgLabel then ctAskMsgLabel:SetText(L.SET_CT_TAUNT_ASK) end
    if ctAskPlace then ctAskPlace:SetText(L.SET_CT_TAUNT_PLACEHOLDERS) end
    if KART.CbCtTauntAnnounce then
        KART.CbCtTauntAnnounce.text:SetText(L.SET_CT_TAUNT_ANNOUNCE)
        KART.CbCtTauntAnnounce.tooltipText = L.DESC_CT_TAUNT_ANNOUNCE
    end
    if KART.CbCtTauntOnlyGroup then
        KART.CbCtTauntOnlyGroup.text:SetText(L.SET_CT_TAUNT_ONLY_GROUP)
        KART.CbCtTauntOnlyGroup.tooltipText = L.DESC_CT_TAUNT_ONLY_GROUP
    end
    if KART.CbCtTauntOnlyDungeon then
        KART.CbCtTauntOnlyDungeon.text:SetText(L.SET_CT_TAUNT_ONLY_DUNGEON)
        KART.CbCtTauntOnlyDungeon.tooltipText = L.DESC_CT_TAUNT_ONLY_DUNGEON
    end
    if KART.CbCtTauntOnlyRaid then
        KART.CbCtTauntOnlyRaid.text:SetText(L.SET_CT_TAUNT_ONLY_RAID)
        KART.CbCtTauntOnlyRaid.tooltipText = L.DESC_CT_TAUNT_ONLY_RAID
    end
    if KART.CbCtTauntWhisper then KART.CbCtTauntWhisper.text:SetText(L.SET_CT_TAUNT_WHISPER) end
    if KART.CbCtTauntGroup then KART.CbCtTauntGroup.text:SetText(L.SET_CT_TAUNT_GROUP) end
    if KART.CbCtTauntRW then KART.CbCtTauntRW.text:SetText(L.SET_CT_TAUNT_RW) end
    if KART.CbCtTauntSay then KART.CbCtTauntSay.text:SetText(L.SET_CT_TAUNT_SAY) end
    if KART.CbCtTauntYell then KART.CbCtTauntYell.text:SetText(L.SET_CT_TAUNT_YELL) end
    if KART.LayoutTauntChannelChips then KART.LayoutTauntChannelChips() end
    if KART.CbCtTauntButton then
        KART.CbCtTauntButton.text:SetText(L.SET_CT_TAUNT_BUTTON)
        KART.CbCtTauntButton.tooltipText = L.DESC_CT_TAUNT_BUTTON
    end
    if KART.CbCtTauntBtnLock then
        KART.CbCtTauntBtnLock.text:SetText(L.SET_CT_TAUNT_BTN_LOCK)
        KART.CbCtTauntBtnLock.tooltipText = L.DESC_CT_TAUNT_BTN_LOCK
    end
    if KART.CbCtTauntBtnGroup then KART.CbCtTauntBtnGroup.text:SetText(L.SET_CT_TAUNT_BTN_GROUP) end
    if KART.CbCtTauntBtnRaid then
        KART.CbCtTauntBtnRaid.text:SetText(L.SET_CT_TAUNT_BTN_RAID)
        KART.CbCtTauntBtnRaid.tooltipText = L.DESC_CT_TAUNT_BTN_RAID
    end
    if KART.SldCtTauntSize then KART.SldCtTauntSize.title:SetText(L.SET_CT_TAUNT_SIZE) end
    if KART.BtnCtTauntMacro then
        KART.BtnCtTauntMacro.text:SetText(L.BTN_CT_TAUNT_MACRO)
        KART.BtnCtTauntMacro.tooltipText = L.DESC_CT_TAUNT_MACRO
    end
    if CT.RefreshAskButton then CT.RefreshAskButton() end
    if KART.CtFlyoutTabButtons then
        KART.CtFlyoutTabButtons[1].text:SetText(L.TAB_CT_LOOK)
        KART.CtFlyoutTabButtons[2].text:SetText(L.TAB_CT_TEXT)
        KART.CtFlyoutTabButtons[3].text:SetText(L.TAB_CT_AURAS)
    end
end)

function CT.SyncRootWidgets()
    local settingsMap = {}
    if KART.CbCtModuleEnabled then settingsMap[KART.CbCtModuleEnabled] = "ctModuleEnabled" end
    KART.ApplySettingsMap(settingsMap)
end
