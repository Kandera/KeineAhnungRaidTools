-- The stun repair, with Blizzard's handler going FIRST ------------------------------------------
-- KART.OnControlLost carries the claim that handler order "must not matter" (Utils.lua). The
-- existing test in test_lc_chrome.lua only ever runs KART first: OnControlLost opens the window,
-- then the hide arrives and reports itself. This file runs the other order, which is the one the
-- game is more likely to produce -- UIParent registers PLAYER_CONTROL_LOST in its OnLoad, before
-- any addon frame exists.
--
-- New file, and it goes at the END of run.lua on purpose: anything inserted above
-- test_lc_churn.lua shifts the math.random stream those assertions turn on (B70).

local F = dofile("tests/lc_fixture.lua")

do
    local sim = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 610, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local vote = alric.KART.LC.voteListFrame
    T.truthy(vote and vote:IsShown(), "the vote window is up for the item that just dropped")

    -- The only difference from test_lc_chrome.lua: the hide lands before the repair opens its window.
    F.RaidSim.As(alric, function()
        vote:Hide() -- CloseAllWindows_WithExceptions, running before KART's own handler
        alric.KART.OnControlLost()
    end)
    T.truthy(not vote:IsShown(), "Blizzard's close still closes it -- an addon cannot stop that")

    KARTTEST.AdvanceTime(0.1)
    T.truthy(vote:IsShown(), "and the frame after, it is back -- whichever handler ran first")
end
