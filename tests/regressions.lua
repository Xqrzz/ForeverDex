-- Run from the addon directory with Lua 5.1 or LuaJIT.
local function noop() end

local function environment(globals)
    local env = setmetatable(globals or {}, { __index = _G })
    local ns = { Locales = {}, Module = function(init) init() end }
    local function loadModule(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)("ForeverDex", ns)
    end
    loadModule("Util.lua")
    loadModule("SavedData.lua")
    loadModule("Locales/enUS.lua")
    ns.L = ns.Locales.enUS
    return ns, env, loadModule
end

local function frames()
    local frame = {}
    return setmetatable(frame, {
        __index = function(_, key)
            if key == "GetFrameLevel" or key == "GetStringWidth" then return function() return 1 end end
            if key:match("^Create") then return function() return frame end end
            return noop
        end,
    })
end

local function testCards()
    local prompt
    local ns, env, loadModule = environment({
        StaticPopupDialogs = {},
        time = function() return 100 end,
        print = noop,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitFullName = function() return "Nouveau", "Test" end,
        UnitRace = function() return nil, nil, 1 end,
        UnitClass = function() return nil, "WARRIOR", 1 end,
        UnitSex = function() return 2 end,
        UnitLevel = function() return 30 end,
        GetGuildInfo = noop,
        C_CreatureInfo = { GetClassInfo = function(id) return { classFile = tostring(id), className = tostring(id) } end },
    })
    ns.Art = { HasAtlas = function() return false end }
    ns.Settings = { Get = function(key) return key == "confirmReplace" end }
    ns.Share = { PrepareCapture = noop, RevealCapture = noop }
    ns.Dialog = { Show = function(which, _first, _second, data) prompt = { which, data } end }

    loadModule("Catalog.lua")
    loadModule("Collection.lua")
    loadModule("Guilds.lua")
    loadModule("Achievements.lua")
    local cards = {}
    env.ForeverDexDB = ns.SavedData.Prepare({ version = 1, cards = cards })
    local captures = 0
    ns.Collection.Initialize(noop, function() captures = captures + 1 end)
    local standard = ns.Catalog.slots[1].key
    local old = { id = "Ancien Test", name = "Ancien Test", key = standard }
    cards[standard] = old

    ns.Collection.Capture()
    assert(prompt[1] == "FOREVERDEX_REPLACE")
    ns.Collection.ToggleFavorite(old)
    env.StaticPopupDialogs[prompt[1]].OnAccept(nil, prompt[2])
    assert(cards[standard] == old, "a stale confirmation replaced a favorite")

    ns.Collection.ToggleFavorite(old)
    ns.Collection.Capture()
    local replacement = { id = "Autre Test", name = "Autre Test", key = standard }
    cards[standard] = replacement
    env.StaticPopupDialogs[prompt[1]].OnAccept(nil, prompt[2])
    env.StaticPopupDialogs.FOREVERDEX_DELETE.OnAccept(nil, { key = standard, entry = old })
    assert(cards[standard] == replacement, "a stale confirmation changed a different card")

    ns.Collection.Capture()
    env.StaticPopupDialogs[prompt[1]].OnAccept(nil, prompt[2])
    assert(cards[standard].name == "Nouveau Test" and cards["bonus:1"] == replacement and captures == 1)
    ns.Collection.ToggleFavorite(cards[standard])
    assert(captures == 1, "a favorite toggle was recorded as a capture")

    local bonuses = ns.Catalog.bonusSlots
    assert(#bonuses == 139 and #ns.Catalog.slots == 251)
    for i = 1, 138 do
        local key = "bonus:" .. i
        assert(bonuses[i].key == key)
        cards[key] = { id = key }
    end
    local slot = ns.Collection.FindBonusSlot({ id = "unused" })
    assert(slot.key == "bonus:139")
    ns.Collection.ToggleFavorite(cards[standard])
    env.UnitFullName = function() return "Dernier", "Test" end
    ns.Collection.Capture()
    assert(prompt[1] == "FOREVERDEX_REPLACE")
    cards[slot.key] = { id = slot.key }
    env.StaticPopupDialogs[prompt[1]].OnAccept(nil, prompt[2])
    assert(cards[standard].name == "Nouveau Test", "a full bonus list changed the confirmed outcome")
    assert(ns.Collection.FindBonusSlot({ id = "unused" }) == nil)
    for _, achievement in ipairs(ns.Achievements.list) do
        if achievement.id == "bonus" then
            local _, goal = achievement.progress({ bonus = 39 })
            assert(goal == 39, "the existing bonus achievement changed")
            return
        end
    end
    error("the bonus achievement is missing")
end

local function testReveal()
    local frame, timers = frames(), {}
    local function finishTimers()
        for _, timer in ipairs(timers) do
            if timer[1] <= 4.5 then timer[2]() end
        end
        timers = {}
    end
    local ns, _, loadModule = environment({
        UIParent = frame,
        CreateFrame = function() return frame end,
        C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end },
    })
    local mode, revealed = "full", {}
    ns.Settings = { Get = function(key) if key == "animation" then return mode end end }
    ns.Art = { ProgressBar = function() return frame end, Sound = noop, SmoothTexture = noop, Gradient = noop, Font = noop }
    ns.Collection, ns.Guilds = { Announce = noop }, { Announce = noop }
    loadModule("CaptureVisuals.lua")
    local function capture(kind, x)
        ns.CaptureVisuals.Play({
            [kind] = {},
            fromX = x,
            fromY = 10,
            onReveal = function() revealed[#revealed + 1] = kind end,
        })
    end
    capture("entry", 10)
    capture("guild", 10)
    finishTimers()
    assert(table.concat(revealed, ",") == "entry,guild")
    revealed = {}
    mode = "quick"
    capture("guild", 10)
    mode = "off"
    capture("entry", 10)
    finishTimers()
    assert(table.concat(revealed, ",") == "guild,entry")
end

local function testShare()
    local frame, timers, sent, listeners = frames(), {}, {}, {}
    local channelEvent
    frame.SetScript = function(_, name, callback)
        if name == "OnEvent" then channelEvent = callback end
    end
    local values = { shareCaptures = true, shareCaptureChannel = "group", shareCooldown = 0 }
    local roster = { player = "Player-1-Owner", party1 = "Player-1-First" }
    local guild = "Guilde A"
    local ns, _, loadModule = environment({
        LE_PARTY_CATEGORY_HOME = 1,
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        GetNumGroupMembers = function() return 2 end,
        UnitGUID = function(unit) return roster[unit] end,
        IsInGuild = function() return true end,
        GetGuildInfo = function() return guild end,
        GetTime = function() return 100 end,
        CreateFrame = function() return frame end,
        C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end },
        SendChatMessage = function(_, chatType) sent[#sent + 1] = chatType end,
    })
    ns.Settings = {
        Get = function(key) return values[key] end,
        AddPage = function() return frame end,
        OnChange = function(listener) listeners[#listeners + 1] = listener end,
        Builder = setmetatable({}, { __index = function() return noop end }),
    }
    ns.Catalog = { StandardProgress = function() return 0, 112 end, slotByKey = {} }
    loadModule("Share.lua")
    local entry = { key = "1:1:2", name = "Nom Fictif" }
    local release = ns.Share.Capture(entry, true)
    roster.party1 = "Player-1-Second"
    channelEvent(nil, "GROUP_ROSTER_UPDATE")
    roster.party1 = "Player-1-First"
    release()
    assert(#sent == 0, "an announcement went to a different party")

    release = ns.Share.Capture(entry, true)
    for _, enabled in ipairs({ false, true }) do
        values.shareCaptures = enabled
        for _, listener in ipairs(listeners) do listener("shareCaptures") end
    end
    release()
    assert(#sent == 0, "an announcement survived disabling and re-enabling the option")

    release = ns.Share.Capture(entry, true)
    release()
    for _, timer in ipairs(timers) do timer() end
    assert(#sent == 1 and sent[1] == "PARTY", "a valid announcement must be sent exactly once")
    values.shareAchievements, values.shareAchievementChannel = true, "guild"
    release = ns.Share.Achievements({ { name = "Succès", points = 10 } })
    guild = "Guilde B"
    channelEvent(nil, "PLAYER_GUILD_UPDATE")
    release()
    assert(#sent == 1, "an achievement was announced to a different guild")
    ns.Share.Achievements({ { name = "Succès", points = 10 } })()
    assert(#sent == 2 and sent[2] == "GUILD")
end

local function testAddresses()
    local receive
    local ns, _, loadModule = environment({
        GetNormalizedRealmName = function() return "Forever" end,
        C_ChatInfo = { RegisterAddonMessagePrefix = noop },
        CreateFrame = function()
            return { RegisterEvent = noop, SetScript = function(_, _, callback) receive = callback end }
        end,
    })
    assert(ns.Util.PlayerAddress("Nom Famille-Forever") == ns.Util.PlayerAddress("Nom-Famille"))
    assert(ns.Util.PlayerAddress("Nom-Famille") ~= ns.Util.PlayerAddress("Nom-Autre"))
    loadModule("Comm.lua")
    local received = 0
    ns.Comm.On("Q", function() received = received + 1 end)
    receive(nil, "CHAT_MSG_ADDON", "ForeverDex", "Q", "WHISPER", "Nom-Famille")
    receive(nil, "CHAT_MSG_ADDON", "ForeverDex", "Q", "PARTY", "Nom-Famille")
    assert(received == 1, "the dispatcher must accept only whispers")
end

local function loadCatalog(ns, loadModule)
    ns.Art = { HasAtlas = function() return false end }
    loadModule("Catalog.lua")
end

local function testSavedGuilds()
    local ns, env, loadModule = environment({
        StaticPopupDialogs = {},
        C_CreatureInfo = { GetClassInfo = function(id) return { classFile = tostring(id), className = tostring(id) } end },
    })
    local alliance = { id = "Homonymes|Alliance", name = "Homonymes", faction = "Alliance" }
    local horde = { id = "Homonymes|Horde", name = "Homonymes", faction = "Horde" }
    local neutral = { id = "Homonymes|", name = "Homonymes" }
    local original = {
        version = 1, view = { races = "invalid" }, settings = false,
        guilds = { [1] = alliance, [3] = horde, [4] = neutral },
        cards = {
            ["1:1:2"] = { name = "Un Joueur", guild = "Homonymes" },
            ["2:1:2"] = { name = "Une Joueuse", guild = "Homonymes" },
            ["1:1:3"] = { name = "Autre Personne", zone = "Homonymes" },
            ["bonus:1"] = { name = "Faction inconnue", guild = "Homonymes" },
            ["bonus:2"] = false,
        },
    }
    env.ForeverDexDB = ns.SavedData.Prepare(original)
    assert(env.ForeverDexDB == original and type(original.settings) == "table" and original.view.races == nil)
    assert(#original.guilds == 3 and original.guilds[2] == horde and original.cards["bonus:2"] == nil)
    assert(type(ns.SavedData.Prepare({ version = 1 }).cards) == "table")
    local newer = { version = 99, cards = { legacy = "new format" } }
    local preserved, compatible = ns.SavedData.Prepare(newer)
    assert(preserved == newer and compatible == false and newer.cards.legacy == "new format" and newer.settings == nil)

    loadCatalog(ns, loadModule)
    ns.Settings = { Get = noop }
    loadModule("Collection.lua")
    loadModule("Guilds.lua")
    ns.Collection.Initialize(noop)
    assert(original.version == 2 and original.cards["1:1:2"].guildID == alliance.id)
    assert(original.cards["2:1:2"].guildID == horde.id and original.cards["bonus:1"].guildID == neutral.id)
    local scans = 0
    env.pairs = function(value)
        if value == original.cards then scans = scans + 1 end
        return pairs(value)
    end
    assert(ns.Guilds.MemberCount(alliance) == 1 and ns.Guilds.MemberCount(horde) == 1 and ns.Guilds.MemberCount(neutral) == 1)
    assert(scans == 1, "checking several banners scanned the collection more than once")
    original.cards["1:1:2"] = nil
    ns.Guilds.InvalidateMembers()
    assert(ns.Guilds.MemberCount(alliance) == 0 and scans == 2)
    local rows = ns.Catalog.Query(original.cards, "", 2, 1, { races = {}, classes = {}, sexes = {} }, horde.id)
    assert(#rows == 1 and rows[1].entry == original.cards["2:1:2"])
    ns.Collection.ReadTarget = function() error("target was read twice") end
    local targetGuild = ns.Guilds.TargetState(original.cards["2:1:2"])
    assert(targetGuild.id == horde.id)

    -- A guild saved without a faction follows its member's card after the migration.
    local unread = { id = "Sans Faction|", name = "Sans Faction", member = "Une Joueuse" }
    local single = { id = "Seule|", name = "Seule" }
    local clash = { id = "Prise|", name = "Prise", member = "Un Joueur" }
    local taken = { id = "Prise|Alliance", name = "Prise", faction = "Alliance" }
    local legacy = ns.SavedData.Prepare({
        version = 1, guilds = { unread, single, clash, taken },
        cards = {
            ["1:1:2"] = { name = "Un Joueur", guild = "Prise" },
            ["2:1:2"] = { name = "Une Joueuse", guild = "Sans Faction" },
            ["1:1:3"] = { name = "Autre Joueur", guild = "Sans Faction" },
            ["2:1:3"] = { name = "Seul Membre", guild = "Seule" },
        },
    })
    env.ForeverDexDB = legacy
    ns.Collection.Initialize(noop)
    assert(unread.id == "Sans Faction|Horde" and unread.faction == "Horde", "the member's faction was not used")
    assert(single.id == "Seule|Horde" and single.faction == "Horde")
    assert(clash.id == "Prise|", "a guild took the id of one already captured")
    ns.Guilds.InvalidateMembers()
    assert(ns.Guilds.MemberCount(unread) == 1 and ns.Guilds.MemberCount(single) == 1)
end

local function testChallenge()
    local slot = { key = "1:1:2", sex = true }
    local ns, env, loadModule = environment({
        date = os.date,
        time = function(parts)
            if parts and parts.hour == 0 then assert(parts.isdst == nil, "midnight inherited the wrong DST value") end
            return os.time(parts)
        end,
        ForeverDexDB = { cards = {} },
    })
    ns.Catalog = { byKey = { [slot.key] = slot }, standardSlots = { slot } }
    loadModule("Home.lua")
    for _, day in ipairs({ { month = 3, day = 29, hours = 23 }, { month = 10, day = 25, hours = 25 } }) do
        local midnight = os.time({ year = 2026, month = day.month, day = day.day, hour = 0 })
        local afternoon = os.time({ year = 2026, month = day.month, day = day.day, hour = 12 })
        local entry = { key = slot.key, capturedAt = midnight - 1 }
        env.ForeverDexDB.cards[slot.key] = entry
        assert(not ns.Home.Challenge(afternoon).done)
        entry.capturedAt = midnight
        local challenge = ns.Home.Challenge(afternoon)
        assert(challenge.done)
        if os.getenv("TZ") == "Europe/Paris" then
            assert(afternoon - midnight + challenge.resetsIn == day.hours * 3600)
        end
        ns.Home.OnCapture(entry, false)
        ns.Home.OnCapture(entry, false)
    end
    assert(ns.Home.ChallengeLog().count == 2 and ns.Home.ChallengeLog().improved)
end

local function testPresence()
    local frame, handlers, sent = frames(), {}, {}
    local clock, ticker, report = 120
    frame.SetScript = function(_, name, callback) handlers[name] = callback end
    local names = { player = "Notre-Personnage", nameplate1 = "Nom-Famille" }
    local ns, _, loadModule = environment({
        UIParent = frame,
        CreateFrame = function() return frame end,
        C_Timer = { NewTicker = function(_, callback) ticker = callback; return { Cancel = noop } end },
        GetTime = function() return clock end,
        UnitIsPlayer = function() return true end,
        UnitIsUnit = function() return false end,
        UnitCanAttack = function() return false end,
        UnitFactionGroup = function() return "Alliance" end,
        CheckInteractDistance = function() return true end,
        GetUnitName = function(unit) return names[unit] end,
        UnitFullName = noop,
        wipe = function(t) for key in pairs(t) do t[key] = nil end end,
        DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) report = line end },
    })
    local receive, apply
    local values = { presenceShow = true, presenceAnnounce = true, presenceRange = 30, presenceDuration = 0 }
    ns.Settings = { Get = function(key) return values[key] end, OnChange = function(callback) apply = callback end }
    ns.Art = { SmoothTexture = noop }
    ns.PresenceIcon = { look = {}, ByKey = {}, CHOICES = {}, RestyleAll = noop }
    ns.Comm = {
        On = function(_, callback) receive = callback end,
        Whisper = function(message, who) sent[#sent + 1] = { message, who } end,
    }
    loadModule("Presence.lua")
    apply(nil)
    handlers.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    ticker()
    assert(#sent == 1 and sent[1][2] == "Nom-Famille")
    receive("H", "Nom-Autre")
    ns.Presence.Report()
    assert(not report:find("Nom-Autre", 1, true))
    receive("H\tfutur", "Nom-Famille")
    ns.Presence.Report()
    assert(report:find("Nom-Famille", 1, true), "an answer with an added field was ignored")
    receive("P\tfutur\tq", "Nom-Discret")
    receive("Pnope", "Nom-Invalide")
    ns.Presence.Report()
    assert(not report:find("Nom-Discret", 1, true) and not report:find("Nom-Invalide", 1, true))
    assert(sent[#sent][1] == "H" and sent[#sent][2] == "Nom-Discret", "a quiet ping with added fields got no answer")
    local before = #sent
    ns.Presence.ToggleDemo()
    clock = 121
    receive("P", "Nom-Famille")
    ticker()
    assert(#sent == before, "the demo replied to a ping")
end

local function testExchange()
    local now, timers, users, wire = 100, {}, {}, {}
    local function newTimer(delay, run)
        local timer = { at = now + delay, run = run, Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = timer
        return timer
    end
    local function advance(untilTime)
        while true do
            local first, index
            for i, timer in ipairs(timers) do
                if timer.at <= untilTime and (not first or timer.at < first.at) then first, index = timer, i end
            end
            if not first then break end
            table.remove(timers, index)
            now = first.at
            if not first.cancelled then first.run() end
        end
        now = untilTime
    end
    local function peer(address)
        local ns, env, loadModule = environment({
            C_CreatureInfo = { GetClassInfo = function(id) return { classFile = tostring(id), className = tostring(id) } end },
            GetTime = function() return now end,
            GetNormalizedRealmName = function() return "Forever" end,
            UnitRace = function() return nil, nil, 1 end,
            UnitClass = function() return nil, nil, 1 end,
            UnitSex = function() return 2 end,
            C_Timer = { NewTimer = newTimer, After = newTimer },
            Enum = { SendAddonMessageResult = { AddonMessageThrottle = 1 } },
            ForeverDexDB = { cards = {} },
        })
        local state = { names = {}, messages = {}, done = {} }
        ns.Collection = { PlayerName = function() return address end }
        ns.Settings = { Get = noop }
        ns.Comm = {
            On = function(_, receive) state.receive = receive end,
            Whisper = function(message, target)
                assert(#message <= 255)
                wire[#wire + 1] = { message, address, target }
                if state.throttled and message:sub(1, 1) == "T" then return 1 end
                newTimer(0, function() if users[target] then users[target].receive(message, address) end end)
            end,
        }
        loadCatalog(ns, loadModule)
        loadModule("DuelCards.lua")
        loadModule("DuelExchange.lua")
        state.api = ns.DuelExchange.New({
            prompt = function(session) state.prompt = session end,
            promptVisible = function() return false end,
            message = function(message) state.messages[#state.messages + 1] = message end,
            completed = function(session, cards) state.done[#state.done + 1] = { session, cards } end,
            combat = function(message, who, token) state.combat = { message, who, token } end,
        })
        state.entries, state.catalog, state.exchange = env.ForeverDexDB.cards, ns.Catalog, ns.DuelExchange
        users[address] = state
        return state
    end

    local a, b = peer("Nom-Famille"), peer("Nom-Autre")
    for _, slot in ipairs(a.catalog.slots) do
        a.entries[slot.key] = { key = slot.key, name = "Carte de test " .. slot.key }
    end
    a.api.Request("Nom-Autre")
    advance(now)
    b.api.Accept(assert(b.prompt))
    advance(now + 20)
    assert(#a.done == 1 and #b.done == 1 and b.done[1][2]["bonus:139"])
    local token = a.done[1][1].token
    assert(token and token == b.done[1][1].token)
    a.exchange.SendCombat(a.done[1][1], "1|S")
    advance(now)
    assert(b.combat[1] == "1|S" and b.combat[3] == token)

    local legacyParts = {}
    users["Client-Ancien"] = { receive = function(message, sender)
        if message:sub(1, 1) == "Q" then
            a.receive("A1:1:2=Client Ancien\tcombat", "Client-Ancien")
            a.receive("D1/1#bonus:39@1:1:2=Carte Ancienne", "Client-Ancien")
        elseif message:sub(1, 1) == "D" then
            local index, piece = message:match("^D(%d+)/%d+#(.*)$")
            legacyParts[tonumber(index)] = piece
        elseif message:sub(1, 1) == "C" then
            assert(sender == "Nom-Famille")
        else
            error("an upgraded packet was sent to a legacy peer")
        end
    end }
    a.api.Request("Client-Ancien")
    advance(now + 20)
    local legacyPayload = table.concat(legacyParts)
    local familiarCards = 0
    for key in legacyPayload:gmatch("([%d:bonus]+)=") do
        local bonus = key:match("^bonus:(%d+)$")
        if not bonus or tonumber(bonus) <= 39 then familiarCards = familiarCards + 1 end
    end
    assert(familiarCards == 151 and a.done[2][1].token == nil and a.done[2][2]["bonus:39"])
    a.exchange.SendCombat(a.done[2][1], "S")
    advance(now)

    a.throttled = true
    a.api.Request("Nom-Autre")
    advance(now)
    local stalled = assert(b.prompt)
    b.api.Accept(stalled)
    advance(now + 121)
    local sentCount = #wire
    advance(now + 5)
    assert(#wire == sentCount and #a.done == 2 and #b.done == 1)
    assert(a.messages[#a.messages]:find("timed out", 1, true))
    a.throttled = false
    a.api.Request("Nom-Autre")
    advance(now)
    assert(b.prompt ~= stalled)
    b.api.Accept(b.prompt)
    advance(now + 20)
    assert(#a.done == 3 and #b.done == 2 and a.done[3][1].token ~= token)
end

local function testFight()
    local ns, _, loadModule = environment()
    loadModule("DuelFight.lua")
    local Fight = ns.DuelFight
    local fight = Fight.New(2)
    local mine, theirs = { key = "1:1:2" }, { key = "bonus:139" }
    assert(not Fight.Vote(fight, "T", true))
    assert(Fight.ReceiveCard(fight, theirs) and not Fight.ReceiveCard(fight, theirs))
    assert(Fight.Pick(fight, mine) and not Fight.Pick(fight, mine))
    assert(Fight.CardToSend(fight) == mine and not Fight.CardToSend(fight))
    assert(Fight.Reveal(fight) and Fight.Vote(fight, "O", true))
    assert(Fight.OpenVote(fight) and Fight.Vote(fight, "T"))
    assert(Fight.Resolve(fight) and fight.phase == "result" and not Fight.Ready(fight))
end

testCards()
testReveal()
testShare()
testAddresses()
testSavedGuilds()
testChallenge()
testPresence()
testExchange()
testFight()
print("ForeverDex regression checks passed")
