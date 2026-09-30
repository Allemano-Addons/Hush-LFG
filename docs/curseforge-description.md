# Hush LFG

**Every group and every player looking for one, in one list.** Hush LFG is a module for [Hush](https://www.curseforge.com/wow/addons/hush) on WoW Forever. It combines the listings from Blizzard's Group Finder with the LFG posts from chat (through Hush Feed), so you no longer have to check both.

> **Alpha.** Requires Hush and Hush Feed.

## What it does

### One list from two sources
- Groups listed in the Group Finder: dungeon, leader, comment, members with their real class icons, level and roles.
- LFG posts from General, Trade and LookingForGroup, read by Hush Feed.

A leader who is both listed and posting in chat becomes **one row** ("Chat + Finder"). Two tabs, **GROUPS** and **PLAYERS**, show groups looking for members and players looking for a group.

### See at a glance what you can join
Each group row shows the open roles (T / H / D, with your role highlighted), level, size and how old the listing is. **"Needs your role"** marks the groups that want what you play. Hover a class icon for the member's name, level and role.

### Filters that stay
Filter by dungeon or raid, level (within 2 or 5 levels of yours), source (chat, Finder or both), role, and hide classes you do not want in your group. Search by dungeon, leader or comment. Your filters are saved between sessions.

### Join without typing
- **Invite** for players looking for a group.
- **Request invite** for groups in the Group Finder (the same as its own button).
- **Ask to join** for groups from chat: Hush opens with a ready whisper such as *"Hi! Tank Warrior lvl 20 here - room for me in Wailing Caverns?"* You edit it and send it; Hush LFG never sends anything by itself. The template is yours to change in the settings.

### Fits into Blizzard's Group Finder
- A **Hush tab** in Blizzard's Group Finder window opens Hush LFG.
- **Refresh Finder** opens the Group Finder for you and refreshes it, so the list stays current.
- When you search in the Group Finder, Hush LFG can open for you (never in combat; `/hlfg auto` turns it on or off).

*Good to know:* On WoW Forever an addon may not run a Group Finder search itself, so Hush LFG shows the results of searches you make in Blizzard's Group Finder. Search once per session and Refresh Finder keeps it going after that.

## Settings
`/hlfg options` or the gear in the window: when to open with the Group Finder, the Group Finder tab, the join whisper with a live preview, and reset filters.

## Commands
`/hlfg` (or `/hushlfg`) opens the window, `/hlfg options`, `/hlfg auto`.

## Installing manually (WoW Forever)
Requires **Hush** and **Hush Feed**. Made for WoW Forever (interface 16001). If the CurseForge app does not install it into the right folder, download the file from the **Files** tab and unzip it so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\Hush_LFG`, next to the Hush folders. Restart the game.

Part of **Allemano Addons**. Source code and issues: https://github.com/Allemano-Addons/Hush-LFG
