-- The raid changing shape underneath a running session.
--
-- The maintainer's operating reality, in their own words: "In Midnight gibt es mehrere Raids mit
-- wenig Bossen, d.h. dass Leute z.B. schon aus dem Raid porten und in einen anderen gehen während
-- die Lootverteilung startet ist normal. Das muss hier trotzdem funktionieren. [...] Bei uns
-- reloggen Leute oft oder wechseln den Char - ich kann nicht jedes Mal /kart v machen für
-- Settingspush und die Session restarten wenn einer umloggt."
--
-- So the rule these tests hold the addon to is: the session and the config survive every roster
-- change, and anyone who turns up gets both without the lootmaster doing anything.
--
-- One deliberate exception, decided by the maintainer: a late arrival does NOT get pulled into a
-- distribution that is already running. They were not in the raid when the boss died, so they are
-- not eligible for its loot, and putting a vote window in front of them would only invite a vote
-- the council has to throw away.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop, HasVoteRow = F.NewRaid, F.Drop, F.HasVoteRow

local NEWCOMER = { name = "Torvi", realm = "TarrenMill", guid = "Player-1-T", class = "MAGE", locale = "enUS" }

-- Everything that recovers state hangs off GROUP_ROSTER_UPDATE, and two of the three paths are
-- delayed (the state request's reply, the session prompt). Settle both.
local function RosterSettles(sim)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
end

-- ===================================================================================
-- Someone joins mid-session
-- ===================================================================================
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 80, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(80, 1) end)

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)

    T.eq(torvi.KART.LC.sessionActive, true, "a late joiner is in the session without being asked in")
    T.eq(torvi.KART.LC.raidConfig.lootmaster, lm.guid, "and knows who the lootmaster is")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled), true,
        "and uses the RAID's roll setting, not the default they logged in with")
    T.deep_eq(RaidSim.As(torvi, torvi.KART.LC.GetButtonConfig),
              RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
        "and reads the same vote buttons as everyone else")

    -- The maintainer's rule: not eligible for loot from a boss they were not there for.
    T.truthy(not HasVoteRow(torvi, 80), "but is NOT dragged into the distribution already running")

    -- And the raid they walked into is untouched by their arrival. The config re-broadcast that a
    -- roster change triggers passes through every client's HandleConfig, which is a place a
    -- half-written change could plausibly wipe the tracked rolls for everyone at once.
    for _, c in ipairs(sim.clients) do
        if c ~= torvi then
            T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[80]),
                c.name .. " still holds the item that was being distributed")
            T.truthy(HasVoteRow(c, 80), c.name .. " still has their vote row for it")
        end
    end
    T.eq((lm.KART.LC.votes[80] or {})[raider.guid] and lm.KART.LC.votes[80][raider.guid].idx, 1,
        "and the votes already cast are still counted")

    -- The next boss is theirs like anyone else's -- which is the whole point of joining cleanly.
    Drop(sim, 81, F.WEAPON)
    T.truthy(torvi.KART.LC.IsRealItemLink(torvi.KART.LC.rollItems[81]),
        "the joiner sees the NEXT item like everyone else")
    RaidSim.As(torvi, function() torvi.KART.LC.Vote.CastVote(81, 1) end)
    T.truthy((lm.KART.LC.votes[81] or {})[torvi.guid], "and their vote reaches the council")
    T.truthy((lm.KART.LC.rolls[81] or {})[torvi.guid], "and so does their 1-100 roll")

    -- The joiner is now an equal member of the raid, so from the next item on there is nothing
    -- about the raid they may see differently from anyone who was here all along.
    F.AssertAgreed(sim, 81, "including the newcomer, from the item after they arrived")
end

-- The same arrival, with the lootmaster's own roster handler taken out of the picture. Only the
-- joiner's LC_STATE_REQ is left to recover the state -- which is the path that has to work when the
-- lootmaster is busy tanking and their client is not the one that notices anything.
do
    local sim, lm = NewRaid()
    Drop(sim, 82, F.GLOVES)

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RaidSim.As(torvi, function() torvi.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)

    T.eq(torvi.KART.LC.sessionActive, true, "the state request alone gets a joiner into the session")
    T.eq(torvi.KART.LC.raidConfig.lootmaster, lm.guid, "and brings the config with it")
end

-- Whoever turns up mid-evening should be able to see what has already been handed out. The council
-- reads the history to decide who is owed something, so a council member arriving on a swapped
-- character with an empty log would be voting blind on everything left.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 95, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(95, raider.guid, "BIS") end)
    T.eq(#lm.env.KART_LootHistory, 1, "the award is in the lootmaster's own log")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(15)     -- the catch-up replies are spread over several seconds

    T.eq(#torvi.env.KART_LootHistory, 1, "and reaches someone who joined afterwards")
    T.eq(torvi.env.KART_LootHistory[1] and torvi.env.KART_LootHistory[1].winner,
         lm.env.KART_LootHistory[1].winner, "naming the same winner")
    -- Every peer holds that entry and every one of them answers, so the deduplication is the thing
    -- worth asserting -- and it needs the number of answers to compare against, or "one row" says
    -- nothing. (The previous version repeated the line above verbatim and called it a dedup check.)
    T.truthy(#RaidSim.Sent(sim, "LC_HIST_ENTRY") > 1, "more than one peer answered the catch-up")
    T.eq(#torvi.env.KART_LootHistory, 1, "and the joiner still ends up with exactly one row")
end

-- A cross-realm raider. Every message the addon accepts is gated on the sender being in our group,
-- and that check has to handle both spellings: a same-realm player, whose realm the API reports as
-- empty, and a genuine cross-realm one, who is always fully qualified. A raid is normally all on one realm,
-- so the second is the exception -- which is exactly why it needs its own test rather than being the
-- accident the fixture used to be.
do
    local sim, lm = NewRaid()
    local guest = RaidSim.Join(sim, { name = "Fremd", realm = "TarrenMill", guid = "Player-2-F",
                                      class = "ROGUE", locale = "enUS" })
    RosterSettles(sim)

    T.eq(guest.KART.LC.sessionActive, true, "a cross-realm raider joins the session")
    T.eq(guest.KART.LC.raidConfig.lootmaster, lm.guid, "and gets the config")

    Drop(sim, 99, F.GLOVES)
    T.truthy(guest.KART.LC.IsRealItemLink(guest.KART.LC.rollItems[99]), "and sees the item")
    RaidSim.As(guest, function() guest.KART.LC.Vote.CastVote(99, 1) end)
    T.truthy((lm.KART.LC.votes[99] or {})[guest.guid], "and their vote is accepted, not rejected")
    T.truthy((lm.KART.LC.rolls[99] or {})[guest.guid], "and so is their roll")
end

-- ===================================================================================
-- Someone swaps character -- the split-run case
-- ===================================================================================
-- A different character, a different GUID, the same person. Nothing about the old one may linger,
-- and the new one must be a full member of the session immediately.
do
    local sim, lm = NewRaid()
    Drop(sim, 83, F.GLOVES)

    RaidSim.Leave(sim, "Sinja")
    local alt = RaidSim.Join(sim, { name = "Sinjaa", realm = "TarrenMill", guid = "Player-1-SA",
                                    class = "PRIEST", locale = "deDE" })
    RosterSettles(sim)

    T.eq(alt.KART.LC.sessionActive, true, "the swapped-in character is in the session")
    T.eq(alt.KART.LC.raidConfig.lootmaster, lm.guid, "and has the config")
    T.eq(RaidSim.As(alt, alt.KART.LC.GetRollsEnabled), true, "and the raid's roll setting")

    Drop(sim, 84, F.WEAPON)
    RaidSim.As(alt, function() alt.KART.LC.Vote.CastVote(84, 2) end)
    T.eq((lm.KART.LC.votes[84] or {})[alt.guid] and lm.KART.LC.votes[84][alt.guid].idx, 2,
        "and votes under their new identity on the next item")

    -- The raid carried on across the swap.
    T.eq(lm.KART.LC.sessionActive, true, "the lootmaster's session survived the swap")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[83]),
        "and so did the distribution that was running")
end

-- ===================================================================================
-- An ordinary raider relogs mid-session
-- ===================================================================================
-- SavedVariables survive, every scrap of session state does not. Nobody may have to be told to
-- restart anything.
do
    local sim, lm = NewRaid()
    Drop(sim, 85, F.GLOVES)

    local alric = RaidSim.Reload(sim, "Alric")
    T.eq(alric.KART.LC.sessionActive, false, "a client comes back from /reload knowing nothing")
    T.eq(alric.env.KART_Settings.lcAutoTransmogVote, true, "though its own settings survived")

    RosterSettles(sim)

    T.eq(alric.KART.LC.sessionActive, true, "and is back in the session on the next roster change")
    T.eq(alric.KART.LC.raidConfig.lootmaster, lm.guid, "with the config back")
    T.eq(RaidSim.As(alric, alric.KART.LC.GetRollsEnabled), true, "and the raid's roll setting back")
    -- They had already answered Blizzard's roll before reloading (Auto-Pass fires in
    -- LC.OnStartLootRoll), so the roll is gone from their client and the catch-up has nothing to
    -- hand back -- which is right: they answered, the council has their reply. The other case, a
    -- client that was deaf BEFORE it could answer, is restored; see the B66 test further down.
    T.truthy(not HasVoteRow(alric, 85),
        "an item they already answered is not put back in front of them")

    Drop(sim, 86, F.WEAPON)
    RaidSim.As(alric, function() alric.KART.LC.Vote.CastVote(86, 1) end)
    T.truthy((lm.KART.LC.votes[86] or {})[alric.guid], "and they vote normally from then on")
    F.AssertAgreed(sim, 86, "including the client that relogged, from the next item on")
end

-- ===================================================================================
-- The LOOTMASTER relogs mid-session -- B30
-- ===================================================================================
-- The one client whose state nobody can replace: LC.HandleStateRequest is answered only by the loot
-- owner and the config owner, and after a reload that is the very client doing the asking. Meanwhile
-- twenty other clients are still in the session, still auto-passing every drop -- so a lootmaster who
-- comes back believing there is no session force-wins nothing and the item is lost to a green roll.
do
    local sim = NewRaid()
    Drop(sim, 87, F.GLOVES)

    local lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.ClearLog(sim)
    RosterSettles(sim)

    -- The half that did the damage: a freshly loaded owner's "no session" is not an answer, and
    -- must not be quoted at anybody.
    T.eq(#RaidSim.Sent(sim, "LC_ACTIVE:0"), 0,
        "a reloaded lootmaster never tells anyone the session is off (B30)")

    for _, c in ipairs(sim.clients) do
        if c ~= lm then
            T.eq(c.KART.LC.sessionActive, true, c.name .. " is still in the session, as they should be")
        end
    end
    T.eq(lm.KART.LC.sessionActive, true,
        "and the reloaded LOOTMASTER rejoins the session the raid is still in (B30)")

    -- The consequence, stated as loot rather than as a flag: the next drop still has to be theirs
    -- to hand out.
    Drop(sim, 88, F.WEAPON)
    T.eq(KARTTEST.rolled[88] and KARTTEST.rolled[88][lm.unit], 1,
        "so they still force-win the next drop instead of letting it roll away (B30)")
    -- The lootmaster is the client the whole raid reads its config from, so a lootmaster who came
    -- back subtly different from the raid they rejoined is the worst shape this addon can be in.
    F.AssertAgreed(sim, 88, "including the lootmaster that relogged")
end

-- The resume claim is only ever about the loot owner, so only the loot owner may act on it. It can
-- turn a session ON and nothing else -- deliberately one-directional, because the two directions are
-- nowhere near equal in what they cost.
do
    local _, _, council, raider = NewRaid()
    -- A raider whose own session is off is told by a council member that it is running. They are not
    -- the loot owner, so the claim is not about them.
    raider.KART.LC.sessionActive = false
    RaidSim.As(council, function() council.KART.LC.SendLC("LC_SESSION_RESUME", "Alric-TarrenMill") end)
    T.eq(raider.KART.LC.sessionActive, false,
        "a session-resume claim is ignored by anyone who does not own the loot flow")
end

-- Standing in follows raid lead. Someone who accepted, then lost the lead, stops being the owner
-- without anyone having to tell them.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    T.truthy(RaidSim.As(stand, stand.KART.LC.IsLootOwner), "the stand-in owns the loot flow")

    -- Standing in also CLEARS the designation, because the stand-in is now the config owner and
    -- their own Lootmaster field is empty (see docs/OWNERSHIP.md). From here the raid names nobody,
    -- so the role simply follows raid lead and there is nothing left to ask about: the question
    -- exists to stop somebody being made to force-win items in place of a NAMED person who is gone,
    -- not to confirm what holding raid lead already means.
    local next_ = RaidSim.Promote(sim, "Corvin")
    RosterSettles(sim)
    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner),
        "and stops owning it when the raid lead moves on")
    T.truthy(RaidSim.As(next_, next_.KART.LC.IsLootOwner),
        "while the new raid leader carries it without being asked -- nobody is named any more")
    T.eq(next_.KART.LC.raidConfig.lootmaster, "", "because the departed name is gone from the config")
end

-- ===================================================================================
-- A roster-change blip must never cost the session
-- ===================================================================================
-- The group APIs report inconsistent state for a moment while a roster change is applied. One such
-- reading used to end the session for the whole raid mid-boss, which is the "session geht rando zu
-- wenn Leute den Raid leaven oder joinen" report. The confirmation delay is what stops it; this is
-- the guard on that guard.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 89, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(89, 1) end)

    for _, c in ipairs(sim.clients) do KARTTEST.solo[c.unit] = true end
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(1)                       -- inside the confirmation window
    for _, c in ipairs(sim.clients) do KARTTEST.solo[c.unit] = nil end
    RosterSettles(sim)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " kept the session through the blip")
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[89]),
            c.name .. " kept the item that was being distributed")
    end
    T.truthy((lm.KART.LC.votes[89] or {})[raider.guid], "and the votes already cast survived it")
end

-- A real departure, on the other hand, does end the session for the person who left -- and for
-- nobody else.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 90, F.GLOVES)

    KARTTEST.solo[raider.unit] = true
    RaidSim.As(raider, function() raider.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)                       -- past the confirmation window

    T.eq(raider.KART.LC.sessionActive, false, "someone who really left is out of the session")
    T.truthy(not raider.KART.LC.rollItems[90], "and their vote window is cleared, not left stale")
    T.eq(lm.KART.LC.sessionActive, true, "while the raid they left carries on")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[90]),
        "with the distribution still running")
    KARTTEST.solo[raider.unit] = nil
end

-- ===================================================================================
-- Someone ports out while the loot is being handed out
-- ===================================================================================
-- Normal in Midnight: short raids, split runs, people leaving for the next lockout the moment the
-- boss is down. The council must be able to finish the distribution regardless -- including seeing
-- the vote of someone who has already gone.
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 91, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(91, 1) end)
    local sinja = sim.byName.Sinja
    RaidSim.As(sinja, function() sinja.KART.LC.Vote.CastVote(91, 2) end)

    RaidSim.Leave(sim, "Alric")
    RosterSettles(sim)

    T.eq(lm.KART.LC.sessionActive, true, "the session survives someone porting out mid-distribution")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[91]), "and the item is still on the table")
    T.truthy((lm.KART.LC.votes[91] or {})[raider.guid],
        "the departed player's vote is still on record for the council to weigh")

    -- And the council can still finish, awarding to someone who is actually there.
    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(91, sinja.guid, "BIS") end)
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[91], sinja.guid, c.name .. " sees the item handed out anyway")
    end
end

-- ===================================================================================
-- The LOOTMASTER ports out -- B29
-- ===================================================================================
-- `LC.raidConfig.lootmaster` is written when a config arrives and never invalidated, so the departed
-- lootmaster's key kept answering for the rest of the evening. Everyone's `IsLootOwner()` was then
-- false: nobody force-won anything, no LC_START went out, and the session could not even be closed.
--
-- Handing the role on is not silent. Whoever stands in starts force-winning every council-eligible
-- item into their own bags, and that is not a side effect to mention in a chat line afterwards.
-- Modelled the way the raid is actually run now (docs/OWNERSHIP.md): the raid leader designates
-- somebody ELSE as lootmaster, and keeps raid lead throughout. When that designee ports out it is
-- the leader's own config that still names them, so the leader is the one asked to stand in.
do
    local sim, _, _, _, leader = F.NewSplitRaid()   -- Corvin leads and has designated Bramor
    RaidSim.Leave(sim, "Bramor")
    RosterSettles(sim)

    T.truthy(not RaidSim.As(leader, leader.KART.LC.IsLootOwner),
        "nobody takes over loot distribution without being asked first (B29)")
    T.truthy(RaidSim.As(leader, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "the raid leader is asked whether to take it over")
    T.truthy(RaidSim.As(leader, leader.KART.LC.IsLootOwner),
        "and owns the loot flow once they accept")
    local stand = leader

    -- The whole point: the raid can keep distributing.
    Drop(sim, 92, F.GLOVES)
    T.eq(KARTTEST.rolled[92] and KARTTEST.rolled[92][stand.unit], 1,
        "the stand-in force-wins the next drop")
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[92]),
            c.name .. " sees the item the stand-in started")
    end

    local raider = sim.byName.Alric
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(92, 1) end)
    T.truthy((stand.KART.LC.votes[92] or {})[raider.guid], "and votes reach the stand-in")
    RaidSim.As(stand, function() stand.KART.LC.Trade.AssignWinner(92, raider.guid, "BIS") end)
    T.eq(sim.byName.Sinja.KART.LC.assignedWinners[92], raider.guid,
        "and the stand-in can hand it out")
end

-- A raider is never asked, however long the lootmaster stays away.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)

    local raider = sim.byName.Alric
    T.truthy(not RaidSim.As(raider, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "a plain raider is not offered the loot flow")
    T.truthy(not RaidSim.As(raider, raider.KART.LC.IsLootOwner), "and does not take it")
end

-- The other half of B29: the stale key survived leaving the raid entirely, so the same client walked
-- into the next raid still believing a lootmaster who was never there.
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 93, F.GLOVES)

    KARTTEST.solo[raider.unit] = true
    RaidSim.As(raider, function() raider.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)
    KARTTEST.solo[raider.unit] = nil

    T.truthy(not next(raider.KART.LC.raidConfig),
        "leaving the raid forgets its config, so none of it leaks into the next one (B29)")
end

-- A raid that never named a lootmaster is not the same case, and must not be pestered about it.
-- The raid leader standing in is the documented setup there, and it has always just worked.
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local lm = sim.byName.Bramor
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)
    RosterSettles(sim)

    T.truthy(not RaidSim.As(lm, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "a raid with an empty Lootmaster field is never asked about standing in")
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsLootOwner), "the leader owns the loot flow as before")
end

-- Presence is "in the raid", not "online". A lootmaster who drops connection keeps the role: their
-- bags still hold the loot, and moving ownership on every connection hiccup would leave the stand-in
-- owing items somebody else is carrying.
do
    local sim, lm, _, _, stand = F.NewSplitRaid()   -- Corvin leads and has designated Bramor
    lm.member.offline = true
    RosterSettles(sim)

    T.truthy(not RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "a disconnected lootmaster is not treated as gone")
    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner), "so the leader does not take over")
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsLootOwner), "and the role is still theirs when they return")
end

-- The lootmaster comes back from the other split raid. The stand-in claim lapses with them, without
-- anyone having to undo anything.
do
    local sim, _, _, _, stand = F.NewSplitRaid()   -- Corvin leads and has designated Bramor
    RaidSim.Leave(sim, "Bramor")
    RosterSettles(sim)
    T.truthy(RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"), "the leader stands in")
    T.truthy(RaidSim.As(stand, stand.KART.LC.IsLootOwner), "and owns the loot flow")

    -- They come back as an ordinary raider. Their own settings are irrelevant now -- the LEADER's
    -- config is what names them, and it never stopped (see docs/OWNERSHIP.md), so the claim lapses
    -- by itself the moment they are back in the roster.
    local returning = {}
    for k, v in pairs(F.MEMBERS[1]) do returning[k] = v end
    returning.leader = nil
    local back = RaidSim.Join(sim, returning)
    RosterSettles(sim)

    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner),
        "the stand-in steps back down the moment the lootmaster is in the raid again")
    T.truthy(RaidSim.As(back, back.KART.LC.IsLootOwner), "and the lootmaster has their role back")
end

-- An empty-field config claims the raid leader's authority, so only the raid leader may send one.
do
    local sim, _, council = NewRaid()
    local alric = sim.byName.Alric
    -- The baseline has to come from the client being asserted on. Reading it off a different client
    -- assumes the very thing this suite exists to disprove -- that two clients agree -- and goes
    -- fully vacuous if the config ever stops arriving, since nil equals nil.
    local before = alric.KART.LC.raidConfig.buttonLabels
    T.truthy(before and before ~= "", "the raider has a real config to begin with")
    RaidSim.As(council, function()
        council.env.KART_Settings.lcButtonLabels = "A;B;C;D;E"
        -- Straight onto the wire, bypassing the ownership gate a real client would hit first.
        council.KART.LC.SendLC("LC_CONFIG:4:A;B;C;D;E:0::Merrit")
    end)
    T.eq(alric.KART.LC.raidConfig.buttonLabels, before,
        "a config with an empty Lootmaster field is ignored unless the raid leader sent it")
end

-- ===================================================================================
-- Handing the lootmaster role over -- B32
-- ===================================================================================
-- Under the ownership rule (docs/OWNERSHIP.md) this is no longer a handover at all: the raid leader
-- owns the config throughout and simply changes who it DESIGNATES. There is nothing to announce and
-- no successor to wait for -- the next broadcast carries the new name, and that is the whole
-- mechanism. The maintainer's own procedure is exactly this: change the field, end the session,
-- start it again.
--
-- What this replaces: typing a successor's name used to make IsConfigOwner() false on the outgoing
-- client, so ApplyOwnConfig wiped its own copy and BroadcastRaidConfig sent nothing at all. The raid
-- never heard about it -- every peer kept naming the outgoing owner and the successor's own field
-- named nobody -- which needed LC_RESIGN as a separate token to paper over (B32). Both are gone.
do
    local sim, lm, council = NewRaid()

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"    -- the leader designates somebody else
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.raidConfig.lootmaster, council.guid, c.name .. " names the new lootmaster")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsLootOwner), "who owns the loot flow at once")
    T.truthy(not RaidSim.As(lm, lm.KART.LC.IsLootOwner),
        "while the leader keeps the CONFIG and stops handing out loot")
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "-- the two roles are separate, and only the loot one moved")

    Drop(sim, 94, F.GLOVES)
    T.eq(KARTTEST.rolled[94] and KARTTEST.rolled[94][council.unit], 1,
        "the designee force-wins from then on")
    T.eq(KARTTEST.rolled[94] and KARTTEST.rolled[94][lm.unit], 0,
        "and the leader passes like any other raider")
end

-- ===================================================================================
-- Ways the session has been lost that no test covered
-- ===================================================================================
-- Everything below was found by a review of this work rather than by a raid, and every one of them
-- ends the same way: an item drops, nothing is force-won, every auto-passing raider passes, and the
-- item goes to a green roll. That is the failure this whole effort exists to stop.

-- Escape closes anything in UISpecialFrames without running a button handler. The prompt latched
-- "already asked" BEFORE it was shown, so dismissing it that way meant no session for the rest of
-- the evening and no second question -- which is verbatim the live report the raid-exit guard was
-- written from ("no session opened for the boss, and afterwards it asked again").
do
    local _, lm = NewRaid()
    RaidSim.As(lm, function() lm.KART.LC.SetSessionActive(false) end)

    RaidSim.As(lm, function()
        lm.KART.LC.promptedThisSession = false
        lm.KART.LC.CheckRaidJoin()
    end)
    KARTTEST.AdvanceTime(5)
    T.truthy(lm.KART.LC.sessionPromptFrame and lm.KART.LC.sessionPromptFrame:IsShown(),
        "the lootmaster is asked whether to start a session")

    RaidSim.As(lm, function() lm.KART.LC.sessionPromptFrame:Hide() end)   -- Escape
    T.eq(lm.KART.LC.promptedThisSession, false,
        "dismissing the prompt without answering leaves the question open")

    RaidSim.As(lm, function() lm.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)
    T.truthy(lm.KART.LC.sessionPromptFrame:IsShown(), "so it is asked again on the next roster change")

    -- Answering, either way, is an answer and must not be re-asked.
    RaidSim.As(lm, function() lm.KART.LC.SetSessionActive(true) end)
    RaidSim.As(lm, function() lm.KART.LC.sessionPromptFrame:Hide() end)
    T.eq(lm.KART.LC.promptedThisSession, true, "answering it closes the question")
end

-- A handover must not cost the raid its settings. Clearing the lootmaster on every peer makes the
-- raid leader the derived config owner, and on the next roster change they broadcast their OWN
-- settings over the raid: council list gone, rolls off, vote labels changed mid-session.
do
    local sim = NewRaid()
    RaidSim.Promote(sim, "Corvin")            -- the lootmaster is not the raid leader
    local lm, alric, successor = sim.byName.Bramor, sim.byName.Alric, sim.byName.Merrit

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    RosterSettles(sim)

    T.truthy(RaidSim.As(successor, successor.KART.LC.IsCouncil),
        "a council member is still council after the lootmaster steps down")
    T.eq(RaidSim.As(alric, alric.KART.LC.GetRollsEnabled), true,
        "and the raid keeps its roll setting")
    T.deep_eq(RaidSim.As(alric, alric.KART.LC.GetButtonConfig),
              RaidSim.As(successor, successor.KART.LC.GetButtonConfig),
        "and everyone still reads the same vote buttons")
end

-- The raid leader reloads. Under the ownership rule the raid runs on their settings, so what has to
-- hold is that a reload does not CHANGE them: KART_Settings is a SavedVariable, so the leader comes
-- back with what they configured and the raid stays exactly where it was.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    RaidSim.As(stand, function()
        stand.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        stand.env.KART_Settings.lcRollsEnabled   = true
        stand.KART.LC.ApplyOwnConfig()
    end)
    RosterSettles(sim)

    local alric = sim.byName.Alric
    local labelsBefore = RaidSim.As(alric, alric.KART.LC.GetButtonConfig)
    RaidSim.Reload(sim, "Merrit")
    RosterSettles(sim)

    T.eq(sim.byName.Merrit.KART.LC.sessionActive, true, "the reloaded leader is back in the session")
    T.eq(RaidSim.As(alric, alric.KART.LC.GetRollsEnabled), true, "and the raid kept its roll setting")
    T.deep_eq(RaidSim.As(alric, alric.KART.LC.GetButtonConfig), labelsBefore,
        "and its vote buttons")
    T.truthy(RaidSim.As(sim.byName.Corvin, sim.byName.Corvin.KART.LC.IsCouncil),
        "and its council")
end

-- A session flag that never arrives. The config has a retry budget; the session flag it is paired
-- with had none, and the state request that would have asked again was a one-shot latch. A client
-- could therefore sit out the whole raid holding a perfectly good config with no session -- getting
-- vote windows, so nothing looked wrong, while never auto-passing and rolling Need against the
-- lootmaster's forced win.
do
    local sim, lm = NewRaid()
    -- Both, because the owner's LC_ACTIVE is no longer the only way to find out: any raider who
    -- knows answers a state request a few seconds behind it (LC.HandleStateRequest). Blackholing
    -- only the first would prove nothing about the retry, since the backstop would cover it.
    RaidSim.Blackhole(sim, "LC_ACTIVE")
    RaidSim.Blackhole(sim, "LC_SESSION_RESUME")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(10)
    T.eq(torvi.KART.LC.sessionActive, false, "with every answer lost, the session flag really is lost")
    T.eq(torvi.KART.LC.raidConfig.lootmaster, lm.guid, "while the config arrived normally")

    RaidSim.Deliver(sim, "LC_ACTIVE")
    RaidSim.Deliver(sim, "LC_SESSION_RESUME")
    KARTTEST.AdvanceTime(60)            -- the state request's own retry budget
    T.eq(torvi.KART.LC.sessionActive, true,
        "a client that never learned the session state asks again until it does")
end

-- The backstop on its own: the owner's answer is lost, and an ordinary raider supplies it instead.
-- Before this, the loot owner was the only client allowed to say the session was running AND the
-- only one that could learn it -- so whenever the owner was the unstable part, a joiner could ask
-- all evening and never find out there was a session at all.
do
    local sim = NewRaid()
    RaidSim.Blackhole(sim, "LC_ACTIVE")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(10)            -- the peers' answers are jittered a few seconds

    T.eq(torvi.KART.LC.sessionActive, true,
        "a raider who knows tells the joiner, when the owner's own answer never arrives")
    -- Counting them would count the owner's own, which is legitimate. What must not happen is a
    -- plain raider taking it upon itself to assert the flag after being told.
    local fromRaiders = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ACTIVE:1")) do
        if e.from == "Alric" or e.from == "Sinja" or e.from == "Torvi" then
            fromRaiders = fromRaiders + 1
        end
    end
    T.eq(fromRaiders, 0,
        "and no plain raider starts asserting the flag itself -- they only learned something")
end

-- Two roster blips inside one confirmation window. The confirmation timer was never cancelled when
-- the raid came back, so the second blip inherited the first one's countdown and could be confirmed
-- almost immediately -- tearing down the session and every tracked roll mid-boss, which is exactly
-- what the confirmation exists to prevent.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 96, F.GLOVES)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(96, 1) end)

    KARTTEST.solo[lm.unit] = true
    RaidSim.As(lm, function() lm.KART.LC.CheckRaidJoin() end)      -- blip one
    KARTTEST.AdvanceTime(0.5)
    KARTTEST.solo[lm.unit] = nil
    RaidSim.As(lm, function() lm.KART.LC.CheckRaidJoin() end)      -- back
    KARTTEST.AdvanceTime(2.4)
    KARTTEST.solo[lm.unit] = true
    RaidSim.As(lm, function() lm.KART.LC.CheckRaidJoin() end)      -- blip two, 0.1s before t=3
    KARTTEST.AdvanceTime(0.2)
    KARTTEST.solo[lm.unit] = nil

    T.eq(lm.KART.LC.sessionActive, true, "a second blip gets its own full confirmation window")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[96]),
        "so the item being distributed survives it")
    T.truthy((lm.KART.LC.votes[96] or {})[raider.guid], "and the votes already cast survive it")
end

-- ===================================================================================
-- When the lootmaster is NOT the raid leader
-- ===================================================================================
-- Every authority check in the addon falls back to the raid leader, and the default fixture cannot
-- tell that fallback apart from the real answer because one person holds both roles there. Splitting
-- them exposes a class of failure that was invisible: a raid leader with an empty Lootmaster field
-- who, for a moment, believes the config is theirs to distribute.

-- The raid leader reloads. For a moment they know nothing, and by the empty-field rule that makes
-- them the config owner -- so they broadcast a config naming nobody. It must not displace the
-- lootmaster the raid already has, nor the council list, nor the roll setting. What made this so
-- expensive is that the leader's own client heals itself seconds later from the reply to its state
-- request, so the one person anybody would ask sees nothing wrong.
do
    local sim, lm, _, raider, leader = F.NewSplitRaid()
    Drop(sim, 97, F.GLOVES)

    RaidSim.Reload(sim, leader.name)
    RosterSettles(sim)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.raidConfig.lootmaster, lm.guid, c.name .. " still names the real lootmaster")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true, c.name .. " still has the raid's rolls")
    end
    T.truthy(RaidSim.As(sim.byName.Merrit, sim.byName.Merrit.KART.LC.IsCouncil),
        "and the council is still the council")

    -- And the loot flow still works, which is the only thing that actually matters.
    Drop(sim, 98, F.WEAPON)
    T.eq(KARTTEST.rolled[98] and KARTTEST.rolled[98][lm.unit], 1, "the lootmaster still force-wins")
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[98]), c.name .. " still sees the item")
    end
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(98, 1) end)
    T.truthy((lm.KART.LC.votes[98] or {})[raider.guid], "and votes still reach the council")
end

-- Raid lead changes. The raid follows the NEW leader's settings, because the config owner is the
-- raid leader (docs/OWNERSHIP.md) -- confirmed with the maintainer, together with the requirement
-- that the switch must not be silent. This is the one behaviour the rework deliberately changes.
--
-- What it replaces is worse than what it costs: ownership used to be a claim, so a lead change left
-- the raid with a config nobody owned and every client silently back on its own roll setting, which
-- defaults to OFF, for the rest of the night (B70). Now the settings simply follow the authority,
-- and the client taking that authority is told so.
do
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local first = sim.byName.Bramor
    RaidSim.As(first, function()
        first.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        first.env.KART_Settings.lcRollsEnabled   = true
        first.KART.LC.ApplyOwnConfig()
        first.KART.LC.SetSessionActive(true)
    end)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true, c.name .. " is on the raid's rolls")
    end

    -- Sinja has never configured anything, so their defaults are what the raid gets. The point is
    -- that the raid AGREES, and that it agrees on something somebody is accountable for.
    local newLead = RaidSim.Promote(sim, "Sinja")
    RosterSettles(sim)

    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled),
             RaidSim.As(newLead, function() return newLead.env.KART_Settings.lcRollsEnabled == true end),
             c.name .. " follows the new raid leader's roll setting")
    end
    T.eq(table.concat(F.Disagreements(sim), " | "), "", "and the raid is of one mind about it")

    -- Handing it back is the same move, so nothing is stuck.
    RaidSim.Promote(sim, "Bramor")
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
             c.name .. " is back on the original leader's rolls when the lead returns")
    end
end

-- The stand-in question could not be shown -- Blizzard's popup pool is four slots wide and this
-- addon is not the only thing using it. Latching "already asked" before checking that left the raid
-- with no loot owner at all and nothing on anyone's screen.
do
    local sim, _, _, _, stand = F.NewSplitRaid()   -- Corvin leads and has designated Bramor
    RaidSim.Leave(sim, "Bramor")

    KARTTEST.popupsBlocked = true
    RosterSettles(sim)
    KARTTEST.popupsBlocked = false
    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner), "nobody stood in while the ask failed")

    RosterSettles(sim)
    T.truthy(RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "so the question is put again rather than silently dropped")
    T.truthy(RaidSim.As(stand, stand.KART.LC.IsLootOwner), "and the raid gets a loot owner")
end

-- ===================================================================================
-- Zoning: the event that fires on a reload when the roster never changes again -- B31
-- ===================================================================================
-- A source check rather than a simulation, because the wiring under test lives in Core.lua's event
-- dispatcher, which the harness deliberately does not load (it builds the whole options UI).
--
-- LC.CheckRaidJoin is the only thing that asks for the session state, and it is reachable from
-- GROUP_ROSTER_UPDATE alone. A client that reloads, or zones into the raid instance, and then sees
-- no further roster change -- a full raid, nobody joining, which is exactly the state a boss fight
-- happens in -- never asks. PLAYER_ENTERING_WORLD is the one event a reload and a zone always
-- raise, and it must reach the same recovery.
do
    local f = assert(io.open("Core.lua", "r"))
    local src = f:read("*a")
    f:close()

    local branch = src:match('elseif event == "PLAYER_ENTERING_WORLD" then(.-)\n%s*elseif event ==')
    T.truthy(branch, "Core.lua still has a PLAYER_ENTERING_WORLD branch to check")
    T.truthy(branch and branch:find("CheckRaidJoin", 1, true),
        "zoning in or reloading re-runs the Loot Council session recovery (B31)")
end

-- ===================================================================================
-- The same item, twice, to the same person -- and someone turns up afterwards
-- ===================================================================================
-- A boss dropping two of the same token and the council handing both to the same raider is
-- ordinary. Every client that was there logs two awards. The catch-up sync has to deliver two as
-- well: it is what a council member who joins late reads to see who is already owed something,
-- and one award silently missing there is a decision made on wrong information.
--
-- Found by tests/test_lc_soak.lua (seed 135), which is the whole reason that file exists.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 97, F.GLOVES)
    Drop(sim, 98, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(97, raider.guid, "BIS") end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(98, raider.guid, "BIS") end)
    T.eq(#lm.env.KART_LootHistory, 2, "both awards are in the lootmaster's own log")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(15)

    T.eq(#torvi.env.KART_LootHistory, 2, "and both reach someone who joined afterwards")
end

-- ===================================================================================
-- The lootmaster leaves for good, then someone joins (B65)
-- ===================================================================================
-- Standing in deliberately moves only the LOOT FLOW, not the config -- the departed lootmaster's
-- name survives so they can pick the role back up when they return (LC.HandleResign,
-- LC.IsConfigOwner). Nobody owns the config while that is true, so nobody re-broadcasts it, and
-- anyone arriving afterwards used to run the evening on their OWN vote buttons, their own minimum
-- quality and their own roll setting -- their vote reaching the council under a different label
-- than they clicked, with nothing to show for it on either side.
--
-- The stand-in now hands on what the raid settled on (LC.RelayRaidConfig), with the lootmaster
-- field empty: here is the config, not "and I am in charge of it".
do
    local sim, lm, council = NewRaid()
    RaidSim.Leave(sim, lm.name)
    RaidSim.Promote(sim, council.name)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN") end
    KARTTEST.AdvanceTime(5)

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(90)

    T.eq(council.KART.LC.raidConfig.buttonLabels, "BIS;Upgrade;Offspec;Sonstiges;Pass",
        "everyone who was already there keeps the raid's config")
    T.eq(torvi.KART.LC.sessionActive, true, "the newcomer is in the session")
    T.eq(torvi.KART.LC.raidConfig.buttonLabels, "BIS;Upgrade;Offspec;Sonstiges;Pass",
        "and gets the raid's vote buttons, not their own")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled), true,
        "and the raid's roll setting, which their own default has off")
    T.deep_eq(RaidSim.As(torvi, torvi.KART.LC.GetButtonConfig),
              RaidSim.As(council, council.KART.LC.GetButtonConfig),
        "so their vote reaches the council under the label they clicked")
    -- The relay says nothing about who is in charge. Ownership stays derived, which is what lets
    -- the real lootmaster reclaim it by simply coming back.
    T.eq(torvi.KART.LC.raidConfig.lootmaster, "",
        "the relay claims no lootmaster of its own")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetLootmaster),
         RaidSim.As(council, council.KART.LC.GetLootmaster),
        "and the newcomer reads the same loot owner as everyone else")
end

-- The relay must never REPLACE a config, only fill a void -- otherwise it becomes a second
-- authority, and a stale forwarded copy could undo the real lootmaster's own broadcast.
do
    local sim, lm, council, raider = NewRaid()
    local lmKey = lm.guid
    -- Same setup as above, so the stand-in really is the loot owner and its relay really goes out.
    RaidSim.Leave(sim, lm.name)
    RaidSim.Promote(sim, council.name)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN") end
    KARTTEST.AdvanceTime(5)

    -- Relayed by an ordinary raider, not by the leader: the config OWNER sends the real thing (see
    -- LC.RelayRaidConfig's own guard), so under the ownership rule the leader never relays at all.
    local relayer = sim.byName.Sinja
    local before = raider.KART.LC.raidConfig.buttonLabels
    T.truthy(not RaidSim.As(relayer, relayer.KART.LC.IsConfigOwner),
        "the relayer is not the config owner, which is what makes it a relay")

    RaidSim.As(relayer, function()
        relayer.KART.LC.raidConfig.buttonLabels = "Forged;Nonsense"
        relayer.KART.LC.RelayRaidConfig(raider.name .. "-" .. raider.realm)
    end)
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG_RELAY") > 0, true, "and it did go out")
    T.eq(raider.KART.LC.raidConfig.buttonLabels, before,
        "but a relay aimed at someone who already has a config changes nothing")
    T.eq(raider.KART.LC.raidConfig.lootmaster, lmKey,
        "and cannot take the lootmaster off them either")
end

-- ===================================================================================
-- The lootmaster reloads and the only people left who know are plain raiders
-- ===================================================================================
-- LC.HandleStateRequest lets a peer tell a freshly reloaded loot owner "your session is still
-- running" -- but only if that peer is council or the raid leader, to keep a reload down to a
-- handful of whispers instead of one per raider.
--
-- That holds right up until the council is the part of the raid that is missing: two council
-- members ported out, and the one still here reloaded a moment ago, so its own session flag is
-- false too. Then the only clients that still KNOW the session is running are ordinary raiders --
-- and they are not allowed to say so. The lootmaster comes back believing there is no session,
-- force-wins nothing for the rest of the evening, and every Auto-Pass raider keeps passing.
--
-- Found by tests/test_lc_soak.lua (seed 87).
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Merrit")
    RaidSim.Leave(sim, "Corvin")     -- the whole council except the lootmaster is gone
    RosterSettles(sim)
    T.eq(sim.byName.Alric.KART.LC.sessionActive, true, "the raiders left behind are in the session")

    local lm = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")
    KARTTEST.AdvanceTime(30)

    T.eq(lm.KART.LC.sessionActive, true,
        "a plain raider tells the reloaded lootmaster the session is still running")

    Drop(sim, 99, F.GLOVES)
    T.eq(KARTTEST.rolled[99] and KARTTEST.rolled[99][lm.unit], 1,
        "so the lootmaster still force-wins the next drop")
end

-- ===================================================================================
-- Every state request is lost, and then things go back to normal
-- ===================================================================================
-- The state request is a bounded backoff on purpose: a raid where nobody can answer must not have
-- twenty clients asking forever. But "bounded" has to mean "for now", not "for the evening".
--
-- Two ways the whole sequence used to be spent without a single answer arriving: Blizzard's chat
-- throttle swallowing the messages, and this client reading itself as ungrouped for a moment --
-- which returned out of RequestSessionState before it could schedule the next attempt, ending the
-- chain on a blip that lasted two seconds. After either, LC.stateSyncRequested stayed latched and
-- nothing ever asked again: session off here, on for everyone else, all evening.
--
-- Found by tests/test_lc_soak.lua (seed 1747).
do
    local sim = NewRaid()
    RaidSim.Blackhole(sim, "LC_STATE_REQ")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(90)          -- longer than the whole backoff: every attempt is lost
    T.eq(torvi.KART.LC.sessionActive, false, "nothing got through, so they are still outside")

    RaidSim.Deliver(sim, "LC_STATE_REQ")
    RosterSettles(sim)

    T.eq(torvi.KART.LC.sessionActive, true, "the next roster change asks again, and they are back in")
end

-- The same sequence, interrupted in the middle rather than before it starts: the chain is running,
-- no answer has arrived yet, and this client reads as ungrouped for two seconds. That used to
-- return out of RequestSessionState before it could schedule the next attempt, so the blip did not
-- cost one try -- it cost every remaining one.
do
    local sim = NewRaid()
    RaidSim.Blackhole(sim, "LC_ACTIVE")           -- the chain runs, but no answer comes back
    local torvi = RaidSim.Join(sim, NEWCOMER)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(3)                       -- past the first retry, chain still going

    KARTTEST.solo[torvi.unit] = true              -- reads as ungrouped, right on an attempt
    KARTTEST.AdvanceTime(5)
    KARTTEST.solo[torvi.unit] = nil

    RaidSim.Deliver(sim, "LC_ACTIVE")
    KARTTEST.AdvanceTime(90)                      -- a later attempt in the SAME chain must fire

    T.eq(torvi.KART.LC.sessionActive, true,
        "a blip costs one attempt, not the whole retry sequence")
end

-- The raid leader reloads after the lootmaster is gone, and invents a config
-- ===================================================================================
-- With the lootmaster gone, LC.IsConfigOwner falls back to the raid leader -- guarded by fromSelf
-- so a leader cannot push their own settings over a config the raid received. A reload clears
-- raidConfig, which leaves that guard nothing to bite on: LC.ApplyOwnConfig then writes the
-- LEADER'S defaults in (rolls off, empty council list) and marks them the owner, and the relay that
-- would have restored the raid's config was refused because "a config is already there".
--
-- The relay now replaces a config that was self-invented from defaults while the client's own
-- Lootmaster field is empty. A leader who typed their own name in that field owns their config on
-- purpose and is left alone.
--
-- Found by tests/test_lc_soak.lua (seed 73).
do
    local sim, lm, council = NewRaid()
    RaidSim.Leave(sim, lm.name)
    -- The rest of the council goes too, on purpose: council and the loot owner relay IMMEDIATELY,
    -- which would answer before the leader's own LC.ApplyOwnConfig could invent anything and the
    -- test would pass whether the fix is there or not. With only ordinary raiders left to answer,
    -- their reply is jittered a few seconds and lands on a config the leader has already made up --
    -- which is the case that matters.
    RaidSim.Leave(sim, "Corvin")
    RaidSim.Promote(sim, council.name)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN") end
    KARTTEST.AdvanceTime(5)

    local leader = RaidSim.Reload(sim, council.name)
    RaidSim.EnterWorld(sim, council.name)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(60)

    T.eq(RaidSim.As(leader, leader.KART.LC.GetRollsEnabled), true,
        "the reloaded leader gets the RAID's roll setting back, not their own default")
    T.eq(RaidSim.As(leader, leader.KART.LC.GetRollsEnabled),
         RaidSim.As(sim.byName.Alric, sim.byName.Alric.KART.LC.GetRollsEnabled),
        "and agrees with the raiders who never reloaded")
end

-- ===================================================================================
-- An item announced while a client was deaf (B66)
-- ===================================================================================
-- LC_START is announced once and never re-requested. A client is deaf for two ordinary reasons: it
-- is still coming back from a reload, or Blizzard's chat throttle swallowed the message. It then
-- had no way back to that item -- no vote row, no answer from it, and the council waiting on
-- somebody who never saw the thing.
--
-- The loot owner now lists the rolls still open when it answers a state request. What keeps this
-- from breaking the maintainer's rule about late arrivals is the receiving side: the roll is
-- rebuilt only if BLIZZARD gave this client that same roll, which is proof it was in the raid when
-- the boss died. Someone who joined afterwards has no such roll and is not pulled in.
do
    local sim, lm = NewRaid()
    RaidSim.Blackhole(sim, "LC_START")

    -- Alric is here and eligible, but reloading at the moment the boss dies: no session, so its own
    -- START_LOOT_ROLL does nothing, and the announcement never arrives either.
    local alric = RaidSim.Reload(sim, "Alric")
    Drop(sim, 90, F.GLOVES)
    T.eq(alric.KART.LC.rollItems[90], nil, "the deaf client has no idea the item dropped")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[90]), "while the raid is voting on it")

    RaidSim.Deliver(sim, "LC_START")
    RaidSim.EnterWorld(sim, "Alric")
    RosterSettles(sim)

    T.truthy(alric.KART.LC.IsRealItemLink(alric.KART.LC.rollItems[90]),
        "once it is back, the item it missed is handed to it")
    T.truthy(HasVoteRow(alric, 90), "with a vote row, so it can still answer")
    RaidSim.As(alric, function() alric.KART.LC.Vote.CastVote(90, 1) end)
    T.truthy((lm.KART.LC.votes[90] or {})[alric.guid], "and the council gets the answer after all")
end

-- The same catch-up must NOT reach someone who was not there for that boss.
do
    local sim, lm = NewRaid()
    Drop(sim, 91, F.GLOVES, { noRollFor = { Torvi = true } })
    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(10)

    T.eq(torvi.KART.LC.sessionActive, true, "the newcomer is in the session")
    T.truthy(not HasVoteRow(torvi, 91),
        "but Blizzard never gave them that roll, so the catch-up leaves them out of it")
    T.truthy(lm.KART.LC.IsRealItemLink(lm.KART.LC.rollItems[91]), "while the raid still has it")
end

-- A config a client invented for itself must not travel any further
-- ===================================================================================
-- The relay hands on what the raid agreed. A client that reloaded while nobody owned the config
-- has, for a moment, a config it made up from its own defaults -- rolls off, empty council list.
-- Passing THAT on is how one client's defaults become the raid's: the next client to ask stores it
-- as the raid's config, and from there it is indistinguishable from the real thing to everybody
-- downstream.
--
-- Found by tests/test_lc_soak.lua (seed 254), where exactly that happened: the reloaded raid leader
-- handed rolls-off to a newcomer, who kept it.
do
    local sim, lm, council = NewRaid()
    RaidSim.Leave(sim, lm.name)
    RaidSim.Leave(sim, "Corvin")
    RaidSim.Promote(sim, council.name)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN") end

    -- The leader reloads and invents one; nothing has corrected it yet.
    local leader = RaidSim.Reload(sim, council.name)
    RaidSim.EnterWorld(sim, council.name)
    RaidSim.ClearLog(sim)

    -- Put it in the state that matters rather than hoping the run produced it: a COMPLETE config,
    -- so nothing else in LC.RelayRaidConfig can be the reason nothing goes out, marked as one this
    -- client applied from its own settings.
    RaidSim.As(leader, function()
        local cfg = leader.KART.LC.raidConfig
        cfg.minQuality, cfg.buttonLabels = 4, "Made;Up"
        cfg.rollsEnabled, cfg.lootmaster, cfg.councilMembers = false, "", ""
        cfg.fromSelf = true
    end)
    -- Raid lead moves on, which is how the invented config gets out into the raid at all: while
    -- they still HELD the lead, LC.IsConfigOwner answered true and LC.RelayRaidConfig stopped one
    -- guard earlier. Hand it to someone else and the same client is suddenly an ordinary member
    -- carrying a config it made up -- and, until this fix, willing to pass it on.
    RaidSim.Promote(sim, "Alric")
    RaidSim.As(leader, function() leader.KART.LC.RelayRaidConfig("Torvi-TarrenMill") end)
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG_RELAY"), 0,
        "a config the client made up for itself is never relayed onward")

    -- The opposite, from a client holding a config it actually received, so the assertion above
    -- cannot pass simply by the relay being broken outright.
    local raider = sim.byName.Alric
    T.is_nil(raider.KART.LC.raidConfig.fromSelf, "the raider's config is one it received")
    RaidSim.As(raider, function() raider.KART.LC.RelayRaidConfig("Torvi-TarrenMill") end)
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG_RELAY"), 1, "while a config it received is handed on")

    -- And the raid still agrees about the roll setting once everything settles.
    RosterSettles(sim)
    KARTTEST.AdvanceTime(60)
    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(60)
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled),
         RaidSim.As(sim.byName.Alric, sim.byName.Alric.KART.LC.GetRollsEnabled),
        "so a newcomer ends up on the raid's roll setting, not one client's default")
end

-- The raid leader reloads into a running session (was B67/B69)
-- ===================================================================================
-- This used to be the most expensive shape in the whole file. Ownership was a claim, so a reloaded
-- leader whose raidConfig came back empty passed the empty-field rule, wrote its own DEFAULTS in
-- (rolls off, empty council) and broadcast those as the raid's. Worse, it only half-landed: clients
-- still naming the previous lootmaster rejected it as a weaker claim, anyone who had joined or
-- reloaded since took it, and the raid split down the middle over its own settings.
--
-- Both halves are gone with the claim (docs/OWNERSHIP.md). The reloaded leader IS the config owner
-- and does broadcast -- and that is now safe for two reasons worth asserting separately:
--   * It broadcasts its OWN SAVED settings, not defaults. KART_Settings is a SavedVariable, so a
--     reload does not reset what that person configured.
--   * Every client accepts it, because acceptance is "did the raid leader send it" and nothing about
--     the content. A split is not merely unlikely now, it is unreachable.
do
    local sim, lm, council = NewRaid()
    local raider = sim.byName.Alric
    RaidSim.Leave(sim, lm.name)
    RaidSim.Leave(sim, "Corvin")
    RaidSim.Promote(sim, council.name)
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN") end
    KARTTEST.AdvanceTime(5)

    -- Something the leader configured, so "their own settings" is a claim with teeth rather than a
    -- coincidence of the defaults.
    RaidSim.As(council, function()
        council.env.KART_Settings.lcRollsEnabled = true
        council.env.KART_Settings.lcMinQuality   = 3
        council.KART.LC.ApplyOwnConfig()
    end)
    RosterSettles(sim)
    RaidSim.ClearLog(sim)

    -- The relay is blackholed exactly as before, so the leader comes back with an empty raidConfig
    -- and nothing to heal it -- the state the old rule turned into a raid-wide split.
    RaidSim.Blackhole(sim, "LC_CONFIG_RELAY")
    local leader = RaidSim.Reload(sim, council.name)
    RaidSim.EnterWorld(sim, council.name)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(10)

    T.eq(leader.KART.LC.sessionActive, true, "the reloaded leader knows the session is running")
    T.truthy(RaidSim.As(leader, leader.KART.LC.IsConfigOwner),
        "and owns the config, because it holds raid lead")
    T.eq(RaidSim.As(leader, leader.KART.LC.GetRollsEnabled), true,
        "on its own SAVED settings -- a reload does not reset them to defaults")
    T.eq(RaidSim.As(leader, leader.KART.LC.GetRaidMinQuality), 3, "including the ones it changed")

    T.eq(RaidSim.As(raider, raider.KART.LC.GetRollsEnabled), true,
        "and the raid follows it rather than splitting")
    T.eq(RaidSim.As(raider, raider.KART.LC.GetRaidMinQuality), 3, "on every field, not just some")

    -- The half of the raid with nothing to compare against is where the damage used to land.
    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(60)
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled), true,
        "somebody arriving afterwards lands on the same config as everybody else")
    T.eq(table.concat(F.Disagreements(sim), " | "), "", "and the whole raid is of one mind")
end

-- End Round clears the round for the RAID, not just for whoever pressed it (B57, GitHub #15)
-- ===================================================================================
-- The two sides judged this differently and both stayed silent. The button is enabled by the
-- presser's own LC.IsLootOwner, which falls back to the raid leader whenever their client holds no
-- config naming somebody else -- normal after a reload while the config is slow. Their peers judged
-- the incoming LC_END_ROUND with IsSenderLootOwner, and THEY had a config naming the real
-- lootmaster, so they threw it away. The presser's window cleared, everyone else kept the previous
-- boss's items, and nothing was printed on either side.
--
-- Reported from a live raid with a screenshot; no path in the code explained it until the two
-- ownership answers were compared against each other rather than each on its own.
do
    local sim, lm = F.NewSplitRaid()          -- lootmaster Bramor, raid lead Corvin
    RaidSim.Blackhole(sim, "LC_CONFIG")
    RaidSim.Blackhole(sim, "LC_CONFIG_RELAY")
    local leader = RaidSim.Reload(sim, "Corvin")
    RaidSim.EnterWorld(sim, "Corvin")
    RosterSettles(sim)
    KARTTEST.AdvanceTime(30)

    Drop(sim, 70, F.GLOVES)
    Drop(sim, 71, F.WEAPON)

    -- The disagreement itself, stated so a change to either side shows up here.
    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), true,
        "the raid leader's own client says it owns the loot flow -- this is what enables the button")
    T.eq(RaidSim.As(lm, function() return lm.KART.LC.IsSenderLootOwner(leader.guid) end), false,
        "while its peers do not agree, because they hold a config naming the real lootmaster")

    RaidSim.As(leader, leader.KART.LC.EndRound)
    KARTTEST.AdvanceTime(1)

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.councilTabs, 0, c.name .. " has no council tabs left")
        T.eq(#c.KART.LC.voteListRolls, 0, c.name .. " has no vote rows left")
    end
end

-- Someone joins while the named lootmaster is merely ABSENT (backlog B58)
-- ------------------------------------------------------------------------------------------------
-- The narrower half of B29: the stand-in leader runs the loot flow but deliberately does NOT own the
-- raid's settings, because the config still names the lootmaster who may walk back in. So while they
-- are away nobody is the config owner, and the reply that hands a joiner the raid's settings is the
-- config owner's to send. Anyone arriving in that window used to get the session flag and nothing
-- else -- their own vote-button labels, their own minimum quality, their own roll setting, for as
-- long as the lootmaster stayed away.
--
-- Whether the relay added for B65 already covers this is the point of the test. It was written for
-- the lootmaster who is gone for good; this is the same shape with the lootmaster only away.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")                -- the named lootmaster steps out
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")

    -- Nobody owns the config in this state, which is what makes it B58 rather than an ordinary join.
    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.IsConfigOwner), false,
            c.name .. " does not own the config while the lootmaster is merely away")
    end

    local alric = sim.byName.Alric
    local labels = RaidSim.As(alric, alric.KART.LC.GetButtonConfig)

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    KARTTEST.AdvanceTime(10)                    -- a plain raider's relay is jittered a few seconds

    T.eq(torvi.KART.LC.sessionActive, true, "the joiner is in the session")
    T.deep_eq(RaidSim.As(torvi, torvi.KART.LC.GetButtonConfig), labels,
        "and runs the raid's vote buttons rather than its own")
    T.eq(RaidSim.As(torvi, torvi.KART.LC.GetRollsEnabled),
        RaidSim.As(alric, alric.KART.LC.GetRollsEnabled), "and the raid's roll setting")
    -- Minimum quality is deliberately not asserted here: the fixture leaves it at the default, so
    -- a client running its OWN setting would answer the same number and the check could never fail.
    T.truthy(RaidSim.As(torvi, function() return torvi.KART.LC.IsSenderCouncil(sim.byName.Corvin.guid) end),
        "and knows who the council is")
end

-- The loot owner is not always the one holding the item (backlog B60, and what B63 would need)
-- ------------------------------------------------------------------------------------------------
-- The lootmaster force-wins a drop and then ports out mid-distribution, which the maintainer
-- describes as the normal shape of a raid night rather than an edge case. The raid leader stands in
-- and is the loot owner from that moment -- but the item is in the departed lootmaster's bags.
--
-- The trade reminder used to be created for whoever was loot owner at award time, so the stand-in
-- was told to hand over an item they had never had. That reminder does not merely sit there being
-- wrong: Trade.OnTradeClosed reads "not in my bags" as "already traded" and clears it the next time
-- that same winner is traded with for anything at all. It tidies itself away, the raid believes the
-- item was handed over, and the winner never receives it.
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 90, F.GLOVES)

    -- Before anything moves: the client that force-won it is the one that owes it.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(90, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(1)
    T.truthy(F.Owes(lm.KART.LC.pendingTrades, 90),
        "the lootmaster who force-won the item owes it after awarding")

    -- Now the same item, decided after the role has moved.
    Drop(sim, 91, F.WEAPON)
    T.truthy(RaidSim.As(lm, function() return lm.KART.LC.rollItems[91] end),
        "the lootmaster saw the second drop and force-won it too")

    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    T.eq(RaidSim.As(stand, stand.KART.LC.IsLootOwner), true,
        "the stand-in is the loot owner once the lootmaster has gone")

    RaidSim.As(stand, function() stand.KART.LC.Trade.AssignWinner(91, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(1)
    T.is_nil(F.Owes(stand.KART.LC.pendingTrades, 91),
        "but owes nothing for an item it never won -- that one is in the departed lootmaster's bags")

    -- The award itself must still happen. Refusing the reminder may not cost the raid the decision.
    T.truthy(RaidSim.As(raider, function() return F.Owes(raider.KART.LC.owedToMe, 91) end),
        "the winner is still owed the item")
end

-- ...and the mark must not outlive the roll it was made for.
-- Blizzard reuses rollIDs. PurgeStaleRoll clears the per-roll state when the ID comes back carrying
-- a DIFFERENT item, and deliberately does nothing when the item is the same -- so a client that once
-- heard about this ID from somebody else, and now force-wins it itself, has to drop the mark on the
-- spot. Otherwise it would refuse the reminder for an item genuinely in its own bags.
do
    local sim, _, council, raider = NewRaid()   -- council = Merrit, not the loot owner yet
    Drop(sim, 92, F.GLOVES)
    T.truthy(council.KART.LC.rollNotInOurBags[92],
        "a council member learns of the drop from the lootmaster, so it is not theirs to hand out")

    RaidSim.Leave(sim, "Bramor")
    RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(council, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")

    Drop(sim, 92, F.GLOVES)                     -- same ID, same item, now won by the stand-in itself
    T.is_nil(council.KART.LC.rollNotInOurBags[92],
        "force-winning the same ID again makes it theirs, whatever the previous round left behind")

    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(92, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(1)
    T.truthy(F.Owes(council.KART.LC.pendingTrades, 92),
        "so the reminder is created for an item that really is in their bags")
end

-- /kart status must survive every state it is meant to describe
-- ------------------------------------------------------------------------------------------------
-- It is the one diagnostic a raider can run mid-raid and paste into an issue, so it is also the one
-- that must not be the thing that breaks. Its failure mode is not a crash in the loot flow but a
-- concatenation against a nil -- a locale key added to one file and not the other, a table read
-- before it exists -- and it would surface at exactly the moment somebody needs an answer.
--
-- Locale parity is covered separately (tests/test_locales.lua); this covers the code path.
do
    local sim = NewRaid()
    local torvi = RaidSim.Join(sim, NEWCOMER)   -- has not been told anything yet

    local realPrint = print
    local function StatusRuns(client, when)
        _G.print = function() end               -- the output itself is not what is under test
        local ok, err = pcall(RaidSim.As, client, client.KART.LC.PrintStatus)
        _G.print = realPrint
        T.truthy(ok, "/kart status runs for " .. client.name .. " " .. when ..
            (ok and "" or (": " .. tostring(err))))
    end

    -- Nothing tracked yet, and one client that has never been told the session state.
    StatusRuns(sim.byName.Bramor, "with no rolls on the table")
    StatusRuns(torvi, "before anyone has answered it")

    RosterSettles(sim)
    Drop(sim, 95, F.GLOVES)
    for _, c in ipairs(sim.clients) do StatusRuns(c, "with an item on the table") end

    -- And after the lootmaster has gone, which is the state people actually run it in.
    RaidSim.Leave(sim, "Bramor")
    RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    for _, c in ipairs(sim.clients) do StatusRuns(c, "with the lootmaster gone") end
end
