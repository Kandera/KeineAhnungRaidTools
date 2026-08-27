-- Core.lua's event and slash wiring, checked against the source.

--

-- The harness does not load Core.lua -- it needs the game to exist at all -- so raidsim calls the

-- handlers directly and every line of routing in that file is invisible to the suite.



local core = assert(io.open("Core.lua", "r")):read("*a")

local toc = assert(io.open("KeineAhnungRaidTools.toc", "r")):read("*a")



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



T.truthy(not toc:find("LootCouncil%.lua", 1, true), "toc does not list LootCouncil.lua")

T.truthy(not code:find("KART%.LC", 1, true), "Core.lua does not reference KART.LC")

T.truthy(not code:find("KART%.LH", 1, true), "Core.lua does not reference KART.LH")

T.truthy(not code:find('RegisterCapability("KART", "LC"', 1, true),

    "Core.lua does not register the LC comm capability")

T.truthy(not code:find('frame:RegisterEvent("START_LOOT_ROLL")', 1, true),

    "START_LOOT_ROLL is not registered")

T.truthy(not code:find('frame:RegisterEvent("TRADE_SHOW")', 1, true),

    "TRADE_SHOW is not registered")

local owedSrc = assert(io.open("RCOwed.lua", "r")):read("*a")
T.truthy(not owedSrc:find('RegisterEvent("TRADE_ACCEPT_UPDATE")', 1, true),
    "owed reminder does not register TRADE_ACCEPT_UPDATE (RC already does)")
T.truthy(not owedSrc:find("OnEvent_TRADE_ACCEPT_UPDATE", 1, true),
    "owed reminder does not hook RC TRADE_ACCEPT_UPDATE (GetTradeTargetItemLink during accept sticks the trade)")
T.truthy(not owedSrc:find('RegisterEvent("UI_INFO_MESSAGE")', 1, true),
    "owed reminder does not register UI_INFO_MESSAGE (RC already does)")



Wired("KART.RefreshProfileButton()", "the profile button is relabelled when settings are applied")



Wired("KART.RequestMissingHellosThrottled()", "the missing handshakes are asked for again")



Wired("KART.RC.OnRosterUpdate()", "RC council is pushed on roster change")

Wired("KART.RC.Enable()", "RC companion Enable is wired from Core.lua")
Wired("KART.RC.OnOwedOutOfCombat()", "owed reminder reappears after combat")
Wired("KART.RC.OpenOwedWindow()", "/kart owed opens the winner reminder")

T.truthy(toc:find("CoTank%.lua"), "toc lists CoTank.lua")
T.truthy(toc:find("CoTankSettings%.lua"), "toc lists CoTankSettings.lua")

Wired('frame:RegisterEvent("CHAT_MSG_OFFICER")', "CHAT_MSG_OFFICER is registered for invite keywords")
Wired("channels.OFFICER", "officer chat is gated by inviteChannels")



do

    local branch = code:match('elseif event == "GROUP_ROSTER_UPDATE" then\n(.-)\nelseif event ==')

    T.truthy(branch and branch:find("KART.RC.OnRosterUpdate()", 1, true),

        "the roster branch calls RC.OnRosterUpdate")

    T.truthy(branch and branch:find("KART.CT.Refresh", 1, true),

        "the roster branch calls CT.Refresh")

end



do

    local branch = code:match('elseif event == "ADDON_LOADED" then\n(.-)\nelseif event ==')

    T.truthy(branch and branch:find('arg1 == "RCLootCouncil"', 1, true)

        and branch:find("KART.RC.Enable()", 1, true),

        "RCLootCouncil ADDON_LOADED re-enables the RC companion")

    T.truthy(branch and branch:find("KART.RegisterNeighborAddons()", 1, true),

        "late-loaded neighbors re-register on the hello")

end



Wired('frame:RegisterEvent("PLAYER_CONTROL_LOST")', "PLAYER_CONTROL_LOST is registered")

Wired('elseif event == "PLAYER_CONTROL_LOST" then', "and routed in the event handler")

Wired("KART.OnControlLost()", "which is what re-opens what Blizzard closed")

Wired("KART.MainFrame:SetScale", "window scale is applied to the main frame")
Wired("KART.CtFlyout:SetScale", "and to the Co-Tank flyout")

Wired('elseif event == "PLAYER_REGEN_DISABLED" then', "PLAYER_REGEN_DISABLED is routed")

Wired("KART.SetEditModeActive(false)", "combat leaves edit mode")
Wired("KART.RefreshEditModeChrome()", "regen restores edit-mode chrome")
do
    local branch = code:match('elseif event == "PLAYER_REGEN_ENABLED" then\n(.-)\nelseif event ==')
    T.truthy(branch and branch:find("KART.HandleAutoPromote()", 1, true),
        "regen retries auto-promote skipped during combat")
end



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



do

    local snippet = code:match("if KART%.pendingBulkRaidConvert.-\nend\n")

    T.truthy(snippet, "the roster-event conversion check was found in Core.lua")

    snippet = snippet or ""



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

