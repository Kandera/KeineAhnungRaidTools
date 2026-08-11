-- What Auto-Pass is allowed to act on. Rewritten 2026-08-11 for B174, which reverses the answer B63
-- gave this file: the question is asked of the SESSION now, not of the item.
--
-- B63 made passing conditional on the council demonstrably having taken THIS item up -- the owner's
-- LC_DROP had to arrive first. That put a message on the hot path. In the good case the raider looked
-- at Blizzard's window for the second it took to travel; in the bad case it never came and they had
-- to answer the window by hand, which is the single complaint that costs this module its raid.
--
-- RCLootCouncil has answered it at session level for years (Classes/Utils/GroupLoot.lua,
-- ShouldPassOnLoot): a bit test over "addon enabled, in a group, valid master looter, their settings
-- received, not us". Nothing on the wire at the moment an item drops. KART now asks the same question
-- through LC.CouncilRunsHere.
--
-- THE TRADE, STATED PLAINLY, because it is a real one and it is the maintainer's decision of
-- 2026-08-11: where the loot owner never gets a roll event of their own, the raid now passes on an
-- item nobody force-won and it goes to whoever is not running KART. B63 rejected exactly that. It is
-- accepted here for the reason RC accepts it -- the alternative costs every raider a visible window
-- on every drop, and that failure is constant while this one needs the owner to be dead, released or
-- out of range at the moment of the kill.
--
-- The announcement is still accepted on its own, so a client that has NOT been told the session state
-- is covered by the message the way it always was. Both orders occur; both are exercised here.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim
local NewRaid, Drop = F.NewRaid, F.Drop

-- Auto-Pass is on by default; Merrit is the fixture's one raider who clicks Blizzard's window
-- themselves, and Bramor is the lootmaster, who force-wins rather than passes.
local AUTOPASSERS = { "Corvin", "Alric", "Sinja" }

local function PassedBy(sim, rollID, name)
    local client = sim.byName[name]
    return (KARTTEST.rolled[rollID] or {})[client.unit]
end

-- Longer than anything KART schedules against a roll: the announcement warning B175 removed fired at
-- 45 seconds, Blizzard's own window is shorter, and the heartbeat repairs within seconds. A silence
-- assertion has to outlast every one of them, or it passes by arriving too early.
local PAST_EVERY_TIMER = 90

-- No chat line may name a looted item. Not "no line for this case" -- none at all, on any client, for
-- any of the reasons a roll window can go unexplained. Reported from raids as the thing that reads as
-- "KART ist schon wieder kaputt" whether or not it names a real fault, and reported as growing MORE
-- frequent over time, which is what more traffic and later announcements produce.
local function SaysNothingAboutLoot(out, label)
    for _, id in ipairs({ F.GLOVES, F.WEAPON, F.RARE }) do
        T.truthy(not out:find(KARTTEST.items[id].name, 1, true), label)
    end
end

local function Capture(fn)
    local lines = {}
    local realPrint = _G.print
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

-- The normal evening: the announcement lands, everybody passes ------------------------------------
-- The regression guard for everything below. Auto-Pass exists so a raider does not have to click
-- loot windows, and it has to keep doing that.
do
    local sim = NewRaid()
    Drop(sim, 50, F.GLOVES)
    -- Past the window a drop is collected in, so the announcement has reached them.
    KARTTEST.AdvanceTime(1)

    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 50, name), 0, name .. " passed Blizzard's roll once the council had the item")
    end
    T.is_nil(PassedBy(sim, 50, "Merrit"), "a raider with Auto-Pass off is still left to answer it themselves")
    T.eq(PassedBy(sim, 50, "Bramor"), 1, "and the lootmaster force-won it rather than passing")
end

-- The local roll event alone is enough (B174) ------------------------------------------------------
-- The fixture drops in raid order, so the owner normally announces before the other clients run their
-- own handler. Driving the raiders' handlers WITHOUT the owner ever running theirs is what isolates
-- the local path: no LC_DROP has been built, let alone sent, and the pass still has to happen.
do
    local sim, lm = NewRaid()
    KARTTEST.lootRolls[51] = { itemID = F.GLOVES, bop = true, forNames = {} }
    for _, c in ipairs(sim.clients) do KARTTEST.lootRolls[51].forNames[c.name] = true end
    for _, c in ipairs(sim.clients) do
        if c ~= lm then RaidSim.As(c, function() c.KART.LC.OnStartLootRoll(51) end) end
    end
    T.eq(#RaidSim.Messages(sim, "LC_DROP"), 0, "nothing has been announced at this point")
    for _, name in ipairs(AUTOPASSERS) do
        T.truthy(not sim.byName[name].KART.LC.rollAnnounced[51],
            name .. " has heard nothing about this item")
        T.eq(PassedBy(sim, 51, name), 0, name .. " passes anyway, off their own roll event")
    end
    T.is_nil(PassedBy(sim, 51, "Merrit"), "a raider with Auto-Pass off is still left to answer it")
end

-- What B63 protected, now accepted: the owner never gets the roll event ----------------------------
-- The owner is dead, released or out of range when the boss dies, so nobody ever announces. Under
-- B63 the raid kept its windows and rolled by hand. It now passes, and the item goes to whoever is
-- not running KART. Asserted rather than merely allowed, so that reversing this decision later means
-- changing a test that says what it costs.
do
    local sim, lm = NewRaid()
    Drop(sim, 52, F.GLOVES, { noRollFor = { Bramor = true } })
    KARTTEST.AdvanceTime(1)

    T.eq(#RaidSim.Messages(sim, "LC_DROP"), 0, "nobody announces the item, because only the owner ever does")
    T.is_nil(lm.KART.LC.rollItems[52], "and the owner is not tracking an item they never saw")

    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 52, name), 0, name .. " passes on the session, not on the announcement")
    end
    T.is_nil(RaidSim.As(sim.byName.Corvin, function() return GetLootRollItemLink(52) end),
        "so no raider is left holding a window to answer by hand -- which is the point of B174")
end

-- ...and nobody is told anything about it ----------------------------------------------------------
-- The warning exists for a raider still looking at a window nobody explained. Under B174 there is no
-- such raider, so the line must not appear -- and that matters on its own account: a raid reads any
-- red KART line as "broken again", whether or not it names a real fault.
do
    local sim = NewRaid()
    Drop(sim, 53, F.GLOVES, { noRollFor = { Bramor = true } })
    local corvin = sim.byName.Corvin

    local out = Capture(function() KARTTEST.AdvanceTime(PAST_EVERY_TIMER) end)
    SaysNothingAboutLoot(out, "an item the council never took up is not mentioned in chat")
    T.truthy(not corvin.KART.LC.rollAnnounced[53], "the item is still on record as never announced")
    T.eq(PassedBy(sim, 53, "Corvin"), 0, "and it was passed all the same")
end

do
    -- Nothing to explain when it did arrive, and nothing to explain to somebody who was going to
    -- click the window anyway.
    local sim = NewRaid()
    Drop(sim, 54, F.GLOVES)
    local out = Capture(function() KARTTEST.AdvanceTime(PAST_EVERY_TIMER) end)
    SaysNothingAboutLoot(out, "and neither is one it did")

    -- Everyone, because Capture cannot tell one client's chat from another's -- and a raid where
    -- nobody uses Auto-Pass must stay completely silent about an item it simply rolls on by hand.
    local sim2 = NewRaid()
    for _, c in ipairs(sim2.clients) do c.env.KART_Settings.lcAutoPass = false end
    Drop(sim2, 55, F.GLOVES, { noRollFor = { Bramor = true } })
    local out2 = Capture(function() KARTTEST.AdvanceTime(PAST_EVERY_TIMER) end)
    SaysNothingAboutLoot(out2, "and a raider who answers their own loot windows is not told either")
end

-- The owner never waits for their own announcement ------------------------------------------------
-- Normally invisible, because force-winning answers the roll and a client with no roll left says
-- nothing. It becomes visible on an item the lootmaster cannot roll on at all -- no Need, no Greed,
-- no Disenchant, no Transmog -- where ForceWinRoll has nothing to claim it with and the window stays
-- open. Without the guard the owner is then told their own item was never announced.
do
    local sim, lm = NewRaid()
    Drop(sim, 58, F.GLOVES, { canNeed = false, canGreed = false })

    T.is_nil(PassedBy(sim, 58, "Bramor"), "the lootmaster had no roll type to claim it with")
    T.truthy(RaidSim.As(lm, function() return GetLootRollItemLink(58) end),
        "so their window is still open long after every timer has run")
    local out = Capture(function() KARTTEST.AdvanceTime(PAST_EVERY_TIMER) end)
    SaysNothingAboutLoot(out, "and the client that did the announcing is not told anything either")
end

-- Below the raid's rarity threshold: unchanged ----------------------------------------------------
-- The council never announces these -- the lootmaster passes on them too -- so there is nothing to
-- wait for, and making Auto-Pass wait would have left a rare sitting on everyone's screen forever.
do
    local sim = NewRaid()
    Drop(sim, 56, F.RARE)
    KARTTEST.AdvanceTime(1)

    T.eq(#RaidSim.Messages(sim, "LC_DROP"), 0, "a rare is below the threshold and is never announced")
    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 56, name), 0, name .. " still passes it straight away")
    end
    T.eq(PassedBy(sim, 56, "Bramor"), 0, "and so does the lootmaster")
end

-- A reused rollID must not inherit either flag ----------------------------------------------------
-- Blizzard hands the same rollID to a genuinely different item within seconds (see PurgeStaleRoll).
-- A stale "already announced" would make the next item pass on the strength of the previous one's
-- announcement.
do
    local sim = NewRaid()
    Drop(sim, 57, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    local corvin = sim.byName.Corvin
    T.truthy(corvin.KART.LC.rollAnnounced[57], "the first item was announced")

    RaidSim.As(corvin, function() corvin.KART.LC.Trade.ClearRollState(57) end)
    T.truthy(not corvin.KART.LC.rollAnnounced[57], "and clearing the roll forgets that")
    T.truthy(not corvin.KART.LC.rollSeenHere[57], "along with having seen it locally")
end

-- Auto-Pass switched OFF is a raider who answers the window themselves ------------------------------
-- The setting is the first half of that branch, and nothing held it: with it off, a below-threshold
-- item must be left alone for this raider exactly like any other. Passing on their behalf when they
-- asked not to is the same damage the whole file is about, reached from the other side -- the item
-- goes to whoever did not pass, and the raider never saw a choice.
do
    local sim = NewRaid()
    for _, name in ipairs(AUTOPASSERS) do
        sim.byName[name].env.KART_Settings.lcAutoPass = false
    end
    Drop(sim, 58, F.RARE)

    for _, name in ipairs(AUTOPASSERS) do
        T.is_nil(PassedBy(sim, 58, name), name .. " does not pass with Auto-Pass switched off")
    end
    for _, name in ipairs(AUTOPASSERS) do
        sim.byName[name].env.KART_Settings.lcAutoPass = true
    end
end

-- A client that learns about the session AFTER the item dropped ------------------------------------
-- Reported 2026-08-05, and caused by the advice that fixed something else: everybody restarted their
-- client mid-raid to pick up a new build. A fresh client starts with sessionActive false and asks the
-- raid what is going on (LC.RequestSessionState), and until the answer lands LC.OnStartLootRoll
-- returns on its second line -- so LC.rollSeenHere is never set for anything that drops in that
-- window. LC.HandleStart has no such gate, so the vote row appears anyway, and AutoPassAnnounced
-- refuses forever afterwards because the flag it needs is only ever written by the handler that was
-- skipped. The raider is left clicking Blizzard's window while their status line says "Session: on".
do
    local sim, lm = NewRaid()
    local corvin = sim.byName.Corvin
    RaidSim.As(corvin, function()
        corvin.KART.LC.sessionActive = false
        corvin.KART.LC.sessionStateKnown = false
    end)

    Drop(sim, 60, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.truthy(corvin.KART.LC.rollItems[60],
        "the announcement still reaches it, so the item is tracked and a vote row exists")
    T.is_nil(PassedBy(sim, 60, "Corvin"),
        "but nothing is passed while the client does not know a session is running")

    -- The raid answers. From here on the client is in every way a normal participant.
    RaidSim.As(lm, function() lm.KART.LC.SendLC("LC_ACTIVE:1") end)
    KARTTEST.AdvanceTime(1)
    T.truthy(corvin.KART.LC.sessionActive, "the state request is answered")
    T.eq(PassedBy(sim, 60, "Corvin"), 0,
        "and the roll it already saw is passed after all, rather than left open for the evening")
end

-- The announcement is lost outright, and Auto-Pass still happens -------------------------------------
-- This is the chain the module is judged on. A raider who has to click Blizzard's window is a raider
-- who asks why the addon is installed -- "das funktioniert schon wieder nicht, können wir nicht
-- einfach das Modul wieder abschaffen", reported on 2026-08-05 -- and every separate repair built
-- since then exists to keep that from happening. Nothing had ever asserted that they compose.
--
-- Four links, and each one has its own test elsewhere; this one is about the whole rope:
--   the announcement is lost      -> the lootmaster's heartbeat says what is on the table
--   the client notices the gap    -> LC_ROLL_REQ
--   the owner answers             -> LC_ROLL_CATCHUP -> LC.HandleStart
--   HandleStart marks it announced-> AutoPassAnnounced finally has both halves
do
    local sim = NewRaid()
    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 70, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    -- Since B174 the first link of that rope is no longer load-bearing for the PASS: the raider is
    -- already done with Blizzard's window before any repair runs. The rope still matters for the vote
    -- row, and the block below it is what holds that.
    for _, name in ipairs(AUTOPASSERS) do
        T.eq(PassedBy(sim, 70, name), 0,
            name .. " passed without the announcement, so the loss is not theirs to notice")
    end
    T.eq(PassedBy(sim, 70, "Bramor"), 1, "while the lootmaster force-won it regardless of the message")

    -- Nothing is re-sent by hand. The heartbeat falls due, the clients ask, the owner answers -- and
    -- THAT is what puts the item on their screen to vote on.
    KARTTEST.AdvanceTime(4)
    for _, name in ipairs(AUTOPASSERS) do
        T.truthy(sim.byName[name].KART.LC.rollItems[70],
            name .. " is tracking the item once the repair reaches them")
    end
end

-- ...and the same when the client also missed the session itself ------------------------------------
-- The shape of a raider who restarted mid-evening: no session state, no announcement, and Blizzard's
-- roll window already up. Both repairs have to land, in either order.
do
    local sim, lm = NewRaid()
    local corvin = sim.byName.Corvin
    RaidSim.As(corvin, function()
        corvin.KART.LC.sessionActive = false
        corvin.KART.LC.sessionStateKnown = false
    end)
    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 71, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    T.is_nil(PassedBy(sim, 71, "Corvin"), "nothing has reached this client at all yet")

    RaidSim.As(lm, function() lm.KART.LC.SendLC("LC_ACTIVE:1") end)
    KARTTEST.AdvanceTime(5)
    T.eq(PassedBy(sim, 71, "Corvin"), 0,
        "and once both the session and the item have found their way there, it passes")
end

-- A reused rollID does not inherit the previous item's announcement ---------------------------------
-- B63's guarantee is that nothing is passed until the council demonstrably has the item. Blizzard
-- reuses roll numbers within seconds, and LC.OnStartLootRoll consults LC.rollAnnounced BEFORE
-- PurgeStaleRoll clears the previous roll's state from under that number -- so the SECOND item, which
-- nobody announced and which may not be council's business at all, was passed on the strength of the
-- first one's announcement. The exact failure B63 was written for, reached through the back door.
do
    local sim = NewRaid()
    local raider = sim.byName.Alric

    Drop(sim, 96, F.GLOVES)
    KARTTEST.AdvanceTime(2)
    T.truthy((KARTTEST.rolled[96] or {})[raider.unit] ~= nil,
        "the announced item is passed, as it should be")

    -- The same number, a different item, and this client is never told about it.
    KARTTEST.rolled[96] = nil
    RaidSim.Blackhole(sim, "LC_DROP")
    Drop(sim, 96, F.WEAPON)
    KARTTEST.AdvanceTime(2)
    RaidSim.Deliver(sim, "LC_DROP")

    T.is_nil((KARTTEST.rolled[96] or {})[raider.unit],
        "the unannounced item reusing that number is not passed on the strength of the first one")
end

-- B148, the deferred half -- fixed 2026-08-07 -----------------------------------------------------
-- Until now the session gate above recorded "unaware" for EVERY roll it saw, above any of the
-- eligibility tests further down -- so a mount or a Bind-on-Equip drop took one of the ten pass-log
-- ring slots. Neither is ever announced (see AutoPassAnnounced / ReplayOne), so that slot could never
-- resolve into anything else: it sat there naming an item nobody was ever going to decide, on the
-- screen the Manifest asks the raid to photograph, until ten further council rolls pushed it out.
--
-- The fix: record a verdict only once it is positively established the council could take the roll
-- up (CouncilCouldTakeRoll, mirroring councilEligible). "Cannot tell yet" -- the item's link has not
-- propagated -- must not count as "yes", so it records nothing rather than guessing. The roll itself
-- is still remembered either way (LC.rollsSeenWhileUnaware); only the verdict is withheld.
do
    local function GateFor(client, id)
        return RaidSim.As(client, function()
            for _, e in ipairs(client.KART.LC.passLog) do
                if e.rollID == id then return e.gate end
            end
        end)
    end

    local sim = NewRaid()
    local corvin = sim.byName.Corvin
    RaidSim.As(corvin, function()
        corvin.KART.LC.sessionActive = false
        corvin.KART.LC.sessionStateKnown = false
    end)

    -- A council item still gets its verdict -- the case B148 built the pass-log entry for in the
    -- first place, and it must not regress.
    Drop(sim, 80, F.GLOVES)
    T.eq(GateFor(corvin, 80), "unaware", "a Bind-on-Pickup drop still records the unaware verdict")
    T.truthy(corvin.KART.LC.rollsSeenWhileUnaware[80], "and the roll itself is remembered")

    -- A Bind-on-Equip drop -- the realistic non-council item; a mount barely reaches Blizzard's roll
    -- window at all in current WoW -- gets no verdict: Council was never going to touch it.
    Drop(sim, 81, F.BOE, { bop = false })
    T.is_nil(GateFor(corvin, 81), "a Bind-on-Equip drop records no verdict at all")
    T.truthy(corvin.KART.LC.rollsSeenWhileUnaware[81], "but the roll is still remembered")

    -- An item whose link has not propagated yet: eligibility cannot be decided at all, so nothing is
    -- recorded rather than guessed. The session gate has no retry loop of its own (deliberately --
    -- unlike the one further down for a known session), so this stays undecided rather than answered
    -- either way.
    Drop(sim, 82, F.GLOVES, { linkPending = true })
    T.is_nil(GateFor(corvin, 82), "an unidentifiable item records no verdict")
    T.truthy(corvin.KART.LC.rollsSeenWhileUnaware[82], "and is still remembered for the replay")
end

-- Eligibility parity: the session gate must not drift from the aware path --------------------------
-- CouncilCouldTakeRoll (~5178) is a deliberate mirror of the councilEligible expression computed
-- later in this same function (~5296), not a shared helper -- the two need the data at different
-- moments and from different sources, and the comment above the helper explains why. What mirroring
-- costs is that nothing enforces the two stay identical, and the carve-out they both encode is a
-- standing maintainer decision that has already changed once (the recipe exception, 2026-08-06) and
-- may change again. An edit applied to one copy and not the other would silently reopen B148 for
-- whichever path was missed -- the pass-log ring filling again with items nobody was ever going to
-- decide -- and nothing would say so short of a live raid's screenshot.
--
-- CouncilCouldTakeRoll is file-local, so it cannot be called directly. This drives both real entry
-- points instead and compares OBSERVABLE outcomes for the same item:
--   unaware -- a roll seen while the session is unknown: does it record an "unaware" pass-gate entry
--              (the case the block above this one covers)?
--   aware   -- the same roll on the LOOTMASTER's own client once the session is known: is their own
--              roll resolved by KART at all -- force-won or auto-passed -- as opposed to left
--              untouched for Blizzard's window to answer? The lootmaster's if/elseif pair (~5308 and
--              ~5320) fires, one way or the other, exactly when councilEligible is true, and not at
--              all when it is false; unlike AutoPassAnnounced for everyone else, neither branch is
--              additionally gated by LC.GetRaidMinQuality(), so "was the lootmaster's roll touched at
--              all" reads councilEligible's effect without councilEngages' extra condition mixed in.
-- The two observables must agree for every item below. If they don't, one site changed and the
-- other didn't.
do
    local function GateFor(client, id)
        return RaidSim.As(client, function()
            for _, e in ipairs(client.KART.LC.passLog) do
                if e.rollID == id then return e.gate end
            end
        end)
    end

    local unawareSim = NewRaid()
    local corvin = unawareSim.byName.Corvin
    RaidSim.As(corvin, function()
        corvin.KART.LC.sessionActive = false
        corvin.KART.LC.sessionStateKnown = false
    end)

    local awareSim = NewRaid()

    -- bop overrides how the harness stub reports each item's bind: it defaults every drop to
    -- Bind-on-Pickup regardless of the item's own fixture data, so a Bind-on-Equip case has to say
    -- so explicitly (the same convention test_lc_collectible.lua and the block above use).
    local MATRIX = {
        { "a Bind-on-Pickup gear item", F.GLOVES },
        { "a Bind-on-Equip item",       F.BOE,    false },
        { "a recipe",                   F.RECIPE, false },
        { "a collectible (mount)",      F.MOUNT },
        { "a tier token",               F.TOKEN },
    }

    for i, case in ipairs(MATRIX) do
        local label, itemID, bop = case[1], case[2], case[3]
        local rollID = 900 + i

        Drop(unawareSim, rollID, itemID, { bop = bop })
        local unaware = GateFor(corvin, rollID) == "unaware"

        Drop(awareSim, rollID, itemID, { bop = bop })
        local aware = PassedBy(awareSim, rollID, "Bramor") ~= nil

        T.eq(aware, unaware,
            label .. ": the aware path's councilEligible and the session gate's CouncilCouldTakeRoll agree")
    end
end

-- B160: the unaware list must not fill up with rolls Blizzard has finished with ---------------------
-- LC.rollsSeenWhileUnaware is capped, and once full the NEWEST entry is dropped rather than the
-- oldest -- deliberately, because it is keyed by rollID and has no order to drop by. The comment says
-- "none of them is worth remembering past the boss it belongs to", and nothing did that: entries only
-- ever left through a replay, which needs the announcement (or, since B158, being the loot owner).
--
-- The case that fills it is precisely the one with no session, so End Round never comes to sweep it:
-- a client sitting in a raid before the lootmaster starts one, or with the module on and the session
-- off, sees every Bind-on-Pickup roll of the evening and remembers each one for ever. Past forty, the
-- roll that actually needs the replay is the one thrown away.
--
-- Bounded by asking Blizzard rather than by an age: an entry is worth keeping exactly while the roll
-- window it names is still open, because ReplayOne does nothing for a roll Blizzard has closed. That
-- needs no constant and no assumption about how long Blizzard's window lasts.
do
    local sim = NewRaid()
    local corvin = sim.byName.Corvin
    RaidSim.As(corvin, function()
        corvin.KART.LC.sessionActive = false
        corvin.KART.LC.sessionStateKnown = false
    end)

    -- A whole evening of drops in a raid with no session, each one's roll window closing behind it.
    -- Forty is SEEN_WHILE_UNAWARE_MAX; the point is to walk past it.
    for i = 1, 45 do
        Drop(sim, 400 + i, F.GLOVES)
        KARTTEST.lootRolls[400 + i] = nil   -- Blizzard's window for it is gone
    end

    local held = 0
    for _ in pairs(corvin.KART.LC.rollsSeenWhileUnaware) do held = held + 1 end
    T.truthy(held < 45,
        "B160: entries for rolls Blizzard has closed do not accumulate (" .. held .. " held)")

    -- ...and the roll that comes in after all that, with a live window, is the one that matters.
    Drop(sim, 499, F.GLOVES)
    T.truthy(corvin.KART.LC.rollsSeenWhileUnaware[499],
        "B160: so a live roll arriving late in the evening is still remembered for the replay")
end
