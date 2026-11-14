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

-- First name only, without the realm: "Name-Realm" or "Name Surname" give "Name".
-- On Forever, the game does not always write the rest of the name the same way.
function Util.ShortName(name)
    return name:match("^[^%-%s]+") or name
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
