

assert(LibStub, "LibTooltip-1.0 requires LibStub")

local MAJOR, MINOR = "LibTooltip-1.0", 1
local Tooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if (not Tooltip) then return end -- No upgrade needed

local CreateNewTooltip, InitializeTooltip

-- Internal constants to tweak the layout
local TOOLTIP_PADDING = 10
local CELL_MARGIN = 3

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------

Tooltip.activeTooltips = Tooltip.activeTooltips or {}
Tooltip.tooltipHeap = Tooltip.tooltipHeap or {}

local activeTooltips = Tooltip.activeTooltips
local tooltipHeap = Tooltip.tooltipHeap

function Tooltip:Acquire(name, numColumns, ...)
	assert(not activeTips[name], "Tooltip "..name.." already in use.")
	local tooltip = tremove(tooltipHeap) or CreateNewTooltip()
	tooltip:Initialize(name, numColumns, ...)
	activeTooltips[name] = tooltip
	return tooltip
end

function Tooltip:Release(tooltip)
	local name = tooltip.name
	tooltip:Hide()
	tooltip:Clear()
	tinsert(tooltipHeap, tooltip)
	activeTooltips[name] = nil
end

function Tooltip:IterateTooltips()
	return pairs(activeTooltips)
end

------------------------------------------------------------------------------
-- Library Utility Functions
------------------------------------------------------------------------------

local function Debug(msg)
	ChatFrame1:AddMessage("|cffff9933Debug:|r "..msg)
end

Tooltip.frameHeap = Tooltip.frameHeap or {}
local frameHeap = Tooltip.frameHeap

local function AcquireFrame(parent)
	local frame = tremove(frameHeap)
	if frame then
		frame:SetParent(parent)
	else
		frame = CreateFrame("Frame", nil, parent)
	end
	return frame
end

local function ReleaseFrame(frame)
	frame:Hide()
	frame:SetParent(nil)
	frame:ClearAllPoints()
	tinsert(frameHeap, frame)
	return nil -- unneeded, but clearer
end

------------------------------------------------------------------------------
-- Tooltip prototype
------------------------------------------------------------------------------

local bgFrame = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeSize = 10,
	insets = {left = 2.5, right = 2.5, top = 2.5, bottom = 2.5}
}

Tooltip.frameMeta = Tooltip.frameMeta or {__index = CreateFrame("Frame")}
Tooltip.tipProto = Tooltip.tipProto or setmetatable({}, Tooltip.frameMeta)
Tooltip.tipMeta = Tooltip.tipMeta or {__index = Tooltip.tipProto}

local tipProto = Tooltip.tipProto
local tipMeta = tipMeta

-- Default fonts

function CreateNewTooltip()
	local self = setmetatable(CreateFrame("Frame", nil, UIParent), tipMeta)
	return self
end

function tipProto:Initialize(name, numColumns, ...)
	-- (Re)set frame settings
	self:SetBackdrop(bgFrame)
	self:SetBackdropColor(0, 0, 0)
	self:SetBackdropBorderColor(1, 1, 1)
	self:SetAlpha(0.75)
	self:SetScale(1.0)

	-- Our data
	self.name = name
	self.numColumns = numColumns
	self.columns = self.columns or {}
	self.lines = self.lines or {}
	
	self.width = 2*TOOLTIP_PADDING + (numColumns - 1) * CELL_MARGIN
	self.height = 2*TOOLTIP_PADDING

	-- Reset some attributes to the prototype value (defaults)
	self.regularFont = nil
	self.headerFont = nil

	-- Create and lay out the columns
	for i = 1, numColumns do
		local justification = select(i, ...) or "LEFT"
		assert(justification == "LEFT" or justification == "CENTER" or justification == "RIGHT", "LibTooltip:Acquire(): invalid justification for column "..i..": "..tostring(justification))
		local column = AcquireFrame(self)
		column.justification = justification
		column:SetWidth(0)
		column:SetPoint("TOP", self, "TOP", 0, -TOOLTIP_PADDING)
		column:SetPoint("BOTTOM", self, "BOTTOM", 0, TOOLTIP_PADDING)
		if i > 1 then
			column:SetPoint("LEFT", self.columns[i-1], "RIGHT", CELL_MARGIN, 0)
		else
			column:SetPoint("LEFT", self, "LEFT", TOOLTIP_PADDING, 0)
		end
		self.columns[i] = column
		column:Show()
	end
end

function tipProto:Clear()
	for i, column in ipairs(self.columns) do
		column:Hide()
		ReleaseFrame(column)
		self.columns[i] = nil
	end
	for i, line in ipairs(self.lines) do
		for j, cell in ipairs(line.cells) do
			cell:Hide()
			ReleaseGrame(cell)
			line.cells[j] = nil
		end
		line:Hide()
		ReleaseFrame(line)
		self.lines[i] = nil
	end
end

function tipProto:SetFont(font)
	assert(font.IsObjectType and font.IsObjectType('Font'))
	self.regularFont = font
end

function tipProto:SetHeaderFont(font)
	assert(font.IsObjectType and font.IsObjectType('Font'))
	self.headerFont = font
end

local function CreateLine(self, font, ...)	
	local line = AcquireFrame(self)
	local lineNum = #self.lines + 1
	line:SetPoint('LEFT', self, 'LEFT', TOOLTIP_PADDING, 0)
	line:SetPoint('RIGHT', self, 'RIGHT', -TOOLTIP_PADDING, 0)
	if lineNum > 1 then
		line:SetPoint('TOP', self.lines[lineNum-1], 'BOTTOM', 0, -CELL_MARGIN)
		self.height = self.height + CELL_MARGIN
		self:SetHeight(self.height)
	else
		line:SetPoint('TOP', self, 'TOP', 0, -TOOLTIP_PADDING)
	end
	self.lines[lineNum] = line	
	line.cells = line.cells or {}	
	line:SetHeight(0)
	line:Show()
	for colNum = 1, self.numColumns do
		self:SetCell(lineNum, colNum, select(colNum, ...), font)
	end
end

function tipProto:AddLine(...)
	return CreateLine(self, self.regularFont, ...)
end

function tipProto:AddHeader(...)
	return CreateLine(self, self.headerFont, ...)
end

local function CreateCell(self, line, column)
	local cell = AcquireFrame(self)
	local fontString = cell.fontString
	if not fontString then
		fontString = cell:CreateFontString(nil, "ARTWORK", font)
		fontString:SetAllPoints(cell)
		cell.fontString = fontString
	else
		fontString:SetFontObject(font)
	end
	cell:SetPoint("LEFT", column, "LEFT", 0, 0)
	cell:SetPoint("RIGHT", column, "RIGHT", 0, 0)
	cell:SetPoint("TOP", line, "TOP", 0, 0)
	cell:SetPoint("BOTTOM", line, "BOTTOM", 0, 0)
	return cell
end

function tipProto:SetCell(lineNum, colNum, value, font)
	local line = self.lines[line]
	local column = self.columns[column]
	assert(line, "tooltip:SetCell(): invalid line number: "..lineNum)
	assert(column, "tooltip:SetCell(): invalid column number: "..colNum)
	local cell = line.cells[colNum]
	if not cell then
		cell = CreateCell(self, line, column)
		line.cells[colNum] = cell
	end
	local fontString = cell.fontString
	fontString:SetJustifyH(column.justification)
	fontString:SetText(tostring(value or ""))
	
	-- Grows the tooltip as needed
	local oldWidth, oldHeight = column:GetWidth(), line:GetHeight()
	local width, height = fontString:GetStringWidth(), fontStrong:GetStringHeight()
	if width > oldWidth then
		column:SetWidth(width)
		self.width = self.width + width - oldWidth
		self:SetWidth(self.width)
	end
	if height > oldHeight then
		line:SetHeight(height)
		self.height = self.height + height - oldHeight
		self:SetHeight(self.height)
	end
end
