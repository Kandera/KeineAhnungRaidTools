-- NSRT Notes: sequence, cursor, generation. Isolated load of Notes.lua.
-- Wrap LibStub so Notes.lua never registers onto run.lua's shared _G KASC
-- (RegisterMessage asserts on duplicate tokens).
local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
env._ntSent = {}
env._ntHandlers = {}
env._isLead = false
env.UnitIsGroupLeader = function() return env._isLead end
local KART = { L = {}, UI = { RegisterStaticPopup = function() end, CreateCard = function() return {} end } }
KART.SenderIsGroupLeader = function(ctx) return ctx and ctx.lead == true end
env.KART = KART
do
    local realLibStub = LibStub
    local kascStub = {
        RegisterMessage = function(_, token, _, fn)
            env._ntHandlers[token] = fn
        end,
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
    T.eq(NT.DisplayBossName("Nek'zali the Soulcaller", "Heroic"),
        "Nek'zali the Soulcaller - Heroic", "EJ names get the list difficulty")
    T.eq(NT.DisplayBossName("Nymrissa - Heroic", "Heroic"),
        "Nymrissa - Heroic", "an imported name that already has the difficulty is not doubled")
    T.eq(NT.DisplayBossName("Nymrissa - Mythic", "Heroic"),
        "Nymrissa - Heroic", "a leftover suffix is replaced with the list difficulty")
    T.eq(NT.DisplayBossName("Sszorak", nil), "Sszorak", "no difficulty leaves the name alone")
end

do
    KART.WU = {
        bosses = { { encounterID = 3470, difficulty = "Mythic", players = { "A", "B" } } },
        IndexForEncounter = function(enc, diff)
            if enc == 3470 and diff == "Mythic" then return 1 end
            return nil
        end,
    }
    T.eq(NT.WuPlayersFor(3470, "Mythic"), 2, "row count uses the WU list")
    T.eq(select(2, NT.WuPlayersFor(3470, "Mythic")), 1, "and returns the WU index")
    T.eq(NT.WuPlayersFor(3470, "Heroic"), 0, "a missing difficulty is count 0")
    KART.WU = nil
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

do
    local s = { gen = 2, editor = "A-T", operator = "Wuusch\t16", mapId = 1, diff = 16,
                cursor = 3470, checksum = "deadbeef", order = { 3470 }, skipped = {} }
    local round = NT.DecodeState(NT.EncodeState(s))
    T.eq(round and round.operator, "Wuusch16", "tab in the operator is stripped on the wire")
    T.eq(round and round.diff, 16, "tab in the operator does not steal the next NT_STATE field")
    T.eq(round and round.mapId, 1, "mapId stays in its own field")
end

-- Event wiring: kill advances cursor and lead flushes; wipe / non-lead / zone visit.
do
    local function seedNSRT()
        env.NorthernSkyRaidTools = {
            SetReminder = function() end,
            Broadcast = function(_, ev, ch, body)
                env._shared = { ev, ch, body }
            end,
        }
        env.NSRT = { Reminders = {
            Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
            Boss2 = "EncounterID:3497;Name:Next;Difficulty:Mythic\ncd",
            Boss3 = "EncounterID:3445;Name:Skipped;Difficulty:Mythic\ncd",
        }}
    end

    local function resetNT()
        env._ntSent = {}
        env._shared = nil
        env._isLead = true
        NT.lastVisit = nil
        KARTTEST.aurasSecret = false
        KARTTEST.instance.mapID = 1
        KARTTEST.instance.instanceType = "raid"
        KARTTEST.instance.difficultyID = 16
        NT._stateRequested = nil
        NT._lastLeadPayload = nil
        NT.leadInRaid = nil
        NT.leadRestricted = nil
        NT._shareQueued = nil
        NT._queueShareCursor = nil
        seedNSRT()
        NT._encountersForMap = function()
            return {
                { id = 3470, name = "Nekzali" },
                { id = 3497, name = "Next" },
                { id = 3445, name = "Skipped" },
            }
        end
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

    local function flushSent()
        local n, last = 0, nil
        for _, m in ipairs(env._ntSent) do
            if type(m) == "string" and m:sub(1, 9) == "NT_FLUSH:" then
                n = n + 1
                last = m
            end
        end
        return n, last
    end

    local function stateSent()
        for _, m in ipairs(env._ntSent) do
            if type(m) == "string" and m:sub(1, 9) == "NT_STATE:" then
                return m
            end
        end
        return nil
    end

    resetNT()
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 0)
    T.eq(#env._ntSent, 0, "wipe does not flush")
    T.eq(env.KART_Settings.ntCursor, 3470, "wipe does not move cursor")
    T.eq(env._shared, nil, "wipe does not Load & Send")

    resetNT()
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(env.KART_Settings.ntCursor, 3497, "kill advances cursor via NextAfter")
    local nFlush, lastFlush = flushSent()
    T.eq(nFlush, 1, "lead flushes after kill when auras clear")
    T.eq(lastFlush, "NT_FLUSH:3497", "flush carries next encounter id")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "kill Load & Sends via NSRT")
    T.eq(env._shared and env._shared[3]:find("3497", 1, true) ~= nil, true, "kill shares the next note")

    resetNT()
    env._isLead = false
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(env.KART_Settings.ntCursor, 3497, "non-lead still advances cursor")
    T.eq(#env._ntSent, 0, "non-lead does not emit NT_FLUSH on kill")
    T.eq(env._shared, nil, "non-lead kill does not Load & Send")

    resetNT()
    KARTTEST.aurasSecret = true
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(flushSent(), 0, "secret auras defer the flush")
    T.truthy(stateSent() and stateSent():find("\t1\t16\t", 1, true),
        "kill publishes stand while Restricted so the operator has map/diff")
    T.eq(env._shared, nil, "secret auras do not Load & Send yet")
    KARTTEST.aurasSecret = false
    KARTTEST.AdvanceTime(1.1)
    nFlush, lastFlush = flushSent()
    T.eq(nFlush, 1, "flush fires once auras clear")
    T.eq(lastFlush, "NT_FLUSH:3497", "deferred flush is the advanced cursor")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "deferred flush Load & Sends")

    resetNT()
    KARTTEST.instance.mapID = 9001
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(NT.lastVisit, 9001, "zone-in stores visit token")
    T.eq(env.KART_Settings.ntLastVisit, 9001, "zone-in persists visit on SV")
    nFlush, lastFlush = flushSent()
    T.eq(nFlush, 1, "lead zone-in flushes current cursor")
    T.eq(lastFlush, "NT_FLUSH:3470", "zone-in flushes existing cursor")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "zone-in Load & Sends via NSRT")
    env._ntSent = {}
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(#env._ntSent, 0, "same visit does not flush again")

    resetNT()
    env.KART_Settings.ntCursor = 0
    KARTTEST.instance.mapID = 9002
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    lastFlush = select(2, flushSent())
    T.eq(lastFlush, "NT_FLUSH:3470", "zone-in uses first sendable when cursor empty")

    resetNT()
    KARTTEST.instance.mapID = 9003
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    nFlush = flushSent()
    T.eq(nFlush, 1, "first PEW enqueues")
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
    nFlush = flushSent()
    T.eq(nFlush, 1, "zone into raid enqueues once")
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
    T.eq(flushSent(), 0, "leave itself does not flush")
    -- Re-enter same mapID as lead → new visit → share current cursor once.
    env._ntSent = {}
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    KARTTEST.instance.mapID = 9004
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    nFlush, lastFlush = flushSent()
    T.eq(nFlush, 1, "hearth and re-enter same map enqueues again")
    T.eq(lastFlush, "NT_FLUSH:3470", "re-enter shares current cursor")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "re-enter Load & Sends")

    -- First raid night: empty SV, unprimed map. Stamp the live stand and share boss 1.
    resetNT()
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "",
        ntMapId = 0,
        ntDiff = 0,
        ntCursor = 0,
        ntLastVisit = 0,
        ntOrderByInstance = {},
    }
    env._shared = nil
    KARTTEST.instance.mapID = 2805
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(env.KART_Settings.ntMapId, 2805, "zone-in stamps live map onto the stand")
    T.eq(env.KART_Settings.ntDiff, 16, "zone-in stamps live difficulty onto the stand")
    T.eq(env.KART_Settings.ntCursor, 3470, "empty SV shares the first sendable")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "first raid night Load & Sends")
    T.eq(env.KART_Settings.ntLastVisit, 2805, "visit is written after a cursor was resolved")
    T.truthy(stateSent() and stateSent():find("\t2805\t16\t", 1, true),
        "zone-in publishes stamped stand so a town operator can RaidMapDiff")
    T.eq((env.KART_Settings.ntGeneration or 0) > 0, true, "zone-in bumps generation")

    -- Lead is not the sender: still publish stand so the town operator can Share.
    resetNT()
    local opRoster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Bramor", realm = "TarrenMill", guid = "Player-1-BR" },
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
    })
    KART.PlayerVersions = { Alric = "3.3.1" }
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 0,
        ntDiff = 0,
        ntCursor = 0,
        ntLastVisit = 0,
        ntGeneration = 0,
        ntOrderByInstance = {},
    }
    env._shared = nil
    env._ntSent = {}
    NT.generation = 0
    KARTTEST.instance.mapID = 2805
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(env.KART_Settings.ntMapId, 2805, "lead still stamps live map when operator will send")
    T.eq(env._shared, nil, "lead does not Share when operator is the chosen sender")
    T.truthy(stateSent() and stateSent():find("\t2805\t16\t", 1, true),
        "zone-in publishes stand even when the lead is not the sender")
    nFlush = flushSent()
    T.eq(nFlush, 1, "lead still flushes so the operator receives NT_FLUSH")
    KART.PlayerVersions = nil
    KARTTEST.RestoreRoster(opRoster)

    -- After boss 1, published checksum must be the next cursor note, not the last sent one.
    resetNT()
    local sumRoster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Bramor", realm = "TarrenMill", guid = "Player-1-BR" },
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
    })
    KART.PlayerVersions = { Alric = "3.3.1" }
    env.KART_Settings.ntOperatorName = "Alric"
    env.KART_Settings.ntChecksum = NT.CursorChecksum(NT.NoteNameForEncounter(3470, "Mythic"))
    env._shared = nil
    env._ntSent = {}
    NT.OnEvent("ENCOUNTER_END", 3470, "Boss", 16, 20, 1)
    T.eq(env._shared, nil, "kill with chosen operator: lead does not Share")
    local nextName = NT.NoteNameForEncounter(3497, "Mythic")
    T.eq(env.KART_Settings.ntChecksum, NT.CursorChecksum(nextName),
        "kill checksum is the next cursor note, not the last sent one")
    KART.PlayerVersions = nil
    KARTTEST.RestoreRoster(sumRoster)

    -- Module off on leave still clears the visit token (frame gate).
    resetNT()
    KARTTEST.instance.mapID = 9007
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(env.KART_Settings.ntLastVisit, 9007, "visit stored before module-off leave")
    env.KART_Settings.ntModuleEnabled = false
    env._ntSent = {}
    env._shared = nil
    KARTTEST.instance.instanceType = "none"
    KARTTEST.instance.difficultyID = 0
    NT._eventFrame:GetScript("OnEvent")(NT._eventFrame, "PLAYER_ENTERING_WORLD")
    T.eq(NT.lastVisit == nil or NT.lastVisit == 0, true, "module-off leave clears session visit")
    T.eq(env.KART_Settings.ntLastVisit == nil or env.KART_Settings.ntLastVisit == 0, true,
        "module-off leave clears SV visit")
    T.eq(env._shared, nil, "module-off leave does not Share")

    -- No sendable cursor: do not consume the visit token.
    resetNT()
    NT._encountersForMap = function() return {} end
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "",
        ntMapId = 0,
        ntDiff = 0,
        ntCursor = 0,
        ntLastVisit = 0,
        ntOrderByInstance = {},
    }
    env.NSRT = { Reminders = {} }
    env._shared = nil
    KARTTEST.instance.mapID = 2806
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    T.eq(env.KART_Settings.ntLastVisit == nil or env.KART_Settings.ntLastVisit == 0, true,
        "no cursor means visit is not consumed")
    T.eq(env._shared, nil, "no sendable note means no Load & Send")
    NT._encountersForMap = nil
    seedNSRT()
end

-- ALERT NT_FLUSH can overtake NORMAL NT_STATE. Operator in town has no stand until STATE lands.
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
    NT.generation = 0
    KARTTEST.aurasSecret = false
    KARTTEST.SetParty({
        { name = "Bramor", realm = "TarrenMill", guid = "Player-1-BR" },
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
    })
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 0,
        ntDiff = 0,
        ntCursor = 0,
        ntGeneration = 0,
        ntChecksum = "",
        ntOrderByInstance = {},
    }
    NT.ApplyFlushAndShare(3470)
    T.eq(env._shared, nil, "FLUSH before stand does not Load & Send")
    T.eq(NT.pendingFlush, 3470, "FLUSH before stand keeps pendingFlush")
    T.eq(NT.ApplyRemoteState(env.KART_Settings, {
        gen = 2,
        editor = "Bramor",
        operator = "Alric",
        mapId = 1,
        diff = 16,
        cursor = 3470,
        checksum = "",
        order = { 3470 },
        skipped = {},
    }), true, "operator applies lead stand")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE",
        "ApplyRemoteState retries pendingFlush so overtaken STATE still Shares")
    NT.pendingFlush = nil
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    env._isLead = true
end

-- Town Infer looks like a notes-valid raid (mixed Mythic+Heroic library, tie → Mythic).
-- FLUSH must not Share that guess, or STATE's Heroic stand arrives with pendingFlush already gone.
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
    NT.generation = 0
    KARTTEST.aurasSecret = false
    KARTTEST.SetParty({
        { name = "Bramor", realm = "TarrenMill", guid = "Player-1-BR" },
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
    })
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        BossM = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\nmythic note",
        BossH = "EncounterID:3470;Name:Nekzali;Difficulty:Heroic\nheroic note",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 0,
        ntDiff = 0,
        ntCursor = 0,
        ntGeneration = 0,
        ntChecksum = "",
        ntOrderByInstance = {},
    }
    env.EJ_GetNumTiers = function() return 2 end
    env.EJ_SelectTier = function() end
    env.EJ_SelectInstance = function() end
    env.EJ_GetInstanceByIndex = function(idx, isRaid)
        if not isRaid then return nil end
        if idx == 1 then return 1 end
        if idx == 2 then return 77 end
        return nil
    end
    env.EJ_GetInstanceInfo = function(journalId)
        if journalId == 77 then
            return "Voidspire", nil, nil, nil, nil, nil, nil, nil, nil, 2805
        end
        if journalId == 1 then
            return "World Bosses", nil, nil, nil, nil, nil, nil, nil, nil, 0
        end
    end
    env.EJ_GetEncounterInfoByIndex = function(i, journalId)
        if journalId == 77 and i == 1 then return "Nekzali", nil, nil, nil, nil, nil, 3470 end
        return nil
    end
    env.EJ_GetInstanceForMap = function(mapId)
        if mapId == 2805 then return 77 end
        return nil
    end
    NT._encountersForMap = nil
    local infMap, infDiff = NT.RaidMapDiff()
    T.eq(infMap, 2805, "mixed library still infers a raid map")
    T.eq(infDiff, 16, "tie infers Mythic")
    T.eq(env.KART_Settings.ntMapId, 0, "inference still does not stamp the stand")
    NT.ApplyFlushAndShare(3470)
    T.eq(env._shared, nil, "FLUSH + Infer does not Load & Send the guessed difficulty")
    T.eq(NT.pendingFlush, 3470, "FLUSH + Infer keeps pendingFlush until a published stand")
    T.eq(NT.ApplyRemoteState(env.KART_Settings, {
        gen = 2,
        editor = "Bramor",
        operator = "Alric",
        mapId = 2805,
        diff = 15,
        cursor = 3470,
        checksum = "",
        order = { 3470 },
        skipped = {},
    }), true, "operator applies the lead's Heroic stand")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE",
        "ApplyRemoteState retries pendingFlush after the published stand")
    T.eq(type(env._shared and env._shared[3]) == "string" and env._shared[3]:find("Difficulty:Heroic", 1, true) ~= nil, true,
        "the retried Share is the published Heroic note, not the Infer Mythic guess")
    NT.pendingFlush = nil
    NT._encountersForMap = nil
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    env.EJ_GetNumTiers = nil
    env.EJ_SelectTier = nil
    env.EJ_SelectInstance = nil
    env.EJ_GetInstanceByIndex = nil
    env.EJ_GetInstanceInfo = nil
    env.EJ_GetEncounterInfoByIndex = nil
    env.EJ_GetInstanceForMap = nil
    env._isLead = true
end

-- Leftover pendingFlush on a client that already has a stand must not rewind the cursor.
do
    env._isLead = true
    env._shared = nil
    NT.pendingFlush = 3470
    NT.generation = 2
    KARTTEST.aurasSecret = false
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
        Boss2 = "EncounterID:3497;Name:Next;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 1,
        ntDiff = 16,
        ntCursor = 3497,
        ntGeneration = 2,
        ntChecksum = "",
        ntOrderByInstance = {
            ["1:16"] = { order = { 3470, 3497 }, skipped = {} },
        },
    }
    T.eq(NT.ApplyRemoteState(env.KART_Settings, {
        gen = 3,
        editor = "Alric",
        operator = "Alric",
        mapId = 1,
        diff = 16,
        cursor = 3497,
        checksum = "new",
        order = { 3470, 3497 },
        skipped = {},
    }), true, "later STATE from operator is accepted")
    T.eq(env.KART_Settings.ntCursor, 3497, "leftover pendingFlush does not rewind cursor")
    T.eq(NT.pendingFlush, nil, "pendingFlush clears when the stand was already valid")
    T.eq(env._shared, nil, "leftover pendingFlush does not re-Share the old note")
    env._isLead = true
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

-- Drag-reorder inserts at the drop index; it does not swap the two ends.
do
    NT.EnsureShape(env.KART_Settings)
    local key = NT.InstanceKey(1, 16)
    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntOrderByInstance[key] = { order = { 3470, 3497, 3445 }, skipped = {} }
    env.KART_Settings.ntModuleEnabled = true
    env._isLead = true
    NT._listMapKey = key
    NT._visibleIds = { 3470, 3497, 3445 }
    NT.Move(1, 3)
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[1], 3497, "first slot is the old second")
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[2], 3445, "middle is the old last")
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[3], 3470, "dropped row lands at the drop index")
    NT._visibleIds = { 3497, 3445, 3470 }
    NT.Move(3, 1)
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[1], 3470, "drop on first puts it first")
    T.eq(env.KART_Settings.ntOrderByInstance[key].order[2], 3497, "the rest shift down")
end

-- Injected EJ order is used as-is; encounter IDs are not numeric-sorted.
do
    local savedNSRT = env.NSRT
    env.NSRT = { Reminders = {} }
    NT._encountersForMap = function()
        return { { id = 3470, name = "Nekzali" }, { id = 100, name = "Low" }, { id = 9999, name = "High" } }
    end
    local order = NT.DefaultEncounterOrder()
    T.eq(order[1], 3470, "injected first encounter is first")
    T.eq(order[2], 100, "injected order is used, not numeric-sorted")
    T.eq(order[3], 9999, "injected last encounter stays last")
    T.eq(#order, 3, "no extra ids without notes")
    NT._encountersForMap = nil
    env.NSRT = savedNSRT
end

-- Imported notes from another instance (1-boss raid) still appear after EJ bosses.
do
    local savedNSRT = env.NSRT
    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.NSRT = { Reminders = {
        A = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
        B = "EncounterID:100;Name:Low;Difficulty:Mythic\ncd",
        Extra = "EncounterID:8800;Name:Nymrissa;Difficulty:Mythic\ncd",
    }}
    NT._encountersForMap = function()
        return { { id = 3470, name = "Nekzali" }, { id = 100, name = "Low" } }
    end
    local order = NT.DefaultEncounterOrder()
    T.eq(#order, 3, "a note whose encounter is not in EJ is appended")
    T.eq(order[1], 3470, "EJ order is kept")
    T.eq(order[2], 100, "EJ second stays second")
    T.eq(order[3], 8800, "the extra note is last, not numeric-sorted into the middle")
    local withBag = NT.AppendMissingNoteIds({ 3470, 100 }, "Mythic")
    T.eq(#withBag, 3, "a saved 8-boss order still gains the 9th note")
    T.eq(withBag[3], 8800, "the extra id is appended to the saved order")
    NT._encountersForMap = nil
    env.NSRT = savedNSRT
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
    local flushedWhileSecret = false
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_FLUSH:" then flushedWhileSecret = true end
    end
    T.eq(flushedWhileSecret, false, "Share now does not flush while secret")
    KARTTEST.aurasSecret = false
    KARTTEST.AdvanceTime(1.1)
    local queuedFlush
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_FLUSH:" then queuedFlush = m end
    end
    T.eq(queuedFlush, "NT_FLUSH:3470", "queued flush is the cursor")
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

-- Solo in town: UnitIsGroupLeader is false (no group). Share now still loads the cursor note.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    KARTTEST.SetRaid({})
    env._isLead = false
    env._shared = nil
    env._loaded = nil
    NT.pendingFlush = nil
    KARTTEST.aurasSecret = false
    env.NorthernSkyRaidTools = {
        SetReminder = function(_, name)
            env._loaded = name
        end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        ["Nekzali - Heroic"] = "EncounterID:3470;Name:Nekzali - Heroic;Difficulty:Heroic\ncd1",
        ["Sentinels - Heroic"] = "EncounterID:3497;Name:Sentinels - Heroic;Difficulty:Heroic\ncd2",
    }}
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 15
    env.KART_Settings.ntCursor = 3497
    env.KART_Settings.ntOperatorName = ""
    env.KART_Settings.ntChecksum = ""
    NT.EnsureShape(env.KART_Settings)
    env.KART_Settings.ntOrderByInstance["1234:15"] = { order = { 3470, 3497 }, skipped = {} }
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    NT.ShareNow()
    T.eq(env._loaded, "Sentinels - Heroic", "solo town Share now loads the marked boss in NSRT")
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntMapId = 1234
    NT.EnsureShape(env.KART_Settings)
    env.KART_Settings.ntOrderByInstance["1234:16"] = { order = { 3470 }, skipped = {} }
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
end

-- pendingFlush is share-now, not a Restricted queue: town still Shares, then the flag clears.
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
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    NT.ShareNow()
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "town + pendingFlush still Shares")
    T.eq(NT.statusLabel.text == "Waiting until combat ends.", false, "pendingFlush does not queue")
    T.eq(NT.pendingFlush, nil, "successful Share clears pendingFlush")
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

-- NT_FLUSH receive applies the cursor and Load & Sends when this client is the chosen sender.
do
    env._isLead = true
    env._shared = nil
    env._ntSent = {}
    KARTTEST.aurasSecret = false
    KARTTEST.instance.mapID = 1
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss2 = "EncounterID:3497;Name:Next;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "",
        ntMapId = 1,
        ntDiff = 16,
        ntCursor = 3470,
        ntOrderByInstance = {
            ["1:16"] = { order = { 3470, 3497 }, skipped = {} },
        },
    }
    T.truthy(env._ntHandlers.NT_FLUSH, "NT_FLUSH handler is registered")
    env._ntHandlers.NT_FLUSH("3497", { shortName = "Bramor", lead = true })
    T.eq(env.KART_Settings.ntCursor, 3497, "flush receive applies payload to cursor")
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "flush receive Load & Sends")

    env._shared = nil
    env.KART_Settings.ntCursor = 3470
    env._ntHandlers.NT_FLUSH("3497", { shortName = "Alric", lead = false })
    T.eq(env.KART_Settings.ntCursor, 3470, "non-lead flush does not move cursor")
    T.eq(env._shared, nil, "non-lead flush does not Load & Send")
end

-- RequestFlush is lead-only.
do
    env._isLead = false
    env._ntSent = {}
    env._shared = nil
    env.KART_Settings.ntModuleEnabled = true
    NT.RequestFlush(3470)
    T.eq(#env._ntSent, 0, "non-lead RequestFlush does not emit")
    T.eq(env._shared, nil, "non-lead RequestFlush does not Share")
end

-- Skip-and-advance: skipped cursor moves; Share now does not send a skipped id.
do
    env._isLead = true
    env._shared = nil
    env._ntSent = {}
    KARTTEST.aurasSecret = false
    KARTTEST.instance.mapID = 1
    KARTTEST.instance.instanceType = "raid"
    KARTTEST.instance.difficultyID = 16
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
        Boss2 = "EncounterID:3497;Name:Next;Difficulty:Mythic\ncd",
        Boss3 = "EncounterID:3445;Name:Third;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "",
        ntMapId = 1,
        ntDiff = 16,
        ntCursor = 3470,
        ntGeneration = 0,
        ntOrderByInstance = {
            ["1:16"] = { order = { 3470, 3497, 3445 }, skipped = {} },
        },
    }
    NT.generation = 0
    NT.SetSkipped("1:16", 3470, true)
    T.eq(env.KART_Settings.ntCursor, 3497, "skipping the current cursor advances it")

    env._shared = nil
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntOrderByInstance["1:16"].skipped = { [3470] = true }
    NT.ShareNow()
    T.eq(env.KART_Settings.ntCursor, 3497, "Share now advances off a skipped cursor")
    T.eq(env._shared and env._shared[3]:find("3497", 1, true) ~= nil, true,
        "Share now sends the next sendable, not the skipped id")

    env._shared = nil
    env.KART_Settings.ntCursor = 3497
    env.KART_Settings.ntOrderByInstance["1:16"].skipped = {}
    NT.SkipAndAdvance()
    T.eq(env.KART_Settings.ntOrderByInstance["1:16"].skipped[3497], true, "SkipAndAdvance skips the cursor")
    T.eq(env.KART_Settings.ntCursor, 3445, "SkipAndAdvance moves to the next sendable")

    env._shared = nil
    env.KART_Settings.ntCursor = 0
    env.KART_Settings.ntOrderByInstance["1:16"].skipped = {}
    NT.ShareNow()
    T.eq(env.KART_Settings.ntCursor, 3470, "Share now with no cursor starts at the first sendable")
    T.eq(env._shared and env._shared[3]:find("3470", 1, true) ~= nil, true,
        "Share now with no cursor sends the first note")

    env._shared = nil
    env.KART_Settings.ntCursor = 0
    env.KART_Settings.ntOrderByInstance["1:16"].skipped = {}
    NT.SkipAndAdvance()
    T.eq(env.KART_Settings.ntOrderByInstance["1:16"].skipped[3470], true,
        "SkipAndAdvance with no cursor skips the first sendable")
    T.eq(env.KART_Settings.ntCursor, 3497, "and moves to the next sendable")
end

-- Tonight starts at boss 4; bosses 1-3 stay on the list (not skipped).
do
    env._isLead = false
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "",
        ntMapId = 1,
        ntDiff = 16,
        ntCursor = 3470,
        ntGeneration = 0,
        ntOrderByInstance = {
            ["1:16"] = { order = { 3470, 3497, 3445 }, skipped = {} },
        },
    }
    NT.generation = 0
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Lead", realm = KARTTEST.realm, guid = "Player-1-LEAD", role = "TANK", class = "WARRIOR", classFile = "WARRIOR" },
        { name = "Alt", realm = KARTTEST.realm, guid = "Player-1-ALT", role = "DAMAGER", class = "MAGE", classFile = "MAGE" },
    })
    NT.SetCursor(3445)
    T.eq(env.KART_Settings.ntCursor, 3470, "a raider in the group cannot set the start cursor")
    env._isLead = true
    NT.SetCursor(3445)
    T.eq(env.KART_Settings.ntCursor, 3445, "lead click sets the start cursor")
    T.is_nil(env.KART_Settings.ntOrderByInstance["1:16"].skipped[3470],
        "setting the start does not skip boss 1")
    T.is_nil(env.KART_Settings.ntOrderByInstance["1:16"].skipped[3497],
        "setting the start does not skip boss 2")
    env._isLead = false
    env.KART_Settings.ntCursor = 3470
    KARTTEST.SetRaid({})
    NT.SetCursor(3445)
    T.eq(env.KART_Settings.ntCursor, 3445, "in town with no group, click still sets the start")
    KARTTEST.RestoreRoster(roster)
end

-- Several notes for one encounter: ActiveReminder wins; else first stable match.
do
    env.NSRT = {
        ActiveReminder = "Alpha",
        Reminders = {
            Alpha = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\nalpha",
            Later = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\nlater",
        },
    }
    T.eq(NT.NoteNameForEncounter(3470, "Mythic"), "Alpha", "ActiveReminder matching the encounter wins")
    env.NSRT.ActiveReminder = "Unrelated"
    env.NSRT.Reminders.Unrelated = "EncounterID:9999;Name:Other;Difficulty:Mythic\nx"
    T.eq(NT.NoteNameForEncounter(3470, "Mythic"), "Alpha",
        "without a matching ActiveReminder, first stable name wins")
end

-- EncountersFromEJ / ResetOrder use the raid stand map, not local town GetInstanceInfo.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 16
    env.EJ_GetNumTiers = function() return 1 end
    env.EJ_GetEncounterInfoByIndex = function(i, journalId)
        if journalId == 77 and i == 1 then return "Nekzali", nil, nil, nil, nil, nil, 3470 end
        return nil
    end
    env.EJ_GetInstanceForMap = function(mapId)
        if mapId == 1234 then return 77 end
        return nil
    end
    env.EJ_SelectInstance = function() end
    NT._encountersForMap = nil
    local list = NT.EncountersFromEJ()
    T.eq(#list, 1, "town EncountersFromEJ uses the stand map")
    T.eq(list[1] and list[1].id, 3470, "stand map yields the raid encounter")

    -- Town, no stand: map 0 must not resolve the world-boss journal (live: key "0:0").
    -- No NSRT notes → nothing to infer a raid from.
    inst.mapID = 0
    inst.difficultyID = 0
    env.KART_Settings.ntMapId = 0
    env.KART_Settings.ntDiff = 0
    local savedNSRT = env.NSRT
    env.NSRT = nil
    local askedMap
    env.EJ_GetInstanceForMap = function(mapId)
        askedMap = mapId
        return 322
    end
    env.EJ_GetEncounterInfoByIndex = function(i)
        if i == 1 then return "Grand Empress Shek'zara", nil, nil, nil, nil, nil, 2351 end
        if i == 2 then return "Ivus the Decayed" end
        return nil
    end
    list = NT.EncountersFromEJ()
    T.eq(#list, 0, "town without a stand does not walk the world-boss journal")
    T.eq(askedMap, nil, "EJ_GetInstanceForMap is not called for map 0")
    env.NSRT = savedNSRT

    -- Valid stand: EJ rows with a name but no dungeonEncounterID are omitted.
    env.KART_Settings.ntMapId = 1234
    env.KART_Settings.ntDiff = 16
    env.EJ_GetInstanceForMap = function(mapId)
        if mapId == 1234 then return 77 end
        return nil
    end
    env.EJ_GetEncounterInfoByIndex = function(i, journalId)
        if journalId == 77 and i == 1 then return "Shek'zara", nil, nil, nil, nil, nil, 2351 end
        if journalId == 77 and i == 2 then return "Ivus the Decayed" end
        if journalId == 77 and i == 3 then return "Wekemara", nil, nil, nil, nil, nil, 2318 end
        return nil
    end
    list = NT.EncountersFromEJ()
    T.eq(#list, 2, "EJ rows with no dungeonEncounterID are omitted")
    T.eq(list[1] and list[1].id, 2351, "first named boss with an id is kept")
    T.eq(list[2] and list[2].id, 2318, "a later boss after a nil-id row is still kept")

    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    env.EJ_GetNumTiers = nil
    env.EJ_GetEncounterInfoByIndex = nil
    env.EJ_GetInstanceForMap = nil
    env.EJ_SelectInstance = nil
end

-- Town operator: no published stand, but NSRT notes pick the current-tier raid
-- (skip world bosses at EJ index 1, same as AutoNote).
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local savedNSRT = env.NSRT
    inst.instanceType = "none"
    inst.difficultyID = 0
    inst.mapID = 0
    env.KART_Settings.ntMapId = 0
    env.KART_Settings.ntDiff = 0
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.EJ_GetNumTiers = function() return 2 end
    env.EJ_SelectTier = function() end
    env.EJ_SelectInstance = function() end
    env.EJ_GetInstanceByIndex = function(idx, isRaid)
        if not isRaid then return nil end
        if idx == 1 then return 1 end
        if idx == 2 then return 77 end
        return nil
    end
    env.EJ_GetInstanceInfo = function(journalId)
        if journalId == 77 then
            return "Voidspire", nil, nil, nil, nil, nil, nil, nil, nil, 2805
        end
        if journalId == 1 then
            return "World Bosses", nil, nil, nil, nil, nil, nil, nil, nil, 0
        end
    end
    env.EJ_GetEncounterInfoByIndex = function(i, journalId)
        if journalId == 1 and i == 1 then return "Ivus the Decayed" end
        if journalId == 77 and i == 1 then return "Nekzali", nil, nil, nil, nil, nil, 3470 end
        return nil
    end
    local askedMap
    env.EJ_GetInstanceForMap = function(mapId)
        askedMap = mapId
        if mapId == 2805 then return 77 end
        if mapId == 0 then return 1 end
        return nil
    end
    NT._encountersForMap = nil
    local mapId, diff = NT.RaidMapDiff()
    T.eq(mapId, 2805, "town infers the raid whose notes match")
    T.eq(diff, 16, "town infers Mythic from note headers")
    T.eq(env.KART_Settings.ntMapId, 0, "inference does not stamp the stand")
    local list = NT.EncountersFromEJ()
    T.eq(#list, 1, "inferred stand walks that raid")
    T.eq(list[1] and list[1].id, 3470, "inferred raid yields the note's encounter")
    T.eq(askedMap == 0, false, "inference does not call EJ_GetInstanceForMap(0)")
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    env.NSRT = savedNSRT
    env.EJ_GetNumTiers = nil
    env.EJ_SelectTier = nil
    env.EJ_SelectInstance = nil
    env.EJ_GetInstanceByIndex = nil
    env.EJ_GetInstanceInfo = nil
    env.EJ_GetEncounterInfoByIndex = nil
    env.EJ_GetInstanceForMap = nil
end

-- DefaultEncounterOrder and RefreshBossList skip encounters with no id
-- (live LuaError: names[enc.id] with enc = { name = "Ivus the Decayed" }).
do
    local savedNSRT = env.NSRT
    env.NSRT = { Reminders = {} }
    NT._encountersForMap = function()
        return {
            { id = 2351, name = "Grand Empress Shek'zara" },
            { name = "Ivus the Decayed" },
            { id = 2318, name = "Wekemara" },
        }
    end
    local order = NT.DefaultEncounterOrder()
    T.eq(#order, 2, "DefaultEncounterOrder skips nil ids")
    T.eq(order[1], 2351, "first id is kept")
    T.eq(order[2], 2318, "id after a nil-id row is kept, not dropped by a hole")

    NT.bossListFrame = {
        rows = {},
        SetHeight = function() end,
        emptyLabel = { Show = function() end, Hide = function() end, SetText = function() end },
    }
    NT.bossListCard = { SetHeight = function() end }
    NT._refreshingList = false
    local ok = pcall(NT.RefreshBossList)
    T.eq(ok, true, "RefreshBossList does not error on an encounter with no id")
    env.NSRT = savedNSRT
    NT._encountersForMap = nil
    NT.bossListFrame = nil
    NT.bossListCard = nil
    NT._refreshingList = false
end

-- Successful ApplyRemoteState refreshes the Notes panel.
do
    local listHits, statusHits = 0, 0
    local origList, origStatus = NT.RefreshBossList, NT.RefreshStatus
    NT.RefreshBossList = function() listHits = listHits + 1 end
    NT.RefreshStatus = function() statusHits = statusHits + 1 end
    env.KART_Settings.ntGeneration = 1
    NT.generation = 1
    local ok = NT.ApplyRemoteState(env.KART_Settings, {
        gen = 4, editor = "Bramor", operator = "Wuusch",
        mapId = 1, diff = 16, cursor = 3470, checksum = "abcd",
        order = { 3470 }, skipped = {},
    })
    T.eq(ok, true, "higher generation applies")
    T.eq(listHits, 1, "ApplyRemoteState refreshes the boss list")
    T.eq(statusHits, 1, "ApplyRemoteState refreshes status")
    NT.RefreshBossList = origList
    NT.RefreshStatus = origStatus
end

-- NT_STATE_REQ pulls; the answerer publishes stand + lead window. Never from OnPeer.
do
    env._isLead = true
    env._ntSent = {}
    NT._lastStateAnswer = nil
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    env.KART_Settings.ntGeneration = 2
    env.KART_Settings.ntOperatorName = "Wuusch"
    NT.generation = 2
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })

    NT.RequestState()
    local sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, true, "RequestState emits NT_STATE_REQ")

    env._ntSent = {}
    T.truthy(env._ntHandlers.NT_STATE_REQ, "NT_STATE_REQ handler is registered")
    env._ntHandlers.NT_STATE_REQ("", { shortName = "Alric", lead = false })
    local sawState, sawLead = false, false
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_STATE:" then sawState = true end
        if type(m) == "string" and m:sub(1, 8) == "NT_LEAD:" then sawLead = true end
    end
    T.eq(sawState, true, "REQ as lead publishes NT_STATE")
    T.eq(sawLead, true, "REQ as lead publishes NT_LEAD")

    env._ntSent = {}
    env._ntHandlers.NT_STATE_REQ("", { shortName = "Alric", lead = false })
    T.eq(#env._ntSent, 0, "REQ answer is on a 5s cooldown")

    env._isLead = false
    env.KART_Settings.ntOperatorName = "Wuusch"
    env._ntSent = {}
    NT._lastStateAnswer = nil
    env._ntHandlers.NT_STATE_REQ("", { shortName = "Alric", lead = false })
    T.eq(#env._ntSent, 0, "raider does not answer NT_STATE_REQ")

    KARTTEST.RestoreRoster(roster)
end

-- Lead Restricted window: town operator queues Share now; fail-open until a window arrives.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    local savedActive = KARTTEST.activeUnit
    local savedRealm = KARTTEST.realm
    KARTTEST.realm = "TarrenMill"
    KARTTEST.activeUnit = "raid1"
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = false
    env._shared = nil
    env._ntSent = {}
    NT.pendingFlush = nil
    NT.leadInRaid = nil
    NT.leadRestricted = nil
    NT._shareQueued = nil
    NT._lastSharedCursor = nil
    NT._lastSharedAt = nil
    KARTTEST.aurasSecret = false
    KART.PlayerVersions = { Alric = "3.3.1" }
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 1234,
        ntDiff = 16,
        ntCursor = 3470,
        ntChecksum = "",
        ntOrderByInstance = {
            ["1234:16"] = { order = { 3470 }, skipped = {} },
        },
    }
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }

    NT.ShareNow()
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "fail-open: no NT_LEAD yet still Shares")

    env._shared = nil
    T.truthy(env._ntHandlers.NT_LEAD, "NT_LEAD handler is registered")
    env._ntHandlers.NT_LEAD("1\t1", { shortName = "Bramor", lead = true })
    T.eq(NT.leadInRaid, true, "NT_LEAD inRaid bit")
    T.eq(NT.leadRestricted, true, "NT_LEAD restricted bit")
    NT.ShareNow()
    T.eq(env._shared, nil, "operator Share now does not Share while lead is Restricted inside")
    T.eq(NT.statusLabel.text, "Waiting until combat ends.", "Share now queues on lead Restricted")

    env._ntHandlers.NT_LEAD("1\t0", { shortName = "Bramor", lead = true })
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE", "unrestrict retries the queued Share now")

    env._shared = nil
    env._ntHandlers.NT_FLUSH("3470", { shortName = "Bramor", lead = true })
    T.eq(env._shared, nil, "FLUSH after the queued share does not Load & Send twice")

    env._shared = nil
    env._ntHandlers.NT_LEAD("1\t1", { shortName = "Alric", lead = false })
    T.eq(NT.leadRestricted, false, "non-lead NT_LEAD is ignored")

    env._isLead = true
    NT.leadInRaid = true
    NT.leadRestricted = true
    KARTTEST.aurasSecret = false
    env._shared = nil
    env.KART_Settings.ntOperatorName = ""
    NT.ShareNow()
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE",
        "lead Share now uses local AurasSecret, not the echoed window")

    KART.PlayerVersions = nil
    KARTTEST.activeUnit = savedActive
    KARTTEST.realm = savedRealm
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    NT.leadInRaid = nil
    NT.leadRestricted = nil
    NT._shareQueued = nil
end

-- Town PEW still pulls; leave publishes the lead window so town Share now unblocks.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })
    env._isLead = false
    env._ntSent = {}
    NT._stateRequested = nil
    NT._lastLeadPayload = nil
    env.KART_Settings.ntModuleEnabled = true
    inst.instanceType = "none"
    inst.difficultyID = 0
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    local sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, true, "grouped town PEW pulls NT_STATE")
    env._ntSent = {}
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, false, "second PEW in the same group does not pull again")

    env._isLead = true
    env._ntSent = {}
    NT._lastLeadPayload = nil
    inst.instanceType = "raid"
    inst.difficultyID = 16
    inst.mapID = 1
    KARTTEST.aurasSecret = false
    NT.PublishLeadWindow(true)
    T.eq(env._ntSent[#env._ntSent], "NT_LEAD:1\t0", "lead in a notes raid publishes inRaid 1 restricted 0")
    env._ntSent = {}
    inst.instanceType = "none"
    inst.difficultyID = 0
    NT.OnEvent("PLAYER_ENTERING_WORLD")
    local lastLead
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 8) == "NT_LEAD:" then lastLead = m end
    end
    T.eq(lastLead, "NT_LEAD:0\t0", "leave publishes inRaid 0 so town Share now unblocks")

    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    NT._stateRequested = nil
    NT._lastLeadPayload = nil
end

-- RequestFlush is in-instance lead only. Town lead must not emit NT_FLUSH.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    env._isLead = true
    env._ntSent = {}
    env._shared = nil
    env.KART_Settings.ntModuleEnabled = true
    env.KART_Settings.ntCursor = 3470
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    NT.RequestFlush(3470)
    local flushed
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_FLUSH:" then flushed = m end
    end
    T.eq(flushed, nil, "town lead RequestFlush does not emit NT_FLUSH")
    T.eq(env._shared, nil, "town lead RequestFlush does not Share")

    inst.instanceType = "raid"
    inst.difficultyID = 16
    inst.mapID = 1
    env._ntSent = {}
    NT.RequestFlush(3470)
    flushed = nil
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_FLUSH:" then flushed = m end
    end
    T.eq(flushed, "NT_FLUSH:3470", "in-instance lead RequestFlush emits NT_FLUSH")
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
end

-- Idle status is who would send, not only operator presence.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    local savedActive = KARTTEST.activeUnit
    local savedRealm = KARTTEST.realm
    KARTTEST.realm = "TarrenMill"
    KARTTEST.activeUnit = "raid1"
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = false
    NT.leadInRaid = nil
    NT.leadRestricted = nil
    KARTTEST.aurasSecret = false
    KART.PlayerVersions = { Alric = "3.3.1" }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 1234,
        ntDiff = 16,
        ntCursor = 3470,
        ntChecksum = "",
        ntOrderByInstance = {
            ["1234:16"] = { order = { 3470 }, skipped = {} },
        },
    }
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    KART.L.NT_STATUS_STALE = "Operator note is older than the last share; lead will send."
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    KART.L.NT_STATUS_OPERATOR_GONE = "Operator: %s (not in group) — you send"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }

    NT.RefreshStatus()
    T.eq(NT.statusLabel.text, "Sender: Alric", "status names the operator when they would send")

    env.KART_Settings.ntChecksum = "not-the-note"
    NT.RefreshStatus()
    T.eq(NT.statusLabel.text, "Operator note is older than the last share; lead will send.",
        "status is stale when the operator would not send")

    env.KART_Settings.ntChecksum = ""
    NT.leadInRaid = true
    NT.leadRestricted = true
    NT.RefreshStatus()
    T.eq(NT.statusLabel.text, "Waiting until combat ends.",
        "status is queued while the lead is Restricted inside")

    NT.leadInRaid = nil
    NT.leadRestricted = nil
    env._isLead = true
    env.KART_Settings.ntOperatorName = "Wuusch"
    KARTTEST.SetRaid({
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })
    KARTTEST.activeUnit = "raid1"
    NT.RefreshStatus()
    T.eq(NT.statusLabel.text, "Operator: Wuusch (not in group) — you send",
        "status is operator gone when the lead would send")

    KART.PlayerVersions = nil
    KARTTEST.activeUnit = savedActive
    KARTTEST.realm = savedRealm
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    NT.leadInRaid = nil
    NT.leadRestricted = nil
end

-- Joining a group in town pulls once; leave group allows a later pull.
do
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", guid = "Player-1-AL" },
    })
    env._isLead = false
    env._ntSent = {}
    NT._stateRequested = nil
    env.KART_Settings.ntModuleEnabled = true
    NT.OnEvent("GROUP_ROSTER_UPDATE")
    local sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, true, "group join pulls NT_STATE")
    env._ntSent = {}
    NT.OnEvent("GROUP_ROSTER_UPDATE")
    sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, false, "roster noise does not pull again")

    KARTTEST.SetRaid({})
    NT.OnEvent("GROUP_ROSTER_UPDATE")
    T.eq(NT._stateRequested, nil, "leaving the group clears the pull flag")
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", guid = "Player-1-AL" },
    })
    env._ntSent = {}
    NT.OnEvent("GROUP_ROSTER_UPDATE")
    sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, true, "rejoin pulls NT_STATE again")

    KARTTEST.RestoreRoster(roster)
    NT._stateRequested = nil
end

-- Module-off GROUP_ROSTER_UPDATE still clears the pull flag (frame gate).
do
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", guid = "Player-1-AL" },
    })
    env.KART_Settings.ntModuleEnabled = true
    NT._stateRequested = true
    env.KART_Settings.ntModuleEnabled = false
    KARTTEST.SetRaid({})
    NT._eventFrame:GetScript("OnEvent")(NT._eventFrame, "GROUP_ROSTER_UPDATE")
    T.eq(NT._stateRequested, nil, "module-off leave group clears the pull flag")
    KARTTEST.RestoreRoster(roster)
    NT._stateRequested = nil
end

-- Operator in town, locally Restricted, lead not inside: queued Share now resumes when auras clear.
do
    local inst = KARTTEST.instance
    local saved = { instanceType = inst.instanceType, difficultyID = inst.difficultyID, mapID = inst.mapID }
    local roster = KARTTEST.SnapshotRoster()
    local savedActive = KARTTEST.activeUnit
    local savedRealm = KARTTEST.realm
    KARTTEST.realm = "TarrenMill"
    KARTTEST.activeUnit = "raid1"
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", assist = true, guid = "Player-1-AL" },
        { name = "Bramor", realm = "TarrenMill", leader = true, guid = "Player-1-BR" },
    })
    inst.instanceType = "none"
    inst.difficultyID = 1
    inst.mapID = 99
    env._isLead = false
    env._shared = nil
    NT.leadInRaid = false
    NT.leadRestricted = false
    NT._shareQueued = nil
    KARTTEST.aurasSecret = true
    KART.PlayerVersions = { Alric = "3.3.1" }
    env.NorthernSkyRaidTools = {
        SetReminder = function() end,
        Broadcast = function(_, ev, ch, body)
            env._shared = { ev, ch, body }
        end,
    }
    env.NSRT = { Reminders = {
        Boss1 = "EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd",
    }}
    env.KART_Settings = {
        ntModuleEnabled = true,
        ntOperatorName = "Alric",
        ntMapId = 1234,
        ntDiff = 16,
        ntCursor = 3470,
        ntChecksum = "",
        ntOrderByInstance = {
            ["1234:16"] = { order = { 3470 }, skipped = {} },
        },
    }
    KART.L.NT_STATUS_QUEUED = "Waiting until combat ends."
    KART.L.NT_STATUS_SENDER = "Sender: %s"
    NT.statusLabel = { SetText = function(self, s) self.text = s end }
    NT.ShareNow()
    T.eq(env._shared, nil, "operator Share now does not Share while locally Restricted")
    KARTTEST.aurasSecret = false
    KARTTEST.AdvanceTime(1.1)
    T.eq(env._shared and env._shared[1], "NSI_REM_SHARE",
        "queued operator Share now resumes when auras clear and lead is not inside")
    KART.PlayerVersions = nil
    KARTTEST.activeUnit = savedActive
    KARTTEST.realm = savedRealm
    KARTTEST.RestoreRoster(roster)
    inst.instanceType, inst.difficultyID, inst.mapID = saved.instanceType, saved.difficultyID, saved.mapID
    NT.leadInRaid = nil
    NT.leadRestricted = nil
end

-- Turning the module on in a group pulls once.
do
    local roster = KARTTEST.SnapshotRoster()
    KARTTEST.SetRaid({
        { name = "Alric", realm = "TarrenMill", guid = "Player-1-AL" },
    })
    env._isLead = false
    env._ntSent = {}
    NT._stateRequested = true
    env.KART_Settings.ntModuleEnabled = true
    NT.OnModuleEnabled()
    local sawReq = false
    for _, m in ipairs(env._ntSent) do
        if m == "NT_STATE_REQ" then sawReq = true end
    end
    T.eq(sawReq, true, "enabling the module in a group pulls NT_STATE")
    KARTTEST.RestoreRoster(roster)
    NT._stateRequested = nil
end

-- Operator slot is a raid stand: only the lead may change it.
do
    env._isLead = false
    T.eq(NT.MayEditOperator(), false, "a raider may not edit the operator slot")
    env._isLead = true
    T.eq(NT.MayEditOperator(), true, "the lead may edit the operator slot")

    env._isLead = false
    env.KART_Settings.ntOperatorName = "Mario"
    env.KART_Settings.ntGeneration = 3
    NT.generation = 3
    env._ntSent = {}
    T.eq(NT.CommitOperatorName("abc"), false, "raider commit is refused")
    T.eq(env.KART_Settings.ntOperatorName, "Mario", "abc does not replace the raid operator")
    T.eq(NT.generation, 3, "refused commit does not bump generation")
    local published = false
    for _, m in ipairs(env._ntSent) do
        if type(m) == "string" and m:sub(1, 9) == "NT_STATE:" then published = true end
    end
    T.eq(published, false, "raider commit does not publish NT_STATE")

    env._isLead = true
    T.eq(NT.CommitOperatorName("Kandera"), true, "lead can put themselves in the slot")
    T.eq(env.KART_Settings.ntOperatorName, "Kandera", "lead commit stores the new operator")
    T.eq(NT.generation > 3, true, "lead commit bumps generation")

    T.eq(NT.CommitOperatorName("Alric\t"), true, "lead commit with a tab is accepted")
    T.eq(env.KART_Settings.ntOperatorName, "Alric", "tab is stripped from the operator name")
end

-- Paste imports into local NSRT shared reminders (not personal, not KASC).
do
    env._imported = nil
    T.eq(NT.ImportReminderText(""), "empty", "blank paste is empty")
    T.eq(NT.ImportReminderText("   "), "empty", "whitespace paste is empty")
    T.eq(NT.ImportReminderText("no headers here"), "parse", "text without EncounterID is a parse miss")

    local savedNSI = env.NorthernSkyRaidTools
    env.NorthernSkyRaidTools = nil
    T.eq(NT.ImportReminderText("EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd"), "no_nsrt",
        "missing NSRT does not import")

    env.NorthernSkyRaidTools = {
        ImportFullReminderString = function(self, str, personal, isUpdate)
            env._imported = { str = str, personal = personal, isUpdate = isUpdate, self = self }
            env.NSRT = env.NSRT or { Reminders = {} }
            env.NSRT.Reminders["Nekzali - Mythic"] = str
        end,
    }
    local status, n = NT.ImportReminderText("EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd")
    T.eq(status, "ok", "a shared-note export imports")
    T.eq(n, 1, "one EncounterID counts as one note")
    T.eq(env._imported.personal, false, "import is shared, not personal")
    T.eq(env._imported.isUpdate, false, "import is not an in-place update")
    T.eq(env._imported.self, env.NorthernSkyRaidTools, "Reloe receives self")

    env._wuReplaced = nil
    KART.WU = {
        ReplaceImportedText = function(text)
            env._wuReplaced = text
            return 1, "ok"
        end,
    }
    KART.RefreshStatusStrip = function() env._stripHits = (env._stripHits or 0) + 1 end
    env._stripHits = 0
    NT.ImportReminderText("EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ninvitelist:A-Realm;\n")
    T.eq(type(env._wuReplaced) == "string" and env._wuReplaced:find("invitelist:", 1, true) ~= nil, true,
        "notes import also replaces the invite library")
    T.eq(env._stripHits >= 1, true, "notes import refreshes the tonight strip")
    KART.WU = nil
    KART.RefreshStatusStrip = nil

    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 99
    NT.EnsureShape(env.KART_Settings)
    env.KART_Settings.ntOrderByInstance["1:16"] = { order = { 99, 88 }, skipped = { [99] = true } }
    env.KART_Settings.ntOrderByInstance["99:16"] = { order = { 1, 2, 3 }, skipped = {} }
    NT._encountersForMap = function()
        return { { id = 3470, name = "Nekzali" } }
    end
    local again = NT.ImportReminderText("EncounterID:3470;Name:Nekzali;Difficulty:Mythic\ncd")
    T.eq(again, "ok", "a second import still succeeds")
    T.eq(env.KART_Settings.ntOrderByInstance["1:16"].order[1], 3470,
        "import replaces the saved drag order")
    T.eq(env.KART_Settings.ntOrderByInstance["1:16"].skipped[99], nil,
        "import clears skips from the old order")
    T.eq(env.KART_Settings.ntOrderByInstance["99:16"], nil,
        "import drops drag bags from other instances")
    T.eq(env.KART_Settings.ntCursor, 0, "import clears the start cursor")
    NT._encountersForMap = nil
    env.NorthernSkyRaidTools = savedNSI
end

-- Delete notes uses Reloe RemoveReminder on shared names, then resets order.
do
    env._removed = {}
    env.NSRT = { Reminders = {
        A = "EncounterID:3470;Name:A;Difficulty:Mythic\ncd",
        B = "EncounterID:100;Name:B;Difficulty:Mythic\ncd",
    }}
    env.NorthernSkyRaidTools = {
        RemoveReminder = function(_, name, personal)
            env._removed[#env._removed + 1] = { name = name, personal = personal }
            env.NSRT.Reminders[name] = nil
        end,
        GetAllReminderNames = function()
            local list = {}
            for name in pairs(env.NSRT.Reminders) do
                list[#list + 1] = { name = name }
            end
            return list
        end,
    }
    env.KART_Settings.ntMapId = 1
    env.KART_Settings.ntDiff = 16
    env.KART_Settings.ntCursor = 3470
    NT.EnsureShape(env.KART_Settings)
    env.KART_Settings.ntOrderByInstance["99:16"] = { order = { 1 }, skipped = {} }
    NT.ImportEditBox = {
        text = "EncounterID:3470;Name:A;Difficulty:Mythic\ncd",
        SetText = function(self, v) self.text = tostring(v or "") end,
        GetText = function(self) return self.text end,
    }
    local status, n = NT.DeleteSharedNotes()
    T.eq(status, "ok", "delete reports ok")
    T.eq(n, 2, "delete removes both shared notes")
    T.eq(env._removed[1].personal, false, "delete is shared, not personal")
    T.eq(env.NSRT.Reminders.A, nil, "Reloe no longer has note A")
    T.eq(env.KART_Settings.ntOrderByInstance["99:16"], nil,
        "delete drops drag bags from other instances")
    T.eq(env.KART_Settings.ntCursor, 0, "delete clears the start cursor")
    T.eq(NT.ImportEditBox:GetText(), "", "delete clears the paste box")
    NT.ImportEditBox:SetText("leftover paste")
    T.eq(NT.DeleteSharedNotes(), "empty", "a second delete with an empty library is empty")
    T.eq(NT.ImportEditBox:GetText(), "", "empty delete still clears leftover paste")
end
