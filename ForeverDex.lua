local addon, ns = ...

-- Saved data is available after ADDON_LOADED.
-- Saved data from an earlier session: a version change is then an update.
local installed = false

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addon then return end
        installed = ForeverDexDB ~= nil
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
        -- Only the target matters: the game then does not send these events for the
        -- crowds of a city. The handler still checks the unit, in case of a client
        -- without RegisterUnitEvent.
        for _, unitEvent in ipairs({ "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE" }) do
            if self.RegisterUnitEvent then
                self:RegisterUnitEvent(unitEvent, "target")
            else
                self:RegisterEvent(unitEvent)
            end
        end
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    elseif event == "PLAYER_ENTERING_WORLD" and not self.greeted then
        -- Welcome message, once per session (not on every loading screen). Right after
        -- an update, and only once, it also points to the news of the release.
        self.greeted = true
        local version = C_AddOns and C_AddOns.GetAddOnMetadata(addon, "Version")
        local seen = ForeverDexDB.seenVersion
        local updated = version ~= nil and version ~= seen and (seen ~= nil or installed)
        if version then ForeverDexDB.seenVersion = version end
        local news = updated and (ns.L.SEPARATOR .. ns.L.NEWS_LOGIN:format("|cffffd100/fdex news|r")) or ""
        print(("|cff63ded1ForeverDex|r%s%sby |cffffd100Xqrz|r%s"):format(version and (" v" .. version) or "",
            ns.L.SEPARATOR, news))
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
BINDING_NAME_FOREVERDEX_CAPTURE_GUILD = L.BINDING_CAPTURE_GUILD
BINDING_NAME_FOREVERDEX_COMPARE = L.BINDING_COMPARE
BINDING_NAME_FOREVERDEX_TOGGLE = L.BINDING_TOGGLE
-- "/foreverdex compare" offers the comparison to the target (usable in a macro).
-- "/foreverdex capture" captures the target, like the ball (key binding, macro).
-- "/foreverdex guild" captures the target's guild only, like a right-click on the ball.
-- "/foreverdex guilds" opens the Guilds page.
-- "/foreverdex collectors" (or "presence") lists the nearby players known to have ForeverDex,
-- "/foreverdex collectors demo" shows the icon above every friendly player nearby.
-- "/foreverdex home" opens the home page (daily challenge, news, statistics).
-- "/foreverdex news" lists the changes of the release.
-- "/foreverdex achievements" (or "hf") opens the achievements page.
-- "/foreverdex share" opens the settings of the announcements to other players.
SlashCmdList.FOREVERDEX = function(message)
    if message and message:lower():match("^%s*capt") then
        ns.Collection.Capture()
    elseif message and message:lower():match("^%s*guilds%s*$") then
        ns.UI.Show("guilds")
    elseif message and message:lower():match("^%s*guild%s*$") then
        ns.Guilds.Capture()
    elseif message and message:lower():match("^%s*home%s*$") then
        ns.UI.Show("home")
    elseif message and message:lower():match("^%s*news%s*$") then
        ns.News.Show()
    elseif message and (message:lower():match("^%s*achiev") or message:lower():match("^%s*hf%s*$")) then
        ns.UI.ShowAchievements()
    elseif message and message:lower():match("^%s*compar") then
        ns.Duel.Request()
    elseif message and (message:lower():match("^%s*presen") or message:lower():match("^%s*collec")) then
        if message:lower():match("demo") then
            ns.Presence.ToggleDemo()
        else
            ns.Presence.Report()
        end
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
ns.Art.SmoothTexture(icon, "Interface\\AddOns\\ForeverDex\\Media\\Icon")
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

-- Game menu (Escape, or Start with the controller): a ForeverDex button right under
-- "AddOns", as EllesmereUI does it on this client. It is a button of our own with the
-- menu's template, placed each time the menu lays out: the game's own buttons and
-- their list are never touched. Shown in controller mode only, and never in combat.
local menuButton
if GameMenuFrame and GameMenuFrame.buttonPool and GameMenuFrame.Layout then
    menuButton = CreateFrame("Button", "ForeverDexGameMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
    menuButton:SetSize(200, 35)
    menuButton:SetText("ForeverDex")
    menuButton:Hide()
    menuButton:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        HideUIPanel(GameMenuFrame)
        ns.UI.Show(ns.UI.Mode() or "home")
    end)

    local GAP, STEP = 4, 39
    -- The menu grows down to its lowest button, whoever added it.
    local function fitHeight()
        local top, lowest = GameMenuFrame:GetTop(), nil
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            local bottom = button:GetBottom()
            if bottom and (not lowest or bottom < lowest) then lowest = bottom end
        end
        local own = menuButton:IsShown() and menuButton:GetBottom()
        if own and (not lowest or own < lowest) then lowest = own end
        if top and lowest then GameMenuFrame:SetHeight(top - lowest + 26) end
    end

    hooksecurefunc(GameMenuFrame, "Layout", function()
        -- Only in controller mode: with the mouse, the minimap icon is at hand and
        -- the menu stays exactly the game's.
        if InCombatLockdown() or not ns.PopupMenu.GamepadInterface() then
            menuButton:Hide()
            return
        end
        -- Under "AddOns", else under the last button.
        local anchor, last
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            if button:GetText() == ADDONS then anchor = button end
            local bottom = button:GetBottom()
            if bottom and (not last or bottom < last:GetBottom()) then last = button end
        end
        anchor = anchor or last
        if not anchor then return end
        local width, height = anchor:GetSize()
        if width and width > 0 then menuButton:SetSize(width, height) end
        -- The buttons under the anchor move down by one row to make room.
        local anchorBottom = anchor:GetBottom()
        if anchorBottom then
            for button in GameMenuFrame.buttonPool:EnumerateActive() do
                local top = button:GetTop()
                if button ~= anchor and top and top < anchorBottom + 2 then
                    local point, relative, relativePoint, x, y = button:GetPoint(1)
                    if point then
                        button:ClearAllPoints()
                        button:SetPoint(point, relative, relativePoint, x, (y or 0) - STEP)
                    end
                end
            end
        end
        menuButton:ClearAllPoints()
        menuButton:SetPoint("TOP", anchor, "BOTTOM", 0, -GAP)
        menuButton:Show()
        -- Once every addon has placed its buttons (EllesmereUI adds some too).
        C_Timer.After(0, fitHeight)
    end)
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
