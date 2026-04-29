-- Libra Dropdown Module - Rewritten for WoW 12.0 MenuUtil API
-- Bridges the old UIDropDownMenu pattern to MenuUtil.CreateContextMenu
local Libra = LibStub("Libra")
local Type, Version = "Dropdown", 16
if Libra:GetModuleVersion(Type) >= Version then return end

Libra.modules[Type] = Libra.modules[Type] or {}

local Dropdown = Libra.modules[Type]
local objects = Dropdown.objects or {}
Dropdown.objects = objects

-- Prototypes
local Prototype = {}
local MenuPrototype = setmetatable({}, {__index = Prototype})
local FramePrototype = setmetatable({}, {__index = Prototype})

-- Metatables are finalized in the constructor once we can capture the
-- original frame __index so that WoW API methods (SetSize, etc.) remain
-- accessible through the chain:  frameMT -> FramePrototype -> Prototype -> <WoW frame methods>
local menuMT, frameMT
local function buildMetatables()
	if frameMT then return end
	local tmp = CreateFrame("Frame")
	local origIndex = getmetatable(tmp).__index
	-- Chain: FramePrototype falls back to original frame methods
	setmetatable(FramePrototype, {__index = function(t, k)
		local v = Prototype[k]
		if v ~= nil then return v end
		if type(origIndex) == "table" then
			return origIndex[k]
		elseif type(origIndex) == "function" then
			return origIndex(t, k)
		end
	end})
	setmetatable(MenuPrototype, {__index = function(t, k)
		local v = Prototype[k]
		if v ~= nil then return v end
		if type(origIndex) == "table" then
			return origIndex[k]
		elseif type(origIndex) == "function" then
			return origIndex(t, k)
		end
	end})
	frameMT = {__index = FramePrototype}
	menuMT = {__index = MenuPrototype}
end

-- ============================================================
-- Generation State
-- ============================================================
local generationItems = {} -- [level] = { info1, info2, ... }
local activeGenerationDropdown = nil
local activeMenuHandle = nil

-- ============================================================
-- Global Compatibility Shims
-- These replace the removed UIDropDownMenu API globals
-- ============================================================
UIDROPDOWNMENU_MENU_VALUE = nil
UIDROPDOWNMENU_MENU_LEVEL = 1
UIDROPDOWNMENU_MAXBUTTONS = 20
UIDROPDOWNMENU_MAXLEVELS = 3
UIDROPDOWNMENU_BUTTON_HEIGHT = 16
UIDROPDOWNMENU_BORDER_HEIGHT = 15

function UIDropDownMenu_CreateInfo()
return {}
end

function UIDropDownMenu_AddButton(info, level)
level = level or 1
if not generationItems[level] then
generationItems[level] = {}
end
local copy = {}
for k, v in pairs(info) do
copy[k] = v
end
tinsert(generationItems[level], copy)
end

function UIDropDownMenu_SetText(frame, text)
if frame and frame.Text then
frame.Text:SetText(text)
end
end

function UIDropDownMenu_SetWidth(frame, width, padding)
if frame and frame.SetDropdownWidth then
frame:SetDropdownWidth(width, padding)
end
end

function UIDropDownMenu_SetButtonWidth(frame, width)
end

function UIDropDownMenu_JustifyText(frame, justify)
if frame and frame.Text then
frame.Text:SetJustifyH(justify)
end
end

function UIDropDownMenu_GetCurrentDropDown()
return activeGenerationDropdown
end

function UIDropDownMenu_GetText(frame)
if frame and frame.Text then
return frame.Text:GetText()
end
end

function UIDropDownMenu_Refresh(frame, useValue, level)
end

function UIDropDownMenu_EnableDropDown(frame)
if frame and frame.Enable then frame:Enable() end
end

function UIDropDownMenu_DisableDropDown(frame)
if frame and frame.Disable then frame:Disable() end
end

function UIDropDownMenu_IsEnabled(frame)
return frame and frame.IsEnabled and frame:IsEnabled()
end

function UIDropDownMenu_StopCounting() end
function UIDropDownMenu_StartCounting() end
function UIDropDownMenu_CreateFrames() end

function CloseDropDownMenus(level)
if activeMenuHandle then
if activeMenuHandle.Close then
activeMenuHandle:Close()
end
activeMenuHandle = nil
end
end

function HideDropDownMenu(level)
CloseDropDownMenus(level)
end

function ToggleDropDownMenu(level, value, dropdown, anchor, xOffset, yOffset, menuList, ...)
if dropdown and dropdown.Toggle then
dropdown:Toggle(value, anchor, xOffset, yOffset, menuList, level, ...)
elseif dropdown and dropdown.ToggleMenu then
dropdown:ToggleMenu(value, anchor, xOffset, yOffset, menuList, level, ...)
end
end

-- ============================================================
-- Menu Generation Bridge
-- Converts collected UIDropDownMenu_AddButton info tables
-- into MenuUtil description elements
-- ============================================================
local function addElementToDescription(description, info, level, dropdown)
if not info.text and not info.isTitle then return end

local text = info.text or ""
if info.colorCode then
text = info.colorCode .. text .. FONT_COLOR_CODE_CLOSE
end

-- Title / section header
if info.isTitle then
description:CreateTitle(text)
return
end

local element

if info.notCheckable then
-- Plain button or submenu parent
local callback
if info.func and not info.disabled then
callback = function()
local mockSelf = {value = info.value}
info.func(mockSelf, info.arg1, info.arg2)
end
end
element = description:CreateButton(text, callback)
elseif info.isNotRadio then
-- Checkbox
element = description:CreateCheckbox(
text,
function()
local c = info.checked
if type(c) == "function" then return c(info) end
return c and true or false
end,
function()
if info.func then
local c = info.checked
if type(c) == "function" then c = c(info) end
local newState = not c
local mockSelf = {value = info.value, checked = newState}
info.func(mockSelf, info.arg1, info.arg2, newState)
end
end
)
else
-- Radio button
element = description:CreateRadio(
text,
function()
local c = info.checked
if type(c) == "function" then return c(info) end
return c and true or false
end,
function()
if info.func then
local mockSelf = {value = info.value}
info.func(mockSelf, info.arg1, info.arg2)
end
end
)
end

if not element then return end

if info.disabled then
element:SetEnabled(false)
end

-- Tooltip
if info.tooltipTitle or info.tooltipText then
element:SetTooltip(function(tooltip, elementDescription)
if info.tooltipTitle then
GameTooltip_SetTitle(tooltip, info.tooltipTitle)
end
if info.tooltipText then
GameTooltip_AddNormalLine(tooltip, info.tooltipText)
end
end)
end

-- Submenu: populate children if hasArrow is set
if info.hasArrow then
local childLevel = level + 1
generationItems[childLevel] = {}

local prevMenuValue = UIDROPDOWNMENU_MENU_VALUE
local prevMenuLevel = UIDROPDOWNMENU_MENU_LEVEL
UIDROPDOWNMENU_MENU_VALUE = info.value
UIDROPDOWNMENU_MENU_LEVEL = childLevel

if dropdown and dropdown.tier then
dropdown.tier[childLevel] = info.value
end

-- Call the appropriate populator for the submenu
if type(info.menuList) == "function" then
info.menuList(dropdown, childLevel)
elseif dropdown and dropdown.initialize then
dropdown.initialize(dropdown, childLevel, info.menuList)
end

-- Convert collected child items
local childItems = generationItems[childLevel]
if childItems then
for _, childInfo in ipairs(childItems) do
addElementToDescription(element, childInfo, childLevel, dropdown)
end
end

UIDROPDOWNMENU_MENU_VALUE = prevMenuValue
UIDROPDOWNMENU_MENU_LEVEL = prevMenuLevel
end

-- Keep menu open after click (for multi-select checkboxes)
if info.keepShownOnClick and element.SetResponse then
element:SetResponse(MenuResponse.Refresh)
end

return element
end

local function runGenerator(dropdown, owner, rootDescription)
wipe(generationItems)
generationItems[1] = {}
activeGenerationDropdown = dropdown
UIDROPDOWNMENU_MENU_LEVEL = 1
UIDROPDOWNMENU_MENU_VALUE = nil

if dropdown.tier then
wipe(dropdown.tier)
end

-- Call the old-style initialize to collect items
if dropdown.initialize then
dropdown.initialize(dropdown, 1)
end

-- Convert to MenuUtil descriptions
local items = generationItems[1]
if items then
for _, info in ipairs(items) do
addElementToDescription(rootDescription, info, 1, dropdown)
end
end

activeGenerationDropdown = nil
end

-- ============================================================
-- Shared Prototype
-- ============================================================
function Prototype:AddButton(info, level)
UIDropDownMenu_AddButton(info, level)
end

function Prototype:SetDisplayMode(mode)
self._displayMode = mode
end

-- ============================================================
-- Menu Prototype (context menus / menu bar menus)
-- ============================================================
function MenuPrototype:Toggle(value, anchorName, xOffset, yOffset, menuList, level, ...)
local anchor
if type(anchorName) == "string" then
if anchorName == "cursor" then
anchor = self
else
anchor = _G[anchorName] or self
end
elseif type(anchorName) == "table" then
anchor = anchorName
else
anchor = self
end

if menuList then
self._pendingMenuList = menuList
end

local dropdown = self
activeMenuHandle = MenuUtil.CreateContextMenu(anchor, function(ownerRegion, rootDescription)
if dropdown._pendingMenuList and dropdown.initialize then
wipe(generationItems)
generationItems[1] = {}
activeGenerationDropdown = dropdown
UIDROPDOWNMENU_MENU_LEVEL = 1
UIDROPDOWNMENU_MENU_VALUE = nil
if dropdown.tier then wipe(dropdown.tier) end
dropdown.initialize(dropdown, 1, dropdown._pendingMenuList)
local items = generationItems[1]
if items then
for _, info in ipairs(items) do
addElementToDescription(rootDescription, info, 1, dropdown)
end
end
activeGenerationDropdown = nil
dropdown._pendingMenuList = nil
else
runGenerator(dropdown, ownerRegion, rootDescription)
end
end)
end

MenuPrototype.ToggleMenu = MenuPrototype.Toggle

function MenuPrototype:Hide(level)
CloseDropDownMenus(level)
end

function MenuPrototype:Close()
CloseDropDownMenus()
end

function MenuPrototype:CloseMenus(level)
CloseDropDownMenus(level)
end

function MenuPrototype:HideMenu(level)
CloseDropDownMenus(level)
end

function MenuPrototype:IsShown()
return activeMenuHandle ~= nil
end

MenuPrototype.IsMenuShown = MenuPrototype.IsShown

function MenuPrototype:Rebuild(level) end
function MenuPrototype:RebuildMenu(level) end
function MenuPrototype:Refresh(useValue) end

function MenuPrototype:SetSelectedName(name, useValue) self._selectedName = name end
function MenuPrototype:SetSelectedValue(value, useValue) self._selectedValue = value end
function MenuPrototype:SetSelectedID(id, useValue) self._selectedID = id end
function MenuPrototype:GetSelectedName() return self._selectedName end
function MenuPrototype:GetSelectedValue() return self._selectedValue end
function MenuPrototype:GetSelectedID() return self._selectedID end

-- ============================================================
-- Frame Prototype (dropdown button for filters etc.)
-- ============================================================
function FramePrototype:SetDropdownWidth(width, padding)
padding = padding or 50
self:SetWidth(width + padding)
if self.Text then
self.Text:SetWidth(width - 25)
end
end

-- Alias for old callers using SetWidth(width, padding) on dropdown frames
local baseSetWidth = getmetatable(CreateFrame("Frame")).__index.SetWidth
function FramePrototype:SetWidth(width, padding)
if padding then
self:SetDropdownWidth(width, padding)
else
baseSetWidth(self, width)
end
end

function FramePrototype:SetButtonWidth(width) end

function FramePrototype:JustifyText(justify)
if self.Text then
self.Text:SetJustifyH(justify)
end
end

function FramePrototype:SetLabel(text)
if self.Label then
self.Label:SetText(text)
end
end

function FramePrototype:SetText(text)
if self.Text then
self.Text:SetText(text)
end
end

function FramePrototype:GetText()
if self.Text then
return self.Text:GetText()
end
end

function FramePrototype:Enable()
if self.Button then self.Button:Enable() end
if self.Text then self.Text:SetVertexColor(1, 1, 1) end
self._enabled = true
end

function FramePrototype:Disable()
if self.Button then self.Button:Disable() end
if self.Text then self.Text:SetVertexColor(0.5, 0.5, 0.5) end
self._enabled = false
end

function FramePrototype:IsEnabled()
return self._enabled ~= false
end

function FramePrototype:SetEnabled(enable)
if enable then
self:Enable()
else
self:Disable()
end
end

function FramePrototype:Toggle(value, anchorName, xOffset, yOffset, menuList, level, ...)
local dropdown = self
activeMenuHandle = MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
runGenerator(dropdown, ownerRegion, rootDescription)
end)
end

FramePrototype.ToggleMenu = FramePrototype.Toggle

function FramePrototype:IsMenuShown()
return activeMenuHandle ~= nil and activeGenerationDropdown == self
end

function FramePrototype:HideMenu(level) CloseDropDownMenus(level) end
function FramePrototype:CloseMenus(level) CloseDropDownMenus(level) end
function FramePrototype:Refresh() end
function FramePrototype:Rebuild() end
function FramePrototype:RebuildMenu() end

function FramePrototype:SetSelectedName(name) self._selectedName = name end
function FramePrototype:SetSelectedValue(value) self._selectedValue = value end
function FramePrototype:SetSelectedID(id) self._selectedID = id end
function FramePrototype:GetSelectedName() return self._selectedName end
function FramePrototype:GetSelectedValue() return self._selectedValue end
function FramePrototype:GetSelectedID() return self._selectedID end

-- ============================================================
-- Constructor
-- ============================================================
local function constructor(self, type, parent, name)
	buildMetatables()
	local dropdown
if type == "Menu" then
dropdown = setmetatable(CreateFrame("Frame"), menuMT)
dropdown._displayMode = "MENU"
dropdown.xOffset = 0
dropdown.yOffset = 0
elseif type == "Frame" then
name = name or Libra:GetWidgetName(self.name)
dropdown = setmetatable(CreateFrame("Button", name, parent), frameMT)
dropdown:SetSize(165, 32)
dropdown._enabled = true

-- Background textures (mimic old UIDropDownMenuTemplate)
local left = dropdown:CreateTexture(nil, "BACKGROUND")
left:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
left:SetTexCoord(0, 0.1953125, 0, 1)
left:SetSize(25, 64)
left:SetPoint("TOPLEFT", 0, 17)
dropdown.Left = left

local right = dropdown:CreateTexture(nil, "BACKGROUND")
right:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
right:SetTexCoord(0.8046875, 1, 0, 1)
right:SetSize(25, 64)
right:SetPoint("TOPRIGHT", 0, 17)
dropdown.Right = right

local middle = dropdown:CreateTexture(nil, "BACKGROUND")
middle:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
middle:SetTexCoord(0.1953125, 0.8046875, 0, 1)
middle:SetHeight(64)
middle:SetPoint("LEFT", left, "RIGHT")
middle:SetPoint("RIGHT", right, "LEFT")
dropdown.Middle = middle

-- Text
local text = dropdown:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
text:SetJustifyH("RIGHT")
text:SetPoint("LEFT", left, "RIGHT", 2, 2)
text:SetPoint("RIGHT", right, "LEFT", -14, 2)
text:SetWordWrap(false)
dropdown.Text = text

-- Arrow button
local button = CreateFrame("Button", nil, dropdown)
button:SetSize(24, 24)
button:SetPoint("RIGHT", 0, 2)
button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
button:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
button:SetScript("OnClick", function()
dropdown:Toggle()
end)
dropdown.Button = button

-- Click the frame itself to toggle
dropdown:SetScript("OnClick", function()
dropdown:Toggle()
end)

-- Label
local label = dropdown:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
dropdown.Label = label
dropdown.label = label

dropdown:SetDropdownWidth(115)
end

if dropdown then
objects[dropdown] = true
end
return dropdown
end

Libra:RegisterModule(Type, Version, constructor)
