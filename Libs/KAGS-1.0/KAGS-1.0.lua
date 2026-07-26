-- KAGS-1.0: scans the local player's own gear for missing enchants, empty sockets and weapon
-- oils. Split from the networking library on purpose -- the accepted-enchant tables are a
-- per-patch maintenance item (see docs/REVIEW-DECISIONS.md) and their churn should not bump
-- the network library's version.
--
-- Reads only the local player. Answering another client's request is KASC's job; this library
-- has no knowledge of the network at all.
local MAJOR, MINOR = "KAGS-1.0", 1
local KAGS = LibStub:NewLibrary(MAJOR, MINOR)
if not KAGS then return end

local KAUtil = LibStub("KAUtil-1.0")

-- Hidden scanning tooltip for KAGS.CountMissingGear's socket check below. C_Item.GetItemStats can
-- report a stale EMPTY_SOCKET_* stat for an item that was already gemmed this session (its cached
-- link predates the gem), so we read the socket state straight from the tooltip instead - that's
-- rendered fresh every time and matches exactly what the player sees on hover.
local KART_GearScanTooltip = CreateFrame("GameTooltip", "KART_GearScanTooltip", UIParent, "GameTooltipTemplate")
KART_GearScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Collects the display strings of every "EMPTY_SOCKET_*" global (Prismatic, Red, Cogwheel, ...)
-- instead of hardcoding them, so new socket types added in future patches are picked up automatically.
local emptySocketTexts
local function GetEmptySocketTexts()
    if emptySocketTexts then return emptySocketTexts end
    emptySocketTexts = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and k:match("^EMPTY_SOCKET_") then
            emptySocketTexts[v] = true
        end
    end
    return emptySocketTexts
end

-- Counted rather than boolean: a few raid items drop with two prismatic sockets (the Midnight neck
-- "Hexlord's Choker" and ring "Loop of the Devouring Abyss"), and a player who filled neither needs
-- both reported. The slot id is then listed once per empty socket, which the panel renders as "(x2)".
local function CountEmptySockets(slot)
    KART_GearScanTooltip:ClearLines()
    KART_GearScanTooltip:SetInventoryItem("player", slot)
    local texts = GetEmptySocketTexts()
    local count = 0
    for i = 1, KART_GearScanTooltip:NumLines() do
        local fs = _G["KART_GearScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and texts[text] then count = count + 1 end
    end
    return count
end

-- Accepted enchant ids per inventory slot — the current tier's rank-2 enchants, everything else on
-- that slot counts as wrong. These are the ids from the item link's enchant field
-- (item:ID:ENCHANT:...), NOT the enchanter's spell ids.
-- A slot whose list is missing or empty is only checked for having *some* enchant, so this table can
-- be filled in slot by slot without producing false "wrong enchant" reports in the meantime.
--
-- REBUILT 2026-07-25 from the game's own SpellItemEnchantment table (wago.tools DB2 export), after
-- the hand-written first attempt reported "(wrong enchant)" on all seven armour slots of a fully
-- enchanted character. Every id below was read out of that table by name, and six of them were
-- cross-checked against a live client's item links: 7961 head, 8031 shoulders, 7987 chest, 8159
-- legs, 7993 boots, 7997 rings all matched. Nothing here is from memory.
--
-- ONLY the top craft quality (Tier2) counts, by explicit maintainer decision — a Tier1 craft is
-- reported as the wrong enchant. Midnight enchants are crafting recipes, so each name exists twice
-- in the table, once per quality, with NO fixed offset between them (Sharpened is 7906/7905 while
-- Weighted is 7907/7908). Never derive one tier's id from the other's; look both up.
--
-- Where a slot is in doubt, the id is INCLUDED rather than left out. Wrongly including one can only
-- let a bad enchant pass unnoticed; wrongly leaving one out accuses a player who did everything
-- right, which is the failure this table is recovering from.
--
-- To refresh for a new tier: https://wago.tools/db2/SpellItemEnchantment/csv?filter[Name_lang]=
-- Quality-NN-Tier2 lists a whole expansion's crafted enchants in one request ("12" is Midnight).
-- "/kart ench" prints a live character's ids with their names for cross-checking.
local GOOD_ENCHANTS = {
    -- Head — three enchants, each with a stronger "Empowered" version. Both count: Empowered is a
    -- separate recipe, not a higher craft quality.
    [1]  = { 7959, 7961, 7989, 7991, 8015, 8017 },
    -- Shoulders — two per faction tree (Amani, Haranir, Thalassian).
    [3]  = { 7971, 7973, 7999, 8001, 8029, 8031 },
    -- Chest — Mark of Nalorakk / Rootwarden / Worldsoul / the Magister.
    [5]  = { 7957, 7985, 7987, 8013 },
    -- Legs are NOT enchanted: they take a tailoring spellthread or a leatherworking armour kit, so
    -- these are stat lines rather than named enchants. Caster set first, then agility/strength.
    [7]  = { 7935, 7937, 7939, 8159, 8161, 8163 },
    -- Boots — Lynx's Dexterity, Shaladrassil's Roots, Farstrider's Hunt.
    [8]  = { 7963, 7993, 8019 },
    -- Rings — nine of them, three per faction tree. Both rings take the same set.
    [11] = { 7965, 7967, 7969, 7995, 7997, 8021, 8023, 8025, 8027 },
    [12] = { 7965, 7967, 7969, 7995, 7997, 8021, 8023, 8025, 8027 },
    -- Weapons, and the reason this slot needs the most care: three unrelated professions and one
    -- class all write here.
    --   crafted enchants  7979-8041 : three per faction tree
    --   engineering scopes 8609-8615 : a ranged weapon carries one of these instead
    --   Rite of the Hash'ey    8689 : Midnight, permanent, slot unconfirmed — see the note above on
    --                                 why an uncertain id is included rather than omitted
    --   runeforges 3366-6245       : death knights only, and the ONLY weapon enchant they can use.
    --                                No craft quality, so every one of them is valid. 6241 (Rune of
    --                                Sanguination) is the one confirmed against a live client.
    [16] = { 7979, 7981, 7983, 8007, 8009, 8011, 8037, 8039, 8041,
             8609, 8611, 8613, 8615, 8689,
             3366, 3367, 3368, 3370, 3595, 3847, 5869, 5870,
             6241, 6242, 6243, 6244, 6245 },
    [17] = { 7979, 7981, 7983, 8007, 8009, 8011, 8037, 8039, 8041,
             8609, 8611, 8613, 8615, 8689,
             3366, 3367, 3368, 3370, 3595, 3847, 5869, 5870,
             6241, 6242, 6243, 6244, 6245 },
}

-- Enchantable slots: Head(1), Shoulders(3), Chest(5), Legs(7), Boots(8), Rings(11,12),
-- Main Hand(16), Off Hand(17 — only when it holds a second weapon, see SlotTakesEnchant).
-- Wrist(9) and Back(15) lost their enchants. Shared by KAGS.CountMissingGear, the /kart ench dump
-- and the raid scan, so all three always agree on what "enchantable" means.
KAGS.ENCHANTABLE_SLOTS = {1, 3, 5, 7, 8, 11, 12, 16, 17}

-- Note what must NOT be used to extend the table above: asking the raid what it wears. That returns
-- whatever people have, outdated enchants included, so it would approve precisely the case the check
-- exists to catch. The accepted set comes from the game's own data, never from a survey — see the
-- note in StartEnchantScan (Utils.lua), whose tally is for human eyes only.

-- Equip locations that can carry a temporary weapon enchant (oil, sharpening stone, poison, imbue).
-- A shield or a caster off-hand cannot, and an empty hand has nothing to oil.
local OIL_EQUIP_LOCS = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
}

-- Whether our own `slot` (16 or 17) holds a weapon that is expected to carry an oil. This is what
-- keeps a shield tank and an Arms warrior's empty off-hand out of the oil check while a Fury warrior
-- or a Frost death knight gets both hands checked — the equipped items decide, not the spec.
function KAGS.SlotNeedsOil(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return false end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    return OIL_EQUIP_LOCS[equipLoc] or false
end

-- Off-hand item types that carry no enchant at all in Midnight. Shields lost theirs expansions ago
-- (there is no "Enchant Shield" any more) and caster off-hands never had one — only a second WEAPON
-- in slot 17 is enchantable. Both must be excluded, not just the caster off-hand: an unenchantable
-- item left in the check has an empty enchant field, so it was reported as "enchant missing" on a
-- slot the player cannot do anything about, permanently, for every shield tank and holy paladin.
local NO_ENCHANT_OFFHANDS = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

-- Only slot 17 can hold something unenchantable; every other slot in enchantableSlots is unconditional.
local function SlotTakesEnchant(slot, link)
    if slot ~= 17 then return true end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    return not NO_ENCHANT_OFFHANDS[equipLoc]
end

function KAGS.IsGoodEnchant(slot, enchantID)
    local good = GOOD_ENCHANTS[slot]
    if not good or #good == 0 then return true end -- no list for this slot yet: presence is enough
    local id = tonumber(enchantID)
    for _, v in ipairs(good) do
        if v == id then return true end
    end
    return false
end

-- Funktion zum Zählen fehlender Verzauberungen und leerer Sockelplätze (Retail)
-- Both return values are slot lists: "0" for nothing missing, otherwise comma-separated entries of
-- an inventory slot number, with a "w" suffix marking a slot that has the wrong enchant rather than
-- none at all (e.g. "1,16w"). KARTSync sends these verbatim, so the format is protocol.
function KAGS.CountMissingGear()
    local missingEnchants = {}
    local missingGems = {}

    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and SlotTakesEnchant(slot, link) then
            local enchant = link:match("item:%d+:(%d*):")
            if not enchant or enchant == "" or enchant == "0" then
                table.insert(missingEnchants, tostring(slot))
            elseif not KAGS.IsGoodEnchant(slot, enchant) then
                table.insert(missingEnchants, tostring(slot) .. "w")
            end
        end
    end

    -- Every slot is scanned rather than only the socketable ones (head, neck, waist, wrist, rings):
    -- the tooltip is authoritative, so a socket type appearing on a new slot needs no code change.
    for slot = 1, 17 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            for _ = 1, CountEmptySockets(slot) do
                table.insert(missingGems, tostring(slot))
            end
        end
    end

    local eStr = table.concat(missingEnchants, ",")
    local gStr = table.concat(missingGems, ",")
    if eStr == "" then eStr = "0" end
    if gStr == "" then gStr = "0" end
    return eStr, gStr
end

-- Prints the enchant data this addon actually sees, so GOOD_ENCHANTS above and the oil's bestSpells
-- (BuffChecker.lua) can be filled from real client output instead of from memory — the first attempt
-- at both was guessed and every single id was wrong. Bound to "/kart ench".
--
-- Permanent enchants live in the item link's third field; temporary ones (oil, sharpening stone,
-- shaman imbue, rogue poison) are not in the link at all and come from GetWeaponEnchantInfo, which is
-- why both are printed separately here.
-- Our own enchant state as {[slot] = "id", oil = "id"} — only slots that actually carry one appear.
-- Shared by the /kart ench print and the raid scan's reply, so both report identically.
function KAGS.GetOwnEnchantIDs()
    local out = {}
    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local enchant = link:match("item:%d+:(%d*):")
            if enchant and enchant ~= "" and enchant ~= "0" then out[slot] = enchant end
        end
    end
    -- The oil is a TEMPORARY enchant and never appears in the item link, so it needs its own read.
    local hasMH, _, _, mhID = GetWeaponEnchantInfo()
    if hasMH and mhID and mhID > 0 then out.oil = tostring(mhID) end
    return out
end

-- "1=7961,3=8031,...,oil=8052" — the wire form of the above, for the raid scan's ENCH reply.
function KAGS.SerializeOwnEnchantIDs()
    local ids, parts = KAGS.GetOwnEnchantIDs(), {}
    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        if ids[slot] then parts[#parts + 1] = slot .. "=" .. ids[slot] end
    end
    if ids.oil then parts[#parts + 1] = "oil=" .. ids.oil end
    return table.concat(parts, ",")
end
