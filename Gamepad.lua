local _, ns = ...
ns.Module(function()
local L, PopupMenu = ns.L, ns.PopupMenu
local Gamepad = {}
ns.Gamepad = Gamepad

-- Controller navigation in the ForeverDex window ------------------------------------------
--
-- With the controller on, the open window takes the controller buttons (out of combat:
-- the game forbids it during a fight, the virtual cursor then remains). A gold frame
-- marks the chosen element; the D-pad moves it to the nearest element in that
-- direction, A/B/X/Y act on it, the shoulders change side tab and the triggers turn the
-- page. Select moves the focus between the window and the character. A bar under the
-- window shows the buttons and what they do right now.
--
-- Each page tells what can be chosen: Gamepad.RegisterPage(mode, provider), where
-- provider() returns { targets = { target… }, back = function, default = frame,
-- direction = function }. A target is { frame = f, A = { label, action }, X = …,
-- Y = … }; without A, A clicks the frame, and noA = true leaves A unused (a sheet that
-- only shows its tooltip). direction(dir), when given, takes the D-pad over (moving a
-- banner) and returns the frame to choose next; backLabel names what B does then.
-- The ForeverDex menu (PopupMenu.lua) and the ForeverDex dialogs take the buttons first
-- while they are open. The sticks are left to the game: the character
-- can still move with the window open.

local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.12
local DIRECTIONS = { PADDUP = "up", PADDDOWN = "down", PADDLEFT = "left", PADDRIGHT = "right" }
local FACE = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y" }
-- ForeverDex's own key bindings still work while the window has the buttons.
local BINDINGS = {
    FOREVERDEX_TOGGLE = "", FOREVERDEX_CAPTURE = "capture",
    FOREVERDEX_CAPTURE_GUILD = "guild", FOREVERDEX_COMPARE = "compare",
}

local window, options
local providers = {}
local focus -- chosen frame
local current -- what the page offers right now (last provider result)

-- Gold frame around the chosen element, and its slow glow.
local marker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
marker:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
marker:SetBackdropBorderColor(1, 0.82, 0.25, 1)
marker:Hide()
local glow = marker:CreateTexture(nil, "BACKGROUND")
glow:SetPoint("TOPLEFT", 3, -3)
glow:SetPoint("BOTTOMRIGHT", -3, 3)
glow:SetColorTexture(1, 0.82, 0.3, 0.12)
glow:SetBlendMode("ADD")
local breathe = glow:CreateAnimationGroup()
breathe:SetLooping("BOUNCE")
local fadeAnimation = breathe:CreateAnimation("Alpha")
fadeAnimation:SetFromAlpha(1)
fadeAnimation:SetToAlpha(0.3)
fadeAnimation:SetDuration(0.8)
breathe:Play()

-- Button hints, under the window.
local hints = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
hints:SetHeight(26)
hints:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
hints:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
hints:SetBackdropBorderColor(0.6, 0.5, 0.3)
hints:Hide()
local hintText = hints:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hintText:SetPoint("CENTER")

-- The game's name of a controller button: an icon on clients that have them, else
-- the letter.
local FALLBACK = {
    PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
    PADLTRIGGER = "LT", PADRTRIGGER = "RT",
}
local glyphs = {}
local function glyph(button)
    if glyphs[button] then return glyphs[button] end
    local text = GetBindingText and GetBindingText(button, true)
    if type(text) ~= "string" or text == "" or text == button then text = FALLBACK[button] or button end
    if not text:find("|", 1, true) then text = ("|cffffd100%s|r"):format(text) end
    glyphs[button] = text
    return text
end

-- Input --------------------------------------------------------------------------------------

local input = CreateFrame("Frame", nil, UIParent)
input:SetFrameStrata("DIALOG")
input:Hide()
local capturing = false
-- Select (left of Start) moves the focus between the window and the character, as the
-- game does with its own windows (a quest giver's, for instance). Without the focus,
-- every button but Select goes on to the game. The window opens with the focus.
local focused = true
local FOCUS_BUTTON = "PADBACK"

local function setCapture(on)
    if on == capturing then return end
    if on and InCombatLockdown() then return end
    local ok = pcall(input.EnableGamePadButton, input, on)
    if not ok then return end
    capturing = on
    input:SetShown(on)
    if not on then
        marker:Hide()
        hints:Hide()
        input.held = nil
    end
end

local function visible(frame)
    return frame and frame:IsVisible() and (not frame.IsEnabled or frame:IsEnabled())
end

-- The dialog of ForeverDex on screen, if any: it takes the buttons first.
local function dialog()
    for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
        local popup = _G["StaticPopup" .. i]
        if popup and popup:IsShown() and type(popup.which) == "string" and popup.which:find("^FOREVERDEX_") then
            return popup
        end
    end
end

local function dialogButton(popup, index)
    local button = popup["button" .. index] or _G[popup:GetName() .. "Button" .. index]
    if button and button:IsVisible() and button:IsEnabled() then return button end
end

local function leave(frame)
    local script = frame and frame:GetScript("OnLeave")
    if script then script(frame) end
end

local function enter(frame)
    local script = frame and frame:GetScript("OnEnter")
    if script then script(frame) end
end

local function findTarget(frame)
    for _, target in ipairs(current and current.targets or {}) do
        if target.frame == frame then return target end
    end
end

local updateHints

local function setFocus(frame)
    if frame ~= focus then
        leave(focus)
        focus = frame
        if frame and capturing and focused then enter(frame) end
    end
    if frame and capturing and focused then
        marker:SetParent(frame)
        marker:SetFrameLevel(frame:GetFrameLevel() + 20)
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 5)
        marker:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
        marker:Show()
    else
        marker:Hide()
    end
    updateHints()
end

-- Reads the page again; keeps the chosen element when it is still there.
local function refreshTargets()
    local provider = window and options and providers[options.mode()]
    current = provider and provider() or { targets = {} }
    local kept = {}
    for _, target in ipairs(current.targets) do
        if visible(target.frame) or (target.frame and target.frame:IsVisible() and target.always) then
            kept[#kept + 1] = target
        end
    end
    current.targets = kept
    if focus and findTarget(focus) then
        setFocus(focus)
        return
    end
    local default = current.default and findTarget(current.default) and current.default
    setFocus(default or (kept[1] and kept[1].frame))
end

-- The nearest element in a direction, ahead of the chosen one: distance along the
-- direction counts once, distance across it twice.
local function center(frame)
    local x, y = frame:GetCenter()
    if not x then return end
    local scale = frame:GetEffectiveScale()
    return x * scale, y * scale
end

local function move(direction)
    if not focus then return refreshTargets() end
    local x, y = center(focus)
    if not x then return end
    local best, bestScore
    for _, target in ipairs(current.targets) do
        if target.frame ~= focus then
            local tx, ty = center(target.frame)
            if tx then
                local dx, dy = tx - x, ty - y
                local along, across
                if direction == "up" then along, across = dy, dx
                elseif direction == "down" then along, across = -dy, dx
                elseif direction == "left" then along, across = -dx, dy
                else along, across = dx, dy end
                if along > 4 then
                    local score = along + 2 * math.abs(across)
                    if not bestScore or score < bestScore then best, bestScore = target.frame, score end
                end
            end
        end
    end
    if best then
        if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
        setFocus(best)
    end
end

local function act(face)
    local target = focus and findTarget(focus)
    if not target then return false end
    local action = target[face]
    if action and action[2] then
        action[2](target.frame)
        return true
    end
    if face == "A" and target.noA then return false end
    if face == "A" and target.frame.Click then
        target.frame:Click()
        return true
    end
    return false
end

-- Returns true when the button was used.
local function press(button)
    -- The ForeverDex menu first, then a ForeverDex dialog.
    if PopupMenu.IsShown() then
        if button == "PADDUP" then PopupMenu.Move(-1)
        elseif button == "PADDDOWN" then PopupMenu.Move(1)
        elseif button == "PAD1" then PopupMenu.Pick()
        elseif button == "PAD2" then PopupMenu.Close()
        else return true end
        updateHints()
        return true
    end
    local popup = dialog()
    if popup then
        local index = (button == "PAD1" and 1) or (button == "PAD2" and 2) or (button == "PAD3" and 3)
        local control = index and dialogButton(popup, index)
        if control then control:Click() end
        return true
    end
    if DIRECTIONS[button] then
        refreshTargets()
        if current.direction then
            local nextFocus = current.direction(DIRECTIONS[button])
            refreshTargets()
            if nextFocus then setFocus(nextFocus) end
        else
            move(DIRECTIONS[button])
        end
        return true
    end
    local face = FACE[button]
    if face then
        refreshTargets()
        if face == "B" then
            if current.back then current.back() else options.close() end
        else
            act(face)
        end
        return true
    end
    if button == "PADLSHOULDER" or button == "PADRSHOULDER" then
        if options.tabs then options.tabs(button == "PADLSHOULDER" and -1 or 1) end
        return true
    end
    if button == "PADLTRIGGER" or button == "PADRTRIGGER" then
        if options.pages then options.pages(button == "PADLTRIGGER" and -1 or 1) end
        return true
    end
    local action = GetBindingAction and GetBindingAction(button)
    if action and BINDINGS[action] then
        SlashCmdList.FOREVERDEX(BINDINGS[action])
        return true
    end
    return false
end

input:SetScript("OnGamePadButtonDown", function(self, button)
    local used
    if button == FOCUS_BUTTON then
        focused, used = not focused, true
        self.held = nil
        PopupMenu.Close()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        if focused then
            refreshTargets()
            enter(focus)
        else
            leave(focus)
            marker:Hide()
            updateHints()
        end
    elseif focused then
        used = press(button)
    else
        used = false
    end
    -- What the window does not use goes on to the game (open the game menu, etc.).
    if not InCombatLockdown() and self.SetPropagateKeyboardInput then
        pcall(self.SetPropagateKeyboardInput, self, not used)
    end
    if not focused then return end
    if DIRECTIONS[button] then self.held, self.wait = button, REPEAT_DELAY end
    -- A click may open a card, close a dialog or change page: the frame follows.
    C_Timer.After(0, function() if capturing and focused then refreshTargets() end end)
end)
input:SetScript("OnGamePadButtonUp", function(self, button)
    if self.held == button then self.held = nil end
end)
-- Holding a direction repeats it.
input:SetScript("OnUpdate", function(self, elapsed)
    if not self.held then return end
    self.wait = self.wait - elapsed
    if self.wait <= 0 then
        self.wait = REPEAT_EVERY
        press(self.held)
    end
end)

-- Hints --------------------------------------------------------------------------------------

local function hint(button, label)
    return glyph(button) .. " " .. label
end

updateHints = function()
    if not capturing or not window then
        hints:Hide()
        return
    end
    local parts = {}
    local popup = dialog()
    if not focused then
        -- The character has the buttons: only the way back to the window is shown.
        hintText:SetText(hint(FOCUS_BUTTON, L.PAD_FOCUS_WINDOW))
        hints:SetWidth(hintText:GetStringWidth() + 30)
        hints:SetAlpha(0.7)
        hints:Show()
        return
    end
    hints:SetAlpha(1)
    if PopupMenu.IsShown() then
        parts = { hint("PAD1", L.PAD_SELECT), hint("PAD2", L.PAD_CLOSE) }
    elseif popup then
        for index, button in ipairs({ "PAD1", "PAD2", "PAD3" }) do
            local control = dialogButton(popup, index)
            if control and control:GetText() then parts[#parts + 1] = hint(button, control:GetText()) end
        end
    else
        local target = focus and findTarget(focus)
        if target then
            local text = target.frame.GetText and target.frame:GetText()
            local label = target.A and target.A[1] or (text and text ~= "" and text) or L.PAD_OPEN
            if not target.noA then parts[#parts + 1] = hint("PAD1", label) end
            if target.X then parts[#parts + 1] = hint("PAD3", target.X[1]) end
            if target.Y then parts[#parts + 1] = hint("PAD4", target.Y[1]) end
        end
        local backLabel = current and (current.backLabel or (current.back and L.PAD_BACK))
        parts[#parts + 1] = hint("PAD2", backLabel or L.PAD_CLOSE)
        if options.tabs then
            parts[#parts + 1] = glyph("PADLSHOULDER") .. glyph("PADRSHOULDER") .. " " .. (options.tabsLabel or L.PAD_TABS)
        end
        if options.pages then parts[#parts + 1] = glyph("PADLTRIGGER") .. glyph("PADRTRIGGER") .. " " .. L.PAD_PAGES end
        parts[#parts + 1] = hint(FOCUS_BUTTON, L.PAD_FOCUS_CHARACTER)
    end
    hintText:SetText(table.concat(parts, "     "))
    hints:SetWidth(hintText:GetStringWidth() + 30)
    hints:Show()
end

-- Public -------------------------------------------------------------------------------------

-- Several windows can be driven (the journal, the duel screen): the one shown last
-- has the buttons, and the previous one gets them back when it closes.
local attached = {} -- [frame] = opts
local stack = {}    -- shown windows, the last one on top

local function topWindow()
    for i = #stack, 1, -1 do
        if stack[i]:IsShown() then return stack[i] end
        table.remove(stack, i)
    end
end

local function update()
    local top = topWindow()
    if top ~= window then
        leave(focus)
        focus = nil
        window, options = top, top and attached[top]
        if window then
            hints:SetParent(window)
            hints:SetFrameStrata(window:GetFrameStrata())
            hints:ClearAllPoints()
            hints:SetPoint("TOP", window, "BOTTOM", 0, -(options.hintsOffset or 30))
        end
    end
    local on = window ~= nil and PopupMenu.GamepadInterface()
    -- Each opening of a window gives it the focus.
    if not capturing then focused = true end
    setCapture(on and true or false)
    if capturing then refreshTargets() end
end

-- frame: a window to drive. opts: mode() → name of its page now, close(), and
-- optionally tabs(step) with tabsLabel, pages(step), hintsOffset (room under the
-- window for its bottom tabs).
function Gamepad.Attach(frame, opts)
    attached[frame] = opts
    frame:HookScript("OnShow", function(self)
        for i = #stack, 1, -1 do
            if stack[i] == self then table.remove(stack, i) end
        end
        stack[#stack + 1] = self
        update()
    end)
    frame:HookScript("OnHide", function() update() end)
end

function Gamepad.RegisterPage(mode, provider)
    providers[mode] = provider
end

-- After a page changes (refresh, new page, opened card): the chosen element follows.
function Gamepad.Refresh()
    if capturing then refreshTargets() end
end

-- True while the window is driven by the controller (menus then open on their owner).
function Gamepad.Driving()
    return capturing
end

-- Controller turned on or off, combat starting or ending.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
pcall(events.RegisterEvent, events, "GAME_PAD_ACTIVE_CHANGED")
-- Forever: the interface switches between controller and mouse as the player uses them.
pcall(events.RegisterEvent, events, "INPUT_DEVICE_INTERFACE_TRANSITION")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        setCapture(false)
    else
        update()
    end
end)

-- Menu and dialogs change the hints while they are open.
PopupMenu.OnVisibilityChanged(function() if capturing then updateHints() end end)
hooksecurefunc("StaticPopup_Show", function() if capturing then C_Timer.After(0, updateHints) end end)
end)
