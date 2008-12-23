assert(LibStub, "LibQTip-1.0 requires LibStub")

local MAJOR, MINOR = "LibQTip-1.0", 6
local LibQTip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibQTip then return end -- No upgrade needed

-- Internal constants to tweak the layout
local TOOLTIP_PADDING = 10
local CELL_MARGIN = 3

local bgFrame = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = {left = 5, right = 5, top = 5, bottom = 5}
}

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

LibQTip.frameHeap = LibQTip.frameHeap or {}

local tipPrototype = LibQTip.tipPrototype
local tipMetatable = LibQTip.tipMetatable

local providerPrototype = LibQTip.providerPrototype
local providerMetatable = LibQTip.providerMetatable

local cellPrototype = LibQTip.cellPrototype
local cellMetatable = LibQTip.cellMetatable

local activeTooltips = LibQTip.activeTooltips
local tooltipHeap = LibQTip.tooltipHeap

local frameHeap = LibQTip.frameHeap

-- Tooltip private methods
local InitializeTooltip, FinalizeTooltip, ResetTooltipSize, ResizeColspans
local AcquireCell, ReleaseCell

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------
function LibQTip:Acquire(key, ...)
	if key == nil then
		error("attempt to use a nil key", 2)
	end
	local tooltip = activeTooltips[key]
	if not tooltip then
		tooltip = tremove(tooltipHeap) or setmetatable(CreateFrame("Frame", nil, UIParent), tipMetatable)
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
-- CellProvider and Cell
------------------------------------------------------------------------------
function providerPrototype:AcquireCell(tooltip)
	local cell = tremove(self.heap)
	if not cell then
		cell = setmetatable(CreateFrame("Frame", nil, tooltip), self.cellMetatable)
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
function InitializeTooltip(self, key)
	-- (Re)set frame settings
	self:SetBackdrop(bgFrame)
	self:SetBackdropColor(0.09, 0.09, 0.09)
	self:SetBackdropBorderColor(1, 1, 1)
	self:SetAlpha(0.9)
	self:SetScale(1.0)	
	self:SetFrameStrata("TOOLTIP")
	self:SetClampedToScreen(false)

	-- Our data
	self.key = key
	self.columns = self.columns or {}
	self.lines = self.lines or {}
	self.colspans = self.colspans or {}
	self.lineHeap = self.lineHeap or {}
	self.columnHeap = self.columnHeap or {}

	self.regularFont = GameTooltipText
	self.headerFont = GameTooltipHeaderText

	self.labelProvider = labelProvider

	self:SetScript('OnShow', ResizeColspans)

	ResetTooltipSize(self)
end

function tipPrototype:SetDefaultProvider(myProvider)
	if not myProvider then return end
	self.labelProvider = myProvider
end

function tipPrototype:GetDefaultProvider()
	return self.labelProvider
end

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
	local line = self.lineHeap[lineNum]
	if not line then
		line = CreateFrame("Frame", nil, self)		
		line.cells = {}
		self.lineHeap[lineNum] = line
	end
	return line
end

function tipPrototype:ReleaseLine(line)
	for i, cell in pairs(line.cells) do
		ReleaseCell(self, cell)
	end
	wipe(line.cells)
	line:ClearAllPoints()
	line:Hide()
end

function tipPrototype:AcquireColumn(colNum)
	local column = self.columnHeap[colNum]
	if not column then
		column = CreateFrame("Frame", nil, self)		
		self.columnHeap[colNum] = column
	end
	return column
end

function tipPrototype:ReleaseColumn(column)
	column:ClearAllPoints()
	column:Hide()
end

function tipPrototype:AddColumn(justification)
	justification = justification or "LEFT"
	checkJustification(justification, 2)
	local colNum = #self.columns + 1
	local column = self:AcquireColumn(colNum)
	column.justification = justification
	column.width = 0
	column:SetWidth(1)
	column:SetPoint("TOP", self)
	column:SetPoint("BOTTOM", self)
	if colNum > 1 then
		column:SetPoint("LEFT", self.columns[colNum-1], "RIGHT", CELL_MARGIN, 0)
		self.width = self.width + CELL_MARGIN
		self:SetWidth(self.width)
	else
		column:SetPoint("LEFT", self, "LEFT", TOOLTIP_PADDING, 0)
	end
	column:Show()
	self.columns[colNum] = column
	return colNum
end

function FinalizeTooltip(self)
	self:Clear()
	for i, column in ipairs(self.columns) do
		self:ReleaseColumn(column)
		self.columns[i] = nil
	end
end

function ResetTooltipSize(self)
	self.width = 2*TOOLTIP_PADDING + math.max(0, CELL_MARGIN * (#self.columns - 1))
	self.height = 2*TOOLTIP_PADDING
	self:SetWidth(self.width)
	self:SetHeight(self.height)
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
		self.width = self.width + width - column.width
		self:SetWidth(self.width)
		column.width = width
		column:SetWidth(width)			
	end
end

function ResizeColspans(self)
	if not self:IsShown() then return end
	local columns = self.columns
	for colRange, width in pairs(self.colspans) do
		local left, right = colRange:match("^(%d+)%-(%d+)$")
		left, right = tonumber(left), tonumber(right)
		for col = left, right-1 do 
			width = width - columns[col].width - CELL_MARGIN
		end
		EnlargeColumn(self, columns[right], width)
		self.colspans[colRange] = nil
	end
end

function AcquireCell(self, provider)
	local cell = provider:AcquireCell(self)
	cell:SetParent(self)
	cell:SetFrameLevel(self:GetFrameLevel()+1)	
	return cell
end

function ReleaseCell(self, cell)
	if cell and cell:GetParent() == self then
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
	if prevCell == false then
		error("overlapping cells at column "..colNum, 3)
	elseif prevCell then
		-- There is a cell here
		font = font or prevCell._font
		justification = justification or prevCell._justification
		colSpan = colSpan or prevCell._colSpan
		if provider == nil or prevCell._provider == provider then
			-- Reuse existing cell
			cell = prevCell
			provider = cell._provider
		else
			-- A new cell is required
			ReleaseCell(self, prevCell)
			cells[colNum] = nil
		end
	else
		-- Creating a new cell, use meaningful defaults
		provider = provider or self.labelProvider
		font = font or self.regularFont
		justification = justification or self.columns[colNum].justification or "LEFT"
		colSpan = colSpan or 1
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
		rightColNum = math.max(colNum, tooltipWidth + colSpan)
		-- Update colspan to its effective value
		colSpan = 1 + rightColNum - colNum
	end

	-- Cleanup colspans
	for i = colNum + 1, rightColNum do
		local cell = cells[i]
		if cell == false then
			error("overlapping cells at column "..i, 3)
		elseif cell then
			ReleaseCell(self, cell)
		end
		cells[i] = false
	end

	-- Create the cell and anchor it
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
		self.colspans[colRange] = math.max(self.colspans[colRange] or 0, width)
	else
		-- Enlarge the column and tooltip if need be
		EnlargeColumn(self, self.columns[colNum], width)
	end

	-- Enlarge the line and tooltip if need be
	if height > line.height then
		self.height = self.height + height - line.height
		self:SetHeight(self.height)
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
	local lineNum, colNum = CreateLine(self, self.regularFont, ...)
	ResizeColspans(self)
	return lineNum, colNum
end

function tipPrototype:AddHeader(...)
	local lineNum, colNum = CreateLine(self, self.headerFont, ...)
	ResizeColspans(self)
	return lineNum, colNum
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

	lineNum, colNum = _SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, select(i, ...))
	ResizeColspans(self)
	return lineNum, colNum
end

function tipPrototype:GetLineCount() return #self.lines end

function tipPrototype:GetColumnCount() return #self.columns end

------------------------------------------------------------------------------
-- "Smart" Anchoring
------------------------------------------------------------------------------
local function GetTipAnchor(frame)
	local x,y = frame:GetCenter()
	if not x or not y then return "TOPLEFT", "BOTTOMLEFT" end
	local hhalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or ""
	local vhalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM"
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
