-- Minimal WoW client stub: enough surface to load TargetFinder and drive its logic.
--
-- What this proves: the toc load order works, every cross-module ns.* call resolves,
-- and the pure logic (matching, macro building, list operations, menu assembly) behaves.
--
-- What it cannot prove: anything the real client decides. Secret-value activation,
-- /targetexact's own matching, /tm in a macro, nameplate availability, saved
-- variable persistence and every pixel of the UI still need an in-game pass.
--
-- Run with:  cd Tests && lua Tests.lua

-- Resolve the addon root from this file's own location, so the suite runs from any checkout.
local here = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./")
local ADDON = here .. "../"

-- shim the 5.1 globals WoW provides that newer Lua dropped
unpack = unpack or table.unpack
loadstring = loadstring or load

local log = {}
local function note(...) log[#log+1] = table.concat({...}, " ") end

-- === world state the tests manipulate ===
W = {
    units = {},            -- token -> {name=, player=bool, secret=bool, dead=bool, guid=}
    macros = {},           -- name -> {icon=, body=}
    macroOrder = {},
    macroCap = 120,
    actions = {},          -- slot -> {kind, id}
    chat = {},
    errors = {},
    secretsOn = false,
    nilChecks = 0,         -- canaccessvalue calls that passed nil
    markCalls = 0,         -- SetRaidTarget calls
    readyCallbacks = {},   -- functions handed to Questie.API.RegisterOnReady
    questCallbacks = {},   -- functions handed to Questie.API.RegisterForQuestUpdates
    group = nil,           -- nil solo, "party" or "raid"
    leader = false,        -- the player leads the group
    assistant = false,     -- the player is a raid assistant
    created = {},          -- every frame CreateFrame returned, in order
    tooltip = {},          -- lines the GameTooltip_* helpers added
}

-- === frame stub ===
local function newRegion(kind)
    local r = {}
    r.kind = kind
    r.calls = {}
    local function noop(name)
        return function(self, ...) self.calls[#self.calls+1] = name; return self end
    end
    local meta = {}
    meta.__index = function(t, k)
        -- lowercase keys are data fields the addon sets itself, so an unset one reads as nil
        if type(k) == "string" and k:match("^%l") then return nil end
        -- record every widget method call, return a chainable no-op
        local f = function(self, ...)
            self.calls[#self.calls+1] = k
            if k == "GetSize" then return 22, 22 end
            if k == "GetStringWidth" or k == "GetStringHeight" or k == "GetTextWidth" then return 10 end
            if k == "IsShown" or k == "IsPlaying" or k == "HasFocus" or k == "IsEnabled" then return false end
            if k == "GetText" then return self.text or "" end
            if k == "GetParent" then return self.parent end
            if k == "GetBottom" then return 500 end
            return self
        end
        rawset(t, k, f)
        return f
    end
    setmetatable(r, meta)
    return r
end

function CreateFrame(kind, name, parent, template)
    local f = newRegion(kind)
    f.parent = parent
    f.frameName = name
    f.template = template
    f.scripts = {}
    f.events = {}
    f.textures = {}
    f.points = {}
    f.SetPoint = function(self, point, rel, relPoint, x, y)
        self.points[#self.points+1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        return self
    end
    f.ClearAllPoints = function(self) self.points = {}; return self end
    f.SetSize = function(self, w, h) self.width, self.height = w, h; return self end
    f.SetHeight = function(self, h) self.height = h; return self end
    f.SetWidth = function(self, w) self.width = w; return self end
    f.SetFrameStrata = function(self, strata) self.strata = strata; return self end
    f.SetScript = function(self, ev, fn) self.scripts[ev] = fn; return self end
    f.HookScript = function(self, ev, fn)
        local before = self.scripts[ev]
        self.scripts[ev] = function(...) if before then before(...) end; fn(...) end
        return self
    end
    f.GetScript = function(self, ev) return self.scripts[ev] end
    f.RegisterEvent = function(self, ev)
        self.events[ev] = true
        _G.__frames = _G.__frames or {}
        _G.__frames[self] = true
        return self
    end
    f.UnregisterEvent = function(self, ev) self.events[ev] = nil; return self end
    f.CreateTexture = function(self)
        local t = newRegion("Texture")
        t.SetTexture = function(s, path) s.texturePath = path; return s end
        t.points = {}
        t.SetPoint = function(s, point, rel, relPoint, x, y)
            s.points[#s.points+1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
            return s
        end
        t.SetAtlas = function(s, a) s.atlas = a; return s end
        t.Show = function(s) s.shown = true; return s end
        t.Hide = function(s) s.shown = false; return s end
        t.SetAlpha = function(s, a) s.alpha = a; return s end
        t.SetDesaturated = function(s, d) s.desaturated = d; return s end
        t.CreateAnimationGroup = function(s)
            local g = newRegion("AnimGroup")
            g.CreateAnimation = function() return newRegion("Anim") end
            g.IsPlaying = function() return false end
            return g
        end
        self.textures[#self.textures+1] = t
        return t
    end
    f.CreateFontString = function(self)
        local fs = newRegion("FontString")
        fs.SetText = function(s, v) s.text = v; return s end
        fs.SetFontObject = function(s, font) s.fontObject = font; return s end
        fs.points = {}
        fs.SetPoint = function(s, point, rel, relPoint, x, y)
            s.points[#s.points+1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
            return s
        end
        fs.SetWordWrap = function(s, v) s.wordWrap = v; return s end
        fs.GetStringWidth = function() return 10 end
        fs.GetStringHeight = function() return 10 end
        return fs
    end
    if kind == "EditBox" then
        f.SetFontObject = function(self, font) self.fontObject = font; return self end
        f.SetText = function(self, v) self.text = v; return self end
        f.GetText = function(self) return self.text or "" end
        f.HasFocus = function() return false end
    end
    -- W.mouseOver names the one frame under the cursor
    f.IsMouseOver = function(self) return W.mouseOver == self end
    f.SetAlpha = function(self, a) self.alpha = a; return self end
    f.SetEnabled = function(self, v) self.enabled = v; return self end
    f.IsEnabled = function(self) return self.enabled end
    f.IsShown = function(self) return self.shown == true end
    -- like the client, OnShow and OnHide fire only when the shown state changes
    local function setShown(self, v)
        v = v and true or false
        local changed = (self.shown == true) ~= v
        self.shown = v
        local script = changed and self.scripts[v and "OnShow" or "OnHide"]
        if script then script(self) end
        return self
    end
    f.Show = function(self) return setShown(self, true) end
    f.Hide = function(self) return setShown(self, false) end
    f.SetShown = setShown
    f.LockHighlight = function(self) self.locked = true; return self end
    f.UnlockHighlight = function(self) self.locked = false; return self end
    if kind == "Button" then
        f.SetText = function(self, v) self.text = v; return self end
    end
    if kind == "CheckButton" then
        f.SetChecked = function(self, v) self.checked = v; return self end
        f.GetChecked = function(self) return self.checked == true end
    end
    -- CheckboxWithLabelTemplate carries its label as .Text
    if template == "CheckboxWithLabelTemplate" then
        f.Text = f:CreateFontString()
    end
    -- the wardrobe's brown panel: its border, tile and four corner ornaments
    if template == "CollectionsBackgroundTemplate" then
        f.SetAllPoints = function(self, rel) self.allPoints = rel; return self end
        f.Bg = f:CreateTexture()
        f.NineSlice = CreateFrame("Frame", nil, f)
        f.NineSlice.shown = true
        for _, corner in ipairs({ "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }) do
            f[corner] = f:CreateTexture()
            f[corner].shown = true
        end
    end
    -- the help tip template: Init stores what it was given, the close button runs the acknowledge callback
    if template == "HelpTipTemplate" then
        f.Init = function(self, parent, info, relative) self.info, self.target = info, relative; return self end
        f.Acknowledge = function(self)
            local info = self.info
            self.info = nil
            self:Hide()
            if info and info.onAcknowledgeCallback then info.onAcknowledgeCallback() end
        end
    end
    -- Blizzard's proc glow carries its start animation
    if template == "ActionButtonSpellAlertTemplate" then
        f.ProcStartAnim = { Play = function(a) a.playing = true end, Stop = function(a) a.playing = false end }
    end
    -- ButtonFrameTemplate hands its content well out as .Inset, with PortraitFrameMixin's title and portrait setters
    if template == "ButtonFrameTemplate" then
        f.Inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
        f.Inset.Bg = f.Inset:CreateTexture()
        f.Inset.NineSlice = CreateFrame("Frame", nil, f.Inset)
        f.PortraitContainer = CreateFrame("Frame", nil, f)
        f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture()
        f.GetPortrait = function(self) return self.PortraitContainer.portrait end
        f.SetTitle = function(self, t) self.title = t; return self end
        f.SetPortraitToAsset = function(self, asset) self.portraitAsset = asset; return self end
    end
    W.created[#W.created+1] = f
    if name then _G[name] = f end
    return f
end

-- the toc's own metadata, read the way the client serves it
C_AddOns = {
    GetAddOnMetadata = function(name, field)
        if name ~= "TargetFinder" then return nil end
        for raw in io.lines(ADDON .. "TargetFinder.toc") do
            local key, value = raw:gsub("\r", ""):match("^## ([%w%-]+): (.*)$")
            if key == field then return value end
        end
    end,
}

function UnitExists(u) return W.units[u] ~= nil end
function UnitName(u) local x = W.units[u]; return x and x.name end
function UnitIsPlayer(u) local x = W.units[u]; return x ~= nil and x.player == true end
-- a comparison under restriction returns a secret boolean, and testing one raises in tainted code
function UnitIsUnit(a, b)
    local x = W.units[a]
    if x and x.comparisonSecret then error("attempt to test a secret boolean") end
    return a == b
end
function UnitIsFriend(a, b) local x = W.units[b]; return x ~= nil and x.friend == true end
function UnitInParty(u) local x = W.units[u]; return x ~= nil and x.party == true end
function UnitInRaid(u) local x = W.units[u]; return x ~= nil and x.raid == true end
function UnitIsDead(u) local x = W.units[u]; return x ~= nil and x.dead == true end
-- one GUID per token and name, so the same mob seen through two tokens only matches when a test says so
function UnitGUID(u) local x = W.units[u]; return x and (x.guid or ("Creature-" .. u .. "-" .. x.name)) end
function IsInGroup() return W.group ~= nil end
function IsInRaid() return W.group == "raid" end
function UnitIsGroupLeader() return W.leader == true end
function UnitIsGroupAssistant() return W.assistant == true end

-- unit token -> marker index; markerSecret makes the read come back as a secret
W.markers = {}
function SetRaidTarget(unit, index)
    W.markCalls = W.markCalls + 1
    W.lastMark = { unit = unit, index = index }
    W.markers[unit] = index
end
function GetRaidTargetIndex(unit)
    if W.markerSecret then return { __secret = true } end
    return W.markers[unit]
end
function UnitCanAttack(_, u) local x = W.units[u]; return x ~= nil and x.hostile == true end
-- W.restricted holds the active restriction types
W.restricted = {}
Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return W.restricted[kind] == true end }
RAID_TARGET_1, RAID_TARGET_2, RAID_TARGET_3, RAID_TARGET_4 = "Star", "Circle", "Diamond", "Triangle"
RAID_TARGET_5, RAID_TARGET_6, RAID_TARGET_7, RAID_TARGET_8 = "Moon", "Square", "Cross", "Skull"

function InCombatLockdown() return W.inCombat == true end

-- character macros sit after the 120 account slots, as in the client
function GetMacroIndexByName(n)
    for i, name in ipairs(W.macroOrder) do
        if name == n then return W.macros[n].perCharacter and 120 + i or i end
    end
    return 0
end
-- at the cap the stub raises, the harder of the two ways the client may refuse
function CreateMacro(n, icon, body, perCharacter)
    if #W.macroOrder >= W.macroCap then error("macro limit reached") end
    W.macroOrder[#W.macroOrder+1] = n
    W.macros[n] = { icon = icon, body = body, perCharacter = perCharacter }
    return GetMacroIndexByName(n)
end
-- the macro book, reduced to the tab, the selection, the large icon and the hooks the addon sets
function ShowMacroFrame()
    if not MacroFrame then
        MacroFrame = {
            hooks = {},
            ChangeTab = function(self, tab) self.tab = tab end,
            SelectMacro = function(self, index) self.selected = index end,
            GetSelectedIndex = function(self) return self.selected end,
            GetMacroDataIndex = function(self, index) return (self.tab == 2 and 120 or 0) + index end,
            IsShown = function(self) return self.shown == true end,
            HookScript = function(self, script, fn) self.hooks[script] = fn end,
            SelectedMacroButton = CreateFrame("CheckButton"),
        }
    end
    MacroFrame.shown = true
end
function HideMacroFrame()
    MacroFrame.shown = false
    if MacroFrame.hooks.OnHide then MacroFrame.hooks.OnHide(MacroFrame) end
end
function GetMacroInfo(index)
    for i, name in ipairs(W.macroOrder) do
        if (W.macros[name].perCharacter and 120 + i or i) == index then return name end
    end
end
-- the post-hook runs after the original, like the client's
function hooksecurefunc(t, key, fn)
    local original = t[key]
    t[key] = function(...) local r = original(...); fn(...); return r end
end
function EditMacro(i, n, icon, body) W.macros[n].icon, W.macros[n].body = icon, body end
function GetActionInfo(slot) local a = W.actions[slot]; if a then return a.kind, a.id end end
function PickupMacro(index) W.cursorMacro = index end

function print(...) W.chat[#W.chat+1] = table.concat({...}, " ") end
tinsert = table.insert

-- the argument is Nilable = false, so nil raises like the client is expected to
canaccessvalue = function(v)
    if v == nil then
        W.nilChecks = W.nilChecks + 1
        error("bad argument #1 to 'canaccessvalue'")
    end
    return not (W.secretsOn and type(v) == "table" and v.__secret)
end

C_Secrets = {
    ShouldUnitIdentityBeSecret = function(u)
        local x = W.units[u]; return (x ~= nil and x.secret == true)
    end,
    ShouldUnitComparisonBeSecret = function(a)
        local x = W.units[a]; return (x ~= nil and x.comparisonSecret == true)
    end,
}

C_Timer = { After = function(_, fn) W.timers = W.timers or {}; W.timers[#W.timers+1] = fn end }
function RunTimers() local t = W.timers or {}; W.timers = {}; for _, fn in ipairs(t) do fn() end end

-- quest progress must come from Questie, so the native quest log refuses to be read
C_QuestLog = { GetQuestObjectives = function() error("native quest log read") end }
C_Map = { GetBestMapForUnit = function() return nil end }
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
UNKNOWN = "Unknown"
UIParent = CreateFrame("Frame")
UISpecialFrames = {}
SlashCmdList = {}
UIErrorsFrame = { AddMessage = function(_, m) W.errors[#W.errors+1] = m end }
GameTooltip = CreateFrame("Frame")
function GameTooltip_Hide() GameTooltip:Hide() end
MacroFrame = nil
Menu = { ModifyMenu = function(tag, cb) W.menuHooks = W.menuHooks or {}; W.menuHooks[tag] = cb end }
-- menu element descriptions: kind, text, callback and the tooltip function SetTooltip hands over
local function menuElement(kind, text, callback)
    return { kind = kind, text = text, fn = callback, SetTooltip = function(self, fn) self.tooltip = fn end }
end
MenuUtil = {
    CreateTitle = function(text) return menuElement("title", text) end,
    CreateButton = function(text, callback) return menuElement("button", text, callback) end,
    CreateDivider = function() return menuElement("divider") end,
}
-- the addon link pieces and the EventRegistry event Blizzard fires for an addon link click
LinkTypes = { AddOn = "addon" }
LinkUtil = { FormatLink = function(kind, text, data) return "|H" .. kind .. ":" .. data .. "|h" .. text .. "|h" end }
EventRegistry = {
    callbacks = {},
    RegisterCallback = function(self, event, fn, owner) self.callbacks[event] = function(...) fn(owner, ...) end end,
}
-- Blizzard's help tip: the pieces the addon reads, and a template whose close button acknowledges
HelpTip = { width = 226, ButtonStyle = { None = 0, Okay = 1, Close = 2 }, Point = { RightEdgeCenter = 8 } }
ADD = "Add"
CLEAR_ALL = "Clear All"
PRESS_TAB = "Press Tab"
ICON_LIST = {}
for i = 1, 8 do ICON_LIST[i] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":" end
-- the font objects behind the design system's roles; distinct tables so a test can tell the roles apart
GameFontNormal = { name = "GameFontNormal" }
GameFontHighlight = { name = "GameFontHighlight" }
GameFontDisable = { name = "GameFontDisable" }
GameFontNormalLarge = { name = "GameFontNormalLarge" }
-- MagicButton_OnLoad only adjusts anchors that exist when it runs, so record how many there were
function MagicButton_OnLoad(b) b.magicAnchors = #b.points end
-- ButtonFrameTemplate's attic and button bar helpers
function ButtonFrameTemplate_HideAttic(f) f.atticHeight = -PANEL_INSET_TOP_OFFSET end
function FrameTemplate_SetAtticHeight(f, h) f.atticHeight = h end
function ButtonFrameTemplate_HideButtonBar(f) f.buttonBarHidden = true end
function FrameTemplate_SetButtonBarHeight(f, h) f.buttonBarHeight = h end
PANEL_INSET_LEFT_OFFSET = 4
PANEL_INSET_RIGHT_OFFSET = -6
PANEL_INSET_BOTTOM_OFFSET = 4
PANEL_INSET_BOTTOM_BUTTON_OFFSET = 26
PANEL_INSET_TOP_OFFSET = -24
PANEL_INSET_ATTIC_OFFSET = -60
-- Blizzard builds these from C_UIColor.GetColors() at load; only the methods the addon calls are stubbed
local function colorObject(hex, r, g, b)
    return {
        WrapTextInColorCode = function(_, text) return "|cff" .. hex .. text .. "|r" end,
        GetRGB = function() return r, g, b end,
    }
end
NORMAL_FONT_COLOR = colorObject("ffd100", 1, 0.82, 0)
HIGHLIGHT_FONT_COLOR = colorObject("ffffff", 1, 1, 1)
GREEN_FONT_COLOR = colorObject("20ff20", 0.125, 1, 0.125)
WARNING_FONT_COLOR = colorObject("ff7f00", 1, 0.5, 0)
YELLOW_FONT_COLOR = colorObject("ffff00", 1, 1, 0)
RED_FONT_COLOR = colorObject("ff2020", 1, 0.125, 0.125)
GRAY_FONT_COLOR = colorObject("808080", 0.5, 0.5, 0.5)
LIGHTGRAY_FONT_COLOR = colorObject("bfbfbf", 0.75, 0.75, 0.75)
local function tooltipLine(kind)
    return function(_, text) W.tooltip[#W.tooltip+1] = kind .. ":" .. tostring(text) end
end
GameTooltip_SetTitle = function(_, text) W.tooltip = { "title:" .. tostring(text) } end
GameTooltip_AddNormalLine = tooltipLine("normal")
GameTooltip_AddInstructionLine = tooltipLine("instruction")
GameTooltip_AddHighlightLine = tooltipLine("highlight")
-- Blizzard_SharedXMLBase/TextureUtil.lua; the stub only keeps the angle
function SetClampedTextureRotation(texture, degrees) texture.rotation = degrees end
GameTooltip_AddDisabledLine = tooltipLine("disabled")
GameTooltip_AddErrorLine = tooltipLine("error")

-- Blizzard's addon menu; RegisterAddon only appends, like AddonCompartmentMixin:RegisterAddon
AddonCompartmentFrame = { registeredAddons = {} }
function AddonCompartmentFrame:RegisterAddon(data) self.registeredAddons[#self.registeredAddons+1] = data end

-- LibDBIcon's compartment entry hands Blizzard's menu click to the data object, as LibDBIcon-1.0.lua does
local function addToCompartment(_, name)
    local obj = W.ldbObject
    AddonCompartmentFrame:RegisterAddon({
        text = name,
        icon = obj.icon,
        func = function(_, menuInputData, menu) obj.OnClick(menu, menuInputData.buttonName) end,
    })
end

-- LibStub with the two libraries the launcher pulls
local libs = {
    ["LibDataBroker-1.1"] = { NewDataObject = function(_, _, o) return o end },
    ["LibDBIcon-1.0"] = {
        IsRegistered = function() return W.ldbObject ~= nil end,
        Register = function(_, _, obj) W.ldbObject = obj end,
        AddButtonToCompartment = addToCompartment,
        Show = function() W.minimapShown = true end,
        Hide = function() W.minimapShown = false end,
    },
}
LibStub = setmetatable({}, { __call = function(_, n) return libs[n] end })

-- the libraries the stub above stands in for; every other toc file loads from disk
local STUBBED = {
    ["Libs/LibStub/LibStub.lua"] = true,
    ["Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"] = true,
    ["Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"] = true,
    ["Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"] = true,
}

-- === load the addon exactly as the toc orders it ===
local ns = {}
local files = {}
for raw in io.lines(ADDON .. "TargetFinder.toc") do
    local line = raw:gsub("\r", "")
    if line ~= "" and not line:match("^##") and line:match("%.lua$") then
        files[#files+1] = (line:gsub("\\", "/"))
    end
end

local loaded = {}
for _, rel in ipairs(files) do
    if not STUBBED[rel] then
        local chunk, err = loadfile(ADDON .. rel)
        if not chunk then error("LOAD FAIL " .. rel .. ": " .. tostring(err)) end
        local ok, e = pcall(chunk, "TargetFinder", ns)
        if not ok then error("RUN FAIL " .. rel .. ": " .. tostring(e)) end
        loaded[#loaded+1] = rel
    end
end

print("loaded " .. #loaded .. " addon and library files in toc order")
_G.ns = ns
_G.W = W
