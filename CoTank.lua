local addonName, KART = ...
KART.CT = KART.CT or {}
local CT = KART.CT
local LSM = LibStub("LibSharedMedia-3.0", true)
local KAUI = LibStub("KAUI-1.0")
local KASC = LibStub("KASC-1.0")

local DEFAULT_HEALTH_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- ===== Instance filter --------------------------------------------------------------------
-- Raid only: a 5-man does not have a second tank. Arenas and BGs stay off separately.
local INSTANCE_OK = { raid = true }

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
    if KART.IsEditModeActive and KART.IsEditModeActive() and not INSTANCE_OK[instanceType] then
        return true
    end
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
    local state = CT.previewState
    if state == "oor" then
        snap.inRange = false
    elseif state == "dead" then
        snap.dead = true
        snap.health = 0
    elseif state == "offline" then
        snap.offline = true
    end
    return snap
end

function CT.SetPreviewState(state)
    if state ~= "oor" and state ~= "dead" and state ~= "offline" then
        state = "ok"
    end
    CT.previewState = state
    CT.Refresh()
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
    healthTexture = DEFAULT_HEALTH_TEXTURE,
    gradient = false,
    gradientFrom = { r = 0.2, g = 0.8, b = 0.2 },
    gradientTo = { r = 0.8, g = 0.2, b = 0.2 },
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

local function EnsureFillTex(bar)
    if not bar.kartFillTex then
        bar.kartFillTex = bar:CreateTexture(nil, "ARTWORK")
        bar:SetStatusBarTexture(bar.kartFillTex)
    end
    return bar.kartFillTex
end

local function InitStatusBarFill(bar)
    local tex = EnsureFillTex(bar)
    tex:SetColorTexture(1, 1, 1, 1)
end

local function ResolveHealthTexturePath(ct)
    local key = (ct and ct.healthTexture) or CT_LAYOUT_DEFAULTS.healthTexture
    if type(key) == "string" and (key:find("\\") or key:find("/")) then
        return key
    end
    if LSM then
        local fetched = LSM:Fetch("statusbar", key)
        if fetched then return fetched end
    end
    return DEFAULT_HEALTH_TEXTURE
end

local function ApplyHealthGradient(bar, ct, fillAlpha)
    local tex = bar and bar.kartFillTex
    if not tex or not tex.SetGradient or not CreateColor then return false end
    local from = (ct and ct.gradientFrom) or CT_LAYOUT_DEFAULTS.gradientFrom
    local to = (ct and ct.gradientTo) or CT_LAYOUT_DEFAULTS.gradientTo
    local fr, fg, fb = ColorRGB(from)
    local tr, tg, tb = ColorRGB(to)
    local a = fillAlpha
    if a == nil then a = (ct and ct.healthAlpha) or CtOrDefault("healthAlpha") or 1 end
    local fill = (ct and ct.healthFill) or CtOrDefault("healthFill")
    local orient = (fill == "up" or fill == "down") and "VERTICAL" or "HORIZONTAL"
    return pcall(tex.SetGradient, tex, orient, CreateColor(fr, fg, fb, a), CreateColor(tr, tg, tb, a))
end

local function ApplyBarFillTexture(bar, ct, allowGradient)
    if not bar then return end
    local tex = EnsureFillTex(bar)
    local path = ResolveHealthTexturePath(ct)
    bar.kartGradientActive = false
    if allowGradient and ct and ct.gradient then
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        bar.kartGradientActive = ApplyHealthGradient(bar, ct) and true or false
        if not bar.kartGradientActive then
            tex:SetTexture(path)
        end
    else
        tex:SetTexture(path)
    end
end

local function ApplyBarTextures(row, ct)
    ct = ct or CtSettings() or {}
    ApplyBarFillTexture(row.health, ct, true)
    ApplyBarFillTexture(row.absorbBar, ct, false)
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

local function ContentFontPath()
    local ui = KART.UI
    if ui and type(ui.lastFont) == "string" and ui.lastFont ~= "" then
        return ui.lastFont
    end
    return "Fonts\\FRIZQT__.TTF"
end

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
    if fs.SetFont then fs:SetFont(ContentFontPath(), size, outline) end
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
        local editMode = KART.IsEditModeActive and KART.IsEditModeActive()
        if ct and (not ct.locked or editMode) and not InCombatLockdown() then
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
    if KART.RegisterEditModeFrame then
        KART.RegisterEditModeFrame(row, "EDIT_MODE_LABEL_COTANK")
    end
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
    debuffs = { show = true, max = 8, size = 28, spacing = 6, perRow = 8,
                anchor = "TOPLEFT", growth = "right", x = 0, y = 4,
                borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                swipe = true, countdown = true, countdownSize = 0,
                stacks = true, stacksSize = 0,
                hideLongDuration = false, hideFatigue = true },
    buffs   = { show = true, max = 6, size = 18, spacing = 1, perRow = 6,
                anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4,
                borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                swipe = true, countdown = true, countdownSize = 0,
                stacks = true, stacksSize = 0,
                hideLongDuration = true },
}

-- v1 shipped 22px / 1px gap. Factory profiles still on those numbers move to 28 / 4
-- at schema 2, then the factory 4px gap becomes 6px at schema 3. A custom size or
-- gap is left alone. Schema 4 splits taunt.onlyInInstance into dungeon and raid
-- toggles; MergeDefaults may already have filled both as true, so v<4 always copies
-- the saved combined flag rather than trusting the new keys.
function CT.MigrateProfile(ct)
    if type(ct) ~= "table" then return end
    local v = tonumber(ct.schemaVersion) or 1
    if v < 2 then
        local d = ct.debuffs
        if type(d) == "table" then
            if d.size == 22 then d.size = 28 end
            if d.spacing == 1 then d.spacing = 4 end
        end
        ct.schemaVersion = 2
        v = 2
    end
    if v < 3 then
        local d = ct.debuffs
        if type(d) == "table" and d.spacing == 4 then d.spacing = 6 end
        ct.schemaVersion = 3
        v = 3
    end
    if v < 4 then
        local t = ct.taunt
        if type(t) == "table" then
            local instanceOn = t.onlyInInstance ~= false
            t.onlyInDungeon = instanceOn
            t.onlyInRaid = instanceOn
        end
        ct.schemaVersion = 4
    end
end

-- Bloodlust/Heroism downs and the Time Warp / Drums equivalents. Spell IDs are game facts,
-- not copied from another addon. Used when hideFatigue is on.
CT.FATIGUE_SPELL_IDS = {
    [57723] = true, -- Exhaustion (Heroism)
    [390435] = true, -- Exhaustion
    [57724] = true, -- Sated (Bloodlust)
    [80354] = true, -- Temporal Displacement (Time Warp)
    [95809] = true, -- Insanity (Drums)
    [264689] = true, -- Fatigued
    [160455] = true, -- Fatigued
}

-- Tank personal defensives and healer externals that land on the co-tank.
-- Per-patch maintenance, same class as GOOD_ENCHANTS: a new ID is drift, not a
-- code defect. Intentionally omitted: short armor stacks (Ironfur, Shield Block,
-- Demon Spikes, Bone Shield, Shuffle), self-hots (Rejuvenation, Enveloping Mist),
-- and absorbs that fire every few seconds (Power Word: Shield, Earth Shield).
CT.BUFF_SPELL_IDS = {
    -- Warrior
    [871]    = true, -- Shield Wall
    [12975]  = true, -- Last Stand
    [97463]  = true, -- Rallying Cry
    [23920]  = true, -- Spell Reflection
    [190456] = true, -- Ignore Pain
    [107574] = true, -- Avatar
    -- Paladin
    [31850]  = true, -- Ardent Defender
    [86659]  = true, -- Guardian of Ancient Kings
    [642]    = true, -- Divine Shield
    [498]    = true, -- Divine Protection
    [389539] = true, -- Sentinel
    [387174] = true, -- Eye of Tyr
    [204018] = true, -- Blessing of Spellwarding
    [1022]   = true, -- Blessing of Protection
    [6940]   = true, -- Blessing of Sacrifice
    [31821]  = true, -- Aura Mastery
    [148039] = true, -- Barrier of Faith
    -- Death Knight
    [48792]  = true, -- Icebound Fortitude
    [55233]  = true, -- Vampiric Blood
    [48707]  = true, -- Anti-Magic Shell
    [81256]  = true, -- Dancing Rune Weapon
    [219809] = true, -- Tombstone
    [49039]  = true, -- Lichborne
    [194679] = true, -- Rune Tap
    [145629] = true, -- Anti-Magic Zone
    [114556] = true, -- Purgatory
    [194844] = true, -- Bonestorm
    -- Demon Hunter
    [187827] = true, -- Metamorphosis
    [209426] = true, -- Darkness
    [209261] = true, -- Last Resort
    [263648] = true, -- Soul Barrier
    -- Monk
    [120954] = true, -- Fortifying Brew
    [243435] = true, -- Fortifying Brew
    [122278] = true, -- Dampen Harm
    [122783] = true, -- Diffuse Magic
    [322507] = true, -- Celestial Brew
    [132578] = true, -- Invoke Niuzao
    [115176] = true, -- Zen Meditation
    [116849] = true, -- Life Cocoon
    -- Druid
    [22812]  = true, -- Barkskin
    [61336]  = true, -- Survival Instincts
    [22842]  = true, -- Frenzied Regeneration
    [102558] = true, -- Incarnation: Guardian of Ursoc
    [200851] = true, -- Rage of the Sleeper
    [204066] = true, -- Lunar Beam
    [50334]  = true, -- Berserk
    [102342] = true, -- Ironbark
    [102351] = true, -- Cenarion Ward
    [102352] = true, -- Cenarion Ward (HoT)
    -- Priest
    [33206]  = true, -- Pain Suppression
    [47788]  = true, -- Guardian Spirit
    [81782]  = true, -- Power Word: Barrier
    [108968] = true, -- Void Shift
    -- Shaman
    [98007]  = true, -- Spirit Link Totem
    [325174] = true, -- Spirit Link Totem
    [201633] = true, -- Earthen Wall Totem
    [207498] = true, -- Ancestral Protection Totem
    [207495] = true, -- Ancestral Protection
    -- Evoker
    [357170] = true, -- Time Dilation
    [370537] = true, -- Stasis
    [370562] = true, -- Stasis
    [374227] = true, -- Zephyr
    [370888] = true, -- Twin Guardian
}

-- AuraContainer candidateFilters for a strip. Debuffs can hide 5-minute+ auras and BL downs.
function CT.CandidateFilters(kind, cfg)
    local filters = {}
    if not cfg then return filters end
    -- maxDuration is the aura's base duration. Food, flask, Well Fed and raid
    -- buffs are ~1h; tank defensives are seconds. HELPFUL|PLAYER is the wrong
    -- cut: it would drop the co-tank's own Shield Wall.
    if kind == "debuffs" then
        -- NPC/boss auras only. Player-applied HARMFUL includes the Guardian
        -- Well-Honed Instincts ICD (90s cheat-death lockout), not raid debuffs.
        filters.isFromPlayerOrPlayerPet = false
        if cfg.hideLongDuration then
            filters.maxDuration = 300
        end
        if cfg.hideFatigue ~= false then
            filters.excludeSpellIDs = CT.FATIGUE_SPELL_IDS
        end
    elseif kind == "buffs" then
        filters.includeSpellIDs = CT.BUFF_SPELL_IDS
        if cfg.hideLongDuration ~= false then
            filters.maxDuration = 300
        end
    end
    return filters
end

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

local AURA_ADDON = "Blizzard_AuraContainer"
local AURA_TEMPLATE = "CustomAuraContainerTemplate"

-- BuffFrame's AuraContainerTemplate OnLoad is forbidden to addons. The Midnight
-- AuraContainer widget is legal with CustomAuraContainerTemplate after the
-- Blizzard_AuraContainer addon is loaded — that is the same path nameplates
-- and other addons use. A bare CreateFrame("AuraContainer") has no groups
-- and paints nothing.
local function EnsureAuraAddon()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(AURA_ADDON) then
        return true
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        local loaded = C_AddOns.LoadAddOn(AURA_ADDON)
        return loaded and true or false
    end
    return false
end

local function AuraEngineFrame(frame)
    if not frame or not frame.AddAuraGroup then return false end
    if frame.GetObjectType then
        local ok, ty = pcall(frame.GetObjectType, frame)
        if ok and ty == "AuraContainer" then return true end
    end
    -- Templated widgets on some builds report as Frame; the addon load is the other proof.
    -- The harness answers every method via __index, so AddAuraGroup alone is not enough.
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(AURA_ADDON) and true or false
end

function CT.AuraEngineAvailable()
    if AURA_ENGINE_AVAILABLE ~= nil then return AURA_ENGINE_AVAILABLE end
    -- No template without the addon. Do not CreateFrame here: WoW cannot destroy frames, and
    -- Refresh calls this often. Leave uncached so a later LoadAddOn can still succeed.
    if not EnsureAuraAddon() then return false end
    local ok, frame = pcall(CreateFrame, "AuraContainer", nil, UIParent, AURA_TEMPLATE)
    local live = ok and AuraEngineFrame(frame)
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
    local size = cfg.size or 18
    local spacing = cfg.spacing or 0
    return {
        elementWidth = size,
        elementHeight = size,
        elementSpacing = spacing,
        lineSpacing = spacing,
    }
end
CT.AuraGroupLayout = AuraGroupLayout

local function TryFrameCall(frame, names, ...)
    if not frame then return false end
    for i = 1, #names do
        local fn = frame[names[i]]
        if fn then
            local ok = pcall(fn, frame, ...)
            if ok then return true end
        end
    end
    return false
end

local function FlowDirectionToken(name)
    local au = _G.AnchorUtil
    local dirs = au and au.FlowDirection
    if not dirs then return name end
    if name == "LEFT" then return dirs.Left or name end
    if name == "RIGHT" then return dirs.Right or name end
    if name == "UP" then return dirs.Up or name end
    if name == "DOWN" then return dirs.Down or name end
    return name
end

-- Origin is the strip's own anchor (buffs: BOTTOMRIGHT). Growth left must
-- start there; a TOPLEFT/RIGHT default packs the icons LTR inside a
-- right-placed box, which reads as "growing the wrong way".
local function ApplyStripFlow(strip, cfg)
    local growth = cfg.growth or "right"
    local point = cfg.anchor or "TOPLEFT"
    local dirH, dirV, vertical = "RIGHT", "DOWN", false
    if growth == "left" then
        dirH, dirV = "LEFT", "DOWN"
    elseif growth == "up" then
        dirH, dirV, vertical = "RIGHT", "UP", true
    elseif growth == "down" then
        dirH, dirV, vertical = "RIGHT", "DOWN", true
    end
    local au = _G.AnchorUtil
    if au and au.FlowLayoutAxis and strip.SetFlowLayoutAxis then
        pcall(strip.SetFlowLayoutAxis, strip,
            vertical and au.FlowLayoutAxis.Vertical or au.FlowLayoutAxis.Horizontal)
    end
    TryFrameCall(strip, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, point)
    local enumH, enumV = FlowDirectionToken(dirH), FlowDirectionToken(dirV)
    local growthNames = { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" }
    if not TryFrameCall(strip, growthNames, enumH, enumV) then
        TryFrameCall(strip, growthNames, dirH, dirV)
    end
    local perRow = cfg.perRow or cfg.max or 8
    if perRow < 1 then perRow = 1 end
    local size = cfg.size or 18
    local spacing = cfg.spacing or 0
    local line = perRow * size + math.max(0, perRow - 1) * spacing
    TryFrameCall(strip, {
        "SetFlowLayoutMaximumLineSize", "SetFlowLayoutMaximumLineSize",
        "SetAuraLayoutRowWidth",
    }, line)
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
            if icon.cd.SetFont then icon.cd:SetFont(ContentFontPath(), cdSize, "OUTLINE") end
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
            if icon.stack.SetFont then icon.stack:SetFont(ContentFontPath(), stSize, "OUTLINE") end
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

-- CustomAuraButtonTemplate ships no Icon region. The engine only paints after
-- initializeFrame registers a texture with SetIcon (and fonts a duration
-- FontString before SetDurationText). Skipping that callback is why a live
-- strip can exist, take a unit, and still show nothing.
local function SkinAuraButton(button, cfg)
    if not button then return end
    pcall(button.EnableMouse, button, false)

    local size = cfg.size or 18
    -- Flow layout uses elementWidth for spacing but does not size the button.
    button:SetSize(size, size)
    local borderSize = cfg.borderSize or 1
    if borderSize < 0 then borderSize = 0 end

    local icon = button:CreateTexture(nil, "ARTWORK")
    if borderSize > 0 then
        local br, bg, bb = ColorRGB(cfg.borderColor, { r = 0, g = 0, b = 0 })
        local edge = button:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(button)
        edge:SetColorTexture(br, bg, bb, 1)
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", borderSize, -borderSize)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
    else
        icon:SetAllPoints(button)
    end
    KAUI.CropSpellIcon(icon)
    if button.SetIcon then pcall(button.SetIcon, button, icon) end

    if cfg.swipe ~= false and button.SetDurationCooldown then
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        pcall(button.SetDurationCooldown, button, cd)
    end

    if cfg.countdown ~= false and button.SetDurationText then
        local fs = button:CreateFontString(nil, "OVERLAY")
        local cdSize = cfg.countdownSize or 0
        if cdSize <= 0 then cdSize = math.max(8, math.floor(size * 0.45)) end
        if fs.SetFont then fs:SetFont(ContentFontPath(), cdSize, "OUTLINE") end
        fs:SetPoint("CENTER", button, "CENTER", 0, 0)
        pcall(button.SetDurationText, button, fs, {})
    end

    if cfg.stacks ~= false and button.SetApplicationCount then
        local fs = button:CreateFontString(nil, "OVERLAY")
        local stSize = cfg.stacksSize or 0
        if stSize <= 0 then stSize = math.max(8, math.floor(size * 0.4)) end
        if fs.SetFont then fs:SetFont(ContentFontPath(), stSize, "OUTLINE") end
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        pcall(button.SetApplicationCount, button, fs, { minCount = 2 })
    end
end

local function BuildLiveStrip(row, key, cfg, filter)
    local host = StripHost(row)
    local strip = row[key]
    if not strip or not strip.isAuraEngine or not strip._auraTemplate
        or not strip.AddAuraGroup
        or (strip.GetParent and strip:GetParent() ~= host) then
        if strip then strip:Hide() end
        EnsureAuraAddon()
        local ok, frame = pcall(CreateFrame, "AuraContainer", nil, host, AURA_TEMPLATE)
        if not ok or not AuraEngineFrame(frame) then return end
        strip = frame
        strip.isAuraEngine = true
        strip._auraTemplate = true
        row[key] = strip
        pcall(strip.EnableMouse, strip, false)
    end

    if host.SetClipsChildren then host:SetClipsChildren(false) end
    if strip.SetClipsChildren then strip:SetClipsChildren(false) end

    if cfg.show == false then
        strip:Hide()
        if strip.SetEnabled then pcall(strip.SetEnabled, strip, false) end
        return strip
    end

    local w, h = StripPixelSize(cfg)
    strip:SetSize(w, h)
    PlaceStrip(strip, row, cfg)
    pcall(ApplyStripFlow, strip, cfg)
    if strip.SetEnabled then pcall(strip.SetEnabled, strip, true) end
    strip:Show()

    local filters = CT.CandidateFilters(key, cfg)

    if not strip._auraGroupAdded then
        local sortMethod, sortDirection
        local methods, dirs = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
        if type(methods) == "table" then
            sortMethod = methods.Default or methods.AuraInstanceIDOnly or methods.ExpirationOnly
        end
        if type(dirs) == "table" then
            sortDirection = dirs.Normal
        end
        local added = pcall(function()
            strip:AddAuraGroup("main", filter, {
                maxFrameCount = cfg.max,
                sortMethod = sortMethod,
                sortDirection = sortDirection,
                layout = AuraGroupLayout(cfg),
                initializeFrame = function(button)
                    pcall(SkinAuraButton, button, cfg)
                end,
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
        if strip.SetAuraGroupCandidateFilters then
            strip:SetAuraGroupCandidateFilters("main", filters)
        end
    end)

    -- Groups must exist before SetUnit: otherwise UNIT_AURA is never registered.
    local unit = CT.PickCoTank()
    if unit and strip.SetUnit then
        pcall(function() strip:SetUnit(unit) end)
    end
    if strip.UpdateAllAuras then pcall(strip.UpdateAllAuras, strip) end
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

    ApplyBarTextures(row, ct)
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
        -- SetStatusBarColor writes vertex colour and wipes SetGradient. Re-apply the gradient
        -- every paint instead of colouring the bar white (which is what a wiped gradient looks like).
        if ct.gradient and ApplyHealthGradient(row.health, ct, fillAlpha) then
            row.health.kartGradientActive = true
        else
            row.health.kartGradientActive = false
            row.health:SetStatusBarColor(r, g, b, fillAlpha)
        end
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
    -- Preview and test mode cannot target Testtank, so they demo the border whenever it is on.
    local demo = row == CT.previewRow or CT.Invented()
    local targeted = tb.show and (demo or (CT.watchedUnit and UnitIsUnit("target", CT.watchedUnit)))
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
        CT.RefreshSwapLine()
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
        row:Show()
        CT.ApplyLayout()
    end
    CT.SyncStripUnits(row, unit)

    CT.SyncRowUnitEvents(row, unit)

    CT.snap = CT.snap or {}
    CT.BlankSnapshot(CT.snap)
    if invented or (not unit and KART.IsEditModeActive and KART.IsEditModeActive()) then
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
    CT.RefreshSwapLine()
    if KART.IsEditModeActive and KART.IsEditModeActive() and KART.RefreshEditModeChrome then
        KART.RefreshEditModeChrome()
    end
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
    if CT.UpdateFlyoutVisibility then CT.UpdateFlyoutVisibility() end
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
    if CT.SyncRootWidgets then CT.SyncRootWidgets() end
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
    setChecked(KART.CbCtGradient, ct.gradient == true)
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
        setChecked(KART.CbCtHideLongDuration, debuffs.hideLongDuration == true)
        setChecked(KART.CbCtHideFatigue, debuffs.hideFatigue ~= false)
        setSlider(KART.SldCtDebuffMax, debuffs.max)
        setSlider(KART.SldCtDebuffSize, debuffs.size)
        setSlider(KART.SldCtDebuffSpacing, debuffs.spacing)
    end

    local buffs = ct.buffs
    if buffs then
        setChecked(KART.CbCtBuffShow, buffs.show)
        setChecked(KART.CbCtHideLongBuffs, buffs.hideLongDuration ~= false)
        setSlider(KART.SldCtBuffMax, buffs.max)
        setSlider(KART.SldCtBuffSize, buffs.size)
        setSlider(KART.SldCtBuffSpacing, buffs.spacing)
    end

    local taunt = ct.taunt
    if taunt then
        setChecked(KART.CbCtTauntAnnounce, taunt.announce)
        setChecked(KART.CbCtTauntOnlyGroup, taunt.onlyInGroup ~= false)
        setChecked(KART.CbCtTauntOnlyDungeon, CT.TauntWantsDungeon(taunt))
        setChecked(KART.CbCtTauntOnlyRaid, CT.TauntWantsRaid(taunt))
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
        local sl = taunt.swapLine or {}
        setSlider(KART.SldCtSwapDuration, sl.duration or 3)
        setSlider(KART.SldCtSwapFontSize, sl.fontSize or 24)
        setChecked(KART.CbCtSwapEnabled, sl.enabled ~= false)
        setChecked(KART.CbCtSwapTest, sl.testMode == true)
        setChecked(KART.CbCtSwapOutline, sl.outline ~= false)
        if KART.BtnCtSwapFont and KART.BtnCtSwapFont.text then
            local fontName = sl.fontName or (KART_Settings and KART_Settings.fontName) or "Friz Quadrata"
            KART.BtnCtSwapFont.text:SetText((KART.L and KART.L.BTN_FONT_PREFIX or "Font: ") .. fontName)
        end
        if KART.RefreshSwapSoundChips then KART.RefreshSwapSoundChips() end
        if KART.CtSwapColorPreview and sl.color then
            local c = sl.color
            KART.CtSwapColorPreview:SetColorTexture(c.r or 1, c.g or 0.82, c.b or 0, 1)
        end
    end

    if KART.RefreshCtGradientSwatches then KART.RefreshCtGradientSwatches() end
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

function CT.TauntWantsDungeon(t)
    if not t then return true end
    if t.onlyInDungeon ~= nil then return t.onlyInDungeon ~= false end
    return t.onlyInInstance ~= false
end

function CT.TauntWantsRaid(t)
    if not t then return true end
    if t.onlyInRaid ~= nil then return t.onlyInRaid ~= false end
    return t.onlyInInstance ~= false
end

function CT.ShouldAnnounce()
    local s = KART_Settings
    if not s or s.ctModuleEnabled ~= true then return false end
    local t = s.ct and s.ct.taunt
    if not t or t.announce ~= true then return false end
    if t.onlyInGroup ~= false and not IsInGroup() then return false end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then return false end
    local dungeon = CT.TauntWantsDungeon(t)
    local raid = CT.TauntWantsRaid(t)
    if dungeon or raid then
        if instanceType == "party" then return dungeon end
        if instanceType == "raid" then return raid end
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
    local dest = WhisperDest(cotank)
    if dest and KASC and KASC.Send then
        KASC:Send("CT_ASK:" .. msg, "WHISPER", dest, { prio = "ALERT" })
    end
end

local SWAP_LINE_DEFAULTS = {
    enabled = true,
    fontSize = 24,
    duration = 3,
    outline = true,
    sound = "off",
    testMode = false,
    color = { r = 1, g = 0.82, b = 0 },
    point = "CENTER", relativePoint = "CENTER", x = 0, y = 120,
}

local function SwapLineCfg()
    local t = TauntCfg()
    local s = t and t.swapLine
    if type(s) ~= "table" then return {} end
    return s
end

local function SwapLineOpt(key)
    local s = SwapLineCfg()
    if s[key] ~= nil then return s[key] end
    return SWAP_LINE_DEFAULTS[key]
end

local function SwapLinePreviewing()
    if KART.IsEditModeActive and KART.IsEditModeActive() then return true end
    return SwapLineOpt("testMode") == true
end

local function SwapLineSampleText()
    local t = TauntCfg() or {}
    local template = t.ask
    if not template or template == "" then template = TAUNT_DEFAULT_ASK end
    local n = ""
    if UnitName then n = PublicString(UnitName("player")) end
    if n == "" then n = "Tank" end
    return CT.FormatTauntMessage(template, { t = "Boss", s = "Taunt", n = n })
end

local function CancelSwapLineTimer()
    if CT.swapLineTimer and CT.swapLineTimer.Cancel then
        CT.swapLineTimer:Cancel()
    end
    CT.swapLineTimer = nil
end

local function SwapLineColor()
    local c = SwapLineOpt("color")
    if type(c) ~= "table" then c = SWAP_LINE_DEFAULTS.color end
    return c.r or 1, c.g or 0.82, c.b or 0
end

function CT.EnsureSwapLine()
    local f = CT.swapLine
    if f and f.GetWidth then return f end
    f = CreateFrame("Frame", "KART_TauntSwapLine", UIParent)
    f:SetSize(400, 32)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    f.text = text
    -- A FontString has no pixels of its own. Without a region, EnableMouse still lets
    -- clicks fall through to the Edit Mode dim.
    local hit = f:CreateTexture(nil, "BACKGROUND")
    hit:SetAllPoints(f)
    if hit.SetColorTexture then hit:SetColorTexture(0, 0, 0, 0.01) end
    f.hit = hit
    f:SetScript("OnDragStart", function(self)
        if SwapLinePreviewing() and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        local t = TauntCfg()
        if not t then return end
        t.swapLine = t.swapLine or {}
        t.swapLine.point = point
        t.swapLine.relativePoint = relativePoint
        t.swapLine.x = xOfs
        t.swapLine.y = yOfs
    end)
    CT.swapLine = f
    if KART.RegisterEditModeFrame then
        KART.RegisterEditModeFrame(f, "EDIT_MODE_LABEL_TAUNT_SWAP")
    end
    return f
end

function CT.StyleSwapLine()
    local f = CT.EnsureSwapLine()
    local size = tonumber(SwapLineOpt("fontSize")) or SWAP_LINE_DEFAULTS.fontSize
    if size < 12 then size = 12 end
    if size > 48 then size = 48 end
    local outline = SwapLineOpt("outline")
    if outline == nil then outline = true end
    local flags = outline ~= false and "OUTLINE" or ""
    local cfg = SwapLineCfg()
    local fontName = cfg.fontName
    if not fontName and KART_Settings then fontName = KART_Settings.fontName end
    local path = "Fonts\\FRIZQT__.TTF"
    local ui = KART.UI
    if ui and ui.GetFontPath then
        path = ui:GetFontPath(fontName) or path
    end
    if f.text.SetFont then f.text:SetFont(path, size, flags) end
    f.text:SetTextColor(SwapLineColor())
    local w = 200
    if f.text.GetStringWidth then
        w = math.max(200, (f.text:GetStringWidth() or 0) + 16)
    end
    f:SetSize(w, size + 8)
    local point = SwapLineOpt("point")
    local rel = SwapLineOpt("relativePoint")
    local x = SwapLineOpt("x")
    local y = SwapLineOpt("y")
    f:ClearAllPoints()
    f:SetPoint(point or "CENTER", UIParent, rel or "CENTER", x or 0, y or 120)
    local edit = SwapLinePreviewing()
    f:EnableMouse(edit and true or false)
    if f.hit then
        if edit then f.hit:Show() else f.hit:Hide() end
    end
    return f
end

local function SwapLineSafeText(msg)
    if type(msg) ~= "string" then return "" end
    return msg:gsub("|", "||")
end

function CT.RefreshSwapLine()
    if SwapLineOpt("enabled") == false then
        CancelSwapLineTimer()
        if CT.swapLine then CT.swapLine:Hide() end
        return
    end
    local preview = SwapLinePreviewing()
    if not preview and not (CT.swapLine and CT.swapLine:IsShown() and CT.swapLineTimer) then
        if CT.swapLine then CT.swapLine:Hide() end
        return
    end
    local f = CT.StyleSwapLine()
    if preview then
        CancelSwapLineTimer()
        f.text:SetText(SwapLineSafeText(SwapLineSampleText()))
        CT.StyleSwapLine()
        f:Show()
        if KART.IsEditModeActive and KART.IsEditModeActive() and KART.RefreshEditModeChrome then
            KART.RefreshEditModeChrome()
        end
    end
end

function CT.ShowSwapLine(msg)
    if type(msg) ~= "string" or msg == "" then return end
    if SwapLineOpt("enabled") == false then
        CancelSwapLineTimer()
        if CT.swapLine then CT.swapLine:Hide() end
        return
    end
    local f = CT.StyleSwapLine()
    f.text:SetText(SwapLineSafeText(msg))
    CT.StyleSwapLine()
    f:Show()
    local sound = SwapLineOpt("sound")
    local kit = SOUNDKIT
    if sound == "warning" then
        PlaySound((kit and kit.RAID_WARNING) or 8959)
    elseif sound == "ready" then
        PlaySound((kit and kit.READY_CHECK) or 8960)
    end
    if SwapLinePreviewing() then return end
    CancelSwapLineTimer()
    local dur = tonumber(SwapLineOpt("duration")) or SWAP_LINE_DEFAULTS.duration
    if dur < 1 then dur = 1 end
    if dur > 10 then dur = 10 end
    if C_Timer and C_Timer.NewTimer then
        CT.swapLineTimer = C_Timer.NewTimer(dur, function()
            CT.swapLineTimer = nil
            if SwapLinePreviewing() then return end
            if CT.swapLine then CT.swapLine:Hide() end
        end)
    end
end

if KASC and not KASC._kartCtAsk then
    KASC._kartCtAsk = true
    -- Reviewed 2026-08: every group member, Co-Tank module off included. See REVIEW-DECISIONS.md.
    KASC:RegisterMessage("CT_ASK", { payload = true, group = true }, function(payload)
        if CT.ShowSwapLine then CT.ShowSwapLine(payload) end
    end)
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
    if KART.IsEditModeActive and KART.IsEditModeActive() and not INSTANCE_OK[instanceType] then
        return true
    end
    if t.locked == false and not INSTANCE_OK[instanceType] then return true end
    if s.ct and s.ct.testMode then return true end
    if t.buttonOnlyInGroup ~= false and not IsInGroup() then return false end
    if t.buttonOnlyInRaid == true and not IsInRaid() then return false end
    return CT.PickCoTank() ~= nil
end

local function AskButtonLabel()
    local L = KART.L
    if L and type(L.BTN_CT_TAKE_IT) == "string" and L.BTN_CT_TAKE_IT ~= "" then
        return L.BTN_CT_TAKE_IT
    end
    return "Take it"
end

local function StyleAskButton(btn)
    if not btn or btn.text then return end
    if btn.icon then btn.icon:Hide() end
    if btn.bg then btn.bg:Hide() end
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        local r, g, b = 0.79, 0.64, 0.15
        local ui = KART.UI
        if ui and ui.AccentColor then
            r, g, b = ui:AccentColor()
        end
        btn:SetBackdropBorderColor(r, g, b, 1)
    end
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    btn.text = text
    local ui = KART.UI
    if ui and ui.RegisterButtonText then
        ui:RegisterButtonText(text)
    end
end

function CT.EnsureAskButton()
    local btn = CT.askBtn
    if not (btn and btn.GetWidth) then
        CT.askBtn = nil
        btn = CreateFrame("Button", "KART_CoTankAskButton", UIParent, "BackdropTemplate")
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
            local editMode = KART.IsEditModeActive and KART.IsEditModeActive()
            if t and (t.locked == false or editMode) and not InCombatLockdown() then
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
        if KART.RegisterEditModeFrame then
            KART.RegisterEditModeFrame(btn, "EDIT_MODE_LABEL_TAUNT")
        end
    end
    StyleAskButton(btn)
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
    if btn.text then
        local ui = KART.UI
        local fontSize = (ui and ui.lastContentSize) or 12
        if btn.text.SetFont then btn.text:SetFont(ContentFontPath(), fontSize, "") end
        btn.text:SetText(AskButtonLabel())
    end
    if btn.icon then btn.icon:Hide() end
    local width = size
    if btn.text and btn.text.GetStringWidth then
        width = math.max(size, (btn.text:GetStringWidth() or 0) + 16)
    end
    btn:SetSize(width, size)
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
