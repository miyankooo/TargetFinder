local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- One launcher serves the LibDBIcon minimap button and the Addon Compartment entry LibDBIcon registers, so both share this click and this tooltip. /tf opens the same window.

local launcher

-- Blizzard's tooltip helpers give the lines under the launcher's title the standard colours: green instructions, red for what is missing.
local function fillLauncherTooltip(tooltip)
    GameTooltip_AddInstructionLine(tooltip, "Click to toggle the window.")
    GameTooltip_AddInstructionLine(tooltip, "Right-click to update the quest NPCs.")
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

function ns.SetupMinimapButton()
    launcher = UI.CreateLauncher({
        title = ns.ADDON_NAME,
        icon = ns.ADDON_ICON,
        db = TargetFinderDB.minimap,
        -- LibDBIcon hands the minimap button's mouse button through, and the addon menu passes its own the same way.
        onClick = function(button)
            if button == "RightButton" then
                ns.RefreshQuestNpcs()
            else
                ns.TogglePanel()
            end
        end,
        tooltip = fillLauncherTooltip,
    })
end

-- Only the minimap button hides; the addon menu entry stays as the way back.
local function toggleMinimapButton()
    local show = TargetFinderDB.minimap.hide == true
    launcher.setShown(show)
    ns.Announce(show and "Minimap button shown." or "Minimap button hidden. Type /tf minimap to show it again.")
end

local HELP = "Type /tf for the window, /tf add with a name or a target to track it, /tf refresh to update the quest NPCs, "
    .. "/tf minimap to show or hide the minimap button, /tf intro to see the welcome line and the tip again, or /tf help for this list."

-- /tf add takes a name, or the current target's when none is typed. The bare command opens the window; a word it does not know opens nothing.
local function onSlash(msg)
    local command, rest = (ns.Trim(msg) or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "" then
        ns.TogglePanel()
    elseif command == "add" then
        local name = ns.Trim(rest) or ns.ReadableName("target")
        if name then
            ns.AddFinder(name)
        else
            ns.Announce("Type a name or target a unit first.")
        end
    elseif command == "refresh" then
        ns.RefreshQuestNpcs()
    elseif command == "minimap" then
        toggleMinimapButton()
    elseif command == "intro" then
        ns.ReplayIntro()
    elseif command == "help" or command == "?" then
        ns.Announce(HELP)
    else
        ns.Announce("Unknown command. Type /tf help for the list.")
    end
end

UI.RegisterSlash("TARGETFINDER", { "/targetfinder", "/tf" }, onSlash)
