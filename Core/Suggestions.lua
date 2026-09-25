local _, ns = ...

-- The autocomplete popup under a slot row. It owns nothing but presentation: every name it offers comes from Quest.lua, and picking one goes straight back through the row's own apply path.

-- One shared popup built like Blizzard's own AutoCompleteBox (Blizzard_AutoComplete/AutoComplete.xml, identical layout on 1.15.9 and 1.60.1): a TooltipBackdropTemplate box, AutoCompleteButtonTemplate rows and a grey "Press Tab" hint. Both templates resolve to each client's own art. Blizzard's box itself is never borrowed, because the chat edit boxes share it and addon writes to it would taint them.
local POPUP_NAME = "TargetFinderSuggestions"
local MAX_SUGGESTIONS = ns.MAX_SUGGESTIONS

-- AutoComplete.xml geometry: 14px rows starting 10px below the top, 35px of vertical chrome, text inset 15px, anchored 3px into the edit box.
local ROW_HEIGHT = 14
local ROWS_TOP = 10
local CHROME_HEIGHT = 35
local TEXT_INSET = 15
local ANCHOR_OVERLAP = 3
local ICON_SIZE = 12
local ICON_GAP = 2

local QUEST_LABEL = "[Quest] "
local QUEST_SUFFIX_COLOR = "|cff808080"
local HINT_COLOR = "|cffbbbbbb"
local COLOR_END = "|r"
local ADD_ALL_TEXT = "Add All"

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
        local picks = ns.QuestNpcs(entry.questId)
        if not picks or #picks == 0 then
            ns.Announce("No NPCs found for that quest.")
            return
        end
        input:SetText(input.tfStored or "")
        input:ClearFocus()
        hidePopup(input)
        ns.AddFinderBatch(picks)
        return
    end
    local picked = entry.name
    if not picked or picked == "" then return end
    input:SetText(picked)
    hidePopup(input)
    if ns.ApplyRowInput and input.slot then
        ns.ApplyRowInput(input.slot)
    end
end

-- Enter takes the keyboard selection when there is one, so plain typed text still applies unchanged. Blizzard preselects row 1; this popup does not, because Enter on a typed prefix must store the prefix.
function ns.TakeSelectedSuggestion(input)
    if not isOpenFor(input) then return false end
    local index = popup.selected or 0
    local row = index > 0 and popup.rows[index]
    if not row or not row:IsShown() or not row.entry then return false end
    activate(input, row.entry)
    return true
end

local function queueEntry(picks, seen, name, kind)
    if name and name ~= "" and not seen[name] then
        seen[name] = true
        picks[#picks + 1] = { name = name, kind = kind }
    end
end

local function addAllShown(input)
    if not isOpenFor(input) then
        ns.Announce("No suggestions to add.")
        return
    end
    local picks = {}
    local seen = {}
    for i = 1, popup.count or 0 do
        local entry = popup.rows[i].entry
        if entry and entry.type == "quest" then
            for _, questEntry in ipairs(ns.QuestNpcs(entry.questId)) do
                queueEntry(picks, seen, questEntry.name, questEntry.kind)
            end
        elseif entry then
            queueEntry(picks, seen, entry.name, entry.kind)
        end
    end
    if #picks == 0 then
        ns.Announce("No suggestions to add.")
        return
    end
    input:SetText("")
    input:ClearFocus()
    hidePopup(input)
    ns.AddFinderBatch(picks)
end

-- The template anchors its text 15px in and lets it run on; here it also stops at the right edge so a long quest name truncates instead of spilling past the border. Rows are named because the template's ButtonText is "$parentText".
local function buildRow(parent, name)
    local row = CreateFrame("Button", name, parent, "AutoCompleteButtonTemplate")
    local text = row:GetFontString()
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
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", TEXT_INSET, 0)
    icon:Hide()
    row.icon = icon
    row:GetFontString():SetPoint("LEFT", row, "LEFT", TEXT_INSET + ICON_SIZE + ICON_GAP, 0)
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

    -- White text marks the footer as an action rather than one more gold name.
    local addAll = buildRow(popup, POPUP_NAME .. "AddAll")
    addAll:SetNormalFontObject(GameFontHighlight)
    addAll:SetText(ADD_ALL_TEXT)
    addAll:SetScript("OnClick", function() addAllShown(popup.owner) end)
    popup.addAll = addAll

    local hint = popup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", TEXT_INSET, 10)
    hint:SetText(HINT_COLOR .. PRESS_TAB .. COLOR_END)

    return popup
end

local function entryText(entry)
    if entry.type == "quest" then return QUEST_LABEL .. entry.name end
    if entry.isQuestNpc and entry.questName then
        return entry.name .. " " .. QUEST_SUFFIX_COLOR .. "(" .. entry.questName .. ")" .. COLOR_END
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
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:ClearAllPoints()
    local bottom = input:GetBottom()
    if bottom and bottom - height <= ANCHOR_OVERLAP + ROWS_TOP then
        popup:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 0, -ANCHOR_OVERLAP)
        popup:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, -ANCHOR_OVERLAP)
    else
        popup:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, ANCHOR_OVERLAP)
        popup:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, ANCHOR_OVERLAP)
    end
end

local function showSuggestions(input, list)
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
    setSelection(0)
    stackRow(popup.addAll, popup.rows[count])

    local height = (count + 1) * ROW_HEIGHT + CHROME_HEIGHT
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
        showSuggestions(self, ns.FindSuggestions(typed))
    end)
    -- A click on a suggestion drops focus before the click resolves, so the hide waits out the click.
    input:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0.15, function() hidePopup(self) end)
    end)
    input:SetScript("OnTabPressed", completeSelection)
end
