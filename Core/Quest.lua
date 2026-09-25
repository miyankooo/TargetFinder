local _, ns = ...

-- Questie is the only quest data source, on both clients: Era runs Questie 11 with its bundled database or Questie 12 with the QuestieDB addon, Forever runs Questie 12 with QuestieDB. Names, spawns, drops, givers and objective progress all come from Questie; native APIs only supply the player's map position and the units on screen. Every Questie internal is existence-checked and each public entry point runs protected, so a changed internal ends in one chat line instead of a Lua error. The rest of the addon only ever calls the ns.* functions below.

local npcNames
local npcNamesLower
local readFailed = false

-- Questie is another addon's private code, so a field that changed shape must not raise on every keystroke. The first failure is reported once with its message so it can be passed on; later ones stay quiet.
local function guarded(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return true, result end
    if not readFailed then
        readFailed = true
        ns.Announce("Could not read Questie data (" .. tostring(result) .. "). Updating Questie or Target Finder should fix it.")
    end
    return false, nil
end

-- QuestieLoader:ImportModule creates an empty module for a name it does not know instead of returning nil, so a table coming back proves nothing; callers still check the fields they use.
local function questieModule(name)
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local module = loader:ImportModule(name)
    if type(module) ~= "table" then return nil end
    return module
end

-- Questie 11 assigns the three queries and NPCPointers inside QuestieDB:Initialize after login; Questie 12 binds the queries at file load but NPCPointers only in QuestieDB.Initialize. Requiring all four covers both, so an early click reports "still loading" instead of reading a half-built database.
local function questieDB()
    local db = questieModule("QuestieDB")
    if not db then return nil end
    if type(db.QueryNPCSingle) ~= "function" then return nil end
    if type(db.QueryQuestSingle) ~= "function" then return nil end
    if type(db.QueryItemSingle) ~= "function" then return nil end
    if type(db.NPCPointers) ~= "table" then return nil end
    return db
end

function ns.QuestieReady()
    return questieDB() ~= nil
end

-- Distinguishes "Questie is absent" from "Questie has not finished loading", because the two need different advice.
local function questieStatus()
    if not _G.QuestieLoader then return "absent" end
    if not ns.QuestieReady() then return "loading" end
    return "ready"
end

function ns.QuestieExcuse()
    if questieStatus() == "loading" then return "Questie is still loading." end
    return "Questie is not loaded."
end

-- Questie fills usedIcons from its own settings during OnInitialize, so the table is read on every call and follows an icon change made in Questie's options.
function ns.QuestieKindIcons()
    local Q = _G.Questie
    local used = type(Q) == "table" and Q.usedIcons
    if type(used) ~= "table" then return nil end
    return {
        [ns.KIND_KILL] = used[Q.ICON_TYPE_SLAY],
        [ns.KIND_DROP] = used[Q.ICON_TYPE_LOOT],
        [ns.KIND_ASSOC] = used[Q.ICON_TYPE_TALK],
        [ns.KIND_GIVER] = used[Q.ICON_TYPE_AVAILABLE],
    }
end

-- Questie replaces currentQuestlog with a new table on every full quest-log scan, so it is read fresh each time and never cached.
local function questLog()
    local player = questieModule("QuestiePlayer")
    local log = player and player.currentQuestlog
    if type(log) ~= "table" then return nil end
    return log
end

-- Log entries are Questie's live quest objects. Questie stores the bare quest id instead when it could not build one, so that case falls back to the database object, which has objective data but no progress.
local function questObject(db, log, questId)
    local entry = log and log[questId]
    if type(entry) == "table" then return entry end
    if type(db.GetQuest) ~= "function" then return nil end
    local quest = db.GetQuest(questId)
    if type(quest) ~= "table" then return nil end
    return quest
end

-- Questie's own progress: quest.Objectives[i] is built from ObjectiveData[i] and its Completed flag is what Questie uses to drop that objective's map icons. A missing entry counts as open, so a quest Questie has not scanned yet still offers its NPCs.
local function objectiveDone(quest, index)
    local objectives = quest.Objectives
    local objective = type(objectives) == "table" and objectives[index]
    return type(objective) == "table" and objective.Completed == true
end

-- Questie's two completion signals: IsComplete reads its quest-log cache, and isComplete is the flag it sets itself when every objective is done before the log catches up.
local function readyToTurnIn(db, quest, questId)
    if quest and quest.isComplete == true then return true end
    return type(db.IsComplete) == "function" and db.IsComplete(questId) == 1
end

local function npcName(db, npcId)
    if not npcId then return nil end
    local name = db.QueryNPCSingle(npcId, "name")
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Kill targets and item droppers for every objective Questie still counts as open.
local function forEachObjectiveNpc(db, quest, visit)
    local objectiveData = quest and quest.ObjectiveData
    if type(objectiveData) ~= "table" then return end
    for index, data in ipairs(objectiveData) do
        if type(data) == "table" and not objectiveDone(quest, index) then
            if data.Type == "monster" and data.Id then
                visit(data.Id, ns.KIND_KILL)
            elseif data.Type == "killcredit" and type(data.IdList) == "table" then
                for _, id in ipairs(data.IdList) do visit(id, ns.KIND_KILL) end
            elseif data.Type == "item" and data.Id then
                local droppers = db.QueryItemSingle(data.Id, "npcDrops")
                if type(droppers) == "table" then
                    for _, dropperId in ipairs(droppers) do visit(dropperId, ns.KIND_DROP) end
                end
            end
        end
    end
end

-- startedBy and finishedBy are { npcIds, objectIds, itemIds }; only the NPC list is something /target can reach.
local function forEachGiverNpc(db, questId, field, visit)
    local givers = db.QueryQuestSingle(questId, field)
    local npcs = type(givers) == "table" and givers[1]
    if type(npcs) ~= "table" then return end
    for _, id in ipairs(npcs) do visit(id, ns.KIND_GIVER) end
end

local function forEachQuestNpc(db, log, questId, visit)
    forEachObjectiveNpc(db, questObject(db, log, questId), visit)
    forEachGiverNpc(db, questId, "startedBy", visit)
    forEachGiverNpc(db, questId, "finishedBy", visit)
end

-- Keeps each NPC name once with the highest-priority kind it was seen with, then sorts by kind with first-seen order as the tiebreak.
local function newNpcCollector(db)
    local seen = {}
    local entries = {}
    local collector = {}

    function collector.add(npcId, kind, questName)
        local name = npcName(db, npcId)
        if not name then return end
        local existing = seen[name]
        if not existing then
            existing = { name = name, kind = kind, questName = questName, order = #entries + 1 }
            seen[name] = existing
            entries[#entries + 1] = existing
        elseif kind < existing.kind then
            existing.kind = kind
            existing.questName = questName
        end
    end

    function collector.sorted()
        table.sort(entries, function(a, b)
            if a.kind ~= b.kind then return a.kind < b.kind end
            return a.order < b.order
        end)
        return entries
    end

    return collector
end

local function buildNpcNameIndex(db)
    if npcNames then return true end
    local seen = {}
    local list = {}
    for npcId in pairs(db.NPCPointers) do
        local name = npcName(db, npcId)
        if name and not seen[name] then
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

local function questNpcs(questId)
    local db = questieDB()
    if not db then return {} end
    local collector = newNpcCollector(db)
    forEachQuestNpc(db, questLog(), questId, collector.add)
    return collector.sorted()
end

-- Every NPC tied to one quest, highest priority kind first and discovery order as the tiebreak.
function ns.QuestNpcs(questId)
    local ok, entries = guarded(questNpcs, questId)
    return ok and entries or {}
end

-- Every NPC across the whole quest log, used to tag search results with their quest.
local function questLogNpcNames(db, log)
    local collector = newNpcCollector(db)
    for questId in pairs(log) do
        local questName = db.QueryQuestSingle(questId, "name")
        forEachQuestNpc(db, log, questId, function(npcId, kind)
            collector.add(npcId, kind, questName)
        end)
    end
    return collector.sorted()
end

-- The player's position in Questie's zone ids. ZoneDB:GetAreaIdByUiMapId raises for a map it cannot place, such as an instance or a map newer than Questie, hence the pcall.
local function playerWhere()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil end
    local ZoneDB = questieModule("ZoneDB")
    if not ZoneDB or type(ZoneDB.GetAreaIdByUiMapId) ~= "function" then return nil end
    local ok, areaId = pcall(ZoneDB.GetAreaIdByUiMapId, ZoneDB, uiMapId)
    if not ok or not areaId then return nil end

    local where = { areaId = areaId }
    if type(ZoneDB.GetParentZoneId) == "function" then
        where.parentId = ZoneDB:GetParentZoneId(areaId)
    end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(uiMapId, "player")
    if pos then
        where.x, where.y = pos.x * 100, pos.y * 100
    end
    return where
end

-- Squared distance to the nearest spawn in the player's zone or its parent, nil when the NPC never spawns there. Questie spawns are map percentages in the running client's own frame (QuestieDB ships Forever's already converted), so they line up with C_Map positions scaled by 100.
local function spawnDistance(db, npcId, where)
    local spawns = db.QueryNPCSingle(npcId, "spawns")
    if type(spawns) ~= "table" then return nil end
    local zoneSpawns = spawns[where.areaId] or (where.parentId and spawns[where.parentId])
    if type(zoneSpawns) ~= "table" then return nil end
    if not where.x then return 0 end
    local best
    for _, coord in ipairs(zoneSpawns) do
        if type(coord) == "table" and coord[1] and coord[2] then
            local dx, dy = coord[1] - where.x, coord[2] - where.y
            local d = dx * dx + dy * dy
            if not best or d < best then best = d end
        end
    end
    return best
end

-- Anything already on a nameplate is close by definition, even where zone and spawn data would reject it.
local function nameplateNames()
    local names = {}
    for i = 1, ns.MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            local name = ns.ReadableName(unit)
            if name then names[name] = true end
        end
    end
    return names
end

-- Closest eight first, then order that subset by priority so the macro's top slot is the most useful thing in reach.
local function closestByPriority(entries)
    table.sort(entries, function(a, b) return a.dist < b.dist end)
    local top = {}
    for i = 1, math.min(#entries, ns.MAX_TARGETS) do top[i] = entries[i] end
    table.sort(top, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.dist < b.dist
    end)
    return top
end

local function nearbyQuestNpcs()
    local db = questieDB()
    local log = questLog()
    if not db or not log then return nil end

    local where = playerWhere()
    local inView = nameplateNames()
    local seen = {}
    local entries = {}

    local function visit(npcId, kind)
        local name = npcName(db, npcId)
        if not name then return end
        local existing = seen[name]
        if existing then
            if kind < existing.kind then existing.kind = kind end
            return
        end
        local dist
        if inView[name] then
            dist = 0
        elseif where then
            dist = spawnDistance(db, npcId, where)
        end
        if not dist then return end
        local entry = { name = name, dist = dist, kind = kind }
        entries[#entries + 1] = entry
        seen[name] = entry
    end

    for questId in pairs(log) do
        local quest = questObject(db, log, questId)
        if readyToTurnIn(db, quest, questId) then
            -- Ready to hand in, so the turn-in giver is the only actionable NPC.
            forEachGiverNpc(db, questId, "finishedBy", visit)
        else
            -- Still active, so open objectives only: startedBy is moot once accepted and finishedBy is not actionable yet.
            forEachObjectiveNpc(db, quest, visit)
        end
    end

    return closestByPriority(entries)
end

-- Quest names from the log first, then quest NPCs, then a prefix pass over the whole NPC index, then a substring pass. Prefix before substring puts the name /target can actually acquire at the top.
local function findSuggestions(query)
    local db = questieDB()
    if not db or not buildNpcNameIndex(db) then return {} end
    local q = query:lower()
    local qLen = #q
    local results = {}
    local picked = {}
    local log = questLog()

    if log then
        for questId in pairs(log) do
            local questName = db.QueryQuestSingle(questId, "name")
            if type(questName) == "string" and questName:lower():find(q, 1, true) then
                results[#results + 1] = { type = "quest", name = questName, questId = questId }
                if #results >= ns.MAX_SUGGESTIONS then return results end
            end
        end

        local questNpcNames = questLogNpcNames(db, log)
        for i = 1, #questNpcNames do
            local entry = questNpcNames[i]
            if not picked[entry.name] and entry.name:lower():find(q, 1, true) then
                results[#results + 1] = {
                    type = "npc",
                    name = entry.name,
                    questName = entry.questName,
                    isQuestNpc = true,
                    kind = entry.kind,
                }
                picked[entry.name] = true
                if #results >= ns.MAX_SUGGESTIONS then return results end
            end
        end
    end

    for i = 1, #npcNamesLower do
        if npcNamesLower[i]:sub(1, qLen) == q and not picked[npcNames[i]] then
            results[#results + 1] = { type = "npc", name = npcNames[i] }
            picked[npcNames[i]] = true
            if #results >= ns.MAX_SUGGESTIONS then return results end
        end
    end

    for i = 1, #npcNamesLower do
        local lname = npcNamesLower[i]
        if lname:sub(1, qLen) ~= q and lname:find(q, 1, true) and not picked[npcNames[i]] then
            results[#results + 1] = { type = "npc", name = npcNames[i] }
            picked[npcNames[i]] = true
            if #results >= ns.MAX_SUGGESTIONS then return results end
        end
    end

    return results
end

function ns.FindSuggestions(query)
    local ok, results = guarded(findSuggestions, query)
    return ok and results or {}
end

function ns.AddNearbyQuestNpcs()
    if not ns.QuestieReady() then
        ns.Announce(ns.QuestieExcuse())
        return
    end
    local ok, entries = guarded(nearbyQuestNpcs)
    if not ok then return end
    if not entries or #entries == 0 then
        ns.Announce("Nothing to track here yet.")
        return
    end
    ns.ReplaceFinder(entries)
end
