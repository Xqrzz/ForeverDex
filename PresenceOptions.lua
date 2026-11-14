local _, ns = ...
ns.Module(function()
local L, Settings, Art, Presence, Icon, Util = ns.L, ns.Settings, ns.Art, ns.Presence, ns.PresenceIcon, ns.Util
local look, play, stop, setLayer, isActive = Icon.look, Icon.Play, Icon.Stop, Icon.SetLayer, Icon.IsActive
local safe = Util.Safe

-- Options page with a live preview ----------------------------------------------------

local page, left, right = Settings.AddPage(L.PRESENCE_TITLE, L.PRESENCE_SUBTITLE)
local B = Settings.Builder

B.section(left, L.PRESENCE_SECTION)
B.checkbox(left, "presenceAnnounce", L.PRESENCE_ANNOUNCE, L.PRESENCE_ANNOUNCE_TIP)
B.checkbox(left, "presenceShow", L.PRESENCE_SHOW, L.PRESENCE_SHOW_TIP)

B.section(left, L.PRESENCE_LOOK)
local iconChoices = {}
for _, icon in ipairs(Icon.CHOICES) do iconChoices[#iconChoices + 1] = { icon[1], icon[2] } end
B.choice(left, "presenceIcon", L.PRESENCE_ICON, iconChoices, L.PRESENCE_ICON_TIP)
B.choice(left, "presenceRange", L.PRESENCE_RANGE, {
    { 10, L.PRESENCE_RANGE_YARDS:format(10) },
    { 30, L.PRESENCE_RANGE_YARDS:format(30) },
    { Presence.FAR, L.PRESENCE_RANGE_YARDS:format(Presence.FAR) },
}, L.PRESENCE_RANGE_TIP)
B.choice(left, "presenceDuration", L.PRESENCE_DURATION, {
    { 0, L.PRESENCE_PERMANENT },
    { 3, L.PRESENCE_PING:format(3) },
    { 5, L.PRESENCE_PING:format(5) },
    { 10, L.PRESENCE_PING:format(10) },
}, L.PRESENCE_DURATION_TIP)
local function percent(value) return L.PERCENT:format(math.floor(value * 100 + 0.5)) end
B.slider(left, "presenceIntensity", L.PRESENCE_INTENSITY, 0, 1.5, 0.05, percent, L.PRESENCE_INTENSITY_TIP)
B.slider(left, "presenceAlpha", L.PRESENCE_ALPHA, 0.2, 1, 0.05, percent, L.PRESENCE_ALPHA_TIP)
B.slider(left, "presenceSize", L.PRESENCE_SIZE, 0.6, 1.6, 0.05, percent, L.PRESENCE_SIZE_TIP)
B.slider(left, "presenceHeight", L.PRESENCE_HEIGHT, -20, 40, 1, function(value)
    return L.PRESENCE_PIXELS:format(value)
end, L.PRESENCE_HEIGHT_TIP)

-- Preview: the player's own character under the icon, in a small scene.
B.section(right, L.PRESENCE_PREVIEW)
local stage = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate" or nil)
stage:SetSize(300, 300)
B.place(right, stage, 308)
if stage.SetBackdrop then
    stage:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    stage:SetBackdropColor(0.04, 0.05, 0.08, 0.92)
    stage:SetBackdropBorderColor(1, 0.82, 0.3, 0.6)
end
local floor = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
floor:SetPoint("BOTTOMLEFT", 4, 4)
floor:SetPoint("BOTTOMRIGHT", -4, 4)
floor:SetHeight(110)
Art.Gradient(floor, 0.35, 0.3, 0.2, 0.35, 0, "VERTICAL")

local okModel, model = pcall(CreateFrame, "PlayerModel", nil, stage)
if okModel and model then
    model:SetPoint("TOPLEFT", 6, -82)
    model:SetPoint("BOTTOMRIGHT", -6, 6)
end

local preview = Icon.Create(stage)
preview.frame:SetPoint("TOP", stage, "TOP", 0, -40)
setLayer(preview, nil, stage:GetFrameLevel() + 20)

local nameLabel = stage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nameLabel:SetPoint("TOP", stage, "TOP", 0, -70)
nameLabel:SetTextColor(0.25, 1, 0.25)

local hint = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetWidth(300)
hint:SetJustifyH("LEFT")
hint:SetTextColor(0.75, 0.75, 0.75)
hint:SetText(L.PRESENCE_LIMITS)
B.place(right, hint, 70, 0)

local replay = B.action(right, L.PRESENCE_REPLAY, 180, function()
    stop(preview, true)
    play(preview, look.duration)
end)

-- In-game test: starting it closes the options so the city shows; the banner at the
-- top of the screen stops it and brings this page back.
local demoButton = B.action(right, L.PRESENCE_DEMO, 180, function()
    local starting = not Presence.IsDemo()
    Presence.ToggleDemo()
    if starting and SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
end, L.PRESENCE_DEMO_TIP)

function Presence.OpenOptions()
    Settings.OpenPage(page)
end

function Presence.RefreshDemoButton()
    demoButton:SetText(Presence.IsDemo() and L.PRESENCE_DEMO_STOP or L.PRESENCE_DEMO)
end
page:HookScript("OnShow", Presence.RefreshDemoButton)

-- In ping mode the preview starts again shortly after each ping.
preview.onDone = function()
    C_Timer.After(1.2, function()
        if page:IsVisible() and not isActive(preview) then play(preview, look.duration) end
    end)
end

local PREVIEW_TOP = -40

function Presence.RefreshPreview()
    if not page:IsVisible() then return end
    preview.frame:SetPoint("TOP", stage, "TOP", 0, PREVIEW_TOP + look.height)
    replay:SetEnabled(look.duration > 0)
    if not isActive(preview) or (look.duration == 0) ~= (preview.duration == 0) then
        stop(preview, true)
        play(preview, look.duration)
    end
end

page:HookScript("OnShow", function()
    if model then
        pcall(model.SetUnit, model, "player")
        pcall(model.SetFacing, model, -0.35)
        if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
    end
    nameLabel:SetText(safe(UnitName, "player") or "")
    stop(preview, true)
    play(preview, look.duration)
    Presence.RefreshPreview()
end)
page:HookScript("OnHide", function() stop(preview, true) end)

Presence.Page = page
end)
