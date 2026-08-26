-- Every settings widget must be re-applied from KART_Settings after a reload.
--
-- A widget created with `store = SettingsStore, key = "..."` writes its value on click, but nothing
-- pushes the saved value BACK into it: the widget is built at file-load time, before KART_Settings
-- exists, and starts unchecked/at zero. The file that builds the widget owns a settingsMap entry
-- (`settingsMap[<widget>] = "<key>"`). Core.lua only fans out to those SyncWidgets helpers.
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

T.truthy(core:find("KART.SyncMainFrameWidgets()", 1, true), "Core fans out to MainFrame widgets")
T.truthy(core:find("KART.RC.SyncWidgets()", 1, true), "Core fans out to RC widgets")
T.truthy(core:find("KART.WU.SyncWidgets()", 1, true), "Core fans out to WoWUtils widgets")
T.truthy(core:find("KART.CT.SyncWidgets()", 1, true), "Core fans out to Co-Tank widgets")
T.eq(core:find("settingsMap[", 1, true), nil, "Core.lua does not keep the widget map")

for key, path in pairs(declared) do
    local text = assert(slurp((path:gsub("\\", "/"))), path .. " is readable")
    -- Apply lines are `if <widget> then settingsMap[<widget>] = "<key>" end`.
    -- `key = "<key>"` on the constructor and `[chip] = "<key>"` on the sidebar map must not count.
    T.truthy(text:find('] = "' .. key .. '" end', 1, true),
        path .. " re-applies " .. key)
end
