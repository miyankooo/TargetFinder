local addonName, ns = ...

-- Bootstrap only: saved variables, the two events that start the addon and the one-time registrations. Everything else lives in Core/ and UI/.

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function initSavedVars()
    if type(TargetFinderDB) ~= "table" then TargetFinderDB = {} end
    if type(TargetFinderDB.minimap) ~= "table" then
        TargetFinderDB.minimap = { hide = false, minimapPos = ns.MINIMAP_DEFAULT_POS }
    end
    if type(TargetFinderDB.position) ~= "table" then TargetFinderDB.position = {} end
    if type(TargetFinderCharDB) ~= "table" then TargetFinderCharDB = {} end

    -- Quest NPCs fill the list unless the player turned the box off.
    if type(TargetFinderCharDB.questNpcs) ~= "boolean" then TargetFinderCharDB.questNpcs = true end

    -- Adopt validates and rebuilds the list, then the saved variable is pointed at the live table so later mutations persist with no explicit save step.
    TargetFinderCharDB.targets = ns.AdoptSaved(TargetFinderCharDB.targets)
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        initSavedVars()
        ns.RegisterUnitMenus()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.SetupMinimapButton()
        ns.WatchQuestie()

        -- Rewrite on login so FIND matches the saved list even if it was edited by hand. Only an existing FIND is edited, because macros may not be loaded yet and a create here could leave two.
        ns.WriteFinderMacro(true)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
