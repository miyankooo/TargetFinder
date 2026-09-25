local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS
local MARK_THROTTLE = 0.15

local lastMarkTime = 0

-- A unit belongs to the first slot whose name covers it, the same priority rule the FIND macro and the target handler use, so two overlapping entries such as "Kobold" and "Kobold Miner" never fight over one unit.
local function ownsUnit(slot, unit)
    local name = ns.ReadableName(unit)
    if not name then return false end
    return ns.SlotCovering(name) == slot
end

-- GetRaidTargetIndex has SecretReturns on 1.60, so the index is only compared once the client lets the addon read it.
local function carriesMarker(unit, marker)
    local current = GetRaidTargetIndex(unit)
    return ns.CanAccess(current) and current == marker
end

-- Dedupe first, then throttle, so holding the FIND macro down cannot flicker a marker that is already correct. A throttled call is dropped rather than queued: the next target change re-runs it anyway.
function ns.ApplySlotMarker(slot)
    if not UnitExists("target") then return end
    local marker = ns.FIND_MARKERS[slot]
    if not marker then return end
    if carriesMarker("target", marker) then return end
    local now = GetTime()
    if now - lastMarkTime < MARK_THROTTLE then return end
    lastMarkTime = now
    SetRaidTarget("target", marker)
end

-- List edits are one-off actions rather than macro spam, so they skip the throttle and only dedupe.
local function markUnit(unit, marker)
    if carriesMarker(unit, marker) then return end
    SetRaidTarget(unit, marker)
end

-- Runs on every target change, including targets picked up by tab or click rather than by the macro.
function ns.ApplyMarkerFromTarget()
    if not UnitExists("target") then return end
    local name = ns.ReadableName("target")
    if not name then return end
    local slot = ns.SlotCovering(name)
    if slot then ns.ApplySlotMarker(slot) end
end

-- The visible nameplate that should hold a slot's marker: one that already carries it wins, so a marked mob keeps its marker, otherwise the first match in token order.
local function pickNameplate(slot, marker)
    local first
    for i = 1, ns.MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if UnitExists(unit) and ownsUnit(slot, unit) then
            if carriesMarker(unit, marker) then return unit end
            first = first or unit
        end
    end
    return first
end

-- A raid marker sits on one unit at a time, so each slot marks exactly one: the current target when it belongs to the slot, since that is the unit the player is looking at, otherwise one visible nameplate. Returns 1 when a unit holds the marker afterwards and 0 when nothing in view matches.
function ns.MarkNearbyForSlot(slot)
    local entry = ns.targets[slot]
    local marker = ns.FIND_MARKERS[slot]
    if not entry or not marker then return 0 end

    if UnitExists("target") and ownsUnit(slot, "target") then
        markUnit("target", marker)
        return 1
    end

    local unit = pickNameplate(slot, marker)
    if not unit then return 0 end
    markUnit(unit, marker)
    return 1
end

-- Every slot moved, so each entry needs its new marker pushed out to whatever is on screen.
function ns.RemarkAllSlots()
    local marked = 0
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then marked = marked + ns.MarkNearbyForSlot(slot) end
    end
    return marked
end
