local addonName = ...

local ADDON_NAME = "TargetShortcuts"
local YELLOW = "|cffffff00"
local RESET = "|r"

local FIND_MACRO = "FIND"
local ASSIST_MACRO = "ASSIST"
local FIND_ICON = "Ability_Hunter_SniperShot"
local ASSIST_ICON = "Ability_DualWield"
local FIND_MARKERS = { 2, 6, 4 }
local MAX_TARGETS = 3
local ACTION_SLOTS = 72
local GLOW_SECONDS = 4

local function announce(msg)
    print(YELLOW .. "[" .. ADDON_NAME .. "]:" .. RESET .. " " .. msg)
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

function FA_Mark(marker)
    if UnitExists("target") and not GetRaidTargetIndex("target") then
        SetRaidTarget("target", marker)
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

local function readTargets()
    local index = GetMacroIndexByName(FIND_MACRO)
    if not index or index == 0 then return {} end
    local body = GetMacroBody(FIND_MACRO) or ""
    local targets = {}
    for entry in body:gmatch("/target%s+([^\n]+)") do
        table.insert(targets, entry)
    end
    return targets
end

local function writeFindMacro(targets)
    local lines = { "/cleartarget" }
    for slot, name in ipairs(targets) do
        table.insert(lines, "/target " .. name)
        local marker = FIND_MARKERS[slot]
        if marker then
            table.insert(lines, "/run FA_Mark(" .. marker .. ")")
        end
    end
    setMacro(FIND_MACRO, FIND_ICON, table.concat(lines, "\n"))
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
    if button.tsGlow then return button.tsGlow end
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
    button.tsGlow = glow
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

local function setFind(name)
    if not name then
        announce("no target selected.")
        return
    end
    writeFindMacro({ name })
    announce(name)
    hintMacro(FIND_MACRO)
end

local function addFind(name)
    if not name then
        announce("no target selected.")
        return
    end
    local targets = readTargets()
    for _, existing in ipairs(targets) do
        if existing == name then
            announce(name .. " is already in Find.")
            return
        end
    end
    if #targets >= MAX_TARGETS then
        announce("Find is full: " .. table.concat(targets, ", ") .. ".")
        return
    end
    table.insert(targets, name)
    writeFindMacro(targets)
    announce(table.concat(targets, ", "))
    hintMacro(FIND_MACRO)
end

local function clearFind()
    local index = GetMacroIndexByName(FIND_MACRO)
    if not index or index == 0 then
        announce("Find is empty.")
        return
    end
    local before = readTargets()
    EditMacro(index, FIND_MACRO, FIND_ICON, "/cleartarget")
    if #before == 0 then
        announce("Find is empty.")
    else
        announce("Find cleared.")
    end
end

local function listFind()
    local targets = readTargets()
    if #targets == 0 then
        announce("Find is empty.")
    else
        announce(table.concat(targets, ", "))
    end
end

local function showHelp()
    announce("commands:")
    print("  /find NAME         set Find target (uses current target if omitted)")
    print("  /find add NAME     add to Find (max " .. MAX_TARGETS .. ": circle, square, triangle)")
    print("  /find clear        clear Find")
    print("  /find list         show Find targets")
    print("  /find help         this message")
    print("  /assist NAME       set Assist target")
    print("  Right-click a unit frame for the same options.")
    print("  Markers only apply when the target has no mark.")
end

local function setAssist(name)
    if not name then
        announce("no target selected.")
        return
    end
    setMacro(ASSIST_MACRO, ASSIST_ICON, "/assist " .. name)
    announce("Assist: " .. name)
    hintMacro(ASSIST_MACRO)
end

SLASH_TARGETSHORTCUTS_FIND1 = "/find"
SlashCmdList.TARGETSHORTCUTS_FIND = function(msg)
    local arg = trim(msg)
    if arg then
        local first, rest = arg:match("^(%S+)%s*(.-)$")
        local cmd = first and first:lower() or ""
        if cmd == "help" or cmd == "?" then
            showHelp()
            return
        elseif cmd == "list" then
            listFind()
            return
        elseif cmd == "clear" then
            clearFind()
            return
        elseif cmd == "add" then
            addFind(resolveName(rest))
            return
        end
    end
    setFind(resolveName(msg))
end

SLASH_TARGETSHORTCUTS_ADDFIND1 = "/addfind"
SlashCmdList.TARGETSHORTCUTS_ADDFIND = function(msg)
    addFind(resolveName(msg))
end

SLASH_TARGETSHORTCUTS_ASSIST1 = "/assist"
SlashCmdList.TARGETSHORTCUTS_ASSIST = function(msg)
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
    root:CreateButton("Find", function() C_Timer.After(0, function() setFind(name) end) end)
    root:CreateButton("Add to Find", function() C_Timer.After(0, function() addFind(name) end) end)
    if #readTargets() > 0 then
        root:CreateButton("Clear Find", function() C_Timer.After(0, function() clearFind() end) end)
    end
    root:CreateButton("Assist", function() C_Timer.After(0, function() setAssist(name) end) end)
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name == addonName then
        TargetShortcutsDB = TargetShortcutsDB or {}
        if not TargetShortcutsDB.greeted then
            TargetShortcutsDB.greeted = true
            announce("loaded.")
            print("  /find NAME — set Find target (uses current target if omitted)")
            print("  /find add NAME — add to Find (max 3: circle, square, triangle)")
            print("  /find clear  |  /find list  |  /find help  |  /assist NAME")
            print("  Right-click a unit frame for Find and Assist options.")
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
