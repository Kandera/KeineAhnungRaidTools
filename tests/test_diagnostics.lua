-- What this client refused, and what its own sends were refused for.
--
-- Written after the raid of 2026-08-03, where four different messages went missing -- an End Round,
-- two roll announcements and four votes -- and not one client anywhere said so (B118, B120). Every
-- loss looked like a different bug on a different screen. These counters do not fix that; they make
-- the NEXT raid able to say which of the causes it was, which is the part that was missing.
--
-- Three causes have to stay distinguishable, because their fixes are unrelated:
--   * this client refused the message      -> a guard is wrong, or an identity did not resolve
--   * this client never recognised it      -> the peer is on a protocol this one does not have
--   * our own send never left the client   -> Blizzard's rate limiter, and a send queue is the answer
-- All counters at zero while a raider is missing an item is itself the answer: the message was never
-- delivered at all, which is nothing a guard change can reach and needs the catch-up instead.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local STRANGER = "Player-4711-DEADBEEF"
local OUTSIDER = "Nobody-Elsewhere"

local function Capture(fn)
    local realPrint = _G.print
    local lines = {}
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

-- The send side ------------------------------------------------------------------------------------
-- The live API answers every send with Enum.SendAddonMessageResult and KASC threw it away, so a
-- message the client REFUSED TO SEND was indistinguishable from one that was sent and ignored.
do
    local sim, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    local before = diag.sendRejected
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    T.eq(diag.sendRejected, before, "a send the client accepts is not counted as rejected")

    sim.sendResult = 3 -- AddonMessageThrottle
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 1, "a throttled send is counted")
    T.eq(diag.sendThrottled, 1, "and counted again as a throttle specifically")
    T.eq(diag.lastSendResult, 3, "with the code kept, so the reason is readable afterwards")

    sim.sendResult = 8 -- ChannelThrottle, the other one that means "too much traffic"
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendThrottled, 2, "the channel throttle counts as a throttle too")

    sim.sendResult = 5 -- NotInGroup: a refusal, but not a throttle
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 3, "any non-success answer counts as rejected")
    T.eq(diag.sendThrottled, 2, "but only the two throttles count as throttled")

    -- The refusal has to stop the message, not merely label it: a throttled send never reaches a
    -- peer, and a harness that delivers it anyway would make every recovery test pass for free.
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_DIAGPROBE", {}, function() heard = heard + 1 end)
        end)
    end
    -- Sent once WITHOUT the refusal first, or the assertion below would also pass on a probe nobody
    -- was ever listening for.
    RaidSim.As(lm, function() lm.KASC:Send("LC_DIAGPROBE") end)
    local delivered = heard
    T.truthy(delivered > 0, "the probe reaches the raid when the client accepts it")

    sim.sendResult = 3
    RaidSim.As(lm, function() lm.KASC:Send("LC_DIAGPROBE") end)
    sim.sendResult = nil
    T.eq(heard, delivered, "and a refused message reaches nobody")
end

-- A client that answers with nothing at all --------------------------------------------------------
-- Not hypothetical enough to skip: "no answer" must never read as "everything failed", or the line
-- in /kart status would accuse the transport on every client that does not return the value.
do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()
    -- Replaced directly rather than through the sim: what is under test is KASC's own reading of the
    -- return value, and the sim always answers with a code.
    local realSend = _G.C_ChatInfo.SendAddonMessage
    _G.C_ChatInfo.SendAddonMessage = function() return nil end
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    _G.C_ChatInfo.SendAddonMessage = realSend
    T.eq(diag.sendRejected, 0, "a client that returns nothing is not treated as a refusal")
end

-- The receive side, one layer below the addon ------------------------------------------------------
do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    RaidSim.As(lm, function() lm.KASC.Dispatch("LC_NO_SUCH_TOKEN:1", "RAID", OUTSIDER) end)
    T.eq(diag.dropUnknownToken, 1, "a token this client has no handler for is counted, not just dropped")

    RaidSim.As(lm, function() lm.KASC.Dispatch("LC_START:80:20:1", "WHISPER", OUTSIDER) end)
    T.eq(diag.dropNotInGroup, 1, "and so is a message from somebody outside the group")
    T.eq(diag.dropUnknownToken, 1, "each drop counts once, against its own reason")
end

-- The receive side, in the addon's own guards ------------------------------------------------------
do
    local _, lm = F.NewRaid()
    local lc = lm.KART.LC

    local before = lc.diag.refusedSender
    RaidSim.As(lm, function() lc.HandleStart("80:20:1", STRANGER) end)
    T.eq(lc.diag.refusedSender, before + 1, "a roll announcement from a non-owner is counted as refused")

    RaidSim.As(lm, function() lc.HandleEndRound(STRANGER) end)
    T.eq(lc.diag.refusedSender, before + 2, "so is an End Round from somebody who is not council")

    RaidSim.As(lm, function() lc.HandleActive("0", STRANGER) end)
    T.eq(lc.diag.refusedSender, before + 3, "and a session flag from a non-owner")
    T.eq(lc.sessionActive, true, "and the session it tried to end is still running")
end

-- A vote for an item this client has never heard of -------------------------------------------------
-- The council side of B118: the vote arrives, the roll does not exist here, and the tally is short by
-- one with nothing anywhere saying why. Distinct from a refused sender, because the fix is different --
-- this one says the item is missing, not the person.
do
    local sim, _, council = F.NewRaid()
    local lc = council.KART.LC
    local voter = sim.byName.Merrit

    local before = lc.diag.unknownRoll
    RaidSim.As(council, function() lc.Vote.HandleVote("4242:2:#6:@:", voter.guid) end)
    T.eq(lc.diag.unknownRoll, before + 1, "a vote for an untracked roll is counted")
    T.eq(lc.votes[4242], nil, "and still not stored, which is what it was refused for")
end

-- /kart status ---------------------------------------------------------------------------------------
-- The line has to be absent on a clean evening: a raider pastes this output into an issue, and a row
-- of zeroes reads as "something went wrong" to everybody who sees it.
-- Counted by LINES, not by matching the text: this line exists in both locales and asserting an
-- English word would pass or fail on which client the fixture happened to build.
local function Lines(s)
    local n = 0
    for _ in s:gmatch("[^\n]+") do n = n + 1 end
    return n
end

do
    local _, lm = F.NewRaid()
    local clean = Capture(function() RaidSim.As(lm, lm.KART.LC.PrintStatus) end)

    lm.KART.LC.diag.refusedSender = 2
    local dirty = Capture(function() RaidSim.As(lm, lm.KART.LC.PrintStatus) end)
    lm.KART.LC.diag.refusedSender = 0

    T.eq(Lines(dirty), Lines(clean) + 1, "a client that refused something prints one more line")
    T.truthy(dirty:find("2", 1, true), "and the line carries the count, not just the fact")

    local again = Capture(function() RaidSim.As(lm, lm.KART.LC.PrintStatus) end)
    T.eq(Lines(again), Lines(clean), "a client that lost nothing prints no such line at all")
end
