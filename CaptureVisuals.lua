local _, ns = ...
ns.Module(function()
local L, Art = ns.L, ns.Art
local CaptureVisuals = {}
ns.CaptureVisuals = CaptureVisuals

-- The ball is a single addon texture: unlike a drawing made of several
-- pieces, it can rotate during the throw and the shakes.
local BALL = "Interface\\AddOns\\ForeverDex\\Media\\Ball"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
CaptureVisuals.BALL = BALL

-- The badge only grows by 3 pixels: snapped to the pixel grid, it would step
-- through 4 sizes instead of growing smoothly. A bias above 0 implies snapping.
local function allowSubpixel(texture)
    if not texture.SetSnapToPixelGrid then return end
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

function CaptureVisuals.DrawBadge(badge)
    local ball = badge:CreateTexture(nil, "ARTWORK")
    ball:SetAllPoints()
    Art.SmoothTexture(ball, BALL)
    allowSubpixel(ball)
    local highlight = badge:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    Art.SmoothTexture(highlight, BALL)
    allowSubpixel(highlight)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.35)
    return ball
end

-- Center and diameter of a frame or texture, in UIParent scale.
-- A position can be "secret" (an ElvUI secure frame, for example): the client
-- forbids any computation on it, so we answer as if it were unknown.
local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function CaptureVisuals.Center(region)
    if not region then return end
    local x, y = region:GetCenter()
    if isSecret(x) or isSecret(y) or not x or not y then return end
    local owner = region.GetEffectiveScale and region or region:GetParent()
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width = region:GetWidth()
    if isSecret(width) or not width then width = 0 end
    return x * scale, y * scale, width * scale
end

-- Native notification animations. All animations in a group share the same
-- order and are placed by their delay, so the timeline reads in seconds.
local function animation(group, kind, start, duration, smoothing)
    local anim = group:CreateAnimation(kind)
    anim:SetOrder(1)
    anim:SetStartDelay(start)
    anim:SetDuration(duration)
    if smoothing then anim:SetSmoothing(smoothing) end
    return anim
end

local function fade(anim, from, to)
    anim:SetFromAlpha(from)
    anim:SetToAlpha(to)
    return anim
end

-- Timeline, modeled on a classic capture: throw, absorption, bounces,
-- three shakes one second apart, click, then back to the journal.
local THROW = 0.55
local ABSORB = 0.55
local DROP = 0.9
local WOBBLES = { 1.8, 2.8, 3.8 }
local CLICK = 4.5
local FLY = 5.2
-- Quick version: no shakes, the click directly follows the bounces.
local QUICK_SHIFT = CLICK - 1.5

-- The whole capture is computed every frame in screen coordinates: on this
-- client, native translations and scales knocked the ball off course.
local effect = CreateFrame("Frame", nil, UIParent)
effect:SetAllPoints(UIParent)
effect:SetFrameStrata("FULLSCREEN_DIALOG")
effect:Hide()

local function smooth(t) return t * t * (3 - 2 * t) end
local function easeOut(t) return 1 - (1 - t) * (1 - t) end

local function put(texture, x, y, size)
    texture:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    texture:SetSize(size, size)
end

local ball = effect:CreateTexture(nil, "ARTWORK")
Art.SmoothTexture(ball, BALL)
local dim = effect:CreateTexture(nil, "ARTWORK", nil, 1)
dim:SetTexture(DISC)
dim:SetVertexColor(0, 0, 0)
local flash = effect:CreateTexture(nil, "OVERLAY")
flash:SetTexture(DISC)
flash:SetBlendMode("ADD")

-- Three stars burst from the top on the click.
local STAR_LIFE = 0.65
local stars = {}
for i, direction in ipairs({ { -34, 26 }, { 0, 40 }, { 34, 26 } }) do
    local star = effect:CreateTexture(nil, "OVERLAY", nil, 1)
    star:SetTexture("Interface\\Cooldown\\star4")
    star:SetBlendMode("ADD")
    star:SetVertexColor(1, 0.9, 0.35)
    stars[i] = { texture = star, x = direction[1], y = direction[2], turn = i == 2 and 0 or (i == 1 and math.pi / 2 or -math.pi / 2) }
end

-- The ball falls back onto the portrait and bounces twice, damped.
-- The sum of the bounces leaves it exactly at the center of the portrait.
local BOUNCES = { { -12, 0.12, true }, { 7, 0.10 }, { -7, 0.10, true }, { 3, 0.06 }, { -3, 0.06, true } }
local LANDING_LIFT, THROW_ARC = 12, 70

local function bounceOffset(elapsed)
    local offset = 0
    for _, bounce in ipairs(BOUNCES) do
        if elapsed < bounce[2] then
            local t = elapsed / bounce[2]
            return offset + bounce[1] * (bounce[3] and t * t or easeOut(t))
        end
        elapsed = elapsed - bounce[2]
        offset = offset + bounce[1]
    end
    return offset
end

-- Shakes: the ball tilts left, right, then left.
local TILT_ANGLE, TILT_TIME, TILT_BACK = math.rad(24), 0.14, 0.24

local function tiltAt(now, starts)
    for i, start in ipairs(starts) do
        local t = now - start
        if t >= 0 and t < TILT_TIME + TILT_BACK then
            local amount = t < TILT_TIME and easeOut(t / TILT_TIME) or 1 - smooth((t - TILT_TIME) / TILT_BACK)
            return TILT_ANGLE * (i == 2 and -1 or 1) * amount
        end
    end
    return 0
end

local seq

effect:SetScript("OnUpdate", function(_, delta)
    seq.elapsed = seq.elapsed + delta
    local now, size = seq.elapsed, seq.size
    local x, y, angle
    if now < THROW then
        local t = now / THROW
        x = seq.x1 + (seq.x2 - seq.x1) * t
        y = seq.y1 + (seq.y2 + LANDING_LIFT - seq.y1) * t + THROW_ARC * 4 * t * (1 - t)
        size = seq.size * (0.35 + 0.65 * easeOut(t))
        angle = -4 * math.pi * easeOut(t)
    else
        x, y = seq.x2, seq.y2 + LANDING_LIFT
        if now > DROP then y = y + bounceOffset(now - DROP) end
        angle = tiltAt(now, seq.wobbles)
    end
    -- While tilting, the center follows an arc around the base, which stays still.
    local radius = size / 2
    local ballX, ballY = x - radius * math.sin(angle), y + radius * (math.cos(angle) - 1)
    if now < THROW then ballX, ballY = x, y end
    put(ball, ballX, ballY, size)
    ball:SetRotation(angle)

    -- White flash: the character is drawn into the ball.
    local sinceAbsorb = now - ABSORB
    local flashing = sinceAbsorb >= 0 and sinceAbsorb < 0.35
    flash:SetShown(flashing)
    if flashing then
        local t = sinceAbsorb / 0.35
        put(flash, x, y, seq.size * 1.25 * (1.3 - 1.05 * t * t))
        flash:SetAlpha(sinceAbsorb < 0.1 and sinceAbsorb / 0.1 or 1 - (sinceAbsorb - 0.1) / 0.25)
    end

    -- The ball darkens slightly once the capture succeeds.
    local sinceClick = now - seq.click
    put(dim, ballX, ballY, size)
    dim:SetAlpha(0.3 * math.max(0, math.min(1, sinceClick / 0.2)))

    for _, star in ipairs(stars) do
        local shown = sinceClick >= 0 and sinceClick < STAR_LIFE
        star.texture:SetShown(shown)
        if shown then
            local t = easeOut(sinceClick / STAR_LIFE)
            put(star.texture, seq.x2 + star.x * t, seq.y2 + seq.size / 2 + star.y * t, 26)
            star.texture:SetRotation(star.turn * sinceClick / STAR_LIFE)
            local alpha = sinceClick < 0.05 and sinceClick / 0.05 or (sinceClick < 0.25 and 1 or 1 - (sinceClick - 0.25) / 0.4)
            star.texture:SetAlpha(math.max(0, alpha))
        end
    end
end)

-- Back to the journal: the ball leaves the portrait, flies in an arc to the minimap
-- icon leaving a golden trail, then tucks in with a burst. The path is computed
-- every frame in screen coordinates, to land exactly on the icon.
local RISE, SETTLE = 0.2, 0.3
local RISE_HEIGHT = 16
local TRAIL_COUNT, TRAIL_EVERY, TRAIL_LIFE = 12, 0.035, 0.38
local STAR = "Interface\\Cooldown\\star4"

local homing = CreateFrame("Frame", nil, UIParent)
homing:SetAllPoints(UIParent)
homing:SetFrameStrata("FULLSCREEN_DIALOG")
homing:SetFrameLevel(effect:GetFrameLevel() + 5)
homing:Hide()

local function homingTexture(file, layer, additive)
    local texture = homing:CreateTexture(nil, layer)
    Art.SmoothTexture(texture, file)
    if additive then
        texture:SetBlendMode("ADD")
        texture:SetVertexColor(1, 0.85, 0.4)
    end
    return texture
end

local homingBall = homingTexture(BALL, "OVERLAY")
local homingGlow = homingTexture(STAR, "ARTWORK", true)
local homingBurst = homingTexture(STAR, "OVERLAY", true)
homingBurst:SetDrawLayer("OVERLAY", 1)
local trail = {}
for i = 1, TRAIL_COUNT do
    trail[i] = { texture = homingTexture(BALL, "BORDER", true) }
end

local function curve(from, control, to, t)
    local rest = 1 - t
    return rest * rest * from + 2 * rest * t * control + t * t * to
end

local run

local function stopHoming()
    homing:Hide()
    run = nil
    for _, ghost in ipairs(trail) do
        ghost.born = nil
        ghost.texture:Hide()
    end
end

local function updateTrail(now)
    for _, ghost in ipairs(trail) do
        local age = ghost.born and now - ghost.born
        if age and age < TRAIL_LIFE then
            local left = 1 - age / TRAIL_LIFE
            put(ghost.texture, ghost.x, ghost.y, ghost.size * (0.5 + 0.5 * left))
            ghost.texture:SetAlpha(0.6 * left)
            ghost.texture:Show()
        else
            ghost.texture:Hide()
        end
    end
end

local function dropGhost(now, x, y, size)
    run.nextGhost = run.nextGhost % TRAIL_COUNT + 1
    local ghost = trail[run.nextGhost]
    ghost.born, ghost.x, ghost.y, ghost.size = now, x, y, size
end

homing:SetScript("OnUpdate", function(_, delta)
    local now = run.elapsed + delta
    run.elapsed = now
    local x, y, size, glow, alpha, spin = run.x2, run.y2, run.endSize, 1, 1, 13
    local travelEnd = RISE + run.travel
    if now < RISE then
        local t = easeOut(now / RISE)
        x, y, size, glow, spin = run.x1, run.y1 - RISE_HEIGHT * (1 - t), run.size * (1 + 0.18 * t), t, 5
    elseif now < travelEnd then
        local t = smooth((now - RISE) / run.travel)
        x, y = curve(run.x1, run.cx, run.x2, t), curve(run.y1, run.cy, run.y2, t)
        size = run.size * 1.18 + (run.endSize - run.size * 1.18) * t
        run.sinceGhost = run.sinceGhost + delta
        if run.sinceGhost >= TRAIL_EVERY then
            run.sinceGhost = 0
            dropGhost(now, x, y, size)
        end
    else
        if not run.arrived then
            run.arrived = true
            run.onArrive()
        end
        local t = (now - travelEnd) / SETTLE
        if t >= 1 then
            local onDone = run.onDone
            stopHoming()
            onDone()
            return
        end
        size, glow, alpha = run.endSize * (1 - 0.75 * t * t), 1 - t, 1 - t * t
        put(homingBurst, x, y, run.endSize * (1.2 + 2.6 * easeOut(t)))
        homingBurst:SetAlpha(1 - t)
        homingBurst:SetRotation(t * 1.2)
        homingBurst:Show()
    end
    run.angle = run.angle - delta * spin
    put(homingBall, x, y, size)
    homingBall:SetRotation(run.angle)
    homingBall:SetAlpha(alpha)
    put(homingGlow, x, y, size * 2.4)
    homingGlow:SetRotation(-run.angle * 0.4)
    homingGlow:SetAlpha(0.8 * glow)
    updateTrail(now)
end)

-- Start (x1, y1): the ball resting on the portrait. With no visible icon, it
-- tucks away on the spot. onArrive handles the sound and icon, onDone the notification.
local function launchHoming(x1, y1, size, homeX, homeY, homeSize, onArrive, onDone)
    stopHoming()
    local startY = y1 + RISE_HEIGHT
    local x2, y2 = homeX or x1, homeY or startY
    local distance = math.sqrt((x2 - x1) ^ 2 + (y2 - startY) ^ 2)
    -- The arc goes above the path without leaving the top of the screen.
    local middleY = (startY + y2) / 2
    local arcY = math.max(middleY, math.min(middleY + distance * 0.35, UIParent:GetHeight() - 30))
    run = {
        x1 = x1, y1 = startY, x2 = x2, y2 = y2, cx = (x1 + x2) / 2, cy = arcY,
        size = size, endSize = math.max(24, (homeSize or size) * 0.9),
        travel = homeX and math.max(0.6, math.min(1, distance / 900)) or 0,
        elapsed = 0, angle = 0, sinceGhost = 0, nextGhost = 0,
        onArrive = onArrive, onDone = onDone,
    }
    homingBurst:Hide()
    homing:Show()
end

-- Notification: rises from the bottom of the screen, above the action bars,
-- like the game's alerts --------------------------------------------------------------

local ACHIEVEMENT = "Interface\\AchievementFrame\\"
-- Frame drawn for the notification: gold dialog box border and the game's dark
-- background. Unlike the achievement background, it forces neither a banner
-- nor a reserved slot: all the content follows the same grid.
--   portrait on the left (center 40 px from the edge);
--   text column at 80 px: title, name, combination, bar + counter.
local TOAST_W, TOAST_H, TEXT_LEFT = 320, 84, 80
local toast = CreateFrame("Button", "ForeverDexToast", UIParent, "BackdropTemplate")
toast:SetSize(TOAST_W, TOAST_H)
toast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
toast:SetFrameStrata("DIALOG")
toast:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
toast:SetBackdropColor(0.09, 0.06, 0.04, 0.96)
toast:Hide()

-- Slight gold gradient at the top, to give the flat background some depth.
local toastSheen = toast:CreateTexture(nil, "BORDER")
toastSheen:SetPoint("TOPLEFT", 5, -5)
toastSheen:SetPoint("TOPRIGHT", -5, -5)
toastSheen:SetHeight(TOAST_H / 2)
Art.Gradient(toastSheen, 1, 0.8, 0.4, 0, 0.12)

local toastGlow = toast:CreateTexture(nil, "OVERLAY")
toastGlow:SetSize(TOAST_W * 1.35, TOAST_H * 2)
toastGlow:SetPoint("CENTER")
toastGlow:SetTexture(ACHIEVEMENT .. "UI-Achievement-Alert-Glow")
toastGlow:SetTexCoord(0, 0.78125, 0, 0.66796875)
toastGlow:SetBlendMode("ADD")
toastGlow:SetAlpha(0)

local toastShine = toast:CreateTexture(nil, "OVERLAY", nil, 1)
toastShine:SetSize(60, TOAST_H - 10)
toastShine:SetPoint("LEFT", 5, 0)
toastShine:SetTexture(ACHIEVEMENT .. "UI-Achievement-Alert-Glow")
toastShine:SetTexCoord(0.78125, 0.912109375, 0, 0.28125)
toastShine:SetBlendMode("ADD")
toastShine:SetAlpha(0)

local toastIcon = toast:CreateTexture(nil, "ARTWORK")
toastIcon:SetSize(48, 48)
toastIcon:SetPoint("CENTER", toast, "LEFT", 40, 0)
local toastIconFrame = toast:CreateTexture(nil, "ARTWORK", nil, 1)
toastIconFrame:SetSize(68, 68)
toastIconFrame:SetPoint("CENTER", toastIcon)
toastIconFrame:SetTexture(ACHIEVEMENT .. "UI-Achievement-IconFrame")
toastIconFrame:SetTexCoord(0, 0.5625, 0, 0.5625)

local toastTitle = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
-- The four lines take about 53 px: a 15 px top margin centers them.
toastTitle:SetPoint("TOPLEFT", TEXT_LEFT, -15)
toastTitle:SetText(L.NEW_CARD)
toastTitle:SetTextColor(1, 0.82, 0)
local toastName = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
Art.Font(toastName, 15, "OUTLINE")
toastName:SetPoint("TOPLEFT", toastTitle, "BOTTOMLEFT", 0, -3)
toastName:SetPoint("RIGHT", toast, "RIGHT", -14, 0)
toastName:SetJustifyH("LEFT")
toastName:SetWordWrap(false)
local toastCombo = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toastCombo:SetPoint("TOPLEFT", toastName, "BOTTOMLEFT", 0, -3)
toastCombo:SetPoint("RIGHT", toast, "RIGHT", -14, 0)
toastCombo:SetJustifyH("LEFT")
toastCombo:SetWordWrap(false)
local toastBar = Art.ProgressBar(toast, 170, 6)
toastBar:SetPoint("TOPLEFT", toastCombo, "BOTTOMLEFT", 1, -6)
local toastBarBorder = toastBar:CreateTexture(nil, "BACKGROUND", nil, -1)
toastBarBorder:SetPoint("TOPLEFT", -1, 1)
toastBarBorder:SetPoint("BOTTOMRIGHT", 1, -1)
toastBarBorder:SetColorTexture(0.75, 0.6, 0.3, 0.8)
local toastCount = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
toastCount:SetPoint("LEFT", toastBar, "RIGHT", 8, 0)

-- Enters from the bottom: offset by 50 pixels then raised, with a fade.
local toastAnimation = toast:CreateAnimationGroup()
toastAnimation:SetToFinalAlpha(true)
animation(toastAnimation, "Translation", 0, 0.001):SetOffset(0, -50)
animation(toastAnimation, "Translation", 0.001, 0.4, "OUT"):SetOffset(0, 50)
fade(animation(toastAnimation, "Alpha", 0, 0.3), 0, 1)
fade(animation(toastAnimation, "Alpha", 4.2, 0.6), 1, 0)
toastAnimation:SetScript("OnFinished", function() toast:Hide() end)

local glowAnimation = toastGlow:CreateAnimationGroup()
fade(animation(glowAnimation, "Alpha", 0.3, 0.2), 0, 1)
fade(animation(glowAnimation, "Alpha", 0.5, 0.5), 1, 0)

local shineAnimation = toastShine:CreateAnimationGroup()
fade(animation(shineAnimation, "Alpha", 0.5, 0.1), 0, 1)
animation(shineAnimation, "Translation", 0.5, 0.85):SetOffset(TOAST_W - 70, 0)
fade(animation(shineAnimation, "Alpha", 1.1, 0.25), 1, 0)

-- The bar fills while the notification is showing.
local fillFrom, fillTo, fillElapsed = 0, 0, 0
toast:SetScript("OnUpdate", function(_, delta)
    fillElapsed = fillElapsed + delta
    local fraction = math.max(0, math.min(1, (fillElapsed - 0.5) / 0.8))
    fraction = 1 - (1 - fraction) ^ 3
    toastBar:SetValue(fillFrom + (fillTo - fillFrom) * fraction)
end)
toast:SetScript("OnClick", function()
    toastAnimation:Stop()
    toast:Hide()
end)

local function showToast(entry)
    if not ns.Settings.Get("toast") then return end
    local catalog = ns.Catalog
    local combination = catalog.byKey[entry.combination or entry.key]
    local slot = catalog.slotByKey[entry.key]
    local _, description = catalog.Describe(slot or {}, entry)
    toastName:SetText(entry.name)
    toastCombo:SetText(slot and ("#%03d%s%s"):format(slot.index, L.SEPARATOR, description) or description)
    local color = combination and RAID_CLASS_COLORS[combination.token]
    if color then toastCombo:SetTextColor(color.r, color.g, color.b) else toastCombo:SetTextColor(0.8, 0.8, 0.8) end

    local target = ns.Collection.ReadTarget() or ns.Collection.ReadPet()
    if target and target.id == entry.id and SetPortraitTexture then
        toastIcon:SetTexture(nil)
        toastIcon:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(toastIcon, "target")
    elseif combination and Art.HasAtlas(combination.portraitAtlas) then
        toastIcon:SetAtlas(combination.portraitAtlas)
    else
        toastIcon:SetTexture(BALL)
        toastIcon:SetTexCoord(0, 1, 0, 1)
    end

    -- A pet fills the pet section, a player the main collection.
    local list = slot and slot.pet and catalog.petSlots or catalog.slots
    local count = catalog.Filled(ForeverDexDB.cards, list)
    toastBar:SetMinMaxValues(0, #list)
    fillFrom, fillTo, fillElapsed = math.max(0, count - 1), count, 0
    toastBar:SetValue(fillFrom)
    toastCount:SetText(("%d / %d"):format(count, #list))

    toastAnimation:Stop()
    glowAnimation:Stop()
    shineAnimation:Stop()
    toast:Show()
    toastAnimation:Play()
    glowAnimation:Play()
    shineAnimation:Play()
end

-- Playback --------------------------------------------------------------------------------

-- Each playback gets a number: a new capture cancels the sounds and
-- steps scheduled by the previous one.
local playback = 0
local function at(delay, token, action)
    C_Timer.After(delay, function()
        if token == playback then action() end
    end)
end

-- options: from (x, y), to (x, y, ball size), home (x, y, minimap
-- icon size), entry, onReveal, onHome.
function CaptureVisuals.Play(options)
    playback = playback + 1
    local token = playback
    -- One capture can interrupt another, for example from chat.
    stopHoming()
    effect:Hide()
    local entry = options.entry
    local mode = ns.Settings.Get("animation")
    if not options.fromX or mode == "off" then
        -- No animation (or no visible starting point): everything happens at once.
        if options.onReveal then options.onReveal() end
        ns.Collection.Announce(entry, true)
        if options.onHome then options.onHome() end
        showToast(entry)
        return
    end
    local quick = mode == "quick"
    local shift = quick and QUICK_SHIFT or 0
    local x1, y1 = options.fromX, options.fromY
    local x2, y2 = options.toX or (x1 - 20), options.toY or (y1 - 30)
    -- Clamped: the target can be a portrait-less ElvUI frame as wide as a bar.
    local size = math.min(72, math.max(36, options.size or 0))

    seq = {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2, size = size, elapsed = 0,
        click = CLICK - shift, wobbles = quick and {} or WOBBLES,
    }
    flash:Hide()
    dim:SetAlpha(0)
    for _, star in ipairs(stars) do star.texture:Hide() end
    effect:Show()

    Art.Sound("IG_SPELLBOOK_OPEN")
    at(ABSORB, token, function() Art.Sound("PUT_DOWN_SMALL_CHAIN") end)
    for _, start in ipairs(seq.wobbles) do
        at(start, token, function() Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end)
    end
    at(CLICK - shift, token, function()
        Art.Sound("IG_QUEST_LIST_COMPLETE")
        ns.Collection.Announce(entry, true)
        if options.onReveal then options.onReveal() end
    end)
    at(FLY - shift, token, function()
        effect:Hide()
        launchHoming(x2, y2, size, options.homeX, options.homeY, options.homeSize, function()
            Art.Sound("LOOTWINDOWCOINSOUND")
            if options.onHome then options.onHome() end
        end, function() showToast(entry) end)
    end)
end
end)
