local _, ns = ...

local UNIT_MENU_TAGS = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_TARGET",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_BOSS",
    "MENU_UNIT_ARENAENEMY",
    "MENU_UNIT_FRIEND",
}

-- Blizzard's own UnitPopupSharedUtil.IsInGroupWithPlayer passes a character name as the unit token, so the name fallback is safe when the menu gives no unit. A non-grouped name simply fails to resolve, which is the filter we want.
local function canAssistUnit(unit, name)
    local token = unit or name
    if not token then return false end

    -- On 1.60 UnitIsUnit and UnitInRaid return secret booleans while a unit-identity restriction is active, and testing one raises in tainted code. Checking first costs the Assist entry inside restricted content, which is the right trade against an error in Blizzard's menu.
    if ns.IdentitySecret(token) then return false end

    if UnitIsUnit(token, "player") then return false end
    if not UnitIsPlayer(token) then return false end
    if not UnitIsFriend("player", token) then return false end
    return UnitInParty(token) or UnitInRaid(token)
end

-- Blizzard fills contextData.name with the RAID_TARGET_ICON string for NPC target menus on both clients, so the unit token is the only trustworthy source of a name. context.name is kept as the fallback for menus that carry no unit, such as the friends list and chat.
local function menuName(context)
    local name
    if context.unit then name = ns.ReadableName(context.unit) end
    if (not name or name == "") and ns.CanAccess(context.name) then
        name = context.name
    end
    if not name or name == "" or name == UNKNOWN then return nil end
    return name
end

local function appendMenu(_, root, context)
    if not context then return end
    local name = menuName(context)
    if not name then return end

    local matchedSlot = ns.SlotCovering(name)

    -- Flat rows under a title, so no submenu hop is needed to reach an action.
    root:CreateDivider()
    root:CreateTitle(ns.ADDON_NAME)

    -- Defer past the click so the menu tears down before the action writes a macro.
    local function action(label, fn)
        root:CreateButton(label, function() C_Timer.After(0, fn) end)
    end

    if canAssistUnit(context.unit, name) then
        action("Assist", function() ns.SetAssistTarget(name) end)
    end
    -- Offered for tracked NPCs too, so an existing entry can be promoted to slot 1.
    if matchedSlot ~= 1 then
        action("Track First", function() ns.AddFinderFirst(name, nil, matchedSlot) end)
    end
    if not matchedSlot then
        action("Track", function() ns.AddFinder(name) end)
    end
    if matchedSlot then
        action("Untrack", function() ns.RemoveFinder(matchedSlot) end)
    end
    if ns.TargetCount() > 0 then
        root:CreateDivider()
        action("Clear Unit List", function() ns.ClearFinder() end)
    end
end

-- Guarded because older 1.15.x builds predate the Menu system; the menu is simply absent there rather than erroring.
function ns.RegisterUnitMenus()
    if not Menu or not Menu.ModifyMenu then return end
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end
