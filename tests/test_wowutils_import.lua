-- WoWUtils paste import: the export's invitelist is comma-separated.
--
-- A live Midnight paste looks like:
--   EncounterID:3379;Difficulty:Mythic;Name:Nymrissa
--   invitelist:Name-Realm,Name-Realm,...;
-- ParseImport captured the list correctly (stops at the trailing ";") and then
-- split it with %S+. Commas are not whitespace, so a line with no spaces became
-- one "player" and every boss showed "(1)".

local env = setmetatable({}, { __index = _G })
env.KART_Settings = {}
local KART = {
    UI = { RegisterStaticPopup = function() end },
    L = {},
}
env.KART = KART
do
    local chunk = assert(loadstring(assert(io.open("Invite.lua", "r"):read("*a")), "@Invite.lua"))
    setfenv(chunk, env)
    chunk("KeineAhnungRaidTools", KART)
end

local WU = KART.WU

local function Parse(text)
    WU.bosses = {}
    WU.lastImportedText = nil
    return WU.ParseImport(text)
end

-- The live export: commas, no spaces, trailing ";" per invitelist -------------------------
do
    local n = Parse((
        "EncounterID:3379;Difficulty:Mythic;Name:Nymrissa\n"
        .. "invitelist:Kanderadk-Blackmoore,Shandelmonk-Mal'Ganis,Akurian-Blackrock,"
        .. "härrimonk-Blackrock,Níná-Blackhand,Sharin,Flixu;\n"
        .. "EncounterID:3380;Difficulty:Mythic;Name:Nek'zali\n"
        .. "invitelist:Heimdal-Blackmoore,Someone-Twisting Nether;\n"
    ))
    T.eq(n, 2, "two boss blocks parse")
    T.eq(#WU.bosses[1].players, 7, "comma-separated names are each a player, not one blob")
    T.eq(WU.bosses[1].players[1], "Kanderadk-Blackmoore", "first name is the first token")
    T.eq(WU.bosses[1].players[2], "Shandelmonk-Mal'Ganis", "apostrophe in the realm survives")
    T.eq(WU.bosses[1].players[4], "härrimonk-Blackrock", "umlaut names stay one token")
    T.eq(WU.bosses[1].players[6], "Sharin", "a name without a realm is still a player")
    T.eq(#WU.bosses[2].players, 2, "the next boss keeps its own list")
    T.eq(WU.bosses[2].players[2], "Someone-Twisting Nether",
        "a realm with a space is not split")
    T.eq(WU.bosses[1].players[7], "Flixu",
        "the first list does not swallow the next EncounterID")
end

-- Older space-separated pastes still import ------------------------------------------------
do
    local n = Parse(
        "EncounterID:1;Difficulty:Heroic;Name:Old Format\n"
        .. "invitelist:Alpha-Blackmoore Bravo-Thrall Charlie-Blackrock;\n"
    )
    T.eq(n, 1, "a space-separated invitelist still parses")
    T.eq(#WU.bosses[1].players, 3, "and still splits on whitespace when there are no commas")
    T.eq(WU.bosses[1].players[2], "Bravo-Thrall", "middle name is its own player")
end

-- The module chip disables invite/remove. Import is deliberately left alone.
do
    KART.L.WU_MODULE_DISABLED_MSG = "disabled"
    WU.bosses = { { name = "Nymrissa", players = { "Alric-TarrenMill" } } }
    KARTTEST.ClearInvites()
    env.KART_Settings.wuModuleEnabled = false
    WU.InviteBoss(1)
    T.eq(#KARTTEST.invited, 0, "a disabled wowutils module invites nobody")
    env.KART_Settings.wuModuleEnabled = nil
end
