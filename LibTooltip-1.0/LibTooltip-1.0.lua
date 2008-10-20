

assert(LibStub, "LibTooltip-1.0 requires LibStub")

local MAJOR, MINOR = "LibTooltip-1.0", 1
local LibTooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if (not LibTooltip) then return end -- No upgrade needed

-- Internal constants to tweak the layout
local TOOLTIP_PADDING = 10
local CELL_MARGIN = 3

local bgFrame = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeSize = 10,
	insets = {left = 2.5, right = 2.5, top = 2.5, bottom = 2.5}
}

-- Tooltip private methods
local CreateTooltip, InitializeTooltip, FinalizeTooltip, ResetTooltipSize

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------

LibTooltip.activeTooltips = LibTooltip.activeTooltips or {}
LibTooltip.tooltipHeap = LibTooltip.tooltipHeap or {}

local activeTooltips = LibTooltip.activeTooltips
local tooltipHeap = LibTooltip.tooltipHeap

function LibTooltip:Acquire(name, numColumns, ...)
-- Tristanian: Refined with safeguards, feel free to remove if not really necessary
-- name must be string (?), should be decided
	assert(name and type(name)~= "number", "LibTooltip:Acquire(name, numColumns, ...): No 'name' provided or invalid type.")
	assert(not activeTooltips[name], "LibTooltip:Acquire(): Tooltip '"..tostring(name).."' already in use.")
	if not numColumns or type(numColumns)~= "number" or numColumns <= 0 then numColumns = 1 end
	local tooltip = tremove(tooltipHeap) or CreateTooltip()
	InitializeTooltip(tooltip, name, numColumns, ...)
	activeTooltips[name] = tooltip
	return tooltip
end

-- Tristanian: IsAcquired
-- name must be string (?), should be decided
function LibTooltip:IsAcquired(name)
	if activeTooltips[name] then
		return true
	else
		return false
	end
end

function LibTooltip:Release(tooltip)
 -- Tristanian: Supress errors for invalid tooltip frames passed
	if not tooltip then return end
	local name = tooltip.name
	tooltip:Hide()
	FinalizeTooltip(tooltip)
	tinsert(tooltipHeap, tooltip)
	activeTooltips[name] = nil
end

function LibTooltip:IterateTooltips()
	return pairs(activeTooltips)
end

------------------------------------------------------------------------------
-- Library Utility Functions
------------------------------------------------------------------------------

local function Debug(msg)
	ChatFrame1:AddMessage("|cffff9933Debug:|r "..msg)
end

LibTooltip.frameHeap = LibTooltip.frameHeap or {}
local frameHeap = LibTooltip.frameHeap

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
end

------------------------------------------------------------------------------
-- Tooltip prototype
------------------------------------------------------------------------------

LibTooltip.frameMeta = LibTooltip.frameMeta or {__index = CreateFrame("Frame")}
LibTooltip.tipProto = LibTooltip.tipProto or setmetatable({}, LibTooltip.frameMeta)
LibTooltip.tipMeta = LibTooltip.tipMeta or {__index = LibTooltip.tipProto}

local tipProto = LibTooltip.tipProto
local tipMeta = LibTooltip.tipMeta

function CreateTooltip()
	return setmetatable(CreateFrame("Frame", nil, UIParent), tipMeta)
end

function InitializeTooltip(self, name, numColumns, ...)
	-- (Re)set frame settings
	self:SetBackdrop(bgFrame)
	self:SetBackdropColor(0, 0, 0)
	self:SetBackdropBorderColor(1, 1, 1)
	self:SetAlpha(0.75)
	self:SetScale(1.0)
	self:SetFrameStrata("TOOLTIP")

	-- Our data
	self.name = name
	self.numColumns = numColumns
	self.columns = self.columns or {}
	self.lines = self.lines or {}

	self.regularFont = GameTooltipText
	self.headerFont = GameTooltipHeader

	-- Create and lay out the columns
	for i = 1, numColumns do
		local justification = select(i, ...) or "LEFT"
		assert(justification == "LEFT" or justification == "CENTER" or justification == "RIGHT", "LibTooltip:Acquire(): invalid justification for column "..i..": "..tostring(justification))
		local column = AcquireFrame(self)
		column.justification = justification
		column.width = 0
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
	ResetTooltipSize(self)
end

function FinalizeTooltip(self)
	self:Clear()
	for i, column in ipairs(self.columns) do
		column:Hide()
		ReleaseFrame(column)
		self.columns[i] = nil
	end
end

function ResetTooltipSize(self)
	self.width = 2*TOOLTIP_PADDING + (self.numColumns - 1) * CELL_MARGIN
	self.height = 2*TOOLTIP_PADDING
	self:SetWidth(self.width)
	self:SetHeight(self.height)
end

function tipProto:Clear()
	for i, line in ipairs(self.lines) do
		for j, cell in ipairs(line.cells) do
			cell.fontString:SetText(nil)
			cell.fontString:Hide()
			cell:Hide()
			ReleaseFrame(cell)
			line.cells[j] = nil
		end
		line:Hide()
		ReleaseFrame(line)
		self.lines[i] = nil
	end
	for i, column in ipairs(self.columns) do
		column.width = 0
		column:SetWidth(0)
	end
	ResetTooltipSize(self)
end

function tipProto:SetFont(font)
	assert(font.IsObjectType and font:IsObjectType("Font"), "tooltip:SetFont(): font must be a Font instance")
	self.regularFont = font
end

function tipProto:GetFont() return self.regularFont end

function tipProto:SetHeaderFont(font)
	assert(font.IsObjectType and font:IsObjectType("Font"), "tooltip:SetHeaderFont(): font must be a Font instance")
	self.headerFont = font
end

function tipProto:GetHeaderFont() return self.headerFont end

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
	line.height = 0
	line:SetHeight(0)
	line:Show()
	for colNum = 1, self.numColumns do
		self:SetCell(lineNum, colNum, select(colNum, ...), font, nil)
	end
	return lineNum
end

function tipProto:AddLine(...)
	return CreateLine(self, self.regularFont, ...)
end

function tipProto:AddHeader(...)
	return CreateLine(self, self.headerFont, ...)
end

local function CreateCell(self, line, column)
	local cell = AcquireFrame(self)
	if not cell.fontString then
		cell.fontString = cell:CreateFontString(nil, "ARTWORK")
		cell.fontString:SetAllPoints(cell)
	end
	cell:SetPoint("LEFT", column, "LEFT", 0, 0)
	cell:SetPoint("RIGHT", column, "RIGHT", 0, 0)
	cell:SetPoint("TOP", line, "TOP", 0, 0)
	cell:SetPoint("BOTTOM", line, "BOTTOM", 0, 0)
	cell.justification = nil
	return cell
end

function tipProto:SetCell(lineNum, colNum, value, font, justification)
	local line = self.lines[lineNum]
	local column = self.columns[colNum]
	assert(line, "tooltip:SetCell(): invalid line number: "..tostring(lineNum))
	assert(column, "tooltip:SetCell(): invalid column number: "..tostring(colNum))
	assert(justification == nil or justification == "LEFT" or justification == "CENTER" or justification == "RIGHT", "LibTooltip:SetCell(): invalid justification: "..tostring(justification))
	local cell = line.cells[colNum]
	local newcell = false

	if not cell then
		newcell = true
		cell = CreateCell(self, line, column)
		line.cells[colNum] = cell
	end

	local fontString = cell.fontString

	if font then
		assert(font.IsObjectType and font:IsObjectType("Font"), "tooltip:SetCell(): font must be nil or a Font instance")
		fontString:SetFontObject(font)
	elseif newcell then
		fontString:SetFontObject(GameTooltipText)
	end
	cell.justification = justification or cell.justification or column.justification
	fontString:SetJustifyH(cell.justification)
	fontString:SetText(tostring(value or " "))
	fontString:Show()

	local width, height = fontString:GetStringWidth(), fontString:GetStringHeight()

	-- Set the cell size (required to have the fontString displayed)
	cell:SetWidth(width)
	cell:SetHeight(height)
	cell:Show()

	-- Grows the tooltip as needed
	if width > column.width then
		self.width = self.width + width - column.width
		self:SetWidth(self.width)
		column.width = width
		column:SetWidth(width)
	end
	if height > line.height then
		self.height = self.height + height - line.height
		self:SetHeight(self.height)
		line.height = height
		line:SetHeight(height)
	end
end
