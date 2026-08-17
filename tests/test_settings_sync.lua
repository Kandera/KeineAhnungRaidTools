-- Every settings widget must be re-applied from KART_Settings after a reload.
--
-- A widget created with `store = SettingsStore, key = "..."` writes its value on click, but nothing
-- pushes the saved value BACK into it: the widget is built at file-load time, before KART_Settings
-- exists, and starts unchecked/at zero. KART.SyncSettingsToUI (Core.lua) is the one place that
-- closes that loop, via a settingsMap entry per widget.
--
-- Forget one entry and the failure is quiet and misleading rather than loud: the setting itself
-- persists and keeps taking effect, while its checkbox renders "off" after every /reload, so the
-- first click writes the value it already had and appears to do nothing. That is exactly what
-- shipped in 3.2.0 for the two irrelevant-item switches, and no test could have caught it -- hence
-- this one, which needs no WoW at all: it just checks the two lists agree.
--
-- The file list comes from the .toc so a settings widget in a newly added file is covered without
-- anyone remembering to extend this test.

local function slurp(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local toc = assert(slurp("KeineAhnungRaidTools.toc"), "KeineAhnungRaidTools.toc is readable")
local core = assert(slurp("Core.lua"), "Core.lua is readable")

-- Collect every widget key declared anywhere the .toc loads. Libs/ are skipped: KAUI defines the
-- checkbox/slider constructors themselves and holds no settings of its own.
local declared, declaredCount = {}, 0
for line in toc:gmatch("[^\r\n]+") do
    local path = line:match("^([%w_/\\%.%-]+%.lua)%s*$")
    if path and not path:match("^Libs") then
        local text = slurp((path:gsub("\\", "/")))
        if text then
            for key in text:gmatch('store%s*=%s*SettingsStore,%s*key%s*=%s*"([%w_]+)"') do
                if not declared[key] then
                    declared[key] = path
                    declaredCount = declaredCount + 1
                end
            end
        end
    end
end

-- A sanity floor, so a broken pattern above cannot turn this into a test that silently checks
-- nothing. 3.2.0 shipped 40; the number only ever grows.
T.truthy(declaredCount >= 25, "found the settings widgets (" .. declaredCount .. " >= 25)")

for key, path in pairs(declared) do
    -- SyncSettingsToUI's entries all read `settingsMap[<widget>] = "<key>"`, so the quoted key is
    -- the thing to look for. Plain find, not a pattern -- keys are identifiers, but the search
    -- string carries quotes.
    T.truthy(core:find('= "' .. key .. '"', 1, true),
        "KART.SyncSettingsToUI re-applies " .. key .. " (declared in " .. path .. ")")
end
