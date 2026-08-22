local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = { L = {} }
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("CoTank.lua", "r")):read("*a"), "@CoTank.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
    for _, name in ipairs({
        "PickCoTank", "ShouldShow", "BlankSnapshot", "FillLiveSnapshot",
        "FillTestSnapshot", "RowAlpha", "SafeTruthy", "Invented", "FormatHealthText",
        "IsSecret",
        "ApplySecureUnit", "OnRegenEnabled",
        "Enable", "Disable", "Refresh", "EnsureRow", "ApplyLayout", "Paint",
        "OnRoster", "OnInstance", "AuraEngineAvailable", "BuildStrips",
        "OnUnitEvent", "SyncRowUnitEvents", "ReadInRange",
        "HostPreview", "ReleasePreview",
        "IsTaunt", "PlayerSpecId", "FormatTauntMessage", "ShouldAnnounce",
        "Announce", "OnTauntCast", "Ask", "CreateAskMacro",
        "ShouldShowAskButton", "EnsureAskButton", "RefreshAskButton", "TauntIcon",
        "BarPass", "AbsorbFill", "HealAbsorbSpan", "SyncStripUnits",
    }) do
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
    KARTTEST.instance.instanceType = "none"
    env.KART_Settings.ct.locked = false
    T.eq(KART.CT.ShouldShow(), true, "unlock shows the row in town")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "pvp"
    env.KART_Settings.ct.locked = false
    T.eq(KART.CT.ShouldShow(), false, "unlock does not punch through a battleground")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "arena"
    env.KART_Settings.ct.locked = false
    T.eq(KART.CT.ShouldShow(), false, "unlock does not punch through an arena")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "none"
    env.KART_Settings.ct.onlyInInstance = false
    T.eq(KART.CT.ShouldShow(), true, "instance filter off shows a co-tank in town")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "pvp"
    env.KART_Settings.ct.onlyInInstance = false
    T.eq(KART.CT.ShouldShow(), false, "battleground stays hidden even with instance filter off")
end

do
    RaidTwoTanks()
    KARTTEST.instance.instanceType = "none"
    KART.CT.hosted = true
    T.eq(KART.CT.ShouldShow(), true, "settings preview shows in town")
    T.eq(KART.CT.Invented(), true, "and uses invented data")
    KART.CT.hosted = nil
end

do
    T.eq(KART.CT.FormatHealthText({ health = 40, healthMax = 100 }, { healthText = "deficit" }),
        "60", "deficit health text is missing health")
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

do
    local snap = KART.CT.BlankSnapshot({})
    T.eq(snap.inRange, true, "blank snapshot starts in range")
end

do
    local other = { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB",
                    role = "TANK", class = "PALADIN", classFile = "PALADIN",
                    health = 40000, healthMax = 50000, absorb = 2000, healAbsorb = 500 }
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
        other,
    })
    KARTTEST.activeUnit = "raid1"
    local snap = KART.CT.FillLiveSnapshot("raid2", KART.CT.BlankSnapshot({}))
    T.eq(snap.name, "Other", "live snapshot takes the co-tank name")
    T.eq(snap.health, 40000, "and their health")
    T.eq(snap.absorb, 2000, "and absorb")
    T.eq(snap.healAbsorb, 500, "and heal absorb")
end

do
    local other = { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB",
                    role = "TANK", class = "PALADIN", classFile = "PALADIN" }
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
        other,
    })
    KARTTEST.activeUnit = "raid1"
    KARTTEST.rangeSecret["raid2"] = true
    local snap = KART.CT.FillLiveSnapshot("raid2", KART.CT.BlankSnapshot({}))
    T.eq(snap.inRange, true, "unreadable range counts as in range")
    KARTTEST.rangeSecret["raid2"] = nil

    KARTTEST.range["raid2"] = false
    snap = KART.CT.FillLiveSnapshot("raid2", KART.CT.BlankSnapshot({}))
    T.eq(snap.inRange, false, "checked out-of-range fades")
    KARTTEST.rangeChecked["raid2"] = false
    snap = KART.CT.FillLiveSnapshot("raid2", KART.CT.BlankSnapshot({}))
    T.eq(snap.inRange, true, "unchecked range counts as in range")
    KARTTEST.range["raid2"] = nil
    KARTTEST.rangeChecked["raid2"] = nil
end

do
    local snap = KART.CT.FillTestSnapshot(KART.CT.BlankSnapshot({}))
    T.truthy(snap.name and snap.healthMax, "test snapshot invents a tank")
    T.eq(snap.dead, false, "who is alive")
end

do
    local ct = { rangeAlpha = 0.4 }
    local snap = { dead = false, offline = false, inRange = false }
    T.eq(KART.CT.RowAlpha(snap, ct), 0.4, "out of range uses rangeAlpha")
    snap.dead = true
    T.eq(KART.CT.RowAlpha(snap, ct), 0.35, "dead is darker than range fade")
    snap.dead = false
    ct.rangeFade = false
    T.eq(KART.CT.RowAlpha(snap, ct), 1, "range fade off keeps full alpha")
end

do
    local calls = {}
    local frame = { SetAttribute = function(_, k, v) calls[#calls + 1] = { k, v } end }
    KARTTEST.inCombat = true
    T.eq(KART.CT.ApplySecureUnit(frame, "raid2"), "deferred", "combat defers SetAttribute")
    T.eq(#calls, 0, "and does not write")
    T.eq(KART.CT.pendingUnit, "raid2", "pending remembers the unit")
    KARTTEST.inCombat = false
    KART.CT.row = frame
    KART.CT.OnRegenEnabled()
    T.eq(calls[1][1], "type1", "after combat type1 is set")
    T.eq(calls[1][2], "target", "to target")
    T.eq(calls[2][1], "unit", "after combat the unit attribute is set")
    T.eq(calls[2][2], "raid2", "to the pending token")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    env.KART_Settings.ctModuleEnabled = false
    KART.CT.Enable()
    T.is_nil(KART.CT.events, "disabled module creates no event frame")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    RaidTwoTanks()
    KART.CT.Enable()
    T.truthy(KART.CT.events, "enabled module creates an event frame")
    T.truthy(KART.CT.row and KART.CT.row:IsShown(), "refresh shows the row when visible")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    RaidTwoTanks()
    KART.CT.Enable()
    KART.CT.pendingUnit = "raid2"
    KART.CT.Disable()
    T.eq(KART.CT.row:IsShown(), false, "disable hides the row")
    T.is_nil(KART.CT.pendingUnit, "disable clears pending unit")
end

local function CountCtEvents(frame)
    local n = 0
    for _, reg in ipairs(KARTTEST.eventFrames) do
        if reg.frame == frame then n = n + 1 end
    end
    return n
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            width = 220, height = 36, scale = 1, locked = true, testMode = true,
            nameMaxLength = 12, healthText = "both", healthColor = "class",
            healthAlpha = 1, trackAlpha = 0.4, rangeAlpha = 0.4,
            absorbShow = true, healAbsorbShow = true,
        },
    }
    KART.CT.EnsureRow()
    KART.CT.ApplyLayout()
    T.eq(KART.CT.row:GetWidth(), 220, "layout uses ct.width")
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            width = 220, height = 36, scale = 1, locked = true, testMode = true,
            nameMaxLength = 12, healthText = "both", healthColor = "class",
            healthAlpha = 1, trackAlpha = 0.4, rangeAlpha = 0.4,
            absorbShow = true, healAbsorbShow = true,
        },
    }
    local row = KART.CT.EnsureRow()
    local snap = KART.CT.FillTestSnapshot(KART.CT.BlankSnapshot({}))
    KART.CT.Paint(snap)
    T.eq(row.nameText:GetText(), "Testtank", "paint sets truncated name")
    T.truthy(row.healthText:GetText():find("%%"), "paint health text includes percent when both")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    RaidTwoTanks()
    KART.CT.Enable()
    T.eq(CountCtEvents(KART.CT.events), 5, "first enable registers roster, instance, roles, target, and own casts")
    KART.CT.Disable()
    T.eq(CountCtEvents(KART.CT.events), 0, "disable unregisters all events")
    KART.CT.Enable()
    T.eq(CountCtEvents(KART.CT.events), 5, "second enable re-registers the same events")
end

do
    T.eq(KART.CT.AuraEngineAvailable(), false, "aura engine unavailable in harness")
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            testMode = true,
            debuffs = { show = true, max = 3, size = 20, spacing = 2,
                        anchor = "TOPLEFT", growth = "right", x = 0, y = 4 },
            buffs   = { show = true, max = 2, size = 16, spacing = 1,
                        anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4 },
        },
    }
    KART.CT.EnsureRow()
    KART.CT.BuildStrips(KART.CT.row)
    T.truthy(KART.CT.row.debuffs, "debuff strip exists")
    T.truthy(KART.CT.row.buffs, "buff strip exists")
    T.truthy(KART.CT.row.debuffs.dummyIcons and KART.CT.row.debuffs.dummyIcons[1],
        "dummy debuff icons when max >= 1")
    T.truthy(KART.CT.row.buffs.dummyIcons and KART.CT.row.buffs.dummyIcons[1],
        "dummy buff icons when max >= 1")
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            testMode = true,
            debuffs = { show = false, max = 3, size = 20, spacing = 2,
                        anchor = "TOPLEFT", growth = "right", x = 0, y = 4 },
            buffs   = { show = true, max = 2, size = 16, spacing = 1,
                        anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4 },
        },
    }
    KART.CT.EnsureRow()
    KART.CT.BuildStrips(KART.CT.row)
    T.truthy(KART.CT.row.debuffs, "hidden debuff strip still exists")
    T.eq(KART.CT.row.debuffs:IsShown(), false, "show false hides debuff strip")
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            testMode = true,
            width = 220, height = 36,
            debuffs = { show = true, max = 2, size = 18, spacing = 1,
                        anchor = "TOPLEFT", growth = "right", x = 0, y = 4 },
            buffs   = { show = true, max = 2, size = 18, spacing = 1,
                        anchor = "BOTTOMRIGHT", growth = "left", x = 0, y = -4 },
        },
    }
    KARTTEST.inCombat = false
    KART.CT.EnsureRow()
    KART.CT.ApplyLayout()
    T.truthy(KART.CT.row.debuffs, "apply layout builds debuff strip OOC")
    T.truthy(KART.CT.row.buffs, "apply layout builds buff strip OOC")
end

do
    local core = assert(io.open("Core.lua", "r")):read("*a")
    T.truthy(core:find("KART.CT.SyncWidgets", 1, true), "Core.lua calls CT.SyncWidgets")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    local other = { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB",
                    role = "TANK", class = "PALADIN", classFile = "PALADIN",
                    health = 40000, healthMax = 50000 }
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
        other,
    })
    KARTTEST.activeUnit = "raid1"
    KARTTEST.instance = { name = "Somewhere", instanceType = "party", difficultyID = 1, difficultyName = "Normal" }
    env.KART_Settings = { ctModuleEnabled = true, ct = { testMode = false } }
    KART.CT.Enable()
    T.eq(KART.CT.snap.health, 40000, "refresh seeds live health")
    T.eq(CountCtEvents(KART.CT.row), 6, "row listens to six unit events including range")
    other.health = 12000
    KART.CT.OnUnitEvent("UNIT_HEALTH", "raid2")
    T.eq(KART.CT.snap.health, 12000, "unit health event repaints live health")
    KARTTEST.range["raid2"] = false
    KART.CT.OnUnitEvent("UNIT_IN_RANGE_UPDATE", "raid2")
    T.eq(KART.CT.snap.inRange, false, "range event paints out of range")
    T.eq(KART.CT.row:GetAlpha(), 0.4, "and fades the row")
    KARTTEST.range["raid2"] = nil
    KARTTEST.instance = { name = "Town", instanceType = "none", difficultyID = 0, difficultyName = "" }
    KART.CT.Refresh()
    T.eq(KART.CT.row:IsShown(), false, "leaving the instance hides the row")
    T.eq(CountCtEvents(KART.CT.row), 0, "and drops unit events including range")
end

do
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = {
            width = 220, height = 36, scale = 1, locked = true, testMode = true,
            nameMaxLength = 12, healthText = "both", healthColor = "class",
            healthAlpha = 1, trackAlpha = 0.4, rangeAlpha = 0.4,
            absorbShow = true, healAbsorbShow = true,
        },
    }
    KARTTEST.inCombat = false
    KART.CT.EnsureRow()
    KART.CT.ApplyLayout()
    T.eq(KART.CT.row:GetWidth(), 220, "layout width before combat")
    KARTTEST.inCombat = true
    env.KART_Settings.ct.width = 300
    KART.CT.ApplyLayout()
    T.eq(KART.CT.row:GetWidth(), 220, "combat blocks ApplyLayout resize")
    KARTTEST.inCombat = false
end

do
    local secret = {}
    KARTTEST.secretValues[secret] = true
    KART.CT.row = nil
    env.KART_Settings = {
        ctModuleEnabled = true,
        ct = { testMode = true, healthText = "both", healthColor = "health" },
    }
    KART.CT.EnsureRow()
    local snap = KART.CT.BlankSnapshot({})
    snap.name = "Zuridk"
    snap.classFile = "DEATHKNIGHT"
    snap.health = secret
    snap.healthMax = secret
    snap.absorb = secret
    snap.healAbsorb = secret
    KART.CT.Paint(snap)
    T.eq(KART.CT.FormatHealthText(snap, { healthText = "both" }), "",
        "secret health is not formatted")
    KARTTEST.secretValues[secret] = nil
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    RaidTwoTanks()
    KART.CT.Enable()
    T.eq(KART.CT.row:IsShown(), true, "row shown in dungeon")
    KARTTEST.inCombat = true
    KARTTEST.instance.instanceType = "none"
    KART.CT.Refresh()
    T.eq(KART.CT.row:IsShown(), true, "combat defers Hide on the secure row")
    KARTTEST.inCombat = false
    KART.CT.OnRegenEnabled()
    T.eq(KART.CT.row:IsShown(), false, "row hides after combat")
end

-- ===== Taunt announce / ask ===========================================================
local function TauntReady(extra)
    RaidTwoTanks()
    env.KART_Settings.ct.taunt = extra or {
        announce = true,
        channels = { WHISPER = true },
        message = "Taunt: %t",
        ask = "%n, please taunt!",
        onlyInGroup = true,
        onlyInInstance = true,
        button = true,
    }
    KARTTEST.target = { name = "Boss", realm = KARTTEST.realm }
    KARTTEST.ClearChat()
    KARTTEST.ClearMacros()
    KART.CT.lastTauntAt = nil
    KARTTEST.specId = 71
end

do
    T.eq(KART.CT.IsTaunt(355), true, "Warrior Taunt is a taunt")
    T.eq(KART.CT.IsTaunt(133), false, "Fireball is not")
    KARTTEST.specId = 250
    T.eq(KART.CT.IsTaunt(49576), true, "Death Grip is a taunt for Blood")
    KARTTEST.specId = 251
    T.eq(KART.CT.IsTaunt(49576), false, "and not for Frost")
    KARTTEST.specId = 71
end

do
    T.eq(KART.CT.FormatTauntMessage("Taunt: %t", { t = "Boss", s = "Taunt", n = "Other" }),
        "Taunt: Boss", "%t is what you taunted")
    T.eq(KART.CT.FormatTauntMessage("%n, please taunt!", { t = "Boss", s = "Taunt", n = "Other" }),
        "Other, please taunt!", "%n is the other tank")
    T.eq(KART.CT.FormatTauntMessage("%s on %t", { t = "Boss", s = "Taunt", n = "Other" }),
        "Taunt on Boss", "%s is the spell name")
end

do
    TauntReady()
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 1, "a taunt whispers once")
    T.eq(KARTTEST.chat[1].channel, "WHISPER", "on whisper")
    T.eq(KARTTEST.chat[1].target, "Other", "to the co-tank")
    T.eq(KARTTEST.chat[1].msg, "Taunt: Boss", "with the template filled")
end

do
    TauntReady({ announce = true, channels = { GROUP = true },
        message = "Taunt: %t", onlyInGroup = true, onlyInInstance = true })
    KART.CT.OnTauntCast(355)
    T.eq(KARTTEST.chat[1].channel, "RAID", "party-or-raid in a raid is RAID")
end

do
    TauntReady({ announce = true, channels = { GROUP = true },
        message = "Taunt: %t", onlyInGroup = true, onlyInInstance = true })
    KARTTEST.SetGroupIsRaid(false)
    KART.CT.OnTauntCast(355)
    T.eq(KARTTEST.chat[1].channel, "PARTY", "party-or-raid in a party is PARTY")
end

do
    TauntReady()
    env.KART_Settings.ctModuleEnabled = false
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 0, "module off never announces")
end

do
    TauntReady({ announce = false, channels = { WHISPER = true },
        message = "Taunt: %t", onlyInGroup = true, onlyInInstance = true })
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 0, "announce off never announces")
end

do
    TauntReady()
    KARTTEST.instance.instanceType = "none"
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 0, "open world does not announce when instance filter is on")
end

do
    TauntReady()
    KART.CT.OnTauntCast(355)
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 1, "a double-cast is debounced")
    KARTTEST.now = KARTTEST.now + 2
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 2, "and announces again after the debounce")
end

do
    TauntReady()
    KART.CT.Ask()
    T.eq(#KARTTEST.chat, 1, "Ask sends the ask line")
    T.eq(KARTTEST.chat[1].msg, "Other, please taunt!", "with the ask template")
    T.eq(KARTTEST.chat[1].channel, "WHISPER", "on the same channels as announce")
    T.eq(KARTTEST.chat[1].target, "Other", "to the co-tank")
end

do
    TauntReady()
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
    })
    KARTTEST.activeUnit = "raid1"
    KART.CT.Ask()
    T.eq(#KARTTEST.chat, 0, "Ask is a no-op without a co-tank")
end

do
    TauntReady()
    KARTTEST.inCombat = true
    T.eq(KART.CT.CreateAskMacro(), "combat", "combat refuses a new macro")
    T.eq(#KARTTEST.macroCalls, 0, "and does not call CreateMacro")
    KARTTEST.inCombat = false
    T.eq(KART.CT.CreateAskMacro(), "created", "out of combat writes the macro")
    T.eq(KARTTEST.macros[1].name, "KART Ask Taunt", "under a 16-char name")
    T.truthy(KARTTEST.macros[1].body:find("KART.CT.Ask", 1, true), "body calls Ask")
end

do
    TauntReady()
    T.eq(KART.CT.ShouldShowAskButton(), true, "ask button shows in a dungeon with a co-tank")
    env.KART_Settings.ct.taunt.button = false
    T.eq(KART.CT.ShouldShowAskButton(), false, "and hides when the button is off")
end

do
    TauntReady({ button = true, buttonOnlyInRaid = true,
        announce = false, channels = { WHISPER = true } })
    KARTTEST.SetGroupIsRaid(false)
    T.eq(KART.CT.ShouldShowAskButton(), false, "only-in-raid hides the button in a 5-man")
end

do
    TauntReady()
    local secret = {}
    KARTTEST.secretValues[secret] = true
    KARTTEST.target = { name = secret, realm = KARTTEST.realm }
    KART.CT.OnTauntCast(355)
    T.eq(KARTTEST.chat[1].msg, "Taunt: ", "secret target name is omitted from the line")
    KARTTEST.ClearChat()
    KART.CT.lastTauntAt = nil
    KART.CT.OnTauntCast(secret)
    T.eq(#KARTTEST.chat, 0, "secret spell id is not announced")
    KARTTEST.secretValues[secret] = nil
end

do
    TauntReady({ button = true, locked = false, announce = false,
        channels = { WHISPER = true } })
    env.KART_Settings.ct.taunt.locked = false
    KARTTEST.instance.instanceType = "arena"
    T.eq(KART.CT.ShouldShowAskButton(), false, "unlock does not show the ask button in an arena")
end

do
    TauntReady({ announce = true, channels = { RAID_WARNING = true },
        message = "Taunt: %t", onlyInGroup = true, onlyInInstance = true })
    KART.CT.OnTauntCast(355)
    T.eq(#KARTTEST.chat, 0, "raid warning is skipped without lead or assist")
end

do
    TauntReady({ announce = true, channels = { RAID_WARNING = true },
        message = "Taunt: %t", onlyInGroup = true, onlyInInstance = true })
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK",
          class = "WARRIOR", classFile = "WARRIOR", leader = true },
        { name = "Other", realm = KARTTEST.realm, guid = "Player-1-BBBB", role = "TANK",
          class = "PALADIN", classFile = "PALADIN" },
    })
    KARTTEST.activeUnit = "raid1"
    KARTTEST.target = { name = "Boss", realm = KARTTEST.realm }
    KART.CT.OnTauntCast(355)
    T.eq(KARTTEST.chat[1].channel, "RAID_WARNING", "raid lead can send raid warning")
end

do
    local secret = {}
    KARTTEST.secretValues[secret] = true
    T.eq(KART.CT.BarPass(secret), secret, "BarPass leaves a secret value alone")
    T.eq(KART.CT.BarPass(nil), 0, "and nil becomes 0")
    T.eq(KART.CT.BarPass(40), 40, "and a real number passes through")
    T.eq(KART.CT.AbsorbFill(40000, 3000, 50000), 43000, "absorb fill is health plus absorb")
    T.eq(KART.CT.AbsorbFill(40000, 20000, 50000), 50000, "and clamps to max")
    local start, shown = KART.CT.HealAbsorbSpan(40000, 500, 50000)
    T.eq(start, 39500, "heal absorb starts inside current health")
    T.eq(shown, 500, "and is the absorb amount")
    T.eq(KART.CT.AbsorbFill(secret, 3000, 50000), nil, "secret health skips the overlay number")
    KARTTEST.secretValues[secret] = nil
end

do
    RaidTwoTanks()
    env.KART_Settings.ct.testMode = false
    KART.CT.hosted = nil
    KART.CT.row = nil
    KART.CT.EnsureRow()
    KART.CT.BuildStrips(KART.CT.row)
    local dummy = KART.CT.row.debuffs and KART.CT.row.debuffs.dummyIcons
    T.eq(dummy and dummy[1] or nil, nil, "live row without AuraContainer does not invent dummy icons")
end

do
    KART.CT.events = nil
    KART.CT.row = nil
    KART.CT.hosted = nil
    KART.CT.pendingHost = nil
    KART.CT.pendingRelease = nil
    RaidTwoTanks()
    KART.CT.Enable()
    T.eq(KART.CT.snap.name, "Other", "live row shows the co-tank")
    KARTTEST.inCombat = true
    KART.CT.HostPreview()
    T.eq(KART.CT.hosted, nil, "combat does not mark the world row as hosted")
    T.eq(KART.CT.pendingHost, true, "and remembers to host after combat")
    T.eq(KART.CT.Invented(), false, "so Invented stays off")
    T.eq(KART.CT.snap.name, "Other", "and the live name is not replaced with Testtank")
    KARTTEST.inCombat = false
    KART.CT.OnRegenEnabled()
    T.eq(KART.CT.hosted, true, "regen hosts the preview")
    KART.CT.ReleasePreview()
    KART.CT.hosted = nil
end

do
    KART.CT.row = nil
    KART.CT.hosted = nil
    KART.CT.pendingHost = nil
    KART.CT.pendingRelease = nil
    RaidTwoTanks()
    local slot = CreateFrame("Frame", "KARTTEST_CtSlot", UIParent)
    KART.CtPreviewSlot = slot
    KART.CT.HostPreview()
    T.eq(KART.CT.row:GetParent(), slot, "preview reparents into the slot")
    KARTTEST.inCombat = true
    env.KART_Settings.ctModuleEnabled = false
    KART.CT.Disable()
    T.eq(KART.CT.row:GetParent(), slot, "combat disable leaves the parent")
    KARTTEST.inCombat = false
    KART.CT.OnRegenEnabled()
    T.eq(KART.CT.row:GetParent(), UIParent, "regen puts the row back on UIParent")
    KART.CtPreviewSlot = nil
end

do
    RaidTwoTanks()
    KART.CT.hosted = true
    KART.CT.pendingHost = nil
    KART.CT.pendingRelease = nil
    KARTTEST.inCombat = true
    KART.CT.ReleasePreview()
    KART.CT.HostPreview()
    T.eq(KART.CT.pendingHost, true, "open after close in combat wants host")
    T.eq(KART.CT.pendingRelease, nil, "and does not keep a stale release")
    KARTTEST.inCombat = false
    KART.CT.hosted = nil
    KART.CT.pendingHost = nil
end

do
    RaidTwoTanks()
    env.KART_Settings.ct.locked = false
    KARTTEST.instance.instanceType = "none"
    KARTTEST.SetRaid({
        { name = "Me", realm = KARTTEST.realm, guid = "Player-1-AAAA", role = "TANK",
          class = "WARRIOR", classFile = "WARRIOR" },
    })
    KARTTEST.activeUnit = "raid1"
    KART.CT.watchedUnit = nil
    KART.CT.snap = {}
    KART.CT.OnUnitEvent("UNIT_HEALTH")
    T.eq(KART.CT.snap.name, "No tanks in the group", "no co-tank does not paint the player as the row")
end

do
    local utils = assert(io.open("Utils.lua", "r")):read("*a")
    T.truthy(utils:find("taunt = {", 1, true), "ct defaults include a taunt blob")
    T.truthy(utils:find("schemaVersion = 1", 1, true), "schemaVersion stays 1")
end

do
    local utils = assert(io.open("Utils.lua", "r")):read("*a")
    T.truthy(utils:find("taunt = {", 1, true), "ct defaults include a taunt blob")
    T.truthy(utils:find("schemaVersion = 1", 1, true), "schemaVersion stays 1")
end
