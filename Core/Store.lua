local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

-- Sparse slot table indexed 1..MAX_TARGETS, nil meaning empty, each entry { name, kind }. Created once and only ever mutated, because every module captures this reference at load time and a reassignment would leave them pointing at the old table.
local targets = {}

ns.targets = targets

function ns.MakeEntry(name, kind)
    return { name = name, kind = kind or ns.KIND_GIVER }
end

-- /target acquires the first nearby unit whose name BEGINS with the typed text, so marking and menu matching use the same prefix rule. Substring matching would claim units the macro can never reach: "Chillgular" would mark and offer Untrack on "Auctioneer Chillgular" while FIND never acquired it.
function ns.NameMatches(unitName, entryName)
    if not unitName or not entryName then return false end
    local lowered = unitName:lower()
    local prefix = entryName:lower()
    return lowered:sub(1, #prefix) == prefix
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

-- Exact name lookup, for deciding whether a typed name is already stored.
function ns.SlotForName(name)
    if not name then return nil end
    for slot = 1, MAX_TARGETS do
        local entry = targets[slot]
        if entry and entry.name == name then return slot end
    end
    return nil
end

-- Prefix lookup, for deciding whether a unit the player is looking at is already covered by a stored entry.
function ns.SlotCovering(unitName)
    if not unitName then return nil end
    for slot = 1, MAX_TARGETS do
        local entry = targets[slot]
        if entry and ns.NameMatches(unitName, entry.name) then return slot end
    end
    return nil
end

function ns.EntryNames()
    local out = {}
    for slot = 1, MAX_TARGETS do
        if targets[slot] then out[#out + 1] = targets[slot].name end
    end
    return out
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
                targets[slot] = ns.MakeEntry(entry.name, tonumber(entry.kind))
            end
        end
    end
    return targets
end
