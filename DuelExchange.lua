local _, ns = ...
ns.Module(function()
local L, Catalog, Comm, Util = ns.L, ns.Catalog, ns.Comm, ns.Util
local Exchange = { PROMPT_TIMEOUT = 30 }
ns.DuelExchange = Exchange

local REQUEST_TIMEOUT, TRANSFER_TIMEOUT, BLOCK_TIME = 35, 120, 60
local CHUNK, MAX_CHUNKS, SEND_GAP, RETRY_DELAY = 220, 200, 0.15, 1.1
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local playerAddress = Util.PlayerAddress

local function tokenField(token)
    return token and ("\tfd185:" .. token) or ""
end

local function parseToken(body)
    local token = body:match("\tfd185:([%x%-]+)$")
    if token and #token <= 22 then return token end
end

local function identity()
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    local sex = UnitSex("player")
    local key = race and class and sex and Catalog.SlotKey(race, class, sex) or ""
    local name = ns.Collection.PlayerName() or UnitName("player")
    return key .. "=" .. (Util.Readable(name) and name:gsub("[~=#|%c]", "") or "") .. "\tcombat"
end

local function readIdentity(body, session)
    local key, name = body:match("^([^=]*)=([^\t]*)")
    if name and name ~= "" and #name <= 64 and not name:find("[|%c]") then session.display = name end
    session.combination = Catalog.byKey[key or ""] or session.combination
    session.combat = ("\t" .. body .. "\t"):find("\tcombat\t", 1, true) ~= nil
end

-- Keep Q/A/N/D compatible with old clients. Peers that echo the token use T for
-- chunks and W for combat, so late traffic cannot enter a later comparison.
function Exchange.New(ui)
    local partners, blocked = {}, {}
    local outgoing, serial = nil, 0
    local api = {}

    local function close(session)
        partners[session.who] = nil
        if outgoing == session then outgoing = nil end
        if session.timeout then session.timeout:Cancel() end
        if session.sendTimer then session.sendTimer:Cancel() end
    end

    local function armTimeout(session, seconds, expired)
        if session.timeout then session.timeout:Cancel() end
        session.timeout = C_Timer.NewTimer(seconds, function()
            session.timeout = nil
            if partners[session.who] ~= session then return end
            close(session)
            if expired then ui.message(expired:format(session.display)) end
        end)
    end

    local function finishIfComplete(session)
        if not session.sent or not session.cards then return end
        close(session)
        ui.completed({
            address = session.address, who = session.who, display = session.display,
            combination = session.combination, combat = session.combat, token = session.token,
        }, session.cards)
    end

    local function transfer(session, acceptance)
        session.accepted = true
        session.chunks, session.received = {}, 0
        armTimeout(session, TRANSFER_TIMEOUT, L.DUEL_TRANSFER_TIMEOUT)
        local payload = ns.DuelCards.Serialize(ForeverDexDB.cards)
        local total = math.max(1, math.ceil(#payload / CHUNK))
        local prefix = session.token and ("T" .. session.token .. "|") or "D"
        local index = 1
        local function nextChunk()
            session.sendTimer = nil
            if partners[session.who] ~= session then return end
            local piece = payload:sub((index - 1) * CHUNK + 1, index * CHUNK)
            local message = acceptance or (prefix .. ("%d/%d#%s"):format(index, total, piece))
            local result = Comm.Whisper(message, session.address)
            if THROTTLED and result == THROTTLED then
                session.sendTimer = C_Timer.NewTimer(RETRY_DELAY, nextChunk)
                return
            end
            if acceptance then
                acceptance = nil
            else
                index = index + 1
            end
            if index > total then
                session.sent = true
                finishIfComplete(session)
            else
                session.sendTimer = C_Timer.NewTimer(SEND_GAP, nextChunk)
            end
        end
        session.sendTimer = C_Timer.NewTimer(0, nextChunk)
    end

    function api.Request(address, display, combination)
        if outgoing then
            ui.message(L.DUEL_PENDING)
            return
        end
        local who = playerAddress(address)
        if not who or partners[who] then return end
        serial = serial + 1
        local offered = ("%x-%x-%x"):format(math.floor(GetTime() * 1000) % 0x100000000, math.random(0, 0xffffff), serial)
        local session = { who = who, address = address, display = display or address, combination = combination, offered = offered }
        outgoing, partners[who] = session, session
        armTimeout(session, REQUEST_TIMEOUT, L.DUEL_NO_ANSWER)
        Comm.Whisper("Q" .. identity() .. tokenField(offered), address)
        ui.message(L.DUEL_SENT:format(session.display))
    end

    function api.Accept(session)
        if partners[session.who] ~= session or session == outgoing or session.accepted then return end
        transfer(session, "A" .. identity() .. tokenField(session.token))
    end

    function api.Decline(session)
        local who = session.who
        if partners[who] ~= session or session.accepted then return end
        close(session)
        local untilTime = GetTime() + BLOCK_TIME
        blocked[who] = untilTime
        C_Timer.After(BLOCK_TIME, function()
            if blocked[who] == untilTime then blocked[who] = nil end
        end)
        Comm.Whisper("N" .. tokenField(session.token), session.address)
    end

    local function chunk(session, body)
        if not session or not session.accepted or session.cards then return end
        local index, total, part = body:match("^(%d+)/(%d+)#(.*)$")
        index, total = tonumber(index), tonumber(total)
        if not index or not total or index < 1 or total > MAX_CHUNKS or index > total or #part > CHUNK then return end
        if (session.total and session.total ~= total) or session.chunks[index] then return end
        session.total = total
        session.chunks[index] = part
        session.received = session.received + 1
        if session.received ~= total then return end
        session.cards = ns.DuelCards.Parse(table.concat(session.chunks, "", 1, total))
        session.chunks = nil
        finishIfComplete(session)
    end

    Comm.On("QANDTCW", function(text, sender)
        if not ForeverDexDB then return end
        local who = playerAddress(sender)
        if not who then return end
        local kind, body = text:sub(1, 1), text:sub(2)
        local session = partners[who]
        if kind == "Q" then
            local token = parseToken(body)
            if ns.Settings.Get("duelRequests") == "refuse" or GetTime() < (blocked[who] or 0) then
                Comm.Whisper("N" .. tokenField(token), sender)
                return
            end
            if ui.promptVisible() then return end
            -- When both upgraded clients ask at once, keep the same request on each side.
            if session == outgoing and outgoing and not outgoing.accepted and token and token < outgoing.offered then
                close(outgoing)
                session = nil
            end
            if session then return end
            session = { who = who, address = sender, display = sender, token = token }
            readIdentity(body, session)
            local inCombat = (InCombatLockdown and InCombatLockdown())
                or (UnitAffectingCombat and UnitAffectingCombat("player"))
            if ns.Settings.Get("duelCombatRefuse") and inCombat then
                partners[who] = session
                api.Decline(session)
                ui.message(L.DUEL_AUTO_REFUSED:format(session.display))
                return
            end
            partners[who] = session
            armTimeout(session, Exchange.PROMPT_TIMEOUT + 1)
            ui.prompt(session)
        elseif kind == "A" or kind == "N" then
            if not session or session ~= outgoing or session.accepted then return end
            local token = parseToken(body)
            if token and token ~= session.offered then return end
            if kind == "N" then
                close(session)
                ui.message(L.DUEL_REFUSED:format(session.display))
                return
            end
            session.token, session.address = token, sender
            readIdentity(body, session)
            transfer(session)
            ui.message(L.DUEL_ACCEPTED:format(session.display))
        elseif kind == "D" then
            if session and not session.token then chunk(session, body) end
        elseif kind == "T" then
            local token, data = body:match("^([%x%-]+)|(.*)$")
            if session and token and token == session.token then chunk(session, data) end
        elseif kind == "W" then
            local token, message = body:match("^([%x%-]+)|(.*)$")
            if token then ui.combat(message, who, token) end
        else
            ui.combat(body, who)
        end
    end)
    return api
end

function Exchange.SendCombat(session, body)
    local prefix = session.token and ("W" .. session.token .. "|") or "C"
    Comm.Whisper(prefix .. body, session.address)
end
end)
