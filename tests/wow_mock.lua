-- WoW API Mock Layer for RecipeBook Tests
-- Provides stubs for WoW globals, API functions, and UI widgets.
-- Call MockWoW.reset() between tests to restore clean state.

MockWoW = MockWoW or {}

-- ============================================================
-- CONFIGURABLE STATE
-- ============================================================

MockWoW._playerName = "TestChar"
MockWoW._playerRealm = "TestRealm"
MockWoW._playerClass = "WARRIOR"
MockWoW._playerClassDisplay = "Warrior"
MockWoW._playerLevel = 70
MockWoW._playerFaction = "Alliance"
MockWoW._currentZone = "Shattrath City"
MockWoW._currentMapID = 1955

-- Area ID -> zone name (populated by tests)
MockWoW._areaNames = {}

-- Map info: [mapID] = { name, mapType, parentMapID }
MockWoW._mapData = {}

-- ============================================================
-- RESET
-- ============================================================

function MockWoW.reset()
    MockWoW._playerName = "TestChar"
    MockWoW._playerRealm = "TestRealm"
    MockWoW._playerClass = "WARRIOR"
    MockWoW._playerClassDisplay = "Warrior"
    MockWoW._playerLevel = 70
    MockWoW._playerFaction = "Alliance"
    MockWoW._currentZone = "Shattrath City"
    MockWoW._currentMapID = 1955
    MockWoW._areaNames = {}
    MockWoW._mapData = {}
    MockWoW._factionStandings = {}
    MockWoW._profSkill = 0

    -- Reset addon globals
    RecipeBook = nil
    RecipeBookDB = nil
    RecipeBookCharDB = nil

    -- Reset UI stub globals
    StaticPopupDialogs = {}
    SlashCmdList = SlashCmdList or {}
    SLASH_RECIPEBOOK1 = nil
    SLASH_RECIPEBOOK2 = nil

    -- Reload addon source files
    MockWoW._loadAddonFiles()
end

-- ============================================================
-- LUA 5.4 COMPAT: globals that WoW's embedded Lua provides
-- ============================================================

strmatch = strmatch or string.match
strfind  = strfind  or string.find
strsub   = strsub   or string.sub
strlower = strlower or string.lower
strupper = strupper or string.upper
strlen   = strlen   or string.len
strtrim  = strtrim  or function(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end
strsplit = strsplit or function(delimiter, str, max)
    if not str then return nil end
    local parts = {}
    local pattern = "(.-)" .. delimiter
    local last_end = 1
    local s, e, cap = str:find(pattern, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            parts[#parts + 1] = cap
        end
        last_end = e + 1
        if max and #parts >= max - 1 then break end
        s, e, cap = str:find(pattern, last_end)
    end
    parts[#parts + 1] = str:sub(last_end)
    return table.unpack(parts)
end

format  = format  or string.format
tinsert = tinsert or table.insert
tremove = tremove or table.remove

function wipe(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
    return t
end

-- ============================================================
-- WOW API STUBS
-- ============================================================

function UnitName(unit)
    if unit == "player" then return MockWoW._playerName, nil end
    return nil
end

function GetRealmName()
    return MockWoW._playerRealm
end

function UnitClass(unit)
    if unit == "player" then
        return MockWoW._playerClassDisplay, MockWoW._playerClass
    end
    return nil
end

function UnitLevel(unit)
    if unit == "player" then return MockWoW._playerLevel end
    return 0
end

function UnitFactionGroup(unit)
    if unit == "player" then return MockWoW._playerFaction end
    return nil
end

function GetRealZoneText()
    return MockWoW._currentZone
end

function GetSpellInfo(spellID)
    return nil
end

function GetItemInfo(itemID)
    return nil
end

function GetFactionInfoByID(factionID)
    local standing = MockWoW._factionStandings and MockWoW._factionStandings[factionID]
    if not standing then return nil end
    return "Faction", nil, standing
end

function GetCraftDisplaySkillLine()
    return "Enchanting", MockWoW._profSkill or 0
end

function IsAddOnLoaded(name)
    return false
end

C_AddOns = C_AddOns or {}
function C_AddOns.IsAddOnLoaded(name) return false end

C_Item = C_Item or {}
function C_Item.RequestLoadItemDataByID(itemID) end
function C_Item.GetItemInfo(itemID) return nil end

-- ============================================================
-- Addon-message + channel + guild-roster mocks (for GuildSync tests)
-- ============================================================
-- MockWoW._addonMessages captures everything sent via SendAddonMessage
-- so tests can inspect the wire. MockWoW.SetGuildRoster() seeds the
-- roster for isInCurrentGuild() lookups.
MockWoW._addonMessages = MockWoW._addonMessages or {}
MockWoW._channels = MockWoW._channels or {}
MockWoW._guildName = nil
MockWoW._guildRealm = ""
MockWoW._guildRoster = {}     -- array of { name, class, level, zone, online }
MockWoW._registeredAddonPrefixes = MockWoW._registeredAddonPrefixes or {}

function MockWoW.ClearAddonMessages()
    MockWoW._addonMessages = {}
end

function MockWoW.SetGuild(name, realm)
    MockWoW._guildName = name
    MockWoW._guildRealm = realm or MockWoW._playerRealm
end

function MockWoW.SetGuildRoster(list) MockWoW._guildRoster = list or {} end

function GetGuildInfo(unit)
    if not MockWoW._guildName then return nil end
    return MockWoW._guildName, "Rank", 0, MockWoW._guildRealm
end

function IsInGuild() return MockWoW._guildName ~= nil end

function GetNumGuildMembers() return #MockWoW._guildRoster end

function GetGuildRosterInfo(i)
    local r = MockWoW._guildRoster[i]
    if not r then return nil end
    -- name, rankName, rankIndex, level, class, zone, note, officernote, online, status, classFileName
    return r.name, "Rank", 0, r.level or 60, r.classDisplay or r.class or "Warrior",
        r.zone or "Ironforge", "", "", r.online and true or false, 0, r.class or "WARRIOR"
end

function JoinTemporaryChannel(name)
    if not MockWoW._channels[name] then
        MockWoW._channels[name] = #MockWoW._channels + 1
        table.insert(MockWoW._channels, name)
    end
    for i, n in ipairs(MockWoW._channels) do
        if n == name then return i end
    end
    return nil
end

function LeaveChannelByName(name)
    for i, n in ipairs(MockWoW._channels) do
        if n == name then
            table.remove(MockWoW._channels, i)
            MockWoW._channels[name] = nil
            return true
        end
    end
end

function GetChannelName(name)
    for i, n in ipairs(MockWoW._channels) do
        if n == name then return i end
    end
    return 0
end

C_ChatInfo = C_ChatInfo or {}
function C_ChatInfo.RegisterAddonMessagePrefix(p)
    MockWoW._registeredAddonPrefixes[p] = true
end
function C_ChatInfo.SendAddonMessage(prefix, text, scope, target)
    table.insert(MockWoW._addonMessages, {
        prefix = prefix, text = text, scope = scope, target = target,
    })
end

C_GuildInfo = C_GuildInfo or {}
function C_GuildInfo.GuildRoster() end

-- ChatThrottleLib stub: bypass the throttle and record priority for tests.
ChatThrottleLib = ChatThrottleLib or {}
function ChatThrottleLib:SendAddonMessage(priority, prefix, text, scope, target)
    table.insert(MockWoW._addonMessages, {
        prefix = prefix, text = text, scope = scope, target = target, priority = priority,
    })
end

-- C_Map stubs
C_Map = C_Map or {}

function C_Map.GetAreaInfo(areaID)
    return MockWoW._areaNames[areaID]
end

function C_Map.GetMapInfo(mapID)
    return MockWoW._mapData[mapID]
end

function C_Map.GetBestMapForUnit(unit)
    if unit == "player" then return MockWoW._currentMapID end
    return nil
end

function C_Map.GetPlayerMapPosition(mapID, unit)
    return { GetXY = function() return 0.5, 0.5 end }
end

-- C_Timer stub
C_Timer = C_Timer or {}
function C_Timer.After(delay, fn) end

-- GetTime stub
GetTime = GetTime or function() return 0 end
if not rawget(_G, "time") then time = os.time end

-- ============================================================
-- WOW UI STUBS
-- ============================================================

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}

WorldFrame = WorldFrame or {}

-- Enum stubs
Enum = Enum or {}
Enum.UIMapType = Enum.UIMapType or { Zone = 3, Continent = 2 }

-- Frame stub: metatable returns no-op for unknown methods
local FrameMethods = {}
FrameMethods.__index = function(t, k)
    local v = rawget(FrameMethods, k)
    if v then return v end
    return function() end
end
function FrameMethods:RegisterEvent() end
function FrameMethods:UnregisterEvent() end
function FrameMethods:SetScript() end
function FrameMethods:HookScript() end
function FrameMethods:Show() end
function FrameMethods:Hide() end
function FrameMethods:IsShown() return false end
function FrameMethods:SetPoint() end
function FrameMethods:ClearAllPoints() end
function FrameMethods:SetSize() end
function FrameMethods:SetWidth() end
function FrameMethods:SetHeight() end
function FrameMethods:GetWidth() return 400 end
function FrameMethods:GetHeight() return 300 end
function FrameMethods:CreateTexture() return setmetatable({}, FrameMethods) end
function FrameMethods:CreateFontString() return setmetatable({}, FrameMethods) end
function FrameMethods:SetTexture() end
function FrameMethods:SetText() end
function FrameMethods:SetFont() end
function FrameMethods:SetBackdrop() end
function FrameMethods:SetBackdropColor() end
function FrameMethods:SetBackdropBorderColor() end
function FrameMethods:SetAllPoints() end
function FrameMethods:GetParent() return nil end
function FrameMethods:SetParent() end
function FrameMethods:IsForbidden() return false end
function FrameMethods:GetItem() return nil, nil end
function FrameMethods:AddLine() end
function FrameMethods:AddDoubleLine() end
function FrameMethods:NumLines() return 0 end
function FrameMethods:ClearLines() end
function FrameMethods:SetHyperlink() end
function FrameMethods:GetText() return nil end
function FrameMethods:RegisterForClicks() end
function FrameMethods:RegisterForDrag() end
function FrameMethods:EnableMouse() end
function FrameMethods:SetMovable() end
function FrameMethods:SetClampedToScreen() end
function FrameMethods:SetToplevel() end
function FrameMethods:SetFrameStrata() end
function FrameMethods:Raise() end
function FrameMethods:SetColorTexture() end
function FrameMethods:SetVertexColor() end
function FrameMethods:SetRotation() end
function FrameMethods:SetScrollChild() end
function FrameMethods:SetPropagateKeyboardInput() end
function FrameMethods:SetJustifyH() end
function FrameMethods:SetWordWrap() end
function FrameMethods:SetNonSpaceWrap() end
function FrameMethods:SetTextColor() end
function FrameMethods:StartMoving() end
function FrameMethods:StopMovingOrSizing() end

function CreateFrame(frameType, name, parent, template)
    local f = setmetatable({}, FrameMethods)
    if name then
        _G[name] = f
        -- UICheckButtonTemplate creates a companion "nameText" FontString
        if template and template:find("CheckButton") then
            _G[name .. "Text"] = setmetatable({}, FrameMethods)
        end
        -- OptionsSliderTemplate creates Low/High labels
        if template and template:find("Slider") then
            _G[name .. "Low"] = setmetatable({}, FrameMethods)
            _G[name .. "High"] = setmetatable({}, FrameMethods)
        end
    end
    return f
end

function CreateFont(name)
    local f = setmetatable({}, FrameMethods)
    if name then _G[name] = f end
    return f
end

function hooksecurefunc(name, fn) end

-- LibStub stub
LibStub = function(name, silent)
    if name == "LibDataBroker-1.1" then
        return { NewDataObject = function(self, objName, obj) return obj end }
    end
    if name == "LibDBIcon-1.0" then
        return { Register = function() end }
    end
    return nil
end

StaticPopupDialogs = StaticPopupDialogs or {}
function StaticPopup_Show() end
Settings = nil
DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or { AddMessage = function() end }
GameTooltip = GameTooltip or setmetatable({}, { __index = function() return function() end end })
UISpecialFrames = UISpecialFrames or {}
SlashCmdList = SlashCmdList or {}

-- UIDropDownMenu stubs
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_Initialize() end
function ToggleDropDownMenu() end
function ChatEdit_InsertLink() end
function IsShiftKeyDown() return false end

-- ============================================================
-- HELPER: set mock state
-- ============================================================

function MockWoW.SetFaction(faction)
    MockWoW._playerFaction = faction
end

function MockWoW.SetAreaName(areaID, name)
    MockWoW._areaNames[areaID] = name
end

function MockWoW.SetFactionStanding(factionID, standingID)
    MockWoW._factionStandings[factionID] = standingID
end

function MockWoW.SetProfessionSkill(profID, skill)
    if not RecipeBookCharDB then RecipeBookCharDB = {} end
    if not RecipeBookCharDB.professionSkill then RecipeBookCharDB.professionSkill = {} end
    RecipeBookCharDB.professionSkill[profID] = skill
end

function MockWoW.SetMapData(mapID, name, mapType, parentMapID)
    MockWoW._mapData[mapID] = {
        name = name,
        mapType = mapType or Enum.UIMapType.Zone,
        parentMapID = parentMapID,
        mapID = mapID,
    }
end

-- ============================================================
-- LOAD ADDON SOURCE FILES
-- ============================================================

function MockWoW._loadAddonFiles()
    -- Data files (pure table assignments, safe to load)
    dofile("Data/Recipes/Alchemy.lua")
    dofile("Data/Recipes/Blacksmithing.lua")
    dofile("Data/Recipes/Cooking.lua")
    dofile("Data/Recipes/Enchanting.lua")
    dofile("Data/Recipes/Engineering.lua")
    dofile("Data/Recipes/Firstaid.lua")
    dofile("Data/Recipes/Fishing.lua")
    dofile("Data/Recipes/Jewelcrafting.lua")
    dofile("Data/Recipes/Leatherworking.lua")
    dofile("Data/Recipes/Mining.lua")
    dofile("Data/Recipes/Poisons.lua")
    dofile("Data/Recipes/Tailoring.lua")

    dofile("Data/Sources/Alchemy.lua")
    dofile("Data/Sources/Blacksmithing.lua")
    dofile("Data/Sources/Cooking.lua")
    dofile("Data/Sources/Enchanting.lua")
    dofile("Data/Sources/Engineering.lua")
    dofile("Data/Sources/Firstaid.lua")
    dofile("Data/Sources/Fishing.lua")
    dofile("Data/Sources/Jewelcrafting.lua")
    dofile("Data/Sources/Leatherworking.lua")
    dofile("Data/Sources/Mining.lua")
    dofile("Data/Sources/Poisons.lua")
    dofile("Data/Sources/Tailoring.lua")

    dofile("Data/NPCs.lua")
    dofile("Data/Objects.lua")
    dofile("Data/Quests.lua")
    dofile("Data/Unique.lua")

    -- Logic files
    dofile("MapResolver.lua")
    dofile("RecipeTracker.lua")
    dofile("GuildSync.lua")
    dofile("GuildComm.lua")
    dofile("GuildRoster.lua")
    dofile("Core.lua")
    dofile("API.lua")
    dofile("UIControls.lua")
    dofile("UIRender.lua")
    dofile("UIDropSources.lua")
end

-- Initial load
MockWoW._loadAddonFiles()
