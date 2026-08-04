-- The Loot Council base flow, across several real clients at once.
--
-- The maintainer's own words for what has to hold, ten times out of ten, and what four raid nights
-- failed to deliver:
--
--     Items droppen, jeder kann das Item sehen, seinen Button drücken und das Council sieht das
--     und kann verteilen.
--
-- Everything here is that sentence, made executable. Each assertion names which half it defends.
-- The raid itself, the item fixtures and the verbs that drive them live in tests/lc_fixture.lua.

local F = dofile("tests/lc_fixture.lua")
local RaidSim, MEMBERS = F.RaidSim, F.MEMBERS
local NewRaid, Drop, Owes, CouncilOf, HasVoteRow = F.NewRaid, F.Drop, F.Owes, F.CouncilOf, F.HasVoteRow

-- ===================================================================================
-- The session and the config reach everybody
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()

    for _, c in ipairs({ council, raider }) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " sees the session as running")
        T.eq(c.KART.LC.raidConfig.lootmaster, lm.guid, c.name .. " knows who the lootmaster is")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            c.name .. " uses the RAID's roll setting, not their own default")
    end
    -- Wrapped, like every call into client code: "player" only means someone while that client is
    -- the one executing, which is exactly what makes a multi-client harness able to tell them apart.
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil), "a configured council member is council")
    T.truthy(not RaidSim.As(raider, raider.KART.LC.IsCouncil), "a plain raider is not")
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG"), 1, "the config went out exactly once")
end

-- ===================================================================================
-- "Jeder kann das Item sehen"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 41, 249331)
    -- Past the collection window a drop is held in, so the announcement has actually gone out.
    KARTTEST.AdvanceTime(1)

    for _, c in ipairs(sim.clients) do
        local link = c.KART.LC.rollItems[41]
        T.truthy(c.KART.LC.IsRealItemLink(link), c.name .. " holds a real item link, not a placeholder")
        T.truthy(tostring(link):find("Ezzorak", 1, true), c.name .. " holds the RIGHT item")

        local listed = false
        for _, id in ipairs(c.KART.LC.voteListRolls) do if id == 41 then listed = true end end
        T.truthy(listed, c.name .. " has the item in their vote window")
    end

    -- The lootmaster has to physically win it to be able to trade it onward.
    T.eq(KARTTEST.rolled[41] and KARTTEST.rolled[41][lm.unit], 1, "the lootmaster rolled Need")
    T.eq(KARTTEST.rolled[41] and KARTTEST.rolled[41][raider.unit], 0, "a raider auto-passed")
    T.truthy(council.KART.LC.councilTabs[1] == 41, "the council panel has a tab for it")
end

-- ===================================================================================
-- "Seinen Button drücken und das Council sieht das"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 42, 249331)

    RaidSim.As(raider,  function() raider.KART.LC.Vote.CastVote(42, 1) end)
    RaidSim.As(council, function() council.KART.LC.Vote.CastVote(42, 2) end)

    local votes = lm.KART.LC.votes[42] or {}
    T.truthy(votes[raider.guid], "the lootmaster sees the raider's vote")
    T.truthy(votes[council.guid], "the lootmaster sees the council member's vote")
    T.eq(votes[raider.guid] and votes[raider.guid].idx, 1, "and the raider's choice is the one they pressed")
    T.eq(votes[council.guid] and votes[council.guid].idx, 2, "and the council member's is theirs")

    -- A fingerprint of the button SET travels with the vote, so a client whose list differs says
    -- "unknown" instead of confidently showing the wrong label. That guard is why a whole evening's
    -- votes were once read wrong -- and it used to be the count alone, which cannot see a
    -- same-length rename (B43).
    T.eq(votes[raider.guid] and votes[raider.guid].count,
        RaidSim.As(lm, function() return lm.KART.LC.ButtonFingerprint() end),
        "the vote carries a fingerprint of the sender's button set")
end

-- ===================================================================================
-- "Und kann verteilen"
-- ===================================================================================
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 43, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(43, 1) end)

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(43, raider.guid, "BIS") end)

    T.eq(lm.KART.LC.assignedWinners[43], raider.guid, "the lootmaster recorded the winner")
    T.eq(council.KART.LC.assignedWinners[43], raider.guid, "and the council sees the same winner")
    T.truthy(lm.KART.LC.pendingTrades and next(lm.KART.LC.pendingTrades),
        "the lootmaster is reminded to hand it over")

    -- Whoever decided it must not be left staring at a live vote row for an item already given out.
    -- Asserted directly rather than by looping over the list: the list is empty by then, so a loop
    -- body checking each entry ran zero times and proved nothing -- it would have passed just as
    -- happily if the item had never been added in the first place.
    for _, c in ipairs(sim.clients) do
        T.truthy(not HasVoteRow(c, 43), c.name .. " no longer has the decided item in their vote window")
    end
end

-- ===================================================================================
-- A client that never got its own loot roll still sees the item
-- ===================================================================================
-- Dead, out of range, ineligible, or simply beaten to it by the addon message. This is GitHub #12,
-- #13 and #16, reported by three people in one evening -- one of whom was alive and in range the
-- whole time, which is why the fix cannot depend on the reason.
do
    local sim, _, _, raider = NewRaid()
    Drop(sim, 44, 249293, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)

    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[44]),
        "a client with no loot roll of its own still ends up with a real link")
    T.truthy(tostring(raider.KART.LC.rollItems[44]):find("Weight of Command", 1, true),
        "and it is the right item")
end

-- The same, with the item not yet in the client's cache: the name cannot be known yet, but the
-- icon can, and the link must upgrade itself the moment the item arrives.
do
    local sim, _, _, raider = NewRaid()
    KARTTEST.items[249293].cached = false
    Drop(sim, 45, 249293, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)

    local parked = raider.KART.LC.rollItems[45]
    T.truthy(tostring(parked):find("item:249293", 1, true),
        "an uncached item is tracked by its ID rather than lost as '???'")

    KARTTEST.AdvanceTime(10)      -- exhaust the retry budget
    KARTTEST.CacheItem(249293)    -- the client finally learns the item
    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[45]),
        "and it becomes a real link once the item is known, however late")
    KARTTEST.items[249293].cached = nil
end

-- ===================================================================================
-- Tier tokens are ordinary Council loot; mounts are not
-- ===================================================================================
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 46, 249364)

    T.eq(KARTTEST.rolled[46] and KARTTEST.rolled[46][lm.unit], 1,
        "the lootmaster force-wins a tier token (GitHub #14)")
    T.truthy(raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[46]),
        "and every raider gets to vote on it")

    -- The whole chain, because the Manifest's C12 names it: a token is ordinary Council loot, so it
    -- has to be decidable and handable-over like any other piece. C6 and C12 are two sides of one
    -- check -- a token and a mount sit in the same item class and differ only by subclass -- and
    -- stopping at "it was force-won" would leave the half that actually gives somebody the item
    -- untested.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(46, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[46], raider.guid, c.name .. " names the same winner")
    end
    T.truthy(F.Owes(lm.KART.LC.pendingTrades, 46), "the holder owes it to them")
    T.truthy(F.Owes(raider.KART.LC.owedToMe, 46), "and the winner is told they are owed it")
end

-- ===================================================================================
-- A boss drops more than one item, and sometimes the same one twice
-- ===================================================================================
-- Both are ordinary, and both are places where one roll's state can leak into another's: the tracked
-- tables are keyed by rollID, and two rolls of the SAME item differ in nothing else.
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 47, 249331)
    Drop(sim, 48, 249293)
    Drop(sim, 49, 249331)     -- the same item as roll 47, a second time
    -- All three fell inside one collection window, so this is also the moment they arrive.
    KARTTEST.AdvanceTime(1)

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.voteListRolls, 3, c.name .. " has a row for each of the three drops")
    end
    T.eq(#council.KART.LC.councilTabs, 3, "and the council has a tab for each")

    -- Votes have to land on the roll they were cast on, not on the other copy of the same item.
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(47, 1) end)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(49, 3) end)
    T.eq((lm.KART.LC.votes[47] or {})[raider.guid].idx, 1, "the first copy carries its own vote")
    T.eq((lm.KART.LC.votes[49] or {})[raider.guid].idx, 3, "and the second copy carries its own")
    T.truthy(not (lm.KART.LC.votes[48] or {})[raider.guid], "and the other item has none")

    -- Deciding one leaves the others alone.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(47, raider.guid, "BIS") end)
    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.voteListRolls, 2, c.name .. " is left with exactly the two undecided items")
    end
    T.truthy(not lm.KART.LC.assignedWinners[49], "the second copy of the item is still undecided")

    -- And both copies can go to different people.
    local sinja = sim.byName.Sinja
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(49, sinja.guid, "Upgrade") end)
    T.eq(council.KART.LC.assignedWinners[47], raider.guid, "the first copy went to one player")
    T.eq(council.KART.LC.assignedWinners[49], sinja.guid, "the second to another")
    -- Both, as two separate obligations. This read `#Owes(...) and 1 or 0 == 1` before, which is the
    -- constant 1 in Lua -- `#entry` on a hash-keyed table is 0, and 0 is truthy. It asserted nothing
    -- about the trade and could only ever fail by crashing.
    T.truthy(Owes(lm.KART.LC.pendingTrades, 47), "the lootmaster owes the first copy")
    T.truthy(Owes(lm.KART.LC.pendingTrades, 49), "and the second, as a separate obligation")
    T.eq(#lm.KART.LC.pendingTrades, 2, "two items owed, not one collapsed entry")
end

-- The item link has not reached this client yet -- a brand-new drop whose data has not propagated.
-- Deciding without it would mean deciding without a classID, so a mount would read as ordinary gear
-- and be force-won; retrying is the only safe answer, and it has to keep going long enough to
-- actually work. Blizzard's roll timer runs for minutes.
do
    local sim, lm = NewRaid()
    Drop(sim, 59, 249331, { linkPending = true })
    -- Well past the seven seconds the old budget gave up after -- which is where the boss dropped
    -- and nothing happened at all: no force-win, no forced pass, no LC_START, no vote window, and
    -- nothing printed.
    KARTTEST.AdvanceTime(10)

    T.eq(#RaidSim.Messages(sim, "LC_DROP"), 0, "nothing is decided while the item is unidentifiable")
    T.truthy(not (KARTTEST.rolled[59] or {})[lm.unit], "and nothing is force-won on a guess")

    -- It arrives, late. The roll must still be picked up rather than abandoned.
    KARTTEST.lootRolls[59].linkPending = nil
    KARTTEST.AdvanceTime(10)

    T.eq(#RaidSim.Messages(sim, "LC_DROP"), 1, "the roll is picked up once the item is identifiable")
    T.eq(KARTTEST.rolled[59] and KARTTEST.rolled[59][lm.unit], 1, "and force-won then")
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[59]), c.name .. " gets the item")
    end
end

-- Blizzard reissues roll IDs within a session -- several trash corpses looted in the same second is
-- the documented trigger. When the previous roll is still parked as a bare "item:NNN" placeholder,
-- because that client had not cached the item yet, the reuse has to be recognised all the same: its
-- votes, its council tab and its vote row must not be inherited by the item that took its place.
do
    local sim, lm, council, raider = NewRaid()
    KARTTEST.items[249293].cached = false
    Drop(sim, 40, 249293, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    -- Parked as the item STRING the announcement carried, not as the bare id it used to be reduced to:
    -- the id alone would come back as the base version of the item once it caches (B119). Still not a
    -- real link, which is the state this whole scenario is about.
    T.truthy(tostring(raider.KART.LC.rollItems[40]):match("^item:249293"),
        "the raider holds the item as a string, uncached")
    T.truthy(not raider.KART.LC.IsRealItemLink(raider.KART.LC.rollItems[40]),
        "and not as a link it cannot render yet")
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(40, 1) end)
    T.truthy((lm.KART.LC.votes[40] or {})[raider.guid], "and votes on it")
    KARTTEST.items[249293].cached = nil

    -- The same roll ID comes round again, for something else entirely.
    KARTTEST.lootRolls[40] = nil
    Drop(sim, 40, 249331)
    KARTTEST.AdvanceTime(1)

    T.truthy(tostring(raider.KART.LC.rollItems[40]):find("Ezzorak", 1, true),
        "the reused roll shows the NEW item")
    T.truthy(not (raider.KART.LC.votes[40] or {})[raider.guid],
        "and does not inherit the previous item's vote")
    local tabs = 0
    for _, id in ipairs(council.KART.LC.councilTabs) do if id == 40 then tabs = tabs + 1 end end
    T.eq(tabs, 1, "and the council has one tab for it, not two")
end

-- ===================================================================================
-- What Council must never touch
-- ===================================================================================
-- STANDING DECISION: collectibles and Bind-on-Equip drops stay out entirely, at any rarity. The
-- lootmaster cannot hand out through the BoP trade window what he never physically holds, so a
-- council decision on one is a decision nobody can execute — and with Auto-Pass on by default,
-- force-passing them would hand every mount to whichever raider is NOT running KART.
--
-- This has gone wrong in both directions already: once by force-winning housing decor, once by
-- letting a tier token be treated as a collectible. The rule is asserted from both sides here.
do
    local sim, lm, _, raider = NewRaid()

    Drop(sim, 55, 249400)                       -- a mount
    Drop(sim, 56, 249401, { bop = false })      -- Bind-on-Equip
    Drop(sim, 57, 249402)                       -- Bind-on-Pickup, but below the raid's minimum
    Drop(sim, 58, F.PET)                        -- a battle pet
    Drop(sim, 59, F.HOUSING)                    -- a housing item, in a subclass nothing enumerates

    for _, id in ipairs({ 55, 56, 57, 58, 59 }) do
        T.truthy(not KARTTEST.rolled[id] or KARTTEST.rolled[id][lm.unit] ~= 1,
            "the lootmaster does not force-win roll " .. id)
        for _, c in ipairs(sim.clients) do
            T.truthy(not c.KART.LC.rollItems[id],
                c.name .. " never sees roll " .. id .. " in Loot Council")
        end
    end
    -- Auto-Pass is the raider's own preference and applies to anything Council would have handled,
    -- regardless of the raid's rarity threshold -- but never to a mount or a BoE.
    T.eq(KARTTEST.rolled[57] and KARTTEST.rolled[57][raider.unit], 0,
        "an Auto-Pass raider still passes on a low-rarity BoP drop")
    T.truthy(not (KARTTEST.rolled[55] or {})[raider.unit], "but is left to roll on a mount themselves")
    T.truthy(not (KARTTEST.rolled[56] or {})[raider.unit], "and on a Bind-on-Equip")
    -- The lootmaster clears the low-rarity item out rather than hoarding it.
    T.eq(KARTTEST.rolled[57] and KARTTEST.rolled[57][lm.unit], 0,
        "and the lootmaster passes it too, whatever their own Auto-Pass says")
    -- The Manifest names pets and housing items next to the mount (C6), and the housing one is the
    -- case the allow-list exists for: nobody has to teach the rule about a compartment Blizzard
    -- has not shipped yet. Neither may be force-won NOR force-passed -- passing hands the raid's
    -- mounts and furniture to whichever raider is not running KART.
    for _, id in ipairs({ 58, 59 }) do
        T.truthy(not (KARTTEST.rolled[id] or {})[lm.unit],
            "roll " .. id .. " is neither won nor passed by the lootmaster")
        T.truthy(not (KARTTEST.rolled[id] or {})[raider.unit],
            "and an Auto-Pass raider is left to answer roll " .. id .. " themselves")
    end
end

-- ===================================================================================
-- /kart add — the path the maintainer used all evening
-- ===================================================================================
-- An item that never produced a loot roll on anyone's client, handed to the council by hand. It has
-- to reach every raider exactly as a real drop does.
do
    local sim, lm, council, raider = NewRaid()
    local link = KARTTEST.items[249331].link

    RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(link) end)
    KARTTEST.AdvanceTime(0)

    local rollID = lm.KART.LC.voteListRolls[1]
    T.truthy(rollID, "the lootmaster has a vote row for the item they added")
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[rollID]),
            c.name .. " received the manually added item")
    end
    T.truthy(council.KART.LC.councilTabs[1] == rollID, "and the council has a tab for it")

    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(rollID, 1) end)
    T.truthy((lm.KART.LC.votes[rollID] or {})[raider.guid], "votes come back on a manual item")
    T.truthy((lm.KART.LC.rolls[rollID] or {})[raider.guid], "and so do the 1-100 rolls")

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(rollID, raider.guid, "BIS") end)
    T.eq(council.KART.LC.assignedWinners[rollID], raider.guid, "and it can be handed out")
end

-- An item link long enough to blow the transport's 255-byte payload cap. A Midnight drop with a
-- full bonus-ID list gets there, and an oversized message is dropped silently by the transport --
-- so the lootmaster's own windows would open on an item nobody else ever heard about.
do
    local sim, lm, council, raider = NewRaid()
    local long = KARTTEST.AddItem({ id = 249500, name = "Deathbound Shoulderguards of the Eternal Vigil",
        quality = 4, ilvl = 285, classID = 4, subclassID = 4, equipLoc = "INVTYPE_SHOULDER", bind = 1,
        link = "|cffa335ee|Hitem:249500::::::::80:268::14:19:11946,10390,12043,10255,1540,10879," ..
               "11996,10336,12356,1485,10222,10395,11304,10874,12053,10260,1545,10884,12001,10401," ..
               "11310,10880,12059:1:28:2462:::::|h[Deathbound Shoulderguards of the Eternal Vigil]|h|r" })
    T.truthy(#long.link + #"LC_MANUAL_START:1000000:20:" > 255,
        "the fixture link really is long enough to blow the payload cap")

    RaidSim.As(lm, function() lm.KART.LC.StartManualRoll(long.link) end)
    KARTTEST.AdvanceTime(0)

    T.truthy(not sim.oversized, "nothing the lootmaster sent exceeded the payload cap")
    local rollID = lm.KART.LC.voteListRolls[1]
    for _, c in ipairs(sim.clients) do
        T.truthy(c.KART.LC.IsRealItemLink(c.KART.LC.rollItems[rollID]),
            c.name .. " received the long-linked item as a real link")
    end
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(rollID, 1) end)
    T.truthy((council.KART.LC.votes[rollID] or {})[raider.guid], "and it can be voted on")
end

-- A raider cannot put items in front of the council.
do
    local sim, _, _, raider = NewRaid()
    RaidSim.As(raider, function() raider.KART.LC.StartManualRoll(KARTTEST.items[249293].link) end)
    T.eq(#RaidSim.Sent(sim, "LC_MANUAL_START"), 0, "only the loot owner can add an item by hand")
end

-- ===================================================================================
-- The 1-100 roll: mandatory, from everybody, visible to everybody
-- ===================================================================================
-- Opt-in raid-wide, and this raid has it on. It is the council's tie-breaker, so a roll that only
-- some clients produce is worse than none at all -- that is what "rolls kommen nicht an von allen"
-- looked like from the council panel.
do
    local sim, lm = NewRaid()
    Drop(sim, 50, 249331)
    KARTTEST.AdvanceTime(1)

    local rolls = lm.KART.LC.rolls[50] or {}
    for _, c in ipairs(sim.clients) do
        local r = rolls[c.guid]
        T.truthy(r, "the lootmaster sees a roll from " .. c.name)
        T.truthy(type(r) == "number" and r >= 1 and r <= 100,
            c.name .. "'s roll is a number between 1 and 100")
    end

    -- Every council member scores against the same numbers, so they must agree exactly.
    for _, c in ipairs(CouncilOf(sim)) do
        for _, other in ipairs(sim.clients) do
            T.eq((c.KART.LC.rolls[50] or {})[other.guid], rolls[other.guid],
                c.name .. " sees the same roll for " .. other.name .. " as the lootmaster does")
        end
    end

    -- Exactly one table for the whole raid, drawn once: a second draw would replace a number the
    -- raid has already been shown, on the one screen that decides who gets the item.
    --
    -- RaidSim.Sent matches on the raw bytes handed to C_ChatInfo.SendAddonMessage, which for a
    -- multipart message is a chunk carrying AceComm's own control byte before the token -- a prefix
    -- match would find nothing. This only works because the fixture's payload here stays under the
    -- single-part size limit; it will fail loudly, not silently, the day this message's payload grows
    -- past that limit.
    T.eq(#RaidSim.Messages(sim, "LC_DROP:"), 1,
        "the whole raid's rolls travel as one message, not one per client")
end

-- With rolls switched off raid-wide, nobody rolls -- and nobody half-rolls.
do
    local sim, lm = NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    Drop(sim, 51, 249331)
    for _, c in ipairs(sim.clients) do
        T.truthy(not (lm.KART.LC.rolls[51] or {})[c.guid],
            "with rolls off raid-wide, " .. c.name .. " did not roll")
    end
end

-- ===================================================================================
-- The council decides together
-- ===================================================================================
do
    local sim, _, _, raider = NewRaid()
    local sinja = sim.byName.Sinja
    Drop(sim, 52, 249331)

    -- Both raiders declare an interest.
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(52, 1) end)
    RaidSim.As(sinja,   function() sinja.KART.LC.Vote.CastVote(52, 2) end)

    -- Every council member sees both, identically. A council scoring different ballots is the
    -- failure that cannot be noticed from inside the game.
    for _, c in ipairs(CouncilOf(sim)) do
        local v = c.KART.LC.votes[52] or {}
        T.eq(v[raider.guid] and v[raider.guid].idx, 1, c.name .. " sees Alric's vote")
        T.eq(v[sinja.guid] and v[sinja.guid].idx, 2, c.name .. " sees Sinja's vote")
    end

    -- The straw poll: two council members pick Alric, one picks Sinja.
    local council = CouncilOf(sim)
    RaidSim.As(council[1], function() council[1].KART.LC.Vote.ToggleCouncilVote(52, raider.guid) end)
    RaidSim.As(council[2], function() council[2].KART.LC.Vote.ToggleCouncilVote(52, raider.guid) end)
    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(52, sinja.guid) end)

    for _, c in ipairs(council) do
        local poll = c.KART.LC.councilVotes[52] or {}
        T.eq(poll[council[1].guid], raider.guid, c.name .. " sees Bramor's pick")
        T.eq(poll[council[2].guid], raider.guid, c.name .. " sees Merrit's pick")
        T.eq(poll[council[3].guid], sinja.guid,   c.name .. " sees Corvin's pick")
    end

    -- Clicking the same candidate again retracts, and that reaches everyone too.
    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(52, sinja.guid) end)
    for _, c in ipairs(council) do
        T.truthy(not (c.KART.LC.councilVotes[52] or {})[council[3].guid],
            c.name .. " sees Corvin's pick retracted")
    end
end

-- A council member who is not the lootmaster may award, and everyone converges on it -- including
-- the lootmaster, who is the one who physically holds the item.
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 53, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(53, 1) end)

    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(53, raider.guid, "BIS") end)

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[53], raider.guid,
            c.name .. " agrees on the winner a non-lootmaster council member picked")
    end
    T.truthy(lm.KART.LC.pendingTrades and next(lm.KART.LC.pendingTrades),
        "and the lootmaster -- not the assigner -- is the one reminded to trade it")
end

-- ===================================================================================
-- German and English clients in one raid must read the same vote the same way
-- ===================================================================================
-- The default button labels are localised -- "Other" against "Sonstiges" -- so language is a real
-- source of the one failure that cannot be seen from inside the game: two clients resolving the
-- same vote index to different words. The raid config is what makes them agree, which is also why
-- a raid where nobody distributes one is dangerous rather than merely degraded.
do
    local sim, lm = NewRaid()
    local de, en = sim.byName.Merrit, sim.byName.Corvin
    T.eq(de.locale, "deDE", "the raid really does contain a German client")
    T.eq(en.locale, "enUS", "and an English one")

    local labelsOf = function(c)
        local out = {}
        for i, def in ipairs(RaidSim.As(c, c.KART.LC.GetButtonConfig)) do out[i] = def.label end
        return out
    end

    T.deep_eq(labelsOf(de), labelsOf(en),
        "with a raid config in force, a German and an English client read identical vote buttons")
    T.deep_eq(labelsOf(lm), labelsOf(en), "and both match the lootmaster's")

    -- And the votes themselves survive the round trip between them.
    Drop(sim, 54, 249331)
    RaidSim.As(en, function() en.KART.LC.Vote.CastVote(54, 4) end)
    local v = de.KART.LC.votes[54] or {}
    T.eq(v[en.guid] and v[en.guid].idx, 4, "a German client receives an English client's vote")
    -- The fingerprint is over the button SET the raid agreed, not over what each client renders, so
    -- two clients in different languages running the same config match. If they did not, every
    -- cross-language vote in this guild would render as "?" -- which is the mismatch marker doing
    -- exactly the wrong thing.
    T.eq(v[en.guid] and v[en.guid].count,
        RaidSim.As(de, function() return de.KART.LC.ButtonFingerprint() end),
        "and agrees with it about which buttons there were, so no mismatch is flagged")
end

-- ===================================================================================
-- A raid that never filled in the Lootmaster field
-- ===================================================================================
-- A documented, supported setup: leave it empty and the raid leader stands in. It used to stand in
-- for the LOOT half only -- the config half had no owner at all, so no client ever received one and
-- every raider silently ran their own vote buttons, their own minimum quality and their own roll
-- setting, which defaults to off. A whole raid not rolling, with the role-status label reporting
-- that all was well (B33).
do
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)
    local lm, council, raider = sim.byName.Bramor, sim.byName.Merrit, sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster     = ""        -- deliberately blank
        lm.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "the raid leader owns the config when nobody is named")

    -- Straight away, and that is the point of the ownership rule (docs/OWNERSHIP.md). This used to
    -- wait out a ten-second grace, because ownership was a CLAIM and a leader who had declared a
    -- session without being told anything might have been about to push their own defaults over a
    -- raid that already had settings. There is nothing to arbitrate any more: the raid leader owns
    -- the config, every client derives that from its own roster, and a config from anybody else is
    -- refused outright -- so there is no case left for the wait to protect against, and holding a
    -- raid unconfigured for ten seconds at the start of an evening was its whole cost.
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG"), 1, "the leader's own settings ARE the raid's, at once")

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " is in the session")
        T.eq(RaidSim.As(c, c.KART.LC.GetRollsEnabled), true,
            c.name .. " uses the raid's roll setting rather than their own")
        T.deep_eq(RaidSim.As(c, c.KART.LC.GetButtonConfig),
                  RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
            c.name .. " reads the same vote buttons as the leader")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil),
        "and the council list reached the council")

    Drop(sim, 72, 249331)
    T.eq(KARTTEST.rolled[72] and KARTTEST.rolled[72][lm.unit], 1,
        "the stand-in still force-wins the item")
    T.truthy((lm.KART.LC.rolls[72] or {})[raider.guid], "and the raid rolls on it")
end

-- Without a config, the same two clients disagree -- documented here because it is exactly what a
-- raid with no lootmaster set looks like, and the reason that state now prints a warning.
do
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)
    local de, en = sim.byName.Merrit, sim.byName.Corvin
    local deLabels = RaidSim.As(de, de.KART.LC.GetButtonConfig)
    local enLabels = RaidSim.As(en, en.KART.LC.GetButtonConfig)
    T.truthy(deLabels[4].label ~= enLabels[4].label,
        "with no config distributed, a German and an English client name the same index differently")
end

-- ===================================================================================
-- The vote timer runs out
-- ===================================================================================
-- Raiders get a bounded window to answer; the council does not. An item whose timer expired is still
-- an item somebody has to receive, so it must stay on the council panel with every vote already cast
-- -- losing it there would mean a drop nobody can hand out.
do
    local sim, lm, council, raider = NewRaid()
    Drop(sim, 58, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(58, 1) end)

    -- Past the raid's configured voting window (lcVoteSeconds, 20 by default), and let the addon's
    -- OWN ticker do the sweeping. Calling PruneExpiredRolls from here instead would assert about the
    -- test's call rather than about the wiring -- the ticker could be severed entirely and this would
    -- still pass.
    KARTTEST.AdvanceTime(lm.env.KART_Settings.lcVoteSeconds + 5)

    T.truthy(not HasVoteRow(raider, 58), "a raider's vote row closes when the timer runs out")
    T.truthy(council.KART.LC.councilTabs[1] == 58, "the council keeps the item on its panel")
    T.truthy(council.KART.LC.IsRealItemLink(council.KART.LC.rollItems[58]),
        "and still knows which item it is")
    T.eq((council.KART.LC.votes[58] or {})[raider.guid].idx, 1,
        "and still has the vote that was cast before it expired")

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(58, raider.guid, "BIS") end)
    T.eq(council.KART.LC.assignedWinners[58], raider.guid,
        "an expired item can still be handed out")
    T.truthy(Owes(raider.KART.LC.owedToMe, 58), "and the winner is owed it")
end

-- ===================================================================================
-- The council's own controls: reassign, no winner, end round, notes
-- ===================================================================================
-- Every one of these changes what other people see, so every one of them is a place where two
-- clients can end up disagreeing. They are asserted from more than one client for that reason.
do
    local sim, lm, _, raider = NewRaid()
    local sinja = sim.byName.Sinja
    Drop(sim, 60, 249331)

    -- Award, then reassign to someone else. The second decision has to win everywhere, and the
    -- first winner's claim has to be gone -- not merely overwritten on the assigner's screen.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(60, raider.guid, "BIS") end)
    -- Reassigning asks first, deliberately: it is how an accidental double award is caught.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(60, sinja.guid, "Upgrade") end)
    T.truthy(RaidSim.As(lm, KARTTEST.AcceptPopup, "KART_LC_REASSIGN_CONFIRM"),
        "reassigning a winner asks for confirmation first")

    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.assignedWinners[60], sinja.guid, c.name .. " sees the reassigned winner")
    end
    T.truthy(not Owes(raider.KART.LC.owedToMe, 60), "the first winner is no longer owed the item")
    T.truthy(Owes(sinja.KART.LC.owedToMe, 60), "and the new winner is")
end

do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 61, 249331)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(61, raider.guid, "BIS") end)

    -- "No winner" revokes: nobody is owed it, nobody has to trade it, and the tab is gone for the
    -- council too, since that decision is broadcast.
    -- Exactly what the panel's "No Winner" button does, in its order. The assigner never receives
    -- its own broadcast, so every step it performs for the raid it must also perform for itself.
    RaidSim.As(lm, function()
        lm.KART.LC.Trade.AnnounceResult(61, "NONE")
        lm.KART.LH.RemoveHistoryForRoll(61)
        lm.KART.LC.Trade.ClearWinnerObligations(61)
        lm.KART.LC.Council.CloseCouncilTab(61)
    end)

    T.truthy(not Owes(raider.KART.LC.owedToMe, 61), "revoking clears the winner's claim")
    for _, c in ipairs(sim.clients) do
        T.truthy(not c.KART.LC.assignedWinners[61], c.name .. " no longer shows a winner")
    end
end

-- Clearing the loot history has to keep it cleared -------------------------------------------------
-- Reported by the maintainer, 2026-08-01: "I clear the history and another player syncs it straight
-- back, so at the start of a season I still have last tier's items in the list."
--
-- LH.RequestHistorySync asks for everything newer than the newest entry it holds. After a clear that
-- is zero, which reads as "send me everything" -- so the catch-up faithfully rebuilt what had just
-- been deleted. Switching the sync off is not the answer either: the whole point of it is that items
-- decided while you were absent still reach your list, and that list is what gets exported.
--
-- A clear is a personal "my history starts here" line. The request already carries a since-timestamp,
-- so nothing about the protocol changes: it just stops asking about anything older than that line.
do
    local sim, lm, _, raider = NewRaid()
    local threeDaysAgo = time() - 3 * 24 * 60 * 60
    for _, c in ipairs({ lm, raider }) do
        RaidSim.As(c, function()
            c.KART.LH.LogHistory(KARTTEST.items[249293].link, "Alric", "BIS", "MAGE", nil, 47, raider.guid)
        end)
        c.env.KART_LootHistory[1].time = threeDaysAgo
    end
    T.eq(#lm.env.KART_LootHistory, 1, "both clients hold last tier's award")

    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)
    T.eq(#lm.env.KART_LootHistory, 0, "the history is cleared")

    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    T.eq(#lm.env.KART_LootHistory, 0, "and stays cleared -- nobody syncs last tier back in")
    -- Not merely discarded on arrival: the request itself says where the history starts, so a peer
    -- with thirty old entries sends nothing at all rather than thirty messages nobody wants.
    T.eq(#RaidSim.Sent(sim, "LC_HIST_ENTRY"), 0, "and nothing is put on the wire for it either")

    -- ...and the catch-up still does the job it exists for: an award decided while this client was
    -- away, AFTER the line was drawn, still reaches the list that gets exported.
    KARTTEST.AdvanceTime(90) -- past the per-sender answer cooldown
    RaidSim.As(raider, function()
        raider.KART.LH.LogHistory(KARTTEST.items[249331].link, "Corvin", "Upgrade", "PALADIN", nil, 48,
            sim.byName.Corvin.guid)
    end)
    RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    T.eq(#lm.env.KART_LootHistory, 1, "an award from after the clear still arrives")
    T.eq(lm.env.KART_LootHistory[1].winner, "Corvin", "and it is that one, not the deleted one")
end

do
    -- The race the request-side line cannot cover: a reply burst spans about eight seconds, so a
    -- clear can land in the middle of one. Those entries are already on their way and must be
    -- refused on arrival.
    local _, lm, _, raider = NewRaid()
    RaidSim.As(raider, function()
        raider.KART.LH.LogHistory(KARTTEST.items[249293].link, "Alric", "BIS", "MAGE", nil, 49, raider.guid)
    end)
    raider.env.KART_LootHistory[1].time = time() - 3 * 24 * 60 * 60

    RaidSim.As(lm, function() lm.KART.LH.RequestHistorySync() end)
    RaidSim.As(lm, function() lm.KART.LH.ClearHistory() end)   -- while the answer is in flight
    KARTTEST.AdvanceTime(15)
    T.eq(#lm.env.KART_LootHistory, 0, "entries already on their way are refused too")
end

-- Revoking an award must reach exactly this roll's entry. Blizzard's roll IDs are small integers
-- reissued every session, while the loot history is a SavedVariable spanning many raid nights -- so
-- matching on the ID alone reached back into previous weeks and deleted somebody's record of an item
-- they really did win, on every client at once.
do
    local sim, lm, _, raider = NewRaid()

    RaidSim.As(lm, function()
        lm.KART.LH.LogHistory(KARTTEST.items[249293].link, "Alric", "BIS", "MAGE", nil, 47, raider.guid)
    end)
    -- time(), not os.time(). The harness clock runs from a FIXED epoch so a failure reproduces
    -- tomorrow as well (see tests/wow_stubs.lua) -- mixing the real clock in gives the assertion an
    -- expiry date: once the real world was more than a week past that epoch, "last Tuesday" landed
    -- AFTER the harness's today, the revoke window swallowed it, and three assertions here went red
    -- with nothing having changed. Which is what happened, 2026-08-01.
    lm.env.KART_LootHistory[1].time = time() - 7 * 24 * 60 * 60   -- last Tuesday
    T.eq(#lm.env.KART_LootHistory, 1, "an award from a previous raid is on record")

    -- Tonight, Blizzard hands out roll 47 again for something else, and the council decides nobody
    -- gets it.
    Drop(sim, 47, 249331)
    RaidSim.As(lm, function() lm.KART.LH.RemoveHistoryForRoll(47) end)
    T.eq(#lm.env.KART_LootHistory, 1, "revoking tonight's roll leaves last week's award alone")

    -- And it still does the job it exists for.
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(47, raider.guid, "BIS") end)
    T.eq(#lm.env.KART_LootHistory, 2, "tonight's award is logged")
    RaidSim.As(lm, function() lm.KART.LH.RemoveHistoryForRoll(47) end)
    T.eq(#lm.env.KART_LootHistory, 1, "and revoking it removes exactly that entry")
    T.eq(lm.env.KART_LootHistory[1].winner, "Alric", "the surviving entry is last week's")
end

do
    local sim, lm = NewRaid()
    Drop(sim, 62, 249331)
    Drop(sim, 63, 249293)

    -- End Round is the one bulk clear, and it has to reach everybody -- this is GitHub #15, where
    -- previous bosses' items stayed on the council panel.
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)

    for _, c in ipairs(sim.clients) do
        T.eq(#c.KART.LC.councilTabs, 0, c.name .. " has no council tabs left after End Round")
        T.eq(#c.KART.LC.voteListRolls, 0, c.name .. " has no vote rows left either")
        T.truthy(not c.KART.LC.rollItems[62], c.name .. " forgot the first item")
        T.truthy(not c.KART.LC.rollItems[63], c.name .. " forgot the second item")
    end
    -- The session itself keeps running: End Round ends a distribution, not the evening.
    for _, c in ipairs(sim.clients) do
        T.eq(c.KART.LC.sessionActive, true, c.name .. " is still in the session")
    end
end

do
    local sim, _, council, raider = NewRaid()

    -- An officer note is council-only information about a player, and it has to reach the other
    -- council members without reaching the player it is about.
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(raider.guid, "hat letzte Woche BIS bekommen")
    end)

    for _, c in ipairs(CouncilOf(sim)) do
        T.eq(c.env.KART_LCOfficerNotes[raider.guid], "hat letzte Woche BIS bekommen",
            c.name .. " sees the officer note")
    end
end

-- ===================================================================================
-- Handing the item over
-- ===================================================================================
do
    local sim, lm, _, raider = NewRaid()
    Drop(sim, 64, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(64, 1) end)
    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(64, raider.guid, "BIS") end)

    T.truthy(Owes(lm.KART.LC.pendingTrades, 64), "the lootmaster owes the item")
    T.truthy(Owes(raider.KART.LC.owedToMe, 64), "and the winner knows they are owed it")

    -- The trade happens: the obligation goes with the item.
    RaidSim.As(lm, function() lm.KART.LC.Trade.RemovePendingTrade(64) end)
    T.truthy(not Owes(lm.KART.LC.pendingTrades, 64),
        "the reminder clears once the item has been handed over")
end

-- ===================================================================================
-- NSRT nicknames
-- ===================================================================================
-- The guild runs Northern Sky, so the lootmaster field and the council list are often filled in
-- with nicknames rather than character names. Before 3.1.0 a client that could not read a nickname
-- rejected EVERY raid config, silently and permanently -- which is how a whole raid ended up on its
-- own vote buttons and never rolling. This is that path.
do
    KARTTEST.SetNSAPI(true)
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    members[1].nickname = "Bram"    -- the lootmaster is known by a nickname
    members[2].nickname = "Merri"

    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, council, raider = sim.byName.Bramor, sim.byName.Merrit, sim.byName.Alric

    RaidSim.As(lm, function()
        -- Typed the way the raid leader actually types it: nicknames, not character names.
        lm.env.KART_Settings.lcLootmaster     = "Bram"
        lm.env.KART_Settings.lcCouncilMembers = "Bram;Merri"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "a lootmaster who typed their own NICKNAME still owns the config")
    for _, c in ipairs({ council, raider }) do
        T.eq(c.KART.LC.raidConfig.lootmaster, lm.guid,
            c.name .. " resolved the nickname to the right player")
        T.eq(c.KART.LC.sessionActive, true, c.name .. " got the session")
    end
    T.truthy(RaidSim.As(council, council.KART.LC.IsCouncil),
        "a council member listed by nickname is council")

    Drop(sim, 70, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(70, 1) end)
    T.truthy((lm.KART.LC.votes[70] or {})[raider.guid],
        "and the whole loot flow still works with nicknames in play")

    KARTTEST.SetNSAPI(false)
end

-- ONE client in the raid cannot read nicknames -- Northern Sky missing, or its global sharing
-- switched off. That client must still end up with the raid's config. Before 3.1.0 it rejected
-- every config forever and silently fell back to its own vote buttons and its own roll setting,
-- which is how a full raid stopped rolling without anyone being able to see why.
do
    KARTTEST.SetNSAPI(true)
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    members[1].nickname = "Bram"
    members[4].nsrt = false          -- Alric, blind to nicknames

    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, raider = sim.byName.Bramor, sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster   = "Bram"
        lm.env.KART_Settings.lcRollsEnabled = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.eq(raider.KART.LC.sessionActive, true,
        "a client that cannot read nicknames still joins the session")
    T.eq(raider.KART.LC.raidConfig.lootmaster, lm.guid,
        "and accepts the config on the sender's identity rather than the name it cannot resolve")
    T.eq(RaidSim.As(raider, raider.KART.LC.GetRollsEnabled), true,
        "and uses the RAID's roll setting, not its own -- this is what broke before 3.1.0")

    Drop(sim, 71, 249331)
    RaidSim.As(raider, function() raider.KART.LC.Vote.CastVote(71, 1) end)
    T.truthy((lm.KART.LC.votes[71] or {})[raider.guid],
        "and votes normally for the rest of the evening")
    KARTTEST.SetNSAPI(false)
end

-- The other half of the same problem, and the one that actually bit last night: a nickname NOBODY
-- can resolve is typed into the Lootmaster field. Under the old ownership rule that was fatal --
-- ownership was derived from "does my own field name me?", the name did not resolve, so nobody owned
-- the config, nothing was broadcast, and every raider silently kept their own roll setting (off).
--
-- Under the rule in docs/OWNERSHIP.md it costs nothing. Ownership is raid lead, which needs no name
-- resolution at all, so the raid gets its settings regardless. Only the DESIGNATION stays pending,
-- and that is a much smaller thing: the raid leader hands out the loot until it resolves.
do
    KARTTEST.SetNSAPI(false)     -- nobody can resolve nicknames
    local members = {}
    for i, m in ipairs(MEMBERS) do
        members[i] = {}
        for k, v in pairs(m) do members[i][k] = v end
    end
    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local lm, raider = sim.byName.Bramor, sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster   = "Bram"   -- resolves to nobody, not even themselves
        lm.env.KART_Settings.lcRollsEnabled = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)

    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "the raid leader owns the config whether or not any nickname resolves")
    T.eq(#RaidSim.Sent(sim, "LC_CONFIG:"), 1, "so the raid's settings go out as normal")
    T.eq(raider.KART.LC.sessionActive, true, "the session starts")
    T.eq(RaidSim.As(raider, raider.KART.LC.GetRollsEnabled), true,
        "and every raider is on the RAID's roll setting -- the evening this used to cost")

    -- The designation is the only casualty, and it degrades to the documented fallback rather than
    -- to silence: nobody could be placed, so the raid leader hands the loot out themselves.
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsLootOwner),
        "with the leader carrying the loot flow until the name resolves")
    KARTTEST.SetNSAPI(true)
end

-- ===================================================================================
-- Does the raid actually agree? (see F.Disagreements)
-- ===================================================================================
-- The assertions above each pick a client and check it. This one checks the clients against EACH
-- OTHER, at every step of the full flow, which is the only way to catch the case that has cost
-- every raid night so far: nineteen machines that agree and one that does not. It is deliberately
-- the whole sentence in one go -- drop, vote, council pick, assign -- because the disagreements
-- that matter appear between the steps, not inside them.
do
    local sim, lm, council, raider = NewRaid()
    local sinja = sim.byName.Sinja
    F.AssertAgreed(sim, nil, "about the session and the config before anything drops")

    Drop(sim, 81, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    F.AssertAgreed(sim, 81, "about the item that just dropped")

    RaidSim.As(raider,  function() raider.KART.LC.Vote.CastVote(81, 1) end)
    RaidSim.As(sinja,    function() sinja.KART.LC.Vote.CastVote(81, 2) end)
    RaidSim.As(council, function() council.KART.LC.Vote.CastVote(81, 3) end)
    F.AssertAgreed(sim, 81, "about who voted what")

    -- Two council members disagreeing about the winner is the normal case, and both picks have to
    -- be on every client's tally -- including on the client of whoever picked first.
    RaidSim.As(council, function() council.KART.LC.Vote.ToggleCouncilVote(81, raider.guid) end)
    RaidSim.As(lm,      function() lm.KART.LC.Vote.ToggleCouncilVote(81, sinja.guid) end)
    F.AssertAgreed(sim, 81, "about the council's own picks")

    RaidSim.As(lm, function() lm.KART.LC.Trade.AssignWinner(81, raider.guid, "BIS") end)
    KARTTEST.AdvanceTime(0)
    F.AssertAgreed(sim, 81, "about who won it")

    -- And a second item, decided by the OTHER council member, on top of a raid that already has
    -- history: an assignment coming from someone other than the lootmaster is the path where the
    -- sender's own local step and everybody else's handler drift apart unnoticed.
    Drop(sim, 82, F.WEAPON)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(sinja, function() sinja.KART.LC.Vote.CastVote(82, 1) end)
    RaidSim.As(council, function() council.KART.LC.Trade.AssignWinner(82, sinja.guid, "Upgrade") end)
    KARTTEST.AdvanceTime(0)
    F.AssertAgreed(sim, 82, "about an item a council member decided")
    F.AssertAgreed(sim, 81, "about the first item, still, after a second one was decided")
end

-- Four items nobody wants: "No Winner" on each clears the card for the WHOLE council ---------------
-- The maintainer's question, and it is the difference between "the round is finished" and "I am
-- still looking at cards from the last boss". End Round wipes everything everywhere in one go; No
-- Winner is per item -- so what has to hold is that four No Winners leave every council member with
-- an empty panel, not just the person who pressed them.
--
-- Asserted through the real button's own sequence, not through a helper: AnnounceResult sends the
-- LC_RESULT, and the three lines after it are the local half the sender has to run itself because
-- KASC drops its own message on the way back.
do
    local sim, lm, council = F.NewRaid()
    local corvin = sim.byName.Corvin
    local ids = { 120, 121, 122, 123 }
    for _, id in ipairs(ids) do F.Drop(sim, id, F.GLOVES) end
    KARTTEST.AdvanceTime(1)

    T.eq(#lm.KART.LC.councilTabs, 4, "the lootmaster has four cards")
    T.eq(#council.KART.LC.councilTabs, 4, "and so does every other council member")
    T.eq(#corvin.KART.LC.councilTabs, 4, "all three of them")

    for _, id in ipairs(ids) do
        RaidSim.As(lm, function()
            lm.KART.LC.Trade.AnnounceResult(id, "NONE")
            lm.KART.LH.RemoveHistoryForRoll(id, lm.KART.LC.rollItems[id])
            lm.KART.LC.Trade.ClearWinnerObligations(id)
            lm.KART.LC.Council.CloseCouncilTab(id)
        end)
    end
    KARTTEST.AdvanceTime(0)

    T.eq(#lm.KART.LC.councilTabs, 0, "the lootmaster's panel is empty")
    T.eq(#council.KART.LC.councilTabs, 0, "and the other council members' panels are too")
    T.eq(#corvin.KART.LC.councilTabs, 0, "every one of them")
    T.eq(#sim.byName.Alric.KART.LC.voteListRolls, 0, "and no raider is left with a vote window open")
end
