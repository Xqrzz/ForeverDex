local _, ns = ...
ns.Module(function()
local L, Collection, Settings, Util = ns.L, ns.Collection, ns.Settings, ns.Util
local Guilds = {}
ns.Guilds = Guilds
local readable = Util.Readable

-- Guild captures ---------------------------------------------------------------
--
-- A guild is captured on its own, with a right-click on the portrait ball: the
-- character's card is not touched. ForeverDexDB.guilds is a list kept in the order
-- the player chose on the Guilds page (GuildsUI.lua); a new guild goes to the end.
-- A guild is identified by its name and faction.

-- Paler and darker than the game's faction colors, so a banner reads as cloth.
local FACTION_COLORS = {
    Horde = { 0.62, 0.11, 0.09 },
    Alliance = { 0.15, 0.29, 0.62 },
}
local NEUTRAL_COLOR = { 0.42, 0.39, 0.35 }
-- Chat colors of the faction names.
local FACTION_TEXT = { Horde = "ffff4d40", Alliance = "ff4da6ff" }

-- Achievement-like steps shown on the guild notification bar.
local MILESTONES = { 5, 10, 25, 50, 100, 250 }

local listeners = {}

local function list()
    ForeverDexDB.guilds = ForeverDexDB.guilds or {}
    return ForeverDexDB.guilds
end
Guilds.List = list

function Guilds.ID(name, faction)
    return name .. "|" .. (faction or "")
end

function Guilds.Count()
    return ForeverDexDB and ForeverDexDB.guilds and #ForeverDexDB.guilds or 0
end

-- Count per faction: Alliance, Horde.
function Guilds.FactionCounts()
    local alliance, horde = 0, 0
    for _, guild in ipairs(list()) do
        if guild.faction == "Alliance" then alliance = alliance + 1 end
        if guild.faction == "Horde" then horde = horde + 1 end
    end
    return alliance, horde
end

function Guilds.Find(id)
    for index, guild in ipairs(list()) do
        if guild.id == id then return index, guild end
    end
end

function Guilds.Color(faction)
    return FACTION_COLORS[faction] or NEUTRAL_COLOR
end

function Guilds.FactionName(faction)
    if faction == "Horde" then return FACTION_HORDE end
    if faction == "Alliance" then return FACTION_ALLIANCE end
    return L.GUILD_NO_FACTION
end

-- Guild name in the color of its faction, for chat and tooltips.
function Guilds.ColoredName(guild)
    return ("|c%s<%s>|r"):format(FACTION_TEXT[guild.faction] or "ffffd100", guild.name)
end

-- Faction crest of the target frame (present on every client), else a guild tabard.
function Guilds.PaintCrest(texture, faction)
    if faction == "Horde" or faction == "Alliance" then
        texture:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
        texture:SetTexCoord(0, 0.625, 0, 0.625)
    else
        texture:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Emblem of the guild on the tabard sheet (GuildEmblemsLG_01): its real one when the
-- game gave it at the capture, otherwise one picked from its name, always the same.
-- Only the first ten rows of the sheet are used: they are sure to be filled.
local EMBLEMS = 160
function Guilds.EmblemIndex(guild)
    if guild.emblem then return guild.emblem end
    local hash = 0
    for i = 1, #guild.name do hash = (hash * 31 + guild.name:byte(i)) % 2147483647 end
    return hash % EMBLEMS
end

-- Real emblem of the target's guild, on clients that can read another player's tabard.
local function readEmblem(unit)
    if not C_GuildInfo or not C_GuildInfo.GetGuildTabardInfo then return end
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, unit)
    if not ok or type(info) ~= "table" then return end
    local style = info.emblemStyle
    if readable(style) and type(style) == "number" and style >= 0 and style < EMBLEMS then return style end
end

-- Next milestone above the count, for the notification bar.
function Guilds.Milestone(count)
    for _, step in ipairs(MILESTONES) do
        if count <= step then return step end
    end
    return count
end

local memberCounts, indexedCards
function Guilds.InvalidateMembers()
    memberCounts, indexedCards = nil, nil
end

-- Index once per collection change, also shared by the guild achievement.
function Guilds.MemberCount(guild)
    local cards = ForeverDexDB.cards
    if indexedCards ~= cards or not memberCounts then
        memberCounts, indexedCards = {}, cards
        for _, entry in pairs(cards) do
            local id = entry.guildID
            if id then memberCounts[id] = (memberCounts[id] or 0) + 1 end
        end
    end
    return memberCounts[guild.id] or 0
end

local function guildOf(member)
    if not member or not member.guildID then return end
    local faction = member.guildID:match("|([^|]+)$")
    local combination = ns.Catalog.byKey[member.key]
    return {
        id = member.guildID,
        name = member.guild,
        faction = faction,
        member = member.name,
        memberClass = combination and combination.token,
    }
end

-- Reuse the player data already read for the portrait.
function Guilds.TargetState(member)
    local guild = guildOf(member)
    if not guild then return end
    return guild, Guilds.Find(guild.id) ~= nil
end

function Guilds.OnChanged(handler)
    listeners[#listeners + 1] = handler
end

-- isNew: a capture (thrown from the portrait unless noThrow), otherwise a change of
-- order or a deletion.
local function changed(guild, isNew)
    for _, handler in ipairs(listeners) do handler(guild, isNew) end
end

local lastLine
function Guilds.Announce(guild)
    ns.Share.RevealCapture(guild)
    if not Settings.Get("chatMessage") then return end
    local lines = L.GUILD_CAPTURE_LINES
    local index = math.random(#lines)
    if #lines > 1 and index == lastLine then index = index % #lines + 1 end
    lastLine = index
    print(L.CHAT_PREFIX .. lines[index]:format(Guilds.ColoredName(guild)))
end

-- The portrait ball (right-click), its orb, the Guilds page button, the key binding
-- and "/fdex guild" all come here.
function Guilds.Capture()
    local member = Collection.ReadTarget()
    if not member then return end
    local guild = guildOf(member)
    if not guild then
        print(L.CHAT_PREFIX .. L.GUILD_NONE_CHAT:format(member.name))
        return
    end
    if Guilds.Find(guild.id) then
        print(L.CHAT_PREFIX .. L.GUILD_ALREADY_CHAT:format(Guilds.ColoredName(guild)))
        return
    end
    guild.emblem = readEmblem("target")
    Collection.StampCapture(guild)
    local guilds = list()
    guilds[#guilds + 1] = guild
    ns.Share.PrepareCapture(guild, true, true)
    changed(guild, true)
end

-- Moves a guild to another place of the list (1 = first).
function Guilds.Move(id, target)
    local guilds = list()
    local from, guild = Guilds.Find(id)
    if not from then return end
    target = math.max(1, math.min(#guilds, target))
    if target == from then return end
    table.remove(guilds, from)
    table.insert(guilds, target, guild)
    changed(guild, false)
end

function Guilds.Delete(id)
    local index, guild = Guilds.Find(id)
    if not index then return end
    table.remove(list(), index)
    print(L.GUILD_DELETED:format(Guilds.ColoredName(guild)))
    changed(guild, false)
end

StaticPopupDialogs["FOREVERDEX_DELETE_GUILD"] = {
    text = L.GUILD_DELETE_PROMPT,
    button1 = L.DELETE,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, id) Guilds.Delete(id) end,
}
end)
