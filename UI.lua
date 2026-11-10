local _, ns = ...
ns.Module(function()
local L, Catalog, Collection, Art = ns.L, ns.Catalog, ns.Collection, ns.Art

-- Layout inspired by the Adventure Guide: portrait frame, race list on
-- the left, grid of "instance buttons" on the right, tabs at the bottom.
local PAGE_SIZE, COLUMNS = 9, 3
local CARD_W, CARD_H, GAP = 214, 118, 12
local CARD_TEXT_W = CARD_W - 20
local BANNER_W, BANNER_H, BANNER_TEXT_X = 680, 190, 92
local BANNER_TEXT_W = BANNER_W - BANNER_TEXT_X - 16
local INK = { 0.24, 0.13, 0.05 }
-- Useful part of the Adventure Guide instance thumbnails (175 × 95 in a 256 × 128 file).
local COVER_COORDS = { 0, 0.68359375, 0, 0.7421875 }

local page, sortMode, viewMode, detailKey, pendingReveal = 1, 1, 1, nil, nil
local filters = { races = {}, classes = {}, sexes = {} }
local refresh, updateTarget

-- A template missing from this client must not prevent the addon from loading.
local function create(frameType, name, parent, template, fallback)
    if template then
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, true end
    end
    return CreateFrame(frameType, name, parent, fallback), false
end

local function fontObject(name, fallback)
    return _G[name] and name or fallback
end

local function text(parent, font, r, g, b)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetJustifyH("LEFT")
    if r then line:SetTextColor(r, g, b) end
    return line
end

-- Displays text at the largest size that fits on one line.
local function fitText(line, value, size, minimum, maxWidth)
    maxWidth = maxWidth or CARD_TEXT_W
    line:SetText(value)
    for current = size, minimum, -1 do
        Art.Font(line, current, "OUTLINE")
        local width = line.GetUnboundedStringWidth and line:GetUnboundedStringWidth() or line:GetStringWidth()
        if width <= maxWidth then return end
    end
end

local function button(parent, title, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 22)
    control:SetText(title)
    control:SetScript("OnClick", action)
    return control
end

local function styleInset(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
    frame:SetBackdropBorderColor(0.55, 0.45, 0.3)
end

-- Window ----------------------------------------------------------------------

local panel, nativePanel = create("Frame", "ForeverDexWindow", UIParent, "PortraitFrameTemplate", "BackdropTemplate")
panel:SetSize(940, 580)
panel:SetPoint("CENTER")
panel:SetClampedToScreen(true)
panel:SetFrameStrata("HIGH")
panel:SetToplevel(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:Hide()
tinsert(UISpecialFrames, panel:GetName())

if nativePanel then
    if panel.SetTitle then panel:SetTitle("ForeverDex") end
    if panel.SetPortraitToAsset then panel:SetPortraitToAsset("Interface\\AddOns\\ForeverDex\\Media\\Icon") end
else
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    local title = text(panel, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("ForeverDex")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    panel.CloseButton = panel.CloseButton or close
end

-- Gear: opens the addon settings.
local gear = CreateFrame("Button", nil, panel)
gear:SetSize(16, 16)
if panel.CloseButton then
    gear:SetPoint("RIGHT", panel.CloseButton, "LEFT", -2, 0)
else
    gear:SetPoint("TOPRIGHT", -30, -4)
end
gear:SetFrameLevel(panel:GetFrameLevel() + 10)
gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
gear:SetScript("OnClick", function() ns.Settings.Open() end)
gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.SETTINGS_TITLE)
    GameTooltip:Show()
end)
gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Header: overall progress, search, sort and capture.
local counts = text(panel, "GameFontNormal")
counts:SetPoint("TOPLEFT", 70, -31)
local percent = text(panel, "GameFontHighlightSmall", 0.85, 0.85, 0.85)
percent:SetPoint("LEFT", counts, "RIGHT", 8, 0)
local progress = Art.ProgressBar(panel, 250, 12, true)
progress:SetPoint("TOPLEFT", 74, -50)
progress:SetMinMaxValues(0, #Catalog.slots)
progress:SetValue(0)

local panelCapture = button(panel, L.ADD_TARGET, 150, function()
    if viewMode == 4 then Collection.CaptureBonus() else Collection.Capture() end
end)
panelCapture:SetPoint("TOPRIGHT", -14, -40)

local sortNames = { L.SORT_COMBINATION, L.SORT_NUMBER, L.SORT_NAME, L.SORT_RACE, L.SORT_CLASS, L.SORT_DATE, L.SORT_LEVEL }
local sortButton = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
sortButton:SetSize(150, 26)
sortButton:SetDefaultText(sortNames[sortMode])
sortButton:SetPoint("RIGHT", panelCapture, "LEFT", -10, 0)

-- Checkbox filters: one column per category, all visible at once.
local filterFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
local filterButton = button(panel, L.FILTERS, 96, function()
    filterFrame:SetShown(not filterFrame:IsShown())
end)
filterButton:SetPoint("RIGHT", sortButton, "LEFT", -8, 0)

filterFrame:SetSize(436, 296)
filterFrame:SetPoint("TOPRIGHT", sortButton, "BOTTOMRIGHT", 0, -6)
filterFrame:SetFrameLevel(panel:GetFrameLevel() + 60)
filterFrame:EnableMouse(true)
filterFrame:Hide()
styleInset(filterFrame)
-- A click outside the panel closes it.
filterFrame:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
filterFrame:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
filterFrame:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not filterButton:IsMouseOver() then self:Hide() end
end)

local filterChecks = {}

local function filterColumn(x, title, items, set)
    local heading = text(filterFrame, "GameFontNormal")
    heading:SetPoint("TOPLEFT", x, -12)
    heading:SetText(title)
    for i, item in ipairs(items) do
        local check = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", x - 2, -32 - (i - 1) * 22)
        check:SetHitRectInsets(0, -108, 0, 0)
        check.set, check.value = set, item.value
        local label = text(check, "GameFontHighlightSmall")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetWidth(108)
        label:SetWordWrap(false)
        label:SetText(item.name)
        if item.color then label:SetTextColor(item.color.r, item.color.g, item.color.b) end
        check:SetScript("OnClick", function(self)
            self.set[self.value] = self:GetChecked() and true or nil
            page, detailKey = 1, nil
            Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            refresh()
        end)
        filterChecks[#filterChecks + 1] = check
    end
end

do
    local raceItems, classItems = {}, {}
    for i, race in ipairs(Catalog.races) do raceItems[i] = { name = race.name, value = race.id } end
    for i, class in ipairs(Catalog.classes) do
        classItems[i] = { name = class.name, value = class.token, color = RAID_CLASS_COLORS[class.token] }
    end
    filterColumn(14, L.SORT_RACE, raceItems, filters.races)
    filterColumn(154, L.SORT_CLASS, classItems, filters.classes)
    filterColumn(294, L.FILTER_SEX, { { name = L.MALE, value = 2 }, { name = L.FEMALE, value = 3 } }, filters.sexes)
end

local function activeFilters()
    local count = 0
    for _, set in pairs(filters) do
        for _ in pairs(set) do count = count + 1 end
    end
    return count
end

local function clearFilters()
    for _, set in pairs(filters) do wipe(set) end
end

local filterReset = button(filterFrame, L.FILTER_RESET, 130, function()
    clearFilters()
    page, detailKey = 1, nil
    refresh()
end)
filterReset:SetPoint("BOTTOMRIGHT", -12, 10)

local function updateFilterPanel()
    local count = activeFilters()
    filterButton:SetText(count > 0 and L.FILTERS_ACTIVE:format(count) or L.FILTERS)
    filterReset:SetEnabled(count > 0)
    for _, check in ipairs(filterChecks) do check:SetChecked(check.set[check.value] == true) end
end

local search, nativeSearch = create("EditBox", nil, panel, "SearchBoxTemplate", "InputBoxTemplate")
search:SetSize(165, 20)
search:SetPoint("RIGHT", filterButton, "LEFT", -10, 0)
search:SetAutoFocus(false)
search:SetMaxLetters(80)
local placeholder = search.Instructions
if placeholder then
    placeholder:SetText(L.SEARCH)
else
    placeholder = text(search, "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText(L.SEARCH)
end
if not nativeSearch then
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
end

-- Race column --------------------------------------------------------------

local sidebar, nativeSidebar = create("Frame", nil, panel, "InsetFrameTemplate", "BackdropTemplate")
if not nativeSidebar then styleInset(sidebar) end
sidebar:SetPoint("TOPLEFT", 8, -72)
sidebar:SetPoint("BOTTOMLEFT", 8, 8)
sidebar:SetWidth(186)

local raceButtons = {}
local raceRows = { { name = L.ALL_RACES, icon = "Interface\\Icons\\INV_Misc_Book_09" } }
for _, race in ipairs(Catalog.races) do raceRows[#raceRows + 1] = race end

for i, filter in ipairs(raceRows) do
    local row = CreateFrame("Button", nil, sidebar)
    row:SetSize(172, 38)
    row:SetPoint("TOPLEFT", 7, -7 - (i - 1) * 40)
    row.filter = filter
    local back = row:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    Art.Apply(back, Art.ROW_BG)
    row.selected = row:CreateTexture(nil, "BORDER")
    row.selected:SetAllPoints()
    Art.Apply(row.selected, Art.ROW_SELECTED)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    Art.Apply(highlight, Art.ROW_HIGHLIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 5, 0)
    if filter.id and Art.HasAtlas(filter.icon) then
        row.icon:SetAtlas(filter.icon)
    else
        row.icon:SetTexture(filter.id and (filter.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark") or filter.icon)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    row.name = text(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -1)
    row.name:SetWidth(96)
    row.name:SetWordWrap(false)
    row.name:SetText(filter.name)
    row.count = text(row, "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", -6, -7)
    row.count:SetJustifyH("RIGHT")
    row.bar = Art.ProgressBar(row, 10, 5)
    row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.bar:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
        -- The list picks a single race; the Filters panel lets you check several.
        wipe(filters.races)
        if self.filter.id then filters.races[self.filter.id] = true end
        detailKey, page = nil, 1
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        refresh()
    end)
    raceButtons[i] = row
end

-- Duel button, at the bottom of the race column.
local compare = button(sidebar, L.COMPARE, 172, function()
    if ns.Duel then ns.Duel.Request() end
end)
compare:SetPoint("BOTTOM", 0, 10)
compare:SetMotionScriptsWhileDisabled(true)
compare:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.COMPARE)
    GameTooltip:AddLine(L.COMPARE_TOOLTIP, 1, 1, 1, true)
    GameTooltip:Show()
end)
compare:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Main area ---------------------------------------------------------------

local content, nativeContent = create("Frame", nil, panel, "InsetFrameTemplate", "BackdropTemplate")
if not nativeContent then styleInset(content) end
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
content:SetPoint("BOTTOMRIGHT", -8, 8)
local journalArt = content:CreateTexture(nil, "BACKGROUND", nil, 1)
journalArt:SetPoint("TOPLEFT", 3, -3)
journalArt:SetPoint("BOTTOMRIGHT", -3, 3)
Art.Apply(journalArt, Art.JOURNAL_BG)
local veil = content:CreateTexture(nil, "BACKGROUND", nil, 2)
veil:SetAllPoints(journalArt)
veil:SetColorTexture(0, 0, 0, 0.3)

-- Breadcrumb in the style of the Adventure Guide navigation bar.
local crumbs = {}
for i = 1, 3 do
    local crumb = CreateFrame("Button", nil, content)
    crumb:SetHeight(18)
    crumb.label = text(crumb, i == 1 and "GameFontNormalLarge" or "GameFontNormal")
    crumb.label:SetPoint("LEFT")
    if i == 1 then
        crumb:SetPoint("TOPLEFT", 14, -9)
    else
        crumb.arrow = text(content, "GameFontNormal")
        crumb.arrow:SetText("|TInterface\\ChatFrame\\ChatFrameExpandArrow:14:14|t")
        crumb.arrow:SetPoint("LEFT", crumbs[i - 1], "RIGHT", 4, -1)
        crumb:SetPoint("LEFT", crumb.arrow, "RIGHT", 4, 1)
    end
    crumb:SetScript("OnClick", function(self)
        if self.action then
            Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            self.action()
        end
    end)
    crumbs[i] = crumb
end

local function setCrumbs(items)
    for i, crumb in ipairs(crumbs) do
        local item = items[i]
        crumb:SetShown(item ~= nil)
        if crumb.arrow then crumb.arrow:SetShown(item ~= nil) end
        if item then
            crumb.label:SetText(item[1])
            crumb:SetWidth(crumb.label:GetStringWidth() + 2)
            crumb.action = item[2]
            if item[2] then
                crumb.label:SetTextColor(1, 0.82, 0)
            else
                crumb.label:SetTextColor(0.95, 0.92, 0.85)
            end
        end
    end
end

-- Adventure Guide covers, cached per world map.
local covers = {}
local function getCover(theme)
    if not theme or not EJ_GetInstanceForMap or not EJ_GetInstanceInfo then return end
    local map = theme[2]
    if covers[map] == nil then
        covers[map] = false
        local journalID = EJ_GetInstanceForMap(map)
        if journalID and journalID > 0 then
            local _, _, _, buttonImage, _, wideImage = EJ_GetInstanceInfo(journalID)
            if buttonImage and buttonImage ~= 0 and buttonImage ~= "" then
                covers[map] = { buttonImage, COVER_COORDS }
            elseif wideImage and wideImage ~= 0 and wideImage ~= "" then
                covers[map] = { wideImage, { 0, 1, 0, 1 } }
            end
        end
    end
    return covers[map] or nil
end

-- A "plate" groups the cover, its gradient and the gold frame.
local function buildPlate(frame)
    local plate = { width = frame:GetWidth() - 6, height = frame:GetHeight() - 6 }
    plate.tint = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    plate.cover = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    for _, texture in ipairs({ plate.tint, plate.cover }) do
        texture:SetPoint("TOPLEFT", 3, -3)
        texture:SetPoint("BOTTOMRIGHT", -3, 3)
    end
    plate.shade = frame:CreateTexture(nil, "BORDER")
    plate.shade:SetPoint("BOTTOMLEFT", 3, 3)
    plate.shade:SetPoint("BOTTOMRIGHT", -3, 3)
    plate.shade:SetHeight(frame:GetHeight() * 0.6)
    Art.Gradient(plate.shade, 0, 0, 0, 0.92, 0)
    plate.accent = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.accent:SetPoint("BOTTOMLEFT", 5, 5)
    plate.accent:SetPoint("BOTTOMRIGHT", -5, 5)
    plate.accent:SetHeight(2)
    plate.border = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.border:SetAllPoints()
    if not Art.Apply(plate.border, Art.CARD_FRAME) then
        local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        edge:SetAllPoints()
        edge:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 16 })
    end
    return plate
end

local function paintPlate(plate, combination, entry)
    local theme = combination and combination.theme
    local dim = entry and 1 or 0.5
    if theme then
        plate.tint:SetColorTexture(theme[3] * dim, theme[4] * dim, theme[5] * dim)
    else
        plate.tint:SetColorTexture(0.2 * dim, 0.15 * dim, 0.1 * dim)
    end
    -- The race loading screen is the most detailed image; the dressing room
    -- backdrop and then the Adventure Guide cover serve as fallbacks.
    local shown = Art.LoadingScreen(plate.cover, theme, plate.width, plate.height)
    if not shown then shown = Art.Scenery(plate.cover, theme, plate.width, plate.height) end
    if not shown then
        local cover = getCover(theme)
        if cover then
            plate.cover:SetTexture(cover[1])
            plate.cover:SetTexCoord(unpack(cover[2]))
            shown = true
        end
    end
    plate.cover:SetShown(shown)
    plate.cover:SetDesaturated(not entry)
    local shade = entry and 1 or 0.6
    plate.cover:SetVertexColor(shade, shade, shade)
    local color = combination and RAID_CLASS_COLORS[combination.token]
    if entry and color then
        plate.accent:SetColorTexture(color.r, color.g, color.b)
    else
        plate.accent:SetColorTexture(0.45, 0.36, 0.24)
    end
end

local function paintMedallion(medallion, combination, entry, live)
    local icon = medallion.icon
    if live then
        icon:SetTexture(nil)
        icon:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(icon, "target")
    elseif combination and Art.HasAtlas(combination.portraitAtlas) then
        icon:SetAtlas(combination.portraitAtlas)
    else
        icon:SetTexture(combination and combination.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    icon:SetDesaturated(not entry and not live)
end

-- Card grid ----------------------------------------------------------------

-- Favorite star, on the cards and the detail page. The raid marker exists on
-- every client; it is grayed out as long as the card is not a favorite.
local function favoriteStar(parent, size)
    local star = CreateFrame("Button", nil, parent)
    star:SetSize(size, size)
    star:SetFrameLevel(parent:GetFrameLevel() + 5)
    star.icon = star:CreateTexture(nil, "ARTWORK")
    star.icon:SetAllPoints()
    star.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    star:SetScript("OnClick", function(self)
        if not self.entry then return end
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Collection.ToggleFavorite(self.entry)
    end)
    star:SetScript("OnEnter", function(self)
        if not self.entry then return end
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.favorite and L.FAVORITE_REMOVE or L.FAVORITE_ADD)
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self.entry and self.entry.favorite and 1 or 0.65)
        GameTooltip:Hide()
    end)
    return star
end

local function paintStar(star, entry)
    star.entry = entry
    star:SetShown(entry ~= nil)
    if not entry then return end
    star.icon:SetDesaturated(not entry.favorite)
    star.icon:SetAlpha(entry.favorite and 1 or 0.65)
end

local function openCardMenu(card)
    local row = card.row
    if not row or not row.entry or row.slot.key == pendingReveal then return end
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    local entry, key = row.entry, row.slot.key
    MenuUtil.CreateContextMenu(card, function(_, root)
        root:CreateButton(entry.favorite and L.FAVORITE_REMOVE or L.FAVORITE_ADD, function()
            Collection.ToggleFavorite(entry)
        end)
        if row.slot.sex then
            local free, label = Collection.FindBonusSlot(entry)
            local item = root:CreateButton(free and L.SEND_TO_BONUS or label, function()
                Collection.MoveToBonus(key)
            end)
            item:SetEnabled(free ~= nil)
        elseif entry.combination then
            local free = Collection.StandardCardFree(entry)
            local item = root:CreateButton(free and L.RESTORE_CARD or L.RESTORE_TAKEN, function()
                Collection.MoveToStandard(key)
            end)
            item:SetEnabled(free)
        end
        root:CreateDivider()
        root:CreateButton(L.DELETE_CARD, function()
            StaticPopup_Show("FOREVERDEX_DELETE", entry.name, nil, key)
        end)
    end)
end

local grid = CreateFrame("Frame", nil, content)
grid:SetPoint("TOP", 0, -36)
grid:SetSize(COLUMNS * CARD_W + (COLUMNS - 1) * GAP, 3 * CARD_H + 2 * GAP)

local cards = {}
for i = 1, PAGE_SIZE do
    local card = CreateFrame("Button", nil, grid)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", ((i - 1) % COLUMNS) * (CARD_W + GAP), -math.floor((i - 1) / COLUMNS) * (CARD_H + GAP))
    card.plate = buildPlate(card)
    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 2, -2)
    highlight:SetPoint("BOTTOMRIGHT", -2, 2)
    Art.Apply(highlight, Art.CARD_HIGHLIGHT)

    card.medallion = Art.Medallion(card, 48)
    card.medallion:SetPoint("TOPLEFT", 3, -2)
    card.medallion:SetFrameLevel(card:GetFrameLevel() + 3)
    card.targeted = text(card, "GameFontGreenSmall")
    Art.Font(card.targeted, 10, "OUTLINE")
    card.targeted:SetPoint("TOPLEFT", 54, -18)
    card.targeted:SetText(L.TARGETED)

    -- Dark badge: the number and level stay readable on every image.
    card.badge = card:CreateTexture(nil, "ARTWORK", nil, 3)
    card.badge:SetPoint("TOPRIGHT", -5, -5)
    card.badge:SetColorTexture(0, 0, 0, 0.6)
    card.star = favoriteStar(card, 18)
    card.star:SetPoint("TOPRIGHT", card.badge, "TOPLEFT", -3, 0)

    card.number = text(card, "GameFontNormalSmall", 0.9, 0.8, 0.6)
    card.number:SetPoint("TOPRIGHT", -10, -9)
    card.number:SetJustifyH("RIGHT")
    card.status = text(card, "GameFontHighlightSmall")
    card.status:SetPoint("TOPRIGHT", card.number, "BOTTOMRIGHT", 0, -2)
    card.status:SetJustifyH("RIGHT")
    card.name = text(card, "GameFontNormalLarge")
    card.name:SetShadowColor(0, 0, 0, 1)
    card.name:SetShadowOffset(1, -1)
    card.name:SetWidth(CARD_TEXT_W)
    card.name:SetWordWrap(false)
    card.guild = text(card, "GameFontHighlightSmall", 0.45, 1, 0.45)
    card.guild:SetPoint("BOTTOMLEFT", 10, 26)
    card.guild:SetWidth(CARD_TEXT_W)
    card.guild:SetWordWrap(false)
    card.classIcon = card:CreateTexture(nil, "OVERLAY")
    card.classIcon:SetSize(14, 14)
    card.classIcon:SetPoint("BOTTOMLEFT", 10, 11)
    card.details = text(card, "GameFontHighlightSmall")
    card.details:SetPoint("LEFT", card.classIcon, "RIGHT", 4, 0)
    card.details:SetWidth(CARD_W - 40)
    card.details:SetWordWrap(false)

    -- Gold flash played when the capture ball reveals this card.
    card.flash = card:CreateTexture(nil, "OVERLAY", nil, 7)
    card.flash:SetAllPoints()
    card.flash:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    card.flash:SetBlendMode("ADD")
    card.flash:SetAlpha(0)
    local flash = card.flash:CreateAnimationGroup()
    local flashIn = flash:CreateAnimation("Alpha")
    flashIn:SetFromAlpha(0)
    flashIn:SetToAlpha(1)
    flashIn:SetDuration(0.12)
    flashIn:SetOrder(1)
    local flashOut = flash:CreateAnimation("Alpha")
    flashOut:SetFromAlpha(1)
    flashOut:SetToAlpha(0)
    flashOut:SetDuration(0.7)
    flashOut:SetOrder(2)
    card.flashAnimation = flash

    card:SetScript("OnEnter", function(self)
        local row = self.row
        if not row then return end
        local hidden = row.slot.key == pendingReveal
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.entry and not hidden and row.entry.name or L.UNDISCOVERED_TOOLTIP)
        GameTooltip:AddLine(row.description, 1, 1, 1, true)
        if row.entry and row.entry.guild and not hidden then
            GameTooltip:AddLine("<" .. row.entry.guild .. ">", 0.25, 1, 0.25)
        end
        if self.targeted:IsShown() then GameTooltip:AddLine(L.LIVE_TOOLTIP, 1, 0.82, 0.36) end
        GameTooltip:AddLine(L.CLICK_DETAIL, 0.6, 0.6, 0.6)
        if row.entry and not hidden then GameTooltip:AddLine(L.RIGHT_CLICK_MENU, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetScript("OnClick", function(self, mouseButton)
        if not self.row then return end
        if mouseButton == "RightButton" then
            openCardMenu(self)
            return
        end
        detailKey = self.row.slot.key
        Art.Sound("IG_SPELLBOOK_OPEN")
        refresh()
    end)
    cards[i] = card
end

local function paintCard(card, row)
    card.row = row
    local slot = row.slot
    local entry = row.entry
    if slot.key == pendingReveal then entry = nil end
    paintPlate(card.plate, row.details, entry)
    card.number:SetText(("%s#%03d"):format(slot.sex and "" or L.BONUS_BADGE, slot.index))
    -- A discovered card shows the player's level rather than a redundant status.
    if entry then
        card.status:SetText(entry.level and L.LEVEL_SHORT:format(entry.level) or "")
        card.status:SetTextColor(1, 0.9, 0.65)
    else
        card.status:SetText(L.UNDISCOVERED)
        card.status:SetTextColor(0.7, 0.7, 0.7)
    end
    card.badge:SetSize(math.max(card.number:GetStringWidth(), card.status:GetStringWidth()) + 12,
        (entry and not entry.level) and 18 or 31)

    -- The name is the star; the guild, when there is one, sits below it.
    fitText(card.name, entry and entry.name or "???", 20, 13)
    if entry then card.name:SetTextColor(1, 0.82, 0) else card.name:SetTextColor(0.6, 0.6, 0.6) end
    local guild = entry and entry.guild
    card.guild:SetShown(guild ~= nil)
    if guild then fitText(card.guild, "<" .. guild .. ">", 12, 9) end
    card.name:ClearAllPoints()
    card.name:SetPoint("BOTTOMLEFT", 10, guild and 39 or 27)
    -- The gradient stops just above the text to keep the image visible.
    card.plate.shade:SetHeight(guild and 74 or 60)
    paintStar(card.star, entry)
    Art.FitLine(card.details, row.description, CARD_W - 41, true)
    local color = row.details and RAID_CLASS_COLORS[row.details.token]
    if entry and color then
        card.details:SetTextColor(color.r, color.g, color.b)
    else
        card.details:SetTextColor(0.7, 0.7, 0.7)
    end
    Art.ClassIcon(card.classIcon, row.details and row.details.token)
    card.classIcon:SetDesaturated(not entry)
end

local empty = text(content, "GameFontHighlightLarge", 0.9, 0.85, 0.75)
empty:SetPoint("CENTER", grid, "CENTER")
empty:SetJustifyH("CENTER")
empty:SetText(L.NO_RESULTS)

-- Pagination: spellbook arrows and mouse wheel.
local pager = CreateFrame("Frame", nil, content)
pager:SetPoint("BOTTOMLEFT", 8, 6)
pager:SetPoint("BOTTOMRIGHT", -8, 6)
pager:SetHeight(32)
local results = text(pager, "GameFontNormalSmall", 0.85, 0.75, 0.55)
results:SetPoint("LEFT", 8, 0)

local function pageButton(direction, step)
    local control = CreateFrame("Button", nil, pager)
    control:SetSize(28, 28)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    control:SetNormalTexture(base .. "Up")
    control:SetPushedTexture(base .. "Down")
    control:SetDisabledTexture(base .. "Disabled")
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetScript("OnClick", function()
        page = page + step
        Art.Sound("IG_ABILITY_PAGE_TURN")
        refresh()
    end)
    return control
end
local nextPage = pageButton("Next", 1)
nextPage:SetPoint("RIGHT", -4, 0)
local pageText = text(pager, "GameFontHighlightSmall")
pageText:SetPoint("RIGHT", nextPage, "LEFT", -6, 0)
local previous = pageButton("Prev", -1)
previous:SetPoint("RIGHT", pageText, "LEFT", -6, 0)

content:EnableMouseWheel(true)
content:SetScript("OnMouseWheel", function(_, delta)
    if detailKey then return end
    if (delta > 0 and previous:IsEnabled()) or (delta < 0 and nextPage:IsEnabled()) then
        page = page - delta
        Art.Sound("IG_ABILITY_PAGE_TURN")
        refresh()
    end
end)

-- Detail page in the style of an encounter page ----------------------------------------

local detail = CreateFrame("Frame", nil, content)
detail:SetPoint("TOPLEFT", 4, -32)
detail:SetPoint("BOTTOMRIGHT", -4, 4)
detail:Hide()
local paper = detail:CreateTexture(nil, "BACKGROUND")
paper:SetAllPoints()
if not Art.Apply(paper, Art.PARCHMENT) then paper:SetColorTexture(0.82, 0.72, 0.55) end

local coverHolder = CreateFrame("Frame", nil, detail)
coverHolder:SetSize(BANNER_W, BANNER_H)
coverHolder:SetPoint("TOPLEFT", 22, -18)
detail.plate = buildPlate(coverHolder)
-- The veil starts from the left: text stays readable and the scenery clear on the right.
detail.plate.shade:Hide()
local bannerVeil = coverHolder:CreateTexture(nil, "BORDER")
bannerVeil:SetPoint("TOPLEFT", 3, -3)
bannerVeil:SetPoint("BOTTOMLEFT", 3, 3)
bannerVeil:SetWidth(540)
Art.Gradient(bannerVeil, 0, 0, 0, 0.9, 0, "HORIZONTAL")
-- Beyond this size, the minimap ring pixelates.
detail.medallion = Art.Medallion(coverHolder, 72)
-- The offset is expressed at medallion scale (4 × 72/31 ≈ 9 pixels).
detail.medallion:SetPoint("LEFT", coverHolder, "LEFT", 4, 0)
detail.medallion:SetFrameLevel(coverHolder:GetFrameLevel() + 4)

-- Detail page banner: medallion, then name, guild and combination stacked to its right.
local showcase = CreateFrame("Frame", nil, coverHolder)
showcase:SetAllPoints()
showcase:SetFrameLevel(coverHolder:GetFrameLevel() + 3)

-- The name is the star of the card: large gold font, outline and drop shadow.
local bannerName = showcase:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bannerName:SetShadowColor(0, 0, 0, 1)
bannerName:SetShadowOffset(2, -2)
bannerName:SetWidth(BANNER_TEXT_W)
bannerName:SetJustifyH("LEFT")
bannerName:SetWordWrap(false)
local bannerGuild = text(showcase, "GameFontHighlight", 0.45, 1, 0.45)
bannerGuild:SetPoint("BOTTOMLEFT", BANNER_TEXT_X, 83)
bannerGuild:SetWidth(BANNER_TEXT_W)
bannerGuild:SetWordWrap(false)
local bannerIcon = showcase:CreateTexture(nil, "OVERLAY")
bannerIcon:SetSize(18, 18)
local bannerClass = showcase:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bannerClass:SetPoint("LEFT", bannerIcon, "RIGHT", 5, 0)

local bannerBadge = showcase:CreateTexture(nil, "ARTWORK")
bannerBadge:SetPoint("TOPRIGHT", -8, -8)
bannerBadge:SetColorTexture(0, 0, 0, 0.6)
local bannerNumber = text(showcase, "GameFontNormalSmall", 0.9, 0.8, 0.6)
bannerNumber:SetPoint("TOPRIGHT", -14, -13)
bannerNumber:SetJustifyH("RIGHT")
local bannerStatus = text(showcase, "GameFontHighlightSmall")
bannerStatus:SetPoint("TOPRIGHT", bannerNumber, "BOTTOMRIGHT", 0, -3)
bannerStatus:SetJustifyH("RIGHT")
local bannerStar = favoriteStar(showcase, 24)
bannerStar:SetPoint("TOPRIGHT", bannerBadge, "TOPLEFT", -4, -2)

local function paintShowcase(entry)
    local slot, combination = detail.slot, detail.combination
    local guild = entry and entry.guild
    fitText(bannerName, entry and entry.name or "???", 30, 16, BANNER_TEXT_W)
    if entry then bannerName:SetTextColor(1, 0.82, 0) else bannerName:SetTextColor(0.6, 0.6, 0.6) end
    bannerGuild:SetShown(guild ~= nil)
    if guild then fitText(bannerGuild, "<" .. guild .. ">", 16, 10, BANNER_TEXT_W) end
    -- The stack stays vertically centered, with or without a guild.
    bannerName:ClearAllPoints()
    bannerName:SetPoint("BOTTOMLEFT", BANNER_TEXT_X, guild and 104 or 93)
    bannerIcon:ClearAllPoints()
    bannerIcon:SetPoint("BOTTOMLEFT", BANNER_TEXT_X, guild and 57 or 67)

    bannerNumber:SetText((slot.sex and "" or L.BONUS_BADGE) .. L.CARD_NUMBER:format(slot.index))
    if entry then
        bannerStatus:SetText(entry.level and L.LEVEL_SHORT:format(entry.level) or "")
        bannerStatus:SetTextColor(1, 0.9, 0.65)
    else
        bannerStatus:SetText(L.UNDISCOVERED)
        bannerStatus:SetTextColor(0.7, 0.7, 0.7)
    end
    bannerBadge:SetSize(math.max(bannerNumber:GetStringWidth(), bannerStatus:GetStringWidth()) + 12,
        (entry and not entry.level) and 20 or 34)

    Art.ClassIcon(bannerIcon, combination and combination.token)
    bannerIcon:SetDesaturated(not entry)
    bannerClass:SetText(detail.description)
    paintStar(bannerStar, entry)
    local color = combination and RAID_CLASS_COLORS[combination.token]
    if entry and color then
        bannerClass:SetTextColor(color.r, color.g, color.b)
    else
        bannerClass:SetTextColor(0.7, 0.7, 0.7)
    end
end

local titleFont = fontObject("QuestTitleFont", "GameFontNormalHuge")
local bodyFont = fontObject("QuestFont", "GameFontHighlight")

local function inkText(font, r, g, b)
    local line = text(detail, font, r or INK[1], g or INK[2], b or INK[3])
    line:SetShadowColor(0, 0, 0, 0)
    return line
end

-- Underlined column title, below the banner; returns the title and its rule.
local function columnHeader(x, width)
    local title = inkText(titleFont)
    title:SetPoint("TOPLEFT", coverHolder, "BOTTOMLEFT", x, -16)
    local line = detail:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(INK[1], INK[2], INK[3], 0.35)
    line:SetSize(width, 1)
    line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    return title, line
end

-- Left column: capture information, one per line.
local captureTitle, captureRule = columnHeader(6, 310)
local factRows = {}
for i = 1, 4 do
    local label = inkText("GameFontNormalSmall", 0.45, 0.3, 0.12)
    label:SetPoint("TOPLEFT", captureRule, "BOTTOMLEFT", 0, -14 - (i - 1) * 34)
    local value = inkText(bodyFont)
    value:SetPoint("LEFT", label, "LEFT", 90, 0)
    value:SetWidth(220)
    value:SetWordWrap(false)
    factRows[i] = { label = label, value = value }
end
detail.body = inkText(bodyFont)
detail.body:SetPoint("TOPLEFT", captureRule, "BOTTOMLEFT", 0, -14)
detail.body:SetWidth(310)
detail.body:SetJustifyV("TOP")
detail.body:SetSpacing(4)

-- Right column: race, class and journal progress.
local collectionTitle, collectionRule = columnHeader(350, 310)
collectionTitle:SetText(L.DETAIL_COLLECTION)
local progressRows = {}
for i = 1, 3 do
    local label = inkText(bodyFont)
    label:SetPoint("TOPLEFT", collectionRule, "BOTTOMLEFT", 0, -14 - (i - 1) * 50)
    local bar = Art.ProgressBar(detail, 300, 12, true)
    bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -8)
    progressRows[i] = { label = label, bar = bar }
end

local back = button(detail, L.BACK, 110, function()
    detailKey = nil
    Art.Sound("IG_SPELLBOOK_CLOSE")
    refresh()
end)
back:SetPoint("BOTTOMLEFT", 16, 12)

-- Deletion, with confirmation: the card goes back to "to discover".
local remove = button(detail, L.DELETE_CARD, 150, function()
    local entry = detail.entry
    if not entry or not detail.slot then return end
    StaticPopup_Show("FOREVERDEX_DELETE", entry.name, nil, detail.slot.key)
end)
remove:SetPoint("BOTTOMRIGHT", -16, 12)
remove:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.DELETE_CARD)
    GameTooltip:AddLine(L.DELETE_TOOLTIP, 1, 1, 1, true)
    GameTooltip:Show()
end)
remove:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function showDetail(slot, perRace, filled)
    local entries = ForeverDexDB.cards
    local entry = entries[slot.key]
    if slot.key == pendingReveal then entry = nil end
    local combination, description = Catalog.Describe(slot, entry)
    detail.slot, detail.entry, detail.combination, detail.description = slot, entry, combination, description
    remove:SetShown(entry ~= nil)
    paintPlate(detail.plate, combination, entry)

    local facts = {}
    if entry then
        if entry.capturedAt then facts[#facts + 1] = { L.CAPTURED_ON, date(L.DATE_FORMAT, entry.capturedAt) } end
        if entry.zone then facts[#facts + 1] = { L.CAPTURED_IN, entry.zone } end
        if entry.level then facts[#facts + 1] = { L.LEVEL, tostring(entry.level) } end
        if entry.guild then facts[#facts + 1] = { L.GUILD, "<" .. entry.guild .. ">" } end
    end
    captureTitle:SetText(entry and L.DETAIL_CAPTURE or L.UNDISCOVERED_TOOLTIP)
    for i, row in ipairs(factRows) do
        local fact = facts[i]
        row.label:SetShown(fact ~= nil)
        row.value:SetShown(fact ~= nil)
        if fact then
            row.label:SetText(fact[1])
            row.value:SetText(fact[2])
        end
    end
    detail.body:SetShown(#facts == 0)
    if not entry then
        detail.body:SetText(slot.sex and L.EMPTY_HINT:format(description) or L.BONUS_HINT)
    elseif #facts == 0 then
        detail.body:SetText(L.NO_DETAILS)
    end

    local progress = {}
    if combination then
        for _, info in ipairs(Catalog.races) do
            if info.id == combination.raceID then
                progress[#progress + 1] = { info.name, perRace[info.id] or 0, info.total }
            end
        end
        local have, total = Catalog.ClassProgress(entries, combination.token)
        progress[#progress + 1] = { combination.class, have, total }
    end
    progress[#progress + 1] = { L.HOME, filled, #Catalog.slots }
    for i, row in ipairs(progressRows) do
        local item = progress[i]
        row.label:SetShown(item ~= nil)
        row.bar:SetShown(item ~= nil)
        if item then
            row.label:SetText(L.RACE_PROGRESS:format(item[1], item[2], item[3]))
            row.bar:SetMinMaxValues(0, item[3])
            row.bar:SetValue(item[2])
        end
    end
end

-- Tabs ----------------------------------------------------------------------------

local tabNames = { L.TAB_ALL, L.TAB_FILLED, L.TAB_EMPTY, L.TAB_BONUS, L.TAB_FAVORITES }
local tabs, nativeTabs = {}, true
for i, name in ipairs(tabNames) do
    local tab, native = create("Button", "ForeverDexWindowTab" .. i, panel, "PanelTabButtonTemplate", "UIPanelButtonTemplate")
    nativeTabs = nativeTabs and native
    tab:SetID(i)
    tab:SetText(name)
    if not native then tab:SetSize(110, 22) end
    if i == 1 then
        tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 12, 2)
    else
        -- Modern tabs nearly touch; old ones overlap.
        tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", (not native or tab.LeftActive) and 3 or -15, 0)
    end
    tab:SetScript("OnClick", function(self)
        viewMode, page, detailKey = self:GetID(), 1, nil
        Art.Sound("IG_CHARACTER_INFO_TAB")
        refresh()
        updateTarget()
    end)
    tabs[i] = tab
end
panel.Tabs = tabs
if nativeTabs and PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(panel, #tabs) end

-- Rendering --------------------------------------------------------------------------------

local function updatePortraits(target)
    if not panel:IsShown() then return end
    for _, card in ipairs(cards) do
        if card:IsShown() and card.row then
            local entry = card.row.entry
            if card.row.slot.key == pendingReveal then entry = nil end
            local live = target and entry and entry.id == target.id and SetPortraitTexture ~= nil
            paintMedallion(card.medallion, card.row.details, entry, live)
            card.targeted:SetShown(live and true or false)
        end
    end
    if detail:IsShown() and detail.slot then
        local entry = detail.entry
        local live = target and entry and entry.id == target.id and SetPortraitTexture ~= nil
        paintMedallion(detail.medallion, detail.combination, entry, live)
        paintShowcase(entry)
    end
end

refresh = function()
    if not ForeverDexDB then return end
    local entries = ForeverDexDB.cards
    local view = ForeverDexDB.view
    if view then view.sort, view.tab = sortMode, viewMode end
    updateFilterPanel()
    local rows, filled = Catalog.Query(entries, search:GetText(), viewMode, sortMode, filters)
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    local total = #Catalog.slots
    Art.FitLine(counts, L.PROGRESS:format(filled, total, filled == total and L.COMPLETE or ""), 225)
    percent:SetText(L.PERCENT:format(math.floor(filled / total * 100 + 0.5)))
    progress:SetValue(filled)

    local perRace = Catalog.RaceProgress(entries)
    local raceName
    for _, row in ipairs(raceButtons) do
        local id = row.filter.id
        local have = id and (perRace[id] or 0) or filled
        local all = id and row.filter.total or total
        local selected
        if id then selected = filters.races[id] == true else selected = next(filters.races) == nil end
        row.count:SetText(have .. "/" .. all)
        Art.FitLine(row.name, row.filter.name, 96, true)
        row.bar:SetMinMaxValues(0, all)
        row.bar:SetValue(have)
        row.selected:SetShown(selected)
        if selected then
            row.name:SetTextColor(1, 1, 1)
            raceName = id and row.filter.name
        else
            row.name:SetTextColor(1, 0.82, 0)
        end
    end

    -- The breadcrumb names the race only when a single one is checked.
    local firstRace = next(filters.races)
    if not firstRace or next(filters.races, firstRace) then raceName = nil end

    if nativeTabs and PanelTemplates_SetTab then
        PanelTemplates_SetTab(panel, viewMode)
    else
        for i, tab in ipairs(tabs) do tab:SetEnabled(i ~= viewMode) end
    end

    local detailSlot = detailKey and Catalog.slotByKey[detailKey]
    grid:SetShown(not detailSlot)
    pager:SetShown(not detailSlot)
    detail:SetShown(detailSlot ~= nil)
    empty:SetText(viewMode == 5 and search:GetText() == "" and L.NO_FAVORITES or L.NO_RESULTS)
    empty:SetShown(#rows == 0 and not detailSlot)
    pageText:SetText(L.PAGE:format(page, pages))
    results:SetText(L.RESULTS:format(#rows))
    previous:SetEnabled(page > 1)
    nextPage:SetEnabled(page < pages)

    for i, card in ipairs(cards) do
        local row = rows[(page - 1) * PAGE_SIZE + i]
        card:SetShown(row ~= nil)
        if row then paintCard(card, row) else card.row = nil end
    end

    local home = function() clearFilters(); detailKey, page = nil, 1; refresh() end
    local section = raceName or tabNames[viewMode]
    if detailSlot then
        showDetail(detailSlot, perRace, filled)
        setCrumbs({ { L.HOME, home }, { section, function() detailKey = nil; refresh() end },
            { detail.entry and detail.entry.name or "???" } })
    else
        setCrumbs({ { L.HOME, (activeFilters() > 0 or viewMode ~= 1) and home or nil }, { section } })
    end
    updatePortraits(Collection.ReadTarget())
end

local function isSortSelected(mode)
    return sortMode == mode
end

local function selectSort(mode)
    sortMode, page = mode, 1
    refresh()
end

-- The radio options of the Blizzard menu represent a single active sort.
sortButton:SetupMenu(function(_, menu)
    for mode, name in ipairs(sortNames) do
        menu:CreateRadio(name, isSortSelected, selectSort, mode)
    end
end)
search:HookScript("OnTextChanged", function(self)
    if not nativeSearch then placeholder:SetShown(self:GetText() == "") end
    page, detailKey = 1, nil
    refresh()
end)
panel:HookScript("OnShow", function()
    Art.Sound("IG_SPELLBOOK_OPEN")
    refresh()
end)
panel:HookScript("OnHide", function() Art.Sound("IG_SPELLBOOK_CLOSE") end)

-- Capture from the target portrait -------------------------------------------------

local capturePortrait

-- Target frame of another interface (EllesmereUI, oUF layouts…): the frame showing
-- the "target" unit whose parent is on screen. Blizzard's frame is skipped, and so
-- are frames left under a hidden parent. The result is kept until it stops matching;
-- a failed search is only tried again after a short delay.
local otherTarget, lastSearch
local function showsTarget(frame)
    if frame == TargetFrame or (frame.IsForbidden and frame:IsForbidden()) then return false end
    local unit = frame.unit
    if unit ~= "target" and frame.GetAttribute then unit = frame:GetAttribute("unit") end
    local parent = frame:GetParent()
    return unit == "target" and parent ~= nil and parent:IsVisible() and frame:GetWidth() > 40
end

local function findOtherTarget()
    if otherTarget and showsTarget(otherTarget) then return otherTarget end
    otherTarget = nil
    local now = GetTime()
    if lastSearch and now - lastSearch < 2 then return end
    lastSearch = now
    local best, bestArea = nil, 0
    local frame = EnumerateFrames()
    while frame do
        if showsTarget(frame) then
            local area = frame:GetWidth() * frame:GetHeight()
            if area > bestArea then best, bestArea = frame, area end
        end
        frame = EnumerateFrames(frame)
    end
    otherTarget = best
    return best
end

-- Displayed target frame and region where the ball sits. ElvUI creates its own after
-- the addon loads and reparents Blizzard's to a hidden parent, so the choice is
-- made again on every update. Without an ElvUI portrait, we aim at the whole frame.
local function targetAnchor()
    local elvFrame, blizzard = _G.ElvUF_Target, TargetFrame
    if elvFrame and not (blizzard and blizzard:GetParent() == UIParent) then
        local portrait = elvFrame.Portrait
        return elvFrame, portrait and portrait:IsShown() and portrait or elvFrame
    end
    -- Blizzard's frame is hidden while there is a target: another interface replaced it.
    local replaced = not blizzard or blizzard:GetParent() ~= UIParent
        or (UnitExists("target") and not blizzard:IsShown())
    local other = replaced and findOtherTarget()
    if other then
        local portrait = other.Portrait
        return other, portrait and portrait.IsShown and portrait:IsShown() and portrait or other
    end
    if not blizzard then return end
    local container = blizzard.TargetFrameContainer
    -- Forever uses the modern container. Some frames still expose the old portrait.
    local portrait = (container and container.Portrait) or TargetFramePortrait
    if portrait then return blizzard, portrait end
end

local function createPortraitCapture()
    local badge = CreateFrame("Button", nil, UIParent)
    badge:SetSize(22, 22)
    badge:SetScript("OnClick", Collection.Capture)
    badge:Hide()
    local badgeBall = ns.CaptureVisuals.DrawBadge(badge)
    -- Gray checked ball: the combination is already taken, a click would replace it.
    local badgeCheck = badge:CreateTexture(nil, "OVERLAY")
    badgeCheck:SetSize(14, 14)
    badgeCheck:SetPoint("BOTTOMRIGHT", 4, -3)
    badgeCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    badgeCheck:Hide()
    -- The ball breathes gently to signal a name to capture.
    local pulse = badge:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local grow = pulse:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(1.15, 1.15)
    else
        grow:SetScale(1.15, 1.15)
    end
    grow:SetDuration(0.6)
    grow:SetSmoothing("IN_OUT")
    -- Only a card still to discover makes the ball breathe.
    function badge:SetHolder(holder)
        self.holder = holder
        badgeBall:SetDesaturated(holder ~= nil)
        badgeCheck:SetShown(holder ~= nil)
        if holder then
            pulse:Stop()
        elseif self:IsShown() and not pulse:IsPlaying() then
            pulse:Play()
        end
    end
    badge:SetScript("OnShow", function(self)
        if not self.holder then pulse:Play() end
    end)
    badge:SetScript("OnHide", function() pulse:Stop() end)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("ForeverDex")
        if self.holder then
            GameTooltip:AddLine(L.COMBINATION_OWNED:format(self.holder.name), 1, 1, 1)
            GameTooltip:AddLine(L.CLICK_TO_REPLACE, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L.ADD_TARGET, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Small checked orb: this player is already in the collection. It is gray
    -- when another player holds the card for this combination.
    local owned = CreateFrame("Frame", nil, UIParent)
    owned:SetSize(18, 18)
    owned:EnableMouse(true)
    owned:Hide()
    local orb = owned:CreateTexture(nil, "ARTWORK")
    orb:SetAllPoints()
    Art.SmoothTexture(orb, ns.CaptureVisuals.BALL)
    local check = owned:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("BOTTOMRIGHT", 5, -4)
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    function owned:SetHolder(holder)
        self.holder = holder
        orb:SetDesaturated(holder ~= nil)
    end
    owned:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("ForeverDex")
        GameTooltip:AddLine(self.holder and L.COMBINATION_OWNED:format(self.holder.name) or L.ALREADY_ADDED, 1, 1, 1)
        GameTooltip:Show()
    end)
    owned:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return badge, owned
end

local capture, owned = createPortraitCapture()
capture:Hide()
owned:Hide()

-- Attaches the ball and orb to the current target frame; returns false if there is none.
local attachedHost, attachedRegion
local function attachCapture()
    local host, region = targetAnchor()
    capturePortrait = region
    if not host then return false end
    if host == attachedHost and region == attachedRegion then return true end
    attachedHost, attachedRegion = host, region
    for _, marker in ipairs({ capture, owned }) do
        marker:SetParent(host)
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", region, "TOPRIGHT", -6, -6)
        -- Wide margin: ElvUI puts its text on raised layers.
        marker:SetFrameLevel(host:GetFrameLevel() + 120)
    end
    return true
end

updateTarget = function()
    local anchored = attachCapture()
    local entry = Collection.ReadTarget()
    updatePortraits(entry)
    local current = entry and ForeverDexDB.cards[entry.key]
    local alreadySaved = current and current.id == entry.id
    -- The card for this combination is held by another player.
    local holder = current and not alreadySaved and current or nil
    local showCapture = false
    if capture then
        -- Setting: always (new card or replacement), empty card only, or never.
        local mode = ns.Settings.Get("portraitButton")
        showCapture = anchored and entry ~= nil and not alreadySaved
        if mode == "missing" then showCapture = anchored and entry ~= nil and current == nil end
        if mode == "off" then showCapture = false end
        capture:SetHolder(holder)
        capture:SetShown(showCapture)
    end
    if owned then
        -- Without a clickable ball, the orb still shows that the combination is taken.
        owned:SetHolder(holder)
        owned:SetShown(anchored and current ~= nil and not showCapture and ns.Settings.Get("ownedMarker") or false)
    end
    compare:SetEnabled(ns.Duel ~= nil and ns.Duel.CanRequest())
    if viewMode == 4 then
        local slot, label
        if entry then slot, label = Collection.FindBonusSlot(entry) end
        panelCapture:SetEnabled(slot ~= nil)
        panelCapture:SetText(label or L.ADD_BONUS)
    else
        panelCapture:SetEnabled(entry ~= nil and not alreadySaved)
        panelCapture:SetText(alreadySaved and L.ALREADY_ADDED or L.ADD_TARGET)
    end
end

panel:HookScript("OnShow", updateTarget)

ns.Settings.OnChange(function(key)
    if key == nil or key == "windowScale" then panel:SetScale(ns.Settings.Get("windowScale")) end
    if key == nil or key == "portraitButton" or key == "ownedMarker" then updateTarget() end
end)
panel:HookScript("OnHide", updateTarget)

local function visibleCard(key)
    for _, card in ipairs(cards) do
        if card:IsVisible() and card.row and card.row.slot.key == key then return card end
    end
end

-- Sort, tab and filters are kept between sessions. The saved filter sets are the
-- live tables: they are only ever changed in place, so the checkboxes stay bound.
local function restoreView()
    local view = ForeverDexDB.view or {}
    ForeverDexDB.view = view
    if sortNames[view.sort] then sortMode = view.sort end
    if tabNames[view.tab] then viewMode = view.tab end
    for name, set in pairs(filters) do
        local saved = view[name]
        if saved then
            for _, check in ipairs(filterChecks) do
                if check.set == set and saved[check.value] then set[check.value] = true end
            end
        end
        view[name] = set
    end
    sortButton:SetDefaultText(sortNames[sortMode])
    if sortButton.GenerateMenu then sortButton:GenerateMenu() end
end

ns.UI = {
    RestoreView = restoreView,
    Refresh = function(entry, isNew, noThrow)
        local Visuals = ns.CaptureVisuals
        -- The starting point is read before the refresh, which hides the ball.
        local origin = not noThrow and ((capture and capture:IsVisible() and capture) or (panelCapture:IsVisible() and panelCapture))
        local x1, y1 = Visuals.Center(origin)
        -- A frame attached to a secure frame (ElvUI) can hide its position:
        -- the ball then starts from the cursor, which has just clicked on it.
        if origin and not x1 then
            local cursorX, cursorY = GetCursorPosition()
            local uiScale = UIParent:GetEffectiveScale()
            x1, y1 = cursorX / uiScale, cursorY / uiScale
        end
        if isNew and x1 then pendingReveal = entry.key end
        refresh()
        updateTarget()
        if not isNew then return end
        local card = visibleCard(entry.key)
        -- The ball lands on the target portrait, at its size. Without a visible
        -- target frame, it falls back onto the card or below the button.
        local landing = (capturePortrait and capturePortrait:IsVisible() and capturePortrait) or card
        local x2, y2, size = Visuals.Center(landing)
        if not x2 then x2, y2, size = Visuals.Center(attachedHost) end
        local home = ns.MinimapButton
        local hx, hy, homeSize = Visuals.Center(home and home:IsVisible() and home)
        Visuals.Play({
            fromX = x1, fromY = y1, toX = x2, toY = y2, size = size,
            homeX = hx, homeY = hy, homeSize = homeSize,
            entry = entry,
            onReveal = function()
                if pendingReveal ~= entry.key then return end
                pendingReveal = nil
                refresh()
                if card and card:IsVisible() and card.row and card.row.slot.key == entry.key then
                    card.flashAnimation:Play()
                end
            end,
            onHome = function()
                if home and home.Flash then home:Flash() end
            end,
        })
    end,
    UpdateTarget = updateTarget,
    Toggle = function() panel:SetShown(not panel:IsShown()) end,
}
end)
