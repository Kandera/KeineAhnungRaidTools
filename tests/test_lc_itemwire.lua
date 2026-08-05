-- What an item looks like on the wire, and what it turns back into on the other side.
--
-- B119, from the raid of 2026-08-03: LC_START carried the itemID and nothing else, so every client
-- that never got Blizzard's own roll window rebuilt the item from that id -- and an id alone is the
-- BASE version of an item. The raid's vote windows read "Item Level 44" next to equipped 285s, the
-- Droptimizer column stayed empty because that lookup is variant-exact, and a set token showed up as
-- something else entirely (GitHub #20, #22, #23).
--
-- The harness could not see any of it: its item database was keyed on the bare id, so both forms
-- answered with the same link. tests/wow_stubs.lua now models the two variants, opt-in per item via
-- def.baseIlvl, and this file is what that exists for.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- The item from the report, with the two levels it actually had: 285 as it dropped, 44 as its base.
local BRACERS = KARTTEST.AddItem({ id = 249326, name = "Light's March Bracers", quality = 4,
                                   ilvl = 285, baseIlvl = 44, classID = 4, subclassID = 3,
                                   equipLoc = "INVTYPE_WRIST", bind = 1 }).id

local function IlvlOf(link)
    return (select(4, C_Item.GetItemInfo(link)))
end

-- The item reaches a client Blizzard gave no roll to ---------------------------------------------
do
    local sim, lm = F.NewRaid()
    local deaf = sim.byName.Corvin -- council, and never asked to roll: the reported case exactly
    RaidSim.ClearLog(sim)
    F.Drop(sim, 90, BRACERS, { bop = true, noRollFor = { Corvin = true } })
    KARTTEST.AdvanceTime(1)

    local sent = RaidSim.Sent(sim, "LC_DROP")
    T.eq(#sent, 1, "the loot owner announces the roll once")
    T.truthy(sent[1].msg:find("11946", 1, true),
        "and the announcement carries the item's bonus ids, not just its id")

    local mine  = lm.KART.LC.rollItems[90]
    local heard = deaf.KART.LC.rollItems[90]
    T.eq(IlvlOf(heard), 285,
        "a client that never saw Blizzard's roll ends up on the item that dropped, not its base version")
    T.eq(IlvlOf(heard), IlvlOf(mine), "which is the same item level the loot owner is looking at")
    T.eq(heard, mine, "and the same link, so tooltip, icon and Droptimizer all agree across the raid")
end

-- Proof the harness can tell the two apart ---------------------------------------------------------
-- Without this, every assertion above would also pass on the old payload, and the test would be
-- decoration. The bare id is what the old wire carried.
do
    T.eq(IlvlOf("item:" .. BRACERS), 44, "the bare id resolves to the base version of the item")
    T.eq(IlvlOf(KARTTEST.items[BRACERS].link), 285, "and the full string to the one that dropped")
end

-- An older client's announcement is still accepted --------------------------------------------------
-- During a rollout the raid runs both builds for an evening. Refusing the old shape would take the
-- item away from everyone still on it, which is the failure this change exists to end.
do
    local sim, _, council = F.NewRaid()
    local owner = sim.byName.Bramor
    RaidSim.As(council, function()
        council.KART.LC.HandleStart("91:20:" .. BRACERS, owner.guid)
    end)
    KARTTEST.AdvanceTime(0)
    local heard = council.KART.LC.rollItems[91]
    T.truthy(heard, "a bare-id announcement from an older client still opens the roll")
    T.truthy(tostring(heard):find(tostring(BRACERS), 1, true), "on the right item")
end

-- Length is no longer a reason to send less ---------------------------------------------------------
-- This used to cut any string over the transport's old 255-byte cap down to the bare id, so a
-- catch-up would hand over the BASE version of the item -- item level 44 instead of 285, wrong
-- tooltip, empty upgrade column (#20, #22, #23, and #35 after they were declared fixed). The cap
-- stopped applying when the transport moved onto AceComm, which splits and reassembles a long message
-- whole; every Midnight drop with a full upgrade track is over it, so the exception was the rule.
do
    local _, lm = F.NewRaid()
    local Payload = lm.KART.LC.ItemPayload

    local long = "|cffa335ee|Hitem:" .. BRACERS .. ":" .. string.rep("9", 240) .. "|h[X]|h|r"
    T.truthy(#Payload(long, tostring(BRACERS)) > 240,
        "a string too long for one message goes out whole, for the transport to split")

    local normal = KARTTEST.items[BRACERS].link
    T.truthy(Payload(normal, tostring(BRACERS)):find("11946", 1, true),
        "while an ordinary one goes out in full")

    T.eq(Payload("Test Item", "777"), "777",
        "and a test roll, which has no real link at all, still names its id")
end
