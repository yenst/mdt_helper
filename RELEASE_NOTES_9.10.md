# MDTHelper 9.10

- Updated for WoW patch 12.1.5 (interface 120105) and MDT 6.3.x.
- On 12.1.5, the enemy forces tooltip line is now left to Blizzard's built-in display, so it no longer appears twice. MDTHelper no longer modifies unit tooltips on this patch.
- Hardened the tooltip hook on older clients so it only touches the standard game tooltip and cannot error on other addons' tooltips.

After updating, reload the game UI with `/reload`.

Tip: if only the map shows and the pull list is missing, Map Only mode is on. Toggle it off with `/mdth maponly` or in the settings panel.

Validation: Lua 5.1 syntax checks and all three regression suites run against the extracted release ZIP. Verified in-game on 12.1.5 with MDT 6.3.6.
