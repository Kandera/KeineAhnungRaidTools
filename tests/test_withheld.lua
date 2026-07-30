-- The two relevance switches are held OFF and greyed out until the defects behind them are fixed
-- (KART.WithheldSettings; ten backlog entries, B36 to B39, B41, B42, B49 to B51, B54).
--
-- Worth a test rather than a comment because the whole point is that it survives things: a profile
-- that carries the old value, a settings tab rebuilt later, somebody wiring a new call site. A
-- default alone would not do it -- defaults only cover a fresh install.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = {}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("Utils.lua", "r")):read("*a"), "@Utils.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end

T.deep_eq(KART.WithheldSettings, { "lcHideIrrelevant", "lcAutoTransmogVote" },
    "both relevance switches are on the withheld list")

-- The values are FORCED, not merely defaulted --------------------------------------------------
do
    env.KART_Settings.lcHideIrrelevant   = true   -- as a profile switch would leave them
    env.KART_Settings.lcAutoTransmogVote = true
    setfenv(KART.EnforceWithheldSettings, env)
    KART.EnforceWithheldSettings()
    T.eq(env.KART_Settings.lcHideIrrelevant, false, "hiding irrelevant items is forced back off")
    T.eq(env.KART_Settings.lcAutoTransmogVote, false, "and so is the automatic transmog vote")
end

-- Wiring: the enforcement has to run where a value can arrive from outside ----------------------
-- KART.SyncSettingsToUI runs at login and on every profile switch, which are the two ways a value
-- appears that the addon did not just write itself. Checked against the source because Core.lua
-- needs the game to load at all -- if this ever moves, the check must move with it.
do
    local core = assert(io.open("Core.lua", "r")):read("*a")
    local body = core:match("function KART%.SyncSettingsToUI%(%).-\nend\n")
    T.truthy(body, "SyncSettingsToUI was found in Core.lua")
    T.truthy(body and body:find("KART.EnforceWithheldSettings()", 1, true),
        "and it enforces the withheld settings before anything reads them")
end

do
    local settings = assert(io.open("LootCouncilSettings.lua", "r")):read("*a")
    T.truthy(settings:find("KART.WithholdCheckbox(KART.LC.CbHideIrrelevant)", 1, true),
        "the hide-irrelevant checkbox is greyed out")
    T.truthy(settings:find("KART.WithholdCheckbox(KART.LC.CbAutoTransmogVote)", 1, true),
        "and so is the auto-transmog one")
end

-- The control itself: disabled AND visibly dimmed ----------------------------------------------
-- Dimming via alpha rather than a text colour is deliberate: the label is registered with KAUI and
-- every restyle rewrites its colour, so a greyed-out label would quietly go back to looking live.
do
    local disabled = false
    local cb = CreateFrame("CheckButton")
    cb.Disable = function() disabled = true end
    KART.WithholdCheckbox(cb)
    T.truthy(disabled, "the checkbox stops answering clicks")
    T.truthy(cb:GetAlpha() < 1, "and is dimmed")

    KART.WithholdCheckbox(nil) -- must not error before the settings tab has been built
end
