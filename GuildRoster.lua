-- GuildRoster.lua — thin wrapper over the WoW guild roster API.
--
-- Provides name -> { online, zone, class, level } for fast lookup during
-- crafter-cell rendering. Refreshed on GUILD_ROSTER_UPDATE (debounced
-- via C_Timer) and on explicit invalidation.

RecipeBook = RecipeBook or {}
RecipeBook.GuildRoster = RecipeBook.GuildRoster or {}

local GR = RecipeBook.GuildRoster

GR._byName = GR._byName or {}
GR._refreshPending = false

-- Request an up-to-date roster from the server, then refresh our cache.
-- GuildRoster() throttles internally; safe to call frequently.
function GR:Request()
    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then
        _G.C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
        _G.GuildRoster()
    end
end

-- Rebuild from GetGuildRosterInfo.
function GR:Rebuild()
    local out = {}
    if not _G.GetNumGuildMembers then
        self._byName = out
        return
    end
    local n = _G.GetNumGuildMembers() or 0
    for i = 1, n do
        -- GetGuildRosterInfo signature:
        -- name, rankName, rankIndex, level, class, zone, note,
        -- officernote, online, status, classFileName
        local name, _, _, level, _, zone, _, _, online, _, classFile = _G.GetGuildRosterInfo(i)
        if name then
            local bare = name:match("^([^-]+)") or name
            out[name:lower()] = { online = online and true or false, zone = zone, class = classFile, level = level }
            out[bare:lower()] = out[name:lower()]
        end
    end
    self._byName = out
end

-- Lookup by char name (with or without realm suffix).
-- @param name string  -- "Name" or "Name-Realm"
-- @return { online, zone, class, level } or nil
function GR:Get(name)
    if type(name) ~= "string" or name == "" then return nil end
    local k = name:lower()
    return self._byName[k]
end

-- Debounced refresh (safe to call from event handlers that fire in bursts).
function GR:ScheduleRefresh()
    if self._refreshPending then return end
    self._refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            GR._refreshPending = false
            GR:Rebuild()
        end)
    else
        self._refreshPending = false
        self:Rebuild()
    end
end
