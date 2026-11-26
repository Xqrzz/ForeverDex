local _, ns = ...
local SavedData = {}
ns.SavedData = SavedData

SavedData.VERSION = 2

local TABLE_FIELDS = { "cards", "settings", "view", "guilds", "achievements", "challengeLog" }
local FILTER_FIELDS = { "races", "classes", "sexes", "capturers" }
local CARD_TEXT_FIELDS = { "firstName", "surname", "realm", "combination", "guild", "guildID", "zone",
    "owner", "family", "capturedBy", "capturedByClass", "id" }

-- Prepare the shared tables before modules read settings or register their UI.
function SavedData.Prepare(db)
    if type(db) ~= "table" then db = {} end
    local version = db.version
    if type(version) == "number" and version > SavedData.VERSION then return db, false end
    if type(version) ~= "number" or version < 0 or version ~= math.floor(version) then db.version = 0 end
    for _, field in ipairs(TABLE_FIELDS) do
        if type(db[field]) ~= "table" then db[field] = {} end
    end
    for _, field in ipairs(FILTER_FIELDS) do
        if type(db.view[field]) ~= "table" then db.view[field] = nil end
    end
    if type(db.settings.language) ~= "string" then db.settings.language = nil end
    for key, entry in pairs(db.cards) do
        if type(key) ~= "string" or type(entry) ~= "table" or type(entry.name) ~= "string" then
            db.cards[key] = nil
        else
            entry.key = key
            for _, field in ipairs(CARD_TEXT_FIELDS) do
                if type(entry[field]) ~= "string" then entry[field] = nil end
            end
            entry.id = entry.id or entry.name
            if type(entry.capturedAt) ~= "number" then entry.capturedAt = nil end
            if type(entry.level) ~= "number" then entry.level = nil end
        end
    end
    local order, guilds = {}, {}
    for index, guild in pairs(db.guilds) do
        if type(index) == "number" and type(guild) == "table"
            and type(guild.id) == "string" and type(guild.name) == "string" then
            order[#order + 1] = index
        end
    end
    table.sort(order)
    for _, index in ipairs(order) do guilds[#guilds + 1] = db.guilds[index] end
    db.guilds = guilds
    for _, field in ipairs({ "count", "streak", "best" }) do
        if type(db.challengeLog[field]) ~= "number" then db.challengeLog[field] = nil end
    end
    return db
end
