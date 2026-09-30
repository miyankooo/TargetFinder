-- Minimal WoW client stub: enough surface to load TargetFinder and drive its logic.
--
-- What this proves: the toc load order works, every cross-module ns.* call resolves,
-- and the pure logic (matching, macro building, list operations, menu assembly) behaves.
--
-- What it cannot prove: anything the real client decides. Secret-value activation,
-- /target's own matching, raid marker permissions, nameplate availability, saved
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
    units = {},            -- token -> {name=, player=bool, secret=bool}
    marks = {},            -- token -> marker index
    macros = {},           -- name -> {icon=, body=}
    macroOrder = {},
    macroCap = 120,
    actions = {},          -- slot -> {kind, id}
    chat = {},
    errors = {},
    secretsOn = false,
    markersSecret = false, -- GetRaidTargetIndex hands out a secret
    nilChecks = 0,         -- canaccessvalue calls that passed nil
    markCalls = 0,         -- SetRaidTarget calls
    readyCallbacks = {},   -- functions handed to Questie.API.RegisterOnReady
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
            if k == "GetStringWidth" or k == "GetStringHeight" then return 10 end
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
    f.SetFrameStrata = function(self, strata) self.strata = strata; return self end
    f.SetScript = function(self, ev, fn) self.scripts[ev] = fn; return self end
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
        t.SetAtlas = function(s, a) s.atlas = a; return s end
        t.Show = function(s) s.shown = true; return s end
        t.Hide = function(s) s.shown = false; return s end
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
        fs.GetStringWidth = function() return 10 end
        fs.GetStringHeight = function() return 10 end
        return fs
    end
    if kind == "EditBox" then
        f.SetText = function(self, v) self.text = v; return self end
        f.GetText = function(self) return self.text or "" end
        f.HasFocus = function() return false end
    end
    f.SetEnabled = function(self, v) self.enabled = v; return self end
    f.IsEnabled = function(self) return self.enabled end
    f.IsShown = function(self) return self.shown == true end
    f.Show = function(self) self.shown = true; return self end
    f.Hide = function(self) self.shown = false; return self end
    f.SetShown = function(self, v) self.shown = v and true or false; return self end
    f.LockHighlight = function(self) self.locked = true; return self end
    f.UnlockHighlight = function(self) self.locked = false; return self end
    if kind == "Button" then
        f.SetText = function(self, v) self.text = v; return self end
    end
    -- ButtonFrameTemplate hands its content well out as .Inset, with PortraitFrameMixin's title and portrait setters
    if template == "ButtonFrameTemplate" then
        f.Inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
        f.SetTitle = function(self, t) self.title = t; return self end
        f.SetPortraitToAsset = function(self, asset) self.portraitAsset = asset; return self end
    end
    W.created[#W.created+1] = f
    if name then _G[name] = f end
    return f
end

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

local SECRET = { __secret = true }
function GetRaidTargetIndex(u)
    if W.markersSecret then return SECRET end
    return W.marks[u]
end
-- a raid marker lives on one unit at a time, so setting it elsewhere moves it
function SetRaidTarget(u, m)
    W.markCalls = W.markCalls + 1
    for other, marker in pairs(W.marks) do
        if marker == m then W.marks[other] = nil end
    end
    W.marks[u] = m
end
function SetRaidTargetIconTexture(tex, idx) tex.markerCell = idx end

function GetTime() W.clock = (W.clock or 0) + 10; return W.clock end
function InCombatLockdown() return W.inCombat == true end

function GetMacroIndexByName(n)
    for i, name in ipairs(W.macroOrder) do if name == n then return i end end
    return 0
end
function CreateMacro(n, icon, body)
    if #W.macroOrder >= W.macroCap then return nil end
    W.macroOrder[#W.macroOrder+1] = n
    W.macros[n] = { icon = icon, body = body }
    return #W.macroOrder
end
function EditMacro(i, n, icon, body) W.macros[n] = { icon = icon, body = body } end
function GetActionInfo(slot) local a = W.actions[slot]; if a then return a.kind, a.id end end
function ShowMacroFrame() W.macroFrameShown = true end

function IsShiftKeyDown() return false end
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
MacroFrame = nil
Menu = { ModifyMenu = function(tag, cb) W.menuHooks = W.menuHooks or {}; W.menuHooks[tag] = cb end }
ADD = "Add"
PRESS_TAB = "Press Tab"
GameFontHighlight = {}
-- MagicButton_OnLoad only adjusts anchors that exist when it runs, so record how many there were
function MagicButton_OnLoad(b) b.magicAnchors = #b.points end
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
GameTooltip_AddDisabledLine = tooltipLine("disabled")
GameTooltip_AddErrorLine = tooltipLine("error")

-- LibStub with just the two libraries the addon pulls at login
local libs = {
    ["LibDataBroker-1.1"] = { NewDataObject = function(_, _, o) return o end },
    ["LibDBIcon-1.0"] = { IsRegistered = function() return false end, Register = function(_, _, obj) W.ldbObject = obj end },
}
function LibStub(n) return libs[n] end

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
    if not rel:match("^Libs/") then
        local chunk, err = loadfile(ADDON .. rel)
        if not chunk then error("LOAD FAIL " .. rel .. ": " .. tostring(err)) end
        local ok, e = pcall(chunk, "TargetFinder", ns)
        if not ok then error("RUN FAIL " .. rel .. ": " .. tostring(e)) end
        loaded[#loaded+1] = rel
    end
end

print("loaded " .. #loaded .. " addon files in toc order")
_G.ns = ns
_G.W = W
