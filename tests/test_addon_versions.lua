-- Neighbor-addon versions: HELLO extras, BuffChecker glyphs, raid-lead nag.
--
-- KART already warns from a peer HELLO when our own build is behind. These tests pin the same
-- comparison for RCLootCouncil / NSRT / wowutils, gated on the addon actually being loaded so a
-- KART-only user is never told to update something they do not run.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local function WipeAddonStubs()
    wipe(KARTTEST.loadedAddons)
    wipe(KARTTEST.addonVersions)
end

local function AddonRow(kart, folder)
    for _, d in ipairs(kart.BuffData) do
        if d.isAddonCheck == folder then return d end
    end
end

-- Cell status vs our local version --------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    local S = lm.KART.AddonCellStatus

    T.eq(S(nil, "3.23.2", false), "unknown", "no HELLO yet is unknown, not 'not installed'")
    T.eq(S(nil, "3.23.2", true), "missing", "HELLO without the addon is not installed")
    T.eq(S("3.22.0", "3.23.2", true), "old", "older than us is out of date")
    T.eq(S("3.23.2", "3.23.2", true), "ok", "matching us is current")
    T.eq(S("3.24.0", "3.23.2", true), "ok", "newer than us is still current")
    T.eq(S("3.23.2", nil, true), "ok", "we do not have it, so we cannot mark them outdated")
    T.eq(S("12.1.13-3-g56c3a5a", "12.1.13", true), "ok",
        "an NSRT git suffix compares as the same 12.1.13")
    T.eq(S("12.1.12-9-gdeadbee", "12.1.13", true), "old",
        "an older NSRT major.minor.patch is out of date even with a git suffix")
end

-- Wire sanitise / local read --------------------------------------------------------------------
do
    local _, lm = F.NewRaid()
    T.eq(lm.KART.SanitizeWireVersion("1.0.6"), "1.0.6", "a plain version is kept")
    T.eq(lm.KART.SanitizeWireVersion("12.1.13-3-g56c3a5a"), "12.1.13-3-g56c3a5a",
        "NSRT git-describe is already wire-legal")
    T.eq(lm.KART.SanitizeWireVersion("1.0.6 (beta)"), "1.0.6",
        "a parenthetical suffix is stripped at the first illegal character")
    T.is_nil(lm.KART.SanitizeWireVersion(""), "an empty version is refused")
    T.is_nil(lm.KART.SanitizeWireVersion(nil), "nil is refused")

    WipeAddonStubs()
    T.is_nil(lm.KART.NeighborVersion("wowutils"), "a missing neighbor has no version")
    KARTTEST.loadedAddons.wowutils = true
    KARTTEST.addonVersions.wowutils = "1.0.6"
    T.eq(lm.KART.NeighborVersion("wowutils"), "1.0.6", "a loaded neighbor's toc version is read")
    WipeAddonStubs()
end

-- HELLO carries only loaded neighbors -----------------------------------------------------------
do
    WipeAddonStubs()
    local _, lm = F.NewRaid()
    local parsed = lm.KASC.ParseHello(lm.KASC.SerializeHello())
    T.truthy(parsed.KART, "KART is always on the hello")
    T.is_nil(parsed.RCLootCouncil, "RC is absent from hello when it is not loaded")
    T.is_nil(parsed.NorthernSkyRaidTools, "NSRT is absent from hello when it is not loaded")
    T.is_nil(parsed.wowutils, "wowutils is absent from hello when it is not loaded")

    KARTTEST.loadedAddons.RCLootCouncil = true
    KARTTEST.addonVersions.RCLootCouncil = "3.23.2"
    KARTTEST.loadedAddons.wowutils = true
    KARTTEST.addonVersions.wowutils = "1.0.6"
    RaidSim.As(lm, function() lm.KART.RegisterNeighborAddons() end)
    parsed = lm.KASC.ParseHello(lm.KASC.SerializeHello())
    T.eq(parsed.RCLootCouncil and parsed.RCLootCouncil.version, "3.23.2",
        "a loaded RC is announced")
    T.eq(parsed.wowutils and parsed.wowutils.version, "1.0.6",
        "a loaded wowutils is announced")
    T.is_nil(parsed.NorthernSkyRaidTools, "an unloaded NSRT is still not announced")
    WipeAddonStubs()
end

-- OutdatedAgainst: our versions vs a lead snapshot ---------------------------------------------
do
    local _, lm = F.NewRaid()
    local localVers = { KART = "4.0.0", RCLootCouncil = "3.22.0", wowutils = "1.0.6" }
    local lead = {
        KART = { version = "4.0.1" },
        RCLootCouncil = { version = "3.23.2" },
        wowutils = { version = "1.0.6" },
        NorthernSkyRaidTools = { version = "12.1.13" },
    }
    local out = lm.KART.OutdatedAgainst(localVers, lead)
    local names = {}
    for _, e in ipairs(out) do names[#names + 1] = e.name end
    T.deep_eq(names, { "KART", "RCLootCouncil" },
        "only addons we have, that are older than the lead, are outdated")
    T.is_nil((function()
        for _, e in ipairs(out) do if e.name == "wowutils" then return e end end
    end)(), "matching the lead is not outdated")
    T.is_nil((function()
        for _, e in ipairs(out) do if e.name == "NorthernSkyRaidTools" then return e end end
    end)(), "an addon we do not have is not in the nag list")
end

-- Presence-gated passive warn -------------------------------------------------------------------
do
    WipeAddonStubs()
    local _, lm = F.NewRaid()
    local printed = {}
    local oldPrint = print
    _G.print = function(msg) printed[#printed + 1] = tostring(msg) end

    RaidSim.As(lm, function()
        lm.KASC.Dispatch("KA_HELLO:KART=4.0.1,RCLootCouncil=3.23.2,wowutils=1.0.7",
            "RAID", "Alric-TarrenMill")
    end)
    _G.print = oldPrint
    local joined = table.concat(printed, "\n")
    T.eq(joined:find("wowutils", 1, true) or joined:find("WowUtils", 1, true), nil,
        "a wowutils version on the wire does not warn us when we do not have wowutils")
    T.eq(joined:find("RCLootCouncil", 1, true), nil,
        "same for RC")

    T.eq(lm.KART.PlayerVersions.Alric, "4.0.1", "a hello still records the KART version")
    T.eq(lm.KART.PlayerAddonVersions.Alric.wowutils, "1.0.7",
        "and keeps the neighbor version for the BuffChecker")

    KARTTEST.loadedAddons.wowutils = true
    KARTTEST.addonVersions.wowutils = "1.0.6"
    RaidSim.As(lm, function() lm.KART.RegisterNeighborAddons() end)
    printed = {}
    _G.print = function(msg) printed[#printed + 1] = tostring(msg) end
    RaidSim.As(lm, function()
        lm.KASC.Dispatch("KA_HELLO:KART=4.0.1,wowutils=1.0.7", "RAID", "Alric-TarrenMill")
    end)
    -- same peer again should not warn a second time
    RaidSim.As(lm, function()
        lm.KASC.Dispatch("KA_HELLO:KART=4.0.1,wowutils=1.0.8", "RAID", "Merrit-TarrenMill")
    end)
    _G.print = oldPrint
    T.eq(#printed, 1, "a loaded wowutils behind a peer warns once per session")
    T.truthy(printed[1]:find("1.0.7", 1, true) and printed[1]:find("1.0.6", 1, true),
        "naming the newer peer version and ours")
    WipeAddonStubs()
end

-- Raid-lead nag ---------------------------------------------------------------------------------
do
    WipeAddonStubs()
    KARTTEST.loadedAddons.RCLootCouncil = true
    KARTTEST.addonVersions.RCLootCouncil = "3.23.2"
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    RaidSim.As(lm, function() lm.KART.RegisterNeighborAddons() end)

    -- Alric is on an older RC; give him that version locally when the nag arrives.
    RaidSim.ClearLog(sim)
    RaidSim.As(alric, function()
        alric.KART.BroadcastAddonNag()
    end)
    T.eq(#RaidSim.Sent(sim, "ADDON_NAG:"), 0, "a non-lead does not broadcast the nag")

    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KART.BroadcastAddonNag() end)
    T.eq(#RaidSim.Sent(sim, "ADDON_NAG:"), 1, "the raid lead broadcasts one nag")

    -- Recipients: Alric behind on RC, Sinja current (same loadedAddons/version stubs as the lead
    -- unless we change them around the dispatch). Set Alric's local RC older, then deliver.
    KARTTEST.addonVersions.RCLootCouncil = "3.22.0"
    RaidSim.As(alric, function()
        alric.KART.RegisterNeighborAddons()
        alric.KART.addonUpdatePopup = nil
        alric.KASC.Dispatch("ADDON_NAG:KART=4.0.1,RCLootCouncil=3.23.2", "RAID", "Bramor-TarrenMill")
    end)
    T.truthy(alric.KART.addonUpdatePopup and alric.KART.addonUpdatePopup:IsShown(),
        "a raider behind the lead gets the update window")

    KARTTEST.addonVersions.RCLootCouncil = "3.23.2"
    RaidSim.As(sim.byName.Sinja, function()
        sim.byName.Sinja.KART.RegisterNeighborAddons()
        sim.byName.Sinja.KART.addonUpdatePopup = nil
        sim.byName.Sinja.KASC.Dispatch("ADDON_NAG:KART=4.0.1,RCLootCouncil=3.23.2",
            "RAID", "Bramor-TarrenMill")
    end)
    T.eq(not not (sim.byName.Sinja.KART.addonUpdatePopup
            and sim.byName.Sinja.KART.addonUpdatePopup:IsShown()),
        false, "a raider on the lead's versions does not get a window")

    -- A non-lead spoofing the token is ignored.
    KARTTEST.addonVersions.RCLootCouncil = "3.22.0"
    RaidSim.As(alric, function()
        if alric.KART.addonUpdatePopup then alric.KART.addonUpdatePopup:Hide() end
        alric.KASC.Dispatch("ADDON_NAG:KART=4.0.1,RCLootCouncil=3.23.2", "RAID", "Merrit-TarrenMill")
    end)
    T.eq(not not (alric.KART.addonUpdatePopup and alric.KART.addonUpdatePopup:IsShown()),
        false, "a nag from someone who is not the lead is ignored")
    WipeAddonStubs()
end

-- BuffChecker Advanced columns ------------------------------------------------------------------
do
    WipeAddonStubs()
    KARTTEST.loadedAddons.RCLootCouncil = true
    KARTTEST.addonVersions.RCLootCouncil = "3.23.2"
    local _, lm = F.NewRaid()
    T.truthy(AddonRow(lm.KART, "RCLootCouncil"), "RC has an advanced BuffChecker column")
    T.truthy(AddonRow(lm.KART, "NorthernSkyRaidTools"), "NSRT has an advanced BuffChecker column")
    T.truthy(AddonRow(lm.KART, "wowutils"), "wowutils has an advanced BuffChecker column")
    T.eq(AddonRow(lm.KART, "RCLootCouncil").page, "advanced", "and they live on the advanced page")

    lm.KART.PlayerVersions = {
        Alric = "4.0.1",
        Merrit = "4.0.1",
        -- Corvin: no hello
    }
    lm.KART.PlayerAddonVersions = {
        Alric = { KART = "4.0.1", RCLootCouncil = "3.22.0" },
        Merrit = { KART = "4.0.1" },
    }
    local byName = {}
    RaidSim.As(lm, function()
        local snap = lm.KART.ScanBuffRoster()
        for _, p in ipairs(snap.players) do byName[p.shortName] = p end
    end)
    local rcId = AddonRow(lm.KART, "RCLootCouncil").id
    T.eq(byName.Alric.states[rcId], "old", "Alric's older RC is a red cross")
    T.eq(byName.Merrit.states[rcId], "missing", "Merrit's HELLO without RC is a dash")
    T.eq(byName.Corvin.states[rcId], "unknown", "Corvin with no HELLO is a question mark")
    T.eq(byName.Bramor.states[rcId], "ok", "our own loaded RC is current against ourselves")
    WipeAddonStubs()
end
