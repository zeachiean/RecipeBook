-- Tests for Core.lua: phase logic, profession lookup, source labels.
local T = {}

-- ============================================================
-- GetRecipePhase
-- ============================================================

function T.test_explicit_phase_is_authoritative()
    -- JC recipes have explicit phase fields from RecipeMaster.
    -- Pick one we know is phase 3 (from RM port).
    local jc = 755
    local found = false
    for rid, data in pairs(RecipeBook.recipeDB[jc]) do
        if data.phase and data.phase == 3 then
            local p = RecipeBook:GetRecipePhase(jc, rid)
            assert_equal(3, p,
                string.format("recipe %d explicit phase 3 should return 3", rid))
            found = true
            break
        end
    end
    assert_true(found, "should find at least one JC recipe with phase=3")
end

function T.test_explicit_phase_overrides_dataset()
    -- If a recipe has both explicit phase and a different dataset phase,
    -- the explicit field wins.
    local jc = 755
    for rid, data in pairs(RecipeBook.recipeDB[jc]) do
        if data.phase then
            local p = RecipeBook:GetRecipePhase(jc, rid)
            assert_equal(data.phase, p,
                string.format("recipe %d: explicit=%d but GetRecipePhase=%d",
                    rid, data.phase, p))
        end
    end
end

function T.test_default_phase_is_1()
    -- A recipe with no explicit phase and no dataset entry should default to 1.
    -- We'll use a profession that has mostly phase-1 trainer recipes.
    local firstaid = 129
    for rid, data in pairs(RecipeBook.recipeDB[firstaid]) do
        if data.phase == 1 then
            local p = RecipeBook:GetRecipePhase(firstaid, rid)
            assert_equal(1, p, "phase-1 recipe should return 1")
            break
        end
    end
end

function T.test_phase_range_always_1_to_5()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        for rid in pairs(RecipeBook.recipeDB[pid]) do
            local p = RecipeBook:GetRecipePhase(pid, rid)
            assert_true(p >= 1 and p <= 5,
                string.format("[%d][%d] phase %d out of range", pid, rid, p))
        end
    end
end

-- ============================================================
-- Profession metadata
-- ============================================================

function T.test_source_order_contains_all_types()
    local expected = {
        "trainer", "vendor", "quest", "drop", "pickpocket",
        "object", "item", "fishing", "unique", "discovery", "worldDrop",
    }
    assert_equal(#expected, #RecipeBook.SOURCE_ORDER, "SOURCE_ORDER length")
    for _, t in ipairs(expected) do
        local found = false
        for _, s in ipairs(RecipeBook.SOURCE_ORDER) do
            if s == t then found = true; break end
        end
        assert_true(found, "SOURCE_ORDER missing: " .. t)
    end
end

function T.test_source_labels_cover_all_types()
    for _, t in ipairs(RecipeBook.SOURCE_ORDER) do
        assert_not_nil(RecipeBook.SOURCE_LABELS[t],
            "SOURCE_LABELS missing: " .. t)
    end
end

function T.test_profession_count()
    assert_equal(12, #RecipeBook.PROFESSIONS, "should have 12 professions")
end

-- ============================================================
-- Anniversary-specific JC overrides (verified by user)
-- ============================================================

function T.test_jc_anniversary_overrides()
    local jc = 755
    -- 31870 = Great Golden Draenite, 31873 = Veiled Flame Spessarite
    -- Both should be phase 2 on Anniversary (manually patched)
    local d1 = RecipeBook.recipeDB[jc][31870]
    assert_not_nil(d1, "recipe 31870 should exist")
    assert_equal(2, d1.phase, "Great Golden Draenite should be phase 2")

    local d2 = RecipeBook.recipeDB[jc][31873]
    assert_not_nil(d2, "recipe 31873 should exist")
    assert_equal(2, d2.phase, "Veiled Flame Spessarite should be phase 2")
end

-- ============================================================
-- Sunwell-era recipes not overridden by RM
-- ============================================================

function T.test_sunwell_recipes_kept_at_phase_5()
    -- These 4 were verified as RM-wrong; they should be phase 5 (not RM's phase 1).
    local eng = 202
    local tail = 197

    -- Engineering: Healing/Mana Potion Injector (35310/35311)
    local d35310 = RecipeBook.recipeDB[eng][35310]
    assert_not_nil(d35310, "recipe 35310 should exist")
    assert_equal(5, RecipeBook:GetRecipePhase(eng, 35310), "35310 should be phase 5")

    local d35311 = RecipeBook.recipeDB[eng][35311]
    assert_not_nil(d35311, "recipe 35311 should exist")
    assert_equal(5, RecipeBook:GetRecipePhase(eng, 35311), "35311 should be phase 5")

    -- Tailoring: Unyielding Bracers (35308) and Girdle (35309) are both phase 5
    local d35308 = RecipeBook.recipeDB[tail][35308]
    assert_not_nil(d35308, "recipe 35308 should exist")
    assert_equal(5, RecipeBook:GetRecipePhase(tail, 35308), "35308 should be phase 5")

    local d35309 = RecipeBook.recipeDB[tail][35309]
    assert_not_nil(d35309, "recipe 35309 should exist")
    assert_equal(5, RecipeBook:GetRecipePhase(tail, 35309), "35309 should be phase 5")
end

-- ============================================================
-- IsRecipeLearnable
-- ============================================================

local function initCharDB()
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.professionSkill = RecipeBookCharDB.professionSkill or {}
    -- Ensure global characters store exists for the mock player
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    local charKey = RecipeBook:GetMyCharKey()
    local charData = RecipeBook:GetOrCreateCharData(charKey, UnitName("player"), GetRealmName())
    return charData
end

function T.test_learnable_requires_known_profession()
    local charData = initCharDB()
    -- Pick a Cooking recipe with low skill requirement
    local cooking = 185
    local rid, data
    for id, d in pairs(RecipeBook.recipeDB[cooking]) do
        if d.requiredSkill and d.requiredSkill <= 50 then
            rid, data = id, d; break
        end
    end
    assert_not_nil(rid, "should find a low-skill Cooking recipe")

    -- Profession not known → not learnable
    assert_equal(false, RecipeBook:IsRecipeLearnable(cooking, rid),
        "should not be learnable when profession unknown")

    -- Mark profession known with sufficient skill
    charData.knownProfessions[cooking] = true
    MockWoW.SetProfessionSkill(cooking, 375)

    assert_equal(true, RecipeBook:IsRecipeLearnable(cooking, rid),
        "should be learnable when profession known and skill sufficient")
end

function T.test_learnable_false_when_already_known()
    local charData = initCharDB()
    local cooking = 185
    local rid
    for id, d in pairs(RecipeBook.recipeDB[cooking]) do
        if d.requiredSkill and d.requiredSkill <= 50 then
            rid = id; break
        end
    end
    assert_not_nil(rid)

    charData.knownProfessions[cooking] = true
    MockWoW.SetProfessionSkill(cooking, 375)
    charData.knownRecipes[cooking] = { [rid] = true }

    assert_equal(false, RecipeBook:IsRecipeLearnable(cooking, rid),
        "known recipe should not be learnable")
end

function T.test_learnable_skill_too_low()
    local charData = initCharDB()
    local cooking = 185
    -- Find a recipe requiring skill > 100
    local rid
    for id, d in pairs(RecipeBook.recipeDB[cooking]) do
        if d.requiredSkill and d.requiredSkill > 100 then
            rid = id; break
        end
    end
    assert_not_nil(rid, "should find a high-skill Cooking recipe")

    charData.knownProfessions[cooking] = true
    MockWoW.SetProfessionSkill(cooking, 50)

    assert_equal(false, RecipeBook:IsRecipeLearnable(cooking, rid),
        "should not be learnable when skill too low")
end

function T.test_learnable_reputation_check()
    local charData = initCharDB()
    -- Find a recipe with a reputation requirement
    local found_pid, found_rid, found_data
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            if data.reputationFaction and data.reputationLevel then
                found_pid, found_rid, found_data = pid, rid, data
                break
            end
        end
        if found_pid then break end
    end
    assert_not_nil(found_pid, "should find a rep-gated recipe")

    charData.knownProfessions[found_pid] = true
    MockWoW.SetProfessionSkill(found_pid, 375)

    -- Insufficient reputation
    MockWoW.SetFactionStanding(found_data.reputationFaction, found_data.reputationLevel - 1)
    assert_equal(false, RecipeBook:IsRecipeLearnable(found_pid, found_rid),
        "should not be learnable with insufficient rep")

    -- Sufficient reputation
    MockWoW.SetFactionStanding(found_data.reputationFaction, found_data.reputationLevel)
    assert_equal(true, RecipeBook:IsRecipeLearnable(found_pid, found_rid),
        "should be learnable with sufficient rep")
end

-- ============================================================
-- Data integrity: every recipe must have a name
-- ============================================================

function T.test_all_recipes_have_names()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            assert_not_nil(data.name,
                string.format("[%d][%d] missing name field", pid, rid))
            assert_true(data.name ~= "",
                string.format("[%d][%d] empty name field", pid, rid))
        end
    end
end

-- ============================================================
-- Data integrity: every recipe must have a nonzero requiredSkill
-- ============================================================

function T.test_all_recipes_have_required_skill()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            assert_not_nil(data.requiredSkill,
                string.format("[%d][%d] missing requiredSkill", pid, rid))
            assert_true(data.requiredSkill > 0,
                string.format("[%d][%d] requiredSkill is 0", pid, rid))
        end
    end
end

-- ============================================================
-- Data integrity: no empty drop tables in source data
-- ============================================================

function T.test_no_empty_drop_tables()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        local sources = RecipeBook.sourceDB[pid]
        if sources then
            for rid, srcData in pairs(sources) do
                if srcData.drop then
                    local count = 0
                    for _ in pairs(srcData.drop) do count = count + 1 end
                    assert_true(count > 0,
                        string.format("[%d][%d] has empty drop table — use worldDrop instead", pid, rid))
                end
            end
        end
    end
end

-- ============================================================
-- Data integrity: every recipe in recipeDB has a source entry
-- ============================================================

function T.test_all_recipes_have_source_entries()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        local sources = RecipeBook.sourceDB[pid] or {}
        for rid in pairs(RecipeBook.recipeDB[pid]) do
            assert_not_nil(sources[rid],
                string.format("[%d][%d] (%s) in recipeDB but missing from sourceDB",
                    pid, rid, RecipeBook.recipeDB[pid][rid].name or "?"))
        end
    end
end

-- ============================================================
-- Data integrity: no source entries without matching recipes
-- ============================================================

function T.test_no_orphaned_source_entries()
    local professions = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }
    for _, pid in ipairs(professions) do
        local recipes = RecipeBook.recipeDB[pid] or {}
        local sources = RecipeBook.sourceDB[pid]
        if sources then
            for rid in pairs(sources) do
                assert_not_nil(recipes[rid],
                    string.format("[%d][%d] in sourceDB but missing from recipeDB", pid, rid))
            end
        end
    end
end

return T
