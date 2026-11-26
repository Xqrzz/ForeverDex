local _, ns = ...
ns.Module(function()
local Catalog = ns.Catalog
local DuelCards = {}
ns.DuelCards = DuelCards

local MAX_NAME_BYTES = 48

-- Both the collection and a chosen combat card use key[@combination]=name.
function DuelCards.Encode(entry)
    local slot = Catalog.slotByKey[entry.key]
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
    local slot = key and Catalog.slotByKey[key]
    if not slot or slot.pet or #name > MAX_NAME_BYTES or name:find("[|%c]") then return end
    return { key = key, name = name, combination = Catalog.byKey[combination] and combination or nil }
end

function DuelCards.Serialize(entries)
    local parts = {}
    for _, slot in ipairs(Catalog.slots) do
        local entry = entries[slot.key]
        local item = entry and DuelCards.Encode(entry)
        if item then parts[#parts + 1] = item end
    end
    return table.concat(parts, "~")
end

function DuelCards.Parse(payload)
    local cards = {}
    for item in payload:gmatch("[^~]+") do
        local entry = DuelCards.Decode(item)
        if entry then cards[entry.key] = entry end
    end
    return cards
end
end)
