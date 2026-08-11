-- The council panel's rows: what each one says about the raider on it.
--
-- This is the screen the item is handed out from. Every signal on a row is a colour, a width or a
-- shown/hidden flag, and a wrong one does not look broken -- it looks like an answer. A row wrongly
-- highlighted as the winner, a straw-poll bar filled when nobody voted, a roll of 85 styled as
-- though it were not the highest in the raid: each of those is read as fact by whoever is deciding.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim, lm = F.NewRaid()
local LC = lm.KART.LC
local Council = LC.Council
local ROLL = 80

F.Drop(sim, ROLL, F.GLOVES)
local panel = LC.councilPanel
T.truthy(panel, "the council panel is up")

local function Refresh() RaidSim.As(lm, Council.RefreshCouncilRows) end
local function Rows()
    local out = {}
    for i = 1, #(panel.rows or {}) do
        local row = panel.rows[i]
        if row and row:IsShown() then out[#out + 1] = row end
    end
    return out
end
-- The identity key the panel stores on a row, resolved the way the panel itself resolves it.
local function KeyOf(client)
    return RaidSim.As(lm, function() return (lm.KASC.Identity.ResolvePlayer(client.unit)) end)
end

local function RowFor(key)
    for _, row in ipairs(Rows()) do if row.memberKey == key then return row end end
end

Refresh()
T.truthy(#Rows() > 1, "with a row per raider")

-- Who won it ---------------------------------------------------------------------------------------
do
    -- The winning row is the only one wearing the gold. It is scoped per roll on purpose, and the
    -- guard that scopes it is also what stops EVERY row wearing it -- which is not a subtle
    -- difference on screen, but it is one nobody would report as a bug, because a panel where
    -- everybody is highlighted reads as "the highlight does not mean anything here".
    local alric = sim.byName.Alric
    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = KeyOf(alric) end)
    Refresh()

    local gold = 0
    for _, row in ipairs(Rows()) do
        local r, g, b = row:GetBackdropColor()
        if r == 0.28 and g == 0.21 and b == 0.03 then gold = gold + 1 end
    end
    T.eq(gold, 1, "exactly one row is marked as the winner")

    RaidSim.As(lm, function() LC.assignedWinners[ROLL] = nil end)
    Refresh()
    local any = 0
    for _, row in ipairs(Rows()) do
        local r = row:GetBackdropColor()
        if r == 0.28 then any = any + 1 end
    end
    T.eq(any, 0, "and none at all before anything is assigned")
end

-- The unassigned rows ------------------------------------------------------------------------------
do
    -- Alternating shading again, and again both halves have to be an opacity: a boolean is
    -- different from 0.1 and is not a shade.
    Refresh()
    local rows = Rows()
    local _, _, _, a1 = rows[1]:GetBackdropColor()
    local _, _, _, a2 = rows[2]:GetBackdropColor()
    T.eq(type(a1), "number", "a row's shading is an opacity")
    T.eq(type(a2), "number", "and so is its neighbour's")
    T.truthy(a1 ~= a2, "and neighbouring rows are shaded apart")
end

-- A class this client does not know ----------------------------------------------------------------
do
    -- The council panel colours the name by the raider's class, read from the roster. A class token
    -- this client has no colour for is an ordinary state on a patch boundary -- somebody logs in on
    -- a class the viewer's client predates -- and the name has to fall back rather than be read off
    -- nothing.
    local alric = sim.byName.Alric
    local realClass = alric.member.class
    alric.member.class = "TINKER"
    local ok = pcall(Refresh)
    T.truthy(ok, "a raider whose class this client does not know still gets a row")

    local row = RowFor(KeyOf(alric))
    if row then
        local r, g, b = row.nameText:GetTextColor()
        T.truthy(r == 0.8 and g == 0.8 and b == 0.8, "with the neutral name colour")
        -- ...and no class icon, rather than a slice of the circle sheet picked at random. Which cell
        -- belongs to which class is not asserted anywhere and must not be: the harness's grid is a
        -- stand-in. That an unknown token yields NO cell is the part that matters.
        T.truthy(not row.classIcon:IsShown(), "and no class icon at all")
    else
        T.truthy(false, "the raider is still on the panel")
    end
    alric.member.class = realClass
    Refresh()

    row = RowFor(KeyOf(alric))
    T.truthy(row and row.classIcon:IsShown(), "while a class it does know gets one")
    T.truthy(row and row.classIcon:GetTexture() ~= nil, "drawn from the shared circle sheet")
end

-- The roll column ----------------------------------------------------------------------------------
do
    -- 85 and up is the "hot roll" styling. The threshold is inclusive, and 85 itself is the value it
    -- exists for: on a 1-100 roll the difference between 84 and 85 is one number, and a council
    -- scanning the column for the high rolls is exactly what the brighter gold is for.
    lm.env.KART_Settings.lcRollsEnabled = true
    local alric = sim.byName.Alric
    local key = KeyOf(alric)
    LC.rolls[ROLL] = LC.rolls[ROLL] or {}

    LC.rolls[ROLL][key] = 85
    Refresh()
    local row = RowFor(key)
    T.truthy(row and row.rollText:GetText():find("ffe066", 1, true),
        "a roll of exactly 85 is styled as a high one")

    LC.rolls[ROLL][key] = 84
    Refresh()
    row = RowFor(key)
    T.truthy(row and row.rollText:GetText():find("ffd200", 1, true),
        "and 84 is not")
    LC.rolls[ROLL][key] = nil

    -- ...and an empty cell has to say WHICH kind of empty it is (B162, Manifest C13) -----------------
    -- C13 states it outright: "An empty roll cell must mean 'this person is not in this decision',
    -- never 'their number did not make it'. If a number is genuinely unknown, the panel has to say so
    -- rather than render the same dash a non-participant gets." The reason is in the same item: the
    -- council cannot see that a column is incomplete, because a missing 97 and a missing 3 look
    -- identical -- so the whole value of the feature depends on the set being whole, and the council
    -- has to be able to tell that it is not.
    --
    -- The two states are separable, and the discriminator is the table rather than the cell: the owner
    -- draws for everybody in its roster snapshot and the numbers travel as ONE message, so a client
    -- either holds the whole table or none of it. No table under a roll this client tracks, with rolls
    -- on raid-wide, is "the numbers have not arrived"; a table that simply has no entry for this raider
    -- is "not in this decision", which is what the dash has always meant.
    local heldRolls = LC.rolls[ROLL]
    LC.rolls[ROLL] = nil
    Refresh()
    row = RowFor(key)
    local unknownCell = row and row.rollText:GetText()
    T.truthy(unknownCell and unknownCell:find(lm.KART.L.LC_ROLL_UNKNOWN, 1, true),
        "B162: a roll column this client holds no numbers for says so instead of showing a dash")
    T.truthy(row and row.rollHitbox and row.rollHitbox:IsMouseEnabled(),
        "B162: ...and the cell explains itself, like the vote column's own unknown marker")

    -- The other kind of empty, unchanged: the table is here and this raider is not in it.
    LC.rolls[ROLL] = { ["someone-else"] = 50 }
    Refresh()
    row = RowFor(key)
    T.truthy(row and row.rollText:GetText():find("444444", 1, true),
        "B162: a raider who is not in the decision still gets the plain dash")
    T.truthy(row and row.rollHitbox and not row.rollHitbox:IsMouseEnabled(),
        "B162: with nothing to explain")

    LC.rolls[ROLL] = heldRolls
end

-- The straw-poll button ----------------------------------------------------------------------------
do
    -- The fill behind the count is the share of the council that picked this raider. With nobody
    -- picked, there is no share -- and a bar drawn at zero width is still a bar: it reads as "this
    -- one has something" on a row where nothing has happened.
    Refresh()
    local row = Rows()[1]
    T.truthy(row.councilVoteBtn and row.councilVoteBtn.fill, "the straw-poll button has a fill")
    T.truthy(not row.councilVoteBtn.fill:IsShown(), "which is not drawn before anybody has picked")
end

-- The panel's own chrome ---------------------------------------------------------------------------
do
    -- The roll and gain column headers follow their settings, and both are hidden while the panel is
    -- minimized. "Or" instead of "and" leaves a header standing over a collapsed panel, in the empty
    -- space below it, on every incoming vote.
    lm.env.KART_Settings.lcRollsEnabled = false
    panel.isMinimized = false
    Refresh()
    T.truthy(not panel.hRoll:IsShown(), "the roll header follows its setting")

    lm.env.KART_Settings.lcRollsEnabled = true
    Refresh()
    T.truthy(panel.hRoll:IsShown(), "and comes back when it is switched on")

    panel.isMinimized = true
    Refresh()
    T.truthy(not panel.hRoll:IsShown(), "while a minimized panel keeps it hidden regardless")
    panel.isMinimized = false
    Refresh()
end

do
    -- The tab strip is the same rule one level up: it is there when there are tabs, and gone while
    -- the panel is collapsed.
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(panel.tabStrip:IsShown(), "the tab strip is up while a roll is running")

    local saved = LC.councilTabs
    LC.councilTabs = {}
    RaidSim.As(lm, Council.RefreshCouncilTabs)
    T.truthy(not panel.tabStrip:IsShown(), "and gone once no tab is left in it")
    LC.councilTabs = saved
    RaidSim.As(lm, Council.RefreshCouncilTabs)
end

-- A panel the player closed stays closed (B123) -------------------------------------------------------
-- The config owner re-broadcasts on every roster change, and an accepted config opens a tab for
-- everything already on the table (B61). For a council member who had closed the panel that meant it
-- came back on every port-out, relog and promotion in the raid -- which in this guild is constantly.
-- Reported as "he votes on everything, closes the window, and it opens again immediately".
do
    -- A raid of its own, not the file-level one: this case closes the panel and reopens it, and the
    -- assertions above depend on that one staying as they left it.
    local ownSim, ownLm, council = F.NewRaid()
    F.Drop(ownSim, 96, F.GLOVES, { bop = true })
    KARTTEST.AdvanceTime(1)
    T.truthy(council.KART.LC.councilPanel and council.KART.LC.councilPanel:IsShown(),
        "the council member's panel is up for the item")

    RaidSim.As(council, function() council.KART.LC.councilPanel:Hide() end)

    -- The roster moves: somebody ports out, relogs, is promoted. The config goes out again and is
    -- accepted again, exactly as before.
    RaidSim.As(ownLm, function() ownLm.KART.LC.BroadcastRaidConfig() end)
    KARTTEST.AdvanceTime(0)
    T.truthy(not council.KART.LC.councilPanel:IsShown(),
        "a re-broadcast config does not force the window back open")

    -- A genuinely new item does, which is the whole job of the function that was doing the forcing.
    F.Drop(ownSim, 97, F.WEAPON, { bop = true })
    KARTTEST.AdvanceTime(1)
    T.truthy(council.KART.LC.councilPanel:IsShown(), "but a new item brings it back")
end

-- The equipped column on a tier token -----------------------------------------------------------
-- A token carries no equipLoc of its own, so the slot it is worn in cannot be read off the item --
-- and the whole equipped-gear comparison used to give up on exactly the drops the council argues
-- hardest about (Manifest C12). The slot comes out of a table of token ids instead.
do
    local ownSim, ownLm = F.NewRaid()
    KARTTEST.AddItem({ id = 800002, name = "Voidwoven Mantle", quality = 4, ilvl = 280,
                       classID = 4, subclassID = 1, equipLoc = "INVTYPE_SHOULDER", bind = 1 })
    -- The inventory stub is keyed by slot number and shared by every simulated client, so this puts
    -- the same shoulders on the whole raid -- see test_lc_equipexchange.
    KARTTEST.inventory[3] = KARTTEST.items[800002].link

    RaidSim.ClearLog(ownSim)
    -- 249364 is a Voidcured Unraveled Nullcore: a shoulder token.
    F.Drop(ownSim, 90, F.TOKEN)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.truthy(#RaidSim.Sent(ownSim, "REQ_EQUIP:INVTYPE_SHOULDER") > 0,
        "a shoulder token asks the raid for their shoulders")

    RaidSim.Drain(ownSim, 5)
    local alric = ownSim.byName.Alric
    RaidSim.As(ownLm, function()
        local link = ownLm.KART.LC.Council.GetEquippedForUnit(alric.unit,
            ownLm.KART.LC.rollItems[90])
        T.eq(link, KARTTEST.items[800002].link, "and the column shows what they wear there")
    end)
    KARTTEST.inventory[3] = nil
end

-- A token nothing knows the slot of ---------------------------------------------------------------
-- The table is an allow-list, exactly like the collectible rule it sits next to: an id that is not in
-- it leaves the column empty, which is what it did before. A guessed slot would put somebody else's
-- gear on the row that hands the item out.
do
    local ownSim, ownLm = F.NewRaid()
    KARTTEST.AddItem({ id = 800003, name = "Nullcore of a Later Tier", quality = 4, ilvl = 285,
                       classID = 15, subclassID = 0, bind = 1 })
    RaidSim.ClearLog(ownSim)
    F.Drop(ownSim, 91, 800003)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.eq(#RaidSim.Sent(ownSim, "REQ_EQUIP:"), 0,
        "a token this client has no slot for asks nobody")
end

-- "x of y council members have voted" ---------------------------------------------------------------
-- The per-candidate tally says who is ahead; it does not say whether everyone has spoken. A council
-- member whose votes never arrive looks exactly like one who is still thinking (Manifest C14), and
-- the lootmaster hands the item out either way.
do
    local ownSim, ownLm = F.NewRaid()
    F.Drop(ownSim, 88, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    local ownPanel = ownLm.KART.LC.councilPanel
    local council = { ownSim.byName.Bramor, ownSim.byName.Merrit, ownSim.byName.Corvin }
    local alric = ownSim.byName.Alric
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(alric.unit))
    end)
    local L = ownLm.KART.L

    local function ProgressText()
        RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
        return ownPanel.voteProgressText:GetText()
    end

    T.eq(ProgressText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 0, 3),
        "a council of three with nobody voted yet says so")

    RaidSim.As(council[1], function() council[1].KART.LC.Vote.ToggleCouncilVote(88, alricKey) end)
    RaidSim.As(council[2], function() council[2].KART.LC.Vote.ToggleCouncilVote(88, alricKey) end)
    RaidSim.Drain(ownSim, 5)
    T.eq(ProgressText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 2, 3),
        "two of the three having picked reads as two of three")
    local r, g, b = ownPanel.voteProgressText:GetTextColor()
    T.truthy(not (r < g and b < g), "and is not yet wearing the everybody-has-voted colour")

    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(88, alricKey) end)
    RaidSim.Drain(ownSim, 5)
    T.eq(ProgressText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 3, 3),
        "and the last one completes it")
    local r2, g2, b2 = ownPanel.voteProgressText:GetTextColor()
    T.truthy(r2 < g2 and b2 < g2, "which is what the colour says too")

    -- A retracted pick is a council member who has not decided again, not one who has.
    RaidSim.As(council[3], function() council[3].KART.LC.Vote.ToggleCouncilVote(88, alricKey) end)
    RaidSim.Drain(ownSim, 5)
    T.eq(ProgressText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 2, 3),
        "and taking a pick back counts back down")
end

-- ...counted against the council that is actually HERE ----------------------------------------------
-- LC.CouncilNamesTable is the AUTHORIZATION list and is deliberately roster-independent: a key stays
-- in it long after that person left, because it decides whose LC_CVOTE is accepted, not who is
-- online. As a denominator it is the wrong list. A council of four with one member not raiding
-- tonight -- somebody on holiday, somebody who logged in on an alt -- can never reach "everyone has
-- spoken", so the line sits on "3 of 4" in the waiting colour for every item, all night, and the one
-- thing it was added to say (Manifest C14: is anybody still missing?) becomes a permanent yes.
do
    local ownSim, ownLm = F.NewRaid()
    RaidSim.As(ownLm, function()
        ownLm.env.KART_Settings.lcCouncilMembers = "Bramor;Merrit;Corvin;Nichthier"
        ownLm.KART.LC.ApplyOwnConfig()
        ownLm.KART.LC.BroadcastRaidConfig()
    end)
    KARTTEST.AdvanceTime(1)
    F.Drop(ownSim, 89, F.GLOVES)
    KARTTEST.AdvanceTime(1)

    local ownPanel = ownLm.KART.LC.councilPanel
    local council = { ownSim.byName.Bramor, ownSim.byName.Merrit, ownSim.byName.Corvin }
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(ownSim.byName.Alric.unit))
    end)
    local L = ownLm.KART.L

    T.truthy(RaidSim.As(ownLm, function()
        local n = 0
        for _ in pairs(ownLm.KART.LC.CouncilNamesTable or {}) do n = n + 1 end
        return n
    end) == 4, "the council list really does name four")

    for _, c in ipairs(council) do
        RaidSim.As(c, function() c.KART.LC.Vote.ToggleCouncilVote(89, alricKey) end)
    end
    RaidSim.Drain(ownSim, 5)
    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)

    T.eq(ownPanel.voteProgressText:GetText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 3, 3),
        "everyone in the raid having picked reads as complete, not as three of four")
    local r, g, b = ownPanel.voteProgressText:GetTextColor()
    T.truthy(r < g and b < g, "and wears the everybody-has-voted colour")
end

-- An empty straw-poll stamp still counts as "cannot tell" (B149 gap 3) -------------------------------
-- The straw poll's own version of the two-part guard in LC.VoteIsForItem (see test_lc_votes.lua for
-- the plain-vote half). Vote.ToggleCouncilVote stamps its pick with TrackedItemID(rollID), which is ""
-- when the PICKER's own copy is still "???". Losing the stamped=="" branch on the receiving side
-- compares that "" against the reader's real itemID and drops the pick from the answered count.
do
    local ownSim, ownLm = F.NewRaid()
    local corvin = ownSim.byName.Corvin
    local alric = ownSim.byName.Alric
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(alric.unit))
    end)
    local L = ownLm.KART.L

    -- Corvin's own copy of the item never arrives -- the same "???" construction test_lc_rolltable.lua
    -- uses (a blackholed LC_DROP, then a hand-fed LC_START-shaped message with no item field).
    RaidSim.Blackhole(ownSim, "LC_DROP")
    F.Drop(ownSim, 200, F.GLOVES, { noRollFor = { Corvin = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(ownSim, "LC_DROP")
    RaidSim.As(corvin, function() corvin.KART.LC.HandleStart("200:20:", ownLm.guid) end)
    T.eq(corvin.KART.LC.rollItems[200], "???", "corvin holds an item it cannot read")

    RaidSim.As(corvin, function() corvin.KART.LC.Vote.ToggleCouncilVote(200, alricKey) end)
    KARTTEST.AdvanceTime(1)

    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.eq(ownLm.KART.LC.councilPanel.voteProgressText:GetText(),
        string.format(L.LC_COUNCIL_VOTES_PROGRESS, 1, 3),
        "a pick with an empty item stamp still counts toward the answered total")
end

-- An unreadable OWN item does not blank the straw poll either (B149 gap 4) ---------------------------
-- The other half: here the READER cannot read its own copy, while the picker's real stamp is fine.
-- Losing the mine=="" branch compares that real stamp against the reader's "" and the pick disappears
-- from a screen that is otherwise voting normally.
do
    local ownSim, ownLm, merrit, alric = F.NewRaid()
    local corvin = ownSim.byName.Corvin
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(alric.unit))
    end)

    RaidSim.Blackhole(ownSim, "LC_DROP")
    F.Drop(ownSim, 201, F.GLOVES, { noRollFor = { Corvin = true } })
    KARTTEST.AdvanceTime(1)
    RaidSim.Deliver(ownSim, "LC_DROP")
    RaidSim.As(corvin, function() corvin.KART.LC.HandleStart("201:20:", ownLm.guid) end)
    T.eq(corvin.KART.LC.rollItems[201], "???", "corvin cannot read its own copy of the item")

    RaidSim.As(merrit, function() merrit.KART.LC.Vote.ToggleCouncilVote(201, alricKey) end)
    KARTTEST.AdvanceTime(1)

    T.truthy(corvin.KART.LC.councilPanel, "corvin still gets a council panel for the item")
    RaidSim.As(corvin, corvin.KART.LC.Council.RefreshCouncilRows)
    T.eq(corvin.KART.LC.councilPanel.voteProgressText:GetText(),
        string.format(corvin.KART.L.LC_COUNCIL_VOTES_PROGRESS, 1, 3),
        "a real-stamped pick still counts on a client that cannot read its own item")
end

-- "x of y" stops counting a council member the moment they leave (B149 gap 5) ------------------------
-- The council SIZE denominator (LootCouncilPanel.lua:1121, one line up) is already covered against
-- LC.CouncilNamesTable's roster-independence -- a listed member not currently in the raid does not
-- inflate y (see the "counted against the council that is actually HERE" case above). The ANSWER
-- count on the line below it needs the same presence check and had no test of its own: a pick from
-- somebody who has since left stayed in x forever, because LC.CouncilNamesTable never forgets a name.
do
    local ownSim, ownLm = F.NewRaid()
    local corvin = ownSim.byName.Corvin
    local alric = ownSim.byName.Alric
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(alric.unit))
    end)
    local L = ownLm.KART.L

    F.Drop(ownSim, 210, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(corvin, function() corvin.KART.LC.Vote.ToggleCouncilVote(210, alricKey) end)
    KARTTEST.AdvanceTime(1)

    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.eq(ownLm.KART.LC.councilPanel.voteProgressText:GetText(),
        string.format(L.LC_COUNCIL_VOTES_PROGRESS, 1, 3), "corvin's pick counts while corvin is here")

    RaidSim.Leave(ownSim, "Corvin")
    RaidSim.RosterUpdate(ownSim)
    KARTTEST.AdvanceTime(5)

    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.eq(ownLm.KART.LC.councilPanel.voteProgressText:GetText(),
        string.format(L.LC_COUNCIL_VOTES_PROGRESS, 0, 2),
        "and stops counting once corvin is gone, though the denominator drops with them too")
end

-- The per-candidate tally stops counting the same departed pick (B149 gap 6) -------------------------
-- The other reader of a straw-poll pick: the candidate's OWN row, which fills a bar for how many
-- council members picked THEM. Same rule, same list, and this is the row the lootmaster actually
-- reads before assigning -- a bar still filled here reads as a live endorsement from somebody no
-- longer in the raid to answer for it.
do
    local ownSim, ownLm = F.NewRaid()
    local corvin = ownSim.byName.Corvin
    local alric = ownSim.byName.Alric
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(alric.unit))
    end)

    F.Drop(ownSim, 211, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(corvin, function() corvin.KART.LC.Vote.ToggleCouncilVote(211, alricKey) end)
    KARTTEST.AdvanceTime(1)

    local function PollFilled(key)
        RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
        for _, row in ipairs(ownLm.KART.LC.councilPanel.rows or {}) do
            if row.memberKey == key and row:IsShown() then
                return row.councilVoteBtn.fill:IsShown()
            end
        end
    end

    T.truthy(PollFilled(alricKey),
        "corvin's pick fills alric's straw-poll bar while corvin is in the raid")

    RaidSim.Leave(ownSim, "Corvin")
    RaidSim.RosterUpdate(ownSim)
    KARTTEST.AdvanceTime(5)

    T.truthy(not PollFilled(alricKey), "and the bar empties once corvin is gone")
end

-- ...and NOT counted when the pick was about the previous item under that number (B166) -------------
-- LC.CouncilVoteIsForItem exists because Vote.HandleCouncilVote's own comment promised a pick naming a
-- different item would be "kept, not dropped, and filtered when it is read" -- and nothing read it. So
-- both consumers of LC.councilVotes counted a pick made about the previous occupant of a reused rollID:
-- the "x of y have voted" line above, and the per-candidate tally on the row.
--
-- The function was added in v3.3.2..HEAD with no test at all, found by mutating it to `return true` --
-- the whole suite stayed green. Which matters more than usual here: the two numbers this filters sit
-- side by side on the screen the item is handed out from, and a council reading "0 of 3 have voted"
-- beside a candidate wearing a 1 has no way to tell which of them is lying.
do
    local ownSim, ownLm = F.NewRaid()
    F.Drop(ownSim, 91, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    local ownPanel = ownLm.KART.LC.councilPanel
    local L = ownLm.KART.L
    local alricKey = RaidSim.As(ownLm, function()
        return (ownLm.KASC.Identity.ResolvePlayer(ownSim.byName.Alric.unit))
    end)

    -- Three council members pick, all about the item that is actually on the table.
    for _, name in ipairs({ "Bramor", "Merrit", "Corvin" }) do
        local c = ownSim.byName[name]
        RaidSim.As(c, function() c.KART.LC.Vote.ToggleCouncilVote(91, alricKey) end)
    end
    RaidSim.Drain(ownSim, 5)
    RaidSim.As(ownLm, ownLm.KART.LC.Council.RefreshCouncilRows)
    T.eq(ownPanel.voteProgressText:GetText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 3, 3),
        "the setup: three picks about the item on the table read as three")

    -- Blizzard hands 91 to a DIFFERENT item. The picks above are still in LC.councilVotes -- that is
    -- the design, they are filtered on read rather than dropped -- and each carries the itemID it was
    -- made about, so every one of them must now be ignored.
    RaidSim.As(ownLm, function()
        ownLm.KART.LC.rollItems[91] = KARTTEST.items[F.WEAPON].link
        ownLm.KART.LC.Council.RefreshCouncilRows()
    end)
    T.eq(ownPanel.voteProgressText:GetText(), string.format(L.LC_COUNCIL_VOTES_PROGRESS, 0, 3),
        "B166: a pick made about the previous item under this number counts for nothing")

    -- ...and the same filter on the other consumer: the per-candidate tally on Alric's own row.
    local row
    for _, r in ipairs(ownPanel.rows or {}) do
        if r:IsShown() and r.memberKey == alricKey then row = r end
    end
    T.truthy(row, "Alric has a row")
    T.truthy(row and not row.councilVoteBtn.text:GetText():find("3", 1, true),
        "B166: and the candidate's own tally does not still show three either")
end
