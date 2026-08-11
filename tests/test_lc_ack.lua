-- Paket F: the announcement receipt-ack, and the answer states the council reads off it.
--
-- The hole this is about: a client whose LC_DROP was swallowed while Blizzard DID give it a roll
-- window sits blind. Auto-Pass needs LC.rollAnnounced, only the announcement (or a catch-up) sets it,
-- and the only thing that happens on its own is WaitForAnnouncement PRINTING at ANNOUNCE_WAIT --
-- longer than Blizzard's window, so the item is already lost by then. 2026-08-03 cost a raider an
-- item exactly this way (B118).

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local function PassedBy(sim, rollID, name)
    return (KARTTEST.rolled[rollID] or {})[sim.byName[name].unit]
end

-- One client deaf to the announcement, and to nothing else.
--
-- RaidSim.Blackhole is raid-wide by token, and this needs the OPPOSITE: the rest of the raid has to
-- receive the drop, because their acks are the evidence under test. So the message is stopped at this
-- client's own LC handler instead -- the same place a swallowed message stops, one layer below the
-- transport. Everything KASC does with the message (the group check, the sender key, the self-echo
-- drop) still runs, and every OTHER token still reaches this client, which is the whole point.
local function Deafen(client)
    local real = client.KART.LC.HandleDrop
    client.KART.LC.HandleDrop = function() end
    return function() client.KART.LC.HandleDrop = real end
end

-- The headline: deaf, holding Blizzard's window, repaired while that window is still open ----------
-- Rolls are OFF here, which is the DEFAULT (Utils.lua) and the case with no repair path at all: the
-- table heartbeat's needItem is false (this client has the item from its own roll event) and its
-- needRolls is false too (a raid that does not roll has no table to miss). Nothing else in the addon
-- ever names this roll to this client again.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    RaidSim.ClearLog(sim)
    local restore = Deafen(deaf)
    F.Drop(sim, 940, F.GLOVES)
    T.truthy(deaf.KART.LC.rollItems[940] ~= nil, "Blizzard raised its roll window")
    T.eq(deaf.KART.LC.rollAnnounced[940], nil, "and nothing has told it what the item is for")
    -- One second: the collection window closes, the announcement goes out to everybody else, their
    -- acks are slotted from it, and the repair has to be finished inside that -- Blizzard's window is
    -- what this is racing, not ANNOUNCE_WAIT's forty-five seconds.
    KARTTEST.AdvanceTime(1)
    restore()

    -- It never received the announcement, so the ONLY route to the item is the one it asked for after
    -- overhearing somebody else being told.
    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == deaf.name then asks = asks + 1 end
    end
    T.eq(asks, 1, "it overhears an ack for a roll it has never heard of and asks -- once")
    T.truthy(deaf.KART.LC.rollAnnounced[940], "the owner answers, and the item is properly announced")
    T.eq(PassedBy(sim, 940, "Alric"), 0, "so Auto-Pass finally has both halves, and it passes")
end

-- ...and without the acks it does not, which is what today's raid looks like ------------------------
-- The control for the test above: same client, same silence, the acks lost as well. Nothing else in
-- the addon names this roll to this client, so it holds Blizzard's window until ANNOUNCE_WAIT --
-- which is the state that cost a raider an item on 2026-08-03.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    RaidSim.Blackhole(sim, "LC_ACK")
    local restore = Deafen(deaf)
    F.Drop(sim, 941, F.GLOVES)
    KARTTEST.AdvanceTime(5)
    restore()

    T.eq(deaf.KART.LC.rollAnnounced[941], nil, "with the acks lost too, nothing reaches it")
    -- What it costs this client is the vote row, and only that. Since B174 the roll window is not
    -- part of the damage: the pass runs off the session, so a raider who hears nothing all evening
    -- still never has to click one.
    T.eq(PassedBy(sim, 941, "Alric"), 0, "though the window was still passed for them")
    RaidSim.Deliver(sim, "LC_ACK")
end

-- What a boss costs: one ack per client, for the whole batch ---------------------------------------
-- The number is the point. B120 bundled a boss's items into ONE announcement to quiet the post-boss
-- minute, and an ack per item would have handed most of that back. Against the B135 baseline (1,680
-- messages an evening) one ack per client per boss is about 174 over six bosses -- ten percent more
-- messages, two percent more bytes.
do
    local sim, lm = F.NewRaid()

    RaidSim.ClearLog(sim)
    F.Drop(sim, 950, F.GLOVES)
    F.Drop(sim, 951, F.WEAPON)
    F.Drop(sim, 952, F.PLATE_CHEST)
    KARTTEST.AdvanceTime(3) -- the collection window, then every slot of the ack spread

    local acks = RaidSim.Messages(sim, "LC_ACK")
    T.eq(#RaidSim.Messages(sim, "LC_DROP:"), 1, "the boss travels as one announcement")
    T.eq(#acks, #sim.clients - 1, "and is answered by one ack per client that received it")
    local fromOwner, ids = 0, nil
    for _, e in ipairs(acks) do
        if e.from == lm.name then fromOwner = fromOwner + 1 end
        ids = ids or e.msg:match("^LC_ACK:(.*)$")
    end
    T.eq(fromOwner, 0, "the owner acks nothing -- it is the one client that was never told")
    T.eq(ids, "950,951,952", "and one ack names the whole batch rather than one item")
end

-- The client with no roll of its own is repaired too ------------------------------------------------
-- Dead, released, out of range: no Blizzard window, so nothing local to notice the silence by, and the
-- clients least able to help themselves. The ask is deliberately NOT gated on holding a roll -- who is
-- entitled is decided on the owner (LC.MayCatchUp) from the roster snapshot, not here.
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Alric

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcRollsEnabled = false
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)

    local restore = Deafen(deaf)
    F.Drop(sim, 953, F.GLOVES, { noRollFor = { Alric = true } })
    KARTTEST.AdvanceTime(1)
    restore()

    T.truthy(deaf.KART.LC.rollAnnounced[953],
        "a client with no roll window of its own is caught up off the overheard ack as well")
    T.truthy(deaf.KART.LC.rollItems[953] ~= nil, "and has the item to vote on")
end

-- ...but somebody who joined afterwards is still refused (B118) --------------------------------------
-- The ask is broadcast, and a late arrival hears the same acks. The rule that keeps them out of the
-- distribution lives on the owner and is unchanged: this only proves the new ask does not route around
-- it.
do
    local sim = F.NewRaid()
    F.Drop(sim, 954, F.GLOVES)
    -- After the announcement has left, or they simply receive it like everybody else and the ask is
    -- never the thing under test.
    KARTTEST.AdvanceTime(1)
    local late = RaidSim.Join(sim, { name = "Torvath", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C97", class = "SHAMAN", locale = "enUS" })
    KARTTEST.AdvanceTime(3)

    T.eq(late.KART.LC.rollItems[954], nil, "a raider who was not there is not handed the item by an ack")
end

-- The suppression gates hold: an ack does not reopen what this client closed ------------------------
-- B135/B138: a roll dismissed here, or watched expire here, is not a gap. The whole burst B135
-- measured was clients re-asking for items they had themselves finished with, so a new ask path that
-- ignored those notes would put it straight back.
do
    local sim, lm = F.NewRaid()
    local council, raider = sim.byName.Merrit, sim.byName.Alric

    F.Drop(sim, 955, F.GLOVES)
    KARTTEST.AdvanceTime(25) -- the window closes: the plain raider frees the roll and notes why
    RaidSim.As(council, function() council.KART.LC.Council.CloseCouncilTab(955) end)
    T.truthy(raider.KART.LC.rollExpiredHere[955] ~= nil, "the raider watched the gloves close")
    T.truthy(council.KART.LC.rollDismissed[955] ~= nil, "and the council member put the tab away")

    -- A peer repaired late acks the roll all over again -- the one message that reaches both of these
    -- clients while they hold their notes.
    RaidSim.ClearLog(sim)
    RaidSim.As(sim.byName.Sinja, function() sim.byName.Sinja.KART.LC.SendLC("LC_ACK:955") end)
    KARTTEST.AdvanceTime(2)

    local asks = 0
    for _, e in ipairs(RaidSim.Sent(sim, "LC_ROLL_REQ")) do
        if e.from == raider.name or e.from == council.name then asks = asks + 1 end
    end
    T.eq(asks, 0, "neither of them asks for an item they are finished with")
    T.eq(#RaidSim.Sent(sim, "LC_ROLL_CATCHUP"), 0, "so the owner's queue stays empty (B135)")
    T.eq(lm.KART.LC.rollItems[955] ~= nil, true, "while the owner still holds it, waiting to award it")
end

-- ==================================================================================================
--  F2: what the council sees about each raider's answer
-- ==================================================================================================
--
-- The panel drew cast votes and nothing else, so a raider mid-relog and a raider ignoring the window
-- were the same empty dash on the screen the item is handed out from (Manifest C14).

local function StateOn(client, rollID, forClient)
    return RaidSim.As(client, function()
        local key = (client.KASC.Identity.ResolvePlayer(forClient.unit))
        return client.KART.LC.Council.AnswerState(rollID, key)
    end)
end

-- Acked, silent, answered ---------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    -- A raider who is not running the module at all: in the raid, on the panel, and saying nothing.
    -- Deafening this client to the announcement would NOT do -- the overhear repair catches it up and
    -- it acks from there, which is the feature working, not a silent raider.
    local quiet = sim.byName.Alric
    local voter = sim.byName.Sinja
    quiet.env.KART_Settings.lcModuleEnabled = false

    F.Drop(sim, 980, F.GLOVES)
    KARTTEST.AdvanceTime(3) -- the announcement, and every slot of the ack spread

    T.eq(StateOn(lm, 980, sim.byName.Corvin), "acked",
        "a raider whose ack arrived is shown as holding the item, not as unanswered")
    T.eq(StateOn(lm, 980, lm), "acked", "and so is the owner, who is holding it by definition")
    T.is_nil(StateOn(lm, 980, quiet),
        "while a raider who has said nothing yet is still just an empty cell -- the ack could be late")

    -- Only after the wait does silence mean anything. Nothing arrives to trigger the redraw, which is
    -- why the panel arms its own timer for this moment.
    KARTTEST.AdvanceTime(10)
    T.eq(StateOn(lm, 980, quiet), "silent", "past the wait, the silence is stated rather than implied")

    -- An answer supersedes both, and it is the row that proves it: AnswerState is only consulted for a
    -- raider who has not voted.
    RaidSim.As(voter, function() voter.KART.LC.Vote.CastVote(980, 1, nil, false) end)
    KARTTEST.AdvanceTime(6)
    local row
    RaidSim.As(lm, function()
        lm.KART.LC.Council.RefreshCouncilRows()
        local key = (lm.KASC.Identity.ResolvePlayer(voter.unit))
        for _, r in ipairs(lm.KART.LC.councilPanel.rows or {}) do
            if r:IsShown() and r.memberKey == key then row = r end
        end
    end)
    T.truthy(row, "the voter has a row on the panel")
    T.truthy(not tostring(row.voteText:GetText()):find(lm.KART.L.LC_ANSWER_ACKED, 1, true),
        "and it shows their answer, not what they acked")
end

-- Somebody who was not in the raid for it stays an empty cell ---------------------------------------
-- The other half of C14: a cell that says "no reply" about a raider who was never asked is the same
-- false statement in the other direction.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 981, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    local late = RaidSim.Join(sim, { name = "Torvin", realm = "TarrenMill",
                                     guid = "Player-1096-0A1B2C96", class = "HUNTER", locale = "enUS" })
    KARTTEST.AdvanceTime(15) -- well past the wait that turns silence into "no reply"

    T.is_nil(StateOn(lm, 981, late), "a raider who joined afterwards is not in this decision at all")
end

-- A reused rollID does not inherit the previous item's answers --------------------------------------
-- Blizzard hands the same number to an unrelated item within seconds. An ack kept across that would
-- show somebody as holding an item they have never been told about.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 982, F.GLOVES)
    KARTTEST.AdvanceTime(3)
    T.eq(StateOn(lm, 982, sim.byName.Corvin), "acked", "the gloves were acked")

    RaidSim.Blackhole(sim, "LC_ACK")
    F.Drop(sim, 982, F.WEAPON)
    KARTTEST.AdvanceTime(3)
    RaidSim.Deliver(sim, "LC_ACK")

    T.is_nil(StateOn(lm, 982, sim.byName.Corvin),
        "and the weapon that reuses the number starts from nothing")
end

-- A refused ack must not turn into a raider who "said nothing" -------------------------------------
-- The ack was built deliberately non-guaranteed, on the reasoning that a lost one costs nothing
-- "because the next client's ack carries the same evidence". That is true of F1, the self-heal: any
-- ack tells a deaf client it was skipped. It is false of F2, the answer states -- each client's ack
-- is the ONLY evidence about that client, and nothing ever re-sends it. QueueAck fires once, on the
-- rollAnnounced false->true edge, and no heartbeat, catch-up or restriction release re-queues it.
--
-- Measured before changing it (offline evening, 30 clients, 174 acks): at the refusal rate B135's
-- live table recorded -- 1 to 4 own sends refused per raider per evening -- 4 refused acks put 24
-- false cells on the council panel, because one ack covers a whole boss BATCH. The panel then says,
-- in the tooltip, that the raider is offline or not running KART, about somebody who is holding the
-- item and deciding. That is the C14 false statement the states exist to prevent, on the screen the
-- item is handed out from.
do
    local sim, lm = F.NewRaid()

    -- The client refusing to send, which is what the rate limiter actually does (B120): the message
    -- never leaves, and the only signal is the return value.
    local victim
    sim.sendResult = function(msg)
        local body = msg:sub(1, 1) == "\001" and msg:sub(2) or msg
        if body:sub(1, 7) == "LC_ACK:" and not victim then
            victim = RaidSim.active
            return 8 -- ChannelThrottle
        end
        return 0
    end

    F.Drop(sim, 983, F.GLOVES)
    KARTTEST.AdvanceTime(3)
    sim.sendResult = nil
    T.truthy(victim ~= nil, "one client's ack really was refused")

    -- Long past ACK_WAIT (8 s), so silence has had every chance to be believed, and past
    -- SEND_RETRY_DELAYS, so a retry has had every chance to land.
    KARTTEST.AdvanceTime(20)

    T.truthy(RaidSim.As(victim, function() return victim.KART.LC.rollItems[983] ~= nil end),
        "the raider whose ack was refused is holding the item")
    T.eq(StateOn(lm, 983, victim), "acked",
        "and the council is told so, instead of being told they said nothing")
end

-- ...and an ack that arrives after the round ended asks for nothing ---------------------------------
-- The other half of the same hole. LC.ClearAllRolls wipes LC.rollReqSent along with everything else,
-- and End Round sends itself three times (0/2/5 s), so each repeat re-opened the cooldown for the
-- acks still despooling behind it. Measured over an offline evening with one boss's announcement
-- lost: 841 asks against 267 on the tree before these packages, six per client per roll inside seven
-- seconds, where the gate on its own allows one.
do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 984, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    RaidSim.Hold(sim, "LC_ACK")
    KARTTEST.AdvanceTime(3)
    RaidSim.As(lm, function() lm.KART.LC.EndRound() end)
    KARTTEST.AdvanceTime(6)   -- past both END_ROUND_REPEATS

    RaidSim.ClearLog(sim)
    T.truthy(RaidSim.Release(sim, "LC_ACK") > 0, "the acks land after the round is over")
    KARTTEST.AdvanceTime(2)

    local asks = 0
    for _, e in ipairs(RaidSim.Messages(sim, "LC_ROLL_REQ")) do
        if e.msg:match("^LC_ROLL_REQ:") then asks = asks + 1 end
    end
    T.eq(asks, 0, "and nobody asks about a roll the round has already ended")
end

-- The redraw an ack triggers is the throttled one (B169) --------------------------------------------
-- Every assertion above reads Council.AnswerState directly, which is the right level for what the
-- state MEANS -- and it leaves the path that puts it on screen unheld. LC.HandleAck refreshes through
-- Council.RefreshCouncilRowsThrottled and through nothing else, and mutating that function to a no-op
-- left the whole suite green.
--
-- What it costs is C14 read literally: "the council sees who has not answered yet". The states are
-- computed correctly and never drawn, so the panel keeps showing the answer it had when something
-- else last happened to redraw it -- which on a quiet distribution is the moment the item dropped.
--
-- Isolated to the timer on purpose: rendered once so the row is known stale, then an ack delivered,
-- then the row read BEFORE the throttle is due and again after. Nothing else calls a refresh in
-- between, so only that timer can account for the change.
do
    local sim, lm = F.NewRaid()
    local acker = sim.byName.Alric
    F.Drop(sim, 985, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local ackerKey = RaidSim.As(lm, function()
        return (lm.KASC.Identity.ResolvePlayer(acker.unit))
    end)
    local function RowText()
        local out
        RaidSim.As(lm, function()
            for _, r in ipairs(lm.KART.LC.councilPanel.rows or {}) do
                if r:IsShown() and r.memberKey == ackerKey then out = tostring(r.voteText:GetText()) end
            end
        end)
        return out or ""
    end

    -- Put the row into the "said nothing yet" state and draw it once, so what follows can only come
    -- from the redraw under test.
    RaidSim.As(lm, function()
        lm.KART.LC.rollAcked[985] = nil
        lm.KART.LC.Council.RefreshCouncilRows()
    end)
    T.truthy(not RowText():find(lm.KART.L.LC_ANSWER_ACKED, 1, true),
        "the setup: the row does not yet say this raider has the item")

    -- The ack lands. LC.HandleAck asks for a throttled redraw and does nothing else to the panel.
    RaidSim.As(lm, function() lm.KART.LC.HandleAck("985", ackerKey) end)
    T.truthy(not RowText():find(lm.KART.L.LC_ANSWER_ACKED, 1, true),
        "B169: the panel has not redrawn yet -- the refresh is throttled, not immediate")

    KARTTEST.AdvanceTime(0.5)
    T.truthy(RowText():find(lm.KART.L.LC_ANSWER_ACKED, 1, true),
        "B169: and once the throttle is due the council sees that this raider has the item (C14)")
end
