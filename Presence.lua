local _, ns = ...
ns.Module(function()
local L, Settings, Art = ns.L, ns.Settings, ns.Art
local Presence = {}
ns.Presence = Presence

-- Presence: a glowing icon above the nearby players who have ForeverDex ---------------
--
-- No API tells which addons another player runs, so the clients introduce themselves
-- with whispered addon messages (invisible in chat), on the prefix of Duel.lua:
--   P       ping, sent when a friendly player shows up within the chosen distance
--   P\tq    the same from a player who does not want to be shown (quiet)
--   H       answer: "I have ForeverDex"
-- Older versions ignore these message types (see "Comparison compatibility").
--
-- The icon hangs from the player's nameplate, the only frame that follows a character
-- in the 3D world. ForeverDex never changes the nameplate settings: the icon shows on
-- the plates the player's own settings display (Shift+V for friendly players), and a
-- line in the player's tooltip works without them. Detection also starts on mouseover
-- and target. The game forbids touching friendly nameplates in dungeons and raids.

local PREFIX = "ForeverDex"
local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"
-- Detection distance (presenceRange): 10 and 30 are checked with CheckInteractDistance
-- (duel range, about 10 yards, and follow range, about 28 yards). Farther, the
-- nameplates decide: the game creates them up to nameplateMaxDistance.
local FAR = 40
local PING_GAP = 0.4      -- seconds between two pings
local WAIT_ANSWER = 15    -- no answer after this: the player has no ForeverDex
local KNOWN_FOR = 600     -- an answer, or its absence, is trusted for 10 minutes
local REPLAY_GAP = 45     -- ping mode: shown again when met again after this
local ANSWER_GAP = 20     -- at most one answer per player in this time
local TICK = 0.5
local REPLACE_GAP = 2     -- seconds before an icon measures its nameplate again
local FORGET_AFTER = 1800 -- players unseen for this long are forgotten
local PRUNE_EVERY = 60    -- seconds between two clean-ups of what is remembered
local QUEUE_MAX = 40      -- pings waiting at most; the oldest ones are dropped

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

local function readable(value)
    return (not issecretvalue or not issecretvalue(value)) and value ~= nil
end

-- Calls a game function and keeps its first result only when it can be read.
local function safe(func, ...)
    if not func then return nil end
    local ok, value = pcall(func, ...)
    if ok and readable(value) then return value end
end

local function shortName(name)
    return name:match("^[^%-%s]+") or name
end

local function inCombat()
    return (InCombatLockdown and InCombatLockdown()) or safe(UnitAffectingCombat, "player") == true
end

local function inInstance()
    return safe(IsInInstance) == true
end

-- Demo: every friendly player of our faction within the distance counts as a ForeverDex
-- player, without any message. Until /reload or the same command again.
local demo = false

-- Settings read every frame by the animation, cached here. The demo shows the
-- icons even when the option is off.
local look = {}
local function readLook()
    look.show = Settings.Get("presenceShow") or demo
    look.announce = Settings.Get("presenceAnnounce")
    look.icon = ICON_BY_KEY[Settings.Get("presenceIcon")] or ICONS[1]
    look.intensity = Settings.Get("presenceIntensity")
    look.alpha = Settings.Get("presenceAlpha")
    look.size = Settings.Get("presenceSize")
    look.range = Settings.Get("presenceRange")
    look.height = Settings.Get("presenceHeight")
    look.duration = Settings.Get("presenceDuration")
end
readLook()

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

function Presence.CreateIcon(parent)
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

-- Game settings ---------------------------------------------------------------------
--
-- ForeverDex no longer touches the nameplate settings: forcing them changed how every
-- name in town looked (a unit with a plate loses the name drawn above it) and fought
-- Ctrl+V. Versions from this branch may have saved the player's values while forcing
-- them; those values are given back once, then forgotten.

local function getCVar(name)
    local ok, value = pcall(C_CVar and C_CVar.GetCVar or GetCVar, name)
    if ok then return value end
end

local function giveBackCVars()
    local db = ForeverDexDB
    local saved = db and db.presenceCVars
    if not saved or InCombatLockdown() then return end
    for name, value in pairs(saved) do
        if value ~= false and getCVar(name) ~= nil then
            pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
        end
    end
    db.presenceCVars, db.presenceCVarsReturned = nil, nil
end

-- Nameplates ------------------------------------------------------------------------

local known = {}   -- [short name] = { has, checked, asking, shown, address }
local plates = {}  -- [unit] = short name of the friendly player on that plate
local icons = {}   -- [unit] = icon hanging from that plate
local spare = {}   -- icons no longer used
local queue = {}   -- short names waiting for their ping, in order
local queued = {}
local answered = {} -- [short name] = time of our last answer
local demoKnown = {} -- [short name] = what the demo pretends to know

local function getPlate(unit)
    return C_NamePlate and safe(C_NamePlate.GetNamePlateForUnit, unit)
end

-- A friendly player of our faction, other than us: someone we can whisper.
local function eligible(unit)
    if safe(UnitIsPlayer, unit) ~= true or safe(UnitIsUnit, unit, "player") ~= false then return false end
    if safe(UnitCanAttack, "player", unit) ~= false then return false end
    local mine, theirs = safe(UnitFactionGroup, "player"), safe(UnitFactionGroup, unit)
    return mine == nil or theirs == nil or mine == theirs
end

-- true, false, or nil when the game does not tell (the nameplate distance then decides).
-- Not asked in combat, where the game may restrict it.
local function inRange(unit)
    if not CheckInteractDistance or inCombat() then return nil end
    if look.range >= FAR then return nil end
    return safe(CheckInteractDistance, unit, look.range <= 10 and 3 or 4)
end

-- What is known of a player: the real answers, or the demo's pretence.
local function entryFor(who, unit)
    if demo and who and (not unit or eligible(unit)) then
        demoKnown[who] = demoKnown[who] or { has = true }
        return demoKnown[who]
    end
    return who and known[who]
end

local function release(unit)
    local icon = icons[unit]
    if not icon then return end
    icons[unit] = nil
    stop(icon, true)
    icon.plate, icon.placedAt = nil, nil
    icon.frame:SetParent(nil)
    icon.frame:ClearAllPoints()
    spare[#spare + 1] = icon
end

-- Nameplate addons (Plater, ElvUI, Kui...) hide the Blizzard bar and draw their own on
-- the same base frame, at their own height, level and strata. The Blizzard bar keeps
-- the fixed placement; any other bar is measured: the icon goes above its highest
-- visible piece, and in front of it.
local BLIZZARD_OFFSET = 36
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function shownAlpha(object)
    local okShown, shown = pcall(object.IsVisible, object)
    if not okShown or not readable(shown) or not shown then return false end
    local getter = object.GetEffectiveAlpha or object.GetAlpha
    local okAlpha, alpha = pcall(getter, object)
    return not okAlpha or not readable(alpha) or alpha > 0.01
end

local function unitFrameOf(plate) return plate.UnitFrame end

local function blizzardBarShown(plate)
    local ok, frame = pcall(unitFrameOf, plate)
    return ok and type(frame) == "table" and shownAlpha(frame)
end

-- Top of the visible content (in the plate's units), highest frame level and strata.
-- The walk runs often: it creates no table and no function. Its state lives in these
-- upvalues, and the regions and children are read from the varargs the game returns.
local plateScale, measuredTop, measuredLevel, measuredStrata

local function reach(object)
    if not shownAlpha(object) then return end
    local okTop, value = pcall(object.GetTop, object)
    local okHeight, height = pcall(object.GetHeight, object)
    if not (okTop and readable(value) and value and okHeight and readable(height)) then return end
    -- Wide glows and highlights are not the bar.
    if height > 150 then return end
    local okScale, scale = pcall(object.GetEffectiveScale, object)
    value = value * ((okScale and readable(scale) and scale) or plateScale) / plateScale
    if not measuredTop or value > measuredTop then measuredTop = value end
end

local function reachEach(...)
    for i = 1, select("#", ...) do reach((select(i, ...))) end
end

local walk
local function walkEach(depth, ...)
    for i = 1, select("#", ...) do pcall(walk, (select(i, ...)), depth) end
end

walk = function(object, depth)
    if object.foreverDexIcon or not shownAlpha(object) then return end
    local okLevel, value = pcall(object.GetFrameLevel, object)
    if okLevel and readable(value) and value > measuredLevel then measuredLevel = value end
    local okStrata, name = pcall(object.GetFrameStrata, object)
    if okStrata and readable(name) and (STRATA[name] or 0) > (STRATA[measuredStrata] or 0) then
        measuredStrata = name
    end
    reach(object)
    reachEach(object:GetRegions())
    if depth < 3 then walkEach(depth + 1, object:GetChildren()) end
end

local function measure(plate)
    plateScale = plate:GetEffectiveScale()
    measuredTop, measuredLevel, measuredStrata = nil, plate:GetFrameLevel(), plate:GetFrameStrata()
    walkEach(1, plate:GetChildren())
    return measuredTop, measuredLevel, measuredStrata
end

-- The game may forbid measuring a nameplate ("Can't measure restricted regions"),
-- for instance a friendly plate it protects: its position must then never be read.
local function restricted(plate)
    if not plate.IsAnchoringRestricted then return false end
    local ok, value = pcall(plate.IsAnchoringRestricted, plate)
    return not ok or not readable(value) or value == true
end

local function place(icon, plate)
    local height = look.height
    if restricted(plate) or blizzardBarShown(plate) then
        icon.frame:SetPoint("CENTER", plate, "CENTER", 0, BLIZZARD_OFFSET + height)
        setLayer(icon, plate:GetFrameStrata(), plate:GetFrameLevel() + 10)
        return
    end
    local okMeasure, top, level, strata = pcall(measure, plate)
    if not okMeasure then top, level, strata = nil, plate:GetFrameLevel(), plate:GetFrameStrata() end
    -- Read under protection too: a plate can become restricted between two calls.
    local okCenter, _, centerY = pcall(plate.GetCenter, plate)
    if not okCenter or not readable(centerY) then centerY = nil end
    local offset = BLIZZARD_OFFSET
    if top and centerY then offset = top - centerY + 30 * look.size * 0.6 end
    icon.frame:SetPoint("CENTER", plate, "CENTER", 0, offset + height)
    setLayer(icon, strata, math.max(plate:GetFrameLevel() + 10, level + 5))
end

-- Measuring a nameplate addon's bar walks its frames: the icon only does it when it
-- changes plate, and then every REPLACE_GAP seconds at most, not on every tick.
local function attach(unit, plate)
    local icon = icons[unit]
    if not icon then
        icon = table.remove(spare) or Presence.CreateIcon(UIParent)
        icon.frame.foreverDexIcon = true
        icons[unit] = icon
    end
    local now = GetTime()
    if icon.plate == plate and now - (icon.placedAt or 0) < REPLACE_GAP then return icon end
    icon.plate, icon.placedAt = plate, now
    icon.frame:SetParent(plate)
    icon.frame:ClearAllPoints()
    if icon.frame.SetIgnoreParentAlpha then icon.frame:SetIgnoreParentAlpha(true) end
    place(icon, plate)
    return icon
end

-- Shows or hides the icon of one nameplate unit, from what is known of its player.
local function update(unit)
    local who = plates[unit]
    local entry = entryFor(who)
    local plate = getPlate(unit)
    if not (look.show and entry and entry.has and plate) then
        local icon = icons[unit]
        if icon then stop(icon) end
        return
    end
    local now = GetTime()
    local range = inRange(unit)
    local icon = icons[unit]
    if look.duration > 0 then
        -- Ping: once when met, again only after a while away.
        if range ~= false and not (icon and active[icon]) and now - (entry.shown or -math.huge) > REPLAY_GAP then
            entry.shown = now
            play(attach(unit, plate), look.duration)
        elseif icon and active[icon] then
            entry.shown = now
            attach(unit, plate)
        end
    elseif range == false then
        if icon then stop(icon) end
    else
        icon = attach(unit, plate)
        if not active[icon] or icon.leaving then play(icon, 0) end
        entry.shown = now
    end
end

local function updateAll()
    for unit in pairs(plates) do update(unit) end
    for unit, icon in pairs(icons) do
        if not plates[unit] then release(unit) elseif not look.show then stop(icon, true) end
    end
end

local function updatePlayer(who)
    for unit, name in pairs(plates) do
        if name == who then update(unit) end
    end
end

-- Pings -----------------------------------------------------------------------------

-- A whisper to a player who has just logged out makes the game print "No player
-- named ... is currently playing". The line comes from ForeverDex, not from anything
-- the player did: it is hidden, and that player counts as not having the addon.
local NOT_FOUND_GAP = 5 -- seconds during which the game's answer is expected
local whispered = {}    -- [address] = time of our last whisper to it

local function send(message, target)
    whispered[target] = GetTime()
    return safe(C_ChatInfo.SendAddonMessage, PREFIX, message, "WHISPER", target)
end

local notFoundPattern
local function notFoundName(message)
    if notFoundPattern == nil then
        local format = ERR_CHAT_PLAYER_NOT_FOUND_S
        notFoundPattern = false
        if type(format) == "string" and format:find("%s", 1, true) then
            local escaped = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
            notFoundPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
        end
    end
    return notFoundPattern and message:match(notFoundPattern)
end

if ChatFrame_AddMessageEventFilter then
    -- Called once per chat window showing system messages: the record is kept until
    -- it expires, so that every window hides the line.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
        if not readable(message) or type(message) ~= "string" then return false end
        local address = notFoundName(message)
        local at = address and whispered[address]
        if not at or GetTime() - at > NOT_FOUND_GAP then return false end
        local entry = known[shortName(address)]
        if entry then entry.has, entry.checked, entry.asking = false, GetTime(), nil end
        return true
    end)
end

local function wantPing(who)
    local entry = known[who]
    if not entry then return true end
    if entry.asking then return false end
    return GetTime() - (entry.checked or 0) > KNOWN_FOR
end

-- Queues a ping for the player on this unit (nameplate, mouseover or target),
-- with the address the whisper expects.
local function consider(unit)
    -- Nothing is queued while the icons are off: the queue would only grow.
    if demo or not look.show or not eligible(unit) or inRange(unit) == false then return end
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    local who = shortName(name)
    if queued[who] or not wantPing(who) then return end
    local entry = known[who] or {}
    known[who] = entry
    entry.address = safe(GetUnitName, unit, true) or entry.address or name
    queued[who] = true
    queue[#queue + 1] = who
    -- A crowded city must not pile up pings: the oldest ones are given up.
    while #queue > QUEUE_MAX do queued[table.remove(queue, 1)] = nil end
end

-- Sends the next ping in the queue, if the moment allows it.
local lastPing = 0
local function pingNext(now)
    if #queue == 0 or now - lastPing < PING_GAP or demo then return end
    if not look.show or inCombat() or inInstance() then return end
    local who = table.remove(queue, 1)
    queued[who] = nil
    local entry = known[who]
    if not (entry and entry.address) or not wantPing(who) then return end
    entry.asking = now
    lastPing = now
    send(look.announce and "P" or "P\tq", entry.address)
end

local prune -- below

local function heard(who, address)
    local entry = known[who] or {}
    known[who] = entry
    entry.has, entry.checked, entry.asking = true, GetTime(), nil
    entry.address = address or entry.address
    updatePlayer(who)
    -- Answers keep arriving while the icons are off and the ticker stopped.
    prune(GetTime())
end

-- Forgets the players not met for a long time, so that a session in town does not
-- keep every name it ever saw. Those still on a plate or in the queue are kept.
local lastPrune = 0
prune = function(now)
    if now - lastPrune < PRUNE_EVERY then return end
    lastPrune = now
    local onPlate = {}
    for _, who in pairs(plates) do onPlate[who] = true end
    for who, entry in pairs(known) do
        local seen = math.max(entry.checked or 0, entry.asking or 0, entry.shown or 0)
        if not onPlate[who] and not queued[who] and now - seen > FORGET_AFTER then known[who] = nil end
    end
    for who, at in pairs(answered) do
        if now - at > ANSWER_GAP then answered[who] = nil end
    end
    for address, at in pairs(whispered) do
        if now - at > NOT_FOUND_GAP then whispered[address] = nil end
    end
end

local function tick()
    local now = GetTime()
    for _, entry in pairs(known) do
        if entry.asking and now - entry.asking > WAIT_ANSWER then
            entry.has, entry.checked, entry.asking = false, now, nil
        end
    end
    prune(now)
    for unit in pairs(plates) do consider(unit) end
    pingNext(now)
    updateAll()
end

local function addPlate(unit)
    if not eligible(unit) then plates[unit] = nil return end
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    plates[unit] = shortName(name)
    consider(unit)
    update(unit)
end

local function removePlate(unit)
    plates[unit] = nil
    release(unit)
end

-- Every visible nameplate with its unit token.
local function eachPlate(callback)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(safe(C_NamePlate.GetNamePlates) or {}) do
        local ok, unit = pcall(function() return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) end)
        if ok and readable(unit) and unit then callback(unit, plate) end
    end
end

local function scanPlates()
    eachPlate(addPlate)
end

-- Tooltip ---------------------------------------------------------------------------
--
-- A line under a player known to have ForeverDex. It works without any nameplate.

-- The 32 px icon of the addon list: the 256 px orb shrunk to 14 px in a text line
-- gets no smoothing there and looked pixelated.
local TOOLTIP_ICON = "|T" .. MEDIA .. "IconSmall:16:16|t "

local function addTooltipLine(tooltip)
    if not look.show or not tooltip or tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not readable(unit) or not unit then return end
    if not eligible(unit) then return end
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    local entry = entryFor(shortName(name), unit)
    if entry and entry.has then
        tooltip:AddLine(TOOLTIP_ICON .. L.PRESENCE_TOOLTIP, 0.39, 0.87, 0.82)
        tooltip:Show()
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, addTooltipLine)
elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", addTooltipLine)
end

-- An answer arriving while the player is still under the mouse shows the line at once.
local function refreshTooltip(who)
    if not (GameTooltip and GameTooltip:IsShown()) then return end
    local name = safe(UnitName, "mouseover")
    if name and shortName(name) == who and safe(UnitIsPlayer, "mouseover") then
        pcall(GameTooltip.SetUnit, GameTooltip, "mouseover")
    end
end

-- Events ----------------------------------------------------------------------------

-- The ticker only runs while the icons are on: answering the pings of other players
-- needs no ticker, it follows their messages.
local ticker
local function syncTicker()
    if look.show and not ticker then
        ticker = C_Timer.NewTicker(TICK, tick)
    elseif not look.show and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, a, b, _, d)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, sender = a, b, d
        if not readable(prefix) or prefix ~= PREFIX or not readable(text) or not readable(sender) then return end
        local kind = text:sub(1, 1)
        if kind ~= "P" and kind ~= "H" then return end
        local who = shortName(sender)
        if who == shortName(safe(UnitName, "player") or "") then return end
        if kind == "P" then
            -- A quiet ping still deserves an answer, but its sender is not shown.
            if not text:find("\tq", 2, true) then
                heard(who, sender)
                refreshTooltip(who)
            end
            local now = GetTime()
            if look.announce and now - (answered[who] or -math.huge) > ANSWER_GAP then
                answered[who] = now
                send("H", sender)
            end
        else
            heard(who, sender)
            refreshTooltip(who)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        addPlate(a)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        removePlate(a)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        consider("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        consider("target")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        giveBackCVars()
        if event == "PLAYER_ENTERING_WORLD" then scanPlates() end
    end
end)

Settings.OnChange(function(key)
    if key ~= nil and not key:find("^presence") then return end
    readLook()
    if key == "presenceShow" and look.show then
        scanPlates()
    elseif key == "presenceDuration" then
        -- Permanent and ping icons do not end the same way: they start again.
        for unit in pairs(icons) do release(unit) end
        for _, entry in pairs(known) do entry.shown = nil end
    end
    syncTicker()
    restyleAll()
    updateAll()
    if Presence.RefreshPreview then Presence.RefreshPreview() end
end)

-- Banner at the top of the screen while the demo runs: it says a test is running, and
-- its button stops it and brings back the Collectors options. Built on the first demo
-- only, and nothing is written in the chat. It can be dragged out of the way.
local banner
local function showBanner(shown)
    if not shown then
        if banner then banner:Hide() end
        return
    end
    if not banner then
        banner = CreateFrame("Frame", "ForeverDexPresenceDemo", UIParent, "BackdropTemplate")
        banner:SetPoint("TOP", UIParent, "TOP", 0, -110)
        banner:SetHeight(46)
        banner:SetFrameStrata("HIGH")
        banner:SetClampedToScreen(true)
        banner:EnableMouse(true)
        banner:SetMovable(true)
        banner:RegisterForDrag("LeftButton")
        banner:SetScript("OnDragStart", banner.StartMoving)
        banner:SetScript("OnDragStop", banner.StopMovingOrSizing)
        banner:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        banner:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
        banner:SetBackdropBorderColor(1, 0.82, 0.35, 0.9)
        local orb = banner:CreateTexture(nil, "ARTWORK")
        orb:SetSize(24, 24)
        orb:SetPoint("LEFT", 10, 0)
        Art.SmoothTexture(orb, MEDIA .. "Ball")
        local title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", orb, "TOPRIGHT", 9, 4)
        title:SetText(L.PRESENCE_DEMO_BANNER)
        -- The icons hang from friendly nameplates: without them, nothing shows.
        local hint = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        hint:SetTextColor(0.75, 0.72, 0.65)
        hint:SetText(L.PRESENCE_DEMO_HINT)
        local stopButton = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
        stopButton:SetSize(120, 22)
        stopButton:SetPoint("RIGHT", -9, 0)
        stopButton:SetText(L.PRESENCE_DEMO_STOP)
        stopButton:SetScript("OnClick", function()
            if demo then Presence.ToggleDemo() end
            if Presence.OpenOptions then Presence.OpenOptions() end
        end)
        local textWidth = math.max(title:GetStringWidth(), hint:GetStringWidth())
        banner:SetWidth(10 + 24 + 9 + textWidth + 18 + 120 + 9)
    end
    banner:Show()
end

function Presence.ToggleDemo()
    demo = not demo
    readLook()
    for unit in pairs(icons) do release(unit) end
    wipe(demoKnown)
    syncTicker()
    scanPlates()
    updateAll()
    showBanner(demo)
    if Presence.RefreshDemoButton then Presence.RefreshDemoButton() end
end

function Presence.IsDemo()
    return demo
end

-- Options page with a live preview ----------------------------------------------------

local page, left, right = Settings.AddPage(L.PRESENCE_TITLE, L.PRESENCE_SUBTITLE)
local B = Settings.Builder

B.section(left, L.PRESENCE_SECTION)
B.checkbox(left, "presenceAnnounce", L.PRESENCE_ANNOUNCE, L.PRESENCE_ANNOUNCE_TIP)
B.checkbox(left, "presenceShow", L.PRESENCE_SHOW, L.PRESENCE_SHOW_TIP)

B.section(left, L.PRESENCE_LOOK)
local iconChoices = {}
for _, icon in ipairs(ICONS) do iconChoices[#iconChoices + 1] = { icon[1], icon[2] } end
B.choice(left, "presenceIcon", L.PRESENCE_ICON, iconChoices, L.PRESENCE_ICON_TIP)
B.choice(left, "presenceRange", L.PRESENCE_RANGE, {
    { 10, L.PRESENCE_RANGE_YARDS:format(10) },
    { 30, L.PRESENCE_RANGE_YARDS:format(30) },
    { FAR, L.PRESENCE_RANGE_YARDS:format(FAR) },
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

local preview = Presence.CreateIcon(stage)
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
    local starting = not demo
    Presence.ToggleDemo()
    if starting and SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
end, L.PRESENCE_DEMO_TIP)

function Presence.OpenOptions()
    Settings.OpenPage(page)
end

function Presence.RefreshDemoButton()
    demoButton:SetText(demo and L.PRESENCE_DEMO_STOP or L.PRESENCE_DEMO)
end
page:HookScript("OnShow", Presence.RefreshDemoButton)

-- In ping mode the preview starts again shortly after each ping.
preview.onDone = function()
    C_Timer.After(1.2, function()
        if page:IsVisible() and not active[preview] then play(preview, look.duration) end
    end)
end

local PREVIEW_TOP = -40

function Presence.RefreshPreview()
    if not page:IsVisible() then return end
    preview.frame:SetPoint("TOP", stage, "TOP", 0, PREVIEW_TOP + look.height)
    replay:SetEnabled(look.duration > 0)
    if not active[preview] or (look.duration == 0) ~= (preview.duration == 0) then
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

-- Number of nearby players known to have ForeverDex, for /foreverdex presence.
function Presence.Report()
    local count, names = 0, {}
    for who, entry in pairs(known) do
        if entry.has then count = count + 1 names[#names + 1] = who end
    end
    table.sort(names)
    DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. L.PRESENCE_REPORT:format(count, table.concat(names, ", ")))
end

Presence.Page = page
end)
