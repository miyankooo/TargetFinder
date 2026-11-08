local _, ns = ...

-- Apply Raid Markers: a listed NPC the player targets, by FIND or any other way, gets its row's marker. Row 1 takes the skull, then down Blizzard's marker order: cross, square, moon, triangle, diamond, circle and star.
-- The addon sets the marker itself, because a macro cannot: /tm has no condition on a unit's name, and a /tm line per row would overflow the 255-character macro cap.
ns.SLOT_MARKERS = { 8, 7, 6, 5, 4, 3, 2, 1 }

-- In a raid only the leader and assistants mark. In a party marks belong to the leader, so Target Finder never moves a marker someone else placed. UnitIsGroupLeader is SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:2039), so a hidden answer counts as no.
function ns.CanMark()
    if not IsInGroup() then return true end
    if ns.IdentitySecret("player") then return false end
    if UnitIsGroupLeader("player") then return true end
    return IsInRaid() and UnitIsGroupAssistant("player")
end

-- SetRaidTarget is HasRestrictions on Forever (RaidMarkersDocumentation.lua:116), and which restriction blocks it is undocumented. Any active one skips the call, so it never raises a blocked-action error.
local function restricted()
    for _, kind in pairs(Enum.AddOnRestrictionType) do
        if C_RestrictedActions.IsAddOnRestrictionActive(kind) then return true end
    end
    return false
end

-- The same units /tm [harm,nodead] marks: a living enemy NPC.
local function markable(unit)
    return UnitExists(unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit)
end

function ns.MarkTarget()
    if not TargetFinderCharDB.raidMarkers or not markable("target") then return end
    local slot = ns.SlotForName(ns.ReadableName("target"))
    if not slot or not ns.CanMark() or restricted() then return end

    -- Setting the marker a unit already carries takes it off, so an unchanged marker is left alone, as /tm's "!" does (SlashCommands.lua:1457-1463). GetRaidTargetIndex has SecretReturns, so an unreadable answer skips the mark.
    local marker = ns.SLOT_MARKERS[slot]
    local current = GetRaidTargetIndex("target")
    if not ns.CanAccess(current) or current == marker then return end
    SetRaidTarget("target", marker)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function() ns.MarkTarget() end)
