-- Core.lua's event and slash wiring, checked against the source.
--
-- The harness does not load Core.lua -- it needs the game to exist at all -- so raidsim calls the
-- handlers directly and every line of routing in that file is invisible to the suite. That is not a
-- theoretical gap: the tracked-roll snapshot (B81) is driven entirely by two Core.lua branches, and
-- a rename or a dropped RegisterEvent would leave the whole feature dead in the game while 1500
-- assertions stayed green.
--
-- Reading the source is the same tool tests/test_withheld.lua used for the same reason, and it is
-- deliberately literal: it asserts the exact call as written, so moving one is a decision somebody
-- has to make here too, rather than something that happens silently.

local core = assert(io.open("Core.lua", "r")):read("*a")

-- Commented-out lines do not count. A plain substring search passes for `-- frame:RegisterEvent(...)`
-- just as happily as for the real thing, which a mutation demonstrated: severing the registration
-- outright left every assertion below green.
local codeLines = {}
for line in (core .. "\n"):gmatch("([^\n]*)\n") do
    local stripped = line:match("^%s*(.-)%s*$")
    if stripped ~= "" and stripped:sub(1, 2) ~= "--" then
        codeLines[#codeLines + 1] = stripped
    end
end
local code = table.concat(codeLines, "\n")

local function Wired(needle, label)
    T.truthy(code:find(needle, 1, true), label)
end

-- The tracked rolls across a reload (B81) ----------------------------------------------------------
-- PLAYER_LOGOUT is the last thing that runs before SavedVariables are written, and it fires for a
-- /reload, a logout and a quit alike. Without the registration the snapshot is never taken, and
-- without the call it is never read back -- and either way the items on the table are gone again.
Wired('frame:RegisterEvent("PLAYER_LOGOUT")', "PLAYER_LOGOUT is registered")
Wired('elseif event == "PLAYER_LOGOUT" then', "and routed in the event handler")
Wired("KART.LC.SaveSessionSnapshot()", "the snapshot is taken there")
Wired("KART.LC.RestoreSessionSnapshot()", "and read back on ADDON_LOADED")

do
    -- Order matters between the two restores: both bring loot-flow state back, and
    -- Trade.RestorePersistedTrades rebuilds LC.assignedWinners from the loot history (B77) while the
    -- snapshot carries this client's own live copy. The snapshot is the more direct answer and must
    -- be able to write over it, which it can only do by running second.
    local trades = code:find("KART.LC.Trade.RestorePersistedTrades()", 1, true)
    local rolls  = code:find("KART.LC.RestoreSessionSnapshot()", 1, true)
    T.truthy(trades and rolls and trades < rolls,
        "the trade obligations are restored before the tracked rolls")
end

-- Applying settings to the widgets ------------------------------------------------------------------
-- KART.SyncSettingsToUI is what every settings-wide change ends by calling -- loading a profile,
-- resetting to defaults, ADDON_LOADED itself. The profile button's label is part of that, and
-- tests/test_mainframe.lua stands in for this line when it asserts a loaded profile is named on the
-- button. Drop it and the button keeps saying whatever it said before, in the game and nowhere else.
Wired("KART.RefreshProfileButton()", "the profile button is relabelled when settings are applied")

-- The three commands that bring a window back (B51, B86) -------------------------------------------
-- Each of these used to call :Show() on a frame, which puts back whatever the row pool last drew --
-- and all three windows only HIDE on their "x", so that picture can be arbitrarily old. They go
-- through a rebuild now, and the rebuild is in LootCouncil.lua precisely so the suite can reach it.
Wired("KART.LC.ReopenTrackedWindow()", "/kart lc goes through the rebuild")
Wired("KART.LC.ReopenTradeReminder()", "/kart trade goes through the rebuild")
Wired("KART.LC.ReopenOwedReminder()", "/kart owed goes through the rebuild")

do
    -- ...and none of them still reaches for the frame directly. A leftover :Show() next to the new
    -- call would pass every assertion above while doing exactly what they were written to stop.
    for _, frame in ipairs({ "councilPanel", "voteListFrame", "tradeReminderFrame", "owedReminderFrame" }) do
        T.truthy(not code:find("KART.LC." .. frame .. ":Show()", 1, true),
            "no command shows " .. frame .. " without rebuilding it first")
    end
end
