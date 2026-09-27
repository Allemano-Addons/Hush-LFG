-- Options: the "LFG" page in the Hush settings (/hlfg options or the gear in the window).
local _, L = ...

local Hush = Hush
local W = Hush.Widgets

Hush.AddSettingsPage({
    id = "lfg",
    label = "LFG",
    build = function(page)
        page:Header("General")
        page:Toggle("Open with the Group Finder", "Searching in the Group Finder (I) opens Hush LFG. Never in combat.",
            function() return L.db.autoOpen end,
            function(v) L.db.autoOpen = v end)
        page:Toggle("Tab in the Group Finder", "A Hush LFG button under the Group Finder's side buttons.",
            function() return L.db.sideTab end,
            function(v)
                L.db.sideTab = v
                if L.UpdateSideTab then L.UpdateSideTab() end
            end)

        page:Header("Ask to join")
        page:Text("The whisper for groups found in chat. It opens in Hush for you to edit and send - "
            .. "never sent by itself. {role} {class} {level} {dungeon} {leader} are filled in.")
        page:Custom(96, function(c)
            local box = W.EditBox(c, L.DEFAULT_JOIN, 28)
            box:SetPoint("TOPLEFT", 0, 0)
            box:SetPoint("TOPRIGHT", 0, 0)
            box:SetMaxLetters(200)
            local preview = W.Text(c, "regular", -1, "textDim")
            preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
            preview:SetPoint("RIGHT", c, "RIGHT")
            preview:SetJustifyH("LEFT")
            preview:SetWordWrap(true)
            local function update()
                preview:SetText("Preview: " .. L.JoinMessage({ activity = "Wailing Caverns", leader = "Kelu Xin" }))
            end
            local function save(self)
                L.db.joinMessage = strtrim(self:GetText() or "")
                update()
            end
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            box:HookScript("OnEditFocusLost", save)
            box:HookScript("OnTextChanged", function(self, user) if user then save(self) end end)
            local reset = W.Button(c, "Default text", "ghost", function()
                L.db.joinMessage = ""
                box:SetText("")
                update()
            end)
            reset:SetHeight(24)
            reset:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", -8, -8)
            return function()
                box:SetText(L.db.joinMessage or "")
                update()
            end
        end)

        page:Header("Filters")
        page:Button("Reset filters", "Dungeon, level, source, role and hidden classes.", "Reset", "default", function()
            L.db.activity, L.db.levels, L.db.source, L.db.role = "all", "any", "both", "any"
            wipe(L.db.hiddenClasses)
            if L.UI then L.UI.FiltersChanged() end
        end)
    end,
})
