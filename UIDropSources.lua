RecipeBook = RecipeBook or {}

local UI = RecipeBook.UI

-- ----------------------------------------------------------------------------
-- Sources popup: shows every source (trainer, vendor, drop, quest, object, …)
-- for a given recipe and lets the user pick one as an AddressBook waypoint.
-- ----------------------------------------------------------------------------

local POPUP_WIDTH = 440
local POPUP_HEIGHT = 320
local ROW_H = 18

local popupFrame = nil
local popupRows = {}   -- active rows displayed in the scroll child
local rowPool = {}

-- Sort priority across all source types (lower = earlier)
local TYPE_ORDER = {
    trainer = 1, vendor = 2, quest = 3,
    drop = 4, pickpocket = 5,
    object = 6, item = 7, fishing = 8, unique = 9,
}

-- Gather every source for a recipe (trainer, vendor, drop, quest, …)
local function CollectAllSources(profID, recipeID, factionFilter)
    local sources = RecipeBook.sourceDB
        and RecipeBook.sourceDB[profID]
        and RecipeBook.sourceDB[profID][recipeID]
    if not sources then return {} end

    local list = {}

    local function addNPC(srcType, npcID, rate, extra)
        local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
        list[#list + 1] = {
            sourceType = srcType,
            npcID = npcID,
            name = RecipeBook:GetNPCName(npcID),
            zone = RecipeBook:GetFirstZoneForNPC(npcID),
            level = npc and npc.level,
            faction = npc and npc.faction,
            dropRate = type(rate) == "number" and rate or nil,
            extra = extra,
        }
    end

    -- Helper: should this NPC be shown given the faction filter?
    -- Trainers/vendors are faction-gated; drops/pickpockets are not.
    local function npcPassesFaction(npcID, srcType)
        if not factionFilter then return true end
        if srcType == "drop" or srcType == "pickpocket" then return true end
        local npc = RecipeBook.npcDB and RecipeBook.npcDB[npcID]
        if not npc or not npc.faction then return true end  -- neutral
        return npc.faction == factionFilter
    end

    for srcType, srcData in pairs(sources) do
        if srcType == "trainer" or srcType == "vendor"
            or srcType == "drop" or srcType == "pickpocket" then
            for npcID, val in pairs(srcData) do
                if npcPassesFaction(npcID, srcType) then
                    if srcType == "vendor" and type(val) == "table" then
                        local cost = val.cost
                        if cost then
                            cost = cost:gsub("gld", "g "):gsub("svr", "s "):gsub("cpr", "c")
                        end
                        addNPC(srcType, npcID, nil, cost)
                    else
                        addNPC(srcType, npcID, val, nil)
                    end
                end
            end
        elseif srcType == "quest" then
            for questID in pairs(srcData) do
                local q = RecipeBook.questDB and RecipeBook.questDB[questID]
                -- Skip quests locked to the opposite faction.
                if factionFilter and q and q.faction and q.faction ~= factionFilter then
                    -- filtered out
                else
                    local label = q and q.name or ("Quest #" .. questID)
                    local extra = q and q.level and ("Level " .. q.level) or nil
                    local zone = nil
                    local npcID = q and q.startNPC
                    if npcID then
                        zone = RecipeBook:GetFirstZoneForNPC(npcID)
                    end
                    list[#list + 1] = {
                        sourceType = "quest",
                        questID = questID,
                        npcID = npcID,
                        name = label,
                        zone = zone,
                        faction = q and q.faction,
                        extra = extra,
                    }
                end
            end
        elseif srcType == "object" then
            for objID in pairs(srcData) do
                list[#list + 1] = {
                    sourceType = "object",
                    objectID = objID,
                    name = RecipeBook:GetObjectName(objID),
                    zone = RecipeBook:GetFirstZoneForObject(objID),
                }
            end
        elseif srcType == "unique" then
            for _, uid in ipairs(srcData) do
                if uid == 0 then
                    local craftedBy = RecipeBook:FindCraftingProfession(profID, recipeID)
                    local label = craftedBy and RecipeBook.PROFESSION_NAMES[craftedBy] or "Crafted"
                    list[#list + 1] = { sourceType = "unique", name = label }
                else
                    list[#list + 1] = {
                        sourceType = "unique",
                        uniqueID = uid,
                        name = RecipeBook:GetUniqueName(uid),
                        zone = RecipeBook:GetFirstZoneForUnique(uid),
                    }
                end
            end
        elseif srcType == "fishing" then
            for areaID in pairs(srcData) do
                list[#list + 1] = {
                    sourceType = "fishing",
                    areaID = areaID,
                    name = "Fishing",
                    zone = RecipeBook:GetZoneNameForAreaID(areaID),
                }
            end
        elseif srcType == "item" then
            for itemID in pairs(srcData) do
                list[#list + 1] = {
                    sourceType = "item",
                    itemID = itemID,
                    name = RecipeBook.itemNames[itemID] or ("Item #" .. itemID),
                }
            end
        end
    end

    -- Sort by source type, then by drop rate desc (for drops), then by name.
    table.sort(list, function(a, b)
        local ta = TYPE_ORDER[a.sourceType] or 99
        local tb = TYPE_ORDER[b.sourceType] or 99
        if ta ~= tb then return ta < tb end
        local ra = a.dropRate or -1
        local rb = b.dropRate or -1
        if ra ~= rb then return ra > rb end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- Expose for testing
RecipeBook.CollectAllSources = CollectAllSources

-- Does a recipe have any sources listed?
function RecipeBook:RecipeHasAnySources(profID, recipeID)
    local sources = self.sourceDB
        and self.sourceDB[profID]
        and self.sourceDB[profID][recipeID]
    if not sources then return false end
    for _ in pairs(sources) do return true end
    return false
end

-- Back-compat alias (old name) — true if any drop/pickpocket sources exist
function RecipeBook:RecipeHasDropSources(profID, recipeID)
    return self:RecipeHasAnySources(profID, recipeID)
end

-- ---------- Row management ----------

local function GetPopupRow(parent)
    local row = tremove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(UI.COLOR_HOVER.r, UI.COLOR_HOVER.g, UI.COLOR_HOVER.b, UI.COLOR_HOVER.a)

        local rateText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        rateText:SetPoint("RIGHT", row, "RIGHT", -24, 0)
        rateText:SetWidth(64)
        rateText:SetJustifyH("RIGHT")
        rateText:SetWordWrap(false)
        rateText:SetNonSpaceWrap(false)
        rateText:SetTextColor(UI.COLOR_SKILL.r, UI.COLOR_SKILL.g, UI.COLOR_SKILL.b)
        row._rateText = rateText

        local nameText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontHighlight")
        nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
        nameText:SetWidth(155)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        row._nameText = nameText

        local zoneText = row:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
        zoneText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
        zoneText:SetPoint("RIGHT", rateText, "LEFT", -8, 0)
        zoneText:SetJustifyH("LEFT")
        zoneText:SetWordWrap(false)
        zoneText:SetNonSpaceWrap(false)
        zoneText:SetTextColor(UI.COLOR_ZONE.r, UI.COLOR_ZONE.g, UI.COLOR_ZONE.b)
        row._zoneText = zoneText

        local wpArrow = row:CreateTexture(nil, "OVERLAY")
        wpArrow:SetSize(14, 14)
        wpArrow:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        wpArrow:SetTexture(UI.ICON_ARROW)
        wpArrow:SetRotation(math.rad(135))
        wpArrow:Hide()
        row._wpArrow = wpArrow
    end
    row:SetParent(parent)
    row:Show()
    return row
end

local function RecycleRow(row)
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row._npcID = nil
    row._npcName = nil
    row._zoneName = nil
    row._level = nil
    row._faction = nil
    row._sourceType = nil
    row._canWaypoint = nil
    row._tooltipName = nil
    row._tooltipExtra = nil
    if row._wpArrow then row._wpArrow:Hide() end
    rowPool[#rowPool + 1] = row
end

-- ---------- Click / tooltip handlers ----------

local function OnRowEnter(self)
    if not self._tooltipName then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self._tooltipName, 1, 1, 1)
    if self._level then
        GameTooltip:AddLine("Level " .. tostring(self._level), 0.7, 0.7, 0.7)
    end
    if self._faction then
        GameTooltip:AddLine("Faction: " .. self._faction, 0.7, 0.7, 0.7)
    end
    if self._zoneName then
        GameTooltip:AddLine(self._zoneName, UI.COLOR_SOURCE.r, UI.COLOR_SOURCE.g, UI.COLOR_SOURCE.b)
    end
    if self._tooltipExtra then
        GameTooltip:AddLine(self._tooltipExtra, 0.7, 0.7, 0.7)
    end
    if self._canWaypoint then
        GameTooltip:AddLine(" ")
        if RecipeBook:HasAddressBook() and RecipeBook:HasTomTom() then
            local wp = RecipeBook.activeWaypoint
            if wp and wp.npcName == self._npcName and wp.zoneName == self._zoneName then
                GameTooltip:AddLine("Click to clear waypoint", 1, 0.3, 0.3)
            else
                GameTooltip:AddLine("Click to set waypoint", UI.COLOR_WAYPOINT.r, UI.COLOR_WAYPOINT.g, UI.COLOR_WAYPOINT.b)
            end
        else
            GameTooltip:AddLine("AddressBook + TomTom required for waypoints", 0.7, 0.4, 0.4)
        end
    end
    GameTooltip:Show()
end

local function OnRowLeave(self)
    GameTooltip:Hide()
end

local function OnRowClick(self)
    if not self._canWaypoint then return end
    if not (RecipeBook:HasAddressBook() and RecipeBook:HasTomTom()) then return end

    local wp = RecipeBook.activeWaypoint
    if wp and wp.npcName == self._npcName and wp.zoneName == self._zoneName then
        if AddressBook and AddressBook.ClearWaypoint then
            AddressBook:ClearWaypoint()
        end
        if AddressBook and AddressBook.ClearAllWaypoints then
            AddressBook:ClearAllWaypoints()
        end
        RecipeBook.activeWaypoint = nil
    else
        if AddressBook and AddressBook.API and AddressBook.API.WaypointTo then
            AddressBook.API:WaypointTo(self._npcName, self._zoneName)
            RecipeBook.activeWaypoint = { npcName = self._npcName, zoneName = self._zoneName }
        end
    end

    -- Refresh popup row highlighting + main list arrows
    if popupFrame and popupFrame:IsShown() and popupFrame._profID and popupFrame._recipeID then
        RecipeBook:ShowSourcesPopup(popupFrame._profID, popupFrame._recipeID)
    end
    if RecipeBook.mainFrame and RecipeBook.mainFrame:IsShown() then
        RecipeBook:RefreshRecipeList()
    end
end

-- ---------- Frame construction ----------

local function CreatePopupFrame()
    if popupFrame then return popupFrame end

    local frame = CreateFrame("Frame", "RecipeBookDropSourcesFrame", UIParent, "BackdropTemplate")
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

    -- Title bar artwork
    local titleBar = frame:CreateTexture(nil, "ARTWORK")
    titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBar:SetSize(220, 64)
    titleBar:SetPoint("TOP", 0, 12)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontTitle")
    titleText:SetPoint("TOP", titleBar, "TOP", 0, -14)
    titleText:SetText("Sources")
    frame._title = titleText

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    -- Subtitle (recipe name)
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontNormal")
    subtitle:SetPoint("TOP", frame, "TOP", 0, -30)
    subtitle:SetWidth(POPUP_WIDTH - 40)
    subtitle:SetWordWrap(false)
    subtitle:SetTextColor(1, 1, 1)
    frame._subtitle = subtitle

    -- Column headers
    local hdrRef = CreateFrame("Frame", nil, frame)
    hdrRef:SetHeight(16)
    hdrRef:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -50)
    hdrRef:SetPoint("RIGHT", frame, "RIGHT", -20, 0)

    -- Row layout inside scrollChild: name LEFT+6 w=150, zone LEFT+162..rate-8, rate RIGHT-24 w=44, arrow RIGHT-4
    -- hdrRef matches scrollChild's horizontal span (frame LEFT+20 .. RIGHT-38 to leave room for scrollbar+arrow column)
    hdrRef:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -50)
    hdrRef:SetPoint("RIGHT", frame, "RIGHT", -38, 0)

    local hName = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    hName:SetPoint("LEFT", hdrRef, "LEFT", 6, 0)
    hName:SetText("Source")
    hName:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local hZone = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    hZone:SetPoint("LEFT", hdrRef, "LEFT", 167, 0)
    hZone:SetText("Zone")
    hZone:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    local hRate = frame:CreateFontString(nil, "OVERLAY", "RecipeBookFontSmall")
    hRate:SetPoint("RIGHT", hdrRef, "RIGHT", -28, 0)
    hRate:SetText("Info")
    hRate:SetTextColor(UI.COLOR_HEADER.r, UI.COLOR_HEADER.g, UI.COLOR_HEADER.b)

    -- List panel + scroll frame
    local listPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    listPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    listPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "RecipeBookDropSourcesScroll", listPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(listPanel:GetWidth() - 30)
    scrollFrame:SetScrollChild(scrollChild)

    frame._scrollFrame = scrollFrame
    frame._scrollChild = scrollChild

    frame:Hide()
    popupFrame = frame
    return frame
end

-- ---------- Public API ----------

-- Build a typed label prefix + info string for an entry
local function formatEntry(e)
    local label = RecipeBook.SOURCE_LABELS[e.sourceType] or e.sourceType
    local nameStr = (e.name or "?")
    -- For drops/pickpocket/trainer/vendor/object/unique the name IS the thing;
    -- prefix with a short type tag to differentiate rows.
    local shortTag
    if e.sourceType == "drop" then shortTag = "D"
    elseif e.sourceType == "pickpocket" then shortTag = "P"
    elseif e.sourceType == "trainer" then shortTag = "T"
    elseif e.sourceType == "vendor" then shortTag = "V"
    elseif e.sourceType == "quest" then shortTag = "Q"
    elseif e.sourceType == "object" then shortTag = "O"
    elseif e.sourceType == "fishing" then shortTag = "F"
    elseif e.sourceType == "item" then shortTag = "I"
    elseif e.sourceType == "unique" then shortTag = "U"
    end
    local displayName = shortTag and ("|cffffcc00[" .. shortTag .. "]|r " .. nameStr) or nameStr

    local info
    if e.dropRate then
        info = string.format("%.1f%%", e.dropRate)
    elseif e.extra then
        info = e.extra
    elseif e.faction then
        info = e.faction
    else
        info = label
    end
    return displayName, info
end

function RecipeBook:ShowSourcesPopup(profID, recipeID)
    local frame = CreatePopupFrame()
    frame._profID = profID
    frame._recipeID = recipeID

    -- Recycle existing rows
    for _, r in ipairs(popupRows) do RecycleRow(r) end
    wipe(popupRows)

    local recipeName = self:GetRecipeName(profID, recipeID) or "Recipe"
    frame._subtitle:SetText(recipeName)

    local scrollChild = frame._scrollChild
    local factionFilter = nil
    if self.myFactionOnly then
        factionFilter = UnitFactionGroup("player")
    end
    local entries = CollectAllSources(profID, recipeID, factionFilter)
    local y = 0

    if #entries == 0 then
        local row = GetPopupRow(scrollChild)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row._nameText:SetText("No sources found")
        row._nameText:SetTextColor(0.6, 0.6, 0.6)
        row._zoneText:SetText("")
        row._rateText:SetText("")
        popupRows[#popupRows + 1] = row
        scrollChild:SetHeight(ROW_H)
    else
        local wp = self.activeWaypoint
        local hasAB = self:HasAddressBook() and self:HasTomTom()
        for _, e in ipairs(entries) do
            local row = GetPopupRow(scrollChild)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

            local nameStr, infoStr = formatEntry(e)
            row._nameText:SetText(nameStr)
            row._nameText:SetTextColor(1, 1, 1)
            row._zoneText:SetText(e.zone or "")
            row._rateText:SetText(infoStr)

            row._sourceType = e.sourceType
            row._npcID = e.npcID
            -- For quests, the waypoint target is the start NPC, not the quest
            -- title; look it up so AB can resolve a waypoint.
            if e.sourceType == "quest" and e.npcID then
                row._npcName = self:GetNPCName(e.npcID)
            else
                row._npcName = e.name
            end
            row._zoneName = e.zone
            row._level = e.level
            row._faction = e.faction
            row._tooltipName = e.name
            row._tooltipExtra = e.extra

            -- Waypoint-eligible if we have a named entity with a zone
            local canWP = hasAB and e.zone ~= nil and row._npcName ~= nil
                and (e.sourceType == "trainer" or e.sourceType == "vendor"
                    or e.sourceType == "drop" or e.sourceType == "pickpocket"
                    or e.sourceType == "object" or e.sourceType == "unique"
                    or (e.sourceType == "quest" and e.npcID))
            row._canWaypoint = canWP

            if canWP then
                row._wpArrow:Show()
                if wp and wp.npcName == e.name and wp.zoneName == e.zone then
                    row._wpArrow:SetVertexColor(1, 1, 0, 1)
                else
                    row._wpArrow:SetVertexColor(UI.COLOR_WAYPOINT.r, UI.COLOR_WAYPOINT.g, UI.COLOR_WAYPOINT.b, 0.6)
                end
            else
                row._wpArrow:Hide()
            end

            row:SetScript("OnEnter", OnRowEnter)
            row:SetScript("OnLeave", OnRowLeave)
            row:SetScript("OnClick", OnRowClick)

            popupRows[#popupRows + 1] = row
            y = y - ROW_H
        end
        scrollChild:SetHeight(math.abs(y) + 4)
    end

    frame:Show()
    frame:Raise()
end

-- Back-compat alias
function RecipeBook:ShowDropSourcesPopup(profID, recipeID)
    return self:ShowSourcesPopup(profID, recipeID)
end

function RecipeBook:HideSourcesPopup()
    if popupFrame then popupFrame:Hide() end
end
RecipeBook.HideDropSourcesPopup = RecipeBook.HideSourcesPopup

function RecipeBook:IsSourcesPopupShown()
    return popupFrame and popupFrame:IsShown() and popupFrame._profID and popupFrame._recipeID
end

function RecipeBook:RefreshSourcesPopup()
    if self:IsSourcesPopupShown() then
        self:ShowSourcesPopup(popupFrame._profID, popupFrame._recipeID)
    end
end

function RecipeBook:CleanupSourcesPopup()
    if popupFrame then
        popupFrame:Hide()
        for _, r in ipairs(popupRows) do RecycleRow(r) end
        wipe(popupRows)
        wipe(rowPool)
    end
end
