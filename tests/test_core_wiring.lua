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
-- The other thing that moment is the last chance for: a boss's items are collected for half a second
-- before they are announced together, and a reload inside that window is the only way the raid never
-- hears about a boss at all (B134).
Wired("KART.LC.FlushPendingDrop()", "and the drop still waiting to be announced goes out with it")
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

-- The lootmaster losing Blizzard's roll (B60) -------------------------------------------------------
-- The whole feature is one event away from doing nothing at all, and nothing else would say so: the
-- handler is tested directly in tests/test_lc_lostroll.lua, so a wrong event name or a dropped
-- registration leaves every one of those assertions green while the lootmaster is never told in the
-- game. That is precisely the shape this file exists for.
-- Registered through pcall on purpose: RegisterEvent throws on a name the client does not know, and
-- this one comes from annotations a minor version behind the live client. Unprotected, a rename
-- aborts Core.lua at load and takes every core function in docs/MANIFEST.md with it, for the sake of
-- a warning that only prints. Asserted in that exact form so the protection cannot be dropped while
-- the registration stays.
Wired('pcall(frame.RegisterEvent, frame, "LOOT_HISTORY_UPDATE_DROP")',
    "the roll outcome event is registered, and registered safely")
Wired('elseif event == "LOOT_HISTORY_UPDATE_DROP" then', "and routed in the event handler")
Wired("KART.LC.HandleLootHistoryDrop(arg1, arg2)", "with both ids, which the lookup needs")

-- Asking again for the handshakes that never arrived (B120) -----------------------------------------
-- KART.RequestMissingHellos is tested directly in tests/test_sync.lua, and it is worth nothing at all
-- unless something calls it. The roster event is the only hook that fires all evening, which is the
-- point: the raid loses a handshake mid-evening, not only while forming.
Wired("KART.RequestMissingHellosThrottled()", "the missing handshakes are asked for again")

-- The guild ranks nobody asked for (B124) -----------------------------------------------------------
-- The data arrives asynchronously, long after the rows were drawn. Without the event the ranks appear
-- only on whatever refresh happens to come next, which on a panel nobody touches is never.
Wired('frame:RegisterEvent("GUILD_ROSTER_UPDATE")', "the guild roster event is registered")
Wired('elseif event == "GUILD_ROSTER_UPDATE" then', "and routed in the event handler")

do
    -- ...and the branch does something. Registered-and-routed is only two thirds of the wiring: an
    -- empty branch passes both assertions above while the ranks never appear. Scoped to the branch
    -- rather than searched for across the file, because the same call also stands in the KASC:OnPeer
    -- handler further down -- a plain search finds that one and reports a branch that is gutted as
    -- wired. Found by the mutation run over the comms rework (B116).
    local branch = code:match('elseif event == "GUILD_ROSTER_UPDATE" then\n(.-)\nelseif event ==')
    T.truthy(branch and branch:find("KART.LC.Council.RefreshCouncilRowsThrottled()", 1, true),
        "and that branch actually refreshes the council rows")
end

-- Identity resolution after an optional dependency loads (B126) --------------------------------------
-- NSRT's nickname API does not exist until NSRT has set itself up, and KART's retry pass is driven by
-- the roster event alone -- so a client that loaded first held plain text where everybody else held
-- keys, until some unrelated roster change happened to heal it.
do
    local addonLoaded = code:find('elseif event == "ADDON_LOADED" then', 1, true)
    T.truthy(addonLoaded, "another addon finishing its load is handled at all")
    Wired("KART.LC.RetryPendingResolutionsThrottled()", "and re-runs the pending identity resolutions")
end

-- The second half of B126, on the other event and without the throttle -------------------------------
-- PLAYER_ENTERING_WORLD's five-second timer is the other moment an on-demand dependency is finally
-- there, and it is the one that covers a client which loaded LAST -- no other addon finishes loading
-- after it, so the ADDON_LOADED path above never fires for them at all. A different call at a
-- different site: the assertion above is on the throttled variant and passes with this one deleted.
Wired("KART.LC.RetryPendingResolutions()", "the entering-world pass resolves what is still pending")

-- Surviving a stun (2026-08-05) ---------------------------------------------------------------------
-- Blizzard hides every UISpecialFrames entry on PLAYER_CONTROL_LOST, and every window in this addon
-- is one. tests/test_lc_chrome.lua drives the repair itself; without these two lines it never runs in
-- the game, and the windows keep vanishing on the first trash pull that stuns anybody.
Wired('frame:RegisterEvent("PLAYER_CONTROL_LOST")', "PLAYER_CONTROL_LOST is registered")
Wired('elseif event == "PLAYER_CONTROL_LOST" then', "and routed in the event handler")
Wired("KART.OnControlLost()", "which is what re-opens what Blizzard closed")

-- /kart ptr runs, on a client that answers and on one that refuses -----------------------------------
-- Its whole job is to work on the FIRST try on a game version nobody has tested against, typed by
-- somebody logged in alone on a PTR. A probe that raises while asking answers nothing -- so the case
-- it is built for, an API that errors, is the case it must survive.
do
    local F2 = dofile("tests/lc_fixture.lua")
    local sim = F2.NewRaid()
    local lm = sim.byName.Bramor

    local lines = 0
    local realPrint = _G.print
    _G.print = function() lines = lines + 1 end
    local ok = F2.RaidSim.As(lm, function() return pcall(lm.KART.PrintClientProbe) end)
    _G.print = realPrint
    T.truthy(ok, "the probe runs on a client that answers everything")
    T.truthy(lines > 4, "and prints a line per question rather than one summary")

    local realLeader, realAura = _G.UnitIsGroupLeader, _G.C_UnitAuras.GetAuraDataByIndex
    local realWpn = _G.GetWeaponEnchantInfo
    _G.UnitIsGroupLeader = function() error("secret") end
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("secret") end
    _G.GetWeaponEnchantInfo = nil
    realPrint = _G.print
    _G.print = function() end
    local ok2 = F2.RaidSim.As(lm, function() return pcall(lm.KART.PrintClientProbe) end)
    _G.print = realPrint
    _G.UnitIsGroupLeader, _G.C_UnitAuras.GetAuraDataByIndex = realLeader, realAura
    _G.GetWeaponEnchantInfo = realWpn

    T.truthy(ok2, "and survives a client that refuses every question it asks -- which is the point")
end

-- The party never converts itself, only a 6th player does (2026-08-12) -------------------------------
-- Converting the instant a party reaches 5 members catches groups that never wanted a 6th at all.
-- Core.lua itself needs the game to load, so this lifts the exact roster-event condition out of the
-- source and runs it standalone against a real 5-man fixture, the same way test_lc_relevance.lua
-- lifts DecideAutoResponse -- a plain substring check could not tell "does not convert" from "was
-- never reached at all".
do
    local snippet = code:match("if KART%.pendingBulkRaidConvert.-\nend\n")
    T.truthy(snippet, "the roster-event conversion check was found in Core.lua")
    snippet = snippet or "" -- so a missed extraction fails the assertion above, not the whole file

    local chunk = assert(loadstring("local KART = ...\nreturn function() " .. snippet .. " end"))
    local KART = {}
    local check = chunk(KART)

    local prevInCombat, prevActive = KARTTEST.inCombat, KARTTEST.activeUnit
    local prevRoster = KARTTEST.SnapshotRoster()
    KARTTEST.inCombat = false
    KARTTEST.activeUnit = nil
    KARTTEST.SetParty({
        { name = "Bramor" }, { name = "Corvin" }, { name = "Merrit" }, { name = "Sinja" },
        { name = "Kandera", leader = true },
    })

    KARTTEST.ClearInvites()
    KART.pendingBulkRaidConvert = false
    check()
    T.truthy(not KARTTEST.convertedToRaid,
        "a full 5-man party does not convert itself -- only a 6th invite request does that now")

    KARTTEST.ClearInvites()
    KART.pendingBulkRaidConvert = true
    check()
    T.truthy(KARTTEST.convertedToRaid,
        "a bulk WoWUtils invite that just filled the party still converts (regression guard)")

    KARTTEST.inCombat, KARTTEST.activeUnit = prevInCombat, prevActive
    KARTTEST.RestoreRoster(prevRoster)
end
