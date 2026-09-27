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
- From the first window test: chat posts are only listed when they name a dungeon or a role ("LF enchanter" is not a group; Hush Feed now sorts crafter requests as Services). Levels are the members' own levels (the Group Finder's minimum is often 0); a player shows their level.

### Step 3 – Filters
- Sidebar filters, saved between sessions: Dungeon / Raid (the dungeons in the list), Level (any, within 2 or 5 of your level), Source (Chat + Finder, Chat only, Finder only), Role (groups that need it / players who play it) and classes to hide (the real class icons; a group with any member of a hidden class is hidden, as is a player of that class). Reset filters.
- The tab counts follow the filters; the footer says how many are hidden by filters.
- `/hlfg probe` also shows what Blizzard's browse frame knows (to make Refresh Finder work without a first search in the Group Finder).
- Refresh Finder knows when Blizzard's Group Finder is ready (you searched there once this session) and says so until then ("Search once in the Group Finder (I)"), instead of clicking a button that cannot search. It never sets Blizzard's choices itself (that would get the searches blocked). A "No answer" notice after 6 s.
- `/hlfg probe` also looks for a micro button or slash command that opens the Group Finder.
- Listings for several dungeons ("5 activities") are read with all their dungeons: the dungeon filter and search match any of them, the row shows the dungeon you filter on plus "+4" (hover for the list).
- Until the Group Finder is ready, Refresh Finder opens it for you (a secure click on its micro button, `LFDMicroButton`) and tries a refresh right away.
- Refresh Finder also switches the Group Finder to its search tab (the micro button opens the "list yourself" tab).
- Refresh Finder re-arms a moment after the Group Finder opens or closes, so the rest of its own click (search tab, refresh) is not cut short.
