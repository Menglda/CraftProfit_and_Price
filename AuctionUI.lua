local _, ns = ...

local CreateFrame = CreateFrame

function ns:UpdateScanButton(progress, total)
    if not self.scanButton then
        return
    end

    if self.scanAwaitingReady then
        self.scanButton:SetText("Waiting...")
        self.scanButton:Disable()
        if self.scanStatus then
            self.scanStatus:SetText(self:WrapColor("블리자드 경매장 응답 대기 중", self.colors.lossLow))
        end
        return
    end

    if self.scanInProgress then
        self.scanButton:SetText(string.format("%d / %d", progress or 0, total or 0))
        self.scanButton:Disable()
        if self.scanStatus then
            self.scanStatus:SetText(self:WrapColor("스캔 중", self.colors.profitMid))
        end
        return
    end

    local remaining = self:GetCooldownRemaining()
    if remaining > 0 then
        self.scanButton:SetText("Scan Cooldown")
        self.scanButton:Disable()
        if self.scanStatus then
            self.scanStatus:SetText(string.format("다음 가능: %s", SecondsToTime(remaining)))
        end
    else
        self.scanButton:SetText("Start Scan")
        self.scanButton:Enable()
        if self.scanStatus then
            self.scanStatus:SetText(string.format("최근 스캔: %s", self:GetTimeText(self.Settings.lastScanAt)))
        end
    end
end

function ns:EnsureAuctionUI()
    if self.auctionUIReady or not AuctionHouseFrame then
        return
    end

    self.auctionUIReady = true

    local button = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    button:SetSize(140, 22)
    button:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", 168, 8)
    button:SetText("Start Scan")
    button:SetScript("OnClick", function()
        ns:StartScan()
    end)
    self.scanButton = button

    local status = AuctionHouseFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 4)
    status:SetJustifyH("LEFT")
    status:SetWidth(220)
    self.scanStatus = status

    hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function()
        ns:UpdateAuctionVisibility()
    end)

    if AuctionHouseItemBuyFrameMixin then
        hooksecurefunc(AuctionHouseItemBuyFrameMixin, "SetItemKey", function(frame, itemKey)
            ns:UpdateAuctionGraph(frame, itemKey)
        end)
    end

    self:UpdateAuctionVisibility()
    self:UpdateScanButton()
end

function ns:UpdateAuctionVisibility()
    if not self.scanButton or not AuctionHouseFrame then
        return
    end

    local displayMode = AuctionHouseFrame.displayMode
    local show = displayMode == AuctionHouseFrameDisplayMode.Buy
        or displayMode == AuctionHouseFrameDisplayMode.ItemBuy
        or displayMode == AuctionHouseFrameDisplayMode.CommoditiesBuy

    self.scanButton:SetShown(show)
    if self.scanStatus then
        self.scanStatus:SetShown(show)
    end
    self:UpdateScanButton()
end

function ns:OnAuctionHouseShow()
    self:EnsureAuctionUI()
    self:UpdateScanButton()
end

function ns:OnAuctionHouseClosed()
    self:UpdateScanButton()
end

function ns:UpdateAuctionGraph(frame, itemKey)
    if frame and frame.CraftProfitSparkline then
        frame.CraftProfitSparkline:Hide()
    end

    if not frame or not frame.ItemList or not frame.ItemList.RefreshFrame then
        return
    end
end

function ns:RefreshAuctionGraph()
    if AuctionHouseFrame and AuctionHouseFrame.ItemBuyFrame and AuctionHouseFrame.ItemBuyFrame.CraftProfitSparkline then
        AuctionHouseFrame.ItemBuyFrame.CraftProfitSparkline:Hide()
    end
end

function ns:SetupAuctionHooks()
    if AuctionHouseFrame then
        self:EnsureAuctionUI()
    else
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_AuctionHouseUI" then
                ns:EnsureAuctionUI()
            end
        end)
    end
end
