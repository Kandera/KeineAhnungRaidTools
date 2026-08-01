-- The "x" on a council tab, and the cursor it follows.
--
-- tests/test_lc_chrome.lua checks this against the SOURCE and says why: "neither is reachable from
-- this harness (both need a real cursor)". That was true because IsMouseOver came from the catch-all
-- and answered with the frame -- truthy for every frame at once, which is not a state a mouse can be
-- in. It is real state now, so the behaviour those source checks stand in for can be exercised.
--
-- Two bugs were paid for here, both in the comments at LootCouncilPanel.lua's tab strip:
--   * hiding the button unconditionally in the tab's OnLeave re-triggered OnEnter next frame, which
--     re-showed it, which re-triggered OnLeave -- a flicker that ate every click before it landed;
--   * the strip re-derives visibility on every refresh, and the panel refreshes every time a vote
--     arrives. With the cursor resting on the x and not on the tab, the next vote hid it away from
--     under the cursor.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim, lm = F.NewRaid()
local LC = lm.KART.LC
local Council = LC.Council

F.Drop(sim, 80, F.GLOVES)
RaidSim.As(lm, Council.RefreshCouncilTabs)

local panel = LC.councilPanel
T.truthy(panel and panel.tabs and panel.tabs[1], "the tab strip has a tab to hover over")

local tab = panel.tabs[1]
local closeBtn = tab.closeBtn
T.truthy(closeBtn, "which carries a close button")

local function Hover(frame) KARTTEST.mouseOver = frame end
local function Fire(frame, script)
    local handler = frame:GetScript(script)
    if handler then RaidSim.As(lm, function() handler(frame) end) end
end

-- Arriving and leaving ------------------------------------------------------------------------------
do
    Hover(tab)
    Fire(tab, "OnEnter")
    T.truthy(closeBtn:IsShown(), "hovering the tab offers its x")

    -- The cursor moves onto the button. WoW's mouse focus is topmost-frame-only, so the TAB's
    -- OnLeave fires here -- and hiding the button in it is what caused the flicker.
    Hover(closeBtn)
    Fire(tab, "OnLeave")
    T.truthy(closeBtn:IsShown(),
        "moving onto the x does not take it away, which is what made it clickable at all")

    -- And away from both.
    Hover(nil)
    Fire(closeBtn, "OnLeave")
    T.truthy(not closeBtn:IsShown(), "leaving both hides it again")
end

do
    -- The other direction: off the button but still on the tab. The button's own OnLeave fires, and
    -- the x has to stay, or it disappears while the cursor is still on the tab it belongs to.
    Hover(tab)
    Fire(tab, "OnEnter")
    Hover(tab)
    Fire(closeBtn, "OnLeave")
    T.truthy(closeBtn:IsShown(), "sliding back from the x onto its tab keeps it shown")
end

-- A refresh under the cursor -------------------------------------------------------------------
-- The council panel is rebuilt every time a vote lands, which during a live decision is constantly.
do
    Hover(closeBtn)
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(closeBtn:IsShown(),
        "a refresh with the cursor on the x leaves it there -- every incoming vote triggers one")

    Hover(tab)
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(closeBtn:IsShown(), "and so does one with the cursor on the tab")

    Hover(nil)
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(not closeBtn:IsShown(), "while a refresh with the cursor elsewhere hides it")
end

-- A recycled tab ---------------------------------------------------------------------------------
-- Tabs are pooled BY POSITION: closing one shifts every later roll onto a different frame without
-- the mouse ever leaving it, so no OnEnter or OnLeave fires. A tab coming back with the previous
-- tab's x already showing means one click closes the wrong roll.
do
    F.Drop(sim, 81, F.WEAPON)
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(panel.tabs[2], "a second drop takes the next tab slot")

    Hover(panel.tabs[2])
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(panel.tabs[2].closeBtn:IsShown(), "hovered, it shows its own x")

    -- The hovered roll is dismissed; the strip shrinks back to one tab.
    RaidSim.As(lm, function() Council.CloseCouncilTab(81) end)
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(not panel.tabs[2]:IsShown(), "the freed tab frame is hidden")
    T.truthy(not panel.tabs[2].closeBtn:IsShown(),
        "and its x with it, so it cannot come back pre-shown on the next roll")
end

KARTTEST.mouseOver = nil
