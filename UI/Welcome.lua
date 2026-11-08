local addonName, ns = ...

-- The first load on an account says what Target Finder does and names its ways in: the window, /tf and the target frame's right-click menu. Its link opens the window.

-- Blizzard reserves the addon link type for addons and hands every click on one to all of them through one EventRegistry event (ItemRefHandlersShared.lua:279-282). Gold is the colour of Blizzard's own action links in chat.
local LINK = LinkTypes.AddOn .. ":" .. addonName

local function SurfaceLink(label)
    return NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink(LinkTypes.AddOn, "[" .. label .. "]", addonName))
end

-- What it does, then the window's link and /tf for the first step. A unit menu has no control a help tip could point at, so the welcome line names Track too.
function ns.PrintWelcome()
    ns.Print("One FIND macro targets the NPCs your quests need, plus any NPC or player you add. Open the " .. SurfaceLink(ns.title)
        .. " window or type /tf to add your first name, or right-click a portrait and pick Track.")
end

-- /tf intro: the welcome line now, and the macro book tip again, at once if the book shows FIND, else the next time it opens there.
function ns.ReplayIntro()
    ns.db.tipSeen = nil
    ns.PrintWelcome()
    ns.ShowFinderTip()
end

-- Another addon's link may come from a line kept from restricted content, so it is checked before the comparison.
EventRegistry:RegisterCallback("SetItemRef", function(_, link)
    if ns.CanAccess(link) and link == LINK then ns.ShowPanel() end
end, ns)

-- ADDON_LOADED marks the account's first run (TargetFinder.lua). The line waits for PLAYER_LOGIN, so it lands after the client's own load lines and the window can open from its link.
EventUtil.ContinueOnPlayerLogin(function()
    if ns.firstRun then ns.PrintWelcome() end
end)
