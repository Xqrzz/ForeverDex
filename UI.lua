local _, ns = ...
ns.Module(function()
local L, Catalog, Collection, Art, Settings, Share, Util = ns.L, ns.Catalog, ns.Collection, ns.Art, ns.Settings, ns.Share, ns.Util

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
-- "collection" (the journal) or a page registered with ns.UI.RegisterPage ("home",
-- "achievements"…), switched by the side tabs on the right of the window. Each
-- session opens on the home page; the window then stays where it was left.
local mode = "home"
local filters = { races = {}, classes = {}, sexes = {}, capturers = {} }
-- Raised by every change of the collection (ns.UI.Refresh): what is computed from the
-- cards is kept until it moves, so that turning a page does not query everything again.
local collectionVersion = 0
local refresh, updateTarget

local create = Util.CreateFrame

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
gear:SetScript("OnClick", function() Settings.Open() end)
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

local function filterCheck(set)
    local check = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetHitRectInsets(0, -108, 0, 0)
    check.set = set
    check.label = text(check, "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetWidth(108)
    check.label:SetWordWrap(false)
    check:SetScript("OnClick", function(self)
        self.set[self.value] = self:GetChecked() and true or nil
        page, detailKey = 1, nil
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        refresh()
    end)
    filterChecks[#filterChecks + 1] = check
    return check
end

local function setFilterItem(check, item)
    check.value = item.value
    check.label:SetText(item.name)
    local color = item.color or HIGHLIGHT_FONT_COLOR
    check.label:SetTextColor(color.r, color.g, color.b)
end

local function filterColumn(x, title, items, set)
    local heading = text(filterFrame, "GameFontNormal")
    heading:SetPoint("TOPLEFT", x, -12)
    heading:SetText(title)
    for i, item in ipairs(items) do
        local check = filterCheck(set)
        check:SetPoint("TOPLEFT", x - 2, -32 - (i - 1) * 22)
        setFilterItem(check, item)
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

-- "Captured by" column, under Gender: the account's characters that filled cards.
-- It only appears when there is a choice, and follows the collection as it changes.
local FILTER_HEIGHT, CAPTURER_TOP = 296, -108
local capturerHeading = text(filterFrame, "GameFontNormal")
capturerHeading:SetPoint("TOPLEFT", 294, CAPTURER_TOP + 20)
capturerHeading:SetText(L.FILTER_CAPTURER)
local capturerChecks, capturerSignature = {}, nil

local capturersVersion
local function updateCapturers()
    if capturersVersion == collectionVersion then return end
    capturersVersion = collectionVersion
    local UNKNOWN = Catalog.UNKNOWN_CAPTURER
    local names, classes = {}, {}
    for _, entry in pairs(ForeverDexDB.cards) do
        local name = entry.capturedBy or UNKNOWN
        if classes[name] == nil then
            names[#names + 1] = name
            classes[name] = entry.capturedByClass or false
        end
    end
    -- A single capturer leaves nothing to choose.
    if #names < 2 then wipe(names) end
    table.sort(names, function(a, b)
        if (a == UNKNOWN) ~= (b == UNKNOWN) then return b == UNKNOWN end
        return a < b
    end)
    local signature = table.concat(names, "\n")
    if signature == capturerSignature then return end
    capturerSignature = signature
    -- A character that no longer has any card must not keep filtering.
    local listed = {}
    for _, name in ipairs(names) do listed[name] = true end
    for value in pairs(filters.capturers) do
        if not listed[value] then filters.capturers[value] = nil end
    end
    for i, name in ipairs(names) do
        local check = capturerChecks[i]
        if not check then
            check = filterCheck(filters.capturers)
            check:SetPoint("TOPLEFT", 292, CAPTURER_TOP - (i - 1) * 22)
            capturerChecks[i] = check
        end
        setFilterItem(check, {
            value = name,
            name = name == UNKNOWN and L.FILTER_CAPTURER_UNKNOWN or name,
            color = classes[name] and RAID_CLASS_COLORS[classes[name]] or (name == UNKNOWN and GRAY_FONT_COLOR) or nil,
        })
        check:Show()
    end
    for i = #names + 1, #capturerChecks do
        capturerChecks[i].value = nil
        capturerChecks[i]:Hide()
    end
    capturerHeading:SetShown(#names > 0)
    filterFrame:SetHeight(math.max(FILTER_HEIGHT, -CAPTURER_TOP + #names * 22 + 44))
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
    updateCapturers()
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

local sidebar = Art.Inset(panel)
sidebar:SetPoint("TOPLEFT", 8, -72)
sidebar:SetPoint("BOTTOMLEFT", 8, 8)
sidebar:SetWidth(186)

local raceButtons = {}
local raceRows = { { name = L.ALL_RACES, icon = "Interface\\Icons\\INV_Misc_Book_09" } }
for _, race in ipairs(Catalog.races) do raceRows[#raceRows + 1] = race end

for i, filter in ipairs(raceRows) do
    local row = Art.ListRow(sidebar, 172, 38)
    row:SetPoint("TOPLEFT", 7, -7 - (i - 1) * 40)
    row.filter = filter
    if filter.id and Art.HasAtlas(filter.icon) then
        row.icon:SetAtlas(filter.icon)
    else
        row.icon:SetTexture(filter.id and (filter.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark") or filter.icon)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    row.name:SetText(filter.name)
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

local content = Art.Inset(panel)
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
content:SetPoint("BOTTOMRIGHT", -8, 8)
Art.JournalBackground(content)

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

-- "B" for bonus cards, "F"/"P" for pets, nothing for standard cards.
local function badgePrefix(slot)
    if slot.pet then return L.PET_BADGE end
    return slot.sex and "" or L.BONUS_BADGE
end

-- Line under the name: the guild of a player, the owner of a pet.
local function subtitle(entry)
    if not entry then return end
    if entry.owner then return L.PET_OF:format(entry.owner) end
    return entry.guild and ("<" .. entry.guild .. ">")
end

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
    local row = card and card.row
    if not row or not row.entry or row.slot.key == pendingReveal then return end
    local entry, key = row.entry, row.slot.key
    -- The game's menu with the mouse, ForeverDex's own one with the controller.
    ns.PopupMenu.Open(card, function(_, root)
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
        root:CreateButton(L.SHARE_CARD, function()
            Share.Show(entry, row.slot)
        end)
        root:CreateDivider()
        local delete = root:CreateButton(L.DELETE_CARD, function()
            StaticPopup_Show("FOREVERDEX_DELETE", entry.name, nil, key)
        end)
        -- A favorite cannot be deleted: it has to leave the favorites first.
        if entry.favorite then
            delete:SetEnabled(false)
            if delete.SetTooltip then
                delete:SetTooltip(function(tooltip) GameTooltip_SetTitle(tooltip, L.DELETE_FAVORITE) end)
            end
        end
    end)
end

-- The Adventure Guide art has a carved recess whose top edge sits about 50 px down:
-- the grid starts below it.
local grid = CreateFrame("Frame", nil, content)
grid:SetPoint("TOP", 0, -Art.JOURNAL_RECESS)
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
        if subtitle(row.entry) and not hidden then
            GameTooltip:AddLine(subtitle(row.entry), 0.25, 1, 0.25)
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
    card.number:SetText(("%s#%03d"):format(badgePrefix(slot), slot.index))
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
    local guild = subtitle(entry)
    card.guild:SetShown(guild ~= nil)
    if guild then fitText(card.guild, guild, 12, 9) end
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
pager:SetPoint("BOTTOMLEFT", 14, 10)
pager:SetPoint("BOTTOMRIGHT", -14, 10)
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
    local guild = subtitle(entry)
    fitText(bannerName, entry and entry.name or "???", 30, 16, BANNER_TEXT_W)
    if entry then bannerName:SetTextColor(1, 0.82, 0) else bannerName:SetTextColor(0.6, 0.6, 0.6) end
    bannerGuild:SetShown(guild ~= nil)
    if guild then fitText(bannerGuild, guild, 16, 10, BANNER_TEXT_W) end
    -- The stack stays vertically centered, with or without a guild.
    bannerName:ClearAllPoints()
    bannerName:SetPoint("BOTTOMLEFT", BANNER_TEXT_X, guild and 104 or 93)
    bannerIcon:ClearAllPoints()
    bannerIcon:SetPoint("BOTTOMLEFT", BANNER_TEXT_X, guild and 57 or 67)

    bannerNumber:SetText(badgePrefix(slot) .. L.CARD_NUMBER:format(slot.index))
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
for i = 1, 5 do
    local label = inkText("GameFontNormalSmall", 0.45, 0.3, 0.12)
    label:SetPoint("TOPLEFT", captureRule, "BOTTOMLEFT", 0, -14 - (i - 1) * 30)
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
-- A favorite is protected: the tooltip still explains why the button is off.
remove:SetMotionScriptsWhileDisabled(true)
remove:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.DELETE_CARD)
    local favorite = detail.entry and detail.entry.favorite
    GameTooltip:AddLine(favorite and L.DELETE_FAVORITE or L.DELETE_TOOLTIP, 1, 1, 1, true)
    GameTooltip:Show()
end)
remove:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Sharing in the channel chosen for captures (Options → Announcements).
local share = button(detail, L.SHARE_CARD, 110, function()
    Share.Show(detail.entry, detail.slot)
end)
share:SetPoint("RIGHT", remove, "LEFT", -8, 0)
share:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.SHARE_CARD)
    GameTooltip:AddLine(L.SHARE_CARD_TIP, 1, 1, 1, true)
    GameTooltip:Show()
end)
share:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function showDetail(slot, perRace, filled)
    local entries = ForeverDexDB.cards
    local entry = entries[slot.key]
    if slot.key == pendingReveal then entry = nil end
    local combination, description = Catalog.Describe(slot, entry)
    detail.slot, detail.entry, detail.combination, detail.description = slot, entry, combination, description
    remove:SetShown(entry ~= nil)
    remove:SetEnabled(not (entry and entry.favorite))
    share:SetShown(entry ~= nil)
    paintPlate(detail.plate, combination, entry)

    local facts = {}
    if entry then
        if entry.owner then facts[#facts + 1] = { L.PET_OWNER, entry.owner } end
        if entry.capturedAt then facts[#facts + 1] = { L.CAPTURED_ON, date(L.DATE_FORMAT, entry.capturedAt) } end
        if entry.capturedBy then facts[#facts + 1] = { L.CAPTURED_BY, entry.capturedBy } end
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
        detail.body:SetText(slot.pet and L.PET_HINT or slot.sex and L.EMPTY_HINT:format(description) or L.BONUS_HINT)
    elseif #facts == 0 then
        detail.body:SetText(L.NO_DETAILS)
    end

    local bars = {}
    if slot.pet then
        bars[1] = { L.PETS, Catalog.Filled(entries, Catalog.petSlots), #Catalog.petSlots }
    elseif combination then
        for _, info in ipairs(Catalog.races) do
            if info.id == combination.raceID then
                bars[#bars + 1] = { info.name, perRace[info.id] or 0, info.total }
            end
        end
        local have, total = Catalog.ClassProgress(entries, combination.token)
        bars[#bars + 1] = { combination.class, have, total }
    end
    if not slot.pet then bars[#bars + 1] = { L.HOME, filled, #Catalog.slots } end
    for i, row in ipairs(progressRows) do
        local item = bars[i]
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

local tabNames = { L.TAB_ALL, L.TAB_FILLED, L.TAB_EMPTY, L.TAB_BONUS, L.TAB_FAVORITES, L.TAB_PETS }
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
        mode, viewMode, page, detailKey = "collection", self:GetID(), 1, nil
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

-- Pages and side tabs ----------------------------------------------------------------

-- Pages shown in place of the journal, by mode. A page is a table with
-- SetShown(shown): it shows or hides its frames, and refreshes them when shown.
local pages = {}

local function registerPage(name, handler)
    pages[name] = handler
    handler.SetShown(false)
end

-- Side tabs, on the right edge of the window: one per mode.
local sideTabs = {}

local function paintSideTab(tab)
    local active = mode == tab.mode
    tab.glow:SetShown(active)
    tab.icon:SetDesaturated(not active)
    tab.icon:SetAlpha(active and 1 or 0.8)
    tab:SetBackdropBorderColor(active and 1 or 0.6, active and 0.85 or 0.55, active and 0.4 or 0.45)
end

-- index: position from the top. paint(icon) sets the icon texture.
local function addSideTab(index, tabMode, label, paint)
    local tab = CreateFrame("Button", nil, panel, "BackdropTemplate")
    tab:SetSize(46, 46)
    tab:SetPoint("TOPLEFT", panel, "TOPRIGHT", -2, -72 - (index - 1) * 54)
    tab:SetFrameLevel(panel:GetFrameLevel() + 20)
    tab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    tab:SetBackdropColor(0.08, 0.06, 0.04, 0.95)
    tab.mode = tabMode
    tab.index = index
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("TOPLEFT", 7, -7)
    tab.icon:SetPoint("BOTTOMRIGHT", -7, 7)
    paint(tab.icon)
    -- Gold light around the active tab, as on the game's side tabs.
    tab.glow = tab:CreateTexture(nil, "OVERLAY")
    tab.glow:SetPoint("TOPLEFT", 4, -4)
    tab.glow:SetPoint("BOTTOMRIGHT", -4, 4)
    tab.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    tab.glow:SetBlendMode("ADD")
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = tab:GetHighlightTexture()
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", 4, -4)
    highlight:SetPoint("BOTTOMRIGHT", -4, 4)
    tab:SetScript("OnClick", function(self)
        Art.Sound("IG_CHARACTER_INFO_TAB")
        mode, detailKey = self.mode, nil
        refresh()
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sideTabs[#sideTabs + 1] = tab
    paintSideTab(tab)
    return tab
end

addSideTab(2, "collection", L.DETAIL_COLLECTION, function(icon)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end)

-- Parts of the window that belong to the journal: hidden while a page replaces it.
local journalParts = { sidebar, content, counts, percent, progress, panelCapture, sortButton, filterButton, search }

-- Returns true when a page took the place of the journal.
local function showMode()
    -- A page missing from this build falls back to the journal.
    if mode ~= "collection" and not pages[mode] then mode = "collection" end
    local journal = mode == "collection"
    for _, part in ipairs(journalParts) do part:SetShown(journal) end
    -- The bottom tabs only sort the journal: the other pages hide them.
    for _, tab in ipairs(tabs) do tab:SetShown(journal) end
    if not journal then filterFrame:Hide() end
    -- Hide first, then show: two pages never overlap, even for a moment.
    for name, handler in pairs(pages) do
        if name ~= mode then handler.SetShown(false) end
    end
    if pages[mode] then pages[mode].SetShown(true) end
    for _, tab in ipairs(sideTabs) do paintSideTab(tab) end
    return not journal
end

-- Checked filters as text, to tell whether the query must run again.
local function filterSignature()
    local parts = {}
    for name, set in pairs(filters) do
        for value, on in pairs(set) do
            if on then parts[#parts + 1] = name .. "=" .. tostring(value) end
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Last query and what it was made from: a new page, a card opened or closed, or the
-- reveal of a capture reuse it.
local lastQuery = {}
-- Target (player or pet) last read by updateTarget, which runs on every change of target,
-- of its name or of its portrait. Reading a pet scans its tooltip: the refresh reuses it.
local lastTarget

refresh = function()
    if not ForeverDexDB then return end
    if showMode() then
        ns.Gamepad.Refresh()
        return
    end
    local entries = ForeverDexDB.cards
    local view = ForeverDexDB.view
    if view then view.sort, view.tab = sortMode, viewMode end
    updateFilterPanel()
    local key = table.concat({ collectionVersion, search:GetText(), viewMode, sortMode, filterSignature() }, "|")
    if lastQuery.key ~= key or lastQuery.entries ~= entries then
        lastQuery.key, lastQuery.entries = key, entries
        lastQuery.rows, lastQuery.filled = Catalog.Query(entries, search:GetText(), viewMode, sortMode, filters)
        lastQuery.perRace = Catalog.RaceProgress(entries)
    end
    local rows, filled = lastQuery.rows, lastQuery.filled
    local pageCount = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(page, pageCount))
    local total = #Catalog.slots
    Art.FitLine(counts, L.PROGRESS:format(filled, total, filled == total and L.COMPLETE or ""), 225)
    percent:SetText(L.PERCENT:format(math.floor(filled / total * 100 + 0.5)))
    progress:SetValue(filled)

    local perRace = lastQuery.perRace
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
    pageText:SetText(L.PAGE:format(page, pageCount))
    results:SetText(L.RESULTS:format(#rows))
    previous:SetEnabled(page > 1)
    nextPage:SetEnabled(page < pageCount)

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
    updatePortraits(lastTarget)
    ns.Gamepad.Refresh()
end

local function isSortSelected(choice)
    return sortMode == choice
end

local function selectSort(choice)
    sortMode, page = choice, 1
    refresh()
end

-- The radio options of the Blizzard menu represent a single active sort.
local function sortMenu(_, menu)
    for choice, name in ipairs(sortNames) do
        menu:CreateRadio(name, isSortSelected, selectSort, choice)
    end
end
sortButton:SetupMenu(sortMenu)
-- With the controller, ForeverDex's own menu replaces the game's (PopupMenu.lua).
ns.PopupMenu.AttachDropdown(sortButton, sortMenu, function()
    sortButton:SetDefaultText(sortNames[sortMode])
    if sortButton.GenerateMenu then sortButton:GenerateMenu() end
end)
-- The query waits for a short pause in the typing; text set by the code (cleared
-- filters) is applied at once.
local searchTimer
search:HookScript("OnTextChanged", function(self, userInput)
    if not nativeSearch then placeholder:SetShown(self:GetText() == "") end
    page, detailKey = 1, nil
    if searchTimer then searchTimer:Cancel() end
    searchTimer = nil
    if not userInput or not C_Timer.NewTimer then
        refresh()
        return
    end
    searchTimer = C_Timer.NewTimer(0.15, function()
        searchTimer = nil
        refresh()
    end)
end)
panel:HookScript("OnShow", function()
    Art.Sound("IG_SPELLBOOK_OPEN")
    refresh()
end)
panel:HookScript("OnHide", function() Art.Sound("IG_SPELLBOOK_CLOSE") end)

-- Capture from the target portrait (PortraitCapture.lua) ------------------------------

local PortraitCapture = ns.PortraitCapture
-- Pages that follow the target too (the Guilds page and its capture button).
local targetListeners = {}

updateTarget = function()
    local anchored = PortraitCapture.Attach()
    local entry = Collection.ReadTarget()
    -- A hunter pet has no fixed card: only a pet already in the collection counts as saved.
    local pet = not entry and Collection.ReadPet() or nil
    lastTarget = entry or pet
    updatePortraits(lastTarget)
    local current = entry and ForeverDexDB.cards[entry.key]
    local alreadySaved = current and current.id == entry.id
    if pet then
        local _, existing = Collection.FindPetSlot(pet)
        current = existing and ForeverDexDB.cards[existing.key]
        alreadySaved = current ~= nil
    end
    -- The card for this combination is held by another player.
    local holder = current and not alreadySaved and current or nil
    local guild, guildOwned
    if entry and ns.Guilds then guild, guildOwned = ns.Guilds.TargetState() end
    PortraitCapture.Update(anchored, entry or pet, current, alreadySaved, holder, guild, guildOwned)
    for _, listener in ipairs(targetListeners) do listener(guild, guildOwned) end
    compare:SetEnabled(ns.Duel ~= nil and ns.Duel.CanRequest())
    if viewMode == 4 then
        local slot, label
        if entry then slot, label = Collection.FindBonusSlot(entry) end
        panelCapture:SetEnabled(slot ~= nil)
        panelCapture:SetText(label or L.ADD_BONUS)
    else
        panelCapture:SetEnabled((entry or pet) ~= nil and not alreadySaved)
        panelCapture:SetText(alreadySaved and L.ALREADY_ADDED or L.ADD_TARGET)
    end
end

panel:HookScript("OnShow", updateTarget)

Settings.OnChange(function(key)
    if key == nil or key == "windowScale" then panel:SetScale(Settings.Get("windowScale")) end
    if key == nil or key == "portraitButton" or key == "ownedMarker" then updateTarget() end
end)
panel:HookScript("OnHide", updateTarget)

-- Combat: the window steps aside as the fight starts and comes back, on the same page,
-- once it is over. Opened and closed again by hand during the fight, it stays closed.
local reopenAfterCombat = false
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if panel:IsShown() then
            reopenAfterCombat = true
            panel:Hide()
        end
    elseif reopenAfterCombat then
        reopenAfterCombat = false
        if not panel:IsShown() then panel:Show() end
    end
end)
-- Opened again by hand during the fight: nothing left to reopen afterwards.
panel:HookScript("OnShow", function() reopenAfterCombat = false end)

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
    -- The capturer boxes depend on the collection: they exist before the saved choices are read.
    updateCapturers()
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

-- Opens the window on a mode, and on a card's detail page in the journal.
local function showWindow(newMode, key)
    mode, detailKey = newMode, key
    if panel:IsShown() then refresh() else panel:Show() end
end

-- Where a throw starts: the clicked marker's center, read before the refresh hides
-- it. A frame attached to a secure frame (ElvUI) can hide its position: the ball
-- then starts from the cursor, which has just clicked on it.
local function throwStart(origin)
    local x1, y1 = ns.CaptureVisuals.Center(origin)
    if origin and not x1 then
        local cursorX, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        x1, y1 = cursorX / uiScale, cursorY / uiScale
    end
    return x1, y1
end

-- The ball lands on the target portrait, at its size. Without a visible target
-- frame, it falls back onto the given frame (a card, a banner) or the target frame.
-- Then it flies home to the minimap icon.
local function throwBall(x1, y1, fallback, options)
    local Visuals = ns.CaptureVisuals
    local region = PortraitCapture.Region()
    local landing = (region and region:IsVisible() and region) or fallback
    local x2, y2, size = Visuals.Center(landing)
    if not x2 then x2, y2, size = Visuals.Center(PortraitCapture.Host()) end
    local home = ns.MinimapButton
    local hx, hy, homeSize = Visuals.Center(home and home:IsVisible() and home)
    options.fromX, options.fromY, options.toX, options.toY, options.size = x1, y1, x2, y2, size
    options.homeX, options.homeY, options.homeSize = hx, hy, homeSize
    options.onHome = function()
        if home and home.Flash then home:Flash() end
    end
    Visuals.Play(options)
end

ns.UI = {
    RestoreView = restoreView,
    Refresh = function(entry, isNew, noThrow)
        -- The starting point is read before the refresh, which hides the ball.
        local origin = not noThrow and ((PortraitCapture.Ball:IsVisible() and PortraitCapture.Ball) or (panelCapture:IsVisible() and panelCapture))
        local x1, y1 = throwStart(origin)
        if isNew and x1 then pendingReveal = entry.key end
        collectionVersion = collectionVersion + 1
        refresh()
        updateTarget()
        if not isNew then return end
        local card = visibleCard(entry.key)
        throwBall(x1, y1, card, {
            entry = entry,
            onReveal = function()
                if pendingReveal ~= entry.key then return end
                pendingReveal = nil
                refresh()
                if card and card:IsVisible() and card.row and card.row.slot.key == entry.key then
                    card.flashAnimation:Play()
                end
            end,
        })
    end,
    -- Guild capture (GuildsUI.lua): the guild ball leaves the portrait ball or orb that
    -- was clicked, else the given fallback button. getLanding() gives the frame to land on when
    -- no target frame is visible; onReveal runs on the "click" of the ball.
    -- Returns false when there is nothing to throw from (no animation).
    ThrowGuild = function(guild, fallback, getLanding, onReveal)
        local ball, orb = PortraitCapture.Ball, PortraitCapture.Orb
        local origin = (ball:IsVisible() and ball:IsMouseOver() and ball) or (orb:IsVisible() and orb:IsMouseOver() and orb)
            or (fallback and fallback:IsVisible() and fallback) or (ball:IsVisible() and ball) or (orb:IsVisible() and orb)
        local x1, y1 = throwStart(origin or nil)
        updateTarget()
        throwBall(x1, y1, getLanding and getLanding(), { guild = guild, onReveal = onReveal })
        return x1 ~= nil
    end,
    OnTargetChanged = function(listener) targetListeners[#targetListeners + 1] = listener end,
    -- Opens the journal searching for a text (a guild name, from the Guilds page).
    ShowSearch = function(query)
        clearFilters()
        search:SetText(query or "")
        showWindow("collection")
    end,
    UpdateTarget = updateTarget,
    Toggle = function() panel:SetShown(not panel:IsShown()) end,
    -- For the pages (HomeUI.lua, AchievementsUI.lua): the window, the area a page
    -- covers, its registration and its side tab.
    Window = panel,
    PageArea = { sidebar, content },
    RegisterPage = registerPage,
    AddSideTab = addSideTab,
    -- Card plates and medallions, as drawn in the journal.
    BuildPlate = buildPlate,
    PaintPlate = paintPlate,
    PaintMedallion = paintMedallion,
    Mode = function() return mode end,
    SetMode = function(newMode)
        mode, detailKey = newMode, nil
        refresh()
    end,
    -- Opens the window on a mode ("home", "collection", "achievements"…).
    Show = showWindow,
    -- Opens the window on the achievements page (achievement alert, /fdex achievements).
    ShowAchievements = function() showWindow("achievements") end,
    -- Opens the detail page of a card in the journal.
    ShowCard = function(key)
        if not Catalog.slotByKey[key] then return end
        showWindow("collection", key)
    end,
}
-- Controller (Gamepad.lua) -------------------------------------------------------------------

-- Side tabs from the top: the shoulders go through them.
local function cycleTabs(step)
    local ordered = {}
    for _, tab in ipairs(sideTabs) do ordered[#ordered + 1] = tab end
    table.sort(ordered, function(a, b) return a.index < b.index end)
    local at = 1
    for i, tab in ipairs(ordered) do
        if tab.mode == mode then at = i end
    end
    local nextTab = ordered[(at - 1 + step) % #ordered + 1]
    if nextTab then nextTab:Click() end
end

ns.Gamepad.Attach(panel, {
    mode = function() return mode end,
    tabs = cycleTabs,
    -- The triggers turn the journal pages (the other pages register their own).
    pages = function(step)
        local handler = pages[mode]
        if handler and handler.TurnPage then
            handler.TurnPage(step)
        elseif mode == "collection" and not detailKey then
            local control = step < 0 and previous or nextPage
            if control:IsEnabled() then control:Click() end
        end
    end,
    close = function() panel:Hide() end,
})

-- Journal: the cards, the race column, the bottom tabs and the header buttons; on a
-- card's page, its buttons. X makes a card a favorite, Y opens its menu.
ns.Gamepad.RegisterPage("collection", function()
    local targets = {}
    -- Filters panel open: its checkboxes and its reset button; B closes it.
    if filterFrame:IsShown() then
        for _, check in ipairs(filterChecks) do
            if check:IsShown() then
                targets[#targets + 1] = { frame = check, A = { check:GetChecked() and L.PAD_UNCHECK or L.PAD_CHECK } }
            end
        end
        targets[#targets + 1] = { frame = filterReset }
        return {
            targets = targets, default = filterChecks[1],
            back = function() filterFrame:Hide() end, backLabel = L.PAD_CLOSE,
        }
    end
    local function favorite(entry)
        return { L.PAD_FAVORITE, function()
            Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            Collection.ToggleFavorite(entry)
        end }
    end
    if detail:IsShown() then
        local entry = detail.entry
        local x = entry and favorite(entry) or nil
        for _, control in ipairs({ back, share, remove }) do
            targets[#targets + 1] = { frame = control, X = x }
        end
        if bannerStar:IsShown() then targets[#targets + 1] = { frame = bannerStar, X = x } end
        return { targets = targets, default = back, back = function() back:Click() end }
    end
    for _, card in ipairs(cards) do
        if card:IsShown() and card.row then
            local entry = card.row.entry
            targets[#targets + 1] = {
                frame = card,
                X = entry and favorite(entry) or nil,
                Y = entry and { L.PAD_OPTIONS, openCardMenu } or nil,
            }
        end
    end
    for _, row in ipairs(raceButtons) do targets[#targets + 1] = { frame = row, A = { L.PAD_SELECT } } end
    for _, tab in ipairs(tabs) do targets[#targets + 1] = { frame = tab, A = { L.PAD_SELECT } } end
    targets[#targets + 1] = { frame = compare }
    targets[#targets + 1] = { frame = panelCapture }
    targets[#targets + 1] = { frame = filterButton }
    targets[#targets + 1] = { frame = sortButton, A = { L.PAD_SORT, function()
        ns.PopupMenu.ShowBelow(sortButton, sortMenu, function()
            sortButton:SetDefaultText(sortNames[sortMode])
            if sortButton.GenerateMenu then sortButton:GenerateMenu() end
        end)
    end } }
    return { targets = targets, default = cards[1] }
end)
end)
