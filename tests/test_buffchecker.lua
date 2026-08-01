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

-- ==========================================================================
--  The render, and the missing-buff list it produces
-- ==========================================================================
-- KART.MissingBuffs is what /Report sends, and it is filled by the render pass -- which had never
-- run: C_UnitAuras and GetReadyCheckStatus were both absent from the harness, and the aura loop is
-- the first thing UpdateBuffCheck does per player.

-- Builds the window for `client` and renders it. UpdateStyles and CreateTabTitle live in files the
-- harness does not load (Core.lua, MainFrame.lua) and only restyle what is already built.
local function Render(client)
    RaidSim.As(client, function()
        client.KART.CreateTabTitle = client.KART.CreateTabTitle or function() end
        client.KART.UpdateStyles = client.KART.UpdateStyles or function() end
        if not client.KART.BuffCheckFrame then client.KART.CreateBuffCheckFrame() end
        client.KART.UpdateBuffCheck()
    end)
    return client.KART.MissingBuffs or {}
end

local function Names(list)
    local out = {}
    for _, n in ipairs(list or {}) do out[#out + 1] = n end
    table.sort(out)
    return table.concat(out, ",")
end

local function HasName(list, name)
    for _, n in ipairs(list or {}) do if n:find(name, 1, true) then return true end end
    return false
end

do
    -- A flask is matched by NAME, not by spell id -- there is one per stat every tier and the list
    -- would go stale every patch. The three spellings the addon accepts are the two locales plus the
    -- older "Flask".
    local sim, lm = F.NewRaid()
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    KARTTEST.auras = {
        [alric.unit] = { { name = "Fläschchen der launischen Winde", spellId = 431972 } },
        [sinja.unit] = { { name = "Phial of Tepid Versatility", spellId = 431972 } },
    }
    local missing = Render(lm)
    T.truthy(not HasName(missing.flask, "Alric"), "a raider carrying a Fläschchen is not reported")
    T.truthy(not HasName(missing.flask, "Sinja"), "nor one carrying a Phial")
    T.truthy(HasName(missing.flask, "Bramor"), "and one carrying neither is")
end

do
    -- Expiring is a warning, not an absence: the raider HAS the buff, and putting them on the
    -- "these people have no flask" list would be wrong.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Flask of Power", spellId = 1, expirationTime = GetTime() + 60 } },
    }
    local missing = Render(lm)
    T.truthy(not HasName(missing.flask, "Alric"),
        "a flask about to run out still counts as having one")
end

do
    -- Class buffs are only asked for when somebody in the raid can cast them. Without this the
    -- report reads out a list of people who "forgot" a buff no one present has.
    -- The fixture raid is DK, druid, paladin, mage, priest: a mage is there, no warrior is. The
    -- class list is rebuilt from the roster on every render, so this is the raid deciding it and
    -- not the test.
    local sim, lm = F.NewRaid()
    KARTTEST.auras = {}
    local missing = Render(lm)
    T.eq(Names(missing.shout), "",
        "with no warrior in the group nobody is reported as missing Battle Shout")
    T.truthy(#(missing.int or {}) > 0,
        "while the mage's buff, which somebody present can cast, is asked for")
    T.truthy(sim ~= nil)
end

do
    -- Matching by spell id, which is how the class buffs are found. 1459 is Arcane Intellect, and
    -- the fixture's mage makes the column live.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Arkane Intelligenz", spellId = 1459 } },
    }
    local missing = Render(lm)
    T.truthy(not HasName(missing.int, "Alric"), "the buff is recognised by its spell id")
    T.truthy(HasName(missing.int, "Bramor"), "and its absence still is")
end

do
    -- A private aura carries values that throw when compared. The loop pcalls the comparison for
    -- exactly this reason; one such aura must not take the rest of that player's auras with it.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    local secret = setmetatable({ name = "Private" }, {
        __index = function(_, k)
            if k == "spellId" then error("secret value") end
            return nil
        end,
    })
    KARTTEST.auras = {
        [alric.unit] = { secret, { name = "Flask of Power", spellId = 2 } },
    }
    local ok = pcall(Render, lm)
    T.truthy(ok, "a private aura does not take the whole render down")
    T.truthy(not HasName(lm.KART.MissingBuffs.flask, "Alric"),
        "and the aura after it is still read")
end

do
    -- The name-match path, which is the only one carrying a localisation trap: Skyfury is matched
    -- by the German AND the English name, because a raid runs both clients and the buff is read off
    -- whatever the VIEWER's client calls it.
    --
    -- Checked on the indicator rather than through /Report: a shaman buff is only reported when a
    -- shaman is present, and the fixture has none -- which is exactly what makes the two states
    -- distinguishable here. The indicator's alpha is the render's own answer: 1.0 for a buff that
    -- is there, 0.1 for a column nobody in the raid can fill.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    local SKY = 6            -- KART.BuffData index of the shaman buff
    local ALRIC_ROW = 4      -- raid4, the fixture's fourth member

    KARTTEST.auras = {}
    Render(lm)
    local ind = lm.KART.BuffCheckFrame.rows[ALRIC_ROW].indicators[SKY]
    T.eq(ind:GetAlpha(), 0.1, "with no shaman present the column is dimmed out entirely")

    KARTTEST.auras = { [alric.unit] = { { name = "Himmelszorn", spellId = 0 } } }
    Render(lm)
    T.eq(ind:GetAlpha(), 1.0, "a buff matched by its German name reads as present")

    KARTTEST.auras = { [alric.unit] = { { name = "Skyfury", spellId = 0 } } }
    Render(lm)
    T.eq(ind:GetAlpha(), 1.0, "and so does the English one, on a client running either language")

    KARTTEST.auras = { [alric.unit] = { { name = "Skyfury Totem is not it", spellId = 0 } } }
    Render(lm)
    T.eq(ind:GetAlpha(), 1.0, "matching is by substring, as the spell names carry suffixes")
end

-- ==========================================================================
--  Truncating a name that does not fit its column
-- ==========================================================================
-- WoW FontStrings do not ellipsize: text wider than the string's width overflows into whatever is
-- anchored next to it. The buff check truncates by binary search, and every step of that search cuts
-- the string at a BYTE index -- so on a German realm, where an umlaut is two bytes, the cut can land
-- inside a character and render as a broken box.
--
-- Lifted out of the source rather than driven through a render: the two functions are pure, and what
-- is under test is where they cut, not what the row looks like.
do
    local src = assert(io.open("BuffChecker.lua", "r")):read("*a")
    local floor = src:match("\nlocal function Utf8Floor%(s, i%).-\nend\n")
    local trunc = src:match("\nlocal function SetTruncatedName%(fontString, text, maxWidth%).-\nend\n")
    T.truthy(floor and trunc, "both truncation helpers were found in BuffChecker.lua")

    local chunk = assert(loadstring(floor .. trunc .. "\nreturn SetTruncatedName"))
    local SetTruncatedName = chunk()

    -- A stand-in FontString whose width is proportional to its BYTE length, which is what the
    -- harness's own GetStringWidth does and what makes the search take its steps at all.
    local function NewString()
        local fs, value = {}, ""
        function fs:SetText(t) value = t end
        function fs:GetText() return value end
        function fs:GetStringWidth() return #value * 6 end
        return fs
    end

    -- Valid UTF-8, checked by walking it: a lead byte announces how many continuation bytes follow,
    -- and a cut inside a character leaves either a lone continuation byte or a lead byte with too
    -- few of them.
    local function IsValidUTF8(s)
        local i = 1
        while i <= #s do
            local b = s:byte(i)
            local extra
            if b < 0x80 then extra = 0
            elseif b >= 0xF0 then extra = 3
            elseif b >= 0xE0 then extra = 2
            elseif b >= 0xC0 then extra = 1
            else return false end          -- continuation byte where a character should start
            for k = 1, extra do
                local c = s:byte(i + k)
                if not c or c < 0x80 or c >= 0xC0 then return false end
            end
            i = i + extra + 1
        end
        return true
    end

    do
        local fs = NewString()
        SetTruncatedName(fs, "Alric", 600)
        T.eq(fs:GetText(), "Alric", "a name that fits is left alone")
    end

    do
        local fs = NewString()
        SetTruncatedName(fs, "Verylongcharactername-Silvermoon", 60)
        local out = fs:GetText()
        T.truthy(#out * 6 <= 60, "a name that does not fit is cut down to the width")
        T.eq(out:sub(-3), "...", "and says so")
    end

    do
        -- Every cut position, on a name full of two-byte characters: at some width the search tries,
        -- the cut lands between the two halves of a glyph.
        local name = "Wölfeäöüß-Blackmoore"
        local checked = 0
        for width = 12, 240, 6 do
            local fs = NewString()
            SetTruncatedName(fs, name, width)
            local out = fs:GetText()
            checked = checked + 1
            if not IsValidUTF8(out) then
                T.truthy(false, "cut at width " .. width .. " left a half character: " .. out)
                break
            end
        end
        T.truthy(checked > 20, "every cut width was tried")
        T.truthy(IsValidUTF8("Wölfe"), "the validator itself accepts a whole umlaut")
        -- string.char, not an escape: 0xC3 is the lead byte of every German umlaut, and it must
        -- be rejected when the byte completing it is gone -- which is what a cut in the wrong
        -- place leaves behind.
        T.truthy(not IsValidUTF8("W" .. string.char(195)),
            "and rejects a lead byte with nothing after it")
    end

    do
        -- Narrower than the ellipsis itself. Anything is better than an empty column, and an empty
        -- string is what the search returns on its own.
        local fs = NewString()
        SetTruncatedName(fs, "Alricsson", 6)
        T.eq(fs:GetText(), "...", "a column too narrow for anything still shows the ellipsis")
    end
end
