-- The handshake: who answers when, and who asks again for what never arrived.
--
-- B120, from the raid of 2026-08-03. Every council panel in the raid marked nearly every row as "no
-- KART detected" while the whole raid was demonstrably on the current build -- and one manual
-- /kart v cleared it for everybody. So nothing was broken about receiving, parsing or rendering a
-- handshake: the answers had never arrived, and nothing ever asked again.
--
-- Two halves, and both are needed. Answering: one request in a full raid was answered by everybody in
-- the same instant, which is the shape Blizzard's rate limiter drops silently -- the four other
-- responders in KASC have carried a cooldown for exactly this reason, and this one never did. Asking:
-- KART asked once per channel change, i.e. during raid formation, and never again.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- Answering ----------------------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    RaidSim.ClearLog(sim)

    RaidSim.As(lm, function() lm.KASC.Dispatch("KA_HELLO_REQ", "RAID", "Merrit-TarrenMill") end)
    T.eq(#RaidSim.Sent(sim, "KA_HELLO:"), 0,
        "a hello request is not answered in the same instant it arrives")

    KARTTEST.AdvanceTime(3)
    T.eq(#RaidSim.Sent(sim, "KA_HELLO:"), 1, "but it is answered")

    -- A second asker inside the cooldown window. The four broadcast responders would refuse this one,
    -- and refusing it here would be wrong: this answer goes to one client only.
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KASC.Dispatch("KA_HELLO_REQ", "WHISPER", "Corvin-TarrenMill") end)
    KARTTEST.AdvanceTime(3)
    local whispered = RaidSim.Sent(sim, "KA_HELLO:")
    T.eq(#whispered, 1, "a different asker is answered even inside the cooldown")
    T.eq(whispered[1].channel, "WHISPER", "privately, since only they asked")
    T.eq(whispered[1].target, "Corvin-TarrenMill", "and to them")

    -- The same asker again, immediately. This is the case the cooldown is for: a raid forming sends
    -- these in bursts, and one answer already served whoever asked.
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function() lm.KASC.Dispatch("KA_HELLO_REQ", "WHISPER", "Corvin-TarrenMill") end)
    KARTTEST.AdvanceTime(3)
    T.eq(#RaidSim.Sent(sim, "KA_HELLO:"), 0, "the same asker twice in a row is answered once")
end

-- Asking again ---------------------------------------------------------------------------------------
local function Requests(sim)
    return RaidSim.Sent(sim, "KA_HELLO_REQ")
end

do
    local sim, lm = F.NewRaid()

    -- Everybody accounted for. This is the state a working evening is in almost all of the time, and
    -- it is what makes hanging this on the roster event affordable at all.
    lm.KART.PlayerVersions = {}
    for _, c in ipairs(sim.clients) do
        if c ~= lm then lm.KART.PlayerVersions[c.name] = "3.3.1" end
    end
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, lm.KART.RequestMissingHellos)
    T.eq(#Requests(sim), 0, "a client that knows everybody asks nothing")

    -- Two missing. Nobody else in the raid is asked to answer, and nobody else has to hear about it.
    lm.KART.PlayerVersions.Corvin = nil
    lm.KART.PlayerVersions.Sinja  = nil
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, lm.KART.RequestMissingHellos)
    local reqs = Requests(sim)
    T.eq(#reqs, 2, "a handful missing is one whisper each")
    -- Compared on the character name: a whisper to somebody on our own realm carries no realm, and
    -- one to a foreign realm has to. Which of the two a fixture produces is not what this asserts.
    local asked = {}
    for _, r in ipairs(reqs) do
        T.eq(r.channel, "WHISPER", "sent privately")
        asked[tostring(r.target):match("^([^%-]+)")] = true
    end
    T.truthy(asked.Corvin and asked.Sinja,
        "to exactly the people whose handshake is missing")
end

-- A raid where nobody is known yet -------------------------------------------------------------------
-- Formation, or our own reload. Whispering everybody individually here would BE the burst this is
-- trying to survive, so it asks once and lets the answers spread themselves out.
do
    local members = {}
    for i = 1, 8 do
        members[i] = { name = "Probe" .. i, realm = "TarrenMill",
                       guid = "Player-1096-0B1B2C4" .. i, class = "MAGE",
                       leader = (i == 1), locale = "enUS" }
    end
    KARTTEST.realm = "TarrenMill"
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    KARTTEST.solo, KARTTEST.popups = {}, {}
    local sim = RaidSim.New(members)
    RaidSim.Install(sim)
    local me = sim.byName.Probe1

    me.KART.PlayerVersions = {}
    RaidSim.ClearLog(sim)
    RaidSim.As(me, me.KART.RequestMissingHellos)
    local reqs = Requests(sim)
    T.eq(#reqs, 1, "a raid where nobody is known is one broadcast, not one whisper per raider")
    T.eq(reqs[1].channel, "RAID", "to the group")
    T.eq(reqs[1].target, nil, "and to nobody in particular")

    -- The line between the two, and both sides of it. HELLO_WHISPER_MAX is 5: it decides whether
    -- five people get a whisper nobody else sees, or the whole raid hears one request that EVERY
    -- client answers. Nothing stood on the boundary until B177 -- mutating the `>` to `>=` left the
    -- suite green, so the number was free to drift by one without anything noticing.
    local others = {}
    for _, c in ipairs(sim.clients) do
        if c ~= me then others[#others + 1] = c.name end
    end

    local function KnowAllBut(n)
        me.KART.PlayerVersions = {}
        for i = 1, #others - n do me.KART.PlayerVersions[others[i]] = "3.3.1" end
        RaidSim.ClearLog(sim)
        RaidSim.As(me, me.KART.RequestMissingHellos)
        return Requests(sim)
    end

    T.eq(#KnowAllBut(5), 5, "five missing is still five whispers")
    local six = KnowAllBut(6)
    T.eq(#six, 1, "one more, and it is a single broadcast instead")
    T.eq(six[1].channel, "RAID", "which the whole raid answers -- the reason the line is there")

    -- Never about ourselves: we do not process our own broadcast, so PlayerVersions has no entry for
    -- us by design. Counting it as missing would ask again on every roster change for the rest of the
    -- evening, which is precisely the traffic this is trying not to add.
    me.KART.PlayerVersions = {}
    for _, c in ipairs(sim.clients) do
        if c ~= me then me.KART.PlayerVersions[c.name] = "3.3.1" end
    end
    RaidSim.ClearLog(sim)
    RaidSim.As(me, me.KART.RequestMissingHellos)
    T.eq(#Requests(sim), 0, "our own missing entry is not something to ask anybody about")
end
