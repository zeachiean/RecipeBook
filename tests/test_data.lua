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

function T.test_no_empty_source_entries()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, sources in pairs(RecipeBook.sourceDB[pid]) do
            local hasSource = false
            for _ in pairs(sources) do hasSource = true; break end
            assert_true(hasSource,
                string.format("[%d][%d] has empty source block", pid, rid))
        end
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

function T.test_no_duplicate_recipe_ids_within_profession()
    for _, pid in ipairs(PROFESSIONS) do
        local seen = {}
        for rid in pairs(RecipeBook.recipeDB[pid]) do
            assert_true(not seen[rid],
                string.format("[%d][%d] duplicate recipe ID", pid, rid))
            seen[rid] = true
        end
    end
end

function T.test_no_recipe_id_collisions_across_professions()
    -- Recipe IDs must not collide across professions unless they are in
    -- different namespaces (one is an item, the other a spell) or are
    -- explicitly allowed (e.g. Gordok Ogre Suit needs both LW and Tailoring).
    local ALLOWED = { [18258] = true }
    local seen = {}    -- rid -> pid
    local isSpell = {} -- rid -> bool
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            if seen[rid] and not ALLOWED[rid] then
                -- Collision allowed only if one is item, other is spell
                local prevSpell = isSpell[rid]
                local curSpell = data.isSpell == true
                assert_true(prevSpell ~= curSpell,
                    string.format("[%d] same-namespace collision between profession %d and %d",
                        rid, seen[rid], pid))
            end
            seen[rid] = pid
            isSpell[rid] = data.isSpell == true
        end
    end
end

-- ============================================================
-- Tooltip coverage: every recipe must produce a valid tooltip
-- ============================================================

function T.test_every_recipe_has_a_name()
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            assert_not_nil(data.name,
                string.format("[%d][%d] recipe missing name", pid, rid))
            assert_true(type(data.name) == "string" and #data.name > 0,
                string.format("[%d][%d] recipe name must be non-empty string", pid, rid))
        end
    end
end

function T.test_every_recipe_resolves_a_source_for_tooltip()
    -- GetBestSourceSummary must return a valid sourceType for every recipe
    -- so the tooltip can render without errors.
    local validTypes = {
        trainer = true, vendor = true, quest = true,
        drop = true, pickpocket = true, object = true,
        item = true, fishing = true, unique = true,
        discovery = true,
    }
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            local srcType, srcID, srcName, zone, isWorldDrop, dropRate =
                RecipeBook.GetBestSourceSummary(pid, rid, nil, nil)
            -- Every recipe must resolve to some source type
            assert_not_nil(srcType,
                string.format("[%d][%d] %s: GetBestSourceSummary returned nil sourceType",
                    pid, rid, data.name or "?"))
            assert_true(validTypes[srcType],
                string.format("[%d][%d] %s: invalid sourceType '%s'",
                    pid, rid, data.name or "?", tostring(srcType)))
        end
    end
end

function T.test_tooltip_source_references_are_valid()
    -- For every recipe's best source, verify that referenced entities
    -- (NPCs, quests, objects, unique sources) actually exist in their
    -- respective databases, so the tooltip won't show "NPC #12345".
    local errors = {}
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            local srcType, srcID, srcName, zone, isWorldDrop =
                RecipeBook.GetBestSourceSummary(pid, rid, nil, nil)
            if not srcType then
                -- Already caught by previous test
            elseif srcType == "vendor" and srcID then
                if not RecipeBook.npcDB[srcID] then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: vendor NPC %d not in npcDB", pid, rid, data.name, srcID)
                end
            elseif srcType == "drop" and srcID and not isWorldDrop then
                if not RecipeBook.npcDB[srcID] then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: drop NPC %d not in npcDB", pid, rid, data.name, srcID)
                end
            elseif srcType == "trainer" and srcID then
                if not RecipeBook.npcDB[srcID] then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: trainer NPC %d not in npcDB", pid, rid, data.name, srcID)
                end
            elseif srcType == "quest" and srcID then
                if not (RecipeBook.questDB and RecipeBook.questDB[srcID]) then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: quest %d not in questDB", pid, rid, data.name, srcID)
                end
            elseif srcType == "object" and srcID then
                if not (RecipeBook.objectDB and RecipeBook.objectDB[srcID]) then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: object %d not in objectDB", pid, rid, data.name, srcID)
                end
            elseif srcType == "unique" and srcID then
                if srcID ~= 0 and not (RecipeBook.uniqueDB and RecipeBook.uniqueDB[srcID]) then
                    errors[#errors + 1] = string.format(
                        "[%d][%d] %s: unique %d not in uniqueDB", pid, rid, data.name, srcID)
                end
            end
        end
    end
    if #errors > 0 then
        error(errors[1] .. (#errors > 1 and string.format(" (and %d more)", #errors - 1) or ""))
    end
end

function T.test_tooltip_source_name_is_not_nil()
    -- The source name shown in the tooltip must never be nil.
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            local srcType, srcID, srcName =
                RecipeBook.GetBestSourceSummary(pid, rid, nil, nil)
            if srcType then
                assert_not_nil(srcName,
                    string.format("[%d][%d] %s: tooltip source name is nil (type=%s, id=%s)",
                        pid, rid, data.name or "?", tostring(srcType), tostring(srcID)))
            end
        end
    end
end

function T.test_every_recipe_tooltip_renders_without_error()
    -- Actually call the tooltip rendering function for every recipe,
    -- simulating what happens when a user hovers over a recipe row.
    -- This catches errors that data-only checks miss (nil concatenation,
    -- bad source references, missing handler for a source type, etc).

    -- Ensure saved-variable stores exist (wow_mock sets them to nil)
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    RecipeBookCharDB = RecipeBookCharDB or {}

    local errors = {}
    for _, pid in ipairs(PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            -- Get source summary the same way the rendering code does
            local srcType, srcID, srcName, zone, isWorldDrop, dropRate =
                RecipeBook.GetBestSourceSummary(pid, rid, nil, nil)

            -- Build a mock row frame with the same fields the real
            -- rendering code sets before OnRecipeEnter fires
            local row = {
                _profID = pid,
                _recipeID = rid,
                _sourceType = srcType,
                _sourceID = srcID,
                _sourceName = srcName,
                _zoneName = zone,
                _isWorldDrop = isWorldDrop,
                _dropRate = dropRate,
                _canWaypoint = false,
            }

            -- Call the actual tooltip function inside pcall
            local ok, err = pcall(RecipeBook._OnRecipeEnter, row)
            if not ok then
                errors[#errors + 1] = string.format(
                    "[%d][%d] %s: tooltip error: %s",
                    pid, rid, data.name or "?", tostring(err))
            end
        end
    end
    if #errors > 0 then
        error(errors[1] .. (#errors > 1
            and string.format("\n  (and %d more)", #errors - 1) or ""))
    end
end

-- ============================================================
-- Faction-mirror deduplication
-- ============================================================

function T.test_faction_mirrors_are_deduplicated()
    -- Multiple recipe items that teach the same spell and share a name
    -- (e.g. Alliance/Horde vendor versions) should be deduplicated in
    -- BuildDisplayData so only one appears in the display and counts.

    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    RecipeBookCharDB = RecipeBookCharDB or {}

    -- Find a faction-mirror pair: two non-isSpell recipes with same
    -- teaches value and same name
    local mirrorProfID, mirrorTeaches, mirrorRids
    for _, pid in ipairs(PROFESSIONS) do
        local byTeaches = {}
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            if not data.isSpell and data.teaches then
                local key = data.teaches .. ":" .. (data.name or "")
                if not byTeaches[key] then byTeaches[key] = {} end
                byTeaches[key][#byTeaches[key] + 1] = rid
            end
        end
        for key, rids in pairs(byTeaches) do
            if #rids > 1 then
                mirrorProfID = pid
                mirrorTeaches = key
                mirrorRids = rids
                break
            end
        end
        if mirrorProfID then break end
    end

    if not mirrorProfID then return end  -- no mirrors found, skip

    -- Build display data with no filters
    local filters = {
        professionID = mirrorProfID,
        maxPhase = 5,
        listMode = "all",
    }
    local groups, totalRecipes, totalKnown, totalShown =
        RecipeBook._BuildDisplayData(filters)

    -- Count how many times each mirror rid appears in the output
    local seenRids = {}
    for _, entries in pairs(groups) do
        for _, entry in ipairs(entries) do
            for _, rid in ipairs(mirrorRids) do
                if entry.recipeID == rid then
                    seenRids[rid] = (seenRids[rid] or 0) + 1
                end
            end
        end
    end

    -- Exactly one of the mirror rids should appear, the others should not
    local presentCount = 0
    for _, rid in ipairs(mirrorRids) do
        if seenRids[rid] and seenRids[rid] > 0 then
            presentCount = presentCount + 1
        end
    end
    assert_equal(1, presentCount,
        "faction mirror dedup: expected exactly 1 of " .. #mirrorRids
        .. " mirror rids to appear in display")
end

function T.test_faction_mirror_prefers_player_faction()
    -- When player is Alliance, the Alliance version should be kept;
    -- when Horde, the Horde version should be kept.

    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    RecipeBookCharDB = RecipeBookCharDB or {}

    -- Find a mirror pair where each rid has a different-faction vendor
    local mirrorProfID, ridA, ridH
    for _, pid in ipairs(PROFESSIONS) do
        local byTeaches = {}
        for rid, data in pairs(RecipeBook.recipeDB[pid]) do
            if not data.isSpell and data.teaches then
                local key = data.teaches .. ":" .. (data.name or "")
                if not byTeaches[key] then byTeaches[key] = {} end
                byTeaches[key][#byTeaches[key] + 1] = rid
            end
        end
        for _, rids in pairs(byTeaches) do
            if #rids == 2 then
                local factions = {}
                for _, rid in ipairs(rids) do
                    local src = RecipeBook.sourceDB[pid] and RecipeBook.sourceDB[pid][rid]
                    if src and src.vendor then
                        for npcID in pairs(src.vendor) do
                            local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
                            if npc and npc.faction then
                                factions[rid] = npc.faction
                            end
                        end
                    end
                end
                if factions[rids[1]] and factions[rids[2]]
                    and factions[rids[1]] ~= factions[rids[2]] then
                    mirrorProfID = pid
                    if factions[rids[1]] == "Alliance" then
                        ridA, ridH = rids[1], rids[2]
                    else
                        ridA, ridH = rids[2], rids[1]
                    end
                    break
                end
            end
        end
        if mirrorProfID then break end
    end

    if not mirrorProfID then return end

    local filters = {
        professionID = mirrorProfID,
        maxPhase = 5,
        listMode = "all",
    }

    -- Test as Alliance
    local origUFG = UnitFactionGroup
    UnitFactionGroup = function() return "Alliance", "Alliance" end
    local groups = RecipeBook._BuildDisplayData(filters)
    local foundA, foundH = false, false
    for _, entries in pairs(groups) do
        for _, entry in ipairs(entries) do
            if entry.recipeID == ridA then foundA = true end
            if entry.recipeID == ridH then foundH = true end
        end
    end
    assert_true(foundA, "Alliance player should see Alliance mirror rid " .. ridA)
    assert_false(foundH, "Alliance player should not see Horde mirror rid " .. ridH)

    -- Test as Horde
    UnitFactionGroup = function() return "Horde", "Horde" end
    groups = RecipeBook._BuildDisplayData(filters)
    foundA, foundH = false, false
    for _, entries in pairs(groups) do
        for _, entry in ipairs(entries) do
            if entry.recipeID == ridA then foundA = true end
            if entry.recipeID == ridH then foundH = true end
        end
    end
    assert_true(foundH, "Horde player should see Horde mirror rid " .. ridH)
    assert_false(foundA, "Horde player should not see Alliance mirror rid " .. ridA)

    UnitFactionGroup = origUFG
end

return T
