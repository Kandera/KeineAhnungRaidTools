local KAUtil = LibStub("KAUtil-1.0")

-- TrimString -------------------------------------------------------------------------
T.eq(KAUtil.TrimString("  hi  "), "hi", "TrimString strips both ends")
T.eq(KAUtil.TrimString("hi"), "hi", "TrimString leaves a clean string alone")
T.eq(KAUtil.TrimString("   "), "", "TrimString collapses whitespace-only to empty")

-- CaseFold ---------------------------------------------------------------------------
T.eq(KAUtil.CaseFold("ABC"), "abc", "CaseFold lowers ASCII")
T.eq(KAUtil.CaseFold("ÖLmann"), "ölmann", "CaseFold folds the German umlaut :lower() misses")
T.eq(KAUtil.CaseFold("Éclair"), "éclair", "CaseFold folds accented Latin-1 used by NSRT nicknames")
T.eq(KAUtil.CaseFold(42), 42, "CaseFold passes non-strings through unchanged")

-- SplitString ------------------------------------------------------------------------
T.deep_eq(KAUtil.SplitString("a;b;c", ";"), { "a", "b", "c" }, "SplitString splits on the separator")
T.deep_eq(KAUtil.SplitString("a b", nil), { "a", "b" }, "SplitString defaults to whitespace")
T.deep_eq(KAUtil.SplitString("a;;b", ";"), { "a", "b" }, "SplitString drops empty fields")

-- Item links -------------------------------------------------------------------------
local LINK = "|cffa335ee|Hitem:12345:7961::::::::80:::::|h[Test Blade]|h|r"
T.truthy(KAUtil.IsRealItemLink(LINK), "IsRealItemLink accepts a real link")
T.eq(KAUtil.IsRealItemLink("|cff00ff00Fake Item|r"), false, "IsRealItemLink rejects a coloured test string")
T.eq(KAUtil.IsRealItemLink(nil), false, "IsRealItemLink rejects nil")
T.eq(KAUtil.GetItemString(LINK), "item:12345:7961::::::::80:::::", "GetItemString keeps every bonus id")
T.is_nil(KAUtil.GetItemString("|cff00ff00Fake Item|r"), "GetItemString returns nil for a non-link")

-- EachGroupUnit ----------------------------------------------------------------------
KARTTEST.SetRaid({ { name = "Ann" }, { name = "Bob" }, { name = "Cid" } })
local units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "raid1", "raid2", "raid3" }, "EachGroupUnit yields raid tokens in a raid")

KARTTEST.SetParty({ { name = "Ann" }, { name = "Bob" }, { name = "Me" } })
units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "party1", "party2", "player" }, "EachGroupUnit yields player last in a party")

-- IsFullNameInGroup ------------------------------------------------------------------
-- The security gate. Realm is compared canonically on both sides: the sender is always
-- realm-qualified with the normalized spelling, while UnitName returns nil for a same-realm
-- unit and the display spelling ("Tarren Mill") for a cross-realm one.
KARTTEST.realm = "TarrenMill"
KARTTEST.SetRaid({
    { name = "Ann" },                              -- same realm, UnitName realm is nil
    { name = "Bob", realm = "Tarren Mill" },       -- display spelling of our own realm
    { name = "Cid", realm = "Silvermoon" },        -- genuinely cross-realm
})
T.truthy(KAUtil.IsFullNameInGroup("Ann-TarrenMill"), "same-realm member matches despite a nil unit realm")
T.truthy(KAUtil.IsFullNameInGroup("Bob-TarrenMill"), "display realm spelling canonicalizes to the same realm")
T.truthy(KAUtil.IsFullNameInGroup("Cid-Silvermoon"), "cross-realm member matches on its own realm")
T.eq(KAUtil.IsFullNameInGroup("Cid-TarrenMill"), false, "same short name on the wrong realm is rejected")
T.eq(KAUtil.IsFullNameInGroup("Dan-TarrenMill"), false, "a non-member is rejected")
T.eq(KAUtil.IsFullNameInGroup(""), false, "empty input is rejected")
T.eq(KAUtil.IsFullNameInGroup(nil), false, "nil input is rejected")
T.truthy(KAUtil.IsFullNameInGroup("ANN-tarrenmill"), "matching is case-insensitive on both parts")

-- DeepCopy / MergeDefaults -----------------------------------------------------------
local src = { a = 1, nested = { b = 2 } }
local copy = KAUtil.DeepCopy(src)
copy.nested.b = 99
T.eq(src.nested.b, 2, "DeepCopy does not share nested tables with the source")

local dst = { keep = "mine", nested = { existing = 1 } }
KAUtil.MergeDefaults(dst, { keep = "default", added = "new", nested = { existing = 9, fresh = 3 } })
T.eq(dst.keep, "mine", "MergeDefaults never overwrites an existing value")
T.eq(dst.added, "new", "MergeDefaults fills a missing top-level key")
T.eq(dst.nested.existing, 1, "MergeDefaults never overwrites a nested existing value")
T.eq(dst.nested.fresh, 3, "MergeDefaults fills a missing key inside an existing nested table")

local defaults = { nested = { x = 1 } }
local fresh = {}
KAUtil.MergeDefaults(fresh, defaults)
fresh.nested.x = 42
T.eq(defaults.nested.x, 1, "MergeDefaults deep-copies table defaults instead of sharing them")
