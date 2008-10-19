assert(LibStub, "LibTooltip-1.0 requires LibStub")

local MAJOR, MINOR = "LibTooltip-1.0", 1
local Tooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if (not Tooltip) then return end -- No upgrade needed

Tooltip.frameMeta = Tooltip.frameMeta or {__index = CreateFrame("Frame")}
Tooltip.baseMeta = Tooltip.baseMeta or setmetatable({}, Tooltip.frameMeta)
Tooltip.tipMeta = Tooltip.tipMeta or {__index = Tooltip.baseMeta}

local frame
if not Tooltip.frame then
	local bgFrame = {
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeSize = 10,
		insets = {left = 2.5, right = 2.5, top = 2.5, bottom = 2.5}
	}

	frame = setmetatable(CreateFrame("Frame", nil, UIParent), Tooltip.tipMeta)
	frame:SetBackdrop(bgFrame)
	frame:SetBackdropColor(0, 0, 0)
	frame:SetBackdropBorderColor(1, 1, 1)
	frame:SetAlpha(0.75)
	Tooltip.frame = frame
end

Tooltip.lines = Tooltip.lines or {}
Tooltip.widths = Tooltip.width or {}
Tooltip.heap = Tooltip.heap or {}
Tooltip.curcol = Tooltip.curcol or 1
-- Do not assign this: Tooltip.curline = Tooltip.curline or nil

local lines = Tooltip.lines
local widths = Tooltip.widths
local heap = Tooltip.heap

-- Internal constant to tweak the layout
local TOOLTIP_PADDING = 10
local CELL_MARGIN = 3

-------------------------------
-- Library Utility Functions --
-------------------------------
local function Debug(msg)
	ChatFrame1:AddMessage("|cffff9933Debug:|r "..msg)
end

local function GetFrame(parent)
	local frame = tremove(heap)
	if frame then
		frame:SetParent(parent)
	else
		frame = CreateFrame("Frame", nil, parent)
	end
	return frame
end

local function RemoveFrame(frame)
	frame:Hide()
	frame:SetParent(nil)
	frame:ClearAllPoints()
	tinsert(heap, frame)
end

local function LineResize(self)
	if #self.columns > 0 then 
		local prev
		local lineWidth = -CELL_MARGIN
		local lineHeight = 0
		for idx,col in ipairs(self.columns) do
			col:ClearAllPoints()
			if prev then
				col:SetPoint("LEFT", prev, "RIGHT", CELL_MARGIN, 0)
			else
				col:SetPoint("LEFT", self, "LEFT", 0, 0)
			end
			
			local width, height = widths[idx], col.text:GetStringHeight()
			col:SetWidth(width)
			col:SetHeight(height)
			
			lineWidth = lineWidth + width + CELL_MARGIN
			lineHeight = math.max(lineHeight, height)
			
			prev = col
		end
		self:SetWidth(lineWidth)
		self:SetHeight(lineHeight)
	else
		self:SetWidth(0)
		self:SetHeight(0)
	end
end

---------------------------------------
-- Library Object Method Definitions --
---------------------------------------
local function AddCell(self, text, orient)
	local line = self.curline
	
	local column = GetFrame(line)	 
	tinsert(line.columns, column)
	 
	 local fontString = column.text
	 if not fontString then
		fontString = column:CreateFontString(nil, "ARTWORK", "GameTooltipText")
		fontString:SetAllPoints(column)
		column.text = fontString	
	 end
	
	fontString:SetText(text)
	fontString:SetJustifyH(orient or "LEFT")
	fontString:Show()
	
	widths[self.curcol] = math.max(widths[self.curcol] or 0, fontString:GetStringWidth())	
	fontString:SetWidth(widths[self.curcol])
	
	column:Show()
end

function Tooltip:AddLine(text, orient)
	local line = GetFrame(frame)
	line.columns = line.columns or {}
	line.Resize = LineResize
	tinsert(lines, line)

	self.curline = line
	self.curcol = 1
	
	AddCell(self, text, orient)
	
	line:Show()
end

function Tooltip:AddColumn(text, orient)
	if not self.curline then
		self:AddLine(text, orient)
	else
		self.curcol = self.curcol + 1 
	end
	AddCell(self, text, orient)
end

function Tooltip:ClearLines()
	for idx,line in ipairs(lines) do
		for idx2,col in ipairs(line.columns) do
			col.text:Hide()
			RemoveFrame(col)
			line.columns[idx2] = nil
		end
		lines[idx] = nil
		RemoveFrame(line)
	end
	self.curline = nil
	self.curcol = 1
	for k in pairs(widths) do
		widths[k] = nil
	end
end

-- Alias
Tooltip.ClearTooltip = Tooltip.ClearLines

function Tooltip:Show()
	local width, height = 0,0
	if #lines > 0 then
		height = -CELL_MARGIN
		local prev
		for idx,line in ipairs(lines) do
			line:ClearAllPoints()
			if prev then
				line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -CELL_MARGIN)
			else
				line:SetPoint("TOPLEFT", frame, "TOPLEFT", TOOLTIP_PADDING, -TOOLTIP_PADDING)
			end			
			line:Resize()
			width = math.max(width, line:GetWidth())
			height = height + line:GetHeight() + CELL_MARGIN
			prev = line
		end
	end
	frame:SetWidth(2*TOOLTIP_PADDING + width)
	frame:SetHeight(2*TOOLTIP_PADDING + height)
	frame:Show()
end

function Tooltip:Hide()
	frame:Hide()
	self:ClearLines()
end

function Tooltip:SetPoint(point, frame, relative, x, y)
	frame:SetPoint(point, frame, relative, x, y)
end
