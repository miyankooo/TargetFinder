local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- Shared constants and the addon's one chat voice.

ns.ADDON_NAME = "Target Finder"

ns.FIND_MACRO = "FIND"

-- The macro API takes the icon as a file ID, as Blizzard_MacroIconSelector.lua:103-109 passes it. 132212 is ADDON_ICON's file.
ns.FIND_ICON = 132212

ns.MAX_TARGETS = 8
ns.MAX_SUGGESTIONS = 8
ns.MIN_QUERY_LENGTH = 2

-- The documented nameplate token range. Tokens only resolve while a nameplate is actually shown.
ns.MAX_NAMEPLATES = 40

-- Ascending value is ascending priority, so a lower number wins when two quests claim the same NPC. A quest entry keeps its kind for its row icon.
--   KILL    mobs that count for a kill objective
--   DROP    mobs that drop a required quest item
--   TURNIN  the NPC a finished quest is handed in to
ns.KIND_KILL = 1
ns.KIND_DROP = 2
ns.KIND_TURNIN = 3

-- The toc's IconTexture, shared by the panel portrait and the minimap button so both read as this addon.
ns.ADDON_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
ns.MINIMAP_DEFAULT_POS = 215

-- One tagged line per user-visible event in the shared chat voice, so the addon never writes to chat by any other route.
function ns.Announce(msg)
    UI.Print(ns.ADDON_NAME, msg)
end

function ns.Trim(value)
    if not value then return nil end
    local stripped = value:match("^%s*(.-)%s*$")
    if stripped == "" then return nil end
    return stripped
end
