-- Tests for character management, wishlist, and ignore list features.
local T = {}

local ALCHEMY = 171

-- Called before each test by the runner
function T.setup()
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = {}
    RecipeBookDB.minimap = { hide = false }
    RecipeBookDB.maxPhase = 5
    RecipeBookDB.currentPhase = 1
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.hideKnown = false
    RecipeBookCharDB.collapsedSources = {}
    RecipeBookCharDB.viewingChar = nil
    -- Ensure current character has an entry
    RecipeBook:GetMyCharData()
end

-- Pick a real recipe ID from the alchemy DB for testing
local function pickRecipeID()
    for rid in pairs(RecipeBook.recipeDB[ALCHEMY]) do
        return rid
    end
end

-- ============================================================
-- Character key building
-- ============================================================

function T.test_build_char_key()
    local key = RecipeBook:BuildCharKey("Frostmage", "Dreamscythe")
    assert_equal("Frostmage-Dreamscythe", key)
end

function T.test_build_char_key_nil_name()
    local key = RecipeBook:BuildCharKey(nil, "Dreamscythe")
    assert_nil(key, "nil name should return nil")
end

function T.test_build_char_key_nil_realm()
    local key = RecipeBook:BuildCharKey("Frostmage", nil)
    assert_nil(key, "nil realm should return nil")
end

function T.test_get_my_char_key()
    local key = RecipeBook:GetMyCharKey()
    assert_equal("TestChar-TestRealm", key)
end

-- ============================================================
-- Character data creation
-- ============================================================

function T.test_get_or_create_char_data_creates_entry()
    local key = "NewChar-TestRealm"
    local data = RecipeBook:GetOrCreateCharData(key, "NewChar", "TestRealm")
    assert_not_nil(data, "should create entry")
    assert_equal("NewChar", data.name)
    assert_equal("TestRealm", data.realm)
    assert_not_nil(data.knownProfessions)
    assert_not_nil(data.knownRecipes)
    assert_not_nil(data.wishlist)
    assert_not_nil(data.ignored)
end

function T.test_get_or_create_char_data_returns_existing()
    local key = "ExistingChar-TestRealm"
    local data1 = RecipeBook:GetOrCreateCharData(key, "ExistingChar", "TestRealm")
    data1.wishlist[ALCHEMY] = { [12345] = true }
    local data2 = RecipeBook:GetOrCreateCharData(key, "ExistingChar", "TestRealm")
    assert_true(data2.wishlist[ALCHEMY][12345] == true,
        "should return same entry, not overwrite")
end

function T.test_get_my_char_data()
    local data = RecipeBook:GetMyCharData()
    assert_not_nil(data)
    assert_equal("TestChar", data.name)
    assert_equal("TestRealm", data.realm)
end

-- ============================================================
-- Viewed character
-- ============================================================

function T.test_viewed_char_defaults_to_self()
    RecipeBookCharDB.viewingChar = nil
    local key = RecipeBook:GetViewedCharKey()
    assert_equal(RecipeBook:GetMyCharKey(), key)
end

function T.test_set_viewed_char_to_other()
    local otherKey = "AltChar-TestRealm"
    RecipeBook:GetOrCreateCharData(otherKey, "AltChar", "TestRealm")
    RecipeBook:SetViewedCharKey(otherKey)
    assert_equal(otherKey, RecipeBook:GetViewedCharKey())
end

function T.test_set_viewed_char_to_self_clears()
    local myKey = RecipeBook:GetMyCharKey()
    RecipeBook:SetViewedCharKey(myKey)
    assert_nil(RecipeBookCharDB.viewingChar,
        "viewing self should clear viewingChar")
    assert_equal(myKey, RecipeBook:GetViewedCharKey())
end

function T.test_set_viewed_char_invalid_falls_back()
    RecipeBookCharDB.viewingChar = "Nonexistent-FakeRealm"
    local key = RecipeBook:GetViewedCharKey()
    assert_equal(RecipeBook:GetMyCharKey(), key,
        "invalid viewingChar should fall back to self")
end

function T.test_get_viewed_char_data()
    local data = RecipeBook:GetViewedCharData()
    assert_not_nil(data)
    assert_equal("TestChar", data.name)
end

-- ============================================================
-- Get all character keys
-- ============================================================

function T.test_get_all_char_keys_sorted()
    RecipeBook:GetOrCreateCharData("Zephyr-Realm", "Zephyr", "Realm")
    RecipeBook:GetOrCreateCharData("Alpha-Realm", "Alpha", "Realm")
    local keys = RecipeBook:GetAllCharKeys()
    assert_true(#keys >= 2, "should have at least 2 characters")
    -- Verify sorted
    for i = 2, #keys do
        assert_true(keys[i - 1] <= keys[i],
            "keys should be sorted: " .. keys[i - 1] .. " <= " .. keys[i])
    end
end

-- ============================================================
-- Profession known
-- ============================================================

function T.test_profession_not_known_by_default()
    assert_false(RecipeBook:IsProfessionKnown(ALCHEMY),
        "professions should not be known by default")
end

function T.test_profession_known_after_set()
    local data = RecipeBook:GetMyCharData()
    data.knownProfessions[ALCHEMY] = true
    assert_true(RecipeBook:IsProfessionKnown(ALCHEMY))
end

function T.test_profession_known_for_specific_char()
    local altKey = "Alt-TestRealm"
    local altData = RecipeBook:GetOrCreateCharData(altKey, "Alt", "TestRealm")
    altData.knownProfessions[ALCHEMY] = true
    assert_true(RecipeBook:IsProfessionKnown(ALCHEMY, altKey))
    -- Current char should not know it (unless set separately)
    local myData = RecipeBook:GetMyCharData()
    if not myData.knownProfessions[ALCHEMY] then
        assert_false(RecipeBook:IsProfessionKnown(ALCHEMY))
    end
end

-- ============================================================
-- Wishlist
-- ============================================================

function T.test_recipe_not_in_wishlist_by_default()
    local rid = pickRecipeID()
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
end

function T.test_set_recipe_wishlist_add()
    local rid = pickRecipeID()
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, true)
    assert_true(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
end

function T.test_set_recipe_wishlist_remove()
    local rid = pickRecipeID()
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, true)
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, false)
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
end

function T.test_toggle_recipe_wishlist()
    local rid = pickRecipeID()
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
    RecipeBook:ToggleRecipeWishlist(ALCHEMY, rid)
    assert_true(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
    RecipeBook:ToggleRecipeWishlist(ALCHEMY, rid)
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
end

function T.test_wishlist_per_character()
    local rid = pickRecipeID()
    local altKey = "WishAlt-TestRealm"
    RecipeBook:GetOrCreateCharData(altKey, "WishAlt", "TestRealm")

    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, true)
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, true, altKey)

    -- Remove from alt only
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, false, altKey)
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid, altKey),
        "alt should no longer have it wishlisted")
    assert_true(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid),
        "current char should still have it wishlisted")
end

-- ============================================================
-- Ignore list
-- ============================================================

function T.test_recipe_not_ignored_by_default()
    local rid = pickRecipeID()
    assert_false(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
end

function T.test_set_recipe_ignored_add()
    local rid = pickRecipeID()
    RecipeBook:SetRecipeIgnored(ALCHEMY, rid, true)
    assert_true(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
end

function T.test_set_recipe_ignored_remove()
    local rid = pickRecipeID()
    RecipeBook:SetRecipeIgnored(ALCHEMY, rid, true)
    RecipeBook:SetRecipeIgnored(ALCHEMY, rid, false)
    assert_false(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
end

function T.test_toggle_recipe_ignored()
    local rid = pickRecipeID()
    assert_false(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
    RecipeBook:ToggleRecipeIgnored(ALCHEMY, rid)
    assert_true(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
    RecipeBook:ToggleRecipeIgnored(ALCHEMY, rid)
    assert_false(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
end

function T.test_ignore_per_character()
    local rid = pickRecipeID()
    local altKey = "IgnAlt-TestRealm"
    RecipeBook:GetOrCreateCharData(altKey, "IgnAlt", "TestRealm")

    RecipeBook:SetRecipeIgnored(ALCHEMY, rid, true)
    assert_true(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))
    assert_false(RecipeBook:IsRecipeIgnored(ALCHEMY, rid, altKey),
        "alt should not be affected")
end

-- ============================================================
-- Wishlist and ignore are independent
-- ============================================================

function T.test_wishlist_and_ignore_independent()
    local rid = pickRecipeID()
    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, true)
    RecipeBook:SetRecipeIgnored(ALCHEMY, rid, true)
    assert_true(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
    assert_true(RecipeBook:IsRecipeIgnored(ALCHEMY, rid))

    RecipeBook:SetRecipeWishlist(ALCHEMY, rid, false)
    assert_false(RecipeBook:IsRecipeInWishlist(ALCHEMY, rid))
    assert_true(RecipeBook:IsRecipeIgnored(ALCHEMY, rid),
        "removing from wishlist should not affect ignore")
end

-- ============================================================
-- IsRecipeKnown uses character data model
-- ============================================================

function T.test_recipe_not_known_by_default()
    local rid = pickRecipeID()
    assert_false(RecipeBook:IsRecipeKnown(ALCHEMY, rid))
end

function T.test_recipe_known_after_marking()
    local rid = pickRecipeID()
    local data = RecipeBook:GetMyCharData()
    data.knownRecipes[ALCHEMY] = data.knownRecipes[ALCHEMY] or {}
    data.knownRecipes[ALCHEMY][rid] = true
    assert_true(RecipeBook:IsRecipeKnown(ALCHEMY, rid))
end

function T.test_recipe_known_for_specific_char()
    local rid = pickRecipeID()
    local altKey = "KnownAlt-TestRealm"
    local altData = RecipeBook:GetOrCreateCharData(altKey, "KnownAlt", "TestRealm")
    altData.knownRecipes[ALCHEMY] = { [rid] = true }

    assert_true(RecipeBook:IsRecipeKnown(ALCHEMY, rid, altKey))
    assert_false(RecipeBook:IsRecipeKnown(ALCHEMY, rid),
        "current char should not know it")
end

return T
