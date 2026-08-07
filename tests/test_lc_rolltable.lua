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
    -- The numbers ride inside the drop's own announcement, so that message IS the roll table on the
    -- wire; LC_ROLLS is left as the repair form (see the catch-up cases further down).
    T.eq(#RaidSim.Messages(sim, "LC_DROP:"), 1, "the whole raid's rolls travel as one message")
    T.eq(RaidSim.Messages(sim, "LC_DROP:")[1].from, lm.name, "and the lootmaster is the one who sent it")
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

    F.Drop(sim, 903, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    -- The numbers ride inside the drop's own announcement, so no token drops them on their own any
    -- more. The state under test is the same one it always was -- a client holding the item and none
    -- of its numbers -- so it is set up directly, exactly as the peer-answer cases below do.
    RaidSim.As(blind, function() blind.KART.LC.rolls[903] = nil end)
    T.eq(blind.KART.LC.rolls[903], nil, "the client that lost the table has no rolls for the item")

    -- The heartbeat is what makes it notice. Nothing is re-broadcast: it asks, and the owner answers
    -- that one client.
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(15)

    -- Counted per client rather than raid-wide: what this checks is the one thing the heartbeat
    -- promises each of them on its own -- asked for, not re-asked for while an answer could already
    -- be on its way.
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
--
-- The second heartbeat now has to be EARNED. The owner repeats an unchanged table only every
-- TABLE_RESEND_SECONDS, which is the same thirty seconds as the cooldown, so waiting for one proves
-- nothing about the cooldown at all -- what it throttles is the burst a CHANGING table produces. So
-- another item drops, the owner says so within a poll interval, and the count below is what stands
-- between that message and a second ask for 906.
do
    local sim = F.NewRaid()
    local blind = sim.byName.Corvin

    F.Drop(sim, 906, F.GLOVES)
    KARTTEST.AdvanceTime(0.5)
    RaidSim.As(blind, function() blind.KART.LC.rolls[906] = nil end)
    T.eq(blind.KART.LC.rolls[906], nil, "the client that lost the table has no rolls for the item")

    -- The catch-up's own LC_ROLLS is HELD rather than let through -- so the first ask's answer never
    -- lands, and the second heartbeat still finds the table missing.
    RaidSim.Hold(sim, "LC_ROLLS")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(3)  -- the first heartbeat, and the ask it produces
    F.Drop(sim, 907, F.WEAPON)
    KARTTEST.AdvanceTime(5)  -- the table has changed, so the owner says so again -- well inside 30s

    T.truthy(#RaidSim.Sent(sim, "LC_TABLE") >= 2,
        "two heartbeats really did go out inside one cooldown")

    -- Both spellings of the ask: the first goes to the owner (LC_ROLL_REQ) and a second one for a
    -- table still missing would escalate to the raid (LC_ROLLS_REQ), so counting only the first
    -- token would pass on a cooldown that had been deleted outright.
    local blindAsks = 0
    for _, token in ipairs({ "LC_ROLL_REQ:906", "LC_ROLLS_REQ:906" }) do
        for _, e in ipairs(RaidSim.Sent(sim, token)) do
            if e.from == blind.name then blindAsks = blindAsks + 1 end
        end
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
-- repair could not fire at all, and every raid runs the default: the first heartbeat naming the roll
-- only stamps rollReqSent, and the escalation needs another 30s on top -- so even now that the first
-- one lands within a couple of seconds, the roll had dropped out of LC.OpenRollIDs at t=20 and
-- nothing was left to trigger from. An item is now askable for as long as it is still on the table
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
-- The accepted other half of the same decision, on the client it was decided FOR: one that never
-- heard the announcement at all -- dead, released or out of range at the drop (no roll of its own),
-- and the broadcast lost on top. Until B135 this test reached "not tracked" by letting an INFORMED
-- raider expire the roll, as a stand-in for the deaf one; the two really are indistinguishable to
-- the OWNER, but not to the asker, and the expired client asking again is exactly the burst B135
-- measured. So the deaf client is now built the way :B132's test below builds one, and the expired
-- client has its own test after this one, asserting the opposite.
-- The catch-up must not answer with a one-second vote window either -- the row would flash up and
-- the prune sweep would tear the whole repair back down a tick later, numbers included.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    RaidSim.Blackhole(sim, "LC_DROP")
    -- The repair itself is held back too, or there is no "after voting closed" to test: the
    -- heartbeat names the missing item within seconds and the deaf client would be caught up while
    -- the window still runs -- which is the ordinary repair other tests already cover.
    RaidSim.Blackhole(sim, "LC_ROLL_CATCHUP")
    F.Drop(sim, 931, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1) -- the announcement goes out -- and is lost -- inside the blackhole
    RaidSim.Deliver(sim, "LC_DROP")
    T.eq(raider.KART.LC.rollItems[931], nil, "the deaf raider knows nothing of the drop")

    KARTTEST.AdvanceTime(25) -- past the default 20s window: voting closes without it ever knowing
    RaidSim.Deliver(sim, "LC_ROLL_CATCHUP")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35) -- past ROLL_REQ_COOLDOWN, then the next heartbeat, ask and answer

    T.truthy(raider.KART.LC.rollItems[931] ~= nil, "the item is handed back while it is still on the table")
    T.deep_eq(raider.KART.LC.rolls[931], lm.KART.LC.rolls[931], "with the numbers that go with it")
    T.eq(F.HasVoteRow(raider, 931), false, "and without a vote on something that closed")
    T.truthy(raider.KART.LC.rollDeadlines[931] <= GetTime(),
        "its deadline stays in the past rather than being reopened")
    -- The deaf client never saw the loot event, so its BoP trade clock can only date from the
    -- repair. That errs towards a reminder that outlives the real window, which is the accepted
    -- direction for a client that may yet be handed the item (LC.HandleRollCatchup's comment).
    T.truthy(raider.KART.LC.rollLootedAt[931] ~= nil,
        "and the repair leaves it a trade clock to run on")
end

-- ...but a raider that WATCHED the window close does not ask for the item back (B135) --------------
-- The other half of the split above, and the cut that empties the lootmaster's queue: an informed
-- raider whose roll expired (Vote.PruneExpiredRolls) knows exactly what it freed. Re-asking bought
-- nothing -- the answer is a closed item with no vote row -- and it cost 27 raiders x 6 items x 2
-- whispered answers from the owner in one synchronized burst per boss, which is the 1,578-message
-- queue of 2026-08-05 (see docs/BACKLOG.md, B135). The roll the raider might still be missing
-- NUMBERS for is untouched: needRolls has its own ask, and C13 keeps it.
do
    local sim = F.NewRaid()
    local raider = sim.byName.Alric

    F.Drop(sim, 933, F.GLOVES)
    KARTTEST.AdvanceTime(2)
    T.truthy(raider.KART.LC.rollItems[933] ~= nil, "the raider was told about the drop")
    local lootedAt = raider.KART.LC.rollLootedAt[933]
    T.truthy(lootedAt ~= nil, "and stamped its trade clock at the loot event")

    KARTTEST.AdvanceTime(23) -- past the default 20s window: the plain raider frees the roll
    T.eq(raider.KART.LC.rollItems[933], nil, "a plain raider stops tracking a roll once voting closes")

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(40) -- a forced heartbeat repeat and a full ROLL_REQ_COOLDOWN

    T.eq(#RaidSim.Sent(sim, "LC_ROLL_REQ"), 0, "nobody asks for an item everybody watched close")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0, "so the owner's queue stays empty")
    T.eq(raider.KART.LC.rollItems[933], nil, "and the freed roll stays freed")
    T.eq(raider.KART.LC.rollLootedAt[933], lootedAt,
        "while the trade clock still runs from the drop, in case the council awards it here")

    -- Blizzard reuses the number for a different item: the note about the expired roll must not
    -- make this client deaf to a drop nobody here ever decided about (the B132 rule, again).
    F.Drop(sim, 933, F.WEAPON)
    KARTTEST.AdvanceTime(2)
    T.truthy(tostring(raider.KART.LC.rollItems[933]):match("item:" .. F.WEAPON),
        "a reused rollID reaches it like any fresh drop")
end

-- ...and the heartbeat alone releases the expiry note, like the dismissal note above (B132 shape) ----
-- The reuse case above learns of the new item from its own START_LOOT_ROLL / the announcement. This
-- client gets neither: no roll of its own, the announcement lost, rolls off for the raid -- the
-- heartbeat is the only message that will ever name the new item to it. The suppression test holds
-- one half of B135 (an expired roll is not re-asked about); this holds the other half, on the branch
-- in LC.HandleTable that compares the note against the item the heartbeat names: without it, this
-- client's own note about the OLD item keeps the gate closed against the NEW one for the rest of the
-- round, and a raider never learns an item existed.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 970, F.GLOVES)
    KARTTEST.AdvanceTime(25) -- past the default 20s window: the plain raider frees the roll
    T.eq(raider.KART.LC.rollItems[970], nil, "the raider watched the gloves close and freed them")
    T.truthy(raider.KART.LC.rollExpiredHere[970] ~= nil, "and holds the note that says so")

    -- The number comes back for a weapon; Blizzard raises no roll for it here and the announcement
    -- is lost, so the heartbeat is this client's only possible source for the drop.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 970, F.WEAPON, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    T.eq(raider.KART.LC.rollItems[970], nil, "and hears nothing about the weapon that reuses its number")

    -- A few seconds, not a full window: the owner's heartbeat changed with the reuse and goes out on
    -- the next tick, the freed note has no ask on cooldown, and the catch-up lands while the weapon's
    -- window still runs. Waiting the window out instead would show the ORDINARY end of that repair --
    -- a plain raider's re-tracked roll expires and is freed with a fresh note, this time about the
    -- weapon -- and the assertion would read that as the clear never having fired.
    KARTTEST.AdvanceTime(6)

    T.truthy(raider.KART.LC.rollExpiredHere[970] ~= tostring(F.GLOVES),
        "the heartbeat naming a DIFFERENT item under that number drops the note about the old one")
    T.truthy(tostring(raider.KART.LC.rollItems[970]):match("item:" .. F.WEAPON),
        "and the drop nobody here watched close reaches it, off the heartbeat alone")
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
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 950, F.WEAPON, { noRollFor = { Merrit = true } })
    -- Past the window the drop is collected in, so the announcement is made -- and lost -- while the
    -- blackhole is still up.
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
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

-- ...and the SAME refusal holds once the note carries a generation (B139) ----------------------------
-- The block above closes the tab a single second after the drop -- before TABLE_POLL_SECONDS (2s) has
-- let a single heartbeat through, so LC.rollInstance[951] is still empty and the note it stamps is
-- bare. That is not the ordinary case: within a couple of seconds of any drop the roll has a
-- generation, and the guard has to keep refusing a same-item catch-up once the note carries one --
-- comparing its ITEM half through LC.RollNoteParts rather than the note whole. Before that fix,
-- "249331@1" never compared equal to a bare "249331" itemID, the refusal stopped firing at all, and a
-- catch-up already in flight when the tab closed reopened the card it had just been put away from.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 952, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(3)   -- past TABLE_POLL_SECONDS: at least one heartbeat has named the roll
    T.eq(council.KART.LC.rollInstance[952], "1", "the heartbeat has named the roll's first instance")

    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(952) end)
    T.eq(council.KART.LC.rollDismissed[952], tostring(F.GLOVES) .. "@1",
        "the note is stamped WITH the generation the heartbeat just named, not bare")

    RaidSim.As(council, function()
        council.KART.LC.HandleRollCatchup("952:15:item:" .. F.GLOVES, lm.guid)
    end)
    T.eq(council.KART.LC.rollItems[952], nil,
        "a catch-up for the SAME item is still refused with a generation-suffixed note")
    T.eq(F.HasVoteRow(council, 952), false, "no vote row comes back with it")
    local function tabbed(client, rollID)
        for _, id in ipairs(client.KART.LC.councilTabs) do if id == rollID then return true end end
        return false
    end
    T.eq(tabbed(council, 952), false, "and the tab it closed stays closed")
end

-- ...and the heartbeat alone is enough, with nothing else on the wire that names the item (B132) -----
-- The case above is repaired in practice by LC_ROLLS: the roll table names its item, so a client that
-- missed the announcement learns of the reuse from it. A raid can simply have rolls switched off, and
-- then the heartbeat is the ONLY message that reaches this client at all -- so it has to carry the
-- item itself. While it named nothing but numbers, this client was deaf to the new drop for the rest
-- of the round: its own note refused the ask, and nothing else was ever going to tell it otherwise.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 960, F.GLOVES)
    KARTTEST.AdvanceTime(25) -- voting closed, the item still on the owner's table
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(960) end)
    T.truthy(council.KART.LC.rollDismissed[960] ~= nil, "the council member is finished with the gloves")

    -- Same shape as the case above: the number comes back for a weapon and Blizzard raises no roll for
    -- it here, so the owner is this client's only possible source for the drop -- and its announcement
    -- is lost.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 960, F.WEAPON, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    T.eq(council.KART.LC.rollItems[960], nil, "and hears nothing about the weapon that reuses its number")
    T.eq(#RaidSim.Sent(sim, "LC_ROLLS:"), 0, "with no roll table anywhere to learn the reuse from")

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(45) -- heartbeats, and ROLL_REQ_COOLDOWN on top of them

    T.eq(council.KART.LC.rollDismissed[960], nil,
        "the heartbeat naming a DIFFERENT item under that number is what drops the note")
    T.truthy(tostring(council.KART.LC.rollItems[960]):match("item:" .. F.WEAPON),
        "and the item nobody here ever dismissed reaches it, off the heartbeat alone")
end

-- ...and an item it cannot READ is repaired in place, not thrown away (B132) -------------------------
-- A client that was dead or out of range at the drop can be handed an announcement that names no item
-- at all -- the owner had not resolved the link when it sent it -- and it parks "???" (B40). When the
-- heartbeat later names that item concretely, "I cannot show what I hold is the same item" looks like
-- a reuse and is not: a heartbeat is a REPEAT of the roll, not a start, and unlike LC.HandleStart it
-- re-tracks nothing afterwards. Purging there costs this client the whole raid's cards for an item
-- nobody ever reused, and the round trip that would repair it is refusable -- a stand-in has no
-- LC.rollEligible for a roll it never announced (LC.MayCatchUp). The itemID is in the message, so the
-- card is repaired from it and nothing is cleared.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit
    local raider, sinja = sim.byName.Alric, sim.byName.Sinja

    local function tabbed(client, rollID)
        for _, id in ipairs(client.KART.LC.councilTabs) do if id == rollID then return true end end
        return false
    end

    -- Blizzard raises no roll on this client, and the announcement that reaches it carries no item.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 980, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.As(council, function() council.KART.LC.HandleStart("980:20:", lm.guid) end)
    -- ...and the numbers with it. They travel inside the announcement, so losing that message loses
    -- both -- and this case is specifically about the client that has everything EXCEPT a readable
    -- item, which is what makes an ask for anything at all a failure below.
    local table980 = RaidSim.As(lm, function() return lm.KART.LC.SerializeRollTable(980) end)
    RaidSim.As(council, function()
        council.KART.LC.HandleRolls(table980:match("^LC_ROLLS:(.*)$"), lm.guid)
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(council.KART.LC.rollItems[980], "???", "the council member holds an item it cannot read")
    T.eq(tabbed(council, 980), true, "tabbed all the same, because the decision is still its own")

    -- The raid votes on it. This is what a purge would take with it.
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(980, 1) end)
    RaidSim.As(sinja, function() sinja.KART.LC.Vote.CastVote(980, 2) end)
    KARTTEST.AdvanceTime(0)
    local cards = {}
    for key, vote in pairs(council.KART.LC.votes[980] or {}) do cards[key] = vote end
    T.truthy(next(cards) ~= nil, "and the raid's cards for it reach the council member")
    local deadline = council.KART.LC.rollDeadlines[980]

    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(11) -- one heartbeat, naming 980 as the gloves it always was

    T.truthy(tostring(council.KART.LC.rollItems[980]):match("item:" .. F.GLOVES),
        "the heartbeat names the item, and the card it could not read becomes readable")
    T.deep_eq(council.KART.LC.votes[980], cards, "with every card that was cast on it still there")
    T.eq(council.KART.LC.rollDeadlines[980], deadline, "the deadline it always had")
    T.eq(tabbed(council, 980), true, "and the tab it decides on still on the panel")

    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == council.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "nothing had to be asked for: the repair was in the message")
end

-- A stand-in's shorter table is not evidence a dismissal is over -------------------------------------
-- The reverse of the rule that used to stand here. Absence was read as "the roll has left the table,
-- so the note about it can go" -- and a stand-in's table is legitimately SHORTER than the previous
-- owner's, because it holds only what this client itself announced. Reading that as "everything else
-- is gone" forgets a note that is still valid, and the previous owner's next heartbeat then puts the
-- closed tab back on screen. The note now goes only when an item is actually named under that number,
-- so a list that simply does not mention it says nothing at all.
do
    local sim = F.NewRaid()
    local council = sim.byName.Merrit
    -- The raid leader is a plain RAIDER here, which is the shortest table there is: nobody tabs
    -- anything for them, so Vote.PruneExpiredRolls frees a roll a second after its deadline. That is
    -- the stand-in this guild actually gets when the lootmaster ports out mid-distribution.
    RaidSim.Promote(sim, "Alric")

    F.Drop(sim, 970, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(970) end)
    T.truthy(council.KART.LC.rollDismissed[970] ~= nil, "the closed tab is noted")

    RaidSim.Leave(sim, "Bramor")
    local stand = sim.byName.Alric
    RaidSim.RosterUpdate(sim)
    RaidSim.As(stand, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
    KARTTEST.AdvanceTime(25) -- past 970's window: the stand-in has dropped it, the council has not
    T.eq(stand.KART.LC.rollItems[970], nil, "the stand-in no longer holds the roll the note is about")

    -- It announces one of its own, and Blizzard raises no roll for it on the council member -- so the
    -- ask that follows is proof this client read the heartbeat rather than ignored its sender.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 971, F.PLATE_CHEST, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(12) -- one heartbeat from the stand-in, naming 971 and nothing else

    local asked = false
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == council.name then asked = true end
    end
    T.eq(asked, true, "the council member acts on the stand-in's own, shorter table")
    T.truthy(council.KART.LC.rollDismissed[970] ~= nil,
        "and a roll that table never mentions leaves the dismissal exactly where it was")
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

    -- The same arithmetic has a second caller now (the vote heartbeat, whose window is shorter than
    -- the roll table's), so the spread is a parameter rather than a constant baked into one
    -- function. Both properties that matter have to survive that: the window is respected, and the
    -- position -- not the key -- is what decides.
    local narrow = {}
    for i, key in ipairs(keys) do narrow[i] = LC.AnswerSlot(keys, key, 4) end
    for _, slot in ipairs(narrow) do
        T.truthy(slot >= 0 and slot < 4, "a slot never leaves its own window")
    end
    T.eq(LC.AnswerSlot(keys, keys[7], 4) * 2.5, LC.AnswerSlot(keys, keys[7], 10),
        "the same position scales with the window it is given")
    T.eq(LC.RollsAnswerSlot(keys, keys[7]), LC.AnswerSlot(keys, keys[7], 10),
        "the roll table's own caller keeps the ten seconds it always had")
end

-- B139: the heartbeat says WHICH instance of a roll it means ----------------------------------------
-- Blizzard reuses roll numbers within seconds, and the itemID under the number cannot tell a repeat
-- of the heartbeat from a second copy of the SAME item. The owner counts the rolls it starts under
-- each number and puts that count on the wire; everything downstream compares it.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    local function lastTable()
        local sent = RaidSim.Messages(sim, "LC_TABLE")
        return sent[#sent] and sent[#sent].msg or ""
    end

    F.Drop(sim, 980, F.GLOVES)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35)   -- at least one heartbeat, and past TABLE_RESEND_SECONDS
    T.truthy(lastTable():match("980=" .. F.GLOVES .. "@1"),
        "the first roll under a number is generation 1")

    -- The number comes back for a SECOND COPY OF THE SAME ITEM, which is the case the itemID cannot
    -- see. The owner is on its own roll here, so its counter moves.
    F.Drop(sim, 980, F.GLOVES)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35)
    T.truthy(lastTable():match("980=" .. F.GLOVES .. "@2"),
        "and the second copy under that number is generation 2")
    T.eq(raider.KART.LC.rollInstance[980], "2",
        "a receiver remembers the generation it last heard, as a string like every other wire field")

    -- An owner holding no counter for a roll already on the table -- a stand-in who took the role
    -- over mid-round, or one who reloaded -- sends the entry bare. That is the RIGHT degradation:
    -- counting on every client instead would give the raid several counters that only agree if every
    -- client saw every roll start, and a wrong generation purges live state where an absent one
    -- purges nothing.
    RaidSim.As(lm, function() wipe(lm.KART.LC.rollGeneration) end)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(35)
    T.truthy(lastTable():match("980=" .. F.GLOVES .. "$"),
        "an owner with no counter for the roll sends the entry bare")
    T.eq(raider.KART.LC.rollInstance[980], "2",
        "and a bare entry leaves the receiver's memory alone rather than erasing it")
end

-- ...and a note about a roll that ended here records that instance ----------------------------------
-- The note is what gates this client's re-ask (B135). It has always held WHICH item ended, so the
-- number alone could not silence it for an unrelated drop (B132); it now holds which instance of that
-- item, which is the half B139 needs.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric
    local council = sim.byName.Merrit

    -- Rolls off raid-wide keeps the assertions about the notes free of roll-table traffic.
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 981, F.GLOVES)
    KARTTEST.AdvanceTime(25)   -- past the 20s window: the plain raider frees the roll and stamps it
    T.eq(raider.KART.LC.rollExpiredHere[981], tostring(F.GLOVES) .. "@1",
        "the expiry note names the item AND the instance of it that ended here")

    F.Drop(sim, 982, F.GLOVES)
    KARTTEST.AdvanceTime(25)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(982) end)
    T.eq(council.KART.LC.rollDismissed[982], tostring(F.GLOVES) .. "@1",
        "and so does the note a council member leaves when it closes a tab")

    local item, gen = lm.KART.LC.RollNoteParts(tostring(F.GLOVES) .. "@3")
    T.eq(item, tostring(F.GLOVES), "a note splits back into its item...")
    T.eq(gen, "3", "...and its generation")
    local plainItem, plainGen = lm.KART.LC.RollNoteParts(tostring(F.GLOVES))
    T.eq(plainItem, tostring(F.GLOVES), "a note with no generation still yields its item")
    T.eq(plainGen, nil, "and says nothing about the instance")
    local unknownItem, unknownGen = lm.KART.LC.RollNoteParts(true)
    T.eq(unknownItem, nil, "an unresolved note yields no item...")
    T.eq(unknownGen, nil, "...and no generation")
end

-- ...and a SECOND COPY of the same item under that number is a new roll, not a repeat (B139) --------
-- The case the itemID cannot see, and the reason the generation exists. This client watched copy 1's
-- window close, so it holds a note; Blizzard hands the number to copy 2 of the SAME item; this client
-- gets no roll of its own for it (dead, released, out of range) and loses the announcement. Before
-- the generation, its note compared equal to the heartbeat forever and it never learned copy 2
-- existed -- for the rest of the round, with nothing on screen to notice it by.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    F.Drop(sim, 985, F.GLOVES)
    KARTTEST.AdvanceTime(25)
    T.eq(raider.KART.LC.rollItems[985], nil, "the raider watched the gloves close and freed them")
    T.eq(raider.KART.LC.rollExpiredHere[985], tostring(F.GLOVES) .. "@1",
        "and holds a note naming the instance that ended")

    -- Blackholing LC_DROP costs the rest of the raid nothing: every other client has its own
    -- START_LOOT_ROLL and tracks the second copy from that.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 985, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    T.eq(raider.KART.LC.rollItems[985], nil,
        "and hears nothing about the second copy under that number")

    -- A few seconds, not a full window: the owner's heartbeat changed with the reuse and goes out on
    -- the next tick, the freed note has no ask on cooldown, and the catch-up lands while the second
    -- copy's own window still runs.
    KARTTEST.AdvanceTime(6)

    T.eq(raider.KART.LC.rollExpiredHere[985], nil,
        "the heartbeat naming a new generation drops the note about the instance that ended")
    T.truthy(tostring(raider.KART.LC.rollItems[985]):match("item:" .. F.GLOVES),
        "and the second copy reaches it, off the heartbeat alone")

    -- ...and the repair is not a loop. Once this client tracks copy 2 its note, when copy 2's own
    -- window closes, names generation 2 -- which is what the owner keeps saying. A rule that kept
    -- firing here would be the B135 burst again: one ask every thirty seconds for the rest of the
    -- round.
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(60)
    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == raider.name then asks = asks + 1 end
    end
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLLS_REQ")) do
        if e.from == raider.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "and no heartbeat after the repair asks again")
end

-- ...while a heartbeat that names no generation changes nothing ------------------------------------
-- A stand-in owner holds no counter for the rolls already on the table. Unknown is not a mismatch --
-- the same rule the itemID has always followed -- so the notes stay exactly as they are and this
-- client stays quiet about a roll it deliberately finished with.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 986, F.GLOVES)
    KARTTEST.AdvanceTime(25)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(986) end)
    T.eq(council.KART.LC.rollItems[986], nil, "the council member is finished with the item")

    RaidSim.As(lm, function() wipe(lm.KART.LC.rollGeneration) end)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(45)   -- several heartbeats, and past ROLL_REQ_COOLDOWN on top of them

    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == council.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "a heartbeat with no generation in it does not reopen what this client put away")
    T.truthy(council.KART.LC.rollDismissed[986] ~= nil, "and the note survives it")
end

-- ...and the dismissal note survives LC_ROLLS traffic too, then releases off the heartbeat (B139) ----
-- LC.ForgetDismissalIfReused is B132's OTHER caller (LC.HandleRolls), and unlike the heartbeat its
-- payload carries no generation at all -- "rollID:@itemID:numbers", bare. A rolled-numbers message for
-- the SAME item cannot prove a reuse by itself, so the note has to survive it and wait for the
-- heartbeat's generation to say so instead. Left with rolls ENABLED (unlike the two blocks above,
-- which turn lcRollsEnabled off): this is the path that reaches LC.ForgetDismissalIfReused at all.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 989, F.GLOVES)
    KARTTEST.AdvanceTime(25)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(989) end)
    T.eq(council.KART.LC.rollDismissed[989], tostring(F.GLOVES) .. "@1",
        "the council member's note names the item and the instance it closed")

    -- A rolled-numbers table for the SAME item, exactly the shape LC.HandleRolls answers with --
    -- handed to the handler directly, as the catch-up tests above do, because the organic broadcast
    -- only fires after a full escalation cycle this test has no need to wait out.
    RaidSim.As(council, function()
        council.KART.LC.HandleRolls("989:@" .. F.GLOVES .. ":15=42,20=7", lm.guid)
    end)
    T.truthy(council.KART.LC.rollDismissed[989] ~= nil,
        "a rolled-numbers message for the SAME item does not release the note by itself")

    -- Blackholing LC_DROP costs the rest of the raid nothing: every other client has its own
    -- START_LOOT_ROLL and tracks the second copy from that.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 989, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    T.eq(council.KART.LC.rollItems[989], nil,
        "and hears nothing about the second copy under that number")

    -- A few seconds, not a full window: the owner's heartbeat changed with the reuse and goes out on
    -- the next tick, and the dismissal note has no ask on cooldown to defer it.
    KARTTEST.AdvanceTime(6)

    T.eq(council.KART.LC.rollDismissed[989], nil,
        "the heartbeat naming a new generation releases the dismissal note")
    T.truthy(tostring(council.KART.LC.rollItems[989]):match("item:" .. F.GLOVES),
        "and the second copy reaches it, off the heartbeat alone")
end

-- ...and the loot role moving mid-round is the case the owner-only guard exists for (B139) -----------
-- LC.OnStartLootRoll only bumps LC.rollGeneration `if LC.IsLootOwner() then` -- the two blocks above
-- get to the same starting point by wipe()ing the counter table directly, which exercises the SYMPTOM
-- (an owner with no counter for a roll) without ever touching the guard that produces it. This drives
-- the real mechanism: a stand-in who was never owner while a roll's starts happened, the way the
-- lootmaster ports out mid-distribution and the raid leader takes over (see LC.IsLootOwner) or a
-- designation simply changes (tests/test_lc_ownership.lua:34-38 shows the pattern this codebase uses
-- to move the role between two named clients).
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric
    local newOwner = sim.byName.Merrit

    F.Drop(sim, 990, F.GLOVES)
    KARTTEST.AdvanceTime(25)   -- past the 20s window: the plain raider frees the roll and stamps it
    T.eq(raider.KART.LC.rollExpiredHere[990], tostring(F.GLOVES) .. "@1",
        "the raider's note names the item and the instance that ended, generation 1 from the owner at drop time")

    -- The designation moves to Merrit, who was in the raid for the drop above (so OnStartLootRoll DID
    -- run on its client) but was never loot owner while it ran, so it counted none of it.
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    T.truthy(RaidSim.As(newOwner, newOwner.KART.LC.IsLootOwner), "the loot role now belongs to Merrit")
    T.eq(newOwner.KART.LC.rollGeneration[990], nil,
        "and it holds no counter for roll 990 -- it was never the owner while any start of it happened")

    -- The new owner still tracks the roll (it was in the raid when LC_DROP announced it, and is
    -- council, so nothing has pruned it) -- called directly rather than waited out on its own ticker,
    -- which nothing here ever started for Merrit (LC.EnsureTableTicker only runs for the client that
    -- was owner AT THE MOMENT a roll started or force-won one of its own).
    RaidSim.ClearLog(sim)
    RaidSim.As(newOwner, newOwner.KART.LC.SendTableHeartbeat)
    KARTTEST.AdvanceTime(1)
    local sent = RaidSim.Messages(sim, "LC_TABLE")
    local lastTable = sent[#sent] and sent[#sent].msg or ""
    T.truthy(lastTable:match("990=" .. F.GLOVES .. "$"),
        "the new owner's heartbeat names the roll bare -- no generation, because it counted none of its starts")

    T.eq(raider.KART.LC.rollExpiredHere[990], tostring(F.GLOVES) .. "@1",
        "and the raider's stamped note survives it untouched -- an absent generation is not a mismatch")
end

-- ...and a roll that never resolves its item still expires cleanly with a generation known (B139) -----
-- LC.StampRollNote's `type(itemID) ~= "string"` guard is what an unresolved "???" roll (B40) relies
-- on: Vote.PruneExpiredRolls always stamps a note through this function, and without the guard
-- `true .. "@" .. gen` -- concatenating a boolean with the generation -- is a hard Lua error on the
-- expiry sweep, which otherwise runs silently once a second.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    -- Blizzard raised no roll here and the announcement that reaches it carries no item (B40), the
    -- same construction the "cannot READ it" block above uses.
    RaidSim.As(raider, function() raider.KART.LC.HandleStart("993:20:", lm.guid) end)
    T.eq(raider.KART.LC.rollItems[993], "???", "the raider tracks an item it never managed to read")

    -- A generation this client heard for the roll despite never learning what it held -- the exact
    -- combination that would concatenate a boolean with a number.
    raider.KART.LC.rollInstance[993] = "1"

    KARTTEST.AdvanceTime(25)   -- past the window: Vote.PruneExpiredRolls stamps the note

    T.eq(raider.KART.LC.rollExpiredHere[993], true,
        "the note for an unresolved roll stays the boolean it always was -- never concatenated with the generation")
end

-- Gap 1 (mutation-run survivor, B139): the catch-up refusal must hold for a roll dismissed while still
-- unresolved ("???") -------------------------------------------------------------------------------
-- LC.HandleRollCatchup refuses a catch-up under a dismissed rollID only when the two items can be
-- compared, and LC.RollNoteParts answers `nil, nil` for the boolean `true` a "???" dismissal leaves
-- behind -- exactly a pair that cannot be compared. The pre-B139 behaviour was to refuse on the rollID
-- alone whenever that happens, which is the conservative answer: unlike the resolved case two blocks
-- above, where a genuinely different item IS taken (B132), an unresolved dismissal cannot tell a repeat
-- from a reuse at all, so it takes neither. Nothing tested it, so a client that put away a roll it never
-- managed to read could have LC_ROLL_CATCHUP push it straight back onto the panel, whatever item the
-- catch-up named.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    local function tabbed(client, rollID)
        for _, id in ipairs(client.KART.LC.councilTabs) do if id == rollID then return true end end
        return false
    end

    -- The same construction the "cannot READ it" block above uses: Blizzard raises no roll here, and
    -- the announcement that reaches this client carries no item at all (B40), so it tracks "???".
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 954, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.As(council, function() council.KART.LC.HandleStart("954:20:", lm.guid) end)
    T.eq(council.KART.LC.rollItems[954], "???", "the council member holds an item it cannot read")
    T.truthy(tabbed(council, 954), "and is tabbed all the same")

    -- Closed without ever having resolved the item, so the note it stamps is the bare boolean.
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(954) end)
    T.eq(council.KART.LC.rollDismissed[954], true,
        "the dismissal note is the boolean true -- this client never learned what it held")

    -- A catch-up naming the item it may well have held is refused...
    RaidSim.As(council, function()
        council.KART.LC.HandleRollCatchup("954:15:item:" .. F.GLOVES, lm.guid)
    end)
    T.eq(council.KART.LC.rollItems[954], nil,
        "...and a catch-up naming the item this client may have dismissed is refused")
    T.eq(tabbed(council, 954), false, "with the tab it closed staying closed")

    -- ...and so is one naming a different item: an unresolved dismissal cannot tell the two apart, so
    -- it refuses on the rollID alone either way, rather than guess.
    RaidSim.As(council, function()
        council.KART.LC.HandleRollCatchup("954:15:item:" .. F.WEAPON, lm.guid)
    end)
    T.eq(council.KART.LC.rollItems[954], nil,
        "a different item is refused too -- the id alone is all this client has")
    T.eq(tabbed(council, 954), false, "and the tab stays closed")
end

-- Gap 2 (mutation-run survivor, B139): LC.ForgetDismissalIfReused must not throw away an unresolved
-- dismissal note ------------------------------------------------------------------------------------
-- Same shape as Gap 1 from the other end: LC.RollNoteParts answers `nil, nil` for the boolean `true`
-- a "???" dismissal leaves behind, so `dismissedItem` is nil and the guard's `dismissedItem and` is
-- the only thing stopping ANY message that names an item from wiping the note -- after which the ask
-- gates open and this client starts asking again for the roll it deliberately closed. Driven through
-- LC.HandleRolls, one of its two real callers, rather than called directly.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    -- The same "cannot READ it" construction as Gap 1: this client tracks "???", never resolves it,
    -- and dismisses it anyway.
    RaidSim.Blackhole(sim, "LC_DROP")
    F.Drop(sim, 955, F.GLOVES, { noRollFor = { Merrit = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(sim, "LC_DROP")
    RaidSim.As(council, function() council.KART.LC.HandleStart("955:20:", lm.guid) end)
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(955) end)
    T.eq(council.KART.LC.rollDismissed[955], true,
        "the dismissal note is the boolean true -- this client never learned what it held")

    -- A rolled-numbers message naming a real item under the same number -- the shape LC.HandleRolls
    -- always carries, and the only thing the guard has to compare the unresolved note against.
    RaidSim.As(council, function()
        council.KART.LC.HandleRolls("955:@" .. F.GLOVES .. ":15=42,20=7", lm.guid)
    end)
    T.eq(council.KART.LC.rollDismissed[955], true,
        "the note survives -- an unresolved dismissal cannot be compared against a named item, so it is left alone")
end

-- Gap 3 (mutation-run survivor, B139): an expiry note stamped with NO generation must not be purged by
-- a heartbeat that carries one --------------------------------------------------------------------
-- LC.HandleTable's expiry-note guard only releases a note on a generation mismatch when the NOTE
-- itself carries a generation (`expiredGen`) -- a bare note said nothing about the instance, so a
-- heartbeat naming one is not evidence against it. The mirror case (a note WITH a generation against a
-- bare wire) and the dismissal note's own version of this rule are both covered; this is the one
-- combination nothing exercised: a note stamped bare because the roll expired before any heartbeat had
-- named it, followed by the first heartbeat that does.
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric

    -- No heartbeat may reach this client before the roll expires, or LC.rollInstance[956] would
    -- already hold a generation by the time Vote.PruneExpiredRolls stamps the note -- the ordinary
    -- case the B139 block above already covers. TABLE_POLL_SECONDS is 2s and the vote window is 20s,
    -- so the heartbeat has to be suppressed outright rather than merely outrun.
    RaidSim.Blackhole(sim, "LC_TABLE")
    F.Drop(sim, 956, F.GLOVES)
    KARTTEST.AdvanceTime(25)   -- past the window: Vote.PruneExpiredRolls stamps the note

    T.eq(raider.KART.LC.rollInstance[956], nil, "no heartbeat ever reached this client")
    T.eq(raider.KART.LC.rollExpiredHere[956], tostring(F.GLOVES),
        "the note is bare -- stamped before any generation was known, not \"...@1\"")

    RaidSim.ClearLog(sim)
    RaidSim.Deliver(sim, "LC_TABLE")
    RaidSim.As(lm, lm.KART.LC.SendTableHeartbeat)
    KARTTEST.AdvanceTime(0)

    T.eq(raider.KART.LC.rollInstance[956], "1", "the heartbeat has now named the roll's first instance")
    T.eq(raider.KART.LC.rollExpiredHere[956], tostring(F.GLOVES),
        "and the bare note survives it -- it never claimed to know an instance, so a generation on the wire is not a mismatch")
    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ:956")) do
        if e.from == raider.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "so no ask goes out for the item this client already watched close")
end

-- Gap 4 (mutation-run survivor, B139): PurgeStaleRoll clearing the PREVIOUS roll's generation ---------
-- A roll STARTING under a reused number makes the remembered generation the previous roll's, not this
-- one's -- PurgeStaleRoll clears LC.rollInstance[rollID] for exactly that reason, unconditionally and
-- before anything else. That matters most for the case its OWN item comparison cannot catch: a SECOND
-- physical drop of the SAME item under the reused number (two identical trash mobs) looks, item for
-- item, exactly like Blizzard re-raising the roll that is still running, so PurgeStaleRoll returns
-- without ever reaching Trade.ClearRollState (which would otherwise clear the generation too, on the
-- genuinely-different-item path). Only the unconditional clear at the top resets it here. Without it, a
-- note stamped from a tab closed in the narrow window before the first heartbeat for the NEW roll would
-- carry the OLD roll's generation, and the next heartbeat -- correctly naming the new one -- would then
-- read that as a mismatch and purge a note that was right: one needless ask for an item this client had
-- already put away. The window is under two seconds (a heartbeat every TABLE_POLL_SECONDS), which is
-- why nothing hit it by accident.
do
    local sim, lm = F.NewRaid()
    local council = sim.byName.Merrit

    F.Drop(sim, 957, F.GLOVES)
    KARTTEST.AdvanceTime(3)   -- past TABLE_POLL_SECONDS: the heartbeat names the first instance
    T.eq(council.KART.LC.rollInstance[957], "1", "the council member remembers generation 1")

    -- A second, physically distinct drop reuses the number for the SAME item. PurgeStaleRoll runs as
    -- part of every client's own OnStartLootRoll, so this is synchronous -- no heartbeat and no
    -- LC_DROP round trip needed for the clear to fire, if it fires at all.
    F.Drop(sim, 957, F.GLOVES)
    T.eq(council.KART.LC.rollInstance[957], nil,
        "PurgeStaleRoll clears the previous roll's generation even though the item comparison alone sees nothing stale")

    -- Within the window: closed before any heartbeat has named the new roll at all.
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(957) end)
    T.eq(council.KART.LC.rollDismissed[957], tostring(F.GLOVES),
        "the note carries no generation -- not \"...@1\", the previous roll's -- because the clear got there first")

    -- The heartbeat now arrives naming the new roll's real instance, generation 2.
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, lm.KART.LC.SendTableHeartbeat)
    KARTTEST.AdvanceTime(0)

    T.eq(council.KART.LC.rollInstance[957], "2", "the heartbeat has now named the second roll's instance")
    T.eq(council.KART.LC.rollDismissed[957], tostring(F.GLOVES),
        "and the bare note survives it -- it never claimed an instance, so a generation on the wire is not a mismatch")
    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ:957")) do
        if e.from == council.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "so no needless ask goes out for the item this client already put away")
end

-- B145 gaps 1-4 (B149 mutation run): "a round that ended is not a gap to repair" --------------------
-- B145's rule: once a round ends, a client must stop asking the owner about the rolls it was in the
-- middle of repairing -- a heartbeat from before End Round can still be in flight and land afterwards.
-- LC.rollRoundEnded is the note that says so, and LC.ClearAllRolls writes it from TWO different
-- tables: LC.rollItems (a client that held something) and LC.rollReqSent (a client that only ever
-- ASKED). The second is the half the whole entry turns on -- a DEAF client, one that never received
-- the announcement at all, holds no LC.rollItems, so the first loop notes nothing for it. It is
-- exactly the client B145 exists for, and it is built the same way in all four gaps below: excluded
-- from Blizzard's own roll (F.Drop's noRollFor) and from the network announcement (LC_DROP
-- blackholed), unlike the "???" construction used elsewhere in this file (a hand-fed LC_START with no
-- item, which still tracks SOMETHING). This client tracks nothing at all -- only that it asked.

-- Builds that client: F.Drop's noRollFor keeps Blizzard from ever raising the roll on it, and
-- blackholing LC_DROP loses the announcement too, so LC.rollItems[rollID] never gets set. A table
-- heartbeat reaches it regardless (LC_TABLE is never blackholed) and it asks for what it cannot see;
-- LC_ROLL_CATCHUP is blackholed too, so the reply is lost and LC.rollReqSent stays the only trace of
-- the roll this client ever holds -- exactly what Gap 1 needs to be testing the right half of.
local function DeafAsksOnce(sim, deaf, rollID, itemID)
    RaidSim.Blackhole(sim, "LC_DROP")
    RaidSim.Blackhole(sim, "LC_ROLL_CATCHUP")
    F.Drop(sim, rollID, itemID, { noRollFor = { [deaf.name] = true } })
    KARTTEST.AdvanceTime(1)
    T.eq(deaf.KART.LC.rollItems[rollID], nil, "the deaf client never heard the announcement at all")
    KARTTEST.AdvanceTime(3) -- past TABLE_POLL_SECONDS: the first heartbeat reaches it
    T.truthy(deaf.KART.LC.rollReqSent[rollID] ~= nil, "and has asked about the roll it never heard of")
    T.eq(deaf.KART.LC.rollItems[rollID], nil, "asking is not hearing -- it still holds nothing")
end

-- Gap 1: LC.ClearAllRolls's rollReqSent loop, and Gap 2: the round-ended gate in LC.HandleTable ------
-- Run together on purpose (per the task): reaching Gap 2 needs a note that only Gap 1's mechanism can
-- produce, so one scenario that drives both beats two that half-drive each.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Sinja
    DeafAsksOnce(sim, deaf, 1000, F.GLOVES)

    -- A second heartbeat is on its way, still naming 1000 -- held rather than delivered, so it can
    -- land AFTER the round ends instead of before it. That is exactly the shape B145 exists for: a
    -- heartbeat sent before End Round, still in flight when it lands.
    RaidSim.Hold(sim, "LC_TABLE")
    KARTTEST.AdvanceTime(30) -- past TABLE_RESEND_SECONDS, so the owner says it again

    -- The round ends while the deaf client's ask is the only thing it holds under 1000.
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    T.truthy(deaf.KART.LC.rollRoundEnded and deaf.KART.LC.rollRoundEnded[1000],
        "Gap 1 (B145): LC.ClearAllRolls's rollReqSent loop notes the round ended for a client the " ..
        "rollItems loop never sees at all -- the deaf client the whole entry turns on")

    -- The stale heartbeat lands now, still naming a roll whose round is over.
    RaidSim.ClearLog(sim)
    local released = RaidSim.Release(sim, "LC_TABLE")
    T.truthy(released > 0, "the heartbeat held since before End Round lands only now")
    local asked = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == deaf.name then asked = asked + 1 end
    end
    T.eq(asked, 0,
        "Gap 2 (B145): the round-ended gate in LC.HandleTable stops a heartbeat in flight from " ..
        "resurrecting an ask for a round that is already over")
end

-- Gap 3: PurgeStaleRoll clears the round-ended note when the roll genuinely restarts ------------------
-- Without this, a fresh roll under a number whose round ended is refused for the rest of the session
-- -- the note outlives the thing it was about.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Sinja
    DeafAsksOnce(sim, deaf, 1010, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    T.truthy(deaf.KART.LC.rollRoundEnded and deaf.KART.LC.rollRoundEnded[1010],
        "the setup: the round-ended note is in place for 1010, same construction as Gaps 1 and 2")

    -- Blizzard hands the SAME number to a genuinely NEW roll, and this time deaf sees it -- included
    -- in Blizzard's own roll again, so its own local OnStartLootRoll runs PurgeStaleRoll(1010, ...)
    -- itself, independent of the network (LC_DROP is still blackholed from the setup above).
    F.Drop(sim, 1010, F.WEAPON)
    KARTTEST.AdvanceTime(1)

    T.eq(deaf.KART.LC.rollRoundEnded[1010], nil,
        "Gap 3 (B145): PurgeStaleRoll clears the stale round-ended note when the roll genuinely restarts")
    T.truthy(tostring(deaf.KART.LC.rollItems[1010]):match("item:" .. F.WEAPON),
        "and the fresh roll is tracked normally -- not refused for the rest of the session")
end

-- Gap 4: TearDownForRaidExit wipes the round-ended notes on the way out -------------------------------
-- Narrow, and the task said to report it rather than force it if it could not be reached: it needs a
-- client that leaves the raid, rejoins, and is THEN deaf to a reused number -- because any roll start
-- it DOES see runs PurgeStaleRoll, which clears the note per rollID (Gap 3), and would prove the wrong
-- mechanism. Reached here via KARTTEST.solo, the same "ported out" tool tests/test_lc_churn.lua uses
-- to drive a real LC.CheckRaidJoin exit-and-teardown, confirmed over RAID_EXIT_CONFIRM_DELAY rather
-- than assumed.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Sinja
    DeafAsksOnce(sim, deaf, 1020, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    T.truthy(deaf.KART.LC.rollRoundEnded and deaf.KART.LC.rollRoundEnded[1020],
        "the setup: the round-ended note is in place for 1020, same construction as Gaps 1 and 2")

    -- deaf ports out of the raid entirely, and the exit has to actually be CONFIRMED
    -- (RAID_EXIT_CONFIRM_DELAY) for TearDownForRaidExit to run at all -- what tells this apart from
    -- the roster blip LC.CheckRaidJoin is written to tolerate and must not tear down on.
    KARTTEST.solo[deaf.unit] = true
    RaidSim.As(deaf, function() deaf.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)
    KARTTEST.solo[deaf.unit] = nil
    RaidSim.As(deaf, function() deaf.KART.LC.CheckRaidJoin() end) -- back in, a new raid as far as LC knows

    -- The "new" raid hands out the SAME number, and deaf is deaf to it again -- excluded from
    -- Blizzard's own roll AND from the announcement (LC_DROP is still blackholed), so nothing on this
    -- client ever runs PurgeStaleRoll for 1020. Only the heartbeat reaches it, exactly as in the setup.
    F.Drop(sim, 1020, F.WEAPON, { noRollFor = { [deaf.name] = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(3)

    local asked = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == deaf.name then asked = asked + 1 end
    end
    T.truthy(asked > 0,
        "Gap 4 (B145): TearDownForRaidExit wiped the stale round-ended note on the way out, so the " ..
        "new raid's roll under the same number is askable again")
end
