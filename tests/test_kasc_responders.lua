-- KASC-1.0's four responders (REQ_OIL, REQ_ILVL, REQ_ENCH, REQ_GEAR) answer another client's
-- request with our own gear state. They are pure enough to drive through KASC.Dispatch and
-- assert the literal payload KARTTEST.sent records -- the exact string, not just "something
-- was sent" -- exactly like tests/test_sync.lua already does for the handshake tokens.
local KASC = LibStub("KASC-1.0")

-- Every block below resets the roster/realm and the whole gear-scan state first, since
-- tests/run.lua shares one global environment across every test file (see wow_stubs.lua) and
-- these responders read every one of KARTTEST.inventory, .equipLocs, .weaponEnchant,
-- .tooltipLines and .equippedIlvl.
local function ResetGearState()
    KARTTEST.inventory = {}
    KARTTEST.equipLocs = {}
    KARTTEST.weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
    KARTTEST.tooltipLines = {}
    KARTTEST.equippedIlvl = nil
end

local function ResetGroup()
    KARTTEST.realm = "TarrenMill"
    KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })
end

-- =====================================================================================
--  REQ_OIL -- the three distinguishable states, combined differently on each hand
-- =====================================================================================

-- Main hand carries an oil, off hand is empty (cannot take an oil at all).
ResetGroup()
ResetGearState()
KARTTEST.inventory[16] = "item:212030:0:"
KARTTEST.equipLocs["item:212030:0:"] = "INVTYPE_WEAPONMAINHAND"
-- Slot 17 is left with no item link at all, so SlotNeedsOil(17) short-circuits to false.
KARTTEST.weaponEnchant = { true, 0, 0, 8052, false, 0, 0, 0 }
KARTTEST.ClearSent()
KASC.Dispatch("REQ_OIL", "RAID", "Ann-TarrenMill")
T.eq(#KARTTEST.sent, 1, "REQ_OIL from a group member produces exactly one reply")
T.eq(KARTTEST.sent[1].msg, "OIL:8052:n",
    "an oiled main hand reports its enchant id, and an empty off hand reports the no-oil-possible marker")
T.eq(KARTTEST.sent[1].channel, "RAID", "the OIL reply broadcasts to the group channel")
T.is_nil(KARTTEST.sent[1].target, "the OIL reply is not whispered back to the requester")

-- Main hand carries a weapon with no oil on it, off hand carries a different oil.
ResetGearState()
local mh, oh = "item:212040:0:", "item:212041:0:"
KARTTEST.inventory[16] = mh
KARTTEST.inventory[17] = oh
KARTTEST.equipLocs[mh] = "INVTYPE_WEAPONMAINHAND"
KARTTEST.equipLocs[oh] = "INVTYPE_WEAPONOFFHAND"
KARTTEST.weaponEnchant = { false, 0, 0, 0, true, 0, 0, 9001 }
KARTTEST.ClearSent()
KASC.Dispatch("REQ_OIL", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "OIL:0:9001",
    "an unoiled main-hand weapon reports 0, distinct from the off hand's own oil id")

-- Main hand is empty, off hand holds a shield -- neither hand can take an oil at all.
ResetGearState()
local shield = "item:212050:0:"
KARTTEST.inventory[17] = shield
KARTTEST.equipLocs[shield] = "INVTYPE_SHIELD"
KARTTEST.ClearSent()
KASC.Dispatch("REQ_OIL", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "OIL:n:n",
    "an empty main hand and a shielded off hand both report the no-oil-possible marker, not 0")

-- =====================================================================================
--  REQ_ILVL -- the numeric formatting, not merely that a number appears
-- =====================================================================================

ResetGearState()
KARTTEST.equippedIlvl = 605.3
KARTTEST.ClearSent()
KASC.Dispatch("REQ_ILVL", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "ILVL:605.3", "the item level reply keeps exactly one decimal place")

ResetGearState()
KARTTEST.equippedIlvl = 620
KARTTEST.ClearSent()
KASC.Dispatch("REQ_ILVL", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "ILVL:620.0", "a whole-number item level still gets a trailing .0")

-- =====================================================================================
--  REQ_ENCH -- the serialised payload for a known equipped state
-- =====================================================================================

ResetGearState()
KARTTEST.inventory[1] = "item:212000:7961:" -- head, a confirmed good enchant
KARTTEST.inventory[3] = "item:212001:0:"    -- shoulders, no enchant applied
KARTTEST.weaponEnchant = { true, 0, 0, 8052, false, 0, 0, 0 } -- main-hand oil, no off-hand oil
KARTTEST.ClearSent()
KASC.Dispatch("REQ_ENCH", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "ENCH:1=7961,oil=8052",
    "the ENCH reply serializes the enchanted slot and the temporary weapon oil, and omits the bare slot")

-- =====================================================================================
--  REQ_GEAR -- the two-slot-list format the receiving parser validates
-- =====================================================================================

-- A missing enchant, a wrong enchant (w suffix) and a slot repeated for two empty sockets.
ResetGearState()
KARTTEST.inventory[1]  = "item:212000:9999:" -- head, enchanted with an id not in GOOD_ENCHANTS[1]
KARTTEST.inventory[3]  = "item:212001:0:"    -- shoulders, no enchant at all
KARTTEST.inventory[11] = "item:212002:7965:" -- ring, a good enchant, but two empty sockets
KARTTEST.tooltipLines[11] = { "Prismatic Socket", "Prismatic Socket" }
KARTTEST.ClearSent()
KASC.Dispatch("REQ_GEAR", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "GEAR:1w,3:11,11",
    "a wrong enchant, a missing enchant and a doubly-socketed slot all reach the wire, in that list format")

-- Nothing missing: every enchantable slot holds an accepted enchant and no sockets are empty.
ResetGearState()
KARTTEST.inventory = {
    [1]  = "item:220001:7961:",
    [3]  = "item:220003:7973:",
    [5]  = "item:220005:7957:",
    [7]  = "item:220007:7935:",
    [8]  = "item:220008:7963:",
    [11] = "item:220011:7965:",
    [12] = "item:220012:7965:",
    [16] = "item:220016:7979:",
    [17] = "item:220017:7979:",
}
KARTTEST.equipLocs["item:220016:7979:"] = "INVTYPE_WEAPONMAINHAND"
KARTTEST.equipLocs["item:220017:7979:"] = "INVTYPE_WEAPONOFFHAND"
KARTTEST.ClearSent()
KASC.Dispatch("REQ_GEAR", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1].msg, "GEAR:0:0", "fully enchanted gear with no empty sockets reports nothing missing")

-- =====================================================================================
--  The group gate -- a disclosure control, not just an authority one. The addon-message
--  prefix is public and CHAT_MSG_ADDON also delivers WHISPER and GUILD, so literally any
--  player can send these requests; answering one from outside the group would hand a
--  stranger our own gear, enchant and item-level state.
-- =====================================================================================

ResetGroup()
ResetGearState()
KARTTEST.equippedIlvl = 599.9

-- Positive control first: the same request from a genuine group member IS answered, so the
-- rejections below prove the gate is closing a door that would otherwise be open, not that
-- the responder is simply broken.
KARTTEST.ClearSent()
KASC.Dispatch("REQ_ILVL", "RAID", "Ann-TarrenMill")
T.eq(KARTTEST.sent[1] and KARTTEST.sent[1].msg, "ILVL:599.9",
    "a genuine group member's request is answered")

KARTTEST.ClearSent()
KASC.Dispatch("REQ_ILVL", "WHISPER", "Stranger-Silvermoon")
T.eq(#KARTTEST.sent, 0, "a whispered request from a sender outside the group produces no reply at all")

-- The realm is what makes this a real gate rather than a name check: identity resolution is
-- short-name based, so without the realm comparison an out-of-group sender sharing a group
-- member's short name would resolve onto that member's GUID and pass every authority check.
KARTTEST.ClearSent()
KASC.Dispatch("REQ_ILVL", "WHISPER", "Ann-Silvermoon")
T.eq(#KARTTEST.sent, 0,
    "a same-short-name sender on a different realm is rejected, not resolved onto the real member")
