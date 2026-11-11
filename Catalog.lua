local _, ns = ...
ns.Module(function()
local L = ns.L
local Catalog = {}
ns.Catalog = Catalog

-- The order of combinations sets the displayed numbers. Saved keys use the game IDs.
local races = {
    { 1, 1, 2, 3, 4, 5, 8, 9 },
    { 3, 1, 2, 3, 4, 5, 7 },
    { 4, 1, 3, 4, 5, 11 },
    { 7, 1, 4, 5, 8, 9 },
    { 2, 1, 3, 4, 7, 8, 9 },
    { 5, 1, 2, 4, 5, 8, 9 },
    { 6, 1, 3, 7, 11 },
    { 8, 1, 3, 4, 5, 7, 8, 9 },
    { 95, 1, 3, 4, 8, 11 },
    { 96, 1, 3, 4, 7, 11 },
}

-- 1 race icon, 2 Adventure Guide map, 3-5 background color,
-- 6 dressing room backdrop, 7 fallback icon,
-- 8 loading screen for the cards and detail page, picked in game for the mood of
-- each race. Without a suitable screen, the dressing room backdrop replaces it.
local raceThemes = {
    [1] = { "human", 291, 0.32, 0.24, 0.15, "Human", nil, "LoadScreenScarletMonastery2" },
    [2] = { "orc", 213, 0.34, 0.16, 0.09, "Orc", nil, "LoadScreenRagefireChasm" },
    [3] = { "dwarf", 230, 0.34, 0.25, 0.15, "Dwarf", nil, "LoadScreenBlackrockDepths" },
    [4] = { "nightelf", 221, 0.13, 0.25, 0.22, "NightElf", nil, 7963776 },
    [5] = { "undead", 310, 0.20, 0.24, 0.23, "Scourge", nil, "LoadScreenShadowFangKeep" },
    [6] = { "tauren", 279, 0.25, 0.27, 0.14, "Tauren", nil, 7963784 },
    [7] = { "gnome", 226, 0.22, 0.27, 0.29, "Gnome", nil, "LoadScreenGnomeregan" },
    [8] = { "troll", 219, 0.25, 0.28, 0.16, "Troll", nil, "LoadScreenZulGurub" },
    [95] = { "elf", 221, 0.17, 0.25, 0.32, "NightElf", "Interface\\Icons\\INV_BannerPVP_02", 7963777 },
    [96] = { "elf", 221, 0.23, 0.18, 0.31, "BloodElf", "Interface\\Icons\\INV_BannerPVP_01", 7963777 },
}

-- Skyborne do not always have their own icon: we try the one of the elf
-- whose backdrop they borrow.
local function raceIcon(theme, sex)
    local suffix = sex == 3 and "female" or "male"
    local own = ("raceicon-%s-%s"):format(theme[1], suffix)
    local borrowed = ("raceicon-%s-%s"):format(theme[6]:lower(), suffix)
    if ns.Art.HasAtlas(own) or not ns.Art.HasAtlas(borrowed) then return own end
    return borrowed
end

local slots, byKey, slotByKey, raceList, classList, seenClass = {}, {}, {}, {}, {}, {}
function Catalog.SlotKey(race, class, sex)
    return race .. ":" .. class .. ":" .. sex
end

for _, race in ipairs(races) do
    local raceID, theme = race[1], raceThemes[race[1]]
    local info = {
        id = raceID, name = L.RACES[raceID], theme = theme, total = 0,
        icon = raceIcon(theme, 2), fallbackIcon = theme[7],
    }
    raceList[#raceList + 1] = info
    for i = 2, #race do
        local class = C_CreatureInfo.GetClassInfo(race[i])
        local className = L.CLASSES[class.classFile] or class.className
        if not seenClass[class.classFile] then
            seenClass[class.classFile] = true
            classList[#classList + 1] = { token = class.classFile, name = className }
        end
        for sex = 2, 3 do
            local slot = {
                index = #slots + 1,
                key = Catalog.SlotKey(raceID, race[i], sex),
                raceID = raceID,
                race = L.RACES[raceID],
                class = className,
                token = class.classFile,
                sex = sex == 2 and L.MALE or L.FEMALE,
                sexID = sex,
                fallbackIcon = theme[7],
                theme = theme,
                portraitAtlas = raceIcon(theme, sex),
            }
            slots[slot.index], byKey[slot.key], slotByKey[slot.key] = slot, slot, slot
            info.total = info.total + 1
        end
    end
end

local bonusSlots = {}
for i = 1, 39 do
    local slot = { index = #slots + 1, key = "bonus:" .. i, race = L.BONUS, class = "" }
    slots[slot.index], slotByKey[slot.key] = slot, slot
    bonusSlots[i] = slot
end

-- Hunter pets: free slots in their own section, outside the player collection
-- and its progress. Every pet card shares the hunter look, over a forest backdrop.
local PET_DETAILS = {
    race = L.PETS, class = "", token = "HUNTER",
    theme = { nil, nil, 0.16, 0.22, 0.11, "NightElf" },
    fallbackIcon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
}
local petSlots = {}
for i = 1, 60 do
    local slot = { index = i, key = "pet:" .. i, race = L.PETS, class = "", pet = true }
    slotByKey[slot.key] = slot
    petSlots[i] = slot
end

Catalog.slots = slots
Catalog.byKey = byKey
Catalog.bonusSlots = bonusSlots
Catalog.petSlots = petSlots
Catalog.slotByKey = slotByKey
Catalog.races = raceList
table.sort(classList, function(a, b) return a.name < b.name end)
Catalog.classes = classList

-- A filled bonus borrows the combination of the captured character.
-- A pet is described by its family (Raptor, Boar…).
function Catalog.Describe(slot, entry)
    if slot.pet then return PET_DETAILS, entry and entry.family or L.PET_DESCRIPTION end
    local details = slot.sex and slot or (entry and byKey[entry.combination])
    local description = details and (details.race .. L.SEPARATOR .. details.class .. L.SEPARATOR .. details.sex)
        or L.BONUS_DESCRIPTION
    return details, description
end

-- Filled slots of a list (Catalog.slots or Catalog.petSlots).
function Catalog.Filled(entries, list)
    local count = 0
    for _, slot in ipairs(list) do
        if entries[slot.key] then count = count + 1 end
    end
    return count
end

-- Standard cards filled for each race (bonuses do not count).
function Catalog.RaceProgress(entries)
    local counts = {}
    for _, slot in ipairs(slots) do
        if slot.raceID and entries[slot.key] then
            counts[slot.raceID] = (counts[slot.raceID] or 0) + 1
        end
    end
    return counts
end

-- Card matching the file names returned by GetPlayerInfoByGUID.
-- Several races can share a file name (Skyborne Alliance and Horde): the GUID
-- does not give the faction. faction (optional) picks among them; otherwise the
-- player's faction. The second value tells whether several cards were possible.
local raceIDsByFile
-- Server races unknown to the client API: their faction is written by hand.
local KNOWN_FACTIONS = { [95] = "Alliance", [96] = "Horde" }
local function raceFaction(raceID)
    local info = C_CreatureInfo.GetFactionInfo and C_CreatureInfo.GetFactionInfo(raceID)
    return info and info.groupTag or KNOWN_FACTIONS[raceID]
end

function Catalog.SlotForFiles(raceFile, classToken, sex, faction)
    if not raceIDsByFile then
        raceIDsByFile = {}
        for _, info in ipairs(raceList) do
            local race = C_CreatureInfo.GetRaceInfo(info.id)
            local file = race and race.clientFileString
            if file then
                raceIDsByFile[file] = raceIDsByFile[file] or {}
                table.insert(raceIDsByFile[file], info.id)
            end
        end
    end
    local candidates = {}
    for _, raceID in ipairs(raceIDsByFile[raceFile] or {}) do
        for _, slot in ipairs(slots) do
            if slot.raceID == raceID and slot.token == classToken and slot.sexID == sex then
                candidates[#candidates + 1] = slot
            end
        end
    end
    if #candidates > 1 then
        faction = faction or UnitFactionGroup("player")
        for _, slot in ipairs(candidates) do
            if raceFaction(slot.raceID) == faction then return slot, true end
        end
    end
    return candidates[1], #candidates > 1
end

-- Standard cards filled and available for a class.
function Catalog.ClassProgress(entries, token)
    local have, total = 0, 0
    for _, slot in ipairs(slots) do
        if slot.token == token then
            total = total + 1
            if entries[slot.key] then have = have + 1 end
        end
    end
    return have, total
end

local accents = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e",
    ["ê"] = "e", ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ÿ"] = "y", ["œ"] = "oe",
    ["À"] = "a", ["Â"] = "a", ["Ç"] = "c", ["É"] = "e", ["È"] = "e", ["Ê"] = "e",
    ["Ë"] = "e", ["Î"] = "i", ["Ï"] = "i", ["Ô"] = "o", ["Ù"] = "u", ["Û"] = "u",
    ["á"] = "a", ["ã"] = "a", ["í"] = "i", ["ì"] = "i", ["ñ"] = "n", ["ó"] = "o", ["ò"] = "o",
    ["õ"] = "o", ["ú"] = "u", ["ß"] = "ss", ["Á"] = "a", ["Ã"] = "a", ["Ä"] = "a", ["Í"] = "i",
    ["Ñ"] = "n", ["Ó"] = "o", ["Õ"] = "o", ["Ö"] = "o", ["Ú"] = "u", ["Ü"] = "u",
}
-- string.lower only knows ASCII: Cyrillic capitals are mapped by hand.
for offset = 0, 15 do accents[string.char(0xD0, 0x90 + offset)] = string.char(0xD0, 0xB0 + offset) end
for offset = 0, 15 do accents[string.char(0xD0, 0xA0 + offset)] = string.char(0xD1, 0x80 + offset) end
accents["Ё"] = "е"
accents["ё"] = "е"
local function normalize(value)
    -- Literal search, insensitive to case and common accents.
    return value:lower():gsub("[\194-\244][\128-\191]+", accents)
end
-- Produces the filtered view without changing the collection.
-- filters holds three checked sets: races, classes and sexes. Within a category,
-- one box is enough; across categories, all must match (Orc AND Shaman).
-- Empty bonuses have no combination: when filtering, they only remain in the Bonus tab.
local function allowed(set, value)
    return next(set) == nil or set[value]
end

function Catalog.Query(entries, searchText, viewMode, sortMode, filters)
    local query = normalize(searchText):match("^%s*(.-)%s*$")
    local rows, filled = {}, 0
    local function add(slot, entry)
        local details, description = Catalog.Describe(slot, entry)
        if slot.pet then
            -- The race, class and sex filters do not apply to pets.
        elseif details then
            if not (allowed(filters.races, details.raceID) and allowed(filters.classes, details.token)
                and allowed(filters.sexes, details.sexID)) then
                return
            end
        elseif viewMode ~= 4 and (next(filters.races) or next(filters.classes) or next(filters.sexes)) then
            return
        end
        local name = entry and entry.name or ""
        local guild, zone = entry and entry.guild or "", entry and entry.zone or ""
        local owner = entry and entry.owner or ""
        local haystack = normalize(slot.race .. " " .. description .. " " .. name .. " " .. guild .. " " .. zone
            .. " " .. owner)
        if haystack:find(query, 1, true) then
            rows[#rows + 1] = {
                slot = slot, entry = entry, details = details, description = description, name = normalize(name),
                race = normalize((details or slot).race), class = normalize((details or slot).class),
            }
        end
    end
    for _, slot in ipairs(slots) do
        local entry = entries[slot.key]
        if entry then filled = filled + 1 end
        if viewMode == 1 or (viewMode == 2 and entry) or (viewMode == 3 and not entry)
            or (viewMode == 4 and not slot.sex) or (viewMode == 5 and entry and entry.favorite) then
            add(slot, entry)
        end
    end
    -- Pets have their own tab, and also show among the favorites.
    for _, slot in ipairs(petSlots) do
        local entry = entries[slot.key]
        if viewMode == 6 or (viewMode == 5 and entry and entry.favorite) then add(slot, entry) end
    end
    table.sort(rows, function(a, b)
        if sortMode == 1 then
            -- Bonuses stay at the end of the catalog. For the same class, the index
            -- keeps the male then female order set at creation.
            local aBonus, bBonus = not a.slot.sex, not b.slot.sex
            if aBonus ~= bBonus then return not aBonus end
            if not aBonus then
                if a.race ~= b.race then return a.race < b.race end
                if a.class ~= b.class then return a.class < b.class end
            end
        end
        if sortMode == 3 and a.name ~= b.name then
            if a.name == "" then return false end
            if b.name == "" then return true end
            return a.name < b.name
        end
        if sortMode == 4 and a.race ~= b.race then return a.race < b.race end
        if sortMode == 5 and a.class ~= b.class then return a.class < b.class end
        -- Cards without a date or level come after the others.
        if sortMode == 6 then
            local first, second = a.entry and a.entry.capturedAt or 0, b.entry and b.entry.capturedAt or 0
            if first ~= second then return first > second end
        end
        if sortMode == 7 then
            local first, second = a.entry and a.entry.level or 0, b.entry and b.entry.level or 0
            if first ~= second then return first > second end
        end
        return a.slot.index < b.slot.index
    end)
    return rows, filled
end
end)
