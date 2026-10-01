local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- One launcher serves the LibDBIcon minimap button and the Addon Compartment entry LibDBIcon registers, so both share this click and this tooltip.

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

-- Blizzard's tooltip helpers give the lines under the launcher's title the standard colours: green instructions, red for what is missing.
local function fillLauncherTooltip(tooltip)
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
    UI.CreateLauncher({
        title = ns.ADDON_NAME,
        icon = ns.ADDON_ICON,
        db = TargetFinderDB.minimap,
        onClick = onLauncherClick,
        tooltip = fillLauncherTooltip,
    })
end
