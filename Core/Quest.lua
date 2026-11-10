local _, ns = ...

-- QuestieDB, the standalone database addon Questie itself is built on, is the only quest data source: quest names, objectives and turn-in NPCs, NPC names and spawns, and item drops, all through its public LibQuestieDB API. The game's own quest log says which quests the player holds and how far each objective is. Questie itself is not needed. Each public entry point runs protected, so a changed field ends in one chat line instead of a Lua error. The rest of the addon only ever calls the ns.* functions below.

-- The LibQuestieDB contract this file is written against. RequireContract accepts a range (QuestieDB src/api.lua:94-110), so an additive QuestieDB release keeps working and an incompatible one reads as unsupported.
local CONTRACT = 4

local EMPTY = {}

local npcNames
local npcNamesLower
local readFailed = false

-- A field that changed shape must not raise on every keystroke. The first failure is reported once with its message so it can be passed on; later ones stay quiet.
local function guarded(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return true, result end
    if not readFailed then
        readFailed = true
        ns.Print("Could not read QuestieDB data (" .. tostring(result) .. "). Updating QuestieDB or Target Finder should fix it.")
    end
    return false, nil
end

-- ipairs over a field that may be missing.
local function each(list)
    return ipairs(type(list) == "table" and list or EMPTY)
end

local function isReader(entity)
    return type(entity) == "table" and type(entity.Get) == "function" and type(entity.GetAllIds) == "function"
end

-- "absent" when QuestieDB did not load, "unsupported" when it speaks another contract or lacks a reader this file calls, else "ready" and the library.
local function libraryStatus()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" then return "absent" end
    if type(lib.RequireContract) ~= "function" or not lib.RequireContract(CONTRACT) then return "unsupported" end
    if not (isReader(lib.Quest) and isReader(lib.Npc) and isReader(lib.Item)) then return "unsupported" end
    return "ready", lib
end

local function questDB()
    local status, lib = libraryStatus()
    if status == "ready" then return lib end
    return nil
end

function ns.QuestDataReady()
    return (libraryStatus()) == "ready"
end

-- Each state that keeps the quest features off needs different advice.
local EXCUSES = {
    absent = "QuestieDB is not loaded.",
    unsupported = "This QuestieDB version is not supported.",
}

function ns.QuestDataExcuse()
    return EXCUSES[(libraryStatus())]
end

-- The quests in the player's log. The log API lists only the quests under expanded headers (Blizzard's own quest search expands every header first, QuestMapFrame.lua:162-175), so the set is seeded by asking C_QuestLog.IsOnQuest about every quest QuestieDB knows, then kept by QUEST_ACCEPTED and QUEST_REMOVED. A loading screen drops it, so the next read seeds it afresh.
local activeQuests

local function questLog(lib)
    if not activeQuests then
        activeQuests = {}
        for _, questId in each(lib.Quest.GetAllIds()) do
            if C_QuestLog.IsOnQuest(questId) then activeQuests[questId] = true end
        end
    end
    return activeQuests
end

-- A quest's objectives in the order the game's quest log lists them, so entry i belongs to the game's objective i. QuestieDB stores them by type; this is Questie's order (Database/QuestieDB.lua:1606-1738): creatures, objects, items, reputation, kill credit, spells, then the scripted event, each type moved to the front for the quests LibQuestieDB.ObjectiveFirst names. Only kill targets and items lead to an NPC; the other types just hold their place.
local function orderedObjectives(lib, questId)
    local list = {}
    local first = type(lib.ObjectiveFirst) == "table" and lib.ObjectiveFirst or EMPTY
    local function add(entry, front)
        if type(front) == "table" and front[questId] then
            table.insert(list, 1, entry)
        else
            list[#list + 1] = entry
        end
    end
    local raw = lib.Quest.Get(questId, "objectives")
    if type(raw) == "table" then
        for _, creature in each(raw[1]) do add({ ids = { creature[1] } }) end
        for _ in each(raw[2]) do add({}, first.objectObjectiveFirst) end
        for _, item in each(raw[3]) do add({ item = item[1] }, first.itemObjectiveFirst) end
        if raw[4] then add({}) end
        for _, credit in each(raw[5]) do add({ ids = credit[1] }, first.killCreditObjectiveFirst) end
        for _ in each(raw[6]) do add({}, first.spellObjectiveFirst) end
    end
    if lib.Quest.Get(questId, "triggerEnd") then add({}, first.eventObjectiveFirst) end
    return list
end

local function rowDone(row)
    return type(row) == "table" and row.finished == true
end

-- The game's own completion flag, or every objective row done before the flag catches up. A quest QuestieDB lists no objectives for, a delivery or talk-to quest, is ready from the start.
local function readyToTurnIn(questId, objectives, rows)
    if C_QuestLog.IsComplete(questId) then return true end
    if #objectives == 0 then return true end
    if #rows == 0 then return false end
    for _, row in ipairs(rows) do
        if not rowDone(row) then return false end
    end
    return true
end

local function npcName(lib, npcId)
    if not npcId then return nil end
    local name = lib.Npc.Get(npcId, "name")
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Kill targets and item droppers for every objective the game still counts as open. A missing row counts as open, so a quest whose objectives have not loaded yet still offers its NPCs.
local function forEachObjectiveNpc(lib, objectives, rows, visit)
    for index, objective in ipairs(objectives) do
        if not rowDone(rows[index]) then
            for _, id in each(objective.ids) do visit(id, ns.KIND_KILL) end
            if objective.item then
                -- An item can also come out of a container item, such as a crate, so the container's droppers count too, one level deep.
                local sources = { objective.item }
                for _, containerId in each(lib.Item.Get(objective.item, "itemDrops")) do sources[#sources + 1] = containerId end
                for _, itemId in ipairs(sources) do
                    for _, dropperId in each(lib.Item.Get(itemId, "npcDrops")) do visit(dropperId, ns.KIND_DROP) end
                end
            end
        end
    end
end

-- finishedBy is { npcIds, objectIds }; only the NPC list is something /target can reach.
local function forEachTurnInNpc(lib, questId, visit)
    local finishers = lib.Quest.Get(questId, "finishedBy")
    for _, id in each(type(finishers) == "table" and finishers[1]) do visit(id, ns.KIND_TURNIN) end
end

-- One rule for every quest NPC: the turn-in NPC once the quest is ready to hand in, otherwise the NPCs of its open objectives. The quest giver is moot once the quest is in the log.
local function forEachQuestNpc(lib, questId, visit)
    local objectives = orderedObjectives(lib, questId)
    local rows = C_QuestLog.GetQuestObjectives(questId)
    if type(rows) ~= "table" then rows = EMPTY end
    if readyToTurnIn(questId, objectives, rows) then
        forEachTurnInNpc(lib, questId, visit)
    else
        forEachObjectiveNpc(lib, objectives, rows, visit)
    end
end

-- Keeps each NPC name once with the highest-priority kind it was seen with, then sorts by kind with first-seen order as the tiebreak.
local function newNpcCollector(lib)
    local seen = {}
    local entries = {}
    local collector = {}

    function collector.add(npcId, kind, questName)
        local name = npcName(lib, npcId)
        if not name then return end
        local existing = seen[name]
        if not existing then
            existing = { name = name, kind = kind, questName = questName, order = #entries + 1, quest = true }
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

-- One pass over every NPC name, a stall QuestieDB says to take where it is invisible and never on a hover path (QuestieDB src/read/shared.lua:473-476). A keystroke is no better, so it runs at login under the loading screen; the first search builds it only if that has not happened yet.
local function buildNpcNameIndex(lib)
    if npcNames then return end
    local seen = {}
    local list = {}
    for _, npcId in each(lib.Npc.GetAllIds()) do
        local name = npcName(lib, npcId)
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
end

local function questNpcs(questId)
    local lib = questDB()
    if not lib then return {} end
    local collector = newNpcCollector(lib)
    forEachQuestNpc(lib, questId, collector.add)
    return collector.sorted()
end

-- Every NPC tied to one quest, highest priority kind first and discovery order as the tiebreak.
function ns.QuestNpcs(questId)
    local ok, entries = guarded(questNpcs, questId)
    return ok and entries or {}
end

-- Every NPC across the whole quest log, used to tag search results with their quest.
local function questLogNpcNames(lib, log)
    local collector = newNpcCollector(lib)
    for questId in pairs(log) do
        local questName = lib.Quest.Get(questId, "name")
        forEachQuestNpc(lib, questId, function(npcId, kind)
            collector.add(npcId, kind, questName)
        end)
    end
    return collector.sorted()
end

-- QuestieDB's zone tables, decoded once: the uiMapID-to-area and subzone-to-parent maps Questie builds the same way in its ZoneDB (Database/Zones/zoneDB.lua:65-100). Each ships as a Lua source string with an override table that wins. The chunks run in an empty environment, since they are plain table literals.
local zones

local function decoded(source)
    if type(source) == "table" then return source end
    if type(source) ~= "string" then return EMPTY end
    local chunk = loadstring(source)
    if not chunk then return EMPTY end
    setfenv(chunk, {})
    local ok, result = pcall(chunk)
    if ok and type(result) == "table" then return result end
    return EMPTY
end

local function merged(base, override)
    local map = {}
    for key, value in pairs(decoded(base)) do map[key] = value end
    for key, value in pairs(decoded(override)) do map[key] = value end
    return map
end

local function zoneMaps(lib)
    if zones then return zones end
    local support = type(lib.Support) == "table" and type(lib.Support.Get) == "function" and lib.Support.Get("ZoneDB")
    local tables = type(support) == "table" and support.private
    if type(tables) ~= "table" then return nil end
    zones = {
        areaByMap = merged(tables.uiMapIdToAreaId, tables.uiMapIdToAreaIdOverride),
        parentByArea = merged(tables.subZoneToParentZone, tables.subZoneToParentZoneOverride),
    }
    return zones
end

-- The player's position in QuestieDB's area IDs. A map the tables cannot place, such as an instance or a map newer than QuestieDB, gives nil.
local function playerWhere(lib)
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil end
    local maps = zoneMaps(lib)
    local areaId = maps and maps.areaByMap[uiMapId]
    if not areaId then return nil end

    local where = { areaId = areaId, parentId = maps.parentByArea[areaId] }
    local pos = C_Map.GetPlayerMapPosition(uiMapId, "player")
    if pos then
        where.x, where.y = pos.x * 100, pos.y * 100
    end
    return where
end

-- Squared distance to the nearest spawn in the player's zone or its parent, nil when the NPC never spawns there. QuestieDB spawns are map percentages in the running client's own frame (it ships Forever's already converted), so they line up with C_Map positions scaled by 100.
local function spawnDistance(lib, npcId, where)
    local spawns = lib.Npc.Get(npcId, "spawns")
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
    local lib = questDB()
    if not lib then return nil end

    local where = playerWhere(lib)
    local inView = nameplateNames()
    local seen = {}
    local entries = {}

    local function visit(npcId, kind)
        local name = npcName(lib, npcId)
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
            dist = spawnDistance(lib, npcId, where)
        end
        if not dist then return end
        local entry = { name = name, dist = dist, kind = kind, quest = true }
        entries[#entries + 1] = entry
        seen[name] = entry
    end

    for questId in pairs(questLog(lib)) do
        forEachQuestNpc(lib, questId, visit)
    end

    return closestByPriority(entries)
end

-- Quest names from the log first, then quest NPCs, then NPC index names that start with the query, then names that contain it. Prefix before substring puts the name /target can actually acquire at the top.
local function findSuggestions(query)
    local lib = questDB()
    if not lib then return {} end
    buildNpcNameIndex(lib)
    local q = query:lower()
    local results = {}
    local picked = {}
    local log = questLog(lib)

    for questId in pairs(log) do
        local questName = lib.Quest.Get(questId, "name")
        if type(questName) == "string" and questName:lower():find(q, 1, true) then
            results[#results + 1] = { type = "quest", name = questName, questId = questId }
            if #results >= ns.MAX_SUGGESTIONS then return results end
        end
    end

    local questNpcNames = questLogNpcNames(lib, log)
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

    -- One pass: prefix matches go straight in, substring matches wait in contained until the pass ends.
    local contained = {}
    for i = 1, #npcNamesLower do
        local at = npcNamesLower[i]:find(q, 1, true)
        if at and not picked[npcNames[i]] then
            if at == 1 then
                results[#results + 1] = { type = "npc", name = npcNames[i] }
                if #results >= ns.MAX_SUGGESTIONS then return results end
            elseif #contained < ns.MAX_SUGGESTIONS then
                contained[#contained + 1] = npcNames[i]
            end
        end
    end
    for _, name in ipairs(contained) do
        if #results >= ns.MAX_SUGGESTIONS then break end
        results[#results + 1] = { type = "npc", name = name }
    end
    return results
end

function ns.FindSuggestions(query)
    local ok, results = guarded(findSuggestions, query)
    return ok and results or {}
end

-- The names every quest in the log still needs, by the same rule as the nearby list. Nil while QuestieDB cannot answer, so nothing is dropped on a guess.
local function openQuestNpcNames()
    local lib = questDB()
    if not lib then return nil end
    local names = {}
    for questId in pairs(questLog(lib)) do
        forEachQuestNpc(lib, questId, function(npcId)
            local name = npcName(lib, npcId)
            if name then names[name] = true end
        end)
    end
    return names
end

function ns.OpenQuestNpcNames()
    local ok, names = guarded(openQuestNpcNames)
    return ok and names or nil
end

-- Quest entries follow the quest log, as RestedXP's targets follow the guide. A full sync, at login, in a new zone and when a quest is accepted, turned in or abandoned, swaps them for the closest NPCs the quests need; a light one, after an objective update, drops what no quest needs any more and fills free slots, so the rows hold still while the player fights. With Auto Apply Quest NPCs off only the drop runs, for NPCs added from a quest suggestion or a manual refresh. manual is the minimap right-click and /tf refresh, which fill the rows even with the box off. Names the player added are never touched: ns.SyncQuestEntries only ever removes or places quest entries.
local function syncQuestNpcs(full, manual)
    if not ns.QuestDataReady() then return end
    local following = TargetFinderCharDB.questNpcs or manual
    if full and not following then return end
    if not following and not ns.HasQuestEntries() then return end
    local open
    if not full then
        open = ns.OpenQuestNpcNames()
        if not open then return end
    end
    local wanted = {}
    if following then
        local ok, nearby = guarded(nearbyQuestNpcs)
        if not ok or not nearby then return end
        wanted = nearby
    end
    ns.SyncQuestEntries(wanted, open)
end

local syncQueued, fullQueued = false, false

-- A burst of quest events runs one sync on the next frame. A full request in the burst wins.
local function queueSync(full)
    fullQueued = fullQueued or full
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        local runFull = fullQueued
        syncQueued, fullQueued = false, false
        syncQuestNpcs(runFull)
    end)
end

-- Each quest's progress as one string: the completion flag and every objective's count. QUEST_LOG_UPDATE fires for far more than progress, so the light sync runs only when one of these moved, the way Questie compares its cached objectives before it calls back (Modules/Quest/QuestLogCache.lua:249).
local progress = {}

local function progressKey(questId)
    local parts = { C_QuestLog.IsComplete(questId) and "done" or "open" }
    for _, row in each(C_QuestLog.GetQuestObjectives(questId)) do
        parts[#parts + 1] = type(row) == "table" and (tostring(row.numFulfilled) .. (row.finished and "+" or "")) or "?"
    end
    return table.concat(parts, " ")
end

local function progressMoved()
    if not activeQuests then return false end
    local moved = false
    for questId in pairs(activeQuests) do
        local key = progressKey(questId)
        if progress[questId] ~= key then
            progress[questId] = key
            moved = true
        end
    end
    for questId in pairs(progress) do
        if not activeQuests[questId] then progress[questId] = nil end
    end
    return moved
end

-- Accepting, turning in or abandoning a quest changes which NPCs the log needs, and so does a new zone or subzone, so those run a full sync. QUEST_REMOVED fires for a turn-in and an abandon alike. A loading screen also drops the quest set, which the sync then seeds afresh.
local questEvents = CreateFrame("Frame")
questEvents:SetScript("OnEvent", function(_, event, questId)
    if event == "QUEST_LOG_UPDATE" then
        if progressMoved() then queueSync(false) end
        return
    end
    if event == "QUEST_ACCEPTED" then
        if activeQuests then activeQuests[questId] = true end
    elseif event == "QUEST_REMOVED" then
        if activeQuests then activeQuests[questId] = nil end
    elseif event == "PLAYER_ENTERING_WORLD" then
        activeQuests = nil
    end
    queueSync(true)
end)

local QUEST_EVENTS = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }

-- Login starts the quest side: the NPC name index pass runs while the loading screen still shows, and the quest events count from here on. PLAYER_ENTERING_WORLD follows login and runs the first sync.
function ns.WatchQuests()
    local lib = questDB()
    if not lib then return end
    guarded(buildNpcNameIndex, lib)
    for _, event in ipairs(QUEST_EVENTS) do questEvents:RegisterEvent(event) end
end

-- The Auto Apply Quest NPCs box. On fills the list at once, off takes every quest entry away. Typed names stay either way.
function ns.SetQuestNpcs(on)
    TargetFinderCharDB.questNpcs = on
    if on then
        syncQuestNpcs(true)
    else
        ns.SyncQuestEntries({})
    end
end

local function questEntryCount()
    local count = 0
    for slot = 1, ns.MAX_TARGETS do
        if ns.targets[slot] and ns.targets[slot].quest then count = count + 1 end
    end
    return count
end

-- The minimap right-click and /tf refresh: the quest rows swap for the quest NPCs closest to the player right now, also with Auto Apply Quest NPCs off. One chat line says what happened, since the window may be closed.
function ns.RefreshQuestNpcs()
    if not ns.QuestDataReady() then
        ns.Print(ns.QuestDataExcuse())
        return
    end
    syncQuestNpcs(true, true)
    local count = questEntryCount()
    if count > 0 then
        ns.Print(("Updated the quest NPCs: %d |4row:rows; filled."):format(count))
    elseif not ns.FirstEmptySlot() then
        ns.Print("Every row holds a name you added, so no quest NPC fits. Remove one first.")
    else
        ns.Print("No quest NPCs found nearby.")
    end
end

-- A quest picked from the suggestions takes the quest rows first. With Auto Apply Quest NPCs on the closest other quest NPCs fill what is left.
function ns.TrackQuest(questId)
    local picks = ns.QuestNpcs(questId)
    if #picks == 0 then
        ns.Print("No NPCs found for that quest.")
        return
    end
    ns.SyncQuestEntries(picks, nil, true)
    if not ns.SlotForName(picks[1].name) then
        ns.Print("The list is full. Remove a name first.")
        return
    end
    syncQuestNpcs(false)
end
