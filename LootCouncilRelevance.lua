local _, KART = ...
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
LC.relevanceHandled = LC.relevanceHandled or {}

-- [rollID] = true for a row hidden because the player cannot use the item. Read by
-- Vote.GetVisibleRolls next to the lcVotedItemDisplay == "hide" case.
LC.hiddenIrrelevant = LC.hiddenIrrelevant or {}

-- [rollID] = true when the vote on that roll was cast by this file rather than by the player.
-- Vote.CastVote lets an automatic vote be overridden once; a manual one still locks.
LC.autoVotedByMe = LC.autoVotedByMe or {}

-- Can this player's class not equip the item at all?  true / false / nil when undecidable.
--
-- GetLootRollItemInfo is the accurate answer -- it is Blizzard's own eligibility verdict and covers
-- weapons as well as armor, with no per-class table to maintain across expansions. It is only
-- available while a real roll is live on THIS client, which is the normal case: Blizzard fires
-- START_LOOT_ROLL even for an item the class cannot use (confirmed by the maintainer, 2026-07-28).
-- The armor fallback below exists for the rest: /kart add items, which never had a Blizzard roll at
-- all, and clients that missed the roll through death or distance and only learned of the item
-- through LC_START. That path cannot judge weapons, so it returns nil for them rather than guessing.
local function IsIrrelevantForMe(rollID, itemLink)
    if rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, canNeed = GetLootRollItemInfo(rollID)
        -- A nil texture means there is no live roll under this ID on our client, not that we are
        -- ineligible -- fall through instead of reading canNeed's nil as "cannot use".
        if texture then return not canNeed end
    end
    if not LC.IsRealItemLink(itemLink) then return nil end
    local rank = KART.LC.Council.GetItemArmorRank(itemLink)
    if not rank then return nil end -- jewellery, weapons, shields: no armor-weight restriction
    local _, classFile = UnitClass("player")
    return not KART.LC.Council.IsArmorEligible(classFile, rank)
end

-- Does the player still need this item's appearance?  true / false / nil when undecidable.
--
-- canTransmog from the live roll already means "collectible by me and not yet owned", so it is used
-- wherever it exists. Without a roll, C_TransmogCollection answers the same question in two steps:
-- an item with no appearance source (rings, necks, trinkets) can never be needed, and one with a
-- source is needed exactly while it is uncollected.
local function NeedsAppearance(rollID, itemLink)
    if rollID and not LC.IsTestRoll(rollID) then
        local texture, _, _, _, _, _, _, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollID)
        if texture then return not not canTransmog end
    end
    if not LC.IsRealItemLink(itemLink) then return nil end
    if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then return nil end
    local appearanceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not appearanceID then return false end -- no appearance to collect
    if not C_TransmogCollection.PlayerHasTransmogByItemInfo then return nil end
    return not C_TransmogCollection.PlayerHasTransmogByItemInfo(itemLink)
end

-- Answers every pending roll that has not been answered yet. Called once per vote-list refresh,
-- which covers a fresh roll, a cast vote, an expiry sweep and -- the case that needs it -- the
-- refresh ResolveRollItemLink triggers once a link that started out as "???" has arrived.
function LC.Relevance.ApplyToPendingRolls()
    local hide = KART_Settings and KART_Settings.lcHideIrrelevant
    local mog  = KART_Settings and KART_Settings.lcAutoTransmogVote
    if not (hide or mog) then return end

    for _, rollID in ipairs(LC.voteListRolls) do
        -- Test rolls are exempt: /kart test exists to show what the window looks like, and a filter
        -- that empties it defeats that. Already-voted and already-handled rolls are left alone so a
        -- refresh cannot vote twice.
        if not LC.IsTestRoll(rollID) and not LC.votedByMe[rollID] and not LC.relevanceHandled[rollID] then
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
                        LC.relevanceHandled[rollID] = true
                        LC.autoVotedByMe[rollID]    = true
                        if answer == "pass" then LC.hiddenIrrelevant[rollID] = true end
                        LC.Vote.CastVote(rollID, idx, nil)
                    end
                end
            end
        end
    end
end
