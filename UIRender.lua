RecipeBook = RecipeBook or {}

local UI = RecipeBook.UI

-- Currently displayed rows
local displayedRows = {}

-- Recipe quality cache: recipeID -> quality number
local recipeQualityCache = {}

-- Get item quality color for a recipe's crafted product
local function GetRecipeQualityColor(profID, recipeID)
    local cached = recipeQualityCache[recipeID]
    if cached then
        return UI.QUALITY_COLORS[cached] or UI.QUALITY_COLORS[1]
    end

    local data = RecipeBook.recipeDB[profID] and RecipeBook.recipeDB[profID][recipeID]
    if not data then return UI.QUALITY_COLORS[1] end

    if data.isSpell then
        -- Spells don't have item quality; use white
        recipeQualityCache[recipeID] = 1
        return UI.QUALITY_COLORS[1]
    end

    -- The recipeID is the crafted item ID; get its quality
    local _, _, quality = C_Item.GetItemInfo(recipeID)
    if quality then
        recipeQualityCache[recipeID] = quality
        return UI.QUALITY_COLORS[quality] or UI.QUALITY_COLORS[1]
    end

    return UI.QUALITY_COLORS[1]
end

-- Shared tooltip handler
local function OnRecipeEnter(self)
    if not self._recipeID or not self._profID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    local data = RecipeBook.recipeDB[self._profID] and RecipeBook.recipeDB[self._profID][self._recipeID]
    if not data then
        GameTooltip:AddLine("Unknown Recipe", 1, 0, 0)
        GameTooltip:Show()
        return
    end

    if not data.isSpell then
        -- Recipe item: show the item tooltip directly
        GameTooltip:SetItemByID(self._recipeID)
    else
        -- isSpell: try spell hyperlink (shows crafting tooltip with reagents)
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. self._recipeID)
        if not ok then
            GameTooltip:AddLine(data.name or "Unknown Recipe", 1, 1, 1)
        end
    end

    GameTooltip:AddLine(" ")
    if self._sourceType then
        local srcLabel = RecipeBook.SOURCE_LABELS[self._sourceType] or self._sourceType
        GameTooltip:AddLine("Source: " .. srcLabel, UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

        if self._sourceType == "discovery" then
            GameTooltip:AddLine("Learned via crafting", 1, 1, 1)

        elseif self._sourceType == "worldDrop" then
            GameTooltip:AddLine("Drops from world mobs", UI.COLOR_WORLDDROP.r, UI.COLOR_WORLDDROP.g, UI.COLOR_WORLDDROP.b)
            local wdData = RecipeBook.sourceDB[self._profID]
                and RecipeBook.sourceDB[self._profID][self._recipeID]
                and RecipeBook.sourceDB[self._profID][self._recipeID].worldDrop
            if type(wdData) == "table" and #wdData > 0 then
                local zoneSet = {}
                for _, areaID in ipairs(wdData) do
                    local zn = RecipeBook:GetZoneNameForAreaID(areaID)
                    if zn then zoneSet[zn] = true end
                end
                local zones = {}
                for z in pairs(zoneSet) do zones[#zones + 1] = z end
                table.sort(zones)
                local max = 6
                for i = 1, math.min(max, #zones) do
                    GameTooltip:AddLine("  " .. zones[i], 0.8, 0.8, 0.8)
                end
                if #zones > max then
                    GameTooltip:AddLine(("  ...and %d more"):format(#zones - max), 0.6, 0.6, 0.6)
                end
            end

        elseif self._sourceType == "trainer" and not self._sourceID then
            GameTooltip:AddLine("Learned from a profession trainer", 1, 1, 1)

        elseif self._sourceType == "trainer" then
            local npcName = RecipeBook:GetNPCName(self._sourceID)
            local zone = RecipeBook:GetFirstZoneForNPC(self._sourceID)
            GameTooltip:AddLine(npcName .. (zone and (" - " .. zone) or ""), 1, 1, 1)

        elseif self._sourceType == "vendor" then
            local npcName = RecipeBook:GetNPCName(self._sourceID)
            local zone = RecipeBook:GetFirstZoneForNPC(self._sourceID)
            GameTooltip:AddLine(npcName .. (zone and (" - " .. zone) or ""), 1, 1, 1)
            local srcData = RecipeBook.sourceDB[self._profID]
                and RecipeBook.sourceDB[self._profID][self._recipeID]
                and RecipeBook.sourceDB[self._profID][self._recipeID].vendor
                and RecipeBook.sourceDB[self._profID][self._recipeID].vendor[self._sourceID]
            if srcData and type(srcData) == "table" then
                if srcData.cost then
                    local cost = srcData.cost:gsub("gld", "g "):gsub("svr", "s "):gsub("cpr", "c")
                    GameTooltip:AddLine("Cost: " .. cost, 1, 1, 1)
                end
                if srcData.stock then
                    GameTooltip:AddLine("Stock: " .. srcData.stock, 1, 1, 1)
                end
            end

        elseif self._sourceType == "drop" or self._sourceType == "pickpocket" then
            if self._isWorldDrop then
                GameTooltip:AddLine("World Drop", UI.COLOR_WORLDDROP.r, UI.COLOR_WORLDDROP.g, UI.COLOR_WORLDDROP.b)
            else
                local npcName = RecipeBook:GetNPCName(self._sourceID)
                local zone = RecipeBook:GetFirstZoneForNPC(self._sourceID)
                local dropRate = RecipeBook.sourceDB[self._profID]
                    and RecipeBook.sourceDB[self._profID][self._recipeID]
                    and RecipeBook.sourceDB[self._profID][self._recipeID][self._sourceType]
                    and RecipeBook.sourceDB[self._profID][self._recipeID][self._sourceType][self._sourceID]
                GameTooltip:AddLine(npcName .. (zone and (" - " .. zone) or ""), 1, 1, 1)
                if dropRate and type(dropRate) == "number" then
                    GameTooltip:AddLine(string.format("Drop Rate: %.1f%%", dropRate), 0.7, 0.7, 0.7)
                end
            end

        elseif self._sourceType == "quest" then
            local questData = RecipeBook.questDB and RecipeBook.questDB[self._sourceID]
            local title = questData and questData.name or ("Quest #" .. self._sourceID)
            GameTooltip:AddLine(title, 1, 1, 1)
            if questData then
                if questData.startNPC then
                    local npcName = RecipeBook:GetNPCName(questData.startNPC)
                    local zone = RecipeBook:GetFirstZoneForNPC(questData.startNPC)
                    if npcName then
                        GameTooltip:AddLine("From: " .. npcName .. (zone and (" - " .. zone) or ""), 0.9, 0.9, 0.9)
                    end
                end
                if questData.faction then
                    GameTooltip:AddLine("Faction: " .. questData.faction, 0.7, 0.7, 0.7)
                end
                if questData.level then
                    GameTooltip:AddLine("Level: " .. questData.level, 0.7, 0.7, 0.7)
                end
            end

        elseif self._sourceType == "object" then
            local objName = RecipeBook:GetObjectName(self._sourceID)
            local zone = RecipeBook:GetFirstZoneForObject(self._sourceID)
            GameTooltip:AddLine(objName .. (zone and (" - " .. zone) or ""), 1, 1, 1)

        elseif self._sourceType == "unique" then
            local uName = RecipeBook:GetUniqueName(self._sourceID)
            local zone = RecipeBook:GetFirstZoneForUnique(self._sourceID)
            GameTooltip:AddLine(uName .. (zone and (" - " .. zone) or ""), 1, 1, 1)

        elseif self._sourceType == "fishing" then
            local zone = RecipeBook:GetZoneNameForAreaID(self._sourceID)
            if zone then GameTooltip:AddLine(zone, 1, 1, 1) end

        elseif self._sourceType == "item" then
            local itemName = RecipeBook.itemNames[self._sourceID] or ("Item #" .. self._sourceID)
            GameTooltip:AddLine(itemName, 1, 1, 1)
        end
    end

    -- Waypoint hint
    if self._canWaypoint then
        GameTooltip:AddLine(" ")
        local wp = RecipeBook.activeWaypoint
        if wp and wp.npcName == self._npcName and wp.zoneName == self._zoneName then
            GameTooltip:AddLine("Click to clear waypoint", 1, 0.3, 0.3)
        else
            GameTooltip:AddLine("Click to set waypoint", UI.COLOR_WAYPOINT.r, UI.COLOR_WAYPOINT.g, UI.COLOR_WAYPOINT.b)
        end
    end

    -- Interaction hints
    if RecipeBook:RecipeHasAnySources(self._profID, self._recipeID) then
        GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine("Shift-click to link in chat", 0.5, 0.5, 0.5)

    -- Known status
    if RecipeBook:IsRecipeKnown(self._profID, self._recipeID) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Already known", 0, 1, 0)
    end

    GameTooltip:Show()
end

local function OnRecipeLeave(self)
    GameTooltip:Hide()
end

-- Hidden anchor for row context menus (wishlist / ignore)
local contextMenuFrame = CreateFrame("Frame", "RecipeBookContextMenu", UIParent, "UIDropDownMenuTemplate")
local contextMenuList = nil

local function ContextMenu_Init(self, level)
    if not contextMenuList then return end
    for _, entry in ipairs(contextMenuList) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = entry.text
        info.isTitle = entry.isTitle
        info.notCheckable = true
        info.disabled = entry.disabled
        info.func = entry.func
        UIDropDownMenu_AddButton(info, level)
    end
end
UIDropDownMenu_Initialize(contextMenuFrame, ContextMenu_Init, "MENU")

local function ShowRecipeContextMenu(row)
    if not row._recipeID or not row._profID then return end
    local profID, recipeID = row._profID, row._recipeID
    local inWish = RecipeBook:IsRecipeInWishlist(profID, recipeID)
    local isIgn  = RecipeBook:IsRecipeIgnored(profID, recipeID)
    local name = RecipeBook:GetRecipeName(profID, recipeID) or "Recipe"
    local viewedName = (RecipeBookDB.characters[RecipeBook:GetViewedCharKey()] or {}).name or "character"
    contextMenuList = {
        { text = name, isTitle = true },
        {
            text = inWish and ("Remove from " .. viewedName .. "'s Wishlist")
                        or ("Add to " .. viewedName .. "'s Wishlist"),
            func = function()
                RecipeBook:ToggleRecipeWishlist(profID, recipeID)
                RecipeBook:RefreshRecipeList()
            end,
        },
        {
            text = isIgn and ("Stop ignoring for " .. viewedName)
                      or ("Ignore for " .. viewedName),
            func = function()
                RecipeBook:ToggleRecipeIgnored(profID, recipeID)
                RecipeBook:RefreshRecipeList()
            end,
        },
        {
            text = "Show All Sources",
            func = function()
                RecipeBook:ShowSourcesPopup(profID, recipeID)
            end,
        },
        { text = "Cancel", func = function() end },
    }
    ToggleDropDownMenu(1, nil, contextMenuFrame, "cursor", 0, 0)
end

local function OnRecipeClick(self, button)
    if button == "RightButton" then
        ShowRecipeContextMenu(self)
        return
    end

    -- Shift-click: link recipe into chat
    if IsShiftKeyDown() and self._recipeID then
        local data = RecipeBook.recipeDB[self._profID] and RecipeBook.recipeDB[self._profID][self._recipeID]
        if data and not data.isSpell then
            local _, link = C_Item.GetItemInfo(self._recipeID)
            if link then
                ChatEdit_InsertLink(link)
                return
            end
        end
        return
    end

    -- Normal click: toggle waypoint
    if not self._canWaypoint then return end

    local wp = RecipeBook.activeWaypoint
    if wp and wp.npcName == self._npcName and wp.zoneName == self._zoneName then
        -- Clear waypoint
        if AddressBook and AddressBook.ClearWaypoint then
            AddressBook:ClearWaypoint()
        end
        if AddressBook and AddressBook.ClearAllWaypoints then
            AddressBook:ClearAllWaypoints()
        end
        RecipeBook.activeWaypoint = nil
    else
        -- Set waypoint
        if self._isTrainerWP then
            -- Search AB for nearest profession trainer
            AddressBook.API:Lookup(self._npcName, {
                category = "Trainers",
                action = "nearest",
            })
        else
            AddressBook.API:WaypointTo(self._npcName, self._zoneName)
        end
        RecipeBook.activeWaypoint = { npcName = self._npcName, zoneName = self._zoneName }
    end

    -- Refresh to update arrow states
    RecipeBook:RefreshRecipeList()
end

-- Header click: toggle collapse
local function OnHeaderClick(self)
    if not self._headerSrcType then return end
    local key = self._headerSrcType
    if RecipeBookCharDB.collapsedSources[key] then
        RecipeBookCharDB.collapsedSources[key] = nil
    else
        RecipeBookCharDB.collapsedSources[key] = true
    end
    RecipeBook:RefreshRecipeList()
end

-- Check if a source entity is in the filtered zone/continent
local function SourcePassesZoneFilter(sourceType, sourceID, filterZone, filterContinent)
    if not filterZone and not filterContinent then return true end

    local zones = nil

    if sourceType == "trainer" or sourceType == "vendor" or sourceType == "drop" or sourceType == "pickpocket" then
        local npc = RecipeBook.npcDB and RecipeBook.npcDB[sourceID]
        if npc then zones = npc.zones end
    elseif sourceType == "object" then
        local obj = RecipeBook.objectDB and RecipeBook.objectDB[sourceID]
        if obj then zones = obj.zones end
    elseif sourceType == "unique" then
        local entry = RecipeBook.uniqueDB and RecipeBook.uniqueDB[sourceID]
        if entry then zones = entry.zones end
    elseif sourceType == "fishing" or sourceType == "worldDrop" then
        -- Both key on area IDs directly.
        local zoneName = RecipeBook:GetZoneNameForAreaID(sourceID)
        if not zoneName then return false end
        if filterZone and zoneName ~= filterZone then return false end
        if filterContinent then
            local cont = RecipeBook:GetContinentForZone(zoneName)
            if cont ~= filterContinent then return false end
        end
        return true
    elseif sourceType == "quest" then
        -- Resolve quest to its start NPC's zones (from Questie data).
        local quest = RecipeBook.questDB and RecipeBook.questDB[sourceID]
        if quest and quest.startNPC then
            local npc = RecipeBook.npcDB and RecipeBook.npcDB[quest.startNPC]
            if npc then zones = npc.zones end
        end
    elseif sourceType == "item" then
        -- No zone info for items: can't prove a filter match.
        return false
    end

    -- No zone data on the entity: can't prove it matches, so reject.
    if not zones then return false end

    for _, areaID in ipairs(zones) do
        local zoneName = RecipeBook:GetZoneNameForAreaID(areaID)
        if zoneName then
            if filterZone and zoneName == filterZone then return true end
            if filterContinent and not filterZone then
                local cont = RecipeBook:GetContinentForZone(zoneName)
                if cont == filterContinent then return true end
            end
        end
    end

    return false
end

local function RecipePassesZoneFilter(profID, recipeID, filterZone, filterContinent)
    if not filterZone and not filterContinent then return true end

    local sources = RecipeBook.sourceDB[profID] and RecipeBook.sourceDB[profID][recipeID]
    if not sources then return true end

    for srcType, srcData in pairs(sources) do
        if type(srcData) == "table" then
            if srcType == "unique" then
                for _, uid in ipairs(srcData) do
                    if SourcePassesZoneFilter("unique", uid, filterZone, filterContinent) then
                        return true
                    end
                end
            elseif srcType == "worldDrop" then
                -- Array of areaIDs (may be empty if scrape found nothing).
                for _, areaID in ipairs(srcData) do
                    if SourcePassesZoneFilter("worldDrop", areaID, filterZone, filterContinent) then
                        return true
                    end
                end
            else
                for srcID in pairs(srcData) do
                    if SourcePassesZoneFilter(srcType, srcID, filterZone, filterContinent) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Count the total number of distinct source entities for a recipe,
-- excluding opposite-faction trainers/vendors/quests when filtered.
local function GetSourceCount(profID, recipeID, factionFilter)
    local sources = RecipeBook.sourceDB and RecipeBook.sourceDB[profID]
        and RecipeBook.sourceDB[profID][recipeID]
    if not sources then return 0 end
    local playerFaction = factionFilter
    local n = 0
    for srcType, srcData in pairs(sources) do
        if type(srcData) == "table" then
            if srcType == "unique" then
                for _ in ipairs(srcData) do n = n + 1 end
            elseif srcType == "worldDrop" then
                n = n + 1
            elseif srcType == "trainer" or srcType == "vendor" then
                for npcID in pairs(srcData) do
                    local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
                    if not playerFaction or not npc or not npc.faction
                        or npc.faction == playerFaction then
                        n = n + 1
                    end
                end
            elseif srcType == "quest" then
                for questID in pairs(srcData) do
                    local q = RecipeBook.questDB and RecipeBook.questDB[questID]
                    if not playerFaction or not q or not q.faction
                        or q.faction == playerFaction then
                        n = n + 1
                    end
                end
            else
                for _ in pairs(srcData) do n = n + 1 end
            end
        elseif srcData == true then
            n = n + 1
        end
    end
    return n
end

-- Expose for testing
RecipeBook.GetSourceCount = GetSourceCount

-- Pick the best source for a single source type; returns the same 6-tuple as
-- GetBestSourceSummary, or nil if nothing in this type matches the filter.
local function BestSourceForType(profID, recipeID, srcType, srcData, hasFilter, passes)
            if srcType == "unique" then
                if #srcData > 0 then
                    local uid = srcData[1]
                    if uid == 0 then
                        -- Crafted by another profession — find which one
                        local craftedBy = RecipeBook:FindCraftingProfession(profID, recipeID)
                        local craftLabel = craftedBy and RecipeBook.PROFESSION_NAMES[craftedBy] or "Crafted"
                        return srcType, uid, craftLabel, nil, false, nil
                    end
                    if passes("unique", uid) then
                        local name = RecipeBook:GetUniqueName(uid)
                        local zone = RecipeBook:GetFirstZoneForUnique(uid)
                        return srcType, uid, name, zone, false, nil
                    end
                end
            elseif srcType == "drop" or srcType == "pickpocket" then
                -- Pick the best NPC among those matching the filter: highest
                -- drop rate, tiebreak by name.
                local bestID, bestRate, bestName
                for npcID, rate in pairs(srcData) do
                    if passes(srcType, npcID) then
                        local r = type(rate) == "number" and rate or -1
                        local name = RecipeBook:GetNPCName(npcID)
                        if not bestID
                            or r > bestRate
                            or (r == bestRate and name < bestName) then
                            bestID = npcID
                            bestRate = r
                            bestName = name
                        end
                    end
                end
                if bestID then
                    local zone = RecipeBook:GetFirstZoneForNPC(bestID)
                    local rateOut = (bestRate and bestRate >= 0) and bestRate or nil
                    return srcType, bestID, bestName, zone, false, rateOut
                end
            elseif srcType == "trainer" then
                -- Trainers: just show "Trainer" — use AB to find nearest.
                -- sourceID = nil signals the waypoint handler to search by profession.
                -- When a filter is active, require at least one trainer NPC in zone.
                if not hasFilter then
                    return srcType, nil, "Trainer", nil, false, nil
                end
                for npcID in pairs(srcData) do
                    if passes("trainer", npcID) then
                        return srcType, nil, "Trainer", nil, false, nil
                    end
                end
            elseif srcType == "vendor" then
                -- Vendors: show specific NPC, prefer player faction, require filter match.
                local _, playerFaction = UnitFactionGroup("player")
                local fallbackID = nil
                for npcID in pairs(srcData) do
                    if passes("vendor", npcID) then
                        local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
                        local npcFaction = npc and npc.faction
                        if npcFaction == playerFaction or not npcFaction then
                            local name = RecipeBook:GetNPCName(npcID)
                            local zone = RecipeBook:GetFirstZoneForNPC(npcID)
                            return srcType, npcID, name, zone, false, nil
                        end
                        if not fallbackID then fallbackID = npcID end
                    end
                end
                if fallbackID then
                    local name = RecipeBook:GetNPCName(fallbackID)
                    local zone = RecipeBook:GetFirstZoneForNPC(fallbackID)
                    return srcType, fallbackID, name, zone, false, nil
                end
            elseif srcType == "quest" then
                local _, playerFaction = UnitFactionGroup("player")
                local function questFaction(qd)
                    if not qd then return nil end
                    if qd.faction then return qd.faction end
                    -- Fall back to the start NPC's faction
                    if qd.startNPC then
                        local npc = RecipeBook.npcDB and RecipeBook.npcDB[qd.startNPC]
                        if npc and npc.faction then return npc.faction end
                    end
                    return nil
                end
                local function questDisplay(questID)
                    local qd = RecipeBook.questDB and RecipeBook.questDB[questID]
                    local name = qd and qd.name or ("Quest #" .. questID)
                    local zone = nil
                    if qd and qd.startNPC then
                        zone = RecipeBook:GetFirstZoneForNPC(qd.startNPC)
                    end
                    return name, zone
                end
                -- Prefer a quest that passes the zone filter and matches faction.
                for questID in pairs(srcData) do
                    if passes("quest", questID) then
                        local qd = RecipeBook.questDB and RecipeBook.questDB[questID]
                        local qFaction = questFaction(qd)
                        if qFaction == playerFaction or not qFaction then
                            local name, zone = questDisplay(questID)
                            return srcType, questID, name, zone, false, nil
                        end
                    end
                end
                -- Fall back to any quest when no filter is set.
                if not hasFilter then
                    local bestQuestID = nil
                    for questID in pairs(srcData) do
                        local qd = RecipeBook.questDB and RecipeBook.questDB[questID]
                        local qFaction = questFaction(qd)
                        if qFaction == playerFaction or not qFaction then
                            local name, zone = questDisplay(questID)
                            return srcType, questID, name, zone, false, nil
                        end
                        if not bestQuestID then bestQuestID = questID end
                    end
                    if bestQuestID then
                        local name, zone = questDisplay(bestQuestID)
                        return srcType, bestQuestID, name, zone, false, nil
                    end
                end
            elseif srcType == "object" then
                for objID in pairs(srcData) do
                    if passes("object", objID) then
                        local name = RecipeBook:GetObjectName(objID)
                        local zone = RecipeBook:GetFirstZoneForObject(objID)
                        return srcType, objID, name, zone, false, nil
                    end
                end
            elseif srcType == "fishing" then
                for areaID in pairs(srcData) do
                    if passes("fishing", areaID) then
                        local zone = RecipeBook:GetZoneNameForAreaID(areaID)
                        return srcType, areaID, "Fishing", zone, false, nil
                    end
                end
            elseif srcType == "item" then
                -- Items carry no zone data; only show if no filter is active.
                if not hasFilter then
                    for itemID in pairs(srcData) do
                        local name = RecipeBook.itemNames[itemID] or ("Item #" .. itemID)
                        return srcType, itemID, name, nil, false, nil
                    end
                end
            elseif srcType == "discovery" then
                -- Discovery recipes (Alchemy mastery): learned via crafting,
                -- no NPC/zone. Only show when no zone filter is active.
                if not hasFilter and srcData == true then
                    return srcType, nil, "Discovery", nil, false, nil
                end
            elseif srcType == "worldDrop" then
                -- World-drop recipes (Jewelcrafting). May be:
                --  * true — legacy flag, no zone data scraped
                --  * { areaID, ... } — scraped drop zones from Wowhead
                if srcData == true then
                    if not hasFilter then
                        return srcType, nil, "World Drop", nil, true, nil
                    end
                elseif type(srcData) == "table" then
                    for _, areaID in ipairs(srcData) do
                        if passes("worldDrop", areaID) then
                            local zone = RecipeBook:GetZoneNameForAreaID(areaID)
                            return srcType, areaID, "World Drop", zone, true, nil
                        end
                    end
                    -- No zone filter — surface with the first known zone if any.
                    if not hasFilter then
                        local firstZone = nil
                        for _, areaID in ipairs(srcData) do
                            firstZone = RecipeBook:GetZoneNameForAreaID(areaID)
                            if firstZone then break end
                        end
                        return srcType, nil, "World Drop", firstZone, true, nil
                    end
                end
            end
    return nil
end

-- Build the best single-source summary for a recipe row (first match across
-- all source types in SOURCE_ORDER).
local function GetBestSourceSummary(profID, recipeID, filterZone, filterContinent)
    local sources = RecipeBook.sourceDB[profID] and RecipeBook.sourceDB[profID][recipeID]
    if not sources then
        -- No source data at all — default to Trainer (common for basic learned recipes)
        return "trainer", nil, "Trainer", nil, false
    end
    local hasFilter = filterZone or filterContinent
    local function passes(srcType, srcID)
        if not hasFilter then return true end
        return SourcePassesZoneFilter(srcType, srcID, filterZone, filterContinent)
    end
    for _, srcType in ipairs(RecipeBook.SOURCE_ORDER) do
        local srcData = sources[srcType]
        if srcData then
            local a, b, c, d, e, f = BestSourceForType(profID, recipeID, srcType, srcData, hasFilter, passes)
            if a then return a, b, c, d, e, f end
        end
    end
    return nil, nil, nil, nil, false, nil
end

-- Build one summary per source type for a recipe (for multi-category display).
-- Returns an array of 6-tuples, in SOURCE_ORDER.
local function GetAllSourceSummaries(profID, recipeID, filterZone, filterContinent)
    local sources = RecipeBook.sourceDB[profID] and RecipeBook.sourceDB[profID][recipeID]
    if not sources then
        return { { "trainer", nil, "Trainer", nil, false, nil } }
    end
    local hasFilter = filterZone or filterContinent
    local function passes(srcType, srcID)
        if not hasFilter then return true end
        return SourcePassesZoneFilter(srcType, srcID, filterZone, filterContinent)
    end
    local out = {}
    for _, srcType in ipairs(RecipeBook.SOURCE_ORDER) do
        local srcData = sources[srcType]
        if srcData then
            local a, b, c, d, e, f = BestSourceForType(profID, recipeID, srcType, srcData, hasFilter, passes)
            if a then
                out[#out + 1] = { a, b, c, d, e, f }
            end
        end
    end
    return out
end

-- Check if a recipe has any source accessible to the player's faction
-- Returns true if at least one source is neutral or matches playerFaction
local function RecipePassesFactionFilter(profID, recipeID, playerFaction)
    if not playerFaction then return true end

    local sources = RecipeBook.sourceDB[profID] and RecipeBook.sourceDB[profID][recipeID]
    if not sources then return true end

    local hasAnyFactionSource = false

    for srcType, srcData in pairs(sources) do
        if srcType == "trainer" or srcType == "vendor" or srcType == "drop" or srcType == "pickpocket" then
            for npcID in pairs(srcData) do
                local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
                if npc then
                    if not npc.faction then
                        return true  -- Neutral NPC, always available
                    end
                    hasAnyFactionSource = true
                    if npc.faction == playerFaction then
                        return true  -- Same faction
                    end
                end
            end
        elseif srcType == "quest" then
            for questID in pairs(srcData) do
                local quest = RecipeBook.questDB and RecipeBook.questDB[questID]
                if quest then
                    local qFaction = quest.faction
                    if not qFaction and quest.startNPC then
                        local npc = RecipeBook.npcDB and RecipeBook.npcDB[quest.startNPC]
                        qFaction = npc and npc.faction or nil
                    end
                    if not qFaction then
                        return true  -- Neutral quest
                    end
                    hasAnyFactionSource = true
                    if qFaction == playerFaction then
                        return true
                    end
                end
            end
        else
            -- object, item, fishing, unique, world drops — no faction restriction
            return true
        end
    end

    -- If we found faction-tagged sources but none matched, filter it out
    return not hasAnyFactionSource
end

-- Build grouped and filtered recipe entries for display
local function BuildDisplayData(filters)
    local profID = filters.professionID
    if not profID then return {} end

    local recipes = RecipeBook.recipeDB[profID]
    if not recipes then return {} end

    local groups = {}
    for _, srcType in ipairs(RecipeBook.SOURCE_ORDER) do
        groups[srcType] = {}
    end

    local viewedKey = filters.viewedCharKey
    local listMode = filters.listMode or "all"

    for recipeID, data in pairs(recipes) do
        local dominated = false

        -- List-mode filter (Wishlist / Ignored view)
        if listMode == "wishlist" then
            if not RecipeBook:IsRecipeInWishlist(profID, recipeID, viewedKey) then
                dominated = true
            end
        elseif listMode == "ignored" then
            if not RecipeBook:IsRecipeIgnored(profID, recipeID, viewedKey) then
                dominated = true
            end
        end

        -- Phase filter
        if not dominated then
            local phase = RecipeBook:GetRecipePhase(profID, recipeID)
            if phase > filters.maxPhase then dominated = true end
        end
        -- Hide known / ignored (only applies to the "all" list)
        if not dominated and listMode == "all" and filters.hideKnown then
            if RecipeBook:IsRecipeKnown(profID, recipeID, viewedKey)
                or RecipeBook:IsRecipeIgnored(profID, recipeID, viewedKey) then
                dominated = true
            end
        end
        -- Hide unlearnable
        if not dominated and filters.hideUnlearnable
            and not RecipeBook:IsRecipeKnown(profID, recipeID)
            and not RecipeBook:IsRecipeLearnable(profID, recipeID) then
            dominated = true
        end
        -- Faction filter
        if not dominated and not RecipePassesFactionFilter(profID, recipeID, filters.playerFaction) then
            dominated = true
        end
        -- Zone filter
        if not dominated and not RecipePassesZoneFilter(profID, recipeID, filters.zone, filters.continent) then
            dominated = true
        end
        -- Search filter
        if not dominated and filters.searchText then
            local name = RecipeBook:GetRecipeName(profID, recipeID)
            if not name or not strlower(name):find(filters.searchText, 1, true) then
                dominated = true
            end
        end

        if not dominated then
            local summaries = GetAllSourceSummaries(profID, recipeID, filters.zone, filters.continent)
            local count = GetSourceCount(profID, recipeID, filters.playerFaction)
            local isKnown = RecipeBook:IsRecipeKnown(profID, recipeID)
            local isLearnable = not isKnown and RecipeBook:IsRecipeLearnable(profID, recipeID)
            for _, s in ipairs(summaries) do
                local srcType, srcID, srcName, srcZone, isWorldDrop, dropRate = s[1], s[2], s[3], s[4], s[5], s[6]
                groups[srcType][#groups[srcType] + 1] = {
                    recipeID = recipeID,
                    requiredSkill = data.requiredSkill or 0,
                    sourceType = srcType,
                    sourceID = srcID,
                    sourceName = srcName,
                    sourceZone = srcZone,
                    sourceCount = count,
                    dropRate = dropRate,
                    isWorldDrop = isWorldDrop,
                    isKnown = RecipeBook:IsRecipeKnown(profID, recipeID, viewedKey),
                    isWishlist = RecipeBook:IsRecipeInWishlist(profID, recipeID, viewedKey),
                    isIgnored = RecipeBook:IsRecipeIgnored(profID, recipeID, viewedKey),
                    isLearnable = isLearnable,
                    difficulty = data.difficulty,
                }
            end
        end
    end

    -- Sort each group by requiredSkill
    for srcType, entries in pairs(groups) do
        table.sort(entries, function(a, b)
            if a.requiredSkill == b.requiredSkill then
                local nameA = RecipeBook:GetRecipeName(profID, a.recipeID)
                local nameB = RecipeBook:GetRecipeName(profID, b.recipeID)
                return nameA < nameB
            end
            return a.requiredSkill < b.requiredSkill
        end)
    end

    return groups
end

function RecipeBook:ClearRenderCaches()
    wipe(recipeQualityCache)
    for _, row in ipairs(displayedRows) do
        self:RecycleRow(row)
    end
    wipe(displayedRows)
end

-- Refresh the recipe list display
function RecipeBook:RefreshRecipeList()
    if not self.mainFrame then return end
    local scrollChild = self.mainFrame._scrollChild
    if not scrollChild then return end

    -- Recycle existing rows
    for _, row in ipairs(displayedRows) do
        self:RecycleRow(row)
    end
    wipe(displayedRows)

    local filters = self:GetFilterState()

    if not filters.professionID then
        local row = self:GetHeaderRow(scrollChild)
        row._nameText:SetText("Select a profession to browse recipes.")
        row._nameText:SetTextColor(0.7, 0.7, 0.7)
        row._toggleIcon:Hide()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        displayedRows[#displayedRows + 1] = row
        scrollChild:SetHeight(UI.ROW_HEIGHT)
        if self.mainFrame._countText then
            self.mainFrame._countText:SetText("")
        end
        return
    end

    local groups = BuildDisplayData(filters)
    local yOffset = 0
    local totalShown = 0
    local totalRecipes = 0
    local totalKnown = 0

    -- Count totals for this profession
    local allRecipes = self.recipeDB[filters.professionID]
    if allRecipes then
        for recipeID, data in pairs(allRecipes) do
            local phase = self:GetRecipePhase(filters.professionID, recipeID)
            if phase <= filters.maxPhase then
                totalRecipes = totalRecipes + 1
                if self:IsRecipeKnown(filters.professionID, recipeID) then
                    totalKnown = totalKnown + 1
                end
            end
        end
    end

    local collapsed = RecipeBookCharDB and RecipeBookCharDB.collapsedSources or {}

    for _, srcType in ipairs(self.SOURCE_ORDER) do
        local entries = groups[srcType]
        if entries and #entries > 0 then
            local isCollapsed = collapsed[srcType]

            -- Source type header (collapsible)
            local headerRow = self:GetHeaderRow(scrollChild)
            local label = self.SOURCE_LABELS[srcType] or srcType
            headerRow._nameText:SetText(label .. " (" .. #entries .. ")")
            headerRow._nameText:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)
            headerRow._headerSrcType = srcType
            headerRow._toggleIcon:SetTexture(isCollapsed and UI.ICON_EXPAND or UI.ICON_COLLAPSE)
            headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
            headerRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            headerRow:SetScript("OnClick", OnHeaderClick)
            displayedRows[#displayedRows + 1] = headerRow
            yOffset = yOffset - UI.ROW_HEIGHT

            -- Recipe rows (skip if collapsed)
            if not isCollapsed then
                for _, entry in ipairs(entries) do
                    local row = self:GetPooledRow(scrollChild)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14, yOffset)
                    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

                    -- Recipe name with quality color + wishlist/ignored indicators
                    local recipeName = self:GetRecipeName(filters.professionID, entry.recipeID)
                    row._nameText:SetFontObject("RecipeBookFontHighlight")
                    row._nameText:SetWidth(210)
                    row._nameText:ClearAllPoints()
                    row._nameText:SetPoint("LEFT", row, "LEFT", 4, 0)

                    local displayName = recipeName
                    if entry.isWishlist then
                        displayName = "|cffffd833*|r " .. displayName
                    end
                    row._nameText:SetText(displayName)

                    if entry.isIgnored then
                        row._nameText:SetTextColor(UI.COLOR_IGNORED.r, UI.COLOR_IGNORED.g, UI.COLOR_IGNORED.b)
                    elseif entry.isKnown then
                        row._nameText:SetTextColor(UI.COLOR_KNOWN.r, UI.COLOR_KNOWN.g, UI.COLOR_KNOWN.b)
                    else
                        local qc = GetRecipeQualityColor(filters.professionID, entry.recipeID)
                        row._nameText:SetTextColor(qc.r, qc.g, qc.b)
                    end

                    -- Learnable indicator
                    if row._learnIcon then
                        if entry.isKnown then
                            row._learnIcon:Hide()
                        elseif entry.isLearnable then
                            row._learnIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                            row._learnIcon:Show()
                        else
                            row._learnIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                            row._learnIcon:Show()
                        end
                    end

                    -- Skill level (colored by crafting difficulty)
                    row._skillText:SetText(tostring(entry.requiredSkill))
                    local skillColor = UI.COLOR_SKILL
                    local diff = entry.difficulty
                    local playerSkill = RecipeBookCharDB
                        and RecipeBookCharDB.professionSkill
                        and RecipeBookCharDB.professionSkill[filters.professionID]
                    if not playerSkill then
                        skillColor = { r = 1.0, g = 0.2, b = 0.2 }
                    elseif diff and playerSkill then
                        if playerSkill < diff[1] then
                            skillColor = { r = 1.0, g = 0.2, b = 0.2 }
                        elseif playerSkill < diff[2] then
                            skillColor = UI.COLOR_ORANGE
                        elseif playerSkill < diff[3] then
                            skillColor = UI.COLOR_YELLOW
                        elseif playerSkill < diff[4] then
                            skillColor = UI.COLOR_GREEN
                        elseif not entry.isKnown then
                            skillColor = UI.COLOR_NORMAL
                        else
                            skillColor = UI.COLOR_GRAY
                        end
                    end
                    row._skillText:SetTextColor(skillColor.r, skillColor.g, skillColor.b)

                    -- Source count
                    if row._countText then
                        row._countText:SetText(tostring(entry.sourceCount or 0))
                    end

                    -- Source summary (always show the chosen best NPC)
                    local sourceStr = entry.sourceName or ""
                    if entry.sourceZone then
                        sourceStr = sourceStr .. " |cff999999(" .. entry.sourceZone .. ")|r"
                    end
                    row._sourceText:SetText(sourceStr)
                    row._sourceText:SetTextColor(UI.COLOR_SOURCE.r, UI.COLOR_SOURCE.g, UI.COLOR_SOURCE.b)

                    -- Drop rate %
                    if row._rateText then
                        if entry.dropRate then
                            row._rateText:SetText(string.format("%.1f%%", entry.dropRate))
                        else
                            row._rateText:SetText("")
                        end
                    end

                    -- Waypoint arrow
                    local questHasStartNPC = false
                    if entry.sourceType == "quest" and entry.sourceID then
                        local qd = RecipeBook.questDB and RecipeBook.questDB[entry.sourceID]
                        if qd and qd.startNPC then questHasStartNPC = true end
                    end
                    local canWaypoint = RecipeBook:HasAddressBook() and RecipeBook:HasTomTom()
                        and (entry.sourceType == "trainer"  -- trainers use AB search
                            or (entry.sourceID and entry.sourceID ~= 0
                                and (entry.sourceType == "vendor"
                                    or entry.sourceType == "drop" or entry.sourceType == "pickpocket"
                                    or entry.sourceType == "object" or entry.sourceType == "unique"))
                            or questHasStartNPC)

                    -- Store data on row for handlers
                    row._recipeID = entry.recipeID
                    row._profID = filters.professionID
                    row._sourceType = entry.sourceType
                    row._sourceID = entry.sourceID
                    row._isWorldDrop = entry.isWorldDrop
                    row._canWaypoint = canWaypoint
                    row._isTrainerWP = (entry.sourceType == "trainer")

                    -- Resolve NPC name for waypoint
                    if canWaypoint then
                        if entry.sourceType == "trainer" then
                            -- For trainers, search AB by profession name
                            local profName = RecipeBook.PROFESSION_NAMES[filters.professionID]
                            row._npcName = profName .. " Trainer"
                            row._zoneName = nil
                        elseif entry.sourceType == "vendor"
                            or entry.sourceType == "drop" or entry.sourceType == "pickpocket" then
                            row._npcName = self:GetNPCName(entry.sourceID)
                            row._zoneName = self:GetFirstZoneForNPC(entry.sourceID)
                        elseif entry.sourceType == "object" then
                            row._npcName = self:GetObjectName(entry.sourceID)
                            row._zoneName = self:GetFirstZoneForObject(entry.sourceID)
                        elseif entry.sourceType == "unique" then
                            row._npcName = self:GetUniqueName(entry.sourceID)
                            row._zoneName = self:GetFirstZoneForUnique(entry.sourceID)
                        elseif entry.sourceType == "quest" then
                            local qd = RecipeBook.questDB and RecipeBook.questDB[entry.sourceID]
                            if qd and qd.startNPC then
                                row._npcName = self:GetNPCName(qd.startNPC)
                                row._zoneName = self:GetFirstZoneForNPC(qd.startNPC)
                            end
                        end

                    else
                        row._npcName = nil
                        row._zoneName = nil
                    end

                    -- Set handlers
                    row:SetScript("OnEnter", OnRecipeEnter)
                    row:SetScript("OnLeave", OnRecipeLeave)
                    row:SetScript("OnClick", OnRecipeClick)

                    displayedRows[#displayedRows + 1] = row
                    yOffset = yOffset - UI.ROW_HEIGHT
                    totalShown = totalShown + 1
                end
            else
                totalShown = totalShown + #entries
            end

            -- Spacing between groups
            yOffset = yOffset - 4
        end
    end

    scrollChild:SetHeight(math.abs(yOffset) + 20)

    -- Update count text
    if self.mainFrame._countText then
        self.mainFrame._countText:SetText(
            totalShown .. " shown | " .. totalKnown .. "/" .. totalRecipes .. " known"
        )
    end

    -- Refresh the sources popup if it's open
    if self.IsSourcesPopupShown and self:IsSourcesPopupShown() then
        self:RefreshSourcesPopup()
    end
end
