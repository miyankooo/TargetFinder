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

-- The game's own completion flag, or every objective row done before the flag catches up. Only a quest neither the game nor QuestieDB lists objectives for, a delivery or talk-to quest, is ready from the start, so a quest QuestieDB knows no objectives for never offers its turn-in NPC while the game still counts an open row.
local function readyToTurnIn(questId, objectives, rows)
    if C_QuestLog.IsComplete(questId) then return true end
    if #rows == 0 then return #objectives == 0 end
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

-- QuestieDB's area-to-map table, decoded once. An NPC's spawns are listed per area ID as percentages of that area's map, the one this table names, so Northshire Valley's spawns sit on the Elwynn Forest map. It ships as a Lua source string with an override table that wins. The chunks run in an empty environment, since they are plain table literals.
local mapByArea

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

local function areaMaps(lib)
    if mapByArea then return mapByArea end
    local support = type(lib.Support) == "table" and type(lib.Support.Get) == "function" and lib.Support.Get("ZoneDB")
    local tables = type(support) == "table" and support.private
    if type(tables) ~= "table" then return nil end
    mapByArea = merged(tables.areaIdToUiMapId, tables.areaIdToUiMapIdOverride)
    return mapByArea
end

-- Each map's place in the world: its continent, the world point of its top-left corner, and the world vectors of one map unit east and one unit south. A zone map is flat, so these place every point on it in yards. False for a map with no world position. Maps never move, so each is read once.
local mapFrames = {}

local function mapFrame(uiMapId)
    local frame = mapFrames[uiMapId]
    if frame ~= nil then return frame end
    frame = false
    local continent, origin = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(0, 0))
    local _, east = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(1, 0))
    local _, south = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(0, 1))
    if continent and origin and east and south then
        frame = {
            continent = continent, x = origin.x, y = origin.y,
            ex = east.x - origin.x, ey = east.y - origin.y, sx = south.x - origin.x, sy = south.y - origin.y,
        }
    end
    mapFrames[uiMapId] = frame
    return frame
end

-- A point given as fractions of a map, in world yards.
local function toWorld(frame, u, v)
    return frame.x + u * frame.ex + v * frame.sx, frame.y + u * frame.ey + v * frame.sy
end

-- The player's continent and world position, from whichever map the game places them on, a subzone or cave map included. Nil where the game gives no map position, such as inside an instance.
local function playerSpot()
    local uiMapId = C_Map.GetBestMapForUnit("player")
    local pos = uiMapId and C_Map.GetPlayerMapPosition(uiMapId, "player")
    local frame = pos and mapFrame(uiMapId)
    if not frame then return nil end
    local x, y = toWorld(frame, pos.x, pos.y)
    return { continent = frame.continent, x = x, y = y }
end

-- Squared yards to the NPC's nearest spawn on the player's continent, whichever area lists it, so a camp just across a zone border counts too. Nil when no spawn can be placed. QuestieDB marks a spawn inside an instance as (-1, -1), which never counts.
local function spawnDistance(lib, npcId, spot, maps)
    local spawns = lib.Npc.Get(npcId, "spawns")
    if type(spawns) ~= "table" then return nil end
    local best
    for areaId, coords in pairs(spawns) do
        local uiMapId = maps[areaId]
        local frame = type(coords) == "table" and type(uiMapId) == "number" and uiMapId > 0 and mapFrame(uiMapId)
        if frame and frame.continent == spot.continent then
            for _, coord in ipairs(coords) do
                local u = type(coord) == "table" and coord[1]
                local v = u and coord[2]
                if type(u) == "number" and type(v) == "number" and u >= 0 and v >= 0 then
                    local x, y = toWorld(frame, u / 100, v / 100)
                    local dx, dy = x - spot.x, y - spot.y
                    local d = dx * dx + dy * dy
                    if not best or d < best then best = d end
                end
            end
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

local REACH = ns.NEARBY_YARDS * ns.NEARBY_YARDS

-- Where the quest rows were last measured from, so the movement check knows how far the player has gone since.
local lastSpot

-- One walk over the quest log: needed holds every name a quest still needs, inReach those within ns.NEARBY_YARDS of the player, and best the closest eight of them by priority.
local function nearbyQuestNpcs()
    local lib = questDB()
    if not lib then return nil end

    local spot = playerSpot()
    lastSpot = spot
    local maps = spot and areaMaps(lib)
    local inView = nameplateNames()
    local needed = {}
    local inReach = {}
    local entries = {}

    local function visit(npcId, kind)
        local name = npcName(lib, npcId)
        if not name then return end
        needed[name] = true
        local existing = inReach[name]
        if existing then
            if kind < existing.kind then existing.kind = kind end
            return
        end
        local dist
        if inView[name] then
            dist = 0
        elseif maps then
            dist = spawnDistance(lib, npcId, spot, maps)
        end
        if not dist or dist > REACH then return end
        local entry = { name = name, dist = dist, kind = kind, quest = true }
        entries[#entries + 1] = entry
        inReach[name] = entry
    end

    for questId in pairs(questLog(lib)) do
        forEachQuestNpc(lib, questId, visit)
    end

    return { needed = needed, inReach = inReach, best = closestByPriority(entries) }
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

-- Quest entries follow the quest log and the player, as RestedXP's targets follow the guide. A full sync, at login, in a new zone and when a quest is accepted, turned in or abandoned, swaps them for the closest NPCs the quests need. A light one, after an objective update and every ns.STEP_YARDS the player moves, drops what no quest needs any more or what is out of reach, and fills free slots, so the rows still in reach hold still while the player fights. A quest entry the player pinned through a quest suggestion stays out of reach and leaves only once no quest needs it. With Auto Apply Quest NPCs off only that drop runs, for every quest entry, so a turn-in still clears its rows. manual is the minimap right-click and /tf refresh, which fill the rows even with the box off. Names the player added are never touched: ns.SyncQuestEntries only ever removes or places quest entries.
local function syncQuestNpcs(full, manual)
    if not ns.QuestDataReady() then return end
    local following = TargetFinderCharDB.questNpcs or manual
    if not following and not ns.HasQuestEntries() then return end
    local needed, wanted, keep = nil, EMPTY, {}
    if following then
        local ok, reach = guarded(nearbyQuestNpcs)
        if not ok or not reach then return end
        needed, wanted = reach.needed, reach.best
        if not full then
            for name in pairs(reach.inReach) do keep[name] = true end
        end
    else
        needed = ns.OpenQuestNpcNames()
        if not needed then return end
    end
    for slot = 1, ns.MAX_TARGETS do
        local entry = ns.targets[slot]
        if entry and entry.quest and needed[entry.name] and (entry.pinned or not following) then keep[entry.name] = true end
    end
    ns.SyncQuestEntries(wanted, keep)
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

-- No event reports the player's position, so while the player moves a ticker checks once a second how far they went from where the rows were last measured, and every ns.STEP_YARDS it runs a light sync. It stops when the player does, so standing still costs nothing, and it only measures while Auto Apply Quest NPCs is on.
local STEP = ns.STEP_YARDS * ns.STEP_YARDS
local mover

local function checkMoved()
    if not TargetFinderCharDB.questNpcs then return end
    local spot = playerSpot()
    if not spot then return end
    if lastSpot and spot.continent == lastSpot.continent then
        local dx, dy = spot.x - lastSpot.x, spot.y - lastSpot.y
        if dx * dx + dy * dy < STEP then return end
    end
    queueSync(false)
end

-- Accepting, turning in or abandoning a quest changes which NPCs the log needs, and so does a new zone or subzone, so those run a full sync. QUEST_REMOVED fires for a turn-in and an abandon alike. A loading screen also drops the quest set, which the sync then seeds afresh.
local questEvents = CreateFrame("Frame")
questEvents:SetScript("OnEvent", function(_, event, questId)
    if event == "QUEST_LOG_UPDATE" then
        if progressMoved() then queueSync(false) end
        return
    elseif event == "PLAYER_STARTED_MOVING" then
        if not mover then mover = C_Timer.NewTicker(1, checkMoved) end
        return
    elseif event == "PLAYER_STOPPED_MOVING" then
        if mover then
            mover:Cancel()
            mover = nil
        end
        checkMoved()
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

local QUEST_EVENTS = {
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
}

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

-- A quest picked from the suggestions takes the quest rows first, pinned so they stay however far away they are until the quest no longer needs them. With Auto Apply Quest NPCs on the closest other quest NPCs fill what is left.
function ns.TrackQuest(questId)
    local picks = ns.QuestNpcs(questId)
    if #picks == 0 then
        ns.Print("No NPCs found for that quest.")
        return
    end
    for _, pick in ipairs(picks) do pick.pinned = true end
    ns.SyncQuestEntries(picks, nil, true)
    if not ns.SlotForName(picks[1].name) then
        ns.Print("The list is full. Remove a name first.")
        return
    end
    syncQuestNpcs(false)
end
