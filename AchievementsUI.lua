local _, ns = ...
ns.Module(function()
local L, Art, Achievements = ns.L, ns.Art, ns.Achievements
local AchievementsUI = {}
ns.AchievementsUI = AchievementsUI

-- Achievements page of the main window, reached through its side tab on the right of
-- the window. It follows the journal: categories in a column on the left (like the
-- races), the achievements of the selected one on the painted background on the right,
-- each on its own parchment sheet with its progress bar. Overall points at the top.

local UI = ns.UI
local window = UI.Window
local sidebar, content = UI.PageArea[1], UI.PageArea[2]

local COLUMNS, CARD_HEIGHT, GAP, SIDE_MARGIN = 2, 78, 8, 16
local ACHIEVEMENT = "Interface\\AchievementFrame\\"
local INK = { 0.24, 0.13, 0.05 }
local INK_LIGHT = { 0.36, 0.22, 0.09 }
local FADED = { 0.32, 0.31, 0.29 }
local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:14:14|t"

local selected = Achievements.categories[1].id
local function text(parent, font, color)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetJustifyH("LEFT")
    if color then line:SetTextColor(unpack(color)) end
    return line
end

local function tooltip(owner, data)
    local achievement = data.achievement
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(achievement.name, 1, 0.82, 0)
    GameTooltip:AddLine(achievement.description, 1, 1, 1, true)
    GameTooltip:AddLine(L.ACH_POINTS:format(achievement.points), 0.6, 0.9, 0.6)
    if data.earned and data.earned > 0 then
        GameTooltip:AddLine(L.ACH_EARNED_ON:format(date(L.DATE_FORMAT, data.earned)), 0.8, 0.8, 0.8)
    elseif data.earned then
        GameTooltip:AddLine(L.ACH_EARNED_BEFORE, 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine(("%d / %d"):format(data.have, data.need), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

-- Header: replaces the journal progress at the top of the window ------------------------

local summary = text(window, "GameFontNormal")
summary:SetPoint("TOPLEFT", 70, -31)
local pointsBar = Art.ProgressBar(window, 300, 12, true)
pointsBar:SetPoint("TOPLEFT", 74, -50)
local pointsText = pointsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pointsText:SetPoint("CENTER", 0, 1)

-- Category column: same frame and rows as the race column ---------------------------------

local column = Art.Inset(window)
column:SetPoint("TOPLEFT", sidebar, "TOPLEFT")
column:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT")

local categoryRows = {}
for i, group in ipairs(Achievements.categories) do
    local row = Art.ListRow(column, 172, 38)
    row:SetPoint("TOPLEFT", 7, -7 - (i - 1) * 40)
    row.group = group
    Achievements.PaintIcon(row.icon, group.icon)
    row.name:SetText(group.name)
    row:SetScript("OnClick", function(self)
        selected = self.group.id
        if ForeverDexDB and ForeverDexDB.view then ForeverDexDB.view.achievements = selected end
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        AchievementsUI.Refresh()
    end)
    categoryRows[i] = row
end

-- Board: the painted journal background, with a title like the journal breadcrumb ---------

local board = Art.Inset(window)
board:SetPoint("TOPLEFT", content, "TOPLEFT")
board:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
Art.JournalBackground(board)
local title = text(board, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -9)

-- Achievement sheets ------------------------------------------------------------------------

local function buildSheet(width)
    local sheet = CreateFrame("Frame", nil, board, "BackdropTemplate")
    sheet:SetSize(width, CARD_HEIGHT)
    sheet:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sheet:EnableMouse(true)
    sheet:SetScript("OnEnter", function(self) if self.data then tooltip(self, self.data) end end)
    sheet:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sheet.parchment = sheet:CreateTexture(nil, "BACKGROUND")
    sheet.parchment:SetPoint("TOPLEFT", 4, -4)
    sheet.parchment:SetPoint("BOTTOMRIGHT", -4, 4)
    Art.Apply(sheet.parchment, Art.PARCHMENT)

    -- Icon in the frame of the game's achievements.
    sheet.icon = sheet:CreateTexture(nil, "ARTWORK")
    sheet.icon:SetSize(46, 46)
    sheet.icon:SetPoint("CENTER", sheet, "LEFT", 40, 0)
    local iconFrame = sheet:CreateTexture(nil, "OVERLAY")
    iconFrame:SetSize(68, 68)
    iconFrame:SetPoint("CENTER", sheet.icon)
    iconFrame:SetTexture(ACHIEVEMENT .. "UI-Achievement-IconFrame")
    iconFrame:SetTexCoord(0, 0.5625, 0, 0.5625)

    -- Points on the shield of the game's achievements.
    sheet.shield = sheet:CreateTexture(nil, "ARTWORK")
    sheet.shield:SetSize(44, 41)
    sheet.shield:SetPoint("RIGHT", -12, 3)
    sheet.shield:SetTexture(ACHIEVEMENT .. "UI-Achievement-Shields")
    sheet.shield:SetTexCoord(0, 0.5, 0, 0.45)
    sheet.points = sheet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sheet.points:SetPoint("CENTER", sheet.shield, "CENTER", 0, 2)

    local left, right = 76, 64
    sheet.name = text(sheet, "GameFontNormal")
    sheet.name:SetPoint("TOPLEFT", left, -11)
    sheet.name:SetPoint("RIGHT", -right, 0)
    sheet.name:SetWordWrap(false)
    sheet.date = text(sheet, "GameFontBlackTiny")
    sheet.date:SetPoint("TOPRIGHT", -right, -13)
    sheet.date:SetJustifyH("RIGHT")
    sheet.description = text(sheet, "GameFontBlackSmall")
    sheet.description:SetPoint("TOPLEFT", sheet.name, "BOTTOMLEFT", 0, -3)
    sheet.description:SetPoint("RIGHT", -right, 0)
    sheet.description:SetWordWrap(false)
    sheet.descriptionWidth = width - left - right

    -- Progress bar with the bordered frame of the game's achievement bars.
    sheet.bar = Art.ProgressBar(sheet, width - left - right, 11, true)
    sheet.bar:SetPoint("BOTTOMLEFT", left, 13)
    sheet.count = sheet.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sheet.count:SetPoint("CENTER", 0, 1)
    return sheet
end

local function paintSheet(sheet, data)
    sheet.data = data
    local achievement, earned = data.achievement, data.earned ~= nil
    Achievements.PaintIcon(sheet.icon, achievement.icon)
    sheet.icon:SetDesaturated(not earned)
    sheet.parchment:SetDesaturated(not earned)
    sheet.parchment:SetVertexColor(earned and 1 or 0.72, earned and 1 or 0.72, earned and 1 or 0.72)
    sheet.shield:SetDesaturated(not earned)
    sheet.points:SetText(achievement.points)
    sheet.points:SetTextColor(earned and 1 or 0.6, earned and 1 or 0.6, earned and 1 or 0.6)
    sheet.name:SetText(achievement.name)
    sheet.name:SetTextColor(unpack(earned and INK or FADED))
    Art.FitLine(sheet.description, achievement.description, sheet.descriptionWidth)
    sheet.description:SetTextColor(unpack(earned and INK_LIGHT or FADED))
    sheet.date:SetText(data.earned and data.earned > 0 and date("%d/%m/%Y", data.earned) or "")
    sheet:SetBackdropBorderColor(earned and 1 or 0.55, earned and 1 or 0.55, earned and 1 or 0.55)
    sheet.bar:SetMinMaxValues(0, math.max(1, data.need))
    sheet.bar:SetValue(data.have)
    if earned then
        sheet.bar:SetStatusBarColor(0.93, 0.66, 0.16)
    else
        sheet.bar:SetStatusBarColor(0.5, 0.5, 0.5)
    end
    sheet.count:SetText(("%d / %d"):format(data.have, data.need))
end

local sheets = {}

-- Refresh -----------------------------------------------------------------------------

function AchievementsUI.Refresh()
    if not board:IsShown() then return end
    local state = Achievements.State()
    summary:SetText(L.ACH_SUMMARY:format(state.done, #state.rows))
    pointsBar:SetMinMaxValues(0, math.max(1, state.totalPoints))
    pointsBar:SetValue(state.points)
    pointsText:SetText(L.ACH_POINTS_PROGRESS:format(state.points, state.totalPoints))

    local groupName
    for _, row in ipairs(categoryRows) do
        local group = state.categories[row.group.id]
        local isSelected = row.group.id == selected
        row.count:SetText(group.done .. "/" .. group.total)
        row.bar:SetMinMaxValues(0, math.max(1, group.total))
        row.bar:SetValue(group.done)
        row.selected:SetShown(isSelected)
        -- White when selected, gold otherwise, as in the race column.
        row.name:SetTextColor(1, isSelected and 1 or 0.82, isSelected and 1 or 0)
        if isSelected then groupName = row.group.name end
    end
    title:SetText(L.ACH_TAB .. " " .. ARROW .. " " .. (groupName or ""))

    -- Two columns of sheets inside the carved recess of the background.
    local width = board:GetWidth()
    if not width or width <= 0 then width = 732 end
    local sheetWidth = math.floor((width - 2 * SIDE_MARGIN - (COLUMNS - 1) * GAP) / COLUMNS)
    local shown = 0
    for _, data in ipairs(state.rows) do
        if data.achievement.category == selected then
            shown = shown + 1
            local sheet = sheets[shown]
            if not sheet or sheet:GetWidth() ~= sheetWidth then
                if sheet then sheet:Hide() end
                sheet = buildSheet(sheetWidth)
                sheets[shown] = sheet
            end
            local columnIndex, line = (shown - 1) % COLUMNS, math.floor((shown - 1) / COLUMNS)
            sheet:ClearAllPoints()
            sheet:SetPoint("TOPLEFT", SIDE_MARGIN + columnIndex * (sheetWidth + GAP),
                -Art.JOURNAL_RECESS - line * (CARD_HEIGHT + GAP))
            sheet:Show()
            paintSheet(sheet, data)
        end
    end
    for i = shown + 1, #sheets do sheets[i]:Hide() end
end

-- Side tab and registration: UI.lua shows this page in place of the journal --------------

UI.AddSideTab(4, "achievements", L.ACH_TAB, function(icon)
    icon:SetTexture(ACHIEVEMENT .. "UI-Achievement-Shields")
    icon:SetTexCoord(0, 0.5, 0, 0.45)
end)

local parts = { summary, pointsBar, column, board }
function AchievementsUI.SetShown(shown)
    for _, part in ipairs(parts) do part:SetShown(shown) end
    if shown then
        local saved = ForeverDexDB and ForeverDexDB.view and ForeverDexDB.view.achievements
        for _, group in ipairs(Achievements.categories) do
            if group.id == saved then selected = saved end
        end
        AchievementsUI.Refresh()
    end
end
UI.RegisterPage("achievements", AchievementsUI)

-- Controller (Gamepad.lua): the categories, then the sheets of the one shown (their
-- tooltip gives the details; A has nothing to do on them).
ns.Gamepad.RegisterPage("achievements", function()
    local targets = {}
    for _, row in ipairs(categoryRows) do targets[#targets + 1] = { frame = row, A = { L.PAD_SELECT } } end
    for _, sheet in ipairs(sheets) do
        if sheet:IsShown() then targets[#targets + 1] = { frame = sheet, noA = true } end
    end
    local first
    for _, row in ipairs(categoryRows) do
        if row.group.id == selected then first = row end
    end
    return { targets = targets, default = first }
end)
end)
