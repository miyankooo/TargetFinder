local addonName, ns = ...

-- Bootstrap only: saved variables, the three events the addon reacts to, and the one-time registrations. Everything else lives in Core/.

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

local function initSavedVars()
    if type(TargetFinderDB) ~= "table" then TargetFinderDB = {} end
    if type(TargetFinderDB.minimap) ~= "table" then
        TargetFinderDB.minimap = { hide = false, minimapPos = ns.MINIMAP_DEFAULT_POS }
    end
    if type(TargetFinderCharDB) ~= "table" then TargetFinderCharDB = {} end

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
        -- Rewrite on login so the macro always matches the saved list, even if it was edited by hand.
        if ns.TargetCount() > 0 then ns.WriteFinderMacro() end
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns.ApplyMarkerFromTarget()
    end
end)
