-- GuildComm.lua — addon-message transport + handshake engine.
--
-- Pure-logic helpers are in GuildSync.lua. This file owns the WoW-facing
-- pieces: prefix registration, CHAT_MSG_ADDON dispatch, and
-- ChatThrottleLib-backed sending. The handshake state machine lives
-- here because it depends on the saved-vars schema and on calling back
-- into the owner's live knownRecipes data.
--
-- Transport: addon messages on "GUILD" scope. These ride a separate
-- packet stream and are invisible in guild chat; only clients that have
-- registered our prefix dispatch them. No channel membership needed —
-- we tried a custom channel first and kept stealing slot /1 from
-- General under edge cases.

RecipeBook = RecipeBook or {}
RecipeBook.GuildComm = RecipeBook.GuildComm or {}

local GuildComm = RecipeBook.GuildComm
local GuildSync = RecipeBook.GuildSync

GuildComm.PREFIX         = "RB"
GuildComm.HELLO_DEBOUNCE = 5       -- seconds
-- Minimum gap between DATA broadcasts for the same profession. Suppresses
-- piling on when many guildmates NEED the same roster — DATA on GUILD
-- scope already reaches everyone, so later NEEDs are redundant.
GuildComm.DATA_COOLDOWN_SECS = 15
GuildComm.MAX_GUILD_MEMBERS_PER_BROADCAST = 50

-- ============================================================
-- Rate-limited send via ChatThrottleLib (or direct fallback).
-- ============================================================

-- ============================================================
-- Debug logging
-- ============================================================
-- Toggled via /rb guild debug. When enabled, every outbound and
-- inbound addon message is echoed to the default chat frame with
-- direction arrows and sender. Stored in RecipeBookDB so the setting
-- persists across /reload for extended debugging sessions.

local function debugEnabled()
    return RecipeBookDB and RecipeBookDB.guildDebug == true
end

GuildComm._debugEnabled = debugEnabled

local function debugPrint(direction, msg, sender)
    if not DEFAULT_CHAT_FRAME then return end
    local tag = (direction == "out") and "|cff00ff00SENT|r" or "|cff99ccffRCVD|r"
    local who = sender and (" |cffffd100[" .. sender .. "]|r") or ""
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cff33bbff[RB-debug]|r " .. tag .. who .. " " .. tostring(msg))
end

-- Priority tiers: "NORMAL" for HELLO/NEED, "BULK" for DATA chunks.
local function rawSend(text, priority)
    priority = priority or "NORMAL"
    if not IsInGuild or not IsInGuild() then return end
    if debugEnabled() then debugPrint("out", text) end
    local ctl = _G.ChatThrottleLib
    if ctl and ctl.SendAddonMessage then
        ctl:SendAddonMessage(priority, GuildComm.PREFIX, text, "GUILD")
    else
        local fn = (_G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
        if fn then fn(GuildComm.PREFIX, text, "GUILD") end
    end
end

GuildComm._rawSend = rawSend  -- exposed for tests
GuildComm._debugPrint = debugPrint

-- Register our addon-message prefix. Safe to call repeatedly.
function GuildComm.RegisterPrefix()
    local reg = _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix
    if reg then reg(GuildComm.PREFIX) end
end

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
--
-- Idempotent: if the hashed recipe set hasn't actually changed since
-- the last call, the dv stays put. That stops an infinite NEED/DATA
-- cycle where harmless TRADE_SKILL_UPDATE events (re-opening a prof
-- window, a passive game tick, etc.) kept stamping new dvs, which
-- peers interpreted as "newer data" and re-requested every time.
--
-- Returns true when the hash actually changed (so callers can decide
-- whether a HELLO broadcast is warranted), false when the recipe set
-- was identical to what we already had.
function GuildComm.RefreshSelfMeta(profID)
    if not RecipeBookCharDB then return false end
    RecipeBookCharDB.guildSelfMeta = RecipeBookCharDB.guildSelfMeta or {}
    local recipes = myRecipesForProfession(profID)
    local hash = GuildSync.HashRecipes(recipes)
    local prev = RecipeBookCharDB.guildSelfMeta[profID]
    local changed = not prev or prev.hash ~= hash or not prev.dv
    if changed then
        RecipeBookCharDB.guildSelfMeta[profID] = { dv = time(), hash = hash }
    end

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

    return changed
end

-- Mirror every known profession's recipe list for the current character
-- into the guild store. Pure data sync — does NOT broadcast. Callers
-- that want to announce our presence (login handler, guild-join
-- handler, manual /rb guild hello) should call BroadcastHello
-- explicitly. Keeping this split means zone transitions (which also
-- fire PLAYER_ENTERING_WORLD) can refresh the mirror without spamming
-- peers with a fresh HELLO.
function GuildComm.MirrorAllSelf()
    if not GuildComm.CurrentGuildKey() then return 0 end
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey then return 0 end
    local charData = RecipeBookDB and RecipeBookDB.characters and RecipeBookDB.characters[myKey]
    if not charData or not charData.knownProfessions then return 0 end
    local count = 0
    for profID, known in pairs(charData.knownProfessions) do
        if known then
            GuildComm.RefreshSelfMeta(profID)
            count = count + 1
        end
    end
    return count
end

-- Apply a received DATA record to the guild store.
-- Staleness guard: if we already have a record for this (charKey, profID)
-- at an equal-or-newer dv, drop the incoming DATA. Protects against
-- replayed reassembly buffers, out-of-order chunk deliveries for a dv
-- we've since moved past, and clock-skew weirdness from peers.
-- Returns true when the store was updated, false on stale reject.
function GuildComm.ApplyData(senderCharKey, profID, dv, recipes)
    local guildKey, gName, realm = GuildComm.CurrentGuildKey()
    if not guildKey then return false end
    local guild = ensureGuildStore(guildKey, gName, realm)
    if not guild then return false end
    local m = ensureMember(guild, senderCharKey)
    local existing = m.professions[profID]
    if existing and existing.dv and dv and existing.dv >= dv then
        -- Still refresh lastSeen — we heard from them, just didn't learn anything new.
        m.lastSeen = time()
        return false
    end
    m.lastSeen = time()
    m.professions[profID] = { dv = dv, hash = GuildSync.HashRecipes(recipes), recipes = recipes }
    m._has = nil
    return true
end

-- ============================================================
-- Outbound — HELLO broadcast with debounce + sharing gate
-- ============================================================

GuildComm._helloPending = false

local function canBroadcast()
    if not RecipeBookDB or RecipeBookDB.guildSharingEnabled ~= true then return false end
    if not GuildComm.CurrentGuildKey() then return false end
    return true
end

-- Minimum gap between actual HELLO emissions on the wire. Prevents a
-- duplicate send when BroadcastHelloImmediate fires while a debounced
-- BroadcastHello timer is already scheduled (the timer would otherwise
-- re-fire sendHelloNow shortly after with identical content).
GuildComm.HELLO_MIN_GAP_SECS = 2

local function sendHelloNow()
    GuildComm._helloPending = false
    if not canBroadcast() then return end
    local now = time()
    if GuildComm._lastHelloSent
        and (now - GuildComm._lastHelloSent) < GuildComm.HELLO_MIN_GAP_SECS then
        return
    end
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey then return end
    local entries = myHelloEntries()
    if next(entries) == nil then return end
    local msg = GuildSync.EncodeHello(myKey, entries)
    rawSend(msg, "NORMAL")
    GuildComm._lastHelloSent = now
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
    if not IsInGuild or not IsInGuild() then return end
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey then return end
    rawSend(GuildSync.EncodeBye(myKey), "NORMAL")
end

-- ============================================================
-- Inbound — dispatch a decoded message
-- ============================================================

GuildComm._seenHelloThisSession = GuildComm._seenHelloThisSession or {}

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

    -- First time we've heard from this peer this session → echo our
    -- own HELLO back (debounced). This is the ONLY reliable way a
    -- late-joining peer learns about us and vice versa — an earlier
    -- "suppress echo if we broadcast recently" heuristic caused
    -- asymmetric discovery, where a peer whose _lastHelloSent was
    -- recent (e.g. just learned a recipe) would skip the echo, so the
    -- newcomer never heard from them.
    --
    -- The HELLO_MIN_GAP_SECS guard in sendHelloNow already prevents
    -- back-to-back identical sends, so unconditionally scheduling
    -- here is safe.
    if not GuildComm._seenHelloThisSession[record.charKey] then
        GuildComm._seenHelloThisSession[record.charKey] = true
        GuildComm.BroadcastHello()
    end
end

GuildComm._lastDataSent = GuildComm._lastDataSent or {}

local function handleNeed(record)
    if not canBroadcast() then return end  -- privacy gate applies to DATA too
    local myKey = RecipeBook:GetMyCharKey()
    if not myKey or record.targetCharKey ~= myKey then return end
    local meta = RecipeBookCharDB and RecipeBookCharDB.guildSelfMeta and RecipeBookCharDB.guildSelfMeta[record.profID]
    if not meta then return end

    -- Dedup: DATA is broadcast on GUILD scope, so a single reply reaches
    -- everyone. If several guildmates NEED the same (profID) within a
    -- short window, only respond to the first one.
    local now = time()
    local last = GuildComm._lastDataSent[record.profID]
    if last and (now - last) < GuildComm.DATA_COOLDOWN_SECS then return end
    GuildComm._lastDataSent[record.profID] = now

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

    -- Addon messages sent on GUILD scope echo back to the sender.
    -- Drop our own echoes up front — nothing useful comes from
    -- processing them, and they clutter the debug log as false "RCVD".
    local myKey = RecipeBook:GetMyCharKey()
    if myKey and senderCharKey then
        local bareSender = senderCharKey:match("^([^-]+)") or senderCharKey
        local bareMe     = myKey:match("^([^-]+)")         or myKey
        if bareSender == bareMe then return end
    end

    if debugEnabled() then debugPrint("in", msg, senderCharKey) end
    if not isInCurrentGuild(senderCharKey) then return end
    local record = GuildSync.Decode(msg)
    if not record then return end
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

