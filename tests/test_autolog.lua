-- Auto Combat Log: when KART turns logging on, and -- far more delicately -- when it is allowed to
-- turn it back off.
--
-- Getting the stop wrong is the expensive direction. A log the player started by hand and KART stops
-- is a raid night with no Warcraft Logs upload, and nobody notices until the next morning. It had no
-- test: LoggingCombat, SetCVar and C_ChallengeMode were all absent from the harness, so
-- KART.AutoLog.Evaluate had never run a line.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = { L = { MSG_AL_STARTED = "started %s", MSG_AL_STOPPED = "stopped" } }
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("AutoLog.lua", "r")):read("*a"), "@AutoLog.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
    setfenv(KART.AutoLog.Evaluate, env)
end

local function Where(instanceType, difficultyID, difficultyName, keyLevel)
    KARTTEST.instance = { name = "Somewhere", instanceType = instanceType,
                          difficultyID = difficultyID, difficultyName = difficultyName or "?" }
    KARTTEST.keystoneLevel = keyLevel or 0
end

local function Settings(t)
    env.KART_Settings = { autoLogEnabled = true }
    for k, v in pairs(t) do env.KART_Settings[k] = v end
end

local function Evaluate()
    local realPrint = print
    _G.print = function() end
    KART.AutoLog.Evaluate()
    _G.print = realPrint
    return KARTTEST.logging
end

-- Starting -----------------------------------------------------------------------------------------
do
    Settings({ autoLogRaidMythic = true })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = false
    T.eq(Evaluate(), true, "a mythic raid starts the log when that toggle is on")
    T.eq(env.KART_Settings.autoLogOwned, true, "and KART owns it")
    T.eq(KARTTEST.cvars.advancedCombatLogging, 1,
        "with advanced logging on, without which the upload is unusable")
end

do
    Settings({ autoLogRaidMythic = false, autoLogRaidHeroic = true })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = false
    T.eq(Evaluate(), false, "a difficulty whose toggle is off starts nothing")
    T.truthy(not env.KART_Settings.autoLogOwned, "and nothing is claimed")
end

do
    Settings({ autoLogRaidMythic = true, autoLogEnabled = false })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = false
    T.eq(Evaluate(), false, "the master switch off means nothing happens at all")
end

-- Keystones ----------------------------------------------------------------------------------------
do
    Settings({ autoLogMythicPlus = true, autoLogMinKey = 10 })
    Where("party", 8, "Mythic Keystone", 12)
    KARTTEST.logging = false
    T.eq(Evaluate(), true, "a key at or above the minimum starts the log")

    Settings({ autoLogMythicPlus = true, autoLogMinKey = 10 })
    Where("party", 8, "Mythic Keystone", 7)
    KARTTEST.logging = false
    T.eq(Evaluate(), false, "and one below it does not")
end

do
    -- A keystone run is a keystone run: with M+ off it must not fall through to the plain dungeon
    -- toggle and start logging anyway.
    Settings({ autoLogMythicPlus = false, autoLogDungeons = true })
    Where("party", 8, "Mythic Keystone", 12)
    KARTTEST.logging = false
    T.eq(Evaluate(), false, "M+ switched off does not log through the dungeon toggle")
end

-- Out in the world ------------------------------------------------------------------------------------
-- Where the player spends most of their time, and where an accidental log runs for hours. The
-- decision reads GetInstanceInfo's difficultyID; what that ID is outside an instance is an
-- assumption about somebody else's API, so the instanceType is checked rather than assumed.
do
    Settings({ autoLogDungeons = true, autoLogRaidMythic = true })
    Where("none", 0, "")
    KARTTEST.logging = false
    T.eq(Evaluate(), false, "standing in the open world starts nothing")
end

do
    Settings({ autoLogDungeons = true })
    Where("none", 1, "Normal")
    KARTTEST.logging = false
    T.eq(Evaluate(), false,
        "and still nothing if the world reports a difficulty that also names a dungeon")
end

do
    -- Delves report a scenario-shaped instance and ARE in the difficulty table (208), so the guard
    -- has to be "not the open world" and not an allow-list of party/raid -- the stricter rule would
    -- have quietly stopped logging delves while looking like the safer choice.
    Settings({ autoLogDelves = true })
    Where("scenario", 208, "Delve")
    KARTTEST.logging = false
    T.eq(Evaluate(), true, "a delve still logs, whatever instance type it reports")
end

-- Stopping, which is the direction that costs a raid night ---------------------------------------------
do
    -- KART's own log, in content that no longer matches: its to start, so its to stop.
    Settings({ autoLogRaidMythic = true })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = false
    Evaluate()
    Where("none", 0, "")
    T.eq(Evaluate(), false, "leaving the content stops the log KART started")
    T.truthy(not env.KART_Settings.autoLogOwned, "and drops the claim with it")
end

do
    -- The one that matters: a log the PLAYER started. KART never claimed it, so KART never stops it
    -- -- otherwise a raid night ends with no upload and nobody notices until the next morning.
    Settings({ autoLogRaidMythic = false })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = true
    env.KART_Settings.autoLogOwned = false
    T.eq(Evaluate(), true, "a log the player started by hand is left running")

    Where("none", 0, "")
    T.eq(Evaluate(), true, "even after leaving the instance entirely")
end

do
    -- ...and KART does not quietly adopt one either. Walking into matching content while the player
    -- is already logging must not make it KART's to stop later.
    Settings({ autoLogRaidMythic = true })
    Where("raid", 16, "Mythic")
    KARTTEST.logging = true
    env.KART_Settings.autoLogOwned = false
    Evaluate()
    T.truthy(not env.KART_Settings.autoLogOwned, "a log already running is not adopted")

    Where("none", 0, "")
    T.eq(Evaluate(), true, "so it is still not stopped on the way out")
end

do
    -- A stale claim: autoLogOwned is a SavedVariable and survives a logout, LoggingCombat does not.
    -- Left standing, the next log the player starts by hand would be stopped as if it were ours.
    Settings({ autoLogRaidMythic = true })
    Where("none", 0, "")
    KARTTEST.logging = false
    env.KART_Settings.autoLogOwned = true
    Evaluate()
    T.truthy(not env.KART_Settings.autoLogOwned,
        "a claim over a log that is not running is dropped")

    KARTTEST.logging = true       -- the player starts one by hand afterwards
    T.eq(Evaluate(), true, "so their own log survives the next evaluation")
end
