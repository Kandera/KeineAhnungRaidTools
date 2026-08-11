-- Does the loot distribution still work when the wire is actually rate-limited?
--
--   luajit tests/measure_loot_under_throttle.lua
--
-- DELIBERATELY NOT IN tests/run.lua. It is a measurement, not an assertion: it prints numbers and
-- fails nothing, and it is slow. Run it when the distribution changes shape -- a new message, a bigger
-- payload, another repeat -- and compare the numbers against the ones in the header below.
--
-- WHY IT EXISTS. Every other test in this repository runs with ChatThrottleLib's limiter switched OFF:
-- tests/raidsim.lua sets HardThrottlingBeginTime = -math.huge and avail = BURST on every client at
-- boot. That is the right call for a suite -- with the real limiter, every one of the hundreds of
-- cases in run.lua would sit waiting on it -- but it means the one question the raid actually cares
-- about has never been asked offline: with 25 people answering at once and the pipe metered, does
-- every vote still reach the council INSIDE the twenty-second window?
--
-- CTL's own numbers, read out of Libs/AceComm-3.0/ChatThrottleLib.lua rather than assumed:
-- MAX_CPS = 800 bytes per second, BURST = 4000, and a hard 10% clamp for five seconds after login or
-- a zone change. The clamp is deliberately NOT modelled here: a boss dies mid-raid, not at load, and
-- the steady rate is the honest case. If you want the worst case, set HardThrottlingBeginTime to
-- GetTime() below and the first five seconds run at a tenth of the rate.
--
-- MEASURED 2026-08-10, on the tree that shipped 29 review commits:
--
--   wide open  25 clients | announced 1.0s | all votes in 11.0s | settled 41.0s | tally gap 0/25
--   THROTTLED  25 clients | announced 1.0s | all votes in 15.5s | settled 45.5s | tally gap 0/25
--   THROTTLED  30 clients | announced 1.0s | all votes in 16.8s | settled 46.8s | tally gap 0/30
--
-- Nothing is lost: every raider's answer reaches the council, no client ends up short an award, and
-- no send is given up on.
--
-- READ THE "all votes in" COLUMN AS A DRAIN TIME, NOT AS A MARGIN. It was first read as one, and that
-- was wrong: this file drains the whole queue before anybody votes, so the clock has already been run
-- forward by the mass-join storm the fixture creates when it puts twenty-five clients in a raid in the
-- same instant. Walk the clock instead and the loot owner's tally is complete three seconds after the
-- drop, in every scenario tried, storm or no storm -- votes travel INBOUND from twenty-five clients
-- that each have their own ChatThrottleLib budget, so they cannot congest one another. The
-- distribution is not tight on time. See B173 for what the traffic measurement did find, and for the
-- one pipe that IS single: the loot owner's outbox.
--
-- AND THIS IS THE OPTIMISTIC READING. Here every simulated client owns its own ChatThrottleLib. In
-- the game there is one per client, shared by every addon installed -- DBM, WeakAuras, Details and
-- KART all draw on the same 800 bytes a second. The real slack is smaller than what this prints, and
-- nothing offline can say by how much.

-- Its own bootstrap, because it is not loaded by tests/run.lua and has to stand on its own. Same
-- order run.lua uses; the two must not drift, so if a library is added there it belongs here too.
dofile("tests/wow_stubs.lua")
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile("Libs/AceComm-3.0/ChatThrottleLib.lua")
dofile("Libs/AceComm-3.0/AceComm-3.0.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/KAUtil-1.0/KAUtil-1.0.lua")
dofile("Libs/KAGS-1.0/KAGS-1.0.lua")
dofile("Libs/KASC-1.0/KASC-1.0.lua")
dofile("Libs/KAUI-1.0/KAUI-1.0.lua")

-- The fixture asserts through T while it builds a raid, so it has to exist. Counted rather than
-- ignored: a fixture assertion failing here would otherwise be invisible and every number below it
-- would be measured against a raid that is not the one the header describes.
local fixtureFailures = 0
_G.T = {
    eq = function(a, e, label)
        if a ~= e then
            fixtureFailures = fixtureFailures + 1
            print("FIXTURE FAIL  " .. tostring(label))
        end
    end,
}
T.truthy  = function(v, label) T.eq(not not v, true, label) end
T.is_nil  = function(v, label) T.eq(v == nil, true, label) end
T.deep_eq = function() end

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local ITEMS = { F.GLOVES, F.WEAPON, F.PLATE_CHEST, F.TOKEN, F.TIER_TOKEN, F.RECIPE }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE",
                  "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER" }

local function Build(size, throttled)
    local sim, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    local i = 0
    while #sim.clients < size do
        i = i + 1
        RaidSim.Join(sim, { name = "Extra" .. i, realm = "TarrenMill",
            guid = string.format("Player-1096-0B%06X", i),
            class = CLASSES[(i % #CLASSES) + 1], locale = "enUS" })
    end
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(2)
    RaidSim.Drain(sim, 200)

    if throttled then
        -- The limiter, put back per client after raidsim.lua disabled it. Sixty seconds in the past so
        -- the five-second login clamp is over and this measures the steady rate.
        for _, c in ipairs(sim.clients) do
            c.CTL.HardThrottlingBeginTime = GetTime() - 60
            c.CTL.avail = 0
            c.CTL.LastAvailUpdate = GetTime()
        end
    end
    return sim, lm
end

local function Awards(c)
    local seen, n = {}, 0
    for _, e in ipairs(c.env.KART_LootHistory or {}) do
        if e.id then seen[e.id] = true n = n + 1 end
    end
    return seen, n
end

local function Run(size, throttled)
    local sim, lm = Build(size, throttled)
    RaidSim.ClearLog(sim)
    local t0 = GetTime()

    -- An ordinary boss: six items in one batch.
    local ids = {}
    for k = 1, 6 do
        ids[k] = 10000 + k
        F.Drop(sim, ids[k], ITEMS[(k % #ITEMS) + 1])
    end
    KARTTEST.AdvanceTime(1)
    RaidSim.Drain(sim, 300)
    local announced = GetTime() - t0

    -- Everybody answers every item in the same instant, each with a note -- the heaviest a vote gets.
    for _, c in ipairs(sim.clients) do
        for _, id in ipairs(ids) do
            RaidSim.As(c, function()
                local box = { GetText = function() return "brauche das fuer den zweiten Spec" end }
                c.KART.LC.Vote.CastVote(id, (id % 3) + 1, box)
            end)
        end
    end
    RaidSim.Drain(sim, 400)
    KARTTEST.AdvanceTime(10)
    RaidSim.Drain(sim, 400)
    local voted = GetTime() - t0

    -- The number the council is actually reading when the timer runs out.
    local worstGap = 0
    for _, id in ipairs(ids) do
        local got = 0
        for _, c in ipairs(sim.clients) do
            if (lm.KART.LC.votes[id] or {})[c.guid] then got = got + 1 end
        end
        if (#sim.clients - got) > worstGap then worstGap = #sim.clients - got end
    end

    for _, id in ipairs(ids) do
        RaidSim.As(lm, function()
            lm.KART.LC.Trade.AssignWinner(id, sim.clients[(id % #sim.clients) + 1].guid, "BIS", nil)
        end)
    end
    RaidSim.Drain(sim, 400)
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    RaidSim.Drain(sim, 400)
    KARTTEST.AdvanceTime(30)
    RaidSim.Drain(sim, 400)
    local settled = GetTime() - t0

    local ref = Awards(lm)
    local short, worstShort = 0, 0
    for _, c in ipairs(sim.clients) do
        local mine = Awards(c)
        local miss = 0
        for id in pairs(ref) do if not mine[id] then miss = miss + 1 end end
        if miss > 0 then short = short + 1 end
        if miss > worstShort then worstShort = miss end
    end
    local gaveUp, retried = 0, 0
    for _, c in ipairs(sim.clients) do
        local kd = RaidSim.As(c, function() return c.KASC:Diagnostics() end)
        gaveUp = gaveUp + (kd.sendGaveUp or 0)
        retried = retried + (kd.sendRetried or 0)
    end

    print(string.format(
        "%s %2d clients | announced %4.1fs | all votes in %5.1fs | settled %5.1fs | " ..
        "worst tally gap %d/%d | clients short %d (worst -%d) | retried %d gaveUp %d | %d chunks",
        throttled and "THROTTLED" or "wide open", size, announced, voted, settled,
        worstGap, #sim.clients, short, worstShort, retried, gaveUp, #(sim.log or {})))
end

print("Loot distribution with ChatThrottleLib's real limiter. See this file's header for what the")
print("numbers mean and why the slack it prints is the optimistic reading.")
Run(25, false)
Run(25, true)
Run(30, true)
if fixtureFailures > 0 then
    print(string.format("\n%d fixture assertion(s) failed while building the raid -- the numbers above " ..
        "were measured against something other than what this file describes.", fixtureFailures))
end
