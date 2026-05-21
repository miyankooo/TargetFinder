local addonName = ...

local ADDON_NAME = "TargetFinder"
local YELLOW = "|cffffff00"
local COLOR_END = "|r"

local FIND_MACRO = "FIND"
local FIND_ICON = "Ability_Hunter_SniperShot"
local FIND_MARKERS = { 8, 6, 2, 1, 7, 4, 3, 5 }
local MAX_TARGETS = 8
local ACTION_SLOTS = 72
local GLOW_SECONDS = 4
local MARK_THROTTLE = 0.15

local MINIMAP_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
local MINIMAP_DEFAULT_POS = 215

local KIND_KILL = 1
local KIND_DROP = 2
local KIND_GIVER = 3

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

-- Each slot holds { name = string, kind = KIND_* }. Manual adds default to KIND_GIVER.
local findTargets = {}

local function makeEntry(name, kind)
    return { name = name, kind = kind or KIND_GIVER }
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
    for slot, entry in ipairs(findTargets) do
        if lowered:find(entry.name:lower(), 1, true) then
            applySlotMarker(slot)
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

-- Macro body mirrors RXPGuides: one /target per slot, in REVERSE so slot 1 lands
-- on the last line and wins. /target is a no-op on no match, so spamming the
-- macro never clears the current target. /targetlasttarget [dead] swaps back to
-- the previous target when the current one dies. On overflow (Classic Era's
-- 255-char macro cap), the lowest-priority lines drop off the top.
local MACRO_LIMIT = 255
local LAST_TARGET_LINE = "/targetlasttarget [dead]"

local function buildFindBody(targets)
    if #targets == 0 then return "/cleartarget" end
    local lines = {}
    for i = #targets, 1, -1 do
        lines[#lines + 1] = "/target " .. targets[i].name
    end
    lines[#lines + 1] = LAST_TARGET_LINE
    local body = table.concat(lines, "\n")
    while #body > MACRO_LIMIT and #lines > 1 do
        table.remove(lines, 1)
        body = table.concat(lines, "\n")
    end
    return body
end

local refreshPanel

local function writeFinderMacro(targets)
    findTargets = targets
    if TargetFinderCharDB then TargetFinderCharDB.targets = targets end
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

local function markNearbyForSlot(slot)
    local entry = findTargets[slot]
    if not entry or not entry.name then return 0 end
    local lower = entry.name:lower()
    local marker = FIND_MARKERS[slot]
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and name:lower():find(lower, 1, true) then
                SetRaidTarget(unit, marker)
                count = count + 1
            end
        end
    end
    return count
end

local function entryNames(entries)
    local out = {}
    for i, entry in ipairs(entries) do out[i] = entry.name end
    return out
end

local function setFinder(name, kind)
    if not name then
        announce("No target selected.")
        return
    end
    writeFinderMacro({ makeEntry(name, kind) })
    applySlotMarker(1)
    local count = markNearbyForSlot(1)
    local suffix = count > 0 and " — " .. count .. " marked" or ""
    announce(name .. suffix)
    hintMacro(FIND_MACRO)
end

local function addFinder(name, kind)
    if not name then
        announce("No target selected.")
        return
    end
    local targets = findTargets
    for _, existing in ipairs(targets) do
        if existing.name == name then
            announce(name .. " is already tracked.")
            return
        end
    end
    if #targets >= MAX_TARGETS then
        announce("Finder is full: " .. table.concat(entryNames(targets), ", ") .. ".")
        return
    end
    table.insert(targets, makeEntry(name, kind))
    writeFinderMacro(targets)
    local slot = #targets
    applySlotMarker(slot)
    local count = markNearbyForSlot(slot)
    local suffix = count > 0 and " — " .. count .. " marked" or ""
    announce(table.concat(entryNames(targets), ", ") .. suffix)
    hintMacro(FIND_MACRO)
end

local function addFinderBatch(items)
    if type(items) ~= "table" or #items == 0 then
        announce("Nothing to add.")
        return
    end
    local targets = findTargets
    local existing = {}
    for _, t in ipairs(targets) do existing[t.name] = true end

    local added = {}
    for _, item in ipairs(items) do
        if #targets >= MAX_TARGETS then break end
        local name, kind = item.name, item.kind
        if name and name ~= "" and not existing[name] then
            table.insert(targets, makeEntry(name, kind))
            existing[name] = true
            added[#added + 1] = name
        end
    end

    if #added == 0 then
        announce("Already tracking everything from that list.")
        return
    end

    local firstNewSlot = #targets - #added + 1
    writeFinderMacro(targets)
    local marked = 0
    for slot = firstNewSlot, #targets do
        applySlotMarker(slot)
        marked = marked + markNearbyForSlot(slot)
    end
    local suffix = marked > 0 and " — " .. marked .. " marked" or ""
    announce(table.concat(added, ", ") .. suffix)
    hintMacro(FIND_MACRO)
end

local function removeFinder(slot)
    local removed = findTargets[slot]
    if not removed then return end
    table.remove(findTargets, slot)
    writeFinderMacro(findTargets)
    announce("Removed: " .. removed.name)
end

local function clearFinder()
    if #findTargets == 0 then
        announce("Finder is empty.")
        return
    end
    writeFinderMacro({})
    announce("Finder cleared.")
end

local panel

local MAX_SUGGESTIONS = 8
local SUGGESTION_ROW_HEIGHT = 16
local SUGGESTION_ICON_SIZE = 14
local MIN_QUERY_LENGTH = 2

local QuestieDB
local QuestiePlayer
local npcNames
local npcNamesLower

local function loadQuestieDB()
    if QuestieDB then return true end
    local loader = _G.QuestieLoader
    if not loader then return false end
    QuestieDB = loader:ImportModule("QuestieDB")
    QuestiePlayer = loader:ImportModule("QuestiePlayer")
    return QuestieDB ~= nil
end

local questieKindIcons

local function getQuestieKindIcons()
    if questieKindIcons then return questieKindIcons end
    local Q = _G.Questie
    if not Q or not Q.usedIcons then return nil end
    questieKindIcons = {
        [KIND_KILL] = Q.usedIcons[Q.ICON_TYPE_SLAY],
        [KIND_DROP] = Q.usedIcons[Q.ICON_TYPE_LOOT],
        [KIND_GIVER] = Q.usedIcons[Q.ICON_TYPE_AVAILABLE],
    }
    return questieKindIcons
end

local function buildNpcNameIndex()
    if npcNames then return true end
    if not loadQuestieDB() then return false end
    if not QuestieDB.NPCPointers or not QuestieDB.QueryNPCSingle then return false end
    local seen = {}
    local list = {}
    for npcId in pairs(QuestieDB.NPCPointers) do
        local name = QuestieDB.QueryNPCSingle(npcId, "name")
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    table.sort(list)
    npcNames = list
    npcNamesLower = {}
    for i = 1, #list do
        npcNamesLower[i] = list[i]:lower()
    end
    return true
end

local function forEachNpcInQuest(questId, visit)
    if not QuestieDB then return end
    local quest = QuestieDB.GetQuest and QuestieDB.GetQuest(questId)
    local objectiveData = quest and quest.ObjectiveData
    local liveObjs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questId)

    if objectiveData then
        for index, data in ipairs(objectiveData) do
            local live = liveObjs and liveObjs[index]
            if not (live and live.finished) then
                if data.Type == "monster" and data.Id then
                    visit(data.Id, KIND_KILL)
                elseif data.Type == "killcredit" and data.IdList then
                    for _, id in ipairs(data.IdList) do visit(id, KIND_KILL) end
                elseif data.Type == "item" and data.Id then
                    local droppers = QuestieDB.QueryItemSingle(data.Id, "npcDrops")
                    if droppers then
                        for _, dropperId in ipairs(droppers) do visit(dropperId, KIND_DROP) end
                    end
                end
            end
        end
    end

    local startedBy = QuestieDB.QueryQuestSingle(questId, "startedBy")
    if startedBy and startedBy[1] then
        for _, id in ipairs(startedBy[1]) do visit(id, KIND_GIVER) end
    end
    local finishedBy = QuestieDB.QueryQuestSingle(questId, "finishedBy")
    if finishedBy and finishedBy[1] then
        for _, id in ipairs(finishedBy[1]) do visit(id, KIND_GIVER) end
    end
end

local function getQuestNpcs(questId)
    if not loadQuestieDB() then return {} end
    local seen = {}
    local entries = {}
    forEachNpcInQuest(questId, function(npcId, kind)
        if not npcId then return end
        local name = QuestieDB.QueryNPCSingle(npcId, "name")
        if not name or name == "" then return end
        local existing = seen[name]
        if not existing then
            entries[#entries + 1] = { name = name, kind = kind, order = #entries + 1 }
            seen[name] = entries[#entries]
        elseif kind < existing.kind then
            existing.kind = kind
        end
    end)
    table.sort(entries, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.order < b.order
    end)
    return entries
end

local function collectQuestNpcNames()
    if not QuestiePlayer or not QuestiePlayer.currentQuestlog then return nil end
    local seen = {}
    local names = {}
    for questId in pairs(QuestiePlayer.currentQuestlog) do
        local questName = QuestieDB.QueryQuestSingle(questId, "name")
        forEachNpcInQuest(questId, function(npcId, kind)
            if not npcId then return end
            local name = QuestieDB.QueryNPCSingle(npcId, "name")
            if not name or name == "" then return end
            local existing = seen[name]
            if not existing then
                local entry = { name = name, questName = questName, kind = kind, order = #names + 1 }
                seen[name] = entry
                names[#names + 1] = entry
            elseif kind < existing.kind then
                existing.kind = kind
                existing.questName = questName
            end
        end)
    end
    table.sort(names, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.order < b.order
    end)
    return names
end

local function getPlayerAreaAndCoords()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil end
    local loader = _G.QuestieLoader
    local ZoneDB = loader and loader:ImportModule("ZoneDB")
    if not ZoneDB or not ZoneDB.GetAreaIdByUiMapId then return nil end
    local areaId = ZoneDB:GetAreaIdByUiMapId(uiMapId)
    if not areaId then return nil end
    local pos = C_Map.GetPlayerMapPosition(uiMapId, "player")
    if not pos then return areaId end
    return areaId, pos.x * 100, pos.y * 100
end

local function collectNearbyQuestNpcs()
    if not loadQuestieDB() then return nil end
    local areaId, px, py = getPlayerAreaAndCoords()
    if not areaId then return nil end
    if not QuestiePlayer or not QuestiePlayer.currentQuestlog then return nil end

    local seen = {}
    local entries = {}
    local function visit(npcId, kind)
        if not npcId then return end
        local name = QuestieDB.QueryNPCSingle(npcId, "name")
        if not name or name == "" then return end
        local spawns = QuestieDB.QueryNPCSingle(npcId, "spawns")
        if not spawns then return end
        local zoneSpawns = spawns[areaId]
        if not zoneSpawns then return end

        local best = math.huge
        if px and py then
            for _, coord in ipairs(zoneSpawns) do
                local dx, dy = coord[1] - px, coord[2] - py
                local d = dx * dx + dy * dy
                if d < best then best = d end
            end
        else
            best = 0
        end

        local existing = seen[name]
        if not existing then
            entries[#entries + 1] = { name = name, dist = best, kind = kind }
            seen[name] = entries[#entries]
        else
            if kind < existing.kind then existing.kind = kind end
            if best < existing.dist then existing.dist = best end
        end
    end

    for questId in pairs(QuestiePlayer.currentQuestlog) do
        local complete = QuestieDB.IsComplete and QuestieDB.IsComplete(questId) == 1
        if complete then
            -- Turn-in givers only; quest is ready to hand in.
            local finishedBy = QuestieDB.QueryQuestSingle(questId, "finishedBy")
            if finishedBy and finishedBy[1] then
                for _, id in ipairs(finishedBy[1]) do visit(id, KIND_GIVER) end
            end
        else
            -- Active quest: kill targets and item droppers only.
            -- startedBy is moot (already accepted); finishedBy isn't actionable yet.
            local quest = QuestieDB.GetQuest and QuestieDB.GetQuest(questId)
            local objectiveData = quest and quest.ObjectiveData
            local liveObjs = C_QuestLog and C_QuestLog.GetQuestObjectives
                and C_QuestLog.GetQuestObjectives(questId)
            if objectiveData then
                for index, data in ipairs(objectiveData) do
                    local live = liveObjs and liveObjs[index]
                    if not (live and live.finished) then
                        if data.Type == "monster" and data.Id then
                            visit(data.Id, KIND_KILL)
                        elseif data.Type == "killcredit" and data.IdList then
                            for _, id in ipairs(data.IdList) do visit(id, KIND_KILL) end
                        elseif data.Type == "item" and data.Id then
                            local droppers = QuestieDB.QueryItemSingle(data.Id, "npcDrops")
                            if droppers then
                                for _, dropperId in ipairs(droppers) do visit(dropperId, KIND_DROP) end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Closest 8 first, then sort that subset by priority (kind asc, distance tiebreak).
    table.sort(entries, function(a, b) return a.dist < b.dist end)
    local top = {}
    for i = 1, math.min(#entries, MAX_TARGETS) do top[i] = entries[i] end
    table.sort(top, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.dist < b.dist
    end)
    return top
end

local function findSuggestions(query)
    if not buildNpcNameIndex() then return {} end
    local q = query:lower()
    local qLen = #q
    local results = {}
    local picked = {}
    local questPicked = {}

    if QuestiePlayer and QuestiePlayer.currentQuestlog then
        for questId in pairs(QuestiePlayer.currentQuestlog) do
            local questName = QuestieDB.QueryQuestSingle(questId, "name")
            if questName and not questPicked[questId] and questName:lower():find(q, 1, true) then
                results[#results + 1] = { type = "quest", name = questName, questId = questId }
                questPicked[questId] = true
                if #results >= MAX_SUGGESTIONS then return results end
            end
        end
    end

    local questNpcs = collectQuestNpcNames()
    if questNpcs then
        for i = 1, #questNpcs do
            local entry = questNpcs[i]
            if not picked[entry.name] and entry.name:lower():find(q, 1, true) then
                results[#results + 1] = {
                    type = "npc",
                    name = entry.name,
                    questName = entry.questName,
                    isQuestNpc = true,
                    kind = entry.kind,
                }
                picked[entry.name] = true
                if #results >= MAX_SUGGESTIONS then return results end
            end
        end
    end

    for i = 1, #npcNamesLower do
        local lname = npcNamesLower[i]
        if lname:sub(1, qLen) == q and not picked[npcNames[i]] then
            results[#results + 1] = { type = "npc", name = npcNames[i] }
            picked[npcNames[i]] = true
            if #results >= MAX_SUGGESTIONS then return results end
        end
    end

    for i = 1, #npcNamesLower do
        local lname = npcNamesLower[i]
        if lname:sub(1, qLen) ~= q and lname:find(q, 1, true) and not picked[npcNames[i]] then
            results[#results + 1] = { type = "npc", name = npcNames[i] }
            picked[npcNames[i]] = true
            if #results >= MAX_SUGGESTIONS then return results end
        end
    end

    return results
end

local function hideSuggestions(input)
    if input.qtPopup then input.qtPopup:Hide() end
end

local function buildSuggestionPopup(input)
    if input.qtPopup then return input.qtPopup end
    local parent = input:GetParent()
    local pop = CreateFrame("Frame", nil, parent, "TooltipBorderedFrameTemplate")
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -4)
    pop:SetWidth(parent:GetWidth() - 28)
    pop:Hide()

    pop.rows = {}
    for i = 1, MAX_SUGGESTIONS do
        local row = CreateFrame("Button", nil, pop)
        row:SetHeight(SUGGESTION_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", pop, "TOPLEFT", 6, -6)
            row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -6)
        else
            row:SetPoint("TOPLEFT", pop.rows[i - 1], "BOTTOMLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", pop.rows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(true)
        highlight:SetColorTexture(1, 1, 1, 0.15)
        highlight:Hide()
        row.highlight = highlight

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(SUGGESTION_ICON_SIZE, SUGGESTION_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:Hide()
        row.icon = icon

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text

        row:SetScript("OnEnter", function() highlight:Show() end)
        row:SetScript("OnLeave", function() highlight:Hide() end)
        row:SetScript("OnClick", function()
            local entry = row.entry
            if not entry then return end
            if entry.type == "quest" then
                local picks = getQuestNpcs(entry.questId)
                if not picks or #picks == 0 then
                    announce("No NPCs found for that quest.")
                    return
                end
                input:SetText("")
                input:ClearFocus()
                hideSuggestions(input)
                addFinderBatch(picks)
                return
            end
            local picked = entry.name
            if not picked or picked == "" then return end
            input:SetText(picked)
            input:SetCursorPosition(#picked)
            pop:Hide()
            input:SetFocus()
        end)

        pop.rows[i] = row
    end

    local footer = CreateFrame("Button", nil, pop)
    footer:SetHeight(SUGGESTION_ROW_HEIGHT)
    local footerHl = footer:CreateTexture(nil, "BACKGROUND")
    footerHl:SetAllPoints(true)
    footerHl:SetColorTexture(1, 1, 1, 0.15)
    footerHl:Hide()
    local footerText = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footerText:SetPoint("CENTER", footer, "CENTER", 0, 0)
    footerText:SetText("Add All")
    footerText:SetTextColor(0.4, 0.85, 1)
    footer:SetScript("OnEnter", function() footerHl:Show() end)
    footer:SetScript("OnLeave", function() footerHl:Hide() end)
    footer:SetScript("OnClick", function() addAllFromSuggestions(input) end)
    pop.footer = footer

    input.qtPopup = pop
    return pop
end

local function showSuggestions(input, list)
    local pop = buildSuggestionPopup(input)
    local count = math.min(#list, MAX_SUGGESTIONS)
    if count == 0 then
        pop:Hide()
        return
    end
    local icons = getQuestieKindIcons()
    for i = 1, MAX_SUGGESTIONS do
        local row = pop.rows[i]
        if i <= count then
            local entry = list[i]
            row.entry = entry
            local iconPath = icons and entry.type == "npc" and entry.kind and icons[entry.kind]
            if iconPath then
                row.icon:SetTexture(iconPath)
                row.icon:Show()
            else
                row.icon:Hide()
            end
            if entry.type == "quest" then
                row.text:SetText("|cffffd200[Quest]|r " .. entry.name)
                row.text:SetTextColor(1, 1, 1)
            elseif entry.isQuestNpc then
                local suffix = entry.questName and " |cffaaaaaa(" .. entry.questName .. ")|r" or ""
                row.text:SetText(entry.name .. suffix)
                row.text:SetTextColor(1, 0.82, 0)
            else
                row.text:SetText(entry.name)
                row.text:SetTextColor(1, 1, 1)
            end
            row.highlight:Hide()
            row:Show()
        else
            row:Hide()
        end
    end
    local lastVisible = pop.rows[count]
    pop.footer:ClearAllPoints()
    pop.footer:SetPoint("TOPLEFT", lastVisible, "BOTTOMLEFT", 0, -3)
    pop.footer:SetPoint("TOPRIGHT", lastVisible, "BOTTOMRIGHT", 0, -3)
    pop.footer:Show()
    pop:SetHeight(12 + count * SUGGESTION_ROW_HEIGHT + SUGGESTION_ROW_HEIGHT + 3)
    pop:Show()
end

local function attachAutocomplete(input)
    input:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local typed = trim(self:GetText())
        if not typed or #typed < MIN_QUERY_LENGTH then
            hideSuggestions(self)
            return
        end
        showSuggestions(self, findSuggestions(typed))
    end)
    input:SetScript("OnEditFocusLost", function(self)
        C_Timer.After(0.15, function() hideSuggestions(self) end)
    end)
    input:SetScript("OnTabPressed", function(self)
        local pop = self.qtPopup
        if not pop or not pop:IsShown() then return end
        local first = pop.rows[1]
        if not first or not first:IsShown() then return end
        local entry = first.entry
        if not entry or entry.type ~= "npc" then return end
        local picked = entry.name
        if not picked or picked == "" then return end
        self:SetText(picked)
        self:SetCursorPosition(#picked)
        hideSuggestions(self)
    end)
end

local function addAllFromSuggestions(input)
    local pop = input.qtPopup
    if not pop or not pop:IsShown() then
        announce("No suggestions to add.")
        return
    end
    local picks = {}
    local seen = {}
    local function queue(name, kind)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            picks[#picks + 1] = { name = name, kind = kind }
        end
    end
    for i = 1, MAX_SUGGESTIONS do
        local row = pop.rows[i]
        if row:IsShown() and row.entry then
            local entry = row.entry
            if entry.type == "quest" then
                for _, qEntry in ipairs(getQuestNpcs(entry.questId)) do
                    queue(qEntry.name, qEntry.kind)
                end
            elseif entry.name then
                queue(entry.name, entry.kind)
            end
        end
    end
    if #picks == 0 then
        announce("No suggestions to add.")
        return
    end
    input:SetText("")
    input:ClearFocus()
    hideSuggestions(input)
    addFinderBatch(picks)
end

local function addNearbyQuestNpcs()
    if not loadQuestieDB() then
        announce("Questie is not loaded.")
        return
    end
    local entries = collectNearbyQuestNpcs()
    if not entries or #entries == 0 then
        announce("Nothing to track here yet.")
        return
    end
    writeFinderMacro({})
    addFinderBatch(entries)
end

local function submitInput(input)
    local typed = trim(input:GetText())
    if typed then
        addFinder(typed)
    else
        addFinder(resolveName(nil))
    end
    input:SetText("")
    input:ClearFocus()
    hideSuggestions(input)
end

local PANEL_PAD = 14
local PANEL_PAD_TOP = 52       -- clears the dialog-box-header banner
local PANEL_PAD_BOTTOM = 14
local SECTION_GAP = 22
local SECTION_INNER_PAD = 12
local SECTION_LABEL_LIFT = 7

-- Matches AceGUI Frame (the look Questie's panel uses).
local function applyPanelBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

-- Dialog-box header banner reconstructed from three texture pieces (left cap,
-- repeating middle, right cap). Same texCoords AceGUI uses for its Frame title.
local function buildTitleHeader(parent, text)
    local HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

    local mid = parent:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(HEADER_TEXTURE)
    mid:SetTexCoord(0.31, 0.67, 0, 0.63)
    mid:SetPoint("TOP", parent, "TOP", 0, 12)
    mid:SetHeight(40)

    local left = parent:CreateTexture(nil, "OVERLAY")
    left:SetTexture(HEADER_TEXTURE)
    left:SetTexCoord(0.21, 0.31, 0, 0.63)
    left:SetPoint("RIGHT", mid, "LEFT")
    left:SetWidth(30)
    left:SetHeight(40)

    local right = parent:CreateTexture(nil, "OVERLAY")
    right:SetTexture(HEADER_TEXTURE)
    right:SetTexCoord(0.67, 0.77, 0, 0.63)
    right:SetPoint("LEFT", mid, "RIGHT")
    right:SetWidth(30)
    right:SetHeight(40)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mid, "TOP", 0, -14)
    title:SetText(text)

    mid:SetWidth((title:GetStringWidth() or 0) + 10)

    return mid
end

-- Matches AceGUI InlineGroup: flat dark bg + tooltip border with a label above.
local function buildSection(parent, labelText)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    section:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    section:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", section, "TOPLEFT", 12, SECTION_LABEL_LIFT)
    label:SetText(labelText)
    section.label = label

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", SECTION_INNER_PAD, -SECTION_INNER_PAD)
    body:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -SECTION_INNER_PAD, SECTION_INNER_PAD)
    section.body = body

    return section
end

local function buildPanel()
    if panel then return panel end

    panel = CreateFrame("Frame", "TargetFinderPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 1)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnShow", function() refreshPanel() end)
    panel:Hide()
    applyPanelBackdrop(panel)
    tinsert(UISpecialFrames, "TargetFinderPanel")

    buildTitleHeader(panel, ADDON_NAME)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

    local tracked = buildSection(panel, "Tracked Targets (max " .. MAX_TARGETS .. ")")
    tracked:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -PANEL_PAD_TOP)
    tracked:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PAD, -PANEL_PAD_TOP)

    panel.rows = {}
    local lastRow
    for slot = 1, MAX_TARGETS do
        local row = CreateFrame("Frame", nil, tracked.body)
        row:SetHeight(22)
        if slot == 1 then
            row:SetPoint("TOPLEFT", tracked.body, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", tracked.body, "TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -2)
            row:SetPoint("TOPRIGHT", lastRow, "BOTTOMRIGHT", 0, -2)
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
        lastRow = row
    end

    local nearbyButton = CreateFrame("Button", nil, tracked.body, "UIPanelButtonTemplate")
    nearbyButton:SetHeight(22)
    nearbyButton:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -10)
    nearbyButton:SetPoint("TOPRIGHT", lastRow, "BOTTOMRIGHT", 0, -10)
    nearbyButton:SetText("Add Nearby Quest NPCs")
    nearbyButton:SetScript("OnClick", function() addNearbyQuestNpcs() end)

    local rowsHeight = MAX_TARGETS * 22 + (MAX_TARGETS - 1) * 2
    local trackedBody = rowsHeight + 10 + 22
    tracked:SetHeight(trackedBody + SECTION_INNER_PAD * 2)

    local addSection = buildSection(panel, "Add Target")
    addSection:SetPoint("TOPLEFT", tracked, "BOTTOMLEFT", 0, -SECTION_GAP)
    addSection:SetPoint("TOPRIGHT", tracked, "BOTTOMRIGHT", 0, -SECTION_GAP)

    local input = CreateFrame("EditBox", nil, addSection.body, "InputBoxTemplate")
    input:SetSize(170, 20)
    input:SetPoint("TOPLEFT", addSection.body, "TOPLEFT", 6, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input:SetScript("OnEnterPressed", function(self) submitInput(self) end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        hideSuggestions(self)
    end)
    attachAutocomplete(input)

    local addButton = CreateFrame("Button", nil, addSection.body, "UIPanelButtonTemplate")
    addButton:SetSize(60, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 10, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function() submitInput(input) end)

    local hint = addSection.body:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -10)
    hint:SetPoint("RIGHT", addSection.body, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Type an NPC or quest name to search, or leave empty for current target.")

    local clearButton = CreateFrame("Button", nil, addSection.body, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 22)
    clearButton:SetPoint("BOTTOMRIGHT", addSection.body, "BOTTOMRIGHT", 0, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", clearFinder)

    -- Input row (22) + gap (10) + hint (~28, wraps to 2 lines) + gap (10) + clear button (22).
    local addBody = 22 + 10 + 28 + 10 + 22
    addSection:SetHeight(addBody + SECTION_INNER_PAD * 2)

    panel:SetHeight(PANEL_PAD_TOP + tracked:GetHeight() + SECTION_GAP + addSection:GetHeight() + PANEL_PAD_BOTTOM)

    return panel
end

refreshPanel = function()
    if not panel then return end
    for slot = 1, MAX_TARGETS do
        local row = panel.rows[slot]
        local entry = findTargets[slot]
        if entry then
            row.name:SetText(entry.name)
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
    else
        panel:Show()
    end
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
            elseif button == "RightButton" then
                addNearbyQuestNpcs()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(ADDON_NAME)
            tt:AddLine("|cffffffffLeft-click|r to toggle the panel.", 1, 1, 1)
            tt:AddLine("|cffffffffRight-click|r to add nearby quest NPCs.", 1, 1, 1)
        end,
    })

    if TargetFinderDB.minimap.angle and not TargetFinderDB.minimap.minimapPos then
        TargetFinderDB.minimap.minimapPos = TargetFinderDB.minimap.angle
    end
    TargetFinderDB.minimap.angle = nil

    LDBIcon:Register(ADDON_NAME, dataObject, TargetFinderDB.minimap)
end

SLASH_TARGETFINDER_PANEL1 = "/tf"
SlashCmdList.TARGETFINDER_PANEL = function(msg)
    local arg = trim(msg)
    if not arg then
        togglePanel()
        return
    end
    if arg:lower() == "clear" then
        clearFinder()
        return
    end
    setFinder(arg)
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
    local lowered = name:lower()
    local matchedSlot
    for slot, entry in ipairs(findTargets) do
        if lowered:find(entry.name:lower(), 1, true) then
            matchedSlot = slot
            break
        end
    end

    if matchedSlot then
        root:CreateButton("Remove Target", function() C_Timer.After(0, function() removeFinder(matchedSlot) end) end)
    else
        root:CreateButton("Set Target", function() C_Timer.After(0, function() setFinder(name) end) end)
        root:CreateButton("Add Target", function() C_Timer.After(0, function() addFinder(name) end) end)
    end
    if #findTargets > 0 then
        root:CreateButton("Clear Targets", function() C_Timer.After(0, function() clearFinder() end) end)
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
        if type(TargetFinderDB) ~= "table" then TargetFinderDB = {} end
        if type(TargetFinderDB.minimap) ~= "table" then
            TargetFinderDB.minimap = { hide = false, minimapPos = MINIMAP_DEFAULT_POS }
        end
        if type(TargetFinderCharDB) ~= "table" then TargetFinderCharDB = {} end
        if type(TargetFinderCharDB.targets) ~= "table" then TargetFinderCharDB.targets = {} end
        findTargets = TargetFinderCharDB.targets
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        setupMinimapButton()
        if #findTargets > 0 then writeFinderMacro(findTargets) end
        announce("Loaded. Type /tf to open the panel.")
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_TARGET_CHANGED" then
        applyMarkerFromTarget()
    end
end)
