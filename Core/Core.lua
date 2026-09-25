local _, ns = ...

-- Shared constants and the addon's one chat voice. Everything here is client-independent; version differences live in Client.lua.

ns.ADDON_NAME = "Target Finder"

ns.FIND_MACRO = "FIND"
ns.FIND_ICON = "Ability_Hunter_SniperShot"
ns.ASSIST_MACRO = "ASSIST"
ns.ASSIST_ICON = "Ability_DualWield"

ns.MAX_TARGETS = 8
ns.MAX_SUGGESTIONS = 8
ns.MIN_QUERY_LENGTH = 2

-- Slot order is priority order, and each slot owns one raid marker for its whole life so a marked mob keeps meaning the same thing.
ns.FIND_MARKERS = { 8, 6, 2, 1, 7, 4, 3, 5 }

-- Ascending value is ascending priority, so a lower number wins when two quests claim the same NPC.
--   KILL  mobs that count for a kill objective
--   DROP  mobs that drop a required quest item
--   ASSOC mobs the quest otherwise references, such as talk or escort targets
--   GIVER quest start and turn-in NPCs
ns.KIND_KILL = 1
ns.KIND_DROP = 2
ns.KIND_ASSOC = 3
ns.KIND_GIVER = 4

-- Mirror the FIND macro icon so the minimap button reads as the same action.
ns.MINIMAP_ICON = "Interface\\Icons\\" .. ns.FIND_ICON
ns.MINIMAP_DEFAULT_POS = 215

local YELLOW = "|cffffff00"
local COLOR_END = "|r"

-- One tagged line per user-visible event, so the addon never writes to chat by any other route.
function ns.Announce(msg)
    print(YELLOW .. "[" .. ns.ADDON_NAME .. "]:" .. COLOR_END .. " " .. msg)
end

function ns.Trim(value)
    if not value then return nil end
    local stripped = value:match("^%s*(.-)%s*$")
    if stripped == "" then return nil end
    return stripped
end
