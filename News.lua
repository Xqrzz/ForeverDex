local _, ns = ...
ns.Module(function()
local L, Art, Home = ns.L, ns.Art, ns.Home
local News = {}
ns.News = News

-- Window listing every change of the release, opened from the banner of the home page,
-- with /fdex news, or after the login message of an update. It is built on its first
-- opening only: a player who never reads it pays nothing for it.

local WIDTH, HEIGHT, PAD = 440, 400, 20
local TEXT_X, GAP = 16, 10
local MEDIA = "Interface\\AddOns\\ForeverDex\\Media\\"

local window, child, lines

-- Height of the list, once the client can measure the lines; nil until then.
local function measure()
    local height = 0
    for i, line in ipairs(lines) do
        local lineHeight = line:GetStringHeight()
        if not lineHeight or lineHeight <= 0 then return end
        height = height + lineHeight + (i > 1 and GAP or 0)
    end
    return height
end

local function fit()
    local height = measure()
    if height then child:SetHeight(height + 4) end
end

local function build()
    window = CreateFrame("Frame", "ForeverDexNews", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    -- Escape closes it, like the game's windows.
    tinsert(UISpecialFrames, window:GetName())
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })

    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", PAD, -PAD + 2)
    Art.SmoothTexture(icon, MEDIA .. "Icon")
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    title:SetText(L.HOME_NEWS)
    local version = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetTextColor(0.78, 0.71, 0.58)
    version:SetText("ForeverDex" .. L.SEPARATOR .. L.HOME_VERSION:format(Home.NEWS_VERSION))
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Gold rule under the header, fading out at both ends.
    local rule = CreateFrame("Frame", nil, window)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", PAD, -64)
    rule:SetPoint("TOPRIGHT", -PAD, -64)
    local left = rule:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", rule, "BOTTOM")
    Art.Gradient(left, 1, 0.82, 0.4, 0.1, 0.8, "HORIZONTAL")
    local right = rule:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPLEFT", rule, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    Art.Gradient(right, 1, 0.82, 0.4, 0.8, 0, "HORIZONTAL")

    -- The list scrolls with the wheel or the bar when the release is long.
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -76)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, PAD)
    local width = WIDTH - 2 * PAD - 22
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)

    lines = {}
    for i, item in ipairs(L.HOME_NEWS_LINES) do
        local line = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetJustifyH("LEFT")
        line:SetJustifyV("TOP")
        line:SetWidth(width - TEXT_X - 4)
        line:SetSpacing(2)
        line:SetTextColor(0.93, 0.9, 0.82)
        if i == 1 then
            line:SetPoint("TOPLEFT", TEXT_X, -2)
        else
            line:SetPoint("TOPLEFT", lines[i - 1], "BOTTOMLEFT", 0, -GAP)
        end
        line:SetText(item)
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(6, 6)
        dot:SetColorTexture(1, 0.82, 0.35)
        if dot.SetRotation then dot:SetRotation(math.rad(45)) end
        dot:SetPoint("CENTER", line, "TOPLEFT", -9, -6)
        lines[i] = line
    end
    fit()
    -- Lines are only measured reliably once on screen.
    window:SetScript("OnShow", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, fit) end
    end)
end

function News.Show()
    if not window then build() end
    window:Show()
    window:Raise()
    if C_Timer and C_Timer.After then C_Timer.After(0, fit) end
end
end)
