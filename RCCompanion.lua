local addonName, KART = ...
KART.RC = KART.RC or {}
local RC = KART.RC

function RC.GetAddon()
    return _G.RCLootCouncil
end

function RC.IsRCLoaded()
    local loaded = _G.C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("RCLootCouncil")
    return not not (loaded and RC.GetAddon())
end

function RC.Enable()
    if not RC.IsRCLoaded() then return end
end
