local addonName, KART = ...
local LC = KART.LC

-- =====================================================================
--  Tier tokens -> the slot they are worn in
-- =====================================================================
-- A tier token is a Miscellaneous item: C_Item.GetItemInfo answers no equipLoc for one, so the
-- council panel's equipped-gear comparison had nothing to look up and gave up -- on exactly the
-- drops the council argues hardest about (Manifest C12). Only the item's own tooltip knows the
-- slot, and the tooltip is written in the client's language.
--
-- So the slot comes out of a table of item ids instead. The data below is taken from
-- RCLootCouncil2's Utils/tokenData.lua (github.com/evil-morfar/RCLootCouncil2, MIT), translated
-- from its own slot names into the INVTYPE_* tokens this addon already keys its slot map on.
--
-- Deliberately NOT adopted from there: its fallback that guesses the slot from tooltip keywords
-- ("helm", "shoulder", ...). Those keywords are enUS, and half this raid runs a German client --
-- a wrong guess would put somebody else's gear on the row that hands the item out. A token this
-- table does not know keeps the old behaviour: an empty column.
--
-- Two-slot items need no special case here: INVTYPE_FINGER and INVTYPE_TRINKET already map to both
-- of their slots in the panel's own EQUIP_LOC_TO_SLOT, so a ring or trinket token would simply
-- carry that INVTYPE and be compared against both.
local TOKEN_EQUIP_LOC = {
    -- Midnight, tier 1 (Riftbloom / Nullcore)
    [249347] = "INVTYPE_CHEST",    -- Alnwoven Riftbloom
    [249348] = "INVTYPE_CHEST",    -- Alncured Riftbloom
    [249349] = "INVTYPE_CHEST",    -- Alncast Riftbloom
    [249350] = "INVTYPE_CHEST",    -- Alnforged Riftbloom
    [249351] = "INVTYPE_HAND",     -- Voidwoven Hungering Nullcore
    [249352] = "INVTYPE_HAND",     -- Voidcured Hungering Nullcore
    [249353] = "INVTYPE_HAND",     -- Voidcast Hungering Nullcore
    [249354] = "INVTYPE_HAND",     -- Voidforged Hungering Nullcore
    [249355] = "INVTYPE_HEAD",     -- Voidwoven Fanatical Nullcore
    [249356] = "INVTYPE_HEAD",     -- Voidcured Fanatical Nullcore
    [249357] = "INVTYPE_HEAD",     -- Voidcast Fanatical Nullcore
    [249358] = "INVTYPE_HEAD",     -- Voidforged Fanatical Nullcore
    [249359] = "INVTYPE_LEGS",     -- Voidwoven Corrupted Nullcore
    [249360] = "INVTYPE_LEGS",     -- Voidcured Corrupted Nullcore
    [249361] = "INVTYPE_LEGS",     -- Voidcast Corrupted Nullcore
    [249362] = "INVTYPE_LEGS",     -- Voidforged Corrupted Nullcore
    [249363] = "INVTYPE_SHOULDER", -- Voidwoven Unraveled Nullcore
    [249364] = "INVTYPE_SHOULDER", -- Voidcured Unraveled Nullcore
    [249365] = "INVTYPE_SHOULDER", -- Voidcast Unraveled Nullcore
    [249366] = "INVTYPE_SHOULDER", -- Voidforged Unraveled Nullcore
}

-- The slot a tier token is worn in, or nil for anything this table does not know.
function LC.GetTokenEquipLoc(itemID)
    return TOKEN_EQUIP_LOC[tonumber(itemID) or 0]
end
