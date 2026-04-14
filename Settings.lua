-- RecipeBook Settings.lua
-- Standalone settings window with character management and About section

RecipeBook = RecipeBook or {}

local UI = RecipeBook.UI

local PANEL_WIDTH = 400
local PANEL_HEIGHT = 480
local CONTENT_WIDTH = PANEL_WIDTH - 12 - 32 - 16  -- left inset, scrollbar, padding

-- ============================================================
-- Standalone settings window
-- ============================================================

local panel = CreateFrame("Frame", "RecipeBookSettingsPanel", UIParent, "BackdropTemplate")
panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
panel:Hide()
tinsert(UISpecialFrames, "RecipeBookSettingsPanel")

-- Title bar
local titleBar = panel:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetSize(260, 64)
titleBar:SetPoint("TOP", 0, 12)

local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", titleBar, "TOP", 0, -14)
titleText:SetText("RecipeBook Settings")

-- Close button
local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)

-- Scroll frame fills the panel below the title
local scrollFrame = CreateFrame("ScrollFrame", "RecipeBookSettingsScroll", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -32)
scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)

local scrollChild = CreateFrame("Frame", "RecipeBookSettingsScrollChild")
scrollChild:SetWidth(CONTENT_WIDTH)
scrollChild:SetHeight(800)
scrollFrame:SetScrollChild(scrollChild)

local SECTION_GAP = 16

-- Helper: create a section header with a horizontal rule
local function CreateSectionHeader(prevEnd, text)
    local header = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", prevEnd, "BOTTOMLEFT", 0, -SECTION_GAP)
    header:SetText("|cffffd100" .. text .. "|r")

    local line = scrollChild:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetWidth(CONTENT_WIDTH)
    line:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    return header, line
end

-- Helper: invisible anchor marking the bottom of a section
local function CreateSectionEnd(lastElement, yOffset)
    local marker = CreateFrame("Frame", nil, scrollChild)
    marker:SetSize(1, 1)
    marker:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, yOffset or 0)
    return marker
end

-- ============================================================
-- Section: General
-- ============================================================

local topAnchor = CreateFrame("Frame", nil, scrollChild)
topAnchor:SetSize(1, 1)
topAnchor:SetPoint("TOPLEFT", 12, 8)

local generalHeader, generalLine = CreateSectionHeader(topAnchor, "General")

-- Minimap button checkbox
local minimapCheck = CreateFrame("CheckButton", "RecipeBookSettingsMinimap", scrollChild, "UICheckButtonTemplate")
minimapCheck:SetPoint("TOPLEFT", generalLine, "BOTTOMLEFT", -4, -8)
minimapCheck:SetSize(24, 24)
local minimapText = _G["RecipeBookSettingsMinimapText"]
minimapText:SetText("Show Minimap Button")
minimapText:SetFontObject("GameFontNormal")
minimapCheck:SetScript("OnClick", function(self)
    local wantHidden = not self:GetChecked()
    local isHidden = RecipeBookDB and RecipeBookDB.minimap and RecipeBookDB.minimap.hide
    if (wantHidden and not isHidden) or (not wantHidden and isHidden) then
        RecipeBook:ToggleMinimapButton()
    end
end)

-- Tooltip info checkbox
local tooltipCheck = CreateFrame("CheckButton", "RecipeBookSettingsTooltip", scrollChild, "UICheckButtonTemplate")
tooltipCheck:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 0, -4)
tooltipCheck:SetSize(24, 24)
local tooltipText = _G["RecipeBookSettingsTooltipText"]
tooltipText:SetText("Show Recipe Info on Tooltips")
tooltipText:SetFontObject("GameFontNormal")
tooltipCheck:SetScript("OnClick", function(self)
    local checked = self:GetChecked() and true or false
    if RecipeBookDB then
        RecipeBookDB.showTooltipInfo = checked
    end
end)

-- ============================================================
-- Section: Filters
-- ============================================================

local generalSectionEnd = CreateSectionEnd(tooltipCheck, 0)
generalSectionEnd:SetPoint("TOPLEFT", tooltipCheck, "BOTTOMLEFT", 4, 0)

local filterHeader, filterLine = CreateSectionHeader(generalSectionEnd, "Filters")

-- My Faction checkbox
local factionCheck = CreateFrame("CheckButton", "RecipeBookSettingsFaction", scrollChild, "UICheckButtonTemplate")
factionCheck:SetPoint("TOPLEFT", filterLine, "BOTTOMLEFT", -4, -8)
factionCheck:SetSize(24, 24)
local factionText = _G["RecipeBookSettingsFactionText"]
factionText:SetText("My Faction Only")
factionText:SetFontObject("GameFontNormal")
factionCheck:SetScript("OnClick", function(self)
    local checked = self:GetChecked() and true or false
    RecipeBook.myFactionOnly = checked
    if RecipeBookCharDB then
        RecipeBookCharDB.myFactionOnly = checked
    end
    RecipeBook:RefreshRecipeList()
end)

-- Phase dropdown
local phaseLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
phaseLabel:SetPoint("TOPLEFT", factionCheck, "BOTTOMLEFT", 4, -12)
phaseLabel:SetText("Max Phase:")

local phaseDropdown = CreateFrame("Frame", "RecipeBookSettingsPhaseDropdown", scrollChild, "UIDropDownMenuTemplate")
phaseDropdown:SetPoint("LEFT", phaseLabel, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(phaseDropdown, 80)

local function PhaseDropdown_Init(self, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = "       All       "
    info.notCheckable = true
    info.func = function()
        RecipeBook._settingsPhase = nil
        UIDropDownMenu_SetText(phaseDropdown, "All")
        RecipeBook:RefreshRecipeList()
    end
    UIDropDownMenu_AddButton(info, level)

    for p = 1, 5 do
        info = UIDropDownMenu_CreateInfo()
        info.text = "         " .. tostring(p) .. "         "
        info.value = p
        info.notCheckable = true
        info.func = function()
            RecipeBook._settingsPhase = p
            UIDropDownMenu_SetText(phaseDropdown, tostring(p))
            RecipeBook:RefreshRecipeList()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end
UIDropDownMenu_Initialize(phaseDropdown, PhaseDropdown_Init)

local phaseDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
phaseDesc:SetPoint("TOPLEFT", phaseLabel, "BOTTOMLEFT", 0, -20)
phaseDesc:SetTextColor(0.5, 0.5, 0.5)
phaseDesc:SetWidth(CONTENT_WIDTH)
phaseDesc:SetWordWrap(true)
phaseDesc:SetText("Only show recipes available in this phase or earlier.")

-- ============================================================
-- Section: Characters
-- ============================================================

local filterSectionEnd = CreateSectionEnd(phaseDesc, 0)

local charHeader, charLine = CreateSectionHeader(filterSectionEnd, "Characters")

local levelLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
levelLabel:SetPoint("TOPLEFT", charLine, "BOTTOMLEFT", 0, -10)
levelLabel:SetText("Minimum Character Level:")

local levelSlider = CreateFrame("Slider", "RecipeBookSettingsLevelSlider", scrollChild, "OptionsSliderTemplate")
levelSlider:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 0, -14)
levelSlider:SetWidth(200)
levelSlider:SetMinMaxValues(1, 70)
levelSlider:SetValueStep(1)
levelSlider:SetObeyStepOnDrag(true)
_G["RecipeBookSettingsLevelSliderLow"]:SetText("1")
_G["RecipeBookSettingsLevelSliderHigh"]:SetText("70")

-- Slider track background for visibility
local sliderBg = levelSlider:CreateTexture(nil, "BACKGROUND")
sliderBg:SetPoint("LEFT", 4, 0)
sliderBg:SetPoint("RIGHT", -4, 0)
sliderBg:SetHeight(6)
sliderBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

local levelValueText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
levelValueText:SetPoint("LEFT", levelSlider, "RIGHT", 10, 0)

levelSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    levelValueText:SetText(tostring(value))
    if RecipeBookDB then
        RecipeBookDB.minCharLevel = value
    end
end)

local levelDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
levelDesc:SetPoint("TOPLEFT", levelSlider, "BOTTOMLEFT", 0, -8)
levelDesc:SetTextColor(0.5, 0.5, 0.5)
levelDesc:SetWidth(CONTENT_WIDTH)
levelDesc:SetWordWrap(true)
levelDesc:SetText("Characters below this level won't be saved or shown in the dropdown.")

-- Character Ignore List
local ignoreLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
ignoreLabel:SetPoint("TOPLEFT", levelDesc, "BOTTOMLEFT", 0, -16)
ignoreLabel:SetText("Character Ignore List:")

local ignoreDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
ignoreDesc:SetPoint("TOPLEFT", ignoreLabel, "BOTTOMLEFT", 0, -4)
ignoreDesc:SetTextColor(0.5, 0.5, 0.5)
ignoreDesc:SetWidth(CONTENT_WIDTH)
ignoreDesc:SetWordWrap(true)
ignoreDesc:SetText("Ignored characters won't appear in the dropdown or be updated on login.")

-- Container for ignore checkboxes
local ignoreContainer = CreateFrame("Frame", nil, scrollChild)
ignoreContainer:SetPoint("TOPLEFT", ignoreDesc, "BOTTOMLEFT", 0, -8)
ignoreContainer:SetWidth(CONTENT_WIDTH)
ignoreContainer:SetHeight(20)  -- will be resized dynamically

local ignoreCheckboxes = {}

local function RefreshIgnoreList()
    for _, cb in ipairs(ignoreCheckboxes) do
        cb:Hide()
    end

    local keys = RecipeBook:GetAllCharKeys()
    local ROW_H = 26
    local count = 0

    for i, key in ipairs(keys) do
        local cb = ignoreCheckboxes[i]
        if not cb then
            cb = CreateFrame("CheckButton", "RecipeBookIgnoreCB" .. i, ignoreContainer, "UICheckButtonTemplate")
            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            ignoreCheckboxes[i] = cb
        end

        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", ignoreContainer, "TOPLEFT", 0, -(i - 1) * ROW_H)

        local entry = RecipeBookDB and RecipeBookDB.characters and RecipeBookDB.characters[key]
        local charName = entry and entry.name or key:match("^([^-]+)") or key
        local realm = entry and entry.realm or key:match("-(.+)$") or ""
        local levelStr = entry and entry.level and (" L" .. entry.level) or ""

        cb.text:SetText(charName .. " - " .. realm .. levelStr)

        -- Check if ignored
        local isIgnored = RecipeBookDB and RecipeBookDB.ignoredCharacters
            and RecipeBookDB.ignoredCharacters[key]
        cb:SetChecked(isIgnored and true or false)

        cb._charKey = key
        cb:SetScript("OnClick", function(self)
            if not RecipeBookDB.ignoredCharacters then
                RecipeBookDB.ignoredCharacters = {}
            end
            RecipeBookDB.ignoredCharacters[self._charKey] = self:GetChecked() and true or nil
        end)

        cb:Show()
        count = count + 1
    end

    ignoreContainer:SetHeight(math.max(20, count * ROW_H))
end

-- ============================================================
-- Section: Reset
-- ============================================================

local charSectionEnd = CreateSectionEnd(ignoreContainer, 0)

local resetHeader, resetLine = CreateSectionHeader(charSectionEnd, "Reset")

local BUTTON_WIDTH = CONTENT_WIDTH
local BUTTON_HEIGHT = 22

-- Clear Profession Data
local clearProfBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
clearProfBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
clearProfBtn:SetPoint("TOPLEFT", resetLine, "BOTTOMLEFT", 0, -8)
clearProfBtn:SetText("Clear Profession Data")

local clearProfDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
clearProfDesc:SetPoint("TOPLEFT", clearProfBtn, "BOTTOMLEFT", 0, -2)
clearProfDesc:SetTextColor(0.5, 0.5, 0.5)
clearProfDesc:SetWidth(CONTENT_WIDTH)
clearProfDesc:SetWordWrap(true)
clearProfDesc:SetText("Clears all saved profession data for this character. Open your profession windows to rescan.")

StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_PROF"] = {
    text = "RecipeBook: Clear all saved profession data for this character?\n\nYou will need to reopen each profession window to rescan.",
    button1 = "Clear",
    button2 = CANCEL,
    OnAccept = function()
        RecipeBookCharDB.professionSkill = {}
        local myData = RecipeBook:GetMyCharData()
        if myData then
            wipe(myData.knownProfessions)
            wipe(myData.knownRecipes)
            if myData.professionSkill then
                wipe(myData.professionSkill)
            end
        end
        RecipeBookCharDB.selectedProfession = nil
        RecipeBook:ClearTeachesCache()
        RecipeBook:Print("Profession data cleared. Please reopen your profession windows.")
        if RecipeBook.SelectProfession then
            RecipeBook:SelectProfession(RecipeBook.PROFESSIONS[1].id)
        elseif RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
clearProfBtn:SetScript("OnClick", function()
    StaticPopup_Show("RECIPEBOOK_CONFIRM_CLEAR_PROF")
end)

-- Clear All Character Data
local clearCharBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
clearCharBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
clearCharBtn:SetPoint("TOPLEFT", clearProfDesc, "BOTTOMLEFT", 0, -10)
clearCharBtn:SetText("Clear All Character Data")

local clearCharDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
clearCharDesc:SetPoint("TOPLEFT", clearCharBtn, "BOTTOMLEFT", 0, -2)
clearCharDesc:SetTextColor(0.5, 0.5, 0.5)
clearCharDesc:SetWidth(CONTENT_WIDTH)
clearCharDesc:SetWordWrap(true)
clearCharDesc:SetText("Clears profession data and wishlists for this character.")

StaticPopupDialogs["RECIPEBOOK_CONFIRM_CLEAR_CHAR"] = {
    text = "RecipeBook: Clear all data for this character?\n\nThis will remove profession data and wishlists. You will need to reopen each profession window to rescan.",
    button1 = "Clear",
    button2 = CANCEL,
    OnAccept = function()
        RecipeBookCharDB.professionSkill = {}
        local myData = RecipeBook:GetMyCharData()
        if myData then
            wipe(myData.knownProfessions)
            wipe(myData.knownRecipes)
            if myData.professionSkill then
                wipe(myData.professionSkill)
            end
            if myData.wishlist then
                wipe(myData.wishlist)
            end
            if myData.ignored then
                wipe(myData.ignored)
            end
        end
        RecipeBookCharDB.selectedProfession = nil
        RecipeBook:ClearTeachesCache()
        RecipeBook:Print("All character data cleared. Please reopen your profession windows.")
        if RecipeBook.SelectProfession then
            RecipeBook:SelectProfession(RecipeBook.PROFESSIONS[1].id)
        elseif RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
clearCharBtn:SetScript("OnClick", function()
    StaticPopup_Show("RECIPEBOOK_CONFIRM_CLEAR_CHAR")
end)

-- Reset All
local resetAllBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
resetAllBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
resetAllBtn:SetPoint("TOPLEFT", clearCharDesc, "BOTTOMLEFT", 0, -10)
resetAllBtn:SetText("Reset All")

local resetAllDesc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
resetAllDesc:SetPoint("TOPLEFT", resetAllBtn, "BOTTOMLEFT", 0, -2)
resetAllDesc:SetTextColor(0.5, 0.5, 0.5)
resetAllDesc:SetWidth(CONTENT_WIDTH)
resetAllDesc:SetWordWrap(true)
resetAllDesc:SetText("Clears all profession, wishlist, and character data for the account and resets all settings to defaults.")

StaticPopupDialogs["RECIPEBOOK_CONFIRM_RESET_ALL"] = {
    text = "RecipeBook: Reset everything?\n\nThis will clear ALL profession data, wishlists, and character data across the account and reset all settings to defaults. This cannot be undone.",
    button1 = "Reset",
    button2 = CANCEL,
    OnAccept = function()
        -- Wipe all character data
        if RecipeBookDB.characters then
            wipe(RecipeBookDB.characters)
        end
        if RecipeBookDB.ignoredCharacters then
            wipe(RecipeBookDB.ignoredCharacters)
        end

        -- Reset account-wide settings to defaults
        RecipeBookDB.maxPhase = 5
        RecipeBookDB.currentPhase = 1
        RecipeBookDB.minCharLevel = 5
        RecipeBookDB.showTooltipInfo = true
        RecipeBookDB.minimap = { hide = false }

        -- Reset per-character settings to defaults
        RecipeBookCharDB.professionSkill = {}
        RecipeBookCharDB.selectedProfession = nil
        RecipeBookCharDB.hideKnown = false
        RecipeBookCharDB.hideUnlearnable = false
        RecipeBookCharDB.myFactionOnly = false
        RecipeBookCharDB.collapsedSources = {}
        RecipeBookCharDB.viewingChar = nil

        -- Re-create current character entry
        RecipeBook:GetMyCharData()

        RecipeBook:ClearTeachesCache()
        RecipeBook.myFactionOnly = false

        -- Restore minimap button
        if RecipeBook._dbIcon then
            RecipeBook._dbIcon:Show("RecipeBook")
        end

        RecipeBook:Print("All data and settings reset to defaults. Please reopen your profession windows.")

        -- Refresh settings panel if open
        if panel:IsShown() then
            panel:Hide()
            panel:Show()
        end

        if RecipeBook.SelectProfession then
            RecipeBook:SelectProfession(RecipeBook.PROFESSIONS[1].id)
        elseif RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
resetAllBtn:SetScript("OnClick", function()
    StaticPopup_Show("RECIPEBOOK_CONFIRM_RESET_ALL")
end)

-- ============================================================
-- Section: Guild Sharing
-- ============================================================

local resetSectionEnd = CreateSectionEnd(resetAllDesc, 0)

local guildHeader, guildLine = CreateSectionHeader(resetSectionEnd, "Guild Sharing")

local guildCheck = CreateFrame("CheckButton", "RecipeBookGuildShareCheck", scrollChild, "UICheckButtonTemplate")
guildCheck:SetPoint("TOPLEFT", guildLine, "BOTTOMLEFT", 0, -6)
guildCheck:SetSize(24, 24)
_G["RecipeBookGuildShareCheckText"]:SetText("Share my recipes with guild")
_G["RecipeBookGuildShareCheckText"]:SetFontObject("GameFontHighlight")
guildCheck:SetScript("OnClick", function(self)
    RecipeBookDB = RecipeBookDB or {}
    RecipeBookDB.guildSharingEnabled = self:GetChecked() and true or false
    RecipeBookDB.guildSharePrompted = true
    if RecipeBookDB.guildSharingEnabled
        and RecipeBook.GuildComm
        and RecipeBook.GuildComm.BroadcastHelloImmediate then
        RecipeBook.GuildComm.BroadcastHelloImmediate()
    end
end)

local guildHelp = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
guildHelp:SetPoint("TOPLEFT", guildCheck, "BOTTOMLEFT", 4, -2)
guildHelp:SetWidth(CONTENT_WIDTH - 8)
guildHelp:SetJustifyH("LEFT")
guildHelp:SetText("Guildmates running RecipeBook will see which recipes you can craft, so they can ask you for help.")

local whisperLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
whisperLabel:SetPoint("TOPLEFT", guildHelp, "BOTTOMLEFT", -4, -12)
whisperLabel:SetText("Whisper template (use |cffffd100{name}|r and |cffffd100{recipe}|r):")

local whisperBox = CreateFrame("EditBox", "RecipeBookWhisperTemplateBox", scrollChild, "InputBoxTemplate")
whisperBox:SetPoint("TOPLEFT", whisperLabel, "BOTTOMLEFT", 6, -6)
whisperBox:SetSize(CONTENT_WIDTH - 20, 22)
whisperBox:SetAutoFocus(false)
whisperBox:SetFontObject(ChatFontNormal)
whisperBox:SetScript("OnEnterPressed", function(self)
    RecipeBookDB.whisperTemplate = self:GetText()
    self:ClearFocus()
end)
whisperBox:SetScript("OnEditFocusLost", function(self)
    RecipeBookDB.whisperTemplate = self:GetText()
end)

local resetTemplateBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
resetTemplateBtn:SetSize(140, 22)
resetTemplateBtn:SetPoint("TOPLEFT", whisperBox, "BOTTOMLEFT", -4, -8)
resetTemplateBtn:SetText("Reset to default")
resetTemplateBtn:SetScript("OnClick", function()
    RecipeBookDB.whisperTemplate = RecipeBook.DEFAULT_WHISPER_TEMPLATE
    whisperBox:SetText(RecipeBook.DEFAULT_WHISPER_TEMPLATE)
end)

local forgetBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
forgetBtn:SetSize(160, 22)
forgetBtn:SetPoint("LEFT", resetTemplateBtn, "RIGHT", 8, 0)
forgetBtn:SetText("Forget current guild…")
StaticPopupDialogs["RECIPEBOOK_FORGET_GUILD"] = {
    text = "Forget cached data for guild '%s'?\n\nThis removes all stored members and recipes. They will re-sync if you're still in this guild.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(self, guildKey)
        if RecipeBookDB and RecipeBookDB.guilds then
            RecipeBookDB.guilds[guildKey] = nil
        end
        if RecipeBookCharDB and RecipeBookCharDB.viewingGuildKey == guildKey then
            RecipeBookCharDB.viewingGuildKey = nil
        end
        if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
            RecipeBook:RefreshRecipeList()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
forgetBtn:SetScript("OnClick", function()
    local gkey = RecipeBook.GuildComm and RecipeBook.GuildComm.CurrentGuildKey()
    if not gkey or not RecipeBookDB.guilds[gkey] then
        RecipeBook:Print("No cached guild to forget.")
        return
    end
    local dlg = StaticPopup_Show("RECIPEBOOK_FORGET_GUILD", gkey, nil, gkey)
    if dlg then dlg.data = gkey end
end)

-- ============================================================
-- Section: About
-- ============================================================

local guildSectionEnd = CreateSectionEnd(resetTemplateBtn, -4)

local aboutHeader, aboutLine = CreateSectionHeader(guildSectionEnd, "About")

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local versionStr = (getMetadata and getMetadata("RecipeBook", "Version")) or RecipeBook.VERSION or "?"
local aboutVersion = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
aboutVersion:SetPoint("TOPLEFT", aboutLine, "BOTTOMLEFT", 0, -8)
aboutVersion:SetText("Version: |cffffd100" .. versionStr .. "|r  " .. (RecipeBook.RELEASE_DATE or ""))

local aboutAuthor = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
aboutAuthor:SetPoint("TOPLEFT", aboutVersion, "BOTTOMLEFT", 0, -6)
aboutAuthor:SetText("Author: |cffffd100Breakbone - Dreamscythe|r")

local function CreateLinkRow(anchor, label, url)
    local row = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    row:SetText(label .. "  |cff69ccf0" .. url .. "|r")
    local btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    btn:SetSize(50, 18)
    btn:SetPoint("LEFT", row, "RIGHT", 6, 0)
    btn:SetText("Copy")
    btn:SetScript("OnClick", function()
        local editBox = ChatFrame1EditBox or ChatFrame1.editBox
        if editBox then
            editBox:Show()
            editBox:SetText("https://" .. url)
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end)
    return row
end

local aboutCurse = CreateLinkRow(aboutAuthor, "CurseForge:", "curseforge.com/wow/addons/recipebook")
local aboutGithub = CreateLinkRow(aboutCurse, "GitHub:", "github.com/breakbone-addons/RecipeBook")

-- Bottom spacer
local bottomSpacer = scrollChild:CreateTexture(nil, "ARTWORK")
bottomSpacer:SetPoint("TOPLEFT", aboutGithub, "BOTTOMLEFT", 0, -20)
bottomSpacer:SetSize(1, 1)

-- ============================================================
-- OnShow: refresh all control states
-- ============================================================

panel:SetScript("OnShow", function()
    -- Faction
    factionCheck:SetChecked(RecipeBook.myFactionOnly and true or false)

    -- Minimap button
    local minimapHidden = RecipeBookDB and RecipeBookDB.minimap and RecipeBookDB.minimap.hide
    minimapCheck:SetChecked(not minimapHidden)

    -- Tooltip info
    local showTooltip = not RecipeBookDB or RecipeBookDB.showTooltipInfo ~= false
    tooltipCheck:SetChecked(showTooltip)

    -- Phase
    local phase = RecipeBook._settingsPhase
    if phase then
        UIDropDownMenu_SetText(phaseDropdown, tostring(phase))
    else
        UIDropDownMenu_SetText(phaseDropdown, "All")
    end

    -- Level slider
    local minLevel = RecipeBookDB and RecipeBookDB.minCharLevel or 5
    levelSlider:SetValue(minLevel)
    levelValueText:SetText(tostring(minLevel))

    -- Character ignore list
    RefreshIgnoreList()

    -- Guild Sharing
    local shareOn = RecipeBookDB and RecipeBookDB.guildSharingEnabled == true
    guildCheck:SetChecked(shareOn)
    local tmpl = (RecipeBookDB and RecipeBookDB.whisperTemplate)
        or RecipeBook.DEFAULT_WHISPER_TEMPLATE or ""
    whisperBox:SetText(tmpl)
end)

-- ============================================================
-- Public API
-- ============================================================

function RecipeBook:ShowSettings()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

-- ============================================================
-- Interface Options proxy (Esc > Options > AddOns)
-- ============================================================

local optionsFrame = CreateFrame("Frame", "RecipeBookOptionsProxy")
optionsFrame.name = "RecipeBook"

local optionsBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
optionsBtn:SetSize(180, 28)
optionsBtn:SetPoint("TOPLEFT", 16, -16)
optionsBtn:SetText("Open Settings Window")
optionsBtn:SetScript("OnClick", function()
    RecipeBook:ShowSettings()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
end
