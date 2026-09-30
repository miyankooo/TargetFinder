# TargetFinder — Memory

Updated 2026-09-30 after the Forever-only rework (4.0.0). The owner's decision is WoW Forever 1.60.x only: `main` holds only the Forever version, and `1.15.x-backup` keeps the dual-client 3.2.0 with all Classic code. Quest data still comes only from Questie. This supersedes the 2026-09-25 decision that every addon supports both clients.

Verified against:

- Gethe `forever` @ `966519cf` (1.60.1.70124), only files the Forever client loads
- Ketho `forever` @ `4149af64` (1.60.1.70009)
- the installed client 1.60.1.70009
- the installed Questie 12.0.3 (`Questie_Camelot.toc`) and QuestieDB 1.0.4

Nothing has run in a client. On 2026-09-30, `cd Tests && lua Tests.lua` passed 165 of 165 (Lua 5.5), which proves logic and wiring, not client behaviour. `luac -p` passes on every Lua file.

## Current state

Keeps up to 8 NPC names and writes one **FIND** macro, a reversed `/target` chain in which slot 1 wins. Each slot's raid marker goes to exactly one unit: the current target if it matches, otherwise one visible nameplate.

It also has:

- A panel with Questie autocomplete and "Add Nearby Quest Units" quick add.
- Unit-menu entries: Assist, Track First, Track, Untrack and Clear.
- A minimap button (LibDBIcon) plus the Addon Compartment.
- Macro writes that wait until combat ends.

| Item | State |
|---|---|
| Version | 4.0.0. Toc: `## Interface: 16001`, `## Category: Combat`, `## IconTexture: 132212`, `## Author: miyanko`, `OptionalDeps: Questie`, Addon Compartment fields. `.pkgmeta` ignores `Tests` and `MEMORY.md`, no externals |
| Git | `main` has three local commits on top of `7ad99db`, not pushed: `c3a1ac5` (split and cleanup), `2dc8878` (fixes), then the UI commit. `1.15.x-backup` = `origin/1.15.x-backup` = `7ad99db` (dual-client 3.2.0), created by the lead. `core.hooksPath` is unset |
| Layout | `TargetFinder.lua` (bootstrap), `Core/` (Core, Secrets, Store, Markers, Macro, Targets, Quest, UnitMenu), `UI/` (Suggestions, Panel, MinimapButton), `Libs/` (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0, tracked, unedited), `Tests/` |
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

Native UI (shared spec):

- The panel `TargetFinderFrame` is a `ButtonFrameTemplate` window, built lazily by one builder, toggled by `ns.TogglePanel()` from the minimap button and the compartment.
  - Portrait shown with `SetPortraitToAsset(132212)`, title "Target Finder", strata HIGH, toplevel, clamped, movable, Escape via `UISpecialFrames`, not in `UIPanelWindows`.
  - The attic holds the help text at x=60 (clear of the 62 px portrait), centred on the band between `PANEL_INSET_TOP_OFFSET` and `PANEL_INSET_ATTIC_OFFSET`. Rows live in `frame.Inset`. Height comes from `PANEL_INSET_ATTIC_OFFSET` and `PANEL_INSET_BOTTOM_BUTTON_OFFSET`.
  - Bottom bar: Add Nearby Quest Units (primary) at `BOTTOMRIGHT`, Clear Unit List `RIGHT` to its `LEFT`, both `MagicButtonTemplate` anchored with zero offsets, then `MagicButton_OnLoad` (`Mainline/SharedUIPanelTemplates.lua:12-46`).
  - The X closes through `onCloseCallback` (`SharedUIPanelTemplates.lua:150-162`), which hides the panel itself, so it works in combat.
  - Row Add is `UIPanelButtonTemplate`, remove is `UIPanelCloseButtonNoScripts`, inputs `InputBoxTemplate`.
- Suggestions are built like Blizzard's name autocomplete (`Blizzard_AutoComplete/AutoComplete.xml`): `TooltipBackdropTemplate`, `AutoCompleteButtonTemplate` rows and the `PRESS_TAB` hint. Blizzard's shared `AutoCompleteBox` isn't used, because writing to it would taint chat. The quest tag uses `GRAY_FONT_COLOR`, the hint `LIGHTGRAY_FONT_COLOR`.
- Minimap button: LibDataBroker `launcher` "Target Finder", icon 132212, db at `TargetFinderDB.minimap`. Tooltip: `GameTooltip_SetTitle` plus instruction lines, a disabled line and an error line while Questie isn't ready.
- Chat prefix `YELLOW_FONT_COLOR`, combat notice `RED_FONT_COLOR`. No hardcoded colour codes or font files remain.

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
- The Addon Compartment callbacks.
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

- [ ] The panel shows the portrait icon, the help text beside it, and Add Nearby Quest Units bottom right with Clear Unit List to its left, both in the standard bar spacing.
- [ ] Right after login the Add Nearby button is off with "Questie is still loading."; it turns on by itself once Questie finishes, without reopening the panel.
- [ ] The first keystroke after login causes no hitch (the name index was prebuilt).
- [ ] Type a nearby NPC in slot 1 and press Enter: a Skull shows in the row and the macro book opens with FIND pulsing. `/m` shows `/target Name`.
- [ ] Put FIND on a bar near the NPC: it gets targeted and Skull-marked, solo and in a party. This settles issue 2.
- [ ] With 2–3 same-named mobs on screen, add the name: exactly one gets the marker and chat says "— 1 marked". Repeat in combat (TF-6).
- [ ] `/dump issecretvalue(GetRaidTargetIndex("target"))` on a marked mob, in the open world and in combat. This settles when TF-6's path runs.
- [ ] Target a wolf and type "Kobold": the wolf stays unmarked.
- [ ] Track "Chillgular" near "Auctioneer Chillgular": FIND never targets the auctioneer.
- [ ] Add a slot in combat: one red notice, and the macro updates after combat. The panel's X closes in combat.
- [ ] Type "Kob": the popup looks like the whisper autocomplete. Up/Down, Enter and Tab work.
- [ ] Finish a kill objective: that mob drops out of suggestions and Add Nearby without a `/reload`.
- [ ] Click Add Nearby inside a dungeon: no Lua error.
- [ ] The compartment entry has the same tooltip as the minimap button: left-click toggles, right-click adds nearby.
- [ ] Track a mob from its unit menu outside restricted content: it gets marked. This settles issue 1.
- [ ] In a dungeon, run `/run print(pcall(canaccessvalue, UnitName("target")))` and `/dump C_Secrets.ShouldUnitComparisonBeSecret("party1", "player")`: no Lua error, and Assist is hidden while either is restricted.
- [ ] Distances look right in a zone whose map differs on Forever, including a sub-zone (TF-10).
- [ ] After `/reload` and a full relog, there is exactly one FIND macro (TF-20).
- [ ] With `/console taintLog 1`, a few list edits with FIND unbound show no taint (TF-11).

## Launchers (owner decision 2026-09-30)

- `/tf` and `/targetfinder` toggle the panel through `ns.TogglePanel` (`UI/Panel.lua`), the same toggle the minimap button and the Addon Compartment use. No Blizzard or installed addon uses either command. The test harness stubs `SlashCmdList` and checks the registration (167/167).
