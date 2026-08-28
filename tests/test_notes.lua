-- NSRT Notes: sequence, cursor, generation. Isolated load of Notes.lua.
-- Wrap LibStub so Notes.lua never registers onto run.lua's shared _G KASC
-- (RegisterMessage asserts on duplicate tokens).
local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
env._ntSent = {}
env._isLead = false
env.UnitIsGroupLeader = function() return env._isLead end
local KART = { L = {}, UI = { RegisterStaticPopup = function() end, CreateCard = function() return {} end } }
env.KART = KART
do
    local realLibStub = LibStub
    local kascStub = {
        RegisterMessage = function() end,
        Send = function(_, msg)
            env._ntSent[#env._ntSent + 1] = msg
        end,
        OnPeer = function() end,
        Identity = {
            GetNickname = function() return nil end,
            IsResolvedKey = function() return false end,
            FindUnitForKey = function() return nil end,
        },
    }
    env.LibStub = setmetatable({}, {
        __index = realLibStub,
        __call = function(_, name, silent)
            if name == "KASC-1.0" then return kascStub end
            return realLibStub(name, silent)
        end,
    })
end
do
    local chunk = assert(loadstring(assert(io.open("Notes.lua", "r"):read("*a")), "@Notes.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end
local NT = KART.NT

do
    local enc, diff, name = NT.ParseNoteHeader("EncounterID:3470;Name:Nekzali;Difficulty:Mythic\nline")
    T.eq(enc, 3470, "header encounter id")
    T.eq(diff, "Mythic", "header difficulty")
    T.eq(name, "Nekzali", "header name")
end

do
    local order = { 3470, 3445, 3497 }
    local skipped = { [3445] = true }
    T.eq(NT.NextAfter(order, skipped, 3470), 3497, "skip the skipped boss after a kill")
    T.eq(NT.NextAfter(order, skipped, 3497), nil, "last sendable does not wrap")
    T.eq(NT.NextAfter(order, {}, 3445), 3497, "out-of-order kill still advances from K")
end

do
    T.eq(NT.AcceptGeneration(3, 4), true, "higher generation wins")
    T.eq(NT.AcceptGeneration(4, 4), false, "equal generation does not flap")
    T.eq(NT.AcceptGeneration(5, 4), false, "lower generation is ignored")
    T.eq(NT.BumpGeneration(3, 5), 6, "bump is max(local, received)+1")
end

do
    T.eq(NT.Checksum("abc"), NT.Checksum("abc"), "stable checksum")
    T.eq(NT.Checksum("abc") == NT.Checksum("abd"), false, "different body different checksum")
end

do
    T.eq(NT.InstanceKey(1234, 16), "1234:16", "instance key is map+difficulty")
end

do
    T.eq(NT.MatchOperator("Wuusch", "Wuuschdk", "TarrenMill", "Wuusch"), true, "nickname matches")
    T.eq(NT.MatchOperator("Wuuschdk", "Wuuschdk", "TarrenMill", nil), true, "short name matches")
    T.eq(NT.MatchOperator("Wuuschdk-Tarren Mill", "Wuuschdk", "TarrenMill", nil), true, "realm-qualified matches canon")
    T.eq(NT.MatchOperator("Wuusch", "Alric", "TarrenMill", "Kandera"), false, "wrong nick does not match")
end

do
    local function S(over)
        local o = {
            moduleEnabled = true, isLead = true, operatorPresent = true,
            operatorAssist = true, operatorKart = true, checksumMatch = true, hasNote = true,
        }
        for k, v in pairs(over or {}) do o[k] = v end
        return NT.ChooseSender(o)
    end
    T.eq(S(), "operator", "operator preferred when present and fresh")
    T.eq(S({ operatorPresent = false }), "lead", "absent operator falls back to lead")
    T.eq(S({ operatorKart = false }), "lead", "no KART hello is absence")
    T.eq(S({ operatorAssist = false }), "lead", "operator without assist is not the sender")
    T.eq(S({ checksumMatch = false }), "lead", "stale note: lead sends")
    T.eq(S({ moduleEnabled = false }), nil, "disabled module sends nobody")
    T.eq(S({ hasNote = false }), nil, "no note: nobody sends")
    T.eq(S({ isLead = false, operatorPresent = false }), nil, "non-lead without operator does not send")
end

do
    T.eq(NT.ShouldEnqueueKill(1), true, "a kill enqueues")
    T.eq(NT.ShouldEnqueueKill(0), false, "a wipe does not enqueue")
    T.eq(NT.ShouldEnqueueKill(nil), false, "nil kill does not enqueue")
end

do
    T.eq(NT.ShouldEnqueueZone(nil, 1001, "raid", 16, true), true, "first raid zone-in enqueues")
    T.eq(NT.ShouldEnqueueZone(1001, 1001, "raid", 16, true), false, "same visit does not")
    T.eq(NT.ShouldEnqueueZone(1001, 1002, "raid", 16, true), true, "new instance id enqueues")
    T.eq(NT.ShouldEnqueueZone(nil, 1001, "raid", 16, false), false, "non-lead does not zone-enqueue")
    T.eq(NT.ShouldEnqueueZone(nil, 1001, "none", 16, true), false, "open world does not")
    T.eq(NT.ShouldEnqueueZone(nil, 1001, "raid", 1, true), false, "wrong difficulty does not")
end

do
    KARTTEST.aurasSecret = true
    T.eq(NT.AurasSecret(), true, "secret auras block share")
    KARTTEST.aurasSecret = false
    T.eq(NT.AurasSecret(), false, "clear auras allow share")
end

do
    T.eq(NT.HasNSRT(), false, "no NSRT")
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(self, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    T.eq(NT.HasNSRT(), true, "NSRT table is enough")
    local list = NT.ListSharedNotes("Mythic")
    T.eq(#list, 1, "one mythic note")
    T.eq(list[1].encID, 3470, "listed by encounter")
    T.eq(NT.Share("Boss1"), true, "share returns true")
    T.eq(env._shared[1], "NSI_REM_SHARE", "uses Reloe event not NSI_MSG")
    T.eq(NT.Share("Nope"), false, "missing name does not share")
end

do
    local s = { gen = 2, editor = "A-T", operator = "Wuusch", mapId = 1, diff = 16,
                cursor = 3470, checksum = "deadbeef", order = { 3470, 3445 }, skipped = { [3445] = true } }
    local round = NT.DecodeState(NT.EncodeState(s))
    T.eq(round.gen, 2, "gen roundtrips")
    T.eq(round.cursor, 3470, "cursor roundtrips")
    T.eq(round.skipped[3445], true, "skip roundtrips")
end

-- Event wiring: kill advances cursor and lead flushes; wipe / non-lead / zone visit.
do
    local function resetNT()
        env._ntSent = {}
        env._isLead = true
        NT.lastVisit = nil
        KARTTEST.aurasSecret = false
        env.KART_Settings = {
            ntModuleEnabled = true,
            ntOperatorName = "",
            ntMapId = 1,
            ntDiff = 16,
            ntCursor = 3470,
            ntLastVisit = 0,
            ntOrderByInstance = {
                ["1:16"] = { order = { 3470, 3497, 3445 }, skipped = { [3445] = true } },
            },
        }
    end

    resetNT()
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 0)
    T.eq(#env._ntSent, 0, "wipe does not flush")
    T.eq(env.KART_Settings.ntCursor, 3470, "wipe does not move cursor")

    resetNT()
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(env.KART_Settings.ntCursor, 3497, "kill advances cursor via NextAfter")
    T.eq(#env._ntSent, 1, "lead flushes after kill when auras clear")
    T.eq(env._ntSent[1], "NT_FLUSH:3497", "flush carries next encounter id")

    resetNT()
    env._isLead = false
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(env.KART_Settings.ntCursor, 3497, "non-lead still advances cursor")
    T.eq(#env._ntSent, 0, "non-lead does not emit NT_FLUSH on kill")

    resetNT()
    KARTTEST.aurasSecret = true
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(#env._ntSent, 0, "secret auras defer the flush")
    KARTTEST.aurasSecret = false
    KARTTEST.AdvanceTime(1.1)
    T.eq(#env._ntSent, 1, "flush fires once auras clear")
    T.eq(env._ntSent[1], "NT_FLUSH:3497", "deferred flush is the advanced cursor")

    resetNT()
    KARTTEST.instance.mapID = 9001
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(NT.lastVisit, 9001, "zone-in stores visit token")
    T.eq(env.KART_Settings.ntLastVisit, 9001, "zone-in persists visit on SV")
    T.eq(#env._ntSent, 1, "lead zone-in flushes current cursor")
    T.eq(env._ntSent[1], "NT_FLUSH:3470", "zone-in flushes existing cursor")
    env._ntSent = {}
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 0, "same visit does not flush again")

    resetNT()
    env.KART_Settings.ntCursor = 0
    KARTTEST.instance.mapID = 9002
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(env._ntSent[1], "NT_FLUSH:3470", "zone-in uses first sendable when cursor empty")

    resetNT()
    KARTTEST.instance.mapID = 9003
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 1, "first PEW enqueues")
    T.eq(env.KART_Settings.ntLastVisit, 9003, "visit persisted on SavedVariables")
    env._ntSent = {}
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 0, "same mapID again does not enqueue")
    -- Simulated reload: session cleared, SV still has ntLastVisit.
    env._ntSent = {}
    NT.lastVisit = nil
    T.eq(env.KART_Settings.ntLastVisit, 9003, "SV visit survives simulated reload")
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 0, "reload same visit does not enqueue")

    -- Hearth / leave then re-enter same map: new visit must share again.
    resetNT()
    KARTTEST.instance.mapID = 9004
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 1, "zone into raid enqueues once")
    env._ntSent = {}
    NT.lastVisit = nil
    T.eq(env.KART_Settings.ntLastVisit, 9004, "still inside: SV holds visit")
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 0, "reload inside same visit does not enqueue")
    -- Leave: open world (or wrong difficulty) clears the visit token.
    env._ntSent = {}
    KARTTEST.instance.instanceType = "none"
    KARTTEST.instance.difficultyID = 0
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(NT.lastVisit == nil or NT.lastVisit == 0, true, "leave clears session visit")
    T.eq(env.KART_Settings.ntLastVisit == nil or env.KART_Settings.ntLastVisit == 0, true,
        "leave clears SV visit")
    T.eq(#env._ntSent, 0, "leave itself does not enqueue")
    -- Re-enter same mapID as lead → new visit → share current cursor once.
    env._ntSent = {}
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    KARTTEST.instance.mapID = 9004
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 1, "hearth and re-enter same map enqueues again")
    T.eq(env._ntSent[1], "NT_FLUSH:3470", "re-enter shares current cursor")
end

-- SetOrder / SetSkipped bump generation and persist order (data, not drag).
do
    NT.EnsureShape(env.KART_Settings)
    local key = NT.InstanceKey(1, 16)
    env.KART_Settings.ntOrderByInstance[key] = { order = { 1, 2 }, skipped = {} }
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntGeneration = 0
    NT.generation = 0
    env._isLead = true
    local g1 = NT.BumpGeneration(0, 0)
    NT.SetOrder(key, { 2, 1 })
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[1], 2, "SetOrder stores the new order")
    T.eq(NT.LocalGeneration(), g1, "SetOrder bumps generation")
    local g2 = NT.LocalGeneration()
    NT.SetSkipped(key, 2, true)
    T.eq(env.KART_Settings.ntOrderByInstance[key].skipped[2], true, "SetSkipped records the skip")
    T.eq(NT.LocalGeneration() > g2, true, "SetSkipped bumps generation")
end

-- Injected EJ order is used as-is; encounter IDs are not numeric-sorted.
do
    NT._encountersForMap = function()
        return { { id = 3470, name = "Nekzali" }, { id = 100, name = "Low" }, { id = 9999, name = "High" } }
    end
    local order = NT.DefaultEncounterOrder()
    T.eq(order[1], 3470, "injected first encounter is first")
    T.eq(order[2], 100, "injected order is used, not numeric-sorted")
    T.eq(order[3], 9999, "injected last encounter stays last")
    NT._encountersForMap = nil
end

-- Share now queues while auras are secret; does not send into combat.
do
    env._isLead = true
    env._ntSent = {}
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntOperatorName = ""
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    KARTTEST.aurasSecret = true
    NT.ShareNow()
    T.eq(NT.statusLabel.text, "Waiting until combat ends.", "Share now queues while auras are secret")
    T.eq(#env._ntSent, 0, "Share now does not flush while secret")
    KARTTEST.aurasSecret = false
    KARTTEST.AdvanceTime(1.1)
    T.eq(#env._ntSent, 1, "queued Share now flushes once auras clear")
    T.eq(env._ntSent[1], "NT_FLUSH:3470", "queued flush is the cursor")
end

-- Operator in town: Share now uses the raid stand, not local open-world difficulty.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = true
    env._shared = nil
    env._ntSent = {}
    NT.pendingFlush = nil
    KARTTEST.aurasSecret = false
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntOperatorName = ""
    KART.L.NT_STATUS_NO_NOTE = "No shared note for this boss."
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    T.eq(NT.CurrentMapKey(), "1234:16", "town CurrentMapKey uses raid stand")
    NT.ShareNow()
    T.eq(NT.statusLabel.text == "No shared note for this boss.", false,
        "town Share now does not NO_NOTE for lack of local difficulty")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "town Share now reaches NSRT Share")
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
end

-- Operator in town while the in-instance lead is already waiting: queue, do not send.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = true
    env._shared = nil
    NT.pendingFlush = 3470
    KARTTEST.aurasSecret = false
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    NT.ShareNow()
    T.eq(NT.statusLabel.text, "Waiting until combat ends.", "town + pendingFlush queues")
    T.eq(env._shared, nil, "pendingFlush does not Share")
    NT.pendingFlush = nil
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
end

-- Operator in the group but not assist: print promote; non-lead does not silent-return.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = false
    env._shared = nil
    NT.pendingFlush = nil
    KARTTEST.aurasSecret = false
    KARTTEST.SetRaid({
        { name = "Wuuschdk", realm = "TarrenMill", assist = false, guid = "Player-1-WU" },
    })
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntOperatorName = "Wuuschdk"
    KART.L.NT_STATUS_PROMOTE = "Promote the note operator to assistant so they can share."
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    NT.ShareNow()
    T.eq(NT.statusLabel.text, "Promote the note operator to assistant so they can share.",
        "operator not assist prints promote")
    T.eq(env._shared, nil, "unpromoted operator does not Share")
    NT.pendingFlush = nil
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
end
