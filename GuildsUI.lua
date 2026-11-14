local _, ns = ...
ns.Module(function()
local L, Art, Guilds = ns.L, ns.Art, ns.Guilds
local GuildsUI = {}
ns.GuildsUI = GuildsUI

-- Guilds page of the main window, reached through its side tab. Each captured guild
-- hangs as a banner in the color of its faction, with its crest and its name. The
-- banners keep the order the player gives them: drag one onto another to move it
-- (hold it over a page arrow to turn the page). The column on the left filters by
-- faction, like the races of the journal.

local UI = ns.UI
local window = UI.Window
local sidebar, content = UI.PageArea[1], UI.PageArea[2]

local COLUMNS, ROWS = 6, 2
local PAGE_SIZE = COLUMNS * ROWS
local CELL_W, CELL_H, GAP_X, GAP_Y = 114, 196, 6, 6
-- Width of the name on the cloth, inside the gold trim.
local NAME_W = 64
local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"
local GOLD = { 1, 0.82, 0.42 }
local ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:14:14|t"
local TABARD = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Time spent over a page arrow, while dragging, before the page turns.
local FLIP_DELAY = 0.6

local FILTERS = {
    { id = "all", name = L.GUILD_ALL },
    { id = "Alliance", name = FACTION_ALLIANCE },
    { id = "Horde", name = FACTION_HORDE },
}

local filter, page = "all", 1
-- Guild being thrown: its banner only appears on the "click" of the ball.
local pendingID
local refresh

local function text(parent, font, r, g, b)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetJustifyH("LEFT")
    if r then line:SetTextColor(r, g, b) end
    return line
end

-- Header: replaces the journal progress at the top of the window ------------------------

local summary = text(window, "GameFontNormal")
summary:SetPoint("TOPLEFT", 70, -31)
local factions = text(window, "GameFontHighlightSmall", 0.85, 0.85, 0.85)
factions:SetPoint("TOPLEFT", 74, -50)

local captureButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
captureButton:SetSize(170, 22)
captureButton:SetPoint("TOPRIGHT", -14, -40)
captureButton:SetText(L.GUILD_CAPTURE)
captureButton:SetScript("OnClick", function() Guilds.Capture() end)
captureButton:SetMotionScriptsWhileDisabled(true)
captureButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L.GUILD_CAPTURE)
    GameTooltip:AddLine(L.GUILD_CAPTURE_TOOLTIP, 1, 1, 1, true)
    GameTooltip:Show()
end)
captureButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

UI.OnTargetChanged(function(guild, owned)
    captureButton:SetEnabled(guild ~= nil and not owned)
    captureButton:SetText(owned and L.GUILD_ALREADY_BUTTON or L.GUILD_CAPTURE)
end)

-- Faction column: same frame and rows as the race column ---------------------------------

local column = Art.Inset(window)
column:SetPoint("TOPLEFT", sidebar, "TOPLEFT")
column:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT")

local filterRows = {}
for i, item in ipairs(FILTERS) do
    local row = Art.ListRow(column, 172, 38)
    row:SetPoint("TOPLEFT", 7, -7 - (i - 1) * 40)
    row.item = item
    if item.id == "all" then
        row.icon:SetTexture(TABARD)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        Guilds.PaintCrest(row.icon, item.id)
    end
    row.name:SetText(item.name)
    row:SetScript("OnClick", function(self)
        filter, page = self.item.id, 1
        if ForeverDexDB and ForeverDexDB.view then ForeverDexDB.view.guildFilter = filter end
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        refresh()
    end)
    filterRows[i] = row
end

local hint = text(column, "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 12, 12)
hint:SetPoint("BOTTOMRIGHT", -12, 12)
hint:SetJustifyH("CENTER")
hint:SetText(L.GUILD_DRAG_HINT)

-- Board: the painted journal background, with a title like the journal breadcrumb ---------

local board = Art.Inset(window)
board:SetPoint("TOPLEFT", content, "TOPLEFT")
board:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
Art.JournalBackground(board)
local title = text(board, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -9)

local grid = CreateFrame("Frame", nil, board)
grid:SetPoint("TOP", 0, -Art.JOURNAL_RECESS + 6)
grid:SetSize(COLUMNS * CELL_W + (COLUMNS - 1) * GAP_X, ROWS * CELL_H + (ROWS - 1) * GAP_Y)

local empty = text(board, "GameFontHighlightLarge", 0.9, 0.85, 0.75)
empty:SetPoint("CENTER", grid, "CENTER")
empty:SetWidth(460)
empty:SetJustifyH("CENTER")

-- Pagination: spellbook arrows and mouse wheel, as in the journal.
local pager = CreateFrame("Frame", nil, board)
pager:SetPoint("BOTTOMLEFT", 14, 10)
pager:SetPoint("BOTTOMRIGHT", -14, 10)
pager:SetHeight(32)
local results = text(pager, "GameFontNormalSmall", 0.85, 0.75, 0.55)
results:SetPoint("LEFT", 8, 0)

local function turnPage(step)
    page = page + step
    Art.Sound("IG_ABILITY_PAGE_TURN")
    refresh()
end

local function pageButton(direction, step)
    local control = CreateFrame("Button", nil, pager)
    control:SetSize(28, 28)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    control:SetNormalTexture(base .. "Up")
    control:SetPushedTexture(base .. "Down")
    control:SetDisabledTexture(base .. "Disabled")
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetScript("OnClick", function() turnPage(step) end)
    control.step = step
    return control
end
local nextPage = pageButton("Next", 1)
nextPage:SetPoint("RIGHT", -4, 0)
local pageText = text(pager, "GameFontHighlightSmall")
pageText:SetPoint("RIGHT", nextPage, "LEFT", -6, 0)
local previous = pageButton("Prev", -1)
previous:SetPoint("RIGHT", pageText, "LEFT", -6, 0)

board:EnableMouseWheel(true)
board:SetScript("OnMouseWheel", function(_, delta)
    if (delta > 0 and previous:IsEnabled()) or (delta < 0 and nextPage:IsEnabled()) then turnPage(-delta) end
end)

-- Banners ------------------------------------------------------------------------------
--
-- The game's own guild banner (the one of the Communities window), lengthened: its
-- cloth in the faction color, its gold border and a guild emblem from the tabard
-- sheet, under the faction coat of arms with its crossed swords. The name is written
-- below. A client without that art gets the addon's hanging banner (cloth, gold trim
-- and rod in Media) with the small faction crest and the name on the cloth.

local SHAPE, BORDER = "communities-guildbanner-background", "communities-guildbanner-border"
local GAME_BANNER = Art.HasAtlas(SHAPE) and Art.HasAtlas(BORDER)
local EMBLEM_SHEET = "Interface\\GuildFrame\\GuildEmblemsLG_01"
local IVORY = { 1, 0.95, 0.82 }
-- Width, length and top of the game banner in a cell.
local BANNER_W, BANNER_H, BANNER_TOP = 86, 134, 32
-- The game banner is a short shield: it is cut in three, as fractions of its height,
-- and its middle strip (straight sides only) is stretched to make it longer, so the
-- top and the point keep their shape.
local CUTS = { 0, 0.3, 0.5, 1 }

-- Size of an atlas fitted in a box, keeping its proportions.
local function fitAtlas(texture, atlas, maxWidth, maxHeight)
    local info = C_Texture.GetAtlasInfo(atlas)
    texture:SetAtlas(atlas)
    local width, height = maxWidth, maxHeight
    if info and info.width and info.height and info.width > 0 and info.height > 0 then
        local scale = math.min(maxWidth / info.width, maxHeight / info.height)
        width, height = info.width * scale, info.height * scale
    end
    texture:SetSize(width, height)
    return width, height
end

-- Natural height of the game banner at its width in a cell.
local function naturalHeight()
    local info = C_Texture.GetAtlasInfo(SHAPE)
    if info and info.width and info.height and info.width > 0 then return BANNER_W * info.height / info.width end
    return BANNER_H
end

-- Draws an atlas of the game banner lengthened, as three textures (or one, stretched,
-- when the client does not give the file behind the atlas). Returns the textures.
local function longBanner(frame, layer, sublevel, atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if not file then
        local texture = frame:CreateTexture(nil, layer, nil, sublevel)
        texture:SetAtlas(atlas)
        texture:SetSize(BANNER_W, BANNER_H)
        texture:SetPoint("TOP", 0, -BANNER_TOP)
        return { texture }
    end
    local natural = naturalHeight()
    local top, bottom = natural * CUTS[2], natural * (1 - CUTS[3])
    local heights = { top, math.max(1, BANNER_H - top - bottom), bottom }
    local left, right, y1, y2 = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local parts, offset = {}, BANNER_TOP
    for i = 1, 3 do
        local texture = frame:CreateTexture(nil, layer, nil, sublevel)
        texture:SetTexture(file)
        texture:SetTexCoord(left, right, y1 + (y2 - y1) * CUTS[i], y1 + (y2 - y1) * CUTS[i + 1])
        texture:SetSize(BANNER_W, heights[i])
        texture:SetPoint("TOP", 0, -offset)
        offset = offset + heights[i]
        parts[i] = texture
    end
    return parts
end

local function each(parts, method, ...)
    for _, part in ipairs(parts) do part[method](part, ...) end
end

-- Shape of the cloth, for its hover light and its glow.
local function drawShape(frame, banner, layer, sublevel)
    if GAME_BANNER then return longBanner(frame, layer, sublevel, SHAPE) end
    local texture = frame:CreateTexture(nil, layer, nil, sublevel)
    texture:SetAllPoints(banner.cloth[1])
    Art.SmoothTexture(texture, MEDIA .. "Banner")
    return { texture }
end

local function drawBanner(frame)
    local banner = {}
    banner.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.name:SetJustifyH("CENTER")
    banner.name:SetWordWrap(true)
    if GAME_BANNER then
        banner.cloth = longBanner(frame, "ARTWORK", 0, SHAPE)
        banner.trim = longBanner(frame, "ARTWORK", 1, BORDER)
        -- Faction coat of arms over the top of the banner.
        banner.arms = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        banner.arms:SetPoint("TOP")
        -- The emblem stays where the short banner had it: on its straight top part.
        local size = BANNER_W * 0.62
        banner.emblem = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        banner.emblem:SetSize(size, size)
        banner.emblem:SetPoint("CENTER", frame, "TOP", 0, -(BANNER_TOP + naturalHeight() * 0.5 - 2))
        banner.emblem:SetTexture(EMBLEM_SHEET)
        banner.emblem:SetVertexColor(unpack(IVORY))
        Art.Font(banner.name, 11, "")
        banner.name:SetShadowOffset(1, -1)
        banner.name:SetPoint("TOP", 0, -(BANNER_TOP + BANNER_H + 4))
        banner.nameWidth = CELL_W - 6
        if banner.name.SetMaxLines then banner.name:SetMaxLines(2) end
    else
        local cloth = frame:CreateTexture(nil, "ARTWORK")
        cloth:SetSize(92, 184)
        cloth:SetPoint("TOP", 0, -2)
        Art.SmoothTexture(cloth, MEDIA .. "Banner")
        local trim = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        trim:SetAllPoints(cloth)
        Art.SmoothTexture(trim, MEDIA .. "BannerTrim")
        banner.cloth, banner.trim = { cloth }, { trim }
        banner.rod = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        banner.rod:SetSize(108, 14)
        banner.rod:SetPoint("TOP")
        Art.SmoothTexture(banner.rod, MEDIA .. "BannerRod")
        banner.crest = frame:CreateTexture(nil, "OVERLAY")
        banner.crest:SetSize(32, 32)
        banner.crest:SetPoint("TOP", cloth, "TOP", 0, -18)
        Art.Font(banner.name, 11, "OUTLINE")
        banner.name:SetTextColor(1, 1, 1)
        banner.name:SetPoint("TOP", banner.crest, "BOTTOM", 0, -6)
        banner.nameWidth = NAME_W
        if banner.name.SetMaxLines then banner.name:SetMaxLines(5) end
    end
    each(banner.trim, "SetVertexColor", unpack(GOLD))
    banner.name:SetWidth(banner.nameWidth)
    -- Measures each word on its own: a word wider than the line cannot wrap.
    local font, size, flags = banner.name:GetFont()
    banner.probe = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    if font then banner.probe:SetFont(font, size, flags) end
    banner.probe:SetAlpha(0)
    return banner
end

local function paintBanner(banner, guild)
    each(banner.cloth, "SetVertexColor", unpack(Guilds.Color(guild.faction)))
    if banner.arms then
        local arms = guild.faction == "Horde" and "HordeEmblem" or "AllianceEmblem"
        if guild.faction and Art.HasAtlas(arms) then
            fitAtlas(banner.arms, arms, 76, 52)
            banner.arms:Show()
        else
            banner.arms:Hide()
        end
        -- The emblem sheet is a 16 × 16 grid of 64-pixel emblems.
        local index, size = Guilds.EmblemIndex(guild), 1 / 16
        local x, y = index % 16 * size, math.floor(index / 16) * size
        banner.emblem:SetTexCoord(x, x + size, y, y + size)
    else
        Guilds.PaintCrest(banner.crest, guild.faction)
    end
    -- A long word (KOMPANIA…) would be cut: the whole name shrinks until its
    -- widest word fits, as Art.FitLine does for one line.
    local maxWidth, name = banner.nameWidth, banner.name
    name:SetText(guild.name)
    if not name.SetTextScale then return end
    local widest, probe = 0, banner.probe
    for word in guild.name:gmatch("%S+") do
        probe:SetText(word)
        local width = probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth() or probe:GetStringWidth()
        widest = math.max(widest, width)
    end
    local scale = widest > maxWidth and math.max(0.6, maxWidth / widest) or 1
    name:SetTextScale(scale)
    name:SetWidth(maxWidth / scale)
end

local function tooltip(owner, guild)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(Guilds.ColoredName(guild))
    GameTooltip:AddLine(Guilds.FactionName(guild.faction), 0.85, 0.85, 0.85)
    if guild.capturedAt then
        GameTooltip:AddLine(L.GUILD_TIP_DATE:format(date(L.DATE_FORMAT, guild.capturedAt)), 1, 1, 1)
    end
    if guild.zone then GameTooltip:AddLine(L.GUILD_TIP_ZONE:format(guild.zone), 1, 1, 1) end
    local function classColored(name, token)
        local color = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        return color and ("|c%s%s|r"):format(color.colorStr or "ffffffff", name) or name
    end
    if guild.member then
        GameTooltip:AddLine(L.GUILD_TIP_MEMBER:format(classColored(guild.member, guild.memberClass)), 1, 1, 1)
    end
    if guild.capturedBy then
        GameTooltip:AddLine(L.GUILD_TIP_BY:format(classColored(guild.capturedBy, guild.capturedByClass)), 1, 1, 1)
    end
    local members = Guilds.MemberCount(guild)
    GameTooltip:AddLine(L.GUILD_TIP_CARDS:format(members), 0.6, 0.9, 0.6)
    if members > 0 then GameTooltip:AddLine(L.GUILD_TIP_SEARCH, 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(L.GUILD_TIP_HINT, 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function openMenu(cell)
    local guild = cell.guild
    if not guild then return end
    -- The game's menu with the mouse, ForeverDex's own one with the controller.
    ns.PopupMenu.Open(cell, function(_, root)
        root:CreateTitle(guild.name)
        if Guilds.MemberCount(guild) > 0 then
            root:CreateButton(L.GUILD_SHOW_MEMBERS, function() UI.ShowSearch(guild.name) end)
        end
        root:CreateButton(L.SHARE_CARD, function() ns.Share.ShowGuild(guild) end)
        local index = Guilds.Find(guild.id)
        local first = root:CreateButton(L.GUILD_MOVE_FIRST, function() Guilds.Move(guild.id, 1) end)
        first:SetEnabled(index ~= 1)
        local last = root:CreateButton(L.GUILD_MOVE_LAST, function() Guilds.Move(guild.id, Guilds.Count()) end)
        last:SetEnabled(index ~= Guilds.Count())
        root:CreateDivider()
        root:CreateButton(L.GUILD_DELETE, function()
            StaticPopup_Show("FOREVERDEX_DELETE_GUILD", Guilds.ColoredName(guild), nil, guild.id)
        end)
    end)
end

-- Drag and drop ----------------------------------------------------------------------------

-- The banner follows the cursor; a gold bar shows where it will be placed.
local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetSize(CELL_W, CELL_H)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetAlpha(0.85)
ghost:Hide()
local ghostBanner = drawBanner(ghost)

local drag -- { guild, cell, target, flip, since }
local cells = {}
local lastDrop = 0

local function clearMarkers()
    for _, cell in ipairs(cells) do
        cell.before:Hide()
        cell.after:Hide()
    end
end

local function stopDrag()
    if not drag then return end
    if drag.cell then drag.cell:SetAlpha(1) end
    drag = nil
    ghost:Hide()
    clearMarkers()
end

ghost:SetScript("OnUpdate", function(self, elapsed)
    if not drag then return self:Hide() end
    local scale = self:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    -- Over a page arrow for a moment: the page turns, the drag goes on.
    local arrow = (nextPage:IsEnabled() and nextPage:IsMouseOver() and nextPage)
        or (previous:IsEnabled() and previous:IsMouseOver() and previous)
    if arrow ~= drag.flip then drag.flip, drag.since = arrow, 0 end
    if arrow then
        drag.since = drag.since + elapsed
        if drag.since >= FLIP_DELAY then
            drag.since = 0
            turnPage(arrow.step)
        end
    end

    -- Target: the banner under the cursor. The dragged one lands before it when
    -- moving back, after it when moving forward.
    local target
    for _, cell in ipairs(cells) do
        if cell:IsShown() and cell.guild and cell.guild ~= drag.guild and cell:IsMouseOver() then target = cell end
    end
    drag.target = target
    clearMarkers()
    if target then
        local from, to = Guilds.Find(drag.guild.id), Guilds.Find(target.guild.id)
        if from and to then (to > from and target.after or target.before):Show() end
    end
end)

local function startDrag(cell)
    if not cell.guild then return end
    stopDrag()
    drag = { guild = cell.guild, cell = cell, since = 0 }
    cell:SetAlpha(0.3)
    GameTooltip:Hide()
    paintBanner(ghostBanner, cell.guild)
    ghost:SetScale(window:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:Show()
    Art.Sound("IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION_CHECKBOX_ON")
end

local function finishDrag()
    if not drag then return end
    local guild, target = drag.guild, drag.target
    stopDrag()
    lastDrop = GetTime()
    if not target or not target.guild then
        refresh()
        return
    end
    local to = Guilds.Find(target.guild.id)
    Art.Sound("IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION_CHECKBOX_ON")
    if to then Guilds.Move(guild.id, to) end
end

-- Cells ------------------------------------------------------------------------------------

local function insertBar(cell, side)
    local bar = cell:CreateTexture(nil, "OVERLAY", nil, 2)
    bar:SetSize(4, CELL_H - 30)
    bar:SetPoint(side == "before" and "RIGHT" or "LEFT", cell, side == "before" and "LEFT" or "RIGHT",
        side == "before" and 1 or -1, 0)
    bar:SetColorTexture(1, 0.82, 0.3, 0.95)
    bar:Hide()
    return bar
end

local function buildCell(index)
    local cell = CreateFrame("Button", nil, grid)
    cell:SetSize(CELL_W, CELL_H)
    local columnIndex, line = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    cell:SetPoint("TOPLEFT", columnIndex * (CELL_W + GAP_X), -line * (CELL_H + GAP_Y))
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell.banner = drawBanner(cell)
    local highlight = drawShape(cell, cell.banner, "HIGHLIGHT", 0)
    each(highlight, "SetBlendMode", "ADD")
    each(highlight, "SetAlpha", 0.18)
    -- Gold glow when the banner appears, on the "click" of the guild ball.
    local flash = CreateFrame("Frame", nil, cell)
    flash:SetAllPoints()
    flash:SetFrameLevel(cell:GetFrameLevel() + 2)
    flash:SetAlpha(0)
    local glow = drawShape(flash, cell.banner, "OVERLAY", 3)
    each(glow, "SetBlendMode", "ADD")
    each(glow, "SetVertexColor", 1, 0.85, 0.4)
    cell.flashAnimation = flash:CreateAnimationGroup()
    local fadeIn = cell.flashAnimation:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.8)
    fadeIn:SetDuration(0.15)
    fadeIn:SetOrder(1)
    local fadeOut = cell.flashAnimation:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.8)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.8)
    fadeOut:SetOrder(2)
    cell.before, cell.after = insertBar(cell, "before"), insertBar(cell, "after")

    cell:SetScript("OnDragStart", startDrag)
    cell:SetScript("OnDragStop", finishDrag)
    cell:SetScript("OnClick", function(self, mouseButton)
        if not self.guild or GetTime() - lastDrop < 0.2 then return end
        if mouseButton == "RightButton" then
            openMenu(self)
        elseif Guilds.MemberCount(self.guild) > 0 then
            UI.ShowSearch(self.guild.name)
        end
    end)
    cell:SetScript("OnEnter", function(self)
        if self.guild and not drag then tooltip(self, self.guild) end
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cell
end

for i = 1, PAGE_SIZE do cells[i] = buildCell(i) end

-- Refresh -----------------------------------------------------------------------------------

local function visibleGuilds()
    local rows = {}
    for _, guild in ipairs(Guilds.List()) do
        if guild.id ~= pendingID and (filter == "all" or guild.faction == filter) then rows[#rows + 1] = guild end
    end
    return rows
end

refresh = function()
    if not board:IsShown() then return end
    local total = Guilds.Count()
    local alliance, horde = Guilds.FactionCounts()
    summary:SetText(L.GUILD_SUMMARY:format(total))
    factions:SetText(("|cff4da6ff%s|r %d   |cffff4d40%s|r %d"):format(FACTION_ALLIANCE, alliance, FACTION_HORDE, horde))

    local counts = { all = total, Alliance = alliance, Horde = horde }
    local filterName
    for _, row in ipairs(filterRows) do
        local selected = row.item.id == filter
        row.count:SetText(counts[row.item.id])
        row.bar:SetMinMaxValues(0, math.max(1, total))
        row.bar:SetValue(counts[row.item.id])
        row.selected:SetShown(selected)
        Art.FitLine(row.name, row.item.name, 96, true)
        row.name:SetTextColor(1, selected and 1 or 0.82, selected and 1 or 0)
        if selected then filterName = row.item.name end
    end
    title:SetText(L.GUILD_TAB .. " " .. ARROW .. " " .. (filterName or ""))

    local rows = visibleGuilds()
    local pageCount = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(page, pageCount))
    for i, cell in ipairs(cells) do
        local guild = rows[(page - 1) * PAGE_SIZE + i]
        cell.guild = guild
        cell:SetShown(guild ~= nil)
        if guild then
            paintBanner(cell.banner, guild)
            cell:SetAlpha(drag and drag.guild == guild and 0.3 or 1)
        end
    end
    empty:SetText(total == 0 and L.GUILD_EMPTY or L.NO_RESULTS)
    empty:SetShown(#rows == 0)
    results:SetText(L.RESULTS:format(#rows))
    pageText:SetText(L.PAGE:format(page, pageCount))
    previous:SetEnabled(page > 1)
    nextPage:SetEnabled(page < pageCount)
end
GuildsUI.Refresh = refresh

-- Shows the page holding a guild, and makes its banner glow.
local function reveal(guild)
    if not board:IsShown() then return end
    if filter ~= "all" and guild.faction ~= filter then filter = "all" end
    local rows = visibleGuilds()
    for index, row in ipairs(rows) do
        if row == guild then page = math.ceil(index / PAGE_SIZE) end
    end
    refresh()
    for _, cell in ipairs(cells) do
        if cell:IsShown() and cell.guild == guild then cell.flashAnimation:Play() end
    end
end

Guilds.OnChanged(function(guild, isNew)
    if not isNew then
        refresh()
        UI.UpdateTarget()
        return
    end
    pendingID = guild.id
    refresh()
    UI.ThrowGuild(guild, captureButton, function() return board:IsVisible() and grid or nil end, function()
        if pendingID ~= guild.id then return end
        pendingID = nil
        reveal(guild)
    end)
end)

-- Side tab and registration: UI.lua shows this page in place of the journal --------------

UI.AddSideTab(3, "guilds", L.GUILD_TAB, function(icon)
    icon:SetTexture(TABARD)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end)

local parts = { summary, factions, captureButton, column, board }
function GuildsUI.SetShown(shown)
    for _, part in ipairs(parts) do part:SetShown(shown) end
    if shown then
        local saved = ForeverDexDB and ForeverDexDB.view and ForeverDexDB.view.guildFilter
        for _, item in ipairs(FILTERS) do
            if item.id == saved then filter = saved end
        end
        UI.UpdateTarget()
        refresh()
    else
        stopDrag()
    end
end
UI.RegisterPage("guilds", GuildsUI)
end)
