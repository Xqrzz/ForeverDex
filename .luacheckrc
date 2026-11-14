-- Luacheck configuration: https://luacheck.readthedocs.io
-- Run from the addon folder:  luacheck .
-- WoW runs Lua 5.1. Every game API the addon uses is listed below: a name missing from
-- these lists is reported, which catches typos and globals created by mistake.

std = "lua51"
max_line_length = 150
-- Methods declared with ":" do not always use self.
self = false

exclude_files = {
    "DemoMode.lua", -- local test tool, never shipped
    ".release/",
}

-- Written by the addon: saved data, slash commands, key binding names, popups.
globals = {
    "BINDING_HEADER_FOREVERDEX", "BINDING_NAME_FOREVERDEX_CAPTURE", "BINDING_NAME_FOREVERDEX_CAPTURE_GUILD",
    "BINDING_NAME_FOREVERDEX_COMPARE", "BINDING_NAME_FOREVERDEX_TOGGLE", "ForeverDexDB",
    "SLASH_FOREVERDEX1", "SLASH_FOREVERDEX2", "SlashCmdList", "StaticPopupDialogs",
}

-- Read from the game.
read_globals = {
    "ACCEPT", "ADDONS", "BackdropTemplateMixin", "CANCEL", "CLASS_ICON_TCOORDS", "C_AddOns", "C_CVar",
    "C_ChatInfo", "C_CreatureInfo", "C_GamePad", "C_GuildInfo", "C_InputInterfaceStyle", "C_NamePlate", "C_Texture", "C_Timer",
    "C_TooltipInfo", "ChatFrame_AddMessageEventFilter", "CheckInteractDistance", "CreateColor",
    "CreateFrame", "DECLINE", "DEFAULT_CHAT_FRAME", "EJ_GetInstanceForMap", "EJ_GetInstanceInfo",
    "ERR_CHAT_PLAYER_NOT_FOUND_S", "Enum", "EnumerateFrames", "EnumerateServerChannels",
    "FACTION_ALLIANCE", "FACTION_HORDE", "GRAY_FONT_COLOR", "GameMenuFrame", "GameTooltip", "GameTooltip_SetTitle",
    "GetBindingAction", "GetBindingText", "GetCVar", "GetCVarBool", "GetChannelName", "GetCursorPosition", "GetGuildInfo", "GetLocale",
    "GetNormalizedRealmName", "GetNumPartyMembers", "GetPlayerInfoByGUID", "GetRealZoneText",
    "GetTime", "GetUnitName", "HIGHLIGHT_FONT_COLOR", "HideUIPanel", "InCombatLockdown",
    "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid", "LE_PARTY_CATEGORY_HOME",
    "LE_PARTY_CATEGORY_INSTANCE", "Menu", "MenuUtil", "Minimap", "NO", "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab", "PlaySound", "RAID_CLASS_COLORS", "ReloadUI", "SOUNDKIT",
    "STATICPOPUP_NUMDIALOGS", "SendChatMessage", "SetCVar", "SetPortraitTexture", "SettingsPanel", "StaticPopup_Show",
    "StaticPopup_Visible", "TargetFrame", "TargetFramePortrait", "TooltipDataProcessor",
    "UIParent", "UISpecialFrames", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_MINION",
    "UNITNAME_TITLE_PET", "UNKNOWNOBJECT", "UnitAffectingCombat", "UnitCanAttack", "UnitClass",
    "UnitCreatureFamily", "UnitCreatureType", "UnitExists", "UnitFactionGroup", "UnitFullName",
    "UnitGUID", "UnitIsPlayer", "UnitIsUnit", "UnitLevel", "UnitName", "UnitPlayerControlled",
    "UnitRace", "UnitSex", "UnitTokenFromGUID", "YES", "hooksecurefunc", "date", "issecretvalue", "time", "tinsert",
    "wipe",
}

files["Locales/"] = { max_line_length = false }
