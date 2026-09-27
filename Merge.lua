-- Merge: one list of groups and players from the Group Finder and LFG chat posts (Hush_Feed).
-- A leader who is both listed and posting in chat becomes one entry (source "both").
local _, L = ...

local Hush = Hush

-- Chat abbreviations -> dungeon names (a Group Finder name wins when one contains it).
local ABBR = {
    rfc = "Ragefire Chasm", wc = "Wailing Caverns", dm = "Deadmines", vc = "Deadmines", deadmines = "Deadmines",
    sfk = "Shadowfang Keep", bfd = "Blackfathom Deeps", stocks = "The Stockade", stockade = "The Stockade",
    gnomer = "Gnomeregan", rfk = "Razorfen Kraul", sm = "Scarlet Monastery", gy = "Scarlet Monastery",
    lib = "Scarlet Monastery", arm = "Scarlet Monastery", cath = "Scarlet Monastery", rfd = "Razorfen Downs",
    ulda = "Uldaman", uldaman = "Uldaman", zf = "Zul'Farrak", mara = "Maraudon", brd = "Blackrock Depths",
    lbrs = "Lower Blackrock Spire", ubrs = "Upper Blackrock Spire", dme = "Dire Maul", dmw = "Dire Maul",
    dmn = "Dire Maul", strat = "Stratholme", strath = "Stratholme", stratholme = "Stratholme",
    scholo = "Scholomance", scholomance = "Scholomance", rol = "Ruins of Lordaeron", thanes = "Hall of Thanes",
}
local SIZE = 5
local NEED = { tank = 1, healer = 1, dps = 3 } -- a five-player group

-- The Group Finder's own name for a dungeon, if one contains ours.
local function finderName(name)
    local lower = strlower(name)
    for n in pairs(L.activityNames) do
        if strlower(n):find(lower, 1, true) then return n end
    end
    return name
end

-- The dungeon a chat post is about, or nil.
function L.DetectActivity(plain)
    local text = " " .. strlower(plain or ""):gsub("[^%w']+", " ") .. " "
    for n in pairs(L.activityNames) do
        if text:find(" " .. strlower(n):gsub("[^%w']+", " ") .. " ", 1, true) then return n end
    end
    for word in text:gmatch("%S+") do
        if ABBR[word] then return finderName(ABBR[word]) end
    end
    return nil
end

local function leaderOf(listing)
    for _, m in ipairs(listing.members) do
        if m.leader then return m end
    end
    return listing.members[1]
end

local function fromListing(l)
    local leader = leaderOf(l) or {}
    local e = {
        kind = l.numMembers > 1 and "group" or "player",
        source = "finder",
        activity = l.activity,
        leader = l.leader or leader.name or "?",
        leaderClass = leader.class,
        text = (l.comment and l.comment ~= "" and l.comment) or (l.title ~= "" and l.title) or nil,
        members = l.members,
        size = l.numMembers,
        age = (l.age or 0) + (time() - (l.readAt or time())),
        listing = l,
    }
    -- The members' own levels (the Group Finder's minimum level is often 0).
    for _, m in ipairs(l.members) do
        if type(m.level) == "number" and m.level > 0 then
            e.minLevel = min(e.minLevel or m.level, m.level)
            e.maxLevel = max(e.maxLevel or m.level, m.level)
        end
    end
    if e.kind == "group" then
        local have = { tank = 0, healer = 0, dps = 0 }
        for _, m in ipairs(l.members) do
            if m.role then have[m.role] = have[m.role] + 1 end
        end
        e.missing = {}
        if l.numMembers < SIZE then
            for role, n in pairs(NEED) do e.missing[role] = max(0, n - have[role]) end
        end
    else
        e.roles = leader.roles or {}
        if leader.role and not next(e.roles) then e.roles[leader.role] = true end
        e.level = leader.level
        e.area = leader.area
    end
    return e
end

local function fromPost(p)
    local info = p.info or {}
    local e = {
        kind = info.lfType == "lfm" and "group" or "player",
        source = "chat",
        activity = L.DetectActivity(p.plain),
        leader = p.author,
        leaderClass = p.class,
        text = p.text,
        channel = p.channel,
        members = p.class and { { name = p.author, class = p.class, leader = true } } or {},
        age = time() - p.last,
        post = p,
    }
    if e.kind == "group" then
        -- Chat says which roles are wanted, not how many: one open slot per role.
        e.missing = {}
        for role in pairs(info.roles or {}) do e.missing[role] = 1 end
    else
        e.roles = {}
        for role in pairs(info.roles or {}) do e.roles[role] = true end
    end
    return e
end

-- All entries, newest first. Cheap enough to rebuild on every refresh (a few hundred at most).
function L.Build()
    local entries, byLeader = {}, {}
    for _, l in ipairs(L.listings) do
        local e = fromListing(l)
        entries[#entries + 1] = e
        byLeader[strlower(e.leader)] = e
    end
    local feed = Hush.Feed
    if feed then
        for _, p in ipairs(feed.Posts("lfg")) do
            local e = byLeader[strlower(p.author)]
            if e then
                -- Listed and posting: one entry.
                if not e.post then
                    e.source, e.post, e.chat = "both", p, p.text
                    e.age = min(e.age, time() - p.last)
                    e.activity = e.activity or L.DetectActivity(p.plain)
                    if not e.text then e.text = p.text end
                end
            else
                -- Only posts about a dungeon or a role ("LF enchanter" is not a group).
                e = fromPost(p)
                if e.activity or next(e.missing or e.roles) then
                    entries[#entries + 1] = e
                    byLeader[strlower(e.leader)] = e
                end
            end
        end
    end
    local role = feed and feed.GetRole() or "none"
    for _, e in ipairs(entries) do
        e.needsRole = role ~= "none" and e.kind == "group" and (e.missing and (e.missing[role] or 0) > 0) or false
    end
    sort(entries, function(a, b) return a.age < b.age end)
    return entries
end
