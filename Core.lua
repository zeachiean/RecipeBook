RecipeBook = RecipeBook or {}

RecipeBook.VERSION = "1.2.1"
RecipeBook.RELEASE_DATE = "April 6, 2026"
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

-- Item name cache (for "item" source type)
RecipeBook.itemNames = {}

-- Active waypoint tracking
RecipeBook.activeWaypoint = nil    -- { npcName, zoneName }

-- Pre-cache recipe item data so tooltips (SetItemByID) work immediately.
-- Only requests non-isSpell recipe items (physical recipe items).
-- isSpell recipes use spell: hyperlink tooltips instead.
-- Batches requests to avoid flooding the client on login.
function RecipeBook:PrecacheRecipeItems()
    if not C_Item or not C_Item.RequestLoadItemDataByID then return end

    local queue = {}
    for profID, recipes in pairs(self.recipeDB) do
        for recipeID, data in pairs(recipes) do
            if not data.isSpell then
                queue[#queue + 1] = recipeID
            end
        end
    end

    local BATCH_SIZE = 50
    local i = 1
    local function ProcessBatch()
        local limit = math.min(i + BATCH_SIZE - 1, #queue)
        for j = i, limit do
            C_Item.RequestLoadItemDataByID(queue[j])
        end
        i = limit + 1
        if i <= #queue then
            C_Timer.After(0.1, ProcessBatch)
        end
    end
    ProcessBatch()
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

-- Get display name for a recipe
function RecipeBook:GetRecipeName(profID, recipeID)
    local data = self.recipeDB[profID] and self.recipeDB[profID][recipeID]
    if not data then return "Unknown Recipe" end
    return data.name or "Unknown Recipe"
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

-- Build the stable character key for a name + realm
function RecipeBook:BuildCharKey(name, realm)
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

-- Current character's key
function RecipeBook:GetMyCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return self:BuildCharKey(name, realm)
end

-- Ensure a character entry exists in the global store, return it
function RecipeBook:GetOrCreateCharData(charKey, name, realm)
    if not RecipeBookDB.characters then RecipeBookDB.characters = {} end
    local entry = RecipeBookDB.characters[charKey]
    if not entry then
        entry = {
            name = name,
            realm = realm,
            knownProfessions = {},
            knownRecipes = {},
            wishlist = {},
            ignored = {},
        }
        RecipeBookDB.characters[charKey] = entry
    end
    -- Ensure sub-tables (forward compat)
    entry.knownProfessions = entry.knownProfessions or {}
    entry.knownRecipes = entry.knownRecipes or {}
    entry.wishlist = entry.wishlist or {}
    entry.ignored = entry.ignored or {}
    return entry
end

-- Current character's data entry
function RecipeBook:GetMyCharData()
    local key = self:GetMyCharKey()
    if not key then return nil end
    return self:GetOrCreateCharData(key, UnitName("player"), GetRealmName())
end

-- Currently viewed character (defaults to me)
function RecipeBook:GetViewedCharKey()
    if RecipeBookCharDB and RecipeBookCharDB.viewingChar then
        local key = RecipeBookCharDB.viewingChar
        if RecipeBookDB.characters and RecipeBookDB.characters[key] then
            return key
        end
    end
    return self:GetMyCharKey()
end

function RecipeBook:SetViewedCharKey(key)
    if not RecipeBookCharDB then return end
    if key == self:GetMyCharKey() then
        RecipeBookCharDB.viewingChar = nil
    else
        RecipeBookCharDB.viewingChar = key
    end
end

function RecipeBook:GetViewedCharData()
    local key = self:GetViewedCharKey()
    if not key or not RecipeBookDB.characters then return nil end
    return RecipeBookDB.characters[key]
end

-- Sorted list of all character keys in the store
function RecipeBook:GetAllCharKeys()
    local list = {}
    if not RecipeBookDB.characters then return list end
    for key in pairs(RecipeBookDB.characters) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

-- Check if a profession is known by the viewed (or specified) character
function RecipeBook:IsProfessionKnown(profID, charKey)
    charKey = charKey or self:GetViewedCharKey()
    if not charKey or not RecipeBookDB.characters then return false end
    local entry = RecipeBookDB.characters[charKey]
    if not entry or not entry.knownProfessions then return false end
    return entry.knownProfessions[profID] == true
end

-- Wishlist / ignored helpers (operate on viewed char unless charKey given)
local function getCharFlagTable(self, bucket, profID, charKey, create)
    charKey = charKey or self:GetViewedCharKey()
    if not charKey or not RecipeBookDB.characters then return nil end
    local entry = RecipeBookDB.characters[charKey]
    if not entry then return nil end
    entry[bucket] = entry[bucket] or {}
    local t = entry[bucket][profID]
    if not t and create then
        t = {}
        entry[bucket][profID] = t
    end
    return t
end

function RecipeBook:IsRecipeInWishlist(profID, recipeID, charKey)
    local t = getCharFlagTable(self, "wishlist", profID, charKey, false)
    return t and t[recipeID] == true or false
end

function RecipeBook:IsRecipeIgnored(profID, recipeID, charKey)
    local t = getCharFlagTable(self, "ignored", profID, charKey, false)
    return t and t[recipeID] == true or false
end

function RecipeBook:SetRecipeWishlist(profID, recipeID, value, charKey)
    local t = getCharFlagTable(self, "wishlist", profID, charKey, value and true or false)
    if not t then return end
    t[recipeID] = value and true or nil
end

function RecipeBook:SetRecipeIgnored(profID, recipeID, value, charKey)
    local t = getCharFlagTable(self, "ignored", profID, charKey, value and true or false)
    if not t then return end
    t[recipeID] = value and true or nil
end

function RecipeBook:ToggleRecipeWishlist(profID, recipeID, charKey)
    local cur = self:IsRecipeInWishlist(profID, recipeID, charKey)
    if not cur then
        self:SetRecipeIgnored(profID, recipeID, false, charKey)
    end
    self:SetRecipeWishlist(profID, recipeID, not cur, charKey)
end

function RecipeBook:ToggleRecipeIgnored(profID, recipeID, charKey)
    local cur = self:IsRecipeIgnored(profID, recipeID, charKey)
    if not cur then
        self:SetRecipeWishlist(profID, recipeID, false, charKey)
    end
    self:SetRecipeIgnored(profID, recipeID, not cur, charKey)
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

StaticPopupDialogs["RECIPEBOOK_SKILL_RESCAN"] = {
    text = "RecipeBook: Profession skill levels are missing.\n\nPlease open each of your profession windows once so RecipeBook can detect your skill levels.",
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
    if not RecipeBookDB.characters then
        RecipeBookDB.characters = {}
    end

    if not RecipeBookCharDB then
        RecipeBookCharDB = {}
    end
    if not RecipeBookCharDB.professionSkill then
        RecipeBookCharDB.professionSkill = {}
    end
    if RecipeBookCharDB.hideKnown == nil then
        RecipeBookCharDB.hideKnown = false
    end
    if RecipeBookCharDB.hideUnlearnable == nil then
        RecipeBookCharDB.hideUnlearnable = false
    end
    if not RecipeBookCharDB.collapsedSources then
        RecipeBookCharDB.collapsedSources = {}
    end

    -- Ensure current character has an entry in the global store
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myKey = RecipeBook:BuildCharKey(myName, myRealm)
    if myKey then
        local entry = RecipeBook:GetOrCreateCharData(myKey, myName, myRealm)
        -- Record faction/class metadata (cheap, refresh every login)
        local _, faction = UnitFactionGroup("player")
        entry.faction = faction
        local _, classFile = UnitClass("player")
        entry.class = classFile
        entry.lastSeen = time()

        -- One-time migration from per-character DB to global characters store
        if RecipeBookCharDB.knownRecipes and not RecipeBookCharDB.migratedToGlobal then
            for profID, recipes in pairs(RecipeBookCharDB.knownRecipes) do
                entry.knownRecipes[profID] = entry.knownRecipes[profID] or {}
                for recipeID, v in pairs(recipes) do
                    if v then entry.knownRecipes[profID][recipeID] = true end
                end
            end
            if RecipeBookCharDB.knownProfessions then
                for profID, v in pairs(RecipeBookCharDB.knownProfessions) do
                    if v then entry.knownProfessions[profID] = true end
                end
            end
            RecipeBookCharDB.knownRecipes = nil
            RecipeBookCharDB.knownProfessions = nil
            RecipeBookCharDB.profTrackingFixed = nil
            RecipeBookCharDB.migratedToGlobal = true
        end
    end
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
        InitSavedVars()
        -- Check if any known profession is missing a saved skill level
        local myData = RecipeBook:GetMyCharData()
        if myData and myData.knownProfessions then
            local missing = false
            for profID in pairs(myData.knownProfessions) do
                if not RecipeBookCharDB.professionSkill[profID] then
                    missing = true
                    break
                end
            end
            if missing then
                C_Timer.After(2, function()
                    StaticPopup_Show("RECIPEBOOK_SKILL_RESCAN")
                end)
            end
        end
        RecipeBook:BuildMapLookup()
        RecipeBook:BuildAreaToZoneLookup()
        RecipeBook:BuildContinentZoneMap()
        RecipeBook:PrecacheRecipeItems()
        RecipeBook:CacheItemSourceNames()
        RecipeBook:BuildItemToRecipeLookup()
        RecipeBook:HookTooltips()
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
            if RecipeBook.itemNames[itemID] == nil then
                local name = C_Item.GetItemInfo(itemID)
                if name then
                    RecipeBook.itemNames[itemID] = name
                end
            end
            -- Debounce: coalesce rapid-fire item loads into one refresh
            if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
                if not RecipeBook._refreshPending then
                    RecipeBook._refreshPending = true
                    C_Timer.After(0.2, function()
                        RecipeBook._refreshPending = nil
                        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
                            RecipeBook:RefreshRecipeList()
                        end
                    end)
                end
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
    elseif msg == "clearcache" then
        wipe(RecipeBook.itemNames)
        RecipeBook._refreshPending = nil
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:ClearRenderCaches()
            RecipeBook:CleanupSourcesPopup()
            RecipeBook:ClearTeachesCache()
            wipe(RecipeBook.framePool)
        end
        RecipeBook:PrecacheRecipeItems()
        RecipeBook:CacheItemSourceNames()
        RecipeBook:Print("Caches cleared.")
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    elseif msg == "clearall" then
        wipe(RecipeBook.itemNames)
        RecipeBook._refreshPending = nil
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:ClearRenderCaches()
            RecipeBook:CleanupSourcesPopup()
            RecipeBook:ClearTeachesCache()
            wipe(RecipeBook.framePool)
        end
        RecipeBookCharDB.professionSkill = {}
        local myData = RecipeBook:GetMyCharData()
        if myData then
            wipe(myData.knownProfessions)
            wipe(myData.knownRecipes)
        end
        RecipeBook:PrecacheRecipeItems()
        RecipeBook:CacheItemSourceNames()
        RecipeBook:Print("All caches and known-recipe data cleared.")
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

-- Reverse lookup: item ID -> list of {profID, recipeID}
-- Non-isSpell recipes: the recipeID IS the item ID.
RecipeBook.itemToRecipe = {}

function RecipeBook:BuildItemToRecipeLookup()
    wipe(self.itemToRecipe)
    for profID, recipes in pairs(self.recipeDB) do
        for recipeID, data in pairs(recipes) do
            if not data.isSpell then
                if not self.itemToRecipe[recipeID] then
                    self.itemToRecipe[recipeID] = {}
                end
                self.itemToRecipe[recipeID][#self.itemToRecipe[recipeID] + 1] = {
                    profID = profID, recipeID = recipeID,
                }
            end
        end
    end
end

-- Hook GameTooltip to show wishlist info on recipe items everywhere in the game.
function RecipeBook:HookTooltips()
    if self._tooltipsHooked then return end
    self._tooltipsHooked = true

    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()
        if not link then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID then return end

        local entries = self.itemToRecipe[itemID]
        if not entries then return end

        -- Check all characters' wishlists for any matching recipe
        local wishChars = {}
        local seen = {}
        for _, entry in ipairs(entries) do
            for _, key in ipairs(self:GetAllCharKeys()) do
                if not seen[key] and self:IsRecipeInWishlist(entry.profID, entry.recipeID, key) then
                    seen[key] = true
                    local charEntry = RecipeBookDB.characters and RecipeBookDB.characters[key]
                    wishChars[#wishChars + 1] = charEntry and charEntry.name or key
                end
            end
        end

        if #wishChars > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine("Wishlist: " .. table.concat(wishChars, ", "), 1, 0.84, 0)
            tooltip:Show()
        end
    end)
end
