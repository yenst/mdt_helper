# Changelog

## v9.3 — 2026-09-03

- Fixed sharing and copying routes with MDT 6.2+, which no longer exposes the global `MDT` table.
- Use MDT's public communication API and current `!~MDT2~` export format; announce chat links after the payload finishes sending, with English dungeon names for cross-language compatibility.
- Restored automatic leader-route import with an independent AceComm subscriber, including multipart routes. Existing routes are preserved as imported copies.
- Fixed cross-realm leader matching and detection of a leader in the final raid slot.
- Restored modern preset-change refreshes and redraw MDT before rebuilding edited pull data.
- Added mocked compatibility regression tests. Modern map-popout floor buttons remain unavailable; select floors in MDT itself.

## v0.2.0 — 2026-02-18

Initial public release.

### Features

- Live pull-by-pull route overlay that reads your active MDT preset
- Auto-advance based on enemy forces progress (triggers at ~80% of expected pull forces)
- Auto-advance on boss kills
- Expanded current pull view with NPC portraits, mob names, clone counts, and forces percentages
- Compact pull rows with stacked portraits for upcoming and completed pulls
- Forces progress bar with count and percentage
- Manual pull navigation via on-screen buttons and chat commands
- Draggable, lockable frame with saved position
- Scrollable pull list
- Automatic show/hide based on dungeon instance detection
- Key completion detection — marks all pulls done when the key ends
- Slash commands: `/mdth toggle`, `lock`, `next`, `prev`, `reset`, `status`
- MDT_Legacy optional dependency support
