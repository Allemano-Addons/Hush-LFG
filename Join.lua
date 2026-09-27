-- Join: the action button on each row and the "Ask to join" whisper.
--   Players:      Invite (a group invite).
--   Listed groups: Request invite (like the Group Finder's own button).
--   Chat groups:  Ask to join (opens Hush with a ready whisper to edit and send - never sent by itself).
local _, L = ...

local Hush = Hush

L.DEFAULT_JOIN = "Hi! {role} {class} lvl {level} here - room for me in {dungeon}?"
local ROLE_NAME = { tank = "Tank", healer = "Healer", dps = "DPS" }

-- The join whisper for an entry, from the template in the settings.
function L.JoinMessage(e)
    local role = Hush.Feed and Hush.Feed.GetRole() or "none"
    local values = {
        role = ROLE_NAME[role] or "",
        class = (UnitClass("player")) or "",
        level = tostring(UnitLevel("player") or ""),
        dungeon = e and e.activity or "your group",
        leader = e and e.leader and (strsplit(" ", e.leader)) or "",
    }
    local text = (L.db and L.db.joinMessage ~= "" and L.db.joinMessage) or L.DEFAULT_JOIN
    text = text:gsub("{(%a+)}", function(key) return values[strlower(key)] end)
    -- A missing value (no role chosen) must not leave double spaces behind.
    text = text:gsub("  +", " "):gsub("^ ", ""):gsub(" ([,.!?])", "%1")
    return text
end

function L.ActionLabel(e)
    if e.kind == "player" then return "Invite" end
    if e.listing then return "Request invite" end
    return "Ask to join"
end

function L.Act(e)
    if e.kind == "player" then
        Hush.InviteToGroup(e.leader)
        L.Print("Invited " .. e.leader .. ".")
    elseif e.listing and Hush.RequestInvite and Hush.RequestInvite(e.leader) then
        L.Print("Asked " .. e.leader .. " for an invite.")
    else
        Hush.OpenWhisper(e.leader, L.JoinMessage(e))
    end
end
