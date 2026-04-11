RecipeBook = RecipeBook or {}

function RecipeBook:CreateMinimapButton()
    local ldb = LibStub("LibDataBroker-1.1", true)
    if not ldb then return end

    local dataObj = ldb:GetDataObjectByName("RecipeBook") or ldb:NewDataObject("RecipeBook", {
        type = "launcher",
        text = "RecipeBook",
        icon = "Interface\\AddOns\\RecipeBook\\minimap-icon",
        OnClick = function(_, button)
            if button == "LeftButton" then
                RecipeBook:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("RecipeBook", 0, 0.82, 1)
            tt:AddLine("Left-click: Toggle window", 1, 1, 1)
            tt:AddLine(" ")
            if RecipeBook:HasAddressBook() then
                tt:AddLine("AddressBook: |cff00ff00Available|r", 0.7, 0.7, 0.7)
            else
                tt:AddLine("AddressBook: |cffff6600Not loaded|r", 0.7, 0.7, 0.7)
            end
        end,
    })
    if not dataObj then return end

    local icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        if not icon:IsRegistered("RecipeBook") then
            icon:Register("RecipeBook", dataObj, RecipeBookDB.minimap)
        end
        self._dbIcon = icon
    end
end

function RecipeBook:ToggleMinimapButton()
    if not RecipeBookDB or not RecipeBookDB.minimap then return end
    RecipeBookDB.minimap.hide = not RecipeBookDB.minimap.hide
    if RecipeBookDB.minimap.hide then
        if self._dbIcon then self._dbIcon:Hide("RecipeBook") end
        self:Print("Minimap button hidden. Use /rb minimap to show it again.")
    else
        if self._dbIcon then self._dbIcon:Show("RecipeBook") end
        self:Print("Minimap button shown.")
    end
end
