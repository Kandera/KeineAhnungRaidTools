-- The WoWUtils module: importing a raid composition, inviting it, and removing everyone who is not
-- on it.
--
-- Invite.lua had no test. UninviteUnit and C_PartyInfo were not in the harness at all until
-- 2026-08-01, so WU.InviteBoss and WU.RemoveForBoss had never run a line -- a call would have thrown.
--
-- Removing is the most destructive thing this addon can do. It kicks real people out of a raid, they
-- have to be re-invited and accept again, and there is no undo. That is worth being careful about.

local env = setmetatable({}, { __index = _G })
env.KART_Settings = { wuModuleEnabled = true }
-- Any key answers with its own name, except the handful used with string.format -- those need the
-- right number of specifiers or the format call itself throws, which would be the test's fault
-- rather than the addon's. (The real strings are checked in tests/test_locales.lua.)
local L = {
    WU_MSG_INVITED = "invited %d for %s",
    WU_MSG_ALREADY_IN = "%d already in",
    WU_MSG_REMOVED = "removed %d for %s",
    WU_STATUS_LOADED = "loaded %d",
    WU_REMOVE_CONFIRM_TEXT = "remove %d?",
}
local KART = { L = setmetatable(L, { __index = function(_, k) return k end }) }
env.KART = KART

-- The two things Invite.lua reaches for at file scope. RegisterStaticPopup writes into the same
-- StaticPopupDialogs table KARTTEST.AcceptPopup reads, so a confirm raised here is answerable.
-- The real widget library underneath, so WU.BuildPanel builds the real controls rather than
-- stand-ins; only RegisterStaticPopup is replaced, to write into the same StaticPopupDialogs table
-- KARTTEST.AcceptPopup reads.
KART.UI = setmetatable({
    RegisterStaticPopup = function(_, name, def) StaticPopupDialogs[name] = def end,
}, { __index = LibStub("KAUI-1.0"):NewNamespace("KARTWoWUtilsTest") })

do
    local chunk = assert(loadstring(assert(io.open("Invite.lua", "r")):read("*a"), "@Invite.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
local WU = KART.WU
T.truthy(WU and WU.ParseImport, "the WoWUtils module loads standalone")
for _, fn in ipairs({ "ParseImport", "InviteBoss", "RemoveForBoss", "ResetBosses" }) do
    setfenv(WU[fn], env)
end

local function Raid(others, me)
    KARTTEST.realm = "TarrenMill"
    KARTTEST.solo = {}
    local all = {}
    for _, m in ipairs(others) do all[#all + 1] = m end
    all[#all + 1] = me or { name = "Kandera", guid = "Player-1-A", leader = true }
    KARTTEST.SetRaid(all)
    KARTTEST.activeUnit = "raid" .. #all
    KARTTEST.ClearInvites()
    KARTTEST.popups = {}
end

local function Import(text)
    WU.bosses = {}
    WU.lastImportedText = nil
    return WU.ParseImport(text)
end

local EXPORT = "EncounterID:3134;Difficulty:Heroic;Name:Plexus Sentinel\ninvitelist:Kandera Wuusch Narrath;"

-- The parser ---------------------------------------------------------------------------------------
do
    T.eq(Import(EXPORT), 1, "one boss block is parsed")
    T.eq(WU.bosses[1].name, "Plexus Sentinel", "with its name")
    T.eq(WU.bosses[1].difficulty, "Heroic", "and its difficulty")
    T.eq(#WU.bosses[1].players, 3, "and everybody on the invite list")
end

do
    -- Two rosters for the same boss and difficulty is a split raid, not a mistake: both are kept and
    -- both stay distinguishable, including the FIRST one, which is renamed retroactively.
    Import(EXPORT)
    WU.ParseImport("EncounterID:3134;Difficulty:Heroic;Name:Plexus Sentinel\ninvitelist:Sinja Merrit;")
    T.eq(#WU.bosses, 2, "a second roster for the same boss is kept alongside the first")
    T.eq(WU.bosses[1].name, "Plexus Sentinel A", "the first one is relabelled")
    T.eq(WU.bosses[2].name, "Plexus Sentinel B", "and the second gets its own letter")

    WU.ParseImport("EncounterID:3134;Difficulty:Heroic;Name:Plexus Sentinel\ninvitelist:Corvin;")
    T.eq(WU.bosses[3].name, "Plexus Sentinel C", "and a third keeps counting")
    T.eq(WU.bosses[1].name, "Plexus Sentinel A", "without relabelling the first one again")
end

do
    -- Same boss, DIFFERENT difficulty is not a split -- pasting Normal and then Heroic must leave two
    -- plainly named entries rather than "A" and "B" of the same thing.
    Import(EXPORT)
    WU.ParseImport("EncounterID:3134;Difficulty:Normal;Name:Plexus Sentinel\ninvitelist:Sinja;")
    T.eq(WU.bosses[1].name, "Plexus Sentinel", "the heroic entry keeps its plain name")
    T.eq(WU.bosses[2].name, "Plexus Sentinel", "and so does the normal one")
end

do
    T.eq(Import(""), 0, "empty text parses nothing")
    T.eq(Import("   "), 0, "and so does whitespace")
    T.eq(Import("not an export at all"), 0, "and so does text that is not an export")
    T.eq(#WU.bosses, 0, "none of which leaves anything behind")
end

-- Inviting -----------------------------------------------------------------------------------------
do
    Raid({ { name = "Wuusch", guid = "Player-1-B" } })
    Import(EXPORT)
    WU.InviteBoss(1)
    T.eq(#KARTTEST.invited, 1, "only the people not already here are invited")
    T.eq(KARTTEST.invited[1], "Narrath", "and it is the one who is missing")
end

do
    -- Starting a raid from nothing is what this button is FOR: open the tab before the evening,
    -- click the first boss, and the invites go out. KAUtil.HasGroupPermissions answers false while
    -- ungrouped -- correctly, there is no group to lead -- so gating on it alone refused the whole
    -- feature at its main use. The deferred raid conversion further down (KART.pendingBulkRaidConvert)
    -- exists only for this case and could never be reached, which is what gives it away.
    --
    -- And ourselves, never: EachGroupUnit yields nothing while solo, so the player would otherwise be
    -- invited to their own group -- a red error and a count one too high.
    KARTTEST.realm = "TarrenMill"
    KARTTEST.SetRaid({ { name = "Kandera", guid = "Player-1-A", leader = true } })
    KARTTEST.activeUnit = "raid1"
    KARTTEST.solo = { raid1 = true }
    KARTTEST.ClearInvites()
    Import(EXPORT)
    WU.InviteBoss(1)
    for _, who in ipairs(KARTTEST.invited) do
        T.truthy(who ~= "Kandera", "a bulk invite while solo does not invite the player themselves")
    end
    T.eq(#KARTTEST.invited, 2, "just the other two")
    KARTTEST.solo = {}
end

do
    -- The module switch is off: nothing happens at all, invite or remove.
    Raid({ { name = "Wuusch", guid = "Player-1-B" } })
    Import(EXPORT)
    env.KART_Settings.wuModuleEnabled = false
    WU.InviteBoss(1)
    WU.RemoveForBoss(1)
    T.eq(#KARTTEST.invited, 0, "a disabled module invites nobody")
    T.eq(#KARTTEST.uninvited, 0, "and removes nobody")
    T.eq(#KARTTEST.popups, 0, "and does not even ask")
    env.KART_Settings.wuModuleEnabled = true
end

-- Removing -------------------------------------------------------------------------------------------
-- One click on a 70-pixel button next to "Invite" kicks everybody who is not on that boss's list.
-- There is no undo: they have to be re-invited and accept again. Resetting the boss LIST asks first
-- and says "this cannot be undone"; removing people asked nothing at all.
do
    Raid({ { name = "Wuusch",  guid = "Player-1-B" },
           { name = "Sinja",   guid = "Player-1-C" },
           { name = "Merrit",  guid = "Player-1-D" } })
    Import(EXPORT)  -- Kandera, Wuusch, Narrath -- so Sinja and Merrit are not on it

    WU.RemoveForBoss(1)
    T.eq(#KARTTEST.uninvited, 0, "nobody is removed on the click itself")
    T.eq(#KARTTEST.popups, 1, "it asks first")
    T.eq(KARTTEST.popups[1] and KARTTEST.popups[1].which, "KART_WU_REMOVE_CONFIRM",
        "with its own confirmation")
    T.eq(KARTTEST.popups[1] and KARTTEST.popups[1].a, 2,
        "naming how many people it is about to remove")

    KARTTEST.AcceptPopup("KART_WU_REMOVE_CONFIRM")
    table.sort(KARTTEST.uninvited)
    T.eq(table.concat(KARTTEST.uninvited, ","), "Merrit,Sinja",
        "and once confirmed it removes exactly the people not on the list")
end

do
    -- Not answering the dialog is the same as saying no.
    Raid({ { name = "Wuusch", guid = "Player-1-B" },
           { name = "Sinja",  guid = "Player-1-C" } })
    Import(EXPORT)
    WU.RemoveForBoss(1)
    T.eq(#KARTTEST.uninvited, 0, "an unanswered confirmation removes nobody")
end

do
    -- Never yourself, even standing on a roster you are not on. EachGroupUnit yields raid1..raidN and
    -- never the literal "player" token, so this cannot be a token comparison.
    Raid({ { name = "Wuusch", guid = "Player-1-B" } },
         { name = "Fremder", guid = "Player-1-Z", leader = true })
    Import(EXPORT)  -- Fremder is not on it
    WU.RemoveForBoss(1)
    KARTTEST.AcceptPopup("KART_WU_REMOVE_CONFIRM")
    for _, who in ipairs(KARTTEST.uninvited) do
        T.truthy(who ~= "Fremder", "a roster that does not list you cannot kick you from your own raid")
    end
end

do
    -- Nobody to remove: no dialog, because a confirmation for nothing trains people to click through
    -- the one that matters.
    Raid({ { name = "Wuusch",  guid = "Player-1-B" },
           { name = "Narrath", guid = "Player-1-C" } })
    Import(EXPORT)
    WU.RemoveForBoss(1)
    T.eq(#KARTTEST.popups, 0, "nothing to remove asks nothing")
    T.eq(#KARTTEST.uninvited, 0, "and removes nothing")
end

KARTTEST.activeUnit = nil

-- The Import button ---------------------------------------------------------------------------------
-- The parser above is reached directly; the BUTTON around it holds three rules of its own, none of
-- which had run -- WU.BuildPanel had never been called, so every line of the panel was dark.
--
-- The panel needs the two things Core.lua and MainFrame.lua provide and the harness does not:
-- a tab-title creator and the locale-refresher registry's owner table.
do
    KART.CreateTabTitle = KART.CreateTabTitle or function() end
    KART.TabTitles = KART.TabTitles or setmetatable({}, { __index = function(t, k)
        local f = CreateFrame("Frame")
        rawset(t, k, f)
        return f
    end })
    setfenv(WU.BuildPanel, env)
    WU.BuildPanel(CreateFrame("Frame"))
    T.truthy(WU.BtnImport and WU.ImportEditBox, "the WoWUtils panel builds")

    -- The locale refresher this panel registers, run the way Core.lua runs it: on load and again
    -- whenever the language is switched. It re-labels widgets by hand, one line per widget, so it
    -- goes stale silently -- a renamed or removed control leaves a nil index that only throws when
    -- somebody actually changes their language. Nine of these exist across the addon and none had
    -- ever been called.
    local ok, err = pcall(function() KART.UI:ApplyLocaleRefreshers() end)
    T.truthy(ok, "its locale refresher runs without error: " .. tostring(err))
end

local function ClickImport(text)
    WU.ImportEditBox:SetText(text)
    WU.BtnImport:GetScript("OnClick")(WU.BtnImport)
    return WU.bosses
end

do
    -- Replace, not append. Only the edit box's text is saved, so the list has to be reconstructible
    -- from it alone -- an appended second import would silently shrink back to the last export on
    -- the next reload, and re-clicking Import on a box holding both would duplicate the first.
    WU.bosses, WU.lastImportedText = {}, nil
    ClickImport(EXPORT)
    T.eq(#WU.bosses, 1, "importing loads the roster")

    local other = "EncounterID:3135;Difficulty:Heroic;Name:Loomithar\ninvitelist:Sinja Merrit;"
    ClickImport(other)
    T.eq(#WU.bosses, 1, "a second import replaces the first rather than adding to it")
    T.eq(WU.bosses[1].name, "Loomithar", "leaving only what is in the box")
end

do
    -- Clicking Import again on unchanged text must not double the list. This is the ordinary case:
    -- the text is re-parsed from the saved box at login, and the player then presses the button.
    WU.bosses, WU.lastImportedText = {}, nil
    ClickImport(EXPORT)
    local first = #WU.bosses
    ClickImport(EXPORT)
    T.eq(#WU.bosses, first, "re-importing identical text changes nothing")
end

do
    -- The one that matters on a raid night: a failed paste must not leave the raid leader with an
    -- empty list. Rebuilding from the saved text would not work either -- the box's OnTextChanged has
    -- already overwritten it with the text that just failed.
    WU.bosses, WU.lastImportedText = {}, nil
    ClickImport(EXPORT)
    local loaded = WU.bosses
    T.eq(#loaded, 1, "a roster is loaded")

    ClickImport("this is not an export at all")
    T.eq(#WU.bosses, 1, "a paste that parses to nothing leaves the previous roster in place")
    T.eq(WU.bosses[1].name, "Plexus Sentinel", "the same one, not a rebuilt guess")
end

do
    -- The module switch is off: the button does nothing at all rather than half of it.
    WU.bosses, WU.lastImportedText = {}, nil
    ClickImport(EXPORT)
    env.KART_Settings.wuModuleEnabled = false
    ClickImport("EncounterID:3135;Difficulty:Heroic;Name:Loomithar\ninvitelist:Sinja;")
    T.eq(WU.bosses[1].name, "Plexus Sentinel", "with the module off, Import leaves the list untouched")
    env.KART_Settings.wuModuleEnabled = true
end
