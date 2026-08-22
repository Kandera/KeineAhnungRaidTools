-- Sidebar chrome helpers in Utils.lua: session Edit Mode and link copy.
local env = setmetatable({}, { __index = _G })
local KART = { L = { LINK_COPIED = "Link copied." } }
env.KART = KART

local chunk = assert(loadstring(assert(io.open("Utils.lua", "r")):read("*a"), "@Utils.lua"))
setfenv(chunk, env)
chunk("KeineAhnungRaidTools", KART)

do
    T.truthy(not KART.IsEditModeActive(), "edit mode starts off each session")
    KART.SetEditModeActive(true)
    T.truthy(KART.IsEditModeActive(), "edit mode can be turned on")
    KART.SetEditModeActive(true)
    T.truthy(KART.IsEditModeActive(), "turning on twice is a no-op")
    KART.SetEditModeActive(false)
    T.truthy(not KART.IsEditModeActive(), "edit mode can be turned off again")
end

do
    KARTTEST.clipboard = nil
    _G.CopyToClipboard = function(text) KARTTEST.clipboard = text end
    KART.CopyLink("https://example.test/kart")
    T.eq(KARTTEST.clipboard, "https://example.test/kart", "CopyLink uses CopyToClipboard")
end

do
    T.truthy(type(KART.InGameChangelog) == "table", "in-game changelog table exists")
    T.truthy(#KART.InGameChangelog >= 2, "changelog covers unreleased and a shipped version")
    T.eq(KART.InGameChangelog[1].version, "Unreleased", "first block is unreleased")
end
