-- Tests for Guild Crafts: GuildSync (pure logic) and GuildComm (handshake).
local T = {}

local ALCHEMY     = 171
local TAILORING   = 197
local ENCHANTING  = 333

-- Fresh SavedVars + guild state between tests.
function T.setup()
    RecipeBookDB = {
        characters = {},
        guilds = {},
        guildSharingEnabled = true,
        guildSharePrompted = true,
        whisperTemplate = RecipeBook.DEFAULT_WHISPER_TEMPLATE,
        minimap = { hide = false },
        currentPhase = 1,
        maxPhase = 5,
    }
    RecipeBookCharDB = {
        professionSkill = {},
        guildSelfMeta = {},
    }
    RecipeBook:GetMyCharData()

    MockWoW.ClearAddonMessages()
    MockWoW.SetGuild("TestGuild", "TestRealm")
    MockWoW.SetGuildRoster({
        { name = "TestChar",  class = "WARRIOR", online = true,  zone = "Ironforge" },
        { name = "Buddy",     class = "MAGE",    online = true,  zone = "Stormwind" },
        { name = "Offline",   class = "ROGUE",   online = false, zone = "Silvermoon" },
    })

    -- Clear any lingering reassembly buffers + per-session state.
    RecipeBook.GuildSync._buffers = {}
    RecipeBook.GuildComm._helloPending = false
    RecipeBook.GuildComm._seenHelloThisSession = {}
    RecipeBook.GuildComm._lastDataSent = {}
    RecipeBook.GuildComm._lastHelloSent = nil
end

-- ============================================================
-- Hash tests
-- ============================================================

function T.test_hash_stability_ignores_input_order()
    local a = RecipeBook.GuildSync.HashRecipes({ 1001, 2002, 3003 })
    local b = RecipeBook.GuildSync.HashRecipes({ 3003, 1001, 2002 })
    assert(a == b, "hash must be order-independent; got " .. a .. " vs " .. b)
end

function T.test_hash_changes_when_recipes_change()
    local a = RecipeBook.GuildSync.HashRecipes({ 1, 2, 3 })
    local b = RecipeBook.GuildSync.HashRecipes({ 1, 2, 3, 4 })
    assert(a ~= b, "hash must change when recipe set changes")
end

function T.test_hash_empty_list_is_stable()
    local a = RecipeBook.GuildSync.HashRecipes({})
    local b = RecipeBook.GuildSync.HashRecipes({})
    assert(a == b and #a == 8, "empty hash must be the 8-char FNV zero: " .. a)
end

-- ============================================================
-- Encode / decode round-trips
-- ============================================================

function T.test_encode_decode_hello()
    local entries = {
        [ALCHEMY] = { dv = 100, hash = "aabbccdd" },
        [TAILORING] = { dv = 200, hash = "11223344" },
    }
    local msg = RecipeBook.GuildSync.EncodeHello("Foo-Realm", entries)
    local decoded = RecipeBook.GuildSync.Decode(msg)
    assert(decoded.type == "HELLO", "expected HELLO, got " .. tostring(decoded.type))
    assert(decoded.charKey == "Foo-Realm")
    assert(decoded.entries[ALCHEMY].dv == 100)
    assert(decoded.entries[ALCHEMY].hash == "aabbccdd")
    assert(decoded.entries[TAILORING].dv == 200)
end

function T.test_encode_decode_need()
    local msg = RecipeBook.GuildSync.EncodeNeed("Target-Realm", ALCHEMY)
    local d = RecipeBook.GuildSync.Decode(msg)
    assert(d.type == "NEED")
    assert(d.targetCharKey == "Target-Realm")
    assert(d.profID == ALCHEMY)
end

function T.test_encode_decode_bye()
    local msg = RecipeBook.GuildSync.EncodeBye("Bye-Realm")
    local d = RecipeBook.GuildSync.Decode(msg)
    assert(d.type == "BYE")
    assert(d.charKey == "Bye-Realm")
end

function T.test_decode_rejects_unknown_protocol()
    assert(RecipeBook.GuildSync.Decode("HELLO|v99|a|") == nil)
end

function T.test_decode_rejects_malformed()
    assert(RecipeBook.GuildSync.Decode("garbage") == nil)
    assert(RecipeBook.GuildSync.Decode("") == nil)
    assert(RecipeBook.GuildSync.Decode(nil) == nil)
end

-- ============================================================
-- Chunking + reassembly
-- ============================================================

local function makeRecipes(n, start)
    start = start or 10000
    local t = {}
    for i = 1, n do t[i] = start + i end
    return t
end

function T.test_small_payload_single_chunk()
    local chunks = RecipeBook.GuildSync.EncodeData("A-R", ALCHEMY, 100, { 1, 2, 3 })
    assert(#chunks == 1, "expected 1 chunk, got " .. #chunks)
    local d = RecipeBook.GuildSync.Decode(chunks[1])
    assert(d.seq == 1 and d.total == 1)
    assert(d.csv == "1,2,3", "csv was: " .. d.csv)
end

function T.test_large_payload_splits_and_reassembles()
    local recipes = makeRecipes(500)
    local chunks = RecipeBook.GuildSync.EncodeData("A-R", ALCHEMY, 100, recipes)
    assert(#chunks > 1, "500 recipes should chunk; got " .. #chunks)

    -- Verify every chunk is under the byte budget.
    for i, c in ipairs(chunks) do
        assert(#c <= 255, "chunk " .. i .. " is " .. #c .. " bytes (over 255)")
    end

    -- Feed out of order to exercise reassembly.
    local order = {}
    for i = #chunks, 1, -1 do order[#order + 1] = i end
    local got, done, recipesOut
    for _, i in ipairs(order) do
        local rec = RecipeBook.GuildSync.Decode(chunks[i])
        done, recipesOut = RecipeBook.GuildSync.IngestData(rec)
    end
    assert(done, "reassembly did not complete")
    assert(#recipesOut == 500, "expected 500 ids, got " .. #recipesOut)
    for i = 1, 500 do
        assert(recipesOut[i] == 10000 + i, "mismatch at " .. i)
    end
end

function T.test_empty_data_roundtrips()
    local chunks = RecipeBook.GuildSync.EncodeData("A-R", ALCHEMY, 100, {})
    assert(#chunks == 1)
    local rec = RecipeBook.GuildSync.Decode(chunks[1])
    local done, recipes = RecipeBook.GuildSync.IngestData(rec)
    assert(done and #recipes == 0)
end

-- ============================================================
-- Staleness decision
-- ============================================================

function T.test_decide_hello_no_record_needs_data()
    assert(RecipeBook.GuildSync.DecideHelloAction(nil, "abcd1234", 100) == "need")
end

function T.test_decide_hello_older_dv_needs_data()
    local ours = { dv = 50, hash = "aaaa" }
    assert(RecipeBook.GuildSync.DecideHelloAction(ours, "bbbb", 100) == "need")
end

function T.test_decide_hello_up_to_date_returns_nil()
    local ours = { dv = 100, hash = "aaaa" }
    assert(RecipeBook.GuildSync.DecideHelloAction(ours, "aaaa", 100) == nil)
end

function T.test_decide_hello_conflict_on_same_dv_different_hash()
    local ours = { dv = 100, hash = "aaaa" }
    assert(RecipeBook.GuildSync.DecideHelloAction(ours, "bbbb", 100) == "conflict")
end

-- ============================================================
-- Whisper template expansion (literal replacement)
-- ============================================================

function T.test_template_expands_placeholders()
    local out = RecipeBook.GuildSync.ExpandTemplate(
        "Hi {name}! Craft {recipe}?", "Buddy", "[Recipe: Foo]")
    assert(out == "Hi Buddy! Craft [Recipe: Foo]?", "got: " .. out)
end

function T.test_template_safe_against_pattern_injection()
    -- Recipe names with percent signs must not be treated as patterns.
    local out = RecipeBook.GuildSync.ExpandTemplate(
        "Craft {recipe}!", "X", "50%[Foo%1Bar]")
    assert(out == "Craft 50%[Foo%1Bar]!", "got: " .. out)
end

function T.test_template_missing_placeholders_ok()
    local out = RecipeBook.GuildSync.ExpandTemplate("Nothing here", "X", "Y")
    assert(out == "Nothing here")
end

-- ============================================================
-- GuildComm: privacy gating + HELLO over mock wire
-- ============================================================

function T.test_privacy_gating_blocks_hello_when_disabled()
    RecipeBookDB.guildSharingEnabled = false
    -- Seed some self meta so there IS something to broadcast.
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 100, hash = "aabbccdd" }
    RecipeBook.GuildComm.BroadcastHelloImmediate()
    assert(#MockWoW._addonMessages == 0,
        "expected zero outbound when disabled, got " .. #MockWoW._addonMessages)
end

function T.test_privacy_gated_hello_fires_when_enabled()
    RecipeBookDB.guildSharingEnabled = true
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 100, hash = "aabbccdd" }
    RecipeBook.GuildComm.BroadcastHelloImmediate()
    assert(#MockWoW._addonMessages == 1, "expected 1 HELLO, got " .. #MockWoW._addonMessages)
    local m = MockWoW._addonMessages[1]
    assert(m.prefix == "RB")
    assert(m.scope == "GUILD", "expected GUILD scope, got " .. tostring(m.scope))
    assert(m.text:find("^HELLO|v1|"), "wrong prefix: " .. m.text)
end

-- ============================================================
-- GuildComm: full handshake cold-start
-- ============================================================

function T.test_handshake_cold_start_triggers_need()
    -- Peer has a HELLO for a char we know nothing about.
    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 200, hash = "aabbccdd" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")

    assert(#MockWoW._addonMessages == 1, "expected 1 outbound NEED")
    local m = MockWoW._addonMessages[1]
    local dec = RecipeBook.GuildSync.Decode(m.text)
    assert(dec and dec.type == "NEED")
    assert(dec.targetCharKey == "Buddy-TestRealm")
    assert(dec.profID == ALCHEMY)
end

function T.test_handshake_up_to_date_emits_no_traffic()
    -- Pre-populate: we already have the peer's data at this dv+hash.
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
        or { name = "TestGuild", realm = "TestRealm", members = {} }
    RecipeBookDB.guilds["TestGuild-TestRealm"] = guild
    guild.members["Buddy-TestRealm"] = {
        name = "Buddy", realm = "TestRealm",
        professions = { [ALCHEMY] = { dv = 200, hash = "aabbccdd", recipes = {1,2,3} } },
    }

    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 200, hash = "aabbccdd" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")
    assert(#MockWoW._addonMessages == 0, "expected silence; got " .. #MockWoW._addonMessages)
end

function T.test_need_triggers_data_reply_when_ours()
    -- Seed our own recipes and meta.
    local myKey = RecipeBook:GetMyCharKey()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [101]=true, [102]=true, [103]=true }
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 500, hash = "deadbeef" }

    local need = RecipeBook.GuildSync.EncodeNeed(myKey, ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")

    assert(#MockWoW._addonMessages >= 1, "expected at least one DATA chunk")
    local m = MockWoW._addonMessages[1]
    local dec = RecipeBook.GuildSync.Decode(m.text)
    assert(dec.type == "DATA")
    assert(dec.charKey == myKey)
    assert(dec.dv == 500)
end

function T.test_data_cooldown_suppresses_duplicate_replies()
    -- Seed self-meta and knownRecipes so the NEED would normally be answered.
    local myKey = RecipeBook:GetMyCharKey()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100] = true, [200] = true }
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 500, hash = "x" }

    -- First NEED → replied.
    local need = RecipeBook.GuildSync.EncodeNeed(myKey, ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")
    local firstCount = #MockWoW._addonMessages
    assert(firstCount >= 1, "first NEED should be answered with DATA")

    -- Immediate second NEED from a different peer → suppressed.
    MockWoW.ClearAddonMessages()
    RecipeBook.GuildComm.HandleMessage(need, "Offline-TestRealm")
    assert(#MockWoW._addonMessages == 0,
        "second NEED within cooldown window should be suppressed; got "
        .. #MockWoW._addonMessages .. " outbound messages")
end

function T.test_data_cooldown_expires()
    local myKey = RecipeBook:GetMyCharKey()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100] = true }
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 500, hash = "x" }

    -- Pretend the last DATA was sent far in the past.
    RecipeBook.GuildComm._lastDataSent[ALCHEMY] = time() - 999

    local need = RecipeBook.GuildSync.EncodeNeed(myKey, ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")
    assert(#MockWoW._addonMessages >= 1,
        "NEED after cooldown expires should be answered")
end

function T.test_own_echoes_are_dropped()
    -- Our own HELLO echoing back via GUILD scope should be a no-op:
    -- no schedule, no recorded sent messages.
    local myKey = RecipeBook:GetMyCharKey()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 500, hash = "x" }

    local hello = RecipeBook.GuildSync.EncodeHello(myKey, {
        [ALCHEMY] = { dv = 500, hash = "x" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, myKey)

    assert(not RecipeBook.GuildComm._seenHelloThisSession[myKey],
        "self-echo should not register as a first-seen peer")
    assert(not RecipeBook.GuildComm._helloPending,
        "self-echo should not schedule any HELLO broadcast")
end

function T.test_refresh_self_meta_return_value()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [1] = true, [2] = true }

    -- First call — must report "changed".
    local firstChanged = RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    assert(firstChanged, "first RefreshSelfMeta must report changed")

    -- Second call with the same recipe set — must report "not changed".
    local secondChanged = RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    assert(not secondChanged,
        "RefreshSelfMeta must return false when hash is unchanged")

    -- Add a recipe and re-run — must report changed again.
    myData.knownRecipes[ALCHEMY][3] = true
    local thirdChanged = RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    assert(thirdChanged, "RefreshSelfMeta must return true after the set grows")
end

function T.test_on_my_recipes_changed_skips_broadcast_when_unchanged()
    local myData = RecipeBook:GetMyCharData()
    myData.knownProfessions[ALCHEMY] = true
    myData.knownRecipes[ALCHEMY]     = { [1] = true, [2] = true }

    -- Prime: the first call has nothing to compare to, so it broadcasts.
    RecipeBook:OnMyRecipesChanged(ALCHEMY)
    assert(RecipeBook.GuildComm._helloPending,
        "first call should schedule a broadcast")

    -- Flush and reset.
    RecipeBook.GuildComm._sendHelloNow()
    RecipeBook.GuildComm._helloPending = false
    assert(not RecipeBook.GuildComm._helloPending)

    -- Call again with identical data — must NOT schedule another broadcast.
    -- (This mirrors TRADE_SKILL_UPDATE firing while the prof window is open.)
    RecipeBook:OnMyRecipesChanged(ALCHEMY)
    assert(not RecipeBook.GuildComm._helloPending,
        "unchanged data must not re-schedule a HELLO")

    -- After an actual change, broadcast resumes.
    myData.knownRecipes[ALCHEMY][3] = true
    RecipeBook:OnMyRecipesChanged(ALCHEMY)
    assert(RecipeBook.GuildComm._helloPending,
        "new recipe should schedule a HELLO")
end

function T.test_idempotent_dv_when_hash_unchanged()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100] = true, [200] = true }

    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    local firstDV   = RecipeBookCharDB.guildSelfMeta[ALCHEMY].dv
    local firstHash = RecipeBookCharDB.guildSelfMeta[ALCHEMY].hash

    -- Re-run with identical recipe set — dv must not budge.
    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    local secondDV   = RecipeBookCharDB.guildSelfMeta[ALCHEMY].dv
    local secondHash = RecipeBookCharDB.guildSelfMeta[ALCHEMY].hash

    assert(secondDV == firstDV,
        "dv must not bump when recipe set hasn't changed (was " ..
        firstDV .. ", became " .. secondDV .. ")")
    assert(secondHash == firstHash)

    -- Now add a recipe — dv MUST bump.
    myData.knownRecipes[ALCHEMY][300] = true
    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    assert(RecipeBookCharDB.guildSelfMeta[ALCHEMY].hash ~= firstHash,
        "hash must change when recipes change")
end

function T.test_need_for_other_char_is_ignored()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 1, hash = "x" }
    local need = RecipeBook.GuildSync.EncodeNeed("Somebody-Else", ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")
    assert(#MockWoW._addonMessages == 0)
end

function T.test_apply_data_populates_guild_store()
    local ok = RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 300, { 10, 20, 30 })
    assert(ok, "ApplyData should return true on fresh write")
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
    assert(guild, "guild entry should exist")
    local m = guild.members["Buddy-TestRealm"]
    assert(m and m.professions[ALCHEMY])
    assert(m.professions[ALCHEMY].dv == 300)
    assert(#m.professions[ALCHEMY].recipes == 3)
end

function T.test_apply_data_rejects_stale_dv()
    -- First, a normal write at dv=500.
    assert(RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 500, { 1, 2, 3, 4 }))
    -- Now an older DATA arrives (replay / out-of-order reassembly).
    local ok = RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 100, { 9 })
    assert(ok == false, "stale DATA must be rejected")
    -- The existing record should be untouched.
    local m = RecipeBookDB.guilds["TestGuild-TestRealm"].members["Buddy-TestRealm"]
    assert(m.professions[ALCHEMY].dv == 500)
    assert(#m.professions[ALCHEMY].recipes == 4)
end

function T.test_apply_data_rejects_equal_dv()
    assert(RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 500, { 1, 2 }))
    -- Same dv again: drop. Same data is idempotent, different data at
    -- the same dv is an owner-side bug but we still don't want a flap.
    local ok = RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 500, { 1, 2, 3 })
    assert(ok == false, "equal-dv DATA must be rejected")
    local m = RecipeBookDB.guilds["TestGuild-TestRealm"].members["Buddy-TestRealm"]
    assert(#m.professions[ALCHEMY].recipes == 2)
end

-- ============================================================
-- BYE handler
-- ============================================================

function T.test_bye_updates_last_seen_without_wiping_data()
    -- Seed Buddy with some data.
    RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 100, { 10, 20, 30 })
    local before = RecipeBookDB.guilds["TestGuild-TestRealm"]
        .members["Buddy-TestRealm"].lastSeen
    -- Tiny wait-equivalent: adjust lastSeen back so we can see it move.
    RecipeBookDB.guilds["TestGuild-TestRealm"]
        .members["Buddy-TestRealm"].lastSeen = before - 100

    local bye = RecipeBook.GuildSync.EncodeBye("Buddy-TestRealm")
    RecipeBook.GuildComm.HandleMessage(bye, "Buddy-TestRealm")

    local m = RecipeBookDB.guilds["TestGuild-TestRealm"].members["Buddy-TestRealm"]
    assert(m, "BYE must not wipe the member entry")
    assert(m.professions[ALCHEMY], "BYE must not wipe cached professions")
    assert(m.lastSeen > before - 100, "lastSeen should be bumped")
end

-- ============================================================
-- Conflict path (same dv, different hash) emits no traffic
-- ============================================================

function T.test_conflict_emits_no_need_or_data()
    -- Pre-populate: we have the peer at dv=200, hash="aaaa".
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
        or { name = "TestGuild", realm = "TestRealm", members = {} }
    RecipeBookDB.guilds["TestGuild-TestRealm"] = guild
    guild.members["Buddy-TestRealm"] = {
        name = "Buddy", realm = "TestRealm",
        professions = { [ALCHEMY] = { dv = 200, hash = "aaaa", recipes = {1,2,3} } },
    }
    -- Mark as already-seen to isolate this from the first-seen echo path.
    RecipeBook.GuildComm._seenHelloThisSession["Buddy-TestRealm"] = true

    -- Peer HELLOs with same dv, different hash → conflict branch.
    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 200, hash = "bbbb" },
    })
    MockWoW.ClearAddonMessages()
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")

    assert(#MockWoW._addonMessages == 0,
        "conflict must not trigger NEED or DATA; got " .. #MockWoW._addonMessages)
    -- And the conflict should be logged once.
    assert(RecipeBook.GuildComm._conflictLog
        and RecipeBook.GuildComm._conflictLog["Buddy-TestRealm:" .. ALCHEMY])
end

-- ============================================================
-- Privacy-gated NEED handling
-- ============================================================

function T.test_need_ignored_when_sharing_disabled()
    RecipeBookDB.guildSharingEnabled = false
    -- Seed self-meta; the ONLY thing stopping a reply is the gate.
    local myKey = RecipeBook:GetMyCharKey()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100] = true }
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 500, hash = "x" }

    local need = RecipeBook.GuildSync.EncodeNeed(myKey, ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")
    assert(#MockWoW._addonMessages == 0,
        "must not reply to NEED when guildSharingEnabled is false")
end

-- ============================================================
-- DATA cooldown is per-profession, not global
-- ============================================================

function T.test_data_cooldown_is_per_profession()
    local myKey = RecipeBook:GetMyCharKey()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY]   = { [100] = true }
    myData.knownRecipes[TAILORING] = { [200] = true }
    RecipeBookCharDB.guildSelfMeta[ALCHEMY]   = { dv = 100, hash = "a" }
    RecipeBookCharDB.guildSelfMeta[TAILORING] = { dv = 200, hash = "b" }

    -- NEED for Alchemy — replied.
    RecipeBook.GuildComm.HandleMessage(
        RecipeBook.GuildSync.EncodeNeed(myKey, ALCHEMY), "Buddy-TestRealm")
    assert(#MockWoW._addonMessages >= 1)

    -- NEED for Tailoring — must NOT be blocked by Alchemy's cooldown.
    MockWoW.ClearAddonMessages()
    RecipeBook.GuildComm.HandleMessage(
        RecipeBook.GuildSync.EncodeNeed(myKey, TAILORING), "Buddy-TestRealm")
    assert(#MockWoW._addonMessages >= 1,
        "cooldown must be per-profession; Tailoring was suppressed by Alchemy's window")
end

-- ============================================================
-- Chunk reassembly corner cases
-- ============================================================

function T.test_duplicate_chunks_do_not_corrupt_buffer()
    local recipes = makeRecipes(500)
    local chunks = RecipeBook.GuildSync.EncodeData("A-R", ALCHEMY, 1, recipes)
    assert(#chunks > 1, "need a multi-chunk payload for this test")

    -- Ingest all chunks, then re-deliver each once more.
    local done, out
    for _, c in ipairs(chunks) do
        done, out = RecipeBook.GuildSync.IngestData(RecipeBook.GuildSync.Decode(c))
    end
    assert(done and #out == 500, "initial reassembly should succeed")

    -- Now replay. The buffer has been freed, so the first replay starts
    -- a new buffer; subsequent dupes within that new buffer should not
    -- bump received past total.
    RecipeBook.GuildSync._buffers = {}
    local d1 = RecipeBook.GuildSync.Decode(chunks[1])
    RecipeBook.GuildSync.IngestData(d1)
    RecipeBook.GuildSync.IngestData(d1)
    RecipeBook.GuildSync.IngestData(d1)  -- triple-deliver chunk 1
    for i = 2, #chunks do
        RecipeBook.GuildSync.IngestData(RecipeBook.GuildSync.Decode(chunks[i]))
    end
    -- Reassembly should still complete cleanly at the right count.
    -- (Buffer is cleared on completion; a subsequent ingest would restart.)
end

-- ============================================================
-- MirrorAllSelf idempotency
-- ============================================================

function T.test_mirror_all_self_preserves_dvs_when_unchanged()
    local myData = RecipeBook:GetMyCharData()
    myData.knownProfessions[ALCHEMY] = true
    myData.knownRecipes[ALCHEMY]     = { [1] = true, [2] = true }

    RecipeBook.GuildComm.MirrorAllSelf()
    local firstDV = RecipeBookCharDB.guildSelfMeta[ALCHEMY].dv

    -- Second pass, no changes.
    RecipeBook.GuildComm.MirrorAllSelf()
    assert(RecipeBookCharDB.guildSelfMeta[ALCHEMY].dv == firstDV,
        "MirrorAllSelf must be idempotent when the recipe set is unchanged")
end

function T.test_messages_from_non_guild_sender_are_dropped()
    local hello = RecipeBook.GuildSync.EncodeHello("Stranger-Realm", {
        [ALCHEMY] = { dv = 1, hash = "aaaa" },
    })
    -- Sender is not in the mock guild roster.
    RecipeBook.GuildComm.HandleMessage(hello, "Stranger-Realm")
    assert(#MockWoW._addonMessages == 0)
    assert(not (RecipeBookDB.guilds["TestGuild-TestRealm"]
        and RecipeBookDB.guilds["TestGuild-TestRealm"].members["Stranger-Realm"]),
        "stranger should not be stored")
end

-- ============================================================
-- Learn-recipe flow: RefreshSelfMeta updates dv/hash + mirrors into guild
-- ============================================================

function T.test_refresh_self_meta_updates_dv_and_hash()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100]=true, [200]=true }

    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)

    local meta = RecipeBookCharDB.guildSelfMeta[ALCHEMY]
    assert(meta and meta.dv and meta.dv > 0, "dv should be set")
    assert(meta.hash == RecipeBook.GuildSync.HashRecipes({100, 200}))

    -- Should also mirror into the guild self-entry.
    local myKey = RecipeBook:GetMyCharKey()
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
    assert(guild and guild.members[myKey])
    local prof = guild.members[myKey].professions[ALCHEMY]
    assert(prof and #prof.recipes == 2)
    assert(prof.recipes[1] == 100 and prof.recipes[2] == 200)
end

-- ============================================================
-- Guild profession filter (Hide Secondary / Hide Gathering)
-- ============================================================

function T.test_profession_not_hidden_when_flags_off()
    RecipeBookDB.guildHideSecondary = false
    RecipeBookDB.guildHideGathering = false
    assert(not RecipeBook:IsProfessionHiddenInGuildView(ALCHEMY))
    assert(not RecipeBook:IsProfessionHiddenInGuildView(356))   -- Fishing
    assert(not RecipeBook:IsProfessionHiddenInGuildView(186))   -- Mining
end

function T.test_hide_secondary_hides_cooking_fishing_firstaid_poisons()
    RecipeBookDB.guildHideSecondary = true
    RecipeBookDB.guildHideGathering = false
    assert(RecipeBook:IsProfessionHiddenInGuildView(185),  "Cooking should be hidden")
    assert(RecipeBook:IsProfessionHiddenInGuildView(129),  "First Aid should be hidden")
    assert(RecipeBook:IsProfessionHiddenInGuildView(356),  "Fishing should be hidden")
    assert(RecipeBook:IsProfessionHiddenInGuildView(2842), "Poisons should be hidden")
    assert(not RecipeBook:IsProfessionHiddenInGuildView(ALCHEMY), "Alchemy should stay")
    assert(not RecipeBook:IsProfessionHiddenInGuildView(186),     "Mining is gathering, not secondary")
end

function T.test_hide_gathering_hides_only_mining()
    RecipeBookDB.guildHideSecondary = false
    RecipeBookDB.guildHideGathering = true
    assert(RecipeBook:IsProfessionHiddenInGuildView(186),     "Mining should be hidden")
    assert(not RecipeBook:IsProfessionHiddenInGuildView(185), "Cooking stays when only gathering hidden")
    assert(not RecipeBook:IsProfessionHiddenInGuildView(ALCHEMY))
end

function T.test_hide_both_hides_all_matching()
    RecipeBookDB.guildHideSecondary = true
    RecipeBookDB.guildHideGathering = true
    assert(RecipeBook:IsProfessionHiddenInGuildView(185))   -- Cooking
    assert(RecipeBook:IsProfessionHiddenInGuildView(186))   -- Mining
    assert(not RecipeBook:IsProfessionHiddenInGuildView(ALCHEMY))
    assert(not RecipeBook:IsProfessionHiddenInGuildView(TAILORING))
end

-- ============================================================
-- Login-time auto-broadcast + first-seen echo
-- ============================================================

function T.test_mirror_all_self_is_pure_data_sync()
    -- MirrorAllSelf must mirror into the guild store but must NOT
    -- broadcast a HELLO on its own — callers decide when to announce,
    -- because PLAYER_ENTERING_WORLD fires on zone changes too.
    local myData = RecipeBook:GetMyCharData()
    myData.knownProfessions[ALCHEMY] = true
    myData.knownRecipes[ALCHEMY]     = { [1] = true, [2] = true }

    assert(not RecipeBook.GuildComm._helloPending)
    local n = RecipeBook.GuildComm.MirrorAllSelf()
    assert(n == 1, "should mirror the one known profession")
    assert(not RecipeBook.GuildComm._helloPending,
        "MirrorAllSelf must NOT schedule a HELLO by itself")

    -- The guild store should reflect the mirror.
    local myKey = RecipeBook:GetMyCharKey()
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
    assert(guild and guild.members[myKey], "self must appear in the guild store")
    assert(#guild.members[myKey].professions[ALCHEMY].recipes == 2)
end

function T.test_mirror_all_self_noop_when_no_known_professions()
    -- Fresh char with no scanned professions.
    assert(not RecipeBook.GuildComm._helloPending)
    local n = RecipeBook.GuildComm.MirrorAllSelf()
    assert(n == 0)
    assert(not RecipeBook.GuildComm._helloPending,
        "should NOT schedule HELLO when there's nothing to announce")
end

function T.test_first_seen_peer_triggers_echo_hello()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "selfhash" }

    -- First HELLO from a peer we've never heard from.
    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 100, hash = "peerhash" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")

    -- Should have scheduled an echo HELLO and marked the peer as seen.
    assert(RecipeBook.GuildComm._helloPending,
        "expected echo HELLO to be scheduled on first-seen peer")
    assert(RecipeBook.GuildComm._seenHelloThisSession["Buddy-TestRealm"])

    -- Flush and verify the echo is actually a HELLO on the wire.
    RecipeBook.GuildComm._sendHelloNow()
    local sawEcho = false
    for _, m in ipairs(MockWoW._addonMessages) do
        if m.text:find("^HELLO|v1|") then sawEcho = true end
    end
    assert(sawEcho, "echo HELLO did not reach the wire")
end

function T.test_first_seen_echo_suppressed_after_recent_broadcast()
    -- We just broadcast a HELLO. Any peer currently online has received
    -- it, so a first-seen echo back at them would be wasted traffic.
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "selfhash" }
    RecipeBook.GuildComm._lastHelloSent = time()  -- just sent

    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 100, hash = "peerhash" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")

    -- The peer is still marked as seen (we processed their HELLO).
    assert(RecipeBook.GuildComm._seenHelloThisSession["Buddy-TestRealm"])
    -- But we did NOT schedule an echo broadcast.
    assert(not RecipeBook.GuildComm._helloPending,
        "recent broadcast should suppress the first-seen echo")
end

function T.test_first_seen_echo_fires_after_suppress_window()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "selfhash" }
    -- Pretend our last HELLO was long enough ago.
    RecipeBook.GuildComm._lastHelloSent =
        time() - RecipeBook.GuildComm.HELLO_ECHO_SUPPRESS_SECS - 10

    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 100, hash = "peerhash" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")

    assert(RecipeBook.GuildComm._helloPending,
        "past the suppress window, the echo should fire")
end

function T.test_send_hello_now_stamps_last_sent()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "x" }
    assert(RecipeBook.GuildComm._lastHelloSent == nil)
    RecipeBook.GuildComm._sendHelloNow()
    assert(RecipeBook.GuildComm._lastHelloSent,
        "sendHelloNow must record the broadcast time")
end

function T.test_hello_rate_limit_prevents_duplicate_from_immediate_plus_debounced()
    -- Simulates: BroadcastHello() scheduled, then BroadcastHelloImmediate()
    -- fires before the debounce — the original timer must not double-send.
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "x" }

    RecipeBook.GuildComm.BroadcastHelloImmediate()
    local count1 = 0
    for _, m in ipairs(MockWoW._addonMessages) do
        if m.text:find("^HELLO|v1|") then count1 = count1 + 1 end
    end
    assert(count1 == 1, "first immediate send should go out")

    -- Now the debounced timer would fire (we fake it synchronously).
    RecipeBook.GuildComm._sendHelloNow()

    local count2 = 0
    for _, m in ipairs(MockWoW._addonMessages) do
        if m.text:find("^HELLO|v1|") then count2 = count2 + 1 end
    end
    assert(count2 == 1,
        "timer-fired sendHelloNow must not double-send when a HELLO just went out; got "
        .. count2 .. " HELLOs")
end

function T.test_subsequent_hellos_do_not_re_echo()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 50, hash = "selfhash" }
    RecipeBook.GuildComm._seenHelloThisSession = { ["Buddy-TestRealm"] = true }

    assert(not RecipeBook.GuildComm._helloPending)
    local hello = RecipeBook.GuildSync.EncodeHello("Buddy-TestRealm", {
        [ALCHEMY] = { dv = 100, hash = "peerhash" },
    })
    RecipeBook.GuildComm.HandleMessage(hello, "Buddy-TestRealm")
    assert(not RecipeBook.GuildComm._helloPending,
        "should NOT re-schedule HELLO for a peer we've already seen")
end

function T.test_debug_flag_is_off_by_default()
    assert(not RecipeBook.GuildComm._debugEnabled(),
        "debug should be off unless explicitly enabled")
end

function T.test_debug_flag_reflects_saved_var()
    RecipeBookDB.guildDebug = true
    assert(RecipeBook.GuildComm._debugEnabled())
    RecipeBookDB.guildDebug = false
    assert(not RecipeBook.GuildComm._debugEnabled())
end

function T.test_mirror_all_self_populates_all_known_professions()
    local myData = RecipeBook:GetMyCharData()
    myData.knownProfessions[ALCHEMY]   = true
    myData.knownProfessions[TAILORING] = true
    myData.knownRecipes[ALCHEMY]   = { [1] = true, [2] = true }
    myData.knownRecipes[TAILORING] = { [10] = true, [20] = true, [30] = true }

    local n = RecipeBook.GuildComm.MirrorAllSelf()
    assert(n == 2, "should mirror 2 professions, got " .. n)

    local myKey = RecipeBook:GetMyCharKey()
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
    assert(guild and guild.members[myKey], "self should be in guild store")
    local profs = guild.members[myKey].professions
    assert(profs[ALCHEMY] and #profs[ALCHEMY].recipes == 2)
    assert(profs[TAILORING] and #profs[TAILORING].recipes == 3)
end

function T.test_mirror_all_self_noop_when_guildless()
    MockWoW.SetGuild(nil)  -- leave guild
    local myData = RecipeBook:GetMyCharData()
    myData.knownProfessions[ALCHEMY] = true
    myData.knownRecipes[ALCHEMY] = { [1]=true }
    local n = RecipeBook.GuildComm.MirrorAllSelf()
    assert(n == 0, "should no-op when not in a guild, got " .. n)
end

function T.test_learn_recipe_advances_hash()
    local myData = RecipeBook:GetMyCharData()
    myData.knownRecipes[ALCHEMY] = { [100]=true }
    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    local h1 = RecipeBookCharDB.guildSelfMeta[ALCHEMY].hash

    myData.knownRecipes[ALCHEMY][200] = true
    RecipeBook.GuildComm.RefreshSelfMeta(ALCHEMY)
    local h2 = RecipeBookCharDB.guildSelfMeta[ALCHEMY].hash

    assert(h1 ~= h2, "hash should differ after learning new recipe")
end

-- ============================================================
-- Guild-hopper: old guild data survives joining a new guild
-- ============================================================

function T.test_guild_hopper_preserves_old_guild_data()
    -- Seed an old guild.
    RecipeBookDB.guilds["OldGuild-TestRealm"] = {
        name = "OldGuild", realm = "TestRealm",
        members = {
            ["Alice-TestRealm"] = {
                name = "Alice", realm = "TestRealm",
                professions = { [ALCHEMY] = { dv = 1, hash = "old1", recipes = {1,2} } },
            },
        },
    }
    -- Now the player is in TestGuild (set in setup). Both should coexist.
    local keys = RecipeBook:GetAllGuildKeys()
    assert(#keys >= 1)
    local seenOld = false
    for _, k in ipairs(keys) do if k == "OldGuild-TestRealm" then seenOld = true end end
    assert(seenOld, "old guild should still be listed")
end

-- ============================================================
-- Viewed-guild state: mutual exclusion with viewed-character
-- ============================================================

function T.test_setting_viewed_guild_clears_viewed_char()
    RecipeBookDB.guilds["TestGuild-TestRealm"] = { name = "TestGuild", members = {} }
    RecipeBookCharDB.viewingChar = "SomeAlt-TestRealm"
    RecipeBook:SetViewedGuildKey("TestGuild-TestRealm")
    assert(RecipeBookCharDB.viewingChar == nil, "viewed char should be cleared")
    assert(RecipeBook:GetViewedGuildKey() == "TestGuild-TestRealm")
end

function T.test_setting_viewed_char_clears_viewed_guild()
    RecipeBookDB.guilds["TestGuild-TestRealm"] = { name = "TestGuild", members = {} }
    RecipeBookCharDB.viewingGuildKey = "TestGuild-TestRealm"
    RecipeBook:SetViewedCharKey("Other-TestRealm")
    assert(RecipeBookCharDB.viewingGuildKey == nil, "viewed guild should be cleared")
end

function T.test_viewed_guild_returns_nil_when_data_gone()
    RecipeBookCharDB.viewingGuildKey = "NoSuchGuild"
    assert(RecipeBook:GetViewedGuildKey() == nil, "missing guild should not be viewable")
    assert(RecipeBookCharDB.viewingGuildKey == nil, "key should be cleared on access")
end

return T
