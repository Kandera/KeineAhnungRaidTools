local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = { L = {} }
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("CoTank.lua", "r")):read("*a"), "@CoTank.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
    for _, name in ipairs({ "PickCoTank", "ShouldShow" }) do
        if KART.CT[name] then setfenv(KART.CT[name], env) end
    end
end

local function RaidTwoTanks()
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
        { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB", role = "TANK", class = "PALADIN", classFile = "PALADIN" },
    })
    KARTTEST.activeUnit = "raid1"
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = { testMode = false },
    }
    KARTTEST.instance = { name = "Somewhere", instanceType = "party", difficultyID = 1, difficultyName = "Normal" }
end

do
    RaidTwoTanks()
    T.eq(KART.CT.PickCoTank(), "raid2", "first other tank is raid2 when player is raid1")
end

do
    RaidTwoTanks()
    T.eq(KART.CT.ShouldShow(), true, "tank in a dungeon with a co-tank shows")
end

do
    RaidTwoTanks()
    env.KART_Settings.ctModuleEnabled = false
    T.eq(KART.CT.ShouldShow(), false, "module off hides even in a dungeon")
end

do
    RaidTwoTanks()
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "DAMAGER", class = "MAGE", classFile = "MAGE" },
        { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB", role = "TANK", class = "PALADIN", classFile = "PALADIN" },
    })
    KARTTEST.activeUnit = "raid1"
    T.eq(KART.CT.ShouldShow(), false, "non-tank player hides")
    T.eq(KART.CT.PickCoTank(), "raid2", "but the co-tank token is still the other tank")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "none"
    T.eq(KART.CT.ShouldShow(), false, "open world hides")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "arena"
    T.eq(KART.CT.ShouldShow(), false, "arena hides")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "pvp"
    T.eq(KART.CT.ShouldShow(), false, "battleground hides")
end

do
    RaidTwoTanks()
    env.KART_Settings.ctModuleEnabled = false
    env.KART_Settings.ct.testMode = true
    T.eq(KART.CT.ShouldShow(), false, "test mode does not override a disabled module")
end

do
    RaidTwoTanks()
    env.KART_Settings.ct.testMode = true
    KARTTEST.instance.instanceType = "none"
    T.eq(KART.CT.ShouldShow(), true, "test mode shows in town when the module is on")
end

do
    RaidTwoTanks()
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
    })
    KARTTEST.activeUnit = "raid1"
    T.is_nil(KART.CT.PickCoTank(), "alone there is no co-tank")
    T.eq(KART.CT.ShouldShow(), false, "and the row stays hidden")
end

do
    local src = assert(io.open("CoTank.lua", "r")):read("*a")
    T.truthy(not src:find("RCLootCouncil", 1, true), "CoTank.lua does not name RCLootCouncil")
    T.truthy(not src:find("KART.RC", 1, true), "CoTank.lua does not name KART.RC")
    T.truthy(not src:find("GetAuraDataByIndex", 1, true), "CoTank.lua does not index-scan auras")
end

do
    local utils = assert(io.open("Utils.lua", "r")):read("*a")
    T.truthy(utils:find("ctModuleEnabled = false", 1, true), "default module off")
    T.truthy(utils:find("schemaVersion = 1", 1, true), "ct blob has schemaVersion")
end
