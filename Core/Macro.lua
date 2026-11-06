local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS
local MACRO_LIMIT = 255
local CHARACTER_MACRO_CAP = Constants.MacroConsts.MAX_CHARACTER_MACROS
local ACCOUNT_MACRO_CAP = Constants.MacroConsts.MAX_ACCOUNT_MACROS

-- Bars 1-6 fill slots 1-72 and MultiBar5-7 add 145-180. An unused slot simply reads back nil.
local ACTION_SLOT_COUNT = 180

-- The marker FIND puts on its pick. The "!" prefix makes Blizzard's /tm handler leave a skull that is already there instead of toggling it off (Blizzard_ChatFrameBase/Shared/SlashCommands.lua:1457-1463).
local SKULL = 8

-- Write the macro, then read the index back. CreateMacro returns the new index, but it has no generated documentation and may raise at the cap, so the protected call and the read-back settle success. FIND is a character macro, because the list and the action bars are per character.
-- shortcut: GetMacroIndexByName finds an account macro of the same name first and edits it, upgrade to a character-range lookup if players report a shared FIND.
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

-- The single write path for the tracked list: persistence is implicit because the saved variable aliases the live table. Like RestedXP's targeting macro, FIND is created when it is missing and the list holds a name, quest fills included. editOnly marks the login and group-change writes, which only edit an existing FIND, because at login the character's macros may not be loaded yet and a create could leave two. quiet marks the writes the player did not make, which show no combat notice.
function ns.WriteFinderMacro(editOnly, quiet)
    if GetMacroIndexByName(ns.FIND_MACRO) > 0 or (not editOnly and next(ns.targets) ~= nil) then
        queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody(), quiet)
    end
    ns.RefreshPanel()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" then
        if canMark() ~= marking then ns.WriteFinderMacro(true, true) end
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

-- Whether FIND sits on any action bar, which picks the window's help line, the one chat reminder and whether the macro book opens.
function ns.FinderOnBar()
    local absIndex = GetMacroIndexByName(ns.FIND_MACRO)
    if absIndex == 0 then return false end
    for slot = 1, ACTION_SLOT_COUNT do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id == absIndex then return true end
    end
    return false
end

-- The window's icon hands FIND to the cursor, so the player drops it on a bar straight from the window. The first drag creates FIND, even for an empty list.
function ns.PickupFinder()
    if InCombatLockdown() then return end
    queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody())
    local index = GetMacroIndexByName(ns.FIND_MACRO)
    if index > 0 then PickupMacro(index) end
end

local reminded = false

-- Once per session, while FIND sits on no bar, a chat line ends with where to get it.
function ns.MacroHint()
    if reminded or ns.FinderOnBar() then return nil end
    reminded = true
    return "Drag FIND from your character macros (/m) to an action bar."
end

-- After Track or /tf add, the macro book opens on FIND while it sits on no bar yet, so the player can drag it out. In combat the write is still queued, so there is nothing to show yet. SelectMacro takes an index within the tab, and character macros follow the account ones (Blizzard_MacroUI.lua:164-178).
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
end
