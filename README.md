# Target Finder

Build a list of up to eight named NPCs and press one macro to target and auto-mark the next relevant one. Quest-aware search and proximity-based "add nearby" when Questie is installed; works as a pure manual list when it isn't. WoW Classic 1.15.x.

## How it works

Target Finder maintains a single **FIND** macro shaped like:

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

Both **FIND** and **ASSIST** are written out of combat only. Blizzard blocks `CreateMacro` / `EditMacro` during combat, so writes made in combat are queued and replayed on `PLAYER_REGEN_ENABLED`, with a single red on-screen notice per combat session.

## Panel

Left-click the minimap icon to toggle a draggable panel titled **Target Finder**. A yellow **Tracked Unit Names** header with a short grey helper text sits above the eight slots, which live directly in the frame:

- Each slot displays its assigned raid marker, the tracked NPC name, and a close button to remove it.
- Each slot input accepts any NPC or quest name; suggestions appear in a popup (Questie required for suggestions).
- **+** — round red icon button (same family as the close button) that appears while typing; adds the typed name to that slot.
- **Add Nearby Quest Units** — clears the list and refills it with quest-related NPCs from your current zone, sorted by actual distance to your character. Disabled with a greyed-out `Requires Questie.` tooltip when Questie is not installed.
- **Clear Unit List** — empties the list. Sits beside the nearby button at equal width.

Press Escape or the corner `X` to close the panel.

## Search (Questie required)

The input box matches both NPC names from Questie's database and quest names from your current quest log. Quest-related NPCs are tagged with their quest name in brackets and grouped by role:

- ⚔️ **Kill** — `objectives.creatures` and kill-credit alternates
- 🎒 **Drop** — NPCs that drop items required by your quest objectives
- ❗ **Quest giver** — `startedBy` and `finishedBy` NPCs

Each appears with the matching Questie icon (sword, bag, gold `!`). Within the suggestion popup, quest rows are labelled `[Quest] <name>`; clicking one adds every NPC tied to that quest in one batch.

The **Add All** footer button in the popup adds every visible suggestion, expanding any quest rows into their NPC list and deduping.

## Minimap icon

- **Left-click** — toggle the panel.
- **Shift + left-click** — clear the unit list.
- **Right-click** — add nearby quest units (same as the panel button). Greyed out in the tooltip, with a `Requires Questie.` note, when Questie is not installed.

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

Right-click any unit frame (target, party, raid, etc.) for a single **Target Finder** submenu, appended after a divider. Everything lives one level down so the addon costs one row in an already-crowded menu:

- **Assist** — shown only for friendly players in your party or raid. Writes an **ASSIST** macro containing `/assist NAME`, then opens the macro book and pulses the icon if that macro isn't on an action bar yet, exactly like the **FIND** macro. Drag it onto a bar once and press it to pick up whatever the current assist target is fighting.
- **Track First** — put this NPC at slot 1 for top priority, shifting everything else down. Hidden when it already holds slot 1. Adding a new name to a full list drops the slot-8 entry and names it in chat.
- **Track** — append this NPC to the next empty slot. Hidden if it's already tracked.
- **Untrack** — shown only if this NPC is already tracked.
- **Clear Unit List** — shown only if the list isn't empty, behind its own divider so it isn't a neighbour-misclick away from **Untrack**. Same label as the panel button, for the same action.

Names deliberately avoid the word *focus*: Blizzard's own **Set Focus** sits in the same menu and means something else entirely.

### One entry, one set of actions

The menu matches by substring, so tracking `Auctioneer` makes every `Auctioneer <something>` read as tracked. All three actions then operate on that one matched entry, never on a near-duplicate of it:

- **Untrack** removes `Auctioneer`.
- **Track First** moves `Auctioneer` to slot 1. It does not add `Auctioneer Chillgular` alongside it.
- **Track** is hidden, because something already covers this NPC.

To track the specific mob instead, untrack the broad name first, then track the specific one.

Yourself, hostile players and NPCs never get the **Assist** entry. Group membership is tested with `UnitInParty` / `UnitInRaid` against the menu's unit token, falling back to the character name the way Blizzard's own `UnitPopupSharedUtil.IsInGroupWithPlayer` does.

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

There are no slash commands. Everything lives in the UI.

## Saved data

Per-character: your tracked NPC list. Account-wide: the minimap icon position. Both persist across reloads and logins.
