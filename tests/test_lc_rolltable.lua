-- The roll table: the lootmaster draws for everybody, once, in one message.
--
-- Before this, every client drew its own number and broadcast it -- 25 messages in the same instant
-- for one drop, 25 separate things to lose, and regular ties because 25 independent draws out of
-- 1-100 collide. What replaces it is a single table drawn by the one client that already knows who
-- was standing there when the item dropped (LC.rollEligible, the same snapshot the catch-up
-- entitlement reads).

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- One drop, one table --------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)
    F.Drop(sim, 900, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    -- RaidSim.Sent matches on the raw bytes handed to C_ChatInfo.SendAddonMessage, which for a
    -- multipart message is a chunk carrying AceComm's own control byte before the token -- a prefix
    -- match would find nothing. This only works because the fixture's payload here stays under the
    -- single-part size limit; it will fail loudly, not silently, the day this message's payload grows
    -- past that limit.
    T.eq(#RaidSim.Sent(sim, "LC_ROLLS:"), 1, "the whole raid's rolls travel as one message")
    T.eq(RaidSim.Sent(sim, "LC_ROLLS:")[1].from, lm.name, "and the lootmaster is the one who sent it")
end

-- Everybody has a number, and no two are the same ------------------------------------------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 901, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local rolls = lm.KART.LC.rolls[901] or {}
    local count, seen, twice = 0, {}, false
    for _, value in pairs(rolls) do
        count = count + 1
        if seen[value] then twice = true end
        seen[value] = true
        T.truthy(value >= 1 and value <= 100, "every number is inside 1-100")
    end
    T.eq(count, #sim.clients, "every raider who was there has a number")
    T.eq(twice, false, "and no number was handed out twice")

    F.AssertAgreed(sim, 901, "about the rolls")
end

-- Somebody who was not there gets nothing ---------------------------------------------------------
-- The settled rule: a late arrival is not handed a running item. Before the table, they drew for
-- themselves the moment LC_START reached them and appeared in the council's tally anyway.
do
    local sim = F.NewRaid()
    F.Drop(sim, 902, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local late = RaidSim.Join(sim, { name = "Torvin", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C99", class = "WARRIOR", locale = "enUS" })
    KARTTEST.AdvanceTime(1)

    local council = sim.byName.Merrit
    T.is_nil((council.KART.LC.rolls[902] or {})[late.guid], "a raider who joined afterwards has no number")
end

-- A table that never arrived is asked for, once ---------------------------------------------------
-- One message carrying the whole raid's rolls is also one message to lose, and losing it costs
-- everybody's numbers at once instead of one raider's. That is the trade this makes: it can be asked
-- for again, which 25 separate broadcasts never could.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    RaidSim.Blackhole(sim, "LC_ROLLS")
    F.Drop(sim, 903, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    T.eq(blind.KART.LC.rolls[903], nil, "the client that lost the table has no rolls for the item")

    -- The heartbeat is what makes it notice. Nothing is re-broadcast: it asks, and the owner answers
    -- that one client.
    RaidSim.Deliver(sim, "LC_ROLLS")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(15)

    -- RaidSim.Blackhole drops the broadcast before it reaches ANY recipient, not just Corvin's, so
    -- every other raid member is equally blind here -- counting the whole raid's requests would count
    -- them too. What this checks is the one thing the heartbeat promises per client: asked for, not
    -- re-asked for, while an answer could already be on its way.
    local blindAsks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == blind.name then blindAsks = blindAsks + 1 end
    end
    T.eq(blindAsks, 1, "it asks exactly once")
    T.deep_eq(blind.KART.LC.rolls[903], lm.KART.LC.rolls[903],
        "and afterwards it holds the same numbers as the lootmaster")
    F.AssertAgreed(sim, 903, "about the rolls after the catch-up")
end

-- ...but not by somebody who was not there ---------------------------------------------------------
do
    local sim = F.NewRaid()
    F.Drop(sim, 904, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)

    local late = RaidSim.Join(sim, { name = "Torvid", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C98", class = "ROGUE", locale = "enUS" })
    KARTTEST.AdvanceTime(20)

    T.eq(late.KART.LC.rolls[904], nil,
        "a raider who joined after the announcement is not caught up with its rolls either")
end

-- The cooldown holds even while the answer is still missing, across a second heartbeat -------------
-- The "asks exactly once" test above cannot tell a live cooldown from a deleted one: its own answer
-- arrives within the same heartbeat tick that triggered the ask, so needRolls turns false before a
-- second heartbeat could ever fire, and nothing there actually exercises ROLL_REQ_COOLDOWN. Here the
-- catch-up's LC_ROLLS is held in flight -- never delivered, not lost -- so needRolls stays true past
-- a SECOND heartbeat, and only the cooldown timer stands between that and asking twice.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    -- The default vote window (20s) would close right on top of the second heartbeat (t=20) and
    -- take the rollID off the table for a reason that has nothing to do with the cooldown -- widen
    -- it so the only thing keeping the second heartbeat from producing a second ask is the cooldown
    -- itself.
    lm.env.KART_Settings.lcVoteSeconds = 60

    RaidSim.Blackhole(sim, "LC_ROLLS")
    F.Drop(sim, 906, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    T.eq(blind.KART.LC.rolls[906], nil, "the client that lost the table has no rolls for the item")

    -- Deliveries resume, but the catch-up's own LC_ROLLS is held rather than let through -- so the
    -- first ask's answer never lands, and the second heartbeat still finds the table missing.
    RaidSim.Deliver(sim, "LC_ROLLS")
    RaidSim.Hold(sim, "LC_ROLLS")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(21) -- past both the t=10 and t=20 heartbeat ticks

    local blindAsks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == blind.name then blindAsks = blindAsks + 1 end
    end
    T.eq(blindAsks, 1,
        "the cooldown keeps it from asking again at the second heartbeat while unanswered")
end

-- An ownership disagreement must not cost a raider the whole raid's numbers (B129) ------------------
-- The test holds the disagreement open deliberately: a promoted client reloads with its config wiped --
-- (empty Lootmaster field, LC.RelayRaidConfig's "ownership stays derived") and reads itself as loot
-- owner through the raid-leader fallback. The disagreement stays unresolved for the whole test
-- because what is under test is LC.HandleRolls's behavior DURING such disagreement, not how long
-- the disagreement persists in a real raid. The named lootmaster is still out there, unaware,
-- still drawing and sending tables under the old config. Before the roll table became one
-- authoritative message this cost nothing: every client drew its own number with no sender check at
-- all. Now the table is a single writer's state, and disagreeing about who that writer is used to
-- mean getting none of it -- permanently, for that item (seed 1728 in the deep soak).
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local alric = RaidSim.Reload(sim, "Alric")
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 905, F.WEAPON)
    KARTTEST.AdvanceTime(0.5)

    T.deep_eq(alric.KART.LC.rolls[905], lm.KART.LC.rolls[905],
        "the promoted-and-reloaded client ends up holding the same numbers as the lootmaster")
end

-- Two announcers, and everybody keeps the numbers of the one they listened to ---------------------
-- The window is B129's: a raid leader who picked its config back up from a peer has an empty
-- lootmaster field, so it reads itself as the loot owner while the real lootmaster does too. Before
-- this, both drew a table and the raid leader ended up holding numbers nobody else had -- for good,
-- because it refused the real owner's table AND the heartbeat that would have made it ask.
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric") or sim.byName.Alric
    RaidSim.As(leader, function() leader.KART.LC.SetSessionActive(true) end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 910, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    -- Merrit accepted an announcement from somebody. Whoever that was, Merrit's numbers are theirs.
    local merrit = sim.byName.Merrit
    local announcer = merrit.KART.LC.rollAnnouncedBy[910]
    T.truthy(announcer ~= nil, "a client records who announced the item it accepted")
    local source = (announcer == lm.guid) and lm or leader
    T.deep_eq(merrit.KART.LC.rolls[910], source.KART.LC.rolls[910],
        "and holds the table of that announcer, not of whoever it thinks is lootmaster")
end

-- A table from somebody who did not announce it cannot overwrite one that is there ----------------
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 911, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local merrit, alric = sim.byName.Merrit, sim.byName.Alric
    local before = {}
    for k, v in pairs(merrit.KART.LC.rolls[911]) do before[k] = v end

    -- Alric never announced 911. Hand Merrit a table from Alric by hand.
    RaidSim.As(merrit, function()
        merrit.KART.LC.HandleRolls("911:@" .. F.GLOVES .. ":" .. lm.guid .. "=1", alric.guid)
    end)
    T.deep_eq(merrit.KART.LC.rolls[911], before,
        "a table from somebody who did not announce the item leaves the existing one alone")
end

-- A peer answers when the announcer cannot ------------------------------------------------------
-- After a lootmaster handover the stand-in has no roster snapshot for items the previous owner
-- announced, so LC.MayCatchUp refuses every catch-up for them -- deliberately (B118). The numbers are
-- not secret, though: the whole raid holds the same table, so anybody who has it may hand it over.
--
-- Blackholing LC_ROLLS (as the earlier "asked once" case above does) would not fit here: that drops
-- the announcement's one broadcast for the WHOLE raid, so nobody but the announcer -- about to leave
-- -- ever holds real numbers. What this case needs is everybody holding the table normally and ONE
-- client losing its own copy, so a peer answering means something.
do
    local sim, lm = F.NewRaid()
    local blind = sim.byName.Corvin

    -- Long past the point LC.OpenRollIDs would otherwise drop the roll from a heartbeat -- what is
    -- under test is recovery minutes into a distribution, not the ordinary 20-second vote window.
    lm.env.KART_Settings.lcVoteSeconds = 90
    F.Drop(sim, 920, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    RaidSim.As(blind, function() blind.KART.LC.rolls[920] = nil end)
    T.eq(blind.KART.LC.rolls[920], nil, "the client that lost the table has no rolls for the item")

    -- The announcer goes away and the raid leader stands in. Its heartbeat is what picks the item
    -- back up (see LC.EnsureTableTicker's OnAccept call) -- but its rollEligible snapshot is Bramor's
    -- to have, not its own, so MayCatchUp still refuses the ITEM (B118) while the numbers are there
    -- for anybody to hand over regardless.
    RaidSim.Leave(sim, "Bramor")
    local stand = sim.byName.Merrit
    -- The stand-in becomes the config owner too (docs/OWNERSHIP.md) and re-broadcasts its OWN
    -- settings on the roster change below; without this the raid-wide roll switch reverts to that
    -- client's untouched default (off) and needRolls never turns true anywhere.
    RaidSim.As(stand, function() stand.env.KART_Settings.lcRollsEnabled = true end)
    RaidSim.RosterUpdate(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(70)

    T.truthy(#RaidSim.Sent(sim, "LC_ROLLS_REQ") >= 1, "the client asks the group, not just the owner")
    T.truthy(blind.KART.LC.rolls[920] ~= nil, "and a peer that still holds the table answers it")
end

-- ...at the DEFAULT vote window, which is the only setting that matters -------------------------
-- The case above widens lcVoteSeconds to 90 to look at recovery minutes in. At the default 20 the
-- repair could not fire at all, and every raid runs the default: the heartbeat ticks every 10s, so
-- the first tick naming the roll lands at t=10 and only stamps rollReqSent; the escalation needs
-- another 30s on top, by which time the roll had dropped out of LC.OpenRollIDs at t=20 and nothing
-- was left to trigger from. An item is now askable for as long as it is still on the table
-- (LC.RollTracked), which is precisely the window in which the council is scoring it.
do
    local sim = F.NewRaid()
    local blind = sim.byName.Corvin

    F.Drop(sim, 930, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    RaidSim.As(blind, function() blind.KART.LC.rolls[930] = nil end)
    T.eq(blind.KART.LC.rolls[930], nil, "the client that lost the table has no rolls for the item")

    -- Same handover as above: the announcer goes, the stand-in has no roster snapshot for the item
    -- and refuses the whispered ask (B118), so only the group-wide escalation can repair this.
    RaidSim.Leave(sim, "Bramor")
    local stand = sim.byName.Merrit
    RaidSim.As(stand, function() stand.env.KART_Settings.lcRollsEnabled = true end)
    RaidSim.RosterUpdate(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(70) -- well past the 20s vote window the old predicate stopped at

    T.truthy(#RaidSim.Sent(sim, "LC_ROLLS_REQ") >= 1,
        "an item still on the table is asked about after its voting timer has run out")
    T.deep_eq(blind.KART.LC.rolls[930], stand.KART.LC.rolls[930],
        "and a peer repairs it at the default vote window, not only at a stretched one")
end

-- A missing ITEM is catchable after voting closed too, and arrives without a vote row -------------
-- The accepted other half of the same decision. A raider who is not on the council stops tracking a
-- roll a second after its deadline (Vote.PruneExpiredRolls), so this is what a lost LC_START looks
-- like from the outside once the timer is gone. The catch-up must not answer it with a one-second
-- vote window -- the row would flash up and the prune sweep would tear the whole repair back down a
-- tick later, numbers included.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    -- Held back only long enough to see the roll actually gone. Without this the repair lands on the
    -- same heartbeat tick that the expiry sweep runs on, and the test could not tell a client that
    -- lost the item from one that never did.
    RaidSim.Blackhole(sim, "LC_ROLL_CATCHUP")
    F.Drop(sim, 931, F.GLOVES)
    local lootedAt = raider.KART.LC.rollLootedAt[931]
    KARTTEST.AdvanceTime(25) -- past the default 20s window: the plain raider has dropped the roll
    T.eq(raider.KART.LC.rollItems[931], nil, "a plain raider stops tracking a roll once voting closes")
    T.eq(F.HasVoteRow(raider, 931), false, "and has no row for it")

    RaidSim.Deliver(sim, "LC_ROLL_CATCHUP")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35) -- past ROLL_REQ_COOLDOWN, then the next heartbeat, ask and answer

    T.truthy(raider.KART.LC.rollItems[931] ~= nil, "the item is handed back while it is still on the table")
    T.deep_eq(raider.KART.LC.rolls[931], lm.KART.LC.rolls[931], "with the numbers that go with it")
    T.eq(F.HasVoteRow(raider, 931), false, "and without a vote on something that closed")
    T.truthy(raider.KART.LC.rollDeadlines[931] <= GetTime(),
        "its deadline stays in the past rather than being reopened")
    -- A repair minutes after the drop must not restart the four-hour BoP trade window; the stamp the
    -- client took when the item really dropped outlives the roll for exactly this reason.
    T.eq(raider.KART.LC.rollLootedAt[931], lootedAt,
        "and its trade clock still runs from the drop, not from the repair")
end

-- ...but what a client PUT AWAY is not what a client lost -------------------------------------------
-- The other side of the same widening. A council member awards the item and closes its tab, which is
-- the ordinary end-of-item gesture and now happens well after voting closed -- leaving that client
-- looking exactly like one that never received the roll: no item, no deadline, nothing tracked. The
-- owner still has its own tab, so its heartbeat keeps naming the roll, and before LC.rollDismissed the
-- request that produced put the tab straight back on screen (panel un-minimized, LC.councilPanelDismissed
-- cleared with it) every thirty seconds for the rest of the distribution.
do
    local sim = F.NewRaid()
    local council = sim.byName.Merrit

    local function tabbed(client, rollID)
        for _, id in ipairs(client.KART.LC.councilTabs) do if id == rollID then return true end end
        return false
    end

    F.Drop(sim, 940, F.GLOVES)
    KARTTEST.AdvanceTime(25) -- past the default 20s window: voting is closed, the item is not
    T.eq(tabbed(council, 940), true, "a council member still has the item tabbed after voting closes")

    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(940) end)
    T.eq(tabbed(council, 940), false, "and closing the tab takes it off the panel")

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(45) -- several heartbeats, and past ROLL_REQ_COOLDOWN on top of them

    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == council.name then asks = asks + 1 end
    end
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLLS_REQ")) do
        if e.from == council.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "it never asks for an item it threw away itself")
    T.eq(tabbed(council, 940), false, "so the tab it closed stays closed")
    T.eq(council.KART.LC.rollItems[940], nil, "and the item stays untracked")
end

-- ...and what it put away is an ITEM, not the number the item arrived under (B132) ------------------
-- Blizzard hands the same rollID to an unrelated drop within seconds on trash. The note above was kept
-- by number alone, so a council member who closed one item's tab was then deaf to the NEXT item under
-- that number: the heartbeat gate refused to ask for it and an arriving catch-up was refused on top of
-- that, for the rest of the round. The client that missed the announcement is the one this costs, and
-- it is exactly the client the whole heartbeat exists for.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 950, F.GLOVES)
    KARTTEST.AdvanceTime(25) -- voting closed, the item still on the owner's table
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(950) end)
    T.eq(council.KART.LC.rollItems[950], nil, "the council member is finished with the gloves")

    -- The number comes back for a weapon, and Blizzard raises no roll for it on this one client --
    -- dead, released or out of range -- so the owner's announcement is the only way it could learn of
    -- the drop at all. Blackholing that broadcast costs the rest of the raid nothing: every other
    -- client has its own START_LOOT_ROLL and tracks the weapon from that.
    RaidSim.Blackhole(sim, "LC_START")
    F.Drop(sim, 950, F.WEAPON, { noRollFor = { Merrit = true } })
    RaidSim.Deliver(sim, "LC_START")
    T.eq(council.KART.LC.rollItems[950], nil, "and hears nothing about the weapon that reuses its number")

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(45) -- heartbeats, and ROLL_REQ_COOLDOWN on top of them

    T.truthy(tostring(council.KART.LC.rollItems[950]):match("item:" .. F.WEAPON),
        "the repair reaches it anyway, for the item it never dismissed")
    T.deep_eq(council.KART.LC.rolls[950], lm.KART.LC.rolls[950], "with the numbers that go with it")
end

-- The two halves of that note, side by side ---------------------------------------------------------
-- A catch-up naming the item this client put away is an answer to an ask made before the tab was
-- closed, and taking it would put the tab straight back on screen. One naming a different item is a
-- roll nobody here has decided anything about. Handed over by hand, because the two differ in nothing
-- but the item in the payload.
--
-- On the client Blizzard raised no roll for, which is who a catch-up is written for in the first
-- place: with a roll of its own the item comes back off GetLootRollItemLink whatever the payload said,
-- and the two cases would be indistinguishable here.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 951, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(951) end)

    RaidSim.As(council, function()
        council.KART.LC.HandleRollCatchup("951:15:item:" .. F.GLOVES, lm.guid)
    end)
    T.eq(council.KART.LC.rollItems[951], nil, "the item it dismissed is still refused")

    RaidSim.As(council, function()
        council.KART.LC.HandleRollCatchup("951:15:item:" .. F.WEAPON, lm.guid)
    end)
    T.truthy(tostring(council.KART.LC.rollItems[951]):match("item:" .. F.WEAPON),
        "and a different item under the same number is taken")
end

-- A note for a roll the owner no longer lists is forgotten -------------------------------------------
-- The other narrowing: a dismissal outlives the roll it names on purpose, but once the owner's
-- heartbeat stops naming that rollID the roll has left the table and the note can only ever block a
-- later reuse of the number. Forgetting it is not a deletion from silence -- nothing this client holds
-- is dropped, and asking is driven entirely by what the heartbeat DOES list.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 952, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(952) end)
    T.truthy(council.KART.LC.rollDismissed[952] ~= nil, "the closed tab is noted")

    -- The owner is finished with it too, so its next heartbeat names an item that is not this one.
    RaidSim.As(lm, function() lm.KART.LC.Council.CloseCouncilTab(952) end)
    F.Drop(sim, 953, F.PLATE_CHEST)
    KARTTEST.AdvanceTime(12) -- one heartbeat, naming 953 and nothing else

    T.eq(council.KART.LC.rollDismissed[952], nil,
        "and dropped once the owner stops listing the roll it was about")
end

-- ...and exactly one peer answers ---------------------------------------------------------------
-- Every client in the raid holds this table. Answering all at once is the message storm this whole
-- rework exists to remove, so the answer is spread by each client's position in the sorted roster and
-- anybody who sees somebody else's answer drops their own.
do
    local sim = F.NewRaid()
    F.Drop(sim, 921, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local asker = sim.byName.Alric
    RaidSim.As(asker, function() asker.KART.LC.rolls[921] = nil end)
    RaidSim.ClearLog(sim)
    RaidSim.As(asker, function() asker.KART.LC.SendLC("LC_ROLLS_REQ:921") end)
    KARTTEST.AdvanceTime(5)

    T.eq(#RaidSim.Sent(sim, "LC_ROLLS:921:"), 1, "one answer reaches the group, not one per peer")
    T.truthy(asker.KART.LC.rolls[921] ~= nil, "and the asker has the table again")
end

-- The spread holds at a full raid, not just this fixture's five ------------------------------------
-- A hash of each client's own name was tried first here and measured to not hold at raid size: two
-- clients landing within a few milliseconds of each other is common enough (simulated: 25 random
-- names, 20,000 trials, the exact hash that was here -- 26% of full rosters collided that closely)
-- that ordinary addon-message jitter under a busy loot round's ChatThrottleLib queue can beat the
-- stand-down to it. LC.RollsAnswerSlot instead places each client by its POSITION in the sorted
-- roster, which guarantees N clients divide the window into N equal gaps -- provable directly, with
-- no simulated raid and no message delivery at all, which is the point of testing the function on its
-- own rather than the traffic it produces.
do
    local _, lm = F.NewRaid()
    local LC = lm.KART.LC

    local keys = {}
    for i = 1, 40 do keys[i] = string.format("Player-1096-%08X", i) end
    table.sort(keys)

    local slots = {}
    for i, key in ipairs(keys) do slots[i] = LC.RollsAnswerSlot(keys, key) end
    table.sort(slots)

    local minGap = math.huge
    for i = 2, #slots do minGap = math.min(minGap, slots[i] - slots[i - 1]) end
    -- The floor this is checked against, not the exact value: it only has to stay comfortably above
    -- ordinary addon-message jitter, and the guarantee holds for any N up to the addon's own maximum
    -- group size (LC.DrawRollTable's roll pool is sized for 40) -- not just the 250ms that size
    -- happens to work out to.
    T.truthy(minGap > 0.2, "a full 40-player raid still keeps every answer at least 200ms apart")

    -- No two clients share a slot. This is what the stand-down actually rests on -- a gap floor says
    -- nothing about two keys landing on the SAME instant, which is the failure the name hash had.
    local taken = {}
    for _, slot in ipairs(slots) do
        T.eq(taken[slot], nil, "no two clients in a full raid are scheduled for the same instant")
        taken[slot] = true
    end

    -- What makes two clients agree, stated as something that can actually be measured: the slot
    -- follows a key's POSITION in a roster every client sorts the same way, and nothing whatsoever
    -- about the key itself. That is the whole difference from the name hash (7123117) -- two clients
    -- holding one roster now agree by construction rather than by luck.
    --
    -- The second list is built independently, and from a DIFFERENT raid: forty names sharing nothing
    -- with the ones above. Reversing `keys` and re-sorting it, which is what stood here, cannot fail
    -- -- sorting a permutation of a sorted list gives that same list back, so the assertion compared
    -- the function against itself on one list and proved only that table.sort is deterministic.
    -- Whoever sits seventh in this second roster has to get the same slot as whoever sits seventh in
    -- the first, and a hash of the name gets that wrong on the first line.
    local otherRaid = {}
    for i = 1, 40 do otherRaid[i] = string.format("Player-2711-%08X", i * 3) end
    table.sort(otherRaid)
    T.eq(LC.RollsAnswerSlot(otherRaid, otherRaid[7]), LC.RollsAnswerSlot(keys, keys[7]),
        "the slot follows a client's position in the sorted roster, not anything about its name")
end
