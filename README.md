# Target Finder

Press one macro to target the NPCs your quests need or any NPC you add. It puts a skull on the target.

## Features

- One FIND macro targets the first NPC on your list that is in range. It targets the way RestedXP's targeting macro does: exact names and a step back to your previous target when the pick is a corpse.
- FIND puts a skull on the enemy it targets, through the game's own `/tm` command.
- With Quest NPCs ticked, free rows fill with the kill, loot and turn-in NPCs of your quests that are closest to you. They change with your quests and the zone you are in.
- Names you add stay until you remove them: typed, picked from the suggestions or tracked from a unit's menu.
- Name suggestions from Questie's database while you type. A quest suggestion puts that quest's NPCs first.
- Track and Untrack in the right-click menu of NPC and enemy unit frames.
- A minimap button, an entry in the addon menu and `/tf`.

## Installation

1. Install it with the CurseForge app under WoW Forever, or copy the `TargetFinder` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or type `/reload`.
3. Enable Target Finder in the AddOns list.

## Usage

1. Type `/tf` or click the minimap button to open the window.
2. Drag the icon in the window's top-left corner to an action bar. That button is FIND.
3. Press FIND to target the first NPC on the list that is in range. Press it again for the next one.

Row 1 wins when several NPCs are in range. A quest row shows Questie's kill, loot or turn-in icon. A row you filled shows none.

To add your own NPC, type its name into a row or use Track in its right-click menu. While you type, the first NPC suggestion is highlighted, so Enter takes its full name. Up and Down pick another one and Tab completes the name without storing it.

## Commands

| Command | Does |
| --- | --- |
| `/tf` | Opens or closes the window |
| `/tf minimap` | Hides or shows the minimap button |

`/targetfinder` works as well.

## Requirements

WoW Forever 1.60.x (Interface `16001`).

[Questie](https://www.curseforge.com/wow/addons/questie) is optional. Without it Target Finder works as a plain list. Suggestions and Quest NPCs are off.

## Restrictions

FIND matches whole names, like `/targetexact`. Pick names from the suggestions to get them right.

Targeting by name can't choose between mobs that share a name, so a corpse can still hide a living mob of the same name.

Macros can't be changed in combat. A change made in combat updates FIND when combat ends.

FIND is a character macro and needs a free character macro slot.

In a group, only the party leader, the raid leader or a raid assistant gets the skull.

If a Questie update changes something Target Finder reads, one chat line names the problem and the quest features stay off until an update.

## Development

The offline suite loads the addon in toc order against a client stub and a small fake Questie. It checks logic and wiring, not how the game draws the window.

```sh
cd Tests && lua Tests.lua
```

## License

MIT. See [LICENSE](LICENSE).
