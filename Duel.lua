local _, ns = ...
ns.Module(function()
local L, Catalog, Collection, Art, Settings, Util = ns.L, ns.Catalog, ns.Collection, ns.Art, ns.Settings, ns.Util
local Duel = {}
ns.Duel = Duel

local readable, playerAddress = Util.Readable, Util.PlayerAddress

local exchange = ns.DuelExchange.New({
    message = function(message) DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. message) end,
    prompt = function(partner) ns.Dialog.Show("FOREVERDEX_DUEL", partner.display, nil, partner) end,
    promptVisible = function() return ns.Dialog.Visible("FOREVERDEX_DUEL") end,
    completed = function(partner, cards) Duel.Show(partner, cards) end,
    combat = function(body, who, token)
        local session = Duel.Session
        if session and session.who == who and session.token == token and Duel.OnCombatMessage then
            Duel.OnCombatMessage(body)
        end
    end,
})

function Duel.CanRequest(unit)
    unit = unit or "target"
    local player = UnitIsPlayer(unit)
    local selfTarget = UnitIsUnit(unit, "player")
    if not readable(player) or not player or not readable(selfTarget) or selfTarget then return false end
    local name = UnitName(unit)
    return readable(name) and name ~= nil and name ~= ""
end

local function startRequest(name, realm, display, combination)
    if readable(realm) and realm and realm ~= "" then name = name .. "-" .. realm end
    exchange.Request(name, display, combination)
end

function Duel.Request(unit)
    unit = unit or "target"
    if not Duel.CanRequest(unit) then return end
    local address = Util.UnitAddress(unit)
    if not address then return end
    local player = Collection.ReadTarget(unit)
    exchange.Request(address, player and player.name, player and Catalog.byKey[player.key])
end

-- From the guild member list, the player has no unit either: the menu gives their
-- name (and their GUID on recent clients). A guildmate shares the player's faction.
-- Forever whispers "First-Surname". The guild list (and the GUID of a guildmate) can
-- give "First Surname" with the server's internal realm on top, which is not part of
-- the name: the whisper address is rebuilt from the name alone.
local function whisperName(name, realm)
    -- "First Surname-Realm": the realm goes, then the space becomes the separator.
    local full = name:match("^(%S+%s+[^%-]+)%-") or name
    local first, surname = full:match("^(%S+)%s+(.+)$")
    if first then return first .. "-" .. surname end
    if full:find("-", 1, true) then return full end
    -- A single word: the realm field holds the surname on Forever, unless it is the
    -- server's own name.
    local own = GetNormalizedRealmName and GetNormalizedRealmName()
    if not readable(realm) or type(realm) ~= "string" or realm == ""
        or (own and realm:gsub("[%s%-]", "") == own) then
        return full
    end
    return full, realm
end

-- From chat, the player has no unit: their name comes from the message line.
local function requestFromChat(context)
    local guid = Collection.ChatSenderGUID(context)
    if not guid then return end
    local _, class, _, race, sex, name, realm = GetPlayerInfoByGUID(guid)
    if not readable(name) or name == "" then return end
    local combination
    if readable(class) and readable(race) and readable(sex) then
        combination = Catalog.SlotForFiles(race, class, sex, Collection.ChatSenderFaction(guid, context))
    end
    local address, addressRealm = whisperName(name, realm)
    startRequest(address, addressRealm, nil, combination)
end

local function guildMember(context)
    if not context then return end
    -- The Communities window also lists offline members: they could not answer.
    local member, presence = context.clubMemberInfo, Enum and Enum.ClubMemberPresence
    if type(member) == "table" and presence and member.presence == presence.Offline then return end
    local guid = context.guid or (type(member) == "table" and member.guid)
    if readable(guid) and type(guid) == "string" and guid:find("^Player%-") then
        local own = UnitGUID("player")
        if readable(own) and guid == own then return end
        local _, class, _, race, sex, name, realm = GetPlayerInfoByGUID(guid)
        if readable(name) and type(name) == "string" and name ~= "" then
            local combination
            if readable(class) and readable(race) and readable(sex) then
                combination = Catalog.SlotForFiles(race, class, sex, UnitFactionGroup("player"))
            end
            local address, addressRealm = whisperName(name, realm)
            return address, addressRealm, combination
        end
    end
    local name = context.name
    if not readable(name) or type(name) ~= "string" or name == "" then return end
    if playerAddress(name) == playerAddress(Util.UnitAddress("player")) then return end
    return whisperName(name, context.server)
end

-- Controller mode: a game menu holding an addon entry cannot run its protected actions
-- (Follow, or closing the menu itself, which updates the controller bindings): they
-- are blocked and the controller buttons lock up. In that mode no entry is added to
-- any menu; controller players compare with the key binding instead.
local gamepadActive = ns.PopupMenu.GamepadActive

-- Right-click on a player portrait, a party member, a name in chat (guild chat
-- included) or a guild member in the guild window. Checked at each opening: the
-- player may switch between the mouse and the controller at any time.
if Menu and Menu.ModifyMenu then
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER" }) do
        Menu.ModifyMenu(tag, function(_, root, context)
            if gamepadActive() then return end
            local unit = context and context.unit
            if not unit or not Duel.CanRequest(unit) then return end
            root:CreateDivider()
            root:CreateButton(L.COMPARE_MENU, function() Duel.Request(unit) end)
        end)
    end
    -- In chat, the option follows "Add to ForeverDex", already preceded by a separator.
    Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
        if gamepadActive() or not Collection.ChatSenderGUID(context) then return end
        root:CreateButton(L.COMPARE_MENU, function() requestFromChat(context) end)
    end)
    -- Guild window: the classic member list, and the Communities window of recent
    -- clients. Offline members have no menu entry: they could not answer.
    for _, tag in ipairs({ "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER" }) do
        Menu.ModifyMenu(tag, function(_, root, context)
            if gamepadActive() or not guildMember(context) then return end
            root:CreateDivider()
            root:CreateButton(L.COMPARE_MENU, function()
                local name, realm, combination = guildMember(context)
                if name then startRequest(name, realm, nil, combination) end
            end)
        end)
    end
end

-- Controller interface: the game's menu on a name in chat cannot hold our entries
-- (above). ForeverDex opens its own small menu next to it instead, driven by the
-- controller (Gamepad.lua): "Add to ForeverDex" and "Compare". It follows the game's
-- handling of the link (hooksecurefunc): the game's menu itself is never touched.
if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link, _, mouseButton, chatFrame)
        if mouseButton ~= "RightButton" or not gamepadActive() or type(link) ~= "string" then return end
        local kind, name, lineID = strsplit(":", link)
        if kind ~= "player" or not name or name == "" then return end
        local context = { name = name, chatTarget = name, lineID = tonumber(lineID) }
        if not Collection.ChatSenderGUID(context) then return end
        -- Once the game's menu is up, so that ours does not close at its click.
        C_Timer.After(0, function()
            ns.PopupMenu.OpenLeftOfCursor(chatFrame or UIParent, function(_, root)
                root:CreateTitle("ForeverDex")
                root:CreateButton(L.CHAT_CAPTURE, function() Collection.CaptureFromChat(context) end)
                root:CreateButton(L.COMPARE_MENU, function() requestFromChat(context) end)
            end)
        end)
    end)
end

StaticPopupDialogs["FOREVERDEX_DUEL"] = {
    text = L.DUEL_PROMPT,
    button1 = ACCEPT,
    button2 = DECLINE,
    timeout = ns.DuelExchange.PROMPT_TIMEOUT,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, partner) exchange.Accept(partner) end,
    OnCancel = function(_, partner) exchange.Decline(partner) end,
}

-- Duel screen ----------------------------------------------------------------------

local ROWS, ROW_H = 11, 28
local BLUE, RED = { 0.25, 0.55, 1 }, { 1, 0.3, 0.22 }

local create = Util.CreateFrame

local function horizontal(texture, r, g, b, leftAlpha, rightAlpha)
    texture:SetColorTexture(1, 1, 1, 1)
    if CreateColor and pcall(texture.SetGradient, texture, "HORIZONTAL",
        CreateColor(r, g, b, leftAlpha), CreateColor(r, g, b, rightAlpha)) then
        return
    end
    texture:SetColorTexture(r, g, b, (leftAlpha + rightAlpha) / 2)
end

local window, native = create("Frame", "ForeverDexDuel", UIParent, "PortraitFrameTemplate", "BackdropTemplate")
window:SetSize(940, 600)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "ForeverDexDuel")
if native then
    if window.SetTitle then window:SetTitle(L.DUEL_TITLE) end
    if window.SetPortraitToAsset then window:SetPortraitToAsset("Interface\\Icons\\Ability_DualWield") end
else
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
end

-- Arena: two sides facing each other, split at the center.
local arena, nativeArena = create("Frame", nil, window, "InsetFrameTemplate", "BackdropTemplate")
if not nativeArena then
    arena:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    arena:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
end
arena:SetPoint("TOPLEFT", 8, -28)
arena:SetPoint("BOTTOMRIGHT", -8, 8)

local backdrop = arena:CreateTexture(nil, "BACKGROUND", nil, 1)
backdrop:SetPoint("TOPLEFT", 3, -3)
backdrop:SetPoint("BOTTOMRIGHT", -3, 3)
Art.JournalInterior(backdrop)
local veil = arena:CreateTexture(nil, "BACKGROUND", nil, 2)
veil:SetAllPoints(backdrop)
veil:SetColorTexture(0, 0, 0, 0.55)
local blueSide = arena:CreateTexture(nil, "BACKGROUND", nil, 3)
blueSide:SetPoint("TOPLEFT", backdrop)
blueSide:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOM")
horizontal(blueSide, BLUE[1], BLUE[2], BLUE[3], 0.35, 0)
local redSide = arena:CreateTexture(nil, "BACKGROUND", nil, 3)
redSide:SetPoint("TOPLEFT", backdrop, "TOP")
redSide:SetPoint("BOTTOMRIGHT", backdrop)
horizontal(redSide, RED[1], RED[2], RED[3], 0, 0.35)

-- One side: medallion, name, score and bar, mirrored on the right.
local function buildSide(side)
    local left = side == "left"
    local frame = CreateFrame("Frame", nil, arena)
    frame:SetSize(400, 150)
    frame:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 14 or -14, -10)
    local color = left and BLUE or RED
    frame.medallion = Art.Medallion(frame, 96)
    frame.medallion:SetPoint(left and "TOPLEFT" or "TOPRIGHT", 0, -4)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    Art.Font(frame.name, 26, "OUTLINE")
    frame.name:SetShadowOffset(2, -2)
    frame.name:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 128 or -128, -14)
    frame.name:SetWidth(260)
    frame.name:SetJustifyH(left and "LEFT" or "RIGHT")
    frame.name:SetWordWrap(false)
    frame.combo = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.combo:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame.name, left and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -6)
    frame.team = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.team:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame.name, left and "TOPLEFT" or "TOPRIGHT", 0, 4)
    frame.team:SetTextColor(color[1], color[2], color[3])
    frame.team:SetText(left and L.DUEL_YOU or L.DUEL_OPPONENT)
    frame.score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    Art.Font(frame.score, 30, "OUTLINE")
    frame.score:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame.combo, left and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -10)
    frame.score:SetTextColor(color[1], color[2], color[3])
    frame.scoreLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.scoreLabel:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame.score, left and "BOTTOMRIGHT" or "BOTTOMLEFT", left and 6 or -6, 4)
    frame.scoreLabel:SetText(L.DUEL_CARDS)
    frame.bar = Art.ProgressBar(frame, 250, 10, true)
    frame.bar:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame.score, left and "BOTTOMLEFT" or "BOTTOMRIGHT", left and 4 or -4, -10)
    frame.bar:SetStatusBarColor(color[1], color[2], color[3])
    frame.bar:SetMinMaxValues(0, #Catalog.slots)
    if not left then
        frame.bar:SetReverseFill(true)
    end

    -- Entrance: each side slides in from its edge.
    local intro = frame:CreateAnimationGroup()
    local away = intro:CreateAnimation("Translation")
    away:SetOffset(left and -320 or 320, 0)
    away:SetDuration(0.001)
    away:SetOrder(1)
    local slide = intro:CreateAnimation("Translation")
    slide:SetOffset(left and 320 or -320, 0)
    slide:SetDuration(0.45)
    slide:SetSmoothing("OUT")
    slide:SetOrder(2)
    local fadeIn = intro:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.45)
    fadeIn:SetOrder(2)
    frame.intro = intro
    return frame
end
local mine, theirs = buildSide("left"), buildSide("right")

-- "VS" emblem: large gold font on a fixed halo, can be disabled.
local vsFrame = CreateFrame("Frame", nil, arena)
vsFrame:SetSize(120, 120)
vsFrame:SetPoint("TOP", 0, -30)
vsFrame:SetFrameLevel(arena:GetFrameLevel() + 5)
local burst = vsFrame:CreateTexture(nil, "BACKGROUND")
burst:SetTexture("Interface\\Cooldown\\starburst")
burst:SetBlendMode("ADD")
burst:SetSize(170, 170)
burst:SetPoint("CENTER")
burst:SetVertexColor(1, 0.75, 0.3, 0.35)
Settings.OnChange(function(key)
    if key == nil or key == "duelVsBurst" then burst:SetShown(Settings.Get("duelVsBurst")) end
end)
local vsText = vsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
Art.Font(vsText, 48, "THICKOUTLINE")
vsText:SetPoint("CENTER")
vsText:SetText(L.DUEL_VS)
vsText:SetShadowOffset(3, -3)
local slam = vsFrame:CreateAnimationGroup()
local slamIn = slam:CreateAnimation("Scale")
if slamIn.SetScaleFrom then
    slamIn:SetScaleFrom(3, 3)
    slamIn:SetScaleTo(1, 1)
else
    slamIn:SetScale(1 / 3, 1 / 3)
end
slamIn:SetDuration(0.25)
slamIn:SetStartDelay(0.4)
slamIn:SetSmoothing("IN")
local slamFade = slam:CreateAnimation("Alpha")
slamFade:SetFromAlpha(0)
slamFade:SetToAlpha(1)
slamFade:SetDuration(0.25)
slamFade:SetStartDelay(0.4)


-- Card list: each row sets the two names against each other around the combination.
local list = CreateFrame("Frame", nil, arena)
list:SetPoint("TOPLEFT", 10, -172)
list:SetPoint("TOPRIGHT", -10, -172)
list:SetHeight(ROWS * ROW_H)

local rows = {}
for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    local back = row:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    Art.Apply(back, Art.ROW_BG)
    row.leftWash = row:CreateTexture(nil, "BORDER")
    row.leftWash:SetPoint("TOPLEFT")
    row.leftWash:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -150, 0)
    horizontal(row.leftWash, BLUE[1], BLUE[2], BLUE[3], 0, 0.4)
    row.rightWash = row:CreateTexture(nil, "BORDER")
    row.rightWash:SetPoint("TOPLEFT", row, "TOP", 150, 0)
    row.rightWash:SetPoint("BOTTOMRIGHT")
    horizontal(row.rightWash, RED[1], RED[2], RED[3], 0.4, 0)

    row.leftMark = row:CreateTexture(nil, "ARTWORK")
    row.leftMark:SetSize(16, 16)
    row.leftMark:SetPoint("RIGHT", row, "CENTER", -158, 0)
    row.leftName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.leftName:SetPoint("RIGHT", row.leftMark, "LEFT", -6, 0)
    row.leftName:SetWidth(250)
    row.leftName:SetJustifyH("RIGHT")
    row.leftName:SetWordWrap(false)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(16, 16)
    row.classIcon:SetPoint("LEFT", row, "CENTER", -142, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.classIcon, "RIGHT", 5, 0)
    row.label:SetWidth(262)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.rightMark = row:CreateTexture(nil, "ARTWORK")
    row.rightMark:SetSize(16, 16)
    row.rightMark:SetPoint("LEFT", row, "CENTER", 158, 0)
    row.rightName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.rightName:SetPoint("LEFT", row.rightMark, "RIGHT", 6, 0)
    row.rightName:SetWidth(250)
    row.rightName:SetJustifyH("LEFT")
    row.rightName:SetWordWrap(false)
    rows[i] = row
end

local function duelSound(...)
    if Settings.Get("duelSounds") then Art.Sound(...) end
end

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MISSING = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function paintName(fontString, mark, wash, entry)
    wash:SetShown(entry ~= nil)
    mark:SetTexture(entry and READY or MISSING)
    mark:SetAlpha(entry and 1 or 0.35)
    fontString:SetText(entry and entry.name or "—")
    if entry then
        fontString:SetTextColor(1, 1, 1)
    else
        fontString:SetTextColor(0.45, 0.45, 0.45)
    end
end

-- Filters at the bottom: all, shared, you only, them only.
local state = { page = 1, filter = 1, opponent = nil, cards = {} }
local filterNames = { L.DUEL_FILTER_ALL, L.DUEL_FILTER_BOTH, L.DUEL_FILTER_MINE, L.DUEL_FILTER_THEIRS }
local pageText = arena:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pageText:SetPoint("BOTTOMRIGHT", -46, 18)
local render

local function pageButton(direction, step)
    local control = CreateFrame("Button", nil, arena)
    control:SetSize(26, 26)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    control:SetNormalTexture(base .. "Up")
    control:SetPushedTexture(base .. "Down")
    control:SetDisabledTexture(base .. "Disabled")
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetScript("OnClick", function()
        state.page = state.page + step
        duelSound("IG_ABILITY_PAGE_TURN")
        render()
    end)
    return control
end
local nextPage = pageButton("Next", 1)
nextPage:SetPoint("BOTTOMRIGHT", -12, 12)
local previous = pageButton("Prev", -1)
previous:SetPoint("RIGHT", pageText, "LEFT", -6, 0)

local filters = {}
for i, name in ipairs(filterNames) do
    local filter = CreateFrame("Button", nil, arena, "UIPanelButtonTemplate")
    filter:SetSize(130, 22)
    filter:SetText(name)
    if i == 1 then
        filter:SetPoint("BOTTOMLEFT", 12, 14)
    else
        filter:SetPoint("LEFT", filters[i - 1], "RIGHT", 6, 0)
    end
    filter:SetScript("OnClick", function()
        state.filter, state.page = i, 1
        duelSound("IG_CHARACTER_INFO_TAB")
        render()
    end)
    filters[i] = filter
end

arena:EnableMouseWheel(true)
arena:SetScript("OnMouseWheel", function(_, delta)
    if (delta > 0 and previous:IsEnabled()) or (delta < 0 and nextPage:IsEnabled()) then
        state.page = state.page - delta
        render()
    end
end)

render = function()
    local visible, counts = {}, { both = 0, mine = 0, theirs = 0, mineTotal = 0, theirsTotal = 0 }
    for _, slot in ipairs(Catalog.slots) do
        local own, other = ForeverDexDB.cards[slot.key], state.cards[slot.key]
        if own then counts.mineTotal = counts.mineTotal + 1 end
        if other then counts.theirsTotal = counts.theirsTotal + 1 end
        if own and other then counts.both = counts.both + 1
        elseif own then counts.mine = counts.mine + 1
        elseif other then counts.theirs = counts.theirs + 1 end
        local keep = (state.filter == 1 and (own or other))
            or (state.filter == 2 and own and other)
            or (state.filter == 3 and own and not other)
            or (state.filter == 4 and other and not own)
        if keep then visible[#visible + 1] = { slot = slot, own = own, other = other } end
    end
    local pages = math.max(1, math.ceil(#visible / ROWS))
    state.page = math.max(1, math.min(state.page, pages))
    pageText:SetText(L.PAGE:format(state.page, pages))
    previous:SetEnabled(state.page > 1)
    nextPage:SetEnabled(state.page < pages)
    local totals = { counts.both + counts.mine + counts.theirs, counts.both, counts.mine, counts.theirs }
    for i, filter in ipairs(filters) do
        filter:SetEnabled(i ~= state.filter)
        filter:SetText(("%s (%d)"):format(filterNames[i], totals[i]))
        Art.FitLine(filter:GetFontString(), filter:GetText(), 114)
    end

    local widest = 0
    for i, row in ipairs(rows) do
        local item = visible[(state.page - 1) * ROWS + i]
        row:SetShown(item ~= nil)
        if item then
            local slot = item.slot
            local combination = Catalog.Describe(slot, item.own or item.other)
            local _, description = Catalog.Describe(slot, item.own or item.other)
            row.label:SetText(("#%03d  %s"):format(slot.index, description))
            widest = math.max(widest, row.label:GetStringWidth())
            Art.ClassIcon(row.classIcon, combination and combination.token)
            paintName(row.leftName, row.leftMark, row.leftWash, item.own)
            paintName(row.rightName, row.rightMark, row.rightWash, item.other)
        end
    end
    -- Icons share one position; the widest line of the page centers the column.
    for _, row in ipairs(rows) do
        row.classIcon:ClearAllPoints()
        row.classIcon:SetPoint("LEFT", row, "CENTER", -(21 + widest) / 2, 0)
    end
    return counts
end

local function paintSide(side, display, combination, unit, total)
    Art.FitLine(side.name, display, 260, true)
    side.combo:SetText(combination and (combination.race .. L.SEPARATOR .. combination.class) or "")
    local color = combination and RAID_CLASS_COLORS[combination.token]
    if color then side.combo:SetTextColor(color.r, color.g, color.b) else side.combo:SetTextColor(0.8, 0.8, 0.8) end
    local icon = side.medallion.icon
    if unit and SetPortraitTexture then
        icon:SetTexture(nil)
        icon:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(icon, unit)
    elseif combination and Art.HasAtlas(combination.portraitAtlas) then
        icon:SetAtlas(combination.portraitAtlas)
    else
        icon:SetTexture(combination and combination.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    side.target = total
end

-- Scores count up from zero during the entrance. The count runs only until the scores
-- reach their value: the window then has no OnUpdate left while it stays open.
local countElapsed = 0
local sides = { mine, theirs }
local function count(self, delta)
    countElapsed = countElapsed + delta
    local fraction = math.max(0, math.min(1, (countElapsed - 0.5) / 0.9))
    if fraction >= 1 then self:SetScript("OnUpdate", nil) end
    fraction = 1 - (1 - fraction) ^ 3
    for _, side in ipairs(sides) do
        local value = math.floor((side.target or 0) * fraction + 0.5)
        side.score:SetText(value)
        side.bar:SetValue(value)
    end
end

-- What Combat.lua needs from the duel screen.
Duel.Window, Duel.Arena, Duel.VsFrame = window, arena, vsFrame
Duel.Sound = duelSound
Duel.BLUE, Duel.RED = BLUE, RED

function Duel.Show(partner, cards)
    if Duel.CloseCombat then Duel.CloseCombat() end
    state.cards, state.page, state.filter = cards, 1, 1
    Duel.Session = partner.address and partner or nil
    if Duel.Session and not partner.who then partner.who = playerAddress(partner.address) end
    if Duel.RefreshCombat then Duel.RefreshCombat() end
    local counts = render()
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    local myCombination = Catalog.byKey[Catalog.SlotKey(race or 0, class or 0, UnitSex("player") or 0)]
    local firstName, surname = UnitFullName("player")
    local myName = surname and surname ~= "" and (firstName .. " " .. surname) or firstName
    paintSide(mine, myName or UnitName("player"), myCombination, "player", counts.mineTotal)
    local targeted = partner.who and playerAddress(Util.UnitAddress("target")) == partner.who
    paintSide(theirs, partner.display or "?", partner.combination, targeted and "target" or nil, counts.theirsTotal)

    local animated = Settings.Get("duelAnimation")
    -- Without animation, scores show their final value directly.
    countElapsed = animated and 0 or 2
    window:SetScript("OnUpdate", count)
    window:Show()
    for _, group in ipairs({ mine.intro, theirs.intro, slam }) do
        group:Stop()
        if animated then group:Play() end
    end
    duelSound("RAID_WARNING", "READY_CHECK")
    C_Timer.After(0.65, function() duelSound("IG_QUEST_LIST_COMPLETE") end)
end

-- Controller (Gamepad.lua) --------------------------------------------------------------------
--
-- The duel screen is driven like the journal: the shoulders go through the filters (all,
-- shared, mine, theirs), the triggers turn the pages, the D-pad reaches the filters and the
-- fight button. During a fight, Combat.lua says what can be chosen (Duel.CombatPad).

local function fighting()
    return Duel.CombatPad ~= nil and Duel.CombatPad() ~= nil
end

ns.Gamepad.Attach(window, {
    mode = function() return "duel" end,
    close = function() window:Hide() end,
    tabs = function(step)
        if fighting() then return end
        state.filter, state.page = (state.filter - 1 + step) % #filters + 1, 1
        duelSound("IG_CHARACTER_INFO_TAB")
        render()
    end,
    tabsLabel = L.PAD_FILTERS,
    pages = function(step)
        if Duel.CombatPages and Duel.CombatPages(step) then return end
        local control = step < 0 and previous or nextPage
        if control:IsEnabled() then control:Click() end
    end,
    hintsOffset = 6,
})

ns.Gamepad.RegisterPage("duel", function()
    local combat = Duel.CombatPad and Duel.CombatPad()
    if combat then return combat end
    local targets = {}
    for _, filter in ipairs(filters) do targets[#targets + 1] = { frame = filter, A = { L.PAD_SELECT } } end
    local start = Duel.StartButton
    if start then targets[#targets + 1] = { frame = start } end
    return { targets = targets, default = start and start:IsEnabled() and start or nil }
end)
end)
