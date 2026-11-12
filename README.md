# MDTHelper

A World of Warcraft addon that displays your [Mythic Dungeon Tools](https://www.curseforge.com/wow/addons/mythic-dungeon-tools) route as a live checklist during Mythic+ runs.

## What It Does

MDTHelper reads the currently selected MDT route when you enter a dungeon and shows a compact overlay listing every pull in order. As you progress through the key, pulls are automatically marked complete based on enemy forces gained. The current pull is expanded to show each mob type with its portrait, name, clone count, and percentage of total forces.

A forces progress bar at the top tracks your overall enemy forces completion.

## Features

- **Auto-detection** — activates only when you enter a Mythic or Mythic+ dungeon, hides in Normal, Heroic, Timewalking, Follower and other instances. Enable **Show in Non-Mythic Dungeons** in settings to use it there too.
- **Load by role** — choose whether the addon appears for **Tank**, **Healer**, and **DPS** in settings. Uses your assigned group role, falling back to your specialization's role when none is assigned.
- **Auto-advance** — defaults to 100% of each pull's expected forces; boss pulls also require a boss kill. Adjust **Pull Accuracy** for a margin of error, or disable auto-advance via the header button or settings when going off route and navigate manually. Existing saved accuracy settings are preserved.
- **Expanded current pull** — the active pull shows detailed mob info with NPC portraits
- **Compact mode** — keep the current pull collapsed to a highlighted portrait row via **Compact Mode** in settings or `/mdth compact`; also works in minimized mode
- **Map only** — show the map without the pull list via **Map Only** in settings or `/mdth maponly`. The preference is saved and pull tracking continues in the background. Toggle it off to restore the pull list; `/mdth map` opens or closes the map window.
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
- **Import Bundled Routes** — use `/mdth settings` to restore missing bundled routes after deleting them or resetting MDT; existing routes and your current selection are preserved
- **Settings panel** — `/mdth settings` to adjust opacity, toggle auto-import, lock/unlock the frame, and reset position & size
- **Key completion** — all pulls marked done when the key completes
- **Simplified Chinese** — addon controls, tooltips, and messages automatically use a `zhCN` translation on Simplified Chinese clients, with English fallback for other clients

Auto-advance carries excess forces across combined pulls, skips empty and already-completed pulls, and rechecks progress after editing mobs through the map popout. Tracking uses total forces, so it cannot identify which individual mobs died or reliably reconstruct kills made out of route order.

## Slash Commands

| Command | Description |
|---|---|
| `/mdth` or `/mdth toggle` | Enable / disable the overlay |
| `/mdth lock` | Toggle frame lock (prevent dragging/resizing) |
| `/mdth min` | Toggle minimized mode |
| `/mdth compact` | Keep the current pull collapsed / restore mob details |
| `/mdth next` | Advance to the next pull |
| `/mdth prev` | Go back to the previous pull |
| `/mdth reset` | Reset all pull progress |
| `/mdth pos` | Reset position and size to defaults |
| `/mdth settings` | Open the settings panel |
| `/mdth map` | Open / close the map window |
| `/mdth maponly` | Toggle map-only mode (hide / restore the pull list) |
| `/mdth share` | Share current route to group |
| `/mdth copy` | Copy route export string |
| `/mdth autoimport` | Toggle auto-import of leader routes |
| `/mdth status` | Print current state to chat |

## Requirements

- **Mythic Dungeon Tools (MDT)** — required dependency; the route data comes from MDT's active preset
- With MDT 6.2+, keep **Mythic Dungeon Tools (MDT) - UI** enabled. It loads on demand when route data is needed.

Sharing, copying, and leader auto-import support modern MDT's `!~MDT2~` format. Older MDT installations retain their legacy sharing/export/import path. Modern map-popout floor buttons are still unavailable; choose the floor in MDT itself.

Bundled routes are added alongside existing presets once MDT's route data loads. The empty-preset check controls automatic selection, not importing. Automatic seeding runs once per bundled route; to restore deleted seeds or recover after resetting MDT, click **Import Bundled Routes** in MDTHelper settings. The button refreshes MDT's route list and reports imported, already-present, and unavailable routes. Bundled dungeons from previous expansions may require MDT Legacy.

## Installation

Copy the `MDTHelper` folder into your WoW addons directory:

```
World of Warcraft/_retail_/Interface/AddOns/MDTHelper/
```

Make sure MDT is also installed, then `/reload` or restart the game client.

## Compatibility tests

Run `lua5.1 tests/mdt_compat_test.lua`, `lua5.1 tests/auto_advance_test.lua`, and `lua5.1 tests/ui_locale_test.lua` from the repository root. These tests mock WoW APIs and cover modern and legacy route actions, delayed loading, leader checks, import preservation, preset changes, mob-edit refreshes, forces tracking, boss/trash completion, manual navigation, compact layouts, locale fallback, combat percentage labels, garrison exclusion, and preserving map visibility and progress across repeated zone events. Verify sharing a large route between two clients, copying/importing an export, changing/editing presets, and auto-advancing through trash and boss pulls in-game before publishing a release. Check compact mode, Chinese text rendering, the planned pull percentage during combat, and hearthing to/flying out of a garrison in-game as well; mocked frames do not measure glyph widths or reproduce live zone transitions.

## Release packaging

Update `## Version:` in `MDTHelper/MDTHelper.toc`, then run `python3 scripts/package_release.py`. It builds `MDTHelper.<version>.zip` from this repository's addon folder and runs the Lua 5.1 checks against the extracted archive before saving the release. Upload that exact ZIP; packaging from an installed game folder can ship stale code. Existing release archives are never overwritten.

## Translation review

`MDTHelper/Locales.lua` contains the initial Simplified Chinese draft. To contribute corrections, edit the Chinese values and keep the English keys, format placeholders, and color codes intact. Enemy and dungeon names come from MDT's data; community route titles retain their original names. The same addon download supports both languages; no separate Chinese version is needed.
