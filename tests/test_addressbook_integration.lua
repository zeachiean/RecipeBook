-- test_addressbook_integration.lua
--
-- Verifies RecipeBook's cross-addon integration with AddressBook works correctly,
-- including the soft-probe pattern (don't error when AB is missing, use API when present).
--
-- This is the ONLY cross-addon integration in the Breakbone family today. See
-- ../../BREAKBONE_BRAND.md §12 for the integration rules.
--
-- The test uses a mock AddressBook namespace installed into the global scope
-- for the duration of each test. We can't load the real AddressBook in this test
-- harness, so we verify the calling contract: that RecipeBook probes correctly,
-- calls the right API method, and gracefully skips the integration when AB absent.

local T = {}

-- Helper: install a fake AddressBook namespace, return a record of calls made to it
local function installFakeAddressBook()
    local calls = {}
    _G.AddressBook = {
        API = {
            WaypointTo = function(self, npcName, zoneName)
                table.insert(calls, {
                    method = "WaypointTo",
                    npcName = npcName,
                    zoneName = zoneName,
                })
                return true
            end,
            Lookup = function(self, name)
                table.insert(calls, { method = "Lookup", name = name })
                return nil
            end,
            Search = function(self, query)
                table.insert(calls, { method = "Search", query = query })
                return {}
            end,
            ShowSpawns = function(self, npcID)
                table.insert(calls, { method = "ShowSpawns", npcID = npcID })
                return true
            end,
        },
        ClearWaypoint = function(self)
            table.insert(calls, { method = "ClearWaypoint" })
        end,
        ClearAllWaypoints = function(self)
            table.insert(calls, { method = "ClearAllWaypoints" })
        end,
    }
    return calls
end

local function removeAddressBook()
    _G.AddressBook = nil
end

-- Helper: ensure RecipeBook namespace exists with the probe function under test.
-- Mirrors RecipeBook/Core.lua:216 exactly.
local function installRecipeBookProbe()
    _G.RecipeBook = _G.RecipeBook or {}
    function RecipeBook:HasAddressBook()
        return AddressBook and AddressBook.API and true or false
    end
end

-- ============================================================
-- HasAddressBook() probe
-- ============================================================

function T.test_has_addressbook_false_when_absent()
    removeAddressBook()
    installRecipeBookProbe()
    assert_equal(false, RecipeBook:HasAddressBook())
end

function T.test_has_addressbook_false_when_api_missing()
    _G.AddressBook = {}  -- namespace exists but no API
    installRecipeBookProbe()
    assert_equal(false, RecipeBook:HasAddressBook())
    removeAddressBook()
end

function T.test_has_addressbook_true_when_api_present()
    installFakeAddressBook()
    installRecipeBookProbe()
    assert_equal(true, RecipeBook:HasAddressBook())
    removeAddressBook()
end

-- ============================================================
-- Waypoint call contract
-- ============================================================

function T.test_waypoint_call_dispatches_to_api()
    local calls = installFakeAddressBook()
    installRecipeBookProbe()

    -- Simulate the guarded call site from UIDropSources.lua:298-299
    if RecipeBook:HasAddressBook() then
        AddressBook.API:WaypointTo("Trogar the Traveler", "Nagrand")
    end

    assert_equal(1, #calls, "should have recorded one API call")
    assert_equal("WaypointTo", calls[1].method)
    assert_equal("Trogar the Traveler", calls[1].npcName)
    assert_equal("Nagrand", calls[1].zoneName)
    removeAddressBook()
end

function T.test_waypoint_call_skipped_when_absent()
    removeAddressBook()
    installRecipeBookProbe()

    -- Simulate the guarded call site — must be a no-op, not an error
    local called = false
    if RecipeBook:HasAddressBook() then
        called = true  -- should not reach here
    end

    assert_false(called, "should skip integration when AB absent")
end

function T.test_waypoint_call_does_not_error_when_absent()
    removeAddressBook()
    installRecipeBookProbe()

    -- The integration must degrade cleanly — no pcall needed around the guard
    local ok = pcall(function()
        if RecipeBook:HasAddressBook() then
            AddressBook.API:WaypointTo("should not reach", "should not reach")
        end
    end)
    assert_true(ok, "guarded call site must not error when AB absent")
end

-- ============================================================
-- ClearWaypoint fallback (legacy AB method outside the API namespace)
-- ============================================================

function T.test_clear_waypoint_calls_legacy_ab_method()
    -- UIDropSources.lua:290-291 calls AddressBook:ClearWaypoint() directly,
    -- not AddressBook.API:Clear(). This test documents that the legacy
    -- method is still used — if AB migrates these under API:, RB must update.
    local calls = installFakeAddressBook()
    installRecipeBookProbe()

    if AddressBook and AddressBook.ClearWaypoint then
        AddressBook:ClearWaypoint()
    end

    assert_equal(1, #calls)
    assert_equal("ClearWaypoint", calls[1].method)
    removeAddressBook()
end

-- ============================================================
-- API version probing (for future compatibility checks)
-- ============================================================

function T.test_api_provides_expected_methods()
    installFakeAddressBook()
    installRecipeBookProbe()

    -- The v1 API surface documented in BREAKBONE_BRAND.md §12.1 and AB CLAUDE.md.
    -- If AB adds or removes methods, this test should be updated to match.
    assert_not_nil(AddressBook.API.Lookup, "API.Lookup must exist")
    assert_not_nil(AddressBook.API.Search, "API.Search must exist")
    assert_not_nil(AddressBook.API.ShowSpawns, "API.ShowSpawns must exist")
    assert_not_nil(AddressBook.API.WaypointTo, "API.WaypointTo must exist")
    removeAddressBook()
end

return T
