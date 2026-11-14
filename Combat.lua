local _, ns = ...
ns.Module(function()
local L, Catalog, Art, Settings, Util = ns.L, ns.Catalog, ns.Art, ns.Settings, ns.Util
local Duel = ns.Duel
local arena, window = Duel.Arena, Duel.Window
local BLUE, RED = Duel.BLUE, Duel.RED

-- Combat: each player picks a champion, then votes for the best name.
-- Messages, sent after the C of the duel protocol:
--   S                  start, the other player opens the picker
--   R                  my champion is chosen, still hidden
--   P<key>[@<combo>]=<name>  my champion, sent once both are ready
--   V<O or T>          my vote: O for my own card, T for theirs
--   X                  the fight is cancelled
-- Both vote for their own card: draw. Each votes for the other: mutual respect.
--
-- No full-screen flash anywhere: impacts use small rings that fade slowly, so the
-- scenes stay safe for photosensitive players. The "duel animation" setting also
-- removes movement, shaking and particles.

local PICK_TIME, VOTE_TIME = 90, 60
local CARD_W, CARD_H, CARD_X, CARD_Y = 250, 350, 240, 0
local VERDICT = 1.1
local PICK_ROWS = 9
local NO_FILTERS = { races = {}, classes = {}, sexes = {} }
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"

local fight
local function chat(message)
    DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. message)
end

local function sendToPartner(body)
    if Duel.Session then Duel.Send("C" .. body, Duel.Session.address) end
end

local function clamp(value)
    return math.max(0, math.min(1, value))
end

local function easeOut(value)
    return 1 - (1 - value) ^ 3
end

local function setTextScale(line, scale)
    if line.SetTextScale then line:SetTextScale(scale) end
end

local function calm()
    return not Settings.Get("duelAnimation")
end

-- Stage: the blue and red table of the duel screen ----------------------------------------

local stage = CreateFrame("Frame", nil, arena)
stage:SetAllPoints()
stage:SetFrameLevel(arena:GetFrameLevel() + 30)
stage:EnableMouse(true)
stage:Hide()
local base = stage:CreateTexture(nil, "BACKGROUND", nil, 0)
base:SetAllPoints()
base:SetColorTexture(0.03, 0.03, 0.04, 1)
local table_ = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
table_:SetPoint("TOPLEFT", 3, -3)
table_:SetPoint("BOTTOMRIGHT", -3, 3)
Art.JournalInterior(table_)
local veil = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
veil:SetAllPoints(table_)
veil:SetColorTexture(0, 0, 0, 0.55)
local blueSide = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
blueSide:SetPoint("TOPLEFT", table_)
blueSide:SetPoint("BOTTOMRIGHT", table_, "BOTTOM")
Art.Gradient(blueSide, BLUE[1], BLUE[2], BLUE[3], 0.35, 0, "HORIZONTAL")
local redSide = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
redSide:SetPoint("TOPLEFT", table_, "TOP")
redSide:SetPoint("BOTTOMRIGHT", table_)
Art.Gradient(redSide, RED[1], RED[2], RED[3], 0, 0.35, "HORIZONTAL")
-- Darkens slowly over the table for the player who lost.
local mourning = stage:CreateTexture(nil, "BACKGROUND", nil, 4)
mourning:SetAllPoints(table_)
mourning:SetColorTexture(0.02, 0.03, 0.08, 1)
mourning:SetAlpha(0)

-- Effects under the cards are clipped: nothing spills out of the window.
local under = CreateFrame("Frame", nil, stage)
under:SetAllPoints()
under:SetClipsChildren(true)
under:SetFrameLevel(stage:GetFrameLevel() + 1)

local function newRays()
    local rays = under:CreateTexture(nil, "ARTWORK")
    rays:SetTexture("Interface\\Cooldown\\starburst")
    rays:SetBlendMode("ADD")
    rays:SetVertexColor(1, 0.75, 0.25, 0.35)
    rays:Hide()
    return rays
end
local rays = { newRays(), newRays() }

local rings = {}
for i = 1, 4 do
    local disc = under:CreateTexture(nil, "BORDER")
    disc:SetTexture(DISC)
    disc:SetBlendMode("ADD")
    disc:Hide()
    rings[i] = { texture = disc }
end

local function ring(x, y, color)
    if calm() then return end
    for _, wave in ipairs(rings) do
        if not wave.age then
            wave.age = 0
            wave.texture:ClearAllPoints()
            wave.texture:SetPoint("CENTER", under, "CENTER", x, y)
            wave.texture:SetVertexColor(color[1], color[2], color[3], 1)
            wave.texture:Show()
            return
        end
    end
end

local function updateRings(delta)
    for _, wave in ipairs(rings) do
        if wave.age then
            wave.age = wave.age + delta
            if wave.age >= 0.55 then
                wave.age = nil
                wave.texture:Hide()
            else
                local progress = wave.age / 0.55
                local size = 120 + 380 * easeOut(progress)
                wave.texture:SetSize(size, size)
                wave.texture:SetAlpha(0.4 * (1 - progress))
            end
        end
    end
end

local overlay = CreateFrame("Frame", nil, stage)
overlay:SetAllPoints()
overlay:SetClipsChildren(true)
overlay:SetFrameLevel(stage:GetFrameLevel() + 20)

-- Clouds of dust rolling out from under a card that hits the table.
local puffs = {}
for i = 1, 22 do
    local cloud = overlay:CreateTexture(nil, "ARTWORK", nil, 2)
    cloud:SetTexture(MEDIA .. "Dust")
    cloud:Hide()
    puffs[i] = { texture = cloud }
end

local function dustCloud(x, y)
    if calm() then return end
    local started = 0
    for _, puff in ipairs(puffs) do
        if started >= 11 then break end
        if not puff.age then
            started = started + 1
            local spread = (started / 11) * 2 - 1
            puff.age, puff.life = 0, 0.9 + math.random() * 0.7
            puff.x, puff.y = x + spread * 110, y - CARD_H / 2 + math.random() * 24
            puff.vx, puff.vy = spread * (90 + math.random() * 120), 8 + math.random() * 34
            puff.size, puff.angle = 90 + math.random() * 70, math.random() * 6.28
            puff.spin = (math.random() - 0.5) * 0.7
            puff.texture:Show()
        end
    end
end

local function updatePuffs(delta)
    for _, puff in ipairs(puffs) do
        if puff.age then
            puff.age = puff.age + delta
            if puff.age >= puff.life then
                puff.age = nil
                puff.texture:Hide()
            else
                local progress = puff.age / puff.life
                -- The cloud is thrown fast, then hangs in the air and thins out.
                puff.vx = puff.vx * (1 - 2.6 * delta)
                puff.x, puff.y = puff.x + puff.vx * delta, puff.y + puff.vy * delta
                puff.angle = puff.angle + puff.spin * delta
                local grown = puff.size * (1 + easeOut(progress) * 1.5)
                puff.texture:ClearAllPoints()
                puff.texture:SetPoint("CENTER", overlay, "CENTER", puff.x, puff.y)
                puff.texture:SetSize(grown, grown)
                puff.texture:SetRotation(puff.angle)
                puff.texture:SetAlpha(0.75 * (1 - progress) ^ 1.4)
            end
        end
    end
end

local title = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
title:SetPoint("TOP", 0, -16)
local status = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
status:SetPoint("TOP", title, "BOTTOM", 0, -6)

local banner = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
banner:SetPoint("CENTER", 0, 234)
banner:SetShadowOffset(3, -3)
banner:Hide()
local line = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
line:SetPoint("CENTER", 0, -222)
line:SetWidth(860)
line:Hide()

local versus = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
versus:SetPoint("CENTER", 0, CARD_Y)
versus:SetShadowOffset(3, -3)
versus:SetText(L.DUEL_VS)
versus:Hide()

-- Small particles: dust at impacts, gold motes for the winner, ash for the loser.
local particles = {}
for i = 1, 40 do
    local star = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    star:SetTexture("Interface\\Cooldown\\star4")
    star:SetBlendMode("ADD")
    star:Hide()
    particles[i] = { texture = star }
end

local function emit(x, y, count, r, g, b, speed, lift, gravity, life)
    if calm() then return end
    for _, spark in ipairs(particles) do
        if count <= 0 then break end
        if not spark.life then
            count = count - 1
            local angle, velocity = math.random() * math.pi * 2, speed * (0.4 + math.random() * 0.6)
            spark.x, spark.y = x + (math.random() - 0.5) * CARD_W, y + (math.random() - 0.5) * 30
            spark.vx, spark.vy = math.cos(angle) * velocity, math.sin(angle) * velocity + lift
            spark.gravity, spark.age, spark.life = gravity, 0, life * (0.6 + math.random() * 0.4)
            local size = 10 + math.random() * 14
            spark.texture:SetSize(size, size)
            spark.texture:SetVertexColor(r, g, b, 0.8)
            spark.texture:Show()
        end
    end
end

local function motes(x, y)
    emit(x, y, 7, 1, 0.8, 0.3, 50, 90, -10, 1.5)
end

local function ash(x, y)
    emit(x, y + 180, 6, 0.55, 0.55, 0.6, 20, -50, 10, 2)
end

local function updateParticles(delta)
    for _, spark in ipairs(particles) do
        if spark.life then
            spark.age = spark.age + delta
            if spark.age >= spark.life then
                spark.life = nil
                spark.texture:Hide()
            else
                spark.vy = spark.vy - spark.gravity * delta
                spark.x, spark.y = spark.x + spark.vx * delta, spark.y + spark.vy * delta
                spark.texture:SetPoint("CENTER", overlay, "CENTER", spark.x, spark.y)
                spark.texture:SetAlpha(0.8 * (1 - spark.age / spark.life))
            end
        end
    end
end

-- Timeline: a scene is called every frame, cues fire once at their time.
local scene, cues, cueIndex, clock = nil, nil, 1, 0
local shakeTime, shakePower, shakeX, shakeY = 0, 0, 0, 0
local bannerAt, versusAt, nextStatus = nil, nil, 0
local BANNER_SCALE, VERSUS_SCALE = 1.7, 2.4

local function play(newScene, newCues)
    scene, cues, cueIndex, clock = newScene, newCues, 1, 0
    table.sort(cues, function(a, b) return a[1] < b[1] end)
end

local function shake(power, duration)
    if calm() then return end
    shakePower, shakeTime = power, duration
end

local function slam(from, to, age)
    if calm() then return to end
    local progress = clamp(age / 0.2)
    return from + (to - from) * progress * progress
end

-- Cards: tall collector's cards, one for each side -----------------------------------------

local function paintPortrait(medallion, combination)
    local icon = medallion.icon
    if combination and Art.HasAtlas(combination.portraitAtlas) then
        icon:SetAtlas(combination.portraitAtlas)
    else
        icon:SetTexture(combination and combination.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function buildCard(color)
    local card = CreateFrame("Frame", nil, stage)
    card:SetSize(CARD_W, CARD_H)
    card:SetFrameLevel(stage:GetFrameLevel() + 6)
    card:Hide()
    local back = card:CreateTexture(nil, "BACKGROUND", nil, 0)
    back:SetPoint("TOPLEFT", 5, -5)
    back:SetPoint("BOTTOMRIGHT", -5, 5)
    back:SetColorTexture(0.09, 0.06, 0.03, 1)

    card.tint = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.cover = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    for _, texture in ipairs({ card.tint, card.cover }) do
        texture:SetPoint("TOPLEFT", 6, -32)
        texture:SetPoint("TOPRIGHT", -6, -32)
        texture:SetHeight(176)
    end
    local fade = card:CreateTexture(nil, "BORDER")
    fade:SetPoint("BOTTOMLEFT", card.cover, "BOTTOMLEFT")
    fade:SetPoint("BOTTOMRIGHT", card.cover, "BOTTOMRIGHT")
    fade:SetHeight(90)
    Art.Gradient(fade, 0.09, 0.06, 0.03, 1, 0)

    -- The owner's ribbon, in the color of their side of the table.
    local ribbon = card:CreateTexture(nil, "ARTWORK", nil, 1)
    ribbon:SetPoint("TOPLEFT", 6, -6)
    ribbon:SetPoint("TOPRIGHT", -6, -6)
    ribbon:SetHeight(26)
    ribbon:SetColorTexture(color[1] * 0.75, color[2] * 0.75, color[3] * 0.75, 1)
    card.owner = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.owner:SetPoint("CENTER", ribbon, "CENTER", 0, 0)
    card.owner:SetJustifyH("CENTER")
    card.owner:SetWordWrap(false)
    card.owner:SetTextColor(1, 1, 1)

    card.classIcon = card:CreateTexture(nil, "OVERLAY")
    card.classIcon:SetSize(32, 32)
    card.classIcon:SetPoint("TOPRIGHT", -12, -40)

    card.medallion = Art.Medallion(card, 92)
    card.medallion:SetPoint("CENTER", card, "TOP", 0, -204 / (92 / 31))
    card.medallion:SetFrameLevel(card:GetFrameLevel() + 4)

    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    Art.Font(card.name, 22, "OUTLINE")
    card.name:SetShadowOffset(2, -2)
    card.name:SetPoint("TOP", 0, -258)
    card.name:SetJustifyH("CENTER")
    card.name:SetWordWrap(false)

    local rule = card:CreateTexture(nil, "ARTWORK")
    rule:SetSize(170, 1)
    rule:SetPoint("TOP", 0, -290)
    rule:SetColorTexture(1, 0.82, 0.35, 0.6)

    card.details = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.details:SetPoint("TOP", rule, "BOTTOM", 0, -9)
    card.details:SetJustifyH("CENTER")
    card.details:SetWordWrap(false)

    local frame = CreateFrame("Frame", nil, card, "BackdropTemplate")
    frame:SetAllPoints()
    frame:SetFrameLevel(card:GetFrameLevel() + 2)
    frame:SetBackdrop({ edgeFile = GOLD_BORDER, edgeSize = 24 })
    return card
end
local cardMine, cardTheirs = buildCard(BLUE), buildCard(RED)

local function setDefeated(card, defeated)
    card.cover:SetDesaturated(defeated)
    card.medallion.icon:SetDesaturated(defeated)
    card.classIcon:SetDesaturated(defeated)
    if defeated then card.name:SetTextColor(0.55, 0.55, 0.55) else card.name:SetTextColor(1, 0.82, 0) end
end

local function paintCard(card, entry, owner)
    local slot = Catalog.slotByKey[entry.key]
    local combination, description = Catalog.Describe(slot or {}, entry)
    local theme = combination and combination.theme
    if theme then card.tint:SetColorTexture(theme[3], theme[4], theme[5]) else card.tint:SetColorTexture(0.2, 0.15, 0.1) end
    local shown = Art.LoadingScreen(card.cover, theme, CARD_W - 12, 176)
    if not shown then shown = Art.Scenery(card.cover, theme, CARD_W - 12, 176) end
    card.cover:SetShown(shown and true or false)
    paintPortrait(card.medallion, combination)
    Art.FitLine(card.owner, owner, CARD_W - 28, true)
    Art.FitLine(card.name, entry.name, CARD_W - 30, true)
    Art.FitLine(card.details, description, CARD_W - 26, true)
    local color = combination and RAID_CLASS_COLORS[combination.token]
    if color then card.details:SetTextColor(color.r, color.g, color.b) else card.details:SetTextColor(0.8, 0.8, 0.8) end
    Art.ClassIcon(card.classIcon, combination and combination.token)
    setDefeated(card, false)
    card:SetScale(1)
    card:SetAlpha(1)
    card:Show()
end

local function setCard(card, x, y, scale, alpha)
    card:SetScale(scale)
    card:ClearAllPoints()
    card:SetPoint("CENTER", stage, "CENTER", (x + shakeX) / scale, (y + shakeY) / scale)
    card:SetAlpha(alpha or 1)
end

local function button(parent, label, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 26)
    control:SetText(label)
    control:SetScript("OnClick", action)
    return control
end

local forward = {}

local VOTE_Y = CARD_Y - CARD_H / 2 - 22
local voteMine = button(overlay, L.COMBAT_VOTE, 200, function() forward.vote("O") end)
voteMine:SetPoint("CENTER", -CARD_X, VOTE_Y)
voteMine:Hide()
local voteTheirs = button(overlay, L.COMBAT_VOTE, 200, function() forward.vote("T") end)
voteTheirs:SetPoint("CENTER", CARD_X, VOTE_Y)
voteTheirs:Hide()

local rematch = button(overlay, L.COMBAT_AGAIN, 170, function() forward.begin(true) end)
rematch:SetPoint("BOTTOM", -95, 14)
rematch:Hide()
local leave = button(overlay, L.BACK, 170, function() forward.close() end)
leave:SetPoint("BOTTOM", 95, 14)
leave:Hide()
local giveUp = button(overlay, CANCEL, 150, function() forward.close() end)
giveUp:SetPoint("BOTTOMRIGHT", -14, 14)
giveUp:Hide()

-- Picker: the list on the left, the chosen champion on the right ------------------------------

local picker = CreateFrame("Frame", nil, stage)
picker:SetAllPoints()
picker:SetFrameLevel(stage:GetFrameLevel() + 4)
picker:Hide()

local LIST_W, ROW_H = 540, 40
local pickPage, pickKey, refreshPicker = 1, nil, nil
local search = Util.CreateFrame("EditBox", nil, picker, "SearchBoxTemplate", "InputBoxTemplate")
search:SetSize(LIST_W - 8, 22)
search:SetPoint("TOPLEFT", 22, -78)
search:SetAutoFocus(false)
search:SetMaxLetters(60)
if search.Instructions then search.Instructions:SetText(L.COMBAT_SEARCH) end
search:HookScript("OnTextChanged", function()
    pickPage = 1
    refreshPicker()
end)

local cells = {}
for i = 1, PICK_ROWS do
    local cell = CreateFrame("Button", nil, picker)
    cell:SetSize(LIST_W, ROW_H)
    cell:SetPoint("TOPLEFT", 18, -108 - (i - 1) * (ROW_H + 2))
    local back = cell:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    Art.Apply(back, Art.ROW_BG)
    cell.selected = cell:CreateTexture(nil, "BORDER")
    cell.selected:SetAllPoints()
    Art.Apply(cell.selected, Art.ROW_SELECTED)
    local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    Art.Apply(highlight, Art.ROW_HIGHLIGHT)
    cell.classIcon = cell:CreateTexture(nil, "ARTWORK")
    cell.classIcon:SetSize(24, 24)
    cell.classIcon:SetPoint("LEFT", 8, 0)
    cell.name = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cell.name:SetPoint("LEFT", cell.classIcon, "RIGHT", 8, 0)
    cell.name:SetJustifyH("LEFT")
    cell.name:SetWordWrap(false)
    cell.star = cell:CreateTexture(nil, "OVERLAY")
    cell.star:SetSize(14, 14)
    cell.star:SetPoint("RIGHT", -8, 0)
    cell.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    cell.details = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.details:SetPoint("RIGHT", -28, 0)
    cell.details:SetJustifyH("RIGHT")
    cell.details:SetWordWrap(false)
    cell:SetScript("OnClick", function(self)
        if not self.key then return end
        pickKey = self.key
        Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        refreshPicker()
    end)
    cell:SetScript("OnDoubleClick", function(self)
        if self.key then
            pickKey = self.key
            forward.confirm()
        end
    end)
    cells[i] = cell
end

local empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
empty:SetPoint("TOP", picker, "TOPLEFT", 18 + LIST_W / 2, -200)
empty:SetText(L.NO_RESULTS)

local pageLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pageLabel:SetPoint("BOTTOM", picker, "BOTTOMLEFT", 18 + LIST_W / 2, 22)
local function pageButton(direction, step, point, x)
    local control = CreateFrame("Button", nil, picker)
    control:SetSize(28, 28)
    local path = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    control:SetNormalTexture(path .. "Up")
    control:SetPushedTexture(path .. "Down")
    control:SetDisabledTexture(path .. "Disabled")
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetPoint(point, pageLabel, point == "RIGHT" and "LEFT" or "RIGHT", x, 0)
    control:SetScript("OnClick", function()
        pickPage = pickPage + step
        Art.Sound("IG_ABILITY_PAGE_TURN")
        refreshPicker()
    end)
    return control
end
local previousPage = pageButton("Prev", -1, "RIGHT", -8)
local nextPage = pageButton("Next", 1, "LEFT", 8)

local PREVIEW_X, PREVIEW_Y = 288, 14
local confirm = button(picker, L.COMBAT_CONFIRM, 220, function() forward.confirm() end)
confirm:SetPoint("CENTER", PREVIEW_X, PREVIEW_Y - CARD_H / 2 - 24)

picker:EnableMouseWheel(true)
picker:SetScript("OnMouseWheel", function(_, delta)
    if (delta > 0 and previousPage:IsEnabled()) or (delta < 0 and nextPage:IsEnabled()) then
        pickPage = pickPage - delta
        refreshPicker()
    end
end)

-- Favorites come first, then everything by name.
local function pickerRows()
    local rows = Catalog.Query(ForeverDexDB.cards, search:GetText() or "", 2, 3, NO_FILTERS)
    local favorites, others = {}, {}
    for _, row in ipairs(rows) do
        local list = row.entry.favorite and favorites or others
        list[#list + 1] = row
    end
    for _, row in ipairs(others) do favorites[#favorites + 1] = row end
    return favorites
end

local function myLabel()
    return L.DUEL_YOU
end

refreshPicker = function()
    if not fight or fight.phase ~= "pick" then return end
    local rows = pickerRows()
    if not pickKey and rows[1] then pickKey = rows[1].slot.key end
    local pages = math.max(1, math.ceil(#rows / PICK_ROWS))
    pickPage = math.max(1, math.min(pickPage, pages))
    pageLabel:SetText(L.PAGE:format(pickPage, pages))
    previousPage:SetEnabled(pickPage > 1)
    nextPage:SetEnabled(pickPage < pages)
    empty:SetShown(#rows == 0)
    for i, cell in ipairs(cells) do
        local row = rows[(pickPage - 1) * PICK_ROWS + i]
        cell:SetShown(row ~= nil)
        cell.key = row and row.slot.key or nil
        if row then
            Art.ClassIcon(cell.classIcon, row.details and row.details.token)
            Art.FitLine(cell.name, row.entry.name, 290, true)
            Art.FitLine(cell.details, row.description, 180, true)
            cell.star:SetShown(row.entry.favorite == true)
            cell.selected:SetShown(cell.key == pickKey)
        end
    end
    local entry = pickKey and ForeverDexDB.cards[pickKey]
    confirm:SetEnabled(entry ~= nil)
    if entry then
        paintCard(cardMine, entry, myLabel())
        setCard(cardMine, PREVIEW_X, PREVIEW_Y, 1)
    else
        cardMine:Hide()
    end
end

-- Fight --------------------------------------------------------------------------------

local function resetStage()
    scene = nil
    bannerAt, versusAt, shakeTime, shakeX, shakeY = nil, nil, 0, 0, 0
    mourning:SetAlpha(0)
    for _, spark in ipairs(particles) do
        spark.life = nil
        spark.texture:Hide()
    end
    for _, wave in ipairs(rings) do
        wave.age = nil
        wave.texture:Hide()
    end
    for _, puff in ipairs(puffs) do
        puff.age = nil
        puff.texture:Hide()
    end
    for _, region in ipairs({ rays[1], rays[2], banner, line, versus, picker, cardMine, cardTheirs,
        voteMine, voteTheirs, rematch, leave, giveUp, title, status }) do
        region:Hide()
    end
end

local function stop(message)
    fight = nil
    resetStage()
    stage:Hide()
    if message then chat(message) end
end

local function opponentName()
    return Duel.Session and Duel.Session.display or "?"
end

local function showTitle(text)
    title:SetText(text)
    title:Show()
end

-- The line under the title, with the time left. Called a few times per second.
local function updateStatus()
    if not fight or not fight.deadline then return end
    local left = math.max(0, math.ceil(fight.deadline - GetTime()))
    local text
    if fight.phase == "pick" then
        text = (fight.theirReady and L.COMBAT_OPP_READY or L.COMBAT_OPP_CHOOSING):format(opponentName())
    elseif fight.phase == "wait" or fight.myVote then
        text = L.COMBAT_WAITING:format(opponentName())
    else
        text = L.COMBAT_VOTE_HINT
    end
    status:SetText(("%s   %d:%02d"):format(text, math.floor(left / 60), left % 60))
    status:Show()
end

local function setDeadline(seconds)
    fight.deadline = GetTime() + seconds
    updateStatus()
end

local function checkDeadline()
    if not fight or not fight.deadline or GetTime() < fight.deadline then return end
    -- The player who did not act is told the time ran out; the other, who was left waiting.
    local idle = fight.phase == "pick" or (fight.phase == "vote" and not fight.myVote)
    sendToPartner("X")
    stop(idle and L.COMBAT_EXPIRED or L.COMBAT_TIMEOUT:format(opponentName()))
end

stage:SetScript("OnUpdate", function(_, delta)
    nextStatus = nextStatus - delta
    if nextStatus <= 0 then
        nextStatus = 0.25
        checkDeadline()
        if not fight then return end
        updateStatus()
    end
    if not scene then return end
    clock = clock + delta
    while cues[cueIndex] and cues[cueIndex][1] <= clock do
        local cue = cues[cueIndex]
        cueIndex = cueIndex + 1
        cue[2]()
        if not scene then return end
    end
    if shakeTime > 0 then
        shakeTime = shakeTime - delta
        local power = shakePower * clamp(shakeTime / 0.3)
        shakeX, shakeY = (math.random() - 0.5) * power * 2, (math.random() - 0.5) * power * 2
    else
        shakeX, shakeY = 0, 0
    end
    scene(clock)
    if bannerAt then setTextScale(banner, slam(BANNER_SCALE * 1.6, BANNER_SCALE, clock - bannerAt)) end
    if versusAt then setTextScale(versus, slam(VERSUS_SCALE * 2, VERSUS_SCALE, clock - versusAt)) end
    updateRings(delta)
    updatePuffs(delta)
    updateParticles(delta)
end)

local function begin(isChallenger)
    local session = Duel.Session
    if not session or not session.combat then return end
    fight = { phase = "pick" }
    resetStage()
    stage:Show()
    pickPage, pickKey = 1, nil
    search:SetText("")
    picker:Show()
    giveUp:Show()
    showTitle(isChallenger and L.COMBAT_PICK_TITLE or L.COMBAT_CHALLENGED:format(opponentName()))
    setDeadline(PICK_TIME)
    refreshPicker()
    if isChallenger then sendToPartner("S") end
end

local function encode(entry)
    local name = entry.name:gsub("[~=@#|]", "")
    return entry.key .. (entry.combination and ("@" .. entry.combination) or "") .. "=" .. name
end

local function decode(text)
    local key, combination, name = text:match("^([^=@]+)@?([^=]*)=([^\t]+)$")
    if not key or not Catalog.slotByKey[key] or #name > 48 then return end
    return { key = key, name = name, combination = combination ~= "" and Catalog.byKey[combination] and combination or nil }
end

local function exchange()
    if fight.mine and fight.theirReady and not fight.sent then
        fight.sent = true
        sendToPartner("P" .. encode(fight.mine))
    end
end

-- A card thrown from the top of the screen: huge and close at first, then
-- crushed flat on the table. Returns its position and scale.
local THROW_TIME = 0.26
local THROW_HEIGHT, THROW_SCALE = 1000, 3.2

local function thrown(landsAt, now)
    if calm() then return CARD_Y, 1, now >= landsAt and 1 or 0 end
    local age = now - (landsAt - THROW_TIME)
    if age < 0 then return CARD_Y + THROW_HEIGHT, THROW_SCALE, 0 end
    if age >= THROW_TIME then
        -- The card is driven into the table, then settles back.
        local after = age - THROW_TIME
        local squash = after < 0.22 and 0.12 * (1 - after / 0.22) ^ 2 or 0
        return CARD_Y, 1 - squash, 1
    end
    local progress = age / THROW_TIME
    progress = progress * progress * progress
    return CARD_Y + THROW_HEIGHT * (1 - progress), THROW_SCALE + (1 - THROW_SCALE) * progress, 1
end

local function reveal()
    fight.phase = "reveal"
    fight.deadline = nil
    resetStage()
    paintCard(cardMine, fight.mine, myLabel())
    paintCard(cardTheirs, fight.theirs, opponentName())
    local LEFT_LANDS, RIGHT_LANDS = 0.85, 1.75
    local function land(x)
        shake(3, 0.25)
        dustCloud(x, CARD_Y)
        Duel.Sound("PUT_DOWN_SMALL_CHAIN", "IG_MAINMENU_OPTION_CHECKBOX_ON")
    end
    play(function(now)
        local y, scale, alpha = thrown(LEFT_LANDS, now)
        setCard(cardMine, -CARD_X, y, scale, alpha)
        y, scale, alpha = thrown(RIGHT_LANDS, now)
        setCard(cardTheirs, CARD_X, y, scale, alpha)
    end, {
        { LEFT_LANDS, function() land(-CARD_X) end },
        { RIGHT_LANDS, function() land(CARD_X) end },
        { 2.35, function()
            versus:Show()
            versusAt = clock
            shake(2, 0.2)
        end },
        { 2.85, function()
            fight.phase = "vote"
            showTitle(L.COMBAT_VOTE_TITLE)
            voteMine:Show()
            voteTheirs:Show()
            voteMine:SetEnabled(true)
            voteTheirs:SetEnabled(true)
            setDeadline(VOTE_TIME)
        end },
    })
end

local function randomLine(lines, first, second)
    return lines[math.random(#lines)]:format(first, second)
end

local function showBanner(text, r, g, b)
    banner:SetText(text)
    banner:SetTextColor(r, g, b)
    banner:Show()
    bannerAt = clock
end

local function showEndButtons()
    rematch:Show()
    leave:Show()
end

local function showLine(text)
    line:SetText(text)
    line:Show()
end

local function tremble(card, x, y, now)
    local amplitude = calm() and 0 or 0.5 + 2 * clamp(now / VERDICT)
    setCard(card, x + (math.random() - 0.5) * amplitude * 2, y + (math.random() - 0.5) * amplitude * 2, 1)
end

local function spinRays(texture, x, y, now, speed, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", under, "CENTER", x, y)
    if not calm() then texture:SetRotation(now * speed) end
    texture:SetSize(size, size)
    texture:Show()
end

local function hideVersus()
    versus:Hide()
    versusAt = nil
end

local function tension(now)
    tremble(cardMine, -CARD_X, CARD_Y, now)
    tremble(cardTheirs, CARD_X, CARD_Y, now)
end

-- The player who won sees their champion take the center of the table in gold.
local function winScene(card, other, startX, otherX, winnerName, loserName, cueList, add)
    add(0, function()
        hideVersus()
        shake(4, 0.3)
        ring(startX, CARD_Y, { 1, 0.8, 0.3 })
        setDefeated(other, true)
        showBanner(L.COMBAT_VICTORY, 1, 0.82, 0.1)
    end)
    for _, delay in ipairs({ 0.3, 0.8, 1.3, 1.8, 2.3 }) do
        add(delay, function() motes(0, CARD_Y - 120) end)
    end
    add(0.5, function()
        showLine(randomLine(L.COMBAT_WIN_LINES, winnerName, loserName))
    end)
    add(2.4, showEndButtons)
    play(function(now)
        if now < VERDICT then return tension(now) end
        local age = now - VERDICT
        local progress = calm() and 1 or easeOut(clamp(age / 0.5))
        local x = startX * (1 - progress)
        setCard(card, x, CARD_Y, 1 + 0.08 * progress)
        spinRays(rays[1], x, CARD_Y, now, 0.3, 470)
        if age < 0.4 then
            tremble(other, otherX, CARD_Y, VERDICT)
        elseif calm() then
            setCard(other, otherX, CARD_Y, 1, 0)
        else
            local fall = age - 0.4
            setCard(other, otherX, CARD_Y - 900 * fall * fall, 1, clamp(1 - fall * 1.4))
        end
    end, cueList)
end

-- The player who lost sees something else entirely: no gold, the table goes
-- cold, and their champion slowly sinks while the winner stays where it is.
local function loseScene(card, other, startX, otherX, winnerName, loserName, cueList, add)
    add(0, function()
        hideVersus()
        shake(3, 0.25)
        setDefeated(card, true)
        showBanner(L.COMBAT_DEFEAT, 0.85, 0.2, 0.2)
        Duel.Sound("IG_QUEST_FAILED", "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    end)
    for _, delay in ipairs({ 0.4, 1, 1.6, 2.2 }) do
        add(delay, function() ash(startX, CARD_Y) end)
    end
    add(0.9, function() showLine(randomLine(L.COMBAT_WIN_LINES, winnerName, loserName)) end)
    add(2.4, showEndButtons)
    play(function(now)
        if now < VERDICT then return tension(now) end
        local age = now - VERDICT
        local sink = calm() and 1 or clamp(age / 2.2)
        mourning:SetAlpha(0.55 * clamp(age / 1.2))
        setCard(card, startX, CARD_Y - 46 * sink, 1 - 0.1 * sink, 1 - 0.55 * sink)
        setCard(other, otherX, CARD_Y, 1)
    end, cueList)
end

local function resolve()
    fight.phase = "result"
    fight.deadline = nil
    voteMine:Hide()
    voteTheirs:Hide()
    title:Hide()
    status:Hide()
    local myVote, theirVote = fight.myVote, fight.theirVote
    local mineName, theirsName = fight.mine.name, fight.theirs.name
    local cueList = {}
    local function add(time, action) cueList[#cueList + 1] = { VERDICT + time, action } end

    if myVote == "O" and theirVote == "T" then
        winScene(cardMine, cardTheirs, -CARD_X, CARD_X, mineName, theirsName, cueList, add)
    elseif myVote == "T" and theirVote == "O" then
        loseScene(cardMine, cardTheirs, -CARD_X, CARD_X, theirsName, mineName, cueList, add)
    elseif myVote == "O" then
        -- Each defended their own card: the two champions clash, nobody gives in.
        add(0, hideVersus)
        for _, delay in ipairs({ 0.2, 0.6, 1 }) do
            add(delay, function()
                shake(3, 0.2)
                ring(0, CARD_Y, { 0.75, 0.8, 1 })
                dustCloud(0, CARD_Y + 60)
                Duel.Sound("PUT_DOWN_SMALL_CHAIN", "IG_MAINMENU_OPTION_CHECKBOX_ON")
            end)
        end
        add(1.25, function()
            showBanner(L.COMBAT_DRAW, 0.8, 0.85, 1)
            showLine(randomLine(L.COMBAT_DRAW_LINES, mineName, theirsName))
        end)
        add(2.4, showEndButtons)
        play(function(now)
            if now < VERDICT then return tension(now) end
            local age = now - VERDICT
            local gap = CARD_X
            if age < 1.2 and not calm() then gap = 132 + (CARD_X - 132) * math.abs(math.cos(age / 0.4 * math.pi)) end
            setCard(cardMine, -gap, CARD_Y, 1)
            setCard(cardTheirs, gap, CARD_Y, 1)
        end, cueList)
    else
        -- Each voted for the other: the champions salute in a warm light.
        add(0, function()
            hideVersus()
            showBanner(L.COMBAT_RESPECT, 1, 0.85, 0.45)
            ring(-CARD_X, CARD_Y, { 1, 0.85, 0.5 })
            ring(CARD_X, CARD_Y, { 1, 0.85, 0.5 })
        end)
        for _, delay in ipairs({ 0.3, 0.9, 1.5, 2.1 }) do
            add(delay, function()
                motes(-CARD_X, CARD_Y - 120)
                motes(CARD_X, CARD_Y - 120)
            end)
        end
        add(0.5, function() showLine(randomLine(L.COMBAT_RESPECT_LINES, mineName, theirsName)) end)
        add(2.4, showEndButtons)
        play(function(now)
            if now < VERDICT then return tension(now) end
            setCard(cardMine, -CARD_X, CARD_Y, 1)
            setCard(cardTheirs, CARD_X, CARD_Y, 1)
            spinRays(rays[1], -CARD_X, CARD_Y, now, 0.25, 380)
            spinRays(rays[2], CARD_X, CARD_Y, now, -0.25, 380)
        end, cueList)
    end
end

local function tryResolve()
    if fight.myVote and fight.theirVote then resolve() end
end

function forward.begin(isChallenger) begin(isChallenger) end

function forward.confirm()
    if not fight or fight.phase ~= "pick" or not pickKey then return end
    local entry = ForeverDexDB.cards[pickKey]
    if not entry then return end
    fight.phase, fight.mine = "wait", entry
    picker:Hide()
    Duel.Sound("IG_CHARACTER_INFO_TAB")
    paintCard(cardMine, entry, myLabel())
    setCard(cardMine, 0, CARD_Y - 10, 1)
    showTitle(L.COMBAT_PICK_TITLE)
    updateStatus()
    sendToPartner("R")
    exchange()
end

function forward.vote(choice)
    if not fight or fight.phase ~= "vote" or fight.myVote then return end
    fight.myVote = choice
    voteMine:SetEnabled(false)
    voteTheirs:SetEnabled(false)
    updateStatus()
    Art.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    sendToPartner("V" .. choice)
    tryResolve()
end

function forward.close()
    if fight and fight.phase ~= "result" then sendToPartner("X") end
    stop()
end

-- Messages from the opponent. Only the current duel partner is listened to.
function Duel.OnCombatMessage(body, who)
    local session = Duel.Session
    if not session or who ~= session.who or not window:IsShown() then return end
    local kind, payload = body:sub(1, 1), body:sub(2)
    if kind == "S" then
        if not fight or fight.phase == "result" then begin(false) end
        return
    end
    if not fight then return end
    if kind == "X" then
        stop(L.COMBAT_LEFT:format(opponentName()))
    elseif kind == "R" then
        fight.theirReady = true
        updateStatus()
        exchange()
    elseif kind == "P" and not fight.theirs then
        local card = decode(payload)
        if not card then return end
        fight.theirs = card
        exchange()
        if fight.mine and fight.phase == "wait" then reveal() end
    elseif kind == "V" and (payload == "O" or payload == "T") and not fight.theirVote then
        fight.theirVote = payload
        tryResolve()
    end
end

-- Entry point on the duel screen, in the gap below the VS.
local start = button(arena, L.COMBAT_BUTTON, 180, function() begin(true) end)
start:SetPoint("TOP", Duel.VsFrame, "BOTTOM", 0, 8)
start:SetFrameLevel(arena:GetFrameLevel() + 8)
start:SetMotionScriptsWhileDisabled(true)
start:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.COMBAT_BUTTON)
    local session = Duel.Session
    local reason = L.COMBAT_TOOLTIP
    if not session or not session.combat then
        reason = L.COMBAT_UNAVAILABLE
    elseif not next(ForeverDexDB.cards) then
        reason = L.COMBAT_NO_CARDS
    end
    GameTooltip:AddLine(reason, 1, 1, 1, true)
    GameTooltip:Show()
end)
start:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Called for every new duel, which ends any fight still on screen.
function Duel.RefreshCombat()
    if fight then stop() end
    local session = Duel.Session
    start:SetEnabled(session ~= nil and session.combat == true and next(ForeverDexDB.cards) ~= nil)
end

window:HookScript("OnHide", function()
    if fight then forward.close() end
end)
end)
