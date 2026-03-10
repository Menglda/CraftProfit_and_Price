local _, ns = ...

local CreateFrame = CreateFrame
local tinsert = table.insert

local function ResolveRecipeInfo(source)
    if not source then
        return nil
    end

    if source.recipeID then
        return source
    end

    if source.recipeInfo then
        return source.recipeInfo
    end

    if source.GetData then
        local elementData = source:GetData()
        if elementData and elementData.recipeInfo then
            return elementData.recipeInfo
        end
    end

    if source.GetElementData then
        local elementData = source:GetElementData()
        if elementData and elementData.recipeInfo then
            return elementData.recipeInfo
        end
    end

    if source.recipeInfo then
        return source.recipeInfo
    end

    return nil
end

local function GetRecipeIDFromSource(source)
    local recipeInfo = ResolveRecipeInfo(source)
    if not recipeInfo then
        return nil
    end

    recipeInfo = (Professions and Professions.GetHighestLearnedRecipe and Professions.GetHighestLearnedRecipe(recipeInfo)) or recipeInfo
    return recipeInfo and recipeInfo.recipeID or nil
end

local function GetDisplayedRecipeInfo(form)
    if not form then
        return nil
    end

    local recipeInfo = form.currentRecipeInfo or (form.GetRecipeInfo and form:GetRecipeInfo()) or nil
    if not recipeInfo then
        return nil
    end

    return (Professions and Professions.GetHighestLearnedRecipe and Professions.GetHighestLearnedRecipe(recipeInfo)) or recipeInfo
end

local function PositionSchematicSummary(form, summary)
    if not form or not summary then
        return
    end

    summary:ClearAllPoints()
    summary:SetPoint("TOPRIGHT", form, "TOPRIGHT", -26, -32)
end

function ns:EnsureRecipeProfitLabel(button)
    if button.CraftProfitLabel then
        return button.CraftProfitLabel
    end

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 11, "")
    label:SetJustifyH("RIGHT")
    label:SetWidth(72)
    if label.SetWordWrap then
        label:SetWordWrap(false)
    end
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(false)
    end
    if label.SetMaxLines then
        label:SetMaxLines(1)
    end
    button.CraftProfitLabel = label
    return label
end

local function GetSelectedForm()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.SchematicForm or nil
end

local function GetProfessionTransaction(form)
    local tableMembers = {
        "transaction",
        "recipeTransaction",
        "craftingTransaction",
        "currentTransaction",
        "activeTransaction",
    }

    local methodMembers = {
        "GetTransaction",
        "GetRecipeTransaction",
        "GetCraftingTransaction",
        "GetCurrentTransaction",
        "GetActiveTransaction",
    }

    local current = form
    for _ = 1, 4 do
        if not current then
            break
        end

        for _, memberName in ipairs(tableMembers) do
            local value = current[memberName]
            if type(value) == "table" then
                return value
            end
        end

        for _, memberName in ipairs(methodMembers) do
            local member = current[memberName]
            if type(member) == "function" then
                local ok, result = pcall(member, current)
                if ok and type(result) == "table" then
                    return result
                end
            end
        end

        current = current.GetParent and current:GetParent() or nil
    end

    return nil
end

function ns:GetProfessionTransaction(form)
    return GetProfessionTransaction(form)
end

local function GetQualityTooltipPrimaryLine(tooltip)
    if not tooltip or not tooltip.GetName then
        return nil
    end

    local textRegion = _G[tooltip:GetName() .. "TextLeft1"]
    return textRegion and textRegion.GetText and textRegion:GetText() or nil
end

local function TooltipTextContains(text, needle)
    if type(text) ~= "string" or type(needle) ~= "string" then
        return false
    end

    local ok, found = pcall(string.find, text, needle, 1, true)
    return ok and found ~= nil or false
end

local function IsProfessionQualityTooltip(tooltip)
    local text = GetQualityTooltipPrimaryLine(tooltip)
    if not text then
        return false
    end

    return TooltipTextContains(text, "품질 보너스")
        or TooltipTextContains(text, "Quality Bonus")
        or TooltipTextContains(text, "제작 세부 정보")
        or TooltipTextContains(text, "Crafting Details")
end

local function IsProfessionDetailsTooltip(tooltip)
    local text = GetQualityTooltipPrimaryLine(tooltip)
    if not text then
        return false
    end

    return TooltipTextContains(text, "제작 세부 정보")
        or TooltipTextContains(text, "Crafting Details")
end

local function ShouldHandleProfessionTooltip(tooltip, form)
    local function IsDescendantOfLocal(frame, ancestor)
        local current = frame
        while current do
            if current == ancestor then
                return true
            end
            current = current.GetParent and current:GetParent() or nil
        end
        return false
    end

    if IsProfessionQualityTooltip(tooltip) then
        return true
    end

    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner() or nil
    if owner and form and IsDescendantOfLocal(owner, form) then
        return true
    end

    return false
end

local function GetNumericValue(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(value)
    end
    return nil
end

local function ReadNumericMember(source, memberName)
    if not source or not memberName then
        return nil
    end

    local value = source[memberName]
    if type(value) == "function" then
        local ok, result = pcall(value, source)
        if ok then
            return GetNumericValue(result)
        end
        return nil
    end

    return GetNumericValue(value)
end

local function GetHoveredQualityIndex(owner, form, options)
    options = options or {}

    local directMemberNames = {
        "GetQualityID",
        "GetOutputQualityID",
        "GetOutputOverrideQualityID",
        "GetCraftingQualityID",
        "qualityID",
        "QualityID",
        "quality",
        "qualityIndex",
        "outputQualityID",
        "outputQuality",
        "craftingQualityID",
    }

    local parentMemberNames = {
        "GetQualityID",
        "qualityID",
        "QualityID",
        "quality",
        "qualityIndex",
        "outputQualityID",
        "outputQuality",
    }

    if options.allowGenericID then
        tinsert(directMemberNames, "GetID")
        tinsert(directMemberNames, "index")
        tinsert(directMemberNames, "id")
        tinsert(directMemberNames, "ID")

        tinsert(parentMemberNames, "GetID")
        tinsert(parentMemberNames, "index")
        tinsert(parentMemberNames, "id")
        tinsert(parentMemberNames, "ID")
    end

    local function ReadMembers(source, memberNames)
        for _, memberName in ipairs(memberNames) do
            local value = ReadNumericMember(source, memberName)
            if value and value > 0 then
                return value
            end
        end
        return nil
    end

    local current = owner
    if current then
        local value = ReadMembers(current, directMemberNames)
        if value then
            return value
        end

        local dataProviders = { "GetElementData", "GetData" }
        for _, providerName in ipairs(dataProviders) do
            local provider = current[providerName]
            if type(provider) == "function" then
                local ok, data = pcall(provider, current)
                if ok and type(data) == "table" then
                    value = ReadMembers(data, directMemberNames)
                    if value then
                        return value
                    end
                end
            end
        end
    end

    current = current and current.GetParent and current:GetParent() or nil
    for _ = 1, 4 do
        if not current then
            break
        end

        local value = ReadMembers(current, parentMemberNames)
        if value then
            return value
        end

        local dataProviders = { "GetElementData", "GetData" }
        for _, providerName in ipairs(dataProviders) do
            local provider = current[providerName]
            if type(provider) == "function" then
                local ok, data = pcall(provider, current)
                if ok and type(data) == "table" then
                    value = ReadMembers(data, parentMemberNames)
                    if value then
                        return value
                    end
                end
            end
        end

        current = current.GetParent and current:GetParent() or nil
    end

    return nil
end

function ns:GetHoveredProfessionQualityIndex(owner, form, options)
    return GetHoveredQualityIndex(owner, form, options)
end

function ns:GetRecipeListDisplay(recipeID)
    -- Keep the recipe list stable regardless of which recipe is selected.
    local data = self:GetRecipeDisplayEconomics(recipeID)
    local source = data and "baseline" or "none"

    self:DebugRecipeTrace(
        recipeID,
        "ListDisplay source=%s",
        source or "none"
    )

    if not data then
        return nil, self.colors.neutral, nil
    end

    if not data.hasSalePrice then
        return self:FormatGoldOnly(data.totalCost), self.colors.neutral, data
    end

    return self:FormatGoldOnly(data.profit), self:GetMarginColor(data.margin), data
end

function ns:ScheduleProfessionViewsRefresh(reason)
    self._professionRefreshToken = (self._professionRefreshToken or 0) + 1
    local token = self._professionRefreshToken
    local delays = { 0, 0.15, 0.6 }

    for _, delaySeconds in ipairs(delays) do
        C_Timer.After(delaySeconds, function()
            if self._professionRefreshToken ~= token then
                return
            end
            self:RefreshProfessionViews()
        end)
    end
end

function ns:UpdateRecipeProfitButton(button, node)
    if not self.Settings.showRecipeListProfit or not button then
        return
    end

    local recipeID = GetRecipeIDFromSource(node or button)
    local label = self:EnsureRecipeProfitLabel(button)
    if not recipeID then
        label:Hide()
        return
    end

    local text, color = self:GetRecipeListDisplay(recipeID)
    if not text then
        label:Hide()
        return
    end

    label:ClearAllPoints()
    label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    label:SetText(self:WrapColor(text, color))
    label:Show()
end

function ns:EnsureReagentPriceLabel(slot)
    if slot.CraftProfitLabel then
        return slot.CraftProfitLabel
    end

    local label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetJustifyH("RIGHT")
    label:SetWidth(160)
    label:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -8, -4)
    slot.CraftProfitLabel = label
    return label
end

function ns:UpdateReagentPriceLabel(slot)
    if not slot then
        return
    end
    local label = self:EnsureReagentPriceLabel(slot)
    label:Hide()
end

function ns:EnsureSchematicSummary(form)
    if form.CraftProfitSummary then
        return form.CraftProfitSummary
    end

    local frame = CreateFrame("Frame", nil, form)
    frame:SetSize(280, 96)
    PositionSchematicSummary(form, frame)

    frame.sale = frame:CreateFontString(nil, "OVERLAY")
    frame.sale:SetFont(STANDARD_TEXT_FONT, 13, "")
    frame.sale:SetPoint("TOPLEFT")
    frame.sale:SetJustifyH("LEFT")
    frame.sale:SetWidth(280)
    if frame.sale.SetWordWrap then frame.sale:SetWordWrap(false) end
    if frame.sale.SetNonSpaceWrap then frame.sale:SetNonSpaceWrap(false) end
    if frame.sale.SetMaxLines then frame.sale:SetMaxLines(1) end

    frame.fee = frame:CreateFontString(nil, "OVERLAY")
    frame.fee:SetFont(STANDARD_TEXT_FONT, 13, "")
    frame.fee:SetPoint("TOPLEFT", frame.sale, "BOTTOMLEFT", 0, -2)
    frame.fee:SetJustifyH("LEFT")
    frame.fee:SetWidth(280)
    if frame.fee.SetWordWrap then frame.fee:SetWordWrap(false) end
    if frame.fee.SetNonSpaceWrap then frame.fee:SetNonSpaceWrap(false) end
    if frame.fee.SetMaxLines then frame.fee:SetMaxLines(1) end

    frame.cost = frame:CreateFontString(nil, "OVERLAY")
    frame.cost:SetFont(STANDARD_TEXT_FONT, 13, "")
    frame.cost:SetPoint("TOPLEFT", frame.fee, "BOTTOMLEFT", 0, -2)
    frame.cost:SetJustifyH("LEFT")
    frame.cost:SetWidth(280)
    if frame.cost.SetWordWrap then frame.cost:SetWordWrap(false) end
    if frame.cost.SetNonSpaceWrap then frame.cost:SetNonSpaceWrap(false) end
    if frame.cost.SetMaxLines then frame.cost:SetMaxLines(1) end

    frame.profit = frame:CreateFontString(nil, "OVERLAY")
    frame.profit:SetFont(STANDARD_TEXT_FONT, 13, "")
    frame.profit:SetPoint("TOPLEFT", frame.cost, "BOTTOMLEFT", 0, -2)
    frame.profit:SetJustifyH("LEFT")
    frame.profit:SetWidth(280)
    if frame.profit.SetWordWrap then frame.profit:SetWordWrap(false) end
    if frame.profit.SetNonSpaceWrap then frame.profit:SetNonSpaceWrap(false) end
    if frame.profit.SetMaxLines then frame.profit:SetMaxLines(1) end

    form.CraftProfitSummary = frame
    return frame
end

local function ParseStoredProfessionQualityTier(link)
    local qualityTier = link and string.match(link, "Quality[^:|]*%-Tier(%d+)") or nil
    qualityTier = qualityTier and tonumber(qualityTier) or nil
    if qualityTier and qualityTier >= 1 and qualityTier <= 5 then
        return qualityTier
    end
    return nil
end

local function GetStoredTwoQualityTopInfo(self, recipeID)
    if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeQualityItemIDs then
        return nil
    end

    local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)
    local itemID = qualityItemIDs and tonumber(qualityItemIDs[2]) or nil
    if not itemID or itemID <= 0 then
        return nil
    end

    local record = self.GetDBRecord and self:GetDBRecord(itemID) or nil
    if not record then
        return nil
    end

    local bestLink = nil
    local bestPrice = nil
    local bestItemLevel = nil

    for _, data in pairs(record) do
        if type(data) == "table" and data.Price then
            local qualityTier = ParseStoredProfessionQualityTier(data.Link)
            if qualityTier == 2 and (not bestPrice or data.Price < bestPrice) then
                bestPrice = data.Price
                bestLink = data.Link
                bestItemLevel = tonumber(data.ItemLevel) or nil
            end
        end
    end

    if not bestPrice then
        return nil
    end

    return {
        itemID = itemID,
        link = bestLink,
        price = bestPrice,
        qualityIndex = 2,
        itemLevel = bestItemLevel,
    }
end

function ns:UpdateSchematicSummary(form)
    if not form then
        return
    end

    local summary = self:EnsureSchematicSummary(form)
    PositionSchematicSummary(form, summary)

    local recipeInfo = GetDisplayedRecipeInfo(form)
    if not recipeInfo then
        summary:Hide()
        return
    end

    local transaction = GetProfessionTransaction(form)
    local data = self:GetRecipeDisplayEconomics(recipeInfo.recipeID)
    if not data then
        summary:Hide()
        return
    end

    -- The list/detail base value stays on the stable baseline path, but two-quality
    -- recipes still need the live rank-2 sale from the selected profession form.
    local formQualityContext = self.GetRecipeQualityContext and self:GetRecipeQualityContext(recipeInfo.recipeID, transaction, form) or nil
    if formQualityContext and formQualityContext.qualityMode == 2 then
        data.qualityMode = 2
        data.qualityBaseIndex = data.qualityBaseIndex or 1

        if not data.topSalePrice then
            local topInfo = GetStoredTwoQualityTopInfo(self, recipeInfo.recipeID)
            if not topInfo then
                topInfo = self:GetRecipeQualityPriceForIndex(recipeInfo.recipeID, 2, transaction, form)
            end
            if topInfo and topInfo.price then
                local auctionCutRate = self.Settings and self.Settings.auctionCutRate or 0.05
                local topAuctionCut = math.floor(topInfo.price * auctionCutRate)
                local topNetSale = topInfo.price - topAuctionCut
                local topProfit = topNetSale - data.totalCost

                data.qualityTopIndex = topInfo.qualityIndex or 2
                data.topSalePrice = topInfo.price
                data.topSaleItemID = topInfo.itemID
                data.topSaleLink = topInfo.link
                data.topAuctionCut = topAuctionCut
                data.topProfit = topProfit
                data.topMargin = (topProfit and data.totalCost > 0) and (topProfit / data.totalCost) or nil
            end
        end
    end

    if not data.hasSalePrice then
        summary.sale:SetText(self:WrapColor("재료+비용: ", self.colors.neutral) .. self:WrapColor(self:FormatGoldOnly(data.totalCost), self.colors.neutral))
        summary.fee:Hide()
        summary.cost:Hide()
        summary.profit:Hide()
        summary.sale:Show()
        summary:Show()
        return
    end

    local color = self:GetMarginColor(data.margin)
    local topColor = self:GetMarginColor(data.topMargin)
    local hasTopDisplay = data.topSalePrice
        and data.qualityTopIndex
        and data.qualityBaseIndex
        and data.qualityTopIndex > data.qualityBaseIndex
        and data.topSalePrice ~= data.salePrice
    local hasMissingTopDisplay = not hasTopDisplay
        and data.topSaleStatusText
        and data.qualityMode >= 4

    local saleText = self:WrapColor("기준가: ", "FF74D06C") .. self:FormatGoldOnly(data.salePrice)
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        saleText = saleText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay then
        saleText = saleText .. ", " .. self:FormatGoldOnly(data.topSalePrice) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    elseif hasMissingTopDisplay then
        saleText = saleText .. self:WrapColor(string.format(" (%s)", data.topSaleStatusText), self.colors.text)
    end

    local costText = self:WrapColor("재료+비용: ", "FF74D06C")
        .. self:FormatGoldOnly(data.totalCost)

    local profitText = self:WrapColor("순이익: ", "FF74D06C")
        .. self:WrapColor(self:FormatGoldOnly(data.profit), color)
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        profitText = profitText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay and data.topProfit then
        profitText = profitText .. ", " .. self:WrapColor(self:FormatGoldOnly(data.topProfit), topColor) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    end

    local marginText = self:WrapColor("이익률: ", "FF74D06C")
        .. self:WrapColor(self:FormatPercent(data.margin), color)
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        marginText = marginText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay and data.topMargin then
        marginText = marginText .. ", " .. self:WrapColor(self:FormatPercent(data.topMargin), topColor) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    end

    summary.sale:SetText(costText)
    summary.fee:SetText(saleText)
    summary.cost:SetText(profitText)
    summary.profit:SetText(marginText)
    summary.sale:Show()
    summary.fee:Show()
    summary.cost:Show()
    summary.profit:Show()
    summary:Show()
end

local function GetProfessionTooltipPriceInfo(self, tooltip, form, recipeInfo)
    if not self or not tooltip or not form or not recipeInfo then
        return nil
    end

    local transaction = GetProfessionTransaction(form)
    local qualityContext = self.GetRecipeQualityContext and self:GetRecipeQualityContext(recipeInfo.recipeID, transaction, form) or nil
    local displayedItemLevel = self.GetTooltipDisplayedItemLevel and self:GetTooltipDisplayedItemLevel(tooltip) or nil
    local isDetailsTooltip = IsProfessionDetailsTooltip(tooltip)
    local qualityIndex = self.GetHoveredProfessionQualityIndex and self:GetHoveredProfessionQualityIndex(tooltip:GetOwner(), form, {
        allowGenericID = not isDetailsTooltip,
    }) or nil

    local function FindByDisplayedItemLevel()
        if not displayedItemLevel or not qualityContext or qualityContext.qualityMode <= 1 then
            return nil
        end

        return self.GetRecipePriceByDisplayedItemLevel and self:GetRecipePriceByDisplayedItemLevel(recipeInfo.recipeID, displayedItemLevel, transaction, form) or nil
    end

    local function FindByQualityIndex()
        if not qualityIndex or not qualityContext then
            return nil
        end

        if qualityContext.qualityMode > 1 and isDetailsTooltip then
            return nil
        end

        local priceInfo = self:GetRecipeQualityPriceForIndex(recipeInfo.recipeID, qualityIndex, transaction, form)
        if priceInfo and priceInfo.price then
            return priceInfo
        end

        return nil
    end

    if qualityContext and qualityContext.qualityMode > 1 and isDetailsTooltip then
        return FindByDisplayedItemLevel() or FindByQualityIndex()
    end

    return FindByQualityIndex() or FindByDisplayedItemLevel()
end

function ns:UpdateProfessionQualityTooltip(tooltip)
    if not tooltip or tooltip:IsForbidden() or tooltip.CraftProfitQualityPriceAdded then
        return
    end

    local form = GetSelectedForm()

    if not ShouldHandleProfessionTooltip(tooltip, form) then
        return
    end

    local recipeInfo = GetDisplayedRecipeInfo(form)
    if not recipeInfo then
        return
    end

    local priceInfo = GetProfessionTooltipPriceInfo(self, tooltip, form, recipeInfo)
    if not priceInfo or not priceInfo.price then
        return
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(self:WrapColor("경매장: ", "FF74D06C") .. self:FormatGoldOnly(priceInfo.price))

    tooltip.CraftProfitQualityPriceAdded = true
    tooltip:Show()
end

function ns:UpdateProfessionGraph(form)
    if not form then
        return
    end

    if form.CraftProfitSparkline then
        form.CraftProfitSparkline:Hide()
    end
end

function ns:RefreshProfessionViews()
    if not ProfessionsFrame or not ProfessionsFrame.CraftingPage then
        return
    end

    local page = ProfessionsFrame.CraftingPage
    if page.SchematicForm then
        self:UpdateSchematicSummary(page.SchematicForm)
        self:UpdateProfessionGraph(page.SchematicForm)
    end

    local recipeList = page.RecipeList
    if recipeList and recipeList.ScrollBox and recipeList.ScrollBox.ForEachFrame then
        recipeList.ScrollBox:ForEachFrame(function(button)
            if button and button.GetElementData then
                self:UpdateRecipeProfitButton(button, button:GetElementData())
            end
        end)
    end
end

function ns:SetupProfessionHooks()
    local function AttachHooks()
        if self.professionHooksInstalled or not ProfessionsFrame or not ProfessionsFrame.CraftingPage then
            return
        end

        self.professionHooksInstalled = true

        if ProfessionsRecipeListRecipeMixin then
            hooksecurefunc(ProfessionsRecipeListRecipeMixin, "Init", function(button, node, hideCraftableCount)
                ns:UpdateRecipeProfitButton(button, node)
            end)
        end

        if EventRegistry then
            EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
                ns:ScheduleProfessionViewsRefresh("recipe-selected")
            end, self)
            EventRegistry:RegisterCallback("Professions.TransactionUpdated", function()
                ns:ScheduleProfessionViewsRefresh("transaction-updated")
            end, self)
        end

        if ProfessionsRecipeListMixin then
            hooksecurefunc(ProfessionsRecipeListMixin, "SelectRecipe", function()
                ns:ScheduleProfessionViewsRefresh("select-recipe")
            end)
        end

        if ProfessionsReagentSlotMixin then
            hooksecurefunc(ProfessionsReagentSlotMixin, "Update", function(slot)
                ns:UpdateReagentPriceLabel(slot)
            end)
        end

        if GameTooltip then
            GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
                tooltip.CraftProfitQualityPriceAdded = nil
                tooltip.CraftProfitQualityRetryPending = nil
            end)
            GameTooltip:HookScript("OnShow", function(tooltip)
                ns:UpdateProfessionQualityTooltip(tooltip)
                if not tooltip.CraftProfitQualityPriceAdded and not tooltip.CraftProfitQualityRetryPending then
                    tooltip.CraftProfitQualityRetryPending = true
                    C_Timer.After(0, function()
                        if tooltip and tooltip.IsShown and tooltip:IsShown() then
                            tooltip.CraftProfitQualityRetryPending = nil
                            ns:UpdateProfessionQualityTooltip(tooltip)
                        end
                    end)
                end
            end)
        end

        if ProfessionsCraftingPageMixin then
            hooksecurefunc(ProfessionsCraftingPageMixin, "Init", function()
                ns:ScheduleProfessionViewsRefresh("crafting-page-init")
            end)
            hooksecurefunc(ProfessionsCraftingPageMixin, "Refresh", function()
                ns:ScheduleProfessionViewsRefresh("crafting-page-refresh")
            end)
        end

        if ProfessionsRecipeSchematicFormMixin then
            hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Init", function(form)
                ns:UpdateSchematicSummary(form)
                ns:UpdateProfessionGraph(form)
            end)
            hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Refresh", function(form)
                ns:UpdateSchematicSummary(form)
                ns:UpdateProfessionGraph(form)
            end)
            hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "UpdateDetailsStats", function(form)
                ns:UpdateSchematicSummary(form)
                ns:UpdateProfessionGraph(form)
            end)
        end
    end

    if ProfessionsFrame and ProfessionsFrame.CraftingPage then
        AttachHooks()
    else
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_Professions" then
                AttachHooks()
            end
        end)
    end
end
