local _, ns = ...
ns.Module(function()
local L, Catalog, Art = ns.L, ns.Catalog, ns.Art
local Achievements = {}
ns.Achievements = Achievements

-- Forever has no achievements of its own: ForeverDex keeps its own list, earned
-- for good (deleting a card takes nothing back), and announces them with the
-- game's achievement alert.

local ORB = "Interface\\AddOns\\ForeverDex\\Media\\Icon"
local PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local ACHIEVEMENT = "Interface\\AchievementFrame\\"

-- Progress of the collection ------------------------------------------------------

local function tally(set, key, filled)
    local row = set[key] or { have = 0, total = 0 }
    set[key] = row
    row.total = row.total + 1
    if filled then row.have = row.have + 1 end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

-- Every figure the achievements need, measured once per check.
-- Bonuses count as captures and show a race and class, but never fill a standard card.
local function measure(cards)
    local stats = {
        captures = 0, standard = 0, bonus = 0, standardTotal = 0,
        races = {}, classes = {}, sexes = {}, seenRaces = {}, seenClasses = {},
    }
    for _, slot in ipairs(Catalog.slots) do
        local entry = cards[slot.key]
        if entry then stats.captures = stats.captures + 1 end
        if slot.sex then
            stats.standardTotal = stats.standardTotal + 1
            if entry then stats.standard = stats.standard + 1 end
            tally(stats.races, slot.raceID, entry)
            tally(stats.classes, slot.token, entry)
            tally(stats.sexes, slot.sexID, entry)
        elseif entry then
            stats.bonus = stats.bonus + 1
        end
        local combination = slot.sex and slot or (entry and Catalog.byKey[entry.combination])
        if entry and combination then
            stats.seenRaces[combination.raceID] = true
            stats.seenClasses[combination.token] = true
        end
    end
    stats.pets = Catalog.Filled(cards, Catalog.petSlots)
    return stats
end

-- The list ---------------------------------------------------------------------------
-- Each achievement: id (saved, never renamed), name, description, icon, points,
-- and progress(stats) → have, need. It is earned once have reaches need.

-- Categories, in the order of the achievements page; each achievement belongs to the
-- category opened last by category().
local list, categories, current = {}, {}, nil
local function category(id, name, icon)
    current = { id = id, name = name, icon = icon }
    categories[#categories + 1] = current
end
local function add(achievement)
    achievement.category = current.id
    list[#list + 1] = achievement
end
category("captures", L.ACH_CAT_CAPTURES, { texture = ORB })

local function full(set, key)
    return function(stats)
        local row = stats[set][key]
        return row and row.have or 0, row and row.total or 0
    end
end

local CAPTURE_POINTS = { [1] = 5, [10] = 10, [25] = 10, [50] = 25, [100] = 50 }
for _, need in ipairs({ 1, 10, 25, 50, 100 }) do
    add({
        id = "captures" .. need, name = L.ACH_CAPTURES[need], points = CAPTURE_POINTS[need],
        description = need == 1 and L.ACH_CAPTURES_FIRST or L.ACH_CAPTURES_DESC:format(need),
        icon = { texture = ORB },
        progress = function(stats) return stats.captures, need end,
    })
end

category("collection", L.ACH_CAT_COLLECTION, { texture = "Interface\\Icons\\INV_Misc_Book_09" })
add({
    id = "everyRace", name = L.ACH_EVERY_RACE, description = L.ACH_EVERY_RACE_DESC, points = 10,
    icon = { texture = "Interface\\Icons\\INV_Misc_Map_01" },
    progress = function(stats) return count(stats.seenRaces), #Catalog.races end,
})
add({
    id = "everyClass", name = L.ACH_EVERY_CLASS, description = L.ACH_EVERY_CLASS_DESC, points = 10,
    icon = { texture = "Interface\\Icons\\INV_Misc_Book_09" },
    progress = function(stats) return count(stats.seenClasses), #Catalog.classes end,
})

category("races", L.ACH_CAT_RACES, { atlas = Catalog.races[1].icon, texture = "Interface\\Icons\\INV_Misc_Map_01" })
for _, race in ipairs(Catalog.races) do
    add({
        id = "race" .. race.id, name = L.ACH_RACE:format(race.name), points = 10,
        description = L.ACH_RACE_DESC:format(race.total, race.name),
        icon = { atlas = race.icon, texture = race.fallbackIcon },
        progress = full("races", race.id),
    })
end

category("classes", L.ACH_CAT_CLASSES, { class = "WARRIOR" })
for _, class in ipairs(Catalog.classes) do
    local total = select(2, Catalog.ClassProgress({}, class.token))
    add({
        id = "class" .. class.token, name = L.ACH_CLASS:format(class.name), points = 10,
        description = L.ACH_CLASS_DESC:format(total, class.name),
        icon = { class = class.token },
        progress = full("classes", class.token),
    })
end

-- Back to the collection category: genders, the full journal and the bonus slots.
current = categories[2]
local perSex = (#Catalog.slots - #Catalog.bonusSlots) / 2
add({
    id = "sex2", name = L.ACH_MALE, description = L.ACH_MALE_DESC:format(perSex), points = 25,
    icon = { texture = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    progress = full("sexes", 2),
})
add({
    id = "sex3", name = L.ACH_FEMALE, description = L.ACH_FEMALE_DESC:format(perSex), points = 25,
    icon = { texture = "Interface\\Icons\\INV_Misc_Head_Human_02" },
    progress = full("sexes", 3),
})
add({
    id = "complete", name = L.ACH_COMPLETE, points = 50,
    description = L.ACH_COMPLETE_DESC:format(#Catalog.slots - #Catalog.bonusSlots),
    icon = { texture = ORB },
    progress = function(stats) return stats.standard, stats.standardTotal end,
})
add({
    id = "bonus", name = L.ACH_BONUS, description = L.ACH_BONUS_DESC:format(#Catalog.bonusSlots), points = 25,
    icon = { texture = "Interface\\Icons\\INV_Misc_Note_02" },
    progress = function(stats) return stats.bonus, #Catalog.bonusSlots end,
})

category("pets", L.ACH_CAT_PETS, { texture = PET_ICON })
local PET_POINTS = { [1] = 5, [10] = 10, [30] = 10, [60] = 25 }
for _, need in ipairs({ 1, 10, 30, 60 }) do
    add({
        id = "pets" .. need, name = L.ACH_PETS[need], points = PET_POINTS[need],
        description = need == 1 and L.ACH_PETS_FIRST or L.ACH_PETS_DESC:format(need),
        icon = { texture = PET_ICON },
        progress = function(stats) return stats.pets, need end,
    })
end

Achievements.list = list
Achievements.categories = categories

local function earned(achievement, stats)
    local have, need = achievement.progress(stats)
    return need > 0 and have >= need
end

-- Icon: an atlas when this client has it, otherwise a texture, otherwise the orb.
function Achievements.PaintIcon(texture, icon)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Show()
    if icon.class then
        Art.ClassIcon(texture, icon.class)
    elseif icon.atlas and Art.HasAtlas(icon.atlas) then
        texture:SetAtlas(icon.atlas)
    else
        local file = icon.texture or ORB
        -- The orb is a 64 px image shown at about 28: smoothed, or it looks pixelated.
        -- Only the addon's own images: the TRILINEAR filter on the game's files has
        -- crashed the client before (see Presence.lua).
        if file:find("^Interface\\AddOns\\ForeverDex\\") then
            Art.SmoothTexture(texture, file)
        else
            texture:SetTexture(file)
        end
    end
end

local function tooltip(owner, achievement)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(achievement.name, 1, 0.82, 0)
    GameTooltip:AddLine(achievement.description, 1, 1, 1, true)
    GameTooltip:AddLine(L.ACH_POINTS:format(achievement.points), 0.6, 0.9, 0.6)
    GameTooltip:AddLine(L.ACH_TOAST_TIP, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- The alert ------------------------------------------------------------------------
-- Forever does not load the game's achievement interface: its alert template calls
-- missing functions. ForeverDex builds the same frame itself, with the art and the
-- layout of the game's plain achievement alert (300 x 88): icon on the left, points on
-- the shield on the right, "achievement earned" at the top and the name in the middle.

local WIDTH, HEIGHT = 300, 88
-- Text column between the icon and the shield, as in the game's alert.
local TEXT_LEFT, TEXT_RIGHT = 72, 60
local alert, waiting = nil, {}
local showNext

local function atlas(texture, name)
    if Art.HasAtlas(name) then
        texture:SetAtlas(name, true)
        return true
    end
end

local function fade(group, from, to, duration, order, delay)
    local animation = group:CreateAnimation("Alpha")
    animation:SetFromAlpha(from)
    animation:SetToAlpha(to)
    animation:SetDuration(duration)
    animation:SetOrder(order or 1)
    if delay then animation:SetStartDelay(delay) end
    return animation
end

local function buildAlert()
    local frame = CreateFrame("Button", "ForeverDexAchievementAlert", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    -- Above the "New card" toast (bottom at 190, 84 high).
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 290)
    frame:SetFrameStrata("DIALOG")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:Hide()

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("CENTER")
    if not atlas(background, "ui-achievement-alert-background") then
        background:SetAllPoints()
        background:SetTexture(ACHIEVEMENT .. "UI-Achievement-Alert-Background")
        background:SetTexCoord(0, 0.605, 0, 0.703)
    end

    -- Black on the light strip under the top border, centred on it (21 below the top).
    frame.unlocked = frame:CreateFontString(nil, "ARTWORK", "GameFontBlackTiny")
    frame.unlocked:SetWidth(200)
    frame.unlocked:SetPoint("CENTER", frame, "TOP", 7, -21)
    frame.name = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.name:SetPoint("TOPLEFT", TEXT_LEFT, -36)
    frame.name:SetPoint("TOPRIGHT", -TEXT_RIGHT, -36)
    frame.name:SetHeight(30)
    frame.name:SetJustifyH("CENTER")
    frame.name:SetJustifyV("MIDDLE")
    if frame.name.SetMaxLines then frame.name:SetMaxLines(2) end

    -- Icon and its frame share the same centre, so the icon always sits in the frame.
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(50, 50)
    frame.icon:SetPoint("CENTER", frame, "TOPLEFT", 36, -44)
    local iconFrame = frame:CreateTexture(nil, "OVERLAY")
    iconFrame:SetPoint("CENTER", frame.icon)
    if not atlas(iconFrame, "ui-achievement-iconframe") then
        iconFrame:SetSize(72, 72)
        iconFrame:SetTexture(ACHIEVEMENT .. "UI-Achievement-IconFrame")
        iconFrame:SetTexCoord(0, 0.5625, 0, 0.5625)
    end

    -- Plain shield of the game's alert, the points in its middle. The background draws
    -- a wreath of laurels around it: the shield is centred in the wreath and kept small
    -- enough to leave the laurels visible on both sides.
    local shield = frame:CreateTexture(nil, "ARTWORK")
    shield:SetSize(44, 41)
    shield:SetPoint("CENTER", frame, "TOPLEFT", 262, -43)
    shield:SetTexture(ACHIEVEMENT .. "UI-Achievement-Shields")
    shield:SetTexCoord(0, 0.5, 0, 0.45)
    frame.points = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.points:SetPoint("CENTER", shield, "CENTER", 0, 2)
    frame.points:SetTextColor(1, 1, 1)

    -- Flash then light sweep, as the game plays them.
    local glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetPoint("CENTER")
    glow:SetBlendMode("ADD")
    if not atlas(glow, "ui-achievement-alert-glow") then
        glow:SetSize(WIDTH * 1.35, HEIGHT * 2)
        glow:SetTexture(ACHIEVEMENT .. "UI-Achievement-Alert-Glow")
        glow:SetTexCoord(0, 0.78125, 0, 0.66796875)
    end
    glow:SetAlpha(0)
    local flash = glow:CreateAnimationGroup()
    fade(flash, 0, 1, 0.2, 1)
    fade(flash, 1, 0, 0.5, 2)

    local shine = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    shine:SetSize(60, HEIGHT - 20)
    shine:SetPoint("BOTTOMLEFT", 0, 10)
    shine:SetBlendMode("ADD")
    shine:SetTexture(ACHIEVEMENT .. "UI-Achievement-Alert-Glow")
    shine:SetTexCoord(0.78125, 0.912109375, 0, 0.28125)
    shine:SetAlpha(0)
    local sweep = shine:CreateAnimationGroup()
    fade(sweep, 0, 1, 0.2, 1)
    local move = sweep:CreateAnimation("Translation")
    move:SetOffset(WIDTH - 60, 0)
    move:SetDuration(0.85)
    move:SetOrder(2)
    fade(sweep, 1, 0, 0.5, 2, 0.35)

    local intro = frame:CreateAnimationGroup()
    fade(intro, 0, 1, 0.2, 1)
    local outro = frame:CreateAnimationGroup()
    fade(outro, 1, 0, 1.5, 1)
    outro:SetScript("OnFinished", function() frame:Hide() end)

    function frame:Play()
        outro:Stop()
        self:SetAlpha(1)
        self.left = 4.5
        self:Show()
        intro:Play()
        flash:Play()
        sweep:Play()
    end
    -- Stays while hovered, like the game's alerts.
    frame:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then return end
        self.left = self.left - elapsed
        if self.left <= 0 and not outro:IsPlaying() then outro:Play() end
    end)
    frame:SetScript("OnEnter", function(self)
        outro:Stop()
        self:SetAlpha(1)
        if self.achievement then tooltip(self, self.achievement) end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnClick", function(self, button)
        GameTooltip:Hide()
        self:Hide()
        if button == "LeftButton" then ns.UI.ShowAchievements() end
    end)
    -- Several achievements at once: the next one waits for this one to leave.
    frame:SetScript("OnHide", function()
        local nextOne = table.remove(waiting, 1)
        if nextOne then C_Timer.After(0.3, function() showNext(nextOne) end) end
    end)
    return frame
end

-- The fanfare the game plays for an achievement. Its name varies between clients.
local fanfare
local function playFanfare()
    if not PlaySound or not ns.Settings.Get("sounds") then return end
    if fanfare == nil then
        fanfare = false
        for key, id in pairs(SOUNDKIT or {}) do
            local name = tostring(key)
            if name:find("ACHIEVEMENT") and (name:find("GAIN") or name:find("EARN")) then
                fanfare = id
                break
            end
        end
    end
    local ok, willPlay = pcall(PlaySound, fanfare or 12891, "SFX")
    if not ok or not willPlay then Art.Sound("LFG_REWARDS", "IG_QUEST_LIST_COMPLETE") end
end

showNext = function(achievement)
    alert = alert or buildAlert()
    if alert:IsShown() then
        waiting[#waiting + 1] = achievement
        return
    end
    alert.achievement = achievement
    alert.unlocked:SetText(L.ACH_UNLOCKED)
    -- Shrinks a long name first, then lets it wrap on a second line.
    Art.FitLine(alert.name, achievement.name, WIDTH - TEXT_LEFT - TEXT_RIGHT)
    Achievements.PaintIcon(alert.icon, achievement.icon)
    alert.points:SetText(achievement.points)
    playFanfare()
    alert:Play()
end

local function showAlert(achievement)
    showNext(achievement)
end

-- Unlocking ------------------------------------------------------------------------

-- Returns the achievements earned by this check. silent: they are recorded
-- without a date (collection gathered before the achievements existed).
function Achievements.Check(silent)
    if Achievements.paused or not ForeverDexDB or not ForeverDexDB.cards then return {} end
    local saved = ForeverDexDB.achievements or {}
    ForeverDexDB.achievements = saved
    local stats, fresh = measure(ForeverDexDB.cards), {}
    for _, achievement in ipairs(list) do
        if not saved[achievement.id] and earned(achievement, stats) then
            saved[achievement.id] = silent and 0 or time()
            fresh[#fresh + 1] = achievement
        end
    end
    return fresh
end

-- After a capture, the alert waits for the capture animation and its toast.
function Achievements.OnCollectionChanged(_, isNew, noThrow)
    local fresh = Achievements.Check()
    if #fresh == 0 then return end
    local delay = 0.5
    if isNew and not noThrow then
        local mode = ns.Settings.Get("animation")
        delay = mode == "full" and 6.5 or mode == "quick" and 3.5 or 0.5
    end
    C_Timer.After(delay, function()
        for _, achievement in ipairs(fresh) do
            print(L.CHAT_PREFIX .. L.ACH_EARNED:format(achievement.name))
            if ns.Settings.Get("achievementToast") then showAlert(achievement) end
        end
    end)
end

-- State of every achievement, for the achievements page: in list order, each row
-- with have / need (capped) and earned (time of unlock, 0 when granted at the first
-- check, nil when not earned yet). Also the totals, in achievements and in points.
function Achievements.State()
    local saved = ForeverDexDB and ForeverDexDB.achievements or {}
    local stats = measure(ForeverDexDB and ForeverDexDB.cards or {})
    local state = { rows = {}, done = 0, points = 0, totalPoints = 0, categories = {} }
    for _, group in ipairs(categories) do state.categories[group.id] = { done = 0, total = 0 } end
    for _, achievement in ipairs(list) do
        local have, need = achievement.progress(stats)
        local earnedAt = saved[achievement.id]
        state.rows[#state.rows + 1] = {
            achievement = achievement, have = math.min(have, need), need = need, earned = earnedAt,
        }
        local group = state.categories[achievement.category]
        group.total = group.total + 1
        state.totalPoints = state.totalPoints + achievement.points
        if earnedAt then
            group.done = group.done + 1
            state.done = state.done + 1
            state.points = state.points + achievement.points
        end
    end
    return state
end
end)
