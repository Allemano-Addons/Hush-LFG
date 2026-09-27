-- Offline test of Join.lua (not loaded by the game). Run from the Hush_LFG folder:  lua Tests/join_test.lua
strlower, strsplit = string.lower, function(sep, s) return s:match("^([^" .. sep .. "]*)") end
local role = "tank"
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 20 end
Hush = { Feed = { GetRole = function() return role end } }
local L = { db = { joinMessage = "" } }
assert(loadfile("Join.lua"))("Hush_LFG", L)
local bad = 0
local function check(got, want)
    if got ~= want then bad = bad + 1; print("BAD  got: " .. got .. "\n     want: " .. want) else print("OK   " .. got) end
end
check(L.JoinMessage({ activity = "Wailing Caverns", leader = "Kelu Xin" }), "Hi! Tank Warrior lvl 20 here - room for me in Wailing Caverns?")
role = "none"
check(L.JoinMessage({ activity = "Deadmines" }), "Hi! Warrior lvl 20 here - room for me in Deadmines?")
check(L.JoinMessage({}), "Hi! Warrior lvl 20 here - room for me in your group?")
L.db.joinMessage = "Hey {leader}, {role} for {dungeon}?"
role = "healer"
check(L.JoinMessage({ activity = "RFC", leader = "Kelu Xin" }), "Hey Kelu, Healer for RFC?")
role = "none"
check(L.JoinMessage({ activity = "RFC", leader = "Kelu Xin" }), "Hey Kelu, for RFC?")
check(L.ActionLabel({ kind = "player" }), "Invite")
check(L.ActionLabel({ kind = "group", listing = {} }), "Request invite")
check(L.ActionLabel({ kind = "group" }), "Ask to join")
print(bad == 0 and "ALL OK" or (bad .. " wrong"))
