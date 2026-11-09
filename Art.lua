local _, ns = ...
local L = ns.L
local Art = {}
ns.Art = Art

-- Every resource comes from the WoW client. Each element first tries the
-- modern atlas, then an older texture, then a solid color, so an atlas
-- missing from the Forever client never shows up as a green square.
local registered, missing = {}, {}

local function hasAtlas(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
Art.HasAtlas = hasAtlas

local function register(specs)
    registered[#registered + 1] = specs
    return specs
end

function Art.Apply(texture, specs)
    for _, spec in ipairs(specs) do
        local applied = false
        if spec.atlas then
            if hasAtlas(spec.atlas) then
                texture:SetAtlas(spec.atlas)
                applied = true
            else
                missing[spec.atlas] = true
            end
        elseif spec.file then
            texture:SetTexture(spec.file)
            texture:SetTexCoord(unpack(spec.coords or { 0, 1, 0, 1 }))
            applied = true
        elseif spec.color then
            texture:SetColorTexture(unpack(spec.color))
            applied = true
        end
        if applied then
            texture:SetBlendMode(spec.blend or "BLEND")
            texture:SetVertexColor(unpack(spec.vertex or { 1, 1, 1, 1 }))
            return true
        end
    end
    return false
end

-- Painted background of the Adventure Guide selection screen (classic era).
Art.JOURNAL_BG = register {
    { atlas = "UI-EJ-Classic" },
    { file = "Interface\\EncounterJournal\\UI-EJ-Classic" },
}
-- Gold frame and highlight of the Adventure Guide instance buttons.
Art.CARD_FRAME = register {
    { atlas = "UI-EJ-DungeonButton-Up" },
}
Art.CARD_HIGHLIGHT = register {
    { atlas = "UI-EJ-DungeonButton-Highlight", blend = "ADD" },
    -- Subtle gold veil: the quest highlight stretched across the whole card was too yellow.
    { color = { 1, 0.82, 0.45, 0.12 }, blend = "ADD" },
}
-- Race list rows, borrowed from the Pet and Mount Journal.
Art.ROW_BG = register {
    { atlas = "PetList-ButtonBackground" },
    { color = { 0, 0, 0, 0.25 } },
}
Art.ROW_HIGHLIGHT = register {
    { atlas = "PetList-ButtonHighlight", blend = "ADD" },
    { file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD" },
}
Art.ROW_SELECTED = register {
    { atlas = "PetList-ButtonSelect" },
    { file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD", vertex = { 1, 0.82, 0.2, 1 } },
}
-- Parchment of the detail page.
Art.PARCHMENT = register {
    { atlas = "UI-EJ-JournalBG" },
    { atlas = "QuestBG-Parchment" },
    { file = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal" },
}

-- Vertical gradient (bottom to top) by default, or "HORIZONTAL" (left to right).
function Art.Gradient(texture, r, g, b, startAlpha, endAlpha, orientation)
    orientation = orientation or "VERTICAL"
    texture:SetColorTexture(1, 1, 1, 1)
    if CreateColor and texture.SetGradient then
        local ok = pcall(texture.SetGradient, texture, orientation,
            CreateColor(r, g, b, startAlpha), CreateColor(r, g, b, endAlpha))
        if ok then return end
    end
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha(orientation, r, g, b, startAlpha, r, g, b, endAlpha)
    else
        texture:SetColorTexture(r, g, b, (startAlpha + endAlpha) / 2)
    end
end

function Art.ClassIcon(texture, token)
    texture:SetShown(token ~= nil)
    if not token then return end
    local atlas = "classicon-" .. token:lower()
    if hasAtlas(atlas) then
        texture:SetAtlas(atlas)
        return
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords then
        texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        texture:SetTexCoord(unpack(coords))
    else
        texture:Hide()
    end
end

-- Round medallion in the style of a minimap button: dark background, masked icon, gold ring.
function Art.Medallion(parent, size)
    local medallion = CreateFrame("Frame", nil, parent)
    medallion:SetSize(31, 31)
    medallion:SetScale(size / 31)
    medallion.back = medallion:CreateTexture(nil, "BACKGROUND")
    medallion.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    medallion.back:SetVertexColor(0, 0, 0, 0.85)
    medallion.back:SetSize(20, 20)
    medallion.back:SetPoint("TOPLEFT", 7, -5)
    medallion.icon = medallion:CreateTexture(nil, "ARTWORK")
    medallion.icon:SetSize(20, 20)
    medallion.icon:SetPoint("TOPLEFT", 7, -5)
    local mask = medallion:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(medallion.icon)
    medallion.icon:AddMaskTexture(mask)
    medallion.ring = medallion:CreateTexture(nil, "OVERLAY")
    medallion.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    medallion.ring:SetSize(53, 53)
    medallion.ring:SetPoint("TOPLEFT")
    return medallion
end

-- Achievement progress bar: three-piece border and spark.
function Art.ProgressBar(parent, width, height, bordered)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.93, 0.66, 0.16)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.6)
    if bordered then
        local file = "Interface\\AchievementFrame\\UI-Achievement-ProgressBar-Border"
        local left = bar:CreateTexture(nil, "OVERLAY")
        left:SetTexture(file)
        left:SetWidth(16)
        left:SetPoint("TOPLEFT", -6, 5)
        left:SetPoint("BOTTOMLEFT", -6, -5)
        left:SetTexCoord(0, 0.0625, 0, 0.75)
        local right = bar:CreateTexture(nil, "OVERLAY")
        right:SetTexture(file)
        right:SetWidth(16)
        right:SetPoint("TOPRIGHT", 6, 5)
        right:SetPoint("BOTTOMRIGHT", 6, -5)
        right:SetTexCoord(0.812, 0.8745, 0, 0.75)
        local middle = bar:CreateTexture(nil, "OVERLAY")
        middle:SetTexture(file)
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
        middle:SetTexCoord(0.0625, 0.812, 0, 0.75)

        local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        spark:SetBlendMode("ADD")
        spark:SetSize(16, height * 2.4)
        bar:HookScript("OnValueChanged", function(self, value)
            local low, high = self:GetMinMaxValues()
            local fraction = high > low and (value - low) / (high - low) or 0
            spark:SetShown(fraction > 0 and fraction < 1)
            spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * fraction, 0)
        end)
        spark:Hide()
    end
    return bar
end

-- Crops an image to fill a box without distorting it.
-- The vertical crop stays slightly above center, where the scenery is.
local function crop(texture, left, right, top, bottom, sourceWidth, sourceHeight, boxWidth, boxHeight)
    local source, box = sourceWidth / sourceHeight, boxWidth / boxHeight
    if source > box then
        local fraction = box / source
        local start = (1 - fraction) / 2
        local width = right - left
        texture:SetTexCoord(left + width * start, left + width * (start + fraction), top, bottom)
    else
        local fraction = source / box
        local start = (1 - fraction) * 0.35
        local height = bottom - top
        texture:SetTexCoord(left, right, top + height * start, top + height * (start + fraction))
    end
end

-- Race backdrop from the dressing room: modern atlas, otherwise the main tile
-- of the old dressing room (256 × 255).
function Art.Scenery(texture, theme, boxWidth, boxHeight)
    if not theme or not theme[6] then return false end
    local atlas = "dressingroom-background-" .. theme[6]:lower()
    local info = hasAtlas(atlas) and C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if file and info.width and info.height and info.leftTexCoord then
        texture:SetTexture(file)
        crop(texture, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord,
            info.width, info.height, boxWidth, boxHeight)
        return true
    end
    missing[atlas] = true
    texture:SetTexture("Interface\\DressUpFrame\\DressUpBackground-" .. theme[6] .. "1")
    crop(texture, 0, 1, 0, 255 / 256, 256, 255, boxWidth, boxHeight)
    return true
end

-- Dungeon loading screen, cropped to the area without black bars
-- (same area as ForeverDungeonJournal: 0.02–0.98 × 0.24–0.82).
function Art.LoadingScreen(texture, theme, boxWidth, boxHeight)
    if not theme or not theme[8] then return false end
    -- A name refers to a screen in Glues\LoadingScreens, a number to a file ID.
    local file = theme[8]
    if type(file) == "string" then file = "Interface\\Glues\\LoadingScreens\\" .. file end
    texture:SetTexture(file)
    crop(texture, 0.02, 0.98, 0.24, 0.82, 0.96, 0.58, boxWidth, boxHeight)
    return true
end

-- Large image displayed small: the TRILINEAR filter keeps it smooth.
-- ElvUI disables pixel snapping on every texture; we restore its settings.
function Art.SmoothTexture(texture, file)
    local readable = texture.IsSnappingToPixelGrid and texture.GetTexelSnappingBias
    local snap, bias = readable and texture:IsSnappingToPixelGrid(), readable and texture:GetTexelSnappingBias()
    texture:SetTexture(file, nil, nil, "TRILINEAR")
    if readable then
        texture:SetSnapToPixelGrid(snap)
        texture:SetTexelSnappingBias(bias)
    end
end

-- Enlarges a game font while keeping its file (Friz Quadrata on this client).
function Art.Font(fontString, size, flags)
    local path = fontString:GetFont()
    if path then fontString:SetFont(path, size, flags or "") end
end

function Art.Sound(...)
    if not SOUNDKIT or not PlaySound then return end
    if ns.Settings and not ns.Settings.Get("sounds") then return end
    for i = 1, select("#", ...) do
        local id = SOUNDKIT[select(i, ...)]
        if id then
            PlaySound(id, "SFX")
            return
        end
    end
end

-- /foreverdex textures: lists the atlases this client does not have.
function Art.Report()
    local catalog = ns.Catalog
    for _, specs in ipairs(registered) do
        for _, spec in ipairs(specs) do
            if spec.atlas and not hasAtlas(spec.atlas) then missing[spec.atlas] = true end
        end
    end
    for _, race in ipairs(catalog.races) do
        if not hasAtlas(race.icon) then missing[race.icon] = true end
    end
    local names = {}
    for name in pairs(missing) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
        print(L.TEXTURES_OK)
        return
    end
    print(L.TEXTURES_MISSING:format(#names))
    for _, name in ipairs(names) do print("   · " .. name) end
    print(L.TEXTURES_FALLBACK)
end
