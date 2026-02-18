# MDTHelper — Live Route Guide for M+

Stop alt-tabbing to check your MDT route mid-key. MDTHelper puts your planned route right on screen as a pull-by-pull checklist that updates automatically as you go.

## How It Works

1. Plan your route in Mythic Dungeon Tools like you normally would.
2. Enter the dungeon. MDTHelper reads your active MDT route and displays it as a compact overlay.
3. Play the key. As your group kills mobs and gains forces, the addon tracks your progress and automatically advances through the pull list.

That's it. No setup, no configuration, no keybinds to learn.

## What You See On Screen

- **A pull list** showing every pull from your MDT route in order. Each pull displays mob portraits so you can quickly see what you're pulling next.
- **The current pull expanded** with full details: mob names, portraits, how many of each mob, and how much forces each group is worth as a percentage.
- **A forces bar** at the top showing your overall forces progress (e.g. 187/300 — 62%).
- **Completed pulls** get checked off and dimmed so you always know where you are.

## Auto-Advance

The addon watches your forces progress during the key. When you've killed enough mobs to match a pull, it automatically marks that pull complete and moves to the next one. Boss kills also advance the tracker. You never have to touch anything during the run.

If the auto-tracking gets out of sync (maybe you pulled extra mobs or skipped something), you can manually step forward or back with the arrow buttons on the overlay, or with chat commands.

## Commands

Type these in chat:

- **/mdth** — show or hide the overlay
- **/mdth lock** — lock the frame in place so you don't accidentally drag it
- **/mdth next** — manually advance to the next pull
- **/mdth prev** — go back one pull
- **/mdth reset** — start the tracker over from pull 1

## Moving the Overlay

Just click and drag it wherever you want. Use **/mdth lock** when you're happy with the position so it stays put.

## Requirements

- [Mythic Dungeon Tools](https://www.curseforge.com/wow/addons/mythic-dungeon-tools) must be installed. MDTHelper reads your route from MDT — without it there's nothing to display.

## FAQ

**Does it work with any dungeon?**
Yes, any dungeon that MDT supports. Whatever route you have selected in MDT is what gets displayed.

**Does it affect performance?**
No. The overlay is lightweight and only updates when forces change or you switch pulls.

**What if I don't follow the route exactly?**
The auto-advance is based on forces gained, not which specific mobs you kill. It handles small deviations fine. For bigger differences, use the manual next/prev buttons to get back on track.

**Does it do anything outside of dungeons?**
No. The overlay automatically hides when you're not in a dungeon instance.
