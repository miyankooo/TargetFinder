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
- The Assist check asks `ns.IdentitySecret` before `UnitInRaid` and `ns.ComparisonSecret` before `UnitIsUnit`, because both return secret booleans when restricted.
- `SetRaidTarget` sets and never toggles, so a re-send while the marker index is hidden is harmless.
- Saved entries store their kind, so the `ns.KIND_*` values never change.
- Never write to Blizzard's `AutoCompleteBox`. The chat edit boxes share it, so addon writes would taint them. `UI/Suggestions.lua` rebuilds it from the same templates.
- Build the UI from LibNativeUI-1.0 roles and tokens: `UI.Font`, `UI.Space`, `UI.Color`. No literal `|cff` codes, no font files. Chat goes only through `ns.Announce`.
- Keep the LibDBIcon minimap icon. The minimap button, the addon menu and `/tf` share one toggle, `ns.TogglePanel`.
- No `## AddonCompartmentFunc*` toc fields. LibDBIcon registers the addon-menu entry, and the fields would list the addon twice.
- Icon `132212` (`Ability_Hunter_SniperShot`) is the toc `IconTexture`, `ns.ADDON_ICON` and `ns.FIND_ICON`. Change all three together.

## Libraries

- `Libs/` holds tracked, unedited upstream copies. No `.pkgmeta` externals.
- LibNativeUI-1.0 is a byte-identical copy. Its reference copy lives in ChatScan, so never edit it here. `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua` must print one hash.

## Checks

- Run `luac -p` on every Lua file and `cd Tests && lua Tests.lua` after a change.
- `Tests/Harness.lua` loads the real LibNativeUI-1.0 and stubs the client. A new client API needs a stub there.
- Turn on `/console scriptErrors 1` before testing in game.
