local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

local MAX_TARGETS = ns.MAX_TARGETS

-- A tool window with a list and a row of actions is the job Blizzard gives ButtonFrameTemplate (Mainline/SharedUIPanelTemplates.xml:711), which UI.CreateWindow builds. The dialog kit is for small popups, which eight editable rows are not.
local PANEL_NAME = "TargetFinderFrame"

-- Wide enough that the one-line attic help fits beside the portrait.
local PANEL_WIDTH = 400

-- Editable rows sit one gap apart, so the 20px edit boxes never touch.
local ROW_PITCH = UI.Size.row + UI.Space.gap

-- The attic names the next step: add a name so Target Finder creates FIND, place it, then press it.
local HELP_ADD = "Add an NPC below to create your FIND macro."
local HELP_PLACE = "Your FIND macro is ready. Drag the icon to a bar."
local HELP_PRESS = "Press FIND to target the first NPC in range."

local FIND_HELP = "Target Finder creates this macro and updates it whenever the list changes. Drag it to an action bar, then press it to target the first NPC on the list that is in range."

local QUEST_LABEL = "Auto Apply Quest NPCs"
local QUEST_HELP = "Fills free rows with the kill, loot and turn-in NPCs of your quests that are closest to you, and keeps them up to date as you quest and change zones. They leave once done. Names you typed stay."

local MARKER_LABEL = "Apply Raid Markers"
local MARKER_HELP = "When you target an NPC from the list, it gets the raid marker of its row."
local MARKER_RIGHTS = "In a group, markers need leader or assistant rights."

-- MagicButton_OnLoad's inset for a bar control in the bottom-left corner (Mainline/SharedUIPanelTemplates.lua:34). The checkbox centres on the 22px bar button slot there.
local BAR_INSET = 4

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
        ns.Announce(typed .. " is already tracked.")
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
    local input = UI.CreateEditBox(row)
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

-- Add fills a fixed trailing column and the X sits centred in it, so the input's right edge never moves. The remove button is Blizzard's close button without its scripts, because the stock close handler would hide the whole row.
local TRAILING_WIDTH = 48

local function buildRowButtons(row, slot)
    local addBtn = UI.CreateButton(row, ADD, TRAILING_WIDTH)
    addBtn:SetPoint("RIGHT", row, "RIGHT")
    addBtn:SetScript("OnClick", function() ns.ApplyRowInput(slot) end)
    addBtn:Hide()
    row.addBtn = addBtn

    local removeBtn = UI.CreateRemoveButton(row)
    removeBtn:SetPoint("CENTER", addBtn, "CENTER")
    removeBtn:SetScript("OnClick", function() ns.RemoveFinder(slot) end)
    removeBtn:Hide()
    row.removeBtn = removeBtn
end

local function buildSlotRow(parent, slot)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(UI.Size.row)
    local top = -UI.Space.padding - (slot - 1) * ROW_PITCH
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.Space.padding, top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.Space.padding, top)

    -- Questie's own kill, loot or turn-in icon marks a row the quest log fills. A typed row leaves it empty.
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(UI.Size.icon, UI.Size.icon)
    icon:SetPoint("LEFT", row, "LEFT")
    icon:Hide()
    row.icon = icon

    buildRowButtons(row, slot)
    row.input = buildSlotInput(row, slot)

    -- InputBoxTemplate hangs only its left cap outside the box, so the box starts that far past one gap.
    row.input:SetPoint("LEFT", icon, "RIGHT", UI.Space.gap + UI.Native.inputArt, 0)
    row.input:SetPoint("RIGHT", row.addBtn, "LEFT", -UI.Space.gap, 0)
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
    local button = CreateFrame("Button", nil, frame.PortraitContainer)
    button:SetAllPoints(frame:GetPortrait())
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() ns.PickupFinder() end)
    UI.AttachTooltip(button, fillFindTooltip)
end

-- One line of help in the attic, the band between the title bar and the Inset, level with the title and centred on the band's height. Its right edge lines up with the rows below.
local function buildAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    local helper = UI.CreateText(frame, "body")
    helper:SetPoint("LEFT", frame, "TOPLEFT", UI.Native.titleLeft, atticMiddle)
    helper:SetPoint("RIGHT", frame, "TOPRIGHT", PANEL_INSET_RIGHT_OFFSET - UI.Space.padding, atticMiddle)
    helper:SetWordWrap(false)
    frame.help = helper
end

-- Blizzard's tooltip helpers carry the standard tooltip colours; the error line says why the box is off.
local function fillQuestTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, QUEST_LABEL)
    GameTooltip_AddNormalLine(tooltip, QUEST_HELP)
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

-- The bar's first control sits where a bar button would start.
local function buildQuestBox(frame)
    local box = UI.CreateCheckbox(frame, QUEST_LABEL)
    box:SetPoint("LEFT", frame, "BOTTOMLEFT", BAR_INSET, BAR_INSET + UI.Native.buttonHeight / 2)
    box:SetScript("OnClick", function(self) ns.SetQuestNpcs(self:GetChecked()) end)

    -- Motion scripts stay alive while disabled, so the tooltip can still explain what is missing.
    box:SetMotionScriptsWhileDisabled(true)
    UI.AttachTooltip(box, fillQuestTooltip)
    frame.questBox = box
end

-- One line per row, with Blizzard's own marker names (RAID_TARGET_1 to 8).
local function fillMarkerTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, MARKER_LABEL)
    GameTooltip_AddNormalLine(tooltip, MARKER_HELP)
    for slot, marker in ipairs(ns.SLOT_MARKERS) do
        GameTooltip_AddHighlightLine(tooltip, "Row " .. slot .. ": " .. _G["RAID_TARGET_" .. marker])
    end
    if ns.CanMark() then
        GameTooltip_AddNormalLine(tooltip, MARKER_RIGHTS)
    else
        GameTooltip_AddErrorLine(tooltip, MARKER_RIGHTS)
    end
end

-- The second bar control follows the first after one padding step.
local function buildMarkerBox(frame)
    local box = UI.CreateCheckbox(frame, MARKER_LABEL)
    box:SetPoint("LEFT", frame.questBox.Text, "RIGHT", UI.Space.padding, 0)
    box:SetScript("OnClick", function(self) TargetFinderCharDB.raidMarkers = self:GetChecked() end)
    UI.AttachTooltip(box, fillMarkerTooltip)
    frame.markerBox = box
end

-- The template's attic and button bar offsets (60 and 26) put the padded rows off the grid, so the height snaps up and the extra 2px fall into the inset's bottom padding.
local function panelHeight()
    local contentHeight = UI.Space.padding * 2 + MAX_TARGETS * ROW_PITCH - UI.Space.gap
    return UI.Snap(-PANEL_INSET_ATTIC_OFFSET + contentHeight + PANEL_INSET_BOTTOM_BUTTON_OFFSET)
end

local function updateHelp()
    local text = HELP_ADD
    if ns.FinderOnBar() then
        text = HELP_PRESS
    elseif ns.FinderExists() then
        text = HELP_PLACE
    end
    panel.help:SetText(text)
end

local function buildPanel()
    panel = UI.CreateWindow({
        name = PANEL_NAME,
        title = ns.ADDON_NAME,
        icon = ns.ADDON_ICON,
        width = PANEL_WIDTH,
        height = panelHeight(),
        position = TargetFinderDB.position,
    })
    -- Dropping FIND on a bar while the window is open switches the help line. Bar slots change in bursts on every
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
    return panel
end

-- A hidden window catches up in OnShow, so writes made while it is closed skip the row and action bar scan.
function ns.RefreshPanel()
    if not ns.PanelShown() then return end
    updateHelp()

    local ready = ns.QuestieReady()
    panel.questBox:SetChecked(TargetFinderCharDB.questNpcs)
    panel.questBox:SetEnabled(ready)
    panel.questBox.Text:SetFontObject(ready and UI.Font.body or UI.Font.muted)
    panel.markerBox:SetChecked(TargetFinderCharDB.raidMarkers)

    local icons = ns.QuestieKindIcons()
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local entry = ns.targets[slot]
        if not row.input:HasFocus() then
            row.input:SetText(entry and entry.name or "")
            row.input:SetCursorPosition(0)
        end
        local iconPath = entry and entry.kind and icons and icons[entry.kind]
        if iconPath then
            row.icon:SetTexture(iconPath)
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
ns.TogglePanel = UI.CreateToggle(buildPanel)
