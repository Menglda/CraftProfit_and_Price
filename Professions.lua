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

local function NormalizeQualityIndex(value)
    value = GetNumericValue(value)
    if value and value >= 1 and value <= 5 then
        return value
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

local function CollectDisplayedQualityCandidates(source)
    local candidates = {}
    local queue = {}
    local seen = {}
    local directMemberNames = {
        "recipeInfo",
        "currentRecipeInfo",
        "recipeData",
        "elementData",
        "data",
        "node",
        "outputItem",
        "operationInfo",
        "craftingOutputInfo",
    }
    local providerMemberNames = {
        "GetElementData",
        "GetData",
        "GetRecipeInfo",
        "GetCurrentRecipeInfo",
        "GetOutputItem",
    }

    local function Enqueue(candidate, depth)
        if type(candidate) ~= "table" or depth > 2 or seen[candidate] then
            return
        end
        seen[candidate] = true
        queue[#queue + 1] = {
            value = candidate,
            depth = depth,
        }
        candidates[#candidates + 1] = candidate
    end

    Enqueue(source, 0)

    local queueIndex = 1
    while queueIndex <= #queue do
        local item = queue[queueIndex]
        queueIndex = queueIndex + 1

        if item.depth < 2 then
            for _, memberName in ipairs(directMemberNames) do
                Enqueue(item.value[memberName], item.depth + 1)
            end

            for _, memberName in ipairs(providerMemberNames) do
                local member = item.value[memberName]
                if type(member) == "function" then
                    local ok, result = pcall(member, item.value)
                    if ok then
                        Enqueue(result, item.depth + 1)
                    end
                end
            end
        end
    end

    return candidates
end

local function FindQualityIndexByQualityID(qualityIDs, qualityID)
    qualityID = GetNumericValue(qualityID)
    if type(qualityIDs) ~= "table" or not qualityID then
        return nil
    end

    for index = 1, 5 do
        local candidateID = GetNumericValue(qualityIDs[index])
        if candidateID and candidateID == qualityID then
            return index
        end
    end

    return nil
end

local function GetDisplayedQualityFromQualityIDs(source)
    local candidates = CollectDisplayedQualityCandidates(source)
    local qualityIDTables = {}
    local overrideQualityIDs = {}

    for _, candidate in ipairs(candidates) do
        local qualityIDs = candidate.qualityIDs
        if type(qualityIDs) == "table" then
            qualityIDTables[#qualityIDTables + 1] = qualityIDs
        end

        local overrideQualityID = GetNumericValue(ReadNumericMember(candidate, "GetOutputOverrideQualityID"))
            or GetNumericValue(ReadNumericMember(candidate, "outputOverrideQualityID"))
            or GetNumericValue(ReadNumericMember(candidate, "selectedQualityID"))
            or GetNumericValue(ReadNumericMember(candidate, "currentQualityID"))

        if overrideQualityID then
            overrideQualityIDs[#overrideQualityIDs + 1] = overrideQualityID
        end
    end

    for _, overrideQualityID in ipairs(overrideQualityIDs) do
        for _, qualityIDs in ipairs(qualityIDTables) do
            local qualityIndex = FindQualityIndexByQualityID(qualityIDs, overrideQualityID)
            if qualityIndex then
                return qualityIndex, "qualityIDs:GetOutputOverrideQualityID"
            end
        end
    end

    return nil
end

local function GetDisplayedQualityInfo(source)
    local qualityIndex, origin = GetDisplayedQualityFromQualityIDs(source)
    if qualityIndex then
        return qualityIndex, origin
    end

    local memberNames = {
        "GetQualityID",
        "GetOutputQualityID",
        "GetCraftingQualityID",
        "GetCurrentQualityID",
        "GetExpectedQuality",
        "qualityID",
        "QualityID",
        "qualityIndex",
        "outputQualityID",
        "outputQuality",
        "craftingQualityID",
        "currentQuality",
        "currentQualityIndex",
        "currentQualityID",
        "expectedQuality",
        "expectedQualityIndex",
        "displayQuality",
        "displayQualityIndex",
    }

    for _, candidate in ipairs(CollectDisplayedQualityCandidates(source)) do
        for _, memberName in ipairs(memberNames) do
            local value = NormalizeQualityIndex(ReadNumericMember(candidate, memberName))
            if value then
                return value, memberName
            end
        end
    end

    return nil
end

local function BuildFrameVisualDebugSummary(frame)
    if type(frame) ~= "table" then
        return "frame=nil"
    end

    local parts = {}

    local function AddPart(value)
        if not value or value == "" or #parts >= 12 then
            return
        end
        parts[#parts + 1] = value
    end

    local function IsInterestingText(text)
        if type(text) ~= "string" or text == "" then
            return false
        end

        return string.find(text, "★", 1, true) ~= nil
            or string.find(text, "품질", 1, true) ~= nil
            or string.find(string.lower(text), "quality", 1, true) ~= nil
    end

    local function IsInterestingAtlas(atlas)
        if type(atlas) ~= "string" or atlas == "" then
            return false
        end

        local lowerAtlas = string.lower(atlas)
        return string.find(lowerAtlas, "quality", 1, true) ~= nil
            or string.find(lowerAtlas, "tier", 1, true) ~= nil
            or string.find(lowerAtlas, "profession", 1, true) ~= nil
    end

    local function DescribeRegion(region, prefix)
        if type(region) ~= "table" or #parts >= 12 then
            return
        end

        local objectType = region.GetObjectType and region:GetObjectType() or nil
        if objectType == "FontString" then
            local text = region.GetText and region:GetText() or nil
            if IsInterestingText(text) then
                AddPart(string.format("%sFont=%s", prefix, text))
            end
            return
        end

        if objectType == "Texture" then
            local atlas = region.GetAtlas and region:GetAtlas() or nil
            if IsInterestingAtlas(atlas) then
                AddPart(string.format("%sAtlas=%s", prefix, atlas))
                return
            end

            local texture = region.GetTexture and region:GetTexture() or nil
            if type(texture) == "string" and IsInterestingAtlas(texture) then
                AddPart(string.format("%sTexture=%s", prefix, texture))
            end
        end
    end

    if type(frame.GetRegions) == "function" then
        local regions = { frame:GetRegions() }
        for index, region in ipairs(regions) do
            DescribeRegion(region, string.format("region%d:", index))
            if #parts >= 12 then
                break
            end
        end
    end

    if #parts < 12 and type(frame.GetChildren) == "function" then
        local children = { frame:GetChildren() }
        for childIndex, child in ipairs(children) do
            if type(child) == "table" and type(child.GetRegions) == "function" then
                local childRegions = { child:GetRegions() }
                for regionIndex, region in ipairs(childRegions) do
                    DescribeRegion(region, string.format("child%dregion%d:", childIndex, regionIndex))
                    if #parts >= 12 then
                        break
                    end
                end
            end

            if #parts >= 12 then
                break
            end
        end
    end

    if #parts == 0 then
        return "no-visual-quality-markers"
    end

    return table.concat(parts, " | ")
end

local function FormatDebugArrayCompact(values, prefix)
    if type(values) ~= "table" then
        return nil
    end

    local parts = {}
    for index = 1, 5 do
        local value = values[index]
        if value == nil then
            break
        end
        parts[#parts + 1] = (prefix or "") .. tostring(value)
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, "/")
end

local function FormatDebugQualityLabel(qualityIndex)
    qualityIndex = GetNumericValue(qualityIndex)
    if not qualityIndex or qualityIndex <= 0 then
        return "미확인"
    end
    return tostring(qualityIndex) .. "성"
end

local function BuildEconomicsDebugSummary(self, recipeID, displayQualityIndex, displayQualityOrigin, data, extraText)
    local parts = {}

    if displayQualityIndex then
        parts[#parts + 1] = string.format("현재=%s", FormatDebugQualityLabel(displayQualityIndex))
    else
        parts[#parts + 1] = "현재=미확인"
    end

    if displayQualityOrigin then
        parts[#parts + 1] = string.format("판독=%s", tostring(displayQualityOrigin))
    end

    if data and data.outputQuantity then
        parts[#parts + 1] = string.format("수량=x%s", tostring(data.outputQuantity))
    end

    if data and data.hasSalePrice then
        local baseQuality = data.qualityBaseIndex or data.requestedDisplayQualityIndex or nil
        parts[#parts + 1] = string.format("기준=%s %s", FormatDebugQualityLabel(baseQuality), self:FormatGoldOnly(data.salePrice))

        if data.topSalePrice and data.qualityTopIndex and data.qualityTopIndex > (data.qualityBaseIndex or 0) then
            parts[#parts + 1] = string.format("최고=%s %s", FormatDebugQualityLabel(data.qualityTopIndex), self:FormatGoldOnly(data.topSalePrice))
        elseif data.topSaleStatusText then
            parts[#parts + 1] = string.format("최고=%s", data.topSaleStatusText)
        else
            parts[#parts + 1] = "최고=없음"
        end
    elseif data then
        if data.baseSaleStatusText then
            parts[#parts + 1] = string.format("기준=%s", data.baseSaleStatusText)
        else
            parts[#parts + 1] = "기준=없음"
        end
        if data.topSaleStatusText then
            parts[#parts + 1] = string.format("최고=%s", data.topSaleStatusText)
        end
        parts[#parts + 1] = string.format("판매가=없음 재료=%s", self:FormatGoldOnly(data.totalCost))
    else
        parts[#parts + 1] = "계산=없음"
    end

    if extraText and extraText ~= "" then
        parts[#parts + 1] = extraText
    end

    return table.concat(parts, " | ")
end

local function BuildDisplayedQualityDebugSummary(source)
    if type(source) ~= "table" then
        return "source=nil"
    end

    local function DescribeDebugArray(value, limit)
        if type(value) ~= "table" then
            return nil
        end

        limit = limit or 8
        local items = {}
        local count = 0
        for index = 1, limit do
            local entry = value[index]
            if entry == nil then
                break
            end
            count = index
            items[#items + 1] = tostring(entry)
        end

        if count == 0 then
            return nil
        end

        local suffix = value[count + 1] ~= nil and ",..." or ""
        return "{" .. table.concat(items, ",") .. suffix .. "}"
    end

    local function DescribeMemberResult(result)
        if result == nil then
            return "nil"
        end

        if type(result) == "table" then
            local describedArray = DescribeDebugArray(result)
            if describedArray then
                return describedArray
            end
            return "<table>"
        end

        return tostring(result)
    end

    local function DescribeSpecialTable(name, value)
        if type(value) ~= "table" then
            return nil
        end

        if name == "qualityIDs" or name == "qualityIlvlBonuses" then
            return DescribeDebugArray(value) or "{}"
        end

        if name == "selectedRecipeLevels" then
            return DescribeDebugArray(value) or "{}"
        end

        if name == "AllocateBestQualityCheckbox" then
            local parts = {}
            local memberNames = { "GetChecked", "IsEnabled", "IsShown", "GetShown" }
            for _, memberName in ipairs(memberNames) do
                local member = value[memberName]
                if type(member) == "function" then
                    local ok, result = pcall(member, value)
                    if ok and result ~= nil then
                        parts[#parts + 1] = string.format("%s=%s", memberName, tostring(result))
                    end
                end
            end
            return #parts > 0 and ("{" .. table.concat(parts, ",") .. "}") or "<table>"
        end

        if name == "RecipeLevelBar" then
            local parts = {}
            local memberNames = {
                "GetValue",
                "GetMinMaxValues",
                "GetCurrentValue",
                "GetUpperValue",
                "GetLowerValue",
                "GetShown",
                "IsShown",
            }
            for _, memberName in ipairs(memberNames) do
                local member = value[memberName]
                if type(member) == "function" then
                    local ok, resultA, resultB = pcall(member, value)
                    if ok then
                        if resultB ~= nil then
                            parts[#parts + 1] = string.format("%s=%s,%s", memberName, tostring(resultA), tostring(resultB))
                        elseif resultA ~= nil then
                            parts[#parts + 1] = string.format("%s=%s", memberName, tostring(resultA))
                        end
                    end
                end
            end
            return #parts > 0 and ("{" .. table.concat(parts, ",") .. "}") or "<table>"
        end

        if name == "currentRecipeInfo" or name == "QualityDialog" then
            local parts = {}
            local memberNames = {
                "recipeID",
                "recipeLevel",
                "maxQuality",
                "quality",
                "qualityID",
                "qualityIndex",
                "currentQuality",
                "currentQualityID",
                "currentQualityIndex",
                "selectedQuality",
                "selectedQualityID",
                "selectedQualityIndex",
                "qualityIDs",
                "qualityIlvlBonuses",
                "selectedRecipeLevels",
                "currentRecipeLevel",
            }
            for _, memberName in ipairs(memberNames) do
                local memberValue = value[memberName]
                if type(memberValue) == "function" then
                    local ok, result = pcall(memberValue, value)
                    if ok and result ~= nil then
                        parts[#parts + 1] = string.format("%s=%s", memberName, DescribeMemberResult(result))
                    end
                elseif memberValue ~= nil then
                    parts[#parts + 1] = string.format("%s=%s", memberName, DescribeMemberResult(memberValue))
                end
            end
            return #parts > 0 and ("{" .. table.concat(parts, ",") .. "}") or "<table>"
        end

        return nil
    end

    local interestingNamePatterns = {
        "quality",
        "output",
        "expected",
        "current",
        "tier",
        "rank",
        "override",
        "level",
    }
    local summary = {}
    local seenNames = {}

    local function IsInteresting(name)
        if type(name) ~= "string" then
            return false
        end

        local lowerName = string.lower(name)
        for _, pattern in ipairs(interestingNamePatterns) do
            if string.find(lowerName, pattern, 1, true) then
                return true
            end
        end
        return false
    end

    local function AddName(candidate, name)
        if seenNames[name] or not IsInteresting(name) then
            return
        end
        seenNames[name] = true

        local value = candidate[name]
        if type(value) == "function" then
            local ok, result = pcall(value, candidate)
            if ok then
                summary[#summary + 1] = string.format("%s=%s", name, DescribeMemberResult(result))
            else
                summary[#summary + 1] = string.format("%s=<fn:error>", name)
            end
        elseif value ~= nil then
            local special = DescribeSpecialTable(name, value)
            if special then
                summary[#summary + 1] = string.format("%s=%s", name, special)
            else
                summary[#summary + 1] = string.format("%s=%s", name, DescribeMemberResult(value))
            end
        else
            summary[#summary + 1] = string.format("%s=nil", name)
        end
    end

    for _, candidate in ipairs(CollectDisplayedQualityCandidates(source)) do
        local priorityNames = {
            "GetCurrentRecipeLevel",
            "GetOutputOverrideQualityID",
            "maxQuality",
            "qualityIDs",
            "qualityIlvlBonuses",
            "alwaysUsesLowestQuality",
            "hasSingleItemOutput",
            "currentRecipeInfo",
            "QualityDialog",
            "AllocateBestQualityCheckbox",
            "selectedRecipeLevels",
            "RecipeLevelBar",
        }
        for _, name in ipairs(priorityNames) do
            AddName(candidate, name)
            if #summary >= 18 then
                break
            end
        end
        if #summary >= 18 then
            break
        end

        for name in pairs(candidate) do
            AddName(candidate, name)
            if #summary >= 18 then
                break
            end
        end
        if #summary >= 18 then
            break
        end

        local meta = getmetatable(candidate)
        local metaIndex = meta and meta.__index or nil
        if type(metaIndex) == "table" then
            for name in pairs(metaIndex) do
                AddName(candidate, name)
                if #summary >= 18 then
                    break
                end
            end
        end

        if #summary >= 18 then
            break
        end
    end

    if #summary == 0 then
        return "no-quality-members"
    end

    return table.concat(summary, " | ")
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

function ns:GetDisplayedProfessionQualityInfo(source)
    return GetDisplayedQualityInfo(source)
end

function ns:GetSimulatedRecipeListQualityInfo(recipeID, source, fallbackSource)
    if not recipeID
        or not C_TradeSkillUI
        or not C_TradeSkillUI.GetCraftingOperationInfo
        or not Professions
        or not ProfessionsUtil
        or not ProfessionsUtil.GetRecipeSchematic
        or type(CreateProfessionsRecipeTransaction) ~= "function"
        or type(Professions.AllocateAllBasicReagents) ~= "function"
    then
        return nil
    end

    local recipeInfo = ResolveRecipeInfo(source) or ResolveRecipeInfo(fallbackSource)
    recipeInfo = (Professions.GetHighestLearnedRecipe and Professions.GetHighestLearnedRecipe(recipeInfo)) or recipeInfo
    if not recipeInfo and C_TradeSkillUI.GetRecipeInfo then
        recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
    end

    if type(recipeInfo) ~= "table" or not recipeInfo.supportsQualities then
        return nil
    end

    local shouldAllocateBest = not recipeInfo.alwaysUsesLowestQuality
        and Professions.ShouldAllocateBestQualityReagents
        and Professions.ShouldAllocateBestQualityReagents()

    local cacheKey = table.concat({
        tostring(recipeID),
        tostring(GetNumericValue(recipeInfo.unlockedRecipeLevel) or "-"),
        shouldAllocateBest and "best" or "low",
    }, ":")

    self._recipeListQualitySimulationCache = self._recipeListQualitySimulationCache or {}
    if self._recipeListQualitySimulationCache[cacheKey] ~= nil then
        local cached = self._recipeListQualitySimulationCache[cacheKey]
        if cached then
            return cached.qualityIndex, cached.origin, cached.outputQuantity
        end
        return nil
    end

    local schematic = ProfessionsUtil.GetRecipeSchematic(
        recipeID,
        recipeInfo.isRecraft or false,
        GetNumericValue(recipeInfo.unlockedRecipeLevel)
    )
    if not schematic then
        self._recipeListQualitySimulationCache[cacheKey] = false
        return nil
    end

    local transaction = CreateProfessionsRecipeTransaction(schematic)
    if not transaction then
        self._recipeListQualitySimulationCache[cacheKey] = false
        return nil
    end

    Professions.AllocateAllBasicReagents(transaction, shouldAllocateBest)

    local operationInfo = C_TradeSkillUI.GetCraftingOperationInfo(
        recipeID,
        transaction:CreateCraftingReagentInfoTbl(),
        transaction:GetAllocationItemGUID(),
        false
    )
    local qualityIndex = NormalizeQualityIndex(operationInfo and operationInfo.craftingQuality)
    if not qualityIndex then
        self._recipeListQualitySimulationCache[cacheKey] = false
        return nil
    end

    local result = {
        qualityIndex = qualityIndex,
        origin = "simulated:auto-basic",
        outputQuantity = ns.GetRecipeOutputQuantity and ns:GetRecipeOutputQuantity(recipeID, transaction, nil) or 1,
    }
    self._recipeListQualitySimulationCache[cacheKey] = result
    return result.qualityIndex, result.origin, result.outputQuantity
end

function ns:GetRecipeListDisplay(recipeID, source, fallbackSource)
    -- Keep the recipe list stable regardless of which recipe is selected.
    local outputQuantity = nil
    local displayQualityIndex, displayQualityOrigin = self:GetDisplayedProfessionQualityInfo(source)
    if not displayQualityIndex and fallbackSource then
        displayQualityIndex, displayQualityOrigin = self:GetDisplayedProfessionQualityInfo(fallbackSource)
    end
    local simulatedQualityIndex, simulatedQualityOrigin, simulatedOutputQuantity = self:GetSimulatedRecipeListQualityInfo(recipeID, source, fallbackSource)
    if not displayQualityIndex then
        displayQualityIndex, displayQualityOrigin = simulatedQualityIndex, simulatedQualityOrigin
    end
    outputQuantity = simulatedOutputQuantity

    local options = nil
    if displayQualityIndex or outputQuantity then
        options = {}
        if displayQualityIndex then
            options.displayQualityIndex = displayQualityIndex
        end
        if outputQuantity and outputQuantity > 0 then
            options.outputQuantityOverride = outputQuantity
        end
    end
    local data = self:GetRecipeDisplayEconomics(recipeID, nil, nil, options)
    local dataSource = data and "baseline" or "none"

    self:DebugRecipeTrace(
        recipeID,
        "ListDisplay source=%s displayQuality=%s origin=%s",
        dataSource or "none",
        tostring(displayQualityIndex or "nil"),
        tostring(displayQualityOrigin or "nil")
    )

    if self.DebugRecipeSummary and self.IsRecipeDebugTarget and self:IsRecipeDebugTarget(recipeID) then
        local apiRecipeInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID) or nil
        local extraText = nil
        if apiRecipeInfo then
            local bonusText = FormatDebugArrayCompact(apiRecipeInfo.qualityIlvlBonuses, "+")
            extraText = string.format(
                "목록API=maxQ%s itemLevel=%s%s",
                tostring(apiRecipeInfo.maxQuality or "-"),
                tostring(apiRecipeInfo.itemLevel or "-"),
                bonusText and (" bonus=" .. bonusText) or ""
            )
        end
        self:DebugRecipeSummary(recipeID, "목록 요약", BuildEconomicsDebugSummary(self, recipeID, displayQualityIndex, displayQualityOrigin, data, extraText))
    end

    if not displayQualityIndex and self.IsRecipeDebugTarget and self:IsRecipeDebugTarget(recipeID) then
        self:DebugRecipeTrace(recipeID, "ListDisplay probe button=%s", BuildDisplayedQualityDebugSummary(source))
        if fallbackSource then
            self:DebugRecipeTrace(recipeID, "ListDisplay probe node=%s", BuildDisplayedQualityDebugSummary(fallbackSource))
        end
        self:DebugRecipeTrace(recipeID, "ListDisplay visuals button=%s", BuildFrameVisualDebugSummary(source))
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
            local apiRecipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
            self:DebugRecipeTrace(recipeID, "ListDisplay api recipeInfo=%s", BuildDisplayedQualityDebugSummary(apiRecipeInfo))
        end
        if ProfessionsUtil and ProfessionsUtil.GetRecipeSchematic then
            local apiSchematic = ProfessionsUtil.GetRecipeSchematic(recipeID, false, nil)
            self:DebugRecipeTrace(recipeID, "ListDisplay api schematic=%s", BuildDisplayedQualityDebugSummary(apiSchematic))
        end
    end

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
    local delays

    if reason == "transaction-updated" or reason == "crafting-page-refresh" then
        delays = { 0.1 }
    else
        delays = { 0, 0.12 }
    end

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

    local text, color = self:GetRecipeListDisplay(recipeID, button, node)
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
    local displayQualityIndex, displayQualityOrigin = self:GetDisplayedProfessionQualityInfo(form)
    local outputQuantity = self.GetRecipeOutputQuantity and self:GetRecipeOutputQuantity(recipeInfo.recipeID, transaction, form) or nil
    local options = nil
    if displayQualityIndex or outputQuantity then
        options = {}
        if displayQualityIndex then
            options.displayQualityIndex = displayQualityIndex
        end
        if outputQuantity and outputQuantity > 0 then
            options.outputQuantityOverride = outputQuantity
        end
    end
    local data = self:GetRecipeDisplayEconomics(recipeInfo.recipeID, nil, nil, options)
    if not data then
        summary:Hide()
        return
    end

    self:DebugRecipeTrace(
        recipeInfo.recipeID,
        "SchematicDisplay displayQuality=%s origin=%s",
        tostring(displayQualityIndex or "nil"),
        tostring(displayQualityOrigin or "nil")
    )

    if self.DebugRecipeSummary and self.IsRecipeDebugTarget and self:IsRecipeDebugTarget(recipeInfo.recipeID) then
        local currentRecipeInfo = form and form.currentRecipeInfo or nil
        local qualityIDText = currentRecipeInfo and FormatDebugArrayCompact(currentRecipeInfo.qualityIDs) or nil
        local bonusText = currentRecipeInfo and FormatDebugArrayCompact(currentRecipeInfo.qualityIlvlBonuses, "+") or nil
        local extraText = nil
        if qualityIDText or bonusText then
            extraText = string.format(
                "세부UI=%s%s",
                qualityIDText and ("IDs " .. qualityIDText) or "",
                bonusText and ((qualityIDText and " / " or "") .. "bonus=" .. bonusText) or ""
            )
        end
        self:DebugRecipeSummary(recipeInfo.recipeID, "세부창 요약", BuildEconomicsDebugSummary(self, recipeInfo.recipeID, displayQualityIndex, displayQualityOrigin, data, extraText))
    end

    if not displayQualityIndex and self.IsRecipeDebugTarget and self:IsRecipeDebugTarget(recipeInfo.recipeID) then
        self:DebugRecipeTrace(recipeInfo.recipeID, "SchematicDisplay probe form=%s", BuildDisplayedQualityDebugSummary(form))
        self:DebugRecipeTrace(recipeInfo.recipeID, "SchematicDisplay visuals form=%s", BuildFrameVisualDebugSummary(form))
    end

    local formQualityContext = self.GetRecipeQualityContext and self:GetRecipeQualityContext(recipeInfo.recipeID, transaction, form) or nil
    if formQualityContext and formQualityContext.qualityMode == 2 then
        data.qualityMode = 2
    end

    if not data.hasSalePrice then
        summary.sale:SetText(self:WrapColor("재료+비용: ", self.colors.neutral) .. self:WrapColor(self:FormatGoldOnly(data.totalCost), self.colors.neutral))
        if data.baseSaleStatusText then
            summary.fee:SetText(self:WrapColor("기준가: ", "FF74D06C") .. self:WrapColor(data.baseSaleStatusText, self.colors.text))
            summary.fee:Show()
        else
            summary.fee:Hide()
        end
        if data.topSaleStatusText then
            summary.cost:SetText(self:WrapColor("추가 기준가: ", "FF74D06C") .. self:WrapColor(data.topSaleStatusText, self.colors.text))
            summary.cost:Show()
        else
            summary.cost:Hide()
        end
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
    local suppressMissingTopDisplay = data.qualityMode == 2
        and data.qualityBaseIndex == 2
        and data.topSaleStatusText == "상위 등급 없음"
    local hasMissingTopDisplay = not hasTopDisplay
        and not suppressMissingTopDisplay
        and data.topSaleStatusText

    local baseSaleText = data.baseSaleStatusText and not data.salePrice
        and self:WrapColor(data.baseSaleStatusText, self.colors.text)
        or self:FormatGoldOnly(data.salePrice)
    local saleText = self:WrapColor("기준가: ", "FF74D06C") .. baseSaleText
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        saleText = saleText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay then
        saleText = saleText .. ", " .. self:FormatGoldOnly(data.topSalePrice) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    elseif hasMissingTopDisplay then
        saleText = saleText .. self:WrapColor(string.format(", (%s)", data.topSaleStatusText), self.colors.text)
    end

    local costText = self:WrapColor("재료+비용: ", "FF74D06C")
        .. self:FormatGoldOnly(data.totalCost)

    local baseProfitText = data.baseSaleStatusText and not data.profit
        and self:WrapColor(data.baseSaleStatusText, self.colors.text)
        or self:WrapColor(self:FormatGoldOnly(data.profit), color)
    local profitText = self:WrapColor("순이익: ", "FF74D06C")
        .. baseProfitText
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        profitText = profitText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay and data.topProfit then
        profitText = profitText .. ", " .. self:WrapColor(self:FormatGoldOnly(data.topProfit), topColor) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    elseif hasMissingTopDisplay then
        profitText = profitText .. self:WrapColor(string.format(", (%s)", data.topSaleStatusText), self.colors.text)
    end

    local baseMarginText = data.baseSaleStatusText and type(data.margin) ~= "number"
        and self:WrapColor(data.baseSaleStatusText, self.colors.text)
        or self:WrapColor(self:FormatPercent(data.margin), color)
    local marginText = self:WrapColor("이익률: ", "FF74D06C")
        .. baseMarginText
    if data.qualityMode == 2 and data.qualityBaseIndex == 2 then
        marginText = marginText .. self:WrapColor("(2등급)", self.colors.text)
    end
    if hasTopDisplay and data.topMargin then
        marginText = marginText .. ", " .. self:WrapColor(self:FormatPercent(data.topMargin), topColor) .. self:WrapColor(string.format("(%d등급)", data.qualityTopIndex), self.colors.text)
    elseif hasMissingTopDisplay then
        marginText = marginText .. self:WrapColor(string.format(", (%s)", data.topSaleStatusText), self.colors.text)
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

    self._recipeListQualitySimulationCache = nil

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
        end

        if ProfessionsRecipeSchematicFormMixin then
            hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Init", function(form)
                ns:ScheduleProfessionViewsRefresh("schematic-init")
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
