# Changelog

## 0.1.0 (in progress)

### Step 1 – Skeleton and Group Finder reading
- Module skeleton (`## Dependencies: Hush, Hush_Feed`), `HushLFGDB` for settings (listings live in memory only).
- Reads the Group Finder: activity, leader, comment, members (class, level, role). Every read is guarded; values the client keeps secret count as missing.
- `C_LFGList.Search` is protected on Forever (blocked even from a slash command), so Hush LFG never searches itself: it reads the results of searches made in Blizzard's Group Finder.
- `/hlfg probe` (what the client lets us read, categories, class icons, Group Finder frames), `/hlfg dump`.
- Roles are read as tank / healer / dps, including the roles a solo player signed up for.

### Step 2 – Window
- The Hush LFG window from the mockup (`/hlfg`, the person button in the Hush title row, or the launcher menu): GROUPS / PLAYERS tabs with counts, search (dungeon, leader, comment), My role (shared with Hush Feed), Refresh Finder.
- One list from both sources: Group Finder listings and LFG posts from Hush Feed. A leader who is listed and also posts in chat becomes one row ("Chat + Finder").
- Rows: dungeon, source, "Needs your role", leader (class color) and comment, level · size · age; the members' real class icons and open role slots (T / H / D, your role in the accent color; a five-player group needs 1 tank, 1 healer, 3 dps). Players show the roles they can play. Hover an icon for name, level and role.
- Dungeons in chat posts are found by the Group Finder's own names and by abbreviations (rfc, wc, dm, sfk, bfd, ubrs, strat, scholo...).
- Refresh Finder clicks Blizzard's refresh button with a secure /click (addons may not search themselves). Out of combat; the Group Finder must have been opened once.
- Whisper (opens Hush) on every row, Invite on players.
- `Tests/merge_test.lua`: offline test of the merging (not loaded by the game).
