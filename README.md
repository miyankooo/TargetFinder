# TargetFinder

Build a list of up to eight named NPCs and press one macro to target and auto-mark the next relevant one. Quest-aware search and proximity-based "add nearby" when Questie is installed; a plain manual list when it isn't.

## Features

- **One FIND macro** — press it to grab the highest-priority living NPC on your list, and spam it to cycle through them as they come into range
- **Automatic raid markers** — each slot owns a marker, applied whenever you acquire that NPC, by macro or by tab-targeting
- **Add Nearby Quest Units** — fills the list with quest NPCs from your zone, sorted by real distance, kill and drop targets first
- **Quest-aware search** — the slot input matches NPC names from Questie's database and quest names from your log, tagged by role
- **Right-click menu** — Track, Track First and Untrack on any unit frame, plus an **ASSIST** macro for party and raid members
- **Minimap button** — left-click opens the panel, shift+left-click clears the list, right-click adds nearby quest units
- Skips dead NPCs, and for kill and drop slots also skips anything unattackable or tapped by another player

## Installation

1. Copy the `TargetFinder/` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **Target Finder** in the AddOns list.

## Usage

1. Left-click the minimap icon to open the **Target Finder** panel.
2. Type an NPC or quest name into a slot and press **+**, or click **Add Nearby Quest Units**.
3. Open the macro book (`/m`) and drag the **FIND** macro onto your action bar.
4. Press FIND to target and mark. Press it again to move to the next NPC.

There are no slash commands — everything lives in the UI.

## Markers

The eight slots map to markers in this order:

| Slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Marker | Skull | Cross | Square | Triangle | Diamond | Circle | Star | Moon |

## Search roles

| Icon | Role | Source |
| --- | --- | --- |
| ⚔️ | Kill | Quest kill objectives and kill-credit alternates |
| 🎒 | Drop | NPCs that drop items your objectives need |
| ❗ | Quest giver | Quest start and turn-in NPCs |

Clicking a `[Quest]` row adds every NPC tied to that quest at once. **Add All** adds every visible suggestion.

## Requirements

WoW Classic Era 1.15.x. Questie is optional: without it the addon works as a manual list, but name suggestions and **Add Nearby Quest Units** are unavailable.

## Restrictions

- Targeting is protected during combat, so the smart pick is inactive in combat and the macro falls back to its plain `/target` chain.
- Macros cannot be written in combat. Writes made in combat are queued and replayed when you leave it, with a single on-screen notice.
- Names are matched by substring, so tracking `Auctioneer` covers every `Auctioneer <something>`. To track one specific mob, untrack the broad name first.

## Saved data

Your tracked NPC list is saved per character; the minimap icon position is saved per account.
