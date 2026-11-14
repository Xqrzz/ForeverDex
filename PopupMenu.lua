local _, ns = ...
ns.Module(function()
local PopupMenu = {}
ns.PopupMenu = PopupMenu

-- Menus opened by ForeverDex (card and banner menus, dropdowns) ---------------------------
--
-- With the controller on, a Blizzard menu created by an addon cannot close: closing it
-- updates the controller bindings, a protected action, and the game blocks it and blames
-- the addon (ADDON_ACTION_FORBIDDEN on SetPreferredGamepadInteractTarget). In that mode
-- ForeverDex shows this small menu of its own instead; with the mouse it keeps the
-- game's menus. The generators are the same: they receive a root offering the few
-- methods ForeverDex uses (CreateTitle, CreateButton, CreateRadio, CreateDivider), and
-- items with SetEnabled and SetTooltip.

function PopupMenu.GamepadActive()
    if C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled() then return true end
    return GetCVarBool ~= nil and GetCVarBool("GamePadEnable") == true
end

-- The interface currently drawn for the controller. On Forever, the controller setting
-- stays on when the player takes the mouse again: only the interface style switches
-- (as EllesmereUI reads it). What the player sees (the gold frame, the button hints,
-- the game menu button) follows this; the menus keep the wider check above, since the
-- controller code of the game runs as soon as the setting is on.
function PopupMenu.GamepadInterface()
    local style, types = C_InputInterfaceStyle, Enum and Enum.InputDeviceInterfaceType
    if style and style.GetCurrentStyle and types and types.Gamepad then
        return style.GetCurrentStyle() == types.Gamepad
    end
    return PopupMenu.GamepadActive()
end

local ROW_H, PADDING, MIN_WIDTH = 20, 10, 140

local frame = CreateFrame("Frame", "ForeverDexPopupMenu", UIParent, "BackdropTemplate")
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropColor(0.06, 0.05, 0.04, 0.96)
frame:SetBackdropBorderColor(0.75, 0.62, 0.38)
-- Escape closes it, like the game's menus.
tinsert(UISpecialFrames, frame:GetName())

-- Gamepad.lua follows the menu: it drives it with the D-pad while it is open.
local visibilityListeners = {}
function PopupMenu.OnVisibilityChanged(listener)
    visibilityListeners[#visibilityListeners + 1] = listener
end
local function notify()
    for _, listener in ipairs(visibilityListeners) do listener(frame:IsShown()) end
end

-- A click anywhere else closes it.
frame:SetScript("OnShow", function(self)
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    notify()
end)
frame:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    self.owner = nil
    notify()
end)
frame:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
end)

local rows = {}
local function row(index)
    local line = rows[index]
    if line then return line end
    line = CreateFrame("Button", nil, frame)
    line:SetHeight(ROW_H)
    line:SetMotionScriptsWhileDisabled(true)
    line.highlight = line:CreateTexture(nil, "HIGHLIGHT")
    line.highlight:SetAllPoints()
    line.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    line.highlight:SetBlendMode("ADD")
    line.check = line:CreateTexture(nil, "ARTWORK")
    line.check:SetSize(16, 16)
    line.check:SetPoint("LEFT", 2, 0)
    line.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    line.label = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.label:SetJustifyH("LEFT")
    line.divider = line:CreateTexture(nil, "ARTWORK")
    line.divider:SetHeight(1)
    line.divider:SetPoint("LEFT", 4, 0)
    line.divider:SetPoint("RIGHT", -4, 0)
    line.divider:SetColorTexture(0.75, 0.62, 0.38, 0.5)
    line:SetScript("OnClick", function(self)
        local item = self.item
        if not item or not item.enabled or not item.action then return end
        frame:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
        item.action()
    end)
    line:SetScript("OnEnter", function(self)
        local item = self.item
        if not item or not item.tooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        item.tooltip(GameTooltip, item)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[index] = line
    return line
end

-- What a generator builds: a list of items.
local Item = {}
Item.__index = Item
function Item:SetEnabled(enabled) self.enabled = enabled and true or false end
function Item:SetTooltip(tooltip) self.tooltip = tooltip end

local function newRoot()
    local root = { items = {} }
    local function push(item)
        setmetatable(item, Item)
        if item.enabled == nil then item.enabled = true end
        root.items[#root.items + 1] = item
        return item
    end
    function root:CreateTitle(text) return push({ kind = "title", text = text, enabled = false }) end
    function root:CreateDivider() return push({ kind = "divider", enabled = false }) end
    function root:CreateButton(text, callback)
        return push({ kind = "button", text = text, action = callback and function() callback() end })
    end
    function root:CreateRadio(text, isSelected, select, value)
        return push({
            kind = "radio", text = text, checked = isSelected(value),
            action = function() select(value) end,
        })
    end
    return root
end

-- Row chosen with the D-pad, lit like a hovered one.
local selected
local function light(index)
    if selected and rows[selected] then rows[selected]:UnlockHighlight() end
    selected = index
    if index and rows[index] then rows[index]:LockHighlight() end
end

-- anchor: "below" (a dropdown), "beside" (next to its owner, with the controller) or
-- nil (at the cursor).
local function show(owner, generator, anchor)
    local anchorBelow = anchor == "below"
    local root = newRoot()
    generator(owner, root)
    if #root.items == 0 then return end
    local width = anchorBelow and owner:GetWidth() or MIN_WIDTH
    for index, item in ipairs(root.items) do
        local line = row(index)
        line.item = item
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", PADDING - 4, -(PADDING - 4) - (index - 1) * ROW_H)
        line:SetPoint("RIGHT", frame, "RIGHT", -(PADDING - 4), 0)
        line:SetEnabled(item.kind == "button" or item.kind == "radio")
        line.highlight:SetShown(item.enabled)
        line.check:SetShown(item.kind == "radio" and item.checked)
        line.divider:SetShown(item.kind == "divider")
        line.label:ClearAllPoints()
        line.label:SetPoint("LEFT", item.kind == "radio" and 20 or 4, 0)
        line.label:SetText(item.text or "")
        if item.kind == "title" then
            line.label:SetTextColor(1, 0.82, 0)
        elseif item.enabled then
            line.label:SetTextColor(1, 1, 1)
        else
            line.label:SetTextColor(0.5, 0.5, 0.5)
        end
        width = math.max(width, line.label:GetStringWidth() + (item.kind == "radio" and 20 or 4) + 2 * PADDING + 8)
        line:Show()
    end
    for index = #root.items + 1, #rows do rows[index]:Hide() end
    frame:SetSize(width, #root.items * ROW_H + 2 * (PADDING - 4))
    frame:ClearAllPoints()
    if anchorBelow then
        frame:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    elseif anchor == "beside" then
        frame:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    else
        frame:SetScale(1)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 4, y / scale + 4)
    end
    frame.owner = owner
    light(nil)
    frame:Show()
    -- Driven by the controller: the first choice is lit, ready for A.
    if ns.Gamepad and ns.Gamepad.Driving() then PopupMenu.Move(1) end
end

-- Controller driving (Gamepad.lua) ---------------------------------------------------------

function PopupMenu.IsShown() return frame:IsShown() end
function PopupMenu.Close() frame:Hide() end

-- Lights the next (step 1) or previous (-1) choice that can be picked.
function PopupMenu.Move(step)
    local count = 0
    for index, line in ipairs(rows) do
        if line:IsShown() then count = index end
    end
    if count == 0 then return end
    local index = selected or (step > 0 and 0 or count + 1)
    for _ = 1, count do
        index = (index - 1 + step) % count + 1
        local item = rows[index].item
        if item and item.enabled and item.action then
            light(index)
            return
        end
    end
end

function PopupMenu.Pick()
    local line = selected and rows[selected]
    if line then line:Click() end
end

-- Context menu at the cursor: the game's menu with the mouse, ForeverDex's own one
-- with the controller.
function PopupMenu.Open(owner, generator)
    if not PopupMenu.GamepadActive() and MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, generator)
    else
        show(owner, generator, ns.Gamepad and ns.Gamepad.Driving() and "beside" or nil)
    end
end

-- A game dropdown (DropdownButton) keeps its look; with the controller, a click opens
-- ForeverDex's menu under it instead of the game's. onPick runs after a choice, to
-- update the text the dropdown shows.
function PopupMenu.AttachDropdown(dropdown, generator, onPick)
    local original = dropdown:GetScript("OnMouseDown")
    dropdown:SetScript("OnMouseDown", function(self, ...)
        if not PopupMenu.GamepadActive() then
            if original then original(self, ...) end
            return
        end
        if frame:IsShown() and frame.owner == self then
            frame:Hide()
            return
        end
        PopupMenu.ShowBelow(self, generator, onPick)
    end)
end

-- The dropdown's menu, opened under it (also by Gamepad.lua when A is pressed on it).
function PopupMenu.ShowBelow(dropdown, generator, onPick)
    show(dropdown, function(owner, root)
        generator(owner, root)
        if onPick then
            for _, item in ipairs(root.items) do
                local action = item.action
                if action then item.action = function() action(); onPick() end end
            end
        end
    end, "below")
end
end)
