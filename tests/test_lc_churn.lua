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
    T.truthy(not HasVoteRow(alric, 85),
        "the distribution already running is not restored to them -- same rule as a late joiner")

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

    local next_ = RaidSim.Promote(sim, "Corvin")
    RosterSettles(sim)
    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner),
        "and stops owning it when the raid lead moves on")
    T.truthy(RaidSim.As(next_, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "the new raid leader is asked in turn")
    T.truthy(RaidSim.As(next_, next_.KART.LC.IsLootOwner), "and takes it over")
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
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)

    T.truthy(not RaidSim.As(stand, stand.KART.LC.IsLootOwner),
        "nobody takes over loot distribution without being asked first (B29)")
    T.truthy(RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "the new raid leader is asked whether to take it over")
    T.truthy(RaidSim.As(stand, stand.KART.LC.IsLootOwner),
        "and owns the loot flow once they accept")

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
    local sim, lm = NewRaid()
    local stand = RaidSim.Promote(sim, "Merrit")
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
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    T.truthy(RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"), "the leader stands in")
    T.truthy(RaidSim.As(stand, stand.KART.LC.IsLootOwner), "and owns the loot flow")

    -- They come back as an ordinary raider -- Merrit kept raid lead -- carrying the settings that
    -- name them lootmaster, exactly as their SavedVariables would.
    local returning = {}
    for k, v in pairs(F.MEMBERS[1]) do returning[k] = v end
    returning.leader = nil
    local back = RaidSim.Join(sim, returning)
    back.env.KART_Settings.lcLootmaster = "Bramor"
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
-- Typing a successor's name made `IsConfigOwner()` false on the outgoing client, so `ApplyOwnConfig`
-- wiped its own copy and returned and `BroadcastRaidConfig` sent nothing at all. The raid never heard
-- about it: every peer kept naming the outgoing owner, and the successor's own field named nobody.
do
    local sim, lm, council = NewRaid()

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)

    T.eq(#RaidSim.Sent(sim, "LC_RESIGN"), 1, "stepping down is announced to the raid (B32)")
    for _, c in ipairs(sim.clients) do
        if c ~= lm then
            T.truthy((c.KART.LC.raidConfig.lootmaster or "") == "",
                c.name .. " no longer names the outgoing lootmaster")
        end
    end

    -- Until the successor configures themselves, ownership rests with the raid leader -- derived, so
    -- every client agrees without another message.
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsLootOwner),
        "the raid leader carries the loot flow in the meantime")

    -- The successor fills their own field in, and the raid follows.
    RaidSim.As(council, function()
        council.env.KART_Settings.lcLootmaster     = "Merrit"
        council.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        council.env.KART_Settings.lcRollsEnabled   = true
        council.KART.LC.ApplyOwnConfig()
        council.KART.LC.BroadcastRaidConfig()
    end)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.raidConfig.lootmaster, council.guid, c.name .. " names the successor")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsLootOwner), "who owns the loot flow")
    T.truthy(not RaidSim.As(lm, lm.KART.LC.IsLootOwner), "and the outgoing owner does not")

    Drop(sim, 94, F.GLOVES)
    T.eq(KARTTEST.rolled[94] and KARTTEST.rolled[94][council.unit], 1,
        "the successor force-wins from then on")
    T.eq(KARTTEST.rolled[94] and KARTTEST.rolled[94][lm.unit], 0,
        "and the outgoing owner passes like any other raider")
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

-- The stand-in leader reloads. A council member tells them the session is running -- they must not
-- take that as licence to push their own settings over the raid. Their own Lootmaster field is
-- empty, which is the documented setup, so their config would carry an empty council list.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")
    RosterSettles(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")

    local alric = sim.byName.Alric
    local labelsBefore = RaidSim.As(alric, alric.KART.LC.GetButtonConfig)
    RaidSim.Reload(sim, "Merrit")
    RosterSettles(sim)

    T.eq(sim.byName.Merrit.KART.LC.sessionActive, true, "the reloaded stand-in is back in the session")
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
    RaidSim.Blackhole(sim, "LC_ACTIVE")

    local torvi = RaidSim.Join(sim, NEWCOMER)
    RosterSettles(sim)
    T.eq(torvi.KART.LC.sessionActive, false, "the lost session flag really is lost")
    T.eq(torvi.KART.LC.raidConfig.lootmaster, lm.guid, "while the config arrived normally")

    RaidSim.Deliver(sim, "LC_ACTIVE")
    KARTTEST.AdvanceTime(60)            -- the state request's own retry budget
    T.eq(torvi.KART.LC.sessionActive, true,
        "a client that never learned the session state asks again until it does")
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

-- Raid lead changes in a raid that never named a lootmaster. The new leader must not overwrite the
-- settings the raid is already using with their own empty ones.
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

    RaidSim.Promote(sim, "Sinja")     -- somebody else takes raid lead
    RosterSettles(sim)

    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            c.name .. " keeps the raid's roll setting across a raid-lead change")
    end
    T.truthy(RaidSim.As(sim.byName.Merrit, sim.byName.Merrit.KART.LC.IsCouncil),
        "and the council survives it")
end

-- The stand-in question could not be shown -- Blizzard's popup pool is four slots wide and this
-- addon is not the only thing using it. Latching "already asked" before checking that left the raid
-- with no loot owner at all and nothing on anyone's screen.
do
    local sim = NewRaid()
    RaidSim.Leave(sim, "Bramor")
    local stand = RaidSim.Promote(sim, "Merrit")

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
