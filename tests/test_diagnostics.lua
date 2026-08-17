-- KASC transport diagnostics (4.0: built-in LC /kart status removed).

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local OUTSIDER = "Nobody-Elsewhere"

do
    local sim, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    local before = diag.sendRejected
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    T.eq(diag.sendRejected, before, "a send the client accepts is not counted as rejected")
    T.eq(diag.sendQueued, 0, "and not counted as queued either")

    sim.sendResult = 5
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 1, "a refusal the transport cannot fix is counted")

    local heard = 0
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function()
            c.KASC:RegisterMessage("LC_DIAGPROBE", {}, function() heard = heard + 1 end)
        end)
    end
    RaidSim.As(lm, function() lm.KASC:Send("LC_DIAGPROBE") end)
    local delivered = heard
    T.truthy(delivered > 0, "the probe reaches the raid when the client accepts it")

    sim.sendResult = 5
    RaidSim.As(lm, function() lm.KASC:Send("LC_DIAGPROBE") end)
    sim.sendResult = nil
    T.eq(heard, delivered, "and a refused message reaches nobody")

    sim.sendResult = 3
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 2, "a throttle is not counted as a refusal")
    T.eq(diag.sendQueued, 1, "it is counted as a wait")
    KARTTEST.AdvanceTime(2)
end

do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    local before = diag.sentByToken.LC_TOKENPROBE or 0
    RaidSim.As(lm, function() lm.KASC:Send("LC_TOKENPROBE:payload") end)
    RaidSim.As(lm, function() lm.KASC:Send("LC_TOKENPROBE:other") end)
    T.eq(diag.sentByToken.LC_TOKENPROBE, before + 2, "two sends under one token count twice")

    RaidSim.As(lm, function()
        lm.KASC:OnRestrictionChanged(1, 2)
        lm.KASC:Send("LC_TOKENPROBE:during")
        lm.KASC:OnRestrictionChanged(1, 0)
    end)
    T.eq(diag.sentByToken.LC_TOKENPROBE, before + 2,
        "a send the restriction gate dropped counts as no message on the wire")

    RaidSim.As(lm, function()
        lm.KASC.diag.sentByToken = nil
        lm.KASC:Send("LC_TOKENPROBE:after-upgrade")
    end)
    T.eq(lm.KASC:Diagnostics().sentByToken.LC_TOKENPROBE, 1,
        "a diag table inherited from an older minor grows the counter instead of erroring the send")
end

do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()
    local realSend = _G.C_ChatInfo.SendAddonMessage
    _G.C_ChatInfo.SendAddonMessage = function() end
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    _G.C_ChatInfo.SendAddonMessage = realSend
    T.eq(diag.sendRejected, 0, "a client that returns nothing is not treated as a refusal")
end

do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    RaidSim.As(lm, function() lm.KASC.Dispatch("LC_NO_SUCH_TOKEN:1", "RAID", OUTSIDER) end)
    T.eq(diag.dropUnknownToken, 1, "a token this client has no handler for is counted, not just dropped")

    RaidSim.As(lm, function()
        lm.KASC:RegisterMessage("DIAG_GROUPPROBE", { payload = true, group = true }, function() end)
        lm.KASC.Dispatch("DIAG_GROUPPROBE:1", "WHISPER", OUTSIDER)
    end)
    T.eq(diag.dropNotInGroup, 1, "and so is a group-scoped message from somebody outside the group")
    T.eq(diag.dropUnknownToken, 1, "each drop counts once, against its own reason")
end
