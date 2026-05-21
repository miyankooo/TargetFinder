# TargetFinder

Build a list of up to eight named NPCs and press one macro to target and auto-mark the next relevant one. Quest-aware search and proximity-based "add nearby" when Questie is installed; works as a pure manual list when it isn't. WoW Classic 1.15.x.

## How it works

TargetFinder maintains a single **FIND** macro shaped like:

```
/run TF_Cycle()
/stopmacro [nodead]
/target NAME1
…
/target NAME8
```

Pressing the macro fires `TF_Cycle()` once, which scans visible nameplates and prefers a **living** match — for kill/drop slots, also **attackable** and **not tapped by another player**. Slots are checked in priority order (slot 1 first), so the highest-priority living candidate wins. If `TF_Cycle` finds one, `/stopmacro [nodead]` ends the macro there. Otherwise the `/target` chain runs as today and grabs whoever's in range (also the in-combat path — `TF_Cycle` is a no-op in combat because Blizzard protects targeting from `/run`).

Either way the addon applies the slot's raid marker via `PLAYER_TARGET_CHANGED`. Spam the macro to cycle through your tracked NPCs as they come within range.

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
- **Right-click** — refill the list with nearby quest NPCs (same as the panel button). Requires Questie.

### Right-click selection rule

Candidates are gathered from your current quest log:

- **Active (incomplete) quests** contribute kill targets (`monster`/`killcredit` objectives) and item-drop NPCs (`npcDrops` for `item` objectives).
- **Completed quests** contribute their `finishedBy` turn-in NPCs.
- `startedBy` NPCs and `finishedBy` NPCs on incomplete quests are skipped — they aren't actionable.

Candidates are then narrowed by distance and ordered by priority:

1. Sort the whole candidate pool by distance ascending; take the closest 8.
2. Within those 8, sort by priority: **Kill → Drop → Turn-in**, with distance as the tiebreaker.

Result: in the field, the list fills with kill/drop mobs; in a city standing on top of turn-in NPCs, the list fills with quest givers. Either way, the macro cycles the highest-priority slot first.

If nothing nearby qualifies, you'll see `Nothing to track here yet.`

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
