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

local ROLES = { "none", "tank", "healer", "dps" }
local ROLE_LABEL = { none = "My role: none", tank = "My role: Tank", healer = "My role: Healer", dps = "My role: DPS" }
local ROLE_LETTER = { tank = "T", healer = "H", dps = "D" }
local ROLE_NAME = { tank = "Tank", healer = "Healer", dps = "DPS" }
local SOURCE_LABEL = { finder = "Finder", chat = "Chat", both = "Chat + Finder" }

local frame, listArea, scrollbar, rowPool
local tabs = {}
local state = { tab = "group", search = "", offset = 0 }
local items, counts = {}, { group = 0, player = 0 }

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
    return (e.activity and strlower(e.activity):find(q, 1, true)) or strlower(e.leader):find(q, 1, true)
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
    r.src = tag(r)
    r.src:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
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
    r.title:SetText(e.activity or (e.kind == "group" and "Group" or "Any dungeon"))
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
        or "Finder: press Refresh Finder"
    frame.status:SetText(finder .. " · chat is live")
    local merged = 0
    for _, e in ipairs(items) do if e.source == "both" then merged = merged + 1 end end
    frame.footer:SetText(("%d %s%s"):format(#items, state.tab == "group" and "groups" or "players",
        merged > 0 and (" · " .. merged .. " in both chat and Finder") or ""))
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local q = strlower(strtrim(state.search))
    wipe(items)
    counts.group, counts.player = 0, 0
    for _, e in ipairs(L.Build()) do
        if matchesSearch(e, q) then
            counts[e.kind] = counts[e.kind] + 1
            if e.kind == state.tab then items[#items + 1] = e end
        end
    end
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
L.OnFinderUpdate = queueRefresh
if Hush.Feed then
    Hush.Feed.OnPost(function(p) if p.cat == "lfg" then queueRefresh() end end)
end

-- ---------------------------------------------------------------------------
-- Refresh Finder: clicks Blizzard's refresh button (secure, so it counts as your click).
-- ---------------------------------------------------------------------------

local function armRefresh()
    local b = frame.refreshBtn
    if not b.secure then return end
    if _G[REFRESH_BUTTON] then
        b.secure:Arm("/click " .. REFRESH_BUTTON)
    else
        b.secure:Disarm()
    end
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
    W.SetResizeBounds(frame, 820, 420, 2000, 1400)
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

    local note = W.Text(side, "regular", -1, "textFaint")
    note:SetPoint("TOPLEFT", PAD, -112)
    note:SetWidth(SIDE_W - PAD * 2)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    note:SetText("Filters (dungeon, level, source, classes) come in the next step.\n\n"
        .. "Groups: listed groups and LFM posts. Players: players looking for a group.")

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
        -- Only runs when the secure click is not armed (Blizzard's button is missing, or in combat).
        if InCombatLockdown() then
            L.Print("Refresh Finder works out of combat.")
        else
            L.Print("Open the Group Finder once (it loads its search button), then Refresh Finder works from here.")
        end
    end)
    frame.refreshBtn:SetHeight(32)
    frame.refreshBtn:SetWidth(frame.refreshBtn.text:GetStringWidth() + 28)
    frame.refreshBtn:SetPoint("TOPRIGHT", -PAD, -40)
    frame.refreshBtn.secure = W.SecureMacroOverlay(frame.refreshBtn, function()
        frame.status:SetText("Searching the Group Finder...")
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
