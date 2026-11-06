local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- One launcher serves the LibDBIcon minimap button and the Addon Compartment entry LibDBIcon registers, so both share this click and this tooltip. /tf opens the same window.

local launcher

-- Blizzard's tooltip helpers give the lines under the launcher's title the standard colours: a green instruction, red for what is missing.
local function fillLauncherTooltip(tooltip)
    GameTooltip_AddInstructionLine(tooltip, "Click to toggle the window.")
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

function ns.SetupMinimapButton()
    launcher = UI.CreateLauncher({
        title = ns.ADDON_NAME,
        icon = ns.ADDON_ICON,
        db = TargetFinderDB.minimap,
        onClick = function() ns.TogglePanel() end,
        tooltip = fillLauncherTooltip,
    })
end

-- Only the minimap button hides; the addon menu entry stays as the way back.
local function toggleMinimapButton()
    local show = TargetFinderDB.minimap.hide == true
    launcher.setShown(show)
    ns.Announce(show and "Minimap button shown." or "Minimap button hidden. Type /tf minimap to show it again.")
end

-- /tf add takes a name, or the current target's when none is typed.
local function onSlash(msg)
    local command, rest = (ns.Trim(msg) or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "minimap" then
        toggleMinimapButton()
    elseif command == "add" then
        local name = ns.Trim(rest) or ns.ReadableName("target")
        if name then
            ns.AddFinder(name)
        else
            ns.Announce("Type a name or target a unit first.")
        end
    else
        ns.TogglePanel()
    end
end

UI.RegisterSlash("TARGETFINDER", { "/targetfinder", "/tf" }, onSlash)
