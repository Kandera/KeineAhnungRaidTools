-- BuffChecker's four incoming handlers, and the cache they write into.
--
-- OIL, ILVL, GEAR and ENCH are replies from OTHER people's clients. Nothing about their content is
-- ours: the sender may be on an older release, may have a corrupted SavedVariables, or may simply
-- be hostile -- the "KART" addon prefix is public and CHAT_MSG_ADDON also delivers whispers. Every
-- one of these handlers already validates its payload; none of them had a test, and this file is
-- 1161 lines that the suite had never executed a line of until 2026-08-01.
--
-- Driven through a real raid rather than by calling the handlers: what is being checked is that the
-- validation is WIRED, not that a local function works.

local F = dofile("tests/lc_fixture.lua")
local RaidSim = F.RaidSim

-- One raider answers a request. KASC drops a sender's own message, so this reaches everyone else.
local function Say(client, msg)
    RaidSim.As(client, function() client.KASC:Send(msg, "RAID") end)
    KARTTEST.AdvanceTime(0)
end

-- =====================================================================================
--  OIL -- an enchant id per hand, "0" for an empty weapon, "n" for a hand that takes none
-- =====================================================================================
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric

    Say(alric, "OIL:8052:n")
    local oil = lm.KART.OilCache and lm.KART.OilCache["Alric"]
    T.truthy(oil, "a well-formed oil reply is cached")
    T.eq(oil and oil.mh, 8052, "with the main hand's enchant id")
    T.eq(oil and oil.oh, "n", "and the off hand marked as taking none")

    -- Zero is a real answer, not a missing one: it means the weapon is there and carries nothing.
    -- It is also the one value that a truthiness check would silently drop, since 0 is truthy in Lua
    -- but a `tonumber` failure is not -- the two look alike to a careless guard.
    Say(alric, "OIL:0:0")
    oil = lm.KART.OilCache["Alric"]
    T.eq(oil.mh, 0, "an unoiled weapon reports 0 and is kept")
    T.eq(oil.oh, 0, "on both hands")
end

do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    Say(alric, "OIL:8052:n")
    local good = lm.KART.OilCache["Alric"]

    for _, bad in ipairs({ "OIL:abc:n", "OIL:8052", "OIL::", "OIL:8052:x", "OIL:-5:0",
                           "OIL:8052:n:extra" }) do
        Say(alric, bad)
        T.eq(lm.KART.OilCache["Alric"], good, "rejected and the last good answer stands: " .. bad)
    end
end

-- =====================================================================================
--  ILVL
-- =====================================================================================
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    Say(alric, "ILVL:289")
    T.eq(lm.KART.ILvlCache and lm.KART.ILvlCache["Alric"], 289, "an item level is cached")

    Say(alric, "ILVL:not a number")
    T.eq(lm.KART.ILvlCache["Alric"], 289, "text is refused and the real number stands")
end

-- =====================================================================================
--  GEAR -- two slot lists, and the reason they are validated rather than trusted
-- =====================================================================================
-- An unrecognized slot renders through string.format(BC_SLOT_FALLBACK, s), whose "%d" throws on
-- non-numeric input -- so one broken or hostile client could make the Advanced-view tooltip error on
-- every hover, for everyone. Rejecting the whole message is also what keeps a nonsense count out.
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric

    Say(alric, "GEAR:0:0")
    T.truthy(lm.KART.GearCache and lm.KART.GearCache["Alric"], "'nothing missing' is a valid answer")
    T.eq(lm.KART.GearCache["Alric"].enchants, "0", "and is stored as it arrived")

    Say(alric, "GEAR:3,8w,16:11,12")
    T.eq(lm.KART.GearCache["Alric"].enchants, "3,8w,16",
        "slot numbers, with the 'wrong enchant' suffix, are kept")
    T.eq(lm.KART.GearCache["Alric"].gems, "11,12", "and so is the gem list")

    local good = lm.KART.GearCache["Alric"]
    for _, bad in ipairs({ "GEAR:head:0", "GEAR:3,,8:0", "GEAR:,3:0", "GEAR:3,:0", "GEAR::0",
                           "GEAR:3:head", "GEAR:3x:0", "GEAR:0" }) do
        Say(alric, bad)
        T.eq(lm.KART.GearCache["Alric"], good, "rejected and the last good answer stands: " .. bad)
    end
end

-- =====================================================================================
--  ENCH -- a maintenance tally, where one bad entry drops the whole message
-- =====================================================================================
do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric

    Say(alric, "ENCH:1=7364,3=7356,oil=8052")
    local scan = lm.KART.EnchantScan and lm.KART.EnchantScan["Alric"]
    T.truthy(scan, "an enchant dump is cached")
    T.eq(scan and scan[1], "7364", "keyed by slot number")
    T.eq(scan and scan.oil, "8052", "with the temporary weapon enchant under its own key")

    Say(alric, "ENCH:1=7364,head=7356")
    T.eq(lm.KART.EnchantScan["Alric"][1], "7364",
        "a non-numeric slot drops the whole message rather than half of it")
    T.is_nil(lm.KART.EnchantScan["Alric"].head, "so the bad entry never lands")
end

-- =====================================================================================
--  Departed peers
-- =====================================================================================
-- All five caches are keyed by short name and were never cleared (B17). Data for someone who left
-- rendered exactly like fresh data, and worse: if Bob left and a different Bob joined, the new one
-- silently inherited the old one's oil, gear, item level and durability.
do
    local sim, lm = F.NewRaid()
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    Say(alric, "OIL:8052:n")
    Say(alric, "ILVL:289")
    Say(sinja, "ILVL:291")
    T.truthy(lm.KART.OilCache["Alric"], "the raider's data is cached")

    RaidSim.Leave(sim, "Alric")
    RaidSim.As(lm, function() lm.KART.PruneDepartedPeers() end)

    T.is_nil(lm.KART.OilCache["Alric"], "and dropped once they leave the raid")
    T.is_nil(lm.KART.ILvlCache["Alric"], "every cache, not just the first")
    T.eq(lm.KART.ILvlCache["Sinja"], 291, "while everyone still here keeps theirs")
end

-- =====================================================================================
--  /Report -- the one thing here that writes into raid chat
-- =====================================================================================
-- SendChatMessage takes at most 255 bytes. A longer line is not truncated into something the raid
-- can still read: it does not arrive at all. Two of the twelve checks report NAMES ("food" and
-- "flask", the two most commonly missing things in any raid), and the list was concatenated into one
-- message however long it came out -- so on the pull where fifteen people have no food, the report
-- silently did nothing. Worst exactly when it matters most, with nothing printed on either side.
do
    local _, lm = F.NewRaid()

    -- A realistic bad pull: fifteen people without food, several of them cross-realm, which is where
    -- the names get long. Nothing exotic -- a raid night before the first boss.
    local missing = {}
    for i = 1, 15 do missing[i] = "Raidmember" .. i .. "-Silvermoon" end
    lm.KART.MissingBuffs = { food = missing }

    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)

    T.truthy(#KARTTEST.chat > 0, "the report says something at all")
    local refused, joined = 0, {}
    for _, m in ipairs(KARTTEST.chat) do
        if m.refused then refused = refused + 1 end
        joined[#joined + 1] = m.msg
    end
    T.eq(refused, 0, "and no line of it is over the length the client will accept")

    -- Splitting is only worth anything if nothing falls out in the process.
    local all = table.concat(joined, " ")
    local found = 0
    for _, name in ipairs(missing) do
        if all:find(name, 1, true) then found = found + 1 end
    end
    T.eq(found, #missing, "every missing player is named across the lines that were sent")
end

do
    -- The short case must not have become chatty: one line stays one line.
    local _, lm = F.NewRaid()
    lm.KART.MissingBuffs = { food = { "Alric", "Sinja" } }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)
    T.eq(#KARTTEST.chat, 1, "two names still go out as a single message")
    T.truthy(KARTTEST.chat[1].msg:find("Alric", 1, true)
         and KARTTEST.chat[1].msg:find("Sinja", 1, true), "with both of them on it")
end
