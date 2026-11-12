local _, ns = ...

-- The chosen language is in the saved data, which the game only provides after
-- every file has run. The modules therefore wait for ADDON_LOADED (see ForeverDex.lua).
ns.Modules = {}
function ns.Module(load) ns.Modules[#ns.Modules + 1] = load end

ns.Locales = {}

-- Shown in their own language, whatever the current one is.
ns.LANGUAGES = {
    { "deDE", "Deutsch" },
    { "enUS", "English" },
    { "esES", "Español" },
    { "frFR", "Français" },
    { "itIT", "Italiano" },
    { "ptBR", "Português" },
    { "ruRU", "Русский" },
}

local ALIASES = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }

-- A string missing from a translation falls back to English.
function ns.ApplyLanguage(choice)
    local code = choice and choice ~= "auto" and choice or GetLocale()
    code = ALIASES[code] or code
    local en = ns.Locales.enUS
    local active = ns.Locales[code] or en
    if active ~= en then setmetatable(active, { __index = en }) end
    ns.L = active
    -- Changing the language needs a reload: the other translations are never read
    -- again, and are let go instead of staying in memory for the whole session.
    for other, strings in pairs(ns.Locales) do
        if strings ~= active and strings ~= en then ns.Locales[other] = nil end
    end
end
