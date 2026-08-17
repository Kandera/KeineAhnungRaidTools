-- The transport underneath KASC: ChatThrottleLib's queue and AceComm's multipart assembly.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

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

do
    local sim, lm = F.NewRaid()
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_THROTTLEPROBE", {}, function() heard = heard + 1 end)
        end)
    end

    sim.sendResult = 3
    RaidSim.As(lm, function() lm.KASC:Send("LC_THROTTLEPROBE") end)
    KARTTEST.AdvanceTime(1)
    T.eq(heard, 0, "while the client refuses, the message does not reach anybody")

    sim.sendResult = nil
    KARTTEST.AdvanceTime(2)
    T.truthy(heard > 0, "and once it lets go, the message arrives without anybody re-sending it")
    T.eq(heard, #sim.clients - 1, "exactly once, at everybody but the sender")
end

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

do
    local sim, lm = F.NewRaid()
    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_RESENDPROBE", {}, function() heard = heard + 1 end)
        end)
    end

    sim.sendResult = 8
    RaidSim.As(lm, function() lm.KASC:Send("LC_RESENDPROBE", nil, nil, { guaranteed = true }) end)
    T.eq(heard, 0, "the refused announcement reaches nobody on the first attempt")

    sim.sendResult = nil
    KARTTEST.AdvanceTime(1)
    T.eq(heard, #sim.clients - 1, "and the library's own retry delivers it to everybody but the sender")
end

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
