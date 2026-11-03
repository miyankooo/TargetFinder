# TargetFinder

One FIND macro targets and marks the NPCs the player's quests need, plus NPCs the player adds. Features and usage are in `README.md`.

## Target

- `main` holds the Forever version. `1.15.x-backup` keeps the dual-client 3.2.0.

## Rules

- Read nothing from Questie before `Questie.API.isReady == true`. Never guess readiness from internals. `ns.WatchQuestie()` registers `Questie.API.RegisterOnReady` at `PLAYER_LOGIN`.
- Test `Questie.API`, not `Questie`. A second Questie install leaves `Questie` an empty table.
- Every public entry of `Core/Quest.lua` runs in `pcall`. Private QuestieDB calls are type-checked after ready. `ZoneDB:GetAreaIdByUiMapId` raises on unmapped maps, so it stays wrapped.
- `QuestiePlayer.currentQuestlog` can still hold bare quest ids, so keep the `QuestieDB.GetQuest` fallback.
- Prebuild the NPC name index one frame after Questie is ready, so the first keystroke never stalls.
- `ns.CanAccess` answers nil itself, because `canaccessvalue` takes no nil. Other values go through `pcall(canaccessvalue, v)`. A raise means not accessible.
- Never compare a possibly secret value with `==`.
- FIND follows RestedXP's targeting macro (`RXPGuides/Targeting.lua`, `UpdateMacro`): one `/targetexact` per slot, slot 1 last so it wins, then `/targetlasttarget [dead]`. Names match exactly everywhere.
- Never call `SetRaidTarget`. Forever restricts it for addons (`HasRestrictions`), so RestedXP skips it there too. FIND marks through its own `/tm [harm,nodead] !8` line, written only while the player may mark: solo, party leader, raid leader or assistant.
- Saved entries store only `name`, `quest` and `kind`. Only `quest` entries change by themselves (the Quest NPCs sync and quest picks). Names the player adds, typed, picked or tracked, are never touched.
- One quest NPC rule everywhere: open objectives, or the turn-in NPC once Questie counts the quest complete (`forEachQuestNpc`).
- FIND is a character macro. Only a player action creates it. Automatic writes (login, quest sync, group changes) pass `editOnly` and show no combat notice.
- Never write to Blizzard's `AutoCompleteBox`. The chat edit boxes share it, so addon writes would taint them. `UI/Suggestions.lua` rebuilds it from the same templates.
- Build the UI from LibNativeUI-1.0 roles and tokens: `UI.Font`, `UI.Space`, `UI.Color`. Chat goes only through `ns.Announce`.
- Keep the LibDBIcon minimap icon, shown by default. The minimap button, the addon menu and `/tf` share one toggle, `ns.TogglePanel`. `/tf minimap` hides the button through the launcher's `setShown`.
- The icon `Interface\Icons\Ability_Hunter_SniperShot` is the toc `IconTexture` and `ns.ADDON_ICON`. `ns.FIND_ICON` is its file ID `132212`, because the macro API takes a number. Change all three together.
- Row buttons share one fixed 48 px trailing column (`TRAILING_WIDTH`), so the input never moves.
- Left out on purpose: localization, a RestedXP integration (RestedXP's own macro covers guide targets), a LibQuestieDB migration, Questie tracker buttons (taint risk) and a Blizzard tracker menu entry (`MENU_QUEST_OBJECTIVE_TRACKER` belongs to the container, so the quest is unknown).

## Behaviour

- The Quest NPCs box (`TargetFinderCharDB.questNpcs`, default on) sits in the bottom-left bar slot. A full sync runs on Questie ready, `ZONE_CHANGED`, `ZONE_CHANGED_NEW_AREA` and ticking the box. A light sync (drop finished, fill free slots) runs on every Questie quest update. Both are silent and debounced one frame.
- The unit menu has one entry. Track inserts at slot 1. A full list drops its last quest entry, else its last entry. Untrack removes the name. Exact names only.
- Suggestions preselect the exact typed name, else the first NPC row. A quest row runs `ns.TrackQuest`, which puts that quest's NPCs first.
- Dragging the window portrait calls `PickupMacro` and creates FIND on the first drag. The attic help switches between the drag hint and the press hint on `ACTIONBAR_SLOT_CHANGED`. The macro book never opens by itself. Unit menu adds give one chat reminder per session.
- Item objectives also count droppers of container items (Questie item key `itemDrops`, one level).

## Checks

- Run `cd Tests && lua Tests.lua` after a change.
- `Tests/Harness.lua` loads the real LibNativeUI-1.0 and stubs the client.

## Release

- `.pkgmeta` also leaves out `CLAUDE.md` and lists `questie` as an optional dependency.
