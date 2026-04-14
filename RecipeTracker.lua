RecipeBook = RecipeBook or {}

-- Extract a numeric ID from a WoW hyperlink (item, enchant, or spell)
local function GetIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)")
        or link:match("enchant:(%d+)")
        or link:match("spell:(%d+)"))
end

-- Detect which profession ID is currently displayed
local function GetDisplayedProfessionID(event)
    -- CRAFT events = Enchanting; TRADE_SKILL events = everything else
    local isCraft = event and (event == "CRAFT_SHOW" or event == "CRAFT_UPDATE")
    local isTrade = event and (event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE")

    if isCraft then
        if GetNumCrafts and GetNumCrafts() > 0 then
            return 333, true
        end
        return nil, false
    end

    if isTrade then
        if GetNumTradeSkills and GetNumTradeSkills() > 0 then
            local skillName = GetTradeSkillLine and GetTradeSkillLine()
            if skillName then
                for _, prof in ipairs(RecipeBook.PROFESSIONS) do
                    if prof.name == skillName then
                        return prof.id, false
                    end
                end
            end
        end
        return nil, false
    end

    -- No event context: try both (legacy fallback)
    if GetNumCrafts and GetNumCrafts() > 0 then
        return 333, true
    end
    if GetNumTradeSkills and GetNumTradeSkills() > 0 then
        local skillName = GetTradeSkillLine and GetTradeSkillLine()
        if skillName then
            for _, prof in ipairs(RecipeBook.PROFESSIONS) do
                if prof.name == skillName then
                    return prof.id, false
                end
            end
        end
    end
    return nil, false
end

-- Reverse lookup: teaches value -> recipeID, built per profession on demand
local teachesLookups = {}

local function GetTeachesLookup(profID)
    if teachesLookups[profID] then return teachesLookups[profID] end
    local lookup = {}
    local recipes = RecipeBook.recipeDB[profID]
    if recipes then
        for recipeID, data in pairs(recipes) do
            if data.teaches and type(data.teaches) == "number" then
                if not lookup[data.teaches] then
                    lookup[data.teaches] = {}
                end
                lookup[data.teaches][#lookup[data.teaches] + 1] = recipeID
            end
        end
    end
    teachesLookups[profID] = lookup
    return lookup
end

-- Scan the currently open profession window and record known recipes
function RecipeBook:ScanProfessionWindow(event)
    local charData = self:GetMyCharData()
    if not charData then return end

    local profID, isEnchanting = GetDisplayedProfessionID(event)
    if not profID then return end

    -- Mark this profession as known on the global character entry
    charData.knownProfessions[profID] = true
    charData.lastScanned = time()

    -- Capture current skill level in both per-character and global DB
    if not RecipeBookCharDB.professionSkill then
        RecipeBookCharDB.professionSkill = {}
    end
    charData.professionSkill = charData.professionSkill or {}
    local currentSkill
    if isEnchanting then
        local _, skill = GetCraftDisplaySkillLine()
        currentSkill = skill
    else
        local _, skill = GetTradeSkillLine()
        currentSkill = skill
    end
    if currentSkill and currentSkill > 0 then
        RecipeBookCharDB.professionSkill[profID] = currentSkill
        charData.professionSkill[profID] = currentSkill
    end

    -- Ensure we have a recipe table for this profession
    if not self.recipeDB[profID] then return end
    if not charData.knownRecipes[profID] then
        charData.knownRecipes[profID] = {}
    end
    local known = charData.knownRecipes[profID]

    local numSkills = isEnchanting and GetNumCrafts() or GetNumTradeSkills()
    if numSkills == 0 then return end

    local teachesLookup = GetTeachesLookup(profID)

    -- Also build a name -> recipeID lookup for fallback matching
    local nameLookup = {}
    for recipeID, data in pairs(self.recipeDB[profID]) do
        local name = self:GetRecipeName(profID, recipeID)
        if name and name ~= "Loading..." and name ~= "Unknown Recipe" then
            nameLookup[strlower(name)] = recipeID
        end
    end

    for i = 1, numSkills do
        local itemID, spellID, matched

        if isEnchanting then
            local link = GetCraftItemLink(i)
            spellID = GetIDFromLink(link)
        else
            local itemLink = GetTradeSkillItemLink(i)
            itemID = GetIDFromLink(itemLink)

            if GetTradeSkillRecipeLink then
                local recipeLink = GetTradeSkillRecipeLink(i)
                spellID = GetIDFromLink(recipeLink)
            end
        end

        -- Strategy 1: crafted item ID is the recipeDB key
        if itemID and self.recipeDB[profID][itemID] then
            known[itemID] = true
            matched = true
        end
        -- Strategy 2: crafted item ID is a "teaches" value
        if itemID then
            local recipeIDs = teachesLookup[itemID]
            if recipeIDs then
                for _, rid in ipairs(recipeIDs) do
                    known[rid] = true
                end
                matched = true
            end
        end
        -- Strategy 3: recipe spell ID is the recipeDB key
        if spellID and self.recipeDB[profID][spellID] then
            known[spellID] = true
            matched = true
        end
        -- Strategy 4: recipe spell ID is a "teaches" value
        if spellID then
            local recipeIDs = teachesLookup[spellID]
            if recipeIDs then
                for _, rid in ipairs(recipeIDs) do
                    known[rid] = true
                end
                matched = true
            end
        end
        -- Strategy 5 (fallback): match by recipe name
        if not matched then
            local skillName
            if isEnchanting then
                skillName = GetCraftInfo(i)
            else
                skillName = GetTradeSkillInfo(i)
            end
            if skillName then
                local recipeID = nameLookup[strlower(skillName)]
                if recipeID then
                    known[recipeID] = true
                end
            end
        end
    end

    -- Infer skill-rank recipes as known (teaches is a string like "Expert", "Artisan", "Master")
    -- If the character knows any recipe with requiredSkill > this rank-up's requiredSkill,
    -- they must have already learned the rank-up.
    local maxKnownSkill = 0
    for recipeID in pairs(known) do
        local data = self.recipeDB[profID][recipeID]
        if data and data.requiredSkill and data.requiredSkill > maxKnownSkill then
            maxKnownSkill = data.requiredSkill
        end
    end
    if maxKnownSkill > 0 then
        for recipeID, data in pairs(self.recipeDB[profID]) do
            if data.teaches and type(data.teaches) == "string" then
                -- String teaches = rank-up (Expert, Artisan, Master, etc.)
                if data.requiredSkill and data.requiredSkill <= maxKnownSkill then
                    known[recipeID] = true
                end
            end
        end
    end

    -- Notify guild subsystems that our recipe list for this profession
    -- may have changed. Cheap when sharing is disabled; debounces its
    -- own HELLO broadcast when enabled.
    if self.OnMyRecipesChanged then
        self:OnMyRecipesChanged(profID)
    end

    -- Switch to the scanned profession and refresh UI
    if self.SelectProfession then
        self:SelectProfession(profID)
    elseif self.mainFrame and self.mainFrame:IsShown() then
        self:RefreshRecipeList()
    end
end

function RecipeBook:ClearTeachesCache()
    wipe(teachesLookups)
end

function RecipeBook:IsRecipeKnown(profID, recipeID, charKey)
    charKey = charKey or self:GetViewedCharKey()
    if not charKey or not RecipeBookDB.characters then return false end
    local entry = RecipeBookDB.characters[charKey]
    if not entry or not entry.knownRecipes then return false end
    local profRecipes = entry.knownRecipes[profID]
    if not profRecipes then return false end
    return profRecipes[recipeID] == true
end

-- Check whether the player meets all requirements to learn a recipe:
--   1. Profession is known
--   2. Recipe is not already known
--   3. Profession skill >= requiredSkill
--   4. Reputation standing >= reputationLevel (if required)
function RecipeBook:IsRecipeLearnable(profID, recipeID)
    if not self:IsProfessionKnown(profID) then return false end
    if self:IsRecipeKnown(profID, recipeID) then return false end

    local data = self.recipeDB[profID] and self.recipeDB[profID][recipeID]
    if not data then return false end

    -- Skill check
    local playerSkill = RecipeBook:GetProfessionSkill(profID)
    if not playerSkill then return false end
    if data.requiredSkill and playerSkill < data.requiredSkill then return false end

    -- Reputation check
    if data.reputationFaction and data.reputationLevel then
        if not GetFactionInfoByID then return false end
        local _, _, standingID = GetFactionInfoByID(data.reputationFaction)
        if not standingID or standingID < data.reputationLevel then return false end
    end

    return true
end

function RecipeBook:RegisterTrackingEvents(eventFrame)
    eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
    eventFrame:RegisterEvent("CRAFT_SHOW")
    eventFrame:RegisterEvent("CRAFT_UPDATE")
end

function RecipeBook:OnTrackingEvent(event)
    -- Short delay to ensure API data is ready (RecipeMaster uses 0.05s)
    C_Timer.After(0.1, function()
        RecipeBook:ScanProfessionWindow(event)
    end)
end
