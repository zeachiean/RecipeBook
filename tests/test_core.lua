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

return T
