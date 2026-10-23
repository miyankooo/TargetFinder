local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- The autocomplete popup under a slot row. It owns nothing but presentation: every name it offers comes from Quest.lua, and picking one goes straight back through the row's own apply path.

-- One shared popup built like Blizzard's own AutoCompleteBox (Blizzard_AutoComplete/AutoComplete.xml): a TooltipBackdropTemplate box, AutoCompleteButtonTemplate rows and a grey "Press Tab" hint. Blizzard's box itself is never borrowed, because the chat edit boxes share it and addon writes to it would taint them.
local POPUP_NAME = "TargetFinderSuggestions"
local MAX_SUGGESTIONS = ns.MAX_SUGGESTIONS

-- Blizzard's AutoCompleteBox geometry moved onto the 4px grid: its 14px rows (AutoComplete.xml:17) become 16 so the 16px role icon fits, the 15px text inset (:21) 16, the 10px first-row and hint offsets (:52, :40) 8, the 35px chrome (AutoComplete.lua:296) 36 and the 3px edit-box overlap (AutoComplete.lua:130) 4.
local ROW_HEIGHT = 16
local TEXT_INSET = 16
local ROWS_TOP = UI.Space.gap
local HINT_BOTTOM = UI.Space.gap

-- 8 above the rows, 8 between the rows and the 12px hint line, 8 below it.
local CHROME = 36
local OVERLAP = 4

-- Role icons come before the name, one gap clear of it.
local NAME_INSET = TEXT_INSET + UI.Size.icon + UI.Space.gap

local QUEST_LABEL = "[Quest] "

local popup

local function isOpenFor(input)
    return popup ~= nil and popup:IsShown() and popup.owner == input
end

local function hidePopup(input)
    if isOpenFor(input) then popup:Hide() end
end

ns.HideSuggestions = hidePopup

-- LockHighlight is how AutoComplete_SetSelectedIndex marks the keyboard choice, so the selected row looks exactly like a hovered one.
local function setSelection(index)
    popup.selected = index
    for i = 1, MAX_SUGGESTIONS do
        local row = popup.rows[i]
        if i == index then row:LockHighlight() else row:UnlockHighlight() end
    end
end

local function moveSelection(input, delta)
    if not isOpenFor(input) then return false end
    local count = popup.count or 0
    if count == 0 then return false end
    local nextIndex = (popup.selected or 0) + delta
    if nextIndex < 1 then
        nextIndex = count
    elseif nextIndex > count then
        nextIndex = 1
    end
    setSelection(nextIndex)
    return true
end

local function activate(input, entry)
    if not entry then return end
    if entry.type == "quest" then
        input:SetText(input.tfStored or "")
        input:ClearFocus()
        hidePopup(input)
        ns.TrackQuest(entry.questId)
        return
    end
    local picked = entry.name
    if not picked or picked == "" then return end
    input:SetText(picked)
    hidePopup(input)
    ns.ApplyRowInput(input.slot)
end

-- Enter takes the keyboard selection when there is one; with nothing to select the typed text applies unchanged.
function ns.TakeSelectedSuggestion(input)
    if not isOpenFor(input) then return false end
    local index = popup.selected or 0
    local row = index > 0 and popup.rows[index]
    if not row or not row:IsShown() or not row.entry then return false end
    activate(input, row.entry)
    return true
end

-- Blizzard's AutoComplete preselects a row so Enter takes a whole name, which FIND needs because it matches names exactly. The NPC whose name the player typed in full wins, otherwise the first NPC row. A quest row is never preselected, because it fills several rows at once.
local function defaultSelection(typed)
    local wanted = typed:lower()
    local first = 0
    for i = 1, popup.count do
        local entry = popup.rows[i].entry
        if entry.type == "npc" then
            if entry.name:lower() == wanted then return i end
            if first == 0 then first = i end
        end
    end
    return first
end

-- The template anchors its text 15px in and lets it run on; here it starts on the grid and stops at the right edge so a long quest name truncates instead of spilling past the border. Rows are named because the template's ButtonText is "$parentText".
local function buildRow(parent, name)
    local row = CreateFrame("Button", name, parent, "AutoCompleteButtonTemplate")
    row:SetHeight(ROW_HEIGHT)
    local text = row:GetFontString()
    text:ClearAllPoints()
    text:SetPoint("LEFT", row, "LEFT", TEXT_INSET, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -TEXT_INSET, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return row
end

-- Full-width rows stacked under each other, the first one ROWS_TOP below the border like AutoCompleteButton1.
local function stackRow(row, above)
    row:ClearAllPoints()
    if above == popup then
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -ROWS_TOP)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -ROWS_TOP)
    else
        row:SetPoint("TOPLEFT", above, "BOTTOMLEFT")
        row:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT")
    end
end

local function buildQuestIcon(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(UI.Size.icon, UI.Size.icon)
    icon:SetPoint("LEFT", row, "LEFT", TEXT_INSET, 0)
    icon:Hide()
    row.icon = icon
    row:GetFontString():SetPoint("LEFT", row, "LEFT", NAME_INSET, 0)
end

local function buildPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", POPUP_NAME, UIParent, "TooltipBackdropTemplate")
    popup:EnableMouse(true)
    popup:Hide()

    -- The popup is parented to whichever edit box owns it, so closing the panel hides it too; clearing the shown flag here stops it reappearing when the panel reopens.
    popup:SetScript("OnHide", function(self) self:Hide() end)

    popup.rows = {}
    local above = popup
    for i = 1, MAX_SUGGESTIONS do
        local row = buildRow(popup, POPUP_NAME .. "Button" .. i)
        stackRow(row, above)
        buildQuestIcon(row)
        row:SetScript("OnClick", function(self) activate(popup.owner, self.entry) end)
        popup.rows[i] = row
        above = row
    end

    -- AutoComplete_OnLoad tints this hint with a literal light grey; LIGHTGRAY_FONT_COLOR is the colour object for that shade. It uses the 12px muted role, not Blizzard's 10px hint font.
    local hint = UI.CreateText(popup, "muted")
    hint:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", TEXT_INSET, HINT_BOTTOM)
    hint:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(PRESS_TAB))

    return popup
end

local function entryText(entry)
    if entry.type == "quest" then return QUEST_LABEL .. entry.name end
    if entry.isQuestNpc and entry.questName then
        return entry.name .. " " .. UI.Color.muted:WrapTextInColorCode("(" .. entry.questName .. ")")
    end
    return entry.name
end

local function fillRow(row, entry, icons)
    row.entry = entry
    row:SetText(entryText(entry))
    local iconPath = icons and entry.type == "npc" and entry.kind and icons[entry.kind]
    if iconPath then
        row.icon:SetTexture(iconPath)
        row.icon:Show()
    else
        row.icon:Hide()
    end
    row:Show()
end

-- AutoComplete_Update's rule: open below the edit box, or above it when the box would run off the bottom of the screen.
local function anchorTo(input, height)
    popup:SetParent(input)
    popup:SetFrameStrata(UI.Strata.dialog)
    popup:ClearAllPoints()
    local bottom = input:GetBottom()
    if bottom and bottom - height <= OVERLAP + ROWS_TOP then
        popup:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 0, -OVERLAP)
        popup:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, -OVERLAP)
    else
        popup:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, OVERLAP)
        popup:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, OVERLAP)
    end
end

local function showSuggestions(input, list, typed)
    buildPopup()
    local count = math.min(#list, MAX_SUGGESTIONS)
    if count == 0 then
        hidePopup(input)
        return
    end
    popup.owner = input
    popup.count = count
    local icons = ns.QuestieKindIcons()
    for i = 1, MAX_SUGGESTIONS do
        local row = popup.rows[i]
        if i <= count then
            fillRow(row, list[i], icons)
        else
            row.entry = nil
            row:Hide()
        end
    end
    setSelection(defaultSelection(typed))

    local height = count * ROW_HEIGHT + CHROME
    popup:SetHeight(height)
    anchorTo(input, height)
    popup:Show()
end

-- The highlighted row, or with nothing highlighted the first NPC row, since a quest row has no single name to complete.
local function completionEntry()
    local selected = popup.selected or 0
    if selected > 0 then
        local entry = popup.rows[selected].entry
        return entry and entry.type == "npc" and entry or nil
    end
    for i = 1, popup.count or 0 do
        local entry = popup.rows[i].entry
        if entry and entry.type == "npc" then return entry end
    end
    return nil
end

-- Tab completes a name into the box without storing it, which is what the "Press Tab" hint promises.
local function completeSelection(input)
    if not isOpenFor(input) then return end
    local entry = completionEntry()
    if not entry then return end
    local picked = entry.name
    if not picked or picked == "" then return end
    input:SetText(picked)
    input:SetCursorPosition(#picked)
    hidePopup(input)
end

function ns.AttachAutocomplete(input, onChange)
    -- Keep arrow keys inside the edit box so OnArrowPressed fires at all, the way Blizzard's own AutoComplete does.
    input:SetAltArrowKeyMode(false)
    input:SetScript("OnArrowPressed", function(self, key)
        if key == "UP" then
            return moveSelection(self, -1)
        elseif key == "DOWN" then
            return moveSelection(self, 1)
        end
    end)
    input:SetScript("OnTextChanged", function(self, userInput)
        if onChange then onChange() end
        if not userInput then return end
        local typed = ns.Trim(self:GetText())
        if not typed or #typed < ns.MIN_QUERY_LENGTH then
            hidePopup(self)
            return
        end
        showSuggestions(self, ns.FindSuggestions(typed), typed)
    end)
    -- A click on a suggestion drops focus before the click resolves, so the hide waits out the click.
    input:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0.15, function() hidePopup(self) end)
    end)
    input:SetScript("OnTabPressed", completeSelection)
end
