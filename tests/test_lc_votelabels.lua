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

    -- Kept, not dropped: a vote is sent exactly once with no retry, and the two clients need not
    -- disagree about which item is current -- ours may be the stale link. It is the READER that
    -- decides, so a vote that turns out to belong here after all is still here to be counted.
    local stale = (lm.KART.LC.votes[42] or {})[raider.guid]
    T.truthy(stale, "the vote is kept rather than thrown away for good")
    T.truthy(not RaidSim.As(lm, function() return lm.KART.LC.VoteIsForItem(stale, 42) end),
        "but it does not count for the item it was never cast on")
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

    local pick = (lm.KART.LC.councilVotes[44] or {})[council.guid]
    T.truthy(pick, "the council pick is kept too")
    T.truthy((lm.KART.LC.councilVoteItem[44] or {})[council.guid] ~= nil,
        "stamped with the item it was cast for")
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

-- B40: a roll we could never identify does not blind the reused-rollID detector -------------------
-- LC_START can arrive with no itemID, and a client that is dead or out of range has no roll of its
-- own to read a link from either, so it tracks "???". PurgeStaleRoll compares itemIDs, and a "???"
-- has none -- it used to return there, leaving every per-roll table to survive into the NEXT item
-- under the same reused ID. The raider's row then showed a vote for an item they had never seen, and
-- they could never vote again.
do
    local sim, _, _, raider = F.NewRaid()
    F.Drop(sim, 45, F.GLOVES, { noRollFor = { Alric = true } })

    -- Force the state the entry describes: tracked, but never identified.
    raider.KART.LC.rollItems[45] = "???"
    raider.KART.LC.votes[45] = { [raider.guid] = { idx = 1, note = "alte stimme", count = 1 } }

    -- A genuinely different item arrives under the same rollID.
    F.Drop(sim, 45, F.WEAPON)

    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[45]),
        "the new item is tracked properly")
    T.is_nil((raider.KART.LC.votes[45] or {})[raider.guid],
        "and the unidentifiable roll's vote did not survive into it")
end

do
    -- The detector must not have become "purge whenever the link is odd": a roll that IS identified
    -- and matches is left alone, votes and all.
    local sim, lm, _, raider = F.NewRaid()
    F.Drop(sim, 46, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(46, 1) end)
    T.truthy((lm.KART.LC.votes[46] or {})[raider.guid], "the vote is in")

    F.Drop(sim, 46, F.GLOVES)   -- the same item again under the same ID
    T.truthy((lm.KART.LC.votes[46] or {})[raider.guid],
        "a re-announced identical item keeps its votes")
end
