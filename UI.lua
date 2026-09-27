-- UI: the Hush LFG window (see the mockup). Groups / Players tabs on the left; search, role and
-- Refresh Finder on top; one row per group or player with class icons, open role slots and buttons.
-- Refresh Finder clicks Blizzard's own refresh button through a secure macro (/click), because
-- addons may not call the Group Finder search themselves.
local _, L = ...

local Hush = Hush
local Theme, W = Hush.Theme, Hush.Widgets

local UI = {}
L.UI = UI

local WIDTH, HEIGHT, SIDE_W = 1000, 620, 250
local ROW_H, PAD, SLOT = 80, 16, 24
local MAX_SLOTS = 8
local REFRESH_BUTTON = "LFGBrowseFrameRefreshButton"
local OPEN_BUTTON = "LFDMicroButton" -- opens the Group Finder on Forever
local SEARCH_TAB = "LFGParentFrameTab2" -- its search (browse) tab

local ROLES = { "none", "tank", "healer", "dps" }
local ROLE_LABEL = { none = "My role: none", tank = "My role: Tank", healer = "My role: Healer", dps = "My role: DPS" }
local ROLE_LETTER = { tank = "T", healer = "H", dps = "D" }
local ROLE_NAME = { tank = "Tank", healer = "Healer", dps = "DPS" }
local SOURCE_LABEL = { finder = "Finder", chat = "Chat", both = "Chat + Finder" }

local frame, listArea, scrollbar, rowPool
local tabs = {}
local state = { tab = "group", search = "", offset = 0, filtered = 0 }
local items, counts = {}, { group = 0, player = 0 }
local activityNames = {} -- dungeons in the current list, for the dropdown

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function classColor(class)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then return c.r, c.g, c.b end
    return Theme:Color("text")
end

local function ago(s)
    if s < 60 then return "now" end
    if s < 3600 then return floor(s / 60) .. "m" end
    return floor(s / 3600) .. "h"
end

local function myRole()
    return Hush.Feed and Hush.Feed.GetRole() or "none"
end

-- The real class icons (atlas on this client, the old texture sheet as a fallback).
local function setClassIcon(tex, class)
    if tex.SetAtlas and pcall(tex.SetAtlas, tex, "classicon-" .. strlower(class)) then
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
end

local function matchesSearch(e, q)
    if q == "" then return true end
    for _, a in ipairs(e.activities or {}) do
        if strlower(a):find(q, 1, true) then return true end
    end
    return strlower(e.leader):find(q, 1, true)
        or (e.text and strlower(e.text):find(q, 1, true)) or (e.chat and strlower(e.chat):find(q, 1, true))
end

local function tag(parent, accent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(18)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.text = W.Text(t, "semibold", -2, "text")
    t.text:SetPoint("CENTER")
    if accent then
        W.OnAccent(function(r, g, b) t.bg:SetColorTexture(r, g, b, 1) end)
        t.text:SetTextColor(Theme:Color("sidebar"))
    else
        t.bg:SetColorTexture(0, 0, 0, 0)
        W.Border(t, "line")
        t.text:SetTextColor(Theme:Color("textDim"))
    end
    function t:SetLabel(s)
        self.text:SetText(s)
        self:SetWidth(self.text:GetStringWidth() + 12)
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- A slot: a member's class icon, or an open role (T / H / D in a frame).
local function createSlot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SLOT, SLOT)
    s:EnableMouse(true)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.border = W.Border(s, "line")
    s.letter = W.Text(s, "semibold", -1, "textDim")
    s.letter:SetPoint("CENTER")
    s:SetScript("OnEnter", function(self) if self.tip then W.ShowTooltip(self, self.tip) end end)
    s:SetScript("OnLeave", function() W.HideTooltip() end)
    return s
end

local function setMemberSlot(s, m)
    s.icon:Show()
    setClassIcon(s.icon, m.class)
    s.letter:SetText("")
    s.border:SetColor(Theme:Color("line"))
    local parts = { m.name or "?" }
    if m.level then parts[#parts + 1] = "level " .. m.level end
    if m.role then parts[#parts + 1] = ROLE_NAME[m.role] end
    s.tip = table.concat(parts, " · ")
end

local function setRoleSlot(s, role, open)
    s.icon:Hide()
    s.letter:SetText(ROLE_LETTER[role])
    if role == myRole() then
        local r, g, b = Theme:Accent()
        s.letter:SetTextColor(r, g, b)
        s.border:SetColor(r, g, b, 1)
    else
        s.letter:SetTextColor(Theme:Color(open and "textFaint" or "text"))
        s.border:SetColor(Theme:Color("line"))
    end
    s.tip = open and ("Needs a " .. strlower(ROLE_NAME[role])) or ("Can play " .. ROLE_NAME[role])
end

local function createRow()
    local r = CreateFrame("Frame", nil, listArea)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r.hover = W.Fill(r, "selected", 0.6)
    r.hover:SetAllPoints()
    r.hover:Hide()
    W.Line(r, "bottom", "line")
    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) if not self:IsMouseOver() then self.hover:Hide() end end)

    r.title = W.Text(r, "heading", 2, "text")
    r.title:SetPoint("TOPLEFT", PAD, -14)
    -- "+4" when a listing is for several dungeons; hover it for all of them.
    r.more = tag(r)
    r.more:SetPoint("LEFT", r.title, "RIGHT", 6, 0)
    r.more:EnableMouse(true)
    r.more:SetScript("OnEnter", function(self) if self.tip then W.ShowTooltip(self, self.tip) end end)
    r.more:SetScript("OnLeave", function() W.HideTooltip() end)
    r.src = tag(r)
    r.need = tag(r, true)
    r.need:SetLabel("Needs your role")
    r.need:SetPoint("LEFT", r.src, "RIGHT", 6, 0)

    r.leader = W.Text(r, "semibold", 1)
    r.leader:SetPoint("TOPLEFT", PAD, -38)
    r.text = W.Text(r, "regular", 1, "text")
    r.text:SetPoint("LEFT", r.leader, "RIGHT", 8, 0)
    r.text:SetWordWrap(false)
    r.text:SetJustifyH("LEFT")
    r.meta = W.Text(r, "regular", -1, "textFaint")
    r.meta:SetPoint("TOPLEFT", PAD, -58)

    -- Buttons, right to left: Whisper, Invite (players).
    r.whisper = W.Button(r, "Whisper", "default", function()
        if r.entry then Hush.OpenWhisper(r.entry.leader) end
    end)
    r.whisper:SetHeight(28)
    r.whisper:SetPoint("RIGHT", -PAD, 0)
    r.invite = W.Button(r, "Invite", "default", function()
        if r.entry then Hush.InviteToGroup(r.entry.leader) end
    end)
    r.invite:SetHeight(28)
    r.invite:SetPoint("RIGHT", r.whisper, "LEFT", -8, 0)

    r.slots = {}
    for i = 1, MAX_SLOTS do r.slots[i] = createSlot(r) end
    return r
end

local function fillRow(r, e)
    r.entry = e
    -- Title: the dungeon you filter on when the listing has it, else the first one.
    local acts = e.activities or {}
    local shownName = e.activity
    if L.db.activity ~= "all" then
        for _, a in ipairs(acts) do if a == L.db.activity then shownName = a end end
    end
    r.title:SetText(shownName or (e.kind == "group" and "Group" or "Any dungeon"))
    r.more:SetShown(#acts > 1)
    r.src:ClearAllPoints()
    if #acts > 1 then
        r.more:SetLabel("+" .. (#acts - 1))
        r.more.tip = table.concat(acts, "\n")
        r.src:SetPoint("LEFT", r.more, "RIGHT", 6, 0)
    else
        r.src:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
    end
    r.src:SetLabel(SOURCE_LABEL[e.source])
    r.need:SetShown(e.needsRole)
    r.leader:SetText(e.leader)
    r.leader:SetTextColor(classColor(e.leaderClass))
    r.text:SetText(e.text or "")

    local meta = {}
    if e.minLevel and e.maxLevel and e.minLevel ~= e.maxLevel then
        meta[#meta + 1] = "Level " .. e.minLevel .. "-" .. e.maxLevel
    elseif e.minLevel or e.level then
        meta[#meta + 1] = "Level " .. (e.minLevel or e.level)
    end
    if e.kind == "group" and e.size then meta[#meta + 1] = e.size .. "/5" end
    if e.area then meta[#meta + 1] = e.area end
    if e.channel then meta[#meta + 1] = e.channel end
    meta[#meta + 1] = ago(e.age)
    r.meta:SetText(table.concat(meta, " · "))

    r.invite:SetShown(e.kind == "player")
    local leftButton = e.kind == "player" and r.invite or r.whisper

    -- Slots: members' class icons, then open roles (groups) or the roles a player can play.
    local n = 0
    local function slot()
        n = n + 1
        return r.slots[n]
    end
    for _, m in ipairs(e.members) do
        if m.class and n < MAX_SLOTS then setMemberSlot(slot(), m) end
    end
    if e.kind == "group" then
        for _, role in ipairs({ "tank", "healer", "dps" }) do
            for _ = 1, (e.missing and e.missing[role] or 0) do
                if n < MAX_SLOTS then setRoleSlot(slot(), role, true) end
            end
        end
    else
        for _, role in ipairs({ "tank", "healer", "dps" }) do
            if e.roles and e.roles[role] and n < MAX_SLOTS then setRoleSlot(slot(), role, false) end
        end
    end
    local x = -12
    for i = n, 1, -1 do
        local s = r.slots[i]
        s:ClearAllPoints()
        s:SetPoint("RIGHT", leftButton, "LEFT", x, 0)
        s:Show()
        x = x - SLOT - 4
    end
    for i = n + 1, MAX_SLOTS do r.slots[i]:Hide() end
    -- The comment gets the room left of the slots.
    local right = 16 + (e.kind == "player" and 180 or 100) + n * (SLOT + 4)
    r.text:SetWidth(max(60, listArea:GetWidth() - PAD - right - r.leader:GetStringWidth() - 8 - PAD))
end

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------

local function contentH() return #items * ROW_H end
local function maxOffset() return max(0, contentH() - listArea:GetHeight()) end

local function render()
    rowPool:ReleaseAll()
    local viewH = listArea:GetHeight()
    local first = floor(state.offset / ROW_H) + 1
    for i = first, #items do
        local top = (i - 1) * ROW_H - state.offset
        if top >= viewH then break end
        local r = rowPool:Acquire()
        fillRow(r, items[i])
        r:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -top)
        r:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", 0, -top)
    end
    scrollbar:Update(state.offset, contentH(), viewH)
end

function UI.SetOffset(v)
    state.offset = min(max(0, v), maxOffset())
    render()
end

local function updateChrome()
    for _, t in ipairs(tabs) do
        local on = t.id == state.tab
        t.label:SetText((t.id == "group" and "GROUPS " or "PLAYERS ") .. counts[t.id])
        t.label:SetTextColor(Theme:Color(on and "text" or "textDim"))
        t.line:SetShown(on)
    end
    local role = myRole()
    frame.roleBtn.text:SetText(ROLE_LABEL[role])
    frame.roleBtn:SetWidth(frame.roleBtn.text:GetStringWidth() + 28)
    if frame.roleBtn.bg then
        if role ~= "none" then
            frame.roleBtn.bg:SetColorTexture(Theme:Accent())
            frame.roleBtn.text:SetTextColor(Theme:Color("sidebar"))
        else
            frame.roleBtn.bg:SetColorTexture(Theme:Color("field"))
            frame.roleBtn.text:SetTextColor(Theme:Color("text"))
        end
    end
    local finder = L.Finder.updated and ("Finder updated " .. ago(time() - L.Finder.updated) .. (time() - L.Finder.updated < 60 and "" or " ago"))
        or (L.Finder.Ready() and "Finder: press Refresh Finder" or "Press Refresh Finder to open the Group Finder search")
    frame.status:SetText(finder .. " · chat is live")
    local merged = 0
    for _, e in ipairs(items) do if e.source == "both" then merged = merged + 1 end end
    frame.footer:SetText(("%d %s%s%s"):format(#items, state.tab == "group" and "groups" or "players",
        merged > 0 and (" · " .. merged .. " in both chat and Finder") or "",
        state.filtered > 0 and (" · " .. state.filtered .. " hidden by filters") or ""))

    -- Filters
    frame.activityDrop:Set(L.db.activity)
    frame.levelDrop:Set(L.db.levels)
    frame.sourceDrop:Set(L.db.source)
    frame.roleSeg:Set(L.db.role)
    frame.roleHeader:SetText(state.tab == "group" and "ROLE · GROUPS THAT NEED" or "ROLE · PLAYERS WHO PLAY")
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local q = strlower(strtrim(state.search))
    local level = UnitLevel("player")
    wipe(items)
    wipe(activityNames)
    counts.group, counts.player = 0, 0
    state.filtered = 0
    local seen = {}
    for _, e in ipairs(L.Build()) do
        for _, a in ipairs(e.activities or {}) do
            if not seen[a] then
                seen[a] = true
                activityNames[#activityNames + 1] = a
            end
        end
        if matchesSearch(e, q) then
            if L.Passes(e, L.db, level) then
                counts[e.kind] = counts[e.kind] + 1
                if e.kind == state.tab then items[#items + 1] = e end
            elseif e.kind == state.tab then
                state.filtered = state.filtered + 1
            end
        end
    end
    -- Keep the chosen dungeon in the dropdown even when nobody runs it right now.
    if L.db.activity ~= "all" and not seen[L.db.activity] then activityNames[#activityNames + 1] = L.db.activity end
    sort(activityNames)
    state.offset = min(state.offset, maxOffset())
    updateChrome()
    render()
end

-- New posts and Finder results arrive in bursts: refresh at most twice a second.
local pending = false
local function queueRefresh()
    if pending or not frame or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        UI.Refresh()
    end)
end
local armRefresh
L.OnFinderUpdate = function()
    queueRefresh()
    -- The first results of the session mean Blizzard's button can search now.
    if frame and frame:IsShown() then armRefresh() end
end
if Hush.Feed then
    Hush.Feed.OnPost(function(p) if p.cat == "lfg" then queueRefresh() end end)
end

-- ---------------------------------------------------------------------------
-- Refresh Finder: clicks Blizzard's refresh button (secure, so it counts as your click).
-- ---------------------------------------------------------------------------

function armRefresh() -- declared local above
    local b = frame.refreshBtn
    if not b.secure then return end
    -- Blizzard's button only searches once the Group Finder knows what to search for.
    -- Until then: open the Group Finder (its micro button opens the "list yourself" tab),
    -- switch to its search tab, and refresh.
    local parent = _G.LFGParentFrame
    if _G[REFRESH_BUTTON] and L.Finder.Ready() then
        b.secure:Arm("/click " .. REFRESH_BUTTON)
        return
    end
    local lines = {}
    if _G[OPEN_BUTTON] and not (parent and parent:IsShown()) then lines[#lines + 1] = "/click " .. OPEN_BUTTON end
    if _G[SEARCH_TAB] then lines[#lines + 1] = "/click " .. SEARCH_TAB end
    if _G[REFRESH_BUTTON] then lines[#lines + 1] = "/click " .. REFRESH_BUTTON end
    if #lines > 0 then
        b.secure:Arm(table.concat(lines, "\n"))
    else
        b.secure:Disarm()
    end
end

-- ---------------------------------------------------------------------------
-- Filters (sidebar)
-- ---------------------------------------------------------------------------

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local LEVEL_OPTIONS = { { value = "any", label = "Any level" }, { value = 2, label = "Within 2 of my level" },
    { value = 5, label = "Within 5 of my level" } }
local SOURCE_OPTIONS = { { value = "both", label = "Chat + Finder" }, { value = "chat", label = "Chat only" },
    { value = "finder", label = "Finder only" } }
local ROLE_OPTIONS = { { value = "any", label = "All" }, { value = "tank", label = "Tank" },
    { value = "healer", label = "Healer" }, { value = "dps", label = "DPS" } }


local function filterHeader(parent, text, y)
    local fs = W.Text(parent, "heading", -1, "textFaint")
    fs:SetPoint("TOPLEFT", PAD, y)
    fs:SetText(text)
    return fs
end

local function className(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class] or (class:sub(1, 1) .. strlower(class:sub(2)))
end

local function updateClassButtons()
    local hidden = 0
    for _, b in ipairs(frame.classButtons) do
        local off = L.db.hiddenClasses[b.class] == true
        if off then hidden = hidden + 1 end
        b.icon:SetDesaturated(off)
        b.icon:SetAlpha(off and 0.4 or 1)
        b.label:SetTextColor(Theme:Color(off and "textFaint" or "text"))
        b.strike:SetShown(off)
    end
    frame.classNote:SetText(hidden > 0 and ("Click a class to show it again. " .. hidden .. " hidden.")
        or "Click a class to hide it.")
end

local function buildFilters(side)
    local w = SIDE_W - PAD * 2
    local function changed()
        state.offset = 0
        UI.Refresh()
    end

    filterHeader(side, "DUNGEON / RAID", -110)
    frame.activityDrop = W.Dropdown(side, w, function()
        local opts = { { value = "all", label = "All dungeons" } }
        for _, n in ipairs(activityNames) do opts[#opts + 1] = { value = n, label = n } end
        return opts
    end, function(v) L.db.activity = v; changed() end)
    frame.activityDrop:SetPoint("TOPLEFT", PAD, -128)

    filterHeader(side, "LEVEL", -166)
    frame.levelDrop = W.Dropdown(side, w, function() return LEVEL_OPTIONS end,
        function(v) L.db.levels = v; changed() end)
    frame.levelDrop:SetPoint("TOPLEFT", PAD, -184)

    filterHeader(side, "SOURCE", -222)
    frame.sourceDrop = W.Dropdown(side, w, function() return SOURCE_OPTIONS end,
        function(v) L.db.source = v; changed() end)
    frame.sourceDrop:SetPoint("TOPLEFT", PAD, -240)

    frame.roleHeader = filterHeader(side, "ROLE", -278)
    frame.roleSeg = W.Segment(side, ROLE_OPTIONS, function(v) L.db.role = v; changed() end)
    frame.roleSeg:SetPoint("TOPLEFT", PAD, -296)

    filterHeader(side, "HIDE GROUPS THAT INCLUDE", -336)
    frame.classButtons = {}
    local cellW, cellH = (w - 8) / 3, 28
    for i, class in ipairs(CLASSES) do
        local b = CreateFrame("Button", nil, side)
        b.class = class
        b:SetSize(cellW, cellH)
        b:SetPoint("TOPLEFT", PAD + ((i - 1) % 3) * (cellW + 4), -354 - floor((i - 1) / 3) * (cellH + 4))
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        W.Border(b, "line")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 5, 0)
        setClassIcon(b.icon, class)
        b.label = W.Text(b, "semibold", -2, "text")
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.label:SetText(className(class))
        b.strike = b:CreateTexture(nil, "OVERLAY")
        b.strike:SetHeight(1)
        b.strike:SetPoint("LEFT", b.label, "LEFT", -1, 0)
        b.strike:SetPoint("RIGHT", b.label, "RIGHT", 1, 0)
        b.strike:SetColorTexture(Theme:Color("textDim"))
        b:SetScript("OnClick", function(self)
            L.db.hiddenClasses[self.class] = not L.db.hiddenClasses[self.class] or nil
            updateClassButtons()
            changed()
        end)
        frame.classButtons[i] = b
    end
    frame.classNote = W.Text(side, "regular", -1, "textFaint")
    frame.classNote:SetPoint("TOPLEFT", PAD, -354 - 3 * (cellH + 4) - 6)
    frame.classNote:SetWidth(w)
    frame.classNote:SetJustifyH("LEFT")

    frame.resetBtn = W.Button(side, "Reset filters", "ghost", function()
        L.db.activity, L.db.levels, L.db.source, L.db.role = "all", "any", "both", "any"
        wipe(L.db.hiddenClasses)
        updateClassButtons()
        changed()
    end)
    frame.resetBtn:SetHeight(26)
    frame.resetBtn:SetPoint("TOPLEFT", frame.classNote, "BOTTOMLEFT", -8, -10)
    updateClassButtons()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function build()
    -- Named only so ESC closes it (UISpecialFrames).
    frame = CreateFrame("Frame", "HushLFGFrame", UIParent)
    tinsert(UISpecialFrames, "HushLFGFrame")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    W.SetResizeBounds(frame, 820, 580, 2000, 1400)
    frame.bg = W.Fill(frame, "window", 0.98)
    frame.bg:SetAllPoints()

    local d = L.db.lfgWindow
    frame:SetSize(d.w or WIDTH, d.h or HEIGHT)
    if d.left and d.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
    else
        frame:SetPoint("CENTER", 0, 20)
    end
    local function save()
        d.left, d.top = Theme:Snap(frame:GetLeft(), frame), Theme:Snap(frame:GetTop(), frame)
        d.w, d.h = Theme:Snap(frame:GetWidth(), frame), Theme:Snap(frame:GetHeight(), frame)
    end

    -- Sidebar
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE_W)
    side.bg = W.Fill(side, "sidebar", 1)
    side.bg:SetAllPoints()
    W.Line(side, "right", "line")

    local title = CreateFrame("Frame", nil, side)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(56)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function() frame:StopMovingOrSizing() save() end)
    local square = title:CreateTexture(nil, "ARTWORK")
    square:SetSize(10, 10)
    square:SetPoint("LEFT", PAD, 0)
    W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)
    local name = W.Text(title, "heading", 5, "text")
    name:SetPoint("LEFT", square, "RIGHT", 10, 0)
    name:SetText("HUSH |cff9aa3adLFG|r")

    -- Tabs: Groups / Players
    for i, id in ipairs({ "group", "player" }) do
        local t = CreateFrame("Button", nil, side)
        t.id = id
        t:SetSize((SIDE_W - PAD * 2) / 2, 36)
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (SIDE_W - PAD * 2) / 2, -56)
        t.label = W.Text(t, "heading", 0, "text")
        t.label:SetPoint("CENTER")
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT")
        t.line:SetPoint("BOTTOMRIGHT")
        W.OnAccent(function(r, g, b) t.line:SetColorTexture(r, g, b, 1) end)
        t:SetScript("OnClick", function(self)
            state.tab = self.id
            state.offset = 0
            UI.Refresh()
        end)
        tabs[i] = t
    end
    local tabLine = side:CreateTexture(nil, "BORDER")
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", PAD, -92)
    tabLine:SetPoint("TOPRIGHT", -PAD, -92)
    tabLine:SetColorTexture(Theme:Color("line"))

    buildFilters(side)

    -- Content
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT")
    content:SetPoint("BOTTOMRIGHT")

    local close = W.IconButton(content, "close", 24, "Close", function() frame:Hide() end, "x")
    close:SetPoint("TOPRIGHT", -8, -8)

    local search = W.EditBox(content, "Search dungeon, leader, comment", 32)
    search:SetPoint("TOPLEFT", PAD, -40)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:HookScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        state.offset = 0
        UI.Refresh()
    end)

    frame.refreshBtn = W.Button(content, "Refresh Finder", "default", function()
        -- Only runs when the secure click is not armed (not ready yet, or in combat).
        if InCombatLockdown() then
            L.Print("Refresh Finder works out of combat.")
        else
            L.Print("Search once in the Group Finder (I) this session - after that, Refresh Finder works from here.")
        end
    end)
    frame.refreshBtn:SetHeight(32)
    frame.refreshBtn:SetWidth(frame.refreshBtn.text:GetStringWidth() + 28)
    frame.refreshBtn:SetPoint("TOPRIGHT", -PAD, -40)
    frame.refreshBtn.secure = W.SecureMacroOverlay(frame.refreshBtn, function()
        frame.status:SetText("Searching the Group Finder...")
        local clicked = time()
        C_Timer.After(6, function()
            if frame:IsShown() and (L.Finder.updated or 0) < clicked then
                frame.status:SetText("No answer - pick a dungeon in the Group Finder and search once")
            end
        end)
    end, { upOnly = true })

    frame.roleBtn = W.Button(content, "My role", "default", function()
        local nextRole = ROLES[1]
        for i, v in ipairs(ROLES) do
            if v == myRole() then nextRole = ROLES[i % #ROLES + 1] end
        end
        if Hush.Feed then Hush.Feed.SetRole(nextRole) end
        UI.Refresh()
    end)
    frame.roleBtn:SetHeight(32)
    frame.roleBtn:SetPoint("RIGHT", frame.refreshBtn, "LEFT", -8, 0)
    frame.roleBtn:HookScript("OnLeave", function() updateChrome() end)
    search:SetPoint("RIGHT", frame.roleBtn, "LEFT", -8, 0)

    -- Footer
    local foot = CreateFrame("Frame", nil, content)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(40)
    W.Line(foot, "top", "line")
    frame.footer = W.Text(foot, "regular", -1, "textFaint")
    frame.footer:SetPoint("LEFT", PAD, 0)
    frame.status = W.Text(foot, "regular", -1, "textFaint")
    frame.status:SetPoint("RIGHT", -PAD - 16, 0)

    -- List
    listArea = CreateFrame("Frame", nil, content)
    listArea:SetPoint("TOPLEFT", 0, -84)
    listArea:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    listArea:SetClipsChildren(true)
    W.Line(listArea, "top", "line")
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta) UI.SetOffset(state.offset - delta * ROW_H) end)
    listArea:SetScript("OnSizeChanged", function() if frame:IsShown() then UI.Refresh() end end)
    rowPool = W.Pool(createRow, function(r) r.entry = nil; r.hover:Hide() end)
    scrollbar = W.Scrollbar(listArea, UI.SetOffset)

    -- Resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip.icon = W.Icon(grip, "grip", 12, "/")
    grip.icon:SetColor(Theme:Color("textFaint"))
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() save() end)

    frame.border = W.Border(frame, "line")
    for _, s in ipairs({ "top", "bottom", "left", "right" }) do frame.border[s]:SetDrawLayer("OVERLAY", 7) end
    if W.SkinPanel then
        W.SkinPanel(frame, { kind = "dialog", hide = { frame.bg, side.bg }, borders = { frame.border }, title = name })
    end

    -- While open: refresh every 20 s (ages); re-arm Refresh Finder after combat.
    local token = 0
    local function tick(t)
        if t ~= token or not frame:IsShown() then return end
        UI.Refresh()
        C_Timer.After(20, function() tick(t) end)
    end
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function() if frame:IsShown() then armRefresh() end end)
    -- Re-arm when Blizzard's Group Finder opens or closes (the micro button toggles it).
    local parent = _G.LFGParentFrame
    if parent and parent.HookScript then
        -- Later, not right away: the Group Finder can open in the middle of our own click,
        -- and changing the macro then could cut the rest of it (tab, refresh) short.
        local function rearm()
            C_Timer.After(0.3, function()
                if frame:IsShown() and not InCombatLockdown() then armRefresh() end
            end)
        end
        parent:HookScript("OnShow", rearm)
        parent:HookScript("OnHide", rearm)
    end
    frame:SetScript("OnShow", function()
        token = token + 1
        pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
        armRefresh()
        UI.Refresh()
        local t = token
        C_Timer.After(20, function() tick(t) end)
    end)
    frame:SetScript("OnHide", function()
        token = token + 1
        events:UnregisterAllEvents()
        W.CloseMenus()
    end)
    frame:Hide()
end

function UI.Toggle()
    if not L.db then return end
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

-- Entry points in Hush: a title-row button and the launcher menu.
Hush.AddTitleButton({ icon = "person", glyph = "L", tooltip = "Hush LFG", onClick = function() UI.Toggle() end })
Hush.AddLauncherMenuItems(function() return { text = "Hush LFG", onClick = function() UI.Toggle() end } end)
