-- The five things this module is judged on, asked of every client at raid size.
--
--   luajit tests/check_the_five_at_raid_size.lua
--
-- DELIBERATELY NOT IN tests/run.lua, and for the same reason as measure_loot_under_throttle.lua: it
-- is slow, and the suite's fixture is five clients on purpose. Run it before a raid, and after any
-- change to the drop, vote, award or session paths.
--
-- The five, stated by the maintainer 2026-08-11 and not softened here:
--
--   1. everybody auto-passes                  4. the council reads the votes correctly
--   2. everybody sees every item              5. the items get handed out
--   3. everybody can press their buttons
--
-- "Wenn nur eine dieser Sachen fuer eine Sekunde nicht geht, dann schreit mein Raid: bad addon,
-- zurueck zu RC Loot Council." So there is no acceptable column below. A line is clean or it is a
-- failure.
--
-- WHY A THIRD OF THE RAID IS BLIND TO EACH ITEM. The first version of this let every client roll on
-- everything, and it proved less than it looked: a client that gets its own START_LOOT_ROLL learns
-- the item from Blizzard, so the wire was never the only source and question 2 could not fail. Each
-- item now skips a third of the raid -- the plate wearer on a cloth drop -- and for those clients the
-- announcement is the only way the item can arrive.
--
-- VERIFIED NOT TO BE BLIND, 2026-08-11, three controls, each restored afterwards:
--
--   remove CouncilRunsHere() from the Auto-Pass gate  -> 345 failures, all of them question 1
--   blackhole LC_RESULT + LC_HIST_BATCH from boss 3   ->  24 failures, every client short 9 awards
--   blackhole LC_DROP + LC_ROLL_CATCHUP + LC_TABLE    ->  78 failures, sight and tally both
--
-- A fourth control is worth knowing about because it came back CLEAN: blackholing LC_DROP and
-- LC_RESULT alone, from boss 3 to the end, changes nothing -- the heartbeat repairs the items and
-- End Round repairs the awards (B171). That is the machinery working, not the check sleeping; the
-- third control above is the same cut with the repair channels closed too, and it fails loudly.
--
-- MEASURED 2026-08-11, on the tree carrying B173/B174/B175:
--
--   25 clients, wire wide open     5 bosses, 15 items, 15 awards -- all five clean
--   25 clients, REAL RATE LIMIT    5 bosses, 15 items, 15 awards -- all five clean
--   30 clients, REAL RATE LIMIT    5 bosses, 15 items, 15 awards -- all five clean

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

-- The fixture asserts through T while it builds a raid. Counted rather than ignored: a fixture that
-- failed here would make every clean line below a statement about the wrong raid.
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

-- The five things the maintainer said the module is judged on, asked of every client at raid size:
--
--   1. everybody auto-passes                  4. the council reads the votes correctly
--   2. everybody sees every item              5. the items get handed out
--   3. everybody can press their buttons
--
-- Run through five bosses at 25 and again at 30, with ChatThrottleLib's real limiter on. Anything
-- but a clean line is a failure -- there is no "acceptable" column here.
local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local ITEMS = { F.GLOVES, F.WEAPON, F.PLATE_CHEST, F.TOKEN, F.TIER_TOKEN, F.RECIPE }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE",
                  "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER" }

local function Step(secs) for _ = 1, math.floor(secs * 10) do KARTTEST.AdvanceTime(0.1) end end

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
            class = CLASSES[(i % #CLASSES) + 1],
            locale = (i % 2 == 0) and "deDE" or "enUS" })
    end
    RaidSim.RosterUpdate(sim)
    for _ = 1, 6 do KARTTEST.AdvanceTime(10) RaidSim.Drain(sim, 200) end
    if throttled then
        for _, c in ipairs(sim.clients) do
            c.CTL.HardThrottlingBeginTime = GetTime() - 60
            c.CTL.avail = 0
            c.CTL.LastAvailUpdate = GetTime()
        end
    end
    return sim, lm
end

local function Run(size, throttled, label)
    local sim, lm = Build(size, throttled)
    local fail = {}
    local function bad(what) fail[#fail + 1] = what end

    local id, awarded = 12000, {}
    for boss = 1, 5 do
        -- A third of the raid gets NO roll event for each item -- the plate wearer on a cloth drop.
        -- Without this every client learns the item from Blizzard and the wire is never the only
        -- source, which is the whole question behind "everybody sees every item".
        local ids, blind = {}, {}
        for k = 1, 3 do
            id = id + 1
            ids[#ids + 1] = id
            local noRoll = {}
            blind[id] = {}
            for n, c in ipairs(sim.clients) do
                if c ~= lm and (n + k) % 3 == 0 then
                    noRoll[c.name] = true
                    blind[id][c.name] = true
                end
            end
            F.Drop(sim, id, ITEMS[((boss + k) % #ITEMS) + 1], { noRollFor = noRoll })
        end
        Step(2)

        -- 1. AUTO-PASS. Every client that is not the loot owner has to have answered Blizzard's roll
        --    for every council item -- 0 is a pass, 1 is the owner's force-win.
        for _, rid in ipairs(ids) do
            for _, c in ipairs(sim.clients) do
                local answered = (KARTTEST.rolled[rid] or {})[c.unit]
                -- Merrit is the fixture's one raider with lcAutoPass off -- somebody who answers
                -- their own loot windows on purpose, and must NOT be passed for.
                local wants = c.env.KART_Settings.lcAutoPass
                -- Blizzard never offered this client the item, so there is nothing to answer and
                -- nothing to check: skipped rather than asserted either way.
                if not blind[rid][c.name] then
                    if c == lm then
                        if answered ~= 1 then bad("owner did not force-win " .. rid) end
                    elseif not wants then
                        if answered ~= nil then bad(c.name .. " was passed for despite Auto-Pass off") end
                    elseif answered ~= 0 then
                        bad(c.name .. " did not auto-pass " .. rid .. " (" .. tostring(answered) .. ")")
                    end
                end
            end
        end

        -- 2. EVERY ITEM ON EVERY SCREEN, and 3. WITH THE SAME BUTTONS. A vote can only be matched
        --    against the raid's tally if both ends agree on how many buttons there are (B25).
        local ownerButtons = #RaidSim.As(lm, function() return lm.KART.LC.GetButtonConfig() end)
        for _, c in ipairs(sim.clients) do
            for _, rid in ipairs(ids) do
                if not c.KART.LC.rollItems[rid] then
                    bad(c.name .. " never saw " .. rid
                        .. (blind[rid][c.name] and " (no roll event -- wire was the only source)" or ""))
                end
            end
            local mine = #RaidSim.As(c, function() return c.KART.LC.GetButtonConfig() end)
            if mine ~= ownerButtons then
                bad(c.name .. " has " .. mine .. " buttons, the owner has " .. ownerButtons)
            end
        end

        -- Everybody answers every item.
        for _, c in ipairs(sim.clients) do
            for _, rid in ipairs(ids) do
                RaidSim.As(c, function()
                    local box = { GetText = function() return "zweiter Spec" end }
                    c.KART.LC.Vote.CastVote(rid, (rid % 3) + 1, box)
                end)
            end
        end
        Step(8)

        -- 4. THE COUNCIL READS THEM. Not only the owner: every council seat has to hold every
        --    raider's answer, because that is the screen a decision is made on.
        for _, c in ipairs(sim.clients) do
            if RaidSim.As(c, function() return c.KART.LC.IsCouncil() end) then
                for _, rid in ipairs(ids) do
                    local got = 0
                    for _, d in ipairs(sim.clients) do
                        if (c.KART.LC.votes[rid] or {})[d.guid] then got = got + 1 end
                    end
                    if got < #sim.clients then
                        bad(c.name .. " reads " .. got .. "/" .. #sim.clients .. " votes on " .. rid)
                    end
                end
            end
        end

        -- 5. THE ITEMS GET HANDED OUT.
        for _, rid in ipairs(ids) do
            local winner = sim.clients[(rid % #sim.clients) + 1]
            awarded[rid] = winner.guid
            RaidSim.As(lm, function()
                lm.KART.LC.Trade.AssignWinner(rid, winner.guid, "BIS", nil)
            end)
        end
        Step(3)
        RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
        Step(10)
        RaidSim.Drain(sim, 120)
        KARTTEST.AdvanceTime(60)
        RaidSim.Drain(sim, 120)
    end

    -- ...and every client agrees who got what. C7.
    local want = 0
    for _ in pairs(awarded) do want = want + 1 end
    for _, c in ipairs(sim.clients) do
        local mine = {}
        for _, e in ipairs(c.env.KART_LootHistory or {}) do
            -- e.id is a minted award identifier; the roll is e.rollID.
            if e.rollID then mine[e.rollID] = true end
        end
        local missing = 0
        for rid in pairs(awarded) do if not mine[rid] then missing = missing + 1 end end
        if missing > 0 then bad(c.name .. " is short " .. missing .. " of " .. want .. " awards") end
    end

    local gaveUp = 0
    for _, c in ipairs(sim.clients) do
        gaveUp = gaveUp + (RaidSim.As(c, function() return c.KASC:Diagnostics() end).sendGaveUp or 0)
    end
    if gaveUp > 0 then bad(gaveUp .. " sends given up on") end

    if #fail == 0 then
        print(string.format("%-34s  5 bosses, 15 items, %d clients, %d awards -- all five clean",
            label, #sim.clients, want))
    else
        print(string.format("%-34s  %d FAILURES", label, #fail))
        local shown = {}
        for _, f in ipairs(fail) do
            local key = f:gsub("%d+", "#")
            if not shown[key] then shown[key] = true print("      " .. f) end
        end
    end
end

print("The five, asked of every client:")
Run(25, false, "25 clients, wire wide open")
Run(25, true,  "25 clients, REAL RATE LIMIT")
Run(30, true,  "30 clients, REAL RATE LIMIT")

if fixtureFailures > 0 then
    print(string.format("\n%d fixture assertion(s) failed -- the lines above describe a raid other "
        .. "than the one this file claims to build.", fixtureFailures))
end
