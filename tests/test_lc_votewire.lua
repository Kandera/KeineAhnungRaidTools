-- LC_VOTE payload parsing.
--
-- The offline harness loads libraries, not addon files -- LootCouncilVote.lua needs the addon's
-- vararg table and a live WoW to load at all. So this lifts ParseVotePayload out of the source and
-- compiles just that function. Testing a copy pasted in here would pass forever after the real one
-- changed, which is worse than no test.
--
-- What makes this worth testing: a vote note is free text and keeps its colons, while the button
-- count added in 3.1 is an optional field in front of it. Get that wrong and a note like
-- "5:30 uhr" is read as a count of 5, which silently marks a correct vote as unmatchable.

local source = assert(io.open("LootCouncilVote.lua", "r"))
local text = source:read("*a")
source:close()

local fn = text:match("\nlocal function ParseVotePayload%(payload%).-\nend\n")
T.truthy(fn, "ParseVotePayload was found in LootCouncilVote.lua")

local chunk = assert(loadstring(fn .. "\nreturn ParseVotePayload"))
local ParseVotePayload = chunk()
T.eq(type(ParseVotePayload), "function", "ParseVotePayload compiles standalone")

local function check(label, payload, eRoll, eIdx, eCount, eNote)
    local r, i, c, n = ParseVotePayload(payload)
    T.eq(r, eRoll, label .. " -- rollID")
    T.eq(i, eIdx, label .. " -- index")
    T.eq(c, eCount, label .. " -- count")
    T.eq(n, eNote, label .. " -- note")
end

-- 3.1 shape ------------------------------------------------------------------------------------
check("3.1 with note",        "12:3:#6:brauche ich", 12, 3, 6,  "brauche ich")
check("3.1 empty note",       "12:3:#6:",            12, 3, 6,  "")
check("3.1 note with colons", "12:3:#6:um 5:30 uhr", 12, 3, 6,  "um 5:30 uhr")
check("3.1 note starting #",  "12:3:#6:#1 prio",     12, 3, 6,  "#1 prio")
check("3.1 single button",    "7:1:#1:",              7, 1, 1,  "")
check("3.1 two-digit count",  "12:3:#12:x",          12, 3, 12, "x")

-- 3.0.x shape: still registers, just without a count --------------------------------------------
check("3.0 with note",        "12:3:brauche ich",    12, 3, nil, "brauche ich")
check("3.0 empty note",       "12:3:",               12, 3, nil, "")
check("3.0 no note field",    "12:3",                12, 3, nil, "")

-- The trap the "#" prefix exists for: a 3.0.x note shaped like a numeric field.
check("3.0 note '5:30 uhr'",  "12:3:5:30 uhr",       12, 3, nil, "5:30 uhr")
check("3.0 note '6:x'",       "12:3:6:x",            12, 3, nil, "6:x")

-- Malformed --------------------------------------------------------------------------------------
check("garbage rejected",     "abc",                 nil, nil, nil, "")
