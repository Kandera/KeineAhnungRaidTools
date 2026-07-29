-- Which items are collectibles that must stay out of Loot Council entirely.
--
-- The offline harness loads libraries, not addon files, so this lifts LC.IsCollectibleItem out of
-- the source and compiles just that, the same way test_lc_votewire.lua does with ParseVotePayload.
--
-- What makes this worth testing: the rule used to be `classID == 15` and that silently excluded
-- every tier token in the game from Loot Council -- no ForceWinRoll for the lootmaster, no Auto-Pass
-- for the raiders, on the most contested drop in the instance. The fixtures below are real,
-- measured values from the guild's own RCLootCouncil history rather than invented ones: the sixteen
-- Midnight Nullcore tokens are classID 15 / subclass 0, and the raid's mount (Ashes of Belo'ren,
-- 246590) is classID 15 / subclass 5. A regression here is invisible in-game until a token drops.

local source = assert(io.open("LootCouncil.lua", "r"))
local text = source:read("*a")
source:close()

local fn = text:match("\nfunction LC%.IsCollectibleItem%(itemID, classID, subclassID%).-\nend\n")
T.truthy(fn, "IsCollectibleItem was found in LootCouncil.lua")

-- The journals as chunk upvalues, so each case controls exactly what they answer. Each starts empty;
-- a test fills the one it cares about.
local preamble = [[
local LC = {}
local mounts, pets, toys = {}, {}, {}
local C_MountJournal = { GetMountFromItem      = function(id) return mounts[id] end }
local C_PetJournal   = { GetPetInfoByItemID    = function(id) return pets[id] end }
local C_ToyBox       = { GetToyInfo            = function(id) return toys[id] end }
]]

local chunk = assert(loadstring(preamble .. fn .. "\nreturn LC, mounts, pets, toys"))
local LC, mounts, pets, toys = chunk()
T.eq(type(LC.IsCollectibleItem), "function", "IsCollectibleItem compiles standalone")

local MISC = 15

-- Tier tokens: the whole point ----------------------------------------------------------------------
-- classID 15 / subclass 0, in no journal. These MUST reach Council.
for id = 249351, 249366 do
    T.eq(LC.IsCollectibleItem(id, MISC, 0), false, "tier token " .. id .. " is not a collectible")
end

-- Collectibles by subclass ---------------------------------------------------------------------------
T.eq(LC.IsCollectibleItem(246590, MISC, 5), true, "Ashes of Belo'ren (subclass 5) is a mount")
T.eq(LC.IsCollectibleItem(1, MISC, 2), true, "subclass 2 is a battle pet")
T.eq(LC.IsCollectibleItem(1, MISC, 6), true, "subclass 6 is mount equipment")

-- Collectibles the subclass does not catch, but the journals do --------------------------------------
mounts[500] = 42
T.eq(LC.IsCollectibleItem(500, MISC, 0), true, "an item the mount journal claims is a collectible")
pets[501] = "Critter"
T.eq(LC.IsCollectibleItem(501, MISC, 0), true, "an item the pet journal claims is a collectible")
toys[502] = 502
T.eq(LC.IsCollectibleItem(502, MISC, 0), true, "an item the toy box claims is a collectible")
-- ...and none of those lookups may drag a token in with them.
T.eq(LC.IsCollectibleItem(249364, MISC, 0), false, "a token is still not a collectible once the journals hold entries")

-- Everything outside Miscellaneous is decided before any journal is consulted -------------------------
mounts[600] = 43 -- would say "mount" if it were ever asked
T.eq(LC.IsCollectibleItem(600, 4, 0), false, "armor (classID 4) is never a collectible")
T.eq(LC.IsCollectibleItem(600, 2, 0), false, "a weapon (classID 2) is never a collectible")

-- Anything else in Miscellaneous stays out without being enumerated ------------------------------------
-- This is the property that matters: the rule must not need teaching about each new compartment
-- Blizzard adds. Housing decor got force-won by the lootmaster when this was a deny-list.
T.eq(LC.IsCollectibleItem(700, MISC, 7), true, "an unknown subclass 7 stays out of Council")
T.eq(LC.IsCollectibleItem(701, MISC, 12), true, "so does an unknown subclass 12")
T.eq(LC.IsCollectibleItem(nil, MISC, 5), true, "subclass 5 alone is enough to exclude a mount, no itemID needed")

-- Unresolved data stays out too, in this class alone ---------------------------------------------------
-- GetItemInfoInstant answers from the client database for any real link, so this is close to
-- unreachable -- but "out" is the direction that cannot force-win someone's furniture.
T.eq(LC.IsCollectibleItem(nil, MISC, nil), true, "an unresolved Miscellaneous item stays out")
T.eq(LC.IsCollectibleItem(249364, MISC, nil), true, "even a known token stays out while its subclass is unknown")
T.eq(LC.IsCollectibleItem(nil, MISC, 0), true, "subclass 0 without an itemID cannot be told from a toy, so it stays out")
-- Outside Miscellaneous nothing changes: unresolved still means "ordinary gear, let Council have it".
T.eq(LC.IsCollectibleItem(nil, nil, nil), false, "an entirely unresolved item is not a collectible")
