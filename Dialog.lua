local _, ns = ...
ns.Module(function()
local PopupMenu, Gamepad = ns.PopupMenu, ns.Gamepad
local Dialog = {}
ns.Dialog = Dialog

-- ForeverDex confirmations -------------------------------------------------------
--
-- With the mouse interface, the confirmations are the game's own (StaticPopup). With
-- the controller interface they cannot be: the game runs the addon's answer, then
-- closes the window from that same addon code, and closing it hands the controller
-- back to the character: the game blocks it and blames the addon (ADDON_ACTION_FORBIDDEN
-- on SetPreferredGamepadInteractTarget). In that mode the same definitions
-- (StaticPopupDialogs: text, button1/2/3, OnAccept, OnCancel, OnAlt, timeout,
-- showAlert) are shown in this window of our own, outside the game's controller code.
-- Button 1 is A, button 2 is B (cancel), button 3 is X, as in the game's windows.

local WIDTH, PADDING, BUTTON_H, GAP = 380, 18, 22, 8

local frame = CreateFrame("Frame", "ForeverDexDialog", UIParent, "BackdropTemplate")
frame:SetWidth(WIDTH)
frame:SetPoint("TOP", UIParent, "TOP", 0, -135)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()

local alert = frame:CreateTexture(nil, "ARTWORK")
alert:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
alert:SetSize(36, 36)
alert:SetPoint("LEFT", PADDING + 4, 0)

local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
text:SetJustifyH("CENTER")
text:SetJustifyV("TOP")
text:SetWordWrap(true)
if text.SetMaxLines then text:SetMaxLines(0) end

local current -- { which, info, data, timer } of the question on screen

-- Hides the window, then gives the answer: an answer may ask a new question.
local function answer(handlerName, reason)
    local state = current
    current = nil
    if state and state.timer then state.timer:Cancel() end
    frame:Hide()
    local handler = state and state.info[handlerName]
    if handler then handler(frame, state.data, reason) end
end

local buttons = {}
local HANDLERS = { "OnAccept", "OnCancel", "OnAlt" }
for index = 1, 3 do
    local control = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    control:SetHeight(BUTTON_H)
    control:SetScript("OnClick", function()
        local handler = HANDLERS[index]
        if index == 1 and current and not current.info.OnAccept then handler = "OnButton1" end
        answer(handler, "clicked")
    end)
    buttons[index] = control
    frame["button" .. index] = control -- Gamepad.lua reads the buttons by index
end

-- Closed some other way (Escape, the combat closing everything): as the game does
-- for its windows, that is a refusal.
frame:SetScript("OnHide", function()
    if current then answer("OnCancel", "clicked") end
end)
tinsert(UISpecialFrames, frame:GetName())

-- Buttons in a row: 1, 3, then 2, so that cancelling stays at the end.
local function layout(info)
    local shown = {}
    for _, index in ipairs({ 1, 3, 2 }) do
        local control, label = buttons[index], info["button" .. index]
        control:SetShown(label ~= nil)
        if label then
            control:SetText(label)
            control:SetWidth(math.max(110, control:GetFontString():GetStringWidth() + 30))
            shown[#shown + 1] = control
        end
    end
    local total = (#shown - 1) * GAP
    for _, control in ipairs(shown) do total = total + control:GetWidth() end
    -- The window widens for long button labels (the border is about 12 wide per side).
    local width = math.max(WIDTH, total + 2 * (PADDING + 12))
    frame:SetWidth(width)
    local x = -total / 2
    for _, control in ipairs(shown) do
        control:ClearAllPoints()
        control:SetPoint("BOTTOMLEFT", frame, "BOTTOM", x, PADDING)
        x = x + control:GetWidth() + GAP
    end

    local left = info.showAlert and (PADDING + 44) or (PADDING + 8)
    alert:SetShown(info.showAlert and true or false)
    -- A fixed width (not two anchors): the text wraps and its height can be measured.
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", left, -PADDING - 6)
    text:SetWidth(width - left - PADDING - 8)
    text:SetHeight(0)
    local height = text:GetStringHeight() + BUTTON_H + 3 * PADDING + 12
    if info.showAlert then height = math.max(height, 36 + BUTTON_H + 3 * PADDING) end
    frame:SetHeight(height)
end

-- Same arguments as StaticPopup_Show(which, textArg1, textArg2, data).
function Dialog.Show(which, textArg1, textArg2, data)
    if not PopupMenu.GamepadInterface() then
        return StaticPopup_Show(which, textArg1, textArg2, data)
    end
    local info = StaticPopupDialogs[which]
    if not info then return end
    -- A new question replaces the one on screen, as the game's windows do.
    if current and current.timer then current.timer:Cancel() end
    current = { which = which, info = info, data = data }
    frame.which = which
    text:SetText(info.text:format(textArg1 or "", textArg2 or ""))
    layout(info)
    if info.timeout and info.timeout > 0 and C_Timer and C_Timer.NewTimer then
        local state = current
        state.timer = C_Timer.NewTimer(info.timeout, function()
            if current == state then answer("OnCancel", "timeout") end
        end)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
    frame:Show()
    frame:Raise()
    return frame
end

-- Same as StaticPopup_Visible: is this question on screen, in either window?
function Dialog.Visible(which)
    if current and current.which == which and frame:IsShown() then return true end
    return StaticPopup_Visible ~= nil and StaticPopup_Visible(which) ~= nil
end

-- The controller drives it like the other ForeverDex windows: A, B and X answer
-- (Gamepad.lua takes the dialog's buttons first), nothing to choose with the D-pad.
Gamepad.Attach(frame, { mode = function() return "dialog" end, close = function() frame:Hide() end, hintsOffset = 6 })
Gamepad.RegisterPage("dialog", function() return { targets = {} } end)
end)
