local addonName = ...

local ADDON_NAME = "TargetFinder"
local YELLOW = "|cffffff00"
local COLOR_END = "|r"

local FIND_MACRO = "FIND"
local FIND_ICON = "Ability_Hunter_SniperShot"
local FIND_MARKERS = { 2, 6, 4, 1, 3, 5, 7, 8 }
local MAX_TARGETS = 8
local ASSIST_MACRO = "ASSIST"
local ASSIST_ICON = "Ability_DualWield"
local ACTION_SLOTS = 72
local GLOW_SECONDS = 4

local function announce(msg)
    print(YELLOW .. "[" .. ADDON_NAME .. "]:" .. COLOR_END .. " " .. msg)
end

local function trim(value)
    if not value then return nil end
    local stripped = value:match("^%s*(.-)%s*$")
    if stripped == "" then return nil end
    return stripped
end

local function resolveName(input)
    local name = trim(input)
    if name then return name end
    if UnitExists("target") then return UnitName("target") end
    return nil
end

local function readTargets()
    if not TargetFinderDB then return {} end
    return TargetFinderDB.findTargets or {}
end

local function applyMarkerFromTarget()
    if not UnitExists("target") then return end
    if GetRaidTargetIndex("target") then return end
    local name = UnitName("target")
    if not name then return end
    local db = TargetFinderDB
    if not db or not db.findTargets then return end
    for slot, saved in ipairs(db.findTargets) do
        if saved == name then
            local marker = FIND_MARKERS[slot]
            if marker then SetRaidTarget("target", marker) end
            return
        end
    end
end

local function setMacro(name, icon, body)
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        EditMacro(index, name, icon, body)
    else
        CreateMacro(name, icon, body, nil)
    end
end

local function buildFindBody(targets)
    if #targets == 0 then return "/cleartarget" end
    local lines = { "/cleartarget" }
    for _, name in ipairs(targets) do
        table.insert(lines, "/target " .. name)
    end
    return table.concat(lines, "\n")
end

local function writeFinderMacro(targets)
    TargetFinderDB = TargetFinderDB or {}
    TargetFinderDB.findTargets = targets
    setMacro(FIND_MACRO, FIND_ICON, buildFindBody(targets))
end

local function isMacroOnBar(absIndex)
    if not absIndex or absIndex == 0 then return false end
    for slot = 1, ACTION_SLOTS do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id == absIndex then return true end
    end
    return false
end

local function buildGlow(button)
    if button.tfGlow then return button.tfGlow end
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetAtlas("bags-newitem", true)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", button, "CENTER")
    local w, h = button:GetSize()
    glow:SetSize(w * 1.4, h * 1.4)
    glow:SetAlpha(0)

    local anim = glow:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.35)
    fadeIn:SetOrder(1)
    local fadeOut = anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.35)
    fadeOut:SetOrder(2)

    glow.anim = anim
    button.tfGlow = glow
    return glow
end

local function pulseGlow(button)
    local glow = buildGlow(button)
    glow.token = (glow.token or 0) + 1
    local token = glow.token
    glow:Show()
    if not glow.anim:IsPlaying() then glow.anim:Play() end
    C_Timer.After(GLOW_SECONDS, function()
        if glow.token ~= token then return end
        glow.anim:Stop()
        glow:SetAlpha(0)
        glow:Hide()
    end)
end

local function focusMacro(absIndex)
    if not MacroFrame then return end
    local tabID = absIndex <= MAX_ACCOUNT_MACROS and 1 or 2
    local relative = absIndex - (tabID == 1 and 0 or MAX_ACCOUNT_MACROS)
    MacroFrame:ChangeTab(tabID)
    MacroFrame:SelectMacro(relative, true)
    if MacroFrame.SelectedMacroButton then
        pulseGlow(MacroFrame.SelectedMacroButton)
    end
end

local function hintMacro(name)
    if InCombatLockdown() then return end
    local absIndex = GetMacroIndexByName(name)
    if not absIndex or absIndex == 0 then return end
    if isMacroOnBar(absIndex) then return end

    ShowMacroFrame()
    if MacroFrame then
        focusMacro(absIndex)
    else
        C_Timer.After(0, function() focusMacro(absIndex) end)
    end
end

local function setFinder(name)
    if not name then
        announce("no target selected.")
        return
    end
    writeFinderMacro({ name })
    announce(name)
    hintMacro(FIND_MACRO)
end

local function addFinder(name)
    if not name then
        announce("no target selected.")
        return
    end
    local targets = readTargets()
    for _, existing in ipairs(targets) do
        if existing == name then
            announce(name .. " is already tracked.")
            return
        end
    end
    if #targets >= MAX_TARGETS then
        announce("Finder is full: " .. table.concat(targets, ", ") .. ".")
        return
    end
    table.insert(targets, name)
    writeFinderMacro(targets)
    announce(table.concat(targets, ", "))
    hintMacro(FIND_MACRO)
end

local function resetFinder()
    local before = readTargets()
    if #before == 0 then
        announce("Finder is empty.")
        return
    end
    writeFinderMacro({})
    announce("Finder reset.")
end

local function setAssist(name)
    if not name then
        announce("no target selected.")
        return
    end
    TargetFinderDB = TargetFinderDB or {}
    TargetFinderDB.assistTarget = name
    setMacro(ASSIST_MACRO, ASSIST_ICON, "/assist " .. name)
    announce("Assist: " .. name)
    hintMacro(ASSIST_MACRO)
end

SLASH_TARGETFINDER_FIND1 = "/find"
SlashCmdList.TARGETFINDER_FIND = function(msg)
    local arg = trim(msg)
    if arg and arg:lower() == "reset" then
        resetFinder()
        return
    end
    setFinder(resolveName(msg))
end

SLASH_TARGETFINDER_ADD1 = "/find+"
SlashCmdList.TARGETFINDER_ADD = function(msg)
    addFinder(resolveName(msg))
end

SLASH_TARGETFINDER_ASSIST1 = "/assist"
SlashCmdList.TARGETFINDER_ASSIST = function(msg)
    setAssist(resolveName(msg))
end

local UNIT_MENU_TAGS = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_TARGET",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_BOSS",
    "MENU_UNIT_ARENAENEMY",
    "MENU_UNIT_FRIEND",
}

local function appendMenu(_, root, context)
    if not context then return end
    local name = context.name
    if (not name or name == "") and context.unit then
        name = UnitName(context.unit)
    end
    if not name or name == "" or name == UNKNOWN then return end

    root:CreateDivider()
    root:CreateTitle(ADDON_NAME)
    root:CreateButton("Set Finder", function() C_Timer.After(0, function() setFinder(name) end) end)
    root:CreateButton("Add to Finder", function() C_Timer.After(0, function() addFinder(name) end) end)
    if #readTargets() > 0 then
        root:CreateButton("Reset Finder", function() C_Timer.After(0, function() resetFinder() end) end)
    end
    root:CreateButton("Set Assist", function() C_Timer.After(0, function() setAssist(name) end) end)
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        TargetFinderDB = TargetFinderDB or {}
        TargetFinderDB.findTargets = TargetFinderDB.findTargets or {}
        announce("loaded.")
        print("  /find NAME    — set finder (uses current target if omitted)")
        print("  /find+ NAME   — add to finder (max " .. MAX_TARGETS .. ")")
        print("  /find reset   — reset finder")
        print("  /assist NAME  — set assist (uses current target if omitted)")
        print("  Right-click a unit frame for finder and assist options.")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_TARGET_CHANGED" then
        applyMarkerFromTarget()
    end
end)
