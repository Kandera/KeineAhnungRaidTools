local addonName, KART = ...
local LC = KART.LC

-- =====================================================================
--  Vote-window relevance  (which items are worth showing to THIS player)
-- =====================================================================
-- Two personal settings decide what happens to an item the player's class cannot equip: hide it
-- (voting the last configured response, so the council is not left waiting on a vote that will
-- never come) and/or vote Transmog on it while its appearance is still missing. Blizzard's own
-- loot roll is not involved anywhere in this file.

LC.Relevance = LC.Relevance or {}

-- Pure decision core, deliberately free of any WoW API call so tests/test_lc_relevance.lua can
-- compile it standalone. facts.irrelevant and facts.needsAppearance are three-state: true, false,
-- or nil for "could not be determined".
--
-- nil must behave like "relevant" and like "appearance owned" -- never the other way round. Both
-- automatic answers are claims made on the player's behalf, and a wrong one is expensive: hiding
-- passes away an item they were eligible for, and voting Transmog puts their name on an item they
-- may already have the appearance of.
local function DecideAutoResponse(facts)
    if facts.irrelevant ~= true then return nil end
    if facts.autoTransmog and facts.needsAppearance == true then return "transmog" end
    if facts.hideIrrelevant then return "pass" end
    return nil
end

LC.Relevance.DecideAutoResponse = DecideAutoResponse

-- Rolls this file has already answered, so a refresh (which runs several times a second during
-- active looting) cannot vote twice or re-hide a row the player brought back with /kart showall.
--
-- The value is the SETTINGS the answer was given under, not a bare true (B50). As a permanent latch
-- this table made both switches inert for anything already on screen: a player who ticked the second
-- one during a boss saw nothing happen, and the Pass their first setting had already broadcast to
-- the council stood. A stamp keeps the anti-recursion guarantee exactly as strong -- within one
-- refresh the settings cannot change -- while letting a genuine change be reconsidered.
LC.relevanceHandled = LC.relevanceHandled or {}

local function SettingsStamp(hide, mog)
    return (hide and "H" or "-") .. (mog and "M" or "-")
end

-- [rollID] = true for a row hidden because the player cannot use the item. Read by
-- Vote.GetVisibleRolls next to the lcVotedItemDisplay == "hide" case.
LC.hiddenIrrelevant = LC.hiddenIrrelevant or {}

-- [rollID] = true when the vote on that roll was cast by this file rather than by the player.
-- Vote.CastVote lets an automatic vote be overridden once; a manual one still locks. Both vote-row
-- renderers read this too and keep such a row's vote buttons on screen (highlighting the one this
-- file answered with) instead of collapsing it to a "you voted X" badge -- without that the
-- override would exist in CastVote and be unreachable from the UI.
LC.autoVotedByMe = LC.autoVotedByMe or {}

-- Blizzard's own per-roll verdict, snapshotted the instant START_LOOT_ROLL fires -- reading
-- GetLootRollItemInfo later, from inside ApplyToPendingRolls, is too late for the default
-- configuration: lcAutoPass defaults to true, and LC.OnStartLootRoll (Core.lua's own dispatcher)
-- calls RollOnLoot/ForceWinRoll on this client's behalf the moment the event fires -- before
-- LC_START even goes out. GetLootRollItemInfo goes blank (texture nil) once THIS client's roll has
-- been resolved, so by the time a vote-list refresh runs, the live call below already sees nothing
-- for the common case, and both gatherers fall through to the armor path -- which cannot judge
-- weapons at all. Capturing here, on our own frame, fixes that without touching Core.lua's
-- dispatcher, RollOnLoot/ForceWinRoll or lcAutoPass -- Blizzard's own roll stays exactly as it was.
--
-- WoW dispatches an event to every registered frame in the order each one called RegisterEvent; the
-- .toc loads this file BEFORE Core.lua, so this handler's RegisterEvent call always happens first
-- and this handler always sees the roll before Core.lua's dispatcher can act on it.
LC.relevanceSnapshot = LC.relevanceSnapshot or {}

local relevanceRollFrame = CreateFrame("Frame")
relevanceRollFrame:RegisterEvent("START_LOOT_ROLL")
relevanceRollFrame:SetScript("OnEvent", function(_, _, rollID)
    -- Same two cheap guards LC.OnStartLootRoll checks first -- NOT its councilEligible/councilEngages
    -- logic below them, which stays exactly once, in that function, so the two copies can't drift.
    -- Skipping module-off/no-session here just avoids snapshotting rolls this feature can never act
    -- on anyway (the module disabled, or no Council session running at all).
    if KART_Settings.lcModuleEnabled == false then return end
    if not LC.sessionActive then return end

    local texture, _, _, _, _, canNeed, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if texture then
        -- canNeed is stored RAW, not folded into a verdict. "Blizzard refused the Need roll" and
        -- "your class cannot equip this" are not the same statement -- see IsIrrelevantForMe,
        -- which is where the two are told apart, and B36 for what folding them cost.
        --
        -- Stamped with the ITEM it describes (B37, B38). A rollID alone does not identify a drop:
        -- Blizzard reuses one for a genuinely different item within seconds on trash, and this
        -- handler fires for every roll including the ones Council never engages -- a BoE or a
        -- collectible landing on a live rollID rewrote the verdict of the item being voted on.
        -- The reader compares against the item currently tracked and falls back rather than
        -- trusting a verdict that belongs to something else. Same medicine as LC.rollsFor for
        -- rolls, vote.item for votes and RemoveHistoryForRoll's itemLink for the loot history.
        local link = GetLootRollItemLink(rollID)
        LC.relevanceSnapshot[rollID] = {
            canNeed = canNeed,
            needsAppearance = not not canTransmog,
            item = (type(link) == "string" and link:match("item:(%d+)")) or nil,
        }
    end

    -- Self-limiting sweep, run on every roll rather than tied to a session ending: most rolls never
    -- reach Council (BoE, collectible, below the raid's rarity threshold -- see councilEngages in
    -- LC.OnStartLootRoll) and so never reach Trade.ClearRollState, which would otherwise be the only
    -- thing freeing this entry. Left unchecked, every such roll for the rest of the session would
    -- leave its snapshot behind. A nil texture is the same "roll is gone" signal LC.OnStartLootRoll's
    -- own retry loop already relies on -- cheap to reuse, needs no timestamp of our own.
    --
    -- Two entries must survive this sweep regardless: rollID itself (just written above, or a
    -- same-tick edge case where GetLootRollItemInfo already went blank -- either way not ours to
    -- judge here), and any roll still in LC.voteListRolls -- a roll reports no texture once IT has
    -- been rolled while its vote row can still be open for minutes, which is the entire reason this
    -- snapshot exists in the first place.
    -- LC.rollItems, not LC.voteListRolls (B42). A roll reaches the vote list one round trip after
    -- the local START_LOOT_ROLL on any client that is not the loot owner -- the owner's LC_DROP has
    -- to arrive first -- and by then Auto-Pass has already blanked GetLootRollItemInfo. On a boss
    -- dropping several items each roll's snapshot was therefore deleted while the NEXT one was
    -- being handled, so only the last item kept Blizzard's verdict and the rest fell through to
    -- the armor rule -- which answers nil for weapons and jewellery. LC.rollItems is the
    -- addon's own "am I tracking this" table and is populated by both entry paths at once.
    for id in pairs(LC.relevanceSnapshot) do
        if id ~= rollID and not LC.rollItems[id] then
            local stillLive = GetLootRollItemInfo(id)
            if not stillLive then LC.relevanceSnapshot[id] = nil end
        end
    end
end)

-- The snapshot for this roll, but only if it describes the item we are actually holding under that
-- rollID (B37, B38). Unknown on either side counts as belonging -- the same rule votes follow
-- (B46) -- because a roll still parked as "???" has no itemID to compare and refusing those
-- would throw away Blizzard's verdict for every client that was slow to resolve a link.
local function SnapshotFor(rollID, itemLink)
    local snap = rollID and LC.relevanceSnapshot[rollID]
    if not snap then return nil end
    local mine = (type(itemLink) == "string" and itemLink:match("item:(%d+)")) or nil
    if snap.item and mine and snap.item ~= mine then return nil end
    return snap
end

-- =====================================================================
--  What a class cannot use, for everything the armor-weight rule cannot judge
-- =====================================================================
-- The armor rule (Council.GetItemArmorRank / IsArmorEligible) answers cloth-to-plate and nothing
-- else, so weapons, shields and off-hands reached DecideAutoResponse as "not determinable" and were
-- treated as relevant. That is the whole of "Auto-Pass does not work for some people": a caster who
-- only ever sees weapons never saw the feature do anything, while a rogue looking at plate did.
--
-- Modelled on RCLootCouncil's Utils/autopass.lua, which has been carrying this in production for
-- years, in two layers that answer two different questions:
--
--   1. PROFICIENCY -- can this class wield this weapon type at all. A static table, because there is
--      no API that answers it and Blizzard's canNeed conflates it with three other refusals (B36).
--   2. MAIN STAT -- a rogue may wield a two-handed sword and still have no use for a strength one.
--      Proficiency cannot see that; the item's own stats can.
--
-- Both answer only in the direction that is cheap to be wrong in. Unknown stays unknown, which
-- DecideAutoResponse reads as relevant -- passing away somebody's upgrade is the expensive mistake.
local ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR = 2, 4
local ARMOR_SUBCLASS_SHIELD = 6 -- Enum.ItemArmorSubclass.Shield

-- [subclassID] = { CLASSFILE = true }: the classes that can NOT use that weapon type. Subclass IDs
-- are Enum.ItemWeaponSubclass, spelled out rather than read from the enum so this file still
-- compiles standalone for tests/test_lc_relevance.lua (same reason ARMOR_SUBCLASS_RANK does it).
local function Set(...)
    local t = {}
    for _, v in ipairs({...}) do t[v] = true end
    return t
end

local RANGED_AUTOPASS = { "DEATHKNIGHT", "PALADIN", "DRUID", "MONK", "SHAMAN", "PRIEST", "MAGE",
                          "WARLOCK", "DEMONHUNTER", "WARRIOR", "EVOKER" }

local WEAPON_AUTOPASS = {
    [0]  = Set("DRUID", "PRIEST", "MAGE", "WARLOCK"),                                    -- Axe1H
    [1]  = Set("DRUID", "ROGUE", "MONK", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER", "EVOKER"), -- Axe2H
    [2]  = Set(unpack(RANGED_AUTOPASS)),                                                 -- Bows
    [3]  = Set(unpack(RANGED_AUTOPASS)),                                                 -- Guns
    [4]  = Set("HUNTER", "MAGE", "WARLOCK", "DEMONHUNTER"),                              -- Mace1H
    [5]  = Set("MONK", "ROGUE", "HUNTER", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER"),   -- Mace2H
    [6]  = Set("ROGUE", "SHAMAN", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER", "EVOKER"), -- Polearm
    [7]  = Set("DRUID", "SHAMAN", "PRIEST"),                                             -- Sword1H
    [8]  = Set("DRUID", "MONK", "ROGUE", "SHAMAN", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER", "EVOKER"), -- Sword2H
    [9]  = Set("WARRIOR", "DEATHKNIGHT", "PALADIN", "DRUID", "MONK", "ROGUE", "PRIEST",
               "MAGE", "WARLOCK", "HUNTER", "SHAMAN", "EVOKER"),                         -- Warglaive
    [10] = Set("DEATHKNIGHT", "PALADIN", "ROGUE", "DEMONHUNTER"),                        -- Staff
    [13] = Set("DEATHKNIGHT", "PALADIN", "PRIEST", "MAGE", "WARLOCK"),                   -- Unarmed (fist)
    [15] = Set("DEATHKNIGHT", "PALADIN", "MONK", "DEMONHUNTER"),                         -- Dagger
    [18] = Set(unpack(RANGED_AUTOPASS)),                                                 -- Crossbow
    [19] = Set("WARRIOR", "DEATHKNIGHT", "PALADIN", "DRUID", "MONK", "ROGUE", "HUNTER",
               "SHAMAN", "DEMONHUNTER", "EVOKER"),                                       -- Wand
}

-- Shields sit in the ARMOR class but carry no armor weight, so GetItemArmorRank deliberately
-- returns nil for them and the weight rule never sees one. Three classes can hold one.
local SHIELD_AUTOPASS = Set("DEATHKNIGHT", "DRUID", "MONK", "ROGUE", "HUNTER", "PRIEST", "MAGE",
                            "WARLOCK", "DEMONHUNTER", "EVOKER")

-- The main stat(s) a weapon has to carry to be worth anything to a class. Same table RCLootCouncil
-- keeps, and the reason it exists: proficiency says a rogue may swing a two-handed sword, the stat
-- says a strength one is not theirs. A class with two entries (a healer/dps hybrid) keeps both.
local WEAPON_MAIN_STAT = {
    WARRIOR     = { "ITEM_MOD_STRENGTH_SHORT" },
    PALADIN     = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_INTELLECT_SHORT" },
    HUNTER      = { "ITEM_MOD_AGILITY_SHORT" },
    ROGUE       = { "ITEM_MOD_AGILITY_SHORT" },
    PRIEST      = { "ITEM_MOD_INTELLECT_SHORT" },
    DEATHKNIGHT = { "ITEM_MOD_STRENGTH_SHORT" },
    SHAMAN      = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_AGILITY_SHORT" },
    MAGE        = { "ITEM_MOD_INTELLECT_SHORT" },
    WARLOCK     = { "ITEM_MOD_INTELLECT_SHORT" },
    MONK        = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_AGILITY_SHORT" },
    DRUID       = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_AGILITY_SHORT" },
    DEMONHUNTER = { "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT" },
    EVOKER      = { "ITEM_MOD_INTELLECT_SHORT" },
}

-- true only when the weapon demonstrably carries a main stat and none of them is one this class
-- uses. Everything else -- stats not loaded yet, a weapon with no main stat at all (a caster
-- off-hand, a stat-stick trinket-shaped thing), an unknown class -- answers false, which leaves the
-- item relevant.
local function WeaponMainStatMismatch(itemLink, classFile)
    local wanted = WEAPON_MAIN_STAT[classFile]
    if not wanted then return false end
    if not C_Item.GetItemStats then return false end
    local stats = C_Item.GetItemStats(itemLink)
    if not stats then return false end
    if not (stats.ITEM_MOD_STRENGTH_SHORT or stats.ITEM_MOD_AGILITY_SHORT
            or stats.ITEM_MOD_INTELLECT_SHORT) then
        return false
    end
    for _, stat in ipairs(wanted) do
        if stats[stat] then return false end
    end
    return true
end

-- Does the item name the classes allowed to use it, and is ours missing from that list?
-- true / false / nil, where nil is "the item says nothing about classes".
--
-- This is the only rule that can judge a TIER TOKEN, and tier tokens are the whole reason it exists:
-- a token is Miscellaneous with no armor weight and no weapon subclass, so both rules above answer
-- nothing about it, and a raid on new content is a raid full of them. The restriction is not exposed
-- by any item API -- it lives in the tooltip, exactly as it does for RCLootCouncil, which has been
-- reading it there for years.
--
-- C_TooltipInfo.GetHyperlink rather than a hidden scanning frame: it returns the lines as data, so
-- there is no frame to own, no anchor to get wrong and nothing on screen to flicker.
--
-- Whitespace is stripped from both sides of the comparison and the list is wrapped in delimiters
-- before matching, so "Death Knight, Paladin" answers correctly for a Paladin without depending on
-- which delimiter the client's locale uses, and no class can match another as a prefix.
local function ClassLocked(itemLink, classDisplayName)
    if not (classDisplayName and ITEM_CLASSES_ALLOWED) then return nil end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return nil end
    local pattern = ITEM_CLASSES_ALLOWED:gsub("%%s", "(.+)")
    for _, line in ipairs(data.lines) do
        local listed = line.leftText and line.leftText:match(pattern)
        if listed then
            local haystack = "," .. listed:gsub("%s", "") .. ","
            local mine = "," .. classDisplayName:gsub("%s", "") .. ","
            return haystack:find(mine, 1, true) == nil
        end
    end
    return nil
end

-- true / false / nil, for the items the armor-weight rule cannot judge. nil means "no opinion",
-- never "cannot use".
local function CannotUseByType(itemLink, classFile)
    if not classFile then return nil end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(itemLink)
    -- Not cached yet. The vote row refreshes again once it is (see ResolveRollItemLink), and
    -- answering from missing data is how an item gets passed away.
    if not classID then return nil end

    if classID == ITEM_CLASS_ARMOR then
        if subclassID ~= ARMOR_SUBCLASS_SHIELD then return nil end -- the weight rule owns the rest
        return SHIELD_AUTOPASS[classFile] or false
    end
    if classID ~= ITEM_CLASS_WEAPON then return nil end -- jewellery, cloaks, anything else

    local blocked = WEAPON_AUTOPASS[subclassID]
    if blocked and blocked[classFile] then return true end
    return WeaponMainStatMismatch(itemLink, classFile)
end

-- Can this player's class not equip the item at all?  true / false / nil when undecidable.
--
-- The snapshot above is the accurate answer -- it is Blizzard's own eligibility verdict and covers
-- weapons as well as armor, with no per-class table to maintain across expansions. The live
-- GetLootRollItemInfo call below is kept as a fallback for a roll that somehow has no snapshot (a
-- START_LOOT_ROLL fired before our frame registered, e.g. mid-/reload), not as the primary path --
-- see the snapshot's own comment for why reading it live here would usually be too late. The armor
-- fallback beneath that exists for the rest: /kart add items, which never had a Blizzard roll at
-- all, and clients that missed the roll through death or distance and only learned of the item
-- through the LC_DROP announcement. That path cannot judge weapons, so it returns nil for them
-- rather than guessing.
local function IsIrrelevantForMe(rollID, itemLink)
    -- Blizzard's canNeed, from the snapshot or live, in that order (see above for why live is
    -- only a fallback).
    local canNeed
    local snap = SnapshotFor(rollID, itemLink)
    if snap then
        canNeed = snap.canNeed
    elseif rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, live = GetLootRollItemInfo(rollID)
        -- A nil texture means there is no live roll under this ID on our client, not that we are
        -- ineligible -- leave canNeed unknown rather than reading nil as "cannot use".
        if texture then canNeed = live end
    end

    -- A Need roll Blizzard allows settles it: this is ours to take.
    if canNeed == true then return false end

    -- It does NOT settle the other direction (B36). canNeed comes back false for a wrong loot
    -- specialization, a level requirement and a unique-equipped item exactly as it does for
    -- armor this class can never wear -- one boolean for four questions, and only the last is
    -- what this feature means. A Holy Paladin was never shown the strength plate chest they
    -- would have taken for off-spec, which is the case the feature was written for (GitHub #11).
    --
    -- So the question is asked again, of the one check that answers exactly it: our own armor
    -- class table. It answers "eligible" whenever it is unsure, which is the direction that
    -- cannot pass away somebody's upgrade -- and it returns nil for weapons and jewellery, which
    -- reaches DecideAutoResponse as "not determinable" and is treated as relevant.
    if not LC.IsRealItemLink(itemLink) then return nil end
    local classDisplay, classFile = UnitClass("player")
    -- Asked first, because it is the only one of the three that is a STATEMENT BY THE ITEM rather
    -- than a rule of ours, and the only one that can answer for a tier token at all.
    local locked = ClassLocked(itemLink, classDisplay)
    if locked ~= nil then return locked end
    local rank = KART.LC.Council.GetItemArmorRank(itemLink)
    if rank then return not KART.LC.Council.IsArmorEligible(classFile, rank) end
    -- No armor weight to judge: jewellery and cloaks (nobody is barred from those, so this answers
    -- nil for them), but also every weapon and every shield -- which used to end here as "not
    -- determinable" and is what CannotUseByType exists for.
    return CannotUseByType(itemLink, classFile)
end

-- Does the player still need this item's appearance?  true / false / nil when undecidable.
--
-- The snapshot's canTransmog already means "collectible by me and not yet owned", so it is used
-- wherever it exists; the live call below is only the fallback described above. Without either,
-- C_TransmogCollection answers the same question in two steps: an item with no appearance source
-- (rings, necks, trinkets) can never be needed, and one with a source is needed exactly while it is
-- uncollected.
local function NeedsAppearance(rollID, itemLink)
    local snap = SnapshotFor(rollID, itemLink)
    if snap then return snap.needsAppearance end
    if rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, _, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        if texture then return not not canTransmog end
    end
    if not LC.IsRealItemLink(itemLink) then return nil end
    if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then return nil end
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID then return false end -- no appearance to collect
    -- CAN this character learn it, asked before "do I already have it" (B39). The two are
    -- different questions and only the second was being asked -- the sourceID sat unused in the
    -- same return. An appearance nobody in this armor class can ever collect is not "needed" no
    -- matter how uncollected it is, and voting Transmog on it puts this player's name on an item
    -- the council then awards them.
    --
    -- Only a definite NO counts. A missing sourceID or a client without the API leaves the
    -- question to the ownership check below, which is the direction that cannot silently drop a
    -- vote the player wanted.
    if sourceID and C_TransmogCollection.PlayerCanCollectSource
       and C_TransmogCollection.PlayerCanCollectSource(sourceID) == false then
        return false
    end
    if not C_TransmogCollection.PlayerHasTransmogByItemInfo then return nil end
    return not C_TransmogCollection.PlayerHasTransmogByItemInfo(itemLink)
end

-- Answers every pending roll that has not been answered yet. Called once per vote-list refresh,
-- which covers a fresh roll, a cast vote, an expiry sweep and -- the case that needs it -- the
-- refresh ResolveRollItemLink triggers once a link that started out as "???" has arrived.
-- The automatic Transmog vote is switched off at the source, on the maintainer's call (2026-08-05):
-- it did not do what it says in a real raid, and the tier ends before there is another one to test a
-- repair in. Switched off HERE rather than deleted, because everything it needs is correct and
-- tested -- NeedsAppearance, DecideAutoResponse's transmog branch, LC.GetTransmogButtonIndex -- and
-- what was wrong was never established. Reviving it is this constant plus the checkbox in
-- LootCouncilSettings.lua, both marked with this date.
--
-- The checkbox is gone with it, so nobody can turn it on; this line is what also switches it off for
-- the people who already had it ticked, whose SavedVariables still say true.
local AUTO_TRANSMOG_ENABLED = false

function LC.Relevance.ApplyToPendingRolls()
    local hide = KART_Settings and KART_Settings.lcHideIrrelevant
    local mog  = AUTO_TRANSMOG_ENABLED and KART_Settings and KART_Settings.lcAutoTransmogVote
    if not (hide or mog) then return end

    local stamp = SettingsStamp(hide, mog)

    for _, rollID in ipairs(LC.voteListRolls) do
        -- Test rolls are exempt: /kart test exists to show what the window looks like, and a filter
        -- that empties it defeats that. A vote the PLAYER cast is final and ends the matter for that
        -- roll; one this file cast is not, and is reconsidered only when the settings behind it
        -- actually changed -- which is what keeps a refresh from voting twice (B50).
        local playerVoted = LC.votedByMe[rollID] and not LC.autoVotedByMe[rollID]
        if not LC.IsTestRoll(rollID) and not playerVoted and LC.relevanceHandled[rollID] ~= stamp then
            local itemLink = LC.rollItems[rollID]
            -- Nothing is decidable without a link; leave the roll pending and try again on the
            -- refresh that ResolveRollItemLink fires once it has one.
            if LC.IsRealItemLink(itemLink) then
                local answer = LC.Relevance.DecideAutoResponse({
                    irrelevant      = IsIrrelevantForMe(rollID, itemLink),
                    needsAppearance = NeedsAppearance(rollID, itemLink),
                    hideIrrelevant  = hide and true or false,
                    autoTransmog    = mog and true or false,
                })
                if answer then
                    local idx = (answer == "transmog") and LC.GetTransmogButtonIndex() or LC.GetPassButtonIndex()
                    if idx then
                        -- Marked handled BEFORE the vote, and that order is load-bearing: CastVote
                        -- ends in an unconditional RefreshVoteListRows, which calls this function
                        -- again from inside itself. Without the stamp already set, that re-entry
                        -- would answer the same roll again and recurse until the stack gives out.
                        LC.relevanceHandled[rollID] = stamp
                        -- Assigned per answer, not only set: on a re-answer under changed settings
                        -- the previous run's Pass may have hidden this row, and a Transmog vote is
                        -- not a reason to keep it hidden.
                        LC.hiddenIrrelevant[rollID] = (answer == "pass") or nil
                        -- Only when the answer actually CHANGED. A settings toggle mid-boss
                        -- reconsiders every item on screen at once, and most of them come out the
                        -- same way -- a burst of identical LC_VOTE messages is exactly what
                        -- Blizzard's chat throttle swallows, taking somebody else's message with it.
                        -- The stamp and the hide flag above are the parts that always have to be
                        -- brought up to date; the vote is already what it should be.
                        if LC.votedByMe[rollID] ~= idx or not LC.autoVotedByMe[rollID] then
                            LC.Vote.CastVote(rollID, idx, nil, true)
                        end
                    end
                end
            end
        end
    end
end
