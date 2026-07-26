local KAGS = LibStub("KAGS-1.0")

-- ENCHANTABLE_SLOTS ------------------------------------------------------------------
-- Wrist(9) and Back(15) lost their enchants; Legs(7) takes a spellthread or armour kit but
-- still reports through this list. Off hand(17) is included and filtered per item by
-- SlotNeedsOil / SlotTakesEnchant, not by omission here.
T.deep_eq(KAGS.ENCHANTABLE_SLOTS, { 1, 3, 5, 7, 8, 11, 12, 16, 17 }, "enchantable slot list is unchanged")

-- IsGoodEnchant ----------------------------------------------------------------------
T.truthy(KAGS.IsGoodEnchant(1, 7961), "a confirmed head enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(5, 7987), "a confirmed chest enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(11, 7997), "a confirmed ring enchant id is accepted")
T.truthy(KAGS.IsGoodEnchant(16, 6241), "a death knight runeforge is accepted on a weapon")
T.eq(KAGS.IsGoodEnchant(1, 12345), false, "an unknown id on a listed slot is rejected")
-- A slot with no list falls back to a presence-only check, so the table can be filled in one
-- slot at a time without accusing correctly enchanted players in the meantime.
T.truthy(KAGS.IsGoodEnchant(9, 12345), "a slot with no list accepts any enchant")

-- SlotNeedsOil -----------------------------------------------------------------------
-- The equipped item decides, not the spec: a shield tank and an Arms warrior's empty off
-- hand stay out of the oil check while a Fury warrior gets both hands checked.
KARTTEST.inventory = {}
KARTTEST.equipLocs = {}
T.eq(KAGS.SlotNeedsOil(16), false, "an empty hand needs no oil")
T.eq(KAGS.SlotNeedsOil(17), false, "an empty off hand needs no oil")

do
    local mh, shield, held = "item:212030:0:", "item:212031:0:", "item:212032:0:"
    KARTTEST.equipLocs = {
        [mh]     = "INVTYPE_WEAPONMAINHAND", -- a Fury warrior's main-hand weapon
        [shield] = "INVTYPE_SHIELD",         -- a tank's off-hand shield
        [held]   = "INVTYPE_HOLDABLE",       -- a caster's off-hand tome/relic
    }

    KARTTEST.inventory = { [16] = mh }
    T.truthy(KAGS.SlotNeedsOil(16), "a one-handed weapon takes oil")

    KARTTEST.inventory = { [17] = shield }
    T.eq(KAGS.SlotNeedsOil(17), false, "a shield does not take oil")

    KARTTEST.inventory = { [17] = held }
    T.eq(KAGS.SlotNeedsOil(17), false, "a held caster off-hand does not take oil")
end

-- SerializeOwnEnchantIDs -------------------------------------------------------------
-- Format contract, because this string goes on the wire: "slot=id" pairs joined by commas,
-- plus an "oil=id" entry for the temporary weapon enchant. The receiving parser in KASC
-- rejects the whole message on one malformed entry, so the shape must not drift.
do
    KARTTEST.equipLocs = {}
    KARTTEST.inventory = {
        [1] = "item:212000:7961:", -- head, enchanted with a confirmed good id
        [3] = "item:212001:0:",    -- shoulders, no enchant applied
    }
    -- GetWeaponEnchantInfo's 4th return is the main-hand temporary enchant's spell id.
    KARTTEST.weaponEnchant = { true, 3000, 0, 8052, false, 0, 0, 0 }
    T.eq(KAGS.SerializeOwnEnchantIDs(), "1=7961,oil=8052",
        "an enchanted slot, an unenchanted slot and a weapon oil serialize to slot=id pairs plus oil=id")
end

-- CountMissingGear --------------------------------------------------------------------
-- Output shape is a protocol: comma-separated slot numbers, a "w" suffix for a present-but-
-- wrong enchant (a bare slot number for a missing one), and a slot repeated once per empty
-- socket on that item.
do
    KARTTEST.equipLocs = {}
    KARTTEST.inventory = {
        [1]  = "item:212000:9999:", -- head, enchanted with an id not in GOOD_ENCHANTS[1]
        [3]  = "item:212001:0:",    -- shoulders, no enchant at all
        [11] = "item:212002:7965:", -- ring, a confirmed good enchant, but two empty sockets
    }
    KARTTEST.tooltipLines = {
        [11] = { "Prismatic Socket", "Prismatic Socket" },
    }
    local enchants, gems = KAGS.CountMissingGear()
    T.eq(enchants, "1w,3", "a wrong enchant gets a w suffix, a missing one stays bare")
    T.eq(gems, "11,11", "a slot with two empty sockets is listed twice")
end
