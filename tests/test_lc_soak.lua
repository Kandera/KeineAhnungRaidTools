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
local NEWCOMER = { name = "Torvi", realm = "TarrenMill", guid = "Player-1096-0A1B2C42",
                   class = "MAGE", locale = "enUS" }

-- How many scripts to run, and how long each one is. The default keeps the suite something you run
-- on every change (a few seconds); KART_SOAK_SEEDS=2000 turns it into the deeper hunt worth doing
-- before a raid night. Seeds are stable, so a bigger number only ADDS runs -- it never renumbers
-- the ones already known good, and a seed that broke stays that seed.
local SEEDS = tonumber(os.getenv("KART_SOAK_SEEDS") or "") or 150
local EVENTS_PER_RUN = 18

-- The script generator draws from its OWN stream, not from math.random.
--
-- It used to share math.random with the addon, and that quietly broke the one property this whole
-- file rests on: "a seed reproduces exactly". The addon draws from the same stream for its jitter
-- (LC.HandleStateRequest, RequestSessionState), so ANY change to how often the addon rolls a number
-- shifts every later draw -- and the same seed then walks a completely different script. Measured:
-- adding one timer to the join path changed seed 631 from
--   leave>leave>endround>award>join>drop>...
-- to
--   leave>promote>vote>vote>settle>throttle>endround>...
-- which makes a before/after comparison meaningless exactly when one is needed, and turns
-- KART_SOAK_DEBUG=<seed> into a debugger that shows a different bug than the one that failed.
--
-- A plain 32-bit LCG (Numerical Recipes constants). Not good randomness, and it does not need to be:
-- what it needs is to be OURS, so the script for seed N is the same script whatever the addon does.
local rngState = 0
local function rnd(n)
    rngState = (1664525 * rngState + 1013904223) % 4294967296
    return (math.floor(rngState / 65536) % n) + 1
end

local function pick(list) return list[rnd(#list)] end

-- One random script. Returns a list of complaints; empty means this raid came out of it agreeing.
local function runOne(seed)
    rngState = seed
    -- Still seeded, because the addon uses math.random itself and an unseeded run would differ
    -- between invocations for reasons that have nothing to do with the script.
    math.randomseed(seed)
    local sim = NewRaid()
    -- Resolved fresh on every use, never captured: RaidSim.Reload REPLACES a client object, so a
    -- list held across one would drive a client that no longer exists -- and the test, not the
    -- addon, would be the thing that is out of sync.
    local COUNCIL = { "Bramor", "Merrit", "Corvin" }
    local function councilMember() return sim.byName[COUNCIL[rnd(#COUNCIL)]] end
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
    -- Rolls that started while messages were being dropped. LC_START is announced once and never
    -- re-requested, so a client that was deaf at that instant has no way back to that item -- a
    -- protocol limitation (docs/BACKLOG.md B66), not something a random walk should re-report four
    -- times a run. The END state is still held to the full standard below: everything that carries
    -- a retry must have arrived by then, outage or no outage.
    local unreliable = {}
    -- Awards made while messages were being dropped. LC_RESULT is announced once; a client that
    -- could not authorize the sender at that instant (its council list had not arrived) never gets
    -- that award, and the history catch-up only runs on JOIN, never again -- docs/BACKLOG.md B66.
    local unreliableAward = {}
    -- [name] = when this client can be held to the raid's view again. A reload is not instant: the
    -- client comes back, asks for the state, and waits for an answer. An item announced inside that
    -- window is announced to somebody who is not listening yet, and LC_START is never re-sent -- so
    -- they are left out of THAT item's comparison and held to everything else (B66).
    local recovering = {}
    local function check(id, what)
        if unreliable[id] then return end
        for _, line in ipairs(F.Disagreements(sim, id, present[id], true)) do
            bad[#bad + 1] = string.format("roll %d after %s: %s", id, what, line)
        end
    end

    -- The raid leader saying yes to "the lootmaster is gone, take over?". Nobody is left holding
    -- the loot flow while a prompt sits unanswered, which is a state a real raid resolves in
    -- seconds and a test would otherwise carry to the end and call a bug.
    -- Every question the addon puts on screen, answered the way the raid answers it: yes to
    -- standing in for a departed lootmaster, and yes to "your session is not running, start it?".
    -- A prompt nobody ever clicks is not a state a raid stays in, and leaving them unanswered made
    -- the harness report a lootmaster sitting in front of an open dialog as a lost session.
    local function answerPrompts()
        for _, c in ipairs(sim.clients) do
            RaidSim.As(c, KARTTEST.AcceptPopup, "KART_LC_STAND_IN")
            RaidSim.As(c, function()
                local f = c.KART.LC.sessionPromptFrame
                if f and f:IsShown() then          -- the prompt's own "Yes"
                    c.KART.LC.sessionPromptAnswered = true
                    c.KART.LC.SetSessionActive(true)
                    f:Hide()
                end
            end)
        end
    end

    -- Tokens whose loss the addon is supposed to survive on its own, because each has a retry
    -- behind it. Deliberately excludes LC_VOTE and LC_RESULT: nothing acknowledges those, so
    -- dropping one is a permanent hole by design, not a defect to hunt.
    local RECOVERABLE = { "LC_CONFIG", "LC_ACTIVE", "LC_STATE_REQ" }
    -- [token] = the simulated time it starts arriving again. A chat throttle is a burst that lasts
    -- SECONDS, not a switch someone leaves off: modelled as an outage the addon's own retries
    -- (LC_CONFIG's twelve attempts, the state request's 5/15/45 backoff) get a fair chance against.
    -- An unbounded one defeats any finite retry policy, so it would only ever prove that.
    local THROTTLE_SECONDS = 12
    local blackholed = {}
    -- How long an outage keeps hurting after it ends. A dropped request is only re-sent on the
    -- backoff (see STATE_REQ_BACKOFF), so a client can still be waiting for its answer well after
    -- messages started flowing again -- and an item announced in THAT window is announced to a
    -- client that has no way to ask for it later.
    local RECOVERY_HORIZON = 15
    local outageUntil = 0
    local function deliverExpired(force)
        for token, until_ in pairs(blackholed) do
            if force or KARTTEST.now >= until_ then
                RaidSim.Deliver(sim, token)
                blackholed[token] = nil
                outageUntil = math.max(outageUntil, KARTTEST.now + RECOVERY_HORIZON)
            end
        end
    end

    local actions = {
        { "drop", function()
            local id = nextRoll
            nextRoll = nextRoll + 1
            Drop(sim, id, pick(ITEMS))
            rolls[#rolls + 1] = id
            expiresAt[id] = KARTTEST.now + VOTE_WINDOW
            if next(blackholed) ~= nil or KARTTEST.now < outageUntil then unreliable[id] = true end
            present[id] = {}
            for _, c in ipairs(sim.clients) do
                if KARTTEST.now >= (recovering[c.name] or 0) then
                    present[id][#present[id] + 1] = c
                end
            end
            check(id, "it dropped")
        end },
        { "vote", function()
            local id = openRoll()
            if not id then return end
            local c = pick(sim.clients)
            RaidSim.As(c, function() c.KART.LC.Vote.CastVote(id, rnd(4)) end)
            check(id, "a vote")
        end },
        -- A council member picks a candidate. Non-binding, but every council member's tally has to
        -- show the same picks.
        { "cvote", function()
            local id = openRoll()
            if not id then return end
            -- A council member may have left the raid by now; the list is by name on purpose.
            local voter, subject = councilMember(), pick(sim.clients)
            if not voter then return end
            RaidSim.As(voter, function()
                voter.KART.LC.Vote.ToggleCouncilVote(id, subject.guid)
            end)
            check(id, "a council pick")
        end },
        -- Someone decides it. Either the lootmaster or another council member -- a council member
        -- deciding is the path where the assigner's own local step and everybody else's handler
        -- have to end up in the same place.
        { "award", function()
            local id = openRoll()
            if not id then return end
            local by, winner = councilMember(), pick(sim.clients)
            if not by then return end
            if next(blackholed) ~= nil or KARTTEST.now < outageUntil then
                -- Both, and for the same reason: a client that could not authorize the sender at
                -- that instant (its council list had not arrived) rejects the LC_RESULT, so it has
                -- neither the award in its history NOR the winner on the roll, and nothing
                -- re-announces either. B66 -- the roll is behind from here on, permanently.
                unreliableAward[id] = true
                unreliable[id] = true
            end
            RaidSim.As(by, function() by.KART.LC.Trade.AssignWinner(id, winner.guid, "BIS") end)
            check(id, "an award")
        end },
        -- Someone reloads. They lose every scrap of session state and have to get it back on their
        -- own; the rolls that were running without them stay theirs to not know about.
        { "reload", function()
            local victim = pick(sim.clients)
            RaidSim.Reload(sim, victim.name)
            RaidSim.EnterWorld(sim, victim.name)   -- always follows, in the game
            recovering[victim.name] = KARTTEST.now + RECOVERY_HORIZON
            for _, id in ipairs(rolls) do
                for i = #present[id], 1, -1 do
                    if present[id][i].name == victim.name then table.remove(present[id], i) end
                end
            end
        end },
        -- Someone turns up.
        { "join", function()
            if joined then return end
            joined = true
            RaidSim.Join(sim, NEWCOMER)
            RaidSim.RosterUpdate(sim)   -- joining a raid is a roster change, on every client
        end },
        -- The raid lead changes hands. Every ownership check in the addon has a raid-leader
        -- fallback, so this moves authority around underneath everything above.
        { "promote", function()
            RaidSim.Promote(sim, pick(sim.clients).name)
        end },
        -- Someone leaves. If it was the lootmaster, the raid leader is offered the role -- accepted
        -- here, which is what a raid leader does when the prompt appears.
        { "leave", function()
            if #sim.clients <= 3 then return end
            -- Anyone, the configured lootmaster included. That used to be excluded because losing
            -- them left nobody owning the config and every later arrival without one (B65), which
            -- buried every other finding under repeats of one known gap. The stand-in hands the
            -- config on now, so the walk is free to take the lootmaster out.
            local victim = pick(sim.clients)
            RaidSim.Leave(sim, victim.name)
            for _, id in ipairs(rolls) do
                for i = #present[id], 1, -1 do
                    if present[id][i].name == victim.name then table.remove(present[id], i) end
                end
            end
            RaidSim.RosterUpdate(sim)
            KARTTEST.AdvanceTime(5)
            answerPrompts()
        end },
        -- The blip: for a moment, ONE client's group APIs report no group at all while everyone
        -- else reads normally. The maintainer has watched this cost a session mid-boss.
        { "blip", function()
            local c = pick(sim.clients)
            KARTTEST.solo[c.unit] = true
            KARTTEST.AdvanceTime(rnd(2))
            KARTTEST.solo[c.unit] = nil
        end },
        -- Messages go missing. Blizzard's chat throttle drops the overflow silently and the sender
        -- cannot tell, so anything the addon depends on has to be re-askable. Only the tokens that
        -- HAVE a retry are dropped here (the config retry, the state-request backoff) -- a lost
        -- vote or result has no acknowledgement in the protocol and never claimed to.
        { "throttle", function()
            local token = pick(RECOVERABLE)
            RaidSim.Blackhole(sim, token)
            blackholed[token] = KARTTEST.now + THROTTLE_SECONDS
            outageUntil = math.max(outageUntil, KARTTEST.now + THROTTLE_SECONDS + RECOVERY_HORIZON)
        end },
        -- Time passes, and the roster settles. Anything that was being dropped starts arriving
        -- again -- a throttle is a moment, not a state.
        { "settle", function()
            deliverExpired(true)
            RaidSim.RosterUpdate(sim)
            KARTTEST.AdvanceTime(rnd(10))
            answerPrompts()
        end },
        -- The council ends the round. Every tracked roll goes, everywhere.
        { "endround", function()
            local by = councilMember()
            if not by then return end
            RaidSim.As(by, by.KART.LC.EndRound)
            for _, id in ipairs(rolls) do expiresAt[id] = 0 end
        end },
    }

    -- Under KART_SOAK_DEBUG, follow one config field as it CHANGES on each client instead of only
    -- printing where it ended up. Watching the value rather than the functions that write it is
    -- deliberate: it catches every writer without having to know them in advance, which is the whole
    -- problem with B69 -- the value a client ends up holding is one no message on the wire appears
    -- to have carried, so the interesting question is which step put it there.
    local watching = os.getenv("KART_SOAK_DEBUG") == tostring(seed)
    local lastRolls = {}
    local function TraceRolls(when)
        if not watching then return end
        for _, c in ipairs(sim.clients) do
            -- rolls AND the fromSelf marker together: the marker is what decides whether the client
            -- keeps asking for a real config (see LC.StateStillNeeded), so a change to it with no
            -- change to the values is exactly the event worth seeing.
            local v = tostring(c.KART.LC.raidConfig.rollsEnabled)
                .. "/" .. tostring(c.KART.LC.raidConfig.fromSelf)
            -- Keyed by NAME, not by client object: a reload replaces the object, and the point here
            -- is to follow the person across it.
            if lastRolls[c.name] ~= v then
                print(string.format("  trace t=%-5s %-8s rolls/fromSelf %-12s -> %-12s  after %s",
                    tostring(KARTTEST.now), c.name, tostring(lastRolls[c.name]), v, when))
                lastRolls[c.name] = v
            end
        end
    end
    TraceRolls("the raid was built")

    -- The script itself, so a failure names the sequence that produced it instead of only the seed.
    local script = {}
    for _ = 1, EVENTS_PER_RUN do
        -- Seconds pass between things happening in a raid. Without this the whole script ran inside
        -- one instant, so nothing ever timed out, no retry ever came due, and a throttle modelled as
        -- lasting seconds outlived the entire run.
        KARTTEST.AdvanceTime(rnd(5))
        deliverExpired(false)
        answerPrompts()   -- a person clicks the prompt in front of them within seconds
        local a = pick(actions)
        script[#script + 1] = a[1]
        a[2]()
        TraceRolls(string.format("step %d (%s)", #script, a[1]))
    end

    -- Settle: a raid that is mid-recovery is allowed to disagree, a settled one is not. Nothing is
    -- being dropped or blipped any more, and two roster updates because the first one is what
    -- several recovery paths react TO.
    deliverExpired(true)
    KARTTEST.solo = {}
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(60)
    TraceRolls("the first settle")
    answerPrompts()
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(60)
    TraceRolls("the second settle")

    -- The session, the config and the council list are the raid's, not anyone's own: they must
    -- agree across every client, including whoever just joined or reloaded.
    for _, line in ipairs(F.Disagreements(sim, nil)) do bad[#bad + 1] = line end

    -- The loot history is the record of the evening, it is synced to whoever turns up, and unlike
    -- the live roll state it is never pruned -- so by now every client must hold the same awards.
    local function awards(client)
        local parts = {}
        for _, e in ipairs(client.env.KART_LootHistory or {}) do
            if not unreliableAward[e.rollID] then
                parts[#parts + 1] = tostring(e.rollID) .. "=" .. tostring(e.winner)
            end
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

    -- And SOMEBODY still owns the loot flow. A raid that agrees nobody hands out loot agrees about
    -- the wrong thing -- that is the failure the whole evening looks like from the inside.
    --
    -- This asked GetLootmaster and tested it with `not`, which could never fire: the function
    -- answers "" when no lootmaster is configured, and "" is truthy in Lua. It was also asking the
    -- wrong question -- an empty field is the NORMAL state of a raid whose leader stands in (see
    -- LC.IsLootOwner), so a blank name is not a fault by itself. What must hold is that at least one
    -- client in the raid answers "yes, I own this".
    local anyOwner = false
    for _, c in ipairs(sim.clients) do
        if RaidSim.As(c, c.KART.LC.IsLootOwner) then anyOwner = true break end
    end
    if not anyOwner then
        bad[#bad + 1] = "nobody owns the loot flow any more"
    end
    -- KART_SOAK_DEBUG=<seed> dumps everything about one run. A seed reproduces exactly, so this is
    -- the whole debugger: no separate script to keep in step with this one.
    if os.getenv("KART_SOAK_DEBUG") == tostring(seed) then
        print("=== seed " .. seed .. ": " .. table.concat(script, ">"))
        for _, c in ipairs(sim.clients) do
            -- The RAW config field and the EFFECTIVE answer both, because they differ on purpose:
            -- PresentLootmaster blanks a named lootmaster who is no longer in the group (B29), so
            -- reading the raw field alone shows a disagreement that the code has already resolved.
            print(string.format("  %-8s session=%-5s owner=%-5s cfgown=%-5s lead=%-5s startedByUs=%-5s rolls(eff)=%-5s rolls(cfg)=%-5s rolls(own)=%-5s fromSelf=%-5s lm(eff)=%-14s lm(raw)=%s",
                c.name,
                tostring(c.KART.LC.sessionActive),
                tostring(RaidSim.As(c, c.KART.LC.IsLootOwner)),
                tostring(RaidSim.As(c, c.KART.LC.IsConfigOwner)),
                tostring(RaidSim.As(c, function() return UnitIsGroupLeader("player") end)),
                tostring(c.KART.LC.sessionStartedByUs),
                tostring(RaidSim.As(c, c.KART.LC.GetRollsEnabled)),
                tostring(c.KART.LC.raidConfig.rollsEnabled),
                tostring(c.env.KART_Settings.lcRollsEnabled),
                tostring(c.KART.LC.raidConfig.fromSelf),
                tostring(RaidSim.As(c, c.KART.LC.GetLootmaster)),
                tostring(c.KART.LC.raidConfig.lootmaster)))
        end
        for _, token in ipairs({ "LC_CONFIG", "LC_CONFIG_RELAY", "LC_ACTIVE", "LC_STATE_REQ",
                                 "LC_SESSION_RESUME", "LC_RESIGN", "LC_START", "LC_ROLL_CATCHUP" }) do
            for _, e in ipairs(RaidSim.Sent(sim, token)) do
                print(string.format("  wire %-10s %-8s -> %-22s %s", token, e.from,
                    tostring(e.target or e.channel), e.msg:sub(1, 60)))
            end
        end
        for _, l in ipairs(bad) do print("  BAD " .. l:sub(1, 160)) end
    end
    if #bad > 0 then bad[1] = table.concat(script, ">") .. "  ||  " .. bad[1] end
    return bad
end

-- What KIND of disagreement this is, with the run-specific parts taken out: numbers become N and
-- everything after the first colon (the two clients and their values) is dropped. "config.buttons"
-- and "roll N after it dropped" are the two that have actually turned up.
--
-- Reporting only the FIRST break, which is all this did, is enough to know something is wrong and
-- almost useless for deciding what to do about it: one line cannot say whether the thirteen breaks
-- in three thousand runs are thirteen instances of one bug or one instance each of thirteen. The
-- tally is what points the next piece of work at the right thing.
local function Signature(line)
    local body = line:match("||%s*(.*)") or line
    return (body:gsub("%d+", "N"):match("^([^:]+)") or body):sub(1, 60)
end

local broken, firstSeed, firstWhy = 0, nil, nil
local kinds, kindSeed = {}, {}
local function Record(seed, why)
    broken = broken + 1
    firstSeed = firstSeed or seed
    firstWhy = firstWhy or why
    local sig = Signature(why)
    kinds[sig] = (kinds[sig] or 0) + 1
    kindSeed[sig] = kindSeed[sig] or seed
end

for seed = 1, SEEDS do
    local ok, res = pcall(runOne, seed)
    if not ok then
        Record(seed, "error: " .. tostring(res))
    elseif #res > 0 then
        Record(seed, res[1])
    end
end

if broken > 0 then
    local sigs = {}
    for sig in pairs(kinds) do sigs[#sigs + 1] = sig end
    table.sort(sigs, function(a, b)
        if kinds[a] ~= kinds[b] then return kinds[a] > kinds[b] end
        return a < b
    end)
    print(string.format("soak: %d of %d runs disagreed, by kind:", broken, SEEDS))
    for _, sig in ipairs(sigs) do
        print(string.format("  %4d  %-40s (first at seed %d, KART_SOAK_DEBUG=%d)",
            kinds[sig], sig, kindSeed[sig], kindSeed[sig]))
    end
end

T.eq(broken, 0, string.format(
    "%d random raids all end up agreeing (first break: seed %s -- %s)",
    SEEDS, tostring(firstSeed), tostring(firstWhy)))
