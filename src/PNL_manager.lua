PNL_manager = {}
local PNL_manager_mt = Class(PNL_manager, AbstractManager)

function PNL_manager.new(customMt)
    local self = PNL_manager:superClass().new(customMt or PNL_manager_mt)
    self.farmData = {}
    self.hasBackfilledHistory = false
    return self
end

PNL_manager.STAT_NAMES = {
    "newVehiclesCost", "soldVehicles", "newAnimalsCost", "soldAnimals",
    "constructionCost", "soldBuildings", "fieldPurchase", "fieldSelling",
    "vehicleRunningCost", "vehicleLeasingCost", "propertyMaintenance", "propertyIncome",
    "productionCosts", "soldWood", "soldBales", "soldWool", "soldMilk", "soldProducts",
    "purchaseFuel", "purchaseSeeds", "purchaseFertilizer", "purchaseSaplings",
    "purchaseWater", "purchaseBales", "purchasePallets",
    "harvestIncome", "incomeBga", "missionIncome", "wagePayment", "other", "loanInterest"
}

PNL_manager.PNL_ITEMS = {
    ["1.1"] = { isExpense = false, stats = {"harvestIncome", "soldProducts", "soldMilk", "soldWood", "soldBales", "soldAnimals", "incomeBga", "propertyIncome"} },
    ["1.2"] = { isExpense = false, stats = {"missionIncome"} },
    ["1.3"] = { isExpense = true, stats = {"purchaseSeeds", "purchaseFertilizer", "purchaseFuel", "purchaseSaplings", "purchaseWater", "purchaseBales", "purchasePallets", "vehicleRunningCost", "vehicleLeasingCost", "propertyMaintenance", "productionCosts", "wagePayment", "animalUpkeep", "newAnimalsCost"} },
    ["2.1"] = { isExpense = false, loanComponent = "positive" },
    ["2.2"] = { isExpense = true, stats = {"loanInterest"}, loanComponent = "negative" },
    ["2.3"] = { isExpense = false, stats = {"other"} },
    ["3.1"] = { isExpense = false, stats = {"soldVehicles", "soldBuildings", "fieldSelling"} },
    ["3.2"] = { isExpense = true, stats = {"newVehiclesCost", "constructionCost", "fieldPurchase"} },
}

function PNL_manager:loadMap()
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
end

function PNL_manager:onPeriodChanged()
    if not g_currentMission:getIsServer() then
        return
    end
    local env = g_currentMission.environment
    local currentPeriod = env.currentPeriod
    local currentYear = env.currentYear
    local completedPeriod = currentPeriod - 1
    local completedYear = currentYear
    if completedPeriod < 0 then
        completedPeriod = 11
        completedYear = currentYear - 1
    end
    if not self.hasBackfilledHistory then
        self:backfillMissingHistory(completedYear, completedPeriod)
        self.hasBackfilledHistory = true
    end
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            local stats = farm.stats
            if #stats.financesHistory > 0 then
                local archived = stats.financesHistory[#stats.financesHistory]
                self:storeMonthlyData(farm.farmId, completedYear, completedPeriod, archived)
            end
        end
    end
end

function PNL_manager:backfillMissingHistory(completedYear, completedPeriod)
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            local stats = farm.stats
            local historyCount = #stats.financesHistory
            if historyCount > 0 then
                local year = completedYear
                local period = completedPeriod
                for i = historyCount, 1, -1 do
                    if year ~= completedYear then
                        break
                    end
                    self:storeMonthlyData(farm.farmId, year, period, stats.financesHistory[i])
                    period = period - 1
                    if period < 0 then
                        period = 11
                        year = year - 1
                    end
                end
            end
        end
    end
end

function PNL_manager:storeMonthlyData(farmId, year, period, financeStats)
    if self.farmData[farmId] == nil then
        self.farmData[farmId] = { months = {}, loanPositive = 0, loanNegative = 0 }
    end
    local fd = self.farmData[farmId]
    if fd.months[year] == nil then
        fd.months[year] = {}
    end
    if fd.months[year][period] ~= nil then
        return
    end
    local monthData = {}
    monthData.year = year
    monthData.period = period
    for _, statName in ipairs(PNL_manager.STAT_NAMES) do
        monthData[statName] = financeStats[statName] or 0
    end
    monthData.loanPositive = fd.loanPositive
    monthData.loanNegative = fd.loanNegative
    fd.loanPositive = 0
    fd.loanNegative = 0
    fd.months[year][period] = monthData
end

function PNL_manager:trackLoan(farmId, amount)
    if self.farmData[farmId] == nil then
        self.farmData[farmId] = { months = {}, loanPositive = 0, loanNegative = 0 }
    end
    if amount > 0 then
        self.farmData[farmId].loanPositive = self.farmData[farmId].loanPositive + amount
    else
        self.farmData[farmId].loanNegative = self.farmData[farmId].loanNegative + (-amount)
    end
end

function PNL_manager:getYearlyStats(farmId, year)
    local fd = self.farmData and self.farmData[farmId]
    if fd == nil or fd.months[year] == nil then
        return nil
    end
    local result = {}
    local loanPos = 0
    local loanNeg = 0
    for _, statName in ipairs(PNL_manager.STAT_NAMES) do
        result[statName] = 0
    end
    for _, monthData in pairs(fd.months[year]) do
        for _, statName in ipairs(PNL_manager.STAT_NAMES) do
            result[statName] = (result[statName] or 0) + (monthData[statName] or 0)
        end
        loanPos = loanPos + (monthData.loanPositive or 0)
        loanNeg = loanNeg + (monthData.loanNegative or 0)
    end
    result.loanPositive = loanPos
    result.loanNegative = loanNeg
    return result
end

function PNL_manager:getItemValue(yearStats, itemId)
    if yearStats == nil then
        return 0
    end
    local item = PNL_manager.PNL_ITEMS[itemId]
    if item == nil then
        return 0
    end
    local value = 0
    if item.stats ~= nil then
        for _, statName in ipairs(item.stats) do
            value = value + (yearStats[statName] or 0)
        end
    end
    if item.loanComponent == "positive" then
        value = value + (yearStats.loanPositive or 0)
    elseif item.loanComponent == "negative" then
        value = value - (yearStats.loanNegative or 0)
    end
    return value
end

function PNL_manager:getBlockItems(blockId)
    if blockId == "I" then
        return {"1.1", "1.2", "1.3"}
    elseif blockId == "II" then
        return {"2.1", "2.2", "2.3"}
    elseif blockId == "III" then
        return {"3.1", "3.2"}
    end
    return {}
end

function PNL_manager:getBlockSubtotal(yearStats, blockId)
    local items = self:getBlockItems(blockId)
    local total = 0
    for _, itemId in ipairs(items) do
        total = total + self:getItemValue(yearStats, itemId)
    end
    return total
end

function PNL_manager:getGrandTotal(yearStats)
    local total = 0
    total = total + self:getBlockSubtotal(yearStats, "I")
    total = total + self:getBlockSubtotal(yearStats, "II")
    total = total + self:getBlockSubtotal(yearStats, "III")
    return total
end

function PNL_manager:getAvailableYears(farmId)
    local fd = self.farmData and self.farmData[farmId]
    if fd == nil or fd.months == nil then
        return {}
    end
    local years = {}
    for year, _ in pairs(fd.months) do
        table.insert(years, year)
    end
    table.sort(years)
    return years
end

function PNL_manager:saveToXMLFile(missionInfo)
    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        return
    end
    local filePath = savegameDirectory .. "/pnl_data.xml"
    local xmlFile = XMLFile.create("pnl_data", filePath, "pnl")
    if xmlFile == nil then
        return
    end
    local farmIdx = 0
    for farmId, fd in pairs(self.farmData) do
        local farmKey = string.format("pnl.farm(%d)", farmIdx)
        xmlFile:setInt(farmKey .. "#farmId", farmId)
        local yearIdx = 0
        for year, months in pairs(fd.months) do
            local yearKey = string.format(farmKey .. ".year(%d)", yearIdx)
            xmlFile:setInt(yearKey .. "#year", year)
            local monthIdx = 0
            for period, monthData in pairs(months) do
                local monthKey = string.format(yearKey .. ".month(%d)", monthIdx)
                xmlFile:setInt(monthKey .. "#period", period)
                xmlFile:setFloat(monthKey .. ".loanPositive", monthData.loanPositive or 0)
                xmlFile:setFloat(monthKey .. ".loanNegative", monthData.loanNegative or 0)
                for _, statName in ipairs(PNL_manager.STAT_NAMES) do
                    xmlFile:setFloat(monthKey .. "." .. statName, monthData[statName] or 0)
                end
                monthIdx = monthIdx + 1
            end
            yearIdx = yearIdx + 1
        end
        farmIdx = farmIdx + 1
    end
    xmlFile:save()
    xmlFile:delete()
end

function PNL_manager:loadFromXMLFile()
    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        return
    end
    local filePath = savegameDirectory .. "/pnl_data.xml"
    local xmlFile = XMLFile.loadIfExists("pnl_data", filePath, "pnl")
    if xmlFile == nil then
        return
    end
    self.farmData = {}
    local farmIdx = 0
    while true do
        local farmKey = string.format("pnl.farm(%d)", farmIdx)
        if not xmlFile:hasProperty(farmKey) then
            break
        end
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        local fd = { months = {}, loanPositive = 0, loanNegative = 0 }
        local yearIdx = 0
        while true do
            local yearKey = string.format(farmKey .. ".year(%d)", yearIdx)
            if not xmlFile:hasProperty(yearKey) then
                break
            end
            local year = xmlFile:getInt(yearKey .. "#year")
            fd.months[year] = {}
            local monthIdx = 0
            while true do
                local monthKey = string.format(yearKey .. ".month(%d)", monthIdx)
                if not xmlFile:hasProperty(monthKey) then
                    break
                end
                local period = xmlFile:getInt(monthKey .. "#period")
                local monthData = { year = year, period = period }
                for _, statName in ipairs(PNL_manager.STAT_NAMES) do
                    monthData[statName] = xmlFile:getFloat(monthKey .. "." .. statName, 0)
                end
                monthData.loanPositive = xmlFile:getFloat(monthKey .. ".loanPositive", 0)
                monthData.loanNegative = xmlFile:getFloat(monthKey .. ".loanNegative", 0)
                fd.months[year][period] = monthData
                monthIdx = monthIdx + 1
            end
            yearIdx = yearIdx + 1
        end
        self.farmData[farmId] = fd
        farmIdx = farmIdx + 1
    end
    xmlFile:delete()
    self.hasBackfilledHistory = (next(self.farmData) ~= nil)
end

g_pnl_manager = PNL_manager.new()
