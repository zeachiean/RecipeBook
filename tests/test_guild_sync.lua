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

    -- Clear any lingering reassembly buffers.
    RecipeBook.GuildSync._buffers = {}
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

function T.test_need_for_other_char_is_ignored()
    RecipeBookCharDB.guildSelfMeta[ALCHEMY] = { dv = 1, hash = "x" }
    local need = RecipeBook.GuildSync.EncodeNeed("Somebody-Else", ALCHEMY)
    RecipeBook.GuildComm.HandleMessage(need, "Buddy-TestRealm")
    assert(#MockWoW._addonMessages == 0)
end

function T.test_apply_data_populates_guild_store()
    RecipeBook.GuildComm.ApplyData("Buddy-TestRealm", ALCHEMY, 300, { 10, 20, 30 })
    local guild = RecipeBookDB.guilds["TestGuild-TestRealm"]
    assert(guild, "guild entry should exist")
    local m = guild.members["Buddy-TestRealm"]
    assert(m and m.professions[ALCHEMY])
    assert(m.professions[ALCHEMY].dv == 300)
    assert(#m.professions[ALCHEMY].recipes == 3)
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
