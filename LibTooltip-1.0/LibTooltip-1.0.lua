assert(LibStub, "LibTooltip-1.0 requires LibStub")
local MAJOR, MINOR = "LibTooltip-1.0", 1
local LibTooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibTooltip then return end -- No upgrade needed

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

LibTooltip.frameMetatable = LibTooltip.frameMetatable or {__index = CreateFrame("Frame")}

LibTooltip.tipPrototype = LibTooltip.tipPrototype or setmetatable({}, LibTooltip.frameMetatable)
LibTooltip.tipMetatable = LibTooltip.tipMetatable or {__index = LibTooltip.tipPrototype}

LibTooltip.providerPrototype = LibTooltip.providerPrototype or {}
LibTooltip.providerMetatable = LibTooltip.providerMetatable or {__index = LibTooltip.providerPrototype}

LibTooltip.cellPrototype = LibTooltip.cellPrototype or setmetatable({}, LibTooltip.frameMetatable)
LibTooltip.cellMetatable = LibTooltip.cellMetatable or { __index = LibTooltip.cellPrototype }

LibTooltip.activeTooltips = LibTooltip.activeTooltips or {}
LibTooltip.tooltipHeap = LibTooltip.tooltipHeap or {}

LibTooltip.frameHeap = LibTooltip.frameHeap or {}

local tipPrototype = LibTooltip.tipPrototype
local tipMetatable = LibTooltip.tipMetatable

local providerPrototype = LibTooltip.providerPrototype
local providerMetatable = LibTooltip.providerMetatable

local cellPrototype = LibTooltip.cellPrototype
local cellMetatable = LibTooltip.cellMetatable

local activeTooltips = LibTooltip.activeTooltips
local tooltipHeap = LibTooltip.tooltipHeap

local frameHeap = LibTooltip.frameHeap

-- Tooltip private methods
local InitializeTooltip, FinalizeTooltip, ResetTooltipSize, ResizeColspans
local AcquireCell, ReleaseCell

------------------------------------------------------------------------------
-- Public library API
------------------------------------------------------------------------------

function LibTooltip:Acquire(key, ...)
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

function LibTooltip:IsAcquired(key)
	if key == nil then
		error("attempt to use a nil key", 2)
	end
	return not not activeTooltips[key]
end

function LibTooltip:Release(tooltip)
	local key = tooltip and tooltip.key
	if not key or activeTooltips[key] ~= tooltip then return end
	tooltip:Hide()
	FinalizeTooltip(tooltip)
	tinsert(tooltipHeap, tooltip)
	activeTooltips[key] = nil
end

function LibTooltip:IterateTooltips()
	return pairs(activeTooltips)
end

------------------------------------------------------------------------------
-- Frame heap
------------------------------------------------------------------------------

local function AcquireFrame(parent)
	local frame = tremove(frameHeap) or CreateFrame("Frame")
	frame:SetParent(parent)
	return frame
end

local function ReleaseFrame(frame)
	frame:Hide()
	frame:SetParent(nil)
	frame:ClearAllPoints()
	tinsert(frameHeap, frame)
end

------------------------------------------------------------------------------
-- CellProvider and Cell
------------------------------------------------------------------------------

-- Provider prototype

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

-- Cell provider factory

function LibTooltip:CreateCellProvider(baseProvider)
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

if not LibTooltip.LabelProvider then
	LibTooltip.LabelProvider, LibTooltip.LabelPrototype = LibTooltip:CreateCellProvider()
end

local labelProvider = LibTooltip.LabelProvider
local labelPrototype = LibTooltip.LabelPrototype

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

local function checkFont(font, level)
	if not font or not font.IsObjectType or not font:IsObjectType("Font") then
		error("font must be Font instance, not: "..tostring(font), level+1)
	end
end

local function checkJustification(justification, method, level)
	if justification ~= "LEFT" and justification ~= "CENTER" and justification ~= "RIGHT" then
		error("invalid justification, must one of LEFT, CENTER or RIGHT, not: "..tostring(justification), level+1)
	end
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
	self.providers = self.providers or {}

	self.regularFont = GameTooltipText
	self.headerFont = GameTooltipHeaderText
	
	self:SetScript('OnShow', ResizeColspans)

	ResetTooltipSize(self)
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

function tipPrototype:AddColumn(justification)
	justification = justification or "LEFT"
	checkJustification(justification, 2)
	local colNum = #self.columns + 1
	local column = AcquireFrame(self)
	column.justification = justification
	column.width = 0
	column:SetWidth(0)
	column:SetPoint("TOP", self, "TOP", 0, -TOOLTIP_PADDING)
	column:SetPoint("BOTTOM", self, "BOTTOM", 0, TOOLTIP_PADDING)
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
		column:Hide()
		ReleaseFrame(column)
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
		for j, cell in ipairs(line.cells) do
			ReleaseCell(self, cell)
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
	for k in pairs(self.colspans) do
		self.colspans[k] = nil
	end
	for cell in self.providers do
		-- Shouldn't happen
		ReleaseCell(self, cell)
	end	
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
		local left, right = colRange:match("(%d)%-(%d)")
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
	self.providers[cell] = provider
	return cell
end

function ReleaseCell(self, cell)
	if cell and self.providers[cell] then
		cell:Hide()
		cell:SetParent(nil)
		cell:ClearAllPoints()
		self.providers[cell]:ReleaseCell(cell)
		self.providers[cell] = nil
	end
end

local function SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, ...)
	-- Line and column checks
	local line = self.lines[lineNum]
	local rightColNum = colNum+colSpan-1
	local leftColumn = self.columns[colNum]
	local rightColumn = self.columns[rightColNum]
	
	-- Release any existing cells, checking for overlaps
	-- We use "false" to indicate unavailable slots
	local cells = line.cells
	for i = colNum, rightColNum do
		local cell = cells[i]
		if cell == false then
			error("tooltip:SetCell(): overlapping cells at column "..i, 3)
		elseif cell then
			ReleaseCell(self, cell)
		end
		cells[i] = false
	end

	-- Create the cell and anchor it
	local cell = AcquireCell(self, provider)
	cell:SetPoint("LEFT", leftColumn, "LEFT", 0, 0)
	cell:SetPoint("RIGHT", rightColumn, "RIGHT", 0, 0)
	cell:SetPoint("TOP", line, "TOP", 0, 0)
	cell:SetPoint("BOTTOM", line, "BOTTOM", 0, 0)
	cells[colNum] = cell

	-- Setup the cell content
	local width, height = cell:SetupCell(tooltip, value, justification or leftColumn.justification, font, ...)

	-- Enforce cell size
	cell:SetWidth(width)
	cell:SetHeight(height)
	cell:Show()

	if colSpan > 1 then
		-- Postpone width changes until the tooltip is shown
		local colRange = colNum.."-"..rightColNum
		self.colspans[colRange] = math.max(self.colspans[colRange] or 0, width)
	else
		-- Enlarge the column and tooltip if need be
		EnlargeColumn(self, leftColumn, width)
	end

	-- Enlarge the line and tooltip if need be
	if height > line.height then
		self.height = self.height + height - line.height
		self:SetHeight(self.height)
		line.height = height
		line:SetHeight(height)
	end
end

local function CreateLine(self, font, ...)
	if select('#', ...) > #self.columns then
		error(select('#', ...).." values provided for only "..#self.columns.." columns", 3)
	end
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
	for colNum = 1, #self.columns do
			local value = select(colNum, ...)
			if value ~= nil then
				SetCell(self, lineNum, colNum, value, font, nil, 1, labelProvider)
			end
	end
	return lineNum
end

function tipPrototype:AddLine(...)
	local lineNum = CreateLine(self, self.regularFont, ...)
	ResizeColspans(self)
	return lineNum
end

function tipPrototype:AddHeader(...)
	local lineNum = CreateLine(self, self.headerFont, ...)
	ResizeColspans(self)
	return lineNum
end

function tipPrototype:SetCell(lineNum, colNum, value, font, justification, colSpan, provider, ...)
	-- Defaults arguments
	colSpan = colSpan or 1
	provider = provider or labelProvider
	font = font or self.regularFont

	-- Argument checking
	if type(provider.AcquireCell) ~= "function" then
		error("invalid cell provider", 2)
	elseif type(colSpan) ~= "number" or colSpan < 1 then
		error("colspan must be a positive number, not: "..tostring(colspan), 2)
	elseif type(lineNum) ~= "number" then
		error("line number must be a number, not: "..tostring(lineNum), 2)
	elseif lineNum < 1 or lineNum > #self.lines then
		error("line number out of range: "..tostring(lineNum), 2)
	elseif type(colNum) ~= "number" then
		error("column number must be a number, not: "..tostring(colNum), 2)
	elseif colNum < 1 or colNum > #self.columns then
		error("column number out of range: "..tostring(colNum), 2)
	elseif colNum + colSpan - 1 > #self.columns then
		error("colspan exceeds latest column: "..tostring(colSpan), 2)
	end
	checkFont(font, 2)
	if justification then
		checkJustification(justification, 2)
	end

	SetCell(self, lineNum, colNum, value, font, justification, colSpan, provider, ...)
	
	ResizeColspans(self)
end

function tipPrototype:GetLineCount() return #self.lines end

function tipPrototype:GetColumnCount() return #self.columns end

------------------------------------------------------------------------------
-- "Smart" Anchoring (work in progress)
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
		error("tooltip:SmartAnchorTo(frame): Invalid frame provided.", 2)
	end
	self:ClearAllPoints()
	self:SetClampedToScreen(true)
	self:SetPoint(GetTipAnchor(frame))
end
