# TargetFinder — Memory

Updated 2026-10-01 after adopting the shared design system LibNativeUI-1.0 (still 4.0.0); before that, 2026-09-30 after the Forever-only rework (4.0.0). The owner's decision is WoW Forever 1.60.x only: `main` holds only the Forever version, and `1.15.x-backup` keeps the dual-client 3.2.0 with all Classic code. Quest data still comes only from Questie. This supersedes the 2026-09-25 decision that every addon supports both clients.

Verified against:

- Gethe `forever` @ `966519cf` (1.60.1.70124), only files the Forever client loads
- Ketho `forever` @ `4149af64` (1.60.1.70009)
- the installed client 1.60.1.70009
- the installed Questie 12.0.3 (`Questie_Camelot.toc`) and QuestieDB 1.0.4

Nothing has run in a client. On 2026-10-01, `cd Tests && lua Tests.lua` passed 174 of 174 (Lua 5.5), which proves logic and wiring, not client behaviour. `luac -p` passes on every Lua file.

## Current state

Keeps up to 8 NPC names and writes one **FIND** macro, a reversed `/target` chain in which slot 1 wins. Each slot's raid marker goes to exactly one unit: the current target if it matches, otherwise one visible nameplate.

It also has:

- A panel with Questie autocomplete and "Add Nearby Quest Units" quick add.
- Unit-menu entries: Assist, Track First, Track, Untrack and Clear.
- One launcher: the LibDBIcon minimap button, whose Addon Compartment entry LibDBIcon registers itself.
- Macro writes that wait until combat ends.

| Item | State |
|---|---|
| Version | 4.0.0. Toc: `## Interface: 16001`, `## Category: Combat`, `## IconTexture: 132212`, `## Author: miyanko`, `OptionalDeps: Questie`. No `## AddonCompartmentFunc*` fields since the design-system commit. `.pkgmeta` ignores `Tests` and `MEMORY.md`, no externals |
| Git | `main` has three local commits on top of `7ad99db`, not pushed: `c3a1ac5` (split and cleanup), `2dc8878` (fixes), then the UI commit. `1.15.x-backup` = `origin/1.15.x-backup` = `7ad99db` (dual-client 3.2.0), created by the lead. `core.hooksPath` is unset |
| Layout | `TargetFinder.lua` (bootstrap), `Core/` (Core, Secrets, Store, Markers, Macro, Targets, Quest, UnitMenu), `UI/` (Suggestions, Panel, MinimapButton), `Libs/` (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0, LibNativeUI-1.0, tracked, unedited), `Tests/` |
| Lua lines | Addon code (no libs, no tests) 1,754 before, 1,767 after. Tests 771 before, 915 after. About 70 Classic and dead lines went; the fixes and the UI spec added about 80 |

Quest data comes only from Questie, through `Core/Quest.lua`:

- Readiness is Questie's public contract: `Questie.API.isReady == true` (created at `Modules/VersionCheck.lua:47`, set as the last init step at `Modules/QuestieInit.lua:342`). Before that nothing is read, and the excuse is "Questie is still loading.".
- `ns.WatchQuestie()` runs at `PLAYER_LOGIN` and calls `Questie.API.RegisterOnReady` (`Public/RegisterOnReady.lua:10-21`, runs at once when already ready). The callback refreshes the panel, so Add Nearby switches on by itself, and prebuilds the NPC name index on the next frame.
- `Questie` can be an empty table when a second Questie install is present (`VersionCheck.lua:30-42`). Then `Questie.API` is missing and the addon reports "Questie is not loaded.".
- The private database is still type-checked (`QueryNPCSingle`, `QueryQuestSingle`, `QueryItemSingle`, `NPCPointers`). A mismatch after ready reports "This Questie version is not supported.".
- Objective progress is `quest.Objectives[i].Completed` / `quest.isComplete` from `QuestiePlayer.currentQuestlog`. There's no `C_QuestLog`.
- Internals verified against 12.0.3: `QuestieDB.lua:443-445` (queries), `:468,489` (`NPCPointers`), `:1604` (`IsComplete` returns -1/0/1), `:1658` (`GetQuest`), `:1767-1834` (`ObjectiveData`); `QuestiePlayer.lua:15`, `zoneDB.lua:152-170`, `Questie.lua:277-309` (`usedIcons`, `ICON_TYPE_*`). Field names match `src/meta/*Meta.lua`. `currentQuestlog` can still hold bare ids, so the `GetQuest` fallback stays.
- Each public entry runs in `pcall`, with one chat line on the first failure. `ZoneDB:GetAreaIdByUiMapId` raises on unmapped maps (`zoneDB.lua:170`), so it's wrapped in `pcall`.
- The NPC name index pass follows QuestieDB's rule to take that stall where it is invisible (`QuestieDB/src/read/shared.lua:473-476`). The first search still builds it if the prebuild has not run.

Secret values, in `Core/Secrets.lua` and `Core/Markers.lua`:

- `ns.CanAccess` answers nil without calling `canaccessvalue` (its argument is `Nilable = false`), tested with `type()`, the way Blizzard's `Dump.lua` tests values that may be secret. Other values go through `pcall(canaccessvalue, v)`; a raise reads as "not accessible".
- `ns.IdentitySecret` (`C_Secrets.ShouldUnitIdentityBeSecret`) and `ns.ComparisonSecret` (`C_Secrets.ShouldUnitComparisonBeSecret`, `SecretPredicateAPIDocumentation.lua:272`) are asked before `UnitInRaid` / `UnitIsUnit` in the Assist check.
- When `GetRaidTargetIndex` is hidden, only the target is marked. The nameplate scan returns no unit, because the mob already carrying the marker can't be found. The 0.15 s throttle still limits target re-sends.
- `SetRaidTarget` sets, it doesn't toggle. Blizzard toggles by hand (`Mainline/TargetFrame.lua:694-699`, `SecureTemplates.lua:596-601`), so re-sending the same index is harmless.

Native UI, built from the shared design system LibNativeUI-1.0 (2026-10-01):

- The library sits at `Libs/LibNativeUI-1.0/` (code and README, the spec), loaded right after LibDBIcon. It is an identical copy of the reference in `ChatScan`, so it is never edited here.
- Components adopted: `UI.CreateWindow`, `UI.AddBarButton`, `UI.CreateToggle`, `UI.RegisterSlash`, `UI.CreateLauncher`, `UI.Print` (behind `ns.Announce`), `UI.CreateText`, `UI.CreateButton`, `UI.CreateEditBox`, `UI.CreateRemoveButton` and `UI.AttachTooltip`. The slot rows and the suggestion popup stay addon composites built from those parts and the tokens.
- The panel `TargetFinderFrame` is `UI.CreateWindow`, built on first toggle by `UI.CreateToggle`. `ns.TogglePanel` serves the minimap button, the addon menu and `/tf`.
  - The window gives the portrait (`132212`), the title "Target Finder", strata HIGH, toplevel, clamped, movable, Escape via `UISpecialFrames` (not `UIPanelWindows`), and the combat-safe X through `onCloseCallback`. There's no position persistence, as before.
  - Size: 400 wide (was 360), so the 12 px help wraps to two lines in the 36 px attic. Height is `-PANEL_INSET_ATTIC_OFFSET` + 16 + 8 × 24 + 16 + `PANEL_INSET_BOTTOM_BUTTON_OFFSET` = 310 (was 290).
  - The attic help is `UI.Font.body` (12 px, was GameFontHighlightSmall 10 px). It starts at `UI.Snap(57)` = 64, the first grid line past the portrait's right edge (62 px at x=-5). It ends `UI.Space.padding` inside the inset's right edge, level with the rows.
  - Rows: `UI.Space.padding` (16) inside the Inset on every side (was 8/6), `UI.Size.row` (24) high. Index 16 wide in `UI.Font.body`, then a 16 px marker one gap (8, was 4) to the right. The input starts one gap plus `UI.Native.inputArt` past the marker and ends one gap before Add/remove (was 6). With no trailing button it runs to the row's edge.
  - Inputs are `UI.CreateEditBox`, which sets `UI.Font.body` (12 px Friz Quadrata, was InputBoxTemplate's ChatFontNormal, 14 px Arial Narrow). Add is `UI.CreateButton` 48 × 22, and remove is `UI.CreateRemoveButton` 24 × 24.
  - Bottom bar: `UI.AddBarButton` puts Add Nearby Quest Units (176 = 22 × 8) bottom-right, then Clear Unit List (128, the default) to its left; `MagicButton_OnLoad` sets Blizzard's own bar spacing. The Add Nearby tooltip goes through `UI.AttachTooltip`, with motion scripts kept while disabled.
- Suggestions are built like Blizzard's name autocomplete (`Blizzard_AutoComplete/AutoComplete.xml`): `TooltipBackdropTemplate`, `AutoCompleteButtonTemplate` rows and the `PRESS_TAB` hint. Blizzard's shared `AutoCompleteBox` isn't used, because writing to it would taint chat.
  - Its metrics stay Blizzard's, named as native geometry: row 14, text inset 15, first row 10, hint bottom 10, chrome 35 and edit-box overlap 3 (`AUTOCOMPLETE_DEFAULT_Y_OFFSET`).
  - The role icon is `UI.Size.icon` (16, was 12), so it overhangs the 14 px row by 1 px each side. Its gap to the name is `UI.Space.gap` (8, was 2), so names start at 39 (was 29).
  - The hint is `UI.Font.muted` (12 px, was Blizzard's GameFontDisableSmall, 10 px), tinted `LIGHTGRAY_FONT_COLOR`. Add All is `UI.Font.body`. The quest tag is `UI.Color.muted` (= `GRAY_FONT_COLOR`).
  - Strata `UI.Strata.dialog` (DIALOG, was FULLSCREEN_DIALOG). That is still above the HIGH panel; Blizzard's own box uses TOOLTIP.
- Launcher: `UI.CreateLauncher`, title "Target Finder" (the LDB name is unchanged), icon 132212, db `TargetFinderDB.minimap`, so the saved position carries over. The launcher adds the tooltip title. `UI/MinimapButton.lua` adds the instruction lines, plus a disabled and an error line while Questie isn't ready.
  - The toc `## AddonCompartmentFunc*` lines and the `TargetFinder_OnClick/OnEnter/OnLeave` globals are gone. LibDBIcon's `AddButtonToCompartment` registers the addon-menu entry through `AddonCompartmentFrame:RegisterAddon` (`Blizzard_Minimap/Mainline/AddonCompartment.lua:136`). That entry reuses the data object's `OnClick` and `OnTooltipShow`, and it sets `TargetFinderDB.minimap.showInCompartment`.
- Chat goes through `UI.Print` (yellow `UI.Color.prefix`). The combat notice stays `RED_FONT_COLOR`. No hardcoded colour codes or font files remain.
- Tests: the harness loads the real `LibNativeUI-1.0.lua` from the toc and stubs the rest (LibStub with `NewLibrary`, LibDBIcon's compartment call, `AddonCompartmentFrame`, `GameTooltip_Hide`, the attic and bar helpers, the role font objects and colours). New checks cover the toc order, absent compartment fields and globals, one addon-menu entry and its clicks, grid padding and width, the input font and the popup strata.

Verified API facts:

- Macros: caps are 120/30 (`Constants.MacroConsts`, `LuaEnum.lua:9706-9708`), the macro limit is 255 characters, and `CreateMacro`/`EditMacro`/`GetMacroIndexByName`/`GetMacroInfo` exist. `ShowMacroFrame` loads `Blizzard_MacroUI` synchronously and skips the show if the load fails (`Blizzard_MacroUI_Bootstrap.lua:7-11`). `MacroFrame.SelectedMacroButton` is a parentKey (`Blizzard_MacroUI.xml:87`).
- Menus: `Menu.ModifyMenu` with `"MENU_UNIT_"..which` tags. All 10 tags used are registered on Camelot.
- Markers: `GetRaidTargetIndex` is `SecretReturns = true`, and `SetRaidTarget` is `HasRestrictions = true`. `SetRaidTargetIconTexture` only sets the sprite-sheet cell (`Mainline/TargetFrame.lua:690`).
- `UnitIsUnit` is `SecretWhenUnitComparisonRestricted`; `UnitInRaid` is `SecretWhenUnitIdentityRestricted`.
- `Enum.AddOnRestrictionType` includes Combat, Encounter, ChallengeMode, PvPMatch, Map and Chat.
- Action slots 1-72 and 145-180 exist (MultiBar5-7 in `Blizzard_ActionBar/Shared/MultiActionBars.xml`).

## Audit 2026-09-30 (Forever-only) and what was done

| ID | Severity | Finding | Status |
|---|---|---|---|
| TF-1 | Medium | No backup branch | Done by the lead: `1.15.x-backup` at `7ad99db` (dual-client 3.2.0), local and GitHub. The audit had suggested `c95eb6a` |
| TF-2 | Medium | `## Interface: 11509, 16001`, Notes name Classic Era | Done (`c3a1ac5`): `16001`, one-sentence Forever Notes |
| TF-3 | Medium | Era fallbacks in `Client.lua` | Done (`c3a1ac5`): `canaccessvalue`, `C_Secrets` and `Constants.MacroConsts.MAX_ACCOUNT_MACROS` called directly |
| TF-4 | Medium | `Menu.ModifyMenu` guard | Done (`c3a1ac5`) |
| TF-5 | Medium | Readiness guessed from internals | Done (`2dc8878`): `Questie.API.isReady`, `RegisterOnReady` at login refreshes the panel |
| TF-6 | Medium | Marker jumps when the index is secret | Done (`2dc8878`): target only, nameplate scan skipped, throttle kept, tests added. When the index is secret is still UNVERIFIED |
| TF-7 | Low | `UnitIsUnit` ran behind the identity guard only | Done (`2dc8878`): `ns.ComparisonSecret` first |
| TF-8 | Low | `canaccessvalue(nil)` | Done (`2dc8878`): nil short-circuit; the stub now raises on nil and a test counts calls |
| TF-9 | Low | Name index built on the first keystroke | Done (`2dc8878`): prebuilt one frame after Questie is ready |
| TF-10 | Low | `where.parentId` compares child-map coordinates with parent-map spawns | Open, needs in-game ZoneDB data |
| TF-11 | Low | Macro book opened after every edit while FIND is unbound, `tfGlow` on a Blizzard button | Open, needs `taintLog` in game |
| TF-12 | Medium | `KIND_ASSOC` never produced | Done (`c3a1ac5`). `KIND_GIVER` stays 4, because saved entries store the kind |
| TF-13 | Low | Dead guards, `minimap.angle` migration, `SetSlot` copy of the report | Done (`c3a1ac5`, plus the `SelectedMacroButton` and panel guards in the UI commit) |
| TF-14 | Medium | `Client.lua` grab-bag | Done (`c3a1ac5`): guards in `Core/Secrets.lua`, caps and slot count in `Macro.lua`, `MAX_NAMEPLATES` in `Core.lua`, marker texture helper local in `UI/Panel.lua` |
| TF-15 | Low | Both-client comments | Done |
| TF-16 | Medium | Era-mode tests | Done: toc, readiness, nil stub, secret marker, comparison and UI tests; 136 became 165 |
| TF-17 | Low | Dual-client README | Done |
| TF-18 | Low | No `## Category` | Done: `Combat`, version 4.0.0 |
| TF-19 | Low | `core.hooksPath` pointed at `_classic_era_` | Done: unset in the local config |
| TF-20 | Low | Possible duplicate FIND if account macros load after `PLAYER_LOGIN` | Open, needs a relog check |

Nothing to do:

- The macro API and caps. The read-back after write covers the cap-reached failure.
- Combat lockdown: queued writes, the in-combat close, and deferred menu actions.
- The unit menu integration and tags.
- Templates and strings.
- First load with empty SV: the beta WTF has none, and the boot test covers it.
- `.pkgmeta`.

Unverified assumptions kept in code:

- `type()` on a secret is safe. Blizzard's `Dump.lua` does it; `==` on a possibly secret value is never used.
- `C_Secrets.ShouldUnitComparisonBeSecret` accepts a grouped character name as its `UnitToken`, like the identity check already did (menus with no unit, such as friends and chat).
- `LIGHTGRAY_FONT_COLOR` is close to AutoComplete's literal `|cffbbbbbb`. Only its existence is verified (14 loaded Blizzard files use it).
- Icon resolved (community listfile, 2026-09-30): 132177 was `ability_hunter_mastermarksman`, not Sniper Shot. The toc now uses 132212 = `interface/icons/ability_hunter_snipershot.blp`, so the portrait, the minimap button and the FIND macro show the same art.
- The frame is now named `TargetFinderFrame` (was `TargetFinderPanel`). A position the client saved under the old name is lost once.

## Blockers, issues, challenges

1. The biggest Forever risk is `canaccessvalue` from addon code. If it raises even on plain values, every name reads as hidden, and marking and menus silently stop.
2. `SetRaidTarget` is `HasRestrictions = true`. Whether it works solo and in a party on 1.60, and whether the marker index turns secret in combat (TF-6), is unverified.
3. Forever spawn coordinates match player map space only according to QuestieDB's own audit.
4. Which `/assist` form reaches a surnamed Forever player, `First` or `First Surname`, is unverified.

## Owner questions


## Next steps

1. Owner review, then push `main`.
2. Run `/console scriptErrors 1` first in game, then the checks below. Settle TF-10, TF-11 and TF-20 from them.

Forever checks:

- [ ] The panel shows the portrait icon, the 12 px help text beside it on two lines inside the attic, and Add Nearby Quest Units bottom right with Clear Unit List to its left, both in the standard bar spacing.
- [ ] Rows look even at 12 px: 16 px padding in the inset, 8 px between index, marker, input and Add/remove, and the input's left cap clear of the marker.
- [ ] The addon menu under the minimap lists Target Finder exactly once (no toc entry any more).
- [ ] Right after login the Add Nearby button is off with "Questie is still loading."; it turns on by itself once Questie finishes, without reopening the panel.
- [ ] The first keystroke after login causes no hitch (the name index was prebuilt).
- [ ] Type a nearby NPC in slot 1 and press Enter: a Skull shows in the row and the macro book opens with FIND pulsing. `/m` shows `/target Name`.
- [ ] Put FIND on a bar near the NPC: it gets targeted and Skull-marked, solo and in a party. This settles issue 2.
- [ ] With 2–3 same-named mobs on screen, add the name: exactly one gets the marker and chat says "— 1 marked". Repeat in combat (TF-6).
- [ ] `/dump issecretvalue(GetRaidTargetIndex("target"))` on a marked mob, in the open world and in combat. This settles when TF-6's path runs.
- [ ] Target a wolf and type "Kobold": the wolf stays unmarked.
- [ ] Track "Chillgular" near "Auctioneer Chillgular": FIND never targets the auctioneer.
- [ ] Add a slot in combat: one red notice, and the macro updates after combat. The panel's X closes in combat.
- [ ] Type "Kob": the popup looks like the whisper autocomplete. Up/Down, Enter and Tab work. The 12 px "Press Tab" hint doesn't touch the Add All row, and the 16 px role icons don't clash between rows.
- [ ] Finish a kill objective: that mob drops out of suggestions and Add Nearby without a `/reload`.
- [ ] Click Add Nearby inside a dungeon: no Lua error.
- [ ] The addon-menu entry has the same tooltip as the minimap button: left-click toggles, shift-left-click clears, right-click adds nearby. The minimap button kept its saved position.
- [ ] Track a mob from its unit menu outside restricted content: it gets marked. This settles issue 1.
- [ ] In a dungeon, run `/run print(pcall(canaccessvalue, UnitName("target")))` and `/dump C_Secrets.ShouldUnitComparisonBeSecret("party1", "player")`: no Lua error, and Assist is hidden while either is restricted.
- [ ] Distances look right in a zone whose map differs on Forever, including a sub-zone (TF-10).
- [ ] After `/reload` and a full relog, there is exactly one FIND macro (TF-20).
- [ ] With `/console taintLog 1`, a few list edits with FIND unbound show no taint (TF-11).

## Launchers (owner decision 2026-09-30)

- `/tf` and `/targetfinder` toggle the panel through `ns.TogglePanel` (`UI/Panel.lua`), the same toggle the minimap button and the Addon Compartment use, registered with `UI.RegisterSlash`. No Blizzard or installed addon uses either command. The test harness stubs `SlashCmdList` and checks the registration.

## LibNativeUI-1.0 version

- The embedded copy is MINOR 2, byte-identical in ChatScan, QuestieGuide and TargetFinder; the reference copy is `ChatScan/Libs/LibNativeUI-1.0/`. MINOR 2 moves `UI.CreateSearchBox`'s typed text and hint from the template's 10px fonts to the 12px body and muted roles, keeping the template's hint grey.

## Minimap icon (owner decision 2026-10-01)

- Keep the draggable LibDBIcon minimap icon. It is built by LibNativeUI's `UI.CreateLauncher`, which also adds the entry in Blizzard's addon menu (Addon Compartment) through LibDBIcon, so both share one click handler and tooltip. LibDBIcon, LibDataBroker and CallbackHandler stay embedded.
