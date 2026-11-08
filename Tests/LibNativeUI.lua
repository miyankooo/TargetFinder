-- Offline smoke test for LibNativeUI-1.0. It loads the real LibStub and library against stubs of the
-- client and builds every component once. It proves the library's own logic and the template wiring it
-- asks for; how the templates look in game still needs an in-game pass.
--
-- Run from the TargetFinder folder:  lua Tests/LibNativeUI.lua

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local ROOT = here .. "../"

strmatch = string.match
tinsert = table.insert

local failures, passes = 0, 0
local function check(label, ok, detail)
    if ok then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL " .. label .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or ""))
    end
end

-- Text width model: 6 px per character on a 12 px line, wrapped at the font string's width.
local CHAR_WIDTH = 6

local function font(name, size)
    return { name = name, GetFont = function() return "Fonts\\FRIZQT__.TTF", size end }
end
GameFontNormal = font("GameFontNormal", 12)
GameFontHighlight = font("GameFontHighlight", 12)
GameFontDisable = font("GameFontDisable", 12)
GameFontNormalLarge = font("GameFontNormalLarge", 16)
GameFontNormalSmall = font("GameFontNormalSmall", 10)

local function colour(hex)
    return { WrapTextInColorCode = function(_, text) return "|cff" .. hex .. text .. "|r" end }
end
NORMAL_FONT_COLOR = colour("ffd100")
HIGHLIGHT_FONT_COLOR = colour("ffffff")
GRAY_FONT_COLOR = colour("808080")
GREEN_FONT_COLOR = colour("20ff20")
RED_FONT_COLOR = colour("ff2020")
WARNING_FONT_COLOR = colour("ff7f00")
YELLOW_FONT_COLOR = colour("ffff00")

FILTER = "Filter"
SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT = 6
UISpecialFrames = {}
SlashCmdList = {}

-- Regions keep their geometry and scripts as plain fields, so checks read them directly.
local Region = {}
Region.__index = Region

local function newRegion(kind, name, parent)
    return setmetatable({ kind = kind, name = name, parent = parent, points = {}, scripts = {}, shown = true,
        width = 0, height = 0 }, Region)
end

function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetName() return self.name end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(rel) self.allPoints = rel end
function Region:SetAtlas(atlas, useAtlasSize) self.atlas, self.useAtlasSize = atlas, useAtlasSize end
function Region:CreateTexture(name, layer)
    local texture = newRegion("Texture", name, self)
    texture.layer = layer
    return texture
end
function Region:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function Region:GetPoint(i)
    local p = self.points[i]
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(shown) self.shown = shown and true or false end
function Region:IsShown() return self.shown end
function Region:SetScript(event, fn) self.scripts[event] = fn end
function Region:GetScript(event) return self.scripts[event] end
function Region:SetFrameStrata(strata) self.strata = strata end
function Region:SetToplevel(on) self.toplevel = on end
function Region:SetClampedToScreen(on) self.clamped = on end
function Region:SetMovable(on) self.movable = on end
function Region:EnableMouse(on) self.mouse = on end
function Region:RegisterForDrag(button) self.dragButton = button end
function Region:StartMoving() self.moving = true end
function Region:StopMovingOrSizing() self.moving = false end
function Region:SetHitRectInsets(l, r, t, b) self.hitRect = { l, r, t, b } end
function Region:SetAutoFocus(on) self.autoFocus = on end
function Region:SetScrollChild(child) self.scrollChild = child end
function Region:SetFontObject(fontObject) self.fontObject = fontObject end
function Region:SetJustifyH(justify) self.justifyH = justify end
function Region:SetWordWrap(on) self.wordWrap = on end
function Region:GetTextColor() return 0.5, 0.5, 0.5 end
function Region:SetTextColor(r, g, b) self.color = { r, g, b } end
function Region:SetText(text) self.text = text end
function Region:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
function Region:GetText() return self.text end
function Region:GetStringWidth() return #(self.text or "") * CHAR_WIDTH end
function Region:GetStringHeight()
    local length = #(self.text or "") * CHAR_WIDTH
    if length == 0 then return 0 end
    local lineHeight = select(2, self.fontObject:GetFont())
    if self.width > 0 then return math.ceil(length / self.width) * lineHeight end
    return lineHeight
end
function Region:GetTextWidth() return #(self.text or "") * CHAR_WIDTH end
function Region:CreateFontString()
    local text = newRegion("FontString", nil, self)
    text.fontObject = GameFontNormal
    return text
end

-- Blizzard template setup, reduced to the keys and sizes the library relies on.
local templates = {}

-- The rock tile and its title streaks, which UI.CreateWindow keeps, and the inset's marble tile and
-- border, which it hides for the brown panel.
templates.ButtonFrameTemplate = function(f)
    f.Bg = newRegion("Texture", nil, f)
    f.TopTileStreaks = newRegion("Texture", nil, f)
    f.Inset = newRegion("Frame", nil, f)
    f.Inset.Bg = newRegion("Texture", nil, f.Inset)
    f.Inset.NineSlice = newRegion("Frame", nil, f.Inset)
    f.SetTitle = function(self, title) self.title = title end
    f.SetPortraitToAsset = function(self, asset) self.portrait = asset end
end

templates.DialogBorderTemplate = function(f) f.setAllPoints = true end

-- DialogHeaderMixin:Setup sizes the banner to the title plus headerTextPadding 64.
templates.DialogHeaderTemplate = function(f)
    f.Text = f:CreateFontString()
    f.Setup = function(self, text)
        self.Text:SetText(text)
        self:SetWidth(self.Text:GetStringWidth() + 64)
    end
end

templates.UIPanelCloseButtonNoScripts = function(f) f:SetSize(24, 24) end
templates.UIPanelCloseButton = function(f)
    f:SetSize(24, 24)
    f.scripts.OnClick = function(self) self.parent.blizzardHide = true end
end

templates.UIPanelButtonTemplate = function(f) f:SetSize(40, 22) end
templates.MagicButtonTemplate = function(f) f:SetSize(80, 22) end

-- CheckboxWithLabelTemplate: 30 x 29 minimal art, label GameFontNormalSmall at RIGHT + 3.
templates.CheckboxWithLabelTemplate = function(f)
    f:SetSize(30, 29)
    f.Text = f:CreateFontString()
    f.Text.fontObject = GameFontNormalSmall
    f.Text:SetPoint("LEFT", f, "RIGHT", 3, 0)
end

templates.InputBoxTemplate = function(f) f:SetSize(160, 20) end
templates.SearchBoxTemplate = function(f) f.Instructions = f:CreateFontString() end
templates.WowStyle1DropdownTemplate = function(f) f:SetSize(120, 25) end
templates.InsetFrameTemplate = function(f)
    f.Bg = newRegion("Texture", nil, f)
    f.NineSlice = newRegion("Frame", nil, f)
end
-- An inset with the collections tile, its shadow and four corner ornaments (SharedCollectionTemplates.xml).
templates.CollectionsBackgroundTemplate = function(f)
    templates.InsetFrameTemplate(f)
    f.BackgroundTile = newRegion("Texture", nil, f)
    for _, corner in ipairs({ "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }) do
        f[corner] = newRegion("Texture", nil, f)
    end
end
templates.MinimalSliderWithSteppersTemplate = function(f) f:SetSize(250, 40) end
templates.ScrollFrameTemplate = function() end

-- WowStyle1FilterDropdownTemplate: 135 x 18, text FILTER, resizeToText with padding 60, and the reset
-- behaviour of WowDropdownFilterBehaviorMixin.
templates.WowStyle1FilterDropdownTemplate = function(f)
    f:SetSize(135, 18)
    f.resizeToText = true
    f.ResetButton = newRegion("Button", nil, f)
    f.ResetButton.shown = false
    f.Text = f:CreateFontString()
    f.SetText = function(self, text)
        self.Text:SetText(text)
        if self.resizeToText then self:SetWidth(self.Text:GetStringWidth() + 60) end
    end
    f.SetDefaultCallback = function(self, fn) self.defaultCallback = fn end
    f.SetIsDefaultCallback = function(self, fn) self.isDefaultCallback = fn end
    f.ValidateResetState = function(self)
        if self.isDefaultCallback then self.ResetButton.shown = not self.isDefaultCallback() end
    end
    f.SetupMenu = function(self, generator)
        self.generator = generator
        self:ValidateResetState()
    end
    f.ResetButton.scripts.OnClick = function()
        if f.defaultCallback then f.defaultCallback() end
        f.ResetButton.shown = false
    end
    f:SetText(FILTER)
end

function CreateFrame(kind, name, parent, template)
    local f = newRegion(kind, name, parent)
    f.template = template
    if template then
        local setup = templates[template]
        if not setup then error("no stub for template " .. template) end
        setup(f)
    end
    if name then _G[name] = f end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
-- Blizzard's quarter turns swap a texture's size and texture coordinates (Blizzard_SharedXMLBase/TextureUtil.lua).
function SetClampedTextureRotation(texture, degrees) texture.rotation = degrees end
GameTooltip = CreateFrame("Frame", "GameTooltip")
function GameTooltip_Hide() GameTooltip:Hide() end
function GameTooltip_SetTitle(tooltip, text) tooltip.title = text end
function ButtonFrameTemplate_HideAttic(f) f.atticHidden = true end
function FrameTemplate_SetAtticHeight(f, h) f.atticHeight = h end
function ButtonFrameTemplate_HideButtonBar(f) f.buttonBarHidden = true end
function MagicButton_OnLoad(b) b.magicAnchors = #b.points end

local function load(path)
    local chunk, err = loadfile(ROOT .. path)
    if not chunk then error(err) end
    chunk()
end

load("Libs/LibStub/LibStub.lua")

-- The launcher's two libraries, reduced to the calls UI.CreateLauncher makes.
local LDB = LibStub:NewLibrary("LibDataBroker-1.1", 1)
function LDB:NewDataObject(name, object) self[name] = object; return object end
local LDBIcon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
LDBIcon.registered, LDBIcon.compartment, LDBIcon.visible = {}, {}, {}
function LDBIcon:IsRegistered(name) return self.registered[name] ~= nil end
function LDBIcon:Register(name, object, db)
    self.registered[name] = { object = object, db = db }
    self.visible[name] = not db.hide
end
function LDBIcon:AddButtonToCompartment(name) self.compartment[#self.compartment + 1] = name end
function LDBIcon:Show(name) self.visible[name] = true end
function LDBIcon:Hide(name) self.visible[name] = false end

load("Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua")
local UI = LibStub("LibNativeUI-1.0")
local _, minor = LibStub:GetLibrary("LibNativeUI-1.0")

local function onGrid(value) return value % UI.GRID == 0 end
local function isEscapable(name)
    for _, entry in ipairs(UISpecialFrames) do
        if entry == name then return true end
    end
    return false
end

-- Tokens
check("MINOR is 6", minor == 6, minor)
check("grid is 4", UI.GRID == 4 and UI.Snap(22) == 24 and UI.Snap(36) == 36)
check("space tokens", UI.Space.tight == 4 and UI.Space.gap == 8 and UI.Space.padding == 16
    and UI.Space.section == 24 and UI.Space.dialog == 20 and UI.Space.dialogTop == 40)
check("size tokens", UI.Size.row == 24 and UI.Size.icon == 16 and UI.Size.button == 128
    and UI.Size.dropdown == 160 and UI.Size.input == 160)
local N = UI.Native
check("native tokens", N.buttonHeight == 22 and N.inputHeight == 20 and N.inputArt == 5 and N.dropdownArt == 8
    and N.dropdownHeight == 25 and N.sliderHeight == 40 and N.titleLeft == 58 and N.scrollBarWidth == 8)
check("scroll gutter stays 24", UI.ScrollGutter() == 24, UI.ScrollGutter())
check("options builder removed", UI.CreateOptions == nil)
check("display font removed", UI.Font.display == nil)
check("font roles are 12 and 16 px", select(2, UI.Font.body:GetFont()) == 12 and select(2, UI.Font.title:GetFont()) == 16)

-- Window
local position = {}
local window = UI.CreateWindow({ name = "SmokeWindow", title = "Smoke Window", icon = 134400,
    width = 480, height = 400, position = position })
check("window is a ButtonFrameTemplate", window.template == "ButtonFrameTemplate")
check("window title and portrait", window.title == "Smoke Window" and window.portrait == 134400)
check("window keeps its stone around the content", window.Bg.colorTexture == nil and window.TopTileStreaks.shown)
local background = window.Background
check("the brown panel takes the inset's place, its corners hidden", background.template == "CollectionsBackgroundTemplate"
    and background.parent == window and background.allPoints == window.Inset and background.NineSlice.shown
    and not background.BGCornerTopLeft.shown and not background.BGCornerBottomRight.shown and background.BackgroundTile.shown)
check("the inset stays the content parent and draws nothing", window.Inset.shown and not window.Inset.Bg.shown
    and not window.Inset.NineSlice.shown)
local inset = UI.CreateInset(window)
check("an inset keeps only its border", inset.template == "InsetFrameTemplate" and not inset.Bg.shown and inset.NineSlice.shown)
local divider = UI.CreateVerticalDivider(background)
check("the divider is the gold Settings line stood on end", divider.atlas == "Options_HorizontalDivider"
    and divider.useAtlasSize and divider.rotation == 90 and divider.layer == "ARTWORK" and divider.parent == background)
check("window on HIGH strata, toplevel and clamped", window.strata == "HIGH" and window.toplevel and window.clamped)
check("window starts hidden", window.shown == false)
check("Escape closes the window", isEscapable("SmokeWindow"))
window:Show()
check("window close works in combat", window.onCloseCallback() == false and window.shown == false)
window.points = { { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 100, y = 600 } }
window.scripts.OnDragStop(window)
check("window saves its position", position.point == "TOPLEFT" and position.x == 100 and position.y == 600)
local bar = UI.AddBarButton(window, "Primary", function() end)
check("bar button keeps the native 22 px", bar.template == "MagicButtonTemplate" and bar.height == 22 and bar.magicAnchors == 1)
local toggle = UI.CreateToggle(function() return window end)
toggle()
check("toggle shows the window", window.shown == true)

-- Dialog with text, field and button
local closed = 0
local dialog = UI.CreateDialog({ name = "SmokeDialog", title = "Smoke Dialog", width = 448 })
local nameText = dialog:AddText("title", "")
local realmText = dialog:AddText("body", "Realm", UI.Space.tight)
local field = UI.CreateEditBox(dialog, dialog.contentWidth - UI.Native.inputArt)
dialog:AddField(field, UI.Native.inputHeight, UI.Space.gap, UI.Native.inputArt)
local hint = dialog:AddText("muted", "Press CTRL+C to copy and close.", UI.Space.tight)
local closeButton = dialog:AddButton("Close", function() closed = closed + 1 end)
local okButton = dialog:AddButton(OKAY or "Okay", function() end)
dialog:Fit()
check("dialog on DIALOG strata, toplevel, clamped and movable", dialog.strata == "DIALOG" and dialog.toplevel
    and dialog.clamped and dialog.movable and dialog.dragButton == "LeftButton")
check("Escape closes the dialog", isEscapable("SmokeDialog"))
check("dialog chrome is native", dialog.Border.template == "DialogBorderTemplate"
    and dialog.Header.template == "DialogHeaderTemplate" and dialog.Header.Text.text == "Smoke Dialog")
check("content column is 408", dialog.contentWidth == 408, dialog.contentWidth)
check("empty title text keeps its 16 px line", nameText.height == 16 and nameText.points[1].y == -40, nameText.height)
check("text uses the role fonts", nameText.fontObject == GameFontNormalLarge and realmText.fontObject == GameFontHighlight
    and hint.fontObject == GameFontDisable)
check("realm sits tight below the name", realmText.points[1].y == -(40 + 16 + 4), realmText.points[1].y)
check("field is indented for the input art", field.points[1].x == 20 + 5 and field.points[1].y == -(40 + 16 + 4 + 12 + 8),
    field.points[1].x .. "," .. field.points[1].y)
check("hint sits tight below the field", hint.points[1].y == -(40 + 16 + 4 + 12 + 8 + 20 + 4), hint.points[1].y)
check("first button takes the bottom-right corner", closeButton.points[1].point == "BOTTOMRIGHT"
    and closeButton.points[1].x == -20 and closeButton.points[1].y == 20)
check("second button chains left one gap apart", okButton.points[1].rel == closeButton and okButton.points[1].x == -8)
check("dialog buttons are 24 px tall", closeButton.height == 24 and okButton.height == 24)
check("dialog height fits its content on the grid", dialog.height == 184 and onGrid(dialog.height), dialog.height)
dialog:Show()
dialog.CloseButton.scripts.OnClick(dialog.CloseButton)
check("dialog close hides it directly, not through HideUIPanel", dialog.shown == false and not dialog.blizzardHide)
closeButton.scripts.OnClick(closeButton)
check("dialog button runs its handler", closed == 1)

local guide = UI.CreateDialog({ name = "SmokeGuide", title = "Guide", width = 400, parent = window })
local heading, body = guide:AddSection("Heading", string.rep("word ", 30))
guide:AddSection("Second", "Short.")
guide:Fit()
check("dialog can sit on a host frame", guide.parent == window)
check("section body wraps across the column", body.height == 36 and body.points[1].y == -(40 + 12 + 8), body.height)
check("next section is a section break below", guide.contentHeight == 12 + 8 + 36 + 24 + 12 + 8 + 12, guide.contentHeight)
check("dialog without buttons fits on the grid", onGrid(guide.height) and guide.height == UI.Snap(40 + guide.contentHeight + 20))
check("heading is gold", heading.fontObject == GameFontNormal)

-- Fit-to-text button
local short = UI.CreateButton(UIParent, "Add")
local long = UI.CreateButton(UIParent, "Add Nearby Quest Units")
local fixed = UI.CreateButton(UIParent, "Apply", 128)
check("short labels keep the 64 px minimum", short.width == 64, short.width)
check("long labels fit their text in steps of 8", long.width == 176, long.width)
check("an explicit width wins", fixed.width == 128)
check("content buttons are 24 px tall", short.height == 24 and long.height == 24 and fixed.height == 24)

-- Checkbox
local checkbox = UI.CreateCheckbox(UIParent, "Play Sound")
check("checkbox uses the minimal native art", checkbox.template == "CheckboxWithLabelTemplate")
check("checkbox is one row square", checkbox.width == 24 and checkbox.height == 24)
check("label is 12 px body text", checkbox.Text.fontObject == GameFontHighlight)
local labelPoint = checkbox.Text.points[1]
check("label sits tight to the right", #checkbox.Text.points == 1 and labelPoint.point == "LEFT"
    and labelPoint.relPoint == "RIGHT" and labelPoint.x == 4)
check("label is clickable", checkbox.hitRect[2] == -(4 + 10 * CHAR_WIDTH), checkbox.hitRect[2])
checkbox:SetLabel("Say")
check("SetLabel updates the text and hit rect", checkbox.Text.text == "Say" and checkbox.hitRect[2] == -(4 + 3 * CHAR_WIDTH))
local bare = UI.CreateCheckbox(UIParent)
check("a checkbox without label starts empty", bare.Text.text == "")

-- Filter dropdown
local filters = { completed = false }
local filter = UI.CreateFilterDropdown(UIParent)
filter:SetDefaultCallback(function() filters.completed = false end)
filter:SetIsDefaultCallback(function() return filters.completed == false end)
filter:SetupMenu(function() end)
check("filter uses Blizzard's filter dropdown", filter.template == "WowStyle1FilterDropdownTemplate" and filter.Text.text == "Filter")
check("filter width snaps the native fit to the grid", filter.width == 96 and onGrid(filter.width), filter.width)
filter:SetText("Filter (2)")
check("later text keeps the width", filter.width == 96, filter.width)
check("reset stays hidden at defaults", filter.ResetButton.shown == false)
filters.completed = true
filter:ValidateResetState()
check("reset shows when filters differ", filter.ResetButton.shown == true)
filter.ResetButton.scripts.OnClick(filter.ResetButton)
check("reset restores the defaults", filters.completed == false and filter.ResetButton.shown == false)
local wide = UI.CreateFilterDropdown(UIParent, 120)
check("an explicit filter width wins", wide.width == 120)

-- Launcher
local db = {}
local clicks = {}
local launcher = UI.CreateLauncher({ title = "Smoke", icon = 134400, db = db,
    onClick = function(button) clicks[#clicks + 1] = button end,
    tooltip = function(tooltip) tooltip.lines = 1 end })
check("launcher registers once with the compartment", LDBIcon:IsRegistered("Smoke") and LDBIcon.compartment[1] == "Smoke")
LDB.Smoke.OnClick(nil, "RightButton")
check("launcher passes the mouse button through", clicks[1] == "RightButton")
LDB.Smoke.OnTooltipShow(GameTooltip)
check("launcher tooltip gets its title", GameTooltip.title == "Smoke" and GameTooltip.lines == 1)
launcher.setShown(false)
check("setShown(false) hides the minimap button and remembers it", db.hide == true and LDBIcon.visible.Smoke == false)
launcher.setShown(true)
check("setShown(true) shows it again", db.hide == false and LDBIcon.visible.Smoke == true)
local again = UI.CreateLauncher({ title = "Smoke", icon = 134400, db = db, onClick = print, tooltip = print })
check("a second launcher call still returns setShown", type(again.setShown) == "function" and #LDBIcon.compartment == 1)

-- Chat and slash
local printed
local realPrint = print
print = function(line) printed = line end
UI.Print("Smoke", "Ready.")
print = realPrint
check("chat line has the yellow prefix", printed == "|cffffff00[Smoke]:|r Ready.", printed)
UI.RegisterSlash("SMOKE", { "/smoke", "/sm" }, function() end)
check("slash commands register", SLASH_SMOKE1 == "/smoke" and SLASH_SMOKE2 == "/sm" and SlashCmdList.SMOKE)

print(string.format("LibNativeUI smoke test: %d passed, %d failed", passes, failures))
if failures > 0 then os.exit(1) end
