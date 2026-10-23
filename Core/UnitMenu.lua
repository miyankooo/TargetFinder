local _, ns = ...

-- The menus of units FIND can reach: NPC and enemy unit frames. Group, raid and friend menus hold only friendly players.
local UNIT_MENU_TAGS = {
    "MENU_UNIT_TARGET",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_BOSS",
    "MENU_UNIT_ENEMY_PLAYER",
}

-- Blizzard fills contextData.name with the RAID_TARGET_ICON string for NPC target menus, so the unit token is the only trustworthy source of a name. A friendly player is never something to hunt, so it gets no name.
local function menuName(context)
    local unit = context.unit
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsPlayer(unit) and UnitIsFriend("player", unit) then return nil end
    local name = ns.ReadableName(unit)
    if not name or name == "" or name == UNKNOWN then return nil end
    return name
end

local function appendMenu(_, root, context)
    if not context then return end
    local name = menuName(context)
    if not name then return end

    local slot = ns.SlotForName(name)

    -- One flat row under a title, so no submenu hop is needed to reach it.
    root:CreateDivider()
    root:CreateTitle(ns.ADDON_NAME)

    -- Defer past the click so the menu tears down before the action writes a macro.
    local function action(label, fn)
        root:CreateButton(label, function() C_Timer.After(0, fn) end)
    end

    if slot then
        action("Untrack", function() ns.RemoveFinder(slot) end)
    else
        action("Track", function() ns.AddFinder(name) end)
    end
end

function ns.RegisterUnitMenus()
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end
