local KASC = LibStub("KASC-1.0")
local Identity = KASC.Identity

local cache = {}
KASC:AttachCache(cache)

-- Resolution branch 1: a live unit token ------------------------------------------------
KARTTEST.SetNSAPI(false)
KARTTEST.SetRaid({ { name = "Ann", guid = "Player-1234-AAAA" } })
local key, pending = Identity.ResolvePlayer("raid1")
T.eq(key, "Player-1234-AAAA", "a unit token resolves to its GUID")
T.eq(pending, false, "a unit token is never pending")
T.truthy(cache["Player-1234-AAAA"], "resolving a unit writes it into the attached cache")
T.eq(cache["Player-1234-AAAA"].name, "Ann", "the cached name is the realm-free short name")

-- Resolution branch 2: a live name ------------------------------------------------------
key, pending = Identity.ResolvePlayer("Ann-TarrenMill")
T.eq(key, "Player-1234-AAAA", "a realm-qualified sender resolves against the live group")
T.eq(pending, false, "a live name match is not pending")
T.eq(Identity.ResolvePlayer("ann"), "Player-1234-AAAA", "free-typed config text matches case-insensitively")

-- Resolution branch 3: the cache fallback -----------------------------------------------
KARTTEST.SetRaid({})
key, pending = Identity.ResolvePlayer("Ann")
T.eq(key, "Player-1234-AAAA", "someone no longer in the group resolves from the cache")
T.eq(pending, false, "a cache hit is not pending")

-- Resolution branch 4: pending ----------------------------------------------------------
key, pending = Identity.ResolvePlayer("Nobody")
T.eq(key, "nobody", "an unknown name yields trimmed, case-folded placeholder text")
T.eq(pending, true, "an unknown name is pending")
T.eq(Identity.IsResolvedKey("nobody"), false, "placeholder text is not a resolved key")
T.truthy(Identity.IsResolvedKey("Player-1234-AAAA"), "a GUID is a resolved key")

-- NSRT nicknames ------------------------------------------------------------------------
-- Load-bearing for Auto-Promote, the council member list, the lootmaster field and the
-- council panel's name column.
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Bob", guid = "Player-1234-BBBB", nickname = "Bobby" } })
local folded, original = Identity.GetNickname("raid1")
T.eq(folded, "bobby", "GetNickname returns the case-folded nickname first")
T.eq(original, "Bobby", "GetNickname returns the original casing second")
T.eq(Identity.ResolvePlayer("Bobby"), "Player-1234-BBBB", "a nickname resolves to the GUID")
T.eq(Identity.ResolvePlayer("bobby"), "Player-1234-BBBB", "nickname matching is case-insensitive")

KARTTEST.SetRaid({ { name = "Cid", guid = "Player-1234-CCCC", nickname = "Cid" } })
T.is_nil(Identity.GetNickname("raid1"), "NSAPI echoing the real name means no nickname is set")

KARTTEST.SetNSAPI(false)
T.is_nil(Identity.GetNickname("raid1"), "no NSRT installed means no nickname")

-- Umlaut nickname, the reason CaseFold exists ---------------------------------------------
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Dan", guid = "Player-1234-DDDD", nickname = "Öl" } })
T.eq(Identity.ResolvePlayer("öl"), "Player-1234-DDDD", "an umlaut nickname matches in either case")

-- Display names ---------------------------------------------------------------------------
T.eq(Identity.ResolveDisplayName("Player-1234-DDDD"), "Dan", "a live key renders as the unit name")
KARTTEST.SetRaid({})
T.eq(Identity.ResolveDisplayName("Player-1234-BBBB"), "Bobby", "an offline key renders from the cache nickname")
T.eq(Identity.ResolveDisplayName("Player-9999-ZZZZ"), "Player-9999-ZZZZ", "an unknown key renders as itself")

-- Multiple attached caches ------------------------------------------------------------------
local second = {}
KASC:AttachCache(second)
KASC:AttachCache(second) -- attaching twice must not duplicate
KARTTEST.SetNSAPI(false)
KARTTEST.SetRaid({ { name = "Eve", guid = "Player-1234-EEEE" } })
Identity.ResolvePlayer("raid1")
T.truthy(cache["Player-1234-EEEE"], "a write reaches the first attached cache")
T.truthy(second["Player-1234-EEEE"], "a write reaches every attached cache")
