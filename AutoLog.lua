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
    local name, instanceType, difficultyID, difficultyName = GetInstanceInfo()
    -- The open world is not content, whatever difficultyID it reports there. Deciding on the ID
    -- alone made this depend on an unstated assumption about what GetInstanceInfo answers outside an
    -- instance -- and the table below claims 1 for Normal dungeons, which is exactly the value that
    -- assumption is about. Anyone with the dungeon toggle on would have been logging while flying
    -- around a capital city, for hours, with a file to match.
    --
    -- "Not the world" rather than an allow-list of party/raid: delves are in the table (208) and do
    -- not report either of those, so the stricter rule would have quietly stopped logging them while
    -- looking like the safer choice.
    if instanceType == "none" then return false end
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
    -- Ownership can go stale: LoggingCombat() resets on logout but autoLogOwned (a SavedVariable)
    -- persists, so a log that ended outside our control leaves us falsely "owning" nothing. If we
    -- think we own the log but nothing is actually logging, drop the claim before deciding anything —
    -- otherwise a later manually-started log gets wrongly stopped as if it were ours.
    if KART_Settings.autoLogOwned and not LoggingCombat() then
        KART_Settings.autoLogOwned = false
    end
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
