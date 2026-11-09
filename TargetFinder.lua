local addonName, ns = ...

-- Bootstrap only: saved variables, the two events that start the addon and the one-time registrations. Everything else lives in Core/ and UI/.

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function initSavedVars()
    -- An absent account table is the account's first load, which earns the one welcome line at login (UI/Welcome.lua).
    if type(TargetFinderDB) ~= "table" then
        TargetFinderDB = {}
        ns.firstRun = true
    end
    ns.db = TargetFinderDB
    if type(ns.db.minimap) ~= "table" then
        ns.db.minimap = { hide = false, minimapPos = ns.MINIMAP_DEFAULT_POS }
    end
    if type(ns.db.position) ~= "table" then ns.db.position = {} end
    if type(TargetFinderCharDB) ~= "table" then TargetFinderCharDB = {} end

    -- Auto Apply Quest NPCs fills the list unless the player turned the box off.
    if type(TargetFinderCharDB.questNpcs) ~= "boolean" then TargetFinderCharDB.questNpcs = true end

    -- Listed NPCs get their row's raid marker unless the player turned the box off.
    if type(TargetFinderCharDB.raidMarkers) ~= "boolean" then TargetFinderCharDB.raidMarkers = true end

    -- Pings reach the whole group on every FIND press, so they wait until the player ticks the box.
    if type(TargetFinderCharDB.pings) ~= "boolean" then TargetFinderCharDB.pings = false end

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
        ns.WriteFinderMacro(true, true)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
