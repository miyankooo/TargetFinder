local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

-- Shared constants and the addon's one chat voice.

ns.ADDON_NAME = "Target Finder"

ns.FIND_MACRO = "FIND"
ns.FIND_ICON = "Ability_Hunter_SniperShot"
ns.ASSIST_MACRO = "ASSIST"
ns.ASSIST_ICON = "Ability_DualWield"

ns.MAX_TARGETS = 8
ns.MAX_SUGGESTIONS = 8
ns.MIN_QUERY_LENGTH = 2

-- The documented nameplate token range. Tokens only resolve while a nameplate is actually shown.
ns.MAX_NAMEPLATES = 40

-- Slot order is priority order, and each slot owns one raid marker for its whole life so a marked mob keeps meaning the same thing.
ns.FIND_MARKERS = { 8, 6, 2, 1, 7, 4, 3, 5 }

-- Ascending value is ascending priority, so a lower number wins when two quests claim the same NPC. Every saved entry stores its kind, so the values never renumber.
--   KILL  mobs that count for a kill objective
--   DROP  mobs that drop a required quest item
--   GIVER quest start and turn-in NPCs
ns.KIND_KILL = 1
ns.KIND_DROP = 2
ns.KIND_GIVER = 4

-- The toc's IconTexture, shared by the panel portrait and the minimap button so both read as this addon.
ns.ADDON_ICON = 132212
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
