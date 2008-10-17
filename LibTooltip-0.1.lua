assert(LibStub, "LibTooltip-0.1 requires LibStub")

local MAJOR, MINOR = "LibTooltip-0.1", 1
local Tooltip, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if (not Tooltip) then return end -- No upgrade needed

local frameMeta = {__index = CreateFrame("Frame")}
local baseMeta = setmetatable({}, frameMeta)
local tipmeta = {__index = baseMeta}

Tooltip.frame = Tooltip.frame or setmetatable(CreateFrame("Frame", "Tooltip", UIParent), tipmeta)

local data = {
	lines = {},
	widths = {},
	heap = {},		-- Frame recycling
	curline = nil,
	prevline = nil,
	curcol = 1
}

-------------------------------
-- Library Utility Functions --
-------------------------------
local function Debug(msg)
	ChatFrame1:AddMessage("|cffff9933Debug:|r "..msg)
end


local function GetFrame(parent)
	local frame

	if (#data.heap > 0) then
		frame = data.heap[#data.heap]
		data.heap[#data.heap] = nil
		frame:SetParent(parent)
	else
		frame = CreateFrame("Frame", nil, parent, nil)
	end

	return frame
end


local function RemoveFrame(frame)
	data.heap[#data.heap + 1] = frame
	frame:Hide()
	frame:SetParent(nil)
end


local function LineResize(self)
	local prev = self
	local width = 0

	for _,col in ipairs(self.columns) do
		col:ClearAllPoints()
		col:SetPoint("LEFT", prev, "LEFT", 0, 0)
		col:Show()
		width = width + col.text:GetStringWidth()
		prev = col
	end
	self:SetWidth(width)
end


---------------------------------------
-- Library Object Method Definitions --
---------------------------------------
function Tooltip:AddLine(text, orient)
	if (data.curline) then data.prevline = data.curline end

	local line

	if (data.prevline) then
		line = GetFrame(data.prevline)
	else
		line = GetFrame(self.frame)
	end
	line.columns = {}
	data.curline = line
	data.curcol = 1

	local column = GetFrame(line)
	column.text = column:CreateFontString(nil, "ARTWORK", "GameTooltipText")

	if (not orient) then orient = "LEFT" end
	column.text:SetText(text)
	column.text:SetPoint(orient, column, orient, 5, -5)

	local width = column.text:GetStringWidth()

	if (#data.widths > data.curcol) then
		if (width > data.widths[data.curcol]) then data.widths[data.curcol] = width end
	else
		table.insert(data.widths, width)
	end
	table.insert(line.columns, column)
	line.Resize = LineResize
	table.insert(data.lines, line)
end


function Tooltip:AddColumn(text, orient)
	if (not data.curline) then
		self:AddLine(text, orient)
	else
		data.curcol = data.curcol + 1 end

	local column = GetFrame(data.curline)
	column.text = column:CreateFontString(nil, "ARTWORK", "GameTooltipText")

	if (not orient) then orient = "LEFT" end

	column.text:SetText(text)
	column.text:SetPoint(orient, column, orient, 5, -5)
	table.insert(data.curline.columns, column)

	local width = column.text:GetStringWidth()

	if (#data.widths > data.curcol) then
		if (width > data.widths[data.curcol]) then data.widths[data.curcol] = width end
	else
		table.insert(data.widths, width)
	end
end


function Tooltip:ClearLines()
	for idx,line in ipairs(data.lines) do
		RemoveFrame(line)

		for _,col in ipairs(line.columns) do
			col.text:SetText(nil)
			RemoveFrame(col)
		end
		line.columns = nil
		data.lines[idx] = nil
	end
	data.curline = nil
	data.prevline = nil
	data.curcol = 1
	data.widths = {}
	data.lines = {}
end


function Tooltip:ClearTooltip()
	self:ClearLines()
end


function Tooltip:Show()
	local bgFrame = {
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeSize = 10,
		insets = {left = 2.5, right = 2.5, top = 2.5, bottom = 2.5}
	}
	self.frame:SetBackdrop(bgFrame)
	self.frame:SetBackdropColor(0, 0, 0)
	self.frame:SetBackdropBorderColor(0, 0, 0)
	self.frame:SetAlpha(0.75)

	local height = 0

	for _,line in ipairs(data.lines) do
		line:ClearAllPoints()
		line:Resize()

		if (height == 0) then height = line.columns[1].text:GetStringHeight() end

		line:SetPoint("TOPLEFT", line:GetParent(), "BOTTOMLEFT", 0, -10)
		line:Show()

		for _,col in ipairs(line.columns) do
			col:Show()
		end
	end

	local width = 0

	for idx,val in ipairs(data.widths) do
		width = width + val
	end
	self.frame:SetWidth(width)
	self.frame:SetHeight((height + 3) * #data.lines)
	self.frame:Show()
end


function Tooltip:Hide()
	self:ClearTooltip()
	self.frame:Hide()
end


function Tooltip:SetPoint(point, frame, relative, x, y)
	self.frame:SetPoint(point, frame, relative, x, y)
end
