RecipeBook = RecipeBook or {}

local L = LibStub("AceLocale-3.0"):GetLocale("RecipeBook")

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
            tt:AddLine(L["Left-click: Toggle window"], 1, 1, 1)
            tt:AddLine(" ")
            if RecipeBook:HasAddressBook() then
                tt:AddLine(L["AddressBook: |cff00ff00Available|r"], 0.7, 0.7, 0.7)
            else
                tt:AddLine(L["AddressBook: |cffff6600Not loaded|r"], 0.7, 0.7, 0.7)
            end
        end,
    })
    if not dataObj then return end

    local icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        -- IsRegistered is the primary guard, but defend against edge
        -- cases where it gives a false negative (library-version skew
        -- between concurrent addons, an embedded copy's state out of
        -- sync with ours): pcall the Register so a duplicate doesn't
        -- bubble an error to the user.
        if not icon:IsRegistered("RecipeBook") then
            pcall(icon.Register, icon, "RecipeBook", dataObj, RecipeBookDB.minimap)
        end
        self._dbIcon = icon
    end
end

function RecipeBook:ToggleMinimapButton()
    if not RecipeBookDB or not RecipeBookDB.minimap then return end
    RecipeBookDB.minimap.hide = not RecipeBookDB.minimap.hide
    if RecipeBookDB.minimap.hide then
        if self._dbIcon then self._dbIcon:Hide("RecipeBook") end
        self:Print(L["Minimap button hidden. Use /rb minimap to show it again."])
    else
        if self._dbIcon then self._dbIcon:Show("RecipeBook") end
        self:Print(L["Minimap button shown."])
    end
end
