-- The ownership rules themselves (docs/OWNERSHIP.md).
--
-- Everything else in tests/ exercises them through a scenario. This file states them directly, so a
-- change to the rule fails HERE, next to the sentence it breaks, instead of surfacing as somebody
-- else's raid going wrong three files away.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

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

-- Rule 1: the config owner is the raid leader, and nobody else -------------------------------------
do
    local sim, lm = F.NewRaid()
    for _, c in ipairs(sim.clients) do
        T.eq(RaidSim.As(c, c.KART.LC.IsConfigOwner), c == lm,
            c.name .. " owns the config exactly when holding raid lead")
    end

    -- Not derived from anybody's settings. The lootmaster field names the leader here, and taking
    -- that name away must change nothing about who owns it.
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsConfigOwner),
        "and still owns it after designating somebody else -- the two roles are separate")
    T.truthy(RaidSim.As(sim.byName.Merrit, sim.byName.Merrit.KART.LC.IsLootOwner),
        "while the designee owns the LOOT flow")
    T.truthy(not RaidSim.As(sim.byName.Merrit, sim.byName.Merrit.KART.LC.IsConfigOwner),
        "and not the config")
end

-- Rule 3: a config is accepted from the raid leader, and from nobody else --------------------------
do
    local sim, lm = F.NewRaid()
    local raider = sim.byName.Alric
    local before = raider.KART.LC.raidConfig.buttonLabels
    T.truthy(before and before ~= "", "the raider starts with the raid's config")

    -- Straight onto the wire from a non-leader, bypassing the gate a real client would hit first.
    RaidSim.As(sim.byName.Sinja, function()
        sim.byName.Sinja.KART.LC.SendLC("LC_CONFIG:4:A;B;C;D;E:0::Sinja")
    end)
    T.eq(raider.KART.LC.raidConfig.buttonLabels, before, "a config from a non-leader is ignored")

    -- And the leader's is taken, whatever it says -- acceptance is not decided on content.
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcButtonLabels = "A;B;C;D;E"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(raider.KART.LC.raidConfig.buttonLabels, "A;B;C;D;E", "the raid leader's is taken")
end

-- Rule 4: the designation travels as an identity key ----------------------------------------------
-- Resolving the NAME on every receiver is the dead end that cost a raid its config: a client without
-- Northern Sky can never resolve a nickname. The owner typed it and is in the raid with that person.
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster = "Merrit"
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    local sent = RaidSim.Sent(sim, "LC_CONFIG:")
    T.eq(#sent, 1, "the config went out")
    T.truthy(tostring(sent[1].msg or ""):find(sim.byName.Merrit.guid, 1, true),
        "carrying the designee's identity key, not the text that was typed")
end

-- An empty council list means "not configured", not "this raid has no council" ---------------------
-- Found by the soak: a client promoted to raid lead for a moment, who never configured KART,
-- broadcast an empty list, every receiver took it, and from then on Trade.HandleResult rejected every
-- award because nobody was council any more. 94 of 3000 raids lost an award in silence.
do
    local sim = F.NewRaid()
    local raider = sim.byName.Alric
    local before = raider.KART.LC.raidConfig.councilMembers
    T.truthy(before and before ~= "", "the raid has a council to lose")

    -- The whole point is the RECEIVING side, so the config is put on the wire directly: an empty
    -- council list from a legitimate sender.
    local sinja = sim.byName.Sinja
    RaidSim.Promote(sim, "Sinja")
    RaidSim.As(sinja, function()
        sinja.KART.LC.SendLC("LC_CONFIG:4:BIS;Upgrade;Offspec;Sonstiges;Pass:1::")
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(raider.KART.LC.raidConfig.councilMembers, before, "an empty council list does not clear it")
    T.truthy(RaidSim.As(raider, function()
        return raider.KART.LC.IsSenderCouncil(sim.byName.Corvin.guid)
    end), "so a council member is still council, and their awards still count")

    -- A NON-empty list still replaces it outright, so changing the council takes one broadcast.
    RaidSim.As(sinja, function()
        sinja.KART.LC.SendLC("LC_CONFIG:4:BIS;Upgrade;Offspec;Sonstiges;Pass:1::Alric")
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(raider.KART.LC.raidConfig.councilMembers, "Alric", "a real list replaces the old one")
    T.truthy(not RaidSim.As(raider, function()
        return raider.KART.LC.IsSenderCouncil(sim.byName.Corvin.guid)
    end), "and takes the dropped members off the council")
end

-- Taking the role over is announced ----------------------------------------------------------------
-- Nobody hands it over any more -- you simply hold raid lead, and from that moment the raid runs on
-- your settings, with lcRollsEnabled defaulting to OFF. Somebody promoted by accident would otherwise
-- switch the whole raid onto their own defaults without a word.
do
    local sim = F.NewRaid()
    local sinja = sim.byName.Sinja
    local out = Capture(function()
        RaidSim.Promote(sim, "Sinja")
        RaidSim.RosterUpdate(sim)
        KARTTEST.AdvanceTime(5)
    end)
    T.truthy(out:find(sinja.KART.L.LC_CONFIG_OWNER_NOW, 1, true),
        "the client that just became config owner is told the raid runs on its settings")

    -- Once per arrival, not once per roster change: a raid produces those constantly.
    local again = Capture(function()
        RaidSim.RosterUpdate(sim)
        KARTTEST.AdvanceTime(5)
    end)
    T.truthy(not again:find(sinja.KART.L.LC_CONFIG_OWNER_NOW, 1, true),
        "and not again on every roster change afterwards")

    -- Losing the role and getting it back is a new arrival, and worth saying again.
    RaidSim.Promote(sim, "Bramor")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    local back = Capture(function()
        RaidSim.Promote(sim, "Sinja")
        RaidSim.RosterUpdate(sim)
        KARTTEST.AdvanceTime(5)
    end)
    T.truthy(back:find(sinja.KART.L.LC_CONFIG_OWNER_NOW, 1, true),
        "but it is said again the next time the role arrives")
end
