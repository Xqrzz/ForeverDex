local _, ns = ...

-- Addon messages ------------------------------------------------------------------------
--
-- Every ForeverDex message is whispered on a single prefix, invisible in chat. Its first
-- letter gives its type, and each type belongs to one file:
--   Q A N D C   comparison and combat (Duel.lua, Combat.lua)
--   P H         collectors detection (Presence.lua)
-- A type no file handles is ignored: an older version keeps working next to a newer one.
-- See "Comparison compatibility" in CONTRIBUTING.md before changing a message.

local Comm = {}
ns.Comm = Comm

local PREFIX = "ForeverDex"
local readable = ns.Util.Readable

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local handlers = {} -- [type letter] = handler

-- handler(text, sender) receives the whole message, type letter included, and the
-- sender's address as the game gives it (the one replies must go to).
function Comm.On(types, handler)
    for letter in types:gmatch(".") do
        assert(not handlers[letter], "ForeverDex: message type " .. letter .. " handled twice")
        handlers[letter] = handler
    end
end

-- Returns the game's result (Enum.SendAddonMessageResult on recent clients).
function Comm.Whisper(message, target)
    return C_ChatInfo.SendAddonMessage(PREFIX, message, "WHISPER", target)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
    if not readable(prefix) or prefix ~= PREFIX then return end
    if not readable(text) or not readable(sender) then return end
    local handler = handlers[text:sub(1, 1)]
    if handler then handler(text, sender) end
end)
