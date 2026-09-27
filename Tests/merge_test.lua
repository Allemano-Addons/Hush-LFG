-- Offline test of Merge.lua (not loaded by the game). Run from the Hush_LFG folder:  lua Tests/merge_test.lua
strlower, sort, min, max, time = string.lower, table.sort, math.min, math.max, os.time
local now = time()
local L = { activityNames = { ["Wailing Caverns"] = true, ["Deadmines"] = true, ["Ruins of Lordaeron"] = true } }
Hush = { Feed = {
    GetRole = function() return "healer" end,
    Posts = function()
        return {
            { author = "Teffes Kadaver", class = "DRUID", text = "WC need heals", plain = "wc need heals", last = now - 30, info = { lfType = "lfm", roles = { healer = true } } },
            { author = "Solo Guy", class = "MAGE", text = "dps LFG RFC", plain = "dps lfg rfc", last = now - 90, info = { lfType = "lfg", roles = { dps = true } } },
            { author = "Big Tank", class = "WARRIOR", text = "LFM SFK need tank", plain = "lfm sfk need tank", last = now - 10, info = { lfType = "lfm", roles = { tank = true } } },
            { author = "Craft Seeker", class = "PRIEST", text = "LF ENCHANTER UC", plain = "lf enchanter uc", last = now - 5, info = { lfType = "lfg" } },
        }
    end,
} }
L.listings = {
    { id = 1, leader = "Teffes Kadaver", activity = "Wailing Caverns", numMembers = 4, age = 120, readAt = now, comment = "",
      members = { { name = "Teffes Kadaver", class = "DRUID", role = "dps", leader = true }, { class = "PALADIN", role = "tank" },
                  { class = "SHAMAN", role = "healer" }, { class = "HUNTER", role = "dps" } } },
    { id = 2, leader = "Ure Savior", activity = "Ruins of Lordaeron", numMembers = 1, age = 60, readAt = now,
      members = { { name = "Ure Savior", class = "PRIEST", role = "dps", roles = { healer = true, dps = true }, leader = true, level = 20 } } },
    { id = 3, leader = "Oh Miyu", activity = "Deadmines", numMembers = 2, age = 300, readAt = now,
      members = { { class = "ROGUE", role = "dps", leader = true }, { class = "WARLOCK", role = "dps" } } },
}
assert(loadfile("Merge.lua"))("Hush_LFG", L)

local bad = 0
local function check(ok, msg) if not ok then bad = bad + 1; print("BAD " .. msg) else print("OK  " .. msg) end end
local entries = L.Build()
local by = {}
for _, e in ipairs(entries) do by[e.leader] = e end

check(#entries == 5, "5 entries (Teffes merged), got " .. #entries)
check(by["Teffes Kadaver"].source == "both", "Teffes is in both chat and Finder")
check(by["Teffes Kadaver"].missing.dps == 1 and by["Teffes Kadaver"].missing.healer == 0, "Teffes misses 1 dps, no healer")
check(by["Teffes Kadaver"].needsRole == false, "Teffes does not need a healer")
check(by["Oh Miyu"].missing.tank == 1 and by["Oh Miyu"].missing.healer == 1 and by["Oh Miyu"].missing.dps == 1, "Oh Miyu misses T, H, 1 D")
check(by["Oh Miyu"].needsRole == true, "Oh Miyu needs a healer")
check(by["Ure Savior"].kind == "player" and by["Ure Savior"].roles.healer, "Ure Savior is a player who can heal")
check(by["Solo Guy"].kind == "player" and by["Solo Guy"].activity == "Ragefire Chasm", "Solo Guy: player, Ragefire Chasm")
check(by["Big Tank"].kind == "group" and by["Big Tank"].activity == "Shadowfang Keep" and by["Big Tank"].missing.tank == 1, "Big Tank: SFK group needs a tank")
check(entries[1].leader == "Big Tank", "newest first")
check(L.DetectActivity("lf ruins of lordaeron heal") == "Ruins of Lordaeron", "full Finder names in chat")
check(by["Craft Seeker"] == nil, "a post without dungeon or role is left out")
check(by["Oh Miyu"].minLevel == nil and by["Ure Savior"].minLevel == 20, "levels come from the members")
check(L.DetectActivity("dm run") == "Deadmines", "dm -> the Finder's Deadmines")
print(bad == 0 and "ALL OK" or (bad .. " wrong"))
