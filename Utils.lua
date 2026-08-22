local addonName, KART = ...
local KAGS = LibStub("KAGS-1.0")
local KASC = LibStub("KASC-1.0")
local KAUtil = LibStub("KAUtil-1.0")

local KAUI = LibStub("KAUI-1.0")
KART.UI = KAUI:NewNamespace("KART")
-- Popup artwork lives in this addon's own folder, so the path is supplied here rather than
-- hardcoded in the library -- see KAUI-1.0's ApplyPopupArtwork for what happens if it's unset.
KART.UI.popupArtworkPath = "Interface\\AddOns\\KeineAhnungRaidTools\\media\\backgrounds\\kart-popup-bg-dark.png"

-- KART.L itself is a STABLE table — its reference must never be replaced, only its values
-- swapped (files capture `local L = KART.L` at load time and keep that reference). Locale
-- refreshers (functions that re-apply static UI text once the saved language is known) are
-- registered via KART.UI:RegisterLocaleRefresher; Core.lua runs them once at ADDON_LOADED,
-- right after the locale values are copied into KART.L.
KART.L = KART.L or {}

-- =====================================================================
--  Escape-closable windows, and surviving a stun
-- =====================================================================
-- Every window in this addon that Escape should close is registered in Blizzard's UISpecialFrames.
-- That list has a second reader nobody wired for: PLAYER_CONTROL_LOST runs
-- CloseAllWindows_WithExceptions, which ends in CloseSpecialWindows -- a bare loop over
-- UISpecialFrames calling Hide() on every entry that is shown (Blizzard_UIParentPanelManager, and
-- the "exceptions" are UIPanels only, so there is nothing an addon frame can opt out of).
--
-- The result, reported from a live raid on 2026-08-05: the first trash pull that stuns or fears
-- somebody takes their vote window, the council panel, the trade reminder and the loot history with
-- it, in the middle of a loot round. Nothing is lost -- the frames are only hidden -- but the person
-- voting has no window to vote in and no reason to suspect one existed.
--
-- The repair is deliberately NOT "leave UISpecialFrames": Escape closing these windows is wanted.
-- Instead, a hide that lands in the SAME frame as PLAYER_CONTROL_LOST is treated as Blizzard's and
-- undone -- whether it arrives before our handler or after it. A hide the player asked for --
-- Escape, the "x" -- happens in some other frame and is left alone, apart from the vanishingly rare
-- case of pressing Escape in the same instant a stun lands, which costs one frame of a window
-- staying open.
local controlLossWindow = false
local hiddenByControlLoss = {}
-- The hides of the current frame, kept so a Blizzard handler that runs BEFORE ours is not lost.
-- GetTime() is constant within a frame, which is what makes "same frame" cheap to ask.
local thisFrameHides, thisFrameAt = {}, nil

function KART.RegisterEscapeFrame(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name then return end
    table.insert(UISpecialFrames, name)
    frame:HookScript("OnHide", function(self)
        local now = GetTime()
        if now ~= thisFrameAt then
            wipe(thisFrameHides)
            thisFrameAt = now
        end
        thisFrameHides[#thisFrameHides + 1] = self
        if controlLossWindow then hiddenByControlLoss[#hiddenByControlLoss + 1] = self end
    end)
end

-- Called from Core.lua's PLAYER_CONTROL_LOST handler. Which of the two handlers runs first, ours or
-- Blizzard's, is decided by registration order -- and UIParent registers the event in its OnLoad,
-- so Blizzard going first is the likely case, not the exotic one. This therefore looks both ways:
-- backwards at the hides already booked in this frame, and forwards through the window below. It
-- does not snapshot what is currently shown, which reads empty in exactly the backwards case.
function KART.OnControlLost()
    if controlLossWindow then return end
    controlLossWindow = true
    if GetTime() == thisFrameAt then
        for _, frame in ipairs(thisFrameHides) do
            hiddenByControlLoss[#hiddenByControlLoss + 1] = frame
        end
    end
    C_Timer.After(0, function()
        controlLossWindow = false
        for _, frame in ipairs(hiddenByControlLoss) do frame:Show() end
        wipe(hiddenByControlLoss)
    end)
end

-- =====================================================================
--  Reading another unit's group standing, on a client that may refuse to say
-- =====================================================================
-- 12.1 makes a number of unit APIs return SECRET values when the unit's identity is secret, and
-- UnitIsGroupLeader and UnitIsGroupAssistant are on that list (docs/BACKLOG-12.1.md, P4). A secret
-- used in an `if` raises an error -- so on a client where that happens, the handler doing the asking
-- dies rather than answering wrong.
--
-- Which handlers: LC.IsSenderLootOwner authorises every incoming Loot Council message, LC.GetLootOwnerKey
-- decides who holds the loot when no lootmaster is configured, and TryAcceptConfig decides whether the
-- raid's settings are taken. An error in those is not a cosmetic loss; it is the loot flow stopping
-- mid-distribution with a Lua error where a decision should have been.
--
-- Whether a group member's identity is ever secret to their OWN group is not known and cannot be
-- measured solo, which is why this is written before the answer rather than after: the cost of being
-- wrong the other way is one pcall per call.
--
-- "Cannot tell" deliberately does NOT mean "no". Answering false would take the lootmaster's
-- authority away at the exact moment combat starts, which is the same outage with a quieter cause.
-- The last answer this client actually got is used instead -- leadership does not change during a
-- pull, and the cache is dropped whenever the roster does (KART.ForgetUnitStanding, called from
-- Core.lua's GROUP_ROSTER_UPDATE), so a stale token can never answer for a new occupant.
local unitLeads, unitAssists = {}, {}

function KART.ForgetUnitStanding()
    wipe(unitLeads)
    wipe(unitAssists)
end

-- pcall, and then a type check rather than a comparison: `value == true` is itself the operation a
-- secret refuses, so the answer has to be shown to be an ordinary boolean before it is used at all.
local function readStanding(fn, unit, cache)
    local ok, value = pcall(fn, unit)
    if ok and type(value) == "boolean" then
        cache[unit] = value
        return value
    end
    local last = cache[unit]
    if last ~= nil then return last end
    return false
end

function KART.UnitLeads(unit)
    if not unit then return false end
    return readStanding(UnitIsGroupLeader, unit, unitLeads)
end

function KART.UnitAssists(unit)
    if not unit then return false end
    return readStanding(UnitIsGroupAssistant, unit, unitAssists)
end

-- =====================================================================
--  /kart ptr -- what the client underneath actually does
-- =====================================================================
-- A maintenance tool in the same spirit as /kart ench: it prints facts about the CLIENT, so a new
-- game version is answered with measurements instead of with reading patch notes and guessing.
--
-- It exists because the alternative was four hand-typed /run probes per question, each of which has
-- to fit in 255 characters, on a PTR where the tester is solo and every round trip costs an evening.
-- Everything it asks is in docs/BACKLOG-12.1.md; the answers decide P1, P2 and P3, and narrow P4.
--
-- Every single read is pcall'd, including the ones that "cannot fail". That is the entire point: on a
-- client that returns secret values, the failure mode being measured IS an error, and a probe that
-- dies while asking answers nothing.
--
-- Deliberately not localized and not in /kart help: it is for whoever is porting the addon to a new
-- client, and it will be read next to the backlog file, in English.
local function probe(label, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return label .. " = ERROR (" .. tostring(a) .. ")" end
    if b ~= nil then return label .. " = " .. type(a) .. " " .. tostring(a) .. " / " .. tostring(b) end
    return label .. " = " .. type(a) .. " " .. tostring(a)
end

-- Whether a value can be USED, which is a different question from whether it can be read. A secret
-- reads back fine and raises on comparison, so this is the check that actually finds one.
local function comparable(value)
    local ok = pcall(function() return value == value end)
    return ok and "usable" or "SECRET (raises when compared)"
end

function KART.PrintClientProbe()
    print("|cff00ff00KART " .. (KART.Version or "?") .. "|r client probe -- see docs/BACKLOG-12.1.md")
    print("  interface = " .. tostring(select(4, GetBuildInfo())) .. "  build = " .. tostring((GetBuildInfo())))

    -- P1: the raidlead bar's secure buttons do nothing unless this is 1.
    print("  " .. probe("P1 ActionButtonUseKeyDown", C_CVar.GetCVar, "ActionButtonUseKeyDown"))

    -- P2: the whole oil column reads this one API.
    print("  P2 GetWeaponEnchantInfo = " .. type(GetWeaponEnchantInfo))
    if type(GetWeaponEnchantInfo) == "function" then
        print("  " .. probe("P2 -> mainhand", GetWeaponEnchantInfo))
    end

    -- P3: the buff checker walks auras by index and reads their fields.
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    if not ok then
        print("  P3 GetAuraDataByIndex = ERROR (" .. tostring(aura) .. ")")
    elseif aura == nil then
        print("  P3 GetAuraDataByIndex = nil -- put any buff on yourself and run this again")
    else
        print("  P3 aura.name = " .. comparable(aura.name) .. "  aura.spellId = " .. comparable(aura.spellId))
    end

    -- P3 and P4 both come down to reading ANOTHER unit, and the player's own identity is never
    -- secret -- so the two lines above answer the easy half of P3 and the loop below is where both
    -- are actually decided. A solo login reaches neither, which the probe says rather than leaving
    -- the reader to notice the silence.
    --
    -- The other person needs nothing: no addon, no version, no settings. This client is the one
    -- asking, they are only the unit being asked about.
    print("  " .. probe("P4 UnitIsGroupLeader(player)", UnitIsGroupLeader, "player"))
    local checked = 0
    for unit in KAUtil.EachGroupUnit() do
        if not UnitIsUnit(unit, "player") and checked < 3 then
            checked = checked + 1
            local okL, leads = pcall(UnitIsGroupLeader, unit)
            local okC, class = pcall(UnitClass, unit)
            print("  P4 " .. unit .. " leader = " .. (okL and comparable(leads) or "ERROR")
                .. "  class = " .. (okC and comparable(class) or "ERROR"))

            -- P3's real question. The buff checker walks every group member's auras and compares
            -- their fields, so THIS is the read that decides whether that module works on 12.1 --
            -- and it is the one a solo login cannot make.
            local okA, other = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HELPFUL")
            if not okA then
                print("  P3 " .. unit .. " aura = ERROR (" .. tostring(other) .. ")")
            elseif other == nil then
                print("  P3 " .. unit .. " aura = nil -- ask them to eat something and run this again")
            else
                print("  P3 " .. unit .. " aura.name = " .. comparable(other.name)
                    .. "  aura.spellId = " .. comparable(other.spellId))
            end
        end
    end
    if checked == 0 then
        print("  P3/P4 no other group member to ask -- both open questions are about ANOTHER unit,")
        print("        so a solo login cannot answer either. Two people on 12.1 is enough.")
    end
end

-- Standardeinstellungen
KART.Defaults = {
    inviteKeywords = "inv;+;invite",
    inviteViaGuildChat = false,
    inviteChannels = { WHISPER = true, BN = true, GUILD = false, OFFICER = false },
    promoteNames = "",
    showRaidleadBar = false,
    lockRaidleadBar = false,
    autoHideRaidleadBar = false,
    autoHideRaidleadBarCombat = false,
    rlBarFrameStrata = 4, -- index into KART.StrataLevels; own slider, not frameStrata
    rlBarYieldToMap = true, -- drop the bar under WorldMapFrame while the map is open
    pullTimerDuration = 10,
    rcReasonDialog = true,
    keybinds = {}, -- filled per-action at runtime (see KART.ApplyKeybinds); nil fields in a table literal are a no-op anyway
    bcModuleEnabled = false,
    ctModuleEnabled = false,
    ct = {
        schemaVersion = 1,
        -- position
        point = "CENTER", relativePoint = "CENTER", x = 0, y = 200,
        locked = true,
        testMode = false,
        onlyInGroup = true,
        onlyInInstance = true,
        -- row
        width = 220, height = 36, scale = 1,
        healthColor = "class", -- "class" | "custom" | "health"
        healthCustom = { r = 0.2, g = 0.8, b = 0.2 },
        healthHigh = { r = 0.2, g = 0.8, b = 0.2 },
        healthMid  = { r = 0.9, g = 0.8, b = 0.2 },
        healthLow  = { r = 0.8, g = 0.2, b = 0.2 },
        healthFill = "right", -- "right" | "left" | "up" | "down"
        healthAlpha = 1, trackAlpha = 0.4,
        bgColor = { r = 0.06, g = 0.07, b = 0.08 },
        bgAlpha = 0.92,
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0 },
        absorbShow = true, healAbsorbShow = true,
        absorbColor = { r = 0.4, g = 0.85, b = 0.85 },
        absorbAlpha = 0.7,
        healAbsorbColor = { r = 0.6, g = 0.2, b = 0.8 },
        healAbsorbAlpha = 0.7,
        nameMaxLength = 12,
        healthText = "both", -- "percent" | "current" | "both" | "deficit"
        nameStyle = {
            show = true, size = 0, classColor = false, outline = "OUTLINE",
            anchor = "LEFT", x = 6, y = 0,
            color = { r = 1, g = 1, b = 1 },
        },
        healthStyle = {
            show = true, size = 0, classColor = false, outline = "OUTLINE",
            anchor = "RIGHT", x = -6, y = 0,
            color = { r = 1, g = 1, b = 1 },
        },
        rangeFade = true,
        rangeAlpha = 0.4,
        deadFade = 0.35,
        offlineFade = 0.35,
        targetBorder = {
            show = false, size = 2,
            color = { r = 1, g = 0.85, b = 0.2 },
        },
        -- strips: show, max, size, spacing, perRow, anchor, growth, x, y, chrome
        debuffs = { show = true, max = 8, size = 22, spacing = 1, perRow = 8,
                    anchor = "TOPLEFT", growth = "right", x = 0, y = 4,
                    borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                    swipe = true, countdown = true, countdownSize = 0,
                    stacks = true, stacksSize = 0 },
        buffs   = { show = true, max = 6, size = 18, spacing = 1, perRow = 6,
                    anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4,
                    borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
                    swipe = true, countdown = true, countdownSize = 0,
                    stacks = true, stacksSize = 0 },
        taunt = {
            announce = false,
            channels = {
                WHISPER = true, GROUP = false, RAID_WARNING = false,
                SAY = false, YELL = false,
            },
            message = "Taunt: %t",
            ask = "%n, please taunt!",
            onlyInGroup = true,
            onlyInInstance = true,
            button = false,
            buttonOnlyInGroup = true,
            buttonOnlyInRaid = false,
            size = 44,
            locked = true,
            point = "CENTER", relativePoint = "CENTER", x = 80, y = 200,
        },
    },
    showBuffCheck = false,
    buffCheckAlpha = 90,
    bcCombatDelay = 2,
    grayOffline = true,
    minimap = {},
    showMinimapIcon = true,
    autoConvertToRaid = false,
    titleFontSize = 12,
    menuFontSize = 11,
    contentFontSize = 12,
    bgAlpha = 85,
    uiScale = 100, -- whole-window scale in percent (PNG-artwork window is not freely resizable)
    fontName = "Friz Quadrata",
    accentR = 0, accentG = 60, accentB = 100,
    bgR = 10, bgG = 10, bgB = 10,
    language = "Auto",
    rcCouncilMembers = "",
    rcCouncilMigrated = false,
    rcShowNickNames = true,
    rcShowOwedReminder = true,
    wuImportText = "",
    frameStrata = 4, -- index into KART.StrataLevels (4 = HIGH)
    autoLogEnabled = false,
    autoLogRaidLFR = false,
    autoLogRaidNormal = false,
    autoLogRaidHeroic = false,
    autoLogRaidMythic = false,
    autoLogMythicPlus = false,
    autoLogMinKey = 2,
    autoLogDungeons = false,
    autoLogDelves = false,
    autoLogOwned = false, -- hidden: whether the addon (not the player) started the current combat log
}

-- True only when semver `ver` is strictly OLDER than `current` -- so a peer on a NEWER build is not
-- mislabeled "outdated". Lenient about a missing part: a two-part "3.2" or a build suffix still
-- yields usable numbers instead of failing the match outright and collapsing every field to 0.
--
-- Shared rather than per-file: the council panel's outdated marker and the Loot Council's protocol
-- check must agree on what "older" means, and two copies of a comparison quietly drift.
function KART.IsOlderVersion(ver, current)
    local a1, a2, a3 = tostring(ver):match("(%d+)%.?(%d*)%.?(%d*)")
    local b1, b2, b3 = tostring(current):match("(%d+)%.?(%d*)%.?(%d*)")
    a1, a2, a3 = tonumber(a1) or 0, tonumber(a2) or 0, tonumber(a3) or 0
    b1, b2, b3 = tonumber(b1) or 0, tonumber(b2) or 0, tonumber(b3) or 0
    if a1 ~= b1 then return a1 < b1 end
    if a2 ~= b2 then return a2 < b2 end
    return a3 < b3
end

-- ==========================================================================
--  B120: asking again for the handshakes that never arrived
-- ==========================================================================
--
-- KART asks the raid to introduce itself exactly once, when the group channel changes (Core.lua's
-- roster handler) -- which is during raid formation, the single noisiest minute of the evening. Every
-- client is doing the same thing, every answer goes out in the same instant, and whatever Blizzard's
-- rate limiter drops is gone for good: nothing asks again. The result is a council panel that marks
-- half the raid as not running KART while they plainly are, all evening, until somebody types
-- /kart v by hand -- which is exactly what happened on 2026-08-03 and exactly what cleared it.
--
-- So ask again, but only about the people we are actually missing, and only ever about them: once the
-- table is complete this costs nothing at all, which is what makes it safe to hang on an event that
-- fires all evening.
local HELLO_WHISPER_MAX = 5

-- Deliberately two shapes, because the two situations are not the same one:
--   * a whole raid unknown -- formation, or our own reload -- is one broadcast. Whispering 24 people
--     individually there would be the very burst this is trying to survive.
--   * a handful unknown -- the ordinary mid-evening loss -- is a whisper each. Nobody else is asked
--     to answer, and no other client has to hear about it.
function KART.RequestMissingHellos()
    if not IsInGroup() then return end
    local missing = {}
    for unit in KAUtil.EachGroupUnit() do
        -- Never ourselves: we do not process our own broadcast, so PlayerVersions has no entry for us
        -- by design and asking would produce one request per roster change, forever.
        if not UnitIsUnit(unit, "player") then
            local name, realm = UnitName(unit)
            local short = name and name:match("([^%-]+)")
            if short and not (KART.PlayerVersions and KART.PlayerVersions[short]) then
                missing[#missing + 1] = (realm and realm ~= "") and (name .. "-" .. realm) or name
            end
        end
    end
    if #missing == 0 then return end
    if #missing > HELLO_WHISPER_MAX then
        KASC:RequestHello()
        return
    end
    for _, full in ipairs(missing) do KASC:RequestHello("WHISPER", full) end
end

-- GROUP_ROSTER_UPDATE fires in bursts while a raid fills up, and the answer cannot change between two
-- firings in the same second. Same leading-edge throttle as KART.HandleAutoPromoteThrottled, with a
-- window long enough that a raid forming asks once rather than once per arrival.
local missingHellosThrottled = false
function KART.RequestMissingHellosThrottled()
    if missingHellosThrottled then return end
    missingHellosThrottled = true
    C_Timer.After(15, function()
        missingHellosThrottled = false
        KART.RequestMissingHellos()
    end)
end

-- Ordered list of WoW frame strata a KART window may sit on, kept here (rather than only inside
-- KAUI-1.0's own copy) purely so the settings-tab strata slider (MainFrame.lua) has a name list
-- and count to build its range and value display from. The raidlead bar has its own
-- `rlBarFrameStrata` slider and is not in these registries. The strata registries and the apply/
-- register logic itself live in KAUI-1.0 now; see KART.UI:RegisterStrataFrame et al.
KART.StrataLevels = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }

-- Fixed status colors used by the addon's own remaining UI code (BuffChecker gear-check
-- indicators). Kept as plain data (no frame references) so KART.UpdateStyles() and callers can
-- read them fresh on every settings change without caching stale colors. Corner radii, font
-- path, accent color and the widget factories all moved to KAUI-1.0.
KART.SUCCESS = {0.35, 0.75, 0.35}
KART.WARNING = {0.90, 0.70, 0.20}
KART.DANGER  = {0.85, 0.30, 0.30}

function KART.UpdateMinimapButton()
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not dbIcon then return end
    -- LibDBIcon keeps its own visibility flag inside the saved table it was registered with, and
    -- both Register and Refresh decide whether to show the button from THAT flag alone -- not from
    -- our checkbox. Leaving it unwritten meant the Refresh below immediately undid our own Hide,
    -- and a fresh login re-showed the icon however the checkbox was set (B4). Write it first so
    -- every path agrees.
    KART_Settings.minimap.hide = not KART_Settings.showMinimapIcon
    if KART_Settings.showMinimapIcon then
        dbIcon:Show("KeineAhnungRaidTools")
    else
        dbIcon:Hide("KeineAhnungRaidTools")
    end
    -- LibDBIcon only reads minimapPos out of its saved table when told to refresh. A profile switch
    -- swaps that table's contents (Profiles.lua keeps the table's identity for exactly this reason),
    -- so without this the icon keeps the previous profile's angle until the next drag or reload.
    if dbIcon.Refresh then
        pcall(dbIcon.Refresh, dbIcon, "KeineAhnungRaidTools", KART_Settings.minimap)
    end
end

-- The enchant's display NAME for `slot`, read off the item tooltip's "Enchanted: X" line.
--
-- This is the piece that makes the whole exercise verifiable. The item link carries only the numeric
-- id, and a bare number can't be checked against anything — which is how a table of invented ids got
-- shipped in the first place. The name can: it maps straight onto a published list of the tier's
-- enchants, so an id is only ever accepted once its name has been confirmed as one of them.
local function EnchantNameForSlot(slot)
    if not ENCHANTED_TOOLTIP then return nil end ---@diagnostic disable-line: undefined-global
    -- ENCHANTED_TOOLTIP is Blizzard's own localized "Enchanted: %s" template. Escaping it and then
    -- turning its %s into a capture keeps this working on a German client ("Verzaubert: %s") without
    -- hardcoding either language.
    local pattern = "^" .. ENCHANTED_TOOLTIP ---@diagnostic disable-line: undefined-global
        :gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        :gsub("%%%%s", "(.+)")
    KART_GearScanTooltip:ClearLines()
    KART_GearScanTooltip:SetInventoryItem("player", slot)
    for i = 1, KART_GearScanTooltip:NumLines() do
        local fs = _G["KART_GearScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        local name = text and text:match(pattern)
        if name then return name end
    end
    return nil
end

function KART.PrintEnchantDump()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_PERMANENT)
    for _, slot in ipairs(KAGS.ENCHANTABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if not link then
            print(string.format("  slot %d: -", slot))
        else
            local enchant = link:match("item:%d+:(%d*):")
            local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            print(string.format("  slot %d: enchant=%s  [%s]  equipLoc=%s  %s",
                slot,
                (enchant and enchant ~= "" and enchant ~= "0") and enchant or "NONE",
                EnchantNameForSlot(slot) or "?",
                tostring(equipLoc),
                C_Item.GetItemInfo(link) or "?"))
        end
    end

    local hasMH, mhExp, _, mhID, hasOH, ohExp, _, ohID = GetWeaponEnchantInfo()
    print("|cff00ff00KART|r " .. KART.L.ENCH_DUMP_TEMPORARY)
    print(string.format("  main hand: has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasMH), tostring(mhID), tostring(mhExp), tostring(KAGS.SlotNeedsOil(16))))
    print(string.format("  off hand:  has=%s id=%s ms_left=%s needsOil=%s",
        tostring(hasOH), tostring(ohID), tostring(ohExp), tostring(KAGS.SlotNeedsOil(17))))
end

-- Answers to a raid scan, keyed by short name so a repeated reply replaces rather than double-counts.
KART.EnchantScan = KART.EnchantScan or {}

-- Asks every KART user in the group for their enchant ids and prints the tally a few seconds later.
--
-- READ THIS BEFORE USING THE OUTPUT: the tally shows what the raid WEARS, which is not the same as
-- what is CORRECT. Pasting it into GOOD_ENCHANTS (Libs/KAGS-1.0/KAGS-1.0.lua) would bless whatever
-- outdated enchant someone happens to have — the list would then approve exactly the case the
-- check is meant to catch. There is no in-game API that ranks an enchantID, so correctness can
-- only come from outside the game.
--
-- What it is actually good for is spotting outliers by eye: when eighteen people share an id on a
-- slot and one person has a different one, that one is worth a look. A human reads that; the code
-- must not.
function KART.StartEnchantScan()
    if not IsInGroup() then
        print("|cffff0000KART:|r " .. KART.L.ENCH_SCAN_NOT_IN_GROUP)
        return
    end
    wipe(KART.EnchantScan)
    -- Our own answer: KASC drops our own message when it comes back (see Dispatch).
    KART.EnchantScan[UnitName("player") or "?"] = KAGS.GetOwnEnchantIDs()
    KASC:Send("REQ_ENCH")
    print("|cff00ff00KART:|r " .. KART.L.ENCH_SCAN_START)
    C_Timer.After(5, KART.PrintEnchantScan)
end

function KART.PrintEnchantScan()
    local perSlot, responders = {}, 0
    for _, ids in pairs(KART.EnchantScan) do
        responders = responders + 1
        for slot, id in pairs(ids) do
            perSlot[slot] = perSlot[slot] or {}
            perSlot[slot][id] = (perSlot[slot][id] or 0) + 1
        end
    end

    print("|cff00ff00KART|r " .. string.format(KART.L.ENCH_SCAN_RESULT, responders))
    local order = {}
    for _, s in ipairs(KAGS.ENCHANTABLE_SLOTS) do order[#order + 1] = s end
    order[#order + 1] = "oil"
    for _, slot in ipairs(order) do
        local counts = perSlot[slot]
        if counts then
            local list = {}
            for id, n in pairs(counts) do list[#list + 1] = { id = id, n = n } end
            -- Most-used first, so the common enchants read as the accepted set and any one-off
            -- (the likely outdated one) sits at the end.
            table.sort(list, function(a, b)
                if a.n ~= b.n then return a.n > b.n end
                return a.id < b.id
            end)
            local parts = {}
            for _, e in ipairs(list) do parts[#parts + 1] = e.id .. " (x" .. e.n .. ")" end
            print(string.format("  %s: %s", tostring(slot), table.concat(parts, ", ")))
        end
    end
end

-- Keybind action list: shared between ApplyKeybinds and the settings-tab bind UI so both
-- stay in sync with a single source of truth for which 4 actions are bindable. Lives in
-- Utils.lua (rather than RaidleadBar.lua where ApplyKeybinds is defined) because it loads
-- before MainFrame.lua, which reads it at file-load time to build the keybind settings card.
KART.KeybindActions = {
    { key = "readyCheck", button = "KART_RL_ReadyCheckBtn" },
    { key = "clearWorldMarkers", button = "KART_RL_ClearWorldMarkersBtn" },
    { key = "pullTimer", button = "KART_RL_PullTimerBtn" },
    { key = "buffCheckToggle", button = "KART_RL_BuffCheckToggleBtn" },
}

-- Maps each of the 6 main-window tab-content panels to its ShowTab index. Used by
-- KART.BuildSearchIndex to figure out which tab a given label belongs to, by walking up the
-- label's parent chain until one of these panels is found.
local SEARCH_TAB_PANELS = {
    { panel = "PromotePanel", tabIndex = 1 },
    { panel = "RaidleadPanel", tabIndex = 2 },
    { panel = "BuffCheckPanel", tabIndex = 3 },
    { panel = "SettingsPanel", tabIndex = 4 },
    { panel = "WoWUtilsPanel", tabIndex = 5 },
    { panel = "CoTankPanel", tabIndex = 6 },
}

-- Builds the settings search index by walking KART.UI's label registry — every settings label
-- already gets registered there by its creation site (checkboxes, sliders, card titles, hints,
-- tab titles), so no per-widget registration is needed here. A label whose parent chain never
-- reaches one of the 6 main tab panels (e.g. one that belongs to a popup window like Loot
-- History) is silently skipped, which is how "only the 6 main tabs are searchable" enforces itself.
function KART.BuildSearchIndex()
    local index = {}
    for _, fs in ipairs(KART.UI:GetLabels()) do
        local text = fs:GetText()
        -- Skip hidden labels: a FontString keeps its text after :Hide(), so a conditionally-shown one
        -- (e.g. the council pending-resolution label) would stay searchable and its result row would
        -- scroll to and highlight an invisible, zero-content strip of the panel.
        if text and text ~= "" and fs:IsShown() then
            local ancestor = fs:GetParent()
            local tabIndex
            while ancestor and not tabIndex do
                for _, entry in ipairs(SEARCH_TAB_PANELS) do
                    if ancestor == KART[entry.panel] then
                        tabIndex = entry.tabIndex
                        break
                    end
                end
                ancestor = ancestor:GetParent()
            end
            if tabIndex then
                table.insert(index, { text = text, tabIndex = tabIndex, widget = fs })
            end
        end
    end
    return index
end
