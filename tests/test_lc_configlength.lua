-- Fitting the raid config into one addon message.
--
-- SendAddonMessage takes 255 bytes. The raid config carries a variable-length tail -- the council
-- list -- behind a prefix that is itself unbounded: vote-button labels run to 128 characters and the
-- lootmaster field has no limit at all. Going over does not truncate into something usable: every
-- receiver's anchored pattern fails on the fragment, so the whole raid silently stays on the config
-- it had before, and nothing is printed on either side. That is a failure this addon has already
-- paid for once, and BuildCouncilPayload is what was written to stop it.
--
-- A mutation run found all three of its boundaries survive being moved: `budget <= 0`,
-- `#council > budget`, and the byte count itself. Nothing measured what it produces.
--
-- Lifted out of the source the way test_lc_collectible.lua lifts IsCollectibleItem: it is a pure
-- string function, and what is under test is where it cuts.

local source = assert(io.open("LootCouncil.lua", "r")):read("*a")
local fn = source:match("\nlocal function BuildCouncilPayload%(prefix, council%).-\nend\n")
T.truthy(fn, "BuildCouncilPayload was found in LootCouncil.lua")

local printed = {}
local preamble = [[
local ADDON_MSG_MAX_BYTES = 255
local KART = { L = { LC_CONFIG_TOO_LONG = "too long", LC_CONFIG_TRUNCATED = "truncated" } }
local print = function(s) PRINTED[#PRINTED + 1] = s end
]]
local chunk = assert(loadstring(preamble .. fn .. "\nreturn BuildCouncilPayload"))
setfenv(chunk, setmetatable({ PRINTED = printed }, { __index = _G }))
local Build = chunk()

local function Fresh() for i = #printed, 1, -1 do printed[i] = nil end end
local function Said(what)
    for _, line in ipairs(printed) do if line:find(what, 1, true) then return true end end
    return false
end

-- Nothing to do -------------------------------------------------------------------------------------
do
    Fresh()
    local out = Build("LC_CONFIG:4:BIS;Zweitspec;Transmog:1:Bramor:", "Bramor;Merrit;Corvin")
    T.eq(out, "LC_CONFIG:4:BIS;Zweitspec;Transmog:1:Bramor:Bramor;Merrit;Corvin",
        "a config that fits is passed through unchanged")
    T.eq(#printed, 0, "with nothing said to the player")
end

-- Exactly at the limit ------------------------------------------------------------------------------
-- The boundary itself, which is what the mutants moved. 255 must go out; 256 must not go out whole.
do
    Fresh()
    local prefix = "LC_CONFIG:4:B:1:X:"
    local council = string.rep("a", 255 - #prefix)
    local out = Build(prefix, council)
    T.eq(#out, 255, "a payload of exactly 255 bytes is sent as it is")
    T.eq(#printed, 0, "and is not reported as truncated")
end

do
    Fresh()
    local prefix = "LC_CONFIG:4:B:1:X:"
    -- One byte over, and no ";" to cut back to: the whole tail goes rather than half a name.
    local out = Build(prefix, string.rep("a", 256 - #prefix))
    T.truthy(#out <= 255, "one byte over the limit does not go out over the limit")
    T.eq(out, prefix, "the council list is dropped rather than cut mid-name")
    T.truthy(Said("truncated"), "and the player is told it was cut")
end

-- Cutting on a name boundary ---------------------------------------------------------------------
do
    Fresh()
    local prefix = "LC_CONFIG:4:B:1:X:"
    local budget = 255 - #prefix
    -- Three names, the last of which crosses the budget.
    local council = string.rep("a", budget - 12) .. ";Merrit;Corvinlonger"
    local out = Build(prefix, council)
    T.truthy(#out <= 255, "the result fits the message")
    T.truthy(not out:find(";$"), "and does not end on a separator")
    local tail = out:sub(#prefix + 1)
    T.truthy(not tail:find("Corvinlong", 1, true),
        "the entry that did not fit is gone entirely, not half-written")
    T.truthy(tail:find("Merrit", 1, true), "while the one before it survives")
    T.truthy(Said("truncated"), "and the player is told")
end

-- A prefix that leaves no room at all --------------------------------------------------------------
-- Button labels run to 128 characters and the lootmaster field is unbounded, so this is reachable
-- from the settings panel alone. Refusing is the whole point: emptying the council list and sending
-- the oversized prefix anyway is what broke every receiver's pattern.
do
    Fresh()
    local prefix = "LC_CONFIG:4:" .. string.rep("L", 250) .. ":1:X:"
    local out = Build(prefix, "Bramor;Merrit")
    T.eq(out, nil, "a prefix that cannot fit returns nothing, so nothing is sent")
    T.truthy(Said("too long"), "and says so rather than failing silently")
    T.truthy(not Said("truncated"), "and does not also claim it merely shortened the list")
end

do
    Fresh()
    -- Exactly no room left: the budget is zero, which is the boundary `budget <= 0` guards.
    local prefix = string.rep("L", 255)
    T.eq(Build(prefix, "Bramor"), nil, "a prefix of exactly 255 bytes leaves no budget and is refused")
    T.truthy(Said("too long"), "with the same message")
end

-- Multi-byte names ----------------------------------------------------------------------------------
-- The budget is in BYTES and a German umlaut is two of them. A cut that counted characters would
-- produce a payload over the cap while reporting itself as within it.
do
    Fresh()
    local prefix = "LC_CONFIG:4:B:1:X:"
    local council = string.rep("Wölfchen;", 40)
    local out = Build(prefix, council)
    T.truthy(#out <= 255, "a council list of umlaut names is cut by bytes, not by characters")
    T.truthy(Said("truncated"), "and reports that it was cut")
end
