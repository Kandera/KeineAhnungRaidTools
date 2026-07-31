-- LC_VOTE payload parsing.
--
-- The offline harness loads libraries, not addon files -- LootCouncilVote.lua needs the addon's
-- vararg table and a live WoW to load at all. So this lifts ParseVotePayload out of the source and
-- compiles just that function. Testing a copy pasted in here would pass forever after the real one
-- changed, which is worse than no test.
--
-- What makes this worth testing: a vote note is free text and keeps its colons, and two fields sit
-- in front of it. Get that wrong and a note like "5:30 uhr", or one beginning "#2:", is read as data
-- -- truncating what the raider wrote and fabricating a value nobody sent, which then either wrongly
-- trips or wrongly satisfies the vote-label mismatch check (B53).

local source = assert(io.open("LootCouncilVote.lua", "r"))
local text = source:read("*a")
source:close()

local fn = text:match("\nlocal function ParseVotePayload%(payload%).-\nend\n")
T.truthy(fn, "ParseVotePayload was found in LootCouncilVote.lua")

local chunk = assert(loadstring(fn .. "\nreturn ParseVotePayload"))
local ParseVotePayload = chunk()
T.eq(type(ParseVotePayload), "function", "ParseVotePayload compiles standalone")

local function check(label, payload, eRoll, eIdx, eCount, eNote, eItem)
    local r, i, c, n, item = ParseVotePayload(payload)
    T.eq(r, eRoll, label .. " -- rollID")
    T.eq(i, eIdx, label .. " -- index")
    T.eq(c, eCount, label .. " -- fingerprint")
    T.eq(n, eNote, label .. " -- note")
    if eItem ~= nil then T.eq(item, eItem, label .. " -- itemID") end
end

-- The current shape: "rollID:idx:#fingerprint:@itemID:note" ---------------------------------------
check("with note",         "12:3:#6:@249331:brauche ich", 12, 3, 6,  "brauche ich", "249331")
check("empty note",        "12:3:#6:@249331:",            12, 3, 6,  "",            "249331")
check("note with colons",  "12:3:#6:@249331:um 5:30 uhr", 12, 3, 6,  "um 5:30 uhr", "249331")
check("note starting #",   "12:3:#6:@249331:#1 prio",     12, 3, 6,  "#1 prio",     "249331")
check("unknown item",      "12:3:#6:@:noch nix",          12, 3, 6,  "noch nix",    "")
check("long fingerprint",  "12:3:#1549745886:@1:x",       12, 3, 1549745886, "x",   "1")

-- B53: a legacy note that LOOKS like the optional fields ------------------------------------------
-- 3.0.x sent "rollID:idx:note" with no markers at all, so a note beginning "#2:" was read as a
-- fingerprint -- truncating what the raider wrote and fabricating a value nobody sent, which then
-- either wrongly tripped or wrongly satisfied the mismatch check. No single-marker format can be
-- made unambiguous against free text that keeps its colons; requiring BOTH markers can.
check("legacy note '#2: nope'", "12:3:#2: nope",       nil, nil, nil, nil)
check("legacy note '5:30 uhr'", "12:3:5:30 uhr",       nil, nil, nil, nil)
check("legacy plain note",      "12:3:brauche ich",    nil, nil, nil, nil)
check("one marker only",        "12:3:#6:brauche ich", nil, nil, nil, nil)

-- Malformed --------------------------------------------------------------------------------------
check("garbage rejected",     "abc",                 nil, nil, nil, nil)
