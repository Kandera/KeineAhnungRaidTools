-- A sender the client cannot place, and the second guard that exists for them.
--
-- Six loot handlers open with the same line -- `if not (senderKey and FindUnitForKey(senderKey))
-- then return end` -- and a systematic mutation run over the loot core found that all six survive
-- having it switched off. Nothing held them.
--
-- The first attempt at a test for it was wrong in a way worth recording: it sent from somebody who
-- had left the raid, and passed -- but it passed on KASC's own filter (`entry.group` ->
-- KAUtil.IsFullNameInGroup), one layer earlier, which was already held by
-- tests/test_kasc_responders.lua. The messages never reached the handlers at all, and every one of
-- the six mutants still survived.
--
-- The two layers do not ask the same question. KASC compares the sender's NAME against the roster.
-- The handler asks whether the resolved KEY belongs to anybody currently here. There is exactly one
-- state where those disagree, and the identity code is written around it: a group member whose
-- UnitGUID is momentarily nil during a loading screen. KASC lets them through on the name;
-- KASC.Identity.ResolvePlayer cannot produce a GUID for them, so it answers with pending TEXT --
-- and the handler guard is the only thing standing between that text and the raid's loot state.
--
-- Without it a vote lands under a key like "sinja" instead of a GUID, on the panel that hands out
-- the item, belonging to nobody the council row can resolve; and a raid config arrives from a
-- sender whose identity was never established.

local KAUtil = LibStub("KAUtil-1.0")
local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- A raid where one member is mid-loading-screen: still on the roster, still answering UnitName, no
-- GUID. The cache is cleared with them, since a cached entry would resolve them by their old GUID
-- and close the gap this file is about.
local function RaidWithUnresolvable()
    local sim, lm, council = F.NewRaid()
    local ghost = sim.byName.Sinja
    KARTTEST.guidBlackout = { [ghost.unit] = true }
    for _, c in ipairs(sim.clients) do c.env.KART_PlayerCache = {} end
    return sim, lm, council, ghost
end

local function Send(client, msg)
    RaidSim.As(client, function() client.KASC:Send(msg, "RAID") end)
    KARTTEST.AdvanceTime(0)
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- It reaches the handler at all ---------------------------------------------------------------------
-- If KASC dropped this the way it drops an out-of-group sender, everything below would pass against
-- a handler that never runs -- which is exactly how the first version of this file fooled itself.
do
    local _, _, council, ghost = RaidWithUnresolvable()
    local Identity = council.KASC.Identity
    local key, pending = RaidSim.As(council, function()
        return Identity.ResolvePlayer(ghost.name .. "-" .. ghost.realm)
    end)
    T.truthy(pending, "the sender cannot be resolved to anybody while their GUID is missing")
    T.truthy(not RaidSim.As(council, function() return Identity.FindUnitForKey(key) end),
        "and the key they resolve to belongs to no unit in the group")
    T.truthy(RaidSim.As(council, function()
        return KAUtil.IsFullNameInGroup(ghost.name .. "-" .. ghost.realm)
    end), "while KASC's own filter still sees them as a group member -- which is the gap")
    KARTTEST.guidBlackout = {}
end

-- A vote from them ------------------------------------------------------------------------------------
do
    local sim, _, council, ghost = RaidWithUnresolvable()
    F.Drop(sim, 120, F.GLOVES)
    KARTTEST.AdvanceTime(0)
    local before = Count(council.KART.LC.votes[120])

    Send(ghost, "LC_VOTE:120:1:#3:@" .. F.GLOVES .. ":brauche ich")
    T.eq(Count(council.KART.LC.votes[120]), before,
        "a vote from a sender who resolves to nobody is not recorded")
    T.eq((council.KART.LC.votes[120] or {})["sinja"], nil,
        "and certainly not under the plain text their name folded down to")
    KARTTEST.guidBlackout = {}
end

-- A roll table from them -------------------------------------------------------------------------------
do
    local sim, _, council, ghost = RaidWithUnresolvable()
    F.Drop(sim, 121, F.GLOVES)
    KARTTEST.AdvanceTime(0)
    local before = Count(council.KART.LC.rolls[121])

    Send(ghost, "LC_ROLLS:121:@" .. F.GLOVES .. ":" .. ghost.guid .. "=97")
    T.eq(Count(council.KART.LC.rolls[121]), before, "nor does their table replace the tally")
    KARTTEST.guidBlackout = {}
end

-- A council pick from them --------------------------------------------------------------------------
do
    local sim, _, council, ghost = RaidWithUnresolvable()
    F.Drop(sim, 122, F.GLOVES)
    KARTTEST.AdvanceTime(0)
    local alric = sim.byName.Alric

    Send(ghost, "LC_CVOTE:122:@" .. F.GLOVES .. ":" .. alric.guid)
    T.eq(Count(council.KART.LC.councilVotes[122]), 0,
        "nor is their council pick recorded against the item")
    KARTTEST.guidBlackout = {}
end

-- The raid's settings from them ------------------------------------------------------------------------
do
    local _, _, council, ghost = RaidWithUnresolvable()
    local before = RaidSim.As(council, council.KART.LC.GetButtonConfig)
    local beforeQ = council.KART.LC.raidConfig.minQuality

    Send(ghost, "LC_CONFIG:0:Alles;Nix:1:Sinja:Sinja")
    local after = RaidSim.As(council, council.KART.LC.GetButtonConfig)
    T.eq(#after, #before, "and the raid's vote buttons are not theirs to set")
    T.eq(council.KART.LC.raidConfig.minQuality, beforeQ, "nor its minimum quality")
    KARTTEST.guidBlackout = {}
end

-- ...and the same messages from a raider the client CAN place still work --------------------------
-- Without this every assertion above would pass just as happily against a handler that refuses
-- everything, which is the failure mode a guard test has to rule out.
do
    local sim, lm, council = F.NewRaid()
    F.Drop(sim, 123, F.GLOVES)
    KARTTEST.AdvanceTime(0)
    local alric = sim.byName.Alric
    local fp = tostring(RaidSim.As(council, council.KART.LC.ButtonFingerprint))

    Send(alric, "LC_VOTE:123:1:#" .. fp .. ":@" .. F.GLOVES .. ":brauche ich")
    local v = (council.KART.LC.votes[123] or {})[alric.guid]
    T.truthy(v, "a raider the client can resolve has their vote counted")
    T.eq(v and v.idx, 1, "under the answer they clicked")

    -- The roll table only ever comes from the loot owner (lm here), unlike a vote -- so this is sent
    -- from them rather than from Alric, and still checked against the same "a resolvable sender still
    -- gets through" question the rest of this block asks.
    Send(lm, "LC_ROLLS:123:@" .. F.GLOVES .. ":" .. lm.guid .. "=97")
    T.eq((council.KART.LC.rolls[123] or {})[lm.guid], 97, "and their roll table joins the tally")
end

KARTTEST.guidBlackout = {}
