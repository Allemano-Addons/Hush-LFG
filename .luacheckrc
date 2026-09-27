std = "lua51"
exclude_files = { "Tests/**" }
max_line_length = false
self = false

globals = {
    "HushLFGDB",
    "SLASH_HUSHLFG1", "SLASH_HUSHLFG2", "SlashCmdList",
    "HushLFGFrame", -- window name, only so ESC closes it
}

read_globals = {
    "Hush",
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "tostringall", "tinsert", "tremove", "wipe",
    "sort", "floor", "ceil", "min", "max", "format", "date", "time", "CopyTable", "geterrorhandler",
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "GetTime", "C_Timer", "GameTooltip",
    "C_LFGList", "C_Texture", "_G", "unpack", "EnumerateFrames",
    "UISpecialFrames", "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS", "InCombatLockdown", "UnitLevel", "LOCALIZED_CLASS_NAMES_MALE", "issecretvalue", "CLASS_ICON_TCOORDS",
}
