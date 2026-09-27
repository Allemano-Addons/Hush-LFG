# Changelog

## 0.1.0 (in progress)

### Step 1 – Skeleton and Group Finder reading
- Module skeleton (`## Dependencies: Hush, Hush_Feed`), `HushLFGDB` for settings (listings live in memory only).
- Reads the Group Finder: activity, leader, comment, members (class, level, role). Every read is guarded; values the client keeps secret count as missing.
- `C_LFGList.Search` is protected on Forever (blocked even from a slash command), so Hush LFG never searches itself: it reads the results of searches made in Blizzard's Group Finder.
- `/hlfg probe` (what the client lets us read, categories, class icons, Group Finder frames), `/hlfg dump`.
