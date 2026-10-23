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
check("Forever interface only", toc["Interface"] == "16001", toc["Interface"])
check("Category read by the AddOns list", toc["Category"] == "Quests", toc["Category"])
check("icon is a texture path", toc["IconTexture"] == "Interface\\Icons\\Ability_Hunter_SniperShot", toc["IconTexture"])
check("Notes fit CurseForge's 100 characters", #toc["Notes"] <= 100, #toc["Notes"])
check("no X-Category", toc["X-Category"] == nil)
local tagged = false
for raw in io.lines(here .. "../TargetFinder.toc") do
    if raw:match("%[AllowLoad") then tagged = true end
end
check("no per-line load tags", not tagged)
local tocFiles, tocOrder = {}, {}
for raw in io.lines(here .. "../TargetFinder.toc") do
    local line = raw:gsub("\r", "")
    if line:match("%.lua$") then
        tocFiles[line] = true
        tocOrder[#tocOrder+1] = line
    end
end
check("UI files live in UI/", tocFiles["UI\\Panel.lua"] and tocFiles["UI\\Suggestions.lua"] and tocFiles["UI\\MinimapButton.lua"])
check("no UI file left in Core/", not (tocFiles["Core\\Panel.lua"] or tocFiles["Core\\Suggestions.lua"] or tocFiles["Core\\MinimapButton.lua"]))
check("no addon-side marker module", not tocFiles["Core\\Markers.lua"])
local dbIconAt
for i, line in ipairs(tocOrder) do
    if line == "Libs\\LibDBIcon-1.0\\LibDBIcon-1.0.lua" then dbIconAt = i end
end
check("LibNativeUI loads right after LibDBIcon", dbIconAt and tocOrder[dbIconAt + 1] == "Libs\\LibNativeUI-1.0\\LibNativeUI-1.0.lua",
      dbIconAt and tocOrder[dbIconAt + 1])
-- LibDBIcon registers the addon menu entry itself, so toc entry points would list the addon twice
for _, key in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
    check("no toc " .. key, toc[key] == nil, toc[key])
end
check("no compartment globals left", TargetFinder_OnClick == nil and TargetFinder_OnEnter == nil and TargetFinder_OnLeave == nil)

section("boot and saved variables")
check("minimap defaults created", TargetFinderDB.minimap.minimapPos == 215)
check("targets aliased to live table", TargetFinderCharDB.targets == ns.targets)
check("Quest NPCs starts on", TargetFinderCharDB.questNpcs == true)
check("unit menus registered", W.menuHooks["MENU_UNIT_TARGET"] ~= nil)
check("friendly-only menus left alone", W.menuHooks["MENU_UNIT_RAID"] == nil and W.menuHooks["MENU_UNIT_FRIEND"] == nil)

section("saved-variable sanitising")
ns.AdoptSaved({ {name="Good", quest=true, kind=1}, {name=""}, {nope=true}, "junk", {name="Also", kind=2, quest="yes"},
    {name="Odd", quest=true, kind=9} })
check("kept only well-formed entries", ns.TargetCount() == 3, ns.TargetCount())
check("slot 1 preserved", ns.targets[1] and ns.targets[1].name == "Good")
check("sparse slots preserved", ns.targets[2] == nil and ns.targets[5] ~= nil)
check("quest source and kind kept", ns.targets[1].quest == true and ns.targets[1].kind == ns.KIND_KILL)
check("only a true quest flag counts, and a typed entry has no kind", ns.targets[5].quest == nil and ns.targets[5].kind == nil)
check("an unknown kind is dropped", ns.targets[6].quest == true and ns.targets[6].kind == nil)

section("names match exactly, like /targetexact")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Kobold Miner")
check("the whole name finds its slot", ns.SlotForName("Kobold Miner") == 1)
check("a prefix finds nothing", ns.SlotForName("Kobold") == nil)
check("no prefix matching left", ns.NameMatches == nil and ns.SlotCovering == nil)

section("macro body follows RestedXP's targeting macro")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Alpha"); ns.targets[2] = ns.MakeEntry("Beta"); ns.targets[3] = ns.MakeEntry("Gamma")
ns.WriteFinderMacro()
local body = W.macros["FIND"].body
local TAIL = "\n/targetlasttarget [dead]\n/tm [harm,nodead] !8"
check("exact names reversed so slot 1 wins last, then the corpse guard and the skull",
      body == "/targetexact Gamma\n/targetexact Beta\n/targetexact Alpha" .. TAIL, body:gsub("\n","|"))
check("FIND is a character macro", W.macros["FIND"].perCharacter == true)
check("FIND uses the icon's file ID", W.macros["FIND"].icon == 132212, W.macros["FIND"].icon)
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
check("the corpse guard and the skull always stay", b:sub(-#TAIL) == TAIL, b:sub(-#TAIL))

section("macro cap is reported, not silent")
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}; W.macroCap = 0
W.chat = {}
ns.targets[1] = ns.MakeEntry("Anything")
ns.WriteFinderMacro()
check("cap failure announced", chatHas("Delete one in the macro book"), table.concat(W.chat, " / "))
W.macroCap = 120

section("the skull line follows the group role")
local macroEvents
for f in pairs(_G.__frames) do if f.events["GROUP_ROSTER_UPDATE"] then macroEvents = f end end
check("group changes are watched", macroEvents ~= nil and macroEvents.events["PARTY_LEADER_CHANGED"] == true)
local function groupEvent(event) macroEvents.scripts.OnEvent(macroEvents, event or "GROUP_ROSTER_UPDATE") end
local function marks() return W.macros["FIND"].body:match("/tm %[harm,nodead%] !8$") ~= nil end
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Kobold")
ns.WriteFinderMacro()
check("solo, FIND marks", marks())
W.group = "party"
groupEvent()
check("a party member who does not lead gets no skull line", not marks(), W.macros["FIND"].body)
W.leader = true
groupEvent("PARTY_LEADER_CHANGED")
check("the party leader marks", marks())
W.group, W.leader = "raid", false
groupEvent()
check("a plain raid member gets no skull line", not marks())
W.assistant = true
groupEvent()
check("a raid assistant marks", marks())
W.macros["FIND"].body = "sentinel"
groupEvent()
check("a roster change that keeps the role leaves FIND alone", W.macros["FIND"].body == "sentinel")
ns.WriteFinderMacro()
W.units = { player = { name = "Me", secret = true } }
W.group, W.assistant, W.leader = "party", false, true
groupEvent()
check("a hidden leader answer counts as no", not marks())
W.units = {}
W.group, W.leader = nil, false
groupEvent()
check("back to solo, FIND marks again", marks())
W.macroOrder = {}; W.macros = {}
W.group = "party"
groupEvent()
check("a group change never creates FIND", W.macros["FIND"] == nil)
W.group = nil
groupEvent()

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
canaccessvalue = realCanAccess
check("a plain value stays accessible", ns.CanAccess("Someone") == true)
W.nilChecks = 0
check("nil is answered without calling canaccessvalue", ns.CanAccess(nil) == true and W.nilChecks == 0, W.nilChecks)

section("unit menu resolves the name from the unit, not context.name")
local root = {
    items = {},
    CreateDivider = function(self) self.items[#self.items+1] = {kind="divider"} end,
    CreateTitle = function(self, t) self.items[#self.items+1] = {kind="title", text=t} end,
    CreateButton = function(self, t, fn) self.items[#self.items+1] = {kind="button", text=t, fn=fn} end,
}
local function menuButtons()
    local labels = {}
    for _, it in ipairs(root.items) do if it.kind == "button" then labels[it.text] = it.fn end end
    return labels
end
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}
W.units = { target = { name = "Mangeclaw" } }
-- exactly what Blizzard passes for an NPC target frame
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon", fromTargetFrame = true })
local trackFn = menuButtons()["Track"]
check("Track offered", trackFn ~= nil)
check("one entry only", menuButtons()["Track First"] == nil and menuButtons()["Untrack"] == nil)
W.chat = {}
if trackFn then trackFn(); RunTimers() end
check("stored the NPC name", ns.targets[1] and ns.targets[1].name == "Mangeclaw",
      ns.targets[1] and ns.targets[1].name)
check("did NOT store 'Raid Target Icon'", ns.targets[1] and ns.targets[1].name ~= "Raid Target Icon")
check("a player's Track creates FIND", W.macros["FIND"] ~= nil)
check("tracking never calls SetRaidTarget", W.markCalls == 0, W.markCalls)
check("one chat line with the bar reminder", #W.chat == 1 and chatHas("^.*Tracking Mangeclaw%. Drag FIND from the Target Finder window %(/tf%) to an action bar%.$"),
      table.concat(W.chat, " / "))
W.chat = {}
ns.AddFinder("Second Pick")
check("the reminder comes once per session", #W.chat == 1 and not chatHas("Drag FIND"), table.concat(W.chat, " / "))

section("friendly players get no Target Finder entries")
ns.WipeTargets()
root.items = {}
W.units = { target = { name = "Someguy", player = true, friend = true } }
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Someguy" })
check("no section for a friendly player", #root.items == 0, #root.items)
W.units = { target = { name = "Rogue", player = true } }
W.menuHooks["MENU_UNIT_ENEMY_PLAYER"](nil, root, { unit = "target", name = "Rogue" })
check("an enemy player can be tracked", menuButtons()["Track"] ~= nil)

section("menu action follows the exact name")
ns.WipeTargets()
ns.targets[2] = ns.MakeEntry("Auctioneer Chillgular")
root.items = {}
W.units = { target = { name = "Auctioneer Chillgular" } }
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
local labels = menuButtons()
check("Untrack offered for a tracked NPC", labels["Untrack"] ~= nil)
check("Track hidden for a tracked NPC", labels["Track"] == nil)
check("no Clear entry in unit menus", labels["Clear Unit List"] == nil and labels["Clear All"] == nil)
W.chat = {}
labels["Untrack"](); RunTimers()
check("Untrack removes the entry", ns.SlotForName("Auctioneer Chillgular") == nil)
check("one chat line with the window closed", #W.chat == 1 and chatHas("Removed Auctioneer Chillgular%.$"), table.concat(W.chat, " / "))
ns.targets[1] = ns.MakeEntry("Auctioneer")
root.items = {}
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
check("a prefix entry does not cover the NPC", menuButtons()["Track"] ~= nil)

section("menu does not test secret booleans")
root.items = {}
W.units = { target = { name = "Enemy", player = true, secret = true } }
local menuOk, menuErr = pcall(function()
    W.menuHooks["MENU_UNIT_ENEMY_PLAYER"](nil, root, { unit = "target", name = "Enemy" })
end)
check("menu builds without error under restriction", menuOk, menuErr)
check("a hidden name adds nothing", #root.items == 0, #root.items)

section("Questie readiness follows Questie.API.isReady")
check("absent Questie reports not loaded", ns.QuestieReady() == false)
check("excuse names absence", ns.QuestieExcuse() == "Questie is not loaded.", ns.QuestieExcuse())
-- the database is complete, but Questie has not finished its init
local noop = function() end
local earlyDB = { QueryNPCSingle = noop, QueryQuestSingle = noop, QueryItemSingle = noop, NPCPointers = {} }
_G.QuestieLoader = { ImportModule = function(_, m)
    if m == "QuestieDB" then return earlyDB end
    return {}
end }
_G.Questie = { API = {
    isReady = false,
    RegisterOnReady = function(cb) W.readyCallbacks[#W.readyCallbacks+1] = cb end,
    RegisterForQuestUpdates = function(cb) W.questCallbacks[#W.questCallbacks+1] = cb end,
} }
check("a built database before isReady is not ready", ns.QuestieReady() == false)
check("excuse names the loading state", ns.QuestieExcuse() == "Questie is still loading.", ns.QuestieExcuse())
W.chat = {}
ns.WipeTargets()
local loadingOk, loadingErr = pcall(ns.SetQuestNpcs, true)
check("Quest NPCs waits quietly while Questie loads", loadingOk and ns.TargetCount() == 0 and #W.chat == 0, loadingErr)
check("no suggestions while loading", #ns.FindSuggestions("kob") == 0)

local login
for f in pairs(_G.__frames) do if f.events["PLAYER_LOGIN"] then login = f end end
W.macroOrder = {}; W.macros = {}
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Saved")
login.scripts.OnEvent(login, "PLAYER_LOGIN")
check("login registers for Questie's ready callback", #W.readyCallbacks == 1 and type(W.readyCallbacks[1]) == "function")
check("login registers for Questie's quest updates", #W.questCallbacks == 1)
check("login never creates FIND", W.macros["FIND"] == nil)
ns.WriteFinderMacro()
W.macros["FIND"].body = "edited by hand"
login.scripts.OnEvent(login, "PLAYER_LOGIN")
check("login rewrites an existing FIND", W.macros["FIND"].body == "/targetexact Saved" .. TAIL, W.macros["FIND"].body)

_G.Questie.API.isReady = true
earlyDB.NPCPointers = nil
check("a reshaped database is not ready", ns.QuestieReady() == false)
check("excuse names an unknown version", ns.QuestieExcuse() == "This Questie version is not supported.", ns.QuestieExcuse())
_G.Questie.started = false
check("excuse names a failed start", ns.QuestieExcuse():match("^Questie failed to start") ~= nil, ns.QuestieExcuse())
_G.Questie = {}
check("an emptied Questie table reads as absent", ns.QuestieExcuse() == "Questie is not loaded.", ns.QuestieExcuse())
_G.QuestieLoader = nil
_G.Questie = nil

-- A small Questie world with the shapes the installed Questie 12.0.3 uses: quest objects in
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
        [8] = { name = "Crate Hauler", spawns = { [12] = { {95, 95} } } },
        [9] = { name = "Looter" },
    }
    local quests = {
        [100] = { name = "Kobold Trouble", startedBy = { {4} }, finishedBy = { {5} } },
    }
    -- item 10 also comes out of the crate item 11, which Crate Hauler drops
    local items = { [10] = { npcDrops = { 3, 6 }, itemDrops = { 11 } }, [11] = { npcDrops = { 8 } } }
    local quest = {
        Id = 100,
        ObjectiveData = {
            { Type = "monster", Id = 1 },
            { Type = "monster", Id = 2 },
            { Type = "item", Id = 10 },
        },
        Objectives = { [1] = { Completed = true }, [2] = { Completed = false } },
    }
    local state = { complete = 0, nameReads = 0 }
    local modules = {
        QuestieDB = {
            NPCPointers = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true },
            QueryNPCSingle = function(id, key)
                if key == "name" then state.nameReads = state.nameReads + 1 end
                local r = npcs[id]; return r and r[key]
            end,
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
        API = { isReady = true },
        usedIcons = { [1] = "slay", [2] = "loot", [8] = "complete" },
        ICON_TYPE_SLAY = 1, ICON_TYPE_LOOT = 2, ICON_TYPE_COMPLETE = 8,
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
check("droppers of the item's container offered", names["Crate Hauler"] ~= nil and picks[names["Crate Hauler"]].kind == ns.KIND_DROP)
check("finished objective skipped", names["Done Wolf"] == nil)
check("quest giver never offered once accepted", names["Quest Giver"] == nil)
check("turn-in NPC waits for the quest to be complete", names["Turn In Guy"] == nil)
check("entries are quest-sourced", picks[1] and picks[1].quest == true)
check("kill sorts before drop", picks[1] and picks[1].name == "Kobold Miner" and picks[1].kind == ns.KIND_KILL,
      picks[1] and picks[1].name)
quest.Objectives[2].Completed = true
check("Completed flag drops a kill target", namesOf(ns.QuestNpcs(100))["Kobold Miner"] == nil)
questState.complete = 1
local turnIn = ns.QuestNpcs(100)
check("a complete quest offers only its turn-in NPC", #turnIn == 1 and turnIn[1].name == "Turn In Guy" and turnIn[1].kind == ns.KIND_TURNIN,
      turnIn[1] and turnIn[1].name)
questState.complete = 0
quest.Objectives[2].Completed = false
modules.QuestiePlayer.currentQuestlog[100] = 100
check("a bare quest id falls back to the database object", namesOf(ns.QuestNpcs(100))["Kobold Miner"] ~= nil)
modules.QuestiePlayer.currentQuestlog[100] = quest

section("the NPC name index is built once Questie is ready")
questState.nameReads = 0
W.timers = {}
W.readyCallbacks[1]()
check("the ready callback defers the index pass", questState.nameReads == 0, questState.nameReads)
RunTimers()
check("the deferred pass reads every NPC name", questState.nameReads >= 7, questState.nameReads)

local function questEntries()
    local n = 0
    for slot = 1, ns.MAX_TARGETS do if ns.targets[slot] and ns.targets[slot].quest then n = n + 1 end end
    return n
end
local zoneEvents
for f in pairs(_G.__frames) do if f.events["ZONE_CHANGED_NEW_AREA"] then zoneEvents = f end end
local function zoneChange(event) zoneEvents.scripts.OnEvent(zoneEvents, event or "ZONE_CHANGED_NEW_AREA"); RunTimers() end

section("quest NPCs fill the list by themselves")
check("zone and subzone changes are watched", zoneEvents ~= nil and zoneEvents.events["ZONE_CHANGED"] == true)
C_Map.GetBestMapForUnit = function() return 1429 end
C_Map.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end
W.units = {}
ns.WipeTargets()
ns.targets[3] = ns.MakeEntry("Typed Wolf")
W.macroOrder = {}; W.macros = {}
W.chat = {}
zoneEvents.scripts.OnEvent(zoneEvents, "ZONE_CHANGED_NEW_AREA")
check("the sync waits for the next frame", ns.TargetCount() == 1)
RunTimers()
check("kill target leads", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)
check("closest dropper follows", ns.targets[2] and ns.targets[2].name == "Kobold Looter", ns.targets[2] and ns.targets[2].name)
check("a typed name keeps its slot", ns.targets[3] and ns.targets[3].name == "Typed Wolf")
check("the next quest NPC skips the typed slot", ns.targets[4] and ns.targets[4].name == "Crate Hauler", ns.targets[4] and ns.targets[4].name)
check("startedBy skipped once accepted", ns.SlotForName("Quest Giver") == nil)
check("dropper in another zone skipped", ns.SlotForName("Kobold Far Away") == nil)
check("quest entries carry their kind", ns.targets[1].kind == ns.KIND_KILL and ns.targets[2].kind == ns.KIND_DROP)
check("the fill is silent", #W.chat == 0, table.concat(W.chat, " / "))
check("an automatic change never creates FIND", W.macros["FIND"] == nil)

section("finished quest entries leave silently, and the rest hold still")
ns.WriteFinderMacro()
quest.Objectives[2].Completed = true
W.questCallbacks[1](100, 2, 2)
W.questCallbacks[1](100, 3, 2)
check("the check waits for the next frame", ns.targets[1] ~= nil)
RunTimers()
check("the finished kill target left the list", ns.SlotForName("Kobold Miner") == nil)
check("the open objectives keep their slots", ns.targets[2].name == "Kobold Looter" and ns.targets[4].name == "Crate Hauler")
check("typed entries are never touched", ns.SlotForName("Typed Wolf") == 3)
check("no chat line", #W.chat == 0, table.concat(W.chat, " / "))
check("an existing FIND follows", not W.macros["FIND"].body:match("Kobold Miner") and W.macros["FIND"].body:match("Kobold Looter") ~= nil,
      W.macros["FIND"].body)
quest.Objectives[2].Completed = false
W.questCallbacks[1](100, 2, 1)
RunTimers()
check("an accepted objective fills the free slot", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)

section("turn-ins and unplaceable maps")
questState.complete = 1
zoneChange("ZONE_CHANGED")
check("a complete quest leaves only its turn-in NPC", questEntries() == 1 and ns.SlotForName("Turn In Guy") ~= nil, questEntries())
check("typed names stay", ns.SlotForName("Typed Wolf") == 3)
questState.complete = 0
quest.isComplete = true
zoneChange()
check("Questie's own isComplete flag counts too", questEntries() == 1 and ns.SlotForName("Turn In Guy") ~= nil)
quest.isComplete = nil

C_Map.GetBestMapForUnit = function() return 999 end
W.units = { nameplate1 = { name = "Kobold Looter" } }
W.chat = {}
zoneEvents.scripts.OnEvent(zoneEvents, "ZONE_CHANGED_NEW_AREA")
local nearbyOk, nearbyErr = pcall(RunTimers)
check("a map Questie cannot place does not raise", nearbyOk, nearbyErr)
check("nameplates still count as nearby", questEntries() == 1 and ns.SlotForName("Kobold Looter") ~= nil, questEntries())
check("no read failure reported", not chatHas("Could not read"))
C_Map.GetBestMapForUnit = function() return 1429 end
W.units = {}
zoneChange()

section("the Quest NPCs setting")
ns.SetQuestNpcs(false)
check("off saves the choice", TargetFinderCharDB.questNpcs == false)
check("off takes every quest entry away", questEntries() == 0, questEntries())
check("off keeps typed names", ns.SlotForName("Typed Wolf") == 3)
zoneChange()
check("a new zone fills nothing while off", questEntries() == 0)
ns.SetQuestNpcs(true)
check("on fills the list at once", questEntries() == 3 and ns.SlotForName("Kobold Miner") ~= nil, questEntries())

section("the quest-update check skips a list without quest entries")
TargetFinderCharDB.questNpcs = false
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Typed Only")
local openReads = 0
local realOpen = ns.OpenQuestNpcNames
ns.OpenQuestNpcNames = function() openReads = openReads + 1; return realOpen() end
W.questCallbacks[1](100, 1, 2)
RunTimers()
check("no quest log walk without quest entries", openReads == 0, openReads)
ns.OpenQuestNpcNames = realOpen
TargetFinderCharDB.questNpcs = true

section("search suggestions")
local results = ns.FindSuggestions("kob")
check("quest name first", results[1] and results[1].type == "quest" and results[1].name == "Kobold Trouble",
      results[1] and results[1].name)
check("quest NPC tagged with its quest", results[2] and results[2].isQuestNpc and results[2].questName == "Kobold Trouble",
      results[2] and results[2].name)
local plain
for _, r in ipairs(results) do if r.name == "Kobold Tunneler" then plain = r end end
check("plain database NPCs follow", plain ~= nil and not plain.isQuestNpc)
check("Questie icons resolve per kind", ns.QuestieKindIcons()[ns.KIND_KILL] == "slay" and ns.QuestieKindIcons()[ns.KIND_TURNIN] == "complete")

section("panel is a native ButtonFrameTemplate window")
local UI = LibStub("LibNativeUI-1.0")
local function onGrid(v) return v % UI.GRID == 0 end
ns.WipeTargets()
ns.TogglePanel()
local panel = _G.TargetFinderFrame
check("the toggle opens the panel", panel and panel.shown == true)
check("built from ButtonFrameTemplate", panel and panel.template == "ButtonFrameTemplate", panel and panel.template)
check("portrait shows the toc icon", panel.portraitAsset == toc["IconTexture"], panel.portraitAsset)
check("panel height is on the grid", panel.height and onGrid(panel.height), panel.height)
check("the window keeps its position", panel.points[1] and panel.points[1].point == "CENTER")
check("title is the spaced name only", panel.title == "Target Finder", panel.title)
check("HIGH strata", panel.strata == "HIGH", panel.strata)
local escapable = false
for _, name in ipairs(UISpecialFrames) do if name == "TargetFinderFrame" then escapable = true end end
check("Escape closes it", escapable)
check("no bar buttons", panel.barButtons == nil)
local row1 = panel.rows[1]
check("rows live in the Inset", row1.parent == panel.Inset)
local rowAnchor = row1.points[1]
check("rows are padded on the grid", rowAnchor.x == UI.Space.padding and rowAnchor.y == -UI.Space.padding, rowAnchor.x)
check("rows sit one gap apart", panel.rows[2].points[1].y == -(UI.Space.padding + UI.Size.row + UI.Space.gap), panel.rows[2].points[1].y)
check("Add fills the fixed 48px column at the row height", row1.addBtn.width == 48 and row1.addBtn.height == UI.Size.row, row1.addBtn.width)
check("the X sits centred in Add's column", row1.removeBtn.points[1].point == "CENTER" and row1.removeBtn.points[1].rel == row1.addBtn)
check("panel width is on the grid", panel.width and onGrid(panel.width), panel.width)
check("inputs use the 12px body font", row1.input.fontObject == UI.Font.body, row1.input.fontObject and row1.input.fontObject.name)
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
ns.targets[1] = ns.MakeEntry("Mine")
ns.targets[2] = ns.MakeEntry("Other")
row1.input:SetText("Mine")
row1.updateState()
check("a stored row offers its X", row1.removeBtn.shown == true and row1.addBtn.shown == false)
row1.input:SetText("Other")
row1.updateState()
check("another slot's name offers Add, never that slot's X", row1.addBtn.shown == true and row1.removeBtn.shown == false)
row1.input:SetText("")
row1.updateState()
W.chat = {}
row1.removeBtn.scripts.OnClick(row1.removeBtn)
check("the X clears its own row", ns.targets[1] == nil and ns.targets[2] ~= nil)
check("no chat line while the window shows the change", #W.chat == 0, table.concat(W.chat, " / "))
ns.WipeTargets()
check("close button hides the panel itself, skipping HideUIPanel", panel.onCloseCallback() == false and panel.shown == false)
panel.shown = true

section("rows show where a quest NPC comes from")
ns.targets[1] = ns.MakeEntry("Quest Mob", true, ns.KIND_KILL)
ns.targets[2] = ns.MakeEntry("Typed Mob")
ns.RefreshPanel()
check("a quest row shows Questie's icon for its kind", row1.icon.texturePath == "slay" and row1.icon.shown == true, row1.icon.texturePath)
check("a typed row shows no icon", panel.rows[2].icon.shown == false)
check("an empty row shows no icon", panel.rows[3].icon.shown == false)

section("the Quest NPCs box")
local box = panel.questBox
local boxAnchor = box.points[1]
check("a native checkbox", box.template == "CheckboxWithLabelTemplate", box.template)
check("it sits where a bar button would start", boxAnchor.point == "LEFT" and boxAnchor.rel == panel and boxAnchor.relPoint == "BOTTOMLEFT"
      and boxAnchor.x == 4 and boxAnchor.y == 4 + UI.Native.buttonHeight / 2, tostring(boxAnchor.x) .. "," .. tostring(boxAnchor.y))
check("it is labelled", box.Text.text == "Quest NPCs", box.Text.text)
check("it mirrors the setting", box.checked == true)
check("it is on while Questie is ready", box.enabled == true and box.Text.fontObject == UI.Font.body)
ns.WipeTargets()
ns.targets[3] = ns.MakeEntry("Typed Wolf")
box:SetChecked(false)
box.scripts.OnClick(box)
check("unticking saves the choice", TargetFinderCharDB.questNpcs == false)
box:SetChecked(true)
box.scripts.OnClick(box)
check("ticking fills the list at once", questEntries() == 3 and ns.SlotForName("Typed Wolf") == 3, questEntries())
box:SetChecked(false)
box.scripts.OnClick(box)
check("unticking clears quest NPCs and keeps typed names", questEntries() == 0 and ns.SlotForName("Typed Wolf") == 3, questEntries())
box:SetChecked(true)
box.scripts.OnClick(box)
box.scripts.OnEnter(box)
check("the tooltip uses Blizzard's title helper", W.tooltip[1] == "title:Quest NPCs", W.tooltip[1])
_G.Questie.API.isReady = false
ns.RefreshPanel()
check("off and greyed while Questie loads", box.enabled == false and box.Text.fontObject == UI.Font.muted)
box.scripts.OnEnter(box)
check("the tooltip says why", W.tooltip[#W.tooltip] == "error:Questie is still loading.", W.tooltip[#W.tooltip])
_G.Questie.API.isReady = true
W.readyCallbacks[1]()
RunTimers()
check("Questie's ready callback turns it on", box.enabled == true)

section("FIND comes from the window icon")
local dragIcon
for _, f in ipairs(W.created) do
    if f.parent == panel.PortraitContainer and f.kind == "Button" then dragIcon = f end
end
check("a button sits on the portrait", dragIcon ~= nil)
check("it drags with the left button", dragIcon and dragIcon.scripts.OnDragStart ~= nil)
W.macroOrder = {}; W.macros = {}; W.cursorMacro = nil; W.actions = {}
ns.RefreshPanel()
check("help says to place FIND", panel.help.text == "Drag the icon to an action bar to use FIND.", panel.help.text)
dragIcon.scripts.OnDragStart(dragIcon)
check("the first drag creates FIND", W.macros["FIND"] ~= nil)
check("and puts it on the cursor", W.cursorMacro ~= nil and W.cursorMacro == GetMacroIndexByName("FIND"), W.cursorMacro)
W.actions[5] = { kind = "macro", id = GetMacroIndexByName("FIND") }
panel.scripts.OnEvent(panel, "ACTIONBAR_SLOT_CHANGED")
check("on a bar, help says to press it", panel.help.text == "Press FIND to target the first NPC in range.", panel.help.text)
W.actions = {}
W.inCombat = true
W.cursorMacro = nil
dragIcon.scripts.OnDragStart(dragIcon)
check("no pickup in combat", W.cursorMacro == nil)
W.inCombat = false
dragIcon.scripts.OnEnter(dragIcon)
check("its tooltip names FIND", W.tooltip[1] == "title:FIND", W.tooltip[1])

section("suggestion popup mirrors Blizzard's AutoCompleteBox")
ns.WipeTargets()
local input = row1.input
input:SetText("kob")
input.scripts.OnTextChanged(input, true)
local pop = _G.TargetFinderSuggestions
check("one shared popup on TooltipBackdropTemplate", pop and pop.template == "TooltipBackdropTemplate", pop and pop.template)
check("popup sits on the dialog strata above the panel", pop.strata == UI.Strata.dialog, pop.strata)
check("popup shown for the typing row", pop and pop.shown == true and pop.owner == input)
local firstRow = _G.TargetFinderSuggestionsButton1
local secondRow = _G.TargetFinderSuggestionsButton2
check("rows use AutoCompleteButtonTemplate", firstRow and firstRow.template == "AutoCompleteButtonTemplate",
      firstRow and firstRow.template)
check("popup rows and height sit on the grid", firstRow.height == 16 and onGrid(pop.height), pop.height)
check("no Add All row", _G.TargetFinderSuggestionsAddAll == nil)
check("quest rows are labelled", firstRow and firstRow.text == "[Quest] Kobold Trouble", firstRow and firstRow.text)
check("quest tags use Blizzard's grey", secondRow.text == "Kobold Miner |cff808080(Kobold Trouble)|r", secondRow.text)
check("the first NPC row is preselected, never the quest row", not firstRow.locked and secondRow.locked == true)
input.scripts.OnArrowPressed(input, "DOWN")
check("arrow down moves the highlight", secondRow.locked == false and _G.TargetFinderSuggestionsButton3.locked == true)
input.scripts.OnArrowPressed(input, "UP")
check("arrow up moves it back", secondRow.locked == true)
input.scripts.OnEnterPressed(input)
check("Enter stores the highlighted NPC", ns.targets[1] and ns.targets[1].name == "Kobold Miner",
      ns.targets[1] and ns.targets[1].name)
check("a picked quest NPC stays until removed, like a typed name", ns.targets[1].quest == nil and ns.targets[1].kind == nil)
zoneChange("ZONE_CHANGED")
check("a subzone change keeps it", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)
check("popup closes after the pick", pop.shown == false)

input:SetText("looter")
input.scripts.OnTextChanged(input, true)
check("a name typed in full wins the preselection", secondRow.entry and secondRow.entry.name == "Looter" and secondRow.locked == true
      and not firstRow.locked, firstRow.entry and firstRow.entry.name)

input:SetText("kob")
input.scripts.OnTextChanged(input, true)
input.scripts.OnTabPressed(input)
check("Tab completes the selected NPC without storing it", input.text == "Kobold Miner" and pop.shown == false, input.text)

ns.WipeTargets()
input:SetText("trouble")
input.scripts.OnTextChanged(input, true)
check("a lone quest row is not preselected", firstRow.entry and firstRow.entry.type == "quest" and not firstRow.locked)
firstRow.scripts.OnClick(firstRow)
check("a quest pick puts that quest's NPCs first", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)
check("even its NPCs outside the zone", ns.SlotForName("Kobold Far Away") ~= nil)
check("the row shows its new entry", input.text == "Kobold Miner", input.text)

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
check("LibDBIcon launcher registered at login", W.ldbObject ~= nil)
check("launcher icon is the toc icon", W.ldbObject.icon == toc["IconTexture"], W.ldbObject.icon)
check("launcher is named after the addon", W.ldbObject.type == "launcher" and W.ldbObject.text == "Target Finder")
W.ldbObject.OnTooltipShow(GameTooltip)
check("minimap tooltip says what a click does and what is missing",
      W.tooltip[1] == "title:Target Finder" and W.tooltip[2] == "instruction:Click to toggle the window."
      and W.tooltip[3] == "error:Questie is not loaded.", table.concat(W.tooltip, " / "))
local entries = {}
for _, data in ipairs(AddonCompartmentFrame.registeredAddons) do
    if data.text == "Target Finder" then entries[#entries+1] = data end
end
check("the addon menu lists the addon once", #entries == 1, #entries)
local entry = entries[1]
local wasShown = panel.shown
entry.func(nil, { buttonName = "LeftButton" })
check("addon menu left-click toggles the panel", panel.shown ~= wasShown)
entry.func(nil, { buttonName = "RightButton" })
check("a right-click toggles it too", panel.shown == wasShown)

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
      and W.macros["FIND"].body == "/targetexact Deferred" .. TAIL, W.macros["FIND"] and W.macros["FIND"].body)
W.errors = {}
W.inCombat = true
ns.targets[2] = ns.MakeEntry("Auto")
ns.WriteFinderMacro(true)
check("an automatic change in combat shows no notice", #W.errors == 0, #W.errors)
W.inCombat = false
regen.scripts.OnEvent(regen, "PLAYER_REGEN_ENABLED")
check("and lands after combat", W.macros["FIND"].body:match("/targetexact Auto") ~= nil, W.macros["FIND"].body)

section("list operations")
ns.WipeTargets()
ns.AddFinder("First"); ns.AddFinder("Second"); ns.AddFinder("Third")
check("three tracked", ns.TargetCount() == 3)
check("the latest pick goes first", ns.targets[1].name == "Third" and ns.targets[2].name == "Second" and ns.targets[3].name == "First")
W.chat = {}
ns.AddFinder("Second")
check("a duplicate is refused", ns.TargetCount() == 3 and chatHas("Second is already tracked%."), table.concat(W.chat, " / "))
ns.RemoveFinder(2)
check("removed leaves a hole", ns.targets[2] == nil and ns.TargetCount() == 2)

section("quest entries sync without touching typed names")
ns.WipeTargets()
ns.WriteFinderMacro()
ns.targets[1] = ns.MakeEntry("Typed")
ns.targets[2] = ns.MakeEntry("OldQuest", true, ns.KIND_KILL)
ns.SyncQuestEntries({ {name="New1", kind=ns.KIND_KILL}, {name="New2", kind=ns.KIND_DROP} })
check("a typed name keeps its slot", ns.targets[1] and ns.targets[1].name == "Typed", ns.targets[1] and ns.targets[1].name)
check("a full sync swaps every quest entry", ns.SlotForName("OldQuest") == nil and ns.targets[2].name == "New1" and ns.targets[3].name == "New2")
check("new entries are quest entries with their kind", ns.targets[3].quest == true and ns.targets[3].kind == ns.KIND_DROP)
check("FIND follows", W.macros["FIND"].body:match("/targetexact New2") ~= nil, W.macros["FIND"].body)
ns.SyncQuestEntries({ {name="New3"} }, { New1 = true })
check("a light sync keeps what quests still need", ns.targets[2] and ns.targets[2].name == "New1")
check("drops the rest", ns.SlotForName("New2") == nil)
check("and fills the free slot", ns.targets[3] and ns.targets[3].name == "New3")
W.macros["FIND"].body = "sentinel"
ns.SyncQuestEntries({ {name="New3"} }, { New1 = true, New3 = true })
check("an unchanged list leaves FIND alone", W.macros["FIND"].body == "sentinel")
ns.WipeTargets()
for i = 1, 8 do ns.targets[i] = ns.MakeEntry("Typed" .. i) end
ns.SyncQuestEntries({ {name="Quest1"} })
check("typed names are never pushed out", ns.SlotForName("Quest1") == nil and ns.TargetCount() == 8)

section("a full list makes room for a tracked name")
panel.shown = false
ns.WipeTargets()
for i = 1, 6 do ns.targets[i] = ns.MakeEntry("Typed" .. i) end
ns.targets[7] = ns.MakeEntry("Quest7", true, ns.KIND_KILL)
ns.targets[8] = ns.MakeEntry("Typed8")
W.chat = {}
ns.AddFinder("Ninth")
check("the tracked name goes first", ns.targets[1].name == "Ninth" and ns.TargetCount() == 8)
check("the last quest entry made room", ns.SlotForName("Quest7") == nil and ns.SlotForName("Typed8") ~= nil)
check("one line names what left", #W.chat == 1 and chatHas("Tracking Ninth%. The list was full, so Quest7 was removed%.$"), table.concat(W.chat, " / "))
ns.AddFinder("Tenth")
check("with only typed names the last one leaves", ns.targets[1].name == "Tenth" and ns.SlotForName("Typed8") == nil and ns.TargetCount() == 8)

section("slash command")
check("/tf and /targetfinder are registered", SLASH_TARGETFINDER1 == "/targetfinder" and SLASH_TARGETFINDER2 == "/tf")
local before = panel.shown
SlashCmdList.TARGETFINDER("")
check("the bare slash command toggles the panel", panel.shown ~= before)
W.chat = {}
SlashCmdList.TARGETFINDER(" Minimap ")
check("/tf minimap hides the minimap button", TargetFinderDB.minimap.hide == true and W.minimapShown == false)
check("and says how to bring it back", chatHas("/tf minimap to show it again"), W.chat[1])
SlashCmdList.TARGETFINDER("minimap")
check("a second /tf minimap shows it", TargetFinderDB.minimap.hide == false and W.minimapShown == true)

section("markers only ever go on through /tm")
check("the addon never called SetRaidTarget", W.markCalls == 0, W.markCalls)
check("target changes are not watched", boot.events["PLAYER_TARGET_CHANGED"] == nil)

io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
