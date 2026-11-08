local addonName, ns = ...

-- The first load on an account says what Target Finder does and names its three ways in: the window, the target frame's right-click menu and /tf. Its link opens the window.

-- Blizzard reserves the addon link type for addons and hands every click on one to all of them through one EventRegistry event (ItemRefHandlersShared.lua:279-282). Gold is the colour of Blizzard's own action links in chat.
local LINK = LinkTypes.AddOn .. ":" .. addonName

function ns.PrintWelcome()
    local link = NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink(LinkTypes.AddOn, "[" .. ns.title .. "]", addonName))
    ns.Print("One FIND macro targets the NPCs your quests need, plus any NPC you add. Open the " .. link
        .. " window or type /tf to add your first NPC, or right-click a portrait and pick Track. Type /tf help for every command.")
end

-- /tf intro: the welcome line now, and the macro book tip again the next time it opens on FIND.
function ns.ReplayIntro()
    ns.db.tipSeen = nil
    ns.PrintWelcome()
end

-- Another addon's link may come from a line kept from restricted content, so it is checked before the comparison.
EventRegistry:RegisterCallback("SetItemRef", function(_, link)
    if ns.CanAccess(link) and link == LINK then ns.ShowPanel() end
end, ns)
