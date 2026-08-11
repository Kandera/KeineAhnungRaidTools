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

-- A refused send is put back on the wire ----------------------------------------------------------
-- 2026-08-05: the lootmaster's own status line read "71 refused, 1578 queued", and the clients that
-- lost an LC_DROP among those 71 spent the evening with items they had never heard of. CTL retries
-- exactly one refusal of its own -- AddonMessageThrottle -- and hands every other result to the
-- callback as "not sent", which used to be the end of the message. ChannelThrottle (8) is the one
-- the raid actually hit.
do
    local sim, lm = F.NewRaid()
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_RESENDPROBE", {}, function() heard = heard + 1 end)
        end)
    end

    sim.sendResult = 8 -- Enum.SendAddonMessageResult.ChannelThrottle -- not a throttle CTL retries
    RaidSim.As(lm, function() lm.KASC:Send("LC_RESENDPROBE", nil, nil, { guaranteed = true }) end)
    T.eq(heard, 0, "the refused announcement reaches nobody on the first attempt")

    -- The pipe recovers before the first retry falls due. Nobody re-sends by hand.
    sim.sendResult = nil
    KARTTEST.AdvanceTime(1)
    T.eq(heard, #sim.clients - 1, "and the library's own retry delivers it to everybody but the sender")
end

-- ...but only the messages whose loss costs something ----------------------------------------------
-- A heartbeat or a state request that fails has been overtaken by the next one before any retry
-- would land, and re-sending it adds traffic to the pipe that just refused it.
do
    local sim, lm = F.NewRaid()
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_CHEAPPROBE", {}, function() heard = heard + 1 end)
        end)
    end

    sim.sendResult = 8
    RaidSim.As(lm, function() lm.KASC:Send("LC_CHEAPPROBE") end)
    sim.sendResult = nil
    KARTTEST.AdvanceTime(8)
    T.eq(heard, 0, "a message that was not worth guaranteeing is not re-sent either")
end

-- A client that cannot send at all gives up, and says so -------------------------------------------
-- The retry is bounded on purpose: an evening spent re-sending into a pipe that never opens is worse
-- than one lost message, and the count is what tells the difference afterwards.
do
    local sim, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()
    local gaveUpBefore, retriedBefore = diag.sendGaveUp, diag.sendRetried

    sim.sendResult = 8
    RaidSim.As(lm, function() lm.KASC:Send("LC_DEADPROBE", nil, nil, { guaranteed = true }) end)
    KARTTEST.AdvanceTime(10)
    sim.sendResult = nil

    T.eq(diag.sendRetried, retriedBefore + 3, "three attempts follow the first refusal")
    T.eq(diag.sendGaveUp, gaveUpBefore + 1, "and the message is counted as lost exactly once, not per attempt")
end

-- Priority: an End Round does not queue behind a handshake storm ------------------------------------
-- 2026-08-03: one version check answered by twenty clients filled the pipe, and the loot flow was
-- behind it. ChatThrottleLib hands each priority an equal share of the bandwidth, so ALERT traffic
-- gets through a BULK backlog instead of waiting it out.
do
    local sim, lm = F.NewRaid()

    -- Squeeze the pipe shut, so everything below has to queue and the order of the queue is what is
    -- actually being measured.
    for _, c in ipairs(sim.clients) do c.CTL.avail = 0 end

    -- Both sides go out through the calls the addon really uses, priorities included -- a test that
    -- passed the priority in itself would be asserting about its own argument, not about the addon.
    RaidSim.As(lm, function()
        for _ = 1, 20 do lm.KASC:AnnounceHello("RAID") end
        lm.KART.LC.SendLC("LC_END_ROUND")
    end)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(0.4)

    local endRound, bulkBefore = nil, 0
    for i, e in ipairs(sim.log) do
        if e.msg == "LC_END_ROUND" then endRound = i break end
        if e.msg:sub(1, 8) == "KA_HELLO" then bulkBefore = bulkBefore + 1 end
    end
    T.truthy(endRound ~= nil, "the End Round leaves while the handshake backlog is still draining")
    T.truthy(bulkBefore < 20, "and does not wait for all twenty of them")
end

-- Priority: the tally does not queue behind a reload wave ------------------------------------------
-- The same shape as the test above, found the same way and one storm further along (B173). Everything
-- a state request is answered with is whispered PER ASKER, so a raid that reloads together puts one
-- copy per asker in the loot owner's outbox -- measured at 12.8 KB against 1.1 KB for the same boss on
-- a quiet raid. It shared NORMAL with LC_VOTES, and LC_VOTES is what fills the vote panel on every
-- council seat that is not the owner's: measured, the second seat saw a complete tally 26 seconds
-- after the drop, six seconds after the window it was meant to decide in had closed.
do
    local sim, lm = F.NewRaid()
    for _, c in ipairs(sim.clients) do c.CTL.avail = 0 end

    -- Through the real send path, priorities included -- same reasoning as the test above.
    RaidSim.As(lm, function()
        for i = 1, 20 do
            lm.KART.LC.SendLC("LC_ROLL_CATCHUP:" .. i .. ":20:item:249331", "Alric-TarrenMill")
        end
        lm.KART.LC.SendLC("LC_VOTES:900:@249331:" .. string.rep("x", 40))
    end)
    RaidSim.ClearLog(sim)
    KARTTEST.AdvanceTime(0.4)

    local votes, catchupBefore = nil, 0
    for i, e in ipairs(sim.log) do
        if e.msg:sub(1, 9) == "LC_VOTES:" then votes = i break end
        if e.msg:sub(1, 16) == "LC_ROLL_CATCHUP:" then catchupBefore = catchupBefore + 1 end
    end
    T.truthy(votes ~= nil, "the tally leaves while the reload wave's catch-up is still draining")
    T.truthy(catchupBefore < 20, "and does not wait out all twenty answers")
end

-- Two buffers in a row ------------------------------------------------------------------------
-- What an encounter held back (B128) is released all at once, into a pipe that is narrow at exactly
-- that moment -- loot drops at the END of a boss, which is when everything else is talking too. Held
-- first, queued second, and nothing may fall between the two.
do
    local sim, lm = F.NewRaid()
    local ENCOUNTER, ACTIVE, INACTIVE = 1, 2, 0

    RaidSim.As(lm, function() KARTTEST.SetRestriction(ENCOUNTER, ACTIVE) end)
    RaidSim.ClearLog(sim)
    RaidSim.As(lm, function()
        for i = 1, 8 do lm.KART.LC.SendLC("LC_START:" .. i .. ":20:item:249331") end
    end)
    T.eq(#RaidSim.Sent(sim, "LC_START"), 0, "nothing goes out while the encounter holds the comms")

    -- Everything is released in the same instant, and the pipe is shut.
    for _, c in ipairs(sim.clients) do c.CTL.avail = 0 end
    RaidSim.As(lm, function() KARTTEST.SetRestriction(ENCOUNTER, INACTIVE) end)
    T.truthy(#RaidSim.Sent(sim, "LC_START") < 8, "the release does not force the whole burst out at once")

    KARTTEST.AdvanceTime(3)
    T.eq(#RaidSim.Sent(sim, "LC_START"), 8,
        "and every one of the eight held announcements leaves once the queue drains")
end
