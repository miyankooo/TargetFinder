local _, ns = ...

-- Apply Raid Markers: FIND marks the unit it targets with a cross, the marker RestedXP's targeting macro uses on Forever (RXPGuides Targeting.lua:242-246). Core/Macro.lua writes the /tm line.
ns.FIND_MARKER = 7

-- In a raid only the leader and assistants mark. In a party marks belong to the leader, so FIND never moves a marker someone else placed. UnitIsGroupLeader is SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:2039), so a hidden answer counts as no.
function ns.CanMark()
    if not IsInGroup() then return true end
    if ns.IdentitySecret("player") then return false end
    if UnitIsGroupLeader("player") then return true end
    return IsInRaid() and UnitIsGroupAssistant("player")
end

-- The Apply Raid Markers box: FIND is rewritten at once with or without its marker line.
function ns.SetRaidMarkers(on)
    TargetFinderCharDB.raidMarkers = on
    ns.WriteFinderMacro()
end
