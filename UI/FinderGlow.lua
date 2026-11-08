local _, ns = ...

-- Blizzard's proc glow (ActionButtonSpellAlertTemplate, Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml) around the macro book's large icon, the one the player drags FIND from. The glow is the addon's own frame laid over that button, sized and centred as GetAlertFrame does it. ActionButtonSpellAlertManager is not used, because it stores its frame on Blizzard's button and the button in its own table, which taints both.
local GLOW_SCALE = 1.4

local glow
local active = false

-- The large icon shows whichever macro is selected, so the glow only shows while that is FIND. GetSelectedIndex and GetMacroDataIndex only read the selector (Blizzard_MacroUI.lua:262 and 310).
local function finderSelected()
    local index = MacroFrame:GetSelectedIndex()
    if not index then return false end
    return GetMacroInfo(MacroFrame:GetMacroDataIndex(index)) == ns.FIND_MACRO
end

local function update()
    glow:SetShown(active and MacroFrame:IsShown() and finderSelected())
end

local function stop()
    active = false
    glow:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
    glow:Hide()
end

local function build()
    local button = MacroFrame.SelectedMacroButton
    glow = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    local width, height = button:GetSize()
    glow:SetSize(width * GLOW_SCALE, height * GLOW_SCALE)
    glow:SetPoint("CENTER", button, "CENTER")

    -- The template's OnLoad loops the glow once the start animation ends, and its OnHide stops the loop.
    glow:HookScript("OnShow", function(self) self.ProcStartAnim:Play() end)
    glow:HookScript("OnHide", function(self) self.ProcStartAnim:Stop() end)

    -- The glow ends for good once FIND lands on a bar or the macro book closes.
    glow:SetScript("OnEvent", function()
        if ns.FinderOnBar() then stop() end
    end)
    MacroFrame:HookScript("OnHide", stop)

    -- A secure post-hook, so picking another macro hides the glow and picking FIND again brings it back.
    hooksecurefunc(MacroFrame, "SelectMacro", update)
end

-- ns.ShowFinder calls this once the macro book shows FIND.
function ns.GlowFinder()
    if not MacroFrame then return end
    if not glow then build() end
    active = true
    glow:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    update()
end
