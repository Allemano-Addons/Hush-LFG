-- Finder: reads the Group Finder (C_LFGList). A search only runs on a click or a slash
-- command (the game wants a real key press/click); results that Blizzard's own Group Finder
-- window receives are read too. Some values may be "secret" on this client: every read is
-- guarded, and secret values count as missing.
local _, L = ...

local Finder = {}
L.Finder = Finder
L.listings = {}          -- the latest results, in the Group Finder's order
Finder.updated = nil     -- time() of the latest results
Finder.secret = {}       -- field name -> true when it was secret (for /hlfg probe)

local C = C_LFGList
local isSecret = issecretvalue or function() return false end

-- Safe field read: nil when the table or the value is secret or missing.
local function get(t, key)
    if t == nil then return nil end
    local ok, v = pcall(function() return t[key] end)
    if not ok or isSecret(v) then
        Finder.secret[key] = true
        return nil
    end
    return v
end

local function call(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- ---------------------------------------------------------------------------
-- Reading results
-- ---------------------------------------------------------------------------

local activityCache = {}
L.activityNames = {}     -- every activity name seen, for finding dungeons in chat posts

-- "TANK" / "HEALER" / "DAMAGER" -> "tank" / "healer" / "dps"; "NONE" -> nil.
function L.NormRole(r)
    if type(r) ~= "string" then return nil end
    r = strlower(r)
    if r:find("tank") then return "tank" end
    if r:find("heal") then return "healer" end
    if r:find("dam") or r:find("dps") then return "dps" end
    return nil
end

-- lfgRoles as { tank = true, ... } (it can be a set or a list).
function L.RoleSet(t)
    local set = {}
    if type(t) ~= "table" then return set end
    pcall(function()
        for k, v in pairs(t) do
            local role = (v == true and L.NormRole(k)) or L.NormRole(v)
            if role then set[role] = true end
        end
    end)
    return set
end

local function activity(id)
    if not id then return nil end
    if activityCache[id] == nil then
        local a = call(C.GetActivityInfoTable, id)
        activityCache[id] = type(a) == "table" and {
            name = get(a, "fullName") or get(a, "shortName"),
            minLevel = get(a, "minLevel"),
            maxLevel = get(a, "maxLevel") or get(a, "maxLevelSuggestion"),
        } or false
        if activityCache[id] and type(activityCache[id].name) == "string" then
            L.activityNames[activityCache[id].name] = true
        end
    end
    return activityCache[id] or nil
end

local function readListing(id)
    local info = call(C.GetSearchResultInfo, id)
    if type(info) ~= "table" then return nil end
    local l = {
        id = id,
        leader = get(info, "leaderName"),
        title = get(info, "name"),
        comment = get(info, "comment"),
        numMembers = get(info, "numMembers") or 0,
        age = get(info, "age"),
        delisted = get(info, "isDelisted"),
        members = {},
    }
    local aid = get(info, "activityID")
    if not aid then
        local ids = get(info, "activityIDs")
        if type(ids) == "table" then aid = get(ids, 1) end
    end
    l.activityID = aid
    local a = activity(aid)
    if a then l.activity, l.minLevel, l.maxLevel = a.name, a.minLevel, a.maxLevel end

    -- Members (the classic Group Finder has one entry per player).
    for i = 1, l.numMembers do
        local p = call(C.GetSearchResultPlayerInfo, id, i)
        if type(p) == "table" then
            l.members[#l.members + 1] = {
                name = get(p, "name"),
                class = get(p, "classFilename"),
                level = get(p, "level"),
                role = L.NormRole(get(p, "assignedRole")),
                roles = L.RoleSet(get(p, "lfgRoles")), -- the roles a player signed up for
                leader = get(p, "isLeader"),
                area = get(p, "areaName"),
            }
        end
    end
    l.readAt = time()
    return l
end

local function readAll()
    local a, b = call(C.GetSearchResults)
    local ids = type(a) == "table" and a or (type(b) == "table" and b) or {}
    wipe(L.listings)
    for _, id in ipairs(ids) do
        if not isSecret(id) then
            local l = readListing(id)
            if l and not l.delisted then L.listings[#L.listings + 1] = l end
        end
    end
    Finder.updated = time()
    if L.OnFinderUpdate then L.OnFinderUpdate() end
end

local function readOne(id)
    for i, old in ipairs(L.listings) do
        if old.id == id then
            local l = readListing(id)
            if l and not l.delisted then L.listings[i] = l else tremove(L.listings, i) end
            if L.OnFinderUpdate then L.OnFinderUpdate() end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Searching
-- ---------------------------------------------------------------------------

local function categories()
    local list = {}
    local ids = call(C.GetAvailableCategories)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local info = call(C.GetLfgCategoryInfo, id)
        list[#list + 1] = { id = id, name = type(info) == "table" and get(info, "name") or "?" }
    end
    return list
end

-- C_LFGList.Search is protected on Forever (an addon call is blocked, even from a slash
-- command). Searches come from Blizzard's own Group Finder; we only read the results.
function Finder.Search()
    L.Print("Addons may not search the Group Finder themselves. Search in the Group Finder (I) - Hush LFG reads the results.")
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            readAll()
        elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
            readOne(...)
        elseif event == "LFG_LIST_SEARCH_FAILED" then
            L.Print("The Group Finder search failed (" .. tostring((...)) .. ").")
        end
    end, ...)
    if not ok then geterrorhandler()(err) end
end)

function Finder.Init()
    if not C then return end
    for _, e in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED" }) do
        pcall(events.RegisterEvent, events, e)
    end
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and call(C_Texture.GetAtlasInfo, name) ~= nil
end

function Finder.Probe()
    if not C then L.Print("C_LFGList is missing.") return end
    L.Print("style:", tostring(call(C.GetPremadeGroupFinderStyle)), "enabled:", tostring(call(C.IsPremadeGroupFinderEnabled)),
        "secret values:", issecretvalue and "yes" or "no")
    local cats = {}
    for _, c in ipairs(categories()) do cats[#cats + 1] = c.id .. "=" .. tostring(c.name) end
    L.Print("categories:", #cats > 0 and table.concat(cats, ", ") or "none")
    L.Print("class icons: atlas classicon-warrior", tostring(atlasExists("classicon-warrior")),
        "· groupfinder-icon-class-warrior", tostring(atlasExists("groupfinder-icon-class-warrior")),
        "· CLASS_ICON_TCOORDS", tostring(CLASS_ICON_TCOORDS ~= nil))
    -- Blizzard's Group Finder windows and search buttons (for a Refresh button of our own).
    local function path(root, ...)
        local f = _G[root]
        for i = 1, select("#", ...) do
            if type(f) ~= "table" then return false end
            f = f[select(i, ...)]
        end
        return type(f) == "table"
    end
    local found = {}
    for _, check in ipairs({
        { "LFGListFrame" }, { "LFGListFrame", "SearchPanel", "RefreshButton" }, { "LFGListFrame", "SearchPanel", "SearchBox" },
        { "PVEFrame" }, { "LFGBrowseFrame" }, { "LFGBrowseFrame", "RefreshButton" }, { "LFGBrowseFrameRefreshButton" },
        { "LFGParentFrame" }, { "LFGListingFrame" },
    }) do
        if path(unpack(check)) then found[#found + 1] = table.concat(check, ".") end
    end
    L.Print("frames:", #found > 0 and table.concat(found, ", ") or "none loaded (open the Group Finder once, then probe again)")
    -- What the browse frame knows before and after you open it (why Refresh needs a first search).
    local browse = _G.LFGBrowseFrame
    if type(browse) == "table" then
        local fields = {}
        pcall(function()
            for k, v in pairs(browse) do
                local lk = type(k) == "string" and strlower(k) or ""
                if lk:find("categ") or lk:find("activ") or lk:find("search") or lk:find("filter") or lk:find("drop") then
                    local desc = type(v)
                    if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
                        desc = tostring(v)
                    elseif type(v) == "table" then
                        local sel = v.selectedValue or v.value or v.selectedValues
                        if sel ~= nil then desc = "table(" .. (type(sel) == "table" and ("#" .. #sel) or tostring(sel)) .. ")" end
                    end
                    fields[#fields + 1] = k .. "=" .. desc
                end
            end
        end)
        sort(fields)
        L.Print("browse:", #fields > 0 and table.concat(fields, " ") or "nothing", "· shown once:", tostring(browse:IsShown() or browse.hasShown or false))
    end
    local buttons = {}
    for _, n in ipairs({ "LFGMicroButton", "LFGParentFrameTab1", "LFGParentFrameTab2", "ToggleLFGParentFrame", "LFGParentFrame_Toggle" }) do
        if _G[n] then buttons[#buttons + 1] = n end
    end
    L.Print("toggles:", #buttons > 0 and table.concat(buttons, ", ") or "none")
    L.Print("results:", #L.listings, Finder.updated and ("(" .. (time() - Finder.updated) .. " s ago)") or "(none yet - search in the Group Finder)")
    local first = L.listings[1]
    if first then
        local info = call(C.GetSearchResultInfo, first.id)
        local keys = {}
        if type(info) == "table" then
            pcall(function() for k, v in pairs(info) do keys[#keys + 1] = k .. ":" .. (isSecret(v) and "SECRET" or type(v)) end end)
        end
        sort(keys)
        L.Print("result fields:", #keys > 0 and table.concat(keys, " ") or "none readable")
        local p = call(C.GetSearchResultPlayerInfo, first.id, 1)
        keys = {}
        if type(p) == "table" then
            pcall(function() for k, v in pairs(p) do keys[#keys + 1] = k .. ":" .. (isSecret(v) and "SECRET" or type(v)) end end)
        end
        sort(keys)
        L.Print("player fields:", #keys > 0 and table.concat(keys, " ") or "none readable")
    end
    local secret = {}
    for k in pairs(Finder.secret) do secret[#secret + 1] = k end
    L.Print("secret fields seen:", #secret > 0 and table.concat(secret, ", ") or "none")
end

local function describe(l)
    local members = {}
    for _, m in ipairs(l.members) do
        members[#members + 1] = ("%s %s%s"):format(tostring(m.class or "?"), tostring(m.level or "?"),
            m.role and m.role ~= "NONE" and ("/" .. m.role) or "")
    end
    return ("[%s] %s (%d) %s%s"):format(l.activity or "?", l.leader or "?", l.numMembers,
        table.concat(members, ", "), l.comment and l.comment ~= "" and (" - " .. l.comment) or "")
end

function Finder.Dump()
    if #L.listings == 0 then L.Print("No results yet. Search in the Group Finder first.") return end
    L.Print(#L.listings, "listings:")
    for i, l in ipairs(L.listings) do
        if i > 25 then L.Print("...", #L.listings - 25, "more") break end
        L.Print("  " .. describe(l))
    end
end
