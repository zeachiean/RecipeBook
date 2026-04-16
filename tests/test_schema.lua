-- Tests for the schema-sentinel pattern: no migrations, just wipes.
-- When RecipeBook.DB_SCHEMA / CHAR_DB_SCHEMA / GUILD_SCHEMA is bumped,
-- the matching namespace is cleared on next InitSavedVars and the data
-- re-sources itself (via rescan prompt or guild handshake).
local T = {}

local ALCHEMY = 171
local popupsShown

function T.setup()
    RecipeBookDB = nil
    RecipeBookCharDB = nil
    popupsShown = {}
    -- Capture StaticPopup_Show calls so we can assert the rescan
    -- prompt fires only when it should.
    _G.StaticPopup_Show = function(name) popupsShown[name] = (popupsShown[name] or 0) + 1 end
end

-- ============================================================
-- Fresh install — no SV yet. No popup should fire.
-- ============================================================

function T.test_fresh_install_sets_schema_without_popup()
    RecipeBook._InitSavedVars()

    assert(RecipeBookDB.schema == RecipeBook.DB_SCHEMA,
        "DB_SCHEMA should be stamped on fresh init")
    assert(RecipeBookDB.guildSchema == RecipeBook.GUILD_SCHEMA,
        "GUILD_SCHEMA should be stamped on fresh init")
    assert(RecipeBookCharDB.schema == RecipeBook.CHAR_DB_SCHEMA,
        "CHAR_DB_SCHEMA should be stamped on fresh init")
    assert(not popupsShown["RECIPEBOOK_RESCAN_PROFESSIONS"],
        "rescan popup must not fire on fresh install")
end

-- ============================================================
-- Unversioned data with content — the upgrade-from-old case.
-- ============================================================

function T.test_unversioned_chars_trigger_wipe_and_popup()
    RecipeBookDB = {
        characters = {
            ["Alt1-Realm"] = { name = "Alt1", knownRecipes = { [ALCHEMY] = { [1] = true } } },
        },
        -- no schema field → treated as 0 → mismatch
    }
    RecipeBookCharDB = {}

    RecipeBook._InitSavedVars()

    -- Old alt should be gone. The current mock player gets re-created
    -- by the tail of InitSavedVars, so the table isn't literally empty.
    assert(RecipeBookDB.characters["Alt1-Realm"] == nil,
        "old alt entry must be wiped on schema mismatch")
    assert(RecipeBookDB.schema == RecipeBook.DB_SCHEMA)
    assert(popupsShown["RECIPEBOOK_RESCAN_PROFESSIONS"] == 1,
        "rescan popup should fire exactly once")
end

function T.test_matching_schema_preserves_chars()
    RecipeBookDB = {
        schema = RecipeBook.DB_SCHEMA,
        guildSchema = RecipeBook.GUILD_SCHEMA,
        characters = {
            ["Alt1-Realm"] = { name = "Alt1" },
        },
    }
    RecipeBookCharDB = { schema = RecipeBook.CHAR_DB_SCHEMA }

    RecipeBook._InitSavedVars()

    assert(RecipeBookDB.characters["Alt1-Realm"],
        "matching schema should preserve character data")
    assert(not popupsShown["RECIPEBOOK_RESCAN_PROFESSIONS"])
end

-- ============================================================
-- CharDB wipe preserves only professionSkill.
-- ============================================================

function T.test_char_db_wipe_preserves_profession_skill()
    RecipeBookCharDB = {
        professionSkill = { [ALCHEMY] = 275 },
        hideKnown = true,
        windowPos = { x = 100, y = 200 },
        viewingChar = "SomeAlt-Realm",
        -- no schema → wipe
    }
    RecipeBookDB = {
        schema = RecipeBook.DB_SCHEMA,
        guildSchema = RecipeBook.GUILD_SCHEMA,
    }

    RecipeBook._InitSavedVars()

    assert(RecipeBookCharDB.professionSkill[ALCHEMY] == 275,
        "professionSkill must survive CharDB wipe")
    assert(RecipeBookCharDB.hideKnown == false,
        "hideKnown should have been reset (wiped + default)")
    assert(RecipeBookCharDB.windowPos == nil,
        "windowPos must be cleared")
    assert(RecipeBookCharDB.viewingChar == nil,
        "viewingChar must be cleared")
    assert(RecipeBookCharDB.schema == RecipeBook.CHAR_DB_SCHEMA)
end

function T.test_char_db_wipe_with_no_profession_skill_is_safe()
    -- A CharDB with no professionSkill at all — wipe should still work.
    RecipeBookCharDB = { hideKnown = true }
    RecipeBookDB = { schema = RecipeBook.DB_SCHEMA, guildSchema = RecipeBook.GUILD_SCHEMA }

    RecipeBook._InitSavedVars()

    assert(type(RecipeBookCharDB.professionSkill) == "table")
    assert(next(RecipeBookCharDB.professionSkill) == nil)
end

-- ============================================================
-- Guild schema wipe is silent (no popup).
-- ============================================================

function T.test_guild_schema_wipe_is_silent()
    RecipeBookDB = {
        schema = RecipeBook.DB_SCHEMA,       -- DB matches
        -- guildSchema missing → mismatch, wipe guilds
        guilds = {
            ["OldGuild-Realm"] = { name = "OldGuild", members = {} },
        },
    }
    RecipeBookCharDB = { schema = RecipeBook.CHAR_DB_SCHEMA }

    RecipeBook._InitSavedVars()

    assert(next(RecipeBookDB.guilds) == nil, "guilds should be wiped")
    assert(RecipeBookDB.guildSchema == RecipeBook.GUILD_SCHEMA)
    assert(not popupsShown["RECIPEBOOK_RESCAN_PROFESSIONS"],
        "guild wipe must not surface a user-facing popup")
end

-- ============================================================
-- No popup when characters table is empty (fresh install edge case).
-- ============================================================

function T.test_empty_characters_table_does_not_popup()
    RecipeBookDB = { characters = {} }  -- empty, no schema
    RecipeBookCharDB = {}

    RecipeBook._InitSavedVars()

    assert(not popupsShown["RECIPEBOOK_RESCAN_PROFESSIONS"],
        "an empty characters table is indistinguishable from fresh install; no popup")
end

-- ============================================================
-- Defaults are re-applied after a wipe.
-- ============================================================

function T.test_defaults_repopulate_after_char_db_wipe()
    RecipeBookDB = {
        schema = RecipeBook.DB_SCHEMA,
        guildSchema = RecipeBook.GUILD_SCHEMA,
    }
    RecipeBookCharDB = { hideKnown = true }  -- no schema → wipe

    RecipeBook._InitSavedVars()

    -- After wipe + defaults, hideKnown should be false again.
    assert(RecipeBookCharDB.hideKnown == false)
    assert(type(RecipeBookCharDB.collapsedSources) == "table")
    assert(RecipeBookCharDB.guildUnknownFilter == "show")
end

return T
