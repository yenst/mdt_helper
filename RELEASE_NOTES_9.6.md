# MDTHelper 9.6

- Added **Compact Mode**: keep the current pull collapsed to a highlighted portrait row. Enable it in settings or with `/mdth compact`. Also works in minimized mode.
- Fixed auto-advance getting stuck on empty or already-completed pulls.
- Editing mobs through the map popout now rechecks whether the current pull has enough forces to advance.
- Verified combined-pull tracking and carrying excess forces into subsequent pulls.
- Added an initial **Simplified Chinese** translation for settings, tooltips, and addon messages. It activates automatically on `zhCN` clients; no separate download is needed. Translation feedback is welcome.

Auto-advance still uses enemy forces gained, so it cannot identify individual kills made out of route order. If you depart from the route, disable auto-advance and navigate manually.
