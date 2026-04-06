-- Tests for UIDropSources.lua: CollectAllSources faction filtering
local T = {}

-- Leatherworking profession ID
local LW = 165

-- Helper: count entries by faction
local function countByFaction(entries)
    local a, h, n = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.faction == "Alliance" then a = a + 1
        elseif e.faction == "Horde" then h = h + 1
        else n = n + 1
        end
    end
    return a, h, n
end

-- Helper: find a trainer recipe with both Alliance and Horde trainers
local function findDualFactionTrainerRecipe()
    local sources = RecipeBook.sourceDB[LW]
    for rid, src in pairs(sources) do
        if src.trainer then
            local aCount, hCount = 0, 0
            for npcID in pairs(src.trainer) do
                local npc = RecipeBook.npcDB[npcID]
                if npc and npc.faction == "Alliance" then aCount = aCount + 1
                elseif npc and npc.faction == "Horde" then hCount = hCount + 1
                end
            end
            if aCount >= 2 and hCount >= 2 then
                return rid, aCount, hCount
            end
        end
    end
    error("Could not find a dual-faction trainer recipe for testing")
end

-- ============================================================
-- TESTS
-- ============================================================

function T.test_collect_all_sources_returns_entries()
    local rid = findDualFactionTrainerRecipe()
    local entries = RecipeBook.CollectAllSources(LW, rid)
    assert_true(#entries > 0, "should return at least one source")
end

function T.test_collect_no_faction_filter_returns_all()
    local rid, aExpected, hExpected = findDualFactionTrainerRecipe()
    local entries = RecipeBook.CollectAllSources(LW, rid, nil)
    local a, h = countByFaction(entries)
    assert_true(a >= aExpected, "unfiltered should include Alliance trainers")
    assert_true(h >= hExpected, "unfiltered should include Horde trainers")
end

function T.test_collect_alliance_filter_excludes_horde_trainers()
    local rid = findDualFactionTrainerRecipe()
    local entries = RecipeBook.CollectAllSources(LW, rid, "Alliance")
    local a, h = countByFaction(entries)
    assert_true(a > 0, "Alliance filter should include Alliance trainers")
    assert_equal(0, h, "Alliance filter should exclude Horde trainers")
end

function T.test_collect_horde_filter_excludes_alliance_trainers()
    local rid = findDualFactionTrainerRecipe()
    local entries = RecipeBook.CollectAllSources(LW, rid, "Horde")
    local a, h = countByFaction(entries)
    assert_equal(0, a, "Horde filter should exclude Alliance trainers")
    assert_true(h > 0, "Horde filter should include Horde trainers")
end

function T.test_collect_faction_filter_keeps_neutral_npcs()
    -- Find a recipe with a neutral trainer (faction = nil on the NPC)
    local sources = RecipeBook.sourceDB[LW]
    local neutralRid
    for rid, src in pairs(sources) do
        if src.trainer then
            for npcID in pairs(src.trainer) do
                local npc = RecipeBook.npcDB[npcID]
                if npc and not npc.faction then
                    neutralRid = rid
                    break
                end
            end
            if neutralRid then break end
        end
    end
    if not neutralRid then
        -- Skip if no neutral trainers exist in data
        return
    end
    local entries = RecipeBook.CollectAllSources(LW, neutralRid, "Alliance")
    local _, _, n = countByFaction(entries)
    assert_true(n > 0, "faction filter should keep neutral NPCs")
end

function T.test_collect_faction_filter_applies_to_vendors()
    -- Find a recipe with faction-specific vendors
    local professions = { 171, 164, 185, 333, 202, 129, 755, 165, 197 }
    local vendorRid, vendorProfID
    for _, pid in ipairs(professions) do
        local sources = RecipeBook.sourceDB[pid]
        if sources then
            for rid, src in pairs(sources) do
                if src.vendor then
                    local aCount, hCount = 0, 0
                    for npcID in pairs(src.vendor) do
                        local npc = RecipeBook.npcDB[npcID]
                        if npc and npc.faction == "Alliance" then aCount = aCount + 1
                        elseif npc and npc.faction == "Horde" then hCount = hCount + 1
                        end
                    end
                    if aCount > 0 and hCount > 0 then
                        vendorRid = rid
                        vendorProfID = pid
                        break
                    end
                end
            end
            if vendorRid then break end
        end
    end
    if not vendorRid then return end  -- skip if not found
    local entries = RecipeBook.CollectAllSources(vendorProfID, vendorRid, "Alliance")
    for _, e in ipairs(entries) do
        if e.sourceType == "vendor" then
            assert_true(e.faction ~= "Horde",
                "Alliance filter should not include Horde vendors")
        end
    end
end

function T.test_collect_drops_not_filtered_by_faction()
    -- Drops should NOT be filtered by faction — mobs don't have faction restrictions
    local sources = RecipeBook.sourceDB[LW]
    local dropRid
    for rid, src in pairs(sources) do
        if src.drop then
            for npcID in pairs(src.drop) do
                local npc = RecipeBook.npcDB[npcID]
                if npc then
                    dropRid = rid
                    break
                end
            end
            if dropRid then break end
        end
    end
    if not dropRid then return end
    -- Drops should appear regardless of faction filter
    local entriesA = RecipeBook.CollectAllSources(LW, dropRid, "Alliance")
    local entriesH = RecipeBook.CollectAllSources(LW, dropRid, "Horde")
    local dropsA, dropsH = 0, 0
    for _, e in ipairs(entriesA) do if e.sourceType == "drop" then dropsA = dropsA + 1 end end
    for _, e in ipairs(entriesH) do if e.sourceType == "drop" then dropsH = dropsH + 1 end end
    assert_equal(dropsA, dropsH, "drops should not be filtered by faction")
end

function T.test_collect_quests_filtered_by_faction()
    -- Find a recipe with faction-specific quests
    local professions = { 171, 164, 185, 333, 202, 129, 755, 165, 197 }
    local questRid, questProfID
    for _, pid in ipairs(professions) do
        local sources = RecipeBook.sourceDB[pid]
        if sources then
            for rid, src in pairs(sources) do
                if src.quest then
                    for questID in pairs(src.quest) do
                        local q = RecipeBook.questDB and RecipeBook.questDB[questID]
                        if q and q.faction then
                            questRid = rid
                            questProfID = pid
                            break
                        end
                    end
                    if questRid then break end
                end
            end
            if questRid then break end
        end
    end
    if not questRid then return end
    local entries = RecipeBook.CollectAllSources(questProfID, questRid, "Alliance")
    for _, e in ipairs(entries) do
        if e.sourceType == "quest" then
            assert_true(e.faction ~= "Horde",
                "Alliance filter should not include Horde-only quests")
        end
    end
end

-- ============================================================
-- Source count / popup consistency
-- ============================================================

function T.test_source_count_matches_popup_with_faction_filter()
    local rid, aExpected = findDualFactionTrainerRecipe()
    local count = RecipeBook.GetSourceCount(LW, rid, "Alliance")
    local entries = RecipeBook.CollectAllSources(LW, rid, "Alliance")
    assert_equal(#entries, count,
        "GetSourceCount with faction filter should match CollectAllSources entry count")
end

function T.test_source_count_matches_popup_without_faction_filter()
    local rid = findDualFactionTrainerRecipe()
    local count = RecipeBook.GetSourceCount(LW, rid, nil)
    local entries = RecipeBook.CollectAllSources(LW, rid, nil)
    assert_equal(#entries, count,
        "GetSourceCount without filter should match CollectAllSources entry count")
end

function T.test_source_count_differs_by_faction()
    local rid = findDualFactionTrainerRecipe()
    local countAll = RecipeBook.GetSourceCount(LW, rid, nil)
    local countA = RecipeBook.GetSourceCount(LW, rid, "Alliance")
    local countH = RecipeBook.GetSourceCount(LW, rid, "Horde")
    assert_true(countAll > countA, "unfiltered count should exceed Alliance-only count")
    assert_true(countAll > countH, "unfiltered count should exceed Horde-only count")
end

-- ============================================================
-- Trainer waypoint name
-- ============================================================

function T.test_profession_names_end_with_trainer_for_waypoint()
    -- Verify that PROFESSION_NAMES entries exist and that appending " Trainer"
    -- produces the expected AddressBook search term.
    local professions = { 171, 164, 185, 333, 202, 129, 755, 165, 186, 197 }
    for _, pid in ipairs(professions) do
        local name = RecipeBook.PROFESSION_NAMES[pid]
        assert_not_nil(name, "PROFESSION_NAMES missing for " .. pid)
        local wpName = name .. " Trainer"
        assert_true(wpName:find("Trainer$") ~= nil,
            pid .. ": waypoint name should end with Trainer, got: " .. wpName)
    end
end

return T
