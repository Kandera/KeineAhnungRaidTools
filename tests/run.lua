-- Offline harness. Run from the repository root: luajit tests/run.lua
-- Loads the WoW stubs, then LibStub, then each library, then each test file. Library files
-- are loaded in dependency order; a library that fails to load is a hard failure here, which
-- is itself a useful check.

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
dofile("Libs/KAUI-1.0/KAUI-1.0.lua")

-- Test files. Extended by each task that adds tests.
dofile("tests/test_kautil.lua")
dofile("tests/test_kags.lua")
dofile("tests/test_kaui.lua")

print(string.format("\n%d assertions, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)
