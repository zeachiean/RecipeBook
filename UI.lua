RecipeBook = RecipeBook or {}

local UI = RecipeBook.UI

-- State
local selectedProfession = nil
local selectedContinent = nil
local selectedZone = nil
local hideKnown = false
local myFactionOnly = true
local selectedPhase = nil -- nil = use maxPhase from settings
local searchText = ""
local listMode = "all" -- "all" | "wishlist" | "ignored"

-- References to controls that need updating
local hideKnownCheck = nil
local profDropdown = nil
local charDropdown = nil

-- Display name for a character key
local function CharDisplayName(charKey)
    if not charKey then return "?" end
    local entry = RecipeBookDB and RecipeBookDB.characters and RecipeBookDB.characters[charKey]
    if not entry then return charKey end
    return entry.name or charKey
end

function RecipeBook:CreateMainFrame()
    if self.mainFrame then return end

    local frame = CreateFrame("Frame", "RecipeBookMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(UI.FRAME_WIDTH, UI.FRAME_HEIGHT)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)

    -- Position: restore or center
    if RecipeBookCharDB and RecipeBookCharDB.windowPos and RecipeBookCharDB.windowPos.x then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", RecipeBookCharDB.windowPos.x, RecipeBookCharDB.windowPos.y)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if RecipeBookCharDB then
            local x, y = self:GetLeft(), self:GetTop() - UIParent:GetHeight()
            RecipeBookCharDB.windowPos = { x = x, y = y }
        end
    end)

    -- Close on ESC
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and self:IsShown() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Title bar
    local titleBar = frame:CreateTexture(nil, "ARTWORK")
    titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBar:SetSize(220, 64)
    titleBar:SetPoint("TOP", 0, 12)

    local title = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontTitle")
    title:SetPoint("TOP", titleBar, "TOP", 0, -14)
    title:SetText("RecipeBook")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    -- Status indicators (top right, single baseline)
    local statusY = -8
    local abStatus = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    abStatus:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -4, statusY)
    frame._abStatus = abStatus

    local ttStatus = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    ttStatus:SetPoint("TOPRIGHT", abStatus, "TOPLEFT", -8, 0)
    frame._ttStatus = ttStatus

    -- Entry count (below status line)
    local countText = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    countText:SetPoint("TOPRIGHT", abStatus, "BOTTOMRIGHT", 0, -1)
    countText:SetTextColor(0.5, 0.5, 0.5)
    frame._countText = countText

    -------------------------------------------------------------------
    -- Layout constants — all labels left-aligned, all dropdowns aligned
    -------------------------------------------------------------------
    local leftEdge = UI.PADDING + 10
    local ddLeft = leftEdge + UI.LABEL_WIDTH  -- where dropdowns start

    -------------------------------------------------------------------
    -- ROW 0: Character dropdown | Show (all/wishlist/ignored)
    -------------------------------------------------------------------
    local row0Y = -UI.HEADER_HEIGHT - 4

    local charLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    charLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, row0Y - 5)
    charLabel:SetText("Character:")
    charLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    charDropdown = CreateFrame("Frame", "RecipeBookCharDropdown", frame, "UIDropDownMenuTemplate")
    charDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", ddLeft - 16, row0Y + 4)
    UIDropDownMenu_SetWidth(charDropdown, UI.DROPDOWN_WIDTH)

    local function CharDropdown_Init(self, level)
        local myKey = RecipeBook:GetMyCharKey()
        local keys = RecipeBook:GetAllCharKeys()

        -- Always put current character first
        if myKey then
            local info = UIDropDownMenu_CreateInfo()
            info.text = CharDisplayName(myKey) .. " (this character)"
            info.notCheckable = true
            info.func = function()
                RecipeBook:SetViewedCharKey(myKey)
                UIDropDownMenu_SetText(charDropdown, CharDisplayName(myKey))
                selectedProfession = nil
                RecipeBookCharDB.selectedProfession = nil
                UIDropDownMenu_SetText(profDropdown, "Select...")
                RecipeBook:UpdateHideKnownState()
                RecipeBook:RefreshRecipeList()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        -- Other characters, sorted
        local hasOthers = false
        for _, key in ipairs(keys) do
            if key ~= myKey then
                if not hasOthers then
                    local header = UIDropDownMenu_CreateInfo()
                    header.text = "Other Characters"
                    header.isTitle = true
                    header.notCheckable = true
                    UIDropDownMenu_AddButton(header, level)
                    hasOthers = true
                end
                local info = UIDropDownMenu_CreateInfo()
                info.text = CharDisplayName(key)
                info.notCheckable = true
                info.func = function()
                    RecipeBook:SetViewedCharKey(key)
                    UIDropDownMenu_SetText(charDropdown, CharDisplayName(key))
                    selectedProfession = nil
                    UIDropDownMenu_SetText(profDropdown, "Select...")
                    RecipeBook:UpdateHideKnownState()
                    RecipeBook:RefreshRecipeList()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    UIDropDownMenu_Initialize(charDropdown, CharDropdown_Init)
    UIDropDownMenu_SetText(charDropdown, CharDisplayName(RecipeBook:GetViewedCharKey()))

    -- Show filter: All / Wishlist / Ignored (right side of row 0)
    local showDropdown = CreateFrame("Frame", "RecipeBookShowDropdown", frame, "UIDropDownMenuTemplate")
    showDropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PADDING + 8, row0Y + 4)
    UIDropDownMenu_SetWidth(showDropdown, 90)

    local showLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    showLabel:SetPoint("RIGHT", showDropdown, "LEFT", 12, 0)
    showLabel:SetPoint("TOP", charLabel, "TOP", 0, 0)
    showLabel:SetText("Show:")
    showLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local function ShowDropdown_Init(self, level)
        local modes = {
            { key = "all", label = "All" },
            { key = "wishlist", label = "Wishlist" },
            { key = "ignored", label = "Ignored" },
        }
        for _, m in ipairs(modes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = m.label
            info.notCheckable = true
            info.func = function()
                listMode = m.key
                UIDropDownMenu_SetText(showDropdown, m.label)
                RecipeBook:RefreshRecipeList()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(showDropdown, ShowDropdown_Init)
    UIDropDownMenu_SetText(showDropdown, "All")

    -------------------------------------------------------------------
    -- ROW 1: Profession dropdown | My Faction | Hide Known/Ignored
    -------------------------------------------------------------------
    local row1Y = row0Y - 26

    local profLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    profLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, row1Y - 5)
    profLabel:SetText("Profession:")
    profLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    profDropdown = CreateFrame("Frame", "RecipeBookProfDropdown", frame, "UIDropDownMenuTemplate")
    profDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", ddLeft - 16, row1Y + 4)
    UIDropDownMenu_SetWidth(profDropdown, UI.DROPDOWN_WIDTH)

    local function ProfDropdown_Init(self, level)
        local knownProfs = {}
        local unknownProfs = {}
        for _, prof in ipairs(RecipeBook.PROFESSIONS) do
            if RecipeBook:IsProfessionKnown(prof.id) then
                knownProfs[#knownProfs + 1] = prof
            else
                unknownProfs[#unknownProfs + 1] = prof
            end
        end

        -- "My Professions" header
        if #knownProfs > 0 then
            local header = UIDropDownMenu_CreateInfo()
            header.text = "My Professions"
            header.isTitle = true
            header.notCheckable = true
            UIDropDownMenu_AddButton(header, level)

            for _, prof in ipairs(knownProfs) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = prof.name
                info.value = prof.id
                info.notCheckable = true
                info.func = function()
                    RecipeBook:SelectProfession(prof.id)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- "Other" header
        if #unknownProfs > 0 then
            local header = UIDropDownMenu_CreateInfo()
            header.text = "Other"
            header.isTitle = true
            header.notCheckable = true
            UIDropDownMenu_AddButton(header, level)

            for _, prof in ipairs(unknownProfs) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = prof.name
                info.value = prof.id
                info.notCheckable = true
                info.func = function()
                    RecipeBook:SelectProfession(prof.id)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    UIDropDownMenu_Initialize(profDropdown, ProfDropdown_Init)

    -- Restore selected profession
    if RecipeBookCharDB and RecipeBookCharDB.selectedProfession then
        selectedProfession = RecipeBookCharDB.selectedProfession
        local name = RecipeBook.PROFESSION_NAMES[selectedProfession]
        UIDropDownMenu_SetText(profDropdown, name or "Select...")
    else
        UIDropDownMenu_SetText(profDropdown, "Select...")
    end

    -- My Faction checkbox — vertically centered with dropdown
    local factionCheck = CreateFrame("CheckButton", "RecipeBookFactionFilter", frame, "UICheckButtonTemplate")
    factionCheck:SetPoint("LEFT", profDropdown, "RIGHT", -8, 0)
    factionCheck:SetPoint("TOP", profLabel, "TOP", 0, 5)
    factionCheck:SetSize(20, 20)
    factionCheck:SetChecked(true)
    myFactionOnly = true
    _G["RecipeBookFactionFilterText"]:SetText("My Faction")
    _G["RecipeBookFactionFilterText"]:SetFontObject("RecipeBookFontSmall")
    factionCheck:SetScript("OnClick", function(self)
        myFactionOnly = self:GetChecked()
        RecipeBook:RefreshRecipeList()
    end)

    -- Hide Known/Ignored checkbox (pinned to right side)
    hideKnownCheck = CreateFrame("CheckButton", "RecipeBookHideKnown", frame, "UICheckButtonTemplate")
    hideKnownCheck:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PADDING - 110, 0)
    hideKnownCheck:SetPoint("TOP", profLabel, "TOP", 0, 5)
    hideKnownCheck:SetSize(20, 20)
    _G["RecipeBookHideKnownText"]:SetText("Hide Known/Ignored")
    _G["RecipeBookHideKnownText"]:SetFontObject("RecipeBookFontSmall")
    hideKnownCheck:SetScript("OnClick", function(self)
        hideKnown = self:GetChecked()
        RecipeBookCharDB.hideKnown = hideKnown
        RecipeBook:RefreshRecipeList()
    end)
    frame._hideKnownCheck = hideKnownCheck

    -- Initialize Hide Known state
    self:UpdateHideKnownState()

    -------------------------------------------------------------------
    -- ROW 2: Continent dropdown + Auto
    -------------------------------------------------------------------
    local row2Y = row1Y - 26

    local contLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    contLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, row2Y - 5)
    contLabel:SetText("Continent:")
    contLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local continentDropdown = CreateFrame("Frame", "RecipeBookContinentDropdown", frame, "UIDropDownMenuTemplate")
    continentDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", ddLeft - 16, row2Y + 4)
    UIDropDownMenu_SetWidth(continentDropdown, UI.DROPDOWN_WIDTH)

    -- Continent Auto checkbox
    local contAutoCheck = CreateFrame("CheckButton", "RecipeBookContAutoFilter", frame, "UICheckButtonTemplate")
    contAutoCheck:SetPoint("LEFT", continentDropdown, "RIGHT", -8, 0)
    contAutoCheck:SetPoint("TOP", contLabel, "TOP", 0, 5)
    contAutoCheck:SetSize(20, 20)
    contAutoCheck:SetChecked(false)
    _G["RecipeBookContAutoFilterText"]:SetText("Auto")
    _G["RecipeBookContAutoFilterText"]:SetFontObject("RecipeBookFontSmall")

    -- Phase dropdown (right edge aligned with search box below)
    -- Search box right edge is at frame RIGHT - PADDING - 8
    -- UIDropDownMenu has ~8px right padding, so offset by that to align visually
    local phaseDropdown = CreateFrame("Frame", "RecipeBookPhaseDropdown", frame, "UIDropDownMenuTemplate")
    phaseDropdown:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PADDING + 8, row2Y + 4)
    UIDropDownMenu_SetWidth(phaseDropdown, 60)

    local phaseLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    phaseLabel:SetPoint("RIGHT", phaseDropdown, "LEFT", 12, 0)
    phaseLabel:SetPoint("TOP", contLabel, "TOP", 0, 0)
    phaseLabel:SetText("Phase:")
    phaseLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    -- Initial continent text
    UIDropDownMenu_SetText(continentDropdown, "All")

    local function ContinentDropdown_Init(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Continents"
        info.notCheckable = true
        info.func = function()
            selectedContinent = nil
            selectedZone = nil
            contAutoCheck:SetChecked(false)
            UIDropDownMenu_SetText(continentDropdown, "All")
            UIDropDownMenu_SetText(frame._zoneDropdown, "All")
            if frame._zoneAutoCheck then frame._zoneAutoCheck:SetChecked(false) end
            RecipeBook:RefreshRecipeList()
        end
        UIDropDownMenu_AddButton(info, level)

        local continents = RecipeBook:GetContinents()
        for _, name in ipairs(continents) do
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.notCheckable = true
            info.func = function()
                selectedContinent = name
                selectedZone = nil
                contAutoCheck:SetChecked(false)
                UIDropDownMenu_SetText(continentDropdown, name)
                UIDropDownMenu_SetText(frame._zoneDropdown, "All")
                if frame._zoneAutoCheck then frame._zoneAutoCheck:SetChecked(false) end
                RecipeBook:RefreshRecipeList()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(continentDropdown, ContinentDropdown_Init)

    contAutoCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            selectedContinent = "Auto"
            local rZone = RecipeBook:GetCurrentZoneName()
            local rCont = rZone and RecipeBook:GetContinentForZone(rZone)
            UIDropDownMenu_SetText(continentDropdown, rCont or "All")
        else
            selectedContinent = nil
            UIDropDownMenu_SetText(continentDropdown, "All")
        end
        RecipeBook:RefreshRecipeList()
    end)

    frame._continentDropdown = continentDropdown

    -------------------------------------------------------------------
    -- ROW 3: Zone dropdown + Auto, Phase dropdown (right)
    -------------------------------------------------------------------
    local row3Y = row2Y - 26

    local zoneLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    zoneLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftEdge, row3Y - 5)
    zoneLabel:SetText("Zone:")
    zoneLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local zoneDropdown = CreateFrame("Frame", "RecipeBookZoneDropdown", frame, "UIDropDownMenuTemplate")
    zoneDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", ddLeft - 16, row3Y + 4)
    UIDropDownMenu_SetWidth(zoneDropdown, UI.DROPDOWN_WIDTH)
    UIDropDownMenu_SetText(zoneDropdown, "All")
    frame._zoneDropdown = zoneDropdown

    -- Zone Auto checkbox
    local zoneAutoCheck = CreateFrame("CheckButton", "RecipeBookZoneAutoFilter", frame, "UICheckButtonTemplate")
    zoneAutoCheck:SetPoint("LEFT", zoneDropdown, "RIGHT", -8, 0)
    zoneAutoCheck:SetPoint("TOP", zoneLabel, "TOP", 0, 5)
    zoneAutoCheck:SetSize(20, 20)
    zoneAutoCheck:SetChecked(false)
    _G["RecipeBookZoneAutoFilterText"]:SetText("Auto")
    _G["RecipeBookZoneAutoFilterText"]:SetFontObject("RecipeBookFontSmall")
    frame._zoneAutoCheck = zoneAutoCheck

    local function ZoneDropdown_Init(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Zones"
        info.notCheckable = true
        info.func = function()
            selectedZone = nil
            zoneAutoCheck:SetChecked(false)
            UIDropDownMenu_SetText(zoneDropdown, "All")
            RecipeBook:RefreshRecipeList()
        end
        UIDropDownMenu_AddButton(info, level)

        local effectiveContinent = selectedContinent
        if effectiveContinent == "Auto" then
            local rZone = RecipeBook:GetCurrentZoneName()
            if rZone then
                effectiveContinent = RecipeBook:GetContinentForZone(rZone)
            end
        end

        local zones
        if effectiveContinent then
            zones = RecipeBook:GetZonesForContinent(effectiveContinent)
        elseif selectedProfession then
            zones = RecipeBook:GetZonesWithSources(selectedProfession)
        else
            zones = {}
        end

        for _, name in ipairs(zones) do
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.notCheckable = true
            info.func = function()
                selectedZone = name
                zoneAutoCheck:SetChecked(false)
                UIDropDownMenu_SetText(zoneDropdown, name)
                if not selectedContinent or selectedContinent == "Auto" then
                    local cont = RecipeBook:GetContinentForZone(name)
                    if cont then
                        selectedContinent = cont
                        contAutoCheck:SetChecked(false)
                        UIDropDownMenu_SetText(continentDropdown, cont)
                    end
                end
                RecipeBook:RefreshRecipeList()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(zoneDropdown, ZoneDropdown_Init)

    zoneAutoCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            selectedZone = "Auto"
            local rZone = RecipeBook:GetCurrentZoneName()
            UIDropDownMenu_SetText(zoneDropdown, rZone or "All")
            if not contAutoCheck:GetChecked() then
                contAutoCheck:SetChecked(true)
                selectedContinent = "Auto"
                local rCont = rZone and RecipeBook:GetContinentForZone(rZone)
                UIDropDownMenu_SetText(continentDropdown, rCont or "All")
            end
        else
            selectedZone = nil
            UIDropDownMenu_SetText(zoneDropdown, "All")
        end
        RecipeBook:RefreshRecipeList()
    end)

    -- Search box (pinned to right side of row 3, aligned to phase dropdown above)
    local searchBox = CreateFrame("EditBox", "RecipeBookSearchBox", frame, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PADDING - 8, 0)
    searchBox:SetPoint("TOP", zoneLabel, "TOP", 0, 5)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    searchBox:SetFontObject("RecipeBookFontHighlight")
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = strtrim(self:GetText() or "")
        RecipeBook:RefreshRecipeList()
    end)
    frame._searchBox = searchBox

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)
    frame._phaseDropdown = phaseDropdown

    local function PhaseDropdown_Init(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All"
        info.notCheckable = true
        info.func = function()
            selectedPhase = nil
            UIDropDownMenu_SetText(phaseDropdown, "All")
            RecipeBook:RefreshRecipeList()
        end
        UIDropDownMenu_AddButton(info, level)

        for p = 1, 5 do
            info = UIDropDownMenu_CreateInfo()
            info.text = tostring(p)
            info.value = p
            info.notCheckable = true
            info.func = function()
                selectedPhase = p
                UIDropDownMenu_SetText(phaseDropdown, tostring(p))
                RecipeBook:RefreshRecipeList()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(phaseDropdown, PhaseDropdown_Init)

    -- Default phase to current server phase
    local currentPhase = RecipeBookDB and RecipeBookDB.currentPhase or 1
    selectedPhase = currentPhase
    UIDropDownMenu_SetText(phaseDropdown, tostring(currentPhase))

    -------------------------------------------------------------------
    -- SCROLL FRAME (main content area)
    -------------------------------------------------------------------
    local topBarHeight = UI.HEADER_HEIGHT + 110

    local listPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PADDING, -topBarHeight)
    listPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PADDING, UI.PADDING)
    listPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.8)

    -- Column headers
    -- Column headers — we create an invisible reference row using the same
    -- pooled-row layout so headers are pixel-perfect with data rows.
    -- scrollFrame is at listPanel TOPLEFT +4, -18
    -- data rows: scrollChild TOPLEFT +14 indent, row inner: name +4, skill +214+4, source +248+8
    -- Use a hidden frame at the header Y to anchor font strings to.
    local hdrRef = CreateFrame("Frame", nil, listPanel)
    hdrRef:SetHeight(16)
    hdrRef:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 4 + 14, -2)   -- match scroll inset + row indent
    hdrRef:SetPoint("RIGHT", listPanel, "RIGHT", -30, 0)           -- match scrollChild width

    local headerName = listPanel:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    headerName:SetPoint("LEFT", hdrRef, "LEFT", 4, 0)
    headerName:SetText("Recipe")
    headerName:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local headerSkill = listPanel:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    headerSkill:SetPoint("LEFT", hdrRef, "LEFT", 218, 0)
    headerSkill:SetWidth(30)
    headerSkill:SetJustifyH("RIGHT")
    headerSkill:SetText("Skill")
    headerSkill:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local headerSource = listPanel:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    headerSource:SetPoint("LEFT", hdrRef, "LEFT", 256, 0)
    headerSource:SetText("Source")
    headerSource:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local headerWP = listPanel:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    headerWP:SetPoint("RIGHT", hdrRef, "RIGHT", -2, 0)
    headerWP:SetJustifyH("RIGHT")
    headerWP:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)
    if RecipeBook:HasAddressBook() and RecipeBook:HasTomTom() then
        headerWP:SetText("WP")
    else
        headerWP:SetText("")
    end

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "RecipeBookScrollFrame", listPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 4, -18)
    scrollFrame:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(listPanel:GetWidth() - 30)
    scrollFrame:SetScrollChild(scrollChild)

    frame._listPanel = listPanel
    frame._scrollFrame = scrollFrame
    frame._scrollChild = scrollChild

    -- Update status indicators
    if RecipeBook:HasTomTom() then
        ttStatus:SetText("|cff00ff00TomTom|r")
    else
        ttStatus:SetText("|cffff0000No TomTom|r")
    end
    if RecipeBook:HasAddressBook() then
        abStatus:SetText("|cff00ff00AddressBook|r")
    else
        abStatus:SetText("|cffff6600No AddressBook|r")
    end

    self.mainFrame = frame
    frame:Hide()
end

-- Select a profession and update UI accordingly
function RecipeBook:SelectProfession(profID)
    selectedProfession = profID
    RecipeBookCharDB.selectedProfession = profID
    UIDropDownMenu_SetText(profDropdown, self.PROFESSION_NAMES[profID] or "Select...")
    self:UpdateHideKnownState()
    self:RefreshRecipeList()
end

-- Update Hide Known checkbox state based on selected profession
function RecipeBook:UpdateHideKnownState()
    if not hideKnownCheck then return end

    if selectedProfession and self:IsProfessionKnown(selectedProfession) then
        -- Known profession: enable checkbox, default to checked
        hideKnownCheck:Enable()
        _G["RecipeBookHideKnownText"]:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

        -- Default to hideKnown=true for known professions unless explicitly set
        if RecipeBookCharDB.hideKnown then
            hideKnownCheck:SetChecked(true)
            hideKnown = true
        else
            hideKnownCheck:SetChecked(RecipeBookCharDB.hideKnown or false)
            hideKnown = RecipeBookCharDB.hideKnown or false
        end
    else
        -- Unknown profession: disable checkbox, uncheck
        hideKnownCheck:Disable()
        _G["RecipeBookHideKnownText"]:SetTextColor(UI.COLOR_DISABLED.r, UI.COLOR_DISABLED.g, UI.COLOR_DISABLED.b)
        hideKnownCheck:SetChecked(false)
        hideKnown = false
    end
end

-- Called when zone changes (for auto-filter)
function RecipeBook:OnZoneChanged()
    if not self.mainFrame then return end

    local contDD = self.mainFrame._continentDropdown
    local zoneDD = self.mainFrame._zoneDropdown
    local contAuto = _G["RecipeBookContAutoFilter"]
    local zoneAuto = self.mainFrame._zoneAutoCheck

    if contAuto and contAuto:GetChecked() then
        local rZone = self:GetCurrentZoneName()
        local rCont = rZone and self:GetContinentForZone(rZone)
        UIDropDownMenu_SetText(contDD, rCont or "All")
    end

    if zoneAuto and zoneAuto:GetChecked() then
        local rZone = self:GetCurrentZoneName()
        UIDropDownMenu_SetText(zoneDD, rZone or "All")
    end

    if (contAuto and contAuto:GetChecked()) or (zoneAuto and zoneAuto:GetChecked()) then
        self:RefreshRecipeList()
    end
end

-- Get current filter state (used by UIRender)
function RecipeBook:GetFilterState()
    local filterContinent = selectedContinent
    local filterZone = selectedZone

    if filterContinent == "Auto" or filterZone == "Auto" then
        local rZone = self:GetCurrentZoneName()
        if filterContinent == "Auto" then
            filterContinent = rZone and self:GetContinentForZone(rZone)
        end
        if filterZone == "Auto" then
            filterZone = rZone
        end
    end

    -- Detect player faction
    local playerFaction = nil
    if myFactionOnly then
        local _, faction = UnitFactionGroup("player")
        playerFaction = faction  -- "Alliance" or "Horde"
    end

    return {
        professionID = selectedProfession,
        continent = filterContinent,
        zone = filterZone,
        hideKnown = hideKnown,
        maxPhase = selectedPhase or (RecipeBookDB and RecipeBookDB.maxPhase) or 5,
        playerFaction = playerFaction,
        searchText = searchText ~= "" and strlower(searchText) or nil,
        listMode = listMode,
        viewedCharKey = self:GetViewedCharKey(),
    }
end
