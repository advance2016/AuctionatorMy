AuctionatorShoppingTabFrameMixin = {}

AutoKillerConfig = {}
AutoKillerConfig["银矿石"] = 48000
--AutoKillerConfig["银矿石"] = 50000
AutoKillerConfig["铜矿石"] = 2000
AutoKillerConfig["锡矿石"] = 7000
AutoKillerConfig["钴矿石"] = 10100

AutoCurrentIndex = 1

IsSearchAuto = false
SearchAutoTimer = nil

KillDatas = nil

local EVENTBUS_EVENTS = {
  Auctionator.Shopping.Events.ListImportFinished,
  Auctionator.Shopping.Tab.Events.ListSearchRequested,
  Auctionator.Shopping.Tab.Events.ShowHistoricalPrices,
  Auctionator.Shopping.Tab.Events.UpdateSearchTerm,
  Auctionator.Shopping.Tab.Events.BuyScreenShown,
}

local function TableLength(t)
  if t == nil then
    return 0
  end
  local res=0
  for k,v in pairs(t) do
      res=res+1
  end
  return res
end

function AuctionatorShoppingTabFrameMixin:DoSearch(terms, options)
  if #terms == 0 then
    return
  end

  if options == nil and Auctionator.Constants.IsClassic and IsShiftKeyDown() then
    options = { searchAllPages = true }
  end

  self:StopSearch()

  self.searchRunning = true
  Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchStart, terms)
  self.SearchProvider:Search(terms, options or {})
  self:StartSpinner()
end

function AuctionatorShoppingTabFrameMixin:StopSearch()
  self.searchRunning = false
  self.SearchProvider:AbortSearch()
end

function AuctionatorShoppingTabFrameMixin:StartSpinner()
  self.ListsContainer.SpinnerAnim:Play()
  self.ListsContainer.LoadingSpinner:Show()
  self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_START", self:GetAppropriateListSearchName()))
  self.ListsContainer.ResultsText:Show()
end

function AuctionatorShoppingTabFrameMixin:CloseAnyDialogs()
  for _, d in ipairs(self.dialogs) do
    if d:IsShown() then
      d:Hide()
    end
  end
end

function AuctionatorShoppingTabFrameMixin:OnLoad()
  Auctionator.EventBus:RegisterSource(self, "AuctionatorShoppingTabFrameMixin")

  self.ResultsListing:Init(self.DataProvider)

  self.dialogs = {}

  self.itemDialog = CreateFrame("Frame", "AuctionatorShoppingTabItemFrame", self, "AuctionatorShoppingItemTemplate")
  self.itemDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.itemDialog)

  self.exportDialog = CreateFrame("Frame", "AuctionatorExportListFrame", self, "AuctionatorExportListTemplate")
  self.exportDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportDialog)

  self.importDialog = CreateFrame("Frame", "AuctionatorImportListFrame", self, "AuctionatorImportListTemplate")
  self.importDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.importDialog)

  self.exportCSVDialog = CreateFrame("Frame", nil, self, "AuctionatorExportTextFrame")
  self.exportCSVDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportCSVDialog)

  self.ExportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.exportDialog:Show()
  end)
  self.ImportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.importDialog:Show()
  end)

  self.itemHistoryDialog = CreateFrame("Frame", "AuctionatorItemHistoryFrame", self, "AuctionatorItemHistoryTemplate")
  self.itemHistoryDialog:SetPoint("CENTER")
  self.itemHistoryDialog:Init()

  self:SetupSearchProvider()

  self:SetupListsContainer()
  self:SetupRecentsContainer()
  self:SetupTopSearch()

  self.NewListButton:SetScript("OnClick", function()
      StaticPopup_Show(Auctionator.Constants.DialogNames.CreateShoppingList, nil, nil, {view = self})
  end)

  self.ContainerTabs:SetView(Auctionator.Config.Get(Auctionator.Config.Options.SHOPPING_LAST_CONTAINER_VIEW))

  self.shouldDefaultOpenOnShow = true
  if Auctionator.Constants.IsVanilla then
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
  else
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
  end
end

function AuctionatorShoppingTabFrameMixin:SetupSearchProvider()
  self.SearchProvider:InitSearch(
    function(results)
      self.searchRunning = false
      Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchEnd, results)
      self.ListsContainer.SpinnerAnim:Stop()
      self.ListsContainer.LoadingSpinner:Hide()
      self.ListsContainer.ResultsText:Hide()
      if TableLength(KillDatas) > 0 then
        self.BuyKiller:Show()
      else
        self.BuyKiller:Hide()
      end
    end,
    function(current, total, partialResults)
      Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate, partialResults, total, current)
      self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_STATUS", current, total, self:GetAppropriateListSearchName()))
    end
  )
end

function AuctionatorShoppingTabFrameMixin:SetupListsContainer()
  self.ListsContainer:SetOnListExpanded(function()
    if Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    end
    self.SearchOptions:OnListExpanded()
  end)
  self.ListsContainer:SetOnListCollapsed(function()
    self:StopSearch()
    self.SearchOptions:OnListCollapsed()
  end)
  self.ListsContainer:SetOnSearchTermClicked(function(list, searchTerm, index)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.ListsContainer:TemporarilySelectSearchTerm(index)
  end)
  self.ListsContainer:SetOnSearchTermDelete(function(list, searchTerm, index)
    list:DeleteItem(index)
  end)
  self.ListsContainer:SetOnSearchTermEdit(function(list, searchTerm, index)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EDIT_ITEM_HEADER, AUCTIONATOR_L_EDIT_ITEM)
    self.itemDialog:SetOnFinishedClicked(function(newItemString)
      list:AlterItem(index, newItemString)
    end)
    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.ListsContainer:SetOnListSearch(function(list)
    self.singleSearch = false
    self:DoSearch(list:GetAllItems())
  end)
  self.ListsContainer:SetOnListEdit(function(list)
    if list:IsTemporary() then
      StaticPopupDialogs[Auctionator.Constants.DialogNames.MakePermanentShoppingList].text = AUCTIONATOR_L_MAKE_PERMANENT_CONFIRM:format(list:GetName()):gsub("%%", "%%%%")
      StaticPopup_Show(Auctionator.Constants.DialogNames.MakePermanentShoppingList, nil, nil, {list = list, view = self})
    else
      StaticPopupDialogs[Auctionator.Constants.DialogNames.RenameShoppingList].text = AUCTIONATOR_L_RENAME_LIST_CONFIRM:format(list:GetName()):gsub("%%", "%%%%")
      StaticPopup_Show(Auctionator.Constants.DialogNames.RenameShoppingList, nil, nil, {list = list, view = self})
    end
  end)
  self.ListsContainer:SetOnListDelete(function(list)
    StaticPopupDialogs[Auctionator.Constants.DialogNames.DeleteShoppingList].text = AUCTIONATOR_L_DELETE_LIST_CONFIRM:format(list:GetName()):gsub("%%", "%%%%")
    StaticPopup_Show(Auctionator.Constants.DialogNames.DeleteShoppingList, nil, nil, {list = list, view = self})
  end)

  self.ListsContainer:SetOnListItemDrag(function(list, oldIndex, newIndex)
    if oldIndex ~= newIndex then
      local old = list:GetItemByIndex(oldIndex)
      list:DeleteItem(oldIndex)
      list:InsertItem(old, newIndex)
    end
  end)
end

function AuctionatorShoppingTabFrameMixin:SetupRecentsContainer()
  self.RecentsContainer:SetOnSearchRecent(function(searchTerm)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.RecentsContainer:TemporarilySelectSearchTerm(searchTerm)
  end)
  self.RecentsContainer:SetOnDeleteRecent(function(searchTerm)
    Auctionator.Shopping.Recents.DeleteEntry(searchTerm)
  end)
  self.RecentsContainer:SetOnCopyRecent(function(searchTerm)
    local list = self.ListsContainer:GetExpandedList()
    if list == nil then
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_NO_LIST_SELECTED)
    else
      list:InsertItem(searchTerm)
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_ITEM_ADDED:format(
        GREEN_FONT_COLOR:WrapTextInColorCode(Auctionator.Search.PrettifySearchString(searchTerm)),
        GREEN_FONT_COLOR:WrapTextInColorCode(list:GetName())
      ))
    end
  end)
end




function AuctionatorShoppingTabFrameMixin:BeginSearchAuto(searchTerm)

  if self.searchRunning then
    --print("searchRunning exit....")
    return
  end

  if KillDatas ~=nil and TableLength(KillDatas) > 0 then
    Auctionator.Debug.Message("还有数据没有秒杀完......")
    self.BuyKiller:Show()
    return
  else
    self.BuyKiller:Hide()
  end

  --AutoConfig = {}
  --AutoConfig["银矿石"] = 40000

  --{"铜矿石", 5000},
  --{"锡矿石", 9000}

  local i = 1
  for k,v in pairs(AutoKillerConfig) do
    --local otpions = {}
    --otpions[k] = v

    if i == AutoCurrentIndex then
      k = "\"" .. k .. "\""
      Auctionator.Debug.Message("searching ", k, v)
      --print("searching ", k, v)
      self.singleSearch = true
      self:DoSearch({k})
      self.SearchOptions:SetSearchTerm(k)
      --break
    end

    i = i + 1
  end

  AutoCurrentIndex = AutoCurrentIndex + 1
  if AutoCurrentIndex >= i then
    AutoCurrentIndex = 1
  end

  --print("BeginSearchAuto exit...", AutoCurrentIndex)

end

function AuctionatorShoppingTabFrameMixin:SetupTopSearch()
  self.SearchOptions:SetOnSearch(function(searchTerm)
    --searchTerm = "银矿石lala"
    IsSearchAuto = false

    self:ClearAutoKiller()

    if self.searchRunning then
      self:StopSearch()
    elseif searchTerm == "" and self.ListsContainer:GetExpandedList() ~= nil then
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    else
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end
  end)
  self.SearchOptions:SetOnSearchAuto(function(searchTerm)
    IsSearchAuto = true
    if SearchAutoTimer == nil then
      SearchAutoTimer = C_Timer.NewTicker(3, function()
        self:BeginSearchAuto(searchTerm)
      end, 3600 * 24 * 30)
    else
      self:ClearAutoKiller()
      --print("searchAutoTimer status", SearchAutoTimer:IsCancelled())
    end
    --C_Timer.NewTicker(1, function() print(GetTime()) end, 4)

    -- C_Timer.After(0, function()
    --  self:BeginSearchAuto(searchTerm)
    -- end)
  end)
  self.SearchOptions:SetOnMore(function(searchTerm)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EXTENDED_SEARCH_HEADER, AUCTIONATOR_L_SEARCH)
    self.itemDialog:SetOnFinishedClicked(function(searchTerm)
      self.SearchOptions:SetSearchTerm(searchTerm)
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end)

    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.SearchOptions:SetOnAddToList(function(searchTerm)
    self.ListsContainer:GetExpandedList():InsertItem(searchTerm)
    self.ListsContainer:ScrollToListEnd()
  end)
end

function AuctionatorShoppingTabFrameMixin:GetAppropriateListSearchName()
  if self.singleSearch or not self.ListsContainer:GetExpandedList() then
    return AUCTIONATOR_L_NO_LIST
  else
    return self.ListsContainer:GetExpandedList():GetName()
  end
end

function AuctionatorShoppingTabFrameMixin:ReceiveEvent(eventName, eventData)
  if eventName == Auctionator.Shopping.Events.ListImportFinished then
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByName(eventData))

  elseif eventName == Auctionator.Shopping.Tab.Events.ListSearchRequested then
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(eventData)
    if not Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(eventData:GetAllItems())
    end

  elseif eventName == Auctionator.Shopping.Tab.Events.ShowHistoricalPrices then
    self:CloseAnyDialogs()
    self.itemHistoryDialog:Show()

  elseif eventName == Auctionator.Shopping.Tab.Events.UpdateSearchTerm then
    self.SearchOptions:SetSearchTerm(eventData)

  elseif eventName == Auctionator.Shopping.Tab.Events.BuyScreenShown then
    self:StopSearch()
  end
end

function AuctionatorShoppingTabFrameMixin:ClearAutoKiller()
  if SearchAutoTimer ~= nil then
    SearchAutoTimer:Cancel()
    SearchAutoTimer = nil
  end
  KillDatas = {}
  self.BuyKiller:Hide()
end

function AuctionatorShoppingTabFrameMixin:OnEvent(eventName, ...)
  if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local showType = ...
    if showType == Enum.PlayerInteractionType.Auctioneer then
      self.shouldDefaultOpenOnShow = true
    end
    self:ClearAutoKiller()
  elseif eventName == "AUCTION_HOUSE_CLOSED" then
    self.shouldDefaultOpenOnShow = true
  end
end

function AuctionatorShoppingTabFrameMixin:OnShow()
  self.SearchOptions:FocusSearchBox()
  Auctionator.EventBus:Register(self, EVENTBUS_EVENTS)

  if self.shouldDefaultOpenOnShow then
    self:OpenDefaultList()
    self.shouldDefaultOpenOnShow = false
  end
end

function AuctionatorShoppingTabFrameMixin:OnHide()
  if self.searchRunning then
    self:StopSearch()
  end

  Auctionator.EventBus:Unregister(self, EVENTBUS_EVENTS)
end

function AuctionatorShoppingTabFrameMixin:ExportCSVClicked()
  self:CloseAnyDialogs()
  self.DataProvider:GetCSV(function(result)
    self.exportCSVDialog:SetExportString(result)
    self.exportCSVDialog:Show()
  end)
end

function AuctionatorShoppingTabFrameMixin:BuyKillerClicked()
  self:CloseAnyDialogs()
  if KillDatas == nil or TableLength(KillDatas) == 0 then
    Auctionator.Debug.Message("没有秒杀数据。。。。。。", TableLength(KillDatas))
    return
  end

  local LeftMoney = GetMoney()
  if LeftMoney<= 50000 then
    Auctionator.Debug.Message("口袋里只有这么一点钱了", LeftMoney)
    return
  end

  if not Auctionator.AH.IsNotThrottled() then
    Auctionator.Debug.Message("拍卖限流，请求过于频繁，请稍后再试")
    return
  end

  for index,v in pairs(KillDatas) do
    local stackPrice = v[Auctionator.Constants.AuctionItemInfo.Buyout]
    if stackPrice > GetMoney() then
      KillDatas[index] = nil
      Auctionator.Debug.Message("口袋里没有钱花了!!!")
    else
      --Auctionator.AH.PlaceAuctionBid(index, stackPrice)
      print("正在秒杀",index, v[1], v[Auctionator.Constants.AuctionItemInfo.Owner], "总价:", stackPrice, "单价:", v[Auctionator.Constants.AuctionItemInfo.Buyout] / v[Auctionator.Constants.AuctionItemInfo.Quantity])
      PlaceAuctionBid("list", index, stackPrice)
      KillDatas[index] = nil
      break
    end
  end

  local LeftDataLen = TableLength(KillDatas)
  Auctionator.Debug.Message("还剩下秒杀的数量", LeftDataLen)
  if LeftDataLen == 0 then
    self.BuyKiller:Hide()
  end

end

function AuctionatorShoppingTabFrameMixin:OpenDefaultList()
  local listName = Auctionator.Config.Get(Auctionator.Config.Options.DEFAULT_LIST)

  if listName == Auctionator.Constants.NO_LIST then
    return
  end

  local listIndex = Auctionator.Shopping.ListManager:GetIndexForName(listName)

  if listIndex ~= nil then
    self.ListsContainer:CollapseList()
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByIndex(listIndex))
  end
end
