# MDTHelper

A World of Warcraft addon that displays your [Mythic Dungeon Tools](https://www.curseforge.com/wow/addons/mythic-dungeon-tools) route as a live checklist during Mythic+ runs.

## What It Does

MDTHelper reads the currently selected MDT route when you enter a dungeon and shows a compact overlay listing every pull in order. As you progress through the key, pulls are automatically marked complete based on enemy forces gained. The current pull is expanded to show each mob type with its portrait, name, clone count, and percentage of total forces.

A forces progress bar at the top tracks your overall enemy forces completion.

## Features

- **Auto-detection** — activates when you enter a Mythic+ dungeon, hides outside instances
- **Auto-advance** — marks pulls complete when ~80% of expected forces are gained; also advances on boss kills
- **Expanded current pull** — the active pull shows detailed mob info with NPC portraits
- **Compact pull list** — other pulls show stacked portraits with clone counts
- **Forces bar** — real-time forces progress shown as count and percentage
- **Manual navigation** — `<` / `>` buttons or `/mdth next` / `/mdth prev` to step through pulls
- **Movable & lockable** — drag to reposition; lock with `/mdth lock`
- **Scrollable** — mouse wheel scrolls the pull list
- **Key completion** — all pulls marked done when the key completes

## Slash Commands

| Command | Description |
|---|---|
| `/mdth` or `/mdth toggle` | Enable / disable the overlay |
| `/mdth lock` | Toggle frame lock (prevent dragging) |
| `/mdth next` | Advance to the next pull |
| `/mdth prev` | Go back to the previous pull |
| `/mdth reset` | Reset all pull progress |
| `/mdth status` | Print current state to chat |

## Requirements

- **Mythic Dungeon Tools (MDT)** — required dependency; the route data comes from MDT's active preset

## Installation

Copy the `MDTHelper` folder into your WoW addons directory:

```
World of Warcraft/_retail_/Interface/AddOns/MDTHelper/
```

Make sure MDT is also installed, then `/reload` or restart the game client.
