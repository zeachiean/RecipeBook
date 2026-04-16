-- Tests for the Reset section buttons in Settings.lua.
-- Each button shows a StaticPopup confirmation; we test the OnAccept handlers.
local T = {}

-- Extra UI stubs needed by Settings.lua
UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth or function() end

-- Load Settings.lua once at module level to verify it parses
dofile("Settings.lua")

function T.setup()
    -- Reload Settings.lua after MockWoW.reset() wipes StaticPopupDialogs
    UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth or function() end
    dofile("Settings.lua")
end

local function initCharDB()
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.professionSkill = RecipeBookCharDB.professionSkill or {}
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    local charKey = RecipeBook:GetMyCharKey()
    return RecipeBook:GetOrCreateCharData(charKey, UnitName("player"), GetRealmName())
end

local function populateCharData()
    local charData = initCharDB()
    local cooking = 185
    charData.knownProfessions[cooking] = true
    charData.knownRecipes[cooking] = { [12345] = true, [67890] = true }
    charData.professionSkill = charData.professionSkill or {}
    charData.professionSkill[cooking] = 375
    charData.wishlist[cooking] = { [11111] = true }
    charData.ignored[cooking] = { [22222] = true }
    RecipeBookCharDB.professionSkill[cooking] = 375
    RecipeBookCharDB.selectedProfession = cooking
    return charData
end

-- ============================================================
-- Clear Profession Data
-- ============================================================

function T.test_clear_prof_wipes_known_professions()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_table_length(charData.knownProfessions, 0,
        "knownProfessions should be empty")
end

function T.test_clear_prof_wipes_known_recipes()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_table_length(charData.knownRecipes, 0,
        "knownRecipes should be empty")
end

function T.test_clear_prof_wipes_profession_skill()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_table_length(charData.professionSkill, 0,
        "global professionSkill should be empty")
    assert_table_length(RecipeBookCharDB.professionSkill, 0,
        "per-char professionSkill should be empty")
end

function T.test_clear_prof_clears_selected_profession()
    populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_nil(RecipeBookCharDB.selectedProfession,
        "selectedProfession should be nil")
end

function T.test_clear_prof_preserves_wishlists()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_not_nil(charData.wishlist[185],
        "wishlist should be preserved")
    assert_true(charData.wishlist[185][11111],
        "wishlist entry should remain")
end

function T.test_clear_prof_preserves_ignored()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"].OnAccept()

    assert_not_nil(charData.ignored[185],
        "ignored should be preserved")
    assert_true(charData.ignored[185][22222],
        "ignored entry should remain")
end

-- ============================================================
-- Clear All Character Data
-- ============================================================

function T.test_clear_char_wipes_known_professions()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_table_length(charData.knownProfessions, 0,
        "knownProfessions should be empty")
end

function T.test_clear_char_wipes_known_recipes()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_table_length(charData.knownRecipes, 0,
        "knownRecipes should be empty")
end

function T.test_clear_char_wipes_profession_skill()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_table_length(charData.professionSkill, 0,
        "global professionSkill should be empty")
    assert_table_length(RecipeBookCharDB.professionSkill, 0,
        "per-char professionSkill should be empty")
end

function T.test_clear_char_wipes_wishlists()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_table_length(charData.wishlist, 0,
        "wishlist should be empty")
end

function T.test_clear_char_wipes_ignored()
    local charData = populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_table_length(charData.ignored, 0,
        "ignored should be empty")
end

function T.test_clear_char_clears_selected_profession()
    populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"].OnAccept()

    assert_nil(RecipeBookCharDB.selectedProfession,
        "selectedProfession should be nil")
end

-- ============================================================
-- Reset All
-- ============================================================

function T.test_reset_all_wipes_all_characters()
    populateCharData()

    -- Add a second character
    local altKey = "AltChar-TestRealm"
    RecipeBook:GetOrCreateCharData(altKey, "AltChar", "TestRealm")
    RecipeBookDB.characters[altKey].knownProfessions[185] = true

    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    -- Alt should be gone
    assert_nil(RecipeBookDB.characters[altKey],
        "alt character should be wiped")
end

function T.test_reset_all_recreates_current_character()
    populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    local myKey = RecipeBook:GetMyCharKey()
    assert_not_nil(RecipeBookDB.characters[myKey],
        "current character entry should be re-created")
    assert_table_length(RecipeBookDB.characters[myKey].knownProfessions, 0,
        "re-created character should have empty knownProfessions")
end

function T.test_reset_all_resets_account_settings()
    populateCharData()
    RecipeBookDB.maxPhase = 3
    RecipeBookDB.minCharLevel = 60
    RecipeBookDB.showTooltipInfo = false
    RecipeBookDB.minimap = { hide = true }

    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    assert_equal(5, RecipeBookDB.maxPhase, "maxPhase should reset to 5")
    assert_equal(5, RecipeBookDB.minCharLevel, "minCharLevel should reset to 5")
    assert_equal(true, RecipeBookDB.showTooltipInfo, "showTooltipInfo should reset to true")
    assert_equal(false, RecipeBookDB.minimap.hide, "minimap.hide should reset to false")
end

function T.test_reset_all_resets_per_char_settings()
    populateCharData()
    RecipeBookCharDB.hideKnown = true
    RecipeBookCharDB.hideUnlearnable = true
    RecipeBookCharDB.myFactionOnly = true
    RecipeBookCharDB.collapsedSources = { vendor = true }
    RecipeBookCharDB.viewingChar = "SomeAlt-TestRealm"

    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    assert_equal(false, RecipeBookCharDB.hideKnown, "hideKnown should reset to false")
    assert_equal(false, RecipeBookCharDB.hideUnlearnable, "hideUnlearnable should reset to false")
    assert_equal(false, RecipeBookCharDB.myFactionOnly, "myFactionOnly should reset to false")
    assert_table_length(RecipeBookCharDB.collapsedSources, 0,
        "collapsedSources should be empty")
    assert_nil(RecipeBookCharDB.viewingChar, "viewingChar should be nil")
    assert_nil(RecipeBookCharDB.selectedProfession, "selectedProfession should be nil")
end

function T.test_reset_all_clears_ignored_characters()
    populateCharData()
    RecipeBookDB.ignoredCharacters = { ["SomeChar-TestRealm"] = true }

    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    assert_table_length(RecipeBookDB.ignoredCharacters, 0,
        "ignoredCharacters should be empty")
end

function T.test_reset_all_clears_per_char_profession_skill()
    populateCharData()
    StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"].OnAccept()

    assert_table_length(RecipeBookCharDB.professionSkill, 0,
        "per-char professionSkill should be empty")
end

return T
