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

KARTTEST.RemoveRC()
T.eq(KART.RC.IsRCLoaded(), false, "no RC addon means the companion is inert")

KARTTEST.InstallRC()
T.eq(KART.RC.IsRCLoaded(), true, "RC double counts as loaded")
