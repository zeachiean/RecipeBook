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
-- Section: Filters
-- ============================================================

local topAnchor = CreateFrame("Frame", nil, scrollChild)
topAnchor:SetSize(1, 1)
topAnchor:SetPoint("TOPLEFT", 12, 8)

local filterHeader, filterLine = CreateSectionHeader(topAnchor, "Filters")

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
-- Section: About
-- ============================================================

local charSectionEnd = CreateSectionEnd(ignoreContainer, 0)

local aboutHeader, aboutLine = CreateSectionHeader(charSectionEnd, "About")

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
