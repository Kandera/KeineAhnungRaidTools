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
