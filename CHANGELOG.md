# Changelog

## 0.1.0 (in progress)

### Step 1 – Skeleton and Group Finder reading
- Module skeleton (`## Dependencies: Hush, Hush_Feed`), `HushLFGDB` for settings (listings live in memory only).
- Reads the Group Finder: activity, leader, comment, members (class, level, role). Every read is guarded; values the client keeps secret count as missing.
- Searches only on a click or command (`/hlfg search [category]`); results from Blizzard's own Group Finder window are read too.
- `/hlfg probe` (what the client lets us read, categories, class icons), `/hlfg dump`.
