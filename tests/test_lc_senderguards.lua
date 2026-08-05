-- The five "is this sender really in our group" guards, which nothing held.
--
-- Every one of them is the same line: resolve the sender's key to a LIVE UNIT first, and refuse the
-- message if it resolves to nobody. The comment at LC.IsSenderCouncil says why, and it is not
-- theoretical: CHAT_MSG_ADDON delivers whispers, the "KART" prefix is public, and a key that once
-- belonged to a council member keeps matching CouncilNamesTable long after that person left the
-- raid. Trusting the key alone means somebody who is not in the raid can vote in it, relay a config
-- into it, or resume its session.
--
-- The same shape guarded the loot history at LH.HandleHistoryEntry, where it was closed on
-- 2026-08-02 (B66) -- these five are its siblings, found by the twentieth bug run.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local STRANGER = "Player-4711-DEADBEEF"

-- Who counts as council -----------------------------------------------------------------------
do
    -- A council member who has left the raid. Their key is still in CouncilNamesTable -- the list is
    -- the raid's config, not its roster -- so the key check alone says yes and only the unit lookup
    -- says no. This is the exact case the guard's own comment describes.
    local sim, lm = F.NewRaid()
    local merrit = sim.byName.Merrit
    T.truthy(RaidSim.As(lm, function() return lm.KART.LC.IsSenderCouncil(merrit.guid) end),
        "a council member in the raid is council")

    RaidSim.Leave(sim, "Merrit")
    T.truthy(RaidSim.As(lm, function() return lm.KART.LC.CouncilNamesTable[merrit.guid] end),
        "their key is still on the council list after they leave")
    T.truthy(not RaidSim.As(lm, function() return lm.KART.LC.IsSenderCouncil(merrit.guid) end),
        "but somebody who is not in the raid is not council, whatever the list says")

    T.truthy(not RaidSim.As(lm, function() return lm.KART.LC.IsSenderCouncil(STRANGER) end),
        "and a key belonging to nobody here never was")
end

-- The four handlers that take a key ---------------------------------------------------------------
-- Each is checked the same way: take a picture of what the message would change, deliver it from a
-- key that resolves to nobody, and require the picture to be unchanged. Coarse on purpose -- what is
-- under test is that the message was REFUSED, not what it would have done.
local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function Snapshot(client)
    local lc = client.KART.LC
    return {
        session   = lc.sessionActive,
        lootmaster = lc.raidConfig and lc.raidConfig.lootmaster,
        council   = lc.raidConfig and lc.raidConfig.councilMembers,
        buttons   = lc.raidConfig and lc.raidConfig.buttonLabels,
        -- Counted, not sampled. `next()` on a table that already holds entries answers the same key
        -- before and after one is added, so it cannot see the thing being asked about: whether the
        -- refused message wrote a vote or a roll of its own.
        votes     = Count(lc.votes[80]),
        rolls     = Count(lc.rolls[80]),
    }
end

local function Same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false, k end end
    for k, v in pairs(b) do if a[k] ~= v then return false, k end end
    return true
end

do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 80, F.GLOVES)
    -- Past the drop's collection window, so the announcement is on the wire before the picture is
    -- taken -- what the assertions below are about is what the REFUSED message adds to either.
    KARTTEST.AdvanceTime(1)
    local before = Snapshot(lm)

    local calls = {
        { "the raid config relay", function()
            lm.KART.LC.HandleConfigRelay("Fremder;Fremder;BIS;1;1;3", STRANGER)
        end },
        { "a session resume", function() lm.KART.LC.HandleSessionResume(STRANGER) end },
        -- The payload has to be one the handler would otherwise ACCEPT, or it bails on the pattern
        -- and the guard under test is never reached -- an assertion that passes for the wrong
        -- reason. HandleRolls' shape is "rollID:@itemID:key=value,...".
        { "somebody else's roll table", function()
            lm.KART.LC.HandleRolls("80:@" .. F.GLOVES .. ":" .. STRANGER .. "=97", STRANGER)
        end },
    }

    for _, case in ipairs(calls) do
        local label, fn = case[1], case[2]
        -- Nothing said back, either. A request to repeat our vote changes no state of ours at all --
        -- what it does is put a message on the wire, so a state snapshot alone cannot see it being
        -- refused, and a stranger who can make us answer can make the whole raid answer.
        RaidSim.ClearLog(sim)
        local ok = pcall(function() RaidSim.As(lm, fn) end)
        KARTTEST.AdvanceTime(2)
        T.truthy(ok, label .. " from a key that is in no group does not throw")
        local same, field = Same(before, Snapshot(lm))
        T.truthy(same, label .. " from a key that is in no group changes nothing"
            .. (field and (" (" .. field .. " moved)") or ""))
        -- Everything except the owner's own table heartbeat, which is nobody's answer to anything:
        -- it is polled every two seconds and lands inside this window whatever the stranger did or
        -- did not send.
        local answers = 0
        for _, e in ipairs(RaidSim.Sent(sim, "")) do
            if not e.msg:match("LC_TABLE") then answers = answers + 1 end
        end
        T.eq(answers, 0, label .. " from that key is not answered either")
    end
end
