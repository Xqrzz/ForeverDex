local addon, ns = ...
local L = ns.L

-- Les sauvegardes sont disponibles après ADDON_LOADED.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon then return end
        ns.Collection.Initialize(ns.UI.Refresh)
        ns.PlaceMinimapButton()
        ns.Settings.ApplyAll()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("UNIT_NAME_UPDATE")
        self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    elseif event == "PLAYER_ENTERING_WORLD" and not self.greeted then
        -- Message d’accueil, une seule fois par session (pas à chaque écran de chargement).
        self.greeted = true
        local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local version = getMetadata and getMetadata(addon, "Version")
        print(("|cff63ded1ForeverDex|r%s · by |cffffd100Xqrz|r"):format(version and (" v" .. version) or ""))
        ns.UI.UpdateTarget()
    -- Les événements d’unité concernent aussi le groupe et les PNJ. Seule la cible
    -- peut modifier le bouton de capture ou le portrait affiché dans la galerie.
    elseif (event ~= "UNIT_NAME_UPDATE" and event ~= "UNIT_PORTRAIT_UPDATE") or name == "target" then
        ns.UI.UpdateTarget()
    end
end)

SLASH_FOREVERDEX1 = "/foreverdex"
-- « /foreverdex textures » liste les atlas absents de ce client.
-- « /foreverdex comparer » propose la comparaison à la cible (utilisable en macro).
SlashCmdList.FOREVERDEX = function(message)
    if message and message:lower():match("^%s*textures") then
        ns.Art.Report()
    elseif message and message:lower():match("^%s*compar") then
        ns.Duel.Request()
    elseif message and message:lower():match("^%s*duel") then
        ns.Duel.ToggleTrace()
    elseif message and message:lower():match("^%s*opt") then
        ns.Settings.Open()
    else
        ns.UI.Toggle()
    end
end

-- Bouton de la mini-carte : même gabarit que les boutons d’addons habituels
-- (fond sombre, icône, anneau doré). Il se déplace en le glissant autour de la carte.
local minimapButton = CreateFrame("Button", "ForeverDexMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")
local background = minimapButton:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)
local icon = minimapButton:CreateTexture(nil, "ARTWORK")
-- L’orbe de ForeverDex, un peu plus grande qu’une icône carrée : elle est ronde.
icon:SetTexture("Interface\\AddOns\\ForeverDex\\Media\\Icon")
icon:SetSize(21, 21)
icon:SetPoint("TOPLEFT", 5, -5)
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Angle autour de la mini-carte, en degrés (0 = à droite, 90 = en haut).
local DEFAULT_ANGLE = 225
local function place(angle)
    local radians = math.rad(angle)
    local radius = Minimap:GetWidth() / 2 + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end
place(DEFAULT_ANGLE)

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function follow()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    if ForeverDexDB then ForeverDexDB.minimapAngle = angle end
    place(angle)
end
minimapButton:SetScript("OnDragStart", function(self)
    if ns.Settings.Get("minimapLock") then return end
    GameTooltip:Hide()
    self:SetScript("OnUpdate", follow)
end)
minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

minimapButton:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then ns.Settings.Open() else ns.UI.Toggle() end
end)
minimapButton:SetScript("OnEnter", function(self)
    if self:GetScript("OnUpdate") then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverDex")
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_OPTIONS, 1, 1, 1)
    if not ns.Settings.Get("minimapLock") then GameTooltip:AddLine(L.MINIMAP_DRAG, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Éclat à l’arrivée de la balle de capture : étoile dorée et petit rebond de l’icône.
local glow = minimapButton:CreateTexture(nil, "OVERLAY", nil, 1)
glow:SetTexture("Interface\\Cooldown\\star4")
glow:SetBlendMode("ADD")
glow:SetVertexColor(1, 0.85, 0.35)
glow:SetSize(64, 64)
glow:SetPoint("CENTER", icon, "CENTER")
glow:SetAlpha(0)
local glowAnimation = glow:CreateAnimationGroup()
local glowIn = glowAnimation:CreateAnimation("Alpha")
glowIn:SetFromAlpha(0)
glowIn:SetToAlpha(1)
glowIn:SetDuration(0.1)
glowIn:SetOrder(1)
local glowOut = glowAnimation:CreateAnimation("Alpha")
glowOut:SetFromAlpha(1)
glowOut:SetToAlpha(0)
glowOut:SetDuration(0.6)
glowOut:SetOrder(2)
local glowTurn = glowAnimation:CreateAnimation("Rotation")
glowTurn:SetDegrees(-90)
glowTurn:SetDuration(0.7)
glowTurn:SetOrder(1)

local bounce = icon:CreateAnimationGroup()
local grow = bounce:CreateAnimation("Scale")
local settle = bounce:CreateAnimation("Scale")
if grow.SetScaleFrom then
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(1.35, 1.35)
    settle:SetScaleFrom(1, 1)
    settle:SetScaleTo(1 / 1.35, 1 / 1.35)
else
    grow:SetScale(1.35, 1.35)
    settle:SetScale(1 / 1.35, 1 / 1.35)
end
grow:SetDuration(0.12)
grow:SetOrder(1)
grow:SetSmoothing("OUT")
settle:SetDuration(0.3)
settle:SetOrder(2)
settle:SetSmoothing("IN_OUT")

function minimapButton:Flash()
    glowAnimation:Stop()
    bounce:Stop()
    glowAnimation:Play()
    bounce:Play()
end

ns.MinimapButton = minimapButton
ns.Settings.OnChange(function(key)
    if key == nil or key == "minimapShow" then
        minimapButton:SetShown(ns.Settings.Get("minimapShow"))
    end
end)
ns.PlaceMinimapButton = function()
    place(ForeverDexDB and ForeverDexDB.minimapAngle or DEFAULT_ANGLE)
end
