-- The same raid, in orders nobody thought of.
--
-- Every other test runs a sequence I chose, which means it can only find bugs I already suspected.
-- A raid does not cooperate: two people vote at the same moment, someone reloads while a council
-- member is assigning, a third person joins between the drop and the vote. The base flow has to
-- survive all of that, not just the order it was written in.
--
-- So this builds random scripts out of the same verbs, runs them, and afterwards asks the one
-- question that matters: does the raid still agree with itself? (F.Disagreements). Each run is
-- seeded, and the seed is printed on failure -- a break here is reproducible, not a mystery.
--
-- Deliberately NOT random: what counts as correct. The invariants below are fixed.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop = F.NewRaid, F.Drop

local ITEMS = { F.GLOVES, F.WEAPON, F.TOKEN }
local NEWCOMER = { name = "Torvi", realm = "TarrenMill", guid = "Player-1-T",
                   class = "MAGE", locale = "enUS" }

-- How many scripts to run, and how long each one is. The default keeps the suite something you run
-- on every change (a few seconds); KART_SOAK_SEEDS=2000 turns it into the deeper hunt worth doing
-- before a raid night. Seeds are stable, so a bigger number only ADDS runs -- it never renumbers
-- the ones already known good, and a seed that broke stays that seed.
local SEEDS = tonumber(os.getenv("KART_SOAK_SEEDS") or "") or 150
local EVENTS_PER_RUN = 18

local function pick(list) return list[math.random(#list)] end

-- One random script. Returns a list of complaints; empty means this raid came out of it agreeing.
local function runOne(seed)
    math.randomseed(seed)
    local sim = NewRaid()
    -- Resolved fresh on every use, never captured: RaidSim.Reload REPLACES a client object, so a
    -- list held across one would drive a client that no longer exists -- and the test, not the
    -- addon, would be the thing that is out of sync.
    local COUNCIL = { "Bramor", "Merrit", "Corvin" }
    local function councilMember() return sim.byName[COUNCIL[math.random(#COUNCIL)]] end
    local nextRoll = 200
    -- [rollID] = the clients that were in the raid when it dropped. Anyone who joins later, or
    -- reloads afterwards, is deliberately left out of a distribution already running -- so they
    -- are not entitled to know about it and must not be compared on it.
    local present, rolls, expiresAt = {}, {}, {}
    local joined = false
    local bad = {}

    -- Per-roll state is shared only while the roll is LIVE. Once the vote window closes, a plain
    -- raider drops the item (they have answered; it is off their screen) while the council keeps it
    -- (they still have to decide it) -- measured, and by design. So a roll is compared at the
    -- moment it is acted on, and never again.
    local VOTE_WINDOW = 20
    local function live(id) return KARTTEST.now < (expiresAt[id] or 0) end
    local function openRoll()
        local open = {}
        for _, id in ipairs(rolls) do if live(id) then open[#open + 1] = id end end
        return #open > 0 and pick(open) or nil
    end
    local function check(id, what)
        for _, line in ipairs(F.Disagreements(sim, id, present[id], true)) do
            bad[#bad + 1] = string.format("roll %d after %s: %s", id, what, line)
        end
    end

    local actions = {
        -- An item drops.
        function()
            local id = nextRoll
            nextRoll = nextRoll + 1
            Drop(sim, id, pick(ITEMS))
            rolls[#rolls + 1] = id
            expiresAt[id] = KARTTEST.now + VOTE_WINDOW
            present[id] = {}
            for i, c in ipairs(sim.clients) do present[id][i] = c end
            check(id, "it dropped")
        end,
        -- Somebody answers.
        function()
            local id = openRoll()
            if not id then return end
            local c = pick(sim.clients)
            RaidSim.As(c, function() c.KART.LC.Vote.CastVote(id, math.random(1, 4)) end)
            check(id, "a vote")
        end,
        -- A council member picks a candidate. Non-binding, but every council member's tally has to
        -- show the same picks.
        function()
            local id = openRoll()
            if not id then return end
            local voter, subject = councilMember(), pick(sim.clients)
            RaidSim.As(voter, function()
                voter.KART.LC.Vote.ToggleCouncilVote(id, subject.guid)
            end)
            check(id, "a council pick")
        end,
        -- Someone decides it. Either the lootmaster or another council member -- a council member
        -- deciding is the path where the assigner's own local step and everybody else's handler
        -- have to end up in the same place.
        function()
            local id = openRoll()
            if not id then return end
            local by, winner = councilMember(), pick(sim.clients)
            RaidSim.As(by, function() by.KART.LC.Trade.AssignWinner(id, winner.guid, "BIS") end)
            check(id, "an award")
        end,
        -- Someone reloads. They lose every scrap of session state and have to get it back on their
        -- own; the rolls that were running without them stay theirs to not know about.
        function()
            local victim = pick(sim.clients)
            RaidSim.Reload(sim, victim.name)
            RaidSim.EnterWorld(sim, victim.name)   -- always follows, in the game
            for _, id in ipairs(rolls) do
                for i = #present[id], 1, -1 do
                    if present[id][i].name == victim.name then table.remove(present[id], i) end
                end
            end
        end,
        -- Someone turns up.
        function()
            if joined then return end
            joined = true
            RaidSim.Join(sim, NEWCOMER)
            RaidSim.RosterUpdate(sim)   -- joining a raid is a roster change, on every client
        end,
        -- The raid lead changes hands. Every ownership check in the addon has a raid-leader
        -- fallback, so this moves authority around underneath everything above.
        function()
            RaidSim.Promote(sim, pick(sim.clients).name)
        end,
        -- Time passes, and the roster settles.
        function()
            RaidSim.RosterUpdate(sim)
            KARTTEST.AdvanceTime(math.random(1, 10))
        end,
    }

    for _ = 1, EVENTS_PER_RUN do pick(actions)() end

    -- Settle: a raid that is mid-recovery is allowed to disagree, a settled one is not. Two roster
    -- updates because the first one is what several recovery paths react TO.
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(60)
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(60)

    -- The session, the config and the council list are the raid's, not anyone's own: they must
    -- agree across every client, including whoever just joined or reloaded.
    for _, line in ipairs(F.Disagreements(sim, nil)) do bad[#bad + 1] = line end

    -- The loot history is the record of the evening, it is synced to whoever turns up, and unlike
    -- the live roll state it is never pruned -- so by now every client must hold the same awards.
    local function awards(client)
        local parts = {}
        for _, e in ipairs(client.env.KART_LootHistory or {}) do
            parts[#parts + 1] = tostring(e.rollID) .. "=" .. tostring(e.winner)
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    local baseAwards = awards(sim.clients[1])
    for i = 2, #sim.clients do
        if awards(sim.clients[i]) ~= baseAwards then
            bad[#bad + 1] = string.format("history: %s has %s, %s has %s",
                sim.clients[1].name, baseAwards, sim.clients[i].name, awards(sim.clients[i]))
        end
    end

    -- And the lootmaster is still someone. A raid that agrees that nobody hands out loot agrees
    -- about the wrong thing -- this is the failure the whole evening looks like from the inside.
    if not RaidSim.As(sim.clients[1], sim.clients[1].KART.LC.GetLootmaster) then
        bad[#bad + 1] = "nobody is the lootmaster any more"
    end
    return bad
end

local broken, firstSeed, firstWhy = 0, nil, nil
for seed = 1, SEEDS do
    local ok, res = pcall(runOne, seed)
    if not ok then
        broken = broken + 1
        firstSeed = firstSeed or seed
        firstWhy = firstWhy or ("error: " .. tostring(res))
    elseif #res > 0 then
        broken = broken + 1
        firstSeed = firstSeed or seed
        firstWhy = firstWhy or res[1]
    end
end

T.eq(broken, 0, string.format(
    "%d random raids all end up agreeing (first break: seed %s -- %s)",
    SEEDS, tostring(firstSeed), tostring(firstWhy)))
