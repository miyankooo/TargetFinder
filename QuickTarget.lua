local addonName = ...

local ADDON_NAME = "QuickTarget"
local YELLOW = "|cffffff00"
local COLOR_END = "|r"

local FIND_MACRO = "FIND"
local FIND_ICON = "Ability_Hunter_SniperShot"
local FIND_MARKERS = { 8, 6, 2, 1, 7, 4, 3, 5 }
local MAX_TARGETS = 8
local ASSIST_MACRO = "ASSIST"
local ASSIST_ICON = "Ability_DualWield"
local ACTION_SLOTS = 72
local GLOW_SECONDS = 4
local MARK_THROTTLE = 0.15

local MINIMAP_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
local MINIMAP_DEFAULT_POS = 215

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

local findTargets = {}

local function readTargets()
    return findTargets
end

local lastMarkTime = 0

local function applySlotMarker(slot)
    if not UnitExists("target") then return end
    local marker = FIND_MARKERS[slot]
    if not marker then return end
    if GetRaidTargetIndex("target") == marker then return end
    local now = GetTime()
    if now - lastMarkTime < MARK_THROTTLE then return end
    lastMarkTime = now
    SetRaidTarget("target", marker)
end

local function applyMarkerFromTarget()
    if not UnitExists("target") then return end
    local name = UnitName("target")
    if not name then return end
    local lowered = name:lower()
    for slot, saved in ipairs(findTargets) do
        if saved and lowered:find(saved:lower(), 1, true) then
            applySlotMarker(slot)
            return
        end
    end
end

local _qtLastGuid

function QuickTargetMark(slot)
    if not slot then
        _qtLastGuid = nil
        return
    end
    if not UnitExists("target") then return end
    local guid = UnitGUID("target")
    if guid == _qtLastGuid then return end
    _qtLastGuid = guid
    applySlotMarker(slot)
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
    local lines = { "/run QuickTargetMark()", "/cleartarget" }
    for slot, name in ipairs(targets) do
        table.insert(lines, "/target " .. name)
        table.insert(lines, "/run QuickTargetMark(" .. slot .. ")")
    end
    return table.concat(lines, "\n")
end

local refreshPanel

local function writeFinderMacro(targets)
    findTargets = targets
    setMacro(FIND_MACRO, FIND_ICON, buildFindBody(targets))
    if refreshPanel then refreshPanel() end
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
    if button.qtGlow then return button.qtGlow end
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
    button.qtGlow = glow
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
        announce("No target selected.")
        return
    end
    writeFinderMacro({ name })
    applySlotMarker(1)
    announce(name)
    hintMacro(FIND_MACRO)
end

local function addFinder(name)
    if not name then
        announce("No target selected.")
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
    applySlotMarker(#targets)
    announce(table.concat(targets, ", "))
    hintMacro(FIND_MACRO)
end

local function removeFinder(slot)
    local targets = readTargets()
    local removed = targets[slot]
    if not removed then return end
    table.remove(targets, slot)
    writeFinderMacro(targets)
    announce("Removed: " .. removed)
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
        announce("No target selected.")
        return
    end
    setMacro(ASSIST_MACRO, ASSIST_ICON, "/assist " .. name)
    announce("Assist: " .. name)
    hintMacro(ASSIST_MACRO)
end

local panel

local function submitInput(input)
    local typed = trim(input:GetText())
    if typed then
        addFinder(typed)
    else
        addFinder(resolveName(nil))
    end
    input:SetText("")
    input:ClearFocus()
end

local function buildPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "QuickTargetPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(280, 340)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    panel.TitleText:SetText(ADDON_NAME)
    tinsert(UISpecialFrames, "QuickTargetPanel")

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -32)
    header:SetText("Tracked targets")

    local cap = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cap:SetPoint("LEFT", header, "RIGHT", 6, 0)
    cap:SetText("(max " .. MAX_TARGETS .. ")")

    panel.rows = {}
    for slot = 1, MAX_TARGETS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(22)
        if slot == 1 then
            row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -58)
        else
            row:SetPoint("TOPLEFT", panel.rows[slot - 1], "BOTTOMLEFT", 0, -2)
            row:SetPoint("TOPRIGHT", panel.rows[slot - 1], "BOTTOMRIGHT", 0, -2)
        end

        local index = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        index:SetPoint("LEFT", row, "LEFT", 2, 0)
        index:SetWidth(18)
        index:SetJustifyH("RIGHT")
        index:SetText(slot .. ".")

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", index, "RIGHT", 4, 0)
        row.icon = icon

        local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -24, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name

        local remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        remove:SetSize(22, 22)
        remove:SetPoint("RIGHT", row, "RIGHT", 4, 0)
        remove:SetScript("OnClick", function() removeFinder(slot) end)
        row.remove = remove

        panel.rows[slot] = row
    end

    local addLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", panel.rows[MAX_TARGETS], "BOTTOMLEFT", 0, -12)
    addLabel:SetText("Add target:")

    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetSize(170, 20)
    input:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 6, -6)
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input:SetScript("OnEnterPressed", function(self) submitInput(self) end)
    input:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(60, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 10, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function() submitInput(input) end)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(80, 22)
    resetButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", resetFinder)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 20)
    hint:SetPoint("RIGHT", resetButton, "LEFT", -8, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Leave the field empty to use the current target.")

    return panel
end

refreshPanel = function()
    if not panel then return end
    local targets = readTargets()
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local name = targets[slot]
        if name then
            row.name:SetText(name)
            row.name:SetTextColor(1, 1, 1)
            SetRaidTargetIconTexture(row.icon, FIND_MARKERS[slot])
            row.icon:Show()
            row.remove:Show()
        else
            row.name:SetText("—")
            row.name:SetTextColor(0.5, 0.5, 0.5)
            row.icon:Hide()
            row.remove:Hide()
        end
    end
end

local function togglePanel()
    buildPanel()
    if panel:IsShown() then
        panel:Hide()
        return
    end
    refreshPanel()
    panel:Show()
end

local function setupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if LDBIcon:IsRegistered(ADDON_NAME) then return end

    local dataObject = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = ADDON_NAME,
        icon = MINIMAP_ICON,
        OnClick = function(_, button)
            if button == "LeftButton" then
                togglePanel()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(ADDON_NAME)
            tt:AddLine("|cffffffffClick|r to toggle the panel.", 1, 1, 1)
        end,
    })

    if QuickTargetDB.minimap.angle and not QuickTargetDB.minimap.minimapPos then
        QuickTargetDB.minimap.minimapPos = QuickTargetDB.minimap.angle
    end
    QuickTargetDB.minimap.angle = nil

    LDBIcon:Register(ADDON_NAME, dataObject, QuickTargetDB.minimap)
end

local QT_HELP_LINES = {
    "/qt           -- open the finder panel",
    "/qt help      -- list available commands",
    "/find NAME    -- set finder (uses current target if omitted)",
    "/findadd NAME -- add to finder (max " .. MAX_TARGETS .. ")",
    "/find reset   -- reset finder",
    "/assist NAME  -- set assist (uses current target if omitted)",
    "Right-click a unit frame for finder and assist options.",
}

local function printHelp()
    announce("Commands:")
    for _, line in ipairs(QT_HELP_LINES) do
        print("  " .. line)
    end
end

SLASH_QUICKTARGET_PANEL1 = "/qt"
SlashCmdList.QUICKTARGET_PANEL = function(msg)
    local arg = trim(msg)
    if arg and arg:lower() == "help" then
        printHelp()
        return
    end
    togglePanel()
end

SLASH_QUICKTARGET_FIND1 = "/find"
SlashCmdList.QUICKTARGET_FIND = function(msg)
    local arg = trim(msg)
    if arg and arg:lower() == "reset" then
        resetFinder()
        return
    end
    setFinder(resolveName(msg))
end

SLASH_QUICKTARGET_ADD1 = "/findadd"
SlashCmdList.QUICKTARGET_ADD = function(msg)
    addFinder(resolveName(msg))
end

SLASH_QUICKTARGET_ASSIST1 = "/assist"
SlashCmdList.QUICKTARGET_ASSIST = function(msg)
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

local function canAssistContext(context)
    if context.unit and UnitExists(context.unit) then
        return UnitCanAssist("player", context.unit)
    end
    return true
end

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
    local targets = readTargets()
    local lowered = name:lower()
    for slot, saved in ipairs(targets) do
        if saved and lowered:find(saved:lower(), 1, true) then
            root:CreateButton("Remove from Finder", function() C_Timer.After(0, function() removeFinder(slot) end) end)
            break
        end
    end
    if #targets > 0 then
        root:CreateButton("Reset Finder", function() C_Timer.After(0, function() resetFinder() end) end)
    end
    if canAssistContext(context) then
        root:CreateButton("Set Assist", function() C_Timer.After(0, function() setAssist(name) end) end)
    end
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(UNIT_MENU_TAGS) do
        Menu.ModifyMenu(tag, appendMenu)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(QuickTargetDB) ~= "table" then QuickTargetDB = {} end
        if type(QuickTargetDB.minimap) ~= "table" then
            QuickTargetDB.minimap = { hide = false, minimapPos = MINIMAP_DEFAULT_POS }
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        setupMinimapButton()
        announce("Loaded. Type /qt help for available commands.")
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_TARGET_CHANGED" then
        applyMarkerFromTarget()
    end
end)
