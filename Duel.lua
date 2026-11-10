local _, ns = ...
ns.Module(function()
local L, Catalog, Collection, Art = ns.L, ns.Catalog, ns.Collection, ns.Art
local Duel = {}
ns.Duel = Duel

-- Collection exchange ---------------------------------------------------------
--
-- Both players need ForeverDex. Everything goes through whispered addon
-- messages (invisible in chat):
--   Q<key>=<name>  comparison request, with the requester's combination and name
--   A<key>=<name>  request accepted: each side then sends its collection
--   N              request declined
--   D<i>/<n>#...   chunk i of n of the collection (255 bytes at most per message)
--   C...           combat, see Combat.lua
-- A collection received without an accepted request is ignored.
-- Q and A end with a tab and "combat" when the sender can fight.
--
-- Cross-version compatibility: these four messages never change shape.
-- Anything new goes through either a new message type (unknown types are
-- ignored) or fields added after a tab, which readers ignore.

local PREFIX, CHUNK, TIMEOUT = "ForeverDex", 220, 25

local function readable(value)
    return (not issecretvalue or not issecretvalue(value)) and value ~= nil
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- /foreverdex duel: shows sent and received messages, for diagnostics.
local tracing = false
local function trace(direction, who, message)
    if not tracing then return end
    DEFAULT_CHAT_FRAME:AddMessage(("|cff63ded1ForeverDex|r: duel %s %s: %s"):format(direction,
        readable(who) and tostring(who) or "(secret)", readable(message) and tostring(message):sub(1, 40) or "(secret)"))
end

function Duel.ToggleTrace()
    tracing = not tracing
    DEFAULT_CHAT_FRAME:AddMessage("|cff63ded1ForeverDex|r: duel trace: " .. (tracing and "on" or "off"))
end

local function send(message, target)
    local result = C_ChatInfo.SendAddonMessage(PREFIX, message, "WHISPER", target)
    trace("sent to", target, ("%s (result %s)"):format(message:sub(1, 20), tostring(result)))
    return result
end

-- First name only: on Forever, the game does not always write the rest of the name the
-- same way. It is used to recognize a player; replies go to the address received.
local function shortName(name)
    return name:match("^[^%-%s]+") or name
end

-- The player's combination and full name, sent with each request.
local function identity()
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    local sex = UnitSex("player")
    local key = race and class and sex and Catalog.SlotKey(race, class, sex) or ""
    local firstName, surname = UnitFullName("player")
    local name = surname and surname ~= "" and (firstName .. " " .. surname) or firstName or UnitName("player")
    return (key .. "=" .. tostring(name):gsub("[~=#]", "") .. "\tcombat")
end

local function parseIdentity(text)
    local key, name = text:match("^([^=]*)=([^\t]*)")
    return Catalog.byKey[key or ""], name ~= "" and name or nil
end

local function canFight(text)
    return text:find("\tcombat", 1, true) ~= nil
end

local function serialize()
    local parts = {}
    for key, entry in pairs(ForeverDexDB.cards) do
        if Catalog.slotByKey[key] and entry.name then
            local name = entry.name:gsub("[~=@#|]", "")
            parts[#parts + 1] = key .. (entry.combination and ("@" .. entry.combination) or "") .. "=" .. name
        end
    end
    return table.concat(parts, "~")
end

-- Received data is filtered: keys known to the catalog, short names.
local function parse(payload)
    local cards = {}
    for item in payload:gmatch("[^~]+") do
        local key, combination, name = item:match("^([^=@]+)@?([^=]*)=([^\t]+)")
        if key and Catalog.slotByKey[key] and #name <= 48 then
            cards[key] = {
                key = key, name = name,
                combination = combination ~= "" and Catalog.byKey[combination] and combination or nil,
            }
        end
    end
    return cards
end

-- Whispers are only throttled inside instances: 10 messages, then 1 per second.
-- A refused piece is sent again once the allowance has recovered.
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local RETRY_DELAY, RETRY_COUNT = 1.1, 60

local function sendPiece(message, target, retries)
    local result = send(message, target)
    if THROTTLED and result == THROTTLED and retries > 0 then
        C_Timer.After(RETRY_DELAY, function() sendPiece(message, target, retries - 1) end)
    end
end

local function sendCollection(target)
    local payload = serialize()
    local total = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, total do
        local piece = payload:sub((i - 1) * CHUNK + 1, i * CHUNK)
        C_Timer.After((i - 1) * 0.15, function()
            sendPiece(("D%d/%d#%s"):format(i, total, piece), target, RETRY_COUNT)
        end)
    end
end

local outgoing -- sent request: { target, display, combination, accepted }
local partners = {} -- [short name] = { expected, chunks, display, combination }
-- Anti-spam: after a refusal, requests from the same player are dropped for a minute.
local BLOCK_TIME = 60
local blocked = {} -- [short name] = time the block ends

local function print(message)
    DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_PREFIX .. message)
end

function Duel.CanRequest(unit)
    unit = unit or "target"
    local player = UnitIsPlayer(unit)
    local selfTarget = UnitIsUnit(unit, "player")
    if not readable(player) or not player or not readable(selfTarget) or selfTarget then return false end
    local name = UnitName(unit)
    return readable(name) and name ~= nil and name ~= ""
end

local function startRequest(name, realm, display, combination)
    -- One request at a time: it clears on the reply or after the timeout.
    if outgoing and not outgoing.accepted then
        print(L.DUEL_PENDING)
        return
    end
    if readable(realm) and realm and realm ~= "" then name = name .. "-" .. realm end
    outgoing = {
        target = shortName(name),
        display = display or shortName(name),
        combination = combination,
    }
    partners[outgoing.target] = { chunks = {}, display = outgoing.display, combination = outgoing.combination }
    send("Q" .. identity(), name)
    print(L.DUEL_SENT:format(outgoing.display))
    local pending = outgoing
    C_Timer.After(TIMEOUT, function()
        if outgoing == pending and not pending.accepted then
            print(L.DUEL_NO_ANSWER:format(pending.display))
            outgoing = nil
        end
    end)
end

function Duel.Request(unit)
    unit = unit or "target"
    if not Duel.CanRequest(unit) then return end
    -- GetUnitName(unit, true) gives the name in the format whispers expect.
    local name = GetUnitName and GetUnitName(unit, true)
    local realm
    if not readable(name) or not name or name == "" then name, realm = UnitName(unit) end
    local player = Collection.ReadTarget(unit)
    startRequest(name, realm, player and player.name, player and Catalog.byKey[player.key])
end

-- From chat, the player has no unit: their name comes from the message line.
local function requestFromChat(context)
    local guid = Collection.ChatSenderGUID(context)
    if not guid then return end
    local _, class, _, race, sex, name, realm = GetPlayerInfoByGUID(guid)
    if not readable(name) or name == "" then return end
    local combination
    if readable(class) and readable(race) and readable(sex) then
        combination = Catalog.SlotForFiles(race, class, sex)
    end
    startRequest(name, realm, nil, combination)
end

-- Right-click on a player portrait, a party member or a name in chat.
if Menu and Menu.ModifyMenu then
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER" }) do
        Menu.ModifyMenu(tag, function(_, root, context)
            local unit = context and context.unit
            if not unit or not Duel.CanRequest(unit) then return end
            root:CreateDivider()
            root:CreateButton(L.COMPARE_MENU, function() Duel.Request(unit) end)
        end)
    end
    -- In chat, the option follows "Add to ForeverDex", already preceded by a separator.
    Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, context)
        if not Collection.ChatSenderGUID(context) then return end
        root:CreateButton(L.COMPARE_MENU, function() requestFromChat(context) end)
    end)
end

StaticPopupDialogs["FOREVERDEX_DUEL"] = {
    text = L.DUEL_PROMPT,
    button1 = ACCEPT,
    button2 = DECLINE,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, who)
        local partner = partners[who]
        if not partner then return end
        partner.expected = true
        send("A" .. identity(), partner.address)
        sendCollection(partner.address)
    end,
    OnCancel = function(_, who)
        local partner = partners[who]
        partners[who] = nil
        blocked[who] = GetTime() + BLOCK_TIME
        send("N", partner and partner.address or who)
    end,
}

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
    if not readable(prefix) or prefix ~= PREFIX then return end
    trace("received from", sender, text)
    if not ForeverDexDB or not readable(sender) or not readable(text) then return end
    local who = shortName(sender)
    local kind, body = text:sub(1, 1), text:sub(2)

    if kind == "Q" then
        local combination, display = parseIdentity(body)
        -- "Ignore all" and the block after a refusal show strictly nothing here;
        -- the requester simply gets a refusal, so they do not have to wait.
        local now = GetTime()
        if ns.Settings.Get("duelRequests") == "refuse" or now < (blocked[who] or 0) then
            send("N", sender)
            return
        end
        -- A request window is already open: we do not replace it.
        if StaticPopup_Visible and StaticPopup_Visible("FOREVERDEX_DUEL") then return end
        local inCombat = (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))
        if ns.Settings.Get("duelCombatRefuse") and inCombat then
            blocked[who] = now + BLOCK_TIME
            send("N", sender)
            print(L.DUEL_AUTO_REFUSED:format(display or who))
            return
        end
        partners[who] = { chunks = {}, display = display or who, combination = combination, address = sender, combat = canFight(body) }
        StaticPopup_Show("FOREVERDEX_DUEL", display or who, nil, who)
    elseif kind == "A" and outgoing and outgoing.target == who then
        outgoing.accepted = true
        local combination, display = parseIdentity(body)
        local partner = partners[who] or { chunks = {} }
        partner.expected = true
        partner.display = display or partner.display
        partner.combination = combination or partner.combination
        partner.combat = canFight(body)
        partners[who] = partner
        print(L.DUEL_ACCEPTED:format(partner.display))
        sendCollection(sender)
    elseif kind == "N" and outgoing and outgoing.target == who then
        print(L.DUEL_REFUSED:format(outgoing.display))
        outgoing, partners[who] = nil, nil
    elseif kind == "D" then
        local partner = partners[who]
        if not partner or not partner.expected then return end
        local index, total, piece = body:match("^(%d+)/(%d+)#(.*)$")
        index, total = tonumber(index), tonumber(total)
        if not index or not total or total > 200 or index > total then return end
        partner.total = total
        partner.chunks[index] = piece
        for i = 1, total do
            if not partner.chunks[i] then return end
        end
        partners[who] = nil
        if outgoing and outgoing.target == who then outgoing = nil end
        partner.address = partner.address or sender
        Duel.Show(partner, parse(table.concat(partner.chunks, "", 1, total)))
    elseif kind == "C" and Duel.OnCombatMessage then
        Duel.OnCombatMessage(body, who)
    end
end)

-- Duel screen ----------------------------------------------------------------------

local ROWS, ROW_H = 11, 28
local BLUE, RED = { 0.25, 0.55, 1 }, { 1, 0.3, 0.22 }

local function create(frameType, name, parent, template, fallback)
    local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
    if ok and frame then return frame, true end
    return CreateFrame(frameType, name, parent, fallback), false
end

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
Art.Apply(backdrop, Art.JOURNAL_BG)
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
ns.Settings.OnChange(function(key)
    if key == nil or key == "duelVsBurst" then burst:SetShown(ns.Settings.Get("duelVsBurst")) end
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
    if ns.Settings.Get("duelSounds") then Art.Sound(...) end
end

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MISSING = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function paintName(fontString, mark, wash, entry, color)
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
            paintName(row.leftName, row.leftMark, row.leftWash, item.own, BLUE)
            paintName(row.rightName, row.rightMark, row.rightWash, item.other, RED)
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

-- Scores count up from zero during the entrance.
local countElapsed, counting = 0, true
local sides = { mine, theirs }
window:SetScript("OnUpdate", function(_, delta)
    if not counting then return end
    countElapsed = countElapsed + delta
    local fraction = math.max(0, math.min(1, (countElapsed - 0.5) / 0.9))
    counting = fraction < 1
    fraction = 1 - (1 - fraction) ^ 3
    for _, side in ipairs(sides) do
        local value = math.floor((side.target or 0) * fraction + 0.5)
        side.score:SetText(value)
        side.bar:SetValue(value)
    end
end)

-- What Combat.lua needs from the duel screen.
Duel.Window, Duel.Arena, Duel.VsFrame = window, arena, vsFrame
Duel.Send, Duel.Sound = send, duelSound
Duel.BLUE, Duel.RED = BLUE, RED

function Duel.Show(partner, cards)
    state.cards, state.page, state.filter = cards, 1, 1
    Duel.Session = partner.address and {
        address = partner.address, who = shortName(partner.address),
        display = partner.display, combination = partner.combination, combat = partner.combat,
    } or nil
    if Duel.RefreshCombat then Duel.RefreshCombat() end
    local counts = render()
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    local myCombination = Catalog.byKey[Catalog.SlotKey(race or 0, class or 0, UnitSex("player") or 0)]
    local firstName, surname = UnitFullName("player")
    local myName = surname and surname ~= "" and (firstName .. " " .. surname) or firstName
    paintSide(mine, myName or UnitName("player"), myCombination, "player", counts.mineTotal)
    local target = Collection.ReadTarget()
    local targeted = target and partner.display and target.name == partner.display
    paintSide(theirs, partner.display or "?", partner.combination, targeted and "target" or nil, counts.theirsTotal)

    local animated = ns.Settings.Get("duelAnimation")
    -- Without animation, scores show their final value directly.
    countElapsed, counting = animated and 0 or 2, true
    window:Show()
    for _, group in ipairs({ mine.intro, theirs.intro, slam }) do
        group:Stop()
        if animated then group:Play() end
    end
    duelSound("RAID_WARNING", "READY_CHECK")
    C_Timer.After(0.65, function() duelSound("IG_QUEST_LIST_COMPLETE") end)
end
end)
