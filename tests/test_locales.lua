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
