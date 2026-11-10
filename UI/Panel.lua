local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

-- Sizes from the design system (wow-forever-dev, ui-components.md): spacing on the 4 px grid, the 24 px row and the 16 px inline icon.
local TIGHT = 4
local GAP = 8
local PADDING = 16
local ROW = 24
local ICON = 16

-- InputBoxTemplate draws its left cap 5 px outside the box (Shared/InputBox/InputBoxTemplates.xml:49), so a box is indented by it.
local EDIT_BOX_CAP = 5

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
-- The suggestion popup writes its hint with it too, so it lives on ns.
function ns.CreateText(parent, fontObject, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(fontObject or GameFontHighlight)
    text:SetJustifyH("LEFT")
    return text
end
local CreateText = ns.CreateText

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
local function AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- AttachTooltip for a frame whose template already sets OnEnter and OnLeave, such as InputBoxInstructionsTemplate and
-- UIPanelButtonTemplate: the same tooltip, hooked so the template's own scripts still run.
local function HookTooltip(frame, fill, anchor)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- Rounds a length derived from text up to the 4 px grid.
local function Snap(length)
    return math.ceil(length / 4) * 4
end

-- A content button one row (24) tall. Without a width it fits its label the way UIPanelButtonTemplate's FitToText
-- does (text plus 40, SecureUIPanelTemplates.xml:42), at least 64, rounded up to 8 so neighbours share widths.
local function CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    width = width or math.max(64, math.ceil((button:GetTextWidth() + 40) / 8) * 8)
    button:SetSize(width, 24)
    return button
end

-- CheckboxWithLabelTemplate: the minimal art Blizzard's Settings use, at the 24 px AddonList gives it
-- (Blizzard_AddOnList/AddonList.xml:73-74). The label joins the hit rect, so a click on it toggles the box.
local function CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "CheckboxWithLabelTemplate")
    checkbox:SetSize(24, 24)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
    return checkbox
end

-- InputBoxInstructionsTemplate: the same box plus Blizzard's grey hint, so an empty field says what it takes.
-- The hint moves to the muted font where typed text starts, keeping the template's grey.
local function CreateHintBox(parent, hint, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxInstructionsTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(GameFontDisable)
    box.Instructions:SetTextColor(r, g, b)
    box.Instructions:ClearAllPoints()
    box.Instructions:SetAllPoints()
    box.Instructions:SetText(hint)
    return box
end

-- The close button Blizzard uses for one row of a list, sized to the row.
local function CreateRemoveButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
    button:SetSize(24, 24)
    return button
end

-- The collections panel's ornaments, which a tool window leaves out.
local BACKGROUND_CORNERS = { "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }

-- Restores a saved position, or centres the frame.
local function RestorePosition(frame, position)
    frame:ClearAllPoints()
    if position and position.point then
        frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Windows and dialogs: toplevel, clamped, dragged with the left button, closed by Escape through UISpecialFrames,
-- never UIPanelWindows, so they never drive Blizzard's panel layout.
local function MakeMovable(frame, name, strata, position)
    frame:SetFrameStrata(strata)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if position then
            local point, _, relPoint, x, y = self:GetPoint(1)
            position.point, position.relPoint, position.x, position.y = point, relPoint, x, y
        end
    end)
    RestorePosition(frame, position)
    frame:Hide()
    tinsert(UISpecialFrames, name)
end

-- A tool window on ButtonFrameTemplate: portrait, title, close button, inset, attic and button bar come from the
-- template. The wardrobe's brown panel (CollectionsBackgroundTemplate, Mainline/SharedCollectionTemplates.xml) takes
-- the inset's place without its corner ornaments; Inset stays the content parent and draws nothing.
local function CreateWindow(name, title, icon, width, height, position)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    frame:SetSize(width, height)
    frame.Inset.Bg:Hide()
    frame.Inset.NineSlice:Hide()
    local background = CreateFrame("Frame", nil, frame, "CollectionsBackgroundTemplate")
    background:ClearAllPoints()
    background:SetAllPoints(frame.Inset)
    for _, corner in ipairs(BACKGROUND_CORNERS) do background[corner]:Hide() end
    frame.Background = background
    frame:SetTitle(title)
    frame:SetPortraitToAsset(icon)

    -- The close button goes through HideUIPanel, which refuses insecure callers in combat. UIPanelCloseButton_OnClick
    -- asks onCloseCallback first, so the window hides itself instead.
    frame.onCloseCallback = function()
        frame:Hide()
        return false
    end

    MakeMovable(frame, name, "HIGH", position)
    return frame
end

-- A help line in the attic, from title left 58 to the rows' right edge, cut rather than wrapped. Two lines sit one
-- gap either side of the attic's middle: a gold how-to over a white next step.
local function CreateAtticLine(frame, fontObject, y, rightOffset)
    local line = CreateText(frame, fontObject)
    line:SetPoint("LEFT", frame, "TOPLEFT", 58, y)
    line:SetPoint("RIGHT", frame, "TOPRIGHT", rightOffset, y)
    line:SetWordWrap(false)
    return line
end

-- The portrait as a drag source, the way a spell leaves the spellbook: dragging it puts the addon's action on the
-- cursor.
local function CreatePortraitDrag(frame, pickup)
    local button = CreateFrame("Button", nil, frame.PortraitContainer)
    button:SetAllPoints(frame:GetPortrait())
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", pickup)
    return button
end

-- Builds the window on first use and flips it after that, so no frame exists until the player asks.
local function CreateToggle(build)
    local window
    return function()
        window = window or build()
        window:SetShown(not window:IsShown())
    end
end

-- A tool window with a list and a row of actions is the job Blizzard gives ButtonFrameTemplate (Mainline/SharedUIPanelTemplates.xml:711), which CreateWindow builds. The dialog chrome is for small popups, which eight editable rows are not.
local PANEL_NAME = "TargetFinderFrame"

-- Wide enough that each line of the attic help fits beside the portrait. The bar's checkboxes can widen it (fitBarWidth).
local PANEL_WIDTH = 400

-- Editable rows sit one gap apart, so the 20px edit boxes never touch.
local ROW_PITCH = ROW + GAP

-- The attic's first line says how to fill the list. The second names the next FIND step: the first name creates it, then the player places it, then presses it.
local HELP_ADD = "Type names below or right-click a portrait to Track."
local STEP_CREATE = "The first name creates your FIND macro."
local STEP_PLACE = "Drag the icon to an action bar to place FIND."
local STEP_PRESS = "Press FIND to target the first listed NPC in range."

-- The list's empty state. The rows fill the inset, so instead of a centred line over them the first row's own grey hint says what the list takes while nothing is listed; the attic's gold line already says how to fill it.
local EMPTY_HINT = "NPC or player name"

local NAME_HELP = "Type an NPC or player name and press Enter. FIND matches whole names only."
local ADD_HELP = "Saves the typed name in this row. Enter does the same."

local FIND_HELP = "Target Finder creates this macro and updates it whenever the list changes. Drag it to an action bar, then press it to target the first NPC on the list that is in range."

local QUEST_LABEL = "Auto Apply Quest NPCs"
local QUEST_HELP = "Fills free rows with the kill, loot and turn-in NPCs of your quests that are closest to you. They update when you accept, turn in or abandon a quest and when you change zones, and leave once done. Names you added are never replaced."
local QUEST_REFRESH = "Right-click the minimap button or type /tf refresh to update them now, also with this box off."

local MARKER_LABEL = "Apply Raid Markers"
local MARKER_HELP = "FIND marks the NPC it targets with a cross, as RestedXP's targeting macro does."
local MARKER_RIGHTS = "In a group, markers need leader or assistant rights."

local PING_LABEL = "Apply Pings"
local PING_HELP = "FIND pings the NPC it targets as your ping key does, so your group sees it too."

-- The template's 26px button bar fits a 22px button, which leaves a 24px checkbox no room. The bar grows to one gap above and below the checkboxes, measured from the frame's bottom border, MagicButton_OnLoad's 4px inset (Mainline/SharedUIPanelTemplates.lua:34). The checkboxes start at the rows' left edge.
local BAR_BORDER = 4
local BAR_HEIGHT = BAR_BORDER + GAP + ROW + GAP
local BAR_LEFT = PANEL_INSET_LEFT_OFFSET + PADDING
local BAR_MIDDLE = BAR_BORDER + GAP + ROW / 2

local panel

-- Typing in a row and pressing Enter, clicking Add, picking a suggestion, or clearing the box and pressing Enter all land here.
function ns.ApplyRowInput(slot)
    local row = panel.rows[slot]
    local input = row.input
    local typed = ns.Trim(input:GetText())
    local current = ns.targets[slot]
    local existingSlot = ns.SlotForName(typed)

    if not typed then
        if current then ns.RemoveFinder(slot) end
    elseif not existingSlot then
        ns.SetSlot(slot, typed)
    elseif existingSlot ~= slot then
        ns.Print(typed .. " is already tracked.")
        input:SetText(current and current.name or "")
    end
    input:ClearFocus()
    ns.HideSuggestions(input)
    row.updateState()
end

-- The trailing column holds Add while the box differs from the stored name and the X while it shows it or is empty. The X always clears its own row.
local function updateTrailing(row, slot)
    local typed = ns.Trim(row.input:GetText())
    local stored = ns.targets[slot]
    row.input.tfStored = stored and stored.name or nil

    local showAdd = typed ~= nil and (not stored or typed ~= stored.name)
    row.addBtn:SetShown(showAdd)
    row.removeBtn:SetShown(stored ~= nil and not showAdd)
end

local function buildSlotInput(row, slot)
    local input = CreateHintBox(row, "")
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
    HookTooltip(input, function(tooltip)
        GameTooltip_SetTitle(tooltip, "Row " .. slot)
        GameTooltip_AddNormalLine(tooltip, NAME_HELP)
    end)
    return input
end

-- Add fills a fixed trailing column, so the input's right edge never moves. The X sits one tight step after the input instead of in that column, so it reads as part of the entry. The remove button is Blizzard's close button without its scripts, because the stock close handler would hide the whole row.
local TRAILING_WIDTH = 48

local function buildRowButtons(row, slot)
    local addBtn = CreateButton(row, ADD, TRAILING_WIDTH)
    addBtn:SetPoint("RIGHT", row, "RIGHT")
    addBtn:SetScript("OnClick", function() ns.ApplyRowInput(slot) end)
    HookTooltip(addBtn, function(tooltip)
        GameTooltip_SetTitle(tooltip, ADD)
        GameTooltip_AddNormalLine(tooltip, ADD_HELP)
    end)
    addBtn:Hide()
    row.addBtn = addBtn

    -- The X only shows on a stored row, so its tooltip names that row's entry, in the words of the unit menu's Untrack.
    local removeBtn = CreateRemoveButton(row)
    removeBtn:SetScript("OnClick", function() ns.RemoveFinder(slot) end)
    AttachTooltip(removeBtn, function(tooltip)
        local stored = ns.targets[slot]
        GameTooltip_SetTitle(tooltip, REMOVE)
        if stored then GameTooltip_AddNormalLine(tooltip, "Takes " .. stored.name .. " off the FIND list.") end
    end)
    removeBtn:Hide()
    row.removeBtn = removeBtn
end

-- Dragging a row's number moves its name to another row, the way Blizzard's lists reorder (ScrollUtil.lua:1552-1580, ConfigureDragBehavior): the dragged row fades to half, and Blizzard's drag line marks where it lands, above the row under the cursor when it moves up and below it when it moves down. The rows are no ScrollBox, so the same look is built from the same template.
local DRAG_LINE_OFFSET = 3
local dragFrom, dragTo, dragLine

local function rowUnderCursor()
    for slot, row in ipairs(panel.rows) do
        if row:IsMouseOver() then return slot end
    end
    return nil
end

local function placeDragLine()
    local over = rowUnderCursor()
    if over then dragTo = over end
    dragLine:ClearAllPoints()
    if not dragTo or dragTo == dragFrom then
        dragLine:Hide()
        return
    end
    local row = panel.rows[dragTo]
    if dragTo < dragFrom then
        dragLine:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, DRAG_LINE_OFFSET)
        dragLine:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, DRAG_LINE_OFFSET)
    else
        dragLine:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -DRAG_LINE_OFFSET)
        dragLine:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -DRAG_LINE_OFFSET)
    end
    dragLine:Show()
end

local function startRowDrag(handle, slot)
    if not ns.targets[slot] then return end
    dragFrom, dragTo = slot, slot
    dragLine = dragLine or CreateFrame("Frame", nil, panel.Inset, "ScrollBoxDragLineTemplate")
    panel.rows[slot]:SetAlpha(0.5)
    handle:SetScript("OnUpdate", placeDragLine)
end

local function stopRowDrag(handle)
    if not dragFrom then return end
    handle:SetScript("OnUpdate", nil)
    panel.rows[dragFrom]:SetAlpha(1)
    dragLine:Hide()
    local from, to = dragFrom, dragTo
    dragFrom, dragTo = nil, nil
    if to and to ~= from then ns.MoveTarget(from, to) end
end

local function fillHandleTooltip(tooltip, slot)
    GameTooltip_SetTitle(tooltip, "Row " .. slot)
    GameTooltip_AddNormalLine(tooltip, "FIND targets row 1 first, then each row below it.")
    GameTooltip_AddInstructionLine(tooltip, "Drag to move this name to another row.")
end

-- The row number is the handle, together with the quest icon beside it, so the grip has a visible mark on every row.
local function buildRowHandle(row, slot)
    local number = CreateText(row, GameFontNormal)
    number:SetSize(ICON, ROW)
    number:SetPoint("LEFT", row, "LEFT")
    number:SetJustifyH("CENTER")
    number:SetText(slot)
    row.number = number

    local handle = CreateFrame("Button", nil, row)
    handle:SetPoint("TOPLEFT", row, "TOPLEFT")
    handle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    handle:SetWidth(ICON + TIGHT + ICON)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function(self) startRowDrag(self, slot) end)
    handle:SetScript("OnDragStop", stopRowDrag)
    AttachTooltip(handle, function(tooltip) fillHandleTooltip(tooltip, slot) end)
    row.handle = handle
end

local function buildSlotRow(parent, slot)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    local top = -PADDING - (slot - 1) * ROW_PITCH
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING, top)

    buildRowHandle(row, slot)

    -- The kill, loot or turn-in icon marks a row the quest log fills. A typed row leaves it empty.
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", row.number, "RIGHT", TIGHT, 0)
    icon:Hide()
    row.icon = icon

    buildRowButtons(row, slot)
    row.input = buildSlotInput(row, slot)

    -- InputBoxTemplate, which the hint box inherits, hangs only its left cap outside the box, so the box starts that far past one gap.
    row.input:SetPoint("LEFT", icon, "RIGHT", GAP + EDIT_BOX_CAP, 0)
    row.input:SetPoint("RIGHT", row.addBtn, "LEFT", -GAP, 0)
    row.removeBtn:SetPoint("LEFT", row.input, "RIGHT", TIGHT, 0)
    row.updateState = function() updateTrailing(row, slot) end
    ns.AttachAutocomplete(row.input, row.updateState)

    row.updateState()
    return row
end

local function fillFindTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, ns.FIND_MACRO)
    GameTooltip_AddNormalLine(tooltip, FIND_HELP)
end

-- The portrait shows FIND's own icon, so dragging it hands FIND to the cursor, the way a spell leaves the spellbook.
local function buildFindIcon(frame)
    local button = CreatePortraitDrag(frame, function() ns.PickupFinder() end)
    AttachTooltip(button, fillFindTooltip)
end

-- Two lines of help in the attic, the band between the title bar and the Inset, one gap either side of the band's middle: a gold line on how to fill the list over a white line with the next FIND step, as Blizzard sets gold over white. Their right edge lines up with the rows below.
local function buildAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    local rightOffset = PANEL_INSET_RIGHT_OFFSET - PADDING
    frame.help = CreateAtticLine(frame, GameFontNormal, atticMiddle + GAP, rightOffset)
    frame.help:SetText(HELP_ADD)
    frame.nextStep = CreateAtticLine(frame, GameFontHighlight, atticMiddle - GAP, rightOffset)
end

-- Blizzard's tooltip helpers carry the standard tooltip colours; the error line says why the box is off.
local function fillQuestTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, QUEST_LABEL)
    GameTooltip_AddNormalLine(tooltip, QUEST_HELP)
    GameTooltip_AddInstructionLine(tooltip, QUEST_REFRESH)
    if not ns.QuestDataReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestDataExcuse())
    end
end

-- The bar's first control, level with the rows above.
local function buildQuestBox(frame)
    local box = CreateCheckbox(frame, QUEST_LABEL)
    box:SetPoint("LEFT", frame, "BOTTOMLEFT", BAR_LEFT, BAR_MIDDLE)
    box:SetScript("OnClick", function(self) ns.SetQuestNpcs(self:GetChecked()) end)

    -- Motion scripts stay alive while disabled, so the tooltip can still explain what is missing.
    box:SetMotionScriptsWhileDisabled(true)
    AttachTooltip(box, fillQuestTooltip)
    frame.questBox = box
end

local function fillMarkerTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, MARKER_LABEL)
    GameTooltip_AddNormalLine(tooltip, MARKER_HELP)
    if ns.CanMark() then
        GameTooltip_AddNormalLine(tooltip, MARKER_RIGHTS)
    else
        GameTooltip_AddErrorLine(tooltip, MARKER_RIGHTS)
    end
end

-- The second bar control follows the first after one padding step.
local function buildMarkerBox(frame)
    local box = CreateCheckbox(frame, MARKER_LABEL)
    box:SetPoint("LEFT", frame.questBox.Text, "RIGHT", PADDING, 0)
    box:SetScript("OnClick", function(self) ns.SetRaidMarkers(self:GetChecked()) end)
    AttachTooltip(box, fillMarkerTooltip)
    frame.markerBox = box
end

local function fillPingTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, PING_LABEL)
    GameTooltip_AddNormalLine(tooltip, PING_HELP)
end

-- The third bar control follows the second the same way.
local function buildPingBox(frame)
    local box = CreateCheckbox(frame, PING_LABEL)
    box:SetPoint("LEFT", frame.markerBox.Text, "RIGHT", PADDING, 0)
    box:SetScript("OnClick", function(self) ns.SetPings(self:GetChecked()) end)
    AttachTooltip(box, fillPingTooltip)
    frame.pingBox = box
end

-- The bar's checkboxes share one line, so the window grows past PANEL_WIDTH when their labels need the room, keeping the rows' margin on the right. Each box is one row square with its label one tight step on, as CreateCheckbox lays it out.
local function fitBarWidth(frame, boxes)
    local width = BAR_LEFT + PADDING - PANEL_INSET_RIGHT_OFFSET
    for i, box in ipairs(boxes) do
        if i > 1 then width = width + PADDING end
        width = width + ROW + TIGHT + box.Text:GetStringWidth()
    end
    frame:SetWidth(math.max(PANEL_WIDTH, Snap(width)))
end

-- The template's 60px attic, the padded rows and the grown bar add up on the grid; the snap keeps it there if a size changes.
local function panelHeight()
    local contentHeight = PADDING * 2 + MAX_TARGETS * ROW_PITCH - GAP
    return Snap(-PANEL_INSET_ATTIC_OFFSET + contentHeight + BAR_HEIGHT)
end

local function updateHelp()
    local text = STEP_CREATE
    if ns.FinderOnBar() then
        text = STEP_PRESS
    elseif ns.FinderExists() then
        text = STEP_PLACE
    end
    panel.nextStep:SetText(text)
end

local function buildPanel()
    panel = CreateWindow(PANEL_NAME, ns.title, ns.ADDON_ICON, PANEL_WIDTH, panelHeight(), ns.db.position)
    -- Blizzard's own setter for the bar under the Inset (Mainline/SharedUIPanelTemplates.lua:57). The brown panel is anchored to the Inset, so it follows.
    FrameTemplate_SetButtonBarHeight(panel, BAR_HEIGHT)
    -- Dropping FIND on a bar while the window is open switches the step line. Bar slots change in bursts on every
    -- form and page swap, so the event is only watched while the window shows.
    panel:SetScript("OnShow", function(self)
        self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        ns.RefreshPanel()
    end)
    panel:SetScript("OnHide", function(self) self:UnregisterEvent("ACTIONBAR_SLOT_CHANGED") end)
    panel:SetScript("OnEvent", updateHelp)

    buildFindIcon(panel)
    buildAtticHelp(panel)

    panel.rows = {}
    for slot = 1, MAX_TARGETS do
        panel.rows[slot] = buildSlotRow(panel.Inset, slot)
    end

    buildQuestBox(panel)
    buildMarkerBox(panel)
    buildPingBox(panel)
    fitBarWidth(panel, { panel.questBox, panel.markerBox, panel.pingBox })
    return panel
end

-- A hidden window catches up in OnShow, so writes made while it is closed skip the row and action bar scan.
function ns.RefreshPanel()
    if not ns.PanelShown() then return end
    updateHelp()

    local ready = ns.QuestDataReady()
    panel.questBox:SetChecked(TargetFinderCharDB.questNpcs)
    panel.questBox:SetEnabled(ready)
    panel.questBox.Text:SetFontObject(ready and GameFontHighlight or GameFontDisable)
    panel.markerBox:SetChecked(TargetFinderCharDB.raidMarkers)
    panel.pingBox:SetChecked(TargetFinderCharDB.pings)

    panel.rows[1].input.Instructions:SetText(next(ns.targets) == nil and EMPTY_HINT or "")
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local entry = ns.targets[slot]
        if not row.input:HasFocus() then
            row.input:SetText(entry and entry.name or "")
            row.input:SetCursorPosition(0)
        end
        local atlas = entry and entry.kind and ns.KIND_ATLAS[entry.kind]
        if atlas then
            row.icon:SetAtlas(atlas)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.updateState()
    end
end

function ns.PanelShown()
    return panel ~= nil and panel:IsShown()
end

-- The minimap button, the addon menu and /tf share this one toggle.
ns.TogglePanel = CreateToggle(buildPanel)

-- The welcome line's link only ever opens the window.
function ns.ShowPanel()
    if not ns.PanelShown() then ns.TogglePanel() end
end
