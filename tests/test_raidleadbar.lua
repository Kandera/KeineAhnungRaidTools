-- The raidlead bar: when it is on screen, and -- the part that reaches outside itself -- when its
-- keys stop being hijacked.
--
-- The bindings are OVERRIDE bindings. They outrank the player's own keybinds for the whole session,
-- so a bar that hides without dropping them leaves whatever key it claimed dead for everything else
-- until a reload. That is the one thing in this file that can break something outside it.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim = F.NewRaid()
local me = sim.byName.Bramor
local KART = me.KART

RaidSim.As(me, function()
    KART.CreateTabTitle = KART.CreateTabTitle or function() end
    local chunk = assert(loadstring(assert(io.open("RaidleadBar.lua", "r")):read("*a"), "@RaidleadBar.lua"))
    setfenv(chunk, me.env)
    chunk("KeineAhnungRaidTools", KART)
end)
T.truthy(KART.RaidleadBar, "the raidlead bar builds")

local function As(fn) return RaidSim.As(me, fn) end
local S = me.env.KART_Settings

-- Visibility -----------------------------------------------------------------------------------
do
    S.showRaidleadBar, S.autoHideRaidleadBar = true, false
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(KART.RaidleadBar:IsShown(), "the bar is shown when the setting is on")

    S.showRaidleadBar = false
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(not KART.RaidleadBar:IsShown(), "and hidden when it is off")
end

do
    -- Auto-hide is about being ALONE, not about the setting. In a group it stays up.
    S.showRaidleadBar, S.autoHideRaidleadBar = true, true
    KARTTEST.solo = {}
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(KART.RaidleadBar:IsShown(), "auto-hide leaves the bar up while in a group")

    KARTTEST.solo = { [me.unit] = true }
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(not KART.RaidleadBar:IsShown(), "and takes it away once alone")
    KARTTEST.solo = {}
    S.autoHideRaidleadBar = false
end

do
    -- The saved position is restored rather than the hard-coded default. A bar that starts hidden
    -- and is shown by this function is the only path that ever applies it.
    S.showRaidleadBar = true
    S.rlBarPoint, S.rlBarRelativePoint, S.rlBarX, S.rlBarY = "BOTTOMLEFT", "BOTTOMLEFT", 120, 240
    As(KART.UpdateRaidleadBarVisibility)
    local point, _, relativePoint, x, y = KART.RaidleadBar:GetPoint()
    T.eq(point, "BOTTOMLEFT", "the bar comes back where it was left")
    T.eq(relativePoint, "BOTTOMLEFT", "anchored the same way")
    T.eq(x, 120, "at the saved offset")
    T.eq(y, 240, "on both axes")
    S.rlBarPoint, S.rlBarRelativePoint, S.rlBarX, S.rlBarY = nil, nil, nil, nil
end

-- Combat ------------------------------------------------------------------------------------------
do
    -- Changing frames in combat is refused by the game, so the function returns early -- and must
    -- leave the bar exactly as it was rather than half-applying anything.
    S.showRaidleadBar = true
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(KART.RaidleadBar:IsShown(), "shown before the pull")

    KARTTEST.inCombat = true
    S.showRaidleadBar = false
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(KART.RaidleadBar:IsShown(), "a setting changed mid-combat does not touch the frame yet")
    KARTTEST.inCombat = false
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(not KART.RaidleadBar:IsShown(), "and takes effect the moment combat ends")
end

-- Override bindings, which outlive the bar ----------------------------------------------------------
do
    S.showRaidleadBar = true
    S.keybinds = { readyCheck = "F1" }
    As(KART.UpdateRaidleadBarVisibility)
    T.truthy(KARTTEST.overrideBindings[KART.RaidleadBar] ~= nil,
        "a shown bar claims its keys")

    S.showRaidleadBar = false
    As(KART.UpdateRaidleadBarVisibility)
    T.eq(KARTTEST.overrideBindings[KART.RaidleadBar], nil,
        "and a hidden bar gives them back, or the key stays dead for everything else all session")
end

do
    -- Reloading mid-pull: the bindings cannot be set in combat, so the bar flags itself and the
    -- PLAYER_REGEN_ENABLED handler re-applies. Without the flag the keys are silently gone until the
    -- player next changes a bind by hand.
    S.showRaidleadBar = true
    KARTTEST.inCombat = false
    As(KART.UpdateRaidleadBarVisibility)
    KARTTEST.overrideBindings = {}
    KART.keybindsPending = nil

    KARTTEST.inCombat = true
    As(KART.ApplyKeybinds)
    T.truthy(KART.keybindsPending, "in combat the bar records that its keys still need applying")

    KARTTEST.inCombat = false
    As(KART.ApplyKeybinds)
    T.truthy(KARTTEST.overrideBindings[KART.RaidleadBar] ~= nil,
        "and they are applied once combat is over")
end

-- Both click transitions are registered, so the CVar cannot decide whether the bar works ------------
-- P1 (docs/BACKLOG-12.1.md), reported from the 12.1 PTR as "kein Icon mehr auf den Kopf per
-- Raidleadbar", with the whole bar inert: 8 raid markers, 8 world markers, Clear World Markers and
-- Ready Check.
--
-- Blizzard gates a secure click on `(down and useOnKeyDown) or (not down and not useOnKeyDown)`, and
-- for an addon's own button useOnKeyDown comes down to ActionButtonUseKeyDown. Register one
-- transition and half the player base gets the one the gate refuses -- the button hovers, holds
-- correct attributes, and does nothing. Register both and exactly one acts whatever the CVar says,
-- which is also why this cannot bring back the double fire the old line was written against.
--
-- Not a 12.1 break: latent for as long as the down-only line existed. 12.1 only shipped a client
-- where the CVar was not 1.
--
-- Checked against the source, like tests/test_core_wiring.lua checks Core.lua's routing. The harness
-- has no secure-button gate to drive, so a behavioural test here could only assert its own stub.
do
    local src = assert(io.open("RaidleadBar.lua", "r")):read("*a")
    local macroBranch = src:match('SetAttribute%("type", "macro"%).-RegisterForClicks%(([^%)]+)%)')
    T.truthy(macroBranch, "the secure macro branch still registers its clicks in one place")
    T.truthy(macroBranch and macroBranch:find("AnyUp", 1, true)
             and macroBranch:find("AnyDown", 1, true),
        "and registers BOTH transitions, so the CVar cannot decide whether the bar works")
end
