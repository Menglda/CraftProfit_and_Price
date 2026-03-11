local _, ns = ...

local GetNumReplicateItems = C_AuctionHouse.GetNumReplicateItems
local GetReplicateItemInfo = C_AuctionHouse.GetReplicateItemInfo
local GetReplicateItemLink = C_AuctionHouse.GetReplicateItemLink
local ReplicateItems = C_AuctionHouse.ReplicateItems
local IsThrottledMessageSystemReady = C_AuctionHouse.IsThrottledMessageSystemReady
local GetItemMaxStackSizeByID = C_Item.GetItemMaxStackSizeByID
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
local Item = Item
local IsLinkType = LinkUtil.IsLinkType
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT

local function IsActiveScan(self, scanRunId)
    return self.scanInProgress
        and self.scanRunId == scanRunId
        and self.scanBuffer ~= nil
        and self.scanTemp ~= nil
        and self.scanStats ~= nil
end

local function DebugScanSummary(self, phase, extraText)
    if not self or not self.Settings or not self.Settings.debugRecipeTrace then
        return
    end

    local readyText = IsThrottledMessageSystemReady and tostring(IsThrottledMessageSystemReady()) or "nil"
    local replicateCount = GetNumReplicateItems and GetNumReplicateItems() or nil
    self:Printf(
        "[DEBUG] 스캔 요약 | %s | ready=%s | replicate=%s%s",
        tostring(phase or "-"),
        readyText,
        tostring(replicateCount or "nil"),
        extraText and extraText ~= "" and (" | " .. extraText) or ""
    )
end

local function ClearThrottleWait(self)
    self.scanAwaitingReady = false
    self.scanWaitRunId = nil
    self.frame:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
end

function ns:AbortScan(reason)
    if not self.scanInProgress and not self.scanAwaitingReady then
        return
    end

    DebugScanSummary(self, "중단", reason)

    if self.scanPendingLoads then
        for _, cancel in pairs(self.scanPendingLoads) do
            cancel()
        end
    end

    self.scanInProgress = false
    self.scanStartedAt = nil
    self.scanBuffer = nil
    self.scanTemp = nil
    self.scanStats = nil
    self.scanPendingLoads = nil
    self.frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    ClearThrottleWait(self)
    self:UpdateScanButton()

    if reason then
        self:Printf("%s", reason)
    end
end

local function BuildVariantBucket(priceByVariant, timestamp)
    local record = {}
    for variant, data in pairs(priceByVariant or {}) do
        if type(data) == "table" then
            record[variant] = {
                Price = data.Price,
                Link = data.Link,
                ItemLevel = data.ItemLevel,
                LastSeen = timestamp,
            }
        else
            record[variant] = {
                Price = data,
                LastSeen = timestamp,
            }
        end
    end
    return record
end

local function CompareBuckets(oldBucket, newBucket, stats)
    for itemID, newVariants in pairs(newBucket or {}) do
        local oldVariants = oldBucket and oldBucket[itemID] or nil
        for variant, newData in pairs(newVariants) do
            local oldData = oldVariants and oldVariants[variant] or nil
            if not oldData then
                stats.new = stats.new + 1
            elseif oldData.Price ~= newData.Price then
                stats.updated = stats.updated + 1
            end
        end
    end

    for itemID, oldVariants in pairs(oldBucket or {}) do
        local newVariants = newBucket and newBucket[itemID] or nil
        for variant in pairs(oldVariants) do
            if not (newVariants and newVariants[variant]) then
                stats.removed = stats.removed + 1
            end
        end
    end
end

function ns:StartScan()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:Printf("경매장을 연 상태에서만 스캔할 수 있습니다.")
        return
    end

    if self.scanAwaitingReady then
        self:Printf("블리자드 경매장 응답 가능 상태를 기다리는 중입니다.")
        return
    end

    if not self:CanScan() then
        self:Printf("다음 스캔 가능까지 %s 남았습니다.", SecondsToTime(self:GetCooldownRemaining()))
        return
    end

    if IsThrottledMessageSystemReady and not IsThrottledMessageSystemReady() then
        self.scanWaitRunId = (self.scanWaitRunId or 0) + 1
        self.scanAwaitingReady = true
        self.frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        self:UpdateScanButton()
        DebugScanSummary(self, "대기진입", "throttle-not-ready")
        self:Printf("블리자드 경매장 제한으로 인해 스캔 가능 상태를 기다리는 중입니다.")

        local waitRunId = self.scanWaitRunId
        C_Timer.After(30, function()
            if self.scanAwaitingReady and self.scanWaitRunId == waitRunId then
                self:AbortScan("블리자드 경매장 제한 대기 시간이 길어 스캔을 중단했습니다. 잠시 후 다시 시도해주세요.")
            end
        end)
        return
    end

    self.scanInProgress = true
    self.scanRunId = (self.scanRunId or 0) + 1
    self.scanStartedAt = time()
    self.Settings.lastScanAt = self.scanStartedAt
    self.Settings.nextScanAt = self.scanStartedAt + (self.Settings.scanCooldown or 1200)
    self.scanBuffer = {}
    self.scanTemp = {}
    self.scanStats = { new = 0, updated = 0, removed = 0 }
    self.scanPendingLoads = {}
    ClearThrottleWait(self)

    self.frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    self:UpdateScanButton()
    DebugScanSummary(self, "시작", "ReplicateItems")
    self:Printf("경매장 전체 가격 스캔을 시작합니다.")

    local scanRunId = self.scanRunId
    local responseTimeoutSeconds = 20
    C_Timer.After(responseTimeoutSeconds, function()
        if IsActiveScan(self, scanRunId) then
            self:AbortScan("스캔 응답이 없어 중단했습니다. 경매장 창을 그대로 둔 상태에서 다시 시도해주세요.")
        end
    end)

    local ok, err = pcall(ReplicateItems)
    if not ok then
        self:AbortScan("스캔 시작에 실패했습니다.")
    end
end

function ns:OnReplicateItemListUpdate()
    self.frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    DebugScanSummary(self, "응답수신", "REPLICATE_ITEM_LIST_UPDATE")
    self:CollectReplicateItems()
end

function ns:CollectReplicateItems()
    local total = GetNumReplicateItems()
    local pendingLoads = self.scanPendingLoads or {}
    local processed = 0
    local scanRunId = self.scanRunId

    if not total or total <= 0 then
        self:AbortScan("경매장 데이터가 아직 준비되지 않았습니다. 경매장 창을 그대로 둔 상태에서 다시 시도해주세요.")
        return
    end

    DebugScanSummary(self, "수집시작", string.format("total=%s", tostring(total)))

    local function StoreReplicateIndex(index, stackable)
        if not IsActiveScan(self, scanRunId) then
            return
        end

        local count, quality, _, _, _, _, _, price, _, _, _, _, _, _, itemID, status = select(3, GetReplicateItemInfo(index))
        local link = GetReplicateItemLink(index)
        if not link or not count or not price or not itemID or not status or count <= 0 or price <= 0 or itemID <= 0 then
            return
        end

        local isCommodity = stackable > 1
        if isCommodity and count < (self.Settings.ignoreCommodityStacksBelow or 1) then
            return
        end

        self.scanBuffer[#self.scanBuffer + 1] = {
            itemID = itemID,
            quality = quality,
            link = link,
            price = price / count,
            itemLevel = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link) or nil,
            isCommodity = isCommodity,
        }
        processed = processed + 1
        self:UpdateScanButton(processed, total)
    end

    for index = 0, total - 1 do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, itemID = select(3, GetReplicateItemInfo(index))
        local stackable = itemID and GetItemMaxStackSizeByID(itemID)
        if stackable then
            StoreReplicateIndex(index, stackable)
        elseif itemID then
            local item = Item:CreateFromItemID(itemID)
            if not item:IsItemEmpty() then
                pendingLoads[item] = item:ContinueWithCancelOnItemLoad(function()
                    if self.scanRunId ~= scanRunId then
                        pendingLoads[item] = nil
                        return
                    end

                    local loadedStackable = GetItemMaxStackSizeByID(itemID) or 1
                    pendingLoads[item] = nil
                    StoreReplicateIndex(index, loadedStackable)
                    if IsActiveScan(self, scanRunId) and not next(pendingLoads) then
                        self:FinalizeScan()
                    end
                end)
            end
        end
    end

    if not next(pendingLoads) then
        self:FinalizeScan()
    else
        C_Timer.After(15, function()
            if self.scanRunId ~= scanRunId then
                return
            end

            for _, cancel in pairs(pendingLoads) do
                cancel()
            end
            if IsActiveScan(self, scanRunId) then
                self:FinalizeScan()
            end
        end)
    end
end

function ns:FinalizeScan()
    if not self.scanInProgress then
        return
    end

    DebugScanSummary(self, "완료직전", string.format("new=%d updated=%d removed=%d", self.scanStats.new, self.scanStats.updated, self.scanStats.removed))
    self.scanInProgress = false
    self.scanStartedAt = nil
    self:ParseScanBuffer()
    self:SyncPriceDB()
    self.scanBuffer = nil
    self.scanTemp = nil
    self.scanPendingLoads = nil
    ClearThrottleWait(self)
    self:UpdateScanButton()
    PlaySound(SOUNDKIT.AUCTION_WINDOW_CLOSE)
    self:Printf("스캔 완료. 신규 %d / 갱신 %d / 미관측 %d", self.scanStats.new, self.scanStats.updated, self.scanStats.removed)
    if self.ScheduleProfessionViewsRefresh then
        self:ScheduleProfessionViewsRefresh("scan-finished")
    else
        self:RefreshProfessionViews()
    end
    self:RefreshAuctionGraph()
end

function ns:OnAuctionHouseThrottleReady()
    if not self.scanAwaitingReady then
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:AbortScan("경매장 창이 닫혀 스캔 대기를 중단했습니다.")
        return
    end

    ClearThrottleWait(self)
    self:UpdateScanButton()
    self:Printf("블리자드 경매장 응답 가능 상태가 되어 스캔을 다시 시작합니다.")
    self:StartScan()
end

function ns:ParseScanBuffer()
    for _, offer in ipairs(self.scanBuffer or {}) do
        local itemVariant
        if IsLinkType(offer.link, "battlepet") then
            itemVariant = self:GetPetVariant(offer.link)
        else
            itemVariant = self:GetItemVariant(offer.link)
        end

        if not self.scanTemp[offer.itemID] then
            self.scanTemp[offer.itemID] = {
                isCommodity = offer.isCommodity,
                cheapestPrice = offer.price,
                variants = {},
            }
        end

        local entry = self.scanTemp[offer.itemID]
        entry.cheapestPrice = math.min(entry.cheapestPrice, offer.price)

        local current = entry.variants[itemVariant]
        if not current or offer.price < current.Price then
            entry.variants[itemVariant] = {
                Price = offer.price,
                Link = offer.link,
                ItemLevel = offer.itemLevel,
            }
        end
    end
end

function ns:SyncPriceDB()
    local now = self.Settings.lastScanAt or time()
    local newRealmBucket = {}
    local newRegionBucket = {}

    for itemID, data in pairs(self.scanTemp or {}) do
        local targetKey = data.isCommodity and self.regionKey or self.realmKey
        local bucket = targetKey == self.regionKey and newRegionBucket or newRealmBucket
        bucket[itemID] = BuildVariantBucket(data.variants, now)
    end

    CompareBuckets(self.PriceDB[self.realmKey], newRealmBucket, self.scanStats)
    CompareBuckets(self.PriceDB[self.regionKey], newRegionBucket, self.scanStats)

    self.PriceDB[self.realmKey] = newRealmBucket
    self.PriceDB[self.regionKey] = newRegionBucket
end
