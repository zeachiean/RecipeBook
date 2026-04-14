-- Tests for RecipeBook.API — public consumer surface.
-- See API.lua for the contract and MouthPiece's spec for the shape.
local T = {}

local ALCHEMY = 171
local ENCHANTING = 333
local TAILORING = 197

-- Fresh character store and current char entry.
function T.setup()
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = {}
    RecipeBookDB.minimap = { hide = false }
    RecipeBookDB.maxPhase = 5
    RecipeBookDB.currentPhase = 1
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.professionSkill = {}
    RecipeBook:GetMyCharData()
end

local function makeChar(name, professions)
    local key = name .. "-TestRealm"
    local data = RecipeBook:GetOrCreateCharData(key, name, "TestRealm")
    for profID in pairs(professions or {}) do
        data.knownProfessions[profID] = true
    end
    return key, data
end

-- ============================================================
-- Version + shape
-- ============================================================

function T.test_api_namespace_exists()
    assert_true(RecipeBook.API ~= nil, "RecipeBook.API must exist")
end

function T.test_api_version_is_at_least_1()
    -- v1 contract stays valid; VERSION only ever increases additively.
    assert_true(RecipeBook.API.VERSION >= 1,
        "API.VERSION must be >= 1, got " .. tostring(RecipeBook.API.VERSION))
end

function T.test_api_version_includes_guild_crafts()
    assert_equal(2, RecipeBook.API.VERSION)
end

-- ============================================================
-- GetAllProfessions
-- ============================================================

function T.test_get_all_professions_returns_twelve()
    local list = RecipeBook.API:GetAllProfessions()
    assert_equal(12, #list, "should return all 12 supported professions")
end

function T.test_get_all_professions_is_sorted()
    local list = RecipeBook.API:GetAllProfessions()
    for i = 2, #list do
        assert_true(list[i-1] <= list[i],
            "professions not alphabetised: " .. list[i-1] .. " > " .. list[i])
    end
end

function T.test_get_all_professions_contains_known_names()
    local list = RecipeBook.API:GetAllProfessions()
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    assert_true(set.Alchemy, "missing Alchemy")
    assert_true(set.Enchanting, "missing Enchanting")
    assert_true(set.Tailoring, "missing Tailoring")
    assert_true(set.Fishing, "missing Fishing")
end

function T.test_get_all_professions_returns_copy()
    local a = RecipeBook.API:GetAllProfessions()
    a[1] = "HACKED"
    local b = RecipeBook.API:GetAllProfessions()
    assert_true(b[1] ~= "HACKED", "API must return a fresh copy each call")
end

-- ============================================================
-- GetAllRecipes
-- ============================================================

function T.test_get_all_recipes_alchemy_nonempty()
    local list = RecipeBook.API:GetAllRecipes("Alchemy")
    assert_true(#list > 0, "Alchemy should have recipes")
end

function T.test_get_all_recipes_unknown_profession_empty()
    local list = RecipeBook.API:GetAllRecipes("Herbalism")
    assert_equal(0, #list)
end

function T.test_get_all_recipes_nil_profession_empty()
    local list = RecipeBook.API:GetAllRecipes(nil)
    assert_equal(0, #list)
end

function T.test_recipe_ref_shape()
    local list = RecipeBook.API:GetAllRecipes("Alchemy")
    local ref = list[1]
    assert_true(type(ref.spellID) == "number", "spellID must be a number")
    assert_true(type(ref.name) == "string", "name must be a string")
    assert_equal("Alchemy", ref.profession)
    assert_true(type(ref.link) == "string", "link must be a string")
    assert_true(ref.link:find("Hspell:") ~= nil, "link must use Hspell format")
    assert_true(type(ref.recipeID) == "number", "recipeID must be a number")
end

function T.test_recipe_ref_spellid_is_teaches()
    -- For any ref, spellID should match the underlying data.teaches field.
    local list = RecipeBook.API:GetAllRecipes("Alchemy")
    for _, ref in ipairs(list) do
        local data = RecipeBook.recipeDB[ALCHEMY][ref.recipeID]
        assert_equal(data.teaches, ref.spellID)
    end
end

function T.test_rank_up_entries_excluded()
    -- String-teaches entries (Expert, Artisan, Master) must not appear in
    -- GetAllRecipes output — they're not real recipes.
    for _, profName in ipairs(RecipeBook.API:GetAllProfessions()) do
        local refs = RecipeBook.API:GetAllRecipes(profName)
        for _, ref in ipairs(refs) do
            assert_true(type(ref.spellID) == "number",
                "rank-up entry leaked into " .. profName .. " refs")
        end
    end
end

function T.test_item_recipe_has_item_id()
    -- Pick an item recipe (one where rid != teaches and not isSpell)
    local refs = RecipeBook.API:GetAllRecipes("Alchemy")
    local found
    for _, ref in ipairs(refs) do
        if ref.itemID then found = ref; break end
    end
    assert_true(found ~= nil, "expected at least one item recipe")
    assert_equal(found.recipeID, found.itemID)
end

function T.test_get_all_recipes_returns_copies()
    local a = RecipeBook.API:GetAllRecipes("Alchemy")
    a[1].name = "HACKED"
    local b = RecipeBook.API:GetAllRecipes("Alchemy")
    -- Not the same table instance
    assert_true(a[1] ~= b[1], "each call should return fresh refs")
end

-- ============================================================
-- GetRecipe (spellID lookup)
-- ============================================================

function T.test_get_recipe_round_trip()
    -- Pick a real recipe from the DB
    local list = RecipeBook.API:GetAllRecipes("Alchemy")
    local source = list[1]
    local ref = RecipeBook.API:GetRecipe(source.spellID)
    assert_true(ref ~= nil, "round-trip lookup should work")
    assert_equal(source.spellID, ref.spellID)
    assert_equal(source.name, ref.name)
    assert_equal("Alchemy", ref.profession)
end

function T.test_get_recipe_unknown_spellid()
    local ref = RecipeBook.API:GetRecipe(99999999)
    assert_true(ref == nil)
end

function T.test_get_recipe_non_number_returns_nil()
    assert_true(RecipeBook.API:GetRecipe("27984") == nil)
    assert_true(RecipeBook.API:GetRecipe(nil) == nil)
    assert_true(RecipeBook.API:GetRecipe({}) == nil)
end

function T.test_get_recipe_resolves_enchanting_spell()
    -- Enchanting has many spell-type recipes. Pick one and round-trip.
    local refs = RecipeBook.API:GetAllRecipes("Enchanting")
    assert_true(#refs > 0)
    for _, r in ipairs(refs) do
        local back = RecipeBook.API:GetRecipe(r.spellID)
        assert_true(back ~= nil,
            "GetRecipe(" .. r.spellID .. ") returned nil but should resolve")
    end
end

-- ============================================================
-- GetKnownProfessions
-- ============================================================

function T.test_get_known_professions_current_char()
    makeChar("TestChar", { [ALCHEMY] = true, [TAILORING] = true })
    -- TestChar is the mock's current char
    local list = RecipeBook.API:GetKnownProfessions(nil)
    assert_equal(2, #list)
    local set = {}
    for _, n in ipairs(list) do set[n] = true end
    assert_true(set.Alchemy)
    assert_true(set.Tailoring)
end

function T.test_get_known_professions_specific_char()
    local key = makeChar("Enchanter", { [ENCHANTING] = true })
    local list = RecipeBook.API:GetKnownProfessions(key)
    assert_equal(1, #list)
    assert_equal("Enchanting", list[1])
end

function T.test_get_known_professions_unknown_char_empty()
    local list = RecipeBook.API:GetKnownProfessions("Ghost-TestRealm")
    assert_equal(0, #list)
end

function T.test_get_known_professions_is_sorted()
    makeChar("Multi", {
        [ALCHEMY] = true, [TAILORING] = true, [ENCHANTING] = true,
    })
    local list = RecipeBook.API:GetKnownProfessions("Multi-TestRealm")
    for i = 2, #list do
        assert_true(list[i-1] <= list[i], "not sorted")
    end
end

-- ============================================================
-- GetKnownRecipes
-- ============================================================

function T.test_get_known_recipes_returns_learned()
    local key, data = makeChar("Alch", { [ALCHEMY] = true })
    -- Pick two real recipe IDs from the DB
    local picked = {}
    for rid in pairs(RecipeBook.recipeDB[ALCHEMY]) do
        picked[#picked + 1] = rid
        if #picked == 2 then break end
    end
    data.knownRecipes[ALCHEMY] = { [picked[1]] = true, [picked[2]] = true }

    local list = RecipeBook.API:GetKnownRecipes(key, "Alchemy")
    assert_equal(2, #list)
end

function T.test_get_known_recipes_unknown_profession_empty()
    makeChar("NoSkill", {})
    local list = RecipeBook.API:GetKnownRecipes("NoSkill-TestRealm", "Herbalism")
    assert_equal(0, #list)
end

function T.test_get_known_recipes_char_without_profession_empty()
    local key = makeChar("Nobody", {})
    local list = RecipeBook.API:GetKnownRecipes(key, "Alchemy")
    assert_equal(0, #list)
end

function T.test_get_known_recipes_defaults_to_current_char()
    local data = RecipeBook:GetMyCharData()
    data.knownProfessions[ALCHEMY] = true
    local rid
    for id in pairs(RecipeBook.recipeDB[ALCHEMY]) do rid = id; break end
    data.knownRecipes[ALCHEMY] = { [rid] = true }

    local list = RecipeBook.API:GetKnownRecipes(nil, "Alchemy")
    assert_equal(1, #list)
end

-- ============================================================
-- GetCharacters
-- ============================================================

function T.test_get_characters_returns_all()
    makeChar("One", {})
    makeChar("Two", {})
    local list = RecipeBook.API:GetCharacters()
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    assert_true(set["One-TestRealm"])
    assert_true(set["Two-TestRealm"])
end

-- ============================================================
-- IsProfessionScanned
-- ============================================================

function T.test_is_profession_scanned_true_when_known()
    local key = makeChar("Scanned", { [ALCHEMY] = true })
    assert_true(RecipeBook.API:IsProfessionScanned(key, "Alchemy"))
end

function T.test_is_profession_scanned_false_when_not_trained()
    local key = makeChar("Untrained", {})
    assert_false(RecipeBook.API:IsProfessionScanned(key, "Alchemy"))
end

function T.test_is_profession_scanned_unknown_profession_false()
    local key = makeChar("Someone", { [ALCHEMY] = true })
    assert_false(RecipeBook.API:IsProfessionScanned(key, "Herbalism"))
end

function T.test_is_profession_scanned_unknown_char_false()
    assert_false(RecipeBook.API:IsProfessionScanned("Ghost-Realm", "Alchemy"))
end

-- ============================================================
-- Safety: no writes leak into RB state
-- ============================================================

function T.test_mutating_returned_ref_doesnt_corrupt_db()
    local list = RecipeBook.API:GetAllRecipes("Alchemy")
    local ref = list[1]
    local rid = ref.recipeID
    local originalName = RecipeBook.recipeDB[ALCHEMY][rid].name

    ref.name = "HACKED"
    ref.spellID = -1

    assert_equal(originalName, RecipeBook.recipeDB[ALCHEMY][rid].name,
        "mutating API return value must not touch internal DB")
end

return T
