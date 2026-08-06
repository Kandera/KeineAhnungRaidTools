-- The compact vote layout -- the other half of the window a raider votes in.
--
-- Two renderers share one window: Spacious draws a card per item, Compact draws a row. Every test in
-- the suite ran the spacious one, and coverage put the 163 lines of the compact renderer at zero:
-- a raider who ticks "compact vote layout" was on code no assertion had ever reached, including the
-- chips they click to answer with.
--
-- What matters here is not how it looks. It is that the same three things work: the answer lands,
-- the note goes with it, and switching layouts does not leave both drawn at once.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim, _, _, raider = F.NewRaid()
local LC = raider.KART.LC
local Vote = LC.Vote

local function Compact(on)
    raider.env.KART_Settings.lcVoteLayoutCompact = on
end

local function Refresh()
    RaidSim.As(raider, Vote.RefreshVoteListRows)
end

local function ShownRows(pool)
    local n = 0
    for _, row in ipairs(pool or {}) do if row:IsShown() then n = n + 1 end end
    return n
end

Compact(true)
F.Drop(sim, 90, F.GLOVES)
KARTTEST.AdvanceTime(1)
Refresh()

local f = LC.voteListFrame
T.truthy(f, "the vote window builds in compact mode")
T.truthy(f.compactRows and f.compactRows[1], "and draws a compact row for the item")

-- One layout at a time ------------------------------------------------------------------------------
-- Both pools live on the same frame and both are positioned from the top, so a spacious card left
-- shown behind a compact row is the shape of every "the vote window is drawn twice" report.
do
    T.eq(ShownRows(f.rows), 0, "with compact on, no spacious card is left showing")
    T.truthy(ShownRows(f.compactRows) > 0, "and the compact row is up")

    Compact(false)
    Refresh()
    T.eq(ShownRows(f.compactRows), 0, "switching back hides every compact row")
    T.truthy(ShownRows(f.rows) > 0, "and the spacious card takes over")

    Compact(true)
    Refresh()
    T.eq(ShownRows(f.rows), 0, "and switching again hides the spacious ones")
end

-- Voting from a chip ---------------------------------------------------------------------------------
do
    local row = f.compactRows[1]
    T.truthy(row.chipButtons and row.chipButtons[1], "the row offers a chip per vote button")
    local buttons = RaidSim.As(raider, LC.GetButtonConfig)
    T.eq(#row.chipButtons, #buttons, "one for each configured answer, and no more")

    T.truthy(row.chipArea:IsShown(), "the chips are offered while nothing is answered")
    T.truthy(not row.votedBadge:IsShown(), "and no answer badge is shown yet")

    RaidSim.As(raider, function() KARTTEST.Click(row.chipButtons[2]) end)
    T.eq(LC.votedByMe[90], 2, "clicking a chip casts that vote")

    Refresh()
    T.truthy(row.votedBadge:IsShown(), "the row then shows what was answered")
    T.truthy(not row.chipArea:IsShown(), "and stops offering the chips")
end

-- The note that travels with the vote ----------------------------------------------------------------
do
    F.Drop(sim, 91, F.WEAPON)
    KARTTEST.AdvanceTime(1)
    Refresh()
    local row
    for _, r in ipairs(f.compactRows) do
        if r:IsShown() and r.chipArea:IsShown() then row = r break end
    end
    T.truthy(row, "the new item has a row of its own with chips on it")

    RaidSim.As(raider, function()
        row.noteBox:SetText("brauche ich für den Set-Bonus")
        KARTTEST.Click(row.chipButtons[1])
    end)
    T.eq(LC.votedByMe[91], 1, "the vote lands")
    T.eq(LC.votedNoteByMe[91], "brauche ich für den Set-Bonus",
        "carrying the note typed into that row, not an empty one or another row's")
end

-- An answer given on the player's behalf -------------------------------------------------------------
-- LC.Relevance can answer for the raider (auto-pass, auto-transmog). The chips have to STAY on offer
-- in that case -- they are the only way to take back an answer nobody chose to give. The spacious
-- layout carries the same rule; the compact one had no test for it.
do
    F.Drop(sim, 92, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    RaidSim.As(raider, function() Vote.CastVote(92, 1, nil, true) end)
    Refresh()
    T.eq(LC.autoVotedByMe[92], true, "the answer was given automatically")

    -- Rows are positional: the row for this roll is the one at its index in the visible list.
    local autoRow
    for i, rollID in ipairs(RaidSim.As(raider, Vote.GetVisibleRolls)) do
        if rollID == 92 then autoRow = f.compactRows[i] end
    end
    T.truthy(autoRow, "the item is still on screen")
    T.truthy(autoRow.chipArea:IsShown(),
        "with its chips still offered, which is the only way to overrule an automatic answer")
    T.truthy(not autoRow.votedBadge:IsShown(),
        "and no answer badge claiming the raider decided it")
end

-- Rows are pooled, and a freed one must not come back carrying the old item ------------------------
do
    local before = ShownRows(f.compactRows)
    T.truthy(before > 1, "several items are on screen")

    -- The WHOLE raid, not this client alone. A raider that has forgotten a roll the rest of the raid
    -- is still holding gets it handed back -- that is the repair path working (the table heartbeat's,
    -- and since the receipt-ack also LC_ACK's), and it landed inside this block and drew a second row.
    -- What is under test here is the row pool, so the round ends everywhere and leaves nothing to
    -- repair.
    for _, c in ipairs(sim.clients) do
        RaidSim.As(c, function() c.KART.LC.ClearAllRolls() end)
    end
    Refresh()
    -- The WINDOW is what closes; the rows keep their own shown flag and go invisible with their
    -- parent, which is why this asks about the window and not about them.
    T.truthy(not f:IsShown(), "with nothing left to answer the window closes")

    -- What matters is the next batch: the pool is reused, and a row still holding the previous
    -- item's chips would let one click answer a roll that is no longer there.
    F.Drop(sim, 93, F.GLOVES)
    KARTTEST.AdvanceTime(1)
    Refresh()
    T.truthy(f:IsShown(), "a new item opens it again")
    T.eq(ShownRows(f.compactRows), 1, "showing exactly the one item, not the batch before it")
end
