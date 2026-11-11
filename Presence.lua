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
    look.duration = Settings.Get("presenceDuration")
end
readLook()

-- Icon ------------------------------------------------------------------------------
--
-- Layers from back to front: halo, rotating star, ping wave, the icon itself.
-- Animate() draws one frame of it; the same object serves the nameplates and the preview.

local active = {} -- icons being animated

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

function Presence.CreateIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame:Hide()
    local icon = { frame = frame }
    icon.halo = layer(frame, MEDIA .. "Glow", "BACKGROUND", 0)
    icon.star = layer(frame, "Interface\\Cooldown\\star4", "BACKGROUND", 1)
    icon.wave = layer(frame, MEDIA .. "Ring", "BORDER", 0)
    icon.core = layer(frame, MEDIA .. "Ball", "ARTWORK", 0, "BLEND")
    icon.glint = layer(frame, MEDIA .. "Glow", "OVERLAY", 1)
    -- Gold light; each layer's own alpha (SetAlpha) is animated.
    for _, texture in ipairs({ icon.halo, icon.star, icon.wave, icon.glint }) do
        texture:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        texture:SetAlpha(0)
    end
    return icon
end

-- Starts the icon: duration 0 = stays until Stop, otherwise fades out after it.
local function play(icon, duration)
    local now = GetTime()
    if not (icon.frame:IsShown() and icon.leaving == nil and active[icon]) then icon.start = now end
    icon.duration = duration or 0
    icon.leaving = nil
    icon.phase = icon.phase or math.random() * 6
    active[icon] = true
    icon.frame:Show()
end

-- Fades out, then hides.
local function stop(icon, immediate)
    if immediate then
        active[icon] = nil
        icon.frame:Hide()
        icon.leaving = nil
        return
    end
    if active[icon] and not icon.leaving then icon.leaving = GetTime() end
end

local FADE_IN, FADE_OUT, POP = 0.35, 0.8, 0.35
local sin, max, min = math.sin, math.max, math.min

-- One frame of the icon. Returns false once it has faded out.
local function animate(icon, now)
    local t = now - icon.start
    local envelope = min(1, t / FADE_IN)
    if icon.duration > 0 and not icon.leaving and t > icon.duration then icon.leaving = now end
    if icon.leaving then
        envelope = envelope * max(0, 1 - (now - icon.leaving) / FADE_OUT)
        if envelope <= 0 then return false end
    end
    setIconTexture(icon, icon.forced or look.icon)

    local size = 30 * look.size * (icon.scale or 1)
    local glow = look.intensity
    local phase = t + icon.phase
    -- Pop on arrival, then a slow float.
    local pop = t < POP and (0.6 + 0.4 * sin(t / POP * math.pi / 2) + 0.12 * sin(t / POP * math.pi)) or 1
    local bob = sin(phase * 1.8) * 2.5 * look.size
    icon.frame:SetAlpha(look.alpha * envelope)

    local core = icon.core
    core:SetSize(size * pop, size * pop)
    core:ClearAllPoints()
    core:SetPoint("CENTER", icon.frame, "CENTER", 0, bob)

    -- Halo breathing behind the icon.
    local breath = 0.5 + 0.5 * sin(phase * 2.6)
    icon.halo:SetSize(size * (2.3 + 0.25 * breath), size * (2.3 + 0.25 * breath))
    icon.halo:SetPoint("CENTER", icon.frame, "CENTER", 0, bob)
    icon.halo:SetAlpha(min(1, glow * (0.45 + 0.25 * breath)))

    -- Slowly turning star.
    icon.star:SetSize(size * 2.1, size * 2.1)
    icon.star:SetPoint("CENTER", icon.frame, "CENTER", 0, bob)
    if icon.star.SetRotation then icon.star:SetRotation(phase * 0.5) end
    icon.star:SetAlpha(min(1, glow * (0.25 + 0.3 * (0.5 + 0.5 * sin(phase * 1.7 + 1)))))

    -- A wave every 2.4 s, and a stronger one when the icon arrives.
    local cycle = (t % 2.4) / 2.4
    local waveSize = size * (0.9 + 1.8 * cycle)
    icon.wave:SetSize(waveSize, waveSize)
    icon.wave:SetPoint("CENTER", icon.frame, "CENTER", 0, bob)
    local arrival = t < 2.4 and 1.6 or 1
    icon.wave:SetAlpha(min(1, glow * 0.55 * arrival * (1 - cycle)))

    -- Small glint passing over the icon.
    local glint = max(0, sin(phase * 1.3)) ^ 8
    icon.glint:SetSize(size * 0.9, size * 0.9)
    icon.glint:SetPoint("CENTER", icon.frame, "CENTER", size * 0.18, bob + size * 0.18)
    icon.glint:SetAlpha(min(1, glow * 0.8 * glint))
    return true
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    local now = GetTime()
    for icon in pairs(active) do
        if not animate(icon, now) then
            active[icon] = nil
            icon.frame:Hide()
            icon.leaving = nil
            if icon.onDone then icon.onDone(icon) end
        end
    end
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
    icon.frame:SetParent(nil)
    icon.frame:ClearAllPoints()
    spare[#spare + 1] = icon
end

local function attach(unit, plate)
    local icon = icons[unit]
    if not icon then
        icon = table.remove(spare) or Presence.CreateIcon(UIParent)
        icons[unit] = icon
    end
    icon.frame:SetParent(plate)
    icon.frame:ClearAllPoints()
    -- Above the Blizzard bar and its name.
    icon.frame:SetPoint("CENTER", plate, "CENTER", 0, 36)
    if icon.frame.SetIgnoreParentAlpha then icon.frame:SetIgnoreParentAlpha(true) end
    icon.frame:SetFrameLevel(plate:GetFrameLevel() + 10)
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

local function send(message, target)
    return safe(C_ChatInfo.SendAddonMessage, PREFIX, message, "WHISPER", target)
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
    if demo or not eligible(unit) or inRange(unit) == false then return end
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    local who = shortName(name)
    if queued[who] or not wantPing(who) then return end
    local entry = known[who] or {}
    known[who] = entry
    entry.address = safe(GetUnitName, unit, true) or entry.address or name
    queued[who] = true
    queue[#queue + 1] = who
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

local function heard(who, address)
    local entry = known[who] or {}
    known[who] = entry
    entry.has, entry.checked, entry.asking = true, GetTime(), nil
    entry.address = address or entry.address
    updatePlayer(who)
end

local function tick()
    local now = GetTime()
    for _, entry in pairs(known) do
        if entry.asking and now - entry.asking > WAIT_ANSWER then
            entry.has, entry.checked, entry.asking = false, now, nil
        end
    end
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

local TOOLTIP_ICON = "|T" .. MEDIA .. "Ball:14:14|t "

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

local ticker
local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, tick)
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
    startTicker()
    updateAll()
    if Presence.RefreshPreview then Presence.RefreshPreview() end
end)

function Presence.ToggleDemo()
    demo = not demo
    readLook()
    for unit in pairs(icons) do release(unit) end
    wipe(demoKnown)
    startTicker()
    scanPlates()
    updateAll()
    DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. (demo and L.PRESENCE_DEMO_ON or L.PRESENCE_DEMO_OFF))
    if Presence.RefreshDemoButton then Presence.RefreshDemoButton() end
end

function Presence.IsDemo()
    return demo
end

-- /foreverdex presence debug: what the module sees, to understand a missing icon.
function Presence.Debug()
    local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff63ded1ForeverDex|r presence: " .. text) end
    local function show(value)
        if value == nil then return "nil" end
        if not readable(value) then return "(secret)" end
        return tostring(value)
    end
    say(("demo=%s show=%s announce=%s combat=%s instance=%s ticker=%s queue=%d"):format(show(demo), show(look.show),
        show(look.announce), show(inCombat()), show(inInstance()), show(ticker ~= nil), #queue))
    local cvars = {}
    for _, name in ipairs({ "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowAll", "nameplateMaxDistance" }) do
        cvars[#cvars + 1] = name:gsub("nameplate", "") .. "=" .. show(getCVar(name))
    end
    say("cvars " .. table.concat(cvars, " "))
    local total, listed = 0, 0
    eachPlate(function(unit)
        total = total + 1
        if listed >= 6 or safe(UnitIsPlayer, unit) ~= true then return end
        listed = listed + 1
        local icon = icons[unit]
        local entry = entryFor(plates[unit])
        say(("%s name=%s tracked=%s attack=%s faction=%s range=%s has=%s icon=%s visible=%s"):format(
            unit, show(safe(UnitName, unit)), show(plates[unit]), show(safe(UnitCanAttack, "player", unit)),
            show(safe(UnitFactionGroup, unit)), show(inRange(unit)), show(entry and entry.has),
            show(icon ~= nil), show(icon and icon.frame:IsVisible())))
    end)
    local tracked, shown = 0, 0
    for _ in pairs(plates) do tracked = tracked + 1 end
    for _ in pairs(icons) do shown = shown + 1 end
    say(("plates=%d tracked=%d icons=%d"):format(total, tracked, shown))
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
preview.frame:SetFrameLevel(stage:GetFrameLevel() + 20)

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

-- In-game test: starts the demo and closes the options so the city shows.
local demoButton = B.action(right, L.PRESENCE_DEMO, 180, function()
    local starting = not demo
    Presence.ToggleDemo()
    if starting and SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
end, L.PRESENCE_DEMO_TIP)

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

function Presence.RefreshPreview()
    if not page:IsVisible() then return end
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
