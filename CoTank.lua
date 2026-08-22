local addonName, KART = ...
KART.CT = KART.CT or {}
local CT = KART.CT

-- ===== Instance filter --------------------------------------------------------------------
local INSTANCE_OK = { party = true, raid = true }

-- ===== Group iteration --------------------------------------------------------------------
local function GroupUnits()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            out[#out + 1] = "raid" .. i
        end
    elseif IsInGroup() then
        out[#out + 1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            out[#out + 1] = "party" .. i
        end
    end
    return out
end

-- ===== Co-tank picker ---------------------------------------------------------------------
function CT.PickCoTank()
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "TANK"
            and not UnitIsUnit(unit, "player") then
            return unit
        end
    end
end

-- ===== Visibility -------------------------------------------------------------------------
function CT.Invented()
    local ct = KART_Settings and KART_Settings.ct
    return ct and ct.testMode and true or false
end

function CT.ShouldShow()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return false end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then return false end
    local ct = s.ct
    if ct and ct.testMode then return true end
    if ct and ct.locked == false and not INSTANCE_OK[instanceType] then
        return true
    end
    if UnitGroupRolesAssigned("player") ~= "TANK" then return false end
    if ct and ct.onlyInGroup ~= false and not IsInGroup() then return false end
    if (not ct or ct.onlyInInstance ~= false) and not INSTANCE_OK[instanceType] then
        return false
    end
    return CT.PickCoTank() ~= nil
end

-- ===== Snapshot ---------------------------------------------------------------------------
function CT.BlankSnapshot(snap)
    snap.name = nil
    snap.classFile = nil
    snap.health = 0
    snap.healthMax = 0
    snap.absorb = 0
    snap.healAbsorb = 0
    snap.dead = false
    snap.offline = false
    snap.inRange = true
    return snap
end

function CT.SafeTruthy(value, fallback)
    if _G.issecretvalue and issecretvalue(value) then
        return fallback
    end
    return value and true or false
end

function CT.IsSecret(value)
    return _G.issecretvalue and issecretvalue(value) == true
end

function CT.FillLiveSnapshot(unit, snap)
    snap.name = UnitName(unit)
    local _, classFile = UnitClass(unit)
    snap.classFile = classFile
    snap.health = UnitHealth(unit)
    snap.healthMax = UnitHealthMax(unit)
    snap.absorb = UnitGetTotalAbsorbs(unit)
    snap.healAbsorb = UnitGetTotalHealAbsorbs(unit)
    snap.dead = UnitIsDeadOrGhost(unit) and true or false
    snap.offline = not UnitIsConnected(unit)
    snap.inRange = CT.ReadInRange(unit)
    return snap
end

-- CompactUnitFrame: out of range only when the client checked and the unit is not in it.
-- Unchecked or secret returns count as in range.
function CT.ReadInRange(unit)
    local inRange, checkedRange = UnitInRange(unit)
    if CT.SafeTruthy(checkedRange, false) and not CT.SafeTruthy(inRange, true) then
        return false
    end
    return true
end

function CT.FillTestSnapshot(snap)
    CT.BlankSnapshot(snap)
    snap.name = "Testtank"
    snap.classFile = "DEATHKNIGHT"
    snap.healthMax = 50000
    snap.health = 40000
    snap.absorb = 3000
    snap.inRange = true
    snap.dead = false
    return snap
end

-- ===== Secure unit attribute -----------------------------------------------------------
function CT.ApplySecureUnit(frame, unit)
    if InCombatLockdown() then
        CT.pendingUnit = unit
        return "deferred"
    end
    CT.pendingUnit = nil
    frame:SetAttribute("unit", unit)
    return "applied"
end

function CT.OnRegenEnabled()
    if InCombatLockdown() then return end
    if CT.row then
        CT.row:SetAttribute("type1", "target")
    end
    if CT.pendingUnit and CT.row then
        CT.ApplySecureUnit(CT.row, CT.pendingUnit)
    end
    if CT.pendingUnparent and CT.row then
        CT.row:SetParent(UIParent)
        CT.pendingUnparent = nil
    end
    if CT.pendingHost then
        CT.pendingHost = nil
        CT.HostPreview()
    elseif CT.pendingRelease then
        CT.pendingRelease = nil
        CT.ReleasePreview()
    end
    CT.Refresh()
end

-- ===== Row chrome -------------------------------------------------------------------------
local CT_LAYOUT_DEFAULTS = {
    point = "CENTER", relativePoint = "CENTER", x = 0, y = 200,
    width = 220, height = 36, scale = 1,
    absorbShow = true, healAbsorbShow = true,
    nameMaxLength = 12, healthText = "both", healthColor = "class",
    healthCustom = { r = 0.2, g = 0.8, b = 0.2 },
    healthHigh = { r = 0.2, g = 0.8, b = 0.2 },
    healthMid  = { r = 0.9, g = 0.8, b = 0.2 },
    healthLow  = { r = 0.8, g = 0.2, b = 0.2 },
    healthFill = "right",
    healthAlpha = 1, trackAlpha = 0.4,
    bgColor = { r = 0.06, g = 0.07, b = 0.08 },
    bgAlpha = 0.92,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0 },
    absorbColor = { r = 0.4, g = 0.85, b = 0.85 },
    absorbAlpha = 0.7,
    healAbsorbColor = { r = 0.6, g = 0.2, b = 0.8 },
    healAbsorbAlpha = 0.7,
    rangeFade = true,
    rangeAlpha = 0.4,
    deadFade = 0.35,
    offlineFade = 0.35,
}

local NAME_STYLE_DEFAULTS = {
    show = true, size = 0, classColor = false, outline = "OUTLINE",
    anchor = "LEFT", x = 6, y = 0,
    color = { r = 1, g = 1, b = 1 },
}
local HEALTH_STYLE_DEFAULTS = {
    show = true, size = 0, classColor = false, outline = "OUTLINE",
    anchor = "RIGHT", x = -6, y = 0,
    color = { r = 1, g = 1, b = 1 },
}
local TARGET_BORDER_DEFAULTS = {
    show = false, size = 2,
    color = { r = 1, g = 0.85, b = 0.2 },
}

local function ColorRGB(c, fallback)
    c = c or fallback
    if not c then return 1, 1, 1 end
    return c.r or 1, c.g or 1, c.b or 1
end

local function Nested(ct, key, defaults)
    local t = ct and ct[key]
    if type(t) ~= "table" then return defaults end
    return t
end

local function CtSettings()
    local s = KART_Settings
    if not s or not s.ct then return nil end
    return s.ct
end

local function CtOrDefault(key)
    local ct = CtSettings()
    if ct and ct[key] ~= nil then return ct[key] end
    return CT_LAYOUT_DEFAULTS[key]
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function TruncateName(name, maxLen)
    if not name then return "" end
    maxLen = maxLen or 12
    if #name <= maxLen then return name end
    return name:sub(1, maxLen)
end

local function FormatHealthText(snap, ct)
    if CT.IsSecret(snap.health) or CT.IsSecret(snap.healthMax) then
        return ""
    end
    local health = snap.health or 0
    local max = snap.healthMax or 0
    local pct = max > 0 and math.floor(health / max * 100 + 0.5) or 0
    local mode = (ct and ct.healthText) or "both"
    if mode == "percent" then
        return pct .. "%"
    elseif mode == "current" then
        return tostring(math.floor(health + 0.5))
    elseif mode == "deficit" then
        local missing = math.max(0, math.floor((max - health) + 0.5))
        return tostring(missing)
    end
    return tostring(math.floor(health + 0.5)) .. " / " .. pct .. "%"
end

CT.FormatHealthText = FormatHealthText

local function HealthBarColor(snap, ct)
    local mode = (ct and ct.healthColor) or "class"
    if mode == "health" and (CT.IsSecret(snap.health) or CT.IsSecret(snap.healthMax)) then
        mode = "class"
    end
    if mode == "class" then
        local c = RAID_CLASS_COLORS and snap.classFile and RAID_CLASS_COLORS[snap.classFile]
        if c then return c.r, c.g, c.b end
        return 0.5, 0.5, 0.5
    elseif mode == "custom" then
        local c = (ct and ct.healthCustom) or CT_LAYOUT_DEFAULTS.healthCustom
        return c.r, c.g, c.b
    end
    local health = snap.health or 0
    local max = snap.healthMax or 1
    if max <= 0 then max = 1 end
    local pct = health / max
    local low = (ct and ct.healthLow) or CT_LAYOUT_DEFAULTS.healthLow
    local mid = (ct and ct.healthMid) or CT_LAYOUT_DEFAULTS.healthMid
    local high = (ct and ct.healthHigh) or CT_LAYOUT_DEFAULTS.healthHigh
    if pct >= 0.5 then
        local t = (pct - 0.5) * 2
        return Lerp(mid.r, high.r, t), Lerp(mid.g, high.g, t), Lerp(mid.b, high.b, t)
    end
    local t = pct * 2
    return Lerp(low.r, mid.r, t), Lerp(low.g, mid.g, t), Lerp(low.b, mid.b, t)
end

local function InitStatusBarFill(bar)
    local tex = bar:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(tex)
end

local function AddEdgeSet(row, key, layer, texParent)
    local edges = {}
    texParent = texParent or row
    local function edge(p1, p2, w, h)
        local tex = texParent:CreateTexture(nil, layer)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:SetPoint(p1, row, p1, 0, 0)
        tex:SetPoint(p2, row, p2, 0, 0)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
        edges[#edges + 1] = { tex = tex, p1 = p1, p2 = p2, isWidth = w ~= nil }
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    row[key] = edges
end

local function StyleEdgeSet(edges, size, r, g, b, shown)
    if not edges then return end
    if size < 0 then size = 0 end
    for _, e in ipairs(edges) do
        e.tex:SetColorTexture(r, g, b, 1)
        if e.isWidth then e.tex:SetWidth(size) else e.tex:SetHeight(size) end
        if shown and size > 0 then e.tex:Show() else e.tex:Hide() end
    end
end

local function ApplyBarFill(bar, fill)
    if not bar then return end
    if fill == "up" or fill == "down" then
        if bar.SetOrientation then bar:SetOrientation("VERTICAL") end
        if bar.SetReverseFill then bar:SetReverseFill(fill == "down") end
    else
        if bar.SetOrientation then bar:SetOrientation("HORIZONTAL") end
        if bar.SetReverseFill then bar:SetReverseFill(fill == "left") end
    end
end

local FONT_PATH = "Fonts\\FRIZQT__.TTF"

local function ApplyLabel(fs, row, style, defaults, snap)
    if not fs then return end
    style = style or defaults
    if style.show == false then
        fs:Hide()
        return
    end
    fs:Show()
    local size = style.size or 0
    if size <= 0 then size = 12 end
    local outline = style.outline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    if fs.SetFont then fs:SetFont(FONT_PATH, size, outline) end
    local r, g, b
    if style.classColor and snap and snap.classFile then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[snap.classFile]
        if c then r, g, b = c.r, c.g, c.b end
    end
    if not r then
        r, g, b = ColorRGB(style.color, defaults.color)
    end
    if fs.SetTextColor then fs:SetTextColor(r, g, b, 1) end
    local anchor = style.anchor or defaults.anchor or "LEFT"
    fs:ClearAllPoints()
    fs:SetPoint(anchor, row, anchor, style.x or defaults.x or 0, style.y or defaults.y or 0)
end

local function BuildRowChrome(row)
    if row.SetClipsChildren then row:SetClipsChildren(false) end

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.07, 0.08, 0.92)
    row.bg = bg

    AddEdgeSet(row, "borderEdges", "BORDER")

    local absorbBar = CreateFrame("StatusBar", nil, row)
    absorbBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    absorbBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    InitStatusBarFill(absorbBar)
    row.absorbBar = absorbBar

    local health = CreateFrame("StatusBar", nil, row)
    health:SetAllPoints(absorbBar)
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    InitStatusBarFill(health)
    row.health = health
    row.healthBg = healthBg
    if absorbBar.GetFrameLevel and health.SetFrameLevel then
        health:SetFrameLevel((absorbBar:GetFrameLevel() or 1) + 1)
    end

    local healFill = health:CreateTexture(nil, "ARTWORK", nil, 2)
    healFill:Hide()
    row.healAbsorbFill = healFill

    local overlay = CreateFrame("Frame", nil, row)
    overlay:SetAllPoints()
    if overlay.SetFrameLevel then
        overlay:SetFrameLevel((health:GetFrameLevel() or 1) + 5)
    end
    if overlay.SetClipsChildren then overlay:SetClipsChildren(false) end
    row.overlay = overlay

    AddEdgeSet(row, "targetEdges", "OVERLAY", overlay)

    if row.SetClampedToScreen then row:SetClampedToScreen(true) end

    local nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.nameText = nameText

    local healthText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.healthText = healthText
end

function CT.EnsureRow()
    if CT.row and CT.row.GetWidth then return CT.row end
    CT.row = nil

    local row = CreateFrame("Button", "KART_CoTankFrame", UIParent, "SecureUnitButtonTemplate")
    row:RegisterForClicks("LeftButtonUp")
    if not InCombatLockdown() then
        row:SetAttribute("type1", "target")
    end
    BuildRowChrome(row)

    row:SetMovable(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        local ct = CtSettings()
        if ct and not ct.locked and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    row:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        local s = KART_Settings
        if not s then return end
        s.ct = s.ct or {}
        s.ct.point = point
        s.ct.relativePoint = relativePoint
        s.ct.x = xOfs
        s.ct.y = yOfs
    end)

    row:SetScript("OnEvent", function(_, event, eventUnit)
        CT.OnUnitEvent(event, eventUnit)
    end)

    CT.row = row
    return row
end

function CT.EnsurePreviewRow()
    if CT.previewRow and CT.previewRow.GetWidth then return CT.previewRow end
    local slot = KART.CtPreviewSlot
    local row = CreateFrame("Frame", "KART_CoTankPreview", slot or UIParent)
    if row.EnableMouse then row:EnableMouse(false) end
    BuildRowChrome(row)
    CT.previewRow = row
    return row
end

-- ===== Aura strips -------------------------------------------------------------------------
local STRIP_DEFAULTS = {
    debuffs = { show = true, max = 8, size = 22, spacing = 1, perRow = 8,
                anchor = "TOPLEFT", growth = "right", x = 0, y = 4,
                borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                swipe = true, countdown = true, countdownSize = 0,
                stacks = true, stacksSize = 0 },
    buffs   = { show = true, max = 6, size = 18, spacing = 1, perRow = 6,
                anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4,
                borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                swipe = true, countdown = true, countdownSize = 0,
                stacks = true, stacksSize = 0 },
}

local AURA_ENGINE_AVAILABLE

local function StripCfg(kind)
    local ct = CtSettings() or {}
    local cfg = ct[kind]
    local def = STRIP_DEFAULTS[kind]
    if not cfg then return def end
    local out = {}
    for k, v in pairs(def) do
        if cfg[k] ~= nil then out[k] = cfg[k] else out[k] = v end
    end
    for k, v in pairs(cfg) do
        if out[k] == nil then out[k] = v end
    end
    return out
end

function CT.AuraEngineAvailable()
    if AURA_ENGINE_AVAILABLE ~= nil then return AURA_ENGINE_AVAILABLE end
    -- Do not instantiate Blizzard XML templates: their OnLoad is forbidden to addons
    -- (BuffFrameTemplates.xml). The widget type itself is legal without a template.
    local ok, frame = pcall(CreateFrame, "AuraContainer", nil, UIParent)
    local live = ok and frame and frame.GetObjectType
        and frame:GetObjectType() == "AuraContainer"
    if frame and frame.Hide then pcall(frame.Hide, frame) end
    AURA_ENGINE_AVAILABLE = live and true or false
    return AURA_ENGINE_AVAILABLE
end

function CT.RefreshAuraEngineNote()
    local fs = KART.CtAuraEngineNote
    if not fs then return end
    if CT.AuraEngineAvailable() then
        fs:Hide()
    else
        local L = KART.L
        if fs.SetText then fs:SetText((L and L.SET_CT_AURA_ENGINE) or "") end
        fs:Show()
    end
end

local function UseDummyStrips()
    return CT.Invented()
end

local function GrowthOffset(cfg, index)
    local size = cfg.size or 18
    local spacing = cfg.spacing or 0
    local perRow = cfg.perRow or cfg.max or 8
    if perRow < 1 then perRow = 1 end
    local col = (index - 1) % perRow
    local wrap = math.floor((index - 1) / perRow)
    local step = size + spacing
    local growth = cfg.growth or "right"
    if growth == "left" then return -col * step, -wrap * step end
    if growth == "up" then return wrap * step, col * step end
    if growth == "down" then return wrap * step, -col * step end
    return col * step, -wrap * step
end

local function AuraGroupLayout(cfg)
    local layout = {
        anchorPoint = cfg.anchor,
        iconWidth = cfg.size,
        iconHeight = cfg.size,
        spacing = cfg.spacing,
        wrapAfter = cfg.perRow,
    }
    if cfg.growth == "left" then
        layout.horizontalDirection = "RightToLeft"
    elseif cfg.growth == "up" then
        layout.verticalDirection = "Up"
    elseif cfg.growth == "down" then
        layout.verticalDirection = "Down"
    else
        layout.horizontalDirection = "LeftToRight"
    end
    return layout
end

local function PlaceStrip(strip, row, cfg)
    strip:ClearAllPoints()
    strip:SetPoint(cfg.anchor, row, cfg.anchor, cfg.x, cfg.y)
end

local function StripHost(row)
    return row.overlay or row
end

local function StripPixelSize(cfg)
    local max = cfg.max or 0
    if max < 1 then return 0, 0 end
    local size = cfg.size or 18
    local spacing = cfg.spacing or 0
    local perRow = cfg.perRow or max
    if perRow < 1 then perRow = 1 end
    local growth = cfg.growth or "right"
    local cols, rows
    if growth == "up" or growth == "down" then
        rows = math.min(max, perRow)
        cols = math.ceil(max / perRow)
    else
        cols = math.min(max, perRow)
        rows = math.ceil(max / perRow)
    end
    local w = cols * size + math.max(0, cols - 1) * spacing
    local h = rows * size + math.max(0, rows - 1) * spacing
    return w, h
end

local function BuildDummyStrip(row, key, cfg, r, g, b)
    local host = StripHost(row)
    local strip = row[key]
    if not strip or strip.isAuraEngine or (strip.GetParent and strip:GetParent() ~= host) then
        if strip then strip:Hide() end
        strip = CreateFrame("Frame", nil, host)
        row[key] = strip
    end
    strip.isAuraEngine = nil
    strip.dummyIcons = strip.dummyIcons or {}
    if host.SetClipsChildren then host:SetClipsChildren(false) end
    if strip.SetClipsChildren then strip:SetClipsChildren(false) end

    if cfg.show == false then
        strip:Hide()
        return strip
    end

    local w, h = StripPixelSize(cfg)
    strip:SetSize(w, h)
    PlaceStrip(strip, row, cfg)
    strip:Show()

    local max = cfg.max or 0
    if max < 0 then max = 0 end
    local borderSize = cfg.borderSize or 1
    if borderSize < 0 then borderSize = 0 end
    local br, bgc, bb = ColorRGB(cfg.borderColor, { r = 0, g = 0, b = 0 })
    for i = 1, max do
        local icon = strip.dummyIcons[i]
        if not icon then
            icon = CreateFrame("Frame", nil, strip)
            local border = icon:CreateTexture(nil, "BACKGROUND")
            border:SetAllPoints()
            icon.border = border
            local tex = icon:CreateTexture(nil, "ARTWORK")
            icon.tex = tex
            strip.dummyIcons[i] = icon
        end
        icon:SetSize(cfg.size, cfg.size)
        local ox, oy = GrowthOffset(cfg, i)
        icon:ClearAllPoints()
        icon:SetPoint(cfg.anchor, strip, cfg.anchor, ox, oy)
        icon.border:SetColorTexture(br, bgc, bb, borderSize > 0 and 1 or 0)
        icon.tex:ClearAllPoints()
        icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
        icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
        icon.tex:SetColorTexture(r, g, b, 0.85)

        if not icon.cd then
            icon.cd = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            icon.cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
        end
        if cfg.countdown ~= false then
            local cdSize = cfg.countdownSize or 0
            if cdSize <= 0 then cdSize = math.max(8, math.floor((cfg.size or 18) * 0.45)) end
            if icon.cd.SetFont then icon.cd:SetFont(FONT_PATH, cdSize, "OUTLINE") end
            icon.cd:SetText("12")
            icon.cd:Show()
        else
            icon.cd:Hide()
        end

        if not icon.stack then
            icon.stack = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            icon.stack:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        end
        if cfg.stacks ~= false then
            local stSize = cfg.stacksSize or 0
            if stSize <= 0 then stSize = math.max(8, math.floor((cfg.size or 18) * 0.4)) end
            if icon.stack.SetFont then icon.stack:SetFont(FONT_PATH, stSize, "OUTLINE") end
            icon.stack:SetText("3")
            icon.stack:Show()
        else
            icon.stack:Hide()
        end

        icon:Show()
    end
    for i = max + 1, #strip.dummyIcons do
        strip.dummyIcons[i]:Hide()
    end
    return strip
end

local function BuildLiveStrip(row, key, cfg, filter)
    local host = StripHost(row)
    local strip = row[key]
    if not strip or not strip.isAuraEngine or (strip.GetParent and strip:GetParent() ~= host) then
        if strip then strip:Hide() end
        local ok, frame = pcall(CreateFrame, "AuraContainer", nil, host)
        if not ok or not frame then return end
        strip = frame
        strip.isAuraEngine = true
        row[key] = strip
    end

    if cfg.show == false then
        strip:Hide()
        if strip.SetEnabled then pcall(strip.SetEnabled, strip, false) end
        return strip
    end

    PlaceStrip(strip, row, cfg)
    if strip.SetEnabled then pcall(strip.SetEnabled, strip, true) end
    strip:Show()

    if not strip._auraGroupAdded then
        local added = pcall(function()
            strip:AddAuraGroup("main", filter, {
                maxFrameCount = cfg.max,
                layout = AuraGroupLayout(cfg),
            })
        end)
        if added then strip._auraGroupAdded = true end
    end

    pcall(function()
        if strip.SetAuraGroupMaxFrameCount then
            strip:SetAuraGroupMaxFrameCount("main", cfg.max)
        end
        if strip.SetAuraGroupLayout then
            strip:SetAuraGroupLayout("main", AuraGroupLayout(cfg))
        end
    end)

    local unit = CT.PickCoTank()
    if unit and strip.SetUnit then
        pcall(function() strip:SetUnit(unit) end)
    end
    return strip
end

function CT.BuildStrips(row, dummy)
    if not row then return end
    if dummy == nil then dummy = UseDummyStrips() end
    local debuffCfg = StripCfg("debuffs")
    local buffCfg = StripCfg("buffs")
    if dummy then
        BuildDummyStrip(row, "debuffs", debuffCfg, 0.85, 0.25, 0.25)
        BuildDummyStrip(row, "buffs", buffCfg, 0.25, 0.75, 0.35)
    elseif CT.AuraEngineAvailable() then
        BuildLiveStrip(row, "debuffs", debuffCfg, "HARMFUL")
        BuildLiveStrip(row, "buffs", buffCfg, "HELPFUL")
    else
        local function hide(key)
            local strip = row[key]
            if not strip then return end
            if strip.dummyIcons then
                for i = 1, #strip.dummyIcons do
                    strip.dummyIcons[i]:Hide()
                end
            end
            strip:Hide()
        end
        hide("debuffs")
        hide("buffs")
    end
end

function CT.SyncStripUnits(row, unit)
    if not row then return end
    for _, key in ipairs({ "debuffs", "buffs" }) do
        local strip = row[key]
        if strip and strip.isAuraEngine and strip.SetUnit then
            pcall(function() strip:SetUnit(unit) end)
        end
    end
end

-- ===== Layout -----------------------------------------------------------------------------
local function LayoutRow(row, preview)
    local ct = CtSettings()
    if not ct then return end

    row:SetSize(ct.width or CtOrDefault("width"), ct.height or CtOrDefault("height"))
    row:SetScale(ct.scale or CtOrDefault("scale"))
    row:ClearAllPoints()
    if preview and KART.CtPreviewSlot then
        row:SetPoint("CENTER", KART.CtPreviewSlot, "CENTER", 0, 0)
    else
        row:SetPoint(
            ct.point or CtOrDefault("point"),
            UIParent,
            ct.relativePoint or CtOrDefault("relativePoint"),
            ct.x or CtOrDefault("x"),
            ct.y or CtOrDefault("y")
        )
    end

    local fill = ct.healthFill or CtOrDefault("healthFill")
    ApplyBarFill(row.health, fill)
    ApplyBarFill(row.absorbBar, fill)

    local br, bgc, bb = ColorRGB(ct.borderColor, CT_LAYOUT_DEFAULTS.borderColor)
    StyleEdgeSet(row.borderEdges, ct.borderSize or CtOrDefault("borderSize"), br, bgc, bb, true)

    if row.bg then
        local bgr, bgg, bgb = ColorRGB(ct.bgColor, CT_LAYOUT_DEFAULTS.bgColor)
        row.bg:SetColorTexture(bgr, bgg, bgb, ct.bgAlpha or CtOrDefault("bgAlpha"))
    end

    if row.absorbBar then
        if ct.absorbShow ~= false then row.absorbBar:Show() else row.absorbBar:Hide() end
    end
    if row.healAbsorbFill then
        if ct.healAbsorbShow == false then row.healAbsorbFill:Hide() end
    end

    CT.BuildStrips(row, preview and true or nil)
end

function CT.ApplyLayout()
    if CT.row and not InCombatLockdown() then
        LayoutRow(CT.row, false)
    end
    if CT.previewRow and CT.hosted then
        LayoutRow(CT.previewRow, true)
    end
end

-- ===== Paint ------------------------------------------------------------------------------
function CT.BarPass(value)
    if CT.IsSecret(value) then return value end
    return value or 0
end

function CT.AbsorbFill(health, absorb, max)
    if CT.IsSecret(health) or CT.IsSecret(absorb) or CT.IsSecret(max) then return nil end
    health, absorb, max = health or 0, absorb or 0, max or 0
    local sum = health + absorb
    if max > 0 and sum > max then return max end
    return sum
end

function CT.HealAbsorbSpan(health, healAbsorb, max)
    if CT.IsSecret(health) or CT.IsSecret(healAbsorb) or CT.IsSecret(max) then
        return nil, nil
    end
    health, healAbsorb = health or 0, healAbsorb or 0
    if healAbsorb > health then healAbsorb = health end
    return health - healAbsorb, healAbsorb
end

local function BarCeiling(max)
    if CT.IsSecret(max) then return max end
    max = max or 0
    if max <= 0 then return 1 end
    return max
end

local function PlaceHealAbsorb(row, start, shown, max, fill)
    local tex = row.healAbsorbFill
    local bar = row.health
    if not tex or not bar then return end
    if not shown or shown <= 0 or not max or max <= 0 or CT.IsSecret(max) then
        tex:Hide()
        return
    end
    local w = bar:GetWidth()
    if not w or w <= 0 then
        tex:Hide()
        return
    end
    if fill ~= "right" then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("LEFT", bar, "LEFT", (start / max) * w, 0)
    tex:SetPoint("TOP", bar, "TOP")
    tex:SetPoint("BOTTOM", bar, "BOTTOM")
    tex:SetWidth((shown / max) * w)
    tex:Show()
end

function CT.Paint(snap, row)
    row = row or CT.row
    if not row or not snap then return end
    local ct = CtSettings() or {}

    local max = BarCeiling(snap.healthMax)
    local health = CT.BarPass(snap.health)

    if row.health then
        row.health:SetMinMaxValues(0, max)
        row.health:SetValue(health)
        local r, g, b = HealthBarColor(snap, ct)
        local fillAlpha = ct.healthAlpha or CtOrDefault("healthAlpha")
        row.health:SetStatusBarColor(r, g, b, fillAlpha)
        if row.healthBg then
            local trackAlpha = ct.trackAlpha or CtOrDefault("trackAlpha")
            row.healthBg:SetColorTexture(0, 0, 0, trackAlpha)
        end
    end

    if row.absorbBar then
        row.absorbBar:SetMinMaxValues(0, max)
        local fill = CT.AbsorbFill(snap.health, snap.absorb, snap.healthMax)
        if fill ~= nil then
            row.absorbBar:SetValue(fill)
        end
        local ar, ag, ab = ColorRGB(ct.absorbColor, CT_LAYOUT_DEFAULTS.absorbColor)
        row.absorbBar:SetStatusBarColor(ar, ag, ab, ct.absorbAlpha or CtOrDefault("absorbAlpha"))
    end

    if row.healAbsorbFill then
        if ct.healAbsorbShow == false then
            row.healAbsorbFill:Hide()
        else
            local start, shown = CT.HealAbsorbSpan(snap.health, snap.healAbsorb, snap.healthMax)
            local hr, hg, hb = ColorRGB(ct.healAbsorbColor, CT_LAYOUT_DEFAULTS.healAbsorbColor)
            row.healAbsorbFill:SetColorTexture(hr, hg, hb, ct.healAbsorbAlpha or CtOrDefault("healAbsorbAlpha"))
            PlaceHealAbsorb(row, start, shown, snap.healthMax, ct.healthFill or CtOrDefault("healthFill"))
        end
    end

    local nameStyle = Nested(ct, "nameStyle", NAME_STYLE_DEFAULTS)
    local healthStyle = Nested(ct, "healthStyle", HEALTH_STYLE_DEFAULTS)
    if row.nameText then
        row.nameText:SetText(TruncateName(snap.name, ct.nameMaxLength or CtOrDefault("nameMaxLength")))
        ApplyLabel(row.nameText, row, nameStyle, NAME_STYLE_DEFAULTS, snap)
    end
    if row.healthText then
        row.healthText:SetText(FormatHealthText(snap, ct))
        ApplyLabel(row.healthText, row, healthStyle, HEALTH_STYLE_DEFAULTS, snap)
    end

    local tb = Nested(ct, "targetBorder", TARGET_BORDER_DEFAULTS)
    local targeted = tb.show and (CT.Invented() or (CT.watchedUnit and UnitIsUnit("target", CT.watchedUnit)))
    local tr, tg, tbcol = ColorRGB(tb.color, TARGET_BORDER_DEFAULTS.color)
    StyleEdgeSet(row.targetEdges, tb.size or TARGET_BORDER_DEFAULTS.size, tr, tg, tbcol, targeted and true or false)

    row:SetAlpha(CT.RowAlpha(snap, ct))
end

-- ===== Live unit events ---------------------------------------------------------------
local ROW_UNIT_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_CONNECTION",
    "UNIT_IN_RANGE_UPDATE",
}

function CT.EventUnitMatchesWatched(eventUnit)
    if not CT.watchedUnit or not eventUnit then return false end
    if UnitIsUnit(eventUnit, CT.watchedUnit) then return true end
    if UnitIsUnit(eventUnit, "player") and UnitIsUnit(CT.watchedUnit, "player") then
        return true
    end
    return false
end

function CT.SyncRowUnitEvents(row, unit)
    if not row then
        CT.watchedUnit = nil
        return
    end
    CT.watchedUnit = unit
    for _, event in ipairs(ROW_UNIT_EVENTS) do
        row:UnregisterEvent(event)
    end
    if not unit then return end
    for _, event in ipairs(ROW_UNIT_EVENTS) do
        if row.RegisterUnitEvent then
            row:RegisterUnitEvent(event, unit)
        end
    end
end

function CT.OnUnitEvent(event, eventUnit)
    if not CT.ShouldShow() then return end
    if eventUnit and not CT.EventUnitMatchesWatched(eventUnit) then return end
    CT.snap = CT.snap or {}
    if CT.Invented() then
        CT.FillTestSnapshot(CT.snap)
    else
        local unit = CT.watchedUnit or CT.PickCoTank()
        if unit then
            CT.FillLiveSnapshot(unit, CT.snap)
        else
            CT.BlankSnapshot(CT.snap)
            CT.snap.name = "No tanks in the group"
            CT.snap.health, CT.snap.healthMax = 1, 1
            CT.snap.inRange = true
        end
    end
    CT.Paint(CT.snap)
end

-- ===== Event wiring -----------------------------------------------------------------------
local CT_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_ROLES_ASSIGNED",
    "PLAYER_TARGET_CHANGED",
}

function CT.OnRoster()
    CT.Refresh()
end

function CT.OnInstance()
    CT.Refresh()
end

function CT.Refresh()
    local combat = InCombatLockdown()
    if not CT.ShouldShow() then
        if CT.row then
            if combat then
                CT.pendingHide = true
            else
                CT.pendingHide = nil
                CT.SyncRowUnitEvents(CT.row, nil)
                CT.row:Hide()
            end
        end
        CT.RefreshAskButton()
        CT.RefreshPreview()
        return
    end
    CT.pendingHide = nil
    if combat and not CT.row then
        CT.RefreshPreview()
        return
    end
    local row = CT.EnsureRow()
    local invented = CT.Invented()
    local unit = invented and nil or CT.PickCoTank()

    if not combat then
        CT.ApplyLayout()
    end
    CT.SyncStripUnits(row, unit)

    CT.SyncRowUnitEvents(row, unit)

    CT.snap = CT.snap or {}
    CT.BlankSnapshot(CT.snap)
    if invented then
        CT.FillTestSnapshot(CT.snap)
    elseif unit then
        CT.FillLiveSnapshot(unit, CT.snap)
    else
        CT.snap.name = "No tanks in the group"
        CT.snap.health, CT.snap.healthMax = 1, 1
        CT.snap.inRange = true
    end
    CT.Paint(CT.snap)
    CT.ApplySecureUnit(row, unit)
    if not combat then
        row:Show()
    end
    CT.RefreshAskButton()
    CT.RefreshPreview()
end

function CT.RefreshPreview()
    if not CT.hosted then return end
    if not KART_Settings or KART_Settings.ctModuleEnabled ~= true then
        if CT.previewRow then CT.previewRow:Hide() end
        return
    end
    local row = CT.EnsurePreviewRow()
    LayoutRow(row, true)
    local snap = CT.BlankSnapshot({})
    CT.FillTestSnapshot(snap)
    CT.Paint(snap, row)
    row:Show()
end

function CT.HostPreview()
    if not KART_Settings or KART_Settings.ctModuleEnabled ~= true then
        CT.ReleasePreview()
        return
    end
    CT.pendingRelease = nil
    CT.pendingHost = nil
    CT.hosted = true
    CT.Refresh()
end

function CT.ReleasePreview()
    CT.pendingHost = nil
    CT.pendingRelease = nil
    CT.hosted = nil
    if CT.previewRow then
        CT.previewRow:Hide()
    end
    CT.Refresh()
end

function CT.OnSettingsTab(open)
    if open then
        CT.HostPreview()
    else
        CT.ReleasePreview()
    end
end

function CT.Disable()
    local combat = InCombatLockdown()
    CT.pendingHost = nil
    CT.pendingRelease = nil
    if combat then
        CT.pendingUnparent = true
        CT.hosted = nil
    else
        CT.hosted = nil
        CT.pendingUnparent = nil
        CT.pendingHide = nil
    end
    if CT.events then
        for _, event in ipairs(CT_EVENTS) do
            CT.events:UnregisterEvent(event)
        end
        CT.events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        CT.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    if CT.row then
        CT.SyncRowUnitEvents(CT.row, nil)
        if not combat then
            CT.row:SetParent(UIParent)
            CT.row:Hide()
        else
            CT.pendingHide = true
        end
    end
    CT.watchedUnit = nil
    CT.pendingUnit = nil
    if CT.previewRow then
        CT.previewRow:Hide()
    end
    if CT.askBtn then
        CT.askBtn:Hide()
    end
end

function CT.SyncWidgets()
    local ct = KART_Settings and KART_Settings.ct
    if not ct then
        CT.Enable()
        return
    end

    local function setSlider(widget, value)
        if widget and widget.SetValue and value ~= nil then widget:SetValue(value) end
    end
    local function setChecked(widget, value)
        if widget and widget.SetChecked then widget:SetChecked(value) end
    end

    setChecked(KART.CbCtTestMode, ct.testMode)
    setChecked(KART.CbCtLock, ct.locked)
    setChecked(KART.CbCtOnlyGroup, ct.onlyInGroup ~= false)
    setChecked(KART.CbCtOnlyInstance, ct.onlyInInstance ~= false)
    setSlider(KART.SldCtWidth, ct.width)
    setSlider(KART.SldCtHeight, ct.height)
    setSlider(KART.SldCtScale, (ct.scale or 1) * 100)
    setSlider(KART.SldCtRangeFade, (ct.rangeAlpha or 0.4) * 100)
    setSlider(KART.SldCtNameMax, ct.nameMaxLength)
    setChecked(KART.CbCtAbsorb, ct.absorbShow)
    setChecked(KART.CbCtHealAbsorb, ct.healAbsorbShow)
    setSlider(KART.SldCtHealthAlpha, (ct.healthAlpha or 1) * 100)
    setSlider(KART.SldCtTrackAlpha, (ct.trackAlpha or 0.4) * 100)
    setSlider(KART.SldCtBgAlpha, (ct.bgAlpha or 0.92) * 100)
    setSlider(KART.SldCtBorderSize, ct.borderSize)
    setSlider(KART.SldCtAbsorbAlpha, (ct.absorbAlpha or 0.7) * 100)
    setSlider(KART.SldCtHealAbsorbAlpha, (ct.healAbsorbAlpha or 0.7) * 100)
    setChecked(KART.CbCtRangeFadeOn, ct.rangeFade ~= false)
    setSlider(KART.SldCtDeadFade, (ct.deadFade or 0.35) * 100)
    setSlider(KART.SldCtOfflineFade, (ct.offlineFade or 0.35) * 100)

    local tb = ct.targetBorder
    if tb then
        setChecked(KART.CbCtTargetBorder, tb.show)
        setSlider(KART.SldCtTargetBorderSize, tb.size)
    end

    local function syncStyle(w, st)
        if not w or not st then return end
        setChecked(w.show, st.show ~= false)
        setSlider(w.size, st.size)
        setChecked(w.classCb, st.classColor)
        setSlider(w.nudgeX, st.x)
        setSlider(w.nudgeY, st.y)
        if w.refreshOutline then w.refreshOutline() end
        if w.refreshAnchor then w.refreshAnchor() end
    end
    syncStyle(KART.CtNameTextWidgets, ct.nameStyle)
    syncStyle(KART.CtHealthTextWidgets, ct.healthStyle)

    local function syncStripExtra(extra, cfg)
        if not extra or not cfg then return end
        setSlider(extra.perRow, cfg.perRow)
        setSlider(extra.border, cfg.borderSize)
        setSlider(extra.nudgeX, cfg.x)
        setSlider(extra.nudgeY, cfg.y)
        setChecked(extra.swipe, cfg.swipe ~= false)
        setChecked(extra.countdown, cfg.countdown ~= false)
        setSlider(extra.cdSize, cfg.countdownSize)
        setChecked(extra.stacks, cfg.stacks ~= false)
        setSlider(extra.stSize, cfg.stacksSize)
    end
    syncStripExtra(KART.CtDebuffExtra, ct.debuffs)
    syncStripExtra(KART.CtBuffExtra, ct.buffs)

    local debuffs = ct.debuffs
    if debuffs then
        setChecked(KART.CbCtDebuffShow, debuffs.show)
        setSlider(KART.SldCtDebuffMax, debuffs.max)
        setSlider(KART.SldCtDebuffSize, debuffs.size)
        setSlider(KART.SldCtDebuffSpacing, debuffs.spacing)
    end

    local buffs = ct.buffs
    if buffs then
        setChecked(KART.CbCtBuffShow, buffs.show)
        setSlider(KART.SldCtBuffMax, buffs.max)
        setSlider(KART.SldCtBuffSize, buffs.size)
        setSlider(KART.SldCtBuffSpacing, buffs.spacing)
    end

    local taunt = ct.taunt
    if taunt then
        setChecked(KART.CbCtTauntAnnounce, taunt.announce)
        setChecked(KART.CbCtTauntOnlyGroup, taunt.onlyInGroup ~= false)
        setChecked(KART.CbCtTauntOnlyInstance, taunt.onlyInInstance ~= false)
        setChecked(KART.CbCtTauntButton, taunt.button)
        setChecked(KART.CbCtTauntBtnLock, taunt.locked ~= false)
        setChecked(KART.CbCtTauntBtnGroup, taunt.buttonOnlyInGroup ~= false)
        setChecked(KART.CbCtTauntBtnRaid, taunt.buttonOnlyInRaid)
        setSlider(KART.SldCtTauntSize, taunt.size)
        local ch = taunt.channels or {}
        setChecked(KART.CbCtTauntWhisper, ch.WHISPER)
        setChecked(KART.CbCtTauntGroup, ch.GROUP)
        setChecked(KART.CbCtTauntRW, ch.RAID_WARNING)
        setChecked(KART.CbCtTauntSay, ch.SAY)
        setChecked(KART.CbCtTauntYell, ch.YELL)
        if KART.EbCtTauntMessage and KART.EbCtTauntMessage.SetText then
            KART.EbCtTauntMessage:SetText(taunt.message or "Taunt: %t")
        end
        if KART.EbCtTauntAsk and KART.EbCtTauntAsk.SetText then
            KART.EbCtTauntAsk:SetText(taunt.ask or "%n, please taunt!")
        end
    end

    CT.Enable()
end

function CT.Enable()
    if KART_Settings.ctModuleEnabled ~= true then
        CT.Disable()
        return
    end
    if not CT.events then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_REGEN_ENABLED" then
                CT.OnRegenEnabled()
            elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
                CT.OnRoster()
            elseif event == "PLAYER_ENTERING_WORLD" then
                CT.OnInstance()
            elseif event == "PLAYER_TARGET_CHANGED" then
                CT.Refresh()
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                local unit, _, spellID = ...
                if unit == "player" then
                    CT.OnTauntCast(spellID)
                end
            end
        end)
        CT.events = f
    end
    for _, event in ipairs(CT_EVENTS) do
        CT.events:RegisterEvent(event)
    end
    CT.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    CT.Refresh()
    CT.RefreshAuraEngineNote()
end

-- ===== Taunt announce / ask -----------------------------------------------------------
-- Only the player's own taunt is visible on this patch (instant casts are not announced
-- for other people). Spell IDs are game data. Death Grip counts only in Blood (spec 250).
local TAUNT_SPELLS = {
    [355] = true,      -- Warrior: Taunt
    [56222] = true,    -- Death Knight: Dark Command
    [49576] = 250,     -- Death Knight: Death Grip (Blood)
    [62124] = true,    -- Paladin: Hand of Reckoning
    [115546] = true,   -- Monk: Provoke
    [6795] = true,     -- Druid: Growl
    [185245] = true,   -- Demon Hunter: Torment
}
local CLASS_TAUNT = {
    WARRIOR = 355,
    DEATHKNIGHT = 56222,
    PALADIN = 62124,
    MONK = 115546,
    DRUID = 6795,
    DEMONHUNTER = 185245,
}
local TAUNT_DEFAULT_MESSAGE = "Taunt: %t"
local TAUNT_DEFAULT_ASK = "%n, please taunt!"
local TAUNT_DEBOUNCE = 1.5
local TAUNT_MACRO_NAME = "KART Ask Taunt"
local ASK_BUTTON_DEFAULTS = {
    size = 44, locked = true,
    point = "CENTER", relativePoint = "CENTER", x = 80, y = 200,
}

local function TauntCfg()
    local ct = CtSettings()
    local t = ct and ct.taunt
    if type(t) ~= "table" then return nil end
    return t
end

local function PublicString(value)
    if value == nil or CT.IsSecret(value) then return "" end
    return value
end

function CT.PlayerSpecId()
    local info = C_SpecializationInfo
    if not info or not info.GetSpecialization or not info.GetSpecializationInfo then
        return 0
    end
    local idx = info.GetSpecialization()
    if not idx then return 0 end
    local specId = info.GetSpecializationInfo(idx)
    return specId or 0
end

function CT.IsTaunt(spellID)
    if spellID == nil or CT.IsSecret(spellID) then return false end
    local spec = TAUNT_SPELLS[spellID]
    if spec == true then return true end
    if spec == nil then return false end
    return CT.PlayerSpecId() == spec
end

function CT.FormatTauntMessage(template, vars)
    template = template or ""
    if template == "" then return "" end
    local function sub(s, key, value)
        value = tostring(value or ""):gsub("%%", "%%%%")
        return (s:gsub("%%" .. key, value))
    end
    vars = vars or {}
    local out = template
    out = sub(out, "t", vars.t)
    out = sub(out, "s", vars.s)
    out = sub(out, "n", vars.n)
    return out
end

function CT.ShouldAnnounce()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return false end
    local t = s.ct and s.ct.taunt
    if not t or t.announce ~= true then return false end
    if t.onlyInGroup ~= false and not IsInGroup() then return false end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then return false end
    if t.onlyInInstance ~= false and not INSTANCE_OK[instanceType] then
        return false
    end
    return true
end

local function WhisperDest(unit)
    if not unit then return nil end
    local name, realm = UnitName(unit)
    name = PublicString(name)
    if name == "" then return nil end
    realm = PublicString(realm)
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function FillTauntVars(spellID, cotank)
    local spellName = ""
    if spellID and not CT.IsSecret(spellID) and C_Spell and C_Spell.GetSpellName then
        spellName = PublicString(C_Spell.GetSpellName(spellID))
    end
    return {
        t = PublicString(UnitName("target")),
        s = spellName,
        n = cotank and PublicString(UnitName(cotank)) or "",
    }
end

function CT.SendTauntChat(msg, cotank)
    if not msg or msg == "" then return end
    local t = TauntCfg()
    local ch = (t and t.channels) or {}
    if ch.WHISPER then
        local dest = WhisperDest(cotank)
        if dest then
            SendChatMessage(msg, "WHISPER", nil, dest)
        end
    end
    if ch.GROUP and IsInGroup() then
        SendChatMessage(msg, IsInRaid() and "RAID" or "PARTY")
    end
    if ch.RAID_WARNING and IsInRaid()
        and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        SendChatMessage(msg, "RAID_WARNING")
    end
    if ch.SAY then
        SendChatMessage(msg, "SAY")
    end
    if ch.YELL then
        SendChatMessage(msg, "YELL")
    end
end

function CT.Announce(spellID)
    local t = TauntCfg() or {}
    local template = t.message
    if not template or template == "" then template = TAUNT_DEFAULT_MESSAGE end
    local cotank = CT.PickCoTank()
    local msg = CT.FormatTauntMessage(template, FillTauntVars(spellID, cotank))
    CT.SendTauntChat(msg, cotank)
end

function CT.OnTauntCast(spellID)
    if spellID == nil or CT.IsSecret(spellID) then return end
    if not CT.IsTaunt(spellID) then return end
    if not CT.ShouldAnnounce() then return end
    local now = GetTime()
    if CT.lastTauntAt and (now - CT.lastTauntAt) < TAUNT_DEBOUNCE then
        return
    end
    CT.lastTauntAt = now
    CT.Announce(spellID)
end

function CT.Ask()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return end
    local cotank = CT.PickCoTank()
    if not cotank then return end
    local t = TauntCfg() or {}
    local template = t.ask
    if not template or template == "" then template = TAUNT_DEFAULT_ASK end
    local msg = CT.FormatTauntMessage(template, FillTauntVars(nil, cotank))
    CT.SendTauntChat(msg, cotank)
end

function CT.TauntIcon()
    local _, classFile = UnitClass("player")
    local spellID = CLASS_TAUNT[classFile] or 355
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return 132270
end

function CT.CreateAskMacro()
    if InCombatLockdown() then return "combat" end
    local body = "/run if KART and KART.CT then KART.CT.Ask() end"
    local icon = CT.TauntIcon()
    local idx = GetMacroIndexByName and GetMacroIndexByName(TAUNT_MACRO_NAME)
    if idx and idx > 0 then
        local ok = pcall(EditMacro, idx, TAUNT_MACRO_NAME, icon, body)
        return ok and "edited" or "failed"
    end
    local ok = pcall(CreateMacro, TAUNT_MACRO_NAME, icon, body)
    return ok and "created" or "failed"
end

function CT.ShouldShowAskButton()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return false end
    local t = s.ct and s.ct.taunt
    if not t or t.button ~= true then return false end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then return false end
    if t.locked == false and not INSTANCE_OK[instanceType] then return true end
    if s.ct and s.ct.testMode then return true end
    if t.buttonOnlyInGroup ~= false and not IsInGroup() then return false end
    if t.buttonOnlyInRaid == true and not IsInRaid() then return false end
    return CT.PickCoTank() ~= nil
end

function CT.EnsureAskButton()
    if CT.askBtn and CT.askBtn.GetWidth then return CT.askBtn end
    CT.askBtn = nil
    local btn = CreateFrame("Button", "KART_CoTankAskButton", UIParent)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")
    if btn.SetClampedToScreen then btn:SetClampedToScreen(true) end
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.07, 0.08, 0.92)
    btn.bg = bg
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon = icon
    btn:SetScript("OnClick", function()
        CT.Ask()
    end)
    btn:SetScript("OnDragStart", function(self)
        local t = TauntCfg()
        if t and t.locked == false and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        local s = KART_Settings
        if not s then return end
        s.ct = s.ct or {}
        s.ct.taunt = s.ct.taunt or {}
        s.ct.taunt.point = point
        s.ct.taunt.relativePoint = relativePoint
        s.ct.taunt.x = xOfs
        s.ct.taunt.y = yOfs
    end)
    CT.askBtn = btn
    return btn
end

function CT.RefreshAskButton()
    if not CT.ShouldShowAskButton() then
        if CT.askBtn then CT.askBtn:Hide() end
        return
    end
    local btn = CT.EnsureAskButton()
    local t = TauntCfg() or {}
    local size = t.size or ASK_BUTTON_DEFAULTS.size
    btn:SetSize(size, size)
    if btn.icon and btn.icon.SetTexture then
        btn.icon:SetTexture(CT.TauntIcon())
    end
    btn:ClearAllPoints()
    btn:SetPoint(
        t.point or ASK_BUTTON_DEFAULTS.point,
        UIParent,
        t.relativePoint or ASK_BUTTON_DEFAULTS.relativePoint,
        t.x or ASK_BUTTON_DEFAULTS.x,
        t.y or ASK_BUTTON_DEFAULTS.y
    )
    btn:Show()
end

-- ===== Row fade ---------------------------------------------------------------------------
function CT.RowAlpha(snap, ct)
    if snap.dead then
        return (ct and ct.deadFade) or 0.35
    end
    if snap.offline then
        return (ct and ct.offlineFade) or 0.35
    end
    if (not ct or ct.rangeFade ~= false) and not snap.inRange then
        return (ct and ct.rangeAlpha) or 0.4
    end
    return 1
end
