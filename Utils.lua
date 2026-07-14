local addonName, KART = ...

local LSM = LibStub("LibSharedMedia-3.0", true)
KART.L = KART.L or {}
KART.EditBoxes = {}
KART.DynamicLabels = {}
KART.SliderThumbs = {}
KART.CheckVisuals = {}
KART.ButtonTexts = {}
KART.CloseButtonTexts = {} -- "×" FontStrings on close buttons that aren't already covered by a per-frame UpdateStyles font update

-- Standardeinstellungen
KART.Defaults = {
    inviteKeywords = "inv;+;invite",
    inviteViaGuildChat = false,
    promoteNames = "",
    showRaidleadBar = false,
    lockRaidleadBar = false,
    autoHideRaidleadBar = false,
    pullTimerDuration = 10,
    bcModuleEnabled = false,
    showBuffCheck = false,
    buffCheckAlpha = 90,
    bcCombatDelay = 2,
    grayOffline = true,
    minimap = {},
    showMinimapIcon = true,
    autoConvertToRaid = false,
    titleFontSize = 12,
    menuFontSize = 11,
    contentFontSize = 12,
    bgAlpha = 85,
    fontName = "Friz Quadrata",
    accentR = 0, accentG = 60, accentB = 100,
    bgR = 10, bgG = 10, bgB = 10,
    language = "Auto",
    lcModuleEnabled = false,
    lcAutoPass = true,
    lcVoteSeconds = 20,
    lcButtonLabels = "BIS;Upgrade;Offspec;Sonstiges;Pass",
    lcCouncilMembers = "",
    wuModuleEnabled = false,
    wuImportText = "",
    dtModuleEnabled = false,
    lcVotePopupPos = false,
    lcCouncilPanelPos = false,
    lcHistoryWindowPos = false,
    lcMinQuality = 4,
}

function KART.TrimString(s)
    return s:match("^%s*(.-)%s*$")
end

function KART.SplitString(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

function KART.HasGroupPermissions()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function KART.GetFontPath(name)
    if LSM then
        return LSM:Fetch("font", name)
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- UI Factory: Modern Button
function KART.CreateModernButton(parent, text, tooltipText)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(130, 25)
    b:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    table.insert(KART.ButtonTexts, b.text)

    b:SetScript("OnEnter", function(self) 
        self:SetBackdropColor(0.2, 0.2, 0.2, 1)
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) 
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        GameTooltip:Hide()
    end)
    return b
end

-- Weitere UI-Hilfsfunktionen (Slider/Checkbox) hier implementieren...
function KART.CreateSettingsCheckbox(parent, name, labelText, settingKey, yOffset, callback, tooltipText)
    local cb = CreateFrame("CheckButton", name, parent, "BackdropTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", 20, yOffset)
    
    cb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(0, 0, 0, 0.5)
    cb:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.text:SetText(labelText)
    table.insert(KART.DynamicLabels, cb.text)

    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\WHITE8X8")
    check:SetSize(12, 12)
    check:SetPoint("CENTER")
    cb:SetCheckedTexture(check)
    table.insert(KART.CheckVisuals, check)

    cb:SetScript("OnClick", function(self)
        KART_Settings[settingKey] = self:GetChecked()
        if callback then callback() end
    end)

    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

function KART.CreateSettingsSlider(parent, labelText, minV, maxV, settingKey, yOffset, name, tooltipText)
    local s = CreateFrame("Slider", name, parent, "BackdropTemplate")
    s:SetSize(180, 14)
    s:SetPoint("TOPLEFT", 20, yOffset - 16) -- 16px Platz für das Label oben
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    s:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0, 0, 0, 0.5)
    s:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    s.title:SetText(labelText)
    table.insert(KART.DynamicLabels, s.title)

    s.valueText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 4)
    
    local thumb = s:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 14)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    s:SetThumbTexture(thumb)
    table.insert(KART.SliderThumbs, thumb)

    s:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value)
        KART_Settings[settingKey] = val
        self.valueText:SetText(val)
        if KART.UpdateStyles then KART.UpdateStyles() end
    end)

    if tooltipText then
        s:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return s
end

function KART.UpdateMinimapButton()
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then
        if KART_Settings.showMinimapIcon then
            dbIcon:Show("KeineAhnungRaidTools")
        else
            dbIcon:Hide("KeineAhnungRaidTools")
        end
    end
end

function KART.OpenColorPicker(rKey, gKey, bKey)
    local startR = (KART_Settings[rKey] or 100) / 100
    local startG = (KART_Settings[gKey] or 100) / 100
    local startB = (KART_Settings[bKey] or 100) / 100
    
    local function onUpdate()
        local r, g, b
        if ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        if not r then return end
        KART_Settings[rKey] = math.floor(r * 100)
        KART_Settings[gKey] = math.floor(g * 100)
        KART_Settings[bKey] = math.floor(b * 100)
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    local function onCancel()
        KART_Settings[rKey] = math.floor(startR * 100)
        KART_Settings[gKey] = math.floor(startG * 100)
        KART_Settings[bKey] = math.floor(startB * 100)
        if KART.UpdateStyles then KART.UpdateStyles() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startR, g = startG, b = startB,
            swatchFunc = onUpdate,
            cancelFunc = onCancel,
        })
    end
end

-- Funktion zum Zählen fehlender Verzauberungen und leerer Sockelplätze (Retail)
function KART.CountMissingGear()
    local missingEnchants = {}
    local missingGems = {}

    -- Slots mit Enchant: Head(1), Shoulders(3), Chest(5), Legs(7), Boots(8), Rings(11,12), Weapon(16)
    local enchantableSlots = {1, 3, 5, 7, 8, 11, 12, 16}
    for _, slot in ipairs(enchantableSlots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local enchant = link:match("item:%d+:(%d*):")
            if not enchant or enchant == "" or enchant == "0" then 
                table.insert(missingEnchants, tostring(slot)) 
            end
        end
    end
    
    for slot = 1, 17 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local stats = C_Item.GetItemStats(link)
            if stats then
                for statKey in pairs(stats) do
                    if statKey:match("^EMPTY_SOCKET_") then
                        table.insert(missingGems, tostring(slot))
                        break
                    end
                end
            end
        end
    end
    
    local eStr = table.concat(missingEnchants, ",")
    local gStr = table.concat(missingGems, ",")
    if eStr == "" then eStr = "0" end
    if gStr == "" then gStr = "0" end
    return eStr, gStr
end

-- Helper: Scrollbars bereinigen (verhindert Code-Duplizierung)
function KART.StripScrollbarTextures(scrollFrame)
    local sb = _G[scrollFrame:GetName().."ScrollBar"]
    if not sb then return nil end
    local up, down = _G[sb:GetName().."ScrollUpButton"], _G[sb:GetName().."ScrollDownButton"]
    for _, btn in ipairs({up, down}) do
        if btn then
            btn:Hide() btn:SetSize(1, 1)
            for i = 1, btn:GetNumRegions() do
                local region = select(i, btn:GetRegions())
                if region and region:IsObjectType("Texture") then region:SetTexture(nil) end
            end
        end
    end
    for i = 1, sb:GetNumRegions() do
        local region = select(i, sb:GetRegions())
        if region and region:IsObjectType("Texture") then region:SetTexture(nil) end
    end
    local thumb = sb:GetThumbTexture()
    if thumb then thumb:SetTexture("Interface\\Buttons\\WHITE8X8") end
    return thumb
end

-- Adds a short fade-in on every OnShow, so a window appearing feels less abrupt than an instant
-- pop-in. HookScript rather than replacing OnShow so it never interferes with a frame's own show
-- logic, and works no matter which of the frame's (possibly many) callers triggers the Show().
function KART.AddShowFade(frame, duration)
    local ag = frame:CreateAnimationGroup()
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(duration or 0.15)
    alpha:SetSmoothing("OUT")
    frame:HookScript("OnShow", function()
        ag:Stop()
        ag:Play()
    end)
end

-- Adds a subtle vertical gradient overlay on top of a frame's flat backdrop fill, so panels read
-- as less flat without abandoning the existing color-picker-driven backdrop system: the backdrop
-- itself stays the color/alpha source of truth (and remains a safe solid-color fallback everywhere
-- else), this only layers a soft brightness falloff on top of whatever color that resolves to.
-- Sits one sublevel above the backdrop's own BACKGROUND fill so it never covers the BORDER-layer
-- edge texture. Returns the texture so the caller can update its color via SetGradientOverlayColor
-- whenever KART.UpdateStyles() recomputes the frame's backdrop color.
function KART.CreateGradientOverlay(frame)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    return tex
end

-- SetGradient's exact signature has changed across WoW API versions, and this can't be tested
-- outside a live client — pcall so a mismatch just skips the visual flourish instead of breaking
-- the rest of KART.UpdateStyles() (fonts, colors, etc.) for every other frame in the same call.
function KART.SetGradientOverlayColor(tex, r, g, b, alpha)
    if not tex then return end
    local top    = CreateColor(math.min(r + 0.06, 1), math.min(g + 0.06, 1), math.min(b + 0.06, 1), alpha)
    local bottom = CreateColor(math.max(r - 0.06, 0), math.max(g - 0.06, 0), math.max(b - 0.06, 0), alpha)
    pcall(tex.SetGradient, tex, "VERTICAL", top, bottom)
end
