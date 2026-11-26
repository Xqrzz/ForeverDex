local _, ns = ...

-- Small helpers shared by every file. Unlike the modules, they are defined as soon as
-- this file runs: the first one in ForeverDex.toc.
local Util = {}
ns.Util = Util

-- The client can mark a value as secret, notably in combat: the addon must check it
-- before any comparison or concatenation. nil counts as unreadable.
function Util.Readable(value)
    return (not issecretvalue or not issecretvalue(value)) and value ~= nil
end

-- Calls a game function and keeps its first result only when it can be read.
function Util.Safe(func, ...)
    if not func then return nil end
    local ok, value = pcall(func, ...)
    if ok and Util.Readable(value) then return value end
end

-- Forever uses First-Surname in whispers and can display First Surname elsewhere.
-- Keep the surname, including when the client appends the local realm after it.
function Util.PlayerAddress(name)
    if not Util.Readable(name) or type(name) ~= "string" then return end
    local address = name:match("^%s*(.-)%s*$"):gsub("%s+", "-"):lower()
    if address == "" then return end
    local character, realm = address:match("^(.+%-.+)%-([^%-]+)$")
    if not character then return address end
    local localRealm = Util.Safe(GetNormalizedRealmName)
    if localRealm and realm == localRealm:lower() then return character end
    return address
end

-- Uses the game's whisper format when available, falling back to the full unit name.
function Util.UnitAddress(unit)
    local name = Util.Safe(GetUnitName, unit, true)
    if name == "" or name == UNKNOWNOBJECT then name = nil end
    if name and name:find("[%s%-]") then return name end
    local first, surname = UnitFullName(unit)
    if not Util.Readable(first) or first == "" or first == UNKNOWNOBJECT then return name end
    if Util.Readable(surname) and surname ~= "" then return first .. "-" .. surname end
    return name or first
end

-- A template missing from this client must not prevent the addon from loading: the
-- frame is then built on the fallback template (or none). The second result tells
-- whether the requested template was used.
function Util.CreateFrame(frameType, name, parent, template, fallback)
    if template then
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, true end
    end
    return CreateFrame(frameType, name, parent, fallback), false
end
