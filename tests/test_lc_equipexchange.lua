-- What a raider answers when a council panel asks what they are wearing.
--
-- REQ_EQUIP goes out while a council member looks at an item; every raider in the group answers with
-- their own equipped link for that slot, and the panel shows the comparison. Two decisions in that
-- responder survived being mutated away, and both are about not flooding or misleading the asker.
--
-- This used to be the third of the addon's 255-byte sites, after the raid config (B107) and the
-- history catch-up (B112), and the one that resolved it by DROPPING the reply. The transport splits
-- and reassembles now, so the responder carries no cap guard of its own any more (B127).

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
-- 309 bytes for the piece below. It used to go out in 57, shortened by KAUtil.GetItemString, and be
-- dropped outright if even that would not fit: the transport truncated an over-cap message into
-- garbage, and a wrong comparison is worse than none.
--
-- The transport splits and reassembles now (see KASC:Send / AceComm), so the reply goes out WHOLE,
-- in several chunks, and arrives as one message -- which is what the link itself is measured against
-- here. The old shortening only ever worked because GetItemString was dropping the bonus list by
-- accident (B127), and with that fixed there is nothing short left for it to fall back to anyway.
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
    -- RaidSim.Messages, not RaidSim.Sent: this one leaves as several chunks, and only the first
    -- carries the token (see there).
    T.truthy(#RaidSim.Messages(sim, "EQUIP:") > 0, "and it is still answered rather than skipped")
    -- What actually matters is what the ASKER ended up holding: the whole link, bonus list and all,
    -- reassembled -- not a shortened stand-in it would have to rebuild an item from.
    RaidSim.As(council, function()
        local cached
        for _, slots in pairs(council.KART.EquipCache or {}) do
            cached = cached or slots["INVTYPE_LEGS"]
        end
        T.eq(cached, link, "and the asker holds the link whole, every bonus id intact")
    end)
end

KARTTEST.inventory[10], KARTTEST.inventory[7] = nil, nil
