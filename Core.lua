local addonName, ns = ...

CraftProfit = ns
ns.name = addonName
ns.PET_CAGE_ITEM_ID = 82800

local CreateFrame = CreateFrame
local GetRealmName = GetRealmName
local GetCVar = GetCVar
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
local SecondsToTime = SecondsToTime
local TooltipDataProcessor = TooltipDataProcessor
local max = math.max
local tinsert = table.insert
local wipe = wipe
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"

ns.frame = CreateFrame("Frame")

ns.defaults = {
    lastScanAt = 0,
    nextScanAt = 0,
    scanCooldown = 0,
    auctionCutRate = 0.05,
    ignoreCommodityStacksBelow = 1,
    showTooltipPrices = true,
    showRecipeListProfit = true,
    debugRecipeTrace = false,
    debugRecipeTarget = "",
    dbVersion = 3,
}

ns.colors = {
    profitLow = "FF9DFF9D",
    profitMid = "FF1EFF00",
    profitHigh = "FFA335EE",
    lossLow = "FFFF9C38",
    lossHigh = "FFFF2020",
    neutral = "FF9D9D9D",
    text = "FFFFFFFF",
}

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                CopyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            CopyDefaults(target[key], value)
        end
    end
end

function ns:Printf(text, ...)
    local prefix = "|cFF74D06C[CraftProfit]|r "
    if select("#", ...) > 0 then
        print(prefix .. string.format(text, ...))
    else
        print(prefix .. text)
    end
end

function ns:WrapColor(text, hexColor)
    return string.format("|c%s%s|r", hexColor or self.colors.text, text or "")
end

function ns:FormatMoney(value)
    if type(value) ~= "number" then
        return "-"
    end
    if value < 0 then
        return "-" .. GetCoinTextureString(math.abs(value))
    end
    return GetCoinTextureString(value)
end

function ns:FormatPercent(ratio)
    if type(ratio) ~= "number" then
        return "-"
    end
    return string.format("%.1f%%", ratio * 100)
end

local function FormatWholeNumber(value)
    local text = tostring(value or 0)
    local pieces = {}

    while #text > 3 do
        tinsert(pieces, 1, text:sub(-3))
        text = text:sub(1, -4)
    end

    if text ~= "" then
        tinsert(pieces, 1, text)
    end

    return table.concat(pieces, ",")
end

function ns:FormatGoldOnly(value)
    if type(value) ~= "number" then
        return "-"
    end

    local gold = math.floor((math.abs(value) / 10000) + 0.5)
    local prefix = value < 0 and "-" or ""
    local formatted = FormatWholeNumber(gold)
    return string.format("%s%s%s", prefix, formatted, GOLD_ICON)
end

function ns:GetMarginColor(ratio)
    if type(ratio) ~= "number" then
        return self.colors.neutral
    end
    if ratio >= 0.20 then
        return self.colors.profitHigh
    end
    if ratio >= 0.10 then
        return self.colors.profitMid
    end
    if ratio >= 0 then
        return self.colors.profitLow
    end
    if ratio >= -0.10 then
        return self.colors.lossLow
    end
    return self.colors.lossHigh
end

function ns:GetCooldownRemaining()
    if not self.Settings or (self.Settings.scanCooldown or 0) <= 0 then
        return 0
    end
    local remaining = (self.Settings and self.Settings.nextScanAt or 0) - time()
    return max(0, remaining)
end

function ns:CanScan()
    return self:GetCooldownRemaining() <= 0 and not self.scanInProgress
end

function ns:GetTimeText(timestamp)
    if not timestamp or timestamp <= 0 then
        return "never"
    end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function OnAddonLoaded()
    CraftProfitSettings = CraftProfitSettings or {}
    CraftProfitPriceDB = CraftProfitPriceDB or {}

    ns.Settings = CraftProfitSettings
    ns.PriceDB = CraftProfitPriceDB
    CopyDefaults(ns.Settings, ns.defaults)
    ns.Settings.scanCooldown = 0
    ns.Settings.nextScanAt = 0
    ns.Settings.debugRecipeTrace = false
    ns.Settings.debugRecipeTarget = ""

    if ns.Settings.dbVersion ~= ns.defaults.dbVersion then
        wipe(ns.PriceDB)
        ns.Settings.dbVersion = ns.defaults.dbVersion
        ns:Printf("가격 데이터 형식이 바뀌어 기존 스캔 데이터를 초기화했습니다. 경매장 재스캔이 필요합니다.")
    end

    ns.realmKey = GetRealmName()
    ns.regionKey = GetCVar("portal")
    ns.PriceDB[ns.realmKey] = ns.PriceDB[ns.realmKey] or {}
    ns.PriceDB[ns.regionKey] = ns.PriceDB[ns.regionKey] or {}

    if ns.Settings.showTooltipPrices and TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            ns:TooltipAddPrice(tooltip, data)
        end)
    end

    ns:SetupCompatibilityAPI()
    ns:SetupSlashCommands()
    ns:SetupAuctionHooks()
    ns:SetupProfessionHooks()
end

ns.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        OnAddonLoaded()
        ns.frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "AUCTION_HOUSE_SHOW" then
        ns:OnAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns:OnAuctionHouseClosed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        ns:OnReplicateItemListUpdate()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        ns:OnAuctionHouseThrottleReady()
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "CRAFTING_DETAILS_UPDATE" or event == "TRACKED_RECIPE_UPDATE" then
        if type(ns.ScheduleProfessionViewsRefresh) == "function" then
            ns:ScheduleProfessionViewsRefresh(event)
        elseif type(ns.RefreshProfessionViews) == "function" then
            ns:RefreshProfessionViews()
        end
    end
end)

ns.frame:RegisterEvent("ADDON_LOADED")
ns.frame:RegisterEvent("AUCTION_HOUSE_SHOW")
ns.frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
ns.frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
ns.frame:RegisterEvent("CRAFTING_DETAILS_UPDATE")
ns.frame:RegisterEvent("TRACKED_RECIPE_UPDATE")
