-- NSRT Notes: KASC NT_STATE last-write and no publish-on-hello (raidsim).
local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

do
    local sim, lm, _, raider = F.NewRaid()
    local lead, op = lm, raider

    lead.env.KART_Settings.ntModuleEnabled = true
    op.env.KART_Settings.ntModuleEnabled = true

    -- Operator boots with gen 1 SavedVariables (stale stand).
    op.env.KART_Settings.ntGeneration = 1
    op.env.KART_Settings.ntEditor = "Old-TarrenMill"
    op.env.KART_Settings.ntOperatorName = "Wuusch"
    op.env.KART_Settings.ntMapId = 1
    op.env.KART_Settings.ntDiff = 16
    op.env.KART_Settings.ntCursor = 3470
    op.env.KART_Settings.ntChecksum = "oldchecksum"
    op.env.KART_Settings.ntOrderByInstance = {
        ["1:16"] = { order = { 3470, 3445 }, skipped = { [3445] = true } },
    }
    op.KART.NT.generation = 1

    -- Lead is last writer at gen 2.
    lead.env.KART_Settings.ntGeneration = 2
    lead.env.KART_Settings.ntEditor = "Bramor-TarrenMill"
    lead.env.KART_Settings.ntOperatorName = "Wuusch"
    lead.env.KART_Settings.ntMapId = 1
    lead.env.KART_Settings.ntDiff = 16
    lead.env.KART_Settings.ntCursor = 3470
    lead.env.KART_Settings.ntChecksum = "deadbeef"
    lead.env.KART_Settings.ntOrderByInstance = {
        ["1:16"] = { order = { 3470, 3445 }, skipped = { [3445] = true } },
    }
    lead.KART.NT.generation = 2

    RaidSim.ClearLog(sim)
    RaidSim.As(op, function()
        op.KASC:AnnounceHello()
    end)
    T.eq(#RaidSim.Sent(sim, "NT_STATE:"), 0, "hello does not publish NT_STATE")
    T.eq(op.KART.NT.generation, 1, "hello does not clobber operator gen")

    RaidSim.ClearLog(sim)
    RaidSim.As(lead, function()
        lead.KART.NT.PublishState()
    end)
    T.eq(#RaidSim.Sent(sim, "NT_STATE:"), 1, "lead publishes NT_STATE")
    T.eq(op.KART.NT.generation, 2, "operator applied gen 2")
    T.eq(op.env.KART_Settings.ntGeneration, 2, "operator SV generation updated")
    T.eq(op.env.KART_Settings.ntChecksum, "deadbeef", "operator applied lead checksum")
end
