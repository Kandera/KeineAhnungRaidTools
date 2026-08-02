-- B62: a raider on a release older than the current loot-council protocol cannot take part, and
-- their client says nothing about it -- it simply drops the tokens it does not know.
--
-- The failure this prevents is not a crash, it is an evening of silence: their client keeps naming a
-- lootmaster who has stepped down, rejects everything the real owner sends, and shows no vote window
-- on any item. Nothing here can repair the old client. What it must do is name the people concerned,
-- on the one screen that can act on it, while there is still time to tell them to update.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- The comparison itself, and who counts as outdated ----------------------------------------------
do
    local _, lm = F.NewRaid()
    local LC = lm.KART.LC

    -- Shared with the council panel's per-row "outdated" marker, so both agree on the answer.
    local Older = lm.KART.IsOlderVersion
    T.truthy(Older("3.2.1", "3.2.2"), "a lower patch is older")
    T.truthy(not Older("3.2.2", "3.2.2"), "the same version is not")
    T.truthy(not Older("3.3.0", "3.2.2"), "and a newer build is never called outdated")
    T.truthy(Older("2.9.9", "3.0.0"), "a lower major is older regardless of the rest")
    -- Lenient on shape, and the direction that matters is the FALSE ALARM: a strict three-part
    -- match fails outright on "3.3", collapses every field to 0, and calls a peer who is AHEAD of us
    -- outdated -- telling the loot owner to chase somebody who has nothing to update.
    T.truthy(not Older("3.3", "3.2.2"), "a two-part version ahead of us is not called outdated")
    T.truthy(Older("3.2", "3.2.2"), "while one behind us still is")
    T.truthy(Older("3.1.0", "3.2"), "and the version compared against parses just as leniently")
    T.truthy(not Older("3.2.2-beta", "3.2.2"), "a build suffix does not make a version older")
    -- Raised for 3.3.0 without a new token being added: the release changes enough of the shared
    -- flow -- who owns the council list, what survives a reload, what the history catch-up carries --
    -- that a peer left on 3.2.2 is worth naming rather than left to be discovered mid-raid.
    T.eq(LC.PROTOCOL_VERSION, "3.3.0", "the protocol floor is the current release")

    T.deep_eq(RaidSim.As(lm, LC.OutdatedRaiders), {},
        "a raid nobody has reported a version for names nobody -- silence is not evidence")

    lm.KART.PlayerVersions = {
        Merrit = "3.2.2",   -- the case: on the previous release
        Corvin = "3.3.0",   -- current
        Alric  = "3.4.0",   -- ahead of us
        Bramor = "3.2.2",   -- ourselves, and we never process our own broadcast anyway
    }
    T.deep_eq(RaidSim.As(lm, LC.OutdatedRaiders), { "Merrit" },
        "only the raider actually below the protocol is named")

    -- Their client neither sends nor rejects anything, so their version cannot break the flow for
    -- anybody -- naming them would be a false alarm on a screen that has to stay worth reading.
    lm.KART.PlayerLCEnabled = { Merrit = false }
    T.deep_eq(RaidSim.As(lm, LC.OutdatedRaiders), {},
        "an outdated raider with the module switched off is not a problem")
    lm.KART.PlayerLCEnabled = { Merrit = true }

    -- Sorted, so two people comparing their /kart status side by side read the same list. Alric
    -- stands behind Merrit in the raid and in front of them in the alphabet, which is what makes
    -- this an assertion about sorting rather than about roster order.
    lm.KART.PlayerVersions.Alric = "3.1.0"
    T.deep_eq(RaidSim.As(lm, LC.OutdatedRaiders), { "Alric", "Merrit" }, "and the list is sorted")
end

-- The warning ------------------------------------------------------------------------------------
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

do
    local sim, lm, council, raider = F.NewRaid()
    for _, c in ipairs(sim.clients) do c.KART.PlayerVersions = { Merrit = "3.2.1" } end

    local out = Capture(function() RaidSim.As(lm, lm.KART.LC.WarnOutdatedRaiders) end)
    T.truthy(out:find("Merrit", 1, true), "the loot owner is told which raider is behind")
    T.truthy(out:find("3.3.0", 1, true), "and what they need to be on")

    -- Latched: the hook is a peer's version arriving, and a raid forming answers one request with one
    -- reply per raider, repeatedly. Unlatched, the owner would read the same line all evening.
    T.eq(Capture(function() RaidSim.As(lm, lm.KART.LC.WarnOutdatedRaiders) end), "",
        "and told once, not once per hello")

    -- A second outdated raider appearing later is still worth a line -- the latch is per name.
    lm.KART.PlayerVersions.Sinja = "3.1.0"
    local more = Capture(function() RaidSim.As(lm, lm.KART.LC.WarnOutdatedRaiders) end)
    T.truthy(more:find("Sinja", 1, true), "somebody arriving later is named too")
    T.truthy(not more:find("Merrit", 1, true), "without repeating whoever was already reported")

    -- Everyone else would be reading a warning they cannot act on: they do not hand out the loot and
    -- they cannot make anybody update.
    T.eq(Capture(function() RaidSim.As(council, council.KART.LC.WarnOutdatedRaiders) end), "",
        "a council member who does not own the loot flow is not warned")
    T.eq(Capture(function() RaidSim.As(raider, raider.KART.LC.WarnOutdatedRaiders) end), "",
        "and neither is a plain raider")
end

-- Where it fires ---------------------------------------------------------------------------------
-- Starting the session, because that is the last moment before items start dropping.
do
    KARTTEST.realm = "TarrenMill"
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    KARTTEST.solo, KARTTEST.popups = {}, {}
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)
    local lm = sim.byName.Bramor
    lm.KART.PlayerVersions = { Merrit = "3.2.1" }

    local out = Capture(function()
        RaidSim.As(lm, function()
            lm.env.KART_Settings.lcLootmaster = "Bramor"
            lm.KART.LC.ApplyOwnConfig()
            lm.KART.LC.SetSessionActive(true)
        end)
    end)
    T.truthy(out:find("Merrit", 1, true), "starting the session names whoever is behind")
end

-- And whenever a peer's version arrives, which is the only moment the answer can change. Checked
-- against the source because Core.lua needs the game to load -- if this call moves, this must too.
do
    local core = assert(io.open("Core.lua", "r")):read("*a")
    local body = core:match("KASC:OnPeer%(function.-\nend%)\n")
    T.truthy(body, "the peer handler was found in Core.lua")
    T.truthy(body and body:find("KART.LC.WarnOutdatedRaiders()", 1, true),
        "and it re-checks the raid every time a version lands")
end

-- Leaving the raid --------------------------------------------------------------------------------
-- The names belonged to the roster we just left; walking into the next raid still latched would
-- leave an outdated raider there unreported for the whole evening.
do
    local _, lm = F.NewRaid()
    lm.KART.PlayerVersions = { Merrit = "3.2.1" }
    Capture(function() RaidSim.As(lm, lm.KART.LC.WarnOutdatedRaiders) end)
    T.truthy(lm.KART.LC.outdatedWarned.Merrit, "Merrit is on the reported list")

    KARTTEST.solo[lm.unit] = true
    RaidSim.As(lm, function() lm.KART.LC.CheckRaidJoin() end)
    KARTTEST.AdvanceTime(5)                       -- past the raid-exit confirmation window
    T.truthy(not lm.KART.LC.outdatedWarned.Merrit, "and off it again once the raid is left")
    KARTTEST.solo[lm.unit] = nil
end

-- /kart status ------------------------------------------------------------------------------------
-- Printed by everyone, not only the loot owner: the person pasting the output is usually the one who
-- cannot see an item, and this line is what tells them the cause is somebody else's client.
do
    local _, _, _, raider = F.NewRaid()
    raider.KART.PlayerVersions = { Merrit = "3.2.1" }
    local out = Capture(function() RaidSim.As(raider, raider.KART.LC.PrintStatus) end)
    T.truthy(out:find("Merrit", 1, true),
        "a plain raider's status names the outdated raider even though they were never warned")
end
