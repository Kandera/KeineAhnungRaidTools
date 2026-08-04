-- The transport underneath KASC: ChatThrottleLib's queue and AceComm's multipart assembly.
--
-- These assert about the harness as much as about the libraries, and that is the point. CTL despools
-- from an OnUpdate this harness has no frames to drive, and AceComm reassembles anything over 255
-- bytes in an event handler nothing here fires -- so a suite that never drove either would report a
-- working transport while nothing moved at all.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- A payload longer than one addon message ------------------------------------------------------
-- 255 bytes is the transport's hard cap, and the whole reason AceComm is bundled rather than just
-- ChatThrottleLib: the roll table and the per-boss message will both exceed it.
do
    local sim, lm = F.NewRaid()
    local peer = sim.byName.Merrit

    local got
    RaidSim.As(peer, function()
        peer.AceComm.RegisterComm(peer, "KARTPROBE", function(_, message)
            got = message
        end)
    end)

    local long = string.rep("x", 600)
    RaidSim.As(lm, function()
        lm.AceComm:SendCommMessage("KARTPROBE", long, "RAID")
    end)
    KARTTEST.AdvanceTime(1)

    T.eq(type(got), "string", "a 600-byte payload arrives at the peer at all")
    T.eq(got and #got or 0, 600, "and arrives whole, not as the first 255 bytes")
end

-- A throttled send is retried, not lost -----------------------------------------------------------
-- 2026-08-03: the client answered AddonMessageThrottle and KASC dropped the message on the floor.
-- Nothing retried, so an End Round that lost this race was simply never said. ChatThrottleLib moves
-- the queue into its blocked ring instead and tries again a third of a second later.
do
    local sim, lm = F.NewRaid()
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_THROTTLEPROBE", {}, function() heard = heard + 1 end)
        end)
    end

    -- The client refuses everything, exactly as it does when the rate limiter is unhappy.
    sim.sendResult = 3 -- Enum.SendAddonMessageResult.AddonMessageThrottle
    RaidSim.As(lm, function() lm.KASC:Send("LC_THROTTLEPROBE") end)
    KARTTEST.AdvanceTime(1)
    T.eq(heard, 0, "while the client refuses, the message does not reach anybody")

    -- The rate limiter lets go. Nobody re-sends anything: the retry is the library's job.
    sim.sendResult = nil
    KARTTEST.AdvanceTime(2)
    T.truthy(heard > 0, "and once it lets go, the message arrives without anybody re-sending it")
    T.eq(heard, #sim.clients - 1, "exactly once, at everybody but the sender")
end

-- What the counters say now ------------------------------------------------------------------------
-- sendThrottled is gone: CTL never tells the caller it throttled, it just re-queues. What a raid can
-- still be asked is whether a message went out at once or had to wait, which is what the question
-- "was there too much traffic" actually reduces to.
do
    local sim, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()
    local before = diag.sendQueued

    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    T.eq(diag.sendQueued, before, "a message that goes straight out is not counted as queued")

    sim.sendResult = 3
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendQueued, before + 1, "one that has to wait is")
    T.eq(diag.sendRejected, 0, "and a throttle is not a rejection any more -- it is a delay")
    KARTTEST.AdvanceTime(2)
end
