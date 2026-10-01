local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

local MAX_TARGETS = ns.MAX_TARGETS

-- A tool window with a list and a row of actions is the job Blizzard gives ButtonFrameTemplate (Mainline/SharedUIPanelTemplates.xml:711), which UI.CreateWindow builds. The dialog kit is for small popups, which eight editable rows are not.
local PANEL_NAME = "TargetFinderFrame"

-- Wide enough that the 12px attic help wraps to two lines, which is all the 36px attic holds.
local PANEL_WIDTH = 50 * UI.GRID

-- Native geometry: PortraitFrameBaseTemplate draws its 62px portrait at x=-5 (Mainline/SharedUIPanelTemplates.xml:581-584), so its right edge sits 57px into the frame.
local NATIVE_PORTRAIT_RIGHT = 57

-- Attic text starts on the first grid line clear of the portrait, level with the title.
local ATTIC_LEFT = UI.Snap(NATIVE_PORTRAIT_RIGHT)

local INDEX_WIDTH = 2 * UI.GRID
local ADD_WIDTH = 6 * UI.GRID

-- MagicButtonTemplate is 80px wide, too narrow for this label.
local NEARBY_WIDTH = 22 * UI.GRID

local NEARBY_LABEL = "Add Nearby Quest Units"
local NEARBY_HELP = "Replaces the list with the kill, loot and turn-in NPCs of your quests that are closest to you."
local CLEAR_LABEL = "Clear Unit List"
local PANEL_HELP = "Track up to " .. MAX_TARGETS .. " units. FIND targets the highest slot in range and marks it; names match from their start."

local panel

-- SetRaidTargetIconTexture only picks the cell out of the sprite sheet (Mainline/TargetFrame.lua:690) and never assigns the file. Blizzard's own frames set it in XML, so a texture the addon creates has to be given the sheet first or the marker never draws.
local RAID_ICON_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function showMarkerTexture(texture, marker)
    texture:SetTexture(RAID_ICON_SHEET)
    SetRaidTargetIconTexture(texture, marker)
    texture:Show()
end

-- Typing in a row and pressing Enter, clicking Add, or clearing the box and pressing Enter all land here.
function ns.ApplyRowInput(slot)
    local row = panel.rows[slot]
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
        row.updateState()
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

    -- InputBoxTemplate hangs only its left cap outside the box, so the box starts that far past one gap and its right edge needs no compensation.
    input:ClearAllPoints()
    input:SetPoint("LEFT", row.icon, "RIGHT", UI.Space.gap + UI.Native.inputArt, 0)
    local trailing = (showAdd and row.addBtn) or (removeSlot and row.removeBtn)
    if trailing then
        input:SetPoint("RIGHT", trailing, "LEFT", -UI.Space.gap, 0)
    else
        input:SetPoint("RIGHT", row, "RIGHT")
    end
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

-- The remove button is Blizzard's close button without its scripts, because the stock close handler would hide the whole row.
local function buildRowButtons(row, slot)
    local addBtn = UI.CreateButton(row, ADD, ADD_WIDTH)
    addBtn:SetPoint("RIGHT", row, "RIGHT")
    addBtn:SetScript("OnClick", function() ns.ApplyRowInput(slot) end)
    addBtn:Hide()
    row.addBtn = addBtn

    local removeBtn = UI.CreateRemoveButton(row)
    removeBtn:SetPoint("RIGHT", row, "RIGHT")
    removeBtn:SetScript("OnClick", function() ns.RemoveFinder(removeBtn.targetSlot or slot) end)
    removeBtn:Hide()
    row.removeBtn = removeBtn
end

local function buildSlotRow(parent, slot)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(UI.Size.row)
    local top = -UI.Space.padding - (slot - 1) * UI.Size.row
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.Space.padding, top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.Space.padding, top)

    local index = UI.CreateText(row, "body")
    index:SetPoint("LEFT", row, "LEFT")
    index:SetWidth(INDEX_WIDTH)
    index:SetJustifyH("RIGHT")
    index:SetText(slot .. ".")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(UI.Size.icon, UI.Size.icon)
    icon:SetPoint("LEFT", index, "RIGHT", UI.Space.gap, 0)
    icon:Hide()
    row.icon = icon

    buildRowButtons(row, slot)
    row.input = buildSlotInput(row, slot)
    row.updateState = function() layoutTrailing(row, slot) end
    ns.AttachAutocomplete(row.input, row.updateState)

    row.updateState()
    return row
end

-- Blizzard's tooltip helpers carry the standard tooltip colours; the error line says why the button is off.
local function fillNearbyTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, NEARBY_LABEL)
    GameTooltip_AddNormalLine(tooltip, NEARBY_HELP)
    if not ns.QuestieReady() then
        GameTooltip_AddErrorLine(tooltip, ns.QuestieExcuse())
    end
end

-- The primary action takes the bottom-right corner and Clear chains to its left.
local function buildButtonBar(frame)
    local nearbyButton = UI.AddBarButton(frame, NEARBY_LABEL, function() ns.AddNearbyQuestNpcs() end, NEARBY_WIDTH)

    -- Motion scripts stay alive while disabled, so the tooltip can still explain what is missing.
    nearbyButton:SetMotionScriptsWhileDisabled(true)
    UI.AttachTooltip(nearbyButton, fillNearbyTooltip)
    frame.nearbyButton = nearbyButton

    frame.clearButton = UI.AddBarButton(frame, CLEAR_LABEL, function() ns.ClearFinder() end)
end

-- Help text in the attic, the band between the title bar and the Inset, beside the portrait and centred on the band's height. Its right edge lines up with the rows below.
local function buildAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    local helper = UI.CreateText(frame, "body")
    helper:SetPoint("LEFT", frame, "TOPLEFT", ATTIC_LEFT, atticMiddle)
    helper:SetPoint("RIGHT", frame, "TOPRIGHT", PANEL_INSET_RIGHT_OFFSET - UI.Space.padding, atticMiddle)
    helper:SetWordWrap(true)
    helper:SetText(PANEL_HELP)
end

-- The window's height follows the template's own attic and button bar offsets around the padded rows.
local function panelHeight()
    local contentHeight = UI.Space.padding * 2 + MAX_TARGETS * UI.Size.row
    return -PANEL_INSET_ATTIC_OFFSET + contentHeight + PANEL_INSET_BOTTOM_BUTTON_OFFSET
end

local function buildPanel()
    panel = UI.CreateWindow({
        name = PANEL_NAME,
        title = ns.ADDON_NAME,
        icon = ns.ADDON_ICON,
        width = PANEL_WIDTH,
        height = panelHeight(),
    })
    panel:SetScript("OnShow", function() ns.RefreshPanel() end)

    buildAtticHelp(panel)

    panel.rows = {}
    for slot = 1, MAX_TARGETS do
        panel.rows[slot] = buildSlotRow(panel.Inset, slot)
    end

    buildButtonBar(panel)
    return panel
end

function ns.RefreshPanel()
    if not panel then return end
    panel.nearbyButton:SetEnabled(ns.QuestieReady())
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local entry = ns.targets[slot]
        if not row.input:HasFocus() then
            row.input:SetText(entry and entry.name or "")
            row.input:SetCursorPosition(0)
        end
        if entry then
            showMarkerTexture(row.icon, ns.FIND_MARKERS[slot])
        else
            row.icon:Hide()
        end
        row.updateState()
    end
end

-- The minimap button, the addon menu and /tf share this one toggle.
ns.TogglePanel = UI.CreateToggle(buildPanel)

UI.RegisterSlash("TARGETFINDER", { "/tf", "/targetfinder" }, ns.TogglePanel)
