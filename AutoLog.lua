local addonName, KART = ...

-- Auto Combat Log: starts/stops LoggingCombat() based on the content filters configured in
-- the Automation tab. Evaluation is event-driven (PLAYER_ENTERING_WORLD, CHALLENGE_MODE_START
-- routed here from Core.lua) plus re-runs from the settings widgets' callbacks.
KART.AutoLog = {}

-- Maps GetInstanceInfo() difficultyIDs to the settings toggle that must be on for that
-- content. Mythic Keystone runs are detected via the active keystone instead (see below),
-- because the key level filter needs C_ChallengeMode data, not just the difficultyID.
local DIFFICULTY_TOGGLES = {
    [17]  = "autoLogRaidLFR",
    [14]  = "autoLogRaidNormal",
    [15]  = "autoLogRaidHeroic",
    [16]  = "autoLogRaidMythic",
    [1]   = "autoLogDungeons", -- Normal
    [2]   = "autoLogDungeons", -- Heroic
    [23]  = "autoLogDungeons", -- Mythic 0
    [208] = "autoLogDelves",
}

-- Returns match, description. An active keystone run is checked first: on
-- CHALLENGE_MODE_START the difficultyID may not have flipped to 8 (Mythic Keystone) yet,
-- but GetActiveKeystoneInfo() is already valid — and it also covers reconnecting or
-- reloading mid-run via PLAYER_ENTERING_WORLD.
local function MatchContent()
    if not KART_Settings.autoLogEnabled then return false end
    local name, _, difficultyID, difficultyName = GetInstanceInfo()
    local keyLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    if keyLevel and keyLevel > 0 then
        if not KART_Settings.autoLogMythicPlus then return false end
        if keyLevel < (KART_Settings.autoLogMinKey or 2) then return false end
        return true, string.format("%s +%d", name or "M+", keyLevel)
    end
    local toggle = DIFFICULTY_TOGGLES[difficultyID]
    if toggle and KART_Settings[toggle] then
        return true, string.format("%s, %s", name or "?", difficultyName or "?")
    end
    return false
end

function KART.AutoLog.Evaluate()
    if not KART_Settings then return end -- settings not loaded yet (widget init during login)
    local match, desc = MatchContent()
    if match then
        if not LoggingCombat() then
            -- Advanced Combat Logging is required for usable Warcraft Logs uploads; the
            -- checkbox in Blizzard's options only sets this same CVar.
            SetCVar("advancedCombatLogging", 1)
            LoggingCombat(true)
            KART_Settings.autoLogOwned = true
            print("|cff00ff00KART:|r " .. string.format(KART.L.MSG_AL_STARTED, desc))
        end
        -- Already logging but not owned: the player started it manually — leave ownership
        -- (and the later stop decision) with them.
    elseif LoggingCombat() and KART_Settings.autoLogOwned then
        LoggingCombat(false)
        KART_Settings.autoLogOwned = false
        print("|cff00ff00KART:|r " .. KART.L.MSG_AL_STOPPED)
    end
end
