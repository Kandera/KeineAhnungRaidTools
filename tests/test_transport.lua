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
