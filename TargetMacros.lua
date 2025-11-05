-- Update FIND and MARK macros for a target or add a new target

local YELLOW_LIGHT_LUA = "|cFFFDE89B"
local WHITE_LUA = "|cFFFFFFFF"

local MARK_ICON = "Ability_Hunter_MarkedForDeath"
local FIND_ICON = "Ability_Hunter_SniperShot"

local function updateTargetMacros(targetInput, addMode)
	local macroFind = "FIND"
	local macroMark = "MARK"
	local macroIndexFind = GetMacroIndexByName(macroFind)
	local macroIndexMark = GetMacroIndexByName(macroMark)
	local macroBodyFind = macroIndexFind > 0 and GetMacroBody(macroFind) or ""
	local macroBodyMark = macroIndexMark > 0 and GetMacroBody(macroMark) or ""
	local targetName

	if targetInput and targetInput ~= "" then
		targetName = targetInput
	else
		targetName = UnitName("target")
		if not targetName then
			print(YELLOW_LIGHT_LUA .. "[Find]:|r No target selected.")
			return
		end
	end

	local existingTargets = {}
	for t in macroBodyFind:gmatch("/target ([^\n]+)") do
		table.insert(existingTargets, t)
	end

	if addMode then
		for _, existingTarget in ipairs(existingTargets) do
			if existingTarget == targetName then
				print(YELLOW_LIGHT_LUA .. "[Find]:|r " .. targetName .. " is already in the list.")
				return
			end
		end
		if #existingTargets >= 3 then
			print(YELLOW_LIGHT_LUA .. "[Find]:|r Maximum of 3 targets reached.")
			return
		end
		if macroBodyFind == "" or not macroBodyFind:find("/cleartarget") then
			macroBodyFind = "/cleartarget\n/target " .. targetName
		else
			macroBodyFind = macroBodyFind:gsub("\n/run .+", "") .. "\n/target " .. targetName
		end
	else
		macroBodyFind = "/cleartarget\n/target " .. targetName
	end

	macroBodyMark = macroBodyFind .. "\n/run if UnitExists(\"target\") and not UnitIsDead(\"target\") and GetRaidTargetIndex(\"target\") == nil then SetRaidTarget(\"target\",8) end"

	if macroIndexFind > 0 then
		EditMacro(macroIndexFind, macroFind, FIND_ICON, macroBodyFind)
	else
		CreateMacro(macroFind, FIND_ICON, macroBodyFind, nil)
	end
	if macroIndexMark > 0 then
		EditMacro(macroIndexMark, macroMark, MARK_ICON, macroBodyMark)
	else
		CreateMacro(macroMark, MARK_ICON, macroBodyMark, nil)
	end

	local targetsDisplay = {}
	for t in macroBodyFind:gmatch("/target ([^\n]+)") do
		table.insert(targetsDisplay, t)
	end
	print(YELLOW_LIGHT_LUA .. "[Find]: " .. "|r" .. table.concat(targetsDisplay, ", ") .. ".")
end

local function updateAssistMacro(targetInput)
	local targetName
	if targetInput and targetInput ~= "" then
		targetName = targetInput
	else
		targetName = UnitName("target")
		if not targetName then
			print(YELLOW_LIGHT_LUA .. "[Assist]:|r No target selected.")
			return false
		end
	end
	local macroName = "ASSIST"
	local macroBody = "/assist " .. targetName
	local macroIndex = GetMacroIndexByName(macroName)
	if macroIndex > 0 then
		EditMacro(macroIndex, macroName, "Ability_DualWield", macroBody)
		print(YELLOW_LIGHT_LUA .. "[Assist]: " .. "|r" .. targetName .. ".")
	else
		CreateMacro(macroName, "Ability_DualWield", macroBody, nil)
		print(YELLOW_LIGHT_LUA .. "[Assist]: " .. "|r" .. targetName .. ".")
	end
	return true
end

SLASH_FINDMACRO1 = "/find"
SlashCmdList["FINDMACRO"] = function(msg)
	updateTargetMacros(msg, false)
end

SLASH_ALSOFINDMACRO1 = "/alsofind"
SlashCmdList["ALSOFINDMACRO"] = function(msg)
	updateTargetMacros(msg, true)
end

SLASH_ASSISTMACRO1 = "/assist"
SlashCmdList["ASSISTMACRO"] = updateAssistMacro
