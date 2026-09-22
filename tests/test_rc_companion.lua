dofile("tests/rc_stub.lua")

do
    local toc = assert(io.open("KeineAhnungRaidTools.toc", "r")):read("*a")
    T.truthy(not toc:find("LootCouncil%.lua", 1, true),
        "4.0 toc does not load built-in Loot Council files")
end

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

T.is_nil(KART.LC, "4.0 does not create a built-in loot council namespace")

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
T.deep_eq(KARTTEST.rcCouncilSentList,
    { "Player-1-BBBB", "Player-1-CCCC", "Player-1-DDDD" },
    "SendCouncil broadcasts council filled by UpdateGroupCouncil")

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
RC.HandleAwardRequest("1:Ann-TarrenMill:Mainspec", ctx)
T.eq(#KARTTEST.rcAwards, 1, "ML client accepts response text")
T.eq(KARTTEST.rcAwards[1].response, "Mainspec", "response text is forwarded not tonumber")

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

RCLootCouncil.masterLooter = {
    name = "Lead-TarrenMill",
    guid = "Player-1-AAAA",
    class = "WARRIOR",
}
local origSend = KASC.Send
local seenTarget
function KASC:Send(msg, channel, target, opts)
    seenTarget = target
    return origSend(self, msg, channel, target, opts)
end
RC.RequestAward(1, "Ann-TarrenMill", "Offspec")
KASC.Send = origSend
T.eq(type(seenTarget), "string",
    "whisper target is a name string, not RC's Player table")
T.eq(seenTarget, "Lead-TarrenMill", "Player.name is the whisper target")

KARTTEST.activeUnit = awardPrevActive
KARTTEST.RestoreRoster(awardSnap)

-- DisplayName and voting-frame hook -----------------------------------------------------
local nickSnap = KARTTEST.SnapshotRoster()
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({ { name = "Bob", guid = "Player-1-BBBB", nickname = "Bobby" } })
local _, original = KASC.Identity.GetNickname("raid1")
T.eq(RC.DisplayName("raid1"), original or "Bob", "display prefers the NSRT nick")
T.eq(RC.DisplayName("Bob-TarrenMill"), "Bobby",
    "display resolves a raid name to the NSRT nick")
KARTTEST.SetRaid({ { name = "Eve", guid = "Player-1-EEEE", nickname = "|cff00ff00Evil|r" } })
T.eq(RC.DisplayName("raid1"), "||cff00ff00Evil||r",
    "display escapes UI pipes in an NSRT nick")
KARTTEST.SetRaid({ { name = "Bob", guid = "Player-1-BBBB", nickname = "Bobby" } })

local originalMenu = function()
    if not RCLootCouncil.isMasterLooter then return end
    KARTTEST.rcMenuOpened = true
end
local vf = {
    RightClickMenu = originalMenu,
    SetCellName = function(rowFrame, frame, data, cols, row, realrow)
        if frame and frame.text and data[realrow] then
            frame.text:SetText("|T123:0|t" .. data[realrow].name)
        end
    end,
    scrollCols = {},
}
vf.scrollCols[1] = { colName = "name", DoCellUpdate = vf.SetCellName }
local menuFrame = { initialize = vf.RightClickMenu }
_G.RCLootCouncil_VotingFrame_RightclickMenu = menuFrame
local prevGetActiveModule = RCLootCouncil.GetActiveModule
RCLootCouncil.GetActiveModule = function() return nil end
RC.HookVotingFrame()
RCLootCouncil.GetActiveModule = function(_, name)
    if name == "votingframe" then return vf end
end
RCLootCouncil.isMasterLooter = false
RCLootCouncil.isCouncil = true
KARTTEST.rcMenuOpened = nil
local msaCalls = 0
_G.MSA_DropDownMenu_Initialize = function()
    msaCalls = msaCalls + 1
end
RC.HookVotingFrame()
T.eq(msaCalls, 0,
    "HookVotingFrame does not Initialize the MSA menu (that SetAttribute taints TradeFrame)")
menuFrame.initialize(vf)
T.eq(KARTTEST.rcMenuOpened, true,
    "HookVotingFrame succeeds on a later call and opens the RC right-click menu for council")

local cellText = {}
local frame = {
    text = {
        _text = "",
        SetText = function(self, t) self._text = t; cellText[1] = t end,
        GetText = function(self) return self._text end,
    },
}
local data = { [1] = { name = "Wrong" }, [2] = { name = "Bob-TarrenMill" } }
vf.scrollCols[1].DoCellUpdate(nil, frame, data, vf.scrollCols, 1, 2)
T.eq(cellText[1], "|T123:0|tBobby",
    "name cell uses realrow and keeps the owner-loot toast prefix")

RCLootCouncil.isMasterLooter = false
RCLootCouncil.masterLooter = "Lead-TarrenMill"
KARTTEST.activeUnit = "raid1"
local beforeRelay = KASC.diag.sentByToken.RC_AWARD or 0
local relayPayload
origSend = KASC.Send
KASC.Send = function(self, msg, ...)
    if type(msg) == "string" and msg:sub(1, 9) == "RC_AWARD:" then
        relayPayload = msg
    end
    return origSend(self, msg, ...)
end
RCLootCouncilML.Award(RCLootCouncilML, 2, "Bob-TarrenMill", "Mainspec", "reason", function() end, "extra")
KASC.Send = origSend
T.eq((KASC.diag.sentByToken.RC_AWARD or 0) - beforeRelay, 1,
    "council non-ML Award wrap relays via RequestAward")
T.eq(relayPayload, "RC_AWARD:2:Bob-TarrenMill:Mainspec",
    "council relay whisper carries response text")

KARTTEST.rcAwards = {}
RCLootCouncil.isMasterLooter = true
local beforeML = KASC.diag.sentByToken.RC_AWARD or 0
local mlReason = { tier = 1 }
local mlCallback = function() end
RCLootCouncilML.Award(RCLootCouncilML, 3, "Ann-TarrenMill", "Mainspec", mlReason, mlCallback, "extra")
T.eq(#KARTTEST.rcAwards, 1, "ML Award uses originalAward")
T.eq(KARTTEST.rcAwards[1].response, "Mainspec", "ML Award keeps response text")
T.eq(KARTTEST.rcAwards[1].extra[1], mlReason, "ML Award forwards reason")
T.eq(KARTTEST.rcAwards[1].extra[2], mlCallback, "ML Award forwards callback")
T.eq(KARTTEST.rcAwards[1].extra[3], "extra", "ML Award forwards varargs")
T.eq((KASC.diag.sentByToken.RC_AWARD or 0) - beforeML, 0,
    "ML Award does not send RC_AWARD")

RCLootCouncil.isMasterLooter = true
RC.SyncAwardWrap()
local mlAward = RCLootCouncilML.Award
RCLootCouncil.isMasterLooter = false
RCLootCouncil.isCouncil = true
RC.SyncAwardWrap()
T.truthy(RCLootCouncilML.Award ~= mlAward, "non-ML Award is the relay wrap")
T.truthy(vf.RightClickMenu ~= originalMenu, "council-not-ML keeps the menu wrap")
RCLootCouncil.isMasterLooter = true
RC.SyncAwardWrap()
T.eq(RCLootCouncilML.Award, mlAward, "ML Award is restored so KART is not on the trade stack")

RCLootCouncil.isMasterLooter = false
RCLootCouncil.isCouncil = true
RC.SyncAwardWrap()
RCLootCouncil.isMasterLooter = true
RCLootCouncil:NewMLCheck()
T.eq(RCLootCouncilML.Award, mlAward,
    "NewMLCheck unwraps Award so the lead's trade stack is RC's")
T.eq(vf.RightClickMenu, originalMenu,
    "NewMLCheck restores RC's RightClickMenu on the ML client")
T.eq(menuFrame.initialize, originalMenu,
    "NewMLCheck restores MSA initialize on the ML client")

RCLootCouncil.GetActiveModule = prevGetActiveModule
_G.RCLootCouncil_VotingFrame_RightclickMenu = nil
KARTTEST.RestoreRoster(nickSnap)

-- Force-push: the hatch when roster/edit did not land a council on RC ----------------------
KARTTEST.SetNSAPI(true)
KARTTEST.SetRaid({
    { name = "Lead", guid = "Player-1-AAAA", nickname = "Lead", leader = true },
    { name = "Bob",  guid = "Player-1-BBBB", nickname = "Bobby" },
})
KARTTEST.activeUnit = "raid1"
KART_Settings.rcCouncilMembers = "Bobby; Ghost"
RCLootCouncil.db.profile.council = {}
KARTTEST.rcCouncilSent = 0
T.eq(RC.ForcePushCouncil(), true, "lead force-push reports success")
T.deep_eq(RCLootCouncil.db.profile.council, { "Player-1-BBBB" },
    "force-push writes live-alt GUIDs into RC")
T.eq(KARTTEST.rcCouncilSent, 1, "and SendCouncil runs")

KARTTEST.rcCouncilSent = 0
RCLootCouncil.db.profile.council = { "keep-me" }
KARTTEST.activeUnit = "raid2"
T.eq(RC.ForcePushCouncil(), false, "non-lead force-push refuses")
T.deep_eq(RCLootCouncil.db.profile.council, { "keep-me" }, "non-lead force-push does not write RC")
T.eq(KARTTEST.rcCouncilSent, 0, "non-lead force-push does not SendCouncil")

KARTTEST.activeUnit = "raid1"
KARTTEST.RemoveRC()
T.eq(RC.ForcePushCouncil(), false, "force-push without RC refuses")
KARTTEST.InstallRC()

-- Voting tooltip reads KART, without editing RC ---------------------------------------
KART.LH = {
    RecentFor = function()
        return { { item = "|Hitem:9|h[Blade]|h", reason = "Offspec", dateStr = "2026/09/01", color = { 0, 1, 0 } } }
    end,
    WinnersOf = function()
        return { Ann = { { lootWon = "|Hitem:9|h[Blade]|h", response = "Offspec", color = { 0, 1, 0 } } } }
    end,
}
local lines = {}
local tip = {
    ClearLines = function() lines = {} end,
    AddLine = function(_, text) lines[#lines + 1] = text end,
    AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. "|" .. right end,
    SetOwner = function() end,
    Show = function(self) self.shown = true end,
}
local calls = 0
local fake = {
    frame = {
        moreInfo = tip,
        content = {},
        itemText = { GetText = function() return "|Hitem:9|h[Blade]|h" end },
    },
    UpdateMoreInfo = function() calls = calls + 1 end,
    GetItemAwardHistory = function() return { from = "rc" } end,
}
RC.HookVotingHistory(fake)
local history = fake:GetItemAwardHistory("|Hitem:9|h[Blade]|h")
T.eq(history.Ann[1].response, "Offspec", "voting history prefers KART when KART has the item")
fake:UpdateMoreInfo(1, { { name = "Ann" } })
T.eq(calls, 1, "RC's own more-info still runs")
T.eq(tip.shown, true, "KART redraws the voting tooltip")
T.eq(lines[2], "Latest items won", "the tooltip lists latest items from KART")

local rcCalls = {}
local previousRc = SlashCmdList and SlashCmdList.ACECONSOLE_RC
SlashCmdList = SlashCmdList or {}
SlashCmdList.ACECONSOLE_RC = function(input) rcCalls[#rcCalls + 1] = input end
local rclcCalls = {}
SlashCmdList.ACECONSOLE_RCLC = function(input) rclcCalls[#rclcCalls + 1] = input end
local toggles = 0
KART.LH = KART.LH or {}
KART.LH.Toggle = function() toggles = toggles + 1 end
RC.RedirectRcHistory()
SlashCmdList.ACECONSOLE_RC("history")
T.eq(toggles, 1, "/rc history opens the KART history")
T.eq(#rcCalls, 0, "/rc history does not open RC's history")
SlashCmdList.ACECONSOLE_RC("version")
T.eq(rcCalls[1], "version", "/rc version still reaches RC")
SlashCmdList.ACECONSOLE_RCLC("history")
T.eq(rclcCalls[1], "history", "/rclc history still opens RC's history")
SlashCmdList.ACECONSOLE_RC = previousRc
tip.Hide = function(self) self.shown = false end
RCLootCouncil.Getdb = function()
    return { modules = { RCVotingFrame = { moreInfo = false } } }
end
fake:UpdateMoreInfo(1, { { name = "Ann" } })
T.eq(tip.shown, false, "the voting arrow hides KART's tooltip with RC's")
RCLootCouncil.Getdb = function()
    return { modules = { RCVotingFrame = { moreInfo = true } } }
end
fake:UpdateMoreInfo(1, { { name = "Ann" } })
T.eq(tip.shown, true, "the voting arrow shows KART's tooltip with RC's")

