local _, ns = ...
ns.Module(function()
local L, Settings, Art = ns.L, ns.Settings, ns.Art
local Presence = {}
ns.Presence = Presence

-- Presence: a glowing icon above the nearby players who have ForeverDex ---------------
--
-- No API tells which addons another player runs, so the clients introduce themselves
-- with whispered addon messages (invisible in chat), on the prefix of Duel.lua:
--   P       ping, sent when a friendly player's nameplate appears within the chosen distance
--   P\tq    the same from a player who does not want to be shown (quiet)
--   H       answer: "I have ForeverDex"
-- Older versions ignore these message types (see "Comparison compatibility").
--
-- The icon hangs from the player's nameplate, the only frame that follows a character
-- in the 3D world. While the option is on, the friendly nameplates are switched on;
-- the values the player had are saved first and given back when the option is turned
-- off and at logout (same approach as the Lueur addon). Plates the player would not
-- have seen keep their Blizzard bar hidden: only the ForeverDex icon remains.
-- The game forbids touching friendly nameplates in dungeons and raids: no icon there.

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

local FRIEND_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyPlayers" }
local MANAGED_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowAll", "nameplateMaxDistance" }

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

local function getCVar(name)
    local ok, value = pcall(C_CVar and C_CVar.GetCVar or GetCVar, name)
    if ok then return value end
end

-- Only the settings this client knows (the list varies between versions).
local function setCVar(name, value)
    if getCVar(name) == nil then return end
    pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end

local pendingCVars -- "apply" or "restore", waiting for the end of combat

local function cvarsLookApplied()
    if getCVar("nameplateShowAll") ~= nil and getCVar("nameplateShowAll") ~= "1" then return false end
    for _, name in ipairs(FRIEND_CVARS) do
        local value = getCVar(name)
        if value ~= nil and value ~= "1" then return false end
    end
    return true
end

local function applyCVars()
    if not ForeverDexDB then return end
    if InCombatLockdown() then pendingCVars = "apply" return end
    local db = ForeverDexDB
    if db.presenceCVarsReturned then
        -- Given back at the last logout: what the client holds now are the player's
        -- values, maybe changed since. They are read again, unless they are ours.
        db.presenceCVarsReturned = nil
        if not cvarsLookApplied() then db.presenceCVars = nil end
    end
    db.presenceCVars = db.presenceCVars or {}
    local saved = db.presenceCVars
    for _, name in ipairs(MANAGED_CVARS) do
        if saved[name] == nil then saved[name] = getCVar(name) or false end
    end
    for _, name in ipairs(FRIEND_CVARS) do setCVar(name, 1) end
    setCVar("nameplateShowAll", 1)
    local distance = tonumber(saved.nameplateMaxDistance)
    -- Plates at least as far as the chosen distance; a player who shows them farther
    -- keeps their value.
    local wanted = look.range >= FAR and FAR or 30
    if distance and distance < wanted then
        setCVar("nameplateMaxDistance", wanted)
    elseif distance then
        setCVar("nameplateMaxDistance", distance)
    end
end

local function restoreCVars()
    if not ForeverDexDB then return end
    if InCombatLockdown() then pendingCVars = "restore" return end
    local saved = ForeverDexDB.presenceCVars
    if saved then
        for name, value in pairs(saved) do
            if value ~= false then setCVar(name, value) end
        end
    end
    ForeverDexDB.presenceCVars = nil
    ForeverDexDB.presenceCVarsReturned = nil
end

-- At logout the game gets its values back, so disabling or removing ForeverDex from
-- the addon list leaves nothing behind. They stay saved in case the client does not
-- store them (game closed abruptly).
local function returnCVars()
    local db = ForeverDexDB
    if not db or not db.presenceCVars or InCombatLockdown() then return end
    for name, value in pairs(db.presenceCVars) do
        if value ~= false then setCVar(name, value) end
    end
    db.presenceCVarsReturned = true
end

-- Nameplates ------------------------------------------------------------------------

local known = {}   -- [short name] = { has, checked, asking, shown, address }
local plates = {}  -- [unit] = short name of the friendly player on that plate
local icons = {}   -- [unit] = icon hanging from that plate
local muted = {}   -- [plate] = Blizzard unit frame hidden on it
local spare = {}   -- icons no longer used
local queue = {}   -- short names waiting for their ping, in order
local queued = {}
local answered = {} -- [short name] = time of our last answer

local function getPlate(unit)
    return C_NamePlate and safe(C_NamePlate.GetNamePlateForUnit, unit)
end

-- Would the player's own settings show this plate? Then its Blizzard bar stays.
local function plateOwed(unit)
    local saved = ForeverDexDB and ForeverDexDB.presenceCVars
    if not saved or ForeverDexDB.presenceCVarsReturned then return true end
    if saved.nameplateShowAll == "0" and not inCombat() then return false end
    local hostile = safe(UnitCanAttack, "player", unit)
    if hostile ~= false then return true end
    local knownValue = false
    for _, name in ipairs(FRIEND_CVARS) do
        if saved[name] == "1" then return true end
        knownValue = knownValue or saved[name] ~= false
    end
    return not knownValue
end

local function unmute(plate)
    local frame = muted[plate]
    if frame then pcall(frame.SetAlpha, frame, 1) end
    muted[plate] = nil
end

local function mute(plate, unit)
    if not look.show or plateOwed(unit) then unmute(plate) return end
    local ok, frame = pcall(function() return plate.UnitFrame end)
    if not ok or type(frame) ~= "table" then return end
    if pcall(frame.SetAlpha, frame, 0) then muted[plate] = frame end
end

local function unmuteAll()
    for plate in pairs(muted) do unmute(plate) end
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

local function release(unit)
    local icon = icons[unit]
    if not icon then return end
    icons[unit] = nil
    icon.onDone = function(done)
        done.frame:SetParent(nil)
        done.frame:ClearAllPoints()
        done.onDone = nil
        spare[#spare + 1] = done
    end
    stop(icon, true)
    icon.onDone(icon)
end

local function attach(unit, plate)
    local icon = icons[unit]
    if not icon then
        icon = table.remove(spare) or Presence.CreateIcon(UIParent)
        icons[unit] = icon
    end
    icon.frame:SetParent(plate)
    icon.frame:ClearAllPoints()
    -- Just above the head when the Blizzard bar is hidden, above the bar otherwise.
    icon.frame:SetPoint("CENTER", plate, "CENTER", 0, muted[plate] and 10 or 36)
    if icon.frame.SetIgnoreParentAlpha then icon.frame:SetIgnoreParentAlpha(true) end
    icon.frame:SetFrameLevel(plate:GetFrameLevel() + 10)
    return icon
end

-- Shows or hides the icon of one nameplate unit, from what is known of its player.
local demoKnown = {} -- [short name] = what the demo pretends to know

local function update(unit)
    local who = plates[unit]
    local entry = who and known[who]
    if demo and who then
        demoKnown[who] = demoKnown[who] or { has = true }
        entry = demoKnown[who]
    end
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

local function enqueue(who)
    if demo or queued[who] or not wantPing(who) then return end
    queued[who] = true
    queue[#queue + 1] = who
end

-- Sends the next ping in the queue, if the moment allows it.
local lastPing = 0
local function pingNext(now)
    if #queue == 0 or now - lastPing < PING_GAP or not look.show or demo then return end
    if inCombat() or inInstance() then return end
    local who = table.remove(queue, 1)
    queued[who] = nil
    local entry = known[who] or {}
    known[who] = entry
    -- Still in sight? The plate gives the address the whisper expects.
    local address
    for unit, name in pairs(plates) do
        if name == who and inRange(unit) ~= false then
            address = safe(GetUnitName, unit, true) or entry.address
            break
        end
    end
    if not address or not wantPing(who) then return end
    entry.address = address
    entry.asking = now
    lastPing = now
    send(look.announce and "P" or "P\tq", address)
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
    for who, entry in pairs(known) do
        if entry.asking and now - entry.asking > WAIT_ANSWER then
            entry.has, entry.checked, entry.asking = false, now, nil
        end
    end
    for unit, who in pairs(plates) do
        if wantPing(who) and inRange(unit) ~= false then enqueue(who) end
    end
    pingNext(now)
    -- The game may give the bar its alpha back: hidden again.
    for plate, frame in pairs(muted) do
        if frame.GetAlpha and frame:GetAlpha() > 0 then pcall(frame.SetAlpha, frame, 0) end
    end
    updateAll()
end

local function addPlate(unit)
    local plate = getPlate(unit)
    if plate then mute(plate, unit) end
    if not eligible(unit) then plates[unit] = nil return end
    local name = safe(UnitName, unit)
    if not name or name == "" then return end
    local who = shortName(name)
    plates[unit] = who
    if wantPing(who) and inRange(unit) ~= false then enqueue(who) end
    update(unit)
end

local function removePlate(unit)
    local plate = getPlate(unit)
    if plate then unmute(plate) end
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

local function remuteAll()
    eachPlate(function(unit, plate) mute(plate, unit) end)
end

-- Events ----------------------------------------------------------------------------

local ticker
local entered = false -- PLAYER_ENTERING_WORLD seen: the game settings can be read
local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, tick)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
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
            if not text:find("\tq", 2, true) then heard(who, sender) end
            local now = GetTime()
            if look.announce and now - (answered[who] or -math.huge) > ANSWER_GAP then
                answered[who] = now
                send("H", sender)
            end
        else
            heard(who, sender)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        addPlate(a)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        removePlate(a)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if event == "PLAYER_REGEN_ENABLED" and pendingCVars then
            local pending = pendingCVars
            pendingCVars = nil
            if pending == "apply" and look.show then applyCVars() elseif pending == "restore" then restoreCVars() end
        end
        -- Without "always show", the player sees the plates in combat only: bars follow.
        remuteAll()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The game settings are read here, once the client has loaded them.
        entered = true
        if look.show then
            applyCVars()
        elseif ForeverDexDB and ForeverDexDB.presenceCVars then
            restoreCVars()
        end
        scanPlates()
    elseif event == "PLAYER_LOGOUT" then
        returnCVars()
    end
end)

Settings.OnChange(function(key)
    if key ~= nil and not key:find("^presence") then return end
    readLook()
    -- On load (key = nil) the game settings wait for PLAYER_ENTERING_WORLD; after it,
    -- key = nil means "Default settings" and is handled like a change of the option.
    if key == "presenceShow" or (key == nil and entered) then
        if look.show then
            applyCVars()
            scanPlates()
        else
            unmuteAll()
            restoreCVars()
        end
    elseif key == "presenceRange" then
        if look.show then applyCVars() end
    elseif key == "presenceDuration" then
        -- Permanent and ping icons do not end the same way: they start again.
        for unit in pairs(icons) do release(unit) end
        for _, entry in pairs(known) do entry.shown = nil end
    end
    if look.show then startTicker() end
    updateAll()
    if Presence.RefreshPreview then Presence.RefreshPreview() end
end)

function Presence.ToggleDemo()
    demo = not demo
    local wasShown = look.show
    readLook()
    for unit in pairs(icons) do release(unit) end
    wipe(demoKnown)
    if demo then
        if not wasShown then applyCVars() end
        startTicker()
        scanPlates()
    elseif not look.show then
        unmuteAll()
        restoreCVars()
    end
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
    say(("demo=%s show=%s option=%s combat=%s instance=%s ticker=%s entered=%s"):format(show(demo), show(look.show),
        show(Settings.Get("presenceShow")), show(inCombat()), show(inInstance()), show(ticker ~= nil), show(entered)))
    local cvars = {}
    for _, name in ipairs(MANAGED_CVARS) do cvars[#cvars + 1] = name:gsub("nameplate", "") .. "=" .. show(getCVar(name)) end
    say("cvars " .. table.concat(cvars, " "))
    local saved = ForeverDexDB and ForeverDexDB.presenceCVars
    if saved then
        local list = {}
        for name, value in pairs(saved) do list[#list + 1] = name:gsub("nameplate", "") .. "=" .. show(value) end
        say("saved " .. table.concat(list, " ") .. (ForeverDexDB.presenceCVarsReturned and " (returned)" or ""))
    else
        say("saved none")
    end
    local total, listed = 0, 0
    eachPlate(function(unit, plate)
        total = total + 1
        if listed >= 6 then return end
        if safe(UnitIsPlayer, unit) ~= true then return end
        listed = listed + 1
        local icon = icons[unit]
        say(("%s name=%s tracked=%s player=%s self=%s attack=%s faction=%s range=%s muted=%s icon=%s shown=%s visible=%s alpha=%s"):format(
            unit, show(safe(UnitName, unit)), show(plates[unit]), show(safe(UnitIsPlayer, unit)),
            show(safe(UnitIsUnit, unit, "player")), show(safe(UnitCanAttack, "player", unit)),
            show(safe(UnitFactionGroup, unit)), show(inRange(unit)), show(muted[plate] ~= nil),
            show(icon ~= nil), show(icon and icon.frame:IsShown()), show(icon and icon.frame:IsVisible()),
            show(icon and icon.frame:GetEffectiveAlpha())))
    end)
    local tracked, active = 0, 0
    for _ in pairs(plates) do tracked = tracked + 1 end
    for _ in pairs(icons) do active = active + 1 end
    say(("plates=%d tracked=%d icons=%d (GetNamePlates=%s)"):format(total, tracked, active,
        show(C_NamePlate and C_NamePlate.GetNamePlates ~= nil)))
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
