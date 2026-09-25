local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

-- A tool window with a list and a row of actions is the job Blizzard gives ButtonFrameTemplate: AddonList, MacroFrame and FriendsFrame inherit it on both clients, and the name resolves to Classic art on 1.15.9 (Classic/SharedUIPanelTemplates.xml:708) and Mainline art on 1.60.1 (Mainline/SharedUIPanelTemplates.xml:711). The dialog kit is for small popups, which eight editable rows are not. Layout follows AddonList: no portrait, attic text at 12,-30, action buttons 4px in from the bottom corners.
local PANEL_NAME = "TargetFinderPanel"
local PANEL_WIDTH = 360

-- ButtonFrameTemplate puts the Inset 60px below the top (the attic) and 26px above the bottom (the button bar).
local ATTIC_HEIGHT = 60
local BUTTON_BAR_HEIGHT = 26
local ATTIC_X = 12
local ATTIC_Y = -30
local BAR_INSET = 4

local ROW_HEIGHT = 24
local ROW_PAD_X = 8
local ROW_PAD_Y = 6
local INDEX_WIDTH = 16
local ICON_SIZE = 16
local ROW_GAP = 4

-- InputBoxTemplate draws its left cap 5px outside the box, so the box starts that far past its neighbour to keep the art clear of it.
local INPUT_ART_OFFSET = 6
local INPUT_HEIGHT = 20
local ROW_BUTTON_SIZE = 24
local ADD_BUTTON_WIDTH = 48

local NEARBY_WIDTH = 176
local CLEAR_WIDTH = 128
local BUTTON_HEIGHT = 22

local NEARBY_LABEL = "Add Nearby Quest Units"
local NEARBY_HELP = "Replaces the list with the kill, loot and turn-in NPCs of your quests that are closest to you."
local CLEAR_LABEL = "Clear Unit List"
local PANEL_HELP = "Track up to " .. MAX_TARGETS .. " units. FIND targets the highest slot in range and marks it; names match from their start."

local panel

-- Typing in a row and pressing Enter, clicking Add, or clearing the box and pressing Enter all land here.
function ns.ApplyRowInput(slot)
    if not panel or not panel.rows then return end
    local row = panel.rows[slot]
    if not row then return end
    local input = row.input
    local typed = ns.Trim(input:GetText())
    local current = ns.targets[slot]

    if not typed then
        if current then ns.RemoveFinder(slot) end
        input:ClearFocus()
        ns.HideSuggestions(input)
        return
    end

    local existingSlot = ns.SlotForName(typed)
    if existingSlot then
        if existingSlot ~= slot then
            ns.Announce(typed .. " is already tracked.")
            input:SetText(current and current.name or "")
        end
        input:ClearFocus()
        ns.HideSuggestions(input)
        if row.updateState then row.updateState() end
        return
    end

    ns.SetSlot(slot, typed)
    input:ClearFocus()
    ns.HideSuggestions(input)
end

-- The slot the trailing remove button would clear: the one holding the typed name, or this row's own entry while the box is empty. Nil means the typed text is new and Add applies instead.
local function removableSlot(slot, typed)
    if typed then return ns.SlotForName(typed) end
    if ns.targets[slot] then return slot end
    return nil
end

-- The trailing button is whichever action the typed text affords, and the input's right edge follows it so the row never overlaps.
local function layoutTrailing(row, slot)
    local input = row.input
    local typed = ns.Trim(input:GetText())
    local stored = ns.targets[slot]
    input.tfStored = stored and stored.name or nil

    local removeSlot = removableSlot(slot, typed)
    local showAdd = typed ~= nil and removeSlot == nil
    row.addBtn:SetShown(showAdd)
    row.removeBtn:SetShown(removeSlot ~= nil)
    row.removeBtn.targetSlot = removeSlot

    input:ClearAllPoints()
    input:SetPoint("LEFT", row.icon, "RIGHT", INPUT_ART_OFFSET + ROW_GAP, 0)
    local trailing = (showAdd and row.addBtn) or (removeSlot and row.removeBtn)
    if trailing then
        input:SetPoint("RIGHT", trailing, "LEFT", -INPUT_ART_OFFSET, 0)
    else
        input:SetPoint("RIGHT", row, "RIGHT", -INPUT_ART_OFFSET, 0)
    end
end

local function buildSlotInput(row, slot)
    local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    input:SetHeight(INPUT_HEIGHT)
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input.slot = slot

    input:SetScript("OnEnterPressed", function(self)
        if ns.TakeSelectedSuggestion(self) then return end
        ns.ApplyRowInput(slot)
    end)
    input:SetScript("OnEscapePressed", function(self)
        local stored = ns.targets[slot]
        self:SetText(stored and stored.name or "")
        self:ClearFocus()
        ns.HideSuggestions(self)
        row.updateState()
    end)
    return input
end

-- Add is a plain UIPanelButtonTemplate and remove the client's own close button, so both carry each client's art. NoScripts, because the stock close handler would hide the whole row.
local function buildRowButtons(row, slot)
    local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    addBtn:SetSize(ADD_BUTTON_WIDTH, BUTTON_HEIGHT)
    addBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    addBtn:SetText(ADD)
    addBtn:SetScript("OnClick", function() ns.ApplyRowInput(slot) end)
    addBtn:Hide()
    row.addBtn = addBtn

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    removeBtn:SetSize(ROW_BUTTON_SIZE, ROW_BUTTON_SIZE)
    removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    removeBtn:SetScript("OnClick", function() ns.RemoveFinder(removeBtn.targetSlot or slot) end)
    removeBtn:Hide()
    row.removeBtn = removeBtn
end

local function buildSlotRow(parent, slot)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    local top = -ROW_PAD_Y - (slot - 1) * ROW_HEIGHT
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_PAD_X, top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ROW_PAD_X, top)

    local index = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    index:SetPoint("LEFT", row, "LEFT", 0, 0)
    index:SetWidth(INDEX_WIDTH)
    index:SetJustifyH("RIGHT")
    index:SetText(slot .. ".")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", index, "RIGHT", ROW_GAP, 0)
    icon:Hide()
    row.icon = icon

    buildRowButtons(row, slot)
    row.input = buildSlotInput(row, slot)
    row.updateState = function() layoutTrailing(row, slot) end
    ns.AttachAutocomplete(row.input, row.updateState)

    row.updateState()
    return row
end

-- Blizzard's tooltip helpers carry each client's tooltip colours; the error line says why the button is off.
local function showNearbyTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, NEARBY_LABEL)
    GameTooltip_AddNormalLine(GameTooltip, NEARBY_HELP)
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(GameTooltip, ns.QuestieExcuse())
    end
    GameTooltip:Show()
end

local function buildButtonBar(frame)
    local nearbyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nearbyButton:SetSize(NEARBY_WIDTH, BUTTON_HEIGHT)
    nearbyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BAR_INSET, BAR_INSET)
    nearbyButton:SetText(NEARBY_LABEL)
    nearbyButton:SetScript("OnClick", function() ns.AddNearbyQuestNpcs() end)

    -- Motion scripts stay alive while disabled, so the tooltip can still explain what is missing.
    nearbyButton:SetMotionScriptsWhileDisabled(true)
    nearbyButton:SetScript("OnEnter", showNearbyTooltip)
    nearbyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.nearbyButton = nearbyButton

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(CLEAR_WIDTH, BUTTON_HEIGHT)
    clearButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
    clearButton:SetText(CLEAR_LABEL)
    clearButton:SetScript("OnClick", function() ns.ClearFinder() end)
end

-- Movable, clamped and toplevel like Blizzard's own windows; Escape closes it through UISpecialFrames, which needs the global name. It stays out of UIPanelWindows so the addon never drives Blizzard's panel layout, which is a taint source.
local function buildPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", PANEL_NAME, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(panel)
    panel:SetTitle(ns.ADDON_NAME)
    panel:SetSize(PANEL_WIDTH, ATTIC_HEIGHT + ROW_PAD_Y * 2 + MAX_TARGETS * ROW_HEIGHT + BUTTON_BAR_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnShow", function() ns.RefreshPanel() end)
    panel:Hide()
    tinsert(UISpecialFrames, PANEL_NAME)

    -- The template's close button calls HideUIPanel, which refuses insecure callers in combat on both clients (UIParentPanelManager.lua CheckProtectedFunctionsAllowed). UIPanelCloseButton_OnClick asks onCloseCallback first, so the panel hides itself and the stock path is skipped.
    panel.onCloseCallback = function()
        panel:Hide()
        return false
    end

    local helper = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helper:SetPoint("TOPLEFT", panel, "TOPLEFT", ATTIC_X, ATTIC_Y)
    helper:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -ATTIC_X, ATTIC_Y)
    helper:SetJustifyH("LEFT")
    helper:SetWordWrap(true)
    helper:SetText(PANEL_HELP)

    panel.rows = {}
    for slot = 1, MAX_TARGETS do
        panel.rows[slot] = buildSlotRow(panel.Inset, slot)
    end

    buildButtonBar(panel)
    return panel
end

function ns.RefreshPanel()
    if not panel then return end
    if panel.nearbyButton then
        panel.nearbyButton:SetEnabled(ns.QuestieReady())
    end
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local entry = ns.targets[slot]
        if not row.input:HasFocus() then
            row.input:SetText(entry and entry.name or "")
            row.input:SetCursorPosition(0)
        end
        if entry then
            ns.ShowMarkerTexture(row.icon, ns.FIND_MARKERS[slot])
        else
            row.icon:Hide()
        end
        row.updateState()
    end
end

function ns.TogglePanel()
    buildPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
