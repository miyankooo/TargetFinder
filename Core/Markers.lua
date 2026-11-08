local _, ns = ...

-- Apply Raid Markers: FIND gives each listed unit it finds the marker of its row. Row 1 takes the skull, then down Blizzard's marker order: cross, square, moon, triangle, diamond, circle and star. Core/Macro.lua writes the /tm lines.
ns.SLOT_MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1 }

-- In a raid only the leader and assistants mark. In a party marks belong to the leader, so FIND never moves a marker someone else placed. UnitIsGroupLeader is SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:2039), so a hidden answer counts as no.
function ns.CanMark()
    if not IsInGroup() then return true end
    if ns.IdentitySecret("player") then return false end
    if UnitIsGroupLeader("player") then return true end
    return IsInRaid() and UnitIsGroupAssistant("player")
end

-- The Apply Raid Markers box: FIND is rewritten at once with or without its marker lines.
function ns.SetRaidMarkers(on)
    TargetFinderCharDB.raidMarkers = on
    ns.WriteFinderMacro()
end
