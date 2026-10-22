# MDTHelper 9.9

- Added **Map Only** in settings to show the dungeon map without the pull list. The preference is saved between sessions, and pull tracking continues in the background.
- Use `/mdth maponly` to toggle map-only mode. Toggle it off to restore the pull list.
- Use `/mdth map` to open or close the map window.
- Includes Simplified Chinese translations for the new option and messages.

After updating, reload the game UI with `/reload`.

Validation: Lua 5.1 syntax checks and all three regression suites run against the extracted release ZIP. In-game verification of map-only mode is still required.
