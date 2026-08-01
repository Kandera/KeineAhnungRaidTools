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
    end
end

dofile("tests/wow_stubs.lua")
dofile("Libs/LibStub/LibStub.lua")

-- Library files, in dependency order. Extended by each task that adds a library.
-- (Task 2 adds KAUtil, Task 3 KAGS, Task 4 KAUI, Task 7 KASC.)
dofile("Libs/KAUtil-1.0/KAUtil-1.0.lua")
dofile("Libs/KAGS-1.0/KAGS-1.0.lua")
dofile("Libs/KASC-1.0/KASC-1.0.lua")
dofile("Libs/KAUI-1.0/KAUI-1.0.lua")

-- Test files. Extended by each task that adds tests.
dofile("tests/test_locales.lua")
dofile("tests/test_kautil.lua")
dofile("tests/test_kags.lua")
dofile("tests/test_kaui.lua")
dofile("tests/test_groupinvite.lua")
dofile("tests/test_identity.lua")
dofile("tests/test_sync.lua")
dofile("tests/test_kasc_responders.lua")
dofile("tests/test_lc_votewire.lua")
dofile("tests/test_settings_sync.lua")
dofile("tests/test_lc_collectible.lua")
dofile("tests/test_lc_relevance.lua")
dofile("tests/test_lc_buttonconfig.lua")
dofile("tests/test_lc_baseflow.lua")
dofile("tests/test_lc_chrome.lua")
dofile("tests/test_lc_version.lua")
dofile("tests/test_lc_autopass.lua")
dofile("tests/test_lc_churn.lua")
-- ORDER IS LOAD-BEARING HERE, AND IT SHOULD NOT BE. The addon jitters its own replies with
-- math.random, and several test_lc_churn.lua assertions turn on which jittered reply lands first --
-- so inserting a file ANYWHERE above changes the random stream churn starts from and silently
-- changes what those assertions measure. Reseeding before each file (the obvious fix) makes five of
-- them fail outright, and that failure is real, not an artifact: see B70 in docs/BACKLOG.md. The
-- reseeding belongs with that fix, so until then new files go at the END.
dofile("tests/test_lc_reload.lua")
dofile("tests/test_lc_ownership.lua")
dofile("tests/test_lc_award.lua")
dofile("tests/test_lc_votelabels.lua")
-- Core.lua is not loadable here (it needs the game), so its event and slash wiring is checked
-- against the source instead -- see the file for why that is worth doing.
dofile("tests/test_core_wiring.lua")
dofile("tests/test_droptimizer.lua")
dofile("tests/test_buffchecker.lua")
dofile("tests/test_autopromote.lua")
-- The Manifest itself (docs/MANIFEST.md), walked C1..C12 in ONE session -- last before the soak,
-- because it is the statement of what must hold and the soak is the search for what does not.
dofile("tests/test_manifest.lua")
dofile("tests/test_lc_soak.lua")

print(string.format("\n%d assertions, %d failures", total, failures))

-- Written before os.exit, which luacov's own exit hook never sees from here.
if coverage then
    coverage.shutdown()
    require("luacov.reporter").report()
    print("Coverage written to luacov.report.out (summary at the end of that file).")
end

os.exit(failures == 0 and 0 or 1)
