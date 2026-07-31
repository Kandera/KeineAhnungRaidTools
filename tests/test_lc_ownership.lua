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

-- A designation the config owner cannot place is said out loud (B59) ------------------------------
-- The old shape of this was fatal and silent: ownership was derived from "does my own field name
-- me?", so a lootmaster who typed their own nickname on a nickname-blind client owned neither the
-- config nor the loot flow, the raid leader took both, and the only trace was a label in a settings
-- tab nobody opens. Ownership no longer reads any name, so all that is left is the designation not
-- taking -- which is safe, because the leader hands out the loot, but is NOT what was asked for.
do
    KARTTEST.SetNSAPI(false)                 -- nobody can resolve nicknames
    local _, lm = F.NewRaid()
    local out = Capture(function()
        RaidSim.As(lm, function()
            lm.env.KART_Settings.lcLootmaster = "Akuri"   -- a nickname this client cannot place
            lm.KART.LC.ApplyOwnConfig()
            lm.KART.LC.SetSessionActive(false)
            lm.KART.LC.SetSessionActive(true)
        end)
    end)
    T.truthy(out:find("Akuri", 1, true),
        "the config owner is told the name they typed could not be placed")
    T.truthy(RaidSim.As(lm, lm.KART.LC.IsLootOwner),
        "and that they are handing out the loot themselves as a result")
    KARTTEST.SetNSAPI(true)
end

do
    -- A name that DOES resolve says nothing: this must not become a line on every session start.
    local _, lm = F.NewRaid()
    local out = Capture(function()
        RaidSim.As(lm, function()
            lm.env.KART_Settings.lcLootmaster = "Merrit"
            lm.KART.LC.ApplyOwnConfig()
            lm.KART.LC.SetSessionActive(false)
            lm.KART.LC.SetSessionActive(true)
        end)
    end)
    T.truthy(not out:find(lm.KART.L.LC_LOOTMASTER_UNRESOLVED:sub(1, 20), 1, true),
        "a designation that resolves is not complained about")
end

do
    -- The designated lootmaster starting the session before the leader's config has reached them.
    -- Their OWN Lootmaster field is not consulted any more, so the old advice about it would be
    -- noise; what actually matters is that the raid is still on everybody's own settings.
    local _, _, council = F.NewSplitRaid()
    wipe(council.KART.LC.raidConfig)
    local out = Capture(function()
        RaidSim.As(council, function() council.KART.LC.SetSessionActive(true) end)
    end)
    T.truthy(not RaidSim.As(council, council.KART.LC.IsConfigOwner), "the designee does not own the config")
    T.truthy(out:find(council.KART.L.LC_NO_CONFIG_YET, 1, true),
        "and is told the raid leader's settings have not arrived")
end

-- A relay with no council list must not settle the question ---------------------------------------
-- The rule "an empty council list means 'not configured', not 'this raid has no council'" has to
-- hold at all three sites that write it. It held in TryAcceptConfig and in ApplyOwnConfig, and not
-- in HandleConfigRelay, which is the one a reloaded raid leader depends on.
--
-- Every peer answers a state request at once, spread over a fraction of a second. The soak found a
-- raid where the first answer came from another client that had just reloaded and had no list
-- either: it was taken, it cleared the "still waiting" marker, and the real list -- 0.17 seconds
-- behind it, from a client that had been there all evening -- was rejected as "we already have a
-- config". Two clients with amnesia confirmed each other, and the raid split over who was council.
do
    local sim = F.NewSplitRaid()
    local leader = sim.byName.Corvin
    T.truthy(RaidSim.As(leader, leader.KART.LC.IsConfigOwner), "Corvin leads, so Corvin owns the config")

    -- The leader comes back from a reload with nothing, and their own settings name neither a
    -- lootmaster nor a council -- the normal state for a stand-in who has never configured KART, and
    -- the reason the raid's list has to come back over the wire rather than out of their saved
    -- variables. Being raid lead, they write their own empty settings in as the raid config; that is
    -- the state every peer's answer is racing to replace.
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcCouncilMembers = ""
        leader.env.KART_Settings.lcLootmaster     = ""
        wipe(leader.KART.LC.raidConfig)
        leader.KART.LC.ApplyOwnConfig()
    end)
    T.eq(leader.KART.LC.raidConfig.councilMembers, "", "and holds no council list at all")

    local CFG = "4:BIS;Upgrade;Offspec;Sonstiges;Pass:0:"
    -- The first answer is from a client just as empty-handed.
    RaidSim.As(leader, function()
        leader.KART.LC.HandleConfigRelay(CFG .. ":", sim.byName.Alric.guid)
    end)
    -- The raid's real answer lands a fraction of a second later.
    RaidSim.As(leader, function()
        leader.KART.LC.HandleConfigRelay(CFG .. ":Bramor;Merrit;Corvin", sim.byName.Sinja.guid)
    end)

    T.eq(leader.KART.LC.raidConfig.councilMembers, "Bramor;Merrit;Corvin",
        "the answer that carries a council list wins over the one that does not")
    T.truthy(RaidSim.As(leader, function() return leader.KART.LC.IsCouncil(sim.byName.Merrit.guid) end),
        "so the leader agrees with the rest of the raid about who is council")
end

do
    -- ...and not the other way round: an empty relay arriving second does not undo it, or the two
    -- would swap places forever while peers keep answering.
    local sim = F.NewSplitRaid()
    local leader = sim.byName.Corvin
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcCouncilMembers = ""
        leader.env.KART_Settings.lcLootmaster     = ""
        wipe(leader.KART.LC.raidConfig)
        leader.KART.LC.ApplyOwnConfig()
    end)
    local CFG = "4:BIS;Upgrade;Offspec;Sonstiges;Pass:0:"

    RaidSim.As(leader, function()
        leader.KART.LC.HandleConfigRelay(CFG .. ":Bramor;Merrit;Corvin", sim.byName.Sinja.guid)
        leader.KART.LC.HandleConfigRelay(CFG .. ":", sim.byName.Alric.guid)
    end)
    T.eq(leader.KART.LC.raidConfig.councilMembers, "Bramor;Merrit;Corvin",
        "a list already recovered is not taken back out by an empty answer")
end

do
    -- ...and not while the leader is still holding a config of their own making either. Taking raid
    -- lead runs LC.ApplyOwnConfig, which KEEPS the raid's council list when the new leader has none
    -- of their own -- so this client has both the marker that says "still asking" and a real list to
    -- lose. An empty answer must leave it alone.
    local sim = F.NewSplitRaid()
    local leader = sim.byName.Corvin
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcCouncilMembers = ""
        leader.env.KART_Settings.lcLootmaster     = ""
        leader.KART.LC.ApplyOwnConfig()
    end)
    T.eq(leader.KART.LC.raidConfig.councilMembers, "Bramor;Merrit;Corvin",
        "taking lead with no council of your own keeps the raid's")
    T.truthy(leader.KART.LC.raidConfig.fromSelf, "and leaves the config marked as our own")

    RaidSim.As(leader, function()
        leader.KART.LC.HandleConfigRelay("4:BIS;Upgrade;Offspec;Sonstiges;Pass:0::",
            sim.byName.Alric.guid)
    end)
    T.eq(leader.KART.LC.raidConfig.councilMembers, "Bramor;Merrit;Corvin",
        "and an answer with no list does not take it away")
    T.truthy(RaidSim.As(leader, function() return leader.KART.LC.IsCouncil(sim.byName.Merrit.guid) end),
        "the lookup the awards are gated on says the same")
end
