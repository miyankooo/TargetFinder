# TargetFinder

Build a list of up to eight named NPCs and press one macro to target and auto-mark the next relevant one. Quest-aware search and proximity-based "add nearby" when Questie is installed; works as a pure manual list when it isn't. WoW Classic 1.15.x.

## How it works

TargetFinder maintains a single **FIND** macro that runs `/cleartarget` followed by a `/target NAME` line for each entry in your tracked list. The first name whose unit is in range becomes your target, and the addon automatically applies that slot's raid marker via `PLAYER_TARGET_CHANGED`. Spam the macro to cycle through your tracked NPCs as they come within range.

After you first add something, open the macro book (`/m`) and drag **FIND** onto your action bar.

## Panel

`/tf` (or left-click the minimap icon) toggles a draggable panel showing all eight slots:

- Each slot displays its assigned raid marker, the tracked NPC name, and a close button to remove it.
- **Add Nearby Quest NPCs** — clears the list and refills it with quest-related NPCs from your current zone, sorted by actual distance to your character. Requires Questie.
- **Add target** input — type any NPC or quest name; suggestions appear in a popup (Questie required for suggestions).
- **Add** — adds the typed name (or your current target if the input is empty).
- **Clear** — empties the list.

Press Escape to close the panel.

## Search (Questie required)

The input box matches both NPC names from Questie's database and quest names from your current quest log. Quest-related NPCs are tagged with their quest name in brackets and grouped by role:

- ⚔️ **Kill** — `objectives.creatures` and kill-credit alternates
- 🎒 **Drop** — NPCs that drop items required by your quest objectives
- ❗ **Quest giver** — `startedBy` and `finishedBy` NPCs

Each appears with the matching Questie icon (sword, bag, gold `!`). Within the suggestion popup, quest rows are labelled `[Quest] <name>`; clicking one adds every NPC tied to that quest in one batch.

The **Add All** footer button in the popup adds every visible suggestion, expanding any quest rows into their NPC list and deduping.

## Minimap icon

- **Left-click** — toggle the panel.
- **Right-click** — refresh the list with nearby quest NPCs (same as the panel button). Requires Questie.

## Right-click unit-frame menu

Right-click any unit frame (target, party, raid, etc.) for:

- **Set Target** — replace the list with this NPC.
- **Add Target** — append this NPC.
- **Remove Target** — shown only if this NPC is already tracked.
- **Clear Targets** — shown only if the list isn't empty.

## Markers

The list holds up to 8 names, each tied to one raid marker in this order:

1. Skull
2. Cross
3. Square
4. Triangle
5. Diamond
6. Circle
7. Star
8. Moon

The marker is applied whenever the macro acquires a target, and also when you tab- or click-target any saved NPC outside the macro (via `PLAYER_TARGET_CHANGED` with a case-insensitive substring match). Marker writes are deduped, so spamming the macro never causes flicker.

## Slash commands

- `/tf` — toggle the panel.
- `/tf NAME` — replace the list with just `NAME` (slot 1, skull marker).
- `/tf clear` — empty the list.

Everything else lives in the UI.

## Saved data

Per-character: your tracked NPC list. Account-wide: the minimap icon position. Both persist across reloads and logins.
