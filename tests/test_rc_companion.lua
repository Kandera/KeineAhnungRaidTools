dofile("tests/rc_stub.lua")

local env = setmetatable({}, { __index = _G })
local KART = {}
env.KART = KART
_G.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("RCCompanion.lua", "r")):read("*a"), "@RCCompanion.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
local RC = KART.RC

KARTTEST.RemoveRC()
T.eq(KART.RC.IsRCLoaded(), false, "no RC addon means the companion is inert")

KARTTEST.InstallRC()
T.eq(KART.RC.IsRCLoaded(), true, "RC double counts as loaded")

-- Nick list -> RC council GUIDs ---------------------------------------------------------
local prevActive = KARTTEST.activeUnit
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", nickname = "Lead", leader = true },
    { name = "Bob",  guid = "Player-1-BBBB", nickname = "Bobby" },
})
KARTTEST.activeUnit = "raid1"
_G.KART_Settings = _G.KART_Settings or {}
KART_Settings.rcCouncilMembers = "Bobby, Ghost"

RC.PushCouncilToRC()
T.deep_eq(RCLootCouncil.db.profile.council, { "Player-1-BBBB" },
    "only nicks whose current alt is in the raid are pushed")
T.eq(KARTTEST.rcCouncilSent, 1, "lead sends RC council after a push")

-- Non-lead must not write.
RCLootCouncil.db.profile.council = { "keep-me" }
KARTTEST.rcCouncilSent = 0
KARTTEST.activeUnit = "raid2"
RC.PushCouncilToRC()
T.deep_eq(RCLootCouncil.db.profile.council, { "keep-me" }, "non-lead does not write RC council")
T.eq(KARTTEST.rcCouncilSent, 0, "non-lead does not SendCouncil")

KARTTEST.activeUnit = prevActive

-- Semicolon-separated council field (LC shape) ------------------------------------------
T.deep_eq(RC.SplitCouncilField("Bramor;Merrit;Corvin"),
    { "Bramor", "Merrit", "Corvin" }, "SplitCouncilField splits semicolon-separated names")
KARTTEST.SetNSAPI(false)
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Bramor", guid = "Player-1-BBBB" },
    { name = "Merrit", guid = "Player-1-CCCC" },
    { name = "Corvin", guid = "Player-1-DDDD" },
})
KARTTEST.activeUnit = "raid1"
KART_Settings.rcCouncilMembers = "Bramor;Merrit;Corvin"
RCLootCouncil.db.profile.council = {}
KARTTEST.rcCouncilSent = 0
RC.PushCouncilToRC()
T.deep_eq(RCLootCouncil.db.profile.council,
    { "Player-1-BBBB", "Player-1-CCCC", "Player-1-DDDD" },
    "semicolon council list resolves live raid names into GUIDs")

-- lcCouncilMembers -> rcCouncilMembers one-shot migration --------------------------------
local KAUtil = LibStub("KAUtil-1.0")
KARTTEST.RemoveRC()
_G.KART_Settings = { lcCouncilMembers = "Bramor;Merrit;Corvin" }
KAUtil.MergeDefaults(KART_Settings, { rcCouncilMembers = "", rcCouncilMigrated = false })
RC.Enable()
T.eq(KART_Settings.rcCouncilMembers, "Bramor;Merrit;Corvin",
    "MergeDefaults empty rc is backfilled from lc once")
T.eq(KART_Settings.rcCouncilMigrated, true, "migration sets rcCouncilMigrated")
KART_Settings.rcCouncilMembers = ""
RC.Enable()
T.eq(KART_Settings.rcCouncilMembers, "", "second Enable does not restore lc into cleared rc")
KARTTEST.InstallRC()

