local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS
local MACRO_LIMIT = 255
local CHARACTER_MACRO_CAP = Constants.MacroConsts.MAX_CHARACTER_MACROS

-- Bars 1-6 fill slots 1-72 and MultiBar5-7 add 145-180. An unused slot simply reads back nil.
local ACTION_SLOT_COUNT = 180

-- The marker FIND puts on its pick. The "!" prefix makes Blizzard's /tm handler leave a skull that is already there instead of toggling it off (Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1457-1463).
local SKULL = 8

-- Write the macro, then read the index back. CreateMacro returns the new index, but it has no generated documentation and may raise at the cap, so the protected call and the read-back settle success. FIND is a character macro, because the list and the action bars are per character.
local function setMacro(name, icon, body)
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        EditMacro(index, name, icon, body)
    else
        pcall(CreateMacro, name, icon, body, true)
    end
    local written = GetMacroIndexByName(name)
    return written ~= nil and written > 0
end

-- In a raid only the leader and assistants mark. In a party marks belong to the leader, so FIND never moves a marker someone else placed. UnitIsGroupLeader is SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:2039), so a hidden answer counts as no.
local function canMark()
    if not IsInGroup() then return true end
    if ns.IdentitySecret("player") then return false end
    if UnitIsGroupLeader("player") then return true end
    return IsInRaid() and UnitIsGroupAssistant("player")
end

-- Whether the last body carries the marker line, so a group change rewrites FIND only when that flips.
local marking

-- RestedXP's targeting macro (RXPGuides Targeting.lua, UpdateMacro): one /targetexact per slot in REVERSE, so slot 1 is the last line and wins, then /targetlasttarget [dead] steps back from a corpse to the match before it. A line that finds nothing leaves the target as it was, so FIND never clears it and never grabs an off-list mob. The skull goes on through /tm, the secure path, because on Forever the addon may not call SetRaidTarget itself (HasRestrictions, RaidMarkersDocumentation.lua:116). On overflow at the 255-character cap the lowest-priority lines drop off the top.
local function buildFindBody()
    local ordered = {}
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then ordered[#ordered + 1] = ns.targets[slot] end
    end

    marking = canMark()

    -- A comment-only body, so pressing FIND with an empty list leaves the current target alone instead of clearing it.
    if #ordered == 0 then return "// " .. ns.ADDON_NAME .. " - no targets" end

    local tail = "\n/targetlasttarget [dead]"
    if marking then tail = tail .. "\n/tm [harm,nodead] !" .. SKULL end

    local lines = {}
    for i = #ordered, 1, -1 do
        lines[#lines + 1] = "/targetexact " .. ordered[i].name
    end
    local body = table.concat(lines, "\n") .. tail
    while #body > MACRO_LIMIT and #lines > 1 do
        table.remove(lines, 1)
        body = table.concat(lines, "\n") .. tail
    end
    return body
end

-- EditMacro and CreateMacro are blocked in combat, so a write made then is stashed and replayed on PLAYER_REGEN_ENABLED. The on-screen red notice fires once per combat session and only for the player's own changes, since quest updates land in nearly every fight.
local pendingMacros = {}
local notifiedCombat = false
local capWarned = false

local function warnMacroCap(name)
    if capWarned then return end
    capWarned = true
    ns.Announce("Could not write the " .. name .. " macro, because this character has " .. CHARACTER_MACRO_CAP
        .. " macros. Delete one in the macro book (/m) and try again.")
end

local function queueMacro(name, icon, body, quiet)
    if InCombatLockdown() then
        pendingMacros[name] = { icon = icon, body = body }
        if not quiet and not notifiedCombat then
            notifiedCombat = true
            UIErrorsFrame:AddMessage(ns.ADDON_NAME .. ": FIND updates after combat.", RED_FONT_COLOR:GetRGB())
        end
        return
    end
    if setMacro(name, icon, body) then
        capWarned = false
    else
        warnMacroCap(name)
    end
end

-- The single write path for the tracked list: persistence is implicit because the saved variable aliases the live table. editOnly marks a change the player did not make, such as a quest update or a group change. It only edits an existing FIND, so only the player's own action creates one and a write at login can never leave two.
function ns.WriteFinderMacro(editOnly)
    if not editOnly or GetMacroIndexByName(ns.FIND_MACRO) > 0 then
        queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody(), editOnly)
    end
    ns.RefreshPanel()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" then
        if canMark() ~= marking then ns.WriteFinderMacro(true) end
        return
    end
    notifiedCombat = false
    if next(pendingMacros) == nil then return end
    local queued = pendingMacros
    pendingMacros = {}
    for name, macro in pairs(queued) do
        if not setMacro(name, macro.icon, macro.body) then warnMacroCap(name) end
    end
    ns.RefreshPanel()
end)

-- Whether FIND sits on any action bar, which picks the window's help line and the one chat reminder.
function ns.FinderOnBar()
    local absIndex = GetMacroIndexByName(ns.FIND_MACRO)
    if absIndex == 0 then return false end
    for slot = 1, ACTION_SLOT_COUNT do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id == absIndex then return true end
    end
    return false
end

-- The window's icon hands FIND to the cursor, so the player drops it on a bar without opening the macro book. The first drag creates FIND.
function ns.PickupFinder()
    if InCombatLockdown() then return end
    ns.WriteFinderMacro()
    local index = GetMacroIndexByName(ns.FIND_MACRO)
    if index > 0 then PickupMacro(index) end
end

local reminded = false

-- Once per session, while FIND sits on no bar, a chat line ends with where to get it. The open window's help line says the same.
function ns.MacroHint()
    if reminded or ns.FinderOnBar() then return nil end
    reminded = true
    return "Drag FIND from the Target Finder window (/tf) to an action bar."
end
