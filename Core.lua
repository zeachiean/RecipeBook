RecipeBook = RecipeBook or {}

RecipeBook.VERSION = "1.1.1"
RecipeBook.ADDON_NAME = "RecipeBook"
RecipeBook.mainFrame = nil

-- Fixed-size fonts
local FONT_FILE = "Fonts\\FRIZQT__.TTF"

local fontTitle = CreateFont("RecipeBookFontTitle")
fontTitle:SetFont(FONT_FILE, 13, "")
fontTitle:SetTextColor(1, 0.82, 0)

local fontNormal = CreateFont("RecipeBookFontNormal")
fontNormal:SetFont(FONT_FILE, 11, "")
fontNormal:SetTextColor(1, 0.82, 0)

local fontSmall = CreateFont("RecipeBookFontSmall")
fontSmall:SetFont(FONT_FILE, 10, "")
fontSmall:SetTextColor(1, 0.82, 0)

local fontHighlight = CreateFont("RecipeBookFontHighlight")
fontHighlight:SetFont(FONT_FILE, 10, "")
fontHighlight:SetTextColor(1, 1, 1)

local fontWhite = CreateFont("RecipeBookFontWhite")
fontWhite:SetFont(FONT_FILE, 11, "")
fontWhite:SetTextColor(1, 1, 1)

-- Chat prefix
local CHAT_PREFIX = "|cff33bbff[RecipeBook]|r "

function RecipeBook:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(msg))
end

-- Profession data
RecipeBook.PROFESSIONS = {
    { id = 171, name = "Alchemy" },
    { id = 164, name = "Blacksmithing" },
    { id = 185, name = "Cooking" },
    { id = 333, name = "Enchanting" },
    { id = 202, name = "Engineering" },
    { id = 129, name = "First Aid" },
    { id = 356, name = "Fishing" },
    { id = 755, name = "Jewelcrafting" },
    { id = 165, name = "Leatherworking" },
    { id = 186, name = "Mining" },
    { id = 2842, name = "Poisons" },
    { id = 197, name = "Tailoring" },
}

-- Lookup by ID
RecipeBook.PROFESSION_NAMES = {}
for _, prof in ipairs(RecipeBook.PROFESSIONS) do
    RecipeBook.PROFESSION_NAMES[prof.id] = prof.name
end

-- Source type display order and labels
RecipeBook.SOURCE_ORDER = { "trainer", "vendor", "quest", "drop", "pickpocket", "object", "item", "fishing", "unique", "discovery", "worldDrop" }
RecipeBook.SOURCE_LABELS = {
    trainer = "Trainer",
    vendor = "Vendor",
    quest = "Quest",
    drop = "Drop",
    pickpocket = "Pickpocket",
    object = "Object",
    item = "Contained In",
    fishing = "Fishing",
    unique = "Special",
    discovery = "Discovery",
    worldDrop = "World Drop",
}

-- Phase labels
RecipeBook.PHASE_LABELS = {
    [1] = "Phase 1",
    [2] = "Phase 2",
    [3] = "Phase 3",
    [4] = "Phase 4",
    [5] = "Phase 5",
}

-- World drop NPC threshold
RecipeBook.WORLD_DROP_THRESHOLD = 10

-- Recipe name/link/icon caches
RecipeBook.recipeNames = {}
RecipeBook.recipeIcons = {}

-- Item name cache (for "item" source type)
RecipeBook.itemNames = {}

-- Active waypoint tracking
RecipeBook.activeWaypoint = nil    -- { npcName, zoneName }

-- Prefixes to strip from recipe item names
local RECIPE_PREFIXES = {
    "Recipe: ", "Plans: ", "Formula: ", "Schematic: ",
    "Pattern: ", "Manual: ", "Design: ",
}

local function StripRecipePrefix(name)
    if not name then return nil end
    for _, prefix in ipairs(RECIPE_PREFIXES) do
        if name:sub(1, #prefix) == prefix then
            return name:sub(#prefix + 1)
        end
    end
    return name
end

-- Cache recipe names asynchronously
function RecipeBook:CacheRecipeNames()
    for profID, recipes in pairs(self.recipeDB) do
        if not self.recipeNames[profID] then
            self.recipeNames[profID] = {}
        end
        if not self.recipeIcons[profID] then
            self.recipeIcons[profID] = {}
        end

        for recipeID, data in pairs(recipes) do
            -- Engineering (202): recipeDB keys came from spell data. When
            -- teaches == recipeID, the key is a spell id — some collide with
            -- unrelated items (e.g. spell 30311 = Adamantite Grenade create,
            -- item 30311 = Warp Slicer). Resolve via spell. Schematic-keyed
            -- entries (teaches != recipeID) still fall through to item lookup.
            if profID == 202 and not data.isSpell and data.teaches == recipeID then
                local name, _, icon = GetSpellInfo(recipeID)
                if name then
                    self.recipeNames[profID][recipeID] = name
                    self.recipeIcons[profID][recipeID] = icon
                end
            elseif data.isSpell then
                -- Mining (186) and Poisons (40): `teaches` is an ITEM id,
                -- not a spell id. Spell lookup collides with unrelated
                -- spells (e.g. 3569 → "Azure Silk Vest"). Resolve via item.
                if (profID == 186 or profID == 40) and data.teaches then
                    local iname, _, _, _, _, _, _, _, _, iicon = C_Item.GetItemInfo(data.teaches)
                    if iname then
                        if profID == 186 then
                            iname = "Smelt " .. iname:gsub(" Bar$", "")
                        end
                        self.recipeNames[profID][recipeID] = iname
                        self.recipeIcons[profID][recipeID] = iicon
                    elseif C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(data.teaches)
                    end
                else
                    local name, _, icon = GetSpellInfo(data.teaches)
                    if name then
                        self.recipeNames[profID][recipeID] = name
                        self.recipeIcons[profID][recipeID] = icon
                    end
                end
            else
                local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(recipeID)
                if name then
                    self.recipeNames[profID][recipeID] = StripRecipePrefix(name)
                    self.recipeIcons[profID][recipeID] = icon
                end
            end
        end
    end
end

-- Cache item names for "item" source type
function RecipeBook:CacheItemSourceNames()
    if not self.sourceDB then return end
    for profID, recipes in pairs(self.sourceDB) do
        for recipeID, sources in pairs(recipes) do
            if sources.item then
                for itemID in pairs(sources.item) do
                    local name = C_Item.GetItemInfo(itemID)
                    if name then
                        self.itemNames[itemID] = name
                    end
                end
            end
        end
    end
end

-- Get display name for a recipe (with fallback)
function RecipeBook:GetRecipeName(profID, recipeID)
    local cached = self.recipeNames[profID] and self.recipeNames[profID][recipeID]
    if cached then return cached end

    local data = self.recipeDB[profID] and self.recipeDB[profID][recipeID]
    if not data then return "Unknown Recipe" end

    -- Engineering (202): when teaches == recipeID, the key is a spell id
    -- (see CacheRecipeNames comment). Resolve via spell lookup.
    if profID == 202 and not data.isSpell and data.teaches == recipeID then
        local name = GetSpellInfo(recipeID)
        if name then
            if not self.recipeNames[profID] then self.recipeNames[profID] = {} end
            self.recipeNames[profID][recipeID] = name
            return name
        end
        return "Loading..."
    end

    if data.isSpell then
        -- Mining (186) and Poisons (40) store the crafted ITEM id in
        -- `teaches`, not a spell id. Several of their recipeIDs collide
        -- with unrelated spell IDs in TBC Classic (e.g. GetSpellInfo(2658)
        -- returns "Poisons" instead of "Smelt Silver"), so spell lookup is
        -- unreliable. Resolve these via the crafted item instead.
        if (profID == 186 or profID == 40) and data.teaches then
            local itemName = C_Item.GetItemInfo(data.teaches)
            if itemName then
                if profID == 186 then
                    -- Display as "Smelt <Metal>" rather than "<Metal> Bar".
                    itemName = "Smelt " .. itemName:gsub(" Bar$", "")
                end
                if not self.recipeNames[profID] then self.recipeNames[profID] = {} end
                self.recipeNames[profID][recipeID] = itemName
                return itemName
            end
            -- Not loaded yet — request and return placeholder. The
            -- GET_ITEM_INFO_RECEIVED handler will refresh once available.
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(data.teaches)
            end
            return "Loading..."
        end

        -- Other professions: isSpell recipes have teaches == recipeID.
        local name = GetSpellInfo(recipeID) or (data.teaches and GetSpellInfo(data.teaches))
        if name then
            if not self.recipeNames[profID] then self.recipeNames[profID] = {} end
            self.recipeNames[profID][recipeID] = name
            return name
        end
    else
        local name = C_Item.GetItemInfo(recipeID)
        if name then
            name = StripRecipePrefix(name)
            if not self.recipeNames[profID] then self.recipeNames[profID] = {} end
            self.recipeNames[profID][recipeID] = name
            return name
        end
    end

    return "Loading..."
end

-- Get display name for an NPC
function RecipeBook:GetNPCName(npcID)
    local npc = self.npcDB and self.npcDB[npcID]
    if not npc or not npc.names then return "NPC #" .. npcID end
    return npc.names.enUS or "NPC #" .. npcID
end

-- Get display name for an object
function RecipeBook:GetObjectName(objectID)
    local obj = self.objectDB and self.objectDB[objectID]
    if not obj or not obj.names then return "Object #" .. objectID end
    return obj.names.enUS or "Object #" .. objectID
end

-- Get display name for a unique source
function RecipeBook:GetUniqueName(uniqueID)
    if uniqueID == 0 then return "Crafted" end
    local entry = self.uniqueDB and self.uniqueDB[uniqueID]
    if not entry or not entry.names then return "Special #" .. uniqueID end
    return entry.names.enUS or "Special #" .. uniqueID
end

-- Get first zone name for a source entity
function RecipeBook:GetFirstZoneForNPC(npcID)
    local npc = self.npcDB and self.npcDB[npcID]
    if not npc or not npc.zones or #npc.zones == 0 then return nil end
    return self:GetZoneNameForAreaID(npc.zones[1])
end

function RecipeBook:GetFirstZoneForObject(objectID)
    local obj = self.objectDB and self.objectDB[objectID]
    if not obj or not obj.zones or #obj.zones == 0 then return nil end
    return self:GetZoneNameForAreaID(obj.zones[1])
end

function RecipeBook:GetFirstZoneForUnique(uniqueID)
    local entry = self.uniqueDB and self.uniqueDB[uniqueID]
    if not entry or not entry.zones or #entry.zones == 0 then return nil end
    return self:GetZoneNameForAreaID(entry.zones[1])
end

-- Find which profession crafts a given recipe item (for unique=0 sources)
-- The recipe item (recipeID) is itself crafted by another profession's recipe
function RecipeBook:FindCraftingProfession(currentProfID, recipeID)
    -- Search all other professions' recipeDBs to see if any teaches this item
    -- The recipe item for profession A might be the crafted output of profession B
    for profID, recipes in pairs(self.sourceDB) do
        if profID ~= currentProfID then
            for otherRecipeID, sources in pairs(recipes) do
                -- Check if any recipe in this profession creates our item
                local data = self.recipeDB[profID] and self.recipeDB[profID][otherRecipeID]
                if data and data.teaches == recipeID then
                    return profID
                end
            end
        end
    end
    return nil
end

-- Check if AddressBook API is available
function RecipeBook:HasAddressBook()
    return AddressBook and AddressBook.API and true or false
end

-- Check if TomTom is available
function RecipeBook:HasTomTom()
    return TomTom and true or false
end

-- Check if a profession is known by the character
function RecipeBook:IsProfessionKnown(profID)
    if not RecipeBookCharDB or not RecipeBookCharDB.knownProfessions then return false end
    return RecipeBookCharDB.knownProfessions[profID] == true
end

-- StaticPopup shown when a one-shot migration wipes the known-recipe cache.
-- Only wired up when InitSavedVars actually performs a wipe — never fire this
-- speculatively. See feedback memory: saved data wipes must be rare and
-- announced.
StaticPopupDialogs["RECIPEBOOK_RESCAN_PROFESSIONS"] = {
    text = "RecipeBook: Your profession cache was reset by an update.\n\nPlease open each of your profession windows once so RecipeBook can rescan which recipes you know.",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Initialize saved variables with defaults.
-- Returns true if a one-shot migration wiped known-recipe state (caller should
-- prompt the user to reopen their profession windows).
local function InitSavedVars()
    if not RecipeBookDB then
        RecipeBookDB = {}
    end
    if not RecipeBookDB.minimap then
        RecipeBookDB.minimap = { hide = false }
    end
    if RecipeBookDB.maxPhase == nil then
        RecipeBookDB.maxPhase = 5
    end
    -- Current server phase — update this when the server advances
    RecipeBookDB.currentPhase = 1

    if not RecipeBookCharDB then
        RecipeBookCharDB = {}
    end
    if not RecipeBookCharDB.knownRecipes then
        RecipeBookCharDB.knownRecipes = {}
    end
    if not RecipeBookCharDB.knownProfessions then
        RecipeBookCharDB.knownProfessions = {}
    end
    local wiped = false

    -- One-time wipe of stale data from v1.0.0 buggy cross-profession matching
    if not RecipeBookCharDB.profTrackingFixed then
        RecipeBookCharDB.knownProfessions = {}
        RecipeBookCharDB.knownRecipes = {}
        RecipeBookCharDB.profTrackingFixed = true
        wiped = true
    end
    if RecipeBookCharDB.hideKnown == nil then
        RecipeBookCharDB.hideKnown = false
    end
    if not RecipeBookCharDB.collapsedSources then
        RecipeBookCharDB.collapsedSources = {}
    end

    return wiped
end

-- Get the effective phase for a recipe.
-- Each recipe has an explicit phase field (1-5) in recipeDB; this is the
-- single source of truth.  Earlier versions used zone-based inference as a
-- fallback, but all phases have been manually verified and hard-coded.
function RecipeBook:GetRecipePhase(profID, recipeID)
    local data = self.recipeDB[profID] and self.recipeDB[profID][recipeID]
    if not data then return 1 end
    return data.phase or 1
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local wiped = InitSavedVars()
        if wiped then
            -- Defer slightly so the popup isn't eaten by other login UI.
            C_Timer.After(2, function()
                StaticPopup_Show("RECIPEBOOK_RESCAN_PROFESSIONS")
            end)
        end
        RecipeBook:BuildMapLookup()
        RecipeBook:BuildAreaToZoneLookup()
        RecipeBook:BuildContinentZoneMap()
        RecipeBook:CacheRecipeNames()
        RecipeBook:CacheItemSourceNames()
        RecipeBook:RegisterTrackingEvents(self)
        RecipeBook:CreateMinimapButton()

        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("ZONE_CHANGED")
        self:RegisterEvent("ZONE_CHANGED_INDOORS")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE"
        or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        RecipeBook:OnTrackingEvent(event)

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:OnZoneChanged()
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success then
            -- Mining/Poisons: the received itemID may be a `teaches` value.
            -- Map it back to any recipe that references it.
            for _, pid in ipairs({ 186, 40 }) do
                local recipes = RecipeBook.recipeDB[pid]
                if recipes then
                    for rid, rdata in pairs(recipes) do
                        if rdata.isSpell and rdata.teaches == itemID then
                            local iname = C_Item.GetItemInfo(itemID)
                            if iname then
                                if pid == 186 then
                                    iname = "Smelt " .. iname:gsub(" Bar$", "")
                                end
                                if not RecipeBook.recipeNames[pid] then
                                    RecipeBook.recipeNames[pid] = {}
                                end
                                RecipeBook.recipeNames[pid][rid] = iname
                            end
                        end
                    end
                end
            end
            for profID, recipes in pairs(RecipeBook.recipeDB) do
                if recipes[itemID] then
                    local name = C_Item.GetItemInfo(itemID)
                    if name then
                        if not RecipeBook.recipeNames[profID] then
                            RecipeBook.recipeNames[profID] = {}
                        end
                        RecipeBook.recipeNames[profID][itemID] = StripRecipePrefix(name)
                    end
                end
            end
            if RecipeBook.itemNames[itemID] == nil then
                local name = C_Item.GetItemInfo(itemID)
                if name then
                    RecipeBook.itemNames[itemID] = name
                end
            end
            if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
                RecipeBook:RefreshRecipeList()
            end
        end
    end
end)

-- Slash commands
SLASH_RECIPEBOOK1 = "/recipebook"
SLASH_RECIPEBOOK2 = "/rb"
SlashCmdList["RECIPEBOOK"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "phase" or msg:match("^phase%s") then
        local phase = tonumber(msg:match("^phase%s+(%d+)"))
        if phase and phase >= 1 and phase <= 5 then
            RecipeBookDB.currentPhase = phase
            RecipeBook:Print("Current phase set to " .. phase)
            if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
                RecipeBook:RefreshRecipeList()
            end
        else
            RecipeBook:Print("Usage: /rb phase <1-5> (current: " .. (RecipeBookDB.currentPhase or 1) .. ")")
        end
    elseif msg == "wipeknown" then
        RecipeBookCharDB.knownProfessions = {}
        RecipeBookCharDB.knownRecipes = {}
        RecipeBook:Print("Known-recipe cache wiped.")
        StaticPopup_Show("RECIPEBOOK_RESCAN_PROFESSIONS")
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    elseif msg == "reset" then
        RecipeBookCharDB.windowPos = nil
        if RecipeBook.mainFrame then
            RecipeBook.mainFrame:ClearAllPoints()
            RecipeBook.mainFrame:SetPoint("CENTER")
        end
        RecipeBook:Print("Window position reset.")
    else
        RecipeBook:Toggle()
    end
end

-- Release UI-specific state when the main window is closed.
-- Recipe name/icon caches and map lookups are session-stable (built once
-- at login) and kept across open/close cycles to avoid a costly rebuild.
function RecipeBook:OnClose()
    -- UI row frames and render caches (cheap to rebuild on next open)
    self:ClearRenderCaches()
    self:CleanupSourcesPopup()
    self:ClearTeachesCache()
    wipe(self.framePool)
end

function RecipeBook:Toggle()
    if not self.mainFrame then
        self:CreateMainFrame()
        self.mainFrame:HookScript("OnHide", function() self:OnClose() end)
    end
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
        self:RefreshRecipeList()
    end
end
