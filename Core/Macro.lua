local _, ns = ...

local MAX_TARGETS = ns.MAX_TARGETS
local MACRO_LIMIT = 255
local GLOW_SECONDS = 4

-- Write the macro, then read the index back instead of trusting a return value. CreateMacro is a C function with no generated documentation on either branch, and at the 120 account-macro cap it fails without telling the caller; the read-back settles it the same way on both clients.
local function setMacro(name, icon, body)
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        EditMacro(index, name, icon, body)
    else
        CreateMacro(name, icon, body, nil)
    end
    local written = GetMacroIndexByName(name)
    return written ~= nil and written > 0
end

-- One /target per slot, in REVERSE so slot 1 lands on the last line and wins. /target matches a name prefix and is a no-op when nothing matches, so the macro never clears the current target and never grabs an off-list mob. On overflow at the 255-character cap the lowest-priority lines drop off the top.
local function buildFindBody()
    local ordered = {}
    for slot = 1, MAX_TARGETS do
        if ns.targets[slot] then ordered[#ordered + 1] = ns.targets[slot] end
    end

    -- A comment-only body, so pressing FIND with an empty list leaves the current target alone instead of clearing it.
    if #ordered == 0 then return "// " .. ns.ADDON_NAME .. " - no targets" end

    local lines = {}
    for i = #ordered, 1, -1 do
        lines[#lines + 1] = "/target " .. ordered[i].name
    end
    local body = table.concat(lines, "\n")
    while #body > MACRO_LIMIT and #lines > 1 do
        table.remove(lines, 1)
        body = table.concat(lines, "\n")
    end
    return body
end

-- EditMacro and CreateMacro are blocked in combat, so a write made then is stashed and replayed on PLAYER_REGEN_ENABLED. The on-screen red notice fires once per combat session to keep chat clean.
local pendingMacros = {}
local notifiedCombat = false
local capWarned = false

local function warnMacroCap(name)
    if capWarned then return end
    capWarned = true
    ns.Announce("Could not write the " .. name .. " macro. The account macro list is full ("
        .. ns.AccountMacroCap() .. "); delete one and try again.")
end

-- Returns true when the macro was written, false when combat deferred it or the cap refused it.
local function queueMacro(name, icon, body)
    if InCombatLockdown() then
        pendingMacros[name] = { icon = icon, body = body }
        if not notifiedCombat then
            notifiedCombat = true
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(ns.ADDON_NAME .. ": leave combat to update macros.", 1.0, 0.1, 0.1)
            end
        end
        return false
    end
    if not setMacro(name, icon, body) then
        warnMacroCap(name)
        return false
    end
    capWarned = false
    return true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    notifiedCombat = false
    if next(pendingMacros) == nil then return end
    local queued = pendingMacros
    pendingMacros = {}
    for name, macro in pairs(queued) do
        if not setMacro(name, macro.icon, macro.body) then warnMacroCap(name) end
    end
    if ns.RefreshPanel then ns.RefreshPanel() end
end)

-- The single write path for the tracked list: persistence is implicit because the saved variable aliases the live table.
function ns.WriteFinderMacro()
    queueMacro(ns.FIND_MACRO, ns.FIND_ICON, buildFindBody())
    if ns.RefreshPanel then ns.RefreshPanel() end
end

local function isMacroOnBar(absIndex)
    if not absIndex or absIndex == 0 then return false end
    for slot = 1, ns.ACTION_SLOT_COUNT do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and id == absIndex then return true end
    end
    return false
end

local function buildGlow(button)
    if button.tfGlow then return button.tfGlow end
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetAtlas("bags-newitem", true)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", button, "CENTER")
    local w, h = button:GetSize()
    glow:SetSize(w * 1.4, h * 1.4)
    glow:SetAlpha(0)

    local anim = glow:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.35)
    fadeIn:SetOrder(1)
    local fadeOut = anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.35)
    fadeOut:SetOrder(2)

    glow.anim = anim
    button.tfGlow = glow
    return glow
end

-- A token per pulse, so a second pulse before the first expires does not let the older timer stop the newer glow.
local function pulseGlow(button)
    local glow = buildGlow(button)
    glow.token = (glow.token or 0) + 1
    local token = glow.token
    glow:Show()
    if not glow.anim:IsPlaying() then glow.anim:Play() end
    C_Timer.After(GLOW_SECONDS, function()
        if glow.token ~= token then return end
        glow.anim:Stop()
        glow:SetAlpha(0)
        glow:Hide()
    end)
end

-- SelectMacro's index is relative to the selected tab, so an account macro past the cap belongs to tab 2.
local function focusMacro(absIndex)
    if not MacroFrame then return end
    local accountCap = ns.AccountMacroCap()
    local tabID = absIndex <= accountCap and 1 or 2
    local relative = absIndex - (tabID == 1 and 0 or accountCap)
    MacroFrame:ChangeTab(tabID)
    MacroFrame:SelectMacro(relative, true)
    if MacroFrame.SelectedMacroButton then
        pulseGlow(MacroFrame.SelectedMacroButton)
    end
end

-- Open the macro book and pulse the macro, but only while it is still not on a bar, so the hint stops once the player has dragged it out.
function ns.HintMacro(name)
    if InCombatLockdown() then return end
    local absIndex = GetMacroIndexByName(name)
    if not absIndex or absIndex == 0 then return end
    if isMacroOnBar(absIndex) then return end

    ShowMacroFrame()
    if MacroFrame then
        focusMacro(absIndex)
    else
        C_Timer.After(0, function() focusMacro(absIndex) end)
    end
end

function ns.SetAssistTarget(name)
    if not name or name == "" then return end
    if not queueMacro(ns.ASSIST_MACRO, ns.ASSIST_ICON, "/assist " .. name) then return end
    ns.Announce("Assisting " .. name .. ".")
    ns.HintMacro(ns.ASSIST_MACRO)
end
