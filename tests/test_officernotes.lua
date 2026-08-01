-- Officer notes: a standing council note about a PERSON, saved forever and broadcast on edit.
--
-- Two things make it worth its own file. It is persisted (KART_LCOfficerNotes) and rendered raw into
-- the council tooltip, so anything that gets in stays in and is displayed as-is -- and it is written
-- by other people's clients, so "what if the sender did not sanitise" is a real question rather than
-- a hypothetical. No test existed.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

local function Note(client, key) return client.env.KART_LCOfficerNotes[key] end

-- Writing and sharing ---------------------------------------------------------------------------
do
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(alric.guid, "has BIS trinket")
    end)
    KARTTEST.AdvanceTime(0)

    T.eq(Note(council, alric.guid), "has BIS trinket", "the note is stored where it was written")
    T.eq(Note(lm, alric.guid), "has BIS trinket", "and reaches the other council members")
end

do
    -- Empty clears it. The dialog allows an empty input for exactly this.
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(alric.guid, "temporary")
    end)
    KARTTEST.AdvanceTime(0)
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(alric.guid, "")
    end)
    KARTTEST.AdvanceTime(0)
    T.is_nil(Note(council, alric.guid), "an empty note clears it locally")
    T.is_nil(Note(lm, alric.guid), "and everywhere else")
end

-- What may not get in ---------------------------------------------------------------------------
do
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    RaidSim.As(council, function()
        council.KART.LC.OfficerNotes.SetOfficerNote(alric.guid, "a:b|cffff0000red")
    end)
    KARTTEST.AdvanceTime(0)

    -- The colon is the payload separator: one in the text would shift every capture after it.
    T.truthy(not Note(council, alric.guid):find(":", 1, true), "a colon is stripped before storing")
    T.truthy(not Note(council, alric.guid):find("|", 1, true), "and so is a pipe")
    T.eq(Note(lm, alric.guid), Note(council, alric.guid),
        "both sides end up with byte-identical text, which is what keeps the raid consistent")
end

do
    -- Straight off the wire, from a client that did not sanitise. It is stored forever and rendered
    -- raw in a tooltip, so an escape sequence here would colour text, fake a hyperlink or draw a
    -- texture in every council member's UI for good.
    local sim, lm, council = F.NewRaid()
    local alric = sim.byName.Alric
    RaidSim.As(council, function()
        council.KASC:Send("LC_ONOTE:" .. alric.guid .. ":evil|cffff0000red", "RAID")
    end)
    KARTTEST.AdvanceTime(0)
    T.eq(Note(lm, alric.guid), "evil||cffff0000red",
        "a pipe that arrives over the wire is escaped rather than trusted")
end

do
    -- Authority: this overwrites a persistent note on every council member's client, so a raider
    -- cannot write one.
    local sim, lm = F.NewRaid()
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    RaidSim.As(alric, function()
        alric.KASC:Send("LC_ONOTE:" .. sinja.guid .. ":not from a raider", "RAID")
    end)
    KARTTEST.AdvanceTime(0)
    T.is_nil(Note(lm, sinja.guid), "a note from somebody who is not council is refused")
end

-- Migrating a pre-GUID note ------------------------------------------------------------------------
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    lm.env.KART_LCOfficerNotes["alric"] = "written before GUIDs existed"
    RaidSim.As(lm, function() lm.KART.LC.OfficerNotes.MigrateOfficerNoteKey("alric") end)

    T.eq(Note(lm, alric.guid), "written before GUIDs existed", "a legacy note moves onto the GUID key")
    T.is_nil(Note(lm, "alric"), "and the old key is cleared")
end

do
    -- Somebody the client has never seen: left alone rather than dropped, and retried on the next
    -- roster change. A note silently lost is worse than one that has not migrated yet.
    local _, lm = F.NewRaid()
    lm.env.KART_LCOfficerNotes["nieGesehen"] = "still worth keeping"
    local moved = RaidSim.As(lm, function()
        return lm.KART.LC.OfficerNotes.MigrateOfficerNoteKey("nieGesehen")
    end)
    T.eq(moved, false, "an unresolvable name does not migrate")
    T.eq(Note(lm, "nieGesehen"), "still worth keeping", "and its note is still there")
end

do
    -- A note already written under the resolved key is the newer one and wins; the legacy entry goes
    -- rather than overwriting it.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    lm.env.KART_LCOfficerNotes["alric"] = "old text"
    lm.env.KART_LCOfficerNotes[alric.guid] = "current text"
    RaidSim.As(lm, function() lm.KART.LC.OfficerNotes.MigrateOfficerNoteKey("alric") end)
    T.eq(Note(lm, alric.guid), "current text", "the newer note is not clobbered by the older one")
    T.is_nil(Note(lm, "alric"), "and the legacy entry is gone")
end
