local _, ns = ...
ns.Module(function()
local L, Art = ns.L, ns.Art
local Icon = {}
ns.PresenceIcon = Icon

-- The glowing icon of Presence.lua, drawn on the nameplates and in the preview of the
-- Collectors options (PresenceOptions.lua). Presence.lua fills Icon.look from the
-- settings; this file only draws.

local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"

-- Icon choices: key, label, texture, blend mode (BLEND when absent), game file.
-- A square game icon (INV_Misc_Book_09) made round crashed this client
-- (ACCESS_VIOLATION), with a mask texture as with SetPortraitToTexture: only images
-- already round. The game's files get no TRILINEAR filter, in case it played a part.
-- A saved choice that no longer exists falls back to the orb.
local ICONS = {
    { "orb", L.PRESENCE_ICON_ORB, MEDIA .. "Ball" },
    { "spark", L.PRESENCE_ICON_SPARK, "Interface\\Cooldown\\star4", "ADD", true },
}
-- The raid target markers, under their names in the game's language.
local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
for i, english in ipairs(MARKER_NAMES) do
    ICONS[#ICONS + 1] = { "marker" .. i, _G["RAID_TARGET_" .. i] or english,
        "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i, nil, true }
end
local ICON_BY_KEY = {}
for _, icon in ipairs(ICONS) do ICON_BY_KEY[icon[1]] = icon end

local GOLD = { 1, 0.82, 0.35 }

-- Settings the icons are drawn with, kept up to date by Presence.lua (readLook).
local look = {}

-- Icon ------------------------------------------------------------------------------
--
-- Layers from back to front: halo, rotating star, ping wave, the icon itself, a glint.
-- The endless motions (float, breathing, rotation, waves, glint) are animation groups
-- the game runs by itself. Lua only drives the arrival (fade and pop), the departure
-- and the timer of a ping: a permanent icon costs nothing once it has arrived.
-- The same object serves the nameplates and the preview.

local active = {} -- icons shown, arriving, steady or leaving
local moving = {} -- icons Lua still has to move: arriving, leaving, or on a timer
-- Runs while an icon is moving: hidden otherwise, it costs nothing.
local driver

local FADE_IN, FADE_OUT, POP = 0.35, 0.8, 0.35
local WAVE_PERIOD = 2.4
local sin, max, min, pi = math.sin, math.max, math.min, math.pi

local function layer(frame, file, drawLayer, sublevel, blend)
    local texture = frame:CreateTexture(nil, drawLayer, nil, sublevel)
    texture:SetTexture(file)
    texture:SetBlendMode(blend or "ADD")
    texture:SetPoint("CENTER")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

local function setIconTexture(icon, choice)
    if icon.choice == choice then return end
    icon.choice = choice
    local core = icon.core
    if choice[5] then core:SetTexture(choice[3]) else Art.SmoothTexture(core, choice[3]) end
    core:SetBlendMode(choice[4] or "BLEND")
    core:SetVertexColor(1, 1, 1, 1)
    if choice[4] == "ADD" then core:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
end

local function loop(icon, region, looping)
    local group = region:CreateAnimationGroup()
    group:SetLooping(looping)
    icon.loops[#icon.loops + 1] = group
    return group
end

local function animation(group, kind, duration, order, smoothing)
    local step = group:CreateAnimation(kind)
    step:SetDuration(duration)
    step:SetOrder(order or 1)
    if smoothing then step:SetSmoothing(smoothing) end
    return step
end

local function scaleTo(step, factor)
    if step.SetScaleFrom then
        step:SetScaleFrom(1, 1)
        step:SetScaleTo(factor, factor)
    else
        step:SetScale(factor, factor)
    end
end

local function createIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame:Hide()
    -- The layers sit on body, which floats: one translation moves them all.
    local body = CreateFrame("Frame", nil, frame)
    body:SetSize(1, 1)
    body:SetPoint("CENTER")
    local icon = { frame = frame, body = body, loops = {} }
    icon.halo = layer(body, MEDIA .. "Glow", "BACKGROUND", 0)
    icon.star = layer(body, "Interface\\Cooldown\\star4", "BACKGROUND", 1)
    icon.wave = layer(body, MEDIA .. "Ring", "BORDER", 0)
    icon.core = layer(body, MEDIA .. "Ball", "ARTWORK", 0, "BLEND")
    icon.glint = layer(body, MEDIA .. "Glow", "OVERLAY", 1)
    -- Gold light; each layer's alpha is animated.
    for _, texture in ipairs({ icon.halo, icon.star, icon.wave, icon.glint }) do
        texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        texture:SetAlpha(0)
    end

    -- Slow float, up and down.
    icon.float = animation(loop(icon, body, "BOUNCE"), "Translation", pi / 1.8, 1, "IN_OUT")

    -- Halo breathing behind the icon.
    local breath = loop(icon, icon.halo, "BOUNCE")
    scaleTo(animation(breath, "Scale", pi / 2.6, 1, "IN_OUT"), 2.55 / 2.3)
    icon.haloFade = animation(breath, "Alpha", pi / 2.6, 1, "IN_OUT")

    -- Slowly turning star, its light pulsing on its own rhythm.
    animation(loop(icon, icon.star, "REPEAT"), "Rotation", 4 * pi):SetDegrees(360)
    icon.starFade = animation(loop(icon, icon.star, "BOUNCE"), "Alpha", pi / 1.7, 1, "IN_OUT")

    -- A wave every 2.4 s, stronger the first time.
    local wave = loop(icon, icon.wave, "REPEAT")
    scaleTo(animation(wave, "Scale", WAVE_PERIOD), 2.7 / 0.9)
    icon.waveFade = animation(wave, "Alpha", WAVE_PERIOD)
    icon.waveFade:SetToAlpha(0)
    wave:SetScript("OnLoop", function()
        icon.waveFade:SetFromAlpha(min(1, (icon.glow or 1) * 0.55))
    end)

    -- Small glint passing over the icon every few seconds.
    local glint = loop(icon, icon.glint, "REPEAT")
    icon.glintIn = animation(glint, "Alpha", 0.35, 1, "IN")
    icon.glintIn:SetFromAlpha(0)
    icon.glintOut = animation(glint, "Alpha", 0.35, 2, "OUT")
    icon.glintOut:SetToAlpha(0)
    local rest = animation(glint, "Alpha", 2 * pi / 1.3 - 0.7, 3)
    rest:SetFromAlpha(0)
    rest:SetToAlpha(0)
    return icon
end

-- Strata and level of the icon; body stays just in front of its frame.
local function setLayer(icon, strata, level)
    if strata then icon.frame:SetFrameStrata(strata) end
    icon.frame:SetFrameLevel(level)
    icon.body:SetFrameLevel(level + 1)
end

local function startLoops(icon, arriving)
    icon.waveFade:SetFromAlpha(min(1, icon.glow * 0.55 * (arriving and 1.6 or 1)))
    for _, group in ipairs(icon.loops) do
        group:Stop()
        group:Play()
    end
end

local function stopLoops(icon)
    for _, group in ipairs(icon.loops) do group:Stop() end
end

-- Applies the current look (icon, size, glow, opacity) to an icon.
local function restyle(icon)
    setIconTexture(icon, icon.forced or look.icon)
    local size = 30 * look.size * (icon.scale or 1)
    local glow = look.intensity
    local steady = icon.settled and not icon.leaving
    if steady then icon.frame:SetAlpha(look.alpha) end
    if icon.size == size and icon.glow == glow and icon.lookSize == look.size then return end
    icon.size, icon.glow, icon.lookSize = size, glow, look.size

    local amplitude = 2.5 * look.size
    icon.body:ClearAllPoints()
    icon.body:SetPoint("CENTER", icon.frame, "CENTER", 0, -amplitude)
    icon.float:SetOffset(0, 2 * amplitude)

    if steady then icon.core:SetSize(size, size) end
    icon.halo:SetSize(size * 2.3, size * 2.3)
    icon.haloFade:SetFromAlpha(min(1, glow * 0.45))
    icon.haloFade:SetToAlpha(min(1, glow * 0.7))
    icon.star:SetSize(size * 2.1, size * 2.1)
    icon.starFade:SetFromAlpha(min(1, glow * 0.25))
    icon.starFade:SetToAlpha(min(1, glow * 0.55))
    icon.wave:SetSize(size * 0.9, size * 0.9)
    icon.glint:SetSize(size * 0.9, size * 0.9)
    icon.glint:ClearAllPoints()
    icon.glint:SetPoint("CENTER", icon.body, "CENTER", size * 0.18, size * 0.18)
    icon.glintIn:SetToAlpha(min(1, glow * 0.8))
    icon.glintOut:SetFromAlpha(min(1, glow * 0.8))
    -- Animations read their values when they start: the loops start over.
    if icon.frame:IsShown() then startLoops(icon, false) end
end

-- Restyles every icon shown, after a change of settings.
local function restyleAll()
    for icon in pairs(active) do restyle(icon) end
end

local function hide(icon)
    active[icon], moving[icon] = nil, nil
    icon.frame:Hide()
    icon.leaving = nil
    stopLoops(icon)
end

-- Starts the icon: duration 0 = stays until Stop, otherwise fades out after it.
local function play(icon, duration)
    local fresh = not (icon.frame:IsShown() and icon.leaving == nil and active[icon])
    icon.duration = duration or 0
    icon.leaving = nil
    active[icon] = true
    if fresh then
        icon.start, icon.settled = GetTime(), nil
        icon.frame:SetAlpha(0)
    end
    restyle(icon)
    if fresh then
        icon.frame:Show()
        startLoops(icon, true)
    end
    moving[icon] = true
    if driver then driver:Show() end
end

-- Fades out, then hides.
local function stop(icon, immediate)
    if immediate then
        hide(icon)
        return
    end
    if active[icon] and not icon.leaving then
        icon.leaving = GetTime()
        moving[icon] = true
        if driver then driver:Show() end
    end
end

-- Size of the icon while it pops in.
local function pop(t)
    if t >= POP then return 1 end
    return 0.6 + 0.4 * sin(t / POP * pi / 2) + 0.12 * sin(t / POP * pi)
end

-- One frame of a moving icon. Returns false once it has faded out, nil once Lua has
-- nothing more to do for it, true otherwise.
local function animate(icon, now)
    local t = now - icon.start
    if icon.duration > 0 and not icon.leaving and t > icon.duration then icon.leaving = now end
    if icon.leaving then
        local envelope = min(1, t / FADE_IN) * max(0, 1 - (now - icon.leaving) / FADE_OUT)
        if envelope <= 0 then return false end
        icon.frame:SetAlpha(look.alpha * envelope)
        local size = icon.size * pop(t)
        icon.core:SetSize(size, size)
        return true
    end
    if t < FADE_IN or t < POP then
        icon.frame:SetAlpha(look.alpha * min(1, t / FADE_IN))
        local size = icon.size * pop(t)
        icon.core:SetSize(size, size)
        return true
    end
    if not icon.settled then
        icon.settled = true
        icon.frame:SetAlpha(look.alpha)
        icon.core:SetSize(icon.size, icon.size)
    end
    -- A ping still waits for its end; a permanent icon is left to its animations.
    if icon.duration > 0 then return true end
    return nil
end

driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    local now = GetTime()
    for icon in pairs(moving) do
        local state = animate(icon, now)
        if state == false then
            hide(icon)
            if icon.onDone then icon.onDone(icon) end
        elseif state == nil then
            moving[icon] = nil
        end
    end
    if next(moving) == nil then self:Hide() end
end)

Icon.CHOICES, Icon.ByKey = ICONS, ICON_BY_KEY
Icon.look = look
Icon.Create = createIcon
Icon.Play, Icon.Stop, Icon.SetLayer, Icon.RestyleAll = play, stop, setLayer, restyleAll
function Icon.IsActive(icon) return active[icon] ~= nil end
end)
