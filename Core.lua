-- Hush_LFG: groups and players from chat (via Hush_Feed) and the Group Finder in one list.
-- Core: namespace, saved settings, slash commands.
local addonName, L = ...

L.name = addonName

function L.Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7ebHush LFG|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Saved settings (account-wide). Listings are kept in memory only.
-- ---------------------------------------------------------------------------

local DEFAULTS = {
    -- Filters
    source = "both",        -- "both" / "chat" / "finder"
    activity = "all",       -- a dungeon name, or "all"
    levels = "any",         -- "any" / 2 / 5: within this many levels of yours
    role = "any",           -- "any" / "tank" / "healer" / "dps": groups that need it, players who play it
    hiddenClasses = {},     -- classFile -> true: hide groups/players with this class
    autoOpen = true,        -- open Hush LFG when you search in the Group Finder
    lfgWindow = {},
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            fill(dst[k], v)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then return end
    if type(HushLFGDB) ~= "table" then HushLFGDB = {} end
    fill(HushLFGDB, DEFAULTS)
    L.db = HushLFGDB
    frame:UnregisterEvent("ADDON_LOADED")
    L.Finder.Init()
end)

-- ---------------------------------------------------------------------------
-- Slash
-- ---------------------------------------------------------------------------

SLASH_HUSHLFG1 = "/hlfg"
SLASH_HUSHLFG2 = "/hushlfg"
SlashCmdList.HUSHLFG = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        L.UI.Toggle()
    elseif cmd == "probe" then
        L.Finder.Probe()
    elseif cmd == "search" then
        L.Finder.Search(tonumber(rest))
    elseif cmd == "auto" then
        L.db.autoOpen = not L.db.autoOpen
        L.Print("Open Hush LFG when you search in the Group Finder:", L.db.autoOpen and "on" or "off")
    elseif cmd == "side" then
        L.Finder.Side()
    elseif cmd == "frames" then
        L.Finder.Frames()
    elseif cmd == "dump" then
        L.Finder.Dump()
    else
        L.Print("/hlfg - open the window, /hlfg auto - open it when you search in the Group Finder (on/off), /hlfg probe - what the Group Finder lets us read, /hlfg dump - list the results")
    end
end
