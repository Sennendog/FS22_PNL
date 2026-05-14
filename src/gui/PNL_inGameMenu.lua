local modDirectory = g_currentModDirectory

PNL_inGameMenu = {}
local PNL_inGameMenu_mt = Class(PNL_inGameMenu, TabbedMenuFrameElement)

PNL_inGameMenu.CONTROLS = {
    "mainBox",
    "tableHeaderBox",
    "pnlTable",
    "headerItem",
    "headerYear1",
    "headerYear2",
    "headerYear3",
    "headerYear4",
    "headerYear5",
}

PNL_inGameMenu.SECTIONS = {
    { title = "pnl_block_operations", prefix = "I", items = {"1.1", "1.2", "1.3"}, subtotalItem = "1.4" },
    { title = "pnl_block_financing",  prefix = "II", items = {"2.1", "2.2", "2.3"}, subtotalItem = "2.4" },
    { title = "pnl_block_investing",  prefix = "III", items = {"3.1", "3.2"},       subtotalItem = "3.3" },
}

PNL_inGameMenu.ITEM_LABELS = {
    ["1.1"] = "pnl_item_income_products",
    ["1.2"] = "pnl_item_income_contract",
    ["1.3"] = "pnl_item_expenses_operations",
    ["1.4"] = "pnl_item_subtotal_op",
    ["2.1"] = "pnl_item_income_financing",
    ["2.2"] = "pnl_item_expenses_financing",
    ["2.3"] = "pnl_item_other",
    ["2.4"] = "pnl_item_subtotal_fi",
    ["3.1"] = "pnl_item_income_assets",
    ["3.2"] = "pnl_item_expenses_assets",
    ["3.3"] = "pnl_item_subtotal_in",
    ["total"] = "pnl_grand_total_title",
}

function PNL_inGameMenu.new(i18n, messageCenter)
    local self = PNL_inGameMenu:superClass().new(nil, PNL_inGameMenu_mt)
    self:registerControls(PNL_inGameMenu.CONTROLS)
    g_currentMission.inGameMenu.framePnl = self
    self.hasCustomMenuButtons = true
    self.messageCenter = messageCenter
    self.i18n = i18n
    self.years = {}
    self.yearStats = {}
    return self
end

function PNL_inGameMenu:initialize()
    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK
    }
    self.menuButtons = {self.backButtonInfo}
    self:setMenuButtonInfo(self.menuButtons)
end

function PNL_inGameMenu:onGuiSetupFinished()
    PNL_inGameMenu:superClass().onGuiSetupFinished(self)
    self.pnlTable:setDataSource(self)
    self.pnlTable:setDelegate(self)
end

function PNL_inGameMenu:onFrameOpen(element)
    PNL_inGameMenu:superClass().onFrameOpen(self)
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    local farmId = farm.farmId
    local allYears = g_pnl_manager:getAvailableYears(farmId)
    local currentYear = g_currentMission.environment.currentYear
    local displayYears = {}
    for _, y in ipairs(allYears) do
        if y >= currentYear - 4 and y <= currentYear then
            table.insert(displayYears, y)
        end
    end
    table.sort(displayYears)
    if #displayYears == 0 then
        table.insert(displayYears, currentYear)
    end
    self.years = displayYears
    self.yearData = {}
    for i, year in ipairs(self.years) do
        self.yearData[i] = g_pnl_manager:getYearlyStats(farmId, year)
    end
    self:updateHeaders()
    self.pnlTable:reloadData()
    FocusManager:setFocus(self.pnlTable)
end

function PNL_inGameMenu:updateHeaders()
    local numYears = #self.years
    for i = 1, 5 do
        local header = self["headerYear" .. i]
        if header ~= nil then
            if i <= numYears then
                local offset = numYears - i
                if offset == 0 then
                    header:setText(g_i18n:getText("pnl_header_current_fy"))
                else
                    header:setText(g_i18n:getText("pnl_header_fy_minus") .. offset)
                end
                header:setVisible(true)
            else
                header:setVisible(false)
            end
        end
    end
end

function PNL_inGameMenu:getNumberOfSections()
    return #PNL_inGameMenu.SECTIONS + 1
end

function PNL_inGameMenu:getNumberOfItemsInSection(list, section)
    if section <= #PNL_inGameMenu.SECTIONS then
        local s = PNL_inGameMenu.SECTIONS[section]
        return #s.items + 1
    else
        return 1
    end
end

function PNL_inGameMenu:getTitleForSectionHeader(list, section)
    if section <= #PNL_inGameMenu.SECTIONS then
        return g_i18n:getText(PNL_inGameMenu.SECTIONS[section].title)
    else
        return g_i18n:getText("pnl_grand_total_title")
    end
end

function PNL_inGameMenu:populateCellForItemInSection(list, section, index, cell)
    local isSubtotal = false
    local itemId = nil
    local sectionDef = PNL_inGameMenu.SECTIONS[section]
    if section <= #PNL_inGameMenu.SECTIONS then
        if index <= #sectionDef.items then
            itemId = sectionDef.items[index]
        else
            itemId = sectionDef.subtotalItem
            isSubtotal = true
        end
    else
        itemId = "total"
        isSubtotal = true
    end
    local labelKey = PNL_inGameMenu.ITEM_LABELS[itemId]
    local label = labelKey and g_i18n:getText(labelKey) or ""
    local rowLabel = cell:getAttribute("rowLabel")
    if rowLabel then
        rowLabel:setText(label)
        local textColor = {1, 1, 1, 1}
        if isSubtotal then
            textColor = {0.8, 0.9, 1, 1}
        end
        rowLabel:setTextColor(unpack(textColor))
    end
    for i = 1, 5 do
        local yearCell = cell:getAttribute("year" .. i)
        if yearCell then
            if i <= #self.years and self.yearData[i] ~= nil then
                local value = 0
                if itemId == "total" then
                    value = g_pnl_manager:getGrandTotal(self.yearData[i])
                elseif isSubtotal and section <= #PNL_inGameMenu.SECTIONS then
                    local prefix = PNL_inGameMenu.SECTIONS[section].prefix
                    value = g_pnl_manager:getBlockSubtotal(self.yearData[i], prefix)
                else
                    value = g_pnl_manager:getItemValue(self.yearData[i], itemId)
                    local itemDef = g_pnl_manager.PNL_ITEMS[itemId]
                    -- if itemDef and itemDef.isExpense then
                    --    value = -value
                    -- end
                end
                yearCell:setText(g_i18n:formatMoney(value))
                if value < 0 then
                    yearCell:setTextColor(0.9, 0.3, 0.3, 1)
                elseif isSubtotal and value >= 0 then
                    yearCell:setTextColor(0.6, 1, 0.6, 1)
                else
                    yearCell:setTextColor(1, 1, 1, 1)
                end
            else
                yearCell:setText("")
            end
        end
    end
end
