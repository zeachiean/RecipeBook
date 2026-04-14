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

-- True when the crafter's current zone matches the active zone/continent
-- filter. Both `zone` and `continent` may be nil (no filter).
local function crafterZoneMatches(crafter, zoneFilter, continentFilter)
    if not zoneFilter and not continentFilter then return true end
    local cz = crafter.zone
    if zoneFilter then
        if not cz then return false end
        return cz == zoneFilter
    end
    if continentFilter then
        if not cz or not RecipeBook.GetContinentForZone then return false end
        return RecipeBook:GetContinentForZone(cz) == continentFilter
    end
    return true
end
UIGC._crafterZoneMatches = crafterZoneMatches

-- True when at least one crafter (online, in the cached guild store)
-- knows the given recipe AND passes the zone/continent filter.
-- A recipe with zero matching crafters is hidden from the guild view
-- when the user has a zone or continent filter active.
function UIGC:AnyCrafterMatchesZoneFilter(profID, recipeID, guildKey, zoneFilter, continentFilter)
    if not zoneFilter and not continentFilter then return true end
    local crafters = self:GatherCrafters(profID, recipeID, guildKey)
    for _, c in ipairs(crafters) do
        if c.online and crafterZoneMatches(c, zoneFilter, continentFilter) then
            return true
        end
    end
    return false
end

-- Total online guild members (from the live guild roster).
function UIGC:CountOnlineGuildMembers()
    if not _G.GetNumGuildMembers then return 0 end
    local n = _G.GetNumGuildMembers() or 0
    local online = 0
    for i = 1, n do
        local _, _, _, _, _, _, _, _, isOnline = _G.GetGuildRosterInfo(i)
        if isOnline then online = online + 1 end
    end
    return online
end

-- Cached guild members who are also currently online. These are the
-- people whose recipe data we know AND who can actually respond.
function UIGC:CountOnlineCachedMembers(guildKey)
    guildKey = guildKey or RecipeBook:GetViewedGuildKey()
    if not guildKey then return 0 end
    local guild = RecipeBookDB and RecipeBookDB.guilds and RecipeBookDB.guilds[guildKey]
    if not guild or not guild.members then return 0 end
    local count = 0
    for _, member in pairs(guild.members) do
        local ri = RecipeBook.GuildRoster and RecipeBook.GuildRoster:Get(member.name or "")
        if ri and ri.online then count = count + 1 end
    end
    return count
end

-- Count unique guildmates (online + offline) who have this profession
-- in the cached guild store. Used to decide whether the profession
-- even appears in the guild-view profession dropdown.
function UIGC:CountMembersWithProfession(profID, guildKey)
    guildKey = guildKey or RecipeBook:GetViewedGuildKey()
    if not guildKey then return 0, 0 end
    local guild = RecipeBookDB and RecipeBookDB.guilds and RecipeBookDB.guilds[guildKey]
    if not guild or not guild.members then return 0, 0 end

    local total, online = 0, 0
    for _, member in pairs(guild.members) do
        local prof = member.professions and member.professions[profID]
        if prof and prof.recipes and #prof.recipes > 0 then
            total = total + 1
            local ri = RecipeBook.GuildRoster and RecipeBook.GuildRoster:Get(member.name or "")
            if ri and ri.online then online = online + 1 end
        end
    end
    return total, online
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

function UIGC:OpenMenu(anchor, crafter, recipeLink, context)
    if not _G.UIDropDownMenu_Initialize then return end
    menuFrame = menuFrame or CreateFrame("Frame", "RecipeBookCrafterMenu", UIParent, "UIDropDownMenuTemplate")

    local charName = crafter and crafter.name or ""
    -- context is an optional { profID, recipeID } pair — lets us offer
    -- "Show All Crafters" only when we know which recipe the menu was
    -- opened from. (The popup itself omits that entry to avoid loops.)
    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        local info

        if context and context.profID and context.recipeID then
            info = UIDropDownMenu_CreateInfo()
            info.text = "Show All Crafters"
            info.notCheckable = true
            info.func = function()
                UIGC:ShowCraftersPopup(context.profID, context.recipeID)
            end
            UIDropDownMenu_AddButton(info, level)

            local sep = UIDropDownMenu_CreateInfo()
            sep.text = ""
            sep.isTitle = true
            sep.notCheckable = true
            UIDropDownMenu_AddButton(sep, level)
        end

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

-- ============================================================
-- Show All Crafters popup
-- ============================================================

local POPUP_WIDTH  = 440
local POPUP_HEIGHT = 320
local ROW_H        = 18
local popupFrame, popupRowPool, popupActiveRows = nil, {}, {}

local function recyclePopupRows()
    for _, row in ipairs(popupActiveRows) do
        row:Hide()
        popupRowPool[#popupRowPool + 1] = row
    end
    popupActiveRows = {}
end

local function getPopupRow(parent)
    local row = table.remove(popupRowPool)
    if row then
        row:SetParent(parent)
        row:ClearAllPoints()
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    row._bg = bg
    row:SetScript("OnEnter", function(s) s._bg:SetColorTexture(1, 1, 1, 0.08) end)
    row:SetScript("OnLeave", function(s) s._bg:SetColorTexture(1, 1, 1, 0) end)

    local nameText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    nameText:SetWidth(140)
    nameText:SetJustifyH("LEFT")
    row._name = nameText

    local levelText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    levelText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    levelText:SetWidth(30)
    levelText:SetJustifyH("LEFT")
    row._level = levelText

    local zoneText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    zoneText:SetPoint("LEFT", levelText, "RIGHT", 10, 0)
    zoneText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    zoneText:SetJustifyH("LEFT")
    row._zone = zoneText

    row:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        local c = self._crafter
        if not c then return end
        UIGC:OpenMenu(self, c, self._recipeLink)
    end)
    return row
end

local function createPopupFrame()
    if popupFrame then return popupFrame end
    local UI = RecipeBook.UI

    local frame = CreateFrame("Frame", "RecipeBookCraftersFrame", UIParent, "BackdropTemplate")
    frame:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and self:IsShown() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Title bar — the texture will be resized per-show to fit the guild name.
    local titleBar = frame:CreateTexture(nil, "ARTWORK")
    titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBar:SetSize(220, 64)
    titleBar:SetPoint("TOP", 0, 12)
    frame._titleBar = titleBar

    local titleText = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontTitle")
    titleText:SetPoint("TOP", titleBar, "TOP", 0, -14)
    frame._title = titleText

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontNormal")
    subtitle:SetPoint("TOP", frame, "TOP", 0, -30)
    subtitle:SetWidth(POPUP_WIDTH - 40)
    subtitle:SetWordWrap(false)
    subtitle:SetTextColor(1, 1, 1)
    frame._subtitle = subtitle

    -- Column headers. Positions mirror the row layout so the Crafter /
    -- Lvl / Status columns line up with the text they label.
    --   row LEFT = frame LEFT + 18 (scrollFrame inset)
    --   nameText  = row LEFT + 6   = frame LEFT + 24, width 140
    --   levelText = nameText RIGHT + 4 = frame LEFT + 168, width 30
    --   zoneText  = levelText RIGHT + 10 = frame LEFT + 208
    local function makeHeader(text, xOffset)
        local fs = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, -52)
        fs:SetText(text)
        if UI and UI.COLOR_HEADER then
            fs:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)
        end
        return fs
    end
    makeHeader("Crafter",        24)
    makeHeader("Lvl",            168)
    makeHeader("Status / Zone",  208)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "RecipeBookCraftersScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 14)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(POPUP_WIDTH - 48)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame._scrollChild = scrollChild

    popupFrame = frame
    return frame
end

function UIGC:ShowCraftersPopup(profID, recipeID, guildKey)
    guildKey = guildKey or RecipeBook:GetViewedGuildKey()
    if not guildKey then return end
    local frame = createPopupFrame()

    local guild = RecipeBookDB and RecipeBookDB.guilds and RecipeBookDB.guilds[guildKey]
    local guildName = (guild and guild.name) or guildKey
    local green = RecipeBook.GUILD_CHAT_COLOR or "|cff40ff40"
    local titleStr = green .. guildName .. "|r Crafters"
    frame._title:SetText(titleStr)

    -- Auto-fit the title bar texture so long guild names don't overflow.
    local textW = frame._title:GetStringWidth() or 0
    local barW = math.max(220, math.ceil(textW + 80))
    frame._titleBar:SetWidth(barW)

    local recipeName = RecipeBook:GetRecipeName(profID, recipeID) or "Recipe"
    frame._subtitle:SetText(recipeName)

    -- Build recipe link for right-click whisper
    local data = RecipeBook.recipeDB[profID] and RecipeBook.recipeDB[profID][recipeID]
    local recipeLink
    if data and data.teaches and type(data.teaches) == "number" then
        recipeLink = string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r",
            data.teaches, data.name or "Recipe")
    end

    -- Populate rows
    recyclePopupRows()
    local crafters = self:GatherCrafters(profID, recipeID, guildKey)
    local scrollChild = frame._scrollChild
    local y = 0
    for _, c in ipairs(crafters) do
        local row = getPopupRow(scrollChild)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

        local nameStr = c.name or "?"
        local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
        if c.online and color then
            nameStr = string.format("|cff%02x%02x%02x%s|r",
                math.floor(color.r * 255), math.floor(color.g * 255),
                math.floor(color.b * 255), nameStr)
        elseif not c.online then
            nameStr = "|cff888888" .. nameStr .. "|r"
        end
        row._name:SetText(nameStr)
        row._level:SetText(c.level and tostring(c.level) or "")
        if c.online then
            row._zone:SetText(c.zone or "Online")
            row._zone:SetTextColor(0.8, 0.9, 1.0)
        else
            row._zone:SetText("|cff888888offline|r")
        end
        row._crafter = c
        row._recipeLink = recipeLink
        popupActiveRows[#popupActiveRows + 1] = row
        y = y - ROW_H
    end
    scrollChild:SetHeight(math.max(1, #crafters * ROW_H))

    frame:Show()
end

function UIGC:CloseCraftersPopup()
    if popupFrame then popupFrame:Hide() end
end
