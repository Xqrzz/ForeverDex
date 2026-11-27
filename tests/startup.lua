-- Smoke-test the manifest and ADDON_LOADED using minimal game frame stubs.
local fixture = ...
local function noop() end
local frames, env = {}, setmetatable({}, { __index = _G })
env._G = env
if type(fixture) == "table" then env.ForeverDexDB = fixture end
env.date, env.time, env.tinsert = os.date, os.time, table.insert
env.wipe = function(t) for key in pairs(t) do t[key] = nil end end
env.GetLocale = function() return "enUS" end
env.GetTime = function() return 100 end
env.UISpecialFrames, env.StaticPopupDialogs, env.SlashCmdList = {}, {}, {}
env.C_ChatInfo = { RegisterAddonMessagePrefix = noop, SendAddonMessage = noop }
env.C_CreatureInfo = { GetClassInfo = function(id) return { classFile = "CLASS" .. id, className = "Class " .. id } end }
env.C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
env.GetNormalizedRealmName = function() return "Forever" end
env.UnitName, env.UnitFullName = function() return "Player", "Example" end, function() return "Player", "Example" end
env.GameFontNormal, env.GameFontHighlightSmall, env.GameFontHighlight = {}, {}, {}
env.UNKNOWNOBJECT, env.ACCEPT, env.CANCEL, env.DECLINE = "Unknown", "Accept", "Cancel", "Decline"
env.NO, env.YES = "No", "Yes"
env.FACTION_ALLIANCE, env.FACTION_HORDE, env.ADDONS = "Alliance", "Horde", "AddOns"
env.RAID_CLASS_COLORS, env.CLASS_ICON_TCOORDS = {}, {}
env.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
env.GRAY_FONT_COLOR, env.HIGHLIGHT_FONT_COLOR = env.NORMAL_FONT_COLOR, env.NORMAL_FONT_COLOR
env.hooksecurefunc, env.EnumerateFrames = noop, noop
env.UnitIsPlayer, env.UnitPlayerControlled = function() return false end, function() return false end
env.UnitIsUnit = function() return false end
local function make(name, parent)
    local frame = { named = name, parent = parent, scripts = {}, events = {}, shown = true }
    local methods = {
        GetName = function(self) return self.named end,
        GetParent = function(self) return self.parent end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetSize = function(self) return self.width or 100, self.height or 100 end,
        GetText = function(self) return self.text or "" end,
        SetText = function(self, value) self.text = value end,
        GetFont = function() return "Font", 12, "" end,
        GetObjectType = function(self) return self.type or "Frame" end,
        GetScript = function(self, script) return self.scripts[script] end,
        SetScript = function(self, script, callback) self.scripts[script] = callback end,
        HookScript = function(self, script, callback)
            local prior = self.scripts[script]
            self.scripts[script] = function(...)
                if prior then prior(...) end
                callback(...)
            end
        end,
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        SetShown = function(self, show) self.shown = show end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown end,
        IsEnabled = function() return true end,
        GetFrameStrata = function() return "MEDIUM" end,
        GetFontString = function(self) return make(nil, self) end,
        GetHighlightTexture = function(self) return make(nil, self) end,
        GetNormalTexture = function(self) return make(nil, self) end,
        GetPushedTexture = function(self) return make(nil, self) end,
        GetChildren = noop, GetRegions = noop,
        HasScript = function() return false end,
    }
    setmetatable(frame, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^Create") then return function(self) return make(nil, self) end end
        if key:match("^Get") then return function() return 1 end end
        for _, pre in ipairs({ "Set", "Register", "Enable", "Hide", "Show", "Clear", "Stop", "Play", "Add", "Raise", "Start" }) do
            if key:sub(1, #pre) == pre then return noop end
        end
    end })
    if name then env[name] = frame end
    frames[#frames + 1] = frame
    return frame
end
env.CreateFrame = function(kind, name, parent)
    local frame = make(name, parent)
    frame.type = kind
    return frame
end
env.UIParent, env.Minimap, env.DEFAULT_CHAT_FRAME = make("UIParent"), make("Minimap"), make("DEFAULT_CHAT_FRAME")
env.GameTooltip = make("GameTooltip")
local ns = {}
for path in io.lines("ForeverDex.toc") do
    if path:match("%.lua$") then
        local chunk = assert(loadfile((path:gsub("\\", "/"))))
        setfenv(chunk, env)("ForeverDex", ns)
    end
end
for _, frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "ForeverDex")
        break
    end
end
assert(env.ForeverDexDB.version == 2 and ns.Duel and ns.DuelFight and #ns.Catalog.bonusSlots >= 139)
print("TOC initialization smoke passed")
