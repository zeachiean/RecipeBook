-- Tests for GetRecipeStatusForChar tooltip logic.
local T = {}

local ALCHEMY = 171
local SKILL_RECIPE = 3827     -- Mana Potion, requiredSkill = 160
local REP_RECIPE = 35752      -- Guardian's Alchemist Stone, repFaction=1077, repLevel=8, reqSkill=375

-- Helper: set up a character with alchemy known at a given skill
local function makeAlchemist(name, skill, class)
    local key = name .. "-TestRealm"
    local data = RecipeBook:GetOrCreateCharData(key, name, "TestRealm")
    data.knownProfessions[ALCHEMY] = true
    data.professionSkill = data.professionSkill or {}
    data.professionSkill[ALCHEMY] = skill
    data.class = class or "MAGE"
    return key, data
end

function T.setup()
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = {}
    RecipeBookDB.ignoredCharacters = nil
    RecipeBookDB.minimap = { hide = false }
    RecipeBookDB.maxPhase = 5
    RecipeBookDB.currentPhase = 1
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.hideKnown = false
    RecipeBookCharDB.collapsedSources = {}
    RecipeBookCharDB.viewingChar = nil
    RecipeBookCharDB.professionSkill = {}
    RecipeBook:GetMyCharData()
end

-- ============================================================
-- Positive: character knows the recipe
-- ============================================================

function T.test_status_knows_when_recipe_is_known()
    local key, data = makeAlchemist("Alch", 375)
    data.knownRecipes[ALCHEMY] = { [SKILL_RECIPE] = true }

    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("knows", status)
end

-- ============================================================
-- Positive: character can learn the recipe
-- ============================================================

function T.test_status_learnable_when_skill_sufficient()
    local key = makeAlchemist("Alch", 300)
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("learnable", status)
end

function T.test_status_learnable_at_exact_skill()
    local key = makeAlchemist("Alch", 160)  -- exactly requiredSkill
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("learnable", status)
end

-- ============================================================
-- Positive: low skill
-- ============================================================

function T.test_status_low_skill_when_below_required()
    local key = makeAlchemist("Alch", 100)  -- below 160
    local status, cur, req = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("lowSkill", status)
    assert_equal(100, cur)
    assert_equal(160, req)
end

function T.test_status_low_skill_at_one_below()
    local key = makeAlchemist("Alch", 159)
    local status, cur, req = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("lowSkill", status)
    assert_equal(159, cur)
    assert_equal(160, req)
end

-- ============================================================
-- Positive: low rep (only works for current character)
-- ============================================================

function T.test_status_low_rep_for_current_char()
    -- Make the current test character an alchemist
    local myKey = RecipeBook:GetMyCharKey()
    local data = RecipeBook:GetMyCharData()
    data.knownProfessions[ALCHEMY] = true
    data.professionSkill = { [ALCHEMY] = 375 }
    -- Also set per-character DB so GetProfessionSkill finds it
    RecipeBookCharDB.professionSkill[ALCHEMY] = 375

    -- Set rep to Revered (7) when Exalted (8) is required
    MockWoW.SetFactionStanding(1077, 7)

    local status, cur, req = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, myKey)
    assert_equal("lowRep", status)
    assert_equal("Revered", cur)
    assert_equal("Exalted", req)
end

function T.test_status_learnable_when_rep_met()
    local myKey = RecipeBook:GetMyCharKey()
    local data = RecipeBook:GetMyCharData()
    data.knownProfessions[ALCHEMY] = true
    data.professionSkill = { [ALCHEMY] = 375 }
    RecipeBookCharDB.professionSkill[ALCHEMY] = 375

    -- Set rep to Exalted (8), which is required
    MockWoW.SetFactionStanding(1077, 8)

    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, myKey)
    assert_equal("learnable", status)
end

-- ============================================================
-- Negative: character does not have the profession
-- ============================================================

function T.test_status_nil_when_profession_not_known()
    local key = "NoProfChar-TestRealm"
    RecipeBook:GetOrCreateCharData(key, "NoProfChar", "TestRealm")

    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_nil(status, "should return nil for character without the profession")
end

-- ============================================================
-- Negative: character doesn't exist
-- ============================================================

function T.test_status_nil_for_nonexistent_character()
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, "Nobody-Nowhere")
    assert_nil(status, "should return nil for unknown character")
end

-- ============================================================
-- Negative: invalid recipe ID
-- ============================================================

function T.test_status_nil_for_invalid_recipe()
    local key = makeAlchemist("Alch", 375)
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, 99999999, key)
    assert_nil(status, "should return nil for nonexistent recipe data")
end

-- ============================================================
-- Negative: rep not checkable for non-current character
-- ============================================================

function T.test_rep_checked_for_alt_via_saved_standings()
    local key, data = makeAlchemist("AltAlch", 375)
    -- Simulate saved rep standings (Honored = 6, Exalted = 8 required)
    data.reputationStandings = { [1077] = 6 }
    local status, cur, req = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, key)
    assert_equal("lowRep", status)
    assert_equal("Honored", cur)
    assert_equal("Exalted", req)
end

function T.test_rep_learnable_for_alt_when_rep_met()
    local key, data = makeAlchemist("AltAlch", 375)
    data.reputationStandings = { [1077] = 8 }  -- Exalted
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, key)
    assert_equal("learnable", status)
end

function T.test_rep_unknown_for_alt_without_saved_standings()
    local key = makeAlchemist("AltAlch", 375)
    -- No saved standings at all — can't determine rep, assume learnable
    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, key)
    assert_equal("learnable", status)
end

-- ============================================================
-- Negative: known recipe is "knows", not "learnable"
-- ============================================================

function T.test_known_recipe_not_learnable()
    local key, data = makeAlchemist("Alch", 375)
    data.knownRecipes[ALCHEMY] = { [SKILL_RECIPE] = true }

    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, SKILL_RECIPE, key)
    assert_equal("knows", status, "known recipe should be 'knows', not 'learnable'")
end

-- ============================================================
-- Skill priority: lowSkill checked before rep
-- ============================================================

function T.test_low_skill_takes_priority_over_rep()
    local myKey = RecipeBook:GetMyCharKey()
    local data = RecipeBook:GetMyCharData()
    data.knownProfessions[ALCHEMY] = true
    data.professionSkill = { [ALCHEMY] = 100 }
    RecipeBookCharDB.professionSkill[ALCHEMY] = 100

    -- Rep is also low, but skill check comes first
    MockWoW.SetFactionStanding(1077, 5)

    local status = RecipeBook:GetRecipeStatusForChar(ALCHEMY, REP_RECIPE, myKey)
    assert_equal("lowSkill", status, "low skill should take priority over low rep")
end

-- ============================================================
-- GetProfessionSkill for other characters via global store
-- ============================================================

function T.test_get_profession_skill_from_global_store()
    local key = makeAlchemist("RemoteAlch", 275)
    local skill = RecipeBook:GetProfessionSkill(ALCHEMY, key)
    assert_equal(275, skill)
end

function T.test_get_profession_skill_nil_when_not_set()
    local key = "NoSkillChar-TestRealm"
    RecipeBook:GetOrCreateCharData(key, "NoSkillChar", "TestRealm")
    local skill = RecipeBook:GetProfessionSkill(ALCHEMY, key)
    assert_nil(skill, "should return nil when no skill data exists")
end

return T
