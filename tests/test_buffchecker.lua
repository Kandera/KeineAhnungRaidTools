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
-- KART.MissingBuffs is what /Report sends. The scan fills it without a window; paint only
-- needs the frame for "this indicator is red".

local function Scan(client)
    local missing
    RaidSim.As(client, function()
        client.KART.ScanBuffRoster()
        missing = client.KART.MissingBuffs or {}
    end)
    return missing
end

-- Builds the window for `client` and paints it. UpdateStyles and CreateTabTitle live in files the
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
    -- A flask is matched by this season's spell ids, with a name fallback — there is one
    -- buff per stat, and a new flask whose id is not in the list yet still has to count.
    -- The three spellings the fallback accepts are the two locales plus the older "Flask".
    local sim, lm = F.NewRaid()
    local alric, sinja = sim.byName.Alric, sim.byName.Sinja
    KARTTEST.auras = {
        [alric.unit] = { { name = "Fläschchen der launischen Winde", spellId = 431972 } },
        [sinja.unit] = { { name = "Phial of Tepid Versatility", spellId = 431972 } },
    }
    local missing = Scan(lm)
    T.eq(lm.KART.BuffCheckFrame, nil, "the scan does not build the Buff Check window")
    T.truthy(not HasName(missing.flask, "Alric"), "a raider carrying a Fläschchen is not reported")
    T.truthy(not HasName(missing.flask, "Sinja"), "nor one carrying a Phial")
    T.truthy(HasName(missing.flask, "Bramor"), "and one carrying neither is")
end

do
    -- Season spell ids (same source as the Healthstone item list: Northern Sky's ready-check
    -- consumables on this client). The name fallback above still covers a flask whose id is
    -- not in the list yet; a known id must match even when the aura name is secret or renamed.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Private", spellId = 1235111 } },
    }
    local missing = Scan(lm)
    T.truthy(not HasName(missing.flask, "Alric"),
        "a flask matched by this season's spell id is not reported missing")
end

do
    -- Expiring is a warning, not an absence: the raider HAS the buff, and putting them on the
    -- "these people have no flask" list would be wrong.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Flask of Power", spellId = 1, expirationTime = GetTime() + 60 } },
    }
    local missing = Scan(lm)
    T.truthy(not HasName(missing.flask, "Alric"),
        "a flask about to run out still counts as having one")
end

do
    -- Class buffs are only asked for when somebody in the raid can cast them. Without this the
    -- report reads out a list of people who "forgot" a buff no one present has.
    -- The fixture raid is DK, druid, paladin, mage, priest: a mage is there, no warrior is. The
    -- class list is rebuilt from the roster on every render, so this is the raid deciding it and
    -- not the test.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    local missing = Scan(lm)
    T.eq(Names(missing.shout), "",
        "with no warrior in the group nobody is reported as missing Battle Shout")
    T.truthy(#(missing.int or {}) > 0,
        "while the mage's buff, which somebody present can cast, is asked for")
end

do
    -- Matching by spell id, which is how the class buffs are found. 1459 is Arcane Intellect, and
    -- the fixture's mage makes the column live.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Arkane Intelligenz", spellId = 1459 } },
    }
    local missing = Scan(lm)
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
    local ok = pcall(Scan, lm)
    T.truthy(ok, "a private aura does not take the whole scan down")
    T.truthy(not HasName(lm.KART.MissingBuffs.flask, "Alric"),
        "and the aura after it is still read")
end

do
    -- 12.1: GetAuraDataByIndex Lua-errors while auras are secret and the addon is tainted
    -- (combat / encounter / M+ / PvP). That used to abort the whole row loop. The render must
    -- survive, and known spell IDs must still be found via GetUnitAuraBySpellID.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    KARTTEST.auras = {
        [alric.unit] = { { name = "Arkane Intelligenz", spellId = 1459 } },
    }
    local realIndex = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function()
        error("Auras cannot be accessed when secret while tainted by 'KeineAhnungRaidTools'")
    end
    local ok, missing = pcall(Scan, lm)
    C_UnitAuras.GetAuraDataByIndex = realIndex
    T.truthy(ok, "a secret index scan does not take the whole scan down")
    T.truthy(ok and missing and not HasName(missing.int, "Alric"),
        "and the buff is still found by spell id")
end

do
    -- Same refusal, but without the spell-id API (older client / missing stub). Still no error.
    local _, lm = F.NewRaid()
    local realIndex, realById = C_UnitAuras.GetAuraDataByIndex, C_UnitAuras.GetUnitAuraBySpellID
    C_UnitAuras.GetAuraDataByIndex = function() error("secret") end
    C_UnitAuras.GetUnitAuraBySpellID = nil
    local ok = pcall(Scan, lm)
    C_UnitAuras.GetAuraDataByIndex, C_UnitAuras.GetUnitAuraBySpellID = realIndex, realById
    T.truthy(ok, "a refused index scan with no spell-id API still does not error")
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

do
    -- The line the split cannot make shorter: one name that, with the label in front of it, is
    -- already over the cap. That case is documented at SplitNameLines as deliberate -- it "cannot be
    -- helped", so the line goes out and the client refuses THAT ONE.
    --
    -- What must not happen is it taking the rest with it. Everybody else missing food is still worth
    -- reporting, and the only thing standing between them and silence is that the split keeps them on
    -- their own line.
    local _, lm = F.NewRaid()
    local names = { string.rep("N", 300) }
    for i = 1, 6 do names[#names + 1] = "Raider" .. i .. "-Silvermoon" end
    lm.KART.MissingBuffs = { food = names }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)

    local delivered, refused = {}, 0
    for _, m in ipairs(KARTTEST.chat) do
        if m.refused then refused = refused + 1 else delivered[#delivered + 1] = m.msg end
    end
    T.eq(refused, 1, "the one impossible line is the only one the client refuses")
    local all = table.concat(delivered, " ")
    local found = 0
    for i = 1, 6 do if all:find("Raider" .. i .. "-", 1, true) then found = found + 1 end end
    T.eq(found, 6, "and every other name still reaches the raid")
end

-- ==========================================================================
--  Where the split puts its line break
-- ==========================================================================
-- The cap is the LAST length that still goes out, not the first that does not. Lifted from the
-- source for the same reason the truncation helpers are: the amount that matters is a single byte,
-- and driving it through a render would put a locale-dependent label in front of it.
do
    local src = assert(io.open("BuffChecker.lua", "r")):read("*a")
    local split = src:match("\nlocal function SplitNameLines%(prefix, names%).-\nend\n")
    T.truthy(split, "the split helper was found in BuffChecker.lua")
    local SplitNameLines = assert(loadstring("local CHAT_MSG_MAX = 255\n" .. split
        .. "\nreturn SplitNameLines"))()

    -- "P: " + 100 + ", " + 150 is 255 on the nose.
    local exact = SplitNameLines("P: ", { string.rep("a", 100), string.rep("b", 150) })
    T.eq(#exact, 1, "a line of exactly 255 bytes is one line")
    T.eq(#exact[1], 255, "and goes out whole")

    -- One more byte, and only then does it become two.
    local over = SplitNameLines("P: ", { string.rep("a", 100), string.rep("b", 151) })
    T.eq(#over, 2, "256 bytes is where it breaks")
    T.truthy(#over[1] <= 255 and #over[2] <= 255, "with both halves inside the cap")
    T.eq(over[2]:sub(1, 3), "P: ", "and the label repeated, so the second line still says what it is")
end

do
    -- A buff nobody is missing. The list is built per buff and can be empty for any of them -- the
    -- ordinary case, since a raid usually fails only one or two checks.
    --
    -- The empty list has to be caught HERE and not left to the split below, and the reason is that
    -- the two report kinds are not alike. A named check ("food", "flask") splits its names into
    -- lines and an empty list happens to produce none. A class-buff check is a headline with no
    -- names at all -- so an empty one still posts "Missing Arcane Intellect" into raid chat, naming
    -- nobody, on a pull where everybody had it.
    local _, lm = F.NewRaid()
    lm.KART.MissingBuffs = { int = {}, food = {}, flask = { "Alric" } }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)

    T.eq(#KARTTEST.chat, 1, "only the buff somebody is actually missing is reported")
    T.truthy(KARTTEST.chat[1].msg:find("Alric", 1, true), "and it is that one")

    -- The same check with somebody on it, so the assertion above is known to be able to move.
    lm.KART.MissingBuffs = { int = { "Sinja" } }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)
    T.eq(#KARTTEST.chat, 1, "a class buff somebody IS missing is still announced")
end

-- ==========================================================================
--  Truncation cuts at the LONGEST place that fits
-- ==========================================================================
-- The existing walk above proves the cut never lands inside a character. It does not prove the cut
-- is in the right place: a search that stops one step early returns a shorter name that is still
-- valid UTF-8, still ends in "...", and still fits the column -- so every assertion there passes
-- while the name column throws away a character it had room for on every single row.
do
    local src = assert(io.open("BuffChecker.lua", "r")):read("*a")
    local floor = src:match("\nlocal function Utf8Floor%(s, i%).-\nend\n")
    local trunc = src:match("\nlocal function SetTruncatedName%(fontString, text, maxWidth%).-\nend\n")
    local chunk = assert(loadstring(floor .. trunc .. "\nreturn SetTruncatedName, Utf8Floor"))
    local SetTruncatedName, Utf8Floor = chunk()

    local function NewString()
        local fs, value = {}, ""
        function fs:SetText(t) value = t end
        function fs:GetText() return value end
        function fs:GetStringWidth() return #value * 6 end
        return fs
    end

    -- The answer, worked out by trying every cut rather than by searching: the longest candidate
    -- that fits, or the whole name when it already does. The last line mirrors the source's own
    -- floor -- below the width of the ellipsis nothing fits, and an ellipsis beats an empty column.
    local function Longest(text, maxWidth)
        if #text * 6 <= maxWidth then return text end
        local best = ""
        for m = 1, #text do
            local cand = text:sub(1, Utf8Floor(text, m)) .. "..."
            if #cand * 6 <= maxWidth then best = cand end
        end
        return best ~= "" and best or "..."
    end

    local names = { "Alricsson", "Verylongcharactername-Silvermoon", "Wölfeäöüß-Blackmoore" }
    local checked = 0
    for _, name in ipairs(names) do
        for width = 6, #name * 6 + 12, 6 do
            local fs = NewString()
            SetTruncatedName(fs, name, width)
            checked = checked + 1
            if fs:GetText() ~= Longest(name, width) then
                T.eq(fs:GetText(), Longest(name, width),
                    "the cut of " .. name .. " at width " .. width .. " uses all the room there is")
                break
            end
        end
    end
    T.truthy(checked > 60, "every width was tried on every name")
    T.truthy(true, "the cut always uses all the room there is")

    -- The boundary at the top of the function, which decides whether anything is cut at all: a name
    -- exactly as wide as its column fits, so it must keep its last character instead of losing it
    -- to an ellipsis that is wider than what it replaced.
    local fs = NewString()
    SetTruncatedName(fs, "Alric", 5 * 6)
    T.eq(fs:GetText(), "Alric", "a name exactly as wide as the column is left whole")
end

-- ==========================================================================
--  The ready-check column
-- ==========================================================================
do
    -- Three statuses have an icon. Anything else -- a status Blizzard adds, or a value that arrived
    -- from somewhere it should not have -- has none, and the column has to stay EMPTY rather than
    -- show a texture built out of the status itself, which draws as a green-and-black grid.
    local _, lm = F.NewRaid()
    local icon = CreateFrame("Frame")
    RaidSim.As(lm, function() lm.KART.SetReadyCheckIcon(icon, "ready") end)
    T.truthy(icon:IsShown(), "a status with an icon shows one")
    RaidSim.As(lm, function() lm.KART.SetReadyCheckIcon(icon, "declined") end)
    T.truthy(not icon:IsShown(), "a status without one shows nothing at all")
    RaidSim.As(lm, function() lm.KART.SetReadyCheckIcon(icon, nil) end)
    T.truthy(not icon:IsShown(), "and neither does no status")
end

do
    -- The reason a raider gave for declining, which arrives on its own message and outlives the
    -- ready check itself. It is looked up by the raider's SHORT name -- with no name to look up,
    -- there is no reason to show, and the row must not fall back to showing the name as the reason.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    lm.KART.ReadyCheckReasons = { Alric = "afk, sorry" }
    Render(lm)
    local rows = lm.KART.BuffCheckFrame.rows
    T.eq(rows[4].reasonIcon.reasonText, "afk, sorry", "the raider who gave a reason carries it")
    T.truthy(not rows[5].reasonIcon:IsShown(), "and one who gave none shows no reason icon")
    lm.KART.ReadyCheckReasons = {}
end

-- ==========================================================================
--  The durability column
-- ==========================================================================
-- Three digits and a colour. The digits are the same at 19% and at 51%, so the colour is the entire
-- warning -- and it is read at a glance across forty rows, which is the only way it is ever read.
do
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    local REPAIR = 13
    local function ColorAt(percent)
        lm.KART.DurabilityCache = { Bramor = percent }
        Render(lm)
        local ind = lm.KART.BuffCheckFrame.rows[1].indicators[REPAIR]
        T.truthy(ind and ind.text, "the durability column is a framed number, not a plain icon")
        local r, g, b = ind.text:GetTextColor()
        return { r, g, b }
    end
    local function Same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

    T.truthy(Same(ColorAt(19), lm.KART.DANGER), "below 20 percent reads as danger")
    T.truthy(Same(ColorAt(20), lm.KART.WARNING), "exactly 20 is already only a warning")
    T.truthy(Same(ColorAt(49), lm.KART.WARNING), "and so is anything under 50")
    T.truthy(Same(ColorAt(50), lm.KART.SUCCESS), "exactly 50 is fine")
    T.truthy(Same(ColorAt(100), lm.KART.SUCCESS), "and so is a full set")
    lm.KART.DurabilityCache = {}
end

-- ==========================================================================
--  Missing, versus nobody here can give it to you
-- ==========================================================================
do
    -- Two different dimmed states that must not collapse into one. A column nobody in the raid can
    -- fill is dimmed to 0.1 and means "not your problem". A buff you are simply missing is dimmed to
    -- 0.6 in the danger colour and means "go get it". Rendering the second as the first is a raider
    -- reading their own row as fine.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    local FLASK = 8
    Render(lm)
    local ind = lm.KART.BuffCheckFrame.rows[4].indicators[FLASK]
    T.eq(ind:GetAlpha(), 0.6, "a flask nobody has is a raider's own problem, not a dead column")
    local r, g, b = ind:GetVertexColor()
    T.truthy(r == lm.KART.DANGER[1] and g == lm.KART.DANGER[2] and b == lm.KART.DANGER[3],
        "and it is shown in the colour that says so")
end

-- ==========================================================================
--  The preview flag
-- ==========================================================================
do
    -- The throttled refresh has no argument, so the window remembers which mode it is in. Remembered
    -- as "preview" while showing live data, every roster tick would redraw the raid as sample rows.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    Render(lm)
    T.eq(lm.KART.BuffCheckPreviewActive, false, "a live render is not remembered as a preview")
    RaidSim.As(lm, function() lm.KART.UpdateBuffCheck(true) end)
    T.eq(lm.KART.BuffCheckPreviewActive, true, "and a preview is")
    Render(lm)
    T.eq(lm.KART.BuffCheckPreviewActive, false, "and going back to live clears it again")
end

-- ==========================================================================
--  Somebody who is offline
-- ==========================================================================
do
    -- A disconnected raider's row is dimmed, because their data is the last thing anybody saw rather
    -- than what is true now. The dimming has to be an opacity: a boolean here is drawn as fully
    -- opaque, which is the one thing it must not look like.
    local sim, lm = F.NewRaid()
    KARTTEST.auras = {}
    lm.env.KART_Settings.grayOffline = true
    sim.byName.Alric.member.offline = true
    Render(lm)
    local rows = lm.KART.BuffCheckFrame.rows
    T.eq(type(rows[4]:GetAlpha()), "number", "the offline row's dimming is an opacity")
    T.truthy(rows[4]:GetAlpha() < rows[1]:GetAlpha(), "and it is dimmer than a connected one")
    sim.byName.Alric.member.offline = nil
end

-- ==========================================================================
--  A raid larger than the row pool
-- ==========================================================================
do
    -- Forty rows exist and the loop stops after the fortieth, which is a guard against an epic
    -- battleground rather than a raid size. Stopping one row early is the failure to watch for: in a
    -- full forty-man group the last person on the list is simply not checked, and their row keeps
    -- whatever the previous render left in it.
    local sim, lm = F.NewRaid()
    KARTTEST.auras = {}
    local members = {}
    for i, c in ipairs(sim.clients) do members[i] = c.member end
    for i = #members + 1, 40 do
        members[i] = { name = "Filler" .. i, realm = "TarrenMill",
                       guid = "Player-1096-FFFF" .. i, class = "WARRIOR" }
    end
    KARTTEST.SetRaid(members)
    Render(lm)
    T.eq(lm.KART.BuffCheckFrame.rows[40].name:GetText(), "Filler40",
        "the fortieth raider is checked like everybody else")
end

-- ==========================================================================
--  About to run out, versus already gone
-- ==========================================================================
do
    -- The amber "expiring" tint is a five-minute warning on a buff the raider still HAS. The
    -- boundary at the other end of that window is the one worth pinning: an aura whose expiry is
    -- exactly now has no time left, so it is not a warning to act on -- and the raider is about to
    -- be reported as missing it anyway, which is the louder of the two signals.
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    local FLASK = 8
    local ALRIC_ROW = 4

    KARTTEST.auras = { [alric.unit] = {
        { name = "Flask of Power", spellId = 1, expirationTime = GetTime() + 60 } } }
    Render(lm)
    local ind = lm.KART.BuffCheckFrame.rows[ALRIC_ROW].indicators[FLASK]
    local r, g, b = ind:GetVertexColor()
    T.truthy(r == 1 and g == 0.8 and b == 0, "a minute left is shown as running out")

    KARTTEST.auras = { [alric.unit] = {
        { name = "Flask of Power", spellId = 1, expirationTime = GetTime() } } }
    Render(lm)
    r, g, b = ind:GetVertexColor()
    T.truthy(r == 1 and g == 1 and b == 1, "no time left is not a warning about time running out")
end

-- ==========================================================================
--  The weapon oil, read off our own hands
-- ==========================================================================
do
    -- GetWeaponEnchantInfo answers per hand: whether there IS a temporary enchant, and its id. The
    -- id field is not cleared when the first answer is false -- it is simply not meaningful -- so
    -- the "has one" flag is what decides whether the id may be read at all. Reading it anyway rates
    -- a bare weapon by whatever oil was on it last, and the column then says the raider is fine.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    -- A bare key rather than a real link: the equip location is looked up in the flat table the
    -- gear-scan tests drive, which only answers for links the item database does not already know.
    KARTTEST.inventory[16] = "MainhandWeapon"
    KARTTEST.equipLocs.MainhandWeapon = "INVTYPE_WEAPONMAINHAND"

    -- Read off the player's own row rather than KART.BuffStatesCache: that table is wiped before
    -- every player and holds the LAST one rendered, which is never us.
    local OIL = 14
    local function OilColor()
        Render(lm)
        local r, g, b = lm.KART.BuffCheckFrame.rows[1].indicators[OIL]:GetVertexColor()
        return { r, g, b }
    end
    local function Same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

    KARTTEST.weaponEnchant = { true, 0, 0, 8052, false, 0, 0, 0 }
    T.truthy(Same(OilColor(), lm.KART.SUCCESS), "an oiled main hand reads as the current oil")

    -- Same id, same slot, but the hand carries nothing.
    KARTTEST.weaponEnchant = { false, 0, 0, 8052, false, 0, 0, 0 }
    T.truthy(Same(OilColor(), lm.KART.DANGER),
        "a bare main hand is not rated by the id left behind in the answer")

    -- And the same for the off hand, which a dual wielder has to keep oiled as well: the worst of
    -- the two hands is what the column shows, so a bare off hand next to an oiled main hand still
    -- reads as missing. Both hands answer out of the same eight-value reply and the off hand's
    -- fields sit at the far end of it, which is where a mistake is least likely to be noticed.
    KARTTEST.inventory[17] = "OffhandWeapon"
    KARTTEST.equipLocs.OffhandWeapon = "INVTYPE_WEAPONOFFHAND"
    KARTTEST.weaponEnchant = { true, 0, 0, 8052, true, 0, 0, 8052 }
    T.truthy(Same(OilColor(), lm.KART.SUCCESS), "two oiled hands read as the current oil")

    KARTTEST.weaponEnchant = { true, 0, 0, 8052, false, 0, 0, 8052 }
    T.truthy(Same(OilColor(), lm.KART.DANGER),
        "and a bare off hand pulls the column down even with the main hand oiled")

    KARTTEST.inventory[16], KARTTEST.inventory[17] = nil, nil
    KARTTEST.weaponEnchant = { false, 0, 0, 0, false, 0, 0, 0 }
end

-- =====================================================================================
--  Shift-click /Report whispers flask, food and rune to the people missing them
-- =====================================================================================
-- Raid chat stays the click. Whisper is a private poke for the three consumables a raider
-- can fix themselves; class buffs and the advanced panel stay out of it.
do
    local _, lm = F.NewRaid()
    lm.KART.MissingBuffs = {
        flask = { "Alric" },
        food  = { "Alric", "Sinja" },
        rune  = { "Sinja" },
        int   = { "Alric" },
    }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.WhisperMissingConsumables() end)
    KARTTEST.AdvanceTime(10)

    local byTarget = {}
    for _, m in ipairs(KARTTEST.chat) do
        T.eq(m.channel, "WHISPER", "consumable pokes go by whisper, not raid chat")
        byTarget[m.target] = (byTarget[m.target] or "") .. m.msg
    end
    T.truthy(byTarget.Alric, "Alric is whispered")
    T.truthy(byTarget.Sinja, "Sinja is whispered")
    T.truthy(byTarget.Alric:find("Flask", 1, true) or byTarget.Alric:find("Fläsch", 1, true),
        "Alric is told about flask")
    T.truthy(byTarget.Alric:find("Food", 1, true) or byTarget.Alric:find("Essen", 1, true),
        "and food, in one whisper")
    T.eq(not not (byTarget.Alric:find("Intellect", 1, true) or byTarget.Alric:find("Intelligenz", 1, true)),
        false, "class buffs are not whispered")
    T.is_nil(byTarget.Alric:find("Intellect", 1, true), "no intellect line in Alric's whisper")
end

do
    local _, lm = F.NewRaid()
    local me
    RaidSim.As(lm, function() me = UnitName("player") end)
    lm.KART.MissingBuffs = { flask = { me, "Alric" }, food = {}, rune = {} }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.WhisperMissingConsumables() end)
    KARTTEST.AdvanceTime(10)
    local toMe = 0
    for _, m in ipairs(KARTTEST.chat) do
        if m.target == me then toMe = toMe + 1 end
    end
    T.eq(toMe, 0, "the reporter is not whispered their own missing flask")
    T.eq(#KARTTEST.chat, 1, "the other missing player still is")
end

do
    local _, lm = F.NewRaid()
    lm.KART.MissingBuffs = { int = { "Alric" }, flask = {}, food = {}, rune = {} }
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.WhisperMissingConsumables() end)
    KARTTEST.AdvanceTime(10)
    T.eq(#KARTTEST.chat, 0, "a raid missing only a class buff produces no whispers")
end

do
    local _, lm = F.NewRaid()
    Render(lm)
    KARTTEST.modifiers.shift = true
    KARTTEST.ClearChat()
    lm.KART.MissingBuffs = { flask = { "Alric" }, food = {}, rune = {} }
    RaidSim.As(lm, function()
        lm.KART.BuffCheckFrame.reportBtn:GetScript("OnClick")(lm.KART.BuffCheckFrame.reportBtn)
    end)
    KARTTEST.AdvanceTime(10)
    KARTTEST.modifiers.shift = false
    T.eq(#KARTTEST.chat, 1, "shift-click on Report whispers")
    T.eq(KARTTEST.chat[1].channel, "WHISPER", "on WHISPER")
end

do
    local _, lm = F.NewRaid()
    lm.KART.MissingBuffs = { flask = {}, food = {}, rune = {} }
    RaidSim.As(lm, function()
        T.eq(lm.KART.ConsumablesComplete(), true, "empty missing tables count as complete")
    end)
    lm.KART.MissingBuffs = { flask = { "Alric" }, food = {}, rune = {} }
    RaidSim.As(lm, function()
        T.eq(lm.KART.ConsumablesComplete(), false, "a missing flask is not complete")
    end)
end

do
    -- Rune is whisper-only: recorded so Shift-Report can poke people, never posted to raid chat.
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    local missing = Render(lm)
    T.truthy(#(missing.rune or {}) > 0, "rune absences are recorded")
    KARTTEST.ClearChat()
    RaidSim.As(lm, function() lm.KART.ReportMissingBuffs() end)
    KARTTEST.AdvanceTime(10)
    local runeInChat = false
    for _, m in ipairs(KARTTEST.chat) do
        if m.msg:find("Rune", 1, true) then runeInChat = true end
    end
    T.eq(runeInChat, false, "but rune is not posted to raid chat")
end

do
    local _, lm = F.NewRaid()
    Render(lm)
    KARTTEST.modifiers.shift = false
    KARTTEST.ClearChat()
    lm.KART.MissingBuffs = { flask = { "Alric" }, food = {}, rune = {} }
    RaidSim.As(lm, function()
        lm.KART.BuffCheckFrame.reportBtn:GetScript("OnClick")(lm.KART.BuffCheckFrame.reportBtn)
    end)
    KARTTEST.AdvanceTime(10)
    T.eq(#KARTTEST.chat, 1, "plain click on Report still posts")
    T.eq(KARTTEST.chat[1].channel, "RAID", "to RAID")
end

do
    local _, lm = F.NewRaid()
    KARTTEST.auras = {}
    Render(lm)
    T.eq(lm.KART.BuffCheckFrame.okBanner:IsShown(), false,
        "a raid missing flasks does not show the all-ok banner")
end

do
    local sim, lm = F.NewRaid()
    local auras = {}
    for _, client in ipairs(sim.clients) do
        auras[client.unit] = {
            { name = "Flask of Power", spellId = 1 },
            { name = "Well Fed", spellId = 1232585 },
            { name = "Augment Rune", spellId = 453112 },
        }
    end
    KARTTEST.auras = auras
    Render(lm)
    T.eq(#(lm.KART.MissingBuffs.flask or {}), 0, "nobody is missing flask")
    T.eq(#(lm.KART.MissingBuffs.food or {}), 0, "nobody is missing food")
    T.eq(#(lm.KART.MissingBuffs.rune or {}), 0, "nobody is missing rune")
    T.eq(lm.KART.BuffCheckFrame.okBanner:IsShown(), true, "the all-ok banner is shown")
    local banner = lm.KART.BuffCheckFrame.okBanner:GetText() or ""
    T.truthy(banner:find("flask", 1, true) or banner:find("Fläsch", 1, true),
        "and names the consumables")
end

-- =====================================================================================
--  Flask/food missing count for the main-window status strip (no Buff Check window)
-- =====================================================================================
do
    local sim, lm = F.NewRaid()
    KARTTEST.auras = {}
    local n
    RaidSim.As(lm, function() n = lm.KART.CountMissingFlaskFood() end)
    T.eq(n, #sim.clients, "everyone without flask or food is counted, without opening the window")
end

do
    local sim, lm = F.NewRaid()
    local auras = {}
    for _, client in ipairs(sim.clients) do
        auras[client.unit] = {
            { name = "Flask of Power", spellId = 1 },
            { name = "Well Fed", spellId = 1232585 },
        }
    end
    -- One raider has flask but no food: still "without flask/food".
    auras[sim.byName.Alric.unit] = { { name = "Flask of Power", spellId = 1 } }
    KARTTEST.auras = auras
    local n
    RaidSim.As(lm, function() n = lm.KART.CountMissingFlaskFood() end)
    T.eq(n, 1, "a player missing only food still counts as one")
    local missing
    RaidSim.As(lm, function() missing = lm.KART.MissingBuffs end)
    T.eq(lm.KART.BuffCheckFrame, nil, "the strip count uses the scan, not the window")
    T.truthy(HasName(missing.food, "Alric"), "and the same scan lists that player as missing food")
end

-- ==========================================================================
--  Healthstone / Soulstone — IDs live on BuffData so a live raid can swap them
-- ==========================================================================
-- Healthstone is a bag item (5512, plus 224464 demonic). Soulstone is aura 20707 on the
-- target, not warlock passive 231811. Neither is raid-chat reported.

local function PlayerState(client, shortName, id)
    for _, p in ipairs(client.KART.BuffRosterSnapshot.players) do
        if p.shortName == shortName then return p.states[id] end
    end
end

local function BuffById(client, id)
    for _, d in ipairs(client.KART.BuffData) do
        if d.id == id then return d end
    end
end

do
    local _, lm = F.NewRaid()
    local hs, ss = BuffById(lm, "hs"), BuffById(lm, "ss")
    T.truthy(hs and hs.isHealthstone and hs.items, "healthstone is a BuffData row with an item list")
    T.eq(hs and hs.items and hs.items[1], 5512, "first healthstone item id is the one to swap after a live measurement")
    T.eq(hs and hs.items and hs.items[2], 224464, "demonic healthstone sits in the same list")
    T.truthy(ss and ss.spells, "soulstone is a BuffData row with a spell list")
    T.eq(ss and ss.spells and ss.spells[1], 20707, "first soulstone aura id is the one to swap after a live measurement")
    T.eq(hs.class, "WARLOCK", "both columns stay quiet when no warlock is in the raid")
    T.eq(ss.class, "WARLOCK", "including soulstone")
    T.is_nil(hs.report, "healthstone is not raid-chat reported")
    T.is_nil(ss.report, "soulstone is not raid-chat reported")
end

do
    local sim, lm = F.NewRaid()
    local sinja = sim.byName.Sinja
    KARTTEST.auras = {
        [sinja.unit] = { { name = "Soulstone", spellId = 20707 } },
    }
    Scan(lm)
    T.eq(PlayerState(lm, "Sinja", "ss"), true, "aura 20707 on a raider is a soulstone")
    T.truthy(not PlayerState(lm, "Alric", "ss"), "and its absence on everyone else still is")
end

do
    local sim, lm = F.NewRaid()
    KARTTEST.itemCounts = { [5512] = 1 }
    Scan(lm)
    T.eq(PlayerState(lm, "Bramor", "hs"), true, "a healthstone in our bags is present on our row")
    T.eq(PlayerState(lm, "Alric", "hs"), "unknown", "without a peer answer, their bag is unknown")
    KARTTEST.itemCounts = {}
end

do
    -- "unknown" is a non-empty string, which is truthy: SetDesaturated(not has) would leave
    -- a full-color stone, so every raider without KART looked like they had one.
    local sim, lm = F.NewRaid()
    KARTTEST.auras = {}
    KARTTEST.itemCounts = { [5512] = 1 }
    Render(lm)
    local HS = 11
    local alricInd = lm.KART.BuffCheckFrame.rows[4].indicators[HS]
    T.eq(alricInd:IsDesaturated(), true,
        "an unanswered healthstone is desaturated, not a full-color stone")
    local ownInd = lm.KART.BuffCheckFrame.rows[1].indicators[HS]
    T.eq(ownInd:IsDesaturated(), false, "our own stone stays a full-color stone")
    KARTTEST.itemCounts = {}
end

do
    local sim, lm = F.NewRaid()
    KARTTEST.itemCounts = { [224464] = 3 }
    Scan(lm)
    T.eq(PlayerState(lm, "Bramor", "hs"), true, "the demonic healthstone counts as having a stone")
    KARTTEST.itemCounts = {}
end

do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    Say(alric, "HS:1")
    T.eq(lm.KART.HSCache and lm.KART.HSCache["Alric"], true, "a peer HS:1 is cached")
    Scan(lm)
    T.eq(PlayerState(lm, "Alric", "hs"), true, "and paints as present")

    Say(alric, "HS:0")
    Scan(lm)
    T.truthy(not PlayerState(lm, "Alric", "hs"), "HS:0 paints as missing, not unknown")

    local good = lm.KART.HSCache["Alric"]
    Say(alric, "HS:yes")
    T.eq(lm.KART.HSCache["Alric"], good, "a malformed HS reply leaves the last good answer")
end

do
    local sim, lm = F.NewRaid()
    local alric = sim.byName.Alric
    Say(alric, "HS:1")
    RaidSim.Leave(sim, "Alric")
    RaidSim.As(lm, function() lm.KART.PruneDepartedPeers() end)
    T.is_nil(lm.KART.HSCache["Alric"], "a departed raider's healthstone answer is dropped")
end

do
    local sim, lm = F.NewRaid()
    KARTTEST.itemCounts = { [5512] = 2 }
    KARTTEST.now = KARTTEST.now + 10
    RaidSim.As(lm, function()
        lm.KASC.Dispatch("REQ_HS", "RAID", "Alric-TarrenMill")
    end)
    KARTTEST.AdvanceTime(0)
    local saw
    for _, e in ipairs(sim.log) do
        if e.msg == "HS:1" then saw = true end
    end
    T.eq(saw, true, "REQ_HS answers 1 when we have a healthstone")

    KARTTEST.itemCounts = {}
    sim.log = {}
    KARTTEST.now = KARTTEST.now + 10
    RaidSim.As(lm, function()
        lm.KASC.Dispatch("REQ_HS", "RAID", "Alric-TarrenMill")
    end)
    KARTTEST.AdvanceTime(0)
    saw = false
    for _, e in ipairs(sim.log) do
        if e.msg == "HS:0" then saw = true end
    end
    T.eq(saw, true, "and 0 when we do not")
end



