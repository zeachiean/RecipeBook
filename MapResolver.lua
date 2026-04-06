RecipeBook = RecipeBook or {}

-- Area ID -> zone name lookup (RecipeMaster stores area IDs, not map IDs)
local areaToZone = {}

-- Zone name -> continent name
local zoneToContinent = {}

-- Continent name -> { sorted zone names }
local continentZones = {}

-- Sorted continent list
local continentList = {}

-- Map name -> mapID (for C_Map operations)
local zoneLookup = nil

function RecipeBook:BuildMapLookup()
    zoneLookup = {}
    for id = 1, 2500 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            local key = strlower(info.name)
            if not zoneLookup[key] then
                zoneLookup[key] = id
            elseif info.mapType == Enum.UIMapType.Zone then
                zoneLookup[key] = id
            end
        end
    end
    return zoneLookup
end

function RecipeBook:BuildAreaToZoneLookup()
    wipe(areaToZone)

    -- Collect all unique area IDs from NPC, Object, Unique databases
    local areaIDs = {}
    if self.npcDB then
        for _, npc in pairs(self.npcDB) do
            if npc.zones then
                for _, zoneID in ipairs(npc.zones) do
                    areaIDs[zoneID] = true
                end
            end
        end
    end
    if self.objectDB then
        for _, obj in pairs(self.objectDB) do
            if obj.zones then
                for _, zoneID in ipairs(obj.zones) do
                    areaIDs[zoneID] = true
                end
            end
        end
    end
    if self.uniqueDB then
        for _, entry in pairs(self.uniqueDB) do
            if entry.zones then
                for _, zoneID in ipairs(entry.zones) do
                    areaIDs[zoneID] = true
                end
            end
        end
    end

    -- Also collect fishing source keys (they ARE area IDs) and worldDrop
    -- area-ID lists (JC designs patched from Wowhead's dropped-by listview).
    if self.sourceDB then
        for profID, recipes in pairs(self.sourceDB) do
            for recipeID, sources in pairs(recipes) do
                if sources.fishing then
                    for areaID in pairs(sources.fishing) do
                        areaIDs[areaID] = true
                    end
                end
                if type(sources.worldDrop) == "table" then
                    for _, areaID in ipairs(sources.worldDrop) do
                        areaIDs[areaID] = true
                    end
                end
            end
        end
    end

    -- Resolve each area ID to a zone name
    for areaID in pairs(areaIDs) do
        local name = C_Map.GetAreaInfo(areaID)
        if name then
            areaToZone[areaID] = name
        end
    end
end

function RecipeBook:BuildContinentZoneMap()
    wipe(continentZones)
    wipe(zoneToContinent)
    wipe(continentList)

    if not zoneLookup then
        self:BuildMapLookup()
    end

    -- Walk all known zone mapIDs and trace each to its continent parent
    for zoneName, mapID in pairs(zoneLookup) do
        local info = C_Map.GetMapInfo(mapID)
        if info and info.mapType == Enum.UIMapType.Zone then
            local parentID = info.parentMapID
            local continentName = nil
            local depth = 0
            while parentID and parentID > 0 and depth < 5 do
                local parentInfo = C_Map.GetMapInfo(parentID)
                if not parentInfo then break end
                if parentInfo.mapType == Enum.UIMapType.Continent then
                    continentName = parentInfo.name
                    break
                end
                parentID = parentInfo.parentMapID
                depth = depth + 1
            end

            if continentName and info.name then
                zoneToContinent[info.name] = continentName
                if not continentZones[continentName] then
                    continentZones[continentName] = {}
                end
                continentZones[continentName][info.name] = true
            end
        end
    end

    -- Instance-to-continent overrides
    local instanceOverrides = {
        -- Classic - Eastern Kingdoms
        ["Blackrock Depths"] = "Eastern Kingdoms",
        ["Blackrock Spire"] = "Eastern Kingdoms",
        ["Scarlet Monastery"] = "Eastern Kingdoms",
        ["Stratholme"] = "Eastern Kingdoms",
        ["Scholomance"] = "Eastern Kingdoms",
        ["Uldaman"] = "Eastern Kingdoms",
        ["Gnomeregan"] = "Eastern Kingdoms",
        ["The Deadmines"] = "Eastern Kingdoms",
        ["The Stockade"] = "Eastern Kingdoms",
        ["Shadowfang Keep"] = "Eastern Kingdoms",
        ["Sunken Temple"] = "Eastern Kingdoms",
        ["Zul'Gurub"] = "Eastern Kingdoms",
        ["Blackwing Lair"] = "Eastern Kingdoms",
        ["Molten Core"] = "Eastern Kingdoms",
        ["Naxxramas"] = "Eastern Kingdoms",
        ["Karazhan"] = "Eastern Kingdoms",
        ["Zul'Aman"] = "Eastern Kingdoms",
        ["Sunwell Plateau"] = "Eastern Kingdoms",
        -- Classic - Kalimdor
        ["Wailing Caverns"] = "Kalimdor",
        ["Razorfen Kraul"] = "Kalimdor",
        ["Razorfen Downs"] = "Kalimdor",
        ["Maraudon"] = "Kalimdor",
        ["Dire Maul"] = "Kalimdor",
        ["Zul'Farrak"] = "Kalimdor",
        ["Blackfathom Deeps"] = "Kalimdor",
        ["Ragefire Chasm"] = "Kalimdor",
        ["Onyxia's Lair"] = "Kalimdor",
        ["Ahn'Qiraj"] = "Kalimdor",
        ["Ruins of Ahn'Qiraj"] = "Kalimdor",
        ["Hyjal Summit"] = "Kalimdor",
        -- TBC - Outland
        ["Hellfire Ramparts"] = "Outland",
        ["The Blood Furnace"] = "Outland",
        ["The Shattered Halls"] = "Outland",
        ["The Slave Pens"] = "Outland",
        ["The Underbog"] = "Outland",
        ["The Steamvault"] = "Outland",
        ["Mana-Tombs"] = "Outland",
        ["Auchenai Crypts"] = "Outland",
        ["Sethekk Halls"] = "Outland",
        ["Shadow Labyrinth"] = "Outland",
        ["The Mechanar"] = "Outland",
        ["The Botanica"] = "Outland",
        ["The Arcatraz"] = "Outland",
        ["Magisters' Terrace"] = "Outland",
        ["Serpentshrine Cavern"] = "Outland",
        ["Black Temple"] = "Outland",
        ["Magtheridon's Lair"] = "Outland",
        ["Gruul's Lair"] = "Outland",
        ["Tempest Keep"] = "Outland",
        -- Caverns of Time
        ["Old Hillsbrad Foothills"] = "Kalimdor",
        ["The Black Morass"] = "Kalimdor",
        -- PvP
        ["Alterac Valley"] = "Eastern Kingdoms",
        ["Arathi Basin"] = "Eastern Kingdoms",
        ["Warsong Gulch"] = "Kalimdor",
    }
    for instanceName, cont in pairs(instanceOverrides) do
        if not zoneToContinent[instanceName] then
            zoneToContinent[instanceName] = cont
            if not continentZones[cont] then
                continentZones[cont] = {}
            end
            continentZones[cont][instanceName] = true
        end
    end

    -- Build sorted continent list
    for name in pairs(continentZones) do
        continentList[#continentList + 1] = name
    end
    table.sort(continentList)

    -- Convert zone sets to sorted lists
    for continent, zones in pairs(continentZones) do
        local sorted = {}
        for z in pairs(zones) do
            sorted[#sorted + 1] = z
        end
        table.sort(sorted)
        continentZones[continent] = sorted
    end
end

function RecipeBook:GetContinents()
    return continentList
end

function RecipeBook:GetZonesForContinent(continent)
    if not continent then return {} end
    return continentZones[continent] or {}
end

function RecipeBook:GetContinentForZone(zoneName)
    return zoneToContinent[zoneName]
end

function RecipeBook:ClearMapCaches()
    wipe(areaToZone)
    wipe(zoneToContinent)
    wipe(continentZones)
    wipe(continentList)
    zoneLookup = nil
end

function RecipeBook:GetCurrentZoneName()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name
end

function RecipeBook:GetZoneNameForAreaID(areaID)
    return areaToZone[areaID]
end

-- Get all zones that have recipe sources for a given profession
function RecipeBook:GetZonesWithSources(profID)
    local zoneSet = {}
    local sources = self.sourceDB and self.sourceDB[profID]
    if not sources then return {} end

    for recipeID, srcTypes in pairs(sources) do
        for srcType, srcData in pairs(srcTypes) do
            if srcType == "trainer" or srcType == "vendor" or srcType == "drop" or srcType == "pickpocket" then
                for npcID in pairs(srcData) do
                    local npc = self.npcDB and self.npcDB[npcID]
                    if npc and npc.zones then
                        for _, areaID in ipairs(npc.zones) do
                            local name = areaToZone[areaID]
                            if name then zoneSet[name] = true end
                        end
                    end
                end
            elseif srcType == "object" then
                for objID in pairs(srcData) do
                    local obj = self.objectDB and self.objectDB[objID]
                    if obj and obj.zones then
                        for _, areaID in ipairs(obj.zones) do
                            local name = areaToZone[areaID]
                            if name then zoneSet[name] = true end
                        end
                    end
                end
            elseif srcType == "unique" then
                for _, uid in ipairs(srcData) do
                    local entry = self.uniqueDB and self.uniqueDB[uid]
                    if entry and entry.zones then
                        for _, areaID in ipairs(entry.zones) do
                            local name = areaToZone[areaID]
                            if name then zoneSet[name] = true end
                        end
                    end
                end
            elseif srcType == "fishing" then
                for areaID in pairs(srcData) do
                    local name = areaToZone[areaID]
                    if name then zoneSet[name] = true end
                end
            elseif srcType == "worldDrop" and type(srcData) == "table" then
                for _, areaID in ipairs(srcData) do
                    local name = areaToZone[areaID]
                    if name then zoneSet[name] = true end
                end
            end
        end
    end

    local sorted = {}
    for z in pairs(zoneSet) do
        sorted[#sorted + 1] = z
    end
    table.sort(sorted)
    return sorted
end
