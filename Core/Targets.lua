local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS

-- The open window already shows each change, so chat only speaks for changes made while it is closed. That is one line, ending with the bar reminder after an addition while FIND still needs one.
local function report(text, remind)
    if ns.PanelShown() then return end
    local hint = remind and ns.MacroHint()
    ns.Announce(hint and (text .. " " .. hint) or text)
end

-- A name from a unit menu goes first, so FIND prefers what the player just picked. Everything else moves down one slot. A full list gives up its last quest entry, or its last entry when every name was typed.
function ns.AddFinder(name)
    if ns.SlotForName(name) then
        ns.Announce(name .. " is already tracked.")
        return
    end

    local kept = {}
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then kept[#kept + 1] = ns.targets[slot] end
    end
    local dropped
    if #kept == MAX_TARGETS then
        local last = #kept
        for i = #kept, 1, -1 do
            if kept[i].quest then
                last = i
                break
            end
        end
        dropped = table.remove(kept, last)
    end

    ns.WipeTargets()
    ns.targets[1] = ns.MakeEntry(name)
    for i, entry in ipairs(kept) do ns.targets[i + 1] = entry end

    ns.WriteFinderMacro()
    local text = "Tracking " .. name .. "."
    if dropped then text = text .. " The list was full, so " .. dropped.name .. " was removed." end
    report(text, true)
    ns.ShowFinder()
end

function ns.RemoveFinder(slot)
    local removed = ns.targets[slot]
    if not removed then return end
    ns.targets[slot] = nil
    ns.WriteFinderMacro()
    report("Removed " .. removed.name .. ".")
end

-- A row dragged to another place in the window. The rows between move one step toward the gap it left, empty rows included, so the rest keep their order. A quest NPC stays a quest NPC, so the quest log can still swap it out.
function ns.MoveTarget(from, to)
    if from == to or not ns.targets[from] then return end
    local list = {}
    for slot = 1, MAX_TARGETS do list[slot] = ns.targets[slot] or false end
    local entry = table.remove(list, from)
    table.insert(list, to, entry)
    for slot = 1, MAX_TARGETS do ns.targets[slot] = list[slot] or nil end
    ns.WriteFinderMacro()
end

-- A name typed or picked into one row of the open window. It stays until the player removes it, even when a quest needs it, so moving on never takes away a name the player chose. ns.ApplyRowInput has already rejected empty and tracked names.
function ns.SetSlot(slot, name)
    ns.targets[slot] = ns.MakeEntry(name)
    ns.WriteFinderMacro()
end

local function listSignature()
    local names = {}
    for slot = 1, MAX_TARGETS do
        local entry = ns.targets[slot]
        names[slot] = entry and entry.name or ""
    end
    return table.concat(names, "\n")
end

-- Quest entries follow the quest log without a chat line. With open, the names quests still need, only quest entries outside it leave; without it every quest entry makes way. wanted, best first, then fills the free slots. Typed names keep their slots. byPlayer marks a quest picked in the window, which shows the combat notice. A list that did not change still writes while FIND is missing, so saved quest rows get their FIND on the first sync.
function ns.SyncQuestEntries(wanted, open, byPlayer)
    local before = listSignature()
    for slot = 1, MAX_TARGETS do
        local entry = ns.targets[slot]
        if entry and entry.quest and not (open and open[entry.name]) then ns.targets[slot] = nil end
    end
    for _, item in ipairs(wanted) do
        local slot = not ns.SlotForName(item.name) and ns.FirstEmptySlot()
        if slot then ns.targets[slot] = ns.MakeEntry(item.name, true, item.kind) end
    end
    if listSignature() ~= before or GetMacroIndexByName(ns.FIND_MACRO) == 0 then ns.WriteFinderMacro(false, not byPlayer) end
end
