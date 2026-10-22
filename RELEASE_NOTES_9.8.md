# MDTHelper 9.8

- Corrected the release package: the published 9.7 download still contained the old code and reported version 9.6 internally.
- Fixed the current pull percentage displaying `xe2x86...` during combat. The planned cumulative percentage now stays visible instead of being replaced by a broken, double-counted prediction.
- Fixed automatic activation in garrisons and repeated zone events reopening a closed map or resetting pull progress.
- Disabling MDTHelper now hides both the route guide and map popout.

After updating, reload the game UI with `/reload`. The addon version is now correctly marked as 9.8.

Validation: Lua 5.1 syntax checks and all three regression suites run against the extracted release ZIP. Live Mythic+ and garrison verification is still required.
