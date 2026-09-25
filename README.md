# TargetFinder

Build a list of up to eight named NPCs and press one macro to target and auto-mark the next relevant one. Quest-aware search and proximity-based "add nearby" when Questie is installed; a plain manual list when it isn't.

One addon folder runs on both **WoW Classic Era 1.15.9** and **WoW Forever 1.60.1**. Each client draws the panel, buttons and popups with its own Blizzard art.

## Features

- **One FIND macro**: a `/target` chain written in reverse, so slot 1 wins when several tracked NPCs are in range. `/target` does nothing when no name matches, so FIND never clears your target and never grabs an off-list mob. Spam it to move through your NPCs as they come into range.
- **Automatic raid markers**: each slot owns one marker. It is applied when you acquire that NPC by macro, tab or click. Filling a slot also marks one matching unit already in view.
- **Add Nearby Quest Units**: fills the list from your quest log with the closest open objectives, kill and drop targets first, or the turn-in NPC once Questie counts the quest complete.
- **Quest-aware search**: the slot input suggests NPC names from Questie's database and quest names from your log, tagged by role.
- **Right-click menu**: Track, Track First, Untrack and Clear on unit frames, plus an **ASSIST** macro for party and raid members.
- **Launchers**: a minimap button on both clients, and on WoW Forever also an entry in the addon menu under the minimap.

## Installation

1. Copy the `TargetFinder/` folder into your client's AddOns folder:
   - Classic Era: `World of Warcraft/_classic_era_/Interface/AddOns/`
   - WoW Forever: `World of Warcraft/_classic_beta_/Interface/AddOns/`
2. Restart the game or `/reload`.
3. Enable **Target Finder** in the AddOns list.

## Usage

1. Left-click the minimap icon to open the **Target Finder** panel.
2. Type an NPC or quest name into a slot and press Enter or **Add**, or click **Add Nearby Quest Units**.
3. The addon opens the macro book and pulses **FIND** until it is on a bar. Drag it onto your action bar.
4. Press FIND to target and mark. Press it again to move to the next NPC.

There are no slash commands. Everything lives in the UI.

### Panel

A standard Blizzard window (the same frame as the AddOns list). Drag it by the title bar, close it with Escape or the corner button.

- Each slot shows its raid marker, the tracked name and a close button to remove it.
- While you type a new name, the close button turns into **Add**.
- **Add Nearby Quest Units** replaces the list. Its tooltip says why when it is disabled.
- **Clear Unit List** empties the list.

### Suggestions

Suggestions open under the slot you type in, styled like Blizzard's own name autocomplete.

- Up and Down pick a row, Enter stores it. With nothing picked, Enter stores exactly what you typed.
- Tab completes the picked NPC name, or the first one, into the box without storing it.
- A `[Quest]` row adds every NPC tied to that quest at once.
- **Add All** adds every visible suggestion, expanding quest rows.
- Names that start with what you typed come before names that only contain it, because only the first kind is something FIND can acquire.

### Minimap button and addon menu

- **Left-click**: toggle the panel.
- **Shift + left-click**: clear the unit list.
- **Right-click**: add nearby quest units.

The tooltip tells Questie being absent apart from Questie still loading its database, which fixes itself a few seconds after login.

### Right-click unit menu

A **Target Finder** section at the bottom of unit-frame menus:

- **Assist**: only for friendly players in your party or raid. Writes an **ASSIST** macro with `/assist NAME`.
- **Track First**: puts this NPC in slot 1 and shifts the rest down. A full list drops slot 8 and names it in chat.
- **Track**: adds this NPC to the next empty slot.
- **Untrack**: removes the entry that covers this NPC.
- **Clear Unit List**: behind its own divider, so it is not a misclick away from Untrack.

The menu matches by name prefix, so with `Auctioneer` tracked every `Auctioneer <something>` counts as covered. Track First and Untrack then act on the `Auctioneer` entry, never on a near-duplicate.

## Markers

The eight slots map to markers in this order:

| Slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Marker | Skull | Square | Circle | Star | Cross | Triangle | Diamond | Moon |

A raid marker sits on one unit at a time, so each slot marks exactly one:

1. your current target, when its name belongs to that slot
2. otherwise a visible nameplate that already carries the marker, so a marked mob keeps it
3. otherwise the first matching nameplate

A unit belongs to the first slot whose name covers it, so `Kobold` in slot 1 and `Kobold Miner` in slot 2 never fight over one mob. The chat line after an add counts one unit per slot that found a match.

## Search roles

| Icon | Role | Source |
| --- | --- | --- |
| Questie's sword | Kill | Kill objectives and kill-credit alternates |
| Questie's bag | Drop | NPCs that drop items your objectives need |
| Questie's `!` | Quest giver | Quest start and turn-in NPCs |

Objectives Questie already counts as done are left out.

## Add Nearby Quest Units

Candidates come from your quest log, as Questie sees it:

- **Quests still in progress**: kill targets and item droppers for the objectives Questie still counts as open.
- **Quests Questie counts as complete**: the turn-in NPC only.

Only NPCs that spawn in your current zone, or already show a nameplate, qualify. The closest eight are kept, then ordered Kill, Drop, Turn-in, with distance as the tiebreak. If nothing qualifies, chat says `Nothing to track here yet.`

## Requirements

| Client | Interface | Questie |
| --- | --- | --- |
| WoW Classic Era 1.15.9 | `11509` | Questie 11.x (bundled database), or Questie 12 with the **QuestieDB** addon |
| WoW Forever 1.60.1 | `16001` | Questie 12 with the **QuestieDB** addon |

Questie is optional. Without it the addon works as a manual list, and name suggestions and **Add Nearby Quest Units** are unavailable. Questie is the only quest data source: names, spawns, drops, givers and objective progress all come from it. The native quest API is not used for quest data.

## Restrictions

- Macros cannot be written in combat. Writes made in combat are queued and replayed when you leave it, with one on-screen notice per fight.
- Names match from the start, like `/target`. Tracking `Auctioneer` covers `Auctioneer Chillgular`; tracking `Chillgular` does not, because FIND could never acquire it.
- Blizzard decides who may set raid markers in a group (on Classic Era, in a raid, only the leader and assistants). When you may not, the markers simply do not appear.
- On WoW Forever, restricted content can hide unit names and identities from addons. The addon then skips marking that unit and withholds **Assist**; everything else keeps working.
- If a Questie update changes something the addon reads, you get one chat line naming the problem instead of Lua errors, and the Questie features stay off until an update.

## Saved data

Your tracked NPC list is saved per character; the minimap icon position is saved per account.

## Development

The offline suite loads the addon in toc order against a client stub and a small fake Questie: `cd Tests && lua Tests.lua`. It proves logic and wiring, not client rendering.

| Path | Holds |
| --- | --- |
| `TargetFinder.toc` | One toc for both clients, `## Interface: 11509, 16001`, plus the addon-menu entry points |
| `TargetFinder.lua` | Bootstrap: saved variables and the three events |
| `Core/Client.lua` | Every Lua-level difference between the clients, detected by feature |
| `Core/Store.lua` | The slot table, the name rule, saved-variable adoption |
| `Core/Markers.lua` | Raid markers, one unit per marker |
| `Core/Macro.lua` | FIND and ASSIST macros, combat queue, macro-book hint |
| `Core/Targets.lua` | List changes |
| `Core/Quest.lua` | Questie integration, the only quest data source |
| `Core/Suggestions.lua` | The autocomplete popup |
| `Core/Panel.lua` | The panel and its slot rows |
| `Core/MinimapButton.lua` | Minimap button and addon-menu entry |
| `Core/UnitMenu.lua` | Unit menu entries |
| `.pkgmeta` | Packaging; leaves `Tests` and `MEMORY.md` out |
