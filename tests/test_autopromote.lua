-- Auto-Promote: who gets assistant handed to them, and in what spelling.
--
-- This one acts on other people's raid. It had no test at all -- PromoteToAssistant was not even
-- defined in the harness until 2026-08-01, so calling KART.HandleAutoPromote would simply have
-- thrown. It also carries the scar of B15, where a name pasted from the WoWUtils export never
-- matched because the two sides spell a realm differently, and nobody was ever told.
--
-- GroupLogic.lua is loaded the way WoW loads it, like tests/test_groupinvite.lua does, because what
-- is under test spans two functions: UpdateCache builds the table, HandleAutoPromote reads it, and
-- the case-folding contract between them is exactly where this goes wrong.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = {}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("GroupLogic.lua", "r")):read("*a"), "@GroupLogic.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
    setfenv(KART.UpdateCache, env)
    setfenv(KART.HandleAutoPromote, env)
end

-- In a raid every member is raid1..raidN and "player" is nobody until KARTTEST.activeUnit says
-- who we are -- so `me` is appended last and pointed at. Getting that wrong does not fail loudly: it
-- makes this client a non-member, HandleAutoPromote's first line returns, and every case below
-- "passes" by promoting nobody for the wrong reason.
--
-- `assist` is what UnitIsGroupAssistant answers, so "already an assistant" is expressible too.
local function Raid(others, me)
    KARTTEST.realm = "TarrenMill"
    KARTTEST.solo = {}
    local all = {}
    for _, m in ipairs(others) do all[#all + 1] = m end
    all[#all + 1] = me or { name = "Kandera", guid = "Player-1-A", leader = true }
    KARTTEST.SetRaid(all)
    KARTTEST.activeUnit = "raid" .. #all
    KARTTEST.ClearPromoted()
end

local function PromoteList(text)
    env.KART_Settings.promoteNames = text
    KART.UpdateCache()
end

local function Run()
    KART.HandleAutoPromote()
    return KARTTEST.promoted
end

-- The plain case ------------------------------------------------------------------------------------
do
    Raid({ { name = "Wuusch",  guid = "Player-1-B" },
           { name = "Narrath", guid = "Player-1-C" } })
    PromoteList("Wuusch")
    local out = Run()
    T.eq(#out, 1, "exactly one person is promoted")
    T.eq(out[1], "Wuusch", "and it is the one on the list")
end

do
    -- Case and spacing, the same contract the invite keywords have: the list is folded when it is
    -- built, so the lookup has to fold too or nothing on it ever matches.
    Raid({ { name = "Wuusch",  guid = "Player-1-B" } })
    PromoteList("  WUUSCH  ;  ")
    T.eq(Run()[1], "Wuusch", "case and surrounding spaces do not matter")
end

do
    Raid({ { name = "Wuusch",  guid = "Player-1-B" } })
    PromoteList("Narrath")
    T.eq(#Run(), 0, "somebody who is not on the list is left alone")
end

-- Authority -----------------------------------------------------------------------------------------
do
    -- Not the leader: promoting is not ours to do, and trying would be an error in the game.
    Raid({ { name = "Wuusch", guid = "Player-1-B", leader = true } },
          { name = "Kandera", guid = "Player-1-A" })
    PromoteList("Kandera;Wuusch")
    T.eq(#Run(), 0, "a member who does not lead promotes nobody")
end

do
    -- Already an assistant, and the leader themselves: neither needs promoting, and asking again
    -- every roster update would be noise on the server for no change.
    Raid({ { name = "Wuusch",  guid = "Player-1-B", assist = true },
           { name = "Narrath", guid = "Player-1-C" } })
    PromoteList("Kandera;Wuusch;Narrath")
    local out = Run()
    T.eq(#out, 1, "only the one who is neither leader nor assistant already")
    T.eq(out[1], "Narrath", "and that is who it is")
end

-- The realm, which is what B15 was ------------------------------------------------------------------
-- A name copied out of the WoWUtils export is realm-qualified and spells the realm NORMALIZED
-- ("TarrenMill"), while UnitName gives a cross-realm unit its DISPLAY realm ("Tarren Mill"). Both
-- spellings have to match the same person, or the entry silently never fires and nobody is told.
do
    Raid({ { name = "Wuusch",  guid = "Player-2-B", realm = "Tarren Mill" } })
    PromoteList("Wuusch-TarrenMill")
    local out = Run()
    T.eq(#out, 1, "a normalized realm in the list matches a display realm on the unit")
    T.eq(out[1], "Wuusch-Tarren Mill",
        "and the promote targets the real character, spelled the way the game spells it")
end

do
    Raid({ { name = "Wuusch",  guid = "Player-2-B", realm = "Tarren Mill" } })
    PromoteList("Wuusch-Tarren Mill")
    T.eq(Run()[1], "Wuusch-Tarren Mill", "and the display spelling in the list works too")
end

do
    -- A realm-qualified entry must not promote a DIFFERENT realm's namesake. This is the whole
    -- reason the entry is realm-qualified in the first place.
    Raid({ { name = "Wuusch",  guid = "Player-3-B", realm = "Silvermoon" } })
    PromoteList("Wuusch-TarrenMill")
    T.eq(#Run(), 0, "a namesake on another realm is not the person named")
end

-- The nickname --------------------------------------------------------------------------------------
-- A name in the promote list applies to every character sharing that Northern Sky nickname, not just
-- one alt. Matching is on the nickname; the promote still targets the real character.
do
    Raid({ { name = "Wuuschdk", guid = "Player-1-B", nickname = "Wuusch" } })
    KARTTEST.SetNSAPI(true)
    PromoteList("Wuusch")
    local out = Run()
    KARTTEST.SetNSAPI(false)
    T.eq(#out, 1, "an alt is promoted by the nickname its main is known by")
    T.eq(out[1], "Wuuschdk", "and the promote names the character, not the nickname")
end
