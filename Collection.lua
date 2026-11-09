local _, ns = ...
local L, Catalog = ns.L, ns.Catalog
local Collection = {}
ns.Collection = Collection
local onChanged

local function readable(value)
    -- Le client peut marquer une valeur comme secrète, notamment en combat.
    -- Il faut le vérifier avant toute comparaison ou concaténation.
    return (not issecretvalue or not issecretvalue(value)) and value ~= nil
end

local function setCharacterName(entry, firstName, surname)
    entry.firstName = firstName
    entry.surname = surname
    entry.name = surname and (firstName .. " " .. surname) or firstName
    entry.id = entry.name
end

-- Lit la cible, ou l’unité indiquée (membre du groupe, portrait cliqué…).
function Collection.ReadTarget(unit)
    unit = unit or "target"
    local player = UnitIsPlayer(unit)
    if not readable(player) or not player then return end
    local selfTarget = UnitIsUnit(unit, "player")
    if not readable(selfTarget) or selfTarget then return end
    -- Dans Forever, UnitFullName renvoie séparément le prénom et le nom de famille.
    local firstName, surname = UnitFullName(unit)
    local _, _, race = UnitRace(unit)
    local _, _, class = UnitClass(unit)
    local sex = UnitSex(unit)
    if not readable(firstName) or firstName == "" or not readable(surname) or surname == ""
        or not readable(race) or not readable(class) or not readable(sex) then
        return
    end
    local slot = Catalog.byKey[Catalog.SlotKey(race, class, sex)]
    if not slot then return end
    local entry = { key = slot.key }
    setCharacterName(entry, firstName, surname)
    -- Détails facultatifs pour la fiche : ils ne servent jamais à identifier le personnage.
    local level = UnitLevel(unit)
    if readable(level) and level > 0 then entry.level = level end
    local guild = GetGuildInfo(unit)
    if readable(guild) and guild ~= "" then entry.guild = guild end
    return entry
end

-- Conversions de la sauvegarde. migrations[n] fait passer les données de la version
-- n - 1 à la version n. Pour changer le format : augmenter DB_VERSION et ajouter
-- une conversion, sans jamais modifier celles qui sont déjà publiées.
local DB_VERSION = 1
local migrations = {
    -- Les anciennes versions stockaient le nom de famille dans le champ realm.
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
}

function Collection.Initialize(onCollectionChanged)
    ForeverDexDB = ForeverDexDB or { cards = {} }
    onChanged = onCollectionChanged
    -- Les sauvegardes antérieures au numéro de version valent 0. Une sauvegarde plus
    -- récente que l’addon reste intacte. La version avance après chaque conversion réussie.
    for version = (ForeverDexDB.version or 0) + 1, DB_VERSION do
        migrations[version](ForeverDexDB)
        ForeverDexDB.version = version
    end
end

-- noThrow : la capture ne vient d’aucun portrait, donc pas de lancer de balle.
local function save(entry, noThrow)
    local isNew = ForeverDexDB.cards[entry.key] == nil
    entry.capturedAt = time()
    local zone = GetRealZoneText and GetRealZoneText()
    if readable(zone) and zone ~= "" then entry.zone = zone end
    ForeverDexDB.cards[entry.key] = entry
    -- Une nouvelle carte s'annonce au « clic » de la balle ; un remplacement tout de suite.
    if not isNew then Collection.Announce(entry, false) end
    onChanged(entry, isNew, noThrow)
end

-- Message de capture façon Pokémon, visible seulement dans le chat du joueur.
-- Le pseudo prend la couleur de sa classe ; la phrase est tirée au hasard.
local lastLine
function Collection.Announce(entry, isNew)
    if not ns.Settings.Get("chatMessage") then return end
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

StaticPopupDialogs["FOREVERDEX_REPLACE"] = {
    text = L.REPLACE_PROMPT,
    button1 = L.REPLACE,
    -- Annuler reste le bouton 2 : la touche Échap déclenche ce bouton.
    button2 = CANCEL,
    button3 = L.ADD_BONUS,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- La boîte reçoit la capture initiale, car la cible peut changer entre-temps.
    OnAccept = function(_, data) save(data.entry, data.noThrow) end,
    OnAlt = function(_, data) Collection.SaveAsBonus(data.entry, data.noThrow) end,
}

-- Retire une carte de la collection : elle redevient « à découvrir ».
function Collection.Delete(key)
    local entry = ForeverDexDB.cards[key]
    if not entry then return end
    ForeverDexDB.cards[key] = nil
    print(L.DELETED:format(entry.name))
    onChanged(entry, false)
end

-- Vide toute la collection (paramètres → Données), après double confirmation.
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
    OnAccept = function(_, key) Collection.Delete(key) end,
}

local function place(entry, noThrow)
    local current = ForeverDexDB.cards[entry.key]
    if not current then
        save(entry, noThrow)
    elseif current.id ~= entry.id and not ns.Settings.Get("confirmReplace") then
        save(entry, noThrow)
    elseif current.id ~= entry.id then
        StaticPopup_Show("FOREVERDEX_REPLACE", current.name, entry.name, { entry = entry, noThrow = noThrow })
    end
end

function Collection.Capture()
    local entry = Collection.ReadTarget()
    if entry then place(entry) end
end

-- Capture depuis le chat ------------------------------------------------------------

local function chatSenderGUID(context)
    if not context or not context.lineID or not C_ChatInfo or not C_ChatInfo.GetChatLineSenderGUID then return end
    local guid = C_ChatInfo.GetChatLineSenderGUID(context.lineID)
    if not readable(guid) or not guid:find("^Player%-") then return end
    local own = UnitGUID("player")
    if not readable(own) or guid == own then return end
    return guid
end

Collection.ChatSenderGUID = chatSenderGUID

-- Forever range le nom de famille dans le champ du royaume : on écarte seulement
-- une valeur vide ou le vrai nom du royaume.
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

-- Le prénom et le nom peuvent venir du GUID ou du pseudo affiché dans le chat.
local function readChatName(name, realm, context)
    local first, surname = splitName(name)
    surname = surname or cleanSurname(realm) or cleanSurname(context.server)
    if surname then return first, surname end
    local chatFirst, chatSurname = splitName(context.name)
    if not chatSurname then chatFirst, chatSurname = splitName(context.chatTarget) end
    return first or chatFirst, chatSurname
end

-- Le chat ne fournit ni le niveau ni la guilde : ces champs restent vides sur la carte.
local function readChatSender(guid, context)
    local _, class, _, race, sex, name, realm = GetPlayerInfoByGUID(guid)
    local slot
    if readable(class) and readable(race) and readable(sex) then
        slot = Catalog.SlotForFiles(race, class, sex)
    end
    local first, surname = readChatName(name, realm, context)
    if not slot or not first or not surname then
        local function shown(value) return readable(value) and tostring(value) or "?" end
        print(L.CHAT_CAPTURE_FAILED)
        print(("   %s · %s · %s · %s · %s · %s · %s"):format(shown(race), shown(class), shown(sex),
            shown(name), shown(realm), shown(context.name), shown(context.server)))
        return
    end
    local entry = { key = slot.key }
    setCharacterName(entry, first, surname)
    return entry
end

local function captureFromChat(context)
    local guid = chatSenderGUID(context)
    local entry = guid and readChatSender(guid, context)
    if not entry then return end
    local current = ForeverDexDB.cards[entry.key]
    if current and current.id == entry.id then
        print(L.CHAT_ALREADY:format(entry.name))
    else
        place(entry, true)
    end
end

if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
        if not chatSenderGUID(context) then return end
        root:CreateDivider()
        root:CreateButton(L.CHAT_CAPTURE, function() captureFromChat(context) end)
    end)
end

function Collection.FindBonusSlot(entry)
    local available
    -- On poursuit après le premier emplacement libre pour détecter un doublon plus loin.
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
    -- Le bonus a sa propre clé, mais garde la combinaison pour le décor et le portrait.
    entry.combination = entry.key
    entry.key = slot.key
    save(entry, noThrow)
end

function Collection.CaptureBonus()
    local entry = Collection.ReadTarget()
    if entry then Collection.SaveAsBonus(entry) end
end

-- Déplace une carte classique vers un bonus libre, avec sa date et ses détails.
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

function Collection.ToggleFavorite(entry)
    entry.favorite = not entry.favorite or nil
    onChanged(entry, false)
end
