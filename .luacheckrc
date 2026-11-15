std = "lua51" -- WoW runs Lua 5.1
max_line_length = false
unused_args = false -- event handler and callback signatures are fixed by the API

exclude_files = {
    "Libs/**",
    "TitanXP.lua", -- not listed in the .toc
}

-- Saved variables and slash command registrations
globals = {
    "SLASH_KEHETSTTL1",
    "SLASH_KEHETSTTLXP1",
    "SlashCmdList",
    "TimeToLevelUpDB",
}

-- WoW API, FrameXML and libraries
read_globals = {
    "C_Timer",
    "C_XMLUtil",
    "CreateFrame",
    "GetMaxPlayerLevel",
    "GetXPExhaustion",
    "LibStub",
    "strtrim",
    "time",
    "UIParent",
    "UnitLevel",
    "UnitXP",
    "UnitXPMax",
}
