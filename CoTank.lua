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
    if CT.pendingUnit and CT.row then
        CT.ApplySecureUnit(CT.row, CT.pendingUnit)
    end
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

function CT.EnsureRow()
    if CT.row then return CT.row end
    CT.row = {
        shown = false,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        SetAttribute = function() end,
        SetAlpha = function() end,
    }
    return CT.row
end

function CT.Refresh()
    if not CT.ShouldShow() then
        if CT.row then
            CT.row:Hide()
        end
        return
    end
    local row = CT.EnsureRow()
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
        for _, event in ipairs(CT_EVENTS) do
            f:RegisterEvent(event)
        end
        CT.events = f
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
