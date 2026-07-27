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

-- EachItemLink -------------------------------------------------------------------------
local function collectLinks(text)
    local out = {}
    for link in KAUtil.EachItemLink(text) do out[#out + 1] = link end
    return out
end

local MODERN_LINK = "|cnIQ4:|Hitem:19019::::::::80:::::|h[Thunderfury]|h|r"
local COMMA_LINK = "|cff0070dd|Hitem:19019:0:0:0:0:0:0:0:60:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
local SPELL = "|cff71d5ff|Hspell:12345|h[Fireball]|h|r"

T.deep_eq(collectLinks(MODERN_LINK), { MODERN_LINK },
    "EachItemLink accepts a modern named-colour-escape link")
T.deep_eq(collectLinks(LINK), { LINK }, "EachItemLink accepts a legacy hex-colour-escape link")
T.deep_eq(collectLinks(LINK .. " " .. MODERN_LINK), { LINK, MODERN_LINK },
    "EachItemLink yields several links pasted in one string")
T.deep_eq(collectLinks(COMMA_LINK), { COMMA_LINK },
    "EachItemLink keeps an item name containing a comma and spaces intact")
T.deep_eq(collectLinks("no item link here"), {}, "EachItemLink yields nothing for text with no link")
T.deep_eq(collectLinks(SPELL), {}, "EachItemLink ignores a spell link")
T.deep_eq(collectLinks(SPELL .. " " .. LINK), { LINK }, "EachItemLink does not swallow a preceding spell link")

-- EachGroupUnit ----------------------------------------------------------------------
KARTTEST.SetRaid({ { name = "Ann" }, { name = "Bob" }, { name = "Cid" } })
local units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "raid1", "raid2", "raid3" }, "EachGroupUnit yields raid tokens in a raid")

KARTTEST.SetParty({ { name = "Ann" }, { name = "Bob" }, { name = "Me" } })
units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "party1", "party2", "player" }, "EachGroupUnit yields player last in a party")

-- Solo. GetNumGroupMembers reports 0 here, which used to make the iterator yield nothing at all --
-- see B7: the player's own name and nickname then resolved through nothing, so a lootmaster who had
-- entered themselves stayed unresolvable and every loot-owner control stayed greyed out.
KARTTEST.SetParty({})
units = {}
for unit in KAUtil.EachGroupUnit() do units[#units + 1] = unit end
T.deep_eq(units, { "player" }, "EachGroupUnit yields the player alone when solo")

-- CanonRealm ---------------------------------------------------------------------------
-- Exported (not file-local) so other callers can reuse this exact realm-normalization (see
-- docs/BACKLOG.md B15) — IsFullNameInGroup below already exercises it indirectly, this covers the
-- primitive itself directly.
T.eq(KAUtil.CanonRealm("Tarren Mill"), KAUtil.CanonRealm("TarrenMill"),
    "CanonRealm folds the display spelling to the same value as the normalized one")
T.eq(KAUtil.CanonRealm(nil), "", "CanonRealm treats a nil realm as blank")
T.eq(KAUtil.CanonRealm("O'Realm"), "orealm", "CanonRealm strips apostrophes too, then case-folds")

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
