-- Offline harness. Run from the repository root: luajit tests/run.lua

-- Loads the WoW stubs, then LibStub, then each library, then each test file. Library files

-- are loaded in dependency order; a library that fails to load is a hard failure here, which

-- is itself a useful check.



-- Line coverage is OPT-IN: KART_COVERAGE=1 luajit tests/run.lua

--

-- Off by default on purpose. This file is the gate that runs on every push, it has to stay fast, and

-- it must not start failing on a machine where the luacov rock is missing. What coverage answers is

-- a different question from "do the tests pass": which branches of a 176 KB LootCouncil.lua the 950

-- assertions never reach at all. An untested branch is where a fix lands quietly wrong.

--

-- raidsim loads each addon file with an "@path" chunk name, so the counts land under the real source

-- paths even though the files are loaded once per simulated client.

local function LoadLuacov()

    local ok, runner = pcall(require, "luacov.runner")

    if ok then return runner end

    -- LuaJIT does not look in luarocks' per-user tree on its own (it does on the CI image, which

    -- installs system-wide), so try there before giving up.

    local home = os.getenv("USERPROFILE") or os.getenv("HOME")

    if home then

        package.path = package.path

            .. ";" .. home .. "/.luarocks/share/lua/5.1/?.lua"

            .. ";" .. home .. "/.luarocks/share/lua/5.1/?/init.lua"

        ok, runner = pcall(require, "luacov.runner")

    end

    return ok and runner or nil

end



local coverage

if os.getenv("KART_COVERAGE") then

    coverage = LoadLuacov()

    if coverage then

        coverage.init({ exclude = { "^tests/", "^luacov" } })

    else

        print("KART_COVERAGE is set but luacov is not installed -- running without coverage.")

    end

end



local total, failures = 0, 0



_G.T = {}



function T.eq(actual, expected, label)

    total = total + 1

    if actual ~= expected then

        failures = failures + 1

        print(string.format("FAIL  %s\n        expected: %s\n        actual:   %s",

            label, tostring(expected), tostring(actual)))

    end

end



function T.truthy(value, label) T.eq(not not value, true, label) end

function T.is_nil(value, label) T.eq(value == nil, true, label) end



function T.deep_eq(actual, expected, label)

    local function same(a, b)

        if a == b then return true end

        if type(a) ~= "table" or type(b) ~= "table" then return false end

        for k, v in pairs(a) do if not same(v, b[k]) then return false end end

        for k in pairs(b) do if a[k] == nil then return false end end

        return true

    end

    total = total + 1

    if not same(actual, expected) then

        failures = failures + 1

        print("FAIL  " .. label .. " (tables differ)")

        local function dump(t, depth)

            if type(t) ~= "table" then return tostring(t) end

            depth = depth or 0

            local parts = {}

            for k, v in pairs(t) do

                local vs = (type(v) == "table" and depth < 1) and dump(v, depth + 1) or tostring(v)

                parts[#parts + 1] = tostring(k) .. "=" .. vs

                    .. "(" .. type(k) .. "/" .. type(v) .. ")"

            end

            table.sort(parts)

            return "{" .. table.concat(parts, ",") .. "}"

        end

        print("        expected: " .. dump(expected))

        print("        actual:   " .. dump(actual))

    end

end



dofile("tests/wow_stubs.lua")

dofile("Libs/LibStub/LibStub.lua")



dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")

dofile("Libs/AceComm-3.0/ChatThrottleLib.lua")

dofile("Libs/AceComm-3.0/AceComm-3.0.lua")

ChatThrottleLib.HardThrottlingBeginTime = -math.huge

ChatThrottleLib.avail = ChatThrottleLib.BURST



dofile("Libs/KAUtil-1.0/KAUtil-1.0.lua")

dofile("Libs/KAGS-1.0/KAGS-1.0.lua")

dofile("Libs/KASC-1.0/KASC-1.0.lua")

dofile("Libs/KAUI-1.0/KAUI-1.0.lua")



dofile("tests/test_locales.lua")

dofile("tests/test_kautil.lua")

dofile("tests/test_kags.lua")

dofile("tests/test_kaui.lua")

dofile("tests/test_groupinvite.lua")

dofile("tests/test_wowutils_import.lua")

dofile("tests/test_identity.lua")

dofile("tests/test_sync.lua")

dofile("tests/test_kasc_responders.lua")

dofile("tests/test_settings_sync.lua")

dofile("tests/test_core_wiring.lua")

dofile("tests/test_buffchecker.lua")

dofile("tests/test_autopromote.lua")

dofile("tests/test_profiles.lua")

dofile("tests/test_autolog.lua")

dofile("tests/test_cotank.lua")
dofile("tests/test_mainframe.lua")

dofile("tests/test_sidebar_chrome.lua")

dofile("tests/test_raidleadbar.lua")

dofile("tests/test_diagnostics.lua")

dofile("tests/test_hello.lua")

dofile("tests/test_transport.lua")

dofile("tests/test_rc_companion.lua")

dofile("tests/test_rc_owed.lua")



print(string.format("\n%d assertions, %d failures", total, failures))



if coverage then

    coverage.shutdown()

    require("luacov.reporter").report()

    print("Coverage written to luacov.report.out (summary at the end of that file).")

end



os.exit(failures == 0 and 0 or 1)

