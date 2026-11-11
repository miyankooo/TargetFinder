# Changelog

## [1.3.0](https://github.com/miyankooo/TargetFinder/compare/v1.2.0...v1.3.0) (2026-11-11)


### Features

* FIND is created under General Macros, shared by all your characters ([2e7b214](https://github.com/miyankooo/TargetFinder/commit/2e7b214eae43e9f7e4c9fa16db9ffb4628c85890))
* Quest NPCs and suggestions come from QuestieDB, so Questie is no longer needed ([117cbe9](https://github.com/miyankooo/TargetFinder/commit/117cbe9ef1ac8ecf03db553134e50909cef5744f))


### Bug Fixes

* FIND clears a dead target first and no longer jumps back to your last target ([a8c7bdf](https://github.com/miyankooo/TargetFinder/commit/a8c7bdfd6ace90d754409ae4f2e41db149a4a34d))

## [1.2.0](https://github.com/miyankooo/TargetFinder/compare/v1.1.0...v1.2.0) (2026-11-09)


### Features

* An empty list shows what to type in its first row ([8d649e0](https://github.com/miyankooo/TargetFinder/commit/8d649e053627174273e458477a9c475c13a30d40))
* Apply Pings makes FIND ping its target ([ea11ff5](https://github.com/miyankooo/TargetFinder/commit/ea11ff5a80358cbdbfd946f01e85206baf085231))
* The name boxes, Add and the remove button explain themselves in tooltips ([6fcd9f1](https://github.com/miyankooo/TargetFinder/commit/6fcd9f1863d5c16560a200e9012b39ba3e1304ac))


### Bug Fixes

* A tip brought back by /tf intro stays until you close it ([62e11bd](https://github.com/miyankooo/TargetFinder/commit/62e11bd188a47fd5a5344266130989ea0f90b6df))
* Chat lines show the addon name in gold ([1bef310](https://github.com/miyankooo/TargetFinder/commit/1bef310ee3c402df888f03447534c7a869845ed4))
* Clearer welcome line, /tf help and macro book tip ([25dbad3](https://github.com/miyankooo/TargetFinder/commit/25dbad31367f8f0bdd1adaa3d8c6f3e3ff155bb0))
* Hiding the minimap button with /tf minimap says how to bring it back ([b4970c1](https://github.com/miyankooo/TargetFinder/commit/b4970c1c17edd129f48239e0c3abb64739370d94))
* The red combat notice no longer repeats the addon name ([bf27e80](https://github.com/miyankooo/TargetFinder/commit/bf27e8046086a33854a9f602e5d6f414b941bd35))
* The welcome line names the Target Finder window ([ff71199](https://github.com/miyankooo/TargetFinder/commit/ff71199b22cebca6aa7f31164631ac3d550bdf38))

## [1.1.0](https://github.com/miyankooo/TargetFinder/compare/v1.0.0...v1.1.0) (2026-11-08)


### Features

* Track and Untrack sit at the top of the right-click menu on NPC and player portraits
* Drag a row's number to change the order of your targets
* Apply Raid Markers: FIND now marks its target with a cross, the way RestedXP's targeting macro does, instead of a skull
* Quest NPCs update when you accept, turn in or abandon a quest
* Right-click the minimap button or type `/tf refresh` to update the quest NPCs where you stand
* The first FIND macro opens the macro book on it with its icon glowing and a tip on where to drag it
* A welcome line on first login, plus `/tf help` and `/tf intro`
* The top of the window explains how to add names and names the next FIND step
* Quest NPCs is now called Auto Apply Quest NPCs
* The window shows the wardrobe's brown panel behind the rows, with room around the checkboxes
* The remove button sits right next to its name


### Bug Fixes

* FIND builds its macro exactly like RestedXP's targeting macro

## 1.0.0 (2026-11-06)


### Features

* One FIND macro targets the first NPC on your list that is in range, matching whole names, and steps back to your previous target when it lands on a corpse
* FIND puts a skull on the enemy it targets through the game's own `/tm` command. In a group only the leader or a raid assistant marks
* Up to eight names, with row 1 first
* With Questie, the Quest NPCs box fills free rows with the closest kill, loot and turn-in NPCs of your quests and follows your quests and the zone you are in. Quest rows show Questie's icons
* With Questie, names are suggested as you type. The first NPC is highlighted, so Enter takes its full name, and a quest suggestion puts that quest's NPCs first
* Track and Untrack in the right-click menus of NPCs and enemy players
* `/tf add` tracks a typed name, or your target, at the top of the list
* FIND appears in your character macros as soon as the list has a name. Track and `/tf add` open the macro book on it until it sits on an action bar
* Drag FIND from the window's icon straight to an action bar
* A minimap button, an entry in the addon menu and `/tf`. `/tf minimap` hides or shows the minimap button
* Changes made in combat update FIND when combat ends
