# TargetFinder — Memory

Updated 2026-09-25 after the dual-client port with native UI and Questie-only quest data (decision: every addon in the folder supports both clients, and quest data comes only from Questie). Verified against Gethe `forever` @ `bd2470a` (1.60.1.70009), Gethe `classic_era` @ `33e177d` (1.15.9.69722), the matching Ketho dumps, Questie 11.37.1 (installed), Questie master @ `4001614` and QuestieDB master @ `b6f5b07`. Nothing has run in a client. `cd Tests && lua Tests.lua` passes 136 of 136, which proves logic and wiring, not client behaviour.

## Current state

Keeps up to 8 NPC names and writes one **FIND** macro, a reversed `/target` chain in which slot 1 wins. Each slot's raid marker goes to exactly one unit: the current target if it matches, otherwise one visible nameplate.

It also has:

- A panel with Questie autocomplete and "Add Nearby Quest Units" quick add.
- Unit-menu entries: Assist, Track First, Track, Untrack and Clear.
- A minimap button, plus the Addon Compartment on Forever.
- Macro writes that wait until combat ends.

| Item | State |
|---|---|
| Version | 3.2.0, both clients from one toc, `## Interface: 11509, 16001`, `## Author: miyanko`, Addon Compartment fields, `.pkgmeta` (ignores `Tests` and `MEMORY.md`) |
| Git | Committed and pushed on 2026-09-25: `main` = `origin/main`. GitHub's README restructure and author fix were merged with the local README and toc kept. The last Era-only release is 3.0.0 at `fe67245`, which would break on 1.60 |

Quest data comes only from Questie, through `Core/Quest.lua`:

- Objective progress is `quest.Objectives[i].Completed` / `quest.isComplete` from `QuestiePlayer.currentQuestlog`. There's no `C_QuestLog` anymore.
- Every internal (`QueryNPCSingle`, `QueryQuestSingle`, `QueryItemSingle`, `NPCPointers`, `ObjectiveData`, `IsComplete`, `ZoneDB`, `usedIcons`) exists in both 11.37.1 and master.
- Each internal is type-checked, and each public entry runs in `pcall`, with one chat line on the first failure.
- `ZoneDB:GetAreaIdByUiMapId` raises on unmapped maps, so it's wrapped in `pcall`.
- On Questie 12, "ready" also requires `NPCPointers`, which that version sets later than its query functions.
- Native APIs are left only for non-quest data: player map position, units, macros and markers.

Client handling, by feature only, lives in `Core/Client.lua`:

- `canaccessvalue` is called inside `pcall` (it's `SecretArguments = "AllowedWhenUntainted"` on 1.60). A raise means "not readable", and a missing function means readable.
- `C_Secrets.ShouldUnitIdentityBeSecret`.
- `Constants.MacroConsts` with `MAX_ACCOUNT_MACROS` as the fallback.

Native UI:

- The panel is a `ButtonFrameTemplate` window without a portrait, laid out like AddonList. Its X closes through `onCloseCallback`, so it works in combat.
- The Add button is `UIPanelButtonTemplate`, and remove is `UIPanelCloseButtonNoScripts`.
- Suggestions are built like Blizzard's name autocomplete: `TooltipBackdropTemplate`, `AutoCompleteButtonTemplate` rows and the `PRESS_TAB` hint. Blizzard's shared `AutoCompleteBox` isn't used, because writing to it would taint chat.

## Blockers, issues, challenges

1. The biggest Forever risk is `canaccessvalue` from addon code. If it raises even on plain values, every name reads as hidden, and marking and menus silently stop.
2. On Forever, Questie 12 and QuestieDB aren't installed. The installed 11.37.1 doesn't load there, so quest features are off on Forever until Questie 12 ships.
3. `SetRaidTarget` is `HasRestrictions = true`. Whether it works solo and in a party on 1.60 is unverified.
4. Forever spawn coordinates match player map space only according to QuestieDB's own audit.
5. Decision pending: the README's marker order differs from the code. The code gives Skull, Square, Circle, Star, Cross, Triangle, Diamond, Moon (`Core/Core.lua:17`), and the README now matches the code.
6. There's no `_classic_era_` install. The installed beta is 69913, the source is 70009.

## Next steps

1. Run `/console scriptErrors 1` first.

Both clients:

- [ ] Type a nearby NPC in slot 1 and press Enter: a Skull shows in the row and the macro book opens with FIND pulsing. `/m` shows `/target Name`.
- [ ] Put FIND on a bar near the NPC: it gets targeted and Skull-marked, solo and in a party. This settles issue 3.
- [ ] With 2–3 same-named mobs on screen, add the name: exactly one gets the marker and chat says "— 1 marked".
- [ ] Target a wolf and type "Kobold": the wolf stays unmarked.
- [ ] Track "Chillgular" near "Auctioneer Chillgular": FIND never targets the auctioneer.
- [ ] Add a slot in combat: one notice, and the macro updates after combat. The panel's X closes in combat.
- [ ] Type "Kob": the popup looks like the whisper autocomplete. Up/Down, Enter and Tab work.
- [ ] Finish a kill objective: that mob drops out of suggestions and Add Nearby without a `/reload`.
- [ ] Click Add Nearby inside a dungeon: no Lua error.

Era, with Questie 11.37.1:

- [ ] The classic frame art and round X. With Questie disabled, Add Nearby is greyed out and its tooltip says Questie isn't loaded.

Forever, with Questie 12 and QuestieDB:

- [ ] Mainline art. The compartment entry has the same tooltip: left-click toggles, right-click adds nearby.
- [ ] Track a mob from its unit menu outside restricted content: it gets marked. This settles issue 1.
- [ ] In a dungeon, run `/run print(pcall(canaccessvalue, UnitName("target")))`: no Lua error, and Assist is hidden.
- [ ] Add Nearby right after login says "Questie is still loading.". Distances look right in a zone whose map differs on Forever.
- [ ] Run `/dump Constants.MacroConsts.MAX_ACCOUNT_MACROS, MAX_ACCOUNT_MACROS`: it prints `120 nil`.
