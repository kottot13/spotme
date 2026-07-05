-- luacheck configuration for the SpotMe addon.
-- Runs in CI before packaging: catches undefined globals (typos in the WoW API),
-- unused variables and similar issues that the game would only reveal at runtime.

std = "lua51"          -- WoW runs on Lua 5.1
max_line_length = false

-- Globals the addon creates/assigns (so they are not flagged as accidental).
globals = {
    "SpotMeDB",
    "SlashCmdList",
    "SLASH_SPOTME1",
    "SLASH_SPOTME2",
}

-- WoW API the addon reads (known names, not typos).
read_globals = {
    "CreateFrame",
    "WorldMapFrame",
    "Minimap",
    "C_Map",
    "C_Timer",
    "C_ClassColor",
    "GetTime",
    "GetLocale",
    "UnitClass",
    "RAID_CLASS_COLORS",
    "hooksecurefunc",
    "wipe",
    "CopyTable",
    "ReloadUI",
    "Settings",
    "CreateSettingsListSectionHeaderInitializer",
    "GroupMembersPinMixin",
    -- party locator
    "UIParent",
    "UnitExists",
    "UnitName",
    "IsInGroup",
    "IsInRaid",
    "GetNumGroupMembers",
    "GetNumSubgroupMembers",
    "UnitPosition",
    "GetPlayerFacing",
    "C_Minimap",
    "GetCVarBool",
    "GetCursorPosition",
    "ShowUIPanel",
    "GameTooltip",
    "CLASS_ICON_TCOORDS",
    "LOCALIZED_CLASS_NAMES_MALE",
    "UiMapPoint",
    "C_SuperTrack",
    "IsShiftKeyDown",
    "CreateVector2D",
}
