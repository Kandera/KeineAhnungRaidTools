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
function CT.ShouldShow()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return false end
    if s.ct and s.ct.testMode then return true end
    if UnitGroupRolesAssigned("player") ~= "TANK" then return false end
    local _, instanceType = IsInInstance()
    if not INSTANCE_OK[instanceType] then return false end
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
    snap.inRange = CT.SafeTruthy(UnitInRange(unit), true)
    return snap
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
    if CT.row and not InCombatLockdown() then
        CT.row:SetAttribute("type1", "target")
    end
    if CT.pendingUnit and CT.row then
        CT.ApplySecureUnit(CT.row, CT.pendingUnit)
    end
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
    healthAlpha = 1, trackAlpha = 0.4,
}

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
    local health = snap.health or 0
    local max = snap.healthMax or 0
    local pct = max > 0 and math.floor(health / max * 100 + 0.5) or 0
    local mode = (ct and ct.healthText) or "both"
    if mode == "percent" then
        return pct .. "%"
    elseif mode == "current" then
        return tostring(math.floor(health + 0.5))
    end
    return tostring(math.floor(health + 0.5)) .. " / " .. pct .. "%"
end

local function HealthBarColor(snap, ct)
    local mode = (ct and ct.healthColor) or "class"
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

local function AddRowBorder(row)
    local function edge(p1, p2, w, h)
        local tex = row:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(0, 0, 0, 1)
        tex:SetPoint(p1, row, p1, 0, 0)
        tex:SetPoint(p2, row, p2, 0, 0)
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

function CT.EnsureRow()
    if CT.row and CT.row.GetWidth then return CT.row end
    CT.row = nil

    local row = CreateFrame("Button", "KART_CoTankFrame", UIParent, "SecureUnitButtonTemplate")
    row:RegisterForClicks("LeftButtonUp")
    if not InCombatLockdown() then
        row:SetAttribute("type1", "target")
    end

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.07, 0.08, 0.92)
    row.bg = bg

    AddRowBorder(row)

    local health = CreateFrame("StatusBar", nil, row)
    health:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    health:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    InitStatusBarFill(health)
    row.health = health
    row.healthBg = healthBg

    local absorbBar = CreateFrame("StatusBar", nil, row)
    absorbBar:SetAllPoints(health)
    InitStatusBarFill(absorbBar)
    row.absorbBar = absorbBar

    local healAbsorbBar = CreateFrame("StatusBar", nil, row)
    healAbsorbBar:SetAllPoints(health)
    InitStatusBarFill(healAbsorbBar)
    row.healAbsorbBar = healAbsorbBar

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.nameText = nameText

    local healthText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.healthText = healthText

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

    CT.row = row
    return row
end

-- ===== Layout -----------------------------------------------------------------------------
function CT.ApplyLayout()
    local row = CT.row
    if not row then return end
    local ct = CtSettings()
    if not ct then return end

    row:SetSize(ct.width or CtOrDefault("width"), ct.height or CtOrDefault("height"))
    row:SetScale(ct.scale or CtOrDefault("scale"))
    row:ClearAllPoints()
    row:SetPoint(
        ct.point or CtOrDefault("point"),
        UIParent,
        ct.relativePoint or CtOrDefault("relativePoint"),
        ct.x or CtOrDefault("x"),
        ct.y or CtOrDefault("y")
    )

    if row.absorbBar then
        if ct.absorbShow ~= false then row.absorbBar:Show() else row.absorbBar:Hide() end
    end
    if row.healAbsorbBar then
        if ct.healAbsorbShow ~= false then row.healAbsorbBar:Show() else row.healAbsorbBar:Hide() end
    end
end

-- ===== Paint ------------------------------------------------------------------------------
function CT.Paint(snap)
    local row = CT.row
    if not row or not snap then return end
    local ct = CtSettings() or {}

    local max = snap.healthMax or 0
    if max <= 0 then max = 1 end
    local health = snap.health or 0

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
        row.absorbBar:SetValue(math.min(snap.absorb or 0, max))
        row.absorbBar:SetStatusBarColor(0.4, 0.85, 0.85, 0.7)
    end

    if row.healAbsorbBar then
        row.healAbsorbBar:SetMinMaxValues(0, max)
        row.healAbsorbBar:SetValue(math.min(snap.healAbsorb or 0, max))
        row.healAbsorbBar:SetStatusBarColor(0.6, 0.2, 0.8, 0.7)
    end

    if row.nameText then
        row.nameText:SetText(TruncateName(snap.name, ct.nameMaxLength or CtOrDefault("nameMaxLength")))
    end

    if row.healthText then
        row.healthText:SetText(FormatHealthText(snap, ct))
    end

    row:SetAlpha(CT.RowAlpha(snap, ct))
end

-- ===== Event wiring -----------------------------------------------------------------------
local CT_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
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
    if not CT.ShouldShow() then
        if CT.row then
            CT.row:Hide()
        end
        return
    end
    local row = CT.EnsureRow()
    CT.ApplyLayout()
    CT.snap = CT.snap or {}
    CT.BlankSnapshot(CT.snap)
    local ct = KART_Settings and KART_Settings.ct
    if ct and ct.testMode then
        CT.FillTestSnapshot(CT.snap)
    else
        CT.FillLiveSnapshot(CT.PickCoTank() or "player", CT.snap)
    end
    CT.Paint(CT.snap)
    CT.ApplySecureUnit(row, CT.PickCoTank() or nil)
    row:Show()
end

function CT.Disable()
    if CT.events then
        for _, event in ipairs(CT_EVENTS) do
            CT.events:UnregisterEvent(event)
        end
    end
    if CT.row then
        CT.row:Hide()
    end
    CT.pendingUnit = nil
end

function CT.Enable()
    if KART_Settings.ctModuleEnabled ~= true then
        CT.Disable()
        return
    end
    if not CT.events then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                CT.OnRegenEnabled()
                CT.Refresh()
            elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
                CT.OnRoster()
            elseif event == "PLAYER_ENTERING_WORLD" then
                CT.OnInstance()
            elseif event == "PLAYER_TARGET_CHANGED" then
                CT.Refresh()
            end
        end)
        CT.events = f
    end
    for _, event in ipairs(CT_EVENTS) do
        CT.events:RegisterEvent(event)
    end
    CT.Refresh()
end

-- ===== Row fade ---------------------------------------------------------------------------
function CT.RowAlpha(snap, ct)
    if snap.dead or snap.offline then
        return 0.35
    end
    if not snap.inRange then
        return (ct and ct.rangeAlpha) or 0.4
    end
    return 1
end
