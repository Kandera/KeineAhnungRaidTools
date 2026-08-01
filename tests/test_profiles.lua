-- Settings profiles: saving a snapshot, loading one back, deleting it.
--
-- Small file, large blast radius: KART.LoadProfile WIPES KART_Settings before it writes anything
-- back, so anything that goes wrong after that line costs the player every setting they have. It had
-- no test.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
env.KART_Profiles = {}
local KART = { L = {}, Defaults = {} }
env.KART = KART

-- The two things Profiles.lua reaches out to. SyncSettingsToUI lives in Core.lua, which the harness
-- cannot load; ReloadUI is the game's. Both are recorded so the language branch is observable.
local synced, reloaded = 0, 0
function env.ReloadUI() reloaded = reloaded + 1 end
KART.SyncSettingsToUI = function() synced = synced + 1 end
function env.LoggingCombat() return env.KARTTEST_logging or false end
KART.UI = { ShowInputDialog = function() end, RegisterStaticPopup = function() end }

do
    local chunk = assert(loadstring(assert(io.open("Profiles.lua", "r")):read("*a"), "@Profiles.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
for _, fn in ipairs({ "SaveProfile", "LoadProfile", "DeleteProfile" }) do
    setfenv(KART[fn], env)
end

KART.Defaults = { lcVoteSeconds = 20, minimap = { hide = false }, language = "auto" }

local function Settings(t)
    env.KART_Settings = {}
    for k, v in pairs(t) do env.KART_Settings[k] = v end
    return env.KART_Settings
end

-- Save and load ------------------------------------------------------------------------------------
do
    Settings({ lcVoteSeconds = 45, inviteKeywords = "inv" })
    KART.SaveProfile("raid")
    T.eq(env.KART_Settings.activeProfile, "raid", "saving makes that profile the active one")

    env.KART_Settings.lcVoteSeconds = 10
    KART.LoadProfile("raid")
    T.eq(env.KART_Settings.lcVoteSeconds, 45, "loading brings the saved value back")
    T.eq(env.KART_Settings.activeProfile, "raid", "and the profile is active again")
end

do
    -- A profile predates a setting that exists now: the load must not leave that key missing, or
    -- every reader of it falls into whatever nil means for them.
    Settings({ lcVoteSeconds = 45 })
    KART.SaveProfile("old")
    KART.Defaults.aBrandNewSetting = "on"
    KART.LoadProfile("old")
    T.eq(env.KART_Settings.aBrandNewSetting, "on",
        "a key the profile predates is filled in from the defaults")
    KART.Defaults.aBrandNewSetting = nil
end

do
    -- The saved snapshot is a COPY. Editing settings afterwards must not reach back into it, or
    -- "load the profile" would mean "load whatever I have now".
    Settings({ lcVoteSeconds = 45, minimap = { hide = false } })
    KART.SaveProfile("copy")
    env.KART_Settings.lcVoteSeconds = 99
    env.KART_Settings.minimap.hide = true
    KART.LoadProfile("copy")
    T.eq(env.KART_Settings.lcVoteSeconds, 45, "the snapshot kept its own value")
    T.eq(env.KART_Settings.minimap.hide, false, "including inside nested tables")
end

do
    -- LibDBIcon holds a REFERENCE to the minimap sub-table it was registered with at load. If a
    -- profile load replaces that table, every later icon-position change is written into an orphan
    -- and lost at the next reload.
    Settings({ minimap = { hide = false } })
    local registered = env.KART_Settings.minimap
    KART.SaveProfile("icon")
    KART.LoadProfile("icon")
    T.truthy(env.KART_Settings.minimap == registered,
        "the minimap table keeps its identity across a profile load")
end

-- Runtime state that is not a preference ------------------------------------------------------------
do
    -- autoLogOwned only means "KART started the log running right now". Restoring a stored true over
    -- a session that started no log would later have AutoLog stop a log the player began by hand.
    Settings({ autoLogOwned = true })
    KART.SaveProfile("logging")
    env.KARTTEST_logging = false
    KART.LoadProfile("logging")
    T.eq(env.KART_Settings.autoLogOwned, false,
        "a stored log claim is re-derived from what is actually running, not restored")
end

-- The language branch --------------------------------------------------------------------------------
do
    Settings({ language = "deDE" })
    KART.SaveProfile("german")
    synced, reloaded = 0, 0
    KART.LoadProfile("german")
    T.eq(reloaded, 0, "loading a profile with the same language does not reload")
    T.eq(synced, 1, "it just pushes the values into the widgets")

    env.KART_Settings.language = "enUS"
    synced, reloaded = 0, 0
    KART.LoadProfile("german")
    T.eq(reloaded, 1, "a different language needs the reload that applies it")
    T.eq(synced, 0, "and does not also push values that the reload is about to redo")
end

-- Deleting ---------------------------------------------------------------------------------------------
do
    Settings({ lcVoteSeconds = 45 })
    KART.SaveProfile("gone")
    KART.DeleteProfile("gone")
    T.is_nil(env.KART_Profiles["gone"], "the snapshot is removed")
    T.is_nil(env.KART_Settings.activeProfile, "and it is no longer the active profile")
    T.eq(env.KART_Settings.lcVoteSeconds, 45,
        "but the settings currently loaded are untouched -- deleting a profile is not a reset")
end

do
    Settings({ lcVoteSeconds = 45 })
    KART.SaveProfile("keep")
    KART.SaveProfile("other")
    KART.DeleteProfile("keep")
    T.eq(env.KART_Settings.activeProfile, "other",
        "deleting a profile that is not the active one leaves the active one alone")
end

-- What a SavedVariables file can come back as -----------------------------------------------------------
do
    -- KART_Profiles is a SavedVariable: hand-edited, half-written after a crash, or touched by
    -- another addon. LoadProfile wipes KART_Settings BEFORE it copies anything in, so anything that
    -- throws after that line costs the player every setting they have -- and pairs() on a string
    -- throws.
    Settings({ lcVoteSeconds = 45, inviteKeywords = "inv" })
    env.KART_Profiles["broken"] = "not a table"
    KART.LoadProfile("broken")
    T.eq(env.KART_Settings.lcVoteSeconds, 45, "a profile that is not a table is refused")
    T.eq(env.KART_Settings.inviteKeywords, "inv", "and nothing is lost in the attempt")

    KART.LoadProfile("never saved")
    T.eq(env.KART_Settings.lcVoteSeconds, 45, "and so is one that does not exist")
end
