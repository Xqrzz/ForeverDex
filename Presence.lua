local _, ns = ...
ns.Module(function()
local L, Settings, Art, Util = ns.L, ns.Settings, ns.Art, ns.Util
local Presence = {}
ns.Presence = Presence
-- The icon is drawn by PresenceIcon.lua, the options page built by PresenceOptions.lua.
local Icon = ns.PresenceIcon
local play, stop, setLayer, restyleAll = Icon.Play, Icon.Stop, Icon.SetLayer, Icon.RestyleAll
local isActive = Icon.IsActive

-- Presence: a glowing icon above the nearby players who have ForeverDex ---------------
--
-- No API tells which addons another player runs, so the clients introduce themselves
-- with whispered addon messages (invisible in chat), through Comm.lua:
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

local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"
-- Detection distance (presenceRange): 10 and 30 are checked with CheckInteractDistance
-- (duel range, about 10 yards, and follow range, about 28 yards). Farther, the
-- nameplates decide: the game creates them up to nameplateMaxDistance.
local FAR = 40
Presence.FAR = FAR
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


local readable, safe, shortName = Util.Readable, Util.Safe, Util.ShortName

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
local look = Icon.look
local function readLook()
    look.show = Settings.Get("presenceShow") or demo
    look.announce = Settings.Get("presenceAnnounce")
    look.icon = Icon.ByKey[Settings.Get("presenceIcon")] or Icon.CHOICES[1]
    look.intensity = Settings.Get("presenceIntensity")
    look.alpha = Settings.Get("presenceAlpha")
    look.size = Settings.Get("presenceSize")
    look.range = Settings.Get("presenceRange")
    look.height = Settings.Get("presenceHeight")
    look.duration = Settings.Get("presenceDuration")
end
readLook()

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
        icon = table.remove(spare) or Icon.Create(UIParent)
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
        if range ~= false and not (icon and isActive(icon)) and now - (entry.shown or -math.huge) > REPLAY_GAP then
            entry.shown = now
            play(attach(unit, plate), look.duration)
        elseif icon and isActive(icon) then
            entry.shown = now
            attach(unit, plate)
        end
    elseif range == false then
        if icon then stop(icon) end
    else
        icon = attach(unit, plate)
        if not isActive(icon) or icon.leaving then play(icon, 0) end
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
    return safe(ns.Comm.Whisper, message, target)
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

-- Pings and answers, received through Comm.lua.
ns.Comm.On("PH", function(text, sender)
    local kind = text:sub(1, 1)
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
end)

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, a)
    if event == "NAME_PLATE_UNIT_ADDED" then
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

-- Number of nearby players known to have ForeverDex, for /foreverdex presence.
function Presence.Report()
    local count, names = 0, {}
    for who, entry in pairs(known) do
        if entry.has then count = count + 1 names[#names + 1] = who end
    end
    table.sort(names)
    DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. L.PRESENCE_REPORT:format(count, table.concat(names, ", ")))
end
end)
