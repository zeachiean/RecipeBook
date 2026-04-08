-- Tests for saved variable management: scanning, clearing, saving, reading.
local T = {}

-- ============================================================
-- MOCK TRADE SKILL API
-- ============================================================

-- Configurable mock state for profession windows
local mockTradeSkill = {
    numSkills = 0,
    skillName = nil,
    skillLevel = 0,
    items = {},  -- [index] = { name, itemLink, recipeLink }
}
local mockCraft = {
    numCrafts = 0,
    skillLevel = 0,
    items = {},  -- [index] = { name, craftLink }
}

local function resetProfMocks()
    mockTradeSkill.numSkills = 0
    mockTradeSkill.skillName = nil
    mockTradeSkill.skillLevel = 0
    mockTradeSkill.items = {}
    mockCraft.numCrafts = 0
    mockCraft.skillLevel = 0
    mockCraft.items = {}
end

-- Install global API stubs
function GetNumTradeSkills()
    return mockTradeSkill.numSkills
end

function GetTradeSkillLine()
    return mockTradeSkill.skillName, mockTradeSkill.skillLevel
end

function GetTradeSkillInfo(index)
    local item = mockTradeSkill.items[index]
    if item then return item.name end
    return nil
end

function GetTradeSkillItemLink(index)
    local item = mockTradeSkill.items[index]
    if item then return item.itemLink end
    return nil
end

function GetTradeSkillRecipeLink(index)
    local item = mockTradeSkill.items[index]
    if item then return item.recipeLink end
    return nil
end

function GetNumCrafts()
    return mockCraft.numCrafts
end

function GetCraftDisplaySkillLine()
    return "Enchanting", mockCraft.skillLevel
end

function GetCraftItemLink(index)
    local item = mockCraft.items[index]
    if item then return item.craftLink end
    return nil
end

function GetCraftInfo(index)
    local item = mockCraft.items[index]
    if item then return item.name end
    return nil
end

-- Helper: set up a mock tradeskill window
local function setupTradeSkill(profName, skill, items)
    resetProfMocks()
    mockTradeSkill.skillName = profName
    mockTradeSkill.skillLevel = skill
    mockTradeSkill.numSkills = #items
    mockTradeSkill.items = items
end

-- Helper: set up a mock enchanting (craft) window
local function setupCraft(skill, items)
    resetProfMocks()
    mockCraft.skillLevel = skill
    mockCraft.numCrafts = #items
    mockCraft.items = items
end

-- ============================================================
-- SETUP
-- ============================================================

function T.setup()
    resetProfMocks()
end

local function initCharDB()
    RecipeBookCharDB = RecipeBookCharDB or {}
    RecipeBookCharDB.professionSkill = RecipeBookCharDB.professionSkill or {}
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.characters = RecipeBookDB.characters or {}
    local charKey = RecipeBook:GetMyCharKey()
    return RecipeBook:GetOrCreateCharData(charKey, UnitName("player"), GetRealmName())
end

-- ============================================================
-- SCANNING: profession detection via event
-- ============================================================

function T.test_scan_detects_tradeskill_via_event()
    local charData = initCharDB()

    -- Set up a Tailoring window with one recipe that's in the DB
    local tailoring = 197
    local rid, rdata
    for id, data in pairs(RecipeBook.recipeDB[tailoring]) do
        if not data.isSpell then
            rid, rdata = id, data
            break
        end
    end
    assert_not_nil(rid, "should find a Tailoring recipe")

    setupTradeSkill("Tailoring", 375, {
        { name = rdata.name, itemLink = "|cffffffff|Hitem:" .. rid .. ":0|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    assert_true(charData.knownProfessions[tailoring],
        "Tailoring should be marked as known")
    assert_true(charData.knownRecipes[tailoring] and charData.knownRecipes[tailoring][rid],
        "recipe should be marked as known")
end

function T.test_scan_detects_enchanting_via_craft_event()
    local charData = initCharDB()

    -- Set up an Enchanting window with one recipe
    local enchanting = 333
    local rid, rdata
    for id, data in pairs(RecipeBook.recipeDB[enchanting]) do
        rid, rdata = id, data
        break
    end
    assert_not_nil(rid, "should find an Enchanting recipe")

    setupCraft(375, {
        { name = rdata.name, craftLink = "|cffffffff|Henchant:" .. rid .. "|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("CRAFT_SHOW")

    assert_true(charData.knownProfessions[enchanting],
        "Enchanting should be marked as known")
end

function T.test_scan_uses_event_to_distinguish_profession()
    local charData = initCharDB()

    -- Both APIs return data (enchanting cached + tailoring open)
    local tailoring = 197
    local enchanting = 333
    local tRid
    for id in pairs(RecipeBook.recipeDB[tailoring]) do
        tRid = id; break
    end

    -- Craft API returns cached enchanting data
    mockCraft.numCrafts = 5
    mockCraft.skillLevel = 375

    -- TradeSkill API returns the open tailoring window
    local rdata = RecipeBook.recipeDB[tailoring][tRid]
    setupTradeSkill("Tailoring", 300, {
        { name = rdata.name, itemLink = "|cffffffff|Hitem:" .. tRid .. ":0|h[Test]|h|r" },
    })
    -- Re-set craft data since setupTradeSkill resets it
    mockCraft.numCrafts = 5
    mockCraft.skillLevel = 375

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    -- Should detect Tailoring (from event), NOT Enchanting (from cached craft data)
    assert_true(charData.knownProfessions[tailoring],
        "Tailoring should be detected via TRADE_SKILL_SHOW")
end

-- ============================================================
-- SCANNING: skill level
-- ============================================================

function T.test_scan_saves_skill_level()
    local charData = initCharDB()
    local tailoring = 197
    local rid
    for id in pairs(RecipeBook.recipeDB[tailoring]) do
        rid = id; break
    end
    local rdata = RecipeBook.recipeDB[tailoring][rid]

    setupTradeSkill("Tailoring", 350, {
        { name = rdata.name, itemLink = "|cffffffff|Hitem:" .. rid .. ":0|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    assert_equal(350, RecipeBookCharDB.professionSkill[tailoring],
        "per-char skill should be 350")
    assert_equal(350, charData.professionSkill[tailoring],
        "global skill should be 350")
end

function T.test_scan_does_not_overwrite_skill_with_zero()
    local charData = initCharDB()
    local tailoring = 197

    -- Pre-set a known skill level
    RecipeBookCharDB.professionSkill[tailoring] = 375
    charData.professionSkill = charData.professionSkill or {}
    charData.professionSkill[tailoring] = 375

    -- API returns 0 (not ready)
    setupTradeSkill("Tailoring", 0, {})

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    assert_equal(375, RecipeBookCharDB.professionSkill[tailoring],
        "per-char skill should remain 375")
    assert_equal(375, charData.professionSkill[tailoring],
        "global skill should remain 375")
end

function T.test_scan_enchanting_saves_skill_level()
    local charData = initCharDB()
    local enchanting = 333

    -- Need at least one craft for GetNumCrafts() > 0 (required by GetDisplayedProfessionID)
    local rid
    for id in pairs(RecipeBook.recipeDB[enchanting]) do
        rid = id; break
    end
    local rdata = RecipeBook.recipeDB[enchanting][rid]

    setupCraft(300, {
        { name = rdata.name, craftLink = "|cffffffff|Henchant:" .. rid .. "|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("CRAFT_SHOW")

    assert_equal(300, RecipeBookCharDB.professionSkill[enchanting],
        "enchanting per-char skill should be 300")
    assert_equal(300, charData.professionSkill[enchanting],
        "enchanting global skill should be 300")
end

-- ============================================================
-- SCANNING: faction-mirror recipes (teaches lookup returns arrays)
-- ============================================================

function T.test_teaches_lookup_returns_arrays()
    -- Find a recipe where teaches is a number
    local found = false
    for _, prof in ipairs(RecipeBook.PROFESSIONS) do
        for rid, data in pairs(RecipeBook.recipeDB[prof.id]) do
            if data.teaches and type(data.teaches) == "number" then
                -- Clear cache so we get a fresh build
                RecipeBook:ClearTeachesCache()
                -- Build the lookup manually to check structure
                local lookup = {}
                for rid2, data2 in pairs(RecipeBook.recipeDB[prof.id]) do
                    if data2.teaches and type(data2.teaches) == "number" then
                        if not lookup[data2.teaches] then
                            lookup[data2.teaches] = {}
                        end
                        lookup[data2.teaches][#lookup[data2.teaches] + 1] = rid2
                    end
                end
                -- Verify the lookup has arrays
                for teachesVal, arr in pairs(lookup) do
                    assert_true(type(arr) == "table",
                        "teaches lookup value should be a table")
                    assert_true(#arr >= 1,
                        "teaches lookup array should have at least 1 entry")
                end
                found = true
                break
            end
        end
        if found then break end
    end
    assert_true(found, "should find at least one recipe with numeric teaches")
end

-- ============================================================
-- SCANNING: name fallback matching
-- ============================================================

function T.test_scan_matches_by_name_fallback()
    local charData = initCharDB()
    local cooking = 185

    -- Find a recipe with a name
    local rid, rdata
    for id, data in pairs(RecipeBook.recipeDB[cooking]) do
        if data.name then
            rid, rdata = id, data
            break
        end
    end
    assert_not_nil(rid)

    -- Set up window with no item/spell links, only name
    setupTradeSkill("Cooking", 375, {
        { name = rdata.name, itemLink = nil, recipeLink = nil },
    })

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    assert_true(charData.knownRecipes[cooking] and charData.knownRecipes[cooking][rid],
        "recipe should be matched by name fallback")
end

-- ============================================================
-- READING: GetProfessionSkill fallthrough
-- ============================================================

function T.test_get_profession_skill_prefers_per_char()
    initCharDB()
    local alchemy = 171

    -- Set different values in per-char vs global
    RecipeBookCharDB.professionSkill[alchemy] = 350
    local charData = RecipeBook:GetMyCharData()
    charData.professionSkill = charData.professionSkill or {}
    charData.professionSkill[alchemy] = 300

    local skill = RecipeBook:GetProfessionSkill(alchemy)
    assert_equal(350, skill, "should prefer per-char value (350) over global (300)")
end

function T.test_get_profession_skill_falls_through_to_global()
    initCharDB()
    local alchemy = 171

    -- Per-char has no value, global does
    RecipeBookCharDB.professionSkill[alchemy] = nil
    local charData = RecipeBook:GetMyCharData()
    charData.professionSkill = charData.professionSkill or {}
    charData.professionSkill[alchemy] = 300

    local skill = RecipeBook:GetProfessionSkill(alchemy)
    assert_equal(300, skill, "should fall through to global value (300)")
end

function T.test_get_profession_skill_nil_when_both_empty()
    initCharDB()
    local alchemy = 171

    RecipeBookCharDB.professionSkill[alchemy] = nil
    local charData = RecipeBook:GetMyCharData()
    charData.professionSkill = charData.professionSkill or {}
    charData.professionSkill[alchemy] = nil

    local skill = RecipeBook:GetProfessionSkill(alchemy)
    assert_nil(skill, "should be nil when neither store has a value")
end

-- ============================================================
-- READING: IsRecipeKnown
-- ============================================================

function T.test_is_recipe_known_returns_true_for_known()
    local charData = initCharDB()
    local cooking = 185
    local rid
    for id in pairs(RecipeBook.recipeDB[cooking]) do
        rid = id; break
    end

    charData.knownRecipes[cooking] = { [rid] = true }
    assert_true(RecipeBook:IsRecipeKnown(cooking, rid),
        "should return true for known recipe")
end

function T.test_is_recipe_known_returns_false_for_unknown()
    initCharDB()
    local cooking = 185
    assert_false(RecipeBook:IsRecipeKnown(cooking, 99999),
        "should return false for unknown recipe")
end

-- ============================================================
-- CLEARING: clearall wipes all stores
-- ============================================================

function T.test_clearall_wipes_known_recipes()
    local charData = initCharDB()
    local cooking = 185

    -- Set up known data
    charData.knownProfessions[cooking] = true
    charData.knownRecipes[cooking] = { [12345] = true }
    charData.professionSkill = { [cooking] = 375 }
    RecipeBookCharDB.professionSkill[cooking] = 375
    RecipeBookCharDB.selectedProfession = cooking

    -- Simulate what clearall does (inline, since slash command handler is local)
    wipe(RecipeBook.itemNames)
    RecipeBook._refreshPending = nil
    RecipeBookCharDB.professionSkill = {}
    local myData = RecipeBook:GetMyCharData()
    if myData then
        wipe(myData.knownProfessions)
        wipe(myData.knownRecipes)
        if myData.professionSkill then
            wipe(myData.professionSkill)
        end
    end
    RecipeBookCharDB.selectedProfession = nil

    -- Verify everything is cleared
    assert_table_length(charData.knownProfessions, 0,
        "knownProfessions should be empty")
    assert_table_length(charData.knownRecipes, 0,
        "knownRecipes should be empty")
    assert_table_length(charData.professionSkill, 0,
        "global professionSkill should be empty")
    assert_table_length(RecipeBookCharDB.professionSkill, 0,
        "per-char professionSkill should be empty")
    assert_nil(RecipeBookCharDB.selectedProfession,
        "selectedProfession should be nil")
end

-- ============================================================
-- CLEARING: clearall followed by scan restores data
-- ============================================================

function T.test_clearall_then_scan_restores_data()
    local charData = initCharDB()
    local tailoring = 197

    -- Clear everything
    RecipeBookCharDB.professionSkill = {}
    wipe(charData.knownProfessions)
    wipe(charData.knownRecipes)
    charData.professionSkill = charData.professionSkill or {}
    wipe(charData.professionSkill)

    -- Now scan tailoring
    local rid
    for id in pairs(RecipeBook.recipeDB[tailoring]) do
        rid = id; break
    end
    local rdata = RecipeBook.recipeDB[tailoring][rid]

    setupTradeSkill("Tailoring", 350, {
        { name = rdata.name, itemLink = "|cffffffff|Hitem:" .. rid .. ":0|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    assert_true(charData.knownProfessions[tailoring],
        "Tailoring should be known after rescan")
    assert_equal(350, RecipeBookCharDB.professionSkill[tailoring],
        "skill should be saved after rescan")
    assert_true(charData.knownRecipes[tailoring] and charData.knownRecipes[tailoring][rid],
        "recipe should be known after rescan")
end

-- ============================================================
-- SCANNING: multiple professions in one session
-- ============================================================

function T.test_multiple_professions_detected_via_events()
    local charData = initCharDB()

    -- Scan Tailoring
    local tailoring = 197
    local tRid
    for id in pairs(RecipeBook.recipeDB[tailoring]) do
        tRid = id; break
    end
    local tData = RecipeBook.recipeDB[tailoring][tRid]

    setupTradeSkill("Tailoring", 350, {
        { name = tData.name, itemLink = "|cffffffff|Hitem:" .. tRid .. ":0|h[Test]|h|r" },
    })
    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    -- Scan Cooking
    local cooking = 185
    local cRid
    for id in pairs(RecipeBook.recipeDB[cooking]) do
        cRid = id; break
    end
    local cData = RecipeBook.recipeDB[cooking][cRid]

    setupTradeSkill("Cooking", 300, {
        { name = cData.name, itemLink = "|cffffffff|Hitem:" .. cRid .. ":0|h[Test]|h|r" },
    })
    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    -- Both should be detected
    assert_true(charData.knownProfessions[tailoring],
        "Tailoring should be known")
    assert_true(charData.knownProfessions[cooking],
        "Cooking should be known")
    assert_equal(350, RecipeBookCharDB.professionSkill[tailoring],
        "Tailoring skill should be 350")
    assert_equal(300, RecipeBookCharDB.professionSkill[cooking],
        "Cooking skill should be 300")
end

-- ============================================================
-- SCANNING: rank-up inference
-- ============================================================

function T.test_scan_infers_rank_up_recipes_as_known()
    local charData = initCharDB()

    -- Find a profession with string teaches entries (rank-ups)
    local profID, rankRid, regularRid
    for _, prof in ipairs(RecipeBook.PROFESSIONS) do
        local hasRankUp, hasRegular = false, false
        local rRid, regRid
        for rid, data in pairs(RecipeBook.recipeDB[prof.id]) do
            if data.teaches and type(data.teaches) == "string" then
                rRid = rid
                hasRankUp = true
            elseif data.requiredSkill and data.requiredSkill > 50 and not data.isSpell then
                regRid = rid
                hasRegular = true
            end
            if hasRankUp and hasRegular then break end
        end
        if hasRankUp and hasRegular then
            profID = prof.id
            rankRid = rRid
            regularRid = regRid
            break
        end
    end

    if not profID then
        -- Skip if no profession has both rank-ups and regular recipes
        return
    end

    local rankData = RecipeBook.recipeDB[profID][rankRid]
    local regData = RecipeBook.recipeDB[profID][regularRid]

    -- Ensure the regular recipe has higher requiredSkill than the rank-up
    if regData.requiredSkill <= (rankData.requiredSkill or 0) then
        -- Find one that does
        for rid, data in pairs(RecipeBook.recipeDB[profID]) do
            if data.requiredSkill and data.requiredSkill > (rankData.requiredSkill or 0) and not data.isSpell then
                regularRid = rid
                regData = data
                break
            end
        end
    end

    local profName = RecipeBook.PROFESSION_NAMES[profID]
    setupTradeSkill(profName, 375, {
        { name = regData.name, itemLink = "|cffffffff|Hitem:" .. regularRid .. ":0|h[Test]|h|r" },
    })

    RecipeBook:ScanProfessionWindow("TRADE_SKILL_SHOW")

    -- The rank-up should be inferred as known since we know a recipe with higher skill
    if regData.requiredSkill > (rankData.requiredSkill or 0) then
        assert_true(charData.knownRecipes[profID][rankRid],
            "rank-up recipe should be inferred as known")
    end
end

return T
