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
    achievementToast = true,
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
    -- Presence: the glowing icon above nearby ForeverDex players (Presence.lua).
    presenceAnnounce = true,   -- answer the other addons, so they can see us
    presenceShow = true,       -- show the icon above the players who answered
    presenceIcon = "orb",      -- orb, emblem, star, book
    presenceIntensity = 1,     -- strength of the glow, 0 to 1.5
    presenceAlpha = 1,         -- opacity of the whole icon, 0.2 to 1
    presenceSize = 1,          -- scale of the icon, 0.6 to 1.6
    presenceRange = 30,        -- detection distance in yards: 10, 30 or 40
    presenceHeight = 0,        -- pixels added to the icon's height above the bar
    presenceDuration = 0,      -- 0 = permanent, otherwise seconds of the ping
    -- Share: captures and achievements announced to other players (Share.lua).
    shareCaptures = false,
    shareCaptureChannel = "guild",     -- guild, group, custom
    shareCaptureScope = "new",         -- new (first card only), all (replacements too)
    shareBonus = true,
    sharePets = true,
    shareAchievements = false,
    shareAchievementChannel = "guild", -- guild, group, custom
    shareAchievementMin = 0,           -- minimum points of an announced achievement
    shareCustomChannel = "",           -- name of a channel the player joined, never an official one
    shareCooldown = 30,                -- seconds between two announcements of the same kind
    shareTag = true,                   -- "[ForeverDex]" in front of the message
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
--
-- The builders below work on columns: { frame, x, y }. A column remembers where its
-- next control goes, so the main panel and its sub-pages share the same helpers.

local panel = CreateFrame("Frame", "ForeverDexSettingsPanel")
panel.name = "ForeverDex"
panel:Hide()
local controls = {}

local function create(frameType, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
    if ok and frame then return frame, true end
    return CreateFrame(frameType, nil, parent), false
end

local TOP = -84
local COLUMN_W = 300

-- Header: addon orb, title and subtitle on a gold gradient.
local function header(frame, titleText, subtitleText)
    local band = frame:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", 0, 0)
    band:SetHeight(72)
    Art.Gradient(band, 1, 0.8, 0.4, 0, 0.14)
    local orb = frame:CreateTexture(nil, "ARTWORK")
    orb:SetSize(48, 48)
    orb:SetPoint("TOPLEFT", 16, -12)
    Art.SmoothTexture(orb, "Interface\\AddOns\\ForeverDex\\Media\\Ball")
    local title = frame:CreateFontString(nil, "ARTWORK", _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", orb, "TOPRIGHT", 12, -4)
    title:SetText(titleText)
    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(subtitleText)
    subtitle:SetTextColor(0.75, 0.75, 0.75)
end

local version = C_AddOns and C_AddOns.GetAddOnMetadata("ForeverDex", "Version")
header(panel, "ForeverDex", version and (L.SETTINGS_SUBTITLE .. L.SEPARATOR .. "v" .. version) or L.SETTINGS_SUBTITLE)

local function column(frame, x)
    return { frame = frame, x = x, y = TOP }
end

local function place(spot, frame, height, indent)
    frame:SetPoint("TOPLEFT", spot.frame, "TOPLEFT", spot.x + (indent or 0), spot.y)
    spot.y = spot.y - height
end

-- Gold section title underlined with a rule, like in the game's options.
local function section(spot, label)
    if spot.y < TOP then spot.y = spot.y - 10 end
    local text = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetText(label)
    text:SetJustifyH("LEFT")
    place(spot, text, 22)
    local line = spot.frame:CreateTexture(nil, "ARTWORK")
    line:SetSize(COLUMN_W, 1)
    line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    line:SetColorTexture(1, 0.82, 0, 0.35)
    spot.y = spot.y - 8
end

-- A description on several lines lists choices: "Name: what it does", one per line.
-- The game's tooltips have no bold, so the name stands out in gold. A description on
-- one line (an intro, or a translation not split yet) is shown as it is.
local function addDescription(description)
    if not description:find("\n", 1, true) then
        GameTooltip:AddLine(description, 1, 1, 1, true)
        return
    end
    for line in description:gmatch("[^\n]+") do
        -- The separator is kept as written: "Name: " in English, "Nom : " in French.
        local name, separator, text = line:match("^(.-)(%s*:%s+)(.+)$")
        if name and name ~= "" then
            GameTooltip:AddLine("|cffffd100" .. name .. "|r" .. separator .. text, 1, 1, 1, true)
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
end

local function tooltip(frame, label, description)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        addDescription(description)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function checkbox(spot, key, label, description)
    local box = create("CheckButton", spot.frame, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    place(spot, box, 28)
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
local function choice(spot, key, label, options, description)
    local text = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetText(label)
    place(spot, text, 18, 4)
    local menu, native = create("DropdownButton", spot.frame, "WowStyle1DropdownTemplate")
    menu:SetSize(220, 26)
    place(spot, menu, 34, 4)
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
        local cycle = CreateFrame("Button", nil, spot.frame, "UIPanelButtonTemplate")
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

-- Slider drawn by hand (the game's slider templates differ between clients):
-- label and value on one line, then the bar. format(value) gives the shown value.
local function slider(spot, key, label, low, high, step, format, description)
    local text = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetText(label)
    place(spot, text, 20, 4)
    local shown = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    shown:SetPoint("TOPLEFT", spot.frame, "TOPLEFT", spot.x + 224, spot.y + 20)
    shown:SetWidth(60)
    shown:SetJustifyH("RIGHT")

    local bar = CreateFrame("Slider", nil, spot.frame)
    bar:SetOrientation("HORIZONTAL")
    bar:SetSize(280, 16)
    bar:SetHitRectInsets(0, 0, -6, -6)
    place(spot, bar, 30, 4)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0, 0, 0, 0.6)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(32, 32)
    bar:SetThumbTexture(thumb)
    -- The fill ends under the handle: the game keeps the handle inside the bar, so its
    -- centre does not travel the full width and a computed width drifts from it.
    local fill = bar:CreateTexture(nil, "BORDER")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(6)
    fill:SetColorTexture(1, 0.75, 0.2, 0.75)
    bar:SetMinMaxValues(low, high)
    bar:SetValueStep(step)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end

    local updating = false
    local function show(value)
        shown:SetText(format(value))
    end
    bar:SetScript("OnValueChanged", function(_, value)
        -- Rounded to the step, then to two decimals so 0.05 steps compare exactly.
        value = tonumber(("%.2f"):format(math.floor(value / step + 0.5) * step))
        show(value)
        if not updating and Settings.Get(key) ~= value then Settings.Set(key, value) end
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(high, math.max(low, self:GetValue() + delta * step)))
    end)
    if description then tooltip(bar, label, description) end
    controls[#controls + 1] = function()
        updating = true
        bar:SetValue(Settings.Get(key))
        show(Settings.Get(key))
        updating = false
    end
    return bar
end

-- One-line text field: label, then the box. The value is saved trimmed on Enter or when
-- the box loses focus; Escape puts the saved value back.
local function input(spot, key, label, description, maxLetters)
    local text = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetText(label)
    place(spot, text, 20, 4)
    local box, native = create("EditBox", spot.frame, "InputBoxTemplate")
    box:SetSize(214, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters or 64)
    if not native then box:SetFontObject("ChatFontNormal") end
    -- The template draws its left border outside the box.
    place(spot, box, 28, 10)
    local function commit(self)
        local value = (self:GetText() or ""):match("^%s*(.-)%s*$")
        self:SetText(value)
        if Settings.Get(key) ~= value then Settings.Set(key, value) end
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(Settings.Get(key) or "")
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", commit)
    if description then tooltip(box, label, description) end
    controls[#controls + 1] = function()
        if not box:HasFocus() then box:SetText(Settings.Get(key) or "") end
    end
    return box
end

-- Small grey text wrapped to the column width, for hints under a group of controls.
local function note(spot, value, height)
    local text = spot.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetWidth(COLUMN_W - 8)
    text:SetJustifyH("LEFT")
    text:SetTextColor(0.75, 0.75, 0.75)
    text:SetText(value)
    place(spot, text, height, 4)
    return text
end

local function action(spot, label, width, onClick, description)
    local control = CreateFrame("Button", nil, spot.frame, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetText(label)
    control:SetScript("OnClick", onClick)
    place(spot, control, 32, 4)
    if description then tooltip(control, label, description) end
    return control
end

local left, right = column(panel, 20), column(panel, 20 + COLUMN_W + 30)

-- Left column: capture and comparison.
section(left, L.SETTINGS_CAPTURE)
choice(left, "animation", L.SETTINGS_ANIMATION, {
    { "full", L.SETTINGS_ANIMATION_FULL },
    { "quick", L.SETTINGS_ANIMATION_QUICK },
    { "off", L.SETTINGS_ANIMATION_OFF },
}, L.SETTINGS_ANIMATION_TIP)
checkbox(left, "chatMessage", L.SETTINGS_CHAT, L.SETTINGS_CHAT_TIP)
checkbox(left, "toast", L.SETTINGS_TOAST, L.SETTINGS_TOAST_TIP)
checkbox(left, "achievementToast", L.SETTINGS_ACHIEVEMENTS, L.SETTINGS_ACHIEVEMENTS_TIP)
checkbox(left, "sounds", L.SETTINGS_SOUNDS, L.SETTINGS_SOUNDS_TIP)
checkbox(left, "confirmReplace", L.SETTINGS_CONFIRM, L.SETTINGS_CONFIRM_TIP)

section(left, L.SETTINGS_DUEL)
choice(left, "duelRequests", L.SETTINGS_DUEL_REQUESTS, {
    { "ask", L.SETTINGS_DUEL_ASK },
    { "refuse", L.SETTINGS_DUEL_REFUSE },
}, L.SETTINGS_DUEL_REQUESTS_TIP)
checkbox(left, "duelCombatRefuse", L.SETTINGS_DUEL_COMBAT, L.SETTINGS_DUEL_COMBAT_TIP)
checkbox(left, "duelAnimation", L.SETTINGS_DUEL_ANIMATION, L.SETTINGS_DUEL_ANIMATION_TIP)
checkbox(left, "duelVsBurst", L.SETTINGS_DUEL_BURST, L.SETTINGS_DUEL_BURST_TIP)
checkbox(left, "duelSounds", L.SETTINGS_DUEL_SOUNDS, L.SETTINGS_DUEL_SOUNDS_TIP)

-- Right column: interface and data.
section(right, L.SETTINGS_INTERFACE)
local languages = { { "auto", L.SETTINGS_LANGUAGE_AUTO } }
for _, language in ipairs(ns.LANGUAGES) do languages[#languages + 1] = language end
choice(right, "language", L.SETTINGS_LANGUAGE, languages, L.SETTINGS_LANGUAGE_TIP)
checkbox(right, "minimapShow", L.SETTINGS_MINIMAP_SHOW, L.SETTINGS_MINIMAP_SHOW_TIP)
checkbox(right, "minimapLock", L.SETTINGS_MINIMAP_LOCK, L.SETTINGS_MINIMAP_LOCK_TIP)
choice(right, "portraitButton", L.SETTINGS_PORTRAIT, {
    { "always", L.SETTINGS_PORTRAIT_ALWAYS },
    { "missing", L.SETTINGS_PORTRAIT_MISSING },
    { "off", L.SETTINGS_PORTRAIT_OFF },
}, L.SETTINGS_PORTRAIT_TIP)
checkbox(right, "ownedMarker", L.SETTINGS_OWNED, L.SETTINGS_OWNED_TIP)
local scales = {}
for _, value in ipairs({ 0.8, 0.9, 1, 1.1, 1.2 }) do
    scales[#scales + 1] = { value, L.PERCENT:format(math.floor(value * 100 + 0.5)) }
end
choice(right, "windowScale", L.SETTINGS_SCALE, scales, L.SETTINGS_SCALE_TIP)

section(right, L.SETTINGS_DATA)
action(right, L.SETTINGS_OPEN, 220, function() if ns.UI then ns.UI.Toggle() end end)
action(right, L.SETTINGS_DEFAULTS, 220, function() Settings.ResetAll() end, L.SETTINGS_DEFAULTS_TIP)
local reset = action(right, L.SETTINGS_RESET, 220, function()
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

-- The game's options window assumes it was opened from the Escape menu: on this client
-- it brings that menu up with it, and closing the window goes back to it. When
-- ForeverDex opens the window (minimap icon, /fdex options) and the menu was closed,
-- the menu is closed again, at the opening and when the window closes. A window opened
-- from the Escape menu keeps the game's behaviour.
local strayMenu = false -- the window was opened by us, the Escape menu was closed

local function closeStrayMenu()
    if not strayMenu or not GameMenuFrame or InCombatLockdown() then return end
    if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
end

local watching = false
local function watchWindow()
    if watching or not SettingsPanel then return end
    watching = true
    SettingsPanel:HookScript("OnHide", function()
        if not strayMenu then return end
        -- The game shows the menu right after hiding the window: one frame later.
        C_Timer.After(0, function()
            closeStrayMenu()
            strayMenu = false
        end)
    end)
end

-- The options window is protected in combat: the request waits for the end of combat.
local pendingId, openCategory
local combatWatcher = CreateFrame("Frame")
combatWatcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local id = pendingId
    pendingId = nil
    if id then openCategory(id) end
end)

function openCategory(id)
    if InCombatLockdown() then
        if not pendingId then
            DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. L.SETTINGS_AFTER_COMBAT)
        end
        pendingId = id
        combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local menuShown = GameMenuFrame and GameMenuFrame:IsShown()
    local windowShown = SettingsPanel and SettingsPanel:IsShown()
    if not windowShown then strayMenu = not menuShown end
    _G.Settings.OpenToCategory(id)
    watchWindow()
    C_Timer.After(0, closeStrayMenu)
end

function Settings.Open()
    if category and _G.Settings.OpenToCategory then
        openCategory(category.GetID and category:GetID() or category.ID)
    end
end

-- Sub-page under ForeverDex in Options → AddOns, built with the same helpers.
-- Returns the page and its two columns; the page refreshes its controls when shown.
local pages = {}
function Settings.AddPage(name, subtitleText)
    local page = CreateFrame("Frame")
    page.name = name
    page.parent = "ForeverDex"
    page:Hide()
    header(page, name, subtitleText)
    page:SetScript("OnShow", Settings.RefreshPanel)
    page.OnCommit = function() end
    page.OnRefresh = Settings.RefreshPanel
    page.OnDefault = Settings.ResetAll
    local subcategory
    if category and _G.Settings.RegisterCanvasLayoutSubcategory then
        subcategory = _G.Settings.RegisterCanvasLayoutSubcategory(category, page, name)
    end
    pages[page] = subcategory
    return page, column(page, 20), column(page, 20 + COLUMN_W + 30)
end

function Settings.OpenPage(page)
    local subcategory = pages[page]
    if subcategory and _G.Settings.OpenToCategory then
        openCategory(subcategory.GetID and subcategory:GetID() or subcategory.ID)
    else
        Settings.Open()
    end
end

Settings.Builder = {
    section = section, checkbox = checkbox, choice = choice, slider = slider,
    input = input, note = note, action = action, tooltip = tooltip, place = place,
}
Settings.Panel = panel
end)
