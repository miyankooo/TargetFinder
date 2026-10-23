# TargetFinder

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no compat layer.
- `main` holds the Forever version. `1.15.x-backup` keeps the dual-client 3.2.0 and stays untouched.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`.

## Rules

- Read nothing from Questie before `Questie.API.isReady == true`, and never guess readiness from internals. `ns.WatchQuestie()` registers `Questie.API.RegisterOnReady` at `PLAYER_LOGIN`.
- Test `Questie.API`, not `Questie`. A second Questie install leaves `Questie` an empty table.
- Every public entry of `Core/Quest.lua` runs in `pcall`. Private QuestieDB calls are type-checked after ready. `ZoneDB:GetAreaIdByUiMapId` raises on unmapped maps, so it stays wrapped.
- `QuestiePlayer.currentQuestlog` can still hold bare quest ids, so keep the `QuestieDB.GetQuest` fallback.
- Prebuild the NPC name index one frame after Questie is ready, so the first keystroke never stalls.
- `ns.CanAccess` answers nil itself, because `canaccessvalue` takes no nil. Other values go through `pcall(canaccessvalue, v)`, and a raise means not accessible.
- Never compare a possibly secret value with `==`.
- FIND follows RestedXP's targeting macro (`RXPGuides/Targeting.lua`, `UpdateMacro`): one `/targetexact` per slot, slot 1 last so it wins, then `/targetlasttarget [dead]`. Names match exactly everywhere.
- Never call `SetRaidTarget`. Forever restricts it for addons (`HasRestrictions`), so RestedXP skips it there too. FIND marks through its own `/tm [harm,nodead] !8` line, written only while the player may mark: solo, party leader, raid leader or assistant.
- Saved entries store only `name`, `quest` and `kind`. Only `quest` entries change by themselves (the Quest NPCs sync and quest picks). Names the player adds, typed, picked or tracked, are never touched.
- One quest NPC rule everywhere: open objectives, or the turn-in NPC once Questie counts the quest complete (`forEachQuestNpc`).
- FIND is a character macro. Only a player action creates it. Automatic writes (login, quest sync, group changes) pass `editOnly` and show no combat notice.
- At most one chat line per action.
- Never write to Blizzard's `AutoCompleteBox`. The chat edit boxes share it, so addon writes would taint them. `UI/Suggestions.lua` rebuilds it from the same templates.
- Build the UI from LibNativeUI-1.0 roles and tokens: `UI.Font`, `UI.Space`, `UI.Color`. No literal `|cff` codes, no font files. Chat goes only through `ns.Announce`.
- Keep the LibDBIcon minimap icon, shown by default. The minimap button, the addon menu and `/tf` share one toggle, `ns.TogglePanel`. `/tf minimap` hides the button through the launcher's `setShown`.
- No `## AddonCompartmentFunc*` toc fields. LibDBIcon registers the addon-menu entry, and the fields would list the addon twice.
- The icon `Interface\Icons\Ability_Hunter_SniperShot` is the toc `IconTexture` and `ns.ADDON_ICON`. `ns.FIND_ICON` is its file ID `132212`, because the macro API takes a number. Change all three together.
- Every size and offset the addon chooses is a multiple of 4. Row buttons share one fixed 48 px trailing column (`TRAILING_WIDTH`), so the input never moves. Copy is Title Case for buttons and menu entries, sentence case with a period for chat and tooltips, no dashes.
- The toc version stays 1.0.0 until the first CurseForge release.
- Licence: MIT (LICENSE).

## Libraries

- `Libs/` holds tracked, unedited upstream copies. No `.pkgmeta` externals.
- LibNativeUI-1.0 is a byte-identical copy. Its reference copy lives in ChatScan, so never edit it here. `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua` must print one hash.

## Checks

- Run `luac -p` on every Lua file and `cd Tests && lua Tests.lua` after a change.
- `Tests/Harness.lua` loads the real LibNativeUI-1.0 and stubs the client. A new client API needs a stub there.
- Turn on `/console scriptErrors 1` before testing in game.
