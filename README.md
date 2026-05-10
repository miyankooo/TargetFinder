# TargetShortcuts

Target finding and assist macros with raid markers for WoW Classic 1.15.x.

## How it works

The addon maintains two macros for you: **FIND** and **ASSIST**. Type `/find <name>` to point FIND at a player; press the FIND macro on your action bar to target them and auto-mark them. After you've used the slash commands once, open your macro book (`/m`) and drag the FIND and ASSIST macros onto your action bar.

## Commands

- `/find NAME` — set Find target (uses current target if NAME omitted)
- `/find add NAME` — add to Find (max 3: circle, square, triangle)
- `/find clear` — clear Find
- `/find list` — show current Find targets
- `/find help` — show help
- `/assist NAME` — set Assist target

You can also right-click any unit frame for **Find**, **Add to Find**, **Clear Find**, and **Assist** options.

## Markers

Slot 1 gets the orange circle, slot 2 gets the blue square, slot 3 gets the green triangle. Markers are only applied when the target has no mark, so any manual marks you place are preserved.

## Note

This addon overrides Blizzard's `/assist` chat slash command (it sets your ASSIST macro instead). Inside macros, `/assist NAME` still behaves normally.
