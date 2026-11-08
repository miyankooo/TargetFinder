local _, ns = ...

-- Every menu the target frame opens (TargetFrame_OpenMenu, Mainline/TargetFrame.lua:630-680): NPCs, friendly and enemy players, party and raid members, plus the focus and boss frames. FIND targets any unit by its exact name, so players count too.
local UNIT_MENU_TAGS = {
    "MENU_UNIT_TARGET",
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_BOSS",
}

-- Blizzard's unit menus open with the unit's name as their first element (UnitPopupShared.lua:110-125), so Target Finder's entries go right under it.
local FIRST_ENTRY = 2

-- Blizzard fills contextData.name with the RAID_TARGET_ICON string for NPC target menus, so the unit token is the only trustworthy source of a name.
local function menuName(context)
    local unit = context.unit
    if not unit or not UnitExists(unit) then return nil end
    local name = ns.ReadableName(unit)
    if not name or name == "" or name == UNKNOWN then return nil end
    return name
end

-- Insert is the description's own method that CreateButton appends with (Menu.lua:427), here given the index under the title. Menu.PopulateDescription runs this after Blizzard's generator, so the title is already in place.
local function appendMenu(_, root, context)
    if not context then return end
    local name = menuName(context)
    if not name then return end

    -- Defer past the click so the menu tears down before the action writes a macro. Untrack looks the row up at click time, because a quest sync may refill rows while the menu is open.
    local label, help, action
    if ns.SlotForName(name) then
        label, help = "Untrack", "Takes " .. name .. " off the FIND list."
        action = function() ns.RemoveFinder(ns.SlotForName(name)) end
    else
        label, help = "Track", "Puts " .. name .. " first on the FIND list, so FIND targets it before the rest."
        action = function() ns.AddFinder(name) end
    end

    local button = MenuUtil.CreateButton(label, function() C_Timer.After(0, action) end)
    button:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, label)
        GameTooltip_AddNormalLine(tooltip, help)
    end)

    root:Insert(MenuUtil.CreateTitle(ns.ADDON_NAME), FIRST_ENTRY)
    root:Insert(button, FIRST_ENTRY + 1)
    root:Insert(MenuUtil.CreateDivider(), FIRST_ENTRY + 2)
end

function ns.RegisterUnitMenus()
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end
