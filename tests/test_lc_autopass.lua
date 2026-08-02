-- B63: LC_START for a real drop is sent from exactly one place, inside the loot owner's own
-- START_LOOT_ROLL handler. The owner is subject to the same conditions as everyone else -- out of
-- range, dead, released, ineligible -- and there is no second broadcaster.
--
-- Auto-Pass did not depend on that announcement, so the whole raid passed on an item nobody had
-- force-won: it went to whichever raider is NOT running KART, or to nobody, with no vote window
-- anywhere. Passing is now conditional on the council demonstrably having taken the item up.
--
-- Which of the two paths does the passing depends on the order the local roll event and the owner's
-- message happen to arrive in, and BOTH orders occur, so both are exercised here.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop = F.NewRaid, F.Drop

-- Auto-Pass is on by default; Merrit is the fixture's one raider who clicks Blizzard's window
-- themselves, and Bramor is the lootmaster, who force-wins rather than passes.
local AUTOPASSERS = { "Corvin", "Alric", "Sinja" }

local function PassedBy(sim, rollID, name)
    local client = sim.byName[name]
    return (KARTTEST.rolled[rollID] or {})[client.unit]
end

-- The wait before a client that heard nothing says so. Read out of the source rather than repeated:
-- it is derived from the owner's link-retry budget, so a copy here would silently stop matching.
local ANNOUNCE_WAIT
do
    local src = assert(io.open("LootCouncil.lua", "r")):read("*a")
    local attempts = tonumber(src:match("START_ROLL_MAX_ATTEMPTS%s*=%s*(%d+)"))
    local retryMax = tonumber(src:match("START_ROLL_RETRY_MAX%s*=%s*(%d+)"))
    local expr = src:match("local ANNOUNCE_WAIT%s*=%s*([^\r\n]+)")
    T.truthy(attempts and retryMax and expr, "the announcement wait was found in LootCouncil.lua")
    ANNOUNCE_WAIT = attempts * retryMax + 5
    T.eq(expr, "START_ROLL_MAX_ATTEMPTS * START_ROLL_RETRY_MAX + 5",
        "and is still derived from the owner's own retry budget, not a hand-picked number")
end

local function Capture(fn)
    local lines = {}
    local realPrint = _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end

-- The normal evening: the announcement lands, everybody passes ------------------------------------
-- The regression guard for everything below. Auto-Pass exists so a raider does not have to click
-- loot windows, and it has to keep doing that.
do
    local sim = NewRaid()
    Drop(sim, 50, F.GLOVES)

    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 50, name), 0, name .. " passed Blizzard's roll once the council had the item")
    end
    T.is_nil(PassedBy(sim, 50, "Merrit"), "a raider with Auto-Pass off is still left to answer it themselves")
    T.eq(PassedBy(sim, 50, "Bramor"), 1, "and the lootmaster force-won it rather than passing")
end

-- The other arrival order: the local roll event first, the announcement second --------------------
-- The fixture drops in raid order, so the owner announces before the other clients have run their
-- own handler. Reversing it puts the announcement second, which is the order the live game produces
-- far more often -- Blizzard raises the event on every client at once and the message has to travel.
do
    local sim, lm = NewRaid()
    KARTTEST.lootRolls[51] = { itemID = F.GLOVES, bop = true, forNames = {} }
    for _, c in ipairs(sim.clients) do KARTTEST.lootRolls[51].forNames[c.name] = true end
    for _, c in ipairs(sim.clients) do
        if c ~= lm then RaidSim.As(c, function() c.KART.LC.OnStartLootRoll(51) end) end
    end
    for _, name in ipairs(AUTOPASSERS) do
        T.is_nil(PassedBy(sim, 51, name), name .. " does not pass before the council has said anything")
    end

    RaidSim.As(lm, function() lm.KART.LC.OnStartLootRoll(51) end)
    KARTTEST.AdvanceTime(0)
    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 51, name), 0, "and passes as soon as the announcement arrives -- " .. name)
    end
end

-- B63 itself: the owner never gets the roll event -------------------------------------------------
do
    local sim, lm = NewRaid()
    Drop(sim, 52, F.GLOVES, { noRollFor = { Bramor = true } })

    T.eq(#RaidSim.Sent(sim, "LC_START"), 0, "nobody announces the item, because only the owner ever does")
    T.is_nil(lm.KART.LC.rollItems[52], "and the owner is not tracking an item they never saw")

    -- The defect: every one of these used to pass, handing the item to whoever is not running KART.
    for _, name in ipairs(AUTOPASSERS) do
        T.is_nil(PassedBy(sim, 52, name), name .. " does not pass an item the council never took up")
    end
    -- Blizzard's own window is therefore still live for them, which is the whole point: the raid can
    -- roll on it the way it would without this addon.
    T.truthy(RaidSim.As(sim.byName.Corvin, function() return GetLootRollItemLink(52) end),
        "so their roll window is still open to answer by hand")
end

-- ...and after the wait, the people it affects are told why ---------------------------------------
do
    local sim = NewRaid()
    Drop(sim, 53, F.GLOVES, { noRollFor = { Bramor = true } })
    local corvin = sim.byName.Corvin

    local early = Capture(function() KARTTEST.AdvanceTime(ANNOUNCE_WAIT - 5) end)
    T.truthy(not early:find("Loot Council", 1, true), "nothing is said while the announcement could still arrive")

    local out = Capture(function() KARTTEST.AdvanceTime(10) end)
    T.truthy(out:find(KARTTEST.items[F.GLOVES].name, 1, true), "then the item is named")
    T.truthy(not corvin.KART.LC.rollAnnounced[53], "and it is still on record as never announced")
end

do
    -- Nothing to explain when it did arrive, and nothing to explain to somebody who was going to
    -- click the window anyway.
    local sim = NewRaid()
    Drop(sim, 54, F.GLOVES)
    local out = Capture(function() KARTTEST.AdvanceTime(ANNOUNCE_WAIT + 5) end)
    T.truthy(not out:find(KARTTEST.items[F.GLOVES].name, 1, true),
        "a drop the council took up says nothing when the wait runs out")

    -- Everyone, because Capture cannot tell one client's chat from another's -- and a raid where
    -- nobody uses Auto-Pass must stay completely silent about an item it simply rolls on by hand.
    local sim2 = NewRaid()
    for _, c in ipairs(sim2.clients) do c.env.KART_Settings.lcAutoPass = false end
    Drop(sim2, 55, F.GLOVES, { noRollFor = { Bramor = true } })
    local out2 = Capture(function() KARTTEST.AdvanceTime(ANNOUNCE_WAIT + 5) end)
    T.truthy(not out2:find(KARTTEST.items[F.GLOVES].name, 1, true),
        "and a raider who answers their own loot windows is not told either")
end

-- The owner never waits for their own announcement ------------------------------------------------
-- Normally invisible, because force-winning answers the roll and a client with no roll left says
-- nothing. It becomes visible on an item the lootmaster cannot roll on at all -- no Need, no Greed,
-- no Disenchant, no Transmog -- where ForceWinRoll has nothing to claim it with and the window stays
-- open. Without the guard the owner is then told their own item was never announced.
do
    local sim, lm = NewRaid()
    Drop(sim, 58, F.GLOVES, { canNeed = false, canGreed = false })

    T.is_nil(PassedBy(sim, 58, "Bramor"), "the lootmaster had no roll type to claim it with")
    T.truthy(RaidSim.As(lm, function() return GetLootRollItemLink(58) end),
        "so their window is still open when the wait runs out")
    local out = Capture(function() KARTTEST.AdvanceTime(ANNOUNCE_WAIT + 5) end)
    T.truthy(not out:find(KARTTEST.items[F.GLOVES].name, 1, true),
        "and the client that did the announcing is not told nobody announced it")
end

-- Below the raid's rarity threshold: unchanged ----------------------------------------------------
-- The council never announces these -- the lootmaster passes on them too -- so there is nothing to
-- wait for, and making Auto-Pass wait would have left a rare sitting on everyone's screen forever.
do
    local sim = NewRaid()
    Drop(sim, 56, F.RARE)

    T.eq(#RaidSim.Sent(sim, "LC_START"), 0, "a rare is below the threshold and is never announced")
    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 56, name), 0, name .. " still passes it straight away")
    end
    T.eq(PassedBy(sim, 56, "Bramor"), 0, "and so does the lootmaster")
end

-- A reused rollID must not inherit either flag ----------------------------------------------------
-- Blizzard hands the same rollID to a genuinely different item within seconds (see PurgeStaleRoll).
-- A stale "already announced" would make the next item pass on the strength of the previous one's
-- announcement.
do
    local sim = NewRaid()
    Drop(sim, 57, F.GLOVES)
    local corvin = sim.byName.Corvin
    T.truthy(corvin.KART.LC.rollAnnounced[57], "the first item was announced")

    RaidSim.As(corvin, function() corvin.KART.LC.Trade.ClearRollState(57) end)
    T.truthy(not corvin.KART.LC.rollAnnounced[57], "and clearing the roll forgets that")
    T.truthy(not corvin.KART.LC.rollSeenHere[57], "along with having seen it locally")
end

-- Auto-Pass switched OFF is a raider who answers the window themselves ------------------------------
-- The setting is the first half of that branch, and nothing held it: with it off, a below-threshold
-- item must be left alone for this raider exactly like any other. Passing on their behalf when they
-- asked not to is the same damage the whole file is about, reached from the other side -- the item
-- goes to whoever did not pass, and the raider never saw a choice.
do
    local sim = NewRaid()
    for _, name in ipairs(AUTOPASSERS) do
        sim.byName[name].env.KART_Settings.lcAutoPass = false
    end
    Drop(sim, 58, F.RARE)

    for _, name in ipairs(AUTOPASSERS) do
        T.is_nil(PassedBy(sim, 58, name), name .. " does not pass with Auto-Pass switched off")
    end
    for _, name in ipairs(AUTOPASSERS) do
        sim.byName[name].env.KART_Settings.lcAutoPass = true
    end
end
