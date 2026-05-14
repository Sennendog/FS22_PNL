local modDirectory = g_currentModDirectory

source(modDirectory .. "src/PNL_manager.lua")
source(modDirectory .. "src/gui/PNL_inGameMenu.lua")

addModEventListener(g_pnl_manager)

Farm.changeBalance = Utils.appendedFunction(Farm.changeBalance, function(self, amount, moneyType)
    if moneyType == MoneyType.LOAN then
        g_pnl_manager:trackLoan(self.farmId, amount)
    end
end)

function fixInGameMenu(frame, pageName, uvs, position, predicateFunc)
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    for k, v in pairs({pageName}) do
        inGameMenu.controlIDs[v] = nil
    end
    inGameMenu:registerControls({pageName})
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    inGameMenu:exposeControlsAsFields(pageName)
    for i = 1, #inGameMenu.pagingElement.elements do
        local child = inGameMenu.pagingElement.elements[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.elements, i)
            table.insert(inGameMenu.pagingElement.elements, position, child)
            break
        end
    end
    for i = 1, #inGameMenu.pagingElement.pages do
        local child = inGameMenu.pagingElement.pages[i]
        if child.element == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, position, child)
            break
        end
    end
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    inGameMenu:registerPage(inGameMenu[pageName], position, predicateFunc)
    local iconFileName = Utils.getFilename("images/menuIcon.dds", modDirectory)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
    inGameMenu[pageName]:applyScreenAlignment()
    inGameMenu[pageName]:updateAbsolutePosition()
    for i = 1, #inGameMenu.pageFrames do
        local child = inGameMenu.pageFrames[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pageFrames, i)
            table.insert(inGameMenu.pageFrames, position, child)
            break
        end
    end
    inGameMenu:rebuildTabList()
end

function loadedMission()
    g_gui:loadProfiles(modDirectory .. "gui/PNL_guiProfiles.xml")
    local guiPage = PNL_inGameMenu.new(g_i18n, g_messageCenter)
    g_gui:loadGui(modDirectory .. "gui/PNL_inGameMenu.xml", "PNL_inGameMenu", guiPage, true)
    fixInGameMenu(guiPage, "PNL_inGameMenu", {0, 0, 1024, 1024}, 3, nil)
    guiPage:initialize()
end

function init()
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
    Mission00.loadItemsFinished = Utils.appendedFunction(Mission00.loadItemsFinished, function()
        g_pnl_manager:loadFromXMLFile()
    end)
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(missionInfo)
        g_pnl_manager:saveToXMLFile(missionInfo)
    end)
end

init()
