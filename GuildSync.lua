-- GuildSync.lua — pure-logic layer for guild recipe synchronisation.
--
-- No frames, no events. Every function is a pure data operation that
-- the tests can drive with mocked transport. GuildComm.lua supplies
-- the real send/receive plumbing.
--
-- Protocol:
--   HELLO|v1|<charKey>|<profID>:<hash>:<dv>,<profID>:<hash>:<dv>,...
--   NEED|v1|<targetCharKey>|<profID>
--   DATA|v1|<charKey>|<profID>|<dv>|<seq>|<total>|<csv>
--   BYE|v1|<charKey>
--
-- dv  = Unix timestamp of last scan for (charKey, profID) on the owner.
-- hash = FNV-1a 32-bit of sorted recipe IDs (8 hex chars).
-- csv  = sorted recipe-ID list, comma-joined.

RecipeBook = RecipeBook or {}
RecipeBook.GuildSync = RecipeBook.GuildSync or {}

local GuildSync = RecipeBook.GuildSync

GuildSync.PROTOCOL = "v1"

-- Payload size budget for a single addon message body. The 255-byte
-- limit is for prefix+body combined; we leave margin for header fields.
GuildSync.CHUNK_BUDGET = 220

-- ============================================================
-- FNV-1a 32-bit hash (pure arithmetic, Lua 5.1 safe)
-- ============================================================

local FNV_OFFSET = 2166136261    -- 0x811C9DC5
local FNV_PRIME  = 16777619      -- 0x01000193
local FNV_MOD    = 4294967296    -- 0x100000000

local function fnv1a(str)
    local h = FNV_OFFSET
    for i = 1, #str do
        h = (h - h % 1) -- force integer
        local b = str:byte(i)
        -- XOR via arithmetic: only safe when both sides fit in 32 bits.
        -- For FNV-1a the byte is <=255 and h low byte is arbitrary, so
        -- we just XOR the low byte and rebuild. Implementation: use a
        -- lookup-free trick via bit manipulation emulation.
        local lo = h % 256
        local xored = 0
        local a, bb = lo, b
        local bit = 1
        for _ = 1, 8 do
            if (a % 2) ~= (bb % 2) then xored = xored + bit end
            a = (a - a % 2) / 2
            bb = (bb - bb % 2) / 2
            bit = bit * 2
        end
        h = h - lo + xored
        h = (h * FNV_PRIME) % FNV_MOD
    end
    return string.format("%08x", h)
end

GuildSync._fnv1a = fnv1a  -- exposed for tests

-- Hash a sorted list of integer recipe IDs.
-- Input is sorted here defensively, so callers can't rely on order.
function GuildSync.HashRecipes(recipes)
    if type(recipes) ~= "table" or #recipes == 0 then
        return fnv1a("")
    end
    local copy = {}
    for i = 1, #recipes do copy[i] = recipes[i] end
    table.sort(copy)
    local parts = {}
    for i = 1, #copy do parts[i] = tostring(copy[i]) end
    return fnv1a(table.concat(parts, ","))
end

-- ============================================================
-- Message encoding / decoding
-- ============================================================

-- Encode a HELLO summarising our profession roster hashes.
-- @param charKey string
-- @param entries { [profID] = { dv = number, hash = string } }
-- @return string
function GuildSync.EncodeHello(charKey, entries)
    local parts = {}
    -- Sort profIDs for stable output (testability)
    local ids = {}
    for profID in pairs(entries) do ids[#ids + 1] = profID end
    table.sort(ids)
    for _, profID in ipairs(ids) do
        local e = entries[profID]
        parts[#parts + 1] = string.format("%d:%s:%d", profID, e.hash, e.dv)
    end
    return string.format("HELLO|%s|%s|%s", GuildSync.PROTOCOL, charKey, table.concat(parts, ","))
end

function GuildSync.EncodeNeed(targetCharKey, profID)
    return string.format("NEED|%s|%s|%d", GuildSync.PROTOCOL, targetCharKey, profID)
end

function GuildSync.EncodeBye(charKey)
    return string.format("BYE|%s|%s", GuildSync.PROTOCOL, charKey)
end

-- Encode DATA reply. Returns an array of chunk strings (1..N).
function GuildSync.EncodeData(charKey, profID, dv, recipes)
    local copy = {}
    for i = 1, #recipes do copy[i] = recipes[i] end
    table.sort(copy)
    local strs = {}
    for i = 1, #copy do strs[i] = tostring(copy[i]) end
    local csv = table.concat(strs, ",")

    -- Header size: "DATA|v1|<charKey>|<profID>|<dv>|<seq>|<total>|"
    -- Charkey realistically <= 30 chars, profID <= 5, dv <= 10, seq/total <= 3 each.
    local header_overhead = #charKey + 40
    local body_budget = GuildSync.CHUNK_BUDGET - header_overhead
    if body_budget < 32 then body_budget = 32 end  -- defensive floor

    local chunks = {}
    if #csv == 0 then
        chunks[1] = string.format("DATA|%s|%s|%d|%d|1|1|", GuildSync.PROTOCOL, charKey, profID, dv)
        return chunks
    end

    -- Walk CSV, splitting on commas to avoid cutting IDs in half.
    local pos = 1
    while pos <= #csv do
        local limit = pos + body_budget - 1
        if limit >= #csv then
            chunks[#chunks + 1] = csv:sub(pos)
            break
        end
        -- Find last comma at or before limit
        local cut = csv:sub(pos, limit):match(".*(),")
        -- match returns position of the pattern inside the substring; but we
        -- need the absolute comma index. Use find instead.
        local sub = csv:sub(pos, limit)
        local lastComma
        local s, e = 1, 1
        while true do
            local c = sub:find(",", s, true)
            if not c then break end
            lastComma = c
            s = c + 1
        end
        if not lastComma then
            -- No comma in the budget window: force advance one ID.
            -- (Should be rare — requires a single ID > body_budget chars, impossible for 32-bit ints.)
            local nextComma = csv:find(",", pos, true)
            if nextComma then
                chunks[#chunks + 1] = csv:sub(pos, nextComma - 1)
                pos = nextComma + 1
            else
                chunks[#chunks + 1] = csv:sub(pos)
                break
            end
        else
            chunks[#chunks + 1] = csv:sub(pos, pos + lastComma - 2) -- drop trailing comma
            pos = pos + lastComma
        end
    end

    local total = #chunks
    for i = 1, total do
        chunks[i] = string.format("DATA|%s|%s|%d|%d|%d|%d|%s",
            GuildSync.PROTOCOL, charKey, profID, dv, i, total, chunks[i])
    end
    return chunks
end

-- Decode a single message. Returns the parsed record, or nil on malformed input.
-- Records:
--   { type="HELLO", charKey, entries = { [profID] = { dv, hash } } }
--   { type="NEED",  targetCharKey, profID }
--   { type="DATA",  charKey, profID, dv, seq, total, csv }
--   { type="BYE",   charKey }
function GuildSync.Decode(msg)
    if type(msg) ~= "string" or #msg == 0 then return nil end
    local kind, proto, rest = msg:match("^([A-Z]+)|([^|]+)|(.*)$")
    if not kind or proto ~= GuildSync.PROTOCOL then return nil end

    if kind == "HELLO" then
        local charKey, summary = rest:match("^([^|]+)|(.*)$")
        if not charKey then return nil end
        local entries = {}
        if #summary > 0 then
            for item in string.gmatch(summary, "([^,]+)") do
                local pid, hash, dv = item:match("^(%d+):([0-9a-f]+):(%d+)$")
                if pid and hash and dv then
                    entries[tonumber(pid)] = { hash = hash, dv = tonumber(dv) }
                end
            end
        end
        return { type = "HELLO", charKey = charKey, entries = entries }

    elseif kind == "NEED" then
        local targetCharKey, pid = rest:match("^([^|]+)|(%d+)$")
        if not targetCharKey then return nil end
        return { type = "NEED", targetCharKey = targetCharKey, profID = tonumber(pid) }

    elseif kind == "DATA" then
        local charKey, pid, dv, seq, total, csv = rest:match("^([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
        if not charKey then return nil end
        return {
            type = "DATA",
            charKey = charKey,
            profID = tonumber(pid),
            dv = tonumber(dv),
            seq = tonumber(seq),
            total = tonumber(total),
            csv = csv or "",
        }

    elseif kind == "BYE" then
        local charKey = rest:match("^([^|]+)$")
        if not charKey then return nil end
        return { type = "BYE", charKey = charKey }
    end

    return nil
end

-- ============================================================
-- Chunk reassembly
-- ============================================================

-- Reassembly buffer keyed by senderCharKey|profID|dv.
-- Stored on the GuildSync module so tests can inspect / clear it.
GuildSync._buffers = GuildSync._buffers or {}

local function bufferKey(charKey, profID, dv)
    return string.format("%s|%d|%d", charKey, profID, dv)
end

-- Feed a DATA record into the reassembly buffer.
-- Returns (complete, recipes) when the final chunk arrives; nil otherwise.
function GuildSync.IngestData(record)
    if record.type ~= "DATA" then return nil end
    local key = bufferKey(record.charKey, record.profID, record.dv)
    local buf = GuildSync._buffers[key]
    if not buf then
        buf = { total = record.total, received = 0, parts = {} }
        GuildSync._buffers[key] = buf
    end
    if not buf.parts[record.seq] then
        buf.parts[record.seq] = record.csv
        buf.received = buf.received + 1
    end
    if buf.received < buf.total then return nil end

    -- Reassemble
    local pieces = {}
    for i = 1, buf.total do
        if not buf.parts[i] then
            GuildSync._buffers[key] = nil
            return nil  -- gap: drop (shouldn't happen in practice)
        end
        pieces[i] = buf.parts[i]
    end
    GuildSync._buffers[key] = nil

    local csv = table.concat(pieces, ",")
    local recipes = {}
    if #csv > 0 then
        for id in string.gmatch(csv, "([^,]+)") do
            local n = tonumber(id)
            if n then recipes[#recipes + 1] = n end
        end
    end
    table.sort(recipes)
    return true, recipes
end

-- ============================================================
-- Staleness decision on an incoming HELLO
-- ============================================================

-- Given our stored entry and the peer's claim, return:
--   "need"    — request a full DATA
--   "conflict"— hashes differ but dv matches (log once, no request)
--   nil       — we're up to date, do nothing
function GuildSync.DecideHelloAction(ourEntry, theirHash, theirDV)
    if not ourEntry or not ourEntry.dv then return "need" end
    if theirDV > ourEntry.dv then return "need" end
    if theirDV == ourEntry.dv and theirHash ~= ourEntry.hash then
        return "conflict"
    end
    return nil
end

-- ============================================================
-- Whisper template expansion (literal, no pattern injection)
-- ============================================================

-- Expand {name} / {recipe} placeholders in a template.
-- Uses plain-text replacement — recipe names with `%` or `$` signs in
-- them can't wreak havoc on string.gsub's pattern matcher.
function GuildSync.ExpandTemplate(template, name, recipeLink)
    if type(template) ~= "string" then return "" end
    local out = template
    -- Literal replace with a function-replacement gsub (skips pattern evaluation on replacement).
    out = out:gsub("{name}",   function() return name or "" end)
    out = out:gsub("{recipe}", function() return recipeLink or "" end)
    return out
end
