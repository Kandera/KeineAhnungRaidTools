-- What a raider answers when a council panel asks what they are wearing.
--
-- REQ_EQUIP goes out while a council member looks at an item; every raider in the group answers with
-- their own equipped link for that slot, and the panel shows the comparison. Two decisions in that
-- responder survived being mutated away, and both are about not flooding or misleading the asker.
--
-- The third of the addon's 255-byte sites, after the raid config (B107) and the history catch-up
-- (B112) -- and the one that resolves it differently ON PURPOSE. Here the reply is DROPPED when it
-- will not fit, because a missing comparison renders as "no data" while a truncated link renders as
-- a wrong one, cached under that raider's name. The history sync cannot do that: a missing award is
-- missing from the record for good.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link

local function Ask(client, slot)
    RaidSim.As(client, function() client.KASC:Send("REQ_EQUIP:" .. slot, "RAID") end)
    KARTTEST.AdvanceTime(0)
end

-- The ordinary exchange, so nothing below passes against a responder that never answers -----------
do
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    -- The inventory stub is keyed by SLOT NUMBER and is shared by every simulated client, so this
    -- equips the whole raid -- which is what a REQ_EQUIP broadcast asks of them anyway.
    KARTTEST.inventory[10] = GLOVES   -- INVTYPE_HAND
    T.truthy(alric ~= nil)

    RaidSim.ClearLog(sim)
    Ask(council, "INVTYPE_HAND")
    local replies = RaidSim.Sent(sim, "EQUIP:")
    T.truthy(#replies > 0, "raiders answer what they have equipped in that slot")
    T.truthy(lm ~= nil)
end

-- The answer cooldown ------------------------------------------------------------------------------
-- The panel refreshes on every incoming vote, and each refresh can ask again. Without a per-slot
-- cooldown every raider answers every refresh, so a council of five deciding one item turns into a
-- steady stream of addon messages from the whole raid.
do
    local sim, _, council = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.inventory[10] = GLOVES
    T.truthy(alric ~= nil)

    RaidSim.ClearLog(sim)
    Ask(council, "INVTYPE_HAND")
    local first = #RaidSim.Sent(sim, "EQUIP:")
    T.truthy(first > 0, "the first ask is answered")

    RaidSim.ClearLog(sim)
    Ask(council, "INVTYPE_HAND")
    Ask(council, "INVTYPE_HAND")
    Ask(council, "INVTYPE_HAND")
    T.eq(#RaidSim.Sent(sim, "EQUIP:"), 0,
        "three more asks in the same moment are answered by nobody")

    -- ...and the cooldown is a pause, not a mute: the next item genuinely needs a fresh answer.
    KARTTEST.AdvanceTime(120)
    RaidSim.ClearLog(sim)
    Ask(council, "INVTYPE_HAND")
    T.truthy(#RaidSim.Sent(sim, "EQUIP:") > 0, "and once it has passed, asking works again")
end

-- A link too long for one message -------------------------------------------------------------------
-- The reply carries an equipped link, and a heavily-crafted one runs well past the cap on its own --
-- 309 bytes for the piece below. It still goes out in 57, because the fallback replaces the link
-- with KAUtil.GetItemString, which keeps the item id and drops the bonus list the length came from.
--
-- Worth measuring rather than assuming: this responder is the third of the addon's 255-byte sites
-- (after the raid config, B107, and the history catch-up, B112) and the only one that resolves it by
-- DROPPING the message. That is right here and wrong there -- a missing comparison renders as "no
-- data" while a missing award is gone from the record -- and it only stays right as long as the
-- fallback keeps producing something short.
--
-- The drop itself has no test and cannot have one: with any real item link the fallback always fits,
-- so the branch is unreachable. Its mutant survives for that reason and not because anything is
-- missing here.
do
    local sim, _, council = F.NewRaid()
    -- A real item with a long bonus list, which is what a max-crafted piece looks like.
    local bonus = {}
    for i = 1, 40 do bonus[i] = tostring(10000 + i) end
    KARTTEST.AddItem({ id = 800001, name = "Beinschienen der endlosen Nacht",
                       quality = 4, ilvl = 291, classID = 4, subclassID = 1,
                       equipLoc = "INVTYPE_LEGS",
                       link = "|cffa335ee|Hitem:800001::::::::80:268::14:" .. #bonus .. ":" ..
                              table.concat(bonus, ",") .. ":::::|h[Beinschienen]|h|r" })
    local link = KARTTEST.items[800001].link
    KARTTEST.inventory[7] = link
    T.truthy(#link > 255, "the equipped link alone is over the cap (" .. #link .. " bytes)")

    RaidSim.ClearLog(sim)
    Ask(council, "INVTYPE_LEGS")
    local replies = RaidSim.Sent(sim, "EQUIP:")
    T.truthy(#replies > 0, "and it is still answered rather than skipped")
    for _, e in ipairs(replies) do
        T.truthy(#e.msg <= 255,
            "with a message that fits (" .. #e.msg .. " bytes), because the fallback drops the " ..
            "bonus list the length came from")
        T.truthy(e.msg:find("item:800001", 1, true),
            "and still names the item, so the asker can look it up")
    end
end

KARTTEST.inventory[10], KARTTEST.inventory[7] = nil, nil
