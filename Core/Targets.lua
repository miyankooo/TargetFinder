local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

-- Every mutation ends the same way: write the macro, give each new slot's marker to one unit in view (the target when it matches, see Markers.lua), report what happened, and offer the macro book while FIND is still unbound.
local function reportAdded(names, marked)
    local suffix = marked > 0 and " — " .. marked .. " marked" or ""
    ns.Announce(table.concat(names, ", ") .. suffix)
    ns.HintMacro(ns.FIND_MACRO)
end

function ns.AddFinder(name, kind)
    if not name then
        ns.Announce("No target selected.")
        return
    end
    if ns.SlotForName(name) then
        ns.Announce(name .. " is already tracked.")
        return
    end
    local slot = ns.FirstEmptySlot()
    if not slot then
        ns.Announce("Finder is full: " .. table.concat(ns.EntryNames(), ", ") .. ".")
        return
    end
    ns.targets[slot] = ns.MakeEntry(name, kind)
    ns.WriteFinderMacro()
    reportAdded(ns.EntryNames(), ns.MarkNearbyForSlot(slot))
end

-- Insert at slot 1 so the macro's last /target line wins. Everything else shifts down one slot and a full list drops its lowest-priority entry off the end.
function ns.AddFinderFirst(name, kind, existingSlot)
    -- Callers that already matched a slot by prefix pass it in, so the matched entry is promoted instead of gaining a near-duplicate beside it.
    local promoted = existingSlot and ns.targets[existingSlot]
    if not promoted and not name then
        ns.Announce("No target selected.")
        return
    end

    local duplicate = existingSlot or ns.SlotForName(name)
    if duplicate == 1 then
        ns.Announce((promoted and promoted.name or name) .. " is already first.")
        return
    end

    local kept = {}
    for slot = 1, MAX_TARGETS do
        local entry = ns.targets[slot]
        if entry and slot ~= duplicate then kept[#kept + 1] = entry end
    end

    ns.WipeTargets()
    ns.targets[1] = promoted or ns.MakeEntry(name, kind)
    for i = 1, math.min(#kept, MAX_TARGETS - 1) do
        ns.targets[i + 1] = kept[i]
    end

    -- Only set when a new name fills a list that was already full, never when promoting in place.
    local dropped = kept[MAX_TARGETS]

    ns.WriteFinderMacro()
    reportAdded(ns.EntryNames(), ns.RemarkAllSlots())

    if dropped then
        ns.Announce("List was full, dropped " .. dropped.name .. ".")
    end
end

function ns.AddFinderBatch(items)
    if type(items) ~= "table" or #items == 0 then
        ns.Announce("Nothing to add.")
        return
    end

    local existing = {}
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then existing[ns.targets[slot].name] = true end
    end

    local added = {}
    local newSlots = {}
    for _, item in ipairs(items) do
        local name = item.name
        if name and name ~= "" and not existing[name] then
            local empty = ns.FirstEmptySlot()
            if not empty then break end
            ns.targets[empty] = ns.MakeEntry(name, item.kind)
            existing[name] = true
            added[#added + 1] = name
            newSlots[#newSlots + 1] = empty
        end
    end

    if #added == 0 then
        ns.Announce("Already tracking everything from that list.")
        return
    end

    ns.WriteFinderMacro()
    local marked = 0
    for _, slot in ipairs(newSlots) do
        marked = marked + ns.MarkNearbyForSlot(slot)
    end
    reportAdded(added, marked)
end

-- Replace the whole list in one step. Wiping and then adding separately would leave the list empty and the macro stale if the add found nothing to do.
function ns.ReplaceFinder(items)
    if type(items) ~= "table" or #items == 0 then
        ns.Announce("Nothing to add.")
        return
    end
    ns.WipeTargets()
    ns.AddFinderBatch(items)
end

function ns.RemoveFinder(slot)
    local removed = ns.targets[slot]
    if not removed then return end
    ns.targets[slot] = nil
    ns.WriteFinderMacro()
    ns.Announce("Removed: " .. removed.name)
end

function ns.ClearFinder()
    if ns.TargetCount() == 0 then
        ns.Announce("Finder is empty.")
        return
    end
    ns.WipeTargets()
    ns.WriteFinderMacro()
    ns.Announce("Finder cleared.")
end

function ns.SetSlot(slot, name)
    if not name or name == "" then return end
    local existingSlot = ns.SlotForName(name)
    if existingSlot == slot then return end
    if existingSlot then
        ns.Announce(name .. " is already tracked.")
        return
    end
    local previous = ns.targets[slot]
    ns.targets[slot] = ns.MakeEntry(name)
    ns.WriteFinderMacro()
    local marked = ns.MarkNearbyForSlot(slot)
    local suffix = marked > 0 and " — " .. marked .. " marked" or ""
    if previous then
        ns.Announce("Replaced " .. previous.name .. " with " .. name .. suffix)
    else
        ns.Announce(name .. suffix)
    end
    ns.HintMacro(ns.FIND_MACRO)
end
