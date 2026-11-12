local _, ns = ...
ns.Module(function()
local L, Catalog = ns.L, ns.Catalog
local Home = {}
ns.Home = Home

-- Data of the home page (HomeUI.lua draws it): the daily challenge, the short
-- statistics and the version whose news it summarizes. Nothing here touches a frame.

-- Release summarized by the "What's new" box. Its lines are translated in each
-- locale (HOME_NEWS_LINES): update both before a release.
Home.NEWS_VERSION = "1.8.0"

local DAY = 86400
local RECENT = 7 * DAY

-- Daily challenge ------------------------------------------------------------------

-- Midnight of the local day containing the given time.
local function startOfDay(now)
    local parts = date("*t", now)
    parts.hour, parts.min, parts.sec = 0, 0, 0
    return time(parts)
end

-- The next midnight. Going two hours past the day's length keeps it right on the
-- days that last 23 or 25 hours when the clocks change.
local function nextDay(dayStart)
    return startOfDay(dayStart + DAY + 2 * 3600)
end

-- Number drawn from the date (Park–Miller generator): the same all day long, a
-- different one the next day. Products stay below 2^53, where Lua numbers are exact.
local function seed(day)
    local value = tonumber((day:gsub("%D", ""))) % 2147483647
    for _ = 1, 3 do value = (value * 48271) % 2147483647 end
    return value
end

-- A combination still to discover. Once the journal is complete, any combination:
-- the challenge then becomes finding a funnier name than the one already there.
local function pick(day)
    local entries, pool = ForeverDexDB.cards, {}
    for _, slot in ipairs(Catalog.slots) do
        if slot.sex and not entries[slot.key] then pool[#pool + 1] = slot end
    end
    if #pool == 0 then
        for _, slot in ipairs(Catalog.slots) do
            if slot.sex then pool[#pool + 1] = slot end
        end
    end
    return pool[seed(day) % #pool + 1].key
end

-- The challenge of the day, drawn on the first look and kept until midnight in
-- ForeverDexDB.challenge, so that capturing the card does not draw another one.
-- Nothing is won: it only suggests what to look for.
--   slot      the standard card to fill
--   entry     the card's current capture, if any
--   done      a capture of today fills it: the challenge is met
--   improve   the card was already filled before today (complete journal)
--   line      number picking the flavour line of the day
--   resetsIn  seconds until the next challenge
function Home.Challenge(now)
    now = now or time()
    local day = date("%Y-%m-%d", now)
    local saved = ForeverDexDB.challenge
    if type(saved) ~= "table" or saved.day ~= day or not Catalog.byKey[saved.key] then
        saved = { day = day, key = pick(day) }
        ForeverDexDB.challenge = saved
    end
    local slot = Catalog.byKey[saved.key]
    local entry = ForeverDexDB.cards[slot.key]
    local dayStart = startOfDay(now)
    local done = entry ~= nil and (entry.capturedAt or 0) >= dayStart
    return {
        slot = slot,
        entry = entry,
        done = done,
        improve = entry ~= nil and not done,
        line = seed(day),
        resetsIn = math.max(0, nextDay(dayStart) - now),
    }
end

-- Statistics -------------------------------------------------------------------------

-- Most frequent value of a tally; ties go to the first name in alphabetical order,
-- so the result does not depend on the order of the saved table.
local function top(tally)
    local best, bestCount
    for value, count in pairs(tally) do
        if not bestCount or count > bestCount or (count == bestCount and value < best) then
            best, bestCount = value, count
        end
    end
    return best, bestCount
end

-- Short figures for the home page. Pets count as captures, but have no class.
--   standard, total  standard cards filled, out of all combinations
--   recent           captures of the last seven days
--   last             most recent capture (entry), or nil
--   class            token of the most captured class, and classCount
--   zone             zone with the most captures, and zoneCount
--   achievements     done, total and points of the achievements, when available
function Home.Stats(now)
    now = now or time()
    local entries = ForeverDexDB.cards
    local stats = { standard = 0, total = 0, recent = 0 }
    for _, slot in ipairs(Catalog.slots) do
        if slot.sex then
            stats.total = stats.total + 1
            if entries[slot.key] then stats.standard = stats.standard + 1 end
        end
    end

    local classes, zones = {}, {}
    for key, entry in pairs(entries) do
        local capturedAt = entry.capturedAt
        if capturedAt then
            if now - capturedAt < RECENT then stats.recent = stats.recent + 1 end
            if not stats.last or capturedAt > stats.last.capturedAt then stats.last = entry end
        end
        if entry.zone then zones[entry.zone] = (zones[entry.zone] or 0) + 1 end
        local slot = Catalog.slotByKey[key]
        if slot and not slot.pet then
            local details = Catalog.Describe(slot, entry)
            if details and details.token then classes[details.token] = (classes[details.token] or 0) + 1 end
        end
    end
    stats.class, stats.classCount = top(classes)
    stats.zone, stats.zoneCount = top(zones)

    if ns.Achievements and ns.Achievements.State then
        local state = ns.Achievements.State()
        stats.achievements = { done = state.done, total = #state.rows, points = state.points }
    end
    return stats
end

-- Name of a class token in the addon language.
function Home.ClassName(token)
    for _, class in ipairs(Catalog.classes) do
        if class.token == token then return class.name end
    end
    return L.CLASSES[token] or token
end
end)
