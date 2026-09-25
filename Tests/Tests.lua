-- Behavioural suite for TargetFinder. Every section maps to behaviour the
-- README promises or to a defect that was fixed, so a regression names itself.
local here = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./")
dofile(here .. "Harness.lua")
local ns, W = _G.ns, _G.W

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1; io.write("  PASS  ", name, "\n")
    else fail = fail + 1; io.write("  FAIL  ", name, "  ", tostring(detail), "\n") end
end
local function section(s) io.write("\n== ", s, " ==\n") end
local function chatHas(pattern)
    for _, l in ipairs(W.chat) do if l:match(pattern) then return true end end
    return false
end
local function countMarks()
    local n = 0
    for _ in pairs(W.marks) do n = n + 1 end
    return n
end

-- boot the addon the way the client does
TargetFinderDB = nil; TargetFinderCharDB = nil
local boot
for f in pairs(_G.__frames) do if f.events["ADDON_LOADED"] then boot = f end end
boot.scripts.OnEvent(boot, "ADDON_LOADED", "TargetFinder")

section("toc metadata")
local toc = {}
for raw in io.lines(here .. "../TargetFinder.toc") do
    local key, value = raw:gsub("\r", ""):match("^## ([%w%-]+): (.*)$")
    if key then toc[key] = value end
end
check("author is miyanko", toc["Author"] == "miyanko", toc["Author"])
check("one toc for both clients", toc["Interface"] == "11509, 16001", toc["Interface"])
for _, key in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
    check(key .. " names a real global", toc[key] and type(_G[toc[key]]) == "function", toc[key])
end

section("boot and saved variables")
check("minimap defaults created", TargetFinderDB.minimap.minimapPos == 215)
check("targets aliased to live table", TargetFinderCharDB.targets == ns.targets)
check("unit menus registered", W.menuHooks["MENU_UNIT_TARGET"] ~= nil)
check("MENU_UNIT_RAID now covered", W.menuHooks["MENU_UNIT_RAID"] ~= nil)

section("saved-variable sanitising")
ns.AdoptSaved({ {name="Good", kind=1}, {name=""}, {nope=true}, "junk", {name="Also", kind="2"} })
check("kept only well-formed entries", ns.TargetCount() == 2, ns.TargetCount())
check("slot 1 preserved", ns.targets[1] and ns.targets[1].name == "Good")
check("sparse slots preserved", ns.targets[2] == nil and ns.targets[5] ~= nil)
check("string kind coerced to number", ns.targets[5].kind == 2, ns.targets[5].kind)

section("names match from the start, like /target")
check("prefix matches", ns.NameMatches("Auctioneer Chillgular", "Auctioneer"))
check("mid-name substring rejected", not ns.NameMatches("Auctioneer Chillgular", "Chillgular"))
check("case insensitive", ns.NameMatches("Kobold Laborer", "kobold"))
check("exact matches", ns.NameMatches("Mangeclaw", "Mangeclaw"))

section("macro body")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Alpha"); ns.targets[2] = ns.MakeEntry("Beta"); ns.targets[3] = ns.MakeEntry("Gamma")
ns.WriteFinderMacro()
local body = W.macros["FIND"].body
check("reversed so slot 1 wins last", body == "/target Gamma\n/target Beta\n/target Alpha", body:gsub("\n","|"))
ns.WipeTargets(); ns.WriteFinderMacro()
check("empty list is a no-op comment", W.macros["FIND"].body:sub(1,2) == "//", W.macros["FIND"].body)

section("macro 255-char overflow drops lowest priority")
ns.WipeTargets()
for i = 1, 8 do ns.targets[i] = ns.MakeEntry(("Name%d"):format(i) .. string.rep("x", 28)) end
ns.WriteFinderMacro()
local b = W.macros["FIND"].body
check("body within cap", #b <= 255, #b)
check("slot 1 survived truncation", b:match("Name1") ~= nil)
check("slot 8 dropped first", b:match("Name8") == nil)

section("macro cap is reported, not silent")
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}; W.macroCap = 0
W.chat = {}
ns.targets[1] = ns.MakeEntry("Anything")
ns.WriteFinderMacro()
check("cap failure announced", chatHas("account macro list is full"), table.concat(W.chat, " / "))
W.macroCap = 120

section("panel markers get the sprite sheet")
local tex = CreateFrame("Frame"):CreateTexture()
ns.ShowMarkerTexture(tex, 8)
check("texture file assigned", tex.texturePath == "Interface\\TargetingFrame\\UI-RaidTargetingIcons", tex.texturePath)
check("cell selected", tex.markerCell == 8)
check("shown", tex.shown == true)

section("markers follow the prefix rule")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Auctioneer")
W.units = { target = { name = "Auctioneer Chillgular" } }
W.marks = {}
ns.ApplyMarkerFromTarget()
check("prefix target marked with slot 1 icon", W.marks["target"] == 8, W.marks["target"])
W.units = { target = { name = "Ragged Young Wolf" } }
W.marks = {}
ns.ApplyMarkerFromTarget()
check("unrelated target untouched", W.marks["target"] == nil)

section("one raid marker goes to one unit")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Kobold")
W.units = { nameplate1 = {name="Kobold Laborer"}, nameplate2 = {name="Kobold Miner"}, nameplate3 = {name="Angry Kobold"} }
W.marks = {}
local n = ns.MarkNearbyForSlot(1)
check("count is the one unit marked", n == 1, n)
check("exactly one unit carries the marker", countMarks() == 1, countMarks())
check("first match in token order took it", W.marks["nameplate1"] == 8, W.marks["nameplate1"])
check("mid-name match skipped", W.marks["nameplate3"] == nil)

W.units = { target = {name="Kobold Miner"}, nameplate1 = {name="Kobold Laborer"}, nameplate2 = {name="Kobold Miner"} }
W.marks = {}
n = ns.MarkNearbyForSlot(1)
check("a matching target keeps the marker", W.marks["target"] == 8 and countMarks() == 1, W.marks["target"])
check("target path counts one", n == 1, n)

W.units = { nameplate1 = {name="Kobold Laborer"}, nameplate2 = {name="Kobold Miner"} }
W.marks = { nameplate2 = 8 }
n = ns.MarkNearbyForSlot(1)
check("a unit already carrying the marker keeps it", W.marks["nameplate2"] == 8 and W.marks["nameplate1"] == nil)
check("keeping it still counts one", n == 1, n)

W.units = { nameplate1 = {name="Wolf"} }
W.marks = {}
check("nothing in view counts zero", ns.MarkNearbyForSlot(1) == 0)

-- overlapping entries: the broader, higher slot owns every unit it covers
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Kobold")
ns.targets[2] = ns.MakeEntry("Kobold Miner")
W.units = { nameplate1 = {name="Kobold Miner"} }
W.marks = {}
local total = ns.RemarkAllSlots()
check("a unit is never claimed by two slots", total == 1 and W.marks["nameplate1"] == 8, total)

-- typing a name into the panel must not stamp the marker on an unrelated target
ns.WipeTargets()
W.units = { target = {name="Ragged Young Wolf"} }
W.marks = {}
ns.SetSlot(3, "Kobold")
check("unrelated target left unmarked", W.marks["target"] == nil, W.marks["target"])

section("secret identity guard")
W.units = { target = { name = "Someone", player = true, friend = true, party = true, secret = true } }
check("secret unit name withheld", ns.ReadableName("target") == nil)
W.units.target.secret = false
check("readable when not secret", ns.ReadableName("target") == "Someone")
check("IdentitySecret false for unknown token", ns.IdentitySecret("nosuchunit") == false)

section("canaccessvalue is only ever called protected")
local realCanAccess = canaccessvalue
canaccessvalue = function() error("secret argument from tainted code") end
local ok, answer = pcall(ns.CanAccess, "Someone")
check("a raising check does not escape", ok, answer)
check("a raising check reads as not accessible", answer == false, answer)
check("the name is withheld instead", ns.ReadableName("target") == nil)
canaccessvalue = nil
check("an absent check reads as accessible", ns.CanAccess("Someone") == true)
canaccessvalue = realCanAccess
check("a plain value stays accessible", ns.CanAccess("Someone") == true)

section("unit menu resolves the name from the unit, not context.name")
local root = {
    items = {},
    CreateDivider = function(self) self.items[#self.items+1] = {kind="divider"} end,
    CreateTitle = function(self, t) self.items[#self.items+1] = {kind="title", text=t} end,
    CreateButton = function(self, t, fn) self.items[#self.items+1] = {kind="button", text=t, fn=fn} end,
}
ns.WipeTargets()
W.units = { target = { name = "Mangeclaw" } }
-- exactly what Blizzard passes for an NPC target frame on both branches
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon", fromTargetFrame = true })
local trackFn
for _, it in ipairs(root.items) do if it.text == "Track" then trackFn = it.fn end end
check("Track offered", trackFn ~= nil)
W.chat = {}
W.marks = {}
if trackFn then trackFn(); RunTimers() end
check("stored the NPC name", ns.targets[1] and ns.targets[1].name == "Mangeclaw",
      ns.targets[1] and ns.targets[1].name)
check("did NOT store 'Raid Target Icon'", ns.targets[1] and ns.targets[1].name ~= "Raid Target Icon")
check("the tracked target got the slot marker", W.marks["target"] == 8, W.marks["target"])

section("menus with no unit still use context.name")
ns.WipeTargets()
root.items = {}
W.units = {}
W.menuHooks["MENU_UNIT_FRIEND"](nil, root, { name = "Someguy" })
local fn2
for _, it in ipairs(root.items) do if it.text == "Track" then fn2 = it.fn end end
if fn2 then fn2(); RunTimers() end
check("context.name used when no unit", ns.targets[1] and ns.targets[1].name == "Someguy",
      ns.targets[1] and ns.targets[1].name)

section("menu action set depends on what is tracked")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Auctioneer")
root.items = {}
W.units = { target = { name = "Auctioneer Chillgular" } }
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
local labels = {}
for _, it in ipairs(root.items) do if it.kind == "button" then labels[it.text] = true end end
check("Untrack offered for a covered NPC", labels["Untrack"] == true)
check("Track hidden for a covered NPC", labels["Track"] == nil)
check("Track First hidden when already slot 1", labels["Track First"] == nil)
check("Clear offered when list non-empty", labels["Clear Unit List"] == true)

-- same NPC, but covered by a lower slot: promotion becomes worth offering
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Something Else")
ns.targets[2] = ns.MakeEntry("Auctioneer")
root.items = {}
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
local labels2, promote = {}, nil
for _, it in ipairs(root.items) do
    if it.kind == "button" then labels2[it.text] = true
        if it.text == "Track First" then promote = it.fn end end
end
check("Track First offered from a lower slot", labels2["Track First"] == true)
if promote then promote(); RunTimers() end
check("promotes the matched entry, not a duplicate",
      ns.targets[1].name == "Auctioneer" and ns.TargetCount() == 2,
      ns.targets[1].name .. "/" .. ns.TargetCount())

section("menu does not test secret booleans")
root.items = {}
W.units = { target = { name = "Enemy", player = true, secret = true } }
local menuOk, menuErr = pcall(function()
    W.menuHooks["MENU_UNIT_ENEMY_PLAYER"](nil, root, { unit = "target", name = "Enemy" })
end)
check("menu builds without error under restriction", menuOk, menuErr)
local hasAssist = false
for _, it in ipairs(root.items) do if it.text == "Assist" then hasAssist = true end end
check("Assist withheld while identity is secret", not hasAssist)

section("Assist for a real group member")
root.items = {}
W.units = { party1 = { name = "Buddy", player = true, friend = true, party = true } }
W.menuHooks["MENU_UNIT_PARTY"](nil, root, { unit = "party1", name = "Buddy" })
local assistFn
for _, it in ipairs(root.items) do if it.text == "Assist" then assistFn = it.fn end end
check("Assist offered for a party member", assistFn ~= nil)
if assistFn then assistFn(); RunTimers() end
check("ASSIST macro body", W.macros["ASSIST"] and W.macros["ASSIST"].body == "/assist Buddy",
      W.macros["ASSIST"] and W.macros["ASSIST"].body)

section("Questie readiness")
check("absent Questie reports not loaded", ns.QuestieReady() == false)
check("excuse names absence", ns.QuestieExcuse() == "Questie is not loaded.", ns.QuestieExcuse())
-- Questie present but QuestieDB:Initialize has not run yet
_G.QuestieLoader = { ImportModule = function(_, m)
    if m == "QuestieDB" then return { NPCPointers = {} } end
    return {}
end }
check("module present but queries nil is not ready", ns.QuestieReady() == false)
check("excuse names the loading state", ns.QuestieExcuse() == "Questie is still loading.", ns.QuestieExcuse())
-- Questie 12 binds the queries at file load but NPCPointers only in QuestieDB.Initialize
local noop = function() end
_G.QuestieLoader = { ImportModule = function(_, m)
    if m == "QuestieDB" then return { QueryNPCSingle = noop, QueryQuestSingle = noop, QueryItemSingle = noop } end
    return {}
end }
check("queries without NPCPointers is not ready", ns.QuestieReady() == false)
W.chat = {}
ns.AddNearbyQuestNpcs()
check("nearby add refuses cleanly while loading",
      W.chat[1] and W.chat[1]:match("still loading") ~= nil, W.chat[1])
_G.QuestieLoader = nil

-- A small Questie world with the shapes both Questie 11.37.1 and master use: quest objects in
-- QuestiePlayer.currentQuestlog carrying ObjectiveData and Objectives[i].Completed.
local function fakeQuestie()
    local npcs = {
        [1] = { name = "Done Wolf", spawns = { [12] = { {50, 50} } } },
        [2] = { name = "Kobold Miner", spawns = { [12] = { {52, 52} } } },
        [3] = { name = "Kobold Looter", spawns = { [12] = { {90, 90} } } },
        [4] = { name = "Quest Giver", spawns = { [12] = { {50, 51} } } },
        [5] = { name = "Turn In Guy", spawns = { [12] = { {51, 51} } } },
        [6] = { name = "Kobold Far Away", spawns = { [40] = { {50, 50} } } },
        [7] = { name = "Kobold Tunneler", spawns = { [12] = { {50, 50} } } },
    }
    local quests = {
        [100] = { name = "Kobold Trouble", startedBy = { {4} }, finishedBy = { {5} } },
    }
    local items = { [10] = { npcDrops = { 3, 6 } } }
    local quest = {
        Id = 100,
        ObjectiveData = {
            { Type = "monster", Id = 1 },
            { Type = "monster", Id = 2 },
            { Type = "item", Id = 10 },
        },
        Objectives = { [1] = { Completed = true }, [2] = { Completed = false } },
    }
    local state = { complete = 0 }
    local modules = {
        QuestieDB = {
            NPCPointers = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true },
            QueryNPCSingle = function(id, key) local r = npcs[id]; return r and r[key] end,
            QueryQuestSingle = function(id, key) local r = quests[id]; return r and r[key] end,
            QueryItemSingle = function(id, key) local r = items[id]; return r and r[key] end,
            GetQuest = function(id) if id == 100 then return quest end end,
            IsComplete = function() return state.complete end,
        },
        QuestiePlayer = { currentQuestlog = { [100] = quest } },
        ZoneDB = {
            GetAreaIdByUiMapId = function(_, uiMapId)
                if uiMapId == 1429 then return 12 end
                error("No AreaId found for UiMapId: " .. tostring(uiMapId))
            end,
            GetParentZoneId = function() return nil end,
        },
    }
    -- like the real loader, an unknown name gets an empty module rather than nil
    _G.QuestieLoader = { ImportModule = function(_, name)
        modules[name] = modules[name] or { private = {} }
        return modules[name]
    end }
    _G.Questie = {
        usedIcons = { [1] = "slay", [2] = "loot", [5] = "talk", [6] = "available" },
        ICON_TYPE_SLAY = 1, ICON_TYPE_LOOT = 2, ICON_TYPE_TALK = 5, ICON_TYPE_AVAILABLE = 6,
    }
    return modules, quest, state
end

local function namesOf(list)
    local out = {}
    for i, e in ipairs(list) do out[e.name] = i end
    return out
end

section("objective progress comes from Questie, not the native quest log")
local modules, quest, questState = fakeQuestie()
check("fake Questie is ready", ns.QuestieReady())
W.chat = {}
local picks = ns.QuestNpcs(100)
local names = namesOf(picks)
check("no native quest-log read and no error", not chatHas("Could not read"), table.concat(W.chat, " / "))
check("open kill objective offered", names["Kobold Miner"] ~= nil)
check("item droppers offered", names["Kobold Looter"] ~= nil)
check("finished objective skipped", names["Done Wolf"] == nil)
check("givers offered", names["Quest Giver"] ~= nil and names["Turn In Guy"] ~= nil)
check("kill sorts before drop and giver", picks[1] and picks[1].name == "Kobold Miner" and picks[1].kind == ns.KIND_KILL,
      picks[1] and picks[1].name)
quest.Objectives[2].Completed = true
check("Completed flag drops a kill target", namesOf(ns.QuestNpcs(100))["Kobold Miner"] == nil)
quest.Objectives[2].Completed = false
modules.QuestiePlayer.currentQuestlog[100] = 100
check("a bare quest id falls back to the database object", namesOf(ns.QuestNpcs(100))["Kobold Miner"] ~= nil)
modules.QuestiePlayer.currentQuestlog[100] = quest

section("nearby add follows Questie's quest state")
C_Map.GetBestMapForUnit = function() return 1429 end
C_Map.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end
W.units = {}
W.marks = {}
ns.WipeTargets()
ns.AddNearbyQuestNpcs()
check("active quest adds open objectives in zone", ns.TargetCount() == 2, ns.TargetCount())
check("kill target leads", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)
check("dropper follows", ns.targets[2] and ns.targets[2].name == "Kobold Looter", ns.targets[2] and ns.targets[2].name)
check("startedBy skipped once accepted", ns.SlotForName("Quest Giver") == nil)
check("dropper in another zone skipped", ns.SlotForName("Kobold Far Away") == nil)

questState.complete = 1
ns.AddNearbyQuestNpcs()
check("complete quest adds only the turn-in NPC", ns.TargetCount() == 1 and ns.targets[1].name == "Turn In Guy",
      ns.targets[1] and ns.targets[1].name)
questState.complete = 0
quest.isComplete = true
ns.AddNearbyQuestNpcs()
check("Questie's own isComplete flag counts too", ns.TargetCount() == 1 and ns.targets[1].name == "Turn In Guy")
quest.isComplete = nil

C_Map.GetBestMapForUnit = function() return 999 end
W.units = { nameplate1 = { name = "Kobold Looter" } }
W.chat = {}
local nearbyOk, nearbyErr = pcall(ns.AddNearbyQuestNpcs)
check("a map Questie cannot place does not raise", nearbyOk, nearbyErr)
check("nameplates still count as nearby", ns.TargetCount() == 1 and ns.targets[1].name == "Kobold Looter",
      ns.targets[1] and ns.targets[1].name)
check("no read failure reported", not chatHas("Could not read"))
C_Map.GetBestMapForUnit = function() return nil end
W.units = {}

section("search suggestions")
local results = ns.FindSuggestions("kob")
check("quest name first", results[1] and results[1].type == "quest" and results[1].name == "Kobold Trouble",
      results[1] and results[1].name)
check("quest NPC tagged with its quest", results[2] and results[2].isQuestNpc and results[2].questName == "Kobold Trouble",
      results[2] and results[2].name)
local plain
for _, r in ipairs(results) do if r.name == "Kobold Tunneler" then plain = r end end
check("plain database NPCs follow", plain ~= nil and not plain.isQuestNpc)
check("Questie icons resolve per kind", ns.QuestieKindIcons()[ns.KIND_KILL] == "slay")

section("panel is a native ButtonFrameTemplate window")
ns.WipeTargets()
ns.TogglePanel()
local panel = _G.TargetFinderPanel
check("built from ButtonFrameTemplate", panel and panel.template == "ButtonFrameTemplate", panel and panel.template)
check("portrait hidden like AddonList", panel and panel.portraitHidden == true)
local escapable = false
for _, name in ipairs(UISpecialFrames) do if name == "TargetFinderPanel" then escapable = true end end
check("Escape closes it", escapable)
local row1 = panel.rows[1]
check("rows live in the Inset", row1.parent == panel.Inset)
check("inputs use InputBoxTemplate", row1.input.template == "InputBoxTemplate", row1.input.template)
check("remove is the client's close button without its hide script", row1.removeBtn.template == "UIPanelCloseButtonNoScripts",
      row1.removeBtn.template)
check("add is a Blizzard panel button", row1.addBtn.template == "UIPanelButtonTemplate", row1.addBtn.template)
row1.input:SetText("Kobold")
row1.updateState()
check("typing a new name offers Add", row1.addBtn.shown == true and row1.removeBtn.shown == false)
row1.input:SetText("")
row1.updateState()
check("an empty unstored row offers nothing", row1.addBtn.shown == false and row1.removeBtn.shown == false)
panel.shown = true
check("close button hides the panel itself, skipping HideUIPanel", panel.onCloseCallback() == false and panel.shown == false)
panel.nearbyButton.scripts.OnEnter(panel.nearbyButton)
check("nearby tooltip uses Blizzard's title helper", W.tooltip[1] == "title:Add Nearby Quest Units", W.tooltip[1])

section("suggestion popup mirrors Blizzard's AutoCompleteBox")
local input = row1.input
input:SetText("kob")
input.scripts.OnTextChanged(input, true)
local pop = _G.TargetFinderSuggestions
check("one shared popup on TooltipBackdropTemplate", pop and pop.template == "TooltipBackdropTemplate", pop and pop.template)
check("popup shown for the typing row", pop and pop.shown == true and pop.owner == input)
local firstRow = _G.TargetFinderSuggestionsButton1
check("rows use AutoCompleteButtonTemplate", firstRow and firstRow.template == "AutoCompleteButtonTemplate",
      firstRow and firstRow.template)
check("quest rows are labelled", firstRow and firstRow.text == "[Quest] Kobold Trouble", firstRow and firstRow.text)
check("no row preselected, so Enter keeps typed text", not firstRow.locked)
input.scripts.OnArrowPressed(input, "DOWN")
check("arrow down locks the first row's highlight", firstRow.locked == true)
input.scripts.OnArrowPressed(input, "DOWN")
check("second arrow moves the highlight", firstRow.locked == false and _G.TargetFinderSuggestionsButton2.locked == true)
W.marks = {}
input.scripts.OnEnterPressed(input)
check("Enter stores the highlighted NPC", ns.targets[1] and ns.targets[1].name == "Kobold Miner",
      ns.targets[1] and ns.targets[1].name)
check("popup closes after the pick", pop.shown == false)

input:SetText("kob")
input.scripts.OnTextChanged(input, true)
input.scripts.OnTabPressed(input)
check("Tab completes the first NPC without storing it", input.text == "Kobold Miner" and pop.shown == false, input.text)

section("a changed Questie internal degrades to one message")
modules.QuestieDB.QueryNPCSingle = function() error("field renamed") end
W.chat = {}
local degradeOk, degraded = pcall(ns.QuestNpcs, 100)
check("no error escapes", degradeOk, degraded)
check("empty result instead", degradeOk and type(degraded) == "table" and #degraded == 0)
check("one chat line explains it", chatHas("Could not read Questie data"), table.concat(W.chat, " / "))
W.chat = {}
ns.FindSuggestions("kob")
check("later failures stay quiet", #W.chat == 0, table.concat(W.chat, " / "))
_G.QuestieLoader = nil
_G.Questie = nil

section("launchers share one click and tooltip")
local login
for f in pairs(_G.__frames) do if f.events["PLAYER_LOGIN"] then login = f end end
login.scripts.OnEvent(login, "PLAYER_LOGIN")
check("LibDBIcon launcher registered", W.ldbObject ~= nil)
W.ldbObject.OnTooltipShow(GameTooltip)
local missing = false
for _, l in ipairs(W.tooltip) do if l == "error:Questie is not loaded." then missing = true end end
check("minimap tooltip names what is missing", W.tooltip[1] == "title:Target Finder" and missing, table.concat(W.tooltip, " / "))
TargetFinder_OnEnter("TargetFinder", UIParent)
check("compartment tooltip is the same tooltip", W.tooltip[1] == "title:Target Finder")
local wasShown = panel.shown
TargetFinder_OnClick("TargetFinder", "LeftButton")
check("compartment left-click toggles the panel", panel.shown ~= wasShown)
W.chat = {}
TargetFinder_OnClick("TargetFinder", "RightButton")
check("compartment right-click adds nearby units", chatHas("Questie is not loaded"), table.concat(W.chat, " / "))

section("combat defers the macro write")
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}; W.errors = {}
W.inCombat = true
ns.targets[1] = ns.MakeEntry("Deferred")
ns.WriteFinderMacro()
check("nothing written in combat", W.macros["FIND"] == nil)
check("one on-screen notice", #W.errors == 1, #W.errors)
W.inCombat = false
local regen
for f in pairs(_G.__frames) do if f.events["PLAYER_REGEN_ENABLED"] then regen = f end end
regen.scripts.OnEvent(regen, "PLAYER_REGEN_ENABLED")
check("replayed after combat", W.macros["FIND"] ~= nil
      and W.macros["FIND"].body == "/target Deferred", W.macros["FIND"] and W.macros["FIND"].body)

section("list operations")
ns.WipeTargets()
ns.AddFinder("First"); ns.AddFinder("Second"); ns.AddFinder("Third")
check("three tracked", ns.TargetCount() == 3)
ns.AddFinderFirst("Third", nil, ns.SlotForName("Third"))
check("promoted to slot 1", ns.targets[1].name == "Third")
check("others shifted down", ns.targets[2].name == "First" and ns.targets[3].name == "Second")
check("no duplicate created", ns.TargetCount() == 3)
ns.RemoveFinder(2)
check("removed leaves a hole", ns.targets[2] == nil and ns.TargetCount() == 2)
ns.ClearFinder()
check("cleared", ns.TargetCount() == 0)

section("ReplaceFinder is atomic")
ns.WipeTargets()
ns.AddFinder("Old")
ns.ReplaceFinder({ {name="New1", kind=1}, {name="New2", kind=2} })
check("old gone, new in", ns.TargetCount() == 2 and ns.targets[1].name == "New1")
W.chat = {}
ns.ReplaceFinder({})
check("empty replace leaves the list intact", ns.TargetCount() == 2, ns.TargetCount())

section("full list behaviour")
ns.WipeTargets()
for i = 1, 8 do ns.AddFinder("Unit" .. i) end
W.chat = {}
ns.AddFinder("Ninth")
check("refuses a ninth", ns.TargetCount() == 8)
check("says it is full", W.chat[1] and W.chat[1]:match("full") ~= nil, W.chat[1])
ns.AddFinderFirst("Ninth")
check("Track First still fits by dropping the last", ns.targets[1].name == "Ninth" and ns.TargetCount() == 8)
check("names what it dropped", chatHas("dropped Unit8"), table.concat(W.chat, " / "))

io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
