local _, ns = ...
ns.Module(function()
local L, Art, Catalog, Home = ns.L, ns.Art, ns.Catalog, ns.Home
local HomeUI = {}
ns.HomeUI = HomeUI

-- Home page of the main window, the first one shown in each session. On the left, on
-- the painted journal background, the daily challenge: a combination to look for,
-- drawn on its race's scenery, with a parchment sheet below it. On the right, a
-- column with the summary of the latest release and a few statistics. The data comes
-- from Home.lua; this file only draws it. No sound is played here.

local UI = ns.UI
local window = UI.Window
local sidebar, content = UI.PageArea[1], UI.PageArea[2]

local SIDE_W, MARGIN, GAP = 300, 16, 6
-- The page covers the race column and the journal: from the window's left inset
-- to its right one, minus the right column.
local BOARD_W = window:GetWidth() - 16 - SIDE_W - GAP
local BANNER_W, BANNER_H = BOARD_W - 2 * MARGIN, 214
local TEXT_X = 116
local NEWS_H, NEWS_LINES = 214, 6
local STAT_ROWS, STAT_STEP, STAT_ICON = 6, 34, 24
local SECTION_PAD = 14

local INK = { 0.24, 0.13, 0.05 }
local INK_LIGHT = { 0.36, 0.22, 0.09 }
local GOLD = { 1, 0.82, 0 }
local MUTED = { 0.78, 0.71, 0.58 }
local SOFT = { 0.92, 0.88, 0.8 }
local NONE = "—"

local function text(parent, font, color)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetJustifyH("LEFT")
    if color then line:SetTextColor(unpack(color)) end
    return line
end

local function inkText(parent, font, color)
    local line = text(parent, font, color or INK)
    line:SetShadowColor(0, 0, 0, 0)
    return line
end

-- Square icon from a file, an atlas or a class, cropped like the game's icons.
local function setIcon(texture, file)
    texture:Show()
    texture:SetTexture(file)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Thin gold rule fading out at both ends, under a title.
local function rule(parent, anchor, rightInset)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(1)
    holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -7)
    holder:SetPoint("RIGHT", parent, "RIGHT", -rightInset, 0)
    local left = holder:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", holder, "BOTTOM")
    Art.Gradient(left, 1, 0.82, 0.4, 0.15, 0.75, "HORIZONTAL")
    local right = holder:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPLEFT", holder, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    Art.Gradient(right, 1, 0.82, 0.4, 0.75, 0, "HORIZONTAL")
    return holder
end

-- Header: replaces the journal progress at the top of the window ---------------------

local greeting = text(window, "GameFontNormal")
greeting:SetPoint("TOPLEFT", 70, -31)
local today = text(window, "GameFontHighlightSmall", MUTED)
today:SetPoint("TOPLEFT", 74, -50)

-- Frames: the board on the left, the column on the right ------------------------------

local side = Art.Inset(window)
side:SetPoint("TOPRIGHT", content, "TOPRIGHT")
side:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
side:SetWidth(SIDE_W)

local board = Art.Inset(window)
board:SetPoint("TOPLEFT", sidebar, "TOPLEFT")
board:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -GAP, 0)
Art.JournalBackground(board)

-- Section of the right column: dark box, thin gold edge, warm light at the top.
local function section(title)
    local box = CreateFrame("Frame", nil, side, "BackdropTemplate")
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0.1, 0.075, 0.045, 0.7)
    box:SetBackdropBorderColor(0.62, 0.5, 0.3, 0.9)
    local light = box:CreateTexture(nil, "BORDER")
    light:SetPoint("TOPLEFT", 3, -3)
    light:SetPoint("TOPRIGHT", -3, -3)
    light:SetHeight(46)
    Art.Gradient(light, 1, 0.75, 0.35, 0, 0.1)
    box.title = text(box, "GameFontNormalLarge")
    box.title:SetPoint("TOPLEFT", SECTION_PAD, -13)
    box.title:SetText(title)
    box.rule = rule(box, box.title, SECTION_PAD)
    return box
end

-- What's new ----------------------------------------------------------------------------

local news = section(L.HOME_NEWS)
news:SetPoint("TOPLEFT", 8, -8)
news:SetPoint("TOPRIGHT", -8, -8)
news:SetHeight(NEWS_H)
local version = text(news, "GameFontHighlightSmall", MUTED)
version:SetPoint("TOPRIGHT", -SECTION_PAD, -17)
version:SetJustifyH("RIGHT")
version:SetText(L.HOME_VERSION:format(Home.NEWS_VERSION))

-- One line per change, after a small gold diamond. The text is set once: it only
-- depends on the language, chosen before the modules load.
local newsWidth = SIDE_W - 16 - 2 * SECTION_PAD - 14
local previous
for i = 1, NEWS_LINES do
    local item = L.HOME_NEWS_LINES[i]
    if not item then break end
    local line = text(news, "GameFontHighlightSmall", SOFT)
    line:SetWidth(newsWidth)
    line:SetJustifyV("TOP")
    line:SetSpacing(2)
    if previous then
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -9)
    else
        line:SetPoint("TOPLEFT", news.rule, "BOTTOMLEFT", 14, -13)
    end
    line:SetText(item)
    local dot = news:CreateTexture(nil, "ARTWORK")
    dot:SetSize(5, 5)
    dot:SetColorTexture(1, 0.82, 0.35)
    if dot.SetRotation then dot:SetRotation(math.rad(45)) end
    dot:SetPoint("CENTER", line, "TOPLEFT", -9, -5)
    previous = line
end

-- Statistics ----------------------------------------------------------------------------

local stats = section(L.HOME_STATS)
stats:SetPoint("TOPLEFT", news, "BOTTOMLEFT", 0, -8)
stats:SetPoint("BOTTOMRIGHT", -8, 8)

local statRows = {}
for i = 1, STAT_ROWS do
    local row = {}
    row.icon = stats:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(STAT_ICON, STAT_ICON)
    row.icon:SetPoint("TOPLEFT", stats.rule, "BOTTOMLEFT", 0, -12 - (i - 1) * STAT_STEP)
    row.label = text(stats, "GameFontNormalSmall", MUTED)
    row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
    row.value = text(stats, "GameFontHighlight")
    row.value:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
    row.value:SetWordWrap(false)
    statRows[i] = row
end
local STAT_TEXT_W = SIDE_W - 16 - 2 * SECTION_PAD - STAT_ICON - 10

-- Daily challenge -------------------------------------------------------------------------

local title = text(board, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -9)
title:SetText(L.HOME_CHALLENGE)
local countdown = text(board, "GameFontHighlightSmall", MUTED)
countdown:SetPoint("TOPRIGHT", -14, -13)
countdown:SetJustifyH("RIGHT")

-- Banner: the race's scenery in the card frame, as on the detail page. Clicking it
-- opens the card in the journal.
local banner = CreateFrame("Button", nil, board)
banner:SetSize(BANNER_W, BANNER_H)
banner:SetPoint("TOPLEFT", MARGIN, -Art.JOURNAL_RECESS)
local plate = UI.BuildPlate(banner)
plate.shade:Hide()
local veil = banner:CreateTexture(nil, "BORDER")
veil:SetPoint("TOPLEFT", 3, -3)
veil:SetPoint("BOTTOMLEFT", 3, 3)
veil:SetWidth(BANNER_W * 0.72)
Art.Gradient(veil, 0, 0, 0, 0.9, 0, "HORIZONTAL")
local hover = banner:CreateTexture(nil, "HIGHLIGHT")
hover:SetPoint("TOPLEFT", 2, -2)
hover:SetPoint("BOTTOMRIGHT", -2, 2)
Art.Apply(hover, Art.CARD_HIGHLIGHT)

local medallion = Art.Medallion(banner, 84)
-- The offset is expressed at medallion scale (4 × 84/31 ≈ 11 pixels).
medallion:SetPoint("LEFT", banner, "LEFT", 4, 0)
medallion:SetFrameLevel(banner:GetFrameLevel() + 4)

local showcase = CreateFrame("Frame", nil, banner)
showcase:SetAllPoints()
showcase:SetFrameLevel(banner:GetFrameLevel() + 3)

local kicker = text(showcase, "GameFontNormalSmall", { 1, 0.86, 0.5 })
kicker:SetPoint("BOTTOMLEFT", TEXT_X, 138)
local race = showcase:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
race:SetJustifyH("LEFT")
race:SetShadowColor(0, 0, 0, 1)
race:SetShadowOffset(2, -2)
race:SetPoint("BOTTOMLEFT", TEXT_X, 102)
race:SetTextColor(unpack(GOLD))
local classIcon = showcase:CreateTexture(nil, "OVERLAY")
classIcon:SetSize(20, 20)
classIcon:SetPoint("BOTTOMLEFT", TEXT_X, 72)
local classLine = text(showcase, "GameFontHighlightLarge")
classLine:SetPoint("LEFT", classIcon, "RIGHT", 6, 0)

-- Card number, on the dark badge of the journal cards.
local badge = showcase:CreateTexture(nil, "ARTWORK")
badge:SetPoint("TOPRIGHT", -8, -8)
badge:SetColorTexture(0, 0, 0, 0.6)
local number = text(showcase, "GameFontNormalSmall", { 0.9, 0.8, 0.6 })
number:SetPoint("TOPRIGHT", -14, -14)
number:SetJustifyH("RIGHT")

-- Seal in the bottom right corner: the challenge met, or the name to outdo.
local seal = CreateFrame("Frame", nil, showcase, "BackdropTemplate")
seal:SetPoint("BOTTOMRIGHT", -14, 14)
seal:SetHeight(46)
seal:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
seal:SetBackdropColor(0, 0, 0, 0.7)
seal:SetBackdropBorderColor(1, 0.82, 0.4, 0.9)
local sealIcon = seal:CreateTexture(nil, "ARTWORK")
sealIcon:SetSize(24, 24)
sealIcon:SetPoint("LEFT", 10, 0)
local sealTitle = text(seal, "GameFontNormal")
sealTitle:SetPoint("TOPLEFT", sealIcon, "TOPRIGHT", 8, 2)
local sealName = text(seal, "GameFontHighlightSmall")
sealName:SetPoint("TOPLEFT", sealTitle, "BOTTOMLEFT", 0, -3)
sealName:SetWordWrap(false)
-- Golden light over the whole banner once the challenge is met.
local glory = showcase:CreateTexture(nil, "BACKGROUND")
glory:SetPoint("TOPLEFT", 3, -3)
glory:SetPoint("BOTTOMRIGHT", -3, 3)
glory:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
glory:SetBlendMode("ADD")
glory:SetAlpha(0.15)

-- Parchment sheet under the banner: the line of the day, then the progress of the
-- race and class of the card.
local sheet = CreateFrame("Frame", nil, board, "BackdropTemplate")
sheet:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -10)
sheet:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -MARGIN, MARGIN)
sheet:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
local parchment = sheet:CreateTexture(nil, "BACKGROUND")
parchment:SetPoint("TOPLEFT", 4, -4)
parchment:SetPoint("BOTTOMRIGHT", -4, 4)
if not Art.Apply(parchment, Art.PARCHMENT) then parchment:SetColorTexture(0.82, 0.72, 0.55) end

local SHEET_TEXT_W = BANNER_W - 44
local flavor = inkText(sheet, _G.QuestFont and "QuestFont" or "GameFontHighlight")
flavor:SetPoint("TOPLEFT", 22, -18)
flavor:SetWidth(SHEET_TEXT_W)
flavor:SetJustifyV("TOP")
flavor:SetSpacing(3)
local note = inkText(sheet, "GameFontBlackSmall", INK_LIGHT)
note:SetPoint("TOPLEFT", flavor, "BOTTOMLEFT", 0, -8)
note:SetWidth(SHEET_TEXT_W)

local divider = sheet:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(INK[1], INK[2], INK[3], 0.3)
divider:SetHeight(1)
divider:SetPoint("BOTTOMLEFT", 22, 96)
divider:SetPoint("BOTTOMRIGHT", -22, 96)

local progressRows = {}
for i = 1, 2 do
    local bar = Art.ProgressBar(sheet, 250, 11, true)
    bar:SetPoint("BOTTOMLEFT", 26, 62 - (i - 1) * 40)
    local label = inkText(sheet, "GameFontBlackSmall")
    label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -4, 6)
    progressRows[i] = { bar = bar, label = label }
end

local open = CreateFrame("Button", nil, sheet, "UIPanelButtonTemplate")
open:SetSize(160, 22)
open:SetText(L.HOME_VIEW_CARD)
open:SetPoint("BOTTOMRIGHT", -18, 18)

-- Painting ----------------------------------------------------------------------------------

local current, shownDay, resetAt

local function openCard()
    if current then UI.ShowCard(current.slot.key) end
end
banner:SetScript("OnClick", openCard)
open:SetScript("OnClick", openCard)
banner:SetScript("OnEnter", function(self)
    if not current then return end
    local slot = current.slot
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(L.HOME_CHALLENGE)
    GameTooltip:AddLine(slot.race .. L.SEPARATOR .. slot.class .. L.SEPARATOR .. slot.sex, 1, 1, 1)
    GameTooltip:AddLine(L.HOME_VIEW_CARD_TOOLTIP, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
banner:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function duration(seconds)
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if hours > 0 then return L.HOME_HOURS:format(hours, minutes) end
    return L.HOME_MINUTES:format(math.max(1, minutes))
end

local function paintCountdown()
    countdown:SetText(resetAt and L.HOME_NEXT_CHALLENGE:format(duration(math.max(0, resetAt - time()))) or "")
end

local function showSeal(icon, heading, name)
    seal:SetShown(heading ~= nil)
    if not heading then return end
    sealIcon:SetTexture(icon)
    sealTitle:SetText(heading)
    Art.FitLine(sealName, name, 190)
    seal:SetWidth(math.max(sealTitle:GetStringWidth(), sealName:GetStringWidth()) + 62)
end

local function paintChallenge(challenge)
    current = challenge
    local slot, entry = challenge.slot, challenge.entry
    -- Always in color: the card is an invitation, not a gap in the collection.
    UI.PaintPlate(plate, slot, true)
    UI.PaintMedallion(medallion, slot, true, false)
    kicker:SetText(challenge.improve and L.HOME_TARGET_IMPROVE or L.HOME_TARGET)
    Art.FitLine(race, slot.race, BANNER_W - TEXT_X - 230)
    Art.ClassIcon(classIcon, slot.token)
    classLine:SetText(slot.class .. L.SEPARATOR .. slot.sex)
    local color = RAID_CLASS_COLORS[slot.token]
    if color then classLine:SetTextColor(color.r, color.g, color.b) else classLine:SetTextColor(1, 1, 1) end
    number:SetText(L.CARD_NUMBER:format(slot.index))
    badge:SetSize(number:GetStringWidth() + 12, 20)

    glory:SetShown(challenge.done)
    if challenge.done then
        showSeal("Interface\\RaidFrame\\ReadyCheck-Ready", L.HOME_DONE, entry.name)
        flavor:SetText(L.HOME_DONE_TEXT:format(entry.name))
        note:SetText(L.HOME_DONE_NOTE)
    elseif challenge.improve then
        showSeal("Interface\\RaidFrame\\ReadyCheck-Waiting", L.HOME_HOLDER, entry.name)
        flavor:SetText(L.HOME_IMPROVE_TEXT:format(entry.name))
        note:SetText("")
    else
        showSeal()
        local lines = L.HOME_CHALLENGE_LINES
        flavor:SetText(lines[challenge.line % #lines + 1])
        note:SetText("")
    end

    -- Progress of the card's race and class, as on the detail page.
    local entries = ForeverDexDB.cards
    local raceHave, raceTotal = Catalog.RaceProgress(entries)[slot.raceID] or 0, 0
    for _, info in ipairs(Catalog.races) do
        if info.id == slot.raceID then raceTotal = info.total end
    end
    local classHave, classTotal = Catalog.ClassProgress(entries, slot.token)
    local progress = { { slot.race, raceHave, raceTotal }, { slot.class, classHave, classTotal } }
    for i, row in ipairs(progressRows) do
        local item = progress[i]
        row.label:SetText(L.RACE_PROGRESS:format(item[1], item[2], item[3]))
        row.bar:SetMinMaxValues(0, math.max(1, item[3]))
        row.bar:SetValue(item[2])
    end

    resetAt = time() + challenge.resetsIn
    paintCountdown()
end

local function paintStat(row, label, value)
    row.label:SetText(label)
    Art.FitLine(row.value, value or NONE, STAT_TEXT_W)
    row.value:SetTextColor(unpack(value and { 1, 1, 1 } or MUTED))
end

local function paintStats(figures)
    local rows = statRows

    setIcon(rows[1].icon, "Interface\\Icons\\INV_Misc_Book_09")
    local percent = figures.total > 0 and math.floor(figures.standard / figures.total * 100 + 0.5) or 0
    paintStat(rows[1], L.HOME_STAT_JOURNAL, L.HOME_STAT_JOURNAL_VALUE:format(figures.standard, figures.total, percent))

    setIcon(rows[2].icon, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    paintStat(rows[2], L.HOME_STAT_RECENT, tostring(figures.recent))

    -- The last capture shows its race portrait when the client has it.
    local last = figures.last
    local lastSlot = last and Catalog.slotByKey[last.key]
    local details = lastSlot and Catalog.Describe(lastSlot, last)
    if details and details.portraitAtlas and Art.HasAtlas(details.portraitAtlas) then
        rows[3].icon:Show()
        rows[3].icon:SetAtlas(details.portraitAtlas)
    else
        setIcon(rows[3].icon, details and details.fallbackIcon or "Interface\\Icons\\INV_Misc_Note_02")
    end
    paintStat(rows[3], L.HOME_STAT_LAST, last and ("|cffffd100%s|r%s%s"):format(
        last.name, L.SEPARATOR, date(L.HOME_DATE_FORMAT, last.capturedAt)))

    if figures.class then
        Art.ClassIcon(rows[4].icon, figures.class)
        local color = RAID_CLASS_COLORS[figures.class]
        local name = Home.ClassName(figures.class)
        if color and color.colorStr then name = ("|c%s%s|r"):format(color.colorStr, name) end
        paintStat(rows[4], L.HOME_STAT_CLASS, L.HOME_STAT_COUNT:format(name, figures.classCount))
    else
        setIcon(rows[4].icon, "Interface\\Icons\\INV_Misc_QuestionMark")
        paintStat(rows[4], L.HOME_STAT_CLASS, nil)
    end

    setIcon(rows[5].icon, "Interface\\Icons\\INV_Misc_Map_01")
    paintStat(rows[5], L.HOME_STAT_ZONE,
        figures.zone and L.HOME_STAT_COUNT:format(figures.zone, figures.zoneCount))

    local achievements = figures.achievements
    rows[6].icon:Show()
    rows[6].icon:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Shields")
    rows[6].icon:SetTexCoord(0, 0.5, 0, 0.45)
    paintStat(rows[6], L.ACH_TAB, achievements
        and L.HOME_STAT_ACHIEVEMENTS_VALUE:format(achievements.done, achievements.total, achievements.points))
end

function HomeUI.Refresh()
    if not board:IsShown() or not ForeverDexDB then return end
    local name = UnitName("player")
    greeting:SetText(name and L.HOME_GREETING:format(name) or L.HOME_TAB)
    today:SetText(date(L.HOME_DATE_FORMAT))
    shownDay = date("%Y-%m-%d")
    paintChallenge(Home.Challenge())
    paintStats(Home.Stats())
end

-- The countdown follows the clock while the page is on screen; at midnight, the
-- whole page is drawn again with the new challenge.
local ticker
local function tick()
    if date("%Y-%m-%d") ~= shownDay then HomeUI.Refresh() else paintCountdown() end
end
board:SetScript("OnShow", function()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(20, tick) end
end)
board:SetScript("OnHide", function()
    if ticker then ticker:Cancel() end
    ticker = nil
end)

-- Side tab and registration: UI.lua shows this page in place of the journal ----------------

UI.AddSideTab(1, "home", L.HOME_TAB, function(icon)
    icon:SetTexture("Interface\\AddOns\\ForeverDex\\Media\\Icon")
    icon:SetTexCoord(0, 1, 0, 1)
end)

local parts = { greeting, today, side, board }
function HomeUI.SetShown(shown)
    for _, part in ipairs(parts) do part:SetShown(shown) end
    if shown then HomeUI.Refresh() end
end
UI.RegisterPage("home", HomeUI)
end)
