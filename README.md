# FindAssist-Classic

**World of Warcraft Classic addon** for quick target finding and assist macro management.

## Features

- **Find Macro**: Automatically creates and updates a FIND macro to target specific enemies (perfect for PvP and battlegrounds)
- **Mark Macro**: Creates a companion MARK macro that targets and marks enemies with a skull to help your team identify priority targets
- **Multiple Targets**: Support for up to 3 targets in rotation with "Also Find" functionality
- **Assist Macro**: Creates an ASSIST macro to assist a specific player for coordinated focus targets

## Commands

### /find [name]
Creates or updates the FIND and MARK macros to target the specified enemy. If no name is provided, uses your current target.

**Examples:**
```
/find                    - Use current target
/find Healer             - Find enemy named "Healer"
```

### /alsofind [name]
Adds an additional target to the FIND/MARK macros (up to 3 targets total). Targets are cycled through in order.

**Examples:**
```
/alsofind Mage          - Add "Mage" to the target list
/alsofind               - Add current target to the list
```

### /assist [name]
Creates or updates an ASSIST macro to assist the specified player. If no name is provided, uses your current target.

**Examples:**
```
/assist                 - Assist current target
/assist PlayerName      - Assist specific player
```

## Created Macros

The addon creates the following macros automatically:

- **FIND**: Targets your specified enemy/enemies in order
- **MARK**: Targets and marks your enemies with a skull icon (if not already marked)
- **ASSIST**: Assists your specified player

Drag the created macros to your action bars for quick access and combine with keybinds for instant targeting.
