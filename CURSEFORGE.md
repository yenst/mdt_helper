# MDTHelper — Live Route Guide for M+

Stop alt-tabbing to check your MDT route mid-key. MDTHelper puts your planned route right on screen as a pull-by-pull checklist that updates automatically as you go.

## How It Works

1. Plan your route in Mythic Dungeon Tools like you normally would.
2. Enter the dungeon. MDTHelper reads your active MDT route and displays it as a compact overlay.
3. Play the key. As your group kills mobs and gains forces, the addon tracks your progress and automatically advances through the pull list.

That's it. No setup required — it just works out of the box.

## What You See On Screen

- **A pull list** showing every pull from your MDT route in order. Each pull displays mob portraits so you can quickly see what you're pulling next.
- **The current pull expanded** with full details: mob names, portraits, how many of each mob, and how much forces each group is worth as a percentage.
- **A forces bar** at the top showing your overall forces progress (e.g. 187/300 — 62%).
- **Completed pulls** get checked off and dimmed so you always know where you are.
- **Minimized mode** — collapse to just the current and next pull when you want a smaller footprint.
- **Compact mode** — keep the current pull collapsed to a highlighted portrait row, including in minimized mode.
- **Map only** — show the dungeon map without the pull list while pull tracking continues in the background.

## Auto-Advance

The addon watches your forces progress during the key. By default, it waits for 100% of a pull's planned forces before marking that pull complete and moving to the next one. Boss pulls also require a boss kill; pulls containing both a boss and trash wait for both. Lower **Pull Accuracy** in settings if you want a margin for skipped mobs. Existing saved accuracy settings are preserved. You can toggle auto-advance on/off with the **A** button in the header.

If the auto-tracking gets out of sync (maybe you pulled extra mobs or skipped something), you can manually step forward or back with the arrow buttons on the overlay, or with chat commands.

Combined pulls carry excess forces forward. Empty and already-completed pulls are skipped, and editing mobs through the map popout immediately rechecks the current pull's progress. Tracking is based on forces gained and cannot identify individual kills made out of route order.

## Route Sharing

- Click the **S** button in the header to send your route to the group (left-click) or copy the export string (right-click).
- **Auto-import** — when your party leader shares an MDT route, it's automatically imported so the whole group stays on the same page. Toggle this in settings.

## Customization

Open the settings panel with **/mdth settings**:

- **Opacity slider** — make the overlay more transparent so it doesn't block your view.
- **Lock / Unlock** — when unlocked, drag the frame to move it and drag the bottom edge to resize the height of the scroll area. Lock it when you're happy with the layout.
- **Auto-import toggle** — enable or disable automatic route imports from your party leader.
- **Compact Mode** — keep the current pull collapsed instead of expanding its mob details.
- **Map Only** — hide the pull list and open the map window. Your preference is saved between sessions.
- **Reset Position & Size** — snap the overlay back to its default location and size.

You can also bind **Next Pull** and **Previous Pull** in WoW's Key Bindings menu (look under "MDT Helper").

## Commands

Type these in chat:

- **/mdth** — show or hide the overlay
- **/mdth lock** — lock the frame in place so you don't accidentally drag or resize it
- **/mdth min** — toggle minimized mode
- **/mdth compact** — toggle compact mode
- **/mdth map** — open or close the map window
- **/mdth maponly** — toggle map-only mode; toggle off to restore the pull list
- **/mdth next** — manually advance to the next pull
- **/mdth prev** — go back one pull
- **/mdth reset** — start the tracker over from pull 1
- **/mdth pos** — reset position and size to defaults
- **/mdth settings** — open the settings panel
- **/mdth share** — send your route to the group
- **/mdth copy** — copy the route export string
- **/mdth autoimport** — toggle auto-import of leader routes
- **/mdth status** — print current state to chat

## Requirements

- [Mythic Dungeon Tools](https://www.curseforge.com/wow/addons/mythic-dungeon-tools) must be installed. MDTHelper reads your route from MDT — without it there's nothing to display.

## Languages

English and Simplified Chinese are included in the same download. Simplified Chinese is selected automatically on `zhCN` clients. The Chinese translation is an initial draft; community corrections are welcome.

## FAQ

**Does it work with any dungeon?**
Yes, any dungeon that MDT supports. Whatever route you have selected in MDT is what gets displayed.

**Does it affect performance?**
No. The overlay is lightweight and only updates when forces change or you switch pulls.

**What if I don't follow the route exactly?**
Auto-advance follows forces gained, so extra off-route kills can count toward the current pull. If you depart from the route, disable auto-advance and use the manual next/prev buttons. To resume automatic tracking, select the pull you are about to start and enable auto-advance; forces tracking starts fresh for that selection.

**Does it do anything outside of dungeons?**
The pull list automatically hides outside dungeon instances. You can open the selected MDT route's map with `/mdth map` or enable map-only mode with `/mdth maponly`.
