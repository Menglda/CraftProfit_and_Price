local _, ns = ...

local ExtractLink = LinkUtil.ExtractLink
local IsLinkType = LinkUtil.IsLinkType
local ItemLocation = ItemLocation
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
local smatch = string.match
local sfind = string.find
local sformat = string.format
local tconcat = table.concat
local tinsert = table.insert

local function SafeStringMatch(value, pattern)
    if type(value) ~= "string" then
        return nil
    end

    local ok, first, second = pcall(smatch, value, pattern)
    if not ok then
        return nil
    end

    return first, second
end

local function SafePlainFind(value, needle)
    if type(value) ~= "string" or type(needle) ~= "string" or needle == "" then
        return false
    end

    local ok, found = pcall(sfind, value, needle, 1, true)
    return ok and found ~= nil or false
end

local function FormatDebugValue(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function ParseProfessionQualityTier(link)
    local qualityTier = SafeStringMatch(link, "Quality[^:|]*%-Tier(%d+)")
    qualityTier = qualityTier and tonumber(qualityTier) or nil
    if qualityTier and qualityTier >= 1 and qualityTier <= 5 then
        return qualityTier
    end
    return nil
end

local function IterateDebugTargets(targets)
    if type(targets) ~= "string" then
        return function()
            return nil
        end
    end

    local index = 0
    local values = {}
    for part in string.gmatch(targets, "([^,]+)") do
        local trimmed = strtrim(part)
        if trimmed ~= "" then
            values[#values + 1] = trimmed
        end
    end

    return function()
        index = index + 1
        return values[index]
    end
end

function ns:IsRecipeDebugTarget(recipeID)
    local target = self.Settings and self.Settings.debugRecipeTarget or nil
    if not target or target == "" or not recipeID then
        return false
    end

    local recipeInfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID) or nil
    for keyword in IterateDebugTargets(target) do
        if SafePlainFind(recipeInfo and recipeInfo.name, keyword) then
            return true
        end

        local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs and C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID) or nil
        for _, itemID in ipairs(qualityItemIDs or {}) do
            local itemName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
            if SafePlainFind(itemName, keyword) then
                return true
            end
        end
    end

    return false
end

function ns:IsDebugItemTarget(itemID, link)
    local target = self.Settings and self.Settings.debugRecipeTarget or nil
    if not target or target == "" then
        return false
    end

    local itemName = itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
    for keyword in IterateDebugTargets(target) do
        if SafePlainFind(link, keyword) or SafePlainFind(itemName, keyword) then
            return true
        end
    end

    return false
end

function ns:DebugRecipeTrace(recipeID, message, ...)
    if not self.Settings or not self.Settings.debugRecipeTrace then
        return
    end

    if not self:IsRecipeDebugTarget(recipeID) then
        return
    end

    self:Printf("[DEBUG] " .. message, ...)
end

function ns:GetItemVariant(link)
    local raw = select(2, ExtractLink(link))
    if not raw then
        return "0"
    end

    local cache = { strsplit(":", raw) }
    local bonusCount = tonumber(cache[13] or "0") or 0
    if bonusCount > 0 then
        local bonuses = { tostring(bonusCount) }
        for index = 14, 13 + bonusCount do
            bonuses[#bonuses + 1] = tostring(tonumber(cache[index]) or 0)
        end
        return table.concat(bonuses, ":")
    end

    return "0"
end

local function GetItemIDFromLink(link)
    local raw = select(2, ExtractLink(link))
    if not raw then
        return nil
    end

    local itemID = tonumber((SafeStringMatch(raw, "item:(%d+)")))
    if itemID and itemID > 0 then
        return itemID
    end

    return nil
end

function ns:GetPetVariant(link)
    local raw = select(2, ExtractLink(link))
    if not raw then
        return "0"
    end
    return tconcat({ smatch(raw, "^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)") }, ":")
end

function ns:GetCheapestVariant(record)
    local selectedVariant
    local lowestPrice
    for variant, data in pairs(record or {}) do
        if type(data) == "table" and data.Price then
            if not lowestPrice or data.Price < lowestPrice then
                lowestPrice = data.Price
                selectedVariant = variant
            end
        end
    end
    return selectedVariant
end

function ns:GetDBRecord(itemID)
    if not itemID then
        return nil
    end

    local realmRecord = self.PriceDB[self.realmKey] and self.PriceDB[self.realmKey][itemID]
    if realmRecord then
        return realmRecord, self.realmKey
    end

    local regionRecord = self.PriceDB[self.regionKey] and self.PriceDB[self.regionKey][itemID]
    if regionRecord then
        return regionRecord, self.regionKey
    end

    return nil
end

function ns:GetPriceForLink(link)
    if not link then
        return nil
    end

    local itemID
    local variant
    if IsLinkType(link, "item") then
        itemID = tonumber(smatch(link, "item:(%d+)"))
        variant = self:GetItemVariant(link)
    elseif IsLinkType(link, "battlepet") then
        itemID = self.PET_CAGE_ITEM_ID
        variant = self:GetPetVariant(link)
    end

    if not itemID then
        return nil
    end

    local record = self:GetDBRecord(itemID)
    if not record then
        return nil
    end

    if record[variant] then
        return record[variant].Price, record[variant].LastSeen
    end

    local cheapestVariant = self:GetCheapestVariant(record)
    if cheapestVariant and record[cheapestVariant] then
        return record[cheapestVariant].Price, record[cheapestVariant].LastSeen, true
    end

    return nil
end

function ns:GetExactPriceForLink(link)
    if not link then
        return nil
    end

    local itemID
    local variant
    if IsLinkType(link, "item") then
        itemID = tonumber(smatch(link, "item:(%d+)"))
        variant = self:GetItemVariant(link)
    elseif IsLinkType(link, "battlepet") then
        itemID = self.PET_CAGE_ITEM_ID
        variant = self:GetPetVariant(link)
    end

    if not itemID then
        return nil
    end

    local record = self:GetDBRecord(itemID)
    if not record or not record[variant] then
        return nil
    end

    return record[variant].Price, record[variant].LastSeen
end

function ns:GetPriceForItemID(itemID)
    local record = self:GetDBRecord(itemID)
    if not record then
        return nil
    end

    local variant = self:GetCheapestVariant(record)
    if variant and record[variant] then
        return record[variant].Price, record[variant].LastSeen
    end

    return nil
end

function ns:GetPriceForItemLevel(itemID, itemLevel)
    itemLevel = tonumber(itemLevel)
    if not itemID or not itemLevel then
        return nil
    end

    local record = self:GetDBRecord(itemID)
    if not record then
        return nil
    end

    local bestPrice
    local bestSeen
    for _, data in pairs(record) do
        if type(data) == "table" and tonumber(data.ItemLevel) == itemLevel and data.Price then
            if not bestPrice or data.Price < bestPrice then
                bestPrice = data.Price
                bestSeen = data.LastSeen
            end
        end
    end

    if bestPrice then
        return bestPrice, bestSeen
    end

    return nil
end

function ns:GetPriceForQualityRank(itemID, qualityIndex)
    itemID = tonumber(itemID)
    qualityIndex = tonumber(qualityIndex)
    if not itemID or itemID <= 0 or not qualityIndex or qualityIndex <= 0 then
        return nil
    end

    local record = self:GetDBRecord(itemID)
    if not record then
        return nil
    end

    local byItemLevel = {}
    for _, data in pairs(record) do
        local itemLevel = type(data) == "table" and tonumber(data.ItemLevel) or nil
        local price = type(data) == "table" and data.Price or nil
        if itemLevel and price then
            local existing = byItemLevel[itemLevel]
            if not existing or price < existing.Price then
                byItemLevel[itemLevel] = {
                    Price = price,
                    LastSeen = data.LastSeen,
                    ItemLevel = itemLevel,
                    Link = data.Link,
                }
            end
        end
    end

    local sortedLevels = {}
    for itemLevel in pairs(byItemLevel) do
        tinsert(sortedLevels, itemLevel)
    end
    table.sort(sortedLevels)

    local selectedLevel = sortedLevels[qualityIndex]
    local selected = selectedLevel and byItemLevel[selectedLevel] or nil
    if not selected then
        return nil
    end

    return selected.Price, selected.LastSeen, selected.ItemLevel, selected.Link, #sortedLevels
end

local function ParsePositiveNumber(value)
    if type(value) == "number" then
        return value > 0 and value or nil
    end

    if type(value) == "string" then
        local numberText = SafeStringMatch(value, "(%d+)")
        local parsed = numberText and tonumber(numberText) or nil
        return parsed and parsed > 0 and parsed or nil
    end

    return nil
end

local function GetTooltipDisplayedItemLevel(tooltip)
    if not tooltip or not tooltip.GetName then
        return nil
    end

    for lineIndex = 1, 12 do
        local textRegion = _G[tooltip:GetName() .. "TextLeft" .. lineIndex]
        local text = textRegion and textRegion.GetText and textRegion:GetText() or nil
        if text then
            local itemLevel = SafeStringMatch(text, "아이템 레벨%s*(%d+)")
                or SafeStringMatch(text, "Item Level%s*(%d+)")
            itemLevel = itemLevel and tonumber(itemLevel) or nil
            if itemLevel and itemLevel > 0 then
                return itemLevel
            end
        end
    end

    return nil
end

function ns:GetTooltipDisplayedItemLevel(tooltip)
    return GetTooltipDisplayedItemLevel(tooltip)
end

local function IsDescendantOf(frame, ancestor)
    local current = frame
    while current do
        if current == ancestor then
            return true
        end
        current = current.GetParent and current:GetParent() or nil
    end
    return false
end

function ns:GetTooltipQuantity(tooltip, data)
    local quantity = ParsePositiveNumber(data and (data.quantity or data.stackCount or data.count))
    if quantity then
        return quantity
    end

    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner() or nil
    if not owner then
        return 1
    end

    if owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo then
        local bagID = owner:GetBagID()
        local slotIndex = owner:GetID()
        if bagID ~= nil and slotIndex ~= nil then
            local containerInfo = C_Container.GetContainerItemInfo(bagID, slotIndex)
            quantity = ParsePositiveNumber(containerInfo and containerInfo.stackCount)
            if quantity then
                return quantity
            end
        end
    end

    if owner.GetItemLocation and C_Item and C_Item.GetStackCount then
        local itemLocation = owner:GetItemLocation()
        if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
            quantity = ParsePositiveNumber(C_Item.GetStackCount(itemLocation))
            if quantity then
                return quantity
            end
        end
    end

    if owner.GetItem and C_Item and C_Item.GetStackCount then
        local itemLocation = owner:GetItem()
        if itemLocation and type(itemLocation) == "table" and itemLocation.IsValid and itemLocation:IsValid() then
            quantity = ParsePositiveNumber(C_Item.GetStackCount(itemLocation))
            if quantity then
                return quantity
            end
        end
    end

    local parent = owner.GetParent and owner:GetParent() or nil
    if parent then
        if parent.GetReagentSlotSchematic then
            local reagentSlotSchematic = parent:GetReagentSlotSchematic()
            local reagent = owner.GetReagent and owner:GetReagent() or (parent.GetReagent and parent:GetReagent()) or nil
            if reagentSlotSchematic then
                if reagentSlotSchematic.GetQuantityRequired and reagent then
                    quantity = ParsePositiveNumber(reagentSlotSchematic:GetQuantityRequired(reagent))
                    if quantity then
                        return quantity
                    end
                end

                quantity = ParsePositiveNumber(reagentSlotSchematic.quantityRequired)
                if quantity then
                    return quantity
                end
            end
        end

        quantity = ParsePositiveNumber(parent.quantity or parent.count or parent.itemCount or parent.overrideQuantity)
        if quantity then
            return quantity
        end

        if parent.Count and parent.Count.GetText then
            quantity = ParsePositiveNumber(parent.Count:GetText())
            if quantity then
                return quantity
            end
        end

        if parent.Quantity and parent.Quantity.GetText then
            quantity = ParsePositiveNumber(parent.Quantity:GetText())
            if quantity then
                return quantity
            end
        end

        if parent.Name and parent.Name.GetText then
            local text = parent.Name:GetText()
            if text then
                local _, required = SafeStringMatch(text, "(%d+)%s*/%s*(%d+)")
                if required then
                    quantity = ParsePositiveNumber(required)
                    if quantity then
                        return quantity
                    end
                end
            end
        end
    end

    if owner.GetQuantity then
        quantity = ParsePositiveNumber(owner:GetQuantity())
        if quantity then
            return quantity
        end
    end

    if owner.GetItemCount then
        quantity = ParsePositiveNumber(owner:GetItemCount())
        if quantity then
            return quantity
        end
    end

    quantity = ParsePositiveNumber(owner.quantity or owner.count or owner.itemCount)
    if quantity then
        return quantity
    end

    if owner.Count and owner.Count.GetText then
        quantity = ParsePositiveNumber(owner.Count:GetText())
        if quantity then
            return quantity
        end
    end

    if owner.Quantity and owner.Quantity.GetText then
        quantity = ParsePositiveNumber(owner.Quantity:GetText())
        if quantity then
            return quantity
        end
    end

    return 1
end

function ns:TooltipAddPrice(tooltip, data)
    if not self.Settings or not self.Settings.showTooltipPrices or not tooltip or tooltip:IsForbidden() then
        return
    end

    local link = tooltip.GetItem and select(2, tooltip:GetItem()) or (data and ((data.GetItemLink and data:GetItemLink()) or data.hyperlink))
    if not link then
        return
    end

    local exactPrice = self:GetExactPriceForLink(link)
    local price = nil
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner() or nil
    local selectedForm = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm or nil
    local transaction = self.GetProfessionTransaction and self:GetProfessionTransaction(selectedForm) or nil
    local recipeInfo = selectedForm and (selectedForm.currentRecipeInfo or (selectedForm.GetRecipeInfo and selectedForm:GetRecipeInfo()) or nil) or nil
    local recipeID = recipeInfo and recipeInfo.recipeID or nil
    local displayedItemLevel = recipeID and GetTooltipDisplayedItemLevel(tooltip) or nil
    local qualityContext = recipeID and self.GetRecipeQualityContext and self:GetRecipeQualityContext(recipeID, transaction, selectedForm) or nil
    local hoveredQualityIndex = recipeID and owner and self.GetHoveredProfessionQualityIndex and self:GetHoveredProfessionQualityIndex(owner, selectedForm, {
        allowGenericID = false,
    }) or nil
    local isProfessionOutputTooltip = recipeID and owner and selectedForm and (IsDescendantOf(owner, selectedForm) or hoveredQualityIndex ~= nil)

    if isProfessionOutputTooltip and qualityContext then
        if qualityContext.qualityMode == 2 then
            price = exactPrice
        elseif qualityContext.qualityMode == 5 and displayedItemLevel then
            local priceInfo = self:GetRecipePriceByDisplayedItemLevel(recipeID, displayedItemLevel, transaction, selectedForm)
            price = priceInfo and priceInfo.price or nil
        elseif hoveredQualityIndex then
            local priceInfo = self:GetRecipeQualityPriceForIndex(recipeID, hoveredQualityIndex, transaction, selectedForm)
            price = priceInfo and priceInfo.price or nil
        end
    elseif not isProfessionOutputTooltip then
        price = exactPrice
    end

    if not price and recipeID and owner then
        if qualityContext and qualityContext.qualityMode == 5 and displayedItemLevel then
            local priceInfo = self:GetRecipePriceByDisplayedItemLevel(recipeID, displayedItemLevel, transaction, selectedForm)
            price = priceInfo and priceInfo.price or nil
        end

        if not price and (not qualityContext or qualityContext.qualityMode == 1) and displayedItemLevel then
            local candidates = self:GetRecipeOutputCandidates(recipeID, transaction, selectedForm)
            for _, itemID in ipairs(candidates or {}) do
                local matchedPrice = self:GetPriceForItemLevel(itemID, displayedItemLevel)
                if matchedPrice then
                    price = matchedPrice
                    break
                end
            end
        end

        if not price and hoveredQualityIndex and (not qualityContext or qualityContext.qualityMode == 1) then
            local priceInfo = self:GetRecipeQualityPriceForIndex(recipeID, hoveredQualityIndex, transaction, selectedForm)
            price = priceInfo and priceInfo.price or nil
        end
    end

    if not price and (not qualityContext or qualityContext.qualityMode ~= 2) then
        price = exactPrice
    end

    if not price and (not qualityContext or qualityContext.qualityMode == 1) then
        price = self:GetPriceForLink(link)
    end
    if not price then
        return
    end

    local quantity = self:GetTooltipQuantity(tooltip, data)
    local showUnitPrice = IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown()
    local displayPrice = showUnitPrice and price or (price * math.max(1, quantity))
    local suffix = showUnitPrice and " |cFF9D9D9D(개당)|r" or (quantity > 1 and string.format(" |cFF9D9D9D(x%d)|r", quantity) or "")

    tooltip:AddLine(self:WrapColor("경매장: ", "FF74D06C") .. self:FormatGoldOnly(displayPrice) .. suffix)
end

function ns:GetRecipeOutputItem(recipeID, transaction, schematicForm)
    if not recipeID then
        return nil
    end

    if C_TradeSkillUI.GetRecipeOutputItemData then
        local reagentInfo = transaction and transaction.CreateCraftingReagentInfoTbl and transaction:CreateCraftingReagentInfoTbl() or nil
        local allocationGUID = transaction and transaction.GetAllocationItemGUID and transaction:GetAllocationItemGUID() or nil
        local qualityOverride = schematicForm and schematicForm.GetOutputOverrideQualityID and schematicForm:GetOutputOverrideQualityID() or nil
        local outputData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagentInfo, allocationGUID, qualityOverride)
        if outputData and (outputData.itemID or outputData.hyperlink) then
            return outputData
        end
    end

    if ProfessionsUtil and ProfessionsUtil.GetRecipeSchematic then
        local schematic = schematicForm and schematicForm.recipeSchematic or ProfessionsUtil.GetRecipeSchematic(recipeID, false, nil)
        if schematic then
            local outputItemID = schematic.outputItemID
            if not outputItemID and C_TradeSkillUI.GetRecipeQualityItemIDs then
                local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)
                outputItemID = qualityItemIDs and qualityItemIDs[1] or nil
            end
            if outputItemID then
                local item = Item:CreateFromItemID(outputItemID)
                local itemName, itemLink = C_Item.GetItemInfo(outputItemID)
                return {
                    itemID = outputItemID,
                    hyperlink = itemLink,
                    name = itemName,
                    item = item,
                }
            end
        end
    end

    return nil
end

function ns:GetRecipeOutputCandidates(recipeID, transaction, schematicForm)
    local candidates = {}
    local seen = {}

    local function AddCandidate(itemID)
        itemID = tonumber(itemID)
        if itemID and itemID > 0 and not seen[itemID] then
            seen[itemID] = true
            tinsert(candidates, itemID)
        end
    end

    local recipeInfo = recipeID and C_TradeSkillUI.GetRecipeInfo(recipeID) or nil
    if not recipeInfo then
        return candidates
    end

    local function CollectForRecipe(enumRecipeInfo)
        if not enumRecipeInfo or not enumRecipeInfo.recipeID then
            return
        end

        if C_TradeSkillUI.GetRecipeQualityItemIDs then
            local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs(enumRecipeInfo.recipeID)
            for _, qualityItemID in ipairs(qualityItemIDs or {}) do
                AddCandidate(qualityItemID)
            end
        end

        if ProfessionsUtil and ProfessionsUtil.GetRecipeSchematic then
            local schematic = (schematicForm and enumRecipeInfo.recipeID == recipeID and schematicForm.recipeSchematic)
                or ProfessionsUtil.GetRecipeSchematic(enumRecipeInfo.recipeID, false, nil)
            if schematic and schematic.outputItemID then
                AddCandidate(schematic.outputItemID)
            end
        end

        if C_TradeSkillUI.GetRecipeOutputItemData then
            local reagentInfo = transaction and transaction.CreateCraftingReagentInfoTbl and transaction:CreateCraftingReagentInfoTbl() or nil
            local allocationGUID = transaction and transaction.GetAllocationItemGUID and transaction:GetAllocationItemGUID() or nil
            local qualityOverride = schematicForm and schematicForm.GetOutputOverrideQualityID and schematicForm:GetOutputOverrideQualityID() or nil
            local outputData = C_TradeSkillUI.GetRecipeOutputItemData(enumRecipeInfo.recipeID, reagentInfo, allocationGUID, qualityOverride)
            AddCandidate(outputData and outputData.itemID)
        end
    end

    if Professions and Professions.EnumerateRecipes then
        for _, enumRecipeInfo in Professions.EnumerateRecipes(recipeInfo) do
            CollectForRecipe(enumRecipeInfo)
        end
    else
        CollectForRecipe(recipeInfo)
    end

    return candidates
end

local function GetPreferredQualityIndexes(count)
    if count >= 4 then
        return 2, count
    end
    if count == 2 then
        return 1, 2
    end
    if count >= 1 then
        return 1, count
    end
    return nil, nil
end

local function GetNormalizedRecipeQualityEntries(recipeID, transaction, schematicForm)
    local entries = {}
    local byQualityIndex = {}
    local explicitQualityCount = 0
    local apiQualityCount = 0

    local function AddEntry(itemID, qualityIndex, link, options)
        options = options or {}
        itemID = tonumber(itemID)
        qualityIndex = tonumber(qualityIndex)
        if not itemID or itemID <= 0 or not qualityIndex or qualityIndex <= 0 then
            return
        end

        local itemLevel = link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link) or nil

        local entry = byQualityIndex[qualityIndex]
        if entry then
            if options.source == "explicit" then
                entry.itemID = itemID
                entry.link = link or entry.link
            elseif not entry.itemID then
                entry.itemID = itemID
            elseif entry.itemID == itemID then
                entry.link = link or entry.link
            end
            entry.itemLevel = itemLevel or entry.itemLevel
            return
        end

        entry = {
            itemID = itemID,
            qualityIndex = qualityIndex,
            link = link,
            itemLevel = itemLevel,
        }

        byQualityIndex[qualityIndex] = entry
        tinsert(entries, entry)
    end

    local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs and C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID) or nil
    explicitQualityCount = qualityItemIDs and #qualityItemIDs or 0
    apiQualityCount = explicitQualityCount
    for qualityIndex, itemID in ipairs(qualityItemIDs or {}) do
        AddEntry(itemID, qualityIndex, nil, { source = "explicit" })
    end

    if C_TradeSkillUI.GetRecipeOutputItemData then
        local reagentInfo = transaction and transaction.CreateCraftingReagentInfoTbl and transaction:CreateCraftingReagentInfoTbl() or nil
        local allocationGUID = transaction and transaction.GetAllocationItemGUID and transaction:GetAllocationItemGUID() or nil
        local maxOutputQuality = (explicitQualityCount == 2 or explicitQualityCount == 5) and explicitQualityCount or 5

        for qualityIndex = 1, maxOutputQuality do
            local outputData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagentInfo, allocationGUID, qualityIndex)
            if outputData and outputData.itemID then
                AddEntry(outputData.itemID, qualityIndex, outputData.hyperlink, { source = "output" })
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.qualityIndex < right.qualityIndex
    end)

    if explicitQualityCount ~= 2 and explicitQualityCount ~= 5 and #entries > 1 then
        local uniqueEntries = {}
        local uniqueOrder = {}

        for _, entry in ipairs(entries) do
            local itemLevel = entry.link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(entry.link) or nil
            local uniqueKey = itemLevel and ("ilevel:" .. itemLevel)
                or (entry.link and ("link:" .. entry.link))
                or ("item:" .. tostring(entry.itemID))

            if not uniqueEntries[uniqueKey] then
                uniqueEntries[uniqueKey] = {
                    itemID = entry.itemID,
                    link = entry.link,
                    itemLevel = itemLevel,
                    sourceQualityIndex = entry.qualityIndex,
                }
                tinsert(uniqueOrder, uniqueEntries[uniqueKey])
            end
        end

        if #uniqueOrder >= 2 and #uniqueOrder <= 5 and #uniqueOrder < #entries then
            table.sort(uniqueOrder, function(left, right)
                if left.itemLevel and right.itemLevel and left.itemLevel ~= right.itemLevel then
                    return left.itemLevel < right.itemLevel
                end
                return left.sourceQualityIndex < right.sourceQualityIndex
            end)

            entries = {}
            byQualityIndex = {}
            explicitQualityCount = #uniqueOrder

            for normalizedIndex, entry in ipairs(uniqueOrder) do
                local normalizedEntry = {
                    itemID = entry.itemID,
                    qualityIndex = normalizedIndex,
                    link = entry.link,
                    itemLevel = entry.itemLevel,
                }
                byQualityIndex[normalizedIndex] = normalizedEntry
                tinsert(entries, normalizedEntry)
            end
        end
    end

    if apiQualityCount == 0 and #entries > 1 then
        local processedItemIDs = {}

        for _, entry in ipairs(entries) do
            local itemID = entry and tonumber(entry.itemID) or nil
            if itemID and not processedItemIDs[itemID] then
                processedItemIDs[itemID] = true

                local record = ns:GetDBRecord(itemID)
                local dbQualityEntries = {}

                for _, data in pairs(record or {}) do
                    if type(data) == "table" then
                        local qualityTier = ParseProfessionQualityTier(data.Link)
                        if qualityTier then
                            local existing = dbQualityEntries[qualityTier]
                            local price = data.Price
                            if not existing or (price and existing.Price and price < existing.Price) or (price and not existing.Price) then
                                dbQualityEntries[qualityTier] = {
                                    itemID = itemID,
                                    qualityIndex = qualityTier,
                                    link = data.Link,
                                    itemLevel = tonumber(data.ItemLevel) or nil,
                                    Price = price,
                                }
                            end
                        end
                    end
                end

                for qualityTier, dbEntry in pairs(dbQualityEntries) do
                    local existing = byQualityIndex[qualityTier]
                    if existing then
                        existing.itemID = dbEntry.itemID or existing.itemID
                        existing.link = dbEntry.link or existing.link
                        existing.itemLevel = dbEntry.itemLevel or existing.itemLevel
                    else
                        byQualityIndex[qualityTier] = {
                            itemID = dbEntry.itemID,
                            qualityIndex = qualityTier,
                            link = dbEntry.link,
                            itemLevel = dbEntry.itemLevel,
                        }
                        tinsert(entries, byQualityIndex[qualityTier])
                    end
                end
            end
        end

        table.sort(entries, function(left, right)
            return left.qualityIndex < right.qualityIndex
        end)
    end

    local maxQualityIndex = 0
    for _, entry in ipairs(entries) do
        if entry.qualityIndex > maxQualityIndex then
            maxQualityIndex = entry.qualityIndex
        end
    end

    return entries, byQualityIndex, maxQualityIndex, explicitQualityCount, apiQualityCount
end

local function GetRecipeQualityMode(apiQualityCount, inferredQualityCount, maxQualityIndex)
    if apiQualityCount == 2 or apiQualityCount == 5 then
        return apiQualityCount
    end
    if maxQualityIndex and maxQualityIndex >= 2 and maxQualityIndex <= 5 then
        return maxQualityIndex
    end
    if inferredQualityCount and inferredQualityCount >= 2 and inferredQualityCount <= 5 then
        return inferredQualityCount
    end
    return 1
end

local function BuildRecipeQualitySale(entry, price, itemLevel, linkOverride)
    if not entry or not price then
        return nil
    end

    return {
        itemID = entry.itemID,
        link = linkOverride or entry.link,
        price = price,
        qualityIndex = entry.qualityIndex,
        itemLevel = itemLevel or entry.itemLevel,
    }
end

local function GetEntryItemLevel(entry)
    if not entry then
        return nil
    end

    if entry.itemLevel then
        return entry.itemLevel
    end

    return entry.link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(entry.link) or nil
end

function ns:GetStrictRecipeQualityPrice(entry, qualityMode)
    if not entry then
        return nil
    end

    local itemLevel = GetEntryItemLevel(entry)
    local exactPrice, exactSeen = nil, nil
    local itemLevelPrice, itemLevelSeen = nil, nil
    local rankedPrice, rankedSeen, rankedItemLevel, rankedLink = nil, nil, nil, nil
    if entry.link then
        exactPrice, exactSeen = self:GetExactPriceForLink(entry.link)
    end
    if entry.itemID and itemLevel then
        itemLevelPrice, itemLevelSeen = self:GetPriceForItemLevel(entry.itemID, itemLevel)
    end
    rankedPrice, rankedSeen, rankedItemLevel, rankedLink = self:GetPriceForQualityRank(entry.itemID, entry.qualityIndex)

    if self:IsDebugItemTarget(entry.itemID, entry.link) then
        self:Printf(
            "[DEBUG] quality=%s itemID=%s variant=%s itemLevel=%s exact=%s ilevel=%s ranked=%s link=%s",
            FormatDebugValue(entry.qualityIndex),
            FormatDebugValue(entry.itemID),
            FormatDebugValue(entry.link and self:GetItemVariant(entry.link) or nil),
            FormatDebugValue(itemLevel),
            FormatDebugValue(exactPrice),
            FormatDebugValue(itemLevelPrice),
            FormatDebugValue(rankedPrice),
            FormatDebugValue(entry.link)
        )
    end

    if qualityMode == 2 then
        if exactPrice then
            return exactPrice, exactSeen, itemLevel, entry.link
        end

        if itemLevelPrice then
            return itemLevelPrice, itemLevelSeen, itemLevel, entry.link
        end

        return nil
    end

    if qualityMode == 5 then
        if itemLevelPrice then
            return itemLevelPrice, itemLevelSeen, itemLevel, entry.link
        end

        if exactPrice then
            return exactPrice, exactSeen, itemLevel, entry.link
        end

        return nil
    end

    if exactPrice then
        return exactPrice, exactSeen, itemLevel, entry.link
    end

    if itemLevelPrice then
        return itemLevelPrice, itemLevelSeen, itemLevel, entry.link
    end

    if rankedPrice then
        return rankedPrice, rankedSeen, itemLevel or rankedItemLevel, entry.link or rankedLink
    end

    return nil
end

function ns:GetRecipeQualityContext(recipeID, transaction, schematicForm)
    local entries, byQualityIndex, maxQualityIndex, explicitQualityCount, apiQualityCount = GetNormalizedRecipeQualityEntries(recipeID, transaction, schematicForm)
    local qualityMode = GetRecipeQualityMode(apiQualityCount, explicitQualityCount, maxQualityIndex)

    if self.Settings and self.Settings.debugRecipeTrace and self:IsRecipeDebugTarget(recipeID) then
        local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs and C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID) or nil
        local qualityIDText = {}
        for index, itemID in ipairs(qualityItemIDs or {}) do
            qualityIDText[#qualityIDText + 1] = sformat("%d=%s", index, FormatDebugValue(itemID))
        end

        local outputText = {}
        if C_TradeSkillUI.GetRecipeOutputItemData then
            local reagentInfo = transaction and transaction.CreateCraftingReagentInfoTbl and transaction:CreateCraftingReagentInfoTbl() or nil
            local allocationGUID = transaction and transaction.GetAllocationItemGUID and transaction:GetAllocationItemGUID() or nil
            for qualityIndex = 1, 5 do
                local outputData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagentInfo, allocationGUID, qualityIndex)
                outputText[#outputText + 1] = sformat(
                    "%d:itemID=%s ilevel=%s link=%s",
                    qualityIndex,
                    FormatDebugValue(outputData and outputData.itemID),
                    FormatDebugValue(outputData and outputData.hyperlink and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(outputData.hyperlink) or nil),
                    FormatDebugValue(outputData and outputData.hyperlink)
                )
            end
        end

        local entryText = {}
        for _, entry in ipairs(entries or {}) do
            entryText[#entryText + 1] = sformat(
                "q=%s itemID=%s ilevel=%s variant=%s",
                FormatDebugValue(entry.qualityIndex),
                FormatDebugValue(entry.itemID),
                FormatDebugValue(GetEntryItemLevel(entry)),
                FormatDebugValue(entry.link and self:GetItemVariant(entry.link) or nil)
            )
        end

        local signature = tconcat({
            FormatDebugValue(apiQualityCount),
            FormatDebugValue(explicitQualityCount),
            FormatDebugValue(maxQualityIndex),
            FormatDebugValue(qualityMode),
            tconcat(qualityIDText, " | "),
            tconcat(outputText, " || "),
            tconcat(entryText, " || "),
        }, " ## ")

        self._debugRecipeContextSignatures = self._debugRecipeContextSignatures or {}
        if self._debugRecipeContextSignatures[recipeID] ~= signature then
            self._debugRecipeContextSignatures[recipeID] = signature
            self:DebugRecipeTrace(recipeID, "QualityItemIDs: %s", tconcat(qualityIDText, " | "))
            self:DebugRecipeTrace(recipeID, "OutputItemData: %s", tconcat(outputText, " || "))
            self:DebugRecipeTrace(recipeID, "Context api=%s inferred=%s max=%s mode=%s entries=%s", apiQualityCount, explicitQualityCount, maxQualityIndex, qualityMode, tconcat(entryText, " || "))
        end
    end

    return {
        entries = entries,
        byQualityIndex = byQualityIndex,
        maxQualityIndex = maxQualityIndex,
        explicitQualityCount = explicitQualityCount,
        apiQualityCount = apiQualityCount,
        qualityMode = qualityMode,
    }
end

function ns:GetRecipePriceByDisplayedItemLevel(recipeID, displayedItemLevel, transaction, schematicForm)
    displayedItemLevel = tonumber(displayedItemLevel)
    if not recipeID or not displayedItemLevel then
        return nil
    end

    local context = self:GetRecipeQualityContext(recipeID, transaction, schematicForm)
    if not context or not context.qualityMode or context.qualityMode <= 1 then
        return nil
    end

    local matches = {}
    for _, entry in ipairs(context.entries or {}) do
        if GetEntryItemLevel(entry) == displayedItemLevel then
            matches[#matches + 1] = entry
        end
    end

    if #matches ~= 1 then
        return nil
    end

    local entry = matches[1]
    local price, _, itemLevel, link = self:GetStrictRecipeQualityPrice(entry, context.qualityMode)
    if not price then
        return nil
    end

    return BuildRecipeQualitySale(entry, price, itemLevel, link)
end

function ns:GetRecipeSalePriceInfo(recipeID, transaction, schematicForm)
    local context = self:GetRecipeQualityContext(recipeID, transaction, schematicForm)
    local qualityEntries = context and context.entries or nil
    local byQualityIndex = context and context.byQualityIndex or nil
    local qualityMode = context and context.qualityMode or 1
    if qualityEntries and #qualityEntries > 0 then
        local baseIndex, topIndex = GetPreferredQualityIndexes(qualityMode)
        local topSale = nil
        local baseSale = nil
        local topMissingText = nil

        local function ResolveStrictSale(index)
            local entry = byQualityIndex and byQualityIndex[index] or nil
            if not entry then
                self:DebugRecipeTrace(recipeID, "ResolveStrictSale q%s entry=nil", FormatDebugValue(index))
                return nil
            end

            local price, _, itemLevel, link = self:GetStrictRecipeQualityPrice(entry, qualityMode)
            self:DebugRecipeTrace(
                recipeID,
                "ResolveStrictSale q%s itemID=%s ilevel=%s price=%s link=%s",
                FormatDebugValue(index),
                FormatDebugValue(entry.itemID),
                FormatDebugValue(itemLevel),
                FormatDebugValue(price),
                FormatDebugValue(link or entry.link)
            )
            return BuildRecipeQualitySale(entry, price, itemLevel, link)
        end

        local function ResolveFirstAvailable(indexes)
            for _, index in ipairs(indexes or {}) do
                local sale = ResolveStrictSale(index)
                if sale and sale.price then
                    return sale
                end
            end
            return nil
        end

        if qualityMode == 2 then
            -- Two-quality recipes should default to rank 1 and show rank 2 as the top option.
            baseSale = ResolveFirstAvailable({ 1, 2 })
            topSale = ResolveFirstAvailable({ 2 })
        elseif qualityMode >= 4 then
            baseSale = ResolveFirstAvailable({ 2, 1 })
            local topCandidates = {}
            for qualityIndex = qualityMode, math.max(qualityMode - 1, 1), -1 do
                topCandidates[#topCandidates + 1] = qualityIndex
            end
            topSale = ResolveFirstAvailable(topCandidates)
            if not topSale then
                topMissingText = "상위등급 없음"
            end
        else
            baseSale = ResolveStrictSale(baseIndex)
            topSale = topIndex and topIndex ~= baseIndex and ResolveStrictSale(topIndex) or nil
        end

        self:DebugRecipeTrace(
            recipeID,
            "SaleInfo mode=%s base=q%s/%s top=q%s/%s topMissing=%s",
            FormatDebugValue(qualityMode),
            FormatDebugValue(baseSale and baseSale.qualityIndex or nil),
            FormatDebugValue(baseSale and baseSale.price or nil),
            FormatDebugValue(topSale and topSale.qualityIndex or nil),
            FormatDebugValue(topSale and topSale.price or nil),
            FormatDebugValue(topMissingText)
        )

        return {
            mode = qualityMode,
            base = baseSale,
            top = topSale,
            baseDisplayIndex = baseSale and baseSale.qualityIndex or baseIndex,
            topDisplayIndex = topSale and topSale.qualityIndex or topIndex,
            topMissingText = topMissingText,
            qualityItemIDs = qualityEntries,
        }
    end

    local outputData = self:GetRecipeOutputItem(recipeID, transaction, schematicForm)
    local outputItemID = outputData and outputData.itemID
    local outputLink = outputData and outputData.hyperlink
    local salePrice = outputLink and self:GetPriceForLink(outputLink) or (outputItemID and self:GetPriceForItemID(outputItemID)) or nil

    if not salePrice then
        for _, candidateItemID in ipairs(self:GetRecipeOutputCandidates(recipeID, transaction, schematicForm)) do
            local candidatePrice = self:GetPriceForItemID(candidateItemID)
            if candidatePrice then
                salePrice = candidatePrice
                outputItemID = outputItemID or candidateItemID
                break
            end
        end
    end

    if not salePrice then
        return {
            mode = 0,
            base = nil,
            top = nil,
            baseDisplayIndex = nil,
            topDisplayIndex = nil,
        }
    end

    return {
        mode = 0,
        base = {
            itemID = outputItemID,
            price = salePrice,
            qualityIndex = 1,
            link = outputLink,
        },
        top = nil,
        baseDisplayIndex = 1,
        topDisplayIndex = nil,
    }
end

function ns:GetRecipeQualityPriceForIndex(recipeID, qualityIndex, transaction, schematicForm)
    qualityIndex = tonumber(qualityIndex)
    if not recipeID or not qualityIndex or qualityIndex <= 0 then
        return nil
    end

    local context = self:GetRecipeQualityContext(recipeID, transaction, schematicForm)
    local entry = context and context.byQualityIndex and context.byQualityIndex[qualityIndex] or nil
    if not entry then
        return nil
    end

    local price, _, itemLevel, link = self:GetStrictRecipeQualityPrice(entry, context.qualityMode)
    if not price then
        return nil
    end

    return {
        itemID = entry.itemID,
        link = link or entry.link,
        price = price,
        qualityIndex = entry.qualityIndex,
        itemLevel = itemLevel,
    }
end

function ns:GetRecipeDisplayEconomics(recipeID, transaction, schematicForm)
    local data = self:GetRecipeEconomics(recipeID, transaction, schematicForm)
    if not data then
        return nil
    end

    if not data.hasSalePrice then
        return data
    end

    return data
end

function ns:GetCheapestReagentPrice(reagentSlotSchematic)
    if not reagentSlotSchematic or not reagentSlotSchematic.reagents then
        return nil, nil, nil
    end

    local bestItemID
    local bestPrice
    local bestReagent
    for _, reagent in ipairs(reagentSlotSchematic.reagents) do
        local itemID = reagent.itemID or reagent.reagentID
        if itemID then
            local price = self:GetPriceForItemID(itemID)
            if price and (not bestPrice or price < bestPrice) then
                bestPrice = price
                bestItemID = itemID
                bestReagent = reagent
            end
        end
    end

    return bestPrice, bestItemID, bestReagent
end

function ns:GetFixedRecipeReagentPrice(recipeID, reagentSlotSchematic, fallbackSlotIndex)
    if not recipeID or not reagentSlotSchematic or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeFixedReagentItemLink then
        return nil, nil, nil, nil
    end

    local slotIndex = reagentSlotSchematic.dataSlotIndex
        or reagentSlotSchematic.slotIndex
        or reagentSlotSchematic.reagentSlotIndex
        or fallbackSlotIndex

    if not slotIndex then
        return nil, nil, nil, nil
    end

    local link = C_TradeSkillUI.GetRecipeFixedReagentItemLink(recipeID, slotIndex)
    if not link then
        return nil, nil, slotIndex, nil
    end

    local price = self:GetPriceForLink(link)
    local itemID = GetItemIDFromLink(link)
    if not price and itemID then
        price = self:GetPriceForItemID(itemID)
    end

    return price, itemID, slotIndex, link
end

local function GetReagentQuantityForSlot(reagentSlotSchematic, reagent)
    if not reagentSlotSchematic then
        return 0
    end

    if reagentSlotSchematic.GetQuantityRequired and reagent then
        local ok, quantity = pcall(reagentSlotSchematic.GetQuantityRequired, reagentSlotSchematic, reagent)
        quantity = ParsePositiveNumber(ok and quantity or nil)
        if quantity then
            return quantity
        end
    end

    return ParsePositiveNumber(reagentSlotSchematic.quantityRequired) or 0
end

function ns:GetDetailedRecipeCost(transaction)
    if not transaction then
        return nil
    end

    local totalCost = 0
    local anyPrice = false
    local infoTable = transaction.CreateCraftingReagentInfoTbl and transaction:CreateCraftingReagentInfoTbl() or {}

    for _, reagentInfo in ipairs(infoTable) do
        local reagent = reagentInfo.reagent
        local quantity = reagentInfo.quantity or (reagent and reagent.quantity) or 0
        local itemID = reagent and (reagent.itemID or reagent.reagentID)
        if itemID and quantity and quantity > 0 then
            local unitPrice = self:GetPriceForItemID(itemID)
            if unitPrice then
                totalCost = totalCost + (unitPrice * quantity)
                anyPrice = true
            end
        end
    end

    if not anyPrice then
        return nil
    end
    return totalCost
end

function ns:GetBaselineRecipeCost(recipeID)
    if not recipeID or not ProfessionsUtil or not ProfessionsUtil.GetRecipeSchematic then
        return nil
    end

    local schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, false, nil)
    if not schematic or not schematic.reagentSlotSchematics then
        return nil
    end

    local totalCost = 0
    local anyPrice = false
    local unresolvedRequiredSlot = false
    for index, reagentSlotSchematic in ipairs(schematic.reagentSlotSchematics) do
        local isBasicSlot = reagentSlotSchematic.reagentType == Enum.CraftingReagentType.Basic
        local isRequiredModifyingSlot = ProfessionsUtil.IsReagentSlotModifyingRequired(reagentSlotSchematic)

        if isBasicSlot then
            local unitPrice, itemID, reagent = self:GetCheapestReagentPrice(reagentSlotSchematic)
            local quantity = GetReagentQuantityForSlot(reagentSlotSchematic, reagent)
            if unitPrice and quantity > 0 then
                totalCost = totalCost + (unitPrice * quantity)
                anyPrice = true
            end

            self:DebugRecipeTrace(
                recipeID,
                "Baseline basic slot index=%s quantity=%s itemID=%s unitPrice=%s",
                FormatDebugValue(index),
                FormatDebugValue(quantity),
                FormatDebugValue(itemID),
                FormatDebugValue(unitPrice)
            )
        elseif isRequiredModifyingSlot then
            local unitPrice, fixedItemID, slotIndex, fixedLink = self:GetFixedRecipeReagentPrice(recipeID, reagentSlotSchematic, index)
            local matchedReagent = nil
            for _, reagent in ipairs(reagentSlotSchematic.reagents or {}) do
                local reagentItemID = reagent and (reagent.itemID or reagent.reagentID)
                if reagentItemID and fixedItemID and reagentItemID == fixedItemID then
                    matchedReagent = reagent
                    break
                end
            end
            local quantity = GetReagentQuantityForSlot(reagentSlotSchematic, matchedReagent)
            if unitPrice and quantity > 0 then
                totalCost = totalCost + (unitPrice * quantity)
                anyPrice = true
            else
                unresolvedRequiredSlot = true
            end

            self:DebugRecipeTrace(
                recipeID,
                "Baseline required slot index=%s dataSlot=%s quantity=%s fixedItemID=%s fixedPrice=%s unresolved=%s",
                FormatDebugValue(index),
                FormatDebugValue(slotIndex),
                FormatDebugValue(quantity),
                FormatDebugValue(fixedItemID),
                FormatDebugValue(unitPrice),
                FormatDebugValue(not unitPrice)
            )
            self:DebugRecipeTrace(recipeID, "Baseline required link=%s", FormatDebugValue(fixedLink))
        end
    end

    if unresolvedRequiredSlot then
        self:DebugRecipeTrace(recipeID, "BaselineCost unresolved required slot")
    end

    if not anyPrice then
        self:DebugRecipeTrace(recipeID, "BaselineCost no priced reagents")
        return nil
    end

    self:DebugRecipeTrace(recipeID, "BaselineCost total=%s", FormatDebugValue(totalCost))
    return totalCost
end

function ns:GetRecipeEconomics(recipeID, transaction, schematicForm)
    local usingTransaction = transaction ~= nil
    local totalCost = transaction and self:GetDetailedRecipeCost(transaction) or self:GetBaselineRecipeCost(recipeID)

    if not totalCost or totalCost <= 0 then
        self:DebugRecipeTrace(recipeID, "Economics source=%s totalCost=nil", usingTransaction and "selected-transaction" or "baseline")
        return nil
    end

    local saleInfo = self:GetRecipeSalePriceInfo(recipeID, transaction, schematicForm)
    local baseSale = saleInfo and saleInfo.base or nil
    local topSale = saleInfo and saleInfo.top or nil
    local salePrice = baseSale and baseSale.price or nil

    local auctionCutRate = self.Settings and self.Settings.auctionCutRate or 0.05
    local auctionCut = salePrice and math.floor(salePrice * auctionCutRate) or nil
    local netSale = salePrice and (salePrice - auctionCut) or nil
    local profit = netSale and (netSale - totalCost) or nil
    local margin = (profit and totalCost > 0) and (profit / totalCost) or nil
    local topAuctionCut = topSale and topSale.price and math.floor(topSale.price * auctionCutRate) or nil
    local topNetSale = topSale and topSale.price and topAuctionCut and (topSale.price - topAuctionCut) or nil
    local topProfit = topNetSale and (topNetSale - totalCost) or nil
    local topMargin = (topProfit and totalCost > 0) and (topProfit / totalCost) or nil
    local hasAnySalePrice = salePrice ~= nil or (topSale and topSale.price ~= nil) or false

    self:DebugRecipeTrace(
        recipeID,
        "Economics source=%s totalCost=%s sale=%s baseQ=%s topSale=%s topQ=%s hasAny=%s",
        usingTransaction and "selected-transaction" or "baseline",
        FormatDebugValue(totalCost),
        FormatDebugValue(salePrice),
        FormatDebugValue(baseSale and baseSale.qualityIndex or nil),
        FormatDebugValue(topSale and topSale.price or nil),
        FormatDebugValue(topSale and topSale.qualityIndex or nil),
        FormatDebugValue(hasAnySalePrice)
    )

    return {
        salePrice = salePrice,
        auctionCut = auctionCut,
        netSale = netSale,
        totalCost = totalCost,
        profit = profit,
        margin = margin,
        outputItemID = (baseSale and baseSale.itemID) or (topSale and topSale.itemID) or nil,
        outputLink = (baseSale and baseSale.link) or (topSale and topSale.link) or nil,
        qualityMode = saleInfo and saleInfo.mode or 0,
        qualityBaseIndex = baseSale and baseSale.qualityIndex or (saleInfo and saleInfo.baseDisplayIndex or nil),
        qualityTopIndex = topSale and topSale.qualityIndex or (saleInfo and saleInfo.topDisplayIndex or nil),
        topSalePrice = topSale and topSale.price or nil,
        topSaleItemID = topSale and topSale.itemID or nil,
        topSaleLink = topSale and topSale.link or nil,
        topAuctionCut = topAuctionCut,
        topProfit = topProfit,
        topMargin = topMargin,
        topSaleStatusText = saleInfo and saleInfo.topMissingText or nil,
        hasSalePrice = hasAnySalePrice,
    }
end

function ns:GetRecipeProfit(recipeID, transaction, schematicForm)
    local data = self:GetRecipeEconomics(recipeID, transaction, schematicForm)
    if not data or not data.hasSalePrice then
        return nil
    end
    return data
end

function ns:GetRecipeProfitText(recipeID, transaction, schematicForm)
    local data = self:GetRecipeEconomics(recipeID, transaction, schematicForm)
    if not data or not data.hasSalePrice then
        return nil, self.colors.neutral, data
    end

    local color = self:GetMarginColor(data.margin)
    local text = string.format("%s %s", self:FormatGoldOnly(data.profit), self:FormatPercent(data.margin))
    return text, color, data
end

function ns:GetRecipeProfitGoldText(recipeID, transaction, schematicForm)
    local data = self:GetRecipeEconomics(recipeID, transaction, schematicForm)
    if not data then
        return nil, self.colors.neutral, nil
    end

    if not data.hasSalePrice then
        return self:FormatGoldOnly(data.totalCost), self.colors.neutral, data
    end

    local color = self:GetMarginColor(data.margin)
    return self:FormatGoldOnly(data.profit), color, data
end

function ns:SetupCompatibilityAPI()
    _G.CraftProfit_PriceCheck = function(link)
        return ns:GetPriceForLink(link)
    end

    _G.CraftProfit_PriceCheckItemID = function(itemID)
        return ns:GetPriceForItemID(itemID)
    end

end

function ns:SetupSlashCommands()
    SLASH_CRAFTPROFIT1 = "/craftprofit"
    SLASH_CRAFTPROFIT2 = "/cp"
    SlashCmdList.CRAFTPROFIT = function(message)
        local rawMessage = strtrim(message or "")
        local command = string.lower(rawMessage)
        if command == "scan" then
            ns:StartScan()
        elseif command == "status" then
            ns:Printf("Last scan: %s", ns:GetTimeText(ns.Settings.lastScanAt))
            ns:Printf("Next scan: %s", ns:GetTimeText(ns.Settings.nextScanAt))
        elseif command == "debug on" then
            ns.Settings.debugRecipeTrace = true
            ns:Printf("디버그를 켰습니다. 대상: %s", ns.Settings.debugRecipeTarget or "-")
        elseif command == "debug off" then
            ns.Settings.debugRecipeTrace = false
            ns:Printf("디버그를 껐습니다.")
        elseif command == "debug status" then
            ns:Printf("디버그: %s / 대상: %s", ns.Settings.debugRecipeTrace and "ON" or "OFF", ns.Settings.debugRecipeTarget or "-")
        elseif string.find(command, "debug target ", 1, true) == 1 then
            local target = strtrim(string.sub(rawMessage, 14))
            if target == "" then
                ns:Printf("대상 이름을 함께 입력해주세요. 예: /cp debug target 밀수업자의 보강된 바지,주입된 비늘매듭 생가죽")
            else
                ns.Settings.debugRecipeTarget = target
                ns:Printf("디버그 대상을 바꿨습니다: %s", target)
            end
        elseif command == "wipe" then
            wipe(ns.PriceDB[ns.realmKey])
            wipe(ns.PriceDB[ns.regionKey])
            ns:Printf("Price data cleared.")
        else
            ns:Printf("/cp scan, /cp status, /cp debug on, /cp debug off, /cp debug status, /cp debug target <이름[,이름]>, /cp wipe")
        end
    end
end
