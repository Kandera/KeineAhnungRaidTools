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

-- LC_VOTES: several votes in one message ---------------------------------------------------------
--
-- The heartbeat carries every vote this client holds, and a note is free text that keeps its colons
-- AND may contain the separator itself. The note is therefore length-prefixed: read exactly that
-- many bytes, and what follows is either ";" or the end. Nothing is escaped, so nothing has to be
-- un-escaped, and the sender's copy stays byte-identical to what the receivers store.
local votesFn = text:match("\nlocal function ParseVotesPayload%(payload%).-\nend\n")
T.truthy(votesFn, "ParseVotesPayload was found in LootCouncilVote.lua")

local ParseVotesPayload = assert(loadstring(votesFn .. "\nreturn ParseVotesPayload"))()
T.eq(type(ParseVotesPayload), "function", "ParseVotesPayload compiles standalone")

do
    local entries = ParseVotesPayload("12:3:#6:@249331:11:brauche ich")
    T.truthy(entries, "a single entry parses")
    T.eq(#entries, 1, "and is one entry")
    T.eq(entries[1].rollID, 12, "rollID")
    T.eq(entries[1].idx, 3, "index")
    T.eq(entries[1].count, 6, "fingerprint")
    T.eq(entries[1].item, "249331", "itemID")
    T.eq(entries[1].note, "brauche ich", "note")
end

do
    local entries = ParseVotesPayload("12:3:#6:@249331:0:;13:1:#6:@249293:0:;14:2:#6:@:0:")
    T.truthy(entries, "three entries parse")
    T.eq(#entries, 3, "all three")
    T.eq(entries[2].rollID, 13, "the second one's rollID")
    T.eq(entries[3].item, "", "an unknown item is an empty field, not a missing one")
end

-- The whole reason for the length prefix ----------------------------------------------------------
do
    local note = "trade um 5:30; sonst mainspec"
    local entries = ParseVotesPayload("12:3:#6:@249331:" .. #note .. ":" .. note
        .. ";13:1:#6:@249293:0:")
    T.truthy(entries, "a note containing the separator still parses")
    T.eq(entries[1].note, note, "and arrives byte for byte")
    T.eq(#entries, 2, "without swallowing the entry behind it")
    T.eq(entries[2].rollID, 13, "which is still readable")
end

-- Framing that does not add up says nothing at all, rather than half of something ------------------
-- The length prefix IS the framing: an entry whose frame is wrong tells us nothing about where the
-- next one starts, so reading on would be guessing. LC.HandleDrop treats an unreadable block the
-- same way, for the same reason -- and the repeat comes round again in five seconds anyway.
T.is_nil(ParseVotesPayload("12:3:#6:@249331:40:too short"), "a note shorter than it claims")
T.is_nil(ParseVotesPayload("12:3:#6:@249331:2:ok;garbage"), "a second entry that is not one")
T.is_nil(ParseVotesPayload("12:3:@249331:0:"), "a missing fingerprint marker")
T.is_nil(ParseVotesPayload("12:3:#6:249331:0:"), "a missing item marker")
T.is_nil(ParseVotesPayload(""), "an empty payload")
T.is_nil(ParseVotesPayload("abc"), "garbage")
