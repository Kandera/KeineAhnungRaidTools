-- Droptimizer: the gain% column, read out of KART_WoWUtilsCache.
--
-- That table is the only thing in this addon written by SOMEBODY ELSE -- the external KART Companion
-- app -- and it is two thirds of a real player's SavedVariables file (measured 2026-08-01: 50.9 KB of
-- 75.5). Every assumption this module makes about its shape is an assumption about another program's
-- output, and none of them had a single test: the module had never executed in the harness at all,
-- which the missing C_Item.GetDetailedItemLevelInfo stub proves -- the first line of GetGainPercent
-- that reaches it would have thrown.
--
-- Loaded standalone, the way test_lc_relevance compiles DecideAutoResponse out of its file: the
-- module is not in raidsim's CLIENT_FILES, and its two build functions at the bottom are guarded on
-- panels that do not exist here, so a bare KART table is enough.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = { dtModuleEnabled = true }
env.KART_WoWUtilsCache = nil
local KART = {}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("Droptimizer.lua", "r")):read("*a"), "@Droptimizer.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
local DT = KART.DT
T.truthy(DT and DT.GetGainPercent, "Droptimizer loads standalone")

-- Two items to look up. The second exists at two upgrade levels, which is the case the companion's
-- cache genuinely produces and the reason GetGainPercent has a tie-break at all.
KARTTEST.AddItem({ id = 700001, name = "Simmed Blade", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 4, equipLoc = "INVTYPE_2HWEAPON" })
KARTTEST.AddItem({ id = 700002, name = "Simmed Ring", quality = 4, ilvl = 291,
                   classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER" })
local BLADE = KARTTEST.items[700001].link
local RING  = KARTTEST.items[700002].link

local function Cache(players)
    env.KART_WoWUtilsCache = { schemaVersion = 1, syncedAt = 1785583037, groupId = "g", players = players }
    setfenv(DT.RebuildIndex, env)
    DT.RebuildIndex()
end

local function Gain(shortName, link, realm)
    setfenv(DT.GetGainPercent, env)
    return DT.GetGainPercent(shortName, link, realm)
end

-- The realm slug, which is the whole reason this module canonicalizes at all ----------------------
-- The companion writes WoWUtils' characterId: a lowercase slug where spaces become hyphens and
-- apostrophes vanish. GetRealmName() on this side answers the DISPLAY name. A naive
-- name.."-"..realm key would therefore never match for ANY multi-word or apostrophe realm -- which
-- is most of the big EU ones, this guild's own included.
do
    KARTTEST.realm = "Tarren Mill"
    Cache({ ["kandera-tarren-mill"] = { { itemId = 700001, ilvl = 285, gainPct = 4.2, source = "raidbots" } } })
    local pct, src = Gain("Kandera", BLADE)
    T.eq(pct, 4.2, "a two-word realm matches its hyphenated slug")
    T.eq(src, "raidbots", "and the source comes back with it")
end

do
    KARTTEST.realm = "Kil'jaeden"
    Cache({ ["kandera-kiljaeden"] = { { itemId = 700001, ilvl = 285, gainPct = 1.5 } } })
    T.eq(Gain("Kandera", BLADE), 1.5, "an apostrophe realm matches a slug that dropped it")
end

do
    -- Umlauts fold on BOTH sides or not at all: the index is built with CaseFold and the lookup has
    -- to use the same fold, or a name starting with "Ö" never finds its own lowercase key.
    KARTTEST.realm = "Blackmoore"
    Cache({ ["öhrchen-blackmoore"] = { { itemId = 700001, ilvl = 285, gainPct = 9.9 } } })
    T.eq(Gain("Öhrchen", BLADE), 9.9, "an umlaut name folds the same way the cache key does")
end

-- Namesakes across realms ---------------------------------------------------------------------------
-- The council reads this column while deciding who gets an item. Showing one player's sim number
-- against another player's name is worse than showing nothing, so an ambiguous short name answers
-- nothing at all.
do
    KARTTEST.realm = "Blackmoore"
    Cache({
        ["kandera-tarrenmill"] = { { itemId = 700001, ilvl = 285, gainPct = 3.0 } },
        ["kandera-silvermoon"] = { { itemId = 700001, ilvl = 285, gainPct = 8.0 } },
    })
    T.is_nil(Gain("Kandera", BLADE), "two cross-realm namesakes answer nothing rather than guessing")
end

do
    -- ...but a single cross-realm entry is unambiguous and still answers, which is what makes the
    -- guard above a guard rather than a blanket refusal.
    KARTTEST.realm = "Blackmoore"
    Cache({ ["kandera-silvermoon"] = { { itemId = 700001, ilvl = 285, gainPct = 8.0 } } })
    T.eq(Gain("Kandera", BLADE), 8.0, "one cross-realm entry is unambiguous and answers")
end

do
    -- The ambiguity guard only ever protected the FALLBACK. Asked about a cross-realm raider, the
    -- lookup tried our own realm first and, finding a namesake there, answered with full confidence
    -- -- somebody else's sim number under this raider's name, on the screen that decides the item.
    -- The caller knows the realm (it is UnitName's second return, and it was being thrown away), so
    -- the answer is to ask the right question rather than to guard the wrong one harder.
    KARTTEST.realm = "Blackmoore"
    Cache({
        ["kandera-blackmoore"] = { { itemId = 700001, ilvl = 285, gainPct = 1.0 } },
        ["kandera-silvermoon"] = { { itemId = 700001, ilvl = 285, gainPct = 9.0 } },
    })
    T.eq(Gain("Kandera", BLADE, "Silvermoon"), 9.0,
        "a raider's own realm decides, not ours")
    T.eq(Gain("Kandera", BLADE, "Blackmoore"), 1.0, "and our own namesake still gets their own number")
    T.eq(Gain("Kandera", BLADE), 1.0,
        "with no realm given it is still ours, which is right for our own character")
end

-- The same item, simmed at several upgrade tracks ---------------------------------------------------
do
    KARTTEST.realm = "Blackmoore"
    KARTTEST.items[700002].detailedIlvl = 291
    Cache({ ["kandera-blackmoore"] = {
        { itemId = 700002, ilvl = 278, gainPct = 1.0 },
        { itemId = 700002, ilvl = 291, gainPct = 5.0 },
        { itemId = 700002, ilvl = 304, gainPct = 9.0 },
    } })
    T.eq(Gain("Kandera", RING), 5.0,
        "the candidate closest to the level actually rolled wins, not the biggest number")
end

-- What the companion can hand us on a bad day -------------------------------------------------------
-- Everything below is another program's output. None of it may throw: this runs inside the council
-- panel's row build, once per candidate per item.
do
    KARTTEST.realm = "Blackmoore"
    env.KART_WoWUtilsCache = nil
    setfenv(DT.RebuildIndex, env); DT.RebuildIndex()
    T.is_nil(Gain("Kandera", BLADE), "no cache at all is simply no data")

    env.KART_WoWUtilsCache = { schemaVersion = 2, players = { ["kandera-blackmoore"] = {
        { itemId = 700001, ilvl = 285, gainPct = 4.0 } } } }
    setfenv(DT.RebuildIndex, env); DT.RebuildIndex()
    T.is_nil(Gain("Kandera", BLADE),
        "a schema this client does not know is refused outright, not read hopefully")

    env.KART_WoWUtilsCache = { schemaVersion = 1, players = "not a table" }
    setfenv(DT.RebuildIndex, env); DT.RebuildIndex()
    T.is_nil(Gain("Kandera", BLADE), "a players field that is not a table does not throw")
end

do
    KARTTEST.realm = "Blackmoore"
    Cache({ ["kandera-blackmoore"] = {
        "not a table",
        { itemId = 700001 },                              -- no gainPct
        { itemId = 700001, gainPct = "4.0" },             -- gainPct as text
        { itemId = 700001, ilvl = 285, gainPct = 7.5 },   -- the only usable one
    } })
    T.eq(Gain("Kandera", BLADE), 7.5, "malformed candidates are skipped, the sound one is used")
end

do
    -- A key with no realm at all. The companion should not write one, but "should not" is not a
    -- guarantee about somebody else's program.
    KARTTEST.realm = "Blackmoore"
    Cache({ ["kandera"] = { { itemId = 700001, ilvl = 285, gainPct = 2.5 } } })
    T.eq(Gain("Kandera", BLADE), 2.5, "a realm-less key still resolves by short name")
end

-- The switch ----------------------------------------------------------------------------------------
do
    KARTTEST.realm = "Blackmoore"
    Cache({ ["kandera-blackmoore"] = { { itemId = 700001, ilvl = 285, gainPct = 4.0 } } })
    T.eq(Gain("Kandera", BLADE), 4.0, "the column answers while the module is on")
    env.KART_Settings.dtModuleEnabled = false
    T.is_nil(Gain("Kandera", BLADE), "and answers nothing at all once it is switched off")
    env.KART_Settings.dtModuleEnabled = true
end

-- The status label, which runs off a ticker ---------------------------------------------------------
-- Once a minute, forever, on a table another program wrote. An ISO-8601 timestamp is the natural
-- thing for an external writer to produce, and arithmetic on it would throw once a minute for the
-- rest of the session.
do
    local shown
    DT.statusLabel = { SetText = function(_, t) shown = t end, SetTextColor = function() end }
    KART.L = { DT_STATUS_NEVER_SYNCED = "never", DT_STATUS_SYNCED_FORMAT = "%s / %d",
               DT_TIME_LT1M = "<1m", DT_TIME_MIN = "%dm", DT_TIME_HOUR = "%dh", DT_TIME_DAY = "%dd" }
    setfenv(DT.RefreshStatusLabel, env)

    env.KART_WoWUtilsCache = { schemaVersion = 1, syncedAt = "2026-08-01T12:00:00Z", players = {} }
    DT.RefreshStatusLabel()
    T.eq(shown, "never", "a timestamp that is not a number reads as never synced instead of throwing")

    env.KART_WoWUtilsCache = { schemaVersion = 2, syncedAt = time(), players = { a = {}, b = {} } }
    DT.RefreshStatusLabel()
    T.eq(shown, "never",
        "and so does a schema mismatch -- reporting a player count there would be a lie, since the index is empty")

    env.KART_WoWUtilsCache = { schemaVersion = 1, syncedAt = time(), players = { a = {}, b = {} } }
    DT.RefreshStatusLabel()
    T.eq(shown, "<1m / 2", "a sound cache reports how long ago and for how many players")
    DT.statusLabel = nil
end

-- ===================================================================================
-- The council panel asks the right question
-- ===================================================================================
-- Everything above tests the module in isolation, which is where the logic is -- but the defect that
-- started this was in the CALLER: the panel split the short name out of UnitName and threw the realm
-- away, so the module was asked about our realm for everybody. A correct module answering the wrong
-- question is still the wrong number on screen.
--
-- Driven through a real raid rather than by reading the source, so it fails if the argument is
-- dropped, renamed or reordered.
do
    local F = dofile("tests/lc_fixture.lua")
    local RaidSim = F.RaidSim
    local sim, _, council = F.NewRaid()

    local asked = {}
    local realGain = council.KART.DT.GetGainPercent
    council.KART.DT.GetGainPercent = function(shortName, itemLink, realm)
        asked[#asked + 1] = { short = shortName, realm = realm }
        return realGain(shortName, itemLink, realm)
    end

    F.Drop(sim, 600, F.GLOVES)
    RaidSim.As(council, function() council.KART.LC.Council.RefreshCouncilRows() end)
    council.KART.DT.GetGainPercent = realGain

    T.truthy(#asked > 0, "the council panel asks Droptimizer for a gain at all")
    local withRealm = 0
    for _, a in ipairs(asked) do
        if a.realm ~= nil then withRealm = withRealm + 1 end
    end
    T.eq(withRealm, #asked, "and asks about each raider's own realm, never only about ours")
end
