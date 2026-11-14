local _, ns = ...
ns.Module(function()
local L, Art, Settings, Collection, CaptureVisuals = ns.L, ns.Art, ns.Settings, ns.Collection, ns.CaptureVisuals
local PortraitCapture = {}
ns.PortraitCapture = PortraitCapture

-- Capture ball on the target portrait ---------------------------------------------
--
-- A ball on the target frame (Blizzard, ElvUI or another interface) captures the
-- target in one click; a small checked orb says the player is already collected.
-- UI.lua decides what the target is worth (PortraitCapture.Update); this file finds
-- the frame, places the markers and shows them.

-- Region where the ball sits, and the target frame holding it (set by Attach).
local capturePortrait, attachedHost, attachedRegion

-- Target frame of another interface (EllesmereUI, oUF layouts…): the frame showing
-- the "target" unit whose parent is on screen. Blizzard's frame is skipped, and so
-- are frames left under a hidden parent. The result is kept until it stops matching;
-- a failed search is only tried again after a short delay.
local otherTarget, lastSearch
local function showsTarget(frame)
    if frame == TargetFrame or (frame.IsForbidden and frame:IsForbidden()) then return false end
    local unit = frame.unit
    if unit ~= "target" and frame.GetAttribute then unit = frame:GetAttribute("unit") end
    local parent = frame:GetParent()
    return unit == "target" and parent ~= nil and parent:IsVisible() and frame:GetWidth() > 40
end

local function findOtherTarget()
    if otherTarget and showsTarget(otherTarget) then return otherTarget end
    otherTarget = nil
    local now = GetTime()
    if lastSearch and now - lastSearch < 2 then return end
    lastSearch = now
    local best, bestArea = nil, 0
    local frame = EnumerateFrames()
    while frame do
        if showsTarget(frame) then
            local area = frame:GetWidth() * frame:GetHeight()
            if area > bestArea then best, bestArea = frame, area end
        end
        frame = EnumerateFrames(frame)
    end
    otherTarget = best
    return best
end

-- Displayed target frame and region where the ball sits. ElvUI creates its own after
-- the addon loads and reparents Blizzard's to a hidden parent, so the choice is
-- made again on every update. Without an ElvUI portrait, we aim at the whole frame.
local function targetAnchor()
    local elvFrame, blizzard = _G.ElvUF_Target, TargetFrame
    if elvFrame and not (blizzard and blizzard:GetParent() == UIParent) then
        local portrait = elvFrame.Portrait
        return elvFrame, portrait and portrait:IsShown() and portrait or elvFrame
    end
    -- Blizzard's frame is hidden while there is a target: another interface replaced it.
    local replaced = not blizzard or blizzard:GetParent() ~= UIParent
        or (UnitExists("target") and not blizzard:IsShown())
    local other = replaced and findOtherTarget()
    if other then
        local portrait = other.Portrait
        return other, portrait and portrait.IsShown and portrait:IsShown() and portrait or other
    end
    if not blizzard then return end
    local container = blizzard.TargetFrameContainer
    -- Forever uses the modern container. Some frames still expose the old portrait.
    local portrait = (container and container.Portrait) or TargetFramePortrait
    if portrait then return blizzard, portrait end
end

local function createPortraitCapture()
    local badge = CreateFrame("Button", nil, UIParent)
    badge:SetSize(22, 22)
    badge:SetScript("OnClick", Collection.Capture)
    badge:Hide()
    local badgeBall = CaptureVisuals.DrawBadge(badge)
    -- Gray checked ball: the combination is already taken, a click would replace it.
    local badgeCheck = badge:CreateTexture(nil, "OVERLAY")
    badgeCheck:SetSize(14, 14)
    badgeCheck:SetPoint("BOTTOMRIGHT", 4, -3)
    badgeCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    badgeCheck:Hide()
    -- The ball breathes gently to signal a name to capture.
    local pulse = badge:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local grow = pulse:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(1.15, 1.15)
    else
        grow:SetScale(1.15, 1.15)
    end
    grow:SetDuration(0.6)
    grow:SetSmoothing("IN_OUT")
    -- Only a card still to discover makes the ball breathe.
    function badge:SetHolder(holder)
        self.holder = holder
        badgeBall:SetDesaturated(holder ~= nil)
        badgeCheck:SetShown(holder ~= nil)
        if holder then
            pulse:Stop()
        elseif self:IsShown() and not pulse:IsPlaying() then
            pulse:Play()
        end
    end
    badge:SetScript("OnShow", function(self)
        if not self.holder then pulse:Play() end
    end)
    badge:SetScript("OnHide", function() pulse:Stop() end)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("ForeverDex")
        if self.holder then
            GameTooltip:AddLine(L.COMBINATION_OWNED:format(self.holder.name), 1, 1, 1)
            GameTooltip:AddLine(L.CLICK_TO_REPLACE, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L.ADD_TARGET, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Small checked orb: this player is already in the collection. It is gray
    -- when another player holds the card for this combination.
    local owned = CreateFrame("Frame", nil, UIParent)
    owned:SetSize(18, 18)
    owned:EnableMouse(true)
    owned:Hide()
    local orb = owned:CreateTexture(nil, "ARTWORK")
    orb:SetAllPoints()
    Art.SmoothTexture(orb, CaptureVisuals.BALL)
    local check = owned:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("BOTTOMRIGHT", 5, -4)
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    function owned:SetHolder(holder)
        self.holder = holder
        orb:SetDesaturated(holder ~= nil)
    end
    owned:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("ForeverDex")
        GameTooltip:AddLine(self.holder and L.COMBINATION_OWNED:format(self.holder.name) or L.ALREADY_ADDED, 1, 1, 1)
        GameTooltip:Show()
    end)
    owned:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return badge, owned
end

local capture, owned = createPortraitCapture()
capture:Hide()
owned:Hide()

-- Attaches the ball and orb to the current target frame; returns false if there is none.
local function attachCapture()
    local host, region = targetAnchor()
    capturePortrait = region
    if not host then return false end
    if host == attachedHost and region == attachedRegion then return true end
    attachedHost, attachedRegion = host, region
    for _, marker in ipairs({ capture, owned }) do
        marker:SetParent(host)
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", region, "TOPRIGHT", -6, -6)
        -- Wide margin: ElvUI puts its text on raised layers.
        marker:SetFrameLevel(host:GetFrameLevel() + 120)
    end
    return true
end

-- Shows the ball or the orb for the target. current: card of its combination (or of
-- the pet), alreadySaved: that card is this very player, holder: the other player
-- holding the card, if any. Returns whether the ball is shown.
local function update(anchored, target, current, alreadySaved, holder)
    -- Setting: always (new card or replacement), empty card only, or never.
    local buttonMode = Settings.Get("portraitButton")
    local showCapture = anchored and target ~= nil and not alreadySaved
    if buttonMode == "missing" then showCapture = anchored and target ~= nil and current == nil end
    if buttonMode == "off" then showCapture = false end
    capture:SetHolder(holder)
    capture:SetShown(showCapture)
    -- Without a clickable ball, the orb still shows that the combination is taken.
    owned:SetHolder(holder)
    owned:SetShown(anchored and current ~= nil and not showCapture and Settings.Get("ownedMarker") or false)
    return showCapture
end

PortraitCapture.Attach = attachCapture
PortraitCapture.Update = update
-- The ball (where a capture throw starts), the region it sits on (where the throw
-- lands) and the target frame.
PortraitCapture.Ball = capture
function PortraitCapture.Region() return capturePortrait end
function PortraitCapture.Host() return attachedHost end
end)
