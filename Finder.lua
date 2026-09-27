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
    -- A listing can be for several dungeons ("5 activities"): keep them all.
    local ids = {}
    local one = get(info, "activityID")
    if one then ids[1] = one end
    local list = get(info, "activityIDs")
    if type(list) == "table" then
        pcall(function()
            for _, aid in ipairs(list) do
                if not isSecret(aid) and aid ~= one then ids[#ids + 1] = aid end
            end
        end)
    end
    l.activities = {}
    for _, aid in ipairs(ids) do
        local a = activity(aid)
        if a and a.name then l.activities[#l.activities + 1] = a.name end
    end
    l.activity = l.activities[1]

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

-- Can Blizzard's refresh button search? Only after the Group Finder has chosen what to search
-- for (you searched there once this session). Read only: writing Blizzard's choices from an
-- addon would taint them and get every later search blocked.
function Finder.Ready()
    if Finder.updated then return true end
    local n = 0
    pcall(function()
        local dd = _G.LFGBrowseFrame.ActivityDropdown
        local sel = dd.selectedValue or dd.value or dd.selectedValues
        if type(sel) == "table" then
            for _ in pairs(sel) do n = n + 1 end
        elseif sel ~= nil then
            n = 1
        end
    end)
    return n > 0
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
            if L.HookGroupFinder then L.HookGroupFinder() end
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
    if L.HookGroupFinder then L.HookGroupFinder() end
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
    -- A safe way to open the Group Finder from a macro: a micro button or a slash command.
    pcall(function()
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("MicroButton$") and type(v) == "table" then
                local lk = strlower(k)
                if lk:find("lfg") or lk:find("group") or lk:find("lfd") or lk:find("finder") then buttons[#buttons + 1] = k end
            elseif type(k) == "string" and k:find("^SLASH_") and type(v) == "string" then
                local lv = strlower(v)
                if lv:find("lfg") or lv:find("group") or lv:find("lfd") or lv:find("finder") then buttons[#buttons + 1] = v end
            end
        end
    end)
    L.Print("toggles:", #buttons > 0 and table.concat(buttons, ", ") or "none", "· ready:", tostring(Finder.Ready()))
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

-- /hlfg frames: the buttons in Blizzard's Group Finder window (to find its search tab).
function Finder.Frames()
    local root = _G.LFGParentFrame
    if not root then L.Print("The Group Finder is not loaded - open it once (I).") return end
    local function label(f, parent)
        local n = f.GetName and f:GetName()
        if n then return n end
        if parent then
            for k, v in pairs(parent) do
                if v == f and type(k) == "string" then return "." .. k end
            end
        end
        return "?"
    end
    local out = {}
    local function walk(f, depth, prefix)
        if depth > 3 or not f.GetChildren then return end
        for _, c in ipairs({ f:GetChildren() }) do
            local name = prefix .. label(c, f)
            local kind = c.GetObjectType and c:GetObjectType() or "?"
            if kind == "Button" or kind == "CheckButton" then
                out[#out + 1] = name .. (c:IsShown() and "" or "(hidden)")
            end
            walk(c, depth + 1, name .. ">")
        end
    end
    walk(root, 1, "")
    L.Print(#out, "buttons in the Group Finder:")
    for i = 1, #out, 6 do
        L.Print("  " .. table.concat(out, ", ", i, min(i + 5, #out)))
    end

    -- The tabs: their text, and which one is selected (open the search tab before running this).
    local tabs = {}
    for i = 1, 6 do
        local t = _G["LFGParentFrameTab" .. i]
        if t then tabs[#tabs + 1] = i .. "=" .. tostring(t.GetText and t:GetText() or "?") end
    end
    L.Print("tabs:", table.concat(tabs, ", "), "· selected:", tostring(root.selectedTab),
        "· shown panels:", (_G.LFGListingFrame and _G.LFGListingFrame:IsShown() and "Listing " or "")
        .. (_G.LFGBrowseFrame and _G.LFGBrowseFrame:IsShown() and "Browse " or "")
        .. (_G.LFGWhoListFrame and _G.LFGWhoListFrame:IsShown() and "Who" or ""))

    -- Shown buttons elsewhere with Tab / LFG / Group in the name (the side buttons).
    local side = {}
    pcall(function()
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType and (k:find("Tab") or k:find("Side"))
                and (k:find("LFG") or k:find("Group") or k:find("Finder")) and not k:find("^LFGParentFrameTab") then
                local ok, kind = pcall(v.GetObjectType, v)
                if ok and (kind == "Button" or kind == "CheckButton") then
                    side[#side + 1] = k .. (v:IsShown() and "" or "(hidden)")
                end
            end
        end
    end)
    sort(side)
    L.Print("other tabs:", #side > 0 and table.concat(side, ", ") or "none")
end

-- /hlfg side: every shown frame attached to the Group Finder window that is not one of its
-- known panels (to find Forever's side buttons: the eye, the magnifier and the people).
function Finder.Side()
    local root = _G.LFGParentFrame
    if not (root and root:IsShown()) then L.Print("Open the Group Finder first (I), then /hlfg side.") return end
    local known = { [_G.LFGListingFrame or 0] = true, [_G.LFGBrowseFrame or 0] = true, [_G.LFGWhoListFrame or 0] = true }
    local function attached(f)
        for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do
            local _, rel = f:GetPoint(i)
            if rel == root then return true end
        end
        local p = f.GetParent and f:GetParent()
        return p == root
    end
    local function texInfo(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then
                local atlas = r.GetAtlas and r:GetAtlas()
                local file = r.GetTexture and r:GetTexture()
                if atlas or file then return tostring(atlas or file) end
            end
        end
        return "-"
    end
    local found = 0
    local f = EnumerateFrames()
    while f do
        local ok, hit = pcall(function()
            return f:IsShown() and not known[f] and f ~= root and attached(f) and not (f.GetName and f:GetName())
        end)
        if ok and hit then
            found = found + 1
            local kind = f:GetObjectType()
            local x, y = f:GetCenter()
            L.Print(("#%d %s %dx%d at %d,%d click:%s tex:%s"):format(found, kind, f:GetWidth(), f:GetHeight(),
                x or 0, y or 0, tostring(f.Click ~= nil), texInfo(f)))
            Finder.sideFrames = Finder.sideFrames or {}
            Finder.sideFrames[found] = f
        end
        f = EnumerateFrames(f)
    end
    if found == 0 then L.Print("No unnamed frames attached to the Group Finder.") end
end
