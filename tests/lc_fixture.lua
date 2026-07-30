-- The raid every Loot Council multi-client test runs against, and the handful of verbs that drive it.
--
-- Shared rather than copied: the fixture IS part of what the tests assert -- real item IDs, a mixed
-- German/English raid, every raider on a different combination of the personal switches -- and two
-- copies of it would drift apart exactly where the interesting failures live.

if KARTTEST.lcFixture then return KARTTEST.lcFixture end

local RaidSim = dofile("tests/raidsim.lua")
local F = { RaidSim = RaidSim }

-- Real drops from the guild's own loot history, with the classID/subclassID the live client reports.
-- Invented IDs were what let the tier-token bug hide.
KARTTEST.AddItem({ id = 249331, name = "Ezzorak's Gloombind", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 4, equipLoc = "INVTYPE_HAND", bind = 1 })
KARTTEST.AddItem({ id = 249293, name = "Weight of Command", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 4, equipLoc = "INVTYPE_2HWEAPON", bind = 1 })
KARTTEST.AddItem({ id = 249364, name = "Voidcured Unraveled Nullcore", quality = 4, ilvl = 285,
                   classID = 15, subclassID = 0, bind = 1 })
-- Everything Council must keep its hands off. A mount is classID 15 with a non-zero subclass; a
-- Bind-on-Equip is ordinary gear that simply is not bound to the winner, so the lootmaster could
-- never hand it over through the BoP trade window; and a rare is below the raid's rarity threshold.
KARTTEST.AddItem({ id = 249400, name = "Voidscarred Ur'zul", quality = 4, ilvl = 1,
                   classID = 15, subclassID = 5, bind = 1 })
KARTTEST.AddItem({ id = 249401, name = "Gloombind Wrap", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK", bind = 2 })
KARTTEST.AddItem({ id = 249402, name = "Cracked Voidglass Band", quality = 3, ilvl = 200,
                   classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", bind = 1 })

F.GLOVES, F.WEAPON, F.TOKEN = 249331, 249293, 249364
F.MOUNT, F.BOE, F.RARE = 249400, 249401, 249402

-- A council of three plus two plain raiders. More than one council member is the point: the whole
-- feature is several people deciding together, and a "council" of one cannot show a tally going out
-- of sync, a straw poll disagreeing, or a second council member's assignment reaching the first.
--
-- Every raider also runs a DIFFERENT combination of the personal switches, because a raid where
-- everyone is on defaults is a raid nobody has. The base flow has to hold for all of them at once:
-- whatever someone has switched on for themselves, the council must still see their answer.
F.SETTINGS = {
    Kandera = {},                                                    -- lootmaster, defaults
    Haerri  = { lcAutoPass = false },                                -- clicks Blizzard's roll himself
    Wuusch  = { lcHideIrrelevant = true },                           -- hides what he cannot equip
    Odin    = { lcAutoTransmogVote = true },                         -- wants the appearances
    Nara    = { lcHideIrrelevant = true, lcAutoTransmogVote = true },-- both
}

F.MEMBERS = {
    { name = "Kandera", realm = "Blackmoore", guid = "Player-1-K", class = "DEATHKNIGHT", leader = true, locale = "deDE" },
    { name = "Haerri",  realm = "Blackmoore", guid = "Player-1-H", class = "DRUID",       locale = "deDE" },
    { name = "Wuusch",  realm = "Blackmoore", guid = "Player-1-W", class = "PALADIN",     locale = "enUS" },
    { name = "Odin",    realm = "Blackmoore", guid = "Player-1-O", class = "MAGE",        locale = "enUS" },
    { name = "Nara",    realm = "Blackmoore", guid = "Player-1-N", class = "PRIEST",      locale = "deDE" },
}

-- Builds a raid whose lootmaster is Kandera and whose council is Kandera + Haerri + Wuusch, then
-- starts the session the way the settings toggle does. Returns the sim, the lootmaster, one council
-- member (Haerri) and one plain raider (Odin).
function F.NewRaid()
    -- The guild raids on one realm, so the client's own realm must match the fixture's -- otherwise
    -- every member reads as cross-realm and the same-realm half of every group-membership check goes
    -- unexercised. Cross-realm members are worth testing too, but as the exception they are.
    KARTTEST.realm = "Blackmoore"
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    KARTTEST.solo, KARTTEST.popups = {}, {}
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)

    local lm, council, raider = sim.byName.Kandera, sim.byName.Haerri, sim.byName.Odin

    for name, opts in pairs(F.SETTINGS) do
        local c = sim.byName[name]
        for k, v in pairs(opts) do c.env.KART_Settings[k] = v end
    end

    RaidSim.As(lm, function()
        lm.env.KART_Settings.lcLootmaster     = "Kandera"
        lm.env.KART_Settings.lcCouncilMembers = "Kandera;Haerri;Wuusch"
        lm.env.KART_Settings.lcRollsEnabled   = true
        lm.KART.LC.ApplyOwnConfig()
        lm.KART.LC.SetSessionActive(true)
    end)
    return sim, lm, council, raider
end

-- The same raid, with the two roles held by DIFFERENT people: Kandera hands out the loot, Wuusch
-- leads the raid. This is the normal shape in a guild where the tank leads and someone else has time
-- to distribute, and every authority check in the addon has a raid-leader fallback that the default
-- fixture cannot tell apart from the real answer, because there both roles are the same person.
-- A whole class of ownership bug is invisible without this.
function F.NewSplitRaid()
    local sim, lm, council, raider = F.NewRaid()
    RaidSim.Promote(sim, "Wuusch")
    return sim, lm, council, raider, sim.byName.Wuusch
end

-- One item drops. Blizzard raises START_LOOT_ROLL on every eligible client independently; the loot
-- owner's handler is what broadcasts LC_START to the rest, so running them in this order is the
-- realistic case and also the awkward one (peers hear about the roll before their own event).
function F.Drop(sim, rollID, itemID, opts)
    opts = opts or {}
    -- noRollFor marks the clients Blizzard never raised this roll on. It has to reach the API stub,
    -- not just skip the call: on those clients GetLootRollItemLink answers nil forever, and that is
    -- precisely the state LC.HandleStart's rebuild-from-payload exists for.
    local notFor = {}
    for _, c in ipairs(sim.clients) do
        if opts.noRollFor and opts.noRollFor[c.name] then notFor[c.unit] = true end
    end
    KARTTEST.lootRolls[rollID] = { itemID = itemID, canNeed = opts.canNeed, canTransmog = opts.canTransmog,
                                   bop = opts.bop, notFor = notFor, linkPending = opts.linkPending }
    for _, c in ipairs(sim.clients) do
        if not notFor[c.unit] then
            RaidSim.As(c, function() c.KART.LC.OnStartLootRoll(rollID) end)
        end
    end
    KARTTEST.AdvanceTime(0)
end

-- pendingTrades and owedToMe are ordered lists of entries, not maps: an item can be owed twice over
-- an evening and order is what the reminder window shows.
function F.Owes(list, rollID)
    for _, e in ipairs(list or {}) do if e.rollID == rollID then return e end end
    return nil
end

-- Every client the raid config lists as council.
function F.CouncilOf(sim)
    return { sim.byName.Kandera, sim.byName.Haerri, sim.byName.Wuusch }
end

-- True when this client holds the item and shows a vote row for it.
function F.HasVoteRow(client, rollID)
    for _, id in ipairs(client.KART.LC.voteListRolls) do if id == rollID then return true end end
    return false
end

-- ===================================================================================
-- Convergence: does the whole raid actually agree?
-- ===================================================================================
-- Every piece of shared state in Loot Council is written by TWO code paths -- a handler, for the
-- clients that receive the message, and a hand-written local step next to the send, for the client
-- that sent it. That split exists because a sender does not process its own message (KASC drops the
-- echo; see its Dispatch). It is also the single most productive bug source in this addon: the two
-- paths are free to drift, and when they do exactly one client in the raid disagrees with the rest
-- -- which is what every failed raid night has looked like from the inside.
--
-- Individual assertions cannot catch that, because they check the client the test was thinking
-- about. This checks all of them against each other.

local SHARED_CFG = { "minQuality", "buttonLabels", "rollsEnabled", "lootmaster", "councilMembers" }

-- Deterministic text for a [key] = value map, so two clients' copies compare as strings.
local function mapText(map, valueText)
    local parts = {}
    for k, v in pairs(map or {}) do parts[#parts + 1] = tostring(k) .. "=" .. valueText(v) end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- What this client believes about the RAID (never about itself: the vote list, the council tabs,
-- our own vote and our own pending trades are per client and SHOULD differ).
local function fingerprint(client, rollID)
    local LC = client.KART.LC
    local fp = { ["session"] = tostring(LC.sessionActive) }
    for _, field in ipairs(SHARED_CFG) do
        fp["config." .. field] = tostring(LC.raidConfig[field])
    end
    fp["council"] = mapText(LC.CouncilNamesTable, tostring)
    if rollID then
        fp["item"]    = tostring(LC.rollItems[rollID])
        fp["winner"]  = tostring(LC.assignedWinners[rollID])
        fp["rolls"]   = mapText(LC.rolls[rollID], tostring)
        fp["cvotes"]  = mapText(LC.councilVotes[rollID], tostring)
        fp["votes"]   = mapText(LC.votes[rollID],
            function(v) return tostring(v.idx) .. "/" .. tostring(v.note) end)
    end
    return fp
end

-- Every way the clients disagree, as readable lines. Empty means the raid is of one mind.
-- Pass rollID to include the state belonging to one specific drop.
function F.Disagreements(sim, rollID)
    local base = sim.clients[1]
    local baseFP = fingerprint(base, rollID)
    local out = {}
    for i = 2, #sim.clients do
        local c = sim.clients[i]
        local fp = fingerprint(c, rollID)
        for key, want in pairs(baseFP) do
            if fp[key] ~= want then
                out[#out + 1] = string.format("%s: %s has %s, %s has %s",
                    key, base.name, want, c.name, tostring(fp[key]))
            end
        end
    end
    table.sort(out)
    return out
end

-- Asserts it, with the actual disagreement as the failure text rather than a bare "false".
function F.AssertAgreed(sim, rollID, what)
    T.eq(table.concat(F.Disagreements(sim, rollID), " | "), "", "the whole raid agrees " .. what)
end

KARTTEST.lcFixture = F
return F
