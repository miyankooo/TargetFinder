# TargetFinder

Find and auto-mark named targets with raid markers for WoW Classic 1.15.x.

## How it works

TargetFinder maintains a **FIND** macro that targets each name on your finder list in order, and applies a raid marker to any unit on the list as soon as you target them. After your first `/find` command, open the macro book (`/m`) and drag **FIND** onto your action bar.

## Commands

- `/find NAME` — set the finder to `NAME` (uses current target if `NAME` omitted)
- `/find+ NAME` — add `NAME` to the finder (uses current target if omitted; max 8)
- `/find reset` — clear the finder list

You can also right-click any unit frame for **Set Finder**, **Add to Finder**, and **Reset Finder**.

## Markers

The finder list holds up to 8 names, each tied to one raid marker in this order:

1. Circle
2. Square
3. Triangle
4. Star
5. Diamond
6. Moon
7. Cross
8. Skull

Markers are applied via `PLAYER_TARGET_CHANGED`: whenever you target a unit whose name matches an entry on the list and the unit has no existing mark, the corresponding marker is set. Manual marks are never overwritten.
