-- The right-click menu on a council row -- the control the loot actually goes out through.
--
-- It was unreachable from the suite: MenuUtil.CreateContextMenu was an empty stub, so the function
-- that builds these four entries had never run. What it decides is not decoration:
--
--   * "Change vote" edits which vote is SHOWN for a player -- somebody who called their answer out
--     on voice, or whispered it. It must never hand out the item. The two live one menu entry
--     apart, and the one that assigns announces to the whole raid and moves the item into the
--     winner's name.
--   * "Assign without reason" is the same assignment with an empty reason, which is what ends up in
--     the loot history for good.
--
-- Assigning is open to the entire council on purpose (docs/OWNERSHIP.md, and the standing decision
-- quoted at LootCouncil.lua's loot-owner section) -- the row right-click is deliberately ungated, so
-- there is no permission assertion here to make.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim, lm = F.NewRaid()
local Council = lm.KART.LC.Council
local LC = lm.KART.LC
local L = lm.KART.L

local alric = sim.byName.Alric
local ROLL = 60

F.Drop(sim, ROLL, F.GLOVES)

local function OpenMenu(voteDef)
    RaidSim.As(lm, function()
        Council.ShowAssignMenu(lm.KART.LC.councilPanel, ROLL, alric.guid, "Alric", voteDef)
    end)
end

-- What the menu offers -----------------------------------------------------------------------------
do
    OpenMenu(nil)
    local labels = KARTTEST.MenuLabels()
    T.eq(#labels, 4, "the row menu offers four actions")
    T.eq(labels[1], L.LC_MENU_ASSIGN, "assign first")
    T.eq(labels[2], L.LC_MENU_CHANGE_VOTE, "then change vote")
    T.eq(labels[3], L.LC_MENU_ASSIGN_NO_REASON, "then assign without a reason")
    T.eq(labels[4], L.LC_MENU_EDIT_NOTE, "and the officer note")

    -- The change-vote entry is a submenu, and it must carry the raid's CONFIGURED buttons -- an
    -- empty one is a dead menu entry, and a stale one corrects a vote to a reason nobody voted.
    local subs = KARTTEST.SubmenuLabels(L.LC_MENU_CHANGE_VOTE)
    local config = RaidSim.As(lm, LC.GetButtonConfig)
    T.eq(#subs, #config, "the change-vote submenu has one entry per configured vote button")
    for i, def in ipairs(config) do
        T.eq(subs[i], def.label, "in the configured order: " .. tostring(def.label))
    end
end

-- Changing a vote assigns nothing ------------------------------------------------------------------
-- The one thing this file exists for. Both entries sit in the same menu, one row apart.
do
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu(nil)
    local config = RaidSim.As(lm, LC.GetButtonConfig)
    local first = config[1] and config[1].label
    T.truthy(RaidSim.As(lm, function() return KARTTEST.ClickMenu(first) end),
        "a vote can be corrected from the submenu")
    local vote = LC.votes[ROLL] and LC.votes[ROLL][alric.guid]
    T.eq(vote and vote.idx, 1,
        "which records that player's vote as the button that was picked")
    T.eq(LC.assignedWinners[ROLL], nil,
        "and hands out nothing -- correcting a vote is not awarding the item")
end

-- What a corrected vote is stamped with (B102) -----------------------------------------------------
-- Both readers -- the council rows and the "x of y answered" badge -- treat a vote carrying no item
-- and no button fingerprint as one they cannot judge, and show it anyway. That is the right answer
-- for a vote from an older client. It is the wrong one for a vote typed on this very screen, and
-- this was the only writer of the three that stored neither.
do
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu(nil)
    local config = RaidSim.As(lm, LC.GetButtonConfig)
    RaidSim.As(lm, function() KARTTEST.ClickMenu(config[1].label) end)
    local vote = LC.votes[ROLL][alric.guid]

    T.eq(vote.item, LC.rollItems[ROLL]:match("item:(%d+)"),
        "a corrected vote carries the item it was made about")
    T.eq(vote.count, RaidSim.As(lm, LC.ButtonFingerprint),
        "and the button set the index was chosen from")
end

do
    -- Blizzard hands the same rollID to a genuinely different drop within seconds on trash, and the
    -- addon deliberately does not wipe the votes on reuse -- the reader decides, per vote, using the
    -- stamp (B46). An unstamped correction passed that test and was drawn as this raider's answer to
    -- an item they had never been shown.
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu(nil)
    local config = RaidSim.As(lm, LC.GetButtonConfig)
    RaidSim.As(lm, function() KARTTEST.ClickMenu(config[1].label) end)
    T.truthy(RaidSim.As(lm, function() return LC.VoteIsForItem(LC.votes[ROLL][alric.guid], ROLL) end),
        "the correction counts while the tab still holds the item it was made about")

    local before = RaidSim.As(lm, function() return LC.CountVotes(ROLL) end)
    RaidSim.As(lm, function() LC.rollItems[ROLL] = KARTTEST.items[F.WEAPON].link end)
    T.truthy(not RaidSim.As(lm, function() return LC.VoteIsForItem(LC.votes[ROLL][alric.guid], ROLL) end),
        "and stops counting the moment that rollID is reused for another drop")
    T.eq(RaidSim.As(lm, function() return LC.CountVotes(ROLL) end), before - 1,
        "so the answered badge on the new item does not include it either")
    RaidSim.As(lm, function() LC.rollItems[ROLL] = KARTTEST.items[F.GLOVES].link end)
end

do
    -- Same shape, one axis over: the raid leader renames the vote buttons mid-item. An index means
    -- whatever the list says now, so a vote stored without the list it was chosen from is re-labelled
    -- rather than marked unknown (B43, B45).
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu(nil)
    local config = RaidSim.As(lm, LC.GetButtonConfig)
    RaidSim.As(lm, function() KARTTEST.ClickMenu(config[1].label) end)
    local stored = LC.votes[ROLL][alric.guid].count

    T.truthy(not RaidSim.As(lm, function() return LC.VoteLabelStale(stored) end),
        "the correction reads as current while the buttons are untouched")
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "Mainspec;Nebenspec;Verzichte"
    end)
    T.truthy(RaidSim.As(lm, function() return LC.VoteLabelStale(stored) end),
        "and is marked unreadable once the labels change under it, rather than silently re-captioned")
    RaidSim.As(lm, function() lm.env.KART_Settings.lcButtonLabels = nil end)
end

-- Assigning ----------------------------------------------------------------------------------------
do
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu({ label = "BIS", r = 1, g = 0.2, b = 0.2 })
    T.truthy(RaidSim.As(lm, function() return KARTTEST.ClickMenu(L.LC_MENU_ASSIGN) end),
        "assign is clickable")
    T.eq(LC.assignedWinners[ROLL], alric.guid, "and the item goes to the row's player")

    local logged = lm.env.KART_LootHistory[#lm.env.KART_LootHistory]
    T.eq(logged and logged.reason, "BIS",
        "logged under the vote the row was showing, which is what the council decided on")
end

do
    -- Same assignment, no reason. The history entry is the permanent record, so an empty reason has
    -- to arrive as empty rather than as the previous item's.
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    OpenMenu({ label = "BIS", r = 1, g = 0.2, b = 0.2 })
    T.truthy(RaidSim.As(lm, function() return KARTTEST.ClickMenu(L.LC_MENU_ASSIGN_NO_REASON) end),
        "assign-without-reason is clickable")
    T.eq(LC.assignedWinners[ROLL], alric.guid, "the item still goes to that player")

    local logged = lm.env.KART_LootHistory[#lm.env.KART_LootHistory]
    T.eq(logged and logged.reason, "",
        "with no reason recorded, rather than the vote definition the row happened to carry")
end

-- The officer note ---------------------------------------------------------------------------------
do
    OpenMenu(nil)
    RaidSim.As(lm, function() KARTTEST.ClickMenu(L.LC_MENU_EDIT_NOTE) end)
    RaidSim.As(lm, function()
        lm.KART.LC.OfficerNotes.SetOfficerNote(alric.guid, "has the tier piece")
    end)
    T.eq(lm.env.KART_LCOfficerNotes[alric.guid], "has the tier piece",
        "the note is written against the row's player, not the name shown on it")
end
