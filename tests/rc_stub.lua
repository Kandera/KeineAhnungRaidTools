-- In-process RCLootCouncil double for the companion tests. Not the game.
function KARTTEST.InstallRC()
    KARTTEST.rcLoaded = true
    KARTTEST.rcCouncilSent = 0
    KARTTEST.rcAwards = {}
    _G.RCLootCouncil = {
        db = { profile = { council = {} } },
        isMasterLooter = false,
        isCouncil = false,
        masterLooter = "Lead-TarrenMill",
        player = { name = "Lead-TarrenMill" },
        GetML = function() return "Lead-TarrenMill" end,
    }
    _G.RCLootCouncilML = {
        SendCouncil = function()
            KARTTEST.rcCouncilSent = KARTTEST.rcCouncilSent + 1
        end,
        UpdateGroupCouncil = function() end,
        Award = function(_, session, winner, response)
            KARTTEST.rcAwards[#KARTTEST.rcAwards + 1] =
                { session = session, winner = winner, response = response }
            return true
        end,
    }
end

function KARTTEST.RemoveRC()
    KARTTEST.rcLoaded = false
    _G.RCLootCouncil = nil
    _G.RCLootCouncilML = nil
end
