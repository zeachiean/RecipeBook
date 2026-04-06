RecipeBook = RecipeBook or {}

-- UI Constants
RecipeBook.UI = RecipeBook.UI or {}
local UI = RecipeBook.UI

UI.FRAME_WIDTH = 540
UI.FRAME_HEIGHT = 566
UI.ROW_HEIGHT = 18
UI.HEADER_HEIGHT = 30
UI.PADDING = 8
UI.SCROLL_STEP = UI.ROW_HEIGHT * 3
UI.LABEL_WIDTH = 60       -- Width for labels column (Profession:, Continent:, Zone:)
UI.DROPDOWN_WIDTH = 130    -- Width for dropdown menus

-- Colors
UI.COLOR_HEADER = { r = 1.0, g = 0.82, b = 0.0 }
UI.COLOR_SELECTED = { r = 0.2, g = 0.4, b = 0.8, a = 0.4 }
UI.COLOR_HOVER = { r = 0.3, g = 0.3, b = 0.3, a = 0.3 }
UI.COLOR_NORMAL = { r = 1.0, g = 1.0, b = 1.0 }
UI.COLOR_KNOWN = { r = 0.5, g = 0.5, b = 0.5 }
UI.COLOR_SKILL = { r = 0.7, g = 0.7, b = 0.7 }
UI.COLOR_SOURCE = { r = 0.6, g = 0.8, b = 1.0 }
UI.COLOR_ZONE = { r = 0.7, g = 0.7, b = 0.7 }
UI.COLOR_WORLDDROP = { r = 0.9, g = 0.6, b = 0.2 }
UI.COLOR_WAYPOINT = { r = 0.3, g = 1.0, b = 0.3 }
UI.COLOR_DISABLED = { r = 0.4, g = 0.4, b = 0.4 }
UI.COLOR_WISHLIST = { r = 1.0, g = 0.85, b = 0.2 }   -- gold star
UI.COLOR_IGNORED  = { r = 0.45, g = 0.45, b = 0.45 } -- dim grey

-- WoW item quality colors
UI.QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },  -- Poor (gray)
    [1] = { r = 1.0,  g = 1.0,  b = 1.0  },  -- Common (white)
    [2] = { r = 0.12, g = 1.0,  b = 0.0  },  -- Uncommon (green)
    [3] = { r = 0.0,  g = 0.44, b = 0.87 },  -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- Epic (purple)
    [5] = { r = 1.0,  g = 0.50, b = 0.0  },  -- Legendary (orange)
}

-- Expand/collapse icons (same as AddressBook)
UI.ICON_EXPAND = "Interface\\Buttons\\UI-PlusButton-UP"
UI.ICON_COLLAPSE = "Interface\\Buttons\\UI-MinusButton-UP"

-- Waypoint arrow icon
UI.ICON_ARROW = "Interface\\Buttons\\UI-MicroStream-Green"

-- Frame pool for recipe rows
RecipeBook.framePool = {}

-- Get or create a pooled row frame
function RecipeBook:GetPooledRow(parent)
    local row = tremove(self.framePool)
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetHeight(UI.ROW_HEIGHT)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Highlight texture
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(UI.COLOR_HOVER.r, UI.COLOR_HOVER.g, UI.COLOR_HOVER.b, UI.COLOR_HOVER.a)
        row._highlight = highlight

        -- Recipe name text (left side)
        local nameText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontHighlight")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetWidth(210)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        row._nameText = nameText

        -- Skill level text
        local skillText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        skillText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        skillText:SetWidth(30)
        skillText:SetJustifyH("RIGHT")
        skillText:SetWordWrap(false)
        skillText:SetTextColor(UI.COLOR_SKILL.r, UI.COLOR_SKILL.g, UI.COLOR_SKILL.b)
        row._skillText = skillText

        -- Source count text (#)
        local countText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        countText:SetPoint("LEFT", skillText, "RIGHT", 8, 0)
        countText:SetWidth(26)
        countText:SetJustifyH("RIGHT")
        countText:SetWordWrap(false)
        countText:SetTextColor(UI.COLOR_SKILL.r, UI.COLOR_SKILL.g, UI.COLOR_SKILL.b)
        row._countText = countText

        -- Drop rate text (%) — anchored first so source can butt up against it
        local rateText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        rateText:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        rateText:SetWidth(40)
        rateText:SetJustifyH("RIGHT")
        rateText:SetWordWrap(false)
        rateText:SetTextColor(UI.COLOR_SKILL.r, UI.COLOR_SKILL.g, UI.COLOR_SKILL.b)
        row._rateText = rateText

        -- Source text (NPC name + zone)
        local sourceText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        sourceText:SetPoint("LEFT", countText, "RIGHT", 8, 0)
        sourceText:SetPoint("RIGHT", rateText, "LEFT", -4, 0)
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(false)
        sourceText:SetNonSpaceWrap(false)
        sourceText:SetTextColor(UI.COLOR_SOURCE.r, UI.COLOR_SOURCE.g, UI.COLOR_SOURCE.b)
        row._sourceText = sourceText

        -- Waypoint arrow texture (right edge, rotated 45° for up-right)
        local wpArrow = row:CreateTexture(nil, "OVERLAY")
        wpArrow:SetSize(16, 16)
        wpArrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        wpArrow:SetTexture(UI.ICON_ARROW)
        wpArrow:SetRotation(math.rad(135))
        wpArrow:Hide()
        row._wpArrow = wpArrow
    end

    row:SetParent(parent)
    row:Show()
    return row
end

-- Return a row to the pool
function RecipeBook:RecycleRow(row)
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row._recipeID = nil
    row._profID = nil
    row._sourceType = nil
    row._sourceID = nil
    row._isHeader = nil
    row._npcName = nil
    row._zoneName = nil
    row._isWorldDrop = nil
    row._headerSrcType = nil
    if row._wpArrow then row._wpArrow:Hide() end
    if row._toggleIcon then row._toggleIcon:Hide() end
    self.framePool[#self.framePool + 1] = row
end

-- Get or create a header row (source type header, collapsible)
function RecipeBook:GetHeaderRow(parent)
    local row = self:GetPooledRow(parent)
    row._isHeader = true
    row._nameText:SetFontObject("RecipeBookFontNormal")
    row._nameText:SetWidth(0)
    row._nameText:ClearAllPoints()
    row._nameText:SetPoint("LEFT", row, "LEFT", 18, 0)
    row._nameText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row._skillText:SetText("")
    if row._countText then row._countText:SetText("") end
    if row._rateText then row._rateText:SetText("") end
    row._sourceText:SetText("")
    row._wpArrow:Hide()

    -- Toggle icon (expand/collapse)
    if not row._toggleIcon then
        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row._toggleIcon = icon
    end
    row._toggleIcon:Show()

    return row
end

-- Create a standard button
function RecipeBook:CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 80, height or 22)
    btn:SetText(text)
    return btn
end
