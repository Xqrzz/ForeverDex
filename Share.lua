local _, ns = ...
ns.Module(function()
local L, Catalog, Settings, Achievements, Collection = ns.L, ns.Catalog, ns.Settings, ns.Achievements, ns.Collection
local Share = {}
ns.Share = Share

-- Announces captures and achievements to other players, in the guild, the group or a
-- channel the player joined. Off by default. Never in a Blizzard channel (General,
-- Trade, LocalDefense…), whatever the player types: ForeverDex must not spam them.
--
-- The message is built at the capture, then sent when the ball clicks (or with the
-- achievement alert), so the guild does not learn the result before the player.

local MAX_LENGTH = 255  -- longest message the chat accepts, in bytes
local REVEAL_LIMIT = 10 -- seconds: a message still waiting for its reveal leaves anyway
local NOOP = function() end

-- Blizzard channels ------------------------------------------------------------------

-- /1 and /2 are General and Trade on every client.
local OFFICIAL_IDS = { [1] = true, [2] = true }

-- Names of the server channels in the supported languages. The client's own list is
-- added on top: this one only covers a client that does not provide it.
local OFFICIAL_NAMES = {
    "General", "Trade", "LocalDefense", "WorldDefense", "LookingForGroup", "GuildRecruitment",
    "Services", "NewcomerChat", "HardcoreDeaths",
    "Général", "Commerce", "DéfenseLocale", "DéfenseUniverselle", "RechercheDeGroupe",
    "RecrutementDeGuilde", "Allgemein", "Handel", "LokaleVerteidigung", "WeltVerteidigung",
    "SucheNachGruppe", "Gildenrekrutierung", "Comercio", "DefensaLocal", "DefensaGeneral",
    "BuscarGrupo", "ReclutamientoDeHermandad", "Generale", "Commercio", "DifesaLocale",
    "DifesaMondiale", "CercaGruppo", "ReclutamentoGilde", "Geral", "Comércio", "DefesaLocal",
    "DefesaMundial", "ProcurandoGrupo", "RecrutamentoDeGuilda", "Общий", "Торговля",
    "Оборона", "ПоискСпутников", "ГильдииНабор",
}

-- Case, spaces and separators do not count: "Local Defense" is "localdefense".
local function squash(name)
    return (name:lower():gsub("[%s%-_:%.]", ""))
end

local officials
local function isOfficial(name)
    if not officials then
        officials = {}
        for _, official in ipairs(OFFICIAL_NAMES) do officials[#officials + 1] = squash(official) end
        if EnumerateServerChannels then
            for _, official in ipairs({ EnumerateServerChannels() }) do
                if type(official) == "string" and official ~= "" then officials[#officials + 1] = squash(official) end
            end
        end
    end
    -- A zone channel is named "General - Elwynn Forest": the start of the name decides.
    local squashed = squash(name)
    for _, official in ipairs(officials) do
        if squashed:sub(1, #official) == official then return true end
    end
    return false
end

-- State of the custom channel: "ok" with its number and name, otherwise the reason
-- it cannot be used ("empty", "number", "official", "missing").
function Share.CheckChannel(name)
    name = name or ""
    if name == "" then return "empty" end
    if name:match("^%d+$") then return "number" end
    if isOfficial(name) then return "official" end
    local id, fullName = GetChannelName(name)
    if not id or id == 0 then return "missing" end
    if OFFICIAL_IDS[id] or (type(fullName) == "string" and isOfficial(fullName)) then return "official" end
    return "ok", id, type(fullName) == "string" and fullName or name
end

-- Destinations -----------------------------------------------------------------------

local function groupChat()
    local instance = LE_PARTY_CATEGORY_INSTANCE
    if instance and IsInGroup and IsInGroup(instance) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0) then return "PARTY" end
end

-- Chat type and channel number for a destination setting (guild, group, custom),
-- or nil and the reason it is unavailable right now. The settings are shared by every
-- character of the account: a character without a guild or group sends nothing.
local function destination(choice)
    if choice == "group" then
        local chatType = groupChat()
        if chatType then return chatType end
        return nil, L.SHARE_NO_GROUP
    elseif choice == "custom" then
        local name = Settings.Get("shareCustomChannel")
        local status, id = Share.CheckChannel(name)
        if status == "ok" then return "CHANNEL", id end
        return nil, Share.StatusText(status, name)
    end
    if IsInGuild and IsInGuild() then return "GUILD" end
    return nil, L.SHARE_NO_GUILD
end

local CHANNEL_LABELS = { guild = "SHARE_CHANNEL_GUILD", group = "SHARE_CHANNEL_GROUP", custom = "SHARE_CHANNEL_CUSTOM" }
local function destinationLabel(choice)
    if choice == "custom" then
        local status, id, name = Share.CheckChannel(Settings.Get("shareCustomChannel"))
        if status == "ok" then return ("/%d %s"):format(id, name) end
    end
    return L[CHANNEL_LABELS[choice] or "SHARE_CHANNEL_GUILD"]
end

-- Each reason is told once per session: a player out of a group captures often.
local warned = {}
local function warn(reason)
    if warned[reason] then return end
    warned[reason] = true
    print(L.CHAT_PREFIX .. L.SHARE_SKIPPED:format(reason))
end

-- Messages ---------------------------------------------------------------------------

-- Fills "{name}", "{count}"… Translations can order the fields as they like.
local function fill(template, values)
    return (template:gsub("{(%a+)}", function(field)
        local value = values[field]
        if value ~= nil then return tostring(value) end
    end))
end

-- The chat refuses colour codes and escapes in a message: only plain text leaves.
local function plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("[\r\n]+", " ")
    return text
end

-- Cut at the chat limit without splitting a character in two.
local function clip(text)
    if #text <= MAX_LENGTH then return text end
    local cut = MAX_LENGTH - 3
    while cut > 0 do
        local nextByte = text:byte(cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then break end
        cut = cut - 1
    end
    return text:sub(1, cut) .. "..."
end

-- A random line, never the same twice in a row from the same list.
local lastPick = {}
local function pick(lines)
    local index = math.random(#lines)
    if #lines > 1 and index == lastPick[lines] then index = index % #lines + 1 end
    lastPick[lines] = index
    return lines[index]
end

local function finish(text)
    if Settings.Get("shareTag") then text = L.SHARE_TAG .. text end
    return clip(plain(text))
end

local function standardProgress()
    local have, total = 0, 0
    local cards = ForeverDexDB and ForeverDexDB.cards or {}
    for _, slot in ipairs(Catalog.slots) do
        if slot.sex then
            total = total + 1
            if cards[slot.key] then have = have + 1 end
        end
    end
    return have, total
end

-- What kind of capture this is: new, replace, bonus or pet.
local function captureKind(entry, isNew)
    local slot = Catalog.slotByKey[entry.key]
    if slot and slot.pet then return "pet" end
    if entry.combination then return "bonus" end
    return isNew and "new" or "replace"
end

local CAPTURE_LINES = {
    new = "SHARE_CAPTURE_LINES", replace = "SHARE_REPLACE_LINES",
    bonus = "SHARE_BONUS_LINES", pet = "SHARE_PET_LINES",
}

local function captureText(entry, kind)
    local have, total = standardProgress()
    return finish(fill(pick(L[CAPTURE_LINES[kind]]), {
        name = entry.name, family = entry.family or "", owner = entry.owner or "",
        count = have, total = total,
    }))
end

local function achievementText(list)
    if #list == 1 then
        local achievement = list[1]
        return finish(fill(pick(L.SHARE_ACHIEVEMENT_LINES), {
            achievement = achievement.name, points = achievement.points,
        }))
    end
    local names = {}
    for i, achievement in ipairs(list) do names[i] = achievement.name end
    return finish(fill(L.SHARE_ACHIEVEMENT_MANY, { count = #list, list = table.concat(names, ", ") }))
end

-- Sending ----------------------------------------------------------------------------

-- Each kind of announcement waits shareCooldown seconds after the previous one.
local lastSent = {}
local function ready(topic)
    local now = GetTime()
    if lastSent[topic] and now - lastSent[topic] < (Settings.Get("shareCooldown") or 0) then return false end
    lastSent[topic] = now
    return true
end

-- Last check before anything leaves: the chat type is one ForeverDex uses, and the
-- guild, group or channel exists right now. Any other chat type (say, yell,
-- whisper…) is refused, so a message can never end up somewhere unexpected.
local AVAILABLE = {
    GUILD = function() return IsInGuild and IsInGuild() end,
    PARTY = function() return groupChat() == "PARTY" end,
    RAID = function() return groupChat() == "RAID" end,
    INSTANCE_CHAT = function() return groupChat() == "INSTANCE_CHAT" end,
    CHANNEL = function(target)
        if type(target) ~= "number" or OFFICIAL_IDS[target] then return false end
        local id, fullName = GetChannelName(target)
        return id ~= nil and id == target and not (type(fullName) == "string" and isOfficial(fullName))
    end,
}

-- Sends only when the destination passes the check; returns true when sent.
local function safeSend(text, chatType, target)
    local available = AVAILABLE[chatType]
    if not available or not available(target) or type(text) ~= "string" or text == "" then return false end
    SendChatMessage(text, chatType, nil, target)
    return true
end

-- Returns the function that sends the message, to call at the reveal. It sends once,
-- and REVEAL_LIMIT seconds later at most. A channel may only accept a message sent
-- during the player's click: that one leaves at once.
local function schedule(choice, chatType, target, text)
    if chatType == "CHANNEL" then
        if not safeSend(text, chatType, target) then warn(L.SHARE_UNAVAILABLE) end
        return NOOP
    end
    local sent = false
    local function release()
        if sent then return end
        sent = true
        -- The player may have left the guild or the group while the ball flew: the
        -- destination is read again, and nothing leaves if it no longer exists.
        local currentType, currentTarget = destination(choice)
        if not currentType then
            warn(currentTarget)
            return
        end
        if not safeSend(text, currentType, currentTarget) then warn(L.SHARE_UNAVAILABLE) end
    end
    C_Timer.After(REVEAL_LIMIT, release)
    return release
end

-- Prepares the announcement of a capture, called as soon as the card is saved.
-- Returns the function to call when the capture is revealed (always a function).
function Share.Capture(entry, isNew)
    if not Settings.Get("shareCaptures") or not entry or not entry.name then return NOOP end
    local kind = captureKind(entry, isNew)
    if kind == "pet" and not Settings.Get("sharePets") then return NOOP end
    if kind == "bonus" and not Settings.Get("shareBonus") then return NOOP end
    if kind == "replace" and Settings.Get("shareCaptureScope") ~= "all" then return NOOP end
    local choice = Settings.Get("shareCaptureChannel")
    local chatType, target = destination(choice)
    if not chatType then
        warn(target)
        return NOOP
    end
    if not ready("capture") then return NOOP end
    return schedule(choice, chatType, target, captureText(entry, kind))
end

-- Prepares the announcement of the achievements earned together (one message for
-- all of them). Returns the function to call with their alert (always a function).
function Share.Achievements(list)
    if not Settings.Get("shareAchievements") or not list then return NOOP end
    local minimum, kept = Settings.Get("shareAchievementMin") or 0, {}
    for _, achievement in ipairs(list) do
        if (achievement.points or 0) >= minimum then kept[#kept + 1] = achievement end
    end
    if #kept == 0 then return NOOP end
    local choice = Settings.Get("shareAchievementChannel")
    local chatType, target = destination(choice)
    if not chatType then
        warn(target)
        return NOOP
    end
    if not ready("achievement") then return NOOP end
    return schedule(choice, chatType, target, achievementText(kept))
end

-- Shares a card of the collection on demand (card menu, detail page), in the channel
-- chosen for captures. Sent at once, during the player's click: a custom channel only
-- accepts it then. A few seconds between two shares, so a double click sends one.
local SHOW_COOLDOWN = 5
local lastShow
function Share.Show(entry, slot)
    if not entry or not entry.name or not slot then return end
    local chatType, target = destination(Settings.Get("shareCaptureChannel"))
    if not chatType then
        print(L.CHAT_PREFIX .. L.SHARE_SKIPPED:format(target))
        return
    end
    local now = GetTime()
    if lastShow and now - lastShow < SHOW_COOLDOWN then
        print(L.CHAT_PREFIX .. L.SHARE_SHOW_WAIT)
        return
    end
    -- A pet carries its family, without an article: the game does not give its gender.
    local name = entry.name
    if slot.pet and entry.family and entry.family ~= "" then
        name = ("%s (%s)"):format(name, entry.family)
    end
    local text = fill(pick(L.SHARE_SHOW_LINES), { name = name })
    if safeSend(finish(text), chatType, target) then
        lastShow = now
    else
        print(L.CHAT_PREFIX .. L.SHARE_SKIPPED:format(L.SHARE_UNAVAILABLE))
    end
end

-- Preview: the message is shown to the player only, with where it would go.
local function preview(channelKey, text)
    local choice = Settings.Get(channelKey)
    print(L.CHAT_PREFIX .. L.SHARE_PREVIEW_LINE:format(destinationLabel(choice), text))
    local chatType, reason = destination(choice)
    if not chatType then print(L.CHAT_PREFIX .. L.SHARE_SKIPPED:format(reason)) end
end

function Share.PreviewCapture()
    local name = Collection.PlayerName() or UNKNOWNOBJECT
    preview("shareCaptureChannel", captureText({ name = name }, "new"))
end

function Share.PreviewAchievement()
    local list = Achievements and Achievements.list
    if not list or #list == 0 then return end
    preview("shareAchievementChannel", achievementText({ list[math.random(#list)] }))
end

-- Settings page ----------------------------------------------------------------------

local STATUS_TEXTS = {
    empty = "SHARE_STATUS_EMPTY", number = "SHARE_STATUS_NUMBER",
    official = "SHARE_STATUS_OFFICIAL", missing = "SHARE_STATUS_MISSING",
}
function Share.StatusText(status, name, id, fullName)
    if status == "ok" then return L.SHARE_STATUS_OK:format(id, fullName) end
    -- The name can appear twice ("not joined: X (/join X)").
    return L[STATUS_TEXTS[status]]:format(name or "", name or "")
end

local page, left, right = Settings.AddPage(L.SHARE_TITLE, L.SHARE_SUBTITLE)
local B = Settings.Builder
local channels = {
    { "guild", L.SHARE_CHANNEL_GUILD },
    { "group", L.SHARE_CHANNEL_GROUP },
    { "custom", L.SHARE_CHANNEL_CUSTOM },
}

B.section(left, L.SHARE_CAPTURES_SECTION)
B.checkbox(left, "shareCaptures", L.SHARE_CAPTURES, L.SHARE_CAPTURES_TIP)
B.choice(left, "shareCaptureChannel", L.SHARE_CHANNEL, channels, L.SHARE_CHANNEL_TIP)
B.choice(left, "shareCaptureScope", L.SHARE_SCOPE, {
    { "new", L.SHARE_SCOPE_NEW },
    { "all", L.SHARE_SCOPE_ALL },
}, L.SHARE_SCOPE_TIP)
B.checkbox(left, "shareBonus", L.SHARE_BONUS, L.SHARE_BONUS_TIP)
B.checkbox(left, "sharePets", L.SHARE_PETS, L.SHARE_PETS_TIP)

B.section(left, L.SHARE_ACHIEVEMENTS_SECTION)
B.checkbox(left, "shareAchievements", L.SHARE_ACHIEVEMENTS, L.SHARE_ACHIEVEMENTS_TIP)
B.choice(left, "shareAchievementChannel", L.SHARE_CHANNEL, channels, L.SHARE_CHANNEL_TIP)
B.choice(left, "shareAchievementMin", L.SHARE_MINIMUM, {
    { 0, L.SHARE_MINIMUM_ALL },
    { 10, L.SHARE_MINIMUM_POINTS:format(10) },
    { 25, L.SHARE_MINIMUM_POINTS:format(25) },
    { 50, L.SHARE_MINIMUM_POINTS:format(50) },
}, L.SHARE_MINIMUM_TIP)

B.section(right, L.SHARE_CUSTOM_SECTION)
B.input(right, "shareCustomChannel", L.SHARE_CUSTOM_NAME, L.SHARE_CUSTOM_TIP, 31)
local status = B.note(right, "", 34)
B.note(right, L.SHARE_CUSTOM_NOTE, 44)

local function refreshStatus()
    if not page:IsVisible() then return end
    local name = Settings.Get("shareCustomChannel")
    local state, id, fullName = Share.CheckChannel(name)
    status:SetText(Share.StatusText(state, name, id, fullName))
    if state == "ok" then
        status:SetTextColor(0.4, 1, 0.4)
    elseif state == "empty" then
        status:SetTextColor(0.75, 0.75, 0.75)
    else
        status:SetTextColor(1, 0.5, 0.3)
    end
end
page:HookScript("OnShow", refreshStatus)
Settings.OnChange(function(key)
    if key == nil or key == "shareCustomChannel" then refreshStatus() end
end)
-- Joining or leaving a channel while the page is open updates the status line.
local channelEvents = CreateFrame("Frame")
channelEvents:RegisterEvent("CHANNEL_UI_UPDATE")
channelEvents:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
channelEvents:SetScript("OnEvent", refreshStatus)

B.section(right, L.SHARE_SENDING_SECTION)
B.checkbox(right, "shareTag", L.SHARE_TAG_OPTION, L.SHARE_TAG_TIP)
B.slider(right, "shareCooldown", L.SHARE_COOLDOWN, 0, 300, 5, function(value)
    return value == 0 and L.SHARE_COOLDOWN_NONE or L.SHARE_SECONDS:format(value)
end, L.SHARE_COOLDOWN_TIP)

B.section(right, L.SHARE_PREVIEW_SECTION)
B.action(right, L.SHARE_PREVIEW_CAPTURE, 220, Share.PreviewCapture, L.SHARE_PREVIEW_TIP)
B.action(right, L.SHARE_PREVIEW_ACHIEVEMENT, 220, Share.PreviewAchievement, L.SHARE_PREVIEW_TIP)

function Share.OpenSettings()
    Settings.OpenPage(page)
end
end)
