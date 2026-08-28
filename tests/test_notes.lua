-- NSRT Notes: sequence, cursor, generation. Isolated load of Notes.lua.
local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = { L = {}, UI = { RegisterStaticPopup = function() end, CreateCard = function() return {} end } }
env.KART = KART
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
