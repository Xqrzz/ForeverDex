local _, ns = ...
ns.Module(function()
local L, Catalog, Settings, Util = ns.L, ns.Catalog, ns.Settings, ns.Util
local Collection = {}
ns.Collection = Collection
local onChanged, onCapture
local readable = Util.Readable

local function setCharacterName(entry, firstName, surname)
    entry.firstName = firstName
    entry.surname = surname
    entry.name = surname and (firstName .. " " .. surname) or firstName
    entry.id = entry.name
end

-- Reads the target, or the given unit (party member, clicked portrait…).
function Collection.ReadTarget(unit)
    unit = unit or "target"
    local player = UnitIsPlayer(unit)
    if not readable(player) or not player then return end
    local selfTarget = UnitIsUnit(unit, "player")
    if not readable(selfTarget) or selfTarget then return end
    -- In Forever, UnitFullName returns the first and last name separately.
    local firstName, surname = UnitFullName(unit)
    local _, _, race = UnitRace(unit)
    local _, _, class = UnitClass(unit)
    local sex = UnitSex(unit)
    -- The client answers UNKNOWNOBJECT until the unit has fully loaded.
    if not readable(firstName) or firstName == "" or firstName == UNKNOWNOBJECT
        or not readable(surname) or surname == ""
        or not readable(race) or not readable(class) or not readable(sex) then
        return
    end
    local slot = Catalog.byKey[Catalog.SlotKey(race, class, sex)]
    if not slot then return end
    local entry = { key = slot.key }
    setCharacterName(entry, firstName, surname)
    -- Optional details for the detail page: they are never used to identify the character.
    local level = UnitLevel(unit)
    if readable(level) and level > 0 then entry.level = level end
    local guild = GetGuildInfo(unit)
    if readable(guild) and guild ~= "" then
        entry.guild = guild
        local faction = UnitFactionGroup(unit)
        if not readable(faction) or (faction ~= "Horde" and faction ~= "Alliance") then
            faction = Catalog.RaceFaction(slot.raceID)
        end
        entry.guildID = ns.Guilds.ID(guild, faction)
    end
    return entry
end

-- Hunter pets ------------------------------------------------------------------

-- "Beast" in each client language: demons, elementals and ghouls also have a
-- family, but only beasts are hunter pets. An unknown language accepts every family.
local BEAST = {
    enUS = "Beast", enGB = "Beast", frFR = "Bête", deDE = "Wildtier", esES = "Bestia", esMX = "Bestia",
    itIT = "Bestia", ptBR = "Fera", ruRU = "Животное", koKR = "야수", zhCN = "野兽", zhTW = "野獸",
}

-- The owner only appears in the tooltip, as "Name's Pet". The pattern is built
-- from the game's own format, so it follows the client language.
local function ownerPattern(format)
    if type(format) ~= "string" then return end
    local escaped = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    local pattern = escaped:gsub("%%s", "(.+)")
    return "^" .. pattern .. "$"
end
local OWNER_PATTERNS = {}
for _, format in ipairs({ UNITNAME_TITLE_PET, UNITNAME_TITLE_MINION, UNITNAME_TITLE_GUARDIAN }) do
    OWNER_PATTERNS[#OWNER_PATTERNS + 1] = ownerPattern(format)
end

local function ownerFromLine(line)
    if not readable(line) or type(line) ~= "string" then return end
    for _, pattern in ipairs(OWNER_PATTERNS) do
        local owner = line:match(pattern)
        if owner then return owner end
    end
end

local scanner
local function tooltipLines(unit)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        for _, line in ipairs(data and data.lines or {}) do lines[#lines + 1] = line.leftText end
        return lines
    end
    scanner = scanner or CreateFrame("GameTooltip", "ForeverDexScanner", nil, "GameTooltipTemplate")
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetUnit(unit)
    for i = 2, math.min(scanner:NumLines(), 5) do
        local region = _G["ForeverDexScannerTextLeft" .. i]
        lines[#lines + 1] = region and region:GetText()
    end
    scanner:Hide()
    return lines
end

-- Full name of the character playing right now (first name and last name).
local function playerName()
    local first, surname = UnitFullName("player")
    if not readable(first) then return end
    return readable(surname) and surname ~= "" and (first .. " " .. surname) or first
end
Collection.PlayerName = playerName

local function readOwner(unit)
    if UnitIsUnit(unit, "pet") then return playerName() end
    for _, line in ipairs(tooltipLines(unit)) do
        local owner = ownerFromLine(line)
        if owner then return owner end
    end
end

-- Reads the target when it is a player's beast: name, family and owner.
function Collection.ReadPet(unit)
    unit = unit or "target"
    local player, controlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
    if not readable(player) or player or not readable(controlled) or not controlled then return end
    local name, family, kind = UnitName(unit), UnitCreatureFamily(unit), UnitCreatureType(unit)
    if not readable(name) or name == "" or name == UNKNOWNOBJECT or not readable(family) or family == "" then return end
    local beast = BEAST[GetLocale()]
    if beast and (not readable(kind) or kind ~= beast) then return end
    local owner = readOwner(unit)
    if not readable(owner) or not owner then return end
    local entry = { name = name, family = family, owner = owner, id = name .. "@" .. owner }
    local level = UnitLevel(unit)
    if readable(level) and level > 0 then entry.level = level end
    return entry
end

-- Slot already holding this pet, then the first free slot.
function Collection.FindPetSlot(entry)
    local available
    for _, slot in ipairs(Catalog.petSlots) do
        local current = ForeverDexDB.cards[slot.key]
        if current and current.id == entry.id then return nil, slot end
        if not current and not available then available = slot end
    end
    return available
end

-- Saved data conversions. migrations[n] moves the data from version n - 1
-- to version n. To change the format: increase DB_VERSION and add a
-- conversion, without ever changing the ones already released.
local DB_VERSION = ns.SavedData.VERSION
local migrations = {
    -- Older versions stored the last name in the realm field.
    [1] = function(db)
        local fallbackRealm = GetNormalizedRealmName()
        for _, entry in pairs(db.cards) do
            if not entry.firstName then
                local surname = entry.realm
                if surname == "" or surname == fallbackRealm then surname = nil end
                setCharacterName(entry, entry.name, surname)
                entry.realm = nil
            end
        end
    end,
    [2] = function(db)
        for key, entry in pairs(db.cards) do
            if entry.guild and not entry.guildID then
                local slot = Catalog.byKey[entry.combination or key]
                local faction = slot and Catalog.RaceFaction(slot.raceID)
                entry.guildID = ns.Guilds.ID(entry.guild, faction)
            end
        end
        -- A guild captured while the target's faction was unreadable was saved as
        -- "Name|": it takes the faction of its member's card, or of the only one the
        -- journal knows for that name, unless that guild is already captured.
        local taken = {}
        for _, guild in ipairs(db.guilds) do taken[guild.id] = true end
        for _, guild in ipairs(db.guilds) do
            if guild.id == ns.Guilds.ID(guild.name) then
                local fromMember, ids, count = nil, {}, 0
                for _, entry in pairs(db.cards) do
                    local id = entry.guild == guild.name and entry.guildID
                    if id and id ~= guild.id then
                        if not ids[id] then ids[id], count = true, count + 1 end
                        if guild.member and entry.name == guild.member then fromMember = id end
                    end
                end
                local id = fromMember or (count == 1 and next(ids)) or nil
                if id and not taken[id] then
                    taken[guild.id], taken[id] = nil, true
                    guild.id, guild.faction = id, id:match("|([^|]+)$")
                end
            end
        end
    end,
}

function Collection.Initialize(onCollectionChanged, onCardCaptured)
    onChanged, onCapture = onCollectionChanged, onCardCaptured
    -- Saved data older than the version number counts as 0. Saved data newer than
    -- the addon is left untouched. The version advances after each successful conversion.
    for version = (ForeverDexDB.version or 0) + 1, DB_VERSION do
        migrations[version](ForeverDexDB)
        ForeverDexDB.version = version
    end
end

-- A replaced standard card goes to the bonus cards, with its date and details.
-- Returns "moved", "kept" (already a bonus card) or "lost" (bonus cards full).
local function bonusFate(old)
    local slot, label = Collection.FindBonusSlot(old)
    if slot then return "moved", slot end
    return label == L.BONUS_DUPLICATE and "kept" or "lost"
end

local function sendReplacedToBonus(old)
    local fate, slot = bonusFate(old)
    if fate == "moved" then
        old.combination = old.key
        old.key = slot.key
        ForeverDexDB.cards[slot.key] = old
        print(L.MOVED_TO_BONUS:format(old.name))
    elseif fate == "lost" then
        print(L.CHAT_PREFIX .. L.REPLACED_LOST:format(old.name))
    end
end

-- The account-wide collection records when, where and by whom something was captured.
function Collection.StampCapture(entry)
    entry.capturedAt = time()
    local zone = GetRealZoneText and GetRealZoneText()
    if readable(zone) and zone ~= "" then entry.zone = zone end
    local capturer = playerName()
    if readable(capturer) and capturer ~= "" and capturer ~= UNKNOWNOBJECT then
        local _, classToken = UnitClass("player")
        entry.capturedBy, entry.capturedByClass = capturer, classToken
    end
end

-- noThrow: the capture does not come from a portrait, so no ball throw.
local function save(entry, noThrow)
    local old = ForeverDexDB.cards[entry.key]
    local isNew = old == nil
    -- Only standard cards are replaced: bonus and pet captures always take a free slot.
    if old and old.id ~= entry.id and Catalog.byKey[entry.key] then sendReplacedToBonus(old) end
    Collection.StampCapture(entry)
    ForeverDexDB.cards[entry.key] = entry
    if onCapture then onCapture(entry, isNew) end
    -- Prepared now, while the player's click is still running: see Share.Capture.
    ns.Share.PrepareCapture(entry, isNew)
    -- A new card is announced on the ball's "click"; a replacement right away.
    if not isNew then Collection.Announce(entry, false) end
    onChanged(entry, isNew, noThrow)
end

-- Pokémon-style capture message, visible only in the player's own chat.
-- The name takes its class color; the sentence is picked at random.
-- The announcement to other players, if any, leaves at the same moment.
local lastLine
function Collection.Announce(entry, isNew)
    ns.Share.RevealCapture(entry)
    if not Settings.Get("chatMessage") then return end
    local lines = isNew and L.CAPTURE_LINES or L.REPLACE_LINES
    local index = math.random(#lines)
    if #lines > 1 and index == lastLine then index = index % #lines + 1 end
    lastLine = index
    local combination = Catalog.byKey[entry.combination or entry.key]
    local color = combination and RAID_CLASS_COLORS and RAID_CLASS_COLORS[combination.token]
    local name = color and ("|c%s%s|r"):format(color.colorStr or "ffffffff", entry.name)
        or ("|cffffd100%s|r"):format(entry.name)
    print(L.CHAT_PREFIX .. lines[index]:format(name))
end

local function confirmReplacement(_, data)
    local current = ForeverDexDB.cards[data.entry.key]
    if current ~= data.current or current.favorite or current.id == data.entry.id then return end
    if bonusFate(current) ~= data.fate then return end
    save(data.entry, data.noThrow)
end

StaticPopupDialogs["FOREVERDEX_REPLACE"] = {
    text = L.REPLACE_PROMPT,
    button1 = L.REPLACE,
    -- Cancel stays button 2: the Escape key triggers this button.
    button2 = CANCEL,
    button3 = L.ADD_BONUS,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- The dialog receives the initial capture, since the target may change in the meantime.
    OnAccept = confirmReplacement,
    OnAlt = function(_, data) Collection.SaveAsBonus(data.entry, data.noThrow) end,
}

-- Same question when the bonus cards are full: the replaced character leaves the collection.
StaticPopupDialogs["FOREVERDEX_REPLACE_FULL"] = {
    text = L.REPLACE_FULL_PROMPT,
    button1 = L.REPLACE,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = confirmReplacement,
}

-- Removes a card from the collection: it goes back to "to discover".
function Collection.Delete(key, expected)
    local entry = ForeverDexDB.cards[key]
    if not entry or (expected and entry ~= expected) then return end
    -- Last guard: a favorite became so while the confirmation was open.
    if entry.favorite then
        print(L.CHAT_PREFIX .. L.DELETE_FAVORITE)
        return
    end
    ForeverDexDB.cards[key] = nil
    print(L.DELETED:format(entry.name))
    onChanged(entry, false)
end

-- Empties the whole collection (settings → Data), after double confirmation.
function Collection.Reset()
    local count = 0
    for _ in pairs(ForeverDexDB.cards) do count = count + 1 end
    ForeverDexDB.cards = {}
    print(L.RESET_DONE:format(count))
    onChanged(nil, false)
end

StaticPopupDialogs["FOREVERDEX_DELETE"] = {
    text = L.DELETE_PROMPT,
    button1 = L.DELETE,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, data) Collection.Delete(data.key, data.entry) end,
}

-- The card is a favorite: it is never replaced. The new character can still go to
-- a bonus slot, when one is free.
StaticPopupDialogs["FOREVERDEX_FAVORITE_HELD"] = {
    text = L.FAVORITE_HELD_PROMPT,
    button1 = L.ADD_BONUS,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, data) Collection.SaveAsBonus(data.entry, data.noThrow) end,
}

local function place(entry, noThrow)
    local current = ForeverDexDB.cards[entry.key]
    if not current then
        save(entry, noThrow)
    elseif current.id ~= entry.id and current.favorite then
        if Collection.FindBonusSlot(entry) then
            ns.Dialog.Show("FOREVERDEX_FAVORITE_HELD", current.name, entry.name, { entry = entry, noThrow = noThrow })
        else
            print(L.CHAT_PREFIX .. L.FAVORITE_HELD:format(current.name))
        end
    elseif current.id ~= entry.id and not Settings.Get("confirmReplace") then
        save(entry, noThrow)
    elseif current.id ~= entry.id then
        local fate = bonusFate(current)
        local which = fate == "lost" and "FOREVERDEX_REPLACE_FULL" or "FOREVERDEX_REPLACE"
        ns.Dialog.Show(which, current.name, entry.name, {
            current = current, entry = entry, noThrow = noThrow, fate = fate,
        })
    end
end

local function capturePet(entry)
    local slot, existing = Collection.FindPetSlot(entry)
    if existing then
        print(L.CHAT_PREFIX .. L.PET_ALREADY:format(entry.name))
    elseif not slot then
        print(L.CHAT_PREFIX .. L.PETS_FULL)
    else
        entry.key = slot.key
        save(entry)
    end
end

-- The target is a player or a hunter pet: the ball, the button and the key binding all come here.
function Collection.Capture()
    local entry = Collection.ReadTarget()
    if entry then return place(entry) end
    local pet = Collection.ReadPet()
    if pet then capturePet(pet) end
end

-- Capture from chat ------------------------------------------------------------

local function chatSenderGUID(context)
    if not context or not context.lineID or not C_ChatInfo or not C_ChatInfo.GetChatLineSenderGUID then return end
    local guid = C_ChatInfo.GetChatLineSenderGUID(context.lineID)
    if not readable(guid) or not guid:find("^Player%-") then return end
    local own = UnitGUID("player")
    if not readable(own) or guid == own then return end
    return guid
end

Collection.ChatSenderGUID = chatSenderGUID

-- Forever stores the last name in the realm field: we only discard an
-- empty value or the actual realm name.
local function cleanSurname(value)
    if not readable(value) or value == "" then return end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and value:gsub("[%s%-]", "") == realm then return end
    return value
end

local function splitName(value)
    if not readable(value) or value == "" then return end
    local first, surname = value:match("^([^%-%s]+)[%-%s]+(.+)$")
    return first or value, cleanSurname(surname)
end

-- The first and last name can come from the GUID or the name shown in chat.
local function readChatName(name, realm, context)
    local first, surname = splitName(name)
    surname = surname or cleanSurname(realm) or cleanSurname(context.server)
    if surname then return first, surname end
    local chatFirst, chatSurname = splitName(context.name)
    if not chatSurname then chatFirst, chatSurname = splitName(context.chatTarget) end
    return first or chatFirst, chatSurname
end

-- The GUID does not give the faction. When the sender is visible (target, nameplate,
-- group…), their unit gives it.
local function unitForGUID(guid)
    if UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(guid)
        if readable(unit) and unit then return unit end
    end
    local units = { "target", "mouseover", "focus" }
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for _, unit in ipairs(units) do
        local other = UnitGUID(unit)
        if readable(other) and other == guid then return unit end
    end
end

-- Only the spoken chats (say, yell, emotes) reach players of the other faction.
local SPOKEN = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true }

-- Faction of the sender, or nil when it cannot be known.
local function chatSenderFaction(guid, context)
    local unit = unitForGUID(guid)
    local faction = unit and UnitFactionGroup(unit)
    if readable(faction) and faction then return faction end
    if context and SPOKEN[context.chatType] then return end
    return UnitFactionGroup("player")
end

Collection.ChatSenderFaction = chatSenderFaction

-- Chat provides neither level nor guild: those fields stay empty on the card.
-- Returns what the card needs, then the faction when it is known.
local function readChatSender(guid, context)
    local _, class, _, race, sex, name, realm = GetPlayerInfoByGUID(guid)
    local slot, ambiguous
    if readable(class) and readable(race) and readable(sex) then
        slot, ambiguous = Catalog.SlotForFiles(race, class, sex)
    end
    local first, surname = readChatName(name, realm, context)
    if not slot or not first or not surname then
        local function shown(value) return readable(value) and tostring(value) or "?" end
        print(L.CHAT_CAPTURE_FAILED)
        print(("   %s - %s - %s - %s - %s - %s - %s"):format(shown(race), shown(class), shown(sex),
            shown(name), shown(realm), shown(context.name), shown(context.server)))
        return
    end
    local sender = { race = race, class = class, sex = sex, first = first, surname = surname }
    return sender, chatSenderFaction(guid, context), ambiguous
end

local function storeFromChat(sender, faction)
    local slot = Catalog.SlotForFiles(sender.race, sender.class, sender.sex, faction)
    local entry = { key = slot.key }
    setCharacterName(entry, sender.first, sender.surname)
    local current = ForeverDexDB.cards[entry.key]
    if current and current.id == entry.id then
        print(L.CHAT_ALREADY:format(entry.name))
    else
        place(entry, true)
    end
end

-- The race exists in both factions and nothing tells which one: the player chooses.
StaticPopupDialogs["FOREVERDEX_FACTION"] = {
    text = L.CHAT_FACTION_PROMPT,
    button1 = FACTION_ALLIANCE,
    -- Cancel stays button 2: the Escape key triggers this button.
    button2 = CANCEL,
    button3 = FACTION_HORDE,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, sender) storeFromChat(sender, "Alliance") end,
    OnAlt = function(_, sender) storeFromChat(sender, "Horde") end,
}

local function captureFromChat(context)
    local guid = chatSenderGUID(context)
    if not guid then return end
    local sender, faction, ambiguous = readChatSender(guid, context)
    if not sender then return end
    if ambiguous and not faction then
        ns.Dialog.Show("FOREVERDEX_FACTION", sender.first .. " " .. sender.surname, nil, sender)
    else
        storeFromChat(sender, faction)
    end
end

Collection.CaptureFromChat = captureFromChat

if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
        -- With the controller, an addon entry blocks the menu's protected actions (Duel.lua).
        if ns.PopupMenu.GamepadActive() or not chatSenderGUID(context) then return end
        root:CreateDivider()
        root:CreateButton(L.CHAT_CAPTURE, function() captureFromChat(context) end)
    end)
end

function Collection.FindBonusSlot(entry)
    local available
    -- We keep going after the first free slot to detect a duplicate further on.
    for _, slot in ipairs(Catalog.bonusSlots) do
        local current = ForeverDexDB.cards[slot.key]
        if current and current.id == entry.id then return nil, L.BONUS_DUPLICATE end
        if not current and not available then available = slot end
    end
    return available, available and L.ADD_BONUS or L.BONUS_FULL
end

function Collection.SaveAsBonus(entry, noThrow)
    local slot, label = Collection.FindBonusSlot(entry)
    if not slot then
        print(L.CHAT_PREFIX .. label)
        return
    end
    -- The bonus has its own key, but keeps the combination for the backdrop and portrait.
    entry.combination = entry.key
    entry.key = slot.key
    save(entry, noThrow)
end

function Collection.CaptureBonus()
    local entry = Collection.ReadTarget()
    if entry then Collection.SaveAsBonus(entry) end
end

-- Moves a standard card to a free bonus slot, with its date and details.
function Collection.MoveToBonus(key)
    local entry = ForeverDexDB.cards[key]
    if not entry or entry.combination then return end
    local slot, label = Collection.FindBonusSlot(entry)
    if not slot then
        print(L.CHAT_PREFIX .. label)
        return
    end
    ForeverDexDB.cards[key] = nil
    entry.combination = key
    entry.key = slot.key
    ForeverDexDB.cards[slot.key] = entry
    print(L.MOVED_TO_BONUS:format(entry.name))
    onChanged(entry, false)
end

function Collection.StandardCardFree(entry)
    local key = entry.combination
    return key ~= nil and Catalog.byKey[key] ~= nil and ForeverDexDB.cards[key] == nil
end

-- Moves a bonus card back to its standard card, with its date and details.
function Collection.MoveToStandard(key)
    local entry = ForeverDexDB.cards[key]
    if not entry or not Collection.StandardCardFree(entry) then return end
    ForeverDexDB.cards[key] = nil
    entry.key = entry.combination
    entry.combination = nil
    ForeverDexDB.cards[entry.key] = entry
    print(L.MOVED_TO_STANDARD:format(entry.name))
    onChanged(entry, false)
end

function Collection.ToggleFavorite(entry)
    entry.favorite = not entry.favorite or nil
    onChanged(entry, false)
end
end)
