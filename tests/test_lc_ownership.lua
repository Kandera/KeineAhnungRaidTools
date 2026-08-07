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

-- An empty Lootmaster field means "not configured" too (B76) --------------------------------------
-- The rule below it -- an empty council list does not clear the raid's -- was written for exactly
-- this shape and stopped one field short. Raid lead moves to somebody who has never filled the
-- Lootmaster field in (the ordinary case: a stand-in, or a promotion by accident), LC.ApplyOwnConfig
-- writes their empty field in as the raid's designation, and from that instant they answer
-- LC.IsLootOwner with "yes" while everybody else still points at the person actually handing out the
-- loot. Both halves are internally consistent, which is what makes it so quiet.
--
-- An item dropping in that window is force-won by the new leader and announced by them -- and every
-- client that still holds the designation rejects the LC_START, because LC.HandleStart opens with
-- IsSenderLootOwner. The roll then exists on part of the raid, and a vote cast on it is dropped for
-- good by the rest. Found by the soak; no reload needed, one promotion is enough.
do
    local sim, lm = F.NewRaid()
    local sinja, merrit = sim.byName.Sinja, sim.byName.Merrit
    T.eq(sinja.env.KART_Settings.lcLootmaster or "", "",
        "the incoming leader has no designation of their own")

    RaidSim.Promote(sim, "Sinja")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    T.eq(sinja.KART.LC.raidConfig.lootmaster, lm.guid,
        "taking lead with an empty field keeps the designation the raid already has")
    T.truthy(not RaidSim.As(sinja, sinja.KART.LC.IsLootOwner),
        "so the new leader does not also take over the loot flow")
    T.eq(merrit.KART.LC.raidConfig.lootmaster, lm.guid, "and the raid still agrees who that is")
    T.truthy(RaidSim.As(merrit, function() return merrit.KART.LC.IsSenderLootOwner(lm.guid) end),
        "so an item the lootmaster announces is still accepted")
end

do
    -- ...and a leader who HAS filled it in still replaces the designation outright, so changing who
    -- hands out the loot takes one broadcast and not a negotiation.
    local sim = F.NewRaid()
    local sinja, merrit = sim.byName.Sinja, sim.byName.Merrit
    RaidSim.Promote(sim, "Sinja")
    RaidSim.As(sinja, function()
        sinja.env.KART_Settings.lcLootmaster = "Corvin"
        sinja.KART.LC.ApplyOwnConfig()
        sinja.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(sinja.KART.LC.raidConfig.lootmaster, sim.byName.Corvin.guid, "the new designation takes")
    T.eq(merrit.KART.LC.raidConfig.lootmaster, sim.byName.Corvin.guid, "and reaches the raid")
end

do
    -- The one time the designation genuinely has to go: the person named in it has LEFT. Keeping it
    -- would point the whole raid at an empty chair, and the rule above -- an empty field keeps what
    -- the raid has -- would do exactly that if it read the stored key instead of LC.GetLootmaster,
    -- which masks a name that is no longer in the group. The raid leader takes the loot flow over
    -- from that moment, which is what standing in means.
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Sinja")             -- lead moves; Sinja has no field of their own
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)
    T.eq(sim.byName.Sinja.KART.LC.raidConfig.lootmaster, lm.guid, "the designation is still Bramor's")

    RaidSim.Leave(sim, "Bramor")
    RaidSim.RosterUpdate(sim)
    KARTTEST.AdvanceTime(5)

    local sinja = sim.byName.Sinja
    T.eq(sinja.KART.LC.raidConfig.lootmaster, "",
        "once the designee has left, the raid stops naming them")
    T.truthy(RaidSim.As(sinja, sinja.KART.LC.IsLootOwner),
        "and the raid leader carries the loot flow instead")
    T.eq(sim.byName.Merrit.KART.LC.raidConfig.lootmaster, "", "on every client, not just theirs")
end

-- Rule 7: a relay says WHETHER the raid has a lootmaster, without naming them ----------------------
-- LC.RelayRaidConfig carries the lootmaster field EMPTY on purpose: only the config owner may name
-- anybody. Read as "nobody was named", that made a reloaded raid leader believe it owned the loot
-- while the real lootmaster stood next to it -- two announcers, and the wrong one never converges
-- because it is its own announcer (B130). The field says which of the two it is now.
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric")
    -- Cleared explicitly, because since D2 a reload no longer produces a client holding no config --
    -- it restores one from disk, and LC.HandleConfigRelay refuses a relay outright while anything is
    -- held (its `next(LC.raidConfig) ~= nil` guard). Without this the assertions below are satisfied
    -- by the restored config and the relay under test never runs at all: delete RelayRaidConfig's
    -- presence field and the case still passes. The state being modelled is a client that has been
    -- told nothing yet, which is what a reload used to leave behind.
    RaidSim.As(leader, function() wipe(leader.KART.LC.raidConfig) end)
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(1)

    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), false,
        "a leader told the raid has a lootmaster does not own the loot")
    T.eq(RaidSim.As(lm, lm.KART.LC.IsLootOwner), true, "and the real lootmaster still does")
    T.truthy(not RaidSim.As(leader, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "and is asked nothing, because somebody is there")
end

-- It survives a roster update ---------------------------------------------------------------------
-- LC.ApplyOwnConfig runs from GROUP_ROSTER_UPDATE, and the first attempt at this fix was wiped by it
-- within seconds of being set. What the relay said about the RAID is not ours to forget on a join.
--
-- ApplyOwnConfig is called DIRECTLY rather than through RaidSim.RosterUpdate, and that is the whole
-- value of the case: a roster update also makes the leader re-request state, and a fresh relay lands
-- a moment later and re-sets the bit. Written that way the test passed with the guard mutated away --
-- it was measuring the recovery, not the guard. One call, nothing else moving, no second relay.
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric")
    -- The client a relay is FOR: one that came back holding nothing. A reload inside the config
    -- snapshot's window restores the raid's own config (D2), and a client that holds one rejects the
    -- relay on purpose -- its lootmaster field is the better answer (see LC.HandleConfigRelay). What
    -- is under test here is the other client: a crash, or a snapshot past its bound.
    RaidSim.As(leader, function() wipe(leader.KART.LC.raidConfig) end)
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(1)
    T.eq(leader.KART.LC.raidConfig.relayLootmaster, "1", "the leader was told the raid has one")

    RaidSim.As(leader, leader.KART.LC.ApplyOwnConfig)

    T.eq(leader.KART.LC.raidConfig.relayLootmaster, "1",
        "and re-applying its own empty field does not unsay it")
    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), false,
        "a roster update does not hand the loot back to the leader")
    T.eq(RaidSim.As(lm, lm.KART.LC.IsLootOwner), true, "and the lootmaster still has it")
end

-- The named lootmaster is gone, so the leader is asked ---------------------------------------------
do
    local sim = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric")
    -- Came back with nothing, as above: the relay is what tells THIS client the raid has a lootmaster.
    RaidSim.As(leader, function() wipe(leader.KART.LC.raidConfig) end)
    RaidSim.Leave(sim, "Bramor")
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(2)

    T.truthy(RaidSim.As(leader, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "a leader told the lootmaster is gone is asked to stand in")
end

-- A raid that never named anybody is untouched -----------------------------------------------------
-- The documented setup. This is the case the third state must not swallow, and the case the first
-- attempt at this fix broke.
--
-- The leader BROADCASTS the empty field rather than only applying it: "never named anybody" is a
-- fact about the raid, and a raid whose members were told the opposite an hour ago is a different
-- setup entirely. Without the broadcast the relayer would still be carrying the old designation and
-- would be telling the truth about it.
do
    local sim = F.NewRaid()
    local leader = sim.byName.Bramor
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcLootmaster = ""
        wipe(leader.KART.LC.raidConfig)
        leader.KART.LC.BroadcastRaidConfig()
    end)
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(2)

    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), true,
        "a raid that never named a lootmaster still lets its leader hand out the loot")
    T.truthy(not RaidSim.As(leader, KARTTEST.AcceptPopup, "KART_LC_STAND_IN"),
        "and nobody is pestered about standing in")
end

-- A whisper answers one client, not the raid ------------------------------------------------------
-- LC.BroadcastRaidConfig with a target is the sync-request answer (see LC.HandleStateRequest), and it
-- reaches exactly one client. Clearing what a relay said about the raid there took the loot flow back
-- in front of an audience that had never heard otherwise: two announcers again, triggered by anybody
-- reloading mid-session (B130).
do
    local sim, lm = F.NewRaid()
    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric")
    -- Cleared explicitly, because since D2 a reload no longer produces a client holding no config --
    -- it restores one from disk, and LC.HandleConfigRelay refuses a relay outright while anything is
    -- held (its `next(LC.raidConfig) ~= nil` guard). Without this the assertions below are satisfied
    -- by the restored config and the relay under test never runs at all: delete RelayRaidConfig's
    -- presence field and the case still passes. The state being modelled is a client that has been
    -- told nothing yet, which is what a reload used to leave behind.
    RaidSim.As(leader, function() wipe(leader.KART.LC.raidConfig) end)
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(1)

    RaidSim.As(leader, function()
        leader.KART.LC.BroadcastRaidConfig(sim.byName.Sinja.name .. "-" .. sim.byName.Sinja.realm)
    end)
    KARTTEST.AdvanceTime(1)

    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), false,
        "answering one client's sync request does not make the leader the loot owner")
    T.eq(RaidSim.As(lm, lm.KART.LC.IsLootOwner), true, "so the raid still has exactly one")
end

-- A relay-fed client passes on what it was told ---------------------------------------------------
-- LC.HandleConfigRelay blanks the lootmaster field, so a client that got its own config from a relay
-- has no designation to derive from. Deriving anyway made the second hop state "nobody was named" --
-- B130's untruth, asserted rather than implied -- and a relay-fed client answers state requests as
-- readily as anybody else.
do
    local sim, lm = F.NewRaid()
    local hop = RaidSim.Reload(sim, "Sinja")
    -- Came back with nothing, as in the relay cases above: a client still holding the raid's config
    -- would reject the relay and have a designation of its own to pass on.
    RaidSim.As(hop, function() wipe(hop.KART.LC.raidConfig) end)
    RaidSim.As(sim.byName.Merrit, function() sim.byName.Merrit.KART.LC.RelayRaidConfig(hop.name) end)
    KARTTEST.AdvanceTime(1)
    T.eq(hop.KART.LC.raidConfig.lootmaster, "", "the first hop holds no designation of its own")
    T.eq(hop.KART.LC.raidConfig.relayLootmaster, "1", "only what it was told about the raid")

    RaidSim.Promote(sim, "Alric")
    local leader = RaidSim.Reload(sim, "Alric")
    RaidSim.As(leader, function() wipe(leader.KART.LC.raidConfig) end)
    RaidSim.As(hop, function() hop.KART.LC.RelayRaidConfig(leader.name) end)
    KARTTEST.AdvanceTime(1)

    T.eq(leader.KART.LC.raidConfig.relayLootmaster, "1",
        "and it hands that on rather than claiming the raid named nobody")
    T.eq(RaidSim.As(leader, leader.KART.LC.IsLootOwner), false, "so the second hop defers too")
    T.eq(RaidSim.As(lm, lm.KART.LC.IsLootOwner), true, "and the lootmaster keeps the loot flow")
end

-- A restored snapshot must not hold the session prompt back once the raid HAS answered ------------
-- B141 (mutation-run gap, B149): LC.ShowSessionPrompt refuses to ask while
-- `LC.sessionSnapshotPending and not LC.sessionStateKnown` -- a snapshot restored from a reload, and
-- no word from the raid yet on whether that session is still running. Dropping the second half of
-- that guard (leaving only `LC.sessionSnapshotPending`) holds the prompt back for the whole
-- RESTORE_CONFIRM_SECONDS (60s), even once the raid HAS answered -- which is most of what B141 was
-- about: a reloaded lootmaster left unable to be asked to start the next session for the better part
-- of a minute after being told everything there was to know.
do
    local sim = F.NewSplitRaid() -- Bramor hands out the loot, Corvin leads -- the ordinary split
    local back = RaidSim.Reload(sim, "Bramor")
    RaidSim.EnterWorld(sim, "Bramor")

    T.truthy(back.KART.LC.sessionSnapshotPending,
        "the setup: a config was restored from disk, so the snapshot flag is set")

    -- LC_STATE_REQ goes out on join, and the requester is the loot owner itself -- council and the
    -- raid leader answer that one at once (LC.HandleStateRequest), not on the ordinary raider jitter,
    -- so the harness's synchronous group delivery already carries the reply back by the time
    -- RaidSim.EnterWorld returns -- seconds, not the RESTORE_CONFIRM_SECONDS minute the timer
    -- fallback would otherwise need.
    T.eq(back.KART.LC.sessionStateKnown, true, "the raid has already told this client the session state")
    T.eq(back.KART.LC.sessionActive, true, "confirming the same session that was running before")
    T.truthy(back.KART.LC.sessionSnapshotPending,
        "the snapshot flag itself is untouched by that answer -- only its own 60s timer clears it, " ..
        "and nowhere near that much time has passed")

    -- The owner, now that it genuinely knows the session is running, ends it -- the ordinary way any
    -- distribution ends, well under a minute after the reload.
    RaidSim.As(back, function() back.KART.LC.SetSessionActive(false) end)

    RaidSim.As(back, back.KART.LC.ShowSessionPrompt)
    T.truthy(back.KART.LC.sessionPromptFrame and back.KART.LC.sessionPromptFrame:IsShown(),
        "Gap 5 (B141): once the session state has genuinely arrived, the prompt is free to appear " ..
        "right away -- not held back for the rest of the snapshot's minute")
end
