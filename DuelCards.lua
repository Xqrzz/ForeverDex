local _, ns = ...
ns.Module(function()
local Catalog = ns.Catalog
local DuelCards = {}
ns.DuelCards = DuelCards

local MAX_NAME_BYTES = 48
-- What one comparison can carry: 200 messages of 220 characters, in every version since
-- 1.8.2. Standard cards always fit; favorite bonus cards fill the rest.
DuelCards.MAX_PAYLOAD = 200 * 220

-- Comparisons and combats use the standard journal and the favorites, bonus ones included.
-- favorites: the other player's version knows this rule (see DuelExchange.lua); an older
-- one only gets standard cards for combat.
function DuelCards.Shared(entry, favorites)
    if not entry or type(entry.key) ~= "string" then return false end
    if Catalog.byKey[entry.key] then return true end
    if not (favorites and entry.favorite) then return false end
    local slot = Catalog.slotByKey[entry.key]
    return slot ~= nil and not slot.pet
end

-- Both the collection and a chosen combat card use key[@combination]=name.
-- A combat card can be a bonus card, whatever its number.
function DuelCards.Encode(entry)
    local slot = Catalog.SlotForKey(entry.key)
    if not slot or slot.pet or type(entry.name) ~= "string" then return end
    local name = entry.name:gsub("[~=@#|%c]", "")
    if name == "" then return end
    if #name > MAX_NAME_BYTES then
        local cut = MAX_NAME_BYTES
        while cut > 0 do
            local nextByte = name:byte(cut + 1)
            if nextByte < 0x80 or nextByte >= 0xC0 then break end
            cut = cut - 1
        end
        name = name:sub(1, cut)
    end
    local combination = Catalog.byKey[entry.combination] and ("@" .. entry.combination) or ""
    return entry.key .. combination .. "=" .. name
end

function DuelCards.Decode(text)
    local key, combination, name = text:match("^([^=@]+)@?([^=]*)=([^\t]+)")
    local slot = key and Catalog.SlotForKey(key)
    if not slot or slot.pet or #name > MAX_NAME_BYTES or name:find("[|%c]") then return end
    return { key = key, name = name, combination = Catalog.byKey[combination] and combination or nil }
end

-- The standard cards, then the favorite bonus cards as long as they fit.
function DuelCards.Serialize(entries)
    local parts, size = {}, 0
    for _, slot in ipairs(Catalog.slots) do
        local entry = entries[slot.key]
        local item = DuelCards.Shared(entry, true) and DuelCards.Encode(entry)
        if item then
            local added = #item + (#parts > 0 and 1 or 0)
            if size + added > DuelCards.MAX_PAYLOAD then break end
            parts[#parts + 1], size = item, size + added
        end
    end
    return table.concat(parts, "~")
end

-- favorites: the sender only sends favorite bonus cards. An older version sends all of
-- its bonus cards, so they are left out.
function DuelCards.Parse(payload, favorites)
    local cards = {}
    for item in payload:gmatch("[^~]+") do
        local entry = DuelCards.Decode(item)
        if entry and (Catalog.byKey[entry.key] or favorites) then
            entry.favorite = not Catalog.byKey[entry.key] or nil
            cards[entry.key] = entry
        end
    end
    return cards
end
end)
