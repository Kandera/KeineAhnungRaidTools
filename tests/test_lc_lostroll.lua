-- B60: the lootmaster force-wins, loses Blizzard's roll, and nothing notices.
--
-- ForceWinRoll rolls Need and never reads the outcome. A raider not running KART can out-roll the
-- lootmaster. The council still awards; Trade.AddPendingTrade records an obligation for an item the
-- lootmaster does not have; Trade.OnTradeClosed later reads "not in my bags" as "already traded" and
-- clears the reminder the next time that winner is traded with for anything at all. The reminder
-- tidies itself away, the lootmaster believes it is done, the winner never receives anything, and
-- the loot history says they won it.
--
-- What is under test is only that the lootmaster is TOLD. The distribution is deliberately not
-- changed from here -- see the comment at LC.HandleLootHistoryDrop for why an item-link match is not
-- allowed to take a trade reminder away.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local GLOVES = KARTTEST.items[F.GLOVES].link

local function Capture(fn)
    local lines, realPrint = {}, _G.print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then error(err, 0) end
    return table.concat(lines, "\n")
end

-- Blizzard resolves the drop and says who won it.
local function Resolve(encounterID, lootListID, drop)
    KARTTEST.lootDrops[tostring(encounterID) .. ":" .. tostring(lootListID)] = drop
end

local function Drop(client, encounterID, lootListID)
    return Capture(function()
        RaidSim.As(client, function()
            client.KART.LC.HandleLootHistoryDrop(encounterID, lootListID)
        end)
    end)
end

do
    local sim, lm = F.NewRaid()
    F.Drop(sim, 95, F.GLOVES)   -- the lootmaster force-wins this one

    Resolve(2000, 1, {
        itemHyperlink = GLOVES,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    local out = Drop(lm, 2000, 1)
    T.truthy(out:find("Fremder", 1, true), "the lootmaster is told who actually won the item")
    T.truthy(out:find(KARTTEST.items[F.GLOVES].name, 1, true), "and which item it was")

    -- Once per drop. LOOT_HISTORY_UPDATE_DROP fires again for the same drop as the panel fills in,
    -- and a line repeated four times reads as four lost items.
    T.eq(Drop(lm, 2000, 1), "", "and told once, not once per update of the same drop")
end

do
    -- The ordinary case, which is every item on a normal evening: the lootmaster won it.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 96, F.GLOVES)
    Resolve(2001, 1, {
        itemHyperlink = GLOVES,
        winner = { playerName = "Bramor", playerGUID = lm.guid, isSelf = true },
    })
    T.eq(Drop(lm, 2001, 1), "", "winning the roll says nothing at all")

    -- Nobody rolled: there is no item to have lost.
    Resolve(2001, 2, { itemHyperlink = GLOVES, allPassed = true })
    T.eq(Drop(lm, 2001, 2), "", "and neither does a drop everybody passed on")
end

do
    -- An item this client never rolled on. Every drop in the instance raises this event, including
    -- the ones below the raid's rarity threshold and the ones from a boss the council ignored --
    -- reporting those would make the line meaningless within one evening.
    local _, lm = F.NewRaid()
    Resolve(2002, 1, {
        itemHyperlink = KARTTEST.items[F.WEAPON].link,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    T.eq(Drop(lm, 2002, 1), "", "an item the council never took up is not reported")
end

do
    -- Only the person who force-wins has anything to lose. A council member or a plain raider
    -- reading "that went to somebody else" about an item they never rolled on cannot act on it.
    local sim, lm, council, raider = F.NewRaid()
    F.Drop(sim, 97, F.GLOVES)
    Resolve(2003, 1, {
        itemHyperlink = GLOVES,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    T.eq(Drop(council, 2003, 1), "", "a council member is not told")
    T.eq(Drop(raider, 2003, 1), "", "and neither is a plain raider")
    T.truthy(Drop(lm, 2003, 1) ~= "", "while the loot owner is")
end

do
    -- A roll learned from somebody else's LC_START is one this client never rolled on, which is
    -- exactly what LC.rollNotInOurBags records. The stand-in who took over mid-distribution must not
    -- be told they lost an item that was never theirs to win.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 98, F.GLOVES)
    RaidSim.As(lm, function() lm.KART.LC.rollNotInOurBags[98] = true end)
    Resolve(2004, 1, {
        itemHyperlink = GLOVES,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    T.eq(Drop(lm, 2004, 1), "", "an item this client never rolled on is not reported as lost")
end

do
    -- The two links come from different producers -- ours from GetLootRollItemLink, Blizzard's from
    -- C_LootHistory -- and the colour escape at the front of a link is not the same on every client
    -- version. Comparing the links as written would make this silent on any client whose escape is
    -- spelled differently, which looks exactly like the state before this existed.
    local sim, lm = F.NewRaid()
    F.Drop(sim, 99, F.GLOVES)
    local named = GLOVES:gsub("^|cff%x%x%x%x%x%x", "|cnIQ4:")
    T.truthy(named ~= GLOVES, "the two link forms really do differ")
    Resolve(2005, 1, {
        itemHyperlink = named,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    T.truthy(Drop(lm, 2005, 1):find("Fremder", 1, true),
        "the same item written with the other colour escape is still recognised")
end

do
    -- The setup this could not see at all. Vote.PruneExpiredRolls frees LC.rollItems once the vote
    -- window is over for any client holding no council tab, and tabs exist only for council
    -- members -- so a lootmaster who is not in the council list has nothing left to match against
    -- by the time Blizzard resolves the roll, which is much later than twenty seconds. The trade
    -- obligation is what outlives it, and it is the promise this warning is about.
    local _, lm = F.NewRaid()
    RaidSim.As(lm, function()
        lm.KART.LC.rollItems = {}       -- the vote window is long over
        lm.KART.LC.pendingTrades = { {
            rollID = 99, itemLink = GLOVES, winnerKey = "Player-1-A", lootedAt = time(),
        } }
    end)
    Resolve(2006, 1, {
        itemHyperlink = GLOVES,
        winner = { playerName = "Fremder", playerGUID = "Player-1-ZZZ", isSelf = false },
    })
    T.truthy(Drop(lm, 2006, 1):find("Fremder", 1, true),
        "an item already owed to somebody is still recognised after the roll state is gone")
end

do
    -- The API guard, which is the whole safety net under a call taken from annotations one minor
    -- version behind the live client. C_LootHistory existing does not mean this function does: a
    -- rename leaves the table in place and the member gone, and calling it then throws inside an
    -- event handler. Both halves have to be checked, not just the table.
    local _, lm = F.NewRaid()
    local real = _G.C_LootHistory
    _G.C_LootHistory = {}                     -- table there, function renamed away
    local ok = pcall(function() Drop(lm, 2007, 1) end)
    _G.C_LootHistory = real
    T.truthy(ok, "a client whose loot-history API moved does not throw on every drop")
end
