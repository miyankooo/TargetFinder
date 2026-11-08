# Changelog

## [1.1.0](https://github.com/miyankooo/TargetFinder/compare/v1.0.0...v1.1.0) (2026-11-08)


### Features

* a welcome line on first login, a help tip at the FIND macro, and /tf help and /tf intro ([4e4630a](https://github.com/miyankooo/TargetFinder/commit/4e4630a62865463be38a7b35a79a786654849d97))
* Apply Raid Markers gives each listed NPC you target the marker of its row, skull for row 1 down to star for row 8 ([5dfe357](https://github.com/miyankooo/TargetFinder/commit/5dfe3572ee20a5bc6f4a75402a7c4761c0f1a4d4))
* drag a row's number to change the order of your targets ([ea2e21b](https://github.com/miyankooo/TargetFinder/commit/ea2e21b5deb7f4737855008b961f6d9c41b9d3b3))
* Quest NPCs is now called Auto Apply Quest NPCs ([5dfe357](https://github.com/miyankooo/TargetFinder/commit/5dfe3572ee20a5bc6f4a75402a7c4761c0f1a4d4))
* quest NPCs update when you accept, turn in or abandon a quest ([4e4630a](https://github.com/miyankooo/TargetFinder/commit/4e4630a62865463be38a7b35a79a786654849d97))
* right-click the minimap button or type /tf refresh to update the quest NPCs where you stand ([4e4630a](https://github.com/miyankooo/TargetFinder/commit/4e4630a62865463be38a7b35a79a786654849d97))
* the checkboxes at the bottom of the window get room around them ([12e1e0a](https://github.com/miyankooo/TargetFinder/commit/12e1e0ac3c54c4b777873acade0c9ab6938b79e8))
* the first FIND macro opens the macro book on it with its icon glowing, and the window says FIND is created for you ([5dfe357](https://github.com/miyankooo/TargetFinder/commit/5dfe3572ee20a5bc6f4a75402a7c4761c0f1a4d4))
* the remove button sits right next to its name ([ea2e21b](https://github.com/miyankooo/TargetFinder/commit/ea2e21b5deb7f4737855008b961f6d9c41b9d3b3))
* the top of the window explains how to add NPCs and names the next FIND step ([0970619](https://github.com/miyankooo/TargetFinder/commit/09706196b2ceaf5383fcecbf93a78fecd4e1cba2))
* the window shows the wardrobe's brown panel behind the rows ([7b1d9a3](https://github.com/miyankooo/TargetFinder/commit/7b1d9a34d751f17fd5edbeab06496558ad8fe132))
* the window's panels show the grey stone background instead of the dark marble ([8327d86](https://github.com/miyankooo/TargetFinder/commit/8327d863bb176bc03642ac2e0f880ccf39daf6e7))
* Track and Untrack sit at the top of the right-click menu on NPC and player portraits ([4e4630a](https://github.com/miyankooo/TargetFinder/commit/4e4630a62865463be38a7b35a79a786654849d97))


### Bug Fixes

* FIND works like RestedXP's targeting macro and marks its target with a cross ([9e56da8](https://github.com/miyankooo/TargetFinder/commit/9e56da8645722013599ab2f4a39c4a901c030c8a))
* raid markers go on through FIND itself, so the addon no longer triggers a blocked-action error ([4a4470d](https://github.com/miyankooo/TargetFinder/commit/4a4470d167174b729db501cca7d77f56d24aebe5))

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
