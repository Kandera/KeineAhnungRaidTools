-- In-process RCLootCouncil double for the companion tests. Not the game.
local transmitCouncil = {}

function KARTTEST.InstallRC()
    KARTTEST.rcLoaded = true
    KARTTEST.rcCouncilSent = 0
    KARTTEST.rcCouncilSentList = nil
    KARTTEST.rcCouncilUpdated = false
    KARTTEST.rcAwards = {}
    transmitCouncil = {}
    _G.RCLootCouncil = {
        db = { profile = { council = {} } },
        isMasterLooter = false,
        isCouncil = false,
        masterLooter = "Lead-TarrenMill",
        player = { name = "Lead-TarrenMill" },
        GetML = function() return "Lead-TarrenMill" end,
        NewMLCheck = function() end,
        OnCouncilReceived = function() end,
        GetLootTable = function()
            return KARTTEST.rcLootTable or {}
        end,
        TradeUI = {
            OnAwardReceived = function() end,
            OnEvent_TRADE_ACCEPT_UPDATE = function() end,
            OnEvent_UI_INFO_MESSAGE = function() end,
        },
    }
    _G.RCLootCouncilML = {
        UpdateGroupCouncil = function()
            transmitCouncil = {}
            local council = RCLootCouncil.db.profile.council
            for i, g in ipairs(council) do
                transmitCouncil[i] = g
            end
            KARTTEST.rcCouncilUpdated = true
        end,
        SendCouncil = function()
            if not KARTTEST.rcCouncilUpdated then
                error("SendCouncil before UpdateGroupCouncil")
            end
            KARTTEST.rcCouncilSentList = {}
            for i, g in ipairs(transmitCouncil) do
                KARTTEST.rcCouncilSentList[i] = g
            end
            KARTTEST.rcCouncilSent = KARTTEST.rcCouncilSent + 1
            KARTTEST.rcCouncilUpdated = false
        end,
        Award = function(_, session, winner, response, ...)
            local extra = { ... }
            KARTTEST.rcAwards[#KARTTEST.rcAwards + 1] =
                { session = session, winner = winner, response = response, extra = extra }
            return true
        end,
    }
end

function KARTTEST.RemoveRC()
    KARTTEST.rcLoaded = false
    transmitCouncil = {}
    _G.RCLootCouncil = nil
    _G.RCLootCouncilML = nil
end
