-- GuildComm.lua — addon-message transport + handshake engine.
--
-- Pure-logic helpers are in GuildSync.lua. This file owns the WoW-facing
-- pieces: channel join, prefix registration, CHAT_MSG_ADDON dispatch,
-- and ChatThrottleLib-backed sending. The handshake state machine lives
-- here because it depends on the saved-vars schema and on calling back
-- into the owner's live knownRecipes data.

RecipeBook = RecipeBook or {}
RecipeBook.GuildComm = RecipeBook.GuildComm or {}

local GuildComm = RecipeBook.GuildComm
local GuildSync = RecipeBook.GuildSync

GuildComm.PREFIX         = "RB"
GuildComm.CHANNEL_NAME   = "RecipeBookSync"
GuildComm.HELLO_DEBOUNCE = 5       -- seconds
GuildComm.KEEPALIVE_SECS = 600     -- 10 min
GuildComm.MAX_GUILD_MEMBERS_PER_BROADCAST = 50

-- ============================================================
-- Rate-limited send via ChatThrottleLib (or direct fallback).
-- ============================================================

-- Priority tiers used: "NORMAL" for HELLO/NEED, "BULK" for DATA chunks.
local function rawSend(text, priority)
    priority = priority or "NORMAL"
    local ctl = _G.ChatThrottleLib
    local idx = GuildComm._channelIndex
    if not idx then return end
    if ctl and ctl.SendAddonMessage then
        ctl:SendAddonMessage(priority, GuildComm.PREFIX, text, "CHANNEL", idx)
    else
        local fn = (_G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
        if fn then fn(GuildComm.PREFIX, text, "CHANNEL", idx) end
    end
end

GuildComm._rawSend = rawSend  -- exposed for tests

-- ============================================================
-- Guild helpers
-- ============================================================

function GuildComm.CurrentGuildKey()
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" then return nil end
    realm = realm or GetRealmName() or ""
    if realm == "" then realm = GetRealmName() or "" end
    return name .. "-" .. realm, name, realm
end

local function isInCurrentGuild(senderName)
    if not senderName or senderName == "" then return false end
    local target = senderName:match("^([^-]+)") or senderName
    target = target:lower()
    if not GetNumGuildMembers then return false end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local nm = GetGuildRosterInfo(i)
        if nm then
            local bare = nm:match("^([^-]+)") or nm
            if bare:lower() == target then return true end
        end
    end
    return false
end

GuildComm._isInCurrentGuild = isInCurrentGuild

-- ============================================================
-- SavedVar accessors (thin wrappers, centralised for testability)
-- ============================================================

local function ensureGuildStore(guildKey, guildName, realm)
    if not RecipeBookDB then return nil end
    RecipeBookDB.guilds = RecipeBookDB.guilds or {}
    local g = RecipeBookDB.guilds[guildKey]
    if not g then
        g = { name = guildName or guildKey, realm = realm or "", members = {} }
        RecipeBookDB.guilds[guildKey] = g
    end
    g.members = g.members or {}
    return g
end

local function ensureMember(guild, charKey)
    guild.members[charKey] = guild.members[charKey] or {
        name = charKey:match("^([^-]+)") or charKey,
        realm = charKey:match("%-(.+)$") or "",
        professions = {},
    }
    local m = guild.members[charKey]
    m.professions = m.professions or {}
    return m
end

local function myHelloEntries()
    local entries = {}
    if not RecipeBookCharDB or not RecipeBookCharDB.guildSelfMeta then return entries end
    for profID, meta in pairs(RecipeBookCharDB.guildSelfMeta) do
        if meta and meta.dv and meta.hash then
            entries[profID] = { dv = meta.dv, hash = meta.hash }
        end
    end
    return entries
end

-- Gather *my* current recipe list for a given profession, fresh from
-- the authoritative char store.
local function myRecipesForProfession(profID)
    local myKey = RecipeBook:GetMyCharKey()
    local charData = RecipeBookDB and RecipeBookDB.characters and RecipeBookDB.characters[myKey]
    if not charData or not charData.knownRecipes or not charData.knownRecipes[profID] then
        return {}
    end
    local out = {}
    for id, v in pairs(charData.knownRecipes[profID]) do
        if v then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

GuildComm._myHelloEntries = myHelloEntries
GuildComm._myRecipesForProfession = myRecipesForProfession

-- Update dv/hash metadata for self after RecipeTracker detects a change.
-- Also mirrors the sorted recipe list into the guild store's self-entry.
function GuildComm.RefreshSelfMeta(profID)
    if not RecipeBookCharDB then return end
    RecipeBookCharDB.guildSelfMeta = RecipeBookCharDB.guildSelfMeta or {}
    local recipes = myRecipesForProfession(profID)
    local hash = GuildSync.HashRecipes(recipes)
    RecipeBookCharDB.guildSelfMeta[profID] = { dv = time(), hash = hash }

    -- Mirror into guild store (if we're in a guild)
    local guildKey = GuildComm.CurrentGuildKey()
    if guildKey then
        local myKey = RecipeBook:GetMyCharKey()
        local _, gName, realm = GuildComm.CurrentGuildKey()
        local guild = ensureGuildStore(guildKey, gName, realm)
        if guild and myKey then
            local member = ensureMember(guild, myKey)
            local _, faction = UnitFactionGroup("player")
            local _, classFile = UnitClass("player")
            member.class = classFile or member.class
            member.faction = faction or member.faction
            member.lastSeen = time()
            member.professions[profID] = {
                dv = RecipeBookCharDB.guildSelfMeta[profID].dv,
                hash = hash,
                recipes = recipes,
            }
            -- Drop any stale membership cache
            member._has = nil
        end
    end
end

-- Apply a received DATA record to the guild store.
function GuildComm.ApplyData(senderCharKey, profID, dv, recipes)
    local guildKey, gName, realm = GuildComm.CurrentGuildKey()
    if not guildKey then return end
    local guild = ensureGuildStore(guildKey, gName, realm)
    if not guild then return end
    local m = ensureMember(guild, senderCharKey)
    m.lastSeen = time()
    m.professions[profID] = { dv = dv, hash = GuildSync.HashRecipes(recipes), recipes = recipes }
    m._has = nil
end

-- ============================================================
-- Outbound — HELLO broadcast with debounce + sharing gate
-- ============================================================

GuildComm._helloPending = false

local function canBroadcast()
    if not RecipeBookDB or RecipeBookDB.guildSharingEnabled ~= true then return false end
    if not GuildComm._channelIndex then return false end
    if not GuildComm.CurrentGuildKey() then return false end
    return true
end

local function sendHelloNow()
    GuildComm._helloPending = false
    if not canBroadcast() then return end
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey then return end
    local entries = myHelloEntries()
    if next(entries) == nil then return end
    local msg = GuildSync.EncodeHello(myKey, entries)
    rawSend(msg, "NORMAL")
end

GuildComm._sendHelloNow = sendHelloNow

function GuildComm.BroadcastHello()
    if GuildComm._helloPending then return end
    GuildComm._helloPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(GuildComm.HELLO_DEBOUNCE, sendHelloNow)
    else
        sendHelloNow()
    end
end

function GuildComm.BroadcastHelloImmediate()
    GuildComm._helloPending = false
    sendHelloNow()
end

function GuildComm.BroadcastBye()
    if not GuildComm._channelIndex then return end
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey then return end
    rawSend(GuildSync.EncodeBye(myKey), "NORMAL")
end

-- ============================================================
-- Inbound — dispatch a decoded message
-- ============================================================

local function handleHello(record, senderCharKey)
    local guildKey, gName, realm = GuildComm.CurrentGuildKey()
    if not guildKey then return end
    local guild = ensureGuildStore(guildKey, gName, realm)
    local member = ensureMember(guild, record.charKey)
    member.lastSeen = time()

    for profID, claim in pairs(record.entries) do
        local ours = member.professions[profID]
        local action = GuildSync.DecideHelloAction(ours, claim.hash, claim.dv)
        if action == "need" then
            rawSend(GuildSync.EncodeNeed(record.charKey, profID), "NORMAL")
        elseif action == "conflict" then
            -- Log once per (charKey,profID) per session
            GuildComm._conflictLog = GuildComm._conflictLog or {}
            local k = record.charKey .. ":" .. profID
            if not GuildComm._conflictLog[k] then
                GuildComm._conflictLog[k] = true
            end
        end
    end
end

local function handleNeed(record)
    if not canBroadcast() then return end  -- privacy gate applies to DATA too
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey or record.targetCharKey ~= myKey then return end
    local meta = RecipeBookCharDB and RecipeBookCharDB.guildSelfMeta and RecipeBookCharDB.guildSelfMeta[record.profID]
    if not meta then return end
    local recipes = myRecipesForProfession(record.profID)
    local chunks = GuildSync.EncodeData(myKey, record.profID, meta.dv, recipes)
    for i = 1, #chunks do
        rawSend(chunks[i], "BULK")
    end
end

local function handleData(record)
    local done, recipes = GuildSync.IngestData(record)
    if not done then return end
    GuildComm.ApplyData(record.charKey, record.profID, record.dv, recipes)
end

local function handleBye(record)
    local guildKey = GuildComm.CurrentGuildKey()
    if not guildKey or not RecipeBookDB or not RecipeBookDB.guilds then return end
    local guild = RecipeBookDB.guilds[guildKey]
    if not guild or not guild.members then return end
    local m = guild.members[record.charKey]
    if m then m.lastSeen = time() end
end

-- Entry point for CHAT_MSG_ADDON dispatch.
-- senderCharKey should be the raw sender string from the event (already
-- "Name-Realm" on modern clients; we accept either).
function GuildComm.HandleMessage(msg, senderCharKey)
    if not msg then return end
    if not isInCurrentGuild(senderCharKey) then return end
    local record = GuildSync.Decode(msg)
    if not record then return end
    -- Ignore self-echoes
    local myKey = RecipeBook:GetMyCharKey()
    if myKey and record.charKey == myKey and record.type ~= "NEED" then return end
    if record.type == "HELLO" then
        handleHello(record, senderCharKey)
    elseif record.type == "NEED" then
        handleNeed(record)
    elseif record.type == "DATA" then
        handleData(record)
    elseif record.type == "BYE" then
        handleBye(record)
    end
end

GuildComm._handleHello = handleHello
GuildComm._handleNeed = handleNeed
GuildComm._handleData = handleData

-- ============================================================
-- Channel lifecycle
-- ============================================================

function GuildComm.JoinChannel()
    if not _G.JoinTemporaryChannel then return end
    -- JoinTemporaryChannel returns the channel index on success.
    local idx = _G.JoinTemporaryChannel(GuildComm.CHANNEL_NAME)
    if not idx and _G.GetChannelName then
        idx = _G.GetChannelName(GuildComm.CHANNEL_NAME)
    end
    GuildComm._channelIndex = (type(idx) == "number" and idx > 0) and idx or nil

    local reg = _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix
    if reg then reg(GuildComm.PREFIX) end
end

function GuildComm.LeaveChannel()
    if not _G.LeaveChannelByName then return end
    _G.LeaveChannelByName(GuildComm.CHANNEL_NAME)
    GuildComm._channelIndex = nil
end

function GuildComm.RefreshChannelIndex()
    if not _G.GetChannelName then return end
    local idx = _G.GetChannelName(GuildComm.CHANNEL_NAME)
    GuildComm._channelIndex = (type(idx) == "number" and idx > 0) and idx or nil
end
