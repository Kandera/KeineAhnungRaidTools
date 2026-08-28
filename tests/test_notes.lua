-- NSRT Notes: sequence, cursor, generation. Isolated load of Notes.lua.
local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
env.LibStub = function()
    return {
        RegisterMessage = function() end,
        Send = function() end,
        DefaultChannel = function() return "RAID" end,
    }
end
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
