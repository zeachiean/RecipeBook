-- Data integrity tests: validate that recipe/source/NPC data is well-formed.
local T = {}

local PROFESSIONS = { 171, 164, 185, 333, 202, 129, 356, 755, 165, 186, 2842, 197 }

-- ============================================================
-- Recipe data
-- ============================================================

function T.test_every_profession_has_recipe_data()
    for _, pid in ipairs(PROFESSIONS) do
        assert_not_nil(RecipeBook.recipeDB[pid],
            "missing recipeDB for profession " .. pid)
    end
end

function T.test_recipes_have_required_fields()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            assert_not_nil(data.phase,
                string.format("[%d][%d] missing phase", pid, rid))
            -- Skill-tier unlock items (teaches = "Expert"/"Artisan"/"Master")
            -- don't need requiredSkill.
            if type(data.teaches) ~= "string" then
                assert_not_nil(data.requiredSkill,
                    string.format("[%d][%d] missing requiredSkill", pid, rid))
            end
        end
    end
end

function T.test_recipes_have_valid_phase()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            if data.phase then
                assert_true(data.phase >= 1 and data.phase <= 5,
                    string.format("[%d][%d] phase %d out of range", pid, rid, data.phase))
            end
        end
    end
end

function T.test_recipe_count_sanity()
    -- Sanity: at least 10 recipes per profession, 2000+ total
    local total = 0
    for _, pid in ipairs(PROFESSIONS) do
        local count = 0
        for _ in pairs(RecipeBook.recipeDB[pid]) do count = count + 1 end
        assert_true(count >= 4,
            string.format("profession %d has too few recipes: %d", pid, count))
        total = total + count
    end
    assert_true(total >= 1800, "total recipe count too low: " .. total)
end

-- ============================================================
-- Source data
-- ============================================================

function T.test_every_profession_has_source_data()
    for _, pid in ipairs(PROFESSIONS) do
        assert_not_nil(RecipeBook.sourceDB[pid],
            "missing sourceDB for profession " .. pid)
    end
end

function T.test_source_types_are_valid()
    local valid = {
        trainer = true, vendor = true, quest = true,
        drop = true, pickpocket = true, object = true,
        item = true, fishing = true, unique = true,
        discovery = true, worldDrop = true,
    }
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            for srcType in pairs(sources) do
                assert_true(valid[srcType],
                    string.format("[%d][%d] invalid source type: %s", pid, rid, srcType))
            end
        end
    end
end

function T.test_trainer_sources_reference_valid_npcs()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.trainer and type(sources.trainer) == "table" then
                for npcID in pairs(sources.trainer) do
                    assert_not_nil(RecipeBook.npcDB[npcID],
                        string.format("[%d][%d] trainer NPC %d not in npcDB", pid, rid, npcID))
                end
            end
        end
    end
end

function T.test_vendor_sources_reference_valid_npcs()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.vendor and type(sources.vendor) == "table" then
                for npcID in pairs(sources.vendor) do
                    assert_not_nil(RecipeBook.npcDB[npcID],
                        string.format("[%d][%d] vendor NPC %d not in npcDB", pid, rid, npcID))
                end
            end
        end
    end
end

function T.test_drop_sources_reference_valid_npcs()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.drop and type(sources.drop) == "table" then
                for npcID in pairs(sources.drop) do
                    assert_not_nil(RecipeBook.npcDB[npcID],
                        string.format("[%d][%d] drop NPC %d not in npcDB", pid, rid, npcID))
                end
            end
        end
    end
end

function T.test_quest_sources_reference_valid_quests()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.quest and type(sources.quest) == "table" then
                for questID in pairs(sources.quest) do
                    assert_not_nil(RecipeBook.questDB[questID],
                        string.format("[%d][%d] quest %d not in questDB", pid, rid, questID))
                end
            end
        end
    end
end

function T.test_object_sources_reference_valid_objects()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.object and type(sources.object) == "table" then
                for objID in pairs(sources.object) do
                    assert_not_nil(RecipeBook.objectDB[objID],
                        string.format("[%d][%d] object %d not in objectDB", pid, rid, objID))
                end
            end
        end
    end
end

function T.test_npc_faction_values_are_valid()
    local valid = { Alliance = true, Horde = true }
    for npcID, npc in pairs(RecipeBook.npcDB) do
        if npc.faction then
            assert_true(valid[npc.faction],
                string.format("NPC %d has invalid faction: %s", npcID, tostring(npc.faction)))
        end
    end
end

function T.test_npc_zones_are_tables()
    for npcID, npc in pairs(RecipeBook.npcDB) do
        if npc.zones then
            assert_true(type(npc.zones) == "table",
                string.format("NPC %d zones should be table", npcID))
            assert_true(#npc.zones > 0,
                string.format("NPC %d zones should not be empty", npcID))
        end
    end
end

function T.test_worlddrop_entries_are_valid()
    -- worldDrop must be either `true` or a non-empty table of area IDs
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            local wd = sources.worldDrop
            if wd ~= nil then
                assert_true(wd == true or type(wd) == "table",
                    string.format("[%d][%d] worldDrop must be true or table", pid, rid))
                if type(wd) == "table" then
                    for i, v in ipairs(wd) do
                        assert_true(type(v) == "number" and v > 0,
                            string.format("[%d][%d] worldDrop[%d] invalid area ID: %s",
                                pid, rid, i, tostring(v)))
                    end
                end
            end
        end
    end
end

function T.test_unique_sources_are_arrays()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            if sources.unique then
                assert_true(type(sources.unique) == "table",
                    string.format("[%d][%d] unique should be table", pid, rid))
                -- Should be an array (ipairs), not a map
                for i, uid in ipairs(sources.unique) do
                    assert_true(type(uid) == "number",
                        string.format("[%d][%d] unique[%d] should be number", pid, rid, i))
                end
            end
        end
    end
end

return T
