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

-- Council award relay -------------------------------------------------------------------
RCLootCouncil.isMasterLooter = true
RCLootCouncil.db.profile.council = { "Player-1-BBBB" }
local awardSnap = KARTTEST.SnapshotRoster()
local awardPrevActive = KARTTEST.activeUnit
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", leader = true },
    { name = "Bob",  guid = "Player-1-BBBB", realm = "TarrenMill" },
})

local ctx = { sender = "Bob-TarrenMill", channel = "WHISPER" }
RC.HandleAwardRequest("1:Ann-TarrenMill:1", ctx)
T.eq(#KARTTEST.rcAwards, 1, "ML client calls RC Award once")
T.eq(KARTTEST.rcAwards[1].session, 1, "session is forwarded")
T.eq(KARTTEST.rcAwards[1].winner, "Ann-TarrenMill", "winner name is forwarded")

KARTTEST.rcAwards = {}
ctx.sender = "Eve-TarrenMill"
RC.HandleAwardRequest("1:Ann-TarrenMill:1", ctx)
T.eq(#KARTTEST.rcAwards, 0, "non-council whisper is ignored")

RCLootCouncil.isMasterLooter = false
RCLootCouncil.masterLooter = "Lead-TarrenMill"
KARTTEST.activeUnit = "raid2"
local KASC = LibStub("KASC-1.0")
local beforeAward = KASC.diag.sentByToken.RC_AWARD or 0
RC.RequestAward(1, "Ann-TarrenMill", 1)
T.eq((KASC.diag.sentByToken.RC_AWARD or 0) - beforeAward, 1,
    "council non-ML sends RC_AWARD whisper to the master looter")

KARTTEST.activeUnit = awardPrevActive
KARTTEST.RestoreRoster(awardSnap)

-- DisplayName and voting-frame hook -----------------------------------------------------
local nickSnap = KARTTEST.SnapshotRoster()
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Bob", guid = "Player-1-BBBB", nickname = "Bobby" } })
local KASC = LibStub("KASC-1.0")
local folded, original = KASC.Identity.GetNickname("raid1")
T.eq(RC.DisplayName("raid1"), original or "Bob", "display prefers the NSRT nick")
T.eq(RC.DisplayName("Bob-TarrenMill"), "Bobby",
    "display resolves a raid name to the NSRT nick")

local originalMenu = function()
    if not RCLootCouncil.isMasterLooter then return end
    KARTTEST.rcMenuOpened = true
end
local vf = {
    RightClickMenu = originalMenu,
    SetCellName = function(self, frame, data, _, realrow)
        if frame and frame.text then frame.text:SetText(data[realrow].name) end
    end,
    scrollCols = {},
}
vf.scrollCols[1] = { colName = "name", DoCellUpdate = vf.SetCellName }
local menuFrame = { initialize = vf.RightClickMenu }
_G.RCLootCouncil_VotingFrame_RightclickMenu = menuFrame
local prevGetActiveModule = RCLootCouncil.GetActiveModule
RCLootCouncil.GetActiveModule = function(_, name)
    if name == "votingframe" then return vf end
end
RCLootCouncil.isMasterLooter = false
RCLootCouncil.isCouncil = true
KARTTEST.rcMenuOpened = nil
RC.HookVotingFrame()
menuFrame.initialize(vf)
T.eq(KARTTEST.rcMenuOpened, true,
    "menuFrame.initialize opens the RC right-click menu for council")

local cellText = {}
local frame = { text = { SetText = function(_, t) cellText[1] = t end } }
vf:SetCellName(frame, { [1] = { name = "Bob-TarrenMill" } }, nil, 1)
T.eq(cellText[1], "Bobby", "name cell shows the NSRT nick")

RCLootCouncil.isMasterLooter = false
RCLootCouncil.masterLooter = "Lead-TarrenMill"
KARTTEST.activeUnit = "raid1"
local beforeRelay = KASC.diag.sentByToken.RC_AWARD or 0
RCLootCouncilML.Award(RCLootCouncilML, 2, "Bob-TarrenMill", 1)
T.eq((KASC.diag.sentByToken.RC_AWARD or 0) - beforeRelay, 1,
    "council non-ML Award wrap relays via RequestAward")

KARTTEST.rcAwards = {}
RCLootCouncil.isMasterLooter = true
local beforeML = KASC.diag.sentByToken.RC_AWARD or 0
RCLootCouncilML.Award(RCLootCouncilML, 3, "Ann-TarrenMill", 1)
T.eq(#KARTTEST.rcAwards, 1, "ML Award uses originalAward")
T.eq((KASC.diag.sentByToken.RC_AWARD or 0) - beforeML, 0,
    "ML Award does not send RC_AWARD")

RCLootCouncil.GetActiveModule = prevGetActiveModule
_G.RCLootCouncil_VotingFrame_RightclickMenu = nil
KARTTEST.RestoreRoster(nickSnap)

