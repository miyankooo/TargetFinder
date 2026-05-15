# QuickTarget

Find and auto-mark named targets with raid markers, plus a quick assist macro, for WoW Classic 1.15.x.

## How it works

QuickTarget maintains a **FIND** macro that targets each name on your finder list in order and then applies the matching raid marker to whichever unit was acquired. It also maintains an **ASSIST** macro that assists a named player. After your first `/find` or `/assist` command, open the macro book (`/m`) and drag **FIND** or **ASSIST** onto your action bar.

## Commands

- `/qt` — open the finder panel (add, remove, reset entries in a native window)
- `/find NAME` — set the finder to `NAME` (uses current target if `NAME` omitted)
- `/findadd NAME` — add `NAME` to the finder (uses current target if omitted; max 8)
- `/find reset` — clear the finder list
- `/assist NAME` — set the assist macro to `NAME` (uses current target if omitted; overwrites each time)

You can also right-click any unit frame for **Set Finder**, **Add to Finder**, **Remove from Finder**, **Reset Finder**, and **Set Assist**.

## Panel

`/qt` toggles a draggable panel showing all eight finder slots, each with its raid marker icon, name, and a close button to remove that entry. An input field at the bottom adds a new name (or the current target if the field is left empty), and a **Reset** button clears the list. Press Escape to close the panel.

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

`/find` and `/findadd` apply the new slot's marker to your current target immediately. The **FIND** macro emits `/run QuickTargetMark(slot)` after each `/target` line, so whichever unit `/target` actually acquired (including fuzzy matches like `commander` → "Commander Ilya") gets the slot's marker. Tab- or click-targeting a saved unit outside the macro also applies its marker via `PLAYER_TARGET_CHANGED`, using a case-insensitive substring match so partial names like `commander` still match "Commander Ilya". Marker writes are deduped, so spamming the macro never causes flicker.

Finder state is in-memory only and resets on `/reload` or logout. The **FIND** macro itself is saved by Blizzard and keeps working across sessions, but click/tab auto-marking won't fire again until you re-run `/find`.
