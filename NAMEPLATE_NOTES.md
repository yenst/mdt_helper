# Nameplate Highlighting for Current Pull Mobs

## STATUS: NOT POSSIBLE as of WoW 12.0 (Midnight) — Feb 2026

## The Idea

Listen to `NAME_PLATE_UNIT_ADDED`, extract the NPC ID from `UnitGUID("nameplateN")`, match it against the current MDT pull's NPC IDs, and attach a glow/border to the nameplate frame.

## Why It Doesn't Work

In Patch 12.0, Blizzard introduced the "Secret Value" system. Both `UnitGUID()` and `UnitName()` return **secret values** for nameplate unit tokens (e.g. `"nameplate1"`). You cannot:

- Call `strsplit()`, `tonumber()`, `string.sub()` on them
- Compare them to other strings
- Pass them to any function expecting a normal string

Doing so throws:
```
attempt to perform string conversion on a secret string value (tainted by 'MDTHelper')
```

This is **intentional**. Blizzard explicitly wants to prevent addons from identifying specific NPCs by ID on nameplates, as it reduces the skill requirement for M+ content (learning which mobs are dangerous through practice vs. having an addon color them for you).

The nameplate `UnitFrame.name` fontstring text is also protected and cannot be read via `GetText()` for the same reason.

Combat log GUIDs (`COMBAT_LOG_EVENT_UNFILTERED`) are NOT secret, but there's no way to link them back to nameplate unit tokens since `UnitGUID` is secret — so combat log correlation doesn't work either.

## What Nameplate Addons CAN Still Do in 12.0

- Color by mob **type** (boss, miniboss, caster, melee) — exposed natively by Blizzard's nameplate system
- Visual customization (fonts, textures, bar sizes)
- Threat-based coloring
- Cast bar interruptibility indicators
- These all work because they don't require knowing the specific NPC ID

## Addons That Adapted

- **Platynator** — built from scratch for Midnight constraints
- **Plater** — uses `issecretvalue()` guards to skip secret data gracefully
- **BetterBlizzPlates** — mob-type coloring only

## If Blizzard Relaxes These Restrictions

The implementation approach would be:

1. `NAME_PLATE_UNIT_ADDED` fires with `unitId`
2. Extract NPC ID: `tonumber(select(6, strsplit("-", UnitGUID(unitId))))`
3. Check `H.currentPullNpcIds[npcId]`
4. Attach a child frame with glow texture to the nameplate (never touch Blizzard's existing children to avoid taint)
5. Clean up on `NAME_PLATE_UNIT_REMOVED`

## References

- https://gerritalex.de/blog/nameplates-in-midnight
- https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes
- https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
