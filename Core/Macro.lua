local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS
local MACRO_LIMIT = 255
local CHARACTER_MACRO_CAP = Constants.MacroConsts.MAX_CHARACTER_MACROS
local ACCOUNT_MACRO_CAP = Constants.MacroConsts.MAX_ACCOUNT_MACROS

-- Bars 1-6 fill slots 1-72 and MultiBar5-7 add 145-180. An unused slot simply reads back nil.
local ACTION_SLOT_COUNT = 180

-- Write the macro, then read the index back. CreateMacro returns the new index, but it has no generated documentation and may raise at the cap, so the protected call and the read-back settle success. FIND is a character macro, because the list and the action bars are per character. The second result says this call created it.
-- shortcut: GetMacroIndexByName finds an account macro of the same name first and edits it, upgrade to a character-range lookup if players report a shared FIND.
local function setMacro(name, icon, body)
    local index = GetMacroIndexByName(name)
    local existed = index and index > 0
    if existed then
        EditMacro(index, name, icon, body)
    else
        pcall(CreateMacro, name, icon, body, true)
    end
    local written = GetMacroIndexByName(name)
    local ok = written ~= nil and written > 0
    return ok, ok and not existed
end

-- FIND is RestedXP's targeting macro (RXPGuides v4.11.34 Targeting.lua:176-266, UpdateMacro), line for line: one /targetexact per row in REVERSE, so row 1 is the last line and wins; then RestedXP's /tm !<marker> on Forever, whose "!" leaves the marker on a unit that already carries it (SlashCommands.lua:1458-1464); then /targetlasttarget [dead], which steps back from a corpse to the match before it. A line that finds nothing leaves the target as it was, so FIND never clears it and never grabs an off-list mob. Like RestedXP, the lowest rows drop off the top until the targeting lines fit what the two closing lines leave of the 255-character cap.
-- Addons may not mark on Forever (SetRaidTarget raised ADDON_ACTION_FORBIDDEN in game on 2026-11-08, and RestedXP's UpdateMarker returns early there), so /tm, Blizzard's secure path, is the only way. The marker line is written only while Apply Raid Markers is ticked and the player may mark.
local TAIL = "\n/targetlasttarget [dead]"

-- Whether the last body carries the marker line, so a group change rewrites FIND only when that flips.
local marking

local function buildFindBody()
    local ordered = {}
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then ordered[#ordered + 1] = ns.targets[slot] end
    end

    marking = TargetFinderCharDB.raidMarkers == true and ns.CanMark()

    -- A comment-only body, so pressing FIND with an empty list leaves the current target alone instead of clearing it.
    if #ordered == 0 then return "// " .. ns.title .. " - no targets" end

    local closing = (marking and "\n/tm !" .. ns.FIND_MARKER or "") .. TAIL
    local lines = {}
    for i = #ordered, 1, -1 do
        lines[#lines + 1] = "/targetexact " .. ordered[i].name
    end
    local content = table.concat(lines, "\n")
    while #content > MACRO_LIMIT - #closing and #lines > 1 do
        table.remove(lines, 1)
        content = table.concat(lines, "\n")
    end
    return content .. closing
end

-- EditMacro and CreateMacro are blocked in combat, so a write made then is stashed and replayed on PLAYER_REGEN_ENABLED. The on-screen red notice fires once per combat session and only for the player's own changes, since quest updates land in nearly every fight.
local pendingMacros = {}
local notifiedCombat = false
local capWarned = false

local function warnMacroCap(name)
    if capWarned then return end
    capWarned = true
    ns.Print("Could not write the " .. name .. " macro, because this character has " .. CHARACTER_MACRO_CAP
        .. " macros. Delete one in the macro book (/m) and try again.")
end

-- The first FIND a character gets opens the macro book on it with its icon glowing and the help tip beside it, so the player sees the macro Target Finder wrote and where to drag it from. It runs a frame later, after the write that created FIND has refreshed the window. It adds no chat line, because a quest fill can create FIND at login.
local function introduceFinder()
    if TargetFinderCharDB.finderIntroduced then return end
    TargetFinderCharDB.finderIntroduced = true
    C_Timer.After(0, ns.ShowFinder)
end

local function writeMacro(name, icon, body)
    local ok, created = setMacro(name, icon, body)
    if not ok then
        warnMacroCap(name)
        return
    end
    capWarned = false
    if created and name == ns.FIND_MACRO then introduceFinder() end
end

local function queueMacro(name, icon, body, quiet)
    if InCombatLockdown() then
        pendingMacros[name] = { icon = icon, body = body }
        if not quiet and not notifiedCombat then
            notifiedCombat = true
            UIErrorsFrame:AddMessage(ns.title .. ": FIND updates after combat.", RED_FONT_COLOR:GetRGB())
        end
        return
    end
    writeMacro(name, icon, body)
end

-- The single write path for the tracked list: persistence is implicit because the saved variable aliases the live table. Like RestedXP's targeting macro, FIND is created when it is missing and the list holds a name, quest fills included. editOnly marks the login and group-change writes, which only edit an existing FIND, because at login the character's macros may not be loaded yet and a create could leave two. quiet marks the writes the player did not make, which show no combat notice.
function ns.WriteFinderMacro(editOnly, quiet)
    if GetMacroIndexByName(ns.FIND_MACRO) > 0 or (not editOnly and next(ns.targets) ~= nil) then
        queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody(), quiet)
    end
    ns.RefreshPanel()
end

-- Marker lines follow the group role, so a roster or leader change rewrites FIND when the player gains or loses the right to mark.
function ns.MarkingChanged()
    return (TargetFinderCharDB.raidMarkers == true and ns.CanMark()) ~= marking
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" then
        if ns.MarkingChanged() then ns.WriteFinderMacro(true, true) end
        return
    end
    notifiedCombat = false
    if next(pendingMacros) == nil then return end
    local queued = pendingMacros
    pendingMacros = {}
    for name, macro in pairs(queued) do
        writeMacro(name, macro.icon, macro.body)
    end
    ns.RefreshPanel()
end)

-- Whether FIND exists, which picks the window's first help line.
function ns.FinderExists()
    return GetMacroIndexByName(ns.FIND_MACRO) > 0
end

-- Whether FIND sits on any action bar, which picks the window's help line, the one chat reminder, whether the macro book opens and when its glow ends.
function ns.FinderOnBar()
    local absIndex = GetMacroIndexByName(ns.FIND_MACRO)
    if absIndex == 0 then return false end
    for slot = 1, ACTION_SLOT_COUNT do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id == absIndex then return true end
    end
    return false
end

-- The window's icon hands FIND to the cursor, so the player drops it on a bar straight from the window. The first drag creates FIND, even for an empty list. A FIND created this way is already in the player's hand, so it needs no introduction.
function ns.PickupFinder()
    if InCombatLockdown() then return end
    TargetFinderCharDB.finderIntroduced = true
    queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody())
    local index = GetMacroIndexByName(ns.FIND_MACRO)
    if index > 0 then PickupMacro(index) end
end

local reminded = false

-- Once per session, while FIND sits on no bar, a chat line ends with where to get it.
function ns.MacroHint()
    if reminded or ns.FinderOnBar() then return nil end
    reminded = true
    return "Drag FIND from the macro book (/m) to an action bar."
end

-- While FIND sits on no bar yet, the macro book opens on it with its icon glowing, so the player can drag it out: after it is first created, after Track and after /tf add. In combat the write is still queued, so there is nothing to show yet. SelectMacro takes an index within the tab, and character macros follow the account ones (Blizzard_MacroUI.lua:164-178).
function ns.ShowFinder()
    if InCombatLockdown() or ns.FinderOnBar() then return end
    local index = GetMacroIndexByName(ns.FIND_MACRO)
    if index == 0 then return end
    ShowMacroFrame()
    -- MacroFrame is only missing when Blizzard_MacroUI failed to load.
    if not MacroFrame then return end
    local character = index > ACCOUNT_MACRO_CAP
    MacroFrame:ChangeTab(character and 2 or 1)
    MacroFrame:SelectMacro(character and index - ACCOUNT_MACRO_CAP or index, true)
    ns.GlowFinder()
end
