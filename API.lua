-- RecipeBook.API — public consumer API for other addons.
--
-- Stable, read-only surface intended for third-party addons (e.g. MouthPiece)
-- that want to query RecipeBook's catalog and known-recipe data instead of
-- scanning professions themselves.
--
-- Consumers soft-probe with:
--     local function HasRecipeBook()
--         return _G.RecipeBook
--            and _G.RecipeBook.API
--            and (_G.RecipeBook.API.VERSION or 0) >= 1
--     end
--
-- Contract (v1):
--   * Pull-only. No callbacks, no writes, no side effects.
--   * Returns copies — consumers may not mutate RB's internal state.
--   * Nil-safe — unknown profession / charKey / recipe returns {} or nil.
--   * Locale-stable spellID is the primary key.
--   * Safe to call after PLAYER_LOGIN. Calling earlier may return empty.

RecipeBook = RecipeBook or {}
RecipeBook.API = RecipeBook.API or {}
-- VERSION history:
--   1 — original (GetAllProfessions, GetAllRecipes, GetKnownRecipes,
--       GetKnownProfessions, GetRecipe, GetCharacters, IsProfessionScanned).
--   2 — add Guild Crafts surface (GetGuilds, GetGuildCrafters).
RecipeBook.API.VERSION = 2

local API = RecipeBook.API

-- Lazy-built internal indexes (nil until first API call)
local profNameToID = nil
local spellToRef = nil

local function buildIndexes()
    profNameToID = {}
    for _, prof in ipairs(RecipeBook.PROFESSIONS or {}) do
        profNameToID[prof.name] = prof.id
    end

    spellToRef = {}
    for profID, recipes in pairs(RecipeBook.recipeDB or {}) do
        for recipeID, data in pairs(recipes) do
            local teaches = data.teaches
            -- Skip rank-up entries (string teaches) and dual-faction
            -- duplicates (first-write-wins — same spell, same name).
            if type(teaches) == "number" and not spellToRef[teaches] then
                spellToRef[teaches] = { profID = profID, recipeID = recipeID }
            end
        end
    end
end

local function ensureIndexes()
    if not profNameToID or not spellToRef then
        buildIndexes()
    end
end

-- Construct a fresh RecipeRef for consumers. Returns nil for entries with
-- non-numeric `teaches` (rank-up placeholders).
local function buildRef(profID, recipeID)
    local recipes = RecipeBook.recipeDB and RecipeBook.recipeDB[profID]
    local data = recipes and recipes[recipeID]
    if not data then return nil end

    local teaches = data.teaches
    if type(teaches) ~= "number" then return nil end

    local profName = RecipeBook.PROFESSION_NAMES and RecipeBook.PROFESSION_NAMES[profID]
    local isSpell = data.isSpell == true or recipeID == teaches
    local itemID = (not isSpell) and recipeID or nil
    local name = data.name or ""

    -- Spell hyperlink — stable across item vs spell recipes since MP
    -- displays the resulting craft, not the scroll/schematic.
    local link = string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", teaches, name)

    return {
        spellID    = teaches,
        recipeID   = recipeID,
        itemID     = itemID,
        name       = data.name,
        profession = profName,
        link       = link,
        icon       = data.icon,
    }
end

local function resolveCharKey(charKey)
    if charKey then return charKey end
    if RecipeBook.GetMyCharKey then return RecipeBook:GetMyCharKey() end
    return nil
end

-- ============================================================
-- Core queries
-- ============================================================

-- Every profession RB knows recipes for, alphabetised.
-- @return array of strings
function API:GetAllProfessions()
    local list = {}
    for _, prof in ipairs(RecipeBook.PROFESSIONS or {}) do
        list[#list + 1] = prof.name
    end
    table.sort(list)
    return list
end

-- Every recipe RB knows about for a profession, regardless of whether any
-- character has learned it.
-- @param profession string — profession name (matches GetAllProfessions)
-- @return array of RecipeRef (empty on unknown profession)
function API:GetAllRecipes(profession)
    ensureIndexes()
    local profID = profession and profNameToID[profession]
    if not profID then return {} end
    local recipes = RecipeBook.recipeDB and RecipeBook.recipeDB[profID]
    if not recipes then return {} end
    local list = {}
    for recipeID in pairs(recipes) do
        local ref = buildRef(profID, recipeID)
        if ref then list[#list + 1] = ref end
    end
    return list
end

-- Recipes the given character has learned for a profession.
-- @param charKey string|nil — "Name-Realm", nil = current character
-- @param profession string
-- @return array of RecipeRef (empty on unknown char/profession)
function API:GetKnownRecipes(charKey, profession)
    charKey = resolveCharKey(charKey)
    if not charKey or not RecipeBookDB or not RecipeBookDB.characters then return {} end
    local entry = RecipeBookDB.characters[charKey]
    if not entry or not entry.knownRecipes then return {} end

    ensureIndexes()
    local profID = profession and profNameToID[profession]
    if not profID then return {} end
    local known = entry.knownRecipes[profID]
    if not known then return {} end

    local list = {}
    for recipeID, v in pairs(known) do
        if v then
            local ref = buildRef(profID, recipeID)
            if ref then list[#list + 1] = ref end
        end
    end
    return list
end

-- Professions the given character has trained.
-- @param charKey string|nil — nil = current character
-- @return array of profession name strings (alphabetised)
function API:GetKnownProfessions(charKey)
    charKey = resolveCharKey(charKey)
    if not charKey or not RecipeBookDB or not RecipeBookDB.characters then return {} end
    local entry = RecipeBookDB.characters[charKey]
    if not entry or not entry.knownProfessions then return {} end
    local list = {}
    for profID, v in pairs(entry.knownProfessions) do
        if v then
            local name = RecipeBook.PROFESSION_NAMES and RecipeBook.PROFESSION_NAMES[profID]
            if name then list[#list + 1] = name end
        end
    end
    table.sort(list)
    return list
end

-- Point lookup by spell ID. Primary key for consumers persisting selections.
-- @param spellID number
-- @return RecipeRef | nil
function API:GetRecipe(spellID)
    if type(spellID) ~= "number" then return nil end
    ensureIndexes()
    local entry = spellToRef[spellID]
    if not entry then return nil end
    return buildRef(entry.profID, entry.recipeID)
end

-- ============================================================
-- Optional queries
-- ============================================================

-- All characters RB has data for. Order unspecified.
-- @return array of charKey strings
function API:GetCharacters()
    if RecipeBook.GetAllCharKeys then return RecipeBook:GetAllCharKeys() end
    return {}
end

-- Has RB received at least one full scan of this profession for this char?
-- Distinguishes "window not yet opened" from "0 recipes selected".
-- @param charKey string|nil
-- @param profession string
-- @return bool
-- All guilds RB has data for. Order unspecified.
-- @return array of guild-key strings ("GuildName-Realm")
function API:GetGuilds()
    if RecipeBook.GetAllGuildKeys then return RecipeBook:GetAllGuildKeys() end
    return {}
end

-- List guild crafters for a recipe (who in the guild has it learned).
-- @param guildKey string|nil  -- "GuildName-Realm", nil = current guild
-- @param spellID  number
-- @return array of { charKey, name, class, online, zone }. Empty on miss.
function API:GetGuildCrafters(guildKey, spellID)
    if type(spellID) ~= "number" then return {} end
    ensureIndexes()
    local entry = spellToRef[spellID]
    if not entry then return {} end

    if guildKey == nil and RecipeBook.GuildComm and RecipeBook.GuildComm.CurrentGuildKey then
        guildKey = RecipeBook.GuildComm.CurrentGuildKey()
    end
    if not guildKey then return {} end

    local guild = RecipeBookDB and RecipeBookDB.guilds and RecipeBookDB.guilds[guildKey]
    if not guild or not guild.members then return {} end

    local out = {}
    for charKey, member in pairs(guild.members) do
        local prof = member.professions and member.professions[entry.profID]
        if prof and prof.recipes then
            -- Lazy build (shared with UI render)
            if not prof._has then
                local has = {}
                for i = 1, #prof.recipes do has[prof.recipes[i]] = true end
                prof._has = has
            end
            if prof._has[entry.recipeID] then
                local rosterInfo = RecipeBook.GuildRoster and RecipeBook.GuildRoster:Get(member.name or charKey)
                out[#out + 1] = {
                    charKey = charKey,
                    name = member.name or charKey,
                    class = (rosterInfo and rosterInfo.class) or member.class,
                    online = rosterInfo and rosterInfo.online or false,
                    zone = rosterInfo and rosterInfo.zone,
                }
            end
        end
    end
    return out
end

function API:IsProfessionScanned(charKey, profession)
    charKey = resolveCharKey(charKey)
    if not charKey or not RecipeBookDB or not RecipeBookDB.characters then return false end
    local entry = RecipeBookDB.characters[charKey]
    if not entry or not entry.knownProfessions then return false end
    ensureIndexes()
    local profID = profession and profNameToID[profession]
    if not profID then return false end
    return entry.knownProfessions[profID] == true
end
