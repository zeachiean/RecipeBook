-- RecipeBook Test Runner
-- Usage: lua tests/run.lua [test_file_pattern]
-- Example: lua tests/run.lua test_data  (runs only test_data.lua)

local RED = "\27[31m"
local GREEN = "\27[32m"
local YELLOW = "\27[33m"
local CYAN = "\27[36m"
local RESET = "\27[0m"

-- ============================================================
-- ASSERTION HELPERS (injected into global scope for test files)
-- ============================================================

function assert_equal(expected, actual, msg)
    if expected ~= actual then
        local detail = string.format("expected %s, got %s",
            tostring(expected), tostring(actual))
        error((msg and (msg .. ": ") or "") .. detail, 2)
    end
end

function assert_true(value, msg)
    if not value then
        error((msg or "expected truthy") .. ", got " .. tostring(value), 2)
    end
end

function assert_false(value, msg)
    if value then
        error((msg or "expected falsy") .. ", got " .. tostring(value), 2)
    end
end

function assert_nil(value, msg)
    if value ~= nil then
        error((msg or "expected nil") .. ", got " .. tostring(value), 2)
    end
end

function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "expected non-nil, got nil", 2)
    end
end

function assert_error(fn, msg)
    local ok = pcall(fn)
    if ok then
        error(msg or "expected error but none was raised", 2)
    end
end

function assert_near(expected, actual, tolerance, msg)
    tolerance = tolerance or 0.01
    if math.abs(expected - actual) > tolerance then
        local detail = string.format("expected ~%.4f, got %.4f (tolerance %.4f)",
            expected, actual, tolerance)
        error((msg and (msg .. ": ") or "") .. detail, 2)
    end
end

function assert_table_length(tbl, expected, msg)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    if count ~= expected then
        local detail = string.format("expected table length %d, got %d", expected, count)
        error((msg and (msg .. ": ") or "") .. detail, 2)
    end
end

-- ============================================================
-- TEST DISCOVERY AND EXECUTION
-- ============================================================

local function discover_tests(pattern)
    local tests = {}
    local handle = io.popen('ls tests/test_*.lua 2>/dev/null')
    if not handle then return tests end
    for line in handle:lines() do
        if not pattern or line:find(pattern) then
            tests[#tests + 1] = line
        end
    end
    handle:close()
    table.sort(tests)
    return tests
end

local function run_test_file(filepath)
    local passed, failed, errors = 0, 0, 0
    local results = {}

    -- Load the mock layer first (resets state)
    dofile("tests/wow_mock.lua")

    -- Each test file returns a table of test_* functions
    local chunk, err = loadfile(filepath)
    if not chunk then
        print(string.format("  %sERROR loading %s: %s%s", RED, filepath, err, RESET))
        return 0, 0, 1, {}
    end

    local ok, mod = pcall(chunk)
    if not ok then
        print(string.format("  %sERROR executing %s: %s%s", RED, filepath, mod, RESET))
        return 0, 0, 1, {}
    end

    -- Collect test functions from the module table
    local test_funcs = {}
    if type(mod) == "table" then
        for name, fn in pairs(mod) do
            if type(fn) == "function" and name:match("^test_") then
                test_funcs[#test_funcs + 1] = name
            end
        end
        table.sort(test_funcs)
    end

    for _, name in ipairs(test_funcs) do
        -- Reset mocks between tests
        if MockWoW and MockWoW.reset then MockWoW.reset() end

        local test_ok, test_err = pcall(mod[name])
        if test_ok then
            passed = passed + 1
            results[#results + 1] = { name = name, status = "pass" }
        else
            failed = failed + 1
            results[#results + 1] = { name = name, status = "fail", err = test_err }
        end
    end

    return passed, failed, errors, results
end

-- ============================================================
-- MAIN
-- ============================================================

local pattern = arg[1]
local test_files = discover_tests(pattern)

if #test_files == 0 then
    print(YELLOW .. "No test files found." .. RESET)
    os.exit(1)
end

local total_passed, total_failed, total_errors = 0, 0, 0

print()
for _, filepath in ipairs(test_files) do
    local label = filepath:match("tests/(.+)%.lua$") or filepath
    print(CYAN .. label .. RESET)

    local passed, failed, errors, results = run_test_file(filepath)
    total_passed = total_passed + passed
    total_failed = total_failed + failed
    total_errors = total_errors + errors

    for _, r in ipairs(results) do
        if r.status == "pass" then
            print(string.format("  %s PASS %s %s", GREEN, RESET, r.name))
        else
            print(string.format("  %s FAIL %s %s", RED, RESET, r.name))
            for line in tostring(r.err):gmatch("[^\n]+") do
                print(string.format("         %s%s%s", RED, line, RESET))
            end
        end
    end
    print()
end

-- Summary
print(string.rep("-", 50))
local summary = string.format("  %d passed, %d failed, %d errors",
    total_passed, total_failed, total_errors)
if total_failed > 0 or total_errors > 0 then
    print(RED .. summary .. RESET)
    os.exit(1)
else
    print(GREEN .. summary .. RESET)
end
print()
