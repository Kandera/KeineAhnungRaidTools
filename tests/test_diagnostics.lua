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
-- The live API answers every send with Enum.SendAddonMessageResult. Since the transport moved onto
-- ChatThrottleLib the two kinds of refusal have different fates, and the counters have to keep them
-- apart: one the library can retry its way out of (a throttle -- it re-queues and tries again), and
-- one it cannot (NotInGroup and the rest -- that message is simply refused).
do
    local sim, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()

    local before = diag.sendRejected
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    T.eq(diag.sendRejected, before, "a send the client accepts is not counted as rejected")
    T.eq(diag.sendQueued, 0, "and not counted as queued either")

    sim.sendResult = 5 -- NotInGroup: a refusal no retry can fix
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 1, "a refusal the transport cannot fix is counted")

    -- The refusal has to stop the message reaching anybody, not merely label it: a harness that
    -- delivered it anyway would make every recovery test pass for free.
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

    sim.sendResult = 5
    RaidSim.As(lm, function() lm.KASC:Send("LC_DIAGPROBE") end)
    sim.sendResult = nil
    T.eq(heard, delivered, "and a refused message reaches nobody")

    -- The throttle goes LAST, because it leaves the queue blocked: every message this client sends
    -- afterwards waits behind it until the clock lets the retry through, and an assertion about
    -- delivery placed below this would be measuring the blockage rather than what it says it does.
    sim.sendResult = 3 -- AddonMessageThrottle: the transport holds on to this one
    RaidSim.As(lm, function() lm.KASC:Send("LC_PROBE") end)
    sim.sendResult = nil
    T.eq(diag.sendRejected, before + 2, "a throttle is not counted as a refusal")
    T.eq(diag.sendQueued, 1, "it is counted as a wait")
    KARTTEST.AdvanceTime(2)
end

-- A client that answers with nothing at all --------------------------------------------------------
-- "No answer" must never read as "everything failed", or the line in /kart status would accuse the
-- transport on every client that does not return the value. ChatThrottleLib maps a send that returned
-- nothing to Success, and this asserts that KASC agrees rather than counting it as a refusal.
do
    local _, lm = F.NewRaid()
    local diag = lm.KASC:Diagnostics()
    -- Replaced directly rather than through the sim: what is under test is how the transport reads a
    -- client that says nothing, and the sim always answers with a code.
    --
    -- `function() end`, NOT `function() return nil end`, and the difference is real: ChatThrottleLib
    -- takes the LAST returned value and only treats NO returned value as success (its
    -- MapToSendResult). A client that returns an explicit nil is read as a failed send. What is being
    -- modelled here is the client that answers nothing at all, which is the one that exists.
    local realSend = _G.C_ChatInfo.SendAddonMessage
    _G.C_ChatInfo.SendAddonMessage = function() end
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

-- ...but an item this client had and has let go of is NOT the same finding ---------------------------
-- One client went from 2 to 181 of these in seven minutes on 2026-08-05 while holding no rolls at
-- all, and every one was a raider voting on an item it had already finished with -- twenty senders
-- times however many the boss dropped, which is ordinary traffic. It buried the counter that had
-- found the message loss the night before. LC.rollLootedAt tells the two apart: it is stamped by
-- every path that tracks a roll and deliberately outlives the roll itself.
do
    local sim, _, council = F.NewRaid()
    local lc = council.KART.LC
    local voter = sim.byName.Merrit

    F.Drop(sim, 96, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.truthy(lc.rollItems[96], "the council member had the item")

    -- Its time runs out and the roll is released, exactly as an evening does it.
    RaidSim.As(council, function() lc.Trade.ClearRollState(96) end)
    T.eq(lc.rollItems[96], nil, "and has let it go")

    local unknownBefore, staleBefore = lc.diag.unknownRoll, lc.diag.staleRoll
    RaidSim.As(council, function() lc.Vote.HandleVote("96:2:#6:@:", voter.guid) end)
    T.eq(lc.diag.staleRoll, staleBefore + 1, "a late vote for it counts as stale, not as unknown")
    T.eq(lc.diag.unknownRoll, unknownBefore,
        "so the counter that means 'the message never reached me' stays readable")
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

    -- The packed-block refusal is on the same list and on the same terms. It has its own line rather
    -- than a slot in the refusal line above because it is the one refusal that costs a whole boss at
    -- once, and because it names a cause none of the others do -- another addon's LibDeflate.
    lm.KART.LC.diag.packedUnreadable = 3
    local unreadable = Capture(function() RaidSim.As(lm, lm.KART.LC.PrintStatus) end)
    lm.KART.LC.diag.packedUnreadable = 0

    T.eq(Lines(unreadable), Lines(clean) + 1, "a client that could not unpack something says so")
    T.truthy(unreadable:find("3", 1, true), "with the count, like every other counter here")
end

-- Addon restrictions ---------------------------------------------------------------------------------
-- Midnight stops addon messages while an encounter or a Mythic+ run is active. Loot drops at the END
-- of an encounter, so this is not a corner case for a loot addon -- it is the exact window every roll
-- announcement goes out in. A message lost there is not delayed, it is gone (B118, B128).
do
    local sim, lm = F.NewRaid()
    local ENCOUNTER, ACTIVE, INACTIVE = 1, 2, 0

    RaidSim.As(lm, function() KARTTEST.SetRestriction(ENCOUNTER, ACTIVE) end)
    RaidSim.ClearLog(sim)

    RaidSim.As(lm, function()
        lm.KART.LC.SendLC("LC_START:900:20:item:249331")
        lm.KART.LC.SendLC("LC_TABLE:1:900")
    end)
    T.eq(#RaidSim.Sent(sim, "LC_START"), 0, "an announcement is not sent while comms are restricted")
    T.eq(#RaidSim.Sent(sim, "LC_TABLE"), 0, "and neither is a heartbeat")

    -- Sent twice inside the window, as a retry would be.
    RaidSim.As(lm, function() lm.KART.LC.SendLC("LC_START:900:20:item:249331") end)

    RaidSim.As(lm, function() KARTTEST.SetRestriction(ENCOUNTER, INACTIVE) end)
    T.eq(#RaidSim.Sent(sim, "LC_START"), 1,
        "the announcement goes out once the encounter releases the comms, exactly once")
    T.eq(#RaidSim.Sent(sim, "LC_TABLE"), 0,
        "while the heartbeat is dropped rather than delivered late -- the asker has moved on")

    local diag = lm.KASC:Diagnostics()
    T.truthy(diag.sendHeldBack >= 1, "what was held is counted")
    T.truthy(diag.sendDroppedRestricted >= 1, "and so is what was dropped")
end
