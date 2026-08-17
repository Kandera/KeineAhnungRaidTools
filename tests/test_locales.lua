-- Both locale tables must carry the same keys.
--
-- A missing key is not a syntax error and not a crash: KART.L is English first with German laid over
-- it (see Core.lua), so a key missing from deDE silently falls back to English, and a key missing
-- from enUS renders as nil in a string.format or as an empty popup for anyone on English. This guild
-- runs both languages in the same raid, and one of the two failures is invisible to whoever added
-- the string.
--
-- English is the reference: it is the primary locale by project convention, so a key present only in
-- German is a strong sign the English one was forgotten rather than that the German is extra.

local function LoadLocale(path)
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadstring(assert(io.open(path, "r")):read("*a"), "@" .. path))
    setfenv(chunk, env)
    local KART = {}
    chunk("KeineAhnungRaidTools", KART)
    return KART
end

do
    local en = LoadLocale("Locales/enUS.lua").L_enUS
    local de = LoadLocale("Locales/deDE.lua").L_deDE
    T.truthy(en and next(en), "enUS loaded and is not empty")
    T.truthy(de and next(de), "deDE loaded and is not empty")

    local missingDE, missingEN = {}, {}
    for k in pairs(en) do if de[k] == nil then missingDE[#missingDE + 1] = k end end
    for k in pairs(de) do if en[k] == nil then missingEN[#missingEN + 1] = k end end
    table.sort(missingDE); table.sort(missingEN)

    T.eq(table.concat(missingDE, ", "), "", "every English key has a German translation")
    T.eq(table.concat(missingEN, ", "), "", "and no German key exists without an English original")

    -- A string used with string.format has to keep the same placeholders in both languages, or the
    -- translated one errors at the moment it is printed -- which for a warning path means the client
    -- fails exactly when it was trying to tell someone something was wrong.
    local mismatched = {}
    for k, v in pairs(en) do
        if type(v) == "string" and type(de[k]) == "string" then
            local function specs(s)
                local out = {}
                for spec in s:gmatch("%%[%-%+ #0-9%.]*[diouxXeEfgGqscs]") do out[#out + 1] = spec end
                return table.concat(out, "")
            end
            if specs(v) ~= specs(de[k]) then mismatched[#mismatched + 1] = k end
        end
    end
    table.sort(mismatched)
    T.eq(table.concat(mismatched, ", "), "",
        "both languages use the same format placeholders in the same order")
end

-- ===================================================================================
-- The other two ways a locale key goes wrong
-- ===================================================================================
-- The checks above compare the two languages against each other. Both can agree perfectly and still
-- be wrong in a way only the CODE can show: a key nothing defines renders as nil and throws on the
-- first concat, and a call site passing the wrong number of arguments to string.format throws at the
-- moment it prints -- which for a warning path means the client fails exactly when it was trying to
-- tell somebody something was wrong.
--
-- Read out of the source, like tests/test_core_wiring.lua, because there is no other way to see a
-- reference that was never taken.

local SOURCES = {
    "Core.lua", "MainFrame.lua", "Utils.lua", "Profiles.lua", "AutoLog.lua",
    "BuffChecker.lua", "GroupLogic.lua", "Invite.lua", "RaidleadBar.lua",
    "RCCompanion.lua",
}

local function Slurp(path)
    local f = assert(io.open(path, "r"), path)
    local text = f:read("*a")
    f:close()
    return text
end

do
    local en = LoadLocale("Locales/enUS.lua").L_enUS
    local missing = {}
    for _, path in ipairs(SOURCES) do
        local src = Slurp(path)
        -- "L.KEY", "KART.L.KEY", "Lx.KEY" -- the three spellings this codebase uses. Keys are
        -- ALL_CAPS by convention, which is what keeps this from matching ordinary table fields.
        for key in src:gmatch("[%w%.]-L%.([A-Z][A-Z0-9_]*)") do
            if en[key] == nil then missing[key] = path end
        end
    end
    local names = {}
    for key, path in pairs(missing) do names[#names + 1] = key .. " (" .. path .. ")" end
    table.sort(names)
    T.eq(table.concat(names, ", "), "", "every locale key the addon reads is actually defined")
end

do
    -- Keys reached by name rather than written out: BuffChecker builds its rows from BuffData's
    -- labelKey/reportLabelKey, and the quality menu from "LC_QUALITY_" .. n. Neither is visible to
    -- the scan above, and a buff added without its string renders as an empty label.
    local en = LoadLocale("Locales/enUS.lua").L_enUS
    local src = Slurp("BuffChecker.lua")
    local seen = 0
    for key in src:gmatch("labelKey%s*=%s*\"([A-Z][A-Z0-9_]*)\"") do
        seen = seen + 1
        T.truthy(en[key] ~= nil, "BuffData's " .. key .. " has a string")
    end
    T.truthy(seen >= 12, "and every row of BuffData was actually looked at (" .. seen .. ")")
end

do
    -- string.format's argument count against the placeholder count of the string it is given.
    -- Walks parentheses rather than matching to the first ")", so a nested call in an argument does
    -- not end the scan early.
    local en = LoadLocale("Locales/enUS.lua").L_enUS
    local function CountSpecs(s)
        local n = 0
        for _ in s:gsub("%%%%", ""):gmatch("%%[%-%+ #0-9%.]*[diouxXeEfgGqcs]") do n = n + 1 end
        return n
    end

    local checked, bad = 0, {}
    for _, path in ipairs(SOURCES) do
        local src = Slurp(path)
        local pos = 1
        while true do
            local s, e, key = src:find("string%.format%(%s*[%w%.]-L%.([A-Z][A-Z0-9_]*)%s*,", pos)
            if not s then break end
            pos = e + 1
            if type(en[key]) == "string" then
                -- Find the closing paren of the format call.
                local depth, i = 1, e
                while i < #src and depth > 0 do
                    i = i + 1
                    local c = src:sub(i, i)
                    if c == "(" or c == "[" or c == "{" then depth = depth + 1
                    elseif c == ")" or c == "]" or c == "}" then depth = depth - 1 end
                end
                -- Split the argument list on top-level commas.
                local args, d, cur = 0, 0, ""
                for c in src:sub(e + 1, i - 1):gmatch(".") do
                    if c == "(" or c == "[" or c == "{" then d = d + 1
                    elseif c == ")" or c == "]" or c == "}" then d = d - 1 end
                    if c == "," and d == 0 then
                        if cur:match("%S") then args = args + 1 end
                        cur = ""
                    else
                        cur = cur .. c
                    end
                end
                if cur:match("%S") then args = args + 1 end

                checked = checked + 1
                local want = CountSpecs(en[key])
                if want ~= args then
                    bad[#bad + 1] = string.format("%s %s: %d placeholders, %d arguments",
                        path, key, want, args)
                end
            end
        end
    end
    table.sort(bad)
    T.eq(table.concat(bad, " | "), "",
        "every string.format on a locale string is given as many arguments as it has placeholders")
    T.truthy(checked >= 8, "and enough call sites were actually reached (" .. checked .. ")")
end

-- ===================================================================================
-- Every setting the addon reads has a default
-- ===================================================================================
-- A setting read but never defaulted is nil on a fresh install, and nil takes whichever branch the
-- reader did not mean -- silently, and only for new users, which is the hardest kind to notice. The
-- exceptions below are settings that are MEANT to be absent until something writes them, and each
-- reader of those carries its own fallback; they are listed by name so a genuinely forgotten default
-- cannot hide among them.
do
    local NIL_BY_DESIGN = {
        activeProfile = true,
        lcCouncilMembers = true, -- legacy WTF only; RC migration reads it once
        -- Window geometry, written when a window is first moved. Every reader supplies its own
        -- default position (`KART_Settings.bcX or 200`), which is what makes "unset" meaningful.
        bcPoint = true, bcRelativePoint = true, bcX = true, bcY = true,
        bcWidth = true, bcHeight = true,
        rlBarPoint = true, rlBarRelativePoint = true, rlBarX = true, rlBarY = true,
    }

    local utils = Slurp("Utils.lua")
    local from = utils:find("KART.Defaults = {", 1, true)
    T.truthy(from, "KART.Defaults was found in Utils.lua")
    local depth, i = 0, from + #"KART.Defaults = " - 1
    while i <= #utils do
        local c = utils:sub(i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then break end
        end
        i = i + 1
    end
    local block = utils:sub(from, i)
    local defaults = {}
    for name in block:gmatch("([A-Za-z_][A-Za-z0-9_]*)%s*=") do defaults[name] = true end

    local missing, seen = {}, 0
    for _, path in ipairs(SOURCES) do
        for name in Slurp(path):gmatch("KART_Settings%.([A-Za-z_][A-Za-z0-9_]*)") do
            seen = seen + 1
            if not defaults[name] and not NIL_BY_DESIGN[name] then missing[name] = path end
        end
    end
    local names = {}
    for name, path in pairs(missing) do names[#names + 1] = name .. " (" .. path .. ")" end
    table.sort(names)
    T.eq(table.concat(names, ", "), "", "every setting the addon reads has a default")
    T.truthy(seen >= 80, "and enough reads were actually reached (" .. seen .. ")")
end
