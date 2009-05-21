assert(LibStub, "LibQTip-1.0 requires LibStub")

local MAJOR, MINOR = "LibQTip-1.0", 13 -- the minor should be manually increased
local LibQTip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibQTip then return end -- No upgrade needed

------------------------------------------------------------------------------
-- Upvalued globals
------------------------------------------------------------------------------
local type = type
local select = select
local error = error
local pairs, ipairs = pairs, ipairs
local tonumber, tostring = tonumber, tostring
local min, max = math.min, math.max
local setmetatable = setmetatable
local tinsert, tremove = tinsert, tremove
local wipe = wipe

local CreateFrame = CreateFrame
local UIParent = UIParent

------------------------------------------------------------------------------
-- Internal constants to tweak the layout
------------------------------------------------------------------------------
local TOOLTIP_PADDING = 10
local CELL_MARGIN_H = 6
local CELL_MARGIN_V = 3

------------------------------------------------------------------------------
-- Tables and locals
------------------------------------------------------------------------------
LibQTip.frameMetatable = LibQTip.frameMetatable or {__index = CreateFrame("Frame")}

LibQTip.tipPrototype = LibQTip.tipPrototype or setmetatable({}, LibQTip.frameMetatable)
LibQTip.tipMetatable = LibQTip.tipMetatable or {__index = LibQTip.tipPrototype}

LibQTip.providerPrototype = LibQTip.providerPrototype or {}
LibQTip.providerMetatable = LibQTip.providerMetatable or {__index = LibQTip.providerPrototype}

LibQTip.cellPrototype = LibQTip.cellPrototype or setmetatable({}, LibQTip.frameMetatable)
LibQTip.cellMetatable = LibQTip.cellMetatable or { __index = LibQTip.cellPrototype }

LibQTip.activeTooltips = LibQTip.activeTooltips or {}
LibQTip.tooltipHeap = LibQTip.tooltipHeap or {}
LibQTip.lineHeap = LibQTip.lineHeap or {}
LibQTip.columnHeap = LibQTip.columnHeap or {}

LibQTip.layoutCleaner = LibQTip.layoutCleaner or CreateFrame('Frame')

local tipPrototype = LibQTip.tipPrototype
local tipMetatable = LibQTip.tipMetatable

local providerPrototype = LibQTip.providerPrototype
local providerMetatable = LibQTip.providerMetatable

local cellPrototype = LibQTip.cellPrototype
local cellMetatable = LibQTip.cellMetatable

local activeTooltips = LibQTip.activeTooltips
local tooltipHeap = LibQTip.tooltipHeap
local lineHeap = LibQTip.lineHeap or {}
local columnHeap = LibQTip.columnHeap or {}

local layoutCleaner = LibQTip.layoutCleaner

------------------------------------------------------------------------------
-- Tooltip private methods
------------------------------------------------------------------------------
local AcquireTooltip, InitializeTooltip, FinalizeTooltip, ResetTooltipSize, LayoutColspans
local AcquireCell, ReleaseCell

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------
--- Create or retrieve the tooltip with the given key. 
-- If additional arguments are passed, they are passed to :SetColumnLayout for the acquired tooltip.
-- @name LibQTip:Acquire(key[, numColumns, column1Justification, column2justification, ...])
-- @param key string or table - the tooltip key. Any value that can be used as a table key is accepted though you should try to provide unique keys to avoid conflicts. 
-- Numbers and booleans should be avoided and strings should be carefully chosen to avoid namespace clashes - no "MyTooltip" - you have been warned! 
-- @return tooltip Frame object - the acquired tooltip. 
-- @usage Acquire a tooltip with at least 5 columns, justification : left, center, left, left, left
-- <pre>local tip = LibStub('LibQTip-1.0'):Acquire('MyFooBarTooltip', 5, "LEFT", "CENTER")</pre>
function LibQTip:Acquire(key, ...)
	if key == nil then error("attempt to use a nil key", 2)	end
	local tooltip = activeTooltips[key]
	if not tooltip then
		tooltip = AcquireTooltip()
		InitializeTooltip(tooltip, key)
		activeTooltips[key] = tooltip
	end
	if select('#', ...) > 0 then
	  -- Here we catch any error to properly report it for the calling code
		local ok, msg = pcall(tooltip.SetColumnLayout, tooltip, ...)
		if not ok then error(msg, 2) end 
	end
	return tooltip
end

function LibQTip:IsAcquired(key)
	if key == nil then
		error("attempt to use a nil key", 2)
	end
	return not not activeTooltips[key]
end

function LibQTip:Release(tooltip)
	local key = tooltip and tooltip.key
	if not key or activeTooltips[key] ~= tooltip then return end
	tooltip:Hide()
	FinalizeTooltip(tooltip)
	tinsert(tooltipHeap, tooltip)
	activeTooltips[key] = nil
end

function LibQTip:IterateTooltips()
	return pairs(activeTooltips)
end

------------------------------------------------------------------------------
-- Dirty layout handler
------------------------------------------------------------------------------
layoutCleaner.registry = layoutCleaner.registry or {}

function layoutCleaner:RegisterForCleanup(tooltip)
	self.registry[tooltip] = true
	self:Show()
end

function layoutCleaner:CleanupLayouts()
	self:Hide()
	for tooltip in pairs(self.registry) do
		LayoutColspans(tooltip)
	end
	wipe(self.registry)
end

layoutCleaner:SetScript('OnUpdate', layoutCleaner.CleanupLayouts)

------------------------------------------------------------------------------
-- CellProvider and Cell
------------------------------------------------------------------------------
function providerPrototype:AcquireCell(tooltip)
	local cell = tremove(self.heap)
	if not cell then
		cell = setmetatable(CreateFrame("Frame", nil, UIParent), self.cellMetatable)
		if type(cell.InitializeCell) == 'function' then
			cell:InitializeCell()
		end
	end
	self.cells[cell] = true
	return cell
end

function providerPrototype:ReleaseCell(cell)
	if not self.cells[cell] then return end
	if type(cell.ReleaseCell) == 'function' then
		cell:ReleaseCell()
	end
	self.cells[cell] = nil
	tinsert(self.heap, cell)
end

function providerPrototype:GetCellPrototype()
	return self.cellPrototype, self.cellMetatable
end

function providerPrototype:IterateCells()
	return pairs(self.cells)
end

function LibQTip:CreateCellProvider(baseProvider)
	local cellBaseMetatable, cellBasePrototype
	if baseProvider and baseProvider.GetCellPrototype then
		cellBasePrototype, cellBaseMetatable = baseProvider:GetCellPrototype()
	else
		cellBaseMetatable = cellMetatable
	end
	local cellPrototype = setmetatable({}, cellBaseMetatable)
	local cellProvider = setmetatable({}, providerMetatable)
	cellProvider.heap = {}
	cellProvider.cells = {}
	cellProvider.cellPrototype = cellPrototype
	cellProvider.cellMetatable = { __index = cellPrototype }
	return cellProvider, cellPrototype, cellBasePrototype
end

------------------------------------------------------------------------------
-- Basic label provider
------------------------------------------------------------------------------
if not LibQTip.LabelProvider then
	LibQTip.LabelProvider, LibQTip.LabelPrototype = LibQTip:CreateCellProvider()
end

local labelProvider = LibQTip.LabelProvider
local labelPrototype = LibQTip.LabelPrototype

function labelPrototype:InitializeCell()
	self.fontString = self:CreateFontString()
	self.fontString:SetAllPoints(self)
	self.fontString:SetFontObject(GameTooltipText)
end

function labelPrototype:SetupCell(tooltip, value, justification, font, ...)
	local fs = self.fontString
	fs:SetFontObject(font or tooltip:GetFont())
	fs:SetJustifyH(justification)
	fs:SetText(tostring(value))
	fs:Show()
	return fs:GetStringWidth(), fs:GetStringHeight()
end

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------
local function checkFont(font, level, silent)
	if not font or type(font) ~= 'table' or type(font.IsObjectType) ~= 'function' or not font:IsObjectType("Font") then
		if silent then
			return false
		else
			error("font must be Font instance, not: "..tostring(font), level+1)
		end
	end
	return true
end

local function checkJustification(justification, level, silent)
	if justification ~= "LEFT" and justification ~= "CENTER" and justification ~= "RIGHT" then
		if silent then
			return false
		else
			error("invalid justification, must one of LEFT, CENTER or RIGHT, not: "..tostring(justification), level+1)
		end
	end
	return true
end

------------------------------------------------------------------------------
-- Tooltip prototype
------------------------------------------------------------------------------
function AcquireTooltip()
	local tip = tremove(tooltipHeap)
	if not tip then
		tip = CreateFrame("Frame", nil, UIParent)
		local scrollFrame = CreateFrame("ScrollFrame", nil, tip)
		scrollFrame:SetPoint("TOP", tip, "TOP", 0, -TOOLTIP_PADDING)
		scrollFrame:SetPoint("BOTTOM", tip, "BOTTOM", 0, TOOLTIP_PADDING)
		scrollFrame:SetPoint("LEFT", tip, "LEFT", TOOLTIP_PADDING, 0)
		scrollFrame:SetPoint("RIGHT", tip, "RIGHT", -TOOLTIP_PADDING, 0)
		tip.scrollFrame = scrollFrame
		local scrollChild = CreateFrame("Frame", nil, tip.scrollframe)
		scrollFrame:SetScrollChild(scrollChild)
		tip.scrollChild = scrollChild
		setmetatable(tip, tipMetatable)
	end
	return tip
end

function InitializeTooltip(self, key)
	-- (Re)set frame settings
	self:SetBackdrop(GameTooltip:GetBackdrop())
	self:SetBackdropColor(GameTooltip:GetBackdropColor())
	self:SetBackdropBorderColor(GameTooltip:GetBackdropBorderColor())
	self:SetScale(GameTooltip:GetScale())
	self:SetAlpha(0.9)
	self:SetFrameStrata("TOOLTIP")
	self:SetClampedToScreen(false)

	-- Our data
	self.key = key
	self.columns = self.columns or {}
	self.lines = self.lines or {}
	self.colspans = self.colspans or {}
	self.regularFont = GameTooltipText
	self.headerFont = GameTooltipHeaderText
	self.labelProvider = labelProvider

	-- Data depending on key
	lineHeap[key] = lineHeap[key] or {}
	columnHeap[key] = columnHeap[key] or {}

	-- Reset auto-hiding
	self:SetAutoHideDelay(nil)

	self:Hide()
	ResetTooltipSize(self)
end

function tipPrototype:SetDefaultProvider(myProvider)
	if not myProvider then return end
	self.labelProvider = myProvider
end

function tipPrototype:GetDefaultProvider() return self.labelProvider end

function tipPrototype:SetColumnLayout(numColumns, ...)
	if type(numColumns) ~= "number" or numColumns < 1  then
		error("number of columns must be a positive number, not: "..tostring(numColumns), 2)
	end
	for i = 1, numColumns do
		local justification = select(i, ...) or "LEFT"
		checkJustification(justification, 2)
		if self.columns[i] then
			self.columns[i].justification = justification
		else
			self:AddColumn(justification)
		end
	end
end

function tipPrototype:AcquireLine(lineNum)
	local line = lineHeap[self.key][lineNum]
	if not line then
		line = CreateFrame("Frame")
		line.cells = {}
		lineHeap[self.key][lineNum] = line
	end
	line:SetParent(self.scrollChild)
	return line
end

function tipPrototype:ReleaseLine(line)
	for i, cell in pairs(line.cells) do
		ReleaseCell(self, cell)
	end
	wipe(line.cells)
	line:ClearAllPoints()
	line:SetParent(nil)
	line:Hide()
end

function tipPrototype:AcquireColumn(colNum)
	local column = columnHeap[self.key][colNum]
	if not column then
		column = CreateFrame("Frame")
		columnHeap[self.key][colNum] = column
	end
	column:SetParent(self.scrollChild)
	return column
end

function tipPrototype:ReleaseColumn(column)
	column:ClearAllPoints()
	column:SetParent(nil)
	column:Hide()
end

function tipPrototype:AddColumn(justification)
	justification = justification or "LEFT"
	checkJustification(justification, 2)

	local colNum = #self.columns + 1
	local column = self:AcquireColumn(colNum)
	column:SetParent(self.scrollChild)
	column.justification = justification
	column.width = 0
	column:SetWidth(1)
	column:SetPoint("TOP", self.scrollChild)
	column:SetPoint("BOTTOM", self.scrollChild)

	if colNum > 1 then
		column:SetPoint("LEFT", self.columns[colNum - 1], "RIGHT", CELL_MARGIN_H, 0)
		self:SetTipSize(self.width + CELL_MARGIN_H, self.height)
	else
		column:SetPoint("LEFT", self.scrollChild)
	end
	column:Show()
	self.columns[colNum] = column
	return colNum
end

function tipPrototype:SetTipSize(width, height)
	self:SetHeight(2 * TOOLTIP_PADDING + height)
	self.scrollChild:SetHeight(height)
	self.height = height

	self:SetWidth(2 * TOOLTIP_PADDING + width)
	self.scrollChild:SetWidth(width)
	self.width = width
end

local sliderBackdrop = {
	["bgFile"] = [[Interface\Buttons\UI-SliderBar-Background]],
	["edgeFile"] = [[Interface\Buttons\UI-SliderBar-Border]],
	["tile"] = true,
	["edgeSize"] = 8,
	["tileSize"] = 8,
	["insets"] = {
		["left"] = 3,
		["right"] = 3,
		["top"] = 3,
		["bottom"] = 3,
	},
}

local function slider_OnValueChanged(self)
	self.scrollFrame:SetVerticalScroll(self:GetValue())
end

local function tooltip_OnMouseWheel(self, delta)
	local slider = self.slider
	local currentValue = slider:GetValue()
	local minValue,maxValue = slider:GetMinMaxValues()
	if delta < 0 and currentValue < maxValue then
		slider:SetValue(min(maxValue, currentValue + 10))
	elseif delta > 0 and currentValue > minValue then
		slider:SetValue(max(minValue, currentValue - 10))
	end
end

-- will resize the tooltip to fit the screen and show a scrollbar if needed
function tipPrototype:UpdateScrolling(maxheight)
	self:SetClampedToScreen(false)

	-- all data is in the tooltip; fix colspan width and prevent the layout cleaner from messing up the tooltip later
	LayoutColspans(self)
	layoutCleaner.registry[self] = nil
	local topside = self:GetTop()
	local bottomside = self:GetBottom()
	local screensize = UIParent:GetHeight()
	local tipsize = topside - bottomside

	-- if the tooltip would be too high, limit its height and show the slider
	if bottomside < 0 or topside > screensize or (maxheight and tipsize > maxheight) then
		local shrink = (bottomside < 0 and (5 - bottomside) or 0) + (topside > screensize and (topside - screensize + 5) or 0)
		if maxheight and tipsize - shrink > maxheight then
			shrink = tipsize - maxheight
		end
		self:SetHeight(2 * TOOLTIP_PADDING + self.height - shrink)
		self:SetWidth(2 * TOOLTIP_PADDING + self.width + 20)
		self.scrollFrame:SetPoint("RIGHT", self, "RIGHT", -(TOOLTIP_PADDING + 20), 0)
		if not self.slider then
			local slider = CreateFrame("Slider", nil, self)
			self.slider = slider
			slider:SetOrientation("VERTICAL")
			slider:SetPoint("TOPRIGHT", self, "TOPRIGHT", -TOOLTIP_PADDING, -TOOLTIP_PADDING)
			slider:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -TOOLTIP_PADDING, TOOLTIP_PADDING)
			slider:SetBackdrop(sliderBackdrop)
			slider:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Vertical]])
			slider:SetMinMaxValues(0, 1)
			slider:SetValueStep(1)
			slider:SetWidth(12)
			slider.scrollFrame = self.scrollFrame
			slider:SetScript("OnValueChanged", slider_OnValueChanged)
			slider:SetValue(0)
		end
		self.slider:SetMinMaxValues(0, shrink)
		self.slider:Show()
		self:EnableMouseWheel(true)
		self:SetScript("OnMouseWheel", tooltip_OnMouseWheel)
	else
		self:SetHeight(2 * TOOLTIP_PADDING + self.height)
		self:SetWidth(2 * TOOLTIP_PADDING + self.width)
		self.scrollFrame:SetPoint("RIGHT", self, "RIGHT", -TOOLTIP_PADDING, 0)
		if self.slider then
			self.slider:SetValue(0)
			self.slider:Hide()
			self:EnableMouseWheel(false)
			self:SetScript("OnMouseWheel", nil)
		end
	end
end

function FinalizeTooltip(self)
	self:Clear()
	if self.slider then
		self.slider:SetValue(0)
		self.slider:Hide()
		self.scrollFrame:SetPoint("RIGHT", self, "RIGHT", -TOOLTIP_PADDING, 0)
		self:EnableMouseWheel(false)
		self:SetScript("OnMouseWheel", nil)
	end
	for i, column in ipairs(self.columns) do
		self:ReleaseColumn(column)
		self.columns[i] = nil
	end
end

function ResetTooltipSize(self)
	self:SetTipSize(max(0, CELL_MARGIN_H * (#self.columns - 1)), 0)
end

function tipPrototype:Clear()
	for i, line in ipairs(self.lines) do
		self:ReleaseLine(line)
		self.lines[i] = nil
	end
	for i, column in ipairs(self.columns) do
		column.width = 0
		column:SetWidth(1)
	end
	wipe(self.colspans)
	ResetTooltipSize(self)
end

function tipPrototype:SetFont(font)
	checkFont(font, 2)
	self.regularFont = font
end

function tipPrototype:GetFont() return self.regularFont end

function tipPrototype:SetHeaderFont(font)
	checkFont(font, 2)
	self.headerFont = font
end

function tipPrototype:GetHeaderFont() return self.headerFont end

local function EnlargeColumn(self, column, width)
	if width > column.width then
		self:SetTipSize(self.width + width - column.width, self.height)

		column.width = width
		column:SetWidth(width)
	end
end

function LayoutColspans(self)
	local columns = self.columns
	for colRange, width in pairs(self.colspans) do
		local left, right = colRange:match("^(%d+)%-(%d+)$")
		left, right = tonumber(left), tonumber(right)
		for col = left, right-1 do
			width = width - columns[col].width - CELL_MARGIN_H
		end
		EnlargeColumn(self, columns[right], width)
	end
	wipe(self.colspans)
end

function AcquireCell(self, provider)
	local cell = provider:AcquireCell(self)
	cell:SetParent(self.scrollChild)
	cell:SetFrameLevel(self.scrollChild:GetFrameLevel() + 1)
	return cell
end

function ReleaseCell(self, cell)
	if cell and cell:GetParent() == self.scrollChild then
		cell:Hide()
		cell:SetParent(nil)
		cell:ClearAllPoints()
		cell._provider:ReleaseCell(cell)
		cell._provider, cell._font, cell._justification, cell._colSpan = nil
	end
end

local function _SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, ...)
	local line = self.lines[lineNum]
	local cells = line.cells

	-- Unset: be quick
	if value == nil then
		local cell = cells[colNum]
		if cell then
			for i = colNum, colNum + cell._colSpan - 1 do
				cells[i] = nil
			end
			ReleaseCell(self, cell)
		end
		return lineNum, colNum
	end

	-- Check previous cell
	local cell
	local prevCell = cells[colNum]
	if prevCell then
		-- There is a cell here
		font = font or prevCell._font
		justification = justification or prevCell._justification
		colSpan = colSpan or prevCell._colSpan
		-- Clear the currently marked colspan
		for i = colNum + 1, colNum + prevCell._colSpan - 1 do
			cells[i] = nil
		end
		if provider == nil or prevCell._provider == provider then
			-- Reuse existing cell
			cell = prevCell
			provider = cell._provider
		else
			-- A new cell is required
			ReleaseCell(self, prevCell)
			cells[colNum] = nil
		end
	elseif prevCell == nil then
		-- Creating a new cell, use meaningful defaults
		provider = provider or self.labelProvider
		font = font or self.regularFont
		justification = justification or self.columns[colNum].justification or "LEFT"
		colSpan = colSpan or 1
	else
		error("overlapping cells at column "..colNum, 3)
	end

	local tooltipWidth = #self.columns
	local rightColNum
	if colSpan > 0 then
		rightColNum = colNum + colSpan - 1
		if rightColNum > tooltipWidth then
			error("ColSpan too big, cell extends beyond right-most column", 3)
		end
	else
		-- Zero or negative: count back from right-most columns
		rightColNum = max(colNum, tooltipWidth + colSpan)
		-- Update colspan to its effective value
		colSpan = 1 + rightColNum - colNum
	end

	-- Cleanup colspans
	for i = colNum + 1, rightColNum do
		local cell = cells[i]
		if cell then
			ReleaseCell(self, cell)
		elseif cell == false then
			error("overlapping cells at column "..i, 3)
		end
		cells[i] = false
	end

	-- Create the cell
	if not cell then
		cell = AcquireCell(self, provider)
		cells[colNum] = cell
	end
	
	-- Anchor the cell
	cell:SetPoint("LEFT", self.columns[colNum])
	cell:SetPoint("RIGHT", self.columns[rightColNum])
	cell:SetPoint("TOP", line)
	cell:SetPoint("BOTTOM", line)

	-- Store the cell settings directly into the cell
	-- That's a bit risky but is really cheap compared to other ways to do it
	cell._provider, cell._font, cell._justification, cell._colSpan = provider, font, justification, colSpan

	-- Setup the cell content
	local width, height = cell:SetupCell(self, value, justification, font, ...)
	cell:Show()

	if colSpan > 1 then
		-- Postpone width changes until the tooltip is shown
		local colRange = colNum.."-"..rightColNum
		self.colspans[colRange] = max(self.colspans[colRange] or 0, width)
		layoutCleaner:RegisterForCleanup(self)
	else
		-- Enlarge the column and tooltip if need be
		EnlargeColumn(self, self.columns[colNum], width)
	end

	-- Enlarge the line and tooltip if need be
	if height > line.height then
		self:SetTipSize(self.width, self.height + height - line.height)

		line.height = height
		line:SetHeight(height)
	end

	if rightColNum < tooltipWidth then
		return lineNum, rightColNum+1
	else
		return lineNum, nil
	end
end

local function CreateLine(self, font, ...)
	if #self.columns == 0 then
		error("column layout should be defined before adding line", 3)
	end
	local lineNum = #self.lines + 1
	local line = self:AcquireLine(lineNum)
	line:SetPoint('LEFT', self.scrollChild)
	line:SetPoint('RIGHT', self.scrollChild)
	if lineNum > 1 then
		line:SetPoint('TOP', self.lines[lineNum-1], 'BOTTOM', 0, -CELL_MARGIN_V)
		self:SetTipSize(self.width, self.height + CELL_MARGIN_V)
	else
		line:SetPoint('TOP', self.scrollChild)
	end
	self.lines[lineNum] = line
	line.cells = line.cells or {}
	line.height = 0
	line:SetHeight(1)
	line:Show()

	local colNum = 1
	for i = 1, #self.columns do
		local value = select(i, ...)
		if value ~= nil then
			lineNum, colNum = _SetCell(self, lineNum, i, value, font, nil, 1, self.labelProvider)
		end
	end
	return lineNum, colNum
end

function tipPrototype:AddLine(...)
	return CreateLine(self, self.regularFont, ...)
end

function tipPrototype:AddHeader(...)
	return CreateLine(self, self.headerFont, ...)
end

function tipPrototype:SetCell(lineNum, colNum, value, ...)
	-- Mandatory argument checking
	if type(lineNum) ~= "number" then
		error("line number must be a number, not: "..tostring(lineNum), 2)
	elseif lineNum < 1 or lineNum > #self.lines then
		error("line number out of range: "..tostring(lineNum), 2)
	elseif type(colNum) ~= "number" then
		error("column number must be a number, not: "..tostring(colNum), 2)
	elseif colNum < 1 or colNum > #self.columns then
		error("column number out of range: "..tostring(colNum), 2)
	end

	-- Variable argument checking
	local font, justification, colSpan, provider
	local i, arg = 1, ...
	if arg == nil or checkFont(arg, 2, true) then
		i, font, arg = 2, ...
	end
	if arg == nil or checkJustification(arg, 2, true) then
		i, justification, arg = i+1, select(i, ...)
	end
	if arg == nil or type(arg) == 'number' then
		i, colSpan, arg = i+1, select(i, ...)
	end
	if arg == nil or type(arg) == 'table' and type(arg.AcquireCell) == 'function' then
		i, provider = i+1, arg
	end

	return _SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, select(i, ...))
end

function tipPrototype:GetLineCount() return #self.lines end

function tipPrototype:GetColumnCount() return #self.columns end

------------------------------------------------------------------------------
-- Auto-hiding feature
------------------------------------------------------------------------------
-- Script of the auto-hiding child frame
local function AutoHideTimerFrame_OnUpdate(self, elapsed)
	if MouseIsOver(self:GetParent()) or (self.alternateFrame and MouseIsOver(self.alternateFrame)) then
		self.elapsed = 0
	else
		self.elapsed = self.elapsed + elapsed
		if self.elapsed > self.delay then
			LibQTip:Release(self:GetParent())
		end
	end
end

-- Usage:
-- :SetAutoHideDelay(0.25) => hides after 0.25sec outside of the tooltip
-- :SetAutoHideDelay(0.25, someFrame) => hides after 0.25sec outside of both the tooltip and someFrame
-- :SetAutoHideDelay() => disable auto-hiding (default)
function tipPrototype:SetAutoHideDelay(delay, alternateFrame)
	delay = tonumber(delay) or 0
	local timerFrame = self.autoHideTimerFrame
	if delay > 0 then
		if not timerFrame then
			timerFrame = CreateFrame("Frame", nil, self)
			timerFrame:SetScript('OnUpdate', AutoHideTimerFrame_OnUpdate)
			self.autoHideTimerFrame = timerFrame
		end
		timerFrame.elapsed = 0
		timerFrame.delay = delay
		timerFrame.alternateFrame = alternateFrame
		timerFrame:Show()
	elseif timerFrame then
		timerFrame.alternateFrame = nil
		timerFrame:Hide()
	end
end

------------------------------------------------------------------------------
-- "Smart" Anchoring
------------------------------------------------------------------------------
local function GetTipAnchor(frame)
	local x,y = frame:GetCenter()
	if not x or not y then return "TOPLEFT", "BOTTOMLEFT" end
	local hhalf = (x > UIParent:GetWidth() * 2/3) and "RIGHT" or (x < UIParent:GetWidth() / 3) and "LEFT" or ""
	local vhalf = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
	return vhalf..hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP")..hhalf
end

function tipPrototype:SmartAnchorTo(frame)
	if not frame then
		error("Invalid frame provided.", 2)
	end
	self:ClearAllPoints()
	self:SetClampedToScreen(true)
	self:SetPoint(GetTipAnchor(frame))
end
