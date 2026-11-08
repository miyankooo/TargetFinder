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
local function targetCount()
    local n = 0
    for slot = 1, ns.MAX_TARGETS do
        if ns.targets[slot] then n = n + 1 end
    end
    return n
end

-- boot the addon the way the client does; from here on every chat line is kept
W.allChat = {}
W.chat = {}
TargetFinderDB = nil; TargetFinderCharDB = nil
local boot
for f in pairs(_G.__frames) do if f.events["ADDON_LOADED"] then boot = f end end
boot.scripts.OnEvent(boot, "ADDON_LOADED", "TargetFinder")
local firstLoadChat = #W.chat
local firstLoadFlag = ns.firstRun
-- the first-FIND introduction has its own section near the end
TargetFinderCharDB.finderIntroduced = true

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
check("the marker module and the glow load", tocFiles["Core\\Markers.lua"] and tocFiles["UI\\FinderGlow.lua"])
-- the UI is built from Blizzard's templates directly; only the minimap button's libraries stay embedded
local libLines, uiLibrary = {}, false
for _, line in ipairs(tocOrder) do
    if line:match("^Libs\\") then libLines[#libLines+1] = line end
    if line:match("LibNativeUI") then uiLibrary = true end
end
check("no UI library in the toc", not uiLibrary)
check("only LibStub, CallbackHandler, LibDataBroker and LibDBIcon are embedded, in that order", #libLines == 4
      and libLines[1] == "Libs\\LibStub\\LibStub.lua" and libLines[2] == "Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua"
      and libLines[3] == "Libs\\LibDataBroker-1.1\\LibDataBroker-1.1.lua" and libLines[4] == "Libs\\LibDBIcon-1.0\\LibDBIcon-1.0.lua",
      table.concat(libLines, ", "))
local libraryCalls = {}
for _, line in ipairs(tocOrder) do
    if not line:match("^Libs\\") then
        local file = io.open(here .. "../" .. line:gsub("\\", "/"))
        local source = file:read("*a")
        file:close()
        if source:match("LibNativeUI") then libraryCalls[#libraryCalls+1] = line end
    end
end
check("no addon file reaches for LibNativeUI", #libraryCalls == 0, table.concat(libraryCalls, ", "))
-- LibDBIcon registers the addon menu entry itself, so toc entry points would list the addon twice
for _, key in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
    check("no toc " .. key, toc[key] == nil, toc[key])
end
check("no compartment globals left", TargetFinder_OnClick == nil and TargetFinder_OnEnter == nil and TargetFinder_OnLeave == nil)

section("boot and saved variables")
check("the first load prints nothing", firstLoadChat == 0, firstLoadChat)
check("an absent account table marks the first run", firstLoadFlag == true)
check("the welcome line waits for login", #W.loginCallbacks == 1, #W.loginCallbacks)
check("minimap defaults created", TargetFinderDB.minimap.minimapPos == 215)
check("targets aliased to live table", TargetFinderCharDB.targets == ns.targets)
check("Auto Apply Quest NPCs starts on", TargetFinderCharDB.questNpcs == true)
check("Apply Raid Markers starts on", TargetFinderCharDB.raidMarkers == true)
-- the plain FIND body is the subject until the marker section turns this back on
TargetFinderCharDB.raidMarkers = false
check("unit menus registered", W.menuHooks["MENU_UNIT_TARGET"] ~= nil)
local targetFrameMenus = true
for _, tag in ipairs({ "MENU_UNIT_TARGET", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_FOCUS", "MENU_UNIT_BOSS" }) do
    if not W.menuHooks[tag] then targetFrameMenus = false end
end
check("every menu the target frame opens is registered", targetFrameMenus)
check("chat, friends and self menus left alone", W.menuHooks["MENU_UNIT_FRIEND"] == nil and W.menuHooks["MENU_UNIT_SELF"] == nil)

section("saved-variable sanitising")
ns.AdoptSaved({ {name="Good", quest=true, kind=1}, {name=""}, {nope=true}, "junk", {name="Also", kind=2, quest="yes"},
    {name="Odd", quest=true, kind=9} })
check("kept only well-formed entries", targetCount() == 3, targetCount())
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
local TAIL = "\n/targetlasttarget [dead]"
check("exact names reversed so slot 1 wins last, then the corpse guard, and no marker line",
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
check("the corpse guard always stays", b:sub(-#TAIL) == TAIL, b:sub(-#TAIL))

section("macro cap is reported, not silent")
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}; W.macroCap = 0
W.chat = {}
ns.targets[1] = ns.MakeEntry("Anything")
ns.WriteFinderMacro()
check("cap failure announced", chatHas("Delete one in the macro book"), table.concat(W.chat, " / "))
W.macroCap = 120

section("Apply Raid Markers adds RestedXP's marker line to FIND")
TargetFinderCharDB.raidMarkers = true
W.units = {}
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Alpha"); ns.targets[2] = ns.MakeEntry("Beta"); ns.targets[4] = ns.MakeEntry("Delta")
ns.WriteFinderMacro()
check("RestedXP's body: reversed names, the cross, then the corpse guard",
      W.macros["FIND"].body == "/targetexact Delta\n/targetexact Beta\n/targetexact Alpha\n/tm !7\n/targetlasttarget [dead]",
      (W.macros["FIND"].body:gsub("\n", "|")))
check("the addon itself never marks", W.markCalls == 0, W.markCalls)
ns.WipeTargets()
for i = 1, 8 do ns.targets[i] = ns.MakeEntry(("Name%d"):format(i) .. string.rep("x", 28)) end
ns.WriteFinderMacro()
local full = W.macros["FIND"].body
check("a long list stays within the cap", #full <= 255, #full)
check("the marker and the corpse guard always stay", full:sub(-32) == "\n/tm !7\n/targetlasttarget [dead]", (full:gsub("\n", "|")))
check("the lowest rows drop first", full:match("Name8") == nil and full:match("/targetexact Name1x+\n/tm") ~= nil)
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Kobold")
ns.WriteFinderMacro()
local function marks() return W.macros["FIND"].body:match("\n/tm !7\n") ~= nil end
check("solo, FIND marks", marks())
local macroEvents
for f in pairs(_G.__frames) do if f.events["GROUP_ROSTER_UPDATE"] then macroEvents = f end end
check("group changes are watched", macroEvents ~= nil and macroEvents.events["PARTY_LEADER_CHANGED"] == true)
local function groupEvent(event) macroEvents.scripts.OnEvent(macroEvents, event or "GROUP_ROSTER_UPDATE") end
W.group = "party"
groupEvent()
check("a party member who does not lead gets no marker line", not marks(), W.macros["FIND"].body)
W.leader = true
groupEvent("PARTY_LEADER_CHANGED")
check("the party leader marks", marks())
W.group, W.leader = "raid", false
groupEvent()
check("a plain raid member gets no marker line", not marks())
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
ns.SetRaidMarkers(false)
check("unticking rewrites FIND without markers", not marks() and TargetFinderCharDB.raidMarkers == false)
ns.SetRaidMarkers(true)
check("ticking puts them back", marks())
W.macroOrder = {}; W.macros = {}
W.group = "party"
groupEvent()
check("a group change never creates FIND", W.macros["FIND"] == nil)
W.group = nil
groupEvent()
TargetFinderCharDB.raidMarkers = false

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
-- Blizzard's unit menu as the ModifyMenu callback finds it: the unit's name title first, then Blizzard's own entries
local root = {
    Insert = function(self, description, index) table.insert(self.items, index, description); return description end,
}
local function resetRoot()
    root.items = { {kind="title", text="Unit Name"}, {kind="button", text="Set Focus"} }
end
resetRoot()
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
check("one chat line with the bar reminder", #W.chat == 1 and chatHas("^.*Tracking Mangeclaw%. Drag FIND from the macro book %(/m%) to an action bar%.$"),
      table.concat(W.chat, " / "))
check("the line opens with the gold title, the rest uncoloured", W.chat[1]
      == NORMAL_FONT_COLOR:WrapTextInColorCode("[Target Finder]") .. ": Tracking Mangeclaw. Drag FIND from the macro book (/m) to an action bar.",
      W.chat[1])
check("Track opens the macro book", MacroFrame and MacroFrame.shown == true)
check("on the character tab with FIND selected", MacroFrame and MacroFrame.tab == 2 and MacroFrame.selected == GetMacroIndexByName("FIND") - 120,
      MacroFrame and (tostring(MacroFrame.tab) .. "/" .. tostring(MacroFrame.selected)))
W.chat = {}
MacroFrame.shown = false
W.actions[7] = { kind = "macro", id = GetMacroIndexByName("FIND") }
ns.AddFinder("Second Pick")
check("the reminder comes once per session", #W.chat == 1 and not chatHas("Drag FIND"), table.concat(W.chat, " / "))
check("the macro book stays shut once FIND is on a bar", MacroFrame.shown == false)
W.actions = {}
W.inCombat = true
ns.AddFinder("Combat Pick")
check("the macro book stays shut in combat", MacroFrame.shown == false)
W.inCombat = false
for f in pairs(_G.__frames) do
    if f.events["PLAYER_REGEN_ENABLED"] then f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end
end
ns.WipeTargets()
ns.SetSlot(1, "Typed In Window")
check("typing in the window does not open the macro book", MacroFrame.shown == false)

section("players and NPCs get Track at the top of the menu")
ns.WipeTargets()
resetRoot()
W.units = { target = { name = "Mangeclaw" } }
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon", fromTargetFrame = true })
check("the unit's own name title stays first", root.items[1].text == "Unit Name")
check("Target Finder's title, Track and a divider follow it", root.items[2].kind == "title" and root.items[2].text == "Target Finder"
      and root.items[3].kind == "button" and root.items[3].text == "Track" and root.items[4].kind == "divider")
check("Blizzard's entries come after", root.items[5].text == "Set Focus")
W.tooltip = {}
root.items[3].tooltip(GameTooltip)
check("Track explains itself", W.tooltip[1] == "title:Track" and W.tooltip[2] == "normal:Puts Mangeclaw first on the FIND list, so FIND targets it before the rest.",
      table.concat(W.tooltip, " / "))
for _, who in ipairs({
    { tag = "MENU_UNIT_PLAYER", unit = { name = "Someguy", player = true, friend = true } },
    { tag = "MENU_UNIT_PARTY", unit = { name = "Buddy", player = true, friend = true, party = true } },
    { tag = "MENU_UNIT_RAID_PLAYER", unit = { name = "Raider", player = true, friend = true, raid = true } },
    { tag = "MENU_UNIT_ENEMY_PLAYER", unit = { name = "Rogue", player = true } },
}) do
    resetRoot()
    W.units = { target = who.unit }
    W.menuHooks[who.tag](nil, root, { unit = "target", name = who.unit.name })
    check(who.tag .. " offers Track at the top", root.items[3].text == "Track")
end
resetRoot()
W.units = { target = { name = "Buddy", player = true, friend = true, party = true } }
ns.targets[2] = ns.MakeEntry("Buddy")
W.menuHooks["MENU_UNIT_PARTY"](nil, root, { unit = "target", name = "Buddy" })
check("a tracked player offers Untrack", root.items[3].text == "Untrack")
ns.WipeTargets()

section("menu action follows the exact name")
ns.WipeTargets()
ns.targets[2] = ns.MakeEntry("Auctioneer Chillgular")
resetRoot()
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
ns.WipeTargets()
ns.targets[2] = ns.MakeEntry("Auctioneer Chillgular")
resetRoot()
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
local staleUntrack = menuButtons()["Untrack"]
-- a quest sync refills the rows while the menu is open
ns.targets[2] = ns.MakeEntry("Kobold Laborer", true, ns.KIND_KILL)
ns.targets[5] = ns.MakeEntry("Auctioneer Chillgular")
staleUntrack(); RunTimers()
check("Untrack removes the name, not the row it held when the menu opened",
      ns.SlotForName("Auctioneer Chillgular") == nil and ns.SlotForName("Kobold Laborer") == 2)
ns.targets[1] = ns.MakeEntry("Auctioneer")
resetRoot()
W.menuHooks["MENU_UNIT_TARGET"](nil, root, { unit = "target", name = "Raid Target Icon" })
check("a prefix entry does not cover the NPC", menuButtons()["Track"] ~= nil)

section("menu does not test secret booleans")
resetRoot()
W.units = { target = { name = "Enemy", player = true, secret = true } }
local menuOk, menuErr = pcall(function()
    W.menuHooks["MENU_UNIT_ENEMY_PLAYER"](nil, root, { unit = "target", name = "Enemy" })
end)
check("menu builds without error under restriction", menuOk, menuErr)
check("a hidden name adds nothing", #root.items == 2, #root.items)

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
check("Quest NPCs waits quietly while Questie loads", loadingOk and targetCount() == 0 and #W.chat == 0, loadingErr)
check("no suggestions while loading", #ns.FindSuggestions("kob") == 0)

-- PLAYER_LOGIN reaches the bootstrap frame and everything EventUtil.ContinueOnPlayerLogin collected
local login
for f in pairs(_G.__frames) do if f.events["PLAYER_LOGIN"] then login = f end end
local function LogIn()
    login.scripts.OnEvent(login, "PLAYER_LOGIN")
    for _, callback in ipairs(W.loginCallbacks) do callback() end
end
local WELCOME = NORMAL_FONT_COLOR:WrapTextInColorCode("[Target Finder]") .. ": One FIND macro targets the NPCs your quests need, "
    .. "plus any NPC or player you add. Open the " .. NORMAL_FONT_COLOR:WrapTextInColorCode("|Haddon:TargetFinder|h[Target Finder]|h")
    .. " window or type /tf to add your first name, or right-click a portrait and pick Track."
W.macroOrder = {}; W.macros = {}
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Saved")
W.chat = {}
LogIn()
check("the account's first login prints one welcome line", #W.chat == 1, table.concat(W.chat, " / "))
check("it says what the addon does, links the window, names /tf and the menu", W.chat[1] == WELCOME, W.chat[1])
check("login registers for Questie's ready callback", #W.readyCallbacks == 1 and type(W.readyCallbacks[1]) == "function")
check("login registers for Questie's quest updates", #W.questCallbacks == 1)
check("login never creates FIND", W.macros["FIND"] == nil)
ns.WriteFinderMacro()
W.macros["FIND"].body = "edited by hand"
-- a later session: the saved tables exist at ADDON_LOADED, so nothing marks a first run. The client hands the
-- character's list back as a fresh table, not the live one.
local savedDB = TargetFinderDB
local reloaded = {}
for slot, entry in pairs(TargetFinderCharDB.targets) do reloaded[slot] = { name = entry.name, quest = entry.quest, kind = entry.kind } end
TargetFinderCharDB.targets = reloaded
ns.firstRun = nil
boot.scripts.OnEvent(boot, "ADDON_LOADED", "TargetFinder")
W.chat = {}
LogIn()
check("a later session keeps the account table", TargetFinderDB == savedDB and ns.db == savedDB)
check("a later login prints nothing", #W.chat == 0, table.concat(W.chat, " / "))
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
        API = { isReady = true, Enums = { QuestUpdateTriggerReason = { QUEST_ACCEPTED = 1, QUEST_UPDATED = 2, QUEST_TURNED_IN = 3, QUEST_ABANDONED = 4 } } },
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
check("the sync waits for the next frame", targetCount() == 1)
RunTimers()
check("kill target leads", ns.targets[1] and ns.targets[1].name == "Kobold Miner", ns.targets[1] and ns.targets[1].name)
check("closest dropper follows", ns.targets[2] and ns.targets[2].name == "Kobold Looter", ns.targets[2] and ns.targets[2].name)
check("a typed name keeps its slot", ns.targets[3] and ns.targets[3].name == "Typed Wolf")
check("the next quest NPC skips the typed slot", ns.targets[4] and ns.targets[4].name == "Crate Hauler", ns.targets[4] and ns.targets[4].name)
check("startedBy skipped once accepted", ns.SlotForName("Quest Giver") == nil)
check("dropper in another zone skipped", ns.SlotForName("Kobold Far Away") == nil)
check("quest entries carry their kind", ns.targets[1].kind == ns.KIND_KILL and ns.targets[2].kind == ns.KIND_DROP)
check("the fill is silent", #W.chat == 0, table.concat(W.chat, " / "))
check("a quest fill creates the missing FIND", W.macros["FIND"] ~= nil and W.macros["FIND"].body:match("/targetexact Kobold Miner") ~= nil,
      W.macros["FIND"] and W.macros["FIND"].body)
check("as a character macro", W.macros["FIND"] and W.macros["FIND"].perCharacter == true)
W.macroOrder = {}; W.macros = {}
zoneChange()
check("saved quest rows get FIND on a sync that changes nothing", W.macros["FIND"] ~= nil)
zoneChange()
check("a later sync never creates a second FIND", #W.macroOrder == 1, #W.macroOrder)

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

section("quest log changes and the manual refresh never move typed rows")
TargetFinderCharDB.questNpcs = true
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Mine One")
ns.targets[2] = ns.MakeEntry("Mine Two")
-- a quest NPC the log still needs but that is not nearby: the light sync keeps it, a full one swaps it out
ns.targets[3] = ns.MakeEntry("Kobold Far Away", true, ns.KIND_DROP)
local function typedHeld() return ns.targets[1].name == "Mine One" and ns.targets[2].name == "Mine Two" end
W.questCallbacks[1](100, 1, 2)
RunTimers()
check("an objective update keeps a needed quest row", ns.SlotForName("Kobold Far Away") == 3)
check("and the typed rows", typedHeld())
for _, case in ipairs({ { reason = 1, label = "accepting" }, { reason = 3, label = "turning in" }, { reason = 4, label = "abandoning" } }) do
    ns.targets[3] = ns.MakeEntry("Kobold Far Away", true, ns.KIND_DROP)
    W.questCallbacks[1](100, nil, case.reason)
    RunTimers()
    check(case.label .. " a quest swaps the quest rows for the closest NPCs", ns.SlotForName("Kobold Far Away") == nil
          and ns.SlotForName("Kobold Miner") ~= nil)
    check(case.label .. " a quest keeps rows 1 and 2", typedHeld())
end
check("quest NPCs only take free rows", ns.SlotForName("Kobold Miner") >= 3)
ns.SetQuestNpcs(false)
W.chat = {}
W.ldbObject.OnClick(nil, "RightButton")
check("the minimap right-click fills quest NPCs even with the box off", questEntries() == 3 and typedHeld(), questEntries())
check("and says so in one line", #W.chat == 1 and chatHas("Updated the quest NPCs: 3 |4row:rows; filled%.$"), table.concat(W.chat, " / "))
check("the box stays off", TargetFinderCharDB.questNpcs == false)
W.chat = {}
SlashCmdList.TARGETFINDER("refresh")
check("/tf refresh does the same", questEntries() == 3 and typedHeld() and #W.chat == 1)
for slot = 3, 8 do ns.targets[slot] = ns.MakeEntry("Typed" .. slot) end
W.chat = {}
SlashCmdList.TARGETFINDER("refresh")
check("with every row typed, nothing is replaced", questEntries() == 0 and typedHeld() and ns.SlotForName("Typed8") == 8)
check("and the line says why", chatHas("Every row holds a name you added, so no quest NPC fits%. Remove one first%.$"), W.chat[1])
_G.Questie.API.isReady = false
W.chat = {}
W.ldbObject.OnClick(nil, "RightButton")
check("while Questie loads, the line says so", chatHas("Questie is still loading%.$"), W.chat[1])
_G.Questie.API.isReady = true
ns.WipeTargets()
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
local tu = ns.FindSuggestions("tu")
check("names that start with the query come before names that only contain it",
      tu[1] and tu[1].name == "Turn In Guy" and tu[2] and tu[2].name == "Kobold Tunneler", tu[1] and tu[1].name)
check("Questie icons resolve per kind", ns.QuestieKindIcons()[ns.KIND_KILL] == "slay" and ns.QuestieKindIcons()[ns.KIND_TURNIN] == "complete")

section("a quest picked in the window creates FIND")
ns.WipeTargets()
W.macroOrder = {}; W.macros = {}
ns.TrackQuest(100)
RunTimers()
check("the quest's NPCs fill the list", ns.SlotForName("Kobold Miner") ~= nil)
check("the pick creates FIND", W.macros["FIND"] ~= nil and W.macros["FIND"].body:match("/targetexact Kobold Miner") ~= nil,
      W.macros["FIND"] and W.macros["FIND"].body)

section("panel is a native ButtonFrameTemplate window")
-- the design system's sizes the panel is built from
local TIGHT, GAP, PADDING, ROW, ICON = 4, 8, 16, 24, 16
local function onGrid(v) return v % 4 == 0 end
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
local background = panel.Background
check("the wardrobe's brown panel takes the inset's place, its corners hidden", background and background.template == "CollectionsBackgroundTemplate"
      and background.allPoints == panel.Inset and background.BGCornerTopLeft.shown == false and background.BGCornerBottomRight.shown == false
      and panel.Inset.Bg.shown == false and panel.Inset.NineSlice.shown == false)
local rowAnchor = row1.points[1]
check("rows are padded on the grid", rowAnchor.x == PADDING and rowAnchor.y == -PADDING, rowAnchor.x)
check("rows sit one gap apart", panel.rows[2].points[1].y == -(PADDING + ROW + GAP), panel.rows[2].points[1].y)
check("Add fills the fixed 48px column at the row height", row1.addBtn.width == 48 and row1.addBtn.height == ROW, row1.addBtn.width)
check("the X sits one tight step after the input", row1.removeBtn.points[1].point == "LEFT" and row1.removeBtn.points[1].rel == row1.input
      and row1.removeBtn.points[1].relPoint == "RIGHT" and row1.removeBtn.points[1].x == TIGHT)
check("each row shows its number in gold", row1.number.text == 1 and panel.rows[8].number.text == 8 and row1.number.fontObject == GameFontNormal)
check("the quest icon follows the number", row1.icon.points[1].rel == row1.number and row1.icon.points[1].x == TIGHT)
check("panel width is on the grid", panel.width and onGrid(panel.width), panel.width)
check("inputs use the 12px body font", row1.input.fontObject == GameFontHighlight, row1.input.fontObject and row1.input.fontObject.name)
check("inputs are hint boxes, InputBoxTemplate with Blizzard's grey hint", row1.input.template == "InputBoxInstructionsTemplate",
      row1.input.template)
check("the hint sits where typed text starts, in the muted font and the template's grey", row1.input.Instructions.fontObject == GameFontDisable
      and row1.input.Instructions.color and row1.input.Instructions.color[1] == 0.35)
check("an empty list says what it takes in its first row", row1.input.Instructions.text == "NPC or player name",
      row1.input.Instructions.text)
check("the other rows carry no hint", panel.rows[2].input.Instructions.text == "" and panel.rows[8].input.Instructions.text == "")
row1.input:SetText("ko")
row1.input.scripts.OnTextChanged(row1.input, true)
check("typing hides the hint, since the suggestions hook the template's handler", row1.input.Instructions.shown == false)
row1.input:SetText("")
row1.input.scripts.OnTextChanged(row1.input, true)
check("clearing the box shows it again", row1.input.Instructions.shown == true)
ns.targets[3] = ns.MakeEntry("Listed")
ns.RefreshPanel()
check("once a name is listed, the hint goes", row1.input.Instructions.text == "", row1.input.Instructions.text)
ns.WipeTargets()
ns.RefreshPanel()
check("remove is the client's close button without its hide script", row1.removeBtn.template == "UIPanelCloseButtonNoScripts",
      row1.removeBtn.template)
check("add is a Blizzard panel button", row1.addBtn.template == "UIPanelButtonTemplate", row1.addBtn.template)
row1.input.scripts.OnEnter(row1.input)
check("the name box explains itself", W.tooltip[1] == "title:Row 1"
      and W.tooltip[2] == "normal:Type an NPC or player name and press Enter. FIND matches whole names only.", table.concat(W.tooltip, " / "))
row1.addBtn.scripts.OnEnter(row1.addBtn)
check("Add explains itself", W.tooltip[1] == "title:Add" and W.tooltip[2] == "normal:Saves the typed name in this row. Enter does the same.",
      table.concat(W.tooltip, " / "))
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
row1.removeBtn.scripts.OnEnter(row1.removeBtn)
check("the X names what it takes off", W.tooltip[1] == "title:Remove" and W.tooltip[2] == "normal:Takes Mine off the FIND list.",
      table.concat(W.tooltip, " / "))
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
ns.targets[1] = ns.MakeEntry("While Closed")
ns.RefreshPanel()
check("a closed window skips the refresh", row1.input.text ~= "While Closed", row1.input.text)
ns.TogglePanel()
check("opening it shows the change", panel.shown == true and row1.input.text == "While Closed", row1.input.text)
ns.WipeTargets()

section("rows show where a quest NPC comes from")
ns.targets[1] = ns.MakeEntry("Quest Mob", true, ns.KIND_KILL)
ns.targets[2] = ns.MakeEntry("Typed Mob")
ns.RefreshPanel()
check("a quest row shows Questie's icon for its kind", row1.icon.texturePath == "slay" and row1.icon.shown == true, row1.icon.texturePath)
check("a typed row shows no icon", panel.rows[2].icon.shown == false)
check("an empty row shows no icon", panel.rows[3].icon.shown == false)

section("the Auto Apply Quest NPCs box")
local box = panel.questBox
local boxAnchor = box.points[1]
check("a native checkbox", box.template == "CheckboxWithLabelTemplate", box.template)
check("the bar grows to one gap above and below a checkbox", panel.buttonBarHeight == 4 + GAP + ROW + GAP,
      panel.buttonBarHeight)
check("it sits level with the rows, centred in the bar", boxAnchor.point == "LEFT" and boxAnchor.rel == panel and boxAnchor.relPoint == "BOTTOMLEFT"
      and boxAnchor.x == PANEL_INSET_LEFT_OFFSET + PADDING and boxAnchor.y == 4 + GAP + ROW / 2,
      tostring(boxAnchor.x) .. "," .. tostring(boxAnchor.y))
check("the window height includes the grown bar", panel.height == -PANEL_INSET_ATTIC_OFFSET + PADDING * 2
      + ns.MAX_TARGETS * (ROW + GAP) - GAP + panel.buttonBarHeight, panel.height)
check("it is labelled", box.Text.text == "Auto Apply Quest NPCs", box.Text.text)
check("it mirrors the setting", box.checked == true)
check("it is on while Questie is ready", box.enabled == true and box.Text.fontObject == GameFontHighlight)
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
check("the tooltip uses Blizzard's title helper", W.tooltip[1] == "title:Auto Apply Quest NPCs", W.tooltip[1])
_G.Questie.API.isReady = false
ns.RefreshPanel()
check("off and greyed while Questie loads", box.enabled == false and box.Text.fontObject == GameFontDisable)
box.scripts.OnEnter(box)
check("the tooltip says why", W.tooltip[#W.tooltip] == "error:Questie is still loading.", W.tooltip[#W.tooltip])
_G.Questie.API.isReady = true
W.readyCallbacks[1]()
RunTimers()
check("Questie's ready callback turns it on", box.enabled == true)

section("the Apply Raid Markers box")
local markerBox = panel.markerBox
check("a native checkbox", markerBox and markerBox.template == "CheckboxWithLabelTemplate")
check("it is labelled", markerBox.Text.text == "Apply Raid Markers", markerBox.Text.text)
local markerAnchor = markerBox.points[1]
check("it follows the quest box's label one padding step on", markerAnchor.point == "LEFT" and markerAnchor.rel == box.Text
      and markerAnchor.relPoint == "RIGHT" and markerAnchor.x == PADDING and markerAnchor.y == 0)
TargetFinderCharDB.raidMarkers = true
ns.RefreshPanel()
check("it mirrors the setting", markerBox.checked == true)
markerBox:SetChecked(false)
markerBox.scripts.OnClick(markerBox)
check("unticking saves the choice", TargetFinderCharDB.raidMarkers == false)
markerBox:SetChecked(true)
markerBox.scripts.OnClick(markerBox)
check("ticking saves it again", TargetFinderCharDB.raidMarkers == true)
markerBox.scripts.OnEnter(markerBox)
check("the tooltip says FIND marks its pick with a cross", W.tooltip[1] == "title:Apply Raid Markers"
      and W.tooltip[2] == "normal:FIND marks the NPC it targets with a cross, as RestedXP's targeting macro does.", table.concat(W.tooltip, " / "))
check("solo, the rights line is plain", W.tooltip[3] == "normal:In a group, markers need leader or assistant rights.", W.tooltip[3])
W.group = "party"
markerBox.scripts.OnEnter(markerBox)
check("without rights, it is an error line", W.tooltip[3] == "error:In a group, markers need leader or assistant rights.", W.tooltip[3])
W.group = nil
TargetFinderCharDB.raidMarkers = false

section("FIND comes from the window icon")
local dragIcon
for _, f in ipairs(W.created) do
    if f.parent == panel.PortraitContainer and f.kind == "Button" then dragIcon = f end
end
check("a button sits on the portrait", dragIcon ~= nil)
check("it drags with the left button", dragIcon and dragIcon.scripts.OnDragStart ~= nil)
W.macroOrder = {}; W.macros = {}; W.cursorMacro = nil; W.actions = {}
ns.RefreshPanel()
check("the gold help line says how to fill the list", panel.help.text == "Type names below or right-click a portrait to Track."
      and panel.help.fontObject == GameFontNormal, panel.help.text)
check("the white step line sits one band below it", panel.nextStep.fontObject == GameFontHighlight
      and panel.help.points[1].y - panel.nextStep.points[1].y == 2 * GAP)
check("both lines are cut, never wrapped, beside the portrait", panel.help.points[1].x == 58
      and panel.nextStep.points[1].x == 58 and panel.help.wordWrap == false and panel.nextStep.wordWrap == false)
check("without FIND, the step says the first name creates it", panel.nextStep.text == "The first name creates your FIND macro.", panel.nextStep.text)
TargetFinderCharDB.finderIntroduced = nil
dragIcon.scripts.OnDragStart(dragIcon)
check("the first drag creates FIND", W.macros["FIND"] ~= nil)
check("a FIND created by dragging needs no introduction", TargetFinderCharDB.finderIntroduced == true and (W.timers == nil or #W.timers == 0))
ns.RefreshPanel()
check("once FIND exists, the step says to place it", panel.nextStep.text == "Drag the icon to an action bar to place FIND.", panel.nextStep.text)
check("and puts it on the cursor", W.cursorMacro ~= nil and W.cursorMacro == GetMacroIndexByName("FIND"), W.cursorMacro)
W.actions[5] = { kind = "macro", id = GetMacroIndexByName("FIND") }
panel.scripts.OnEvent(panel, "ACTIONBAR_SLOT_CHANGED")
check("on a bar, the step says to press it", panel.nextStep.text == "Press FIND to target the first listed NPC in range.", panel.nextStep.text)
W.actions = {}
W.inCombat = true
W.cursorMacro = nil
dragIcon.scripts.OnDragStart(dragIcon)
check("no pickup in combat", W.cursorMacro == nil)
W.inCombat = false
dragIcon.scripts.OnEnter(dragIcon)
check("its tooltip names FIND", W.tooltip[1] == "title:FIND", W.tooltip[1])

section("rows reorder by drag and drop")
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("First")
ns.targets[2] = ns.MakeEntry("Second")
ns.targets[4] = ns.MakeEntry("Fourth", true, ns.KIND_KILL)
ns.RefreshPanel()
local handle3 = panel.rows[3].handle
check("each row has a drag handle over its number and icon", handle3 and handle3.width == ICON + TIGHT + ICON)
handle3.scripts.OnEnter(handle3)
check("its tooltip says how to reorder", W.tooltip[1] == "title:Row 3" and W.tooltip[3] == "instruction:Drag to move this name to another row.",
      table.concat(W.tooltip, " / "))
handle3.scripts.OnDragStart(handle3)
check("an empty row does not drag", handle3.scripts.OnUpdate == nil and panel.rows[3].alpha ~= 0.5)
local handle1 = panel.rows[1].handle
handle1.scripts.OnDragStart(handle1)
check("the dragged row fades to half, as Blizzard's lists do", panel.rows[1].alpha == 0.5)
local line
for _, f in ipairs(W.created) do if f.template == "ScrollBoxDragLineTemplate" then line = f end end
W.mouseOver = panel.rows[4]
handle1.scripts.OnUpdate(handle1)
check("Blizzard's drag line marks the drop below the row it moves down to", line and line.shown == true
      and line.points[1].point == "TOPLEFT" and line.points[1].rel == panel.rows[4] and line.points[1].y == -3)
W.mouseOver = nil
handle1.scripts.OnUpdate(handle1)
check("the gap between rows keeps the last target", line.shown == true and line.points[1].rel == panel.rows[4])
W.mouseOver = panel.rows[4]
handle1.scripts.OnDragStop(handle1)
W.mouseOver = nil
check("the drop moves the name and the rows between step up", ns.targets[1].name == "Second" and ns.targets[2] == nil
      and ns.targets[3].name == "Fourth" and ns.targets[4].name == "First", (ns.targets[1] and ns.targets[1].name or "-"))
check("the row is solid again and the line gone", panel.rows[1].alpha == 1 and line.shown == false)
check("FIND follows the new order", W.macros["FIND"].body:match("/targetexact Second\n/targetlasttarget") ~= nil, W.macros["FIND"].body)
check("a moved quest NPC stays a quest NPC", ns.targets[3].quest == true)
local handle4 = panel.rows[4].handle
handle4.scripts.OnDragStart(handle4)
W.mouseOver = panel.rows[1]
handle4.scripts.OnUpdate(handle4)
check("moving up, the line sits above the target row", line.points[1].point == "BOTTOMLEFT" and line.points[1].rel == panel.rows[1]
      and line.points[1].y == 3)
handle4.scripts.OnDragStop(handle4)
W.mouseOver = nil
check("dropping on row 1 makes it first", ns.targets[1].name == "First" and ns.targets[2].name == "Second" and ns.targets[4].name == "Fourth")
handle4 = panel.rows[2].handle
handle4.scripts.OnDragStart(handle4)
W.mouseOver = panel.rows[2]
handle4.scripts.OnUpdate(handle4)
check("over its own row, no line", line.shown == false)
handle4.scripts.OnDragStop(handle4)
W.mouseOver = nil
check("and nothing moves", ns.targets[2].name == "Second")
ns.WipeTargets()

section("suggestion popup mirrors Blizzard's AutoCompleteBox")
ns.WipeTargets()
local input = row1.input
input:SetText("kob")
input.scripts.OnTextChanged(input, true)
local pop = _G.TargetFinderSuggestions
check("one shared popup on TooltipBackdropTemplate", pop and pop.template == "TooltipBackdropTemplate", pop and pop.template)
check("popup sits on the dialog strata above the panel", pop.strata == "DIALOG", pop.strata)
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
check("minimap tooltip says what each click does and what is missing",
      W.tooltip[1] == "title:Target Finder" and W.tooltip[2] == "instruction:Click to toggle the window."
      and W.tooltip[3] == "instruction:Right-click to update the quest NPCs." and W.tooltip[4] == "error:Questie is not loaded.",
      table.concat(W.tooltip, " / "))
local entries = {}
for _, data in ipairs(AddonCompartmentFrame.registeredAddons) do
    if data.text == "Target Finder" then entries[#entries+1] = data end
end
check("the addon menu lists the addon once", #entries == 1, #entries)
local entry = entries[1]
local wasShown = panel.shown
entry.func(nil, { buttonName = "LeftButton" })
check("addon menu left-click toggles the panel", panel.shown ~= wasShown)
W.chat = {}
local shownBeforeRight = panel.shown
entry.func(nil, { buttonName = "RightButton" })
check("a right-click updates the quest NPCs instead of toggling", panel.shown == shownBeforeRight and chatHas("Questie is not loaded%.$"),
      table.concat(W.chat, " / "))

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
ns.WriteFinderMacro(true, true)
check("an automatic change in combat shows no notice", #W.errors == 0, #W.errors)
W.inCombat = false
regen.scripts.OnEvent(regen, "PLAYER_REGEN_ENABLED")
check("and lands after combat", W.macros["FIND"].body:match("/targetexact Auto") ~= nil, W.macros["FIND"].body)
W.inCombat = true
ns.RemoveFinder(2)
check("a removal in combat shows Blizzard's red error text", #W.errors == 1 and W.errors[1] == "FIND updates after combat.", W.errors[1])
W.inCombat = false
regen.scripts.OnEvent(regen, "PLAYER_REGEN_ENABLED")

section("a removal creates FIND only while names remain")
W.macroOrder = {}; W.macros = {}
ns.WipeTargets()
ns.targets[1] = ns.MakeEntry("Keep"); ns.targets[2] = ns.MakeEntry("Drop")
ns.RemoveFinder(2)
check("a removal that leaves names creates FIND", W.macros["FIND"] ~= nil and W.macros["FIND"].body:match("/targetexact Keep") ~= nil)
W.macroOrder = {}; W.macros = {}
ns.RemoveFinder(1)
check("removing the last name creates nothing", W.macros["FIND"] == nil)
ns.SetSlot(3, "Typed")
check("typing a name creates FIND", W.macros["FIND"] ~= nil and W.macros["FIND"].body:match("/targetexact Typed") ~= nil)

section("list operations")
ns.WipeTargets()
ns.AddFinder("First"); ns.AddFinder("Second"); ns.AddFinder("Third")
check("three tracked", targetCount() == 3)
check("the latest pick goes first", ns.targets[1].name == "Third" and ns.targets[2].name == "Second" and ns.targets[3].name == "First")
W.chat = {}
ns.AddFinder("Second")
check("a duplicate is refused", targetCount() == 3 and chatHas("Second is already tracked%."), table.concat(W.chat, " / "))
ns.RemoveFinder(2)
check("removed leaves a hole", ns.targets[2] == nil and targetCount() == 2)

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
check("typed names are never pushed out", ns.SlotForName("Quest1") == nil and targetCount() == 8)

section("a full list makes room for a tracked name")
panel.shown = false
ns.WipeTargets()
for i = 1, 6 do ns.targets[i] = ns.MakeEntry("Typed" .. i) end
ns.targets[7] = ns.MakeEntry("Quest7", true, ns.KIND_KILL)
ns.targets[8] = ns.MakeEntry("Typed8")
W.chat = {}
ns.AddFinder("Ninth")
check("the tracked name goes first", ns.targets[1].name == "Ninth" and targetCount() == 8)
check("the last quest entry made room", ns.SlotForName("Quest7") == nil and ns.SlotForName("Typed8") ~= nil)
check("one line names what left", #W.chat == 1 and chatHas("Tracking Ninth%. The list was full, so Quest7 was removed%.$"), table.concat(W.chat, " / "))
ns.AddFinder("Tenth")
check("with only typed names the last one leaves", ns.targets[1].name == "Tenth" and ns.SlotForName("Typed8") == nil and targetCount() == 8)

section("slash command")
check("/tf and /targetfinder are registered", SLASH_TARGETFINDER1 == "/targetfinder" and SLASH_TARGETFINDER2 == "/tf")
local before = panel.shown
SlashCmdList.TARGETFINDER("")
check("the bare slash command toggles the panel", panel.shown ~= before)
W.chat = {}
SlashCmdList.TARGETFINDER(" Minimap ")
check("/tf minimap hides the minimap button", TargetFinderDB.minimap.hide == true and W.minimapShown == false)
SlashCmdList.TARGETFINDER("minimap")
check("a second /tf minimap shows it", TargetFinderDB.minimap.hide == false and W.minimapShown == true)
check("the button itself is the answer, so no chat line", #W.chat == 0, table.concat(W.chat, " / "))
W.macroOrder = {}; W.macros = {}
ns.WipeTargets()
SlashCmdList.TARGETFINDER("add Hogger the Great")
check("/tf add tracks the typed name first", ns.targets[1] and ns.targets[1].name == "Hogger the Great")
check("/tf add creates FIND", W.macros["FIND"] ~= nil)
W.units = { target = { name = "Mangeclaw" } }
SlashCmdList.TARGETFINDER("ADD")
check("/tf add without a name takes the target", ns.targets[1] and ns.targets[1].name == "Mangeclaw")
W.units = {}
W.chat = {}
ns.WipeTargets()
SlashCmdList.TARGETFINDER("add")
check("/tf add with no name and no target explains", chatHas("Type a name or target a unit first%.$") and ns.targets[1] == nil,
      table.concat(W.chat, " / "))
local shownBefore = panel.shown
W.chat = {}
SlashCmdList.TARGETFINDER("assist Buddy")
check("an unknown word opens nothing and points to help", panel.shown == shownBefore and W.macros["ASSIST"] == nil
      and #W.chat == 1 and chatHas("Unknown command%. Type /tf help for the list%.$"), table.concat(W.chat, " / "))
W.chat = {}
SlashCmdList.TARGETFINDER("help")
check("/tf help names every command in one line", #W.chat == 1 and W.chat[1] == NORMAL_FONT_COLOR:WrapTextInColorCode("[Target Finder]")
      .. ": Type /tf to open the window, /tf add with a name or your target to track it, /tf refresh to update the quest NPCs, "
      .. "/tf intro to see the welcome line and the tip again, /tf minimap to show or hide the minimap button, or /tf help for this list.",
      W.chat[1])
W.chat = {}
SlashCmdList.TARGETFINDER("?")
check("/tf ? is help too", #W.chat == 1 and chatHas("/tf help for this list"))
TargetFinderDB.tipSeen = true
W.chat = {}
SlashCmdList.TARGETFINDER("intro")
check("/tf intro prints the welcome line again", #W.chat == 1 and W.chat[1] == WELCOME, W.chat[1])
check("and brings the tip back", TargetFinderDB.tipSeen == nil)
if panel.shown then ns.TogglePanel() end
EventRegistry.callbacks.SetItemRef("addon:OtherAddon")
check("another addon's link does nothing", panel.shown == false)
W.secretsOn = true
EventRegistry.callbacks.SetItemRef({ __secret = true })
W.secretsOn = false
check("a secret link does nothing", panel.shown == false)
EventRegistry.callbacks.SetItemRef("addon:TargetFinder")
check("the welcome link opens the window", panel.shown == true)
EventRegistry.callbacks.SetItemRef("addon:TargetFinder")
check("and never closes it", panel.shown == true)

section("the first FIND opens the macro book with its icon glowing")
W.macroOrder = {}; W.macros = {}; W.actions = {}; W.timers = {}
MacroFrame.shown, MacroFrame.tab, MacroFrame.selected = false, nil, nil
TargetFinderCharDB.finderIntroduced = nil
TargetFinderDB.tipSeen = nil
local tip
for _, f in ipairs(W.created) do
    if f.template == "HelpTipTemplate" then tip = f end
end
if tip then tip:Hide() end
ns.WipeTargets()
ns.SyncQuestEntries({ { name = "Quest Wolf", kind = ns.KIND_KILL } })
check("a quest fill creates FIND", W.macros["FIND"] ~= nil)
check("the introduction waits a frame", MacroFrame.shown == false)
W.chat = {}
RunTimers()
check("the macro book opens on FIND", MacroFrame and MacroFrame.shown == true and MacroFrame.tab == 2
      and MacroFrame.selected == GetMacroIndexByName("FIND") - 120)
local glow
for _, f in ipairs(W.created) do
    if f.template == "ActionButtonSpellAlertTemplate" then glow = f end
end
check("Blizzard's proc glow sits on the large macro icon", glow and glow.parent == MacroFrame.SelectedMacroButton)
check("it is scaled like an action button's", glow and glow.width == 22 * 1.4 and glow.points[1].point == "CENTER")
check("it shows and plays", glow and glow.shown == true and glow.ProcStartAnim.playing == true)
check("the introduction adds no chat line", #W.chat == 0, table.concat(W.chat, " / "))
check("the character is marked introduced", TargetFinderCharDB.finderIntroduced == true)
for _, f in ipairs(W.created) do
    if f.template == "HelpTipTemplate" then tip = f end
end
check("Blizzard's help tip points at the large icon", tip and tip.shown == true and tip.target == MacroFrame.SelectedMacroButton
      and tip.parent == MacroFrame.SelectedMacroButton)
check("it says what to do with FIND and what it gives", tip.info.text == "Drag FIND to an action bar to target the names on your Target Finder list."
      and tip.info.buttonStyle == HelpTip.ButtonStyle.Close and tip.info.targetPoint == HelpTip.Point.RightEdgeCenter)
table.insert(W.macroOrder, 1, "Other")
W.macros["Other"] = { perCharacter = true }
MacroFrame:SelectMacro(1)
check("selecting another macro hides it", glow.shown == false)
check("and the tip, without marking it seen", tip.shown == false and TargetFinderDB.tipSeen == nil)
MacroFrame:SelectMacro(GetMacroIndexByName("FIND") - 120)
check("selecting FIND again brings it back", glow.shown == true and glow.ProcStartAnim.playing == true)
W.actions[3] = { kind = "macro", id = GetMacroIndexByName("FIND") }
glow.scripts.OnEvent(glow, "ACTIONBAR_SLOT_CHANGED")
check("FIND on a bar ends it", glow.shown == false and glow.events["ACTIONBAR_SLOT_CHANGED"] == nil)
check("placing FIND counts the tip as seen", tip.shown == false and TargetFinderDB.tipSeen == true)
MacroFrame:SelectMacro(GetMacroIndexByName("FIND") - 120)
check("and it stays off", glow.shown == false)
W.actions = {}
ns.ShowFinder()
check("Track or /tf add brings it back while FIND is on no bar", glow.shown == true)
check("a seen tip stays away", tip.shown == false)
TargetFinderDB.tipSeen = nil
HideMacroFrame()
ns.ShowFinder()
check("an unseen tip comes back with the glow", tip.shown == true)
tip:Acknowledge()
check("its close button marks it seen", TargetFinderDB.tipSeen == true and tip.shown == false)
SlashCmdList.TARGETFINDER("intro")
check("/tf intro brings it back at once while the book shows FIND", tip.shown == true and TargetFinderDB.tipSeen == nil
      and tip.info and tip.info.text ~= nil)
HideMacroFrame()
check("closing the macro book ends it", glow.shown == false and glow.events["ACTIONBAR_SLOT_CHANGED"] == nil)
check("after intro, hiding with the macro book does not mark the tip seen", tip.shown == false and TargetFinderDB.tipSeen == nil,
      tostring(TargetFinderDB.tipSeen))
ns.ShowFinder()
check("so it shows again at the next chance", tip.shown == true)
W.actions[3] = { kind = "macro", id = GetMacroIndexByName("FIND") }
glow.scripts.OnEvent(glow, "ACTIONBAR_SLOT_CHANGED")
check("placing FIND while it shows retires it through its own close path", tip.shown == false and TargetFinderDB.tipSeen == true)
W.actions = {}
HideMacroFrame()
W.macroOrder = {}; W.macros = {}
MacroFrame.shown = false
ns.SyncQuestEntries({ { name = "Quest Boar", kind = ns.KIND_KILL } })
RunTimers()
check("a character is introduced once", MacroFrame.shown == false)

section("markers never come from tracking or the macro")
check("no list change called SetRaidTarget", W.markCalls == 0, W.markCalls)

section("every chat line goes through ns.Print")
local prefix = NORMAL_FONT_COLOR:WrapTextInColorCode("[Target Finder]") .. ": "
local offPrefix = {}
for _, line in ipairs(W.allChat) do
    if line:sub(1, #prefix) ~= prefix then offPrefix[#offPrefix+1] = line end
end
check("the suite printed lines", #W.allChat > 10, #W.allChat)
check("each one starts with the gold [Target Finder] and an uncoloured colon", #offPrefix == 0, table.concat(offPrefix, " / "))

io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
