-- The export cut. WoWUtils does not dedup on import, so importing one raid and then the next lands
-- the first raid's drops twice. The cut is per award and keyed on the stable id, NOT on a timestamp:
-- the catch-up sync backfills entries OLDER than everything already stored, and a timestamp cut would
-- drop every one of those through the gap and never export them at all.
--
-- Three states, and the difference is load-bearing:
--   exported == false  -> new, has not been exported
--   exported == true   -> exported
--   exported == nil    -> written by a build before this one; counts as exported
--
-- Writing the rule as `not e.exported` would collapse nil into new and invert the migration, so the
-- checks below are written against the exact values rather than against truthiness.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local sim = F.NewRaid()
local me = sim.byName.Bramor
local KART = me.KART
local LH = KART.LH

local function As(fn, ...) return RaidSim.As(me, fn, ...) end
local GLOVES = KARTTEST.items[F.GLOVES].link

-- A newly logged award is new, not exported -------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {}
        LH.LogHistory(GLOVES, "Alric", "BIS", "MAGE", nil, 90, "Player-1-A", "id-1", 1)
    end)
    local e = me.env.KART_LootHistory[1]
    T.eq(e.exported, false, "a freshly logged award is stamped exported = false, not left nil")
end

-- The mark is personal and must not travel. One player's export bookkeeping says nothing about
-- anybody else's, and an entry arriving through the catch-up is new to whoever receives it.
--
-- Two claims, kept apart on purpose. This used to be one assertion reading `== nil` under a label
-- about the wire -- but nil is the LEGACY state, "written before the cut existed, counts as already
-- exported", so it asserted that every caught-up award is born silently exported and pinned exactly
-- that defect in place. What the wire must not carry and what the receiver must store are different
-- claims and each gets its own line.
do
    local sim2, lm, _, raider = F.NewRaid()
    RaidSim.As(lm, function()
        lm.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 91, id = "wire-1", epoch = 1,
              exported = true },
        }
    end)
    RaidSim.As(raider, function() raider.env.KART_LootHistory = {} end)
    RaidSim.As(raider, function() raider.KART.LH.RequestHistorySync() end)
    KARTTEST.AdvanceTime(15)
    RaidSim.Drain(sim2, 30)

    T.eq(#raider.env.KART_LootHistory, 1, "the award reaches the peer")
    T.eq(raider.env.KART_LootHistory[1].exported, false,
        "and it is NEW to whoever receives it -- stamped false, never left nil, which would read as legacy")
    T.eq(raider.env.KART_LootHistory[1].exported == lm.env.KART_LootHistory[1].exported, false,
        "while the sender's own mark did not ride along: the two clients disagree, which is the point")

    -- The claim the design records as covered and nothing checked: a caught-up award has to be
    -- REACHABLE, which means on the New side and counted on the label the player actually reads.
    -- Without this, an award born already-exported is invisible in every direction.
    T.eq(#RaidSim.As(raider, raider.KART.LH.UnexportedEntries), 1,
        "the caught-up award is on the New side")
    RaidSim.As(raider, function() raider.KART.LH.ShowExportDialog() end)
    T.eq(raider.KART.LH.exportDialog.btnNew.text:GetText(),
        string.format(raider.KART.L.LH_EXPORT_TAB_NEW, 1),
        "and the dialog says New (1) -- not the New (0) that means everything is exported")
end

-- A reassignment received over the wire is a new entry too ----------------------------------------
--
-- The council changes its mind, the correction arrives, and the prior entry is removed and replaced.
-- That prior entry may well have carried exported = true, and the replacement must not inherit it:
-- the corrected winner is what WoWUtils has to be told, and an entry born marked never gets there.
do
    local _, lm5, _, raider5 = F.NewRaid()
    local now = time()
    RaidSim.As(lm5, function()
        lm5.env.KART_LootHistory = {
            { winner = "Alric", winnerKey = "Player-1-A", item = GLOVES, reason = "BIS",
              time = now, rollID = 70, class = "MAGE", id = "re-1", epoch = 1, exported = true },
        }
    end)
    -- One record, worded exactly as the catch-up sync words it (see EntryRecord / HandleHistoryBatch).
    local record = ("%d:16:%d:MAGE:1,1,1:%s:%s:%s:%s:%d:%s"):format(
        now + 1, 70, "Player-1-S", "Sinja", "BIS", "re-2", 1, GLOVES)
    RaidSim.As(raider5, function()
        raider5.KASC:Send(("LC_HIST_BATCH:1:%s:0:%s"):format(raider5.guid, record), "WHISPER", lm5.name)
    end)
    KARTTEST.AdvanceTime(1)

    T.eq(#lm5.env.KART_LootHistory, 1, "the roll still holds exactly one award")
    T.eq(lm5.env.KART_LootHistory[1].winner, "Sinja", "and it names the raider it was reassigned to")
    T.eq(lm5.env.KART_LootHistory[1].exported, false,
        "which is waiting to be exported -- the replaced entry's mark does not carry to another winner")
end

-- C8, "a reload changes nothing". The mark lives on the entry and the history is a SavedVariable, so
-- this should hold by construction -- which is exactly why it is worth pinning, since nothing else
-- would notice if the entry were ever rebuilt on load instead of restored.
do
    local sim3, _, _, raider = F.NewRaid()
    RaidSim.As(raider, function()
        raider.env.KART_LootHistory = {
            { time = time() - 60, item = GLOVES, winner = "Alric", winnerKey = "Player-1-A",
              reason = "BIS", class = "MAGE", rollID = 92, id = "reload-1", epoch = 1,
              exported = true },
        }
    end)
    raider = RaidSim.Reload(sim3, raider.name)
    T.eq(raider.env.KART_LootHistory[1].exported, true, "the export mark survives a reload")
end

-- The cut ignores the window filters; "everything" keeps respecting them.
--
-- This is the one rule worth stating twice, because the alternative fails silently. Filter to one
-- player, press the cut, and a filter-respecting cut marks only that player's awards -- the rest of
-- the same evening stays unmarked and comes round again next time, while the player believes the
-- night is done. "Everything" is a VIEW and may follow the filters; the cut is BOOKKEEPING and must
-- not depend on how a filter happens to be set.
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000003, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-1", epoch = 1, exported = false },
            { time = 1785000002, item = GLOVES, winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", id = "cut-2", epoch = 1, exported = false },
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-3", epoch = 1, exported = true },
            { time = 1785000000, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "cut-4", epoch = 1 },   -- legacy: no field at all
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
    end)

    T.eq(#As(LH.UnexportedEntries), 2, "only the two entries at exported == false count as new")
    T.eq(#As(LH.FilteredEntries), 4, "everything shows all four")

    -- Now filter to one player and ask again.
    As(function() LH.filters.playerIds = { ["K-A"] = true } end)
    T.eq(#As(LH.UnexportedEntries), 2,
        "the cut still covers both players' new awards while a player filter is active")
    T.eq(#As(LH.FilteredEntries), 3, "everything follows the filter, as it always has")
    As(function() LH.filters.playerIds = nil end)
end

-- A legacy entry counts as exported, an explicit false does not -----------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mig-1", epoch = 1 },                   -- no field
            { time = 1785000000, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mig-2", epoch = 1, exported = false },
        }
    end)
    local new = As(LH.UnexportedEntries)
    T.eq(#new, 1, "an entry written before this version counts as already exported")
    T.eq(new[1].id, "mig-2", "and the one that is genuinely new is the one with exported == false")
end

-- Marking sets the mark and says so ----------------------------------------------------------------
do
    local lines = {}
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = GLOVES, winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "mark-1", epoch = 1, exported = false },
            { time = 1785000000, item = GLOVES, winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", id = "mark-2", epoch = 1, exported = false },
        }
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.MarkExported(LH.UnexportedEntries())
        me.env.print = realPrint
    end)

    T.eq(me.env.KART_LootHistory[1].exported, true, "the first award is marked")
    T.eq(me.env.KART_LootHistory[2].exported, true, "and so is the second")
    T.eq(#As(LH.UnexportedEntries), 0, "nothing is left new afterwards")
    T.eq(#lines, 1, "marking prints exactly one line")
    T.truthy(lines[1]:find("2", 1, true), "and the line names how many were marked")
end

-- The JSON is byte-identical to what it was ---------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1786090821, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "json-1", epoch = 3, exported = false },
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
    end)
    local json = As(LH.BuildRCLootCouncilJSON)

    T.eq(json:find("exported", 1, true), nil, "the mark does not leak into the export")
    T.eq(json:find("epoch", 1, true), nil, "and neither does the epoch")
    T.truthy(json:find('"player":"Alric"', 1, true), "the export still says what it always said")
end

-- Passing an explicit list overrides the filters ------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "pick-1", epoch = 1, exported = false },
            { time = 1785000000, item = "item:1234", winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", class = "MAGE", id = "pick-2", epoch = 1, exported = true },
        }
        LH.filters = { player = nil, playerIds = { ["K-S"] = true }, reason = nil, search = "" }
    end)
    local json = As(function() return LH.BuildRCLootCouncilJSON(LH.UnexportedEntries()) end)

    T.truthy(json:find('"player":"Alric"', 1, true),
        "an explicit list is exported whole, regardless of the window filter")
    T.eq(json:find('"player":"Sinja"', 1, true), nil, "and nothing outside that list appears")
    As(function() LH.filters.playerIds = nil end)
end

-- The dialog. It opens on New, because that is the answer to the question the player came with.
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000002, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "dlg-1", epoch = 1, exported = false },
            { time = 1785000001, item = "item:1234", winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", class = "MAGE", id = "dlg-2", epoch = 1, exported = true },
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
        LH.ShowExportDialog()
    end)
    local f = LH.exportDialog

    T.eq(f.mode, "new", "the dialog opens on the New side")
    T.truthy(f.editBox.text:find('"player":"Alric"', 1, true), "showing the award still to export")
    T.eq(f.editBox.text:find('"player":"Sinja"', 1, true), nil, "and not the one already exported")
    T.truthy(f.btnMark:IsShown(), "the mark button is there on New")
    T.truthy(f.btnMark:IsEnabled(), "and it is usable, because there is one to mark")

    -- Read off the LABELS, not off the queries behind them. The two counts are the whole of C14 here
    -- -- they are the only place a player can see whether anything is quietly stuck -- so the claim
    -- that has to hold is what the row SAYS, and every one of the three numbers is asserted.
    T.eq(f.btnNew.text:GetText(), string.format(KART.L.LH_EXPORT_TAB_NEW, 1),
        "the New label counts the awards still to export, and nothing else")
    T.eq(f.btnAll.text:GetText(), string.format(KART.L.LH_EXPORT_TAB_ALL, 2),
        "the All label counts everything the window shows")
    T.eq(f.btnMark.text:GetText(), string.format(KART.L.LH_EXPORT_MARK, 1),
        "and the button carries its own count, so it cannot be read as 'mark everything'")
end

-- Switching to All shows everything and takes the mark button away ----------------------------------
do
    As(function() LH.SetExportMode("all") end)
    local f = LH.exportDialog

    T.eq(f.mode, "all", "the mode follows the switch")
    T.truthy(f.editBox.text:find('"player":"Sinja"', 1, true), "All shows the exported award too")
    T.eq(not f.btnMark:IsShown(), true,
        "and the mark button is gone -- All follows the window filters, so marking from there would " ..
        "cover only the filtered slice")

    -- Out of REACH, not merely out of sight. Hidden is the whole mechanism keeping the cut off the
    -- All side, so the harness has to refuse a hidden button the way the game does -- otherwise this
    -- rule is enforced by nothing a test can see.
    As(function()
        local realPrint = me.env.print
        me.env.print = function() end
        f.btnMark:Click()
        me.env.print = realPrint
    end)
    T.eq(me.env.KART_LootHistory[1].exported, false,
        "and a click where it used to sit marks nothing at all")
end

-- Nothing new: the button stays visible but cannot be pressed ---------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000000, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "dlg-3", epoch = 1, exported = true },
        }
        LH.ShowExportDialog()
    end)
    local f = LH.exportDialog

    T.eq(f.mode, "new", "the dialog opens on New again")
    T.eq(not f.btnMark:IsEnabled(), true, "with nothing to mark, the button is disabled")
    T.truthy(f.btnMark:IsShown(), "but still visible -- a button that vanishes reads as one you missed")
end

-- Opening the dialog marks nothing ------------------------------------------------------------------
do
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000000, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "dlg-4", epoch = 1, exported = false },
        }
        LH.ShowExportDialog()
        LH.exportDialog:Hide()
    end)
    T.eq(me.env.KART_LootHistory[1].exported, false,
        "opening and closing the dialog leaves the award unexported -- the addon cannot know it was copied")
end

-- Pressing the button marks what is shown and empties the New side ----------------------------------
do
    local lines = {}
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000000, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "dlg-5", epoch = 1, exported = false },
        }
        LH.ShowExportDialog()
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.exportDialog.btnMark:Click()
        me.env.print = realPrint
    end)
    local f = LH.exportDialog

    T.eq(me.env.KART_LootHistory[1].exported, true, "the award is marked")
    T.eq(f.editBox.text, "[]", "the New side is empty afterwards")
    T.eq(not f.btnMark:IsEnabled(), true, "and the button has nothing left to do")
    T.truthy(lines[1]:find("|cffff0000KART:|r ", 1, true),
        "and the line is attributed to KART, like every other spontaneous line this module writes -- " ..
        "an unattributed one is the one the player cannot find again in a raid-night log")
end

-- An award logged while the dialog sits open is not marked by that press ----------------------------
--
-- LH.Refresh does not reach the export dialog, so an award logged after it opened is in neither the
-- JSON on screen nor the count on the button. Marking it anyway would record as exported something
-- that was never in the text the player copied -- the exact silent loss this whole cut exists to
-- prevent, arriving from inside. What is marked has to be what was RENDERED.
do
    local lines = {}
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000000, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "late-1", epoch = 1, exported = false },
        }
        LH.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
        LH.ShowExportDialog()
    end)
    local rendered = LH.exportDialog.editBox.text

    As(function()
        LH.LogHistory(GLOVES, "Sinja", "Upgrade", "PRIEST", nil, 93, "K-S", "late-2", 1)
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.exportDialog.btnMark:Click()
        me.env.print = realPrint
    end)

    T.eq(rendered:find('"player":"Sinja"', 1, true), nil,
        "the award logged after the dialog opened was never in the text on screen")
    local late
    for _, e in ipairs(me.env.KART_LootHistory) do if e.id == "late-2" then late = e end end
    T.eq(late.exported, false,
        "so the press leaves it unexported -- a press marks what it copied, not what has arrived since")
    T.eq(lines[1], "|cffff0000KART:|r " .. string.format(KART.L.LH_EXPORT_MARKED, 1),
        "and the chat line records the one that WAS copied, matching the count on the button pressed")
    T.eq(#As(LH.UnexportedEntries), 1, "the late award is still waiting on the New side")
end

-- A legacy entry is not "one more marked" ------------------------------------------------------------
--
-- It counts as already exported, it is not on the New side and it is not in the button's count -- so
-- counting it into the chat line would make the record disagree with the label that was pressed, and
-- the chat line is the only lasting evidence the press happened at all.
do
    local lines = {}
    As(function()
        me.env.KART_LootHistory = {
            { time = 1785000001, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", id = "leg-1", epoch = 1 },                       -- legacy: no field
            { time = 1785000000, item = "item:1234", winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", id = "leg-2", epoch = 1, exported = false },
        }
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.MarkExported(me.env.KART_LootHistory)   -- the whole history, legacy entry and all
        me.env.print = realPrint
    end)

    T.eq(me.env.KART_LootHistory[1].exported, nil, "the legacy entry is left exactly as it was")
    T.eq(me.env.KART_LootHistory[2].exported, true, "the one that was genuinely new is marked")
    T.eq(lines[1], "|cffff0000KART:|r " .. string.format(KART.L.LH_EXPORT_MARKED, 1),
        "and the line says ONE, the same number the New side and the button label were showing")
end

-- A press that finds nothing left still says so ------------------------------------------------------
--
-- Nothing is lost when the answer is zero, but "the chat line is the record" has to hold for every
-- press, including that one. A press with no line is the single case where the player is left with
-- "I think I pressed it", which is the state this line exists to abolish.
do
    local lines = {}
    As(function()
        local realPrint = me.env.print
        me.env.print = function(s) lines[#lines + 1] = tostring(s) end
        LH.MarkExported({})
        me.env.print = realPrint
    end)
    T.eq(#lines, 1, "the press is still recorded")
    T.eq(lines[1], "|cffff0000KART:|r " .. string.format(KART.L.LH_EXPORT_MARKED, 0),
        "as the zero it was")
end

-- After a raid-wide wipe both counts read zero -------------------------------------------------------
--
-- Driven through LH.ClearHistory, the real wipe, rather than by assigning an empty table: the epoch
-- bump and the wipe are the thing under test, and a hand-emptied table would run neither. Read off
-- the labels for the same reason as above -- "New (0) · All (0) means the log was cleared, New (0) ·
-- All (487) means everything is exported" is a claim about what the row SAYS.
do
    local _, lm4 = F.NewRaid()
    local LH4 = lm4.KART.LH
    RaidSim.As(lm4, function()
        lm4.env.KART_LootHistory = {
            { time = 1785000001, item = "item:1234", winner = "Alric", winnerKey = "K-A",
              reason = "BIS", class = "MAGE", id = "wipe-1", epoch = 1, exported = false },
            { time = 1785000000, item = "item:1234", winner = "Sinja", winnerKey = "K-S",
              reason = "Upgrade", class = "MAGE", id = "wipe-2", epoch = 1, exported = true },
        }
        LH4.filters = { player = nil, playerIds = nil, reason = nil, search = "" }
        LH4.ShowExportDialog()
    end)
    local f = LH4.exportDialog

    T.eq(f.btnNew.text:GetText(), string.format(lm4.KART.L.LH_EXPORT_TAB_NEW, 1),
        "before the wipe the New label counts the one award still to export")
    T.eq(f.btnAll.text:GetText(), string.format(lm4.KART.L.LH_EXPORT_TAB_ALL, 2),
        "and the All label counts both")

    RaidSim.As(lm4, function()
        LH4.ClearHistory()
        LH4.RefreshExportDialog()
    end)

    T.eq(#lm4.env.KART_LootHistory, 0, "the wipe really emptied the log")
    T.eq(f.btnNew.text:GetText(), string.format(lm4.KART.L.LH_EXPORT_TAB_NEW, 0),
        "New reads zero afterwards")
    T.eq(f.btnAll.text:GetText(), string.format(lm4.KART.L.LH_EXPORT_TAB_ALL, 0),
        "and so does All -- together the two numbers say the log was cleared, not that all is exported")
end
