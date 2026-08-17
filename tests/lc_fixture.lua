-- The raid every Loot Council multi-client test runs against, and the handful of verbs that drive it.
--
-- Shared rather than copied: the fixture IS part of what the tests assert -- real item IDs, a mixed
-- German/English raid, every raider on a different combination of the personal switches -- and two
-- copies of it would drift apart exactly where the interesting failures live.

if KARTTEST.lcFixture then return KARTTEST.lcFixture end

local RaidSim = dofile("tests/raidsim.lua")
local F = { RaidSim = RaidSim }

-- Real current-tier drops, with the classID/subclassID the live client reports for them. Invented
-- IDs were what let the tier-token bug hide.
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
-- A battle pet and a housing item, named in the Manifest's C6 alongside the mount. The housing
-- one deliberately sits in a subclass nothing enumerates: the rule is an ALLOW-list (only 15/0
-- reaches Council, see LC.IsCollectibleItem), so an unknown compartment of Miscellaneous is
-- exactly how Blizzard's next one will look, and the fixture should not pretend to know which
-- number housing decor actually got.
KARTTEST.AddItem({ id = 249403, name = "Voidling Hatchling", quality = 4, ilvl = 1,
                   classID = 15, subclassID = 2, bind = 1 })
KARTTEST.AddItem({ id = 249404, name = "Gloombound Sconce", quality = 4, ilvl = 1,
                   classID = 15, subclassID = 7, bind = 1 })

F.GLOVES, F.WEAPON, F.TOKEN = 249331, 249293, 249364
F.MOUNT, F.BOE, F.RARE = 249400, 249401, 249402
-- A SECOND plate piece. One is not enough: the relevance feature only reaches its Transmog branch
-- for an item the armor check calls irrelevant, so exercising a reused rollID across two such
-- items needs two of them. This is also the shape from GitHub #11 -- the strength plate chest a
-- Holy Paladin would have taken for off-spec.
KARTTEST.AddItem({ id = 249405, name = "Gloombound Breastplate", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", bind = 1 })

F.PET, F.HOUSING = 249403, 249404
F.PLATE_CHEST = 249405

-- The items the armor-weight rule cannot judge, which is every weapon and every shield. Until
-- 2026-08-05 those reached the relevance decision as "not determinable" and were therefore always
-- shown -- a caster who only ever saw weapons never saw Auto-Pass do anything at all.
--
-- Four, because two different rules decide them: PROFICIENCY (a paladin cannot hold a staff, a
-- priest cannot hold a shield, nobody but a hunter shape can hold a bow) and MAIN STAT (a priest
-- MAY swing a one-handed mace, and a strength one is still not theirs). The last one is the control:
-- proficiency and stat both say yes, so it must stay visible.
KARTTEST.AddItem({ id = 249406, name = "Voidglass Spire", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 10, equipLoc = "INVTYPE_2HWEAPON", bind = 1,
                   stats = { ITEM_MOD_INTELLECT_SHORT = 300 } })
KARTTEST.AddItem({ id = 249407, name = "Gloombound Bulwark", quality = 4, ilvl = 285,
                   classID = 4, subclassID = 6, equipLoc = "INVTYPE_SHIELD", bind = 1,
                   stats = { ITEM_MOD_INTELLECT_SHORT = 300 } })
KARTTEST.AddItem({ id = 249408, name = "Gloombound Crusher", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 4, equipLoc = "INVTYPE_WEAPONMAINHAND", bind = 1,
                   stats = { ITEM_MOD_STRENGTH_SHORT = 300 } })
KARTTEST.AddItem({ id = 249409, name = "Voidglass Kris", quality = 4, ilvl = 285,
                   classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPONMAINHAND", bind = 1,
                   stats = { ITEM_MOD_INTELLECT_SHORT = 300 } })

F.STAFF, F.SHIELD, F.STR_MACE, F.INT_DAGGER = 249406, 249407, 249408, 249409

-- An item whose STRING is long enough to matter on the wire. Everything above sits comfortably
-- inside one addon message, so no test could see what happens to the one that does not -- and a
-- Midnight drop carrying a full upgrade track, a crest and a tertiary runs well past it.
--
-- baseIlvl is what makes the difference observable: asked by bare id, the stub answers the BASE
-- version, exactly as the live client does. That is the whole of "ilvl 44 statt 285" (#20, #22,
-- #23) -- a client holding the id alone is holding a different item.
KARTTEST.AddItem({ id = 249410, name = "Voidbound Regalia of the Eternal Vigil", quality = 4,
                   ilvl = 285, baseIlvl = 44, classID = 4, subclassID = 1,
                   equipLoc = "INVTYPE_CHEST", bind = 1,
                   link = "|cffa335ee|Hitem:249410::::::::80:268::14:28:11946,10390,12043,10255," ..
                          "1540,10879,11996,10396,10394,1527,10877,10255,12345,10871,11304,10333," ..
                          "10842,10256,10395,12044,11300,10389,10391,10392,10393,10397,10398,10399" ..
                          ":28:9:::::|h[Voidbound Regalia of the Eternal Vigil]|h|r" })

F.LONG_ITEM = 249410

-- A tier token, restricted to three classes. Neither of the two rules above can say anything about
-- one: a token is Miscellaneous, so it has no armor weight and no weapon subclass -- and a raid on
-- new content is full of them. Only the item's own tooltip knows.
KARTTEST.AddItem({ id = 249411, name = "Voidbound Vestment of the Vigil", quality = 4, ilvl = 285,
                   classID = 15, subclassID = 0, bind = 1,
                   classesAllowed = { "DEATHKNIGHT", "PALADIN", "WARRIOR" } })

F.TIER_TOKEN = 249411

-- The one named exception to "Bind-on-Equip never reaches Council" (2026-08-06, #34): a recipe goes
-- to the lootmaster whatever it is bound as and whatever the raid's minimum quality says. Rare on
-- purpose -- most recipes are, the threshold is Epic, and a fixture that made it Epic would test the
-- exception without testing the half of it that matters.
--
-- Next to it, a Bind-on-Equip that is NOT a recipe: the control that says the rule still holds for
-- everything else. F.BOE is a cloak, and stays out.
KARTTEST.AddItem({ id = 249412, name = "Pattern: Voidbound Vestment", quality = 3, ilvl = 1,
                   classID = 9, subclassID = 11, bind = 2 })
-- Housing decor as Midnight ships it: its own item class, not a compartment of Miscellaneous any
-- more, and Bind-on-Pickup -- which is what made it reach Council while the rule only knew class 15.
KARTTEST.AddItem({ id = 249413, name = "Gloombound Chandelier", quality = 4, ilvl = 1,
                   classID = 20, subclassID = 0, bind = 1 })

F.RECIPE, F.HOUSING_DECOR = 249412, 249413

-- A council of three plus two plain raiders. More than one council member is the point: the whole
-- feature is several people deciding together, and a "council" of one cannot show a tally going out
-- of sync, a straw poll disagreeing, or a second council member's assignment reaching the first.
--
-- Every raider also runs a DIFFERENT combination of the personal switches, because a raid where
-- everyone is on defaults is a raid nobody has. The base flow has to hold for all of them at once:
-- whatever someone has switched on for themselves, the council must still see their answer.
F.SETTINGS = {
    Bramor = {},
    Merrit = {},
    Corvin = {},
    Alric  = {},
    Sinja  = {},
}

-- Real-length GUIDs on purpose: "Player-<realmID>-<8 hex>", about twice the width of the
-- placeholders this fixture used to carry. The lootmaster DESIGNATION now travels as an identity key
-- inside LC_CONFIG's prefix (see LC.BroadcastRaidConfig), so every byte of it comes off the council
-- list's budget in BuildCouncilPayload -- and a ten-character stand-in would have hidden a truncated
-- council list until a live raid found it.
F.MEMBERS = {
    { name = "Bramor", realm = "TarrenMill", guid = "Player-1096-0A1B2C3D", class = "DEATHKNIGHT", leader = true, locale = "deDE" },
    { name = "Merrit", realm = "TarrenMill", guid = "Player-1096-0A1B2C3E", class = "DRUID",       locale = "deDE" },
    { name = "Corvin", realm = "TarrenMill", guid = "Player-1096-0A1B2C3F", class = "PALADIN",     locale = "enUS" },
    { name = "Alric",  realm = "TarrenMill", guid = "Player-1096-0A1B2C40", class = "MAGE",        locale = "enUS" },
    { name = "Sinja",  realm = "TarrenMill", guid = "Player-1096-0A1B2C41", class = "PRIEST",      locale = "deDE" },
}

-- Builds a raid whose lootmaster is Bramor and whose council is Bramor + Merrit + Corvin, then
-- starts the session the way the settings toggle does. Returns the sim, the lootmaster, one council
-- member (Merrit) and one plain raider (Alric).
function F.NewRaid()
    -- A raid is normally all on one realm, so the client's own realm must match the fixture's -- otherwise
    -- every member reads as cross-realm and the same-realm half of every group-membership check goes
    -- unexercised. Cross-realm members are worth testing too, but as the exception they are.
    KARTTEST.realm = "TarrenMill"
    KARTTEST.now = 1000
    KARTTEST.timers, KARTTEST.lootRolls, KARTTEST.rolled = {}, {}, {}
    KARTTEST.solo, KARTTEST.popups = {}, {}
    local sim = RaidSim.New(F.MEMBERS)
    RaidSim.Install(sim)

    local lm, council, raider = sim.byName.Bramor, sim.byName.Merrit, sim.byName.Alric

    for name, opts in pairs(F.SETTINGS) do
        local c = sim.byName[name]
        for k, v in pairs(opts) do c.env.KART_Settings[k] = v end
    end

    return sim, lm, council, raider
end

-- The same raid, with the two roles held by DIFFERENT people: Bramor hands out the loot, Corvin
-- leads the raid. This is the normal shape where the tank leads and someone else has time
-- to distribute, and every authority check in the addon has a raid-leader fallback that the default
-- fixture cannot tell apart from the real answer, because there both roles are the same person.
-- A whole class of ownership bug is invisible without this.
function F.NewSplitRaid()
    local sim, lm, council, raider = F.NewRaid()
    local leader = RaidSim.Promote(sim, "Corvin")
    -- The DESIGNATION lives on the config owner's client, and the config owner is the raid leader
    -- (docs/OWNERSHIP.md). So the leader is the one who has to name the lootmaster -- that is the
    -- whole point of the split: one person leads, another hands out the loot, and the leader says
    -- which. A leader with an empty field is a raid that has designated nobody, which is a different
    -- setup and is covered by F.NewRaid.
    RaidSim.As(leader, function()
        leader.env.KART_Settings.lcLootmaster     = "Bramor"
        leader.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin"
        leader.env.KART_Settings.lcRollsEnabled   = true
        leader.KART.LC.ApplyOwnConfig()
        leader.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(0)
    return sim, lm, council, raider, leader
end

-- One item drops. Blizzard raises START_LOOT_ROLL on every eligible client independently; the loot
-- owner's handler collects the item into the batch that announces it to the rest (LC_DROP, half a
-- second later), so running them in this order is the realistic case and also the awkward one. Note
-- that this no longer means peers hear about the roll before their own event: nothing goes out until
-- the collection window closes, so a caller that wants the announcement has to advance the clock.
function F.Drop(sim, rollID, itemID, opts)
    opts = opts or {}
    -- noRollFor marks the clients Blizzard never raised this roll on. It has to reach the API stub,
    -- not just skip the call: on those clients GetLootRollItemLink answers nil forever, and that is
    -- precisely the state LC.HandleStart's rebuild-from-payload exists for.
    local notFor, forNames = {}, {}
    for _, c in ipairs(sim.clients) do
        if opts.noRollFor and opts.noRollFor[c.name] then
            notFor[c.unit] = true
        else
            -- Who Blizzard raised the roll on: everyone in the raid at this moment, and nobody
            -- else. A player who joins later has no roll under this ID for the rest of its life,
            -- which is what the game does and what keeps them out of a distribution they were not
            -- there for.
            forNames[c.name] = true
        end
    end
    KARTTEST.lootRolls[rollID] = { itemID = itemID, canNeed = opts.canNeed, canGreed = opts.canGreed,
                                   canTransmog = opts.canTransmog,
                                   bop = opts.bop, notFor = notFor, forNames = forNames,
                                   linkPending = opts.linkPending }
    for _, c in ipairs(sim.clients) do
        if not notFor[c.unit] then
            RaidSim.As(c, function()
                -- The EVENT first, then Core.lua's dispatcher -- which is the order the game
                -- uses and the order that matters. LootCouncilRelevance.lua registers its own
                -- frame for START_LOOT_ROLL and the .toc loads it before Core.lua, so it sees
                -- Blizzard's per-roll verdict BEFORE OnStartLootRoll resolves this client's own
                -- roll and GetLootRollItemInfo goes blank. Calling only the dispatcher, as this
                -- did, meant that whole file never ran in any test.
                KARTTEST.FireEvent("START_LOOT_ROLL", rollID)
                c.KART.LC.OnStartLootRoll(rollID)
            end)
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
    return { sim.byName.Bramor, sim.byName.Merrit, sim.byName.Corvin }
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

-- Deterministic text for a [key] = value map, so two clients' copies compare as strings.
local function mapText(map, valueText)
    local parts = {}
    for k, v in pairs(map or {}) do parts[#parts + 1] = tostring(k) .. "=" .. valueText(v) end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- What this client believes about the RAID (never about itself: the vote list, the council tabs,
-- our own vote and our own pending trades are per client and SHOULD differ).
local function fingerprint(sim, client, rollID, rollFieldsOnly)
    local LC = client.KART.LC
    local fp = {}
    if not rollFieldsOnly then
        fp["session"] = tostring(LC.sessionActive)
        -- The EFFECTIVE answers, not the stored fields. What the raid experiences is what
        -- LC.GetLootmaster/GetButtonConfig/GetRaidMinQuality/GetRollsEnabled return, and those
        -- deliberately differ from the raw table: a departed lootmaster is masked to "" by
        -- everyone who watched them leave, while a client that arrived afterwards was handed a
        -- config with that field already empty (LC.RelayRaidConfig). Same answer, different
        -- spelling -- and comparing the spelling reports agreement as a disagreement.
        RaidSim.As(client, function()
            fp["config.lootmaster"]  = tostring(LC.GetLootmaster())
            fp["config.rollsEnabled"] = tostring(LC.GetRollsEnabled())
            fp["config.minQuality"]  = tostring(LC.GetRaidMinQuality())
            -- The synced label STRING, plus how many buttons it produces -- not the rendered
            -- labels. A raid that configured none leaves every client on its own localized
            -- defaults, so a German client shows "Sonstiges" where an English one shows "Other":
            -- the same button, in two languages, and comparing the text calls that a disagreement.
            -- What must match is the string the raid agreed and the number of responses, because
            -- that is what makes a vote index mean the same thing everywhere.
            fp["config.buttons"] = tostring(LC.raidConfig.buttonLabels)
                .. "#" .. #(LC.GetButtonConfig() or {})
        end)
        -- Who is council, asked about the people actually IN the raid -- not the raw table.
        -- CouncilNamesTable legitimately differs between clients for anyone absent: a name a client
        -- has never seen is parked under a lowercased TEXT key until that person shows up (see
        -- LC.ResolveConfigName and the pending-key retry), so a client that joined after someone
        -- left holds the pending form of a name an older client resolved long ago. That difference
        -- is the design working. What must never differ is the answer for someone standing here.
        local parts = {}
        for _, c in ipairs(sim.clients) do
            local isCouncil = RaidSim.As(client, function() return LC.IsSenderCouncil(c.guid) end)
            parts[#parts + 1] = c.name .. "=" .. tostring(not not isCouncil)
        end
        fp["council"] = table.concat(parts, ",")
    end
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
--
-- `clients` narrows it to a subset, which per-roll checks need: someone who arrived (or reloaded)
-- after an item dropped deliberately does NOT get pulled into that distribution, so they are
-- entitled to know nothing about it. Everything that is not per-roll -- the session, the config,
-- the council -- must still agree across the whole raid, always.
-- `rollFieldsOnly` drops the session/config/council half. The two halves converge on different
-- timescales: a client that just reloaded has the roll (LC_START reaches it immediately) long
-- before it has the config back (that waits on a roster change or a state request). Comparing
-- both at the moment an item drops would report a recovery still in flight as a disagreement.
function F.Disagreements(sim, rollID, clients, rollFieldsOnly)
    clients = clients or sim.clients
    -- A client that auto-answered this item (it cannot equip it, or KART voted Transmog for it on
    -- their behalf) stops tracking it -- they are done with it and it is off their screen. That is
    -- a PERSONAL setting doing its job, so they are no longer party to what the raid thinks about
    -- that item. Everything not tied to the roll still has to agree.
    if rollID then
        local still = {}
        for _, c in ipairs(clients) do
            if not (c.KART.LC.relevanceHandled or {})[rollID] then still[#still + 1] = c end
        end
        clients = still
    end
    if #clients < 2 then return {} end
    local base = clients[1]
    local baseFP = fingerprint(sim, base, rollID, rollFieldsOnly)
    local out = {}
    for i = 2, #clients do
        local c = clients[i]
        local fp = fingerprint(sim, c, rollID, rollFieldsOnly)
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
function F.AssertAgreed(sim, rollID, what, clients)
    T.eq(table.concat(F.Disagreements(sim, rollID, clients), " | "), "",
         "the whole raid agrees " .. what)
end

KARTTEST.lcFixture = F
return F
