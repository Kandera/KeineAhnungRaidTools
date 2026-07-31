-- The Loot Council windows step aside for the addon's own confirm dialogs.
--
-- Blizzard's StaticPopup frames are stuck at the DIALOG stratum and moving one taints it for the
-- rest of the session, which is what B8's original fix did and why it was taken out again (B55, and
-- the comment on KAUI's RegisterStaticPopup). So the movement happens on our side instead: KAUI
-- clamps the frames it owns while one of our popups is up.
--
-- These windows are NOT among them. They keep their own list and their own stratum setting so the
-- module stays separable for a future split (B22), which means KAUI's clamp cannot reach them and
-- they subscribe with RegisterPopupYielder instead. Without that subscription the Loot Council
-- windows would be the only ones left covering the dialog -- and they are the ones actually in the
-- way, because they are what the player is looking at when the prompt appears.
--
-- The stand-in prompt is why this is worth a test rather than a comment: it is raised while the
-- council panel is open, and a raid whose lootmaster has left waits on somebody pressing a button
-- they cannot see.
--
-- What is assertable offline is whether the frames move and come back. Whether the result then
-- renders on top needs a client.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local _, lm = F.NewRaid()

RaidSim.As(lm, function()
    local LC = lm.KART.LC

    -- DIALOG is the setting that produces the burial: the windows land on the same stratum as
    -- Blizzard's popup frames, and which one draws on top is then not ours to decide.
    lm.env.KART_Settings.lcFrameStrata = 5
    local window, dialog = CreateFrame("Frame"), CreateFrame("Frame")
    LC.RegisterWindow(window)
    LC.RegisterWindow(dialog, true)
    T.eq(window:GetFrameStrata(), "DIALOG", "a Loot Council window follows its own strata setting")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "and its own dialogs sit one above it")

    local def = lm.env.StaticPopupDialogs["KART_LC_STAND_IN"]
    T.truthy(def, "the stand-in prompt is registered")

    -- Stands in for a pooled Blizzard popup frame. Nothing here is ever written to -- that is the
    -- taint that started all of this -- so it only has to be identifiable.
    local popup = {}

    def.OnShow(popup)
    T.eq(window:GetFrameStrata(), "HIGH",
        "the council window comes down while the stand-in prompt is up")
    T.eq(dialog:GetFrameStrata(), "HIGH", "and so does a Loot Council dialog")

    -- A window built while the prompt is up must not appear in front of it either. The vote window
    -- opening on an incoming roll is exactly that case.
    local late = CreateFrame("Frame")
    LC.RegisterWindow(late)
    T.eq(late:GetFrameStrata(), "HIGH", "a window created while the prompt is up is clamped too")

    def.OnHide(popup)
    T.eq(window:GetFrameStrata(), "DIALOG", "the configured stratum is restored when it closes")
    T.eq(dialog:GetFrameStrata(), "FULLSCREEN", "for Loot Council dialogs as well")
    T.eq(late:GetFrameStrata(), "DIALOG", "including the one built while the prompt was up")
end)

-- A setting below DIALOG was never buried, and must not be moved at all -- dropping those windows
-- to HIGH would raise a player who deliberately put them on MEDIUM.
RaidSim.As(lm, function()
    local LC = lm.KART.LC
    lm.env.KART_Settings.lcFrameStrata = 3 -- MEDIUM
    local window = CreateFrame("Frame")
    LC.RegisterWindow(window)
    T.eq(window:GetFrameStrata(), "MEDIUM", "a window configured below DIALOG starts there")

    local def = lm.env.StaticPopupDialogs["KART_LC_STAND_IN"]
    local popup = {}
    def.OnShow(popup)
    T.eq(window:GetFrameStrata(), "MEDIUM", "and stays there while a popup is up -- it was never in the way")
    def.OnHide(popup)
    T.eq(window:GetFrameStrata(), "MEDIUM", "and is unchanged afterwards")
end)

-- The tab's "x" must stay reachable ---------------------------------------------------------------
-- It sits OUTSIDE the tab on purpose, so it cannot be hit while just clicking a tab to switch. That
-- placement leaves a strip between the two where neither is hovered, and it made the button
-- unclickable in practice: moving towards it fired the tab's OnLeave and the x hid. The second half
-- was the refresh -- it re-derives the button's visibility from the hover state, and it runs every
-- time a vote lands, so with the mouse resting ON the x and not on the tab the next vote hid it.
--
-- Neither is reachable from this harness (both need a real cursor), so the two properties the fix
-- rests on are checked against the source. If the tab strip is rewritten, this has to move with it.
do
    local panel = assert(io.open("LootCouncilPanel.lua", "r")):read("*a")

    -- No gap between the two frames, in either direction. A hit-rect widening does NOT count and is
    -- what the first attempt got wrong: IsMouseOver measures the frame RECT, so the checks below
    -- still read "not over" in the strip the cursor has to cross.
    T.truthy(not panel:find("SetHitRectInsets", 1, true),
        "the close button is not merely made clickable over a gap")
    local dx = tonumber(panel:match('tab%.closeBtn:SetPoint%("RIGHT", tab, "LEFT", (%-?%d+),'))
    T.truthy(dx and dx >= 0, "its rect touches or overlaps the tab, so the hover is continuous")
    T.truthy(panel:find("tab.closeBtn:SetShown(tab:IsMouseOver() or tab.closeBtn:IsMouseOver())", 1, true),
        "and a refresh keeps it shown while the cursor is on the button itself")

    -- The hover handlers this depends on are still the ones that check BOTH frames -- hiding
    -- unconditionally in either brought back the show/hide flicker that ate every click.
    local _, bothChecks = panel:gsub("if not tab%.closeBtn:IsMouseOver%(%) then", "")
    T.eq(bothChecks, 1, "the tab's OnLeave still defers to the button's own hover")
    local _, tabChecks = panel:gsub("if not tab:IsMouseOver%(%) then", "")
    T.eq(tabChecks, 1, "and the button's OnLeave defers to the tab's")
end

-- The tab's x is LOCAL, "No Winner" is raid-wide -- and that is deliberate --------------------------
-- Decided by the maintainer after seeing this measured. The two buttons sit next to each other and
-- leave the same empty panel behind, so the difference is easy to forget and worth pinning down:
--
--   * "No Winner" broadcasts LC_RESULT ... NONE. Every client drops the item -- card, vote row,
--     trade obligation, history entry. The raid is finished with it.
--   * the tab's x sends nothing. It means "off my screen", and everybody else keeps the card.
--
-- Leaving it local is the choice: closing a tab drops the roll entirely, and a mis-click that took
-- the item away from the whole raid could not be undone. End Round is the tool that clears
-- everything for everyone, and it is what ends the round.
--
-- What this test exists to stop is somebody quietly making the x broadcast -- or quietly making
-- "No Winner" local -- because the two looked like they should match.
do
    local sim, owner, council = F.NewRaid()
    local corvin, alric = sim.byName.Corvin, sim.byName.Alric
    for _, id in ipairs({ 130, 131, 132, 133 }) do F.Drop(sim, id, F.GLOVES) end

    RaidSim.As(owner, function()
        owner.KART.LC.Council.CloseCouncilTab(130)
        owner.KART.LC.Council.CloseCouncilTab(131)
    end)
    for _, id in ipairs({ 132, 133 }) do
        RaidSim.As(owner, function()
            owner.KART.LC.Trade.AnnounceResult(id, "NONE")
            owner.KART.LH.RemoveHistoryForRoll(id, owner.KART.LC.rollItems[id])
            owner.KART.LC.Trade.ClearWinnerObligations(id)
            owner.KART.LC.Council.CloseCouncilTab(id)
        end)
    end
    KARTTEST.AdvanceTime(0)

    T.eq(#owner.KART.LC.councilTabs, 0, "the panel of whoever pressed them is empty")
    T.deep_eq(council.KART.LC.councilTabs, { 130, 131 },
        "and the rest of the council still holds exactly the two that were dismissed locally")
    T.deep_eq(corvin.KART.LC.councilTabs, { 130, 131 }, "the same two, on every council member")
    T.eq(#alric.KART.LC.voteListRolls, 2, "and the raiders still have those two to answer")

    -- Neither button touches the session. Only Close Session does.
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " is still in the session")
    end

    -- End Round is what finishes it, and it reaches everyone.
    RaidSim.As(owner, owner.KART.LC.EndRound)
    KARTTEST.AdvanceTime(0)
    T.eq(#council.KART.LC.councilTabs, 0, "End Round clears what the local dismissals left behind")
    T.eq(#alric.KART.LC.voteListRolls, 0, "including the raiders' open vote rows")
    T.eq(council.KART.LC.sessionActive, true, "and still leaves the session running")
end
