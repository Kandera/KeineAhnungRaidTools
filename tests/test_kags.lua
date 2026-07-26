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
T.eq(KAGS.SlotNeedsOil(16), false, "an empty hand needs no oil")
T.eq(KAGS.SlotNeedsOil(17), false, "an empty off hand needs no oil")

-- SerializeOwnEnchantIDs -------------------------------------------------------------
-- Format contract, because this string goes on the wire: "slot=id" pairs joined by commas,
-- plus an "oil=id" entry for the temporary weapon enchant. The receiving parser in KASC
-- rejects the whole message on one malformed entry, so the shape must not drift.
KARTTEST.inventory = {}
KARTTEST.weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
local serialized = KAGS.SerializeOwnEnchantIDs()
T.eq(type(serialized), "string", "SerializeOwnEnchantIDs returns a string")
for entry in serialized:gmatch("[^,]+") do
    T.truthy(entry:match("^%w+=%d+$"), "every serialized entry matches key=digits: " .. entry)
end
