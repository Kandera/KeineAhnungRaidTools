-- The Loot Council base flow, across several real clients at once.
--
-- The maintainer's own words for what has to hold, ten times out of ten, and what four raid nights
-- failed to deliver:
--
--     Items droppen, jeder kann das Item sehen, seinen Button drücken und das Council sieht das
--     und kann verteilen.
--
-- Everything here is that sentence, made executable. Each assertion names which half it defends.
-- Item fixtures are real drops from the guild's own loot history, with the classID/subclassID the
-- live client reports -- invented IDs were what let the tier-token bug hide.

local RaidSim = dofile("tests/raidsim.lua")

KARTTEST.AddItem({ id = 249331, name = "Ezzorak's Gloombind", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 4, equipLoc = "INVTYPE_HAND", bind = 1 })
KARTTEST.AddItem({ id = 249293, name = "Weight of Command", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 4, equipLoc = "INVTYPE_2HWEAPON", bind = 1 })
KARTTEST.AddItem({ id = 249364, name = "Voidcured Unraveled Nullcore", quality = 4, ilvl = 285,
                   classID = 15, subclassID = 0, bind = 1 })

local MEMBERS = {
    { name = "Kandera", realm = "Blackmoore", guid = "Player-1-K", class = "DEATHKNIGHT", leader = true },
    { name = "Haerri",  realm = "Blackmoore", guid = "Player-1-H", class = "DRUID" },
    { name = "Odin",    realm = "Blackmoore", guid = "Player-1-O", class = "MAGE" },
}

-- Builds a raid whose lootmaster is Kandera and whose council is Kandera + Haerri, then starts the
-- session the way the settings toggle does. Returns the sim and the three clients.
local function NewRaid()
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    local sim = RaidSim.New(MEMBERS)
    RaidSim.Install(sim)

    local lm, council, raider = sim.byName.Kandera, sim.byName.Haerri, sim.byName.Odin

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster     = "Kandera"
        lm.env.KART_Settings.lcCouncilMembers = "Kandera;Haerri"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)
    return sim, lm, council, raider
end

-- One item drops. Blizzard raises START_LOOT_ROLL on every eligible client independently; the loot
-- owner's handler is what broadcasts LC_START to the rest, so running them in this order is the
-- realistic case and also the awkward one (peers hear about the roll before their own event).
local function Drop(sim, rollID, itemID, opts)
    opts = opts or {}
    KARTTEST.lootRolls[rollID] = { itemID = itemID, canNeed = opts.canNeed, canTransmog = opts.canTransmog }
    for _, c in ipairs(sim.clients) do
        if not (opts.noRollFor and opts.noRollFor[c.name]) then
            RaidSim.As(c, function() c.KART.LC.OnStartLootRoll(rollID) end)
        end
    end
    KARTTEST.AdvanceTime(0)
end

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

    -- The count travels with the vote so a client with a different button list says "unknown"
    -- instead of confidently showing the wrong label. That guard is why a whole evening's votes
    -- were once read wrong.
    T.eq(votes[raider.guid] and votes[raider.guid].count,
        #RaidSim.As(lm, lm.KART.LC.GetButtonConfig),
        "the vote carries the sender's button count")
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
    for _, c in ipairs(sim.clients) do
        for _, id in ipairs(c.KART.LC.voteListRolls) do
            T.truthy(id ~= 43, c.name .. " no longer has the decided item in their vote window")
        end
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
    Drop(sim, 44, 249293, { noRollFor = { Odin = true } })

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
    Drop(sim, 45, 249293, { noRollFor = { Odin = true } })

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
end
