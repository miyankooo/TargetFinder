local _, ns = ...

-- Two launchers share one click and one tooltip: the LibDBIcon minimap button on both clients, and on 1.60 also the Addon Compartment, which Blizzard_Minimap loads only for the mainline family (Blizzard_Minimap.toc:32-33). Era ignores the toc's AddonCompartmentFunc lines, so the globals below are simply never called there.

local function onLauncherClick(mouseButton)
    if mouseButton == "LeftButton" then
        if IsShiftKeyDown() then
            ns.ClearFinder()
        else
            ns.TogglePanel()
        end
    elseif mouseButton == "RightButton" then
        ns.AddNearbyQuestNpcs()
    end
end

-- Blizzard's tooltip helpers keep the launcher tooltip in each client's own colours: white title, green instructions, red for what is missing.
local function fillLauncherTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, ns.ADDON_NAME)
    GameTooltip_AddInstructionLine(tooltip, "Left-click to toggle the panel.")
    GameTooltip_AddInstructionLine(tooltip, "Shift + left-click to clear the unit list.")
    if ns.QuestieReady() then
        GameTooltip_AddInstructionLine(tooltip, "Right-click to add nearby quest units.")
    else
        GameTooltip_AddDisabledLine(tooltip, "Right-click to add nearby quest units.")
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

function ns.SetupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if LDBIcon:IsRegistered(ns.ADDON_NAME) then return end

    local dataObject = LDB:NewDataObject(ns.ADDON_NAME, {
        type = "launcher",
        text = ns.ADDON_NAME,
        icon = ns.MINIMAP_ICON,
        OnClick = function(_, mouseButton) onLauncherClick(mouseButton) end,
        OnTooltipShow = fillLauncherTooltip,
    })

    -- Earlier versions stored the angle under their own key; migrate once so the button does not jump back to the default.
    local minimap = TargetFinderDB.minimap
    if minimap.angle and not minimap.minimapPos then
        minimap.minimapPos = minimap.angle
    end
    minimap.angle = nil

    LDBIcon:Register(ns.ADDON_NAME, dataObject, minimap)
end

-- Addon Compartment entry points named in the toc. Blizzard calls them with the addon name first, then the mouse button or the menu row.
function TargetFinder_OnClick(_, mouseButton)
    onLauncherClick(mouseButton)
end

function TargetFinder_OnEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    fillLauncherTooltip(GameTooltip)
    GameTooltip:Show()
end

function TargetFinder_OnLeave()
    GameTooltip:Hide()
end
