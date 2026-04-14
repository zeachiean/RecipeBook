-- UIGuildCrafters.lua — guild-view rendering + right-click crafter menu.
--
-- When the Character dropdown has a Guild selected, UIRender swaps the
-- per-row Source cell for a Crafters cell rendered here. Rows expose the
-- raw knowers list via row._guildCrafters for the "Show All" popup to
-- reuse.

RecipeBook = RecipeBook or {}
RecipeBook.UIGuildCrafters = RecipeBook.UIGuildCrafters or {}

local UIGC = RecipeBook.UIGuildCrafters
local INLINE_LIMIT = 3

-- ============================================================
-- Lazy membership cache per member (session only)
-- ============================================================

local function warmHas(member)
    if not member or not member.professions then return end
    for _, prof in pairs(member.professions) do
        if prof.recipes and not prof._has then
            local has = {}
            for i = 1, #prof.recipes do has[prof.recipes[i]] = true end
            prof._has = has
        end
    end
end

-- Return the list of crafters for a (profID, recipeID) within the viewed guild.
-- @return { {charKey, name, class, online, zone}, ... } sorted online-first then name.
function UIGC:GatherCrafters(profID, recipeID, guildKey)
    guildKey = guildKey or RecipeBook:GetViewedGuildKey()
    if not guildKey then return {} end
    local guild = RecipeBookDB and RecipeBookDB.guilds and RecipeBookDB.guilds[guildKey]
    if not guild or not guild.members then return {} end

    local out = {}
    for charKey, member in pairs(guild.members) do
        warmHas(member)
        local prof = member.professions and member.professions[profID]
        if prof and prof._has and prof._has[recipeID] then
            local rosterInfo = RecipeBook.GuildRoster and RecipeBook.GuildRoster:Get(member.name or charKey)
            out[#out + 1] = {
                charKey = charKey,
                name = member.name or charKey,
                class = (rosterInfo and rosterInfo.class) or member.class,
                online = rosterInfo and rosterInfo.online or false,
                zone = rosterInfo and rosterInfo.zone or nil,
                level = rosterInfo and rosterInfo.level or nil,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- Count only (used by the Count column).
function UIGC:CountCrafters(profID, recipeID, guildKey)
    return #self:GatherCrafters(profID, recipeID, guildKey)
end

-- Render a crafters cell for a row. Writes into the existing _sourceText
-- field so we don't need a second font-string widget.
function UIGC:RenderCraftersCell(row, profID, recipeID)
    if not row or not row._sourceText then return end
    local crafters = self:GatherCrafters(profID, recipeID)
    row._guildCrafters = crafters
    row._profID = profID
    row._recipeID = recipeID

    if #crafters == 0 then
        row._sourceText:SetText("|cff888888(no crafters)|r")
        if row._countText then row._countText:SetText("0") end
        return
    end

    local parts = {}
    local limit = math.min(#crafters, INLINE_LIMIT)
    for i = 1, limit do
        local c = crafters[i]
        local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
        local name = c.name
        if c.online and color then
            name = string.format("|cff%02x%02x%02x%s|r",
                math.floor(color.r * 255), math.floor(color.g * 255),
                math.floor(color.b * 255), name)
        elseif not c.online then
            name = "|cff888888" .. name .. "|r"
        end
        parts[#parts + 1] = name
    end
    local text = table.concat(parts, ", ")
    if #crafters > INLINE_LIMIT then
        text = text .. string.format(" |cff888888+%d|r", #crafters - INLINE_LIMIT)
    end
    row._sourceText:SetText(text)

    if row._countText then
        row._countText:SetText(tostring(#crafters))
    end
end

-- ============================================================
-- Right-click menu
-- ============================================================

local menuFrame

local function getExpandedTemplate(charName, recipeLink)
    local tmpl = (RecipeBookDB and RecipeBookDB.whisperTemplate)
        or RecipeBook.DEFAULT_WHISPER_TEMPLATE or ""
    return RecipeBook.GuildSync.ExpandTemplate(tmpl, charName, recipeLink)
end

local function doWhisper(charName, recipeLink)
    local text = getExpandedTemplate(charName, recipeLink)
    if _G.ChatFrame_OpenChat then
        _G.ChatFrame_OpenChat("/w " .. charName .. " " .. text, DEFAULT_CHAT_FRAME)
    end
end

local function doInvite(charName)
    if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
        _G.C_PartyInfo.InviteUnit(charName)
    elseif _G.InviteUnit then
        _G.InviteUnit(charName)
    end
end

local function doWho(charName)
    if _G.SendWho then _G.SendWho("n-" .. charName) end
end

local function doCopy(charName)
    StaticPopupDialogs["RECIPEBOOK_COPY_CHAR_NAME"] = StaticPopupDialogs["RECIPEBOOK_COPY_CHAR_NAME"] or {
        text = "Character name (Ctrl-C to copy):",
        button1 = OKAY or "OK",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self, data)
            local eb = self.editBox or _G[self:GetName() .. "EditBox"]
            if eb then
                eb:SetText(data or "")
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopup_Show("RECIPEBOOK_COPY_CHAR_NAME", nil, nil, charName)
end

function UIGC:OpenMenu(anchor, crafter, recipeLink)
    if not _G.UIDropDownMenu_Initialize then return end
    menuFrame = menuFrame or CreateFrame("Frame", "RecipeBookCrafterMenu", UIParent, "UIDropDownMenuTemplate")

    local charName = crafter and crafter.name or ""
    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        local info

        info = UIDropDownMenu_CreateInfo()
        info.text = charName
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Whisper"
        info.notCheckable = true
        info.func = function() doWhisper(charName, recipeLink or "") end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Invite"
        info.notCheckable = true
        info.func = function() doInvite(charName) end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Who"
        info.notCheckable = true
        info.func = function() doWho(charName) end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Copy Name"
        info.notCheckable = true
        info.func = function() doCopy(charName) end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = CANCEL or "Cancel"
        info.notCheckable = true
        info.func = function() end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")

    if _G.ToggleDropDownMenu then
        ToggleDropDownMenu(1, nil, menuFrame, anchor or "cursor", 0, 0)
    end
end

-- Pick a crafter to target when the whole row is right-clicked: first
-- online one, or the first listed if none online.
function UIGC:PickPrimaryCrafter(row)
    if not row or not row._guildCrafters or #row._guildCrafters == 0 then return nil end
    for _, c in ipairs(row._guildCrafters) do if c.online then return c end end
    return row._guildCrafters[1]
end
