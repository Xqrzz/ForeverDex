local _, ns = ...
ns.Module(function()
local L, Art = ns.L, ns.Art
local Settings = {}
ns.Settings = Settings

-- Default values. Multiple choices are strings, checkboxes are booleans.
local DEFAULTS = {
    animation = "full",       -- full, quick, off
    chatMessage = true,
    toast = true,
    sounds = true,
    confirmReplace = true,
    language = "auto",
    minimapShow = true,
    minimapLock = false,
    portraitButton = "always", -- always, missing, off
    ownedMarker = true,
    windowScale = 1,
    duelRequests = "ask",      -- ask, refuse
    duelCombatRefuse = true,
    duelAnimation = true,
    duelVsBurst = true,
    duelSounds = true,
}
Settings.DEFAULTS = DEFAULTS

local listeners = {}

local function store()
    if not ForeverDexDB then return end
    ForeverDexDB.settings = ForeverDexDB.settings or {}
    return ForeverDexDB.settings
end

function Settings.Get(key)
    local saved = ForeverDexDB and ForeverDexDB.settings
    local value = saved and saved[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

function Settings.Set(key, value)
    local saved = store()
    if not saved then return end
    if value == DEFAULTS[key] then value = nil end
    saved[key] = value
    for _, listener in ipairs(listeners) do listener(key, Settings.Get(key)) end
end

-- Notifies a module when an option changes (and once on load, key = nil).
function Settings.OnChange(listener)
    listeners[#listeners + 1] = listener
end

function Settings.ApplyAll()
    for _, listener in ipairs(listeners) do listener(nil) end
end

function Settings.ResetAll()
    if ForeverDexDB then ForeverDexDB.settings = nil end
    Settings.ApplyAll()
    if Settings.RefreshPanel then Settings.RefreshPanel() end
end

-- Options panel -------------------------------------------------------------------

local panel = CreateFrame("Frame", "ForeverDexSettingsPanel")
panel.name = "ForeverDex"
panel:Hide()
local controls = {}

local function create(frameType, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
    if ok and frame then return frame, true end
    return CreateFrame(frameType, nil, parent), false
end

-- Header: addon orb, title and subtitle on a gold gradient.
local header = panel:CreateTexture(nil, "BACKGROUND")
header:SetPoint("TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", 0, 0)
header:SetHeight(72)
Art.Gradient(header, 1, 0.8, 0.4, 0, 0.14)
local orb = panel:CreateTexture(nil, "ARTWORK")
orb:SetSize(48, 48)
orb:SetPoint("TOPLEFT", 16, -12)
Art.SmoothTexture(orb, "Interface\\AddOns\\ForeverDex\\Media\\Ball")
local title = panel:CreateFontString(nil, "ARTWORK", _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
title:SetPoint("TOPLEFT", orb, "TOPRIGHT", 12, -4)
title:SetText("ForeverDex")
local version = C_AddOns and C_AddOns.GetAddOnMetadata("ForeverDex", "Version")
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetText(version and (L.SETTINGS_SUBTITLE .. L.SEPARATOR .. "v" .. version) or L.SETTINGS_SUBTITLE)
subtitle:SetTextColor(0.75, 0.75, 0.75)

local COLUMN_W = 300
local columns = {
    { x = 20, y = -84 },
    { x = 20 + COLUMN_W + 30, y = -84 },
}

local function place(column, frame, height, indent)
    local spot = columns[column]
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", spot.x + (indent or 0), spot.y)
    spot.y = spot.y - height
end

-- Gold section title underlined with a rule, like in the game's options.
local function section(column, label)
    local spot = columns[column]
    if spot.y < -84 then spot.y = spot.y - 10 end
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetText(label)
    text:SetJustifyH("LEFT")
    place(column, text, 22)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetSize(COLUMN_W, 1)
    line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    line:SetColorTexture(1, 0.82, 0, 0.35)
    columns[column].y = columns[column].y - 8
end

local function tooltip(frame, label, description)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(description, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function checkbox(column, key, label, description)
    local box = create("CheckButton", panel, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    place(column, box, 28)
    local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 4, 1)
    text:SetText(label)
    box:SetHitRectInsets(0, -260, 0, 0)
    box:SetScript("OnClick", function(self)
        Settings.Set(key, self:GetChecked() and true or false)
        Art.Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    end)
    if description then tooltip(box, label, description) end
    controls[#controls + 1] = function() box:SetChecked(Settings.Get(key)) end
    return box
end

-- Multiple choice: label, then the game's dropdown menu (radio buttons).
local function choice(column, key, label, options, description)
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetText(label)
    place(column, text, 18, 4)
    local menu, native = create("DropdownButton", panel, "WowStyle1DropdownTemplate")
    menu:SetSize(220, 26)
    place(column, menu, 34, 4)
    if native and menu.SetupMenu then
        local function isSelected(value) return Settings.Get(key) == value end
        local function select(value) Settings.Set(key, value) end
        menu:SetupMenu(function(_, root)
            for _, option in ipairs(options) do
                root:CreateRadio(option[2], isSelected, select, option[1])
            end
        end)
        controls[#controls + 1] = function()
            if menu.GenerateMenu then menu:GenerateMenu() end
            for _, option in ipairs(options) do
                if option[1] == Settings.Get(key) and menu.SetDefaultText then
                    menu:SetDefaultText(option[2])
                end
            end
        end
    else
        -- Client without modern menus: a button that cycles through the choices.
        local cycle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        cycle:SetAllPoints(menu)
        local function current()
            for i, option in ipairs(options) do
                if option[1] == Settings.Get(key) then return i, option end
            end
            return 1, options[1]
        end
        cycle:SetScript("OnClick", function()
            local index = current()
            Settings.Set(key, options[index % #options + 1][1])
            Settings.RefreshPanel()
        end)
        controls[#controls + 1] = function()
            local _, option = current()
            cycle:SetText(option[2])
        end
    end
    if description then tooltip(menu, label, description) end
end

local function action(column, label, width, onClick, description)
    local control = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetText(label)
    control:SetScript("OnClick", onClick)
    place(column, control, 32, 4)
    if description then tooltip(control, label, description) end
    return control
end

-- Left column: capture and comparison.
section(1, L.SETTINGS_CAPTURE)
choice(1, "animation", L.SETTINGS_ANIMATION, {
    { "full", L.SETTINGS_ANIMATION_FULL },
    { "quick", L.SETTINGS_ANIMATION_QUICK },
    { "off", L.SETTINGS_ANIMATION_OFF },
}, L.SETTINGS_ANIMATION_TIP)
checkbox(1, "chatMessage", L.SETTINGS_CHAT, L.SETTINGS_CHAT_TIP)
checkbox(1, "toast", L.SETTINGS_TOAST, L.SETTINGS_TOAST_TIP)
checkbox(1, "sounds", L.SETTINGS_SOUNDS, L.SETTINGS_SOUNDS_TIP)
checkbox(1, "confirmReplace", L.SETTINGS_CONFIRM, L.SETTINGS_CONFIRM_TIP)

section(1, L.SETTINGS_DUEL)
choice(1, "duelRequests", L.SETTINGS_DUEL_REQUESTS, {
    { "ask", L.SETTINGS_DUEL_ASK },
    { "refuse", L.SETTINGS_DUEL_REFUSE },
}, L.SETTINGS_DUEL_REQUESTS_TIP)
checkbox(1, "duelCombatRefuse", L.SETTINGS_DUEL_COMBAT, L.SETTINGS_DUEL_COMBAT_TIP)
checkbox(1, "duelAnimation", L.SETTINGS_DUEL_ANIMATION, L.SETTINGS_DUEL_ANIMATION_TIP)
checkbox(1, "duelVsBurst", L.SETTINGS_DUEL_BURST, L.SETTINGS_DUEL_BURST_TIP)
checkbox(1, "duelSounds", L.SETTINGS_DUEL_SOUNDS, L.SETTINGS_DUEL_SOUNDS_TIP)

-- Right column: interface and data.
section(2, L.SETTINGS_INTERFACE)
local languages = { { "auto", L.SETTINGS_LANGUAGE_AUTO } }
for _, language in ipairs(ns.LANGUAGES) do languages[#languages + 1] = language end
choice(2, "language", L.SETTINGS_LANGUAGE, languages, L.SETTINGS_LANGUAGE_TIP)
checkbox(2, "minimapShow", L.SETTINGS_MINIMAP_SHOW, L.SETTINGS_MINIMAP_SHOW_TIP)
checkbox(2, "minimapLock", L.SETTINGS_MINIMAP_LOCK, L.SETTINGS_MINIMAP_LOCK_TIP)
choice(2, "portraitButton", L.SETTINGS_PORTRAIT, {
    { "always", L.SETTINGS_PORTRAIT_ALWAYS },
    { "missing", L.SETTINGS_PORTRAIT_MISSING },
    { "off", L.SETTINGS_PORTRAIT_OFF },
}, L.SETTINGS_PORTRAIT_TIP)
checkbox(2, "ownedMarker", L.SETTINGS_OWNED, L.SETTINGS_OWNED_TIP)
local scales = {}
for _, value in ipairs({ 0.8, 0.9, 1, 1.1, 1.2 }) do
    scales[#scales + 1] = { value, L.PERCENT:format(math.floor(value * 100 + 0.5)) }
end
choice(2, "windowScale", L.SETTINGS_SCALE, scales, L.SETTINGS_SCALE_TIP)

section(2, L.SETTINGS_DATA)
action(2, L.SETTINGS_OPEN, 220, function() if ns.UI then ns.UI.Toggle() end end)
action(2, L.SETTINGS_DEFAULTS, 220, function() Settings.ResetAll() end, L.SETTINGS_DEFAULTS_TIP)
local reset = action(2, L.SETTINGS_RESET, 220, function()
    local count = 0
    for _ in pairs(ForeverDexDB and ForeverDexDB.cards or {}) do count = count + 1 end
    if count > 0 then StaticPopup_Show("FOREVERDEX_RESET", count) end
end, L.SETTINGS_RESET_TIP)
local resetLabel = reset:GetFontString()
if resetLabel then resetLabel:SetTextColor(1, 0.35, 0.3) end

function Settings.RefreshPanel()
    for _, refresh in ipairs(controls) do refresh() end
end
panel:SetScript("OnShow", Settings.RefreshPanel)
-- Callbacks expected by the game's options panel.
panel.OnCommit = function() end
panel.OnRefresh = Settings.RefreshPanel
panel.OnDefault = Settings.ResetAll

-- Collection reset: two successive confirmations.
StaticPopupDialogs["FOREVERDEX_RESET"] = {
    text = L.RESET_PROMPT,
    button1 = L.SETTINGS_RESET,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        -- The first dialog must be closed before opening the second.
        C_Timer.After(0, function() StaticPopup_Show("FOREVERDEX_RESET_CONFIRM") end)
    end,
}
StaticPopupDialogs["FOREVERDEX_RESET_CONFIRM"] = {
    text = L.RESET_CONFIRM,
    button1 = YES or "Oui",
    button2 = NO or "Non",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function() ns.Collection.Reset() end,
}

-- The interface is built once per load, so a new language needs a reload.
StaticPopupDialogs["FOREVERDEX_RELOAD"] = {
    text = L.RELOAD_PROMPT,
    button1 = L.RELOAD,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function() ReloadUI() end,
}
Settings.OnChange(function(key)
    if key == "language" then StaticPopup_Show("FOREVERDEX_RELOAD") end
end)

-- Registration in Options → AddOns.
local category
if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
    category = _G.Settings.RegisterCanvasLayoutCategory(panel, "ForeverDex")
    _G.Settings.RegisterAddOnCategory(category)
end

function Settings.Open()
    if category and _G.Settings.OpenToCategory then
        _G.Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    end
end

Settings.Panel = panel
end)
