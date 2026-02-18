# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MDTHelper is a World of Warcraft addon (retail) written in Lua. It likely extends or integrates with [Mythic Dungeon Tools (MDT)](https://www.curseforge.com/wow/addons/mythic-dungeon-tools), a popular addon for planning Mythic+ dungeon routes.

## No Build Step

WoW addons are loaded directly by the game client — there is no compilation, bundling, or build tooling. To "deploy", copy the addon folder into `Interface/AddOns/` (already done here) and reload the game UI (`/reload` in-game).

## WoW Addon Structure

A minimal addon requires:
- `MDTHelper.toc` — Table of Contents: metadata (addon name, WoW interface version, author) and the ordered list of Lua files to load.
- One or more `.lua` files — the addon logic.
- Optional `libs/` — embedded libraries (e.g., Ace3 via LibStub).

### TOC Interface Version

The `## Interface:` line in the `.toc` must match the current WoW client version. Check the running client version via `/run print(select(4, GetBuildInfo()))`.

## Lua & WoW API Conventions

- Addons are sandboxed; global state is shared across all addons. Namespace all globals under a single table: `MDTHelper = MDTHelper or {}`.
- Event-driven: register events on a Frame with `frame:RegisterEvent("EVENT_NAME")` and handle them in `frame:SetScript("OnEvent", handler)`.
- Slash commands are registered via `SlashCmdList["MDTHELPER"] = handler; SLASH_MDTHELPER1 = "/mdthelper"`.
- MDT exposes a global API table; check `MDT` or `MythicDungeonTools` globals to interact with it.
