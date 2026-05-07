local addonName = ...

local ADDON_NAME = "FindAssist"
local YELLOW = "|cffffff00"
local WHITE = "|cffffffff"
local RESET = "|r"

local FIND_MACRO = "FIND"
local ASSIST_MACRO = "ASSIST"
local FIND_ICON = "Ability_Hunter_SniperShot"
local ASSIST_ICON = "Ability_DualWield"
local FIND_MARKERS = { 2, 6 } -- orange circle, blue square
local MAX_FIND_TARGETS = 2

local function announce(message)
	print(YELLOW .. "[" .. ADDON_NAME .. "]:" .. RESET .. " " .. WHITE .. message .. RESET)
end

local function trim(value)
	if not value then return nil end
	local stripped = value:match("^%s*(.-)%s*$")
	if stripped == "" then return nil end
	return stripped
end

local function resolveName(input)
	local fromInput = trim(input)
	if fromInput then return fromInput end
	if UnitExists("target") then
		return UnitName("target")
	end
	return nil
end

function FA_Mark(marker)
	if UnitExists("target") and not GetRaidTargetIndex("target") then
		SetRaidTarget("target", marker)
	end
end

local function setMacro(name, icon, body)
	local index = GetMacroIndexByName(name)
	if index and index > 0 then
		EditMacro(index, name, icon, body)
	else
		CreateMacro(name, icon, body, nil)
	end
end

local function readFindTargets()
	local index = GetMacroIndexByName(FIND_MACRO)
	if not index or index == 0 then return {} end
	local body = GetMacroBody(FIND_MACRO) or ""
	local targets = {}
	for entry in body:gmatch("/target%s+([^\n]+)") do
		table.insert(targets, entry)
	end
	return targets
end

local function writeFindMacro(targets)
	local lines = { "/cleartarget" }
	for slot, name in ipairs(targets) do
		table.insert(lines, "/target " .. name)
		local marker = FIND_MARKERS[slot]
		if marker then
			table.insert(lines, "/run FA_Mark(" .. marker .. ")")
		end
	end
	setMacro(FIND_MACRO, FIND_ICON, table.concat(lines, "\n"))
end

local function setFindTarget(name)
	if not name then
		announce("No target selected.")
		return
	end
	writeFindMacro({ name })
	announce("Find: " .. name .. ".")
end

local function addFindTarget(name)
	if not name then
		announce("No target selected.")
		return
	end
	local targets = readFindTargets()
	for _, existing in ipairs(targets) do
		if existing == name then
			announce(name .. " is already in Find: " .. table.concat(targets, ", ") .. ".")
			return
		end
	end
	if #targets >= MAX_FIND_TARGETS then
		announce("Find is full: " .. table.concat(targets, ", ") .. ".")
		return
	end
	table.insert(targets, name)
	writeFindMacro(targets)
	announce("Find: " .. table.concat(targets, ", ") .. ".")
end

local function clearFind()
	local index = GetMacroIndexByName(FIND_MACRO)
	if not index or index == 0 then
		announce("Find was already empty.")
		return
	end
	local before = readFindTargets()
	EditMacro(index, FIND_MACRO, FIND_ICON, "/cleartarget")
	if #before == 0 then
		announce("Find was already empty.")
	else
		announce("Find cleared (was " .. table.concat(before, ", ") .. ").")
	end
end

local function showFindList()
	local targets = readFindTargets()
	if #targets == 0 then
		announce("Find is empty.")
	else
		announce("Find: " .. table.concat(targets, ", ") .. ".")
	end
end

local function showHelp()
	announce("commands —")
	print(WHITE .. "  /find NAME       set Find target" .. RESET)
	print(WHITE .. "  /find add NAME   add to Find (max " .. MAX_FIND_TARGETS .. ")" .. RESET)
	print(WHITE .. "  /find clear      clear Find" .. RESET)
	print(WHITE .. "  /find list       show Find list" .. RESET)
	print(WHITE .. "  /find help       this message" .. RESET)
	print(WHITE .. "  /assist NAME     set Assist" .. RESET)
	print(WHITE .. "Right-click a unit frame for the same actions." .. RESET)
	print(WHITE .. "Markers only set when target has no mark; manual marks are preserved." .. RESET)
end

local function setAssistTarget(name)
	if not name then
		announce("No target selected.")
		return
	end
	setMacro(ASSIST_MACRO, ASSIST_ICON, "/assist " .. name)
	announce("Assist: " .. name .. ".")
end

SLASH_FINDASSIST_FIND1 = "/find"
SlashCmdList.FINDASSIST_FIND = function(msg)
	local arg = trim(msg)
	if arg then
		local first, rest = arg:match("^(%S+)%s*(.-)$")
		local cmd = first and first:lower() or ""
		if cmd == "help" or cmd == "?" then
			showHelp()
			return
		elseif cmd == "list" then
			showFindList()
			return
		elseif cmd == "clear" then
			clearFind()
			return
		elseif cmd == "add" then
			addFindTarget(resolveName(rest))
			return
		end
	end
	setFindTarget(resolveName(msg))
end

SLASH_FINDASSIST_ADDFIND1 = "/addfind"
SlashCmdList.FINDASSIST_ADDFIND = function(msg)
	addFindTarget(resolveName(msg))
end

SLASH_FINDASSIST_ASSIST1 = "/assist"
SlashCmdList.FINDASSIST_ASSIST = function(msg)
	setAssistTarget(resolveName(msg))
end

local UNIT_MENU_TAGS = {
	"MENU_UNIT_PLAYER",
	"MENU_UNIT_PARTY",
	"MENU_UNIT_RAID_PLAYER",
	"MENU_UNIT_ENEMY_PLAYER",
	"MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS",
	"MENU_UNIT_BOSS",
	"MENU_UNIT_ARENAENEMY",
	"MENU_UNIT_FRIEND",
}

local function appendMenu(_, rootDescription, contextData)
	if not contextData then return end
	local name = contextData.name
	if (not name or name == "") and contextData.unit then
		name = UnitName(contextData.unit)
	end
	if not name or name == "" or name == UNKNOWN then return end

	rootDescription:CreateDivider()
	rootDescription:CreateTitle(ADDON_NAME)
	rootDescription:CreateButton("Find", function() setFindTarget(name) end)
	rootDescription:CreateButton("Add to Find", function() addFindTarget(name) end)
	if #readFindTargets() > 0 then
		rootDescription:CreateButton("Clear Find", function() clearFind() end)
	end
	rootDescription:CreateButton("Assist", function() setAssistTarget(name) end)
end

if Menu and Menu.ModifyMenu then
	for _, tag in ipairs(UNIT_MENU_TAGS) do
		Menu.ModifyMenu(tag, appendMenu)
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		FindAssistDB = FindAssistDB or {}
		if not FindAssistDB.greeted then
			FindAssistDB.greeted = true
			announce("Loaded. Type /find help to get started, or right-click a unit frame for the FindAssist menu.")
		end
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
