-- The loot history's JSON export and the filters it shares with the window.
--
-- This is the one thing in the addon whose output is read by SOMETHING ELSE -- it mirrors
-- RCLootCouncil's own history export so it can be pasted into tools built for that, and the
-- maintainer exports every raid night. Broken JSON is not a cosmetic problem there: the receiving
-- tool refuses the whole paste, and the evening is simply not in the record.
--
-- The export and the window must also agree on what "currently visible" means, since the export
-- deliberately exports what the filters show. Neither had a test.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- One booted client is enough: LootHistory.lua is loaded per client by raidsim, so KART.LH here is
-- the real module with the real filters.
local sim = F.NewRaid()
local me = sim.byName.Bramor
local LH = me.KART.LH

local function History(entries)
    me.env.KART_LootHistory = entries
    LH.filters.player, LH.filters.reason, LH.filters.search = nil, nil, ""
end

local function Export()
    return RaidSim.As(me, LH.BuildRCLootCouncilJSON)
end

-- Count top-level objects without a JSON parser: every entry contributes exactly one "player" key.
local function CountEntries(json)
    local n = 0
    for _ in json:gmatch('"player":') do n = n + 1 end
    return n
end

local GLOVES = KARTTEST.items[F.GLOVES].link

-- Shape -----------------------------------------------------------------------------------------
do
    History({ { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
                class = "MAGE", time = 1785000000, difficultyID = 16 } })
    local json = Export()
    T.eq(json:sub(1, 1), "[", "the export is a JSON array")
    T.eq(json:sub(-1), "]", "and is closed")
    T.eq(CountEntries(json), 1, "with one object per entry")
    T.truthy(json:find('"player":"Alric"', 1, true), "naming the winner")
    T.truthy(json:find('"response":"BIS"', 1, true), "and the reason they were given it for")
    T.truthy(json:find('"instance":"Mythic"', 1, true),
        "with the difficulty in English, so a mixed-language raid exports one consistent value")
end

do
    History({})
    T.eq(Export(), "[]", "an empty history exports an empty array, not nothing")
end

-- Escaping, which is what makes it parseable at all ------------------------------------------------
-- Every one of these fields can hold text somebody else typed: a vote note, a custom reason, an item
-- name in any language. One unescaped quote and the receiving tool rejects the whole paste.
do
    History({ { winner = 'He said "hi"', item = GLOVES, reason = "back\\slash", time = 1785000000 } })
    local json = Export()
    T.truthy(json:find('\\"hi\\"', 1, true), "a quote in a name is escaped")
    T.truthy(json:find("back\\\\slash", 1, true), "and so is a backslash")
    T.truthy(not json:find('"player":"He said "hi""', 1, true),
        "so the field does not end early and take the rest of the object with it")
end

do
    History({ { winner = "Line\nBreak\tTab", item = GLOVES, reason = "r", time = 1785000000 } })
    local json = Export()
    T.truthy(json:find("Line\\nBreak\\tTab", 1, true), "newlines and tabs become escapes")
    T.truthy(not json:find("Line\nBreak", 1, true), "and no raw control character survives")
end

do
    History({ { winner = "Bell\1Here", item = GLOVES, reason = "r", time = 1785000000 } })
    T.truthy(Export():find("Bell\\u0001Here", 1, true),
        "a stray control byte is escaped as \\u00XX rather than emitted raw")
end

-- The filters, which the export deliberately honours ------------------------------------------------
do
    History({
        { winner = "Alric", winnerKey = "K-A", item = GLOVES, reason = "BIS",     time = 1785000003 },
        { winner = "Sinja", winnerKey = "K-S", item = GLOVES, reason = "Upgrade", time = 1785000002 },
        { winner = "Alric", winnerKey = "K-A", item = GLOVES, reason = "Upgrade", time = 1785000001 },
    })
    T.eq(CountEntries(Export()), 3, "everything is exported with no filter set")

    LH.filters.player, LH.filters.playerIds = "K-A", { ["K-A"] = true }
    T.eq(CountEntries(Export()), 2, "a player filter narrows the export the same way it narrows the window")

    LH.filters.player, LH.filters.playerIds, LH.filters.reason = nil, nil, "Upgrade"
    T.eq(CountEntries(Export()), 2, "and so does a reason filter")

    LH.filters.player, LH.filters.playerIds = "K-A", { ["K-A"] = true }
    T.eq(CountEntries(Export()), 1, "two filters narrow together, not separately")
end

do
    -- The player filter holds a stable id: a winnerKey for modern entries, the display name for ones
    -- written before keys existed. Both have to match, or switching the filter loses half a player's
    -- history without saying so.
    History({
        { winner = "Alric", winnerKey = "K-A", item = GLOVES, reason = "BIS", time = 1785000002 },
        { winner = "Alric",                    item = GLOVES, reason = "BIS", time = 1785000001 },
    })
    local players = RaidSim.As(me, LH.GetUniquePlayers)
    T.eq(#players, 1, "one person is one entry in the player filter, not two")
    T.eq(players[1] and players[1].label, "Alric", "under their name")

    LH.filters.player  = players[1] and players[1].id
    LH.filters.playerIds = players[1] and players[1].ids
    T.eq(CountEntries(Export()), 2,
        "and filtering by them shows their whole history, keyed and legacy alike")
    LH.filters.player, LH.filters.playerIds = nil, nil
end

do
    -- Somebody who has since left the guild is in neither the group nor the name cache, so
    -- ResolveDisplayName answers with the key it was given. Taking that as a label put raw GUIDs in
    -- the filter list while the name they were logged under sat unused in the entry itself.
    History({ { winner = "Ausgetreten", winnerKey = "Player-9999-DEADBEEF", item = GLOVES,
                reason = "BIS", time = 1785000000 } })
    local players = RaidSim.As(me, LH.GetUniquePlayers)
    T.eq(players[1] and players[1].label, "Ausgetreten",
        "a departed raider is listed under their name, not their GUID")
end

do
    -- Search is folded when it is typed, so it has to be compared against a folded name -- and it is
    -- a plain find, not a pattern, or an item with a "(" in its name would throw.
    History({ { winner = "Alric", item = GLOVES, reason = "r", time = 1785000000 } })
    local name = GLOVES:match("%[(.-)%]")
    LH.filters.search = me.KAUtil.CaseFold(name:sub(1, 4))
    T.eq(CountEntries(Export()), 1, "a search matches the item name")
    LH.filters.search = me.KAUtil.CaseFold("nothing like it")
    T.eq(CountEntries(Export()), 0, "and excludes what it does not match")
    LH.filters.search = "("
    T.eq(CountEntries(Export()), 0, "a regex-looking search is treated as plain text, not a pattern")
    LH.filters.search = ""
end

-- Ordering ------------------------------------------------------------------------------------------
do
    -- Newest first, because that is what the window shows and the two must agree. The catch-up sync
    -- appends older entries at the end of the table, so insertion order is NOT chronological.
    History({
        { winner = "Oldest", item = GLOVES, reason = "r", time = 1785000001 },
        { winner = "Newest", item = GLOVES, reason = "r", time = 1785000003 },
        { winner = "Middle", item = GLOVES, reason = "r", time = 1785000002 },
    })
    local json = Export()
    local order = {}
    for who in json:gmatch('"player":"([^"]*)"') do order[#order + 1] = who end
    T.eq(table.concat(order, ","), "Newest,Middle,Oldest",
        "the export is newest-first regardless of the order entries were stored in")
end

-- What a damaged history can look like ----------------------------------------------------------------
do
    -- KART_LootHistory is a SavedVariable, and the export runs over whatever is in it. A row without
    -- a time, an item that never resolved, a missing reason -- none may take the export down, because
    -- the failure would be one unusable paste with no clue which row caused it.
    History({
        { winner = "Alric", item = GLOVES, reason = "BIS", time = 1785000000 },
        { winner = "NoTime", item = GLOVES, reason = "r" },
        { winner = "NoItem", reason = "r", time = 1785000000 },
        { winner = "Bare", item = "item:249331", reason = "r", time = 1785000000 },
    })
    local ok, json = pcall(Export)
    T.truthy(ok, "a history with damaged rows still exports")
    T.eq(ok and CountEntries(json), 4, "and every row is in it")
    T.truthy(ok and json:find('"itemID":0', 1, true),
        "a row whose item never resolved exports a zero id rather than a broken field")
end

LH.filters.player, LH.filters.reason, LH.filters.search = nil, nil, ""

do
    -- The cost of grouping by displayed name, held so the choice stays a choice (B109). Two different
    -- people ever logged under the same name collapse into ONE filter entry carrying both histories.
    -- Grouping by key instead is what B98 was: one raider listed twice with their record split in
    -- half and nothing to say the other half existed.
    History({
        { winner = "Bramor", winnerKey = "K-OLD", item = GLOVES, reason = "BIS", time = 1785000002 },
        { winner = "Bramor", winnerKey = "K-NEW", item = GLOVES, reason = "BIS", time = 1785000001 },
    })
    local players = RaidSim.As(me, LH.GetUniquePlayers)
    T.eq(#players, 1, "two people of the same name are one entry in the filter, not two")
    T.truthy(players[1] and players[1].ids["K-OLD"] and players[1].ids["K-NEW"],
        "and picking it shows both of their histories, which is the documented trade")
    LH.filters.player, LH.filters.playerIds = nil, nil
end

-- The new fields stay out of the export. BuildRCLootCouncilJSON mirrors the field set and order
-- RCLootCouncil itself produces, because the output is pasted into tools built to read that -- an
-- extra key is a change to somebody else's format, and the export cut that will use `id` (sub-project
-- 2) tracks it on our side, not on the wire to wowutils.
do
    me.env.KART_LootHistoryEpoch = 3
    History({ { time = 1786090821, item = "item:1234", winner = "Alric", winnerKey = "Player-1-A",
                reason = "BIS", class = "MAGE", id = "1786090821-3f9a1c", epoch = 3 } })
    local json = Export()

    T.eq(json:find("epoch", 1, true), nil, "the epoch does not leak into the export")
    T.truthy(json:find('"player":"Alric"', 1, true), "and the export still says what it always said")
end
