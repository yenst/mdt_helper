# MDTHelper

A World of Warcraft addon that displays your [Mythic Dungeon Tools](https://www.curseforge.com/wow/addons/mythic-dungeon-tools) route as a live checklist during Mythic+ runs.

## What It Does

MDTHelper reads the currently selected MDT route when you enter a dungeon and shows a compact overlay listing every pull in order. As you progress through the key, pulls are automatically marked complete based on enemy forces gained. The current pull is expanded to show each mob type with its portrait, name, clone count, and percentage of total forces.

A forces progress bar at the top tracks your overall enemy forces completion.

## Features

- **Auto-detection** — activates when you enter a Mythic+ dungeon, hides outside instances
- **Auto-advance** — marks pulls complete when ~80% of expected forces are gained; also advances on boss kills (toggleable via header button or settings)
- **Expanded current pull** — the active pull shows detailed mob info with NPC portraits
- **Compact pull list** — other pulls show stacked portraits with clone counts
- **Forces bar** — real-time forces progress shown as count and percentage
- **Minimized mode** — collapse to show only the current and next pull; toggle with the `-`/`+` header button or `/mdth min`
- **Manual navigation** — `<` / `>` buttons or `/mdth next` / `/mdth prev` to step through pulls; also bindable via WoW Key Bindings UI
- **Movable & resizable** — drag to reposition when unlocked; drag the bottom edge to resize the scroll area height
- **Lockable** — lock the frame via settings or `/mdth lock` to prevent accidental moving/resizing
- **Scrollable** — mouse wheel scrolls the pull list
- **Share route** — send your MDT route to the group or copy the export string (header `S` button or `/mdth share` / `/mdth copy`)
- **Auto-import** — automatically imports routes shared by the party leader (toggleable in settings)
- **Bundled community routes** — adds one starter route for each current-season dungeon and selects it on entry only when the current preset has no route
- **Settings panel** — `/mdth settings` to adjust opacity, toggle auto-import, lock/unlock the frame, and reset position & size
- **Key completion** — all pulls marked done when the key completes

## Slash Commands

| Command | Description |
|---|---|
| `/mdth` or `/mdth toggle` | Enable / disable the overlay |
| `/mdth lock` | Toggle frame lock (prevent dragging/resizing) |
| `/mdth min` | Toggle minimized mode |
| `/mdth next` | Advance to the next pull |
| `/mdth prev` | Go back to the previous pull |
| `/mdth reset` | Reset all pull progress |
| `/mdth pos` | Reset position and size to defaults |
| `/mdth settings` | Open the settings panel |
| `/mdth share` | Share current route to group |
| `/mdth copy` | Copy route export string |
| `/mdth autoimport` | Toggle auto-import of leader routes |
| `/mdth status` | Print current state to chat |

## Requirements

- **Mythic Dungeon Tools (MDT)** — required dependency; the route data comes from MDT's active preset
- With MDT 6.2+, keep **Mythic Dungeon Tools (MDT) - UI** enabled. It loads on demand when route data is needed.

Sharing, copying, and leader auto-import support modern MDT's `!~MDT2~` format. Older MDT installations retain their legacy sharing/export/import path. Modern map-popout floor buttons are still unavailable; choose the floor in MDT itself.

## Installation

Copy the `MDTHelper` folder into your WoW addons directory:

```
World of Warcraft/_retail_/Interface/AddOns/MDTHelper/
```

Make sure MDT is also installed, then `/reload` or restart the game client.

## Compatibility tests

Run `lua tests/mdt_compat_test.lua` from the repository root. These tests mock WoW APIs and cover modern and legacy route actions, delayed loading, leader checks, import preservation, preset changes, and mob-edit refreshes. Verify sharing a large route between two clients, copying/importing an export, and changing/editing presets in-game before publishing a release.
