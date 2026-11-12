local addon, ns = ...

-- Saved data is available after ADDON_LOADED.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon then return end
        local saved = ForeverDexDB and ForeverDexDB.settings
        ns.ApplyLanguage(saved and saved.language)
        for _, load in ipairs(ns.Modules) do load() end
        -- Achievements first: the refresh then shows them already unlocked.
        ns.Collection.Initialize(function(...)
            ns.Achievements.OnCollectionChanged(...)
            ns.UI.Refresh(...)
        end)
        -- What the collection already deserves is granted without alerts.
        ns.Achievements.Check(true)
        ns.UI.RestoreView()
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
        -- Welcome message, once per session (not on every loading screen).
        self.greeted = true
        local version = C_AddOns and C_AddOns.GetAddOnMetadata(addon, "Version")
        print(("|cff63ded1ForeverDex|r%s%sby |cffffd100Xqrz|r"):format(version and (" v" .. version) or "", ns.L.SEPARATOR))
        ns.UI.UpdateTarget()
    -- Unit events also cover the party and NPCs. Only the target can
    -- change the capture button or the portrait shown in the gallery.
    elseif (event ~= "UNIT_NAME_UPDATE" and event ~= "UNIT_PORTRAIT_UPDATE") or name == "target" then
        ns.UI.UpdateTarget()
    end
end)

ns.Module(function()
local L = ns.L

SLASH_FOREVERDEX1 = "/foreverdex"
SLASH_FOREVERDEX2 = "/fdex"
-- Names of the key bindings declared in Bindings.xml.
BINDING_HEADER_FOREVERDEX = "ForeverDex"
BINDING_NAME_FOREVERDEX_CAPTURE = L.BINDING_CAPTURE
BINDING_NAME_FOREVERDEX_COMPARE = L.BINDING_COMPARE
BINDING_NAME_FOREVERDEX_TOGGLE = L.BINDING_TOGGLE
-- "/foreverdex textures" lists the atlases missing from this client.
-- "/foreverdex compare" offers the comparison to the target (usable in a macro).
-- "/foreverdex capture" captures the target, like the ball (key binding, macro).
-- "/foreverdex collectors" (or "presence") lists the nearby players known to have ForeverDex,
-- "/foreverdex collectors demo" shows the icon above every friendly player nearby.
-- "/foreverdex home" opens the home page (daily challenge, news, statistics).
-- "/foreverdex achievements" (or "hf") opens the achievements page.
-- "/foreverdex share" opens the settings of the announcements to other players.
SlashCmdList.FOREVERDEX = function(message)
    if message and message:lower():match("^%s*capt") then
        ns.Collection.Capture()
    elseif message and message:lower():match("^%s*home%s*$") then
        ns.UI.Show("home")
    elseif message and (message:lower():match("^%s*achiev") or message:lower():match("^%s*hf%s*$")) then
        ns.UI.ShowAchievements()
    elseif message and message:lower():match("^%s*textures") then
        ns.Art.Report()
    elseif message and message:lower():match("^%s*compar") then
        ns.Duel.Request()
    elseif message and (message:lower():match("^%s*presen") or message:lower():match("^%s*collec")) then
        if message:lower():match("demo") then
            ns.Presence.ToggleDemo()
        elseif message:lower():match("debug") then
            ns.Presence.Debug()
        else
            ns.Presence.Report()
        end
    elseif message and message:lower():match("^%s*duel") then
        ns.Duel.ToggleTrace()
    elseif message and message:lower():match("^%s*share") then
        ns.Share.OpenSettings()
    elseif message and message:lower():match("^%s*opt") then
        ns.Settings.Open()
    else
        ns.UI.Toggle()
    end
end

-- Minimap button: same template as the usual addon buttons
-- (dark background, icon, gold ring). Drag it to move it around the map.
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
-- The ForeverDex orb, slightly larger than a square icon since it is round.
icon:SetTexture("Interface\\AddOns\\ForeverDex\\Media\\Icon")
icon:SetSize(21, 21)
icon:SetPoint("TOPLEFT", 5, -5)
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Angle around the minimap, in degrees (0 = right, 90 = top).
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

-- Burst when the capture ball arrives: gold star and a small bounce of the icon.
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
end)
