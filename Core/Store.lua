local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

local KINDS = { [ns.KIND_KILL] = true, [ns.KIND_DROP] = true, [ns.KIND_TURNIN] = true }

-- Sparse slot table indexed 1..MAX_TARGETS, nil meaning empty, each entry { name, quest, kind }. Created once and only ever mutated, because every module captures this reference at load time and a reassignment would leave them pointing at the old table.
local targets = {}

ns.targets = targets

-- quest marks an entry that came from the quest log, so it may drop off once Questie counts it done. kind picks its row icon. Typed entries leave both nil and are never dropped.
function ns.MakeEntry(name, quest, kind)
    local fromQuest = quest == true or nil
    return { name = name, quest = fromQuest, kind = fromQuest and KINDS[kind] and kind or nil }
end

function ns.TargetCount()
    local n = 0
    for slot = 1, MAX_TARGETS do
        if targets[slot] then n = n + 1 end
    end
    return n
end

function ns.FirstEmptySlot()
    for slot = 1, MAX_TARGETS do
        if not targets[slot] then return slot end
    end
    return nil
end

-- FIND targets names exactly, as /targetexact does, so a unit belongs to the entry that carries its whole name.
function ns.SlotForName(name)
    if not name then return nil end
    for slot = 1, MAX_TARGETS do
        local entry = targets[slot]
        if entry and entry.name == name then return slot end
    end
    return nil
end

-- Lets the quest-update check skip its walk over the quest log while no entry came from it.
function ns.HasQuestEntries()
    for slot = 1, MAX_TARGETS do
        if targets[slot] and targets[slot].quest then return true end
    end
    return false
end

function ns.WipeTargets()
    for slot = 1, MAX_TARGETS do targets[slot] = nil end
end

-- Take over the saved list in place, dropping anything malformed so a corrupt or half-written saved variable cannot break the macro builder. Aliasing the live table back into the saved variable afterwards is what makes later mutations persist without an explicit save step.
function ns.AdoptSaved(saved)
    ns.WipeTargets()
    if type(saved) == "table" then
        for slot = 1, MAX_TARGETS do
            local entry = saved[slot]
            if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
                targets[slot] = ns.MakeEntry(entry.name, entry.quest, entry.kind)
            end
        end
    end
    return targets
end
