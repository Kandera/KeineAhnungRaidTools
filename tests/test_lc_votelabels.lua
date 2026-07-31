-- What a vote MEANS depends on the button set it was cast against, and that set can change under it.
--
-- B25 was the original: an index alone, resolved against a different-length list, renders as a
-- confident label for a choice nobody made -- and a whole evening was scored that way. The count was
-- added for it. B43 to B45 are what the count does not cover.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- B43: a SAME-LENGTH rename slips past a count ----------------------------------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 40, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(40, 2) end)

    local before = lm.KART.LC.votes[40][raider.guid]
    T.truthy(before, "the vote arrived")
    T.eq(before.idx, 2, "as the index that was pressed")

    local countBefore = #RaidSim.As(lm, lm.KART.LC.GetButtonConfig)

    -- The config owner renames one button mid-roll. Same number of buttons, so a count-based guard
    -- sees nothing at all -- and index 2 now points at a label the raider never clicked.
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "BIS;Mainspec;Offspec;Sonstiges;Pass"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(#RaidSim.As(lm, lm.KART.LC.GetButtonConfig), countBefore,
        "the list is exactly as long as it was, so a count guard sees nothing")
    T.truthy(RaidSim.As(lm, function() return lm.KART.LC.ButtonFingerprint() end) ~= before.count,
        "but the fingerprint of the SET has changed, which is what the guard now compares")
end

-- B45: the voter's own badge is withheld once the set changed under them --------------------------
do
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 41, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(41, 2) end)

    local castFp = raider.KART.LC.votedFpByMe[41]
    T.truthy(castFp, "the raider remembers which button set they voted against")
    T.eq(castFp, RaidSim.As(raider, function() return raider.KART.LC.ButtonFingerprint() end),
        "which is the one in force at the time")

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "BIS;Mainspec;Offspec;Sonstiges;Pass"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    T.truthy(castFp ~= RaidSim.As(raider, function() return raider.KART.LC.ButtonFingerprint() end),
        "after the edit their stored fingerprint no longer matches the live set")
    T.eq(raider.KART.LC.votedByMe[41], 2, "their index is still recorded")

    -- The badge, the council rows and the tab tooltip all ask the same question, and none of the
    -- three is reachable from this harness -- the vote list and the panel need the real UI. So the
    -- RULE they share is what is asserted, which is also what stopped them disagreeing: the tooltip
    -- used to skip the check entirely and state as fact the vote the rows rendered as "?".
    T.truthy(RaidSim.As(raider, function()
        return raider.KART.LC.VoteLabelStale(castFp, raider.KART.LC.GetButtonConfig())
    end), "so the label is withheld rather than named")
end

do
    local sim = F.NewRaid()
    local raider = sim.byName.Alric
    local live = RaidSim.As(raider, function() return raider.KART.LC.ButtonFingerprint() end)
    T.truthy(not RaidSim.As(raider, function()
        return raider.KART.LC.VoteLabelStale(live, raider.KART.LC.GetButtonConfig())
    end), "a vote cast against the set in force is shown normally")
    -- A vote from an older client arrives without a fingerprint. Refusing to show those would turn a
    -- mixed-version raid into a screen full of question marks, which is worse than what it guards.
    T.truthy(not RaidSim.As(raider, function()
        return raider.KART.LC.VoteLabelStale(nil, raider.KART.LC.GetButtonConfig())
    end), "and a vote with no fingerprint at all is not treated as stale")
end

-- B46: a vote for the PREVIOUS item does not land in the new one's tally ---------------------------
-- Blizzard reuses a rollID for a genuinely different drop within seconds on trash, and the guard used
-- to be "is SOME item tracked under this ID".
do
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 42, F.GLOVES)

    -- The raider votes on the gloves, and the message is held on the wire.
    RaidSim.Hold(sim, "LC_VOTE")
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(42, 1) end)

    -- The same rollID comes back for a different item before that vote lands.
    F.Drop(sim, 42, F.WEAPON)
    T.truthy(lm.KART.LC.rollItems[42]:find(tostring(F.WEAPON), 1, true),
        "the lootmaster is now tracking the weapon under that rollID")

    RaidSim.Release(sim, "LC_VOTE")
    KARTTEST.AdvanceTime(0)

    T.is_nil((lm.KART.LC.votes[42] or {})[raider.guid],
        "the stale vote is not counted for the item it was never cast on")
end

do
    -- ...and a vote for the item actually on the table still counts, so the guard is not "drop
    -- everything late".
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 43, F.GLOVES)
    RaidSim.Hold(sim, "LC_VOTE")
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(43, 1) end)
    RaidSim.Release(sim, "LC_VOTE")
    KARTTEST.AdvanceTime(0)
    T.truthy((lm.KART.LC.votes[43] or {})[raider.guid], "a late vote for the CURRENT item still counts")
end

-- The council straw poll carries the same guard ----------------------------------------------------
do
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    F.Drop(sim, 44, F.GLOVES)

    RaidSim.Hold(sim, "LC_CVOTE")
    RaidSim.As(council, function() council.KART.LC.Vote.ToggleCouncilVote(44, alric.guid) end)
    F.Drop(sim, 44, F.WEAPON)
    RaidSim.Release(sim, "LC_CVOTE")
    KARTTEST.AdvanceTime(0)

    T.is_nil((lm.KART.LC.councilVotes[44] or {})[council.guid],
        "a stale council pick does not land on the new item either")
end

-- All three render sites actually ask the rule ----------------------------------------------------
-- The rule above is covered; its WIRING is not, because none of the three sites can be reached from
-- here -- they need the real UI. Checked against the source instead, which is what stops the tooltip
-- quietly going back to resolving the label on its own (B44). If a site moves, this must move too.
do
    local panel = assert(io.open("LootCouncilPanel.lua", "r")):read("*a")
    local _, panelSites = panel:gsub("LC%.VoteLabelStale%(", "")
    T.eq(panelSites, 3, "the council panel asks the rule at all three of its sites")

    local vote = assert(io.open("LootCouncilVote.lua", "r")):read("*a")
    T.truthy(vote:find("LC.VoteLabelStale(", 1, true), "and the voter's own badge asks it too")

    -- Nobody resolves a label straight out of the button list next to a stored fingerprint any more.
    T.truthy(not panel:find("voteData.count ~= LC.ButtonFingerprint", 1, true),
        "and no site compares the fingerprint by hand instead")
end
