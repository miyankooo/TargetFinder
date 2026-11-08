local _, ns = ...

-- One launcher serves the LibDBIcon minimap button and the Addon Compartment entry LibDBIcon registers, so both share this click and this tooltip. /tf opens the same window.

-- One launcher for the minimap button and the Addon Compartment: LibDBIcon draws the button and adds the
-- compartment entry through AddonCompartmentFrame, so both share the click and the tooltip. Such an addon has no
-- AddonCompartmentFunc toc keys. LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 load first.
local function CreateLauncher(icon, db, onClick, fillTooltip)
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if not LDBIcon:IsRegistered(ns.title) then
        local object = LibStub("LibDataBroker-1.1"):NewDataObject(ns.title, {
            type = "launcher",
            text = ns.title,
            icon = icon,
            OnClick = function(_, button) onClick(button) end,
            OnTooltipShow = function(tooltip)
                GameTooltip_SetTitle(tooltip, ns.title)
                fillTooltip(tooltip)
            end,
        })
        LDBIcon:Register(ns.title, object, db)
        LDBIcon:AddButtonToCompartment(ns.title)
    end
    -- Shows or hides only the minimap button and remembers it in db.hide; the addon menu entry stays.
    return function(shown)
        db.hide = not shown
        if shown then LDBIcon:Show(ns.title) else LDBIcon:Hide(ns.title) end
    end
end

-- Blizzard's tooltip helpers give the lines under the launcher's title the standard colours: green instructions, red for what is missing.
local function fillLauncherTooltip(tooltip)
    GameTooltip_AddInstructionLine(tooltip, "Click to toggle the window.")
    GameTooltip_AddInstructionLine(tooltip, "Right-click to update the quest NPCs.")
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

-- LibDBIcon hands the minimap button's mouse button through, and the addon menu passes its own the same way.
local function onLauncherClick(button)
    if button == "RightButton" then
        ns.RefreshQuestNpcs()
    else
        ns.TogglePanel()
    end
end

function ns.SetupMinimapButton()
    ns.SetMinimapShown = CreateLauncher(ns.ADDON_ICON, ns.db.minimap, onLauncherClick, fillLauncherTooltip)
end

local HELP = "Type /tf to open the window, /tf add with a name or your target to track it, /tf refresh to update the quest NPCs, "
    .. "/tf intro to see the welcome line and the tip again, /tf minimap to show or hide the minimap button, or /tf help for this list."

-- One long command and one short alias. The bare command opens the window; help, intro and minimap are the shared words, and any other word prints the hint. /tf add takes a name, or the current target's when none is typed.
SLASH_TARGETFINDER1, SLASH_TARGETFINDER2 = "/targetfinder", "/tf"
SlashCmdList.TARGETFINDER = function(message)
    local command, rest = (ns.Trim(message) or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "" then
        ns.TogglePanel()
    elseif command == "add" then
        local name = ns.Trim(rest) or ns.ReadableName("target")
        if name then
            ns.AddFinder(name)
        else
            ns.Print("Type a name or target a unit first.")
        end
    elseif command == "refresh" then
        ns.RefreshQuestNpcs()
    elseif command == "help" or command == "?" then
        ns.Print(HELP)
    elseif command == "intro" then
        ns.ReplayIntro()
    elseif command == "minimap" then
        -- Only the minimap button hides; the addon menu entry stays as the way back. Hiding prints the way back, showing prints nothing, since the button is the feedback.
        local show = ns.db.minimap.hide
        ns.SetMinimapShown(show)
        if not show then ns.Print("Minimap button hidden. Type /tf minimap to show it again.") end
    else
        ns.Print("Unknown command. Type /tf help for the list.")
    end
end
