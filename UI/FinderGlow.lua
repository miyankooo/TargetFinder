local _, ns = ...

-- The macro book callout for FIND: Blizzard's proc glow around the large icon the player drags FIND from, plus the addon's one help tip beside it. Both show while the macro book shows FIND and FIND sits on no bar.

-- Blizzard's proc glow on a Blizzard button the player should use or drag: an own ActionButtonSpellAlertTemplate
-- frame 1.4 times the button's size, as GetAlertFrame sizes it. Never ActionButtonSpellAlertManager, which stores its
-- frame on Blizzard's button and in its own table.
-- The template's OnLoad loops the glow once the start animation ends, and its OnHide stops the loop.
local function CreateProcGlow(button)
    local glow = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    local width, height = button:GetSize()
    glow:SetSize(width * 1.4, height * 1.4)
    glow:SetPoint("CENTER")
    glow:HookScript("OnShow", function(self) self.ProcStartAnim:Play() end)
    glow:HookScript("OnHide", function(self) self.ProcStartAnim:Stop() end)
    glow:Hide()
    return glow
end

-- The help tip is an own HelpTipTemplate frame, never HelpTip:Show, which takes a frame from Blizzard's shared pool and taints the help tips Blizzard shows later. Closing it or placing FIND marks it seen for the account, and /tf intro clears that. Unlike the recipe's AttachTip it does not follow its target's OnShow: the large icon shows every selected macro, so update() below shows the tip only while it shows FIND.
local TIP_TEXT = "Drag FIND to an action bar to target the names on your Target Finder list."

local glow, tip
local active = false

local info = {
    text = TIP_TEXT,
    buttonStyle = HelpTip.ButtonStyle.Close,
    targetPoint = HelpTip.Point.RightEdgeCenter,
    onAcknowledgeCallback = function() ns.db.tipSeen = true end,
}

-- Reset comes before every Init: only Blizzard's pool resets a tip, and Init leaves acknowledged set (Blizzard_SharedXML/HelpTip.lua:419-431, 495, 687), so a tip closed once and brought back by /tf intro would count as seen when it merely hides with the macro book. Close hands a hidden tip to HelpTip:Release, which ignores a frame its pool does not own (HelpTip.lua:343-346).
local function showTip(target)
    if ns.db.tipSeen or (tip and tip:IsShown()) then return end
    if not tip then
        tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
        tip.width = HelpTip.width
        tip:SetWidth(tip.width)
    end
    tip:Reset()
    tip:Init(target, info, target)
    tip:Show()
end

-- The player used the feature: the tip goes for good, shown or not.
local function retireTip()
    if tip and tip.info then tip:Acknowledge() else ns.db.tipSeen = true end
end

-- A hide without the close button leaves the tip unseen, so it comes back at the next chance.
local function hideTip()
    if tip and tip:IsShown() then tip:Hide() end
end

-- The large icon shows whichever macro is selected, so the callout only shows while that is FIND. GetSelectedIndex and GetMacroDataIndex only read the selector (Blizzard_MacroUI.lua:262 and 310).
local function finderSelected()
    local index = MacroFrame:GetSelectedIndex()
    if not index then return false end
    return GetMacroInfo(MacroFrame:GetMacroDataIndex(index)) == ns.FIND_MACRO
end

local function update()
    local show = active and MacroFrame:IsShown() and finderSelected()
    glow:SetShown(show)
    if show then showTip(MacroFrame.SelectedMacroButton) else hideTip() end
end

local function stop()
    active = false
    glow:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
    glow:Hide()
    hideTip()
end

local function build()
    glow = CreateProcGlow(MacroFrame.SelectedMacroButton)

    -- FIND on a bar is what the tip asks for, so it counts as seen and the callout ends for good. Closing the macro book only ends it until the next time it opens on FIND.
    glow:SetScript("OnEvent", function()
        if not ns.FinderOnBar() then return end
        retireTip()
        stop()
    end)
    MacroFrame:HookScript("OnHide", stop)

    -- A secure post-hook, so picking another macro hides the callout and picking FIND again brings it back.
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

-- /tf intro: with the macro book already open on FIND the tip comes back now, otherwise the next time it opens there.
function ns.ShowFinderTip()
    if active then update() end
end
